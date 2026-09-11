#!/usr/bin/env bash
# ovn_queue_health_sweep.sh — periodic "is the active queue itself healthy" pass, established
# 2026-09-11 after billwatch/iptv_apps/gitlark/test-automation-agent/xlite each independently
# ended up with most or all of their active items parked (AUTO-SKIP) at once, and the existing
# ovn_recover_parked.sh cadence (1 item per repo per 2h cron) was far too slow to dig a repo back
# out once it happened - xlite sat at doable=0 for hours waiting on a cadence that would have
# taken most of a day to clear its 28 parked items one at a time.
#
# Two things, in order:
#   1. AUTO-FIX (safe): any repo currently at doable=0 gets several extra recovery passes right
#      now, via the existing, already git-safe ovn_recover_parked.sh - this script does nothing
#      new here, it just calls that harder when a repo is actually stuck.
#   2. AUTO-FIX: scan every repo's active (non-parked) items for (a) two items that are
#      effectively duplicates of each other (keep the first, drop the rest - same rule
#      dedupe_progress_headers.py already uses for duplicate bullets), and (b) an item whose own
#      VERIFY command already passes against current code (queue_refill.py's already_satisfied(),
#      reused as-is - checked off with the same "(pre-verified: VERIFY already passed against
#      current code)" note queue_refill.py's own pre-check uses, not reimplemented wording).
#      2026-09-11: this used to be report-only out of an over-applied caution - the hold+isolated-
#      clone care that's right for a SLOW, INTERACTIVE, multi-step Claude session doing manual
#      surgery is the wrong model for a FAST, single-purpose cron script; ovn_recover_parked.sh
#      and ovn_park_sweep.sh already commit+push directly to these same shared clones on their own
#      schedules with no hold, and report-only meant a found duplicate/already-done item would
#      just keep getting run by the fleet forever instead of actually stopping the waste. Uses
#      the exact commit+push-with-rebase-retry pattern those two scripts already use.
#
# Cron: 0 */4 * * *  cd ~/overnight-queue && ./ovn_queue_health_sweep.sh >> logs/ovn_queue_health_sweep.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_queue_health_sweep.log"; say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor}"
RECOVER_PASSES="${OVN_HEALTH_RECOVER_PASSES:-3}"

# ---- 1. unstick any repo currently sitting at doable=0 ----
for r in $REPOS; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || continue
  doable="$(grep -E '^- \[ \]' "$f" 2>/dev/null | grep -viE 'AUTO-SKIP|HUMAN-ONLY' | wc -l | tr -d ' ')"
  if [ "${doable:-0}" -eq 0 ]; then
    parked="$(grep -cE '^- \[ \] \[AUTO-SKIP' "$f" 2>/dev/null | tr -d ' ')"
    if [ "${parked:-0}" -gt 0 ]; then
      say "$r: doable=0 with ${parked} parked item(s) — pushing $RECOVER_PASSES extra recovery passes"
      for _ in $(seq 1 "$RECOVER_PASSES"); do ./ovn_recover_parked.sh "$r" >/dev/null 2>&1; done
    else
      say "$r: doable=0 and nothing parked either — genuinely out of work (roadmap/backlog needs attention, not recovery)"
    fi
  fi
done

# ---- 2. fix duplicates + already-satisfied items among what's still active ----
export REPOS
CHANGED="$(python3 - <<'PYEOF' 2>>"$LOG"
import os, re, sys
sys.path.insert(0, os.path.expanduser("~/overnight-queue"))
from queue_refill import already_satisfied

REPOS = os.environ["REPOS"].split()
BASE = os.path.expanduser("~/overnight-queue/repos")
ts = __import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def normalize(text):
    text = re.sub(r"\[[^\]]*\]", "", text)
    text = re.sub(r"VERIFY:.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r"[`*_]", "", text)
    return re.sub(r"\s+", " ", text).strip().lower()

for repo in REPOS:
    path = f"{BASE}/{repo}/OVERNIGHT_PROGRESS.md"
    if not os.path.exists(path):
        continue
    root = f"{BASE}/{repo}"
    lines = open(path).read().splitlines()

    seen = set()
    dupe_count = 0
    already_done_count = 0
    out = []
    for l in lines:
        if not l.lstrip().startswith("- [ ]"):
            out.append(l)
            continue
        key = normalize(l)
        if len(key) >= 15:
            if key in seen:
                dupe_count += 1
                continue  # drop this duplicate outright, keep the first occurrence
            seen.add(key)
        if "AUTO-SKIP" not in l and "HUMAN-ONLY" not in l and already_satisfied(l, root, timeout=10):
            already_done_count += 1
            l = l.replace("- [ ]", "- [x]", 1) + "  <!-- pre-verified: VERIFY already passed against current code -->"
        out.append(l)

    if dupe_count or already_done_count:
        open(path, "w").write("\n".join(out) + "\n")
        print(f"{ts} {repo}: removed {dupe_count} duplicate(s), credited {already_done_count} already-satisfied item(s)", file=sys.stderr)
        print(repo)
PYEOF
)"
echo "$CHANGED" | grep -v '^$' >> "$LOG" 2>/dev/null || true

for r in $CHANGED; do
  rd="repos/$r"
  ( cd "$rd" && git add OVERNIGHT_PROGRESS.md \
    && git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): dedupe + credit already-satisfied items (health sweep)" \
    && { git push -q origin overnight/feature 2>/dev/null \
         || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
  say "$r: dedupe/credit changes committed and pushed"
done

say "queue health sweep complete"
