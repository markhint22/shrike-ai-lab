#!/usr/bin/env bash
# QA harness-X follow-up X-a, end to end through the REAL run_aider_fix_task (stub aider): a green cycle whose item VERIFY outruns the auto-credit
# timeout must still land (pushed(tests:pass)), leave the item OPEN, log one deduped distinct alert, write the indet-hash marker, and NOT be billed
# as a failed attempt by the real ovn_item_guard.sh. Benign twin: the same item with a VERIFY that fits is credited as before.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
G="$Q/scripts/ovn_item_guard.sh"
[ -f "$G" ] || { echo "  SKIP: ovn_item_guard.sh not found"; exit 0; }
cd "$W" || exit 1

SLOW='- [ ] app.py — Make hello return 2. VERIFY: `sleep 3 && grep -q "return 2" app.py`'
mk_case e2e_slow; scout_ok
aplan 2 "gc OVERNIGHT_PROGRESS.md '$SLOW' 'docs: queue item'
printf 'def hello():\n    return 2\n' > app.py; git add -A; git commit -q -m 'feat: hello returns 2'"
OVN_AC_VERIFY_TIMEOUT=1 OVN_AC_VERIFY_TIMEOUT_HEAVY=1 run_case
ok "slow VERIFY: the cycle still lands as pushed(tests:pass)" '[[ "$OUT" == pushed\(tests:pass\)* ]]'
ok "slow VERIFY: item stays OPEN on the pushed branch" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[ \] app.py — Make hello"'
ok "slow VERIFY: no auto-credit commit" '! origin_has claude/feature "auto-credit item(s)"'
ok "slow VERIFY: logged as INDETERMINATE (timed out rc=124 after 1s), never 'clause FAILED'" 'logged "INDETERMINATE line" && logged "VERIFY timed out (rc=124) after 1s" && ! logged "clause FAILED"'
eq "slow VERIFY: exactly one alert with the distinct reason" "$(printf '%s\n' "$ALERTS" | grep -c 'VERIFY timed out (rc=124) after 1s')" 1
ok "slow VERIFY: indet-hash marker, no item-hash marker" 'logged "auto-credit: indet-hash" && ! logged "auto-credit: item-hash"'
# the real item guard on this cycle's real task log + status: not a failed attempt, allowance armed
ST="$W/gstate"; mkdir -p "$ST"
H="$(grep -o 'indet-hash [0-9a-f]\{32\}' "$TASK_LOG" | head -1 | awk '{print $2}')"
bash "$G" "$REPO" "$OUT" "$ST" t-app "$TASK_LOG" >/dev/null 2>&1
ok "slow VERIFY: item guard recorded no failed attempt and no no-op" '[ -z "$(ls "$ST/item_fails" 2>/dev/null | grep -E "\.(count|noopcount)$")" ]'
ok "slow VERIFY: item guard armed the indeterminate allowance for that item" '[ -n "$H" ] && [ -f "$ST/item_fails/t-app.$H.indet" ]'

FAST='- [ ] app.py — Make hello return 2. VERIFY: `sleep 1 && grep -q "return 2" app.py`'
mk_case e2e_fit; scout_ok
aplan 2 "gc OVERNIGHT_PROGRESS.md '$FAST' 'docs: queue item'
printf 'def hello():\n    return 2\n' > app.py; git add -A; git commit -q -m 'feat: hello returns 2'"
OVN_AC_VERIFY_TIMEOUT=30 run_case
ok "benign twin: a VERIFY that fits is credited" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] app.py — Make hello" && logged "auto-credit: item-hash"'
ok "benign twin: no indeterminate marker or alert" '! logged "indet-hash" && ! printf "%s" "$ALERTS" | grep -q "VERIFY timed out"'
summary
