#!/usr/bin/env bash
# Diagnose why the tuned container probed at 10 tok/s when the sweep measured 86.
# Starts the tuned config, fires a WARMUP call then 4 timed calls with the sweep's
# exact prompt, logging each — so we can tell cold-start warmup (call 1 slow, rest
# ~86) from a real regression (all ~10). Restores prod on exit. flock-guarded.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
P27=shrike-llama-dflash-35b
SW=shrike-llama-sweep
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/diag-tuned.out
exec 9>/tmp/diag_tuned.lock
if ! flock -n 9; then echo "diag already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
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
  docker rm -f "$SW" >/dev/null 2>&1 || true
  docker start "$P27" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$P27 --format '{{.Status}}')"
  log "=== DIAG DONE ==="
}
trap restore_prod EXIT
call(){ # label
  local R sp gn
  R=$(curl -s --max-time 120 -H 'Content-Type: application/json' \
    -d "{\"prompt\":$(printf '%s' "$PROMPT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"n_predict\":200,\"temperature\":0,\"cache_prompt\":false}" \
    http://localhost:8081/completion 2>/dev/null)
  sp=$(printf '%s' "$R" | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["timings"]["predicted_per_second"],1))' 2>/dev/null || echo "?")
  gn=$(printf '%s' "$R" | python3 -c 'import json,sys;print(json.load(sys.stdin)["timings"]["predicted_n"])' 2>/dev/null || echo "?")
  log "$1: GEN ${sp} tok/s (gen_n=${gn})"
}

log "pausing queue"; "$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$P27" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done

log "starting tuned config (identical to apply script)"
docker run -d --name "$SW" --gpus all --network "$NET" -p 8081:8080 -v "$MODELS:/models" \
  -e GGML_CUDA_GRAPH_OPT=1 --entrypoint /bin/sh "$IMG" -c "exec /app/llama-server \
    -m $MD/Qwen3.8-27B-Q4_K_M.gguf --ctx-size 65536 -ngl 99 \
    --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 --batch-size 512 --ubatch-size 256 \
    --spec-type draft-mtp --spec-draft-n-max 8 --host 0.0.0.0 --port 8080 --alias sweep \
    --chat-template-file $MD/fixed_template_qwen3.8.jinja" >/dev/null 2>&1
ok=0
for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }; [ "$(docker inspect -f '{{.State.Running}}' $SW 2>/dev/null)" != "true" ] && break; sleep 2; done
[ "$ok" = 1 ] || { log "FAILED to start: $(docker logs $SW 2>&1|tail -3|tr '\n' ' ')"; exit 1; }
log "healthy VRAM $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)/24576"

call "warmup"
call "measure-1"
call "measure-2"
call "measure-3"
# also test with n-max 4 hypothesis? no — this isolates cold vs regression first.
log "=== DIAG RESULTS ABOVE ==="
