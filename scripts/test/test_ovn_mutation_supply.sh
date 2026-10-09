#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_mutation_supply.py (GDScript mutation-survivor supply; shim godot, runs anywhere).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_mutation_supply.py"
rc=$?
echo "test_ovn_mutation_supply.py rc=$rc"
exit $rc
