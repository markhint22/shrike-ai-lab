#!/usr/bin/env bash
# Regression test for docs/patches/iptv-daily-verify-r10.patch (iptv_apps scripts/daily-verify.sh + new scripts/daily-verify-lib.sh; review findings F4 / F3 / IPTV-6).
# The patch is applied to a FIXTURE copy of the pre-patch script (fixtures/iptv_daily_verify/daily-verify.base.sh) and the WHOLE patched script is run against stubbed
# xcrun / xcodebuild / npm / curl / ssh / janitor / gradle / pytest in a temp tree (DV_ROOT, HOME and ANDROID_HOME are all temp dirs). Nothing touches the real simulators,
# the network, the box or ntfy.sh.
#
# The stub xcodebuild models the REAL failure: a destination with only a NAME means OS:latest, which resolves on the newest installed iOS runtime (27.0) where the
# dedicated sim (iOS 18.6) does not exist -> "Unable to find a device matching the provided destination specifier" (ios-20261010-061547.log). The pre-patch script
# FAILS against that world (the mutation proof is part of this test); the patched script resolves the sim by id and passes.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OQ="$(cd "$HERE/../.." && pwd)"
PATCH=""
for c in "${IPTV_DV_PATCH:-/nonexistent}" "$OQ/../../docs/patches/iptv-daily-verify-r10.patch" "$OQ/docs/patches/iptv-daily-verify-r10.patch"; do [ -f "$c" ] && { PATCH="$c"; break; }; done
BASE="$HERE/fixtures/iptv_daily_verify/daily-verify.base.sh"
[ -n "$PATCH" ] && [ -f "$BASE" ] || { echo "  SKIP: docs/patches/iptv-daily-verify-r10.patch or the base fixture is not installed here"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "  SKIP: python3 missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "  SKIP: git missing"; exit 0; }
P=0; F=0
# assertions run with pipefail OFF (x | grep -q is flaky under pipefail: SIGPIPE rc 141)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

T="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1
trap 'rm -rf "$T"' EXIT
W="$T/world"; mkdir -p "$W"

# ---- apply the patch to a fixture repo
PR="$T/patched"; mkdir -p "$PR/scripts"
cp "$BASE" "$PR/scripts/daily-verify.sh"; chmod +x "$PR/scripts/daily-verify.sh"
( cd "$PR" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1 )
ok "the patch applies cleanly to the pre-patch script (git apply --check)" "cd '$PR' && git apply --check '$PATCH'"
( cd "$PR" && git apply "$PATCH" ) >/dev/null 2>&1
ok "patch creates scripts/daily-verify-lib.sh" "[ -f '$PR/scripts/daily-verify-lib.sh' ]"
ok "patched script + lib pass bash -n (3.2 syntax)" "bash -n '$PR/scripts/daily-verify.sh' && bash -n '$PR/scripts/daily-verify-lib.sh'"
ok "patched script has no name-only simulator destination left" "! grep -q \"name=ChickadeeE2E\" '$PR/scripts/daily-verify.sh'"
if [ -d "${IPTV_REPO:-$HOME/LocalProjects/iptv_apps}/.git" ]; then   # informational only: the live repo may have moved since the patch was cut
  ( cd "${IPTV_REPO:-$HOME/LocalProjects/iptv_apps}" && git apply --check "$PATCH" ) >/dev/null 2>&1 && echo "  info: patch also applies cleanly to the live iptv_apps checkout" || echo "  info: patch does NOT apply to the live iptv_apps checkout any more (re-cut it)"
fi

# ---- the stub world
cat > "$W/runtimes.json" <<'EOF'
{"runtimes":[
 {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-6","version":"18.6","isAvailable":true,"platform":"iOS","supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"},{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"}]},
 {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","isAvailable":true,"platform":"iOS","supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16"},{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]},
 {"identifier":"com.apple.CoreSimulator.SimRuntime.tvOS-27-0","version":"27.0","isAvailable":true,"platform":"tvOS","supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation"}]}]}
EOF
cat > "$W/devices_with_sim.json" <<'EOF'
{"devices":{
 "com.apple.CoreSimulator.SimRuntime.iOS-18-6":[{"name":"ChickadeeE2E-iPhone16","udid":"E427C22E-06B8-48CF-8CA1-3C0463A54640","isAvailable":true,"state":"Booted"}],
 "com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"01D8EA35-0314-4432-B677-0A20A98541D5","isAvailable":true,"state":"Shutdown"}],
 "com.apple.CoreSimulator.SimRuntime.tvOS-27-0":[{"name":"Apple TV 4K (3rd generation)","udid":"A30E5B06-4C2B-4881-8FA8-85F4C3CA4C67","isAvailable":true,"state":"Shutdown"}]}}
EOF
cat > "$W/devices_without_sim.json" <<'EOF'
{"devices":{
 "com.apple.CoreSimulator.SimRuntime.iOS-18-6":[],
 "com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"01D8EA35-0314-4432-B677-0A20A98541D5","isAvailable":true,"state":"Shutdown"}]}}
EOF
cat > "$W/addsim.py" <<'EOF'
import json, re, sys
w, name, rt, udid = sys.argv[1:5]
p = w + "/devices.json"
d = json.load(open(p))
d["devices"].setdefault(rt, []).append({"name": name, "udid": udid, "isAvailable": True, "state": "Shutdown"})
json.dump(d, open(p, "w"))
EOF
cat > "$W/dest.py" <<'EOF'
import json, os, re, sys
w = sys.argv[1]
d = json.load(open(w + "/devices.json"))["devices"]
hide = set(open(w + "/dest_hide").read().split()) if os.path.exists(w + "/dest_hide") else set()
print('\n\tDestinations compatible with the "ChickadeeStreams" scheme:')
print("\t\t{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00006030-001809983A28001C, name:My Mac }")
print("\t\t{ platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }")
for rt, lst in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)$", rt)
    if not m:
        continue
    for x in lst:
        if x["udid"] not in hide:
            print("\t\t{ platform:iOS Simulator, arch:arm64, id:%s, OS:%s.%s, name:%s }" % (x["udid"], m.group(1), m.group(2), x["name"]))
print('\n\tDestinations incompatible with the "ChickadeeStreams" scheme:')
for rt, lst in d.items():
    if "tvOS" in rt:
        for x in lst:
            print("\t\t{ platform:tvOS Simulator, arch:arm64, id:%s, OS:27.0, name:%s, error:platform mismatch }" % (x["udid"], x["name"]))
EOF
cat > "$W/xctest.py" <<'EOF'
# models xcodebuild's destination matching: id= exact; name= WITHOUT OS means OS:latest = the newest installed iOS runtime
import json, re, sys
w, dest = sys.argv[1], sys.argv[2]
kv = dict(p.split("=", 1) for p in dest.split(",")[1:] if "=" in p)
d = json.load(open(w + "/devices.json"))["devices"]
rts = json.load(open(w + "/runtimes.json"))["runtimes"]
def ver(s):
    m = re.search(r"iOS-(\d+)-(\d+)$", s)
    return (int(m.group(1)), int(m.group(2))) if m else None
latest = max((ver(r["identifier"]) for r in rts if ver(r["identifier"])), default=None)
found = None
for rt, lst in d.items():
    v = ver(rt)
    if v is None:
        continue
    for x in lst:
        if "id" in kv and x["udid"] == kv["id"]:
            found = x
        elif "id" not in kv and x["name"] == kv.get("name") and ("OS" in kv and kv["OS"] == "%d.%d" % v or "OS" not in kv and v == latest):
            found = x
if not found:
    print("xcodebuild: error: Unable to find a device matching the provided destination specifier:\n\t\t{ platform:iOS Simulator, OS:latest, name:%s }" % kv.get("name", kv.get("id")))
    sys.exit(70)
print("Test Suite 'All tests' passed at 2026-10-10 06:00:00.\n\t Executed 5 tests, with 0 failures (0 unexpected) in 1.0 (1.1) seconds")
EOF

# stub tools as exported FUNCTIONS (they beat PATH lookups, including the script's own PATH rewrite)
xcrun(){
  [ "$1" = simctl ] || return 0
  case "$2" in
    list) if [ "$4" = runtimes ]; then cat "$W/runtimes.json"; else cat "$W/devices.json"; fi ;;
    create) echo "create $*" >> "$W/calls"
            if [ -f "$W/create_fail" ]; then echo "Invalid runtime: $5" >&2; return 1; fi
            _u="AAAAAAAA-0000-4000-8000-$(printf %012d $((RANDOM + 1000)))"; python3 "$W/addsim.py" "$W" "$3" "$5" "$_u"; echo "$_u" ;;
    boot) echo "Unable to boot device in current state: Booted" >&2; return 149 ;;
  esac
}
xcodebuild(){
  case " $* " in
    *" -showdestinations "*) echo "xcodebuild -showdestinations" >> "$W/calls"
        if [ -f "$W/dest_garbage" ]; then echo "xcodebuild: error: Could not resolve package dependencies" >&2; return 74; fi
        python3 "$W/dest.py" "$W" ;;
    *" test "*) _d=""; while [ $# -gt 0 ]; do [ "$1" = "-destination" ] && _d="$2"; shift; done
        echo "xcodebuild test -destination $_d" >> "$W/calls"; python3 "$W/xctest.py" "$W" "$_d" ;;
    *) return 0 ;;
  esac
}
npm(){ echo "Tests  12 passed (12)"; return 0; }
curl(){
  case "$*" in
    *ntfy.sh*) echo "REAL-NTFY $*" >> "$W/calls"; return 0 ;;
    *relay.test*) echo "RELAY $*" >> "$W/relay_posts"; return 0 ;;
  esac
  # network probe: the first N probes fail (net_down_left), then succeed
  _n="$(cat "$W/net_down_left" 2>/dev/null || echo 0)"
  echo "probe" >> "$W/probes"
  if [ "${_n:-0}" -gt 0 ]; then echo $((_n - 1)) > "$W/net_down_left"; return 6; fi
  return 0
}
ssh(){ echo "ssh $*" >> "$W/ssh_calls"; cat >> "$W/ssh_stdin" 2>/dev/null; return 0; }
export -f xcrun xcodebuild npm curl ssh

# build one scenario tree. $1 = dir, $2 = script to run (patched | base)
mk_root(){
  local r="$1" which="$2"
  rm -rf "$r"; mkdir -p "$r/scripts" "$r/iptv-web" "$r/iptv-backend/.venv/bin" "$r/iptv-android" "$r/iptv-ios" "$r/home/Library/Caches/org.swift.swiftpm/repositories/purchases-ios-x" "$r/android/emulator"
  if [ "$which" = patched ]; then cp "$PR/scripts/daily-verify.sh" "$PR/scripts/daily-verify-lib.sh" "$r/scripts/"; else cp "$BASE" "$r/scripts/daily-verify.sh"; fi
  # SAFETY: the pre-patch script hard-codes ROOT=/Users/.../iptv_apps (the REAL repo: real janitor, real pytest, real gradle). Rewrite that ONE line to require DV_ROOT
  # (unset => the script aborts) so a scenario can never touch the real checkout; the patched script already has the DV_ROOT hook. Refuse to run if no hook is present.
  sed -i.bak -e 's#^ROOT="/Users/mhintermeister/LocalProjects/iptv_apps"#ROOT="${DV_ROOT:?}"#' -e 's#^ROOT="${DV_ROOT:-/Users/mhintermeister/LocalProjects/iptv_apps}"#ROOT="${DV_ROOT:?}"#' "$r/scripts/daily-verify.sh"; rm -f "$r/scripts/daily-verify.sh.bak"
  grep -q '^ROOT="${DV_ROOT' "$r/scripts/daily-verify.sh" || { echo "  ABORT: scenario script has no DV_ROOT hook - refusing to run against the real checkout"; exit 2; }
  # janitor stub: fails while the network is down or on its first call when janitor_fail_first is set; counts its calls
  cat > "$r/scripts/e2e_janitor.py" <<EOF
import os, sys
w = "$W"
open(w + "/janitor_calls", "a").write("x\n")
n = int(open(w + "/net_down_left").read() or 0) if os.path.exists(w + "/net_down_left") else 0
calls = len(open(w + "/janitor_calls").read().split())
if n > 0:
    print("nodename nor servname provided, or not known"); sys.exit(1)
if os.path.exists(w + "/janitor_fail_first") and calls == 1:
    print(open(w + "/janitor_fail_first").read().strip() or "transient failure"); sys.exit(1)
sys.exit(0)
EOF
  printf '#!/bin/sh\necho "5 passed"\nexit 0\n' > "$r/iptv-backend/.venv/bin/pytest"; chmod +x "$r/iptv-backend/.venv/bin/pytest"
  printf '#!/bin/sh\nexit 0\n' > "$r/iptv-android/gradlew"; chmod +x "$r/iptv-android/gradlew"
  printf '#!/bin/sh\n[ "$1" = "-list-avds" ] && exit 0\nexit 0\n' > "$r/android/emulator/emulator"; chmod +x "$r/android/emulator/emulator"
}
# run the script. env: DV_NET_SLEEP=0.01 keeps the network waits instant. NTFY_SERVER/NTFY_TOPIC are cleared unless a scenario sets them.
run_dv(){
  local r="$1"
  ( cd "$r" && env -u NTFY_SERVER -u NTFY_TOPIC DV_ROOT="$r" HOME="$r/home" ANDROID_HOME="$r/android" W="$W" DV_NET_SLEEP=0.01 DV_NET_URL="https://net.test/health" \
      OVN_SSH="box.test" "${@:2}" bash "$r/scripts/daily-verify.sh" ) > "$r/run.out" 2>&1
  echo $? > "$r/run.rc"
}
fresh_world(){ rm -f "$W/calls" "$W/ssh_calls" "$W/ssh_stdin" "$W/relay_posts" "$W/probes" "$W/janitor_calls" "$W/create_fail" "$W/dest_hide" "$W/dest_garbage" "$W/net_down_left" "$W/janitor_fail_first"; cp "$W/${1:-devices_with_sim}.json" "$W/devices.json"; }
summary_of(){ cat "$1"/store-assets/daily-verify-logs/summary-*.txt 2>/dev/null; }
ioslog_of(){ cat "$1"/store-assets/daily-verify-logs/ios-*.log 2>/dev/null; }

# ================= S0: the defect, reproduced on the PRE-patch script (this is the mutation proof)
fresh_world devices_with_sim; R0="$T/r0"; mk_root "$R0" base; run_dv "$R0"
ok "S0 pre-patch script: ios check FAILS in the iOS-27-installed world (name-only destination = OS:latest)" "summary_of '$R0' | grep -q '^FAIL  ios'"
ok "S0 pre-patch script: the failure is the real 'Unable to find a device matching' error" "ioslog_of '$R0' | grep -q 'Unable to find a device matching'"
ok "S0 pre-patch script used a name-only destination" "grep -q 'destination platform=iOS Simulator,name=ChickadeeE2E-iPhone16' '$W/calls'"

# ================= S1: patched script, sim exists on the OLD runtime while a newer one is installed -> resolved by id, passes
fresh_world devices_with_sim; R1="$T/r1"; mk_root "$R1" patched; run_dv "$R1"
ok "S1 patched: ios check PASSES (sim resolved by id on iOS 18.6 although 27.0 is the latest runtime)" "summary_of '$R1' | grep -q '^PASS  ios'"
ok "S1 patched: xcodebuild test destination is the sim UDID" "grep -q 'xcodebuild test -destination platform=iOS Simulator,id=E427C22E-06B8-48CF-8CA1-3C0463A54640' '$W/calls'"
ok "S1 patched: no name-only destination was ever used" "! grep -q 'destination platform=iOS Simulator,name=' '$W/calls'"
ok "S1 patched: the -showdestinations preflight ran before the test" "[ \"\$(grep -n 'showdestinations' '$W/calls' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'xcodebuild test' '$W/calls' | head -1 | cut -d: -f1)\" ]"
ok "S1 patched: no simulator was created (it already existed)" "! grep -q '^create ' '$W/calls'"
ok "S1 patched: whole run is green (rc 0, 0 failed)" "[ \"\$(cat '$R1/run.rc')\" = 0 ] && grep -q 'RESULT: [0-9]* passed, 0 failed' '$R1/run.out'"
ok "S1 patched: no streak alert on a green run" "[ ! -s '$W/ssh_calls' ]"

# ================= S2: sim missing -> recreated on the NEWEST iOS runtime that ships the device type, resolved by id afterwards
fresh_world devices_without_sim; R2="$T/r2"; mk_root "$R2" patched; run_dv "$R2"
ok "S2 recreate: simctl create used the newest iOS runtime (27.0), not the oldest" "grep -q '^create simctl create ChickadeeE2E-iPhone16 com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-27-0' '$W/calls'"
ok "S2 recreate: the test ran against the NEW sim's id and passed" "summary_of '$R2' | grep -q '^PASS  ios' && grep -q 'destination platform=iOS Simulator,id=AAAAAAAA-' '$W/calls'"
ok "S2 recreate: the log records what was created" "ioslog_of '$R2' | grep -q \"created simulator 'ChickadeeE2E-iPhone16' on com.apple.CoreSimulator.SimRuntime.iOS-27-0\""
# newest runtime without the device type is skipped
fresh_world devices_without_sim; python3 - "$W/runtimes.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for r in d["runtimes"]:
    if r["identifier"].endswith("iOS-27-0"):
        r["supportedDeviceTypes"] = [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]
json.dump(d, open(p, "w"))
EOF
R2b="$T/r2b"; mk_root "$R2b" patched; run_dv "$R2b"
ok "S2b a newer runtime that lacks the iPhone 16 type is skipped (falls back to 18.6)" "grep -q 'iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-18-6' '$W/calls'"
python3 - "$W/runtimes.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for r in d["runtimes"]:
    if r["identifier"].endswith("iOS-27-0"):
        r["supportedDeviceTypes"] = [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"}, {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]
json.dump(d, open(p, "w"))
EOF

# ================= S3: create fails -> LOUD (summary FAIL with the reason, log has the simctl error), xcodebuild test never runs
fresh_world devices_without_sim; touch "$W/create_fail"; R3="$T/r3"; mk_root "$R3" patched; run_dv "$R3"
ok "S3 create failure: ios check is a FAIL" "summary_of '$R3' | grep -q '^FAIL  ios'"
ok "S3 create failure: the summary line says the simulator could not be created" "summary_of '$R3' | grep '^FAIL  ios' | grep -q 'could not be created'"
ok "S3 create failure: the log has the simctl error text" "ioslog_of '$R3' | grep -q 'SIM FAIL: xcrun simctl create' && ioslog_of '$R3' | grep -q 'Invalid runtime'"
ok "S3 create failure: no xcodebuild test was attempted" "! grep -q 'xcodebuild test' '$W/calls'"
# pre-patch behaviour for the same world (hidden by || true): ran xcodebuild with a name that cannot exist
fresh_world devices_without_sim; touch "$W/create_fail"; R3b="$T/r3b"; mk_root "$R3b" base; run_dv "$R3b"
ok "S3 mutation: the pre-patch script hid the create error (no SIM FAIL in its log) and still ran xcodebuild test" "! ioslog_of '$R3b' | grep -q 'SIM FAIL' && grep -q 'xcodebuild test' '$W/calls'"

# ================= S4: preflight - the sim exists but xcodebuild does not offer it -> FAIL with the reason, no test run
fresh_world devices_with_sim; echo "E427C22E-06B8-48CF-8CA1-3C0463A54640" > "$W/dest_hide"; R4="$T/r4"; mk_root "$R4" patched; run_dv "$R4"
ok "S4 preflight: not-offered destination fails the ios check" "summary_of '$R4' | grep '^FAIL  ios' | grep -q 'not offered by xcodebuild -showdestinations'"
ok "S4 preflight: the log lists the simulators xcodebuild does offer" "ioslog_of '$R4' | grep -q 'PREFLIGHT FAIL' && ioslog_of '$R4' | grep -q 'name:iPhone 17'"
ok "S4 preflight: no xcodebuild test was attempted" "! grep -q 'xcodebuild test' '$W/calls'"
# S5: a preflight that cannot produce a listing must NOT cause a false FAIL
fresh_world devices_with_sim; touch "$W/dest_garbage"; R5="$T/r5"; mk_root "$R5" patched; run_dv "$R5"
ok "S5 an unusable -showdestinations listing is skipped (no false FAIL); the real test still runs and passes" "summary_of '$R5' | grep -q '^PASS  ios' && grep -q 'xcodebuild test' '$W/calls' && ioslog_of '$R5' | grep -q 'check skipped'"

# ================= S6: network - janitor 'before' waits for the network and retries once
fresh_world devices_with_sim; echo 3 > "$W/net_down_left"; R6="$T/r6"; mk_root "$R6" patched; run_dv "$R6"
ok "S6 network down for the first 3 probes: janitor (before) PASSES after the wait" "summary_of '$R6' | grep -q '^PASS  janitor — test accounts canonical (before)'"
ok "S6 janitor ran once (the wait happened BEFORE it, not a retry)" "[ \"\$(wc -l < '$W/janitor_calls' | tr -d ' ')\" = 2 ]"   # before + after
fresh_world devices_with_sim; echo 3 > "$W/net_down_left"; R6b="$T/r6b"; mk_root "$R6b" base; run_dv "$R6b"
ok "S6 mutation: the pre-patch script FAILS the janitor (before) when the network is not up yet" "summary_of '$R6b' | grep -q '^FAIL  janitor — test accounts canonical (before)'"
# a janitor failure that is NOT a network error must fail ONCE (no second run, no appended retry output)
fresh_world devices_with_sim; echo "AssertionError: premium account has 3 playlists" > "$W/janitor_fail_first"; R6c="$T/r6c"; mk_root "$R6c" patched; run_dv "$R6c"
ok "S6c a non-network janitor failure is NOT retried: FAIL reported, janitor ran exactly twice in the run (before + after)" "summary_of '$R6c' | grep -q '^FAIL  janitor — test accounts canonical (before)' && [ \"\$(wc -l < '$W/janitor_calls' | tr -d ' ')\" = 2 ]"
ok "S6c the janitor log has no retry marker" "! cat '$R6c'/store-assets/daily-verify-logs/janitor-before-*.log | grep -q 'retry after network wait'"
# a DNS/connect failure on the first attempt IS retried once (the network answers) and passes
fresh_world devices_with_sim; echo "urllib.error.URLError: <urlopen error [Errno 8] nodename nor servname provided, or not known>" > "$W/janitor_fail_first"; R6e="$T/r6e"; mk_root "$R6e" patched; run_dv "$R6e"
ok "S6e a DNS error on the first janitor attempt is retried once and passes" "summary_of '$R6e' | grep -q '^PASS  janitor — test accounts canonical (before)' && [ \"\$(wc -l < '$W/janitor_calls' | tr -d ' ')\" = 3 ]"
ok "S6e the janitor log records the retry" "cat '$R6e'/store-assets/daily-verify-logs/janitor-before-*.log | grep -q 'retry after network wait'"
fresh_world devices_with_sim; echo "ConnectionError: Connection refused" > "$W/janitor_fail_first"; R6f="$T/r6f"; mk_root "$R6f" patched; run_dv "$R6f"
ok "S6f a connect error ('Connection refused') is retried once too" "summary_of '$R6f' | grep -q '^PASS  janitor — test accounts canonical (before)' && [ \"\$(wc -l < '$W/janitor_calls' | tr -d ' ')\" = 3 ]"
fresh_world devices_with_sim; echo 100000 > "$W/net_down_left"; R6d="$T/r6d"; mk_root "$R6d" patched
( s=$(date +%s); run_dv "$R6d"; echo $(( $(date +%s) - s )) > "$T/r6d.secs" )
ok "S6d network NEVER up: bounded (the waits give up, run finishes in < 60 s), WARN line + janitor FAIL, no hang" "[ \"\$(cat '$T/r6d.secs')\" -lt 60 ] && summary_of '$R6d' | grep -q 'WARN  network still down' && summary_of '$R6d' | grep -q '^FAIL  janitor'"

# ================= S7: failure streak -> ONE line in the box alerts path after 2 consecutive FAIL summaries
mk_prev(){ # $1 root, $2 = FAIL|PASS : a complete earlier summary
  mkdir -p "$1/store-assets/daily-verify-logs"; local f="$1/store-assets/daily-verify-logs/summary-20200101-000000.txt"
  if [ "$2" = FAIL ]; then printf 'header\nFAIL  ios  — xcodebuild test (build/run error)  (see x)\nRESULT: 6 passed, 1 failed  (20200101-000000)\n' > "$f"; else printf 'header\nPASS  ios\nRESULT: 7 passed, 0 failed  (20200101-000000)\n' > "$f"; fi
  touch -t 202001010000 "$f"
}
fresh_world devices_without_sim; touch "$W/create_fail"; R7="$T/r7"; mk_root "$R7" patched; mk_prev "$R7" FAIL; run_dv "$R7"
ok "S7 two consecutive FAIL summaries: ONE alert line was written to the box alerts.log over ssh" "[ \"\$(grep -c 'chickadee-daily-verify' '$W/ssh_stdin')\" = 1 ] && grep -q 'alerts.log' '$W/ssh_calls'"
ok "S7 the alert line has the fleet alerts.log shape and names the streak and the failing check" "grep -qE '^\[[0-9-]+ [0-9:]+\] warn \| chickadee-daily-verify \| chickadee daily-verify has FAILED 2 runs in a row: .*ios' '$W/ssh_stdin'"
ok "S7 ssh is BatchMode with a connect timeout (cannot hang the daily job)" "grep -q 'BatchMode=yes' '$W/ssh_calls' && grep -q 'ConnectTimeout=' '$W/ssh_calls'"
fresh_world devices_without_sim; touch "$W/create_fail"; R7b="$T/r7b"; mk_root "$R7b" patched; mk_prev "$R7b" PASS; run_dv "$R7b"
ok "S7b FAIL after a PASS day (streak 1): no alert" "[ ! -s '$W/ssh_stdin' ]"
fresh_world devices_without_sim; touch "$W/create_fail"; R7c="$T/r7c"; mk_root "$R7c" patched; run_dv "$R7c"
ok "S7c first ever FAIL (no earlier summary): no alert" "[ ! -s '$W/ssh_stdin' ]"
fresh_world devices_without_sim; touch "$W/create_fail"; R7d="$T/r7d"; mk_root "$R7d" patched; mk_prev "$R7d" FAIL; run_dv "$R7d" DV_ALERT=0
ok "S7d DV_ALERT=0 kill switch: no alert" "[ ! -s '$W/ssh_stdin' ]"
fresh_world devices_without_sim; touch "$W/create_fail"; R7e="$T/r7e"; mk_root "$R7e" patched; mk_prev "$R7e" FAIL; run_dv "$R7e" DV_ALERT_BOX=0
ok "S7e DV_ALERT_BOX=0: no ssh" "[ ! -s '$W/ssh_calls' ]"
fresh_world devices_without_sim; touch "$W/create_fail"; R7f="$T/r7f"; mk_root "$R7f" patched; mk_prev "$R7f" FAIL; run_dv "$R7f" NTFY_SERVER="http://relay.test:8099" NTFY_TOPIC=t_test
ok "S7f with a relay configured the streak is ALSO posted ONCE to the relay (never to ntfy.sh)" "[ \"\$(grep -c 'relay.test:8099/t_test' '$W/relay_posts')\" -ge 1 ] && ! grep -q REAL-NTFY '$W/calls'"
fresh_world devices_without_sim; touch "$W/create_fail"; R7g="$T/r7g"; mk_root "$R7g" patched; mk_prev "$R7g" FAIL; run_dv "$R7g" NTFY_TOPIC=t_test
ok "S7g a topic but NO relay (NTFY_SERVER unset): the NEW streak alert never goes straight to ntfy.sh (the pre-existing end-of-run summary push is unchanged and not counted)" "! grep REAL-NTFY '$W/calls' | grep -q 'failing .* days in a row' && [ ! -s '$W/relay_posts' ]"

# ================= lib unit checks: dv_fail_streak ignores incomplete (killed) summaries and stops at the first PASS
L="$T/streak"; mkdir -p "$L"
for n in 1 2 3 4; do :; done
printf 'x\nFAIL a\nRESULT: 1 passed, 1 failed\n' > "$L/summary-20260101-000001.txt"; touch -t 202601010001 "$L/summary-20260101-000001.txt"
printf 'x\nPASS a\nRESULT: 2 passed, 0 failed\n' > "$L/summary-20260102-000001.txt"; touch -t 202601020001 "$L/summary-20260102-000001.txt"
printf 'x\nFAIL a\n' > "$L/summary-20260103-000001.txt"; touch -t 202601030001 "$L/summary-20260103-000001.txt"      # killed run: no RESULT line, ignored
printf 'x\nFAIL b\nRESULT: 1 passed, 1 failed\n' > "$L/summary-20260104-000001.txt"; touch -t 202601040001 "$L/summary-20260104-000001.txt"
printf 'x\nFAIL c\nRESULT: 1 passed, 1 failed\n' > "$L/summary-20260105-000001.txt"; touch -t 202601050001 "$L/summary-20260105-000001.txt"
ok "dv_fail_streak: newest 2 complete FAIL summaries then a PASS = 2 (the killed run is ignored, the older FAIL is cut off by the PASS)" "[ \"\$(. '$PR/scripts/daily-verify-lib.sh'; dv_fail_streak '$L')\" = 2 ]"
ok "dv_fail_streak: empty dir = 0" "[ \"\$(. '$PR/scripts/daily-verify-lib.sh'; dv_fail_streak '$T/none')\" = 0 ]"

# bash 3.2 compatibility of the patched files (macOS /bin/bash) when available
if [ -x /bin/bash ] && /bin/bash --version 2>/dev/null | head -1 | grep -q 'version 3\.'; then
  fresh_world devices_with_sim; R8="$T/r8"; mk_root "$R8" patched
  ( cd "$R8" && env -u NTFY_SERVER -u NTFY_TOPIC DV_ROOT="$R8" HOME="$R8/home" ANDROID_HOME="$R8/android" W="$W" DV_NET_SLEEP=0.01 DV_NET_URL="https://net.test/health" OVN_SSH=box.test /bin/bash "$R8/scripts/daily-verify.sh" ) > "$R8/run.out" 2>&1
  ok "bash 3.2: the full patched script runs green under /bin/bash" "summary_of '$R8' | grep -q '^PASS  ios'"
fi

echo "test_iptv_daily_verify_patch: $P passed, $F failed"
[ "$F" -eq 0 ]
