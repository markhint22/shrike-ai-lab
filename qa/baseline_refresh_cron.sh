#!/usr/bin/env bash
# baseline_refresh_cron.sh - BOX: refresh each python/pytest repo's CLEAN-BASE red-test set for baseline-relative verify (gate S4, SHADOW).
# 2026-10-02. For every repo it runs `baseline_verify.py refresh --ref origin/develop`: the repo's own .venv pytest over a DETACHED worktree of
# origin/develop (qa_common.worktree, removed afterwards), then the lib's snapshot rules decide whether the set is stored:
#   * deterministic only (a COMPLETE pytest parse, no hard failures; timeouts/truncation => nothing written, old baseline untouched),
#   * 24h expiry (a stale baseline reads as missing at compare time), never auto-widen (growth => growth_pending + alert, needs --accept-growth),
#   * refuses a mostly-red suite (> OVN_QA_BASELINE_MAX ids).
# Why origin/develop and not the live clone / overnight/feature: develop only ever receives gated-green merges, so its red set is what a change
# started from; a red that exists only on overnight/feature is conservatively NEW until it reaches develop.
# Hard rules (spec): never the live clone's working tree (detached worktree only), never run.lock or any per-repo verify lock (only its own
# small lock), CPU-polite (nice + ionice + QA_CPUSET like qa_run_shadow.sh), bounded per repo and in total, no network (a missing origin/develop
# ref is reported UNVERIFIED, never fetched here), ALWAYS exits 0, nothing is written outside state/qa_baselines + state/qa_shadow + logs.
# Cron (NOT installed; see qa/baseline_refresh_cron.txt):
#   11 */3 * * *  NTFY_SERVER=http://127.0.0.1:8099 $HOME/overnight-queue/qa/baseline_refresh_cron.sh >> $HOME/overnight-queue/logs/baseline_refresh.out 2>&1
# Kill switches: OVN_BASELINE_REFRESH=off | OVN_BASELINE_SHADOW=off | qa mode `baseline` = off.  Tunables: OVN_BASELINE_REFRESH_REPOS, OVN_BASELINE_REF,
# OVN_BASELINE_REPO_TIMEOUT (default 900, one suite), OVN_BASELINE_BUDGET (default 3300 total).
set -u
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac          # resolve our own path BEFORE any cd (cron may call a relative path)
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || exit 0
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="$HOME/qa-venv/bin:$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export PYTHONDONTWRITEBYTECODE=1
STATE="$OVN_DIR/state"; LOGD="$OVN_DIR/logs"; LOG="$LOGD/baseline_refresh.log"
mkdir -p "$STATE" "$LOGD" 2>/dev/null || exit 0
log(){ echo "$(date '+%F %T') baseline_refresh: $*" >> "$LOG" 2>/dev/null; }
[ "${OVN_BASELINE_REFRESH:-on}" = off ] && { log "disabled (OVN_BASELINE_REFRESH=off)"; exit 0; }
[ "${OVN_BASELINE_SHADOW:-on}" = off ] && { log "disabled (OVN_BASELINE_SHADOW=off)"; exit 0; }
PY="$(command -v python3.12 || command -v python3)"
[ -n "$PY" ] || { log "no python3 - skipped"; exit 0; }
[ -f "$HERE/baseline_verify.py" ] && [ -f "$HERE/qa_timeout.py" ] || { log "baseline_verify.py/qa_timeout.py missing - skipped"; exit 0; }
[ "$("$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import qa_common as q; print(q.mode("baseline"))' "$HERE" 2>/dev/null)" = off ] && { log "disabled (qa mode baseline=off)"; exit 0; }
if [ -z "${QA_CPUSET+x}" ] && [ "$(nproc 2>/dev/null || echo 0)" -ge 12 ]; then export QA_CPUSET="10-15"; fi   # QA capped at 6 of 16 threads

# OUR OWN lock only (never run.lock / a verify lock): one refresh pass at a time. flock on the box; mkdir lock with 2h stale takeover elsewhere.
LOCK="$STATE/baseline_refresh.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" || exit 0
  flock -n 9 || { log "previous refresh pass still running - skipped"; exit 0; }
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    if [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rmdir "$LOCK.d" 2>/dev/null; mkdir "$LOCK.d" 2>/dev/null || exit 0
    else log "previous refresh pass still running - skipped"; exit 0; fi
  fi
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi

REPOS="${OVN_BASELINE_REFRESH_REPOS:-billwatch gitlark iptv_apps shrike-monitor shrike-notify test-automation-agent}"
REF="${OVN_BASELINE_REF:-origin/develop}"
RT="${OVN_BASELINE_REPO_TIMEOUT:-900}"; BUDGET="${OVN_BASELINE_BUDGET:-3300}"
t_all=$(date +%s)
for r in $REPOS; do
  if [ $(( $(date +%s) - t_all )) -ge "$BUDGET" ]; then log "$r: skipped (total budget ${BUDGET}s spent)"; continue; fi
  case "$r" in *[!A-Za-z0-9._-]*|"") log "skipped bad repo name"; continue ;; esac
  [ -e "${OVN_REPOS_DIR:-$OVN_DIR/repos}/$r/.git" ] || { log "$r: no clone - skipped"; continue; }   # same resolution order as qa_common.repo_dir
  t0=$(date +%s)
  # outer bound = suite timeout + slack for worktree add/remove; the lib's own --timeout turns a slow suite into UNVERIFIED (old baseline kept)
  out="$(nice -n 15 "$PY" "$HERE/qa_timeout.py" $((RT + 120)) "$PY" "$HERE/baseline_verify.py" refresh --repo "$r" --ref "$REF" --timeout "$RT" 2>>"$LOG" | tail -1)"
  log "$r: $(printf '%s' "$out" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read()); print(d.get("verdict","?"), "|", str(d.get("summary",""))[:160])
except Exception: print("NO-OUTPUT (timeout or crash; old baseline untouched)")' 2>/dev/null) ($(( $(date +%s) - t0 ))s)"
done
log "done in $(( $(date +%s) - t_all ))s"
exit 0
