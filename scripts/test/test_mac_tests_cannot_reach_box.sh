#!/usr/bin/env bash
# test_mac_tests_cannot_reach_box.sh - Z10 (2026-11-10). Runs EVERY Mac-side test (test_mac_*.sh, the z4 / z6 / z8a Mac tests, test_k1_mac_reach, test_p1_notify_delivery, test_fxp1_*, test_y6_notify_fixes,
# test_deploy_watch*, test_promote_alerting) under a PATH + exported-function + BASH_ENV guard (lib_mac_test_sandbox.sh) that records every ssh/scp/rsync/curl/nc call and BLOCKs (rc 97, never executes) any
# non-loopback / non-reserved target (the box LAN + Tailscale addresses, ntfy.sh, any real host), and asserts: every test still passes AND the guard recorded ZERO BLOCK calls. A test that reaches the real box
# (the 2026-11-10 z6 leak: four WARN rows in the real alerts.log) turns this red with the offending argv in the output. It takes minutes (each test has a 900 s timeout).
# Limits (documented, deliberate): a call by ABSOLUTE path (/usr/bin/ssh) cannot be intercepted by PATH or functions; lint_no_abs_ssh below fails the suite if a Mac test or job script does that.
# Mutants: a test that clears OVN_NOTIFY_DISABLE and runs ssh to the box with no stub is caught; a harmless loopback test is not; an absolute-path ssh in a test is caught by the lint.
# Darwin only (the Mac job scripts are not on the box): skips elsewhere.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SC="$(cd "$HERE/../../.." && pwd)"
[ -f "$SC/mac_lib.sh" ] || { echo "  SKIP: Mac job scripts not present - queue-only tree (GPU box mirror)"; exit 0; }
[ "$(uname)" = Darwin ] || { echo "  SKIP: Mac tests run on macOS only"; exit 0; }
T="$(safe_mktemp_dir z10run)" || exit 1
safe_set_sandbox_home "$T" || exit 1
trap 'safe_rm_rf "$T"' EXIT
export OVN_MTS_LOG="$T/guard.log"
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: sandbox init"; exit 1; }
P=0; F=0
ok() { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
SELF="$(basename "$0")"
mac_test_list() { # <dir>
  local d="$1" f
  for f in "$d"/test_mac_*.sh "$d"/test_z4_*.sh "$d"/test_z6_notify_guard.sh "$d"/test_z8a_*.sh "$d"/test_k1_mac_reach.sh "$d"/test_p1_notify_delivery.sh "$d"/test_fxp1_*.sh \
           "$d"/test_y6_notify_fixes.sh "$d"/test_deploy_watch*.sh "$d"/test_promote_alerting.sh; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in "$SELF"|test_mac_tests_cannot_reach_box.sh|test_z10_*) continue;; esac
    basename "$f"
  done | sort -u
}
# run_guarded <dir> <test>: echoes "<rc> <blocks>"; the guard log is reset per test; output kept in $T/out.<test>
run_guarded() {
  local d="$1" t="$2"
  : > "$OVN_MTS_LOG"
  ( cd "$d" && perl -e 'alarm shift; exec @ARGV' "${MTS_TEST_TIMEOUT:-900}" bash "$t" > "$T/out.$t" 2>&1 </dev/null ); local rc=$?
  echo "$rc $(grep -c ' BLOCK ' "$OVN_MTS_LOG" 2>/dev/null || true)"
}

LIST="$(mac_test_list "$HERE")"
n="$(printf '%s\n' "$LIST" | grep -c .)"
ok "the Mac test list is non-empty and covers the known Mac tests ($n tests)" "$([ "$n" -ge 15 ] && printf '%s\n' "$LIST" | grep -qx test_mac_live_sync.sh && printf '%s\n' "$LIST" | grep -qx test_z6_notify_guard.sh && printf '%s\n' "$LIST" | grep -qx test_p1_notify_delivery.sh && printf '%s\n' "$LIST" | grep -qx test_z8a_bridge_commit_feature.sh && echo 0 || echo 1)"
echo "== A: every Mac test under the guard: passes, zero BLOCKed calls"
for t in $LIST; do
  read -r rc bl <<< "$(run_guarded "$HERE" "$t")"
  ok "$t: rc=$rc, guard BLOCKs=$bl$([ "$bl" != 0 ] && printf ' :: %s' "$(grep ' BLOCK ' "$OVN_MTS_LOG" | head -2 | cut -c1-200 | tr '\n' '|')")" "$([ "$rc" = 0 ] && [ "$bl" = 0 ] && echo 0 || echo 1)"
  [ "$rc" != 0 ] && tail -3 "$T/out.$t" | sed 's/^/        /'
  grep -q 'SKIP' "$T/out.$t" 2>/dev/null && [ "$rc" = 0 ] && grep -q 'passed\|PASS\|ok' "$T/out.$t" 2>/dev/null || true
done

echo "== B: lint - no Mac test / Mac job script calls ssh/scp/rsync by ABSOLUTE path (the one thing the guard cannot see)"
abs="$(cd "$SC" && grep -nE '(^|[ ;(`|&])/(usr/)?(local/)?(bin|sbin)/(ssh|scp|rsync)([ ;)`|&]|$)|/opt/homebrew/bin/(ssh|scp|rsync)([ ;)`|&]|$)' mac_*.sh mac-*.sh overnight-queue/deploy_watch.sh overnight-queue/overnight_digest.sh 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | head -5)"
tabs="$(cd "$HERE" && for t in $LIST; do grep -nE '^[^#]*[ ;(`|&=]/(usr/)?(local/)?bin/(ssh|scp|rsync) ' "$t" 2>/dev/null | grep -v 'ntfy_guard\|case\|/usr/bin/ssh|' | sed "s|^|$t:|"; done | head -5)"
ok "no absolute-path ssh/scp/rsync in the Mac job scripts ($(printf '%s' "$abs" | head -c 120))" "$([ -z "$abs" ] && echo 0 || echo 1)"
ok "no absolute-path ssh/scp/rsync call in a Mac test ($(printf '%s' "$tabs" | head -c 120))" "$([ -z "$tabs" ] && echo 0 || echo 1)"

echo "== C: mutants - the harness itself catches a leaking test"
MD="$T/mutd"; mkdir -p "$MD"
cat > "$MD/test_leak_clear_switch.sh" <<'LEOF'
#!/usr/bin/env bash
# a test that clears the disable switch "to test delivery" with NO stub and reaches the box (the z6 pattern)
unset OVN_NOTIFY_DISABLE MAC_SSH MAC_CURL
export PATH="/usr/bin:/bin:/opt/homebrew/bin"
ssh -o BatchMode=yes -o ConnectTimeout=3 mhintermeister@192.168.68.145 'echo leak' >/dev/null 2>&1
curl -s -m 3 -d leak https://ntfy.sh/ovn_test_leak >/dev/null 2>&1
echo "leaky: done"; exit 0
LEOF
cat > "$MD/test_leak_script_prepends_path.sh" <<'LEOF'
#!/usr/bin/env bash
# the exact incident shape: a stub ssh first on PATH, then a child script that PREPENDS the system dirs and calls plain ssh to the box
mkdir -p "$LEAKD/leakstub"; printf '#!/bin/sh\nexit 0\n' > "$LEAKD/leakstub/ssh"; chmod 755 "$LEAKD/leakstub/ssh"
PATH="$LEAKD/leakstub:$PATH" bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; ssh -o BatchMode=yes mhintermeister@192.168.68.145 true' >/dev/null 2>&1
exit 0
LEOF
cat > "$MD/test_ok_loopback.sh" <<'LEOF'
#!/usr/bin/env bash
curl -s -m 1 http://127.0.0.1:9/x >/dev/null 2>&1; ssh -o ConnectTimeout=1 u@box.test true >/dev/null 2>&1
echo "ok: done"; exit 0
LEOF
export LEAKD="$T"
read -r rc bl <<< "$(MTS_TEST_TIMEOUT=60 run_guarded "$MD" test_leak_clear_switch.sh)"
ok "MUTANT test clearing the switch with no stub (ssh + ntfy.sh): the harness records BLOCKs (got $bl, expect 2)" "$([ "$bl" = 2 ] && echo 0 || echo 1)"
read -r rc bl <<< "$(MTS_TEST_TIMEOUT=60 run_guarded "$MD" test_leak_script_prepends_path.sh)"
ok "MUTANT stub-on-PATH + a script that prepends /usr/bin (the z6 incident shape): the harness records the BLOCK (got $bl)" "$([ "$bl" = 1 ] && echo 0 || echo 1)"
read -r rc bl <<< "$(MTS_TEST_TIMEOUT=60 run_guarded "$MD" test_ok_loopback.sh)"
ok "control: a loopback / reserved-name test records zero BLOCKs (got $bl) and passes (rc $rc)" "$([ "$bl" = 0 ] && [ "$rc" = 0 ] && echo 0 || echo 1)"
ok "lint regex catches an absolute-path ssh call (mutant file)" "$(grep -qE '^[^#]*[ ;(`|&=]/(usr/)?(local/)?bin/(ssh|scp|rsync) ' <(printf 'x=$(/usr/bin/ssh -V 2>&1)\n') && echo 0 || echo 1)"
echo
echo "mac_tests_cannot_reach_box: $P passed, $F failed"
[ "$F" = 0 ]
