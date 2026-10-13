#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_intake_park_scope.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_intake_park_scope.py"
rc=$?
echo "test_intake_park_scope.py rc=$rc"
exit $rc
