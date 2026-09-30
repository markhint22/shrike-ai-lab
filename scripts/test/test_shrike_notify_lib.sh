#!/usr/bin/env bash
# Regression tests for shrike_notify_lib.sh (shrike_notify_publish): the shared, best-effort dual-publish helper.
# Hermetic: curl (and, for one case, python3) are stub executables first on PATH; nothing touches the network.
# Covers: unset/empty SHRIKE_NOTIFY_URL no-op, URL composition (trailing slash), headers (auth only when a token is
# set), JSON payload shape (tags split/trim/drop-empties, special chars, unicode, newlines), curl flags, curl failure
# never failing the caller, python3 failure -> silent no-op, re-sourcing, unset-var safety.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../../shrike_notify_lib.sh"; [ -f "$LIB" ] || LIB="$HERE/../shrike_notify_lib.sh"; [ -f "$LIB" ] || LIB="$HERE/shrike_notify_lib.sh"
[ -f "$LIB" ] || { echo "shrike_notify_lib.sh not found"; exit 1; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; mkdir -p "$BIN"
export CURL_LOG="$T/curl.log"; export CURL_PAYLOAD="$T/curl.payload"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
echo CALL >> "$CURL_LOG"
prev=""
for a in "$@"; do
  echo "ARG:$a" >> "$CURL_LOG"
  [ "$prev" = "-d" ] && printf '%s' "$a" > "$CURL_PAYLOAD"
  prev="$a"
done
exit "${CURL_RC:-0}"
STUB
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"
reset(){ rm -f "$CURL_LOG" "$CURL_PAYLOAD"; unset SHRIKE_NOTIFY_URL SHRIKE_NOTIFY_TOKEN CURL_RC; }
ncalls(){ [ -f "$CURL_LOG" ] && grep -c '^CALL$' "$CURL_LOG" || echo 0; }
hasarg(){ grep -qxF "ARG:$1" "$CURL_LOG" 2>/dev/null; }
pj(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$CURL_PAYLOAD" "$1" 2>/dev/null; }

# shellcheck source=/dev/null
source "$LIB"
ok "library defines shrike_notify_publish" "$(declare -F shrike_notify_publish >/dev/null && echo 1 || echo 0)"

# ---- 1. no-op when unconfigured ----
reset; shrike_notify_publish t "T" "a" "b"; rc=$?
ok "URL unset -> returns 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "URL unset -> curl never invoked" "$([ "$(ncalls)" = 0 ] && echo 1 || echo 0)"
reset; export SHRIKE_NOTIFY_URL=""; shrike_notify_publish t "T" "a" "b"; rc=$?
ok "URL empty string -> no-op, rc 0, no curl" "$([ $rc = 0 ] && [ "$(ncalls)" = 0 ] && echo 1 || echo 0)"

# ---- 2. happy path: URL, headers, flags ----
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app"
shrike_notify_publish fleet_billwatch_deploy "Deploy OK" "rocket,white_check_mark" "all green"; rc=$?
ok "configured -> exactly one curl call, rc 0" "$([ "$(ncalls)" = 1 ] && [ $rc = 0 ] && echo 1 || echo 0)"
ok "URL is <base>/<topic>" "$(hasarg 'https://sn.example.app/fleet_billwatch_deploy' && echo 1 || echo 0)"
ok "Content-Type JSON header sent" "$(hasarg 'Content-Type: application/json' && echo 1 || echo 0)"
ok "no Authorization header without a token" "$(! grep -q '^ARG:Authorization' "$CURL_LOG" && echo 1 || echo 0)"
ok "curl called with -fsS and --max-time 8" "$(hasarg -fsS && hasarg --max-time && hasarg 8 && echo 1 || echo 0)"
ok "payload title" "$([ "$(pj 'd["title"]')" = "Deploy OK" ] && echo 1 || echo 0)"
ok "payload body" "$([ "$(pj 'd["body"]')" = "all green" ] && echo 1 || echo 0)"
ok "payload tags split into a list" "$([ "$(pj 'd["tags"]')" = "['rocket', 'white_check_mark']" ] && echo 1 || echo 0)"
ok "payload priority defaults to 'default'" "$([ "$(pj 'd["priority"]')" = "default" ] && echo 1 || echo 0)"

# ---- 3. URL normalisation + auth ----
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app/"
shrike_notify_publish topic_x T "" b
ok "single trailing slash stripped (no //topic)" "$(hasarg 'https://sn.example.app/topic_x' && echo 1 || echo 0)"
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app" SHRIKE_NOTIFY_TOKEN="s3cret"
shrike_notify_publish topic_x T "" b
ok "token set -> Bearer Authorization header" "$(hasarg 'Authorization: Bearer s3cret' && echo 1 || echo 0)"
ok "token set -> Content-Type header still sent" "$(hasarg 'Content-Type: application/json' && echo 1 || echo 0)"
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app" SHRIKE_NOTIFY_TOKEN=""
shrike_notify_publish topic_x T "" b
ok "empty token -> treated as unauthenticated" "$(! grep -q '^ARG:Authorization' "$CURL_LOG" && echo 1 || echo 0)"

# ---- 4. tag parsing ----
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app"
shrike_notify_publish t T "" b
ok "empty tags -> []" "$([ "$(pj 'd["tags"]')" = "[]" ] && echo 1 || echo 0)"
shrike_notify_publish t T " a , ,b,, c " b
ok "tags trimmed, empties dropped" "$([ "$(pj 'd["tags"]')" = "['a', 'b', 'c']" ] && echo 1 || echo 0)"

# ---- 5. payload is safely JSON-encoded ----
body=$'line1\nline2 "quoted" \\back $HOME `x` \'s\' ünï ✅'
shrike_notify_publish t "Ti\"tle" "a" "$body"
ok "special chars / newlines / unicode in body round-trip" "$([ "$(pj 'd["body"]')" = "$body" ] && echo 1 || echo 0)"
ok "quote in title round-trips" "$([ "$(pj 'd["title"]')" = 'Ti"tle' ] && echo 1 || echo 0)"
shrike_notify_publish t "" "" ""
ok "empty title/body still publishes valid JSON" "$([ "$(pj 'd["title"]+d["body"]')" = "" ] && [ "$(ncalls)" = 4 ] && echo 1 || echo 0)"

# ---- 6. failures never propagate ----
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app" CURL_RC=22
shrike_notify_publish t T a b; rc=$?
ok "curl failure -> helper still returns 0" "$([ $rc = 0 ] && [ "$(ncalls)" = 1 ] && echo 1 || echo 0)"
( set -e; shrike_notify_publish t T a b; echo survived ) > "$T/e.out" 2>&1
ok "curl failure does not abort a set -e caller" "$(grep -q survived "$T/e.out" && echo 1 || echo 0)"

mkdir -p "$T/badpy"; printf '#!/bin/sh\nexit 1\n' > "$T/badpy/python3"; chmod +x "$T/badpy/python3"
reset; export SHRIKE_NOTIFY_URL="https://sn.example.app"
PATH="$T/badpy:$PATH" shrike_notify_publish t T a b; rc=$?
ok "python3 failure (empty payload) -> silent no-op, rc 0, no curl" "$([ $rc = 0 ] && [ "$(ncalls)" = 0 ] && echo 1 || echo 0)"

# ---- 7. re-sourcing / isolation ----
source "$LIB"; reset; export SHRIKE_NOTIFY_URL="https://sn.example.app"
shrike_notify_publish t T a b
ok "re-sourcing the library is harmless" "$([ "$(ncalls)" = 1 ] && echo 1 || echo 0)"
ok "helper does not leak locals (topic/title/tags/body/payload unset)" "$([ -z "${topic:-}${title:-}${tags:-}${body2:-}${payload:-}${hdr:-}" ] && echo 1 || echo 0)"
reset
( set -u; shrike_notify_publish only_three T a ) >/dev/null 2>&1; rc=$?
ok "calling with <4 args under set -u aborts the caller (documented 4-arg contract)" "$([ $rc != 0 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
