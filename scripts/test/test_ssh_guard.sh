#!/usr/bin/env bash
# scripts/test/ntfy_guard.sh box guard (qacov F7): ssh/scp/rsync to a box address from the real system binary are swallowed + logged (rc 255), a stub first on PATH or an absolute-path
# shim still sees the call, other hosts pass through, OVN_SSH_GUARD=off disables it. Hermetic: the "box" address is overridden to RFC 5737 192.0.2.1 (never routed), so even the MUTANT
# (guard broken) can only attempt a 2 s connection to a black hole. SKIPs when /usr/bin/ssh is not the system ssh. bash 3.2 ok.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/ntfy_guard.sh"; [ -f "$G" ] || { echo "  SKIP: ntfy_guard.sh not found"; exit 0; }
SSHBIN="$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin type -P ssh 2>/dev/null)"   # type -P: `command -v` would answer "ssh" (the exported guard function) when run inside run_all.sh
case "$SSHBIN" in /usr/bin/ssh|/bin/ssh|/usr/local/bin/ssh|/opt/homebrew/bin/ssh) ;; *) echo "  SKIP: no system ssh"; exit 0;; esac
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
BOX=192.0.2.1
# t <guard file> <command...>: runs the command in a fresh bash that sourced the guard; prints rc to $T/rc, stdout+stderr to $T/out
t(){ local g="$1"; shift; ( export OVN_SSH_GUARD_LOG="$T/guard.log" OVN_GUARD_BOX_HOSTS="$BOX" OVN_NTFY_GUARD_LOG="$T/ntfy.log"; unset OVN_SSH_GUARD; . "$g"; "$@" ) > "$T/out" 2>&1; echo $? > "$T/rc"; }
rm -f "$T/guard.log"
t "$G" ssh -o BatchMode=yes -o ConnectTimeout=2 "mhintermeister@$BOX" 'echo x >> ~/overnight-queue/state/alerts.log'
ok "real ssh to a box address: swallowed, rc 255, logged with the command line" "$([ "$(cat "$T/rc")" = 255 ] && grep -q "ssh -o BatchMode=yes .*mhintermeister@$BOX" "$T/guard.log" && echo 1 || echo 0)"
rm -f "$T/guard.log"; t "$G" scp -q -o ConnectTimeout=2 /dev/null "mhintermeister@$BOX:overnight-queue/state/x.json"
ok "real scp to a box address: swallowed (rc 255) and logged" "$([ "$(cat "$T/rc")" = 255 ] && grep -q "scp -q" "$T/guard.log" && echo 1 || echo 0)"
rm -f "$T/guard.log"; t "$G" rsync -a /dev/null "mhintermeister@$BOX:scratch/"
ok "real rsync to a box address: swallowed (rc 255) and logged" "$([ "$(cat "$T/rc")" = 255 ] && grep -q "rsync -a" "$T/guard.log" && echo 1 || echo 0)"
# a stub first on PATH sees the call (the guard only swallows the REAL binary)
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "stub ssh $*" >> "%s/stub.log"\nexit 0\n' "$T" > "$T/bin/ssh"; chmod +x "$T/bin/ssh"
rm -f "$T/guard.log" "$T/stub.log"; ( export PATH="$T/bin:$PATH"; t "$G" ssh "mhintermeister@$BOX" true )
ok "a stub ssh first on PATH still sees the box call (not swallowed, nothing logged)" "$([ "$(cat "$T/rc")" = 0 ] && grep -q "stub ssh mhintermeister@$BOX true" "$T/stub.log" && [ ! -s "$T/guard.log" ] && echo 1 || echo 0)"
# absolute-path shim (QA_E2E_SSH style): a different binary altogether, never touched by the function
rm -f "$T/stub.log"; t "$G" "$T/bin/ssh" "mhintermeister@$BOX" true
ok "an absolute-path shim is untouched (functions only shadow the bare name)" "$([ "$(cat "$T/rc")" = 0 ] && grep -q 'stub ssh' "$T/stub.log" && echo 1 || echo 0)"
# not a box host: passes through to the real binary (which fails fast on a bad option so no network is needed)
rm -f "$T/guard.log"; t "$G" ssh -o NoSuchOptionXyz=1 192.0.2.77 true
ok "a non-box host is passed through to the real ssh (its own error, rc != 255-by-guard, nothing logged)" "$([ ! -s "$T/guard.log" ] && grep -qi 'unsupported\|bad\|unknown\|invalid' "$T/out" && echo 1 || echo 0)"
# kill switch
rm -f "$T/guard.log"; ( export OVN_SSH_GUARD=off; export OVN_SSH_GUARD_LOG="$T/guard.log" OVN_GUARD_BOX_HOSTS="$BOX"; . "$G"; export OVN_SSH_GUARD=off; ssh -o NoSuchOptionXyz=1 "$BOX" true ) > "$T/out" 2>&1
ok "OVN_SSH_GUARD=off passes box calls through to the real binary (nothing logged)" "$([ ! -s "$T/guard.log" ] && grep -qi 'unsupported\|bad\|unknown\|invalid' "$T/out" && echo 1 || echo 0)"
# the curl guard is intact
# --resolve pins ntfy.sh to the RFC 5737 black hole: even if the guard failed, nothing could reach the real ntfy.sh (the connection would time out after 1 s, rc 28)
rm -f "$T/ntfy.log"; t "$G" curl -fsS --connect-timeout 1 --resolve ntfy.sh:443:192.0.2.1 -d x https://ntfy.sh/qacov_guard_test
ok "the curl guard swallows ntfy.sh for THIS host's curl ($(type -P curl)): rc 0 and logged (before 2026-10-10 the Homebrew keg curl was not covered)" "$([ "$(cat "$T/rc")" = 0 ] && grep -q 'ntfy.sh' "$T/ntfy.log" && echo 1 || echo 0)"
# MUTANT: the box match never fires -> the real ssh would run (here against the black-hole address, 2 s)
sed 's/\*"\$h"\*) printf/*"NEVER-MATCHES-$h"*) printf/' "$G" > "$T/mut_guard.sh"
ok "mutant differs" "$(cmp -s "$T/mut_guard.sh" "$G" && echo 0 || echo 1)"
rm -f "$T/guard.log"; t "$T/mut_guard.sh" ssh -o BatchMode=yes -o ConnectTimeout=2 "mhintermeister@$BOX" true
ok "MUTANT (match broken): nothing is logged and the real ssh ran - the swallow assertion bites" "$([ ! -s "$T/guard.log" ] && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
