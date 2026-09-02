#!/usr/bin/env bash
# Speed sweep #2 — research-optimized configs. Applies the documented Gated-DeltaNet
# ~50 tok/s recipe to the 27B (q4_0 KV instead of q8_0, --spec-draft-n-max 8, batch
# 512/ubatch 256, GGML_CUDA_GRAPH_OPT=1, -ngl 99) and benches the two upgrade
# candidates that fit cleanly: Qwen3.6-27B dense + MTP (quality pick, SWE-V 77.2) and
# GLM-4.7-Flash MoE (throughput pick). q4_0 KV is a mild quality tradeoff on the 16
# attention layers — flagged, to be confirmed in the follow-up quality bench.
#
# Restores production on exit (trap). flock-guarded. Poll reports/speed-sweep2.out.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
MD=/models/deepflash
IMG="${SWEEP_IMG:-ghcr.io/ggml-org/llama.cpp:server-cuda}"   # override w/ a fresher tag if needed
NET=shrike-ai-network
P27=shrike-llama-dflash-35b
SW=shrike-llama-sweep
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/speed-sweep2.out
exec 9>/tmp/speed_sweep2.lock
if ! flock -n 9; then echo "sweep2 already running" >&2; exit 0; fi
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
  log "restoring production 27B"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  docker start "$P27" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$P27 --format '{{.Status}}')"
  log "=== SWEEP2 DONE ==="
}
trap restore_prod EXIT

measure(){
  local name="$1" model="$2" extra="$3" env="${4:-}"
  docker rm -f "$SW" >/dev/null 2>&1 || true
  for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
  docker run -d --gpus all --name "$SW" --network "$NET" -p 8081:8080 -v "$MODELS:/models" \
    $env --entrypoint /bin/sh "$IMG" \
    -c "exec /app/llama-server -m $model $extra --host 0.0.0.0 --port 8080 --alias sweep" >/dev/null 2>&1
  local ok=0
  for i in $(seq 1 90); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
    [ "$(docker inspect -f '{{.State.Running}}' $SW 2>/dev/null)" != "true" ] && break
    sleep 2
  done
  if [ "$ok" != 1 ]; then
    log "$name: FAILED — $(docker logs $SW 2>&1 | grep -iE 'error|oom|out of memory|cannot|unknown|invalid' | tail -2 | tr '\n' ' ')"
    return
  fi
  local vram; vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)
  curl -s --max-time 120 -H 'Content-Type: application/json' \
    -d "{\"prompt\":$(printf '%s' "$PROMPT" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"n_predict\":200,\"temperature\":0,\"cache_prompt\":false}" \
    http://localhost:8081/completion >/tmp/sw2_resp.json 2>/dev/null
  local pps preds ptok gtok
  pps=$(python3 -c 'import json;d=json.load(open("/tmp/sw2_resp.json"));print(round(d["timings"]["prompt_per_second"],1))' 2>/dev/null || echo "?")
  preds=$(python3 -c 'import json;d=json.load(open("/tmp/sw2_resp.json"));print(round(d["timings"]["predicted_per_second"],1))' 2>/dev/null || echo "?")
  ptok=$(python3 -c 'import json;d=json.load(open("/tmp/sw2_resp.json"));print(d["timings"]["prompt_n"])' 2>/dev/null || echo "?")
  gtok=$(python3 -c 'import json;d=json.load(open("/tmp/sw2_resp.json"));print(d["timings"]["predicted_n"])' 2>/dev/null || echo "?")
  log "$name: GEN ${preds} tok/s | PREFILL ${pps} tok/s (${ptok} tok) | VRAM ${vram} MiB | gen_n=${gtok}"
}

log "pausing queue"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$P27" >/dev/null 2>&1 || true
log "=== SPEED SWEEP #2 (research-optimized) — image: $IMG ==="

GRAPH="-e GGML_CUDA_GRAPH_OPT=1"
RECIPE="--flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 --batch-size 512 --ubatch-size 256 --spec-type draft-mtp --spec-draft-n-max 8"
TPL="--chat-template-file $MD/fixed_template_qwen3.8.jinja"

# --- the 27B GDN recipe, honest context, at increasing offload ---
measure "27B_recipe_32k_autofit"  "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 $RECIPE $TPL" "$GRAPH"
measure "27B_recipe_32k_ngl99"    "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 $RECIPE $TPL" "$GRAPH"
measure "27B_recipe_65k_ngl99"    "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 65536 -ngl 99 $RECIPE $TPL" "$GRAPH"
measure "27B_recipe_32k_q8kv_ngl99" "$MD/Qwen3.8-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --batch-size 512 --ubatch-size 256 --spec-type draft-mtp --spec-draft-n-max 8 $TPL" "$GRAPH"

# --- Qwen3.6-27B dense + MTP: the quality-that-fits-cleanly pick (SWE-V 77.2) ---
measure "Qwen36_27B_mtp8_32k_ngl99" "$MD/Qwen3.6-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 8 --batch-size 512 --ubatch-size 256" "$GRAPH"
# with a separate matched drafter instead of MTP head
measure "Qwen36_27B_draft_32k_ngl99" "$MD/Qwen3.6-27B-Q4_K_M.gguf" "--ctx-size 32768 -ngl 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --model-draft $MD/dflash-Qwen3.6-27B-Q8_0.gguf --spec-draft-n-max 8 --batch-size 512 --ubatch-size 256" "$GRAPH"

# --- GLM-4.7-Flash MoE: throughput champ (no spec — MoE gets nothing from it) ---
measure "GLM47Flash_32k_ngl99"     "$MD/GLM-4.7-Flash-UD-Q4_K_XL.gguf" "--ctx-size 32768 -ngl 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --batch-size 512 --ubatch-size 256" "$GRAPH"

log "=== SWEEP2 RESULTS ABOVE ==="
