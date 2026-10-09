#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_spec_rules.py (spec-compiler-v2).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_spec_rules.py"
rc=$?
echo "test_ovn_spec_rules.py rc=$rc"
exit $rc
