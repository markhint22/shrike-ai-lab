#!/usr/bin/env bash
# run_overnight.sh MAIN LOOP, end to end: the REAL script runs in a hermetic fake tree (OVN_SCRIPT_DIR) with stub aider/curl/docker on
# $HOME/aider-venv/bin, fake git repos with bare origins, and a repo-owned .ovn-verify.sh. Covers: start-up guards (paused, lock held,
# LiteLLM down, aider missing, model-not-listed warning), per-task dispatch, hold/disabled handling, every status class the real
# run_aider_fix_task can produce cheaply, report-table writing, outcome recording, per-task hooks, safety valve, end-of-cycle hooks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
ST="$T/tree/state"; HK="$RO_STUB/hooks.log"
mkdir -p "$ST"

echo "=== start-up guards ==="
ro_tasks '[]'
touch "$ST/PAUSED"
ro_run_main
eq "paused at start: exits 0" 0 "$RO_RC"
has "paused at start: says so" "$RO_OUT" "Queue is paused"
hasnt "paused at start: no cycle hooks ran" "$(cat "$HK" 2>/dev/null)" "cycle_notify"
rm -f "$ST/PAUSED"

# lock held by someone else (this shell holds run.lock on fd 8, the script opens its own fd 200 -> flock conflict)
exec 8>"$ST/run.lock"; flock -n 8
ro_run_main
exec 8>&-
eq "lock held: exits 0 without doing anything" 0 "$RO_RC"
has "lock held: reports skip" "$RO_OUT" "already running"
eq "lock held: no report written" 0 "$(ls "$T/tree/reports" 2>/dev/null | wc -l | tr -d ' ')"

touch "$RO_STUB/litellm_down"
ro_run_main
eq "LiteLLM down: exits 1" 1 "$RO_RC"
has "LiteLLM down: logged" "$RO_OUT" "not responding. Aborting this run."
has "LiteLLM down: abort report written" "$(ro_report)" "**Aborted**: LiteLLM"
rm -f "$RO_STUB/litellm_down" "$T/tree/reports"/*

cp "$T/home/aider-venv/bin/aider" "$T/aider.saved"; rm -f "$T/home/aider-venv/bin/aider"
ro_run_main
eq "aider missing: exits 1" 1 "$RO_RC"
has "aider missing: abort report" "$(ro_report)" "\`aider\` not found on PATH"
cp "$T/aider.saved" "$T/home/aider-venv/bin/aider"; rm -f "$T/tree/reports"/*

touch "$RO_STUB/models_missing"
ro_run_main
eq "model not listed: continues (warning only)" 0 "$RO_RC"
has "model-not-listed warning logged" "$RO_OUT" "WARNING: model 'qwen-dflash-27B' not found"
has "zero tasks -> cycle completes" "$RO_OUT" "Loaded 0 task(s)"
has "completion logged with the report path" "$RO_OUT" "complete. Report:"
has "report has the table header" "$(ro_report)" "| Task | Type | Status | Branch/Version | Log |"
has "end-of-cycle planner hook ran" "$(cat "$HK")" "ovn_planner.sh"
has "end-of-cycle refill hook ran" "$(cat "$HK")" "queue_refill.sh"
has "cycle_notify got the report path" "$(cat "$HK")" "cycle_notify.sh $T/tree/reports/"
rm -f "$RO_STUB/models_missing" "$T/tree/reports"/*

echo "=== per-task status classes through the real loop ==="
cat > "$RO_STUB/scn" <<'EOF'
case "$(basename "$(pwd)")" in
  r-noop) IMPL_SEQ=none;;
  r-push) IMPL_SEQ=ok;;
  r-transient) IMPL_SEQ=ratelimit;;
  r-revert) IMPL_SEQ=bad; FIXUP_ACT=none;;
  r-blocked) SCOUT_VERDICT=BLOCKED;;
  r-done) IMPL_SEQ=alreadydone;;
  r-rc) IMPL_SEQ=fail; IMPL_RC=1;;
  r-ctx) IMPL_SEQ=ctx;;
  r-over) IMPL_SEQ=oversized;;
  r-redred) IMPL_SEQ=assertfail;;
  r-skipv) IMPL_SEQ=ok;;
  r-persist) IMPL_SEQ=ok;;
esac
EOF
for n in noop push transient revert blocked done rc ctx over redred skipv persist held stale; do ro_mkrepo "r-$n" >/dev/null; done
ro_mkrepo r-exhausted '# Overnight Progress

## Next Steps
- [x] everything is done' >/dev/null
echo assertfail > "$RO_STUB/verify.r-redred"; echo skip > "$RO_STUB/verify.r-skipv"
mkdir -p "$T/repos/r-nogit"
touch "$ST/HOLD_r-held"
touch -d '10 hours ago' "$ST/HOLD_r-stale"
# pre-seed the valve counter for the reverting task one below the threshold (MAX_CONSECUTIVE_FAILURES=8) and the no-op streak for r-noop one below 30
mkdir -p "$ST/failures" "$ST/noops"; echo 7 > "$ST/failures/t-revert.count"; echo 29 > "$ST/noops/t-noop.count"
R="$T/repos"
ro_tasks "$(jq -nc --arg R "$R" '[
 {id:"t-noop",repo:($R+"/r-noop"),prompt:"work the top item"},
 {id:"t-push",repo:($R+"/r-push"),prompt:"work the top item",map_tokens:2000,max_files:3,protected_files:["secret.py","other.py"],timeout_secs:120,skip_agents_md:true},
 {id:"t-transient",repo:($R+"/r-transient"),prompt:"work the top item"},
 {id:"t-revert",repo:($R+"/r-revert"),prompt:"work the top item"},
 {id:"t-blocked",repo:($R+"/r-blocked"),prompt:"work the top item"},
 {id:"t-done",repo:($R+"/r-done"),prompt:"work the top item"},
 {id:"t-rc",repo:($R+"/r-rc"),prompt:"work the top item"},
 {id:"t-ctx",repo:($R+"/r-ctx"),prompt:"work the top item"},
 {id:"t-over",repo:($R+"/r-over"),prompt:"work the top item"},
 {id:"t-redred",repo:($R+"/r-redred"),prompt:"work the top item"},
 {id:"t-skipv",repo:($R+"/r-skipv"),prompt:"work the top item"},
 {id:"t-persist",repo:($R+"/r-persist"),prompt:"work the top item",persistent_branch:true},
 {id:"t-exhausted",repo:($R+"/r-exhausted"),prompt:"work the top item"},
 {id:"t-nogit",repo:($R+"/r-nogit"),prompt:"work the top item"},
 {id:"t-held",repo:($R+"/r-held"),prompt:"work the top item"},
 {id:"t-stale",repo:($R+"/r-stale"),prompt:"work the top item"},
 {id:"t-disabled",repo:($R+"/r-disabled"),prompt:"p",enabled:false},
 {id:"t-train",type:"train_job",project:"proj",task:"tk",engine:"unsloth",version:"vTEST"}
]')"
TRAINING="$T/home/shrike-ai-lab-training"; mkdir -p "$TRAINING/.venv/bin" "$TRAINING/scripts"; echo ': # activate' > "$TRAINING/.venv/bin/activate"
: > "$HK"
ro_run_main
REP="$(ro_report)"
eq "full cycle exits 0" 0 "$RO_RC"
row(){ printf '%s\n' "$REP" | grep -F "| $1 |" | head -1; }
oc(){ jq -r --arg id "$1" --arg f "$2" 'select(.id==$id) | .[$f]' "$ST/outcomes.jsonl" | tail -1; }

has "no-op task reported as plain no-op" "$(row t-noop)" "| no-op |"
eq "no-op task outcome class noop/bad" "noop/bad" "$(oc t-noop class)/$(oc t-noop severity)"
has "pushed task reports tests:pass" "$(row t-push)" "pushed(tests:pass)"
eq "pushed task outcome class landed/good" "landed/good" "$(oc t-push class)/$(oc t-push severity)"
has "pushed task's branch column is the per-run branch" "$(row t-push)" "overnight/"
eq "pushed commit really reached the bare origin" 1 "$(git -C "$T/origin/r-push.git" branch -a 2>/dev/null | grep -q overnight && echo 1 || echo 0)"
has "transient API error not counted (status)" "$(row t-transient)" "error-transient(API/network - see log)"
has "build-break commit reverted" "$(row t-revert)" "reverted(build-break)"
eq "reverted outcome class" "reverted/bad" "$(oc t-revert class)/$(oc t-revert severity)"
eq "build-break left no broken file in the work tree" 0 "$([ -f "$R/r-revert/app/broken.py" ] && echo 1 || echo 0)"
has "BLOCKED scout verdict -> no-op(BLOCKED)" "$(row t-blocked)" "no-op(BLOCKED)"
eq "BLOCKED outcome neutral" "noop/neutral" "$(oc t-blocked class)/$(oc t-blocked severity)"
has "implement-time already-done -> no-op(ALREADY-DONE)" "$(row t-done)" "no-op(ALREADY-DONE)"
has "aider non-zero exit -> error(exit=1)" "$(row t-rc)" "error(exit=1)"
has "context overflow -> error(model/API error)" "$(row t-ctx)" "error(model/API error - see log)"
has "oversized context -> skip(oversized-context)" "$(row t-over)" "skip(oversized-context)"
eq "oversized outcome class" "oversized/fixable" "$(oc t-over class)/$(oc t-over severity)"
has "tests-red commit -> no-op(reverted-red)" "$(row t-redred)" "no-op(reverted-red)"
has "lock-contended verify -> error(verify-skipped" "$(row t-skipv)" "error(verify-skipped - lock contended, retry next cycle)"
has "persistent task pushes to overnight/feature" "$(row t-persist)" "overnight/feature"
eq "overnight/feature exists on origin" 1 "$(git -C "$T/origin/r-persist.git" branch 2>/dev/null | grep -q overnight/feature && echo 1 || echo 0)"
has "exhausted backlog -> skip(exhausted)" "$(row t-exhausted)" "skip(exhausted)"
eq "exhausted outcome skipped/expected" "skipped/expected" "$(oc t-exhausted class)/$(oc t-exhausted severity)"
has "repo without .git -> error status in the report" "$REP" "error: no .git at"
known_bug "a repo without .git is recorded as class 'error' (run_overnight.sh:799's log line leaks into the captured status so it classifies 'unknown')" "$([ "$(oc t-nogit class)" = error ] && echo 1 || echo 0)"
has "fresh hold -> held(...) row" "$(row t-held)" "held(r-held)"
has "stale hold auto-expired and the task ran" "$(row t-stale)" "| pushed"
eq "stale hold file removed" 0 "$([ -f "$ST/HOLD_r-stale" ] && echo 1 || echo 0)"
has "stale-hold expiry alert raised" "$(cat "$ST/alerts.log")" "auto-expired a stale 6h+ hold on r-stale"
eq "fresh hold file kept" 1 "$([ -f "$ST/HOLD_r-held" ] && echo 1 || echo 0)"
has "disabled task row" "$(row t-disabled)" "| disabled |"
has "train_job row present with its version" "$(row t-train)" "| trained | vTEST |"
eq "train_job recorded as landed" "landed/good" "$(oc t-train class)/$(oc t-train severity)"
has "train.py ran for the train job" "$(cat "$RO_STUB/python.log")" "--project proj --task tk --engine unsloth --version vTEST"
has "duration column appended to rows" "$(row t-push)" "s |"

echo "--- safety valve + no-op streak through the loop ---"
eq "8th consecutive revert auto-disables THAT task in tasks.json" false "$(jq -r '.[] | select(.id=="t-revert") | .enabled' "$T/tree/tasks.json")"
eq "other tasks untouched by the valve" "null" "$(jq -r '.[] | select(.id=="t-push") | .enabled' "$T/tree/tasks.json")"
has "auto-disable alert raised" "$(cat "$ST/alerts.log")" "t-revert | AUTO-DISABLED after 8 consecutive failures"
has "no-op streak alert raised at the threshold (30)" "$(cat "$ST/alerts.log")" "no-op'd 30 cycles in a row"
eq "successful push cleared its failure counter" 0 "$([ -f "$ST/failures/t-push.count" ] && echo 1 || echo 0)"
eq "transient error did not start a failure streak" 0 "$([ -f "$ST/failures/t-transient.count" ] && echo 1 || echo 0)"

echo "--- hooks ---"
hk="$(cat "$HK")"
has "item-guard ran for an aider task with repo/status/state-dir/id args" "$hk" "ovn_item_guard.sh $R/r-push pushed(tests:pass)"
has "cycle-triage ran for an aider task" "$hk" "ovn_cycle_triage.sh $R/r-noop no-op"
eq "train_job does not call item-guard (only aider tasks do)" 0 "$(grep -c 't-train' "$HK")"
has "end-of-cycle hooks ran after the loop" "$hk" "queue_refill.sh"
has "cycle_notify ran last" "$(tail -1 "$HK")" "cycle_notify.sh"

echo "--- outcomes.jsonl ---"
eq "every non-skipped/disabled/held task got an outcome row" 16 "$(jq -r '.id' "$ST/outcomes.jsonl" | sort -u | wc -l | tr -d ' ')"
eq "outcomes.jsonl is valid JSONL" 0 "$(jq -c . "$ST/outcomes.jsonl" >/dev/null 2>&1; echo $?)"
eq "outcome repo field is the repo basename" "r-push" "$(oc t-push repo)"
eq "outcome attempt defaults to 1 (no best-of-N)" 1 "$(oc t-push attempt)"
eq "pushed task outcome carries scout token counts" 1 "$([ "$(oc t-push tokens_sent)" -gt 0 ] && echo 1 || echo 0)"
eq "no-op streak counter reset by nothing (still 30)" 30 "$(cat "$ST/noops/t-noop.count")"

ro_summary
