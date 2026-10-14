#!/usr/bin/env bash
# N4 stage-runner-waste, Part 1 (2026-10-13): OVN_STAGE_EMPTY_FILE. A staged step whose aider run left a 0-byte DECLARED file used to pass the per-step gate (an empty test file collects 0 tests;
# `git diff --shortstat` ignores untracked files, hence 'nostat') and died 15-25 minutes later on the final full_verify '-- QUALITY FAIL: <file> is a 0-byte file' (8 staged runs / 481k step tokens in 48h:
# billwatch test_auth_register_audit.py x2, gitlark test_memory_rekey.py x2, iptv junk paths app/jobs/test_parental_lockout.py x3, TAA test_visual_diffs_api.py).
# Drives the REAL ovn_stage_runner.sh in the hermetic fixture (lib_osr_fixture.sh): stub aider writes the files, stub LLM returns the plan. Needs GNU sed + bash 5 (run on the box).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_EMPTY_FILE NTFY_SERVER NTFY_TOPIC
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
# aider writes a real foo.py but leaves the DECLARED test file empty
SNIP_EMPTY_DECL='mkdir -p backend/app backend/tests
printf "def foo():\n    return 1\n" > backend/app/foo.py
: > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
# aider writes the good files PLUS an empty junk file at a path nobody declared (the iptv shape)
SNIP_EMPTY_JUNK="$SNIP_FOO
mkdir -p backend/app/jobs
: > backend/app/jobs/test_foo_junk.py"
SNIP_ONLY_JUNK='mkdir -p backend/app/jobs
: > backend/app/jobs/test_foo_junk.py
echo "Applied edit"'
SNIP_EMPTY_INIT="$SNIP_FOO
mkdir -p backend/app/jobs
: > backend/app/jobs/__init__.py"
setup(){ osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; }

echo "== A: a DECLARED empty file fails the step with fa=empty-file and the retry is told why"
setup; osr_aider 1 "$SNIP_EMPTY_DECL"; osr_aider 2 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "A1 attempt 1 FAILs with the empty-file reason (not a pass)" G "step 0 att 1 FAIL (empty-file"
t "A2 the journal row carries fail_reason empty-file and names the file" bash -c "osr_jsonl(){ cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl; }; osr_jsonl | jq -e 'select(.fail_reason==\"empty-file\") | .excerpt | contains(\"backend/tests/test_foo.py\")'"
t "A3 the SECOND aider call's prompt carries the empty-file feedback" bash -c "grep -q 'EMPTY (0 bytes)' '$T/scn/aider.args.2' && grep -q 'backend/tests/test_foo.py' '$T/scn/aider.args.2'"
t "A4 the FIRST aider call's prompt has no such feedback" bash -c "! grep -q 'EMPTY (0 bytes)' '$T/scn/aider.args.1'"
t "A5 attempt 2 writes the full content and the step PASSes" G "step 0 PASS (att 2"
t "A6 the run lands 1/1 and is verified + pushed" bash -c "grep -q 'DONE: 1/1 steps landed' '$T/out.txt' && grep -q 'independent full-verify: PASSED' '$T/out.txt' && grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup

echo "== B: empty file on EVERY attempt -> the step is BLOCKED at the step, the 25-minute final verify never runs"
setup; osr_aider default "$SNIP_EMPTY_DECL"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "B1 both attempts FAIL (empty-file)" bash -c "grep -c 'FAIL (empty-file' '$T/out.txt' | grep -qx 2"
t "B2 the step is BLOCKED and nothing is committed (0/1 landed)" bash -c "grep -q 'step 0 BLOCKED' '$T/out.txt' && grep -q 'DONE: 0/1 steps landed' '$T/out.txt'"
t "B3 no independent full-verify ran (it would have taken minutes for a guaranteed failure)" NG "independent full-verify"
osr_cleanup

echo "== C: an UNDECLARED empty file is reaped and the step carries on"
setup; osr_aider 1 "$SNIP_EMPTY_JUNK"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "C1 'reaped empty undeclared file' is logged for the junk path" G "reaped empty undeclared file: backend/app/jobs/test_foo_junk.py"
t "C2 the step PASSes on attempt 1 (no retry burned)" G "step 0 PASS (att 1"
t "C3 the junk file is NOT in the pushed commit" bash -c "! git -C '$O' ls-tree -r --name-only overnight/feature | grep -q test_foo_junk"
t "C4 the real files ARE pushed" bash -c "git -C '$O' ls-tree -r --name-only overnight/feature | grep -q backend/app/foo.py"
t "C5 an empty_file_reaped event is journaled" J '"event":"empty_file_reaped"'
osr_cleanup

echo "== D: ONLY an empty junk file -> after the reap the tree is unchanged = no-edit"
setup; osr_aider default "$SNIP_ONLY_JUNK"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D1 the junk is reaped and the attempt is a no-edit (not a pass)" bash -c "grep -q 'reaped empty undeclared file' '$T/out.txt' && grep -q 'FAIL (no-edit' '$T/out.txt'"
osr_cleanup

echo "== E: control - non-empty declared files are untouched by the new check"
setup; osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1 PASS on attempt 1, no reap, no empty-file" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -qE 'reaped|empty-file' '$T/out.txt'"
t "E2 landed 1/1" G "DONE: 1/1 steps landed"
osr_cleanup

echo "== F: an empty __init__.py is left exactly as before (neither reaped nor a step failure)"
setup; osr_aider 1 "$SNIP_EMPTY_INIT"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F1 not reaped, step PASSes (the pre-existing final 0-byte gate decides, as before)" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -q 'reaped' '$T/out.txt'"
osr_cleanup

echo "== F2: other empty-by-design marker files (py.typed, .gdignore) are left alone exactly like __init__.py"
SNIP_EMPTY_MARKERS="$SNIP_FOO
: > backend/app/py.typed
: > backend/app/.gdignore"
setup; osr_aider 1 "$SNIP_EMPTY_MARKERS"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F2a undeclared empty py.typed / .gdignore are NOT reaped and the step PASSes" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -q 'reaped' '$T/out.txt' && ! grep -q 'empty_file_reaped' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
PLAN_PT='[{"desc":"add foo helper and the py.typed marker","files":["backend/app/foo.py","backend/app/py.typed"],"verify":"pytest backend/tests/test_foo.py"}]'
SNIP_PT="$SNIP_FOO
: > backend/app/py.typed"
osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN_PT"; osr_aider 1 "$SNIP_PT"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F2b a DECLARED empty py.typed is not an empty-file failure (marker file)" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -q 'empty-file' '$T/out.txt'"
osr_cleanup

echo "== G: kill switch OVN_STAGE_EMPTY_FILE=off restores the old behaviour (declared empty passes the step, dies at the final verify)"
setup; osr_aider 1 "$SNIP_EMPTY_DECL"
OVN_STAGE_EMPTY_FILE=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "G1 the step PASSes (nostat) even though the declared file is empty" bash -c "grep -q 'step 0 PASS (att 1' '$T/out.txt' && ! grep -q 'empty-file' '$T/out.txt'"
t "G2 ... and the FINAL verify rejects it: QUALITY FAIL 0-byte" bash -c "cat '$Q'/state/stage_runs/$OSR_REPO-*.verify.log | grep -q 'QUALITY FAIL: backend/tests/test_foo.py is a 0-byte file'"
osr_cleanup
osr_summary
