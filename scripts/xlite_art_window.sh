#!/usr/bin/env bash
# Maintenance-window generation of xlite pixel-art STYLE TESTS. Pauses the queue,
# frees the GPU (stops the llama container), installs diffusers deps, generates +
# pixelizes, then ALWAYS restores the llama container + queue on exit (trap).
# flock-guarded. Requires setup_comfyui.sh to have finished. Poll reports/xlite-art.out
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-art.out
exec 9>/tmp/xlite_art.lock
if ! flock -n 9; then echo "art window already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring GPU to the llama queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "llama restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== ART WINDOW DONE ==="
}
trap restore EXIT

# preconditions
[ -x "$PY" ] || { log "FATAL: comfy venv missing — run setup_comfyui.sh first"; exit 1; }
[ -s "$C/models/checkpoints/sd_xl_base_1.0.safetensors" ] || { log "FATAL: SDXL checkpoint missing"; exit 1; }
[ -s "$C/models/loras/pixel-art-xl.safetensors" ] || { log "FATAL: pixel-art LoRA missing"; exit 1; }

log "installing diffusers deps (gpu-free)"
"$PY" -m pip install -q diffusers transformers accelerate peft safetensors pillow >>"$OUT" 2>&1 \
  && log "diffusers deps ok" || { log "diffusers install FAILED"; exit 1; }

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1) MiB used"

log "=== generating style tests ==="
timeout 1200 "$PY" /tmp/xlite_style_tests.py >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED (see log)"

log "=== pixelizing ==="
timeout 300 "$PY" /tmp/pixelize.py >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"

SPR=/run/media/mhintermeister/secondary_drive1/comfy/out/style_tests_sprites
log "outputs: $(ls "$SPR"/*.png 2>/dev/null | wc -l) files in $SPR"
log "=== RESULTS READY (restoring GPU next) ==="
