#!/usr/bin/env bash
# One GPU maintenance window: generate xlite's ruined-city terrain/object art
# (buildings, roads, sidewalks, street furniture - see art_terrain_briefs.json),
# many seed variants per piece, then isolate/downscale with pixelize3.py.
#
# ALWAYS restores the prod llama server + overnight queue on exit (trap), even
# on failure. Uses the art_window.hold file (NOT just queue.sh pause) because
# gpu_autoswap.sh runs every 1 min and would otherwise restart llama in the gap
# BETWEEN this script's generation and pixelize3 subprocesses, OOMing the next
# one - see memory project_gpu-autoswap-watcher.md's 2026-09-08 update. The
# earlier xlite_art_batch_window.sh template did NOT set this hold; this one
# does, on purpose, as the fix for that exact gap.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
HERE=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/scripts
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-terrain-pieces.out
TER=/run/media/mhintermeister/secondary_drive1/comfy/out/terrain
VARIANTS="${VARIANTS:-6}"

exec 9>/tmp/xlite_terrain_pieces.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring prod llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do
    docker exec "$LLAMA" curl -sf --max-time 5 http://localhost:8080/health >/dev/null 2>&1 && break
    sleep 2
  done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  # Remove the hold LAST, after llama is confirmed back - the watcher's own
  # restart logic never needs to fire, this is just cleanup for correctness.
  rm -f "$Q/state/art_window.hold"
  log "prod restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== TERRAIN PIECES WINDOW DONE ==="
}
trap restore EXIT

log "setting art_window.hold + pausing queue + freeing GPU"
mkdir -p "$Q/state"
touch "$Q/state/art_window.hold"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1) MiB used"

log "=== 1/2 generating terrain/object art ($VARIANTS variants/key) ==="
timeout 7200 "$PY" "$HERE/gen_terrain_from_brief.py" --variants "$VARIANTS" >>"$OUT" 2>&1 && log "gen ok" || log "gen FAILED"
log "raw renders: $(ls "$TER"/*.png 2>/dev/null | wc -l)"

log "=== 2/2 pixelize (isolate objects / keep tiles full-frame) ==="
timeout 900 "$PY" "$HERE/pixelize3.py" "$TER" >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "sprites: $(ls ${TER}_sprites3/*@64.png 2>/dev/null | wc -l) at 64px"
log "=== RESULTS READY (out/terrain_sprites3) ==="
