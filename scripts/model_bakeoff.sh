#!/usr/bin/env bash
# Comprehensive model bake-off on the single 24GB GPU. Disconnect-safe: a trap
# ALWAYS restores production. Measures tok/s + a code sample for each candidate.
# One prod-down window: baseline (prod) -> stop prod -> test all candidates -> restore.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
DF=$MODELS/deepflash
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
KEY=sk-shrike-local
PROD=shrike-llama-dflash-35b
OUT=/home/mhintermeister/overnight-queue/reports/bakeoff.out
: > "$OUT"

restore() { docker rm -f cand >/dev/null 2>&1 || true
  docker start "$PROD" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  echo "[restore] production: $(docker ps --filter name=$PROD --format '{{.Status}}')" >> "$OUT"; }
trap restore EXIT

toks() { # $1=url -> best tok/s over 2 coding completions
  local base="$1" best=0 i r w c ts
  for i in 1 2; do
    r=$(curl -s -w '\nWALL:%{time_total}' --max-time 120 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
      -d '{"model":"probe","prompt":"Write a Python function merge_sort(arr) with a helper and comments.","max_tokens":180,"temperature":0}' "$base/v1/completions")
    w=$(echo "$r" | grep -oE 'WALL:[0-9.]+' | cut -d: -f2)
    c=$(echo "$r" | sed 's/WALL:.*//' | python3 -c 'import sys,json;print(json.load(sys.stdin)["usage"]["completion_tokens"])' 2>/dev/null || echo 0)
    [ "${c:-0}" -gt 0 ] && ts=$(python3 -c "print(round(${c}/${w},1))" 2>/dev/null) || ts=0
    [ "$(python3 -c "print(1 if ${ts:-0}>${best} else 0)")" = 1 ] && best=$ts
  done
  echo "$best"
}
sample() { # $1=url -> short code-quality sample (SEARCH/REPLACE diff capability)
  curl -s --max-time 150 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d '{"model":"probe","messages":[{"role":"user","content":"Given this code:\n\ndef add(a,b):\n    return a-b\n\nIt has a bug. Reply with ONLY a SEARCH/REPLACE diff block that fixes it (aider format: <<<<<<< SEARCH / ======= / >>>>>>> REPLACE)."}],"max_tokens":200,"temperature":0}' \
    "$1/v1/chat/completions" | jq -r '.choices[0].message.content // "NO RESPONSE"' 2>/dev/null | head -18
}
gpu() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1; }
launch() { # $1=label $2=extra llama-server args (model + ctx etc). auto-fit (no -ngl).
  echo "======== CANDIDATE: $1 ========" >> "$OUT"
  docker rm -f cand >/dev/null 2>&1 || true
  docker run -d --gpus all --name cand -p 8081:8080 -v "$MODELS:/models" --entrypoint /bin/sh "$IMG" \
    -c "exec /app/llama-server $2 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --host 0.0.0.0 --port 8080 --alias probe" >/dev/null
  local ok=0
  for i in $(seq 1 75); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }
    [ "$(docker inspect -f '{{.State.Running}}' cand 2>/dev/null)" != "true" ] && break
    sleep 2
  done
  if [ "$ok" = 1 ]; then
    sleep 3
    echo "  tok/s: $(toks http://localhost:8081) | VRAM: $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)" >> "$OUT"
    echo "  --- code sample (SEARCH/REPLACE fix) ---" >> "$OUT"; sample http://localhost:8081 >> "$OUT"
  else
    echo "  FAILED to start — logs:" >> "$OUT"; docker logs cand 2>&1 | tail -12 >> "$OUT"
  fi
  docker rm -f cand >/dev/null 2>&1 || true
  for i in $(seq 1 20); do [ "$(gpu)" -lt 3000 ] && break; sleep 2; done
}

for i in $(seq 1 8); do fuser /home/mhintermeister/overnight-queue/state/run.lock >/dev/null 2>&1 || break; sleep 8; done
echo "======== BASELINE: current 27B hybrid (262k, MTP, auto-fit) via litellm ========" >> "$OUT"
echo "  tok/s: $(toks http://localhost:4000)" >> "$OUT"

echo "======== stopping prod, freeing GPU ========" >> "$OUT"
docker stop "$PROD" >/dev/null
for i in $(seq 1 30); do [ "$(gpu)" -lt 3000 ] && break; sleep 2; done

CTX='--ctx-size 65536'
[ -f "$DF/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf" ] && launch "Qwen3-Coder-30B-A3B (MoE ~3B active)" "-m /models/deepflash/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf $CTX"
[ -f "$DF/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf" ] && launch "Devstral-Small-2-24B (dense, agentic)" "-m /models/deepflash/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf $CTX"
[ -f "$DF/GLM-4.7-Flash-UD-Q4_K_XL.gguf" ] && launch "GLM-4.7-Flash (MoE, MLA, thinking)" "-m /models/deepflash/GLM-4.7-Flash-UD-Q4_K_XL.gguf $CTX"

echo "======== DONE ========" >> "$OUT"
