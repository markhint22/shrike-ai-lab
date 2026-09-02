#!/usr/bin/env bash
# Deep-dive xlite art window: proper ANIMATED poses (ControlNet+IP-Adapter, the fix
# for identical frames), MULTIPLE-OPTION unit/enemy/terrain/icon renders, and wasteland
# background options. ALWAYS restores the prod llama server + queue on exit (trap).
# Timeout-bounded, flock-guarded.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-art-deepdive.out
ANIMS=/run/media/mhintermeister/secondary_drive1/comfy/out/anims
OPTS=/run/media/mhintermeister/secondary_drive1/comfy/out/options
SCN=/run/media/mhintermeister/secondary_drive1/comfy/out/scenes

exec 9>/tmp/xlite_deepdive.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore(){
  log "restoring prod llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored: $(docker ps --filter name=$LLAMA --format '{{.Status}}')"
  log "=== DEEP-DIVE ART WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1) MiB used"

log "=== 1/5 pose skeletons ==="
timeout 120 "$PY" /tmp/pose_skeletons.py >>"$OUT" 2>&1 && log "skeletons ok" || log "skeletons FAILED"

log "=== 2/5 animated pose sets (ControlNet + IP-Adapter) ==="
timeout 2400 "$PY" /tmp/generate_anims_controlnet.py >>"$OUT" 2>&1 && log "anims ok" || log "anims FAILED"
log "anim frames: $(ls "$ANIMS"/*.png 2>/dev/null | wc -l)"

log "=== 3/5 option renders (units/terrain/icons) ==="
timeout 2400 "$PY" /tmp/xlite_options_batch.py >>"$OUT" 2>&1 && log "options ok" || log "options FAILED"
log "option renders: $(ls "$OPTS"/*.png 2>/dev/null | wc -l)"

log "=== 4/5 wasteland background options ==="
timeout 1200 "$PY" /tmp/xlite_scenes_batch.py >>"$OUT" 2>&1 && log "scenes ok" || log "scenes FAILED"
log "scene options: $(ls "$SCN"/bg_*opt*.png 2>/dev/null | grep -v __raw | wc -l)"

log "=== 5/5 pixelize (anims + options -> 64/48/32) ==="
timeout 600 "$PY" /tmp/pixelize3.py "$ANIMS" >>"$OUT" 2>&1 && log "pixelize anims ok" || log "pixelize anims FAILED"
timeout 600 "$PY" /tmp/pixelize3.py "$OPTS"  >>"$OUT" 2>&1 && log "pixelize options ok" || log "pixelize options FAILED"
log "=== RESULTS READY (anims_sprites3 + options_sprites3 + scenes) ==="
