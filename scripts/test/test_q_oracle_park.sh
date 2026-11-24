#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_q_oracle_park.py (q-oracle-park 2026-11-24: GUT verify-oracle rewrite GU1 (enforce), scout import grounding (shadow), TEST-FIRST-MISSING-SOURCE guard (shadow),
# build-break park stays shadow; mutation-verified) in a private, fail-closed temp sandbox (lib_safe_tmp.sh + lib_mac_test_sandbox.sh). Nothing is deleted outside it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$SB" || { echo "  FAIL: mac test sandbox"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
mkdir -p "$SB/tmp"
TMPDIR="$SB/tmp" "$PY" "$HERE/test_q_oracle_park.py"
rc=$?
safe_rm_rf "$SB"
echo "test_q_oracle_park.py rc=$rc"
exit $rc
