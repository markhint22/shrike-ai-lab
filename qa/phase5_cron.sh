#!/usr/bin/env bash
# phase5_cron.sh - cron-safe wrapper for the Phase 5 SHADOW observers: wip_cap.py run (WIP-cap log + alert) then gpu_ledger.py run (GPU-seconds ledger + weekly table).
# Suggested cron (box, hourly, AFTER the :23 ledger derive):  41 * * * * $HOME/overnight-queue/qa/phase5_cron.sh >> $HOME/overnight-queue/logs/phase5_cron.out 2>&1
# Same safety as qa_ledger_cron.sh: resolves its own path before cd, minimal PATH, single instance (flock -n, mkdir fallback), never takes run.lock, never touches a repo
# for writing, never pushes/notifies, ALWAYS exits 0. Each observer honours its own flag (OVN_QA_WIP_CAP, OVN_QA_GPU_LEDGER; off = it does nothing).
# The manifest and the rollback drill are NOT run from cron here (they are operator-run until the promote patch is adopted: qa/patches/promote_manifest.md).
set -u
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || exit 0
cd "$HERE" || exit 0
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"; export OVN_DIR
STATE="$OVN_DIR/state"; LOGD="$OVN_DIR/logs"
mkdir -p "$STATE" "$LOGD" 2>/dev/null || exit 0
LOG="$LOGD/phase5_cron.log"
say(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
PY=python3; command -v python3.12 >/dev/null 2>&1 && PY=python3.12
command -v "$PY" >/dev/null 2>&1 || { say "no python3 - skipped"; exit 0; }
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 600"; command -v gtimeout >/dev/null 2>&1 && [ -z "$TO" ] && TO="gtimeout 600"

LOCK="$STATE/phase5.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" || exit 0
  flock -n 9 || { say "another phase5 pass holds the lock - skipped"; exit 0; }
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    if [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
      rmdir "$LOCK.d" 2>/dev/null; mkdir "$LOCK.d" 2>/dev/null || exit 0
    else
      say "another phase5 pass holds the lock - skipped"; exit 0
    fi
  fi
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi

OUT="$($TO nice -n 15 "$PY" "$HERE/wip_cap.py" run 2>&1 | tail -n 1)"
say "wip_cap ${OUT:0:300}"
OUT="$($TO nice -n 15 "$PY" "$HERE/gpu_ledger.py" run 2>&1 | tail -n 1)"
say "gpu_ledger ${OUT:0:300}"
exit 0
