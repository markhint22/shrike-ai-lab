#!/usr/bin/env bash
# test_baseline_shadow_hook.sh - the SHADOW-ONLY baseline-relative-verify hook inside the REAL ovn_stage_runner.sh, run end to end in the hermetic
# fake tree (lib_osr_fixture.sh). 2026-10-02. Contract under test: when the full verify is RED the runner logs ONE row to state/qa_shadow/baseline.jsonl
# (baseline verdict + the runner's ACTUAL final decision + new/pre-existing sets + would_have_rescued) and its own behaviour - verdict, exit code,
# pushes, output, journal - is BYTE-FOR-BYTE what it was without the hook, even when the hook crashes, hangs or its tool is missing.
# Never reaches the network or ntfy; OVN_QA_SHADOW=off keeps the (unrelated) hygiene hook inert.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
# T2 "label" "shell snippet": like t(), but evaluated in THIS shell so the helper functions below are visible
SIGEQ(){ if [ "$2" = "$3" ]; then ok "$1" 1; else ok "$1" 0; diff <(echo "$2") <(echo "$3") | head -12; fi; }
T2(){ local l="$1"; if eval "$2" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }
export OVN_QA_SHADOW=off OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
unset OVN_BASELINE_SHADOW OVN_QA_BASELINE 2>/dev/null || true
command -v jq >/dev/null || { echo "jq missing - skipped"; exit 0; }
command -v timeout >/dev/null || { echo "no GNU timeout (the runner itself needs it; box-only test) - skipped"; exit 0; }
PYB="$(command -v python3.12 || command -v python3)"
ROWS(){ cat "$Q/state/qa_shadow/baseline.jsonl" 2>/dev/null; }
NROWS(){ ROWS | grep -c . || true; }
LASTROW(){ ROWS | tail -1; }
BLJSON(){ cat "$Q"/state/stage_runs/"$OSR_REPO"-*.baseline.json 2>/dev/null; }

# a live-venv pytest stub that prints a REAL pytest -q short summary for the ids listed in $OSR_SCN/pytest.fails (one per line)
osr_reds(){
  local d="$RD/backend/.venv/bin"; osr_venv backend
  _osr_stub "$d/pytest" '#!/usr/bin/env bash
echo "$PWD :: $*" >> "$OSR_SCN/pytest.calls"
f="$OSR_SCN/pytest.fails"
if [ -s "$f" ]; then
  echo "=========================== short test summary info ==========================="
  n=0; while IFS= read -r id; do [ -n "$id" ] && { echo "FAILED $id - AssertionError: boom"; n=$((n+1)); }; done < "$f"
  echo "$n failed, 4 passed in 0.50s"; exit 1
fi
echo "5 passed in 0.50s"; exit 0'
}
# fresh tree with the QA tools installed next to the runner, reds = $1 (newline list), baseline = $2 (raw pytest ids, space-free, or "")
scene(){
  osr_new; osr_reds; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  cp -R "$REALQ/qa" "$Q/qa"
  printf '%s\n' "$1" > "$T/scn/pytest.fails"
  if [ -n "${2:-}" ]; then
    { echo "-- pytest FULL in backend  --"; printf 'FAILED %s - x\n' $2; echo "$(printf '%s\n' $2 | grep -c .) failed, 4 passed in 0.5s"; } > "$T/base.log"
    OVN_DIR="$Q" "$PYB" "$Q/qa/baseline_verify.py" snapshot --repo "$OSR_REPO" --failing-file "$T/base.log" --format verify-log --commit c0 --no-record >/dev/null 2>&1
  fi
}
norm(){ sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:]{8}Z?/TS/g; s/[0-9]{8}-[0-9]{6}-[0-9]+/RUN/g; s/, [0-9]+s,/, Ns,/g; s/\"(duration_s|tok_s)\":[0-9]+/\"\1\":N/g; s#[^ ]*/stage-osrrepo\.[A-Za-z0-9]+#WT#g; s#/tmp/tmp\.[A-Za-z0-9]+#TMP#g; s#/var/folders/[^ ]*#TMP#g'; }
runsig(){   # normalized, hook-independent behaviour signature of the last run: rc + combined output + journal + what reached origin
  { echo "rc=$RC"; norm < "$T/out.txt"; echo "--jsonl"; osr_jsonl | jq -S -c 'del(.ts)' | norm; echo "--origin"; osr_origin_log; echo "--vlog"; osr_vlog | norm; } 2>/dev/null
}

OLD="tests/test_old.py::test_old_red"; NEW="tests/test_new.py::test_new_red"

echo "== benign control: only the pre-existing red test fails (baseline has it)"
scene "$OLD" "$OLD"
osr_run "$OSR_REPO" "$ITEM_PY"
T2 "runner behaviour UNCHANGED: still FAILED, NOT pushing" "grep -q 'independent full-verify: FAILED — NOT pushing' '$T/out.txt'"
T2 "nothing pushed to origin (shadow never rescues)" "! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
T2 "journal still says verified:false" "osr_jsonl | grep -q '\"verified\":false'"
t "exactly ONE row appended" test "$(NROWS)" = 1
R="$(LASTROW)"
T2 "row: baseline verdict PASS (no NEW failing id)" "[ \"\$(jq -r .verdict <<<\"\$R\")\" = PASS ]"
T2 "row: would_have_rescued=true and real_rescue=true (runner finally rejected)" "jq -e '.would_have_rescued==true and .real_rescue==true and .runner.final==\"not_verified\" and .runner.first==\"not_verified\"' <<<\"\$R\""
T2 "row: preexisting set carries the id, new_failures empty" "jq -e '(.preexisting|index(\"[backend] $OLD\")!=null) and (.new_failures|length==0) and .n_new==0 and .n_pre==1' <<<\"\$R\""
T2 "row: run id + kind + repo present" "jq -e '.kind==\"staged_shadow\" and .repo==\"$OSR_REPO\" and (.run|startswith(\"$OSR_REPO-\"))' <<<\"\$R\""
T2 "<run>.baseline.json written next to the journal" "jq -e '.verdict==\"PASS\"' <(BLJSON)"
T2 "verify.log is NOT touched by the hook (repair loop greps it)" "! osr_vlog | grep -qi 'baseline'"
SIG_ON="$(runsig)"
osr_cleanup

echo "== byte-for-byte: the same scenario with the kill switch OVN_BASELINE_SHADOW=off"
scene "$OLD" "$OLD"
OVN_BASELINE_SHADOW=off osr_run "$OSR_REPO" "$ITEM_PY"
T2 "kill switch: no row, no .baseline.json" "[ \"\$(NROWS)\" = 0 ] && [ -z \"\$(BLJSON)\" ]"
SIG_OFF="$(runsig)"
SIGEQ "hook ON vs OFF: rc + output + journal + pushes + verify.log identical (normalized)" "$SIG_ON" "$SIG_OFF"
osr_cleanup

echo "== negative control: a NEW failing test on top of the pre-existing red"
scene "$OLD
$NEW" "$OLD"
osr_run "$OSR_REPO" "$ITEM_PY"
R="$(LASTROW)"
T2 "row: baseline verdict FAIL, not a rescue, the NEW id is named" "jq -e '.verdict==\"FAIL\" and .would_have_rescued==false and .real_rescue==false and (.new_failures|index(\"[backend] $NEW\")!=null) and .n_new==1 and .n_pre==1' <<<\"\$R\""
T2 "runner still FAILED / nothing pushed" "grep -q 'independent full-verify: FAILED' '$T/out.txt' && ! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
osr_cleanup

echo "== no baseline for the repo: UNVERIFIED, never a guess"
scene "$OLD" ""
osr_run "$OSR_REPO" "$ITEM_PY"
R="$(LASTROW)"
T2 "row: UNVERIFIED, would_have_rescued=false" "jq -e '.verdict==\"UNVERIFIED\" and .would_have_rescued==false and .real_rescue==false' <<<\"\$R\""
osr_cleanup

echo "== hard gate failure (stub/placeholder in the change) is never baseline-tolerated (and, since 2026-10-03, never echoed as a baseline FAIL: NA)"
scene "$OLD" "$OLD"
osr_aider 1 'mkdir -p backend/app backend/tests
printf "def foo():\n    raise NotImplementedError\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo\n" > backend/tests/test_foo.py'
osr_run "$OSR_REPO" "$ITEM_PY"
R="$(LASTROW)"
T2 "row: QUALITY FAIL => baseline NA (2026-10-03: the runner already enforces it; no independent FAIL), listed in details.runner_enforced, never a rescue" "jq -e '.verdict==\"NA\" and .would_have_rescued==false and (.details.runner_enforced|length)>0' <<<\"\$R\""
osr_cleanup

echo "== green verify: no row, no baseline.json (the hook only fires on a RED verify)"
scene "" "$OLD"
: > "$T/scn/pytest.fails"
osr_run "$OSR_REPO" "$ITEM_PY"
T2 "green run: verified + pushed as before" "git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
T2 "green run: zero rows, zero baseline.json" "[ \"\$(NROWS)\" = 0 ] && [ -z \"\$(BLJSON)\" ]"
osr_cleanup

echo "== repair round turns the red run green: the row records the runner's FINAL decision"
scene "$OLD" "$OLD"
osr_aider 2 ': > "$OSR_SCN/pytest.fails"; echo "# fix" >> backend/app/foo.py; echo fixed'
OVN_VERIFY_REPAIR_ROUNDS=1 osr_run "$OSR_REPO" "$ITEM_PY"
R="$(LASTROW)"
T2 "runner verified after the repair round" "grep -q 'REPAIR PASSED (round 1)' '$T/out.txt'"
T2 "row: runner.final=verified, baseline PASS is NOT counted as a real rescue; one row only" "jq -e '.runner.final==\"verified\" and .would_have_rescued==true and .real_rescue==false' <<<\"\$R\" && [ \"\$(NROWS)\" = 1 ]"
T2 "the repair prompt did not pick up anything from the hook" "! grep -qi 'baseline' '$T/scn/aider.args.2'"
osr_cleanup

echo "== qa mode switch (qa_modes.json baseline=off) writes no row"
scene "$OLD" "$OLD"
echo '{"baseline":"off"}' > "$Q/state/qa_modes.json"
osr_run "$OSR_REPO" "$ITEM_PY"
T2 "mode off: no row; runner unchanged" "[ \"\$(NROWS)\" = 0 ] && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup

echo "== hook CRASHES: runner verdict unchanged, UNVERIFIED row, error swallowed"
for crash in raise exit1 garbage hang missing; do
  scene "$OLD" "$OLD"
  case "$crash" in
    raise)   printf 'import sys\nraise RuntimeError("boom")\n' > "$Q/qa/baseline_verify.py" ;;
    exit1)   printf 'import sys\nsys.exit(1)\n' > "$Q/qa/baseline_verify.py" ;;
    garbage) printf 'print("not json at all")\n' > "$Q/qa/baseline_verify.py" ;;
    hang)    printf 'import time\ntime.sleep(60)\n' > "$Q/qa/baseline_verify.py" ;;
    missing) rm -rf "$Q/qa" ;;
  esac
  t0=$(date +%s)
  osr_run "$OSR_REPO" "$ITEM_PY"
  el=$(( $(date +%s) - t0 ))
  SIG_C="$(runsig)"
  SIGEQ "crash=$crash: rc/output/journal/pushes identical to the hook-off run" "$SIG_C" "$SIG_OFF"
  if [ "$crash" = missing ]; then
    T2 "crash=$crash: still leaves an UNVERIFIED fallback row (accounted for, not silent)" "[ \"\$(NROWS)\" = 1 ] && jq -e '.verdict==\"UNVERIFIED\" and .real_rescue==false and .runner.final==\"not_verified\"' <<<\"\$(LASTROW)\""
  else
    T2 "crash=$crash: UNVERIFIED row, never PASS/rescue" "[ \"\$(NROWS)\" = 1 ] && jq -e '.verdict==\"UNVERIFIED\" and .would_have_rescued==false and .real_rescue==false' <<<\"\$(LASTROW)\""
  fi
  T2 "crash=$crash: the error is logged to logs/qa_shadow.log" "grep -q 'baseline-shadow: UNVERIFIED' '$Q/logs/qa_shadow.log'"
  if [ "$crash" = hang ]; then t "hang: bounded - the hook cost <= ~12s (two 5s caps), the 60s sleep was killed (took ${el}s)" test "$el" -le 40; fi
  osr_cleanup
done

echo "== set -u safety: the hook cannot abort the runner even with hostile env"
scene "$OLD" "$OLD"
OVN_BASELINE_SHADOW= PYTHONPATH=/nonexistent osr_run "$OSR_REPO" "$ITEM_PY"
T2 "runner reached its normal end (DONE line) and exit code unchanged" "grep -q 'DONE: 0/' '$T/out.txt' && [ $RC = 0 ]"
osr_cleanup

osr_summary
