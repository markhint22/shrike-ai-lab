#!/usr/bin/env bash
# xlite-night F7 (2026-10-13): a `Create <test file>` item whose target ALREADY exists with its test functions is decided deterministically, before the scout / implement step.
#
# Live defect replayed (xlite, logs/20261013-014119/ongoing-xlite.log): the scout answered `PROCEED PLAN: Create tests/test_orphan_save_manager.gd` for an item whose file already existed
# (a255bdd); its siblings answered ALREADY-DONE. The implement step APPENDED a second `extends GutTest` plus both functions (1d98f79), the build-gate fix-up removed them, the cycle ended
# no-op(fixup-undid-item): 395s, 145k tokens. run_overnight.sh now asks scripts/ovn_stage_guards.py create-exists first (OVN_CREATE_EXISTS=off|shadow|on, default shadow).
# Drives the REAL run_aider_fix_task in the hermetic Linux fixture (box-only); the decision logic itself is unit-tested in test_stage_guards.py.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$(uname)" != Linux ]; then echo "  SKIP: box-only (the hermetic run_overnight.sh fixture needs the Linux runtime); run on the box"; exit 0; fi
. "$HERE/lib_ro_aider2_fixture.sh"
run_id(){ local id="$1" prompt="${2:-$PROMPT_DEFAULT}"
  : > "$TREE/state/alerts.log"
  OUT="$(run_aider_fix_task "$id" "$REPO" "$prompt" claude/feature false "$TASK_LOG" "" false 2 "" 60 2>/dev/null | tail -1)"
  LOGTXT="$(cat "$TASK_LOG" 2>/dev/null)"; }
set_prog(){ ( cd "$OTHER" && printf '# Progress\n\n## Next Steps\n%s\n- [ ] [T2] other.py — second item\n\n## Completed\n' "$1" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m "prog" && git push -q origin main && git push -q -f origin main:claude/feature \
    && cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1; }
aider_calls(){ cat "$CASE_DIR/aider.n" 2>/dev/null || echo 0; }
# fixed-string membership without `x | grep -q` (pipefail + early-exit grep = SIGPIPE flake): capture first, then match
prog_has(){ local t; t="$(git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md 2>/dev/null)"; case "$t" in *"$1"*) return 0;; esac; return 1; }
log_has(){ local t; t="$(git -C "$REPO" log --format=%s 2>/dev/null)"; case "$t" in *"$1"*) return 0;; esac; return 1; }
# the fixture's tests/test_app.py only has test_app(): give it the function / asserted call the items below name (committed on origin like the progress file)
add_test_fn(){ ( cd "$OTHER" && printf '\n\ndef test_hello_returns_one():\n    assert hello(41) == 42\n' >> tests/test_app.py && git add -A && git commit -q -m "tests" && git push -q origin main && git push -q -f origin main:claude/feature \
    && cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1; }
CE_OK='- [ ] [T1] tests/test_app.py — Create test test_hello_returns_one that asserts `hello` in app.py returns 1. VERIFY: `grep -q hello app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-app-test]'
CE_CALL='- [ ] [T1] tests/test_app.py — Create a test file that asserts `hello(41) == 42`. VERIFY: `grep -q hello app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-app-test]'
CE_UNNAMED='- [ ] [T1] tests/test_app.py — Add a test case verifying that `hello` returns 1 when called with 41. VERIFY: `grep -q hello app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-app-test]'
CE_VFAIL='- [ ] [T1] tests/test_app.py — Create test test_hello_returns_one that asserts `hello` in app.py returns 1. VERIFY: `grep -q zzz_not_there app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-app-test]'
CE_NAMED_MISSING='- [ ] [T1] tests/test_app.py — Create test_app and test_never_written for `hello`. VERIFY: `grep -q hello app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-app-test]'
CE_NEWFILE='- [ ] [T1] tests/test_brand_new.py — Create a test file that asserts `hello` in app.py returns 1. VERIFY: `grep -q hello app.py`. (cat:test; multifile:no) [feat:demo-20261013-create-brand-new]'

echo "== ON: the item is credited without any model call"
mk_case ce_on; add_test_fn; set_prog "$CE_OK"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
eq "1 status no-op(ALREADY-DONE)" "$OUT" "no-op(ALREADY-DONE)"
eq "2 no model call was spent (aider never ran: no scout, no implement)" "$(aider_calls)" "0"
ok "3 the item is ticked and the credit commit exists" 'prog_has "- [x] (already-done, create target exists with its tests)" && log_has "credit create item already satisfied"'
ok "4 pushed to origin" 'origin_has claude/feature "credit create item already satisfied"'
ok "5 the decision is recorded in state/create_exists.log (mode=on)" 'grep -q "mode=on target=tests/test_app.py" "$TREE/state/create_exists.log"'
ok "6 the test file itself is untouched (no duplicate class body appended)" '[ "$(git -C "$REPO" show HEAD:tests/test_app.py | grep -c "def test_hello_returns_one")" = 1 ]'

echo "== ON, the item's own VERIFY FAILS: not credited, still no model call (the implement step would only append a duplicate)"
mk_case ce_vfail; add_test_fn; set_prog "$CE_VFAIL"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
eq "7 status no-op(ALREADY-DONE)" "$OUT" "no-op(ALREADY-DONE)"
eq "8 no model call" "$(aider_calls)" "0"
ok "9 the item stays OPEN (VERIFY gate refused the credit)" 'prog_has "- [ ] [T1] tests/test_app.py" && logged "CREATE-EXISTS credit REFUSED"'

echo "== controls"
mk_case ce_named; set_prog "$CE_NAMED_MISSING"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
ok "10 a named test function the file lacks: NOT short-circuited, the cycle runs" '[ "$(aider_calls)" -ge 1 ] && ! logged "CREATE-EXISTS"'
mk_case ce_new; set_prog "$CE_NEWFILE"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
ok "11 a Create item whose target does not exist yet: NOT short-circuited, the cycle runs" '[ "$(aider_calls)" -ge 1 ] && ! logged "CREATE-EXISTS"'
mk_case ce_nonongoing; add_test_fn; set_prog "$CE_OK"; scout_ok
OVN_CREATE_EXISTS=on run_id t-app
ok "12 a non-ongoing task id never runs the check" '! logged "CREATE-EXISTS" && [ "$(aider_calls)" -ge 1 ]'

echo "== SHADOW (the default) and OFF"
mk_case ce_shadow; add_test_fn; set_prog "$CE_OK"; scout_ok
run_id ongoing-app
ok "13 DEFAULT is shadow: logs 'would short-circuit', credits nothing, the cycle runs" '[ -z "${OVN_CREATE_EXISTS:-}" ] && grep -q "mode=shadow target=tests/test_app.py" "$TREE/state/create_exists.log" && [ "$(aider_calls)" -ge 1 ] && ! log_has "credit create item"'
mk_case ce_off; add_test_fn; set_prog "$CE_OK"; scout_ok
_ce_n="$(wc -l < "$TREE/state/create_exists.log" | tr -d ' ')"
OVN_CREATE_EXISTS=off run_id ongoing-app
ok "14 MUTATION / kill switch off: the item goes to the scout and the implement step (the live defect), nothing is logged" '[ "$(aider_calls)" -ge 1 ] && [ "$(wc -l < "$TREE/state/create_exists.log" | tr -d " ")" = "$_ce_n" ]'

echo "== reviewer defect 2: only evidence-grade items short-circuit"
mk_case ce_call; add_test_fn; set_prog "$CE_CALL"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
ok "15 an item naming an asserted call the file contains verbatim (hello(41) == 42): short-circuited, no model call" '[ "$OUT" = "no-op(ALREADY-DONE)" ] && [ "$(aider_calls)" = 0 ] && prog_has "- [x] (already-done, create target exists with its tests)"'
mk_case ce_unnamed; add_test_fn; set_prog "$CE_UNNAMED"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
ok "16 'Add a test case verifying X' naming no function, against a file that has other tests: NOT short-circuited (the old 'any test function' rule credited it), the cycle runs" '[ "$(aider_calls)" -ge 1 ] && ! logged "CREATE-EXISTS" && ! log_has "credit create item"'
mk_case ce_unnamed_shadow; add_test_fn; set_prog "$CE_UNNAMED"; scout_ok
_ce_n2="$(wc -l < "$TREE/state/create_exists.log" 2>/dev/null | tr -d ' ')"; _ce_n2="${_ce_n2:-0}"
run_id ongoing-app
ok "17 ... and shadow mode does not even log a 'would credit' row for it (no log noise)" '[ "$(wc -l < "$TREE/state/create_exists.log" 2>/dev/null | tr -d " ")" = "$_ce_n2" ] || { [ ! -f "$TREE/state/create_exists.log" ] && [ "$_ce_n2" = 0 ]; }'

echo "== second review: the shadow log is not appended every cycle, and the item is the one the scout path resolves"
CE_OK2="${CE_OK/create-app-test/create-app-test-two}"
mk_case ce_shadow2; add_test_fn; set_prog "$CE_OK2"; scout_ok
_ce_n3="$(wc -l < "$TREE/state/create_exists.log" 2>/dev/null | tr -d ' ')"; _ce_n3="${_ce_n3:-0}"
run_id ongoing-app
scout_ok
run_id ongoing-app
ok "18 shadow mode logs ONE row for the same repo/item/target across two cycles (it used to append one per cycle)" '[ "$(wc -l < "$TREE/state/create_exists.log" | tr -d " ")" = "$((_ce_n3 + 1))" ]'
mk_case ce_on2; add_test_fn; set_prog "$CE_OK"; scout_ok
OVN_CREATE_EXISTS=on run_id ongoing-app
ok "19 ON mode still logs its row (it acts on it)" 'grep -q "mode=on target=tests/test_app.py" "$TREE/state/create_exists.log"'
# the block must decide the item ovn_resolve_top_item names (the scout path's resolver), not a private copy of its pipeline: a resolver pointing at the 2nd line wins over the file's first line.
# A distinct item text keys the row (the log persists across cases, so a bare 'target=' match would pass on rows written by earlier cases).
CE_OK3="${CE_OK/create-app-test/create-app-test-three}"
mk_case ce_resolver; add_test_fn; scout_ok
( cd "$OTHER" && printf '# Progress\n\n## Next Steps\n- [ ] [T2] other.py — first item, not a create item\n%s\n\n## Completed\n' "$CE_OK3" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m prog3 && git push -q origin main && git push -q -f origin main:claude/feature && cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1
ovn_resolve_top_item(){ printf '5:%s' "$CE_OK3"; }
run_id ongoing-app
_ce_k3="item=$(printf '%s' "$CE_OK3" | cksum | cut -d' ' -f1) "
ok "20 the CREATE-EXISTS block takes its item from ovn_resolve_top_item (a stubbed resolver naming the Create item at line 5 makes ITS row appear; the old private pipeline picked line 1 and logged nothing for it)" 'grep -qF -- "$_ce_k3" "$TREE/state/create_exists.log"'
unset -f ovn_resolve_top_item

summary
