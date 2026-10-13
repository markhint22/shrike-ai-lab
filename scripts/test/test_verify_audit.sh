#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_verify_audit.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_verify_audit.py"
rc=$?
echo "test_verify_audit.py rc=$rc"
exit $rc
