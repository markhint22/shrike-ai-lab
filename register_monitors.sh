#!/usr/bin/env bash
# register_monitors.sh — idempotently register the fleet's live HTTP surfaces as
# shrike-monitor monitors, so shrike-monitor becomes a second, independent uptime
# signal alongside deploy_watch.sh's own Railway/Vercel CLI checks (which read
# deploy *build* status, not live HTTP reachability).
#
# Source of truth for WHICH surfaces to register: overnight-queue/deploy_watch.sh's
# own SURFACES table (key|repo|label|provider|target|health_url|fleet_active) — the
# same list deploy_watch already polls, so the two never drift apart. Rows for
# task-manager-platform and social-media-manager (Ripple) are skipped: both were
# discontinued 2026-09-09 per CLAUDE.md and are intentionally excluded from every
# fleet integration, this one included. That leaves exactly 7 live surfaces:
#   billwatch backend + frontend, chickadee backend + frontend,
#   gitlark backend + frontend, and the shrike-labs-website frontend.
#
# No-op unless SHRIKE_MONITOR_URL is configured (production secrets for
# shrike-monitor/shrike-notify haven't been provisioned yet — see HUMAN_QUEUE.md).
#
# `--heartbeats` additionally registers one HEARTBEAT (dead-man's-switch) monitor per pipeline job
# (branch_hygiene / reconcile_branches / promote_to_prod). The ping token is shown by shrike-monitor
# exactly once, so the resulting ping URLs are written (mode 600) to state/heartbeat_urls.env, which
# shrike_monitor_heartbeat() in shrike_notify_lib.sh reads. A monitor that already exists is left alone
# (its token cannot be re-read: delete it in shrike-monitor and re-run to re-issue).
#
# Safe to re-run: GET /monitors first and skip any name that's already registered.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 2026-09-30: lives next to deploy_watch.sh inside the pipeline dir (was one level up, which left a broken duplicate on the box)
DEPLOY_WATCH="$DIR/deploy_watch.sh"; [ -f "$DEPLOY_WATCH" ] || DEPLOY_WATCH="$DIR/overnight-queue/deploy_watch.sh"

if [ -z "${SHRIKE_MONITOR_URL:-}" ]; then
  echo "SHRIKE_MONITOR_URL not set — nothing to do (no-op)."
  exit 0
fi
[ -f "$DEPLOY_WATCH" ] || { echo "FATAL: can't find $DEPLOY_WATCH to read the SURFACES table from" >&2; exit 1; }

MURL="${SHRIKE_MONITOR_URL%/}"
hdr=(-H "Content-Type: application/json")
[ -n "${SHRIKE_MONITOR_TOKEN:-}" ] && hdr+=(-H "Authorization: Bearer ${SHRIKE_MONITOR_TOKEN}")

DISCONTINUED_REPOS="task-manager-platform social-media-manager"
is_discontinued(){ local r="$1" d; for d in $DISCONTINUED_REPOS; do [ "$r" = "$d" ] && return 0; done; return 1; }

# Pull the SURFACES heredoc-style block straight out of deploy_watch.sh (between
# the `SURFACES="` line and the closing `"` line) so this script can never drift
# from the list deploy_watch.sh itself actually polls.
WANT_HB=0; [ "${1:-}" = "--heartbeats" ] && WANT_HB=1
SURFACES="$(sed -n '/^SURFACES="$/,/^"$/p' "$DEPLOY_WATCH" | sed '1d;$d')"
[ -n "$SURFACES" ] || { echo "FATAL: couldn't extract SURFACES table from $DEPLOY_WATCH" >&2; exit 1; }

existing="$(curl -fsS --max-time 8 "${hdr[@]}" "$MURL/monitors" 2>/dev/null)"
existing_names="$(printf '%s' "${existing:-[]}" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    data = []
for m in data:
    print(m.get("name", ""))
' 2>/dev/null)"

registered=0; skipped=0; failed=0
while IFS='|' read -r key repo label provider target health fleet; do
  [ -z "${key// /}" ] && continue
  is_discontinued "$repo" && { echo "skip (discontinued repo $repo): $label"; continue; }
  name="$label"
  if printf '%s\n' "$existing_names" | grep -qxF "$name"; then
    echo "skip (already registered): $name"
    skipped=$((skipped + 1))
    continue
  fi
  payload="$(python3 -c 'import json, sys; print(json.dumps({"name": sys.argv[1], "type": "http", "url": sys.argv[2]}))' "$name" "$health")"
  if curl -fsS --max-time 8 "${hdr[@]}" -d "$payload" "$MURL/monitors" >/dev/null 2>&1; then
    echo "registered: $name -> $health"
    registered=$((registered + 1))
  else
    echo "FAILED to register: $name -> $health" >&2
    failed=$((failed + 1))
  fi
done <<< "$SURFACES"

if [ "$WANT_HB" = 1 ]; then
  HB_FILE="${SHRIKE_HEARTBEAT_FILE:-$DIR/state/heartbeat_urls.env}"
  mkdir -p "$(dirname "$HB_FILE")"
  # job|monitor name|interval_seconds|grace_seconds  (hygiene hourly, reconcile every ~20min, promote daily)
  for row in "BRANCH_HYGIENE|fleet-branch-hygiene|3600|3600" "RECONCILE|fleet-reconcile-branches|1800|1800" "PROMOTE|fleet-promote-to-prod|86400|10800"; do
    IFS='|' read -r job hname hint hgrace <<< "$row"
    if printf '%s\n' "$existing_names" | grep -qxF "$hname"; then echo "skip (already registered): $hname"; continue; fi
    payload="$(python3 -c 'import json, sys; print(json.dumps({"name": sys.argv[1], "type": "heartbeat", "interval_seconds": int(sys.argv[2]), "grace_seconds": int(sys.argv[3])}))' "$hname" "$hint" "$hgrace")"
    resp="$(curl -fsS --max-time 8 "${hdr[@]}" -d "$payload" "$MURL/monitors" 2>/dev/null)" || { echo "FAILED to register: $hname" >&2; failed=$((failed + 1)); continue; }
    ping="$(printf '%s' "$resp" | python3 -c 'import sys, json; d = json.load(sys.stdin); print("%s/heartbeat/%s?token=%s" % (sys.argv[1], d["id"], d["ping_token"]))' "$MURL" 2>/dev/null)"
    if [ -z "$ping" ]; then echo "FAILED to parse ping token for $hname" >&2; failed=$((failed + 1)); continue; fi
    ( umask 077; grep -v "^SHRIKE_HEARTBEAT_URL_${job}=" "$HB_FILE" 2>/dev/null > "$HB_FILE.tmp"; echo "SHRIKE_HEARTBEAT_URL_${job}=$ping" >> "$HB_FILE.tmp"; mv "$HB_FILE.tmp" "$HB_FILE" )
    echo "registered heartbeat: $hname (ping URL stored in $HB_FILE)"
    registered=$((registered + 1))
  done
fi

echo "register_monitors: $registered registered, $skipped already present, $failed failed"
[ "$failed" -eq 0 ]
