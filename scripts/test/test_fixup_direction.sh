#!/usr/bin/env bash
# Tier-2 fix-up direction: model-added failing test => fix the test; previously-green test broken by the model's source edit => fix the SOURCE.
Q="$(cd "$(dirname "$0")/../.." && pwd)"
. "$Q/scripts/lib_fixup.sh"
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
ok "no new tests => source-broke-green" "$([ "$(ovn_fixup_kind 'FAILED tests/test_old.py::test_a - assert 1 == 2' '')" = source-broke-green ] && echo 1 || echo 0)"
ok "failure names the NEW test file => own-test" "$([ "$(ovn_fixup_kind 'FAILED tests/test_new.py::test_b - AssertionError' $'backend/tests/test_new.py')" = own-test ] && echo 1 || echo 0)"
ok "new tests exist but the failure names an OLD test => source-broke-green" "$([ "$(ovn_fixup_kind 'FAILED tests/test_old.py::test_a' $'backend/tests/test_new.py')" = source-broke-green ] && echo 1 || echo 0)"
ok "several new tests, one named in the failure => own-test" "$([ "$(ovn_fixup_kind 'x FAIL src/b.spec.ts > y' $'src/a.spec.ts\nsrc/b.spec.ts')" = own-test ] && echo 1 || echo 0)"
ok "empty summary => source-broke-green (never crashes)" "$([ "$(ovn_fixup_kind '' $'a/test_x.py')" = source-broke-green ] && echo 1 || echo 0)"
ok "own-test direction tells the model to fix the TEST" "$(ovn_fixup_direction own-test | grep -q 'prefer fixing the TEST' && echo 1 || echo 0)"
ok "source-broke-green direction tells the model to fix the SOURCE change and restore old behaviour" "$(ovn_fixup_direction source-broke-green | grep -q 'Fix the SOURCE change' && ovn_fixup_direction source-broke-green | grep -q 'restore the old behaviour' && echo 1 || echo 0)"
ok "unknown kind defaults to the source direction" "$(ovn_fixup_direction nonsense | grep -q 'Fix the SOURCE change' && echo 1 || echo 0)"
ok "no direction text says 'your change' or 'you just added' (a fresh session has no memory of one; 2026-10-02 is_prime contamination)" "$({ ovn_fixup_direction own-test; ovn_fixup_direction source-broke-green; } | grep -qiE 'your change|you just added' && echo 0 || echo 1)"
ok "no direction text says 'your change' (the fresh session has no memory of one; 2026-10-02 is_prime contamination)" "$(! { ovn_fixup_direction own-test; ovn_fixup_direction source-broke-green; } | grep -qi 'your change\|you just added' && echo 1 || echo 0)"
ok "run_overnight.sh builds the prompt from the cause-aware direction, not the hard-coded sentence" "$(grep -q '\${_fixup_dir}' "$Q/run_overnight.sh" && ! grep -q 'reply with a udiff only. Prefer fixing the TEST' "$Q/run_overnight.sh" && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
