#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_block_watch.py (qa/qa_block_watch.py: self-healing / loud enforcing QA blocks).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_block_watch.py"
rc=$?
echo "test_qa_block_watch.py rc=$rc"
exit $rc
