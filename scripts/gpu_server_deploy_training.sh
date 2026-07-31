#!/bin/bash
# ===========================================
# Shrike AI Lab - Deploy Training Pipeline to GPU Server
# ===========================================
# Syncs the training pipeline (scripts/ + training/, minus logs/cache/models)
# to a DEDICATED directory on the GPU server, separate from the docker-compose
# checkout that runs the LLM-serving stack. This is deliberate: the compose
# directory's config has already diverged from this repo (see the gpu-server
# skill) and training must never risk clobbering it.
#
# Usage: ./scripts/gpu_server_deploy_training.sh
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

GPU_SERVER_HOST="${GPU_SERVER_HOST:?Set GPU_SERVER_HOST in .env}"
GPU_SERVER_SSH_USER="${GPU_SERVER_SSH_USER:?Set GPU_SERVER_SSH_USER in .env}"
REMOTE_DIR="${TRAINING_REMOTE_DIR:-~/shrike-ai-lab-training}"

echo "Deploying training pipeline to ${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}:${REMOTE_DIR}"
echo "(This is a separate directory from the docker-compose stack — not touching that.)"

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

ssh $SSH_OPTS "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}" "mkdir -p ${REMOTE_DIR}"

# No --delete: additive sync only, so anything added directly on the server
# (e.g. real training data collected there) is never wiped by a Mac-side deploy.
rsync -avz -e "ssh $SSH_OPTS" \
  --exclude 'training/logs/' \
  --exclude 'training/cache/' \
  --exclude 'models/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  "$REPO_ROOT/scripts/" "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}:${REMOTE_DIR}/scripts/"

rsync -avz -e "ssh $SSH_OPTS" \
  --exclude 'logs/' \
  --exclude 'cache/' \
  "$REPO_ROOT/training/" "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}:${REMOTE_DIR}/training/"

rsync -avz -e "ssh $SSH_OPTS" "$REPO_ROOT/pyproject.toml" "$REPO_ROOT/requirements.txt" \
  "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}:${REMOTE_DIR}/"

echo "Deploy complete: ${REMOTE_DIR}"
