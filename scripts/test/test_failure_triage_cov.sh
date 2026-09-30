#!/usr/bin/env bash
# wrapper: the coverage runner invokes tests with bash; run the python test in place.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
OVN_SCRIPTS="${OVN_SCRIPTS:-$OVN_ROOT/scripts}"
export OVN_ROOT OVN_SCRIPTS
python3 "$HERE/test_failure_triage.py"
exit $?
