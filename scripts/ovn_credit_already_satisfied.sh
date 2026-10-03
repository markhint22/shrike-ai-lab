#!/usr/bin/env bash
# Credit items the IMPLEMENT pass found already-satisfied in the code.
# The 27B walks the item list during implement and reports items already done
# ("Query is already imported", "already uses except Exception", "This item is
# already done") -> no diff, no commit -> UNTAGGED no-op, and the item is
# re-faced every cycle forever. This harvests the file named right before each
# already-done admission (awk tracks the last file token seen) and checks off
# the matching unchecked, non-human item. Prints CREDITED=<n>. Run in repo cwd.
#
# SHADOW-MODE VERIFY GATE (2026-09-24): this mechanism has ZERO actual
# verification - despite the "(already-satisfied in code, implement-verified)"
# label, it never checks the file exists or runs the item's own VERIFY: clause.
# Confirmed via direct filesystem checks (billwatch research pass): multiple
# credited items' target files don't exist (create/modify items) or still
# exist (delete items) despite being marked done. A broader tight-regex sample
# across 4 repos found a 5-21% suspect rate on 464 checkable credits - a real,
# previously invisible data-integrity gap, not an edge case (see memory:
# project_credit-already-satisfied-false-credit-bug-2026-09-24).
#
# This adds a SHADOW check only: before crediting, extract the item's own
# "VERIFY: `<cmd>`" clause and actually run it, logging PASS/FAIL/NO_CLAUSE/
# SKIPPED to state/verify_gate_shadow.log. Crediting behavior is UNCHANGED -
# this purely observes, so we get real pass/fail data before deciding whether
# to demote failing credits back to open (a Phase-3-style staged rollout, not
# an immediate behavior flip - see the pipeline-hardening plan).
#
# CALIBRATION (2026-09-25, after the first overnight run of real shadow data):
#   1. A bare `python`/`python3` VERIFY command (no .venv/ prefix) resolved to
#      whatever interpreter is on PATH, which lacks this repo's installed deps
#      (pytest etc) - a real FAIL was actually "No module named pytest", an
#      environment mismatch, not a false credit. Same fix already proven in
#      ovn_stage_runner.sh's try_regen: substitute the repo's own venv python
#      when one exists nearby.
#   2. The denylist's blanket `*">"*` match skipped `2>/dev/null` (a completely
#      standard, safe stderr-suppression idiom used throughout this fleet's own
#      VERIFY clauses) as if it were a real file write, throwing away signal on
#      common, safe commands. Narrowed to only deny an actual non-/dev/null
#      redirect target.
#
# CALIBRATION ROUND 2 (2026-09-26, after 105 more shadow data points - 44 FAIL,
# but almost all environment noise, not real credit problems):
#   3. Bare `pytest` (no "python"/"python3" token at all) was never substituted -
#      only "python "/"python3 " prefixes were, so a VERIFY of plain
#      `pytest tests/...` still resolved to whatever's on PATH (often nothing:
#      "pytest: command not found", or the wrong interpreter's site-packages:
#      "No module named pytest" on iptv_apps).
#   4. Several items' own hardcoded VERIFY text has a duplicated path segment
#      from a "cd backend && ./backend/.venv/bin/python3 ..." authoring
#      mistake - after the cd, that resolves to backend/backend/.venv/..., which
#      never exists. Confirmed on shrike-monitor and test-automation-agent.
#   5. `godot` is never on PATH anywhere on this box (confirmed: no symlink, no
#      alias, not found even in a login shell) - the REAL pipeline
#      (run_overnight.sh's own GUT-test verification) always calls the full
#      "$HOME/godot/godot4" path, but VERIFY clauses are authored with bare
#      `godot`, which only ever works by accident if something else's PATH
#      happens to include it. Every xlite VERIFY containing "godot" was a
#      guaranteed FAIL here regardless of the actual credit's correctness.
# Fix: replaced the narrow token-substitution with a small tool-path resolver
# that (a) always substitutes bare `godot` for $HOME/godot/godot4, matching the
# real pipeline's own convention exactly, and (b) re-resolves python/python3/
# pytest against a FRESH `find` for the nearest real .venv - authoritatively
# replacing the command's own path reference even when one is already present,
# so an already-correct path is a no-op substitution and an already-wrong one
# self-heals, instead of trying to detect and special-case every possible
# wrong-path shape by hand.
set -uo pipefail
LOG="${1:-}"; PROG="${2:-OVERNIGHT_PROGRESS.md}"
[ -f "$LOG" ] || { echo "CREDITED=0"; exit 0; }
[ -f "$PROG" ] || { echo "CREDITED=0"; exit 0; }

# PROMOTED 2026-09-28: after 3 rounds of tool-path calibration (2026-09-25/26/27),
# post-round-3 shadow data (deployed 2026-09-27 09:23 CDT) shows 27 PASS vs 5 FAIL,
# with EVERY post-fix FAIL a genuine content signal (an item whose VERIFY clause no
# longer matches reality - already-flagged/already-resolved-differently in each
# case checked), zero remaining tooling-noise false negatives. Meets the plan's own
# "promote independently once proven" bar. OVN_VERIFY_GATE_MODE=shadow reverts
# instantly to the old observe-only behavior with no code change if this needs
# rolling back.
VERIFY_GATE_MODE="${OVN_VERIFY_GATE_MODE:-enforce}"

SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}"
mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
_REPO_LABEL="$(basename "$PWD")"

# _resolve_tool_paths / _has_real_redirect / shadow_check live in lib_verify_clause.sh (shared with the runner's auto-credit, 2026-10-02).
# shellcheck source=lib_verify_clause.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib_verify_clause.sh"

# TARGET-PATH GATE (2026-09-30): the VERIFY gate above only protects items that HAVE a runnable VERIFY clause.
# The 2026-09-24 audit found 5-21% of credits wrong (billwatch 21%, gitlark 16%) and the remaining exposure is
# items with NO_VERIFY_CLAUSE / SKIPPED_DENYLIST, which still credited on the model's say-so alone. This is the
# cheap, tight check that audit used: the item's own LEADING path (`- [ ] [T3] path/to/file.ext — ...`) must
# make sense. A create/modify item whose target file does not exist cannot be "already satisfied in code"; a
# delete/remove item whose target still exists is not satisfied either. Result is OK / MISSING / STILL_EXISTS /
# NA (no resolvable leading path -> no opinion, credit as before). OVN_PATH_GATE=off disables (observe-only
# logging stays); OVN_PATH_GATE=shadow logs but never refuses.
PATH_GATE_MODE="${OVN_PATH_GATE:-enforce}"
_LAST_PATH_RESULT=""
path_gate(){  # $1 = line number in $PROG about to be credited. Sets $_LAST_PATH_RESULT. Logic lives in ovn_path_gate.py (shared with the scout credit path).
  local ln="$1" ts out; ts="$(date -u +%FT%TZ)"
  out="$(python3 "$(dirname "${BASH_SOURCE[0]}")/ovn_path_gate.py" "$PROG" "$ln" "$PWD" 2>/dev/null)"
  _LAST_PATH_RESULT="${out%% *}"; [ -n "$_LAST_PATH_RESULT" ] || _LAST_PATH_RESULT="NA"
  [ "$_LAST_PATH_RESULT" = "NA" ] && return
  echo "$ts repo=$_REPO_LABEL line=$ln path_gate=$_LAST_PATH_RESULT target=${out#* }" >> "$SHADOW_LOG"
}

# UNDER-CREDITING FIX (2026-09-28): both patterns below were exact-phrase matches with zero
# tolerance for ordinary sentence variation, so a correctly-completed item whose model
# response phrased "nothing to change" even slightly differently was scored as a flail
# (no FILES match -> no credit -> re-served every cycle) instead of neutral. Confirmed live
# on billwatch: a stuck item that was ALREADY correctly fixed in code kept getting re-served
# and re-failing for 4+ days, burning ~450K tokens, because its "already done" responses
# were phrased in ways like "This item appears to already be satisfied" that this regex
# could not see. Calibrated against 350+ real recent model responses (grep across
# logs/*billwatch*.log), not guessed - every addition below is a phrasing that actually
# appeared and was NOT matched by the old pattern:
#   "already be satisfied"       - the old pattern required "already <word>" adjacency;
#                                   a "be" (or "fully"/"correctly"/"completely") between
#                                   "already" and the verb broke the match every time.
#   "already fully implemented", "already correctly defined" - same adjacency gap.
#   "already contains", "already defined", "already handles", "already satisfies" - present-
#                                   tense/3rd-person verb forms the old list never had (it only
#                                   had "handled"/"satisfied" past tense, no "contains"/"defined").
#   "already fine"                - a common casual completion phrase, not in the old list at all.
#   "No further changes are needed.", "No code changes needed." - the old "No changes? needed"
#                                   pattern required strict adjacency; "further"/"code" in
#                                   between broke it.
#   "does not need any changes."  - an entirely different sentence shape the old pattern
#                                   had no alternative for at all.
# This is purely a RECALL fix (catching more true already-done responses) - it does NOT
# weaken the enforce-mode VERIFY gate below, which independently confirms (and can still
# REFUSE) every credit this produces, so a broader match that happens to be wrong still
# cannot silently over-credit - see that gate's own 2026-09-24/25/26/27 header notes.
FILES="$(awk '
  { if (match($0, /[A-Za-z0-9_\/.-]+\.[A-Za-z0-9]{1,8}/)) { lastf=substr($0,RSTART,RLENGTH) } }
  /[Aa]lready (fully |correctly |completely |essentially |be )*(done|implemented|imported|present|in place|use|uses|has|have|correct|handled|handles|satisfied|satisfies|been|exists?|contains?|defined|defines|covers?|tests?|validates?|guards?|fine|good|complete)/ { if (lastf!="") print lastf }
  /[Nn]o (code |further |additional )*changes? (are |is )?(needed|required|necessary)|[Nn]othing to (change|do|add)|is already (there|the case)|already (passes|passing)|does not (need|require) (any )?changes?/ { if (lastf!="") print lastf }
' "$LOG" | sort -u)"
credited=0
for f in $FILES; do
  case "$f" in *.md) continue;; esac
  b="$(basename "$f")"
  ln="$(grep -nE '^- \[ \]' "$PROG" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED ITEM' | grep -F "$b" | head -1 | cut -d: -f1)"
  if [ -n "$ln" ]; then
    shadow_check "$ln"
    # ENFORCE: a FAIL means the item's own VERIFY clause does not hold - refuse
    # the credit and leave it open rather than propagate a false "done" (the
    # exact data-integrity gap this whole mechanism was built to close). PASS/
    # NO_VERIFY_CLAUSE/SKIPPED_DENYLIST all credit as before - none of those are
    # evidence the credit is wrong, just cases this check can (or chooses not
    # to) verify one way or the other.
    _LAST_PATH_RESULT="NA"
    # the path gate covers exactly what the VERIFY gate cannot: items with no runnable VERIFY clause
    case "$_LAST_VERIFY_RESULT" in NO_VERIFY_CLAUSE|SKIPPED_DENYLIST) path_gate "$ln" ;; esac
    # (2026-10-02 harness-X: TIMEOUT / UNRUNNABLE used to be reported as FAIL by shadow_check and were refused here; they are now distinct results
    # but this caller keeps refusing them - an unverified already-satisfied claim must not be credited. It keeps the 60s cap: it sets no VERIFY_TIMEOUT_*.)
    if [ "$VERIFY_GATE_MODE" = "enforce" ] && { [ "$_LAST_VERIFY_RESULT" = "FAIL" ] || [ "$_LAST_VERIFY_RESULT" = "TIMEOUT" ] || [ "$_LAST_VERIFY_RESULT" = "UNRUNNABLE" ]; }; then
      echo "REFUSED credit at line ${ln} (matched ${b}) - VERIFY clause failed${_LAST_VERIFY_WHY:+ ($_LAST_VERIFY_WHY)}, left open for review"
    elif [ "$PATH_GATE_MODE" = "enforce" ] && { [ "$_LAST_PATH_RESULT" = "MISSING" ] || [ "$_LAST_PATH_RESULT" = "STILL_EXISTS" ]; }; then
      echo "REFUSED credit at line ${ln} (matched ${b}) - item's own target path check: ${_LAST_PATH_RESULT}, left open for review"
    else
      sed -i "${ln}s/^- \[ \] /- [x] (already-satisfied in code, implement-verified) /" "$PROG"
      credited=$((credited+1))
      echo "credited line ${ln} (matched ${b})"
    fi
  fi
done
echo "CREDITED=${credited}"
exit 0
