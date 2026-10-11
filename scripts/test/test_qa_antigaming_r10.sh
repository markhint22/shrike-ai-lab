#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_antigaming_r10.py (package qagate, 2026-10-10).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_antigaming_r10.py"
rc=$?
echo "test_qa_antigaming_r10.py rc=$rc"
exit $rc
