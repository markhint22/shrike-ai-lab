#!/usr/bin/env bash
# One GPU maintenance window for a full xlite art pass:
#   1. refreshed 48px unit/tile/icon sprites  (xlite_vibrant_batch.py + pixelize3.py)
#   2. NEW scene backgrounds: title/battle/hub/menu  (xlite_scenes_batch.py)
# ALWAYS restores the prod llama server + overnight queue on exit (trap), even on
# failure. Everything timeout-bounded. flock-guarded (never a pgrep launch guard).
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-art-batch.out
VIB=/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant
SCN=/run/media/mhintermeister/secondary_drive1/comfy/out/scenes

exec 9>/tmp/xlite_art_batch.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring prod llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== ART BATCH WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1) MiB used"

log "=== 1/3 refreshed sprite roster ==="
timeout 1800 "$PY" /tmp/xlite_vibrant_batch.py >>"$OUT" 2>&1 && log "sprites ok" || log "sprites FAILED"
log "=== 2/3 pixelize sprites (48px) ==="
timeout 300 "$PY" /tmp/pixelize3.py "$VIB" >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "sprites: $(ls ${VIB}_sprites3/*@48.png 2>/dev/null | wc -l) at 48px"

log "=== 3/3 scene backgrounds ==="
timeout 900 "$PY" /tmp/xlite_scenes_batch.py >>"$OUT" 2>&1 && log "scenes ok" || log "scenes FAILED"
log "scenes: $(ls "$SCN"/bg_*.png 2>/dev/null | grep -v __raw | wc -l) backgrounds"
log "=== RESULTS READY (out/vibrant_sprites3 + out/scenes) ==="
