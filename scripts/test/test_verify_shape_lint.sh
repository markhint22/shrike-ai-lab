#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_verify_shape_lint.py (D1 VERIFY shape linter, 2026-10-18) in a private, fail-closed temp sandbox (lib_safe_tmp.sh). Nothing is deleted outside it.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
mkdir -p "$SB/tmp"
TMPDIR="$SB/tmp" "$PY" "$HERE/test_verify_shape_lint.py"
rc=$?
safe_rm_rf "$SB"
echo "test_verify_shape_lint.py rc=$rc"
exit $rc
