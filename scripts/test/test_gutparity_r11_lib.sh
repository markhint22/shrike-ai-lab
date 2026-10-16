#!/usr/bin/env bash
# test_gutparity_r11_lib.sh - 2026-10-11, package gutparity (xlite findings X2 / X3 / X7a). GUT (Godot) parity for the test-id helpers that only understood pytest/vitest:
#   lib_gut_xml.sh         gut_xml_failing_ids / gut_xml_ids_complete / gut_xml_emit_fail_ids   ('--- GUT-FAIL-ID: tests/foo.gd::test_x' from the junit XML)
#   lib_run_integrity.sh   ovn_ri_failing_ids / ovn_ri_has_summary / ovn_ri_foreign_red / ovn_ri_subtract understand GUT (a pre-existing red test is baseline-subtracted)
#   ovn_extract_failure.sh GUT branch first, exit-leak noise excluded from the fallback
#   lib_item_select.sh     ovn_failing_ids / ovn_repeat_key / ovn_bestn_baseline_stop, ovn_repeat_ids.py base_only, ovn_plan_path_tokens / ovn_item_head_path
# Every behaviour has a NEGATIVE control (the seeded bad input is still caught) and a BENIGN one (clean input is untouched). Assertions run with pipefail ON on purpose
# (the SIGPIPE regressions below only exist under pipefail).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export HOME="$T/home"; mkdir -p "$HOME"
. "$Q/scripts/lib_gut_xml.sh"
. "$Q/scripts/lib_run_integrity.sh"
. "$Q/scripts/lib_item_select.sh"

# ---------------------------------------------------------------------------------------------------- fixtures
ORPHAN_ID='tests/test_orphan_save_manager.gd::test_orphan_save_manager_does_not_exist'
xml_red(){   # the REAL shape from xlite's 2026-10-11 04:15 failure (3001 tests, 1 failing, root failures="1"); no trailing newline like GUT writes it
  printf '%s' '<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="1" tests="3001" >
  <testsuite name="tests/test_ability.gd" tests="1" failures="0" skipped="0" time="0.000203" >
      <testcase name="test_ok" assertions="1" status="pass" classname="tests/test_ability.gd" time="0.0001" >
      </testcase>
      </testsuite>
  <testsuite name="tests/test_orphan_save_manager.gd" tests="1" failures="1" skipped="0" time="0.000102" >
      <testcase name="test_orphan_save_manager_does_not_exist" assertions="1" status="fail" classname="tests/test_orphan_save_manager.gd" time="0.000102" >
      <failure message="failed"><![CDATA[scripts/battle/save_manager.gd should not exist
            at line -1]]></failure></testcase>
      </testsuite>
  </testsuites>'
}
xml_red2(){  # two failing tests in two files (root failures="2")
  printf '%s' '<testsuites name="GutTests" failures="2" tests="9" >
  <testsuite name="tests/test_a.gd" tests="2" failures="1" ><testcase name="test_a1" status="pass" classname="tests/test_a.gd"></testcase>
      <testcase name="test_a2" assertions="1" status="fail" classname="tests/test_a.gd" ><failure message="x"/></testcase></testsuite>
  <testsuite name="tests/test_b.gd" tests="1" failures="1" ><testcase name="test_b1" status="fail" classname="res://tests/test_b.gd" ><failure message="y"/></testcase></testsuite>
  </testsuites>'
}
xml_green(){ printf '%s' '<testsuites name="GutTests" failures="0" tests="3" ><testsuite name="a" failures="0" tests="3"><testcase name="t" status="pass" classname="tests/a.gd"></testcase></testsuite></testsuites>'; }
# summary console block exactly as GUT prints it (ANSI colour codes included)
console_red(){
  printf '\033[33m= Run Summary\033[0m\n\n\033[4m\nres://tests/test_orphan_save_manager.gd\n\033[0m- test_orphan_save_manager_does_not_exist\n\033[31m    [Failed]:  \033[0mscripts/battle/save_manager.gd should not exist\n          at line -1\n\n---- Totals ----\nWarnings          22\n\nScripts           392\nTests             3001\n  Passing         3000\n  Failing         1\nAsserts           15759\n'
}
noise(){ printf 'SCRIPT ERROR: Invalid assignment of property or key '"'"'text'"'"' with value of type '"'"'String'"'"' on a base object of type '"'"'Nil'"'"'.\nERROR: 1 RID allocations of type '"'"'PN18TextServerAdvanced12FontAdvancedE'"'"' were leaked at exit.\nERROR: 9 resources still in use at exit (run with --verbose for details).\n'; }
leak(){ noise | grep -E 'RID allocations|resources still in use'; }   # the three exit-leak shapes the fallback must drop
# the verify output the (patched) GUT block of run_overnight.sh writes: GUT console, junit XML + newline, suite-red mark, GUT RED line, ids [+ COMPLETE]
mk_gut_log(){   # mk_gut_log <file> <xml fn> [flags: glued nocomplete noids]
  local f="$1" xf="$2" mode=" ${3:-} " x="$T/_x.xml"
  "$xf" > "$x"
  { echo '--- verify: GUT tests in . (90s cap) ---'; noise; console_red; cat "$x"
    case "$mode" in
      *" glued "*) printf -- '--- verify-suite-red: gut in . rc=1 ---\n';;      # the OLD shape: marker glued to "</testsuites>" (no newline after the XML)
      *)           printf -- '\n--- verify-suite-red: gut in . rc=1 ---\n';;
    esac
    echo "--- GUT RED: $(gut_xml_summary "$x")"
    case "$mode" in
      *" noids "*) ;;
      *" nocomplete "*) gut_xml_emit_fail_ids "$x" | grep -v 'IDS-COMPLETE';;
      *) gut_xml_emit_fail_ids "$x";;
    esac
  } > "$f"
}

# ============================================================== A. lib_gut_xml: ids from the junit report
xml_red > "$T/red.xml"; xml_red2 > "$T/red2.xml"; xml_green > "$T/green.xml"
eq "A1 ids: the real orphan-test report yields exactly the failing test" "$ORPHAN_ID" "$(gut_xml_failing_ids "$T/red.xml")"
eq "A2 ids: two failing tests in two files, res:// stripped, report order" "$(printf 'tests/test_a.gd::test_a2\ntests/test_b.gd::test_b1')" "$(gut_xml_failing_ids "$T/red2.xml")"
eq "A3 ids: a green report has none (BENIGN)" "" "$(gut_xml_failing_ids "$T/green.xml")"
eq "A4 ids: missing file / empty file / no argument never raise, print nothing" "" "$(gut_xml_failing_ids "$T/nope.xml")$(: > "$T/e.xml"; gut_xml_failing_ids "$T/e.xml")$(gut_xml_failing_ids)"
printf '%s' '<testsuites failures="0"><testsuite name="s" failures="0"><testcase name="t_risky" status="no asserts" classname="tests/r.gd"></testcase><testcase name="t_ok" status="pass" classname="tests/r.gd"></testcase></testsuite></testsuites>' > "$T/noassert.xml"
eq "A5 ids: a status=\"no asserts\" testcase is RED and named (gut_xml_green says red too)" "tests/r.gd::t_risky" "$(gut_xml_failing_ids "$T/noassert.xml")"
printf '%s' '<testsuites failures="1"><testsuite name="tests/s.gd" failures="1"><testcase name="t_child"><failure message="boom"/></testcase><testcase name="t_fine"></testcase></testsuite></testsuites>' > "$T/child.xml"
eq "A6 ids: a <failure> child without a status attribute is RED; classname falls back to the testsuite name" "tests/s.gd::t_child" "$(gut_xml_failing_ids "$T/child.xml")"
printf '%s' '<testsuites failures="1"><testsuite name="tests/o.gd" failures="1"><failure message="orphan"/></testsuite></testsuites>' > "$T/orphan.xml"
eq "A7 ids: a <failure> with no testcase is named at suite level (never silently dropped)" "tests/o.gd::(suite-level)" "$(gut_xml_failing_ids "$T/orphan.xml")"
printf '%s' '<testsuites failures="2"><testsuite name="s"><testcase name="same" status="fail" classname="tests/d.gd"><failure message="1"/><failure message="2"/></testcase></testsuite></testsuites>' > "$T/dup.xml"
eq "A8 ids: one testcase with two failed asserts is ONE id" "tests/d.gd::same" "$(gut_xml_failing_ids "$T/dup.xml")"

gut_xml_ids_complete "$T/red.xml" && ok "A9 complete: the real report (1 failure element == root failures=1)" 1 || ok "A9 complete: the real report (1 failure element == root failures=1)" 0
gut_xml_ids_complete "$T/red2.xml" && ok "A10 complete: two named == root failures=2" 1 || ok "A10 complete: two named == root failures=2" 0
printf '%s' '<testsuites failures="3"><testsuite name="s"><testcase name="t" status="fail" classname="c"><failure message="x"/></testcase></testsuite></testsuites>' > "$T/under.xml"
gut_xml_ids_complete "$T/under.xml" && ok "A11 complete NEGATIVE: root counts 3 reds but only 1 is named -> NOT complete" 0 || ok "A11 complete NEGATIVE: root counts 3 reds but only 1 is named -> NOT complete" 1
printf '%s' '<testsuite name="s"><testcase name="t" status="fail" classname="c"><failure message="x"/></testcase></testsuite>' > "$T/noroot.xml"
gut_xml_ids_complete "$T/noroot.xml" && ok "A12 complete NEGATIVE: no <testsuites> root -> NOT complete (nothing to cross-check)" 0 || ok "A12 complete NEGATIVE: no <testsuites> root -> NOT complete (nothing to cross-check)" 1
gut_xml_ids_complete "$T/green.xml" && ok "A13 complete NEGATIVE: a green report names nothing -> NOT complete" 0 || ok "A13 complete NEGATIVE: a green report names nothing -> NOT complete" 1
gut_xml_ids_complete "$T/noassert.xml" && ok "A14 complete: a no-asserts-only report (failures=0, 0 failure elements, 1 id) is covered" 1 || ok "A14 complete: a no-asserts-only report (failures=0, 0 failure elements, 1 id) is covered" 0
eq "A15 emit: ids + COMPLETE marker" "$(printf -- '--- GUT-FAIL-ID: %s\n--- GUT-FAIL-IDS-COMPLETE ---' "$ORPHAN_ID")" "$(gut_xml_emit_fail_ids "$T/red.xml")"
eq "A16 emit: green report prints nothing" "" "$(gut_xml_emit_fail_ids "$T/green.xml")"
eq "A17 emit: cap OVN_GUT_FAIL_ID_MAX=1 keeps 1 id and withholds COMPLETE (a truncated list must never read as complete)" "--- GUT-FAIL-ID: tests/test_a.gd::test_a2" "$(OVN_GUT_FAIL_ID_MAX=1 gut_xml_emit_fail_ids "$T/red2.xml")"
eq "A18 emit: underspecified report has ids but NO COMPLETE" "--- GUT-FAIL-ID: c::t" "$(gut_xml_emit_fail_ids "$T/under.xml")"

# ============================================================== B. lib_run_integrity: ids / summary on a GUT log
mk_gut_log "$T/g1.log" xml_red
eq "B1 ovn_ri_failing_ids reads the GUT-FAIL-ID line (OLD code: empty -> status=no-ids)" "$ORPHAN_ID" "$(ovn_ri_failing_ids "$T/g1.log")"
OFF="$(wc -c < "$T/g1.log" | tr -d ' ')"; { echo 'FAILED tests/x.py::t - boom'; echo '--- GUT-FAIL-ID: tests/later.gd::test_later'; } >> "$T/g1.log"
eq "B2 ids: pytest + GUT ids merge; only bytes after the offset (an earlier verify cannot leak in)" "$(printf 'tests/later.gd::test_later\ntests/x.py::t')" "$(ovn_ri_failing_ids "$T/g1.log" "$OFF")"
ovn_ri_has_summary "$T/g1.log" 0 && ok "B3 has_summary: GUT '---- Totals ----' counts (OLD code: incomplete)" 1 || ok "B3 has_summary: GUT '---- Totals ----' counts (OLD code: incomplete)" 0
printf -- '--- GUT-FAIL-ID: tests/a.gd::t\nTotals incomplete: timeout killed GUT\n' > "$T/partial.log"
ovn_ri_has_summary "$T/partial.log" 0 && ok "B4 has_summary NEGATIVE: a killed GUT run (ids but no Totals block) is not a summary" 0 || ok "B4 has_summary NEGATIVE: a killed GUT run (ids but no Totals block) is not a summary" 1
# SIGPIPE regression (pipefail ON): the matching line is FIRST in a multi-MB log. `tail | grep -q` read this as "no match" (141) -> has_summary false / a veto lost.
big(){ { printf '%s\n' "$1"; head -c 3000000 /dev/zero | tr '\0' 'x' | fold -w 100; } > "$T/big.log"; }
big '---- Totals ----'
ovn_ri_has_summary "$T/big.log" 0 && ok "B5 has_summary on a 3 MB log whose Totals line is first (pipefail on)" 1 || ok "B5 has_summary on a 3 MB log whose Totals line is first (pipefail on)" 0
big 'src/a.ts(3,1): error TS2322: bad'
ovn_ri_foreign_red "$T/big.log" 0 && ok "B6 foreign_red on a 3 MB log whose veto marker is first: STILL vetoes (OLD code lost the veto to SIGPIPE)" 1 || ok "B6 foreign_red on a 3 MB log whose veto marker is first: STILL vetoes (OLD code lost the veto to SIGPIPE)" 0
big 'all fine'
ovn_ri_foreign_red "$T/big.log" 0 && ok "B7 foreign_red BENIGN: a clean 3 MB log is not a veto" 0 || ok "B7 foreign_red BENIGN: a clean 3 MB log is not a veto" 1

# ============================================================== C. ovn_ri_foreign_red + ovn_ri_subtract on GUT logs (stub verification, fixture repo)
R="$T/repo"; mkdir -p "$R"; ( cd "$R" && git init -q -b main && echo 0 > f && git add f && git commit -q -m c0 && echo 1 > f && git add f && git commit -q -m c1 )
C0="$(git -C "$R" rev-parse HEAD~1)"; SD="$T/state"; mkdir -p "$SD"; FIX="$T/fix"; mkdir -p "$FIX"
run_repo_verification(){ local s; s="$(git rev-parse HEAD)"; echo $(( $(cat "$FIX/calls" 2>/dev/null || echo 0) + 1 )) > "$FIX/calls"; [ -f "$FIX/out.$s" ] && cat "$FIX/out.$s" >> "$task_log"; cat "$FIX/res.$s" 2>/dev/null || echo fail; }
task_log="$T/cycle.log"
base_with(){ rm -f "$SD"/baseline_fail_*; : > "$FIX/calls"; cp "$1" "$FIX/out.$C0"; echo fail > "$FIX/res.$C0"; }   # baseline = the same shape of GUT log at BEFORE_SHA
sub(){ ( cd "$R" && ovn_ri_subtract "$1" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS n=$OVN_RI_BASE_N new=[$(printf '%s' "$OVN_RI_NEW" | tr '\n' ',')]" ); }

mk_gut_log "$T/c_cur.log" xml_red; base_with "$T/c_cur.log"
eq "C1 pre-existing red GUT test, same id at BEFORE_SHA -> all-baseline, rc 0 (OLD: status=no-ids -> revert)" "rc=0 all-baseline n=1 new=[]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red2; mk_gut_log "$T/c_base.log" xml_red; base_with "$T/c_base.log"
eq "C2 NEGATIVE: the commit adds a NEW failing GUT test on top of the pre-existing one -> subtracted, NEW names only the new ids" "rc=1 subtracted n=1 new=[tests/test_a.gd::test_a2,tests/test_b.gd::test_b1]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red; echo pass > "$FIX/res.$C0"; rm -f "$FIX/out.$C0" "$SD"/baseline_fail_*
eq "C3 NEGATIVE: green baseline -> baseline-green (every id is new red; revert stays)" "rc=1 baseline-green n=0 new=[$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red nocomplete; base_with "$T/c_cur.log"
eq "C4 NEGATIVE: GUT ids WITHOUT the COMPLETE marker (root counts more reds than named) -> other-suite-red" "rc=1 other-suite-red n=0 new=[$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red; printf -- '--- verify-suite-red: gut in . rc=1 ---\n' >> "$T/c_cur.log"; base_with "$T/c_base.log"
eq "C5 NEGATIVE: a SECOND gut red mark (run_repo_verification records one for a Parse/load error) -> other-suite-red" "rc=1 other-suite-red n=0 new=[$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red; printf -- '--- verify-suite-red: pytest in ./backend rc=1 ---\nFAILED backend/tests/test_x.py::test_y - boom\n== 1 failed in 1.0s ==\n' >> "$T/c_cur.log"; base_with "$T/c_cur.log"
eq "C6 NEGATIVE: GUT red + a red pytest suite in the same verify -> other-suite-red" "rc=1 other-suite-red n=0 new=[backend/tests/test_x.py::test_y,$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red; printf 'src/a.ts(3,1): error TS2322: bad\n' >> "$T/c_cur.log"; base_with "$T/c_cur.log"
eq "C7 NEGATIVE: GUT red + a tsc error -> other-suite-red (non-GUT veto markers still apply)" "rc=1 other-suite-red n=0 new=[$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red "glued nocomplete"; base_with "$T/c_cur.log"
eq "C8 NEGATIVE: marker GLUED to </testsuites> and ids WITHOUT the COMPLETE marker -> still other-suite-red (never subtracts without proof)" "rc=1 other-suite-red n=0 new=[$ORPHAN_ID]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red glued; base_with "$T/c_cur.log"
eq "C9 BENIGN: the glued marker (old XML-without-newline shape) is recognised as ONE gut red, ids complete -> all-baseline" "rc=0 all-baseline n=1 new=[]" "$(sub "$T/c_cur.log")"
mk_gut_log "$T/c_cur.log" xml_red; base_with "$T/c_cur.log"
eq "C10 BENIGN: the benign exit-leak ERROR / 'SCRIPT ERROR ... Nil' noise and '[Failed]:' / 'Failing 1' text do not veto" "rc=0 all-baseline n=1 new=[]" "$(sub "$T/c_cur.log")"
base_with "$T/c_cur.log"
eq "C11 kill switch OVN_BASELINE_SUBTRACT_GUT=off -> other-suite-red (the old veto for GUT)" "rc=1 other-suite-red n=0 new=[$ORPHAN_ID]" "$(OVN_BASELINE_SUBTRACT_GUT=off sub "$T/c_cur.log")"
eq "C12 kill switch OVN_BASELINE_SUBTRACT=off -> disabled" "rc=1 disabled n=0 new=[]" "$(OVN_BASELINE_SUBTRACT=off sub "$T/c_cur.log")"
{ echo '--- verify: pytest ---'; echo 'FAILED tests/old.py::test_old - x'; echo '== 1 failed, 6 passed in 2.00s =='; } > "$T/py_cur.log"; base_with "$T/py_cur.log"
eq "C13 BENIGN (pytest unchanged): single pytest red == baseline -> all-baseline" "rc=0 all-baseline n=1 new=[]" "$(sub "$T/py_cur.log")"
# a big log (the real xlite verify log is 1.8 MB): the same decision on a 3 MB log, GUT section at the END, noise before it
{ head -c 3000000 /dev/zero | tr '\0' 'x' | fold -w 100; cat "$T/c_cur.log"; } > "$T/c_big.log"; base_with "$T/c_cur.log"
eq "C14 a 3 MB verify log still decides correctly (all-baseline)" "rc=0 all-baseline n=1 new=[]" "$(sub "$T/c_big.log")"

# ============================================================== D. ovn_extract_failure.sh
EX="$Q/scripts/ovn_extract_failure.sh"
mk_gut_log "$T/d_new.log" xml_red
out="$(bash "$EX" "$T/d_new.log")"
eq "D1 new-format log: names the failing test and the assertion text" "GUT failing: $ORPHAN_ID - scripts/battle/save_manager.gd should not exist" "$out"
case "$out" in *'RID allocations'*|*'resources still in use'*) ok "D2 the exit-leak ERROR noise is not in the summary" 0;; *) ok "D2 the exit-leak ERROR noise is not in the summary" 1;; esac
{ echo '--- verify: GUT tests in . (90s cap) ---'; noise; console_red; echo '--- GUT RED: root: <testsuites name="GutTests" failures="1" tests="3001" > | failing: name="test_orphan_save_manager_does_not_exist" name="tests/test_orphan_save_manager.gd" '; } > "$T/d_old.log"
eq "D3 OLD-format log (no GUT-FAIL-ID lines, as every log written before this change): the console Run Summary names the test" "GUT failing: $ORPHAN_ID - scripts/battle/save_manager.gd should not exist" "$(bash "$EX" "$T/d_old.log")"
{ echo '--- GUT RED: root: <testsuites failures="1" > | failing: name="test_only_in_red_line" name="tests/test_x.gd" '; noise; } > "$T/d_redline.log"
eq "D4 only the '--- GUT RED' line survives -> its failing names" "GUT failing: test_only_in_red_line tests/test_x.gd" "$(bash "$EX" "$T/d_redline.log")"
{ leak; echo 'ERROR: something else failed'; echo 'real failure: boom FAILED here'; } > "$T/d_fb.log"
eq "D5 fallback (no pytest/vitest/GUT evidence): exit-leak lines are excluded, a real error line is kept" "ERROR: something else failed real failure: boom FAILED here" "$(bash "$EX" "$T/d_fb.log")"
{ leak; } > "$T/d_noiseonly.log"
eq "D6 NEGATIVE-noise: a log with ONLY exit-leak noise yields an empty summary (OLD code returned the leak lines)" "" "$(bash "$EX" "$T/d_noiseonly.log")"
{ console_red | sed 's/Failing         1/Failing         0/; s/\[Failed\]/[Passed]/'; } > "$T/d_green.log"
eq "D7 BENIGN: a green GUT run (Run Summary, no [Failed]) adds nothing" "" "$(bash "$EX" "$T/d_green.log")"
{ printf 'FAILED tests/test_a.py::test_b - AssertionError: nope\n'; console_red | sed 's/\[Failed\]/[Passed]/'; } > "$T/d_py.log"
eq "D8 pytest evidence is unchanged when GUT is green" "FAILED tests/test_a.py::test_b - AssertionError: nope" "$(bash "$EX" "$T/d_py.log")"
# two verify runs in one log (attempt + fix-up re-verify): the LAST group wins
{ echo '--- GUT-FAIL-ID: tests/old_attempt.gd::test_old'; echo '--- GUT RED: first'; echo 'something'; echo '--- GUT RED: second'; echo '--- GUT-FAIL-ID: tests/new_attempt.gd::test_new'; } > "$T/d_two.log"
eq "D9 two verify runs in one log: only the LAST run's ids" "GUT failing: tests/new_attempt.gd::test_new" "$(bash "$EX" "$T/d_two.log")"

# ============================================================== E. ovn_failing_ids / ovn_repeat_key / base_only / ovn_bestn_baseline_stop
mk_gut_log "$T/e1.log" xml_red; mk_gut_log "$T/e2.log" xml_red; mk_gut_log "$T/e3.log" xml_red2
eq "E1 ovn_failing_ids returns the GUT id (OLD: empty -> no repeat key)" "$ORPHAN_ID" "$(ovn_failing_ids "$T/e1.log")"
k1="$(ovn_repeat_key h1 "$T/e1.log")"; k2="$(ovn_repeat_key h1 "$T/e2.log")"; k3="$(ovn_repeat_key h1 "$T/e3.log")"
ok "E2 repeat key is non-empty for a GUT red and identical for the same failing set" "$([ -n "$k1" ] && [ "$k1" = "$k2" ] && echo 1 || echo 0)"
ok "E3 NEGATIVE: a different failing set -> a different key" "$([ -n "$k3" ] && [ "$k3" != "$k1" ] && echo 1 || echo 0)"
s1=1; s1="$(ovn_repeat_streak "" "$k1" 1)"; s2="$(ovn_repeat_streak "$k1" "$k2" "$s1")"
eq "E4 the breaker streak reaches OVN_REPEAT_BREAKER_N=2 on the second identical GUT red (so best-of-N stops, the item guard parks)" "1 2" "$s1 $s2"
eq "E5 BENIGN: a green log has no ids / no key" "" "$(ovn_repeat_key h1 "$T/d_green.log")"
RP="$T/rp/xlite"; mkdir -p "$RP"; ST="$T/st"; mkdir -p "$ST/qa_baselines/verify"
printf '{"failing":["res://%s"],"ts":%s,"ttl_s":86400}' "$ORPHAN_ID" "$(date +%s)" > "$ST/qa_baselines/verify/xlite.json"
eq "E6 qa baseline stores the console form 'res://tests/x.gd::t': a GUT-FAIL-ID that is red at the baseline gives NO repeat key (not the item's fault)" "" "$(ovn_repeat_key h1 "$T/e1.log" "$RP" "$ST")"
ok "E7 ... while a NEW failing id on top of it is still keyed" "$([ -n "$(ovn_repeat_key h1 "$T/e3.log" "$RP" "$ST")" ] && echo 1 || echo 0)"
eq "E8 base_only: every id red at the active baseline -> yes" "yes" "$(printf '%s\n' "$ORPHAN_ID" | python3 "$Q/scripts/ovn_repeat_ids.py" base_only xlite "$ST")"
eq "E9 base_only NEGATIVE: one id not at the baseline -> no" "no" "$(printf '%s\n%s\n' "$ORPHAN_ID" "tests/new.gd::t" | python3 "$Q/scripts/ovn_repeat_ids.py" base_only xlite "$ST")"
eq "E10 base_only NEGATIVE: no ids / no baseline store -> no" "no no" "$(printf '' | python3 "$Q/scripts/ovn_repeat_ids.py" base_only xlite "$ST") $(printf '%s\n' "$ORPHAN_ID" | python3 "$Q/scripts/ovn_repeat_ids.py" base_only ghostrepo "$ST")"
printf '{"failing":["%s"],"ts":1,"ttl_s":60}' "$ORPHAN_ID" > "$ST/qa_baselines/verify/old.json"
eq "E11 base_only NEGATIVE: an EXPIRED baseline is not trusted" "no" "$(printf '%s\n' "$ORPHAN_ID" | python3 "$Q/scripts/ovn_repeat_ids.py" base_only old "$ST")"
# ovn_bestn_baseline_stop: every failing id red at the baseline AND the NO-NEW-RED subtraction could not decide
stop_log(){ cp "$T/e1.log" "$T/stop.log"; [ -n "${1:-}" ] && echo "--- NO-NEW-RED BASELINE: status=$1 new=1 baseline=0 ---" >> "$T/stop.log"; }
chk(){ ovn_bestn_baseline_stop "$T/stop.log" "$RP" "$ST" "${1:-reverted(tests:FAIL)}" && echo stop || echo go; }
stop_log baseline-unknown; eq "E12 stop: all ids baseline-red + subtraction undecided (baseline-unknown) -> no more attempts" stop "$(chk)"
stop_log disabled;         eq "E13 stop: ... also when the subtraction is switched off" stop "$(chk)"
stop_log other-suite-red;  eq "E14 NEGATIVE: other-suite-red (a parse error / second suite the model may have caused) -> keep retrying" go "$(chk)"
stop_log subtracted;       eq "E15 NEGATIVE: subtracted (a NEW id) -> keep retrying" go "$(chk)"
stop_log baseline-green;   eq "E16 NEGATIVE: baseline-green -> keep retrying" go "$(chk)"
stop_log "";               eq "E17 NEGATIVE: no marker at all (the attempt never reached the subtraction) -> keep retrying" go "$(chk)"
stop_log baseline-unknown; eq "E18 NEGATIVE: a build-break revert is never stopped here" go "$(chk 'reverted(build-break)')"
cp "$T/e3.log" "$T/stop.log"; echo "--- NO-NEW-RED BASELINE: status=baseline-unknown new=2 baseline=0 ---" >> "$T/stop.log"
eq "E19 NEGATIVE: a failing id that is NOT red at the baseline -> keep retrying" go "$(chk)"
stop_log incomplete;       eq "E21 NEGATIVE: incomplete (the verify run was killed / timed out: may be a model-caused hang) -> keep retrying" go "$(chk)"
stop_log lib-missing;      eq "E22 stop: lib-missing (the subtraction could not run at all) -> no more attempts" stop "$(chk)"
printf '{"failing":["res://bare.gd::t"],"ts":%s,"ttl_s":86400}' "$(date +%s)" > "$ST/qa_baselines/verify/bare.json"
eq "E23 a directory-less 'res://bare.gd::t' baseline id still equals the junit 'bare.gd::t' (the ends-with-/ rule; no separate res:// normalisation exists)" "yes" "$(printf 'bare.gd::t\n' | python3 "$Q/scripts/ovn_repeat_ids.py" base_only bare "$ST")"
stop_log baseline-unknown; eq "E20 kill switch OVN_BESTN_BASELINE_STOP=off -> go" go "$(OVN_BESTN_BASELINE_STOP=off chk)"

# ============================================================== F. ungrounded-plan path tokens (cwd = a repo)
W="$T/work"; mkdir -p "$W/scripts/battle/enemy_fattle" "$W/app"; : > "$W/app/foo.py"; : > "$W/scripts/battle/enemy_fattle/.keep"; cd "$W"
eq "F1 a directory plan token with 2 slashes is grounding (the 22 xlite no-ops)" "scripts/battle/enemy_fattle" "$(printf 'Delete the typo directory scripts/battle/enemy_fattle and its empty artifact file using the DELETE trailer mechanism.' | ovn_plan_path_tokens)"
eq "F2 trailing sentence punctuation is stripped" "scripts/battle/enemy_fattle" "$(printf 'remove scripts/battle/enemy_fattle.' | ovn_plan_path_tokens)"
eq "F3 one-slash token under an existing top-level dir counts" "app/legacy" "$(printf 'drop app/legacy now' | ovn_plan_path_tokens)"
eq "F4 NEGATIVE: 'and/or', 'read/write', '1/2' name no path" "" "$(printf 'make it better and/or faster, read/write 1/2 of it' | ovn_plan_path_tokens)"
eq "F5 NEGATIVE: the fabricated is_prime plan has no path token" "" "$(printf 'Replace the custom is_prime function with a call to sympy.isprime and add sympy to requirements' | ovn_plan_path_tokens)"
eq "F6 NEGATIVE: a one-slash token under a NON-existent top dir ('nodir/x') does not count" "" "$(printf 'see nodir/x' | ovn_plan_path_tokens)"
eq "F4b NEGATIVE: prose triples ('read/write/execute', 'client/server/db', 'pass/fail/skip') name no path (OLD: any 2-slash token grounded a plan)" "" "$(printf 'improve the client/server/db throughput, pass/fail/skip reporting and read/write/execute bits' | ovn_plan_path_tokens)"
eq "F4c a 2-slash token with a file-like last segment still counts even under unknown dirs" "zz/yy/mod.py" "$(printf 'edit zz/yy/mod.py please' | ovn_plan_path_tokens)"
eq "F4d a 2-slash prose triple whose first segment IS an existing dir still counts (plausibly a real path)" "app/sub/dir" "$(printf 'remove app/sub/dir' | ovn_plan_path_tokens)"
eq "F7 head path: the first EXISTING path in the item text" "app/foo.py" "$(ovn_item_head_path '[T1] app/foo.py — fix it (cat:python)')"
eq "F8 head path NEGATIVE: item naming no existing path -> nothing" "" "$(ovn_item_head_path '[T1] ghost/none.py — fix it')"
cd "$HERE"

echo "gutparity r11 lib: $P passed, $F failed"
[ "$F" -eq 0 ]
