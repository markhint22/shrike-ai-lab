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

# shrike-notify dual-publish (no-op unless SHRIKE_NOTIFY_URL is configured — see
# shrike_notify_lib.sh for the topic taxonomy and env var docs).
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./shrike_notify_lib.sh
[ -f "$LIB_DIR/shrike_notify_lib.sh" ] && source "$LIB_DIR/shrike_notify_lib.sh"

# alert <title> <tags> <body> [repo-for-topic] [priority]
# $repo (the main sweep's loop variable, set by `read` below and in scope for every
# call site inside that loop) is used to build the "fleet_<repo>_deploy" shrike-notify
# topic unless an explicit 4th arg is given — used by the shrike-monitor supplementary
# check below, which runs outside the per-surface loop and has no single $repo.
# 2026-09-28: priority (5th arg, default "default") differentiates genuinely broken/
# decision-needed deploy events (high/urgent) from routine recovery pings (low) — see
# call sites below for the actual tiering.
alert(){
  local topic_repo="${4:-${repo:-queue}}"
  local prio="${5:-default}"
  [ "$DRYRUN" = 1 ] && { echo "  [ntfy] $1 :: $3" ; return 0; }
  curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -H "Priority: $prio" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  command -v shrike_notify_publish >/dev/null 2>&1 && shrike_notify_publish "fleet_${topic_repo}_deploy" "$1" "$2" "$3"
}
log(){ echo "$(date '+%F %T') $*"; }
hc(){ curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }

# key | repo | label | provider | target | health_url | fleet_active(1/0)
#   provider=railway: target = project_id:environment_id:service_id (see note below)
#   provider=vercel:  target = project name
#
# 2026-09-26 FIX: railway rows used to key off a per-repo .env.railway file holding a
# RAILWAY_TOKEN. Those tokens are secrets — one leaked+got-rotated fleet-wide on 2026-09-04
# (see project_committed-railway-tokens-fleet-leak) — and the 3 repos below never got a
# fresh one recreated afterward. railway_stat()'s only response to a missing file was a
# silent "UNKNOWN" (skip), with no alert distinguishing "can't tell" from "healthy" — so
# these 3 backend checks silently no-op'd on every single run for 3+ weeks (2026-09-04 to
# 2026-09-26) while gitlark staging crash-looped the entire time with zero warning.
#
# Fix: use the Mac's own already-authenticated `railway` CLI user session (confirmed
# persistent via ~/.railway/config.json's refreshToken — the same session interactively
# used to diagnose the gitlark crash this session) with hardcoded project/environment/
# service IDs instead of a per-repo secret file. No token file to go stale, and one fewer
# secret sitting in a repo directory. IDs below are PRODUCTION (not secrets - useless
# without the authenticated session) confirmed live via `railway status`/config.json on
# 2026-09-26 for billwatch/gitlark/chickadee-stream(iptv_apps).
SURFACES="
billwatch-backend|billwatch|billwatch backend|railway|38d377fc-d005-41fc-9675-e84659ef7ce1:b1ecd4c1-05d0-40a7-bf1c-44c7664c9a14:31f8e4dd-5827-48a8-9d36-d09dc6ce64c2|https://billwatch-production.up.railway.app/health|1
chickadee-backend|iptv_apps|chickadee backend|railway|5adaa84c-5dd0-40ee-8265-deb5870ee87e:d9dda61d-6154-4eb2-ba9e-f857ee8b9a34:58dcc554-8c73-4fa1-8c0f-653de8f31784|https://chickadeestream-production.up.railway.app/health|1
gitlark-backend|gitlark|gitlark backend|railway|a6a9ae6b-8df9-4d05-8169-25bf13d92293:62ac46fe-07be-4028-9c39-ad8de2b443e3:de12ff53-2434-4b7e-8a32-eb77e02c14dd|https://gitlark-production.up.railway.app/health|1
billwatch-frontend|billwatch|billwatch frontend|vercel|billwatch|https://billwatch.vercel.app|1
chickadee-frontend|iptv_apps|chickadee frontend|vercel|chickadee|https://chickadeestream.com|1
gitlark-frontend|gitlark|gitlark frontend|vercel|gitlark|https://gitlark.vercel.app|1
ripple-frontend|social-media-manager|ripple frontend|vercel|social-media-manager|https://ripple-production.vercel.app|0
website|shrike-labs-website|shrike website|vercel|shrike-labs-website|https://shrikelabs.dev|0
"

command -v railway >/dev/null 2>&1 || { log "FATAL: railway CLI not on PATH"; exit 1; }
command -v vercel  >/dev/null 2>&1 || log "WARN: vercel CLI not on PATH — frontend checks will skip"

# All railway CLI calls run from a dedicated, isolated cwd (not a project checkout) so
# this script's `railway link` state never collides with a human's interactive session
# linked against the same project from LocalProjects/<repo> (config.json keys links by cwd).
RWCWD="$STATE/.railway-cwd"; mkdir -p "$RWCWD"

# ---- provider status: echoes "STATUS<TAB>DEPLOY_ID"  (STATUS in FAILED|OK|INPROGRESS|UNKNOWN) ----
railway_stat(){ # $1=project_id:environment_id:service_id
  local pid eid sid raw did st
  IFS=':' read -r pid eid sid <<<"$1"
  ( cd "$RWCWD" || exit 0
    railway link --project "$pid" --environment "$eid" --service "$sid" >/dev/null 2>&1 || { echo "UNKNOWN	"; exit 0; }
    raw="$(railway deployment list --json --environment "$eid" --service "$sid" --limit 1 2>/dev/null | grep -vE 'setup agent|Tip:')"
    did="$(printf '%s' "$raw" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d[0]["id"] if d else "")
except Exception: print("")' 2>/dev/null)"
    st="$(printf '%s' "$raw" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d[0]["status"] if d else "")
except Exception: print("")' 2>/dev/null)"
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
# target_file <raw log text> — best-effort extraction of a repo-relative file path from a
# Python traceback (`File "/app/some/path.py", line N, in ...`), preferring the LAST frame
# inside /app (the app's own code) over site-packages/vendored frames. Empty if none found.
#
# 2026-09-26 FIX: emergency deploy-fix items enqueued below only ever carried a prose error
# excerpt, never a concrete file path — ovn_retire_vague.py's sanitizer correctly requires a
# named file with a real extension (it exists specifically so the scout doesn't churn
# no-op(BLOCKED) forever on items with nothing to open) and retires anything without one as
# "vague" before the fleet ever attempts it. Confirmed live: billwatch's own psycopg fix
# today (commit f14d5a2) landed only because a human traced the log by hand — the
# auto-enqueued item for the exact same failure was silently retired-vague first. Every
# Railway/Vercel deploy failure this script catches was, by construction, unactionable by
# the fleet until this existed.
target_file(){
  printf '%s\n' "$1" | grep -oE 'File "/app/[^"]+", line [0-9]+' | grep -v '/app/\.venv/\|/site-packages/' | tail -1 | sed -E 's#File "/app/##; s#", line.*##'
}
railway_err(){ # $1=project_id:environment_id:service_id $2=deployment_id -> echoes "FILE<US>EXCERPT" (US = 0x1f: a TAB delimiter made `read` collapse an empty FILE field, so the excerpt became the target file)
  local pid eid sid fulllog tf excerpt
  IFS=':' read -r pid eid sid <<<"$1"
  ( cd "$RWCWD" || exit 0
    railway link --project "$pid" --environment "$eid" --service "$sid" >/dev/null 2>&1
    fulllog="$(railway logs "$2" --service "$sid" --environment "$eid" --lines 60 2>/dev/null | grep -vE 'setup agent|Tip:')"
    tf="$(target_file "$fulllog")"
    excerpt="$(printf '%s' "$fulllog" | grep -iE 'error|failed|exception|traceback|refus|no module|multiple head|cannot|denied|fatal' | tail -6 | tr '\n' ' ' | tr -s ' ' | cut -c1-460)"
    printf '%s\x1f%s\n' "$tf" "$excerpt" )
}
vercel_err(){ # -> echoes "FILE<US>EXCERPT" (US = 0x1f: a TAB delimiter made `read` collapse an empty FILE field, so the excerpt became the target file) (vercel build logs use JS-style "at file.ts:12:34" frames)
  local fulllog tf excerpt
  fulllog="$(vercel inspect "$1" --logs 2>&1)"
  tf="$(printf '%s\n' "$fulllog" | grep -oE '[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|vue|mjs|cjs):[0-9]+' | grep -v 'node_modules/' | tail -1 | sed -E 's/:[0-9]+$//')"
  excerpt="$(printf '%s' "$fulllog" | grep -iE 'error|failed|cannot|not found|module|type|expected|exit code' | tail -6 | tr '\n' ' ' | tr -s ' ' | cut -c1-460)"
  printf '%s\x1f%s\n' "$tf" "$excerpt"
}

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
    railway) read -r st did <<<"$(railway_stat "$target")";;
    vercel)  read -r st did <<<"$(vercel_stat "$target")";;
    *) continue;;
  esac
  st="${st:-UNKNOWN}"
  idf="$STATE/$key.id"; atf="$STATE/$key.attempts"
  usf="$STATE/$key.unknown_streak"; uaf="$STATE/$key.unknown_alerted"

  # 2026-09-26 FIX: a check that silently returns UNKNOWN forever (missing token, broken
  # link, CLI auth expired, API outage) looks identical to "quiet and healthy" in every log
  # line above — this exact blind spot hid gitlark/billwatch/chickadee's Railway checks for
  # 3+ weeks with zero alert. Any run that gets a REAL signal (OK or FAILED) resets the
  # streak; only an unbroken run of UNKNOWNs (this check itself failing, not the deploy)
  # escalates, once, until a real signal returns.
  if [ "$st" = "UNKNOWN" ] || [ "$st" = "INPROGRESS" ]; then
    if [ "$st" = "UNKNOWN" ]; then
      streak=$(( $(cat "$usf" 2>/dev/null || echo 0) + 1 ))
      echo "$streak" > "$usf"
      if [ "$streak" -ge 6 ] && [ ! -f "$uaf" ]; then
        touch "$uaf"
        alert "🕳️ $label monitoring is blind (${streak}x UNKNOWN)" "warning" "deploy_watch has gotten UNKNOWN from $label for $streak consecutive checks (~$((streak*20))min) — this means the CHECK ITSELF is broken (railway link/auth/API), not necessarily the deploy. Investigate deploy_watch.sh's railway_stat for $key before trusting silence here again."
        log "$key: MONITORING-BLIND escalated after $streak consecutive UNKNOWN"
      fi
    fi
    log "$key: $st (skip)"; continue
  fi
  rm -f "$usf" "$uaf" 2>/dev/null

  if [ "$st" = OK ]; then
    if [ -f "$idf" ]; then          # we'd acted on a failure -> report the RESULT
      atts="$(cat "$atf" 2>/dev/null || echo 0)"; rm -f "$idf" "$atf"
      code="$(hc "$health")"
      if [ "$code" = 200 ] || [ "$code" = 307 ]; then
        alert "✅ Deploy recovered: $label" "white_check_mark" "$label recovered — deploy is healthy and /health returns HTTP $code (after $atts fix attempt(s)). Auto-heal worked." "" "low"
      else
        alert "⚠️ $label deployed but /health=$code" "warning" "$label's deploy is healthy again but /health returns HTTP $code (not 200/307) — built but maybe not serving right. Check it."
      fi
      log "$key: RECOVERED (/health=$code, after $atts)"
    else log "$key: $st"; fi
    continue
  fi

  # FAILED
  [ "$(cat "$idf" 2>/dev/null)" = "$did" ] && { log "$key: FAILED (already handled $did)"; continue; }
  atts=$(( $(cat "$atf" 2>/dev/null || echo 0) + 1 ))
  case "$provider" in railway) IFS=$'\x1f' read -r tfile err <<<"$(railway_err "$target" "$did")";; vercel) IFS=$'\x1f' read -r tfile err <<<"$(vercel_err "$did")";; esac
  [ -n "$err" ] || err="(no error captured — inspect the $provider deploy $did)"
  echo "$did" > "$idf"; echo "$atts" > "$atf"

  if [ "$atts" -ge "$MAX_ATTEMPTS" ]; then
    # auto-fix exhausted -> deeper-dive snapshot + human escalation, stop churning
    { echo "=== $(date '+%F %T') ESCALATION $key ($label) after $atts attempts ==="; echo "deploy: $did"; echo "error: $err"; } >> "$STATE/escalations.log"
    alert "🆘 $label deploy STILL failing (${atts}x)" "sos" "$label has failed $atts deploys in a row — the auto-fix isn't recovering it. Backing off (no more auto-queue) — this needs a human / deeper dive. Latest error: ${err:0:200} — snapshot in ~/.deploy_watch/escalations.log" "" "urgent"
    log "$key: ESCALATED after $atts attempts"
    continue
  fi

  if [ "$fleet" = 1 ]; then
    ts="$(date '+%Y-%m-%d')"
    # A named TARGET FILE (when extraction succeeded) is load-bearing, not decorative:
    # ovn_retire_vague.py's sanitizer requires a real file+extension in the item text or it
    # retires the item as "vague" before the fleet ever attempts it (see target_file()'s note
    # above) — without this, every emergency item enqueued below silently never gets tried.
    if [ "$provider" = vercel ]; then
      if [ -n "$tfile" ]; then
        item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Vercel PRODUCTION frontend build FAILED — prod is serving the last good build. TARGET FILE: ${tfile} — start there. Fix the build error so it compiles and deploys. ERROR EXCERPT: ${err}"
      else
        item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Vercel PRODUCTION frontend build FAILED — prod is serving the last good build. Fix the web build error so it compiles and deploys (check the web/ dir build + typecheck). ERROR EXCERPT: ${err}"
      fi
    else
      if [ -n "$tfile" ]; then
        item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Railway PRODUCTION deploy FAILED — prod is frozen on the last good build. TARGET FILE: ${tfile} — start there. Fix the code so it builds, starts, and passes /health. ERROR EXCERPT: ${err}"
      else
        item="- [ ] [T4] ${label} — 🚨 EMERGENCY DEPLOY FIX (auto-added ${ts}): the Railway PRODUCTION deploy FAILED — prod is frozen on the last good build. Fix the code so it builds, starts, and passes /health. ERROR EXCERPT: ${err}"
      fi
    fi
    if [ "$DRYRUN" = 1 ]; then
      log "$key: FAILED ($did) attempt $atts -> WOULD enqueue fix into $repo"
      alert "🚨 Deploy failed: $label" "rotating_light" "$label deploy FAILED — auto-fix queued (attempt $atts/$MAX_ATTEMPTS). ${err:0:180}" "" "high"
    elif enqueue_fix "$repo" "$key" "$item"; then
      log "$key: FAILED ($did) -> enqueued fix (attempt $atts)"
      alert "🚨 Deploy failed: $label" "rotating_light" "$label deploy FAILED — auto-fix queued into the overnight queue (attempt $atts/$MAX_ATTEMPTS). ${err:0:180}" "" "high"
    else
      log "$key: FAILED but enqueue errored"
      alert "⚠️ deploy_watch couldn't enqueue $label" "warning" "$label deploy FAILED and the auto-fix couldn't be injected (ssh/git). Check /tmp/deploy_watch.log." "" "high"
    fi
  else
    # not fleet-managed -> the 27B can't fix it; ntfy as a human task
    log "$key: FAILED ($did) — non-fleet, human-escalated"
    alert "🚨 Deploy failed: $label (human)" "rotating_light" "$label deploy FAILED and this repo isn't 27B-managed — needs you. ${err:0:200}" "" "urgent"
  fi
done <<< "$SURFACES"

# ---- supplementary signal: shrike-monitor fleet status ----
# Independent of the Railway/Vercel CLI checks above (doesn't replace them — this
# is the "one more health signal" the SHRIKE_MONITOR_URL integration adds). No-op
# unless SHRIKE_MONITOR_URL is set (see register_monitors.sh + HUMAN_QUEUE.md).
shrike_monitor_supplement(){
  [ -n "${SHRIKE_MONITOR_URL:-}" ] || return 0
  local murl="${SHRIKE_MONITOR_URL%/}" hdr=() out total healthy
  [ -n "${SHRIKE_MONITOR_TOKEN:-}" ] && hdr=(-H "Authorization: Bearer ${SHRIKE_MONITOR_TOKEN}")
  out="$(curl -fsS --max-time 8 "${hdr[@]}" "$murl/monitors/status" 2>/dev/null)" || { log "shrike-monitor: unreachable (skip supplementary check)"; return 0; }
  total="$(printf '%s' "$out" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("total_monitors", ""))
except Exception:
    print("")' 2>/dev/null)"
  healthy="$(printf '%s' "$out" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("healthy_monitors", ""))
except Exception:
    print("")' 2>/dev/null)"
  [ -n "$total" ] || { log "shrike-monitor: couldn't parse /monitors/status response"; return 0; }
  log "shrike-monitor: $healthy/$total monitors healthy (supplementary signal)"
  if [ "$healthy" != "$total" ]; then
    alert "⚠️ shrike-monitor: fleet degraded ($healthy/$total)" "warning" "shrike-monitor independently reports $healthy/$total monitors healthy — a supplementary signal alongside deploy_watch's own Railway/Vercel checks above. Check shrike-monitor's /monitors/*/incidents for which surface." "queue"
  fi
}
shrike_monitor_supplement

log "deploy_watch pass complete"
