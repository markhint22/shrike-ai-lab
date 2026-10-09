#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 5, review follow-up): END-TO-END wiring of the fix-up integrity gates through the REAL run_aider_fix_task
# (same hermetic fixture as test_run_integrity_e2e.sh / test_run_overnight_aider2_gates.sh). test_fixup_undid_item.sh proves the gate FUNCTIONS; this proves the
# call sites in run_overnight.sh actually run them with the right arguments and honour the returned status:
#   (a) Tier-2 fix-up that leaves no net diff on the item's target  => reset to BEFORE_SHA, status no-op(fixup-undid-item)   [enforced by default]
#       ... a fix-up with a real net diff is kept and the cycle lands;  OVN_FIXUP_UNDO_GUARD=off => the undo is NOT caught (control)
#   (b) item VERIFY fails after the fix-up: shadow (default) => logged '[fixup-verify-fail]', kept & landed; OVN_FIXUP_REVERIFY=enforce => reset
#   (c) the fix-up deletes a test function the main commit added: shadow => '[fixup-tests-lost]', kept; enforce => reset
#   (d) test item touching production code: shadow (default) => '[prod-touch]' in the status, kept; OVN_TESTONLY_GUARD=enforce => reverted(test-item-touched-prod)
# Every case has a benign control. Runs on the Mac (bash 5) and the box.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

# the model's commit changes app.py and tests/test_app.py; BEFORE ("init") is green, the model's commit leaves the suite red (tests/test_app.py::test_app)
eval "$(declare -f mk_case | sed '1s/mk_case/_mk_case_orig/')"
mk_case(){ _mk_case_orig "$@"; rm -rf "$TREE/state/nr_reverts" "$TREE"/state/baseline_fail_* "$TREE"/state/cycle_active_*; }
# setitem <progress line>: replace the Next Steps with ONE path-first item (the fixture's own items name no leading path) and publish it as BEFORE_SHA
setitem(){
  printf '# Progress\n\n## Next Steps\n%s\n- [ ] [T2] other.py — a later unrelated item. (cat:python)\n\n## Completed\n' "$1" > "$REPO/OVERNIGHT_PROGRESS.md"
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m "item" >/dev/null 2>&1
  git -C "$REPO" push -q -f origin HEAD:main >/dev/null 2>&1; git -C "$REPO" push -q -f origin HEAD:claude/feature >/dev/null 2>&1
}
before_sha(){ git -C "$REPO" rev-parse HEAD; }
RED_AFTER_MAIN='if [ "$(git log -1 --format=%s)" = "feat: hello2" ]; then echo "FAILED tests/test_app.py::test_app - assert 1 == 2"; echo "== 1 failed, 4 passed in 0.5s =="; exit 1; fi; echo "5 passed in 0.5s"; exit 0'
ITEM_APP='- [ ] [T2] app.py — Change `hello` to return 2. (cat:python)'
scout_app(){ aplan 1 'scout PROCEED "change hello in app.py" "app.py"'; }
# the model's work is ONE cycle with two commits; the last one carries the marker subject the verify snippets key on
main_commit(){ aplan 2 'gc tests/test_app.py "def test_hello2(): assert True" "test: hello2"; gc app.py "def hello2(): return 2" "feat: hello2"'; }
fix_failing(){ echo "tests/test_app.py::test_app - assert 1 == 2" > "$CASE_DIR/extract.out"; }

# ---------- (a) net-zero fix-up => reset + no-op(fixup-undid-item)
mk_case undo; setitem "$ITEM_APP"; B="$(before_sha)"
scout_app; main_commit
aplan 3 'git checkout -q HEAD~2 -- app.py tests/test_app.py; git add -A; git commit -q -m "fix: undo everything"'
vplan default "$RED_AFTER_MAIN"; fix_failing
run_case
eq "(a) net-zero fix-up => status no-op(fixup-undid-item)" "$OUT" "no-op(fixup-undid-item)"
ok "(a) tree reset to BEFORE_SHA" '[ "$(repo_head)" = "$B" ]'
ok "(a) nothing pushed" '! origin_has claude/feature "feat: hello2" && ! origin_has claude/feature "fix: undo everything"'
ok "(a) log carries the lastfail text the item guard reads" 'logged "fixup-integrity: fix-up reverted the item"'
ok "(a) alert says the fix-up undid the item" 'grep -q "fix-up undid the item" <<< "$ALERTS"'

# (a) control: the fix-up keeps a real net change => the cycle is NOT reset
mk_case undo_ctl; setitem "$ITEM_APP"; B="$(before_sha)"
scout_app; main_commit
aplan 3 'gc app.py "def hello3(): return 3" "fix: hello3"'
vplan default 'if [ "$(git log -1 --format=%s)" = "feat: hello2" ]; then echo "FAILED tests/test_app.py::test_app - assert 1 == 2"; echo "== 1 failed, 4 passed in 0.5s =="; exit 1; fi; echo "5 passed in 0.5s"; exit 0'; fix_failing
run_case
ok "(a) control: a fix-up with a real net diff is kept and the cycle lands (pushed)" '[[ "$OUT" == pushed* ]]'
ok "(a) control: the fix-up commit is on origin" 'origin_has claude/feature "fix: hello3"'
ok "(a) control: no integrity reset logged" '! logged "FIXUP-INTEGRITY"'

# (a) kill switch: with OVN_FIXUP_UNDO_GUARD=off the undo goes through (proves the status above comes from the gate, not from something else)
mk_case undo_off; setitem "$ITEM_APP"
scout_app; main_commit
aplan 3 'git checkout -q HEAD~2 -- app.py tests/test_app.py; git add -A; git commit -q -m "fix: undo everything"'
vplan default "$RED_AFTER_MAIN"; fix_failing
OVN_FIXUP_UNDO_GUARD=off run_case
ok "(a) OVN_FIXUP_UNDO_GUARD=off: the undo is not caught (status is not no-op(fixup-undid-item))" '[ "$OUT" != "no-op(fixup-undid-item)" ]'
unset OVN_FIXUP_UNDO_GUARD

# ---------- (a) BUILD-GATE call site: the build-break fix-up that simply undoes the item is reset too
BUILD_BREAK='if [ "$(git log -1 --format=%s)" = "feat: breaks build" ]; then echo "SyntaxError: invalid syntax (app.py, line 3)"; exit 1; fi; echo "5 passed in 0.5s"; exit 0'
mk_case bg_undo; setitem "$ITEM_APP"; B="$(before_sha)"
scout_app
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'git checkout -q HEAD~1 -- app.py; git add -A; git commit -q -m "fix: undo"'
vplan default "$BUILD_BREAK"
run_case
eq "(a) BUILD-GATE: a fix-up that undoes the item => no-op(fixup-undid-item)" "$OUT" "no-op(fixup-undid-item)"
ok "(a) BUILD-GATE: the gate that fired is the build-gate call site (re-verify logged, then the integrity reset)" 'logged "BUILD-GATE fix-up re-verify: pass" && logged "FIXUP-INTEGRITY (buildgate)"'
ok "(a) BUILD-GATE: tree reset to BEFORE_SHA" '[ "$(repo_head)" = "$B" ]'
mk_case bg_keep; setitem "$ITEM_APP"
scout_app
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'gc app.py "def fixed(): return 2" "fix: repaired"'
vplan default "$BUILD_BREAK"
run_case
ok "(a) BUILD-GATE control: a fix-up that really repairs the build (net diff on the target) is kept and lands" '[[ "$OUT" == pushed* ]] && origin_has claude/feature "fix: repaired"'

# ---------- (b) the item's own VERIFY fails after the fix-up: shadow keeps (logged), enforce resets
ITEM_VER='- [ ] [T2] app.py — Change `hello` to return 2. (cat:python) VERIFY: `exit 1`'
mk_case verify_shadow; setitem "$ITEM_VER"
scout_app; main_commit
aplan 3 'gc app.py "def hello3(): return 3" "fix: hello3"'
vplan default "$RED_AFTER_MAIN"; fix_failing
run_case
ok "(b) shadow (default): the failing item VERIFY is logged as [fixup-verify-fail]" 'logged "[fixup-verify-fail] (tier2, mode=shadow)"'
ok "(b) shadow: NOT reset - the fix-up commit stays on the branch" '[ "$(git -C "$REPO" log -1 --format=%s)" != init ] && git -C "$REPO" log --format=%s | grep -qF "fix: hello3"'
ok "(b) shadow: the status is not the integrity status" '[ "$OUT" != "no-op(fixup-undid-item)" ]'
ok "(b) shadow: an info alert is written" 'grep -q "fixup-verify-fail" <<< "$ALERTS"'
mk_case verify_enforce; setitem "$ITEM_VER"; B="$(before_sha)"
scout_app; main_commit
aplan 3 'gc app.py "def hello3(): return 3" "fix: hello3"'
vplan default "$RED_AFTER_MAIN"; fix_failing
OVN_FIXUP_REVERIFY=enforce run_case
eq "(b) enforce: status no-op(fixup-undid-item)" "$OUT" "no-op(fixup-undid-item)"
ok "(b) enforce: tree reset to BEFORE_SHA" '[ "$(repo_head)" = "$B" ]'
unset OVN_FIXUP_REVERIFY

# ---------- (c) the fix-up removes a test the main commit added
mk_case lost_shadow; setitem "$ITEM_APP"; B="$(before_sha)"
scout_app; main_commit
aplan 3 'git checkout -q HEAD~2 -- tests/test_app.py; gc app.py "def hello3(): return 3" "fix: hello3"'
vplan default "$RED_AFTER_MAIN"; fix_failing
run_case
ok "(c) shadow (default): the lost test is logged as [fixup-tests-lost]" 'logged "[fixup-tests-lost] (tier2, mode=shadow)" && logged "tests/test_app.py::test_hello2"'
ok "(c) shadow: kept (fix-up commit not reset away)" 'git -C "$REPO" log --format=%s | grep -qF "fix: hello3"'
mk_case lost_enforce; setitem "$ITEM_APP"; B="$(before_sha)"
scout_app; main_commit
aplan 3 'git checkout -q HEAD~2 -- tests/test_app.py; gc app.py "def hello3(): return 3" "fix: hello3"'
vplan default "$RED_AFTER_MAIN"; fix_failing
OVN_FIXUP_REVERIFY=enforce run_case
eq "(c) enforce: status no-op(fixup-undid-item)" "$OUT" "no-op(fixup-undid-item)"
ok "(c) enforce: tree reset to BEFORE_SHA" '[ "$(repo_head)" = "$B" ]'
unset OVN_FIXUP_REVERIFY

# ---------- (d) test-only guard: a test item that also rewrote production code
ITEM_TEST='- [ ] [T2] tests/test_app.py — Add a test for the hello endpoint. (cat:test)'
mk_case toguard_shadow; setitem "$ITEM_TEST"
aplan 1 'scout PROCEED "add a test" "tests/test_app.py"'
aplan 2 'gc tests/test_app.py "def test_hello(): assert True" "test: hello"; gc app.py "def rate_limit(): return 429" "feat: rewrote prod"'
vplan default 'echo "5 passed in 0.5s"; exit 0'
run_case
ok "(d) shadow (default): the status carries [prod-touch] and the cycle still lands" '[[ "$OUT" == pushed* ]] && [[ "$OUT" == *"[prod-touch]"* ]]'
ok "(d) shadow: logged + alerted" 'logged "[prod-touch] (mode=shadow)" && grep -q "prod-touch" <<< "$ALERTS"'
mk_case toguard_enforce; setitem "$ITEM_TEST"; B="$(before_sha)"
aplan 1 'scout PROCEED "add a test" "tests/test_app.py"'
aplan 2 'gc tests/test_app.py "def test_hello(): assert True" "test: hello"; gc app.py "def rate_limit(): return 429" "feat: rewrote prod"'
vplan default 'echo "5 passed in 0.5s"; exit 0'
OVN_TESTONLY_GUARD=enforce run_case
eq "(d) enforce: status reverted(test-item-touched-prod)" "$OUT" "reverted(test-item-touched-prod)"
ok "(d) enforce: tree reset to BEFORE_SHA and nothing pushed" '[ "$(repo_head)" = "$B" ] && ! origin_has claude/feature "feat: rewrote prod"'
unset OVN_TESTONLY_GUARD
# (d) benign control: a test item that only changes tests lands untagged, even in enforce mode
mk_case toguard_ok; setitem "$ITEM_TEST"
aplan 1 'scout PROCEED "add a test" "tests/test_app.py"'
aplan 2 'gc tests/test_app.py "def test_hello(): assert True" "test: hello"'
vplan default 'echo "5 passed in 0.5s"; exit 0'
OVN_TESTONLY_GUARD=enforce run_case
ok "(d) control: a tests-only change by a test item lands with no [prod-touch] (enforce mode)" '[[ "$OUT" == pushed* ]] && [[ "$OUT" != *"[prod-touch]"* ]]'
unset OVN_TESTONLY_GUARD

summary
