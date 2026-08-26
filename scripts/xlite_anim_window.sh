#!/usr/bin/env bash
# Maintenance window: generate ControlNet-OpenPose animation frames (distinct poses,
# consistent character) for the humanoid primaries, pixelize to 48px, restore prod.
# Trap-safe, flock-guarded. Requires the ControlNet model already downloaded.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-anim.out
exec 9>/tmp/xlite_anim.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring prod 27B + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== ANIM WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== generating ControlNet anim frames ==="
timeout 1200 "$PY" /tmp/generate_anims_controlnet.py >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED"
log "=== pixelizing (48px) ==="
timeout 300 "$PY" /tmp/pixelize3.py /run/media/mhintermeister/secondary_drive1/comfy/out/anims >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
SPR=/run/media/mhintermeister/secondary_drive1/comfy/out/anims_sprites3
log "anim sprites: $(ls "$SPR"/*@48.png 2>/dev/null | wc -l) at 48px"
log "=== RESULTS READY ==="
