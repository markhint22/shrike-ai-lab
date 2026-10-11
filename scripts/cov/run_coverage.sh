#!/usr/bin/env bash
# Run the pipeline test suite under line-coverage instrumentation and print the report.
# usage: run_coverage.sh [test_script ...]   (default: scripts/test/run_all.sh)  env: OVN_COV_MIN=<pct> to fail below it
set -uo pipefail
Q="${OVN_Q:-$HOME/overnight-queue}"
D="${OVN_COV_DIR:-/tmp/ovn-cov}"; rm -rf "$D"; mkdir -p "$D/py"
# 2026-10-10 (qacov QA-3): tests that COPY a tool into a temp dir before running it (test_ovn_mutation_supply.py shutil.copy, test_ovn_spec_gate_scan.sh `cp ovn_spec_gate.py`)
# were invisible to `source = $Q` (the copy lives elsewhere), so well-tested modules showed 32-45%. The run rc now uses `include`: everything under $Q plus ANY file whose
# basename is one of the pipeline's own python scripts (`**/name.py`; basenames are unique, attic/.bak excluded); ovn_cov_report.py folds a copy's executed lines back onto
# the script with the same basename (the bash side already did this). `source` is kept in a SECOND rc (covrc_src) used for one no-op run at the end: coverage records the
# never-imported files of its `source` dirs as 0% only at process exit, which `include` alone cannot do (archive_claude_queue_done.py etc. must still count as missed). Its data goes to
# its OWN dir ($D/py_noop): `coverage combine` drops a data file whose content hash equals an earlier one's, and the touched-only (zero-line) noop data hashes like the hundreds of empty
# data files of one-liner python processes - merged in the same dir it was silently lost (measured on the box). The report merges it with `combine --append`.
# Generic basenames (conftest.py, __init__.py, __main__.py, setup.py) are left out of that include list and of the report's basename fold: any project has them, and folding an unrelated copy onto a pipeline file of the
# same name would add its executed lines (2026-10-11 review of qacov).
# OVN_COV_QA=1 also measures qa/ (python: `env -i` tests get the cov vars through scripts/cov/shim/env; bash: reported too) as SEPARATE python-qa/bash-qa rows that the nightly
# floors do not include (see ovn_coverage_cron.sh); default off until a clean night proves the shim does not disturb the qa tests.
OMIT="*/scripts/test/*,*/scripts/cov/*,*/repos/*,*/proposals*/*,*/attic/*"; [ "${OVN_COV_QA:-0}" = "1" ] || OMIT="$OMIT,*/qa/*"
PYBASES="$(cd "$Q" && find . \( -name test -o -name cov -o -name attic -o -name repos -o -name state -o -name logs -o -name __pycache__ -o -name '.git' -o -name 'proposals*' -o -name '.bak*' $([ "${OVN_COV_QA:-0}" = "1" ] || echo "-o -name qa") \) -prune -o -type f -name '*.py' ! -name '._*' ! -name conftest.py ! -name __init__.py ! -name __main__.py ! -name setup.py -print 2>/dev/null | sed 's#.*/##' | sort -u | sed 's#^#**/#' | tr '\n' ',')"
cat > "$D/covrc" <<RC
[run]
parallel = True
data_file = $D/py/.coverage
include = $Q/**,${PYBASES%,}
omit = $OMIT
[report]
omit = $OMIT
RC
mkdir -p "$D/py_noop"
cat > "$D/covrc_src" <<RC
[run]
parallel = True
data_file = $D/py_noop/.coverage
source = $Q
omit = $OMIT
RC
printf 'pass\n' > "$D/noop.py"
SHIM="$Q/scripts/cov/shim"
export OVN_COV_DIR="$D" BASH_ENV="$Q/scripts/cov/cov_env.sh" COVERAGE_PROCESS_START="$D/covrc" PYTHONPATH="$Q/scripts/cov/pysite${PYTHONPATH:+:$PYTHONPATH}"
# the REAL env is looked up on a fixed system PATH: `command -v env` on the live PATH would return an OUTER run's shim when this harness runs nested (the shim then exec'ed itself forever: a 30 min hang)
[ "${OVN_COV_QA:-0}" = "1" ] && [ -x "$SHIM/env" ] && export PATH="$SHIM:$PATH" OVN_COV_REAL_ENV="$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin command -v env || echo /usr/bin/env)"
cd "$Q/scripts/test" || exit 1
# shellcheck source=/dev/null
. "$Q/scripts/test/ntfy_guard.sh"   # 2026-09-30: never reach the real ntfy.sh from a test run
if [ "$#" -gt 0 ]; then for t in "$@"; do bash "$t" < /dev/null > "$D/out.$(basename "$t").log" 2>&1; echo "$t rc=$?"; done
else bash run_all.sh < /dev/null > "$D/run_all.log" 2>&1; echo "run_all rc=$?"; fi
unset BASH_ENV COVERAGE_PROCESS_START OVN_COV_REAL_ENV
# the one no-op run under the `source` rc: records every never-imported python file under $Q as 0% (see above); failure is harmless (those files just are not listed)
( cd "$D" && python3 -m coverage run --rcfile="$D/covrc_src" "$D/noop.py" ) >/dev/null 2>&1
LIVE=""; [ -f "$Q/scripts/cov/live_scripts.txt" ] && LIVE="--only-live $Q/scripts/cov/live_scripts.txt"
python3 "$Q/scripts/cov/ovn_cov_report.py" "$D" "$Q" ${OVN_COV_MIN:+--min "$OVN_COV_MIN"} --json "$D/report.json" $LIVE ${OVN_COV_MISSING:+--show-missing "$OVN_COV_MISSING"}
