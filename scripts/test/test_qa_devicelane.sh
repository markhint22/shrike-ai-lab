#!/usr/bin/env bash
# Tests for qa/device_lane/ (S11, advisory Android device lane). Hermetic: no real emulator, no network, no real backend.
# Runs the REAL entry points (run_nightly.sh, setup_emulator.sh, build_apk.sh) by absolute path AND relative path from
# scripts/overnight-queue, under `env -i` with a minimal PATH, against fakes (adb, emulator, appium, node, gradlew, a local
# HTTP "staging backend") that live in a temp dir.
set -uo pipefail
if [ -n "${DL_XTRACE:-}" ]; then exec 5>/tmp/qa-dl-xtrace.log; BASH_XTRACEFD=5; set -x; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/ntfy_guard.sh"
ROOT="$(cd "$HERE/../.." && pwd)"                       # scripts/overnight-queue
LANE="$ROOT/qa/device_lane"
[ -f "$LANE/run_nightly.sh" ] || { echo "qa/device_lane not found"; exit 2; }
PY="$(command -v python3.12 || command -v python3)"
pass=0; fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
b() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

PRE_BUILD_DIRS="$(ls -d /tmp/qa-dl-build.* 2>/dev/null)"   # a real lane run may be building concurrently; only NEW leftovers count
T="$(mktemp -d /tmp/qa-dl-test.XXXXXX)"
SERVER_PIDS=""
# 2026-10-02: per-run random emulator console port (even) and AVD name, like the appium port: a fixed 5598 + the default qa_api34 AVD made two
# concurrent suite runs (run_all.sh + test-watch) - or a suite run next to a real lane run - collide on emulator-$EMU_PORT / each other's AVD sweep.
EMU_PORT=$((41000 + 2 * (RANDOM % 4000))); TAVD="qa_api34_t$$"
cleanup() { for p in $SERVER_PIDS; do kill "$p" 2>/dev/null; done; [ -f "$T/adbd.pid" ] && kill "$(cat "$T/adbd.pid")" 2>/dev/null; pkill -f "$T/fake/" 2>/dev/null; [ -n "${DL_KEEP:-}" ] && echo "kept $T" >&2 || rm -rf "$T"; }
trap cleanup EXIT
FAKE="$T/fake"; mkdir -p "$FAKE" "$T/home" "$T/ovn/state"
SECRET="Sup3r-Secret-Pass-9431"
BADSECRET="wrong-pass"

# ---------- fakes ----------------------------------------------------------------------------------------------------------
# adb: state in $T/emu_up (device present) and $T/adb.log
cat >"$FAKE/adb" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$T/adb.log"
[ "\$1" = "-s" ] && shift 2
case "\$1" in
  start-server) { [ -f "$T/adbd.pid" ] && kill -0 "\$(cat "$T/adbd.pid")" 2>/dev/null; } || { sleep 3000 >/dev/null 2>&1 & echo \$! >"$T/adbd.pid"; }; exit 0 ;;
  devices) { [ -f "$T/adbd.pid" ] && kill -0 "\$(cat "$T/adbd.pid")" 2>/dev/null; } || { sleep 3000 >/dev/null 2>&1 & echo \$! >"$T/adbd.pid"; }
           echo "List of devices attached"; [ -f "$T/emu_up" ] && printf 'emulator-$EMU_PORT\tdevice\n'; exit 0 ;;
  kill-server) echo kill-server >>"$T/adb.killed"; [ -f "$T/adbd.pid" ] && kill "\$(cat "$T/adbd.pid")" 2>/dev/null; rm -f "$T/adbd.pid"; exit 0 ;;
  emu) rm -f "$T/emu_up"; [ -f "$T/emu.pid" ] && kill "\$(cat "$T/emu.pid")" 2>/dev/null; exit 0 ;;
  install) [ -f "$T/install_fail" ] && { echo "Failure [INSTALL_FAILED_NO_MATCHING_ABIS]"; exit 1; }; echo Success; exit 0 ;;
  logcat) if [ "\$2" = "-d" ] && [ -f "$T/crash" ]; then echo "E AndroidRuntime: FATAL EXCEPTION: main"; echo "E AndroidRuntime: Process: com.chickadeestreams.iptv, PID: 42"; fi
          echo "logline token=\$(cat "$T/secret" 2>/dev/null)"; exit 0 ;;
  pull) printf 'fakevideo' > "\$3"; exit 0 ;;
  shell) case "\$2" in
           getprop) echo 1 ;;
           screenrecord) sleep 1 ;;
           *) : ;; esac; exit 0 ;;
esac
exit 0
EOF
# emulator: marks the device up (unless FAKE_EMU_NOBOOT), records its pid, then lives until killed
cat >"$FAKE/emulator" <<EOF
#!/usr/bin/env bash
echo \$\$ >"$T/emu.pid"
echo "\$@" >"$T/emu.args"; echo x >>"$T/emu.starts"
[ -f "$T/emu_noboot" ] || touch "$T/emu_up"
exec sleep 3000
EOF
# appium: "driver list --installed" answers; otherwise a tiny http server on --port
cat >"$FAKE/appium" <<EOF
#!/usr/bin/env bash
if [ "\$1" = driver ]; then echo "- uiautomator2@8.7.0 [installed (npm)]"; exit 0; fi
port=4733; while [ \$# -gt 0 ]; do [ "\$1" = --port ] && port="\$2"; shift; done
echo \$\$ >"$T/appium.pid"; echo x >>"$T/appium.starts"
exec $PY -c "
import http.server,socketserver,sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s): s.send_response(200); s.end_headers(); s.wfile.write(b'{}')
    def log_message(s,*a): pass
socketserver.TCPServer.allow_reuse_address=True
socketserver.TCPServer(('127.0.0.1',\$port),H).serve_forever()
"
EOF
# node: a "spec" is a bash script (the fake e2e tests/*.test.mjs); node just runs it
cat >"$FAKE/node" <<'EOF'
#!/usr/bin/env bash
exec bash "$@"
EOF
printf '#!/bin/sh\necho "openjdk 17"\n' >"$FAKE/java"
chmod +x "$FAKE"/*
# fake staging backend: /health 200; /api/auth/login 200 only for the right password
cat >"$FAKE/backend.py" <<EOF
import http.server,socketserver,sys,json
SECRET="$SECRET"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        s.send_response(200); s.send_header('Content-Type','application/json'); s.end_headers(); s.wfile.write(b'{"status":"ok"}')
    def do_POST(s):
        n=int(s.headers.get('Content-Length','0')); body=s.rfile.read(n).decode()
        good=('"password":"%s"'%SECRET) in body
        s.send_response(200 if good else 401); s.end_headers(); s.wfile.write(b'{}')
    def log_message(s,*a): pass
socketserver.TCPServer.allow_reuse_address=True
socketserver.TCPServer(('127.0.0.1',int(sys.argv[1])),H).serve_forever()
EOF
PORT_BACKEND=$((20000 + RANDOM % 20000)); PORT_APPIUM=$((PORT_BACKEND + 1))
$PY "$FAKE/backend.py" "$PORT_BACKEND" >/dev/null 2>&1 & SERVER_PIDS="$SERVER_PIDS $!"
sleep 1

# fake SDK tree so `setup_emulator.sh --check` is satisfied
SDK="$T/home/android-sdk"
mkdir -p "$SDK/emulator" "$SDK/platform-tools" "$SDK/system-images/android-34/google_apis/x86_64" "$T/home/qa-avd/$TAVD.avd" "$T/home/qa-tools/appium/node_modules/.bin"
cp "$FAKE/emulator" "$SDK/emulator/emulator"; cp "$FAKE/adb" "$SDK/platform-tools/adb"; : >"$SDK/system-images/android-34/google_apis/x86_64/system.img"
: >"$T/home/qa-avd/$TAVD.ini"; : >"$T/home/qa-avd/$TAVD.avd/config.ini"
cp "$FAKE/appium" "$T/home/qa-tools/appium/node_modules/.bin/appium"; chmod +x "$SDK"/emulator/emulator "$SDK"/platform-tools/adb "$T/home/qa-tools/appium/node_modules/.bin/appium"

# fake iptv_apps repo: gradlew + build.gradle.kts with the prod URL + an e2e suite of bash "specs"
REPO="$T/repo_iptv"; mkdir -p "$REPO/iptv-android/app" "$REPO/iptv-android/e2e/tests"
(
  cd "$REPO" && git init -q . && git config user.email t@t && git config user.name t
  cat >iptv-android/app/build.gradle.kts <<'KTS'
android { defaultConfig { buildConfigField("String", "API_BASE_URL", "\"https://api.chickadeestream.com\"") }
  buildTypes { release { buildConfigField("String", "API_BASE_URL", "\"https://api.chickadeestream.com\"") } } }
KTS
  cat >iptv-android/gradlew <<EOF
#!/usr/bin/env bash
# 2026-10-02: gradle_slow flag = a hung/long gradle (marker argv0) for the abort-during-build test
[ -f "$T/gradle_slow" ] && exec -a "fake-gradle-$TAVD" sleep 3000
mkdir -p app/build/outputs/apk/googleTv/debug && echo apk > app/build/outputs/apk/googleTv/debug/app-googleTv-debug.apk
cp app/build.gradle.kts "$T/built_gradle.kts"; exit 0
EOF
  chmod +x iptv-android/gradlew
  cat >iptv-android/e2e/helpers.mjs <<'H'
export const PREMIUM_EMAIL = 'premium.e2e@chickadeestream.com'
export const PREMIUM_PASSWORD = 'PremiumPass123'
H
  echo '{"name":"x","version":"1.0.0"}' >iptv-android/e2e/package.json
  cat >iptv-android/e2e/tests/_fixture_creds.mjs <<'J'
const FREE = { email: 'shots@chickadeestream.com', password: "ShotsPass123" }
const PREMIUM = { email: 'premium.e2e@chickadeestream.com', password: 'PremiumPass123' }
const note = 'contact shots@chickadeestream.com.example for help'
J
  for s in alpha beta gamma; do printf '#!/usr/bin/env bash\necho "running %s"\nexit 0\n' "$s" >"iptv-android/e2e/tests/$s.test.mjs"; done
  git add -A && git commit -qm init && git branch -M develop && git update-ref refs/remotes/origin/develop HEAD
)
mkdir -p "$T/ovn/repos"; ln -s "$REPO" "$T/ovn/repos/iptv_apps"
printf 'CHICK_EMAIL=free@example.test\nCHICK_PASSWORD=%s\nCHICK_PREMIUM_EMAIL=prem@example.test\nCHICK_PREMIUM_PASSWORD=%s\n' "$SECRET" "$SECRET" >"$T/creds.env"
chmod 600 "$T/creds.env"; echo "$SECRET" >"$T/secret"

set_spec() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$REPO/iptv-android/e2e/tests/$1.test.mjs"; (cd "$REPO" && git add -A >/dev/null 2>&1; git commit -qm "spec $1" --allow-empty >/dev/null 2>&1; git update-ref refs/remotes/origin/develop HEAD); }
reset_specs() { for s in alpha beta gamma; do set_spec "$s" "echo running $s; exit 0"; done; rm -f "$T/emu.starts" "$T/crash" "$T/install_fail" "$T/emu_noboot" "$T/emu_up" "$T/emu.pid" "$T/appium.pid" "$T/appium.starts" "$T/flaky.marker"; rm -rf "$T/ovn/state/qa_devicelane" "$T/ovn/state/qa_shadow"; }

# run the lane exactly as cron would: env -i, minimal PATH, cwd = $HOME-like dir, NTFY_SERVER set
lane() {  # lane <script-invocation> [extra env KEY=VAL ...] -- [args]
  local script="$1"; shift; local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; [ "${1:-}" = -- ] && shift
  ( cd "${LANE_CWD:-$T/home}" && env -i HOME="$T/home" PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$T/ovn" \
      DL_EXTRA_PATH="$FAKE" DL_NODE="$FAKE/node" DL_CREDS="$T/creds.env" DL_API_BASE="http://127.0.0.1:$PORT_BACKEND" \
      DL_APPIUM_PORT="$PORT_APPIUM" DL_EMU_PORT=$EMU_PORT DL_AVD=$TAVD DL_FAKE_KVM=1 DL_BOOT_TIMEOUT=20 DL_SPEC_TIMEOUT=30 DL_NO_VIDEO= ${DL_TRACE:+DL_TRACE=$DL_TRACE} \
      ${envs[@]+"${envs[@]}"} ${DL_BASHX:+/usr/bin/env bash -x} "$script" "$@" 2>"$T/stderr.txt" )
}
last_json() { tail -1; }
field() { $PY -c 'import json,sys; d=json.loads(sys.stdin.read().strip().splitlines()[-1]); v=d
for k in sys.argv[1].split("."): v=v[k]
print(v if not isinstance(v,(list,dict)) else json.dumps(v))' "$1"; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
# gone <pid>: the process no longer exists OR is only a zombie. `! kill -0` is wrong for a killed CHILD of this shell: it stays defunct (and kill -0 succeeds)
# until bash reaps it, which races with the probe under load (2026-10-08: "post-run sweep killed the straggler" failed one full run and passed the next).
gone() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -z "$s" ] || [ "${s#Z}" != "$s" ]; }
leftovers() { # 1 if any fake emulator/appium we started is still alive
  if alive "$T/emu.pid" || alive "$T/appium.pid" || pgrep -f "$T/home/qa-tools/appium/node_modules/.bin/appium" >/dev/null 2>&1 || pgrep -f "$T/home/android-sdk/emulator/emulator" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
export ANDROID_HOME="$SDK"   # setup_emulator/lane_env pick this up through env -i via QA_DL_HOME instead (below)

# NOTE: with env -i the lane derives everything from HOME (=$T/home): ~/android-sdk, ~/qa-avd, ~/qa-tools/appium.
RN="$LANE/run_nightly.sh"

echo "== 1. benign: all specs pass -> PASS (absolute path, cron-like env)"
reset_specs
out="$(lane "$RN" -- )"; rc=$?
ok "exit 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "verdict PASS" "$([ "$(echo "$out" | field verdict)" = PASS ] && echo 1 || echo 0)"
ok "gate=devicelane, advisory flag set, mode shadow" "$([ "$(echo "$out" | field gate)" = devicelane ] && [ "$(echo "$out" | field details.advisory)" = True ] && [ "$(echo "$out" | field mode)" = shadow ] && echo 1 || echo 0)"
ok "3 specs counted as pass" "$([ "$(echo "$out" | field details.counts.pass)" = 3 ] && echo 1 || echo 0)"
ok "shadow log line written" "$([ "$(wc -l <"$T/ovn/state/qa_shadow/devicelane.jsonl" 2>/dev/null | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "history line written for flake stats" "$([ "$(wc -l <"$T/ovn/state/qa_devicelane/history.jsonl" 2>/dev/null | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "emulator + appium cleaned up on exit" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
ok "screen kept awake before the specs (stayon, no screen-off timeout, wakeup)" "$(grep -q 'svc power stayon true' "$T/adb.log" && grep -q 'screen_off_timeout' "$T/adb.log" && grep -q 'KEYCODE_WAKEUP' "$T/adb.log" && echo 1 || echo 0)"
ok "emulator launched headless with KVM accel + pinned port + swiftshader" "$(grep -q -- '-no-window' "$T/emu.args" && grep -q -- '-accel on' "$T/emu.args" && grep -q -- "-port $EMU_PORT" "$T/emu.args" && grep -q swiftshader_indirect "$T/emu.args" && echo 1 || echo 0)"
ok "APK built against the (patched) staging URL, prod URL gone from the build copy" "$(grep -q "127.0.0.1:$PORT_BACKEND" "$T/built_gradle.kts" && ! grep -q 'api.chickadeestream.com' "$T/built_gradle.kts" && echo 1 || echo 0)"
ok "the live clone was not modified (no worktree/branch/ref side effects, clean status)" "$([ -z "$(git -C "$REPO" status --porcelain)" ] && [ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "no stray build scratch dirs left in /tmp" "$([ "$(ls -d /tmp/qa-dl-build.* 2>/dev/null)" = "$PRE_BUILD_DIRS" ] && echo 1 || echo 0)"
E2E_DIR="$(ls -d "$T"/ovn/state/qa_devicelane/e2e/*/ | head -1)"
ok "scratch e2e copy has staging-capable premium creds (env-driven), repo file untouched" "$(grep -q 'CHICK_PREMIUM_EMAIL' "$E2E_DIR/helpers.mjs" && ! grep -q CHICK_PREMIUM "$REPO/iptv-android/e2e/helpers.mjs" && echo 1 || echo 0)"

[ -n "${DL_DEBUG:-}" ] && { echo "DEBUG: $out" >&2; cat "$T/stderr.txt" >&2; }
echo "== 2. same, RELATIVE path from scripts/overnight-queue"
reset_specs
out="$(cd "$ROOT" && env -i HOME="$T/home" PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$T/ovn" DL_EXTRA_PATH="$FAKE" DL_NODE="$FAKE/node" DL_CREDS="$T/creds.env" DL_API_BASE="http://127.0.0.1:$PORT_BACKEND" DL_APPIUM_PORT="$PORT_APPIUM" DL_EMU_PORT=$EMU_PORT DL_AVD=$TAVD DL_FAKE_KVM=1 DL_BOOT_TIMEOUT=20 DL_SPEC_TIMEOUT=30 qa/device_lane/run_nightly.sh 2>/dev/null)"
ok "relative path -> PASS" "$([ "$(echo "$out" | field verdict)" = PASS ] && echo 1 || echo 0)"
ok "relative path -> nothing left running" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"

E2E_DIR="$(ls -d "$T"/ovn/state/qa_devicelane/e2e/*/ | head -1)"
ok "prod account literals in specs rewritten to env lookups in the scratch copy (no fallback to prod literals)" "$(grep -q 'email: process.env.CHICK_EMAIL, password: process.env.CHICK_PASSWORD' "$E2E_DIR/tests/_fixture_creds.mjs" && grep -q 'process.env.CHICK_PREMIUM_PASSWORD' "$E2E_DIR/tests/_fixture_creds.mjs" && ! grep -q 'ShotsPass123\|PremiumPass123' "$E2E_DIR/tests/_fixture_creds.mjs" && echo 1 || echo 0)"
ok "a longer string that merely contains an account literal is left alone" "$(grep -q 'contact shots@chickadeestream.com.example' "$E2E_DIR/tests/_fixture_creds.mjs" && echo 1 || echo 0)"
ok "the repo's own spec files are untouched" "$(git -C "$REPO" show origin/develop:iptv-android/e2e/tests/_fixture_creds.mjs | grep -q 'ShotsPass123' && echo 1 || echo 0)"
echo "== 3. negative control: a spec that always fails -> FLAG, retried once, artifacts saved"
reset_specs; set_spec beta 'echo "assert failed: Menu never appeared"; exit 1'
out="$(lane "$RN" -- )"
ok "verdict FLAG (never FAIL: advisory)" "$([ "$(echo "$out" | field verdict)" = FLAG ] && echo 1 || echo 0)"
ok "details name the failed spec" "$(echo "$out" | field details.failed | grep -q beta && echo 1 || echo 0)"
RD="$(ls -d "$T"/ovn/state/qa_devicelane/runs/*/ | tail -1)"
ok "two attempts were made (retry-once)" "$([ -f "$RD/specs/beta/attempt1.log" ] && [ -f "$RD/specs/beta/attempt2.log" ] && [ ! -f "$RD/specs/beta/attempt3.log" ] && echo 1 || echo 0)"
ok "logcat saved for the failed attempt" "$([ -s "$RD/specs/beta/attempt2.logcat.txt" ] && echo 1 || echo 0)"
ok "screen recording pulled for the failed attempt" "$(ls "$RD"/specs/beta/attempt2.rec*.mp4 >/dev/null 2>&1 && echo 1 || echo 0)"
ok "passing specs keep NO logcat/video (no clutter)" "$([ ! -f "$RD/specs/alpha/attempt1.logcat.txt" ] && ! ls "$RD"/specs/alpha/*.mp4 >/dev/null 2>&1 && echo 1 || echo 0)"
ok "counts: 2 pass 1 fail" "$([ "$(echo "$out" | field details.counts.pass)" = 2 ] && [ "$(echo "$out" | field details.counts.fail)" = 1 ] && echo 1 || echo 0)"

echo "== 4. flaky: fails first, passes on retry -> FLAG (flaky), counted as flaky not failed"
reset_specs; set_spec gamma "if [ ! -f $T/flaky.marker ]; then touch $T/flaky.marker; echo 'socket hang up'; exit 1; fi; exit 0"
out="$(lane "$RN" -- )"
ok "verdict FLAG" "$([ "$(echo "$out" | field verdict)" = FLAG ] && echo 1 || echo 0)"
ok "gamma reported flaky, not failed" "$(echo "$out" | field details.flaky | grep -q gamma && [ "$(echo "$out" | field details.failed)" = '[]' ] && echo 1 || echo 0)"
ok "appium restarted after a suspected instrumentation crash (socket hang up)" "$([ "$(wc -l <"$T/appium.starts" | tr -d ' ')" -ge 2 ] && echo 1 || echo 0)"
ok "nothing left running" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"

echo "== 5. app crash in logcat during a PASSING spec -> FLAG"
reset_specs; touch "$T/crash"
out="$(lane "$RN" -- )"
ok "verdict FLAG with crash list" "$([ "$(echo "$out" | field verdict)" = FLAG ] && [ "$(echo "$out" | field details.app_crash_or_anr)" != '[]' ] && echo 1 || echo 0)"

echo "== 6. every spec fails -> UNVERIFIED (environment suspected), not FLAG/FAIL"
reset_specs; for s in alpha beta gamma; do set_spec $s 'echo "login failed"; exit 1'; done
out="$(lane "$RN" -- )"
ok "verdict UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo 1 || echo 0)"

echo "== 7. skipped specs (exit 2) are not failures"
reset_specs; set_spec beta 'echo skipped; exit 2'
out="$(lane "$RN" -- )"
ok "PASS with a skip" "$([ "$(echo "$out" | field verdict)" = PASS ] && [ "$(echo "$out" | field details.counts.skip)" = 1 ] && [ "$(echo "$out" | field details.counts.pass)" = 2 ] && echo 1 || echo 0)"

echo "== 8. spec timeout -> killed, reported as failed (FLAG)"
reset_specs; set_spec alpha "echo \$\$ >>$T/spec.pids; exec sleep 61"
out="$(lane "$RN" DL_SPEC_TIMEOUT=3 -- )"
ok "FLAG, alpha listed as failed" "$([ "$(echo "$out" | field verdict)" = FLAG ] && echo "$out" | field details.failed | grep -q alpha && echo 1 || echo 0)"
stray=0; for p in $(cat "$T/spec.pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && stray=1; done
ok "timeout kills the spec process (both attempts; none left sleeping)" "$([ -s "$T/spec.pids" ] && [ $stray = 0 ] && echo 1 || echo 0)"

echo "== 9. UNVERIFIED (never PASS, never FAIL) when it could not run"
reset_specs
out="$(lane "$RN" DL_FAKE_KVM=0 -- )"
ok "no /dev/kvm access -> UNVERIFIED, exit 0, reason mentions kvm" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -qi kvm && echo 1 || echo 0)"
ok "kvm message names the exact human command (sudo usermod -aG kvm <user>), no reboot needed" "$(echo "$out" | field summary | grep -q 'sudo usermod -aG kvm' && echo "$out" | field summary | grep -q 'KVM unavailable' && echo 1 || echo 0)"
ok "no emulator booted when kvm is missing" "$([ ! -f "$T/emu.pid" ] && echo 1 || echo 0)"
reset_specs; mv "$SDK/emulator/emulator" "$SDK/emulator/emulator.off"
out="$(lane "$RN" -- )"; mv "$SDK/emulator/emulator.off" "$SDK/emulator/emulator"
ok "emulator binary missing -> UNVERIFIED (not provisioned)" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -qi 'not provisioned' && echo 1 || echo 0)"
reset_specs; touch "$T/emu_noboot"
out="$(lane "$RN" DL_BOOT_TIMEOUT=4 -- )"
ok "emulator never boots -> UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -qi 'did not boot' && echo 1 || echo 0)"
ok "a hung emulator is killed on the way out" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
ok "boot failure is retried exactly once (2 launches, then UNVERIFIED)" "$([ "$(wc -l <"$T/emu.starts" | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
reset_specs; touch "$T/install_fail"
out="$(lane "$RN" -- )"
ok "adb install failure -> UNVERIFIED, emulator cleaned up" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && [ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
reset_specs
out="$(lane "$RN" DL_API_BASE=http://127.0.0.1:9 -- )"
ok "staging backend down -> UNVERIFIED (not an app result), nothing booted" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -q '/health' && [ ! -f "$T/emu.pid" ] && echo 1 || echo 0)"
reset_specs; printf 'CHICK_EMAIL=free@example.test\nCHICK_PASSWORD=%s\nCHICK_PREMIUM_EMAIL=prem@example.test\nCHICK_PREMIUM_PASSWORD=%s\n' "$BADSECRET" "$BADSECRET" >"$T/creds_bad.env"
out="$(lane "$RN" DL_CREDS="$T/creds_bad.env" -- )"
ok "test account cannot log in -> UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -q 'login returned 401' && echo 1 || echo 0)"
ok "bad password never printed" "$(echo "$out" | grep -q "$BADSECRET" && echo 0 || echo 1)"
reset_specs
out="$(lane "$RN" DL_CREDS="$T/does-not-exist.env" -- )"
ok "missing creds file -> UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo 1 || echo 0)"
reset_specs
out="$(lane "$RN" DL_REPO_DIR="$T/nope" -- )"
ok "repo clone missing -> UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo 1 || echo 0)"
reset_specs
out="$(lane "$RN" -- --ref origin/does-not-exist)"
ok "unknown ref -> UNVERIFIED" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo 1 || echo 0)"

echo "== 10. lock contention (flock -n): a second run is a fast no-op"
reset_specs; mkdir -p "$T/ovn/state/qa_devicelane"
if PATH=/usr/bin:/bin command -v flock >/dev/null 2>&1; then
  ( exec 8>"$T/ovn/state/qa_devicelane/lane.lock"; flock 8; sleep 8 ) & HOLD=$!
else  # macOS: the lane falls back to a mkdir lock holding a live pid
  sleep 8 & HOLD=$!; mkdir "$T/ovn/state/qa_devicelane/lane.lockdir"; echo $HOLD >"$T/ovn/state/qa_devicelane/lane.lockdir/pid"
fi
sleep 1
t0=$(date +%s); out="$(lane "$RN" -- )"; t1=$(date +%s)
ok "UNVERIFIED 'another run holds the lock'" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -q 'holds the lock' && echo 1 || echo 0)"
ok "returned immediately (did not wait for the lock)" "$([ $((t1 - t0)) -lt 5 ] && echo 1 || echo 0)"
ok "no empty run dir left behind by the contended call" "$([ -z "$(ls -A "$T/ovn/state/qa_devicelane/runs" 2>/dev/null)" ] && echo 1 || echo 0)"
kill $HOLD 2>/dev/null; wait $HOLD 2>/dev/null

echo "== 11. SIGTERM mid-run still cleans up emulator + appium (idempotent cleanup)"
reset_specs; set_spec alpha 'sleep 40'
( lane "$RN" DL_SPEC_TIMEOUT=60 -- >/dev/null 2>&1 ) & BG=$!
for _ in $(seq 1 40); do [ -f "$T/appium.pid" ] && alive "$T/emu.pid" && break; sleep 0.5; done
ok "emulator + appium were up before the kill" "$(alive "$T/emu.pid" && alive "$T/appium.pid" && echo 1 || echo 0)"
RP="$(pgrep -f 'device_lane/run_nightly.sh' | head -1)"; kill -TERM "$RP" 2>/dev/null; wait $BG 2>/dev/null; sleep 2
ok "after SIGTERM: emulator + appium gone" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
pkill -f 'sleep 40' 2>/dev/null

echo "== 12. secrets never reach saved output"
reset_specs; set_spec alpha "echo password is $SECRET; exit 1"
touch "$T/crash"
out="$(lane "$RN" -- )"
ok "stdout verdict has no secret" "$(echo "$out" | grep -q "$SECRET" && echo 0 || echo 1)"
ok "stderr of the wrapper has no secret" "$(grep -q "$SECRET" "$T/stderr.txt" && echo 0 || echo 1)"
[ -n "${DL_DEBUG:-}" ] && grep -rlF --exclude-dir=e2e "$SECRET" "$T/ovn/state" >&2
ok "no saved log/logcat/json under state contains the secret" "$(grep -rqF --exclude-dir=e2e "$SECRET" "$T/ovn/state" && echo 0 || echo 1)"
ok "redaction marker present where the spec printed it" "$(grep -rq '<redacted>' "$T/ovn/state/qa_devicelane/runs" && echo 1 || echo 0)"

echo "== 12b. redaction by shape (OkHttp bearer/JWT/JSON bodies in logcat)"
shape_out="$($PY - "$LANE" <<'EOF2'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("lane_runner", sys.argv[1] + "/lane_runner.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIyIiwiZXhwIjoxNzkwOTAwNTQzfQ.Gt6qDntXlEERMgEXll2zb8jn6snRGTxvmjDyvY"
t = ('I okhttp: Authorization: Bearer %s\nI okhttp: {"access_token":"abcdef123456","refresh_token":"zzzzzz999999","email":"a@b.c"}\n'
     'I okhttp: {"email":"a@b.c","password":"hunter2hunter2"}\nGET /x?token=qwerty123456&y=1\nplain eyJhbGciOiJIUzI1NiIsInR5cCI6.eyJzdWIiOiIyIiwiZXhw.Gt6qDntXlEERMgEXll2z line') % jwt
r = m.redact(t, [])
bad = [x for x in (jwt, "abcdef123456", "zzzzzz999999", "hunter2hunter2", "qwerty123456") if x in r]
print("BAD" if bad else "CLEAN", "email-kept" if "a@b.c" in r else "email-lost")
EOF2
)"
ok "bearer tokens, JWTs, token/password JSON fields and ?token= are redacted" "$([ "${shape_out%% *}" = CLEAN ] && echo 1 || echo 0)"
ok "non-secret fields (email) survive redaction" "$([ "${shape_out##* }" = email-kept ] && echo 1 || echo 0)"
echo "== 13. setup_emulator.sh: --check benign + negative, idempotent"
SE="$LANE/setup_emulator.sh"
se() { ( cd "$T/home" && env -i HOME="$T/home" DL_AVD=$TAVD PATH=/usr/bin:/bin DL_EXTRA_PATH="$FAKE" DL_FAKE_KVM=1 PATH=/usr/bin:/bin:"$FAKE" "$SE" "$@" 2>/dev/null ); }
out="$(se --check)"; rc=$?
ok "provisioned fake lane -> ready=true rc 0" "$([ $rc = 0 ] && [ "$(echo "$out" | field ready)" = True ] && echo 1 || echo 0)"
out="$(se --check)"; rc=$?
ok "re-run is idempotent" "$([ $rc = 0 ] && [ "$(echo "$out" | field ready)" = True ] && echo 1 || echo 0)"
rm -rf "$SDK/system-images"; out="$(se --check)"; rc=$?
ok "missing system image -> ready=false rc 1, names the package" "$([ $rc = 1 ] && [ "$(echo "$out" | field ready)" = False ] && echo "$out" | field missing | grep -q 'system-images' && echo 1 || echo 0)"
mkdir -p "$SDK/system-images/android-34/google_apis/x86_64"; : >"$SDK/system-images/android-34/google_apis/x86_64/system.img"
out="$( ( cd "$T/home" && env -i HOME="$T/home" DL_AVD=$TAVD PATH=/usr/bin:/bin:"$FAKE" DL_FAKE_KVM=0 "$SE" --check 2>/dev/null ) )"; rc=$?
ok "no kvm -> ready=false and a clear usermod hint" "$([ $rc = 1 ] && echo "$out" | field missing | grep -q 'usermod -aG kvm' && echo 1 || echo 0)"
( cd "$ROOT" && env -i HOME="$T/home" DL_AVD=$TAVD PATH=/usr/bin:/bin:"$FAKE" DL_FAKE_KVM=1 qa/device_lane/setup_emulator.sh --check >/dev/null 2>&1 ); rc=$?
ok "relative-path invocation works" "$([ $rc = 0 ] && echo 1 || echo 0)"
( cd "$T/home" && env -i HOME="$T/home" PATH=/usr/bin:/bin "$SE" --bogus >/dev/null 2>&1 ); rc=$?
ok "bad usage -> rc 2" "$([ $rc = 2 ] && echo 1 || echo 0)"

echo "== 14. build_apk.sh: cache + unpatchable layout"
BA="$LANE/build_apk.sh"
ba() { ( cd "$T/home" && env -i HOME="$T/home" PATH=/usr/bin:/bin ANDROID_HOME="$SDK" "$BA" "$@" 2>/dev/null ); }
rm -rf "$T/bout"
j1="$(ba --repo-dir "$REPO" --ref origin/develop --api-base http://x.test --out "$T/bout" | tail -1)"
j2="$(ba --repo-dir "$REPO" --ref origin/develop --api-base http://x.test --out "$T/bout" | tail -1)"
ok "first build ok, uncached" "$(echo "$j1" | grep -q '"cached":false' && echo 1 || echo 0)"
ok "second build is served from the sha-keyed cache" "$(echo "$j2" | grep -q '"cached":true' && echo 1 || echo 0)"
j3="$(ba --repo-dir "$REPO" --ref origin/develop --api-base http://other.test --out "$T/bout" | tail -1)"
ok "a different API base is a different cache key" "$(echo "$j3" | grep -q '"cached":false' && echo 1 || echo 0)"
j4="$(ba --repo-dir "$REPO" --ref nope --api-base http://x.test --out "$T/bout"; echo "rc=$?")"
ok "bad ref -> rc 3 + ok:false JSON" "$(echo "$j4" | grep -q '"ok":false' && echo "$j4" | grep -q 'rc=3' && echo 1 || echo 0)"
# gradle layout without the prod URL -> must refuse (a build that silently hits prod is the dangerous failure)
set_spec alpha 'exit 0'
(cd "$REPO" && echo 'android {}' >iptv-android/app/build.gradle.kts && git add -A && git commit -qm nopatch && git update-ref refs/remotes/origin/develop HEAD)
j5="$(ba --repo-dir "$REPO" --ref origin/develop --api-base http://x.test --out "$T/bout2"; echo "rc=$?")"
ok "unpatchable API_BASE_URL -> refuses to build (never silently tests prod)" "$(echo "$j5" | grep -q '"ok":false' && echo "$j5" | grep -q 'rc=4' && echo 1 || echo 0)"

echo "== 15. flake_stats.py"
FS="$LANE/flake_stats.py"
H="$T/hist.jsonl"
$PY - "$H" <<'EOF'
import json,sys
rows=[]
for i in range(6):
    rows.append({"ts":"t%d"%i,"specs":{
        "steady.test.mjs":{"first":"pass","final":"pass"},
        "wobbly.test.mjs":{"first":"fail" if i in (1,4) else "pass","final":"flaky" if i in (1,4) else "pass"},
        "dead.test.mjs":{"first":"fail","final":"fail"},
        "absent.test.mjs":{"first":"skip","final":"skip"}}})
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
EOF
js="$($PY "$FS" --history "$H" --json)"
cls() { echo "$js" | $PY -c 'import json,sys; print(json.load(sys.stdin)["per_spec"][sys.argv[1]]["class"])' "$1"; }
ok "steady spec over 6 runs -> reliable" "$([ "$(cls steady.test.mjs)" = reliable ] && echo 1 || echo 0)"
ok "intermittent spec -> flaky" "$([ "$(cls wobbly.test.mjs)" = flaky ] && echo 1 || echo 0)"
ok "always-failing spec -> broken" "$([ "$(cls dead.test.mjs)" = broken ] && echo 1 || echo 0)"
ok "always-skipped spec -> skipped" "$([ "$(cls absent.test.mjs)" = skipped ] && echo 1 || echo 0)"
ok "overall flake rate = first-attempt failures / non-skipped spec-runs ((2+6)/18=44.44)" "$([ "$(echo "$js" | $PY -c 'import json,sys; print(json.load(sys.stdin)["flake_rate_pct"])')" = 44.44 ] && echo 1 || echo 0)"
ok "missing history file -> empty stats, no crash" "$($PY "$FS" --history "$T/none.jsonl" >/dev/null 2>&1 && echo 1 || echo 0)"

echo "== 16. lane_report: advisory contract (never FAIL)"
LR="$LANE/lane_report.py"
echo '{"counts":{"fail":2},"seconds":1,"specs":[{"spec":"a","status":"fail","attempts":[{"status":"fail"},{"status":"fail"}]},{"spec":"b","status":"pass","attempts":[{"status":"pass"}]},{"spec":"c","status":"pass","attempts":[{"status":"pass"}]},{"spec":"d","status":"fail","attempts":[{"status":"fail"},{"status":"fail"}]}]}' >"$T/res.json"
v="$(OVN_DIR="$T/ovn2" $PY "$LR" results --results "$T/res.json" --no-record | field verdict)"
ok "some failures -> FLAG (not FAIL)" "$([ "$v" = FLAG ] && echo 1 || echo 0)"
v="$(OVN_DIR="$T/ovn2" OVN_QA_DEVICELANE=enforce $PY "$LR" results --results "$T/res.json" --no-record | field verdict)"
ok "even in enforce mode the lane cannot FAIL" "$([ "$v" = FLAG ] && echo 1 || echo 0)"
v="$(OVN_DIR="$T/ovn2" $PY "$LR" results --results "$T/nonexistent.json" --no-record | field verdict)"
ok "unreadable results -> UNVERIFIED, exit 0" "$([ "$v" = UNVERIFIED ] && echo 1 || echo 0)"

# test 14 deliberately left the fake repo with an unpatchable build.gradle.kts; restore a patchable one for the end-to-end tests below
cat >"$REPO/iptv-android/app/build.gradle.kts" <<'KTS'
android { defaultConfig { buildConfigField("String", "API_BASE_URL", "\"https://api.chickadeestream.com\"") } }
KTS
(cd "$REPO" && git add -A >/dev/null 2>&1; git commit -qm "restore gradle" >/dev/null 2>&1; git update-ref refs/remotes/origin/develop HEAD)
echo "== 17. known-issues quarantine: expected failures never FLAG, recoveries are reported, fixture env un-quarantines"
cat >"$T/res_q.json" <<'JSON'
{"counts":{},"seconds":1,"specs":[
 {"spec":"favorites-screen.test.mjs","status":"fail","attempts":[{"status":"fail"}]},
 {"spec":"guide-channel-picker.test.mjs","status":"fail","attempts":[{"status":"fail"}]},
 {"spec":"b.test.mjs","status":"pass","attempts":[{"status":"pass"}]},{"spec":"c.test.mjs","status":"pass","attempts":[{"status":"pass"}]},
 {"spec":"d.test.mjs","status":"pass","attempts":[{"status":"pass"}]}]}
JSON
out="$(OVN_DIR="$T/ovn2" $PY "$LR" results --results "$T/res_q.json" --no-record)"
ok "only quarantined specs failing -> PASS (not FLAG)" "$([ "$(echo "$out" | field verdict)" = PASS ] && echo 1 || echo 0)"
ok "quarantined failures still listed with their category" "$(echo "$out" | field details.quarantined_failing | grep -q obsolete_spec && echo "$out" | field details.quarantined_failing | grep -q needs_fixture && echo 1 || echo 0)"
out="$(OVN_DIR="$T/ovn2" DL_GUIDE_MULTI_URL=http://x.test/g.xml $PY "$LR" results --results "$T/res_q.json" --no-record)"
ok "with DL_GUIDE_MULTI_URL set the guide spec is un-quarantined and its failure FLAGs" "$([ "$(echo "$out" | field verdict)" = FLAG ] && echo "$out" | field details.failed | grep -q guide-channel-picker && echo 1 || echo 0)"
sed 's/"favorites-screen.test.mjs","status":"fail","attempts":\[{"status":"fail"}\]/"favorites-screen.test.mjs","status":"pass","attempts":[{"status":"pass"}]/' "$T/res_q.json" >"$T/res_q2.json"
out="$(OVN_DIR="$T/ovn2" $PY "$LR" results --results "$T/res_q2.json" --no-record)"
ok "a quarantined spec that passes is reported as recovered" "$(echo "$out" | field details.quarantine_recovered_remove_from_known_issues | grep -q favorites-screen && echo 1 || echo 0)"
cat >"$T/res_q3.json" <<'JSON'
{"counts":{},"seconds":1,"specs":[{"spec":"zz-new.test.mjs","status":"fail","attempts":[{"status":"fail"},{"status":"fail"}]},
 {"spec":"b.test.mjs","status":"pass","attempts":[{"status":"pass"}]},{"spec":"c.test.mjs","status":"pass","attempts":[{"status":"pass"}]}]}
JSON
out="$(OVN_DIR="$T/ovn2" $PY "$LR" results --results "$T/res_q3.json" --no-record)"
ok "negative control: an UNquarantined failing spec still FLAGs" "$([ "$(echo "$out" | field verdict)" = FLAG ] && echo 1 || echo 0)"
ok "known_issues.json is valid JSON and every entry has category+reason" "$($PY -c '
import json,sys; d=json.load(open(sys.argv[1])); assert all("category" in v and "reason" in v for k,v in d.items() if not k.startswith("_"))' "$LANE/known_issues.json" && echo 1 || echo 0)"
reset_specs; set_spec favorites-screen 'echo "Drawer item Favorites not found"; exit 1'
out="$(lane "$RN" -- )"
RD="$(ls -d "$T"/ovn/state/qa_devicelane/runs/*/ | tail -1)"
ok "end to end: quarantined failing spec runs ONCE (no retry) and the run is PASS" "$([ "$(echo "$out" | field verdict)" = PASS ] && [ -f "$RD/specs/favorites-screen/attempt1.log" ] && [ ! -f "$RD/specs/favorites-screen/attempt2.log" ] && echo 1 || echo 0)"
rm -f "$REPO/iptv-android/e2e/tests/favorites-screen.test.mjs"

echo "== 18. prep_e2e: layout/text compat patches + overlay (scratch copy only)"
PE="$T/pe"; rm -rf "$PE"; mkdir -p "$PE/pages" "$PE/tests"
cat >"$PE/pages/DiscoverPage.mjs" <<'J'
const rows = [...src.matchAll(/clickable="true"[^>]*bounds="\[42,(\d+)\]\[1038,(\d+)\]"/g)]
J
cat >"$PE/tests/epg-add-source.test.mjs" <<'J'
    await page.waitForText('EPG source added. Importing data in background...', {
      timeout: 15000,
J
cat >"$PE/tests/import-functional.test.mjs" <<'J'
  const result = await add.waitForResult()
  assert(result.success, `playlist import did not report success: ${result.message}`)
  assert(result.message.startsWith('Imported '), `expected an "Imported N channel(s)" message, got: ${result.message}`)
  await nav.backToHome()
J
cat >"$PE/pages/HistoryPage.mjs" <<'J'
  async open() {
    await this.waitForText('Watch History', { timeout: 15000, msg: 'Watch History screen did not open' })
    await this.driver.pause(1500)
  }
  async isPremiumGated() {}
  async tapFirstRow() {
    const el = await this.driver.$('android=new UiSelector().className("android.widget.TextView").instance(2)')
    if (!(await el.isExisting())) return null
    const text = await el.getText()
    await el.click()
    return text
  }
J
echo "old spec" >"$PE/tests/watchlist-screen.test.mjs"
pj="$($PY "$LANE/prep_e2e.py" "$PE")"
ok "row-bounds regex now accepts the narrower (996) rows and still the old (1038) ones" "$(grep -q '\[(?:1038|996),' "$PE/pages/DiscoverPage.mjs" && echo 1 || echo 0)"
ok "regex change is matched by an actual JS regex run on a 996-wide row" "$(node -e '
const fs=require("fs"); const m=fs.readFileSync(process.argv[1],"utf8").match(/matchAll\((\/.*\/g)\)/)[1];
const re=eval(m); const t1="clickable=\"true\" x bounds=\"[42,921][996,1132]\""; const t2="clickable=\"true\" bounds=\"[42,9][1038,10]\"";
process.exit([...t1.matchAll(re)].length===1 && [...t2.matchAll(re)].length===1 ? 0 : 1)' "$PE/pages/DiscoverPage.mjs" >/dev/null 2>&1 && echo 1 || { command -v node >/dev/null 2>&1 || echo 1; })"
ok "EPG success assertion switched to the snackbar the app shows now (textContains, exact-match call replaced)" "$(grep -q "byTextContains('Guide loaded')" "$PE/tests/epg-add-source.test.mjs" && ! grep -q 'EPG source added' "$PE/tests/epg-add-source.test.mjs" && echo 1 || echo 0)"
ok "playlist import waits for the home list instead of the removed 'Imported N' card" "$(grep -q 'nav.waitForHome' "$PE/tests/import-functional.test.mjs" && ! grep -q 'startsWith' "$PE/tests/import-functional.test.mjs" && echo 1 || echo 0)"
ok "history page: waits for real content instead of a fixed 1.5s pause" "$(grep -q 'watch history never loaded' "$PE/pages/HistoryPage.mjs" && echo 1 || echo 0)"
ok "history page: first row is the first non-chrome TextView, not TextView #3" "$(grep -q 'chrome.has(text)' "$PE/pages/HistoryPage.mjs" && ! grep -q 'instance(2)' "$PE/pages/HistoryPage.mjs" && echo 1 || echo 0)"
ok "overlay replaced the stale repo spec that exists" "$(grep -q 'More options' "$PE/tests/watchlist-screen.test.mjs" && echo "$pj" | grep -q watchlist-screen && echo 1 || echo 0)"
rm -f "$PE/tests/watchlist-screen.test.mjs"; pj="$($PY "$LANE/prep_e2e.py" "$PE")"
ok "overlay never ADDS a spec the repo does not have" "$([ ! -f "$PE/tests/watchlist-screen.test.mjs" ] && echo 1 || echo 0)"
cp "$PE/tests/epg-add-source.test.mjs" "$T/e1"; $PY "$LANE/prep_e2e.py" "$PE" >/dev/null
ok "prep_e2e is idempotent" "$(cmp -s "$T/e1" "$PE/tests/epg-add-source.test.mjs" && echo 1 || echo 0)"
ok "overlay watchlist spec is syntactically valid JS" "$(command -v node >/dev/null 2>&1 && { node --check "$LANE/overlay/tests/watchlist-screen.test.mjs" >/dev/null 2>&1 && echo 1 || echo 0; } || echo 1)"

echo "== 19. seed_data.py against a stub staging API: idempotent, API-only, no secrets in output"
cat >"$FAKE/seedapi.py" <<'EOF'
import http.server, socketserver, sys, json, os
STATE = {"streams": [{"id": 1, "name": "QA Test Channel 1"}], "maps": [], "hist": [], "calls": []}
class H(http.server.BaseHTTPRequestHandler):
    def _j(s, code, obj):
        s.send_response(code); s.send_header("Content-Type", "application/json"); s.end_headers(); s.wfile.write(json.dumps(obj).encode())
    def do_GET(s):
        STATE["calls"].append("GET " + s.path)
        if s.path == "/api/streams": return s._j(200, STATE["streams"])
        if s.path == "/api/epg/mappings": return s._j(200, STATE["maps"])
        if s.path == "/api/history": return s._j(200, STATE["hist"])
        s._j(404, {})
    def do_POST(s):
        n = int(s.headers.get("Content-Length", "0")); body = json.loads(s.rfile.read(n) or b"{}")
        STATE["calls"].append("POST " + s.path)
        if s.path == "/api/auth/login": return s._j(200 if body.get("password") == os.environ["SEED_PW"] else 401, {"access_token": "tok"})
        if s.headers.get("Authorization") != "Bearer tok": return s._j(401, {})
        if s.path == "/api/streams":
            if any(x.get("url") == body["url"] for x in STATE["streams"] if "url" in x): return s._j(400, {})
            body["id"] = len(STATE["streams"]) + 10; STATE["streams"].append(body); return s._j(201, body)
        if s.path == "/api/epg/mappings": STATE["maps"].append(body); return s._j(201, body)
        if s.path == "/api/history": STATE["hist"].append(body); return s._j(201, body)
        s._j(404, {})
    def log_message(s, *a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
PORT_SEED=$((PORT_BACKEND + 7)); SEED_PW="$SECRET" $PY "$FAKE/seedapi.py" "$PORT_SEED" >/dev/null 2>&1 & SERVER_PIDS="$SERVER_PIDS $!"
sleep 1
sd() { env -i PATH=/usr/bin:/bin CHICK_API_BASE="http://127.0.0.1:$PORT_SEED" CHICK_PREMIUM_EMAIL=p@x.test CHICK_PREMIUM_PASSWORD="$1" "$PY" "$LANE/seed_data.py"; }
o1="$(sd "$SECRET")"; o2="$(sd "$SECRET")"
ok "first run: creates the vod + live streams, the guide mapping and the history row" "$([ "$(echo "$o1" | field ok)" = True ] && [ "$(echo "$o1" | $PY -c 'import json,sys; print(len(json.load(sys.stdin)["actions"]))')" = 4 ] && echo 1 || echo 0)"
ok "second run: idempotent, zero actions" "$([ "$(echo "$o2" | field ok)" = True ] && [ "$(echo "$o2" | field actions)" = '[]' ] && echo 1 || echo 0)"
ok "wrong password -> ok:false, exit 0, nothing created" "$(o3="$(sd "$BADSECRET")"; [ "$(echo "$o3" | field ok)" = False ] && echo 1 || echo 0)"
ok "no secret or token in seed output" "$(! echo "$o1$o2" | grep -q "$SECRET\|tok" && echo 1 || echo 0)"
ok "missing env -> ok:false JSON, exit 0" "$(env -i PATH=/usr/bin:/bin "$PY" "$LANE/seed_data.py" | field ok | grep -q False && echo 1 || echo 0)"
ok "seeded streams use distinct URLs (backend rejects duplicate URLs with 400)" "$(echo "$o1" | $PY -c 'import json,sys; a=json.load(sys.stdin)["actions"]; sys.exit(0 if all(x.endswith("201") for x in a) else 1)' && echo 1 || echo 0)"

echo "== 20. make_xmltv.py + staging janitor wiring"
xml="$($PY "$LANE/make_xmltv.py")"
ok "xmltv fixture is well-formed with >=2 channels and a long schedule" "$(echo "$xml" | $PY -c '
import sys, xml.etree.ElementTree as ET
r = ET.fromstring(sys.stdin.read()); ch = r.findall("channel"); pr = r.findall("programme")
sys.exit(0 if len(ch) >= 2 and len(pr) >= 2 * 200 else 1)' && echo 1 || echo 0)"
cat >"$REPO/scripts_e2e_janitor_stub" <<'EOF'
EOF
rm -f "$REPO/scripts_e2e_janitor_stub"; mkdir -p "$REPO/scripts"
cat >"$REPO/scripts/e2e_janitor.py" <<EOF
import os, sys
open("$T/janitor.calls", "a").write(" ".join(sys.argv[1:]) + " pw_set=%s api=%s\n" % (bool(os.environ.get("E2E_STAGING_PREMIUM_PASSWORD")), os.environ.get("E2E_STAGING_API", "")))
EOF
(cd "$REPO" && git add -A >/dev/null && git commit -qm janitor && git update-ref refs/remotes/origin/develop HEAD)
reset_specs; rm -f "$T/janitor.calls"; set_spec beta 'echo "boom"; exit 1'
out="$(lane "$RN" -- )"
ok "janitor ran before AND after the specs, staging only" "$([ "$(grep -c -- '--env staging' "$T/janitor.calls" 2>/dev/null)" = 2 ] && echo 1 || echo 0)"
ok "janitor got the staging API base and the password via env (never argv)" "$(grep -q "pw_set=True api=http://127.0.0.1:$PORT_BACKEND" "$T/janitor.calls" && ! grep -q "$SECRET" "$T/janitor.calls" && echo 1 || echo 0)"
ok "janitor pre/post logs exist in the run dir; no secret in them" "$(RD="$(ls -d "$T"/ovn/state/qa_devicelane/runs/*/ | tail -1)"; [ -e "$RD/janitor_pre.log" ] && [ -e "$RD/janitor_post.log" ] && ! grep -rq "$SECRET" "$RD" && echo 1 || echo 0)"
reset_specs; rm -f "$T/janitor.calls"
out="$(lane "$RN" DL_NO_JANITOR=1 -- )"
ok "DL_NO_JANITOR=1 disables the sweeps" "$([ ! -s "$T/janitor.calls" ] && echo 1 || echo 0)"
ok "still nothing left running" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"

echo "== 21. cron_nightly.sh wrapper"
CW="$LANE/cron_nightly.sh"
reset_specs
out="$(lane "$CW" -- )"
ok "wrapper (absolute path, env -i) -> run completes with PASS verdict line" "$(echo "$out" | grep -c '"verdict": "PASS"' | grep -q 1 && echo 1 || echo 0)"
ok "wrapper logs start/done markers" "$(echo "$out" | grep -q 'cron_nightly\] start' && echo "$out" | grep -q 'cron_nightly\] done' && echo 1 || echo 0)"
ok "wrapper leaves nothing running" "$([ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
reset_specs
out="$(cd "$ROOT" && env -i HOME="$T/home" PATH=/usr/bin:/bin OVN_DIR="$T/ovn" DL_EXTRA_PATH="$FAKE" DL_NODE="$FAKE/node" DL_CREDS="$T/creds.env" DL_API_BASE="http://127.0.0.1:$PORT_BACKEND" DL_APPIUM_PORT="$PORT_APPIUM" DL_EMU_PORT=$EMU_PORT DL_AVD=$TAVD DL_FAKE_KVM=1 DL_BOOT_TIMEOUT=20 DL_SPEC_TIMEOUT=30 qa/device_lane/cron_nightly.sh 2>/dev/null)"
ok "wrapper via RELATIVE path -> PASS" "$(echo "$out" | grep -q '"verdict": "PASS"' && echo 1 || echo 0)"
if { [ -x /usr/bin/flock ] || [ -x /bin/flock ]; } && command -v flock >/dev/null 2>&1; then   # the wrapper runs under env -i PATH=/usr/bin:/bin
  mkdir -p "$T/ovn/state/qa_devicelane"; exec 7>"$T/ovn/state/qa_devicelane/cron.lock"; flock -n 7
  out="$(lane "$CW" -- )"; exec 7>&-
  ok "second firing while the lock is held -> silent skip, exit 0, no emulator started" "$(echo "$out" | grep -q 'skipped' && ! echo "$out" | grep -q verdict && [ "$(leftovers)" = 0 ] && echo 1 || echo 0)"
fi
reset_specs
out="$(lane "$CW" -- )"; ok "cron_nightly never propagates a failure (always exit 0)" "$([ $? = 0 ] && echo 1 || echo 0)"

echo "== 22. the adb server (a daemon) must never inherit and hold the lane lock"
reset_specs; rm -f "$T/adbd.pid"
out="$(lane "$RN" -- )"
if [ -e "$T/ovn/state/qa_devicelane/lane.lock" ]; then
  ok "after a run the lane lock is free even though a daemonized adb server was started during it" "$($PY -c '
import fcntl,sys
f=open(sys.argv[1]); fcntl.flock(f, fcntl.LOCK_EX|fcntl.LOCK_NB)' "$T/ovn/state/qa_devicelane/lane.lock" && echo 1 || echo 0)"
fi
ok "run still PASSes with the daemon in play" "$([ "$(echo "$out" | field verdict)" = PASS ] && echo 1 || echo 0)"
ok "adb server is stopped at the end when only our own (possibly offline) emulator remained" "$([ ! -f "$T/adbd.pid" ] && echo 1 || echo 0)"

. "$LANE/lane_env.sh" 2>/dev/null   # for verify_teardown in the sections below (env derived from the fake HOME)
vt() { ( export HOME="$T/home" QA_DL_HOME="$T/home" DL_EMU_PORT=$EMU_PORT DL_AVD=$TAVD DL_APPIUM_PORT="$PORT_APPIUM" ADB="$FAKE/adb" PATH=/usr/bin:/bin; unset ANDROID_HOME ANDROID_SDK_ROOT
  . "$LANE/lane_env.sh"; verify_teardown "$T/vt.json" "${1:-}" 2>/dev/null ); }

echo "== 23. verified teardown (post-run process check)"
reset_specs
out="$(lane "$RN" -- )"; RD="$(ls -d "$T"/ovn/state/qa_devicelane/runs/*/ | tail -1)"
ok "a normal run leaves a teardown.json that says clean:true" "$(grep -q '"clean":true' "$RD/teardown.json" && echo 1 || echo 0)"
ok "run stderr (cron log) carries the verified-clean line" "$(grep -q 'teardown verified clean' "$T/stderr.txt" && echo 1 || echo 0)"
# benign: nothing running -> clean, nothing escalated
vt; ok "benign: nothing of ours running -> clean:true, escalated empty" "$(grep -q '"clean":true,"escalated":\[\]' "$T/vt.json" && echo 1 || echo 0)"
# negative: a straggler that carries our avd name (a qemu child that outlived its launcher) is found, killed, and reported
cat >"$FAKE/straggler.sh" <<STRAGGLER_EOF
#!/usr/bin/env bash
# cmdline carries "-avd $TAVD -port $EMU_PORT" like a real qemu child
exec -a "qemu-system-x86_64 -avd $TAVD -port $EMU_PORT -no-window" sleep 3000
STRAGGLER_EOF
chmod +x "$FAKE/straggler.sh"; "$FAKE/straggler.sh" & SPID=$!; sleep 1
kill -0 "$SPID" 2>/dev/null && S_UP=1 || S_UP=0
vt
ok "negative: leaked qemu-like process was alive before the check" "$S_UP"
ok "negative: verify_teardown killed it and listed it under escalated" "$(gone "$SPID" && grep -q '"escalated":\["' "$T/vt.json" && grep -q '"clean":true' "$T/vt.json" && echo 1 || echo 0)"
wait "$SPID" 2>/dev/null
# negative: a stray appium on OUR port is killed too; an unrelated process is left alone
cat >"$FAKE/appium_stray.sh" <<APPIUM_EOF
#!/usr/bin/env bash
exec -a "node /x/.bin/appium --port $PORT_APPIUM" sleep 3000
APPIUM_EOF
chmod +x "$FAKE/appium_stray.sh"; "$FAKE/appium_stray.sh" & APID=$!
sleep 3000 & OTHER=$!; sleep 1
vt
ok "negative: stray appium on our port killed" "$(gone "$APID" && echo 1 || echo 0)"
ok "benign: an unrelated process is untouched" "$(kill -0 "$OTHER" 2>/dev/null && echo 1 || echo 0)"
kill "$OTHER" 2>/dev/null; wait "$OTHER" "$APID" 2>/dev/null

# 2026-10-02 review fix: the avd pattern must carry OUR console port. Decoys that share the AVD name but not the port (another lane run in a
# different state dir, a human's manual run) must survive; our own process in either arg order must still die.
mkdir -p "$FAKE"
cat >"$FAKE/decoy.sh" <<DECOY_EOF
#!/usr/bin/env bash
exec -a "qemu-system-x86_64 -avd $TAVD -port \$1 -no-window" sleep 3000
DECOY_EOF
cat >"$FAKE/rev.sh" <<REV_EOF
#!/usr/bin/env bash
exec -a "qemu-system-x86_64 -port $EMU_PORT -no-window -avd $TAVD" sleep 3000
REV_EOF
chmod +x "$FAKE/decoy.sh" "$FAKE/rev.sh"
"$FAKE/decoy.sh" $((EMU_PORT + 2)) & D1=$!; "$FAKE/decoy.sh" "${EMU_PORT}6" & D2=$!; "$FAKE/rev.sh" & R1=$!; sleep 1
vt
ok "negative control: same AVD, different port -> decoy survives" "$(kill -0 "$D1" 2>/dev/null && echo 1 || echo 0)"
ok "negative control: our port as a prefix of a longer port number -> decoy survives" "$(kill -0 "$D2" 2>/dev/null && echo 1 || echo 0)"
ok "positive: our AVD + our port in the other arg order is still killed" "$(gone "$R1" && echo 1 || echo 0)"
kill "$D1" "$D2" 2>/dev/null; wait "$D1" "$D2" "$R1" 2>/dev/null
# end-to-end: a stub nightly run (and its cleanup sweep) next to a decoy emulator on the same AVD but another port must not touch the decoy
reset_specs; "$FAKE/decoy.sh" $((EMU_PORT + 2)) & D3=$!; sleep 1
out="$(lane "$RN" -- )"
ok "a full stub run PASSes and its cleanup sweep leaves a same-AVD other-port emulator alone" "$([ "$(echo "$out" | field verdict)" = PASS ] && kill -0 "$D3" 2>/dev/null && echo 1 || echo 0)"
kill "$D3" 2>/dev/null; wait "$D3" 2>/dev/null
ok "isolation: this suite uses a private AVD name and a non-default port" "$([ "$TAVD" != qa_api34 ] && [ "$EMU_PORT" != 5570 ] && [ "$EMU_PORT" != 5598 ] && echo 1 || echo 0)"

echo "== 23b. abort during the build phase does not leak gradle (dl_timeout_fwd)"
cat >"$T/fwd_probe.sh" <<FWD_EOF
#!/usr/bin/env bash
. "$LANE/lane_env.sh"
dl_timeout_fwd 100 bash -c 'exec -a "fwd-probe-$TAVD" sleep 3000'
FWD_EOF
chmod +x "$T/fwd_probe.sh"
"${DL_SETSID[@]}" "$T/fwd_probe.sh" >/dev/null 2>&1 & FP=$!; sleep 2
ok "negative setup: the wrapped long command is running" "$(pgrep -f "fwd-probe-$TAVD" >/dev/null && echo 1 || echo 0)"
kill_tree "$FP" TERM; sleep 3
ok "a group TERM aimed at the caller takes the timeout-wrapped command down too" "$(pgrep -f "fwd-probe-$TAVD" >/dev/null && echo 0 || echo 1)"
pkill -KILL -f "fwd-probe-$TAVD" 2>/dev/null; wait "$FP" 2>/dev/null
( . "$LANE/lane_env.sh"; dl_timeout_fwd 1 sleep 5 ); rc=$?
ok "benign: dl_timeout_fwd still times out with rc 124" "$([ $rc = 124 ] && echo 1 || echo 0)"
( . "$LANE/lane_env.sh"; dl_timeout_fwd 10 bash -c 'exit 7' ); rc=$?
ok "benign: dl_timeout_fwd passes the command's exit code through" "$([ $rc = 7 ] && echo 1 || echo 0)"
reset_specs; touch "$T/gradle_slow"; rm -rf "$T/ovn/state/qa_devicelane/apk"
t0=$(date +%s)
out="$(lane "$RN" DL_OVERALL_TIMEOUT=6 -- )"; el=$(( $(date +%s) - t0 ))
ok "overall cap hit during the build -> UNVERIFIED, ended near the cap" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && [ "$el" -lt 40 ] && echo 1 || echo 0)"
ok "the hung gradle (grandchild of build_apk under timeout) is gone, not leaked" "$(pgrep -f "fake-gradle-$TAVD" >/dev/null && echo 0 || echo 1)"
pkill -KILL -f "fake-gradle-$TAVD" 2>/dev/null
rm -f "$T/gradle_slow"; rm -rf "$T/ovn/state/qa_devicelane/apk"; reset_specs
out="$(lane "$RN" -- )"
ok "benign: with a normal gradle the build still succeeds and the run PASSes" "$([ "$(echo "$out" | field verdict)" = PASS ] && echo 1 || echo 0)"

echo "== 23c. boot tuning (real boot never proven: give it the best chance)"
ok "emulator io class is best-effort 7 (not idle), default boot timeout >= 420s" "$( ( unset DL_BOOT_TIMEOUT QA_CPUSET; . "$LANE/lane_env.sh"; [ "$DL_BOOT_TIMEOUT" -ge 420 ] && { ! command -v ionice >/dev/null 2>&1 || dl_prefix | grep -q 'ionice -c2 -n7'; } && ! dl_prefix | grep -q 'ionice -c3' && echo 1 || echo 0 ) )"

echo "== 24. overall hard timeout: the run aborts, tears down, reports UNVERIFIED, exits 0"
reset_specs; set_spec alpha "exec sleep 61"
t0=$(date +%s)
out="$(lane "$RN" DL_OVERALL_TIMEOUT=8 DL_SPEC_TIMEOUT=60 -- )"; rc=$?; el=$(( $(date +%s) - t0 ))
ok "exit 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "verdict UNVERIFIED naming the overall cap" "$([ "$(echo "$out" | field verdict)" = UNVERIFIED ] && echo "$out" | field summary | grep -qi 'overall' && echo 1 || echo 0)"
ok "ended near the cap (<40s), not the spec's 60s sleep" "$([ "$el" -lt 40 ] && echo 1 || echo 0)"
ok "emulator + appium torn down after the abort, teardown verified clean" "$([ "$(leftovers)" = 0 ] && grep -q '"clean":true' "$(ls -d "$T"/ovn/state/qa_devicelane/runs/*/ | tail -1)/teardown.json" && echo 1 || echo 0)"
reset_specs
out="$(lane "$RN" DL_OVERALL_TIMEOUT=600 -- )"
ok "benign: a normal run well inside the cap is unaffected (PASS) and leaves no watchdog sleeping" "$([ "$(echo "$out" | field verdict)" = PASS ] && ! pgrep -f 'dl-watchdog 600' >/dev/null && echo 1 || echo 0)"

echo "== 25. cron_nightly backstop: hung run_nightly -> hard timeout, post-run sweep, exit 0"
printf '#!/usr/bin/env bash\ntrap "" TERM\nwhile :; do sleep 1; done\n' >"$T/hung_run.sh"; chmod +x "$T/hung_run.sh"
printf '#!/usr/bin/env bash\necho fake-run-ok\n' >"$T/quick_run.sh"; chmod +x "$T/quick_run.sh"
"$FAKE/straggler.sh" & SPID=$!; sleep 1
t0=$(date +%s)
out="$(lane "$CW" DL_RUN_NIGHTLY="$T/hung_run.sh" DL_HARD_TIMEOUT=3 DL_HARD_KILL_GRACE=2 -- )"; rc=$?; el=$(( $(date +%s) - t0 ))
ok "hung run killed by the wrapper (<30s), exit 0" "$([ $rc = 0 ] && [ "$el" -lt 30 ] && echo 1 || echo 0)"
ok "wrapper logs the hard timeout" "$(echo "$out" | grep -q 'HARD TIMEOUT' && echo 1 || echo 0)"
ok "post-run sweep killed the straggler and wrote a clean verdict" "$(gone "$SPID" && grep -q '"clean":true' "$T/ovn/state/qa_devicelane/teardown_cron.json" && echo "$out" | grep -q 'teardown verified' && echo 1 || echo 0)"
wait "$SPID" 2>/dev/null
out="$(lane "$CW" DL_RUN_NIGHTLY="$T/quick_run.sh" -- )"
ok "benign: a run that finishes on its own passes through with no HARD TIMEOUT message" "$(echo "$out" | grep -q fake-run-ok && ! echo "$out" | grep -q 'HARD TIMEOUT' && echo 1 || echo 0)"
out="$(lane "$CW" DL_RUN_NIGHTLY="$T/quick_run.sh" QA_CPUSET=999-1000 -- )"
ok "benign: an invalid QA_CPUSET is skipped, the run still happens" "$(echo "$out" | grep -q fake-run-ok && echo 1 || echo 0)"

echo "== 26. cron.txt: one nightly line, bounded, advisory, not installed"
CT="$LANE/cron.txt"
ok "cron.txt exists with exactly one active line" "$([ "$(grep -vc '^[[:space:]]*#\|^[[:space:]]*$' "$CT")" = 1 ] && echo 1 || echo 0)"
CL="$(grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$CT")"
ok "line is a valid 5-field once-a-day schedule" "$(echo "$CL" | awk '{ exit !($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3=="*" && $4=="*" && $5=="*") }' && echo 1 || echo 0)"
ok "line calls the wrapper by relative path after cd, pins QA_CPUSET, appends to the lane log" "$(echo "$CL" | grep -q 'cd /home/mhintermeister/overnight-queue && .*QA_CPUSET=.* ./qa/device_lane/cron_nightly.sh >> state/qa_devicelane/cron.log 2>&1' && echo 1 || echo 0)"
ok "line cannot take run.lock / call promote or hygiene" "$(echo "$CL" | grep -qi 'run.lock\|promote\|hygiene' && echo 0 || echo 1)"
ok "no device-lane script takes run.lock or any repo lock" "$(grep -v '^[[:space:]]*#' "$LANE"/*.sh "$LANE"/*.py | grep -q 'run\.lock\|index\.lock\|repo\.lock' && echo 0 || echo 1)"
ok "no flake-loop script exists in the lane" "$(ls "$LANE" | grep -qi 'loop' && echo 0 || echo 1)"

echo "== 27. real emulator: OFF by default (never under run_all.sh)"
ok "run_all.sh registers this suite and force-unsets the real-emulator flag" "$(grep -q 'test_qa_devicelane.sh' "$HERE/run_all.sh" && grep -q 'unset DL_REAL_EMULATOR_TEST' "$HERE/run_all.sh" && echo 1 || echo 0)"
ok "every section above ran against the stub emulator (the SDK emulator is the fake)" "$(grep -q 'emu.pid' "$SDK/emulator/emulator" && echo 1 || echo 0)"
if [ "${DL_REAL_EMULATOR_TEST:-0}" = 1 ]; then
  echo "  (DL_REAL_EMULATOR_TEST=1: ONE bounded real KVM boot + verified teardown)"
  REAL_OUT="$( ( export DL_EMU_PORT="${DL_REAL_PORT:-5590}" DL_BOOT_TIMEOUT="${DL_REAL_BOOT_TIMEOUT:-300}"; unset ANDROID_HOME ANDROID_SDK_ROOT DL_FAKE_KVM QA_DL_HOME; . "$LANE/lane_env.sh"
      P="$(mktemp -d /tmp/qa-dl-real.XXXXXX)"
      start_emulator "$P/emu.pid" "$P/emu.log"; rc=$?; echo "boot_rc=$rc boot_s=${DL_BOOT_SECONDS:-0}"
      # evidence BEFORE teardown: a failed boot must be diagnosable from this output alone (the first real attempt, 2026-10-02, timed out and its log was gone)
      [ "$rc" = 0 ] || { echo "--- emulator.log tail ---"; tail -25 "$P/emu.log" 2>&1; echo "--- adb devices ---"; "$ADB" devices 2>&1; echo "--- qemu cpu ---"; ps -eo pid,pcpu,etime,args 2>/dev/null | grep "[-]avd $DL_AVD" | cut -c1-160; }
      stop_emulator "$P/emu.pid"; stop_adb_if_idle; DL_CHECK_ADB=1 verify_teardown "$P/td.json" "$P" 2>/dev/null; cat "$P/td.json"; rm -rf "$P" ) 2>&1 )"
  echo "$REAL_OUT" | sed 's/^/    /'
  ok "real emulator booted (boot_rc=0) under KVM" "$(echo "$REAL_OUT" | grep -q 'boot_rc=0' && echo 1 || echo 0)"
  ok "real emulator torn down, verified clean" "$(echo "$REAL_OUT" | grep -q '"clean":true' && echo 1 || echo 0)"
else
  echo "  skip: real-emulator test (set DL_REAL_EMULATOR_TEST=1 to run ONE bounded boot; OFF by default)"
fi

echo; echo "devicelane: $pass passed, $fail failed"
[ "$fail" = 0 ]
