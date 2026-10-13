#!/usr/bin/env python3
"""R14 verify package (2026-10-12) - X1 / iptv D / iptv F: VERIFY polarity and the spec-rule extensions.

  verify_polarity (ovn_backlog_eligibility)   'neg' only for an exit-code command narrated as an absence; pos / unknown otherwise
  queue_refill.already_satisfied              credits an absence item only when the command's exit status says ABSENT (the old code credited when the symbol was STILL there)
  R03                                         `returns no lines|no output|nothing|empty [containing ...]` -> negated form (also for a grep pipeline)
  R01                                         the bare `cmd && echo "FAIL" || echo "PASS"` idiom is repaired and backticked
  bare_verify_neg                             bare `grep ... returns no results` is read as a command (with its polarity)
Mutations proved inline: polarity disabled (always 'unknown'), R03 no-lines phrase removed, R01 echo repair removed. The bash side (shadow_check) is test_verify_polarity_shadow.sh."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_spec_rules as R  # noqa: E402
import queue_refill as Q  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def it(v, tail=""):
    return "- [ ] [T2] a.gd — x. VERIFY: %s%s (cat:gd; multifile:no)" % (v, tail)


print("== verify_polarity: absence narrations")
NEG = [
    '`grep -n "is_destructible_type" scripts/battle/aoe.gd` returns no matches.',
    '`grep -n "X" f.gd` returns no results.',
    '`grep -r "CellRing" tests/` returns no output.',
    '`ls scripts/battle/cell_ring.gd` fails with "No such file or directory".',
    '`test -f a.gd` returns false.',
    '`grep -q x f` exits non-zero.',
    '`grep -n "_cache" discover.py | grep -v "_catalog_cache"` returns no lines containing _cache: dict[str, list].',
    '`ls a.gd` fails.',
    '`grep -n foo f` returns nothing.',
    '`cat a.gd` fails once the file is deleted.',
]
for v in NEG:
    ok("neg: " + v[:70], E.verify_polarity(it(v, "")) == "neg", E.verify_clause_and_polarity(it(v)))
print("== verify_polarity: pos / unknown stay as today")
OTHER = [
    ('`grep -n x f` returns matches.', "pos"),
    ('`grep -c x f` passes.', "pos"),
    ('`grep -q x f`', "unknown"),
    ('`! grep -q x f` fails with no such file.', "unknown"),           # already negated (R03 output keeps the narration sentence)
    ('`test ! -f a.gd` returns false.', "unknown"),
    ('`pytest tests/test_x.py -q` fails.', "unknown"),                  # a runner narrating 'fails' means fails BEFORE the fix
    ('`python3 -c "import x"` returns false.', "unknown"),
    ('`grep -q x f` returns no matches before the change.', "unknown"),  # red-state narration
    ('`grep -q x f` returns no matches today, matches after.', "unknown"),
    ('`grep -q x f` fails when the symbol is present.', "unknown"),
    ('`grep -q x f` returns matches but returns no output for y.', "unknown"),  # mixed
    ('`grep -q "returns no matches" f`', "unknown"),                   # the phrase inside the command is not narration
]
for v, want in OTHER:
    ok("%s: %s" % (want, v[:70]), E.verify_polarity(it(v)) == want, E.verify_clause_and_polarity(it(v)))
ok("no VERIFY at all -> unknown", E.verify_polarity("- [ ] [T2] a — b (cat:x)") == "unknown")

print("== polarity_verdict (exit-status mapping)")
V = E.polarity_verdict
ok("neg grep: rc1 = satisfied", V("neg", "grep", 1) is True)
ok("neg grep: rc0 (still present) = NOT satisfied", V("neg", "grep", 0) is False)
ok("neg grep: rc2 (grep error) is never an absence", V("neg", "grep", 2) is False)
ok("neg exit-tool: rc2 (ls: no such file) = satisfied", V("neg", "exit", 2) is True)
ok("neg exit-tool: rc0 = NOT satisfied", V("neg", "exit", 0) is False)
ok("124/126/127 are never a verdict", V("neg", "grep", 124) is None and V("pos", "grep", 127) is None and V("neg", "exit", 126) is None)
ok("unknown / pos: rc==0 as before", V("unknown", "grep", 0) is True and V("pos", "grep", 1) is False)

print("== queue_refill.already_satisfied honours the polarity (the live false-credit)")
d = tempfile.mkdtemp(prefix="pol-")
os.makedirs(os.path.join(d, "scripts", "battle"))
os.makedirs(os.path.join(d, "tests"))
with open(os.path.join(d, "scripts", "battle", "aoe.gd"), "w") as f:
    f.write("static func is_destructible_type(x):\n\treturn true\n")
with open(os.path.join(d, "scripts", "battle", "cell_ring.gd"), "w") as f:
    f.write("pass\n")
with open(os.path.join(d, "tests", "test_cell_ring.gd"), "w") as f:
    f.write("CellRing\n")
l_sym = it('`grep -n "is_destructible_type" scripts/battle/aoe.gd` returns no matches.')
ok("symbol STILL present + 'returns no matches' -> NOT credited (was credited: rc 0)", Q.already_satisfied(l_sym, d) is False)
l_gone = it('`grep -n "nonexistent_symbol_zz" scripts/battle/aoe.gd` returns no matches.')
ok("symbol absent + 'returns no matches' -> credited", Q.already_satisfied(l_gone, d) is True)
l_err = it('`grep -n "x" scripts/battle/does_not_exist.gd` returns no matches.')
ok("grep error (rc 2, missing file) is not an absence -> NOT credited", Q.already_satisfied(l_err, d) is False)
l_ls = it('`ls scripts/battle/cell_ring.gd` fails with "No such file or directory".')
ok("file STILL exists + 'fails with No such file' -> NOT credited", Q.already_satisfied(l_ls, d) is False)
l_ls2 = it('`ls scripts/battle/gone.gd` fails with "No such file or directory".')
ok("file absent + 'fails with No such file' -> credited", Q.already_satisfied(l_ls2, d) is True)
l_tree = it('`grep -r "CellRing" tests/` returns no output.')
ok("grep -r still matches a test + 'returns no output' -> NOT credited", Q.already_satisfied(l_tree, d) is False)
l_pipe = it('`grep -n "is_destructible_type" scripts/battle/aoe.gd | grep -v "xx"` returns no lines containing is_destructible_type.')
ok("pipeline still has lines + 'returns no lines' -> NOT credited", Q.already_satisfied(l_pipe, d) is False)
ok("CONTROL unknown polarity: grep rc0 still credits as before", Q.already_satisfied(it('`grep -n "is_destructible_type" scripts/battle/aoe.gd`'), d) is True)
ok("CONTROL pos polarity: grep rc0 credits", Q.already_satisfied(it('`grep -n "is_destructible_type" scripts/battle/aoe.gd` returns matches.'), d) is True)
ok("neg + an unsafe compound command is refused (never executed)", Q.already_satisfied(it('`ls a.gd; touch /tmp/pol_never` fails.'), d) is False and not os.path.exists("/tmp/pol_never"))
os.environ["OVN_VERIFY_POLARITY"] = "off"
ok("kill switch OVN_VERIFY_POLARITY=off restores the old reading (credits on rc 0)", Q.already_satisfied(l_sym, d) is True)
del os.environ["OVN_VERIFY_POLARITY"]

print("== MUTATION: polarity disabled -> the false credit comes back")
_vc = E.verify_clause_and_polarity
_au = E.absence_narration_unresolved
E.verify_clause_and_polarity = lambda line: (E.extract_verify(line) or "", "unknown")
try:
    # 2026-10-13 (iptv F3): a second layer now refuses an absence narration the polarity reader left unresolved, so disabling ONLY the polarity reader no longer credits it
    ok("polarity reader disabled alone: the unresolved-absence refusal still blocks the credit (defence in depth)", Q.already_satisfied(l_sym, d) is False)
    E.absence_narration_unresolved = lambda line: False
    ok("mutant (both layers disabled) credits the still-present symbol (proves the test above can fail)", Q.already_satisfied(l_sym, d) is True)
finally:
    E.verify_clause_and_polarity = _vc
    E.absence_narration_unresolved = _au

print("== R03: 'returns no lines|no output|nothing|empty [containing ...]' (iptv D)")
l = it('`grep -n "_cache" discover.py | grep -v "_catalog_cache"` returns no lines containing _cache: dict[str, list[dict[str, Any]]].', "")
l2, fs = R.lint_static(l, only={"R03"})
ok("pipeline + 'returns no lines containing ...' -> `! ( pipeline )`", E.extract_verify(l2) == '! ( grep -n "_cache" discover.py | grep -v "_catalog_cache" )' and [f["rule"] for f in fs] == ["R03"], (l2, fs))
ok("the rest of the line (cat tag) survives, no stray narration", "(cat:gd; multifile:no)" in l2 and "returns no lines" not in l2, l2)
for ph in ("returns no output", "returns nothing", "returns empty", "returns no lines"):
    l3, fs3 = R.lint_static(it("`grep -rn x a.py` " + ph + "."), only={"R03"})
    ok("R03 phrase '%s' -> `! grep ...`" % ph, E.extract_verify(l3) == "! grep -rn x a.py" and [f["rule"] for f in fs3] == ["R03"], (l3, fs3))
l4, fs4 = R.lint_static(it("`grep -rn x a.py | wc -l` returns no output."), only={"R03"})
ok("NEGATIVE: a pipe ending in wc is never negated", E.extract_verify(l4) == "grep -rn x a.py | wc -l" and not [f for f in fs4 if f["sev"] == "repair"], (l4, fs4))
l5, fs5 = R.lint_static(it("`pytest tests/x.py` returns no output."), only={"R03"})
ok("NEGATIVE: a test runner is never negated", E.extract_verify(l5) == "pytest tests/x.py", (l5, fs5))
l6, fs6 = R.lint_static(it("`grep -rn x a.py` returns no output before the change."), only={"R03"})
ok("NEGATIVE: temporal qualifier -> untouched + flag", E.extract_verify(l6) == "grep -rn x a.py" and [f["sev"] for f in fs6] == ["flag"], (l6, fs6))
l7, fs7 = R.lint_static(l2, only={"R03"})
ok("R03 is idempotent on its own output", l7 == l2 and not fs7, (l7, fs7))
_n = R._R03_NOLINES
R._R03_NOLINES = R.re.compile("NEVERMATCHES")
l8, fs8 = R.lint_static(l, only={"R03"})
R._R03_NOLINES = _n
ok("MUTATION (no-lines pipeline phrase removed): the pipeline is left alone", l8 == l or not [f for f in fs8 if f["sev"] == "repair"], l8)

print("== R01: bare `cmd && echo FAIL || echo PASS` (iptv F)")
bare = '- [ ] [T2] iptv-backend/tests/test_content_rate_limit.py — remove strict=True from xfail. VERIFY: grep -q "strict=True" iptv-backend/tests/test_content_rate_limit.py && echo "FAIL" || echo "PASS". (cat:python; multifile:no) [feat:x]'
b2, fb = R.lint_static(bare, only={"R01"})
ok("bare echo idiom -> VERIFY: `! ( grep -q \"strict=True\" ... )`", E.extract_verify(b2) == '! ( grep -q "strict=True" iptv-backend/tests/test_content_rate_limit.py )' and [f["rule"] for f in fb] == ["R01"], (b2, fb))
ok("(cat:...) tag and feat tag survive", "(cat:python; multifile:no) [feat:x]" in b2, b2)
b3, fb3 = R.lint_static(b2, only={"R01"})
ok("idempotent", b3 == b2 and not fb3)
pb = bare.replace('echo "FAIL" || echo "PASS"', 'echo "PASS" || echo "FAIL"')
ok("the PASS-first variant becomes the plain command", E.extract_verify(R.lint_static(pb, only={"R01"})[0]) == 'grep -q "strict=True" iptv-backend/tests/test_content_rate_limit.py', R.lint_static(pb, only={"R01"})[0])
pipe = bare.replace('grep -q "strict=True" iptv-backend/tests/test_content_rate_limit.py', 'grep -n x f | head -1')
ok("NEGATIVE: an echo idiom around a pipeline is left alone (repair_vacuous_cmd refuses it)", R.lint_static(pipe, only={"R01"})[0] == pipe)
_rv = R.repair_vacuous_cmd
R.repair_vacuous_cmd = lambda c: None
ok("MUTATION (echo repair removed): the bare idiom stays unrepaired", R.lint_static(bare, only={"R01"})[0] == bare)
R.repair_vacuous_cmd = _rv

print("== bare_verify_neg: bare `grep ... returns no results` (xlite X1 damage.gd items)")
bl = "- [ ] [T2] scripts/battle/damage.gd — remove coerce_to_array. VERIFY: grep -n \"coerce_to_array\" scripts/battle/damage.gd returns no results. (cat:gd; multifile:no)"
ok("bare_verify rejects it (prose), bare_verify_neg reads the command", R.bare_verify(bl) is None and R.bare_verify_neg(bl) is not None and R.bare_verify_neg(bl)[1] == 'grep -n "coerce_to_array" scripts/battle/damage.gd', R.bare_verify_neg(bl))
ok("... with polarity neg / grep", E.verify_clause_and_polarity(bl) == ('grep -n "coerce_to_array" scripts/battle/damage.gd', "neg") and E.verify_tool_class('grep -n x f') == "grep")
ok("NEGATIVE: bare runner + 'fails' is not read", R.bare_verify_neg("- [ ] [T2] a — b. VERIFY: pytest tests/x.py fails. (cat:py)") is None)
ok("NEGATIVE: backticked clause is not a bare clause", R.bare_verify_neg(it('`grep x f` returns no results.')) is None)
tf = os.path.join(d, "prog.md")
with open(tf, "w") as f:
    f.write(bl + "\n")
out = subprocess.run([sys.executable, os.path.join(HERE, "..", "ovn_credit_items.py"), "bare-verify", tf, "1"], capture_output=True, text=True).stdout.strip()
ok("ovn_credit_items.py bare-verify prints the command", out == 'grep -n "coerce_to_array" scripts/battle/damage.gd', out)
out = subprocess.run([sys.executable, os.path.join(HERE, "..", "ovn_credit_items.py"), "polarity", tf, "1"], capture_output=True, text=True).stdout.strip()
ok("ovn_credit_items.py polarity prints `neg grep`", out == "neg grep", out)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
