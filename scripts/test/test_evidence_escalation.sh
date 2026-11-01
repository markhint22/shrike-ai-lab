#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_evidence_escalation.py (K1: evidence-freshness escalation to EMERGENCY, 2026-11-01).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_evidence_escalation.py"
rc=$?
echo "test_evidence_escalation.py rc=$rc"
exit $rc
