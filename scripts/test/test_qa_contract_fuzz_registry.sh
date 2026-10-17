#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_qa_contract_fuzz_registry.py in a private, fail-closed temp sandbox (lib_safe_tmp.sh: 2026-10-16 HOME-wipe incident). Nothing is deleted outside it.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
SB="$(safe_mktemp_dir)" || { echo "no safe temp dir - refusing to run"; exit 1; }
safe_set_sandbox_home "$SB" || exit 1
mkdir -p "$SB/tmp"
TMPDIR="$SB/tmp" "$PY" "$HERE/test_qa_contract_fuzz_registry.py"
rc=$?
safe_rm_rf "$SB"
echo "test_qa_contract_fuzz_registry.py rc=$rc"
exit $rc
