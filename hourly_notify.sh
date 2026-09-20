#!/usr/bin/env bash
# hourly_notify.sh (cron, hourly) — a leaner, more-frequent companion to digest_notify.sh's
# 3h rollup. Added 2026-09-20 (explicit ask): tier-broken-out (T1-T5) landed/failed/reverted/
# no-op counts for the trailing 1h, the same per-item "what actually landed" detail
# digest_notify.sh shows, and feature-progress ("X/Y sub-items done") when relevant.
#
# Deliberately kept LEAN so it doesn't feel redundant with the 3h rollup when both land in the
# same hour: no token totals, no by-language/type pass-rate breakdown, no planning-activity
# section — digest_notify.sh (3h) stays the fuller, "everything" digest; this one is scoped to
# "what just happened." It also carries NO idle/paused/not-running heartbeat: digest_notify.sh
# already owns "is the box alive" (it fires unconditionally every 3h even when quiet), so an
# hourly heartbeat on top of that would just double the noise during a quiet stretch without
# adding any new information. If nothing landed in the last hour this script sends NOTHING —
# silence here is unambiguous (the 3h digest is the one guaranteed to explain a quiet box).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
SERVER="${NTFY_SERVER:-https://ntfy.sh}"
HOURS=1
[ -n "$TOPIC" ] || exit 0

send() {
  local title="$1" tags="$2" body="$3" attempt rc=0
  for attempt in 1 2 3; do
    if curl -fsS --max-time 8 -H "Title: $title" -H "Tags: $tags" -d "$body" "$SERVER/$TOPIC" >/dev/null 2>&1; then
      return 0
    fi
    rc=$?
    [ "$attempt" -lt 3 ] && sleep 2
  done
  echo "$(date '+%Y-%m-%d %H:%M:%S') send() FAILED after 3 attempts (curl rc=$rc): title='hourly digest'" >&2
  return 1
}

# 2026-09-20: a terse one-liner ($_ONE), sourced from the SAME outcomes.jsonl rows the tier
# breakdown below already groups by (ovn_tier_stats.py's own --oneline mode) — so this can
# never disagree with the table it sits next to, unlike digest_notify.sh's old header total
# (see that script's own 2026-09-20 fix comment for the bug this avoids repeating here).
_ONE="$(python3 "$DIR/scripts/ovn_tier_stats.py" "$HOURS" --oneline 2>/dev/null)"
_TIERS="$(python3 "$DIR/scripts/ovn_tier_stats.py" "$HOURS" 2>/dev/null)"
_LANDED_DETAIL="$(python3 "$DIR/scripts/ovn_landed_detail.py" "$HOURS" --max-per-repo 2 --max-total 8 2>/dev/null)"
_FEAT="$(OVN_QUEUE_DIR="$DIR" python3 "$DIR/scripts/ovn_feature_groups.py" --digest "$HOURS" --max-total 4 2>/dev/null)"

# nothing at all happened this hour -> send nothing (see header: this is fine, not ambiguous)
if [ -z "$_TIERS" ] && [ -z "$_LANDED_DETAIL" ] && [ -z "$_FEAT" ]; then
  exit 0
fi

# 2026-09-20: terse summary line goes FIRST (was previously implicit only in the tier table
# further down) — someone should be able to read just the title + this line and get the
# gist; the tier/detail/feature sections below are for digging in.
body="Overnight queue · last ~${HOURS}h ($(date '+%a %H:%M'))"
[ -n "$_ONE" ] && body="$body

$_ONE"
[ -n "$_TIERS" ] && body="$body

$_TIERS"
[ -n "$_LANDED_DETAIL" ] && body="$body

$_LANDED_DETAIL"
[ -n "$_FEAT" ] && body="$body

$_FEAT"
body="$body

(Fuller breakdown — tokens, by-language pass-rate, planning activity — every 3h.)"

send "Overnight queue — hourly" "hourglass_flowing_sand" "$body"
