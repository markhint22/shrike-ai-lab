#!/usr/bin/env bash
# Micro-sweep to pick the FINAL prod context/KV config: largest safe context (real
# aider tasks tail to ~50K tokens) at the best KV precision that still fits ngl99.
# Prefer q8_0 KV (near-lossless, = current prod precision); fall back to hybrid or
# q4_0 only if q8_0 OOMs. All configs are the tuned 27B (ngl99, MTP n8, batch, graph).
# Restores prod on exit. flock-guarded. Poll reports/speed-sweep3.out.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
P27=shrike-llama-dflash-35b
SW=shrike-llama-sweep
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/speed-sweep3.out
exec 9>/tmp/speed_sweep3.lock
if ! flock -n 9; then echo "sweep3 already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
read -r -d '' PROMPT <<'EOF'
You are a senior Python engineer. Add an async endpoint GET /api/v2/users/{user_id}/summary
returning display name, total order count, and lifetime spend using the existing async
session dependency, keeping the existing error-handling style. Write the complete endpoint:
EOF
restore_prod(){
  log "restoring production 27B"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  docker start "$P27" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$P27 --format '{{.Status}}')"
  log "=== SWEEP3 DONE ==="
}
trap restore_prod EXIT
measure(){
  local name="$1" extra="$2"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
  docker run -d --gpus all --name "$SW" --network "$NET" -p 8081:8080 -v "$MODELS:/models" \
    -e GGML_CUDA_GRAPH_OPT=1 --entrypoint /bin/sh "$IMG" \
    -c "exec /app/llama-server -m $MD/Qwen3.8-27B-Q4_K_M.gguf $extra --host 0.0.0.0 --port 8080 --alias sweep --chat-template-file $MD/fixed_template_qwen3.8.jinja" >/dev/null 2>&1
  local ok=0
  for i in $(seq 1 90); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
    [ "$(docker inspect -f '{{.State.Running}}' $SW 2>/dev/null)" != "true" ] && break; sleep 2
  done
  if [ "$ok" != 1 ]; then
    log "$name: FAILED — $(docker logs $SW 2>&1 | grep -iE 'out of memory|cudaMalloc|error' | tail -1 | tr '\n' ' ')"; return
  fi
  local vram; vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)
  curl -s --max-time 120 -H 'Content-Type: application/json' \
    -d "{\"prompt\":$(printf '%s' "$PROMPT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"n_predict\":200,\"temperature\":0,\"cache_prompt\":false}" \
    http://localhost:8081/completion >/tmp/sw3.json 2>/dev/null
  local preds; preds=$(python3 -c 'import json;print(round(json.load(open("/tmp/sw3.json"))["timings"]["predicted_per_second"],1))' 2>/dev/null || echo "?")
  log "$name: GEN ${preds} tok/s | VRAM ${vram}/24576 MiB"
}
log "pausing queue"; "$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$P27" >/dev/null 2>&1 || true
log "=== MICRO-SWEEP: largest safe ctx @ best KV precision ==="
SPEC="--spec-type draft-mtp --spec-draft-n-max 8 --batch-size 512 --ubatch-size 256 --flash-attn on"
measure "64k_q8kv"       "--ctx-size 65536 -ngl 99 --cache-type-k q8_0 --cache-type-v q8_0 $SPEC"
measure "48k_q8kv"       "--ctx-size 49152 -ngl 99 --cache-type-k q8_0 --cache-type-v q8_0 $SPEC"
measure "64k_hybrid_k8v4" "--ctx-size 65536 -ngl 99 --cache-type-k q8_0 --cache-type-v q4_0 $SPEC"
measure "96k_q4kv"       "--ctx-size 98304 -ngl 99 --cache-type-k q4_0 --cache-type-v q4_0 $SPEC"
log "=== SWEEP3 RESULTS ABOVE ==="
