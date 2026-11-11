#!/usr/bin/env python3
"""Q2 VERIFY lint ReDoS hardening: a model-written grep pattern with catastrophic backtracking must not hang ovn_verify_lint.py (rule guard + per-item time budget + size caps ->
verdict 'unknown', never raises), and the ovn_item_guard.sh Q2 hook must run under ovn_hto. Source mutants (each must make run_checks fail)."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "ovn_verify_lint.py")
GUARD = os.path.join(ROOT, "scripts", "ovn_item_guard.sh")
ITEM = "- [ ] do x VERIFY: `grep -E '(a*)*c:\\nreturn' big.txt`"


def load(path, name="ovl"):
    sp = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def run_checks(m, guard_src=None):
    fails = []

    def chk(name, cond):
        if not cond:
            fails.append(name)
    m.BUDGET_S = 1.0
    with tempfile.TemporaryDirectory() as td:
        open(os.path.join(td, "big.txt"), "w").write("a" * 34 + "\n")
        open(os.path.join(td, "long.txt"), "w").write("if foo:" + "x" * 6000 + "\n")
        # 1. end-to-end repro completes quickly and does not raise
        t = time.time()
        try:
            r = m.lint_verify(ITEM, td)
        except BaseException as e:
            r = None
            fails.append("raised:%s" % type(e).__name__)
        chk("repro_under_budget", time.time() - t < 5)
        chk("repro_not_suspect", r is not None and r["verdict"] != "SUSPECT")
        # 2. layer A: nested-quantifier patterns are rejected, ordinary ones are not
        chk("unsafe_nested", m._unsafe_pattern("(a*)*c:"))
        chk("unsafe_alt", m._unsafe_pattern("(a|aa)+c"))
        chk("safe_plain", not m._unsafe_pattern("if foo_ready:"))
        chk("safe_group", not m._unsafe_pattern("(foo)bar"))
        # 3. layer B: with the rule guard disabled the time budget still bounds it and degrades to 'unknown'
        orig = m._unsafe_pattern
        m._unsafe_pattern = lambda p: False
        t = time.time()
        try:
            r = m.lint_verify(ITEM, td)
        except BaseException as e:
            r = None
            fails.append("raised_b:%s" % type(e).__name__)
        el = time.time() - t
        m._unsafe_pattern = orig
        chk("budget_bounds_runtime", el < 5)
        chk("budget_unknown_verdict", r is not None and r["verdict"] == "unknown")
        # 4. line-length cap: a huge line is skipped, so no (false) finding is built from it
        r = m.lint_verify("- [ ] y VERIFY: `grep -E 'if foo:\\nreturn' long.txt`", td)
        chk("long_line_skipped", r["verdict"] == "OK")
        # 5. alarm/deadline state is cleaned up (no stray timer after the call)
        try:
            import signal
            chk("timer_cleared", signal.getitimer(signal.ITIMER_REAL)[0] == 0)
        except Exception:
            pass
        # 6. the hook is wrapped
        gs = guard_src if guard_src is not None else open(GUARD).read()
        chk("hook_wrapped", "ovn_hto 30 verify_lint_park python3 -" in gs)
        chk("hook_shadow_only", "PYQ2' >/dev/null 2>&1 || true" in gs)
    return fails


MUTANTS = [
    ("    return re.search(r\"\\((?:[^()", "    return False and re.search(r\"\\((?:[^()"),                         # rule guard off
    ("signal.setitimer(signal.ITIMER_REAL, BUDGET_S)", "pass"),                                               # no alarm
    ("                    if len(ln) > MAX_LINE:", "                    if False:"),                              # no line cap
    ("    except Budget:\n        return _res(\"unknown\", \"lint-budget-exceeded\")", "    except Budget:\n        return _res(OK, \"x\")"),   # wrong verdict
    ("        if armed:\n            try:\n                signal.setitimer(signal.ITIMER_REAL, 0)", "        if False:\n            try:\n                signal.setitimer(signal.ITIMER_REAL, 0)"),
]


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--run-file":
        f = run_checks(load(sys.argv[2], "mutchild"))
        print("child fails:", f)
        return 1 if f else 0
    fails = ["base:" + f for f in run_checks(load(SRC))]
    for f in fails:
        print("FAIL", f)
    src = open(SRC).read()
    survived = 0
    for i, (old, new) in enumerate(MUTANTS):
        if old not in src:
            print("MUTANT %d: stale" % i)
            fails.append("stale_mutant_%d" % i)
            continue
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "mut.py")
            open(p, "w").write(src.replace(old, new, 1))
            # a mutant that hangs (the very defect) must FAIL the checks, not stall the suite: run it in a child under a hard wall-clock cap
            try:
                cp = subprocess.run([sys.executable, os.path.abspath(__file__), "--run-file", p], timeout=25, capture_output=True, text=True)
                mf = ["rc%d" % cp.returncode] if cp.returncode != 0 else []
            except subprocess.TimeoutExpired:
                mf = ["hung"]
        if not mf:
            survived += 1
            print("MUTANT %d SURVIVED: %s" % (i, old[:60]))
            fails.append("mutant_%d_survived" % i)
    g = open(GUARD).read()
    for j, (old, new) in enumerate([("ovn_hto 30 verify_lint_park python3 -", "python3 -"), ("PYQ2' >/dev/null 2>&1 || true", "PYQ2' >/dev/null 2>&1")]):
        if old not in g:
            fails.append("stale_guard_mutant_%d" % j)
        elif not run_checks(load(SRC), g.replace(old, new, 1)):
            survived += 1
            fails.append("guard_mutant_%d_survived" % j)
    print("q2 verify lint redos: %d failure(s), %d mutants survived" % (len(fails), survived))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
