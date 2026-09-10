#!/usr/bin/env bash
# Art/animation queue control (mirrors queue.sh for the code fleet).
#   art.sh add <type> <key> "<prompt>" [seed]   # queue a task (type: unit|sprite|icon|tile)
#   art.sh list                                  # show queued + staged tasks
#   art.sh run                                   # generate the queue NOW (grabs the GPU; 27B pauses, auto-restores after)
#   art.sh status                                # GPU + queue + runner state
#   art.sh review                                # list staged art awaiting review
#   art.sh remove "<substring>"                  # drop a queued task
set -uo pipefail
DIR="$HOME/overnight-queue"
Q="$DIR/art_queue.md"
PY="/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI/.venv/bin/python"  # torch+diffusers venv
RUNNER="$DIR/art_runner.py"
LLAMA="shrike-llama-dflash-35b"
STAGE="$DIR/repos/xlite/assets/staging/art-review"
LOG="$DIR/logs/art_runner.log"
cmd="${1:-status}"; shift || true

case "$cmd" in
  add)
    type="${1:?type: unit|sprite|icon|tile}"; key="${2:?key}"; prompt="${3:?\"prompt\"}"; seed="${4:-}"
    line="- [ ] [$type] $key — $prompt"; [ -n "$seed" ] && line="$line | seed:$seed"
    [ -f "$Q" ] || echo "# Art / animation queue — add with: art.sh add <type> <key> \"<prompt>\" [seed]" > "$Q"
    echo "$line" >> "$Q"; echo "queued: $line" ;;
  list)
    echo "=== queued (pending) ==="; grep -nE "^- \[ \]" "$Q" 2>/dev/null || echo "  (none)"
    echo "=== staged (generated, awaiting review) ==="; grep -nE "^- \[x\]" "$Q" 2>/dev/null | tail -20 || echo "  (none)" ;;
  run)
    n=$(grep -cE "^- \[ \]" "$Q" 2>/dev/null || echo 0)
    [ "${n:-0}" -eq 0 ] && { echo "art queue empty — nothing to run"; exit 0; }
    echo "generating $n task(s). Stopping 27B to free the GPU (auto-restores when done)..."
    docker stop "$LLAMA" >/dev/null 2>&1 || true
    mkdir -p "$STAGE"
    nohup bash -c "NTFY_TOPIC=${NTFY_TOPIC:-shrike_ovn_311380987a} '$PY' '$RUNNER' >> '$LOG' 2>&1" >/dev/null 2>&1 &
    echo "art runner started (pid $!). Tail: art.sh status  |  log: $LOG"
    echo "The gpu_autoswap watcher restarts the 27B automatically once the GPU frees." ;;
  status)
    echo "=== queue ==="; echo "  pending: $(grep -cE '^- \[ \]' "$Q" 2>/dev/null || echo 0)  staged: $(grep -cE '^- \[x\]' "$Q" 2>/dev/null || echo 0)"
    echo "=== runner ==="; pgrep -f art_runner.py >/dev/null && echo "  RUNNING" || echo "  idle"
    echo "=== GPU ==="; nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader 2>/dev/null | head -1
    echo "=== 27B ==="; [ "$(docker inspect -f '{{.State.Running}}' "$LLAMA" 2>/dev/null)" = true ] && echo "  up" || echo "  down (art running or auto-swap pending)"
    echo "=== last log ==="; tail -3 "$LOG" 2>/dev/null ;;
  review)
    echo "staged art in $STAGE:"; ls -1 "$STAGE" 2>/dev/null | sed 's/^/  /' || echo "  (none yet)"
    echo "Approve: move an approved unit's PNGs into assets/sprites/ and commit; then it is in-game." ;;
  remove)
    sub="${1:?substring}"; grep -vF "$sub" "$Q" > "$Q.tmp" && mv "$Q.tmp" "$Q"; echo "removed lines matching: $sub" ;;
  *) echo "usage: art.sh add|list|run|status|review|remove" ;;
esac
