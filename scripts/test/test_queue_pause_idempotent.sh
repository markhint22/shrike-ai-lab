#!/usr/bin/env bash
# 2026-10-15 regression: queue.sh pause/resume must be idempotent and leave an audit trail.
# Before: a second `pause` re-touched state/PAUSED, resetting its mtime, so pause_guard.sh's
# 90-minute "manual pause forgotten" age never accrued across a deploy that re-paused. Also no
# record of who paused/resumed when, which made the 2026-10-14 pause timeline unrecoverable.
# Runs the REAL queue.sh against a throwaway HOME (never touches the live ~/overnight-queue).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QSRC="$HERE/../../queue.sh"
[ -f "$QSRC" ] || { echo "  FAIL: $QSRC missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/overnight-queue/state"
cp "$QSRC" "$T/home/overnight-queue/queue.sh"
Q="$T/home/overnight-queue"
qrun(){ HOME="$T/home" USER=tester bash "$Q/queue.sh" "$@" 2>&1; }
mtime(){ python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$1"; }

echo "=== first pause creates the flag ==="
qrun pause >/dev/null
ok "pause creates state/PAUSED" "$([ -f "$Q/state/PAUSED" ] && echo 1 || echo 0)"

echo "=== a second pause keeps the original flag age ==="
OLD=$(( $(date +%s) - 7200 ))
touch -d "@$OLD" "$Q/state/PAUSED" 2>/dev/null || python3 -c 'import os,sys; os.utime(sys.argv[1],(int(sys.argv[2]),int(sys.argv[2])))' "$Q/state/PAUSED" "$OLD"
BEFORE="$(mtime "$Q/state/PAUSED")"
OUT="$(qrun pause)"
AFTER="$(mtime "$Q/state/PAUSED")"
ok "re-pause does not reset PAUSED mtime (before=$BEFORE after=$AFTER)" "$([ "$BEFORE" = "$AFTER" ] && echo 1 || echo 0)"
ok "re-pause says it is already paused" "$(printf '%s' "$OUT" | grep -q 'Already paused' && echo 1 || echo 0)"

echo "=== resume clears; resume again is a harmless no-op ==="
qrun resume >/dev/null
ok "resume removes state/PAUSED" "$([ ! -f "$Q/state/PAUSED" ] && echo 1 || echo 0)"
RC=0; OUT="$(qrun resume)" || RC=$?
ok "resume when not paused exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "resume when not paused says no change" "$(printf '%s' "$OUT" | grep -q 'no change' && echo 1 || echo 0)"

echo "=== audit trail ==="
LOG="$Q/state/pause_log"
ok "pause_log exists" "$([ -s "$LOG" ] && echo 1 || echo 0)"
ok "pause_log records a real pause" "$(grep -q ' pause by=tester' "$LOG" && echo 1 || echo 0)"
ok "pause_log records the no-op re-pause" "$(grep -q ' pause-noop by=tester' "$LOG" && echo 1 || echo 0)"
ok "pause_log records a real resume" "$(grep -q ' resume by=tester' "$LOG" && echo 1 || echo 0)"
ok "pause_log records the no-op resume" "$(grep -q ' resume-noop by=tester' "$LOG" && echo 1 || echo 0)"
ok "pause_log lines are UTC ISO timestamps" "$(grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$LOG" && echo 1 || echo 0)"

echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
