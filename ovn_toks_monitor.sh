#!/usr/bin/env bash
# ovn_toks_monitor.sh — track the 27B's generation speed + alert on a SUSTAINED regression.
#
# 2026-09-26 REDESIGN: the original design tried to isolate a genuinely uncontended ("solo",
# no fleet aider running immediately before OR after the probe) sample and only alert on THAT,
# reasoning that a contended reading is just normal load, not a real regression. In practice
# that precondition is essentially unreachable: the fleet runs continuously by design (one
# aider active most of the time), so tok_s_solo was 0 (no valid solo sample ever obtained) in
# EVERY SINGLE reading across 3+ weeks of history (1346 samples, 2026-09-08 through
# 2026-09-26) - the regression-alert path had literally never once been exercised in its
# entire life. Confirmed directly the same day: forcibly pausing the fleet to get a genuine
# idle window and re-measuring got 34-45 tok/s, matching this same history's best= readings
# almost exactly (mean 35.9, max 47.1 across all 897 valid readings) - there was never a real
# regression to catch, just a design that could never have caught one either way.
#
# NEW APPROACH: don't require an elusive clean sample. Compare the CURRENT probe against a
# trailing historical baseline (median of the last BASELINE_DAYS of best= readings, which this
# script already successfully collects on every single run regardless of contention) and only
# alert if SUSTAINED (the last ROLLING_WINDOW readings, not just one) fall below
# REGRESSION_RATIO of that baseline - a single slow contended reading is expected noise;
# several in a row well below the established historical range is the actual signal worth
# waking a human for. Falls back to the old fixed FLOOR during the bootstrap period (not
# enough history yet to trust a computed baseline).
#
# Cron: 20,50 * * * *  cd ~/overnight-queue && ./ovn_toks_monitor.sh >> logs/ovn_toks_monitor.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LKEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
FLOOR="${OVN_TOKS_FLOOR:-20}"                          # fallback absolute floor while history is thin
BASELINE_DAYS="${OVN_TOKS_BASELINE_DAYS:-14}"          # trailing window for the historical baseline
BASELINE_MIN_SAMPLES="${OVN_TOKS_BASELINE_MIN:-20}"    # need at least this many readings to trust a computed baseline
ROLLING_WINDOW="${OVN_TOKS_ROLLING_WINDOW:-6}"         # consecutive readings required (~3h at 30min cadence)
REGRESSION_RATIO="${OVN_TOKS_REGRESSION_RATIO:-0.5}"   # alert only if ALL of the last N readings are below baseline*ratio
ROLLING_FILE="state/toks_rolling.txt"

# respect a manual/GPU-testing pause — this script actively probes the local model (real
# GPU/inference load, by design) and should not compete with a dedicated debugging session.
if [ -f state/PAUSED ]; then
  echo "$(date '+%F %T') queue is paused (state/PAUSED exists) — skipping this probe entirely" >&2
  exit 0
fi

_aiders(){ pgrep -c -f 'bin/aider ' 2>/dev/null || echo 0; }
best=0
for i in 1 2 3 4; do
  t0=$(date +%s.%N)
  r=$(curl -fsS --max-time 25 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $LKEY" -d '{"model":"qwen-dflash-27B","messages":[{"role":"user","content":"List 30 common fruits, comma separated."}],"max_tokens":150,"temperature":0}' 2>/dev/null)
  t1=$(date +%s.%N)
  tk=$(printf '%s' "$r" | jq -r '.usage.completion_tokens // 0' 2>/dev/null); tk="${tk:-0}"
  if [ "$tk" -gt 0 ]; then
    ts=$(echo "scale=1; $tk/($t1-$t0)" | bc 2>/dev/null)
    [ -n "$ts" ] && [ "$(echo "$ts > $best" | bc 2>/dev/null)" = 1 ] && best="$ts"
  fi
  sleep 1
done
aiders="$(_aiders)"
gpu=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
now_ts="$(date -u +%FT%TZ)"
mkdir -p state
echo "{\"ts\":\"$now_ts\",\"tok_s_best\":${best:-0},\"aiders\":${aiders:-0},\"gpu\":\"${gpu:-}\"}" >> state/toks.jsonl
echo "$(date '+%F %T') best=${best} aiders=${aiders} gpu=${gpu}"

# A failed/zero probe has nothing to compare or feed into the rolling window.
best_int="${best%.*}"; [ -n "$best_int" ] || best_int=0
if [ "$best_int" -gt 0 ] 2>/dev/null; then
  # rolling window: append this reading, keep only the last ROLLING_WINDOW lines.
  { [ -f "$ROLLING_FILE" ] && tail -n "$((ROLLING_WINDOW - 1))" "$ROLLING_FILE"; echo "$best"; } > "${ROLLING_FILE}.new"
  mv "${ROLLING_FILE}.new" "$ROLLING_FILE"
  n_readings=$(wc -l < "$ROLLING_FILE" | tr -d ' ')

  baseline="$(FLOOR="$FLOOR" BASELINE_DAYS="$BASELINE_DAYS" BASELINE_MIN_SAMPLES="$BASELINE_MIN_SAMPLES" python3 -c "
import json, os
from datetime import datetime, timedelta, timezone
cutoff = datetime.now(timezone.utc) - timedelta(days=int(os.environ['BASELINE_DAYS']))
vals = []
try:
    with open('state/toks.jsonl') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            ts = d.get('ts')
            if not ts:
                continue
            try:
                t = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            except Exception:
                continue
            if t < cutoff:
                continue
            v = d.get('tok_s_best', 0)
            if v and v > 0:
                vals.append(float(v))
except FileNotFoundError:
    pass
if len(vals) < int(os.environ['BASELINE_MIN_SAMPLES']):
    print(os.environ['FLOOR'])  # not enough history yet - fall back to the fixed floor
else:
    vals.sort()
    print(vals[len(vals)//2])
")"

  if [ "${n_readings:-0}" -ge "$ROLLING_WINDOW" ] && [ "$(echo "${baseline:-0} > 0" | bc 2>/dev/null)" = 1 ]; then
    threshold="$(echo "scale=1; $baseline * $REGRESSION_RATIO" | bc 2>/dev/null)"
    all_below=1
    while read -r v; do
      [ -n "$v" ] || continue
      [ "$(echo "$v < $threshold" | bc 2>/dev/null)" = 1 ] || { all_below=0; break; }
    done < "$ROLLING_FILE"
    if [ "$all_below" = 1 ]; then
      if [ "$(cat state/toks_alerted 2>/dev/null)" != "$(date +%F)" ]; then
        date +%F > state/toks_alerted
        curl -fsS --max-time 8 -H "Title: 27B speed regression: ${best} tok/s (baseline ${baseline})" -H "Tags: warning" \
          -d "The last ${ROLLING_WINDOW} generation-speed probes were ALL below ${threshold} tok/s (${REGRESSION_RATIO}x the ${BASELINE_DAYS}-day median of ${baseline}) - sustained, not a one-off contended blip. Check llama-server flags (flash-attn/ngl/spec-decode), GPU thermals/clocks, or try a container restart. Latest: ${best} tok/s, aiders=${aiders}, GPU=${gpu}." \
          "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
      fi
    else
      rm -f state/toks_alerted 2>/dev/null   # recovered - allow a future regression to alert again today too
    fi
  fi
fi
