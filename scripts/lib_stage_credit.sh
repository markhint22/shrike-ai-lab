#!/usr/bin/env bash
# Stage-run credit ledger (2026-10-15). A higher-tier stage run is credited as "pushed(tests:pass) stage(higher-tier)" when its
# stage_runs summary reports commits_pushed>0. The summary is read from the NEWEST stage_runs jsonl, so when a later cycle produces no new
# stage jsonl the same old summary is read again and the same run gets credited again (2026-10-14 night: two items each credited 19-27
# times, 2-4 s "pushes", zero new commits). ovn_stage_credit_claim makes each stage run creditable exactly once.
#
# usage: ovn_stage_credit_claim <stage-jsonl-path> <ledger-file>
#   rc 0 = not yet credited; the path is recorded in the ledger, so the caller may credit.
#   rc 1 = already credited (or no path / no ledger given); the caller must NOT credit.
ovn_stage_credit_claim(){
  local jl="${1:-}" ledger="${2:-}"
  [ -n "$jl" ] && [ -n "$ledger" ] || return 1
  if [ -f "$ledger" ] && grep -qxF -- "$jl" "$ledger" 2>/dev/null; then return 1; fi
  mkdir -p "$(dirname "$ledger")" 2>/dev/null || return 1
  printf '%s\n' "$jl" >> "$ledger" 2>/dev/null || return 1
  # keep the ledger bounded; the newest 2000 claims are enough to catch a re-read of the newest summary
  if [ "$(wc -l < "$ledger" 2>/dev/null | tr -d ' ')" -gt 4000 ] 2>/dev/null; then
    tail -n 2000 "$ledger" > "$ledger.tmp.$$" 2>/dev/null && mv -f "$ledger.tmp.$$" "$ledger" 2>/dev/null
    rm -f "$ledger.tmp.$$" 2>/dev/null
  fi
  return 0
}
