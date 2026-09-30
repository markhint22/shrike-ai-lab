#!/usr/bin/env bash
# Run the pipeline test suite under line-coverage instrumentation and print the report.
# usage: run_coverage.sh [test_script ...]   (default: scripts/test/run_all.sh)  env: OVN_COV_MIN=<pct> to fail below it
set -uo pipefail
Q="${OVN_Q:-$HOME/overnight-queue}"
D="${OVN_COV_DIR:-/tmp/ovn-cov}"; rm -rf "$D"; mkdir -p "$D/py"
cat > "$D/covrc" <<RC
[run]
parallel = True
data_file = $D/py/.coverage
source = $Q
omit = */scripts/test/*,*/scripts/cov/*,*/repos/*,*/proposals*/*
RC
export OVN_COV_DIR="$D" BASH_ENV="$Q/scripts/cov/cov_env.sh" COVERAGE_PROCESS_START="$D/covrc" PYTHONPATH="$Q/scripts/cov/pysite${PYTHONPATH:+:$PYTHONPATH}"
cd "$Q/scripts/test" || exit 1
# shellcheck source=/dev/null
. "$Q/scripts/test/ntfy_guard.sh"   # 2026-09-30: never reach the real ntfy.sh from a test run
if [ "$#" -gt 0 ]; then for t in "$@"; do bash "$t" < /dev/null > "$D/out.$(basename "$t").log" 2>&1; echo "$t rc=$?"; done
else bash run_all.sh < /dev/null > "$D/run_all.log" 2>&1; echo "run_all rc=$?"; fi
unset BASH_ENV COVERAGE_PROCESS_START
LIVE=""; [ -f "$Q/scripts/cov/live_scripts.txt" ] && LIVE="--only-live $Q/scripts/cov/live_scripts.txt"
python3 "$Q/scripts/cov/ovn_cov_report.py" "$D" "$Q" ${OVN_COV_MIN:+--min "$OVN_COV_MIN"} --json "$D/report.json" $LIVE ${OVN_COV_MISSING:+--show-missing "$OVN_COV_MISSING"}
