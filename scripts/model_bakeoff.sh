#!/usr/bin/env bash
# ===========================================
# Model bake-off: current 27B+MTP vs Qwen3-Coder-30B-A3B vs Qwen3.8-27B+DFlash2
# ===========================================
# Measures real tokens/sec + a coding-quality sample for each candidate, on the
# SAME GPU, one at a time (they can't co-reside in 24GB). Safe with production:
# it STOPS (never removes) the prod container, runs each candidate as a separate
# throwaway container on the prod port, then `docker start`s prod back exactly as
# it was. Pause the overnight queue before running (the model is briefly down).
#
# Usage:  ./model_bakeoff.sh            # runs baseline + both candidates
# ===========================================
set -uo pipefail

MODELS_HOST="/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models"
IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda"
PROD_CONTAINER="shrike-llama-dflash-35b"
PORT=8081
KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
CAND="bakeoff-cand"
TEST_CTX=32768   # smaller than prod's 262144 — safe for a speed/quality probe, avoids OOM
CODE_PROMPT='Write a Python function is_palindrome(s) that ignores case and non-alphanumeric characters, with a docstring. Then show a unified diff that adds a type hint to it.'

measure() {  # $1 = base url ; prints "tok/s | sample"
  local base="$1" total_t=0 total_ct=0 i resp ct
  for i in 1 2 3; do
    resp="$(curl -s -w '\nWALL:%{time_total}' --max-time 120 -H "Authorization: Bearer $KEY" \
      -H 'Content-Type: application/json' \
      -d '{"model":"probe","prompt":"Count slowly from 1 to 50, one number per line.","max_tokens":120,"temperature":0}' \
      "$base/v1/completions")"
    local wall ctok
    wall="$(echo "$resp" | grep -oE 'WALL:[0-9.]+' | cut -d: -f2)"
    ctok="$(echo "$resp" | sed 's/WALL:.*//' | python3 -c 'import sys,json;print(json.load(sys.stdin)["usage"]["completion_tokens"])' 2>/dev/null || echo 0)"
    total_t="$(python3 -c "print($total_t + ${wall:-0})")"
    total_ct=$((total_ct + ${ctok:-0}))
  done
  python3 -c "print(f'{$total_ct/$total_t:.1f} tok/s (idle)')" 2>/dev/null || echo "?"
  # coding-quality sample (udiff format — the aider-critical bit)
  echo "--- coding sample ---"
  curl -s --max-time 180 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg p "$CODE_PROMPT" '{model:"probe",messages:[{role:"user",content:$p}],max_tokens:400,temperature:0}')" \
    "$base/v1/chat/completions" | jq -r '.choices[0].message.content // "NO RESPONSE"' 2>/dev/null | head -40
}

wait_health() { for _ in $(seq 1 90); do curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }

run_candidate() {  # $1 = label ; $2... = llama-server args after the model
  local label="$1"; shift
  echo "======================================================"
  echo "=== CANDIDATE: $label"
  echo "======================================================"
  docker rm -f "$CAND" >/dev/null 2>&1 || true
  docker run -d --rm --gpus all --name "$CAND" -p "$PORT:8080" \
    -v "$MODELS_HOST:/models" --entrypoint /bin/sh "$IMAGE" \
    -c "exec /app/llama-server $* --host 0.0.0.0 --port 8080 --alias probe --ctx-size $TEST_CTX --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0" >/dev/null
  if wait_health; then
    sleep 3
    measure "http://localhost:$PORT"
  else
    echo "  DID NOT BECOME HEALTHY — logs:"; docker logs "$CAND" 2>&1 | tail -15
  fi
  docker rm -f "$CAND" >/dev/null 2>&1 || true
}

echo "### Baseline: current production ($PROD_CONTAINER, 27B + native MTP) ###"
measure "http://localhost:$PORT"

echo ""
echo "### Stopping production to free the GPU for candidates... ###"
docker stop "$PROD_CONTAINER" >/dev/null && echo "  stopped $PROD_CONTAINER"

# Candidate 1: Qwen3-Coder-30B-A3B (MoE coding specialist; no spec decoding)
run_candidate "Qwen3-Coder-30B-A3B (MoE)" \
  '-m /models/deepflash/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf'

# Candidate 2: Qwen3.8-27B + DFlash2 external drafter (vs current native MTP)
run_candidate "Qwen3.8-27B + DFlash2 drafter" \
  '-m /models/deepflash/Qwen3.8-27B-Q4_K_M.gguf -md /models/deepflash/Qwen3.8-27B-DFlash2-Q8_0.gguf --chat-template-file /models/deepflash/fixed_template_qwen3.8.jinja'

echo ""
echo "### Restoring production... ###"
docker start "$PROD_CONTAINER" >/dev/null && echo "  started $PROD_CONTAINER"
for _ in $(seq 1 120); do curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1 && { echo "  production healthy again"; break; }; sleep 2; done
echo "### bake-off complete ###"
