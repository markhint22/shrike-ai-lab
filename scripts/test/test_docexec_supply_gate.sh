#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_docexec_supply_gate.py (gd-missing-doc supply gate: executor ON / post-check enforce / explicit model override).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_docexec_supply_gate.py"
rc=$?
echo "test_docexec_supply_gate.py rc=$rc"
exit $rc
