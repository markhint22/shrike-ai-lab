#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="$ROOT_DIR/models/deepflash/Qwen3.6-35B-A3B-Q4_K_M.gguf"
DRAFT_FILE="$ROOT_DIR/models/deepflash/dflash-Qwen3.6-35B-A3B-Q8_0.gguf"

TARGET_EXPECTED=20419565568
DRAFT_EXPECTED=421060800

human_size() {
  numfmt --to=iec --suffix=B "$1"
}

print_file_status() {
  local file="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -f "$file" ]]; then
    echo "$label: missing"
    return
  fi

  local size
  size=$(stat -c '%s' "$file")
  local pct=$(( size * 100 / expected ))

  if [[ "$size" -ge "$expected" ]]; then
    echo "$label: ready ($(human_size "$size"))"
  else
    echo "$label: downloading ($(human_size "$size") / $(human_size "$expected"), ${pct}%)"
  fi
}

print_file_status "$TARGET_FILE" "$TARGET_EXPECTED" "Target"
print_file_status "$DRAFT_FILE" "$DRAFT_EXPECTED" "Draft"

echo ""
echo "Service status:"
docker compose -f "$ROOT_DIR/docker-compose.yml" ps --format json 2>/dev/null | jq -r '.Name + ": " + .State' || true

if curl -sf -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-shrike-local}" "http://localhost:4000/health" >/dev/null; then
  echo "LiteLLM health: ready"
else
  echo "LiteLLM health: not ready"
fi

if curl -sf "http://localhost:8081/health" >/dev/null; then
  echo "DFlash server health: ready"
else
  echo "DFlash server health: not ready"
fi
