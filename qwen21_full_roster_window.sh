#!/usr/bin/env bash
# GPU window: generate the 8-character x 6-pose full-roster Qwen-Image 2.1
# eval. Trap-safe: always clears art_window.hold + restarts inference on
# exit, success or failure. Deliberately does NOT touch the overnight
# queue's own pause state (queue.sh pause/resume) - the queue was already
# paused by the orchestrating session before this ran, and stays paused for
# that separate process to resume; this script only fights gpu_autoswap.sh
# (which fights back within 1 minute via cron if art_window.hold isn't set).
set -uo pipefail
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/qwen21-full-roster.out
VENV=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/.venv-qwen21
SCRIPT=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/gen_qwen21_full_roster.py
C=shrike-llama-dflash-35b

mkdir -p "$Q/reports"
exec 9>/tmp/qwen21_full_roster.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring: clearing art_window.hold, restarting inference container (queue pause left untouched)"
  rm -f "$STATE/art_window.hold"
  docker start "$C" >/dev/null 2>&1 || true
  for i in $(seq 1 30); do
    st=$(docker inspect --format='{{.State.Health.Status}}' "$C" 2>/dev/null || echo unknown)
    [ "$st" = "healthy" ] && break
    sleep 5
  done
  log "inference container status: $(docker inspect --format='{{.State.Status}}' "$C" 2>/dev/null) health=${st:-unknown}"
  log "=== QWEN21 FULL ROSTER WINDOW DONE ==="
}
trap restore EXIT

mkdir -p "$STATE"
touch "$STATE/art_window.hold"
log "set art_window.hold (blocks gpu_autoswap.sh cron for this window's duration)"

log "stopping inference container to free VRAM"
docker stop "$C" >/dev/null 2>&1 || true
used=0
for i in $(seq 1 40); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  [ "$used" -lt 2500 ] && break
  sleep 3
done
log "GPU free (used=${used}MiB)"

log "=== GENERATING full roster (8 chars x 6 poses = 48 images) ==="
if timeout 5400 "$VENV/bin/python3" "$SCRIPT" >>"$OUT" 2>&1; then
  log "gen script exited 0"
else
  log "gen script exited non-zero ($?)"
fi
