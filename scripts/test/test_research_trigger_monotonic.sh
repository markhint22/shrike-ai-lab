#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_research_trigger_monotonic.py (ovn_research_trigger_check.py: the starvation streak no longer resets on healthy-looking planner lines).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_research_trigger_monotonic.py"
rc=$?
echo "test_research_trigger_monotonic.py rc=$rc"
exit $rc
