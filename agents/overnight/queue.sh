#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Queue Control (phone/SSH-friendly)
# ===========================================
# One short command instead of remembering paths - designed to be a single
# tappable snippet in a mobile SSH app (e.g. Termius) over Tailscale.
#
# Usage (run ON the GPU server, e.g. via SSH from your phone):
#   ~/overnight-queue/queue.sh status
#   ~/overnight-queue/queue.sh pause
#   ~/overnight-queue/queue.sh resume
#   ~/overnight-queue/queue.sh report [N]     # latest report, or N nights ago
#   ~/overnight-queue/queue.sh log <task-id>  # tail the most recent log for a task
#   ~/overnight-queue/queue.sh run-now
#   ~/overnight-queue/queue.sh enable <task-id>
#   ~/overnight-queue/queue.sh disable <task-id>
#   ~/overnight-queue/queue.sh list           # show all tasks + enabled state
#   ~/overnight-queue/queue.sh repos          # show repos available for `add`
#   ~/overnight-queue/queue.sh add <task-id> <repo-name> <prompt text...>
#                                              # new aider_fix task, enabled by
#                                              # default. No quoting needed -
#                                              # everything after <repo-name>
#                                              # becomes the prompt verbatim.
#   ~/overnight-queue/queue.sh remove <task-id>
#   ~/overnight-queue/queue.sh hold <repo-name>    # skip a repo while you edit it
#   ~/overnight-queue/queue.sh release <repo-name>
#   ~/overnight-queue/queue.sh alerts [N]          # recent runner alerts
#   ~/overnight-queue/queue.sh ack                 # clear current alerts
# ===========================================

set -uo pipefail

DIR="$HOME/overnight-queue"
TASKS="$DIR/tasks.json"

cmd="${1:-status}"

case "$cmd" in
  status)
    echo "=== scheduling ==="
    # CHANGED 2026-08-15: was a fixed "every 2 hours" cron entry, which left
    # the GPU idle ~88% of the time (measured live: ~126 min of real work
    # out of 1080 min/9 cycles on 2026-08-15). Replaced with a systemd
    # service (Restart=always, RestartSec=20) that re-runs the queue back
    # to back with just a 20s cooldown, so it's actually working almost
    # continuously instead of waiting up to 2 hours between attempts.
    if systemctl is-active overnight-queue.service >/dev/null 2>&1; then
      echo "overnight-queue.service: active (continuous loop, ~20s between cycles)"
    else
      echo "overnight-queue.service: NOT ACTIVE - check: systemctl status overnight-queue.service"
    fi
    echo ""
    echo "=== pause state ==="
    if [ -f "$DIR/state/PAUSED" ]; then echo "PAUSED (queue.sh resume to continue)"; else echo "Not paused"; fi
    echo ""
    echo "=== latest run ==="
    LATEST_REPORT="$(ls -t "$DIR"/reports/*.md 2>/dev/null | head -1)"
    if [ -n "$LATEST_REPORT" ]; then
      echo "$(basename "$LATEST_REPORT" .md)  (queue.sh report for the full table)"
    else
      echo "None yet"
    fi
    echo ""
    # A task can be disabled either by you, or by the safety valve after 3
    # consecutive failures (see run_overnight.sh) - surface which, so a
    # silently-stuck task doesn't go unnoticed for days like it did once.
    echo "=== disabled tasks ==="
    DISABLED="$(jq -r '.[] | select((.enabled | if . == null then true else . end) == false) | .id' "$TASKS")"
    if [ -z "$DISABLED" ]; then
      echo "None"
    else
      echo "$DISABLED" | while read -r id; do
        COUNT_FILE="$DIR/state/failures/${id}.count"
        if [ -f "$COUNT_FILE" ]; then
          echo "  ${id}  <- AUTO-DISABLED by safety valve (failed $(cat "$COUNT_FILE")x in a row). Check: queue.sh log ${id}"
        else
          echo "  ${id}  (manually disabled)"
        fi
      done
    fi
    echo ""
    echo "=== holds (repos a human is editing; runner skips them) ==="
    HELD="$(ls "$DIR"/state/HOLD_* 2>/dev/null | sed 's#.*/HOLD_##')"
    if [ -z "$HELD" ]; then echo "None"; else echo "$HELD" | while read -r r; do echo "  ${r}  (queue.sh release ${r} to clear)"; done; fi
    echo ""
    echo "=== recent alerts (queue.sh alerts for more, queue.sh ack to clear) ==="
    if [ -s "$DIR/state/alerts.log" ]; then tail -5 "$DIR/state/alerts.log"; else echo "None"; fi
    echo ""
    echo "=== inference container ==="
    docker ps --filter name=shrike-llama --format '{{.Names}}: {{.Status}}'
    ;;

  pause)
    mkdir -p "$DIR/state"
    touch "$DIR/state/PAUSED"
    echo "Paused. In-progress task still finishes; no new tasks will start."
    ;;

  resume)
    rm -f "$DIR/state/PAUSED"
    echo "Resumed."
    ;;

  report)
    N="${2:-1}"
    FILE="$(ls -t "$DIR"/reports/*.md 2>/dev/null | sed -n "${N}p")"
    if [ -z "$FILE" ]; then echo "No report found."; else cat "$FILE"; fi
    ;;

  log)
    TASK_ID="${2:-}"
    if [ -z "$TASK_ID" ]; then echo "Usage: queue.sh log <task-id>"; exit 1; fi
    FILE="$(ls -t "$DIR"/logs/*/"${TASK_ID}".log 2>/dev/null | head -1)"
    if [ -z "$FILE" ]; then echo "No log found for ${TASK_ID}."; else tail -60 "$FILE"; fi
    ;;

  run-now)
    "$DIR/run_overnight.sh"
    ;;

  list)
    # NB: jq's `//` treats `false` as falsy too, not just null - would show
    # "enabled=true" for every disabled task. Use an explicit null check.
    jq -r '.[] | "\(.id)  [\(.type // "aider_fix")]  enabled=\(.enabled | if . == null then true else . end)"' "$TASKS"
    ;;

  enable)
    TASK_ID="${2:-}"
    if [ -z "$TASK_ID" ]; then echo "Usage: queue.sh enable <task-id>"; exit 1; fi
    jq --arg id "$TASK_ID" '(.[] | select(.id == $id)).enabled = true' "$TASKS" > "$TASKS.tmp" && mv "$TASKS.tmp" "$TASKS"
    # Reset the safety-valve failure counter (2026-08-25 Tier-2 hardening).
    # Forgetting to `rm state/failures/<id>.count` after a manual re-enable has
    # bitten every single time — a stale count sitting at the trip threshold
    # re-disables the task on its very next minor hiccup. Do it automatically.
    rm -f "$DIR/state/failures/${TASK_ID}.count"
    echo "Enabled ${TASK_ID} (failure counter reset)."
    ;;

  disable)
    TASK_ID="${2:-}"
    if [ -z "$TASK_ID" ]; then echo "Usage: queue.sh disable <task-id>"; exit 1; fi
    jq --arg id "$TASK_ID" '(.[] | select(.id == $id)).enabled = false' "$TASKS" > "$TASKS.tmp" && mv "$TASKS.tmp" "$TASKS"
    echo "Disabled ${TASK_ID}."
    ;;

  repos)
    ls "$DIR/repos"
    ;;

  add)
    TASK_ID="${2:-}"
    REPO_NAME="${3:-}"
    if [ -z "$TASK_ID" ] || [ -z "$REPO_NAME" ]; then
      echo "Usage: queue.sh add <task-id> <repo-name> <prompt text...>"
      echo "Available repos: $(ls "$DIR/repos" 2>/dev/null | tr '\n' ' ')"
      exit 1
    fi
    shift 3
    PROMPT="$*"
    if [ -z "$PROMPT" ]; then
      echo "Usage: queue.sh add <task-id> <repo-name> <prompt text...> - prompt can't be empty"
      exit 1
    fi
    REPO_PATH="$DIR/repos/$REPO_NAME"
    if [ ! -d "$REPO_PATH/.git" ]; then
      echo "No cloned repo at ${REPO_PATH}."
      echo "Available repos: $(ls "$DIR/repos" 2>/dev/null | tr '\n' ' ')"
      exit 1
    fi
    if jq -e --arg id "$TASK_ID" '.[] | select(.id == $id)' "$TASKS" >/dev/null; then
      echo "A task with id '${TASK_ID}' already exists - pick a different id or 'remove' it first."
      exit 1
    fi
    jq --arg id "$TASK_ID" --arg repo "$REPO_PATH" --arg prompt "$PROMPT" \
      '. + [{"id": $id, "type": "aider_fix", "enabled": true, "repo": $repo, "prompt": $prompt}]' \
      "$TASKS" > "$TASKS.tmp" && mv "$TASKS.tmp" "$TASKS"
    echo "Added '${TASK_ID}' (repo: ${REPO_NAME}, enabled). Runs on the next"
    echo "scheduled cron pass, or right now with: queue.sh run-now"
    ;;

  remove)
    TASK_ID="${2:-}"
    if [ -z "$TASK_ID" ]; then echo "Usage: queue.sh remove <task-id>"; exit 1; fi
    jq --arg id "$TASK_ID" 'del(.[] | select(.id == $id))' "$TASKS" > "$TASKS.tmp" && mv "$TASKS.tmp" "$TASKS"
    echo "Removed ${TASK_ID}."
    ;;

  hold)
    # Hold a repo the runner is cycling so you can safely edit its working tree
    # without racing the ~20s reset. Keyed by repo BASENAME (as shown by
    # `queue.sh repos`), not task id — one repo can back several tasks. Safer
    # than `disable`: leaves the failure counter untouched, and auto-expires
    # after HOLD_MAX_HOURS (6h) in the runner so a forgotten hold can't freeze
    # a repo silently.
    REPO_NAME="${2:-}"
    if [ -z "$REPO_NAME" ]; then echo "Usage: queue.sh hold <repo-name>  (see: queue.sh repos)"; exit 1; fi
    mkdir -p "$DIR/state"
    touch "$DIR/state/HOLD_${REPO_NAME}"
    echo "Held ${REPO_NAME}. Runner will skip its task(s) until 'queue.sh release ${REPO_NAME}' (auto-expires after 6h)."
    ;;

  release)
    REPO_NAME="${2:-}"
    if [ -z "$REPO_NAME" ]; then echo "Usage: queue.sh release <repo-name>"; exit 1; fi
    rm -f "$DIR/state/HOLD_${REPO_NAME}"
    echo "Released ${REPO_NAME}."
    ;;

  alerts)
    N="${2:-20}"
    if [ -s "$DIR/state/alerts.log" ]; then tail -"$N" "$DIR/state/alerts.log"; else echo "No alerts."; fi
    ;;

  ack)
    # Archive-and-clear current alerts so `status` goes quiet again. History is
    # preserved in alerts.log.acked.
    if [ -s "$DIR/state/alerts.log" ]; then
      cat "$DIR/state/alerts.log" >> "$DIR/state/alerts.log.acked"
      : > "$DIR/state/alerts.log"
      echo "Acknowledged; history kept in alerts.log.acked."
    else
      echo "No alerts to ack."
    fi
    ;;

  *)
    echo "Usage: queue.sh {status|pause|resume|report [N]|log <task-id>|run-now|list|repos|enable <id>|disable <id>|add <id> <repo> <prompt...>|remove <id>|hold <repo>|release <repo>|alerts [N]|ack}"
    exit 1
    ;;
esac
