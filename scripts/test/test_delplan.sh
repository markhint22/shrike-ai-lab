#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_delplan.py (package delplan: X5 plan / X6 importers / X10-X11 spec rules R13-R15 / F8 move executor).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
timeout 600 "$PY" "$HERE/test_delplan.py"
rc=$?
echo "test_delplan.py rc=$rc"
exit $rc
