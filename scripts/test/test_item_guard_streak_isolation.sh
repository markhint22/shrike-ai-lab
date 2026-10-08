#!/usr/bin/env bash
# Regression test: ovn_item_guard.sh's fail/no-op streaks must be keyed per (id, item_hash),
# not per id alone (2026-09-29).
#
# Real gap this closes: every streak file used to be a SINGLE SLOT keyed only by the generic
# repo-task-id (e.g. "ongoing-billwatch") — not by which specific item was actually stuck. A
# clean landing unconditionally wiped that one slot regardless of which item hash it belonged
# to. Confirmed live on billwatch: a stuck feature (3 sub-items sharing one [feat:...] tag)
# burned 7 reverts over ~3.5h and ~660k tokens before finally hitting the expensive
# token-spend cap, because 6 unrelated, successful landings elsewhere in the SAME repo each
# reset the shared slot back to 0 before the cheap CAP=3/NCAP=4 cycle-count caps ever got a
# real chance to fire.
#
# Landings are now identified via an "item-hash <md5>" marker line in $task_log, written by
# run_overnight.sh at the exact moment it checks an item off (see that file's 2026-09-29
# comment at the marker-emission site, and ovn_item_guard.sh's own header comment for why a
# fresh top-of-file re-read can't identify the landed item itself: by the time this guard
# runs on a landing, that item's checkbox is already flipped to "- [x] ").
set -uo pipefail
G="${OVN_ITEM_GUARD:-$HOME/overnight-queue/scripts/ovn_item_guard.sh}"
[ -f "$G" ] || { echo "  SKIP: $G not found on this host"; exit 0; }
_lib="$(dirname "$G")/lib_item_select.sh"
[ -f "$_lib" ] || { echo "  SKIP: $_lib not found on this host"; exit 0; }
# shellcheck source=/dev/null
. "$_lib"
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mklog(){  # $1=name $2=filename-named-in-the-scout-signal
  local f="$tmp/log_$1.log"
  { echo "VERDICT: PROCEED"; echo "FILES: $2"; } > "$f"
  echo "$f"
}
landing_log(){  # $1=name $2=item-line-that-landed -> a task_log carrying the landed hash marker
  local f="$tmp/landing_$1.log" h
  h="$(ovn_item_hash "$2")"
  printf -- '--- auto-credit: item-hash %s ---\n' "$h" > "$f"
  echo "$f"
}

new_repo(){  # $1=name $2.. = item lines -> echoes repo dir
  local n="$1"; shift
  local r="$tmp/$n"; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && printf '%s\n' "$@" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  echo "$r"
}

# --- Scenario 1: item A fails 3x while item B lands once in between - A's streak must NOT
#     reset from B's unrelated landing, and must still trip the cap at the same point (the
#     3rd fail) it would have if nothing else had ever landed. ---
lineA='- [ ] [T2] {py} `backend/app/a.py` — fix thing A'
lineB='- [ ] [T2] {py} `backend/app/b.py` — fix thing B'
r="$(new_repo scen1 "$lineA" "$lineB")"
st="$tmp/state1"; mkdir -p "$st"

# A fails once.
bash "$G" "$r" "reverted(build-break)" "$st" itemX "$(mklog s1a1 backend/app/a.py)" >/dev/null
# B lands (unrelated item, different hash) - must not touch A's streak.
bash "$G" "$r" "pushed(tests:pass)" "$st" itemX "$(landing_log s1b "$lineB")" >/dev/null
# A fails a 2nd time - if B's landing had wrongly reset A, this would still read as A's 1st fail.
bash "$G" "$r" "reverted(build-break)" "$st" itemX "$(mklog s1a2 backend/app/a.py)" >/dev/null
ok "A is not yet capped after only 2 real fails (B's landing didn't inflate or deflate A's count)" \
   "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
# A fails a 3rd time - CAP=3 must trip now, exactly as it would have with no B activity at all.
bash "$G" "$r" "reverted(build-break)" "$st" itemX "$(mklog s1a3 backend/app/a.py)" >/dev/null
ok "A trips the cap on its 3rd real fail, unaffected by B's unrelated landing in between" \
   "grep -q 'AUTO-SKIP after 3 failed-to-land cycles' '$r/OVERNIGHT_PROGRESS.md'"
ok "B's own line was never touched/tagged by A's cap" \
   "grep -F 'fix thing B' '$r/OVERNIGHT_PROGRESS.md' | grep -qv AUTO-SKIP"

# --- Scenario 2 (must still work): item A's OWN landing DOES correctly clear item A's own
#     streak - this fix must not disable legitimate self-recovery. ---
r2="$(new_repo scen2 "$lineA")"
st2="$tmp/state2"; mkdir -p "$st2"
bash "$G" "$r2" "reverted(build-break)" "$st2" itemY "$(mklog s2a1 backend/app/a.py)" >/dev/null
bash "$G" "$r2" "reverted(build-break)" "$st2" itemY "$(mklog s2a2 backend/app/a.py)" >/dev/null
ok "A has a 2-fail streak recorded before it lands" \
   "ls '$st2'/item_fails/itemY.*.count >/dev/null 2>&1"
# A itself lands.
bash "$G" "$r2" "pushed(tests:pass)" "$st2" itemY "$(landing_log s2land "$lineA")" >/dev/null
ok "A's own landing clears its own fail-streak file" \
   "! ls '$st2'/item_fails/itemY.*.count >/dev/null 2>&1"
# ovn_item_guard.sh never flips the checkbox itself (that's run_overnight.sh's job, well
# before this guard runs) so the line is still open here - simulate a regression by failing
# it again and confirm the streak starts fresh at 1, not a leftover 3 (no immediate cap).
bash "$G" "$r2" "reverted(build-break)" "$st2" itemY "$(mklog s2a3 backend/app/a.py)" >/dev/null
ok "a fresh fail after A's own landing starts the streak at 1, not a leftover 3 (no immediate cap)" \
   "! grep -q 'AUTO-SKIP' '$r2/OVERNIGHT_PROGRESS.md'"

echo "Item-guard streak isolation (per-item state, not per-id): $P passed, $F failed"
[ "$F" -eq 0 ]
