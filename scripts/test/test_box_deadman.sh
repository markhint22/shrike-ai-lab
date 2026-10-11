#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_box_deadman.py (scripts/box_deadman.py: the Mac-side off-box dead-man's switch for the GPU box).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_box_deadman.py"
rc=$?
echo "test_box_deadman.py rc=$rc"
exit $rc
