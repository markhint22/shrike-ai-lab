#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_work_supply_frozen.py (K3 item 3: AGENTS.md frozen-file filter in the deterministic work supply).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_work_supply_frozen.py"
rc=$?
echo "test_ovn_work_supply_frozen.py rc=$rc"
exit $rc
