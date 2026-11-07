#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_qa_antigaming_y5.py (package Y5, 2026-11-04). NTFY pinned to a dead port.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC "$PY" "$HERE/test_qa_antigaming_y5.py"
rc=$?
echo "test_qa_antigaming_y5.py rc=$rc"
exit $rc
