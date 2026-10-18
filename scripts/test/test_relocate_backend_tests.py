#!/usr/bin/env python3
"""relocate_new_tests for a backend/-rooted pytest layout (test-automation-agent, 2026-10-18): an item naming `tests/x.py` (backend-relative) must not create a
ghost at the repo root. Includes a mutant (the layout detection disabled) and the OVN_RELOCATE_BACKEND_TESTS=off kill switch."""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path[:0] = [HERE, ROOT, os.path.join(ROOT, "scripts")]
import tmp_track  # noqa: E402
tmp_track.install()
import queue_refill as Q  # noqa: E402

P = F = 0


def ok(name, cond):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL:", name)


def mk(root_pytest_ini=False, with_testpaths=True):
    r = os.path.realpath(tempfile.mkdtemp(prefix="relbk-"))
    os.makedirs(os.path.join(r, "backend", "tests"))
    with open(os.path.join(r, "backend", "pytest.ini"), "w") as f:
        f.write("[pytest]\nasyncio_mode = auto\n" + ("testpaths = tests\n" if with_testpaths else ""))
    with open(os.path.join(r, "backend", "tests", "test_existing.py"), "w") as f:
        f.write("def test_a(): pass\n")
    if root_pytest_ini:
        open(os.path.join(r, "pytest.ini"), "w").close()
    return r


NEW = "- [ ] [T2] tests/test_new_thing.py — Add a test. VERIFY: `pytest tests/test_new_thing.py -v`. (cat:test)"
EXISTING = "- [ ] [T2] tests/test_existing.py — Extend it. VERIFY: `pytest tests/test_existing.py::test_a -v`. (cat:test)"
CD_OK = "- [ ] [T2] backend/tests/test_new_thing.py — Add. VERIFY: `cd backend && pytest tests/test_new_thing.py -q`. (cat:test)"

r = mk()
ok("layout detected", Q.collected_test_dir(r) == "backend/tests/")
l, m = Q.relocate_new_tests(NEW, r)
ok("new root-relative test path is rewritten under backend/tests", "backend/tests/test_new_thing.py — Add" in l and "pytest backend/tests/test_new_thing.py -v" in l and m)
l, m = Q.relocate_new_tests(EXISTING, r)
ok("a tests/ path naming a file that only exists under backend/tests is pointed at backend/tests", "pytest backend/tests/test_existing.py::test_a" in l)
l, m = Q.relocate_new_tests(CD_OK, r)
ok("an already-correct backend/tests path with `cd backend` is untouched", l == CD_OK and m == [])

os.environ["OVN_RELOCATE_BACKEND_TESTS"] = "off"
ok("kill switch: layout not detected", Q.collected_test_dir(r) is None)
ok("kill switch: line untouched", Q.relocate_new_tests(NEW, r) == (NEW, []))
del os.environ["OVN_RELOCATE_BACKEND_TESTS"]

ok("a repo with a ROOT pytest.ini (gitlark layout) is not treated as backend-rooted", Q.collected_test_dir(mk(root_pytest_ini=True)) is None)
ok("backend/pytest.ini without testpaths = tests is not treated as backend-rooted", Q.collected_test_dir(mk(with_testpaths=False)) is None)

# mutant: with the detection removed the ghost path is left alone (proves the assertions above bite)
src = open(os.path.join(ROOT, "queue_refill.py")).read()
mut = src.replace('os.path.isdir(os.path.join(repo_root, "backend", "tests"))', 'False', 1)
ok("mutant source differs", mut != src)
import types  # noqa: E402
M = types.ModuleType("qr_mut")
M.__file__ = os.path.join(ROOT, "queue_refill.py")
exec(compile(mut, M.__file__, "exec"), M.__dict__)
ok("MUTANT (detection disabled) leaves the ghost path -> the test would fail", M.relocate_new_tests(NEW, r) == (NEW, []))

print("relocate_backend_tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
