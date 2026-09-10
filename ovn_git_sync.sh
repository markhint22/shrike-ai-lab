#!/usr/bin/env bash
# Auto-commit + push the overnight-queue directory itself to shrike-ai-lab
# (branch: overnight-live). Established 2026-09-10 after discovering the git
# history had rotted since 2026-08-25 - scripts kept evolving on the server
# but nobody was manually syncing them back into shrike-ai-lab anymore.
# Runs on a cron; a no-op commit attempt is expected and harmless most cycles.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
git add -A
git diff --cached --quiet && exit 0   # nothing changed this cycle
git commit -q -m "auto-sync $(date "+%F %T")"
git push -q origin overnight-live
