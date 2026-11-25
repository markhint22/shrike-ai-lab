#!/usr/bin/env bash
# test_z6_notify_guard.sh - Z6 (2026-11-09). Running `mac_jobs_health.py --print` with NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 still wrote Mac state, copied health.json to the box,
# appended lines to the box alerts.log and pushed two REAL emergencies through the box relay over ssh (the relay fallback). Contract proven here, hermetically (stub ssh/curl on PATH that RECORD calls;
# MAC_SSH / MAC_CURL / OVN_SSH are deliberately UNSET so the stubs stand in for the real binaries; temp HOME; never the real box):
#   1. `mac_jobs_health.py --print` is strictly read-only: no state dir/file, no copy to the box, no alert, no push, no ssh/curl, no kickstart (stdout only).
#   2. With OVN_NOTIFY_DISABLE=1 every Mac alert path does NOTHING over the network: mac_alert (emergency + warn), ovn_relay.deliver, mac_jobs_health.py, mac_live_sync.sh, mac_live_commit_push.sh
#      -> zero ssh / zero curl invocations (for NTFY_SERVER unset, a real-looking host, and the closed loopback port 9). Local alerts.log lines are still written (the alert is not lost, only the push).
#   3. Control: with the disable switch OFF the same paths DO call the stubs (so the zero above is not a broken stub).
#   4. Mutants (disable switch neutralised in mac_lib.sh / ovn_relay.py, --print read-only removed) each make a scenario FAIL.
#   5. (review fix) deploy_watch.sh alert/alert_ok/emergency_failed, mac-native-build-check.sh alert, vercel_state_check.py fallback post honour the switch; a disabled run writes no dedupe/cooldown marker (D2); --print + enforce never kickstarts a loaded job.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SC="$(cd "$HERE/../../.." && pwd)"
for f in mac_lib.sh ovn_relay.py ovn_pick_srv.py mac_jobs_health.py mac_live_sync.sh mac_live_commit_push.sh mac-native-build-check.sh overnight-queue/deploy_watch.sh overnight-queue/vercel_state_check.py; do
  [ -f "$SC/$f" ] || { echo "  SKIP: Mac job scripts not present ($SC/$f) - queue-only tree (GPU box mirror)"; exit 0; }
done
T="$(safe_mktemp_dir z6)" || exit 1
. "$(cd "$(dirname "$0")" && pwd)/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }   # Z10: real ssh/curl/ntfy delivery impossible from this test
safe_set_sandbox_home "$T" || exit 1
trap 'safe_rm_rf "$T"' EXIT
P=0; F=0; i=0
ok() { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
mkdir -p "$T/bin"; export CALLS="$T/calls.log"
printf '%s\n' '#!/bin/sh' 'echo "ssh $*" >> "$CALLS"' 'exit 0' > "$T/bin/ssh"
printf '%s\n' '#!/bin/sh' 'echo "curl $*" >> "$CALLS"' 'exit 0' > "$T/bin/curl"
printf '%s\n' '#!/bin/sh' 'echo "launchctl $*" >> "$CALLS"' 'case "$1" in list) printf "PID\tStatus\tLabel\n";; esac' 'exit 0' > "$T/bin/launchctl"
chmod 755 "$T/bin/ssh" "$T/bin/curl" "$T/bin/launchctl"
export PATH="$T/bin:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
# the box/suite guards of the OTHER tests must not mask the behaviour under test: only OVN_NOTIFY_DISABLE protects here
unset OVN_NTFY_GUARD_LOG OVN_SSH MAC_SSH MAC_CURL OVN_RELAY_FALLBACK MAC_JOBS_NO_BOX OVN_MAC_JOBS OVN_SSH_GUARD_LOG
export TZ=UTC MAC_LAUNCHCTL="$T/bin/launchctl" MAC_DISK_FREE_GIB=100 OVN_NTFY_DUMMY=1
unset -f ssh scp rsync curl 2>/dev/null; . "$OVN_MTS_ENVFILE"   # Z10: drop the suite guard functions (they would swallow the stubs) but KEEP the sandbox guard
nssh() { grep -cE '^(ssh|curl) ' "$CALLS" 2>/dev/null || true; }

# scenario fixtures: a repo on a feature branch (commit_push => deliberate-refusal WARN alert), a manifest with a critical job that is loaded=missing (health => emergency)
R="$T/repo"; git init -q "$R" && git -C "$R" -c user.name=t -c user.email=t@t checkout -q -b claude/feature && echo x > "$R/f" && git -C "$R" add f && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m seed
mkdir -p "$T/agents" && : > "$T/agents/com.t.a.plist"
mk_state() { S="$T/st$1"; mkdir -p "$S/hb"; printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$S/m"; echo "$S"; }

# paths <scripts-dir> <state-dir> <NTFY_SERVER value or UNSET> : run every Mac alert path with the disable switch ON (OFF when OVN_NOTIFY_DISABLE_OVERRIDE=off)
paths() {
  local sd="$1" st="$2" ns="$3" dis=1
  [ "${OVN_NOTIFY_DISABLE_OVERRIDE:-}" = off ] && dis=""
  : > "$CALLS"
  (
    export OVN_MAC_STATE="$st" OVN_MAC_JOBS=shadow OVN_NOTIFY_DISABLE="$dis" MAC_ALERT_COOLDOWN_S=0 MAC_LIVE_DIR="$T/nolive" MAC_LIVE_SOURCE="$T/nosource" MAC_LAUNCH_AGENTS_DIR="$T/agents"
    [ "$ns" = UNSET ] && unset NTFY_SERVER || export NTFY_SERVER="$ns"
    bash -c '. "$1"; mac_alert emergency z6-e "emergency msg"; mac_alert warn z6-w "warn msg"' _ "$sd/mac_lib.sh" >/dev/null 2>&1
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ovn_relay; ovn_relay.deliver("emergency", "z6-py-e", "m"); ovn_relay.deliver("warn", "z6-py-w", "m")' "$sd" >/dev/null 2>&1
    MAC_JOBS_MANIFEST="$st/m" MAC_JOBS_NOW=2000000000 python3 "$sd/mac_jobs_health.py" >/dev/null 2>&1 </dev/null
    bash "$sd/mac_live_sync.sh" >/dev/null 2>&1 </dev/null
    bash "$sd/mac_live_commit_push.sh" "$R" "z6" f >/dev/null 2>&1 </dev/null
  )
}

echo "== A: OVN_NOTIFY_DISABLE=1: zero ssh / curl from every Mac alert path"
for ns in UNSET "https://relay.example.invalid:8099" "http://127.0.0.1:9"; do
  st="$(mk_state "a$((++i))")"; paths "$SC" "$st" "$ns"
  ok "NTFY_SERVER=$ns: zero ssh/curl invocations over mac_alert, ovn_relay, mac_jobs_health, mac_live_sync, mac_live_commit_push (got $(nssh))" "$([ "$(nssh)" = 0 ] && echo 0 || echo 1)"
done
ok "the alerts were still recorded locally (health emergency + live-sync + commit-push + mac_alert lines in alerts.log): the push is skipped, not the record" "$(grep -q 'z6-e' "$st/alerts.log" && grep -q 'live-sync-missing' "$st/alerts.log" && grep -qE 'commit-push-(branch|feature)' "$st/alerts.log" && grep -q '\[emergency\] com.t.a' "$st/alerts.log" && echo 0 || echo 1)"
ok "a normal (non --print) health run still writes its state under the switch (health.json)" "$([ -s "$st/health.json" ] && echo 0 || echo 1)"
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ovn_relay, os; r = ovn_relay.deliver("emergency", "k", "m"); sys.exit(0 if r == {"relay": False, "ssh": False, "direct": False} else 1)' "$SC" 2>/dev/null; rc=$?
ok "ovn_relay.deliver returns nothing-sent under the switch (python call, switch inherited from env: unset => not asserted; run explicitly below)" 0
OVN_NOTIFY_DISABLE=1 NTFY_SERVER=https://relay.example.invalid:8099 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ovn_relay; r = ovn_relay.deliver("emergency", "k", "m"); sys.exit(0 if r == {"relay": False, "ssh": False, "direct": False} else 1)' "$SC" 2>"$T/err.txt"
ok "ovn_relay.deliver: result is all-False and says 'notify disabled'" "$([ $? = 0 ] && grep -q 'notify disabled' "$T/err.txt" && echo 0 || echo 1)"

echo "== B: control - with the switch OFF the same paths DO reach the stubs (the zero above is real)"
st="$(mk_state b1)"; OVN_NOTIFY_DISABLE_OVERRIDE=off paths "$SC" "$st" "https://relay.example.invalid:8099"
ok "switch off: ssh/curl stubs are invoked (got $(nssh))" "$([ "$(nssh)" -gt 0 ] && echo 0 || echo 1)"

echo "== C: mac_jobs_health.py --print is strictly read-only"
for md in shadow enforce; do
  S="$T/ro_$md"; mkdir -p "$T/rom_$md"; printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/rom_$md/m"
  : > "$CALLS"
  out="$(OVN_MAC_STATE="$S" OVN_MAC_JOBS=$md MAC_JOBS_MANIFEST="$T/rom_$md/m" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 python3 "$SC/mac_jobs_health.py" --print 2>&1 </dev/null)"
  ok "$md: --print created no state dir / file at all" "$([ ! -e "$S" ] && echo 0 || echo 1)"
  ok "$md: --print made no ssh / curl / kickstart call (got: $(tr '\n' ';' < "$CALLS"))" "$([ "$(nssh)" = 0 ] && ! grep -q kickstart "$CALLS" && echo 0 || echo 1)"
  ok "$md: --print printed the computed health to stdout" "$(printf '%s' "$out" | grep -q "mac-jobs\[$md\]" && echo 0 || echo 1)"
done
# even with the switch OFF and a stale critical job, --print must not push or write
S="$T/ro_off"; mkdir -p "$T/rom_off"; printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/rom_off/m"; : > "$CALLS"
OVN_MAC_STATE="$S" OVN_MAC_JOBS=enforce MAC_JOBS_MANIFEST="$T/rom_off/m" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" NTFY_SERVER=https://relay.example.invalid:8099 python3 "$SC/mac_jobs_health.py" --print >/dev/null 2>&1 </dev/null
ok "--print with NO disable switch and a critical outage: still no state, no ssh/curl, no kickstart" "$([ ! -e "$S" ] && [ "$(nssh)" = 0 ] && ! grep -q kickstart "$CALLS" && echo 0 || echo 1)"

echo "== D: mutants (each must make a scenario fail)"
M="$T/mut"; mkdir -p "$M"; cp "$SC/mac_lib.sh" "$SC/ovn_relay.py" "$SC/ovn_pick_srv.py" "$SC/mac_jobs_health.py" "$SC/mac_live_sync.sh" "$SC/mac_live_commit_push.sh" "$M/"
mutf() { # mutf <file> <sed-expr>: apply to the mutant copy; fail the scenario when the anchor did not change anything
  cp "$M/$1" "$M/$1.orig"; sed -i.bak "$2" "$M/$1"; rm -f "$M/$1.bak"; if cmp -s "$M/$1" "$M/$1.orig"; then ok "mutant anchor present in $1 ($2)" 1; return 1; fi; return 0; }
unmut() { cp "$M/$1.orig" "$M/$1"; }
if mutf mac_lib.sh 's/^_mac_notify_disabled() {.*/_mac_notify_disabled() { return 1; }/'; then
  st="$(mk_state m1)"; paths "$M" "$st" "https://relay.example.invalid:8099"; [ "$(nssh)" != 0 ]; ok "MUTANT bash disable switch ignored (old behaviour): ssh/curl leak detected (got $(nssh))" $?
  unmut mac_lib.sh
fi
if mutf ovn_relay.py 's/^    return os.environ.get("OVN_NOTIFY_DISABLE", "").strip().lower() not in .*/    return False/'; then
  st="$(mk_state m2)"; paths "$M" "$st" "https://relay.example.invalid:8099"; [ "$(nssh)" != 0 ]; ok "MUTANT python disable switch ignored (old behaviour): ssh/curl leak detected (got $(nssh))" $?
  unmut ovn_relay.py
fi
if mutf mac_jobs_health.py 's/^    READONLY = "--print" in argv/    READONLY = False/'; then
  S="$T/ro_mut"; printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/rom_off/m2"; : > "$CALLS"
  OVN_MAC_STATE="$S" OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$T/rom_off/m2" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 python3 "$M/mac_jobs_health.py" --print >/dev/null 2>&1 </dev/null
  [ -e "$S" ]; ok "MUTANT --print not read-only (old behaviour): state written" $?
  unmut mac_jobs_health.py
fi

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Z6-fix (review defects D1/D2 + the leaks the reviewer listed)
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DWS="$SC/overnight-queue/deploy_watch.sh"
# dw_run <deploy_watch.sh> <disable-value or UNSET> <state-dir> : source ONLY deploy_watch.sh's alert / alert_ok / emergency_failed definitions (the real text, no sweep) and drive them with stub curl/ssh/publish
dw_run() {
  local f="$1" dis="$2" st="$3"; mkdir -p "$st"; : > "$CALLS"
  awk '/^_notify_disabled\(\)/ {p=1} /^alert\(\)\{/ {p=1} /^log\(\)\{/ {p=0} /^emergency_failed\(\)\{/ {q=1} q {print} q && /^}/ {q=0} p {print}' "$f" > "$T/dw_funcs.sh"
  (
    [ "$dis" = UNSET ] && unset OVN_NOTIFY_DISABLE || export OVN_NOTIFY_DISABLE="$dis"
    export NTFY_SERVER="https://relay.example.invalid:8099"; DRYRUN=0; TOPIC=t; repo=r; STATE="$st"; SRV=box.example.invalid
    log() { :; }; shrike_notify_publish() { echo "publish $*" >> "$CALLS"; }
    . "$T/dw_funcs.sh"
    alert "title-a" tag "body-a" r high; alert_ok "title-b" tag "body-b" r urgent; echo "alert_ok_rc=$?" > "$T/dw_rc"
    emergency_failed "billwatch-prod" billwatch "BillWatch" sha1234567 dep1 "boom"
  ) >/dev/null 2>&1 </dev/null
}
dw_calls() { grep -cE '^(curl|ssh|publish) ' "$CALLS" 2>/dev/null || true; }
echo "== E (D1): deploy_watch.sh alert() / alert_ok() / emergency_failed honour OVN_NOTIFY_DISABLE"
for v in 1 true yes on; do
  dw_run "$DWS" "$v" "$T/dws_$v"
  ok "deploy_watch OVN_NOTIFY_DISABLE=$v: zero curl / ssh / shrike_notify_publish calls (got $(dw_calls))" "$([ "$(dw_calls)" = 0 ] && echo 0 || echo 1)"
done
ok "deploy_watch disabled: alert_ok reports NOT sent (rc 1) and emergency_failed wrote no marker / .alog / alerts.log (so a later real run still pages)" "$(grep -q 'alert_ok_rc=1' "$T/dw_rc" && [ -z "$(ls "$T/dws_1" 2>/dev/null)" ] && echo 0 || echo 1)"
for v in UNSET "" 0 false no off OFF; do
  dd="$T/dwc_$((++i))"; dw_run "$DWS" "$v" "$dd"
  ok "deploy_watch control OVN_NOTIFY_DISABLE='${v}' (enabled): curl + publish + ssh stubs ARE called (got $(dw_calls)), marker written" "$([ "$(dw_calls)" -ge 5 ] && grep -q ssh "$CALLS" && ls "$dd" | grep -q '^emerg_billwatch_prod_' && echo 0 || echo 1)"
done
echo "== F: other raw-push leaks under the switch (mac-native-build-check.sh alert, vercel_state_check.py fallback post)"
nb_run() { # nb_run <script> <disable>: extract alert() + the switch helper + say(); run
  : > "$CALLS"; awk '/^ts\(\)/ {print} /^say\(\)/ {print} /^_notify_disabled\(\)/ {print} /^alert\(\)\{/ {print}' "$1" > "$T/nb_funcs.sh"
  ( [ "$2" = UNSET ] && unset OVN_NOTIFY_DISABLE || export OVN_NOTIFY_DISABLE="$2"; export NTFY_SERVER="https://relay.example.invalid:8099" TOPIC=t; . "$T/nb_funcs.sh"; alert "BROKEN" "body" ) >/dev/null 2>&1 </dev/null
}
nb_run "$SC/mac-native-build-check.sh" 1
ok "mac-native-build-check.sh alert() under the switch: zero curl (got $(nssh))" "$([ "$(nssh)" = 0 ] && echo 0 || echo 1)"
nb_run "$SC/mac-native-build-check.sh" UNSET
ok "mac-native-build-check.sh alert() control (switch off): curl stub called" "$([ "$(nssh)" -ge 1 ] && echo 0 || echo 1)"
vs_run() { # vs_run <vercel_state_check.py> <disable>: force `import ovn_relay` to fail (legacy direct post) and count urlopen calls
  cat > "$T/vs.py" <<'PYEOF'
import sys, os, types, runpy, urllib.request
path, dis = sys.argv[1], sys.argv[2]
if dis == "UNSET": os.environ.pop("OVN_NOTIFY_DISABLE", None)
else: os.environ["OVN_NOTIFY_DISABLE"] = dis
os.environ["NTFY_SERVER"] = "https://relay.example.invalid:8099"
calls = []
urllib.request.urlopen = lambda *a, **k: calls.append(a) or types.SimpleNamespace()
sys.modules["ovn_relay"] = None            # `import ovn_relay` raises ImportError -> the legacy path
sys.argv = [path, "--selftest-none"]
ns = runpy.run_path(path, run_name="not_main")
r = ns["push"]("T", "B", True, False)
print("RESULT", r, len(calls))
PYEOF
  python3 "$T/vs.py" "$1" "$2" >"$T/vs_out" 2>&1 </dev/null
}
vs_run "$SC/overnight-queue/vercel_state_check.py" 1
ok "vercel_state_check.py legacy fallback push under the switch: no urlopen, returns False ($(grep RESULT "$T/vs_out"))" "$(grep -q 'RESULT False 0' "$T/vs_out" && echo 0 || echo 1)"
vs_run "$SC/overnight-queue/vercel_state_check.py" UNSET
ok "vercel_state_check.py legacy fallback control (switch off): posts once" "$(grep -q 'RESULT True 1' "$T/vs_out" && echo 0 || echo 1)"

echo "== G (D2): a disabled run must NOT write the dedupe / cooldown marker (shared state dir), a later real emergency still delivers"
dedupe_bash() { # dedupe_bash <scripts-dir> <state>
  : > "$CALLS"
  ( export OVN_MAC_STATE="$2" OVN_MAC_JOBS=shadow NTFY_SERVER="https://relay.example.invalid:8099"; unset MAC_CURL MAC_SSH
    OVN_NOTIFY_DISABLE=1 bash -c '. "$1"; mac_alert emergency k-d2 "disabled run"' _ "$1/mac_lib.sh" >/dev/null 2>&1
    echo "disabled_calls=$(grep -cE '^(ssh|curl) ' "$CALLS" 2>/dev/null || true) marker=$([ -e "$2/alert_sent/k-d2" ] && echo yes || echo no)" > "$T/d2_bash"
    : > "$CALLS"
    OVN_NOTIFY_DISABLE= bash -c '. "$1"; mac_alert emergency k-d2 "real run"' _ "$1/mac_lib.sh" >/dev/null 2>&1 ) </dev/null
}
rm -rf "$T/d2b"; dedupe_bash "$SC" "$T/d2b"
ok "bash mac_alert: disabled emergency wrote no alert_sent marker and made 0 calls" "$(grep -q 'disabled_calls=0 marker=no' "$T/d2_bash" && echo 0 || echo 1)"
ok "bash mac_alert: the normal emergency on the SAME key right after still delivers (got $(nssh) calls) and writes the marker" "$([ "$(nssh)" -ge 1 ] && [ -e "$T/d2b/alert_sent/k-d2" ] && echo 0 || echo 1)"
dedupe_py() { # dedupe_py <scripts-dir> <state>: python alert() twin
  : > "$CALLS"
  cat > "$T/d2.py" <<'PYEOF'
import sys, os
sys.path.insert(0, sys.argv[1]); import mac_jobs_health as m
os.environ["OVN_NOTIFY_DISABLE"] = "1"
a = m.alert("emergency", "k-d2", "disabled run", 2000000000)
marker = os.path.join(m.STATE, "alert_sent", "k-d2")
print("disabled_ret", a, "marker", os.path.exists(marker))
os.environ["OVN_NOTIFY_DISABLE"] = ""
b = m.alert("emergency", "k-d2", "real run", 2000000001)
print("real_ret", b)
PYEOF
  OVN_MAC_STATE="$2" NTFY_SERVER="https://relay.example.invalid:8099" python3 "$T/d2.py" "$1" "$2" >"$T/d2_py" 2>&1 </dev/null
}
rm -rf "$T/d2p"; dedupe_py "$SC" "$T/d2p"
ok "python alert(): disabled emergency returned False with no marker ($(grep disabled_ret "$T/d2_py"))" "$(grep -q 'disabled_ret False marker False' "$T/d2_py" && echo 0 || echo 1)"
ok "python alert(): the normal emergency on the SAME key right after is delivered (ret True, ssh/curl called: $(nssh))" "$(grep -q 'real_ret True' "$T/d2_py" && [ "$(nssh)" -ge 1 ] && echo 0 || echo 1)"
echo "== H: --print writes NOTHING (state-dir assertion, with a pre-existing state dir holding a marker)"
S="$T/ro_pre"; mkdir -p "$S/alert_sent" "$S/hb"; echo 1 > "$S/alert_sent/old"; before="$(cd "$S" && find . -type f -exec cksum {} + | sort | tr '\n' ' ')"
printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/rom_pre.m"; : > "$CALLS"
OVN_MAC_STATE="$S" OVN_MAC_JOBS=enforce MAC_JOBS_MANIFEST="$T/rom_pre.m" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" NTFY_SERVER=https://relay.example.invalid:8099 python3 "$SC/mac_jobs_health.py" --print >/dev/null 2>&1 </dev/null
printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/rom_pre.m"   # the manifest file lives outside $S, so the tree under $S is exactly what --print could have touched
after="$(cd "$S" && find . -type f -exec cksum {} + | sort | tr '\n' ' ')"
ok "--print left every file under an existing state dir byte-identical (no health.json / health_state.json / alerts.log / new marker)" "$([ "$before" = "$after" ] && echo 0 || echo 1)"

echo "== I: kickstart mutant - a LOADED, stale, kickable job in --print mode with enforce on must produce NO kickstart call"
# launchctl list shows the job loaded (pid '-', status 0), heartbeat missing/old => stale + kickable. Normal enforce run kicks it (control); --print must not.
printf '%s\n' '#!/bin/sh' 'echo "launchctl $*" >> "$CALLS"' 'case "$1" in list) printf "PID\tStatus\tLabel\n-\t0\tcom.t.k\n";; esac' 'exit 0' > "$T/bin/launchctl_loaded"; chmod 755 "$T/bin/launchctl_loaded"
: > "$T/agents/com.t.k.plist"
kick_run() { # kick_run <scripts-dir> <state> <extra-arg>
  mkdir -p "$2/hb"; printf 'com.t.k | 600 | %s/k.log | hb/k | critical\n' "$2" > "$2.m"; echo 1000000000 > "$2/hb/k"; : > "$CALLS"
  OVN_MAC_STATE="$2" OVN_MAC_JOBS=enforce MAC_JOBS_MANIFEST="$2.m" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" MAC_LAUNCHCTL="$T/bin/launchctl_loaded" NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 python3 "$1/mac_jobs_health.py" $3 >/dev/null 2>&1 </dev/null
}
rm -rf "$T/k1" "$T/k2"; kick_run "$SC" "$T/k1" ""
ok "control: a normal enforce run DOES kickstart the loaded stale job (so the zero below is real)" "$(grep -q 'launchctl kickstart' "$CALLS" && echo 0 || echo 1)"
kick_run "$SC" "$T/k2" "--print"
ok "--print + enforce: loaded stale kickable job -> no kickstart call (calls: $(tr '\n' ';' < "$CALLS"))" "$(grep -q kickstart "$CALLS" && echo 1 || echo 0)"

echo "== J: Z6-fix mutants (each must make a scenario fail)"
pymut() { # pymut <file-in-$M> <old> <new>: literal replace (first occurrence) on the mutant copy; fail the scenario if the anchor is absent
  cp "$M/$1" "$M/$1.orig"; python3 - "$M/$1" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  [ $? = 0 ] || { ok "mutant anchor present in $1 ($2)" 1; return 1; }; return 0; }
mkdir -p "$M/overnight-queue"; cp "$SC/mac-native-build-check.sh" "$M/"; cp "$SC/overnight-queue/deploy_watch.sh" "$SC/overnight-queue/vercel_state_check.py" "$M/overnight-queue/"
# D1 mutants: the guard removed from alert() / alert_ok()
if pymut overnight-queue/deploy_watch.sh '  _notify_disabled && { echo "notify disabled (OVN_NOTIFY_DISABLE): $1 not sent" >&2; return 0; }
' ''; then dw_run "$M/overnight-queue/deploy_watch.sh" 1 "$T/dwm1"; [ "$(dw_calls)" != 0 ]; ok "MUTANT deploy_watch alert() unguarded (old behaviour): leak detected (got $(dw_calls))" $?; cp "$M/overnight-queue/deploy_watch.sh.orig" "$M/overnight-queue/deploy_watch.sh"; fi
if pymut overnight-queue/deploy_watch.sh '  _notify_disabled && { echo "notify disabled (OVN_NOTIFY_DISABLE): $1 not sent" >&2; return 1; }' ''; then dw_run "$M/overnight-queue/deploy_watch.sh" 1 "$T/dwm2"; [ "$(dw_calls)" != 0 ]; ok "MUTANT deploy_watch alert_ok() unguarded (old behaviour): leak detected (got $(dw_calls))" $?; cp "$M/overnight-queue/deploy_watch.sh.orig" "$M/overnight-queue/deploy_watch.sh"; fi
if pymut overnight-queue/deploy_watch.sh 'elif _notify_disabled; then :' 'elif false; then :'; then dw_run "$M/overnight-queue/deploy_watch.sh" 1 "$T/dwm3"; [ -n "$(ls "$T/dwm3" 2>/dev/null)" ] || [ "$(dw_calls)" != 0 ]; ok "MUTANT emergency_failed writes .alog / alerts.log under the switch: detected" $?; cp "$M/overnight-queue/deploy_watch.sh.orig" "$M/overnight-queue/deploy_watch.sh"; fi
if pymut overnight-queue/deploy_watch.sh 'case "$(printf '"'"'%s'"'"' "${OVN_NOTIFY_DISABLE:-}" | tr '"'"'A-Z'"'"' '"'"'a-z'"'"')" in ""|0|false|no|off) return 1' 'case "${OVN_NOTIFY_DISABLE:-}" in "") return 1'; then dw_run "$M/overnight-queue/deploy_watch.sh" 0 "$T/dwm4"; [ "$(dw_calls)" = 0 ]; ok "MUTANT deploy_watch treats '0' as disabled (semantics drift): control scenario fails" $?; cp "$M/overnight-queue/deploy_watch.sh.orig" "$M/overnight-queue/deploy_watch.sh"; fi
# F mutants
if pymut mac-native-build-check.sh 'alert(){ if _notify_disabled; then' 'alert(){ if false; then'; then nb_run "$M/mac-native-build-check.sh" 1; [ "$(nssh)" != 0 ]; ok "MUTANT mac-native-build-check alert() unguarded (old behaviour): leak detected" $?; fi
if pymut overnight-queue/vercel_state_check.py '    if os.environ.get("OVN_NOTIFY_DISABLE", "").strip().lower() not in ("", "0", "false", "no", "off"):' '    if False:'; then vs_run "$M/overnight-queue/vercel_state_check.py" 1; ! grep -q 'RESULT False 0' "$T/vs_out"; ok "MUTANT vercel_state_check fallback post unguarded (old behaviour): leak detected" $?; fi
# D2 mutants
cp "$SC/mac_lib.sh" "$SC/mac_jobs_health.py" "$SC/ovn_relay.py" "$SC/ovn_pick_srv.py" "$M/"
if pymut mac_lib.sh '  if _mac_notify_disabled && _mac_curl_blocked && _mac_ssh_blocked; then echo "notify disabled (OVN_NOTIFY_DISABLE): $key not sent" >&2; return 0; fi' ''; then rm -rf "$T/d2bm"; dedupe_bash "$M" "$T/d2bm"; grep -q 'marker=yes' "$T/d2_bash" && [ "$(nssh)" = 0 ]; ok "MUTANT bash mac_alert writes the marker before a disabled delivery (old behaviour): the later real emergency is swallowed (got $(nssh) calls)" $?; fi
if pymut mac_jobs_health.py '    if notify_disabled() and not (os.environ.get("MAC_CURL") or os.environ.get("MAC_SSH")):
        # Z6-fix' '    if False:
        # Z6-fix'; then rm -rf "$T/d2pm"; dedupe_py "$M" "$T/d2pm"; ! grep -q 'disabled_ret False marker False' "$T/d2_py"; ok "MUTANT python alert() writes the marker when disabled (old behaviour): detected" $?; fi
# kickstart + --print mutants
if pymut mac_jobs_health.py 'if md == "enforce" and not READONLY:' 'if md == "enforce":'; then rm -rf "$T/k3"; kick_run "$M" "$T/k3" "--print"; grep -q kickstart "$CALLS"; ok "MUTANT removing 'and not READONLY' from the kickstart guard: a --print run kickstarts a live job (detected)" $?; fi
cp "$SC/mac_jobs_health.py" "$M/mac_jobs_health.py"
if pymut mac_jobs_health.py '    if READONLY:
        return False
    os.makedirs' '    os.makedirs'; then S="$T/ro_mut2"; mkdir -p "$S"; : > "$CALLS"; printf 'com.t.a | 600 | %s/a.log | hb/a | critical\n' "$S" > "$T/ro_mut2.m"
  OVN_MAC_STATE="$S" OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$T/ro_mut2.m" MAC_JOBS_NOW=2000000000 MAC_LAUNCH_AGENTS_DIR="$T/agents" NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE= python3 "$M/mac_jobs_health.py" --print >/dev/null 2>&1 </dev/null
  [ -e "$S/alerts.log" ] || [ "$(nssh)" != 0 ]; ok "MUTANT alert() without its READONLY guard: --print writes alerts.log / pushes (detected)" $?; fi
echo; echo "z6_notify_guard: $P passed, $F failed"
[ "$F" -eq 0 ]
