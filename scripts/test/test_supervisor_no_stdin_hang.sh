#!/usr/bin/env bash
# Regression: supervisor.sh's auto-recover timeout counter did `grep -h PATTERN $(ls report*.md)`; with NO report files the
# command substitution expands to nothing and grep reads STDIN. Under cron stdin is /dev/null (fine) but under any open
# pipe (a test harness, an interactive ssh) it blocks forever: found 2026-09-30 as a test_supervisor.sh that hung 35 min.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../supervisor.sh"; [ -f "$S" ] || S="$HERE/../supervisor.sh"; [ -f "$S" ] || S="$HERE/supervisor.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
line="$(grep -n 'grep -h "| \${id} |"' "$S" | head -1)"
ok "the recover-count grep passes /dev/null so it can never fall back to stdin" "$(printf '%s' "$line" | grep -q '/dev/null \$(ls -t' && echo 1 || echo 0)"
T="$(mktemp -d)"; id=x; REPORT_DIR="$T"
# reproduce the exact expression with an EMPTY report dir and stdin held open by a pipe that never closes
out="$( ( sleep 8 ) | timeout 4 bash -c 'id=x; REPORT_DIR='"$T"'; tos="$(grep -h "| ${id} |" /dev/null $(ls -t "$REPORT_DIR"/2026*.md 2>/dev/null | head -6) 2>/dev/null | grep -c "error(exit=124)")"; echo "tos=$tos"' 2>&1 )"
ok "empty report dir + open stdin pipe does not hang (prints tos=0)" "$([ "$out" = "tos=0" ] && echo 1 || echo 0)"
rm -rf "$T"; echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
