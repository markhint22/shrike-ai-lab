#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_pingpong_guard.py (K3 item 1: literal ping-pong guard, real gitlark replay + mutants).
# Also exercises the cron wrapper ovn_pingpong_guard.sh itself (syntax, kill switch, always-exit-0) so the pipeline lint's
# "every script is referenced by a test" gate is satisfied by a real check, not a name drop.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_pingpong_guard.py"
rc=$?
echo "test_ovn_pingpong_guard.py rc=$rc"
W="$HERE/../ovn_pingpong_guard.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/pp_wrap.XXXXXX")"; mkdir -p "$T/ovn/state" "$T/ovn/scripts"
wf=0
chk(){ if [ "$2" = "1" ]; then echo "  ok   wrapper: $1"; else echo "  FAIL wrapper: $1"; wf=$((wf+1)); fi; }
bash -n "$W" 2>/dev/null; chk "ovn_pingpong_guard.sh parses" "$([ $? -eq 0 ] && echo 1 || echo 0)"
OVN_DIR="$T/ovn" OVN_STATE_DIR="$T/ovn/state" OVN_PINGPONG_GUARD=off bash "$W"; r=$?
chk "kill switch exits 0" "$([ $r -eq 0 ] && echo 1 || echo 0)"
chk "kill switch logs 'disabled'" "$(grep -q 'disabled' "$T/ovn/logs/pingpong_guard.log" 2>/dev/null && echo 1 || echo 0)"
# python failure must still exit 0 (infrastructure trouble = log line, no change)
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 3\n' > "$T/bin/python3"; chmod +x "$T/bin/python3"
cp "$HERE/../ovn_pingpong_guard.py" "$T/ovn/scripts/" 2>/dev/null; cp "$W" "$T/ovn/scripts/"
PATH="$T/bin:$PATH" OVN_PINGPONG_REPOS=" " OVN_DIR="$T/ovn" OVN_STATE_DIR="$T/ovn/state" bash "$T/ovn/scripts/ovn_pingpong_guard.sh" >/dev/null 2>&1; r=$?
chk "python failure still exits 0" "$([ $r -eq 0 ] && echo 1 || echo 0)"
rm -rf "$T"
[ "$wf" -gt 0 ] && rc=1
exit $rc
