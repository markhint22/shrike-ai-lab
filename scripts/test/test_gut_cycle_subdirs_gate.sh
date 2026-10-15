#!/usr/bin/env bash
# test_gut_cycle_subdirs_gate.sh - 2026-10-13, package gate (INCIDENT: xlite overnight/feature held off develop 04:03-~08:00 because fleet commit ad33d45 added
# tests/mission/test_mission_directive.gd using MissionDirective.REINFORCEMENTS - the enum is MissionDirective.Directive - a Parse error).
#   branch_hygiene.sh's gate runs GUT with -ginclude_subdirs and treats 'Failed to load script|Failed to compile depended scripts' as red; run_overnight.sh's per-cycle
#   run_repo_verification ran GUT WITHOUT the flag, so the fleet never saw its own broken test; and the hygiene gate's silent early returns left the hygiene-gate-streak alert
#   with no failing test name.
# PART A  per-cycle verify (REAL run_overnight.sh run_repo_verification via lib_ro_core.sh, stub godot): a parse-broken tests/mission/x.gd is RED in the cycle that wrote it.
# PART B  hygiene gate (REAL branch_hygiene.sh, stub godot, throwaway bare origins): the reason is logged at both former silent returns and reaches the streak alert.
# Every NEGATIVE has a BENIGN control and a kill-switch case. Nothing real is touched or pushed.
export OVN_QA_SHADOW=off
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
ro_link scripts/lib_run_integrity.sh scripts/ovn_extract_failure.sh scripts/ovn_repeat_ids.py
ro_tasks '[]'
ro_source
set +e

# =====================================================================================================================================================================
echo "=== PART A: per-cycle verify (run_repo_verification) ==="
# stub godot: GUT only LOADS tests/<sub>/ scripts when -ginclude_subdirs is on the command line. Like the real GUT it then exits 0 with a GREEN junit xml (failures="0") and
# only prints the load error. Marker files in the cwd steer it: tests/mission/test_bad.gd (parse error), compile_only.flag (only 'Failed to compile depended scripts'),
# slow.flag (hang before writing the xml).
mkdir -p "$HOME/godot"
cat > "$HOME/godot/godot4" <<'EOF'
#!/bin/bash
echo "godot $*" >> "$T/godot.calls"
case "$*" in *--import*) exit 0;; esac
xml=""; for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
[ -n "$xml" ] || exit 0
[ -f slow.flag ] && exec /bin/sleep 6   # (not `sleep`: lib_ro_core.sh puts a no-op sleep stub first on PATH)
sub=0; case " $* " in *" -ginclude_subdirs "*) sub=1;; esac
if [ "$sub" = 1 ] && [ -f tests/mission/test_bad.gd ]; then
  echo 'SCRIPT ERROR: Parse Error: Cannot find member "REINFORCEMENTS" in base "MissionDirective".'
  echo '          at: GDScript::reload (res://tests/mission/test_bad.gd:12)'
  echo 'ERROR: Failed to load script "res://tests/mission/test_bad.gd" with error "Parse error".'
fi
[ -f compile_only.flag ] && echo 'ERROR: Failed to compile depended scripts.'
printf -- '---- Totals ----\nTests 9\n  Passing 9\n'
printf '<testsuites name="GutTests" failures="0" tests="9"><testsuite name="tests/test_ok.gd" failures="0"><testcase name="test_a" status="pass" classname="tests/test_ok.gd"/></testsuite></testsuites>' > "$xml"
exit 0
EOF
chmod +x "$HOME/godot/godot4"

task_log="$T/verify.task.log"; : > "$task_log"
V="$T/v"
newrepo(){ rm -rf "$V"; mkdir -p "$V/addons/gut" "$V/tests/mission"; cd "$V" || exit 1; git init -q; echo x > project.godot; echo x > addons/gut/gut_cmdln.gd
  printf 'extends GutTest\nfunc test_a():\n\tassert_true(true)\n' > tests/test_ok.gd; echo base > README
  git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; : > "$task_log"; rm -f "$T/godot.calls"; }
commit_all(){ git add -A; git commit -q -m c; AFTER_SHA="$(git rev-parse HEAD)"; }
gutcall(){ grep -- 'gut_cmdln.gd' "$T/godot.calls" 2>/dev/null | head -1; }

echo "--- A1. a parse-broken test under tests/<sub>/ is red in the cycle that wrote it"
newrepo; printf 'extends GutTest\nfunc test_x():\n\tassert_eq(MissionDirective.REINFORCEMENTS, 1)\n' > tests/mission/test_bad.gd; commit_all
r="$(run_repo_verification)"
eq "A1 NEGATIVE: tests/mission/test_bad.gd fails to load (junit green, GUT rc 0) -> verification FAILS (old code: pass, GUT never looked in tests/mission)" fail "$r"
log="$(cat "$task_log")"
has "A1 the task log names the script" "$log" '--- GUT LOAD/COMPILE FAILURE: SCRIPT ERROR: Parse Error: Cannot find member "REINFORCEMENTS" in base "MissionDirective". | ERROR: Failed to load script "res://tests/mission/test_bad.gd"'
ok "A1 exactly one gut suite-red mark (a hidden red: never baseline-subtracted as a known failure)" "$([ "$(grep -c '^--- verify-suite-red: gut in \. rc=1 ---$' "$task_log")" = 1 ] && echo 1 || echo 0)"
has "A1 the GUT run carries the recursion flag right after -gdir" "$(gutcall)" "-gdir=res://tests -ginclude_subdirs -gexit"
has "A1 the log names the flag" "$log" "--- verify: GUT run args: -gdir=res://tests -ginclude_subdirs -gexit ---"
has "A1 the header carries the REAL cap (not a stale 90s)" "$log" "--- verify: GUT tests in . (cap 60s) ---"
ok "A1 no stale 90s cap wording next to the real one" "$(grep -q 'GUT tests in .*90s cap' "$task_log" && echo 0 || echo 1)"

echo "--- A2. BENIGN controls"
newrepo; rm -f tests/mission/test_bad.gd; echo y > f; commit_all
eq "A2 BENIGN: no broken script -> pass" pass "$(run_repo_verification)"
ok "A2 BENIGN: a green run writes no LOAD/COMPILE marker" "$(grep -q 'GUT LOAD/COMPILE FAILURE' "$task_log" && echo 0 || echo 1)"
has "A2 BENIGN: the GUT run still recursed" "$(gutcall)" "-ginclude_subdirs"

echo "--- A3. kill switch OVN_GUT_SUBDIRS=off restores the old non-recursive run (parse-broken subdir test is then not seen)"
newrepo; printf 'extends GutTest\n' > tests/mission/test_bad.gd; commit_all
eq "A3 kill switch off: the broken subdir script is never loaded -> pass (documented old behaviour)" pass "$(OVN_GUT_SUBDIRS=off run_repo_verification)"
ok "A3 kill switch off: no -ginclude_subdirs on the GUT command" "$(grep -q include_subdirs "$T/godot.calls" && echo 0 || echo 1)"
has "A3 kill switch off: command is -gdir=res://tests -gexit" "$(gutcall)" "-gdir=res://tests -gexit"
has "A3 kill switch off: the args line shows no flag" "$(cat "$task_log")" "--- verify: GUT run args: -gdir=res://tests -gexit ---"

echo "--- A4. 'Failed to compile depended scripts' alone is red too (the old 'ERROR: Failed to load' pattern never matched it)"
newrepo; touch compile_only.flag; commit_all
eq "A4 NEGATIVE: only the compile-depended-scripts signature -> FAIL (old code: pass)" fail "$(run_repo_verification)"
has "A4 the marker carries the line" "$(cat "$task_log")" "--- GUT LOAD/COMPILE FAILURE: ERROR: Failed to compile depended scripts."

echo "--- A5. the per-cycle GUT run stays bounded (OVN_GUT_CYCLE_TIMEOUT)"
newrepo; touch slow.flag; commit_all
t0=$SECONDS; r="$(OVN_GUT_CYCLE_TIMEOUT=1 run_repo_verification)"; el=$((SECONDS - t0))
eq "A5 a hung GUT run is killed at the cap and the verification is red (no junit xml)" fail "$r"
ok "A5 ... in well under the 6s the stub would sleep (took ${el}s)" "$([ "$el" -lt 5 ] && [ "$el" -ge 1 ] && echo 1 || echo 0)"
newrepo; echo y > f; commit_all
r="$(OVN_GUT_CYCLE_TIMEOUT=banana run_repo_verification)"
has "A5 a non-numeric cap falls back to 60" "$(cat "$task_log")" "GUT tests in . (cap 60s) ---"
r="$(OVN_GUT_CYCLE_TIMEOUT=17 run_repo_verification)"
has "A5 a custom cap is shown in the header" "$(cat "$task_log")" "GUT tests in . (cap 17s) ---"


echo "--- A6. PARTIAL DEPLOY: a lib_gut_xml.sh that sources fine but predates gut_subdirs_flag / gut_load_failure_line must NOT fail open"
# rsync copies run_overnight.sh before scripts/lib_gut_xml.sh: for a moment the NEW script meets the OLD lib. `source lib || { fallback }` never fires (the source succeeds),
# so gut_subdirs_flag / gut_load_failure_line were undefined: no recursion flag, no load-failure scan -> a parse-broken tests/<sub> script PASSED the cycle.
stale_lib(){ awk '/^gut_(subdirs_flag|load_failure_line)\(\) \{/ { skip = 1 } !skip { print } skip && /^\}/ { skip = 0 }' "$1"; }
stale_lib "$RO_Q/scripts/lib_gut_xml.sh" > "$T/stale_lib.sh"
ok "A6 setup: the stale lib really lacks both new functions and keeps the old ones" "$(! grep -q 'gut_subdirs_flag()\|gut_load_failure_line()' "$T/stale_lib.sh" && grep -q 'gut_xml_green()' "$T/stale_lib.sh" && echo 1 || echo 0)"
unset -f gut_subdirs_flag gut_load_failure_line
rm -f "$T/tree/scripts/lib_gut_xml.sh"; cp "$T/stale_lib.sh" "$T/tree/scripts/lib_gut_xml.sh"
ro_source
ok "A6 setup: after sourcing the real script against the stale lib the helpers exist anyway (the guard defined them)" "$(declare -F gut_subdirs_flag >/dev/null && declare -F gut_load_failure_line >/dev/null && echo 1 || echo 0)"
newrepo; printf 'extends GutTest\nfunc test_x():\n\tassert_eq(MissionDirective.REINFORCEMENTS, 1)\n' > tests/mission/test_bad.gd; commit_all
r="$(run_repo_verification)"
eq "A6 NEGATIVE: new script + STALE lib: the parse-broken subdir test still FAILS the cycle (unguarded: pass = fails open)" fail "$r"
has "A6 the GUT run still carries the recursion flag" "$(gutcall)" "-gdir=res://tests -ginclude_subdirs -gexit"
has "A6 the load/compile marker still names the script" "$(cat "$task_log")" "--- GUT LOAD/COMPILE FAILURE:"
newrepo; echo y > f; commit_all
eq "A6 BENIGN: new script + stale lib, clean repo -> pass" pass "$(run_repo_verification)"
for _f in branch_hygiene.sh run_overnight.sh ovn_stage_runner.sh ovn_test_watch.sh scripts/ovn_test_collect_canary.sh; do
  _src="$RO_Q/$_f"; _n=0; _g=0
  for _fn in gut_subdirs_flag gut_load_failure_line; do
    grep -qE "\\\$\\($_fn( |\\))" "$_src" || continue   # this script does not call it
    _n=$((_n+1)); grep -qF "declare -F $_fn >/dev/null 2>&1 || $_fn(){" "$_src" && _g=$((_g+1))
  done
  ok "A6 $_f defines every GUT helper it calls when the lib lacks it (guards $_g of $_n)" "$([ "$_n" -ge 1 ] && [ "$_n" = "$_g" ] && echo 1 || echo 0)"
done
# restore the real lib for the rest of the run
unset -f gut_subdirs_flag gut_load_failure_line; rm -f "$T/tree/scripts/lib_gut_xml.sh"; ro_link scripts/lib_gut_xml.sh; ro_source

echo "--- A7. gut_load_failure_line pairs the reason with THE failing script (not the first Parse Error in the log)"
LIBG="$RO_Q/scripts/lib_gut_xml.sh"
cat > "$T/pair.log" <<'LOGEOF'
SCRIPT ERROR: Parse Error: Identifier "Foo" not declared in the current scope.
          at: GDScript::reload (res://src/other.gd:3)
SCRIPT ERROR: Parse Error: Cannot find member "REINFORCEMENTS" in base "MissionDirective".
          at: GDScript::reload (res://tests/mission/test_bad.gd:12)
ERROR: Failed to load script "res://tests/mission/test_bad.gd" with error "Parse error".
LOGEOF
out="$( . "$LIBG"; gut_load_failure_line "$T/pair.log" )"
ok "A7 NEGATIVE: the quoted reason is the one for res://tests/mission/test_bad.gd (old: the unrelated first Parse Error 'Foo')" "$([ "$out" = 'SCRIPT ERROR: Parse Error: Cannot find member "REINFORCEMENTS" in base "MissionDirective". | ERROR: Failed to load script "res://tests/mission/test_bad.gd" with error "Parse error".' ] && echo 1 || echo 0)"
cat > "$T/pair2.log" <<'LOGEOF'
SCRIPT ERROR: Parse Error: Reason for A.
          at: GDScript::reload (res://tests/a/test_a.gd:1)
ERROR: Failed to load script "res://tests/a/test_a.gd" with error "Parse error".
SCRIPT ERROR: Parse Error: Reason for B.
          at: GDScript::reload (res://tests/b/test_b.gd:1)
ERROR: Failed to load script "res://tests/b/test_b.gd" with error "Parse error".
LOGEOF
out="$( . "$LIBG"; gut_load_failure_line "$T/pair2.log" )"
ok "A7 BENIGN: two broken scripts -> the FIRST script is named with ITS reason" "$(case "$out" in *"Reason for A."*"test_a.gd"*) case "$out" in *"Reason for B"*|*test_b*) echo 0;; *) echo 1;; esac;; *) echo 0;; esac)"
printf 'SCRIPT ERROR: Parse Error: only reason, no at line.\nERROR: Failed to load script "res://tests/x/test_x.gd" with error "Parse error".\n' > "$T/pair3.log"
out="$( . "$LIBG"; gut_load_failure_line "$T/pair3.log" )"
ok "A7 no 'at:' line: falls back to the Parse Error before the failure line" "$(case "$out" in "SCRIPT ERROR: Parse Error: only reason, no at line. | ERROR: Failed to load script"*) echo 1;; *) echo 0;; esac)"
printf 'ERROR: Failed to compile depended scripts.\n' > "$T/pair4.log"
out="$( . "$LIBG"; gut_load_failure_line "$T/pair4.log" )"
ok "A7 compile-only signature (no path, no reason) is still reported alone" "$([ "$out" = 'ERROR: Failed to compile depended scripts.' ] && echo 1 || echo 0)"
printf 'Totals\n9 passed\nSCRIPT ERROR: Parse Error: benign unrelated\n' > "$T/pair5.log"
ok "A7 BENIGN: a Parse Error with no load failure is NOT a load failure (rc 1, no output)" "$( ( . "$LIBG"; gut_load_failure_line "$T/pair5.log" >/dev/null ) && echo 0 || echo 1)"

# =====================================================================================================================================================================
echo "=== PART B: branch_hygiene.sh gate ==="
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; ro_summary; exit $?; }
for t in flock timeout jq; do command -v $t >/dev/null || { echo "  SKIP part B: no $t"; ro_summary; exit $?; }; done
cd "$T" || exit 1
REALGIT="$(type -P git)"; export REALGIT
export HOME="$T/home"; export STATE_DIR="$T/state"; export REPORT_FILE="$T/report.md"; OUT="$T/out.log"
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
setupb(){
  rm -rf "$T/home" "$T/origin" "$T/seed" "$T/repos" "$T/state" "$T/report.md"
  mkdir -p "$HOME/overnight-queue/scripts" "$T/origin" "$T/seed" "$T/repos" "$STATE_DIR"
  cp "$HERE/../../scripts/ovn_extract_failure.sh" "$HOME/overnight-queue/scripts/" 2>/dev/null
  mkdir -p "$HOME/godot"; cat > "$HOME/godot/godot4" <<'G'
#!/usr/bin/env bash
echo "godot $*" >> "$T/godot.calls"
xml=""; for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
case " $* " in *" --import "*)
  [ -f "$PWD/import_bad.flag" ] && echo 'SCRIPT ERROR: Parse Error: Identifier "Foo" not declared in the current scope.'
  exit 0;; esac
[ -n "$xml" ] || exit 0
case " $* " in *" -ginclude_subdirs "*) sub=1;; *) sub=0;; esac
if [ "$sub" = 1 ] && [ -f "$PWD/tests/mission/test_bad.gd" ]; then
  echo 'SCRIPT ERROR: Parse Error: Cannot find member "REINFORCEMENTS" in base "MissionDirective".'
  echo '          at: GDScript::reload (res://tests/mission/test_bad.gd:12)'
  echo 'ERROR: Failed to load script "res://tests/mission/test_bad.gd" with error "Parse error".'
fi
echo '<testsuites><testsuite failures="0"/></testsuites>' > "$xml"
exit 0
G
  chmod +x "$HOME/godot/godot4"
  rm -f "$T/godot.calls"
  unset FAIL_WT HYGIENE_MERGE_TARGET HYGIENE_FEATURE_BRANCH AUTO_MERGE_DEFAULT DRY_RUN KEEP_DAYS TEST_TIMEOUT OVN_GUT_SUBDIRS OVN_HYG_STREAK_ALERT
}
mkgd(){ # name nfeat : a godot repo (project.godot + vendored GUT stub on main), feature branch with nfeat commits
  local n="$1" nf="${2:-2}" o="$T/origin/$1.git" s="$T/seed/$1" i
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; echo x > project.godot; mkdir -p addons/gut; echo x > addons/gut/gut_cmdln.gd
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature
    for i in $(seq 1 "$nf"); do echo "feat$i" > "feat$i.txt"; git add -A; git commit -q -m "feat: $i"; done
    git push -q origin overnight/feature
    git checkout -q develop; git branch claude/feature; git push -q origin claude/feature )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  git -C "$T/repos/$n" config user.email t@t; git -C "$T/repos/$n" config user.name t
}
flagfile(){ local n="$1" f="$2" sub="${3:-.}" s="$T/seed/$1"; ( cd "$s"; git checkout -q overnight/feature; mkdir -p "$sub"; echo 1 > "$sub/$f"; git add -A; git commit -q -m "flag $f"; git push -q origin overnight/feature; git checkout -q develop ); git -C "$T/repos/$n" fetch -q origin; }
run(){ ( cd "$T" && PATH="$BIN:$PATH" bash "$BH" "$@" > "$OUT" 2>&1 ); echo $? > "$T/rc"; }
merged(){ git -C "$T/origin/$1.git" merge-base --is-ancestor overnight/feature develop && echo 1 || echo 0; }
outhas(){ local t; t="$(cat "$OUT" 2>/dev/null)"; grep -qF -- "$1" <<< "$t"; }
alertshas(){ local t; t="$(cat "$STATE_DIR/alerts.log" 2>/dev/null)"; grep -qF -- "$1" <<< "$t"; }
bok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; echo "    --- last hygiene output:"; tail -n 10 "$OUT" 2>/dev/null | sed 's/^/    | /'; echo "    --- alerts.log:"; tail -n 3 "$STATE_DIR/alerts.log" 2>/dev/null | sed 's/^/    | /'; fi; }

echo "--- B1. GUT load/compile scan return is no longer silent"
setupb; mkgd app 2; flagfile app test_bad.gd tests/mission
run "$T/repos/app"
bok "B1 NEGATIVE: the gate FAILS (not merged to develop)" "$([ "$(merged app)" = 0 ] && outhas 'gate FAILED' && echo 1 || echo 0)"
bok "B1 the hygiene log names the load/compile scan and the failing script" "$(outhas 'gate: GUT load/compile scan FAILED:' && outhas 'res://tests/mission/test_bad.gd' && echo 1 || echo 0)"
bok "B1 ... and the parse error reason" "$(outhas 'Cannot find member "REINFORCEMENTS" in base "MissionDirective"' && echo 1 || echo 0)"
run "$T/repos/app"; run "$T/repos/app"
bok "B1 after 3 consecutive failed passes the hygiene-gate-streak alert fires" "$(alertshas 'hygiene-gate-streak:app' && alertshas 'FAILED 3 consecutive passes for app overnight/feature' && echo 1 || echo 0)"
bok "B1 the streak alert NAMES the failing script (old: no 'failing:' part at all)" "$(alertshas 'failing: GUT script failed to load/compile:' && alertshas 'res://tests/mission/test_bad.gd' && echo 1 || echo 0)"
bok "B1 the streak alert carries the parse error" "$(alertshas 'REINFORCEMENTS' && echo 1 || echo 0)"
bok "B1 the gate GUT run carried the recursion flag" "$(grep -q 'gdir=res://tests -ginclude_subdirs -gexit' "$T/godot.calls" && echo 1 || echo 0)"

echo "--- B2. BENIGN control + kill switch"
setupb; mkgd app 2
run "$T/repos/app"
bok "B2 BENIGN: no broken script -> merged, no load/compile line, no streak" "$([ "$(merged app)" = 1 ] && ! outhas 'GUT load/compile scan FAILED' && [ -z "$(ls "$STATE_DIR/hygiene_gate_streak/" 2>/dev/null)" ] && echo 1 || echo 0)"
setupb; mkgd app 2; flagfile app test_bad.gd tests/mission
OVN_GUT_SUBDIRS=off run "$T/repos/app"
bok "B2 kill switch OVN_GUT_SUBDIRS=off: the subdir script is not loaded -> gate green, merged (old non-recursive behaviour)" "$([ "$(merged app)" = 1 ] && ! grep -q include_subdirs "$T/godot.calls" && echo 1 || echo 0)"

echo "--- B3. godot --import scan return is no longer silent"
setupb; mkgd app 2; flagfile app import_bad.flag
run "$T/repos/app"
bok "B3 NEGATIVE: an import error fails the gate (not merged)" "$([ "$(merged app)" = 0 ] && echo 1 || echo 0)"
bok "B3 the hygiene log shows the first offending line" "$(outhas 'gate: godot --import scan FAILED: SCRIPT ERROR: Parse Error: Identifier "Foo" not declared in the current scope.' && echo 1 || echo 0)"
run "$T/repos/app"; run "$T/repos/app"
bok "B3 the streak alert names it (old: no 'failing:' part)" "$(alertshas 'failing: godot import error: SCRIPT ERROR: Parse Error: Identifier "Foo"' && echo 1 || echo 0)"
setupb; mkgd app 2
run "$T/repos/app"
bok "B3 BENIGN: clean import -> merged, no import-scan line" "$([ "$(merged app)" = 1 ] && ! outhas 'godot --import scan FAILED' && echo 1 || echo 0)"


echo "--- B4. PARTIAL DEPLOY: new branch_hygiene.sh + a lib_gut_xml.sh without the new helpers must not MERGE a parse-broken script"
SBH_DIR="$T/stale_oq"; rm -rf "$SBH_DIR"; mkdir -p "$SBH_DIR/scripts"
cp "$(dirname "$BH")/branch_hygiene.sh" "$SBH_DIR/"
find "$(dirname "$BH")/scripts" -maxdepth 1 -type f -exec cp {} "$SBH_DIR/scripts/" \;
awk '/^gut_(subdirs_flag|load_failure_line)\(\) \{/ { skip = 1 } !skip { print } skip && /^\}/ { skip = 0 }' "$(dirname "$BH")/scripts/lib_gut_xml.sh" > "$SBH_DIR/scripts/lib_gut_xml.sh"
REAL_BH="$BH"; BH="$SBH_DIR/branch_hygiene.sh"
setupb; mkgd app 2; flagfile app test_bad.gd tests/mission
run "$T/repos/app"
bok "B4 NEGATIVE: stale lib, parse-broken tests/mission script -> gate FAILS, not merged (unguarded: merged = fails open)" "$([ "$(merged app)" = 0 ] && outhas 'gate FAILED' && echo 1 || echo 0)"
bok "B4 the gate GUT run still carried the recursion flag" "$(grep -q 'gdir=res://tests -ginclude_subdirs -gexit' "$T/godot.calls" && echo 1 || echo 0)"
bok "B4 the hygiene log still names the failing script" "$(outhas 'gate: GUT load/compile scan FAILED:' && outhas 'res://tests/mission/test_bad.gd' && echo 1 || echo 0)"
setupb; mkgd app 2
run "$T/repos/app"
bok "B4 BENIGN: stale lib, clean repo -> merged" "$([ "$(merged app)" = 1 ] && echo 1 || echo 0)"
BH="$REAL_BH"


ro_summary
