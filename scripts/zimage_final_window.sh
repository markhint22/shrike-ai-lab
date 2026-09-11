#!/usr/bin/env bash
# GPU window: generate the actual deliverable (full sprite roster + terrain/
# prop set) via Z-Image-Turbo (gen_zimage_final.py), then isolate with
# pixelize3.py. Same trap-safe pause/free-GPU/restore-on-EXIT pattern.
set -uo pipefail
EVAL=/run/media/mhintermeister/secondary_drive1/comfy/models_eval
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/zimage-final.out
GEN_OUT=/run/media/mhintermeister/secondary_drive1/comfy/out/zimage_final

exec 9>/tmp/zimage_final.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "removing hold + resuming"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  ok=0
  for i in $(seq 1 18); do
    docker ps --format '{{.Names}} {{.Status}}' | grep -q 'shrike-llama-dflash-35b.*healthy' && { ok=1; break; }
    sleep 5
  done
  [ "$ok" = "1" ] && log "verified: shrike-llama-dflash-35b is healthy" || log "WARNING: model not healthy after 90s"
  log "=== ZIMAGE FINAL WINDOW DONE ==="
}
trap restore EXIT

mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
log "=== GENERATING (targets: ${*:-ALL}) ==="
timeout 3600 "$EVAL/.venv/bin/python" /tmp/gen_zimage_final.py "$@" >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED"

if [ -d "$GEN_OUT" ] && [ "$(ls -A "$GEN_OUT" 2>/dev/null)" ]; then
  log "=== ISOLATING (pixelize3.py) ==="
  "$EVAL/.venv/bin/python" /tmp/pixelize3.py "$GEN_OUT" >>"$OUT" 2>&1 && log "isolation ok" || log "isolation FAILED"
  log "isolated: $(ls "${GEN_OUT}_sprites3"/*@64.png 2>/dev/null | wc -l)"
fi
log "=== RESULTS READY ==="
