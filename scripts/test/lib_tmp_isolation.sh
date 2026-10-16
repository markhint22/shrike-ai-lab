# scripts/test/lib_tmp_isolation.sh - SOURCE from run_all.sh (after ntfy_guard.sh) and call `ovn_tmp_isolate`. 2026-10-14 (N4 tmp-isolation).
#
# Why: the box /tmp is a 1,048,576-inode tmpfs. Cron run_all.sh (every 6h) plus ~300 shell tests with only ~36 traps, plus python tests with unmatched mkdtemp,
# leaked 300-400k files per run, and two overlapping runs (the 6h cron next to a manual/agent run) exhausted it twice in 24h (hygiene gates failed, worktree
# creation blocked). This library makes a run self-contained and bounded:
#   1. SINGLE-FLIGHT: only one run_all.sh at a time (flock on $BASE/.run_all.lock; the holder pid + start time are recorded in $BASE/.run_all.lock.pid). A second run
#      refuses with exit 75 (EX_TEMPFAIL). A lock whose recorded holder is DEAD is stale (an orphaned daemon that inherited the lock fd would otherwise wedge every later run
#      forever): it is replaced under a mkdir mutex. No flock binary (the Mac): degrades to the same pid+start-time check without the kernel lock.
#   2. DISK-BACKED PRIVATE TMPDIR: TMPDIR=$BASE/run.<pid> ($BASE = OVN_TEST_TMP_BASE, default $HOME/qtmp - NOT the inode-limited /tmp). Everything a test makes through
#      mktemp / tempfile / $TMPDIR lands there.
#   3. GUARANTEED CLEANUP: the root is removed on EXIT, INT and TERM (composed with whatever traps the caller already had - they still run first).
#   4. LEAK REPORT: before the removal, whatever the tests left behind is counted: a `tmp-leak:` line goes to stdout, and over OVN_TEST_LEAK_WARN entries (default 5000)
#      a WARN line is appended to the queue's state/alerts.log (OVN_ALERTS_FILE overrides; skipped when the state dir does not exist).
#   5. STALE SWEEP: leftover $BASE/run.<pid> roots of runs that died hard (SIGKILL / power loss) are removed at the next start.
# OVN_TEST_ISOLATE=off disables everything (a deliberate manual run). A refused run exits 75: a cron line that alerts on a non-zero exit should treat 75 as benign:
#   ... bash scripts/test/run_all.sh >/tmp/qtests.log 2>&1 || [ $? -eq 75 ] || <alert>
# Scope limit: tests that hard-code a literal /tmp/... path (instead of mktemp / $TMPDIR) are not redirected. bash 3.2 (Mac) and bash 5 safe; no `set -e`.

__OVN_TMP_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "$__OVN_TMP_LIBDIR/lib_safe_tmp.sh" || { echo "tmp-isolation: lib_safe_tmp.sh missing - refusing to run without the guarded rm" >&2; return 1 2>/dev/null || exit 1; }
__ovn_tmp_lower(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }
__ovn_tmp_started(){ ps -p "$1" -o lstart= 2>/dev/null | sed 's/^ *//; s/ *$//'; }   # process start time ("" when the pid is not running)
# rc 0 when the pid recorded in the pid file ("<pid>|<start>") is a LIVE process that is the same one that wrote it (a reused pid has a different start time)
__ovn_tmp_holder_alive(){
  local rec pid st cur
  rec="$(cat "$1" 2>/dev/null)"; pid="${rec%%|*}"; st="${rec#*|}"
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  cur="$(__ovn_tmp_started "$pid")"
  [ -n "$cur" ] && [ "$cur" = "$st" ]
}
__ovn_tmp_write_pid(){ printf '%s|%s\n' "$$" "$(__ovn_tmp_started $$)" > "$1.pid"; }


# 2026-10-16 (HOME-deletion incident hardening). A pid is ALIVE when kill -0 succeeds OR ps can see it: kill -0 fails with EPERM for another user's process, which the old
# sweep read as "dead" (a live run of another user - cron vs an agent shell - then lost its TMPDIR root and every mktemp in it failed).
__ovn_tmp_pid_alive(){
  case "$1" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$1" 2>/dev/null && return 0
  [ -n "$(ps -p "$1" -o pid= 2>/dev/null | tr -d ' ')" ]
}
# every run root carries an owner marker "<pid>|<start>"; the sweep and the cleanup both respect it
__ovn_tmp_write_owner(){ printf '%s|%s\n' "$$" "$(__ovn_tmp_started $$)" > "$1/.ovn_owner" 2>/dev/null; }
# rc 0 when the root's recorded owner is a live process (same start time when it is known). Unknown/unreadable marker -> fall back to the pid in the dir name.
__ovn_tmp_root_owner_alive(){
  local d="$1" rec pid st cur
  rec="$(cat "$d/.ovn_owner" 2>/dev/null)"; pid="${rec%%|*}"; st="${rec#*|}"
  [ -n "$rec" ] || { pid="${d##*/run.}"; st=""; }
  __ovn_tmp_pid_alive "$pid" || return 1
  [ -z "$st" ] && return 0
  cur="$(__ovn_tmp_started "$pid")"
  [ -z "$cur" ] || [ "$cur" = "$st" ]
}
# rc 0 when anything inside the root (or the root itself) changed in the last N minutes (default 10): a root that is still being written is never swept
__ovn_tmp_recent(){ [ -n "$(find "$1" -mmin "-${OVN_TEST_SWEEP_MIN_AGE_MIN:-10}" -print -quit 2>/dev/null)" ]; }
# guarded removal of a run root: fail closed (lib_safe_tmp.sh safe_rm_rf: refuses empty, /, /home, HOME, shallow paths, anything outside the isolation base or the temp roots)
__ovn_tmp_rm_root(){
  local r="$1"
  case "$r" in */run.[0-9]*) ;; *) echo "tmp-isolation: refusing to remove '$r' (not a run.<pid> root)" >&2; return 1;; esac
  if [ -n "${OVN_TMP_BASE_USED:-}" ]; then OVN_SAFE_RM_ROOTS="${OVN_TMP_BASE_USED}${OVN_SAFE_RM_ROOTS:+:$OVN_SAFE_RM_ROOTS}" safe_rm_rf "$r"; else safe_rm_rf "$r"; fi
}

__ovn_tmp_cleanup(){   # idempotent: leak report, then remove the root
  local root="$OVN_TMP_ROOT" n af ad
  [ -n "$root" ] && [ -d "$root" ] || return 0
  case "$root" in */run.[0-9]*) ;; *) return 0;; esac   # only ever remove a root this library created
  n="$(find "$root" -mindepth 1 ! -name .ovn_owner 2>/dev/null | wc -l | tr -d ' ')"; n="${n:-0}"
  echo "tmp-leak: $n entries left in the private TMPDIR by the tests (removed: $root)"
  # 2026-10-15 attribution: the 413k-entry leak (2026-10-14) was reported but not attributed. Name the top-level entries that hold the most files so the
  # leaking test is findable from the log (a mktemp template like /tmp/<name>.XXXX shows as <name>). One complete find pass over the root, grouped by the
  # top-level name (no cap: a leaker sorted past any fixed entry count must still be named). Memory is one counter per top-level name.
  if [ "$n" -gt 0 ] 2>/dev/null; then
    find "$root" -mindepth 1 ! -name .ovn_owner 2>/dev/null \
      | awk -v r="$root/" 'index($0, r) == 1 { s = substr($0, length(r) + 1); sub(/\/.*/, "", s); c[s]++ } END { for (k in c) printf "%d\t%s\n", c[k], k }' \
      | sort -rn | head -5 | while IFS="$(printf '\t')" read -r c nm; do echo "tmp-leak-top: $c entries under '$nm'"; done
  fi
  if [ "$n" -gt "${OVN_TEST_LEAK_WARN:-5000}" ] 2>/dev/null; then
    af="${OVN_ALERTS_FILE:-${OVN_TMP_HERE:-.}/../../state/alerts.log}"; ad="$(dirname "$af")"
    [ -d "$ad" ] && printf '[%s] WARN | test-tmp-leak | the test suite left %s entries in its private TMPDIR (warn threshold %s): a test is not cleaning up after itself\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$n" "${OVN_TEST_LEAK_WARN:-5000}" >> "$af" 2>/dev/null
  fi
  # never remove a root another live run owns (pid reuse / a stray OVN_TMP_ROOT): our own marker says "$$"
  if [ -f "$root/.ovn_owner" ] && [ "$(cut -d'|' -f1 "$root/.ovn_owner" 2>/dev/null)" != "$$" ] && __ovn_tmp_root_owner_alive "$root"; then
    echo "tmp-isolation: $root is owned by another live run - not removing it" >&2; OVN_TMP_ROOT=""; return 0
  fi
  __ovn_tmp_rm_root "$root" 2>/dev/null
  OVN_TMP_ROOT=""
}
__ovn_tmp_on_exit(){
  local rc=$?
  trap - EXIT INT TERM
  [ -z "$OVN_TMP_PREV_EXIT" ] || eval "$OVN_TMP_PREV_EXIT"
  __ovn_tmp_cleanup
  [ -n "${OVN_TMP_LOCKPID_OWNED:-}" ] && rm -f "$OVN_TMP_LOCKPID_OWNED" 2>/dev/null
  exit "$rc"
}
__ovn_tmp_on_signal(){   # $1=INT|TERM $2=exit code: the caller's own handler runs first, then `exit` fires the EXIT trap (cleanup)
  local prev
  if [ "$1" = INT ]; then prev="$OVN_TMP_PREV_INT"; else prev="$OVN_TMP_PREV_TERM"; fi
  [ -z "$prev" ] || eval "$prev"
  exit "$2"
}
__ovn_tmp_prev_trap(){   # $1=signal $2=variable name -> sets it to the caller's existing handler command ("" when none). Subshell-free: bash 3.2 resets traps inside $( ).
  local sig="$1" var="$2" f; f="${TMPDIR:-/tmp}/.ovn_trap.$$.$1"
  trap -p "$sig" > "$f" 2>/dev/null
  printf -v "$var" '%s' ""
  if [ -s "$f" ]; then eval "set -- $(cat "$f")"; printf -v "$var" '%s' "${3:-}"; fi   # the file reads: trap -- 'cmd' SIG
  rm -f "$f"
}

ovn_tmp_isolate(){
  local base lock sweepd d pid
  [ "$(__ovn_tmp_lower "${OVN_TEST_ISOLATE:-on}")" = off ] && return 0
  OVN_TMP_HERE="${OVN_TMP_HERE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)}"
  base="${OVN_TEST_TMP_BASE:-$HOME/qtmp}"
  if ! mkdir -p "$base" 2>/dev/null || [ ! -w "$base" ]; then
    echo "tmp-isolation: $base is not writable - running WITHOUT isolation" >&2; return 0
  fi
  lock="$base/.run_all.lock"
  # --- 1. single-flight
  if [ -n "$(type -P flock 2>/dev/null)" ]; then
    exec 9>>"$lock"
    if ! flock -n 9; then
      if __ovn_tmp_holder_alive "$lock.pid"; then
        echo "tmp-isolation: another run_all.sh is in progress (pid $(cut -d'|' -f1 "$lock.pid" 2>/dev/null)) - refusing to start a second one (exit 75)" >&2; exit 75
      fi
      # the recorded holder is dead (or unknown) but the lock is still held: an orphan inherited the fd. Replace the lock file under a mutex so two starters cannot both "recover".
      find "$lock.recover" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
      if ! mkdir "$lock.recover" 2>/dev/null; then
        echo "tmp-isolation: another run is recovering a stale lock - refusing to start (exit 75)" >&2; exit 75
      fi
      exec 9>&-; exec 9>>"$lock"
      if ! flock -n 9; then
        if __ovn_tmp_holder_alive "$lock.pid"; then rmdir "$lock.recover" 2>/dev/null; echo "tmp-isolation: another run_all.sh is in progress - refusing to start (exit 75)" >&2; exit 75; fi
        exec 9>&-; rm -f "$lock"; exec 9>>"$lock"
        if ! flock -n 9; then rmdir "$lock.recover" 2>/dev/null; echo "tmp-isolation: cannot take the run lock - refusing to start (exit 75)" >&2; exit 75; fi
        echo "tmp-isolation: replaced a stale run lock (its recorded holder is dead)" >&2
      fi
      __ovn_tmp_write_pid "$lock"; rmdir "$lock.recover" 2>/dev/null
    else
      __ovn_tmp_write_pid "$lock"
    fi
  else
    if __ovn_tmp_holder_alive "$lock.pid"; then
      echo "tmp-isolation: another run_all.sh is in progress (pid $(cut -d'|' -f1 "$lock.pid" 2>/dev/null)) - refusing to start a second one (exit 75)" >&2; exit 75
    fi
    __ovn_tmp_write_pid "$lock"   # no flock binary: best-effort pid+start-time lock (tiny start-up race, accepted)
  fi
  OVN_TMP_LOCKPID_OWNED="$lock.pid"
  OVN_TMP_BASE_USED="$base"
  # --- 5. stale sweep: roots of runs that died without cleaning (SIGKILL / power loss). A root is removed ONLY when (a) its owner is not alive (kill -0 AND ps; owner marker
  # start time checked when present) AND (b) nothing in it was modified in the last OVN_TEST_SWEEP_MIN_AGE_MIN minutes (default 10). Either doubt keeps it.
  for d in "$base"/run.[0-9]*; do
    [ -d "$d" ] || continue
    [ -L "$d" ] && continue
    pid="${d##*/run.}"
    case "$pid" in ''|*[!0-9]*) continue;; esac
    [ "$pid" = "$$" ] && continue
    __ovn_tmp_root_owner_alive "$d" && continue
    __ovn_tmp_recent "$d" && continue
    __ovn_tmp_rm_root "$d" 2>/dev/null
  done
  # --- 2. private disk-backed TMPDIR
  OVN_TMP_ROOT="$base/run.$$"
  if [ -d "$OVN_TMP_ROOT" ] && [ -f "$OVN_TMP_ROOT/.ovn_owner" ] && [ "$(cut -d'|' -f1 "$OVN_TMP_ROOT/.ovn_owner" 2>/dev/null)" != "$$" ] && __ovn_tmp_root_owner_alive "$OVN_TMP_ROOT"; then
    OVN_TMP_ROOT=""; echo "tmp-isolation: $base/run.$$ belongs to another live run - TMPDIR unchanged" >&2; return 0
  fi
  [ -e "$OVN_TMP_ROOT" ] && { __ovn_tmp_rm_root "$OVN_TMP_ROOT" 2>/dev/null || true; }
  if ! mkdir -p "$OVN_TMP_ROOT" 2>/dev/null; then OVN_TMP_ROOT=""; echo "tmp-isolation: cannot create the run root under $base - TMPDIR unchanged" >&2; return 0; fi
  __ovn_tmp_write_owner "$OVN_TMP_ROOT"
  export TMPDIR="$OVN_TMP_ROOT"
  # --- 3. cleanup traps composed with the caller's
  __ovn_tmp_prev_trap EXIT OVN_TMP_PREV_EXIT; __ovn_tmp_prev_trap INT OVN_TMP_PREV_INT; __ovn_tmp_prev_trap TERM OVN_TMP_PREV_TERM
  trap '__ovn_tmp_on_exit' EXIT
  trap '__ovn_tmp_on_signal INT 130' INT
  trap '__ovn_tmp_on_signal TERM 143' TERM
  return 0
}
