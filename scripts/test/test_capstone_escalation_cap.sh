#!/usr/bin/env bash
# Regression test for ovn_stage_runner.sh's capstone escalation cap (2026-09-28).
#
# The templated "run the full suite once to confirm zero regressions" capstone fast-path is a
# single run-and-report, not a retry loop, so a capstone item whose VERIFY genuinely fails is
# correctly never hammered in a tight loop — but nothing ever advanced PAST it either. Because
# ovn_stage_sweep.sh invokes this script per-REPO (not per-item), the picker's `head -1` of
# doable T3-5 items re-selects the SAME stuck capstone item on every subsequent invocation
# forever, permanently starving every other doable T3-5 item behind it. Confirmed live on
# xlite: one capstone item looped capstone_regression_detected 22+ times over 7 hours.
#
# Fix: capstone_escalate_on_failure() caps consecutive detections per item (hash-keyed on the
# item text) and escalates to [CLAUDE] once the cap is hit, so the picker's own doable-item
# exclusion (extended to skip \[CLAUDE\] too) moves past it automatically.
#
# Extracts the real function out of ovn_stage_runner.sh so this can't silently drift from what's
# deployed.
set -uo pipefail
SR="${OVN_STAGE_RUNNER:-$HOME/overnight-queue/ovn_stage_runner.sh}"
[ -f "$SR" ] || { echo "  SKIP: $SR not found on this host"; exit 0; }

FN="$(sed -n '/^capstone_escalate_on_failure() {$/,/^}$/p' "$SR")"
[ -n "$FN" ] || { echo "  FAIL: could not extract capstone_escalate_on_failure() from $SR"; exit 1; }
if ! printf '%s' "$FN" | grep -qF '[CLAUDE]' || ! printf '%s' "$FN" | grep -qF 'capstone_fails'; then
  echo "  FAIL: extracted function doesn't look like the expected escalation cap:"; printf '%s\n' "$FN"; exit 1
fi
eval "$FN"

# The picker's own doable-item exclusion, extracted the same way — asserts the [CLAUDE] tag this
# function adds is ACTUALLY excluded by the picker, not just present in the file with nothing
# reading it.
PICKER_LINE="$(grep -E "^\s*_doable=" "$SR" | head -1)"
[ -n "$PICKER_LINE" ] || { echo "  FAIL: could not find the picker's _doable selector in $SR"; exit 1; }
if ! printf '%s' "$PICKER_LINE" | grep -qF '\[CLAUDE\]'; then
  echo "  FAIL: picker's doable-item selector does not exclude \\[CLAUDE\\]:"; echo "    $PICKER_LINE"; exit 1
fi

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ITEM='[T3] `godot` capstone — run the full suite once to confirm zero regressions. VERIFY: `true`'

new_repo(){  # $1=name -> echoes repo dir path, with OVERNIGHT_PROGRESS.md + origin/overnight/feature set up
  local bare="$tmp/$1.git" rd="$tmp/$1"
  git init -q --bare "$bare"
  git clone -q "$bare" "$rd" 2>/dev/null
  ( cd "$rd" && git config user.email t@t.com && git config user.name t \
    && printf -- '- [ ] %s\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init \
    && git branch -M overnight/feature && git push -q origin overnight/feature )
  git -C "$bare" symbolic-ref HEAD refs/heads/overnight/feature
  echo "$rd"
}

# --- A: below cap (default 2) — first detection does NOT escalate ---
rd="$(new_repo repoA)"
st="$tmp/stateA"
unset OVN_STAGE_CAPSTONE_CAP
out="$(capstone_escalate_on_failure "$rd" "$ITEM" repoA 3 testrun "$st")"; rc=$?
ok "1st detection: function returns non-zero (not yet escalated)" "[ $rc -ne 0 ]"
ok "1st detection: item is still plain unescalated (no [CLAUDE] tag)" \
   "! grep -q '\[CLAUDE\]' '$rd/OVERNIGHT_PROGRESS.md'"
ok "1st detection: count file records 1" "[ \"\$(cat '$st/stage_runs/capstone_fails/repoA__'*.count)\" = 1 ]"

# --- B: hitting the cap (2nd consecutive detection, same item) escalates to [CLAUDE] ---
out="$(capstone_escalate_on_failure "$rd" "$ITEM" repoA 3 testrun "$st")"; rc=$?
ok "2nd detection: function returns success (escalated)" "[ $rc -eq 0 ]"
ok "2nd detection: item is now tagged [CLAUDE]" "grep -q -- '- \[ \] \[CLAUDE\] ' '$rd/OVERNIGHT_PROGRESS.md'"
ok "2nd detection: escalation event emitted on stdout" "printf '%s' \"\$out\" | grep -q capstone_escalated"
ok "2nd detection: escalation was committed" "git -C '$rd' log --oneline -1 | grep -qi escalate"
ok "2nd detection: escalation reached origin (pushed)" \
   "git -C '$tmp/repoA.git' log --oneline overnight/feature | grep -qi escalate"
ok "2nd detection: count file cleared after escalation" "[ ! -f '$st/stage_runs/capstone_fails/repoA__'*.count ]"

# --- C: once escalated, the picker's own exclusion regex would skip the line ---
DOABLE_EXCL="$(printf '%s' "$PICKER_LINE" | grep -oE "grep -vE '[^']+'" | head -1 | sed -E "s/^grep -vE '//; s/'$//")"
ok "escalated line is excluded by the picker's own doable-item filter" \
   "! grep -E '^- \[ \] ' '$rd/OVERNIGHT_PROGRESS.md' | grep -vE \"$DOABLE_EXCL\" | grep -q ."

# --- D: a DIFFERENT item's counter is independent (hash-keyed on item text, not just repo) ---
rd2="$(new_repo repoB)"
st2="$tmp/stateB"
ITEM_A='[T3] `foo` capstone — run the full suite once to confirm zero regressions. VERIFY: `true`'
ITEM_B='[T3] `bar` capstone — run the full suite once to confirm zero regressions. VERIFY: `false`'
( cd "$rd2" && printf -- '- [ ] %s\n- [ ] %s\n' "$ITEM_A" "$ITEM_B" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m items && git push -q origin overnight/feature )
capstone_escalate_on_failure "$rd2" "$ITEM_A" repoB 3 testrun "$st2" >/dev/null
ok "item A's first detection creates exactly 1 counter file" \
   "[ \$(ls '$st2'/stage_runs/capstone_fails/repoB__*.count 2>/dev/null | wc -l) -eq 1 ]"
capstone_escalate_on_failure "$rd2" "$ITEM_B" repoB 3 testrun "$st2" >/dev/null
ok "item B's first detection creates a SECOND, independent counter file (different hash)" \
   "[ \$(ls '$st2'/stage_runs/capstone_fails/repoB__*.count 2>/dev/null | wc -l) -eq 2 ]"
capstone_escalate_on_failure "$rd2" "$ITEM_A" repoB 3 testrun "$st2" >/dev/null
ok "item A's 2nd detection escalates it to [CLAUDE]" \
   "grep -q -- '\[CLAUDE\].*foo' '$rd2/OVERNIGHT_PROGRESS.md'"
ok "item B (only 1 detection so far) is NOT escalated" \
   "! grep -q -- '\[CLAUDE\].*bar' '$rd2/OVERNIGHT_PROGRESS.md'"

# --- E: the cap threshold is configurable via OVN_STAGE_CAPSTONE_CAP ---
rd3="$(new_repo repoC)"
st3="$tmp/stateC"
OVN_STAGE_CAPSTONE_CAP=3 capstone_escalate_on_failure "$rd3" "$ITEM" repoC 3 testrun "$st3" >/dev/null; rc1=$?
OVN_STAGE_CAPSTONE_CAP=3 capstone_escalate_on_failure "$rd3" "$ITEM" repoC 3 testrun "$st3" >/dev/null; rc2=$?
OVN_STAGE_CAPSTONE_CAP=3 capstone_escalate_on_failure "$rd3" "$ITEM" repoC 3 testrun "$st3" >/dev/null; rc3=$?
ok "custom cap=3: 1st+2nd detections do not escalate" "[ $rc1 -ne 0 ] && [ $rc2 -ne 0 ]"
ok "custom cap=3: 3rd detection escalates" "[ $rc3 -eq 0 ]"
ok "custom cap=3: item now tagged [CLAUDE]" "grep -q -- '- \[ \] \[CLAUDE\] ' '$rd3/OVERNIGHT_PROGRESS.md'"

echo "Capstone escalation cap: $P passed, $F failed"
[ "$F" -eq 0 ]
