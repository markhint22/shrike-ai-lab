#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_ag_h13.py (2026-10-04 audit rules: qa/ag_h13.py) like cron-style callers do.
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_ag_h13.py"
rc=$?
echo "test_qa_ag_h13.py rc=$rc"
exit $rc
