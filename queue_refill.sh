#!/usr/bin/env bash
# queue_refill.sh — autonomous, $0 queue top-up from the pre-decomposed backlog.
#
# For each active repo whose doable count has dropped below MIN_DOABLE, pull items from
# backlog/<repo>.md into the repo's OVERNIGHT_PROGRESS.md (hold-safe, committed + pushed to
# overnight/feature so the next cycle sees them). NO repo survey, NO LLM. The only ntfy this
# sends is when a repo is low AND its backlog is dry — the single signal that a human/Claude
# must replenish the long-term plan. As long as backlogs have depth, queues self-refill.
#
# This runs both on its own hourly cron AND at the end of every fleet cycle (~20-40min), so a
# persistently-dry repo used to re-alert every single cycle with zero dedup — dozens/day of
# noise for a fact that doesn't change cycle to cycle. Per-repo state/qr_dry_<repo> markers
# (same pattern as queue_health.sh's qh_bad_<name>) cut this to: one alert when a repo newly
# goes dry, silence while it stays dry, one reminder per DRY_REMIND_HOURS, one quiet recovery
# note when it's refilled again.
#
# Cron (server): 30 * * * * cd ~/overnight-queue && MIN_DOABLE=15 ./queue_refill.sh >> logs/queue_refill.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
MIN_DOABLE="${MIN_DOABLE:-15}"      # refill trigger
ADD_TO="${ADD_TO:-28}"             # refill target (pull up to this many doable)
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
DRY_REMIND_HOURS="${DRY_REMIND_HOURS:-24}"
DRY_REMIND_SECS=$(( DRY_REMIND_HOURS * 3600 ))
log(){ echo "$(date '+%F %T') $*"; }

repos="${*:-}"
if [ -z "$repos" ]; then
  repos="$(jq -r 'map(select((.enabled != false) and (.type=="aider_fix"))) | .[].repo // empty' tasks.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)"
fi

doable(){ # $1=repo -> doable count (open [ ] minus parked)
  local f="repos/$1/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || { echo 0; return; }
  local open parked
  open=$(grep -cE '^- \[ \] ' "$f" 2>/dev/null); open=${open:-0}   # NO `|| echo 0` — grep -c prints 0 itself; that fallback doubled it -> "0\n0" -> integer errors
  parked=$(grep -E '^- \[ \] ' "$f" 2>/dev/null | grep -cE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED|^\- \[ \] \[CLAUDE\]')  # grep -c already prints 0 on no-match; no `|| echo 0` (that doubled it -> "0\n0" -> integer errors)
  # [CLAUDE]-tagged lines are open but NOT 27B-doable (queue_refill.py header: only
  # [T1..T5] items are pulled) - without this, a repo whose live queue is entirely
  # [CLAUDE] escalation notes reads as healthy/doable and refill never fires, even
  # with a deep backlog waiting. Found live 2026-09-24: xlite had 20 [CLAUDE] items
  # and ZERO real [T1-5] items, yet logged "N doable (ok, no refill)" every cron
  # tick while 175 real backlog items sat unpulled.
  echo $(( open - parked ))
}

FORCE_PULL="${FORCE_PULL:-0}"   # if >0, pull this many per repo regardless of current doable (one-time priority injection)
dry=""; newly_dry=""; reminder_dry=""; recovered=""
now=$(date +%s)
for r in $repos; do
  d=$(doable "$r"); bl="backlog/$r.md"; marker="$STATE_DIR/qr_dry_$r"
  if [ "$FORCE_PULL" -eq 0 ] && [ "$d" -ge "$MIN_DOABLE" ]; then
    log "$r: $d doable (ok, no refill)"
    [ -f "$marker" ] && { rm -f "$marker"; recovered="$recovered $r"; }
    continue
  fi
  avail=0; [ -f "$bl" ] && avail=$(grep -cE '^- \[ \] \[T[1-5]\]' "$bl" 2>/dev/null)  # no `|| echo 0`: grep -c prints 0 itself; the [ -f ] guard covers a missing file
  if [ "$avail" -eq 0 ]; then
    # ROADMAP-AWARE dry check (2026-09-28): backlog/<repo>.md being at 0 right now does NOT
    # mean this repo is actually stuck — ovn_planner.sh replenishes backlog/<repo>.md from a
    # [ready] roadmap/<repo>.md feature on its own cadence (hourly cron + inline at cycle-end,
    # see run_overnight.sh's roadmap-refill note), and a repo whose backlog naturally drains
    # faster than that cadence (confirmed live: shrike-monitor/test-automation-agent/
    # shrike-notify sit at 0/184, 0/237, 1/169 conforming backlog lines far more often than a
    # repo like gitlark, which currently has 17/217) used to register as "backlog DRY" every
    # single time it dipped to 0, indistinguishable from a repo that is GENUINELY out of both
    # backlog AND roadmap fuel. That false-equivalence is exactly what correlated these 3
    # specific repos with the ones ovn_fleet_health.sh flagged as starved — the escalating
    # dry-marker/reminder treatment (and everything downstream that trusts it) fired for a
    # transient, self-resolving gap the same way it fires for a genuine dead end. Check
    # roadmap/<repo>.md for a [ready] feature (same selector ovn_planner.sh itself uses)
    # before committing to "dry": if one exists, the planner will refill this repo's backlog
    # soon on its own — log it distinctly and do NOT set/escalate the dry marker (clearing it
    # if a previous genuine-dry episode had set it, since "has fuel again" is a real recovery).
    # Only the true "nothing left anywhere" case (no roadmap fuel either) gets the escalating
    # dry treatment queue_refill.sh's marker/reminder machinery exists for.
    if [ -f "roadmap/$r.md" ] && grep -qE '^- \[ \] \[P[1-4]\] \[ready\]' "roadmap/$r.md" 2>/dev/null; then
      log "$r: $d doable — backlog empty but roadmap has a [ready] feature (planner will refill; not marking dry)"
      [ -f "$marker" ] && { rm -f "$marker"; recovered="$recovered $r"; }
      continue
    fi
    log "$r: $d doable — backlog DRY (roadmap also has no [ready] feature)"
    if [ "$FORCE_PULL" -eq 0 ]; then
      dry="$dry $r"
      if [ ! -f "$marker" ]; then
        echo "$now" > "$marker"; newly_dry="$newly_dry $r"
      elif [ $(( now - $(cat "$marker" 2>/dev/null || echo "$now") )) -ge "$DRY_REMIND_SECS" ]; then
        echo "$now" > "$marker"; reminder_dry="$reminder_dry $r"
      fi
    fi
    continue
  fi
  [ -f "$marker" ] && { rm -f "$marker"; recovered="$recovered $r"; }
  if [ "$FORCE_PULL" -gt 0 ]; then need=$FORCE_PULL; else need=$(( ADD_TO - d )); fi
  [ "$need" -lt 1 ] && need=1; [ "$need" -gt "$avail" ] && need=$avail
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  if ! ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ); then
    log "$r: git sync failed — skipping"; ./queue.sh release "$r" >/dev/null 2>&1 || true; continue
  fi
  out=$(python3 queue_refill.py "repos/$r/OVERNIGHT_PROGRESS.md" "$bl" "$need" 2>&1)
  moved=$(echo "$out" | grep -oE 'REFILL=[0-9]+' | cut -d= -f2); moved=${moved:-0}
  credited=$(echo "$out" | grep -oE 'CREDITED=[0-9]+' | cut -d= -f2); credited=${credited:-0}
  remain=$(echo "$out" | grep -oE 'BACKLOG_REMAINING=[0-9]+' | cut -d= -f2)
  # 2026-09-10: a pre-check credit (queue_refill.py's already_satisfied()) writes to
  # OVERNIGHT_DONE.md even when NOTHING gets pulled into the active queue (moved=0) — the old
  # `if moved -gt 0` guard would have skipped committing that, so the credited items would just
  # get silently reverted by the next cycle's `git reset --hard origin/...` above. Commit on
  # EITHER moved or credited, and stage both files.
  if [ "$moved" -gt 0 ] || [ "$credited" -gt 0 ]; then
    ( cd "repos/$r"
      # 2026-09-30: `git add A B` is all-or-nothing - a missing OVERNIGHT_DONE.md aborted the whole add, nothing was committed, yet "refilled +N" was logged
      git add OVERNIGHT_PROGRESS.md 2>/dev/null; [ -f OVERNIGHT_DONE.md ] && git add OVERNIGHT_DONE.md 2>/dev/null
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): auto-refill $moved items from backlog, pre-verify-credited $credited (doable was $d)"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && log "$r: refilled +$moved, credited +$credited already-satisfied (was $d, backlog now $remain)" || log "$r: refill push FAILED"
  else
    log "$r: nothing moved ($out)"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done

# 2026-09-28: newly_dry/reminder_dry used to each push their own "out of queued items" ntfy —
# one of FOUR scripts independently alerting on the same underlying "this repo is running out
# of work" fact (confirmed live: state/qr_dry_shrike-monitor and state/ovn_needs_research_
# shrike-monitor existed simultaneously for the same repo). ovn_fleet_health.sh is now the
# single canonical alerter for that fact (richest context, sensible daily cadence) — this still
# does its OWN detection + the qr_dry_<repo> marker bookkeeping (dedup/reminder timing), it just
# logs instead of pushing a redundant phone notification. The "recovered" note below is a
# DIFFERENT fact (repo unstuck, not out of work) that nothing else surfaces, so it still pushes.
if [ -n "$newly_dry" ]; then
  log "backlog-dry (new) — ntfy suppressed, see ovn_fleet_health.sh for the consolidated low-runway push, for:${newly_dry}"
fi
if [ -n "$reminder_dry" ]; then
  log "backlog-dry reminder — ntfy suppressed, see ovn_fleet_health.sh, unresolved:${reminder_dry}"
fi
if [ -n "$recovered" ]; then
  curl -fsS --max-time 8 -H "Title: Backlog refilled" -H "Tags: white_check_mark" -H "Priority: low" \
    -d "These repos have doable items again:${recovered}." \
    "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-recovered note sent for:${recovered}"
fi
[ -n "$dry" ] && [ -z "$newly_dry$reminder_dry" ] && log "still dry (no alert, within cooldown):${dry}"
log "queue_refill pass complete"
