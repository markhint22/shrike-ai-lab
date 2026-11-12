#!/usr/bin/env bash
# test_run_all_skip77.sh - package q-infra-gates (2026-11-11), finding 2 of nov11_health: run_all.sh run_if_present turned a suite's exit 77 (skip) into rc=1, so the six-hourly suite cron
# was red 3 runs in a row with NO suite named ("sandboxed suite rc=1"). The REAL run_if_present / finish / suite shadow functions are extracted from run_all.sh and run against fake suites.
#   A. exit 77 is a SKIP: rc stays 0, the final verdict is green, the skipped suite is LISTED in the summary
#   B. exit 1 still fails AND names itself in FAILED SUITES; a missing file is a listed skip
#   C. a red run with an empty FAILED SUITES list is impossible: finish prints an explicit "none recorded: rc=N" line
#   D. OVN_RUN_IF_PRESENT_77=fail restores the old mapping (77 -> rc=1)
#   E. ops/run_suite_sandboxed_cron.sh: a red run whose capture is empty records rc and the LAST failing line (synthetic row + the alerts.log WARN)
#   F. run_all.sh registers this test; test_q_z4_advisories.sh (the real 77 exit) is run through run_or_notrun
# Mutants: M1 old mapping (`|| rc=1`), M2 77 skipped but not listed, M3 finish drops the empty-list line, M4 wrapper drops the last failing line.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
export TZ=UTC OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9
REAL_SRC="$(cd "$HERE/../.." && pwd)"; SRC="${RA_SRC:-$REAL_SRC}"
RA="$SRC/scripts/test/run_all.sh"; WR="$SRC/ops/run_suite_sandboxed_cron.sh"
[ -f "$RA" ] && [ -f "$WR" ] || { echo "  FAIL: run_all.sh / wrapper missing under $SRC"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir ra77)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
safe_set_sandbox_home "$T" || exit 1

R="$T/ra"; mkdir -p "$R"
{ echo 'FAILED_SUITES=""; rc=0; NOTRUN=0'
  grep -E '^(_ovn_first_fail|_ovn_note_fail)\(' "$RA"
  awk '/^_ovn_run_suite\(\)\{/,/^\}$/' "$RA"
  grep -E '^(bash|python3)\(\)\{' "$RA"
  grep -E '^(SKIPPED=0;|run_if_present\(\)\{)' "$RA"
  awk '/^finish\(\)\{/,/^\}$/' "$RA"; } > "$R/fns.sh"
[ "$(grep -c 'run_if_present()' "$R/fns.sh")" = 1 ] && [ "$(grep -c '^finish()' "$R/fns.sh")" = 1 ] || { echo "  FAIL: could not extract the functions from run_all.sh"; exit 1; }
printf 'echo "SKIP: prerequisites missing"; exit 77\n' > "$R/skip.sh"; printf 'echo ran-ok; exit 0\n' > "$R/ok.sh"; printf 'echo "  FAIL: a real check failed"; exit 1\n' > "$R/bad.sh"
run_case(){   # <out> <fake suites...>: run through run_if_present, then finish
  local o="$1"; shift
  ( cd "$R" || exit 99; . "$R/fns.sh"
    for x in "$@"; do run_if_present "$x" >>"$o.body" 2>&1; done
    finish >"$o" 2>&1; echo "frc=$? rc=$rc skipped=$SKIPPED" >>"$o" )
}
has(){ grep -qE -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }

# ===== A =====
rm -f "$T/a"*; run_case "$T/a" skip.sh
ok "A1 a suite exiting 77 does NOT fail the run: rc stays 0, verdict green (frc=0)" "$(has $T/a '^frc=0 rc=0 skipped=1$')"
ok "A2 ...and the final summary LISTS the skipped suite" "$(has $T/a 'SKIPPED SUITES \(1, not failures\): skip.sh')"
ok "A3 ...with the green banner, no FAILED banner" "$([ "$(has $T/a 'ALL QUEUE TESTS PASS')" = 1 ] && [ "$(has $T/a 'SOME QUEUE TESTS FAILED')" = 0 ] && echo 1 || echo 0)"
ok "A4 the run body says SKIPPED (not NOT RUN / FAILED)" "$(has $T/a.body 'SKIPPED: skip.sh exited 77')"
rm -f "$T/a2"*; run_case "$T/a2" ok.sh skip.sh ok.sh
ok "A5 passes around a skip stay green, the skip is still listed" "$([ "$(has $T/a2 '^frc=0 rc=0 skipped=1$')" = 1 ] && [ "$(has $T/a2 'SKIPPED SUITES.*skip.sh')" = 1 ] && echo 1 || echo 0)"

# ===== B =====
rm -f "$T/b"*; run_case "$T/b" bad.sh skip.sh
ok "B1 a suite exiting 1 still fails the run (frc=1 rc=1)" "$(has $T/b '^frc=1 rc=1 skipped=1$')"
ok "B2 ...and NAMES ITSELF in FAILED SUITES" "$(has $T/b '^FAILED SUITES: bad.sh$')"
ok "B3 ...the skipped one is not in the failed list but is listed as skipped" "$([ "$(has $T/b '^FAILED SUITES:.*skip.sh')" = 0 ] && [ "$(has $T/b 'SKIPPED SUITES.*skip.sh')" = 1 ] && echo 1 || echo 0)"
ok "B4 verdict banner is the FAILED one" "$(has $T/b 'SOME QUEUE TESTS FAILED')"
rm -f "$T/b2"*; run_case "$T/b2" nosuch.sh ok.sh
ok "B5 a registered-but-absent file is a listed skip, not a failure" "$([ "$(has $T/b2 '^frc=0 rc=0 skipped=1$')" = 1 ] && [ "$(has $T/b2 'SKIPPED SUITES.*nosuch.sh')" = 1 ] && echo 1 || echo 0)"

# ===== C: a red run can never have an empty, silent list =====
rm -f "$T/c"*; ( cd "$R" || exit 99; . "$R/fns.sh"; rc=1; finish >"$T/c" 2>&1; echo "frc=$?" >>"$T/c" )
ok "C1 rc=1 with nothing recorded: finish says so explicitly (rc named) instead of printing no FAILED SUITES line" "$([ "$(has $T/c 'FAILED SUITES: \(none recorded: rc=1')" = 1 ] && [ "$(has $T/c 'SOME QUEUE TESTS FAILED')" = 1 ] && [ "$(has $T/c '^frc=1$')" = 1 ] && echo 1 || echo 0)"

# ===== D =====
rm -f "$T/d"*; OVN_RUN_IF_PRESENT_77=fail run_case "$T/d" skip.sh
ok "D1 OVN_RUN_IF_PRESENT_77=fail restores the old mapping (77 -> rc=1)" "$(has $T/d '^frc=1 rc=1 skipped=0$')"

# ===== E: the cron wrapper, end to end with a stub run_all_sandboxed.sh that exits red with an EMPTY failed.tsv =====
H="$T/home"; QQ="$H/overnight-queue"; mkdir -p "$H/qtmp" "$QQ/state" "$QQ/scripts/test"
cat > "$QQ/scripts/test/run_all_sandboxed.sh" <<'STUB'
#!/usr/bin/env bash
printf '  ok   something\n  FAIL: the last failing check line\n' > "$OVN_SUITE_CAPTURE_DIR/zz_suite.sh.1.out"
exit 3
STUB
env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_SUITE_LOG="$H/qtmp/suite_cron.log" bash "$WR" >"$T/e.out" 2>&1; rc=$?
ok "E1 the wrapper returns the red rc" "$([ "$rc" = 3 ] && echo 1 || echo 0)"
ok "E2 the alerts.log WARN is not a bare 'rc=3': it carries the synthetic row (rc) and the last failing line" "$([ "$(has $QQ/state/alerts.log 'WARN \| qtests \| sandboxed suite rc=3 - failed: \(run_all rc=3\)')" = 1 ] && [ "$(has $QQ/state/alerts.log 'the last failing check line')" = 1 ] && echo 1 || echo 0)"
ok "E3 the suite-failure INFO names the run (rc=3), not an empty list" "$(has $QQ/state/alerts.log 'suite FAILED \(run_all rc=3\)')"

# ===== F =====
ok "F1 run_all.sh registers this test" "$(grep -qE '(bash|run_if_present) test_run_all_skip77\.sh' "$RA" && echo 1 || echo 0)"
ok "F2 test_q_z4_advisories.sh (the suite that exits 77 on the queue-only tree) is run through run_or_notrun (NOT-RUN on 77 or when absent; was run_if_present)" "$(grep -qE 'run_or_notrun test_q_z4_advisories\.sh' "$RA" && echo 1 || echo 0)"
ok "F3 run_if_present no longer contains the old '|| rc=1' mapping of the suite's rc" "$(grep '^run_if_present(){' "$RA" | grep -q 'bash "\$1" || rc=1' && echo 0 || echo 1)"

echo "test_run_all_skip77: $P passed, $F failed"
if [ -z "${RA_SRC:-}" ] && [ -z "${RA_NO_MUTANTS:-}" ]; then
  mutant(){   # <id> <file rel> <old> <new>
    local id="$1" M="$T/mut_$1"; rm -rf "$M"; mkdir -p "$M/scripts/test" "$M/ops"
    cp "$REAL_SRC/scripts/test/run_all.sh" "$M/scripts/test/"; cp "$REAL_SRC/ops/run_suite_sandboxed_cron.sh" "$M/ops/"
    OLD="$3" NEW="$4" F="$M/$2" python3 - <<'PY' || { ok "M$id mutation applied" 0; return; }
import os,sys
f=os.environ['F']; s=open(f).read(); o=os.environ['OLD']
if o not in s: sys.exit(1)
open(f,'w').write(s.replace(o,os.environ['NEW'],1))
PY
    RA_SRC="$M" RA_NO_MUTANTS=1 bash "$HERE/test_run_all_skip77.sh" >/dev/null 2>&1
    ok "M$id mutant is caught" "$([ $? != 0 ] && echo 1 || echo 0)"
  }
  mutant 1 scripts/test/run_all.sh '[ "$_rip" -eq 77 ] && [ "${OVN_RUN_IF_PRESENT_77:-skip}" != fail ]' 'false'
  mutant 2 scripts/test/run_all.sh 'SKIPPED_SUITES="${SKIPPED_SUITES:-} $1"; echo "  SKIPPED:' 'echo "  SKIPPED:'
  mutant 3 scripts/test/run_all.sh 'else echo "FAILED SUITES: (none recorded' 'else : "FAILED SUITES: (none recorded'
  mutant 4 ops/run_suite_sandboxed_cron.sh '"${_lastfail:-none found in the captures}"' '"none"'
  echo "test_run_all_skip77 (with mutants): $P passed, $F failed"
fi
[ "$F" = 0 ]
