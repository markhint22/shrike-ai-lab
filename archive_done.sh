#!/usr/bin/env bash
# Archive completed [x] items out of each repo's OVERNIGHT_PROGRESS.md (into OVERNIGHT_DONE.md),
# hold-safe, committed + pushed. Keeps the read-only progress file small so it doesn't blow the
# model's input limit (xlite hit 63K > 55K -> ContextWindowExceeded -> could never work).
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
for r in "$@"; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || { echo "$r: no progress file"; continue; }
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  if ! ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ); then
    echo "$r: sync failed"; ./queue.sh release "$r" >/dev/null 2>&1; continue
  fi
  before=$(wc -l < "$f")
  out=$(python3 archive_done.py "$f" "repos/$r/OVERNIGHT_DONE.md" 2>&1)
  moved=$(echo "$out" | grep -oE 'MOVED=[0-9]+' | cut -d= -f2); moved=${moved:-0}
  if [ "$moved" -gt 0 ]; then
    ( cd "repos/$r"
      git add OVERNIGHT_PROGRESS.md OVERNIGHT_DONE.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): archive $moved completed items out of OVERNIGHT_PROGRESS.md (keep fed context small)"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && echo "$r: archived $moved done items ($before -> $(wc -l < "$f") lines)" || echo "$r: push failed"
  else
    echo "$r: nothing to archive ($before lines)"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
