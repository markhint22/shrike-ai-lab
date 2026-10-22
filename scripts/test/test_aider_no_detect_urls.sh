#!/usr/bin/env bash
# 2026-10-22 (PKG-C). aider's URL detection tried to `playwright install` a scraper when a failure text contained a URL (28 task logs). EVERY aider argument array the queue builds must carry --no-detect-urls:
# run_overnight.sh AIDER_BASE_ARGS (all fix-up/migration/build-fix/main calls use it), both ovn_stage_runner.sh aider calls, reconcile_branches.sh. Mutant: the flag removed from one site breaks the matching check.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
# every line that STARTS an aider invocation or arg array with --yes-always (comments and pgrep patterns excluded)
sites(){ grep -n -e '--yes-always' "$ROOT/$1" | grep -v -e 'pgrep' -e '^[0-9]*:[[:space:]]*#' | grep -v -e 'which aider (with'; }
for f in run_overnight.sh ovn_stage_runner.sh reconcile_branches.sh; do
  n="$(sites $f | wc -l | tr -d ' ')"; m="$(sites $f | grep -c -e '--no-detect-urls')"
  ok "$f: has aider --yes-always sites ($n)" "[ $n -ge 1 ]"
  ok "$f: every one ($n) carries --no-detect-urls ($m)" "[ $n = $m ]"
done
ok "run_overnight.sh: the aider calls use AIDER_BASE_ARGS (so the one array covers them)" "grep -c 'aider \"\${AIDER_BASE_ARGS\[@\]}\"' '$ROOT/run_overnight.sh' | grep -qvx 0"
ok "no other file under the queue tree launches aider with --yes-always" "[ \"\$(grep -rl -e '--yes-always' '$ROOT' --include='*.sh' --include='*.py' 2>/dev/null | grep -v -e '/scripts/test/' -e 'run_overnight.sh' -e 'ovn_stage_runner.sh' -e 'reconcile_branches.sh' | wc -l | tr -d ' ')\" = 0 ]"
# mutant: strip the flag from the reconcile site -> the check above must fail
tmp="$(safe_mktemp_dir nodet)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT; sed 's/ --no-detect-urls//' "$ROOT/reconcile_branches.sh" > "$tmp/r.sh"
n="$(grep -v -e '^[0-9]*:[[:space:]]*#' <(grep -n -e '--yes-always' "$tmp/r.sh") | wc -l | tr -d ' ')"; m="$(grep -c -e '--no-detect-urls' "$tmp/r.sh")"
nok "MUTANT flag removed from reconcile_branches.sh is detected" "[ $n = $m ]"
echo "no-detect-urls: pass=$P fail=$F"; [ "$F" = 0 ]
