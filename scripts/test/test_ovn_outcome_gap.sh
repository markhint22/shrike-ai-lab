#!/usr/bin/env bash
# 2026-10-15 regression: the 2026-10-14 night wrote no outcomes for 8 h (21:00-05:00 CDT) and nothing flagged it. ovn_outcome_gap.py is a
# SHADOW monitor: it writes WOULD-ALERT lines only, never pages, and stays quiet during a deliberate pause. Drives the real script with a
# fixed --now so the result does not depend on the clock.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../../ovn_outcome_gap.py"
[ -f "$PY" ] || { echo "  FAIL: $PY missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
OUT="$T/outcomes.jsonl"; FLAG="$T/PAUSED"; LOG="$T/outcome_gap.log"
# fixed clock: 2026-10-15T06:00:00Z
NOW=$(python3 -c 'import calendar,time; print(calendar.timegm(time.strptime("2026-10-15T06:00:00","%Y-%m-%dT%H:%M:%S")))')
row(){ printf '{"ts":"%s","repo":"x","class":"landed"}\n' "$1" >> "$OUT"; }

echo "=== fresh outcomes: no alert ==="
row "2026-10-15T05:30:00Z"
R="$(python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --now "$NOW")"; RC=$?
ok "fresh outcome exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "fresh outcome is ok" "$(printf '%s' "$R" | grep -q '^ok' && echo 1 || echo 0)"
ok "fresh outcome writes no WOULD-ALERT" "$([ ! -s "$LOG" ] && echo 1 || echo 0)"

echo "=== 90-minute gap, not paused: WOULD-ALERT (shadow) ==="
rm -f "$OUT"; row "2026-10-15T04:30:00Z"
R="$(python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --now "$NOW")"; RC=$?
ok "gap exits 0 (shadow never fails the run)" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "gap reports WOULD-ALERT" "$(printf '%s' "$R" | grep -q 'WOULD-ALERT' && echo 1 || echo 0)"
ok "gap is logged" "$(grep -q 'WOULD-ALERT gap_min=90' "$LOG" && echo 1 || echo 0)"

echo "=== same gap but deliberately paused: silent ==="
rm -f "$LOG"; : > "$FLAG"
R="$(python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --now "$NOW")"
ok "paused reports paused" "$(printf '%s' "$R" | grep -q '^paused' && echo 1 || echo 0)"
ok "paused writes no alert line" "$([ ! -s "$LOG" ] && echo 1 || echo 0)"
rm -f "$FLAG"

echo "=== no outcomes file at all: flagged ==="
rm -f "$OUT" "$LOG"
R="$(python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --now "$NOW")"
ok "missing outcomes reports no-outcomes" "$(printf '%s' "$R" | grep -q '^no-outcomes' && echo 1 || echo 0)"
ok "missing outcomes is logged" "$(grep -q 'no-outcomes' "$LOG" && echo 1 || echo 0)"

echo "=== bad input: refused, no enforcement mode ==="
python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --mode alert >/dev/null 2>&1; RC=$?
ok "--mode alert is refused (rc 2)" "$([ "$RC" = 2 ] && echo 1 || echo 0)"
python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --max-min 0 >/dev/null 2>&1; RC=$?
ok "--max-min 0 is refused (rc 2)" "$([ "$RC" = 2 ] && echo 1 || echo 0)"

echo "=== newest row wins even if the file is out of order ==="
rm -f "$OUT" "$LOG"; row "2026-10-15T05:50:00Z"; row "2026-10-14T01:00:00Z"
R="$(python3 "$PY" --outcomes "$OUT" --pause-flag "$FLAG" --log "$LOG" --now "$NOW")"
ok "out-of-order file is ok (newest 05:50)" "$(printf '%s' "$R" | grep -q '^ok' && echo 1 || echo 0)"

echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
