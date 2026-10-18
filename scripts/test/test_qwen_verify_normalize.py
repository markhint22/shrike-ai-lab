#!/usr/bin/env python3
"""test_qwen_verify_normalize.py: the explorer's VERIFY spelling normaliser + dialect-only ledger rule (2026-10-18 backlog-starvation fix).
Fixtures are the VERIFY shapes the 27B really wrote for shrike-monitor / shrike-notify / test-automation-agent (AGENTS.md documents `cd backend && .venv/bin/pytest -q --no-cov`).
usage: test_qwen_verify_normalize.py [path-to-ovn_qwen_explore.py]   (the .sh wrapper also runs it against mutated copies, which must FAIL)"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "ovn_qwen_explore.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("PASS %s" % name)
    else:
        F += 1
        print("FAIL %s %s" % (name, extra))


spec = importlib.util.spec_from_file_location("qe_norm", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

FSET = {"backend/pytest.ini", "backend/tests/conftest.py", "backend/app/main.py", "backend/tests/test_a.py", "AGENTS.md"}
BW_FSET = {"pytest.ini", "tests/conftest.py", "billwatch-backend/app/x.py"}


def final(v, fset=FSET):
    n = m.normalize_verify(v, fset)
    return n, m.verify_dialect_reason(n)


# 1. real rejected shapes become accepted, with the exact rewritten command
GOOD = [
    ("agents_md_verbatim", "cd backend && .venv/bin/pytest tests/test_new_x.py -q --no-cov", "cd backend && pytest tests/test_new_x.py -q --no-cov"),
    ("venv_dot_slash", "cd backend && ./.venv/bin/pytest tests/test_new_x.py -q", "cd backend && pytest tests/test_new_x.py -q"),
    ("venv_python_m", "cd backend && .venv/bin/python -m pytest tests/test_new_x.py::test_a -q", "cd backend && pytest 'tests/test_new_x.py::test_a' -q".replace("'", "")),
    ("root_relative_path", "pytest backend/tests/test_new_x.py -q", "cd backend && pytest tests/test_new_x.py -q"),
    ("root_relative_venv", "backend/.venv/bin/pytest backend/tests/test_new_x.py -q --no-cov", "cd backend && pytest tests/test_new_x.py -q --no-cov"),
    ("double_prefix", "cd backend && pytest backend/tests/test_new_x.py -q", "cd backend && pytest tests/test_new_x.py -q"),
    ("python3_m_root_relative", "python3 -m pytest backend/tests/test_new_x.py -x", "cd backend && python3 -m pytest tests/test_new_x.py -x"),
    ("bare_tests_path_suite_in_backend", "pytest tests/test_new_x.py -q", "cd backend && pytest tests/test_new_x.py -q"),
    ("keep_k_expr", "cd backend && .venv/bin/pytest tests/test_new_x.py -k 'a and b' -q", "cd backend && pytest tests/test_new_x.py -k 'a and b' -q"),
]
for name, v, want in GOOD:
    n, why = final(v)
    ok("normalize_" + name, why == "" and n == want, "got=%r why=%r" % (n, why))
ok("billwatch_root_suite_untouched", final("pytest -q tests/test_new_y.py", BW_FSET) == ("pytest -q tests/test_new_y.py", ""))
ok("already_good_unchanged", m.normalize_verify("cd backend && pytest tests/test_a.py -q", FSET) == "cd backend && pytest tests/test_a.py -q")
ok("negated_grep_untouched", m.normalize_verify("! grep -n 'foo bar baz qux' backend/app/main.py", FSET) == "! grep -n 'foo bar baz qux' backend/app/main.py")

# 2. vacuous / unsafe shapes stay rejected (normalising must never widen the allow-list)
BAD = [
    "grep -n 'def f' backend/app/main.py | grep -q f",
    "grep -rn 'x' backend/app | wc -l",
    "cd backend && .venv/bin/pytest tests/test_x.py -q; rm -rf /",
    "cd backend && .venv/bin/pytest tests/test_x.py && curl http://evil",
    "cd backend && .venv/bin/python -c 'print(1)'",
    "cd backend && .venv/bin/pytest ../../etc/passwd",
    "cd backend && .venv/bin/pytest /etc/passwd",
    "cd backend && .venv/bin/pytest tests/test_x.py > /tmp/o",
    "cd backend && .venv/bin/pytest $(whoami)",
    "cd backend && .venv/bin/pytest --cov=app --cov-report=html:/tmp/x tests/test_x.py",
    "cd backend && .venv/bin/pytest -q --no-cov",                       # no test path: runs the whole suite, not a check of THIS defect
    "source backend/.venv/bin/activate && pytest tests/test_x.py",
]
for v in BAD:
    n, why = final(v)
    ok("still_rejected %s" % v[:50], why != "", "normalised to %r" % n)

# 3. the switch
os_env = os.environ.get("OVN_QE_VERIFY_NORMALIZE")
m.VERIFY_NORMALIZE = False
ok("switch_off_is_identity", m.normalize_verify("cd backend && .venv/bin/pytest tests/test_x.py -q", FSET) == "cd backend && .venv/bin/pytest tests/test_x.py -q")
m.VERIFY_NORMALIZE = True

# 4. dialect-only passes do not burn the lens / file TTLs; a real empty pass still does
class R:
    def __init__(self, d):
        self.d = d


ok("dialect_only_detected", m.dialect_only_empty(R({"proposed": 4, "accepted": 0, "rejected": {"verify-dialect": 4}}), 0))
ok("mixed_rejects_not_dialect_only", not m.dialect_only_empty(R({"proposed": 4, "accepted": 0, "rejected": {"verify-dialect": 3, "hedged-claim": 1}}), 0))
ok("nothing_proposed_not_dialect_only", not m.dialect_only_empty(R({"proposed": 0, "accepted": 0, "rejected": {}}), 0))
ok("written_not_dialect_only", not m.dialect_only_empty(R({"proposed": 2, "accepted": 1, "rejected": {"verify-dialect": 1}}), 1))

qd = os.environ.get("QV_TMP")
if qd and os.path.isdir(qd):
    m.LEDGER_ROOT[0] = qd
    now = 1_000_000.0
    m.now_ts = lambda: now
    base = {"lenses": {}, "files": {}, "day_count": 0}
    m.next_path = None
    try:
        m.write_next = lambda repo, ts: None
        L1 = json.loads(json.dumps(base))
        m._ledger_pass("r", L1, "bug-hunt", ["backend/app/a.py"], 0, False, now, dialect_only=True)
        L2 = json.loads(json.dumps(base))
        m._ledger_pass("r", L2, "bug-hunt", ["backend/app/a.py"], 0, False, now, dialect_only=False)
        ok("dialect_only_keeps_files_unstamped", "backend/app/a.py" not in L1["files"] and "backend/app/a.py" in L2["files"])
        ok("dialect_only_lens_reopens_in_a_quarter_ttl", L1["lenses"]["bug-hunt"] == now - m.LENS_TTL_S * 3 // 4 and L2["lenses"]["bug-hunt"] == now)
        later = now + m.LENS_TTL_S // 4 + 1
        cfg = {"kinds": {"backend"}}
        names = m.applicable_lenses(cfg)
        Lx = {"lenses": {n: now for n in names}}
        Lx["lenses"]["bug-hunt"] = L1["lenses"]["bug-hunt"]
        picked = m.pick_lens(cfg, Lx, later)[0]
        Ly = {"lenses": {n: now for n in names}}
        picked2 = m.pick_lens(cfg, Ly, later)[0]
        ok("lens_available_again_after_quarter_ttl", picked == "bug-hunt" and picked2 is None, "picked=%r picked2=%r" % (picked, picked2))
    except Exception as e:  # noqa
        ok("ledger_section_ran", False, repr(e))
else:
    ok("ledger_section_needs_QV_TMP", False)

print("RESULT pass=%d fail=%d" % (P, F))
sys.exit(1 if F else 0)
