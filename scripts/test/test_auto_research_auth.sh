#!/usr/bin/env bash
# 2026-10-19: an expired Claude login must NOT consume the research lane's daily failed-pass cap.
# Tests the SHIPPED classifier (ovn_claude_auth.sh) against the real captured CLI message, and proves the
# research lane's rc!=0 branch routes auth failures away from mark_fail (mutant-checked).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; QUEUE="$HERE/../.."; SCRIPT="$QUEUE/ovn_auto_research.sh"; AUTHLIB="$QUEUE/ovn_claude_auth.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
source "$HERE/lib_safe_tmp.sh" || { echo "cannot source lib_safe_tmp.sh" >&2; exit 2; }
T="$(safe_mktemp_dir aresauth)" || exit 1
cleanup(){ safe_rm_rf "$T"; }
trap cleanup EXIT
source "$AUTHLIB"

echo "== classifier (shipped ovn_claude_is_auth_failure)"
printf 'Not logged in · Please run /login\n' > "$T/login.txt"
ok "the real CLI login message is an AUTH failure" "ovn_claude_is_auth_failure '$T/login.txt'"
printf 'Error: rate limited, try again later\n' > "$T/other.txt"
ok "an ordinary error is NOT an AUTH failure (must still count)" "! ovn_claude_is_auth_failure '$T/other.txt'"
: > "$T/empty.txt"
ok "an empty file is NOT an AUTH failure" "! ovn_claude_is_auth_failure '$T/empty.txt'"
ok "missing files are NOT an AUTH failure" "! ovn_claude_is_auth_failure '$T/nope.txt'"

echo "== behaviour: the research lane's rc!=0 block, mark_fail stubbed to a counter"
# the block as shipped: from the 'if [ "$rc" -ne 0 ]' that tests the classifier, through its closing fi
block_of(){ awk '/if \[ "\$rc" -ne 0 \] && ovn_claude_is_auth_failure/{f=1} f{print} f&&/if \[ "\$rc" -ne 0 \]; then log .*mark_fail; continue; fi/{exit}' "$1"; }
run_block(){   # $1 = script, $2 = stderr sample, $3 = reply sample -> prints mark_fail call count
  local b="$T/block.sh"; block_of "$1" > "$b"
  [ -s "$b" ] || { echo "NOBLOCK"; return; }
  ( in="$T/in"; mkdir -p "$in"; cp "$2" "$in/claude_stderr.txt"; cp "$3" "$in/claude_reply.txt"
    rc=1; repo=r; fails=0; STATE="$T/state"; mkdir -p "$STATE"; mark_fail(){ fails=$((fails+1)); }; log(){ :; }; ar_fail_ok=1; SALVAGE_REPO=""; DRY_RUN=""; OVN_CLAUDE_AUTH_LAST=""; ovn_claude_auth_alert(){ return 0; }
    for _once in once; do source "$b"; done
    echo "$fails" )
}
printf 'Not logged in · Please run /login\n' > "$T/s_login.txt"; : > "$T/r_empty.txt"
printf 'Error: rate limited\n' > "$T/s_other.txt"
f1="$(run_block "$SCRIPT" "$T/s_login.txt" "$T/r_empty.txt")"
ok "shipped: an auth failure does NOT call mark_fail (got '$f1')" "[ '$f1' = 0 ]"
f2="$(run_block "$SCRIPT" "$T/s_other.txt" "$T/r_empty.txt")"
ok "shipped: an ordinary failure DOES call mark_fail once (got '$f2')" "[ '$f2' = 1 ]"

echo "== mutants (each must change the behaviour above)"
mutant_fails(){   # $1 = sed program on the script, $2 = label
  sed "$1" "$SCRIPT" > "$T/mut.sh"
  if cmp -s "$SCRIPT" "$T/mut.sh"; then echo "  MUTANT-NOT-APPLIED $2"; F=$((F+1)); return; fi
  local mf; mf="$(run_block "$T/mut.sh" "$T/s_login.txt" "$T/r_empty.txt")"
  if [ "$mf" = 0 ]; then echo "  MUTANT-SURVIVED $2"; F=$((F+1)); else echo "  ok   mutant caught: $2 (auth now calls mark_fail x$mf)"; P=$((P+1)); fi
}
mutant_fails 's/ && ovn_claude_is_auth_failure "\$in\/claude_stderr.txt" "\$in\/claude_reply.txt"; then/ \&\& false; then/' "classifier branch disabled"
echo "auto_research_auth: $P passed, $F failed"
[ "$F" -eq 0 ]
