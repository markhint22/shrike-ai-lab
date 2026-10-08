#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_work_supply.py (deterministic work supply + red-before spec check).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_work_supply.py"
rc=$?
echo "test_ovn_work_supply.py rc=$rc"
exit $rc
