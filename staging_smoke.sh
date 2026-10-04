#!/usr/bin/env bash
# Reusable staging smoke test. Verifies a deployed backend is actually healthy
# BEFORE we promote develop -> main (prod). Catches the exact failure modes that
# have bitten us in prod: 502 (async driver / startup crash), HTML-instead-of-JSON,
# and missing CORS headers (invisible to /health but fatal in the browser).
#
# Usage:  staging_smoke.sh <backend_base_url> [frontend_origin]
#   e.g.  staging_smoke.sh https://billwatch-staging.up.railway.app https://billwatch-staging.vercel.app
# 2026-10-03 PROVENANCE: with STAGING_EXPECT_SHA=<candidate sha> (promote_to_prod.sh passes it) the smoke also checks WHICH build answered: when /health
# exposes a commit field (commit|commit_sha|git_sha|git_commit|sha|release) it must be the candidate, or (with STAGING_REPO_DIR=<clone>) a descendant of
# it; a different commit = healthy-but-STALE deploy = FAIL (the 09:00 smoke of 2026-10-03 passed on an old deploy while the new one FAILED). A /health
# without a commit field cannot prove it: that is said out loud, and the deploy-status half lives in qa/promote_gate.py (Railway deploy list).
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

# 2b0. migration state (2026-10-04): /health reports {"migrations": "current|mismatch|unknown"} (iptv_apps). "mismatch" = the DATABASE is not at the code's alembic head
# (the deploy booted although `alembic upgrade head` failed - start.sh swallows that). Never promote that. Absent/"unknown"/"current" never fails.
body="$(curl -s --max-time 15 "$BASE$HEALTH_PATH" 2>/dev/null)"
if printf '%s' "$body" | grep -qE '"migrations"[[:space:]]*:[[:space:]]*"mismatch"'; then
  say "❌ migrations: the database is NOT at the code's alembic head ($(printf '%s' "$body" | grep -oE '"db_revision"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1) vs $(printf '%s' "$body" | grep -oE '"alembic_head"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)) - a migration failed or never ran"; fail=1
elif printf '%s' "$body" | grep -qE '"migrations"[[:space:]]*:[[:space:]]*"current"'; then say "✅ migrations: database is at the alembic head"
fi

# 2b. provenance (only when the caller knows the candidate)
if [ -n "${STAGING_EXPECT_SHA:-}" ]; then
  served="$(printf '%s' "$body" | grep -oiE '"(commit|commit_sha|git_sha|git_commit|sha|release)"[[:space:]]*:[[:space:]]*"[0-9a-f]{7,40}"' | head -1 | sed -E 's/.*"([0-9a-fA-F]+)"$/\1/' | tr 'A-F' 'a-f')"
  exp="$(printf '%s' "$STAGING_EXPECT_SHA" | tr 'A-F' 'a-f')"
  if [ -z "$served" ]; then say "⚠️ provenance UNVERIFIED: /health exposes no commit field (staging deploy status is checked by the promote staging-gate)"
  elif [[ "$served" == "$exp"* || "$exp" == "$served"* ]]; then say "✅ provenance: staging serves the candidate ${served:0:10}"
  elif [ -n "${STAGING_REPO_DIR:-}" ] && git -C "$STAGING_REPO_DIR" cat-file -e "${served}^{commit}" 2>/dev/null && git -C "$STAGING_REPO_DIR" merge-base --is-ancestor "$exp" "$served" 2>/dev/null; then
    say "✅ provenance: staging serves ${served:0:10}, which contains the candidate ${exp:0:10}"
  elif [ -n "${STAGING_REPO_DIR:-}" ] && ! git -C "$STAGING_REPO_DIR" cat-file -e "${served}^{commit}" 2>/dev/null; then
    say "⚠️ provenance UNVERIFIED: served commit ${served:0:10} is unknown to the local clone"
  else say "❌ provenance: staging serves ${served:0:10} but the candidate is ${exp:0:10} — a healthy but STALE deploy (the new deploy did not go live)"; fail=1; fi
fi

# 3. CORS preflight exposes allow-origin for the frontend (only if origin given)
if [ -n "$ORIGIN" ]; then
  acao="$(curl -s -D - -o /dev/null --max-time 15 -X OPTIONS "$BASE$HEALTH_PATH" \
      -H "Origin: $ORIGIN" -H "Access-Control-Request-Method: GET" \
      | tr -d '\r' | awk 'tolower($1)=="access-control-allow-origin:"{print $2}')"
  if [ -n "$acao" ]; then say "✅ CORS allow-origin: $acao"; else say "❌ no access-control-allow-origin for $ORIGIN — browser calls will fail"; fail=1; fi
fi

[ "$fail" -eq 0 ] && { say "SMOKE PASS ($BASE)"; exit 0; } || { say "SMOKE FAIL ($BASE) — do NOT promote"; exit 1; }
