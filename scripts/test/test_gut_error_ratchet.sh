#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_gut_error_ratchet.py (shadow ratchet over hidden GUT SCRIPT ERRORs).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_gut_error_ratchet.py"
rc=$?
echo "test_gut_error_ratchet.py rc=$rc"
exit $rc
