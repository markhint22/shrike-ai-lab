#!/usr/bin/env bash
# ovn_auto_research.sh run-lock diagnostics (2026-10-09). run.log alternated "daily cap reached" / "another run active - skip" x2 for days with no way to
# tell why. Now a skip says WHO holds the lock (pid), how old it is and whether the pid is alive (ps stat - never kill -0, which answers "alive" for a
# killed-but-unreaped child); a lock whose holder is dead, or older than 3h, is removed and the run continues; and the releasing trap is installed right
# after the lock is taken (the old code leaked the lock on every daily-cap exit, which matches the alternation).
# Hermetic (lib_ar_fixture.sh): temp HOME/state, stub ssh/scp/claude. Liveness in this test is ps stat too. Mutation checks at the bottom.
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../ovn_auto_research.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../ovn_auto_research.sh"
. "$HERE/lib_ar_fixture.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
MT="$(cd "$(mktemp -d)" && pwd -P)"
BG=""
cleanup_all(){ for p in $BG; do kill "$p" 2>/dev/null; { wait "$p"; } 2>/dev/null; done; rm -rf "$MT"; [ -n "${T:-}" ] && rm -rf "$T"; }
trap cleanup_all EXIT

mutate(){   # <src> <dest> <anchor> <replacement>
  python3 - "$1" "$2" "$3" "$4" 2>/dev/null <<'PY' || { F=$((F+1)); echo "  FAIL mutation anchor missing - the test is stale: $3"; }
import sys
src, dest, a, b = sys.argv[1:5]
s = open(src).read()
assert a in s, "mutation anchor missing: %r" % a
open(dest, "w").write(s.replace(a, b, 1))
PY
}
epoch_ago(){ python3 -c "import time,sys; print(int(time.time()-float(sys.argv[1])))" "$1"; }
mklock(){ mkdir -p "$STATE/run.lock.d"; [ -n "${2:-}" ] && echo "$1 $2" > "$STATE/run.lock.d/holder"; }   # <pid> <epoch>  (no epoch -> no holder file)
state_of(){ ps -o stat= -p "$1" 2>/dev/null | tr -d ' '; }            # liveness: ps stat, never kill -0
spawn_live(){   # a live process whose command line contains the holder pattern (what the real job looks like to ps)
  printf '#!/usr/bin/env bash\nsleep 120 &\ntrap '"'"'kill $! 2>/dev/null; exit 0'"'"' TERM\nwait\n' > "$T/ovn_auto_research_holder.sh"   # TERM also reaps its sleep child (no orphans)
  "$BASH" "$T/ovn_auto_research_holder.sh" >/dev/null 2>&1 & LIVE_PID=$!; BG="$BG $LIVE_PID"   # stdout detached: a background child holding the $(...) pipe would hang the capture
}
spawn_other(){ sleep 120 >/dev/null 2>&1 & OTHER_PID=$!; BG="$BG $OTHER_PID"; }       # live, but NOT an ovn_auto_research process (a reused pid)
reaped_pid(){ sleep 0 & local p=$!; { wait "$p"; } 2>/dev/null; echo "$p"; }
make_zombie(){   # a killed child whose parent never reaps it: ps stat = Z, but kill -0 still succeeds
  rm -f "$T/zpid"
  python3 -c 'import subprocess,sys,time
p = subprocess.Popen(["sleep", "100"]); open(sys.argv[1], "w").write(str(p.pid)); time.sleep(0.5); p.kill(); time.sleep(40)' "$T/zpid" >/dev/null 2>&1 &
  ZPARENT=$!; BG="$BG $ZPARENT"
  local i=0 st
  while [ $i -lt 50 ]; do
    ZPID="$(cat "$T/zpid" 2>/dev/null)"
    if [ -n "$ZPID" ]; then st="$(state_of "$ZPID")"; case "$st" in Z*) return 0;; esac; fi
    sleep 0.2; i=$((i+1))
  done
  return 1
}
fresh(){ rm -rf "$STATE" "$CAP"; mkdir -p "$STATE" "$CAP"; : > "$BOX/ssh.log"; rm -f "$BOX/lock_peek.txt"; ar_starving; }   # no repo starving: a run that gets past the lock just says so
log_has(){ grep -a -c -F -- "$1" "$T/out.txt"; }

# prints "1|name" / "0|name" lines; all 1 for the real script, every mutant must produce at least one 0
lock_checks(){
  ar_setup "$1"
  local pid dead

  # A. live holder, 10 minutes old -> skip, the line names pid + liveness + age, the lock is untouched
  fresh; spawn_live; pid="$LIVE_PID"; mklock "$pid" "$(epoch_ago 600)"
  ar_run
  [ "$(log_has "another run active - skip (lock holder pid=$pid alive(")" = 1 ] && [ "$(log_has "age=10m)")" = 1 ] && echo "1|live holder: skip line carries pid, 'alive(...)' and age" || echo "0|live holder: skip line carries pid, 'alive(...)' and age [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  [ "$AR_RC" = 0 ] && [ -d "$STATE/run.lock.d" ] && [ "$(cut -d' ' -f1 "$STATE/run.lock.d/holder")" = "$pid" ] && echo "1|live holder: lock left untouched, exit 0" || echo "0|live holder: lock left untouched, exit 0"
  [ ! -s "$BOX/ssh.log" ] && [ "$(log_has "no repo starving")" = 0 ] && echo "1|live holder: the run did not proceed (no ssh traffic)" || echo "0|live holder: the run did not proceed (no ssh traffic)"
  kill "$pid" 2>/dev/null; { wait "$pid"; } 2>/dev/null

  # A2. a LIVE pid that is some other command (pid reused) is not our holder -> cleaned, run proceeds
  fresh; spawn_other; pid="$OTHER_PID"; mklock "$pid" "$(epoch_ago 600)"
  ar_run
  [ "$(log_has "stale run lock removed (holder dead): holder pid=$pid dead(pid reused by another command) age=10m")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && echo "1|reused pid (live, different command) -> treated as dead, cleaned, run proceeds" || echo "0|reused pid (live, different command) -> treated as dead, cleaned, run proceeds [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  kill "$pid" 2>/dev/null; { wait "$pid"; } 2>/dev/null

  # B. dead (reaped) holder -> cleaned, run proceeds, lock released at exit
  fresh; dead="$(reaped_pid)"; mklock "$dead" "$(epoch_ago 600)"
  ar_run
  [ "$(log_has "stale run lock removed (holder dead): holder pid=$dead dead(no such process) age=10m")" = 1 ] && echo "1|dead pid -> 'stale run lock removed' with pid, 'dead(no such process)' and age" || echo "0|dead pid -> 'stale run lock removed' with pid, 'dead(no such process)' and age [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  [ "$(log_has "no repo starving")" = 1 ] && [ "$(log_has "another run active")" = 0 ] && echo "1|dead pid: the run continued past the lock" || echo "0|dead pid: the run continued past the lock"
  [ ! -d "$STATE/run.lock.d" ] && echo "1|dead pid: the lock is released when the run ends" || echo "0|dead pid: the lock is released when the run ends"

  # B2. a killed-but-unreaped child (zombie): ps stat says Z (dead); kill -0 would say alive
  fresh
  if make_zombie; then
    mklock "$ZPID" "$(epoch_ago 600)"; ar_run
    [ "$(log_has "holder pid=$ZPID dead(zombie)")" = 1 ] && echo "1|zombie holder (ps stat Z) -> dead(zombie), cleaned" || echo "0|zombie holder (ps stat Z) -> dead(zombie), cleaned [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  else
    echo "0|could not create a zombie process on this host (test cannot prove the ps-stat liveness check)"
  fi

  # C. lock older than 3h, holder still alive -> cleaned (a hung run must not block forever)
  fresh; spawn_live; pid="$LIVE_PID"; mklock "$pid" "$(epoch_ago $((4*3600)))"
  ar_run
  [ "$(log_has "stale run lock removed (lock older than 3h): holder pid=$pid alive(")" = 1 ] && [ "$(log_has "age=240m")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && echo "1|lock older than 3h -> cleaned even though the pid is alive; run proceeds" || echo "0|lock older than 3h -> cleaned even though the pid is alive; run proceeds [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  kill "$pid" 2>/dev/null; { wait "$pid"; } 2>/dev/null
  # C2. just under 3h (2h50m) with a live holder -> NOT cleaned (negative control for the age rule)
  fresh; spawn_live; pid="$LIVE_PID"; mklock "$pid" "$(epoch_ago $((170*60)))"
  ar_run
  [ "$(log_has "another run active - skip (lock holder pid=$pid alive(")" = 1 ] && [ "$(log_has "stale run lock removed")" = 0 ] && echo "1|2h50m-old live lock is respected" || echo "0|2h50m-old live lock is respected"
  # C3. OVN_AR_LOCK_STALE_H=1 shortens the limit
  fresh; mklock "$pid" "$(epoch_ago 7200)"; ar_run OVN_AR_LOCK_STALE_H=1
  [ "$(log_has "stale run lock removed (lock older than 1h)")" = 1 ] && echo "1|OVN_AR_LOCK_STALE_H=1 -> a 2h-old live lock is cleaned" || echo "0|OVN_AR_LOCK_STALE_H=1 -> a 2h-old live lock is cleaned"
  kill "$pid" 2>/dev/null; { wait "$pid"; } 2>/dev/null

  # D. a lock with no holder file (left by the OLD script): age comes from the directory mtime
  fresh; mklock "" ""; ar_run
  [ "$(log_has "another run active - skip (lock holder pid=? unknown(no holder file) age=0m)")" = 1 ] && echo "1|no holder file, fresh -> skip, says unknown(no holder file)" || echo "0|no holder file, fresh -> skip, says unknown(no holder file) [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  fresh; mklock "" ""; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-4*3600)))')" "$STATE/run.lock.d"; ar_run
  [ "$(log_has "stale run lock removed (no holder file for more than 10m): holder pid=? unknown(no holder file)")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && echo "1|no holder file, 4h old by mtime -> cleaned, run proceeds" || echo "0|no holder file, 4h old by mtime -> cleaned, run proceeds [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  # D3. (round-3 review fix) the leaked EMPTY lock dir left by the old script: a lock with no holder file is stale after 10 minutes, not 3h (the Mac had one that
  #     would have delayed the first productive tick by up to 3h). 15 min -> cleaned; 5 min -> still respected (a run between its mkdir and its holder write).
  fresh; mklock "" ""; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-15*60)))')" "$STATE/run.lock.d"; ar_run
  [ "$(log_has "stale run lock removed (no holder file for more than 10m)")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && echo "1|empty lock dir 15 min old (old-script leak) -> cleaned at once, run proceeds" || echo "0|empty lock dir 15 min old (old-script leak) -> cleaned at once, run proceeds [$(tail -2 "$T/out.txt" | tr '\n' '~')]"
  fresh; mklock "" ""; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-5*60)))')" "$STATE/run.lock.d"; ar_run
  [ "$(log_has "another run active - skip (lock holder pid=? unknown(no holder file)")" = 1 ] && [ "$(log_has "stale run lock removed")" = 0 ] && echo "1|empty lock dir 5 min old -> respected (negative control)" || echo "0|empty lock dir 5 min old -> respected (negative control)"

  # E. the daily-cap exit releases the lock (the leak behind the cap/active/active alternation)
  fresh; echo 2 > "$STATE/count_$(date +%F)"; ar_run
  [ "$(log_has "daily cap reached (2/2) - skip")" = 1 ] && [ ! -d "$STATE/run.lock.d" ] && echo "1|daily-cap exit releases the lock (no leak)" || echo "0|daily-cap exit releases the lock (no leak) [lock dir present: $([ -d "$STATE/run.lock.d" ] && echo yes || echo no)]"
  # E2. back-to-back runs: after a cap exit the NEXT run is not blocked
  ar_run
  [ "$(log_has "daily cap reached (2/2) - skip")" = 1 ] && [ "$(log_has "another run active")" = 0 ] && echo "1|second run after a cap exit is not 'another run active'" || echo "0|second run after a cap exit is not 'another run active'"

  # F. a normal run records "<pid> <epoch>" while it holds the lock and releases it afterwards
  fresh; ar_run LOCK_PEEK="$STATE/run.lock.d/holder"
  [ -s "$BOX/lock_peek.txt" ] && [ "$(grep -c -E '^[0-9]+ [0-9]+$' "$BOX/lock_peek.txt")" = 1 ] && echo "1|the running job records '<pid> <epoch>' in the lock" || echo "0|the running job records '<pid> <epoch>' in the lock"
  [ ! -d "$STATE/run.lock.d" ] && echo "1|normal run releases the lock at exit" || echo "0|normal run releases the lock at exit"

  # G. kill switch: OVN_AR_LOCK_DIAG=off -> the old behaviour (plain message, no holder bookkeeping, 2h by mtime)
  fresh; dead="$(reaped_pid)"; mklock "$dead" "$(epoch_ago 600)"; ar_run OVN_AR_LOCK_DIAG=off
  [ "$(log_has "another run active - skip")" = 1 ] && [ "$(log_has "lock holder pid")" = 0 ] && [ "$(log_has "stale run lock removed")" = 0 ] && echo "1|OVN_AR_LOCK_DIAG=off: old plain skip message, dead holder not inspected" || echo "0|OVN_AR_LOCK_DIAG=off: old plain skip message, dead holder not inspected"
  fresh; mklock "$dead" "$(epoch_ago 600)"; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-3*3600)))')" "$STATE/run.lock.d"; ar_run OVN_AR_LOCK_DIAG=off
  [ "$(log_has "no repo starving")" = 1 ] && echo "1|OVN_AR_LOCK_DIAG=off: a >2h-old lock is still replaced (old rule)" || echo "0|OVN_AR_LOCK_DIAG=off: a >2h-old lock is still replaced (old rule)"

  # H. (review fix) a corrupt holder file must never crash the script or run its content: before the fix 'abc;touch PWNED xyz' made `read` put
  #    "PWNED xyz" into the timestamp and the arithmetic aborted with "PWNED: unbound variable" (rc=1) on EVERY hourly tick until someone removed the lock.
  fresh; mkdir -p "$STATE/run.lock.d"; echo 'abc;touch PWNED xyz' > "$STATE/run.lock.d/holder"; ( cd "$T" && ar_run )
  [ "$AR_RC" = 0 ] && [ "$(log_has "another run active - skip (lock holder pid=? unknown(invalid holder file) age=0m)")" = 1 ] && echo "1|garbage holder: exit 0, treated as unknown(invalid holder file), skipped (fresh lock)" || echo "0|garbage holder: exit 0, treated as unknown(invalid holder file), skipped (fresh lock) [rc=$AR_RC $(tail -2 "$T/out.txt" | tr '\n' '~')]"
  [ "$(log_has "unbound variable")" = 0 ] && [ "$(log_has "syntax error")" = 0 ] && [ ! -e "$T/PWNED" ] && echo "1|garbage holder: no bash arithmetic error, nothing executed" || echo "0|garbage holder: no bash arithmetic error, nothing executed"
  fresh; mkdir -p "$STATE/run.lock.d"; echo 'abc;touch PWNED xyz' > "$STATE/run.lock.d/holder"
  touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-4*3600)))')" "$STATE/run.lock.d"; ar_run
  [ "$AR_RC" = 0 ] && [ "$(log_has "stale run lock removed (lock older than 3h): holder pid=? unknown(invalid holder file)")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && echo "1|garbage holder, 4h old by mtime -> cleaned, the run proceeds (no permanent wedge)" || echo "0|garbage holder, 4h old by mtime -> cleaned, the run proceeds (no permanent wedge) [rc=$AR_RC $(tail -2 "$T/out.txt" | tr '\n' '~')]"
  fresh; mkdir -p "$STATE/run.lock.d"; echo '123 99999999999999999999999' > "$STATE/run.lock.d/holder"; ar_run
  [ "$AR_RC" = 0 ] && [ "$(log_has "unknown(invalid holder file)")" = 1 ] && echo "1|overflowing-timestamp holder line is rejected as invalid, no crash" || echo "0|overflowing-timestamp holder line is rejected as invalid, no crash [rc=$AR_RC $(tail -2 "$T/out.txt" | tr '\n' '~')]"
  # H2. a missing holder file prints no raw bash error (the failed `< file` redirect used to print one before 2>/dev/null applied)
  fresh; mklock "" ""; ar_run
  [ "$(log_has "No such file")" = 0 ] && [ "$(log_has "holder: ")" = 0 ] && [ "$(log_has "unknown(no holder file)")" = 1 ] && echo "1|missing holder file: no raw 'No such file' bash error on stderr" || echo "0|missing holder file: no raw 'No such file' bash error on stderr [$(tail -3 "$T/out.txt" | tr '\n' '~')]"

  # I. (review fix) stale-lock takeover is atomic. Two runs can both judge the lock stale; before the fix the loser's `rm -rf` deleted the WINNER's fresh lock and
  #    both proceeded. A stub `tee` (the log() sink: it runs at a chosen point of the takeover) swaps in a fresh lock owned by a live "other run" or, with no
  #    SWAP_PID, a fresh lock that has no holder file yet (a run between its mkdir and its holder write). SWAP_ON = the log line that triggers the swap.
  cat > "$FAKEBIN/tee" <<'EOS'
#!/usr/bin/env bash
in="$(cat)"; printf '%s\n' "$in" | /usr/bin/tee "$@"
case "$in" in *"${SWAP_ON:-@@never@@}"*) rm -rf "$SWAP_STATE/run.lock.d"; mkdir "$SWAP_STATE/run.lock.d"; [ -z "${SWAP_PID:-}" ] || echo "$SWAP_PID $(date +%s)" > "$SWAP_STATE/run.lock.d/holder";; esac
EOS
  chmod +x "$FAKEBIN/tee"
  fresh; spawn_live; pid="$LIVE_PID"; dead="$(reaped_pid)"; mklock "$dead" "$(epoch_ago 600)"
  ar_run SWAP_ON="stale run lock removed" SWAP_PID="$pid" SWAP_STATE="$STATE"
  [ "$AR_RC" = 0 ] && [ "$(log_has "lock was replaced by another run during the stale cleanup - skip")" = 1 ] && [ "$(log_has "no repo starving")" = 0 ] && echo "1|racing takeover: a lock replaced by another run mid-cleanup makes this run skip" || echo "0|racing takeover: a lock replaced by another run mid-cleanup makes this run skip [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  [ -d "$STATE/run.lock.d" ] && [ "$(cut -d' ' -f1 "$STATE/run.lock.d/holder" 2>/dev/null)" = "$pid" ] && [ ! -s "$BOX/ssh.log" ] && echo "1|racing takeover: the other run's fresh lock is still in place and no work was done" || echo "0|racing takeover: the other run's fresh lock is still in place and no work was done"
  [ "$(ls -d "$STATE"/run.lock.d.stale.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && [ ! -d "$STATE/run.lock.d.takeover" ] && echo "1|racing takeover: no stale.* directory and no takeover guard left behind" || echo "0|racing takeover: no stale.* directory and no takeover guard left behind"
  # I3. swap AFTER the staleness was confirmed under the guard (between the confirmation and the move): the moved lock is not the one confirmed -> put back, skip
  fresh; mklock "$dead" "$(epoch_ago 600)"
  ar_run SWAP_ON="confirmed under the takeover guard" SWAP_PID="$pid" SWAP_STATE="$STATE"
  [ "$AR_RC" = 0 ] && [ "$(log_has "no repo starving")" = 0 ] && [ -d "$STATE/run.lock.d" ] && [ "$(cut -d' ' -f1 "$STATE/run.lock.d/holder" 2>/dev/null)" = "$pid" ] && [ ! -s "$BOX/ssh.log" ] && [ "$(ls -d "$STATE"/run.lock.d.stale.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && echo "1|swap between confirmation and move: the other run's lock is restored, this run skips" || echo "0|swap between confirmation and move: the other run's lock is restored, this run skips [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  # I4. (round-3) a stale (4h old, so the OLD code also judged it stale) lock with NO holder file, and another run has just mkdir'd a fresh lock but not written its holder yet: the old code compared two empty
  #     holder lines ("same lock") and deleted the fresh lock. The verdict is now re-taken from the disk under the guard (a fresh empty lock is not stale).
  fresh; mklock "" ""; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-4*3600)))')" "$STATE/run.lock.d"
  ar_run SWAP_ON="stale run lock removed" SWAP_PID="" SWAP_STATE="$STATE"
  [ "$AR_RC" = 0 ] && [ "$(log_has "no repo starving")" = 0 ] && [ -d "$STATE/run.lock.d" ] && [ ! -s "$BOX/ssh.log" ] && [ "$(log_has "lock was replaced by another run during the stale cleanup - skip")" = 1 ] && echo "1|holder-less stale lock replaced by another run's fresh holder-less lock: NOT deleted, this run skips" || echo "0|holder-less stale lock replaced by another run's fresh holder-less lock: NOT deleted, this run skips [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  # I5. same swap but after the confirmation (between confirmation and move): both lines are empty, so only the pre-move re-judgement could help; the lock was
  #     confirmed stale, then swapped, then moved aside: it must be put back (the fresh empty lock is the other run's) - the old code deleted it.
  fresh; mklock "" ""; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-4*3600)))')" "$STATE/run.lock.d"
  ar_run SWAP_ON="confirmed under the takeover guard" SWAP_PID="" SWAP_STATE="$STATE"
  [ "$AR_RC" = 0 ] && [ "$(log_has "no repo starving")" = 0 ] && [ -d "$STATE/run.lock.d" ] && [ ! -s "$BOX/ssh.log" ] && echo "1|holder-less swap after confirmation: the fresh lock is restored, nothing proceeds" || echo "0|holder-less swap after confirmation: the fresh lock is restored, nothing proceeds [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  rm -f "$FAKEBIN/tee"
  kill "$pid" 2>/dev/null; { wait "$pid"; } 2>/dev/null
  # J. (round-3) the takeover is serialised by a mkdir mutex: a run that judges the lock stale while ANOTHER run holds the takeover guard must skip and touch nothing
  fresh; dead="$(reaped_pid)"; mklock "$dead" "$(epoch_ago 600)"; mkdir "$STATE/run.lock.d.takeover"
  ar_run
  [ "$AR_RC" = 0 ] && [ "$(log_has "another run is taking over the stale lock - skip")" = 1 ] && [ "$(log_has "no repo starving")" = 0 ] && [ -d "$STATE/run.lock.d.takeover" ] && [ "$(cut -d' ' -f1 "$STATE/run.lock.d/holder")" = "$dead" ] && [ ! -s "$BOX/ssh.log" ] && echo "1|takeover guard held by another run: skip, the lock and the guard are untouched" || echo "0|takeover guard held by another run: skip, the lock and the guard are untouched [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  # J2. a guard leaked by a killed run (older than 10 min) is cleaned and the takeover proceeds; no guard is left behind
  fresh; mklock "$dead" "$(epoch_ago 600)"; mkdir "$STATE/run.lock.d.takeover"; touch -t "$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time()-15*60)))')" "$STATE/run.lock.d.takeover"
  ar_run
  [ "$(log_has "takeover guard older than 10m (its run died) - removed")" = 1 ] && [ "$(log_has "no repo starving")" = 1 ] && [ ! -d "$STATE/run.lock.d.takeover" ] && echo "1|leaked takeover guard (15 min old) is cleaned, the run proceeds and leaves no guard" || echo "0|leaked takeover guard (15 min old) is cleaned, the run proceeds and leaves no guard [$(tail -3 "$T/out.txt" | tr '\n' '~')]"
  # I2. the normal takeover leaves no .stale directory either
  fresh; dead="$(reaped_pid)"; mklock "$dead" "$(epoch_ago 600)"; ar_run
  [ "$(log_has "no repo starving")" = 1 ] && [ "$(ls -d "$STATE"/run.lock.d.stale.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && echo "1|normal stale takeover leaves no stale.* directory" || echo "0|normal stale takeover leaves no stale.* directory"
  ar_cleanup; T=""
}

echo "== run lock (real script) =="
res="$(lock_checks "$SCRIPT")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOF
$res
EOF

echo "== mutation checks: break each rule, the checks above must notice =="
nfail(){ printf '%s\n' "$1" | grep -c '^0|'; }
mv_lock(){   # <name> <anchor> <replacement>
  mutate "$SCRIPT" "$MT/s.sh" "$2" "$3"
  local r; r="$(lock_checks "$MT/s.sh")"; T=""
  ok "mutant '$1' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
}
mv_lock "a dead holder is never cleaned" 'if [ "$h_alive" = 0 ]; then stale="holder dead"' 'if false; then stale="holder dead"'
mv_lock "liveness by kill -0 instead of ps stat" "st=\"\$(ps -o stat= -p \"\$1\" 2>/dev/null | tr -d ' ')\"" 'if kill -0 "$1" 2>/dev/null; then st=S; else st=; fi'
mv_lock "age rule disabled" '[ "$age_s" -gt $(( LOCK_STALE_H * 3600 )) ]' '[ "$age_s" -gt 999999999 ]'
mv_lock "skip line without pid/liveness/age" 'another run active - skip (lock holder pid=${hpid:-?} $hstate age=$(( age_s / 60 ))m)' 'another run active - skip'
mv_lock "pid reuse not detected (any live pid is the holder)" 'case "$cmd" in *"$LOCK_HOLDER_PATTERN"*) echo "alive($st)"; return 0;;' 'case "$cmd" in *) echo "alive($st)"; return 0;;'
mv_lock "holder file never written" '[ "${OVN_AR_LOCK_DIAG:-on}" = "off" ] || echo "$$ $(date +%s)" > "$LOCKD/holder"' 'true'
mv_lock "diagnostics always off" 'elif [ "${OVN_AR_LOCK_DIAG:-on}" = "off" ]; then' 'elif true; then'
mv_lock "stale limit ignores OVN_AR_LOCK_STALE_H" 'LOCK_STALE_H="${OVN_AR_LOCK_STALE_H:-3}"' 'LOCK_STALE_H=3'
mv_lock "holder content trusted (no numeric validation)" 'if [[ "$hline" =~ ^([0-9]{1,9})\ ([0-9]{1,12})$ ]]; then hpid="${BASH_REMATCH[1]}"; hts="${BASH_REMATCH[2]}"' 'if [ -n "$hline" ]; then read -r hpid hts <<< "$hline"; [ -z "${hts:-}" ] || true'
mv_lock "failed holder read prints a raw bash error" 'hline="$(head -n 1 "$jd/holder" 2>/dev/null)" || true' 'read -r hline < "$LOCKD/holder" || true'
# atomic takeover reverted to the old rm -rf + mkdir (plain), and with only the replaced-lock check disabled
mutate "$SCRIPT" "$MT/s0.sh" 'mv "$LOCKD" "$stale_dir" 2>/dev/null || { log "lock changed under us after a stale cleanup - skip"; exit 0; }' 'rm -rf "$LOCKD"; mkdir -p "$stale_dir"'
mutate "$MT/s0.sh" "$MT/s.sh" 'if [ "$moved_line" != "$confirmed_line" ] || [ -z "$stale" ]; then' 'if false; then'
r="$(lock_checks "$MT/s.sh")"; T=""
ok "mutant 'stale takeover is rm -rf + mkdir (not atomic)' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
mv_lock "replaced-lock check disabled" 'if [ "$moved_line" != "$confirmed_line" ] || [ -z "$stale" ]; then' 'if false; then'
# the original leak: the releasing trap installed only AFTER the daily-cap check
mutate "$SCRIPT" "$MT/s0.sh" "trap 'rm -rf \"\${WORK:-}\"; drop_guard; release_lock' EXIT" ':'
mutate "$MT/s0.sh" "$MT/s.sh" 'WORK="$(mktemp -d)"' "WORK=\"\$(mktemp -d)\"; trap 'rm -rf \"\$WORK\"; drop_guard; release_lock' EXIT"
r="$(lock_checks "$MT/s.sh")"; T=""
ok "mutant 'trap installed after the cap check (the original leak)' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"

echo
echo "auto research lock: $P passed, $F failed"
[ "$F" = 0 ]
