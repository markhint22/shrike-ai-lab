#!/usr/bin/env bash
# gitlark_control_consumer.sh — consumes gitlark's P5 conversational control-plane
# triggers (promote / pause_fleet) and actually executes them against this pipeline.
#
# Background: gitlark's chat assistant can, after an explicit confirm round-trip,
# request "promote" (ship develop->main) or "pause_fleet" on behalf of a user. It
# does this by writing ONE JSON line to `.gitlark/fleet-control.jsonl` in the
# TARGET repo's configured branch (default overnight/feature) via the GitHub API —
# a deliberate git-mediated trigger, not a new network-facing ops endpoint. See
# gitlark's backend/app/services/control_plane.py (_write_trigger_commit /
# _gated_trigger / promote / pause_fleet) for the producer side. Schema, one JSON
# object per line, newest last:
#   {"action": "promote"|"pause", "marker": "gitlark-control:<action>:<workspace_id>:<confirm_token>",
#    "requested_by": "<user_id>", "requested_at": "<ISO8601>", "workspace_id": "<uuid>"}
#
# This script is the CONSUMER: for each repo given, it fetches overnight/feature,
# reads any new lines in .gitlark/fleet-control.jsonl since the last run, and:
#   - action == "promote" -> calls promote_to_prod.sh --yes (the real gated
#     merge+smoke+migration+tag+push flow already lives there — this does NOT
#     reimplement it)
#   - action == "pause"   -> touches state/PAUSED (a MANUAL pause, no
#     state/deploy_pause marker — pause_guard.sh then correctly leaves it alone
#     until 90+ min instead of auto-clearing it like a deploy pause)
#   - anything else / malformed JSON -> logged and skipped, never crashes the run
#
# Idempotency: a per-repo line-count marker in state/gitlark_control_seen_<name>
# tracks how many lines of the JSONL have already been processed. Only lines
# beyond that count are new; the counter is advanced (persisted) after every
# line handled — including skipped/malformed ones — so nothing is ever
# reprocessed and a malformed line isn't retried forever. The file is append-only
# (newest last), so "already seen" == "line index <= stored count" holds across
# runs even as the file grows between them.
#
# Usage:
#   gitlark_control_consumer.sh repos/billwatch repos/gitlark ...
#   gitlark_control_consumer.sh --dry-run repos/billwatch     # log only, no side effects
#
# Cron (recommended, matches pause_guard.sh's cadence — see HUMAN_QUEUE.md):
#   */5 * * * *  cd ~/overnight-queue && ./gitlark_control_consumer.sh repos/* >> logs/gitlark_control.log 2>&1
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${OVERNIGHT_DIR:-$HOME/overnight-queue}"; STATE="$DIR/state"
mkdir -p "$STATE"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
CONTROL_FILE=".gitlark/fleet-control.jsonl"
CONTROL_BRANCH="overnight/feature"
DRY=0
args=()
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; *) args+=("$a");; esac; done
[ "${#args[@]}" -gt 0 ] || { echo "usage: gitlark_control_consumer.sh [--dry-run] repos/<name> ..."; exit 2; }

# shrike-notify dual-publish (no-op unless SHRIKE_NOTIFY_URL is configured — see
# shrike_notify_lib.sh for the topic taxonomy and env var docs).
# shellcheck source=./shrike_notify_lib.sh
[ -f "$HERE/shrike_notify_lib.sh" ] && source "$HERE/shrike_notify_lib.sh"

# alert <title> <tags> <body> <repo>
alert(){
  local title="$1" tags="$2" body="$3" repo_name="$4"
  [ "$DRY" -eq 1 ] && { echo "  [ntfy-dry-run] $title :: $body"; return 0; }
  curl -fsS --max-time 8 -H "Title: $title" -H "Tags: $tags" -d "$body" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  command -v shrike_notify_publish >/dev/null 2>&1 && shrike_notify_publish "fleet_${repo_name}_control" "$title" "$tags" "$body"
}

# parse_control_line <json-line> -> prints "action<TAB>marker" and exits 0,
# or exits 1 on anything that isn't a valid object with a non-empty "action".
parse_control_line() {
  python3 -c '
import json, sys
try:
    obj = json.loads(sys.argv[1])
    action = obj.get("action")
    marker = obj.get("marker", "")
    if not isinstance(action, str) or not action:
        sys.exit(1)
    sys.stdout.write(action + "\t" + str(marker))
except Exception:
    sys.exit(1)
' "$1"
}

for repo in "${args[@]}"; do
  name="$(basename "$repo")"
  [ -d "$repo/.git" ] || { echo "SKIP $name (no checkout)"; continue; }

  # bounded fetch so a stalled remote can't hang the whole run (same pattern as
  # promote_to_prod.sh's `timeout 30 git ... fetch`)
  timeout 30 git -C "$repo" fetch -q origin "$CONTROL_BRANCH" 2>/dev/null
  if ! git -C "$repo" rev-parse --verify -q "origin/$CONTROL_BRANCH" >/dev/null; then
    echo "SKIP $name (no $CONTROL_BRANCH)"; continue
  fi

  # safe no-op when the control file doesn't exist yet (matches the pattern
  # used elsewhere in this pipeline for optional/unconfigured integrations,
  # e.g. SHRIKE_NOTIFY_URL) — redirect stderr, don't treat as an error.
  content="$(git -C "$repo" show "origin/$CONTROL_BRANCH:$CONTROL_FILE" 2>/dev/null)"
  [ -n "$content" ] || { echo "$name: no $CONTROL_FILE (no-op)"; continue; }

  seenfile="$STATE/gitlark_control_seen_${name}"
  seen=0
  [ -f "$seenfile" ] && seen="$(cat "$seenfile" 2>/dev/null || echo 0)"
  case "$seen" in ''|*[!0-9]*) seen=0;; esac

  mapfile -t lines <<< "$content"
  total="${#lines[@]}"
  [ "$total" -le "$seen" ] && { echo "$name: nothing new ($seen/$total already processed)"; continue; }

  echo "$name: $((total - seen)) new control line(s) (seen $seen, total $total)"
  # NOTE: the seen-marker is only persisted when NOT in --dry-run. --dry-run is a
  # preview with zero side effects, so it must never advance the idempotency
  # counter — doing so would let a dry-run "trial" silently swallow a real
  # promote/pause request the next time this runs for real.
  mark_seen() { [ "$DRY" -eq 1 ] || echo "$1" > "$seenfile"; }
  for i in "${!lines[@]}"; do
    idx=$((i + 1))
    [ "$idx" -le "$seen" ] && continue
    line="${lines[$i]}"

    if [ -z "$line" ]; then
      mark_seen "$idx"; continue
    fi

    if ! parsed="$(parse_control_line "$line" 2>/dev/null)"; then
      echo "  ⚠️  $name: malformed control line #$idx — skipping: ${line:0:120}"
      mark_seen "$idx"
      continue
    fi
    action="${parsed%%$'\t'*}"
    marker="${parsed#*$'\t'}"

    case "$action" in
      promote)
        echo "  🚀 $name: gitlark-triggered PROMOTE ($marker)"
        if [ "$DRY" -eq 1 ]; then
          echo "  [dry-run] would run: $HERE/promote_to_prod.sh --yes $repo"
        else
          "$HERE/promote_to_prod.sh" --yes "$repo"
          alert "gitlark-triggered promote: $name" "rocket" "gitlark control-plane requested a promote for $name (develop -> main). marker=$marker" "$name"
        fi
        ;;
      pause)
        echo "  ⏸️  $name: gitlark-triggered PAUSE ($marker)"
        if [ "$DRY" -eq 1 ]; then
          echo "  [dry-run] would touch $STATE/PAUSED"
        else
          touch "$STATE/PAUSED"
          alert "gitlark-triggered fleet pause" "warning" "gitlark control-plane requested a fleet pause (via $name's workspace). marker=$marker" "$name"
        fi
        ;;
      *)
        echo "  ⚠️  $name: unrecognized control action '$action' ($marker) — skipping"
        ;;
    esac
    mark_seen "$idx"
  done
done
