#!/usr/bin/env bash
# test_q_gradle_infra.sh - package q-infra-gates (2026-11-11): gradle host-infra classification (finding 1 of nov11_health) + ops/gradle_daemon_guard.sh.
# Incident: unattended-upgrades replaced openjdk-17 under a live Gradle daemon; every child spawn failed ("Failed to exec spawn helper"); the iptv_apps hygiene gate was scored RED for 9 h.
#   A. signature matcher (5 signatures + a genuine test failure is NOT infra; OVN_GRADLE_INFRA_RETRY=off disables)
#   B. ovn_gradle_run with a stub gradlew: clean -> 1 run; real red -> 1 run, no stop, not INFRA-RED; infra once -> --stop + retry passes; infra persists -> exactly 2 runs, 1 stop, INFRA-RED; off switch -> 1 run
#   C. deleted-exe daemon preflight (fake /proc tree): only a GradleDaemon whose exe is "(deleted)" is found, stopped before the build; healthy daemons / other deleted-exe java are ignored
#   D. ovn_gradle_infra_alert: one warn per label per interval, distinct key gradle-infra-red
#   E. REAL branch_hygiene.sh end to end: INFRA-RED = no streak, no flag, nothing merged, alert once, neutral report; infra-once merges; a genuine red is still red; switch off = old red
#   G. ops/gradle_daemon_guard.sh: shadow logs only; --stop signals exactly the deleted-exe GradleDaemon pids (stub kill), never anything else; refuses a real kill under a fake proc root
# Mutants (each must make this suite FAIL): M1 no retry, M2 INFRA-RED never set, M3 hygiene scores INFRA-RED as red, M4 alert not deduped, M5 deleted-exe test matches any daemon, M6 guard shadow still kills,
#   M7 signature list drops 'Failed to exec spawn helper', M8 hygiene merges on INFRA-RED.
# bash >= 4 + flock + timeout + git (exit 77 = NOT RUN elsewhere). Hermetic: sandbox HOME, stub gradlew, fake /proc, no ntfy.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for t in flock timeout git; do type -P $t >/dev/null || { echo "  NOT RUN: no $t"; exit 77; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  NOT RUN: needs bash >= 4"; exit 77; }
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
export TZ=UTC OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9
REAL_SRC="$(cd "$HERE/../.." && pwd)"
SRC="${GI_SRC:-$REAL_SRC}"
[ -f "$SRC/scripts/lib_gradle_infra.sh" ] && [ -f "$SRC/branch_hygiene.sh" ] && [ -f "$SRC/ops/gradle_daemon_guard.sh" ] || { echo "  FAIL: package files missing under $SRC"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir giq)" || exit 1; export T
trap 'safe_rm_rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset OVN_GRADLE_INFRA_RETRY OVN_GRADLE_INFRA_ALERT_SEC OVN_GRADLE_PROC_ROOT OVN_HYG_STREAK_ALERT HYGIENE_GATE_ONLY DRY_RUN HYGIENE_FEATURE_BRANCH
safe_set_sandbox_home "$T" || exit 1; mkdir -p "$HOME/android-sdk"
. "$SRC/scripts/lib_gradle_infra.sh"
log(){ :; }   # the lib logs through log() when it exists: keep the suite output clean

# ---- stub gradlew: behaviour from $GMODE_FILE; counts runs/stops in $GCNT.{runs,stops}; `--stop` clears the "broken daemon" state
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
  persist2) echo "Could not connect to the Gradle daemon"; exit 1;;
  persist3) echo "Unable to start the daemon process."; exit 1;;
  persist4) echo "Caused by: java.io.IOException: error=12, Cannot allocate memory"; exit 1;;
  persist5) echo "Caused by: java.io.IOException: error=2, No such file or directory"; exit 1;;
esac
exit 0
STUB
  chmod +x "$1/gradlew"
}
cnt(){ [ -f "$GCNT.$1" ] && wc -l < "$GCNT.$1" | tr -d ' ' || echo 0; }
newc(){ rm -f "$T/c".*; export GCNT="$T/c" GMODE_FILE="$T/mode"; echo "$1" > "$T/mode"; }

# ===== A: matcher =====
for sig in 'Failed to exec spawn helper' 'AAPT2 aapt2-8.1-1: Daemon startup failed' 'Could not connect to the Gradle daemon' 'Caused by: java.io.IOException: error=2, No such file' 'Caused by: java.io.IOException: error=12, Cannot allocate' 'Unable to start the daemon process.'; do
  printf '%s\n' "noise" "$sig" > "$T/sig"
  ok "A1 signature matched: $sig" "$(ovn_gradle_infra_text "$T/sig" && echo 1 || echo 0)"
done
printf '%s\n' "com.x.FooTest > bar FAILED" "java.io.IOException: error=22, Invalid argument" "BUILD FAILED" > "$T/sig"
ok "A2 a genuine test failure / unrelated IOException is NOT infra" "$(ovn_gradle_infra_text "$T/sig" && echo 0 || echo 1)"
printf 'Failed to exec spawn helper\n' > "$T/sig"
ok "A3 OVN_GRADLE_INFRA_RETRY=off disables the classification" "$(OVN_GRADLE_INFRA_RETRY=off ovn_gradle_infra_text "$T/sig" && echo 0 || echo 1)"

# ===== B: ovn_gradle_run =====
G="$T/proj"; mkgradlew "$G"; OUTF="$T/out"
export OVN_GRADLE_PROC_ROOT="$T/noproc"   # no fake daemons here (section C builds its own)
newc ok; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B1 clean build: rc 0, one run, no stop, not INFRA-RED" "$([ $rc = 0 ] && [ "$(cnt runs)" = 1 ] && [ "$(cnt stops)" = 0 ] && [ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"
newc red; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B2 genuine test failure: rc 1, ONE run, no stop, not INFRA-RED (still a code red)" "$([ $rc = 1 ] && [ "$(cnt runs)" = 1 ] && [ "$(cnt stops)" = 0 ] && [ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"
newc once; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B3 infra once: ./gradlew --stop then a retry that passes -> rc 0, 2 runs, 1 stop, not INFRA-RED" "$([ $rc = 0 ] && [ "$(cnt runs)" = 2 ] && [ "$(cnt stops)" = 1 ] && [ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"
ok "B3b the output records the stop+retry" "$(has $OUTF 'infra signature; ./gradlew --stop and retry once')"
for m in persist persist2 persist3 persist4 persist5; do
  newc $m; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
  ok "B4($m) infra persists: rc != 0, EXACTLY 2 runs and 1 stop, INFRA-RED=1" "$([ $rc != 0 ] && [ "$(cnt runs)" = 2 ] && [ "$(cnt stops)" = 1 ] && [ "$OVN_GRADLE_INFRA_RED" = 1 ] && echo 1 || echo 0)"
done
ok "B4b the output says INFRA-RED" "$(has $OUTF 'INFRA-RED')"
newc persist; OVN_GRADLE_INFRA_RETRY=off ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "B5 switch off: one run, no stop, not INFRA-RED (old behaviour)" "$([ $rc != 0 ] && [ "$(cnt runs)" = 1 ] && [ "$(cnt stops)" = 0 ] && [ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"
newc ok; OVN_GRADLE_INFRA_RED=1; ovn_gradle_run "$G" "$OUTF" 20
ok "B6 INFRA-RED is reset at the start of every run" "$([ "$OVN_GRADLE_INFRA_RED" = 0 ] && echo 1 || echo 0)"

# ===== C: deleted-exe preflight (fake /proc) =====
FP="$T/fakeproc"; rm -rf "$FP"; mkdir -p "$FP/100" "$FP/200" "$FP/300" "$FP/400"
printf 'java\0-XX:+X\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/100/cmdline"; ln -s "/usr/lib/jvm/java-17/bin/java (deleted)" "$FP/100/exe"   # the incident
printf 'java\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/200/cmdline"; ln -s "/usr/lib/jvm/java-17/bin/java" "$FP/200/exe"                      # healthy daemon
printf 'java\0-jar\0other.jar\0' > "$FP/300/cmdline"; ln -s "/usr/lib/jvm/java-17/bin/java (deleted)" "$FP/300/exe"                                              # other deleted java
printf 'bash\0build.sh\0' > "$FP/400/cmdline"; ln -s "/bin/bash" "$FP/400/exe"
export OVN_GRADLE_PROC_ROOT="$FP"
ok "C1 only the GradleDaemon with a deleted exe is found" "$([ "$(ovn_gradle_deleted_daemons | tr '\n' ' ')" = "100 " ] && echo 1 || echo 0)"
newc ok; ovn_gradle_run "$G" "$OUTF" 20; rc=$?
ok "C2 preflight: the deleted-exe daemon triggers ./gradlew --stop BEFORE the (single) build" "$([ $rc = 0 ] && [ "$(cnt stops)" = 1 ] && [ "$(cnt runs)" = 1 ] && [ "$(has $OUTF 'stopped daemon(s) on a deleted java binary (pid 100')" = 1 ] && echo 1 || echo 0)"
rm -rf "$FP/100"; newc ok; ovn_gradle_run "$G" "$OUTF" 20
ok "C3 with only healthy / non-gradle processes there is no preflight stop" "$([ "$(cnt stops)" = 0 ] && echo 1 || echo 0)"
export OVN_GRADLE_PROC_ROOT="$T/noproc"

# ===== D: alert dedupe =====
SD="$T/alertstate"; mkdir -p "$SD"
ovn_gradle_infra_alert "$SD" "iptv_apps:overnight/feature" "msg one"; ovn_gradle_infra_alert "$SD" "iptv_apps:overnight/feature" "msg two"
ok "D1 one warn per label per hour, key gradle-infra-red" "$([ "$(grep -c 'warn | gradle-infra-red | iptv_apps:overnight/feature' "$SD/alerts.log")" = 1 ] && echo 1 || echo 0)"
ovn_gradle_infra_alert "$SD" "iptv_apps:claude/feature" "msg three"
ok "D2 a different lane has its own hourly slot" "$([ "$(grep -c 'gradle-infra-red' "$SD/alerts.log")" = 2 ] && echo 1 || echo 0)"
OVN_GRADLE_INFRA_ALERT_SEC=0 ovn_gradle_infra_alert "$SD" "iptv_apps:overnight/feature" "msg four"
ok "D3 after the interval it warns again" "$([ "$(grep -c 'gradle-infra-red' "$SD/alerts.log")" = 3 ] && echo 1 || echo 0)"

# ===== E: the REAL branch_hygiene.sh =====
Q="$HOME/overnight-queue"; BIN="$T/bin"; mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs" "$BIN"
cp "$SRC/branch_hygiene.sh" "$Q/"; for f in lib_lock.sh lib_pytest_parallel.sh lib_gut_xml.sh lib_tree_guard.sh lib_gradle_infra.sh; do [ -f "$SRC/scripts/$f" ] && cp "$SRC/scripts/$f" "$Q/scripts/"; done
mk(){   # main == develop, overnight/feature = develop + 1 commit that adds a gradle project (stub gradlew); clone on overnight/feature
  local o="$T/origin/app.git" s="$T/seed/app"
  rm -rf "$o" "$s" "${Q:?}/repos/app" "${Q:?}/state" "${T:?}/report.md"; mkdir -p "$T/origin" "$T/seed" "$Q/state"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main; git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature; mkgradlew "$s/android"; echo feat > feat.txt; git add -A; git commit -q -m "feat: work"; git push -q origin overnight/feature )
  git clone -q "$o" "$Q/repos/app" 2>/dev/null; git -C "$Q/repos/app" checkout -q overnight/feature
}
sha(){ git -C "$T/origin/app.git" rev-parse --verify -q "$1" 2>/dev/null; true; }
run(){ ( cd "$Q" && HYGIENE_MERGE_TARGET=develop REPORT_FILE="$T/report.md" PATH="$BIN:$PATH" bash ./branch_hygiene.sh repos/app > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
OUT="$T/out.log"; REP="$T/report.md"; ST="$Q/state"
STREAK="$ST/hygiene_gate_streak/app__overnight_feature"; FLAG="$ST/branch_hygiene_review_app"; AL="$ST/alerts.log"
streak_n(){ [ -f "$STREAK" ] && cut -d' ' -f1 "$STREAK" || echo 0; }
export OVN_GRADLE_PROC_ROOT="$T/noproc"

mk; d0="$(sha develop)"; newc persist; run
ok "E1 INFRA-RED is logged as such" "$([ "$(has $OUT 'gate INFRA-RED')" = 1 ] && echo 1 || echo 0)"
ok "E2 not scored as a code failure: no 'gate FAILED', no review flag, no streak" "$([ "$(has $OUT 'gate FAILED')" = 0 ] && [ ! -e "$FLAG" ] && [ ! -e "$STREAK" ] && echo 1 || echo 0)"
ok "E3 nothing merged (conservative): develop untouched" "$([ "$(sha develop)" = "$d0" ] && echo 1 || echo 0)"
ok "E4 neutral report line" "$([ "$(has $REP 'gate INFRA-RED')" = 1 ] && [ "$(has $REP 'needs review')" = 0 ] && echo 1 || echo 0)"
ok "E5 the gate ran stop + exactly one retry (2 gradle runs, 1 stop)" "$([ "$(cnt runs)" = 2 ] && [ "$(cnt stops)" = 1 ] && echo 1 || echo 0)"
ok "E6 one WARN with the distinct key gradle-infra-red" "$([ "$(grep -c 'warn | gradle-infra-red | app:overnight/feature' "$AL" 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
ok "E7 the pass completes normally" "$([ "$(has $OUT 'branch hygiene complete')" = 1 ] && echo 1 || echo 0)"
run
ok "E8 a second pass in the same hour does not alert again (still 1 row), still unscored and unmerged" "$([ "$(grep -c 'gradle-infra-red' "$AL")" = 1 ] && [ ! -e "$STREAK" ] && [ ! -e "$FLAG" ] && [ "$(sha develop)" = "$d0" ] && echo 1 || echo 0)"
mk; newc once; run
ok "E9 infra once (cleared by ./gradlew --stop): the gate is green and the lane merges" "$([ "$(has $OUT 'MERGED app')" = 1 ] && git -C $T/origin/app.git merge-base --is-ancestor overnight/feature develop && [ ! -e "$AL" -o "$(grep -c gradle-infra-red "$AL" 2>/dev/null)" = 0 ] && echo 1 || echo 0)"
mk; newc red; run
ok "E10 a GENUINE red is still red: gate FAILED, flag, streak 1, one run, no stop, no infra alert" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ -s "$FLAG" ] && [ "$(streak_n)" = 1 ] && [ "$(cnt runs)" = 1 ] && [ "$(cnt stops)" = 0 ] && [ "$(has $OUT 'gate INFRA-RED')" = 0 ] && [ ! -s "$AL" ] && echo 1 || echo 0)"
mk; newc persist; OVN_GRADLE_INFRA_RETRY=off run
ok "E11 OVN_GRADLE_INFRA_RETRY=off restores the old scoring: plain red, one run" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(streak_n)" = 1 ] && [ "$(cnt runs)" = 1 ] && [ "$(has $OUT 'gate INFRA-RED')" = 0 ] && echo 1 || echo 0)"

# ===== G: ops/gradle_daemon_guard.sh =====
GG="$SRC/ops/gradle_daemon_guard.sh"; GL="$T/guard.log"; KL="$T/kills"
printf '#!/usr/bin/env bash\necho "$@" >> "%s"\n' "$KL" > "$T/killstub"; chmod +x "$T/killstub"
rm -rf "$FP"; mkdir -p "$FP/100" "$FP/200" "$FP/300"
printf 'java\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/100/cmdline"; ln -s "/j/bin/java (deleted)" "$FP/100/exe"
printf 'java\0org.gradle.launcher.daemon.bootstrap.GradleDaemon\0' > "$FP/200/cmdline"; ln -s "/j/bin/java" "$FP/200/exe"
printf 'java\0-jar\0x.jar\0' > "$FP/300/cmdline"; ln -s "/j/bin/java (deleted)" "$FP/300/exe"
rm -f "$KL" "$GL"; OVN_GRADLE_PROC_ROOT="$FP" OVN_GRADLE_GUARD_LOG="$GL" OVN_GRADLE_GUARD_KILL_CMD="$T/killstub" bash "$GG" >/dev/null 2>&1; rc=$?
ok "G1 shadow (no flag): logs the candidate, signals NOTHING, rc 0" "$([ $rc = 0 ] && [ ! -e "$KL" ] && [ "$(has $GL 'WOULD stop pid 100')" = 1 ] && [ "$(has $GL 'pid 200')" = 0 ] && [ "$(has $GL 'pid 300')" = 0 ] && echo 1 || echo 0)"
rm -f "$KL" "$GL"; OVN_GRADLE_PROC_ROOT="$FP" OVN_GRADLE_GUARD_LOG="$GL" OVN_GRADLE_GUARD_KILL_CMD="$T/killstub" bash "$GG" --stop >/dev/null 2>&1; rc=$?
ok "G2 --stop: TERM goes to exactly pid 100 (deleted-exe GradleDaemon) - not the healthy daemon, not other java" "$([ $rc = 0 ] && [ "$(cat "$KL" 2>/dev/null)" = "100" ] && [ "$(has $GL 'stopped pid 100')" = 1 ] && echo 1 || echo 0)"
rm -f "$KL" "$GL"; OVN_GRADLE_PROC_ROOT="$FP" OVN_GRADLE_GUARD_LOG="$GL" bash "$GG" --stop >/dev/null 2>&1
ok "G3 fake proc root without a stubbed kill: REFUSES to signal anything (a fake pid can never hit a real process)" "$([ ! -e "$KL" ] && [ "$(has $GL 'REFUSED to kill pid 100')" = 1 ] && echo 1 || echo 0)"
rm -rf "$FP/100"; rm -f "$KL" "$GL"; OVN_GRADLE_PROC_ROOT="$FP" OVN_GRADLE_GUARD_LOG="$GL" OVN_GRADLE_GUARD_KILL_CMD="$T/killstub" bash "$GG" --stop >/dev/null 2>&1; rc=$?
ok "G4 nothing to stop: rc 0, no signal" "$([ $rc = 0 ] && [ ! -e "$KL" ] && echo 1 || echo 0)"
OVN_GRADLE_PROC_ROOT="$FP" bash "$GG" --bogus >/dev/null 2>&1; ok "G5 unknown argument rejected (rc 64)" "$([ $? = 64 ] && echo 1 || echo 0)"

echo "test_q_gradle_infra: $P passed, $F failed"

# ===== M: mutants (only when run against the real tree: the child runs below set GI_SRC) =====
if [ -z "${GI_SRC:-}" ] && [ -z "${GI_NO_MUTANTS:-}" ]; then
  mutant(){   # <id> <file under the tree> <python replace old> <new>
    local id="$1" f="$2" M="$T/mut_$1"; rm -rf "$M"; mkdir -p "$M/scripts" "$M/ops"
    cp "$REAL_SRC/branch_hygiene.sh" "$M/"; cp "$REAL_SRC"/scripts/lib_*.sh "$M/scripts/"; cp "$REAL_SRC/ops/gradle_daemon_guard.sh" "$M/ops/"
    OLD="$3" NEW="$4" F="$M/$f" python3 - <<'PY' || { ok "M$id mutation applied" 0; return; }
import os,sys
f=os.environ['F']; s=open(f).read(); o=os.environ['OLD']
if o not in s: sys.exit(1)
open(f,'w').write(s.replace(o,os.environ['NEW'],1))
PY
    GI_SRC="$M" GI_NO_MUTANTS=1 bash "$HERE/test_q_gradle_infra.sh" >/dev/null 2>&1
    ok "M$id mutant is caught (suite fails against it)" "$([ $? != 0 ] && echo 1 || echo 0)"
  }
  mutant 1 scripts/lib_gradle_infra.sh 'ovn_gradle_infra_text "$out" || return "$rc"' 'return "$rc"'
  mutant 2 scripts/lib_gradle_infra.sh '    OVN_GRADLE_INFRA_RED=1
    echo "--- gradle-infra: INFRA-RED' '    OVN_GRADLE_INFRA_RED=0
    echo "--- gradle-infra: INFRA-RED'
  mutant 3 branch_hygiene.sh 'if [ "$_ir_n" -le "$_ir_max" ]; then g=4' 'if [ "$_ir_n" -le "$_ir_max" ]; then g=1'
  mutant 4 scripts/lib_gradle_infra.sh '  [ $((now - last)) -ge "$gap" ] || return 0' ':'
  mutant 5 scripts/lib_gradle_infra.sh 'case "$exe" in *"(deleted)"*) ;; *) continue;; esac' ':'
  mutant 6 ops/gradle_daemon_guard.sh '[ "$MODE" != enforce ]' '[ "$MODE" = never ]'
  mutant 7 scripts/lib_gradle_infra.sh 'Failed to exec spawn helper|' ''
  mutant 8 branch_hygiene.sh 'if [ "$_ir_n" -le "$_ir_max" ]; then g=4' 'if [ "$_ir_n" -le "$_ir_max" ]; then g=0'
  mutant 9 scripts/lib_gradle_infra.sh '[ "${OVN_GRADLE_INFRA_RETRY:-on}" = off ] && return 1' ':'
  echo "test_q_gradle_infra (with mutants): $P passed, $F failed"
fi
[ "$F" = 0 ]
