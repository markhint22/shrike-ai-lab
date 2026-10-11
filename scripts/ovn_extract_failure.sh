#!/usr/bin/env bash
# ovn_extract_failure.sh — pull a short, GROUNDED summary of the most recent real test
# failure out of a task log. Used by both the same-cycle fix-up (Tier 2) and the
# cross-cycle lastfail memory (Tier 3). Deliberately never paraphrases: Reflexion
# (arXiv:2303.11366) found that reflection WITHOUT grounded evidence can perform WORSE
# than no reflection at all (52% vs 60% in their ablation) - this only ever surfaces
# real pytest/vitest output, verbatim, truncated to keep the injected prompt small.
#
# 2026-10-11 (gutparity X2): GUT (xlite) branch FIRST. The old fallback `grep -iE 'error|failed' | tail -6` returned Godot's exit-leak noise ("ERROR: 1 RID allocations ... leaked at
# exit", "9 resources still in use at exit") and never the failing test, so the Tier-2 fix-up prompt and the test-watch EMERGENCY item both said nothing useful. The GUT summary names the
# failing test(s) from, in order of preference: the last group of '--- GUT-FAIL-ID: tests/foo.gd::test_x' lines (run_overnight.sh, from the junit XML), else the last console
# 'Run Summary' block (res://file / '- test' / '[Failed]: text'), else the 'failing: name="..."' tail of '--- GUT RED:'; assertion text comes from the Run Summary block.
#
# Usage: ovn_extract_failure.sh <task_log>
# Prints a single line (empty if nothing found).
set -uo pipefail
log="${1:-}"
[ -f "$log" ] || exit 0

# pytest: "FAILED tests/foo.py::test_bar - AssertionError: ..." plus the assert/E line
# immediately above it (pytest prints the assertion detail before the FAILED summary).
py="$(grep -B2 -E '^FAILED ' "$log" 2>/dev/null | grep -E '^(FAILED |E +|>.*assert)' | head -6)"

# vitest/jest: a failing test name line (❯) plus an assertion/expectation line.
js="$(grep -E '❯ .*\.(test|spec)\.[jt]sx?|AssertionError:|expected .* to (be|equal|deep)' "$log" 2>/dev/null | head -6)"

# GUT: only when the log actually carries a GUT red (a GUT-FAIL-ID line, a '--- GUT RED' line, or a console Run Summary block with a '[Failed]' line).
gut=""
if grep -aqE '^--- GUT-FAIL-ID: |^--- GUT RED|Run Summary' "$log" 2>/dev/null; then
  gut="$(sed $'s/\033\\[[0-9;]*m//g' "$log" 2>/dev/null | awk '
    function strip(t) { sub(/^res:\/\//, "", t); return t }
    function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t\r]+$/, "", t); return t }
    /^--- GUT-FAIL-ID: / {
      if (prev != "id" && prev != "red") { ng = 0; delete gid }
      t = trim(substr($0, 17))
      ng++; gid[ng] = t; prev = "id"; next
    }
    /^--- GUT RED/ { prev = "red"; ng = 0; delete gid; redline = $0; next }
    /Run Summary/ { insum = 1; ns = 0; delete sid; delete stext; cf = ""; ct = ""; prev = ""; next }
    /^---- Totals ----/ { insum = 0; prev = ""; next }
    insum && /^res:\/\// { cf = trim($0); ct = ""; prev = ""; next }
    insum && /^- / { ct = trim(substr($0, 3)); prev = ""; next }
    insum && /\[Failed\]/ && cf != "" && ct != "" {
      key = strip(cf) "::" ct
      if (!(key in stext)) { ns++; sid[ns] = key; stext[key] = "" }
      t = $0; sub(/^.*\[Failed\]:?[ \t]*/, "", t); t = trim(t)
      if (t != "" && length(stext[key]) < 160) stext[key] = (stext[key] == "" ? t : stext[key] " / " t)
      prev = ""; next
    }
    { prev = "" }
    END {
      n = 0; out = ""
      if (ng > 0) { for (i = 1; i <= ng && n < 6; i++) { k = gid[i]; e = k; if (k in stext && stext[k] != "") e = k " - " stext[k]; out = out (n ? "; " : "") e; n++ } }
      else if (ns > 0) { for (i = 1; i <= ns && n < 6; i++) { k = sid[i]; e = k; if (stext[k] != "") e = k " - " stext[k]; out = out (n ? "; " : "") e; n++ } }
      else if (redline != "") {
        r = redline; if (match(r, /failing:.*/)) { r = substr(r, RSTART + 8); gsub(/name="/, "", r); gsub(/" ?/, " ", r); r = trim(r); if (r != "") out = r }
      }
      if (out != "") print "GUT failing: " out
    }' 2>/dev/null)"
fi

summary="${py:-$js}"
if [ -n "$gut" ]; then summary="$gut${summary:+ | $summary}"; fi
if [ -z "$summary" ]; then
  # fallback: last few error/failed lines in the log, still real output not a paraphrase. The Godot/GUT exit-leak noise is not a failure (2026-10-11).
  summary="$(grep -iE 'error|failed' "$log" 2>/dev/null | grep -vE 'RID allocations|resources still in use|leaked at exit' | tail -6)"
fi
[ -z "$summary" ] && exit 0

printf '%s' "$summary" | tr '\n' ' ' | tr -s ' ' | cut -c1-500
