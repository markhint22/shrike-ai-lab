#!/usr/bin/env bash
# test_q_infra_red_fix.sh - package q-infra-gates review fixes (2026-11-11): INFRA-RED must not hide a real red lane.
#   A. matcher: a signature only counts in infra context (Caused by:/What-went-wrong block/banner line) and NEVER beside test-failure markers (reviewer repro: a failing test that prints
#      `expected java.io.IOException: error=2` was INFRA-RED)
#   B. ovn_gradle_run with a stub gradlew: that repro is an ordinary red (1 run, no stop, not INFRA-RED)
#   C. consecutive INFRA-RED counter helper
#   D. REAL branch_hygiene.sh: first OVN_HYG_INFRA_RED_MAX (3) passes are INFRA-RED (no flag/streak), pass 4 falls through to a normal red (review flag + gate streak, crit alert, never merged),
#      any other verdict resets the count, the real-red repro is red on pass 1
#   E. `./gradlew --stop` serialization: skipped (after the wait) while another gradle client is active, the retry still happens; flock actually serializes
#   F. daemon match is java-only: a non-java process with the GradleDaemon class in argv and a deleted exe is NOT listed and NOT signalled (guard --stop with a stub kill)
#   G. run_all.sh: a missing registered suite via run_or_notrun is NOT-RUN (not silently skipped); test_q_z4_advisories.sh and this suite are registered with run_or_notrun
# Mutants (each must make this suite FAIL): M1 test-marker check removed, M2 context check removed, M3 no fall-through, M4 counter never reset, M5 crit -> warn, M6 stop ignores other clients,
#   M7 stop without flock, M8 deleted-daemon match not java-only, M9 bare GradleDaemon argv match, M10 run_or_notrun missing file not NOT-RUN, M11 counter not incremented, M12 z4 advisories back to run_if_present.
# bash >= 4 + flock + timeout + git (exit 77 = NOT RUN elsewhere). Hermetic: sandbox HOME, stub gradlew, fake /proc, no ntfy, never signals a real process.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for t in flock timeout git python3; do type -P $t >/dev/null || { echo "  NOT RUN: no $t"; exit 77; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  NOT RUN: needs bash >= 4"; exit 77; }
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
export TZ=UTC OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9
REAL_SRC="$(cd "$HERE/../.." && pwd)"
SRC="${GI_SRC:-$REAL_SRC}"
[ -f "$SRC/scripts/lib_gradle_infra.sh" ] && [ -f "$SRC/branch_hygiene.sh" ] && [ -f "$SRC/ops/gradle_daemon_guard.sh" ] && [ -f "$SRC/scripts/test/run_all.sh" ] || { echo "  FAIL: package files missing under $SRC"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir irf)" || exit 1; export T
trap 'safe_rm_rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset OVN_GRADLE_INFRA_RETRY OVN_GRADLE_INFRA_ALERT_SEC OVN_GRADLE_PROC_ROOT OVN_HYG_STREAK_ALERT HYGIENE_GATE_ONLY DRY_RUN HYGIENE_FEATURE_BRANCH OVN_HYG_INFRA_RED_MAX OVN_GRADLE_STOP_LOCK
export OVN_GRADLE_STOP_WAIT=0
safe_set_sandbox_home "$T" || exit 1; mkdir -p "$HOME/android-sdk"
. "$SRC/scripts/lib_gradle_infra.sh"
log(){ :; }

mkgradlew(){   # <dir>
  mkdir -p "$1"; : > "$1/settings.gradle"
  cat > "$1/gradlew" <<'STUB'
#!/usr/bin/env bash
c="${GCNT:?}"; m="$(cat "${GMODE_FILE:?}" 2>/dev/null)"
if [ "${1:-}" = "--stop" ]; then echo x >> "$c.stops"; echo fixed > "$c.fixed"; exit 0; fi
echo x >> "$c.runs"
case "$m" in
  ok)      echo "BUILD SUCCESSFUL"; exit 0;;
  red)     echo "FAILED: com.x.FooTest > bar FAILED"; echo "BUILD FAILED"; exit 1;;
  once)    if [ -f "$c.fixed" ]; then echo "BUILD SUCCESSFUL"; exit 0; fi; echo "java.io.IOException: Cannot run program java: error=0, Failed to exec spawn helper: exit value 1"; exit 1;;
  persist) echo "AAPT2 aapt2-8.1: Daemon startup failed"; exit 1;;
  quoted)  echo "FAILED: MyTest.testSpawn"; echo "  expected java.io.IOException: error=2, No such file or directory"; echo "  Daemon startup failed"; echo "BUILD FAILED"; exit 1;;
esac
exit 0
STUB
  chmod +x "$1/gradlew"
}
cnt(){ [ -f "$GCNT.$1" ] && wc -l < "$GCNT.$1" | tr -d ' ' || echo 0; }
newc(){ rm -f "$T/c".*; export GCNT="$T/c" GMODE_FILE="$T/mode"; echo "$1" > "$T/mode"; }
isinfra(){ printf '%s\n' "$@" > "$T/txt"; ovn_gradle_infra_text "$T/txt" && echo 1 || echo 0; }

# ===== A: matcher =====
ok "A0 sanity: a Caused-by infra line alone IS infra" "$(isinfra 'noise' 'Caused by: java.io.IOException: error=2, No such file or directory')"
ok "A1 reviewer repro (FAILED test line + mid-line 'expected java.io.IOException: error=2') is NOT infra" "$([ "$(isinfra 'FAILED: MyTest.testSpawn' '  expected java.io.IOException: error=2, No such file or directory')" = 0 ] && echo 1 || echo 0)"
ok "A2 'Class > method FAILED' beside a Caused-by infra line is NOT infra (test failure => ordinary RED)" "$([ "$(isinfra 'com.x.FooTest > bar FAILED' '    Caused by: java.io.IOException: error=2, No such file or directory' 'BUILD FAILED')" = 0 ] && echo 1 || echo 0)"
ok "A3 '5 tests completed, 1 failed' beside a spawn-helper banner is NOT infra" "$([ "$(isinfra '5 tests completed, 1 failed' 'Failed to exec spawn helper: exit value 1')" = 0 ] && echo 1 || echo 0)"
ok "A4 a signature quoted mid-line (no test markers, no infra context) is NOT infra" "$([ "$(isinfra 'log: earlier the build said Could not connect to the Gradle daemon once' 'BUILD FAILED')" = 0 ] && echo 1 || echo 0)"
ok "A5 a signature inside a '* What went wrong:' block IS infra" "$(isinfra '* What went wrong:' "Execution failed for task ':app:processDebugResources'." '> Process aapt2 failed: see: the Daemon startup failed there' '* Try:')"
ok "A6 the same text AFTER '* Try:' is not in the block (NOT infra)" "$([ "$(isinfra '* What went wrong:' 'something else' '* Try:' '> Run with --stacktrace: Daemon startup failed in the middle')" = 0 ] && echo 1 || echo 0)"
ok "A7 a JUnit <failure> marker beside an infra line is NOT infra" "$([ "$(isinfra '<failure message="x">' 'Caused by: java.io.IOException: error=12, Cannot allocate memory')" = 0 ] && echo 1 || echo 0)"
ok "A8 'There were failing tests' beside an AAPT2 line is NOT infra" "$([ "$(isinfra '> There were failing tests. See the report' 'AAPT2 aapt2: Daemon startup failed')" = 0 ] && echo 1 || echo 0)"

# ===== B: ovn_gradle_run =====
G="$T/proj"; mkgradlew "$G"; OUTF="$T/out"; export OVN_GRADLE_PROC_ROOT="$T/noproc"
newc quoted; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B1 reviewer repro through ovn_gradle_run: rc 1, ONE run, no stop, OVN_GRADLE_INFRA_RED=0 (ordinary red)" "$([ $rc = 1 ] && [ "$(cnt runs)" = 1 ] && [ "$(cnt stops)" = 0 ] && [ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"
newc persist; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B2 a genuine infra persist is still INFRA-RED (2 runs, 1 stop)" "$([ $rc != 0 ] && [ "$(cnt runs)" = 2 ] && [ "$(cnt stops)" = 1 ] && [ "$OVN_GRADLE_INFRA_RED" = 1 ] && echo 1 || echo 0)"

# ===== C: counter helper =====
CS="$T/cstate"; mkdir -p "$CS"
a="$(ovn_gradle_infra_red_count "$CS" r feature/x inc)"; b="$(ovn_gradle_infra_red_count "$CS" r feature/x inc)"; g="$(ovn_gradle_infra_red_count "$CS" r feature/x get)"
ok "C1 inc,inc,get = 1,2,2" "$([ "$a $b $g" = "1 2 2" ] && echo 1 || echo 0)"
o="$(ovn_gradle_infra_red_count "$CS" r other/lane get)"; ok "C2 lanes are independent" "$([ "$o" = 0 ] && echo 1 || echo 0)"
ovn_gradle_infra_red_count "$CS" r feature/x reset >/dev/null; ok "C3 reset" "$([ "$(ovn_gradle_infra_red_count "$CS" r feature/x get)" = 0 ] && echo 1 || echo 0)"
SDA="$T/alst"; mkdir -p "$SDA"; ovn_gradle_infra_alert "$SDA" lbl "m1"; ovn_gradle_infra_alert "$SDA" lbl "m2" crit; ovn_gradle_infra_alert "$SDA" lbl "m3" crit
ok "C4 warn and crit have their own hourly slots; crit row carries level crit" "$([ "$(grep -c 'warn | gradle-infra-red | lbl' "$SDA/alerts.log")" = 1 ] && [ "$(grep -c 'crit | gradle-infra-red | lbl' "$SDA/alerts.log")" = 1 ] && echo 1 || echo 0)"

# ===== D: the REAL branch_hygiene.sh =====
Q="$HOME/overnight-queue"; BIN="$T/bin"; mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs" "$BIN"
cp "$SRC/branch_hygiene.sh" "$Q/"; for f in lib_lock.sh lib_pytest_parallel.sh lib_gut_xml.sh lib_tree_guard.sh lib_gradle_infra.sh; do [ -f "$SRC/scripts/$f" ] && cp "$SRC/scripts/$f" "$Q/scripts/"; done
mk(){   # state (the counter) is kept across passes unless $1 = fresh
  local o="$T/origin/app.git" s="$T/seed/app"
  rm -rf "${o:?}" "${s:?}" "${Q:?}/repos/app" "${T:?}/report.md"; [ "${1:-}" = fresh ] && rm -rf "${Q:?}/state"; mkdir -p "$T/origin" "$T/seed" "$Q/state"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main; git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature; mkgradlew "$s/android"; echo feat > feat.txt; git add -A; git commit -q -m "feat: work"; git push -q origin overnight/feature )
  git clone -q "$o" "$Q/repos/app" 2>/dev/null; git -C "$Q/repos/app" checkout -q overnight/feature
}
sha(){ git -C "$T/origin/app.git" rev-parse --verify -q "$1" 2>/dev/null; true; }
run(){ ( cd "$Q" && HYGIENE_MERGE_TARGET=develop REPORT_FILE="$T/report.md" PATH="$BIN:$PATH" bash ./branch_hygiene.sh repos/app > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
OUT="$T/out.log"; REP="$T/report.md"; ST="$Q/state"
STREAK="$ST/hygiene_gate_streak/app__overnight_feature"; FLAG="$ST/branch_hygiene_review_app"; AL="$ST/alerts.log"; CF="$ST/gradle_infra_red_count/app__overnight_feature"
streak_n(){ [ -f "$STREAK" ] && cut -d' ' -f1 "$STREAK" || echo 0; }
cfn(){ [ -f "$CF" ] && cat "$CF" || echo 0; }
export OVN_GRADLE_PROC_ROOT="$T/noproc"

mk fresh; d0="$(sha develop)"; newc quoted; run
ok "D1 reviewer repro is a plain red on pass 1: gate FAILED, review flag, streak 1, NOT infra-red, no counter" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ -s "$FLAG" ] && [ "$(streak_n)" = 1 ] && [ "$(has $OUT 'gate INFRA-RED')" = 0 ] && [ "$(cfn)" = 0 ] && [ "$(cnt runs)" = 1 ] && echo 1 || echo 0)"
mk fresh; d0="$(sha develop)"; newc persist
for i in 1 2 3; do run; done
ok "D2 passes 1-3 are INFRA-RED: counter 3, no flag, no streak, develop untouched, no crit" "$([ "$(cfn)" = 3 ] && [ ! -e "$FLAG" ] && [ ! -e "$STREAK" ] && [ "$(sha develop)" = "$d0" ] && [ "$(grep -c '| crit |' "$AL" 2>/dev/null)" = 0 ] && echo 1 || echo 0)"
run
ok "D3 pass 4 FALLS THROUGH to a normal red: gate FAILED, review flag written, streak 1" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(has $OUT 'INFRA-RED budget exhausted')" = 1 ] && [ -s "$FLAG" ] && [ "$(streak_n)" = 1 ] && echo 1 || echo 0)"
ok "D4 ... a crit gradle-infra-red alert is raised, and the lane is still never merged" "$([ "$(grep -c 'crit | gradle-infra-red | app:overnight/feature' "$AL")" = 1 ] && [ "$(sha develop)" = "$d0" ] && [ "$(has $REP 'needs review')" = 1 ] && echo 1 || echo 0)"
run
ok "D5 pass 5: still red, streak 2 (flag + streak keep ovn_hygiene_stuck_check / streak WARN-CRIT firing), crit not repeated within the hour" "$([ "$(streak_n)" = 2 ] && [ -s "$FLAG" ] && [ "$(grep -c 'crit | gradle-infra-red' "$AL")" = 1 ] && echo 1 || echo 0)"
mk fresh; newc persist; run; run; newc red; run
ok "D6 a non-infra verdict (real red) between INFRA-RED passes RESETS the counter" "$([ "$(cfn)" = 0 ] && echo 1 || echo 0)"
newc persist; run; run; run
ok "D7 ... so 3 more INFRA-RED passes are again unscored (counter 3, streak stays 1 from the red)" "$([ "$(cfn)" = 3 ] && [ "$(streak_n)" = 1 ] && echo 1 || echo 0)"
mk fresh; newc persist; run; run; newc ok; run
ok "D8 a green pass resets the counter and merges" "$([ "$(cfn)" = 0 ] && [ "$(has $OUT 'MERGED app')" = 1 ] && echo 1 || echo 0)"
mk fresh; newc persist; OVN_HYG_INFRA_RED_MAX=1 run; OVN_HYG_INFRA_RED_MAX=1 run
ok "D9 OVN_HYG_INFRA_RED_MAX=1: second pass already falls through to a red" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ -s "$FLAG" ] && echo 1 || echo 0)"

# D10/D11: unwritable counter dir fails SAFE toward escalation (restore perms in a trap)
trap 'chmod -R u+rwx "$ST/gradle_infra_red_count" 2>/dev/null; safe_rm_rf "$T"' EXIT
mk fresh; d0="$(sha develop)"; newc persist; mkdir -p "$ST/gradle_infra_red_count"; chmod 555 "$ST/gradle_infra_red_count"
if ( : > "$ST/gradle_infra_red_count/.w" ) 2>/dev/null; then rm -f "$ST/gradle_infra_red_count/.w"; echo "ok - D10/D11 skipped (dir stays writable, running as root)"
else
  for i in 1 2 3 4 5 6; do run; done
  ok "D10 counter unwritable, 6 passes: review flag + streak written (escalated, no stuck INFRA-RED), never merged" "$([ -s "$FLAG" ] && [ "$(streak_n)" -ge 1 ] && [ "$(sha develop)" = "$d0" ] && echo 1 || echo 0)"
  ok "D11 the flag text says INFRA-RED persisted N passes" "$([ "$(has "$FLAG" 'INFRA-RED persisted')" -ge 1 ] && echo 1 || echo 0)"
fi
chmod -R u+rwx "$ST/gradle_infra_red_count" 2>/dev/null

# ===== E: --stop serialization =====
FP="$T/fakeproc"; rm -rf "$FP"; mkdir -p "$FP/500"
printf 'bash\0./gradlew\0test\0' > "$FP/500/cmdline"; ln -s /bin/bash "$FP/500/exe"
export OVN_GRADLE_PROC_ROOT="$FP" OVN_GRADLE_STOP_LOCK="$T/stop.lock"
ok "E1 an active gradle client (gradlew) is detected; daemons and unrelated processes are not" "$(mkdir -p "$FP/501" "$FP/502"; printf 'java\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/501/cmdline"; printf 'vim\0gradlew\0' > "$FP/502/cmdline"; [ "$(ovn_gradle_active_clients | tr '\n' ' ')" = "500 " ] && echo 1 || echo 0)"
rm -rf "$FP/501" "$FP/502"
newc once; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "E2 infra once while another client is active: NO ./gradlew --stop, the single retry still runs (2 runs, 0 stops)" "$([ "$(cnt stops)" = 0 ] && [ "$(cnt runs)" = 2 ] && echo 1 || echo 0)"
rm -rf "$FP/500"
newc once; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "E3 no other client: the stop runs and the retry passes (1 stop, rc 0)" "$([ $rc = 0 ] && [ "$(cnt stops)" = 1 ] && [ "$(cnt runs)" = 2 ] && echo 1 || echo 0)"
# flock really serializes: a background holder keeps the lock ~3 s; the stop must wait for it
( flock "$OVN_GRADLE_STOP_LOCK" sleep 3 ) & hp=$!
sleep 1; newc once; t0=$(date +%s); ovn_gradle_run "$G" "$OUTF" 20 >/dev/null; t1=$(date +%s)
wait $hp 2>/dev/null
ok "E4 the stop waits for the flock holder (>= 2 s) and then still runs" "$([ $((t1 - t0)) -ge 2 ] && [ "$(cnt stops)" = 1 ] && echo 1 || echo 0)"
export OVN_GRADLE_PROC_ROOT="$T/noproc"

# ===== F: java-only daemon match =====
FP="$T/fakeproc2"; rm -rf "$FP"; mkdir -p "$FP/100" "$FP/200" "$FP/300" "$FP/400"
printf 'java\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/100/cmdline"; ln -s "/usr/lib/jvm/java-17/bin/java (deleted)" "$FP/100/exe"            # real broken daemon
printf 'python3\0tool.py\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/200/cmdline"; ln -s "/usr/bin/python3 (deleted)" "$FP/200/exe"               # NOT java, deleted exe
printf 'java\0-jar\0x.jar\0GradleDaemon\0' > "$FP/300/cmdline"; ln -s "/usr/lib/jvm/java-17/bin/java (deleted)" "$FP/300/exe"                                    # java, bare 'GradleDaemon' arg only
printf 'tail\0-f\0/var/log/org.gradle.launcher.daemon.bootstrap.GradleDaemon.log\0' > "$FP/400/cmdline"; ln -s "/usr/bin/tail (deleted)" "$FP/400/exe"          # non-java mentioning the class
export OVN_GRADLE_PROC_ROOT="$FP"
ok "F1 only the java process with the daemon main class and a deleted exe is listed (pid 100)" "$([ "$(ovn_gradle_deleted_daemons | tr '\n' ' ')" = "100 " ] && echo 1 || echo 0)"
printf '#!/usr/bin/env bash\necho "$@" >> "%s"\n' "$T/kills" > "$T/killstub"; chmod +x "$T/killstub"; rm -f "$T/kills" "$T/guard.log"
OVN_GRADLE_GUARD_LOG="$T/guard.log" OVN_GRADLE_GUARD_KILL_CMD="$T/killstub" bash "$SRC/ops/gradle_daemon_guard.sh" --stop >/dev/null 2>&1
ok "F2 guard --stop signals exactly pid 100 - never the non-java processes (pids 200/300/400)" "$([ "$(cat "$T/kills" 2>/dev/null)" = "100" ] && echo 1 || echo 0)"
rm -rf "$FP/100"; rm -f "$T/kills" "$T/guard.log"
OVN_GRADLE_GUARD_LOG="$T/guard.log" OVN_GRADLE_GUARD_KILL_CMD="$T/killstub" bash "$SRC/ops/gradle_daemon_guard.sh" --stop >/dev/null 2>&1
ok "F3 with ONLY the non-java look-alikes present nothing is signalled" "$([ ! -e "$T/kills" ] && echo 1 || echo 0)"
export OVN_GRADLE_PROC_ROOT="$T/noproc"

# ===== G: run_all registration / NOT-RUN =====
RA="$SRC/scripts/test/run_all.sh"
ok "G1 test_q_z4_advisories.sh is registered with run_or_notrun (not run_if_present)" "$(grep -qE '^echo; .*run_or_notrun test_q_z4_advisories\.sh' "$RA" && ! grep -qE 'run_if_present test_q_z4_advisories\.sh' "$RA" && echo 1 || echo 0)"
ok "G2 this suite is registered with run_or_notrun" "$(grep -qE 'run_or_notrun test_q_infra_red_fix\.sh' "$RA" && echo 1 || echo 0)"
FN="$(grep '^run_or_notrun(){' "$RA")"
r="$( cd "$T" && NOTRUN=0 rc=0; eval "$FN"; run_or_notrun test_absent_zz.sh; echo "notrun=$NOTRUN rc=$rc" )"
ok "G3 run_or_notrun on a MISSING suite is NOT-RUN (counted, loud), rc untouched" "$(case "$r" in *"NOT RUN: test_absent_zz.sh"*"notrun=1 rc=0") echo 1;; *) echo 0;; esac)"
printf 'exit 77\n' > "$T/test_p77.sh"; printf 'exit 1\n' > "$T/test_f1.sh"
r="$( cd "$T" && NOTRUN=0 rc=0; eval "$FN"; run_or_notrun test_p77.sh >/dev/null; n77=$NOTRUN; run_or_notrun test_f1.sh >/dev/null; echo "n77=$n77 rc=$rc" )"
ok "G4 exit-77 prerequisite skip still maps to NOT-RUN and a real failure still sets rc=1" "$([ "$r" = "n77=1 rc=1" ] && echo 1 || echo 0)"

echo "test_q_infra_red_fix: $P passed, $F failed"

# ===== M: mutants (only against the real tree) =====
if [ -z "${GI_SRC:-}" ] && [ -z "${GI_NO_MUTANTS:-}" ]; then
  mutant(){   # <id> <file under the tree> <old> <new>
    local id="$1" f="$2" M="$T/mut_$1"; rm -rf "$M"; mkdir -p "$M/scripts/test" "$M/ops"
    cp "$REAL_SRC/branch_hygiene.sh" "$M/"; cp "$REAL_SRC"/scripts/lib_*.sh "$M/scripts/"; cp "$REAL_SRC/ops/gradle_daemon_guard.sh" "$M/ops/"; cp "$REAL_SRC/scripts/test/run_all.sh" "$M/scripts/test/"
    OLD="$3" NEW="$4" F="$M/$f" python3 - <<'PY' || { ok "M$id mutation applied" 0; return; }
import os,sys
f=os.environ['F']; s=open(f).read(); o=os.environ['OLD']
if o not in s: sys.exit(1)
open(f,'w').write(s.replace(o,os.environ['NEW'],1))
PY
    GI_SRC="$M" GI_NO_MUTANTS=1 bash "$HERE/test_q_infra_red_fix.sh" >/dev/null 2>&1
    ok "M$id mutant is caught (suite fails against it)" "$([ $? != 0 ] && echo 1 || echo 0)"
  }
  mutant 1 scripts/lib_gradle_infra.sh 'grep -aqE "$_OVN_GRADLE_TESTFAIL_RE" "$1" 2>/dev/null && return 1' ':'
  mutant 2 scripts/lib_gradle_infra.sh '($0 ~ ENVIRON["OVN_GI_SIG"]) && (wb || $0 ~ ENVIRON["OVN_GI_CTX"])' '($0 ~ ENVIRON["OVN_GI_SIG"])'
  mutant 3 branch_hygiene.sh 'if [ "$_ir_n" -le "$_ir_max" ]; then g=4' 'if true; then g=4'
  mutant 4 branch_hygiene.sh 'elif [ "$DRY_RUN" != 1 ]; then ovn_gradle_infra_red_count' 'elif false; then ovn_gradle_infra_red_count'
  mutant 5 branch_hygiene.sh 'needs a human" crit' 'needs a human" warn'
  mutant 6 scripts/lib_gradle_infra.sh 'if [ -n "$(ovn_gradle_active_clients)" ]; then' 'if false; then'
  mutant 7 scripts/lib_gradle_infra.sh 'flock -w 120 9 || exit 2' ':'
  mutant 8 scripts/lib_gradle_infra.sh 'case "$exe" in java*) echo "$pid";; esac' 'case "$exe" in *) echo "$pid";; esac'
  mutant 9 scripts/lib_gradle_infra.sh 'case "$cmd" in *org.gradle.launcher.daemon.bootstrap.GradleDaemon*) ;; *) continue;; esac' 'case "$cmd" in *GradleDaemon*) ;; *) continue;; esac'
  mutant 10 scripts/test/run_all.sh 'if [ ! -f "$1" ]; then NOTRUN=$((NOTRUN+1));' 'if false; then NOTRUN=$((NOTRUN+1));'
  mutant 11 scripts/lib_gradle_infra.sh '    n=$((n + 1))' '    n=$((n + 0))'
  mutant 12 scripts/test/run_all.sh 'run_or_notrun test_q_z4_advisories.sh' 'run_if_present test_q_z4_advisories.sh'
  mutant 13 scripts/lib_gradle_infra.sh '[ "$n" -gt "$mx" ] || n=$((mx + 1))' ':'
  mutant 14 branch_hygiene.sh '${_ir_fall:+; $_ir_fall}' ''
  echo "test_q_infra_red_fix (with mutants): $P passed, $F failed"
fi
[ "$F" = 0 ]
