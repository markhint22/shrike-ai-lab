#!/usr/bin/env bash
# ovn_gpu_util_check.sh — sample GPU utilization (cron-friendly, local only, no network).
# 2026-10-03 (Phase 6 observability): the diagnosis measured 17 of 23 overnight GPU samples under
# 5% (xlite VERIFY hangs idling the GPU for ~45 min per cycle) and nothing reported it. Run every
# ~15 min from cron:
#   */15 * * * * cd $HOME/overnight-queue && scripts/ovn_gpu_util_check.sh >> logs/gpu_util_check.log 2>&1
#
# Appends "<epoch> <util_pct> <mem_used_mib>" to state/gpu_util.log (trimmed to the last 14 days),
# then asks ovn_stats.py --gpu-alert to evaluate the 24h busy percentage: one deduped (6h) alerts.log
# line when it is under 40% while any lane is enabled. ovn_stats.py also prints the 24h busy%% in
# its digest/report output.
#
# Pure observability: never blocks anything, never touches the network, always exits 0. If
# nvidia-smi is absent/failing no sample is written (a missing sample is not "0% busy").
# Env: OVN_STATE_DIR (default ./state), OVN_NVIDIA_SMI (default nvidia-smi; test seam).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${OVN_STATE_DIR:-$DIR/state}"
SMI="${OVN_NVIDIA_SMI:-nvidia-smi}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
export OVN_STATE_DIR="$STATE_DIR"

out="$("$SMI" --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)" || out=""
util="$(printf '%s' "$out" | cut -d, -f1 | tr -d ' %')"
mem="$(printf '%s' "$out" | cut -d, -f2 | tr -d ' ')"
case "$util" in
  ''|*[!0-9]*) echo "$(date '+%F %T') no usable GPU sample (nvidia-smi: '${out:-empty}')"; exit 0;;
esac
LOG="$STATE_DIR/gpu_util.log"
echo "$(date +%s) $util ${mem:-0}" >> "$LOG"

# bound the file: keep 14 days
cutoff=$(( $(date +%s) - 14*86400 ))
awk -v c="$cutoff" '$1 >= c' "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"

python3 "$DIR/scripts/ovn_stats.py" --gpu-alert 2>/dev/null
exit 0
