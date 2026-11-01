#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_k5_supply_engine.py (package K5-supply-engine, 2026-11-01; includes the mutant runner).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_k5_supply_engine.py"
rc=$?
echo "test_k5_supply_engine.py rc=$rc"
exit $rc
