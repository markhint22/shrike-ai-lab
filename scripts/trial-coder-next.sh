#!/usr/bin/env bash
# ============================================================================
# trial-coder-next.sh  —  A/B trial launcher for Qwen3-Coder-Next (80B MoE)
# ----------------------------------------------------------------------------
# Qwen3-Coder-Next is an 80B MoE (~3B active). At UD-Q4_K_XL it is ~46 GiB and
# does NOT fit the 3090's 24 GB VRAM. This launcher keeps ATTENTION on the GPU
# (-ngl 99) and offloads ALL MoE expert tensors to CPU/RAM (--cpu-moe). 108 GB
# free RAM is plenty. Attention + KV still need GPU room, so:
#
#   >>> STOP THE 27B FLEET FIRST — they cannot share the 24 GB GPU. <<<
#
# The fleet (shrike-llama-dflash-35b) normally holds ~23.9/24 GB. This trial
# container is STOPPED by default and only serves the LiteLLM alias
# `qwen-coder-next` (api_base http://shrike-llama-coder-next:8080/v1) while up.
#
# Usage:
#   ./trial-coder-next.sh start   # stops the 27B fleet, starts Coder-Next :8082
#   ./trial-coder-next.sh stop    # stops Coder-Next (does NOT restart fleet)
#   ./trial-coder-next.sh restore # stops Coder-Next AND restarts the 27B fleet
#   ./trial-coder-next.sh test    # quick health + completion probe on :8082
# ============================================================================
set -euo pipefail

LAB_DIR="/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab"
MODELS_DIR="${LAB_DIR}/models"
MODEL="/models/deepflash/Qwen3-Coder-Next-UD-Q4_K_XL.gguf"
IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda"
NET="shrike-ai-network"
NAME="shrike-llama-coder-next"
HOST_PORT="8082"
FLEET="shrike-llama-dflash-35b"

start() {
  echo ">> Stopping 27B fleet (${FLEET}) to free the GPU..."
  docker stop "${FLEET}" || true
  echo ">> Removing any old ${NAME} container..."
  docker rm -f "${NAME}" 2>/dev/null || true
  echo ">> Starting Coder-Next on :${HOST_PORT} (attention on GPU, experts on CPU)..."
  docker run -d --name "${NAME}" --network "${NET}" \
    --gpus all \
    -v "${MODELS_DIR}:/models" \
    -e GGML_CUDA_GRAPH_OPT=1 \
    -p "${HOST_PORT}:8080" \
    --entrypoint /app/llama-server \
    "${IMAGE}" \
    -m "${MODEL}" \
    -ngl 99 \
    --cpu-moe \
    --ctx-size 32768 \
    --flash-attn on \
    --jinja \
    --temp 1.0 --top-p 0.95 --top-k 40 \
    --batch-size 512 --ubatch-size 256 \
    --host 0.0.0.0 --port 8080 \
    --alias qwen-coder-next
  echo ">> Started. Model load (46 GiB, CPU expert offload) takes a few minutes."
  echo ">> Watch: docker logs -f ${NAME}"
  echo ">> LiteLLM alias: qwen-coder-next  (via :4000)"
}

stop() {
  echo ">> Stopping/removing ${NAME}..."
  docker rm -f "${NAME}" 2>/dev/null || true
  echo ">> Done. NOTE: 27B fleet was NOT restarted (use 'restore')."
}

restore() {
  stop
  echo ">> Restarting 27B fleet (${FLEET})..."
  docker start "${FLEET}" || (cd "${LAB_DIR}" && docker compose up -d llama-dflash-35b)
  echo ">> Fleet restarting. Verify: curl -s localhost:8081/health"
}

test_probe() {
  echo ">> /health on :${HOST_PORT}:"
  curl -s "http://localhost:${HOST_PORT}/health" || true
  echo
  echo ">> completion probe:"
  curl -s "http://localhost:${HOST_PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen-coder-next","messages":[{"role":"user","content":"Write a Python one-liner that reverses a string."}],"max_tokens":128,"temperature":1.0}' \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["choices"][0]["message"]["content"])' || true
  echo
}

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restore) restore ;;
  test)    test_probe ;;
  *) echo "usage: $0 {start|stop|restore|test}"; exit 1 ;;
esac
