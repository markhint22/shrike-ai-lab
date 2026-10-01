#!/usr/bin/env bash
# qa_ledger_cron.sh - cron-safe wrapper for the S12 ledger derivation (qa_ledger.py derive).
# Suggested cron (box):  23 * * * * NTFY_SERVER=... $HOME/overnight-queue/qa/qa_ledger_cron.sh >/dev/null 2>&1
# Safe by construction: resolves its own path BEFORE cd, minimal PATH, single instance (flock -n, mkdir fallback),
# never takes run.lock, never touches a repo, never pushes/notifies, ALWAYS exits 0 (a broken ledger must not become a cron alert).
set -u
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || exit 0
cd "$HERE" || exit 0
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"; export OVN_DIR
STATE="$OVN_DIR/state"; LOGD="$OVN_DIR/logs"
mkdir -p "$STATE" "$LOGD" 2>/dev/null || exit 0
LOG="$LOGD/qa_ledger_cron.log"
say(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
PY=python3; command -v python3.12 >/dev/null 2>&1 && PY=python3.12
command -v "$PY" >/dev/null 2>&1 || { say "no python3 - skipped"; exit 0; }
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 600"; command -v gtimeout >/dev/null 2>&1 && [ -z "$TO" ] && TO="gtimeout 600"

LOCK="$STATE/qa_ledger.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" || exit 0
  flock -n 9 || { say "another ledger pass holds the lock - skipped"; exit 0; }
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    # stale-lock guard: a lock dir older than 30 min is a crashed run
    if [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
      rmdir "$LOCK.d" 2>/dev/null; mkdir "$LOCK.d" 2>/dev/null || exit 0
    else
      say "another ledger pass holds the lock - skipped"; exit 0
    fi
  fi
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi

OUT="$($TO nice -n 15 "$PY" "$HERE/qa_ledger.py" derive --no-record 2>&1 | tail -n 1)"
say "derive ${OUT:0:300}"
exit 0
