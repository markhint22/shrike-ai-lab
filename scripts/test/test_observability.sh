#!/usr/bin/env bash
# wrapper: run the python observability tests in place (scratch-copy safe).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
OVN_SCRIPTS="${OVN_SCRIPTS:-$OVN_ROOT/scripts}"
export OVN_ROOT OVN_SCRIPTS
python3 "$HERE/test_observability.py"
exit $?
