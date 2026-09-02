#!/usr/bin/env bash
# Idempotent recovery to the known-good gated-27B baseline after the racing-bench
# incident. flock-guarded so it runs exactly once no matter how many times it is
# launched. Kills all bench processes, removes the coder container, ensures the
# 27B is serving on 8081, sets edit-format back to udiff, resumes the queue.
set -uo pipefail
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/recover.out
P27=shrike-llama-dflash-35b
exec 9>/tmp/recover_to_27b.lock
if ! flock -n 9; then echo "already running" ; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

log "killing all bench processes"
pkill -9 -f bench_coder_gate 2>/dev/null || true
pkill -9 -f bench_devstral 2>/dev/null || true
pkill -9 -f "sleep 1500" 2>/dev/null || true
pkill -9 -f "sleep 1800" 2>/dev/null || true
sleep 2
log "remaining bench procs: $(pgrep -f 'bench_coder\|bench_devstral' | wc -l)"

log "pausing queue + waiting for lock"
"$Q/queue.sh" pause >/dev/null 2>&1 || true
for i in $(seq 1 15); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 4; done

log "removing coder candidate container"
docker rm -f shrike-llama-coder >/dev/null 2>&1 || true
docker rm -f shrike-llama-devstral >/dev/null 2>&1 || true

# handle both possible 27B names (apply_coder renamed it to -rollback if it ran)
if ! docker inspect "$P27" >/dev/null 2>&1; then
  if docker inspect shrike-llama-27b-rollback >/dev/null 2>&1; then
    docker rename shrike-llama-27b-rollback "$P27" 2>/dev/null || true
    log "renamed rollback container -> $P27"
  fi
fi

log "starting 27B"
docker start "$P27" >/dev/null 2>&1 || true
ok=0
for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && { ok=1; break; }; sleep 2; done
log "27B health: ok=$ok status=$(docker ps --filter name=$P27 --format '{{.Status}}')"

log "edit-format -> udiff"
sed -i 's/--edit-format diff/--edit-format udiff/' "$Q/run_overnight.sh" 2>/dev/null || true

log "resuming queue"
"$Q/queue.sh" resume >/dev/null 2>&1 || true
log "containers: $(docker ps --filter name=shrike-llama --format '{{.Names}}:{{.Status}}' | tr '\n' ' ')"
log "gpu: $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | head -1)"
log "=== RECOVER DONE ==="
