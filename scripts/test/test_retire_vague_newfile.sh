#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_retire_vague_newfile.py (new-file test items are never dead-path; stale-create shadow detector).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_retire_vague_newfile.py"
rc=$?
echo "test_retire_vague_newfile.py rc=$rc"
exit $rc
