#!/bin/bash
# Bash wrapper so run_all.sh executes test_qwen_explore_dialect.py (explorer VERIFY-dialect regression + mutants; hermetic, seconds).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qwen_explore_dialect.py"
rc=$?
echo "test_qwen_explore_dialect.py rc=$rc"
exit $rc
