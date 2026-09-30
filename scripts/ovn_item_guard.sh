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
              "$state/item_fails/${id}.${_lh}.lastfail" 2>/dev/null
      done < <(grep -ohE 'item-hash [0-9a-f]{32}' "$task_log" 2>/dev/null | awk '{print $2}' | sort -u)
    fi
    exit 0
    ;;
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
  top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | head -1)"
fi
[ -z "$top" ] && exit 0
lineno="${top%%:*}"
text="${top#*:}"
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
      [ -n "$fsum" ] && printf '%s|%s' "$h" "$fsum" > "$lastfailf"
    fi
    ;;
esac

# --- No-op streak: park an item that keeps doing nothing ---------------------
# Catch every "nothing landed, not a hard fail" shape: no-op(BLOCKED),
# no-op(ALREADY-DONE), a bare <none>, or an empty status (a PROCEED that emitted
# no diff). Reverts/errors deliberately fall through to the fail streak below.
if [[ "$status" == no-op* || "$status" == "<none>"* || -z "$status" ]]; then
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
    sed -i "${lineno}s#^- \[ \] #- [ ] [AUTO-SKIP after ${trigger} — already-done, mis-targeted, or beyond the 27B; review] #" "$prog"
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
  sed -i "${lineno}s#^- \[ \] #- [ ] [AUTO-SKIP after ${trigger} — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] #" "$prog"
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
