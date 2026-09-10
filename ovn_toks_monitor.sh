#!/usr/bin/env bash
# ovn_toks_monitor.sh — track the 27B's generation speed + alert on a REAL regression (not load).
#
# WHY: the model's SOLO ceiling on this 3090 is ~60 tok/s (27B Q4, flash-attn, full offload, MTP
# spec-decode — near-optimal; 200 tok/s is NOT achievable for this size on one GPU). The single-threaded
# llama-server serves ONE request at a time, so a probe sent WHILE the fleet's aider is mid-generation
# QUEUES behind it and looks slow. That is a MEASUREMENT artifact, not the fleet's work being slowed
# (the fleet is serial: one aider at a time; the stage sweep pauses the fleet). So: probe, and if the
# fleet was busy during the probe, LABEL the sample contended and do NOT treat it as the true rate or
# alert on it. Only a slow SOLO sample (no aider running) is a real config/GPU regression.
#
# Cron: 20,50 * * * *  cd ~/overnight-queue && ./ovn_toks_monitor.sh >> logs/ovn_toks_monitor.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LKEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
FLOOR="${OVN_TOKS_FLOOR:-38}"   # true (solo) tok/s below this = a real regression to investigate

_aiders(){ pgrep -c -f 'bin/aider ' 2>/dev/null || echo 0; }
best=0; solo_best=0; any_solo=0
for i in 1 2 3 4; do
  a0="$(_aiders)"
  t0=$(date +%s.%N)
  r=$(curl -fsS --max-time 25 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $LKEY" -d '{"model":"qwen-dflash-27B","messages":[{"role":"user","content":"List 30 common fruits, comma separated."}],"max_tokens":150,"temperature":0}' 2>/dev/null)
  t1=$(date +%s.%N); a1="$(_aiders)"
  tk=$(printf '%s' "$r" | jq -r '.usage.completion_tokens // 0' 2>/dev/null); tk="${tk:-0}"
  if [ "$tk" -gt 0 ]; then
    ts=$(echo "scale=1; $tk/($t1-$t0)" | bc 2>/dev/null)
    [ -n "$ts" ] && [ "$(echo "$ts > $best" | bc 2>/dev/null)" = 1 ] && best="$ts"
    # a SOLO sample = no fleet aider running before OR after the probe (it had the GPU to itself)
    if [ "${a0:-0}" -eq 0 ] && [ "${a1:-0}" -eq 0 ]; then
      any_solo=1
      [ "$(echo "$ts > $solo_best" | bc 2>/dev/null)" = 1 ] && solo_best="$ts"
    fi
  fi
  sleep 1
done
aiders="$(_aiders)"
gpu=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
# report the SOLO rate as the true rate when we got one; else mark the sample contended (rate unknown)
if [ "$any_solo" = 1 ]; then true_rate="$solo_best"; contended=false; else true_rate="$best"; contended=true; fi
echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"tok_s_best\":${best:-0},\"tok_s_solo\":${solo_best:-0},\"true_rate\":${true_rate:-0},\"contended\":${contended},\"aiders\":${aiders:-0},\"gpu\":\"${gpu:-}\"}" >> state/toks.jsonl
echo "$(date '+%F %T') best=${best} solo=${solo_best} contended=${contended} aiders=${aiders} gpu=${gpu}"

# ALERT only on a real SOLO regression — never on a contended reading (that is just load, expected + fine)
if [ "$contended" = false ]; then
  ti=${true_rate%.*}
  if [ "${ti:-0}" -gt 0 ] && [ "${ti:-0}" -lt "$FLOOR" ]; then
    if [ "$(cat state/toks_alerted 2>/dev/null)" != "$(date +%F)" ]; then
      date +%F > state/toks_alerted
      curl -fsS --max-time 8 -H "Title: 27B speed regression: ${true_rate} tok/s SOLO" -H "Tags: warning" \
        -d "The 27B's SOLO (no-contention) generation speed dropped to ${true_rate} tok/s (floor ${FLOOR}; healthy is ~60). This is a REAL regression, not load — check llama-server flags (flash-attn/ngl/spec-decode), GPU thermals/clocks, or a container restart. GPU=${gpu}." \
        "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
    fi
  fi
fi
