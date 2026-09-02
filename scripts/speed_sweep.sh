#!/usr/bin/env bash
# Speed sweep: measure prefill + generation tok/s across model/ctx/spec configs to
# find the fastest config that preserves quality. The 27B-at-smaller-ctx configs are
# LOSSLESS on quality (identical model, just a smaller KV reservation) so speed alone
# decides them; the alternative models still need a follow-up quality bench.
#
# ALWAYS restores production (Qwen3.8-27B @ its original 256K/MTP config) on exit.
# flock-guarded (no double-launch). Fully server-side; poll reports/speed-sweep.out.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
P27=shrike-llama-dflash-35b            # production container (Exited/Started around the sweep)
SW=shrike-llama-sweep                  # ephemeral sweep container
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/speed-sweep.out
exec 9>/tmp/speed_sweep.lock
if ! flock -n 9; then echo "sweep already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

# realistic coding prompt (~350 tokens) so prefill numbers mean something
read -r -d '' PROMPT <<'EOF'
You are a senior Python engineer. Given this FastAPI module, add a new async
endpoint GET /api/v2/users/{user_id}/summary that returns the user's display name,
their total order count, and their lifetime spend, using the existing async session
dependency. Keep the existing error handling style. Here is the current file:

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.db import get_session
from app.models import User, Order

router = APIRouter()

@router.get("/api/v2/users/{user_id}")
async def get_user(user_id: int, session: AsyncSession = Depends(get_session)):
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    return {"id": user.id, "name": user.display_name, "email": user.email}

Now write the complete new endpoint below:
EOF

restore_prod(){
  log "restoring production 27B"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  docker start "$P27" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$P27 --format '{{.Status}}')"
  log "=== SWEEP DONE ==="
}
trap restore_prod EXIT

# measure(): args = a llama-server arg string (after -m ... already fixed per call).
# Starts $SW, waits health (or bails), fires ONE native /completion, logs prefill+gen tok/s + VRAM.
measure(){
  local name="$1" model="$2" extra="$3"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  # wait for VRAM to drain from the previous container
  for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
  docker run -d --gpus all --name "$SW" --network "$NET" -p 8081:8080 -v "$MODELS:/models" \
    --entrypoint /bin/sh "$IMG" \
    -c "exec /app/llama-server -m $model $extra --host 0.0.0.0 --port 8080 --alias sweep" >/dev/null 2>&1
  local ok=0
  for i in $(seq 1 90); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
    [ "$(docker inspect -f '{{.State.Running}}' $SW 2>/dev/null)" != "true" ] && break
    sleep 2
  done
  if [ "$ok" != 1 ]; then
    log "$name: FAILED to start — $(docker logs $SW 2>&1 | grep -iE 'error|oom|failed|cannot|out of memory' | tail -2 | tr '\n' ' ')"
    return
  fi
  local vram; vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)
  # warm + measure via native endpoint (returns detailed timings)
  curl -s --max-time 120 -H 'Content-Type: application/json' \
    -d "{\"prompt\":$(printf '%s' "$PROMPT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"n_predict\":200,\"temperature\":0,\"cache_prompt\":false}" \
    http://localhost:8081/completion >/tmp/sw_resp.json 2>/dev/null
  local pps preds ptok gtok
  pps=$(python3 -c 'import json;d=json.load(open("/tmp/sw_resp.json"));print(round(d["timings"]["prompt_per_second"],1))' 2>/dev/null || echo "?")
  preds=$(python3 -c 'import json;d=json.load(open("/tmp/sw_resp.json"));print(round(d["timings"]["predicted_per_second"],1))' 2>/dev/null || echo "?")
  ptok=$(python3 -c 'import json;d=json.load(open("/tmp/sw_resp.json"));print(d["timings"]["prompt_n"])' 2>/dev/null || echo "?")
  gtok=$(python3 -c 'import json;d=json.load(open("/tmp/sw_resp.json"));print(d["timings"]["predicted_n"])' 2>/dev/null || echo "?")
  log "$name: GEN ${preds} tok/s | PREFILL ${pps} tok/s (${ptok} prompt tok) | VRAM ${vram}/24576 MiB | gen_n=${gtok}"
}

log "pausing queue"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
log "stopping production 27B"
docker stop "$P27" >/dev/null 2>&1 || true

log "=== SPEED SWEEP START (RTX 3090 24GB) ==="

# --- the quality-preserving 27B configs (same model, smaller/no wasted context) ---
COMMON_K="--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0"
measure "27B_baseline_256k_mtp"   "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 262144 --spec-type draft-mtp --spec-draft-n-max 4 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"
measure "27B_65k_mtp"             "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 65536 --spec-type draft-mtp --spec-draft-n-max 4 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"
measure "27B_32k_mtp"             "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 --spec-type draft-mtp --spec-draft-n-max 4 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"
measure "27B_32k_mtp_n6"          "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 --spec-type draft-mtp --spec-draft-n-max 6 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"
measure "27B_32k_nospec"          "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"
measure "27B_32k_mtp_ngl99"       "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 --spec-type draft-mtp --spec-draft-n-max 4 $COMMON_K --chat-template-file $MD/fixed_template_qwen3.8.jinja"

# --- alternative fitting models at full GPU offload (need a follow-up quality bench) ---
measure "Devstral24B_32k_ngl99"   "$MD/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 $COMMON_K"
measure "GLM47Flash_32k_ngl99"    "$MD/GLM-4.7-Flash-UD-Q4_K_XL.gguf" "--ctx-size 32768 -ngl 99 $COMMON_K"
measure "Coder30BA3B_32k_ngl99"   "$MD/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 $COMMON_K"
measure "Qwen36_27B_32k_ngl99"    "$MD/Qwen3.6-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 $COMMON_K"

log "=== SWEEP RESULTS ABOVE ==="
