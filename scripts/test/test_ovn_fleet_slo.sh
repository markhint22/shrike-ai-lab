#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_fleet_slo.py (package L5-fleet-slo, 2026-10-18; includes the mutant runner and the real-shaped box fixture).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_ovn_fleet_slo.py"
rc=$?
echo "test_ovn_fleet_slo.py rc=$rc"
exit $rc
