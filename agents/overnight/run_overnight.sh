#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Local-LLM Task Runner
# ===========================================
# Waits for the GPU server to be reachable, then runs each task in tasks.json.
# Two task types:
#   - aider_fix (default): runs aider against a repo, committing + pushing a
#     dedicated branch. Never touches main/develop.
#   - train_job: stops the inference container (training needs the GPU to
#     itself), runs a training job on the GPU server, then ALWAYS restarts
#     inference afterward (even if training failed) so chat/aider access is
#     never left down overnight.
#
# Pause/resume: touch state/PAUSED (or `make overnight-pause`) to stop the
# queue from starting any further tasks - e.g. before an active chat session.
# A task already in progress finishes; pause just stops the NEXT one from
# starting. `make overnight-resume` removes the flag.
#
# Usage:
#   ./run_overnight.sh          # normal run (skips if already run tonight)
#   ./run_overnight.sh --force  # re-run tonight even if the marker exists
#
# Intended to be launched by ~/Library/LaunchAgents/com.shrikelabs.overnight-agent.plist
# wrapped in `caffeinate -i` so it isn't interrupted by the Mac re-sleeping.
# ===========================================

set -uo pipefail

# launchd runs agents with a minimal PATH — make sure pipx/homebrew binaries
# (aider, jq, git) are found even though this isn't an interactive shell.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

GPU_SERVER_HOST="${GPU_SERVER_HOST:-192.168.68.145}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL_NAME="${OVERNIGHT_MODEL:-qwen-dflash-35B-A3B}"
LITELLM_BASE="http://${GPU_SERVER_HOST}:4000"

TASKS_FILE="$SCRIPT_DIR/tasks.json"
STATE_DIR="$SCRIPT_DIR/state"
LOG_DIR="$SCRIPT_DIR/logs"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$STATE_DIR" "$LOG_DIR" "$REPORT_DIR"

PAUSE_FLAG="$STATE_DIR/PAUSED"

MAX_WAIT_SECONDS=1800   # give up waiting for the GPU server after 30 min
POLL_INTERVAL_SECONDS=60

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# "Night key": a run between midnight and noon still belongs to the previous
# calendar day's night, so it doesn't create a second marker for the same run.
HOUR="$(date +%H)"
if [ "$HOUR" -lt 12 ]; then
  NIGHT_KEY="$(date -v-1d +%Y-%m-%d)"
else
  NIGHT_KEY="$(date +%Y-%m-%d)"
fi

MARKER="$STATE_DIR/last_run_${NIGHT_KEY}.done"
LOG_NIGHT_DIR="$LOG_DIR/$NIGHT_KEY"
mkdir -p "$LOG_NIGHT_DIR"
REPORT_FILE="$REPORT_DIR/${NIGHT_KEY}.md"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
  log "Already ran for night ${NIGHT_KEY} (marker exists at ${MARKER}). Use --force to rerun."
  exit 0
fi

if [ -f "$PAUSE_FLAG" ]; then
  log "Queue is paused (${PAUSE_FLAG} exists). Skipping tonight's run entirely. Run 'make overnight-resume' to clear."
  exit 0
fi

write_abort_report() {
  {
    echo "# Overnight run report — ${NIGHT_KEY}"
    echo ""
    echo "**Aborted**: $1"
  } > "$REPORT_FILE"
}

log "Waiting for GPU server (${LITELLM_BASE}) to become reachable (up to ${MAX_WAIT_SECONDS}s)..."
WAITED=0
REACHABLE=0
while [ "$WAITED" -lt "$MAX_WAIT_SECONDS" ]; do
  if curl -sf --max-time 5 "${LITELLM_BASE}/health/liveliness" >/dev/null 2>&1 \
    || curl -sf --max-time 5 "${LITELLM_BASE}/health" >/dev/null 2>&1; then
    REACHABLE=1
    break
  fi
  sleep "$POLL_INTERVAL_SECONDS"
  WAITED=$((WAITED + POLL_INTERVAL_SECONDS))
done

if [ "$REACHABLE" -eq 0 ]; then
  log "GPU server never became reachable within ${MAX_WAIT_SECONDS}s. Aborting for tonight."
  write_abort_report "GPU server (${LITELLM_BASE}) was not reachable within ${MAX_WAIT_SECONDS}s."
  exit 1
fi
log "GPU server reachable."

if ! command -v aider >/dev/null 2>&1; then
  log "aider not found on PATH. Aborting."
  write_abort_report "\`aider\` not found on PATH — run \`make overnight-install\` first."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq not found on PATH. Aborting."
  write_abort_report "\`jq\` not found on PATH."
  exit 1
fi

if ! curl -sf --max-time 10 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" "${LITELLM_BASE}/v1/models" \
    | grep -q "\"${MODEL_NAME}\""; then
  log "WARNING: model '${MODEL_NAME}' not found in ${LITELLM_BASE}/v1/models — continuing anyway, but tasks will likely fail. Check with 'curl ${LITELLM_BASE}/v1/models' and set OVERNIGHT_MODEL in .env if needed."
fi

TASK_COUNT="$(jq 'length' "$TASKS_FILE")"
log "Loaded ${TASK_COUNT} task(s) from ${TASKS_FILE}"

{
  echo "# Overnight run report — ${NIGHT_KEY}"
  echo ""
  echo "Model: \`${MODEL_NAME}\` via ${LITELLM_BASE}"
  echo ""
  echo "| Task | Type | Status | Branch/Version | Log |"
  echo "|---|---|---|---|---|"
} > "$REPORT_FILE"

run_aider_fix_task() {
  local id="$1" repo="$2" prompt="$3" branch="$4" task_log="$5"

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

    if ! git checkout -B "$branch" "origin/${DEFAULT_BRANCH}" --quiet 2>/dev/null; then
      git checkout -B "$branch" "$DEFAULT_BRANCH" --quiet
    fi

    BEFORE_SHA="$(git rev-parse HEAD)"

    # Give aider the repo's own dev-standards doc as read-only context, if it
    # has one — aider doesn't discover CLAUDE.md/AGENTS.md on its own.
    READ_ARGS=()
    for f in CLAUDE.md AGENTS.md; do
      if [ -f "$f" ]; then
        READ_ARGS+=(--read "$f")
      fi
    done

    aider --yes-always --no-check-update \
      --model "openai/${MODEL_NAME}" \
      --openai-api-base "${LITELLM_BASE}/v1" \
      --openai-api-key "${LITELLM_MASTER_KEY}" \
      ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
      --message "${prompt}" \
      > "$task_log" 2>&1
    AIDER_EXIT=$?

    AFTER_SHA="$(git rev-parse HEAD)"

    if [ "$AIDER_EXIT" -ne 0 ]; then
      echo "error(exit=${AIDER_EXIT})"
    elif [ "$BEFORE_SHA" != "$AFTER_SHA" ]; then
      if git push origin "$branch" --quiet 2>>"$task_log"; then
        echo "pushed"
      else
        echo "committed-but-push-failed"
      fi
    else
      echo "no-op"
    fi
  )
}

run_train_job_task() {
  local id="$1" project="$2" task_name="$3" engine="$4" version="$5" task_log="$6"

  {
    echo "=== Stopping inference container to free the GPU ==="
    "$REPO_ROOT/scripts/gpu_server_stop_inference.sh"
  } >> "$task_log" 2>&1
  STOP_EXIT=$?

  TRAIN_EXIT=1
  if [ "$STOP_EXIT" -eq 0 ]; then
    {
      echo ""
      echo "=== Running training job: ${project}/${task_name} (engine=${engine}, version=${version}) ==="
      "$REPO_ROOT/scripts/gpu_server_ssh.sh" \
        "cd ~/shrike-ai-lab-training && . .venv/bin/activate && python scripts/train.py --project ${project} --task ${task_name} --engine ${engine} --version ${version}"
    } >> "$task_log" 2>&1
    TRAIN_EXIT=$?
  else
    echo "Skipping training run: failed to stop the inference container (see log)." >> "$task_log"
  fi

  # ALWAYS restart inference afterward, regardless of stop/train success —
  # chat/aider access must never be left down because a training job failed.
  {
    echo ""
    echo "=== Restarting inference container ==="
    "$REPO_ROOT/scripts/gpu_server_restart.sh"
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

REMAINING_SKIPPED=0
for i in $(seq 0 $((TASK_COUNT - 1))); do
  if [ -f "$PAUSE_FLAG" ]; then
    REMAINING_TONIGHT=$((TASK_COUNT - i))
    log "Queue paused mid-run (${PAUSE_FLAG} exists) — stopping before task $((i + 1))/${TASK_COUNT}. ${REMAINING_TONIGHT} task(s) skipped."
    for j in $(seq "$i" $((TASK_COUNT - 1))); do
      SKIPPED_ID="$(jq -r ".[$j].id" "$TASKS_FILE")"
      echo "| ${SKIPPED_ID} | - | skipped(paused) | - | - |" >> "$REPORT_FILE"
    done
    REMAINING_SKIPPED=1
    break
  fi

  ID="$(jq -r ".[$i].id" "$TASKS_FILE")"
  TYPE="$(jq -r ".[$i].type // \"aider_fix\"" "$TASKS_FILE")"
  # NB: jq's `//` treats `false` as falsy too (would silently ignore "enabled": false) -
  # use an explicit null check instead.
  ENABLED="$(jq -r ".[$i].enabled | if . == null then true else . end" "$TASKS_FILE")"
  TASK_LOG="$LOG_NIGHT_DIR/${ID}.log"

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
    VERSION="$(jq -r ".[$i].version // \"overnight-${NIGHT_KEY}-${ID}\"" "$TASKS_FILE")"
    STATUS="$(run_train_job_task "$ID" "$PROJECT" "$TASK_NAME" "$ENGINE" "$VERSION" "$TASK_LOG")"
    VERSION_OR_BRANCH="$VERSION"
  else
    REPO="$(jq -r ".[$i].repo" "$TASKS_FILE")"
    PROMPT="$(jq -r ".[$i].prompt" "$TASKS_FILE")"
    BRANCH="overnight/${NIGHT_KEY}/${ID}"
    STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$TASK_LOG")"
    VERSION_OR_BRANCH="$BRANCH"
  fi

  log "Task ${ID}: ${STATUS}"
  echo "| ${ID} | ${TYPE} | ${STATUS} | ${VERSION_OR_BRANCH} | ${TASK_LOG} |" >> "$REPORT_FILE"
done

touch "$MARKER"
if [ "$REMAINING_SKIPPED" -eq 1 ]; then
  log "Night ${NIGHT_KEY} stopped early due to pause. Report: ${REPORT_FILE}"
else
  log "Night ${NIGHT_KEY} complete. Report: ${REPORT_FILE}"
fi
