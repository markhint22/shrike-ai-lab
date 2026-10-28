#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_antigaming_noact.py (2026-10-28 fleet review).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_antigaming_noact.py"
rc=$?
echo "test_qa_antigaming_noact.py rc=$rc"
exit $rc
