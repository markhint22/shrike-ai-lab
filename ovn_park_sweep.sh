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
# shellcheck source=scripts/lib_run_integrity.sh
# lib missing => ovn_ri_cycle_active undefined => the declare -F guards below keep the OLD behaviour
. "$HOME/overnight-queue/scripts/lib_run_integrity.sh" 2>/dev/null || true

repos="${*:-}"
if [ -z "$repos" ]; then
  repos="$(jq -r 'map(select((.enabled != false) and (.type=="aider_fix"))) | .[].repo // empty' tasks.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)"
fi

for r in $repos; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"
  [ -f "$f" ] || { log "$r: no progress file, skipping"; continue; }
  # 2026-10-03 (integrity A6): never reset a repo whose cycle is in flight - the `git reset --hard origin/overnight/feature` below discarded a commit that
  # was made but not yet pushed (xlite: "pushed" recorded for work origin never had). HOLD only stops a NEW cycle starting, so check the cycle marker /
  # stage runner first, then again after taking the hold (a cycle may have started in between). Skip-if-busy, never a blocking wait: the next pass retries.
  if declare -F ovn_ri_cycle_active >/dev/null 2>&1 && ovn_ri_cycle_active "$HOME/overnight-queue/state" "$r"; then
    log "$r: a cycle/stage runner is in flight - skipping this pass (will retry next run)"; continue
  fi
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  if declare -F ovn_ri_cycle_active >/dev/null 2>&1 && ovn_ri_cycle_active "$HOME/overnight-queue/state" "$r"; then
    log "$r: a cycle started while taking the hold - skipping this pass"; ./queue.sh release "$r" >/dev/null 2>&1 || true; continue
  fi
  if ! ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ); then
    log "$r: git sync failed — skipping"; ./queue.sh release "$r" >/dev/null 2>&1 || true; continue
  fi
  # first park items that can never land (hard-banned / context-overflowing target), then relocate parked items
  pk=$(python3 ovn_park_unworkable.py "$f" "repos/$r" 2>&1 | grep -oE 'PARKED=[0-9]+' | cut -d= -f2); pk=${pk:-0}
  [ "$pk" -gt 0 ] && log "$r: parked $pk unworkable item(s) (hard-banned / too large for the model context)"
  out=$(python3 ovn_park_sweep.py "$f" 2>&1)
  moved=$(echo "$out" | grep -oE 'SWEPT=[0-9]+' | cut -d= -f2); moved=${moved:-0}
  moved=$((moved + pk))
  if [ "$moved" -gt 0 ]; then
    ( cd "repos/$r"
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "chore(queue): sweep $moved parked (AUTO-SKIP/HUMAN-ONLY) item(s) out of the active flow"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && log "$r: swept $moved parked item(s)" || log "$r: sweep push FAILED"
  else
    log "$r: nothing to sweep"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
log "ovn_park_sweep pass complete"
