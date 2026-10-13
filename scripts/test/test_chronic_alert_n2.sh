#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_chronic_alert_n2.py (package qa, 2026-10-13).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_chronic_alert_n2.py"
rc=$?
echo "test_chronic_alert_n2.py rc=$rc"
exit $rc
