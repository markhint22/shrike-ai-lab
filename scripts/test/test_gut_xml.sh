#!/usr/bin/env bash
# lib_gut_xml.sh: a red GUT report must never be called green (the old `grep failures="0"` accepted a root failures="3" report).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib_gut_xml.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
mk(){ printf '%s' "$2" > "$T/$1.xml"; }
RED='<?xml version="1.0"?>
<testsuites name="GutTests" failures="3" tests="10" >
  <testsuite name="res://tests/test_a.gd" failures="0" tests="5"><testcase name="test_one" assertions="1" status="pass"></testcase></testsuite>
  <testsuite name="res://tests/test_scar.gd" failures="3" tests="5"><testcase name="test_should_scar_above_threshold" assertions="1" status="fail"><failure message="x"/></testcase></testsuite>
</testsuites>'
mk red "$RED"
ok "REGRESSION: root failures=3 with per-file failures=0 lines is RED (old grep said green)" "$(grep -qE 'failures="0"' "$T/red.xml" && ! gut_xml_green "$T/red.xml" && echo 1 || echo 0)"
mk green '<testsuites name="GutTests" failures="0" tests="10" ><testsuite name="a" failures="0" tests="5"><testcase name="t" status="pass"></testcase></testsuite></testsuites>'
ok "root failures=0 is green" "$(gut_xml_green "$T/green.xml" && echo 1 || echo 0)"
mk errs '<testsuites name="GutTests" failures="0" errors="2" tests="3"></testsuites>'
ok "root errors>0 is RED" "$(gut_xml_green "$T/errs.xml" && echo 0 || echo 1)"
mk noasserts '<testsuites name="GutTests" failures="0" tests="1"><testsuite name="a" failures="0"><testcase name="t" status="no asserts"></testcase></testsuite></testsuites>'
ok "a testcase with status=no asserts is RED" "$(gut_xml_green "$T/noasserts.xml" && echo 0 || echo 1)"
: > "$T/empty.xml"
ok "empty file is RED" "$(gut_xml_green "$T/empty.xml" && echo 0 || echo 1)"
ok "missing file is RED" "$(gut_xml_green "$T/nope.xml" && echo 0 || echo 1)"
ok "no argument is RED" "$(gut_xml_green && echo 0 || echo 1)"
mk noroot_bad '<testsuite name="a" failures="0"><testcase name="t"><failure message="boom"/></testcase></testsuite>'
ok "no <testsuites> root + a <failure> element is RED" "$(gut_xml_green "$T/noroot_bad.xml" && echo 0 || echo 1)"
mk bare_child_red '<testsuites><testsuite failures="2"/></testsuites>'
ok "bare <testsuites> root with a per-file failures=2 is RED (hygiene fixture shape)" "$(gut_xml_green "$T/bare_child_red.xml" && echo 0 || echo 1)"
mk bare_child_ok '<testsuites><testsuite failures="0"/></testsuites>'
ok "bare <testsuites> root with only failures=0 children is green" "$(gut_xml_green "$T/bare_child_ok.xml" && echo 1 || echo 0)"
mk noroot_ok '<testsuite name="a" failures="0"><testcase name="t" status="pass"></testcase></testsuite>'
ok "no <testsuites> root and no failure/error elements is green" "$(gut_xml_green "$T/noroot_ok.xml" && echo 1 || echo 0)"
mk multiline '<testsuites
   name="GutTests"
   failures="1"
   tests="4">
</testsuites>'
ok "root element split across lines is still parsed (RED)" "$(gut_xml_green "$T/multiline.xml" && echo 0 || echo 1)"
mk nofail_attr '<testsuites name="GutTests" tests="4"></testsuites>'
ok "root without failures/errors attributes counts as 0 (green)" "$(gut_xml_green "$T/nofail_attr.xml" && echo 1 || echo 0)"
ok "summary prints the root and the failing test name" "$(gut_xml_summary "$T/red.xml" | grep -q 'failures="3"' && gut_xml_summary "$T/red.xml" | grep -q 'test_should_scar_above_threshold' && echo 1 || echo 0)"
ok "summary never raises on a missing file" "$([ "$(gut_xml_summary "$T/nope.xml")" = "no junit xml" ] && echo 1 || echo 0)"
# the three real call sites must use the helper and must NOT still contain the blind grep
for f in branch_hygiene.sh run_overnight.sh ovn_stage_runner.sh; do
  [ -f "$HERE/../../$f" ] || continue
  ok "$f uses gut_xml_green and no longer greps failures=\"0\"" "$(grep -q 'gut_xml_green' "$HERE/../../$f" && ! grep -qE "grep -q?E? '?failures=\\\"0\\\"" "$HERE/../../$f" && echo 1 || echo 0)"
done
echo "  $P passed, $F failed"; [ "$F" = 0 ]
