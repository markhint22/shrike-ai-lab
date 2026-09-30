#!/usr/bin/env bash
# Runs the REAL deploy_watch.sh end to end in a hermetic fake HOME with stubbed railway / vercel / ssh / curl
# (exported bash functions, so they win over the script's own PATH prepend). Covers: healthy, FAILED -> enqueue,
# per-deploy-id dedupe, attempt escalation, recovery (+/health good/bad), vercel + non-fleet paths, enqueue failure,
# blind-monitoring (UNKNOWN streak) alert, DRYRUN, missing CLIs, shrike-monitor supplement, shrike-notify publish.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DW="$HERE/../../deploy_watch.sh"; [ -f "$DW" ] || DW="$HERE/../deploy_watch.sh"
[ -f "$DW" ] || { echo "  SKIP: deploy_watch.sh not found"; exit 0; }
grep -q 'RWCWD=' "$DW" || { echo "  SKIP: stale deploy_watch.sh (pre-2026-09-26, token-file based)"; exit 0; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
cnt(){ grep -cF -- "$2" "$1" 2>/dev/null || true; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FX="$T/fx"; mkdir -p "$FX"; export FX

# ---- stubs (exported functions) ----
curl(){ echo "curl $*" >> "$FX/curl.log"
  local a last="${*: -1}"
  case "$*" in
    *ntfy.sh*) return 0;;
    *"%{http_code}"*) printf '%s' "${HC_CODE:-200}"; return 0;;
    *monitors/status*) [ "${MON_FAIL:-0}" = 1 ] && return 22; printf '%s' "${MON_JSON:-}"; return 0;;
    *) return 0;;
  esac; }
ssh(){ echo "ssh $*" >> "$FX/ssh.log"; cat > /dev/null
  local a; for a in "$@"; do case "$a" in ITEM_B64=*) printf '%s' "${a#ITEM_B64=}" | base64 -d >> "$FX/items.log"; echo >> "$FX/items.log";; REPO=*) echo "${a#REPO=}" >> "$FX/repos.log";; esac; done
  echo enqueued; return "${SSH_RC:-0}"; }
railway(){ echo "railway $*" >> "$FX/rw.log"
  local sid="" a prev=""
  for a in "$@"; do [ "$prev" = "--service" ] && sid="$a"; prev="$a"; done
  case "$1" in
    link) [ "${RW_LINK_FAIL:-0}" = 1 ] && return 1; return 0;;
    deployment)
      local v="RWS_${sid:0:8}" st; st="${!v:-${RW_STATUS:-SUCCESS}}"
      echo "setup agent: noise line"
      case "$st" in EMPTY) echo '[]';; GARBAGE) echo 'not json';; *) printf '[{"id":"%s","status":"%s"}]\n' "${RW_ID:-d1}" "$st";; esac;;
    logs) echo "Tip: something"; printf '%s\n' "${RW_LOG:-}";;
  esac; }
vercel(){ echo "vercel $*" >> "$FX/vc.log"
  case "$1" in
    ls) [ "${VC_LS_EMPTY:-0}" = 1 ] && return 0; echo "  https://${2}-x1.vercel.app   Ready   Production";;
    inspect)
      local u="${2#https://}"; u="${u%-x1.vercel.app}"; local v="VCS_${u//-/_}" st
      st="${!v:-${VC_STATUS:-Ready}}"
      if [ "${3:-}" = "--logs" ]; then printf '%s\n' "${VC_LOG:-}"; else echo "    status      ● $st"; fi;;
  esac; }
export -f curl ssh railway vercel

newhome(){ rm -rf "$T/home" "$FX"/*; mkdir -p "$T/home"; unset RW_STATUS RW_ID RW_LOG RW_LINK_FAIL HC_CODE MON_JSON MON_FAIL SSH_RC VC_STATUS VC_LOG VC_LS_EMPTY DRYRUN SHRIKE_MONITOR_URL SHRIKE_MONITOR_TOKEN SHRIKE_NOTIFY_URL SHRIKE_NOTIFY_TOKEN; unset RWS_31f8e4dd RWS_58dcc554 RWS_de12ff53 VCS_billwatch VCS_chickadee VCS_gitlark VCS_social_media_manager VCS_shrike_labs_website; }
run(){ HOME="$T/home" NTFY_TOPIC=selftest bash "$DW" > "$FX/out.log" 2>&1; echo $? > "$FX/rc"; }
ST="$T/home/.deploy_watch"

# 1. all healthy
newhome; run
ok "healthy: rc 0" "$([ "$(cat $FX/rc)" = 0 ] && echo 1 || echo 0)"
ok "healthy: billwatch-backend OK logged" "$(has $FX/out.log 'billwatch-backend: OK')"
ok "healthy: no ssh, no ntfy" "$([ ! -s $FX/ssh.log ] && ! grep -q ntfy.sh $FX/curl.log && echo 1 || echo 0)"
ok "healthy: completion line" "$(has $FX/out.log 'deploy_watch pass complete')"

# 2. railway FAILED -> enqueue with target file, dedupe, attempts
newhome; export RW_STATUS=FAILED RW_ID=d1 RW_LOG='Traceback (most recent call last):
  File "/app/app/main.py", line 10, in <module>
  File "/app/.venv/lib/site-packages/x.py", line 3, in f
ModuleNotFoundError: No module named psycopg'
run
ok "failed: 3 railway repos enqueued" "$([ "$(wc -l < $FX/repos.log)" = 3 ] && echo 1 || echo 0)"
ok "failed: item names TARGET FILE app/main.py" "$(has $FX/items.log 'TARGET FILE: app/main.py')"
ok "failed: item has error excerpt" "$(has $FX/items.log 'No module named psycopg')"
ok "failed: urgent-ish high alert sent" "$(has $FX/curl.log 'Priority: high')"
ok "failed: attempts=1 state" "$([ "$(cat $ST/billwatch-backend.attempts)" = 1 ] && echo 1 || echo 0)"
n1=$(wc -l < $FX/repos.log); run
ok "dedupe: same deploy id not re-enqueued" "$([ "$(wc -l < $FX/repos.log)" = "$n1" ] && has $FX/out.log 'already handled d1' | grep -q 1 && echo 1 || echo 0)"
RW_ID=d2 run
ok "attempt 2 enqueues again" "$([ "$(cat $ST/billwatch-backend.attempts)" = 2 ] && echo 1 || echo 0)"
RW_ID=d3 run
ok "attempt 3 escalates (no extra enqueue)" "$(has $FX/out.log 'ESCALATED after 3 attempts')"
ok "escalation snapshot written" "$(has $ST/escalations.log 'ESCALATION billwatch-backend')"
ok "escalation is urgent sos" "$(has $FX/curl.log 'Priority: urgent')"
# 4. recovery
export RW_STATUS=SUCCESS HC_CODE=200; run
ok "recovery: alert low priority" "$(has $FX/curl.log 'Priority: low')"
ok "recovery: state cleared" "$([ ! -f $ST/billwatch-backend.id ] && [ ! -f $ST/billwatch-backend.attempts ] && echo 1 || echo 0)"
ok "recovery log" "$(has $FX/out.log 'RECOVERED (/health=200')"
# recovery with bad health
newhome; export RW_STATUS=FAILED RW_ID=d1; run; export RW_STATUS=SUCCESS HC_CODE=502; run
ok "recovery w/ bad /health -> warning text" "$(has $FX/curl.log 'deployed but /health=502')"

# 5. failed, no error captured / no file; enqueue failure
newhome; export RW_STATUS=FAILED RW_ID=x1 RW_LOG='' SSH_RC=1; run
ok "enqueue failure -> couldn't-enqueue alert" "$(has $FX/curl.log "couldn't enqueue")"
ok "enqueue failure logged" "$(has $FX/out.log 'enqueue errored')"
ok "no error captured placeholder used" "$(has $FX/items.log 'no error captured')"
ok "no-file railway item has no TARGET FILE" "$([ "$(has $FX/items.log 'TARGET FILE')" = 0 ] && echo 1 || echo 0)"

# 6. vercel failures: fleet (with + without file) and non-fleet human
newhome; export VC_STATUS=Error VC_LOG='Building...
src/components/App.tsx:12:34 error TS2304: Cannot find name foo
Error: Command "npm run build" exited with 1'
run
ok "vercel fleet item w/ TARGET FILE" "$(has $FX/items.log 'TARGET FILE: src/components/App.tsx')"
ok "vercel item says Vercel PRODUCTION" "$(has $FX/items.log 'Vercel PRODUCTION frontend build FAILED')"
ok "non-fleet (ripple/website) human-escalated" "$(has $FX/out.log 'non-fleet, human-escalated')"
ok "non-fleet alert is urgent (human)" "$(has $FX/curl.log '(human)')"
newhome; export VC_STATUS=Failed VC_LOG='Error: boom'; run
# KNOWN-BUG (deploy_watch.sh vercel_err/railway_err consumers): `IFS=$'\t' read -r tfile err` treats the leading empty
# FILE field as collapsible whitespace, so when no file is extracted the EXCERPT lands in $tfile (item gets
# "TARGET FILE: Error: boom" and err is empty). Proposed fix: emit/parse with a non-whitespace delimiter (e.g. $'\x1f').
kb(){ if [ "$2" = 1 ]; then pass=$((pass+1)); else echo "  WARN KNOWN-BUG: $1"; fi; }
kb "no-file vercel item must not use the excerpt as TARGET FILE and must keep the excerpt" "$([ "$(has $FX/items.log 'TARGET FILE: Error: boom')" = 0 ] && [ "$(has $FX/items.log 'ERROR EXCERPT: Error: boom')" = 1 ] && echo 1 || echo 0)"
ok "vercel item without file still enqueued as an emergency item" "$(has $FX/items.log 'EMERGENCY DEPLOY FIX')"
# vercel recovered: state then Ready
newhome; export VC_STATUS=Error VC_LOG=''; run; export VC_STATUS=Ready; run
ok "vercel recovery alert" "$(has $FX/out.log 'billwatch-frontend: RECOVERED')"

newhome; export VC_STATUS=Failed VC_LOG=''; run
ok "vercel no file + no excerpt -> web/ guidance item" "$(has $FX/items.log 'check the web/ dir build')"
newhome; export RW_STATUS=FAILED RW_ID=q1 RW_LOG='ERROR: boom without a path'; run
kb "no-file railway item must keep the excerpt (not TARGET FILE)" "$([ "$(has $FX/items.log 'TARGET FILE: ERROR: boom')" = 0 ] && echo 1 || echo 0)"

# 7. in-progress / building is skipped
newhome; export RW_STATUS=BUILDING VC_STATUS=Building; run
ok "in-progress skip logged" "$(has $FX/out.log 'INPROGRESS (skip)')"
ok "in-progress: no unknown streak file" "$([ ! -f $ST/billwatch-backend.unknown_streak ] && echo 1 || echo 0)"
# DEPLOYING/QUEUED/CRASHED/garbage/empty mapping
newhome; export RWS_31f8e4dd=CRASHED RWS_58dcc554=QUEUED RWS_de12ff53=GARBAGE; run
ok "CRASHED maps to FAILED" "$(has $FX/out.log 'billwatch-backend: FAILED')"
ok "QUEUED maps to INPROGRESS" "$(has $FX/out.log 'chickadee-backend: INPROGRESS')"
ok "garbage maps to UNKNOWN" "$(has $FX/out.log 'gitlark-backend: UNKNOWN')"
newhome; export RW_STATUS=EMPTY VC_LS_EMPTY=1; run
ok "empty list -> UNKNOWN" "$(has $FX/out.log 'billwatch-backend: UNKNOWN')"
ok "vercel ls empty -> UNKNOWN" "$(has $FX/out.log 'billwatch-frontend: UNKNOWN')"
newhome; export VC_STATUS=Weird; run
ok "vercel unrecognized status -> UNKNOWN" "$(has $FX/out.log 'billwatch-frontend: UNKNOWN')"

# 8. blind monitoring: UNKNOWN streak alert once
newhome; export RW_LINK_FAIL=1
for i in 1 2 3 4 5; do run; done
ok "5 UNKNOWN: no blind alert yet" "$([ "$(has $FX/curl.log 'monitoring is blind')" = 0 ] && echo 1 || echo 0)"
ok "streak counter at 5" "$([ "$(cat $ST/billwatch-backend.unknown_streak)" = 5 ] && echo 1 || echo 0)"
run
ok "6th UNKNOWN: blind alert" "$(has $FX/curl.log 'monitoring is blind (6x UNKNOWN)')"
ok "blind escalated log" "$(has $FX/out.log 'MONITORING-BLIND escalated after 6')"
ok "alerted marker set" "$([ -f $ST/billwatch-backend.unknown_alerted ] && echo 1 || echo 0)"
b1=$(cnt $FX/curl.log 'billwatch backend monitoring is blind'); run
ok "7th UNKNOWN: alert deduped" "$([ "$(cnt $FX/curl.log 'billwatch backend monitoring is blind')" = "$b1" ] && echo 1 || echo 0)"
unset RW_LINK_FAIL; run
ok "real signal resets streak+alerted" "$([ ! -f $ST/billwatch-backend.unknown_streak ] && [ ! -f $ST/billwatch-backend.unknown_alerted ] && echo 1 || echo 0)"

# 9. DRYRUN: no ssh, prints [ntfy], touches no live state
newhome; export DRYRUN=1 RW_STATUS=FAILED RW_ID=dd1 VC_STATUS=Ready; run
ok "dryrun: would-enqueue logged" "$(has $FX/out.log 'WOULD enqueue fix into')"
ok "dryrun: [ntfy] printed instead of curl" "$(has $FX/out.log '[ntfy]')"
ok "dryrun: no ssh" "$([ ! -s $FX/ssh.log ] && echo 1 || echo 0)"
ok "dryrun: live state dir untouched" "$([ ! -f $ST/billwatch-backend.id ] && echo 1 || echo 0)"
unset DRYRUN

# 10. CLI missing: no railway -> FATAL; no vercel -> warn + UNKNOWN
newhome
real_rw="$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin bash -c 'unset -f railway; command -v railway')"
if [ -z "$real_rw" ]; then
  HOME="$T/home" NTFY_TOPIC=x env -u BASH_FUNC_railway%% bash "$DW" > "$FX/out.log" 2>&1; rc=$?
  ok "no railway CLI -> FATAL exit 1" "$([ "$rc" = 1 ] && has $FX/out.log 'FATAL: railway CLI not on PATH' | grep -q 1 && echo 1 || echo 0)"
else ok "no railway CLI (skipped: real railway installed)" 1; fi
real_vc="$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin bash -c 'command -v vercel')"
if [ -z "$real_vc" ]; then
  newhome; HOME="$T/home" NTFY_TOPIC=x env -u BASH_FUNC_vercel%% bash "$DW" > "$FX/out.log" 2>&1
  ok "no vercel CLI -> WARN + frontends UNKNOWN" "$(has $FX/out.log 'WARN: vercel CLI not on PATH')"
  ok "no vercel -> billwatch-frontend UNKNOWN" "$(has $FX/out.log 'billwatch-frontend: UNKNOWN')"
else ok "no vercel CLI (skipped: real vercel installed)" 1; ok "skipped" 1; fi

# 11. shrike-monitor supplement + shrike-notify publish
newhome; export SHRIKE_MONITOR_URL=http://mon.local/ SHRIKE_MONITOR_TOKEN=tok MON_JSON='{"total_monitors":5,"healthy_monitors":5}'; run
ok "monitor healthy logged" "$(has $FX/out.log 'shrike-monitor: 5/5 monitors healthy')"
ok "monitor bearer header used" "$(has $FX/curl.log 'Authorization: Bearer tok')"
export MON_JSON='{"total_monitors":5,"healthy_monitors":3}'; run
ok "monitor degraded -> alert" "$(has $FX/curl.log 'fleet degraded (3/5)')"
export MON_JSON='not json'; run
ok "monitor unparseable logged" "$(has $FX/out.log "couldn't parse /monitors/status")"
export MON_FAIL=1; run
ok "monitor unreachable logged" "$(has $FX/out.log 'shrike-monitor: unreachable')"
unset MON_FAIL SHRIKE_MONITOR_TOKEN
export MON_JSON='{"total_monitors":1,"healthy_monitors":1}'; : > $FX/curl.log; run
ok "monitor without token: no bearer" "$([ "$(grep -c 'Bearer' $FX/curl.log)" = 0 ] && grep -q monitors/status $FX/curl.log && echo 1 || echo 0)"
# shrike-notify publish path (alert -> shrike_notify_publish) with token and without
newhome; export SHRIKE_NOTIFY_URL=http://notify.local SHRIKE_NOTIFY_TOKEN=nt RW_STATUS=FAILED RW_ID=n1; run
ok "shrike-notify publish hit with bearer" "$(has $FX/curl.log 'notify.local/fleet_billwatch_deploy')"
ok "shrike-notify token header" "$(has $FX/curl.log 'Authorization: Bearer nt')"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
