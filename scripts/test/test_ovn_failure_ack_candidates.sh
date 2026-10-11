#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_failure_ack_candidates.py (dry-run list of failure clusters already fixed by shipped commits).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_failure_ack_candidates.py"
rc=$?
echo "test_ovn_failure_ack_candidates.py rc=$rc"
exit $rc
