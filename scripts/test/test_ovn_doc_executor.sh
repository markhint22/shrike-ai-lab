#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_doc_executor.py (deterministic gd-missing-doc executor; stub LiteLLM, runs anywhere).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_doc_executor.py"
rc=$?
echo "test_ovn_doc_executor.py rc=$rc"
exit $rc
