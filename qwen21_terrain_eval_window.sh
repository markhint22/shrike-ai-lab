#!/usr/bin/env bash
# GPU window: Qwen-Image 2.1 terrain comparison eval (5 elements, text2img).
# Trap-safe: always clears art_window.hold + restarts inference on exit.
# Does NOT touch queue.sh pause state (orchestrating session owns that).
set -uo pipefail
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/qwen21-terrain-eval.out
VENV=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/.venv-qwen21
SCRIPT=/run/media/mhintermeister/secondary_drive1/comfy/models_eval/gen_qwen21_terrain_eval.py
C=shrike-llama-dflash-35b

mkdir -p "$Q/reports"
exec 9>/tmp/qwen21_terrain_eval.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring: clearing art_window.hold, restarting inference container (queue pause left untouched)"
  rm -f "$STATE/art_window.hold"
  docker start "$C" >/dev/null 2>&1 || true
  for i in $(seq 1 30); do
    st=$(docker inspect --format="{{.State.Health.Status}}" "$C" 2>/dev/null || echo unknown)
    [ "$st" = "healthy" ] && break
    sleep 5
  done
  log "inference container status: $(docker inspect --format="{{.State.Status}}" "$C" 2>/dev/null) health=${st:-unknown}"
  log "=== QWEN21 TERRAIN EVAL WINDOW DONE ==="
}
trap restore EXIT

mkdir -p "$STATE"
touch "$STATE/art_window.hold"
log "set art_window.hold (blocks gpu_autoswap.sh cron for this windows duration)"

log "stopping inference container to free VRAM"
docker stop "$C" >/dev/null 2>&1 || true
used=0
for i in $(seq 1 40); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  [ "$used" -lt 2500 ] && break
  sleep 3
done
log "GPU free (used=${used}MiB)"

log "=== GENERATING terrain eval (5 elements) ==="
if timeout 1800 "$VENV/bin/python3" "$SCRIPT" >>"$OUT" 2>&1; then
  log "gen script exited 0"
else
  log "gen script exited non-zero ($?)"
fi
