#!/usr/bin/env bash
# test_tool_health_off_marker.sh - P6b: qa_tool_health reads `#OFF#` cron lines / '# id: x (off by default' headers as declared-off. Temp dirs from lib_safe_tmp.sh; sandbox HOME.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib_safe_tmp.sh" || exit 1
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
[ -n "$PY" ] || { echo "  SKIP: no python3"; exit 0; }
tmp="$(safe_mktemp_dir)" || exit 1
safe_set_sandbox_home "$tmp" || exit 1
export TQH_TMP="$tmp"
"$PY" "$HERE/test_tool_health_off_marker.py"
rc=$?
safe_rm_rf "$tmp" || rc=1
echo "test_tool_health_off_marker.py rc=$rc"
exit $rc
