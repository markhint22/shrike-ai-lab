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
  parked=$(grep -E '^- \[ \] ' "$f" 2>/dev/null | grep -cE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED')  # grep -c already prints 0 on no-match; no `|| echo 0` (that doubled it -> "0\n0" -> integer errors)
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
    log "$r: $d doable — backlog DRY"
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
      git add OVERNIGHT_PROGRESS.md OVERNIGHT_DONE.md 2>/dev/null
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): auto-refill $moved items from backlog, pre-verify-credited $credited (doable was $d)"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && log "$r: refilled +$moved, credited +$credited already-satisfied (was $d, backlog now $remain)" || log "$r: refill push FAILED"
  else
    log "$r: nothing moved ($out)"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done

if [ -n "$newly_dry" ]; then
  curl -fsS --max-time 8 -H "Title: A few repos are out of queued items" -H "Tags: battery" \
    -d "These repos just ran out of doable items and their backlog is empty:${newly_dry}. Everything else keeps running — no rush. Whenever it's convenient, add items to backlog/<repo>.md or ask Claude to refill. (silent while still dry — a reminder repeats at most every ${DRY_REMIND_HOURS}h)" \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-dry alert (new) sent for:${newly_dry}"
fi
if [ -n "$reminder_dry" ]; then
  curl -fsS --max-time 8 -H "Title: Still out of queued items (reminder)" -H "Tags: battery" \
    -d "Still dry after ${DRY_REMIND_HOURS}h+, unresolved:${reminder_dry}. No rush — just a periodic nudge." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-dry reminder sent for:${reminder_dry}"
fi
if [ -n "$recovered" ]; then
  curl -fsS --max-time 8 -H "Title: Backlog refilled" -H "Tags: white_check_mark" \
    -d "These repos have doable items again:${recovered}." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-recovered note sent for:${recovered}"
fi
[ -n "$dry" ] && [ -z "$newly_dry$reminder_dry" ] && log "still dry (no alert, within cooldown):${dry}"
log "queue_refill pass complete"
