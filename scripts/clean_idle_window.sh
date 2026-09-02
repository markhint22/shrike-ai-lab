#!/usr/bin/env bash
# Small GPU window: clean bg-removable idles -> pixelize (alpha key) -> procedural
# animation frames. Restores llama + queue on exit (trap). flock-guarded.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/clean-idles.out
IDLES=/run/media/mhintermeister/secondary_drive1/comfy/out/idles

exec 9>/tmp/clean_idles.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== CLEAN IDLE WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== 1/3 clean idles ==="
timeout 900 "$PY" /tmp/clean_idles.py >>"$OUT" 2>&1 && log "idles ok" || log "idles FAILED"
log "=== 2/3 pixelize (alpha key) ==="
timeout 300 "$PY" /tmp/pixelize3.py "$IDLES" >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "=== 3/3 procedural animation ==="
timeout 300 "$PY" /tmp/procedural_anim.py "${IDLES}_sprites3" "${IDLES}_sprites3_anim" >>"$OUT" 2>&1 && log "anim ok" || log "anim FAILED"
log "frames: $(ls ${IDLES}_sprites3_anim/*.png 2>/dev/null | wc -l)"
log "=== RESULTS READY (${IDLES}_sprites3_anim) ==="
