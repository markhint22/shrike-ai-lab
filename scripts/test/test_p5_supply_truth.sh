#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_p5_supply_truth.py (package P5-supply-truth, 2026-11-02; includes the mutant runner).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
TZ=UTC NTFY_SERVER=http://127.0.0.1:9 "$PY" "$HERE/test_p5_supply_truth.py"
rc=$?
echo "test_p5_supply_truth.py rc=$rc"
exit $rc
