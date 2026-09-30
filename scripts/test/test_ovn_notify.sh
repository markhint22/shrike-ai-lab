#!/usr/bin/env bash
# wrapper so the real scripts/ovn_notify.py runs IN PLACE (coverage is attributed to it) under the suite
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
exec python3 "$HERE/test_ovn_notify.py"
