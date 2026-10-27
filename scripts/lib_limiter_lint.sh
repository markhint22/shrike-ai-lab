#!/usr/bin/env bash
# scripts/lib_limiter_lint.sh - per-cycle hook of ovn_limiter_order_lint.py (P6a, 2026-10-27). SOURCE it, then:
#   limiter_lint_gate <repo> <before_sha> <after_sha> [item_id]    -> rc 0 = fine / shadow / off / lint unavailable; rc 1 = enforce AND a touched file has a limiter ABOVE a route decorator
# Lints ONLY the .py files the cycle's commit range touched. OVN_LIMITER_LINT=off|shadow|enforce (default shadow): shadow appends the findings to state/limiter_lint.log (OVN_LIMITER_LINT_LOG)
# and writes ONE alerts.log line (OVN_LIMITER_LINT_ALERTS); it never changes the return code, so it can never revert a commit. Findings are also echoed on stdout for the task log.
# Fail-open: a missing/crashing linter, a missing repo or bad shas = rc 0 (a lint must never block a cycle by being broken). OVN_LIMITER_LINT_PY overrides the linter path (tests).
_LL_HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
limiter_lint_gate() {
  local repo="${1:-}" before="${2:-}" after="${3:-}" id="${4:-lint}" mode py out rc log alog
  mode="$(printf '%s' "${OVN_LIMITER_LINT:-shadow}" | tr 'A-Z' 'a-z')"
  case "$mode" in off) return 0;; shadow|enforce) ;; *) mode=shadow;; esac
  py="${OVN_LIMITER_LINT_PY:-$_LL_HERE/ovn_limiter_order_lint.py}"
  [ -f "$py" ] && [ -n "$repo" ] && [ -n "$before" ] || return 0
  out="$(python3 "$py" diff --repo "$repo" --before "$before" ${after:+--after "$after"} 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] || return 0                       # 0 = clean, 2/other = usage or crash: fail-open
  [ -n "$out" ] || return 0
  printf '%s\n' "$out"
  log="${OVN_LIMITER_LINT_LOG:-${STATE_DIR:-.}/limiter_lint.log}"; alog="${OVN_LIMITER_LINT_ALERTS:-${ALERTS_FILE:-${STATE_DIR:-.}/alerts.log}}"
  { printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id" "$mode" "$(printf '%s' "$out" | head -3 | tr '\n' '|' | cut -c1-400)"; } >> "$log" 2>/dev/null || true
  printf '[%s] warn | %s | limiter-order lint (%s): %d finding(s), a limiter decorator sits ABOVE a route decorator so the limit is never enforced: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$id" "$mode" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "$(printf '%s' "$out" | head -1 | cut -c1-140)" >> "$alog" 2>/dev/null || true
  [ "$mode" = enforce ] && return 1
  return 0
}
