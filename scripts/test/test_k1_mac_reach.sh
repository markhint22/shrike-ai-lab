#!/usr/bin/env bash
# test_k1_mac_reach.sh - package K1-mac-reach (2026-11-01). Mac->box links died for 4 days because Tailscale was stopped and every script defaulted to the Tailscale address.
# Covers: pick_srv (bash, mac_lib.sh) and its python twin (ovn_pick_srv.py): OVN_SSH wins, LAN probed BEFORE Tailscale, both down => LAN + rc 0; mac_jobs_health.py: a Mac-job
# heartbeat stale > 6 h is an EMERGENCY (a 2 h stale non-critical job stays a WARN), Mac disk bullet < 8 GiB / emergency < 2 GiB; railway_config_guard.py tolerates ENOSPC (rc 0, good copy never truncated).
# Hermetic: ssh is a PATH stub, time pinned, no network, tmp under mktemp. Each mutant (probe order swapped, escalation threshold broken, guard catch removed) must FAIL its scenario.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SC="$(cd "$HERE/../../.." && pwd)"   # shared/scripts
[ -f "$SC/mac_lib.sh" ] && [ -f "$SC/ovn_pick_srv.py" ] && [ -f "$SC/mac_jobs_health.py" ] && [ -f "$SC/railway_config_guard.py" ] || { echo "  SKIP: K1 Mac scripts not present under $SC (box copy of the queue dir)"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/k1test.XXXXXX")" || exit 1
case "$T" in /*/k1test.*) :;; *) echo "  FAIL: unsafe tmp"; exit 1;; esac
trap 'rm -rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
LAN="mhintermeister@192.168.68.145"; TS="mhintermeister@100.79.64.64"
mkdir -p "$T/bin"
cat > "$T/bin/ssh" <<'EOF'
#!/bin/sh
# stub ssh: logs the target, succeeds only for targets listed in $STUB_UP
t=""; for a in "$@"; do case "$a" in *@*) t="$a";; esac; done
echo "$t" >> "$STUB_LOG"
case " $STUB_UP " in *" $t "*) exit 0;; esac
exit 255
EOF
chmod +x "$T/bin/ssh"
export STUB_LOG="$T/ssh.log"; export PATH="$T/bin:$PATH"; unset OVN_SSH MAC_SSH OVN_LAN_SRV OVN_TS_SRV

bash_pick() { # bash_pick <lib> -> target on stdout
  bash -c '. "$1"; pick_srv; echo "rc=$?" >&2' _ "$1" 2>"$T/rc.txt"
}
py_pick() { python3 "$1" 2>/dev/null; }
order_ok() { # order_ok <lib-or-py> <kind>   the whole ordering contract; rc 0 = contract holds
  local f="$1" kind="$2" pick bad=0 got
  if [ "$kind" = sh ]; then pick=bash_pick; else pick=py_pick; fi
  : > "$STUB_LOG"; export STUB_UP="$LAN $TS"; got="$($pick "$f")"; [ "$got" = "$LAN" ] || bad=1
  [ "$(head -n1 "$STUB_LOG")" = "$LAN" ] || bad=1                         # LAN is probed FIRST
  : > "$STUB_LOG"; export STUB_UP="$LAN"; got="$($pick "$f")"; [ "$got" = "$LAN" ] || bad=1   # LAN up, Tailscale down => LAN
  : > "$STUB_LOG"; export STUB_UP="$TS"; got="$($pick "$f")"; [ "$got" = "$TS" ] || bad=1     # only Tailscale up => Tailscale
  : > "$STUB_LOG"; export STUB_UP=""; got="$($pick "$f")"; [ "$got" = "$LAN" ] || bad=1      # both down => LAN fallback
  [ "$(wc -l < "$STUB_LOG" | tr -d ' ')" = 2 ] || bad=1                  # ... after probing exactly both
  return $bad
}
echo "== pick_srv (bash)"
order_ok "$SC/mac_lib.sh" sh; ok "bash: LAN probed first; LAN up+TS down => LAN; TS only => TS; both down => LAN fallback" $?
bash_pick "$SC/mac_lib.sh" >/dev/null; grep -q '^rc=0$' "$T/rc.txt"; ok "bash: rc 0 even when both probes fail" $?
export STUB_UP=""; : > "$STUB_LOG"; OVN_SSH="me@elsewhere" bash_pick "$SC/mac_lib.sh" > "$T/o.txt"
[ "$(cat "$T/o.txt")" = "me@elsewhere" ] && [ ! -s "$STUB_LOG" ]; ok "bash: OVN_SSH wins and nothing is probed" $?
sed 's/for c in "\$lan" "\$ts"; do/for c in "$ts" "$lan"; do/' "$SC/mac_lib.sh" > "$T/mac_lib_mut.sh"; ! cmp -s "$T/mac_lib_mut.sh" "$SC/mac_lib.sh"; ok "mutant built (probe order swapped)" $?
order_ok "$T/mac_lib_mut.sh" sh; r=$?; [ "$r" != 0 ]; ok "MUTANT swapped probe order (Tailscale first) FAILS the ordering test" $?
echo "== pick_srv (python twin)"
order_ok "$SC/ovn_pick_srv.py" py; ok "python: same contract as bash" $?
export STUB_UP=""; OVN_SSH="me@elsewhere" py_pick "$SC/ovn_pick_srv.py" > "$T/o.txt"; [ "$(cat "$T/o.txt")" = "me@elsewhere" ]; ok "python: OVN_SSH wins" $?
sed 's/for cand in (lan, ts):/for cand in (ts, lan):/' "$SC/ovn_pick_srv.py" > "$T/ovn_pick_srv_mut.py"; ! cmp -s "$T/ovn_pick_srv_mut.py" "$SC/ovn_pick_srv.py"; ok "python mutant built" $?
order_ok "$T/ovn_pick_srv_mut.py" py; r=$?; [ "$r" != 0 ]; ok "MUTANT python swapped probe order FAILS" $?
echo "== no hard-coded Tailscale default left in the Mac->box paths"
left="$(grep -nE 'OVN_SSH:-mhintermeister@100\.79\.64\.64|OVN_SSH", "mhintermeister@100\.79\.64\.64' "$SC/mac_lib.sh" "$SC/qa-staging-e2e.sh" "$SC/qa-notes-bridge.sh" "$SC/qa-staging-export.sh" "$SC/overnight-queue/claude_queue_bridge.sh" "$SC/mac_jobs_health.py" "$SC/qa-status" | wc -l | tr -d ' ')"
[ "$left" = 0 ]; ok "6 call sites no longer default to the Tailscale address (found $left)" $?
for f in qa-staging-e2e.sh qa-notes-bridge.sh qa-staging-export.sh overnight-queue/claude_queue_bridge.sh; do grep -q 'pick_srv' "$SC/$f"; ok "$f uses pick_srv" $?; done
echo "== mac_jobs_health.py: delivery + box copy use the probed target; always exit 0"
S="$T/hs"; mkdir -p "$S/hb"; : > "$STUB_LOG"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
printf 'PID\tStatus\tLabel\n-\t0\tcom.t.b\n' > "$T/lc.table"
printf '#!/bin/sh\ncat "%s"\n' "$T/lc.table" > "$T/bin/launchctl"; chmod +x "$T/bin/launchctl"
NOW=2000000000
printf 'com.t.b | 3600 | %s/b.log | hb/b |\n' "$S" > "$S/m"
printf '{"ts": %d, "mode": "enforce", "state": "ok", "head": "abc1234", "behind": 0, "ahead": 0, "detail": "", "dir": "x"}' "$NOW" > "$S/live_sync.json"
hrun() { # hrun <hb-age-s> [extra env...] ; fresh state each time
  local age="$1"; shift; rm -rf "$S/alerts.log" "$S/alert_sent" "$S/health.json" "$S/health_state.json"
  echo $((NOW - age)) > "$S/hb/b"
  env OVN_MAC_STATE="$S" OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$S/m" MAC_JOBS_NOW=$NOW MAC_JOBS_UID=501 MAC_LAUNCHCTL="$T/bin/launchctl" MAC_CURL="$T/bin/curl" \
      NTFY_SERVER=http://127.0.0.1:9 MAC_DISK_FREE_GIB=100 "$@" python3 "${HP:-$SC/mac_jobs_health.py}" > "$T/h.out" 2>&1 < /dev/null
}
export STUB_UP="$LAN"; hrun 7200 OVN_SSH=; hrc=$?
[ "$hrc" = 0 ] && grep -q '\[warn\] com.t.b:stale' "$S/alerts.log" && ! grep -q 'emergency' "$S/alerts.log"; ok "heartbeat 2 h old (limit 1 h): still a WARN (not escalated), exit 0" $?
hrun 25200; hrc=$?
[ "$hrc" = 0 ] && grep -q '\[emergency\] com.t.b:stale' "$S/alerts.log"; ok "heartbeat 7 h old on a NON-critical job: EMERGENCY alert, exit 0" $?
hrun 25200 MAC_HB_ESCALATE=off; ! grep -q 'emergency' "$S/alerts.log"; ok "MAC_HB_ESCALATE=off restores the old WARN" $?
sed 's/return age > lim/return age > lim * 1000/' "$SC/mac_jobs_health.py" > "$SC/.k1_mut_health.py"; ! cmp -s "$SC/.k1_mut_health.py" "$SC/mac_jobs_health.py"; ok "health mutant built" $?
HP="$SC/.k1_mut_health.py" hrun 25200; ! grep -q '\[emergency\] com.t.b:stale' "$S/alerts.log"; ok "MUTANT broken 6 h threshold: the emergency test FAILS (escalation not raised)" $?
rm -f "$SC/.k1_mut_health.py"
# delivery of a WARN goes over ssh to the PROBED target (LAN up, no OVN_SSH), not the Tailscale address
: > "$STUB_LOG"; export STUB_UP="$LAN"; hrun 7200 NTFY_SERVER=; hrc=$?
grep -q "^$LAN\$" "$STUB_LOG" && ! grep -q "^$TS\$" "$STUB_LOG" && [ "$hrc" = 0 ]; ok "WARN delivery + box copy go to the LAN target when only LAN answers (exit 0)" $?
: > "$STUB_LOG"; export STUB_UP=""; hrun 7200 NTFY_SERVER=; hrc=$?
[ "$hrc" = 0 ] && grep -q "^$LAN\$" "$STUB_LOG"; ok "both links down: supervisor still exits 0 (LAN fallback target used)" $?
echo "== Mac disk free check"
hrun 100 MAC_DISK_FREE_GIB=50; ! grep -q 'mac-disk' "$S/alerts.log" 2>/dev/null; ok "50 GiB free: no disk alert" $?
hrun 100 MAC_DISK_FREE_GIB=5; grep -q '\[warn\] mac-disk:low' "$S/alerts.log" && ! grep -q 'emergency' "$S/alerts.log"; ok "5 GiB free (< 8): digest-level warn only" $?
grep -q 'mac-disk low 5.0GiB' "$S/health.json"; ok "5 GiB free: health summary carries the disk bullet" $?
hrun 100 MAC_DISK_FREE_GIB=1.5; grep -q '\[emergency\] mac-disk:emergency' "$S/alerts.log"; ok "1.5 GiB free (< 2): EMERGENCY" $?
echo "== railway_config_guard.py tolerates ENOSPC"
cat > "$T/enospc.py" <<'EOF'
import builtins, errno, importlib.util, json, os, sys
mode, home, guard = sys.argv[1], sys.argv[2], sys.argv[3]
os.environ["HOME"] = home
spec = importlib.util.spec_from_file_location("g", guard); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
real = builtins.open
def full(path, mode_="r", *a, **k):
    if isinstance(path, str) and ("w" in mode_ or "a" in mode_) and path.startswith(home):
        # ENOSPC: the open itself succeeds for a truncating write (the filesystem truncates), then the write fails - emulate the worst case honestly
        f = real(path, mode_, *a, **k)
        class W:
            def __getattr__(s, n): return getattr(f, n)
            def __enter__(s): return s
            def __exit__(s, *e): f.close()
            def write(s, d): raise OSError(errno.ENOSPC, "No space left on device")
            def flush(s): raise OSError(errno.ENOSPC, "No space left on device")
        return W()
    return real(path, mode_, *a, **k)
builtins.open = full
rc = g.main()
builtins.open = real
good = os.path.join(home, ".railway", "config.good.json")
print("rc=%s good_intact=%s" % (rc, json.load(open(good)) == {"user": {"refreshToken": "KEEP"}}))
print("cfg_unchanged=%s" % (real(os.path.join(home, ".railway", "config.json")).read() == sys.argv[4].replace("\\n", "\n")))
print("tmp_left=%s" % any(f.endswith(".tmp") for f in os.listdir(os.path.join(home, ".railway"))))
EOF
setup_home() { rm -rf "$T/home"; mkdir -p "$T/home/.railway"; echo '{"user": {"refreshToken": "KEEP"}}' > "$T/home/.railway/config.good.json"; printf '%s' "$1" > "$T/home/.railway/config.json"; }
setup_home '{"user": {"refreshToken": "NEW"}}'
out="$(python3 "$T/enospc.py" valid "$T/home" "$SC/railway_config_guard.py" '{"user": {"refreshToken": "NEW"}}' 2>&1)"
echo "$out" | grep -q 'rc=0 good_intact=True' && echo "$out" | grep -q 'tmp_left=False'; ok "valid config + disk full: snapshot step skipped, rc 0, existing good copy NOT truncated, no tmp litter ($(echo "$out" | tr '\n' ' '))" $?
setup_home '{corrupt'
out="$(python3 "$T/enospc.py" corrupt "$T/home" "$SC/railway_config_guard.py" '{corrupt' 2>&1)"
echo "$out" | grep -q 'rc=0 good_intact=True' && echo "$out" | grep -q 'cfg_unchanged=True'; ok "corrupt config + disk full: repair skipped, rc 0, good copy intact, config not made worse ($(echo "$out" | tr '\n' ' '))" $?
sed 's/    except OSError as e:  # K1/    except KeyError as e:  # K1/' "$SC/railway_config_guard.py" > "$T/guard_mut.py"; ! cmp -s "$T/guard_mut.py" "$SC/railway_config_guard.py"; ok "guard mutant built (OSError no longer caught)" $?
setup_home '{"user": {"refreshToken": "NEW"}}'
python3 "$T/enospc.py" valid "$T/home" "$T/guard_mut.py" '{"user": {"refreshToken": "NEW"}}' >/dev/null 2>&1; r=$?; [ "$r" != 0 ]; ok "MUTANT without the OSError catch crashes under ENOSPC (test FAILS on old behaviour)" $?
setup_home '{"user": {"refreshToken": "KEEP"}}'; rm -f "$T/home/.railway/config.good.json"
HOME="$T/home" python3 "$SC/railway_config_guard.py" >/dev/null 2>&1; rc=$?; [ "$rc" = 0 ] && grep -q KEEP "$T/home/.railway/config.good.json"; ok "normal disk: snapshot still written (no regression)" $?
echo; echo "k1 mac reach: $n checks, $fails failed"
[ "$fails" = 0 ]
