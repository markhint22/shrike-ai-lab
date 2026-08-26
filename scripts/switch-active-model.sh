#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIVE_FILE="$ROOT_DIR/runtime/active-model.txt"
DFLASH_ENV_FILE="$ROOT_DIR/runtime/dflash-active.env"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <model-name>"
  echo "Examples:"
  echo "  $0 qwen-dflash-35B-A3B"
  echo "  $0 qwen-dflash-27B"
  echo "  $0 qwen-dflash-9B"
  echo "  $0 qwen3-coder:30b"
  exit 1
fi

MODEL="$1"
KNOWN_MODELS=(
  "qwen-dflash-35B-A3B"
  "qwen-dflash-27B"
  "qwen-dflash-9B"
  "qwen3-coder:30b"
)

is_known=false
for m in "${KNOWN_MODELS[@]}"; do
  if [[ "$MODEL" == "$m" ]]; then
    is_known=true
    break
  fi
done

if [[ "$is_known" == "false" ]]; then
  echo "Unknown model: $MODEL"
  echo "Allowed models: ${KNOWN_MODELS[*]}"
  exit 1
fi

echo "Switching active model to: $MODEL"

mkdir -p "$ROOT_DIR/runtime"

download_if_missing() {
  local target_file="$1"
  local source_url="$2"

  if [[ -f "$target_file" ]]; then
    return
  fi

  mkdir -p "$(dirname "$target_file")"
  echo "Downloading $(basename "$target_file")"
  wget -q -c -O "$target_file" "$source_url"
}

# ctx_size (2026-08-13 hardening): all three DFlash models were empirically
# tested with --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 (both
# halve the default f16 KV cache) - this made a much bigger context window
# affordable on this single 24GB GPU than the original flat 16384 default,
# with no model-quality change at all. 262144 is the model family's own
# trained context ceiling (n_ctx_train) - going higher just wastes VRAM on
# positions the model was never trained to understand.
#   qwen-dflash-35B-A3B at 262144: only ~75MB VRAM free - too risky for
#     production (request-size variance could OOM). Capped at 131072.
#   qwen-dflash-27B    at 262144: ~1.2GB VRAM free - comfortable, kept at 262144.
#   qwen-dflash-9B     at 262144: ~9.1GB VRAM free - very comfortable, kept at 262144.
# chat_template_args: fixed_template.jinja was built for the Qwen3.6 family
# (27B/35B-A3B). The 9B model is the older Qwen3.5 family and correctly
# auto-detects its own chat template from GGUF metadata without it (verified
# live via /v1/chat/completions - reasoning/content split worked correctly) -
# passing the 3.6 template to a 3.5 model is untested and likely wrong.
write_dflash_env() {
  local target_model="$1"
  local draft_model="$2"
  local alias_name="$3"
  local ctx_size="$4"
  local chat_template_args="$5"

  # spec_draft_n_max (2026-08-15): overridable via the DFLASH_SPEC_DRAFT_N_MAX
  # env var, default 4 unchanged from the original hardcoded value. Measured
  # live: draft acceptance rate is 0.63-0.81 with mean accepted length
  # 3.5-4.2 - i.e. the draft is already often proposing the full 4-token max
  # and getting it accepted, suggesting a higher cap could let it propose
  # (and get credit for) longer correct runs. Untested above 4 as of this
  # writing - change here, measure real tokens/sec via a direct completion
  # request before trusting it, and revert if it doesn't clearly help.
  local spec_draft_n_max="${DFLASH_SPEC_DRAFT_N_MAX:-4}"

  cat > "$DFLASH_ENV_FILE" <<EOF
DFLASH_TARGET_MODEL=$target_model
DFLASH_DRAFT_MODEL=$draft_model
DFLASH_MODEL_ALIAS=$alias_name
DFLASH_CTX_SIZE=$ctx_size
DFLASH_FLASH_ATTN=on
DFLASH_CACHE_TYPE_K=q8_0
DFLASH_CACHE_TYPE_V=q8_0
DFLASH_CHAT_TEMPLATE_ARGS=$chat_template_args
DFLASH_SPEC_DRAFT_N_MAX=$spec_draft_n_max
EOF
}

wait_for_dflash_health() {
  for _ in $(seq 1 180); do
    if curl -sf "http://localhost:8081/health" >/dev/null; then
      return 0
    fi
    sleep 2
  done

  return 1
}

validate_dflash_model() {
  local alias_name="$1"
  local response

  # Retry a few times (2026-08-13 hardening): litellm can take a couple of
  # seconds after its own restart before it is actually ready to route
  # requests, even though the underlying llama-server health check (which
  # gates this function being called at all) already passed. A transient
  # "connection reset" here used to be fatal under set -e, aborting the
  # whole script BEFORE it reached the final line that records the new
  # active model - leaving runtime/active-model.txt stale even though the
  # model swap itself had actually succeeded.
  for attempt in 1 2 3 4 5; do
    if response="$(curl -sS --max-time 15 http://localhost:4000/v1/completions \
      -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-shrike-local}" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"${alias_name}\",\"prompt\":\"Reply exactly with READY\",\"max_tokens\":8,\"temperature\":0}" 2>&1)"; then
      break
    fi
    echo "Validation attempt ${attempt}/5 failed, retrying in 3s..."
    sleep 3
  done

  if command -v jq >/dev/null 2>&1; then
    echo "$response" | jq -r '.choices[0].text // .error.message // .' 2>/dev/null || echo "$response"
  else
    echo "$response"
  fi
}

activate_dflash_model() {
  local target_file="$1"
  local draft_file="$2"
  local alias_name="$3"
  local ctx_size="$4"
  local chat_template_args="$5"

  write_dflash_env "$target_file" "$draft_file" "$alias_name" "$ctx_size" "$chat_template_args"

  docker compose --env-file "$DFLASH_ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" up -d --force-recreate llama-dflash-35b litellm ollama >/dev/null

  if ! wait_for_dflash_health; then
    echo "DFlash server did not become healthy for $alias_name"
    docker compose --env-file "$DFLASH_ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" logs --tail=160 llama-dflash-35b
    exit 1
  fi

  echo "Active model is ready: $alias_name"
  validate_dflash_model "$alias_name"
}

case "$MODEL" in
  qwen-dflash-35B-A3B)
    activate_dflash_model \
      "/models/deepflash/Qwen3.6-35B-A3B-Q4_K_M.gguf" \
      "/models/deepflash/dflash-Qwen3.6-35B-A3B-Q8_0.gguf" \
      "$MODEL" \
      "131072" \
      "--chat-template-file /models/deepflash/fixed_template.jinja"
    ;;
  qwen-dflash-27B)
    # NOTE (2026-08-26): STALE relative to production. Prod runs the TUNED
    # Qwen3.8-27B (65K ctx, -ngl 99, q4_0 KV, MTP n8, ~87 tok/s) defined by the
    # docker-compose.yml defaults + runtime/dflash-active.env, NOT this 3.6/256K
    # case. This case is kept only for A/B against the 3.6 dense model; do NOT run
    # it expecting the production config (it would clobber prod to 256K/no-ngl).
    download_if_missing \
      "$ROOT_DIR/models/deepflash/Qwen3.6-27B-Q4_K_M.gguf" \
      "https://huggingface.co/ggml-org/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-Q4_K_M.gguf"
    download_if_missing \
      "$ROOT_DIR/models/deepflash/dflash-Qwen3.6-27B-Q8_0.gguf" \
      "https://huggingface.co/ggml-org/Qwen3.6-27B-GGUF/resolve/main/dflash-Qwen3.6-27B-Q8_0.gguf"

    activate_dflash_model \
      "/models/deepflash/Qwen3.6-27B-Q4_K_M.gguf" \
      "/models/deepflash/dflash-Qwen3.6-27B-Q8_0.gguf" \
      "$MODEL" \
      "262144" \
      "--chat-template-file /models/deepflash/fixed_template.jinja"
    ;;
  qwen-dflash-9B)
    # Target: Qwen/Qwen3.5-9B, quantized by bartowski (no official ggml-org
    # GGUF repo exists for this size). Draft: qwen35-9b-dflash-Q4_K_M.gguf,
    # a third-party DFlash draft that was already present locally before
    # this pairing was verified - confirmed compatible live (2026-08-13):
    # speculative decoding engages correctly (draft acceptance rate ~65-88%
    # across test completions), chat template auto-detects correctly.
    download_if_missing \
      "$ROOT_DIR/models/deepflash/Qwen3.5-9B-Q4_K_M.gguf" \
      "https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/resolve/main/Qwen_Qwen3.5-9B-Q4_K_M.gguf"

    activate_dflash_model \
      "/models/deepflash/Qwen3.5-9B-Q4_K_M.gguf" \
      "/models/deepflash/qwen35-9b-dflash-Q4_K_M.gguf" \
      "$MODEL" \
      "262144" \
      ""
    ;;
  *)
    # Restart stack so OLLAMA_MAX_LOADED_MODELS changes are guaranteed live.
    docker compose -f "$ROOT_DIR/docker-compose.yml" up -d ollama litellm >/dev/null

    # Best-effort: stop any other loaded models to free memory immediately.
    for m in "${KNOWN_MODELS[@]}"; do
      if [[ "$m" != "$MODEL" ]]; then
        docker exec shrike-ollama ollama stop "$m" >/dev/null 2>&1 || true
      fi
    done

    # Warm selected model.
    set +e
    WARM_OUTPUT="$(docker exec shrike-ollama ollama run "$MODEL" "Reply with exactly READY" 2>&1)"
    WARM_RC=$?
    set -e

    if [[ $WARM_RC -ne 0 ]]; then
      echo "Model warm-up failed for $MODEL"
      echo "$WARM_OUTPUT"
      exit $WARM_RC
    fi

    echo "Active model is ready: $MODEL"
    echo "$WARM_OUTPUT" | tail -n 2
    ;;
esac

printf '%s\n' "$MODEL" > "$ACTIVE_FILE"
