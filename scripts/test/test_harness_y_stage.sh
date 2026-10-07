#!/usr/bin/env bash
# Harness Y4 (2026-10-02): a staged run that ends UNVERIFIED (0 of N steps pushed, ~15 min of GPU) used to leave no row in state/outcomes.jsonl
# (iptv Android run 215550, 21:55Z), so no pass-rate dashboard ever saw it. The REAL ovn_stage_runner.sh now appends one outcome row at the end of
# such a run: status "no-op(stage-unverified) stage(runner)", fail_reason = the first error line of the verify log, repo, feat_tag, duration.
# 2026-10-02 (review notes Y-a, Y-f): fail_reason is a BOUNDED tag (ovn_classify_fail.sh) so Counter()-based reports do not make one bucket per row, and the
# free-text excerpt is a separate truncated + SCRUBBED "detail" field (verify output can carry connection strings / tokens). Y-f: the fixture's stub
# watchdog sleep used to expire after 60s and kill -9 the runner, so a run that merely took > 1 minute under load failed 3 assertions (20/23).
# NEGATIVE: unverified (red verify, and 0 steps landed) -> exactly one row. BENIGN: verified+pushed -> no row; invoked inline by run_overnight.sh
# (OVN_STAGE_OUTCOME_BY_CALLER=1, the caller records its own row) -> no row; OVN_STAGE_UNVERIFIED_ROW=off -> no row; non-persistent outcomes untouched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
eq(){ if [ "$2" = "$3" ]; then ok "$1" 1; else ok "$1 (expected [$2] got [$3])" 0; fi; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
FEAT_ITEM='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python) [feat:iptv_apps-20261002-foo-helper]'
base(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; }
rows(){ [ -f "$Q/state/outcomes.jsonl" ] && wc -l < "$Q/state/outcomes.jsonl" | tr -d ' ' || echo 0; }
row(){ jq -r --arg f "$1" '.[$f]' "$Q/state/outcomes.jsonl" 2>/dev/null | tail -1; }

echo "== red full verify -> one stage-unverified row =="
base
echo fail > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$FEAT_ITEM"
ok "run ended unverified (nothing pushed)" "$(grep -q 'verified commit' "$T/out.txt" && echo 0 || echo 1)"
eq "exactly one outcome row appended" 1 "$(rows)"
eq "row status is the stage-unverified no-op the dashboards already bucket as a real failure" "no-op(stage-unverified) stage(runner)" "$(row status)"
eq "row repo" "$OSR_REPO" "$(row repo)"
eq "row feat_tag from the item" "iptv_apps-20261002-foo-helper" "$(row feat_tag)"
eq "row fail_reason is the BOUNDED classifier tag (consumers Counter() it), not free text" "stage-unverified" "$(row fail_reason)"
ok "row detail carries the first error line of the verify log" "$([[ "$(row detail)" == *"FAILED tests/test_x.py"* ]] && echo 1 || echo 0)"
ok "row has a numeric duration" "$([[ "$(row duration_s)" =~ ^[0-9]+$ ]] && echo 1 || echo 0)"
eq "row class/severity -> counted as a bad (thrown-away) attempt" "noop bad" "$(row class) $(row severity)"
ok "row has an item_hash (shared ovn_item_hash) so the guard/dashboards can join it" "$([ -n "$(row item_hash)" ] && echo 1 || echo 0)"
ok "row attempts >= 1 and tokens summed from the run" "$([ "$(row attempts)" -ge 1 ] && [ "$(row tokens_sent)" -gt 0 ] && echo 1 || echo 0)"
ok "row is valid JSON with the standard keys" "$(jq -e 'has("ts") and has("id") and has("tier") and has("category") and has("fail_reason")' "$Q/state/outcomes.jsonl" >/dev/null 2>&1 && echo 1 || echo 0)"
osr_cleanup

echo "== 0 of N steps landed (no verify log at all) -> row with a synthesized reason =="
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/"
osr_progress "- [ ] $FEAT_ITEM"
osr_plan 1 '[{"desc":"big step","files":["backend/app/foo.py"],"verify":"pytest"}]'
osr_plan 2 '[{"desc":"only one sub","files":["backend/app/foo.py"],"verify":"pytest"}]'
OVN_STAGE_ZERO_CAP=1 osr_run "$OSR_REPO"   # 2026-10-07: cap 1 = immediate escalation (the retry budget: test_stage_zero_retry.sh)
ok "run landed nothing and escalated" "$(grep -q 'escalated to Claude' "$T/out.txt" && echo 1 || echo 0)"
eq "one row for the 0/1 run" 1 "$(rows)"
eq "0/1 run: fail_reason is the bounded tag too" "stage-unverified" "$(row fail_reason)"
ok "detail says 0/1 steps landed (or carries the verify error)" "$([[ "$(row detail)" == *"0/1 steps landed"* || "$(row detail)" == *Error* || "$(row detail)" == *FAIL* ]] && echo 1 || echo 0)"
eq "status" "no-op(stage-unverified) stage(runner)" "$(row status)"
osr_cleanup

echo "== BENIGN: verified + pushed -> no row =="
base
osr_run "$OSR_REPO" "$FEAT_ITEM"
ok "run verified and pushed" "$(grep -q 'pushed 1 verified commit' "$T/out.txt" && echo 1 || echo 0)"
eq "no outcome row for a landed run" 0 "$(rows)"
osr_cleanup

echo "== BENIGN: invoked inline by run_overnight.sh (caller records its own row) -> no row =="
base
echo fail > "$T/scn/pytest.mode"
OVN_STAGE_OUTCOME_BY_CALLER=1 osr_run "$OSR_REPO" "$FEAT_ITEM"
ok "run ended unverified (nothing pushed)" "$(grep -q 'verified commit' "$T/out.txt" && echo 0 || echo 1)"
eq "no duplicate row when the caller flag is set" 0 "$(rows)"
osr_cleanup

echo "== inline caller passes the flag =="
ok "run_overnight.sh's inline stage call sets OVN_STAGE_OUTCOME_BY_CALLER=1 (it records its own row)" "$(grep -q 'OVN_STAGE_OUTCOME_BY_CALLER=1 timeout 12900 bash ovn_stage_runner.sh' "$REALQ/run_overnight.sh" && echo 1 || echo 0)"

echo "== kill switch =="
base
echo fail > "$T/scn/pytest.mode"
OVN_STAGE_UNVERIFIED_ROW=off osr_run "$OSR_REPO" "$FEAT_ITEM"
eq "OVN_STAGE_UNVERIFIED_ROW=off -> no row" 0 "$(rows)"
osr_cleanup

echo "== lib missing: row still written, hash empty (never fatal) =="
base
rm -f "$Q/scripts/lib_item_select.sh"
echo fail > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$FEAT_ITEM"
eq "row written without the shared hash lib" 1 "$(rows)"
eq "item_hash empty in that case" "" "$(row item_hash)"
osr_cleanup

echo "== Y-a: fail_reason is a bounded tag; the excerpt is scrubbed in a separate detail field =="
for variant in sed python; do
  base
  [ "$variant" = python ] && { mkdir -p "$Q/qa"; cp "$REALQ"/qa/baseline_verify.py "$REALQ"/qa/qa_common.py "$Q/qa/"; }
  echo fail-secret > "$T/scn/pytest.mode"
  osr_run "$OSR_REPO" "$FEAT_ITEM"
  eq "[$variant] one row" 1 "$(rows)"
  eq "[$variant] fail_reason stays the bounded tag even when the verify line is long free text" "stage-unverified" "$(row fail_reason)"
  ok "[$variant] detail still names the failing test" "$([[ "$(row detail)" == *"FAILED tests/test_x.py"* ]] && echo 1 || echo 0)"
  ok "[$variant] detail has the DB password scrubbed" "$([[ "$(row detail)" != *s3cr3tPassw0rd* ]] && echo 1 || echo 0)"
  ok "[$variant] detail has the token=... value scrubbed" "$([[ "$(row detail)" != *abcd1234efgh5678* ]] && echo 1 || echo 0)"
  ok "[$variant] detail has the Bearer token scrubbed" "$([[ "$(row detail)" != *eyAbCdEf0123456789xyz* ]] && echo 1 || echo 0)"
  ok "[$variant] no secret anywhere in outcomes.jsonl" "$(grep -qE 's3cr3tPassw0rd|abcd1234efgh5678|eyAbCdEf0123456789xyz' "$Q/state/outcomes.jsonl" && echo 0 || echo 1)"
  ok "[$variant] detail is truncated to 160 chars" "$([ "$(row detail | wc -c | tr -d ' ')" -le 162 ] && echo 1 || echo 0)"
  osr_cleanup
done
base
echo fail > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$FEAT_ITEM"
base_fr="$(row fail_reason)"; osr_cleanup
base
echo fail-secret > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$FEAT_ITEM"
eq "BENIGN: two unverified runs with DIFFERENT error text land in the SAME fail_reason bucket" "$base_fr" "$(row fail_reason)"
osr_cleanup

echo "== Y-a: a hung / crashing qa module can neither stall the runner nor leak the secret (sed fallback) =="
for qm in hang raise; do
  base
  mkdir -p "$Q/qa"
  if [ "$qm" = hang ]; then printf 'import time\ntime.sleep(60)\n' > "$Q/qa/baseline_verify.py"; else printf 'raise RuntimeError("boom")\n' > "$Q/qa/baseline_verify.py"; fi
  echo fail-secret > "$T/scn/pytest.mode"
  t0=$(date +%s); OVN_BASELINE_SHADOW=off osr_run "$OSR_REPO" "$FEAT_ITEM"; el=$(( $(date +%s) - t0 ))
  eq "[$qm] one row still written" 1 "$(rows)"
  ok "[$qm] detail scrubbed by the sed fallback" "$([[ "$(row detail)" != *s3cr3tPassw0rd* && "$(row detail)" != *abcd1234efgh5678* ]] && echo 1 || echo 0)"
  ok "[$qm] the whole run took < 40s (the scrub's python import is capped at 5s; took ${el}s)" "$([ "$el" -lt 40 ] && echo 1 || echo 0)"
  osr_cleanup
done

echo "== Y-f: fixture cleanup must not delete a CONCURRENT suite's runner worktree =="
base
PEER="/tmp/stage-${OSR_REPO}.peer$$"; OWN="/tmp/stage-${OSR_REPO}.own$$"
mkdir -p "$PEER"; echo live > "$PEER/marker"                       # a worktree some other test process's runner is using right now
git -C "$RD" worktree add -q --detach "$OWN" HEAD 2>/dev/null       # a leftover worktree of THIS fixture's own runner
osr_cleanup
ok "a peer process's /tmp/stage-<repo>.* directory survives this fixture's cleanup (old: rm -rf'd)" "$([ -f "$PEER/marker" ] && echo 1 || echo 0)"
ok "this fixture's own registered worktree IS cleaned up" "$([ ! -e "$OWN" ] && echo 1 || echo 0)"
rm -rf "$PEER"

echo "== Y-f: a run slower than the stub watchdog's old 60s life still completes (deterministic, no load needed) =="
base
osr_aider 1 "/bin/sleep 62
$SNIP_FOO"
osr_run "$OSR_REPO" "$FEAT_ITEM"
ok "a 62s aider step: runner NOT killed by the fixture's stub watchdog; verified + pushed" "$(grep -q 'pushed 1 verified commit' "$T/out.txt" && echo 1 || echo 0)"
eq "no outcome row for that landed run" 0 "$(rows)"
osr_cleanup

osr_summary
