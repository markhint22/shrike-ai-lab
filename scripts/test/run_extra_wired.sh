#!/usr/bin/env bash
# scripts/test/run_extra_wired.sh - runs the finished-but-never-wired python test files that scripts/test/run_all.sh does not reference (qacov QA-3, 2026-10-10).
# analysis[2] QA-3: test_ovn_ruff_fix_executor.py, test_ovn_mission_lint.py, test_ovn_work_supply_filter.py and test_contract_fuzz.py exist and pass (34 / 17 / 69 / 75 checks) but no
# line of run_all.sh ran them, so ovn_ruff_fix_executor.py (31/174 lines), ovn_mission_lint.py and the v2 filter of ovn_work_supply.py showed as untested in the nightly coverage run.
# run_all.sh stays untouched by this package: add ONE line to it (the lead does):
#   echo; echo "===== extra wired tests ====="; bash run_extra_wired.sh || rc=1
# Each test runs through `python3 <file>` exactly as its docstring says; exit 0 only if all four pass. Tests that need tools missing on the host print their own SKIP and exit 0
# (ruff absent, schemathesis absent: OVN_REQUIRE_TOOLS / OVN_REQUIRE_QA_VENV make those a failure, as in the test files).
HERE_EW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE_EW" || exit 1
rc=0
PY="$(command -v python3.12 || command -v python3)"
for t in test_ovn_ruff_fix_executor test_ovn_mission_lint test_ovn_work_supply_filter test_contract_fuzz; do
  echo "===== $t ====="
  if [ -f "$t.py" ]; then "$PY" "$t.py" || { echo "  FAIL: $t.py rc=$?"; rc=1; }; else echo "  FAIL: $t.py missing"; rc=1; fi
done
[ $rc -eq 0 ] && echo "extra wired tests: all pass" || echo "extra wired tests: FAILED"
exit $rc
