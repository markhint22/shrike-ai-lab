#!/usr/bin/env bash
# Maintenance window: re-roll the 4 melee-alien attack frames (claw/punch, no gun),
# pixelize, restore prod. Trap-safe, flock-guarded.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
LLAMA=shrike-llama-dflash-35b
OUT=$Q/reports/xlite-melee.out
exec 9>/tmp/melee_window.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){
  docker start "$LLAMA" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "prod restored"; log "=== MELEE WINDOW DONE ==="
}
trap restore EXIT
log "pausing queue + freeing GPU"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop "$LLAMA" >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "=== generating melee attacks ==="
timeout 900 "$PY" /tmp/generate_melee_attacks.py >>"$OUT" 2>&1 && log "gen ok" || log "gen FAILED"
log "=== pixelizing ==="
timeout 200 "$PY" /tmp/pixelize3.py /run/media/mhintermeister/secondary_drive1/comfy/out/melee >>"$OUT" 2>&1 && log "pixelize ok" || log "pixelize FAILED"
log "outputs: $(ls /run/media/mhintermeister/secondary_drive1/comfy/out/melee_sprites3/*@48.png 2>/dev/null | wc -l)"
log "=== RESULTS READY ==="
