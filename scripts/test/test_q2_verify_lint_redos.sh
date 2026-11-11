#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_q2_verify_lint_redos.py (Q2 lint ReDoS hardening, 2026-11-10) in a private fail-closed sandbox, under the Z10 Mac test sandbox.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
mkdir -p "$SB/tmp"
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$SB" || { echo "mac sandbox init failed"; safe_rm_rf "$SB"; exit 1; }
TMPDIR="$SB/tmp" "$PY" "$HERE/test_q2_verify_lint_redos.py"
rc=$?
safe_rm_rf "$SB"
echo "test_q2_verify_lint_redos.py rc=$rc"
exit $rc
