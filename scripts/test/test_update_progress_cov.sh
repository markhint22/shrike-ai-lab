#!/usr/bin/env bash
# Runs the python update_progress tests under the coverage runner (which invokes tests with `bash`), pointing OVN_ROOT at the tree
# that contains the real script so it executes in place.
HERE="$(cd "$(dirname "$0")" && pwd)"
export OVN_ROOT="$(cd "$HERE/../.." && pwd)" PYTHONDONTWRITEBYTECODE=1
rc=0
python3 "$HERE/test_update_progress.py" || rc=1
python3 "$HERE/test_update_progress_more.py" || rc=1
exit $rc
