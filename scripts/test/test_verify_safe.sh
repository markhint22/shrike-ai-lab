#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_verify_safe.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_verify_safe.py"
rc=$?
echo "test_verify_safe.py rc=$rc"
exit $rc
