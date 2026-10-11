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

# gut_xml_failing_ids FILE -> one id per RED testcase, "<classname>::<testcase name>" (res:// stripped), de-duplicated, in report order. 2026-10-11 (gutparity, X2): every
# parity helper (baseline subtraction, repeat breaker, failure extractor) is keyed on test ids, and GUT only ever produced the free-text "GUT RED: ... failing: name=" line, so
# a pre-existing red GUT test was billed to every later cycle (xlite: 21 reverts for ONE stub-vs-absence test). Red = status fail|error|no asserts, or a <failure>/<error>
# child (an orphan one without a testcase is named "<testsuite>::(suite-level)"). Pure awk (BWK + mawk + gawk), never raises, prints nothing for a missing/empty report.
gut_xml_failing_ids() {
  local x="${1:-}"
  [ -n "$x" ] && [ -s "$x" ] || return 0
  awk '
    BEGIN { RS = "<"; suite = ""; cur = ""; cls = ""; emitted = 0 }
    function attr(s, k,    p, r, q) {
      p = index(s, " " k "=\"")
      if (!p) return ""
      r = substr(s, p + length(k) + 3); q = index(r, "\"")
      return (q ? substr(r, 1, q - 1) : "")
    }
    function emit(id) {
      sub(/^res:\/\//, "", id)
      if (!(id in seen)) { seen[id] = 1; print id }
    }
    {
      if (!match($0, /^[A-Za-z!\/][^ \t\r\n>\/]*/)) next
      tag = substr($0, 1, RLENGTH)
      if (tag == "testsuite") { suite = attr($0, "name"); next }
      if (tag == "testcase") {
        cur = attr($0, "name"); cls = attr($0, "classname"); if (cls == "") cls = suite
        emitted = 0
        st = attr($0, "status")
        if (st == "fail" || st == "error" || st == "no asserts") { emit(cls "::" cur); emitted = 1 }
        if ($0 ~ /\/>[ \t\r\n]*$/) cur = ""
        next
      }
      if (tag == "/testcase") { cur = ""; next }
      if (tag == "failure" || tag == "error") {
        if (cur != "") { if (!emitted) { emit(cls "::" cur); emitted = 1 } }
        else emit(suite "::(suite-level)")
      }
    }
  ' "$x" 2>/dev/null
}

# gut_xml_ids_complete FILE -> rc 0 when EVERY red thing in the report is covered by an id from gut_xml_failing_ids: the number of <failure>/<error> elements equals the root's
# failures+errors counts (a missing attribute counts 0) and at least one id exists. A report whose root counts more reds than it names (odd/handwritten/truncated) is NOT complete,
# and the baseline subtraction then keeps the old revert (a hidden red is worse than a false revert).
gut_xml_ids_complete() {
  local x="${1:-}" root f e n have
  [ -n "$x" ] && [ -s "$x" ] || return 1
  root="$(head -c 8000 "$x" 2>/dev/null | tr '\n\r' '  ' | grep -oE '<testsuites[^>]*>' | head -1)"
  [ -n "$root" ] || return 1
  f="$(printf '%s' "$root" | grep -oE ' failures="[0-9]+"' | grep -oE '[0-9]+' | head -1)"; f="${f:-0}"
  e="$(printf '%s' "$root" | grep -oE ' errors="[0-9]+"' | grep -oE '[0-9]+' | head -1)"; e="${e:-0}"
  n="$(grep -oE '<(failure|error)[ />]' "$x" 2>/dev/null | wc -l | tr -d ' ')"
  have="$(gut_xml_failing_ids "$x" | grep -c . || true)"
  [ "${have:-0}" -ge 1 ] 2>/dev/null || return 1
  [ "$n" -eq $((f + e)) ] 2>/dev/null
}

# gut_xml_emit_fail_ids FILE -> stdout: "--- GUT-FAIL-ID: tests/foo.gd::test_x" per red test (at most OVN_GUT_FAIL_ID_MAX=100), then "--- GUT-FAIL-IDS-COMPLETE ---" when the
# list covers every red in the report. run_overnight.sh appends this next to "--- GUT RED:"; lib_run_integrity.sh / lib_item_select.sh / ovn_extract_failure.sh read it.
gut_xml_emit_fail_ids() {
  local x="${1:-}" ids n max="${OVN_GUT_FAIL_ID_MAX:-100}"
  case "$max" in ''|*[!0-9]*) max=100;; esac
  ids="$(gut_xml_failing_ids "$x")"
  [ -n "$ids" ] || return 0
  n="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  printf '%s\n' "$ids" | head -n "$max" | sed 's/^/--- GUT-FAIL-ID: /'
  if [ "$n" -le "$max" ] && gut_xml_ids_complete "$x"; then echo "--- GUT-FAIL-IDS-COMPLETE ---"; fi
  return 0
}

# gut_ignored_scripts LOGFILE: the script path of EVERY 'Ignoring script <path> because ...' line, de-duplicated, one per line, 'res://' stripped. 2026-10-10: the
# alert used to print the first 3 raw lines cut at 200 chars, so the 4th ignored script of an alert ('4 script(s)') was never named.
gut_ignored_scripts() {
  [ -n "${1:-}" ] && [ -r "$1" ] || return 0
  grep -E 'Ignoring script' "$1" 2>/dev/null | sed -E 's/^.*Ignoring script[[:space:]]+//; s/[[:space:]]+because.*$//; s@^res://@@' | sort -u
}

# gut_new_ignored GITDIR BASEREF <ignored paths on stdin-less $3, newline separated>: the subset of those scripts that were NOT already non-GUT at BASEREF (absent there,
# or extending GutTest there) = scripts that became ignored with this change. Static approximation of 'Ignoring script count vs the base ref' (no second GUT run).
gut_new_ignored() {
  local gd="${1:-}" ref="${2:-}" list="${3:-}" p txt
  [ -n "$gd" ] && [ -n "$ref" ] && [ -n "$list" ] || return 0
  git -C "$gd" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1 || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if txt="$(git -C "$gd" show "$ref:$p" 2>/dev/null)" && ! grep -qE '^extends[[:space:]]+(GutTest|["'"'"']res://addons/gut/test\.gd["'"'"'])' <<< "$txt"; then
      continue    # already a non-GUT script at the base: pre-existing, not new
    fi
    printf '%s\n' "$p"
  done <<< "$list"
}

# gut_log_skips_note LOGFILE REPO [STATE_DIR] [GITDIR BASEREF] - SHADOW check (2026-10-03): GUT silently skips a test script it cannot parse ("Ignoring script",
# "Parse Error") and still exits 0 with a green junit xml, so tests that were never run count as passing (xlite had 3 such scripts: an
# 'extends GUTTest' typo, assert_le, an empty file). Appends ONE alerts.log warn line per (repo, distinct skip set), deduped via
# state/gut_skip_seen.txt. Missing/unreadable log or state dir -> silently nothing.
# 2026-10-10: the line names EVERY ignored script; with GITDIR+BASEREF (hygiene passes the worktree and origin/<merge target>) it also names the ones that are NEW vs the
# base ref. OVN_GUT_SKIPS_NEW=shadow (default: only the alert text) | enforce (return 1 when a NEW script is ignored - the caller fails the gate; NOT deduped) | off.
# Returns 0 always except in enforce mode with a NEW ignored script.
gut_log_skips_note() {
  local log="${1:-}" repo="${2:-?}" sd="${3:-${STATE_DIR:-state}}" gd="${4:-}" ref="${5:-}" n sig ign nign newl="" perr rc=0 txt
  [ -n "$log" ] && [ -s "$log" ] && [ -d "$sd" ] || return 0
  n="$(grep -cE 'Ignoring script|Parse Error' "$log" 2>/dev/null)"; n="${n:-0}"
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  ign="$(gut_ignored_scripts "$log")"
  if [ -n "$ign" ] && [ -n "$gd" ] && [ -n "$ref" ] && [ "${OVN_GUT_SKIPS_NEW:-shadow}" != off ]; then
    newl="$(gut_new_ignored "$gd" "$ref" "$ign")"
    [ "${OVN_GUT_SKIPS_NEW:-shadow}" = enforce ] && [ -n "$newl" ] && rc=1
  fi
  sig="$repo:$(grep -E 'Ignoring script|Parse Error' "$log" | sort -u | md5sum | cut -c1-12)"
  grep -qxF "$sig" "$sd/gut_skip_seen.txt" 2>/dev/null && return $rc
  echo "$sig" >> "$sd/gut_skip_seen.txt" 2>/dev/null
  txt=""
  [ -n "$ign" ] && txt="ignored (does not extend GutTest): $(printf '%s' "$ign" | tr '\n' ',' | sed 's/,/, /g; s/, $//')"
  [ -n "$newl" ] && txt="$txt; NEW vs $ref: $(printf '%s' "$newl" | tr '\n' ',' | sed 's/,/, /g; s/, $//')"
  perr="$(grep -E 'Parse Error' "$log" | sort -u | head -3 | tr '\n' ';' | cut -c1-200)"
  [ -n "$perr" ] && txt="${txt:+$txt; }$perr"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] warn | gut-skips:$repo | GUT ignored/failed to parse $n script(s) yet exited green - those tests are NOT running: $txt" >> "$sd/alerts.log" 2>/dev/null
  return $rc
}
