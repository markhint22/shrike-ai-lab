#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_gut_clause_r16.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_gut_clause_r16.py"
rc=$?
echo "test_gut_clause_r16.py rc=$rc"
exit $rc
