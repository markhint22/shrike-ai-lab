#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Runner Smoke Test
# ===========================================
# Checks everything that CAN be verified without the GPU server being
# reachable (tooling installed, tasks.json valid), and reports on the parts
# that need the GPU server (model reachability/registration).
# ===========================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

GPU_SERVER_HOST="${GPU_SERVER_HOST:-192.168.68.145}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL_NAME="${OVERNIGHT_MODEL:-qwen-dflash-35B-A3B}"
LITELLM_BASE="http://${GPU_SERVER_HOST}:4000"
TASKS_FILE="$SCRIPT_DIR/tasks.json"

FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "OK   - ${desc}"
  else
    echo "FAIL - ${desc}"
    FAIL=1
  fi
}

echo "=== Local checks (no GPU server needed) ==="
check "aider is installed"      command -v aider
check "jq is installed"         command -v jq
check "git is installed"        command -v git
check "tasks.json is valid JSON" jq empty "$TASKS_FILE"

echo ""
echo "=== GPU-server-dependent checks (will FAIL while off the home LAN) ==="
if curl -sf --max-time 5 "${LITELLM_BASE}/health/liveliness" >/dev/null 2>&1 \
  || curl -sf --max-time 5 "${LITELLM_BASE}/health" >/dev/null 2>&1; then
  echo "OK   - GPU server reachable at ${LITELLM_BASE}"
  if curl -sf --max-time 10 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" "${LITELLM_BASE}/v1/models" \
      | grep -q "\"${MODEL_NAME}\""; then
    echo "OK   - model '${MODEL_NAME}' is registered"
  else
    echo "FAIL - model '${MODEL_NAME}' not found in ${LITELLM_BASE}/v1/models (set OVERNIGHT_MODEL in .env to override)"
    FAIL=1
  fi
else
  echo "FAIL - GPU server not reachable at ${LITELLM_BASE} (expected while off the home LAN)"
  FAIL=1
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All checks passed."
else
  echo "One or more checks failed — see above."
fi
exit "$FAIL"
