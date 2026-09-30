#!/usr/bin/env bash
# wrapper so the coverage runner (bash <file>) executes the python test in place.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/test_small_py_more_w3cb.py"
exit $?
