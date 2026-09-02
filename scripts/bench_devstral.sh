#!/usr/bin/env bash
# Quality+speed bench of Devstral-24B on the REAL queue for a fixed window, with
# the build-gate active. ALWAYS restores the 27B on exit (trap). Reports the
# real outcome mix (pushed(tests:pass) vs reverted(build-break) vs tests:FAIL vs
# no-op) so we judge quality on real tasks, not one cherry-picked diff.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
NET=shrike-ai-network
DEV=/models/deepflash/Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf
P27=shrike-llama-dflash-35b
CAND=shrike-llama-devstral
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/bench-devstral.out
WINDOW="${1:-1800}"
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

restore_27b(){
  log "restoring 27B"
  docker rm -f "$CAND" >/dev/null 2>&1 || true
  docker start "$P27" >/dev/null 2>&1 || true
  for i in $(seq 1 60); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  sed -i 's/--edit-format diff/--edit-format udiff/' "$Q/run_overnight.sh" 2>/dev/null
  "$Q/queue.sh" resume >/dev/null 2>&1 || true
  log "27B restored: $(docker ps --filter name=$P27 --format '{{.Status}}')"
}
trap restore_27b EXIT

"$Q/queue.sh" pause >/dev/null; log "paused"
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done

log "swapping 27B -> Devstral"
docker stop "$P27" >/dev/null
for i in $(seq 1 30); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|head -1)" -lt 3000 ] && break; sleep 2; done
docker rm -f "$CAND" >/dev/null 2>&1 || true
docker run -d --gpus all --name "$CAND" --network "$NET" --network-alias llama-dflash-35b \
  -p 8081:8080 -v "$MODELS:/models" --entrypoint /bin/sh "$IMG" \
  -c "exec /app/llama-server -m $DEV --ctx-size 65536 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --host 0.0.0.0 --port 8080 --alias qwen-dflash-27B" >/dev/null
ok=0; for i in $(seq 1 75); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }; [ "$(docker inspect -f '{{.State.Running}}' $CAND 2>/dev/null)" != "true" ] && break; sleep 2; done
[ "$ok" = 1 ] || { log "Devstral failed to start:"; docker logs "$CAND" 2>&1 | tail -12 >> "$OUT"; exit 1; }
log "Devstral healthy: VRAM $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)"

# quick speed sample
R=$(curl -s -w '\nW:%{time_total}' --max-time 60 -H "Authorization: Bearer sk-shrike-local" -H 'Content-Type: application/json' -d '{"model":"qwen-dflash-27B","prompt":"Write merge_sort in Python:","max_tokens":120,"temperature":0}' http://localhost:8081/v1/completions)
W=$(echo "$R"|grep -oE 'W:[0-9.]+'|cut -d: -f2); C=$(echo "$R"|sed 's/W:.*//'|python3 -c 'import sys,json;print(json.load(sys.stdin)["usage"]["completion_tokens"])' 2>/dev/null)
[ -n "$C" ] && log "Devstral speed: $(python3 -c "print(round(${C}/${W},1))") tok/s (idle)"

# Devstral emits SEARCH/REPLACE -> diff format
sed -i 's/--edit-format udiff/--edit-format diff/' "$Q/run_overnight.sh"
START=$(date +%s)
"$Q/queue.sh" resume >/dev/null; log "queue resumed on Devstral — running ${WINDOW}s"
sleep "$WINDOW"
"$Q/queue.sh" pause >/dev/null
for i in $(seq 1 15); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done

log "=== DEVSTRAL BENCH RESULTS (window: ${WINDOW}s) ==="
for r in $(ls -t "$Q"/reports/2026*.md); do
  ts=$(basename "$r" .md); tsec=$(date -d "${ts:0:8} ${ts:9:2}:${ts:11:2}:${ts:13:2}" +%s 2>/dev/null || echo 0)
  [ "$tsec" -ge "$START" ] && grep -hE '^\| ongoing' "$r"
done 2>/dev/null | grep -oE 'pushed\(tests:pass\)|reverted\(build-break\)|pushed\(tests:FAIL[^|]*|no-op|error\([^)]*\)|held' | sort | uniq -c | sort -rn >> "$OUT"
log "=== DONE ==="
