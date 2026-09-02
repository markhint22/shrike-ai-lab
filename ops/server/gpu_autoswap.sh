#!/usr/bin/env bash
# Auto-restore the 27B llama inference server whenever the GPU frees up, and
# record WHAT is holding the GPU whenever the 27B can't load (so a fleet-starving
# process is never a mystery).
#
# Context: the 3090 can't run both the 27B (needs ~21GB @ 65K ctx) and a ComfyUI
# art job at once, so the art side docker-stops the llama container to free VRAM.
# The container is restart=unless-stopped, so a manual stop means it will NOT come
# back on its own. This watcher brings it back the moment there's room.
#
# Idempotent. Runs every 1 min via cron. Health-checks via `docker exec` because
# the container has no host port mapping (LiteLLM reaches it over the docker net).
set -uo pipefail
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
C="shrike-llama-dflash-35b"
NEED_FREE_MIB=21000          # 27B @ 65K needs ~21GB free before it can load
STARVE_SECS=1800            # alert once if a non-27B GPU holder starves the fleet this long (30 min)
LOG="$HOME/overnight-queue/logs/gpu_autoswap.log"
STATE="$HOME/overnight-queue/state"
ts(){ date "+%F %T"; }
say(){ echo "$(ts) $*" >> "$LOG"; }
alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true; }

healthy(){ docker exec "$C" curl -sf --max-time 5 http://localhost:8080/health >/dev/null 2>&1; }

# 0. Art-window hold: an art/ComfyUI window holds the WHOLE GPU across several gen
# subprocesses. Between subprocesses the GPU briefly frees; without this guard the
# watcher restarts the 27B in that gap and the next gen OOMs. The window creates
# state/art_window.hold at start and removes it on exit (trap), then the next tick
# restores the 27B normally.
if [ -f "$STATE/art_window.hold" ]; then exit 0; fi

# 1. already running? (healthy -> done; running-but-loading -> don't thrash)
if [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null)" = "true" ]; then
  exit 0
fi

# 2. container is down. Is there room to load the model?
read used total < <(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr ',' ' ')
[ -z "${total:-}" ] && { say "no nvidia-smi reading; skip"; exit 0; }
free=$(( total - used ))
if [ "$free" -lt "$NEED_FREE_MIB" ]; then
  # --- identify the GPU holder(s) so the fleet-starving process is always logged ---
  holders="$(nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader 2>/dev/null | paste -sd';' - )"
  top_pid="$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
  top_cmd=""; top_et=""; top_secs=0
  if [ -n "${top_pid:-}" ]; then
    top_cmd="$(ps -o cmd= -p "$top_pid" 2>/dev/null | cut -c1-140)"
    top_et="$(ps -o etime= -p "$top_pid" 2>/dev/null | tr -d ' ')"
    top_secs="$(ps -o etimes= -p "$top_pid" 2>/dev/null | tr -d ' ')"
  fi
  say "llama down; GPU free=${free}MiB (<${NEED_FREE_MIB}); held by: ${holders:-unknown} | top pid=${top_pid:-?} up=${top_et:-?} cmd=${top_cmd:-?}"
  # --- one-time ntfy if a NON-27B holder has starved the fleet >= STARVE_SECS ---
  mkdir -p "$STATE"
  for f in "$STATE"/gpu_holder_alerted_*; do        # drop stale dedupe flags (pid gone)
    [ -e "$f" ] || continue; p="${f##*_}"; kill -0 "$p" 2>/dev/null || rm -f "$f"
  done
  if [ -n "${top_pid:-}" ] && ! printf '%s' "$top_cmd" | grep -q "llama-server" \
     && [ "${top_secs:-0}" -ge "$STARVE_SECS" ] && [ ! -f "$STATE/gpu_holder_alerted_$top_pid" ]; then
    touch "$STATE/gpu_holder_alerted_$top_pid"
    alert "GPU held ${top_et} — 27B fleet paused" "warning" \
      "A non-27B process has held the GPU for ${top_et} (pid ${top_pid}), so the code fleet is paused: ${top_cmd}. It resumes automatically when this frees. If unexpected, check it."
  fi
  exit 0
fi

# 3. free enough + down -> restore. Clear any half-created duplicate first.
dup=$(docker ps -aq -f name=dflash -f status=created 2>/dev/null)
[ -n "$dup" ] && { docker rm -f $dup >/dev/null 2>&1 || true; say "removed stuck Created dup(s): $dup"; }
say "GPU free=${free}MiB — starting $C"
docker start "$C" >/dev/null 2>&1
for i in $(seq 1 24); do
  sleep 5
  if healthy; then
    say "RESTORED: llama healthy after $((i*5))s"
    alert "27B restored (auto-swap)" "white_check_mark" "GPU freed (${free}MiB); llama-server back up. Overnight fleet resumes."
    exit 0
  fi
done
say "FAILED: llama did not health-check within 120s"
alert "27B auto-restart FAILED" "rotating_light" "GPU free=${free}MiB but llama did not become healthy in 2min. Run: docker start $C ; docker logs $C"
exit 1
