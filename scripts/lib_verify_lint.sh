#!/usr/bin/env bash
# scripts/lib_verify_lint.sh - shell front end of ovn_verify_shape_lint.py (package D1, 2026-10-18). SOURCE it or run it:
#   lib_verify_lint.sh audit <repo_root|file>... [--tree DIR] [--all] [--json F] [--md F]   classify every open item's VERIFY (OK / UNSATISFIABLE / VACUOUS / UNRUNNABLE + reason + rewrite)
#   lib_verify_lint.sh check '<verify clause>' [--tree DIR]                                  one clause, JSON
#   verify_lint_filter <repo> <tree> [dropped_file]                                          stdin item lines -> stdout per OVN_VERIFY_LINT (off|shadow|enforce, default shadow)
# Mode: OVN_VERIFY_LINT=off|shadow|enforce (default shadow: findings go to state/verify_shape_lint.log + one alerts.log line per run, items are never changed;
#       enforce: a mechanically fixable VERIFY is rewritten at creation, anything else is dropped to the quarantine file).
_VL_PY="${OVN_VERIFY_LINT_PY:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/ovn_verify_shape_lint.py}"
verify_lint_filter(){ # <repo> <tree> [dropped_file]
  local repo="${1:-}" tree="${2:-}" dropped="${3:-}"
  [ "${OVN_VERIFY_LINT:-shadow}" = off ] && { cat; return 0; }
  # stdin is buffered in a variable: python consumes it, so a bare `|| cat` fallback would read nothing and silently lose every item. Fail-open = echo the ORIGINAL items back.
  local buf out rc
  buf="$(cat; printf x)"; buf="${buf%x}"
  out="$(printf '%s' "$buf" | python3 "$_VL_PY" filter ${tree:+--tree "$tree"} --repo "$repo" ${dropped:+--dropped "$dropped"}; printf 'RC%d' "$?")"
  rc="${out##*RC}"; out="${out%RC*}"
  if [ "$rc" = 0 ]; then printf '%s' "$out"; else echo "verify_lint_filter: python filter failed (rc=$rc); passing items through unchanged" >&2; printf '%s' "$buf"; fi
}
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  [ $# -ge 1 ] || { sed -n 2,8p "$0"; exit 2; }
  exec python3 "$_VL_PY" "$@"
fi
