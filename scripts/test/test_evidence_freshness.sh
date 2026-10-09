#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_evidence_freshness.py (qa/evidence_freshness_check.py: stale promote evidence -> one alerts.log WARN per source per 6 h).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_evidence_freshness.py"
rc=$?
echo "test_evidence_freshness.py rc=$rc"
exit $rc
