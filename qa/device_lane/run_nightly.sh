#!/usr/bin/env bash
# run_nightly.sh - ADVISORY nightly Android device lane for Chickadee (cron-safe: self-locating, minimal PATH, flock -n).
#
#   run_nightly.sh [--ref origin/develop] [--specs all|a,b] [--repo iptv_apps] [--api-base URL] [--no-record]
#
# Flow: lock -> preflight (kvm/sdk/appium, staging health + test-account login) -> build debug APK pointed at STAGING (cached by sha)
#       -> boot headless emulator (KVM, cpuset) -> install -> appium -> run every spec, retry-once-then-report with video+logcat
#       on failure -> verdict via lane_report.py (PASS | FLAG | UNVERIFIED, never FAIL) -> cleanup of emulator/appium/adb ALWAYS.
# Exit code is always 0 (advisory); the verdict is the last stdout line (one JSON object) and in state/qa_shadow/devicelane.jsonl.
# Secrets: credentials come from $DL_CREDS (default ~/.config/qa-devicelane/staging.env, mode 600). They are exported to the specs
# only; never echoed, and spec output is redacted before it is saved.
set -u
# --- resolve our own path BEFORE any cd (cron starts in $HOME with a tiny PATH) ----------------------------------------------
SELF="${BASH_SOURCE[0]}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" && pwd)"
QA_DIR="$(dirname "$HERE")"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${DL_EXTRA_PATH:+:$DL_EXTRA_PATH}"
. "$HERE/lane_env.sh"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
[ -n "${DL_TRACE:-}" ] && { exec 5>>"$DL_TRACE"; BASH_XTRACEFD=5; set -x; }   # debugging aid: xtrace to a file (never stdout)
PY="${DL_PYTHON:-}"
if [ -z "$PY" ]; then for c in /usr/bin/python3.12 /usr/bin/python3 /usr/local/bin/python3 python3; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done; fi

OVN="${OVN_DIR:-$HOME/overnight-queue}"; export OVN_DIR="$OVN"
STATE="$OVN/state/qa_devicelane"
REPO="iptv_apps"; REF="origin/develop"; SPECS="all"; API_BASE="${DL_API_BASE:-https://chickadeestream-backend-staging.up.railway.app}"; NOREC=""
while [ $# -gt 0 ]; do case "$1" in
  --ref) REF="$2"; shift 2 ;; --specs) SPECS="$2"; shift 2 ;; --repo) REPO="$2"; shift 2 ;;
  --api-base) API_BASE="$2"; shift 2 ;; --no-record) NOREC="--no-record"; shift ;; *) echo "unknown arg $1" >&2; exit 0 ;; esac; done

mkdir -p "$STATE/runs" "$STATE/apk" 2>/dev/null
RUN_ID="$(date +%Y%m%dT%H%M%S)"; RUN_DIR="$STATE/runs/$RUN_ID"
SHA=""

REPORTED=""
report_infra() {  # $1 = reason. Prints the UNVERIFIED verdict JSON line and returns.
  REPORTED=1
  dl_log "UNVERIFIED: $1"
  "$PY" "$HERE/lane_report.py" infra --reason "$1" --sha "$SHA" --run-dir "$RUN_DIR" $NOREC
}

# --- lock: never overlap (a 2nd cron firing while a slow run is active must be a no-op, not a failure) --------------------------
LOCKDIR=""
if command -v flock >/dev/null 2>&1; then
  exec 9>"$STATE/lane.lock"
  if ! flock -n 9; then report_infra "another device-lane run holds the lock (skipped)"; exit 0; fi
else  # no flock (macOS): portable mkdir lock with stale-pid recovery
  LOCKDIR="$STATE/lane.lockdir"
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    opid="$(cat "$LOCKDIR/pid" 2>/dev/null)"
    if [ -n "$opid" ] && kill -0 "$opid" 2>/dev/null; then report_infra "another device-lane run holds the lock (skipped)"; exit 0; fi
    rm -rf "$LOCKDIR"; mkdir "$LOCKDIR" 2>/dev/null || { report_infra "another device-lane run holds the lock (skipped)"; exit 0; }
  fi
  echo $$ >"$LOCKDIR/pid"
fi

# adb daemonizes its server on first use and the server would inherit our lock fd (9) and hold the lane lock forever: start it with fd 9 closed
[ -x "$ADB" ] && "$ADB" start-server 9>&- >/dev/null 2>&1
mkdir -p "$RUN_DIR" 2>/dev/null; PIDS="$RUN_DIR/pids"; mkdir -p "$PIDS"; STARTED_EMU=0; CHILD=""
cleanup() {
  # 2026-10-02: teardown FIRST (frees the CPU the emulator burns), ignore further signals so it always completes, then the janitor
  trap '' INT TERM HUP
  [ -n "${WD:-}" ] && kill_tree "$WD" TERM            # the overall-timeout watchdog (own session: its sleep dies with it)
  [ -n "${CHILD:-}" ] && kill_tree "$CHILD" TERM   # a runner/build still in flight (own session)
  stop_appium "$PIDS/appium.pid"
  stop_emulator "$PIDS/emu.pid"
  [ "$STARTED_EMU" = 1 ] && stop_adb_if_idle
  # verified post-run process check: anything still carrying our avd / appium port is killed and reported (teardown.json + log line)
  DL_CHECK_ADB="$([ "$STARTED_EMU" = 1 ] && echo 1)" verify_teardown "$RUN_DIR/teardown.json" "$PIDS"
  run_janitor post
  # keep the last 14 runs; videos/logcats only exist for failures so this stays small
  [ -n "$LOCKDIR" ] && rm -rf "$LOCKDIR"
  ls -1dt "$STATE"/runs/*/ 2>/dev/null | tail -n +15 | while IFS= read -r d; do rm -rf "$d"; done
  find "$STATE/apk" -name '*.apk' -mtime +14 -delete 2>/dev/null
  # a signal/overall-timeout abort never reached a verdict: say so (UNVERIFIED), never leave the night without a line
  if [ -n "${DL_ABORTED:-}" ] && [ -z "$REPORTED" ]; then report_infra "run aborted (overall ${DL_OVERALL_TIMEOUT}s cap hit or signal) - partial result discarded"; fi
}
JANITOR=""   # path of the extracted e2e_janitor.py once we have it; the post-run sweep happens in cleanup() so aborts are covered too
run_janitor() {  # $1 = pre|post. Best effort: puts the two staging test accounts back to canonical state through the public API.
  [ -n "$JANITOR" ] && [ -f "$JANITOR" ] || return 0
  E2E_STAGING_API="$API_BASE" E2E_STAGING_PREMIUM_PASSWORD="${CHICK_PREMIUM_PASSWORD:-}" E2E_STAGING_FREE_PASSWORD="${CHICK_PASSWORD:-}" \
    dl_timeout 300 "$PY" "$JANITOR" --env staging >"$RUN_DIR/janitor_$1.log" 2>&1 9>&-
}
trap cleanup EXIT
trap 'DL_ABORTED=1; exit 0' INT TERM HUP
# 2026-10-02 hard overall cap: the whole run (build + boot + specs + teardown) can never exceed DL_OVERALL_TIMEOUT. The watchdog is its own
# session (so its sleep dies with it) and signals this shell; every long phase below is a background+wait or has its own timeout so the trap fires.
DL_OVERALL_TIMEOUT="${DL_OVERALL_TIMEOUT:-6000}"; WD=""
"${DL_SETSID[@]}" bash -c 'sleep "$1"; kill -TERM "$2" 2>/dev/null' dl-watchdog "$DL_OVERALL_TIMEOUT" "$$" >/dev/null 2>&1 9>&- &
WD=$!

[ -n "$PY" ] || { dl_log "no python3"; exit 0; }
case "$REPO" in *[!A-Za-z0-9_.-]*|"") report_infra "bad repo name"; exit 0 ;; esac
REPO_PATH="${DL_REPO_DIR:-$OVN/repos/$REPO}"
[ -d "$REPO_PATH/.git" ] || [ -f "$REPO_PATH/.git" ] || { report_infra "repo clone not found: $REPO_PATH"; exit 0; }

# --- preflight ---------------------------------------------------------------------------------------------------------------
# 2026-10-02: KVM first and explicit: without it an x86_64 emulator is unusably slow, so do not build or boot anything (no CPU burned) and
# say exactly what the human must run. UNVERIFIED, never PASS/FAIL.
if ! kvm_ok; then
  if [ -e /dev/kvm ]; then kvm_why="/dev/kvm exists but user $(id -un) has no read/write access in this session"; else kvm_why="no /dev/kvm device (enable VT-x/AMD-V and load the kvm module)"; fi
  report_infra "KVM unavailable: $kvm_why. One human step, no reboot: run  sudo usermod -aG kvm $(id -un)  on this host, then use a NEW login/cron session"
  exit 0
fi
"$HERE/setup_emulator.sh" --check >"$RUN_DIR/setup_check.json" 2>"$RUN_DIR/setup_check.err" || {
  report_infra "lane not provisioned: $(tr '\n' ';' <"$RUN_DIR/setup_check.err" | cut -c1-250)"; exit 0; }

CREDS="${DL_CREDS:-$HOME/.config/qa-devicelane/staging.env}"
[ -r "$CREDS" ] || { report_infra "staging test-account file missing ($CREDS)"; exit 0; }
set -a; . "$CREDS"; set +a
export CHICK_API_BASE="${CHICK_API_BASE:-$API_BASE}"
[ -n "${CHICK_EMAIL:-}" ] && [ -n "${CHICK_PASSWORD:-}" ] || { report_infra "CHICK_EMAIL/CHICK_PASSWORD not set in creds file"; exit 0; }

[ -n "${CHICK_PREMIUM_EMAIL:-}" ] && [ -n "${CHICK_PREMIUM_PASSWORD:-}" ] || { report_infra "CHICK_PREMIUM_EMAIL/CHICK_PREMIUM_PASSWORD not set in creds file (premium specs need the staging premium account)"; exit 0; }

code="$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$API_BASE/health" 2>/dev/null)"
[ "$code" = 200 ] || { report_infra "staging backend /health returned ${code:-000} (backend down - not an app result)"; exit 0; }
for who in free premium; do
  if [ "$who" = free ]; then e="$CHICK_EMAIL"; p="$CHICK_PASSWORD"; else e="${CHICK_PREMIUM_EMAIL:-}"; p="${CHICK_PREMIUM_PASSWORD:-}"; fi
  [ -n "$e" ] || continue
  lc="$(printf '{"email":"%s","password":"%s"}' "$e" "$p" | curl -s -m 20 -o /dev/null -w '%{http_code}' -X POST "$API_BASE/api/auth/login" \
        -H 'Content-Type: application/json' --data-binary @- 2>/dev/null)"
  [ "$lc" = 200 ] || { report_infra "staging $who test account login returned ${lc:-000} (account/backend problem - not an app result)"; exit 0; }
done

# --- build -------------------------------------------------------------------------------------------------------------------
# own session + background/wait: a SIGTERM to us is handled immediately (bash defers traps while a foreground child runs)
"${DL_SETSID[@]}" "$HERE/build_apk.sh" --repo-dir "$REPO_PATH" --ref "$REF" --api-base "$API_BASE" --out "$STATE" >"$RUN_DIR/build.out" 2>"$RUN_DIR/build.err" 9>&- &
CHILD=$!; wait "$CHILD"; CHILD=""
BJ="$(tail -1 "$RUN_DIR/build.out" 2>/dev/null)"
case "$BJ" in *'"ok":true'*) ;; *) report_infra "apk build/prep failed: $(echo "$BJ" | cut -c1-120) $(tail -2 "$RUN_DIR/build.err" | tr '\n' ' ' | cut -c1-200)"; exit 0 ;; esac
APK="$("$PY" -c 'import json,sys; print(json.loads(sys.argv[1])["apk"])' "$BJ")"
E2E="$("$PY" -c 'import json,sys; print(json.loads(sys.argv[1])["e2e_dir"])' "$BJ")"
SHA="$("$PY" -c 'import json,sys; print(json.loads(sys.argv[1])["sha"])' "$BJ")"
BUILD_S="$("$PY" -c 'import json,sys; print(json.loads(sys.argv[1])["build_seconds"])' "$BJ")"

# --- emulator + appium -------------------------------------------------------------------------------------------------------
STARTED_EMU=1
start_emulator "$PIDS/emu.pid" "$RUN_DIR/emulator.log"; rc=$?
if [ "$rc" = 5 ] || [ "$rc" = 6 ]; then   # 2026-10-02 retry-once-then-report: a boot timeout/early exit gets exactly one more attempt (not kvm/binary problems)
  dl_log "emulator boot failed (rc=$rc): one retry"; stop_emulator "$PIDS/emu.pid"
  start_emulator "$PIDS/emu.pid" "$RUN_DIR/emulator.retry.log"; rc=$?
fi
[ "$rc" = 0 ] || { report_infra "emulator did not boot after retry (rc=$rc; kvm/cpuset/image problem - see $RUN_DIR/emulator*.log)"; exit 0; }
BOOT_S="${DL_BOOT_SECONDS:-0}"
dl_timeout 240 "$ADB" -s "$DL_SERIAL" install -r -d -g "$APK" >"$RUN_DIR/install.log" 2>&1 || { report_infra "adb install failed: $(tail -1 "$RUN_DIR/install.log" | cut -c1-150)"; exit 0; }
"$ADB" -s "$DL_SERIAL" shell pm clear com.chickadeestreams.iptv >/dev/null 2>&1
# a screen that times out mid-run turns every later spec into a bogus "login failed": keep it awake, unlock, and drop animations
"$ADB" -s "$DL_SERIAL" shell svc power stayon true >/dev/null 2>&1
"$ADB" -s "$DL_SERIAL" shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
"$ADB" -s "$DL_SERIAL" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" -s "$DL_SERIAL" shell wm dismiss-keyguard >/dev/null 2>&1
start_appium "$PIDS/appium.pid" "$RUN_DIR/appium.log" || { report_infra "appium did not start (see $RUN_DIR/appium.log)"; exit 0; }
restart_cmd="bash -c '. \"$HERE/lane_env.sh\"; stop_appium \"$PIDS/appium.pid\"; start_appium \"$PIDS/appium.pid\" \"$RUN_DIR/appium.log\"'"

# --- staging data: canonical baseline, then the extra data the suite assumes (cleaned again by the post-run janitor) -------------
if [ -z "${DL_NO_JANITOR:-}" ] && git -C "$REPO_PATH" show "$SHA:scripts/e2e_janitor.py" >"$RUN_DIR/e2e_janitor.py" 2>/dev/null; then JANITOR="$RUN_DIR/e2e_janitor.py"; fi
run_janitor pre
dl_timeout 300 "$PY" "$HERE/seed_data.py" >"$RUN_DIR/seed.json" 2>"$RUN_DIR/seed.err" 9>&-
NORETRY="$("$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import lane_report; print(",".join(sorted(lane_report.load_quarantine())))' "$HERE" 2>/dev/null)"

# --- run ---------------------------------------------------------------------------------------------------------------------
"${DL_SETSID[@]}" "$PY" "$HERE/lane_runner.py" --e2e-dir "$E2E" --serial "$DL_SERIAL" --out-dir "$RUN_DIR/specs" --specs "$SPECS" --adb "$ADB" \
    --node "${DL_NODE:-$(command -v node || echo node)}" --appium-port "$DL_APPIUM_PORT" --appium-restart-cmd "$restart_cmd" \
    --no-retry "$NORETRY" --spec-timeout "${DL_SPEC_TIMEOUT:-420}" --max-seconds "${DL_MAX_SECONDS:-4200}" ${DL_NO_VIDEO:+--no-video} >"$RUN_DIR/runner.out" 2>"$RUN_DIR/runner.err" 9>&- &
CHILD=$!; wait "$CHILD"; CHILD=""
if [ ! -s "$RUN_DIR/specs/results.json" ]; then report_infra "lane_runner produced no results ($(tail -1 "$RUN_DIR/runner.err" | cut -c1-150))"; exit 0; fi

"$PY" "$HERE/lane_report.py" results --results "$RUN_DIR/specs/results.json" --sha "$SHA" --run-dir "$RUN_DIR" \
    --boot-seconds "$BOOT_S" --build-seconds "$BUILD_S" $NOREC
REPORTED=1
exit 0
