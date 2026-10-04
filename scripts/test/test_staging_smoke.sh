#!/usr/bin/env bash
# Regression tests for staging_smoke.sh (the pre-promote staging gate): health code, JSON content-type, CORS preflight.
# Hermetic: curl is a stub that answers from env vars (STUB_CODE / STUB_CT / STUB_HDRS) and logs every call; no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../staging_smoke.sh"; [ -f "$S" ] || S="$HERE/../staging_smoke.sh"; [ -f "$S" ] || S="$HERE/staging_smoke.sh"
[ -f "$S" ] || { echo "staging_smoke.sh not found"; exit 1; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"; export CURL_LOG="$T/curl.log"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# one log line per call: the full argv
echo "$*" >> "$CURL_LOG"
w=""; d=0; prev=""
for a in "$@"; do
  [ "$prev" = "-w" ] && w="$a"
  [ "$prev" = "-D" ] && d=1
  prev="$a"
done
if [ "$d" = 1 ]; then printf '%b' "${STUB_HDRS:-HTTP/1.1 200 OK\r\n\r\n}"; exit 0; fi
case "$w" in
  *http_code*) printf '%s' "${STUB_CODE:-200}";;
  *content_type*) printf '%s' "${STUB_CT-application/json}";;
esac
exit 0
STUB
chmod +x "$BIN/curl"; export PATH="$BIN:$PATH"
run(){ rm -f "$CURL_LOG"; "$S" "$@" 2>&1; }
cnt(){ [ -f "$CURL_LOG" ] && wc -l < "$CURL_LOG" | tr -d ' ' || echo 0; }
has(){ printf '%s' "$out" | grep -qF -- "$1"; }
export STUB_CODE=200 STUB_CT="application/json"; unset STUB_HDRS HEALTH_PATH

out="$(run https://api.example.app)"; rc=$?
ok "all green (no origin): exit 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "all green: health + content-type + SMOKE PASS reported" "$(has 'health 200' && has 'content-type application/json' && has 'SMOKE PASS (https://api.example.app)' && echo 1 || echo 0)"
ok "no origin -> only 3 curl calls (code, content-type, health body for migration state) and no CORS preflight" "$([ "$(cnt)" = 3 ] && ! grep -q OPTIONS "$CURL_LOG" && echo 1 || echo 0)"
ok "health URL defaults to <base>/health with --max-time 15" "$(grep -q 'https://api.example.app/health' "$CURL_LOG" && grep -q -- '--max-time 15' "$CURL_LOG" && echo 1 || echo 0)"

for c in 204 307; do
  STUB_CODE=$c out="$(run https://a.app)"; rc=$?
  ok "health $c accepted" "$([ $rc = 0 ] && has "health $c" && echo 1 || echo 0)"
done
for c in 502 404 500 000 301 201; do
  STUB_CODE=$c out="$(run https://a.app)"; rc=$?
  ok "health $c rejected (exit 1, SMOKE FAIL, do NOT promote)" "$([ $rc = 1 ] && has "health $c" && has 'SMOKE FAIL' && has 'do NOT promote' && echo 1 || echo 0)"
done
STUB_CODE=200 STUB_CT="text/html; charset=utf-8" out="$(run https://a.app)"; rc=$?
ok "HTML content-type rejected even with 200" "$([ $rc = 1 ] && has 'serving HTML' && has "'text/html; charset=utf-8'" && echo 1 || echo 0)"
STUB_CT="application/json; charset=utf-8" out="$(run https://a.app)"; rc=$?
ok "application/json; charset=... accepted (prefix match)" "$([ $rc = 0 ] && echo 1 || echo 0)"
export STUB_CT=""; out="$(run https://a.app)"; rc=$?
ok "empty content-type rejected" "$([ $rc = 1 ] && has "content-type ''" && echo 1 || echo 0)"
STUB_CODE=502 STUB_CT="text/html" out="$(run https://a.app)"; rc=$?
ok "both failures are reported, not just the first" "$([ $rc = 1 ] && has 'expected 200/307' && has 'serving HTML' && echo 1 || echo 0)"
export STUB_CODE=200 STUB_CT="application/json"

export HEALTH_PATH=/api/health; out="$(run https://a.app)"; rc=$?
ok "HEALTH_PATH override used in URL and report" "$([ $rc = 0 ] && grep -q 'https://a.app/api/health' "$CURL_LOG" && has '(https://a.app/api/health)' && echo 1 || echo 0)"
unset HEALTH_PATH

# ---- CORS ----
export STUB_HDRS='HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: https://fe.app\r\nVary: Origin\r\n\r\n'
out="$(run https://a.app https://fe.app)"; rc=$?
ok "CORS allow-origin present -> pass" "$([ $rc = 0 ] && has 'CORS allow-origin: https://fe.app' && echo 1 || echo 0)"
ok "preflight is OPTIONS with Origin + Access-Control-Request-Method: GET" "$(grep -q -- '-X OPTIONS' "$CURL_LOG" && grep -q 'Origin: https://fe.app' "$CURL_LOG" && grep -q 'Access-Control-Request-Method: GET' "$CURL_LOG" && echo 1 || echo 0)"
ok "with origin -> 4 curl calls (code, content-type, health body, CORS preflight)" "$([ "$(cnt)" = 4 ] && echo 1 || echo 0)"
export STUB_HDRS='HTTP/1.1 204 No Content\r\naccess-control-allow-origin: *\r\n\r\n'
out="$(run https://a.app https://fe.app)"; rc=$?
ok "lower-case header name + wildcard value accepted; CRLF stripped" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q 'CORS allow-origin: \*$' && echo 1 || echo 0)"
export STUB_HDRS='HTTP/1.1 200 OK\r\nVary: Origin\r\n\r\n'
out="$(run https://a.app https://fe.app)"; rc=$?
ok "CORS header missing -> fail" "$([ $rc = 1 ] && has 'no access-control-allow-origin for https://fe.app' && has 'SMOKE FAIL' && echo 1 || echo 0)"
export STUB_HDRS='HTTP/1.1 200 OK\r\nAccess-Control-Allow-Methods: GET\r\n\r\n'
out="$(run https://a.app https://fe.app)"; rc=$?
ok "other Access-Control-* headers do not count as allow-origin" "$([ $rc = 1 ] && echo 1 || echo 0)"
export STUB_CODE=502 STUB_HDRS='HTTP/1.1 204\r\nAccess-Control-Allow-Origin: *\r\n\r\n'
out="$(run https://a.app https://fe.app)"; rc=$?
ok "good CORS does not mask a bad health code" "$([ $rc = 1 ] && has 'CORS allow-origin' && has 'health 502' && echo 1 || echo 0)"
export STUB_CODE=200; unset STUB_HDRS HEALTH_PATH

# ---- usage ----
out="$("$S" 2>&1)"; rc=$?
ok "no args -> usage error, non-zero, no curl" "$([ $rc != 0 ] && printf '%s' "$out" | grep -q 'usage: staging_smoke.sh' && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
