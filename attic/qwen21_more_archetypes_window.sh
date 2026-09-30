#!/usr/bin/env bash
# GPU window: generate the 6-archetype x 6-pose Qwen-Image 2.1 "more
# archetypes" eval (elite/raider/shotgunner/shield/minigunner/boss).
# Trap-safe: always clears art_window.hold + restarts inference on exit,
# success or failure. Does NOT touch queue.sh pause state - the queue was
# already paused by the orchestrating session and stays paused for it to
# resume. Modeled directly on qwen21_full_roster_window.sh.
set -uo pipefail
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/qwen21-more-archetypes.out
VENV=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/.venv-qwen21
SCRIPT=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/gen_qwen21_more_archetypes.py
C=shrike-llama-dflash-35b

mkdir -p "$Q/reports"
exec 9>/tmp/qwen21_more_archetypes.lock
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
  log "=== QWEN21 MORE-ARCHETYPES WINDOW DONE ==="
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

log "=== GENERATING more archetypes (6 chars x 6 poses = 36 images) ==="
if timeout 5400 "$VENV/bin/python3" "$SCRIPT" "$@" >>"$OUT" 2>&1; then
  log "gen script exited 0"
else
  log "gen script exited non-zero ($?)"
fi
