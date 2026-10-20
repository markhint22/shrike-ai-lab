#!/usr/bin/env bash
# 2026-10-19: a merge silently dropped two L2 changes from the research lane and fleet review (the SHARED checkout path
# and the success heartbeat), and no test noticed. This pins them, and pins the auth classifier against false outages
# from ordinary model prose (a long reply that mentions 'oauth' or '401' is NOT an authentication failure).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; QUEUE="$HERE/../.."
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
source "$HERE/lib_safe_tmp.sh" || { echo "cannot source lib_safe_tmp.sh" >&2; exit 2; }
T="$(safe_mktemp_dir l2guard)" || exit 1
cleanup(){ safe_rm_rf "$T"; }
trap cleanup EXIT
source "$QUEUE/ovn_claude_auth.sh"

echo "== L2 changes survive (merge-regression guard)"
ok "research lane derives SHARED from its own checkout (L2), not a hard-coded path" "grep -q 'SHARED=\"\${SHARED_DIR:-\$(cd \"\$(dirname \"\${BASH_SOURCE\[0\]}\")/../..\" && pwd)}\"' '$QUEUE/ovn_auto_research.sh'"
ok "research lane writes its success heartbeat (hb/ovn-auto-research)" "grep -q 'hb/ovn-auto-research' '$QUEUE/ovn_auto_research.sh'"
ok "fleet review writes its success heartbeat (hb/fleet-review), only when not killed by the cap" "grep -q 'hb/fleet-review' '$QUEUE/ops/fleet_review/run_review.sh' && grep -q 'killed:-.*hb/fleet-review\|\[ -z \"\${killed:-}\" \]' '$QUEUE/ops/fleet_review/run_review.sh'"

echo "== classifier: the real outage is caught, model prose is not"
printf 'Not logged in · Please run /login\n' > "$T/login.txt"
ok "the captured CLI login message is an auth failure" "ovn_claude_is_auth_failure '$T/login.txt'"
{ printf 'Here is my analysis. The OAuth flow in the module is well structured, and the 401 handling\n'; head -c 1500 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$T/prose.txt"
ok "a long reply that mentions OAuth and 401 is NOT an auth failure" "! ovn_claude_is_auth_failure '$T/prose.txt'"
printf 'Error: rate limited, try again later\n' > "$T/other.txt"
ok "an ordinary error is NOT an auth failure" "! ovn_claude_is_auth_failure '$T/other.txt'"

echo "== mutants (each must flip a check above)"
# text-only: a mutant is checked by reading the mutated text, never by running the lane (that would spend a probe and alert)
mut(){ sed "$1" "$QUEUE/$2" > "$T/m.sh"; if cmp -s "$QUEUE/$2" "$T/m.sh"; then echo "  MUTANT-NOT-APPLIED $3"; F=$((F+1)); return; fi
  if grep -q "$4" "$T/m.sh"; then echo "  MUTANT-SURVIVED $3"; F=$((F+1)); else echo "  ok   mutant caught: $3"; P=$((P+1)); fi }
mut 's/hb\/ovn-auto-research/hb\/REMOVED/' ovn_auto_research.sh "heartbeat line removed" "hb/ovn-auto-research"
mut 's/SHARED="\${SHARED_DIR:-\$(cd .*$/SHARED="${SHARED_DIR:-$HOME\/LocalProjects\/shared}"/' ovn_auto_research.sh "SHARED path reverted to hard-coded" "dirname"
echo "l2_guard: $P passed, $F failed"
[ "$F" -eq 0 ]
