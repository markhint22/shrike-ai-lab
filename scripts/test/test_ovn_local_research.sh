#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_local_research.py (the Claude-free roadmap refuel: scripts/ovn_local_research.py).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_local_research.py"
rc=$?
echo "test_ovn_local_research.py rc=$rc"
exit $rc
