#!/usr/bin/env bash
# GPU window: generate reference-briefed DEAD sprites (one per unit) -> pixelize
# (alpha key). Restores llama + queue on exit (trap). flock-guarded. Mirrors
# clean_idle_window.sh. The dead sprites are the fix for "the dead alien looks
# like a live green blob tipped over" — a distinct flattened, ichor-pooled corpse.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/dead-sprites.out
DEAD=/run/media/mhintermeister/secondary_drive1/comfy/out/units_dead

exec 9>/tmp/dead_sprites.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== DEAD SPRITE WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== 1/2 generate dead sprites (from reference briefs) ==="
timeout 1200 "$PY" /tmp/gen_from_brief.py --dead-all >>"$OUT" 2>&1 && log "gen ok" || log "gen FAILED"
log "=== 2/2 pixelize (alpha key) ==="
timeout 300 "$PY" /tmp/pixelize3.py "$DEAD" >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "dead frames: $(ls ${DEAD}_sprites3/*__dead@64.png 2>/dev/null | wc -l)"
log "=== RESULTS READY (${DEAD}_sprites3) ==="
