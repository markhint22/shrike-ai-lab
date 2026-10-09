#!/usr/bin/env bash
# lib_fixup.sh - cause-aware direction for the Tier-2 fix-up (2026-10-01, feedback-loops analysis).
# The old prompt always said "prefer fixing the TEST's expectation, do not change the source unless clearly the bug". That is right for a test the
# model JUST ADDED, and exactly backwards for a test that PASSED before the change: there the model's own source edit broke existing behaviour
# (230 NO-NEW-RED 'source broke a previously-green test' cases in 14 days; the fix-up rescued 3).
#   ovn_fixup_kind <failure-summary> <newline-separated list of test files ADDED by the red commit> [<before_sha> <failing ids>]
#     -> prints "own-test"  when the failure names one of the added test files (the model's new test is wrong or mis-mocked)
#     -> prints "source-broke-green" otherwise (no new tests, or the failing test is an older one)
#   2026-10-09 (harness-credit-integrity item 3): with the optional <before_sha> + failing test ids the decision is made PER ID, not from added-file
#   basenames. `git diff --diff-filter=A` is blank whenever a placeholder stub was committed first ("Placeholder - the implement step fills this in."),
#   because the model's commit then MODIFIES the stub: its brand-new failing test was classed source-broke-green and the fix-up was told to restore the
#   old behaviour (the item was undone). A failing id is OWN when at BEFORE_SHA (a) its file is absent, or (b) the file does not define the test
#   function/name, or (c) the file is only the harness placeholder stub. OVN_OWN_TEST_IDS=off keeps the old basename rule.
#   A third answer is UNKNOWN: the id's file is absent at BEFORE_SHA AND cannot be found at the after-commit either (a path relative to some subproject dir,
#   or a test deleted again), or a subproject-relative id matches SEVERAL tracked paths. Claiming "own" there would flip the fix-up direction for tests that
#   already passed (the original bug in reverse) and skip the NEEDS-DECISION park, so UNKNOWN ids fall back to the old added-file-basename rule.
OVN_FIXUP_PLACEHOLDER_TEXT="Placeholder - the implement step fills this in"
# portable in-place sed (GNU on the box, BSD on the Mac where the tests run): GNU sed accepts `-i` alone, BSD sed needs `-i ''`
_ovn_sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }


# _ovn_fx_split_id <id> -> sets _FX_FILE (path as written in the id) and _FX_NAME (test function/name, may be empty for a file-level id)
#   pytest  tests/test_x.py::TestC::test_name[param]   vitest/jest  src/a.spec.ts > describe > test name
_ovn_fx_split_id() {
  local id="${1:-}" rest
  _FX_FILE=""; _FX_NAME=""
  case "$id" in
    *::*) _FX_FILE="${id%%::*}"; rest="${id#*::}"; _FX_NAME="${rest##*::}"; _FX_NAME="${_FX_NAME%%\[*}" ;;
    *" > "*) _FX_FILE="${id%% > *}"; rest="${id#* > }"; _FX_NAME="${rest##* > }" ;;
    *) _FX_FILE="$id" ;;
  esac
  _FX_FILE="${_FX_FILE#./}"
}

# _ovn_fx_resolve_at <sha> <path>: prints the path as tracked at <sha> (exact, else the unique '*/<path>' suffix match, e.g. an id relative to a subproject
# directory); prints nothing when the file does not exist there and the sentinel AMBIGUOUS when several tracked paths match the suffix. Pure bash membership
# (no pipe into grep -q: pipefail/SIGPIPE flaky for big trees).
_ovn_fx_resolve_at() {
  local sha="$1" path="$2" tree cand hit="" n=0
  [ -n "$path" ] || return 0
  if git cat-file -e "${sha}:${path}" 2>/dev/null; then printf '%s\n' "$path"; return 0; fi
  tree="$(git ls-tree -r --name-only "$sha" 2>/dev/null)"
  while IFS= read -r cand; do
    case "$cand" in */"$path") hit="$cand"; n=$((n + 1)) ;; esac
  done <<< "$tree"
  if [ "$n" = 1 ]; then printf '%s\n' "$hit"; elif [ "$n" -gt 1 ]; then printf 'AMBIGUOUS\n'; fi
  return 0
}

# ovn_test_id_is_own <before_sha> <id> [<after_ref>=HEAD]: rc 0 when the failing test id is the change's OWN (see the rules above), rc 1 when it already
# existed at <before_sha>, rc 2 when it cannot be decided (UNKNOWN: file absent at BEFORE and not at <after_ref> either, or an ambiguous path suffix).
ovn_test_id_is_own() {
  local sha="$1" id="${2:-}" after="${3:-HEAD}" f tmp own=1
  _ovn_fx_split_id "$id"
  [ -n "$_FX_FILE" ] || return 1
  case "$_FX_FILE" in *.*) ;; *) return 1 ;; esac            # not a file-shaped id (no extension): cannot judge, never claim "own"
  f="$(_ovn_fx_resolve_at "$sha" "$_FX_FILE")"
  [ "$f" = AMBIGUOUS ] && return 2                           # several tracked paths share the suffix: cannot tell which one the id meant
  if [ -z "$f" ]; then                                       # (a) file absent at BEFORE: own only when the change really has it (added/created); else unknown
    f="$(_ovn_fx_resolve_at "$after" "$_FX_FILE")"
    [ -n "$f" ] && [ "$f" != AMBIGUOUS ] && return 0
    return 2
  fi
  tmp="$(mktemp 2>/dev/null)" || return 1
  git show "${sha}:${f}" > "$tmp" 2>/dev/null
  if grep -qF -- "$OVN_FIXUP_PLACEHOLDER_TEXT" "$tmp"; then own=0   # (c) the file was only the placeholder stub
  elif [ -n "$_FX_NAME" ]; then
    case "$_FX_NAME" in
      *[!A-Za-z0-9_]*) grep -qF -- "$_FX_NAME" "$tmp" || own=0 ;;   # JS-style test title: fixed-string substring
      *) grep -qwF -- "$_FX_NAME" "$tmp" || own=0 ;;                 # (b) python/gd identifier: whole word, so test_foo is not 'present' because test_foo_bar is
    esac
  fi
  rm -f "$tmp"
  return "$own"
}

# ovn_fixup_own_test_ids <before_sha> <newline-separated ids> [<after_ref>]: prints the ids that are OWN, one per line (empty when none).
ovn_fixup_own_test_ids() {
  local sha="$1" ids="${2:-}" after="${3:-HEAD}" id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    ovn_test_id_is_own "$sha" "$id" "$after"
    [ $? = 0 ] && printf '%s\n' "$id"
  done <<< "$ids"
  return 0
}

# ovn_fixup_unknown_test_ids <before_sha> <ids> [<after_ref>]: prints the ids ovn_test_id_is_own cannot decide (rc 2), one per line.
ovn_fixup_unknown_test_ids() {
  local sha="$1" ids="${2:-}" after="${3:-HEAD}" id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    ovn_test_id_is_own "$sha" "$id" "$after"
    [ $? = 2 ] && printf '%s\n' "$id"
  done <<< "$ids"
  return 0
}

# _ovn_fx_added_basename_hit <before_sha> <after_ref> <ids>: the OLD rule - rc 0 when an id's file basename equals the basename of a file ADDED between the two.
_ovn_fx_added_basename_hit() {
  local before="$1" after="$2" ids="${3:-}" added id b
  added="$(git diff --name-only --diff-filter=A "$before" "$after" -- . 2>/dev/null)"
  [ -n "$added" ] || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    _ovn_fx_split_id "$id"; b="${_FX_FILE##*/}"
    [ -n "$b" ] || continue
    case $'\n'"$added"$'\n' in *"/$b"$'\n'*|*$'\n'"$b"$'\n'*) return 0 ;; esac
  done <<< "$ids"
  return 1
}

# ovn_item_leading_path <item line>: the item's own leading path token ("- [ ] [T2] tests/test_x.py - Add ..." -> tests/test_x.py), backticks and :line stripped.
ovn_item_leading_path() {
  local b="${1:-}"
  b="${b#- \[ \] }"; b="${b#- \[x\] }"; b="${b#- \[X\] }"
  while :; do
    case "$b" in
      "["*"]"*) b="${b#*]}"; b="${b# }" ;;
      "("*")"*) b="${b#*)}"; b="${b# }" ;;
      *) break ;;
    esac
  done
  b="${b%% *}"; b="${b//\`/}"; b="${b%%:*}"
  printf '%s\n' "$b"
}

# ovn_fixup_ids_hit_target <item line> <ids>: rc 0 when the failing test file of ANY id is the item's own target file (path equal, or one is a path-suffix of the other).
ovn_fixup_ids_hit_target() {
  local tgt id
  tgt="$(ovn_item_leading_path "${1:-}")"
  [ -n "$tgt" ] || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    _ovn_fx_split_id "$id"
    [ -n "$_FX_FILE" ] || continue
    case "$_FX_FILE" in "$tgt"|*/"$tgt") return 0 ;; esac
    case "$tgt" in "$_FX_FILE"|*/"$_FX_FILE") return 0 ;; esac
  done <<< "${2:-}"
  return 1
}

# ovn_fixup_ids_old_only <before_sha> <ids> [item line] [after_ref=HEAD]: rc 0 when there ARE ids, NONE of them is own and (when an item line is given) NONE of
# their files is the item's own target - i.e. the failing tests are pre-existing ones the change broke. UNKNOWN ids (see above) are judged by the old rule: own
# only when a file with that basename was ADDED between <before_sha> and <after_ref>. This is the NEEDS-DECISION guard's precondition (OVN_OWN_TEST_IDS=off: the
# caller falls back to the old added-file-basename test).
ovn_fixup_ids_old_only() {
  local sha="$1" ids="${2:-}" item="${3:-}" after="${4:-HEAD}" unk
  [ -n "$ids" ] || return 1
  [ -z "$(ovn_fixup_own_test_ids "$sha" "$ids" "$after")" ] || return 1
  unk="$(ovn_fixup_unknown_test_ids "$sha" "$ids" "$after")"
  if [ -n "$unk" ] && _ovn_fx_added_basename_hit "$sha" "$after" "$unk"; then return 1; fi
  if [ -n "$item" ] && ovn_fixup_ids_hit_target "$item" "$ids"; then return 1; fi
  return 0
}

ovn_fixup_kind() {
  local summary="${1:-}" newtests="${2:-}" before="${3:-}" ids="${4:-}" nt base unk
  if [ -n "$before" ] && [ -n "$ids" ] && [ "${OVN_OWN_TEST_IDS:-on}" != off ]; then
    if [ -n "$(ovn_fixup_own_test_ids "$before" "$ids")" ]; then echo "own-test"; return 0; fi
    unk="$(ovn_fixup_unknown_test_ids "$before" "$ids")"
    [ -z "$unk" ] && { echo "source-broke-green"; return 0; }
    # UNKNOWN ids (file unresolvable / ambiguous): fall through to the old added-file rule below instead of claiming own OR old
  fi
  while IFS= read -r nt; do
    [ -n "$nt" ] || continue
    base="$(basename "$nt")"
    case "$summary" in *"$base"*) echo "own-test"; return 0;; esac
  done <<< "$newtests"
  echo "source-broke-green"
}
# ovn_fixup_direction <kind> -> the sentence appended to the fix-up prompt
ovn_fixup_direction() {
  case "${1:-}" in
    own-test) echo "The failing test is NEW: the committed change added it (or filled in its placeholder stub): prefer fixing the TEST's expectation/mocks to match the real behaviour of the source shown, or the NEW code when that is clearly the bug. Never restore old behaviour and never delete or empty the new test or undo the committed change: it is the task." ;;
    *) echo "This failing test PASSED before the committed change, so that change broke existing behaviour. Fix the SOURCE change so the existing test passes again (restore the old behaviour). Only edit that existing test if the item text explicitly says this behaviour must change." ;;
  esac
}

# ovn_is_delete_intent <text>: 0 when the item text's LEADING instruction is a whole-FILE delete (ovn_delete_executor.py intent), 1 otherwise.
# 2026-10-09 (harness-credit-integrity item 2): replaces the runner's inline "delete/remove ... file(s)" regex, which also matched "Remove the unused
# import(s) in this file: ..." and told the model to write a DELETE: trailer instead of editing the file. OVN_DELETE_INTENT=legacy restores the old regex.
ovn_is_delete_intent() {
  local text="${1:-}" _py
  _py="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ovn_delete_executor.py"
  # OVN_DELETE_INTENT=legacy, or ovn_delete_executor.py not deployed next to this lib: the old regex (same fallback run_overnight.sh uses when THIS lib is missing,
  # so a half-deployed tree never silently stops injecting the DELETE-trailer hint for a real delete item)
  if [ "${OVN_DELETE_INTENT:-new}" = legacy ] || [ ! -f "$_py" ]; then
    grep -qiE '\b(delete|deletes|deleting|deleted|remove|removes|removing|removed)\b.{0,60}\bfiles?\b|\bfiles?\b.{0,60}\b(delete|deletes|deleting|deleted|remove|removes|removing|removed)\b' <<< "$text"
    return $?
  fi
  python3 "$_py" intent "$text" >/dev/null 2>&1
}

# ovn_fixup_nd_precondition <before_sha> <after_sha> <failing ids>: the NEEDS-DECISION guard's first test - rc 0 when every failing id is a PRE-EXISTING test (none
# was added/filled-in by the change). Id-based (ovn_fixup_ids_old_only); OVN_OWN_TEST_IDS=off restores the old rule (no added-file basename matches a failing file).
ovn_fixup_nd_precondition() {
  local before="$1" after="$2" ids="${3:-}"
  if [ "${OVN_OWN_TEST_IDS:-on}" != off ]; then ovn_fixup_ids_old_only "$before" "$ids" "" "$after"; return $?; fi
  [ -z "$(git diff --name-only --diff-filter=A "$before" "$after" -- . 2>/dev/null | grep -F -f <(printf '%s\n' "$ids" | sed -E 's#::.*##; s#.*/##' | grep .))" ]
}

# =====================================================================================================================================================
# FIX-UP MUST NOT UNDO THE ITEM (2026-10-09, harness-credit-integrity item 5)
# xlite remove/restore ping-pong (12 and 9 landed cycles, 21 pairs) and iptv fix-ups that deleted the model's own tests: the Tier-2 / BUILD-GATE fix-up fixes the
# red by undoing the committed change, the net diff on the item's own file is empty and the cycle still lands as a "pass".
#   (a) NET-ZERO GUARD, ENFORCED by default (OVN_FIXUP_UNDO_GUARD=off disables): the main commit changed the item's target file but BEFORE_SHA..HEAD has no net
#       diff on it => git reset --hard BEFORE_SHA, status no-op(fixup-undid-item). ovn_item_guard.sh bills it to the FAIL cap and keeps the text as lastfail.
#   (b) VERIFY RE-RUN, SHADOW by default (OVN_FIXUP_REVERIFY=shadow|enforce|off): the item's own VERIFY (shadow_check, lib_verify_clause.sh, unchanged) must
#       still pass after the fix-up; FAIL => '[fixup-verify-fail]' in the task log + alerts.log (info); enforce => reset + the same status.
#   (c) TEST-NAME RETENTION, same flag: every test function the main commit ADDED (test files, +lines of git diff -U0) must still exist at HEAD.
#   (d) TEST-ONLY GUARD, SHADOW by default (OVN_TESTONLY_GUARD=shadow|enforce|off): a test item (target under tests/ or cat:test) whose cycle diff touches files
#       outside tests/ and its target => '[prod-touch]' (status + alerts.log); enforce => reset, status reverted(test-item-touched-prod). Motivating incident: a
#       notifications 429 test item rewrote app/core/rate_limiting.py and reached prod.
# Every function is fail-safe: a missing lib or an unresolvable item means "no opinion" (gate returns 0 = keep).
# =====================================================================================================================================================

# _ovn_fx_is_testpath <path>: 0 for a test file/dir path (tests/, __tests__/, test_*.py, *_test.py|gd, *.test.*, *.spec.*, test_*.gd)
_ovn_fx_is_testpath() {
  case "${1:-}" in
    tests/*|test/*|*/tests/*|*/test/*|__tests__/*|*/__tests__/*|test_*|*/test_*|*_test.py|*_test.gd|*.test.*|*.spec.*) return 0 ;;
  esac
  return 1
}

# ovn_fixup_item_line <before_sha> <task_log>: prints "N:text" of the item the cycle worked, resolved against the BEFORE tree's OVERNIGHT_PROGRESS.md (the model's
# commit has usually ticked its own item, so the post-commit file would point at the NEXT item). Empty when unresolvable.
ovn_fixup_item_line() {
  local before="${1:-}" tl="${2:-}" d out=""
  declare -F ovn_resolve_top_item >/dev/null 2>&1 || return 0
  [ -n "$before" ] || return 0
  d="$(mktemp -d 2>/dev/null)" || return 0
  if git show "${before}:OVERNIGHT_PROGRESS.md" > "$d/OVERNIGHT_PROGRESS.md" 2>/dev/null; then out="$(ovn_resolve_top_item "$d" "$tl" 2>/dev/null)"; fi
  rm -rf "$d"
  # Wrong-item guard (harness-credit-integrity review): ovn_resolve_top_item falls back to the TOP of the file when the scout named files that no open item mentions.
  # That top item is then probably NOT what the cycle worked, and the gates below (which can reset the tree in enforce mode) must not act on it: when the log carries
  # scout file tokens and the resolved item text contains none of them, answer "unresolvable". No scout tokens at all => the top item is the best answer there is.
  if [ -n "$out" ] && [ "${OVN_FIXUP_ITEM_STRICT:-on}" != off ] && [ -n "$tl" ] && [ -f "$tl" ]; then
    local scouted f hit=0
    scouted="$( { grep -A4 -hiE "VERDICT:[[:space:]]*(PROCEED|NEEDS-DECISION)" "$tl" 2>/dev/null; grep -hiE "FILES:" "$tl" 2>/dev/null; } | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}" | grep -vE "\.md$" | sort -u)"
    if [ -n "$scouted" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "${out#*:}" in *"$f"*) hit=1; break ;; esac
      done <<< "$scouted"
      [ "$hit" = 1 ] || out=""
    fi
  fi
  printf '%s' "$out"
}

# ovn_fixup_item_target <item text>: the item's own leading file path normalised against the tracked files (empty when the item names no concrete file)
ovn_fixup_item_target() {
  local p
  p="$(ovn_item_leading_path "${1:-}")"
  case "$p" in ''|*[\*\?\[]*|http*|/*|.|..) return 0 ;; esac
  case "$p" in *.*) ;; *) return 0 ;; esac
  if declare -F ovn_normalize_path >/dev/null 2>&1; then p="$(ovn_normalize_path "$PWD" "$p")"; fi
  printf '%s' "$p"
}

# ovn_fixup_undid_item <before_sha> <main_sha> <target>: rc 0 when the MAIN commit changed <target> but HEAD carries no net diff against BEFORE for it
ovn_fixup_undid_item() {
  local before="$1" main="$2" tgt="${3:-}"
  [ -n "$tgt" ] || return 1
  git --literal-pathspecs diff --quiet "$before" "$main" -- "$tgt" 2>/dev/null && return 1   # the main commit never touched it: nothing to undo
  git --literal-pathspecs diff --quiet "$before" HEAD -- "$tgt" 2>/dev/null
}

# ovn_fixup_added_test_names <before_sha> <main_sha>: "file<TAB>name" for every test function/title the main commit ADDED (python def test_*, gdscript func test_*,
# JS it()/test() titles) in test files
ovn_fixup_added_test_names() {
  local line f="" t=0 q="'" re_py re_js
  re_py='^[[:space:]]*(async[[:space:]]+)?(def|func)[[:space:]]+(test_[A-Za-z0-9_]*)'
  re_js="^[[:space:]]*(it|test)(\.[a-z]+)?\([[:space:]]*[${q}\"\`]([^${q}\"\`]+)[${q}\"\`]"
  while IFS= read -r line; do
    case "$line" in
      "+++ "*) f="${line#+++ }"; f="${f#b/}"; t=0; if _ovn_fx_is_testpath "$f"; then t=1; fi ;;
      "---"*) ;;
      "+"*)
        [ "$t" = 1 ] || continue
        line="${line:1}"
        if [[ $line =~ $re_py ]]; then printf '%s\t%s\n' "$f" "${BASH_REMATCH[3]}"
        elif [[ $line =~ $re_js ]]; then printf '%s\t%s\n' "$f" "${BASH_REMATCH[3]}"; fi ;;
    esac
  done < <(git diff -U0 --no-color "$1" "$2" -- . 2>/dev/null)
}

# ovn_fixup_lost_tests <before_sha> <main_sha>: prints "file::name" for each test the main commit added that is missing at HEAD (empty = all kept)
ovn_fixup_lost_tests() {
  local before="$1" main="$2" f n tmp
  while IFS=$'\t' read -r f n; do
    [ -n "$f" ] && [ -n "$n" ] || continue
    if ! git cat-file -e "HEAD:${f}" 2>/dev/null; then printf '%s::%s\n' "$f" "$n"; continue; fi
    tmp="$(mktemp 2>/dev/null)" || continue
    git show "HEAD:${f}" > "$tmp" 2>/dev/null
    case "$n" in
      *[!A-Za-z0-9_]*) grep -qF -- "$n" "$tmp" || printf '%s::%s\n' "$f" "$n" ;;
      *) grep -qwF -- "$n" "$tmp" || printf '%s::%s\n' "$f" "$n" ;;
    esac
    rm -f "$tmp"
  done <<< "$(ovn_fixup_added_test_names "$before" "$main" | sort -u)"
  return 0
}

# ovn_testonly_is_test_item <item text> <target>: 0 when the item is a test item (target is a test path, or cat:test in the text)
ovn_testonly_is_test_item() {
  _ovn_fx_is_testpath "${2:-}" && return 0
  case "$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')" in *"cat:test"*) return 0 ;; esac
  return 1
}

# ovn_testonly_prod_touch <before_sha> <head> <item text> <target>: prints the files the cycle changed outside tests/ and the item target (bookkeeping files
# excluded); rc 0 when the item is a test item and there is at least one
ovn_testonly_prod_touch() {
  local before="$1" head="$2" text="$3" tgt="${4:-}" f out=""
  ovn_testonly_is_test_item "$text" "$tgt" || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in OVERNIGHT_PROGRESS.md|OVERNIGHT_DONE.md) continue ;; esac
    _ovn_fx_is_testpath "$f" && continue
    [ -n "$tgt" ] && [ "$f" = "$tgt" ] && continue
    out="${out:+$out }$f"
  done <<< "$(git diff --name-only "$before" "$head" -- . 2>/dev/null)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

_ovn_fxi_alert() { if declare -F emit_alert >/dev/null 2>&1; then emit_alert "$1" "${2:-fixup-integrity}" "$3" 2>/dev/null; fi; return 0; }
_ovn_fxi_log() { [ -n "${1:-}" ] && printf '%s\n' "--- $2 ---" >> "$1"; return 0; }
_ovn_fxi_reset() { git reset --hard "$1" --quiet 2>/dev/null; git clean -fd --quiet 2>/dev/null; return 0; }

# ovn_fixup_integrity_gate <phase> <before_sha> <main_sha> <task_log> [id]: run (a)+(b)+(c) after a fix-up commit. rc 0 = keep; rc 1 = the tree was reset to
# BEFORE_SHA and OVN_FXI_STATUS holds the status the caller must return (OVN_FXI_TEXT = the lastfail text, also logged as '--- fixup-integrity: ... ---').
OVN_FXI_STATUS=""; OVN_FXI_TEXT=""
ovn_fixup_integrity_gate() {
  local phase="$1" before="$2" main="$3" tl="${4:-}" id="${5:-fixup-integrity}" item text tgt sym ids mode lost
  OVN_FXI_STATUS=""; OVN_FXI_TEXT=""
  [ -n "$before" ] && [ -n "$main" ] || return 0
  item="$(ovn_fixup_item_line "$before" "$tl")"
  [ -n "$item" ] || return 0
  text="${item#*:}"; tgt="$(ovn_fixup_item_target "$text")"
  # (a) net-zero => the fix-up undid the item (enforced)
  if [ "${OVN_FIXUP_UNDO_GUARD:-on}" != off ] && ovn_fixup_undid_item "$before" "$main" "$tgt"; then
    sym=""; _bt=$'\x60'; _re="${_bt}([A-Za-z_][A-Za-z0-9_.]*)${_bt}"   # first backticked identifier of the item text
    if [[ $text =~ $_re ]]; then sym="${BASH_REMATCH[1]}"; fi
    ids="$(printf '%s' "${OVN_RI_NEW:-}" | head -3 | tr '\n' ' ' | sed 's/ *$//')"
    OVN_FXI_TEXT="fix-up reverted the item; tests ${ids:-that exercise it} still reference ${sym:-the changed code}; edit them in the same step"
    _ovn_fxi_log "$tl" "fixup-integrity: ${OVN_FXI_TEXT}"
    _ovn_fxi_log "$tl" "FIXUP-INTEGRITY (${phase}): the fix-up left no net change on ${tgt} - the committed item was undone; resetting to ${before:0:12}"
    _ovn_fxi_reset "$before"
    _ovn_fxi_alert warn "$id" "${phase} fix-up undid the item (no net diff on ${tgt}); reset to ${before:0:12}"
    OVN_FXI_STATUS="no-op(fixup-undid-item)"
    return 1
  fi
  mode="${OVN_FIXUP_REVERIFY:-shadow}"
  [ "$mode" = off ] && return 0
  # (b) the item's own VERIFY must still pass (shadow_check unchanged; INDETERMINATE results - timeout/unrunnable - are not a failure)
  if declare -F shadow_check >/dev/null 2>&1; then
    local PROG SHADOW_LOG _REPO_LABEL VERIFY_TIMEOUT_SECS="${OVN_FIXUP_VERIFY_TIMEOUT:-300}" VERIFY_TIMEOUT_HEAVY_SECS="${OVN_FIXUP_VERIFY_TIMEOUT_HEAVY:-900}" _VC_MEMO="" _VC_MEMO_ON=0
    PROG="$(mktemp 2>/dev/null)" && {
      printf '%s\n' "$text" > "$PROG"
      SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}"; mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
      _REPO_LABEL="$(basename "$PWD")"
      shadow_check 1
      rm -f "$PROG"
      if [ "${_LAST_VERIFY_RESULT:-}" = FAIL ]; then
        OVN_FXI_TEXT="after the ${phase} fix-up the item's own VERIFY no longer passes"
        _ovn_fxi_log "$tl" "[fixup-verify-fail] (${phase}, mode=${mode}) ${OVN_FXI_TEXT}"
        _ovn_fxi_alert info "$id" "[fixup-verify-fail] ${phase} fix-up: ${OVN_FXI_TEXT} (mode=${mode})"
        if [ "$mode" = enforce ]; then
          _ovn_fxi_log "$tl" "fixup-integrity: ${OVN_FXI_TEXT}"
          _ovn_fxi_reset "$before"; OVN_FXI_STATUS="no-op(fixup-undid-item)"; return 1
        fi
      fi
    }
  fi
  # (c) the tests the main commit added must still exist
  lost="$(ovn_fixup_lost_tests "$before" "$main" | head -5 | tr '\n' ' ' | sed 's/ *$//')"
  if [ -n "$lost" ]; then
    OVN_FXI_TEXT="the ${phase} fix-up removed test(s) the item added: ${lost}"
    _ovn_fxi_log "$tl" "[fixup-tests-lost] (${phase}, mode=${mode}) ${OVN_FXI_TEXT}"
    _ovn_fxi_alert info "$id" "[fixup-tests-lost] ${OVN_FXI_TEXT} (mode=${mode})"
    if [ "$mode" = enforce ]; then
      _ovn_fxi_log "$tl" "fixup-integrity: ${OVN_FXI_TEXT}; edit them in the same step instead of deleting them"
      OVN_FXI_TEXT="${OVN_FXI_TEXT}; edit them in the same step instead of deleting them"
      _ovn_fxi_reset "$before"; OVN_FXI_STATUS="no-op(fixup-undid-item)"; return 1
    fi
  fi
  return 0
}

# ovn_testonly_guard <before_sha> <task_log> [id]: (d). rc 0 = keep (OVN_TOGUARD_TAG is '[prod-touch]' in shadow mode when it would have fired, else empty);
# rc 1 = enforce mode reset the tree (OVN_FXI_STATUS = reverted(test-item-touched-prod)).
OVN_TOGUARD_TAG=""
ovn_testonly_guard() {
  local before="$1" tl="${2:-}" id="${3:-testonly-guard}" mode="${OVN_TESTONLY_GUARD:-shadow}" item text tgt files
  OVN_TOGUARD_TAG=""; OVN_FXI_STATUS=""; OVN_FXI_TEXT=""
  [ "$mode" = off ] && return 0
  item="$(ovn_fixup_item_line "$before" "$tl")"
  [ -n "$item" ] || return 0
  text="${item#*:}"; tgt="$(ovn_fixup_item_target "$text")"
  files="$(ovn_testonly_prod_touch "$before" HEAD "$text" "$tgt")" || return 0
  OVN_FXI_TEXT="a test item changed production file(s): ${files:0:200}"
  _ovn_fxi_log "$tl" "[prod-touch] (mode=${mode}) ${OVN_FXI_TEXT}"
  _ovn_fxi_alert warn "$id" "[prod-touch] ${OVN_FXI_TEXT} (mode=${mode})"
  if [ "$mode" = enforce ]; then
    _ovn_fxi_log "$tl" "fixup-integrity: ${OVN_FXI_TEXT}; a test item may only change tests"
    _ovn_fxi_reset "$before"; OVN_FXI_STATUS="reverted(test-item-touched-prod)"; return 1
  fi
  OVN_TOGUARD_TAG="[prod-touch]"
  return 0
}

# =====================================================================================================================================================
# AIDER ATTEMPT VERDICTS (2026-10-09, harness-credit-integrity item 10)
# The implement loop treated every aider invocation alike: a commit => stop (even a PARTIAL one), no commit => 'maybe scan for more files, else stop'. Real xlite shapes:
#   - enemy_scaling.gd / enemy_faction_map.gd: 'UnifiedDiffNoMatch: hunk failed to apply!' AFTER earlier hunks applied => aider commits the half-applied edit
#     ('Commit c1d004f ...', here even an empty file at a mistyped path) and the cycle then lands/gets reverted on a mutilated change;
#   - dot_damage.gd / tech_tree.gd: the model wrote the diff INLINE (no fenced ```diff block: aider rendered '--- p +++ p @@ ...' as one markdown paragraph with '+' lines turned
#     into bullets), nothing applied, the loop gave up with 'no commit';
#   - platform.gd: a fenced diff whose hunk was blank-only / had no context lines: nothing applied.
# ovn_aider_attempt_verdict <log-slice-file> prints ONE of (the slice = this aider invocation's output only):
#   applied            'Applied edit to ...' (and/or a 'Commit <sha>' line) and no NoMatch AFTER the last applied edit (a NoMatch that aider recovered from is still 'applied')
#   nomatch-partial    a NoMatch error is the LAST edit event and something was applied/committed before it (half-applied edit)
#   no-edit-unfenced   nothing applied, no NoMatch, but the reply carries diff-looking text that aider could not use: headers collapsed onto one line (inline diff), a stray
#                      '@@' with no code block, or a diff block whose hunk is blank-only / has no context lines
#   no-edit            anything else (prose only, 'no changes needed', or a NoMatch with nothing applied: the existing flow handles those)
# Aider's own strings: 'Applied edit to', 'UnifiedDiffNoMatch' / 'hunk failed to apply' / 'does not contain lines that match' / 'does not contain these N exact lines',
# 'did not match' (only counted next to aider's 'did not conform to the edit format' frame), the '```diff' fence, '^Commit <sha>'.
# Runner policy (run_overnight.sh implement loop, OVN_UDIFF_RETRY=off disables): nomatch-partial => git reset --hard to the pre-attempt sha and retry ONCE;
# no-edit-unfenced => retry ONCE in the same cycle with ovn_udiff_nudge_text appended to the prompt instead of breaking the loop.
# =====================================================================================================================================================
ovn_aider_attempt_verdict() {
  local f="${1:-}"
  [ -f "$f" ] || { echo "no-edit"; return 0; }
  python3 - "$f" <<'PYEOF' 2>/dev/null || echo "no-edit"
import re, sys
t = open(sys.argv[1], errors="replace").read()
lines = t.split("\n")
NOM = re.compile(r"UnifiedDiffNoMatch|hunk failed to apply|does not contain lines that match|does not contain these \d+ exact lines")
APP = re.compile(r"^Applied edit to ")
COM = re.compile(r"^Commit [0-9a-f]{6,}")
conform = "did not conform to the edit format" in t
pn = pa = -1
first_app = None
has_commit = False
for i, ln in enumerate(lines):
    if NOM.search(ln) or (conform and re.search(r"\bdid not match\b", ln)):
        pn = i
    if APP.match(ln):
        pa = i
        if first_app is None:
            first_app = i
    if COM.match(ln):
        has_commit = True
if pn >= 0:
    if pa > pn:
        print("applied")
    elif has_commit or (first_app is not None and first_app < pn):
        print("nomatch-partial")
    else:
        print("no-edit")
    sys.exit(0)
if pa >= 0 or has_commit:
    print("applied")
    sys.exit(0)
# nothing applied, no NoMatch: is there diff-looking text aider could not use?
fence = re.search(r"^```diff[ \t]*$", t, re.M)
own = re.search(r"^--- \S+[ \t]*\n\+\+\+ \S+[ \t]*\n@@ ", t, re.M)
inline = re.search(r"^--- \S+ \+\+\+ \S+", t, re.M)
stray = re.search(r"^@@ ", t, re.M)
body = None
if fence:
    m = re.search(r"^```diff[ \t]*\n(.*?)(^```|\Z)", t, re.M | re.S)
    body = m.group(1) if m else ""
elif own:
    m = re.search(r"^--- \S+[ \t]*\n\+\+\+ \S+[ \t]*\n(.*?)(\n[ \t]*\n[ \t]*\n|^Tokens:|\Z)", t[own.start():], re.M | re.S)
    body = m.group(1) if m else ""
if body is not None:
    real = [l for l in body.split("\n") if re.match(r"^[+-](?!--|\+\+)", l) and l[1:].strip()]
    ctx = [l for l in body.split("\n") if l.startswith(" ") and l.strip()]
    if not real or not ctx:
        print("no-edit-unfenced")   # blank-only hunk / zero-context hunk that did not apply
    else:
        print("no-edit")
elif inline or stray:
    print("no-edit-unfenced")
else:
    print("no-edit")
PYEOF
}

# ovn_udiff_retry_decision <verdict> <already_retried_nomatch 0|1> <already_retried_unfenced 0|1> <tree_moved 0|1>: prints reset-retry | nudge-retry | none.
#   nomatch-partial  + not yet retried + the attempt left something behind (commit or dirty tree) => reset-retry   (OVN_UDIFF_RETRY=off => none, checked by the caller)
#   no-edit-unfenced + not yet retried + the attempt changed nothing                              => nudge-retry
# Each shape is retried at most once per cycle.
ovn_udiff_retry_decision() {
  local verdict="${1:-}" nm="${2:-0}" unf="${3:-0}" moved="${4:-0}"
  [ "${OVN_UDIFF_RETRY:-on}" = off ] && { echo none; return 0; }
  if [ "$verdict" = nomatch-partial ] && [ "$nm" = 0 ] && [ "$moved" = 1 ]; then echo reset-retry; return 0; fi
  if [ "$verdict" = no-edit-unfenced ] && [ "$unf" = 0 ] && [ "$moved" = 0 ]; then echo nudge-retry; return 0; fi
  echo none
}

# the one-time nudge appended to the prompt for a no-edit-unfenced retry
ovn_udiff_nudge_text() {
  printf '%s' 'Your reply had no fenced ```diff block or used a zero-context hunk. Resend the change as a fenced ```diff block with at least 3 lines of unchanged context and the exact enclosing `func`/`def` line.'
}

# =====================================================================================================================================================
# IDLE BEHAVIOUR (2026-10-09, harness-credit-integrity item 11)
# When every lane has nothing doable the pass ends in seconds, systemd restarts the unit at once and the cycle repeats: restart spam, a skip(exhausted) outcomes row per
# lane per pass (hundreds of identical rows), and no one asks the supply to produce more work.
#   (a) ovn_idle_wait <state_dir> [sleep_s] [step_s]: sleep OVN_IDLE_SLEEP_S (default 60) in OVN_IDLE_STEP_S (default 5) second steps, waking early when state/supply_kick exists
#       (deleted on wake). Prints 'kick' or 'timeout'. The runner calls it only after an all-exhausted pass, AFTER releasing run.lock; the unit restarts as before.
#   (b) ovn_skip_row_should_write <repo> <state_dir>: record_outcome writes at most ONE skip(exhausted) row per repo per hour. rc 0 = write (and the hour starts now),
#       rc 1 = suppress. The first skip after any non-skip row is written (ovn_skip_row_reset clears the hour); OVN_SKIP_ROW_DEDUPE=off writes every row.
#   (c) ovn_exhausted_supply_kick <repo> <state_dir> <ovn_dir>: on the FIRST exhausted pass per repo (state/exhausted_since_<repo> absent) start
#       `python3 scripts/ovn_work_supply.py <repo> --on-exhausted >> logs/work_supply.log` in the background (the supply script owns its own 5-minute lock and rate limit;
#       run.lock's fd 200 is closed for the child so it can never hold the runner's lock). ovn_exhausted_clear removes the marker when the repo has work again.
#       OVN_EXHAUSTED_SUPPLY=off disables the launch (the marker is still maintained); default 'auto' launches only when the deployed ovn_work_supply.py contains
#       '--on-exhausted' (i.e. supply-v2 is deployed and owns the lock); 'on' forces the launch.
# =====================================================================================================================================================
ovn_idle_wait() {
  local sd="${1:-state}" total="${2:-${OVN_IDLE_SLEEP_S:-60}}" step="${3:-${OVN_IDLE_STEP_S:-5}}" waited=0
  case "$total" in ''|*[!0-9]*) total=60 ;; esac
  case "$step" in ''|*[!0-9]*|0) step=5 ;; esac
  while [ "$waited" -lt "$total" ]; do
    if [ -e "$sd/supply_kick" ]; then rm -f "$sd/supply_kick"; echo kick; return 0; fi
    sleep "$step"; waited=$((waited + step))
  done
  if [ -e "$sd/supply_kick" ]; then rm -f "$sd/supply_kick"; echo kick; return 0; fi
  echo timeout
  return 0
}

ovn_skip_row_should_write() {
  local repo="${1:-none}" sd="${2:-state}" f now last
  [ "${OVN_SKIP_ROW_DEDUPE:-on}" = off ] && return 0
  f="$sd/skip_row_ts_${repo}"; now="$(date +%s)"
  last="$(cat "$f" 2>/dev/null)"; case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -ge 3600 ]; then printf '%s' "$now" > "$f" 2>/dev/null; return 0; fi
  return 1
}
ovn_skip_row_reset() { rm -f "${2:-state}/skip_row_ts_${1:-none}" 2>/dev/null; return 0; }

ovn_exhausted_supply_kick() {
  local repo="${1:-}" sd="${2:-state}" od="${3:-.}"
  [ -n "$repo" ] || return 0
  [ -e "$sd/exhausted_since_${repo}" ] && return 0       # not the first exhausted pass for this repo
  mkdir -p "$sd" 2>/dev/null; date +%s > "$sd/exhausted_since_${repo}" 2>/dev/null
  [ "${OVN_EXHAUSTED_SUPPLY:-auto}" = off ] && return 0
  [ -f "$od/scripts/ovn_work_supply.py" ] || return 0
  # auto (default): launch only when the deployed supply script actually implements --on-exhausted (it then owns its 5-minute lock + rate limit). A supply script that
  # ignores the flag would run a normal pass that can overlap the :07/:37 cron run and rewrite backlog/state files non-atomically. OVN_EXHAUSTED_SUPPLY=on forces.
  if [ "${OVN_EXHAUSTED_SUPPLY:-auto}" != on ] && ! grep -qF -- '--on-exhausted' "$od/scripts/ovn_work_supply.py" 2>/dev/null; then return 0; fi
  mkdir -p "$od/logs" 2>/dev/null
  ( python3 "$od/scripts/ovn_work_supply.py" "$repo" --on-exhausted >> "$od/logs/work_supply.log" 2>&1 < /dev/null 200>&- & ) 2>/dev/null
  return 0
}
ovn_exhausted_clear() { rm -f "${2:-state}/exhausted_since_${1:-none}" 2>/dev/null; return 0; }

# =====================================================================================================================================================
# DETERMINISTIC EXECUTOR HOOKS (2026-10-09, harness-credit-integrity item 12) - contract only; the executors themselves are built elsewhere
# (scripts/ovn_doc_executor.py by package supply-v2, scripts/ovn_ruff_fix_executor.py by xlite-godot-lane). Beside the DELETE-EXECUTOR block run_overnight.sh calls
#   ovn_executor_hook <doc|ruff> <ovn_dir> <repo_dir> <item line> <branch> <task_log> <before_sha>
# for the ongoing-* lanes. Contract of an executor script X (X = scripts/ovn_doc_executor.py | scripts/ovn_ruff_fix_executor.py):
#   python3 X check <repo_dir> "<item line>"   prints  OK<TAB><files>  |  SKIP<TAB><why>
#   python3 X apply <repo_dir> "<item line>"   edits the WORKING TREE ONLY (no commit); prints  APPLIED<TAB><files><TAB><summary>  |  FAIL<TAB><why>; leaves the tree clean on FAIL
# The hook: git add the declared files, commit 'chore(supply): <kind> via deterministic executor', run_repo_verification, run the item's OWN VERIFY via shadow_check
# (it must PASS), credit the item like DELETE-EXECUTOR, push with the same rebase-retry and print 'pushed(tests:pass) <kind>-executor' (rc 0). ANY failure resets to
# BEFORE_SHA, remembers the item in <ovn_dir>/state/exec_failed/<hash> (a verification that could not run ('skip') is not remembered) and returns rc 1 = fall through to
# the normal model path. A commit that stages anything beyond the declared files is a failure too.
# Mode: OVN_DOC_EXECUTOR / OVN_RUFF_EXECUTOR = off | shadow | on, default SHADOW (run `check` only and log 'would apply: <files>'; never edits anything).
# A missing executor script is skipped silently. Needs run_repo_verification (runner) and shadow_check (lib_verify_clause.sh); without them the hook does nothing.
# =====================================================================================================================================================
ovn_executor_hook() {
  local kind="${1:-}" od="${2:-}" rd="${3:-.}" item="${4:-}" branch="${5:-}" tl="${6:-/dev/null}" before="${7:-}"
  local script modevar mode hash failed out act files summary v ln staged f extra okc PROG SHADOW_LOG _REPO_LABEL
  case "$kind" in
    doc)  script="$od/scripts/ovn_doc_executor.py";      modevar=OVN_DOC_EXECUTOR ;;
    ruff) script="$od/scripts/ovn_ruff_fix_executor.py"; modevar=OVN_RUFF_EXECUTOR ;;
    *) return 1 ;;
  esac
  mode="${!modevar:-shadow}"
  case "$mode" in off|shadow|on) ;; *) mode=shadow ;; esac
  [ "$mode" = off ] && return 1
  [ -f "$script" ] || return 1                               # absent executor: silent
  [ -n "$item" ] && [ -n "$before" ] || return 1
  hash="$(ovn_item_hash "$item" 2>/dev/null)"; [ -n "$hash" ] || return 1
  failed="$od/state/exec_failed/$hash"
  [ -e "$failed" ] && return 1                               # tried (and failed) once already
  out="$(cd "$rd" && timeout 60 python3 "$script" check "$rd" "$item" 2>>"$tl")"
  case "$out" in
    OK*) files="$(printf '%s' "$out" | cut -f2)" ;;
    *) [ -n "$out" ] && echo "--- ${kind}-executor: ${out#SKIP	} ---" >> "$tl"; return 1 ;;
  esac
  if [ "$mode" = shadow ]; then
    echo "--- ${kind^^}-EXECUTOR (shadow): would apply: ${files} ---" >> "$tl"
    return 1
  fi
  declare -F run_repo_verification >/dev/null 2>&1 && declare -F shadow_check >/dev/null 2>&1 || return 1
  _ex_fail() {  # reset to BEFORE_SHA, remember (unless the verification itself could not run), log why
    echo "--- ${kind^^}-EXECUTOR: $1 - reset, normal path continues ---" >> "$tl"
    git -C "$rd" reset -q --hard "$before" >>"$tl" 2>&1; git -C "$rd" clean -fdq >>"$tl" 2>&1
    if [ "${2:-remember}" = remember ]; then mkdir -p "$od/state/exec_failed" 2>/dev/null; : > "$failed"; fi
    return 1
  }
  act="$(cd "$rd" && timeout 300 python3 "$script" apply "$rd" "$item" 2>>"$tl")"
  case "$act" in
    APPLIED*) files="$(printf '%s' "$act" | cut -f2)"; summary="$(printf '%s' "$act" | cut -f3)" ;;
    *) _ex_fail "apply failed (${act#FAIL	})"; return 1 ;;
  esac
  [ -n "$files" ] || { _ex_fail "apply declared no files"; return 1; }
  # shellcheck disable=SC2086
  git -C "$rd" add -- $files >>"$tl" 2>&1
  staged="$(git -C "$rd" diff --cached --name-only 2>/dev/null)"
  [ -n "$staged" ] || { _ex_fail "apply changed nothing"; return 1; }
  extra=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " $files " in *" $f "*) ;; *) extra="$extra $f" ;; esac
  done <<< "$staged"
  [ -z "$extra" ] || { _ex_fail "staged files beyond the declared set:${extra}"; return 1; }
  # the working tree must hold nothing the executor did not declare (it would be swept into later commits or silently lost)
  [ -z "$(git -C "$rd" status --porcelain --untracked-files=no 2>/dev/null | grep -v '^A  \|^M  \|^D  \|^R  ')" ] || { _ex_fail "working tree has changes beyond the declared files"; return 1; }
  git -C "$rd" commit -q -m "chore(supply): ${kind} via deterministic executor" -m "${summary}" >>"$tl" 2>&1 || { _ex_fail "commit failed"; return 1; }
  v="$(cd "$rd" && run_repo_verification)"
  if [ "$v" != pass ]; then
    if [ "$v" = skip ]; then _ex_fail "verification=${v} (could not run; not remembered)" noremember; else _ex_fail "verification=${v} (not pass)"; fi
    return 1
  fi
  # the item's OWN VERIFY must pass (PASS only: an item that cannot be proven done is left to the normal path)
  PROG="$(mktemp 2>/dev/null)" || { _ex_fail "no temp file for the VERIFY check"; return 1; }
  printf '%s\n' "$item" > "$PROG"
  SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$od/state/verify_gate_shadow.log}"; mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
  _REPO_LABEL="$(basename "$rd")"
  ( cd "$rd" && shadow_check 1; echo "$_LAST_VERIFY_RESULT" > "$PROG.res" )
  okc="$(cat "$PROG.res" 2>/dev/null)"; rm -f "$PROG" "$PROG.res"
  [ "$okc" = PASS ] || { _ex_fail "the item's own VERIFY did not pass (${okc:-no verdict})"; return 1; }
  ln="$(grep -nF -- "$item" "$rd/OVERNIGHT_PROGRESS.md" 2>/dev/null | head -1 | cut -d: -f1)"
  if [ -n "$ln" ]; then
    _ovn_sed_i "${ln}s/^- \[ \] /- [x] (${kind} via deterministic executor, verified) /" "$rd/OVERNIGHT_PROGRESS.md"
    git -C "$rd" add OVERNIGHT_PROGRESS.md
    git -C "$rd" commit -q -m "chore(queue): credit deterministic ${kind} change (${files})" -- OVERNIGHT_PROGRESS.md >>"$tl" 2>&1
  fi
  if timeout 30 git -C "$rd" push origin "$branch" --quiet 2>>"$tl" || { timeout 30 git -C "$rd" pull --rebase origin "$branch" >>"$tl" 2>&1 && timeout 30 git -C "$rd" push origin "$branch" --quiet 2>>"$tl"; }; then
    echo "--- ${kind^^}-EXECUTOR: verified green and pushed ---" >> "$tl"
    echo "pushed(tests:pass) ${kind}-executor"
    return 0
  fi
  git -C "$rd" rebase --abort >/dev/null 2>&1 || true
  _ex_fail "push failed after rebase-retry"
  return 1
}
