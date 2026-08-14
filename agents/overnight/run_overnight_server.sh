#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Task Runner (SERVER-RESIDENT VERSION)
# ===========================================
# Runs entirely ON the GPU server, scheduled via cron (every 2 hours as of
# 2026-08-04 - not once-nightly anymore, see below), not launchd. This exists
# because the original Mac-resident version (run_overnight.sh) requires the
# Mac to be awake, plugged in, and reachable on the home LAN every night -
# which breaks the moment the Mac travels and isn't reliably connected. This
# box stays home, stays on, and doesn't sleep, so it's the right place for
# unattended automation to actually live.
#
# Two task types:
#   - aider_fix: runs aider against a repo cloned locally under repos/,
#     committing + pushing a branch. Never touches main/develop. Two modes:
#       * one-shot (default): fresh branch off the default branch every run
#         (overnight/<run-key>/<id>) - for a single specific, scoped fix.
#       * persistent_branch:true: reuses ONE fixed branch (overnight/feature)
#         across every run, never resetting it - for an ongoing "review
#         status, pick the next TODO, implement it" task that's meant to
#         accumulate work over many runs/weeks until you review and merge it.
#   - train_job: stops the inference container locally (docker stop),
#     trains locally in ~/shrike-ai-lab-training's venv, then ALWAYS
#     restarts inference afterward (even on failure).
#
# CHANGED 2026-08-04: removed the old "already ran tonight" marker/skip
# logic entirely. That was designed for a once-per-night cron trigger; now
# that cron fires every 2 hours and tasks are meant to run every single
# time they're enabled, a per-calendar-day dedup marker would just skip
# every run after the first each day. Cadence is controlled purely by cron
# now - this script always runs its full task loop when invoked. Logs and
# reports are named by a full run timestamp (not just date) so multiple
# same-day runs don't overwrite each other's history.
#
# Safety valve: if the SAME task fails 3 runs in a row, THAT TASK is
# auto-disabled (enabled:false in tasks.json) rather than silently burning
# GPU time on a broken task every 2 hours for weeks. CHANGED 2026-08-08: this
# used to pause the whole queue - live testing showed one structurally-stuck
# task (gitlark repeatedly overflowing context on the same item) took down
# 6 other healthy repos for 4 days with nobody noticing. Now only the
# offending task is disabled; everything else keeps running. Check
# state/failures/<id>.count and the task's own log, fix it, then
# `queue.sh enable <id>`. The global state/PAUSED flag still exists for your
# own manual pause/resume (e.g. during an active chat session) - it's just
# no longer triggered automatically by a single task's failures.
#
# Pause/resume: touch state/PAUSED (from anywhere you can SSH in, e.g. via
# Tailscale from a phone, or `queue.sh pause`) to stop the queue from
# starting further tasks. A task already in progress finishes; pause just
# stops the next one from starting.
#
# Usage:
#   ./run_overnight_server.sh   # always runs the full task loop once
#
# Scheduled via cron (see README.md) - nothing here depends on the Mac
# being present, awake, or reachable.
# ===========================================

set -uo pipefail

export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL_NAME="${OVERNIGHT_MODEL:-qwen-dflash-27B}"
LITELLM_BASE="http://localhost:4000"
INFERENCE_CONTAINER="${INFERENCE_CONTAINER:-shrike-llama-dflash-35b}"

# Explicit context-window metadata for aider (2026-08-08 hardening). Without
# this, aider doesn't recognize the custom model name and warns "Unknown
# context window size and costs, using sane defaults" - it can't proactively
# manage/trim context, it just sends and lets the API 400 on overflow (the
# ContextWindowExceededError failures documented throughout this file).
# Confirmed via `curl .../v1/models` that the real ceiling is 16384 tokens.
MODEL_METADATA_FILE="$SCRIPT_DIR/model-metadata.json"

# Shared quality bar, appended to every aider_fix task's prompt (2026-08-08
# hardening) so it doesn't need to be copy-pasted into every task definition
# and applies uniformly to one-off tasks added later via `queue.sh add` too.
STANDARDS_SUFFIX="

Quality bar: match existing code style, keep the diff minimal and focused on the one item, use the project's existing test framework/layout, don't add new dependencies unless needed. Edit OVERNIGHT_PROGRESS.md's existing 'Next Steps' section in place (never add a second one; never re-add a done/existing item). Before adding a new function, grep for its name first - edit the existing one rather than adding a duplicate definition. Be decisive: pick the files you need in ONE pass and stop - do not narrate a long chain of 'let me also check this file... and this one... and this one' before ever writing code. If you are not sure a file is needed, do not ask for it - work with what you have and adjust later if a real problem shows up."
TRAINING_DIR="$HOME/shrike-ai-lab-training"

TASKS_FILE="$SCRIPT_DIR/tasks.json"
STATE_DIR="$SCRIPT_DIR/state"
FAIL_DIR="$STATE_DIR/failures"
LOG_DIR="$SCRIPT_DIR/logs"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$STATE_DIR" "$FAIL_DIR" "$LOG_DIR" "$REPORT_DIR"

PAUSE_FLAG="$STATE_DIR/PAUSED"
MAX_CONSECUTIVE_FAILURES=3

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Concurrency lock. Found by live testing (2026-08-08): a slow manual
# `run-now` was still in progress when the next scheduled cron tick fired,
# producing two run_overnight.sh processes walking the same tasks.json
# concurrently - no corruption happened this time, but two processes racing
# git checkout/commit on the same repo checkout is a real risk, and both
# aider calls competing for the one inference container also just slows
# everything down further, making the next overlap more likely. Non-blocking:
# if another run is already in progress, skip this invocation entirely
# rather than queue up behind it - the next cron tick will pick up any
# skipped work anyway.
LOCK_FILE="$STATE_DIR/run.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "Another run_overnight.sh is already in progress (lock: ${LOCK_FILE}) — skipping this invocation entirely."
  exit 0
fi

RUN_KEY="$(date +%Y%m%d-%H%M%S)"
LOG_RUN_DIR="$LOG_DIR/$RUN_KEY"
mkdir -p "$LOG_RUN_DIR"
REPORT_FILE="$REPORT_DIR/${RUN_KEY}.md"

if [ -f "$PAUSE_FLAG" ]; then
  log "Queue is paused (${PAUSE_FLAG} exists). Skipping this run entirely."
  exit 0
fi

write_abort_report() {
  {
    echo "# Overnight run report — ${RUN_KEY}"
    echo ""
    echo "**Aborted**: $1"
  } > "$REPORT_FILE"
}

# Quick local check only - no long wait loop needed since this script only
# runs on the box that IS the GPU server.
if ! curl -sf --max-time 10 "${LITELLM_BASE}/health/liveliness" >/dev/null 2>&1 \
    && ! curl -sf --max-time 10 "${LITELLM_BASE}/health" >/dev/null 2>&1; then
  log "LiteLLM (${LITELLM_BASE}) not responding. Aborting this run."
  write_abort_report "LiteLLM (${LITELLM_BASE}) was not reachable — check \`docker ps\` on this box."
  exit 1
fi

if ! command -v aider >/dev/null 2>&1; then
  log "aider not found on PATH. Aborting."
  write_abort_report "\`aider\` not found on PATH — check ~/aider-venv/bin/aider exists."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq not found on PATH. Aborting."
  write_abort_report "\`jq\` not found on PATH."
  exit 1
fi

if ! curl -sf --max-time 10 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" "${LITELLM_BASE}/v1/models" \
    | grep -q "\"${MODEL_NAME}\""; then
  log "WARNING: model '${MODEL_NAME}' not found in ${LITELLM_BASE}/v1/models — continuing anyway."
fi

TASK_COUNT="$(jq 'length' "$TASKS_FILE")"
log "Loaded ${TASK_COUNT} task(s) from ${TASKS_FILE}"

{
  echo "# Overnight run report — ${RUN_KEY}"
  echo ""
  echo "Model: \`${MODEL_NAME}\` via ${LITELLM_BASE} (server-resident run)"
  echo ""
  echo "| Task | Type | Status | Branch/Version | Log |"
  echo "|---|---|---|---|---|"
} > "$REPORT_FILE"

# Post-commit test verification (2026-08-08 hardening). Best-effort: only
# runs suites that are ALREADY provisioned (a real .venv with pytest, or
# node_modules already installed) - never installs anything itself, so it's
# a safe no-op ("none") on a repo that hasn't been provisioned, rather than
# attempting a slow/flaky unattended `npm install`/`pip install` every
# cycle. Must be called with cwd already inside the target repo. Appends
# real output to $task_log (global, set by the caller) and returns one of:
# "pass" (something ran and all green), "fail" (something ran, at least one
# failure), "none" (nothing provisioned to run).
run_repo_verification() {
  local any_ran=0 any_failed=0 dir

  while IFS= read -r -d '' venv_pytest; do
    dir="${venv_pytest%/.venv/bin/pytest}"
    echo "--- verify: pytest in ${dir} (120s cap) ---" >> "$task_log"
    ( cd "$dir" && timeout 120 ./.venv/bin/pytest -q --no-cov ) >> "$task_log" 2>&1
    [ $? -ne 0 ] && any_failed=1
    any_ran=1
  done < <(find . -maxdepth 4 -type f -path "*/.venv/bin/pytest" -print0 2>/dev/null)

  while IFS= read -r -d '' pkg; do
    dir="$(dirname "$pkg")"
    if [ -d "${dir}/node_modules" ] && grep -q '"test"[[:space:]]*:' "$pkg"; then
      echo "--- verify: npm test in ${dir} (120s cap - if this project's test script defaults to interactive watch mode, this will time out rather than hang forever; check the log) ---" >> "$task_log"
      # CI=true: several repos' "test" script is plain "vitest" (not
      # "vitest --run"), which defaults to interactive watch mode outside
      # CI and would hang until the timeout kills it - vitest/Jest/CRA all
      # respect CI=true to run once and exit instead.
      ( cd "$dir" && CI=true timeout 120 npm test --silent ) >> "$task_log" 2>&1
      [ $? -ne 0 ] && any_failed=1
      any_ran=1
    fi
  done < <(find . -maxdepth 4 -type f -name "package.json" -not -path "*/node_modules/*" -print0 2>/dev/null)

  if [ "$any_ran" -eq 0 ]; then
    echo "none"
  elif [ "$any_failed" -eq 1 ]; then
    echo "fail"
  else
    echo "pass"
  fi
}

run_aider_fix_task() {
  local id="$1" repo="$2" prompt="$3" branch="$4" persistent="$5" task_log="$6" map_tokens="$7" skip_agents_md="$8" max_files="${9:-2}"

  if [ ! -d "$repo/.git" ]; then
    log "Repo ${repo} has no .git checkout — skipping"
    echo "error: no .git at ${repo}"
    return
  fi

  (
    cd "$repo" || exit 1

    DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
    DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
    git fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null
    git fetch origin "$branch" --quiet 2>/dev/null

    if [ "$persistent" = "true" ] && git rev-parse --verify --quiet "$branch" >/dev/null; then
      # Branch already exists locally from a previous run - keep building on
      # it, don't reset (that would discard all prior accumulated work).
      git checkout "$branch" --quiet
    elif [ "$persistent" = "true" ] && git rev-parse --verify --quiet "origin/${branch}" >/dev/null; then
      # Exists on the remote (e.g. queue restarted) but not local yet.
      git checkout -B "$branch" "origin/${branch}" --quiet
    elif ! git checkout -B "$branch" "origin/${DEFAULT_BRANCH}" --quiet 2>/dev/null; then
      git checkout -B "$branch" "$DEFAULT_BRANCH" --quiet
    fi

    # Discovered by live testing: this model's udiff output is reliable for
    # editing existing files, but unreliable for synthesizing a brand-new
    # prose file from scratch - it sometimes emits a hunk aider can't apply
    # at all (silent no-op), and sometimes an empty 0-byte file gets
    # committed. Sidestep this entirely by having bash stub the file out
    # first (plain heredoc, no LLM involved) whenever the task's prompt
    # references it - aider then only ever has to EDIT an existing file,
    # which it does reliably.
    if [[ "$prompt" == *"OVERNIGHT_PROGRESS.md"* ]] && [ ! -f "OVERNIGHT_PROGRESS.md" ]; then
      cat > OVERNIGHT_PROGRESS.md <<'STUB'
# Overnight Progress

## Current Status
(not yet reviewed)

## Next Steps
(not yet populated)
STUB
      git add OVERNIGHT_PROGRESS.md
      git commit -m "chore: stub OVERNIGHT_PROGRESS.md" --quiet
    fi

    BEFORE_SHA="$(git rev-parse HEAD)"

    # OVERNIGHT_PROGRESS.md is always pre-loaded as an editable file, not
    # counted against max_files - it's the queue's own bookkeeping doc
    # (typically 1-2KB) and was previously never actually added to the
    # chat (excluded from scan_for_new_files as a .md file), meaning the
    # model edited it "blind" without ever seeing its real current
    # content - the likely cause of the duplicate "Next Steps" sections
    # found in iptv_apps and test-automation-agent (2026-08-13).
    PROGRESS_FILE_ARGS=()
    if [ -f "OVERNIGHT_PROGRESS.md" ]; then
      PROGRESS_FILE_ARGS=(--file "OVERNIGHT_PROGRESS.md")
    fi

    READ_ARGS=()
    if [ "$skip_agents_md" != "true" ]; then
      for f in CLAUDE.md AGENTS.md; do
        if [ -f "$f" ]; then
          READ_ARGS+=(--read "$f")
        fi
      done
    fi

    # --edit-format udiff: aider doesn't recognize this custom model name, so
    # it defaults to the fragile "whole" format (expects the model to output
    # the entire file). This model naturally outputs unified-diff hunks
    # instead, which "whole" can't parse - aider then silently no-ops (shows
    # a plausible-looking diff in the log, but never actually commits).
    # Confirmed by testing: forcing "udiff" (which matches the model's
    # natural output) fixes this - verified a real commit gets created.
    AIDER_BASE_ARGS=(
      --yes-always --no-check-update --edit-format udiff
      --model "openai/${MODEL_NAME}"
      --openai-api-base "${LITELLM_BASE}/v1"
      --openai-api-key "${LITELLM_MASTER_KEY}"
    )
    if [ -f "$MODEL_METADATA_FILE" ]; then
      AIDER_BASE_ARGS+=(--model-metadata-file "$MODEL_METADATA_FILE")
    fi
    # Per-task override for large repos: aider's default repo-map budget
    # scales with repo size, and for a repo with hundreds of files the
    # map alone (before any task file is even loaded) can already consume
    # most of the 16,384-token window. Set via the task's "map_tokens"
    # field in tasks.json.
    if [ -n "$map_tokens" ] && [ "$map_tokens" != "null" ]; then
      AIDER_BASE_ARGS+=(--map-tokens "$map_tokens")
    fi

    full_prompt="${prompt}${STANDARDS_SUFFIX}"

    # Iterative file-feeding. Root cause found by live testing (2026-08-08):
    # aider's single-shot `--message` mode does NOT loop back after the
    # model asks to add more files mid-conversation - if the model's first
    # move is "please add file X", the run just ends there with nothing
    # done (confirmed: billwatch/task-manager-platform/test-automation-agent
    # all stalled exactly this way for multiple cycles). Aider DOES support
    # pre-loading files via --file before the message is sent, so: pass 1
    # asks (read-only, no edits expected) which files it needs; each
    # subsequent pass re-scans the transcript so far for newly-mentioned
    # existing files, adds any not already loaded, and retries - up to
    # MAX_IMPLEMENT_ATTEMPTS times, stopping early on a real commit or once
    # a retry surfaces no new file to add.
    #
    # A second bug found during that same testing: the naive first version
    # of this (bare-path-line matching against the whole log) kept picking
    # up README.md/OVERNIGHT_PROGRESS.md/AGENTS.md as "requested files" -
    # aider silently auto-adds any file mentioned in the message TEXT
    # ITSELF to the chat and echoes that as a bare filename line, which is
    # indistinguishable from the model's real answer under a pure
    # exists-on-disk check. Since the prompt text always mentions
    # OVERNIGHT_PROGRESS.md, this wasted the file budget on it every time.
    # Fixed by excluding markdown docs from candidates (real code-file needs
    # don't come through as .md) and by extracting path-like tokens instead
    # of requiring the WHOLE line to be a bare path, since the model often
    # appends trailing prose on the same line ("services/foo.py (the
    # service under test)").
    MAX_IMPLEMENT_ATTEMPTS=2
    FILE_ARGS=()
    ADDED_FILES="|"

    scan_for_new_files() {
      local found_new=0
      local cand
      while IFS= read -r cand; do
        [ -z "$cand" ] && continue
        case "$cand" in
          *.md) continue ;;
        esac
        case "$ADDED_FILES" in
          *"|${cand}|"*) continue ;;
        esac
        if [ -f "$cand" ] && [ "${#FILE_ARGS[@]}" -lt $((max_files * 2)) ]; then
          FILE_ARGS+=(--file "$cand")
          ADDED_FILES="${ADDED_FILES}${cand}|"
          found_new=1
        fi
      done < <(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}' "$task_log" | sort -u)
      [ "$found_new" -eq 1 ]
    }

    SCOUT_PROMPT="Before doing anything else: decide which existing repo files (at most ${max_files}) you would need to see in full to complete the task below. Reply with ONLY those file paths relative to the repo root, one per line, and nothing else - no explanation, no edits. If you don't need to see any files beyond what is already open, reply with exactly: NONE

Task: ${full_prompt}"

    # timeout wrapper (2026-08-08 hardening): if the inference server hangs
    # mid-request, aider would otherwise block forever - combined with the
    # concurrency lock, that would freeze the queue permanently until
    # someone manually intervenes. 600s is generous for a single completion.
    timeout 600 aider "${AIDER_BASE_ARGS[@]}" \
      ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
      ${PROGRESS_FILE_ARGS[@]+"${PROGRESS_FILE_ARGS[@]}"} \
      --message "${SCOUT_PROMPT}" \
      > "$task_log" 2>&1
    AIDER_EXIT=$?
    scan_for_new_files || true

    SCOUT_SHA="$(git rev-parse HEAD)"
    if [ "$SCOUT_SHA" = "$BEFORE_SHA" ]; then
      ATTEMPT=1
      while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do
        echo "--- implement attempt ${ATTEMPT}/${MAX_IMPLEMENT_ATTEMPTS} (${#FILE_ARGS[@]} file(s) pre-loaded) ---" >> "$task_log"
        timeout 600 aider "${AIDER_BASE_ARGS[@]}" \
          ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
          ${PROGRESS_FILE_ARGS[@]+"${PROGRESS_FILE_ARGS[@]}"} \
          ${FILE_ARGS[@]+"${FILE_ARGS[@]}"} \
          --message "${full_prompt}" \
          >> "$task_log" 2>&1
        AIDER_EXIT=$?

        NOW_SHA="$(git rev-parse HEAD)"
        if [ "$NOW_SHA" != "$BEFORE_SHA" ]; then
          break
        fi
        if [ "$ATTEMPT" -eq "$MAX_IMPLEMENT_ATTEMPTS" ] || ! scan_for_new_files; then
          break
        fi
        ATTEMPT=$((ATTEMPT + 1))
      done
    else
      # Model ignored the "no edits" instruction and just did the work in
      # the scout pass - don't run a second pass on top of it (a fresh model
      # invocation could redo/duplicate what it already just committed).
      echo "--- scout pass unexpectedly committed real work - skipping implement pass ---" >> "$task_log"
    fi

    AFTER_SHA="$(git rev-parse HEAD)"

    if [ "$AIDER_EXIT" -ne 0 ]; then
      echo "error(exit=${AIDER_EXIT})"
    elif [ "$BEFORE_SHA" != "$AFTER_SHA" ]; then
      # Post-commit verification (2026-08-08 hardening). Provisioned once,
      # server-side, for all 7 repos (real .venv/node_modules, not
      # reinstalled every cycle - see docs/ops/LOCAL_LLM_UPGRADE_PLAN.md).
      # Runs whatever test suite already exists in THIS repo and puts the
      # real pass/fail into the log and the report status, instead of only
      # trusting the model's own "I ran the tests" claim. Deliberately does
      # NOT feed into the consecutive-failure safety valve - a real code
      # regression and an environment/flake-caused failure look identical
      # here, and auto-disabling a task over the latter would be worse than
      # just surfacing it for you to glance at in the report.
      VERIFY_RESULT="$(run_repo_verification)"
      if git push origin "$branch" --quiet 2>>"$task_log"; then
        case "$VERIFY_RESULT" in
          fail) echo "pushed(tests:FAIL - see log)" ;;
          pass) echo "pushed(tests:pass)" ;;
          *) echo "pushed" ;;
        esac
      else
        echo "committed-but-push-failed"
      fi
    elif grep -qE "ContextWindowExceededError|BadRequestError|APIError|RateLimitError|Traceback \(most recent call last\)" "$task_log"; then
      # Aider often exits 0 even after an internal API exception (e.g. the
      # model asking for more files than fit in its 16384-token context) -
      # it just prints the error and stops, which looks identical to a
      # genuine "nothing needed changing" no-op unless we check the log
      # content too. Without this, a systematically-broken task (like a
      # context overflow) would report "no-op" forever and never trip the
      # consecutive-failure safety valve below.
      echo "error(model/API error - see log)"
    else
      echo "no-op"
    fi
  )
}

run_train_job_task() {
  local id="$1" project="$2" task_name="$3" engine="$4" version="$5" task_log="$6"

  {
    echo "=== Stopping inference container (${INFERENCE_CONTAINER}) to free the GPU ==="
    docker stop "${INFERENCE_CONTAINER}"
  } >> "$task_log" 2>&1
  STOP_EXIT=$?

  TRAIN_EXIT=1
  if [ "$STOP_EXIT" -eq 0 ]; then
    {
      echo ""
      echo "=== Running training job: ${project}/${task_name} (engine=${engine}, version=${version}) ==="
      cd "$TRAINING_DIR" && . .venv/bin/activate && python scripts/train.py \
        --project "${project}" --task "${task_name}" --engine "${engine}" --version "${version}"
    } >> "$task_log" 2>&1
    TRAIN_EXIT=$?
  else
    echo "Skipping training run: failed to stop the inference container (see log)." >> "$task_log"
  fi

  # ALWAYS restart inference afterward, regardless of stop/train success.
  {
    echo ""
    echo "=== Restarting inference container ==="
    docker start "${INFERENCE_CONTAINER}"
    for i in $(seq 1 24); do
      HEALTH="$(docker inspect --format='{{.State.Health.Status}}' "${INFERENCE_CONTAINER}" 2>/dev/null || echo unknown)"
      echo "  [$i] health: ${HEALTH}"
      [ "$HEALTH" = "healthy" ] && break
      sleep 5
    done
  } >> "$task_log" 2>&1
  RESTART_EXIT=$?

  if [ "$STOP_EXIT" -ne 0 ]; then
    echo "error(could not stop inference, exit=${STOP_EXIT})"
  elif [ "$TRAIN_EXIT" -ne 0 ]; then
    echo "error(training exit=${TRAIN_EXIT}, inference restart exit=${RESTART_EXIT})"
  elif [ "$RESTART_EXIT" -ne 0 ]; then
    echo "trained-but-inference-restart-failed(exit=${RESTART_EXIT}) — check manually"
  else
    echo "trained"
  fi
}

# Consecutive-failure tracking: bumps a per-task counter file on error/no-op,
# resets it on any non-error outcome. If a task hits MAX_CONSECUTIVE_FAILURES,
# auto-disable THAT TASK (not the whole queue - see header comment) rather
# than keep burning GPU time on it every 2 hours indefinitely.
check_and_record_failure() {
  local id="$1" status="$2"
  local count_file="$FAIL_DIR/${id}.count"
  case "$status" in
    error*|committed-but-push-failed)
      local count=0
      [ -f "$count_file" ] && count="$(cat "$count_file")"
      count=$((count + 1))
      echo "$count" > "$count_file"
      if [ "$count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
        jq --arg id "$id" '(.[] | select(.id == $id)).enabled = false' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
        log "SAFETY VALVE: task '${id}' has failed ${count} times in a row — auto-disabled THIS TASK ONLY (the rest of the queue keeps running). Check ${FAIL_DIR}/${id}.count and its log, fix the issue, then 'queue.sh enable ${id}'."
      fi
      ;;
    *)
      rm -f "$count_file"
      ;;
  esac
}

REMAINING_SKIPPED=0
for i in $(seq 0 $((TASK_COUNT - 1))); do
  if [ -f "$PAUSE_FLAG" ]; then
    REMAINING_NOW=$((TASK_COUNT - i))
    log "Queue paused mid-run (${PAUSE_FLAG} exists) — stopping before task $((i + 1))/${TASK_COUNT}. ${REMAINING_NOW} task(s) skipped."
    for j in $(seq "$i" $((TASK_COUNT - 1))); do
      SKIPPED_ID="$(jq -r ".[$j].id" "$TASKS_FILE")"
      echo "| ${SKIPPED_ID} | - | skipped(paused) | - | - |" >> "$REPORT_FILE"
    done
    REMAINING_SKIPPED=1
    break
  fi

  ID="$(jq -r ".[$i].id" "$TASKS_FILE")"
  TYPE="$(jq -r ".[$i].type // \"aider_fix\"" "$TASKS_FILE")"
  ENABLED="$(jq -r ".[$i].enabled | if . == null then true else . end" "$TASKS_FILE")"
  TASK_LOG="$LOG_RUN_DIR/${ID}.log"

  if [ "$ENABLED" != "true" ]; then
    log "Task ${ID} (type=${TYPE}) is disabled — skipping"
    echo "| ${ID} | ${TYPE} | disabled | - | - |" >> "$REPORT_FILE"
    continue
  fi

  log "=== Task ${ID} (type=${TYPE}) ==="

  if [ "$TYPE" = "train_job" ]; then
    PROJECT="$(jq -r ".[$i].project" "$TASKS_FILE")"
    TASK_NAME="$(jq -r ".[$i].task" "$TASKS_FILE")"
    ENGINE="$(jq -r ".[$i].engine // \"unsloth\"" "$TASKS_FILE")"
    VERSION="$(jq -r ".[$i].version // \"overnight-${RUN_KEY}-${ID}\"" "$TASKS_FILE")"
    STATUS="$(run_train_job_task "$ID" "$PROJECT" "$TASK_NAME" "$ENGINE" "$VERSION" "$TASK_LOG")"
    VERSION_OR_BRANCH="$VERSION"
  else
    REPO="$(jq -r ".[$i].repo" "$TASKS_FILE")"
    PROMPT="$(jq -r ".[$i].prompt" "$TASKS_FILE")"
    PERSISTENT="$(jq -r ".[$i].persistent_branch // false" "$TASKS_FILE")"
    MAP_TOKENS="$(jq -r ".[$i].map_tokens // \"\"" "$TASKS_FILE")"
    SKIP_AGENTS_MD="$(jq -r ".[$i].skip_agents_md // false" "$TASKS_FILE")"
    MAX_FILES="$(jq -r ".[$i].max_files // 2" "$TASKS_FILE")"
    if [ "$PERSISTENT" = "true" ]; then
      BRANCH="overnight/feature"
    else
      BRANCH="overnight/${RUN_KEY}/${ID}"
    fi
    STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" "$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES")"
    VERSION_OR_BRANCH="$BRANCH"
  fi

  log "Task ${ID}: ${STATUS}"
  echo "| ${ID} | ${TYPE} | ${STATUS} | ${VERSION_OR_BRANCH} | ${TASK_LOG} |" >> "$REPORT_FILE"
  check_and_record_failure "$ID" "$STATUS"
done

if [ "$REMAINING_SKIPPED" -eq 1 ]; then
  log "Run ${RUN_KEY} stopped early due to pause. Report: ${REPORT_FILE}"
else
  log "Run ${RUN_KEY} complete. Report: ${REPORT_FILE}"
fi
