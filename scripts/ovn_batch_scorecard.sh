#!/usr/bin/env bash
# ovn_batch_scorecard.sh — daily cron wrapper for ovn_batch_scorecard.py (2026-09-23,
# letter-grade redesign 2026-09-25). The python script prints a grade-distribution
# summary plus the full D/F detail list and this drives it, logs it, and alerts on
# ntfy only when at least one batch is flagged D/F — a quiet day with all-healthy
# batches should not page anyone, mirroring ovn_fleet_health.sh's
# alert-only-when-something-needs-attention convention.
#
# 2026-09-25 fix: the previous version counted `⚠️` occurrences in the (capped)
# python output for its title, then ALSO truncated the alert body to `head -c 800` —
# so the title's count and the body's visible content could both undercount the true
# picture. The python script now emits a machine-parseable "#SUMMARY ..." trailer
# line specifically so this wrapper never has to re-derive counts from the
# human-readable text (which can legitimately be long); the alert body is sent in
# full (minus the #SUMMARY line itself, which is log-only) since a fleet at this
# scale produces at most a few dozen flagged-batch lines — nowhere near ntfy's
# message-size ceiling — so there is no need to truncate it at all.
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

SUMMARY_LINE="$(printf '%s\n' "$OUT" | grep '^#SUMMARY ' || true)"
FLAGGED="$(printf '%s\n' "$SUMMARY_LINE" | sed -n 's/.*flagged=\([0-9]*\).*/\1/p')"
FLAGGED="${FLAGGED:-0}"
BODY="$(printf '%s\n' "$OUT" | grep -v '^#SUMMARY ')"

if [ "$FLAGGED" -gt 0 ]; then
  alert "Research-batch scorecard: $FLAGGED batch(es) graded D/F" "warning" "$BODY"
else
  say "no D/F batches — no alert"
fi
