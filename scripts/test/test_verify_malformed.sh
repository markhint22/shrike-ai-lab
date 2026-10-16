#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_verify_malformed.py (VERIFY malformation lint, 2026-10-15).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_verify_malformed.py"
rc=$?
echo "test_verify_malformed.py rc=$rc"
exit $rc
