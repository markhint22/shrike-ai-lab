#!/usr/bin/env bash
# test_z10_mac_test_sandbox.sh - Z10 (2026-11-10). Regression for the test leak that put four WARN rows (live-sync-missing ... /private/var/folders/.../z6.XXXX/nolive, commit-push-branch ... /z6.XXXX/repo)
# into the REAL box alerts.log: a Mac test cleared OVN_NOTIFY_DISABLE (to prove delivery works), relied on a PATH stub ssh, and mac_live_sync.sh / mac_live_commit_push.sh put the REAL /usr/bin/ssh ahead of it.
# Proven here (no real ssh/curl is ever reachable: the sandbox guard stands behind every case; the guard log is the evidence):
#   A. mts_guard.sh: BLOCK (rc 97, recorded) for the box LAN / Tailscale addresses, ntfy.sh, any real host, for ssh/scp/rsync/curl/nc; ALLOW for loopback and reserved names.
#   B. lib_mac_test_sandbox.sh: guard stubs first on PATH, exported guard functions beat a script that resets PATH to /usr/bin first, BASH_ENV re-arms them in children, a test's own stub earlier on PATH is untouched,
#      defaults OVN_NOTIFY_DISABLE=1 + NTFY_SERVER=http://127.0.0.1:9.
#   C. mac_path_setup: production prepends the system dirs, a sandbox appends them (the test's stub ssh stays first).
#   D. mac_alert_for / mac_is_fixture_path: an alert for a path under a temp dir is NEVER delivered through the real ssh/curl (stderr 'test-fixture path: not delivered', local alerts.log row kept, no cooldown marker);
#      explicit absolute stubs (MAC_SSH + MAC_CURL) and MAC_FIXTURE_DELIVER=1 still deliver (so the refusal is not a dead switch).
#   E. mac_live_sync.sh + mac_live_commit_push.sh with the switch CLEARED, no MAC_SSH/MAC_CURL, temp-dir paths (the exact incident): zero own-stub calls, zero guard BLOCKs.
#   F. Mutants (each must make a scenario fail): fixture refusal removed, PATH prepend restored, both (the incident), guard that allows everything, sandbox that does not export the functions.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SC="$(cd "$HERE/../../.." && pwd)"
for f in mac_lib.sh mac_live_sync.sh mac_live_commit_push.sh ovn_relay.py ovn_pick_srv.py; do
  [ -f "$SC/$f" ] || { echo "  SKIP: Mac job scripts not present ($SC/$f) - queue-only tree (GPU box mirror)"; exit 0; }
done
T="$(safe_mktemp_dir z10)" || exit 1
safe_set_sandbox_home "$T" || exit 1
trap 'safe_rm_rf "$T"' EXIT
export OVN_MTS_LOG="$T/z10_guard.log"   # own log: the A scenarios BLOCK on purpose and must not pollute a parent runner log
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: sandbox init"; exit 1; }
P=0; F=0
ok() { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
nblock() { grep -c ' BLOCK ' "$OVN_MTS_LOG" 2>/dev/null || true; }
reset_log() { : > "$OVN_MTS_LOG"; }
export GIT_CONFIG_NOSYSTEM=1 TZ=UTC

echo "== A: mts_guard.sh target classification"
G="$HERE/mts_guard.sh"
g() { reset_log; OVN_MTS_LOG="$OVN_MTS_LOG" MTS_TOOL="$1" bash "$G" "${@:2}" >/dev/null 2>"$T/g.err"; echo $?; }
ok "ssh to the box LAN address: BLOCK rc 97" "$([ "$(g ssh -o BatchMode=yes mhintermeister@192.168.68.145 true)" = 97 ] && echo 0 || echo 1)"
ok "ssh to the Tailscale address: BLOCK rc 97" "$([ "$(g ssh mhintermeister@100.79.64.64 true)" = 97 ] && echo 0 || echo 1)"
ok "scp to the box: BLOCK rc 97" "$([ "$(g scp f mhintermeister@192.168.68.145:~/x)" = 97 ] && echo 0 || echo 1)"
ok "rsync to the box: BLOCK rc 97" "$([ "$(g rsync -a d mhintermeister@100.79.64.64:/x)" = 97 ] && echo 0 || echo 1)"
ok "curl to ntfy.sh: BLOCK rc 97" "$([ "$(g curl -s -d m https://ntfy.sh/topic)" = 97 ] && echo 0 || echo 1)"
ok "curl to the box relay over LAN: BLOCK rc 97" "$([ "$(g curl -s http://192.168.68.145:8099/)" = 97 ] && echo 0 || echo 1)"
ok "curl scheme-less real host: BLOCK rc 97" "$([ "$(g curl -s 100.79.64.64:8099)" = 97 ] && echo 0 || echo 1)"
ok "nc to the box: BLOCK rc 97" "$([ "$(g nc -z 192.168.68.145 22)" = 97 ] && echo 0 || echo 1)"
ok "every BLOCK is recorded and says so loudly on stderr" "$([ "$(nblock)" = 1 ] && grep -q 'BLOCKED' "$T/g.err" && echo 0 || echo 1)"
ok "ssh to a loopback / reserved name is ALLOWed (not rc 97, recorded ALLOW)" "$(r1="$(g ssh -o ConnectTimeout=1 u@box.test true)"; grep -q ' ALLOW ssh' "$OVN_MTS_LOG" && [ "$r1" != 97 ] && [ "$(nblock)" = 0 ] && echo 0 || echo 1)"
ok "curl to 127.0.0.1:9 is ALLOWed" "$(r1="$(g curl -s -m 1 http://127.0.0.1:9/x)"; [ "$r1" != 97 ] && [ "$(nblock)" = 0 ] && echo 0 || echo 1)"

echo "== B: lib_mac_test_sandbox.sh"
ok "defaults: OVN_NOTIFY_DISABLE=1 and NTFY_SERVER closed port 9" "$([ "$OVN_NOTIFY_DISABLE" = 1 ] && [ "$NTFY_SERVER" = http://127.0.0.1:9 ] && echo 0 || echo 1)"
ok "guard stubs for ssh scp rsync curl nc ntfy exist and are first on PATH" "$([ "$(type -P ssh)" = "$MTS_BIN/ssh" ] && [ -x "$MTS_BIN/curl" ] && [ -x "$MTS_BIN/nc" ] && [ -x "$MTS_BIN/ntfy" ] && echo 0 || echo 1)"
reset_log; env PATH=/usr/bin:/bin bash -c 'ssh -o BatchMode=yes mhintermeister@192.168.68.145 true' >/dev/null 2>&1; rc=$?
ok "a child bash that resets PATH to /usr/bin first still cannot reach the box (rc $rc, exported function -> guard BLOCK)" "$([ "$rc" = 97 ] && [ "$(nblock)" = 1 ] && echo 0 || echo 1)"
reset_log; ( unset -f ssh scp rsync curl nc; env PATH=/usr/bin:/bin bash -c 'ssh mhintermeister@192.168.68.145 true' >/dev/null 2>&1; echo $? > "$T/rc.txt" )
ok "BASH_ENV re-arms the guard in a child even after the test unset the functions in the parent (rc $(cat "$T/rc.txt"))" "$([ "$(cat "$T/rc.txt")" = 97 ] && [ "$(nblock)" = 1 ] && echo 0 || echo 1)"
reset_log; mkdir -p "$T/mybin"; printf '%s\n' '#!/bin/sh' 'echo stub >> "$T/mystub.log"' 'exit 0' > "$T/mybin/ssh"; chmod 755 "$T/mybin/ssh"; : > "$T/mystub.log"
PATH="$T/mybin:$PATH" T="$T" bash -c 'ssh mhintermeister@192.168.68.145 true' >/dev/null 2>&1
ok "a test's OWN stub ssh earlier on PATH wins (stub called, guard not hit)" "$([ -s "$T/mystub.log" ] && [ "$(nblock)" = 0 ] && echo 0 || echo 1)"
ok "mts_assert_no_real_calls is green on a clean log and red after a BLOCK" "$(reset_log; mts_assert_no_real_calls && { MTS_TOOL=ssh bash "$G" u@192.168.68.145 true >/dev/null 2>&1; ! mts_assert_no_real_calls 2>/dev/null; } && echo 0 || echo 1)"

echo "== C: mac_path_setup"
ok "production (no sandbox markers): system dirs are PREPENDED (unchanged behaviour)" "$(env -i HOME="$T" PATH=/x/y /bin/bash -c '. "$1"; mac_path_setup; case "$PATH" in /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/x/y) exit 0;; esac; exit 1' _ "$SC/mac_lib.sh" && echo 0 || echo 1)"
ok "sandbox (OVN_MTS_BIN set): system dirs are APPENDED, the test's own PATH order wins" "$(env -i HOME="$T" PATH=/x/y OVN_MTS_BIN=/g /bin/bash -c '. "$1"; mac_path_setup; case "$PATH" in /x/y:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin) exit 0;; esac; exit 1' _ "$SC/mac_lib.sh" && echo 0 || echo 1)"

echo "== D: mac_is_fixture_path / mac_alert_for"
isfx() { bash -c '. "$1"; mac_is_fixture_path "$2"' _ "$SC/mac_lib.sh" "$1" 2>/dev/null; }
ok "/private/var/folders/.. , /var/folders/.., /tmp/.., /private/tmp/.. are fixtures" "$(isfx /private/var/folders/8w/x/T/z6.abc/nolive && isfx /var/folders/8w/x/T/y && isfx /tmp/q/repo && isfx /private/tmp/q && echo 0 || echo 1)"
ok "the real live checkout / repo paths are not fixtures" "$(! isfx /Users/someone/LocalProjects/shared-live && ! isfx /Users/someone/LocalProjects/shared && echo 0 || echo 1)"
ok "a path whose parent is a symlink into the temp root is a fixture (physical resolution)" "$(mkdir -p "$T/real" && ln -sfn "$T/real" "$T/lnk" && isfx "$T/lnk/repo" && echo 0 || echo 1)"
mkdir -p "$T/stubbin"
printf '%s\n' '#!/bin/sh' 'echo "ssh $*" >> "$OWN"' 'exit 0' > "$T/stubbin/ssh"; printf '%s\n' '#!/bin/sh' 'echo "curl $*" >> "$OWN"' 'exit 0' > "$T/stubbin/curl"; chmod 755 "$T/stubbin/ssh" "$T/stubbin/curl"
export OWN="$T/own.log"
alert_case() { # <scripts-dir> <state> [env assignments...] : mac_alert_for on a temp fixture path, switch cleared, test stubs first on PATH, MAC_SSH/MAC_CURL unset
  local sd="$1" st="$2"; shift 2; : > "$OWN"; reset_log
  env -u MAC_SSH -u MAC_CURL OVN_MAC_STATE="$st" OVN_MAC_JOBS=shadow OVN_NOTIFY_DISABLE= NTFY_SERVER=https://relay.example.invalid:8099 MAC_ALERT_COOLDOWN_S=0 PATH="$T/stubbin:$PATH" OWN="$OWN" "$@" \
    bash -c '. "$1"; mac_alert_for "$2" warn z10-k "fixture alert"' _ "$sd/mac_lib.sh" "$T/fx/nolive" 2>"$T/alert.err" >/dev/null </dev/null
}
alert_case "$SC" "$T/sd1"
ok "fixture path + real ssh/curl: nothing delivered (own-stub calls: $(wc -l < "$OWN" | tr -d ' '), guard BLOCKs: $(nblock))" "$([ ! -s "$OWN" ] && [ "$(nblock)" = 0 ] && echo 0 || echo 1)"
ok "... stderr says 'test-fixture path: not delivered'" "$(grep -q 'test-fixture path: not delivered' "$T/alert.err" && echo 0 || echo 1)"
ok "... the alert is still recorded locally and no cooldown marker was written" "$(grep -q 'z10-k' "$T/sd1/alerts.log" && [ ! -e "$T/sd1/alert_sent/z10-k" ] && echo 0 || echo 1)"
alert_case "$SC" "$T/sd2" MAC_SSH="$T/stubbin/ssh" MAC_CURL="$T/stubbin/curl"
ok "control: explicit absolute stubs MAC_SSH + MAC_CURL still deliver to the stubs (calls: $(wc -l < "$OWN" | tr -d ' '))" "$([ -s "$OWN" ] && echo 0 || echo 1)"
alert_case "$SC" "$T/sd3" MAC_FIXTURE_DELIVER=1
ok "control: MAC_FIXTURE_DELIVER=1 (a person's deliberate check) delivers through the PATH stubs (calls: $(wc -l < "$OWN" | tr -d ' '))" "$([ -s "$OWN" ] && echo 0 || echo 1)"

echo "== E: the incident - mac_live_sync.sh + mac_live_commit_push.sh, switch CLEARED, no MAC_SSH/MAC_CURL, temp-dir paths"
R="$T/repo"; git init -q "$R" && git -C "$R" -c user.name=t -c user.email=t@t checkout -q -b claude/feature && echo x > "$R/f" && git -C "$R" add f && git -C "$R" -c user.name=t -c user.email=t@t commit -q -m seed
incident() { # <scripts-dir> <state> : both scripts exactly as the z6 control scenario ran them
  local sd="$1" st="$2"; : > "$OWN"; reset_log
  env OVN_MAC_STATE="$st" OVN_MAC_JOBS=shadow OVN_NOTIFY_DISABLE= NTFY_SERVER=https://relay.example.invalid:8099 MAC_ALERT_COOLDOWN_S=0 MAC_LIVE_DIR="$T/nolive" MAC_LIVE_SOURCE="$T/nosource" \
    PATH="$T/stubbin:/usr/bin:/bin:/opt/homebrew/bin" OWN="$OWN" OVN_MTS_LOG="$OVN_MTS_LOG" OVN_MTS_BIN="$MTS_BIN" OVN_MTS_GUARD="$OVN_MTS_GUARD" BASH_ENV="$BASH_ENV" \
    bash -c 'unset MAC_SSH MAC_CURL OVN_SSH; bash "$1/mac_live_sync.sh" </dev/null; bash "$1/mac_live_commit_push.sh" "$2" z10 f </dev/null' _ "$sd" "$R" >"$T/inc.out" 2>"$T/inc.err"
}
incident "$SC" "$T/st_e"
ok "fixed scripts: zero own-stub calls and zero guard BLOCKs (stub calls $(wc -l < "$OWN" | tr -d ' '), BLOCKs $(nblock))" "$([ ! -s "$OWN" ] && [ "$(nblock)" = 0 ] && echo 0 || echo 1)"
ok "fixed scripts: both refusals are still recorded locally (live-sync-missing + commit-push-*) and say 'not delivered'" "$(grep -q 'live-sync-missing' "$T/st_e/alerts.log" && grep -qE 'commit-push-(branch|feature)' "$T/st_e/alerts.log" && [ "$(grep -c 'test-fixture path: not delivered' "$T/inc.err")" -ge 2 ] && echo 0 || echo 1)"
ok "fixed scripts: no cooldown markers written for undelivered fixture alerts" "$([ -z "$(ls "$T/st_e/alert_sent" 2>/dev/null)" ] && echo 0 || echo 1)"

echo "== F: mutants (each must fail a scenario)"
M="$T/mut"; mkdir -p "$M"; cp "$SC/mac_lib.sh" "$SC/mac_live_sync.sh" "$SC/mac_live_commit_push.sh" "$SC/ovn_relay.py" "$SC/ovn_pick_srv.py" "$M/"
mutf() { cp "$M/$1" "$M/$1.orig"; python3 - "$M/$1" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if s.count(old) != 1: sys.exit(1)
open(p, "w").write(s.replace(old, new))
PYEOF
  local r=$?; [ "$r" = 0 ] || ok "mutant anchor unique in $1 ($2)" 1; return $r; }
unmut() { cp "$M/$1.orig" "$M/$1"; }
FIXTURE_ON='  if [ "${MAC_FIXTURE_DELIVER:-}" != 1 ] && mac_is_fixture_path "$path"'
PATH_ON='if [ -n "${OVN_MTS_BIN:-}" ] || [ -n "${OVN_NTFY_GUARD_LOG:-}" ] || [ "${OVN_PATH_APPEND:-}" = 1 ]; then export PATH="$PATH:'
if mutf mac_lib.sh "$FIXTURE_ON" '  if false && mac_is_fixture_path "$path"'; then
  incident "$M" "$T/st_m1"; [ -s "$OWN" ] || [ "$(nblock)" != 0 ]
  ok "MUTANT fixture refusal removed: the fixture alerts reach ssh/curl (own-stub calls $(wc -l < "$OWN" | tr -d ' '), BLOCKs $(nblock))" $?
  alert_case "$M" "$T/st_m1b"; [ -s "$OWN" ]; ok "MUTANT fixture refusal removed: the D scenario delivers to the stub (leak detected)" $?
  unmut mac_lib.sh
fi
if mutf mac_lib.sh "$PATH_ON" 'if false; then export PATH="$PATH:'; then
  # PATH prepend restored, fixture refusal still on: the BASH real ssh would win over the stub BUT nothing is delivered for fixture paths; combine with the refusal off = the incident
  mutf mac_lib.sh "$FIXTURE_ON" '  if false && mac_is_fixture_path "$path"' || true
  incident "$M" "$T/st_m2"; b="$(nblock)"; [ "$b" != 0 ]
  ok "MUTANT PATH prepend restored + fixture refusal removed (= the 2026-11-10 incident): the REAL ssh is reached, the guard BLOCKs it ($b blocked, rows with the temp paths: $(grep -c 'z10' "$OVN_MTS_LOG"))" $?
  unmut mac_lib.sh
fi
cp "$SC/mac_lib.sh" "$M/mac_lib.sh"; cp "$M/mac_lib.sh" "$M/mac_lib.sh.orig"
if mutf mac_lib.sh "$PATH_ON" 'if false; then export PATH="$PATH:'; then
  ok "MUTANT PATH prepend restored: mac_path_setup test C catches it" "$(env -i HOME="$T" PATH=/x/y OVN_MTS_BIN=/g /bin/bash -c '. "$1"; mac_path_setup; case "$PATH" in /x/y:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin) exit 1;; esac; exit 0' _ "$M/mac_lib.sh" && echo 0 || echo 1)"
  unmut mac_lib.sh
fi
cp "$G" "$T/guard_mut.sh"; python3 - "$T/guard_mut.sh" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read(); a = 'if [ "$bad" = 1 ]; then echo "MTS GUARD'
assert a in s; open(p, "w").write(s.replace(a, 'if false; then echo "MTS GUARD', 1).replace('/usr/bin /bin /opt/homebrew/bin /usr/local/bin; do', '/nonexistent; do'))
PYEOF
reset_log; MTS_TOOL=ssh OVN_MTS_LOG="$OVN_MTS_LOG" bash "$T/guard_mut.sh" -o BatchMode=yes u@192.168.68.145 true >/dev/null 2>&1; rc=$?
ok "MUTANT guard that allows everything: the A-scenario (BLOCK rc 97 for the box) catches it (rc $rc)" "$([ "$rc" != 97 ] && echo 0 || echo 1)"
SB2="$(safe_mktemp_dir_in "$T" nofn)" && ( cd "$SB2" && cp "$HERE/lib_mac_test_sandbox.sh" "$HERE/mts_guard.sh" . && python3 - lib_mac_test_sandbox.sh <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read(); a = 'export -f __mts_route ssh scp rsync curl nc'
assert a in s; open(p, "w").write(s.replace(a, ':'))
PYEOF
)
# never invokes ssh: asks the grand-child shell what `ssh` IS (function => the guard travels with the environment)
fn_type() { env -i HOME="$T" PATH=/usr/bin:/bin OVN_MTS_LOG="$OVN_MTS_LOG" /bin/bash -c '. "$1"; mts_sandbox_init "$2" >/dev/null; env -u BASH_ENV PATH=/usr/bin:/bin /bin/bash -c "type -t ssh"' _ "$1" "$2" 2>/dev/null </dev/null; }
mkdir -p "$T/ft1" "$T/ft2"
ok "sandbox lib: a grandchild bash sees ssh as an exported FUNCTION (guard travels with the env)" "$([ "$(fn_type "$HERE/lib_mac_test_sandbox.sh" "$T/ft1")" = function ] && echo 0 || echo 1)"
ok "MUTANT sandbox that does not export the guard functions: the function scenario catches it (type: '$(fn_type "$SB2/lib_mac_test_sandbox.sh" "$T/ft2")')" "$([ "$(fn_type "$SB2/lib_mac_test_sandbox.sh" "$T/ft2")" != function ] && echo 0 || echo 1)"
echo
echo "z10_mac_test_sandbox: $P passed, $F failed"
[ "$F" = 0 ]
