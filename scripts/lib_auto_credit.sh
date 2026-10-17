#!/usr/bin/env bash
# scripts/lib_auto_credit.sh - the runner's per-file AUTO-CREDIT, rebuilt 2026-10-02 (QA harness-X, X1).
#
# WHY: the old inline block in run_overnight.sh ticked the FIRST unchecked item whose text merely CONTAINED a file name the green commit
# touched (`grep -F "$file"`) and never ran the item's VERIFY: clause. Live false credits 2026-10-02: test-automation-agent T1/T2 "stop the
# sync Anthropic client" ticked [x] by unrelated commits (their VERIFY greps still return 0 matches); billwatch ticked an `articles.py` item
# because article_relevance.py changed (and the cycle had committed a placeholder routers/articles.py). Worse, the chore commit that did the
# ticking used a bare `git commit` and swept a half-restored index into history (the 13:14 CDT billwatch incident: verified source reverted).
#
# RULES (every one is a refusal, logged with its reason to the task log):
#   1. the working tree + index must equal the cycle's AFTER_SHA before AND after anything runs (else refuse, hard-reset only if WE dirtied it, alert)
#   2. credit only when the touched path EQUALS the item's own leading path (normalised against the tracked files via lib_path_normalize)
#   3. the touched file must carry a real diff (not a 0/0 empty add) and must not be a placeholder stub
#   4. the item must have a VERIFY: clause that is safe to run (shared runner, lib_verify_clause.sh) and that PASSES - no clause = no credit
#   5. the tick commit stages and commits ONLY the progress file (pathspec commit; the staged set is asserted)
#
# usage (cwd = repo root):  ovn_auto_credit <before_sha> <after_sha> <progress_file> <task_log>
#   rc 0 = ran (OVN_AC_CREDITED = number of ticked items; may be 0)   rc 1 = refused because the tree did not match AFTER (flagged)
#   OVN_AC_NEWHEAD = HEAD after the call (changes only when a tick commit was made)
#   OVN_AC_INDETERMINATE = number of items whose VERIFY timed out / was not runnable (NOT credited, NOT a failed attempt: see below)
#
# INDETERMINATE VERIFY (harness-X X-a): the credit gate used shadow_check's fixed 60s cap; live VERIFYs are slow (Chickadee `./gradlew testDebugUnitTest`,
# xcodebuild, full pytest, vitest), so a correctly landed item could never be credited, got re-faced and burned the item guard's attempt counter.
# Now the auto-credit caller uses OVN_AC_VERIFY_TIMEOUT (default 300s) and OVN_AC_VERIFY_TIMEOUT_HEAVY (default 900s, for gradlew/xcodebuild/mvn/
# npm run build/npm test/vitest/full pytest), bounded overall by OVN_AC_VERIFY_BUDGET (default 2400s per call). A timeout (rc=124) or unrunnable
# clause is neither credited nor FAILED: the item stays open, one alert per call (deduped) says why, and an `indet-hash <md5>` marker goes into the task
# log so ovn_item_guard.sh treats the green landing as a landing (clears the item's counters) and does not bill the item's next ALREADY-DONE no-ops.
_AC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_path_normalize.sh
[ -f "$_AC_DIR/lib_path_normalize.sh" ] && . "$_AC_DIR/lib_path_normalize.sh"
declare -F ovn_normalize_path >/dev/null 2>&1 || ovn_normalize_path(){ printf '%s\n' "$2"; }
# shellcheck source=lib_verify_clause.sh
[ -f "$_AC_DIR/lib_verify_clause.sh" ] && . "$_AC_DIR/lib_verify_clause.sh"

OVN_AC_PLACEHOLDER_TEXT="Placeholder - the implement step fills this in"

# GENERATED-ARTEFACT ALLOWLIST (harness-X X-c). Tracked files a build/test/engine run rewrites by itself. A tracked path that differs from AFTER
# is IGNORED (logged, never committed: every credit/bookkeeping commit is a pathspec commit) only when BOTH hold:
#   (1) its path matches one of these globs (`*` matches across `/`), and
#   (2) the cycle's own diff (BEFORE..AFTER) did NOT touch it.
# (2) is deliberate and stricter than "refuse only untouched files": the 13:14 CDT incident was a half-reverted SOURCE file that the cycle's diff DID
# touch (red-green restore failed), so a differing path inside the cycle's diff is never benign, whatever its name.
# Assumptions (no live "git status --porcelain after a normal cycle" is available, so reasoned from the toolchains the lanes run):
#   Godot (xlite)    headless runs rewrite project.godot / *.import / *.uid / .godot/** (memory: feedback_godot-regenerates-project-file)
#   Gradle (Android) rewrites local.properties, .gradle/**, */build/** (normally untracked; listed in case a repo tracked them)
#   Xcode            *.xcuserstate, xcuserdata/**, *.xcworkspace/xcshareddata/swiftpm/Package.resolved is NOT listed (a real dependency change)
#   Python/JS        __pycache__/*.pyc, .coverage, coverage.xml, *.tsbuildinfo, .DS_Store, *.log
# NOT assumed benign: lockfiles (package-lock.json, poetry.lock), mode-only changes, anything under src/tests/app code.
# OVN_TREE_BENIGN_GLOBS (space separated) replaces the list; OVN_TREE_BENIGN=off disables the allowlist (every tracked difference refuses).
OVN_TREE_BENIGN_DEFAULT="*__pycache__/* *.pyc .coverage */.coverage coverage.xml */coverage.xml *.tsbuildinfo .DS_Store */.DS_Store *.log project.godot */project.godot *.import *.uid .godot/* */.godot/* local.properties */local.properties .gradle/* */.gradle/* */build/* *.xcuserstate xcuserdata/* */xcuserdata/*"

_ovn_tree_is_benign_path() {
  local p="$1" g _had_noglob=0 _rc=1
  [ "${OVN_TREE_BENIGN:-on}" = "off" ] && return 1
  # 2026-10-02 (follow-up 3): the unquoted glob list was pathname-expanded against the repo root (cwd): '*.log' became the literal a.log b.log, etc.
  # Turn globbing off while splitting so the patterns reach `case` untouched, then restore the caller's setting.
  case "$-" in *f*) _had_noglob=1 ;; esac
  set -f
  for g in ${OVN_TREE_BENIGN_GLOBS:-$OVN_TREE_BENIGN_DEFAULT}; do
    case "$p" in $g) _rc=0; break ;; esac
  done
  [ "$_had_noglob" = 1 ] || set +f
  return "$_rc"
}

# portable in-place sed (GNU on the box, BSD on the Mac where the tests run): GNU sed accepts `-i` alone, BSD sed needs `-i ''`
_ovn_sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
# _ovn_in_lines <newline-separated list> <needle>: 0 when needle is exactly one line of the list (no pipe, no process; safe under pipefail at any size)
_ovn_in_lines() { case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; esac; return 1; }

# ovn_tree_matches_sha <sha> [except_path] [before_sha]: 0 when HEAD == sha and no TRACKED path differs from it in the index or worktree, except
# generated artefacts (see the allowlist above; needs before_sha to know what the cycle touched - without it NOTHING is treated as benign).
# except_path, when given, is ignored: the runner's own progress bookkeeping legitimately edits OVERNIGHT_PROGRESS.md before it commits it.
# On refusal prints the offending paths on stdout: the first 5, then "(+N more)". OVN_TREE_IGNORED holds the benign paths that were ignored
# (space separated, may be non-empty on success); OVN_TREE_ALL_BAD holds EVERY offending path, one per line, untruncated (package verify-credit-runner: the lockfile settle below
# needs the full list, OVN_TREE_OUT only the first 5); OVN_TREE_OUT holds the same text as stdout (use it when calling without a subshell). Untracked files are ignored (aider/pytest droppings).
ovn_tree_matches_sha() {
  local sha="$1" except="${2:-}" before="${3:-}" all p n=0 bad="" total=0 touched=""
  local spec=(-- .); [ -n "$except" ] && spec=(-- . ":(exclude)$except")
  OVN_TREE_IGNORED=""; OVN_TREE_OUT=""; OVN_TREE_ALL_BAD=""
  if [ "$(git rev-parse HEAD 2>/dev/null)" != "$sha" ]; then OVN_TREE_OUT="HEAD is not ${sha:0:12}"; echo "$OVN_TREE_OUT"; return 1; fi
  all="$( { git diff --name-only "$sha" "${spec[@]}" 2>/dev/null; git diff --cached --name-only "$sha" "${spec[@]}" 2>/dev/null; } | sort -u)"
  [ -n "$all" ] || return 0
  [ -n "$before" ] && touched="$(git diff --name-only "$before" "$sha" -- . 2>/dev/null)"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # pure-bash exact-line membership (2026-10-09: `printf | grep -q` under pipefail is SIGPIPE-flaky once the list is > the 64KB pipe buffer)
    if [ -n "$before" ] && _ovn_tree_is_benign_path "$p" && ! _ovn_in_lines "$touched" "$p"; then
      OVN_TREE_IGNORED="$OVN_TREE_IGNORED $p"; continue
    fi
    total=$((total + 1)); OVN_TREE_ALL_BAD="${OVN_TREE_ALL_BAD}${p}"$'\n'
    if [ "$n" -lt 5 ]; then bad="$bad $p"; n=$((n + 1)); fi
  done <<< "$all"
  OVN_TREE_IGNORED="${OVN_TREE_IGNORED# }"
  if [ "$total" -gt 0 ]; then
    bad="${bad# }"; [ "$total" -gt 5 ] && bad="$bad (+$((total - 5)) more)"
    OVN_TREE_OUT="$bad"; echo "$bad"; return 1
  fi
  return 0
}

# real inserted/deleted lines between before..after for one file (binary counts as real; a 0/0 add/rename/mode change does not)
ovn_ac_has_real_diff() {
  local before="$1" after="$2" f="$3" stat add del
  stat="$(git diff --numstat "$before" "$after" -- "$f" 2>/dev/null)"
  [ -z "$stat" ] && return 1
  add="$(printf '%s' "$stat" | awk '{print $1}')"; del="$(printf '%s' "$stat" | awk '{print $2}')"
  if [ "$add" = "-" ] || [ "$del" = "-" ]; then return 0; fi
  [ "${add:-0}" -gt 0 ] || [ "${del:-0}" -gt 0 ]
}

# true when the file AT <after> is only the harness placeholder stub
ovn_ac_is_placeholder() {
  local _head; _head="$(git show "$1:$2" 2>/dev/null | head -c 4000)"   # capture first: `| grep -q` under pipefail is flaky (SIGPIPE on the writer)
  case "$_head" in *"$OVN_AC_PLACEHOLDER_TEXT"*) return 0 ;; esac
  return 1
}

# CREDIT-REFUSAL COUNTER (2026-10-09, harness-credit-integrity item 6). A refusal that happens AFTER the path matched (placeholder stub / no VERIFY clause / VERIFY not
# safe to run / VERIFY FAILED) means "the commit touched THIS item's own file but cannot be credited" - the cycle still pushes, the item stays [ ] and is re-faced
# (iptv: 29 'refusals' + 7 churn landings on one file in 24h). Each such refusal bumps state/credit_refused/<repo>.<item hash> = "<count>\n<reason>\n<item line>";
# ovn_item_guard.sh parks the item at OVN_REFUSED_PARK_AT (default 2, 0 = off) with '[AUTO-SKIP after N credit refusals: <reason>]'; a successful credit deletes
# the file. Path-mismatch refusals are deliberately NOT counted: they fire for every open item that merely shares a basename with a touched file, so counting
# them would park innocent items. The hash is ovn_item_hash (the same identity the item guard and queue_refill use); no helper => md5 of the text.
_ovn_cr_dir() { printf '%s' "${OVN_STATE_DIR:-${STATE_DIR:-$HOME/overnight-queue/state}}/credit_refused"; }
_ovn_cr_hash() {
  if declare -F ovn_item_hash >/dev/null 2>&1; then ovn_item_hash "$1"; else printf '%s' "$1" | sed -E 's/^- \[[ xX]\] //' | md5sum | cut -d' ' -f1; fi
}
# PER-REPO keying (harness-credit-integrity round-3 fix): state/credit_refused is shared by every repo, so the counter file is "<repo>.<item hash>" and ovn_item_guard.sh
# only ever reads/parks/deletes the counters of ITS OWN repo (before: a guard call for repo A deleted an at-threshold counter of repo B because B's item line is not in A's
# progress file, so B's park was silently lost). <repo> = basename of the repo dir with every char outside [A-Za-z0-9_-] replaced by '_' (never contains a dot).
_ovn_cr_repo() {  # <repo dir or progress file path> -> sanitised repo name
  local p="${1:-}"
  [ -f "$p" ] && p="$(cd "$(dirname "$p")" 2>/dev/null && pwd)"   # absolute: the progress file may be passed relative ("OVERNIGHT_PROGRESS.md" => dirname ".")
  [ -n "$p" ] || p="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  basename "$p" | sed 's/[^A-Za-z0-9_-]/_/g'
}
ovn_credit_refused_note() {  # <progress line text> <reason> [<repo dir>]
  local text="${1:-}" reason="${2:-credit refused}" d h f n
  [ "${OVN_REFUSED_PARK_AT:-2}" = 0 ] && return 0
  [ -n "$text" ] || return 0
  d="$(_ovn_cr_dir)"; mkdir -p "$d" 2>/dev/null || return 0
  h="$(_ovn_cr_hash "$text")"; [ -n "$h" ] || return 0
  f="$d/$(_ovn_cr_repo "${3:-}").$h"
  n="$(sed -n 1p "$f" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n%s\n%s\n' "$((n + 1))" "$reason" "$text" > "$f" 2>/dev/null
  return 0
}
ovn_credit_refused_clear() {  # <progress line text> [<repo dir>]
  local h; h="$(_ovn_cr_hash "${1:-}")"
  [ -n "$h" ] && rm -f "$(_ovn_cr_dir)/$(_ovn_cr_repo "${2:-}").$h" 2>/dev/null
  return 0
}
# Count a refusal ONLY for the item this cycle actually worked (harness-credit-integrity fix): ovn_auto_credit walks EVERY open item that names a touched file, so a
# sibling item on the same file that the cycle never worked (its VERIFY still red / absent) used to collect the same refusals and was parked after 2 cycles.
# The worked item is what the rest of the harness bills (ovn_resolve_top_item: the scout's named file, else top of file - the same resolver record_outcome and
# ovn_item_guard.sh use), compared by ovn_item_hash. It is resolved once per call (_AC_WORKED_H); unresolvable => nothing is counted (never park an innocent).
# OVN_REFUSED_WORKED_ONLY=off restores "count every refused open item".
_ovn_cr_worked_hash() {  # <prog> <task_log> -> hash of the item this cycle worked, or empty
  local prog="$1" tl="${2:-}" top
  [ "$(basename "$prog")" = OVERNIGHT_PROGRESS.md ] || return 0
  declare -F ovn_resolve_top_item >/dev/null 2>&1 || return 0
  top="$(ovn_resolve_top_item "$(dirname "$prog")" "$tl" 2>/dev/null)"
  [ -n "$top" ] || return 0
  _ovn_cr_hash "${top#*:}"
}
_ovn_cr_bump() {  # <prog> <line no> <reason>
  local prog="$1" ln="$2" reason="$3" text
  text="$(sed -n "${ln}p" "$prog")"
  if [ "${OVN_REFUSED_WORKED_ONLY:-on}" != off ]; then
    [ -n "${_AC_WORKED_H:-}" ] && [ "$(_ovn_cr_hash "$text")" = "$_AC_WORKED_H" ] && { ovn_credit_refused_note "$text" "$reason" "$prog"; return 0; }
    _ovn_ac_log "refusal of line ${ln} not counted toward a park: this cycle did not work that item"
    return 0
  fi
  ovn_credit_refused_note "$text" "$reason" "$prog"
}

# ovn_credit_twins <progress file> <line of the item just credited by a VERIFIED path> [task_log]   (2026-10-12, package uidcredit)
# Credit the IDENTICAL open twins of that item too. Identity = ovn_credit_items.py canon_item (same text once the checkbox, annotations, state tags, tier tag and the feat date
# are dropped; the VERIFY clause is part of the text), NEVER the feat tag / item hash alone: all siblings of one feature share a hash and are different work. A twin used to stay
# open and be served again next cycle (one extra ALREADY-DONE / credit-refused cycle per copy). OVN_TWIN_CREDIT=off|shadow|on, default ON (a twin has the identical text incl. its VERIFY clause, and the
# credit paths that call this already verified that text); `shadow` only logs 'would credit identical twin', `off` = the old one-tick behaviour.
# Sets OVN_TWIN_N (twins found / ticked), always rc 0.
OVN_TWIN_N=0
ovn_credit_twins() {
  local prog="$1" ln="$2" tl="${3:-}" mode="${OVN_TWIN_CREDIT:-on}" out
  OVN_TWIN_N=0
  [ "$mode" = off ] && return 0
  out="$(timeout 20 python3 "$_AC_DIR/ovn_credit_items.py" tick-twins "$prog" "$ln" "$mode" 2>/dev/null)" || return 0
  case "$out" in
    "TICKED "[1-9]*) OVN_TWIN_N="${out#TICKED }"; [ -n "$tl" ] && echo "--- auto-credit: twin credit: also ticked ${OVN_TWIN_N} identical open copy(ies) of line ${ln} ---" >> "$tl" ;;
    "SHADOW "[1-9]*) OVN_TWIN_N="$(printf '%s' "$out" | awk '{print $2}')"; [ -n "$tl" ] && echo "--- auto-credit: twin credit SHADOW: would also tick ${OVN_TWIN_N} identical open copy(ies) of line ${ln} (lines: $(printf '%s' "$out" | cut -d' ' -f3-)); OVN_TWIN_CREDIT=on enables ---" >> "$tl" ;;
  esac
  return 0
}

_ovn_ac_log() { [ -n "${_AC_TASK_LOG:-}" ] && echo "--- auto-credit: $* ---" >> "$_AC_TASK_LOG"; return 0; }
_ovn_ac_alert() { if declare -F emit_alert >/dev/null 2>&1; then emit_alert warn "${id:-auto-credit}" "$1" 2>/dev/null; fi; return 0; }

# LOCKFILE / PROGRESS-FILE SETTLE (2026-10-13, package verify-credit-runner, night review N4 finding B). Three landed, green cycles were refused only because the tree changed AFTER the
# cycle's verify: a build/test step (npm install/ci inside the cycle's tests or an item VERIFY) rewrote billwatch-web/package-lock.json (billwatch 122817, iptv 042516), and in the
# post-VERIFY check OVERNIGHT_PROGRESS.md differed (gitlark 144311, code commit d2c2fdab was green). Neither is the half-restored SOURCE tree RULE 1 exists to catch (the 2026-10-02 13:14
# incident). A package-lock.json / yarn.lock / pnpm-lock.yaml delta is RESTORED to the cycle's AFTER commit (`git checkout <after> -- <file>`: index and worktree) and the check re-run; the
# progress file (post-VERIFY only) is kept as it is and the ticked lines are re-located BY TEXT before ticking (line numbers may have moved). ANY other differing path (source, tests, a
# lockfile mixed with source, a lockfile that cannot be restored) keeps the refusal untouched - nothing is restored in that case. OVN_AC_LOCKFILE_RESTORE=off restores the old refusal.
_ovn_ac_is_lockfile() { case "${1##*/}" in package-lock.json|yarn.lock|pnpm-lock.yaml) return 0 ;; esac; return 1; }
# _ovn_ac_settle_tree <after> <before> [progress_file]: call right after ovn_tree_matches_sha REFUSED (uses OVN_TREE_ALL_BAD). rc 0 = the tree now equals AFTER (modulo the progress file,
# when given: _AC_PROG_CHANGED=1 if it differs); rc 1 = refuse as before (nothing was touched unless a restore half-failed, which is also a refusal).
_AC_PROG_CHANGED=0
_ovn_ac_settle_tree() {
  local after="$1" before="$2" prog="${3:-}" all="${OVN_TREE_ALL_BAD:-}" p locks="" seen_prog=0
  _AC_PROG_CHANGED=0
  [ "${OVN_AC_LOCKFILE_RESTORE:-on}" = off ] && return 1
  [ -n "$all" ] || return 1
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ -n "$prog" ] && [ "$p" = "$prog" ]; then seen_prog=1; continue; fi
    _ovn_ac_is_lockfile "$p" || return 1
    locks="${locks}${p}"$'\n'
  done <<< "$all"
  [ -n "$locks" ] || [ "$seen_prog" = 1 ] || return 1
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    git checkout -q "$after" -- "$p" 2>/dev/null || return 1
    _ovn_ac_log "restored lockfile ${p} to ${after:0:12} (a build/test step rewrote it after the cycle's verify; lockfile-only delta, not a source change)"
  done <<< "$locks"
  # a differing progress file is KEPT and RULE 5 commits it whole, so it must look like bookkeeping: every line removed/changed versus AFTER has to be an item line (`- [ ]` / `- [x]`: a
  # tick, a park annotation); a changed heading/record line, or a file we cannot diff, refuses. The diffstat is logged so a swept-in concurrent edit is visible.
  if [ "$seen_prog" = 1 ]; then
    local _pd _pbad
    _pd="$(git diff -U0 "$after" -- "$prog" 2>/dev/null)" || return 1
    _pbad="$(printf '%s\n' "$_pd" | grep -a '^-' | grep -av '^---' | grep -avE '^-[[:space:]]*[-*] \[[ xX]\] ' | head -1)"
    if [ -n "$_pbad" ]; then _ovn_ac_log "progress file ${prog} differs from AFTER in a non-item line (${_pbad:0:120}); not bookkeeping, refusing"; return 1; fi
    _ovn_ac_log "progress file ${prog} diffstat vs AFTER: +$(printf '%s\n' "$_pd" | grep -a '^+' | grep -avc '^+++') -$(printf '%s\n' "$_pd" | grep -a '^-' | grep -avc '^---')"
  fi
  ovn_tree_matches_sha "$after" "$prog" "$before" >/dev/null || return 1
  [ "$seen_prog" = 1 ] && { _AC_PROG_CHANGED=1; _ovn_ac_log "progress file ${prog} changed since the cycle's verify (only differing path besides lockfiles); keeping it, re-locating ticked items by text"; }
  return 0
}

# S2 SHADOW ADVISORY (QA plan Phase 2, package P2-phase2-s0-card-pilot-wiring): after an item is auto-credited, log to state/qa_shadow/card_credit.jsonl whether an S0 acceptance card existed
# for it (credit_without_card) and whether the card's verify_cmd passes at the credited head. NO behaviour change: detached, niced, time-boxed, run.lock fd closed, always rc 0.
# OVN_QA_CARD_CREDIT=off|shadow (default shadow; there is no enforce path). OVN_QA_CARD_CREDIT_SYNC=1 runs it in the foreground (tests only).
ovn_card_credit_shadow() {  # <progress line of the credited item> <credited head sha>
  [ "${OVN_QA_CARD_CREDIT:-shadow}" = "off" ] && return 0
  [ -f "$_AC_DIR/../qa/card_pilot_run.py" ] || return 0
  local _cc_sd="${QA_STATE_DIR:-${OVN_STATE_DIR:-${STATE_DIR:-$HOME/overnight-queue/state}}}"
  [ -d "$_cc_sd" ] || return 0   # no state dir = nowhere to log (and never create one from a hook)
  if [ "${OVN_QA_CARD_CREDIT_SYNC:-}" = 1 ]; then
    ( export QA_STATE_DIR="$_cc_sd"; OVN_CC_ITEM="$1" timeout -k 30 180 python3 "$_AC_DIR/../qa/card_pilot_run.py" credit --repo "$(basename "$PWD")" --repo-path "$PWD" --head "$2" --no-stdout ) >/dev/null 2>&1 200>&- 201>&- 202>&- || true
    return 0
  fi
  ( export QA_STATE_DIR="$_cc_sd"; OVN_CC_ITEM="$1" nohup nice -n 15 timeout -k 30 180 python3 "$_AC_DIR/../qa/card_pilot_run.py" credit --repo "$(basename "$PWD")" --repo-path "$PWD" --head "$2" --no-stdout ) >/dev/null 2>&1 200>&- 201>&- 202>&- &
  return 0
}

ovn_auto_credit() {
  local before="$1" after="$2" prog="$3" _AC_TASK_LOG="${4:-}"
  OVN_AC_CREDITED=0; OVN_AC_NEWHEAD="$(git rev-parse HEAD 2>/dev/null)"
  [ -f "$prog" ] || return 0
  local _ac_pretext="" changed items bad n ln tgt cf norm res ticked_lines="" ticked_texts="" indet_lines="" indet_msgs="" _t0=$SECONDS _budget _AC_WORKED_H=""
  # visible to shadow_check through bash dynamic scope; every other caller of shadow_check keeps the 60s default
  local _VC_MEMO="" _VC_MEMO_ON=1   # identical VERIFY commands run once per call (lib_verify_clause.sh)
  local VERIFY_TIMEOUT_SECS="${OVN_AC_VERIFY_TIMEOUT:-300}" VERIFY_TIMEOUT_HEAVY_SECS="${OVN_AC_VERIFY_TIMEOUT_HEAVY:-900}"
  _budget="${OVN_AC_VERIFY_BUDGET:-2400}"; OVN_AC_INDETERMINATE=0

  changed="$(git diff --name-only "$before" "$after" -- . 2>/dev/null | grep -v '^$' | grep -vxF "$prog" || true)"
  [ -n "$changed" ] || return 0

  # RULE 1: the tree must equal AFTER before we do anything at all.
  if ! ovn_tree_matches_sha "$after" "" "$before" >/dev/null; then
    bad="$OVN_TREE_OUT"
    # lockfile-only delta (no source path): restore it to AFTER and carry on (OVN_AC_LOCKFILE_RESTORE=off = refuse as before)
    # the progress file may differ here too (gitlark 144311: something wrote it between the cycle's verify and the credit step): settled like the post-VERIFY case
    if ! _ovn_ac_settle_tree "$after" "$before" "$prog"; then
      _ovn_ac_log "REFUSED - working tree/index differ from AFTER ${after:0:12} (${bad}); nothing credited, nothing committed"
      _ovn_ac_alert "auto-credit refused: tree differs from the cycle's commit (${bad}) - a half-restored tree must never be committed"
      return 1
    fi
  fi

  [ -n "$OVN_TREE_IGNORED" ] && _ovn_ac_log "ignoring tracked generated-artefact difference(s) not touched by this cycle: ${OVN_TREE_IGNORED:0:300}"

  items="$(python3 "$_AC_DIR/ovn_credit_items.py" list "$prog" 2>/dev/null)"
  [ -n "$items" ] || return 0

  SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}"
  mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
  PROG="$prog"; _REPO_LABEL="$(basename "$PWD")"
  _AC_WORKED_H="$(_ovn_cr_worked_hash "$prog" "$_AC_TASK_LOG")"

  while IFS= read -r cf; do
    [ -z "$cf" ] && continue
    if ! ovn_ac_has_real_diff "$before" "$after" "$cf"; then
      _ovn_ac_log "SKIPPED ${cf} - it's in the diff but has a 0/0 (empty) change, not real work"
      continue
    fi
    while IFS=$'\t' read -r ln tgt; do
      [ -z "$ln" ] && continue
      # cheap prefilter before the (git ls-files based) normalisation: basenames must agree
      [ "$(basename "$tgt")" = "$(basename "$cf")" ] || continue
      norm="$(ovn_normalize_path "$PWD" "$tgt")"
      # RULE 2: exact path equality (no substring / "mentions the file" matching)
      [ "$norm" = "$cf" ] || { _ovn_ac_log "REFUSED line ${ln} - item names ${tgt} (=${norm}), the commit touched ${cf}: path mismatch"; continue; }
      # RULE 3: never credit a placeholder stub
      if ovn_ac_is_placeholder "$after" "$cf"; then
        _ovn_ac_log "REFUSED line ${ln} - ${cf} is only a placeholder stub ('${OVN_AC_PLACEHOLDER_TEXT}'), not real work"
        _ovn_cr_bump "$prog" "$ln" "placeholder stub"
        continue
      fi
      # RULE 4: the item's own VERIFY clause must pass
      _ac_pretext="$(sed -n "${ln}p" "$prog")"   # the item's text BEFORE its VERIFY runs (a VERIFY may rewrite the progress file; the tick re-finds the item by this text)
      if [ $((SECONDS - _t0)) -ge "$_budget" ]; then
        _LAST_VERIFY_RESULT="TIMEOUT"; _LAST_VERIFY_WHY="VERIFY timed out (rc=124) after ${_budget}s (per-cycle verify budget exhausted; not run)"
      else
        shadow_check "$ln"
      fi
      case "${_LAST_VERIFY_RESULT:-}" in
        PASS)
          ticked_lines="$ticked_lines $ln"; ticked_texts="${ticked_texts}${ln}"$'\t'"${_ac_pretext}"$'\n'
          _ovn_ac_log "VERIFY passed for line ${ln} (${cf})"
          break ;;   # one item per touched file, as before
        NO_VERIFY_CLAUSE) _ovn_ac_log "REFUSED line ${ln} (${cf}) - item has no VERIFY: clause, so there is nothing to prove it is done"
                          _ovn_cr_bump "$prog" "$ln" "no VERIFY clause" ;;
        SKIPPED_DENYLIST) _ovn_ac_log "REFUSED line ${ln} (${cf}) - the item's VERIFY: clause is not safe to run (denylist/redirect)"
                          _ovn_cr_bump "$prog" "$ln" "VERIFY not safe to run" ;;
        TIMEOUT|UNRUNNABLE)
          # indeterminate: not credited, but NOT a failure either
          indet_lines="$indet_lines $ln"; indet_msgs="${indet_msgs:+$indet_msgs; }line ${ln}: ${_LAST_VERIFY_WHY}"
          _ovn_ac_log "INDETERMINATE line ${ln} (${cf}) - ${_LAST_VERIFY_WHY}; item left open, not counted as a failed attempt"
          OVN_AC_INDETERMINATE=$((OVN_AC_INDETERMINATE + 1)) ;;
        *) _ovn_ac_log "REFUSED line ${ln} (${cf}) - the item's own VERIFY: clause FAILED"
           _ovn_cr_bump "$prog" "$ln" "VERIFY failed" ;;
      esac
    done <<< "$items"
  done <<< "$changed"

  # indeterminate VERIFYs: ONE alert per call (= per cycle), plus the marker the item guard reads (only from a tests:pass cycle)
  if [ "$OVN_AC_INDETERMINATE" -gt 0 ]; then
    _ovn_ac_alert "auto-credit not applied (indeterminate, item stays open, not a failed attempt): ${indet_msgs:0:300}"
    for ln in $indet_lines; do
      if declare -F ovn_item_hash >/dev/null 2>&1 && [ -n "$_AC_TASK_LOG" ]; then
        echo "--- auto-credit: indet-hash $(ovn_item_hash "$(sed -n "${ln}p" "$prog")") ---" >> "$_AC_TASK_LOG"
      fi
    done
  fi

  [ -n "$ticked_lines" ] || return 0

  # RULE 1 again: running a VERIFY command must not have changed the tree. If it did, WE dirtied it: restore AFTER and refuse.
  _AC_PROG_CHANGED=0
  if ! ovn_tree_matches_sha "$after" "" "$before" >/dev/null; then
    bad="$OVN_TREE_OUT"
    # lockfile-only delta / progress-file-only delta: settle instead of refusing (any source path still refuses and is hard-reset below)
    if ! _ovn_ac_settle_tree "$after" "$before" "$prog"; then
      _ovn_ac_log "REFUSED - a VERIFY command modified the tree (${bad}); restoring ${after:0:12}, nothing credited"
      git reset --hard -q "$after" 2>/dev/null
      _ovn_ac_alert "auto-credit refused: an item VERIFY command modified the working tree (${bad}); reset to the cycle commit"
      OVN_AC_NEWHEAD="$(git rev-parse HEAD 2>/dev/null)"
      return 1
    fi
  fi

  local _ac_row _ac_rowln _ac_rowtext
  for ln in $ticked_lines; do
    if [ "$_AC_PROG_CHANGED" = 1 ]; then
      # the progress file moved under us: the line number is stale, find the SAME item text again (an unchanged text that is no longer an open line is skipped)
      _ac_rowtext="$(printf '%s' "$ticked_texts" | awk -F'\t' -v n="$ln" '$1==n{print substr($0,length(n)+2); exit}')"
      _ac_rowln=""; [ -n "$_ac_rowtext" ] && _ac_rowln="$(grep -nxF -m1 -- "$_ac_rowtext" "$prog" 2>/dev/null | cut -d: -f1)"
      if [ -z "$_ac_rowln" ]; then _ovn_ac_log "SKIPPED tick of line ${ln}: its item text is not an open line of the changed progress file any more"; continue; fi
      ln="$_ac_rowln"
    fi
    _ac_before_text="$(sed -n "${ln}p" "$prog")"
    res="$(python3 "$_AC_DIR/ovn_credit_items.py" tick "$prog" "$ln" 2>/dev/null)"
    if [ "$res" = "TICKED" ]; then ovn_credit_refused_clear "$_ac_before_text" "$prog"; OVN_AC_CREDITED=$((OVN_AC_CREDITED + 1)); _ovn_ac_log "checked off line ${ln} (green change touched its named file and its VERIFY passed)"; ovn_credit_twins "$prog" "$ln" "$_AC_TASK_LOG"; ovn_card_credit_shadow "$_ac_before_text" "$after"; fi
  done
  [ "$OVN_AC_CREDITED" -gt 0 ] || return 0

  # RULE 5: stage and commit ONLY the progress file, and assert that is all that is staged.
  git add -- "$prog" 2>/dev/null
  n="$(git diff --cached --name-only 2>/dev/null | grep -v '^$' | grep -vxF "$prog" | head -5 | tr '\n' ' ')"
  if [ -n "$n" ]; then
    _ovn_ac_log "REFUSED - index holds more than the progress file (${n}); unstaging, nothing committed"
    git reset -q 2>/dev/null; git checkout -q -- "$prog" 2>/dev/null
    _ovn_ac_alert "auto-credit refused: index contained paths other than the progress file (${n})"
    OVN_AC_CREDITED=0
    return 1
  fi
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -q -m "chore(queue): auto-credit item(s) whose file this green change touched" -- "$prog" 2>/dev/null
    OVN_AC_NEWHEAD="$(git rev-parse HEAD 2>/dev/null)"
  fi
  return 0
}

# ovn_landed_uncredited <task_log> <status>: rc 0 when this cycle PUSHED green work but the item was NOT credited (2026-10-09, harness-credit-integrity item 4).
# The auto-credit above refuses (path mismatch, placeholder, no VERIFY: clause, failing VERIFY, dirty tree) and the push happens anyway, so the row
# said "landed" while the item stayed [ ] and was re-faced next cycle (churn: 7 landings on routers/subscription.py, 29 refusals/24h). record_outcome()
# writes such rows as class=landed-uncredited (neutral: counted neither as a landing nor in the pass rate; reports show "N uncredited pushes").
# Rules: status starts with pushed(tests:pass); the log SEGMENT AFTER the last '--- landing: ' marker (the runner writes one right before bookkeeping +
# auto-credit + push; best-of-N reuses one task_log, so an earlier attempt's refusal must not count; no marker => the whole log, e.g. the stage runner)
# holds a '--- auto-credit: REFUSED' / 'item has no VERIFY: clause' line and NO credit line ('--- auto-credit: checked off line' / 'item-hash').
# OVN_LANDED_UNCREDITED=off disables. Pure grep -c on a captured segment (no grep -q pipes).
ovn_landed_uncredited() {
  local tl="${1:-}" st="${2:-}" n seg refused credited
  [ "${OVN_LANDED_UNCREDITED:-on}" = off ] && return 1
  [ -n "$tl" ] && [ -f "$tl" ] || return 1
  case "$(printf '%s' "$st" | tr 'A-Z' 'a-z')" in 'pushed(tests:pass)'*) ;; *) return 1 ;; esac
  n="$(grep -an '^--- landing: ' "$tl" 2>/dev/null | tail -1 | cut -d: -f1)"
  if [ -n "$n" ]; then seg="$(tail -n +$((n + 1)) "$tl" 2>/dev/null)"; else seg="$(cat "$tl" 2>/dev/null)"; fi
  refused="$(grep -acE '^--- auto-credit: REFUSED|item has no VERIFY: clause' <<< "$seg")"
  [ "${refused:-0}" -gt 0 ] || return 1
  credited="$(grep -acE '^--- auto-credit: (checked off line|item-hash) ' <<< "$seg")"
  [ "${credited:-0}" -eq 0 ]
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------
# CREDIT PATHS THAT RAN NO VERIFY (2026-10-09, harness-credit-integrity item 7). ovn_auto_credit RULE 4 above and ovn_credit_already_satisfied.sh (the any-verdict and
# implement-pass credits) already run the item's own VERIFY. Two runner paths still ticked an item on a claim alone:
#   - the scout ALREADY-DONE credit (run_overnight.sh, scout block): "the scout's PLAN names a file matching an open item => [x] (already-done, scout-verified)"
#   - the DONE:-trailer bookkeeping (update_progress.py ticks whatever the model's commit message declared done)
# ovn_credit_verify_gate <prog> <line> [task_log] [label] runs shadow_check (lib_verify_clause.sh, unchanged) on the item's VERIFY and answers rc 1 = REFUSE the credit
# only when the clause FAILED and OVN_VERIFY_GATE_MODE is enforce (the existing flag; default enforce, as in ovn_credit_already_satisfied.sh). OVN_VERIFY_GATE_MODE=shadow
# logs 'would be REFUSED' and credits. An item with NO VERIFY clause, an unsafe clause, or an INDETERMINATE one (timeout / unrunnable: no evidence the credit is wrong)
# keeps today's behaviour (credited).
# SCOUT-REFUSAL COUNTER (2026-10-12, package uidcredit). The scout ALREADY-DONE credit above refuses when the item's own VERIFY FAILS, but that refusal was never counted toward the
# credit_refused park: xlite `add-enemyfactionmap` T1/T2 had `-gdir=tests/test_x.gd` VERIFYs (GUT -gdir takes a DIRECTORY: "The path [tests/test_x.gd] does not exist. Nothing was run";
# real run on the box 2026-10-12) that can never pass, so 4 cycles in a row the scout said ALREADY-DONE (true: faction_for exists), the gate refused, and only the 5-no-op cap ended it.
# OVN_SCOUT_REFUSAL_PARK=on|shadow|off (default ON since 2026-10-13, was shadow): `on` bumps the same state/credit_refused counter the auto-credit refusals use, so
# ovn_item_guard parks the item at OVN_REFUSED_PARK_AT (default 2) with '[AUTO-SKIP after N credit refusals: VERIFY failed (...)]'. Only the scout ALREADY-DONE label counts
# (the DONE-trailer gate runs on a commit that may be a half-done attempt that the failed-attempt counters already bill). shadow = log what would be counted, off = old behaviour.
# WHY ON (night review 2026-10-13, iptv F5; evidence table in docs/SCOUT_REFUSAL_PARK_2026-10-13.md): 26 distinct items / 83 cycles had a scout ALREADY-DONE credit refused by
# the item's own VERIFY (10-04..10-13); every one of the 20+ hand-checked items was genuinely done in code and its VERIFY unsatisfiable or unrunnable (TS generic breaking a literal
# grep, a -k test name that does not exist, a literal import line, 'cd /path/to/xlite', 'cd tests && godot -s'). No hand-checked item was a wrong scout claim. Parking at the 2nd
# refusal would have skipped 41 of the 83 cycles; the 5-no-op cap used to be the only brake (9 wasted cycles / 258k tokens on one recordings.ts item).
_ovn_scout_refusal() {  # <prog> <line> <label> [task_log]
  local prog="$1" ln="$2" label="$3" tl="${4:-}" mode="${OVN_SCOUT_REFUSAL_PARK:-on}" text n cf
  case "$label" in "scout ALREADY-DONE credit") ;; *) return 0 ;; esac
  [ "$mode" = off ] && return 0
  [ "${OVN_REFUSED_PARK_AT:-2}" = 0 ] && return 0
  text="$(sed -n "${ln}p" "$prog" 2>/dev/null)"; [ -n "$text" ] || return 0
  if [ "$mode" = on ]; then
    ovn_credit_refused_note "$text" "VERIFY failed${_LAST_VERIFY_WHY:+ (${_LAST_VERIFY_WHY//[\]\[]/})}" "$prog"
    [ -n "$tl" ] && echo "--- verify-gate: scout ALREADY-DONE refusal at line ${ln} counted toward the credit-refusal park ---" >> "$tl"
  else
    cf="$(_ovn_cr_dir)/$(_ovn_cr_repo "$prog").$(_ovn_cr_hash "$text")"
    n="$(sed -n 1p "$cf" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
    [ -n "$tl" ] && echo "--- verify-gate: SHADOW scout ALREADY-DONE refusal at line ${ln} would count as refusal $((n + 1)) of ${OVN_REFUSED_PARK_AT:-2} (OVN_SCOUT_REFUSAL_PARK=on enforces) ---" >> "$tl"
  fi
  return 0
}

ovn_credit_verify_gate() {
  local prog="$1" ln="$2" tl="${3:-}" label="${4:-credit}" mode="${OVN_VERIFY_GATE_MODE:-enforce}"
  declare -F shadow_check >/dev/null 2>&1 || return 0
  local PROG="$prog" SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}" _REPO_LABEL VERIFY_TIMEOUT_SECS="${OVN_CREDIT_VERIFY_TIMEOUT:-300}" VERIFY_TIMEOUT_HEAVY_SECS="${OVN_CREDIT_VERIFY_TIMEOUT_HEAVY:-900}" _VC_MEMO="" _VC_MEMO_ON=0
  _REPO_LABEL="$(basename "$PWD")"; mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
  shadow_check "$ln"
  case "${_LAST_VERIFY_RESULT:-}" in
    FAIL)
      if [ "$mode" = enforce ]; then
        [ -n "$tl" ] && echo "--- verify-gate: ${label} REFUSED at line ${ln} - the item's own VERIFY: clause FAILED; left open ---" >> "$tl"
        _ovn_scout_refusal "$prog" "$ln" "$label" "$tl"
        return 1
      fi
      [ -n "$tl" ] && echo "--- verify-gate: ${label} at line ${ln} would be REFUSED (VERIFY: clause FAILED) - OVN_VERIFY_GATE_MODE=${mode}, crediting anyway ---" >> "$tl"
      return 0 ;;
    TIMEOUT|UNRUNNABLE)
      # 2026-10-16 (overnight review, xlite): an UNRUNNABLE VERIFY (rc 127 - the clause's tool is absent) is not evidence that the item is done, and the scout ALREADY-DONE credit
      # ran on it anyway (50 rows in one night). OVN_UNRUNNABLE_CREDIT_GATE: shadow (default: log 'would be REFUSED' and credit as before) | enforce (refuse; the item stays open) | off.
      # New enforcement ships shadow-only; flip to enforce after a soak. TIMEOUT is unchanged.
      if [ "${_LAST_VERIFY_RESULT}" = UNRUNNABLE ] && [ "$label" = "scout ALREADY-DONE credit" ] && [ "${OVN_UNRUNNABLE_CREDIT_GATE:-shadow}" != off ]; then
        if [ "${OVN_UNRUNNABLE_CREDIT_GATE:-shadow}" = enforce ]; then
          [ -n "$tl" ] && echo "--- verify-gate: ${label} REFUSED at line ${ln} - VERIFY UNRUNNABLE (${_LAST_VERIFY_WHY:-no verdict}); item left open ---" >> "$tl"
          return 1
        fi
        [ -n "$tl" ] && echo "--- verify-gate: ${label} at line ${ln} would be REFUSED (VERIFY UNRUNNABLE: ${_LAST_VERIFY_WHY:-no verdict}) - OVN_UNRUNNABLE_CREDIT_GATE=shadow, crediting anyway ---" >> "$tl"
      fi
      [ -n "$tl" ] && echo "--- verify-gate: ${label} at line ${ln}: VERIFY indeterminate (${_LAST_VERIFY_WHY:-no verdict}); not a failure, crediting as before ---" >> "$tl"
      return 0 ;;
  esac
  return 0
}

# ovn_bookkeeping_verify_gate <prog> [task_log]: after update_progress.py ticked items from DONE: trailers (working tree edited, NOT yet committed), run the VERIFY gate
# on every item it flipped "- [ ] X" -> "- [x] X" (exact text twin, relative to HEAD's copy of <prog>) and UN-tick the ones the gate refuses. Prints the number refused.
ovn_bookkeeping_verify_gate() {
  local prog="$1" tl="${2:-}" old line rest nl refused=0
  [ -f "$prog" ] || { printf '0'; return 0; }
  old="$(mktemp 2>/dev/null)" || { printf '0'; return 0; }
  if git show "HEAD:${prog}" > "$old" 2>/dev/null; then
    while IFS= read -r line; do
      rest="${line#- \[ \] }"
      nl="$(grep -nxF -- "- [x] ${rest}" "$prog" 2>/dev/null | head -1 | cut -d: -f1)"
      [ -n "$nl" ] || continue
      if ! ovn_credit_verify_gate "$prog" "$nl" "$tl" "DONE-trailer credit"; then
        _ovn_sed_i "${nl}s/^- \[x\] /- [ ] /" "$prog"
        refused=$((refused + 1))
      fi
    done < <(grep -E '^- \[ \] ' "$old")
  fi
  rm -f "$old"
  printf '%s' "$refused"
}
