#!/bin/bash
# ===========================================
# Shrike AI Lab - Backlog Grooming (#2, 2026-08-25)
# ===========================================
# A daily "re-evaluate reality and fix the backlog" pass. For each active repo it
# compares the current OVERNIGHT_PROGRESS.md Next Steps against the repo's ACTUAL
# state (file inventory, recent commits) and produces a grooming PROPOSAL:
# remove done/stale items, split oversized ones, reprioritize quick wins first,
# add high-value new items. Would have pre-empted gitlark's delete-timeout loop
# and test-auto's oversized item.
#
# SAFETY: proposal-mode by default. An LLM silently rewriting a human-curated
# backlog is risky, so this WRITES a proposal (reports/grooming-<repo>-<date>.md)
# and the supervisor surfaces "N grooming proposals ready" to your phone. Review,
# then apply. The DETERMINISTIC half (an item to delete a file that is already
# gone) is always surfaced because it is objective.
# Uses the local model (LiteLLM) — $0. Prefers Claude if ANTHROPIC_API_KEY set.
#
# Usage:  ./groom.sh                # groom all active aider_fix repos
# Cron:   0 4 * * *  cd ~/overnight-queue && ./groom.sh >> logs/groom.log 2>&1
# ===========================================
set -uo pipefail

DIR="${OVERNIGHT_DIR:-$HOME/overnight-queue}"
STATE="$DIR/state"; REPORT_DIR="$DIR/reports"; TASKS="$DIR/tasks.json"
LITELLM_BASE="${LITELLM_BASE:-http://localhost:4000}"
LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVERNIGHT_MODEL:-qwen-dflash-27B}"
DATE="$(date +%Y%m%d)"
mkdir -p "$STATE" "$REPORT_DIR"

if ! curl -sf --max-time 8 "$LITELLM_BASE/health/liveliness" >/dev/null 2>&1; then
  echo "groom: LiteLLM unreachable — skipping"; exit 0
fi

count=0
for id in $(jq -r '.[] | select((.enabled // true) == true and ((.type // "aider_fix") == "aider_fix")) | .id' "$TASKS" 2>/dev/null); do
  repo="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.repo' "$TASKS")"
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  doc="$repo/OVERNIGHT_PROGRESS.md"
  [ -f "$doc" ] || continue

  next="$(sed -n '/## Next Steps/,/## /p' "$doc" | grep -E '^[0-9]+\.|^- \[' | head -30)"
  [ -z "$next" ] && continue
  recent="$(git -C "$repo" log -8 --format='%s' origin/overnight/feature 2>/dev/null)"
  tree="$(cd "$repo" && git ls-files 2>/dev/null | grep -vE 'node_modules|\.venv|addons/gut' | head -70)"

  # deterministic: "delete/remove <file>" items whose target is already gone
  stale="$(echo "$next" | grep -iE 'delete|remove' | while IFS= read -r line; do
    f="$(echo "$line" | grep -oE '[A-Za-z0-9_./-]+\.(py|ts|js|jsx|tsx|vue|gd)' | head -1)"
    [ -n "$f" ] && [ ! -e "$repo/$f" ] && echo "$line"
  done)"

  prompt="You are grooming an autonomous coding queue's backlog for the repo '$name'. Compare its current Next Steps to its real state and propose an improved list: drop items already done or referencing deleted files; SPLIT any item too large for one ~15-minute coding session; reprioritize so quick, high-value wins come first; add up to 3 genuinely useful new items grounded in the file inventory. Output ONLY a numbered list, one item per line, nothing else.

Current Next Steps:
$next

Recent commits:
$recent

File inventory (partial):
$tree"

  payload="$(jq -n --arg m "$MODEL" --arg p "$prompt" '{model:$m,messages:[{role:"user",content:$p}],max_tokens:800,temperature:0.2}')"
  proposal="$(curl -sf --max-time 300 -H "Authorization: Bearer $LITELLM_KEY" -H "Content-Type: application/json" -d "$payload" "$LITELLM_BASE/v1/chat/completions" 2>/dev/null | jq -r '.choices[0].message.content // ""')"
  [ -z "$proposal" ] && { echo "groom: $name — no proposal (model returned nothing)"; continue; }

  rpt="$REPORT_DIR/grooming-${name}-${DATE}.md"
  {
    echo "# Grooming proposal — ${name} — $(date '+%Y-%m-%d %H:%M')"
    echo
    if [ -n "$stale" ]; then echo "## Deterministically stale (target file already gone — safe to drop)"; echo '```'; echo "$stale"; echo '```'; echo; fi
    echo "## Current Next Steps"; echo '```'; echo "$next"; echo '```'; echo
    echo "## Proposed (LLM re-evaluation — review before applying)"; echo "$proposal"
  } > "$rpt"
  count=$((count + 1))
  echo "groom: $name -> $(basename "$rpt")$([ -n "$stale" ] && echo ' (+stale)')"
done

echo "$count" > "$STATE/grooming_pending"
echo "grooming complete: $count proposal(s) for $DATE"
