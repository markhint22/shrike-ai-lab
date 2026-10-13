#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_intake_verify_lint.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_intake_verify_lint.py"
rc=$?
echo "test_intake_verify_lint.py rc=$rc"
exit $rc
