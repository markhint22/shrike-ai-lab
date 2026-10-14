#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_supply_ledger.py (package supply-ledger, 2026-10-13).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_supply_ledger.py"
rc=$?
echo "test_supply_ledger.py rc=$rc"
exit $rc
