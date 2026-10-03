#!/usr/bin/env bash
# Bash wrapper so the suite runner (bash <file>) executes test_qa_h11_gates.py in place, exactly as cron-style callers do.
# 2026-10-03 QA-gate fixes: release_candidate hold-backs, baseline FAIL echo, antigaming FPs + A_VACUOUS, reviewer kt/gd + severity floor,
# scanners (paused repos, mypy messages, seeded-positive selftest), gold set + qa_replay --gold, mark-escape script, shipped cron line.
HERE="$(cd "$(dirname "$0")" && pwd)"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qa_h11_gates.py"
rc=$?
echo "test_qa_h11_gates.py rc=$rc"
exit $rc
