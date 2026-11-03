#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_research_trigger_monotonic.py (ovn_research_trigger_check.py: the starvation streak no longer resets on healthy-looking planner lines).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_test_tz.sh"   # 2026-11-01 (K4): time-relative suite, pinned to UTC (DST fall-back made "N hours ago" ambiguous)
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:9}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_research_trigger_monotonic.py"
rc=$?
echo "test_research_trigger_monotonic.py rc=$rc"
exit $rc
