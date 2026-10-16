#!/usr/bin/env bash
# [gutparity r11 hygiene-streak test: fixture copied from test_branch_hygiene_run.sh] Runs the REAL branch_hygiene.sh against throwaway bare origins + clones. Gate tools (pytest/npm/gradlew/godot/docker),
# curl and a git wrapper (to inject worktree failures) are stub executables first on PATH; HOME is a fake tree that holds a
# fake check_migrations.py. STATE_DIR/REPORT_FILE point into the fixture. Nothing real is touched or pushed.
export OVN_QA_SHADOW=off   # never launch the real QA shadow gates from a test (they would write fake-repo rows into production state)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
for t in flock timeout jq; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = 1 ]; then pass=$((pass+1)); else echo "  WARN KNOWN-BUG: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(mktemp -d)" || exit 1; export T; trap 'rm -rf "$T"' EXIT
REALGIT="$(type -P git)"; export REALGIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; export STATE_DIR="$T/state"; export REPORT_FILE="$T/report.md"; OUT="$T/out.log"
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
mkstub git 'if [ -n "${FAIL_WT:-}" ] && [ "$3" = worktree ] && [ "$4" = add ]; then case "$*" in *"$FAIL_WT"*) exit 1;; esac; fi
exec "$REALGIT" "$@"'
# npm: behaviour driven by marker files in the package dir (cwd)
mkstub npm 'echo "npm $* (cwd=$PWD)" >> "$T/npm.log"
case "$1 $2" in
  "ci --no-audit"*|"install --no-audit"*) exit 0;;
  "run build") [ -f build_slow.flag ] && { sleep 5; exit 0; }; [ -f build_red.flag ] && exit 1; exit 0;;
esac
[ "$1" = test ] && { [ -f test_red.flag ] && exit 1; exit 0; }
exit 0'
# pytest in the clone's .venv; count calls; red.flag => fail; slow_once.flag => hang on first call only
PYTEST_BODY='echo "pytest $*" >> "$T/pytest.log"; echo "cwd=$PWD" >> "$T/pytest.log"
if [ -f slow_first.flag ]; then c="$T/slowcount"; n=$(cat "$c" 2>/dev/null || echo 0); echo $((n+1)) > "$c"; [ "$n" = 0 ] && sleep 6; fi
if [ -f slow_always.flag ]; then sleep 6; fi
[ -f red.flag ] && { echo "FAILED pkg/test_x.py::test_foo_streak - AssertionError: nope"; echo "1 failed in 0.1s"; exit 1; }; echo ". passed"; exit 0'
mkstub docker 'echo "docker $*" >> "$T/docker.log"; [ "$1" = build ] && { [ -f "$PWD/docker_red.flag" ] && exit 1; [ -f "$PWD/docker_slow.flag" ] && sleep 6; }; exit 0'

setup(){ # fresh fixture tree
  rm -rf "${T:?}/home" "${T:?}/origin" "${T:?}/seed" "${T:?}/repos" "${T:?}/state" "${T:?}/report.md" "${T:?}"/*.log "${T:?}/slowcount" "${T:?}/godot_mode"
  mkdir -p "$HOME/overnight-queue/scripts" "$T/origin" "$T/seed" "$T/repos" "$STATE_DIR"
  cat > "$HOME/overnight-queue/scripts/check_migrations.py" <<'PY'
import os, sys
if os.path.exists(os.path.expanduser("~/mig_fail")): sys.exit(1)
PY
  unset FAIL_WT HYGIENE_MERGE_TARGET HYGIENE_FEATURE_BRANCH AUTO_MERGE_DEFAULT DRY_RUN KEEP_DAYS TEST_TIMEOUT OVN_XDIST_REPOS HYGIENE_LOCK_WAIT NTFY_TOPIC LOCK_ALERT_COOLDOWN_SECS
}
# mk <name> <kind> [nfeat]: kinds (files on main so every branch has them): py | none | web | webnotest | vscode | gradle | godot | shellbad | docker | dockerchg
mk(){
  local n="$1" kind="$2" nf="${3:-2}" o="$T/origin/$1.git" s="$T/seed/$1" i
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt
    case "$kind" in
      py) mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py;;
      web) mkdir -p web; echo '{"scripts":{"build":"x","test":"y"}}' > web/package.json;;
      webnotest) mkdir -p web; echo '{"scripts":{"build":"x"}}' > web/package.json;;
      webtestonly) mkdir -p web; echo '{"scripts":{"test":"y"}}' > web/package.json;;
      webnone) mkdir -p web; echo '{"scripts":{}}' > web/package.json;;
      vscode) mkdir -p vscode-extension; echo '{"scripts":{"build":"x","test":"y"}}' > vscode-extension/package.json;;
      gradle) mkdir -p android; printf '#!/bin/sh\necho "gradlew $*" >> "$T/gradle.log"\nif [ -f ../gradle_daemon.flag ] && [ ! -f "$T/gd_done" ]; then touch "$T/gd_done"; echo "Gradle build daemon disappeared unexpectedly"; exit 1; fi\n[ -f ../gradle_red.flag ] && exit 1\nexit 0\n' > android/gradlew; chmod +x android/gradlew; echo "" > android/settings.gradle.kts;;
      godot) echo "x" > project.godot; mkdir -p addons/gut; echo "x" > addons/gut/gut_cmdln.gd;;
      shellbad) echo 'if then fi ((' > bad.sh;;
      shellok) echo 'echo hi' > good.sh;;
      docker|dockerchg) mkdir -p svc; echo "FROM scratch" > svc/Dockerfile;;
    esac
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature
    for i in $(seq 1 "$nf"); do echo "feat$i" > "feat$i.txt"; git add -A; git commit -q -m "feat: $i"; done
    git push -q origin overnight/feature
    git checkout -q develop; git branch claude/feature; git push -q origin claude/feature
    [ "$kind" = dockerchg ] && { git checkout -q overnight/feature; echo "RUN echo hi" >> svc/Dockerfile; git commit -qam "docker change"; git push -q origin overnight/feature; } )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  git -C "$T/repos/$n" config user.email t@t; git -C "$T/repos/$n" config user.name t
  [ "$kind" = py ] && { mkdir -p "$T/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$T/repos/$n/.venv/bin/pytest"; chmod +x "$T/repos/$n/.venv/bin/pytest"; }
  return 0
}
flagfile(){ # commit a marker file onto overnight/feature (so the worktree of the feature branch has it)
  local n="$1" f="$2" sub="${3:-.}" s="$T/seed/$1"; ( cd "$s"; git checkout -q overnight/feature; mkdir -p "$sub"; echo 1 > "$sub/$f"; git add -A; git commit -q -m "flag $f"; git push -q origin overnight/feature; git checkout -q develop ); git -C "$T/repos/$n" fetch -q origin; }
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$T" && PATH="$BIN:$PATH" bash "$BH" "$@" > "$OUT" 2>&1 ); echo $? > "$T/rc"; }
merged(){ git -C "$T/origin/$1.git" merge-base --is-ancestor "${3:-overnight/feature}" "${2:-develop}" && echo 1 || echo 0; }
flag(){ echo "$STATE_DIR/branch_hygiene_review_$1"; }


# diagnostics on failure (the last hygiene output + alerts.log tail), so a load-dependent flake is explainable instead of a bare FAIL line
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; echo "    --- last hygiene output:"; tail -n 12 "$OUT" 2>/dev/null | sed 's/^/    | /'; echo "    --- alerts.log tail:"; tail -n 5 "$STATE_DIR/alerts.log" 2>/dev/null | sed 's/^/    | /'; fi; }
alerts(){ cat "$STATE_DIR/alerts.log" 2>/dev/null; }
# NO `cmd | grep -q` anywhere in the assertions (pipefail + an early-exiting grep is SIGPIPE-flaky under load: 6 concurrent runs failed 1-2 assertions each with the right
# text on screen): capture to a variable and match a here-string (no pipe).
ahas(){ local t; t="$(cat "$STATE_DIR/alerts.log" 2>/dev/null)"; grep -qE -- "$1" <<< "$t"; }     # ERE
afirst(){ local t; t="$(sed -n 1p "$STATE_DIR/alerts.log" 2>/dev/null)"; grep -qE -- "$1" <<< "$t"; }
alast(){ local t; t="$(tail -n 1 "$STATE_DIR/alerts.log" 2>/dev/null)"; grep -qE -- "$1" <<< "$t"; }
nalerts(){ local n; n="$(grep -c "hygiene-gate-streak:$1" "$STATE_DIR/alerts.log" 2>/dev/null)"; echo "${n:-0}"; }
streakf(){ ls "$STATE_DIR/hygiene_gate_streak/" 2>/dev/null | tr '\n' ' '; }
mkgodot(){ mkdir -p "$HOME/godot"; cat > "$HOME/godot/godot4" <<'G'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
case " $* " in *" --import "*) exit 0;; esac
[ -n "${xml:-}" ] || exit 0
if [ "$(cat "$T/godot_mode" 2>/dev/null)" = red ]; then
  printf '%s' '<testsuites name="GutTests" failures="1" tests="3001" ><testsuite name="tests/test_orphan_save_manager.gd" failures="1"><testcase name="test_orphan_save_manager_does_not_exist" status="fail" classname="tests/test_orphan_save_manager.gd"><failure message="failed"/></testcase></testsuite></testsuites>' > "$xml"
else echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml"; fi
exit 0
G
chmod +x "$HOME/godot/godot4"; }

echo "== pytest lane: 5 consecutive gate failures (the xlite shape) =="
setup; mk app py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none
run "$T/repos/app"; run "$T/repos/app"
ok "pass 1-2 failed: NO alert yet (streak 2 < 3)" "$([ "$(nalerts app)" = 0 ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "pass 3 failed: exactly ONE warn line" "$([ "$(nalerts app)" = 1 ] && ahas '\] warn \| hygiene-gate-streak:app \|' && echo 1 || echo 0)"
ok "the alert says 3 consecutive passes, names the lane and the target" "$(ahas 'FAILED 3 consecutive passes for app overnight/feature' && ahas 'reaches develop' && echo 1 || echo 0)"
ok "the alert names the failing TEST (extracted from the gate output)" "$(ahas 'pkg/test_x.py::test_foo_streak' && echo 1 || echo 0)"
ok "alerts.log line format matches the other alerts: '[YYYY-mm-dd HH:MM:SS] warn | tag | msg'" "$(ahas '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] warn \| hygiene-gate-streak:app \| ' && echo 1 || echo 0)"
run "$T/repos/app"; run "$T/repos/app"
ok "pass 4-5: NO further alert (dedup per streak)" "$([ "$(nalerts app)" = 1 ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "pass 6: ONE crit line" "$([ "$(nalerts app)" = 2 ] && ahas '\] crit \| hygiene-gate-streak:app \| hygiene gate FAILED 6 consecutive' && echo 1 || echo 0)"
run "$T/repos/app"; run "$T/repos/app"
ok "pass 7-8: still exactly warn + crit (no spam)" "$([ "$(nalerts app)" = 2 ] && echo 1 || echo 0)"
ok "streak state is per (repo, branch)" "$(case "$(streakf)" in *app__overnight_feature*) true;; *) false;; esac && echo 1 || echo 0)"
ok "(the existing per-run behaviour is unchanged: not merged, flagged)" "$([ "$(merged app develop)" = 0 ] && grep -q 'gate FAILED' "$(flag app)" && echo 1 || echo 0)"
# fix the lane: remove the red flag on the feature branch -> green gate -> merged, streak reset
( cd "$T/seed/app" && git checkout -q overnight/feature && git rm -q red.flag && git commit -q -m "fix" && git push -q origin overnight/feature && git checkout -q develop ); git -C "$T/repos/app" fetch -q origin
run "$T/repos/app"
ok "green gate: merged AND the streak file is gone (reset)" "$([ "$(merged app develop)" = 1 ] && [ -z "$(streakf)" ] && echo 1 || echo 0)"
n_before="$(nalerts app)"
# a new failure after the fix starts a NEW streak: 2 reds -> no alert
( cd "$T/seed/app" && git checkout -q overnight/feature && echo 1 > red.flag && git add -A && git commit -q -m "red again" && git push -q origin overnight/feature && git checkout -q develop ); git -C "$T/repos/app" fetch -q origin
run "$T/repos/app"; run "$T/repos/app"
ok "NEGATIVE-control: a fresh streak after a green pass needs 3 again (2 reds -> no new alert)" "$([ "$(nalerts app)" = "$n_before" ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "... and the 3rd red of the NEW streak alerts again (dedup is per streak)" "$([ "$(nalerts app)" = "$((n_before + 1))" ] && echo 1 || echo 0)"

echo "== a streak ends when the lane is fixed out of band (nothing ahead any more) =="
setup; mk app py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none
run "$T/repos/app"; run "$T/repos/app"; run "$T/repos/app"
ok "(setup) 3 failed passes -> 1 warn + a streak file" "$([ "$(nalerts app)" = 1 ] && [ -n "$(streakf)" ] && echo 1 || echo 0)"
( cd "$T/seed/app" && git checkout -q develop && git merge -q --ff-only overnight/feature && git push -q origin develop ); git -C "$T/repos/app" fetch -q origin
run "$T/repos/app"
ok "lane fixed out of band (feature already in develop, ahead==0): the streak file is removed" "$([ -z "$(streakf)" ] && [ "$(has $OUT 'already in develop')" = 1 ] && echo 1 || echo 0)"
( cd "$T/seed/app" && git checkout -q overnight/feature && echo 2 > red.flag && git add -A && git commit -q -m "red again" && git push -q origin overnight/feature && git checkout -q develop ); git -C "$T/repos/app" fetch -q origin
run "$T/repos/app"; run "$T/repos/app"
ok "a later failure starts a NEW streak (2 reds: still just the first warn)" "$([ "$(nalerts app)" = 1 ] && echo 1 || echo 0)"

echo "== kill switch / dry run / gate-unavailable =="
setup; mk app py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none
for i in 1 2 3 4; do OVN_HYG_STREAK_ALERT=off run "$T/repos/app"; done
ok "OVN_HYG_STREAK_ALERT=off: no alert, no state" "$([ "$(nalerts app)" = 0 ] && [ -z "$(streakf)" ] && echo 1 || echo 0)"
for i in 1 2 3 4; do DRY_RUN=1 run "$T/repos/app"; done; unset DRY_RUN
ok "DRY_RUN=1 never writes the streak or an alert" "$([ "$(nalerts app)" = 0 ] && [ -z "$(streakf)" ] && echo 1 || echo 0)"
setup; mk app none 1
for i in 1 2 3 4; do run "$T/repos/app"; done
ok "BENIGN: 'no build/test gate available' (g=2) is not a gate failure: no streak alert" "$([ "$(nalerts app)" = 0 ] && echo 1 || echo 0)"
setup; mk app py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none
for i in 1 2 3 4 5 6; do OVN_HYG_STREAK_WARN=2 OVN_HYG_STREAK_CRIT=4 run "$T/repos/app"; done
ok "thresholds are tunable: WARN=2 CRIT=4 -> warn after 2 and crit after 4 (exactly 2 lines)" "$([ "$(nalerts app)" = 2 ] && afirst 'warn \| hygiene-gate-streak:app \| hygiene gate FAILED 2 ' && alast 'crit \| .*FAILED 4 ' && echo 1 || echo 0)"
setup; mk app py 2; mk other py 2; flagfile app red.flag; export OVN_XDIST_REPOS=none
for i in 1 2 3; do run "$T/repos/app" "$T/repos/other"; done
ok "lanes are independent: the red repo alerts, the green repo does not" "$([ "$(nalerts app)" = 1 ] && [ "$(nalerts other)" = 0 ] && echo 1 || echo 0)"

echo "== GUT lane: the failing test comes from the junit report =="
setup; mk app godot 1; mkgodot; echo red > "$T/godot_mode"
for i in 1 2 3; do run "$T/repos/app"; done
ok "GUT red x3: ONE warn naming the failing GUT test id" "$([ "$(nalerts app)" = 1 ] && ahas 'tests/test_orphan_save_manager.gd::test_orphan_save_manager_does_not_exist' && echo 1 || echo 0)"
setup; mk app godot 1; mkgodot; echo ok > "$T/godot_mode"
for i in 1 2 3; do run "$T/repos/app"; done
ok "BENIGN: a green GUT lane never alerts" "$([ "$(nalerts app)" = 0 ] && echo 1 || echo 0)"

echo; echo "gutparity r11 hygiene: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
