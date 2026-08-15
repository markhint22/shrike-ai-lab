#!/bin/bash
# ===========================================
# Shrike AI Lab - GPU Server Logs
# ===========================================
# Tails logs for a container on the remote GPU server.
#
# Usage: ./scripts/gpu_server_logs.sh [container] [tail-lines]
#   ./scripts/gpu_server_logs.sh                          # llama-dflash-35b, last 100 lines
#   ./scripts/gpu_server_logs.sh shrike-litellm 300
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
GPU_SERVER_SSH_USER="${GPU_SERVER_SSH_USER:?Set GPU_SERVER_SSH_USER in .env}"

CONTAINER="${1:-shrike-llama-dflash-35b}"
TAIL="${2:-100}"

echo "Tailing logs for '${CONTAINER}' (last ${TAIL} lines, Ctrl-C to stop)..."
ssh -o BatchMode=yes "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}" \
  "docker logs -f --tail=${TAIL} ${CONTAINER}"
