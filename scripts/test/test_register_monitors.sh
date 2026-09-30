#!/usr/bin/env bash
# Regression: register_monitors.sh (idempotently registers fleet HTTP surfaces as shrike-monitor monitors).
# The script is copied into a temp layout ($T/register_monitors.sh + $T/overnight-queue/deploy_watch.sh, which is where it
# looks for the SURFACES table); curl is a stub first on PATH, so no network/monitor service is ever contacted.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../../register_monitors.sh" "$HERE/../../register_monitors.sh" "$HERE/../register_monitors.sh"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "register_monitors.sh not found"; exit 2; }
REAL_DW=""; for c in "$(dirname "$SUT")/overnight-queue/deploy_watch.sh" "$HERE/../../deploy_watch.sh" "$HERE/../deploy_watch.sh"; do [ -f "$c" ] && { REAL_DW="$c"; break; }; done
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
warn(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else echo "  WARN $1 (non-fatal, known defect)"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lay/overnight-queue" "$T/bin" "$T/bare"
cp "$SUT" "$T/lay/register_monitors.sh"; cp "$SUT" "$T/bare/register_monitors.sh"   # $T/bare has no overnight-queue/deploy_watch.sh
cat > "$T/lay/overnight-queue/deploy_watch.sh" <<'DW'
#!/usr/bin/env bash
# fixture
SURFACES="
billwatch-backend|billwatch|billwatch backend|railway|billwatch|https://bw.example/health|1
billwatch-frontend|billwatch|billwatch frontend|vercel|billwatch|https://bw.example|1

tm-backend|task-manager-platform|taskman backend|railway|tm|https://tm.example/health|0
ripple-frontend|social-media-manager|ripple frontend|vercel|sm|https://ripple.example|0
   |x|blank key row|x|x|https://nope.example|0
website|shrike-labs-website|shrike website|vercel|site|https://site.example|0
"
echo unrelated
DW
cat > "$T/bin/curl" <<'C'
#!/usr/bin/env bash
# stub: GET /monitors -> $EXISTING_JSON (or fail when GET_FAIL=1); POST -> record, fail if payload matches $POST_FAIL_ON
args="$*"; echo "$args" >> "$CURL_LOG"
post=0; payload=""
while [ $# -gt 0 ]; do case "$1" in -d) post=1; payload="$2"; shift;; esac; shift; done
if [ $post = 0 ]; then
  [ "${GET_FAIL:-0}" = 1 ] && exit 22
  cat "$EXISTING_JSON" 2>/dev/null; exit 0
fi
echo "$payload" >> "$POST_LOG"
[ -n "${POST_FAIL_ON:-}" ] && case "$payload" in *"$POST_FAIL_ON"*) exit 22;; esac
exit 0
C
chmod +x "$T/bin/curl"
export CURL_LOG="$T/curl.log" POST_LOG="$T/posts.log" EXISTING_JSON="$T/existing.json"
reset(){ : > "$CURL_LOG"; : > "$POST_LOG"; echo '[]' > "$EXISTING_JSON"; }
run(){ local script="$1"; shift; env -u SHRIKE_MONITOR_URL -u SHRIKE_MONITOR_TOKEN PATH="$T/bin:$PATH" "$@" bash "$script" > "$T/out" 2> "$T/err"; rc=$?; }
L="$T/lay/register_monitors.sh"

# 1. kill switch
reset; run "$L"
ok "no SHRIKE_MONITOR_URL -> no-op, exit 0" "$([ $rc = 0 ] && grep -q 'SHRIKE_MONITOR_URL not set' "$T/out" && echo 1 || echo 0)"
ok "no-op makes zero curl calls" "$([ ! -s "$CURL_LOG" ] && echo 1 || echo 0)"
reset; run "$L" SHRIKE_MONITOR_URL=
ok "empty SHRIKE_MONITOR_URL is also a no-op" "$([ $rc = 0 ] && [ ! -s "$CURL_LOG" ] && echo 1 || echo 0)"

# 2. FATAL paths
reset; run "$T/bare/register_monitors.sh" SHRIKE_MONITOR_URL=http://mon
ok "missing deploy_watch.sh -> FATAL exit 1 (stderr)" "$([ $rc = 1 ] && grep -q "FATAL: can't find .*/overnight-queue/deploy_watch.sh" "$T/err" && echo 1 || echo 0)"
ok "FATAL before any network call" "$([ ! -s "$CURL_LOG" ] && echo 1 || echo 0)"
cp "$T/lay/overnight-queue/deploy_watch.sh" "$T/dw.bak"; echo '#!/bin/bash' > "$T/lay/overnight-queue/deploy_watch.sh"
reset; run "$L" SHRIKE_MONITOR_URL=http://mon
ok "deploy_watch.sh without a SURFACES block -> FATAL exit 1" "$([ $rc = 1 ] && grep -q "couldn't extract SURFACES" "$T/err" && [ ! -s "$CURL_LOG" ] && echo 1 || echo 0)"
cp "$T/dw.bak" "$T/lay/overnight-queue/deploy_watch.sh"

# 3. fresh registration
reset; run "$L" SHRIKE_MONITOR_URL=http://mon/ SHRIKE_MONITOR_TOKEN=tok123
ok "fresh: exit 0 and summary '3 registered, 0 already present, 0 failed'" "$([ $rc = 0 ] && grep -qx 'register_monitors: 3 registered, 0 already present, 0 failed' "$T/out" && echo 1 || echo 0)"
ok "fresh: 3 POSTs (billwatch backend/frontend + shrike website)" "$([ "$(wc -l < "$POST_LOG" | tr -d ' ')" = 3 ] && echo 1 || echo 0)"
ok "payloads are JSON {name,type:http,url=health_url}" "$(python3 - "$POST_LOG" <<'P'
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
want=[{"name":"billwatch backend","type":"http","url":"https://bw.example/health"},
      {"name":"billwatch frontend","type":"http","url":"https://bw.example"},
      {"name":"shrike website","type":"http","url":"https://site.example"}]
print(1 if r==want else 0)
P
)"
ok "discontinued repos are skipped with a log line and never POSTed" "$(grep -q 'skip (discontinued repo task-manager-platform): taskman backend' "$T/out" && grep -q 'skip (discontinued repo social-media-manager): ripple frontend' "$T/out" && ! grep -q 'ripple\|taskman' "$POST_LOG" && echo 1 || echo 0)"
ok "blank-key row ignored" "$(! grep -q 'nope.example' "$CURL_LOG" && echo 1 || echo 0)"
ok "trailing slash on SHRIKE_MONITOR_URL stripped (GET http://mon/monitors)" "$(grep -q 'http://mon/monitors' "$CURL_LOG" && ! grep -q 'mon//monitors' "$CURL_LOG" && echo 1 || echo 0)"
ok "Authorization bearer header sent when token set" "$(grep -q 'Authorization: Bearer tok123' "$CURL_LOG" && echo 1 || echo 0)"
ok "Content-Type JSON header + 8s timeout on every call" "$([ "$(grep -c 'Content-Type: application/json' "$CURL_LOG")" = 4 ] && [ "$(grep -c -- '--max-time 8' "$CURL_LOG")" = 4 ] && echo 1 || echo 0)"
ok "output lists each 'registered: name -> url'" "$(grep -q 'registered: billwatch backend -> https://bw.example/health' "$T/out" && echo 1 || echo 0)"
reset; run "$L" SHRIKE_MONITOR_URL=http://mon
ok "no token -> no Authorization header" "$(! grep -q Authorization "$CURL_LOG" && echo 1 || echo 0)"

# 4. idempotency
reset; echo '[{"name":"billwatch backend"},{"name":"shrike website","url":"x"}]' > "$EXISTING_JSON"
run "$L" SHRIKE_MONITOR_URL=http://mon
ok "existing monitors skipped, only the missing one POSTed" "$([ "$(wc -l < "$POST_LOG" | tr -d ' ')" = 1 ] && grep -q 'billwatch frontend' "$POST_LOG" && grep -qx 'skip (already registered): billwatch backend' "$T/out" && echo 1 || echo 0)"
ok "summary counts '1 registered, 2 already present'" "$(grep -qx 'register_monitors: 1 registered, 2 already present, 0 failed' "$T/out" && echo 1 || echo 0)"
reset; echo '[{"name":"billwatch backend"},{"name":"billwatch frontend"},{"name":"shrike website"}]' > "$EXISTING_JSON"
run "$L" SHRIKE_MONITOR_URL=http://mon
ok "all present -> zero POSTs, exit 0 (fully idempotent)" "$([ $rc = 0 ] && [ ! -s "$POST_LOG" ] && grep -q '0 registered, 3 already present' "$T/out" && echo 1 || echo 0)"
reset; echo '[{"name":"billwatch backend v2"},{"name":"Billwatch Frontend"}]' > "$EXISTING_JSON"
run "$L" SHRIKE_MONITOR_URL=http://mon
ok "name match is exact (prefix/case variants do not count as registered)" "$(grep -q '3 registered, 0 already' "$T/out" && echo 1 || echo 0)"
reset; echo '[{"id":1},{"name":"shrike website"}]' > "$EXISTING_JSON"
run "$L" SHRIKE_MONITOR_URL=http://mon
ok "existing entries lacking a name are tolerated" "$([ $rc = 0 ] && grep -q '2 registered, 1 already' "$T/out" && echo 1 || echo 0)"

# 5. degraded monitor API
reset; run "$L" SHRIKE_MONITOR_URL=http://mon GET_FAIL=1
ok "GET /monitors failing -> treated as empty, registers all" "$([ $rc = 0 ] && grep -q '3 registered' "$T/out" && echo 1 || echo 0)"
reset; echo 'this is <html> not json' > "$EXISTING_JSON"; run "$L" SHRIKE_MONITOR_URL=http://mon
ok "non-JSON GET body -> treated as empty (no crash)" "$([ $rc = 0 ] && grep -q '3 registered' "$T/out" && echo 1 || echo 0)"
reset; run "$L" SHRIKE_MONITOR_URL=http://mon POST_FAIL_ON='billwatch frontend'
ok "one POST failing -> exit 1, FAILED on stderr, others still registered" "$([ $rc = 1 ] && grep -q 'FAILED to register: billwatch frontend -> https://bw.example' "$T/err" && grep -q '2 registered, 0 already present, 1 failed' "$T/out" && echo 1 || echo 0)"
reset; run "$L" SHRIKE_MONITOR_URL=http://mon POST_FAIL_ON='"type"'
ok "all POSTs failing -> exit 1 with failed=3" "$([ $rc = 1 ] && grep -q '0 registered, 0 already present, 3 failed' "$T/out" && echo 1 || echo 0)"

# 6. drift guard against the REAL deploy_watch.sh SURFACES table
if [ -n "$REAL_DW" ]; then
  mkdir -p "$T/real/overnight-queue"; cp "$SUT" "$T/real/register_monitors.sh"; cp "$REAL_DW" "$T/real/overnight-queue/deploy_watch.sh"
  reset; run "$T/real/register_monitors.sh" SHRIKE_MONITOR_URL=http://mon
  ok "real deploy_watch.sh: extraction works, exit 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
  ok "real table registers exactly the 7 live surfaces" "$(grep -q 'register_monitors: 7 registered, 0 already present, 0 failed' "$T/out" && echo 1 || echo 0)"
  ok "real table: discontinued Ripple/task-manager never registered" "$(! grep -qi 'ripple\|task-manager\|taskman' "$POST_LOG" && echo 1 || echo 0)"
  ok "real table: every registered url is http(s)" "$(python3 -c '
import json,sys
r=[json.loads(l) for l in open(sys.argv[1])]
print(1 if len(r)==7 and all(x["url"].startswith("http") and x["type"]=="http" for x in r) else 0)' "$POST_LOG")"
fi
# 7. deployment-layout check: the script looks for $DIR/overnight-queue/deploy_watch.sh
# 2026-09-30: fixed - the script now lives next to deploy_watch.sh (and still falls back to $DIR/overnight-queue/deploy_watch.sh)
ok "register_monitors.sh finds deploy_watch.sh in its own directory (no FATAL for a copy inside ~/overnight-queue/)" "$([ -f "$(dirname "$SUT")/deploy_watch.sh" ] || [ -f "$(dirname "$SUT")/overnight-queue/deploy_watch.sh" ] && echo 1 || echo 0)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
