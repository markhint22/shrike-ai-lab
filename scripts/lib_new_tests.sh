#!/usr/bin/env bash
# lib_new_tests.sh - explicitly run the NEW / CHANGED test files of a cycle (2026-10-04, QA audit H).
#
# Why: a new test file that the repo's verify command never collects (iptv app/**/test_*.py with `pytest tests/`; xlite tests/battle/* before
# -ginclude_subdirs; test/ (singular)) "passes" silently - 12 iptv files never ran, 4 of them failing. After the fleet's own verify, the stage
# runner runs exactly the files the cycle added/changed and requires them green.
#
#   ovn_new_test_files WT BEFORE_REF        -> prints changed/new (A/M + untracked) test file paths (repo-relative), one per line.
#       --no-renames: a RENAMED test file shows as 'R' under git's default rename detection and was silently skipped (review fix); core.quotepath=off keeps non-ASCII names usable.
#   ovn_run_new_tests WT PKG PYTEST GODOT BEFORE_REF LOG
#       WT = worktree, PKG = python package dir relative to WT ('.' or 'iptv-backend'), PYTEST = pytest executable (or '' to skip python),
#       GODOT = godot binary (or '' to skip GUT), LOG = file the output is appended to.
#   returns 0 = green OR nothing to run OR infrastructure trouble (timeout / missing tool / usage error / internal error: PROCEED),
#           1 = a new/changed test file ran and FAILED (pytest rc 1/2, GUT junit not green).  Never raises.
# Kill switch: OVN_RUN_NEW_TESTS=off (checked by the caller AND here). Max files per run: OVN_NEW_TESTS_MAX (default 25; more => the first 25).
ovn_new_test_files() {
  local wt="$1" before="$2"
  [ -d "$wt" ] || return 0
  { git -C "$wt" -c core.quotepath=off diff --no-renames --name-only --diff-filter=AM "$before" -- 2>/dev/null; git -C "$wt" -c core.quotepath=off ls-files -o --exclude-standard 2>/dev/null; } | sort -u | \
    grep -E '(^|/)(test_[^/]*\.py|[^/]*_test\.py|test_[^/]*\.gd|[^/]*_test\.gd)$' | grep -vE '(^|/)(node_modules|\.venv|venv|addons)/' || true
}

ovn_run_new_tests() {
  local wt="$1" pkg="${2:-.}" pytest="${3:-}" godot="${4:-}" before="${5:-HEAD}" log="${6:-/dev/null}"
  [ "${OVN_RUN_NEW_TESTS:-on}" = "off" ] && return 0
  [ -d "$wt" ] || return 0
  local max="${OVN_NEW_TESTS_MAX:-25}" files py=() gd=() f rel rc
  files="$(ovn_new_test_files "$wt" "$before" | head -n "$max")"
  [ -n "$files" ] || return 0
  while IFS= read -r f; do
    [ -f "$wt/$f" ] || continue
    case "$f" in
      *.py) if [ "$pkg" = "." ]; then py+=("$f"); else case "$f" in "$pkg"/*) py+=("${f#"$pkg"/}");; esac; fi ;;
      *.gd) grep -qE '^extends[[:space:]]+(GutTest|"res://addons/gut/test.gd")' "$wt/$f" 2>/dev/null && gd+=("res://$f") ;;
    esac
  done <<< "$files"
  local bad=0
  if [ "${#py[@]}" -gt 0 ] && [ -n "$pytest" ] && [ -x "$pytest" ]; then
    echo "-- new/changed python tests (explicit run): ${py[*]} --" >> "$log"
    ( cd "$wt/$pkg" && timeout "${OVN_NEW_TESTS_TIMEOUT:-300}" "$pytest" -q -o addopts="" -p no:cacheprovider "${py[@]}" ) >> "$log" 2>&1; rc=$?
    case "$rc" in
      0|5) : ;;                                         # green / nothing collected in a file with no tests
      1|2) echo "-- NEW-TESTS RED: explicit run of new/changed python test file(s) failed (pytest rc=$rc) --" >> "$log"; bad=1 ;;
      *)   echo "-- new-tests: infra rc=$rc (timeout/usage/internal) - proceeding --" >> "$log" ;;
    esac
  fi
  if [ "${#gd[@]}" -gt 0 ] && [ -n "$godot" ] && [ -x "$godot" ] && [ -f "$wt/project.godot" ] && [ -f "$wt/addons/gut/gut_cmdln.gd" ]; then
    local xml gl list; xml="$(mktemp)"; gl="$(mktemp)"; list="$(IFS=,; echo "${gd[*]}")"
    echo "-- new/changed GUT tests (explicit -gtest): ${gd[*]} --" >> "$log"
    ( cd "$wt" && timeout "${OVN_NEW_TESTS_TIMEOUT:-120}" "$godot" --headless -s addons/gut/gut_cmdln.gd "-gtest=$list" -gexit "-gjunit_xml_file=$xml" ) > "$gl" 2>&1; rc=$?
    cat "$gl" >> "$log" 2>/dev/null
    if [ ! -s "$xml" ]; then
      echo "-- new-tests: GUT produced no junit xml (rc=$rc) - infra, proceeding --" >> "$log"
    elif command -v gut_xml_green >/dev/null 2>&1 && ! gut_xml_green "$xml"; then
      echo "-- NEW-TESTS RED: explicit GUT run of new/changed test file(s) failed: $(gut_xml_summary "$xml" 2>/dev/null) --" >> "$log"; bad=1
    elif grep -qE 'Failed to load script|Failed to compile|Parse Error' "$gl" 2>/dev/null; then
      echo "-- NEW-TESTS RED: new/changed GUT test failed to parse/compile --" >> "$log"; bad=1
    fi
    rm -f "$xml" "$gl"
  fi
  [ "$bad" = 0 ]
}
