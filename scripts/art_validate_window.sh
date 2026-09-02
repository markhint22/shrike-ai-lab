#!/usr/bin/env bash
# Small GPU window: VALIDATE the consistency rework — derive attack/downed/dead from
# 2 units' idles via img2img (gen_pose_from_idle), pixelize, QA. Cheap (6 gens) so we
# can eyeball whether the character stays consistent before a full batch. Trap-restores.
set -uo pipefail
C=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI
PY="$C/.venv/bin/python"
Q=/home/mhintermeister/overnight-queue
STATE=$Q/state
OUT=$Q/reports/art-validate.out
O=/run/media/mhintermeister/secondary_drive1/comfy/out

exec 9>/tmp/art_validate.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
restore(){ rm -f "$STATE/art_window.hold"; "$Q/queue.sh" resume >/dev/null 2>&1 || true; log "=== VALIDATE WINDOW DONE ==="; }
trap restore EXIT

mkdir -p "$STATE"; touch "$STATE/art_window.hold"
log "freeing GPU (both model containers)"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done
docker stop shrike-llama-dflash-35b shrike-llama-coder-next >/dev/null 2>&1 || true
for i in $(seq 1 40); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 2500 ] && break; sleep 2; done
log "GPU free"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
log "=== (0) draw OpenPose skeletons ==="
"$PY" /tmp/pose_skeletons.py >>"$OUT" 2>&1 && log "skeletons ok" || log "skeletons FAILED"
log "=== ControlNet+IP-Adapter pose-forced: trooper + grunt, all 3 poses ==="
timeout 1200 "$PY" /tmp/gen_pose_controlnet.py \
  player_trooper__attack player_trooper__downed player_trooper__dead \
  enemy_grunt__attack enemy_grunt__downed enemy_grunt__dead >>"$OUT" 2>&1 && log "gen ok" || log "gen FAILED"
for pose in attack downed dead; do
  timeout 200 "$PY" /tmp/pixelize3.py "$O/units_$pose" >>"$OUT" 2>&1
  log "QA $pose:"; "$PY" /tmp/art_qa_gate.py "$O/units_${pose}_sprites3" --role "$pose" 2>>"$OUT" >/dev/null || true
done
log "=== RESULTS READY ==="
