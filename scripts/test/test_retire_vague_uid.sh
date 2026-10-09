#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_retire_vague_uid.py (.gd.uid items are no longer mis-retired as dead-path).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_retire_vague_uid.py"
rc=$?
echo "test_retire_vague_uid.py rc=$rc"
exit $rc
