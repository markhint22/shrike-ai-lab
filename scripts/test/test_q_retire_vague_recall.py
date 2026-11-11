#!/usr/bin/env python3
"""retire_vague recall (2026-11-10): scripts/ovn_retire_vague.py. Two changes that land together:
  B  a BACKTICKED test name is a test-creation object: `Add `test_retry_budget` to tests/test_new.py` names a test file that does not exist yet BY DEFINITION (the Z1 exemption), exactly like
     `Add tests ...`; `Add `test_x` to existing tests/test_y.py`, `Add `helper_x` ...` and `Add `test_x` docs` stay NOT creation.
  S  path-mismatch exemption tightening (17 of 50 mismatches were `a tracked file ends with /<path>`, ~33 more a same-named test in ANOTHER test dir):
       suffix:   `tests/test_x.py` when the repo has `svc-backend/tests/test_x.py` EXISTS (never dead-path, even with no create phrase)
       basename: a test-creation item whose missing test path has the same basename as a test file in another test dir is a mislocated duplicate: the Z1 exemption no longer excuses it (dead-path)
  both together: the suffix case must stay kept (exists) while the basename-elsewhere case is retired; neither change alone is enough.
Hermetic: a temp git repo is the cwd (classify reads the repo), no network. MUTANTS: copies of the source with one substitution each; at least one check must fail on every mutant.
Env QRV_SRC points at another copy of ovn_retire_vague.py (the mutant runner)."""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.abspath(os.path.join(HERE, "..", "ovn_retire_vague.py"))
SRC = os.environ.get("QRV_SRC") or REAL
BASE = os.path.realpath(tempfile.mkdtemp(prefix="qrv-"))
FAILS, PASSES = [], [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


spec = importlib.util.spec_from_file_location("rv_q", SRC)
RV = importlib.util.module_from_spec(spec)
spec.loader.exec_module(RV)

REPO = os.path.join(BASE, "repo")
for rel in ("svc-backend/tests/test_sync.py", "svc-backend/tests/api/test_dup.py", "svc-backend/app/sync.py", "svc-backend/tests/conftest.py", "web/tests/conftest.py", "docs/spec/test_notes.md", "svc-backend/myapp/other.py", "docs/guide/test_gidx.py"):
    os.makedirs(os.path.dirname(os.path.join(REPO, rel)), exist_ok=True)
    open(os.path.join(REPO, rel), "w").write("x\n")
subprocess.run(["git", "init", "-q"], cwd=REPO, check=True)
subprocess.run(["git", "add", "-A"], cwd=REPO, check=True)
subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "x"], cwd=REPO, check=True)
os.chdir(REPO)


def C(line):
    return RV.classify(line)


# ------------------------------------------------------------------------------------------------ B backticked test names
chk("B1 `Add `test_x` to <new test file>` is a test-creation item (kept, not dead-path)",
    C("- [ ] [T2] Add `test_retry_budget` to tests/test_brand_new.py asserting the budget is respected. VERIFY: `pytest tests/test_brand_new.py -q`") is None)
chk("B2 `Add `test_x()`` with parens and a `Write` verb", C("- [ ] [T2] Write `test_retry_budget()` in tests/test_brand_new2.py. VERIFY: `pytest tests/test_brand_new2.py -q`") is None)
chk("B3 modifier words between verb and name (`a new`, `a failing`)", C("- [ ] [T2] Add a failing `test_retry_budget` into tests/test_brand_new3.py. VERIFY: `pytest tests/test_brand_new3.py -q`") is None)
chk("B4 `Add `test_x` to existing tests/test_y.py` is NOT creation (the named file is expected to exist): dead-path", C("- [ ] [T2] Add `test_retry_budget` to existing tests/test_gone.py. VERIFY: `pytest tests/test_gone.py -q`") == "dead-path")
chk("B5 a backticked non-test name is not a test-creation phrase: dead-path", C("- [ ] [T2] Add `helper_retry_budget` to tests/test_gone2.py. VERIFY: `pytest tests/test_gone2.py -q`") == "dead-path")
chk("B6 `test_x` followed by prose that only mentions docs is still handled by the existing negative lookahead", C("- [ ] [T2] Add `test_x` docs to tests/test_gone3.py. VERIFY: `pytest tests/test_gone3.py -q`") in ("dead-path", None))
chk("B7 backticked name but the path is a non-test file: dead-path", C("- [ ] [T2] Add `test_retry_budget` note to app/never_there.py. VERIFY: `grep -q x app/never_there.py`") == "dead-path")

# ------------------------------------------------------------------------------------------------ S suffix / basename
chk("S1 suffix: `tests/test_sync.py` exists as svc-backend/tests/test_sync.py -> kept (no create phrase)", C("- [ ] [T2] tests/test_sync.py - assert the retry budget. VERIFY: `pytest tests/test_sync.py -q`") is None)
chk("S2 suffix: a non-test path `app/sync.py` (svc-backend/app/sync.py) -> kept", C("- [ ] [T2] app/sync.py - tighten the retry loop. VERIFY: `grep -q retry app/sync.py`") is None)
chk("S3 suffix match is on a path boundary: `ync.py` / `tests/test_sync.p` do not match", C("- [ ] [T2] app/ync.py - tighten. VERIFY: `grep -q x app/ync.py`") == "dead-path")
chk("S3b suffix needs a PATH boundary: `app/other.py` must not match svc-backend/myapp/other.py", C("- [ ] [T2] app/other.py - tighten. VERIFY: `grep -q x app/other.py`") == "dead-path" and not RV._suffix_exists("app/other.py"))
chk("S3c `_mislocated_test` on a path that already exists as a suffix is False (that is the kept case, not a mislocation)", not RV._mislocated_test("tests/test_sync.py"))
chk("S3d a same-named file under docs/ is not a test dir: creating tests/test_gidx.py is a legitimate creation (kept)", C("- [ ] [T2] Add tests for gidx in tests/test_gidx.py. VERIFY: `pytest tests/test_gidx.py -q`") is None and not RV._mislocated_test("tests/test_gidx.py"))
chk("S4 basename elsewhere: creating tests/test_dup.py while svc-backend/tests/api/test_dup.py exists is a mislocated duplicate -> dead-path (not excused)",
    C("- [ ] [T2] Add tests for the dup path in tests/test_dup.py. VERIFY: `pytest tests/test_dup.py -q`") == "dead-path")
chk("S5 basename elsewhere (backticked creation phrase too)", C("- [ ] [T2] Add `test_dup_case` to tests/test_dup.py. VERIFY: `pytest tests/test_dup.py -q`") == "dead-path")
chk("S6 a genuinely new basename is still excused as a creation: kept", C("- [ ] [T2] Add tests for the new path in tests/test_unique_name.py. VERIFY: `pytest tests/test_unique_name.py -q`") is None)
chk("S7 generic basenames (conftest.py) are never 'mislocated'", C("- [ ] [T2] Add tests fixtures in tests/unit/conftest.py. VERIFY: `pytest tests -q`") in (None, "dead-path") and not RV._mislocated_test("tests/unit/conftest.py"))
chk("S8 `_mislocated_test` is False for a non-test path and for a path with no same-named test elsewhere", not RV._mislocated_test("app/never_there.py") and not RV._mislocated_test("tests/test_unique_name.py"))
chk("S9 `_suffix_exists` direct", RV._suffix_exists("tests/test_sync.py") and not RV._suffix_exists("tests/test_nothing.py"))
chk("S10 a sibling of the same feature that creates the path still excuses it (Z1 behaviour kept)", RV.classify("- [ ] [T2] tests/test_sib_new.py - assert x. VERIFY: `pytest tests/test_sib_new.py` [feat:abc-1]",
    {"abc-1": {"tests/test_sib_new.py"}}) is None)
chk("S11 existing exact path still kept", C("- [ ] [T2] svc-backend/app/sync.py - tighten. VERIFY: `grep -q x svc-backend/app/sync.py`") is None)

# both together: the suffix case is kept AND the basename case is retired in the same repo
chk("BOTH suffix kept + basename retired", C("- [ ] [T2] tests/test_sync.py - assert x. VERIFY: `pytest tests/test_sync.py`") is None and C("- [ ] [T2] Add tests for it in tests/test_dup.py. VERIFY: `pytest tests/test_dup.py`") == "dead-path")

# process() end to end: retired lines are moved, kept lines stay
qf = os.path.join(BASE, "q.md")
open(qf, "w").write("## s\n- [ ] [T2] Add tests for the dup path in tests/test_dup.py. VERIFY: `pytest tests/test_dup.py -q`\n- [ ] [T2] tests/test_sync.py - assert the retry budget. VERIFY: `pytest tests/test_sync.py -q`\n"
                    "- [ ] [T2] Add `test_retry_budget` to tests/test_brand_new.py. VERIFY: `pytest tests/test_brand_new.py -q`\n")
v, d = RV.process(qf)
txt = open(qf).read()
chk("E process(): 1 dead-path (the mislocated duplicate), the suffix item and the backticked creation stay open", (v, d) == (0, 1) and "- [ ] [T2] tests/test_sync.py" in txt and "- [ ] [T2] Add `test_retry_budget`" in txt and "(retired-dead-path) [T2] Add tests for the dup" in txt, (v, d, txt))

# the file list is cached per cwd (one `git ls-files`, not one per path)
chk("E cache: the file list is built once per cwd", len(RV._FILES) >= 1 and os.getcwd() in RV._FILES)

# ------------------------------------------------------------------------------------------------ mutants
MUTANTS = [
    ("B backticked test names not a creation object", '|`test_[A-Za-z0-9_]+(?:\\(\\))?`)"', ')"'),
    ("B backticked alternative accepts any backticked name", '`test_[A-Za-z0-9_]+(?:\\(\\))?`', '`[A-Za-z0-9_]+(?:\\(\\))?`'),
    ("S suffix check removed from _path_exists", "    return _suffix_exists(p)", "    return False"),
    ("S suffix check matches any substring (no path boundary)", 'f.endswith("/" + q) for f in _repo_files()', 'f.endswith(q) for f in _repo_files()'),
    ("S basename tightening removed (every own creation path excused)", "made = set(p for p in _test_creation_paths(body) if not _mislocated_test(p))", "made = set(_test_creation_paths(body))"),
    ("S mislocated test ignores the other-dir requirement", 'return any(f != q and not f.endswith("/" + q) and _is_test_path(f)', 'return any(_is_test_path(f)'),
    ("S generic basenames not exempt", 'if not _is_test_path(q) or base in _GENERIC_TEST_BASENAMES:', 'if not _is_test_path(q):'),
    ("S same-named NON-test file counts as a mislocation", 'and _is_test_path(f) for f in _repo_files().get(base, ()))', 'for f in _repo_files().get(base, ()))'),
]


def mutants():
    bad = 0
    for name, old, new in MUTANTS:
        mdir = os.path.join(BASE, "mut")
        shutil.rmtree(mdir, ignore_errors=True)
        os.makedirs(mdir)
        s = open(REAL, encoding="utf-8").read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        p_ = os.path.join(mdir, "ovn_retire_vague.py")
        with open(p_, "w", encoding="utf-8") as f:
            f.write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, QRV_SRC=p_, QRV_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


os.chdir(BASE)
if os.environ.get("QRV_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
shutil.rmtree(BASE, ignore_errors=True)
print("test_q_retire_vague_recall: %d passed, %d failed" % (PASSES[0], len(FAILS)))
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
sys.exit(1 if FAILS else 0)
