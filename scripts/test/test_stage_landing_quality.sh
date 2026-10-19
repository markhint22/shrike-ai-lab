#!/usr/bin/env bash
# 2026-10-18 landing audit: the staged runner's final QUALITY gate must reject changes that are green but not a real deliverable (scripts/ovn_landing_quality.py wired into
# full_verify): a tautological assertion, a discarded `_ = call()`, a function defined twice, a new private helper nothing but its test references. Runs the REAL
# ovn_stage_runner.sh end to end in the hermetic fake tree (lib_osr_fixture.sh). Every case has a control and the switch OVN_STAGE_LANDING_QUALITY=off|shadow|enforce.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
V(){ grep -qF -- "$1" <<<"$VL"; }
vl(){ VL="$(osr_vlog)"; }
LQ="$REALQ/scripts/ovn_landing_quality.py"
[ -f "$LQ" ] || { echo "  FAIL: $LQ missing"; exit 1; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
plan1='[{"desc":"module","files":["backend/app/zmod.py","backend/tests/test_zmod.py"],"verify":"t"}]'
# case <name> <source body (printf fmt)> <test body (printf fmt)>: a step that writes backend/app/zmod.py + backend/tests/test_zmod.py (the test imports the module, so the
# older 'does a changed test exercise the changed source' check is satisfied and only the NEW check can object)
mk(){ osr_new; osr_venv backend; cp "$LQ" "$Q/scripts/"; osr_plan default "$plan1"
  osr_aider 1 "mkdir -p backend/app backend/tests; printf '$1' > backend/app/zmod.py; printf '$2' > backend/tests/test_zmod.py"; }
GOOD_SRC='def qq():\n    return 1\n'
GOOD_TST='import zmod\n\ndef test_it():\n    assert zmod.qq() == 1\n'

echo "== control: a real change passes the new gate"
mk "$GOOD_SRC" "$GOOD_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "clean change => verified" G "independent full-verify: PASSED"
t "no landing-quality row" bash -c "! grep -q 'landing-quality' '$T/out.txt'"
osr_cleanup

echo "== TAUTOLOGY (billwatch test_legislators_refactor.py shape)"
# 2026-10-18: the DEFAULT enforced set is only DUP_DEF (TAUTOLOGY/DISCARDED_CALL had real false positives -> shadow). This e2e proves the MECHANISM of every rule, so it turns them on explicitly;
# the default-config behaviour has its own case below.
export OVN_LQ_RULES_ENFORCE=TAUTOLOGY,TAUTOLOGY_STATUS,DISCARDED_CALL,DUP_DEF
TAUT_TST='import zmod\n\ndef test_it():\n    assert zmod.qq() == 1\n\ndef test_cls():\n    assert zmod.qq() == 1 or True\n'
mk "$GOOD_SRC" "$TAUT_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "tautology => QUALITY FAIL row naming the rule and file" V "QUALITY FAIL: backend/tests/test_zmod.py: TAUTOLOGY"
t "=> unverified (never pushed as a landing)" G "independent full-verify: FAILED"
t "journal carries a landing_quality event in enforce mode" J '"event":"landing_quality"'
osr_cleanup
mk "$GOOD_SRC" "$TAUT_TST"; OVN_STAGE_LANDING_QUALITY=off osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "MUTANT OVN_STAGE_LANDING_QUALITY=off (the old behaviour): the same tautological change is VERIFIED" G "independent full-verify: PASSED"
osr_cleanup
mk "$GOOD_SRC" "$TAUT_TST"; OVN_STAGE_LANDING_QUALITY=shadow osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "shadow: still verified" G "independent full-verify: PASSED"
t "shadow: but the finding is journaled for measurement" J '"mode":"shadow"'
osr_cleanup
mk "$GOOD_SRC" "$TAUT_TST"; ( unset OVN_LQ_RULES_ENFORCE; osr_run "$OSR_REPO" "$ITEM_PY" ); vl
t "DEFAULT rules (only DUP_DEF enforced): the tautology is verified, never blocked" G "independent full-verify: PASSED"
osr_cleanup

echo "== DISCARDED_CALL (test-automation-agent test_runs.py shape)"
mk 'def is_ok(x):\n    return True\n\ndef qq():\n    _ = is_ok(1)\n    return 1\n' "$GOOD_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "'_ = is_ok(..)' (a pure predicate result thrown away) => QUALITY FAIL DISCARDED_CALL" V "QUALITY FAIL: backend/app/zmod.py: DISCARDED_CALL"
osr_cleanup
mk 'def qq():\n    _ = print(1)\n    return 1\n' "$GOOD_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "REPAIR: '_ = print(..)' (a side-effecting call) is NOT a discarded-call finding any more => verified" G "independent full-verify: PASSED"
osr_cleanup

echo "== TAUTOLOGY_STATUS (vacuous status_code list)"
mk "$GOOD_SRC" 'import zmod\n\ndef test_it():\n    assert zmod.qq() == 1\n\nclass R:\n    status_code = 200\n\ndef test_status():\n    assert R().status_code in [200, 401, 403]\n'; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "status_code in [200,401,403] => QUALITY FAIL TAUTOLOGY_STATUS" V "QUALITY FAIL: backend/tests/test_zmod.py: TAUTOLOGY_STATUS"
osr_cleanup

echo "== DUP_DEF (shrike-notify broker.py shape)"
mk 'class B:\n    def m(self):\n        return 1\n    def m(self):\n        return 2\n\ndef qq():\n    return B().m()\n' "$GOOD_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "method defined twice => QUALITY FAIL DUP_DEF" V "QUALITY FAIL: backend/app/zmod.py: DUP_DEF"
osr_cleanup

echo "== UNWIRED_HELPER (iptv engagement.py _to_utc shape)"
UNW_SRC='def _helper(x):\n    return x\n\ndef qq():\n    return 1\n'; UNW_TST='import zmod\n\ndef test_it():\n    assert zmod._helper(1) == 1\n    assert zmod.qq() == 1\n'
mk "$UNW_SRC" "$UNW_TST"; OVN_LQ_RULES_ENFORCE=TAUTOLOGY,UNWIRED_HELPER osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "OVN_LQ_RULES_ENFORCE listing UNWIRED_HELPER: private helper only its test uses => QUALITY FAIL UNWIRED_HELPER" V "QUALITY FAIL: backend/app/zmod.py: UNWIRED_HELPER"
osr_cleanup
mk "$UNW_SRC" "$UNW_TST"; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "DEFAULT (UNWIRED_HELPER is a shadow rule: 3 of its 4 replay hits were wired by the item's next landing) => still VERIFIED" G "independent full-verify: PASSED"
t "... and the shadow finding is journaled as landing_quality_shadow" J '"event":"landing_quality_shadow"'
NJ(){ ! osr_jsonl | grep -F '"event":"landing_quality"' >/dev/null; }
t "... never as an enforced landing_quality event" NJ
osr_cleanup
mk 'def _helper(x):\n    return x\n\ndef qq():\n    return _helper(1)\n' 'import zmod\n\ndef test_it():\n    assert zmod.qq() == 1\n'; osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "control: the same helper CALLED by production code in the same file is fine" G "independent full-verify: PASSED"
osr_cleanup

osr_summary
