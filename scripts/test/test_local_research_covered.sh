#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_local_research_covered.py (ovn_local_research.py: an evidence item is covered only by an OPEN line naming the same file + symbol).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_local_research_covered.py"
rc=$?
echo "test_local_research_covered.py rc=$rc"
exit $rc
