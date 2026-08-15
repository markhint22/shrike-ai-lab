#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/runtime"
REPORT_FILE="$REPORT_DIR/dflash-35b-test-report.txt"

mkdir -p "$REPORT_DIR"

ACT_PID="${1:-}"
if [[ -z "$ACT_PID" ]]; then
  ACT_PID="$(pgrep -f 'bash ./scripts/activate-dflash-35b.sh' | head -n 1 || true)"
fi

{
  echo "[START] $(date -Iseconds)"
  if [[ -n "$ACT_PID" ]]; then
    echo "Waiting for activation PID: $ACT_PID"
    tail --pid="$ACT_PID" -f /dev/null || true
  else
    echo "No activation PID found; proceeding with immediate checks"
  fi

  echo "[CHECK] Service status"
  docker compose -f "$ROOT_DIR/docker-compose.yml" ps

  echo "[TEST] Local inference via LiteLLM"
  curl -s http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-shrike-local}" \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen-dflash-35B-A3B","messages":[{"role":"user","content":"Reply with exactly LOCAL_DFLASH_35B_OK"}],"temperature":0}'

  echo "[TEST] LAN inference via LiteLLM"
  curl -s http://192.168.68.145:4000/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-sk-shrike-local}" \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen-dflash-35B-A3B","messages":[{"role":"user","content":"Reply with exactly LAN_DFLASH_35B_OK"}],"temperature":0}'

  echo "[END] $(date -Iseconds)"
} > "$REPORT_FILE" 2>&1

echo "Wrote report: $REPORT_FILE"
