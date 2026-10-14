#!/usr/bin/env bash
# N4 stage-runner-waste, Part 3 (2026-10-13): OVN_STAGE_SCOPE_LEARN=off|shadow|on in ovn_stage_runner.sh.
# The multifile:no scope guard rejects a step whose (already green) diff touches an undeclared file: 15 rejections over 6 items in 48h, the SAME undeclared set recurring 8 times (iptv RecordingsView.vue
# needs iptv-web/src/stores/recordings.ts + __tests__/recordings.test.ts; RevenueCatManagerTest.kt needs RevenueCatManager.kt 4x) - the guard can never be satisfied, so the item deadlocks.
# The same undeclared set recurring in two attempts: ON extends the item's declared scope for the next attempt (<=3 existing tracked, non-denylisted, non-banned, non-native files) or escalates at once
# (anything else); SHADOW (the default) only logs what it would do; a first sighting never changes anything.
# Drives the REAL ovn_stage_runner.sh in the hermetic fixture (lib_osr_fixture.sh). Needs GNU sed + bash 5 (run on the box).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_SCOPE_LEARN OVN_STAGE_SAME_SIG_STOP OVN_STAGE_MAX_ATTEMPTS NTFY_SERVER NTFY_TOPIC
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
ITEM_SCOPE='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python; multifile:no)'
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
# aider does the declared work AND edits an existing tracked file nobody declared (svc.py): the step's own gate is green, the scope guard rejects
SNIP_TOUCH_SVC="$SNIP_FOO
echo '# touched by the step' >> backend/app/svc.py"
nextrun(){ rm -f "$T/llm/n" "$T/scn/aider.n" "$T"/llm/body.* "$T"/scn/aider.args.*; }
sd(){ ls "$Q"/state/item_fails/stage-"$OSR_REPO".*."$1" 2>/dev/null; }
setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_progress "- [ ] $ITEM_SCOPE"; osr_plan default "$PLAN"; osr_aider default "$SNIP_TOUCH_SVC"; }
# runs the step twice in ONE run (2 attempts) with redecompose off
run(){ OVN_STAGE_REDECOMP="${REDECOMP:-0}" osr_run "$OSR_REPO"; }

echo "== A: SHADOW (default): logs what it would extend, changes nothing"
setup; run
t "A1 attempt 1: REJECTED (scope) for backend/app/svc.py (the guard itself is unchanged)" G "step 0 REJECTED (scope): touched undeclared file(s): backend/app/svc.py"
t "A2 attempt 2 (same set recurs): the shadow line says it WOULD extend" G "scope-learn (shadow): would extend the declared scope by backend/app/svc.py"
t "A3 ... and nothing was extended" bash -c "! grep -q 'scope extended' '$T/out.txt' && [ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext 2>/dev/null)\" ]"
t "A4 the journal has a scope_learn first row and a shadow-extend row" bash -c "grep -q '\"decision\":\"first\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '\"decision\":\"shadow-extend\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "A5 the step is still BLOCKED (0/1 landed): shadow never rescues anything" G "DONE: 0/1 steps landed"
nextrun; OVN_STAGE_SAME_SIG_STOP=on run
t "A6 the NEXT run is rejected again (no extension in shadow); the identical failure then stops the retry (Part 2)" bash -c "grep -q 'REJECTED (scope)' '$T/out.txt' && grep -q 'same failure signature as the previous staged run' '$T/out.txt'"
osr_cleanup

echo "== B: ON: the recurring set is extended for the next attempt, which then passes and lands"
setup; OVN_STAGE_SCOPE_LEARN=on run
t "B1 attempt 1 REJECTED; attempt 2 (recurrence) logs 'scope extended' for svc.py" bash -c "grep -q 'step 0 REJECTED (scope)' '$T/out.txt' && grep -q 'scope extended: the same undeclared set recurred (backend/app/svc.py)' '$T/out.txt'"
t "B2 the extension is persisted for the item" bash -c "grep -qx 'backend/app/svc.py' \$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext)"
t "B3 this run still lands 0/1 (the extension is for the NEXT attempt) but was NOT stopped by the same-signature check" bash -c "grep -q 'DONE: 0/1 steps landed' '$T/out.txt' && ! grep -q 'same failure signature' '$T/out.txt' && grep -q 'attempt 1/3: item stays OPEN' '$T/out.txt'"
nextrun; OVN_STAGE_SCOPE_LEARN=on run
t "B4 next run: the step PASSES at attempt 1 although it touches svc.py (scope extended)" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -q 'REJECTED (scope)' '$T/out.txt'"
t "B5 the item lands 1/1 and the pushed commit contains the svc.py edit" bash -c "grep -q 'DONE: 1/1 steps landed' '$T/out.txt' && git -C '$O' show overnight/feature:backend/app/svc.py | grep -q 'touched by the step'"
t "B6 the learned state is cleared after the landing (scopeseen/scopeext)" bash -c "[ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeseen '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext 2>/dev/null)\" ]"
osr_cleanup

echo "== C: ON, single attempt per run: a FIRST sighting never extends; the recurrence in the next run does"
setup; OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_SCOPE_LEARN=on run
t "C1 run 1: rejected, first sighting, NO extension" bash -c "grep -q 'REJECTED (scope)' '$T/out.txt' && ! grep -q 'scope extended' '$T/out.txt' && [ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext 2>/dev/null)\" ]"
nextrun; OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_SCOPE_LEARN=on run
t "C2 run 2: the set recurs (across runs) -> scope extended, and the retry is NOT killed by the same-signature stop" bash -c "grep -q 'scope extended' '$T/out.txt' && ! grep -q 'same failure signature' '$T/out.txt' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt'"
nextrun; OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_SCOPE_LEARN=on run
t "C3 run 3: lands with the extended scope" G "DONE: 1/1 steps landed"
osr_cleanup

echo "== D: ON: a recurring set that cannot be learned escalates at once (no more attempts, no re-decomposition)"
d_case(){ # $1=label $2=aider snippet $3=expected reason fragment ; sets up tracked extras first via $4 (shell snippet run after setup)
  setup; [ -n "${4:-}" ] && eval "$4"
  osr_aider default "$SNIP_FOO
$2"
  REDECOMP=1 OVN_STAGE_SCOPE_LEARN=on run
  t "$1: 'cannot be learned (...$3...)' and the step is ABANDONED (scope-violation)" bash -c "grep -q 'cannot be learned' '$T/out.txt' && grep -q '$3' '$T/out.txt' && grep -q 'step 0 ABANDONED (scope-violation)' '$T/out.txt'"
  t "$1: not re-decomposed (only the one decompose LLM call was made) and nothing extended" bash -c "[ \"\$(cat '$T/llm/n')\" = 1 ] && [ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext 2>/dev/null)\" ]"
  osr_cleanup
}
d_case "D1 more than 3 files" 'for i in 1 2 3 4; do echo "# t" >> backend/app/x$i.py; done' "4 files (limit 3)" 'for i in 1 2 3 4; do osr_tracked backend/app/x$i.py "# x\n"; done'
d_case "D2 hard-banned file" 'echo "# t" >> backend/app/svc.py' "hard-banned file" 'osr_tracked .queue-hard-banned-files "backend/app/svc.py\n"'
d_case "D3 a NEW (untracked) junk file" 'mkdir -p aether; echo junk > aether/README.md' "is not an existing tracked file" ''
d_case "D4 vendored path" 'echo "# t" >> vendor/lib.py' "vendored/generated path" 'osr_tracked vendor/lib.py "# v\n"'
d_case "D5 native mobile code" 'echo "# t" >> iptv-android/app/Foo.kt' "native mobile code" 'osr_tracked iptv-android/app/Foo.kt "// k\n"'

echo "== E: SHADOW with an ineligible set only logs"
setup; osr_aider default "$SNIP_FOO
mkdir -p aether; echo junk > aether/README.md"
REDECOMP=1 run
t "E1 'would escalate immediately' is logged, the step is NOT abandoned early (old behaviour: re-decomposed)" bash -c "grep -q 'scope-learn (shadow): would escalate immediately' '$T/out.txt' && ! grep -q 'ABANDONED' '$T/out.txt' && [ \"\$(cat '$T/llm/n')\" -ge 2 ]"
osr_cleanup

echo "== F: OVN_STAGE_SCOPE_LEARN=off writes no state and logs nothing"
setup; OVN_STAGE_SCOPE_LEARN=off run
t "F1 rejected as before, no scope-learn line, no state files" bash -c "grep -q 'REJECTED (scope)' '$T/out.txt' && ! grep -q 'scope-learn\|scope extended' '$T/out.txt' && [ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeseen 2>/dev/null)\" ]"
osr_cleanup

echo "== G: a multifile:yes item is never scope-checked (control)"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null
osr_progress "- [ ] [T3] backend/app/foo.py — Add foo helper with its test. VERIFY: \`pytest backend/tests/test_foo.py\` (cat:python; multifile:yes)"
osr_plan default "$PLAN"; osr_aider default "$SNIP_TOUCH_SVC"
OVN_STAGE_SCOPE_LEARN=on run
t "G1 PASSes with the extra file, no scope-learn activity" bash -c "grep -q 'DONE: 1/1 steps landed' '$T/out.txt' && ! grep -q 'scope' '$T/out.txt'"
osr_cleanup
osr_summary
