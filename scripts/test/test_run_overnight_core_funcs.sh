#!/usr/bin/env bash
# run_overnight.sh core helpers, exercised by SOURCING THE REAL SCRIPT (OVN_SOURCE_ONLY seam) inside a hermetic fake tree:
# log, emit_alert, error_status, write_abort_report, record_outcome (every class/category/tier/hash/token branch),
# check_and_record_failure (safety valve), track_progress_signal (no-op streak), run_train_job_task,
# coder_window_open/close, coder_process_index, coder_fast_prepass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_hook_stubs
ro_link scripts/ovn_classify.py
ro_tasks '[{"id":"t-one","type":"aider_fix","repo":"/nonexistent/repo-one","prompt":"p"},{"id":"t-two","type":"aider_fix","repo":"/nonexistent/repo-two","prompt":"p"}]'
ro_source
set +e
STATE_DIR="$T/tree/state"

echo "--- log / emit_alert / error_status / write_abort_report ---"
out="$(log "hello world")"
ok "log prefixes a timestamp" "$(printf '%s' "$out" | grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] hello world$' && echo 1 || echo 0)"
so="$(emit_alert crit my-task "it broke" 2>"$T/alert.err")"
eq "emit_alert writes NOTHING to stdout (status-string capture safety)" "" "$so"
has "emit_alert appends to alerts.log" "$(cat "$ALERTS_FILE")" "crit | my-task | it broke"
has "emit_alert mirrors to stderr" "$(cat "$T/alert.err")" "ALERT(crit) my-task: it broke"
echo 'RateLimitError: 429' > "$T/el1.log"
eq "error_status: rate limit -> transient" "error-transient(API/network - see log)" "$(error_status "$T/el1.log" "real")"
printf 'Connection reset by peer\n' > "$T/el2.log"
eq "error_status: connection reset -> transient" "error-transient(API/network - see log)" "$(error_status "$T/el2.log" "real")"
printf 'ContextWindowExceededError and also RateLimitError\n' > "$T/el3.log"
eq "error_status: context overflow is NEVER transient" "real" "$(error_status "$T/el3.log" "real")"
printf 'some unrelated failure\n' > "$T/el4.log"
eq "error_status: unknown text -> fallback status" "real" "$(error_status "$T/el4.log" "real")"
eq "error_status: missing log -> fallback status" "real" "$(error_status "$T/nope.log" "real")"
RUN_KEY=RK1; REPORT_FILE="$T/abort_report.md"
write_abort_report "it was \`down\`"
has "write_abort_report header" "$(cat "$REPORT_FILE")" "# Overnight run report — RK1"
has "write_abort_report reason" "$(cat "$REPORT_FILE")" "**Aborted**: it was \`down\`"

echo "--- record_outcome: status -> class/severity table ---"
: > "$STATE_DIR/outcomes.jsonl"
jf(){ tail -1 "$STATE_DIR/outcomes.jsonl" | jq -r ".$1"; }
chk(){ # status expected_class expected_sev
  record_outcome tid repo1 "$1" "prompt text" aider_fix 1 "" 5 ""
  eq "status [$1] -> class $2" "$2" "$(jf class)"
  eq "status [$1] -> severity $3" "$3" "$(jf severity)"
}
chk "reverted(build-break)" reverted bad
chk "skip(oversized-context)" oversized fixable
chk "no-op(BLOCKED)" noop neutral
chk "no-op(NEEDS-DECISION)" noop neutral
chk "no-op(ALREADY-DONE)" noop neutral
chk "no-op" noop bad
chk "no-op(reverted-red)" noop bad
chk "skip(exhausted)" skipped expected
chk "skip(none-left)" skipped expected
chk "skip(whatever)" skipped neutral
chk "error(model/API error)" error neutral
chk "fail(x)" error neutral
chk "held(repo)" held neutral
chk "pushed(tests:pass)" landed good
chk "pushed" landed good
chk "trained" landed good
chk "weird-unrecognised-status" unknown neutral
chk "OVERNIGHT_PROGRESS.md: needs merge
no-op(reverted-red)" unknown neutral
eq "embedded newline flattened: record is ONE valid JSON line" "1" "$(tail -1 "$STATE_DIR/outcomes.jsonl" | jq -e . >/dev/null 2>&1 && echo 1 || echo 0)"
eq "outcomes.jsonl line count == records written (no line splitting)" "$(wc -l < "$STATE_DIR/outcomes.jsonl" | tr -d ' ')" "$(jq -c . "$STATE_DIR/outcomes.jsonl" | wc -l | tr -d ' ')"
record_outcome tid repo1 'pushed "quoted"' "p" aider_fix 1 "" 5 ""
eq "double quotes stripped from status" 'pushed quoted' "$(jf status)"

echo "--- record_outcome: category from prompt/log text ---"
cat_of(){ record_outcome tid repo1 "no-op" "$1" aider_fix 1 "" 5 ""; jf category; }
eq "cat godot (.gd)" godot "$(cat_of 'edit scripts/a.gd please')"
eq "cat godot (gut)" godot "$(cat_of 'run gut tests')"
eq "cat vue" vue "$(cat_of 'fix Page.vue layout')"
eq "cat typescript (.tsx)" typescript "$(cat_of 'fix Widget.tsx props')"
eq "cat typescript (tsconfig)" typescript "$(cat_of 'adjust tsconfig paths')"
eq "cat endpoint (router)" endpoint "$(cat_of 'add a router for users')"
eq "cat endpoint (/api/)" endpoint "$(cat_of 'call /api/users')"
eq "cat schema (pydantic)" schema "$(cat_of 'pydantic model tweak')"
eq "cat refactor" refactor "$(cat_of 'refactor the helper')"
eq "cat docs (readme)" docs "$(cat_of 'update the readme')"
eq "cat test (pytest)" test "$(cat_of 'add pytest cases')"
eq "cat test (test_ file)" test "$(cat_of 'add test_widget coverage')"
eq "cat python (.py)" python "$(cat_of 'edit util.py')"
eq "cat other" other "$(cat_of 'do a thing')"

echo "--- record_outcome: tier source priority + token sums + fail_reason ---"
R1="$T/ro-repo"; mkdir -p "$R1"
printf '# P\n## Next Steps\n- [ ] [T3] `app/x.py` — thing one (cat:python)\n- [ ] [T1] `app/y.py` — thing two\n' > "$R1/OVERNIGHT_PROGRESS.md"
TL="$T/ro-task.log"
printf 'VERDICT: PROCEED\nFILES: app/y.py\nTokens: 1.5k sent, 2k received.\nTokens: 500 sent, 0.5k received.\n' > "$TL"
record_outcome tid repo1 "pushed(tests:pass)" "prompt [t5]" aider_fix 2 "$TL" 42 "$R1"
eq "tier from LIVE backlog line of the scouted item (app/y.py -> T1)" 1 "$(jf tier)"
eq "attempt recorded" 2 "$(jf attempt)"
eq "duration recorded" 42 "$(jf duration_s)"
eq "tokens_sent summed (1.5k + 500)" 2000 "$(jf tokens_sent)"
eq "tokens_recv summed (2k + 0.5k)" 2500 "$(jf tokens_recv)"
eq "item_hash non-empty for a repo with a queue" 1 "$([ -n "$(jf item_hash)" ] && echo 1 || echo 0)"
eq "feat_tag empty when item has none" "" "$(jf feat_tag)"
eq "landed -> no fail_reason lookup" "" "$(jf fail_reason)"
# fail_reason classifier hook (only for non-landed + executable script at $SCRIPT_DIR)
printf '#!/bin/bash\necho "stubreason:$2"\n' > "$T/tree/ovn_classify_fail.sh"; chmod +x "$T/tree/ovn_classify_fail.sh"
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "non-landed gets fail_reason from ovn_classify_fail.sh" "stubreason:no-op" "$(jf fail_reason)"
record_outcome tid repo1 "pushed" "p" aider_fix 1 "$TL" 5 "$R1"
eq "landed never calls the classifier" "" "$(jf fail_reason)"
# tier falls back to the log/prompt text when the live line has no tag
printf '# P\n## Next Steps\n- [ ] `app/z.py` — untagged item\n' > "$R1/OVERNIGHT_PROGRESS.md"
printf 'VERDICT: PROCEED\nFILES: app/z.py\n' > "$TL"
record_outcome tid repo1 "no-op" "see [T4] item" aider_fix 1 "$TL" 5 "$R1"
eq "tier falls back to explicit tag in prompt" 4 "$(jf tier)"
record_outcome tid repo1 "no-op" "no tag here" aider_fix 1 "$TL" 5 "$R1"
eq "tier '?' when no tag anywhere" "?" "$(jf tier)"
# feat tag => hash + raw tag kept; newline/quote-safe
printf '# P\n## Next Steps\n- [ ] [T2] [feat:repo1-20260922-some-feature] `app/w.py` — a feature step\n' > "$R1/OVERNIGHT_PROGRESS.md"
: > "$TL"
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "feat_tag captured (raw, without brackets/prefix)" "repo1-20260922-some-feature" "$(jf feat_tag)"
h_feat="$(jf item_hash)"
eq "item_hash equals the shared ovn_item_hash of the line text" "$(ovn_item_hash "$(ovn_resolve_top_item "$R1" "$TL" | sed 's/^[0-9]*://')")" "$h_feat"
# fallbacks when the shared lib functions are unavailable (sourcing failure case)
saved_res="$(declare -f ovn_resolve_top_item)"; saved_hash="$(declare -f ovn_item_hash)"
unset -f ovn_resolve_top_item
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "no ovn_resolve_top_item: inline grep fallback still yields the same hash" "$h_feat" "$(jf item_hash)"
unset -f ovn_item_hash
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "no ovn_item_hash, feat tag: inline md5 of the feat key (non-empty)" 1 "$([ -n "$(jf item_hash)" ] && echo 1 || echo 0)"
printf '# P\n## Next Steps\n- [ ] [T2] `app/w.py` — plain item\n' > "$R1/OVERNIGHT_PROGRESS.md"
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "no ovn_item_hash, plain item: inline md5 of the text (non-empty)" 1 "$([ -n "$(jf item_hash)" ] && echo 1 || echo 0)"
eval "$saved_res"; eval "$saved_hash"
# no progress file / empty repo_dir => empty hash
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$T/no-such-repo"
eq "no progress file -> empty item_hash" "" "$(jf item_hash)"
record_outcome tid repo1 "no-op" "p" aider_fix "" "" "" ""
eq "missing attempt/duration args default to 1/0" "1/0" "$(jf attempt)/$(jf duration_s)"
printf '# P\n## Next Steps\n- [x] done\n' > "$R1/OVERNIGHT_PROGRESS.md"
record_outcome tid repo1 "no-op" "p" aider_fix 1 "$TL" 5 "$R1"
eq "no open item -> empty item_hash" "" "$(jf item_hash)"

echo "--- check_and_record_failure (safety valve) ---"
ro_tasks '[{"id":"valve-task","type":"aider_fix","repo":"/x","prompt":"p","enabled":true},{"id":"other","enabled":true}]'
: > "$ALERTS_FILE"
rm -f "$FAIL_DIR"/*.count
o="$(check_and_record_failure valve-task "error-transient(API)")"
has "transient status logged as not counted" "$o" "not counted toward the safety valve"
eq "transient leaves no counter" 0 "$(ls "$FAIL_DIR" | wc -l | tr -d ' ')"
check_and_record_failure valve-task "committed-but-push-failed(x)" >/dev/null
check_and_record_failure valve-task "push-diverged" >/dev/null
check_and_record_failure valve-task "error(foo push-diverged bar)" >/dev/null
eq "push-diverged variants are all transient" 0 "$(ls "$FAIL_DIR" | wc -l | tr -d ' ')"
check_and_record_failure valve-task "reverted(build-break)" >/dev/null
eq "first real revert -> count 1" 1 "$(cat "$FAIL_DIR/valve-task.count")"
check_and_record_failure valve-task "error-transient(API)" >/dev/null
eq "a transient in the middle does not reset the streak" 1 "$(cat "$FAIL_DIR/valve-task.count")"
MAX_CONSECUTIVE_FAILURES=3
check_and_record_failure valve-task "reverted(x)" >/dev/null
eq "count 2, task still enabled" true "$(jq -r '.[0].enabled' "$TASKS_FILE")"
o="$(check_and_record_failure valve-task "reverted(x)")"
eq "count 3 reaches threshold" 3 "$(cat "$FAIL_DIR/valve-task.count")"
eq "threshold disables ONLY that task in tasks.json" "false/true" "$(jq -r '.[0].enabled' "$TASKS_FILE")/$(jq -r '.[1].enabled' "$TASKS_FILE")"
has "SAFETY VALVE logged" "$o" "SAFETY VALVE: task 'valve-task' has failed 3 times in a row"
has "crit alert emitted on auto-disable" "$(cat "$ALERTS_FILE")" "AUTO-DISABLED after 3 consecutive failures"
check_and_record_failure valve-task "pushed(tests:pass)" >/dev/null
eq "any non-revert outcome resets the counter" 0 "$([ -f "$FAIL_DIR/valve-task.count" ] && echo 1 || echo 0)"
check_and_record_failure valve-task "no-op" >/dev/null
eq "a plain no-op is not a failure (no counter)" 0 "$([ -f "$FAIL_DIR/valve-task.count" ] && echo 1 || echo 0)"

echo "--- track_progress_signal (no-op streak alert) ---"
: > "$ALERTS_FILE"; rm -f "$NOOP_DIR"/*.count
NOOP_STREAK_ALERT=3
track_progress_signal np "no-op"; track_progress_signal np "no-op"
eq "streak counts up" 2 "$(cat "$NOOP_DIR/np.count")"
eq "no alert below threshold" 0 "$(grep -c warn "$ALERTS_FILE")"
track_progress_signal np "no-op"
has "alert fires exactly at the threshold" "$(cat "$ALERTS_FILE")" "no-op'd 3 cycles in a row"
track_progress_signal np "no-op"
eq "no re-alert past the threshold (== not >=)" 1 "$(grep -c "no-op'd" "$ALERTS_FILE")"
track_progress_signal np "error(x)"
eq "errors leave the streak alone" 4 "$(cat "$NOOP_DIR/np.count")"
track_progress_signal np "pushed(tests:pass)"
eq "pushed progress resets the streak" 0 "$([ -f "$NOOP_DIR/np.count" ] && echo 1 || echo 0)"

echo "--- run_train_job_task ---"
TRAINING_DIR="$T/training"; mkdir -p "$TRAINING_DIR/.venv/bin" "$TRAINING_DIR/scripts"
echo ': # fake activate' > "$TRAINING_DIR/.venv/bin/activate"
TL="$T/train.log"; : > "$TL"; rm -f "$RO_STUB"/docker_* "$RO_STUB/train_fails" "$RO_STUB/sleep_fails" "$RO_STUB/docker.log" "$RO_STUB/python.log"
s="$(run_train_job_task job1 proj taskA unsloth v9 "$TL")"
eq "train success -> trained" trained "$s"
has "stop + start both called" "$(cat "$RO_STUB/docker.log")" "docker stop"
has "restart called" "$(cat "$RO_STUB/docker.log")" "docker start"
has "train.py got project/task/engine/version" "$(cat "$RO_STUB/python.log")" "scripts/train.py --project proj --task taskA --engine unsloth --version v9"
: > "$TL"; touch "$RO_STUB/train_fails"
s="$(run_train_job_task job1 proj taskA unsloth v9 "$TL")"
has "train failure -> error(training exit=3 ...)" "$s" "error(training exit=3"
has "inference restart still attempted after a failed train" "$(cat "$TL")" "=== Restarting inference container ==="
rm -f "$RO_STUB/train_fails"; : > "$TL"; touch "$RO_STUB/docker_stop_fails"
s="$(run_train_job_task job1 proj taskA unsloth v9 "$TL")"
has "stop failure -> error(could not stop inference" "$s" "error(could not stop inference, exit=1)"
has "training skipped when stop failed" "$(cat "$TL")" "Skipping training run"
rm -f "$RO_STUB/docker_stop_fails"; : > "$TL"; touch "$RO_STUB/docker_unhealthy"
: > "$RO_STUB/sleep.log"
s="$(run_train_job_task job1 proj taskA unsloth v9 "$TL")"
eq "unhealthy loop polled all 24 times" 24 "$(grep -c 'health:' "$TL")"
known_bug "inference never became healthy after a training run but status is still plain '$s' (RESTART_EXIT is the exit of the last sleep, always 0) - run_overnight.sh:2865-2878; patch: set HEALTHY=1 before the break and treat HEALTHY!=1 as a restart failure" "$([ "$s" != "trained" ] && echo 1 || echo 0)"
: > "$TL"; touch "$RO_STUB/sleep_fails"
s="$(run_train_job_task job1 proj taskA unsloth v9 "$TL")"
has "restart-failure branch (forced by a failing sleep stub)" "$s" "trained-but-inference-restart-failed(exit=1)"
rm -f "$RO_STUB/sleep_fails" "$RO_STUB/docker_unhealthy"

echo "--- coder window open/close ---"
OVN_SERVE_EVAL="$T/serve_ok.sh"; printf '#!/bin/bash\necho "serve $*" >> "%s/serve.log"\nexit 0\n' "$RO_STUB" > "$OVN_SERVE_EVAL"; chmod +x "$OVN_SERVE_EVAL"
rm -f "$RO_STUB"/coder_unhealthy "$RO_STUB"/no_route "$RO_STUB"/restore_unhealthy
coder_window_open >/dev/null; rc=$?
eq "window opens when serve+health+routing are fine" 0 "$rc"
eq "hold marker set while coder window open" 1 "$([ -f "$STATE_DIR/coder_window.hold" ] && echo 1 || echo 0)"
has "serve-eval got gguf+ctx" "$(cat "$RO_STUB/serve.log")" "serve $OVN_CODER_GGUF $OVN_CODER_CTX"
printf '#!/bin/bash\nexit 1\n' > "$OVN_SERVE_EVAL"
o="$(coder_window_open)"; rc=$?
eq "serve-eval failure -> rc 1" 1 "$rc"; has "serve failure logged" "$o" "serve-eval failed"
printf '#!/bin/bash\nexit 0\n' > "$OVN_SERVE_EVAL"
touch "$RO_STUB/coder_unhealthy"
o="$(coder_window_open)"; rc=$?
eq "unhealthy coder backend -> rc 1" 1 "$rc"; has "unhealthy backend logged" "$o" "coder backend not healthy"
rm -f "$RO_STUB/coder_unhealthy"; touch "$RO_STUB/no_route"
o="$(coder_window_open)"; rc=$?
eq "LiteLLM not routing the alias -> rc 1" 1 "$rc"; has "routing failure logged" "$o" "LiteLLM did not route"
rm -f "$RO_STUB/no_route"
# GPU never frees: poll loop runs to its cap then proceeds
printf '#!/bin/bash\necho 99999\n' > "$T/home/aider-venv/bin/nvidia-smi"
: > "$RO_STUB/sleep.log"; coder_window_open >/dev/null
eq "GPU-busy poll slept 30 times before giving up and continuing" 30 "$(grep -c 'sleep 2' "$RO_STUB/sleep.log")"
printf '#!/bin/bash\necho 100\n' > "$T/home/aider-venv/bin/nvidia-smi"
o="$(coder_window_close)"
has "close: restored healthy" "$o" "27B restored + healthy"
eq "close removes the hold marker" 0 "$([ -f "$STATE_DIR/coder_window.hold" ] && echo 1 || echo 0)"
has "close removes the eval container" "$(cat "$RO_STUB/docker.log")" "docker rm -f shrike-eval"
touch "$RO_STUB/restore_unhealthy"; : > "$ALERTS_FILE"
o="$(coder_window_close 2>/dev/null)"
has "close: unhealthy restore warns" "$o" "WARNING 27B not healthy after restore"
has "close: unhealthy restore raises an alert" "$(cat "$ALERTS_FILE")" "27B did not health-check after a coder window"
rm -f "$RO_STUB/restore_unhealthy"

echo "--- coder_process_index ---"
ro_tasks '[
 {"id":"c-ok","type":"aider_fix","repo":"/nonexistent/r-ok","prompt":"p","persistent_branch":true,"map_tokens":1000,"protected_files":["a","b"],"timeout_secs":5},
 {"id":"c-off","type":"aider_fix","repo":"/nonexistent/r-off","prompt":"p","enabled":false},
 {"id":"c-train","type":"train_job","project":"x","task":"y"},
 {"id":"c-held","type":"aider_fix","repo":"/nonexistent/r-held","prompt":"p"},
 {"id":"c-stale","type":"aider_fix","repo":"/nonexistent/r-stale","prompt":"p"},
 {"id":"c-oneshot","type":"aider_fix","repo":"/nonexistent/r-one","prompt":"p"}
]'
REPORT_FILE="$T/coder_report.md"; : > "$REPORT_FILE"; LOG_RUN_DIR="$T/tree/logs/coder"; mkdir -p "$LOG_RUN_DIR"; : > "$T/stub/hooks.log"
TASK_COUNT=6; RUN_KEY=RKC; CODER_DONE=""; OVN_CODER_FAST=1
coder_process_index 0
has "coder task reported with (coder) marker" "$(cat "$REPORT_FILE")" "| c-ok | aider_fix |"
has "coder task uses the persistent branch" "$(cat "$REPORT_FILE")" "overnight/feature"
has "item-guard hook called for coder task" "$(cat "$RO_STUB/hooks.log")" "ovn_item_guard.sh /nonexistent/r-ok"
has "cycle-triage hook called for coder task" "$(cat "$RO_STUB/hooks.log")" "ovn_cycle_triage.sh /nonexistent/r-ok"
has "task id appended to CODER_DONE" "$CODER_DONE" " c-ok"
eq "OVN_ACTIVE_MODEL/OVN_EDIT_FORMAT unset afterwards" "" "${OVN_ACTIVE_MODEL:-}${OVN_EDIT_FORMAT:-}"
n0="$(wc -l < "$REPORT_FILE" | tr -d ' ')"
coder_process_index 0
eq "already-done task skipped when OVN_CODER_FAST=1" "$n0" "$(wc -l < "$REPORT_FILE" | tr -d ' ')"
coder_process_index 1; coder_process_index 2
eq "disabled + train_job tasks are ignored" "$n0" "$(wc -l < "$REPORT_FILE" | tr -d ' ')"
touch "$STATE_DIR/HOLD_r-held"
o="$(coder_process_index 3)"
has "fresh hold skips the coder task" "$o" "repo r-held on hold"
eq "held task not reported" "$n0" "$(wc -l < "$REPORT_FILE" | tr -d ' ')"
touch -d '10 hours ago' "$STATE_DIR/HOLD_r-stale"
coder_process_index 4
eq "stale hold auto-expired (file removed) and task processed" "0/1" "$([ -f "$STATE_DIR/HOLD_r-stale" ] && echo 1 || echo 0)/$(grep -c '| c-stale |' "$REPORT_FILE")"
s="$(run_aider_fix_task x /nonexistent/zz p b false "$T/l.log" "" false 2 "" 5 2>/dev/null)"
known_bug "a repo with no .git returns a status that STARTS with 'error' (the log() line at run_overnight.sh:799 goes to stdout and pollutes the captured status, so record_outcome classifies it unknown); patch: log ... >&2" "$(printf '%s' "$s" | head -1 | grep -q '^error' && echo 1 || echo 0)"
coder_process_index 5
has "non-persistent coder task gets a per-run branch" "$(cat "$REPORT_FILE")" "overnight/RKC/c-oneshot"
OVN_CODER_FAST=0

echo "--- coder_fast_prepass ---"
ro_tasks '[
 {"id":"e1","type":"aider_fix","repo":"/nonexistent/e1","prompt":"[T1] fix typo in `a.py`"},
 {"id":"e2","type":"aider_fix","repo":"/nonexistent/e2","prompt":"[T4] refactor the whole module across many files `a.py` `b.py`"},
 {"id":"e3","type":"aider_fix","repo":"/nonexistent/e3","prompt":"x","coder_eligible":true},
 {"id":"e4","type":"aider_fix","repo":"/nonexistent/e4","prompt":"[T1] fix typo in `a.py`","coder_eligible":false},
 {"id":"e5","type":"train_job","project":"x","task":"y"},
 {"id":"e6","type":"aider_fix","repo":"/nonexistent/e6","prompt":"[T1] fix `a.py`","enabled":false},
 {"id":"e7","type":"aider_fix","repo":"/nonexistent/e7","prompt":"[T1] fix `a.py`","persistent_branch":true},
 {"id":"e8","type":"aider_fix","repo":"/nonexistent/e8","prompt":"[T1] fix typo in `a.py`"}
]'
TASK_COUNT=8; CODER_DONE=""; : > "$REPORT_FILE"; : > "$T/stub/hooks.log"
OVN_CODER_MIN_BATCH=9
o="$(coder_fast_prepass)"
has "below break-even: no swap, everything stays on 27B" "$o" "NO coder swap"
eq "below break-even: nothing processed" 0 "$(wc -l < "$REPORT_FILE" | tr -d ' ')"
OVN_CODER_MIN_BATCH=3
printf '#!/bin/bash\nexit 1\n' > "$OVN_SERVE_EVAL"
o="$(coder_fast_prepass)"
has "window open failure falls back to 27B" "$o" "window open FAILED"
has "failed window is closed again" "$o" "restoring 27B"
printf '#!/bin/bash\nexit 0\n' > "$OVN_SERVE_EVAL"
CODER_DONE=""
coder_fast_prepass > "$T/prepass.out"; o="$(cat "$T/prepass.out")"
has "eligible batch reaches break-even 3" "$o" "eligible simple item(s) >= break-even 3"
has "prepass completes" "$o" "CODER FAST BATCH: done ("
known_bug "coder_eligible:false must exclude a task from the coder batch - jq's '//' treats false as empty so explicit=\"\" and the T1 prompt still qualifies it (run_overnight.sh:3034-3035); patch: explicit=\"\$(jq -r \".[\$i].coder_eligible | if . == null then \\\"\\\" else tostring end\" ...)\"" "$(case "$CODER_DONE" in *" e4"*) echo 0;; *) echo 1;; esac)"
eq "explicit-true (e3) and T1-tagged (e1,e8) tasks processed; train/disabled/persistent skipped" " e1 e3 e8" "${CODER_DONE// e4/}"
OVN_CODER_INCLUDE_PERSISTENT=1; OVN_CODER_MIN_BATCH=4; CODER_DONE=""
coder_fast_prepass > "$T/prepass.out"
eq "OVN_CODER_INCLUDE_PERSISTENT=1 adds the persistent T1 task (e7)" " e1 e3 e7 e8" "${CODER_DONE// e4/}"

ro_summary
