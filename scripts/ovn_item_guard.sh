#!/usr/bin/env bash
# Per-item fail cap (2026-08-28): if the SAME top-unchecked Next Steps item fails
# to land N consecutive cycles, auto-tag it "HUMAN-ONLY BLOCKED" so the model
# skips it (the prompt already tells it to skip those) instead of banging on the
# same wall forever — the npm-audit 8x pattern. Only ever ADDS a skip tag on a
# tiny doc commit; reversible; never touches code. A landing resets the counter.
#
# No-op streak cap (2026-08-31): the guard used to `exit 0` on any no-op, so an
# already-done / mis-targeted / too-hard item that cleanly no-ops EVERY cycle sat
# at the top of the list forever, blocking everything below it — the #1 lingering
# no-op source (e.g. an item naming a router file when the logic lives in a
# delegated service the model correctly reports as already-done, so the
# credit-by-filename never matches and it never gets checked off). Now same-item
# no-ops accrue on their OWN streak and the item is parked (AUTO-SKIP) once it
# proves it will never land. Separate counter + higher cap than the fail path so
# a couple of incidental no-ops never park a real item.
# Token-budget cap (2026-09-10): the cycle-count caps above assume every cycle costs about the
# same, but a T4/T5 item's decomposed multi-step attempt can burn 5-10x what a T1 one-shot does
# — CAP/NCAP alone lets an expensive item thrash through several times the token spend of a
# cheap one before either cap trips. This tracks CUMULATIVE tokens for the current streak
# alongside the existing cycle count and trips FIRST on whichever limit is hit, so an expensive
# item gets caught by spend, not just by attempt count. Same streak-reset semantics as the
# cycle counters (a new item hash starts the token tally over; a landing clears it).
#
# Per-ITEM state keying (2026-09-29 FIX): every streak file used to be keyed ONLY by the
# generic repo-task-id (e.g. "ongoing-billwatch"), a SINGLE SLOT shared by every item that
# ever passes through this guard for that id/repo — not by which specific item is actually
# stuck. Confirmed live on billwatch: a stuck feature (3 sub-items sharing one [feat:...] tag)
# burned 7 reverts over ~3.5h and ~660k tokens before hitting the expensive TOKCAP, because 6
# unrelated, successful landings elsewhere in the SAME repo each hit the old unconditional
# `rm -f` in the tests:pass case below and wiped the id's single slot — resetting whatever
# stuck item happened to be "top" at that moment back to a 0-streak, so the cheap CAP=3/NCAP=4
# cycle-count caps never got a real chance to fire. Every state file is now keyed by
# (id, item_hash) instead of just id, so a repeated failure of the SAME item accrues on its
# OWN file regardless of what else happens in the repo, and a landing only ever touches the
# file(s) for the item hash(es) that ACTUALLY landed this cycle (see the tests:pass case below
# for how that identity is established) — never a different item's counter.
# args: <repo_dir> <status> <state_dir> <id> [<task_log>]
set -uo pipefail
repo="${1:-}"; status="${2:-}"; state="${3:-}"; id="${4:-}"; task_log="${5:-}"
[ -n "$repo" ] && [ -d "$repo" ] || exit 0
prog="$repo/OVERNIGHT_PROGRESS.md"
[ -f "$prog" ] || exit 0
CAP="${OVN_ITEM_FAIL_CAP:-3}"
NCAP="${OVN_ITEM_NOOP_CAP:-4}"
TOKCAP="${OVN_ITEM_TOKEN_CAP:-200000}"
mkdir -p "$state/item_fails" 2>/dev/null || exit 0

cur_toks=0
if [ -n "$task_log" ] && [ -f "$task_log" ]; then
  cur_toks="$(grep -oiE '[0-9.]+k? +sent' "$task_log" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"
  cur_toks="${cur_toks:-0}"
fi

_lib="$(dirname "$0")/lib_item_select.sh"
# shellcheck source=scripts/lib_item_select.sh
[ -f "$_lib" ] && . "$_lib"
# shellcheck source=scripts/lib_bug_escalate.sh
_elib="$(dirname "$0")/lib_bug_escalate.sh"; [ -f "$_elib" ] && . "$_elib"

# portable in-place sed (GNU on the box, BSD on the Mac where the tests run): GNU sed accepts `-i` alone, BSD sed needs `-i ''`
_ig_sedi() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }

# --- Credit-refusal park (2026-10-09, harness-credit-integrity item 6) ---------------------------------------------------------------------------
# lib_auto_credit.sh bumps state/credit_refused/<repo>.<item hash> ("<count>\n<reason>\n<item line>") whenever a green commit touched an item's OWN file but the credit was
# refused (placeholder / no VERIFY clause / unsafe VERIFY / VERIFY failed). The cycle still pushes, so the item stays open and is re-faced. At OVN_REFUSED_PARK_AT
# (default 2; 0 disables) refusals the item is parked with the usual reversible tag '[AUTO-SKIP after N credit refusals: <reason>]'. A stale counter (the item was
# credited, edited or already parked) is deleted. Runs on every guard call: only the green landing statuses can have created one, and it is a cheap directory test.
_rp_at="${OVN_REFUSED_PARK_AT:-2}"
if [ "$_rp_at" -gt 0 ] 2>/dev/null && [ -d "$state/credit_refused" ]; then
  _rp_parked=0
  # ONLY this repo's counters ("<repo>.<hash>"; state/credit_refused is shared by every repo): another repo's counter is never read, parked or deleted here
  # (its item line is not in THIS progress file, so the stale-counter rule below would have deleted it and lost that repo's park)
  _rp_repo="$(basename "$repo" | sed 's/[^A-Za-z0-9_-]/_/g')"
  find "$state/credit_refused" -maxdepth 1 -type f ! -name '*.*' -mtime +1 -exec rm -f {} + 2>/dev/null   # pre-per-repo bare-hash counters: ownerless, aged out
  for _rf in "$state/credit_refused/${_rp_repo}."*; do
    [ -f "$_rf" ] || continue
    _rn="$(sed -n 1p "$_rf" 2>/dev/null)"
    case "$_rn" in ''|*[!0-9]*) rm -f "$_rf"; continue ;; esac
    [ "$_rn" -ge "$_rp_at" ] || continue
    _rr="$(sed -n 2p "$_rf" 2>/dev/null | tr -cd 'A-Za-z0-9 ,.:;()/_-')"; [ -n "$_rr" ] || _rr="credit refused"
    _rt="$(sed -n '3,$p' "$_rf" 2>/dev/null)"
    _rl=""
    [ -n "$_rt" ] && _rl="$(grep -nF -- "$_rt" "$prog" 2>/dev/null | grep -E '^[0-9]+:- \[ \] ' | head -1 | cut -d: -f1)"
    if [ -z "$_rl" ]; then rm -f "$_rf"; continue; fi
    _ig_sedi "${_rl}s#^- \[ \] #- [ ] [AUTO-SKIP after ${_rn} credit refusals: ${_rr}] #" "$prog"
    rm -f "$_rf"; _rp_parked=$((_rp_parked + 1))
  done
  if [ "$_rp_parked" -gt 0 ] && ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
    _rp_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
    git -C "$repo" commit -q -m "chore(queue): park ${_rp_parked} item(s) after ${_rp_at}+ credit refusals (green commits the auto-credit could not tick)" -- OVERNIGHT_PROGRESS.md 2>/dev/null
    [ -n "$_rp_branch" ] && git -C "$repo" push -q origin "$_rp_branch" 2>/dev/null
    echo "AUTO-SKIPPED ${_rp_parked} item(s) after ${_rp_at}+ credit refusals"
  fi
fi

# A clean landing clears the fail/no-op streaks (+ grounded failure memory) for whichever
# item(s) actually landed THIS cycle — identified via "item-hash <md5>" marker line(s) that
# run_overnight.sh writes into $task_log at the exact moment(s) it checks an item off in
# OVERNIGHT_PROGRESS.md (both the per-file auto-credit path and the DONE:-trailer bookkeeping
# path; see run_overnight.sh's 2026-09-29 comment at the marker-emission site).
#
# Why not just re-resolve "the top item" here like the fail/no-op paths do below? Because by
# the time this guard runs on a landing, the item that just landed has ALREADY been flipped
# from "- [ ] " to "- [x] " in OVERNIGHT_PROGRESS.md (the credit happens earlier in the same
# cycle, before this script is ever invoked) — so a fresh top-of-file/scout-match re-read can
# only ever find a DIFFERENT, still-open item, never the one that landed. Blindly clearing
# THAT item's counter is exactly the cross-item bug this fix targets, just with a narrower
# blast radius. Only ever clear a hash this cycle's task_log positively names as landed.
#
# KNOWN GAP: the higher-tier staged sub-flow (ovn_stage_runner.sh) checks its own items off
# directly (a separate worktree/branch) and does not yet emit this marker, so a staged item's
# OWN prior fail-streak (if any) is not cleared on its own staged landing — a narrower,
# self-only limitation (it never touches ANOTHER item's counter) left as a documented
# follow-up rather than risking a same-pass edit to that larger, separately-gated script.
case "$status" in
  *"tests:pass"*)
    if [ -n "$task_log" ] && [ -f "$task_log" ]; then
      while IFS= read -r _lh; do
        [ -z "$_lh" ] && continue
        rm -f "$state/item_fails/${id}.${_lh}.count" "$state/item_fails/${id}.${_lh}.toks" \
              "$state/item_fails/${id}.${_lh}.noopcount" "$state/item_fails/${id}.${_lh}.nooptoks" \
              "$state/item_fails/${id}.${_lh}.lastfail" "$state/item_fails/${id}.${_lh}.indet" "$state/item_fails/${id}.${_lh}.indetlands" "$state/item_fails/${id}.${_lh}.lastids" \
              "$state/item_fails/${id}.${_lh}.ungrounded" "$state/credit_refused/$(basename "$repo" | sed 's/[^A-Za-z0-9_-]/_/g').${_lh}" 2>/dev/null   # h13 review: a landing of this feature breaks the ungrounded-plan streak ("consecutive"); item credited => its credit-refusal counter goes too
      done < <(grep -ohE 'item-hash [0-9a-f]{32}' "$task_log" 2>/dev/null | awk '{print $2}' | sort -u)
      # 2026-10-02 (harness-X X-a): "indet-hash <md5>" = the cycle landed green but the item's own VERIFY timed out / was not runnable, so the runner
      # could neither credit nor fail it. The commit DID land: clear its failure/no-op streaks like a credited landing, and arm a bounded allowance
      # (.indet, max OVN_INDET_NOOP_ALLOW=3 cycles) so the next cycles' benign ALREADY-DONE no-ops do not walk it toward the no-op AUTO-SKIP.
      # follow-up 3: bound it ACROSS cycles. A VERIFY that is permanently unrunnable/hung would otherwise let the item land, clear its streaks and
      # re-arm the allowance forever (never credited, never auto-skipped). After OVN_INDET_LAND_MAX (default 4) indeterminate landings of the same
      # item the streaks are no longer cleared, so normal accounting resumes, and one alert asks for a human.
      while IFS= read -r _ih; do
        [ -z "$_ih" ] && continue
        _il=$(( $(cat "$state/item_fails/${id}.${_ih}.indetlands" 2>/dev/null || echo 0) + 1 ))
        printf '%s' "$_il" > "$state/item_fails/${id}.${_ih}.indetlands" 2>/dev/null
        if [ "$_il" -gt "${OVN_INDET_LAND_MAX:-4}" ]; then
          [ "$_il" -eq $(( ${OVN_INDET_LAND_MAX:-4} + 1 )) ] && echo "$(date '+%F %T') warn | item-guard | ${id} item ${_ih:0:8} landed $_il times but its VERIFY never concluded (timeout/unrunnable): fix or replace the VERIFY clause; streaks are no longer cleared" >> "$state/alerts.log" 2>/dev/null
          continue
        fi
        rm -f "$state/item_fails/${id}.${_ih}.count" "$state/item_fails/${id}.${_ih}.toks" \
              "$state/item_fails/${id}.${_ih}.noopcount" "$state/item_fails/${id}.${_ih}.nooptoks" \
              "$state/item_fails/${id}.${_ih}.lastfail" "$state/item_fails/${id}.${_ih}.ungrounded" 2>/dev/null
        printf '0' > "$state/item_fails/${id}.${_ih}.indet" 2>/dev/null
      done < <(grep -ohE 'indet-hash [0-9a-f]{32}' "$task_log" 2>/dev/null | awk '{print $2}' | sort -u)
    fi
    # 2026-10-02 (bugs-first): the higher-tier staged runner checks its items off itself and emits no item-hash marker (KNOWN GAP above), so a
    # landed step of a manual bug's brief would leave that bug's attempt counter standing and the NEXT step would inherit it. While a manual bug
    # is open the lane works ONLY bug items (lib_item_select.sh lane focus), so any landing here is a bug-step landing: clear this id's bug
    # attempt counters (separate *.bugcount/*.bugtoks files - generic item counters are untouched). No bug counters exist otherwise.
    [ "${OVN_BUG_FIRST:-on}" != off ] && rm -f "$state/item_fails/${id}."*.bugcount "$state/item_fails/${id}."*.bugtoks 2>/dev/null
    exit 0
    ;;
esac

# 2026-10-02: the scout-file guard already PARKED the item this cycle ([CLAUDE] [unworkable: ...]) - it left the doable set, so the fresh
# top-item resolve below would bill this cycle (streak + lastfail memory) to whatever unrelated line is now on top. Nothing to track.
case "$status" in "no-op(scout-unworkable)") exit 0;; esac
# 2026-10-02 (review fix): the staged runner already counted/escalated THIS cycle's attempt on a manual bug itself ("bug-handled" marker in the status,
# emitted by run_overnight.sh from the runner's bug_attempt journal event). Re-resolving "top" here would bill the cycle (streak + lastfail memory) to
# an unrelated roadmap item once the bug has been parked - the same cross-item mis-attribution as scout-unworkable above. Nothing to track.
case "$status" in *"bug-handled"*) exit 0;; esac
# h13 review: the delete executor already CREDITED the item whose target was gone (log marker below) and returned no-op(ALREADY-DONE). The fresh
# top-item resolve would bill that no-op to the NEXT open item (often a sibling of the same dead-code [feat:] group), walking it toward the no-op park.
if [ "$status" = "no-op(ALREADY-DONE)" ] && [ -n "$task_log" ] && [ -f "$task_log" ] && grep -q -- 'DELETE-EXECUTOR: .* is already gone' "$task_log" 2>/dev/null; then exit 0; fi

# 2026-10-09 (harness-credit-integrity item 8): a staged cycle (status ... stage(higher-tier)) ran the item the STAGE RUNNER picked, not the top-of-file / scout
# match this guard would resolve below, so billing it to the top line charged an unrelated item (and parked it). run_overnight.sh writes 'stage-item-hash <md5>' and
# 'stage-item-line <text>' into the task log; a stage status WITHOUT them bills nothing (like bug-handled); with them the failure/no-op is billed to THAT item.
# (A staged LANDING needs no code here: its 'stage-item-hash <md5>' marker also matches the 'item-hash <md5>' pattern of the landing case above.)
# OVN_STAGE_BILLING=off restores the old top-line billing.
_stage_h=""; _stage_txt=""
case "$status" in
  *"stage(higher-tier)"*)
    if [ "${OVN_STAGE_BILLING:-on}" != off ]; then
      if [ -n "$task_log" ] && [ -f "$task_log" ]; then
        _stage_h="$(grep -aoE 'stage-item-hash [0-9a-f]{32}' "$task_log" 2>/dev/null | tail -1 | awk '{print $2}')"
        _stage_txt="$(grep -a '^stage-item-line ' "$task_log" 2>/dev/null | tail -1 | sed 's/^stage-item-line //')"
      fi
      [ -n "$_stage_h" ] && [ -n "$_stage_txt" ] || exit 0
    fi ;;
esac

# The top unchecked item that is NOT already tagged blocked/skipped.
# 2026-09-17 fix: this was the ONE selector 383a2d9 missed when it added a
# \[CLAUDE\] exclusion to the 6 other "find the real top item" selectors in
# run_overnight.sh/ovn_recover_parked.sh. Since THIS is the selector that both
# (a) decides which line's pass/fail/no-op streak gets tracked and (b) applies
# the "[AUTO-SKIP after N cycles...]" tag, missing the exclusion here meant
# every cycle's real outcome (whatever file the model actually worked on, per
# cycle_summary.log's planfiles=) kept getting attributed to the frozen
# [CLAUDE]-escalated line instead - which then re-tripped the fail/no-op cap
# and got AUTO-SKIP re-prepended onto the escalation line itself, over and
# over. Confirmed still live on xlite AFTER 383a2d9 landed: the
# addons/gut/version_numbers.gd escalation got auto-skip-tagged again at
# 2026-09-17 17:24 (commit 28ca19a), 3.5h after the "fix". Apply the same
# exclusion here so cap-tracking follows the item the fleet is actually
# working on, not a stale terminal escalation note.
#
# 2026-09-28 FIX: "the item the fleet is actually working on" was still a LIE even after the
# above fix - a fresh top-of-file grep is only a PROXY for that, and the two can genuinely
# diverge (a line above flips done/skip mid-cycle, wording drifts, etc). Confirmed live on
# test-automation-agent: one item failed 8 times across 2 hours while this guard's own
# consecutive-fail counter stayed at 1 the whole time, because it kept hashing whatever
# unrelated item happened to be topmost that cycle instead of the one actually retried. Use
# the scout's own FILES: answer (recorded in $task_log, the same proven signal
# run_overnight.sh's OVN_SCOUT_FILES/cycle_summary.log already use) to find the REAL line
# when one is available; see scripts/lib_item_select.sh for the full root-cause writeup and
# the exact fallback semantics (identical to the old top-of-file-only behavior when there is
# no usable scout signal).
#
# (lib_item_select.sh, sourced above, provides both ovn_resolve_top_item() and the shared
# ovn_item_hash() this fix uses — the fail/no-op path below is unaffected by OVERNIGHT_PROGRESS.md
# mutation timing, since a fail/no-op cycle never checks anything off before this guard runs.)
if command -v ovn_resolve_top_item >/dev/null 2>&1; then
  top="$(ovn_resolve_top_item "$repo" "$task_log")"
else
  top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|\[CLAUDE\]' | grep -vE 'BLOCKED' | head -1)"
fi
if [ -n "$_stage_h" ]; then
  # bill the item the stage runner actually worked: the exact open line "- [ ] <stage-item-line>"; gone/edited/ticked => nothing to bill or park
  _sl="$(grep -nxF -- "- [ ] ${_stage_txt}" "$prog" 2>/dev/null | head -1 | cut -d: -f1)"
  [ -n "$_sl" ] || exit 0
  top="${_sl}:- [ ] ${_stage_txt}"
fi
[ -z "$top" ] && exit 0
lineno="${top%%:*}"
text="${top#*:}"
# 2026-10-02: schema/migration/model items get a larger fail + token budget (measured evidence in lib_item_select.sh ovn_schema_budget);
# every other item keeps CAP/NCAP/TOKCAP exactly as configured above. OVN_SCHEMA_BUDGET=off restores the single budget for all.
if command -v ovn_schema_budget >/dev/null 2>&1; then
  CAP="$(ovn_schema_budget failcap "$CAP" "$text")"
  NCAP="$(ovn_schema_budget noopcap "$NCAP" "$text")"
  TOKCAP="$(ovn_schema_budget tokcap "$TOKCAP" "$text")"
fi
# Feature-scoped streak key (2026-09-22, date-strip hardened 2026-09-28): a multi-line
# feature (e.g. an impl file + its paired test file, tagged with the same [feat:...] id)
# used to get a FRESH fail/no-op streak budget every time the "top" unchecked line flipped
# between its sibling sub-items, and a feat-tag regenerated with a new date used to reset
# the same underlying feature's streak too — see lib_item_select.sh's ovn_item_hash() for
# the full history; both fixes now live in that one shared function so every caller
# (this guard, run_overnight.sh's record_outcome()/lastfail lookup) agrees on identity.
if command -v ovn_item_hash >/dev/null 2>&1; then
  h="$(ovn_item_hash "$text")"
else
  featkey="$(printf '%s' "$text" | grep -oE '\[feat:[^]]+\]' | head -1)"
  if [ -n "$featkey" ]; then
    featkey="$(printf '%s' "$featkey" | sed -E 's/-[0-9]{8}-/-/; s/-[0-9]{6}-/-/')"
    h="$(printf '%s' "$featkey" | md5sum | cut -d' ' -f1)"
  else
    h="$(printf '%s' "$text" | md5sum | cut -d' ' -f1)"
  fi
fi

# Per-item state files (2026-09-29: keyed by (id, item_hash), not just id — see header note).
countf="$state/item_fails/${id}.${h}.count"; toksf="$state/item_fails/${id}.${h}.toks"
ncountf="$state/item_fails/${id}.${h}.noopcount"; ntoksf="$state/item_fails/${id}.${h}.nooptoks"
lastfailf="$state/item_fails/${id}.${h}.lastfail"

# --- Repeat circuit-breaker (2026-10-02, harness Y1) ---------------------------------------------------------
# The SAME failing test-id set on N=2 (OVN_REPEAT_BREAKER_N) consecutive attempts of the same item is a deterministic failure, not bad luck: more
# samples only burn GPU (iptv 'add last_event_ms column': ~9 attempts / 65 min / 0 landed, drift test red with the identical id each time). Two
# sources: (a) run_overnight.sh's inner best-of-N loop stopped on it and left a "repeat-breaker:" marker in the log; (b) across cycles, this guard
# remembers the previous cycle's failing-id key per item (state/item_fails/<id>.<hash>.lastids = "<key> <streak>"). On a trip the item is parked with
# the existing AUTO-SKIP tag, the note carrying "needs-human" + the repeated test ids. More than OVN_REPEAT_MAX_IDS (20) failing ids is a baseline /
# env break, never an item signal (ovn_repeat_key returns empty). OVN_REPEAT_BREAKER=off disables it.
lastidsf="$state/item_fails/${id}.${h}.lastids"
case "$status" in
  no-op\(BLOCKED\)|no-op\(ALREADY-DONE\)|no-op\(NEEDS-DECISION\)) : ;;
  *)
    if [ "${OVN_REPEAT_BREAKER:-on}" != off ] && command -v ovn_repeat_key >/dev/null 2>&1 && [ -n "$task_log" ] && [ -f "$task_log" ]; then
      _rk="$(ovn_repeat_key "$h" "$task_log" "$repo" "$state")"
      _rstreak=1
      if [ -n "$_rk" ]; then
        read -r _rprev _rps < "$lastidsf" 2>/dev/null || true
        _rstreak="$(ovn_repeat_streak "${_rprev:-}" "$_rk" "${_rps:-1}")"
        printf '%s %s' "$_rk" "$_rstreak" > "$lastidsf"
      else
        rm -f "$lastidsf" 2>/dev/null
      fi
      ovn_repeat_record "$repo" "$state" "$h" "$task_log"   # AFTER the key: "previous item" must mean the item before this one
      _rbasis="$(ovn_repeat_basis "$repo" "$state")"
      case "$_rbasis" in baseline) _rbasis="not red at the repo baseline";; *) _rbasis="not a repeat of the previous item's failures";; esac
      _rmark="$(grep -m1 'repeat-breaker: same failing tests' "$task_log" 2>/dev/null)"
      if [ -n "$_rmark" ] || { [ -n "$_rk" ] && [ "$_rstreak" -ge "${OVN_REPEAT_BREAKER_N:-2}" ]; }; then
        _rids="$(ovn_failing_ids "$task_log" | python3 "$(dirname "$0")/ovn_repeat_ids.py" filter "$(basename "$repo")" "$state" "$h" 2>/dev/null | head -3 | tr '\n' ' ' | sed 's/ *$//' | tr -d '#[]')"
        [ -z "$_rids" ] && _rids="$(printf '%s' "$_rmark" | sed -E 's/.*same item: //; s/ *-*$//' | tr -d '#[]')"
        branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        _ig_sedi "${lineno}s#^- \[ \] #- [ ] [AUTO-SKIP needs-human: the same failing tests repeated on ${OVN_REPEAT_BREAKER_N:-2} consecutive attempts (${_rids:0:140}) - a repeat of the same failing ids (${_rbasis}) - deterministic, not luck; review] #" "$prog"
        if ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
          git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
          git -C "$repo" commit -q -m "chore(queue): park item - same failing tests repeated on consecutive attempts (needs-human)" 2>/dev/null
          [ -n "$branch" ] && git -C "$repo" push -q origin "$branch" 2>/dev/null
          echo "AUTO-SKIPPED item (repeat circuit-breaker, needs-human): ${text:0:70}"
        fi
        rm -f "$state/failures/${id}.count" "$countf" "$toksf" "$ncountf" "$ntoksf" "$lastidsf" 2>/dev/null
        exit 0
      fi
    fi
    ;;
esac

# --- Tier-3 grounded failure memory (2026-09-16) ------------------------------
# Persist what THIS attempt actually did wrong (real log output, keyed to the
# CURRENT top item's hash) so run_overnight.sh's next cycle can tell the model what
# was already tried and failed instead of re-deriving the same investigation cold -
# root-caused live on shrike-notify's revoke_token() item: 25 cycles bounced between
# 4 different theories (scope.py, test file, auth.py service layer, schemas.py) with
# zero memory of what the last attempt broke. Never written for the cheap
# blocked/done/skip short-circuits below - there's no code-level evidence to ground a
# lesson in there, and Reflexion (arXiv:2303.11366) found ungrounded reflection can
# be WORSE than none.
case "$status" in
  no-op\(BLOCKED\)|no-op\(ALREADY-DONE\)|no-op\(NEEDS-DECISION\)) : ;;
  *)
    extractor="$(dirname "$0")/ovn_extract_failure.sh"
    if [ -x "$extractor" ] && [ -n "$task_log" ] && [ -f "$task_log" ]; then
      fsum="$(bash "$extractor" "$task_log" 2>/dev/null)"
      # 2026-10-09: the integrity gate (lib_fixup.sh) logs the exact lesson as '--- fixup-integrity: <text> ---'; it beats the generic failure extract
      case "$status" in
        "no-op(fixup-undid-item)"*|"reverted(test-item-touched-prod)"*)
          _fxi_txt="$(grep -a '^--- fixup-integrity: ' "$task_log" 2>/dev/null | tail -1 | sed -E 's/^--- fixup-integrity: //; s/ ---$//')"
          [ -n "$_fxi_txt" ] && fsum="$_fxi_txt" ;;
      esac
      [ -n "$fsum" ] && printf '%s|%s' "$h" "$fsum" > "$lastfailf"
    fi
    ;;
esac

# --- BUGS FIRST attempt cap + escalation (2026-10-02, branch qa/h8-bug-first) ---------------------------------------------------------
# A manual-test bug (Mark's hand-logged bug; see lib_item_select.sh) gets OVN_BUG_ATTEMPT_CAP (default 2) failed attempts - NOT the generic
# 3-4 cycles, and never the schema budget - and is then NEVER silently AUTO-SKIPped (that tag parks it where nobody looks, which is exactly how 3
# of 7 real Chickadee bugs sat as needs-human). Instead it is handed to a Claude fix session the same day, visibly:
#   1. every still-open line of the bug (the item + the sibling steps of its brief, same [feat:] tag) becomes '[CLAUDE] [bug-escalated: <reason>]'
#      (the loop already ignores [CLAUDE] items, so the lane moves on to the next bug / back to normal work);
#   2. one JSON line is appended to state/bug_escalations.jsonl (repo, note, item hash, attempts, last failure reason, brief location);
#   3. ONE low-priority relay note 'Manual bug escalated: <repo>' goes through the relay (buffered by the notification policy, never urgent).
# 2 and 3 happen at most once per item hash. An "attempt" is one fleet cycle, or one best-of-N try (run_overnight.sh passes OVN_GUARD_ATTEMPTS).
# Statuses where nothing was attempted (skip*/held*) do not count. Landings never reach this code (tests:pass exits above). Kill switch OVN_BUG_FIRST=off.
is_bug=0
# (needs the shared escalation helper too: without it the bug falls back to the generic caps rather than looping uncapped)
if command -v ovn_is_manual_bug_text >/dev/null 2>&1 && command -v ovn_bug_escalate >/dev/null 2>&1 && ovn_is_manual_bug_text "$text"; then is_bug=1; fi
if [ "$is_bug" = 1 ]; then
  case "$status" in skip*|held*) exit 0;; esac
  BUGCAP="${OVN_BUG_ATTEMPT_CAP:-2}"; case "$BUGCAP" in ''|*[!0-9]*|0) BUGCAP=2;; esac
  att="${OVN_GUARD_ATTEMPTS:-1}"; case "$att" in ''|*[!0-9]*|0) att=1;; esac; [ "$att" -gt 10 ] && att=10
  bcountf="$state/item_fails/${id}.${h}.bugcount"; btoksf="$state/item_fails/${id}.${h}.bugtoks"
  bc=$(( $(cat "$bcountf" 2>/dev/null || echo 0) + att ))
  bt=$(( $(cat "$btoksf" 2>/dev/null || echo 0) + cur_toks ))
  printf '%s' "$bc" > "$bcountf"; printf '%s' "$bt" > "$btoksf"
  if [ "$bc" -ge "$BUGCAP" ] || [ "$bt" -ge "$TOKCAP" ]; then
    why="${bc} failed attempts (cap ${BUGCAP})"
    [ "$bt" -ge "$TOKCAP" ] && [ "$bc" -lt "$BUGCAP" ] && why="${bt} tokens spent in ${bc} attempt(s) without a fix"
    # the tag / commit / escalation record / relay note live in lib_bug_escalate.sh, SHARED with ovn_stage_runner.sh (2026-10-02 review fix)
    ovn_bug_escalate "$repo" "$prog" "$lineno" "$text" "$h" "$id" "$bc" "$status" "$state" "$why"
    rm -f "$bcountf" "$btoksf" "$state/failures/${id}.count" 2>/dev/null
  fi
  exit 0
fi

# --- Ungrounded-plan sibling-group park (2026-10-04, h13) ------------------------------------------------------------------------------------
# no-op(ungrounded-plan) = the scout said PROCEED but named NO file (items whose path is '.' / 'tests', e.g. "[T4] . - Execute full test suite").
# Every sibling of the same [feat:...] group shares that shape, so parking ONE item per NCAP no-ops walked the group at ~25s a cycle each
# (xlite: 20 rows in 24h). After OVN_UNGROUNDED_GROUP_CAP (default 3) CONSECUTIVE ungrounded-plan hits for this feature, park every still-open
# sibling at once with the usual reversible AUTO-SKIP tag. Any other outcome for the feature resets the streak. An item without a [feat:] tag
# keeps the ordinary no-op streak below (there is no group to park).
ugf="$state/item_fails/${id}.${h}.ungrounded"
if [ "$status" = "no-op(ungrounded-plan)" ]; then
  ug=$(( $(cat "$ugf" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$ug" > "$ugf"
  _ugfeat="$(printf '%s' "$text" | grep -oE '\[feat:[^]]+\]' | head -1)"
  if [ "$ug" -ge "${OVN_UNGROUNDED_GROUP_CAP:-3}" ] && [ -n "$_ugfeat" ]; then
    _ugn="$(python3 - "$prog" "$_ugfeat" "$ug" "$text" <<'PYEOF'
import sys
path, feat, n = sys.argv[1], sys.argv[2], sys.argv[3]
marker = "[AUTO-SKIP ungrounded-plan x%s - scout names no file for this feature group; review] " % n
lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
tagged = 0
import re
# h13 review: park only siblings that THEMSELVES name no concrete file before their VERIFY ('.', 'tests', prose): a sibling with a real target file
# is not ungrounded, merely unlucky in three scouts - it keeps its place (the ordinary per-item caps still apply to it). The item whose scout just
# failed (matched by the full text) is always parked.
FILE = re.compile(r"[A-Za-z0-9_@-]+(/[A-Za-z0-9_.@\[\]-]+)*\.[A-Za-z][A-Za-z0-9]{0,7}\b|[A-Za-z0-9_@-]+/[A-Za-z0-9_.@-]+")
cur = re.sub(r"^- \[ \] ", "", sys.argv[4].strip())
def ungrounded_shape(ln):
    body = re.split(r"VERIFY:", ln, 1)[0]
    body = re.sub(r"\[feat:[^\]]*\]|\[T[1-5]\]|\{[^}]*\}", " ", body)
    return not FILE.search(body)
for i, ln in enumerate(lines):
    if ln.startswith("- [ ] ") and feat in ln and "AUTO-SKIP" not in ln and "[CLAUDE]" not in ln and (ln[len("- [ ] "):].strip() == cur.strip() or ungrounded_shape(ln)):
        lines[i] = "- [ ] " + marker + ln[len("- [ ] "):]
        tagged += 1
if tagged:
    open(path, "w", encoding="utf-8").write("\n".join(lines))
print(tagged)
PYEOF
)"
    if [ "${_ugn:-0}" -gt 0 ] 2>/dev/null; then
      branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
      if ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
        git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
        git -C "$repo" commit -q -m "chore(queue): park ${_ugn} sibling item(s) after ${ug} consecutive ungrounded-plan no-ops (${_ugfeat})" -- OVERNIGHT_PROGRESS.md 2>/dev/null
        [ -n "$branch" ] && git -C "$repo" push -q origin "$branch" 2>/dev/null
        echo "AUTO-SKIPPED ${_ugn} sibling item(s) of ${_ugfeat} after ${ug} consecutive ungrounded-plan no-ops: ${text:0:60}"
      fi
      rm -f "$ugf" "$ncountf" "$ntoksf" "$state/failures/${id}.count" 2>/dev/null
      exit 0
    fi
  fi
else
  rm -f "$ugf" 2>/dev/null
fi

# --- No-op streak: park an item that keeps doing nothing ---------------------
# Catch every "nothing landed, not a hard fail" shape: no-op(BLOCKED),
# no-op(ALREADY-DONE), a bare <none>, or an empty status (a PROCEED that emitted
# no diff). Reverts/errors deliberately fall through to the fail streak below.
# 2026-10-09 (harness-credit-integrity item 5): no-op(fixup-undid-item) = the fix-up undid the committed item and the runner reset it. That is a failed
# attempt (real model work thrown away), not a benign no-op: it counts toward the FAIL cap below (CAP), not the no-op streak (NCAP).
_ig_fixup_fail=0
case "$status" in "no-op(fixup-undid-item)"*) _ig_fixup_fail=1 ;; esac
if [ "$_ig_fixup_fail" = 0 ] && [[ "$status" == no-op* || "$status" == "<none>"* || -z "$status" ]]; then
  # indeterminate-credit allowance (see the tests:pass case above): an ALREADY-DONE no-op on an item whose landing could not be credited only because
  # its VERIFY timed out is expected; do not count it (bounded, then it counts like any other no-op).
  if [ "$status" = "no-op(ALREADY-DONE)" ] && [ -f "$state/item_fails/${id}.${h}.indet" ]; then
    _ia=$(( $(cat "$state/item_fails/${id}.${h}.indet" 2>/dev/null || echo 0) + 1 ))
    if [ "$_ia" -le "${OVN_INDET_NOOP_ALLOW:-3}" ]; then printf '%s' "$_ia" > "$state/item_fails/${id}.${h}.indet"; exit 0; fi
  fi
  nc=$(( $(cat "$ncountf" 2>/dev/null || echo 0) + 1 ))
  ntoks=$(( $(cat "$ntoksf" 2>/dev/null || echo 0) + cur_toks ))
  printf '%s' "$nc" > "$ncountf"
  printf '%s' "$ntoks" > "$ntoksf"
  if [ "$nc" -ge "$NCAP" ] || [ "$ntoks" -ge "$TOKCAP" ]; then
    trigger="${NCAP} no-op cycles"; [ "$ntoks" -ge "$TOKCAP" ] && [ "$nc" -lt "$NCAP" ] && trigger="${ntoks} tokens with no landing (only ${nc}/${NCAP} cycles — caught by spend, not attempt count)"
    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    # AUTO-SKIP is in the runner's doable-exclude grep, so this drops the item
    # from rotation while staying visible (unchecked) for a human/Claude to
    # verify-and-credit or fix the target.
    _ig_sedi "${lineno}s#^- \[ \] #- [ ] [AUTO-SKIP after ${trigger} — already-done, mis-targeted, or beyond the 27B; review] #" "$prog"
    if ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
      git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
      git -C "$repo" commit -q -m "chore(queue): auto-skip item after ${trigger} (already-done/mis-targeted)" 2>/dev/null
      [ -n "$branch" ] && git -C "$repo" push -q origin "$branch" 2>/dev/null
      echo "AUTO-SKIPPED no-op item after ${trigger}: ${text:0:70}"
    fi
    # parked -> reset the task-valve too so this streak doesn't also disable the task
    rm -f "$state/failures/${id}.count" "$ncountf" "$ntoksf" 2>/dev/null
  fi
  exit 0
fi

# --- Fail streak: park an item that keeps failing to land --------------------
c=$(( $(cat "$countf" 2>/dev/null || echo 0) + 1 ))
toks=$(( $(cat "$toksf" 2>/dev/null || echo 0) + cur_toks ))
printf '%s' "$c" > "$countf"
printf '%s' "$toks" > "$toksf"

if [ "$c" -ge "$CAP" ] || [ "$toks" -ge "$TOKCAP" ]; then
  trigger="${CAP} failed-to-land cycles"; [ "$toks" -ge "$TOKCAP" ] && [ "$c" -lt "$CAP" ] && trigger="${toks} tokens with no landing (only ${c}/${CAP} cycles — caught by spend, not attempt count)"
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # tag the item so the model skips it next cycle
  _ig_sedi "${lineno}s#^- \[ \] #- [ ] [AUTO-SKIP after ${trigger} — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] #" "$prog"
  if ! git -C "$repo" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
    git -C "$repo" add OVERNIGHT_PROGRESS.md 2>/dev/null
    git -C "$repo" commit -q -m "chore(queue): auto-skip item after ${trigger} (needs a human)" 2>/dev/null
    [ -n "$branch" ] && git -C "$repo" push -q origin "$branch" 2>/dev/null
    echo "AUTO-SKIPPED item after ${trigger}: ${text:0:70}"
  fi
  # bad item now parked -> give the REPO a fresh start: reset the task-valve
  # counter so this same streak doesn't also auto-disable the whole task.
  rm -f "$state/failures/${id}.count" 2>/dev/null
  rm -f "$countf" "$toksf" 2>/dev/null
fi
exit 0
