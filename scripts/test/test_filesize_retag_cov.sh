#!/usr/bin/env bash
# Bash wrapper so the coverage runner (bash <file>) executes the python test test_filesize_retag.py in place.
HERE="$(cd "$(dirname "$0")" && pwd)"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
python3 "$HERE/test_filesize_retag.py"
rc=$?
echo "test_filesize_retag.py rc=$rc"
exit $rc
