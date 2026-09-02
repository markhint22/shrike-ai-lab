#!/usr/bin/env bash
# GPU window: run the CHARACTER sub-flow of the art pipeline for DEAD (side-lying
# canon, redo) + DOWNED (new state), each through gen -> pixelize -> QA auto-reject
# -> re-roll (art_pipeline_run.py). Restores llama + queue on exit (trap).
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/art-characters.out

exec 9>/tmp/art_char.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  # Remove the watcher hold + resume the queue; the auto-swap watcher (cron, 1 min)
  # restores the production 27B on its next tick now that the GPU is free again.
  log "removing art hold + resuming (watcher restores 27B)"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== ART CHARACTER WINDOW DONE ==="
}
trap restore EXIT

# Pin the auto-swap watcher OFF for the whole window (it otherwise restarts the 27B
# in the gap between gen subprocesses -> the next gen OOMs), pause the queue, and stop
# BOTH model containers (the watched 27B AND the coder-next A/B trial) to free VRAM.
mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "pausing queue + freeing GPU (both model containers)"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== DEAD (side-lying, QA-gated) ==="
timeout 2400 "$PY" /tmp/art_pipeline_run.py --role dead --passes 3 >>"$OUT" 2>&1 && log "dead ok" || log "dead FAILED"
log "=== DOWNED (new, QA-gated) ==="
timeout 2400 "$PY" /tmp/art_pipeline_run.py --role downed --passes 3 >>"$OUT" 2>&1 && log "downed ok" || log "downed FAILED"
log "dead frames: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/units_dead_sprites3/*__dead@64.png 2>/dev/null | wc -l)"
log "downed frames: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/units_downed_sprites3/*__downed@64.png 2>/dev/null | wc -l)"
log "=== RESULTS READY ==="
