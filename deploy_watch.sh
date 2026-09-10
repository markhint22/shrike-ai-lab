#!/usr/bin/env bash
# deploy_watch.sh — Mac-side deploy self-heal for BOTH Railway (backends) and Vercel (frontends).
#
# For each monitored surface it reads the latest PRODUCTION deploy status:
#   - FAILED (Railway FAILED/CRASHED, Vercel Error) -> pull the build error and, if the
#     repo is fleet-managed, inject a prioritized "🚨 EMERGENCY DEPLOY FIX" item into the
#     repo's overnight queue (hold-safe) so the 27B fleet fixes it next cycle. ntfy on fail.
#   - RECOVERED (was failing, now healthy) -> ntfy the RESULT (✅ + live /health, or ⚠️).
#   - Escalation: if the SAME surface fails MAX_ATTEMPTS (3) distinct deploys in a row, the
#     auto-fix isn't working -> stop churning, log a deeper-dive snapshot, and send a 🆘
#     human-escalation ntfy (see "what if the fix fails" below).
#
# Non-fleet repos (task-manager, ripple, website) can't be auto-fixed by the 27B, so a
# failure there ntfys as a human task instead of enqueuing a phantom item.
#
# Runs on the Mac: that's where the Railway CLI + tokens + account login AND the Vercel
# CLI (authed) live. Cron (Mac): */20 * * * * .../deploy_watch.sh >> /tmp/deploy_watch.log 2>&1
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

LOCAL="${LOCAL_PROJECTS:-/Users/mhintermeister/LocalProjects}"
SRV="${OVN_SERVER:-mhintermeister@100.79.64.64}"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
ENQ_REMOTE="scripts/ovn_enqueue_emergency.py"
DRYRUN="${DRYRUN:-0}"
# DRYRUN must NEVER touch the live dedup state — clearing the per-deploy-id markers makes
# the next REAL run re-alert every currently-failing surface (the self-inflicted spam we hit).
if [ "$DRYRUN" = 1 ]; then STATE="$(mktemp -d)"; else STATE="$HOME/.deploy_watch"; fi
mkdir -p "$STATE"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
# Suppression list (shared with deploy_health.sh): keys here are LOGGED but never alerted
# or auto-enqueued — for known human-gated surfaces with no per-cycle fix.
SUPPRESS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/alert_suppress.txt"
suppressed(){ [ -f "$SUPPRESS_FILE" ] && grep -vE '^\s*#|^\s*$' "$SUPPRESS_FILE" | sed 's/#.*//' | awk '{print $1}' | grep -qxF "$1"; }

alert(){ [ "$DRYRUN" = 1 ] && { echo "  [ntfy] $1 :: $3" ; return 0; }; curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true; }
log(){ echo "$(date '+%F %T') $*"; }
hc(){ curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }

# key | repo | label | provider | target | health_url | fleet_active(1/0)
#   provider=railway: target = service name          provider=vercel: target = project name
SURFACES="
billwatch-backend|billwatch|billwatch backend|railway|billwatch|https://billwatch-production.up.railway.app/health|1
chickadee-backend|iptv_apps|chickadee backend|railway|chickadeestream-backend|https://chickadeestream-production.up.railway.app/health|1
gitlark-backend|gitlark|gitlark backend|railway|gitlark|https://gitlark-production.up.railway.app/health|1
billwatch-frontend|billwatch|billwatch frontend|vercel|billwatch|https://billwatch.vercel.app|1
chickadee-frontend|iptv_apps|chickadee frontend|vercel|chickadee|https://chickadeestream.com|1
gitlark-frontend|gitlark|gitlark frontend|vercel|gitlark|https://gitlark.vercel.app|1
ripple-frontend|social-media-manager|ripple frontend|vercel|social-media-manager|https://ripple-production.vercel.app|0
website|shrike-labs-website|shrike website|vercel|shrike-labs-website|https://shrikelabs.dev|0
"

command -v railway >/dev/null 2>&1 || { log "FATAL: railway CLI not on PATH"; exit 1; }
command -v vercel  >/dev/null 2>&1 || log "WARN: vercel CLI not on PATH — frontend checks will skip"

# ---- provider status: echoes "STATUS<TAB>DEPLOY_ID"  (STATUS in FAILED|OK|INPROGRESS|UNKNOWN) ----
railway_stat(){ # $1=repo $2=service  (cwd-independent; uses the repo's project token to link)
  local repo="$1" svc="$2" d="$LOCAL/$1" pid raw did st
  [ -f "$d/.env.railway" ] || { echo "UNKNOWN	"; return; }
  ( cd "$d" || exit 0
    pid="$(RAILWAY_TOKEN="$(grep -E '^RAILWAY_TOKEN=' .env.railway | cut -d= -f2- | tr -d '"'"'"'[:space:]')" railway status --json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)"
    [ -n "$pid" ] || { echo "UNKNOWN	"; exit 0; }
    railway link --project "$pid" --environment production --service "$svc" >/dev/null 2>&1 || { echo "UNKNOWN	"; exit 0; }
    raw="$(railway deployment list 2>/dev/null | grep -vE 'setup agent|Tip:' | grep -oE '[0-9a-f-]{36} \| [A-Z]+' | head -1 | tr -d '|')"
    did="$(echo "$raw" | awk '{print $1}')"; st="$(echo "$raw" | awk '{print $2}')"
    case "$st" in FAILED|CRASHED) echo "FAILED	$did";; SUCCESS) echo "OK	$did";; BUILDING|DEPLOYING|INITIALIZING|QUEUED) echo "INPROGRESS	$did";; *) echo "UNKNOWN	$did";; esac )
}
vercel_stat(){ # $1=project
  command -v vercel >/dev/null 2>&1 || { echo "UNKNOWN	"; return; }
  local url st
  url="$(vercel ls "$1" --prod 2>/dev/null | grep -oE 'https://[a-z0-9-]+\.vercel\.app' | head -1)"
  [ -n "$url" ] || { echo "UNKNOWN	"; return; }
  st="$(vercel inspect "$url" 2>&1 | grep -iE '^[[:space:]]*status' | grep -oE 'Ready|Error|Building|Queued|Canceled|Failed' | head -1)"
  case "$st" in Error|Failed|Canceled) echo "FAILED	$url";; Ready) echo "OK	$url";; Building|Queued) echo "INPROGRESS	$url";; *) echo "UNKNOWN	$url";; esac
}
railway_err(){ ( cd "$LOCAL/$1" 2>/dev/null || exit 0; railway logs "$2" 2>/dev/null | grep -vE 'setup agent|Tip:' | grep -iE 'error|failed|exception|traceback|refus|no module|multiple head|cannot|denied|fatal' | tail -6 | tr '\n' ' ' | tr -s ' ' | cut -c1-460 ); }
vercel_err(){ vercel inspect "$1" --logs 2>&1 | grep -iE 'error|failed|cannot|not found|module|type|expected|exit code' | tail -6 | tr '\n' ' ' | tr -s ' ' | cut -c1-460; }

enqueue_fix(){ # $1=repo $2=surface-label $3=item-text  -> 0 ok
  # 2026-09-07 FIX: base64 the item text. Previously ITEM="$3" was passed as an ssh command-line env
  # var, which the REMOTE shell re-parses — so any special char in the deploy-error excerpt ($ ` " '
  # [ ] newlines) word-split/globbed and the enqueue crashed ("enqueue errored", 2026-09-04). base64
  # is single-line + shell-safe on both sides; the remote decodes it back to the exact bytes.
  local item_b64; item_b64="$(printf '%s' "$3" | base64 | tr -d '\n')"
  ssh -o ConnectTimeout=15 -o BatchMode=yes "$SRV" REPO="$1" SVC="$2" ITEM_B64="$item_b64" ENQ="$ENQ_REMOTE" 'bash -s' <<'REMOTE'
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
ITEM="$(printf '%s' "$ITEM_B64" | base64 -d)"
./queue.sh hold "$REPO" >/dev/null 2>&1 || true
cleanup(){ cd "$HOME/overnight-queue" && ./queue.sh release "$REPO" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cd "repos/$REPO" || exit 1
git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature || exit 1
python3 "$HOME/overnight-queue/$ENQ" OVERNIGHT_PROGRESS.md "$SVC" "$ITEM" || exit 1
git diff --quiet -- OVERNIGHT_PROGRESS.md && { echo "noop"; exit 0; }
git add OVERNIGHT_PROGRESS.md
git commit -q -m "chore(queue): 🚨 auto-enqueue emergency deploy-fix for $REPO ($SVC)"
git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
echo enqueued
REMOTE
}

# ---- main sweep ----
while IFS='|' read -r key repo label provider target health fleet; do
  [ -z "${key// /}" ] && continue        # skip blank lines (read line-by-line; fields contain spaces)
  if suppressed "$key"; then log "$key: suppressed (human-gated, see alert_suppress.txt)"; continue; fi
  case "$provider" in
    railway) read -r st did <<<"$(railway_stat "$repo" "$target")";;
    vercel)  read -r st did <<<"$(vercel_stat "$target")";;
    *) continue;;
  esac
  st="${st:-UNKNOWN}"
  idf="$STATE/$key.id"; atf="$STATE/$key.attempts"

  if [ "$st" = OK ]; then
    if [ -f "$idf" ]; then          # we'd acted on a failure -> report the RESULT
      atts="$(cat "$atf" 2>/dev/null || echo 0)"; rm -f "$idf" "$atf"
      code="$(hc "$health")"
      if [ "$code" = 200 ] || [ "$code" = 307 ]; then
        alert "✅ Deploy recovered: $label" "white_check_mark" "$label recovered — deploy is healthy and /health returns HTTP $code (after $atts fix attempt(s)). Auto-heal worked."
      else
        alert "⚠️ $label deployed but /health=$code" "warning" "$label's deploy is healthy again but /health returns HTTP $code (not 200/307) — built but maybe not serving right. Check it."
      fi
      log "$key: RECOVERED (/health=$code, after $atts)"
    else log "$key: $st"; fi
    continue
  fi
  [ "$st" != FAILED ] && { log "$key: $st (skip)"; continue; }   # INPROGRESS/UNKNOWN -> wait

  # FAILED
  [ "$(cat "$idf" 2>/dev/null)" = "$did" ] && { log "$key: FAILED (already handled $did)"; continue; }
  atts=$(( $(cat "$atf" 2>/dev/null || echo 0) + 1 ))
  case "$provider" in railway) err="$(railway_err "$repo" "$did")";; vercel) err="$(vercel_err "$did")";; esac
  [ -n "$err" ] || err="(no error captured — inspect the $provider deploy $did)"
  echo "$did" > "$idf"; echo "$atts" > "$atf"

  if [ "$atts" -ge "$MAX_ATTEMPTS" ]; then
    # auto-fix exhausted -> deeper-dive snapshot + human escalation, stop churning
    { echo "=== $(date '+%F %T') ESCALATION $key ($label) after $atts attempts ==="; echo "deploy: $did"; echo "error: $err"; } >> "$STATE/escalations.log"
    alert "🆘 $label deploy STILL failing (${atts}x)" "sos" "$label has failed $atts deploys in a row — the auto-fix isn't recovering it. Backing off (no more auto-queue) — this needs a human / deeper dive. Latest error: ${err:0:200} — snapshot in ~/.deploy_watch/escalations.log"
    log "$key: ESCALATED after $atts attempts"
    continue
  fi

  if [ "$fleet" = 1 ]; then
    ts="$(date '+%Y-%m-%d')"
    if [ "$provider" = vercel ]; then
      item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Vercel PRODUCTION frontend build FAILED — prod is serving the last good build. Fix the web build error so it compiles and deploys (check the web/ dir build + typecheck). ERROR EXCERPT: ${err}"
    else
      item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Railway PRODUCTION deploy FAILED — prod is frozen on the last good build. Fix the code so it builds, starts, and passes /health. ERROR EXCERPT: ${err}"
    fi
    if [ "$DRYRUN" = 1 ]; then
      log "$key: FAILED ($did) attempt $atts -> WOULD enqueue fix into $repo"
      alert "🚨 Deploy failed: $label" "rotating_light" "$label deploy FAILED — auto-fix queued (attempt $atts/$MAX_ATTEMPTS). ${err:0:180}"
    elif enqueue_fix "$repo" "$key" "$item"; then
      log "$key: FAILED ($did) -> enqueued fix (attempt $atts)"
      alert "🚨 Deploy failed: $label" "rotating_light" "$label deploy FAILED — auto-fix queued into the overnight queue (attempt $atts/$MAX_ATTEMPTS). ${err:0:180}"
    else
      log "$key: FAILED but enqueue errored"
      alert "⚠️ deploy_watch couldn't enqueue $label" "warning" "$label deploy FAILED and the auto-fix couldn't be injected (ssh/git). Check /tmp/deploy_watch.log."
    fi
  else
    # not fleet-managed -> the 27B can't fix it; ntfy as a human task
    log "$key: FAILED ($did) — non-fleet, human-escalated"
    alert "🚨 Deploy failed: $label (human)" "rotating_light" "$label deploy FAILED and this repo isn't 27B-managed — needs you. ${err:0:200}"
  fi
done <<< "$SURFACES"
log "deploy_watch pass complete"
