#!/usr/bin/env bash
# Package Z3 (2026-11-07): the landing gates are WIRED into the real ovn_stage_runner.sh. Hermetic fixture (lib_osr_fixture.sh): stub aider writes a "Hey" greeting route in a repair-like
# change; the step must PASS and the finding be journalled by default (shadow), and be REFUSED (fa=landing-gate) only with the gate's own enforce flag.
# Needs GNU sed + bash 5 (run on the box); SKIPs elsewhere like the other runner fixtures.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_Z3_TONE_LINT OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_EMPTY_FILE NTFY_SERVER NTFY_TOPIC OVN_Z3_TONE OVN_Z3_STEP_DIFF OVN_Z3_TEST_SRC OVN_Z3_EDITOR_LEAK OVN_STAGE_EDITOR_FORMAT
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
SNIP_HEY='mkdir -p backend/app backend/tests
printf "def foo():\n    return \"Hey there! foo\"\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo()\n" > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_landing_gates.sh" "$REALQ/scripts/ovn_landing_gates.py" "$Q/scripts/"; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; }
SH(){ cat "$Q/state/landing_gates_shadow.log" 2>/dev/null; }

echo "== A: OVN_Z3_TONE=shadow (the revert switch; tone-lint defaults to enforce since 2026-11-12) - the tone finding is journalled, the step still PASSes and lands"
setup; osr_aider default "$SNIP_HEY"
OVN_Z3_TONE=shadow OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "A1 step PASSes on attempt 1 (shadow never refuses)" G "step 0 PASS (att 1"
t "A2 the shadow journal has a tone-lint row naming the file and the token" bash -c "grep -q '\"rule\": \"tone-lint\"' '$Q/state/landing_gates_shadow.log' && grep -q '\"token\": \"Hey\"' '$Q/state/landing_gates_shadow.log' && grep -q 'backend/app/foo.py' '$Q/state/landing_gates_shadow.log'"
t "A3 the journal row says mode shadow" bash -c "grep -q '\"mode\": \"shadow\"' '$Q/state/landing_gates_shadow.log'"
t "A4 the run lands 1/1" G "DONE: 1/1 steps landed"
osr_cleanup

echo "== B: DEFAULT (no flag = enforce) refuses the step as fa=landing-gate, nothing is committed"
setup; osr_aider default "$SNIP_HEY"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "B1 the step is REJECTED by the landing gate" G "REJECTED (landing gate): tone-lint"
t "B2 the journal row records fail_reason landing-gate" bash -c "cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | grep -q 'landing-gate'"
t "B3 0/1 steps landed and the greeting is not on origin" bash -c "grep -q 'DONE: 0/1 steps landed' '$T/out.txt' && ! git -C '$O' show overnight/feature:backend/app/foo.py 2>/dev/null | grep -q Hey"
osr_cleanup

echo "== C: a clean change leaves no journal at all and lands"
setup; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "C1 PASS and landed 1/1" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
t "C2 no landing_gates_shadow.log rows for a clean diff" bash -c "! grep -q . '$Q/state/landing_gates_shadow.log' 2>/dev/null"
osr_cleanup

echo "== D: the editor-example leak in the aider output is journalled (B0) and enforced only on request"
LEAKSNIP="$SNIP_FOO
echo 'The user wants to change the greeting to be more casual. Looking at the component'"
setup; osr_aider 1 "$LEAKSNIP"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D1 shadow: leak row journalled, step passes" bash -c "grep -q 'editor-example-leak' '$Q/state/landing_gates_shadow.log' && grep -q 'step 0 PASS (att 1' '$T/out.txt'"
osr_cleanup
setup; osr_aider default "$LEAKSNIP"
OVN_Z3_EDITOR_LEAK=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D2 enforce: the leaked attempt is refused" G "REJECTED (landing gate): editor-example-leak"
osr_cleanup

echo "== E: OVN_STAGE_EDITOR_FORMAT is passed to aider as --editor-edit-format only when set"
setup; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_EDITOR_FORMAT=editor-diff OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1 aider got --editor-edit-format editor-diff" bash -c "grep -qx -- '--editor-edit-format' '$T/scn/aider.args.1' && grep -qx 'editor-diff' '$T/scn/aider.args.1'"
osr_cleanup
setup; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E2 unset (default): the flag is absent" bash -c "! grep -q -- 'editor-edit-format' '$T/scn/aider.args.1'"
osr_cleanup
echo "== F: a NO-EDIT attempt that ends on a replayed example is journalled too (B0 on every attempt, not only post-edit)"
NOEDIT_LEAK="echo 'The user wants to change the greeting to be more casual. No other files need to be added'"
setup; osr_aider default "$NOEDIT_LEAK"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F1 no-edit attempt: the leak row is journalled (shadow) although no edit was produced" bash -c "grep -q 'editor-example-leak' '$Q/state/landing_gates_shadow.log'"
t "F2 nothing landed (the gate never changes the outcome)" G "DONE: 0/1 steps landed"
osr_cleanup
osr_summary
