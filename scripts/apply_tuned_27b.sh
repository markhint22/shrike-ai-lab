#!/usr/bin/env bash
# Apply the tuned 27B config to production: SAME model (Qwen3.8-27B-Q4_K_M, identical
# quality tier) but ctx 262144->65536, -ngl 99 (full GPU offload), q4_0 KV, MTP n-max 8,
# batch 512/256, GGML_CUDA_GRAPH_OPT=1  => ~86 tok/s vs the old 8.7 (measured, 9.9x).
# Keeps the old container as shrike-llama-27b-256k-rollback for instant revert.
# flock-guarded; rolls back automatically if the new container isn't healthy+fast.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
NAME=shrike-llama-dflash-35b
OLD=shrike-llama-27b-256k-rollback
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/apply-tuned.out
exec 9>/tmp/apply_tuned.lock
if ! flock -n 9; then echo "apply already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

start_new(){
  docker run -d --name "$NAME" --gpus all --restart unless-stopped \
    --network "$NET" --network-alias llama-dflash-35b \
    -p 8081:8080 -v "$MODELS:/models" -e GGML_CUDA_GRAPH_OPT=1 \
    --entrypoint /bin/sh "$IMG" -c "exec /app/llama-server \
      -m $MD/Qwen3.8-27B-Q4_K_M.gguf \
      --ctx-size 65536 -ngl 99 \
      --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 \
      --batch-size 512 --ubatch-size 256 \
      --spec-type draft-mtp --spec-draft-n-max 8 \
      --host 0.0.0.0 --port 8080 --alias qwen-dflash-27B \
      --chat-template-file $MD/fixed_template_qwen3.8.jinja" >/dev/null 2>&1
}

rollback(){
  log "ROLLBACK: reverting to the 256K container"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker rename "$OLD" "$NAME" >/dev/null 2>&1 || true
  docker start "$NAME" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "rolled back: $(docker ps --filter name=$NAME --format '{{.Status}}')"
}

log "pausing queue"; "$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done

# preserve the current prod container for rollback
docker rm -f "$OLD" >/dev/null 2>&1 || true
log "stopping + preserving current 256K container as $OLD"
docker stop "$NAME" >/dev/null 2>&1 || true
docker rename "$NAME" "$OLD" >/dev/null 2>&1 || { log "FATAL: rename failed"; "$Q/queue.sh" resume; exit 1; }
for i in $(seq 1 30); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done

log "starting tuned container (65K, ngl99, q4_0 KV, MTP n8)"
start_new
ok=0
for i in $(seq 1 90); do
  curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
  [ "$(docker inspect -f '{{.State.Running}}' $NAME 2>/dev/null)" != "true" ] && break
  sleep 2
done
if [ "$ok" != 1 ]; then
  log "tuned container UNHEALTHY: $(docker logs $NAME 2>&1 | grep -iE 'error|out of memory|cudaMalloc' | tail -3 | tr '\n' ' ')"
  rollback; log "=== APPLY FAILED (rolled back) ==="; exit 1
fi

vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)
# speed probe via litellm-facing endpoint
R=$(curl -s --max-time 60 -H 'Content-Type: application/json' \
  -d '{"prompt":"Write a Python function to merge two sorted lists:","n_predict":150,"temperature":0}' \
  http://localhost:8081/completion 2>/dev/null)
sp=$(printf '%s' "$R" | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["timings"]["predicted_per_second"],1))' 2>/dev/null || echo "?")
log "tuned container healthy: GEN ${sp} tok/s | VRAM ${vram}/24576 MiB"

# sanity: require a real speedup, else roll back (guards a silent CPU-offload regression)
if python3 -c "import sys; sys.exit(0 if float('${sp}')>=45 else 1)" 2>/dev/null; then
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "queue resumed on TUNED 27B. rollback container kept as $OLD."
  log "=== APPLY OK (${sp} tok/s) ==="
else
  log "speed ${sp} below threshold — treating as regression"
  rollback; log "=== APPLY FAILED (slow; rolled back) ==="; exit 1
fi
