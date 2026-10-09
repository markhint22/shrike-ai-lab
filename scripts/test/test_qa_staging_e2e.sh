#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_staging_e2e.py (live-staging e2e v2: runner cells vs an in-process stub of staging, run script, ingest, scorecard, G10 replay, mutations).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_staging_e2e.py"
rc=$?
echo "test_qa_staging_e2e.py rc=$rc"
exit $rc
