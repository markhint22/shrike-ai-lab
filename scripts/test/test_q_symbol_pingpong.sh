#!/usr/bin/env bash
# q-mon-fixes (2026-11-23): runs test_q_symbol_pingpong.py (SHADOW symbol-shape ping-pong detector, real taa plan_lint.py replay + 4 mutants)
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_q_symbol_pingpong.py"; rc=$?
echo "test_q_symbol_pingpong.py rc=$rc"
exit $rc
