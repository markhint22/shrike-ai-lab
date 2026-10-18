#!/usr/bin/env bash
# 2026-10-18 xlite landing audit: an item whose own VERIFY is a pure text probe (grep/test) and is RED after the change must NOT be ticked, even in the default
# OVN_STAGE_ITEM_VERIFY=shadow mode. Live false credits: 'Delete generate_intent / intent_label' (the repair round re-added both: `grep -n "func generate_intent"` still matched),
# 'return "" for unknown directives' and 'if ... directive_label in mission_hub.gd' (the grep matched nothing) - all ticked [x] with decision=refuse journalled in shadow.
#   Part U: stage_item_verify_textonly classifier (pure bash, runs anywhere).   Part E: the real runner in the fixture (GNU sed needed: run on the box / sandboxed scratch).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_ITEM_VERIFY OVN_STAGE_ITEM_VERIFY_TEXT OVN_STAGE_IV_SHADOW_LOG OVN_STAGE_RED_BEFORE OVN_STAGE_WEB_VERIFY NTFY_SERVER NTFY_TOPIC
trap osr_cleanup EXIT
. "$HERE/../lib_stage_guards.sh"
echo "== U: classifier"
yes_(){ stage_item_verify_textonly "$1"; }
no_(){ ! stage_item_verify_textonly "$1"; }
t "U1 the xlite generate_intent shape (grep -n ... returns no output) is a text probe" yes_ '[T4] scripts/battle/enemy_intent.gd — Delete the function. VERIFY: `grep -n "func generate_intent" scripts/battle/enemy_intent.gd` returns no output. (cat:refactor)'
t "U2 grep -q ... is a text probe" yes_ '[T1] a.gd — x. VERIFY: `grep -q "def foo" backend/app/foo.py` (cat:python)'
t "U3 test -f / ! grep are text probes" yes_ '[T1] a.gd — x. VERIFY: `test ! -f scripts/battle/loot_table.gd && echo PASS`'
t "U3b X && echo FAIL || echo PASS is still a text probe (iptv streams.py false credit)" yes_ '[T3] a.py — x. VERIFY: `grep -E "def a|def b" a.py && echo "FAIL" || echo "PASS"`'
t "U3c a runner behind the echo form is NOT a text probe" no_ '[T3] a.py — x. VERIFY: `pytest tests/t.py && echo FAIL || echo PASS`'
t "U3b ! grep is a text probe" yes_ '[T1] a.gd — x. VERIFY: `! grep -n "foo" a.gd`'
t "U4 pytest is NOT a text probe (its FAIL can be an env gap)" no_ '[T2] a.py — x. VERIFY: `python -m pytest tests/test_a.py -v` (cat:python)'
t "U5 grep && pytest is NOT a text probe" no_ '[T2] a.py — x. VERIFY: `grep -q "x" a.py && python -m pytest tests/test_a.py -v`'
t "U6 a godot run is NOT a text probe" no_ '[T2] a.gd — x. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gexit`'
t "U7 command substitution / chaining is NOT a text probe" no_ '[T2] a.gd — x. VERIFY: `grep -q x a.gd; echo $(rm -rf /tmp/x)`'
t "U8 no VERIFY clause is NOT a text probe" no_ '[T2] a.gd — x. (cat:godot)'
t "U9 only the FIRST backticked VERIFY command counts; a runner after it is not hidden" no_ '[T2] a.gd — x. VERIFY: `bash run.sh` then `grep -q x a.gd`'

if ! sed --version >/dev/null 2>&1; then echo "  SKIP part E: needs GNU sed; run on the box"; osr_summary; exit $?; fi
n2_new(){ osr_new
  local f; for f in lib_stage_guards.sh lib_verify_clause.sh ovn_stage_guards.py ovn_backlog_eligibility.py ovn_credit_items.py ovn_spec_rules.py ovn_verify_safe.py ovn_gut_clause.py lib_item_select.sh; do
    [ -f "$REALQ/scripts/$f" ] && cp "$REALQ/scripts/$f" "$Q/scripts/"
  done; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
PROGF(){ git -C "$O" show overnight/feature:OVERNIGHT_PROGRESS.md; }
echo "== E: the real runner"
ITEM_G='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `grep -q "def foo" backend/app/foo.py` (cat:python)'
BAD='mkdir -p backend/app backend/tests; printf "def bar():\n    return 1\n" > backend/app/foo.py; printf "from app.foo import bar\n\ndef test_bar():\n    assert bar() == 1\n" > backend/tests/test_foo.py; echo "Applied edit"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_G"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$BAD"
osr_run "$OSR_REPO"
t "E1 default (shadow) + text-probe VERIFY RED after the change: NOT ticked" bash -c "! grep -q '^- \[x\]' <<< \"\$($(declare -f PROGF); O='$O'; PROGF)\""
t "E2 ... and parked for review with the RED reason" bash -c "grep -q 'AUTO-SKIP staged 1/1 .*RED after the change' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
t "E3 ... the journal says item_verify_text_enforced" bash -c "grep -q 'item_verify_text_enforced' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_G"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$BAD"
OVN_STAGE_ITEM_VERIFY_TEXT=off osr_run "$OSR_REPO"
t "E4 MUTANT (OVN_STAGE_ITEM_VERIFY_TEXT=off): the old behaviour - ticked although the grep is RED" bash -c "grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
ITEM_P='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_nothing_here.py` (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_P"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$BAD"
osr_run "$OSR_REPO"
t "E5 control: a pytest VERIFY that is RED after the change is NOT enforced in shadow (env gaps stay credit-as-before)" bash -c "! grep -q 'item_verify_text_enforced' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_G"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "E6 control: a text-probe VERIFY that goes GREEN is ticked as before" bash -c "grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
osr_summary
