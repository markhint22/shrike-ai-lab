#!/usr/bin/env bash
# Extra coverage for ovn_classify_fail.sh: every status shortcut and every log-signature branch.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
C=""
for c in "$HERE/../../ovn_classify_fail.sh" "$HERE/../ovn_classify_fail.sh" "$HOME/overnight-queue/ovn_classify_fail.sh"; do [ -f "$c" ] && { C="$c"; break; }; done
[ -n "$C" ] || { echo "SKIP: ovn_classify_fail.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got '$2' want '$3')"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mk(){ printf '%s\n' "$2" > "$tmp/$1.log"; }
cl(){ bash "$C" "$tmp/$1.log" "${2:-}"; }

mk plain "nothing interesting"
ok "missing log -> unknown" "$(bash "$C" "$tmp/nope.log" x)" unknown
ok "no args -> unknown" "$(bash "$C")" unknown
ok "status landed" "$(cl plain LANDED)" landed
ok "status done" "$(cl plain done)" landed
ok "status needs-decision" "$(cl plain needs-decision)" needs-decision
ok "status needs_decision" "$(cl plain needs_decision)" needs-decision
ok "status blocked" "$(cl plain blocked)" needs-decision
ok "status oversized" "$(cl plain oversized)" oversized
ok "status transient" "$(cl plain 'error-transient(x)')" model-api-error
ok "status skip(exhausted)" "$(cl plain 'skip(exhausted)')" queue-exhausted
ok "status build-break" "$(cl plain 'reverted(build-break)')" build-red
ok "status reverted-red" "$(cl plain 'reverted-red')" test-red
ok "status migration-fork" "$(cl plain 'reverted(migration-fork)')" migration-fork
ok "status ts-regression" "$(cl plain 'reverted(ts-regression)')" ts-regression
ok "status stage-unverified" "$(cl plain 'no-op(stage-unverified)')" stage-unverified

mk ctx "litellm ContextWindowExceededError happened"; ok ctx "$(cl ctx x)" context-exceeded
mk diff "SearchReplaceNoExactMatch for foo.py"; ok diff "$(cl diff x)" diff-not-applied
mk to "aider hard-killed after 900s"; ok to "$(cl to x)" timeout
mk api "AttributeError: module has no attribute foo"; ok api "$(cl api x)" api-mismatch
mk syn "SyntaxError: invalid syntax"; ok syn "$(cl syn x)" syntax-error
mk tr "FAILED tests/test_a.py::t"; ok tr "$(cl tr x)" test-red
mk br "npm run build exited with 1"; ok br "$(cl br x)" build-red
mk ne "Aider made no changes"; ok ne "$(cl ne x)" no-edit
mk po "the architect proposed a plan"; ok po "$(cl po x)" plan-only
mk pa "architect plan ... then wrote the file"; ok pa "$(cl pa x)" unknown
ok "fallthrough unknown" "$(cl plain x)" unknown

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
