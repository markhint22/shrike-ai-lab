#!/usr/bin/env bash
# deploy_health.sh — user-facing deployment health across ALL surfaces.
#
# deploy_watch.sh only catches Railway *build* failures (crash-loops it can code-fix).
# This complements it by HTTP-checking what a real user hits — every backend AND
# frontend AND Fly app — so a frontend build failure, a 500, or a Fly ancient-build
# 404 is caught too, and so you can get a trustworthy "green everywhere" signal
# instead of chasing stale alerts from one surface.
#
# It alerts only on TRANSITIONS (healthy->down or down->recovered), state-tracked per
# surface, so it never spams. Known human-gated surfaces (custom domains not yet DNS'd)
# are listed separately and alerted as human tasks, never as "outages".
#
# Cron (Mac): */10 * * * * .../deploy_health.sh >> /tmp/deploy_health.log 2>&1
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
DRYRUN="${DRYRUN:-0}"
# DRYRUN must NEVER touch the live dedup state (clearing it makes the next REAL run
# re-alert every known issue — the #1 self-inflicted cause of alert spam). Use a
# throwaway state dir when dry-running so testing is fully isolated.
if [ "$DRYRUN" = 1 ]; then STATE="$(mktemp -d)"; else STATE="$HOME/.deploy_health"; fi
mkdir -p "$STATE"
# Suppression list: keys here are LOGGED but never ntfy'd (known human-gated issues).
SUPPRESS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/alert_suppress.txt"
suppressed(){ [ -f "$SUPPRESS_FILE" ] && grep -vE '^\s*#|^\s*$' "$SUPPRESS_FILE" | sed 's/#.*//' | awk '{print $1}' | grep -qxF "$1"; }
alert(){ # alert <key> <title> <tags> <body> [priority]  — respects DRYRUN + suppression
  local key="$1"; shift
  if suppressed "$key"; then log "  (suppressed alert for $key — human-gated, see alert_suppress.txt)"; return 0; fi
  [ "$DRYRUN" = 1 ] && return 0
  local prio="${4:-default}"
  curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -H "Priority: $prio" -d "$3" "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true; }
log(){ echo "$(date '+%F %T') $*"; }
code(){ curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }
healthy(){ case "$1" in 200|301|302|307|308) return 0;; *) return 1;; esac; }
# Debounce: a surface must fail FAILS_THRESHOLD consecutive checks before alerting DOWN
# (kills transient single-sample 000/blip flaps). Recovery still alerts on the first green.
FAILS_THRESHOLD="${FAILS_THRESHOLD:-2}"

# 2026-09-30: ripple-* and taskmanager-backend REMOVED - Ripple/VoiceRipple and FlockWorks (task-manager) were DISCONTINUED
# 2026-09-09 (backends taken down on purpose; the ripple-backend 404 was reported as still down every 10 minutes
# indefinitely). Do not re-add. NOTE: no comment lines and no double quotes inside the SURFACES string below - a
# quoted phrase in a comment there closed the string early and silently disabled this whole check (2026-09-30).
# name|url  - the WORKING platform surfaces that must stay up (backend + frontend per product)
SURFACES="
billwatch-backend|https://billwatch-production.up.railway.app/health
billwatch-frontend|https://billwatch.vercel.app
gitlark-backend|https://gitlark-production.up.railway.app/health
gitlark-frontend|https://gitlark.vercel.app
chickadee-backend|https://chickadeestream-production.up.railway.app/health
chickadee-frontend|https://chickadeestream.com
specpilot-backend|https://specpilot.fly.dev/health
shrike-website|https://shrikelabs.dev
"

fails=0; checked=0
for line in $SURFACES; do
  [ -z "$line" ] && continue
  name="${line%%|*}"; url="${line#*|}"; checked=$((checked+1))
  c="$(code "$url")"
  sf="$STATE/$name.state"; prev="$(cat "$sf" 2>/dev/null || echo NEW)"
  cf="$STATE/$name.fails"; nfail="$(cat "$cf" 2>/dev/null || echo 0)"
  if healthy "$c"; then
    if [ "$prev" != NEW ] && ! healthy "$prev"; then
      alert "$name" "✅ Recovered: $name" "white_check_mark" "$name is back up — HTTP $c ($url)." "low"
      log "$name: RECOVERED ($c)"
    else log "$name: ok ($c)"; fi
    echo "$c" > "$sf"; echo 0 > "$cf"
  else
    fails=$((fails+1))
    nfail=$((nfail+1)); echo "$nfail" > "$cf"
    # classify the likely cause for a useful push
    case "$c" in
      000) cause="unreachable/DNS or app down";;
      404) cause="404 — wrong route or a build serving without the app mounted";;
      5*)  cause="server error ($c) — likely a crash or bad deploy";;
      *)   cause="HTTP $c";;
    esac
    # Debounce: only alert once we've seen FAILS_THRESHOLD consecutive fails, and only
    # on the transition into "down" (fires exactly when the counter crosses the line).
    if [ "$nfail" -eq "$FAILS_THRESHOLD" ]; then
      alert "$name" "🔴 DOWN: $name" "rotating_light" "$name is DOWN — HTTP $c: $cause (${nfail}x consecutive). URL: $url. (deploy_watch will auto-fix a Railway *build* failure; a frontend/Fly/DNS issue needs a redeploy or a human.)" "high"
      log "$name: DOWN ($c, ${nfail}x) — $cause"
    elif [ "$nfail" -lt "$FAILS_THRESHOLD" ]; then
      log "$name: soft-fail ($c, ${nfail}/${FAILS_THRESHOLD} — debouncing, no alert yet)"
    else log "$name: still down ($c, ${nfail}x)"; fi
    echo "$c" > "$sf"
  fi
done

# SpecPilot route-drift smoke: /health can be 200 while the deployed build is ancient
# (new routes 404). Catch that specifically (the audit's recommended check).
sp="$(code https://specpilot.fly.dev/api/orgs)"
spf="$STATE/specpilot-routes.state"; sprev="$(cat "$spf" 2>/dev/null || echo NEW)"
if [ "$sp" = 404 ]; then
  [ "$sprev" != 404 ] && alert "specpilot-routes" "⚠️ SpecPilot serving an old build" "warning" "specpilot.fly.dev /health is up but /api/orgs returns 404 — the live Fly build predates the current code (deploy not wired to main). Human: set FLY_API_TOKEN / wire fly deploy. See HUMAN_QUEUE." "default"
  log "specpilot-routes: 404 (ancient build — human-gated, suppressed)"
else
  [ "$sprev" = 404 ] && alert "specpilot-routes-recovered" "✅ SpecPilot routes live" "white_check_mark" "specpilot.fly.dev /api/orgs now returns $sp — the Fly build is current again." "low"
  log "specpilot-routes: ok ($sp)"
fi
echo "$sp" > "$spf"

log "deploy_health: $checked surfaces checked, $fails currently failing"
