#!/usr/bin/env bash
# Regression test: ovn_item_guard.sh's feature-scoped streak key must survive feat-tag
# CHURN across roadmap regenerations, not just group sibling sub-items under one live
# tag (2026-09-28).
#
# ovn_planner.sh mints a feat-tag as [feat:<repo>-<YYYYMMDD>-<slug>]. When the roadmap
# re-decomposes the SAME underlying stuck feature idea later, it gets a FRESH date (and
# often a slightly reworded slug) - before this fix, that meant the "same" stuck work was
# treated as a brand-new item with a reset streak instead of a continuation. Confirmed
# live on shrike-notify: one file got 3 different feat-tags across repeated regeneration,
# turning a single design ambiguity into 5-20 wasted cycles instead of being capped.
set -uo pipefail
G="${OVN_ITEM_GUARD:-$HOME/overnight-queue/scripts/ovn_item_guard.sh}"
[ -f "$G" ] || { echo "  SKIP: $G not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

new_repo(){  # $1=name $2=item-line -> echoes repo dir
  local r="$tmp/$1"; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  echo "$r"
}

# --- A: the SAME feature, regenerated with a NEW date each time, still accumulates one
#     shared streak instead of resetting on every regeneration ---
r="$(new_repo repoA '- [ ] [T2] {py} `backend/app/models.py` — fix the thing [feat:shrike-notify-20260921-wire-check-message-field-duplicates]')"
st="$tmp/stateA"; mkdir -p "$st"
bash "$G" "$r" "reverted(build-break)" "$st" itemA >/dev/null

# simulate a roadmap regeneration: same slug, new date
sed -i.bak 's/20260921/20260925/' "$r/OVERNIGHT_PROGRESS.md"
( cd "$r" && git add -A && git commit -q -m regen1 )
bash "$G" "$r" "reverted(build-break)" "$st" itemA >/dev/null

# a SECOND regeneration: new date again
sed -i.bak 's/20260925/20260928/' "$r/OVERNIGHT_PROGRESS.md"
( cd "$r" && git add -A && git commit -q -m regen2 )
bash "$G" "$r" "reverted(build-break)" "$st" itemA >/dev/null

ok "3 regenerations of the same slug (only the date changed) trip the cap (3), not reset to 1 each time" \
   "grep -q 'AUTO-SKIP after 3 failed-to-land cycles' '$r/OVERNIGHT_PROGRESS.md'"

# --- B: a GENUINELY different feature (different slug, not just a date bump) still gets
#     its OWN independent streak - this fix must not over-collapse unrelated features ---
r2="$(new_repo repoB '- [ ] [T2] {py} `backend/app/other.py` — unrelated feature [feat:shrike-notify-20260921-completely-different-feature]')"
st2="$tmp/stateB"; mkdir -p "$st2"
bash "$G" "$r2" "reverted(build-break)" "$st2" itemB >/dev/null
ok "a genuinely different feat-tag slug does not collapse into repoA's counter (separate state dirs anyway, but confirms independent hashing)" \
   "grep -q -- '- \[ \] \[T2\]' '$r2/OVERNIGHT_PROGRESS.md'"

# --- C: two lines sharing ONE live (non-churning) feat-tag still hash identically and
#     accumulate one shared streak - confirms the date-stripping change is a pure ADDITION
#     that does not disturb the base same-tag-accumulates behavior
#     (the ORIGINAL 2026-09-22 fix this must not regress) ---
r3="$tmp/repoC"; mkdir -p "$r3"
( cd "$r3" && git init -q && git config user.email t@t.com && git config user.name t \
  && printf '%s\n%s\n' \
    '- [ ] [T2] {py} `backend/app/models.py` — impl [feat:shrike-notify-20260921-shared-feature]' \
    '- [ ] [T2] {py} `backend/tests/test_models.py` — test [feat:shrike-notify-20260921-shared-feature]' \
    > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
st3="$tmp/stateC"; mkdir -p "$st3"
# both sub-items share the SAME feat-tag -> same key -> streak accumulates across flips
bash "$G" "$r3" "reverted(build-break)" "$st3" itemC >/dev/null
bash "$G" "$r3" "reverted(build-break)" "$st3" itemC >/dev/null
bash "$G" "$r3" "reverted(build-break)" "$st3" itemC >/dev/null
ok "sibling sub-items sharing one live feat-tag still accumulate one shared streak (no regression of the 2026-09-22 fix)" \
   "grep -q 'AUTO-SKIP after 3 failed-to-land cycles' '$r3/OVERNIGHT_PROGRESS.md'"

echo "Item-guard feat-tag churn: $P passed, $F failed"
[ "$F" -eq 0 ]
