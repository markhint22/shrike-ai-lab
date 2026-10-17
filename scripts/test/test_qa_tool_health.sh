#!/usr/bin/env bash
# test_qa_tool_health.sh - P1 gate tool health sentinel + qa_tools_install.sh. Every temp dir comes from lib_safe_tmp.sh (fail closed) and is removed with
# safe_rm_rf; HOME is a sandbox HOME; nothing touches the real home, state dir, crontab or network (stub pip, fixture gitleaks tarball).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib_safe_tmp.sh" || exit 1
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
[ -n "$PY" ] || { echo "  SKIP: no python3"; exit 0; }
tmp="$(safe_mktemp_dir)" || exit 1
safe_set_sandbox_home "$tmp" || exit 1
export TQH_TMP="$tmp"
"$PY" "$HERE/test_qa_tool_health.py"
rc=$?
safe_rm_rf "$tmp" || rc=1
echo "test_qa_tool_health.py rc=$rc"
exit $rc
