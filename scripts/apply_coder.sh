#!/usr/bin/env bash
# Cut production over to Qwen3-Coder-30B-A3B. Rollback-safe: ANY unexpected exit
# or failure restores the current 27B (kept, renamed, as an instant rollback).
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
CODER=/models/deepflash/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
OLD=shrike-llama-dflash-35b
ROLLBACK=shrike-llama-27b-rollback
NEW=shrike-llama-coder
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/cutover.out
: > "$OUT"
DONE=0
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
gpu(){ nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1; }

rollback(){
  log "ROLLBACK: restoring 27B"
  docker rm -f "$NEW" >/dev/null 2>&1 || true
  docker inspect "$ROLLBACK" >/dev/null 2>&1 && docker rename "$ROLLBACK" "$OLD" >/dev/null 2>&1 || true
  docker start "$OLD" >/dev/null 2>&1 || true
  for i in $(seq 1 60); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "rollback: $(docker ps --filter name=$OLD --format '{{.Status}}')"
}
trap '[ "$DONE" = 1 ] || rollback' EXIT

"$Q/queue.sh" pause >/dev/null; log "queue paused"
for i in $(seq 1 12); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done

docker stop "$OLD" >/dev/null && log "stopped $OLD"
docker rename "$OLD" "$ROLLBACK" && log "renamed 27B -> $ROLLBACK (rollback preserved)"
for i in $(seq 1 30); do [ "$(gpu)" -lt 3000 ] && break; sleep 2; done

docker rm -f "$NEW" >/dev/null 2>&1 || true
docker run -d --gpus all --name "$NEW" --network "$NET" --network-alias llama-dflash-35b \
  --restart unless-stopped -p 8081:8080 -v "$MODELS:/models" --entrypoint /bin/sh "$IMG" \
  -c "exec /app/llama-server -m $CODER --ctx-size 65536 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --host 0.0.0.0 --port 8080 --alias qwen-dflash-27B" >/dev/null
log "started coder container ($NEW)"

ok=0
for i in $(seq 1 75); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }; [ "$(docker inspect -f '{{.State.Running}}' $NEW 2>/dev/null)" != "true" ] && break; sleep 2; done
[ "$ok" = 1 ] || { log "coder failed to start:"; docker logs "$NEW" 2>&1 | tail -12 >> "$OUT"; exit 1; }
log "coder healthy: VRAM $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)"

sleep 3
R=$(curl -s --max-time 60 -H "Authorization: Bearer sk-shrike-local" -H "Content-Type: application/json" \
  -d '{"model":"qwen-dflash-27B","prompt":"def add(a,b):\n    return","max_tokens":12,"temperature":0}' http://localhost:4000/v1/completions)
echo "$R" | grep -q completion_tokens || { log "litellm cannot reach coder: $(echo "$R"|head -c 200)"; exit 1; }
log "litellm -> coder OK"

# switch the queue's aider edit format to the coder's SEARCH/REPLACE (diff)
sed -i 's/--edit-format udiff/--edit-format diff/' "$Q/run_overnight.sh" && log "runner edit-format: udiff -> diff ($(grep -c 'edit-format diff' "$Q/run_overnight.sh") site)"

"$Q/queue.sh" resume >/dev/null; log "queue resumed on coder"
DONE=1
log "=== CUTOVER COMPLETE — Qwen3-Coder is now production ==="
