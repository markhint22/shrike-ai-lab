#!/usr/bin/env bash
# Reusable staging smoke test. Verifies a deployed backend is actually healthy
# BEFORE we promote develop -> main (prod). Catches the exact failure modes that
# have bitten us in prod: 502 (async driver / startup crash), HTML-instead-of-JSON,
# and missing CORS headers (invisible to /health but fatal in the browser).
#
# Usage:  staging_smoke.sh <backend_base_url> [frontend_origin]
#   e.g.  staging_smoke.sh https://billwatch-staging.up.railway.app https://billwatch-staging.vercel.app
# Exit 0 = all green (safe to promote). Non-zero = do NOT promote.
set -uo pipefail
BASE="${1:?usage: staging_smoke.sh <backend_base_url> [frontend_origin]}"
ORIGIN="${2:-}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
fail=0
say(){ printf '  %s\n' "$*"; }

# 1. health endpoint returns 2xx/307
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$BASE$HEALTH_PATH")"
if [[ "$code" =~ ^(200|204|307)$ ]]; then say "✅ health $code  ($BASE$HEALTH_PATH)"; else say "❌ health $code (expected 200/307) — likely 502 startup crash / wrong URL"; fail=1; fi

# 2. content-type is JSON, not an HTML error/SPA fallback
ct="$(curl -s -o /dev/null -w '%{content_type}' --max-time 15 "$BASE$HEALTH_PATH")"
if [[ "$ct" == application/json* ]]; then say "✅ content-type $ct"; else say "❌ content-type '$ct' (expected application/json) — API is serving HTML"; fail=1; fi

# 3. CORS preflight exposes allow-origin for the frontend (only if origin given)
if [ -n "$ORIGIN" ]; then
  acao="$(curl -s -D - -o /dev/null --max-time 15 -X OPTIONS "$BASE$HEALTH_PATH" \
      -H "Origin: $ORIGIN" -H "Access-Control-Request-Method: GET" \
      | tr -d '\r' | awk 'tolower($1)=="access-control-allow-origin:"{print $2}')"
  if [ -n "$acao" ]; then say "✅ CORS allow-origin: $acao"; else say "❌ no access-control-allow-origin for $ORIGIN — browser calls will fail"; fail=1; fi
fi

[ "$fail" -eq 0 ] && { say "SMOKE PASS ($BASE)"; exit 0; } || { say "SMOKE FAIL ($BASE) — do NOT promote"; exit 1; }
