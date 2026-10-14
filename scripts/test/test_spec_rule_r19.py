#!/usr/bin/env python3
"""R19 (spec-intake-5-lanes, 2026-10-13): a VERIFY names `pytest <file>::<name>` / `-k <name>` where <name> is not defined in <file> at the ref and the item does not touch <file>.

Replay of the 16 rows / 947k tokens of pytest rc 4/5 'not found': shrike-monitor T1 `_safe_tick_monitor` names test_safe_tick_monitor_catches_exception, which a LATER item of the same [feat]
batch adds (7 of the 15 distinct node ids exist on overnight/feature now). The rule is evidence-first: SHADOW (default) only flags and carries the proposal; a later sibling = a HOLD
(evidence.action = hold, reorder, R14 machinery); otherwise the proposal is `pytest <file> -q`, NEVER applied (repair mode is refused: the whole-file run is green before the work). An item that edits <file> itself defines the name and is never judged.
All repository reads are at a ref; the fixture working tree is dirtied to prove it is never read."""
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
import ovn_spec_gate as G  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


FILES = {
    "monitor/app.py": "def tick():\n    return 1\n",
    "monitor/tests/test_monitor.py": ("import pytest\n\ndef test_other():\n    assert True\n\nclass TestX:\n    def test_method(self):\n        assert True\n\n"
                                      "@pytest.mark.parametrize('case', ['alpha_case', 'beta_case'])\ndef test_param(case):\n    assert case\n"),
    "monitor/tests/test_second.py": "def test_second():\n    assert True\n",
    "monitor/tests/test_broken.py": "def test_x(:\n",
    "backend/tests/test_stale.py": "def test_find_stale_run_ids_returns_old_running_runs():\n    assert True\n",
}
work = os.path.realpath(tempfile.mkdtemp(prefix="r19-"))
repo = os.path.join(work, "repo")
os.makedirs(repo)
git = lambda *a: subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True)  # noqa: E731
git("init", "-q")
git("checkout", "-q", "-b", "main")
for rp, body in FILES.items():
    fp = os.path.join(repo, rp)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    open(fp, "w").write(body)
git("add", "-A")
subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"], capture_output=True)
open(os.path.join(repo, "monitor/tests/test_monitor.py"), "a").write("def test_worktree_only():\n    pass\n")      # never seen: reads are at the ref
ctx = R.Ctx(repo, "main")
for k in ("OVN_SPEC_R18", "OVN_SPEC_R19", "OVN_SPEC_GATE_ENFORCE_RULES"):
    os.environ.pop(k, None)

FEAT = "shrike-monitor-20261013-safe-tick"
TM = "monitor/tests/test_monitor.py"


def item(target, text, verify, feat=None):
    s = "- [ ] [T2] %s — %s VERIFY: %s (cat:test; multifile:no)" % (target, text, verify)
    return s + (" [feat:%s]" % feat if feat else "")


def pt(node, extra=""):
    return "`pytest %s%s -q`." % (node, extra)


def r19(lines, i, c=ctx):
    parsed = [R.parse(l) if E.is_open_item(l) else None for l in lines]
    return R._r19(i, parsed, lines, c)


def only(lines, i=0, c=ctx):
    return r19(lines, i, c)[0]


print("== node defined at the ref -> no flag")
for name, v in (("function", pt(TM + "::test_other")), ("method through its class", pt(TM + "::TestX::test_method")), ("the class alone", pt(TM + "::TestX")),
                ("parametrize id suffix is stripped", pt(TM + "::test_param[alpha_case]")), ("-k naming a defined test", pt(TM, " -k test_other")),
                ("-k substring of a defined test", pt(TM, " -k other")), ("-k naming a parametrize id", pt(TM, " -k alpha_case")),
                ("-k expression, every ident present", pt(TM, ' -k "test_other or test_param and not beta_case"')), ("whole file, no node", pt(TM)),
                ("python -m pytest form", "`python3 -m pytest %s::test_other -q`." % TM)):
    ok("defined: %s" % name, only([item("monitor/app.py", "Wrap tick in a safe wrapper.", v, FEAT)]) is None, only([item("monitor/app.py", "x.", v, FEAT)]))

print("== a LATER sibling of the same batch creates the node -> HOLD (shrike-monitor T1)")
T1 = item("monitor/app.py", "Add `_safe_tick_monitor` wrapping tick() so an exception is logged instead of killing the loop.", pt(TM + "::test_safe_tick_monitor_catches_exception"), FEAT)
T2 = item(TM, "Add a test test_safe_tick_monitor_catches_exception that patches tick to raise.", pt(TM + "::test_safe_tick_monitor_catches_exception"), FEAT)
f, new = r19([T1, T2], 0)
ok("T1: R19 flag, action hold, creator = item 2, nothing to rewrite", f and f["rule"] == "R19" and f["sev"] == "flag" and f["evidence"]["action"] == "hold" and f["evidence"]["creator_items"] == [2] and new is None, f)
ok("T1: finding shape rule/sev/msg/evidence and the message says move it after", f and set(f) == {"rule", "sev", "msg", "evidence"} and "move this item after" in f["msg"])
ok("T2 (the creator) is never judged: it edits the test file itself", only([T1, T2], 1) is None)
ok("order reversed (creator FIRST): T1 is fine, the queue order lands the test before it", only([T2, T1], 1) is None)
ok("the gate's would_do reads it as hold:R19", G.would_do([f], None) == "hold:R19", G.would_do([f], None))
out = R.lint_batch([T1, T2], ctx)
ok("lint_batch: the hold finding is on item 1 only, lines untouched", [x["rule"] for x in out[0][1] if x["rule"] == "R19"] == ["R19"] and not [x for x in out[1][1] if x["rule"] == "R19"] and out[0][0] == T1)
os.environ["OVN_SPEC_R19"] = "repair"
ok("a hold is never a rewrite, even in repair mode", r19([T1, T2], 0)[1] is None and R.lint_batch([T1, T2], ctx)[0][0] == T1)
os.environ.pop("OVN_SPEC_R19")
T2x = item(TM, "Add a test test_safe_tick_monitor_catches_exception_extra for the wrapper.", pt(TM + "::test_safe_tick_monitor_catches_exception_extra"), FEAT)
f, new = r19([T1, T2x], 0)
ok("a sibling that adds a LONGER name is not the creator (whole-word match): rewrite proposal, not hold", f and f["evidence"]["action"] == "rewrite", f)
T2o = item(TM, "Add a test test_safe_tick_monitor_catches_exception.", pt(TM + "::test_safe_tick_monitor_catches_exception"), "some-other-feat")
f, _ = r19([T1, T2o], 0)
ok("a sibling of ANOTHER feat batch does not count", f and f["evidence"]["action"] == "rewrite", f)

print("== never created, file exists -> rewrite proposal; shadow does NOT mutate")
V = item("monitor/app.py", "Wrap tick() in a safe wrapper.", pt(TM + "::test_never_written"), FEAT)
f, new = r19([V], 0)
ok("shadow: flag, action rewrite, proposal = pytest <file> -q, the line is not touched", f and f["sev"] == "flag" and f["evidence"]["action"] == "rewrite" and f["evidence"]["proposed"] == "pytest %s -q" % TM and new is None, (f, new))
ok("shadow: lint_batch leaves the line byte-identical", R.lint_batch([V], ctx)[0][0] == V and any(x["rule"] == "R19" for x in R.lint_batch([V], ctx)[0][1]))
ok("shadow: would_do is a flag, never a hold", G.would_do([f], None) == "flag:R19", G.would_do([f], None))
os.environ["OVN_SPEC_R19"] = "repair"
f, new = r19([V], 0)
l2 = R.lint_batch([V], ctx)[0][0]
ok("repair mode is REFUSED: still a flag, nothing returned to apply, the line is byte-identical (a whole-file run is green before the work: vacuous VERIFY)", f and f["sev"] == "flag" and new is None and l2 == V, (f, new, l2))
ok("repair mode: the proposal stays in evidence, marked vacuous, and the message says it is never applied", f["evidence"]["proposed"] == "pytest %s -q" % TM and f["evidence"].get("vacuous") is True and "never applied" in f["msg"], f)
ok("repair mode: no R19 finding has sev repair, in any form (cd prefix, -k)", all(x["sev"] != "repair" for v_ in (V, item("monitor/app.py", "Wrap tick().", "`cd monitor && python -m pytest tests/test_monitor.py::test_never_written -x`."), item("monitor/app.py", "Wrap tick().", pt(TM, " -k test_never_written"))) for x in R.lint_batch([v_], ctx)[0][1] if x["rule"] == "R19"))
ok("repair mode: lint_batch never changes any of those lines", all(R.lint_batch([v_], ctx)[0][0] == v_ for v_ in (V, item("monitor/app.py", "Wrap tick().", pt(TM, " -k test_never_written")))))
ok("repair mode: would_do is still only a flag", G.would_do([f], None) == "flag:R19", G.would_do([f], None))
os.environ.pop("OVN_SPEC_R19")

print("== -k, class paths, cd directories")
for name, v in (("-k with a missing ident", pt(TM, " -k test_nope")), ("-k expression, one ident missing", pt(TM, ' -k "test_other or test_nope"')),
                ("class defined, method missing", pt(TM + "::TestX::test_missing")), ("class missing", pt(TM + "::TestY::test_method")),
                ("cd dir + path relative to it", "`cd monitor && pytest tests/test_monitor.py::test_nope -q`."), ("-k=ident form", pt(TM, " -k=test_nope")),
                ("second invocation after &&", "`pytest %s::test_other -q && pytest %s::test_nope -q`." % (TM, TM))):
    f = only([item("monitor/app.py", "Wrap tick().", v, FEAT)])
    ok("flagged: %s" % name, f is not None and f["rule"] == "R19", f)
f = only([item("monitor/app.py", "Wrap tick().", "`pytest %s::test_nope monitor/tests/test_second.py::test_nope2 -q`." % TM, FEAT)])
ok("two different files: flagged, but NO rewrite proposal (action flag)", f and f["evidence"]["action"] == "flag" and f["evidence"]["proposed"] is None, f)

print("== NEGATIVES: the rule says nothing")
NEG = [
    ("the item EDITS the test file (it defines the name)", item(TM, "Add a test for the wrapper.", pt(TM + "::test_brand_new"), FEAT)),
    ("the item creates the file through a Create path in its body", item("monitor/app.py", "Add the wrapper and create monitor/tests/test_monitor.py::test_brand_new coverage in monitor/tests/test_monitor.py.", pt(TM + "::test_brand_new"), FEAT)),
    ("the test file is absent at the ref (R12's business)", item("monitor/app.py", "Wrap tick().", pt("monitor/tests/test_gone.py::test_x"), FEAT)),
    ("the test file does not parse", item("monitor/app.py", "Wrap tick().", pt("monitor/tests/test_broken.py::test_y"), FEAT)),
    ("a VERIFY that is not pytest", item("monitor/app.py", "Wrap tick().", "`grep -q tick monitor/app.py`.", FEAT)),
    ("-k with no file argument (nothing to judge it against)", item("monitor/app.py", "Wrap tick().", "`pytest -k test_nope -q`.", FEAT)),
    ("no VERIFY at all", "- [ ] [T2] monitor/app.py — Wrap tick(). (cat:test; multifile:no)"),
    ("a bare (unbackticked) VERIFY: R01 backticks it first", item("monitor/app.py", "Wrap tick().", "pytest %s::test_nope -q" % TM, FEAT)),
]
for name, l in NEG:
    ok("NEGATIVE %s" % name, r19([l], 0) == (None, None), r19([l], 0))
ok("no ctx (planner / queue_refill static path): nothing", R._r19(0, [R.parse(V)], [V], None) == (None, None))
os.environ["OVN_SPEC_R19"] = "off"
ok("OVN_SPEC_R19=off silences the canonical hold", r19([T1, T2], 0) == (None, None))
os.environ["OVN_SPEC_R19"] = "bogus"
ok("an unknown mode falls back to shadow", r19([V], 0)[0]["sev"] == "flag" and r19([V], 0)[1] is None)
os.environ.pop("OVN_SPEC_R19")
ok("TAA replay: an item that adds the test to the file itself is never judged (the model's name choice is invisible to a static rule)",
   only([item("backend/tests/test_stale.py", "Add a test for find_stale_run_ids.", pt("backend/tests/test_stale.py::test_find_stale_run_ids"), FEAT)]) is None)
ok("R19 is not in any default enforce set", "R19" not in G.DEFAULT_ENFORCE_RULES and "R19" not in __import__("queue_refill").DEFAULT_ENFORCE_RULES and "R19" not in G.HOLD_RULES)
ok("R19 is not static: lint_static never touches it", R.lint_static(V) == (V, []))

shutil.rmtree(work, ignore_errors=True)
print("\nR19: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
