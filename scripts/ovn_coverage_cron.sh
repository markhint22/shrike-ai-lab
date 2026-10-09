#!/usr/bin/env bash
# scripts/ovn_coverage_cron.sh - nightly full-suite LINE-COVERAGE run + ratchet (2026-09-30).
#
# Runs the whole pipeline test suite under scripts/cov/run_coverage.sh (bash xtrace + python coverage), then compares the measured
# bash and python line coverage to scripts/cov/coverage_baseline.json (a floor). Below the floor, or any failing test in the run,
# appends a warn line to state/alerts.log (ONE alerting channel - no separate push). A clearly better result raises the floor so
# coverage can only ratchet upward. Writes the human report to state/coverage_latest.txt and the machine report to
# state/coverage_latest.json. OVN_COVERAGE_DISABLE=1 turns it off. Heavy (~15-25 min), so it runs at night from cron.
set -uo pipefail
[ -n "${OVN_COVERAGE_DISABLE:-}" ] && exit 0
Q="${OVN_Q:-$HOME/overnight-queue}"
cd "$Q" || exit 1
STATE="$Q/state"; mkdir -p "$STATE"
# shellcheck source=/dev/null
. "$Q/scripts/lib_lock.sh"
acquire_lock "$STATE/coverage.lock" 231 0 "coverage-cron" log || exit 0
BASE="${OVN_COV_BASELINE:-$Q/scripts/cov/coverage_baseline.json}"
RUNNER="${OVN_COV_RUNNER:-$Q/scripts/cov/run_coverage.sh}"
# NOTE: deliberately NOT named OVN_COV_DIR - that variable belongs to the instrumentation harness (cov_env.sh writes its xtrace data there)
D="${OVN_COV_NIGHTLY_DIR:-/tmp/ovn-cov-nightly}"
ALERTS="$STATE/alerts.log"
alert(){ echo "$(date '+%F %T') warn | coverage | $*" >> "$ALERTS"; }

# 2026-10-09: the instrumented run failed 7-9 tests every night since 10-04 because coverage.py's own stderr warning ("CoverageWarning: Couldn't import
# C tracer: ... (no-ctracer)", 246 lines per run on the box, where only the pure-python tracer is installed) leaked into the captured got-values of the
# 'buckets' and 'outcomes: every row is valid JSON' tests (the uninstrumented 06:00 run is green). coverage's `disable_warnings` rc option would be the
# tidy fix but the rc is written by scripts/cov/run_coverage.sh, so silence the same warnings through Python's own filter (inherited by every
# instrumented child): no test file and no coverage floor changes. Messages are prefix-matched (case-sensitive): no-ctracer, couldnt-parse,
# no-data-collected. OVN_COV_KEEP_WARNINGS=1 leaves them visible (debugging).
if [ "${OVN_COV_KEEP_WARNINGS:-0}" != "1" ]; then
  export PYTHONWARNINGS="${PYTHONWARNINGS:+$PYTHONWARNINGS,}ignore:Couldn't import C tracer,ignore:Couldn't parse Python file,ignore:No data was collected"
fi
OVN_COV_DIR="$D" bash "$RUNNER" > "$STATE/coverage_latest.txt" 2>&1
cp "$D/report.json" "$STATE/coverage_latest.json" 2>/dev/null

read -r bash_pct py_pct min_b min_p < <(python3 - "$D/report.json" "$BASE" <<'PY'
import json, sys
try:
    rows = json.load(open(sys.argv[1])).get("scripts", [])
except Exception:
    print("-1 -1 0 0"); sys.exit(0)
try:
    base = json.load(open(sys.argv[2]))
except Exception:
    base = {}
def pct(lang):
    h = sum(r["hit"] for r in rows if r["lang"] == lang); t = sum(r["lines"] for r in rows if r["lang"] == lang)
    return 100.0 * h / t if t else -1
print("%.1f %.1f %s %s" % (pct("bash"), pct("python"), base.get("bash", 0), base.get("python", 0)))
PY
)
if [ "${bash_pct%%.*}" = "-1" ] || [ "${py_pct%%.*}" = "-1" ]; then
  alert "coverage run produced no usable report (see $STATE/coverage_latest.txt)"; exit 0
fi
# 2026-10-02: was `failed, [1-9]`, which also matched "0 failed, 2 known-bug warning(s)" (a passing summary) - 34 false alerts on 10-01. Now only a NONZERO failed count.
# 2026-10-09: passing lines are dropped first - "  ok   cycle 1 (1 failed attempt)" / "2 failed attempts" / "after 2 failed (verify red) attempts" are PASSING tests that
# merely talk about failed attempts; they kept failing=3 on the nightly even with the warning noise gone.
failed="$(grep -av '^[[:space:]]*ok[[:space:]]' "$D/run_all.log" 2>/dev/null | grep -acE '❌|^  FAIL |(^|[^0-9])[1-9][0-9]* failed')"; failed="${failed:-0}"
[ "$failed" -gt 0 ] && alert "$failed failing test line(s) in the instrumented suite run (see $D/run_all.log)"
below=""
python3 -c "import sys; sys.exit(0 if float('$bash_pct') >= float('$min_b') else 1)" || below="$below bash ${bash_pct}% < floor ${min_b}%"
python3 -c "import sys; sys.exit(0 if float('$py_pct') >= float('$min_p') else 1)" || below="$below python ${py_pct}% < floor ${min_p}%"
[ -n "$below" ] && alert "line coverage regressed:$below"
# ratchet: a result more than 1 point above the floor raises the floor to (result - 1), floored to an integer
python3 - "$BASE" "$bash_pct" "$py_pct" <<'PY'
import json, sys
p, b, y = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
try:
    base = json.load(open(p))
except Exception:
    base = {"bash": 0, "python": 0}
ch = False
for k, v in (("bash", b), ("python", y)):
    new = int(v - 1)
    if new > base.get(k, 0):
        base[k] = new; ch = True
if ch:
    json.dump(base, open(p, "w")); print("ratcheted floor ->", base)
PY
echo "$(date '+%F %T') coverage: bash ${bash_pct}% python ${py_pct}% (floor ${min_b}/${min_p}) failing=$failed" >> "$STATE/coverage_history.log"
exit 0
