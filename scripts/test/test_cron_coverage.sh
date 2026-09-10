#!/usr/bin/env bash
# Tests that every fleet-managed repo (persistent_branch aider_fix tasks in tasks.json) is
# covered by BOTH branch_hygiene.sh cron lines: the default (overnight/feature -> develop) one
# and a HYGIENE_FEATURE_BRANCH=claude/feature one.
#
# Written 2026-09-09 after a real incident: shrike-notify and shrike-monitor's claude/feature
# branches sat unmerged (+9/+15 commits) with NO review flag at all, because they were simply
# never listed in either claude/feature hygiene cron line (the hourly one only had gitlark/
# iptv_apps/test-automation-agent/xlite; the 3h one only had billwatch/shrike-labs-website).
# This is a config-coverage gap, not a gate failure, so nothing else catches it — hence a
# dedicated test. Only runs where a live crontab is available (server-only, like the other
# live-infra tests in this suite); skips cleanly elsewhere.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
TASKS="$OQ/tasks.json"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

command -v crontab >/dev/null 2>&1 || { echo "  SKIP: no crontab on this host"; exit 0; }
[ -f "$TASKS" ] || { echo "  SKIP: $TASKS not found"; exit 0; }

CRONTAB="$(crontab -l 2>/dev/null)"
[ -n "$CRONTAB" ] || { echo "  SKIP: crontab -l returned nothing (no user crontab installed)"; exit 0; }

# Ground truth: repos the fleet actually maintains a persistent overnight/feature branch for.
REPOS="$(python3 -c "
import json
d = json.load(open('$TASKS'))
for t in d:
    if t.get('type') == 'aider_fix' and t.get('persistent_branch') and t.get('enabled', True):
        print(t['repo'].rstrip('/').split('/')[-1])
")"
[ -n "$REPOS" ] || { echo "  SKIP: no persistent_branch aider_fix tasks found in $TASKS"; exit 0; }

# hygiene lines targeting develop, split by whether they set HYGIENE_FEATURE_BRANCH=claude/feature
DEFAULT_LINES="$(printf '%s\n' "$CRONTAB" | grep 'branch_hygiene\.sh' | grep 'HYGIENE_MERGE_TARGET=develop' | grep -v 'HYGIENE_FEATURE_BRANCH=claude')"
CLAUDE_LINES="$(printf '%s\n' "$CRONTAB" | grep 'branch_hygiene\.sh' | grep 'HYGIENE_FEATURE_BRANCH=claude/feature')"

ok "at least one overnight/feature hygiene cron line exists" "[ -n \"\$DEFAULT_LINES\" ]"
ok "at least one claude/feature hygiene cron line exists"    "[ -n \"\$CLAUDE_LINES\" ]"

while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  ok "$repo: covered by an overnight/feature hygiene cron line" \
     "printf '%s' \"\$DEFAULT_LINES\" | grep -q 'repos/$repo\\b'"
  ok "$repo: covered by a claude/feature hygiene cron line" \
     "printf '%s' \"\$CLAUDE_LINES\" | grep -q 'repos/$repo\\b'"
done <<< "$REPOS"

echo "Cron repo-coverage: $P passed, $F failed"
[ "$F" -eq 0 ]
