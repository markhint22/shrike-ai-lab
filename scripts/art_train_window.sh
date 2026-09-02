#!/usr/bin/env bash
# GPU window: train the style LoRA on the normalized idles. Same hold-flag + both-
# containers-stopped pattern as the other art windows; trap-restores on exit.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/art-train.out

exec 9>/tmp/art_train.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){ rm -f "$STATE/art_window.hold"; "$Q/queue.sh" resume >/dev/null 2>&1 || true; log "=== TRAIN WINDOW DONE ==="; }
trap restore EXIT

mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "freeing GPU (both model containers)"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
log "=== training style LoRA on normalized idles ==="
timeout 2700 "$PY" /tmp/train_style_lora.py >>"$OUT" 2>&1 && log "train ok" || log "train FAILED"
log "lora files: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/lora/ 2>/dev/null | tr '\n' ' ')"
log "=== RESULTS READY ==="
