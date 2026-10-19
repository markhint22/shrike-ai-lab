#!/usr/bin/env bash
# 2026-10-18 (xlite reverted(build-break) x2, 21:32Z / 22:04Z): END-TO-END through the REAL run_aider_fix_task (same hermetic fixture as test_fixup_gates_e2e.sh).
#
# Live defect replayed. The 27B "deleted dead TurnManager helpers" and removed get_phase_name() while get_phase_summary() still called it. The BUILD-GATE fix-up "restored" it,
# aider's udiff applied the restore hunk at TWO places (the function ended up defined twice = compile error), the re-verify failed on a different message, and the cycle was
# reverted after ~45 min of GUT runs (reverted commit 0551207: get_phase_name at line 61 AND line 146). Two causes, two fixes, each proven here with a mutant:
#   (A) ovn_fixup_dedupe_defs: a byte-identical duplicate introduced by the fix-up is removed before the re-verify.   mutant: OVN_FIXUP_DEDUPE=off => reverted(build-break)
#   (B) ovn_dangling_refs.py: the fix-up prompt names EVERY deleted-but-still-called function with its deleted source.  mutant: OVN_DANGLING_REFS=off => no such text
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

eval "$(declare -f mk_case | sed '1s/mk_case/_mk_case_orig/')"
mk_case(){ _mk_case_orig "$@"; rm -rf "${TREE:?}/state/nr_reverts" "${TREE:?}"/state/baseline_fail_* "${TREE:?}"/state/cycle_active_*; }
# setitem <progress line> [extra shell run in the repo before publishing BEFORE_SHA]
setitem(){
  printf '# Progress\n\n## Next Steps\n%s\n- [ ] [T2] other.py — a later unrelated item. (cat:python)\n\n## Completed\n' "$1" > "$REPO/OVERNIGHT_PROGRESS.md"
  [ -n "${2:-}" ] && ( cd "$REPO" && eval "$2" )
  git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -q -m "item" >/dev/null 2>&1
  git -C "$REPO" push -q -f origin HEAD:main >/dev/null 2>&1; git -C "$REPO" push -q -f origin HEAD:claude/feature >/dev/null 2>&1
}
ITEM_APP='- [ ] [T2] app.py — Change `hello` to return 2. (cat:python)'
scout_app(){ aplan 1 'scout PROCEED "change hello in app.py" "app.py"'; }
# verify: the breaking commit fails with a structural (SyntaxError) message; a file that defines `restored` twice is also a structural error (the Godot "duplicate function" shape)
V_DUP='s="$(git log -1 --format=%s)"
if [ "$s" = "feat: breaks build" ]; then echo "SyntaxError: invalid syntax (app.py, line 3)"; exit 1; fi
if [ "$(grep -c "^def restored" app.py)" -ge 2 ]; then echo "SyntaxError: duplicate definition of restored (app.py)"; exit 1; fi
echo "5 passed in 0.5s"; exit 0'

echo "== A: the fix-up's duplicated restore hunk is de-duplicated before the re-verify"
mk_case dup_on; setitem "$ITEM_APP"; B="$(git -C "$REPO" rev-parse HEAD)"
scout_app
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'printf "def restored():\n    return 1\n\ndef restored():\n    return 1\n" > app.py; git add -A; git commit -q -m "fix: restore"'
vplan default "$V_DUP"
run_case
ok "A1: the cycle lands (pushed) instead of reverting" '[[ "$OUT" == pushed* ]]'
ok "A2: the log says the fix-up introduced a duplicate that was removed" 'logged "BUILD-GATE fix-up introduced duplicate definition(s), removed: app.py: removed duplicate(s): restored"'
ok "A3: exactly one definition survives on origin" '[ "$(git -C "$ORIGIN" show claude/feature:app.py | grep -c "^def restored")" = 1 ]'
ok "A4: the dedupe commit is on origin" 'origin_has claude/feature "auto-remove duplicate definition(s) a fix-up introduced"'
ok "A5: re-verify passed" 'logged "BUILD-GATE fix-up re-verify: pass"'

mk_case dup_off; setitem "$ITEM_APP"; B="$(git -C "$REPO" rev-parse HEAD)"
scout_app
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'printf "def restored():\n    return 1\n\ndef restored():\n    return 1\n" > app.py; git add -A; git commit -q -m "fix: restore"'
vplan default "$V_DUP"
OVN_FIXUP_DEDUPE=off run_case
eq "A6 MUTANT (OVN_FIXUP_DEDUPE=off = the old behaviour): the same cycle is reverted(build-break)" "$OUT" "reverted(build-break)"
ok "A7 MUTANT: tree reset to BEFORE_SHA, nothing pushed" '[ "$(repo_head)" = "$B" ] && ! origin_has claude/feature "fix: restore"'
unset OVN_FIXUP_DEDUPE

# control: a fix-up that does NOT duplicate is untouched (no dedupe commit, no log line)
mk_case dup_ctl; setitem "$ITEM_APP"
scout_app
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'printf "def restored():\n    return 1\n" > app.py; git add -A; git commit -q -m "fix: restore"'
vplan default "$V_DUP"
run_case
ok "A8 control: a clean fix-up lands" '[[ "$OUT" == pushed* ]] && origin_has claude/feature "fix: restore"'
ok "A9 control: no dedupe commit and no duplicate log line" '! origin_has claude/feature "auto-remove duplicate" && ! logged "introduced duplicate definition"'

echo "== B: the fix-up prompt lists every deleted-but-still-called function, with its deleted source"
setup_dangling(){   # BEFORE_SHA: lib.py defines two helpers, app.py calls both
  printf 'def gone_one():\n    return 1\n\ndef gone_two(x):\n    return x + 2\n\ndef kept():\n    return 0\n' > lib.py
  printf 'from lib import gone_one, gone_two\n\ndef hello():\n    return gone_one() + gone_two(1)\n' > app.py
}
V_DANG='s="$(git log -1 --format=%s)"
if [ "$s" = "feat: breaks build" ]; then echo "SyntaxError: gone_one is not defined (app.py, line 4)"; exit 1; fi
echo "5 passed in 0.5s"; exit 0'
mk_case dang_on; setitem "$ITEM_APP" "$(declare -f setup_dangling); setup_dangling"
scout_app
aplan 2 'printf "def kept():\n    return 0\n" > lib.py; git add -A; git commit -q -m "feat: breaks build"'
aplan 3 'printf "def gone_one():\n    return 1\n\ndef gone_two(x):\n    return x + 2\n\ndef kept():\n    return 0\n" > lib.py; git add -A; git commit -q -m "fix: restore both"'
vplan default "$V_DANG"
run_case
ARGS3="$(cat "$CASE_DIR/aider.args.3" 2>/dev/null)"
ok "B1: the fix-up call ran (3rd aider call)" '[ -s "$CASE_DIR/aider.args.3" ]'
ok "B2: prompt says functions were DELETED and are still called" 'grep -qF "DELETED function(s) that are still called" <<< "$ARGS3"'
ok "B3: BOTH names are listed (not just the first)" 'grep -qE "^DANGLING.gone_one" <<< "$ARGS3" && grep -qE "^DANGLING.gone_two" <<< "$ARGS3"'
ok "B4: the deleted definition source is in the prompt" 'grep -qF "def gone_two(x):" <<< "$ARGS3" && grep -qF "return x + 2" <<< "$ARGS3"'
ok "B5: the caller file (app.py:4) is pulled into the chat as an editable file" 'grep -qx "app.py" "$CASE_DIR/aider.args.3"'
ok "B6: the log names the dangling functions" 'logged "BUILD-GATE: deleted function(s) still called: gone_one gone_two"'
ok "B7: the cycle lands after the restore" '[[ "$OUT" == pushed* ]]'

mk_case dang_off; setitem "$ITEM_APP" "$(declare -f setup_dangling); setup_dangling"
scout_app
aplan 2 'printf "def kept():\n    return 0\n" > lib.py; git add -A; git commit -q -m "feat: breaks build"'
aplan 3 'printf "def gone_one():\n    return 1\n\ndef gone_two(x):\n    return x + 2\n\ndef kept():\n    return 0\n" > lib.py; git add -A; git commit -q -m "fix: restore both"'
vplan default "$V_DANG"
OVN_DANGLING_REFS=off run_case
ARGS3="$(cat "$CASE_DIR/aider.args.3" 2>/dev/null)"
ok "B8 MUTANT (OVN_DANGLING_REFS=off = the old prompt): no DANGLING text reaches the model" '! grep -qF "DELETED function(s)" <<< "$ARGS3" && ! grep -qE "^DANGLING" <<< "$ARGS3"'
unset OVN_DANGLING_REFS

# control: a deletion whose caller was deleted too is NOT dangling (no false alarm in the prompt)
mk_case dang_none; setitem "$ITEM_APP" "$(declare -f setup_dangling); setup_dangling"
scout_app
aplan 2 'printf "def kept():\n    return 0\n" > lib.py; printf "def hello():\n    return 0\n\ndef broken(:\n" > app.py; git add -A; git commit -q -m "feat: breaks build"'
aplan 3 'printf "def hello():\n    return 0\n" > app.py; git add -A; git commit -q -m "fix: syntax"'
vplan default "$V_DANG"
run_case
ARGS3="$(cat "$CASE_DIR/aider.args.3" 2>/dev/null)"
ok "B9 control: callers deleted together with the callee => no DANGLING text" '! grep -qF "DELETED function(s)" <<< "$ARGS3"'

summary
