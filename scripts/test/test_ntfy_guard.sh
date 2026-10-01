#!/usr/bin/env bash
# ntfy_guard.sh: the suite must never reach the real ntfy.sh (2026-09-30 quota-exhaustion incident), yet stub curls must still work.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export OVN_NTFY_GUARD_LOG="$T/guard.log"
. "$HERE/ntfy_guard.sh"
curl -s -m 2 -d hi https://ntfy.sh/some_topic; rc=$?
ok "a direct ntfy.sh call is swallowed and succeeds" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "the swallowed attempt is logged with its arguments" "$(grep -q 'ntfy.sh/some_topic' "$T/guard.log" && echo 1 || echo 0)"
out="$(bash -c 'PATH=/usr/local/bin:/usr/bin:/bin; curl -s -m 2 -d x https://ntfy.sh/child_topic; echo rc=$?')"
ok "a child bash that resets PATH to /usr/bin first is still guarded" "$(printf '%s' "$out" | grep -q 'rc=0' && grep -q child_topic "$T/guard.log" && echo 1 || echo 0)"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "STUB $*" >> "%s/stub.log"\n' "$T" > "$T/bin/curl"; chmod +x "$T/bin/curl"
PATH="$T/bin:$PATH" curl -s https://ntfy.sh/stubbed_topic
ok "a stub curl first on PATH still receives ntfy.sh calls (tests can assert on them)" "$(grep -q 'ntfy.sh/stubbed_topic' "$T/stub.log" 2>/dev/null && ! grep -q stubbed_topic "$T/guard.log" && echo 1 || echo 0)"
( cd "$T" && python3 -m http.server 0 >/dev/null 2>&1 & echo $! > "$T/srv.pid" ); sleep 0
echo hello > "$T/local.txt"
ok "non-ntfy URLs are forwarded to the real curl (file:// works)" "$([ "$(curl -s "file://$T/local.txt")" = "hello" ] && echo 1 || echo 0)"
kill "$(cat "$T/srv.pid" 2>/dev/null)" 2>/dev/null
ok "run_all.sh sources the guard" "$(grep -q 'ntfy_guard.sh' "$HERE/run_all.sh" && echo 1 || echo 0)"
ok "run_coverage.sh sources the guard" "$(grep -q 'ntfy_guard.sh' "$HERE/../cov/run_coverage.sh" 2>/dev/null && echo 1 || echo 0)"
# ---- regression (2026-10-01): run_all.sh's header must load the guard when started with a RELATIVE path from the repo root, as cron does
_q="$(cd "$HERE/../.." && pwd)"; _probe="$HERE/.ra_probe.sh"
n=$(grep -n '^rc=0' "$HERE/run_all.sh" | head -1 | cut -d: -f1)
{ head -n "$((n-1))" "$HERE/run_all.sh"; echo 'echo "PROBE NTFY_SERVER=[${NTFY_SERVER:-unset}] curl=$(type -t curl)"'; } > "$_probe"
_out="$(cd "$_q" && NTFY_SERVER=http://127.0.0.1:8099 bash scripts/test/.ra_probe.sh 2>&1)"; rm -f "$_probe"
ok "run_all.sh header loads the guard under a relative (cron-style) invocation, unsets NTFY_SERVER, and shadows curl" "$([ "$_out" = "PROBE NTFY_SERVER=[unset] curl=function" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]

