# lane_env.sh - shared config + helpers for the device lane (sourced, never executed).
# Everything is overridable by env so tests can point it at fakes. NEVER prints secrets.

QA_DL_HOME="${QA_DL_HOME:-$HOME}"
export ANDROID_HOME="${ANDROID_HOME:-$QA_DL_HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$QA_DL_HOME/qa-avd}"
DL_AVD="${DL_AVD:-qa_api34}"
DL_IMAGE="${DL_IMAGE:-system-images;android-34;google_apis;x86_64}"
DL_EMU_PORT="${DL_EMU_PORT:-5570}"                  # console port (even); adb serial = emulator-<port>
DL_SERIAL="emulator-${DL_EMU_PORT}"
DL_APPIUM_PORT="${DL_APPIUM_PORT:-4733}"
export APPIUM_HOME="${APPIUM_HOME:-$QA_DL_HOME/qa-tools/appium/home}"
DL_APPIUM_BIN="${DL_APPIUM_BIN:-$QA_DL_HOME/qa-tools/appium/node_modules/.bin/appium}"
DL_RAM_MB="${DL_RAM_MB:-3072}"
DL_CORES="${DL_CORES:-4}"
# 2026-10-02: 420 (was 240): the only real boot ever attempted on the busy box (6 pinned cores, idle-class io) took >300s; 240s would have made the
# nightly report UNVERIFIED every night. Boot is retried once (run_nightly), 2x420s still sits far inside DL_OVERALL_TIMEOUT.
DL_BOOT_TIMEOUT="${DL_BOOT_TIMEOUT:-420}"
ADB="${ADB:-$ANDROID_HOME/platform-tools/adb}"
EMULATOR_BIN="${EMULATOR_BIN:-$ANDROID_HOME/emulator/emulator}"
SDKMANAGER="${SDKMANAGER:-$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager}"
AVDMANAGER="${AVDMANAGER:-$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager}"

# --- portability shims: the lane runs on the Linux GPU box (KVM) but its tests also run on macOS, which lacks setsid/timeout. -----
dl_py() { if [ -x /usr/bin/python3.12 ]; then echo /usr/bin/python3.12; else command -v python3; fi; }
# DL_SETSID is an ARRAY used as a prefix of a *simple* background command (`"${DL_SETSID[@]}" cmd &`) so that $! is the pid of the
# process that becomes the session leader. (A shell FUNCTION in the background forks a subshell first: $! would then be the
# subshell, and a group kill by that pid's pgid would hit OUR OWN group - that exact bug was caught by the tests.)
if command -v setsid >/dev/null 2>&1; then DL_SETSID=(setsid)
else DL_SETSID=("$(dl_py)" -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])'); fi
# kill_tree PID SIG: signal PID's process group ONLY when PID is its own group leader (never our own group); else just PID.
kill_tree() {
  local pid="$1" sig="${2:-TERM}" pg
  [ -n "$pid" ] || return 0
  pg="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ -n "$pg" ] && [ "$pg" = "$pid" ]; then kill "-$sig" -- "-$pg" 2>/dev/null; else kill "-$sig" "$pid" 2>/dev/null; fi
  return 0
}
dl_timeout() {  # dl_timeout SECONDS cmd... ; rc 124 on timeout (GNU timeout semantics); kills the command's process group
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"
  else "$(dl_py)" -c '
import os, signal, subprocess, sys
secs = float(sys.argv[1])
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except FileNotFoundError:
    sys.exit(127)
def _fwd(sig, frm):  # 2026-10-02: our caller was signalled: take the commands new session down with us
    try: os.killpg(p.pid, signal.SIGKILL)
    except OSError: pass
    sys.exit(143)
for _s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP): signal.signal(_s, _fwd)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    try: os.killpg(p.pid, signal.SIGKILL)
    except OSError: pass
    p.wait(); sys.exit(124)
' "$secs" "$@"
  fi
}

# dl_timeout_fwd SECONDS cmd...: dl_timeout that ALSO dies with its caller's group. 2026-10-02: GNU timeout (and the python fallback) put the command in a
# NEW process group, so a group TERM aimed at a build script (run_nightly's cleanup -> kill_tree on build_apk) never reached gradle/npm under it:
# the 3 GB gradle JVM kept burning CPU for up to 1800s after an overall-cap/signal abort while verify_teardown reported clean. Run it in a subshell
# whose own TERM/INT/HUP trap forwards the signal to the timeout wrapper (which forwards to the command and its group) and waits for it to die.
# The subshell is in the caller's group, so a group kill reaches it. rc semantics as dl_timeout (124 timeout); 143 when aborted by signal.
dl_timeout_fwd() {
  (
    local tp
    if command -v timeout >/dev/null 2>&1; then timeout "$@" & else dl_timeout "$@" & fi
    tp=$!
    trap 'kill -TERM "$tp" 2>/dev/null; for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$tp" 2>/dev/null || break; sleep 1; done; kill_tree "$tp" KILL; kill -KILL "$tp" 2>/dev/null; exit 143' TERM INT HUP
    wait "$tp"
  )
}

dl_log() { printf '%s [devicelane] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# kvm_ok: /dev/kvm readable+writable by THIS process (new login/cron sessions get group kvm; old ones do not).
kvm_ok() {
  case "${DL_FAKE_KVM:-}" in 1) return 0 ;; 0) return 1 ;; esac   # test hooks
  [ -r /dev/kvm ] && [ -w /dev/kvm ]
}

# cpuset prefix: QA_CPUSET pins the emulator so it cannot starve the box (plan caps QA at 6 of 16 cores).
dl_prefix() {
  local p=""
  # 2026-10-02: only pin when the cpuset is valid on THIS machine (a bad QA_CPUSET made taskset exit 1 and the emulator never started)
  if [ -n "${QA_CPUSET:-}" ] && command -v taskset >/dev/null 2>&1 && taskset -c "$QA_CPUSET" true >/dev/null 2>&1; then p="taskset -c $QA_CPUSET "; fi
  # 2026-10-02: best-effort class 7 (was idle class 3). Idle-class io is starved to a crawl whenever the dev loop does disk work, which is what
  # made the one real boot time out; class 2/7 still yields to every normal-priority reader but is guaranteed to make progress.
  if command -v ionice >/dev/null 2>&1; then p="${p}ionice -c2 -n7 "; fi
  printf '%snice -n 10 ' "$p"
}

# emu_alive: is OUR emulator (this port) known to adb?
emu_alive() { "$ADB" devices 2>/dev/null | awk -v s="$DL_SERIAL" '$1==s {f=1} END{exit !f}'; }

# start_emulator <pidfile> <logfile>: headless boot in its own session/process group. Returns 0 once sys.boot_completed=1.
start_emulator() {
  local pidf="$1" logf="$2" t0 now
  [ -x "$EMULATOR_BIN" ] || { dl_log "emulator binary missing: $EMULATOR_BIN"; return 3; }
  kvm_ok || { dl_log "no access to /dev/kvm (user not in group kvm in THIS session)"; return 4; }
  # shellcheck disable=SC2046
  "${DL_SETSID[@]}" $(dl_prefix) "$EMULATOR_BIN" -avd "$DL_AVD" -port "$DL_EMU_PORT" -no-window -no-audio -no-boot-anim \
      -gpu swiftshader_indirect -accel on -no-snapshot -no-metrics -netdelay none -netspeed full \
      -cores "$DL_CORES" -memory "$DL_RAM_MB" >"$logf" 2>&1 < /dev/null 9>&- &
  echo $! >"$pidf"
  t0=$(date +%s)
  while :; do
    now=$(date +%s)
    if [ $((now - t0)) -gt "$DL_BOOT_TIMEOUT" ]; then dl_log "boot timeout after ${DL_BOOT_TIMEOUT}s"; return 5; fi
    if ! kill -0 "$(cat "$pidf")" 2>/dev/null; then dl_log "emulator exited during boot (see log)"; return 6; fi
    if emu_alive && [ "$("$ADB" -s "$DL_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      DL_BOOT_SECONDS=$((now - t0)); return 0
    fi
    sleep 2
  done
}

# stop_emulator <pidfile>: graceful `emu kill`, then SIGTERM/SIGKILL of the whole process group we started.
# Only touches the emulator we started (by recorded pid / our avd name + port), never other emulators.
stop_emulator() {
  local pidf="$1" pid pg
  emu_alive && "$ADB" -s "$DL_SERIAL" emu kill >/dev/null 2>&1
  [ -f "$pidf" ] || return 0
  pid="$(cat "$pidf" 2>/dev/null)"; [ -n "$pid" ] || return 0
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then
    kill_tree "$pid" TERM; sleep 2
    kill_tree "$pid" KILL
    kill -KILL "$pid" 2>/dev/null
  fi
  # a qemu child can outlive the launcher wrapper: match our avd + port precisely.
  pkill -KILL -f "qemu-system.*-avd $DL_AVD .*-port $DL_EMU_PORT" 2>/dev/null
  pkill -KILL -f "qemu-system.*-port $DL_EMU_PORT .*-avd $DL_AVD" 2>/dev/null
  rm -f "$pidf"; return 0
}

# start_appium <pidfile> <logfile>: private appium on DL_APPIUM_PORT, own process group. 0 when /status is ready.
start_appium() {
  local pidf="$1" logf="$2" t0 now
  [ -x "$DL_APPIUM_BIN" ] || { dl_log "appium missing: $DL_APPIUM_BIN"; return 3; }
  "${DL_SETSID[@]}" "$DL_APPIUM_BIN" --port "$DL_APPIUM_PORT" --address 127.0.0.1 --log-no-colors >"$logf" 2>&1 < /dev/null 9>&- &
  echo $! >"$pidf"
  t0=$(date +%s)
  while :; do
    now=$(date +%s)
    [ $((now - t0)) -gt 60 ] && { dl_log "appium did not become ready"; return 5; }
    kill -0 "$(cat "$pidf")" 2>/dev/null || { dl_log "appium exited"; return 6; }
    if curl -fsS -m 2 "http://127.0.0.1:${DL_APPIUM_PORT}/status" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
}

stop_appium() {
  local pidf="$1" pid
  [ -f "$pidf" ] || return 0
  pid="$(cat "$pidf" 2>/dev/null)"; [ -n "$pid" ] || return 0
  kill_tree "$pid" TERM
  for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill_tree "$pid" KILL
  kill -KILL "$pid" 2>/dev/null
  rm -f "$pidf"; return 0
}

# stop_adb_if_idle: kill the adb server only if no device remains attached (it may be shared with a human's session).
stop_adb_if_idle() {
  local n
  # our own serial (even if it lingers as "offline") does not count as someone else's device
  n="$("$ADB" devices 2>/dev/null | awk -v s="$DL_SERIAL" 'NR>1 && $2!="" && $1!=s {c++} END{print c+0}')"
  [ "$n" = 0 ] && "$ADB" kill-server >/dev/null 2>&1
  return 0
}

# verify_teardown <outfile> [pids-dir]: 2026-10-02 post-run PROOF that nothing of ours survived. The earlier cleanup is best effort (a qemu child
# can outlive its launcher, appium spawns children); this independently looks for anything still carrying OUR avd name or OUR appium port,
# escalates TERM -> KILL once, re-checks, and writes {"clean":bool,"escalated":[..],"leaked":[..]}. Only our avd/port are matched, never other
# emulators or a human's adb. DL_CHECK_ADB=1 additionally requires the adb server to be gone when no foreign device is attached.
# Always returns 0 (advisory lane); "clean":false is the signal.
verify_teardown() {
  local out="${1:-}" pdir="${2:-}" pat pid f esc="" left="" pids="" alive=""
  # 2026-10-02: avd pattern is AVD *and* console port (same precision as stop_emulator): an avd-name-only match killed any emulator on that AVD,
  # including a real lane run in another state dir (lane.lock does not span state dirs) and a human's manual run. Both arg orders are matched.
  local pats=("[-]avd $DL_AVD .*-port $DL_EMU_PORT( |\$)" "[-]port $DL_EMU_PORT .*-avd $DL_AVD( |\$)" "[a]ppium.* --port $DL_APPIUM_PORT( |\$)")
  for pat in "${pats[@]}"; do
    for pid in $(pgrep -f -- "$pat" 2>/dev/null); do [ "$pid" = "$$" ] || pids="$pids $pid"; done
  done
  if [ -n "$pdir" ]; then for f in "$pdir"/*.pid; do [ -f "$f" ] && { pid="$(cat "$f" 2>/dev/null)"; [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && pids="$pids $pid"; }; done; fi
  pids="$(printf '%s\n' $pids | sort -u | tr '\n' ' ')"
  if [ -n "${pids// /}" ]; then
    for pid in $pids; do esc="$esc\"$pid:$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' \"')\","; kill -TERM "$pid" 2>/dev/null; done
    sleep 2
    for pid in $pids; do kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done
    sleep 1
    for pid in $pids; do kill -0 "$pid" 2>/dev/null && left="$left\"$pid\","; done
  fi
  if curl -fsS -m 2 "http://127.0.0.1:${DL_APPIUM_PORT}/status" >/dev/null 2>&1; then left="$left\"appium-port-$DL_APPIUM_PORT\","; fi
  if [ -n "${DL_CHECK_ADB:-}" ] && pgrep -f 'adb.* fork-server' >/dev/null 2>&1; then
    stop_adb_if_idle; sleep 1
    if pgrep -f 'adb.* fork-server' >/dev/null 2>&1 && [ "$("$ADB" devices 2>/dev/null | awk -v s="$DL_SERIAL" 'NR>1 && $2!="" && $1!=s {c++} END{print c+0}')" = 0 ]; then
      left="$left\"adb-server\","
    fi
  fi
  local json
  json="$(printf '{"clean":%s,"escalated":[%s],"leaked":[%s]}' "$([ -z "$left" ] && echo true || echo false)" "${esc%,}" "${left%,}")"
  [ -n "$out" ] && printf '%s\n' "$json" >"$out" 2>/dev/null
  if [ -z "$left" ]; then dl_log "teardown verified clean ${esc:+(escalated: ${esc%,})}"; else dl_log "TEARDOWN LEAK: ${left%,}"; fi
  return 0
}
