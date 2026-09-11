#!/usr/bin/env bash
# GPU window: run the v2 city TILESET generator (gen_city_tileset.py) - real
# seamless-tiled walls/floors + fixed bounded chunks/props. Same trap-safe
# pause/free-GPU/restore-on-EXIT pattern as art_city_window.sh.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/art-city-tileset.out
CHUNKS_OUT=/run/media/mhintermeister/secondary_drive1/comfy/out/city_tileset_v2/chunks

exec 9>/tmp/art_city_tileset.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "removing hold + resuming (watcher restores 27B within ~1min)"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  # The auto-swap watcher fires on the next top-of-minute cron tick, which can
  # be up to ~60s away - poll for up to 90s instead of a single early check
  # (a single 5s check falsely warned twice earlier tonight even though the
  # watcher always recovered fine within its normal cycle).
  ok=0
  for i in $(seq 1 18); do
    if docker ps --format '{{.Names}} {{.Status}}' | grep -q 'shrike-llama-dflash-35b.*healthy'; then
      ok=1; break
    fi
    sleep 5
  done
  if [ "$ok" = "1" ]; then
    log "verified: shrike-llama-dflash-35b is healthy"
  else
    log "WARNING: shrike-llama-dflash-35b not healthy after 90s - check manually"
  fi
  log "=== ART CITY TILESET WINDOW DONE ==="
}
trap restore EXIT

mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
log "=== GENERATING (targets: ${*:-ALL}) ==="
timeout 5400 "$PY" /tmp/gen_city_tileset.py "$@" >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED (check $OUT)"

if [ -d "$CHUNKS_OUT" ] && [ "$(ls -A "$CHUNKS_OUT" 2>/dev/null)" ]; then
  log "=== ISOLATING CHUNKS (pixelize3.py) ==="
  "$PY" /tmp/pixelize3.py "$CHUNKS_OUT" >>"$OUT" 2>&1 && log "isolation ok" || log "isolation FAILED"
  log "isolated chunks: $(ls "${CHUNKS_OUT}_sprites3"/*@64.png 2>/dev/null | wc -l)"
fi
log "=== RESULTS READY ==="
