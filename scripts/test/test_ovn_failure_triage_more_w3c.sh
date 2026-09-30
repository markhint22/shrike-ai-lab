#!/usr/bin/env bash
# wrapper so the coverage runner (which invokes `bash <file>`) executes the python test.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$HERE/test_ovn_failure_triage_more_w3c.py"
exit $?
