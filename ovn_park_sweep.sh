#!/usr/bin/env bash
# ovn_park_sweep.sh — autonomous, $0 relocation of parked items out of the active scout flow.
#
# See ovn_park_sweep.py for the full "why". Short version: AUTO-SKIP/HUMAN-ONLY-tagged items
# are still `- [ ] ` (open) lines, and the scout+implement loop's model reads the file top-down
# and treats the first open line as gospel — it does NOT mechanically skip parked lines itself.
# As items above a parked line get completed, it naturally drifts to the front and then burns a
# full model call every single cycle correctly reporting "BLOCKED" before ever reaching real
# work. Runs this for every active repo, hold-safe, committed + pushed to overnight/feature.
# NO repo survey, NO LLM — pure text relocation, same shape as queue_refill.sh.
#
# Cron (server): 15 */2 * * * cd ~/overnight-queue && ./ovn_park_sweep.sh >> logs/ovn_park_sweep.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
log(){ echo "$(date '+%F %T') $*"; }

repos="${*:-}"
if [ -z "$repos" ]; then
  repos="$(jq -r 'map(select((.enabled != false) and (.type=="aider_fix"))) | .[].repo // empty' tasks.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)"
fi

for r in $repos; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"
  [ -f "$f" ] || { log "$r: no progress file, skipping"; continue; }
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  if ! ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ); then
    log "$r: git sync failed — skipping"; ./queue.sh release "$r" >/dev/null 2>&1 || true; continue
  fi
  out=$(python3 ovn_park_sweep.py "$f" 2>&1)
  moved=$(echo "$out" | grep -oE 'SWEPT=[0-9]+' | cut -d= -f2); moved=${moved:-0}
  if [ "$moved" -gt 0 ]; then
    ( cd "repos/$r"
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): sweep $moved parked (AUTO-SKIP/HUMAN-ONLY) item(s) out of the active flow"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && log "$r: swept $moved parked item(s)" || log "$r: sweep push FAILED"
  else
    log "$r: nothing to sweep"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
log "ovn_park_sweep pass complete"
