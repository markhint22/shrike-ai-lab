#!/usr/bin/env bash
# GPU window: run the CHARACTER sub-flow of the art pipeline for DEAD (side-lying
# canon, redo) + DOWNED (new state), each through gen -> pixelize -> QA auto-reject
# -> re-roll (art_pipeline_run.py). Restores llama + queue on exit (trap).
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/art-characters.out

exec 9>/tmp/art_char.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== ART CHARACTER WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== DEAD (side-lying, QA-gated) ==="
timeout 2400 "$PY" /tmp/art_pipeline_run.py --role dead --passes 3 >>"$OUT" 2>&1 && log "dead ok" || log "dead FAILED"
log "=== DOWNED (new, QA-gated) ==="
timeout 2400 "$PY" /tmp/art_pipeline_run.py --role downed --passes 3 >>"$OUT" 2>&1 && log "downed ok" || log "downed FAILED"
log "dead frames: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/units_dead_sprites3/*__dead@64.png 2>/dev/null | wc -l)"
log "downed frames: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/units_downed_sprites3/*__downed@64.png 2>/dev/null | wc -l)"
log "=== RESULTS READY ==="
