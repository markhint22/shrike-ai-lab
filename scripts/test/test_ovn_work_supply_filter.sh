#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_work_supply_filter.py (the v2 per-line filter / seen policy / --on-exhausted / A3 hook; it was never registered).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_work_supply_filter.py"
rc=$?
echo "test_ovn_work_supply_filter.py rc=$rc"
exit $rc
