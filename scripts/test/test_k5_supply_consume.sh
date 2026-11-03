#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_k5_supply_consume.py (package K5-supply, 2026-11-03: research_requests consumers, forecast real-repo list, explorer dead-code dialect,
# K8 mutation-survivor consumer; includes the mutant runner). Hermetic: no ntfy (dead-port NTFY_SERVER, OVN_NOTIFY_DISABLE=1), TZ=UTC.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
"$PY" "$HERE/test_k5_supply_consume.py"
rc=$?
echo "test_k5_supply_consume.py rc=$rc"
exit $rc
