#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/models/deepflash"
TARGET_FILE="$MODELS_DIR/Qwen3.6-35B-A3B-Q4_K_M.gguf"
DRAFT_FILE="$MODELS_DIR/dflash-Qwen3.6-35B-A3B-Q8_0.gguf"

chmod +x "$ROOT_DIR/scripts/preflight-dflash-35b.sh"
"$ROOT_DIR/scripts/preflight-dflash-35b.sh" --fix

mkdir -p "$MODELS_DIR"

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "Downloading target model: Qwen3.6-35B-A3B-Q4_K_M.gguf (about 19 GB)"
  wget -q -c -O "$TARGET_FILE" "https://huggingface.co/ggml-org/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-Q4_K_M.gguf"
fi

if [[ ! -f "$DRAFT_FILE" ]]; then
  echo "Downloading draft model: dflash-Qwen3.6-35B-A3B-Q8_0.gguf (about 402 MB)"
  wget -q -c -O "$DRAFT_FILE" "https://huggingface.co/ggml-org/Qwen3.6-35B-A3B-GGUF/resolve/main/dflash-Qwen3.6-35B-A3B-Q8_0.gguf"
fi

echo "Starting dflash + litellm services"
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d llama-dflash-35b litellm

echo "Waiting for dflash server"
for _ in $(seq 1 60); do
  if curl -sf "http://localhost:8081/health" >/dev/null; then
    break
  fi
  sleep 2
done

if ! curl -sf "http://localhost:8081/health" >/dev/null; then
  echo "DFlash server did not become healthy in time"
  docker compose -f "$ROOT_DIR/docker-compose.yml" logs --tail=120 llama-dflash-35b
  exit 1
fi

echo "Validating via LiteLLM"
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-shrike-local}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen-dflash-35B-A3B","messages":[{"role":"user","content":"Reply with exactly DFLASH_35B_READY"}],"temperature":0}' | jq -r '.choices[0].message.content // .error.message'

echo "qwen-dflash-35B-A3B is active."
