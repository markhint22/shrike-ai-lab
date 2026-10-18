#!/usr/bin/env python3
"""Regression: the explorer rejected ~all proposals of billwatch/gitlark/TAA/shrike-monitor/shrike-notify as 'verify-dialect' because (a) those repos had dialect=None so the
prompt gave a vague generic line and the 27B echoed its label ('test: cd backend && .venv/bin/pytest -q --no-cov ...'), (b) --no-cov was not allowed.
Live evidence 2026-10-18: 224 passes, 0 accepted, verify-dialect = 42/39/46/25/25 rejects for those repos. Hermetic: imports the script, no network."""
import importlib.util, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "ovn_qwen_explore.py")
fails = []
def ok(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond: fails.append(name)
def load(path):
    spec = importlib.util.spec_from_file_location("qe_dialect_under_test", path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
def checks(m):
    r = {}
    raw = lambda v: {"title": "t", "file": "backend/app/x.py", "symbol": "f", "evidence_quote": "a = 1", "what_is_wrong": "It returns 1.", "proposed_change": "Change it.", "verify": v, "size": "S", "tier": 2}
    def cleaned(v):
        it, why = m.normalise_item(raw(v), "bug-hunt")
        return (it or {}).get("verify", "<%s>" % why)
    live = "test: cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_quiet_hours.py"
    r["label_stripped"] = cleaned(live) == "cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_quiet_hours.py"
    r["no_cov_allowed"] = m.verify_dialect_reason("cd backend && python3 -m pytest -q --no-cov tests/test_a.py") == ""
    r["labelled_pytest_passes"] = m.verify_dialect_reason(cleaned("test: cd backend && python3 -m pytest tests/test_a.py -q")) == ""
    r["test_dash_f_untouched"] = cleaned("test -f backend/tests/test_a.py") == "test -f backend/tests/test_a.py"
    r["still_refuses_chain"] = m.verify_dialect_reason("cd backend && pytest tests/test_a.py -q && rm -rf x") != ""
    for repo in ("billwatch", "gitlark", "test-automation-agent", "shrike-monitor", "shrike-notify"):
        d = m.REPO_CFG[repo]["dialect"] if hasattr(m, "REPO_CFG") else None
        r["dialect_explicit_" + repo] = bool(d) and "python3 -m pytest tests/test_<name>.py" in d and "no 'test:' label" in d
    return r
src = open(SRC).read()
real = checks(load(SRC))
for k, v in real.items(): ok(k, v)
# mutants: each must make at least one check fail
muts = {"no label strip": ("verify = VERIFY_LABEL_RE.sub(", "verify = (lambda *a, **k: a[2])(", 1),
        "no --no-cov": ("-ra|--no-cov|", "-ra|", 1),
        "gitlark dialect back to None": ('node_modules=("web",), dialect=("- backend test: cd backend', 'node_modules=("web",), dialect=None, _x=("- backend test: cd backend', 1)}
for name, (a, b, n) in muts.items():
    assert a in src, name
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "mut.py"); open(p, "w").write(src.replace(a, b, n))
        try: res = checks(load(p))
        except Exception as e: res = {"load": False}
        ok("MUTANT '%s' is caught" % name, not all(res.values()))
sys.exit(1 if fails else 0)
