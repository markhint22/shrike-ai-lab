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
# Safe to re-run: GET /monitors first and skip any name that's already registered.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_WATCH="$DIR/overnight-queue/deploy_watch.sh"

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

echo "register_monitors: $registered registered, $skipped already present, $failed failed"
[ "$failed" -eq 0 ]
