#!/usr/bin/env bash
# One-shot recovery: strip the wrong "<repo>/" path prefix from open items already sitting
# in each repo's OVERNIGHT_PROGRESS.md (injected before the bug was fixed), hold-safe,
# committed + pushed to overnight/feature. Makes in-flight items loadable/workable.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
for r in "$@"; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || { echo "$r: no progress file"; continue; }
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) || { echo "$r: sync failed"; ./queue.sh release "$r" >/dev/null 2>&1; continue; }
  out=$(python3 strip_repo_prefix.py "$r" "$f" 2>&1)
  n=$(echo "$out" | grep -oE 'STRIPPED=[0-9]+' | cut -d= -f2); n=${n:-0}
  if [ "$n" -gt 0 ]; then
    ( cd "repos/$r" && git add OVERNIGHT_PROGRESS.md && git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "fix(queue): strip wrong '$r/' path prefix from $n in-flight items" && (git push -q origin overnight/feature || (git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature)) ) && echo "$r: fixed $n in-flight items" || echo "$r: push failed"
  else
    echo "$r: no prefixed items (clean)"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
