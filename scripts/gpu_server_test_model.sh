#!/bin/bash
# ===========================================
# Shrike AI Lab - Quick Model Test
# ===========================================
# Sends a minimal chat completion through the litellm proxy to confirm the
# model is up, on GPU, and responding correctly.
#
# Usage: ./scripts/gpu_server_test_model.sh [model-name]
#   ./scripts/gpu_server_test_model.sh                    # qwen-dflash-35B-A3B
#   ./scripts/gpu_server_test_model.sh qwen-coder-30b-local
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

GPU_SERVER_HOST="${GPU_SERVER_HOST:?Set GPU_SERVER_HOST in .env}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${1:-qwen-dflash-35B-A3B}"

echo "Testing '${MODEL}' via http://${GPU_SERVER_HOST}:4000 ..."

curl -s -m 60 "http://${GPU_SERVER_HOST}:4000/v1/chat/completions" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"chat_template_kwargs\":{\"enable_thinking\":false},\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":20}" \
  | python3 -m json.tool
