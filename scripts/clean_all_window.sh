#!/usr/bin/env bash
# GPU window: ALL clean static artwork (units/cover/icons/tiles) -> isolate -> plus
# wasteland background options incl the rundown-arcade hub. Restores llama + queue.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/clean-all.out
ART=/run/media/mhintermeister/secondary_drive1/comfy/out/allart

exec 9>/tmp/clean_all.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== CLEAN ALL WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== 1/3 all static art (units/cover/icons/tiles) ==="
timeout 2400 "$PY" /tmp/clean_all.py >>"$OUT" 2>&1 && log "art ok" || log "art FAILED"
log "=== 2/3 isolate (floodkey sprites, keep tiles) ==="
timeout 600 "$PY" /tmp/pixelize3.py "$ART" >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "sprites: $(ls ${ART}_sprites3/*@64.png 2>/dev/null | wc -l)"
log "=== 3/3 wasteland backgrounds (+ arcade hub) ==="
timeout 1200 "$PY" /tmp/xlite_scenes_batch.py >>"$OUT" 2>&1 && log "scenes ok" || log "scenes FAILED"
log "=== RESULTS READY (${ART}_sprites3 + out/scenes) ==="
