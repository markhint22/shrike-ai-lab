#!/usr/bin/env python3
"""Z1 (2026-11-07): VERIFY shape linter rules Q1 / G1 / P1 / R1 (ovn_verify_shape_lint.py) + their enforcement policy.

  Q1  `grep -q X f | wc -l | grep -q N`   quiet producer feeding a pipe        (xlite tutorial_overlay: 5 FAIL rows)
  G1  `grep -n A f | grep -A2 -B2 B`      context flags on the 2nd grep        (billwatch tone filter, gitlark remove_tag ...)
  P1  `python -c "...; try: ...; except"` compound statement after `;`         (TAA validate_plan, iptv profile schemas ...)
  R1  `python -c "from app..."`           import root that exists nowhere in the repo

Behavioural: every flagged clause is RUN in a sandbox and must really fail, the Q1 rewrite must really pass/fail with the count. Mutants: each rule removed from _RULES, the policy
defaults flipped, the enforce promotion removed -> the --core assertions must go red (= the old behaviour). The wrapper test_z1_verify_lint.sh gives it a fail-closed private TMPDIR."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.environ.get("VSL_DIR") or os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import tmp_track  # noqa: E402
tmp_track.install()
sys.path.insert(0, SD)
import ovn_verify_shape_lint as L  # noqa: E402

CORE_ONLY = "--core" in sys.argv
PASS = FAIL = 0
for _k in [k for k in os.environ if k.startswith("OVN_VERIFY_")]:
    del os.environ[_k]   # a clean policy baseline: only the module defaults


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS " + name)
    else:
        FAIL += 1
        print("  FAIL %s %s" % (name, extra))


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def codes(clause, tree=None, item=None):
    return [f["code"] for f in L.lint_verify(clause, tree, item)["findings"] if f["class"] != L.OK]


def sh(clause, cwd):
    r = subprocess.run(["bash", "-c", clause], cwd=cwd, capture_output=True, text=True, timeout=30)
    return r.returncode, (r.stdout + r.stderr)


T = tempfile.mkdtemp(prefix="z1-lint-")
mk(T, "scripts/tutorial/tutorial_overlay.gd", "func a():\n    _next_button.grab_focus.call_deferred()\nfunc b():\n    _next_button.grab_focus.call_deferred()\n")
mk(T, "billwatch-backend/app/services/llm_service.py", "def f():\n    return None\n\ndef filter_comment_tone(x):\n    return x\n")
mk(T, "billwatch-backend/app/__init__.py", "")
mk(T, "backend/app/routers/ctl.py", "def promote(plan):\n    state = 1\n    return state\n\ndef other():\n    db.commit()\n")
mk(T, "same/line.py", "x = 1  # tone\nreturn None  # filter_comment_tone\n")

Q1 = 'grep -q "_next_button.grab_focus.call_deferred" scripts/tutorial/tutorial_overlay.gd | wc -l | grep -q 2'
G1 = 'grep -n "commit" backend/app/routers/ctl.py | grep -A2 -B2 promote'
G1B = 'grep -n "return None" billwatch-backend/app/services/llm_service.py | grep -A2 -B2 "filter_comment_tone"'
P1 = 'python3 -c "from app.services.test_plan_validation import validate_plan; try: validate_plan({}); print(1) except ValueError: print(2)"'
R1 = 'python3 -c "from app.models import Thing; print(Thing)"'

print("== Q1")
r = L.lint_verify(Q1, T)
ok("Q1 the real xlite clause is UNSATISFIABLE/Q1", r["class"] == L.UNSAT and [f["code"] for f in r["findings"]] == ["Q1"], r)
rw = r["findings"][0]["rewrite"] if r["findings"] else None
ok("Q1 rewrite is the exact count test", rw == 'test "$(grep -c "_next_button.grab_focus.call_deferred" scripts/tutorial/tutorial_overlay.gd)" -eq 2', rw)
rc0, _ = sh(Q1, T)
ok("Q1 behaviour: the ORIGINAL clause fails although the file holds exactly 2 matching lines (proof it cannot pass)", rc0 != 0)
ok("Q1 behaviour: the rewrite PASSES on 2 matching lines", bool(rw) and sh(rw, T)[0] == 0)
mk(T, "one.gd", "x_call\n")
ok("Q1 behaviour: the rewrite FAILS on 1 matching line (still a real check)", bool(rw) and sh(rw.replace("scripts/tutorial/tutorial_overlay.gd", "one.gd").replace('"_next_button.grab_focus.call_deferred"', "x_call"), T)[0] != 0)
ok("Q1 no tree needed", codes(Q1) == ["Q1"])
ok("Q1 `| wc -l | grep -q 0` stays silent (matches the `0` wc prints)", codes("grep -q X f | wc -l | grep -q 0") == [])
ok("Q1 `grep -q X f | grep -q Y` flagged (empty input)", codes("grep -q X f | grep -q Y") == ["Q1"])
ok("Q1 negated pipeline `! grep -q X f | grep -q Y` stays silent", codes("! grep -q X f | grep -q Y") == [])
ok("Q1 `grep -c X f | grep -q 2` (a counting producer) stays silent", codes("grep -c X f | grep -q 2") == [])
ok("Q1 `grep -q X f && grep -q Y f` stays silent", codes("grep -q X f && grep -q Y f") == [])
ok("Q1 an `||` clause stays silent (status not decided by the pipe)", "Q1" not in codes("grep -q X f | grep -q Y || echo ok"))
ok("Q1 consumer `grep -v` is satisfiable on empty input: silent", codes("grep -q X f | grep -qv Y") == [])
ok("Q1 non-quiet producer stays silent", codes("grep -n X f | wc -l | grep -q 2") == [])

print("== P1")
r = L.lint_verify(P1)
ok("P1 the TAA validate_plan clause is UNRUNNABLE/P1, no rewrite", r["class"] == L.UNRUN and [f["code"] for f in r["findings"]] == ["P1"] and r["findings"][0]["rewrite"] is None, r)
rcp, outp = sh('python3 -c "x=1; for i in range(2): pass"', T)
ok("P1 behaviour: such a clause really dies with SyntaxError", rcp != 0 and "SyntaxError" in outp, outp[-200:])
ok("P1 `; for` / `; with` / `; if` / `; while` flagged", all(codes('python3 -c "x=1; %s"' % k) == ["P1"] for k in ("for i in y: pass", "with a as b: pass", "if x: pass", "while 0: pass")))
ok("P1 a `;` inside a string literal is fine", codes("python3 -c \"print('a; try: b')\"") == [])
ok("P1 plain `a; b; c` is fine", codes('python3 -c "import os; x=1; print(x)"') == [])
ok("P1 ternary `if` after an expression is fine", codes('python3 -c "x=1; y = 2 if x else 3; print(y)"') == [])
ok("P1 `;` inside a string literal followed by `if` is not a finding (other syntax errors are not P1)", codes('python3 -c "x = \'a;\' if True else 0; y = = 1"') == [])
ok("P1 only python -c stages (a grep PATTERN may contain `; try:`)", codes("grep -q 'a; try: b' f") == [])
ok("P1 a multi-line -c body (try on its own line) is fine", codes('python3 -c "import os\ntry:\n    os.getcwd()\nexcept OSError:\n    pass"') == [])

print("== G1")
r = L.lint_verify(G1, T)
ok("G1 billwatch clause flagged with tree evidence (no line holds both patterns)", [f["code"] for f in r["findings"]] == ["G1"] and r["class"] == L.UNSAT, r)
ok("G1 behaviour: the clause fails against the file", sh(G1, T)[0] != 0)
ok("G1 also fires on the billwatch tone-filter clause (alongside S1)", "G1" in codes(G1B, T))
ok("G1 silent without a tree", "G1" not in codes(G1))
ok("G1 silent when one line DOES carry both patterns", "G1" not in codes('grep -n "return None" same/line.py | grep -A2 -B2 "filter_comment_tone"', T))
ok("G1 silent when the second grep has no context flags", "G1" not in codes('grep -n "commit" backend/app/routers/ctl.py | grep promote', T))
ok("G1 silent on a recursive/multi-file first grep (path prefix)", "G1" not in codes('grep -rn "commit" backend | grep -A2 -B2 promote', T))
ok("G1 silent with -H (the path prefix `backend/app/routers/...` can satisfy the 2nd grep)", "G1" not in codes('grep -nH "commit" backend/app/routers/ctl.py | grep -A1 routers', T))
ok("G1 silent when the item adds the 2nd pattern to a line that carries the 1st", "G1" not in codes('grep -n "commit" backend/app/routers/ctl.py | grep -A1 promote', T,
   item='- [ ] [T1] x.py - append `db.commit()  # promote` VERIFY: `grep -n "commit" backend/app/routers/ctl.py | grep -A1 promote`'))

print("== R1")
mk(T, "py_only/x.py", "x = 1\n")
T2 = tempfile.mkdtemp(prefix="z1-lint-r1-")
mk(T2, "lib/util.py", "x = 1\n")
r = L.lint_verify(R1, T2)
ok("R1 `from app...` flagged when `app` exists nowhere", [f["code"] for f in r["findings"]] == ["R1"] and r["class"] == L.UNRUN, r)
ok("R1 behaviour: the clause dies with ModuleNotFoundError", "ModuleNotFoundError" in sh(R1, T2)[1])
ok("R1 silent when app/ exists somewhere (the runner's py-root retry finds it)", codes(R1, T) == [] and codes(R1, T) == [])
T3 = tempfile.mkdtemp(prefix="z1-lint-r1b-")
mk(T3, "svc/app/__init__.py", "")
mk(T3, "svc/app/models.py", "Thing = 1\n")
ok("R1 silent when the package lives under a sub-dir", codes(R1, T3) == [])
ok("R1 silent when the tree has no python at all", codes(R1, tempfile.mkdtemp(prefix="z1-lint-r1c-")) == [])
ok("R1 silent when the clause edits sys.path", codes('python3 -c "import sys; sys.path.insert(0, \'x\'); from app.models import Thing"', T2) == [])
ok("R1 silent when the item creates the root", codes(R1, T2, item="- [ ] [T1] app/models.py - NEW model. VERIFY: `%s`" % R1) == [])
ok("R1 silent for third-party/stdlib roots", codes('python3 -c "import fastapi, json; print(1)"', T2) == [])
ok("R1 silent without a tree", codes(R1) == [])

print("== policy (defaults, switches, enforce promotion)")
ok("policy defaults: P1 enforce; Q1 (review 2026-11-07), G1 + R1 shadow", {c: L.z1_mode(c) for c in ("Q1", "G1", "P1", "R1")} == {"Q1": "shadow", "G1": "shadow", "P1": "enforce", "R1": "shadow"})
ok("policy: per-rule env override beats the default", (lambda: (os.environ.__setitem__("OVN_VERIFY_Z1_Q1", "enforce"), L.z1_mode("Q1"))[1])() == "enforce")
del os.environ["OVN_VERIFY_Z1_Q1"]
os.environ["OVN_VERIFY_Z1"] = "shadow"
ok("policy: group switch shadows every rule", all(L.z1_mode(c) == "shadow" for c in ("Q1", "G1", "P1", "R1")))
os.environ["OVN_VERIFY_Z1"] = "off"
ok("policy: group switch off removes the findings", codes(Q1) == [] and codes(P1) == [])
del os.environ["OVN_VERIFY_Z1"]
item_q = "- [ ] [T1] scripts/tutorial/tutorial_overlay.gd - guard focus. VERIFY: `%s` (cat:godot)" % Q1
item_p = "- [ ] [T1] backend/app/x.py - validate. VERIFY: `%s` (cat:test)" % P1
item_g = "- [ ] [T1] backend/app/routers/ctl.py - promote. VERIFY: `%s` (cat:test)" % G1
d, out, _ = L.lint_item_line(item_q, T, "shadow")
ok("Q1 default (shadow): flagged, the item text is UNCHANGED", d == "flagged" and out == item_q, d)
os.environ["OVN_VERIFY_Z1_Q1"] = "enforce"
d, out, _ = L.lint_item_line(item_q, T, "shadow")
ok("enforced Q1 REWRITES the item even while OVN_VERIFY_LINT=shadow", d == "rewritten" and '-eq 2' in out and "| wc" not in out, (d, out))
d, out, _ = L.lint_item_line(item_p, None, "shadow")
ok("enforced P1 DROPS (quarantines) the item even while OVN_VERIFY_LINT=shadow", d == "dropped" and out == item_p, d)
d, out, _ = L.lint_item_line(item_g, T, "shadow")
ok("shadow-default G1 is only flagged: text unchanged", d == "flagged" and out == item_g, d)
d, out, _ = L.lint_item_line(item_g, T, "enforce")
ok("G1 stays flag-only under OVN_VERIFY_LINT=enforce while its own switch is shadow", d == "flagged" and out == item_g, d)
os.environ["OVN_VERIFY_Z1_G1"] = "enforce"
d, out, _ = L.lint_item_line(item_g, T, "shadow")
ok("G1 promoted by its own switch: dropped (no rewrite exists)", d == "dropped", d)
del os.environ["OVN_VERIFY_Z1_G1"]
os.environ["OVN_VERIFY_Z1_Q1"] = "shadow"
d, out, _ = L.lint_item_line(item_q, T, "shadow")
ok("Q1 explicitly shadow: flagged, unchanged", d == "flagged" and out == item_q, d)
os.environ["OVN_VERIFY_Z1_Q1"] = "enforce"   # the visibility block below exercises an ENFORCED Q1 rewrite
# visibility: JSON row + alerts line + stderr line for an enforced Z1 action
LOG = os.path.join(T, "state", "verify_shape_lint.log")
os.environ["OVN_VERIFY_SHAPE_LOG"] = LOG
os.environ["OVN_VERIFY_ALERTS_LOG"] = os.path.join(T, "state", "alerts.log")
import io, contextlib
err = io.StringIO()
with contextlib.redirect_stderr(err):
    kept, dropped, nflag = L.process_lines([item_q, item_p, "- [ ] [T1] a.py - ok. VERIFY: `true` (cat:test)"], T, "z1repo", "unit", "shadow")
rows = [json.loads(x) for x in open(LOG)]
ok("visible: kept = rewritten Q1 + untouched ok item; P1 dropped", len(kept) == 2 and len(dropped) == 1 and nflag == 2, (len(kept), len(dropped)))
ok("visible: one JSON row per action with the code and decision", sorted((x["codes"][0], x["decision"]) for x in rows) == [("P1", "dropped"), ("Q1", "rewritten")], rows)
ok("visible: stderr line per enforced Z1 action", err.getvalue().count("verify-lint(Z1):") == 2 and "DROPPED" in err.getvalue() and "REWRITTEN" in err.getvalue(), err.getvalue())
AL = open(os.path.join(T, "state", "alerts.log")).read()
ok("visible: alerts.log summary says mode=enforce (not shadow) when Z1 rewrote/dropped, level warn", "mode=enforce" in AL and "mode=shadow" not in AL and " warn " in AL and "1 rewritten, 1 dropped" in AL, AL)
ok("visible: every row says mode=enforce and carries the ITEM line, not just the clause", all(x["mode"] == "enforce" and x["item"].startswith("- [ ] [T1]") for x in rows), rows)
QF = os.path.join(T, "state", "verify_lint_quarantine.md")
ok("visible: process_lines wrote a quarantine row (whole item + code + repo/where) for the drop", os.path.isfile(QF) and item_p in open(QF).read() and "verify-lint:P1 z1repo unit" in open(QF).read())
# a shadow-only flag still logs mode=shadow (no enforcement happened)
os.environ["OVN_VERIFY_Z1_Q1"] = "shadow"
open(os.path.join(T, "state", "alerts.log"), "w").close()
L.process_lines([item_q], T, "z1repo", "unit2", "shadow")
AL2 = open(os.path.join(T, "state", "alerts.log")).read()
ok("visible: a flag-only run still says mode=shadow / info", "mode=shadow" in AL2 and " info " in AL2 and "mode=enforce" not in AL2, AL2)
os.environ["OVN_VERIFY_Z1_Q1"] = "enforce"
# the OTHER drop paths: work_supply._shape_lint_keep and generate_items._lint_block must also quarantine + stderr + say enforce
import ovn_work_supply as WS
import ovn_generate_items as GI
os.remove(QF)
open(os.path.join(T, "state", "alerts.log"), "w").close()
err = io.StringIO()
with contextlib.redirect_stderr(err):
    kk = WS._shape_lint_keep([("spec", item_p, "v"), ("spec2", "- [ ] [T1] a.py - ok. VERIFY: `true` (cat:test)", "v")], T, "wsrepo")
ok("work_supply path: P1 item dropped, ok item kept", len(kk) == 1 and kk[0][0] == "spec2", kk)
ok("work_supply path: quarantine row with the item", os.path.isfile(QF) and item_p in open(QF).read() and "wsrepo work_supply" in open(QF).read())
ok("work_supply path: stderr line + alerts says enforce", "verify-lint(Z1): DROPPED" in err.getvalue() and "mode=enforce" in open(os.path.join(T, "state", "alerts.log")).read(), err.getvalue())
os.remove(QF)
err = io.StringIO()
blk = "## Next Steps\n" + item_p + "\n- [ ] [T1] a.py - ok. VERIFY: `true` (cat:test)\n"
with contextlib.redirect_stderr(err):
    nb, nn = GI._lint_block(blk, 2, T)
ok("generate_items path: P1 item removed from the block", item_p not in nb and nn == 1, (nb, nn))
ok("generate_items path: quarantine row + stderr line", os.path.isfile(QF) and item_p in open(QF).read() and "verify-lint(Z1): DROPPED" in err.getvalue())
for k in ("OVN_VERIFY_SHAPE_LOG", "OVN_VERIFY_ALERTS_LOG", "OVN_VERIFY_Z1_Q1"):
    del os.environ[k]

print("== Q1 review-fix: regex translation, -f, rewrite scope")
ok("Q1 POSIX class pattern (satisfiable: grep matches `0`) is NOT flagged", codes("grep -q X f | wc -l | grep -q '^[[:digit:]]$'") == [])
ok("Q1 `[[:space:]]*0*$` style pattern is NOT flagged", codes("grep -q X f | wc -l | grep -q '^[[:space:]]*0*$'") == [])
rcp, _ = sh("printf 'x\\n' > /dev/null; echo 0 | grep -q '^[[:digit:]]$'", T)
ok("Q1 behaviour: that POSIX-class grep really matches `0` (so flagging it would have been a FP)", rcp == 0)
ok("Q1 `| grep -q -f pats` is NOT flagged (pattern file may match 0)", codes("grep -q X f | wc -l | grep -q -f pats") == [] and codes("grep -q X f | grep -q --file=pats") == [] and codes("grep -q X f | wc -l | grep -q --file pats") == [])
ok("Q1 `grep -q -f pats f | wc -l | grep -q 2` is NOT flagged either", codes("grep -q -f pats f | wc -l | grep -q 2") == [])
ok("Q1 GNU `\\<` word escape (python mistranslates) is NOT flagged", codes("grep -q X f | wc -l | grep -q '\\<0\\>'") == [])
def q1rw(c):
    fs = [f for f in L.lint_verify(c, T)["findings"] if f["code"] == "Q1"]
    return (bool(fs), fs[0].get("rewrite") if fs else None)
ok("Q1 -o: still flagged but NO rewrite (-c counts lines, not occurrences)", q1rw("grep -q -o X f | wc -l | grep -q 3") == (True, None))
ok("Q1 -w / -x / -c / -m: flagged, no rewrite", all(q1rw(c) == (True, None) for c in ("grep -q -w X f | wc -l | grep -q 3", "grep -q -x X f | wc -l | grep -q 3", "grep -q -m 5 X f | wc -l | grep -q 3")))
ok("Q1 plain -i single-file case is still rewritten (documented as EXACTLY N lines)", q1rw("grep -q -i X f | wc -l | grep -q 3")[1] == 'test "$(grep -c -i X f)" -eq 3')
ok("Q1 non-integer N (`2.`, `[0-9]`) is flagged but not rewritten", q1rw("grep -q X f | wc -l | grep -q '2.'") == (True, None) or q1rw("grep -q X f | wc -l | grep -q '2.'") == (False, None))
ok("Q1 finding reason documents the exact-N rewrite semantics", "EXACTLY" in L.lint_verify("grep -q X f | wc -l | grep -q 3", T)["findings"][0]["reason"])

if CORE_ONLY:
    print("z1 lint core: pass=%d fail=%d" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)

print("== mutants (the core assertions must go red on each; = the old behaviour)")
SRC = open(os.path.join(SD, "ovn_verify_shape_lint.py")).read()
MUT = [
    ("Q1 rule removed", "_rule_quiet_pipe, _rule_grep_context", "_rule_grep_context"),
    ("G1 rule removed", "_rule_grep_context, _rule_semicolon_compound", "_rule_semicolon_compound"),
    ("P1 rule removed", "_rule_semicolon_compound, _rule_import_root_missing)", "_rule_import_root_missing)"),
    ("R1 rule removed", "_rule_semicolon_compound, _rule_import_root_missing)", "_rule_semicolon_compound)"),
    ("Q1 fires on `| grep -q 0`", "if rx is None or rx.search(\"0\") or rx.search(\" 0\") or rx.search(\"0\\n\"):", "if rx is None:"),
    ("Q1 ignores negation / || (status not decided by the pipe)", "if not _stage_ops_plain(stages):\n        return out\n    for pl in pls:\n        if len(pl) < 3", "if False:\n        return out\n    for pl in pls:\n        if len(pl) < 3"),
    ("Q1 rewrite dropped", "if s1 != pl[0][1] and not re.search", "if False and not re.search"),
    ("P1 counts `;` inside strings", "if t.type == tokenize.OP and t.string == \";\":", "if t.string == \";\" or \";\" in t.string:"),
    ("G1 fires when a line carries both patterns", "if any(rx1.search(l) and rx2.search(l) for l in lines):\n                continue", "if False:\n                continue"),
    ("G1 fires on recursive greps", "if _multi_path_grep(g1, tree) or g1[\"ctx\"]", "if g1[\"ctx\"]"),
    ("R1 fires when the package exists elsewhere", "if root in dns or (root + \".py\") in fns:\n            return True", "if False:\n            return True"),
    ("R1 fires when the item creates the root", "                continue   # the item names a path under that root", "                pass   # the item names a path under that root"),
    ("policy: Q1 default enforce", 'Z1_DEFAULT = {"Q1": "shadow"', 'Z1_DEFAULT = {"Q1": "enforce"'),
    ("Q1 POSIX-class guard + python-warning guard removed", ['and "F" not in flags and "--fixed-strings" not in long_:', 'warnings.simplefilter("error")'], ['and False:', 'warnings.simplefilter("ignore")']),
    ("-f no longer aborts the grep parse", 'if ch == "f":\n                    return None', 'if ch == "f":\n                    break'),
    ("--file no longer aborts the grep parse", 'elif t == "--file" or t.startswith("--file="):\n                return None', 'elif t == "--file" or t.startswith("--file="):\n                long_.add(t)'),
    ("Q1 rewrite applied to -o/-w/-x/-m", 'plain_flags = g0["flags"] <= set("qiEFsn") and g0["long"] <=', 'plain_flags = True or g0["long"] <='),
    ("alerts/rows say shadow when Z1 acted", '"mode": "enforce" if d in ("rewritten", "dropped") else md', '"mode": md'),
    ("alerts summary keeps the old shadow wording", "    if acted:\n        nrw,", "    if False:\n        nrw,"),
    ("rows lose the item line", '"item": ln[:400],', ''),
    ("quarantine row not written", '_append(_quarantine_path(), "%s  <!-- verify-lint', '(lambda *a: None)(_quarantine_path(), "%s  <!-- verify-lint'),
    ("work_supply path does not notify/quarantine", 'vsl.note_decision(l, d, res, repo, "work_supply")', 'pass', "ovn_work_supply.py"),
    ("policy: P1 default shadow", '"P1": "enforce"', '"P1": "shadow"'),
    ("policy: G1 default enforce", '"G1": "shadow"', '"G1": "enforce"'),
    ("enforced Z1 does not promote past OVN_VERIFY_LINT=shadow", "if (u4e and codes == {\"U4\"}) or (z1e and bad_codes", "if (u4e and codes == {\"U4\"}) or (False and bad_codes"),
    ("per-rule env switch ignored", 'for var in ("OVN_VERIFY_Z1_" + code, "OVN_VERIFY_Z1"):', 'for var in ("OVN_VERIFY_Z1",):'),
    ("Z1 enforcement is silent (no stderr line)", "sys.stderr.write(\"verify-lint(Z1):", "(lambda *a: None)(\"verify-lint(Z1):"),
]
FILES = ("ovn_verify_shape_lint.py", "ovn_work_supply.py", "ovn_generate_items.py")
for ent in MUT:
    name, old, new = ent[:3]
    target = ent[3] if len(ent) > 3 else "ovn_verify_shape_lint.py"
    src = open(os.path.join(SD, target)).read()
    olds, news = (old, new) if isinstance(old, list) else ([old], [new])
    if any(o not in src for o in olds):
        ok("[mut] %s: hunk present in source" % name, False, olds)
        continue
    md = tempfile.mkdtemp(prefix="z1-mut-")
    for fn in FILES:
        open(os.path.join(md, fn), "w").write(open(os.path.join(SD, fn)).read())
    for o, n in zip(olds, news):
        src = src.replace(o, n, 1)
    open(os.path.join(md, target), "w").write(src)
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "--core"], capture_output=True, text=True, env=dict(os.environ, VSL_DIR=md), timeout=300)
    ok("[mut] %s -> core goes red" % name, r.returncode != 0)
    tmp_track.sweep()

print("z1 lint: pass=%d fail=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
