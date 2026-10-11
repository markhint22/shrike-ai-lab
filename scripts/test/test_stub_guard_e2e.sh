#!/usr/bin/env bash
# test_stub_guard_e2e.sh - r11 package stub. The REAL run_aider_fix_task (hermetic fixture, stub aider) against the stub step's four defects:
#   X4/P1  a deleted path / an "asserts X does not exist" item is never re-created as a stub (red HEAD for hours on xlite)
#   P5/F2  'build.gradle.kts' never produces a committed junk 'build.gradle.kt'
#   (4)    nothing is stubbed under a directory AGENTS.md declares out of scope
#   (3)    an unfilled stub does not survive ANY early return (scout BLOCKED / ALREADY-DONE no-op / a reverted cycle / a landed cycle that left it empty);
#          a stub the implement step filled is kept
# Every guard has the kill switch the old behaviour comes back with (OVN_STUB_GUARDS=off, OVN_STUB_UNDO=off): the OFF cases below are the
# "fails on the old behaviour" proof and also pin the kill switches.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

stubs_in(){ git -C "$REPO" log --format=%s | grep -c "stub new source file"; }
# $1 = item line(s) appended as the top open item; history: scripts/old_mod.gd added then deleted; app/build.gradle.kts exists
setup_item(){
  ( cd "$REPO" && mkdir -p scripts app && echo 'extends Node' > scripts/old_mod.gd && echo 'plugins {}' > app/build.gradle.kts && git add -A && git commit -q -m "add old_mod + gradle" \
    && git rm -q scripts/old_mod.gd && git commit -q -m "remove old_mod" \
    && printf '# Progress\n\n## Next Steps\n%s\n- [ ] Tidy dead code in old.py\n\n## Completed\n' "$1" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m "queue" \
    && git push -q origin HEAD:claude/feature ) >/dev/null 2>&1
}
runit(){ OUT="$(run_aider_fix_task "ongoing-t" "$REPO" "$PROMPT_DEFAULT" claude/feature true "$TASK_LOG" "" false 2 "" 60 2>/dev/null | tail -1)"; }
exists_in_head(){ git -C "$REPO" cat-file -e "HEAD:$1" 2>/dev/null; }
placeholder_in_head(){ git -C "$REPO" show "HEAD:$1" 2>/dev/null | grep -q 'Placeholder - the implement step fills this in'; }

# ---------------------------------------------------------------- X4 / P1: deleted path + "asserts does not exist"
ITEM_X4='- [ ] [T2] tests/ - Create a test that asserts `scripts/old_mod.gd` does not exist'
mk_case x4
setup_item "$ITEM_X4"
scout_ok
OVN_STUB_UNDO=off runit   # undo disabled so these cases measure the GUARD alone (an undone stub would hide a missing guard)
eq "X4: no stub commit for a path git history shows was deleted" "$(stubs_in)" "0"
ok "X4: the deleted file is not back in HEAD" '! exists_in_head scripts/old_mod.gd'
ok "X4: the refusal is logged with its reason" 'grep -qF "stub-guard: NOT stubbing (deleted-in-history scripts/old_mod.gd)" "$TREE/logs/stub_guard.log"'

mk_case x4_off
setup_item "$ITEM_X4"
scout_ok
OVN_STUB_GUARDS=off OVN_STUB_UNDO=off runit
eq "X4 OLD BEHAVIOUR (OVN_STUB_GUARDS=off + OVN_STUB_UNDO=off = legacy extraction, no cleanup): the deleted file IS re-created as a stub" "$(stubs_in)" "1"

mk_case x4_never
setup_item '- [ ] [T2] tests/ - Create a test that asserts `scripts/ghost.gd` does not exist'
scout_ok
OVN_STUB_UNDO=off runit   # undo disabled so these cases measure the GUARD alone (an undone stub would hide a missing guard)
eq "X4: 'asserts X does not exist' for a never-existed path stubs nothing either" "$(stubs_in)" "0"
ok "X4: logged asserts-absent" 'grep -qF "asserts-absent scripts/ghost.gd" "$TREE/logs/stub_guard.log"'

mk_case x4_hist
setup_item '- [ ] [T2] scripts/old_mod.gd - Add a clamp01 helper.'
scout_ok
OVN_STUB_UNDO=off runit   # no does-not-exist wording here: ONLY the git-history guard can refuse this one
eq "X4: an item that just names a path deleted in history (no 'does not exist' wording) stubs nothing" "$(stubs_in)" "0"

# ---------------------------------------------------------------- P5 / F2: .kts is not .kt
ITEM_KTS='- [ ] [T2] app/build.gradle.kts - Add the signing config block.'
mk_case kts
setup_item "$ITEM_KTS"
scout_ok
OVN_STUB_UNDO=off runit   # undo disabled so these cases measure the GUARD alone (an undone stub would hide a missing guard)
eq "P5: an item naming build.gradle.kts commits no stub" "$(stubs_in)" "0"
ok "P5: no junk build.gradle.kt in HEAD" '! exists_in_head app/build.gradle.kt'
ok "P5: the real build.gradle.kts is untouched" 'exists_in_head app/build.gradle.kts'
mk_case kts_off
setup_item "$ITEM_KTS"
scout_ok
OVN_STUB_GUARDS=off OVN_STUB_UNDO=off runit
ok "P5 OLD BEHAVIOUR (kill switches off): the junk build.gradle.kt stub IS committed" 'exists_in_head app/build.gradle.kt && placeholder_in_head app/build.gradle.kt'

# ---------------------------------------------------------------- (4) AGENTS.md out of scope
mk_case oos
setup_item '- [ ] [T2] iptv-android/app/src/Foo.kt - Create the Foo class.'
( cd "$REPO" && printf '%s\n' '# AGENTS' '`iptv-ios/` and `iptv-android/` are **out of scope** — never edit them.' > AGENTS.md && git add -A && git commit -q -m agents && git push -q origin HEAD:claude/feature ) >/dev/null 2>&1
scout_ok
OVN_STUB_UNDO=off runit   # undo disabled so these cases measure the GUARD alone (an undone stub would hide a missing guard)
eq "F3: nothing is stubbed under an AGENTS.md out-of-scope directory" "$(stubs_in)" "0"
ok "F3: logged out-of-scope" 'grep -qF "out-of-scope:iptv-android" "$TREE/logs/stub_guard.log"'
mk_case oos_none
setup_item '- [ ] [T2] iptv-android/app/src/Foo.kt - Create the Foo class.'
scout_ok
OVN_STUB_UNDO=off runit
eq "F3 BENIGN: without an AGENTS.md the same item IS stubbed (guard only acts on a declared scope; undo disabled to observe it)" "$(stubs_in)" "1"

# ---------------------------------------------------------------- (3) the stub does not survive early returns
ITEM_NEW='- [ ] [T2] scripts/new_mod.gd - Create the new helper module.'
mk_case undo_blocked
setup_item "$ITEM_NEW"
aplan 1 'scout BLOCKED "needs a human decision" ""'
runit
case "$OUT" in no-op*) _blk=1;; *) _blk=0;; esac
ok "(3) scout BLOCKED returned a no-op status (got: $OUT)" '[ "$_blk" = 1 ]'
ok "(3) BLOCKED: the stub file is gone from the working tree" '[ ! -e "$REPO/scripts/new_mod.gd" ]'
ok "(3) BLOCKED: HEAD does not contain the stub" '! exists_in_head scripts/new_mod.gd'
eq "(3) BLOCKED: no stub commit survives in history" "$(stubs_in)" "0"
ok "(3) BLOCKED: the tree is clean" '[ -z "$(git -C "$REPO" status --porcelain)" ]'
ok "(3) BLOCKED: the undo is logged" 'logged "stub-guard: unfilled stub scripts/new_mod.gd dropped"'

mk_case undo_blocked_off
setup_item "$ITEM_NEW"
aplan 1 'scout BLOCKED "needs a human decision" ""'
OVN_STUB_UNDO=off runit
eq "(3) OLD BEHAVIOUR (OVN_STUB_UNDO=off): the stub commit SURVIVES the BLOCKED early return" "$(stubs_in)" "1"

mk_case undo_noop
setup_item "$ITEM_NEW"
scout_ok
aplan 2 'echo "I looked at it and need more information."'
aplan default 'echo "still nothing"'
runit
ok "(3) a no-change implement cycle ends without the stub (status: $OUT)" '[[ "$OUT" == no-op* ]] && [ ! -e "$REPO/scripts/new_mod.gd" ] && [ "$(stubs_in)" = 0 ]'

mk_case undo_filled
setup_item "$ITEM_NEW"
scout_ok
aplan 2 'printf "extends Node\n" > scripts/new_mod.gd; git add -A; git commit -q -m "feat: add new_mod

DONE: Create the new helper module"'
runit
ok "(3) a stub the implement step FILLED is kept (status: $OUT)" '[[ "$OUT" == pushed* ]] && [ "$(git -C "$REPO" show HEAD:scripts/new_mod.gd | head -1)" = "extends Node" ]'
ok "(3) filled: no drop commit" '! git -C "$REPO" log --format=%s | grep -q "drop unfilled stub"'

mk_case undo_landed_unfilled
setup_item "$ITEM_NEW"
scout_ok
aplan 2 'gc app.py "def h2(): return 2" "feat(app): other work

DONE: nothing about the new module"'
runit
ok "(3) a landed cycle that never filled the stub: other work kept (status: $OUT)" '[[ "$OUT" == pushed* ]] && git -C "$REPO" log --format=%s | grep -q "feat(app): other work"'
ok "(3) landed-unfilled: the placeholder file is removed from HEAD" '! exists_in_head scripts/new_mod.gd'
ok "(3) landed-unfilled: local is not left diverged (clean tree)" '[ -z "$(git -C "$REPO" status --porcelain)" ]'
ok "(3) landed-unfilled: origin does not keep the placeholder either (the removal was pushed fast-forward)" '! git -C "$ORIGIN" cat-file -e claude/feature:scripts/new_mod.gd'

# ---------------------------------------------------------------- helper absent = legacy extraction (partial deploy / minimal test tree, like every other guard)
mk_case helper_absent
setup_item '- [ ] [T2] scripts/new_mod.gd - Create the new helper module.'
scout_ok
mv "$TREE/scripts/ovn_stub_guard.py" "$TREE/scripts/ovn_stub_guard.py.off"
OVN_STUB_UNDO=off runit
mv "$TREE/scripts/ovn_stub_guard.py.off" "$TREE/scripts/ovn_stub_guard.py"
eq "helper script absent: the legacy extraction still stubs a plain create item (no crash, no silent loss of the stub trick)" "$(stubs_in)" "1"

summary
