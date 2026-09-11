#!/usr/bin/env bash
# GPU window: run the image-model A/B/C comparison (SDXL+LoRA baseline vs
# LLaDA-Image-Turbo vs Z-Image-Turbo) on the SAME prompt set. Same trap-safe
# pause/free-GPU/restore-on-EXIT pattern as the other art windows.
set -uo pipefail
EVAL=/run/media/mhintermeister/secondary_drive1/comfy/models_eval
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/model-eval.out

exec 9>/tmp/model_eval.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "removing hold + resuming"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  ok=0
  for i in $(seq 1 18); do
    if docker ps --format '{{.Names}} {{.Status}}' | grep -q 'shrike-llama-dflash-35b.*healthy'; then
      ok=1; break
    fi
    sleep 5
  done
  [ "$ok" = "1" ] && log "verified: shrike-llama-dflash-35b is healthy" || log "WARNING: model not healthy after 90s"
  log "=== MODEL EVAL WINDOW DONE ==="
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

log "=== [1/3] SDXL+LoRA baseline ==="
timeout 900 "$C/.venv/bin/python" /tmp/eval_sdxl_baseline.py >>"$OUT" 2>&1 && log "sdxl_baseline ok" || log "sdxl_baseline FAILED"

log "=== [2/3] LLaDA-Image-Turbo ==="
timeout 1200 "$EVAL/.venv-llada/bin/python" /tmp/eval_llada_image.py >>"$OUT" 2>&1 && log "llada ok" || log "llada FAILED"

log "=== [3/3] Z-Image-Turbo ==="
timeout 1200 "$EVAL/.venv/bin/python" /tmp/eval_zimage.py >>"$OUT" 2>&1 && log "zimage ok" || log "zimage FAILED"

log "=== [retry] LLaDA-Image-Turbo with CPU offload (first attempt OOM'd) ==="
timeout 1800 "$EVAL/.venv-llada/bin/python" /tmp/eval_llada_image.py >>"$OUT" 2>&1 && log "llada_retry ok" || log "llada_retry FAILED"

log "=== [followup] Z-Image terrain prompt retest ==="
timeout 600 "$EVAL/.venv/bin/python" /tmp/eval_zimage_terrain_retest.py >>"$OUT" 2>&1 && log "zimage_retest ok" || log "zimage_retest FAILED"

log "=== RESULTS READY ==="
