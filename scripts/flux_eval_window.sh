#!/usr/bin/env bash
# GPU window: run FLUX.1-schnell through the shared A/B/C/D comparison
# prompts. Same trap-safe pause/free-GPU/restore-on-EXIT pattern.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/flux-eval.out

exec 9>/tmp/flux_eval.lock
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
  log "=== FLUX EVAL WINDOW DONE ==="
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
log "=== FLUX.1-schnell ==="
timeout 1800 "$C/.venv/bin/python" /tmp/eval_flux_schnell.py >>"$OUT" 2>&1 && log "flux ok" || log "flux FAILED"
log "=== RESULTS READY ==="
