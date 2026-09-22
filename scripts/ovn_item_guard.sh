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
hashf="$state/item_fails/${id}.hash"; countf="$state/item_fails/${id}.count"; toksf="$state/item_fails/${id}.toks"
nhashf="$state/item_fails/${id}.noophash"; ncountf="$state/item_fails/${id}.noopcount"; ntoksf="$state/item_fails/${id}.nooptoks"
lastfailf="$state/item_fails/${id}.lastfail"

cur_toks=0
if [ -n "$task_log" ] && [ -f "$task_log" ]; then
  cur_toks="$(grep -oiE '[0-9.]+k? +sent' "$task_log" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"
  cur_toks="${cur_toks:-0}"
fi

# A clean landing clears BOTH streaks (fail and no-op) plus any grounded failure memory.
case "$status" in
  *"tests:pass"*) rm -f "$hashf" "$countf" "$toksf" "$nhashf" "$ncountf" "$ntoksf" "$lastfailf" 2>/dev/null; exit 0 ;;
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
top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | head -1)"
[ -z "$top" ] && exit 0
lineno="${top%%:*}"
text="${top#*:}"
# Feature-scoped streak key (2026-09-22): a multi-line feature (e.g. an impl file +
# its paired test file, tagged with the same [feat:...] id) used to get a FRESH
# fail/no-op streak budget every time the "top" unchecked line flipped between its
# sibling sub-items - each sub-item hashes to different raw text, so CAP/NCAP reset
# to 0 on every flip instead of accumulating. Root-caused live on shrike-notify's
# [feat:shrike-notify-20260921-wire-check-message-field-duplicates] pair: the
# backend/app/models.py line and the backend/tests/test_models.py line kept trading
# off as "top" across 9+ cycles / 160k+ tokens (both ultimately blocked by the same
# underlying bug - an `importlib.reload(app.models)` test call that poisons
# isinstance-based FastAPI exception-handler matching for the rest of the pytest
# session, confirmed by direct reproduction), and neither sub-item's streak alone
# ever reached the existing CAP=3/NCAP=4 before the OTHER sub-item became "top" and
# reset the clock. Hash the shared [feat:...] tag when present so all sub-items of
# one feature draw from the SAME budget; fall back to the old whole-line hash for
# untagged items (no behavior change there).
featkey="$(printf '%s' "$text" | grep -oE '\[feat:[^]]+\]' | head -1)"
if [ -n "$featkey" ]; then
  h="$(printf '%s' "$featkey" | md5sum | cut -d' ' -f1)"
else
  h="$(printf '%s' "$text" | md5sum | cut -d' ' -f1)"
fi

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
  nprev="$(cat "$nhashf" 2>/dev/null || echo '')"
  if [ "$h" = "$nprev" ]; then
    nc=$(( $(cat "$ncountf" 2>/dev/null || echo 0) + 1 ))
    ntoks=$(( $(cat "$ntoksf" 2>/dev/null || echo 0) + cur_toks ))
  else
    nc=1; printf '%s' "$h" > "$nhashf"
    ntoks="$cur_toks"
  fi
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
    rm -f "$state/failures/${id}.count" "$nhashf" "$ncountf" "$ntoksf" 2>/dev/null
  fi
  exit 0
fi

# --- Fail streak: park an item that keeps failing to land --------------------
prev="$(cat "$hashf" 2>/dev/null || echo '')"
if [ "$h" = "$prev" ]; then
  c=$(( $(cat "$countf" 2>/dev/null || echo 0) + 1 ))
  toks=$(( $(cat "$toksf" 2>/dev/null || echo 0) + cur_toks ))
else
  c=1; printf '%s' "$h" > "$hashf"
  toks="$cur_toks"
fi
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
  rm -f "$hashf" "$countf" "$toksf" 2>/dev/null
fi
exit 0
