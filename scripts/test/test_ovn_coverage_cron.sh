#!/usr/bin/env bash
# scripts/ovn_coverage_cron.sh: nightly coverage run + ratchet. A stub runner writes a canned report.json/run_all.log.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../ovn_coverage_cron.sh"; [ -f "$S" ] || S="$HERE/ovn_coverage_cron.sh"
LIB="$(dirname "$S")/lib_lock.sh"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/q/scripts/cov" "$T/q/state"; cp "$LIB" "$T/q/scripts/"
mkrunner(){  # $1=bash hit, $2=python hit, $3=failing-line-or-empty
  cat > "$T/q/scripts/cov/run_coverage.sh" <<R
#!/usr/bin/env bash
mkdir -p "\$OVN_COV_DIR"
cat > "\$OVN_COV_DIR/report.json" <<J
{"scripts":[{"file":"a.sh","lang":"bash","hit":$1,"lines":100},{"file":"b.py","lang":"python","hit":$2,"lines":100}]}
J
echo "${3:-all good}" > "\$OVN_COV_DIR/run_all.log"
echo "TOTAL: stub"
R
  chmod +x "$T/q/scripts/cov/run_coverage.sh"; }
run(){ OVN_Q="$T/q" OVN_COV_NIGHTLY_DIR="$T/cov" OVN_COV_BASELINE="$T/q/base.json" OVN_COV_RUNNER="$T/q/scripts/cov/run_coverage.sh" bash "$S"; }
echo '{"bash": 80, "python": 80}' > "$T/q/base.json"
mkrunner 90 85; run
ok "healthy run: no alert" "$([ ! -s "$T/q/state/alerts.log" ] && echo 1 || echo 0)"
ok "healthy run: history line written" "$(grep -q 'bash 90.0% python 85.0%' "$T/q/state/coverage_history.log" && echo 1 || echo 0)"
ok "report copied to state/coverage_latest.json" "$([ -s "$T/q/state/coverage_latest.json" ] && echo 1 || echo 0)"
ok "ratchet: floor raised to result-1 (bash 89, python 84)" "$(python3 -c "import json;d=json.load(open('$T/q/base.json'));print(d=={'bash':89,'python':84})" | grep -q True && echo 1 || echo 0)"
mkrunner 70 85; run
ok "regression below the floor raises a warn alert naming bash" "$(grep -q 'warn | coverage | line coverage regressed: bash 70.0% < floor 89' "$T/q/state/alerts.log" && echo 1 || echo 0)"
ok "floor is NOT lowered by a regression" "$(python3 -c "import json;d=json.load(open('$T/q/base.json'));print(d['bash']==89)" | grep -q True && echo 1 || echo 0)"
: > "$T/q/state/alerts.log"; mkrunner 95 90 "  FAIL something broke"; run
ok "failing test lines in the suite log raise a warn alert" "$(grep -q 'failing test line' "$T/q/state/alerts.log" && echo 1 || echo 0)"
# 2026-10-22 (PKG-A): the loose "N failed" regex counted summary lines such as "passed=6 failed=0" / "6 failed attempts" (3 false matches on the box). Only "  FAIL " lines and the banner count.
: > "$T/q/state/alerts.log"; mkrunner 95 90 "  ok   x
passed=6 failed=0
  3 passed, 0 failed
  summary: 6 failed attempts were retried
  ok   cycle (1 failed attempt)
  SKIP something (2 failed probes)"; run
ok "PKG-A: loose 'N failed' summary text is NOT a failing test line (no alert)" "$(grep -q 'failing test line' "$T/q/state/alerts.log" && echo 0 || echo 1)"
: > "$T/q/state/alerts.log"; mkrunner 95 90 "  FAIL: noise suite: something broke"; run
ok "PKG-A: a '  FAIL:' line (colon form) still alerts" "$(grep -q '1 failing test line' "$T/q/state/alerts.log" && echo 1 || echo 0)"
: > "$T/q/state/alerts.log"; mkrunner 95 90 "$(printf '\342\235\214 SOME QUEUE TESTS FAILED')"; run
ok "PKG-A: the failure banner still alerts" "$(grep -q '1 failing test line' "$T/q/state/alerts.log" && echo 1 || echo 0)"
: > "$T/q/state/alerts.log"; printf 'not json' > /dev/null; cat > "$T/q/scripts/cov/run_coverage.sh" <<'R'
#!/usr/bin/env bash
mkdir -p "$OVN_COV_DIR"; rm -f "$OVN_COV_DIR/report.json"; echo x > "$OVN_COV_DIR/run_all.log"
R
run
ok "no usable report raises a warn alert instead of crashing" "$(grep -q 'no usable report' "$T/q/state/alerts.log" && echo 1 || echo 0)"
mkrunner 99 99; : > "$T/q/state/alerts.log"; OVN_COVERAGE_DISABLE=1 run
ok "OVN_COVERAGE_DISABLE=1 does nothing" "$([ ! -s "$T/q/state/alerts.log" ] && echo 1 || echo 0)"
# lock: while another run holds the lock this one skips silently (no alert, no history line)
mkrunner 99 99; : > "$T/q/state/alerts.log"; : > "$T/q/state/coverage_history.log"
( exec 9>"$T/q/state/coverage.lock"; flock 9; sleep 5 ) & holder=$!
sleep 1; run >/dev/null 2>&1
ok "a held lock makes the run skip: no history line written" "$([ ! -s "$T/q/state/coverage_history.log" ] && echo 1 || echo 0)"
wait "$holder" 2>/dev/null
run >/dev/null 2>&1
ok "once the lock is free the run proceeds" "$([ -s "$T/q/state/coverage_history.log" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
