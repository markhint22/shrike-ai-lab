#!/usr/bin/env bash
# Bash wrapper so run_all.sh can execute test_spec_rule_r18.py (spec-intake-5-lanes). Python only; no network, no repo writes.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_spec_rule_r18.py"
rc=$?
echo "test_spec_rule_r18.py rc=$rc"
exit $rc
