#!/usr/bin/env bash
# ovn_log_tokens.sh — append one token-spend entry to the shared cross-pipeline ledger.
#
# WHY: run_overnight.sh's main task loop already tracks every aider_fix/train_job cycle's
# tokens into state/outcomes.jsonl (parsed from aider's own "Tokens: X sent, Y received"
# log lines). But five OTHER scripts make their own direct LiteLLM calls outside that loop -
# ovn_recover_parked.sh (item recovery/decomposition), groom.sh (backlog grooming),
# ovn_planner.sh (roadmap decomposition, runs HOURLY), ovn_prework.sh (Claude-bound
# briefings), and supervisor.sh's local-27B review pass - and every one of them piped the
# curl response straight into `jq -r '.choices[0].message.content'`, discarding the
# response's own `.usage` field entirely. That token spend was never lost by the model
# server, just never surfaced anywhere in this pipeline's accounting (2026-09-16 audit).
#
# Usage: ovn_log_tokens.sh <source> <repo-or-context> <tokens_sent> <tokens_recv>
set -uo pipefail
DIR="${OVERNIGHT_DIR:-$HOME/overnight-queue}"
STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null || exit 0
src="${1:-unknown}"; repo="${2:--}"; sent="${3:-0}"; recv="${4:-0}"
case "$sent" in ''|null) sent=0 ;; esac
case "$recv" in ''|null) recv=0 ;; esac
printf '{"ts":"%s","source":"%s","repo":"%s","tokens_sent":%s,"tokens_recv":%s}\n' \
  "$(date -u +%FT%TZ)" "$src" "$repo" "$sent" "$recv" >> "$STATE/token_ledger.jsonl" 2>/dev/null || true
