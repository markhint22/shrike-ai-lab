#!/usr/bin/env bash
# GPU window: generate mega-batch part 1/3 - walls/windows/floors ONLY for 7
# new themes (frozen/desert/farmland/subway/hospital/dock/prison). Trap-safe:
# always resumes the queue + restarts inference on exit, success or failure.
# Also holds gpu_autoswap.sh off via state/art_window.hold (its documented
# guard) - a bare docker-stop isn't enough, the autoswap cron races back in
# on the very next free-GPU tick and OOMs the next generation.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/new-terrain-batch3.out
REPO=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab

exec 9>/tmp/new_terrain_batch3.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring: clearing art_window.hold, resuming queue + restarting inference container"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  docker start shrike-llama-dflash-35b >/dev/null 2>&1 || true
  for i in $(seq 1 30); do
    st=$(docker inspect --format='{{.State.Health.Status}}' shrike-llama-dflash-35b 2>/dev/null || echo unknown)
    [ "$st" = "healthy" ] && break
    sleep 5
  done
  log "inference container status: $(docker inspect --format='{{.State.Status}}' shrike-llama-dflash-35b 2>/dev/null) health=${st:-unknown}"
  log "=== NEW TERRAIN BATCH3 WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + waiting for any in-progress cycle to clear"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$STATE/run.lock" >/dev/null 2>&1 || break; sleep 8; done

mkdir -p "$STATE"
touch "$STATE/art_window.hold"
log "set art_window.hold (blocks gpu_autoswap.sh cron for this window's duration)"

log "stopping inference container to free VRAM"
docker stop shrike-llama-dflash-35b >/dev/null 2>&1 || true
used=0
for i in $(seq 1 40); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  [ "$used" -lt 2500 ] && break
  sleep 3
done
log "GPU free (used=${used}MiB)"

log "=== GENERATING new terrain batch3 (63 items) ==="
cd "$REPO"
if timeout 5400 "$PY" scripts/gen_new_terrain_batch3.py >>"$OUT" 2>&1; then
  log "batch script exited 0"
else
  log "batch script exited non-zero ($?)"
fi
log "=== RESULTS READY ==="
