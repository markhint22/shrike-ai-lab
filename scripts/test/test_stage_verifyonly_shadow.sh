#!/usr/bin/env bash
# N4 stage-runner-waste, Part 5 (2026-10-13): the VERIFY-ONLY PREFLIGHT in ovn_stage_runner.sh is SHADOW ONLY. shrike-monitor bf654f65 '[T3] ... Verify existing test suite passes without modification'
# (VERIFY = 34 passed on overnight/feature, nothing to edit) burned 9 no-edit attempts / 330k tokens. When the item's own VERIFY already PASSES on the pristine tree and the item only asks to verify/ensure/confirm,
# the verdict is LOGGED (event + state/stage_verifyonly_shadow.log). Nothing else changes: the steps still run, credit and enforcement are untouched.
#   Part U: stage_item_is_verify_only extracted from the real runner (python/bash only, runs anywhere).   Part E: the real runner in the fixture (GNU sed + bash 5: the box).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_VERIFYONLY_PREFLIGHT OVN_STAGE_ITEM_VERIFY OVN_STAGE_IV_SHADOW_LOG OVN_STAGE_VERIFYONLY_LOG NTFY_SERVER NTFY_TOPIC
W="$(mktemp -d)"; trap 'rm -rf "$W"; osr_cleanup' EXIT
sed -n '/^# >>> n4-stage-waste helpers: verify-only preflight/,/^# <<< n4-stage-waste helpers: verify-only preflight/p' "$RUNNER" > "$W/h.sh"
[ -s "$W/h.sh" ] || { echo "  FAIL: verify-only helper block not found in $RUNNER"; exit 1; }
# shellcheck disable=SC1091
. "$W/h.sh"
vo(){ stage_item_is_verify_only "$1"; }
echo "== U: classifier"
t "U1 the real shrike-monitor shape is verify-only" vo '[T3] backend/tests/test_monitors_api.py — Verify existing test suite passes without modification. VERIFY: `pytest backend/tests/test_monitors_api.py -v`. (cat:test; multifile:no)'
t "U2 'Confirm ...' is verify-only" vo '[T2] backend/app/svc.py — Confirm run_job is idempotent. VERIFY: `pytest backend/tests/test_svc.py`'
t "U3 'Ensure ... still passes' is verify-only" vo '[T3] Ensure the suite still passes after the last merge. VERIFY: `pytest`'
t "U4 an item that adds code is NOT verify-only" bash -c "$(declare -f stage_item_is_verify_only); ! stage_item_is_verify_only '[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: \`pytest backend/tests/test_foo.py\`'"
t "U5 'Verify X and add a test' is NOT verify-only (it names a change)" bash -c "$(declare -f stage_item_is_verify_only); ! stage_item_is_verify_only '[T3] backend/app/foo.py — Verify foo handles None and add a test for it. VERIFY: \`pytest\`'"
t "U6 words after VERIFY: do not count ('Verify ... VERIFY: pytest -k add')" vo '[T3] backend/app/foo.py — Verify the module imports cleanly. VERIFY: `pytest -k "add or create"`'
t "U7 an item that merely CONTAINS 'verify' mid-sentence is NOT verify-only" bash -c "$(declare -f stage_item_is_verify_only); ! stage_item_is_verify_only '[T3] backend/app/foo.py — Return a value that callers can verify. VERIFY: \`pytest\`'"
nvo(){ bash -c "$(declare -f stage_item_is_verify_only); ! stage_item_is_verify_only \"\$1\"" _ "$1"; }
t "U8 reviewer case: 'Verify ... Modify the balance-check failure path at line 61 to call SquadScore' is a CHANGE request" nvo '[T3] battle.gd — Verify the cost table. Modify the balance-check failure path at line 61 to call SquadScore. VERIFY: `grep -q SquadScore battle.gd`'
t "U9 reviewer case: 'Ensure _credit_cost returns the specific value for Kevlar instead of falling back to default' is a CHANGE request" nvo '[T3] app/credits.py — Ensure _credit_cost returns the specific value for Kevlar instead of falling back to default. VERIFY: `pytest tests/test_credits.py`'
t "U10 'instead of' / 'rather than' alone marks a change request" nvo '[T3] app/x.py — Verify the cache is consulted rather than the database. VERIFY: `pytest`'
t "U11 'Ensure the handler sets the header / uses the helper' is a change request" nvo '[T3] app/x.py — Ensure the handler sets the X-Total header and uses the shared helper. VERIFY: `pytest`'
t "U12 conservative: a 'make sure ...' phrase inside a verify item counts as a change verb (the shadow count must never overstate)" nvo '[T3] Verify the suite passes and make sure the cache is warm. VERIFY: `pytest`'
t "U13 'Make X faster' stays a change request" bash -c "$(declare -f stage_item_is_verify_only); ! stage_item_is_verify_only '[T3] app/x.py — Verify startup and make the import lazy. VERIFY: \`pytest\`'"
t "U19 reviewer case: 'Ensure the login handler rejects empty passwords' is an edit request" nvo '[T3] app/auth.py — Ensure the login handler rejects empty passwords. VERIFY: `pytest`'
t "U20 reviewer case: 'Ensure rate limiter lives in app/core and imports cleanly' is not counted (conservative)" nvo '[T3] app/core/rl.py — Ensure rate limiter defines a RateLimiter class in app/core and imports cleanly. VERIFY: `pytest`'
t "U21 reviewer case: 'Ensure foo.py has a docstring for bar' is an edit request" nvo '[T3] foo.py — Ensure foo.py has a docstring for bar. VERIFY: `pytest`'
t "U22 control: the motivating 'Verify existing test suite passes without modification' is STILL verify-only" vo '[T3] x — Verify existing test suite passes without modification. VERIFY: `pytest`'
echo "== U: shadow log is bounded"
LG="$W/shadow.log"; : > "$LG"; for i in $(seq 1 1000); do printf '%s %0380d\n' "line$i" 0 >> "$LG"; done
sz0="$(wc -c < "$LG" | tr -d ' ')"
t "U14 fixture log is over the cap" test "$sz0" -gt 262144
stage_shadow_log_cap "$LG"
t "U15 an oversized shadow log is cut to the newest 500 lines" bash -c "[ \"\$(wc -l < '$LG' | tr -d ' ')\" = 500 ] && head -1 '$LG' | grep -q '^line501 ' && tail -1 '$LG' | grep -q '^line1000 ' && [ ! -e '$LG.tmp.\$\$' ]"
printf 'a\nb\n' > "$W/small.log"; stage_shadow_log_cap "$W/small.log"
t "U16 a small log is untouched" bash -c "[ \"\$(cat '$W/small.log' | tr -d '\n')\" = ab ]"
t "U17 a missing log is a no-op (rc 0)" stage_shadow_log_cap "$W/does-not-exist.log"
OVN_STAGE_SHADOW_LOG_MAX=100 stage_shadow_log_cap "$W/small.log"; t "U18 the cap is overridable (OVN_STAGE_SHADOW_LOG_MAX)" bash -c "[ \"\$(wc -c < '$W/small.log' | tr -d ' ')\" -le 4 ]"
if ! sed --version >/dev/null 2>&1; then echo "  (Part E skipped: needs GNU sed; run on the box)"; osr_summary; exit $?; fi

echo "== E: the real runner"
n2_new(){ osr_new; local f; for f in lib_stage_guards.sh lib_verify_clause.sh ovn_stage_guards.py ovn_backlog_eligibility.py ovn_credit_items.py ovn_spec_rules.py ovn_verify_safe.py ovn_gut_clause.py lib_item_select.sh; do
    [ -f "$REALQ/scripts/$f" ] && cp "$REALQ/scripts/$f" "$Q/scripts/"; done; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
ITEM_VO='[T3] backend/app/svc.py — Verify run_job still exists without modification. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python; multifile:no)'
PLAN_VO='[{"desc":"Verify run_job exists and add a second test","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py"}]'
SNIP_VO='printf "\n\ndef test_run_job_twice():\n    assert run_job() == run_job()\n" >> backend/tests/test_svc.py; echo "Applied edit"'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN_VO"; osr_aider 1 "$SNIP_VO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1 the pristine PASS of a verify-only item is logged (say + event + shadow log)" bash -c "grep -q 'verify-only item whose own VERIFY already PASSES on the pristine tree' '$T/out.txt' && grep -q '\"event\":\"verify_only_pristine_pass\",\"run\":\|\"event\":\"verify_only_pristine_pass\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'verify_only_pristine_pass' '$Q/state/stage_verifyonly_shadow.log'"
t "E2 NOTHING else changed: the step still ran (aider called), the item landed and was ticked exactly as before" bash -c "[ \"\$(cat '$T/scn/aider.n')\" -ge 1 ] && grep -q 'DONE: 1/1 steps landed' '$T/out.txt' && grep -q '^- \[x\]' <<< \"\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)\""
osr_cleanup
ITEM_ADD='[T3] backend/app/svc.py — Add a second helper to the service. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_ADD"; osr_plan default "$PLAN_VO"; osr_aider 1 "$SNIP_VO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E3 control: an item that ADDS code is not logged even though its VERIFY passes pristine" bash -c "! grep -q 'verify-only item' '$T/out.txt' && ! grep -q 'verify_only_pristine_pass' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN_VO"; osr_aider 1 "$SNIP_VO"
OVN_STAGE_VERIFYONLY_PREFLIGHT=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E4 OVN_STAGE_VERIFYONLY_PREFLIGHT=off: nothing is logged" bash -c "! grep -q 'verify-only item' '$T/out.txt' && [ ! -f '$Q/state/stage_verifyonly_shadow.log' ]"
osr_cleanup
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN_VO"; osr_aider 1 "$SNIP_VO"
OVN_STAGE_ITEM_VERIFY=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E5 with the item-verify probe off there is no pristine verdict and so nothing to log" bash -c "! grep -q 'verify-only item' '$T/out.txt'"
osr_cleanup
osr_summary
