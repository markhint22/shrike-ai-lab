#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_intake_digest.py.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_intake_digest.py"
rc=$?
echo "test_intake_digest.py rc=$rc"
exit $rc
