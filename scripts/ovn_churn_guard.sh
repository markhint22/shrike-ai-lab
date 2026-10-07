#!/usr/bin/env bash
# ovn_churn_guard.sh - cron wrapper for ovn_churn_guard.py (fleet churn-loop guard, 2026-10-07). See the .py header for the rule.
# Takes a bounded-wait lock (scripts/lib_lock.sh; mkdir-lock fallback when flock is missing), runs the python pass, ALWAYS exits 0
# (infrastructure trouble = a log line and no change). Kill switch: OVN_CHURN_GUARD=off. DRY_RUN=1 = print only.
# Cron line (shipped, NOT installed): scripts/cron.txt.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
STATE="${OVN_STATE_DIR:-$OVN/state}"; mkdir -p "$STATE" "$OVN/logs" 2>/dev/null
LOGF="${OVN_CHURN_LOG:-$OVN/logs/churn_guard.log}"
exec >>"$LOGF" 2>&1 || true
[ "${OVN_CHURN_GUARD:-on}" = "off" ] && { echo "$(date '+%F %T') [churn-guard] disabled (OVN_CHURN_GUARD=off)"; exit 0; }
if command -v flock >/dev/null 2>&1 && [ -f "$HERE/lib_lock.sh" ]; then
  # shellcheck source=/dev/null
  . "$HERE/lib_lock.sh"
  acquire_lock "$STATE/churn_guard.lock" 9 "${OVN_CHURN_LOCK_WAIT:-60}" churn-guard log || exit 0
else
  LD="$STATE/churn_guard.lockdir"
  if ! mkdir "$LD" 2>/dev/null; then
    age=$(( $(date +%s) - $(stat -c %Y "$LD" 2>/dev/null || stat -f %m "$LD" 2>/dev/null || echo 0) ))
    [ "$age" -gt 1800 ] && rm -rf "$LD" && mkdir "$LD" 2>/dev/null || { echo "$(date '+%F %T') [churn-guard] another pass holds the lock - skipping"; exit 0; }
  fi
  trap 'rm -rf "$LD"' EXIT
fi
command -v nice >/dev/null 2>&1 && NICE="nice -n 15" || NICE=""
# shellcheck disable=SC2086
$NICE python3 "$HERE/ovn_churn_guard.py" "$@" || echo "$(date '+%F %T') [churn-guard] python exited $? - ignored (exit 0)"
exit 0
