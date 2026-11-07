#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_z1_r2.py (Z1 review round 2 regression battery) in a private, fail-closed temp sandbox (lib_safe_tmp.sh). Nothing is deleted outside it.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
mkdir -p "$SB/tmp"
TMPDIR="$SB/tmp" "$PY" "$HERE/test_z1_r2.py"
rc=$?
safe_rm_rf "$SB"
echo "test_z1_r2.py rc=$rc"
exit $rc
