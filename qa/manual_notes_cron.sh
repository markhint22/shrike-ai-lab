#!/usr/bin/env bash
# manual_notes_cron.sh - cron-safe wrapper for `manual_notes_ingest.py sweep` (box side).
#   */10 * * * * NTFY_SERVER=http://127.0.0.1:8099 $HOME/overnight-queue/qa/manual_notes_cron.sh >> $HOME/overnight-queue/logs/manual_notes.log 2>&1
# Cron-safety (past incidents): our own directory is resolved BEFORE any cd (cron may call us by a relative path), PATH is set
# explicitly, one sweep at a time (flock -n; mkdir lock fallback where flock is missing), a hard timeout, and ALWAYS exit 0.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
log(){ echo "$(date '+%F %T') manual_notes_cron: $*"; }
mkdir -p "$OVN_DIR/state" "$OVN_DIR/logs" 2>/dev/null
[ "${OVN_MANUAL_SWEEP:-on}" = "off" ] && { log "disabled (OVN_MANUAL_SWEEP=off)"; exit 0; }
PY="$(command -v python3.12 || command -v python3)"
[ -n "$PY" ] || { log "no python3 on PATH"; exit 0; }
cd "$OVN_DIR" 2>/dev/null || { log "cannot cd to $OVN_DIR"; exit 0; }
if command -v flock >/dev/null 2>&1; then
  exec 9>"$OVN_DIR/state/manual_notes_cron.lock"
  flock -n 9 || { log "previous sweep still running, skipping"; exit 0; }
else
  LD="$OVN_DIR/state/manual_notes_cron.lock.d"
  if ! mkdir "$LD" 2>/dev/null; then
    if [ -n "$(find "$LD" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then rmdir "$LD" 2>/dev/null; mkdir "$LD" 2>/dev/null || exit 0
    else log "previous sweep still running, skipping"; exit 0; fi
  fi
  trap 'rmdir "$LD" 2>/dev/null' EXIT
fi
if [ -f "$HERE/qa_timeout.py" ]; then
  "$PY" "$HERE/qa_timeout.py" "${OVN_MANUAL_SWEEP_TIMEOUT:-600}" "$PY" "$HERE/manual_notes_ingest.py" sweep
else
  "$PY" "$HERE/manual_notes_ingest.py" sweep
fi
rc=$?
[ "$rc" -eq 0 ] || log "sweep exited rc=$rc (ignored)"
exit 0
