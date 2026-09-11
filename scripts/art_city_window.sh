#!/usr/bin/env bash
# GPU window: run the ruined-wasteland-CITY prop/building batch
# (gen_city_props.py, from docs/art/CITY_PROPS_BRIEF.md + city_reference_
# briefs.json) through gen -> pixelize3. Same trap-safe pause/restore
# pattern as art_character_window.sh - restores llama + queue on exit no
# matter how the run ends (success, failure, or kill).
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/art-city-props.out
CITY_OUT=/run/media/mhintermeister/secondary_drive1/comfy/out/city_props

exec 9>/tmp/art_city.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  # Remove the watcher hold + resume the queue; the auto-swap watcher (cron, 1 min)
  # restores the production 27B on its next tick now that the GPU is free again.
  log "removing art hold + resuming (watcher restores 27B)"
  rm -f "$STATE/art_window.hold"
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  # Verify, don't just trust the trap - the whole point of this window is that
  # the fleet must be back up when it's done (explicit user requirement).
  sleep 5
  if docker ps --format '{{.Names}}' | grep -q shrike-llama-dflash-35b; then
    log "verified: shrike-llama-dflash-35b is back up"
  else
    log "WARNING: shrike-llama-dflash-35b not detected running after resume - check manually"
  fi
  log "=== ART CITY WINDOW DONE ==="
}
trap restore EXIT

# Pin the auto-swap watcher OFF for the whole window (it otherwise restarts the 27B
# in the gap between gen subprocesses -> the next gen OOMs), pause the queue, and stop
# BOTH model containers (the watched 27B AND the coder-next A/B trial) to free VRAM.
mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "pausing queue + freeing GPU (both model containers)"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export SEEDS_PER_VARIANT="${SEEDS_PER_VARIANT:-3}"
log "=== GENERATING (SEEDS_PER_VARIANT=$SEEDS_PER_VARIANT, modules: ${*:-ALL}) ==="
timeout 7200 "$PY" /tmp/gen_city_props.py "$@" >>"$OUT" 2>&1 && log "generation ok" || log "generation FAILED (check $OUT)"
log "raw renders: $(ls "$CITY_OUT"/*.png 2>/dev/null | wc -l)"

log "=== ISOLATING (pixelize3.py) ==="
"$PY" /tmp/pixelize3.py "$CITY_OUT" >>"$OUT" 2>&1 && log "isolation ok" || log "isolation FAILED (check $OUT)"
log "isolated pieces: $(ls "${CITY_OUT}_sprites3"/*@64.png 2>/dev/null | wc -l)"
log "=== RESULTS READY: ${CITY_OUT}_sprites3 ==="
