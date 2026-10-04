#!/usr/bin/env bash
# test_ovn_stage_runner_flow.sh — runs the REAL ovn_stage_runner.sh end to end in a hermetic fake tree
# (see lib_osr_fixture.sh): startup/guards, item picker, capstone fast path + escalation cap, decompose
# (valid / fenced / invalid / LLM down / godot), watchdog, per-step attempts + every fail_reason, scope guard,
# re-decompose, marking done / partial / escalate, push accounting. The verification layer is in
# test_ovn_stage_runner_verify.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }   # no -q: under pipefail an early-exiting grep SIGPIPEs cat when loaded

# -------- A. lock contention: another runner holds the lock -> exit 0, nothing done --------
echo "== A: lock contention"
osr_new
printf 'acquire_lock(){ return 1; }\n' > "$Q/scripts/lib_lock.sh"
osr_run "$OSR_REPO" "$ITEM_PY"
t "lock held -> exit 0" test "$RC" = 0
t "lock held -> no run log, no ITEM line" bash -c "! grep -q ITEM '$T/out.txt'"
osr_cleanup

# -------- B. argument / clone guards, and the lib_pytest_parallel fallback stub --------
echo "== B: arg guards"
osr_new
osr_run nonexistent-repo
t "missing clone -> 'no clone', exit 1" bash -c "grep -q 'no clone' '$T/out.txt' && [ $RC = 1 ]"
osr_run
t "no args -> non-zero (repo required)" test "$RC" != 0
osr_cleanup

# -------- C. nothing doable --------
echo "== C: no doable item"
osr_new
osr_progress '- [x] [T3] backend/app/done.py — already done' '- [ ] [T1] backend/app/easy.py — tier-1 only' '- [ ] [T3] backend/app/blocked.py — BLOCKED thing'
osr_run "$OSR_REPO"
t "no doable T3+ item -> exit 0 with message" bash -c "grep -q 'no doable T3+ item found' '$T/out.txt' && [ $RC = 0 ]"
kb "early 'no doable item' exit must release the dedicated-mode pause (state/PAUSED left behind, cleanup trap not yet installed)" test ! -f "$Q/state/PAUSED"
osr_cleanup

# -------- D. item picker --------
echo "== D: picker"
osr_new
osr_plan default '[]'
osr_progress \
  '- [ ] [CLAUDE] [T3] backend/app/esc.py — escalated py' \
  '- [ ] [AUTO-SKIP x] [T3] backend/app/skip.py — skipped' \
  '- [ ] [T3] tests/test_codex.gd — godot test target' \
  '- [ ] [T3] web/src/Foo.vue — Wire Foo into Bar' \
  '- [ ] [T3] backend/app/wire.py — wire thing into other' \
  '- [ ] backend/app/real.py ·T4· — Real python item'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "python item preferred, tier parsed from ·T4·" G "ITEM (T4)"
t "python pick is the real.py line" bash -c "grep 'ITEM (T4)' '$T/out.txt' | grep -q real.py"
t "decompose producing [] -> decompose_failed exit 1" bash -c "[ $RC = 1 ] && grep -q 'decompose produced no steps' '$T/out.txt'"
t "decompose_failed is journaled" J 'decompose_failed'
osr_progress \
  '- [ ] [CLAUDE] [T3] backend/app/esc.py — escalated py' \
  '- [ ] [T3] tests/test_codex.gd — godot test target' \
  '- [ ] [T3] web/src/Foo.vue — Wire Foo into Bar' \
  '- [ ] [T3] backend/app/wire.py — wire thing into other'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "no plain python item -> falls back to first doable (the .vue), default tier 3 from [T3]" bash -c "grep 'ITEM (T3)' '$T/out.txt' | grep -q Foo.vue"
osr_cleanup

# -------- E. capstone fast path --------
echo "== E: capstone fast path"
CAP_PASS='[T3] backend/app/foo.py — Run the full test suite to confirm the foo change caused zero regressions. VERIFY: `true` (cat:test)'
CAP_FAIL='[T3] backend/app/foo.py — Run the full test suite to confirm the foo change caused zero regressions. VERIFY: `echo boom; false` (cat:test)'
osr_new
osr_progress "- [ ] $CAP_PASS"
touch "$T/reject_once"     # first push is rejected -> the pull --rebase + retry fallback must still land it
osr_run "$OSR_REPO"
t "capstone PASSED -> exit 0, marked done" bash -c "[ $RC = 0 ] && grep -q 'regression-check PASSED' '$T/out.txt'"
t "origin progress has the auto-verified [x] line (push fallback worked)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'auto-verified via direct VERIFY run'"
t "capstone_verified journaled" J capstone_verified
osr_cleanup

osr_new
osr_progress "- [ ] $CAP_FAIL"
osr_run "$OSR_REPO"
t "capstone FAIL #1 -> exit 1, left open, detection journaled" bash -c "[ $RC = 1 ] && grep -q 'regression-check FAILED' '$T/out.txt'"
t "capstone_regression_detected journaled" J capstone_regression_detected
t "count file written after 1st detection" bash -c "ls '$Q'/state/stage_runs/capstone_fails/*.count >/dev/null 2>&1"
t "item not yet escalated" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '\[CLAUDE\]'"
osr_run "$OSR_REPO"
t "capstone FAIL #2 -> exit 1 and hits the cap" G "hit the 2-detection cap"
t "escalated to [CLAUDE] on origin" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '\[T3\]\|\[CLAUDE\] \[T3\]' && git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[CLAUDE\]'"
t "capstone_escalated journaled with n=2" J '"event":"capstone_escalated","n":2'
t "escalation commit pushed" bash -c "git -C '$O' log --format=%s overnight/feature | grep -q 'escalate capstone regression-check item'"
osr_run "$OSR_REPO"
t "picker moves past the escalated item ([CLAUDE] excluded)" G "no doable T3+ item found"
osr_cleanup

# item passed as an ARG that is not in the queue file: lineno empty on both the pass and the escalate path
osr_new
osr_run "$OSR_REPO" "$CAP_PASS"
t "capstone via arg, item not in queue file -> passes, no queue edit" bash -c "[ $RC = 0 ] && grep -q 'regression-check PASSED' '$T/out.txt'"
OVN_STAGE_CAPSTONE_CAP=1 osr_run "$OSR_REPO" "$CAP_FAIL"
t "cap=1 escalates on first failure; with no queue line nothing is edited" bash -c "[ $RC = 1 ] && grep -q 'hit the 1-detection cap' '$T/out.txt'"
t "capstone escalation event still journaled" J capstone_escalated
# capstone phrase but no VERIFY clause -> not a fast path, goes on to decompose
osr_plan default '[]'
osr_run "$OSR_REPO" '[T3] backend/app/foo.py — Run the full test suite to confirm there were no regressions (cat:test)'
t "capstone wording without VERIFY falls through to decompose" G "decompose produced no steps"
osr_cleanup

# godot capstone: bare `godot` in VERIFY is rewritten to the box path; asset import is warmed first
osr_new
osr_godot ok
osr_run "$OSR_REPO" '[T3] game/x.gd — Run the whole suite to confirm it caused no regressions. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd` (cat:test)'
t "godot capstone VERIFY rewritten to godot4 and run" bash -c "[ $RC = 0 ] && grep -q 'godot4 --headless -s addons/gut/gut_cmdln.gd' '$T/scn/godot.calls'"
t "godot --import warm-up ran before VERIFY" bash -c "head -1 '$T/scn/godot.calls' | grep -q -- '--import'"
osr_cleanup

# -------- F. decompose --------
echo "== F: decompose"
osr_new
osr_plan default 'Sure! Here is the plan:
```json
[{"desc":"first","files":["backend/app/foo.py"],"verify":"v"},"junk",{"nodesc":1},{"desc":"second"}]
```
Done.'
OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "JSON wrapped in prose+fences parsed; junk/no-desc filtered -> 2 steps" G "decomposed into 2 sub-steps"
t "watchdog rearm line logged with NSTEPS" G "watchdog rearmed for"
t "plan journaled" J '"event":"decomposed"'
t "steps with no edit are BLOCKED; item_arg mode -> exit 0, summary 0/2" bash -c "grep -q 'step 0 BLOCKED' '$T/out.txt' && grep -q 'DONE: 0/2 steps landed' '$T/out.txt'"
t "blocked verdict journaled" J '"verdict":"blocked"'
t "no-edit fail_reason journaled" J '"fail_reason":"no-edit"'
t "item_arg mode never touches queue.sh (no hold/release)" test ! -f "$Q/state/queue.calls"
t "decompose prompt carries the real source layout" bash -c "grep -q 'backend/app/svc.py' '$T/llm/body.1'"
t "decompose call's token spend logged" bash -c "grep -q 'stage-decompose $OSR_REPO 11 7' '$Q/state/tokens.calls'"
t "dedicated mode cleaned up its pause on normal exit" test ! -f "$Q/state/PAUSED"
osr_cleanup

osr_new
osr_plan default '[{"desc":"a"},{"desc":"b"},{"desc":"c"},{"desc":"d"}]'
OVN_STAGE_MAX_STEPS=2 OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_REDECOMP=0 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "plan truncated to OVN_STAGE_MAX_STEPS" G "decomposed into 2 sub-steps"
osr_cleanup

osr_new
osr_plan default '[{bad json]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "invalid JSON -> decompose-no-steps abort (exit 1)" bash -c "[ $RC = 1 ] && grep -q 'decompose produced no steps' '$T/out.txt'"
osr_cleanup

osr_new
touch "$T/llm/fail"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "LLM down: 4 empty attempts with backoff logged, then abort" bash -c "grep -q 'llm attempt 4 got empty' '$Q/logs/ovn_stage_runner.log' && [ $RC = 1 ] && grep -q 'decompose produced no steps' '$T/out.txt'"
osr_cleanup

osr_new
osr_godot ok
osr_plan default '[]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" '[T3] game/x.gd — Add static function foo to x.gd. VERIFY: `gdparse game/x.gd` (cat:godot)'
t "godot item gets the SOURCE-ONLY decompose rules" bash -c "grep -q 'GODOT 4 MODE' '$T/llm/body.1'"
osr_new
osr_plan default '[]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "non-godot item gets the self-verifying rules" bash -c "grep -q 'SELF-VERIFYING' '$T/llm/body.1' && ! grep -q 'GODOT 4 MODE' '$T/llm/body.1'"
osr_cleanup

# worktree creation fails (remote unreachable AND tracking ref gone)
osr_new
osr_plan default "$PLAN_FOO"
git -C "$RD" remote set-url origin "$T/nonexistent.git"; git -C "$RD" update-ref -d refs/remotes/origin/overnight/feature
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "worktree failure -> 'worktree failed', exit 1" bash -c "[ $RC = 1 ] && grep -q 'worktree failed' '$T/out.txt'"
osr_cleanup

# -------- G. self-watchdog kills a hung runner (and its descendants) --------
echo "== G: watchdog fire"
osr_new
touch "$T/llm/hang"
s0=$(date +%s)
OSR_WD_ARG=1234 OVN_STAGE_STARTUP_TIMEOUT=1234 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
s1=$(date +%s)
kb "hung LLM call: watchdog must SIGKILL the runner (rc 137) right after it fires (_kt walks pgrep -P \$_self, which includes the watchdog subshell itself -> it kill -9s ITSELF first and never reaches kill -9 \$_self)" bash -c "[ $RC = 137 ] && [ $((s1-s0)) -lt 15 ]"
osr_cleanup

# -------- H. happy path, auto-pick: 2 steps, wire context, source auto-add, tokens, marking done --------
echo "== H: happy path (auto-pick)"
ITEM_WIRE='[T3] backend/app/svc.py — Wire `foo` into svc.run_job and cover it with a test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python)'
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_WIRE"
osr_plan default '[{"desc":"add foo helper and test","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"},{"desc":"call foo from run_job","files":["backend/app/svc.py"],"verify":"pytest backend/tests"}]'
osr_aider 1 "$SNIP_FOO"
osr_aider 2 'printf "from app.foo import foo\n\ndef run_job():\n    return foo()\n" > backend/app/svc.py'
osr_run "$OSR_REPO"
t "run ends 2/2 landed, verified, pushed" bash -c "[ $RC = 0 ] && grep -q 'independent full-verify: PASSED' '$T/out.txt' && grep -q 'pushed 2 verified commit' '$T/out.txt' && grep -q 'DONE: 2/2 steps landed (100%)' '$T/out.txt'"
t "both step commits are on origin" bash -c "git -C '$O' log --format=%s overnight/feature | grep -c 'staged step' | grep -qx 2"
t "origin progress item checked off with staged 2/2 tag" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] .*staged 2/2 DONE'"
t "queue.sh hold then release around the progress edit" bash -c "[ \"\$(cat '$Q/state/queue.calls')\" = \"\$(printf 'hold %s\nrelease %s' $OSR_REPO $OSR_REPO)\" ]"
t "target-function body injected into the step prompt" bash -c "grep -q 'EXACT function you must modify is run_job in backend/app/svc.py' '$T/scn/aider.args.1'"
t "symbol-defining source auto-added as --file on step 2" bash -c "grep -A1 -- '--file' '$T/scn/aider.args.2' | grep -q 'backend/app/foo.py'"
t "first attempt runs rich: architect + AGENTS.md + map 3072" bash -c "grep -q -- '--architect' '$T/scn/aider.args.1' && grep -q AGENTS.md '$T/scn/aider.args.1' && grep -qx 3072 '$T/scn/aider.args.1'"
t "token accounting parsed (2.5k sent + 340 recv)" J '"tokens_sent":2500,"tokens_recv":340'
t "verify + summary journaled with commits_pushed 2" bash -c "osr_jsonl() { cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl; }; osr_jsonl | grep '\"verified\":true,\"commits_pushed\":2' >/dev/null"
t "dedicated pause released at exit" test ! -f "$Q/state/PAUSED"
t "semantic check logged OK for the wired symbol" bash -c "grep -q 'semantic OK: backend/app/svc.py uses foo' '$Q'/state/stage_runs/*.verify.log"
osr_cleanup

# -------- I. failure taxonomy inside one item (multifile:no) --------
echo "== I: per-step failure reasons + scope guard"
ITEM_MF='[T3] backend/app/m0.py — Add m0 helpers (multifile:no) VERIFY: `pytest backend/tests`'
mk(){ printf 'printf "def f%s():\\n    return %s\\n" > backend/app/m%s.py' "$1" "$1" "$1"; }
osr_new; osr_venv backend
osr_plan default '[{"desc":"m0","files":["backend/app/m0.py"],"verify":"t"},{"desc":"m1","files":["backend/app/m1.py"],"verify":"t"},{"desc":"m2","files":["backend/app/m2.py"],"verify":"t"},{"desc":"m3","files":["backend/app/m3.py"],"verify":"t"},{"desc":"m4","files":["backend/app/m4.py"],"verify":"t"}]'
osr_aider 1 'echo "litellm.ContextWindowExceededError: context size has been exceeded"'
osr_aider 2 "$(mk 0)"
# 2026-09-30: a genuine hang killed by the step timeout (was a 3s sleep vs a 14s timeout: the dur>=TIMEOUT-12 rule then
# also flagged every ordinary step under heavy load/xtrace as a timeout). Timeout 30 => threshold 18s; aider #3 sleeps past it.
osr_aider 3 "$(mk 1); /bin/sleep 100"
osr_aider 4 "$(mk 1)"
osr_aider 5 'echo "I looked but changed nothing"'
osr_aider 6 "$(mk 2)"
osr_aider 7 "$(mk 3); echo 'FAILED test_m3 assert 1 == 2'"
osr_aider 8 "$(mk 3)"
osr_aider 9 "$(mk 4); echo 'def junk(): return 1' > backend/app/junk.py"
osr_aider 10 "$(mk 4); printf 'from app.m4 import f4\n\ndef test_f4():\n    assert f4() == 4\n' > backend/tests/test_m4.py"
# autotest calls happen only for attempts that edited and did not hit ctx/timeout: #4 is s3-attempt-1 -> red
osr_autotest 4 'echo "FAILED tests/test_m3.py::test_f3 - assert 1 == 2"; exit 1'
OVN_STAGE_STEP_TIMEOUT=30 OVN_STAGE_REDECOMP=0 OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_MF"
t "all 5 steps eventually land; item_arg mode -> verified + pushed" bash -c "grep -q 'DONE: 5/5 steps landed' '$T/out.txt' && grep -q 'pushed 5 verified commit' '$T/out.txt'"
t "context-exceeded detected" J '"fail_reason":"context-exceeded"'
t "step timeout detected" J '"fail_reason":"timeout"'
t "no-edit detected" J '"fail_reason":"no-edit"'
t "scope-violation detected and names the junk file" bash -c "osr_jsonl(){ cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl; }; osr_jsonl | grep '\"fail_reason\":\"scope-violation\"' | grep -q junk.py"
t "red scoped gate classified by ovn_classify_fail.sh with an excerpt" bash -c "cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | jq -c 'select(.step==3 and .attempt==1)' | jq -e '.verdict==\"fail\" and (.fail_reason|length)>0 and (.excerpt|test(\"assert\"))'"
t "after context blow-up next attempt shrinks: map 1536, no architect, no AGENTS.md" bash -c "grep -qx 1536 '$T/scn/aider.args.2' && ! grep -q -- '--architect' '$T/scn/aider.args.2' && ! grep -q AGENTS.md '$T/scn/aider.args.2'"
t "scope-rejected step REJECTED line logged" G "REJECTED (scope)"
t "same-basename test companion tolerated on multifile:no" bash -c "git -C '$O' show overnight/feature:backend/tests/test_m4.py | grep -q f4"
t "rejected attempt's junk file did not survive" bash -c "! git -C '$O' show overnight/feature:backend/app/junk.py"
t "item_arg mode: queue.sh untouched" test ! -f "$Q/state/queue.calls"
osr_cleanup

# -------- J. re-decompose --------
echo "== J: re-decompose"
osr_new; osr_venv backend
osr_plan 1 '[{"desc":"big step","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest"}]'
osr_plan 2 '[{"desc":"sub one","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest one"},{"desc":"sub two","files":["backend/app/bar.py"],"verify":"pytest two"}]'
osr_aider 3 "$SNIP_FOO"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "step fails twice -> re-decomposed smaller" bash -c "grep -q 'failing after 2 — re-decomposing smaller' '$T/out.txt' && grep -q 'redecomposed' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "sub-step 0.0 passes, sub-step 0.1 BLOCKED, parent returns partial progress" bash -c "grep -q 'step 0.0 PASS' '$T/out.txt' && grep -q 'sub-step 0.1 BLOCKED' '$T/out.txt'"
t "partial progress still verified + pushed" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt'"
osr_cleanup

osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
osr_plan 1 '[{"desc":"big step","files":["backend/app/foo.py"],"verify":"pytest"}]'
osr_plan 2 '[{"desc":"only one sub","files":["backend/app/foo.py"],"verify":"pytest"}]'
osr_run "$OSR_REPO"
t "re-decompose yielding <2 pieces -> step BLOCKED" G "step 0 BLOCKED (could not land after retries + re-decomp)"
t "landed nothing in auto mode -> escalated to Claude (queue line tagged, committed, pushed)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this' && git -C '$O' log --format=%s overnight/feature | grep -q 'escalate staged T3 item to Claude' && grep -q 'escalated to Claude' '$T/out.txt'"
t "escalation wrapped in queue hold/release" bash -c "grep -qx 'hold $OSR_REPO' '$Q/state/queue.calls' && grep -qx 'release $OSR_REPO' '$Q/state/queue.calls'"
t "summary says 0 passed" J '"passed":0,"total":1'
osr_cleanup

# -------- K. partial landing, auto mode: park the remainder --------
echo "== K: partial + push-race"
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"t"},{"desc":"add bar","files":["backend/app/bar.py"],"verify":"t"}]'
osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "1/2 landed -> verified, pushed, remainder parked with AUTO-SKIP staged 1/2" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged 1/2 — 1 step(s) blocked'"
t "item NOT checked off on a partial" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\]'"
t "partial summary journaled" J '"passed":1,"total":2'
osr_cleanup

osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
osr_plan default "$PLAN_FOO"
osr_aider 1 "$SNIP_FOO"
touch "$T/reject_always"
osr_run "$OSR_REPO"
t "verified but push lost the race -> 'push FAILED', not counted" bash -c "grep -q 'push FAILED (fleet racing)' '$T/out.txt'"
t "...and the item is left OPEN for a clean re-attempt" bash -c "grep -q 'leaving item OPEN for a clean re-attempt' '$T/out.txt' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'staged'"
t "summary commits_pushed 0 despite verified" bash -c "cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | grep -q '\"verified\":true,\"commits_pushed\":0'"
osr_cleanup

# -------- L. godot step: Godot-4 prompt + GODOT4.md, GUT full verify --------
echo "== L: godot step"
osr_new
osr_venv backend   # 2026-09-30: fail-closed verify - the fixture repo carries python tests, so its live venv must exist for verification to run
osr_godot ok
osr_plan default '[{"desc":"add foo to x.gd","files":["game/x.gd"],"verify":"gdparse game/x.gd"}]'
osr_aider 1 'mkdir -p game; printf "static func foo() -> int:\n\treturn 1\n" > game/x.gd'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" '[T3] game/x.gd — Add static function foo to x.gd. VERIFY: `gdparse game/x.gd` (cat:godot)'
t "godot step: GODOT4.md passed via --read and the Godot-4 message used" bash -c "grep -q GODOT4.md '$T/scn/aider.args.1' && grep -q 'GODOT 4.x GDScript task' '$T/scn/aider.args.1'"
t "godot full verify (GUT) passed and landed" bash -c "grep -q 'independent full-verify: PASSED' '$T/out.txt' && grep -q -- '-- GUT FULL --' '$Q'/state/stage_runs/*.verify.log"
osr_cleanup

osr_summary
