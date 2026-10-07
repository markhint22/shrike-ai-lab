#!/usr/bin/env bash
# Zero-landing RETRY BUDGET in the real ovn_stage_runner.sh (2026-10-07). A staged run that lands NOTHING used to route the whole item to Claude at once
# ('[AUTO-SKIP staged: 27B could not land this (beyond it) - route to CLAUDE]'); one bad attempt (flaky box, baseline-red test, unlucky plan) cost a Claude
# line per step (105 open [CLAUDE] lines, ~60% noise). Now: attempts 1..cap-1 keep the item OPEN and record why; the next decomposition is told why the
# last attempt failed; only the cap routes to Claude; a run that lands anything clears the state. OVN_STAGE_ZERO_CAP=1 = the old immediate escalation.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP NTFY_SERVER NTFY_TOPIC
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; osr_cleanup' EXIT
PLAN_STUCK1='[{"desc":"big step","files":["backend/app/foo.py"],"verify":"pytest"}]'
PLAN_STUCK2='[{"desc":"only one sub","files":["backend/app/foo.py"],"verify":"pytest"}]'
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
prog(){ osr_origin_file OVERNIGHT_PROGRESS.md; }
zc(){ cat "$Q"/state/item_fails/stage-"$OSR_REPO".*.zerocount 2>/dev/null; }
stuck_run(){ rm -f "$T/llm/n" "$T/scn/aider.n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; osr_run "$OSR_REPO"; }

echo "=== Z1: default budget (3): attempts 1 and 2 keep the item open, attempt 3 routes it ==="
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
stuck_run
t "attempt 1: runner really landed 0/1 (fixture sanity)" J '"passed":0,"total":1'
t "attempt 1: item is still OPEN and untagged (no AUTO-SKIP, no [CLAUDE])" bash -c "prog_out=\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md); echo \"\$prog_out\" | grep -q '^- \[ \] \[T3\] backend/app/foo.py' && ! echo \"\$prog_out\" | grep -qE 'AUTO-SKIP|CLAUDE'"
t "attempt 1: zerocount = 1" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount)\" = 1 ]"
t "attempt 1: the reason is recorded (priorfail says 'attempt 1 of 3')" bash -c "grep -q 'attempt 1 of 3' '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail"
t "attempt 1: zero_landing_attempt journaled with attempt=1 cap=3" bash -c "grep -q '\"event\":\"zero_landing_attempt\",\"attempt\":1,\"cap\":3' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "attempt 1: queue released (never left held)" bash -c "grep -qx 'release $OSR_REPO' '$Q/state/queue.calls'"
t "attempt 1: the first decomposition prompt had NO previous-failure block (nothing to carry yet)" bash -c "! grep -l 'PREVIOUS ATTEMPT' '$T'/llm/body.* >/dev/null 2>&1"
stuck_run
t "attempt 2: still OPEN, zerocount = 2" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && [ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount)\" = 2 ]"
t "attempt 2: the decomposition prompt CARRIES the previous failure ('PREVIOUS ATTEMPT' + 'attempt 1 of 3')" bash -c "grep -l 'PREVIOUS ATTEMPT' '$T/llm'/body.* 2>/dev/null | head -1 | xargs grep -q 'attempt 1 of 3'"
stuck_run
t "attempt 3 (cap): NOW routed - '[AUTO-SKIP staged: 27B could not land this ...]'" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this'"
t "attempt 3: counters cleared after the routing" bash -c "! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount >/dev/null 2>&1 && ! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail >/dev/null 2>&1"
osr_cleanup

echo "=== Z2: OVN_STAGE_ZERO_CAP=1 restores the immediate escalation (kill switch) ==="
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_STAGE_ZERO_CAP=1 osr_run "$OSR_REPO"
t "cap=1: first zero-landing run routes at once (old behaviour)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this'"
osr_cleanup

echo "=== Z3: a run that LANDS something clears the retry state; garbage cap falls back to 3 ==="
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
stuck_run
t "setup: attempt 1 left zerocount=1 and a priorfail" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount)\" = 1 ] && ls '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail >/dev/null 2>&1"
rm -f "$T/llm/n" "$T/scn/aider.n"
osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"t"}]'
osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "a landing run: 1/1 landed (fixture sanity)" J '"passed":1,"total":1'
t "a landing run clears zerocount and priorfail" bash -c "! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail >/dev/null 2>&1"
osr_cleanup
osr_new; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_STAGE_ZERO_CAP=abc osr_run "$OSR_REPO"
t "garbage OVN_STAGE_ZERO_CAP falls back to 3 (item stays open on attempt 1)" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && [ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount)\" = 1 ]"
osr_summary
