#!/usr/bin/env bash
# test_p1_notify_delivery.sh - package P1-notify-delivery (2026-11-02). Mark got no ntfy messages: every Mac job posted to the relay's Tailscale IP while Tailscale was stopped, and nothing
# checked the result. Covers scripts/mac_lib.sh (pick_relay, checked mac_deliver), scripts/ovn_relay.py (python twin), vercel_state_check.py (push fallback, lost push not recorded,
# 3-polls prod ERROR escalation), box_deadman.py (LAN first), mac_jobs_health.py (no false emergency for a never-installed job, 'OK n jobs' line), the plist TEMPLATES (LAN relay, logs under
# ~/Library/Logs/shrike), mac_jobs.manifest <-> templates consistency, and the gpu_autoswap heartbeat.
# Hermetic: curl/ssh are stubs (absolute path via MAC_CURL / MAC_SSH), nothing touches the network, the real HOME, launchd or the box; NTFY_SERVER never points at a real relay.
# Every mutant (one per rule) must FAIL its scenario. Time/zone: TZ=UTC, epochs injected (MAC_NOW).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_test_tz.sh"
SC="$(cd "$HERE/../../.." && pwd)"   # <repo>/scripts
[ -f "$SC/mac_lib.sh" ] && [ -f "$SC/ovn_relay.py" ] && [ -f "$SC/mac_jobs_health.py" ] || { echo "  SKIP: Mac job scripts not present under $SC (queue-only tree: GPU box mirror)"; exit 0; }
QD="$SC/overnight-queue"
T="$(safe_mktemp_dir p1notify)" || exit 1
safe_set_sandbox_home "$T" || exit 1
trap 'safe_rm_rf "${T:?}"' EXIT
unset OVN_SSH OVN_MAC_JOBS MAC_NOW OVN_NTFY_GUARD_LOG OVN_RELAY_FALLBACK MAC_DIRECT_URL NTFY_TOPIC MAC_CURL MAC_SSH
export NTFY_SERVER="http://127.0.0.1:9"      # never a real relay, whatever happens
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }

mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
# stub curl: logs every call; hosts listed in $STUB_CURL_DOWN refuse (rc 7, prints 000 when -w is used); relay POST answers "<body>\n200"; ntfy.sh answers 200; probes answer 404
printf "curl %s\n" "$*" >> "$STUB_LOG"
url=""; for a in "$@"; do url="$a"; done
for d in $STUB_CURL_DOWN; do case "$url" in *"$d"*) case " $* " in *http_code*) printf '000';; esac; exit 7;; esac; done
case "$*" in
  *"-X POST"*) case "$url" in *ntfy.sh*|*direct.test*) printf '200';; *) printf '%s\n200' "$STUB_RELAY_BODY";; esac;;
  *) printf '404';;
esac
exit 0
EOF
cat > "$T/bin/ssh" <<'EOF'
#!/bin/sh
printf "ssh %s\n" "$*" >> "$STUB_LOG"
exit "${STUB_SSH_RC:-0}"
EOF
chmod 755 "$T/bin/curl" "$T/bin/ssh"
export STUB_LOG="$T/calls.log" MAC_CURL="$T/bin/curl" MAC_SSH="$T/bin/ssh" OVN_SSH="u@box.test" OVN_RELAY_FALLBACK=on
LAN="192.168.68.145:8099"; TS="100.79.64.64:8099"; TOPIC="shrike_ovn_311380987a"
RN=0
fresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/st$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$STUB_LOG"; unset STUB_CURL_DOWN STUB_RELAY_BODY STUB_SSH_RC MAC_NOW OVN_NTFY_GUARD_LOG; export OVN_RELAY_FALLBACK=on NTFY_SERVER="http://$TS"; }
posts() { grep -c "^curl .*-X POST.* http://$1/$TOPIC\$" "$STUB_LOG"; }          # POSTs to a relay base
direct() { grep -c "^curl .*-X POST.* https://ntfy.sh/$TOPIC\$" "$STUB_LOG"; }   # direct ntfy.sh posts
sshs() { grep -c "^ssh .*alerts.log" "$STUB_LOG"; }
bdeliver() { # bdeliver <lib> <sev> <key> <msg>
  bash -c '. "$1"; mac_deliver "$2" "$3" "$4"; exit $?' _ "$1" "$2" "$3" "$4" >/dev/null 2>&1
}
pdeliver() { # pdeliver <dir with ovn_relay.py> <sev> <key> <msg>
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import ovn_relay; ovn_relay.deliver(sys.argv[2], sys.argv[3], sys.argv[4])' "$1" "$2" "$3" "$4" >/dev/null 2>&1
}
LIB="$SC/mac_lib.sh"

echo "== (a) bash: pick_relay + checked mac_deliver"
fresh; export STUB_CURL_DOWN="$TS"
r="$(bash -c '. "$1"; pick_relay' _ "$LIB" 2>/dev/null)"
chk "pick_relay: Tailscale NTFY_SERVER down, LAN up -> LAN relay" test "$r" = "http://$LAN"
fresh; export NTFY_SERVER="http://relay.test:8099"
r="$(bash -c '. "$1"; pick_relay' _ "$LIB" 2>/dev/null)"
chk "pick_relay: a reachable NTFY_SERVER wins over the LAN default" test "$r" = "http://relay.test:8099"
fresh; export STUB_CURL_DOWN="$TS $LAN"
r="$(bash -c '. "$1"; pick_relay' _ "$LIB" 2>/dev/null)"
chk "pick_relay: nothing reachable -> the configured NTFY_SERVER (the post will fail and be handled), rc 0" test "$r" = "http://$TS"
fresh; export STUB_CURL_DOWN="$TS"; bdeliver "$LIB" warn k1 "hello"
chk "mac_deliver (warn): LAN up + Tailscale down -> posted to the LAN relay, never to Tailscale" bash -c "[ $(posts "$LAN") = 1 ] && [ $(posts "$TS") = 0 ]"
fresh; export STUB_CURL_DOWN="$TS"; bdeliver "$LIB" emergency k2 "box down"
chk "mac_deliver (emergency): LAN up + Tailscale down -> LAN relay took it: NO ssh fallback, NO direct post" bash -c "[ $(posts "$LAN") = 1 ] && [ $(sshs) = 0 ] && [ $(direct) = 0 ]"
fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$LIB" emergency k3 "box down"; rc=$?
chk "emergency, every relay down: ALSO ssh-appends alerts.log (marked undelivered) and posts directly to ntfy.sh, rc 0" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 1 ] && grep -q 'EMERGENCY undelivered' '$STUB_LOG' && [ $rc = 0 ]"
chk "emergency, every relay down: persistent [delivery-failed] marker in alerts.log" grep -q "\[delivery-failed\] k3" "$OVN_MAC_STATE/alerts.log"
fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$LIB" warn k4 "note"
chk "NON-emergency with every relay down: ssh digest line yes, direct post NEVER" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 0 ]"
fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$LIB" emergency k5 "again"; bdeliver "$LIB" emergency k5 "again"
chk "direct fallback is rate limited per key (second identical emergency: no second direct post)" test "$(direct)" = 1
bdeliver "$LIB" emergency k6 "other"
chk "... a different key is still allowed" test "$(direct)" = 2
fresh; export STUB_CURL_DOWN="$TS $LAN" MAC_DIRECT_DAILY_CAP=2; for k in a b c d; do bdeliver "$LIB" emergency "cap$k" "x"; done; unset MAC_DIRECT_DAILY_CAP
chk "direct fallback daily cap (2): four distinct emergencies -> two direct posts" test "$(direct)" = 2
fresh; export STUB_RELAY_BODY='{"action":"emergency:failed"}'; bdeliver "$LIB" emergency k7 "relay upstream failed"
chk "relay answering emergency:failed is NOT delivered (ssh + direct follow)" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 1 ]"
fresh; export OVN_NTFY_GUARD_LOG="$T/guard.log" NTFY_SERVER="http://relay.test:8099" STUB_CURL_DOWN="relay.test"; unset OVN_RELAY_FALLBACK; bdeliver "$LIB" emergency k8 "hermetic"
chk "under the test-suite guard (OVN_NTFY_GUARD_LOG) a dead custom relay is NOT redirected to the real LAN/Tailscale relay" bash -c "[ $(posts "$LAN") = 0 ] && [ $(posts "$TS") = 0 ] && ! grep -q '$LAN\|$TS' '$STUB_LOG'"
fresh; MAC_CURL=/nonexistent/curl MAC_SSH=/nonexistent/ssh bdeliver "$LIB" emergency k9 "no binaries"; rc=$?
chk "missing curl/ssh binaries: mac_deliver still returns 0" test "$rc" = 0

echo "== (a') python twin ovn_relay.py"
fresh; export STUB_CURL_DOWN="$TS"; pdeliver "$SC" warn k1 "hello"
chk "py: LAN up + Tailscale down -> posted to LAN, not Tailscale" bash -c "[ $(posts "$LAN") = 1 ] && [ $(posts "$TS") = 0 ]"
fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$SC" emergency k3 "box down"
chk "py: emergency with relay down -> ssh + ONE direct post + marker" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 1 ] && grep -q '\[delivery-failed\] k3' '$OVN_MAC_STATE/alerts.log'"
pdeliver "$SC" emergency k3 "box down"
chk "py: direct fallback rate limited per key (shares direct_sent.log with the bash twin)" test "$(direct)" = 1
bdeliver "$LIB" emergency k3 "box down"
chk "bash twin honours the python twin's direct_sent.log (still ONE direct post for k3)" test "$(direct)" = 1
fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$SC" warn k4 "note"
chk "py: NON-emergency never direct-posts" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 0 ]"
fresh; export STUB_CURL_DOWN="$TS"; pdeliver "$SC" emergency k2 "up on LAN"
chk "py: emergency taken by the LAN relay -> no ssh, no direct" bash -c "[ $(posts "$LAN") = 1 ] && [ $(sshs) = 0 ] && [ $(direct) = 0 ]"
fresh; export STUB_RELAY_BODY='{"action":"emergency:failed"}'; pdeliver "$SC" emergency k7 "x"
chk "py: relay answer emergency:failed -> fallbacks run" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 1 ]"
fresh; export OVN_NTFY_GUARD_LOG="$T/guard.log" NTFY_SERVER="http://relay.test:8099" STUB_CURL_DOWN="relay.test"; unset OVN_RELAY_FALLBACK; pdeliver "$SC" emergency k8 "hermetic"
chk "py: under the test-suite guard no redirect to the real relay" bash -c "! grep -q '$LAN\|$TS' '$STUB_LOG'"

echo "== (b) vercel_state_check.push + escalation"
VSC="$QD/vercel_state_check.py"
vpush() { # vpush <script> <title> <urgent 1|0>   -> prints push() result
  python3 -I - "$1" "$2" "$3" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vsc", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.push(sys.argv[2], "body", sys.argv[3] == "1", False))
PY
}
vpush1() { vpush "$@" | tail -n 1; }
fresh; export STUB_CURL_DOWN="$TS"; r="$(vpush1 "$VSC" "Vercel PRODUCTION x: ERROR" 1)"
chk "push(urgent): Tailscale down -> LAN relay, returns True" bash -c "[ '$r' = True ] && [ $(posts "$LAN") = 1 ]"
fresh; export STUB_CURL_DOWN="$TS $LAN"; r="$(vpush1 "$VSC" "Vercel PRODUCTION x: ERROR" 1)"
chk "push(urgent): relay down -> ssh alerts.log + direct ntfy.sh post, returns True, failure marker written" bash -c "[ '$r' = True ] && [ $(sshs) = 1 ] && [ $(direct) = 1 ] && grep -q 'delivery-failed' '$OVN_MAC_STATE/alerts.log'"
fresh; export STUB_CURL_DOWN="$TS $LAN"; r="$(vpush1 "$VSC" "Vercel previews failing: x (2)" 0)"
chk "push(note): relay down -> ssh digest line only, NEVER a direct post" bash -c "[ $(sshs) = 1 ] && [ $(direct) = 0 ]"
fresh; export STUB_CURL_DOWN="$TS $LAN direct.test ntfy.sh" STUB_SSH_RC=255; r="$(vpush1 "$VSC" "Vercel PRODUCTION x: ERROR" 1)"
chk "push(urgent): NO channel works -> returns False and leaves the [delivery-failed] marker" bash -c "[ '$r' = False ] && grep -q 'NO channel\|no channel' '$OVN_MAC_STATE/alerts.log'"

cat > "$T/vsc_drive.py" <<'PY'
import importlib.util, json, os, sys, time
script, statef = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("vsc", script); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.PROJECTS, m.STATE = ["p"], statef
m.token = lambda: "tok"
pushed = []
lost = os.environ.get("DRIVE_LOSE") == "1"
def fake_push(title, body, urgent, dry):
    pushed.append((title, urgent))
    return False if lost else True
m.push = fake_push
st = os.environ.get("DRIVE_STATE", "ERROR")
dep = dict(uid="d1", createdAt=int(time.time() * 1000), target="production", readyState=st, errorMessage="build failed", meta={})
m.api = lambda tok, path: {"projects": [{"name": "p", "id": "p1"}]} if "/v9/projects" in path else {"deployments": [dep]}
for _ in range(int(os.environ.get("DRIVE_POLLS", "1"))):
    m.main()
print(json.dumps(pushed))
PY
vdrive() { python3 -I "$T/vsc_drive.py" "$1" "$2" | tail -n 1; }   # env: DRIVE_POLLS DRIVE_STATE DRIVE_LOSE
cnt() { python3 -I -c 'import json,sys; rows=json.loads(sys.argv[1]); print(len([r for r in rows if sys.argv[2] in r[0]]))' "$1" "$2"; }
fresh; S="$T/vsc1.json"; rm -f "$S"; o="$(DRIVE_POLLS=2 vdrive "$VSC" "$S")"
chk "prod ERROR, 2 polls: one initial urgent push, NO escalation yet" bash -c "[ $(cnt "$o" 'PRODUCTION p: ERROR') = 1 ] && [ $(cnt "$o" 'still ERROR') = 0 ]"
rm -f "$S"; o="$(DRIVE_POLLS=3 vdrive "$VSC" "$S")"
chk "prod ERROR on 3 consecutive polls -> ONE urgent 'still ERROR' escalation" bash -c "[ $(cnt "$o" 'still ERROR') = 1 ]"
o="$(DRIVE_POLLS=2 vdrive "$VSC" "$S")"
chk "... deduped per day: further polls the same day do not escalate again" bash -c "[ $(cnt "$o" 'still ERROR') = 0 ]"
rm -f "$S"; o="$(DRIVE_POLLS=2 vdrive "$VSC" "$S")"; o2="$(DRIVE_POLLS=1 DRIVE_STATE=READY vdrive "$VSC" "$S")"; o3="$(DRIVE_POLLS=2 vdrive "$VSC" "$S")"
chk "a READY poll resets the consecutive-ERROR counter (2 + READY + 2 -> no escalation)" bash -c "[ $(cnt "$o3" 'still ERROR') = 0 ]"
rm -f "$S"; o="$(DRIVE_POLLS=2 DRIVE_LOSE=1 vdrive "$VSC" "$S")"
chk "a LOST push is not recorded as sent: the initial alert is retried on the next poll (2 attempts in 2 polls)" bash -c "[ $(cnt "$o" 'PRODUCTION p: ERROR') = 2 ]"

echo "== (c) box_deadman default targets: LAN first"
chk "DEFAULT_TARGETS lists the LAN address before Tailscale" python3 -I -c '
import importlib.util,sys
s=importlib.util.spec_from_file_location("bd",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
t=m.DEFAULT_TARGETS.split(); sys.exit(0 if t[0].endswith("192.168.68.145") and t[1].endswith("100.79.64.64") else 1)' "$QD/scripts/box_deadman.py"

echo "== (d)(e) mac_jobs_health: not_installed, OK line; manifest/templates"
HP="$SC/mac_jobs_health.py"
printf '%s\n' 'com.t.a | 600 | LOGA | hb/a | critical' 'com.t.live | 1800 | LOGL | hb/live | critical' > "$T/h.manifest"
hrun() { # hrun <script> [launchctl-table-lines...]; plists in $T/agents
  local s="$1"; shift
  { printf 'PID\tStatus\tLabel\n'; local e; for e in "$@"; do printf '%s\t0\t%s\n' "-" "$e"; done; } > "$T/lc.table"
  printf '#!/bin/sh\n[ "$1" = list ] && cat "%s"\nexit 0\n' "$T/lc.table" > "$T/bin/launchctl"; chmod 755 "$T/bin/launchctl"
  mkdir -p "$OVN_MAC_STATE/hb"; date +%s > "$OVN_MAC_STATE/hb/a"; date +%s > "$OVN_MAC_STATE/hb/live"
  printf '{"ts": %d, "mode": "enforce", "state": "ok", "head": "abc", "behind": 0, "ahead": 0, "detail": ""}' "$(date +%s)" > "$OVN_MAC_STATE/live_sync.json"
  OVN_MAC_JOBS=shadow MAC_LAUNCHCTL="$T/bin/launchctl" MAC_JOBS_MANIFEST="$T/h.manifest" MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 MAC_DISK_FREE_GIB=100 MAC_LAUNCH_AGENTS_DIR="$T/agents" \
    python3 "$s" --print > "$T/hout.txt" 2>&1 < /dev/null
}
mkdir -p "$T/agents"; : > "$T/agents/com.t.a.plist"
fresh; hrun "$HP" com.t.a
chk "a manifest job with NO plist in LaunchAgents (never installed) is 'not_installed', NOT an emergency (no relay emergency, no ssh, no kickstart)" bash -c "! grep -q 'X-Ovn-Level: emergency' '$STUB_LOG' && grep -q 'not_installed' '$OVN_MAC_STATE/health.json' && grep -q "not.installed:.com.t.live" '$T/hout.txt'"
chk "... and it is not counted as an outage (healthy=true)" python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["healthy"] else 1)' "$OVN_MAC_STATE/health.json"
chk "... a not_installed run does NOT print the OK line" bash -c "! grep -q '^OK ' '$T/hout.txt'"
: > "$T/agents/com.t.live.plist"; fresh; hrun "$HP" com.t.a
chk "plist installed but NOT loaded is still a not_loaded EMERGENCY (real outage)" bash -c "grep -q 'X-Ovn-Level: emergency' '$STUB_LOG' && grep -q 'not_loaded' '$OVN_MAC_STATE/health.json'"
fresh; hrun "$HP" com.t.a com.t.live
chk "healthy run prints the one-line 'OK 3 jobs' (2 manifest jobs + live-sync pseudo job)" grep -qx "OK 3 jobs" "$T/hout.txt"
chk "healthy run: no relay/ssh traffic" bash -c "! grep -q 'curl\|ssh' '$STUB_LOG'"
chk "manifest: every Mac job has a plist template and every template (except the supervisor itself) is in the manifest" python3 -I - "$SC" <<'PY'
import glob, os, sys
sc = sys.argv[1]
man = {l.split("|")[0].strip() for l in open(sc + "/mac_jobs.manifest") if l.strip() and not l.startswith("#")}
tpl = {os.path.basename(p)[:-6] for p in glob.glob(sc + "/mac_jobs/templates/*.plist")}
missing = man - tpl
extra = tpl - man - {"com.shrike.mac-jobs-health"}
print("manifest without template:", missing, "template without manifest row:", extra)
sys.exit(0 if not missing and not extra else 1)
PY
chk "templates: NTFY_SERVER is the LAN relay (never the Tailscale IP) and every log path is under ~/Library/Logs/shrike (never /tmp; fleet-review keeps ~/fleet_review/logs)" python3 -I - "$SC" <<'PY'
import glob, plistlib, sys
bad = []
for p in glob.glob(sys.argv[1] + "/mac_jobs/templates/*.plist"):
    s = open(p).read().replace("@HOME@", "/Users/x").replace("@LIVE@", "/Users/x/live")
    d = plistlib.loads(s.encode())
    ns = d.get("EnvironmentVariables", {}).get("NTFY_SERVER")
    if ns not in (None, "http://192.168.68.145:8099"):
        bad.append((p, ns))
    for k in ("StandardOutPath", "StandardErrorPath"):
        if "fleet-review" in p:
            continue   # its own ~/fleet_review/logs dir (not /tmp, survives reboot)
        if not d.get(k, "").startswith("/Users/x/Library/Logs/shrike/"):
            bad.append((p, k, d.get(k)))
print(bad)
sys.exit(1 if bad else 0)
PY
chk "installer creates ~/Library/Logs/shrike before bootstrapping (launchd does not create the StandardOutPath directory)" grep -q 'mkdir -p "\$HOME/Library/Logs/shrike"' "$SC/mac_jobs_install.sh"

echo "== (f) gpu_autoswap heartbeat"
GA="$QD/gpu_autoswap.sh"
mkdir -p "$T/gbin" "$T/home/overnight-queue/logs" "$T/home/overnight-queue/state"
printf '#!/bin/sh\ncase "$1" in inspect) echo true;; esac\nexit 0\n' > "$T/gbin/docker"; chmod 755 "$T/gbin/docker"
grun() { PATH="$T/gbin:$PATH" HOME="$T/home" bash "$1" >/dev/null 2>&1; }
hbn() { grep -c 'heartbeat: watcher alive' "$T/home/overnight-queue/logs/gpu_autoswap.log" 2>/dev/null; }
rm -f "$T/home/overnight-queue/logs/gpu_autoswap.log" "$T/home/overnight-queue/state/gpu_autoswap.hb"*
grun "$GA"; grun "$GA"
chk "gpu_autoswap: every run touches state/gpu_autoswap.hb; the log gets ONE heartbeat line per window (2 runs -> 1 line)" bash -c "[ -s '$T/home/overnight-queue/state/gpu_autoswap.hb' ] && [ $(hbn) = 1 ] && grep -q 'window hold=none' '$T/home/overnight-queue/logs/gpu_autoswap.log'"
HB_LOG_EVERY_S=0 grun "$GA"
chk "gpu_autoswap: window elapsed (HB_LOG_EVERY_S=0) -> another heartbeat line" test "$(hbn)" = 2
touch "$T/home/overnight-queue/state/art_window.hold"; rm -f "$T/home/overnight-queue/state/gpu_autoswap.hb"; grun "$GA"
chk "gpu_autoswap: the heartbeat is written BEFORE the art-window early exit" test -s "$T/home/overnight-queue/state/gpu_autoswap.hb"
rm -f "$T/home/overnight-queue/state/art_window.hold"

echo "== mutants (each must fail its scenario)"
MUT="$T/mut"; mkdir -p "$MUT/overnight-queue/scripts"
mutate() { python3 -I - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "mutation anchor %r found %d times in %s" % (old, s.count(old), sys.argv[1])
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
bmut() { mutate "$LIB" "$MUT/mac_lib.sh" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
pmut() { cp "$SC/ovn_pick_srv.py" "$MUT/"; mutate "$SC/ovn_relay.py" "$MUT/ovn_relay.py" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
if bmut no-lan-fallback 'if [ "$fb" = 1 ] && { [ -n "$base" ] || [ "$mode" = on ]; }; then' 'if false; then'; then
  fresh; export STUB_CURL_DOWN="$TS"; bdeliver "$MUT/mac_lib.sh" warn k1 "hello"
  chk "B1 (no LAN fallback) is caught: nothing reaches the LAN relay" bash -c "[ $(posts "$LAN") = 0 ]"
fi
if bmut emergency-no-ssh 'if [ "$sev" != emergency ] || [ "$relay_ok" != 1 ]; then' 'if [ "$sev" != emergency ]; then'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$MUT/mac_lib.sh" emergency k3 "x"
  chk "B2 (old behaviour: no ssh for an emergency) is caught" bash -c "[ $(sshs) = 0 ]"
fi
if bmut direct-for-all '[ "$sev" = emergency ] && [ "$guard_curl" != 1 ] && _mac_direct_post "$key" "$msg" && direct_ok=1' '_mac_direct_post "$key" "$msg" && direct_ok=1'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$MUT/mac_lib.sh" warn k4 "x"
  chk "B3 (non-emergency direct post) is caught" bash -c "[ $(direct) = 1 ]"
fi
if bmut unchecked-relay 'if _mac_post_relay "$c" "$sev" "$key" "$msg"; then relay_ok=1; break; fi' '_mac_post_relay "$c" "$sev" "$key" "$msg"; relay_ok=1; break'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$MUT/mac_lib.sh" emergency k3 "x"
  chk "B4 (curl result unchecked, the original bug) is caught: no fallback ran" bash -c "[ $(sshs) = 0 ] && [ $(direct) = 0 ]"
fi
if bmut no-direct-limit '[ "${n:-0}" -lt "${MAC_DIRECT_DAILY_CAP:-8}" ] && [ "${k:-0}" -eq 0 ] || return 1' 'true'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; bdeliver "$MUT/mac_lib.sh" emergency k5 "x"; bdeliver "$MUT/mac_lib.sh" emergency k5 "x"
  chk "B5 (no direct rate limit) is caught: two direct posts for one key" bash -c "[ $(direct) = 2 ]"
fi
if bmut no-guard-switch 'case "$mode" in on) fb=1;; off) fb=0;; *) [ -z "${OVN_NTFY_GUARD_LOG:-}" ] && fb=1;; esac' 'fb=1'; then
  fresh; export OVN_NTFY_GUARD_LOG="$T/guard.log" NTFY_SERVER="http://relay.test:8099" STUB_CURL_DOWN="relay.test"; unset OVN_RELAY_FALLBACK; bdeliver "$MUT/mac_lib.sh" emergency k8 "x"
  chk "B6 (fallback not disabled under the test guard) is caught: the real LAN relay was contacted" bash -c "grep -q '$LAN' '$STUB_LOG'"
fi
if pmut py-no-fallback 'if fb and (base or mode == "on"):' 'if False:'; then
  fresh; export STUB_CURL_DOWN="$TS"; pdeliver "$MUT" warn k1 "hello"
  chk "P1 (py: no LAN fallback) is caught" bash -c "[ $(posts "$LAN") = 0 ]"
fi
if pmut py-direct-nonurgent 'if urgent and not _guarded_real("MAC_CURL"):
                res["direct"] = direct_post(key, title, msg)' 'if True:
                res["direct"] = direct_post(key, title, msg)'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$MUT" warn k4 "x"
  chk "P2 (py: non-emergency direct post) is caught" bash -c "[ $(direct) = 1 ]"
fi
if pmut py-no-ssh-emergency 'if not (urgent and res["relay"]) and not _guarded_real("MAC_SSH"):' 'if not urgent and not _guarded_real("MAC_SSH"):'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$MUT" emergency k3 "x"
  chk "P3 (py: no ssh fallback for a failed emergency) is caught" bash -c "[ $(sshs) = 0 ]"
fi
if pmut py-unchecked 'if rc != 0:
        return False
    body_out, _, code = out.rpartition("\n")
    code = code.strip()
    if code and not code.startswith("2"):
        return False' 'body_out, _, code = out.rpartition("\n")'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$MUT" emergency k3 "x"
  chk "P4 (py: relay result unchecked, the original bug) is caught: the refused relay counts as delivered, no fallback" bash -c "[ $(sshs) = 0 ] && [ $(direct) = 0 ]"
fi
if pmut py-no-limit 'return not any(k == _ksafe(key) and t - ts < cd for ts, k in rows)' 'return True'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN"; pdeliver "$MUT" emergency k5 "x"; pdeliver "$MUT" emergency k5 "x"
  chk "P5 (py: no per-key direct limit) is caught" bash -c "[ $(direct) = 2 ]"
fi
# vercel mutants run from MUT/overnight-queue (the module imports ../ovn_relay.py)
vmut() { mutate "$VSC" "$MUT/overnight-queue/vercel_state_check.py" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; cp "$SC/ovn_relay.py" "$SC/ovn_pick_srv.py" "$MUT/"; }
if vmut no-escalation 'n_err >= ESCALATE_POLLS and' 'False and'; then
  fresh; S="$T/vscm1.json"; rm -f "$S"; o="$(DRIVE_POLLS=3 vdrive "$MUT/overnight-queue/vercel_state_check.py" "$S")"
  chk "V1 (no 3-poll escalation) is caught" bash -c "[ $(cnt "$o" 'still ERROR') = 0 ]"
fi
if vmut lost-push-recorded 'if push("Vercel PRODUCTION %s: %s" % (name, st(prod[0])), (prod[0].get("errorMessage") or "newest production deploy is not live")[:200], True, dry) is not False:' 'if push("Vercel PRODUCTION %s: %s" % (name, st(prod[0])), (prod[0].get("errorMessage") or "newest production deploy is not live")[:200], True, dry) is not None or True:'; then
  fresh; S="$T/vscm2.json"; rm -f "$S"; o="$(DRIVE_POLLS=2 DRIVE_LOSE=1 vdrive "$MUT/overnight-queue/vercel_state_check.py" "$S")"
  chk "V2 (lost push recorded as sent) is caught: no retry" bash -c "[ $(cnt "$o" 'PRODUCTION p: ERROR') = 1 ]"
fi
if vmut push-print-only 'ok = bool(r.get("relay") or r.get("direct") or (not urgent and r.get("ssh")))' 'ok = True'; then
  fresh; export STUB_CURL_DOWN="$TS $LAN direct.test ntfy.sh" STUB_SSH_RC=255; r="$(vpush1 "$MUT/overnight-queue/vercel_state_check.py" "x" 1)"
  chk "V3 (push always reports success) is caught" bash -c "[ '$r' = True ]"
fi
hmut() { cp "$SC/ovn_relay.py" "$SC/ovn_pick_srv.py" "$MUT/"; mutate "$HP" "$MUT/mac_jobs_health.py" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
if hmut no-not-installed 'if tbl is not None and not loaded and not plist_installed(label):' 'if False:'; then
  mkdir -p "$T/agents2"; fresh; hrun "$MUT/mac_jobs_health.py" com.t.a
  rm -f "$T/agents/com.t.live.plist"; fresh; hrun "$MUT/mac_jobs_health.py" com.t.a
  chk "H1 (never-installed job treated as not_loaded) is caught: false EMERGENCY returns" bash -c "grep -q 'X-Ovn-Level: emergency' '$STUB_LOG'"
  : > "$T/agents/com.t.live.plist"
fi
if hmut no-ok-line 'print("OK %d jobs" % len(jobs_out))' 'pass'; then
  fresh; hrun "$MUT/mac_jobs_health.py" com.t.a com.t.live
  chk "H2 (no OK line) is caught" bash -c "! grep -qx 'OK 3 jobs' '$T/hout.txt'"
fi
hstale() { # hstale <script>: one critical job, loaded, success heartbeat 5000 s old (limit 600) -> a stale EMERGENCY, every relay down
  fresh; export STUB_CURL_DOWN="$TS $LAN"
  printf '%s\n' 'com.t.a | 600 | LOGA | hb/a | critical' > "$T/h2.manifest"
  { printf 'PID\tStatus\tLabel\n'; printf '%s\t0\t%s\n' "-" com.t.a; } > "$T/lc.table"
  printf '#!/bin/sh\n[ "$1" = list ] && cat "%s"\nexit 0\n' "$T/lc.table" > "$T/bin/launchctl"; chmod 755 "$T/bin/launchctl"
  mkdir -p "$OVN_MAC_STATE/hb"; echo $(( $(date +%s) - 5000 )) > "$OVN_MAC_STATE/hb/a"
  printf '{"ts": %d, "mode": "enforce", "state": "ok", "head": "abc", "behind": 0, "ahead": 0, "detail": ""}' "$(date +%s)" > "$OVN_MAC_STATE/live_sync.json"
  OVN_MAC_JOBS=shadow MAC_LAUNCHCTL="$T/bin/launchctl" MAC_JOBS_MANIFEST="$T/h2.manifest" MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 MAC_DISK_FREE_GIB=100 MAC_LAUNCH_AGENTS_DIR="$T/agents" python3 "$1" >/dev/null 2>&1 </dev/null
}
hstale "$HP"
chk "supervisor emergency (stale critical job) with every relay down: ssh digest line AND one direct post" bash -c "[ $(sshs) -ge 1 ] && [ $(direct) = 1 ] && grep -q 'X-Ovn-Level: emergency' '$STUB_LOG'"
if hmut health-no-ovn-relay 'ovn_relay.deliver(sev, key, msg)' 'pass'; then
  hstale "$MUT/mac_jobs_health.py"
  chk "H3 (supervisor not using the fallback delivery) is caught" bash -c "[ $(direct) = 0 ] && [ $(sshs) = 0 ]"
fi
if mutate "$QD/scripts/box_deadman.py" "$MUT/box_deadman.py" 'DEFAULT_TARGETS = "mhintermeister@192.168.68.145 mhintermeister@100.79.64.64"' 'DEFAULT_TARGETS = "mhintermeister@100.79.64.64 mhintermeister@192.168.68.145"'; then
  chk "D1 (Tailscale first again) is caught" bash -c "! python3 -I -c '
import importlib.util,sys
s=importlib.util.spec_from_file_location(\"bd\",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
t=m.DEFAULT_TARGETS.split(); sys.exit(0 if t[0].endswith(\"192.168.68.145\") else 1)' '$MUT/box_deadman.py'"
fi
if mutate "$GA" "$MUT/gpu_autoswap.sh" 'echo "$_now" > "$STATE/gpu_autoswap.hb" 2>/dev/null' ':'; then
  rm -f "$T/home/overnight-queue/state/gpu_autoswap.hb"; grun "$MUT/gpu_autoswap.sh"
  chk "G1 (no heartbeat file) is caught" bash -c "[ ! -e '$T/home/overnight-queue/state/gpu_autoswap.hb' ]"
fi

echo; echo "p1_notify_delivery: $((n-fails))/$n passed"; [ "$fails" = 0 ]
