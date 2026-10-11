#!/usr/bin/env bash
# 2026-10-10 (harness R10, BX-09): the staged runner must not report success when nothing landed.
#
# Live defect replayed (xlite, logs/20261010-012830 and 014406): 'step 0 BLOCKED', 'step 0.0 BLOCKED', 'step 0.1 BLOCKED' (all FAIL (no-edit)), then
# "independent full-verify: PASSED - the combined result is real", "leaving item OPEN ... (verified but push failed - not marking done)" and "DONE: 1/1 steps landed (100%)".
# Nothing had been changed. Root cause: run_step's re-decompose branch `return 0`'d ("partial progress") even when EVERY sub-step was BLOCKED, so the step counted as landed, the full verify
# ran on the unchanged baseline tree ("verified"), and "push failed" was claimed with no push attempted.
# Drives the REAL ovn_stage_runner.sh in the hermetic fixture (lib_osr_fixture.sh): stub aider/LLM, a local bare origin.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }

PLAN_BIG='[{"desc":"big step","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest"}]'
PLAN_SUBS='[{"desc":"sub one","files":["backend/app/foo.py"],"verify":"pytest one"},{"desc":"sub two","files":["backend/app/bar.py"],"verify":"pytest two"}]'

# aider never edits anything (no-edit on every attempt) -> every step and sub-step BLOCKED
setup_all_blocked(){ osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan 1 "$PLAN_BIG"; osr_plan 2 "$PLAN_SUBS"; osr_aider default 'echo "I looked at it, nothing to change"'; }

echo "== A: every re-decomposed sub-step BLOCKED -> the step is NOT landed"
setup_all_blocked
OVN_STAGE_ZERO_CAP=3 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "A1 sub-steps 0.0 and 0.1 are reported BLOCKED" bash -c "grep -q 'sub-step 0.0 BLOCKED' '$T/out.txt' && grep -q 'sub-step 0.1 BLOCKED' '$T/out.txt'"
t "A2 the parent step says all sub-steps BLOCKED and is itself BLOCKED" G "all 2 re-decomposed sub-steps BLOCKED - nothing landed"
t "A3 the run reports 0 of 1 steps landed" G "DONE: 0/1 steps landed (0%)"
t "A4 NO 'independent full-verify: PASSED' (nothing to verify)" NG "independent full-verify: PASSED"
t "A5 no claim that a push failed" NG "push failed"
t "A6 the summary journals passed 0, verified false, commits_pushed 0" J '"passed":0,"total":1,"verified":false,"commits_pushed":0'
t "A7 the item stays OPEN for another try (zero-landing retry budget), not checked off" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\]' && grep -q 'staged pipeline landed 0/1 - attempt 1/3' '$T/out.txt'"
osr_cleanup

echo "== B: MUTATIONS - the old behaviour, switch by switch"
setup_all_blocked
OVN_STAGE_SUBSTEP_HONEST=off OVN_STAGE_ZERO_CAP=3 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "B1 honest-substeps OFF + no-edit guard ON: the guard still catches it ('no-edit', steps landed=0, verify skipped)" bash -c "grep -q 'no-edit: no step produced a commit ahead of origin/overnight/feature' '$T/out.txt' && grep -q 'DONE: 0/1 steps landed' '$T/out.txt' && ! grep -q 'independent full-verify: PASSED' '$T/out.txt'"
t "B2 ... and the journal has the no_edit event" J '"event":"no_edit"'
osr_cleanup
setup_all_blocked
OVN_STAGE_SUBSTEP_HONEST=off OVN_STAGE_NOEDIT_GUARD=off OVN_STAGE_ZERO_CAP=3 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "B3 BOTH off = the live defect: 'DONE: 1/1 steps landed (100%)' with nothing changed" G "DONE: 1/1 steps landed (100%)"
t "B4 ... 'independent full-verify: PASSED' on the unchanged tree" G "independent full-verify: PASSED"
t "B5 ... but it no longer CLAIMS a push failed when no push was attempted" bash -c "! grep -q 'push failed' '$T/out.txt' && grep -q 'nothing to push' '$T/out.txt'"
osr_cleanup

echo "== C: a real push race still says so (a push WAS attempted)"
osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"
osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; touch "$T/reject_always"
osr_run "$OSR_REPO"
t "C1 verified + push rejected -> 'push FAILED (fleet racing)' and 'verified but push failed'" bash -c "grep -q 'push FAILED (fleet racing)' '$T/out.txt' && grep -q 'verified but push failed' '$T/out.txt'"
osr_cleanup

echo "== D: partial landing (some sub-steps BLOCKED) is pushed but the item is NOT checked off"
osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"
osr_plan 1 "$PLAN_BIG"; osr_plan 2 "$PLAN_SUBS"; osr_aider 3 "$SNIP_FOO"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "D1 sub-step 0.0 PASSES, 0.1 is BLOCKED" bash -c "grep -q 'step 0.0 PASS' '$T/out.txt' && grep -q 'sub-step 0.1 BLOCKED' '$T/out.txt'"
t "D2 the landed sub-step is still verified and pushed (partial progress is kept)" G "pushed 1 verified commit"
t "D3 the item is NOT checked off as fully done" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\]'"
t "D4 ... it is parked with the partial-landing tag (BLOCKED sub-steps are not landed)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged 1/1 — 1 step(s) landed only part of their re-decomposed sub-steps'"
osr_cleanup

echo "== E: unverified outcome row carries fail_reason no-edit when the guard fired"
setup_all_blocked
OVN_STAGE_SUBSTEP_HONEST=off OVN_STAGE_ZERO_CAP=3 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "E1 state/outcomes.jsonl row: no-op(stage-unverified), fail_reason no-edit" bash -c "tail -1 '$Q/state/outcomes.jsonl' | jq -e '.fail_reason==\"no-edit\" and (.status|startswith(\"no-op(stage-unverified)\"))'"
osr_cleanup

osr_summary
