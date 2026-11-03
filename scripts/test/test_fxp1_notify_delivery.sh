#!/usr/bin/env bash
# test_fxp1_notify_delivery.sh - fix package FX-P1 (2026-11-02), reviewer defects on P1-notify-delivery.
#  (1) NTFY_SERVER unset + URGENT: before, no candidate => attempted=False => only an ssh line and push() still returned True (escalation recorded as sent, nothing pushed).
#      Now an emergency with no relay takes the same rate-limited direct-post path as a failed relay, and vercel push() is True only when a real push channel (relay/direct) took it.
#  (2) Under the suite guard (OVN_NTFY_GUARD_LOG) with the REAL curl/ssh (MAC_CURL/MAC_SSH not stubbed) python ovn_relay and bash mac_deliver skip the direct ntfy.sh post and the box ssh.
#  Relay answer 'emergency:capped' stays counted as delivered (the relay's own policy cap).
# Hermetic: stub curl/ssh logging every call; TZ=UTC; lib_safe_tmp for temp dirs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_test_tz.sh"
SC="$(cd "$HERE/../../.." && pwd)"
[ -f "$SC/mac_lib.sh" ] && [ -f "$SC/ovn_relay.py" ] || { echo "  SKIP: Mac job scripts not present under $SC"; exit 0; }
QD="$SC/overnight-queue"
T="$(safe_mktemp_dir fxp1)" || exit 1
safe_set_sandbox_home "$T" || exit 1
trap 'safe_rm_rf "${T:?}"' EXIT
unset OVN_SSH OVN_MAC_JOBS MAC_NOW OVN_NTFY_GUARD_LOG OVN_RELAY_FALLBACK MAC_DIRECT_URL NTFY_TOPIC MAC_CURL MAC_SSH NTFY_SERVER
export TZ=UTC
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'STUB'
#!/bin/sh
printf "curl %s\n" "$*" >> "$STUB_LOG"
url=""; for a in "$@"; do url="$a"; done
case "$*" in
  *"-X POST"*) case "$url" in *ntfy.sh*|*direct.test*) printf '%s' "${STUB_DIRECT_CODE:-200}";; *) printf '%s\n200' "$STUB_RELAY_BODY";; esac;;
  *) printf '404';;
esac
exit 0
STUB
cat > "$T/bin/ssh" <<'STUB'
#!/bin/sh
printf "ssh %s\n" "$*" >> "$STUB_LOG"
exit "${STUB_SSH_RC:-0}"
STUB
chmod 755 "$T/bin/curl" "$T/bin/ssh"
export STUB_LOG="$T/calls.log" OVN_SSH="u@box.test"
RN=0
fresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/st$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$STUB_LOG"; unset OVN_NTFY_GUARD_LOG NTFY_SERVER STUB_DIRECT_CODE STUB_RELAY_BODY STUB_SSH_RC MAC_CURL MAC_SSH; export OVN_RELAY_FALLBACK=auto MAC_DIRECT_URL="http://direct.test"; }
stub() { export MAC_CURL="$T/bin/curl" MAC_SSH="$T/bin/ssh"; }
direct() { grep -c "^curl .*-X POST.* http://direct.test/" "$STUB_LOG"; }
sshs() { grep -c "^ssh .*alerts.log" "$STUB_LOG"; }
anycall() { [ -s "$STUB_LOG" ]; }
LIB="$SC/mac_lib.sh"
bdeliver() { bash -c '. "$1"; mac_deliver "$2" "$3" "$4"' _ "$LIB" "$1" "$2" "$3" >/dev/null 2>&1; }
pdeliver() { python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import ovn_relay; ovn_relay.deliver(sys.argv[2], sys.argv[3], sys.argv[4])' "$SC" "$1" "$2" "$3" >/dev/null 2>&1; }
vpush() { # vpush <urgent 0|1> -> prints True/False
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import vercel_state_check as v; print(v.push("t", "b", sys.argv[2] == "1", False))' "$QD" "$1" 2>/dev/null | tail -1
}

echo "== (1) no relay configured: emergency direct-posts (rate limited), warn does not"
fresh; stub; pdeliver emergency k1 "box down"
chk "python: NTFY_SERVER unset + emergency -> direct post made" test "$(direct)" = 1
chk "python: ... and the ssh alerts.log line is written too" test "$(sshs)" = 1
fresh; stub; pdeliver emergency k1 "box down"; pdeliver emergency k1 "box down"
chk "python: second identical emergency inside the 3h cooldown is NOT direct-posted again" test "$(direct)" = 1
fresh; stub; pdeliver warn k2 "note"
chk "python: NTFY_SERVER unset + warn -> never direct-posts" test "$(direct)" = 0
fresh; stub; bdeliver emergency k1 "box down"
chk "bash: NTFY_SERVER unset + emergency -> direct post made" test "$(direct)" = 1
fresh; stub; bdeliver emergency k1 "box down"; bdeliver emergency k1 "box down"
chk "bash: second identical emergency inside the cooldown is NOT direct-posted again" test "$(direct)" = 1
fresh; stub; bdeliver warn k2 "note"
chk "bash: NTFY_SERVER unset + warn -> never direct-posts" test "$(direct)" = 0

echo "== (1b) vercel push() is True only when a real push channel took it"
fresh; stub; r="$(vpush 1)"
chk "push(urgent), no relay, direct accepted -> True" test "$r" = True
fresh; stub; export STUB_DIRECT_CODE=500; r="$(vpush 1)"
chk "push(urgent), no relay, direct refused, only the ssh log line landed -> False (retried next poll)" test "$r" = False
fresh; stub; export STUB_DIRECT_CODE=500; r="$(vpush 0)"
chk "push(note), no relay, ssh digest line landed -> True (the digest is a note's channel)" test "$r" = True
fresh; stub; export NTFY_SERVER="http://relay.test:8099" STUB_RELAY_BODY="emergency:capped"; r="$(vpush 1)"
chk "relay answer 'emergency:capped' counts as delivered (relay's own policy cap)" test "$r" = True

echo "== (2) suite guard + real curl/ssh: no direct post, no ssh"
fresh; export OVN_NTFY_GUARD_LOG="$T/guard.log" PATH="$T/bin:$PATH"; pdeliver emergency k3 "box down"
chk "python under guard (curl/ssh not stubbed): nothing reached curl or ssh" bash -c "! [ -s '$STUB_LOG' ]"
fresh; export OVN_NTFY_GUARD_LOG="$T/guard.log"; bdeliver emergency k3 "box down"
chk "bash under guard (curl/ssh not stubbed): no ssh and no direct ntfy post" bash -c "[ $(sshs) = 0 ] && ! grep -q 'ntfy.sh' '$STUB_LOG'"
fresh; stub; export OVN_NTFY_GUARD_LOG="$T/guard.log"; pdeliver emergency k3 "box down"
chk "python under guard but curl/ssh STUBBED: direct path still runs (tests can observe it)" test "$(direct)" = 1
fresh; stub; export OVN_NTFY_GUARD_LOG="$T/guard.log"; bdeliver emergency k3 "box down"
chk "bash under guard but curl/ssh STUBBED: direct path still runs" test "$(direct)" = 1
echo; echo "fxp1 notify delivery: $((n-fails))/$n passed"
[ "$fails" = 0 ]
