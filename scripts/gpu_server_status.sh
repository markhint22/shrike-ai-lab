#!/bin/bash
# ===========================================
# Shrike AI Lab - GPU Server Status Check
# ===========================================
# Checks containers, GPU usage, and API health on the remote GPU server.
#
# Usage: ./scripts/gpu_server_status.sh
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

GPU_SERVER_HOST="${GPU_SERVER_HOST:?Set GPU_SERVER_HOST in .env (see .env.example)}"
GPU_SERVER_SSH_USER="${GPU_SERVER_SSH_USER:?Set GPU_SERVER_SSH_USER in .env}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"

SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}"

echo "🦅 Shrike AI Lab - GPU Server Status (${GPU_SERVER_HOST})"
echo "==========================================================="
echo ""

echo "1. SSH reachability..."
if $SSH "echo ok" > /dev/null 2>&1; then
  echo "✅ SSH reachable (key-based auth working)"
else
  echo "❌ SSH not reachable. Is the box on and sshd running?"
  exit 1
fi
echo ""

echo "2. GPU (nvidia-smi)..."
$SSH "nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv" 2>/dev/null \
  || echo "⚠️  Could not query GPU"
echo ""

echo "3. Docker containers..."
$SSH "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null \
  || echo "⚠️  Could not query docker"
echo ""

echo "4. API health..."
echo -n "  LiteLLM (:4000):      "
curl -s -m 5 "http://${GPU_SERVER_HOST}:4000/v1/models" -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" > /dev/null \
  && echo "✅ Responding" || echo "❌ Not responding"

echo -n "  llama-server (:8081): "
curl -s -m 5 "http://${GPU_SERVER_HOST}:8081/health" > /dev/null 2>&1 \
  && echo "✅ Responding" || echo "❌ Not responding"
