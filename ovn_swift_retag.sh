#!/usr/bin/env bash
# ovn_swift_retag.sh — tag doable items targeting a .swift file AUTO-SKIP, since no Linux fleet
# path can verify a Swift/iOS/tvOS build (see ovn_swift_retag.py's docstring for the full "why").
#
# Pure text relocation, same shape/safety pattern as ovn_filesize_retag.sh/ovn_park_sweep.sh: no
# LLM, hold-safe, committed + pushed to overnight/feature.
#
# Cron (server): 50 */4 * * * cd ~/overnight-queue && ./ovn_swift_retag.sh >> logs/ovn_swift_retag.log 2>&1
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
  out=$(python3 ovn_swift_retag.py "$f" 2>&1)
  retagged=$(echo "$out" | grep -oE 'RETAGGED=[0-9]+' | cut -d= -f2); retagged=${retagged:-0}
  if [ "$retagged" -gt 0 ]; then
    ( cd "repos/$r"
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): AUTO-SKIP $retagged swift item(s) — no Linux build-check path, route to Claude"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && log "$r: AUTO-SKIPped $retagged swift item(s)" || log "$r: retag push FAILED"
  else
    log "$r: nothing to retag"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
log "ovn_swift_retag pass complete"
