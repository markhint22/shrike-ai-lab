#!/usr/bin/env bash
# Z9: the GUT pass/fail decision must come from lib_gut_xml.sh gut_xml_green (root <testsuites> failures/errors, tests>0), never from
# `grep failures="0"` (matches any per-suite line: a real red report has hundreds). Fixtures + old-form mutant + wiring mutation.
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."
. "$HERE/../lib_gut_xml.sh"
T=$(safe_mktemp_dir) || exit 1; trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
mk(){ printf '%s\n' "$2" > "$T/$1.xml"; }
zeros(){ local i; for i in $(seq 1 414); do printf '  <testsuite name="tests/s%s.gd" tests="3" failures="0" skipped="0"><testcase name="t" status="pass"></testcase></testsuite>\n' "$i"; done; }
{ echo '<testsuites name="GutTests" failures="36" tests="3282" >'; zeros; echo '  <testsuite name="tests/bad.gd" tests="2" failures="36"><testcase name="t" status="fail"><failure message="x"/></testcase></testsuite>'; echo '</testsuites>'; } > "$T/red414.xml"
{ echo '<testsuites name="GutTests" tests="3282" failures="36">'; zeros; echo '</testsuites>'; } > "$T/red_order.xml"      # attribute order variant, red only at root
{ echo '<testsuites name="GutTests" failures="0" tests="3431" >'; zeros; echo '  <testsuite name="tests/sfx.gd" tests="2" failures="0" skipped="1"><testcase name="p" assertions="0" status="pending"><skipped message="pending"><![CDATA[x]]></skipped></testcase></testsuite></testsuites>'; } > "$T/green.xml"
{ echo '<testsuites name="GutTests" failures="0" errors="2" tests="9" >'; zeros; echo '</testsuites>'; } > "$T/errs.xml"
: > "$T/empty.xml"
mk notests '<testsuites name="GutTests" failures="0" tests="0" ></testsuites>'
mk notests2 '<testsuites name="GutTests" tests="0" failures="0"></testsuites>'
mk risky '<testsuites name="GutTests" failures="0" tests="2" ><testsuite name="a" tests="2" failures="0" skipped="1"><testcase name="p" status="pending"><skipped message="pending"/></testcase><testcase name="q" status="pass"/></testsuite></testsuites>'
mk noroot '<testsuite name="a" tests="2" failures="2"><testcase name="t" status="fail"><failure message="x"/></testcase></testsuite><testsuite name="b" failures="0"/>'
mk noroot_ok '<testsuite name="a" tests="1" failures="0"><testcase name="t" status="pass"></testcase></testsuite>'
mk noasserts '<testsuites name="GutTests" failures="0" tests="1"><testsuite name="a" failures="0"><testcase name="t" status="no asserts"></testcase></testsuite></testsuites>'
g(){ gut_xml_green "$T/$1.xml" && echo G || echo R; }
oldgrep(){ grep -qE 'failures="0"' "$T/$1.xml" && echo G || echo R; }   # the REPLACED broken form
ok "green report (3431 tests, 1 pending/skipped) is GREEN" "$([ "$(g green)" = G ] && echo 1 || echo 0)"
ok "pending/skipped-only testcase does not count as failure" "$([ "$(g risky)" = G ] && echo 1 || echo 0)"
ok "red: root failures=36 with 414 failures=0 lines is RED" "$([ "$(g red414)" = R ] && grep -c 'failures="0"' "$T/red414.xml" | grep -qx 414 && echo 1 || echo 0)"
ok "red: root-only failures with attribute order tests-before-failures is RED" "$([ "$(g red_order)" = R ] && echo 1 || echo 0)"
ok "errors>0 at root is RED" "$([ "$(g errs)" = R ] && echo 1 || echo 0)"
ok "empty XML is RED" "$([ "$(g empty)" = R ] && echo 1 || echo 0)"
ok "missing XML is RED" "$(gut_xml_green "$T/none.xml" && echo 0 || echo 1)"
ok "root tests=0 is RED (both attribute orders)" "$([ "$(g notests)$(g notests2)" = RR ] && echo 1 || echo 0)"
ok "no root, per-suite failures>0 is RED" "$([ "$(g noroot)" = R ] && echo 1 || echo 0)"
ok "no root, all per-suite failures=0 is GREEN" "$([ "$(g noroot_ok)" = G ] && echo 1 || echo 0)"
ok "status=no asserts is RED" "$([ "$(g noasserts)" = R ] && echo 1 || echo 0)"
# parse/compile-error log: the xml stays green, the log scan (gut_load_failure_line) is the second half of every decision point
printf 'SCRIPT ERROR: Parse Error: Cannot find member "X"\n   at: GDScript::reload (res://tests/t.gd:3)\nERROR: Failed to load script "res://tests/t.gd" with error "Parse error".\n' > "$T/parse.log"
ok "parse/compile error log is caught by gut_load_failure_line" "$(gut_load_failure_line "$T/parse.log" >/dev/null && echo 1 || echo 0)"
printf 'Totals\n  Passing 3\n' > "$T/clean.log"
ok "clean log is not flagged" "$(gut_load_failure_line "$T/clean.log" >/dev/null && echo 0 || echo 1)"
# mutants: the old grep form passes the red fixtures -> proves these fixtures catch a revert
ok "MUTANT old grep form says PASS on red414 (fixture is a real regression test)" "$([ "$(oldgrep red414)" = G ] && echo 1 || echo 0)"
ok "MUTANT old grep form says PASS on empty-tests root" "$([ "$(oldgrep notests)" = G ] && echo 1 || echo 0)"
# wiring: every GUT decision point calls gut_xml_green and none greps failures="0"
wired(){ local f="$1"; grep -q 'gut_xml_green "\$' "$f" && ! grep -vE '^\s*#' "$f" | grep -qE "grep -q?E? +'?failures=\\\\?\"0"; }
for f in branch_hygiene.sh run_overnight.sh ovn_stage_runner.sh; do
  ok "$f calls gut_xml_green and has no failures=\"0\" grep" "$(wired "$ROOT/$f" && echo 1 || echo 0)"
  sed -E 's/gut_xml_green "(\$[A-Za-z_]+)"/grep -qE '"'"'failures="0"'"'"' "\1"/' "$ROOT/$f" > "$T/mut_$f"
  ok "MUTANT $f restored to the old grep form is detected by the wiring check" "$(wired "$T/mut_$f" && echo 0 || echo 1)"
done
echo "  $P passed, $F failed"; [ "$F" = 0 ]
