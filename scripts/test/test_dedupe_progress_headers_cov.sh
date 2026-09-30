#!/usr/bin/env bash
# Bash wrapper so the coverage runner (bash <file>) executes the python test test_dedupe_progress_headers.py in place.
HERE="$(cd "$(dirname "$0")" && pwd)"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
python3 "$HERE/test_dedupe_progress_headers.py"
rc=$?
echo "test_dedupe_progress_headers.py rc=$rc"
exit $rc
