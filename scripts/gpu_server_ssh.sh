#!/bin/bash
# ===========================================
# Shrike AI Lab - GPU Server SSH Shortcut
# ===========================================
# Opens an interactive SSH session to the GPU server.
# Uses key-based auth (no password needed) once ssh-copy-id has been run.
#
# Usage: ./scripts/gpu_server_ssh.sh [remote command]
#   ./scripts/gpu_server_ssh.sh                # interactive shell
#   ./scripts/gpu_server_ssh.sh "docker ps"    # run one command and exit
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

ssh -o BatchMode=yes -o ConnectTimeout=10 "${GPU_SERVER_SSH_USER}@${GPU_SERVER_HOST}" "$@"
