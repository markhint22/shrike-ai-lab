#!/usr/bin/env bash
# Chickadee Streams — daily verification.
# Builds + tests all three platforms (web, Android, iOS) plus the backend, on this
# Mac, and writes a pass/fail summary. Designed to run unattended once a day via a
# launchd agent (see com.shrike.chickadee.dailyverify.plist). Optional ntfy push:
# set NTFY_TOPIC in the environment (or ~/.chickadee_ntfy_topic).
#
# Nothing here needs signing or a backend — it verifies the code still BUILDS and
# its unit/integration tests still PASS. Full functional UI flows (login->browse->
# play) additionally need the backend reachable + a test account; see the UI-test
# section at the bottom, gated on CHICKADEE_TEST_EMAIL/PASSWORD.
set -uo pipefail

ROOT="/Users/mhintermeister/LocalProjects/iptv_apps"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
# launchd's cron environment doesn't source .zshrc, so nvm's node/npm and asdf's
# JDK shims aren't on PATH by default — without this, npm/gradle silently fall
# back to whatever the bare system has (no node at all; Homebrew JDK 25, which
# Gradle 8.13 doesn't support and fails with a bare "25.0.2" error). Found 2026-09-06.
export JAVA_HOME="${JAVA_HOME:-$HOME/.asdf/installs/java/openjdk-17.0.2}"
NODE_BIN="$(dirname "$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -1)" 2>/dev/null)"
# /opt/homebrew/bin: the asdf shims exec the `asdf` binary from there; launchd's PATH lacks it, so `python3` died with "exec: asdf: not found" and both janitor checks
# failed every day since 2026-10-01 (found 2026-10-09).
export PATH="$NODE_BIN:$JAVA_HOME/bin:$HOME/.asdf/shims:/opt/homebrew/bin:/usr/local/bin:$ANDROID_HOME/platform-tools:$PATH"
LOG_DIR="$ROOT/store-assets/daily-verify-logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY="$LOG_DIR/summary-$STAMP.txt"

pass=0; fail=0
line() { echo "$@" | tee -a "$SUMMARY"; }
result() { if [ "$1" -eq 0 ]; then line "PASS  $2"; pass=$((pass+1)); else line "FAIL  $2  (see $3)"; fail=$((fail+1)); fi; }

line "Chickadee Streams daily verification — $STAMP"
line "repo: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null) on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
line "----------------------------------------------------------------"

# 0) E2E JANITOR (before) — restore the shared test accounts to their canonical state so a run
# that was killed/crashed yesterday cannot leave guide sources, playlists or streams behind
# (that is how the prod database grew to 587 MB). See docs/TEST_ACCOUNTS.md.
L="$LOG_DIR/janitor-before-$STAMP.log"
python3 "$ROOT/scripts/e2e_janitor.py" --env all > "$L" 2>&1
result $? "janitor — test accounts canonical (before)" "$L"

# 1) WEB (vitest)
L="$LOG_DIR/web-$STAMP.log"
( cd "$ROOT/iptv-web" && CI=true npm test ) > "$L" 2>&1
result $? "web  — vitest ($(grep -oE '[0-9]+ passed' "$L" | tail -1))" "$L"

# 2) BACKEND (pytest)
L="$LOG_DIR/backend-$STAMP.log"
# rebuild the Mac backend venv when it is missing (the check failed daily with "./.venv/bin/pytest: No such file")
[ -x "$ROOT/iptv-backend/.venv/bin/pytest" ] || ( cd "$ROOT/iptv-backend" && /opt/homebrew/bin/python3.12 -m venv .venv && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt ) > "$LOG_DIR/venv-rebuild-$STAMP.log" 2>&1
( cd "$ROOT/iptv-backend" && ./.venv/bin/pytest -q --no-cov ) > "$L" 2>&1
result $? "backend — pytest ($(grep -oE '[0-9]+ passed' "$L" | tail -1))" "$L"

# 3) ANDROID (build + unit tests). Flavor-qualified since the googleTv/fireTv
#    product flavors (added 2026-09-01) made the bare task names ambiguous.
L="$LOG_DIR/android-$STAMP.log"
( cd "$ROOT/iptv-android" && ./gradlew assembleGoogleTvDebug testGoogleTvDebugUnitTest --console=plain ) > "$L" 2>&1
result $? "android — assembleGoogleTvDebug + testGoogleTvDebugUnitTest" "$L"

# 3b) ANDROID Compose UI tests — needs a STABLE-API emulator (the 'cd_api35' AVD;
#     newer preview images break the Compose test rule's InputManager reflection).
#     Boots it, runs the instrumented tests, shuts it down. Skipped if the AVD is absent.
#
#     A prior run's `kill "$EMU_PID"` only killed the `emulator` launcher process,
#     not the actual `qemu-system-*` process it spawns as a separate child — that
#     child survives as an orphan holding the AVD lock. The NEXT run's boot then
#     fails fast with "Running multiple emulators with the same AVD is an
#     experimental feature", which looked like a segfault/kill in the log for
#     4+ consecutive days (found 2026-09-05). Fix: reap any stale qemu process
#     for this AVD before booting, and shut down via `adb emu kill` (which
#     cleanly terminates the real qemu process) instead of killing the launcher.
if "$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | grep -qx "cd_api35"; then
  L="$LOG_DIR/android-ui-$STAMP.log"
  pkill -f "qemu-system.*-avd cd_api35" 2>/dev/null && sleep 3
  "$ANDROID_HOME/emulator/emulator" -avd cd_api35 -no-window -no-snapshot -no-audio -no-boot-anim -gpu swiftshader_indirect >/dev/null 2>&1 &
  for _ in $(seq 1 40); do [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 6; done
  ( cd "$ROOT/iptv-android" && ./gradlew connectedGoogleTvDebugAndroidTest \
      -Pandroid.testInstrumentationRunnerArguments.class=com.chickadeestreams.iptv.LoginScreenTest \
      --console=plain ) > "$L" 2>&1
  result $? "android UI — LoginScreenTest (Compose on cd_api35)" "$L"
  adb emu kill 2>/dev/null
  pkill -f "qemu-system.*-avd cd_api35" 2>/dev/null
else
  line "SKIP  android UI — create the 'cd_api35' emulator (android-35) to enable"
fi

# 4) iOS (build + tests). Guard against the SwiftPM/RevenueCat resolution hang by
#    pre-seeding the package cache with system git if it's missing (see memory).
CACHE="$HOME/Library/Caches/org.swift.swiftpm/repositories"
if ! ls -d "$CACHE"/purchases-ios-* >/dev/null 2>&1; then
  # learn the cache dir name, then seed it with a fast system-git bare clone
  ( cd "$ROOT/iptv-ios" && timeout 20 xcodebuild -resolvePackageDependencies -project ChickadeeStreams.xcodeproj -scheme ChickadeeStreams >/dev/null 2>&1 & sleep 12; kill %1 2>/dev/null ) || true
  D="$(ls -d "$CACHE"/purchases-ios-* 2>/dev/null | head -1)"
  [ -n "$D" ] && { rm -rf "$D"; git clone --bare https://github.com/RevenueCat/purchases-ios.git "$D" >/dev/null 2>&1; }
fi
# "iPhone 17 Pro" intermittently gets stuck mid-clone-creation on this Mac
# ("Device was allocated but was stuck in creation state" — a CoreSimulator
# registration issue, not a code bug; found 2026-09-05). The dedicated
# "ChickadeeE2E-iPhone16" sim (created for XCUITest runs) is reliable and is
# the only iPhone-16-class device left registered — target it by name, not
# the generic "iPhone 16" device type name (which no longer resolves; found 2026-09-06).
# the dedicated sim vanished when the iOS 26 runtimes were removed (the ios check then failed "no matching destination" daily): recreate it when missing, on the
# newest installed iOS runtime that still ships an iPhone 16 device type.
if ! xcrun simctl list devices 2>/dev/null | grep -q "ChickadeeE2E-iPhone16"; then
  _rt="$(xcrun simctl list runtimes 2>/dev/null | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | sort -V | head -1)"
  [ -n "$_rt" ] && xcrun simctl create "ChickadeeE2E-iPhone16" com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$_rt" >/dev/null 2>&1 || true
fi
xcrun simctl boot "ChickadeeE2E-iPhone16" >/dev/null 2>&1 || true
L="$LOG_DIR/ios-$STAMP.log"
( cd "$ROOT/iptv-ios" && xcodebuild test \
    -project ChickadeeStreams.xcodeproj -scheme ChickadeeStreams \
    -destination 'platform=iOS Simulator,name=ChickadeeE2E-iPhone16' \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO ) > "$L" 2>&1
ios_rc=$?
if [ "$ios_rc" -eq 0 ]; then
  # tests run across parallel simulator clones, so "Executed N tests" appears once
  # per clone; the last one is as good a total as any when everything passed.
  ios_detail="$(grep -oE 'Executed [0-9]+ tests, with [0-9]+ failures' "$L" | tail -1)"
else
  # on failure, that same last "Executed" line is just one clone's sub-summary and
  # is often "0 failures" even though the overall run failed (2026-09-08: reported
  # FAIL with "0 failures" in the same breath). Report the actual failing tests
  # from the "Failing tests:" block instead.
  ios_detail="failing: $(awk '/^Failing tests:/{f=1;next} f && /^$/{exit} f{sub(/^[ \t]+/,"");print}' "$L" | tr '\n' ',' | sed 's/,/, /g; s/, $//')"
  [ "$ios_detail" = "failing: " ] && ios_detail="build/run error — see log"
fi
result "$ios_rc" "ios  — xcodebuild test ($ios_detail)" "$L"

# 5) E2E JANITOR (after) — sweep up anything today's UI tests created and did not delete.
L="$LOG_DIR/janitor-after-$STAMP.log"
python3 "$ROOT/scripts/e2e_janitor.py" --env all > "$L" 2>&1
result $? "janitor — test accounts canonical (after)" "$L"

line "----------------------------------------------------------------"
line "RESULT: $pass passed, $fail failed  ($STAMP)"

# optional phone push
TOPIC="${NTFY_TOPIC:-$(cat "$HOME/.chickadee_ntfy_topic" 2>/dev/null)}"
if [ -n "$TOPIC" ]; then
  TAG=$([ "$fail" -eq 0 ] && echo white_check_mark || echo rotating_light)
  curl -fsS --max-time 10 -H "Title: Chickadee daily verify" -H "Tags: $TAG" \
    -d "$(cat "$SUMMARY")" "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
fi

# keep only the last 14 summaries
ls -t "$LOG_DIR"/summary-*.txt 2>/dev/null | tail -n +15 | xargs rm -f 2>/dev/null || true
exit "$fail"
