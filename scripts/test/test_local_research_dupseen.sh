#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_local_research_dupseen.py (ovn_local_research.py: evidence rejected as a duplicate is remembered, so research passes stop re-proposing it).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_local_research_dupseen.py"
rc=$?
echo "test_local_research_dupseen.py rc=$rc"
exit $rc
