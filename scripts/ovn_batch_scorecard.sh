#!/usr/bin/env bash
# ovn_batch_scorecard.sh — daily cron wrapper for ovn_batch_scorecard.py (2026-09-23).
# The python script only prints a report; this drives it, logs it, and alerts on
# ntfy only when a batch is actually struggling (<50%, i.e. the python script's own
# "⚠️ " flag) — a quiet day with all-healthy batches should not page anyone, mirroring
# ovn_fleet_health.sh's alert-only-when-something-needs-attention convention.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_batch_scorecard.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

OUT="$(python3 scripts/ovn_batch_scorecard.py 2>>"$LOG")"

if [ -z "$OUT" ]; then
  say "clean run — no feat-tagged batches >=24h old to report on"
  exit 0
fi

say "$OUT"
BAD_N="$(printf '%s' "$OUT" | grep -c '⚠️' || true)"
if [ "${BAD_N:-0}" -gt 0 ]; then
  alert "Research-batch scorecard: $BAD_N struggling batch(es)" "warning" "$(printf '%s' "$OUT" | head -c 800)"
else
  say "all reported batches landing >=50% — no alert"
fi
