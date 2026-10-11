#!/usr/bin/env python3
"""ovn_work_supply.c_gd_docs gate (2026-10-10, package docexec, analysis[5] B3): the gd-missing-doc family is supplied to the model path ONLY when something other than the 27B's
positional udiff guards the result: the deterministic executor ON for the repo (env or state/executor_mode), OR the net-diff post-check ENFORCED, OR the explicit
OVN_SUPPLY_GD_DOCS_MODEL=on override. Before this, OVN_SUPPLY_GD_DOCS=on alone fed the model (credited 12 of 57 doc commits, orphan/duplicate blocks left behind)."""
import io
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "scripts", "ovn_work_supply.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


GD = "extends Node\nfunc do_it(x):\n\tvar a = 1\n\tvar b = 2\n\tvar c = 3\n\tvar e = 4\n\treturn a\n"
KEYS = ("OVN_SUPPLY_GD_DOCS", "OVN_SUPPLY_GD_DOCS_MODEL", "OVN_DOC_EXECUTOR", "OVN_DOC_POSTCHECK", "OVN_DIR")


def load(path, ovn_dir):
    import importlib.util
    os.environ["OVN_DIR"] = ovn_dir
    spec = importlib.util.spec_from_file_location("ws_%d" % abs(hash(path + ovn_dir)), path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def battery(path, tag):
    f0 = F
    tmp = tempfile.mkdtemp(prefix="sg-")
    repo = os.path.join(tmp, "xlite")
    os.makedirs(os.path.join(repo, "scripts"))
    open(os.path.join(repo, "scripts", "a.gd"), "w").write(GD)
    od = os.path.join(tmp, "ovn")
    os.makedirs(os.path.join(od, "state"))
    m = load(path, od)

    def run(env, mode_file=None):
        for k in KEYS:
            if k != "OVN_DIR":
                os.environ.pop(k, None)
        os.environ.update(env)
        mf = os.path.join(od, "state", "executor_mode")
        if os.path.exists(mf):
            os.remove(mf)
        if mode_file is not None:
            open(mf, "w").write(mode_file)
        err = io.StringIO()
        old = sys.stderr
        sys.stderr = err
        try:
            specs = list(m.c_gd_docs(repo))
        finally:
            sys.stderr = old
        return specs, err.getvalue()

    s, e = run({})
    ok("%s: family off by default => nothing, silent" % tag, s == [] and e == "", (s, e))
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on"})
    ok("%s: OVN_SUPPLY_GD_DOCS=on alone (executor shadow, post-check shadow) => NOTHING supplied, and stderr says why" % tag, s == [] and "not supplying model-path doc items" in e and "executor is shadow" in e, (s, e))
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_DOC_EXECUTOR": "on"})
    ok("%s: ... with OVN_DOC_EXECUTOR=on => the gap is supplied" % tag, len(s) == 1 and s[0]["kind"] == "gd-missing-doc", s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on"}, "doc:xlite=on\n")
    ok("%s: ... with state/executor_mode doc:xlite=on (no env) => supplied" % tag, len(s) == 1, (s, e))
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on"}, "doc:billwatch=on\n")
    ok("%s: ... with the ON line for ANOTHER repo => not supplied" % tag, s == [], s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on"}, "doc=on\n")
    ok("%s: ... with a repo-less 'doc=on' => supplied" % tag, len(s) == 1, s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_DOC_EXECUTOR": "off"}, "doc=on\n")
    ok("%s: env OVN_DOC_EXECUTOR=off beats the file's ON => not supplied (kill switch)" % tag, s == [], s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_DOC_EXECUTOR": "shadow"}, "doc=on\n")
    ok("%s: an explicit shadow in the (cron) environment beats the file too => not supplied" % tag, s == [], s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_DOC_POSTCHECK": "enforce"})
    ok("%s: post-check ENFORCED guards the model path => supplied" % tag, len(s) == 1, (s, e))
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_DOC_POSTCHECK": "shadow"})
    ok("%s: post-check only in shadow does not guard anything => not supplied" % tag, s == [], s)
    s, e = run({"OVN_SUPPLY_GD_DOCS": "on", "OVN_SUPPLY_GD_DOCS_MODEL": "on"})
    ok("%s: OVN_SUPPLY_GD_DOCS_MODEL=on is the explicit override => supplied" % tag, len(s) == 1, s)
    s, e = run({"OVN_SUPPLY_GD_DOCS_MODEL": "on", "OVN_DOC_EXECUTOR": "on"})
    ok("%s: the override does not switch the family on by itself (OVN_SUPPLY_GD_DOCS still off => nothing)" % tag, s == [], s)
    shutil.rmtree(tmp, ignore_errors=True)
    return F - f0


bad = battery(SRC, "real")
ok("real collector passes the whole battery", bad == 0, bad)
src = open(SRC).read()
MUTANTS = [
    ("gate removed (OVN_SUPPLY_GD_DOCS=on alone feeds the model again)", 'if doc_executor_mode(root) != "on" and os.environ.get("OVN_DOC_POSTCHECK", "shadow") != "enforce" \\', 'if False and os.environ.get("OVN_DOC_POSTCHECK", "shadow") != "enforce" \\'),
    ("post-check shadow counts as a guard", 'os.environ.get("OVN_DOC_POSTCHECK", "shadow") != "enforce" \\', 'os.environ.get("OVN_DOC_POSTCHECK", "shadow") == "off" \\'),
    ("model override ignored", 'and os.environ.get("OVN_SUPPLY_GD_DOCS_MODEL", "off").lower() not in ("on", "1", "true", "yes"):', "and True:"),
    ("env ignored in doc_executor_mode", 'm = (os.environ.get("OVN_DOC_EXECUTOR") or "").strip()', 'm = ""'),
    ("state file ignored in doc_executor_mode", 'for ln in open(os.path.join(OVN_DIR, "state", "executor_mode"), encoding="utf-8", errors="replace"):', 'for ln in []:'),
    ("repo-specific line applies to every repo", 'if k == "doc:" + repo:', 'if k.startswith("doc:"):'),
]
tmpd = tempfile.mkdtemp(prefix="sg-mut-")
for name, old, new in MUTANTS:
    if src.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src.count(old))
        continue
    mp = os.path.join(tmpd, "ovn_work_supply.py")
    open(mp, "w").write(src.replace(old, new))
    p_, f_ = P, F
    so = sys.stdout
    sys.stdout = io.StringIO()
    try:
        b = battery(mp, "mutant")
    finally:
        sys.stdout = so
    P, F = p_, f_
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, b), b > 0)
shutil.rmtree(tmpd, ignore_errors=True)
print("docexec_supply_gate: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
