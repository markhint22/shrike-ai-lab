#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_q_supply_honest.py (pkg q-supply-honest, 2026-11-11; includes the mutant runner).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_q_supply_honest.py"
rc=$?
echo "test_q_supply_honest.py rc=$rc"
exit $rc
