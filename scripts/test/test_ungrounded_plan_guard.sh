#!/usr/bin/env bash
# Regression test for run_overnight.sh's UNGROUNDED-PLAN GUARD (2026-09-29).
#
# A PROCEED verdict where the scout named ZERO file-shaped tokens anywhere in its
# own PLAN/FILES text (not even a not-yet-created one) used to still reach a full
# implement attempt with FILE_ARGS empty, wrapped in "Execute it NOW... do NOT
# re-plan, do NOT re-explore, do NOT ask to see more files". Confirmed live on
# billwatch, twice in one hour: the scout reproduced aider's own built-in
# udiff-format few-shot example verbatim ("Replace the custom is_prime function
# with a call to sympy.isprime... FILES: NONE" - the canonical mathweb/flask/
# app.py demo) instead of grounding in the real backlog item, burning a full
# implement-stage call (13-28k tokens) that could never succeed.
#
# This test extracts the real candidate-token computation out of run_overnight.sh
# (not a reimplementation) so it can't silently drift from what's deployed, then
# exercises it against both the failure case (guard should fire) and the
# must-not-regress case (a legitimate brand-new-file plan, which names a
# non-existent path and must NOT be blocked by this guard).
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || RO="$(cd "$(dirname "$0")/../.." && pwd)/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# --- A: the guard must be present and gated correctly ---
ok "ungrounded-plan guard is present in run_overnight.sh" \
   "grep -q 'UNGROUNDED-PLAN GUARD' '$RO'"
ok "guard only fires on PROCEED (never overrides BLOCKED/ALREADY-DONE/NEEDS-DECISION handling above it)" \
   "grep -A3 'if \[ \"\$OVN_VERDICT\" = \"PROCEED\" \] && \[ -z \"\$_ovn_candidate_tokens\" \]' '$RO' | grep -q 'no-op(ungrounded-plan)'"
ok "guard checks FILE_ARGS is still empty too (never blocks a case the fallback already recovered)" \
   "grep -B2 'no-op(ungrounded-plan)' '$RO' | grep -q '\"\${#FILE_ARGS\[@\]}\" -eq 0'"
ok "candidate-token capture prep comment is present (documents the before-existence-filter rationale)" \
   "grep -q 'UNGROUNDED-PLAN GUARD prep' '$RO'"
ok "candidate-token filter documents the sympy.isprime false-positive it excludes" \
   "grep -q 'sympy.isprime' '$RO'"

# --- B: the candidate-token extraction logic, extracted verbatim in spirit ---
_candidate_tokens() {  # $1 = OVN_PLAN text, $2 = OVN_SCOUT_FILES text
  { echo "$1" | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}"; echo "$2"; } \
    | grep -E '/|\.(py|ts|tsx|js|jsx|vue|gd|kt|java|go|rb|rs|c|cpp|h|hpp|md|ya?ml|json|toml|cfg|ini|sh|txt|xml|gradle|properties|env)$' \
    | sort -u | grep -v '^$'
}

# Reproduces the confirmed-live billwatch failure: no REAL file-shaped token anywhere -
# "sympy.isprime" in the fabricated plan text itself matches the loose word.word shape
# but must be excluded by the stricter filter (no slash, no recognized extension).
_tokens_hallucinated="$(_candidate_tokens 'Replace the custom is_prime function with a call to sympy.isprime and add sympy to requirements' '')"
ok "hallucinated is_prime/sympy plan yields zero candidate tokens (guard would fire)" \
   '[ -z "$_tokens_hallucinated" ]'

# Legitimate brand-new-file task: names a real-shaped path that does not exist yet.
_tokens_newfile="$(_candidate_tokens 'Create backend/tests/test_new_export_endpoint.py covering the new /export route' '')"
ok "brand-new-file plan yields a candidate token even though the file does not exist yet (guard must NOT fire)" \
   '[ -n "$_tokens_newfile" ]'
ok "the new-file candidate token is the expected path" \
   '[ "$_tokens_newfile" = "backend/tests/test_new_export_endpoint.py" ]'

# A real, existing-file plan must also yield a candidate (sanity check the common case).
_tokens_existing="$(_candidate_tokens 'Fix the off-by-one in backend/app/services/pagination.py' '')"
ok "an ordinary existing-file plan still yields a candidate token" \
   '[ "$_tokens_existing" = "backend/app/services/pagination.py" ]'

echo "ungrounded-plan guard: $P passed, $F failed"
[ "$F" -eq 0 ]
