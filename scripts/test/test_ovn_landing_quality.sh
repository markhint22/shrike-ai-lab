#!/usr/bin/env bash
# 2026-10-18 landing audit: scripts/ovn_landing_quality.py must flag the four false-credit shapes found in the fleet's own landings (each one real, each green under the full suite)
# and stay silent on legitimate changes. Every positive is replayed from the live commit; every rule has a MUTANT (the rule disabled => the same input is no longer flagged).
#   TAUTOLOGY       billwatch  tests/test_legislators_refactor.py   `assert ...__module__ == "builtins" or True`
#   DISCARDED_CALL  test-automation-agent app/routers/test_runs.py  `_ = is_terminal_status(test_run.status.value)`   (also: a PRODUCTION module named test_*.py is source)
#   DUP_DEF         shrike-notify app/services/broker.py            two `async def topics_from_store` in one class
#   UNWIRED_HELPER  iptv engagement.py                              `_to_utc` used only by its own new test
#
# 2026-10-18 REPAIR (adversarial review of 43f36b1): decorated private functions / nested functions are not UNWIRED_HELPER; an unparsable BASE skips the structural rules; `_ = call()` only for provably
# pointless calls; vacuous `status_code in [200,401,403]` / `assert True or x` flagged; per-rule enforce/shadow split (OVN_LQ_RULES_ENFORCE). REAL-DATA REPLAY (scripts/ovn_lq_replay.py over
# origin/overnight/feature of iptv_apps, gitlark, billwatch, test-automation-agent, shrike-monitor, shrike-notify, xlite, last 10 days = 3159 commits, staged items replayed as one unit) is in the commit message.
set -uo pipefail
# all rules enforced for the rule-level cases below; the DEFAULT split is tested in its own section
export OVN_LQ_RULES_ENFORCE=TAUTOLOGY,TAUTOLOGY_STATUS,DISCARDED_CALL,DUP_DEF,UNWIRED_HELPER
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
LQ="$HERE/../ovn_landing_quality.py"; [ -f "$LQ" ] || LQ="$HERE/ovn_landing_quality.py"
[ -f "$LQ" ] || { echo "  FAIL: ovn_landing_quality.py not found"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
R="$T/r"
mkrepo(){ rm -rf "$R"; mkdir -p "$R/app/routers" "$R/tests"; git -C "$R" init -q -b main
  printf 'def pub():\n    return 1\n' > "$R/app/core.py"
  printf 'def old():\n    return 0\n' > "$R/app/routers/test_runs.py"
  printf 'def test_a():\n    assert pub() == 1\n' > "$R/tests/test_core.py"
  git -C "$R" add -A; git -C "$R" commit -q -m base; }
# commit <subject> <file> <content>  (content via printf format) ; then run the checker over base..HEAD
chg(){ mkdir -p "$(dirname "$R/$1")"; printf "$2" > "$R/$1"; }
run(){ git -C "$R" add -A; git -C "$R" commit -q -m c; python3 -I "${CHECKER:-$LQ}" check "$R" HEAD~1 HEAD 2>&1; }
hit(){ run | grep -q "^$1	"; }
none(){ [ -z "$(run)" ]; }

echo "== TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    assert x.__class__.__module__ == "builtins" or True  # sets\n'
ok "T1: 'assert ... or True' in a changed test is flagged (billwatch shape)" "hit TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    assert True\n'
ok "T2: bare 'assert True' is flagged" "hit TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    assert pub() == 1 or pub() == 2\n'
ok "T3: 'or' with a real operand is NOT flagged" "none"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    # assert x or True is what the old test did\n    assert pub() == 1\n'
ok "T4: a comment that mentions 'or True' is NOT flagged" "none"
mkrepo; chg app/core.py 'def pub():\n    return True or False\n'
ok "T5: 'or True' in PRODUCTION code is not this rule's business" "none"
mkrepo; mkdir -p "$R/tests"; printf 'extends GutTest\nfunc test_x():\n\tassert_true(true)\n' > "$R/tests/test_g.gd"
ok "T6: GDScript assert_true(true) is flagged" "hit TAUTOLOGY"

echo "== DISCARDED_CALL"
mkrepo; chg app/core.py 'def pub():\n    _ = is_ready(pub)\n    return 1\n'
ok "D1: '_ = call(...)' in production code is flagged" "hit DISCARDED_CALL"
mkrepo; chg app/routers/test_runs.py 'def old():\n    return 0\n\ndef start(r):\n    _ = is_terminal_status(r.status.value)\n    return 1\n'
ok "D2: a production module NAMED test_runs.py (under app/routers) is source, not a test (the live test-automation-agent miss)" "hit DISCARDED_CALL"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    _ = pub()\n    assert _ == 1\n'
ok "D3: '_ = call()' in a test file is not flagged" "none"
mkrepo; chg app/core.py 'def pub():\n    result = helper(pub)\n    return result\n'
ok "D4: a real assignment is not flagged" "none"

echo "== DUP_DEF"
mkrepo; chg app/core.py 'class Broker:\n    def topics(self):\n        return 1\n\n    async def topics_from_store(self):\n        return self.topics()\n\n    async def topics_from_store(self):\n        return 2\n'
ok "U1: the same method defined twice in a class is flagged (shrike-notify shape)" "hit DUP_DEF"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_a():\n    assert pub() == 1\n'
ok "U2: a duplicated test name in a test module is flagged (the first test silently never runs)" "hit DUP_DEF"
mkrepo; chg app/core.py 'class C:\n    @property\n    def v(self):\n        return 1\n\n    @v.setter\n    def v(self, x):\n        pass\n'
ok "U3: property getter+setter share a name legitimately: not flagged" "none"
mkrepo; printf 'def dup():\n    return 1\n\ndef dup():\n    return 2\n' > "$R/app/core.py"; git -C "$R" add -A; git -C "$R" commit -q -m predup
chg app/core.py 'def dup():\n    return 1\n\ndef dup():\n    return 2\n\ndef extra():\n    return 3\n'
ok "U4: a duplicate that ALREADY existed at base is not re-flagged" "none"
mkrepo; chg app/core.py 'class A:\n    def m(self):\n        return 1\n\nclass B:\n    def m(self):\n        return 2\n'
ok "U5: the same method name in two different classes is fine" "none"

echo "== UNWIRED_HELPER"
mkrepo; chg app/routers/eng.py 'def _to_utc(dt):\n    return dt\n'; chg tests/test_eng.py 'from app.routers.eng import _to_utc\ndef test_u():\n    assert _to_utc(1) == 1\n'
ok "H1: a new private helper referenced only by its own test is flagged (iptv _to_utc)" "hit UNWIRED_HELPER"
mkrepo; chg app/routers/eng.py 'def _to_utc(dt):\n    return dt\n'; chg app/core.py 'from app.routers.eng import _to_utc\ndef pub():\n    return _to_utc(1)\n'
ok "H2: the same helper CALLED from production code is fine" "none"
mkrepo; chg app/routers/eng.py 'def to_utc(dt):\n    return dt\n'
ok "H3: a new PUBLIC helper nothing calls yet is not flagged (library/API surface; only private ones are)" "none"
mkrepo; chg app/routers/eng.py '# _to_utc is planned\ndef _to_utc(dt):\n    return dt\n'
ok "H4: a mention in a comment is not a caller" "hit UNWIRED_HELPER"
mkrepo; printf 'def _old_helper():\n    return 1\n' > "$R/app/core.py"; git -C "$R" add -A; git -C "$R" commit -q -m pre
chg app/core.py 'def _old_helper():\n    return 1\n\ndef pub():\n    return 2\n'
ok "H5: a private helper that already existed at base is not 'new'" "none"

echo "== TAUTOLOGY_STATUS / more tautologies"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(r):\n    assert r.status_code in [200, 401, 403]\n'
ok "T7: status_code in [200,401,403] (success AND error accepted) is flagged" "hit TAUTOLOGY_STATUS"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(r):\n    assert r.status_code in (200, 201, 204)\n'
ok "T8: status_code in (200,201,204) (all success) is NOT flagged" "none"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(r):\n    assert r.status_code in (401, 403, 404)\n'
ok "T9: status_code in (401,403,404) (all errors) is NOT flagged" "none"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(r):\n    assert r.status_code in (200, 404)\n'
ok "T9b: a two-member idempotency check (200 or 404) is NOT flagged" "none"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(x):\n    assert True or x\n'
ok "T10: 'assert True or x' is flagged" "hit TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(x):\n    assert (x or True), "msg"\n'
ok "T11: parenthesised 'x or True' with a message is flagged" "hit TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(x):\n    assert x or 1\n'
ok "T12: 'x or 1' is flagged" "hit TAUTOLOGY"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(x):\n    assert x or "fallback"\n'
ok "T13: 'x or \"fallback\"' (a string default) is NOT flagged (not provably vacuous: could be a real default)" "none"

echo "== DISCARDED_CALL narrowing"
mkrepo; chg app/core.py 'def pub():\n    _ = session.exec(stmt)\n    return 1\n'
ok "D5: '_ = session.exec(..)' (side-effecting) is NOT flagged" "none"
mkrepo; chg app/core.py 'import os\ndef pub():\n    _ = os.environ.get("X")\n    return 1\n'
ok "D6: '_ = os.environ.get(..)' is NOT flagged" "none"
mkrepo; chg app/core.py 'def pub():\n    _ = has_permission(user)\n    return 1\n'
ok "D7: a has_* predicate result thrown away IS flagged" "hit DISCARDED_CALL"
mkrepo; chg app/util.py 'def compute(x):\n    return len(str(x)) + 1\n'; git -C "$R" add -A; git -C "$R" commit -q -m util; chg app/core.py 'from app.util import compute\ndef pub():\n    _ = compute(2)\n    return 1\n'
ok "D8: a bare call to a repo-defined PURE function is flagged" "hit DISCARDED_CALL"
mkrepo; chg app/util.py 'def compute(x):\n    print(x)\n    return 1\n'; git -C "$R" add -A; git -C "$R" commit -q -m util; chg app/core.py 'from app.util import compute\ndef pub():\n    _ = compute(2)\n    return 1\n'
ok "D9: a bare call to a repo-defined function that CALLS something (print) is NOT flagged" "none"
mkrepo; chg app/core.py 'def pub():\n    _ = unknown_fn(2)\n    return 1\n'
ok "D10: a call to a function the repo does not define is NOT flagged" "none"

echo "== UNWIRED_HELPER: registered / nested functions (adversarial review false positives)"
mkrepo; chg app/core.py 'def pub():\n    return 1\n\n@app.exception_handler(ValueError)\nasync def _value_error_handler(request, exc):\n    return 1\n'
ok "H6: @app.exception_handler private handler is registered by its decorator" "none"
mkrepo; chg app/core.py 'def pub():\n    return 1\n\n@app.get("/hidden")\nasync def _hidden_route():\n    return 1\n'
ok "H7: @app.get(..) private route is registered by its decorator" "none"
mkrepo; chg app/core.py 'import click\n@click.command()\ndef _cli():\n    pass\n'
ok "H8: @click.command() private command is registered by its decorator" "none"
mkrepo; chg app/core.py 'def pub():\n    return 1\n\n@pytest.fixture\ndef _fx():\n    return 1\n'
ok "H9: @pytest.fixture private fixture in a source module is registered by its decorator" "none"
mkrepo; chg app/core.py 'def register(app):\n    @app.exception_handler(ValueError)\n    async def _h(request, exc):\n        return 1\n    return app\n'
ok "H10: a nested decorated handler inside a registration function (gitlark _dispatch_write_error_handler) is not a candidate" "none"
mkrepo; chg app/core.py 'def pub():\n    def _inner():\n        return 1\n    return 2\n'
ok "H11: a NESTED private function is not a candidate (closures are not module helpers)" "none"
mkrepo; chg app/core.py 'class K:\n    def _meth(self):\n        return 1\n'
ok "H12: a private METHOD nothing references IS still flagged (class-level helpers count)" "hit UNWIRED_HELPER"
mkrepo; chg app/core.py 'import signal\ndef _on_term(sig, frm):\n    pass\n\nsignal.signal(signal.SIGTERM, _on_term)\n'
ok "H13: a handler registered via signal.signal(.., _on_term) is referenced" "none"

echo "== unparsable base / head: structural rules fail open"
mkrepo; printf 'def _old_helper():\n    """unterminated\n    return 1\n\ndef dup():\n    return 1\n\ndef dup():\n    return 2\n' > "$R/app/core.py"; git -C "$R" add -A; git -C "$R" commit -q -m broken
chg app/core.py 'def _old_helper():\n    """closed"""\n    return 1\n\ndef dup():\n    return 1\n\ndef dup():\n    return 2\n'
ok "B1: a change that REPAIRS an unparsable base does not inherit its helpers / duplicates as new (gitlark 2001e169 shape)" "none"
mkrepo; chg app/core.py 'def pub(:\n    return 1\n'
ok "B2: an unparsable HEAD file gets no structural verdict (rc 0, no output)" "none"

echo "== DUP_DEF: legitimate same-name definitions"
mkrepo; chg app/core.py 'class U:\n    @hybrid_property\n    def tok(self):\n        return 1\n\n    @tok.setter\n    def tok(self, v):\n        pass\n\n    @tok.expression\n    def tok(cls):\n        return 2\n'
ok "U6: hybrid_property + .setter + .expression (gitlark User.github_token, was the one replay FP) is not flagged" "none"
mkrepo; chg tests/test_core.py 'class U:\n    @thing.custom\n    def val(self):\n        return 1\n\n    @val.other\n    def val(self):\n        return 2\n'
ok "U7: @<name>.<attr> chains on the function's own name are one descriptor definition" "none"
mkrepo; chg app/core.py '@app.get("/a")\nasync def h():\n    return 1\n\n@app.get("/b")\nasync def h():\n    return 2\n'
ok "U8: two route-registered handlers sharing a name in a SOURCE module are both registered: not flagged" "none"
mkrepo; chg tests/test_core.py 'import pytest\n@pytest.fixture\ndef client():\n    return 1\n\n@pytest.fixture\ndef client():\n    return 2\n'
ok "U9: a fixture defined twice in a TEST module is still a shadow: flagged" "hit DUP_DEF"

echo "== per-rule enforce / shadow split"
runenv(){ git -C "$R" add -A; git -C "$R" commit -q -m c; env "$@" python3 -I "${CHECKER:-$LQ}" check "$R" HEAD~1 HEAD 2>&1; }
mkrepo; chg app/routers/eng.py 'def _to_utc(dt):\n    return dt\n'
git -C "$R" add -A; git -C "$R" commit -q -m c
o="$(env -u OVN_LQ_RULES_ENFORCE python3 -I "$LQ" check "$R" HEAD~1 HEAD 2>&1)"; rc=$?
ok "E1: DEFAULT config: UNWIRED_HELPER is printed as ~UNWIRED_HELPER (got: $o)" "[ \"\$(printf '%s' '$o' | cut -c1-15)\" = '~UNWIRED_HELPER' ]"
ok "E1b: ... and exits 0 because it is shadow-only (got $rc)" "[ $rc = 0 ]"
hit_default(){ git -C "$R" add -A; git -C "$R" commit -q -m c; env -u OVN_LQ_RULES_ENFORCE python3 -I "${CHECKER:-$LQ}" check "$R" HEAD~1 HEAD 2>&1 | grep -q "^$1	"; }
mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    assert True\n'; git -C "$R" add -A; git -C "$R" commit -q -m c
env -u OVN_LQ_RULES_ENFORCE python3 -I "$LQ" check "$R" HEAD~1 HEAD >/dev/null 2>&1; rc=$?
ok "E2: DEFAULT config does NOT enforce TAUTOLOGY (rc 0: it had real false positives, shadow-only until the replay shows 0 FP; got $rc)" "[ $rc = 0 ]"
ok "E2b: ... and the finding is still logged as ~TAUTOLOGY" "[ -n \"\$(env -u OVN_LQ_RULES_ENFORCE python3 -I '$LQ' check '$R' HEAD~1 HEAD 2>&1 | grep '^~TAUTOLOGY')\" ]"
mkrepo; chg app/core.py 'class C:\n    def m(self):\n        return 1\n    def m(self):\n        return 2\n'; git -C "$R" add -A; git -C "$R" commit -q -m c
env -u OVN_LQ_RULES_ENFORCE python3 -I "$LQ" check "$R" HEAD~1 HEAD >/dev/null 2>&1; rc=$?
ok "E2c: DEFAULT config enforces DUP_DEF (rc 1, got $rc)" "[ $rc = 1 ]"
ok "E2d: stage runner wraps the checker in a timeout (fail-open on a stall)" "grep -q 'timeout \"\${OVN_LQ_TIMEOUT:-90}\" python3 scripts/ovn_landing_quality.py' '$HERE/../../ovn_stage_runner.sh'"
mkrepo; chg app/core.py 'class B:\n    def m(self):\n        return 1\n    def m(self):\n        return 2\n'; git -C "$R" add -A; git -C "$R" commit -q -m c
OVN_LQ_RULES_ENFORCE=TAUTOLOGY python3 -I "$LQ" check "$R" HEAD~1 HEAD >/dev/null 2>&1; rc=$?
ok "E3: OVN_LQ_RULES_ENFORCE=TAUTOLOGY demotes DUP_DEF to shadow (rc 0, got $rc)" "[ $rc = 0 ]"
OVN_LQ_RULES_ENFORCE= python3 -I "$LQ" check "$R" HEAD~1 HEAD >/dev/null 2>&1; rc=$?
ok "E4: an EMPTY enforce list = everything shadow (rc 0, got $rc)" "[ $rc = 0 ]"
ok "E4b: ... but the finding is still logged as ~DUP_DEF" "[ -n \"\$(OVN_LQ_RULES_ENFORCE= python3 -I '$LQ' check '$R' HEAD~1 HEAD 2>&1 | grep '^~DUP_DEF')\" ]"
ok "E5: fail open on an internal error: a file that raises inside check_file is skipped, not fatal" "python3 -I - '$LQ' <<'PY'
import importlib.util,sys
sp=importlib.util.spec_from_file_location('lq',sys.argv[1]);m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
m.check_file=lambda *a,**k:(_ for _ in ()).throw(RuntimeError('boom'))
m.git=lambda repo,*a,**k:'a.py\nb.py' if a[0]=='diff' else ''
assert m.check('x','b','h')==[]
PY"

echo "== clean change / errors"
mkrepo; chg app/core.py 'def pub():\n    return 1\n\ndef more():\n    return pub() + 1\n'; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_more():\n    assert more() == 2\n'
ok "C1: an ordinary feature + test is clean (rc 0, no output)" "none"
ok "C2: exit code 0 when clean" "git -C '$R' diff --quiet HEAD && python3 -I '$LQ' check '$R' HEAD HEAD"
mkrepo; chg tests/test_core.py 'def test_a():\n    assert True\n'; git -C "$R" add -A; git -C "$R" commit -q -m c
python3 -I "$LQ" check "$R" HEAD~1 HEAD >/dev/null 2>&1; rc=$?
ok "C3: exit code 1 when there are findings (got $rc)" "[ $rc = 1 ]"
python3 -I "$LQ" check "$R" no-such-ref HEAD >/dev/null 2>&1; rc=$?
ok "C4: a bad ref is rc 2 = no verdict (fail open), not a finding (got $rc)" "[ $rc = 2 ]"
python3 -I "$LQ" >/dev/null 2>&1; rc=$?
ok "C5: usage error is rc 2 (got $rc)" "[ $rc = 2 ]"

echo "== MUTANTS: each rule disabled => the live shape is no longer caught (proves the cases above exercise the rule)"
mkmut(){ python3 -I - "$LQ" "$T/mut.py" "$1" "$2" <<'PY'
import sys
src=open(sys.argv[1]).read()
assert sys.argv[3] in src, "mutation anchor missing: "+sys.argv[3]
open(sys.argv[2],"w").write(src.replace(sys.argv[3],sys.argv[4],1))
PY
}
mut(){  # <label> <anchor> <replacement> <setup fn> <rule>: the rule's positive case must stop firing under the mutant
  local lab="$1"; mkmut "$2" "$3" || { F=$((F+1)); echo "  FAIL: $lab anchor"; return; }
  $4
  ok "$lab: unmutated flags $5" "hit $5"
  ok "$lab: MUTANT no longer flags $5" "! CHECKER='$T/mut.py' hit $5"
}
mutneg(){  # <label> <anchor> <replacement> <setup fn> <rule>: a legitimate case must stay silent, and the mutant (guard removed) must flag it
  local lab="$1"; mkmut "$2" "$3" || { F=$((F+1)); echo "  FAIL: $lab anchor"; return; }
  $4
  ok "$lab: unmutated is silent for the legitimate case" "! hit $5"
  ok "$lab: MUTANT (guard removed) now false-positives $5" "CHECKER='$T/mut.py' hit $5"
}
s_taut(){ mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b():\n    assert x or True\n'; }
s_disc(){ mkrepo; chg app/core.py 'def pub():\n    _ = is_ready(pub)\n    return 1\n'; }
s_dup(){ mkrepo; chg app/core.py 'class Broker:\n    def m(self):\n        return 1\n    def m(self):\n        return 2\n'; }
s_unw(){ mkrepo; chg app/routers/eng.py 'def _to_utc(dt):\n    return dt\n'; chg tests/test_eng.py 'from app.routers.eng import _to_utc\ndef test_u():\n    assert _to_utc(1) == 1\n'; }
s_testmod(){ mkrepo; chg app/routers/test_runs.py 'def old():\n    return 0\n\ndef start(r):\n    _ = is_terminal_status(r)\n'; }
s_stat(){ mkrepo; chg tests/test_core.py 'def test_a():\n    assert pub() == 1\n\ndef test_b(r):\n    assert r.status_code in [200, 401, 403]\n'; }
s_deco(){ mkrepo; chg app/core.py 'def pub():\n    return 1\n\n@app.get("/hidden")\nasync def _hidden_route():\n    return 1\n'; }
s_nest(){ mkrepo; chg app/core.py 'def pub():\n    def _inner():\n        return 1\n    return 2\n'; }
s_brk(){ mkrepo; printf 'def _old_helper():\n    """unterminated\n    return 1\n' > "$R/app/core.py"; git -C "$R" add -A; git -C "$R" commit -q -m broken; chg app/core.py 'def _old_helper():\n    """closed"""\n    return 1\n'; }
s_exec(){ mkrepo; chg app/core.py 'def pub():\n    _ = session.exec(stmt)\n    return 1\n'; }
s_impure(){ mkrepo; chg app/util.py 'def compute(x):\n    print(x)\n    return 1\n'; git -C "$R" add -A; git -C "$R" commit -q -m util; chg app/core.py 'from app.util import compute\ndef pub():\n    _ = compute(2)\n    return 1\n'; }
s_pure(){ mkrepo; chg app/util.py 'def compute(x):\n    return len(str(x)) + 1\n'; git -C "$R" add -A; git -C "$R" commit -q -m util; chg app/core.py 'from app.util import compute\ndef pub():\n    _ = compute(2)\n    return 1\n'; }
s_hyb(){ mkrepo; chg tests/test_core.py 'class U:\n    @thing.custom\n    def val(self):\n        return 1\n\n    @val.other\n    def val(self):\n        return 2\n'; }
s_route2(){ mkrepo; chg app/core.py '@app.get("/a")\nasync def h():\n    return 1\n\n@app.get("/b")\nasync def h():\n    return 2\n'; }
mut M1 'if hit:' 'if False:' s_taut TAUTOLOGY
mut M2 'if PREDICATE.match(nm) or (isinstance(f, ast.Name) and _pure_function(repo, head, nm)):' 'if False:' s_disc DISCARDED_CALL
mut M3 'if n > bd.get((scope, name), 1):' 'if False:' s_dup DUP_DEF
mut M4 'if not referenced_outside_tests(repo, head, name):' 'if False:' s_unw UNWIRED_HELPER
mut M5 'return bool(TEST_NAME.search(path)) and not APP_DIR.search(path)' 'return bool(TEST_NAME.search(path))' s_testmod DISCARDED_CALL
mut M6 'if _status_vacuous(t):' 'if False:' s_stat TAUTOLOGY_STATUS
mutneg M7 'if all(d in TRIVIAL_DECOS for d in _deco_texts(n)):' 'if True:' s_deco UNWIRED_HELPER
mutneg M8 '    walk(tree.body)
    return out' '    out.update(n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("_") and not n.name.startswith("__"))
    return out' s_nest UNWIRED_HELPER
mutneg M9 'if head_tree is None or (base_src is not None and base_tree is None):' 'if head_tree is None:' s_brk UNWIRED_HELPER
mutneg M10 'if PREDICATE.match(nm) or (isinstance(f, ast.Name) and _pure_function(repo, head, nm)):' 'if True:' s_exec DISCARDED_CALL
mutneg M11 'if isinstance(n, ast.Call) and not (isinstance(n.func, ast.Name) and n.func.id in SAFE_BUILTINS):' 'if False:' s_impure DISCARDED_CALL
mutneg M12 'if any(d.startswith(node.name + ".") for d in decos):' 'if False:' s_hyb DUP_DEF
mutneg M13 'if not is_test and any(re.match(' 'if False and any(re.match(' s_route2 DUP_DEF
mkmut 'if r[0] in enf:' 'if True:'; s_unw
ok "M14: unmutated, the DEFAULT config does not print UNWIRED_HELPER as an enforced finding" "! hit_default UNWIRED_HELPER"
ok "M14: MUTANT (shadow split removed) prints it as enforced" "CHECKER='$T/mut.py' hit_default UNWIRED_HELPER"

echo "landing-quality: $P passed, $F failed"
[ "$F" -eq 0 ]
