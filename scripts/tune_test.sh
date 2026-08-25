#!/usr/bin/env bash
# Disconnect-safe context/spec tuning A/B on the current Qwen3.8-27B.
# ALWAYS restores production on exit (trap), even if the caller's SSH dies.
# Tests: baseline (prod) -> tuned MTP (64k) -> tuned + DFlash2 drafter.
set -uo pipefail
MODELS=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models
IMG=ghcr.io/ggml-org/llama.cpp:server-cuda
KEY=sk-shrike-local
PROD=shrike-llama-dflash-35b
BASE_M=/models/deepflash/Qwen3.8-27B-Q4_K_M.gguf
TMPL=/models/deepflash/fixed_template_qwen3.8.jinja
DF2=/models/deepflash/Qwen3.8-27B-DFlash2-Q8_0.gguf
OUT=/home/mhintermeister/overnight-queue/reports/tune-test.out
: > "$OUT"

restore() { docker rm -f tune-test >/dev/null 2>&1 || true
  docker start "$PROD" >/dev/null 2>&1 || true
  for i in $(seq 1 90); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  echo "[restore] production: $(docker ps --filter name=$PROD --format '{{.Status}}')" >> "$OUT"; }
trap restore EXIT

meas() { # $1=url -> best tok/s over 2 tries (skips failed/0-token)
  local base="$1" best=0 i r w c ts
  for i in 1 2; do
    r=$(curl -s -w '\nWALL:%{time_total}' --max-time 120 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
      -d '{"model":"qwen-dflash-27B","prompt":"Write a Python function merge_sort(arr) with a helper and comments.","max_tokens":160,"temperature":0}' "$base/v1/completions")
    w=$(echo "$r" | grep -oE 'WALL:[0-9.]+' | cut -d: -f2)
    c=$(echo "$r" | sed 's/WALL:.*//' | python3 -c 'import sys,json;print(json.load(sys.stdin)["usage"]["completion_tokens"])' 2>/dev/null || echo 0)
    [ "${c:-0}" -gt 0 ] && ts=$(python3 -c "print(round(${c}/${w},1))" 2>/dev/null) || ts=0
    [ "$(python3 -c "print(1 if ${ts:-0}>${best} else 0)")" = 1 ] && best=$ts
  done
  echo "$best"
}
gpu_used() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1; }
launch() { # $1=extra llama-server args ; starts tune-test on 8081 (no --rm so logs survive)
  # NO -ngl / --mlock: let llama.cpp auto-fit layers to VRAM exactly like prod does
  # (this hybrid 27B's ~10GB rs-cache means it can't fully fit on 24GB — forcing
  # full offload OOMs). Smaller ctx just lets auto-fit keep MORE layers on GPU.
  docker rm -f tune-test >/dev/null 2>&1 || true
  docker run -d --gpus all --name tune-test -p 8081:8080 -v "$MODELS:/models" --entrypoint /bin/sh "$IMG" \
    -c "exec /app/llama-server -m $BASE_M --ctx-size 65536 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --no-context-shift --host 0.0.0.0 --port 8080 --alias qwen-dflash-27B --chat-template-file $TMPL $1" >/dev/null
  for i in $(seq 1 60); do
    curl -sf http://localhost:8081/health >/dev/null 2>&1 && return 0
    [ "$(docker inspect -f '{{.State.Running}}' tune-test 2>/dev/null)" != "true" ] && return 1   # crashed — bail fast
    sleep 2
  done
  return 1
}

for i in $(seq 1 8); do fuser /home/mhintermeister/overnight-queue/state/run.lock >/dev/null 2>&1 || break; sleep 8; done
echo "=== BASELINE (prod: 262144 ctx, MTP n-max 4) via litellm ===" >> "$OUT"
echo "  $(meas http://localhost:4000) tok/s" >> "$OUT"

echo "=== stopping prod + waiting for GPU to free ===" >> "$OUT"
docker stop "$PROD" >/dev/null
for i in $(seq 1 30); do u=$(gpu_used); echo "  gpu used=${u}MiB" >> "$OUT"; [ "${u:-99999}" -lt 3000 ] && break; sleep 2; done

echo "=== TUNED-A: 64k ctx + MTP n-max 16 p-min 0.8 + ngram-cache ===" >> "$OUT"
if launch '--spec-type draft-mtp,ngram-cache --spec-draft-n-max 16 --spec-draft-p-min 0.8'; then
  sleep 3; echo "  $(meas http://localhost:8081) tok/s | VRAM $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)" >> "$OUT"
else
  echo "  FAILED to start — logs:" >> "$OUT"; docker logs tune-test 2>&1 | tail -15 >> "$OUT"
fi
docker rm -f tune-test >/dev/null 2>&1 || true
for i in $(seq 1 20); do [ "$(gpu_used)" -lt 3000 ] && break; sleep 2; done

echo "=== TUNED-B: 64k ctx + DFlash2 external drafter (n-max 16 p-min 0.8) ===" >> "$OUT"
if [ -f "$MODELS/deepflash/Qwen3.8-27B-DFlash2-Q8_0.gguf" ]; then
  if launch "--spec-type draft-dflash -md $DF2 --spec-draft-n-max 16 --spec-draft-p-min 0.8 --spec-draft-type-k q8_0 --spec-draft-type-v q8_0"; then
    sleep 3; echo "  $(meas http://localhost:8081) tok/s | VRAM $(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader)" >> "$OUT"
  else
    echo "  FAILED to start — logs:" >> "$OUT"; docker logs tune-test 2>&1 | tail -15 >> "$OUT"
  fi
  docker rm -f tune-test >/dev/null 2>&1 || true
else
  echo "  (DFlash2 drafter not downloaded yet — skipped)" >> "$OUT"
fi
echo "=== DONE ===" >> "$OUT"
