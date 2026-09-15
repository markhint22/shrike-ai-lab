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
#
# 2026-09-15 FIX: REMOVED the old "wait up to 15min for run_overnight's
# run.lock, else skip EVERY repo and retry tomorrow" gate. That was an
# all-or-nothing failure mode: one busy morning meant zero repos promoted
# for a full 24h, which is exactly backwards for a tool whose whole job is
# to stop drift from accumulating - a live incident (2026-09-15, iptv_apps
# stuck 2h+ on an unrelated hygiene conflict) showed this compounding risk
# directly. The lock was never actually protecting anything real:
# promote_to_prod.sh's own git mutations (merge/tag/push) already run in an
# isolated /tmp worktree, the identical pattern reconcile_branches.sh has
# used UNLOCKED every ~20 minutes for weeks with no corruption. develop's
# tip is ALSO always a complete, gated state - only branch_hygiene.sh and
# reconcile_branches.sh ever write to it, never the fleet's own mid-task
# work (that lives on overnight/feature/claude/feature) - so there was
# never a real "wait for the cycle to finish before promoting FROM this"
# reason in the first place. Each repo is still handled independently
# below (a gate failure or merge conflict on one repo still just lands in
# `blocked` and gets reported, it doesn't stop the others).
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
REPOS="${OVN_PROMOTE_REPOS:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-labs-website}"

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
