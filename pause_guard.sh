#!/usr/bin/env bash
# Pause self-heal + guard. Runs every 15 min (cron).
#
# The fleet can get stuck if a deploy's `queue.sh pause` is never resumed (a
# session/ssh drop between pause and resume) — that idled the whole fleet ~10h once.
#
# Two pause kinds are distinguished so DELIBERATE pauses (e.g. pausing during an
# active chat) are NEVER auto-cleared:
#   - DEPLOY pause: the deploy marks it with state/deploy_pause. If it's older than
#     20 min (any deploy is minutes), it's forgotten -> auto-resume + notify.
#   - MANUAL pause (no deploy marker): left alone, but if it's been >90 min it may
#     be forgotten -> ALERT only (you decide), never auto-clear.
set -uo pipefail
STATE="$HOME/overnight-queue/state"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
P="$STATE/PAUSED"
alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true; }

# 2026-09-10 fix: clean the alert dedup flag HERE (before the early exit), not in dead code
# after it - the old `[ ! -f "$P" ] && rm -f pause_alerted` line at the bottom could never run,
# since every other path either still has $P set or already exited. Net effect: once a manual
# pause crossed the 90-min alert threshold, pause_alerted was never reset after it resolved, so
# a LATER, separate manual-pause episode that also crossed 90 min would silently never re-alert.
[ -f "$P" ] || { rm -f "$STATE/pause_alerted"; exit 0; }
age=$(( $(date +%s) - $(stat -c %Y "$P" 2>/dev/null || date +%s) ))

# STAGE pause: the higher-tier stage-sweep pauses the fleet for dedicated inference and clears its own
# pause via a trap; if the sweep was killed the pause could linger -> auto-clear a stale one (>45 min).
if [ -f "$STATE/stage_pause_since" ]; then
  sage=$(( $(date +%s) - $(cat "$STATE/stage_pause_since" 2>/dev/null || date +%s) ))
  if [ "$sage" -gt 2700 ]; then
    rm -f "$P" "$STATE/stage_pause_since"
    alert "Fleet auto-resumed (stale stage-pause)" "white_check_mark" "A stage-sweep pause lingered $((sage/60)) min (sweep likely died) — auto-cleared; fleet running again."
  fi
  exit 0
fi

if [ -f "$STATE/deploy_pause" ]; then
  if [ "$age" -gt 1200 ]; then           # deploy pause >20 min = forgotten -> self-heal
    "$HOME/overnight-queue/queue.sh" resume >/dev/null 2>&1
    rm -f "$STATE/deploy_pause"
    alert "Fleet auto-resumed (stale deploy-pause)" "white_check_mark" \
      "A deploy-pause was left set for $((age/60)) min (resume never ran). Auto-cleared it — the overnight fleet is running again."
  fi
  exit 0
fi

# manual pause (no deploy marker): alert once past 90 min, don't clear
if [ "$age" -gt 5400 ] && [ ! -f "$STATE/pause_alerted" ]; then
  touch "$STATE/pause_alerted"
  alert "Queue paused 90min+ (manual)" "warning" \
    "The overnight queue has been manually paused for $((age/60)) min. If that was unintended: ~/overnight-queue/queue.sh resume"
fi
