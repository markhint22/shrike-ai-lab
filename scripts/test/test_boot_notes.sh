#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_boot_notes.py (ovn_notify.boot_notes: reboot / unclean-outage / silent-queue lines of the hourly update).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_boot_notes.py"
rc=$?
echo "test_boot_notes.py rc=$rc"
exit $rc
