#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_backlog_eligibility.py (spec-compiler-v2).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_backlog_eligibility.py"
rc=$?
echo "test_backlog_eligibility.py rc=$rc"
exit $rc
