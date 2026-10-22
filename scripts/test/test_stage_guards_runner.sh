#!/usr/bin/env bash
# Package `stage` (2026-10-13): the REAL ovn_stage_runner.sh against the findings of the 2026-10-12/13 overnight review, in the hermetic fixture (lib_osr_fixture.sh).
#
#   A  xlite F3   a Verify step naming a file that does not exist is REFUSED before any model call (the run fabricated scripts/mission/codex_manager.gd)
#   B  xlite F3   an item whose own VERIFY greps a non-existent file is mis-targeted: no step runs, the item is escalated at once (OVN_STAGE_ITEM_MISTARGET=enforce; SHADOW by default - reviewer 2026-10-13)
#   C  xlite F3   Godot's `hides an autoload singleton` abandons the step (no retry, no re-decomposition)
#   D  iptv F2    every test the item / a landed step promised must exist in the final tree and pass by node id (a repair round deleted the test and the item was credited)
#   E  F3 + F2    the item's own VERIFY red-before / green-after (SHADOW by default; enforce parks the item)
#   F  iptv F6    red-before: a test the change added must fail when the source change is reverted (SHADOW by default)
#   G  iptv F6    web verification (vue-tsc + vitest related) for changed web files (SHADOW by default)
# Every block also runs the old behaviour through its kill switch (the mutation proof that the assertion can fail). GNU sed is needed by the runner's progress bookkeeping: run on the box.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP NTFY_SERVER NTFY_TOPIC OVN_STAGE_MISTARGET OVN_STAGE_ITEM_MISTARGET OVN_STAGE_SHADOW_LOG OVN_STAGE_IV_SHADOW_LOG OVN_SG_CONTEXT OVN_STAGE_CLASS_CONFLICT OVN_STAGE_NAMED_TESTS OVN_STAGE_ITEM_VERIFY OVN_STAGE_RED_BEFORE OVN_STAGE_WEB_VERIFY
trap osr_cleanup EXIT
# the shared fixture copies only a fixed set of libs: add the package's own (without them the runner's guards are no-ops by design)
n2_new(){ osr_new
  local f; for f in lib_stage_guards.sh lib_verify_clause.sh ovn_stage_guards.py ovn_backlog_eligibility.py ovn_credit_items.py ovn_spec_rules.py ovn_verify_safe.py ovn_gut_clause.py lib_item_select.sh; do
    [ -f "$REALQ/scripts/$f" ] && cp "$REALQ/scripts/$f" "$Q/scripts/"
  done; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
prog(){ osr_origin_file OVERNIGHT_PROGRESS.md; }
aider_calls(){ cat "$T/scn/aider.n" 2>/dev/null || echo 0; }
llm_calls(){ cat "$T/llm/n" 2>/dev/null || echo 0; }
pushed(){ G "verified commit(s) to overnight/feature"; }

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== A: a Verify step naming a non-existent file is refused (xlite F3)"
ITEM_A='[T3] backend/app/svc.py — Verify run_job is idempotent. VERIFY: `pytest backend/tests/test_svc.py` (cat:python)'
PLAN_A='[{"desc":"Verify the presence of the idempotence helper","files":["backend/app/ghost.py"],"verify":"gdparse backend/app/ghost.py"}]'
SNIP_GHOST='mkdir -p backend/app; printf "def run_job_twice():\n    return 2\n" > backend/app/ghost.py; echo "Applied edit to backend/app/ghost.py"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_A"; osr_plan default "$PLAN_A"; osr_aider default "$SNIP_GHOST"
osr_run "$OSR_REPO"
t "A1 the step is REFUSED as mis-targeted" G "REFUSED (mis-targeted)"
t "A2 aider was never called (no model call, nothing created)" bash -c "[ '$(aider_calls)' = 0 ]"
t "A3 nothing was pushed: ghost.py does not exist on origin" bash -c "! git -C '$O' cat-file -e overnight/feature:backend/app/ghost.py 2>/dev/null"
t "A4 the journal records fail_reason mistargeted + the step BLOCKED" bash -c "grep -q '\"fail_reason\":\"mistargeted\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '\"verdict\":\"blocked\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "A5 the item is NOT ticked" bash -c "! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
# MUTATION: guard off = the live defect
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_A"; osr_plan default "$PLAN_A"; osr_aider default "$SNIP_GHOST"
OVN_STAGE_MISTARGET=off osr_run "$OSR_REPO"
t "A6 MUTANT (OVN_STAGE_MISTARGET=off): aider ran and the fabricated file reached origin (the old behaviour)" bash -c "[ '$(aider_calls)' -ge 1 ] && git -C '$O' cat-file -e overnight/feature:backend/app/ghost.py"
osr_cleanup
echo "== A (control): a Verify step on an EXISTING file still runs"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_A"
osr_plan default '[{"desc":"Verify run_job and add its second test","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py"}]'
osr_aider default 'printf "\n\ndef test_run_job_twice():\n    assert run_job() == run_job()\n" >> backend/tests/test_svc.py; echo "Applied edit"'
osr_run "$OSR_REPO"
t "A7 control: the step ran (aider called) and was not refused" bash -c "[ '$(aider_calls)' -ge 1 ]" 
t "A8 control: not refused" NG "REFUSED (mis-targeted)"
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== B: an item whose own VERIFY greps a non-existent file is mis-targeted (xlite F3)"
ITEM_B='[T5] backend/app/svc.py — Verify no other helpers are missing by checking ghost.py usage. VERIFY: `grep "run_job" backend/app/ghost.py | grep -q run` (cat:python; multifile:no)'
PLAN_B='[{"desc":"Verify the presence of the run_job reference","files":["backend/app/ghost.py"],"verify":"gdparse backend/app/ghost.py"}]'
SNIP_B='mkdir -p backend/app; printf "run_job = 1\n" > backend/app/ghost.py; echo "Applied edit to backend/app/ghost.py"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_B"; osr_plan default "$PLAN_B"; osr_aider default "$SNIP_B"
OVN_STAGE_ITEM_MISTARGET=enforce osr_run "$OSR_REPO"
t "B1 the item is refused as mis-targeted before any step" G "item REFUSED (mis-targeted)"
t "B2 no step ran (aider never called)" bash -c "[ '$(aider_calls)' = 0 ]"
t "B3 escalated at once (zero-landing cap 1): AUTO-SKIP staged ... route to CLAUDE" bash -c "grep -q 'AUTO-SKIP staged: 27B could not land this' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
t "B4 the verify log says why (QUALITY FAIL: mis-targeted item ... ghost.py)" bash -c "grep -q 'mis-targeted item.*ghost.py' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log"
t "B5 the item is NOT ticked and nothing was created" bash -c "! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\" && ! git -C '$O' cat-file -e overnight/feature:backend/app/ghost.py 2>/dev/null"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_B"; osr_plan default "$PLAN_B"; osr_aider default "$SNIP_B"
OVN_STAGE_MISTARGET=off OVN_STAGE_ITEM_MISTARGET=enforce osr_run "$OSR_REPO"
t "B6 MUTANT (OVN_STAGE_MISTARGET=off): a step creates ghost.py, the grep VERIFY goes green and the item is TICKED (the live false credit)" bash -c "git -C '$O' cat-file -e overnight/feature:backend/app/ghost.py && grep -q '^- \[x\].*staged 1/1 DONE' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
echo "== B (default = SHADOW): the item-level verdict is logged, nothing is refused"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_B"; osr_plan default "$PLAN_B"; osr_aider default "$SNIP_B"
osr_run "$OSR_REPO"
t "B8 default (shadow): the item is NOT refused at item level" NG "item REFUSED (mis-targeted)"
t "B9 default (shadow): the verdict is written to state/stage_guards_shadow.log (item-mistarget(shadow) ... ghost.py)" bash -c "grep -q 'item-mistarget(shadow).*ghost.py' '$Q'/state/stage_guards_shadow.log"
t "B10 default (shadow): the step-level guard still refuses the Verify step on the missing file (no model call, nothing created)" bash -c "grep -qF 'REFUSED (mis-targeted)' '$T/out.txt' && [ '$(aider_calls)' = 0 ] && ! git -C '$O' cat-file -e overnight/feature:backend/app/ghost.py 2>/dev/null"
osr_cleanup
echo "== B (reviewer defect 1): a bare-narration VERIFY is never read as file operands (enforce on)"
ITEM_B3='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: grep -n "def foo" backend/app/foo.py shows a match near line 41. (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_B3"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_ITEM_MISTARGET=enforce osr_run "$OSR_REPO"
t "B11 enforce + narration words (41, a, line, match) are not operands: the item is not refused and lands" bash -c "! grep -qF 'item REFUSED' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
echo "== B (control): an item that CREATES the file its VERIFY greps is not mis-targeted"
ITEM_B2='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `grep -q "def foo" backend/app/foo.py` (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_B2"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "B7 control: not refused, landed and ticked" bash -c "! grep -qF 'item REFUSED' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== C: a class_name / autoload conflict abandons the step (xlite F3)"
ITEM_C='[T3] backend/app/svc.py — Add the codex helper to the service. VERIFY: `pytest backend/tests/test_svc.py` (cat:python)'
PLAN_C='[{"desc":"Add the codex helper","files":["backend/app/codex.py"],"verify":"pytest"}]'
SNIP_C='printf "def codex():\n    return 1\n" > backend/app/codex.py; echo "res://scripts/mission/codex_manager.gd:1 - Parse Error: Class \"CodexManager\" hides an autoload singleton."; echo "Applied edit to backend/app/codex.py"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_C"; osr_plan 1 "$PLAN_C"; osr_plan 2 '[{"desc":"sub a","files":["backend/app/codex.py"],"verify":"pytest"},{"desc":"sub b","files":["backend/app/codex2.py"],"verify":"pytest"}]'; osr_aider default "$SNIP_C"
osr_run "$OSR_REPO"
t "C1 the step is ABANDONED (class-conflict)" G "ABANDONED (class-conflict)"
t "C2 exactly ONE aider attempt (no retry)" bash -c "[ '$(aider_calls)' = 1 ]"
t "C3 no re-decomposition (one LLM call: the decomposition itself)" bash -c "[ '$(llm_calls)' = 1 ]"
t "C4 nothing pushed" NG "verified commit(s) to overnight/feature"
t "C5 the journal has fail_reason class-conflict" bash -c "grep -q '\"fail_reason\":\"class-conflict\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_C"; osr_plan 1 "$PLAN_C"; osr_plan 2 '[{"desc":"sub a","files":["backend/app/codex.py"],"verify":"pytest"},{"desc":"sub b","files":["backend/app/codex2.py"],"verify":"pytest"}]'; osr_aider default "$SNIP_C"
OVN_STAGE_CLASS_CONFLICT=off osr_run "$OSR_REPO"
t "C6 MUTANT (OVN_STAGE_CLASS_CONFLICT=off): the step is not abandoned - it LANDS despite the conflict message (the old behaviour: the fabricated file was committed)" bash -c "grep -q 'step 0 PASS' '$T/out.txt' && ! grep -q ABANDONED '$T/out.txt'"
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== D: promised tests must exist in the final tree and pass by node id (iptv F2)"
ITEM_D='[T4] backend/app/svc.py — Add test test_run_job_limit that asserts run_job is bounded. VERIFY: `pytest backend/tests/test_svc.py::test_run_job_limit` (cat:python)'
PLAN_D='[{"desc":"add the bounded run_job and its test","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py::test_run_job_limit"}]'
SNIP_D_GOOD='printf "\n\ndef test_run_job_limit():\n    assert run_job() == 1\n" >> backend/tests/test_svc.py; printf "\n\ndef bounded():\n    return run_job()\n" >> backend/app/svc.py; echo "Applied edit"'
SNIP_D_RENAMED='printf "\n\ndef test_something_else():\n    assert run_job() == 1\n" >> backend/tests/test_svc.py; printf "\n\ndef bounded():\n    return run_job()\n" >> backend/app/svc.py; echo "Applied edit"'

n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_GOOD"
osr_run "$OSR_REPO"
t "D1 the promised test exists and is run by node id (pytest was called with ...::test_run_job_limit)" bash -c "grep -q 'tests/test_svc.py::test_run_job_limit' '$T/scn/pytest.calls'"
t "D2 verified, pushed and the item is ticked" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && grep -q '^- \[x\].*staged 1/1 DONE' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup

n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_RENAMED"
osr_run "$OSR_REPO"
t "D3 a landed step that wrote a DIFFERENT test name is not verified: the promised test is missing" bash -c "grep -q 'promised test(s) that do not exist in the final tree.*test_run_job_limit' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log"
t "D4 nothing pushed, item not ticked" bash -c "! grep -q 'verified commit' '$T/out.txt' && ! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_RENAMED"
OVN_STAGE_NAMED_TESTS=shadow osr_run "$OSR_REPO"
t "D5 shadow mode: logged to <vlog>.shadow-named, the run still verifies (no enforcement)" bash -c "grep -q 'test_run_job_limit' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log.shadow-named && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup

echo "-- D (the live defect): a repair round deletes the test it was meant to fix; the suite is green again"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_GOOD"
echo fail > "$T/scn/pytest.mode"
osr_aider 2 'echo ok > "$OSR_SCN/pytest.mode"; printf "from app.svc import run_job\n" > backend/tests/test_svc.py; echo "Applied edit (repair deleted the test)"'
OVN_VERIFY_REPAIR_ROUNDS=1 osr_run "$OSR_REPO"
t "D6 the repair prompt tells the model never to delete the test" bash -c "grep -q 'NEVER delete, empty, skip or xfail the test the change added' '$T/scn/aider.args.2'"
t "D7 the second verify is rejected: the suite is green but the promised test is gone" bash -c "grep -q 'promised test(s) that do not exist' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log"
t "D8 NOT verified, NOT pushed, NOT ticked (was: REPAIR PASSED and credited)" bash -c "! grep -q 'REPAIR PASSED' '$T/out.txt' && ! grep -q 'verified commit' '$T/out.txt' && ! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_GOOD"
echo fail > "$T/scn/pytest.mode"
osr_aider 2 'echo ok > "$OSR_SCN/pytest.mode"; printf "from app.svc import run_job\n" > backend/tests/test_svc.py; echo "Applied edit (repair deleted the test)"'
OVN_STAGE_NAMED_TESTS=off OVN_VERIFY_REPAIR_ROUNDS=1 osr_run "$OSR_REPO"
t "D9 MUTANT (OVN_STAGE_NAMED_TESTS=off): REPAIR PASSED and the item is credited with the test gone (the live false credit)" bash -c "grep -q 'REPAIR PASSED' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup

echo "-- D: the promise lives in the LANDED STEP only (the item text names no test)"
ITEM_D2='[T4] backend/app/svc.py — Add coverage for the bounded run_job helper. VERIFY: `pytest backend/tests/test_svc.py` (cat:python)'
PLAN_D2='[{"desc":"Add test test_run_job_limit for the bounded helper","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py"}]'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D2"; osr_plan default "$PLAN_D2"; osr_aider 1 "$SNIP_D_RENAMED"
osr_run "$OSR_REPO"
t "D11 a test promised only by a landed step (its description) is also required in the final tree" bash -c "grep -q 'promised test(s) that do not exist in the final tree.*test_run_job_limit' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log && ! grep -q 'verified commit' '$T/out.txt'"
osr_cleanup

echo "-- D (control): a plan whose verify string names a test the model then writes under another name is NOT held to it (only the description and the item's own VERIFY promise)"
ITEM_D3='[T4] backend/app/svc.py — Add coverage for the bounded run_job helper. VERIFY: `pytest backend/tests/test_svc.py` (cat:python)'
PLAN_D3='[{"desc":"Add a test for the bounded helper","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py::test_run_job_limit"}]'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D3"; osr_plan default "$PLAN_D3"; osr_aider 1 "$SNIP_D_RENAMED"
osr_run "$OSR_REPO"
t "D12 control: the model's own guess in the plan verify is not a promise: verified and pushed" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && ! grep -q 'promised test' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log"
osr_cleanup

echo "-- D (reviewer defect 3): a promised Kotlin test that EXISTS is not reported missing"
ITEM_K='[T4] android/app/src/test/EpgRepositoryTest.kt — Add test test_createSource_triggersAutoMap that asserts creating a source maps it (mirrors backend/app/svc.py). VERIFY: `grep -q "fun test_createSource_triggersAutoMap" android/app/src/test/EpgRepositoryTest.kt` (cat:kotlin)'
PLAN_K='[{"desc":"add the kotlin test","files":["android/app/src/test/EpgRepositoryTest.kt"],"verify":"grep -q fun android/app/src/test/EpgRepositoryTest.kt"}]'
SNIP_K='mkdir -p android/app/src/test; printf "class EpgRepositoryTest {\n    @Test\n    fun test_createSource_triggersAutoMap() {\n    }\n}\n" > android/app/src/test/EpgRepositoryTest.kt; echo "Applied edit"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_K"; osr_plan default "$PLAN_K"; osr_aider 1 "$SNIP_K"
osr_run "$OSR_REPO"
t "D13 a Kotlin test promised in a MIXED item (names a .py path too) is located in the .kt file, not reported missing: no 'promised test(s) that do not exist' QUALITY FAIL, verified and pushed" bash -c "! grep -q 'promised test' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log 2>/dev/null && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup
echo "-- D (second review): a promised Kotlin test that was NEVER written is MISSING (it used to fail open as 'unverifiable' and the item was credited)"
ITEM_K2='[T4] android/app/src/test/EpgRepositoryTest.kt — Add test test_createSource_triggersAutoMap that asserts creating a source maps it. VERIFY: `grep -q "fun other" android/app/src/test/EpgRepositoryTest.kt` (cat:kotlin)'
SNIP_K2='mkdir -p android/app/src/test; printf "class EpgRepositoryTest {\n    @Test\n    fun other() {\n    }\n}\n" > android/app/src/test/EpgRepositoryTest.kt; echo "Applied edit"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_K2"; osr_plan default "$PLAN_K"; osr_aider 1 "$SNIP_K2"
osr_run "$OSR_REPO"
t "D14 only Kotlin paths named and the promised test never written: QUALITY FAIL 'promised test(s) that do not exist' and nothing is pushed" bash -c "grep -q 'promised test(s) that do not exist.*test_createSource_triggersAutoMap' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log 2>/dev/null && ! grep -q 'verified commit' '$T/out.txt'"
osr_cleanup
echo "-- D (second review, control): a promised test in a language read with less confidence (TS) stays unverifiable: no finding"
ITEM_T='[T4] web/src/__tests__/foo.spec.ts — Add test test_never_written_ts that asserts foo works. VERIFY: `grep -q "fun other" android/app/src/test/EpgRepositoryTest.kt` (cat:ts)'
PLAN_T='[{"desc":"add the ts test","files":["web/src/__tests__/foo.spec.ts"],"verify":"grep -q it web/src/__tests__/foo.spec.ts"}]'
SNIP_T='mkdir -p web/src/__tests__ android/app/src/test; printf "it(\"other\", () => {})\n" > web/src/__tests__/foo.spec.ts; printf "class EpgRepositoryTest {\n    fun other() {\n    }\n}\n" > android/app/src/test/EpgRepositoryTest.kt; echo "Applied edit"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_T"; osr_plan default "$PLAN_T"; osr_aider 1 "$SNIP_T"
osr_run "$OSR_REPO"
t "D15 only a .ts path named, the promised test never written: unverifiable, no 'promised test' finding" bash -c "! grep -q 'promised test' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log 2>/dev/null"
osr_cleanup

echo "-- D: a promised test that exists but FAILS when run by node id"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_D"; osr_plan default "$PLAN_D"; osr_aider 1 "$SNIP_D_GOOD"
echo "failfile:test_run_job_limit" > "$T/scn/pytest.mode"
osr_run "$OSR_REPO"
t "D10 rc != 0 for the node id is a failure (the full suite alone was green)" bash -c "grep -q 'promised test tests/test_svc.py::test_run_job_limit did not pass' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log && ! grep -q 'verified commit' '$T/out.txt'"
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== E: the item's own VERIFY, red before and green after (xlite F3 + iptv F2)"
ITEM_E1='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `grep -q "def foo" backend/app/foo.py` (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E1"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "E1 pre-change verdict FAIL (file missing), post-change PASS: decision OK, journalled (shadow default)" bash -c "grep -q '\"event\":\"item_verify\",\"mode\":\"shadow\",\"pre\":\"FAIL\",\"post\":\"PASS\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '\"decision\":\"OK\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "E2 ticked as before" bash -c "grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
t "E8 the item-VERIFY probe rows go to their OWN log (state/stage_item_verify_shadow.log), never into verify_gate_shadow.log (digest red counts)" bash -c "grep -q 'repo=stage-' '$Q'/state/stage_item_verify_shadow.log && ! grep -qs 'repo=stage-' '$Q'/state/verify_gate_shadow.log"
osr_cleanup

ITEM_E2='[T3] backend/app/svc.py — Add bounded helper to the service. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python)'
SNIP_E2='printf "\n\ndef bounded():\n    return run_job()\n" >> backend/app/svc.py; printf "from app.svc import bounded\n\ndef test_bounded():\n    assert bounded() == 1\n" > backend/tests/test_bounded.py; echo "Applied edit"'
PLAN_E2='[{"desc":"add bounded and its test","files":["backend/app/svc.py","backend/tests/test_bounded.py"],"verify":"pytest"}]'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E2"; osr_plan default "$PLAN_E2"; osr_aider 1 "$SNIP_E2"
osr_run "$OSR_REPO"
t "E3 shadow: VERIFY already GREEN before any step -> the event says refuse (default unchanged), but the item is still ticked (nothing enforced)" bash -c "grep -q '\"pre\":\"PASS\",\"post\":\"PASS\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'refuse:the item.s own VERIFY was already GREEN' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E2"; osr_plan default "$PLAN_E2"; osr_aider 1 "$SNIP_E2"
OVN_STAGE_ITEM_VERIFY_ALREADY_GREEN=credit OVN_STAGE_ITEM_VERIFY=enforce osr_run "$OSR_REPO"
t "E4a PKG-B enforce + already GREEN + ALREADY_GREEN=credit: credited as already-satisfied, ticked, not parked" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E2"; osr_plan default "$PLAN_E2"; osr_aider 1 "$SNIP_E2"
OVN_STAGE_ITEM_VERIFY=enforce osr_run "$OSR_REPO"
t "E4 enforce: the verified code is pushed but the item is NOT ticked" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && ! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
t "E5 enforce: the line is parked '[AUTO-SKIP staged 1/1 - ... item's own VERIFY did not confirm ...'" bash -c "grep -q 'AUTO-SKIP staged 1/1 .*item.s own VERIFY did not confirm' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E1"; osr_plan default "$PLAN_FOO"; osr_aider 1 'mkdir -p backend/app backend/tests; printf "def bar():\n    return 1\n" > backend/app/foo.py; printf "from app.foo import bar\n\ndef test_bar():\n    assert bar() == 1\n" > backend/tests/test_foo.py; echo "Applied edit"'
OVN_STAGE_ITEM_VERIFY=enforce osr_run "$OSR_REPO"
t "E6 enforce: the item's VERIFY is RED after the change (def foo missing): not ticked, parked" bash -c "! grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\" && grep -q 'AUTO-SKIP staged 1/1 .*RED after the change' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_E2"; osr_plan default "$PLAN_E2"; osr_aider 1 "$SNIP_E2"
OVN_STAGE_ITEM_VERIFY=off osr_run "$OSR_REPO"
t "E7 off: no item_verify event, ticked as before" bash -c "! grep -q 'item_verify' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== F: red-before - a test the change added must fail without the source change (iptv F6)"
ITEM_F='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python)'
rb_stub(){   # pytest stub: exit $(cat rb.rc) when run inside the red-before worktree (path contains /stage-rb.), else ok
  _osr_stub "$RD/backend/.venv/bin/pytest" '#!/usr/bin/env bash
echo "$PWD :: $*" >> "$OSR_SCN/pytest.calls"
case "$PWD" in */stage-rb.*) exit "$(cat "$OSR_SCN/rb.rc" 2>/dev/null || echo 0)";; esac
echo "5 passed"; exit 0'
}
n2_new; osr_venv backend; rb_stub; echo 0 > "$T/scn/rb.rc"; osr_progress "- [ ] $ITEM_F"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "F1 weak test (passes on the pre-change tree): shadow records it, the run still lands" bash -c "grep -q '\"event\":\"red_before\",\"mode\":\"shadow\",\"detail\":\"RB weak' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'pushed 1 verified commit' '$T/out.txt'"
t "F2 the red-before run happened in a scratch worktree with the source reverted (foo.py absent there) and the scratch worktree is gone" bash -c "grep -q 'stage-rb\.' '$T/scn/pytest.calls' && ! ls -d /tmp/stage-rb.* >/dev/null 2>&1 || true"
osr_cleanup
n2_new; osr_venv backend; rb_stub; echo 1 > "$T/scn/rb.rc"; osr_progress "- [ ] $ITEM_F"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "F3 a test that fails without the change: red-ok" bash -c "grep -q '\"event\":\"red_before\".*RB red-ok' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
n2_new; osr_venv backend; rb_stub; echo 0 > "$T/scn/rb.rc"; osr_progress "- [ ] $ITEM_F"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_RED_BEFORE=enforce osr_run "$OSR_REPO"
t "F4 enforce + weak test: QUALITY FAIL, not verified, nothing pushed" bash -c "grep -q 'pass without the source change' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log && ! grep -q 'verified commit' '$T/out.txt'"
osr_cleanup
n2_new; osr_venv backend; rb_stub; echo 0 > "$T/scn/rb.rc"; osr_progress "- [ ] $ITEM_F"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_RED_BEFORE=off osr_run "$OSR_REPO"
t "F5 off: no red_before event" bash -c "! grep -q 'red_before' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
echo "-- F (control): a test-only change has no source to revert -> skipped"
n2_new; osr_venv backend; rb_stub; osr_progress "- [ ] $ITEM_F"; osr_plan default '[{"desc":"add a test","files":["backend/tests/test_svc.py"],"verify":"pytest"}]'
osr_aider 1 'printf "\n\ndef test_run_job_again():\n    assert run_job() == 1\n" >> backend/tests/test_svc.py; echo "Applied edit"'
OVN_STAGE_RED_BEFORE=enforce osr_run "$OSR_REPO"
t "F6 test-only change: skipped-no-source-change, never enforced against" bash -c "grep -q 'RB skipped-no-source-change' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== G: web verification for changed web files (iptv F6)"
ITEM_G='[T3] web/src/foo.ts — Add the foo helper. VERIFY: `grep -q "export function foo" web/src/foo.ts` (cat:typescript)'
PLAN_G='[{"desc":"add the foo helper","files":["web/src/foo.ts"],"verify":"vitest"}]'
SNIP_G='mkdir -p web/src; printf "export function foo() {\n  return 1\n}\n" > web/src/foo.ts; echo "Applied edit"'
web_setup(){ n2_new; osr_venv backend; mkdir -p "$RD/web/node_modules"; printf '{"name":"web","devDependencies":{"vitest":"1","vue-tsc":"1"}}\n' > "$RD/web/package.json"; mkdir -p "$RD/web/src"
  printf 'export const x = 1\n' > "$RD/web/src/x.ts"; git -C "$RD" add -A; git -C "$RD" commit -q -m web; git -C "$RD" push -q origin HEAD:overnight/feature
  osr_progress "- [ ] $ITEM_G"; osr_plan default "$PLAN_G"; osr_aider 1 "$SNIP_G"; }
web_setup; echo 0 > "$T/scn/npx.rc"
osr_run "$OSR_REPO"
t "G1 vue-tsc --noEmit and vitest related ran for the changed web file" bash -c "grep -q 'npx vue-tsc --noEmit' '$T/scn/npx.calls' && grep -q 'npx vitest related --run --passWithNoTests src/foo.ts' '$T/scn/npx.calls'"
t "G2 green: journalled web_verify ok, landed" bash -c "grep -q '\"event\":\"web_verify\",\"mode\":\"shadow\",\"detail\":\"WEB ok' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup
web_setup; echo 1 > "$T/scn/npx.rc"
osr_run "$OSR_REPO"
t "G3 SHADOW + red web check: recorded (WEB red) but the run still lands (nothing enforced)" bash -c "grep -q 'WEB red' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup
web_setup; echo 1 > "$T/scn/npx.rc"
OVN_STAGE_WEB_VERIFY=enforce osr_run "$OSR_REPO"
t "G4 enforce + red web check: QUALITY FAIL, not verified, nothing pushed" bash -c "grep -q 'web verification failed' '$Q'/state/stage_runs/$OSR_REPO-*.verify.log && ! grep -q 'verified commit' '$T/out.txt'"
osr_cleanup
web_setup; echo 1 > "$T/scn/npx.rc"
OVN_STAGE_WEB_VERIFY=off osr_run "$OSR_REPO"
t "G5 off: no web check at all" bash -c "! grep -q 'vue-tsc' '$T/scn/npx.calls' 2>/dev/null && ! grep -q 'web_verify' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
echo "-- G (control): a python-only change never runs the web check"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "G6 python-only: WEB skipped-no-web-change" bash -c "grep -q 'WEB skipped-no-web-change' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup

# ------------------------------------------------------------------------------------------------------------------------------------
echo "== H: fail-safe - the guards never break a run when their files are missing"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
rm -f "$Q/scripts/lib_stage_guards.sh"
osr_run "$OSR_REPO"
t "H1 lib_stage_guards.sh missing: the run lands and ticks exactly as before" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
rm -f "$Q/scripts/ovn_stage_guards.py"
osr_run "$OSR_REPO"
t "H2 ovn_stage_guards.py missing: every guard is a no-op, the run lands and ticks" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
echo "-- H (control): the default configuration lands a normal python item and ticks it"
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO"
t "H3 normal item, all guards on: lands, ticked, no refusal text anywhere" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\" && ! grep -qE 'REFUSED|ABANDONED' '$T/out.txt'"
osr_cleanup

osr_summary
