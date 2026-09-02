#!/usr/bin/env bash
# One maintenance window: (1) generate the VIBRANT 48px asset batch, (2) pixelize,
# (3) bench the UD-IQ4_XS quant for tok/s. ALWAYS restores the prod 27B + queue on
# exit (trap). Everything timeout-bounded so nothing hangs the queue. flock-guarded.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
BENCH=shrike-llama-iq4bench
OUT=$Q/reports/xlite-vibrant.out
exec 9>/tmp/xlite_vibrant.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring prod 27B + queue"
  docker rm -f "$BENCH" >/dev/null 2>&1 || true
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== VIBRANT WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== generating VIBRANT batch ==="
timeout 1500 "$PY" /tmp/xlite_vibrant_batch.py >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED"

log "=== pixelizing (48px) ==="
timeout 300 "$PY" /tmp/pixelize3.py /run/media/mhintermeister/secondary_drive1/comfy/out/vibrant >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
SPR=/run/media/mhintermeister/secondary_drive1/comfy/out/vibrant_sprites3
log "sprites: $(ls "$SPR"/*@48.png 2>/dev/null | wc -l) at 48px"

# ---- IQ4_XS speed bench (inline, bounded loops; failure never blocks restore) ----
log "=== IQ4_XS bench ==="
PROBE='You are a senior Python engineer. Add an async FastAPI endpoint GET /api/v2/users/{user_id}/summary returning display name, total order count, and lifetime spend via the existing async session dependency, keeping existing error handling. Write the complete endpoint with imports:'
run_iq4(){ # $1 = spec args, $2 = label
  docker rm -f "$BENCH" >/dev/null 2>&1 || true
  docker run -d --gpus all --name "$BENCH" --network "$NET" -p 8081:8080 -v "$MODELS:/models" \
    -e GGML_CUDA_GRAPH_OPT=1 --entrypoint /bin/sh "$IMG" -c "exec /app/llama-server \
      -m $MD/Qwen3.8-27B-UD-IQ4_XS.gguf --ctx-size 65536 -ngl 99 --flash-attn on \
      --cache-type-k q4_0 --cache-type-v q4_0 --batch-size 512 --ubatch-size 256 \
      $1 --host 0.0.0.0 --port 8080 --alias iq4" >/dev/null 2>&1
  local ok=0 i
  for i in $(seq 1 60); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
    [ "$(docker inspect -f '{{.State.Running}}' $BENCH 2>/dev/null)" != "true" ] && break; sleep 2; done
  if [ "$ok" != 1 ]; then
    log "  [$2] failed to start: $(docker logs $BENCH 2>&1|grep -iE 'error|not found|cannot|mtp|draft|unknown'|tail -2|tr '\n' ' ')"
    docker rm -f "$BENCH" >/dev/null 2>&1 || true; return 1; fi
  local vram sp payload
  vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)
  payload="{\"prompt\":$(printf '%s' "$PROBE"|python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"n_predict\":200,\"temperature\":0,\"cache_prompt\":false}"
  curl -s --max-time 90 -H 'Content-Type: application/json' -d "$payload" http://localhost:8081/completion >/dev/null 2>&1  # warmup
  sp=$(curl -s --max-time 90 -H 'Content-Type: application/json' -d "$payload" http://localhost:8081/completion 2>/dev/null \
       | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["timings"]["predicted_per_second"],1))' 2>/dev/null||echo "?")
  log "  [$2] GEN ${sp} tok/s | VRAM ${vram} MiB (vs prod Q4_K_M 87 tok/s / ~23900 MiB)"
  docker rm -f "$BENCH" >/dev/null 2>&1 || true; return 0
}
run_iq4 "--spec-type draft-mtp --spec-draft-n-max 8" "IQ4_XS+bundledMTP" \
  || run_iq4 "-md $MD/mtp-Qwen3.8-27B-Q4_0.gguf --spec-type draft-mtp --spec-draft-n-max 8" "IQ4_XS+separateMTP" \
  || run_iq4 "" "IQ4_XS+noMTP"
log "=== RESULTS READY ==="
