#!/usr/bin/env bash
# Hermetic end-to-end tests of run_aider_fix_task's push phase and final statuses (run_overnight.sh, second half):
# push with rebase-retry (pushed(after-rebase)), error-transient(push-diverged), plain "pushed" when no verifier ran,
# model/API error status, plain no-op.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

# ---------- A: push rejected (peer pushed meanwhile), rebase clean -> pushed(after-rebase) ----------
mk_case rebase_ok
export OTHER
scout_ok
aplan 2 'gc app.py "def mine(): return 1" "feat: mine"
( cd "$OTHER" && git fetch -q origin && git checkout -q -B claude/feature origin/claude/feature && echo "peer" > peer.txt && git add -A && git commit -q -m "peer commit" && git push -q origin claude/feature ) >/dev/null 2>&1'
run_case "$PROMPT_DEFAULT" true
eq "A: rebase-retry push -> pushed(after-rebase)" "$OUT" "pushed(after-rebase)"
ok "A: rejection logged" 'logged "push rejected; rebasing onto origin/claude/feature and retrying"'
ok "A: both my commit and the peer commit on origin" 'origin_has claude/feature "feat: mine" && origin_has claude/feature "peer commit"'

# ---------- B: push rejected, rebase conflicts -> abort, resync, error-transient(push-diverged) ----------
mk_case rebase_conflict
export OTHER
scout_ok
aplan 2 'gc app.py "def mine(): return 1" "feat: mine"
( cd "$OTHER" && git fetch -q origin && git checkout -q -B claude/feature origin/claude/feature && echo "def theirs(): return 2" >> app.py && git add -A && git commit -q -m "peer conflicting" && git push -q origin claude/feature ) >/dev/null 2>&1'
run_case "$PROMPT_DEFAULT" true
eq "B: conflicting rebase -> error-transient(push-diverged)" "$OUT" "error-transient(push-diverged - resynced, retry next cycle)"
eq "B: clone resynced to origin" "$(git -C "$REPO" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse claude/feature)"
ok "B: no rebase left in progress" '[ ! -d "$REPO/.git/rebase-merge" ] && [ ! -d "$REPO/.git/rebase-apply" ]'
ok "B: my commit did not land" '! origin_has claude/feature "feat: mine"'

# ---------- C: origin rejects the push outright on a brand-new branch (pull --rebase cannot even start) ----------
mk_case origin_reject
scout_ok
aplan 2 'gc app.py "def mine(): return 1" "feat: mine"'
printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
run_case "$PROMPT_DEFAULT" false claude/brand-new
eq "C: hard push failure -> error-transient(push-diverged)" "$OUT" "error-transient(push-diverged - resynced, retry next cycle)"

# ---------- D: no verifier in repo -> plain "pushed" (no tests:pass tag, no item-hash credit lines) ----------
mk_case noverify noverify
scout_ok
aplan 2 'gc app.py "def mine(): return 1" "feat: mine

DONE: Fix \`hello\` in app.py to return 2"; gc tests/test_mine.py "def test_mine(): assert True" "test: mine"'
run_case
eq "D: verification=none -> bare pushed" "$OUT" "pushed"
ok "D: no item-hash credit lines when verify was not a pass" '! logged "auto-credit: item-hash"'

# ---------- E: final statuses without a commit ----------
mk_case apierr
scout_ok
aplan 2 'echo "litellm.BadRequestError: bad request"'
run_case
eq "E: API error text, no commit -> error(model/API error - see log)" "$OUT" "error(model/API error - see log)"
mk_case traceback
scout_ok
aplan 2 'printf "Traceback (most recent call last):\n  File x\nValueError\n"'
run_case
eq "E: python traceback, no commit -> error(model/API error - see log)" "$OUT" "error(model/API error - see log)"
mk_case plain_noop
scout_ok
aplan 2 'echo "I looked at app.py but could not come up with a change."'
run_case
eq "E: nothing happened -> no-op" "$OUT" "no-op"
mk_case no_git
mkdir -p "$CASE_DIR/notarepo"
OUT="$(run_aider_fix_task t-app "$CASE_DIR/notarepo" "$PROMPT_DEFAULT" claude/feature false "$TASK_LOG" "" false 2 "" 60 2>/dev/null | tail -1)"
ok "E: missing .git -> error(no .git ...)" '[[ "$OUT" == "error: no .git at"* ]]'

# ---------- F: lastfail-free second run: re-running after a landed cycle with nothing new stays no-op ----------
mk_case second_cycle
scout_ok
aplan 2 'gc app.py "def first(): return 1" "feat: first"'
run_case
ok "F: first cycle pushed" '[[ "$OUT" == pushed* ]]'
rm -f "$CASE_DIR/aider.n" "$CASE_DIR/aider.2.sh"
aplan default 'echo "nothing more to do"'
aplan 1 'scout PROCEED "polish" "app.py"'
run_case "$PROMPT_DEFAULT" true
eq "F: second persistent cycle with no diff -> no-op" "$OUT" "no-op"

summary
