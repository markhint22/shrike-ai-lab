#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
EXPECTED_MODELS_DIR="$ROOT_DIR/models"
MAIN_MODEL="$EXPECTED_MODELS_DIR/deepflash/Qwen3.6-35B-A3B-Q4_K_M.gguf"
DRAFT_MODEL="$EXPECTED_MODELS_DIR/deepflash/dflash-Qwen3.6-35B-A3B-Q8_0.gguf"
CONTAINER_NAME="shrike-llama-dflash-35b"

AUTO_FIX=false
if [[ "${1:-}" == "--fix" ]]; then
  AUTO_FIX=true
fi

if [[ ! -f "$MAIN_MODEL" ]]; then
  echo "[ERROR] Missing main model: $MAIN_MODEL"
  exit 1
fi

if [[ ! -f "$DRAFT_MODEL" ]]; then
  echo "[ERROR] Missing draft model: $DRAFT_MODEL"
  exit 1
fi

get_models_mount_source() {
  docker inspect "$CONTAINER_NAME" \
    --format '{{range .Mounts}}{{if eq .Destination "/models"}}{{.Source}}{{end}}{{end}}' \
    2>/dev/null || true
}

canonical_path() {
  readlink -f "$1" 2>/dev/null || echo "$1"
}

container_exists=false
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  container_exists=true
fi

if [[ "$container_exists" == true ]]; then
  actual_source="$(get_models_mount_source)"
  expected_source="$(canonical_path "$EXPECTED_MODELS_DIR")"
  actual_source_canon="$(canonical_path "$actual_source")"

  if [[ -z "$actual_source" ]]; then
    echo "[WARN] Container exists but /models mount was not found."
  elif [[ "$actual_source_canon" != "$expected_source" ]]; then
    echo "[WARN] Detected stale /models bind mount:"
    echo "       expected: $expected_source"
    echo "       actual:   $actual_source_canon"

    if [[ "$AUTO_FIX" == true ]]; then
      echo "[FIX] Recreating services from current workspace path..."
      docker compose -f "$COMPOSE_FILE" down
      docker compose -f "$COMPOSE_FILE" up -d --force-recreate llama-dflash-35b litellm ollama
    else
      echo "[ACTION] Run this script with --fix to auto-recreate containers."
      exit 1
    fi
  fi
fi

echo "[OK] Preflight passed for qwen-dflash-35B-A3B"
