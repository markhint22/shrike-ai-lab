#!/bin/bash
# ===========================================
# Shrike AI Lab - GPU Server Container Restart
# ===========================================
# Restarts one container on the remote GPU server (not the whole docker-compose
# stack). Useful after editing docker-compose.yml (run this via
# gpu_server_ssh.sh + `docker compose up -d <service>` instead) or after the
# GPU-passthrough race condition on boot (see .claude/skills/gpu-server).
#
# Usage: ./scripts/gpu_server_restart.sh [container]
#   ./scripts/gpu_server_restart.sh                    # shrike-llama-dflash-35b
#   ./scripts/gpu_server_restart.sh shrike-litellm
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
SSH="ssh -o BatchMode=yes ${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}"

echo "Restarting '${CONTAINER}' on ${GPU_SERVER_HOST}..."
$SSH "docker restart ${CONTAINER}"

# Not every container has a Docker HEALTHCHECK defined (e.g. shrike-litellm
# doesn't) - Health.Status comes back empty in that case, not "unhealthy".
# Polling for "healthy" on those would never succeed, so fall back to just
# checking the container is running after a short grace period instead.
HAS_HEALTHCHECK=$($SSH "docker inspect --format='{{if .State.Health}}yes{{else}}no{{end}}' ${CONTAINER} 2>/dev/null")

if [ "$HAS_HEALTHCHECK" = "yes" ]; then
  echo "Waiting for it to become healthy..."
  for i in $(seq 1 24); do
    HEALTH=$($SSH "docker inspect --format='{{.State.Health.Status}}' ${CONTAINER} 2>/dev/null" || echo "unknown")
    echo "  [$i] health: ${HEALTH}"
    if [ "$HEALTH" = "healthy" ]; then
      echo "✅ ${CONTAINER} is healthy"
      exit 0
    fi
    sleep 5
  done
  echo "⚠️  Still not healthy after 2 minutes - check logs with gpu_server_logs.sh"
else
  echo "No Docker healthcheck defined for '${CONTAINER}' - checking it's running instead..."
  sleep 10
  STATUS=$($SSH "docker inspect --format='{{.State.Status}}' ${CONTAINER} 2>/dev/null" || echo "unknown")
  if [ "$STATUS" = "running" ]; then
    echo "✅ ${CONTAINER} is running (status: ${STATUS})"
  else
    echo "⚠️  ${CONTAINER} status is '${STATUS}', not running - check logs with gpu_server_logs.sh"
  fi
fi
