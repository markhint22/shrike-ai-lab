#!/usr/bin/env bash
# S2 notify fixes (vercel_state_check escalation/noise, ovn_notify OVN_ESC_HYGIENE default + drop detail + heartbeat classes + Mac supervisor staleness) with in-process mutation proofs.
HERE="$(cd "$(dirname "$0")" && pwd)"
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
[ -n "${OVN_ROOT:-}" ] || { OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/vercel_state_check.py" ] || OVN_ROOT="$(cd "$HERE/.." && pwd)"; export OVN_ROOT; }
python3 "$HERE/test_s2_notify_fixes.py"
