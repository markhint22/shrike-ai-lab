#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_supply_r10.py (work-supply package 2026-10-10: pullable_count list, ruff-F401 classify, parked lines, bad-spec reporting, relocate cd).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_supply_r10.py"
rc=$?
echo "test_ovn_supply_r10.py rc=$rc"
exit $rc
