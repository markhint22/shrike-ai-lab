#!/usr/bin/env bash
# GPU window for the AnimateDiff spike. Restores llama + queue on exit (trap).
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/animatediff.out
AD=/run/media/mhintermeister/secondary_drive1/comfy/out/animatediff

exec 9>/tmp/animatediff.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  log "restoring llama + queue"
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "=== ANIMATEDIFF WINDOW DONE ==="
}
trap restore EXIT

log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

log "=== animatediff spike (may download the motion adapter first) ==="
timeout 1800 "$PY" /tmp/animatediff_test.py >>"$OUT" 2>&1 && log "animatediff ok" || log "animatediff FAILED (see log)"
log "frames: $(ls "$AD"/walk_*.png 2>/dev/null | wc -l)  gif: $(ls "$AD"/*.gif 2>/dev/null | wc -l)"
log "=== RESULTS READY ($AD) ==="
