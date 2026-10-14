#!/usr/bin/env python3
"""R01 extensions (spec-intake-5-lanes, 2026-10-13): VERIFY shapes no reader could parse. (a) Run-verb and (c) `| wc -l >= N` are pure repairs, ENFORCED like R01. (b) the bare
'returns no results' form is SHADOW by default (fixer round: `! grep` credited a typo'd path; the deployed credit gate already reads the bare form with strict polarity); OVN_SPEC_R01X_NEG=on
repairs a lone grep to the rc-strict `grep ... ; [ $? -eq 1 ]`. A wc comparison an empty count satisfies is flagged, never rewritten.

Fixtures are the exact VERIFY texts of the 10-13 credit refusals (state/verify_gate_shadow.log, 5 lanes enabled 14:42-15:15Z):
  TAA line 1485      VERIFY: Run `pytest backend/tests/test_baseline_lookup.py -v`.                              (4 rows)
  xlite f68cdc4e     VERIFY: grep -n "func simulate_single_load" scripts/battle/damage.gd returns no results.
  shrike-notify 0ac5801c  VERIFY: grep -n "_track_task" backend/app/services/auth.py | wc -l >= 2             (unquoted >= is a shell redirect: the clause can never pass)
The repaired text must be read back by BOTH extractors (ovn_backlog_eligibility.extract_verify and the classifier's verify_of), be idempotent, and run with the intended polarity.
Mutation proof: see the package report (drop the new branch in _r01 -> every fixture below fails)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.path.insert(0, ROOT)
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_spec_classify as C  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def line(target, text, verify, cat="python", feat=None):
    s = "- [ ] [T2] %s — %s VERIFY: %s (cat:%s; multifile:no)" % (target, text, verify, cat)
    return s + (" [feat:%s]" % feat if feat else "")


def run(cmd, cwd):
    return subprocess.run(["bash", "-c", cmd], cwd=cwd, capture_output=True).returncode


def rules_of(fs):
    return sorted(f["rule"] for f in fs)


for k in ("OVN_SPEC_R01X", "OVN_SPEC_R01X_NEG", "OVN_SPEC_GATE", "OVN_SPEC_GATE_ENFORCE_RULES"):
    os.environ.pop(k, None)

TAA = line("backend/tests/test_baseline_lookup.py", "Create tests for the baseline lookup.", "Run `pytest backend/tests/test_baseline_lookup.py -v`.", "test", "test-automation-agent-20261012-baseline")
NEG = line("scripts/battle/damage.gd", "Delete func simulate_single_load.", 'grep -n "func simulate_single_load" scripts/battle/damage.gd returns no results.', "godot")
WC = line("backend/app/services/auth.py", "Track the background tasks.", 'grep -n "_track_task" backend/app/services/auth.py | wc -l >= 2')
WCP = line("backend/app/services/auth.py", "Track the background tasks.", 'grep -n "_track_task" backend/app/services/auth.py | wc -l >= 2.')

print("== reproduction: the old behaviour leaves all of them unreadable")
for name, l in (("TAA Run-prefix", TAA), ("xlite bare negative", NEG), ("shrike-notify wc >=", WC)):
    ok("%s: R01 proper (bare_verify) does not accept the raw clause, so no reader got a command" % name, R.bare_verify(l) is None and "VERIFY: `" not in l, R.bare_verify(l))

print("== (a) Run|Execute|Check verb")
l2, fs = R.lint_static(TAA)
ok("TAA: R01 repair, verb and period dropped, command backticked", rules_of(fs) == ["R01"] and "VERIFY: `pytest backend/tests/test_baseline_lookup.py -v` (cat:test" in l2, (l2, fs))
ok("TAA: both extractors read the repaired command", E.extract_verify(l2) == C.verify_of(l2) == "pytest backend/tests/test_baseline_lookup.py -v", (E.extract_verify(l2), C.verify_of(l2)))
ok("TAA: the classifier already reads the Run-prefix of an UNrepaired line", C.verify_of(TAA) == "pytest backend/tests/test_baseline_lookup.py -v", C.verify_of(TAA))
ok("TAA: finding shape rule/sev/msg/evidence, sev repair", fs and set(fs[0]) == {"rule", "sev", "msg", "evidence"} and fs[0]["sev"] == "repair" and "Run" in fs[0]["msg"])
ok("TAA: idempotent", R.lint_static(l2) == (l2, []))
for verb in ("Run", "run", "Execute", "Check"):
    l = line("a.py", "do it.", "%s `pytest tests/test_a.py -q`." % verb)
    ok("verb %s is dropped" % verb, C.verify_of(R.lint_static(l)[0]) == "pytest tests/test_a.py -q", R.lint_static(l)[0])
l = line("a.py", "do it.", "Run pytest tests/test_a.py -q.")
ok("the unbackticked 'Run cmd.' form is repaired too", E.extract_verify(R.lint_static(l)[0]) == "pytest tests/test_a.py -q", R.lint_static(l)[0])
l = line("a.py", "do it.", "Run `grep -c foo f.txt | wc -l >= 2`.")
ok("verb + wc compose", E.extract_verify(R.lint_static(l)[0]) == '[ "$(grep -c foo f.txt | wc -l)" -ge 2 ]', R.lint_static(l)[0])

print("== (b) bare 'returns no results': SHADOW by default (flag, line untouched)")
l2, fs = R.lint_static(NEG)
ok("xlite f68cdc4e default: line untouched, one R01 FLAG carrying the rc-strict proposal", l2 == NEG and rules_of(fs) == ["R01"] and fs[0]["sev"] == "flag"
   and fs[0]["evidence"]["proposed"] == 'grep -n "func simulate_single_load" scripts/battle/damage.gd ; [ $? -eq 1 ]', (l2, fs))
ok("xlite default: the proposal is NEVER `! grep` (a typo'd path would pass)", "! grep" not in str(fs))
ok("xlite default: sev flag is not a repair (consult_gate / lint filter apply nothing)", not [f for f in fs if f["sev"] == "repair"])
ok("xlite default: idempotent", R.lint_static(l2) == (l2, fs))
for mode in ("off", "OFF"):
    os.environ["OVN_SPEC_R01X_NEG"] = mode
    ok("OVN_SPEC_R01X_NEG=%s: no finding at all" % mode, R.lint_static(NEG) == (NEG, []))
os.environ["OVN_SPEC_R01X_NEG"] = "bogus"
ok("an unknown value falls back to shadow", R.lint_static(NEG)[0] == NEG and rules_of(R.lint_static(NEG)[1]) == ["R01"])
os.environ["OVN_SPEC_R01X_NEG"] = " On "
l2, fs = R.lint_static(NEG)
ok("OVN_SPEC_R01X_NEG=on (any case): R01 repair to the rc-strict form", rules_of(fs) == ["R01"] and fs[0]["sev"] == "repair" and E.extract_verify(l2) == 'grep -n "func simulate_single_load" scripts/battle/damage.gd ; [ $? -eq 1 ]', (l2, fs))
ok("on: both extractors agree", E.extract_verify(l2) == C.verify_of(l2))
ok("on: idempotent", R.lint_static(l2) == (l2, []))
td = tempfile.mkdtemp(prefix="r01x-")
os.makedirs(os.path.join(td, "scripts/battle"))
dmg = os.path.join(td, "scripts/battle/damage.gd")
open(dmg, "w").write("func other():\n\tpass\n")
cmd = E.extract_verify(l2)
ok("on BEHAVIOUR: passes once the function is gone", run(cmd, td) == 0)
open(dmg, "w").write("func simulate_single_load():\n\tpass\n")
ok("on BEHAVIOUR: fails while the function is still there", run(cmd, td) != 0)
os.remove(dmg)
ok("on BEHAVIOUR: a MISSING / typo'd path FAILS (grep rc 2), the bug the reviewer found in `! grep`", run(cmd, td) != 0)
ok("contrast: `! grep` on the same missing path would pass (why it is not emitted)", run('! grep -n "func simulate_single_load" scripts/battle/damage.gd', td) == 0)
shutil.rmtree(td, ignore_errors=True)
for narr in ("has no matches", "returns nothing", "returns no matches", "returns no lines", "should return no results", "returns no results after the change"):
    l = line("a.gd", "x.", 'grep -n "foo" a.gd %s.' % narr)
    ok("on: narration '%s' repaired" % narr, E.extract_verify(R.lint_static(l)[0]) == 'grep -n "foo" a.gd ; [ $? -eq 1 ]', R.lint_static(l)[0])
for name, v in (("a && chain", 'grep -n "foo" a.gd && grep -n "bar" a.gd returns no results.'),
                ("a regex alternation in quotes is fine, a pipe is not", 'grep -n "foo" a.gd | sort returns no results.'),
                ("ls (empty dir is the correct state; `! ls` is true only for a MISSING dir)", "ls -A tmp_dir has no output."),
                ("ls prints no output", "ls tests/ prints no output."),
                ("test -s", "test -s f.log returns nothing."),
                ("test -f", "test -f a.gd returns no results."),
                ("a leading !", '! grep -n "foo" a.gd returns no results.')):
    l = line("a.gd", "x.", v)
    ok("on: NEVER rewritten: %s" % name, R.lint_static(l) == (l, []), R.lint_static(l))
l = line("a.gd", "x.", 'grep -nE "foo|bar" a.gd returns no results.')
ok("on: an alternation inside quotes is not a pipe", E.extract_verify(R.lint_static(l)[0]) == 'grep -nE "foo|bar" a.gd ; [ $? -eq 1 ]', R.lint_static(l)[0])
del os.environ["OVN_SPEC_R01X_NEG"]
for v in ("ls -A tmp_dir has no output.", "ls tests/ prints no output.", "test -s f.log returns nothing."):
    l = line("a.gd", "x.", v)
    ok("default: no repair and no finding for non-grep narration: %s" % v, R.lint_static(l) == (l, []))

print("== (c) | wc -l >= N")
for name, l in (("without period", WC), ("with period", WCP)):
    l2, fs = R.lint_static(l)
    want = '[ "$(grep -n "_track_task" backend/app/services/auth.py | wc -l)" -ge 2 ]'
    ok("shrike-notify 0ac5801c (%s): R01 repair" % name, rules_of(fs) == ["R01"] and E.extract_verify(l2) == want == C.verify_of(l2), (l2, fs))
    ok("shrike-notify (%s): idempotent" % name, R.lint_static(l2) == (l2, []))
td = tempfile.mkdtemp(prefix="r01x-")
os.makedirs(os.path.join(td, "backend/app/services"))
auth = os.path.join(td, "backend/app/services/auth.py")
cmd = E.extract_verify(R.lint_static(WC)[0])
open(auth, "w").write("x = _track_task(a)\n")
ok("wc BEHAVIOUR: one match is below 2 -> fails", run(cmd, td) != 0)
open(auth, "w").write("x = _track_task(a)\ny = _track_task(b)\n")
ok("wc BEHAVIOUR: two matches -> passes", run(cmd, td) == 0)
open(auth, "w").write("x = _track_task(a)\ny = _track_task(b)\nz = _track_task(c)\n")
ok("wc BEHAVIOUR: three matches -> passes", run(cmd, td) == 0)
ok("the unrepaired form can NEVER pass (wc is handed a file named 2, stdout goes into a file named '='), the bug this fixes", run('grep -n "_track_task" backend/app/services/auth.py | wc -l >= 2', td) != 0 and os.path.exists(os.path.join(td, "=")))
os.remove(auth)
ok("wc BEHAVIOUR: a typo'd / missing path FAILS a >= 2 test (count 0)", run(cmd, td) != 0)
shutil.rmtree(td, ignore_errors=True)
for op, flag in (("==", "-eq"), (">", "-gt")):
    l = line("a.py", "x.", 'grep -n "foo" a.py | wc -l %s 3' % op)
    ok("operator %s -> %s" % (op, flag), E.extract_verify(R.lint_static(l)[0]) == '[ "$(grep -n "foo" a.py | wc -l)" %s 3 ]' % flag, R.lint_static(l)[0])
for op, n in (("<=", 3), ("<", 3), ("==", 0), (">=", 0), ("<=", 0)):
    l = line("a.py", "x.", 'grep -n "foo" a.py | wc -l %s %d' % (op, n))
    l2, fs = R.lint_static(l)
    ok("operator %s %d (an empty count satisfies it): NOT rewritten, R01 flag only" % (op, n), l2 == l and rules_of(fs) == ["R01"] and fs[0]["sev"] == "flag" and "typo" in fs[0]["msg"], (l2, fs))
td = tempfile.mkdtemp(prefix="r01x-")
l = line("a.py", "x.", 'grep -rn "foo" nodir | grep -v test_ | wc -l == 0')
ok("the historical `... | wc -l == 0` line is left as written (its rewrite would pass on a missing dir)", R.lint_static(l)[0] == l and run('[ "$(grep -rn "foo" nodir | grep -v test_ | wc -l)" -eq 0 ]', td) == 0)
shutil.rmtree(td, ignore_errors=True)
os.environ["OVN_SPEC_R01X"] = "OFF"
ok("OVN_SPEC_R01X=OFF (upper case) is honoured too: no flag, no repair", R.lint_static(l) == (l, []) and R.lint_static(WC) == (WC, []) and R.lint_static(TAA) == (TAA, []))
os.environ["OVN_SPEC_R01X"] = " Off "
ok("OVN_SPEC_R01X=' Off ' is honoured", R.lint_static(WC) == (WC, []))
del os.environ["OVN_SPEC_R01X"]
l = line("a.py", "x.", "grep -n foo a.py | grep -v bar | wc -l >= 2")
ok("a multi-stage grep pipeline is fine", E.extract_verify(R.lint_static(l)[0]) == '[ "$(grep -n foo a.py | grep -v bar | wc -l)" -ge 2 ]', R.lint_static(l)[0])

print("== the classifier reader does not treat a Run/Check SENTENCE as a command")
for v in ("Run npm test and ensure it passes.", "Run ls foo and see that it exists.", "Check grep -n foo f.py shows a match near line 4.", "Execute pytest tests/test_a.py and verify it passes."):
    l = line("a.py", "do it.", v)
    got = C.verify_of(l)
    ok("verify_of(%r) keeps the sentence as it was (verb kept, so it still classifies as unrunnable) and does NOT hand back the stripped 'command'" % v, got is None or got.split()[0] in ("Run", "Execute", "Check"), got)
    ok("strip_verify_verb(%r) is None" % v, C.strip_verify_verb(v) is None, C.strip_verify_verb(v))
ok("strip_verify_verb still reads the clean bare and backticked forms", C.strip_verify_verb("Run pytest a.py -q.") == "pytest a.py -q" and C.strip_verify_verb("Run `pytest a.py -q`.") == "pytest a.py -q")

print("== NEGATIVES: nothing else is touched")
BAD = (
    ("prose after Run", "Run the tests and confirm they pass."),
    ("Run + backticked cmd + narration", "Run `pytest tests/test_a.py` and confirm it passes."),
    ("Check that", "Check that the file exists."),
    ("Run with a verb that is not allowed", "Run `curl localhost:8000/health`."),
    ("Run with a denylisted command", "Run `rm -rf build`."),
    ("Run + two backtick spans", "Run `pytest a.py` then `pytest b.py`."),
    ("negative narration on a runner (pytest)", "pytest tests/test_a.py returns no results."),
    ("negative narration on python -c (not in R03's whitelist)", 'python3 -c "print(1)" returns no results.'),
    ("negative narration with a redirect", 'grep -n "foo" a.gd > out.txt returns no results.'),
    ("negative narration, denylisted token", 'grep -n "foo" a.gd && curl x returns no results.'),
    ("negative narration inside a single pipe (R03 only takes a grep tail)", 'grep -n "foo" a.gd | sort returns no results.'),
    ("wc with a ; chain", 'grep foo a.py; grep bar a.py | wc -l >= 2'),
    ("wc with a redirect stage", 'grep foo a.py > o.txt | wc -l >= 2'),
    ("wc on a denylisted command", 'curl http://x | wc -l >= 2'),
    ("wc on cat (not an R01 tool)", 'cat a.py | wc -l >= 2'),
    ("wc with a non-numeric bound", 'grep foo a.py | wc -l >= many'),
    ("wc -c, not -l", 'grep foo a.py | wc -c >= 2'),
    ("wc behind && ", 'grep foo a.py && grep bar a.py | wc -l >= 2'),
    ("empty-ish", "see above"),
)
for name, v in BAD:
    l = line("a.py", "do it.", v)
    ok("NEGATIVE %s: line unchanged" % name, R.lint_static(l) == (l, []), R.lint_static(l))
ok("an already backticked clause is untouched", R.lint_static(line("a.py", "x.", "`grep -q a f`")) == (line("a.py", "x.", "`grep -q a f`"), []))
echo = line("f.txt", "Rename it.", 'grep -q old_name f.txt && echo "FAIL" || echo "PASS"')
l2, fs = R.lint_static(echo)
ok("the existing echo-idiom repair still works", rules_of(fs) == ["R01"] and E.extract_verify(l2) == "! ( grep -q old_name f.txt )", (l2, fs))
plain = line("a.py", "do it.", "pytest tests/test_a.py -q.")
ok("the plain bare repair still works", "VERIFY: `pytest tests/test_a.py -q` (cat:" in R.lint_static(plain)[0])

print("== kill switch and enforcement wiring")
os.environ["OVN_SPEC_R01X"] = "off"
ok("OVN_SPEC_R01X=off: none of them is repaired or flagged", all(R.lint_static(l) == (l, []) for l in (TAA, NEG, WC, WCP)))
os.environ["OVN_SPEC_R01X_NEG"] = "on"
ok("OVN_SPEC_R01X=off wins over OVN_SPEC_R01X_NEG=on", R.lint_static(NEG) == (NEG, []))
del os.environ["OVN_SPEC_R01X_NEG"]
del os.environ["OVN_SPEC_R01X"]
ok("lint_static(only={'R01'}) applies the two repairs (R01 is in the default enforced set) and leaves the shadow form alone", all(R.lint_static(l, only={"R01"})[0] != l for l in (TAA, WC)) and R.lint_static(NEG, only={"R01"})[0] == NEG)
ok("lint_static(only={'R02','R03'}) does not", all(R.lint_static(l, only={"R02", "R03"}) == (l, []) for l in (TAA, NEG, WC)))
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_spec_gate.py"), "lint"], input="\n".join([TAA, NEG, WC]), capture_output=True, text=True,
                   env={k: v for k, v in os.environ.items() if not k.startswith("OVN_SPEC")})
outl = r.stdout.split("\n")
ok("`ovn_spec_gate.py lint` with the DEFAULT env repairs the Run-verb and wc lines and leaves the bare 'returns no results' line byte-identical (planner path)", len(outl) == 3 and outl[1] == NEG and [E.extract_verify(x) for x in (outl[0], outl[2])] == [
    "pytest backend/tests/test_baseline_lookup.py -v", '[ "$(grep -n "_track_task" backend/app/services/auth.py | wc -l)" -ge 2 ]'], (r.stdout, r.stderr))
try:
    import queue_refill as Q
    for l in (TAA, WC):
        act, l2, rule, _ = Q.consult_gate(l, "x", {})
        ok("queue_refill.consult_gate (default enforce set) pulls the REPAIRED line: %s" % l[7:40], act == "pull" and l2 != l and E.extract_verify(l2) and "Run" not in (E.extract_verify(l2) or "") and "wc -l >=" not in (E.extract_verify(l2) or ""), (act, l2))
    act, l2, rule, _ = Q.consult_gate(NEG, "x", {})
    ok("queue_refill.consult_gate (default enforce set) pulls the bare 'returns no results' line UNCHANGED (no `! grep` at pull time)", act == "pull" and l2 == NEG, (act, l2))
except ImportError as e:
    ok("queue_refill importable", False, e)

print("\nR01x: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
