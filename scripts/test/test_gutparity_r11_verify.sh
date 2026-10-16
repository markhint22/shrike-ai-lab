#!/usr/bin/env bash
# test_gutparity_r11_verify.sh - 2026-10-11, package gutparity (X2/X3/X7a), END-TO-END through the REAL run_overnight.sh (sourced via lib_ro_core.sh):
#   1. the GUT block of run_repo_verification writes '--- GUT-FAIL-ID:' + the COMPLETE marker (and ends the XML line so the suite-red marker is at a line start),
#   2. ovn_ri_subtract (REAL baseline run, REAL run_repo_verification at BEFORE_SHA with a stub godot) turns a pre-existing red GUT test into all-baseline,
#   3. the ungrounded-plan guard accepts a plan that names a directory (real run_aider_fix_task via the aider1 driver) and still refuses a plan with no path.
# NEGATIVE + BENIGN control for each.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_link scripts/lib_run_integrity.sh scripts/ovn_extract_failure.sh scripts/ovn_repeat_ids.py
ro_tasks '[]'
ro_source
set +e

# ---- fake godot: the junit XML written depends on tracked marker files in the cwd (so the BEFORE and AFTER commits differ)
mkdir -p "$HOME/godot"
cat > "$HOME/godot/godot4" <<'EOF'
#!/bin/bash
case "$*" in *--import*) exit 0;; esac
echo "SCRIPT ERROR: Invalid assignment of property or key 'text' with value of type 'String' on a base object of type 'Nil'."
echo "ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit."
printf -- '---- Totals ----\nTests 3\n  Failing 1\n'
xml=""; for a in "$@"; do case "$a" in -gjunit_xml_file=*) xml="${a#-gjunit_xml_file=}";; esac; done
[ -n "$xml" ] || exit 0
nf=0; body=""
if [ -f red_old.flag ]; then nf=$((nf+1)); body="$body<testsuite name=\"tests/test_old.gd\" failures=\"1\"><testcase name=\"test_old\" status=\"fail\" classname=\"tests/test_old.gd\"><failure message=\"f\"/></testcase></testsuite>"; fi
if [ -f red_new.flag ]; then nf=$((nf+1)); body="$body<testsuite name=\"tests/test_new.gd\" failures=\"1\"><testcase name=\"test_new\" status=\"fail\" classname=\"tests/test_new.gd\"><failure message=\"f\"/></testcase></testsuite>"; fi
[ -f hidden_red.flag ] && nf=$((nf+1))     # root counts a red that no testcase names (an odd/truncated report)
[ -f parse_err.flag ] && echo "SCRIPT ERROR: Parse Error: Identifier \"foo\" not declared in the current scope."
printf '<testsuites name="GutTests" failures="%s" tests="3">%s</testsuites>' "$nf" "$body" > "$xml"   # no trailing newline, like GUT
exit 0
EOF
chmod +x "$HOME/godot/godot4"

task_log="$T/verify.task.log"; : > "$task_log"
V="$T/v"
newrepo(){ rm -rf "$V"; mkdir -p "$V/addons/gut" "$V/tests"; cd "$V" || exit 1; git init -q; echo x > project.godot; echo x > addons/gut/gut_cmdln.gd; echo base > README; touch red_old.flag
  git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; : > "$task_log"; rm -rf "${T:?}/tree/state"; mkdir -p "$T/tree/state"; }
commit_all(){ git add -A; git commit -q -m c; AFTER_SHA="$(git rev-parse HEAD)"; }
ST="$T/tree/state"

echo "--- 1. GUT block output"
newrepo; echo y > f; commit_all
r="$(run_repo_verification)"
eq "red pre-existing GUT test -> verification fails" fail "$r"
log="$(cat "$task_log")"
has "GUT-FAIL-ID line written" "$log" "--- GUT-FAIL-ID: tests/test_old.gd::test_old"
has "COMPLETE marker written" "$log" "--- GUT-FAIL-IDS-COMPLETE ---"
ok "suite-red marker is at a LINE START (the XML has no trailing newline; old shape: glued to </testsuites>)" "$([ "$(grep -c '^--- verify-suite-red: gut in \. rc=1 ---$' "$task_log")" = 1 ] && echo 1 || echo 0)"
ok "the '--- GUT RED:' line is still written (existing consumers)" "$(grep -q '^--- GUT RED: root: <testsuites' "$task_log" && echo 1 || echo 0)"
ok "ovn_ri_failing_ids sees the id" "$([ "$(ovn_ri_failing_ids "$task_log")" = "tests/test_old.gd::test_old" ] && echo 1 || echo 0)"
newrepo; rm -f red_old.flag; commit_all
eq "BENIGN: green GUT -> pass, and no GUT-FAIL-ID line" "pass" "$(run_repo_verification)"
ok "BENIGN: a green run writes no GUT-FAIL-ID" "$(grep -q 'GUT-FAIL-ID' "$task_log" && echo 0 || echo 1)"

echo "--- 2. NO-NEW-RED baseline subtraction through the real baseline run"
sub(){ ovn_ri_subtract "$task_log" "${OFF:-0}" "repo" "$BEFORE_SHA" "$ST"; echo "rc=$? $OVN_RI_STATUS n=$OVN_RI_BASE_N new=[$(printf '%s' "$OVN_RI_NEW" | tr '\n' ',' | sed 's/,$//')]"; }
newrepo; echo y > f; commit_all          # pre-existing red test_old at BEFORE and AFTER (the stub-vs-absence-test shape)
: > "$task_log"; OFF=0; run_repo_verification >/dev/null
eq "pre-existing red GUT test, model's commit adds nothing red -> all-baseline (rc 0)" "rc=0 all-baseline n=1 new=[]" "$(sub)"
ok "baseline cache written for BEFORE_SHA with the GUT id" "$(grep -qx 'tests/test_old.gd::test_old' "$ST/baseline_fail_repo_$BEFORE_SHA.txt" 2>/dev/null && echo 1 || echo 0)"
eq "tree restored to the model's commit after the baseline run" "$AFTER_SHA" "$(git rev-parse HEAD)"
newrepo; touch red_new.flag; commit_all
: > "$task_log"; run_repo_verification >/dev/null
eq "NEGATIVE: the commit makes a NEW GUT test fail on top of the pre-existing one -> subtracted, NEW = only the new id" "rc=1 subtracted n=1 new=[tests/test_new.gd::test_new]" "$(sub)"
newrepo; touch red_new.flag parse_err.flag; commit_all
: > "$task_log"; run_repo_verification >/dev/null
eq "NEGATIVE: a Parse Error next to the pre-existing red (second gut red mark) -> other-suite-red, never subtracted" "other-suite-red" "$(sub | sed -E 's/^rc=[0-9]+ ([a-z-]+) .*/\1/')"
newrepo; touch hidden_red.flag; commit_all
: > "$task_log"; run_repo_verification >/dev/null
has "hidden red: ids are written but the COMPLETE marker is withheld" "$(cat "$task_log")" "--- GUT-FAIL-ID: tests/test_old.gd::test_old"
ok "hidden red: NO COMPLETE marker" "$(grep -q 'GUT-FAIL-IDS-COMPLETE' "$task_log" && echo 0 || echo 1)"
eq "NEGATIVE: root counts a red no testcase names -> other-suite-red (a hidden red is never baseline-subtracted)" "other-suite-red" "$(sub | sed -E 's/^rc=[0-9]+ ([a-z-]+) .*/\1/')"
newrepo; echo y > f; commit_all
: > "$task_log"; run_repo_verification >/dev/null
eq "kill switch OVN_BASELINE_SUBTRACT_GUT=off restores the old veto" "other-suite-red" "$(OVN_BASELINE_SUBTRACT_GUT=off sub | sed -E 's/^rc=[0-9]+ ([a-z-]+) .*/\1/')"

echo "--- 3. ungrounded-plan guard (real run_aider_fix_task via the aider1 driver)"
DRV="$HERE/lib_ro_aider1_driver.sh"
run_drv(){ timeout 150 bash "$DRV" "$1" "$T/drv_$1" > "$T/drv_$1.out" 2>&1; }
res(){ cat "$T/drv_$1/result" 2>/dev/null; }
run_drv sc_ungrounded
eq "BENIGN control (existing behaviour): PLAN 'make it better somehow' FILES NONE -> no-op(ungrounded-plan)" "no-op(ungrounded-plan)" "$(res sc_ungrounded)"
run_drv sc_ungrounded_andor
eq "NEGATIVE: a plan whose only 'paths' are 'and/or', 'read/write' is still ungrounded" "no-op(ungrounded-plan)" "$(res sc_ungrounded_andor)"
run_drv sc_ungrounded_dir
ok "a plan that names a DIRECTORY ('Delete the typo directory app/legacy_dir ...' FILES NONE) is grounded: NOT ungrounded-plan (OLD code: no-op, ~13k tokens x 22 cycles)" "$([ "$(res sc_ungrounded_dir)" != 'no-op(ungrounded-plan)' ] && [ -n "$(res sc_ungrounded_dir)" ] && echo 1 || echo 0)"
ok "... and the implement call actually ran" "$([ -f "$T/drv_sc_ungrounded_dir/scn/calls/2.impl" ] && echo 1 || echo 0)"
OVN_UNGROUNDED_PATHS=off run_drv sc_ungrounded_dir
eq "kill switch OVN_UNGROUNDED_PATHS=off restores the old refusal" "no-op(ungrounded-plan)" "$(res sc_ungrounded_dir)"
run_drv sc_ungrounded_delete
ok "a whole-file DELETE plan naming no file ('FILES: NONE') is grounded by the top item's own head path (app/foo.py) (OLD: no-op(ungrounded-plan), the 59 historical delete no-ops)" "$([ "$(res sc_ungrounded_delete)" != 'no-op(ungrounded-plan)' ] && [ -n "$(res sc_ungrounded_delete)" ] && echo 1 || echo 0)"
ok "... and the implement call actually ran" "$([ -f "$T/drv_sc_ungrounded_delete/scn/calls/2.impl" ] && echo 1 || echo 0)"
OVN_UNGROUNDED_HEAD_PATH=off run_drv sc_ungrounded_delete
eq "kill switch OVN_UNGROUNDED_HEAD_PATH=off restores the refusal for the delete plan" "no-op(ungrounded-plan)" "$(res sc_ungrounded_delete)"
run_drv sc_ungrounded_notdelete
eq "NEGATIVE: a NON-delete plan ('remove the unused import in this file') with the same existing top item stays ungrounded (the head path is delete-only)" "no-op(ungrounded-plan)" "$(res sc_ungrounded_notdelete)"

ro_summary
