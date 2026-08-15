#!/bin/bash
# ===========================================
# Shrike AI Lab - Stop Inference Container (free GPU for training)
# ===========================================
# The inference container already holds ~22.6GB/24GB VRAM (self-speculative
# Q4 main + Q8 draft model) - there's no room to also run a training job.
# Stop it before training, then bring it back with gpu_server_restart.sh
# (which works whether the container is currently running or stopped).
#
# Usage: ./scripts/gpu_server_stop_inference.sh [container]
#   ./scripts/gpu_server_stop_inference.sh                    # shrike-llama-dflash-35b
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

echo "Stopping '${CONTAINER}' on ${GPU_SERVER_HOST} to free the GPU for training..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}" "docker stop ${CONTAINER}"
echo "Stopped. Chat/aider inference is unavailable until it's restarted (scripts/gpu_server_restart.sh)."
