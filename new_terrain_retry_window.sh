#!/usr/bin/env bash
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/new-terrain-retry.out
REPO=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab

exec 9>/tmp/new_terrain_retry.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring: resuming queue + restarting inference container"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  docker start shrike-llama-dflash-35b >/dev/null 2>&1 || true
  for i in $(seq 1 30); do
    st=$(docker inspect --format='{{.State.Health.Status}}' shrike-llama-dflash-35b 2>/dev/null || echo unknown)
    [ "$st" = "healthy" ] && break
    sleep 5
  done
  log "inference container status: $(docker inspect --format='{{.State.Status}}' shrike-llama-dflash-35b 2>/dev/null) health=${st:-unknown}"
  log "=== RETRY WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + waiting for any in-progress cycle to clear"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$STATE/run.lock" >/dev/null 2>&1 || break; sleep 8; done

log "stopping inference container to free VRAM"
docker stop shrike-llama-dflash-35b >/dev/null 2>&1 || true
used=0
for i in $(seq 1 40); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  [ "$used" -lt 2500 ] && break
  sleep 3
done
log "GPU free (used=${used}MiB)"

cd "$REPO"
log "=== RETRY 1/2: 2 leftover phase-A props (fresh process) ==="
timeout 600 "$PY" scripts/retry_terrain_props.py >>"$OUT" 2>&1 && log "props retry ok" || log "props retry FAILED"

log "=== RETRY 2/2: 12 phase-B coherence siblings (fresh process) ==="
timeout 1800 "$PY" scripts/retry_terrain_siblings.py >>"$OUT" 2>&1 && log "siblings retry ok" || log "siblings retry FAILED"

log "=== RESULTS READY ==="
