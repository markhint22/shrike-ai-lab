#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_q_order.py (q-order 2026-11-24: fixup-undone classifier tag, GUT verify DEFERRED for a test file a later sibling step creates, placeholder strip default,
# TEST-FIRST-MISSING-SOURCE precision measure; mutation-verified) in a private, fail-closed temp sandbox (lib_safe_tmp.sh + lib_mac_test_sandbox.sh). Nothing is deleted outside it.
# The Mac has no `timeout`: a perl shim (alarm + exec) stands in for it inside the sandbox only.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$SB" || { echo "  FAIL: mac test sandbox"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
mkdir -p "$SB/tmp" "$SB/shim"
if ! command -v timeout >/dev/null 2>&1; then
  printf '#!/usr/bin/perl\nmy $s = shift @ARGV; $s =~ s/[a-z]$//; alarm($s + 0); exec @ARGV or exit 127;\n' > "$SB/shim/timeout"; chmod +x "$SB/shim/timeout"
  export PATH="$SB/shim:$PATH"
fi
TMPDIR="$SB/tmp" "$PY" "$HERE/test_q_order.py"
rc=$?
safe_rm_rf "$SB"
echo "test_q_order.py rc=$rc"
exit $rc
