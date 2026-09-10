#!/usr/bin/env bash
# daily_promote.sh — batch the develop -> main (prod) promote to ONCE A DAY.
#
# Rationale: the fleet + Claude work land continuously in develop (via
# branch_hygiene). Promoting to main on every change means a prod deploy per
# change = constant deploy churn + failure alerts. This runs the gated
# develop->main promote for every repo once a day, so prod deploys are batched,
# predictable, and protected by the migration + smoke gates inside
# promote_to_prod.sh. A repo whose migration/smoke gate fails is simply skipped
# (stays on its last-good prod build) and surfaced in the ntfy summary.
#
# Cron (server): 0 9 * * *  cd ~/overnight-queue && ./daily_promote.sh >> logs/daily_promote.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
REPOS="${OVN_PROMOTE_REPOS:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-labs-website}"

# Take run_overnight's lock and WAIT for the running cycle to finish (short) before promoting —
# never interrupt a cycle mid-git. Give up after 15min so the daily tick can't hang forever.
# 2026-09-07. (Does NOT call reconcile_branches itself - that runs on its own 10,30,50 * * * * cron; this comment previously claimed otherwise, corrected 2026-09-09.)
mkdir -p "$HOME/overnight-queue/state"
exec 203>"$HOME/overnight-queue/state/run.lock"
if ! flock -w 900 203; then
  echo "daily_promote: run_overnight busy >15min — skipping today's promote; will retry tomorrow."
  curl -fsS --max-time 8 -H "Title: Daily promote skipped (loop busy)" -H "Tags: information_source" -d "run_overnight held the lock >15min at 9am — promote deferred to the next run." "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  exit 0
fi

promoted=""; nothing=""; blocked=""
for r in $REPOS; do
  [ -d "repos/$r" ] || continue
  out="$(./promote_to_prod.sh --yes "repos/$r" 2>&1)"
  echo "===== $r ====="; echo "$out" | grep -vE 'setup agent|Tip:' | tail -6
  if   echo "$out" | grep -q "PROMOTED";                 then promoted="$promoted $r"
  elif echo "$out" | grep -qiE "nothing to promote";     then nothing="$nothing $r"
  else                                                        blocked="$blocked $r"; fi
done

body="Daily prod promote $(date '+%a %H:%M')
Promoted:${promoted:- none}
No change:${nothing:- none}"
[ -n "$blocked" ] && body="$body
⚠ BLOCKED (gate/conflict — stayed on last-good):$blocked"
curl -fsS --max-time 8 -H "Title: Daily prod promote" -H "Tags: rocket" -d "$body" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
echo "$body"
