#!/usr/bin/env bash
# Bash wrapper so run_all.sh can execute test_spec_gate_repos.py (spec-intake-5-lanes). Python only.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_spec_gate_repos.py"
rc=$?
echo "test_spec_gate_repos.py rc=$rc"
exit $rc
