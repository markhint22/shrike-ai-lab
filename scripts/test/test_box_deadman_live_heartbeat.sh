#!/usr/bin/env bash
# Wrapper so run_all.sh runs test_box_deadman_live_heartbeat.py (P5: box_deadman live-attempt heartbeat; Mac-side script, skips loudly where it is absent).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_box_deadman_live_heartbeat.py"
rc=$?
echo "test_box_deadman_live_heartbeat.py rc=$rc"
exit $rc
