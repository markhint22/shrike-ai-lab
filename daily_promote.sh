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
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HOME/overnight-queue" || exit 1
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
REPOS="${OVN_PROMOTE_REPOS:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-labs-website}"

# shrike-notify dual-publish (no-op unless SHRIKE_NOTIFY_URL is configured — see
# shrike_notify_lib.sh for the topic taxonomy and env var docs).
# shellcheck source=./shrike_notify_lib.sh
[ -f "$DIR/shrike_notify_lib.sh" ] && source "$DIR/shrike_notify_lib.sh"

promoted=""; nothing=""; blocked=""; held=""; unverified=""; transient=""
# 2026-10-03: a hold whose reason is TRANSIENT (staging deploy of the candidate still BUILDING / staging BEHIND = hygiene merged into develop at :00, same minute as this
# job, and staging has not deployed it yet) is retried ONCE after OVN_PROMOTE_RETRY_S (default 600; 0 = no retry). The first pass defers the alerts.log WARN + relay
# note for such holds (OVN_PROMOTE_DEFER_NOTE=1), the retry pass writes them if the hold persists, so a 10-minute catch-up never pages or burns the once-per-candidate note.
RETRY_S="${OVN_PROMOTE_RETRY_S:-600}"
run_repo(){  # $1=repo $2=defer-note(0|1)
  local r="$1" out
  out="$(OVN_PROMOTE_DEFER_NOTE="$2" ./promote_to_prod.sh --yes "repos/$r" 2>&1)"
  # 2026-10-02: the "[candidate]" / "[staging-gate]" evidence lines promote_to_prod.sh prints are kept whole in this log (tail -6 would
  # cut them off) so the morning read shows which SHA was considered and what staging was serving.
  echo "===== $r ====="; echo "$out" | grep -vE 'setup agent|Tip:|^  \[(candidate|staging-gate|unverified|prod-alembic|prod-deploy|transient-hold)\]' | tail -6
  echo "$out" | grep -E '^  \[(candidate|staging-gate|unverified|prod-alembic|prod-deploy|transient-hold)\]'
  # 2026-10-03: promoted WITHOUT staging provenance (NA / unknown commit) is reported, never silent
  if echo "$out" | grep -q "PROMOTED" && echo "$out" | grep -q '^  \[unverified\]'; then unverified="$unverified $r"; fi
  if   echo "$out" | grep -q "PROMOTED";                 then promoted="$promoted $r"
  elif echo "$out" | grep -qiE "nothing to promote";     then nothing="$nothing $r"
  elif echo "$out" | grep -q "STAGING-GATE BLOCK";       then held="$held $r"
    echo "$out" | grep -q '^  \[transient-hold\]' && transient="$transient $r"
  else                                                        blocked="$blocked $r"; fi
}
_defer=0; [ "$RETRY_S" -gt 0 ] 2>/dev/null && _defer=1
for r in $REPOS; do
  [ -d "repos/$r" ] || continue
  run_repo "$r" "$_defer"
done
if [ "$_defer" -eq 1 ] && [ -n "$transient" ]; then
  echo "===== retry in ${RETRY_S}s: transient staging hold for:$transient ====="
  sleep "$RETRY_S"
  _retry="$transient"; transient=""
  for r in $_retry; do held=" $(echo " $held " | sed "s/ $r / /" | xargs)"; held="${held% }"; run_repo "$r" 0; done
fi

body="Daily prod promote $(date '+%a %H:%M')
Promoted:${promoted:- none}
No change:${nothing:- none}"
# 2026-09-28: a promote-BLOCKED repo (gate/conflict) is decision-needed — it stayed on its
# last-good build and needs a human look — so it gets "high", not the same "default" tier
# as a routine day where everything promoted cleanly or had nothing to do.
PROMOTE_PRIO="default"
if [ -n "$blocked" ]; then
  body="$body
⚠ BLOCKED (gate/conflict — stayed on last-good):$blocked"
  PROMOTE_PRIO="high"
fi
# 2026-10-03: staging gate enforces by default for repos with a staging backend (promote_gate.py); HELD = FAIL or stale/missing evidence.
# 2026-10-02: a repo held by the (enforced) staging-evidence gate stayed on its last-good build too; the other repos were promoted normally.
if [ -n "$held" ]; then
  body="$body
⚠ HELD (staging not serving the candidate — stayed on last-good):$held"
  PROMOTE_PRIO="high"
fi
if [ -n "$unverified" ]; then
  body="$body
UNVERIFIED (promoted without staging provenance):$unverified"
fi
curl -fsS --max-time 8 -H "Title: Daily prod promote" -H "Tags: rocket" -H "Priority: $PROMOTE_PRIO" -d "$body" "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
command -v shrike_notify_publish >/dev/null 2>&1 && shrike_notify_publish "fleet_queue_promote" "Daily prod promote" "rocket" "$body"
echo "$body"
