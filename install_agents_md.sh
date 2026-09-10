#!/usr/bin/env bash
# Install staged AGENTS.md into each repo (hold-safe, commit+push to overnight/feature).
# Staged files: ~/overnight-queue/staging_agents/AGENTS_<repo>.md
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
STAGE="$HOME/overnight-queue/staging_agents"
for r in billwatch gitlark iptv_apps test-automation-agent shrike-notify shrike-monitor xlite; do
  src="$STAGE/AGENTS_${r}.md"
  [ -f "$src" ] || { echo "$r: no staged file"; continue; }
  ./queue.sh hold "$r" >/dev/null 2>&1 || true
  if ! ( cd "repos/$r" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ); then
    echo "$r: sync failed"; ./queue.sh release "$r" >/dev/null 2>&1; continue
  fi
  cp "$src" "repos/$r/AGENTS.md"
  lines=$(wc -l < "repos/$r/AGENTS.md")
  if ( cd "repos/$r" && git diff --quiet -- AGENTS.md ); then
    echo "$r: AGENTS.md unchanged ($lines lines)"
  else
    ( cd "repos/$r"
      git add AGENTS.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "docs(agents): tight AGENTS.md (<=150 lines) for the coding model (repo map + commands + conventions + gotchas)"
      git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
    ) && echo "$r: installed AGENTS.md ($lines lines)" || echo "$r: push failed"
  fi
  ./queue.sh release "$r" >/dev/null 2>&1 || true
done
