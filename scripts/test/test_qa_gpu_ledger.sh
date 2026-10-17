#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_gpu_ledger.py (Phase 5, shadow) inside a sandbox TMPDIR made with the safe-tmp helpers (fail-closed mktemp, guarded rm).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh"
PY="$(command -v python3.12 || command -v python3)"
tmp="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$tmp"' EXIT
mkdir -p "$tmp/tmp" "$tmp/home" || exit 1
TMPDIR="$tmp/tmp" HOME="$tmp/home" "$PY" "$HERE/test_qa_gpu_ledger.py"
rc=$?
echo "test_qa_gpu_ledger.py rc=$rc"
exit $rc
