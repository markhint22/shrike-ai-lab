#!/usr/bin/env bash
# qa_run_shadow.sh <repo> <base_ref> <head_ref> - run every installed QA gate in SHADOW over a merged range.
# Called (detached, in the background) by branch_hygiene.sh after a successful merge into develop, and by the nightly QA cron.
# Contract: ALWAYS exits 0, never blocks or alters anything, never takes run.lock / a verify lock. Gates record their own verdicts to
# state/qa_shadow/<gate>.jsonl (qa_common). One shadow run at a time (global flock) so QA never competes with itself.
#
# Cron-safety (past incidents): our own directory is resolved BEFORE any cd (cron runs relative paths); minimal PATH is extended
# explicitly; every gate has a hard timeout; a missing gate/tool is simply skipped (the gate itself reports UNVERIFIED).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="$HOME/qa-venv/bin:$HOME/qa-tools/bin:$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
repo="${1:-}"; base="${2:-}"; head="${3:-}"
LOG="$OVN_DIR/logs/qa_shadow.log"; mkdir -p "$OVN_DIR/logs" "$OVN_DIR/state" 2>/dev/null
log(){ echo "$(date '+%F %T') [qa_shadow $repo ${base:0:8}..${head:0:8}] $*" >> "$LOG" 2>/dev/null; }
[ -n "$repo" ] && [ -n "$base" ] && [ -n "$head" ] || { echo "usage: qa_run_shadow.sh <repo> <base_ref> <head_ref>" >&2; exit 0; }
[ "${OVN_QA_SHADOW:-on}" = "off" ] && { log "disabled (OVN_QA_SHADOW=off)"; exit 0; }
PY="$(command -v python3.12 || command -v python3)"
if [ -z "${QA_CPUSET+x}" ] && [ "$(nproc 2>/dev/null || echo 0)" -ge 12 ]; then export QA_CPUSET="10-15"; fi   # QA capped at 6 of 16 threads
# one shadow run at a time. flock where it exists (the box); a mkdir lock with 2h stale takeover where it does not (macOS has no flock).
LW="${QA_LOCK_WAIT:-1800}"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$OVN_DIR/state/qa_shadow.lock"
  if ! flock -w "$LW" 9; then log "another shadow run held the lock >${LW}s - skipping"; exit 0; fi
else
  LD="$OVN_DIR/state/qa_shadow.lock.d"; waited=0
  while ! mkdir "$LD" 2>/dev/null; do
    if [ -n "$(find "$LD" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rmdir "$LD" 2>/dev/null; continue; fi
    [ "$waited" -ge "$LW" ] && { log "another shadow run held the lock >${LW}s - skipping"; exit 0; }
    sleep 1; waited=$((waited+1))
  done
  trap 'rmdir "$LD" 2>/dev/null' EXIT
fi
T="${QA_GATE_TIMEOUT:-900}"
export QA_GATE_TIMEOUT="$T"   # gates derive their own time budget from it (must stay under it so they can answer + clean up)
ran=0
# 2026-10-02: a gate that only applies to some repos must not run (and log an NA row) for the others. gate_migrations starts a postgres
# container, so it runs only for repos registered in qa_repos.json (those with an alembic backend). Fail OPEN: an unreadable registry
# runs the gate, which then reports UNVERIFIED itself. Other gates apply to every repo.
applies(){ # $1 = gate name
  case "$1" in
    migrations) "$PY" -c 'import json,sys
try: sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])) else 1)
except Exception: sys.exit(0)' "${QA_REPOS_JSON:-$HERE/qa_repos.json}" "$repo" 2>/dev/null ;;
    *) return 0 ;;
  esac
}
for g in "$HERE"/gate_*.py; do
  [ -f "$g" ] || continue
  name="$(basename "$g" .py)"; name="${name#gate_}"
  [ "${OVN_QA_MODE_ALL:-}" = "off" ] && continue
  applies "$name" || { log "$name: skipped (repo has no applicable target)"; continue; }
  t0=$(date +%s)
  out="$("$PY" "$HERE/qa_timeout.py" "$T" "$PY" "$g" check --repo "$repo" --base "$base" --head "$head" 2>>"$LOG" | tail -1)"; rc=$?
  v="$(printf '%s' "$out" | "$PY" -c 'import sys,json
try: print(json.loads(sys.stdin.read()).get("verdict","?"))
except Exception: print("NO-OUTPUT")' 2>/dev/null)"
  log "$name: ${v:-NO-OUTPUT} rc=$rc $(( $(date +%s) - t0 ))s"
  ran=$((ran+1))
done
log "done ($ran gate(s))"
exit 0
