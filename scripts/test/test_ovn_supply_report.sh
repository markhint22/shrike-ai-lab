#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_supply_report.py (package supply-aware-alerting, 2026-10-18; includes the mutant runner).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_ovn_supply_report.py"
rc=$?
echo "test_ovn_supply_report.py rc=$rc"
exit $rc
