#!/usr/bin/env bash
# ovn_prework.sh — the 27B does the LEGWORK on a Claude-bound task so Claude spends minimal tokens.
# For a task it can't fully land itself, the 27B produces a briefing: which files matter, the current
# state, a concrete approach, and a best-effort DRAFT (diff/pseudocode). Stored in prework/<slug>.md.
# When Claude picks the task up, it reads the briefing first instead of exploring the repo from zero.
#
# 2026-09-07 (Sept-14 token-offload prep). Uses the model directly via LiteLLM (a research/writing
# task). Every task that CAN have prework should have it — done by the 27B, reviewed by Claude.
#
# Usage: ovn_prework.sh <repo_basename> "<task text>"   (or reads prework/queue.tsv: <repo>\t<task>)
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
source scripts/lib_worktree.sh
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVN_MODEL:-qwen-dflash-27B}"
mkdir -p prework logs
LOG="logs/ovn_prework.log"; say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

# 2026-09-21: respect a manual/GPU-testing pause — this script hits the local LLM directly
# (real GPU contention) and had no pause check, so `queue.sh pause` before a dedicated GPU
# session did NOT actually stop this from firing on its own cron.
if [ -f state/PAUSED ]; then
  say "queue is paused (state/PAUSED exists) — skipping this run entirely"
  exit 0
fi

do_one(){
  local repo="$1" task="$2"
  local base_rd="repos/$repo"; [ -d "$base_rd" ] || { say "$repo: no clone"; return 1; }
  # Phase 2 (2026-09-25): read from an isolated worktree snapshot instead of the live,
  # continuously-mutating clone. This cron-driven pass (fixed cadence) and the fleet's own
  # loop touching the same repos/<name> checkout concurrently is exactly the read-while-write
  # collision the phased hardening plan's Phase 2 targets - named explicitly alongside
  # ovn_recover_parked.sh (migrated 2026-09-21), which hit this exact collision twice in one
  # night before that fix. This script never commits/pushes into the target repo (read-only
  # context-gathering for a prework briefing), so only wt_open/wt_close are needed, not wt_push.
  local rd; rd="$(wt_open "$base_rd" overnight/feature)"
  local using_wt=1
  if [ -z "$rd" ]; then
    say "$repo: worktree open failed — falling back to the live clone for this pass"
    rd="$base_rd"; using_wt=0
  fi
  local slug; slug="$(printf '%s' "$task" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | cut -c1-50 | sed 's/-$//')"
  local out="prework/${repo}-${slug}.md"

  # gather likely-relevant files: explicit paths in the task + keyword grep, capped
  local paths kws files
  paths="$(printf '%s' "$task" | grep -oE '[A-Za-z0-9_./-]+\.(py|ts|tsx|vue|gd|md|json|yaml|yml)' | sort -u)"
  kws="$(printf '%s' "$task" | tr 'A-Z' 'a-z' | grep -oE '[a-z_]{5,}' | sort -u | grep -vE '^(the|and|that|with|from|this|should|which|there)$' | head -6 | paste -sd'|' -)"
  files="$( { printf '%s\n' $paths; [ -n "$kws" ] && grep -rliE "$kws" "$rd" --include='*.py' --include='*.ts' --include='*.tsx' --include='*.vue' --include='*.gd' --exclude-dir=.venv --exclude-dir=node_modules --exclude-dir=.godot --exclude-dir=__pycache__ 2>/dev/null | sed "s#^$rd/##" | head -8; } | sort -u | head -8)"

  # build the context blob (capped per file so we stay well under the window)
  local ctx=""; for f in $files; do
    [ -f "$rd/$f" ] || continue
    ctx="$ctx
### $f
$(head -c 2500 "$rd/$f")
"
  done
  [ -z "$ctx" ] && ctx="(no files auto-located — layout only)
$(cd "$rd" && find . -maxdepth 3 \( -name '*.py' -o -name '*.ts' -o -name '*.vue' -o -name '*.gd' \) -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sed 's#^\./##' | head -40)"

  local prompt="You prepare a briefing for a senior engineer (Claude) who will FINISH a task. Do the legwork so they don't explore the repo from scratch. Be concrete and concise.

REPO: $repo
TASK: $task

Relevant code (excerpts):
$ctx

Write a markdown briefing with EXACTLY these sections:
## Relevant files
- one line per file that matters, and why
## Current state
- what exists now that bears on this task (functions, patterns, gaps)
## Approach
- concrete, numbered steps to do the task
## Draft
- a best-effort diff or pseudocode for the core change (the engineer will refine; getting it 70% right saves them the most time)
## Risks / unknowns
- anything you're unsure about that the engineer must decide"

  # 2026-09-23 FIX: $ctx above is built from `head -c 2500` byte-slices of arbitrary
  # source files - the same raw-byte-cut hazard already root-caused and fixed in
  # run_overnight.sh's progress-tail generation on 2026-09-19 (ovn_progress_slice.py's
  # errors='ignore' decode). Here it was NOT fixed: sys.stdin.read() decodes with the
  # strict default codec, so a cut landing mid-multi-byte-sequence (confirmed live:
  # 938 UnicodeDecodeError crashes in this log, ~1699 total failed attempts) aborted
  # this python one-liner entirely, leaving $body empty and every such task silently
  # skipped forever ("model returned too little (0 chars)") every time it was retried.
  # Read raw bytes and decode leniently instead, exactly matching the proven fix.
  local body; body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':sys.stdin.buffer.read().decode('utf-8','ignore')}],'temperature':0.3,'max_tokens':1500}))" <<<"$prompt")"
  local _raw; _raw="$(curl -fsS --max-time 200 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_KEY" -d "$body" 2>>"$LOG")"
  local resp; resp="$(printf '%s' "$_raw" | jq -r '.choices[0].message.content // empty' 2>>"$LOG")"
  # 2026-09-16: this call's real token spend was discarded entirely - log it.
  bash "$HOME/overnight-queue/scripts/ovn_log_tokens.sh" prework "$repo" \
    "$(printf '%s' "$_raw" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)" \
    "$(printf '%s' "$_raw" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)" 2>/dev/null || true
  if [ "${#resp}" -lt 200 ]; then
    say "$repo/$slug: model returned too little (${#resp} chars) — skip"
    [ "$using_wt" = 1 ] && wt_close "$base_rd" "$rd"
    return 1
  fi
  {
    echo "# Prework: $task"
    echo "_Repo: $repo · generated by the 27B $(date '+%F %T') · REVIEW — a starting point, not gospel._"
    echo ""
    echo "$resp"
  } > "$out"
  say "$repo/$slug: wrote $out (${#resp} chars)"
  [ "$using_wt" = 1 ] && wt_close "$base_rd" "$rd"
  echo "$out"
}

if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
  do_one "$1" "$2"
elif [ -f prework/queue.tsv ]; then
  # process up to MAX per run and CONSUME the lines, so cycle-end works through the queue over time
  MAX="${OVN_PREWORK_MAX:-2}"; done=0
  tmp="prework/queue.tsv.$$"; : > "$tmp"
  while IFS=$'\t' read -r repo task; do
    if [ -n "$repo" ] && [ -n "$task" ] && [ "$done" -lt "$MAX" ]; then
      do_one "$repo" "$task" && done=$((done+1)) || printf '%s\t%s\n' "$repo" "$task" >> "$tmp"
    else
      [ -n "$repo" ] && printf '%s\t%s\n' "$repo" "$task" >> "$tmp"   # leftover for next run
    fi
  done < prework/queue.tsv
  mv "$tmp" prework/queue.tsv
  say "prework pass: generated $done briefing(s); $(grep -c . prework/queue.tsv 2>/dev/null || echo 0) left in queue"
else
  echo "usage: ovn_prework.sh <repo> \"<task>\"   (or populate prework/queue.tsv)"; exit 1
fi
