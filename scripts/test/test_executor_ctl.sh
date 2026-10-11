#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_executor_ctl.py (ovn_executor_ctl.py: summary/readiness/enable/disable/rehearse; real git, real doc executor against a stub LiteLLM).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_executor_ctl.py"
rc=$?
echo "test_executor_ctl.py rc=$rc"
exit $rc
