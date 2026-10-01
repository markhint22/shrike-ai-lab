#!/usr/bin/env bash
# lib_gut_xml.sh - ONE correct "is this GUT junit report green?" check (2026-10-01).
#
# Replaces `grep -qE 'failures="0"' "$xml"` in branch_hygiene.sh, run_overnight.sh and ovn_stage_runner.sh. That grep matches ANY
# per-file <testsuite ... failures="0"> line, so a report whose ROOT is <testsuites failures="3"> still "passed": xlite's main/develop sat
# red (3 failing tests in tests/test_scar.gd) from 2026-09-29 while every Godot gate said green (376 matching lines in a red report).
#
#   gut_xml_green FILE   -> 0 = green, 1 = red / unreadable.  Green requires ALL of:
#     * the file exists and is non-empty
#     * no failures="N" / errors="N" attribute with N>0 anywhere, and no <failure>/<error> element (so a red ROOT <testsuites failures="3">
#       is red even when 376 per-file lines say failures="0")
#     * no testcase carries status="no asserts"
#   gut_xml_summary FILE -> one line for logs: root attributes + names of failing tests (never raises).
gut_xml_green() {
  local x="${1:-}"
  [ -n "$x" ] && [ -s "$x" ] || return 1
  grep -q 'status="no asserts"' "$x" 2>/dev/null && return 1
  # ANY non-zero failures/errors attribute anywhere is red (the root <testsuites> totals are >= every child, but a hand-built or odd
  # report may only mark a child) - and any <failure>/<error> element is red. A zero count never makes anything green by itself.
  grep -qE '(failures|errors)="[1-9][0-9]*"' "$x" 2>/dev/null && return 1
  grep -qE '<failure|<error' "$x" 2>/dev/null && return 1
  return 0
}

gut_xml_summary() {
  local x="${1:-}" root
  [ -n "$x" ] && [ -s "$x" ] || { echo "no junit xml"; return 0; }
  root="$(head -c 8000 "$x" 2>/dev/null | tr '\n\r' '  ' | grep -oE '<testsuites[^>]*>' | head -1)"
  echo "root: ${root:-<none>} | failing: $(grep -B1 -E '<failure|<error' "$x" 2>/dev/null | grep -oE '<testcase[^>]*name="[^"]*"' | grep -oE 'name="[^"]*"' | head -5 | tr '\n' ' ')"
}
