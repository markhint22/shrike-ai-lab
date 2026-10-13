#!/usr/bin/env bash
# [package qa, 2026-10-13, platform-night P1] The xlite GUT gate output is KEPT like the pytest gate's: logs/hygiene_gate/<ts>.<repo>.gut.<rand>, with a pointer line in the hygiene log when the
# gate FAILED, removed again when the gate is green, pruned by age, capped in size, OVN_HYGIENE_GATE_GUT_KEEP=off disables. Real branch_hygiene.sh against throwaway repos (fixture copied from
# test_gutparity_r11_hygiene.sh); fake godot4 prints a mode-dependent GUT/compile transcript.
# curl and a git wrapper (to inject worktree failures) are stub executables first on PATH; HOME is a fake tree that holds a
# fake check_migrations.py. STATE_DIR/REPORT_FILE point into the fixture. Nothing real is touched or pushed.
export OVN_QA_SHADOW=off   # never launch the real QA shadow gates from a test (they would write fake-repo rows into production state)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
for t in flock timeout jq; do type -P $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = 1 ]; then pass=$((pass+1)); else echo "  WARN KNOWN-BUG: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(mktemp -d)"; export T; trap 'rm -rf "$T"' EXIT
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
  rm -rf "$T/home" "$T/origin" "$T/seed" "$T/repos" "$T/state" "$T/report.md" "$T"/*.log "$T/slowcount" "$T/godot_mode"
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
case " $* " in *" --import "*) [ "$(cat "$T/godot_mode" 2>/dev/null)" = import ] && echo "IMPORT-SCAN-MARK SCRIPT ERROR: Parse Error: Identifier \"foo\" not declared in the current scope."; exit 0;; esac
[ -n "${xml:-}" ] || exit 0
mode="$(cat "$T/godot_mode" 2>/dev/null)"
echo "GUT-TRANSCRIPT-MARK start"
case "$mode" in
  red) echo "res://tests/test_orphan_save_manager.gd"; echo "  [Failed]: test_orphan_save_manager_does_not_exist"
       printf '%s' '<testsuites name="GutTests" failures="1" tests="3001"><testsuite name="tests/test_orphan_save_manager.gd" failures="1"><testcase name="test_orphan_save_manager_does_not_exist" status="fail" classname="tests/test_orphan_save_manager.gd"><failure message="failed"/></testcase></testsuite></testsuites>' > "$xml";;
  compile) echo "SCRIPT ERROR: Parse Error: Cannot find member \"REINFORCEMENTS\" in base \"MissionDirective\"."; echo "   at: GDScript::reload (res://tests/mission/test_mission_directive.gd:12)"
       echo "ERROR: Failed to load script \"res://tests/mission/test_mission_directive.gd\" with error \"Parse error\"."
       echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml";;
  big) i=0; while [ $i -lt 5000 ]; do echo "line $i of a very chatty GUT run"; i=$((i+1)); done; echo "BIG-TAIL-MARK"
       printf '%s' '<testsuites failures="1" tests="2"><testsuite name="t.gd" failures="1"><testcase name="test_x" status="fail" classname="t.gd"><failure message="f"/></testcase></testsuite></testsuites>' > "$xml";;
  *) echo "Totals: 3001 passed"; echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml";;
esac
exit 0
G
chmod +x "$HOME/godot/godot4"; }
GD="$T/gatedir"; export OVN_HYGIENE_GATE_DIR="$GD"
gutfiles(){ ls "$GD" 2>/dev/null | grep -E '\.app\.gut\.' || true; }
ngut(){ local n; n="$(gutfiles | grep -c . || true)"; echo "${n:-0}"; }
firstgut(){ local f; f="$(gutfiles | head -n 1)"; [ -n "$f" ] && echo "$GD/$f"; }

echo "== GUT red: the raw GUT output survives and the hygiene log points at it =="
setup; mk app godot 1; mkgodot; echo red > "$T/godot_mode"
run "$T/repos/app"
ok "ONE kept file named <ts>.app.gut.<rand> in logs/hygiene_gate" "$([ "$(ngut)" = 1 ] && echo 1 || echo 0)"
ok "the kept file holds the GUT transcript (the failing test line)" "$([ -n "$(firstgut)" ] && grep -q 'Failed\]: test_orphan_save_manager_does_not_exist' "$(firstgut)" && echo 1 || echo 0)"
ok "the hygiene log says where it is" "$([ "$(has "$OUT" 'gate GUT output kept in')" = 1 ] && [ "$(has "$OUT" "$(firstgut)")" = 1 ] && echo 1 || echo 0)"
ok "(the existing behaviour is unchanged: not merged, flagged)" "$([ "$(merged app develop)" = 0 ] && grep -q 'gate FAILED' "$(flag app)" && echo 1 || echo 0)"

echo "== load/compile scan trips (the 2026-10-13 xlite incident shape): the compile error is in the kept file =="
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo compile > "$T/godot_mode"
run "$T/repos/app"
ok "kept file exists and holds the parse error + the 'Failed to load script' line" "$([ "$(ngut)" = 1 ] && grep -q 'Cannot find member "REINFORCEMENTS"' "$(firstgut)" && grep -q 'Failed to load script' "$(firstgut)" && echo 1 || echo 0)"
ok "the pointer line is logged for the compile failure too" "$([ "$(has "$OUT" 'gate GUT output kept in')" = 1 ] && echo 1 || echo 0)"

echo "== godot --import scan trips (reviewer fix: this early return used to delete the output unkept) =="
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo import > "$T/godot_mode"
run "$T/repos/app"
ok "the import-scan trip fails the gate (not merged, flagged)" "$([ "$(merged app develop)" = 0 ] && grep -q 'gate FAILED' "$(flag app)" && echo 1 || echo 0)"
ok "ONE kept file holding the import-scan parse error" "$([ "$(ngut)" = 1 ] && [ -n "$(firstgut)" ] && grep -q 'IMPORT-SCAN-MARK SCRIPT ERROR: Parse Error' "$(firstgut)" && echo 1 || echo 0)"
ok "the pointer line is logged for the import-scan failure too" "$([ "$(has "$OUT" 'gate GUT output kept in')" = 1 ] && [ "$(has "$OUT" "$(firstgut)")" = 1 ] && echo 1 || echo 0)"

echo "== stub-leak streak files are per lane: a pass with nothing ahead clears ONLY its own lane's file =="
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo ok > "$T/godot_mode"
mkdir -p "$STATE_DIR/stub_leak_streak"; echo "123 3 1" > "$STATE_DIR/stub_leak_streak/app__claude_feature"; echo "123 3 1" > "$STATE_DIR/stub_leak_streak/app__overnight_feature"
HYGIENE_FEATURE_BRANCH=claude/feature run "$T/repos/app"
ok "claude/feature has nothing ahead (in sync): its stale streak file (n=3 alerted=1) is removed" "$([ "$(has "$OUT" 'already in')" = 1 ] && [ ! -e "$STATE_DIR/stub_leak_streak/app__claude_feature" ] && echo 1 || echo 0)"
ok "... and the OTHER lane's streak file is untouched" "$([ -e "$STATE_DIR/stub_leak_streak/app__overnight_feature" ] && echo 1 || echo 0)"

echo "== green gate keeps nothing =="
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo ok > "$T/godot_mode"
run "$T/repos/app"
ok "GUT green: merged and NO .gut. file left behind" "$([ "$(merged app develop)" = 1 ] && [ "$(ngut)" = 0 ] && [ "$(has "$OUT" 'gate GUT output kept in')" = 0 ] && echo 1 || echo 0)"

echo "== kill switch / pruning / size cap =="
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo red > "$T/godot_mode"
OVN_HYGIENE_GATE_GUT_KEEP=off run "$T/repos/app"
ok "OVN_HYGIENE_GATE_GUT_KEEP=off: nothing kept, no pointer line (gate still FAILED)" "$([ "$(ngut)" = 0 ] && [ "$(has "$OUT" 'gate GUT output kept in')" = 0 ] && grep -q 'gate FAILED' "$(flag app)" && echo 1 || echo 0)"
setup; rm -rf "$GD"; mkdir -p "$GD"; mk app godot 1; mkgodot; echo red > "$T/godot_mode"
: > "$GD/20200101-000000.app.gut.OLDOLD"; touch -t 202001010000 "$GD/20200101-000000.app.gut.OLDOLD"
run "$T/repos/app"
ok "a kept file older than OVN_HYGIENE_GATE_KEEP_DAYS (3) is pruned on the next keep; the new one stays" "$([ ! -e "$GD/20200101-000000.app.gut.OLDOLD" ] && [ "$(ngut)" = 1 ] && echo 1 || echo 0)"
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo big > "$T/godot_mode"
OVN_HYGIENE_GATE_GUT_TAIL=300 run "$T/repos/app"
ok "a 5000-line transcript is capped (head 200 + omitted marker + tail 300, the tail keeps the end)" "$([ -n "$(firstgut)" ] && [ "$(wc -l < "$(firstgut)" | tr -d ' ')" -le 520 ] && grep -q 'BIG-TAIL-MARK' "$(firstgut)" && grep -q 'GUT output lines omitted' "$(firstgut)" && echo 1 || echo 0)"
setup; rm -rf "$GD"; mk app godot 1; mkgodot; echo red > "$T/godot_mode"
run "$T/repos/app"; run "$T/repos/app"
ok "a second pass keeps its OWN file (one per failed pass, pruned by age - not overwritten)" "$([ "$(ngut)" = 2 ] && echo 1 || echo 0)"

echo; echo "hygiene gut keep n2: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
