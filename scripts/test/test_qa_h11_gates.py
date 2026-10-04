#!/usr/bin/env python3
"""Tests for the 2026-10-03 QA-gate fixes (diagnosis A11 + QA next-phase list): release_candidate hold-back logic, baseline FAIL echo,
antigaming false positives + A_VACUOUS, reviewer Kotlin/GDScript + severity floor + pattern pass, scanners (paused repos, mypy messages,
seeded-positive selftest), the gold set + `qa_replay.py --gold`, the mark-escape script and the shipped (not installed) cron line.

Every behaviour has a NEGATIVE control (seeded bad input is caught) and a BENIGN control (clean input passes). Gates run through their REAL entry
point under `env -i` with a minimal PATH and NTFY_SERVER set, against throwaway git repos in a temp dir (OVN_DIR/OVN_REPOS_DIR/QA_STATE_DIR are
temp). Never touches the network, ntfy, the live queue dir or a live clone. Real-tool cases (bandit/gitleaks/pip-audit) SKIP loudly where the tool
is missing (the GPU box has them)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
sys.path.insert(0, QA)
import release_candidate as rcm  # noqa: E402
import gate_reviewer as rv  # noqa: E402
import gate_scanners as gs  # noqa: E402
import qa_common as qc  # noqa: E402
import qa_replay as rp  # noqa: E402
import baseline_verify as bv  # noqa: E402

PY = sys.executable
P = F = S = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def skip(name, why):
    global S
    S += 1
    print("  SKIP %s (%s)" % (name, why))


T = tempfile.mkdtemp(prefix="qa-h11-test-")
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(T, "repos")
STATE = os.path.join(OVN, "state")
os.makedirs(os.path.join(STATE, "qa_shadow"))
os.makedirs(REPOS)
GITENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
          "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "HOME": T, "PATH": os.environ.get("PATH", "")}
MINPATH = "/usr/bin:/bin:/usr/local/bin"
GREEN = "chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=tests-green)"


def sh(cwd, *cmd):
    p = subprocess.run(list(cmd), cwd=cwd, env=GITENV, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("%s -> %s %s" % (cmd, p.stdout, p.stderr))
    return p.stdout.strip()


def mkrepo(name, files):
    d = os.path.join(REPOS, name)
    os.makedirs(d)
    sh(d, "git", "init", "-q", "-b", "main")
    return d if commit(d, files, "init") else d


def commit(d, files, msg):
    for fn, body in files.items():
        fp = os.path.join(d, fn)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        if body is None:
            os.remove(fp)
        else:
            with open(fp, "w") as f:
                f.write(body)
    sh(d, "git", "add", "-A")
    sh(d, "git", "commit", "-q", "--allow-empty", "-m", msg)
    return sh(d, "git", "rev-parse", "HEAD")


def gate(script, *args, env_extra=(), rel=False):
    """Real entry point under env -i. Returns (rc, last-json, stdout)."""
    path = os.path.join("qa", script) if rel else os.path.join(QA, script)
    env = ["env", "-i", "PATH=" + MINPATH, "NTFY_SERVER=http://127.0.0.1:9", "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + REPOS, "HOME=" + T,
           "QA_PAUSED_REPOS=none", "QA_FETCH_WAIT=0"] + list(env_extra)
    p = subprocess.run(env + [PY, path] + list(args), cwd=(OQ if rel else T), capture_output=True, text=True, timeout=300)
    last = None
    try:
        last = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        pass
    return p.returncode, last, p.stdout + p.stderr


def anti(repo, base, head, rel=False):
    rc, j, out = gate("gate_antigaming.py", "check", "--repo", repo, "--base", base, "--head", head, "--no-record", rel=rel)
    rules = sorted({f["rule"] for f in (j or {}).get("details", {}).get("findings", [])})
    return j, rules, out


def two(name, before, after, msg="refactor(x): change"):
    """repo with `before` committed, then `after` committed. -> (name, base_sha, head_sha)"""
    d = mkrepo(name, before)
    b = sh(d, "git", "rev-parse", "HEAD")
    h = commit(d, after, msg)
    return name, b, h


# ==================================================================================================================== 1. release_candidate
print("# 1. release_candidate: baseline staged_shadow rows, no age expiry, all reasons")
NOW = time.time()
iso = lambda ago_h: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - ago_h * 3600))  # noqa: E731
ok("baseline staged_shadow FAIL is ignored (it carries the clone HEAD, a queue bookkeeping commit)",
   not rcm.counts_as_fail({"gate": "baseline", "kind": "staged_shadow", "verdict": "FAIL", "ts": iso(1)}))
ok("CONTROL: a baseline row of another kind still counts", rcm.counts_as_fail({"gate": "baseline", "kind": "compare", "verdict": "FAIL", "ts": iso(1)}))
ok("CONTROL: a fresh migrations FAIL counts", rcm.counts_as_fail({"gate": "migrations", "verdict": "FAIL", "ts": iso(1)}))
ok("NEGATIVE: a 100h-old code FAIL (antigaming, scanners, migrations) is NOT forgiven by age", all(rcm.counts_as_fail({"gate": g_, "verdict": "FAIL", "ts": iso(100)}) for g_ in ("migrations", "antigaming", "scanners")))
ok("CONTROL: FAIL row at 71h still counts", rcm.counts_as_fail({"gate": "migrations", "verdict": "FAIL", "ts": iso(71)}))
ok("CONTROL: a FAIL row with no ts is kept (never silently forgiven)", rcm.counts_as_fail({"gate": "migrations", "verdict": "FAIL"}))
ok("opt-in QA_RELEASE_FAIL_MAX_AGE_H=72 still expires old rows", (lambda: (os.environ.__setitem__("QA_RELEASE_FAIL_MAX_AGE_H", "72"), not rcm.counts_as_fail(
    {"gate": "migrations", "verdict": "FAIL", "ts": iso(100)}), os.environ.pop("QA_RELEASE_FAIL_MAX_AGE_H"))[1])())
ok("fail_tokens skips baseline staged_shadow rows", not rcm.fail_tokens([{"gate": "baseline", "kind": "staged_shadow", "repo": "r", "verdict": "FAIL", "ref": "deadbeef1", "ts": iso(1)}], "r"))
ok("fail_rows keeps a real migrations FAIL", len(rcm.fail_rows([{"gate": "migrations", "repo": "r", "verdict": "FAIL", "ref": "deadbeef1", "ts": iso(1)}], "r")) == 1)


def rc_repo(name):
    d = mkrepo(name, {"a.txt": "a\n"})
    sh(d, "git", "checkout", "-q", "-b", "develop")
    return d


def hyg(d, tag, subject=GREEN):
    sh(d, "git", "checkout", "-q", "-b", "feat-" + tag, "develop")
    c = commit(d, {"f_%s.txt" % tag: tag + "\n"}, "feat(x): change " + tag)
    sh(d, "git", "checkout", "-q", "develop")
    sh(d, "git", "merge", "-q", "--no-ff", "-m", subject, "feat-" + tag)
    return sh(d, "git", "rev-parse", "HEAD"), c


def publish(d):
    sh(d, "git", "update-ref", "refs/remotes/origin/main", "main")
    sh(d, "git", "update-ref", "refs/remotes/origin/develop", "develop")


def write_rows(rows):
    p = os.path.join(STATE, "qa_shadow")
    shutil.rmtree(p, ignore_errors=True)
    os.makedirs(p)
    by = {}
    for r in rows:
        by.setdefault(r["gate"], []).append(r)
    for g, rs in by.items():
        with open(os.path.join(p, g + ".jsonl"), "w") as f:
            for r in rs:
                f.write(json.dumps(r) + "\n")


def plan(repo):
    rc, j, out = gate("release_candidate.py", "plan", "--repo", repo, "--date", "20261003", "--no-record")
    return j


d1 = rc_repo("rcbase")
g1, _ = hyg(d1, "a")
tip1, c1 = hyg(d1, "b")
publish(d1)
write_rows([{"gate": "baseline", "kind": "staged_shadow", "repo": "rcbase", "verdict": "FAIL", "ref": tip1, "ts": iso(1), "summary": "echo"}])
j = plan("rcbase")
ok("baseline staged_shadow FAIL on the tip no longer holds it back: PASS, candidate == tip", j and j["verdict"] == "PASS" and j["ref"] == tip1[:10], j and j["summary"])
write_rows([{"gate": "migrations", "kind": "x", "repo": "rcbase", "verdict": "FAIL", "ref": tip1, "ts": iso(1), "summary": "real"}])
j = plan("rcbase")
ok("NEGATIVE control: the same FAIL from a code gate (migrations) holds the tip back (FLAG, candidate = previous merge)",
   j and j["verdict"] == "FLAG" and j["ref"] == g1[:10], j and j["summary"])
write_rows([{"gate": "migrations", "repo": "rcbase", "verdict": "FAIL", "ref": tip1, "ts": iso(100), "summary": "stale"}])
j = plan("rcbase")
ok("NEGATIVE: a 100h-old migrations FAIL still holds the tip back (no age forgiveness)", j and j["verdict"] == "FLAG" and "migrations" in j["summary"], j and j["summary"])

d2 = rc_repo("rcmulti")
g2, _ = hyg(d2, "a")
commit(d2, {"direct.txt": "x\n"}, "fix: manual change straight on develop")   # ungated tip commit
tip2 = sh(d2, "git", "rev-parse", "HEAD")
publish(d2)
write_rows([{"gate": "migrations", "repo": "rcmulti", "verdict": "FAIL", "ref": tip2, "ts": iso(1)},
            {"gate": "antigaming", "repo": "rcmulti", "verdict": "FAIL", "ref": "%s..%s" % (g2, tip2), "ts": iso(1)}])
j = plan("rcmulti")
reason = ((j or {}).get("details", {}).get("skipped") or [{}])[0].get("reason", "")
ok("ALL reasons per held-back commit are printed: ungated AND the QA FAIL naming both gates", "ungated" in reason and "migrations" in reason and "antigaming" in reason
   and "QA FAIL in range" in reason, reason)
ok("the FLAG summary itself carries the reasons", j and "reasons:" in j["summary"] and "migrations" in j["summary"], j and j["summary"])
ok("held_back entries carry their reason", j and j["details"]["held_back"] and "QA FAIL" in j["details"]["held_back"][0].get("reason", ""), j and j["details"].get("held_back"))

# ==================================================================================================================== 2. baseline gate
print("# 2. baseline: runner-enforced gate failures are NA, new failing tests still FAIL")
hard_only = {"format": "verify-log", "ids": [], "hard": ["QUALITY FAIL: app/x.py is a stub"], "complete": True, "reasons": [], "expected": None}
v, summ, det = bv.compare_sets(hard_only, {"failing": ["a::b"], "ts": time.time(), "commit": "c", "iso": "x", "history": []}, runner_failed=True)
ok("hard gate failure alone => NA (the runner already enforces it)", v == "NA" and det["runner_enforced"], (v, summ))
v, summ, det = bv.compare_sets(hard_only, None, runner_failed=True)
ok("hard gate failure with NO baseline => NA, not FAIL", v == "NA", (v, summ))
hard_new = dict(hard_only, ids=["t::new_red"])
v, summ, det = bv.compare_sets(hard_new, {"failing": ["a::b"], "ts": time.time(), "commit": "c", "iso": "x", "history": []}, runner_failed=True)
ok("NEGATIVE control: gate failure PLUS a new failing test vs a live baseline => FAIL", v == "FAIL" and "NEW failing" in summ, (v, summ))
clean = {"format": "pytest", "ids": [], "hard": [], "complete": True, "reasons": [], "expected": None}
v, summ, det = bv.compare_sets(clean, None, runner_failed=False)
ok("BENIGN control: green run still PASS", v == "PASS", (v, summ))

# ==================================================================================================================== 3. antigaming
print("# 3. antigaming: the false-positive rules")
# --- C_VALIDATION_REMOVED across Depends
ROUTE_OLD = ("from fastapi import Depends, HTTPException\n\n\n"
             "def get_current_user_optional():\n    return None\n\n\n"
             "async def refresh(legislator_id: int, user=Depends(get_current_user_optional), db=Depends(get_db)):\n"
             "    \"\"\"Force refresh.\"\"\"\n    await require_key()\n"
             "    if user is None:\n        raise HTTPException(status_code=401, detail='Not authenticated')\n"
             "    if not getattr(user, 'is_admin', False):\n        raise HTTPException(status_code=403, detail='Admin access required')\n"
             "    result = await db.execute(legislator_id)\n    rows = list(result)\n    total = sum(r.amount for r in rows)\n    top = sorted(rows, key=lambda r: r.amount)[:5]\n"
             "    summary = {'total': total, 'top': top, 'count': len(rows)}\n    await db.commit()\n    logger.info('refreshed %s', legislator_id)\n    return summary\n")
ROUTE_DEP = ROUTE_OLD.replace("user=Depends(get_current_user_optional)", "_admin=Depends(require_admin)").replace(
    "    if user is None:\n        raise HTTPException(status_code=401, detail='Not authenticated')\n"
    "    if not getattr(user, 'is_admin', False):\n        raise HTTPException(status_code=403, detail='Admin access required')\n", "")
ROUTE_DROP = ROUTE_OLD.replace(
    "    if user is None:\n        raise HTTPException(status_code=401, detail='Not authenticated')\n"
    "    if not getattr(user, 'is_admin', False):\n        raise HTTPException(status_code=403, detail='Admin access required')\n", "")
n, b, h = two("ag_dep", {"app/finance.py": ROUTE_OLD}, {"app/finance.py": ROUTE_DEP})
j, rules, out = anti(n, b, h)
ok("raises replaced by a NEW Depends(require_admin) are delegated, not removed: no C_VALIDATION_REMOVED", "C_VALIDATION_REMOVED" not in rules, (rules, j and j["summary"]))
n, b, h = two("ag_dep_neg", {"app/finance.py": ROUTE_OLD}, {"app/finance.py": ROUTE_DROP})
j, rules, out = anti(n, b, h)
ok("NEGATIVE control: the same raises just deleted (no Depends) => C_VALIDATION_REMOVED", "C_VALIDATION_REMOVED" in rules, (rules, j and j["summary"]))

# --- C_ERRORHANDLING_REMOVED on a widened except
WID_OLD = ("def hook(data, raw):\n"
           "    try:\n        body = parse(data)\n    except Exception:\n        return None\n"
           "    try:\n        uid = int(raw)\n    except ValueError:\n        return {'status': 'ignored'}\n"
           "    try:\n        exp = float(body['exp'])\n    except (TypeError, ValueError):\n        exp = None\n"
           "    return uid, exp\n")
WID_NEW = ("def hook(data, raw):\n"
           "    try:\n        body = parse(data)\n    except Exception:\n        return None\n"
           "    if not isinstance(body, dict):\n        return None\n"
           "    try:\n        uid = int(raw)\n    except (ValueError, TypeError):\n        return {'status': 'ignored'}\n"
           "    exp = body.get('exp')\n"
           "    return uid, exp\n")
NARROW_NEW = ("def hook(data, raw):\n"
              "    try:\n        body = parse(data)\n    except Exception:\n        return None\n"
              "    uid = int(raw)\n"
              "    try:\n        exp = float(body['exp'])\n    except (TypeError, ValueError):\n        exp = None\n"
              "    return uid, exp\n")
n, b, h = two("ag_wide", {"app/hook.py": WID_OLD}, {"app/hook.py": WID_NEW})
j, rules, out = anti(n, b, h)
ok("a widened except tuple (+ new guards) is not a removed guard: no C_ERRORHANDLING_REMOVED", "C_ERRORHANDLING_REMOVED" not in rules, (rules, j and j["summary"]))
n, b, h = two("ag_wide_neg", {"app/hook.py": WID_OLD}, {"app/hook.py": NARROW_NEW})
j, rules, out = anti(n, b, h)
ok("NEGATIVE control: an except removed with NO widening => C_ERRORHANDLING_REMOVED", "C_ERRORHANDLING_REMOVED" in rules, (rules, j and j["summary"]))

# --- A_ASSERT_WEAKENED when the net is not lower
AW_OLD = ("import pytest\n\n\ndef test_blocks():\n    with pytest.raises(ValueError, match='blocked'):\n        fetch('http://x')\n")
AW_NEW = ("def test_blocks():\n    res = fetch('http://x')\n    assert res['ok'] is False\n    assert res['error'] == 'blocked'\n    assert res['status'] == 403\n")
n, b, h = two("ag_aw", {"tests/test_a.py": AW_OLD}, {"tests/test_a.py": AW_NEW})
j, rules, out = anti(n, b, h)
ok("pytest.raises swapped for three stronger asserts is not a weakening: no A_ASSERT_WEAKENED", "A_ASSERT_WEAKENED" not in rules, (rules, j and j["summary"]))
AW_OLD2 = "def test_v():\n    assert compute(2) == 4\n    assert compute(3) == 9\n"
AW_BAD2 = "def test_v():\n    assert compute(2)\n    assert compute(3) == 9\n"
n, b, h = two("ag_aw_neg", {"tests/test_a.py": AW_OLD2}, {"tests/test_a.py": AW_BAD2})
j, rules, out = anti(n, b, h)
ok("NEGATIVE control: an exact assertion degraded to truthiness (net rank lower) => A_ASSERT_WEAKENED", "A_ASSERT_WEAKENED" in rules, (rules, j and j["summary"]))

# --- F_CLAIM_TEST_ONLY
CL_BASE = {"tests/test_uid.py": "def _scan(d):\n    names = list(d)\n    return names\n\n\ndef test_none():\n    assert _scan([]) == []\n"}
d = mkrepo("ag_claim_helper", CL_BASE)
b = sh(d, "git", "rev-parse", "HEAD")
h = commit(d, {"tests/test_uid.py": CL_BASE["tests/test_uid.py"].replace("    return names\n", "    names.clear()\n    return names\n")}, "fix: free DirAccess to prevent resource leaks")
j, rules, out = anti("ag_claim_helper", b, h)
ok("BENIGN: a 'fix:' that only edits a test HELPER (no assertion, no test definition) is not F_CLAIM_TEST_ONLY", "F_CLAIM_TEST_ONLY" not in rules, (rules, j and j["summary"]))
d = mkrepo("ag_claim_named", CL_BASE)
b = sh(d, "git", "rev-parse", "HEAD")
h = commit(d, {"tests/test_uid.py": CL_BASE["tests/test_uid.py"].replace("== []", "== [] or True")}, "fix: tighten tests/test_uid.py scan expectation")
j, rules, out = anti("ag_claim_named", b, h)
ok("a subject that NAMES the touched test file is honest: no F_CLAIM_TEST_ONLY", "F_CLAIM_TEST_ONLY" not in rules, (rules, j and j["summary"]))
d = mkrepo("ag_claim_const", {"tests/test_c.py": "EXPECTED = 200\n\n\ndef test_c():\n    assert get() == EXPECTED\n"})
b = sh(d, "git", "rev-parse", "HEAD")
h = commit(d, {"tests/test_c.py": "EXPECTED = 500\n\n\ndef test_c():\n    assert get() == EXPECTED\n"}, "fix: handle upstream errors")
j, rules, out = anti("ag_claim_const", b, h)
ok("NEGATIVE: a 'fix:' that only flips an expected-value constant => F_CLAIM_TEST_ONLY", "F_CLAIM_TEST_ONLY" in rules, (rules, j and j["summary"]))
d = mkrepo("ag_claim_stem", {"tests/models.py": CL_BASE["tests/test_uid.py"]})
b = sh(d, "git", "rev-parse", "HEAD")
h = commit(d, {"tests/models.py": CL_BASE["tests/test_uid.py"].replace("== []", "== [] or True")}, "fix: models validation of empty input")
j, rules, out = anti("ag_claim_stem", b, h)
ok("NEGATIVE: a subject naming only a bare STEM (not path/basename) does not exempt the commit", "F_CLAIM_TEST_ONLY" in rules, (rules, j and j["summary"]))
d = mkrepo("ag_claim_neg", {"tests/test_lim.py": "def test_env():\n    assert limiter.enabled is False\n"})
b = sh(d, "git", "rev-parse", "HEAD")
h = commit(d, {"tests/test_lim.py": "def test_env():\n    assert limiter.enabled is True\n"}, "fix: respect RATE_LIMIT_ENABLED env var in limiter initialization")
j, rules, out = anti("ag_claim_neg", b, h)
ok("NEGATIVE control: a product-fix claim whose diff only rewrites an assertion => F_CLAIM_TEST_ONLY", "F_CLAIM_TEST_ONLY" in rules, (rules, j and j["summary"]))

print("# 3b. antigaming: A_VACUOUS (new test whose only assertions are tautologies / placeholder body) is a FAIL")
BASE = {"app/m.py": "def f():\n    return 1\n", "tests/__init__.py": ""}
for label, body in (("assert True", "def test_health():\n    assert True\n"),
                    ("assert 1 == 1", "def test_health():\n    assert 1 == 1\n"),
                    ("assert x or True", "def test_health():\n    x = f()\n    assert x or True\n"),
                    ("placeholder pass body", "def test_health():\n    # placeholder, fill in later\n    pass\n"),
                    ("docstring-only body", "def test_health():\n    \"\"\"does nothing\"\"\"\n")):
    nm = "ag_vac_" + str(abs(hash(label)) % 100000)
    n, b, h = two(nm, BASE, {"tests/test_new.py": body}, msg="test: add tests")
    j, rules, out = anti(n, b, h)
    ok("A_VACUOUS FAIL: new test with %s" % label, j and j["verdict"] == "FAIL" and "A_VACUOUS" in rules, (j and j["verdict"], rules))
n, b, h = two("ag_vac_call", BASE, {"tests/test_new.py": "from app.m import f\n\n\ndef check_response(x):\n    assert x == 1\n\n\ndef test_c():\n    check_response(f())  # TODO: add test for placeholder\n"}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("BENIGN: a helper-asserting test with a placeholder-ish comment is not A_VACUOUS", "A_VACUOUS" not in rules, (j and j["verdict"], rules))
OLDT = "from app.m import f\n\n\ndef test_t():\n    assert True\n"
n, b, h = two("ag_vac_moved", dict(BASE, **{"tests/test_old.py": OLDT}), {"tests/test_old.py": None, "tests/test_moved.py": OLDT}, msg="test: move tests")
j, rules, out = anti(n, b, h)
ok("BENIGN: a MOVED test (same qualified name in the old file set) is not 'newly added' => no A_VACUOUS", "A_VACUOUS" not in rules, (j and j["verdict"], rules))
n, b, h = two("ag_vac_ok", BASE, {"tests/test_new.py": "from app.m import f\n\n\ndef test_f():\n    assert f() == 1\n"}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("BENIGN control: a new test with a real assertion => PASS, no A_VACUOUS", j and j["verdict"] == "PASS" and "A_VACUOUS" not in rules, (j and j["summary"], rules))
n, b, h = two("ag_vac_mixed", BASE, {"tests/test_new.py": "from app.m import f\n\n\ndef test_f():\n    assert f() == 1\n    assert True\n"}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("BENIGN control: a real assertion plus one stray tautology is NOT the FAIL rule (A_VACUOUS needs ONLY tautologies)", j and j["verdict"] != "FAIL" and "A_VACUOUS" not in rules, (j and j["verdict"], rules))
n, b, h = two("ag_vac_helper", BASE, {"tests/test_new.py": "from app.m import f\n\n\ndef check(x):\n    assert x == 1\n\n\ndef test_f():\n    check(f())\n"}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("BENIGN control: a test that asserts through a helper is not judged vacuous", j and "A_VACUOUS" not in rules, (j and j["verdict"], rules))
KT = ("package a.b\n\nimport org.junit.Test\n\nclass StreamsViewModelTest {\n\n    @Test\n    fun testPlaceholder() {\n"
      "        // Placeholder test to ensure the file compiles.\n        assert(true)\n    }\n}\n")
n, b, h = two("ag_kt", {"app/src/test/java/a/b/StreamsViewModelTest.kt": ""}, {"app/src/test/java/a/b/StreamsViewModelTest.kt": KT})
j, rules, out = anti(n, b, h)
ok("A_VACUOUS FAIL: Kotlin new test body is `assert(true)` (closed-captions false credit shape)", j and j["verdict"] == "FAIL" and "A_VACUOUS" in rules, (j and j["summary"], rules))
KT_OK = KT.replace("assert(true)", "assertEquals(2, 1 + 1)").replace("Placeholder test to ensure the file compiles.", "adds")
n, b, h = two("ag_kt_ok", {"app/src/test/java/a/b/StreamsViewModelTest.kt": ""}, {"app/src/test/java/a/b/StreamsViewModelTest.kt": KT_OK}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("BENIGN control: Kotlin new test with assertEquals => PASS", j and j["verdict"] == "PASS", (j and j["summary"], rules))
KT_TICK = ("package a.b\n\nimport org.junit.Test\n\nclass T {\n    @Test\n    fun `setStreamType reloads the selected tab's type`() {\n        assertEquals(2, 1 + 1)\n    }\n\n"
           "    @Test\n    fun `second test`() {\n        assertEquals(3, 1 + 2)\n    }\n}\n")
n, b, h = two("ag_kt_tick", {"app/src/test/java/a/b/T.kt": "package a.b\n\nclass T\n"}, {"app/src/test/java/a/b/T.kt": KT_TICK}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("Kotlin backticked test name containing an apostrophe parses (was UNVERIFIED 'could not be parsed')", j and j["verdict"] == "PASS", (j and j["verdict"], j and j["summary"]))
GD = "extends GutTest\n\n\nfunc test_placeholder():\n\tassert_true(true)\n"
n, b, h = two("ag_gd", {"tests/test_a.gd": "extends GutTest\n\n\nfunc test_a():\n\tassert_eq(1, 1 + 0)\n"}, {"tests/test_b.gd": GD}, msg="test: add tests")
j, rules, out = anti(n, b, h)
ok("A_VACUOUS FAIL: GDScript new test is assert_true(true)", j and j["verdict"] == "FAIL" and "A_VACUOUS" in rules, (j and j["summary"], rules))
j, rules, out = anti(n, b, h, rel=True)
ok("same through the relative cron-style path", j and j["verdict"] == "FAIL", (j and j["summary"]))
ok("antigaming stays SHADOW: the exit code is 0 even on FAIL and the mode is shadow", gate("gate_antigaming.py", "check", "--repo", n, "--base", b, "--head", h, "--no-record")[0] == 0 and j["mode"] == "shadow")

# ==================================================================================================================== 4. reviewer
print("# 4. reviewer: Kotlin/GDScript enabled, severity floor, model-free pattern pass, never blocks")
ok("kotlin and gdscript are in the default reviewed languages", {"kt", "gd"} <= set(rv.REVIEW_LANGS_DEFAULT.split(",")), rv.REVIEW_LANGS_DEFAULT)
ok("severity floor: 'unauthenticated' claim at medium -> high (raised)", rv.severity_floor("endpoint accepts a password reset unauthenticated", "x", "medium") == ("high", True))
ok("severity floor: hardcoded secret claim at low -> high", rv.severity_floor("hardcoded API key in source", "k = 'x'", "low") == ("high", True))
ok("severity floor: 'anyone can' phrasing", rv.severity_floor("anyone can call this without a token", "", "medium")[0] == "high")
for c_ in ("No authentication errors are logged", "tokens are returned in the response as designed", "token is logged at debug level only in tests"):
    ok("severity floor NOT inflated for benign claim: %r" % c_, rv.severity_floor(c_, "", "medium") == ("medium", False))
ok("CONTROL: a real 'route has no authentication dependency' is still raised", rv.severity_floor("The route has no authentication dependency", "", "medium") == ("high", True))
ok("CONTROL: a token logged in production is still raised", rv.severity_floor("token is logged in production", "", "medium") == ("high", True))
ok("body-model reset route (PasswordResetRequest, the billwatch incident shape) stays flagged: the signature cannot show whether the model holds a token", rv.AUTHISH_RE.search("async def reset(request: PasswordResetRequest):") is None)
ok("CONTROL: an ordinary off-by-one stays medium and is not marked raised", rv.severity_floor("off-by-one in the loop bound", "for i in range(n+1):", "medium") == ("medium", False))
ok("CONTROL: severity is never lowered", rv.severity_floor("some defect", "", "high") == ("high", False))
ROUTE_NOAUTH = ("from fastapi import APIRouter, Depends\n\nrouter = APIRouter()\n\n\n@router.post(\"/reset-password\", status_code=200)\n"
                "async def reset_password(\n    request: PasswordResetRequest,\n    db: AsyncSession = Depends(get_db)\n):\n"
                "    \"\"\"Reset user password.\"\"\"\n    await svc.reset(request.email, request.new_password)\n    return {\"ok\": True}\n")
ROUTE_AUTH = ROUTE_NOAUTH.replace("request: PasswordResetRequest,", "request: PasswordResetRequest,\n    token: str,")
ROUTE_USER = ROUTE_NOAUTH.replace("db: AsyncSession = Depends(get_db)", "user: User = Depends(get_current_user)")
DEAD = ["QA_REVIEWER_URL=http://127.0.0.1:9", "QA_REVIEWER_DEADLINE=15", "QA_REVIEWER_CALL_TIMEOUT=3"]


def review(name, before, after, env=()):
    n, b, h = two(name, before, after)
    rc, j, out = gate("gate_reviewer.py", "check", "--repo", n, "--base", b, "--head", h, "--no-record", env_extra=list(DEAD) + list(env))
    return rc, j


rc, j = review("rv_noauth", {"app/routers/auth.py": "x = 1\n"}, {"app/routers/auth.py": ROUTE_NOAUTH})
f0 = ((j or {}).get("details", {}).get("findings") or [{}])[0]
ok("NEGATIVE control: new /reset-password route with no auth/token is flagged high WITHOUT any model (dead model URL)",
   j and j["verdict"] == "FLAG" and f0.get("severity") == "high" and f0.get("source") == "pattern" and f0.get("line") == 6, (j and j["summary"], f0))
ok("the reviewer still never blocks (exit 0, shadow)", rc == 0 and j["mode"] == "shadow")
rc, j = review("rv_token", {"app/routers/auth.py": "x = 1\n"}, {"app/routers/auth.py": ROUTE_AUTH})
ok("BENIGN control: the same route with a reset-token parameter has no pattern finding", j and not (j["details"].get("findings") or []), (j and j["summary"]))
rc, j = review("rv_user", {"app/routers/auth.py": "x = 1\n"}, {"app/routers/auth.py": ROUTE_USER})
ok("BENIGN control: the same route behind get_current_user has no pattern finding", j and not (j["details"].get("findings") or []), (j and j["summary"]))
rc, j = review("rv_secret", {"app/core/config.py": "x = 1\n"}, {"app/core/config.py": "from pydantic import Field\n\n\nclass S:\n    token_encryption_key: str = Field(default=\"local-dev-token-encryption-key-change-in-prod\")\n"})
f0 = ((j or {}).get("details", {}).get("findings") or [{}])[0]
ok("NEGATIVE control: hardcoded default secret (pydantic Field(default=...)) flagged high", j and j["verdict"] == "FLAG" and f0.get("severity") == "high" and "hardcoded default secret" in f0.get("claim", ""), (j and j["summary"], f0))
rc, j = review("rv_envsecret", {"app/core/config.py": "x = 1\n"}, {"app/core/config.py": "import os\n\nTOKEN_KEY = os.environ[\"TOKEN_KEY\"]\nDEBUG_LABEL = \"change-me-later\"\n"})
ok("BENIGN control: a secret read from the environment and a non-secret 'change' label are not flagged", j and not (j["details"].get("findings") or []), (j and j["summary"]))
rc, j = review("rv_kt", {"app/src/main/java/a/Repo.kt": "package a\n"}, {"app/src/main/java/a/Repo.kt": "package a\n\nclass Repo {\n    fun load(): Int {\n        return 1\n    }\n}\n"})
ok("Kotlin product code now reaches the review path (UNVERIFIED model-down, not NA 'lang-not-enabled')", j and j["verdict"] == "UNVERIFIED" and "model" in j["summary"], (j and j["verdict"], j and j["summary"]))
rc, j = review("rv_gd", {"scripts/a.gd": "extends Node\n"}, {"scripts/a.gd": "extends Node\n\n\nfunc add(a, b):\n\treturn a + b\n"})
ok("GDScript product code now reaches the review path too", j and j["verdict"] == "UNVERIFIED" and "model" in j["summary"], (j and j["verdict"], j and j["summary"]))
rc, j = review("rv_swift", {"a/A.swift": "import Foundation\n"}, {"a/A.swift": "import Foundation\n\nstruct A {\n    func f() -> Int { 1 }\n}\n"})
ok("CONTROL: swift stays disabled (NA, lang-not-enabled listed)", j and j["verdict"] == "NA" and any("lang-not-enabled" in s["reason"] for s in j["details"]["skipped"]), (j and j["summary"]))

# in-process: a model-proposed finding with severity 'medium' about missing auth is raised to high and marked
n, b, h = two("rv_model", {"app/routers/x.py": "x = 1\n"}, {"app/routers/x.py": "def get_item(item_id):\n    item = db.load(item_id)\n    return item\n\n\ndef other():\n    return 2\n"})


def model(prompt):
    if "REFUTER" in prompt:
        return json.dumps({"refuted": False, "reason": "the code shows no check"})
    return json.dumps({"findings": [{"file": "app/routers/x.py", "line": 2, "quote": "item = db.load(item_id)",
                                     "claim": "any user can read any item without an ownership check", "severity": "medium"}]})


os.environ["OVN_REPOS_DIR"] = REPOS
os.environ["OVN_DIR"] = OVN
os.environ["QA_PAUSED_REPOS"] = "none"
res = rv.check(["check", "--repo", n, "--base", b, "--head", h, "--no-record"], model_fn=lambda p, *a, **k: model(p))
fnd = (res.get("details", {}).get("findings") or [{}])[0]
ok("model-proposed 'any user can read any item without an ownership check' labelled medium is raised to high and marked severity_raised",
   res["verdict"] == "FLAG" and fnd.get("severity") == "high" and fnd.get("severity_raised") is True and not fnd.get("source"), (res["verdict"], fnd))


def model2(prompt):
    if "REFUTER" in prompt:
        return json.dumps({"refuted": False, "reason": "real"})
    return json.dumps({"findings": [{"file": "app/routers/x.py", "line": 2, "quote": "item = db.load(item_id)",
                                     "claim": "load may return None for an unknown id", "severity": "medium"}]})


res = rv.check(["check", "--repo", n, "--base", b, "--head", h, "--no-record"], model_fn=lambda p, *a, **k: model2(p))
fnd = (res.get("details", {}).get("findings") or [{}])[0]
ok("CONTROL: an ordinary correctness finding stays medium and is not marked raised", res["verdict"] == "FLAG" and fnd.get("severity") == "medium" and not fnd.get("severity_raised"), fnd)

# ==================================================================================================================== 5. scanners
print("# 5. scanners: paused repos, original mypy messages, seeded-positive selftest")
m = 'Argument 1 to "make_token" has incompatible type "str"; expected "int"  [arg-type]'
ok("mypy message keeps function and type names (was 'Argument 1 to <str> has incompatible type <str>; expected <str>')",
   gs.redact_msg(m, strings=True) == m, gs.redact_msg(m, strings=True))
ok("NEGATIVE: redact_msg masks a double-quoted VALUE after 'is' (hunter2)", "hunter2" not in gs.redact_msg('Value of "password" is "hunter2"', strings=True))
ok("CONTROL: redact_msg keeps type names after 'type'", gs.redact_msg('has incompatible type "str"; expected "int"', strings=True) == 'has incompatible type "str"; expected "int"')
tok = "ghp_" + "Zk3Qm9Rv2Tn7Xb5Lw8Hc4Jd6Sf1Ya0Pe"
ok("NEGATIVE control: Literal['<token>'] contents are still masked", tok not in gs.redact_msg("Incompatible types (expression has type \"Literal['%s']\", variable has type \"int\")" % tok, strings=True))
ok("NEGATIVE control: a single-quoted literal and a free-text double-quoted string are masked", "hunter22" not in gs.redact_msg("bad 'hunter22' and \"my secret value is hunter22!\"", strings=True))
ok("NEGATIVE control: a bare token-like run is redacted even with strings=False", tok not in gs.redact_msg("x " + tok))
# paused repos
os.environ["QA_PAUSED_REPOS"] = "none"
ok("QA_PAUSED_REPOS=none pauses nothing", qc.paused_repos() == set())
os.environ["QA_PAUSED_REPOS"] = "alpha, beta"
ok("QA_PAUSED_REPOS=alpha,beta", qc.paused_repos() == {"alpha", "beta"})
del os.environ["QA_PAUSED_REPOS"]
tmp_ovn = os.path.join(T, "ovn_paused")
os.makedirs(os.path.join(tmp_ovn, "state"))
os.environ["OVN_DIR"] = tmp_ovn
json.dump([{"type": "aider_fix", "repo": "/x/repos/lane_off", "enabled": False}, {"type": "aider_fix", "repo": "/x/repos/lane_off", "enabled": False},
           {"type": "aider_fix", "repo": "/x/repos/lane_on", "enabled": True}, {"type": "aider_fix", "repo": "/x/repos/mixed", "enabled": False},
           {"type": "aider_fix", "repo": "/x/repos/mixed", "enabled": True}], open(os.path.join(tmp_ovn, "tasks.json"), "w"))
pr = qc.paused_repos()
ok("NEGATIVE: a `hold` (all aider_fix lanes disabled in tasks.json) does NOT pause scanners for the repo", "lane_off" not in pr and "lane_on" not in pr and "mixed" not in pr, pr)
ok("the tracked qa/qa_paused_repos.txt pauses shrike-monitor and shrike-notify", {"shrike-monitor", "shrike-notify"} <= pr, pr)
json.dump({"mode": "qa"}, open(os.path.join(tmp_ovn, "state", "qa_mode.json"), "w"))
pr = qc.paused_repos()
ok("in QA mode tasks.json still says nothing: only the explicit lists pause", "lane_off" not in pr and "shrike-monitor" in pr, pr)
open(os.path.join(tmp_ovn, "state", "qa_paused_repos.txt"), "w").write("# comment\nextra_repo  # trailing\n")
ok("state/qa_paused_repos.txt is honoured (comments stripped)", "extra_repo" in qc.paused_repos())
os.environ["OVN_DIR"] = OVN
os.environ["QA_PAUSED_REPOS"] = "none"
n, b, h = two("shrike-monitor", {"app/ok.py": "x = 1\n"}, {"app/ok.py": "x = 2\n"})
rc, j, out = gate("gate_scanners.py", "check", "--repo", n, "--base", b, "--head", h, "--no-record", env_extra=["QA_PAUSED_REPOS="])
ok("paused repo (shrike-monitor): scanners returns NA 'repo is paused' without running a tool", j and j["verdict"] == "NA" and "paused" in j["summary"], (j and j["summary"], out[-200:]))
rc, j, out = gate("gate_scanners.py", "check", "--repo", n, "--base", b, "--head", h, "--no-record", env_extra=["QA_PAUSED_REPOS=none"])
ok("CONTROL: QA_PAUSED_REPOS=none forces the scan (not NA 'paused')", j and "paused" not in j["summary"], (j and j["summary"]))
n, b, h = two("active_repo", {"app/ok.py": "x = 1\n"}, {"app/ok.py": "x = 2\n"})
rc, j, out = gate("gate_scanners.py", "check", "--repo", n, "--base", b, "--head", h, "--no-record", env_extra=["QA_PAUSED_REPOS="])
ok("CONTROL: a non-paused repo is scanned (not NA 'paused')", j and "paused" not in j["summary"], (j and j["summary"]))

# selftest with stub tools: seeded positive caught / missed
STUBS = os.path.join(T, "stubs")
os.makedirs(STUBS)


def stub(name, body):
    p = os.path.join(STUBS, name)
    open(p, "w").write("#!/bin/sh\n" + body)
    os.chmod(p, 0o755)
    return p


# a bandit that reports B602 HIGH when the scanned file contains shell=True (blind otherwise)
GOOD_BANDIT = stub("bandit_good", r'''
for f in "$@"; do case "$f" in *.py) if grep -q "shell=True" "$f" 2>/dev/null; then
printf '{"results":[{"filename":"%s","line_number":5,"test_id":"B602","issue_severity":"HIGH","issue_confidence":"HIGH","issue_text":"subprocess call with shell=True"}]}\n' "$f"; exit 1; fi; esac; done
echo '{"results":[]}'; exit 0
''')
BLIND_BANDIT = stub("bandit_blind", "echo '{\"results\":[]}'\nexit 0\n")
rc, j, out = gate("gate_scanners.py", "selftest", "--tools", "bandit", env_extra=["QA_TOOL_BANDIT=" + GOOD_BANDIT])
sd = (j or {}).get("details", {})
ok("selftest: a bandit that sees shell=True CATCHES the seeded B602 (recall 1/1, PASS)", j and j["verdict"] == "PASS" and sd.get("caught") == 1 and sd.get("recall") == 1.0, (j and j["summary"], sd))
ok("selftest: seeds of tools that were not selected are UNMEASURED, never counted", sorted(sd.get("unmeasured", [])) == ["gitleaks", "pip-audit"], sd.get("unmeasured"))
rc, j, out = gate("gate_scanners.py", "selftest", "--tools", "bandit", env_extra=["QA_TOOL_BANDIT=" + BLIND_BANDIT])
sd = (j or {}).get("details", {})
ok("NEGATIVE control: a blind bandit MISSES the seeded B602: recall 0/1 and the verdict is FLAG (recall gap)", j and j["verdict"] == "FLAG" and sd.get("caught") == 0 and "missed: bandit" in j["summary"], (j and j["summary"], sd))
rc, j, out = gate("gate_scanners.py", "selftest", "--tools", "bandit", env_extra=["QA_TOOL_BANDIT=/nonexistent/bandit"])
ok("selftest with no runnable tool is UNVERIFIED (nothing measurable), not PASS", j and j["verdict"] == "UNVERIFIED", (j and j["summary"]))
ok("selftest never records to state/qa_shadow", not os.path.exists(os.path.join(STATE, "qa_shadow", "scanners.jsonl")))
ok("this test file holds no scannable secret literal (secret-shaped seeds are assembled at run time)", "AKIA" + "Q3EG" not in open(__file__).read().replace('"AKIA" + "Q3EG"', ""))

# real tools (box): the full seeded-positive replay
real = {t: gs.find_tool(t) for t in ("bandit", "gitleaks", "pip-audit")}
if any(real.values()):
    rc, j, out = gate("gate_scanners.py", "selftest", env_extra=["PATH=" + os.path.expanduser("~/qa-venv/bin") + ":" + os.path.expanduser("~/qa-tools/bin") + ":" + MINPATH,
                                                                   "HOME=" + os.path.expanduser("~")])
    sd = (j or {}).get("details", {})
    rows = {r["tool"]: r for r in sd.get("seeds", [])}
    print("  info seeded-positive replay: " + (j["summary"] if j else out[-200:]))
    for t in ("bandit", "gitleaks", "pip-audit"):
        r = rows.get(t, {})
        if r.get("status") == "UNMEASURED":
            skip("real %s seeded positive" % t, r.get("why", "")[:80])
        elif real[t]:
            ok("REAL %s catches its seeded positive (recall)" % t, r.get("status") == "CAUGHT", r)
    ok("REAL tools: the benign change is not flagged", sd.get("benign_verdict") not in ("FAIL", "FLAG"), sd.get("benign_summary"))
else:
    skip("real-tool seeded-positive replay", "no bandit/gitleaks/pip-audit on this host")

# ==================================================================================================================== 6. gold set + qa_replay --gold
print("# 6. gold set + qa_replay.py --gold")
GOLD = os.path.join(QA, "gold_set.json")
rows = rp.gold_rows(GOLD)
ids = [r["id"] for r in rows]
ok("gold set parses with unique ids", len(ids) == len(set(ids)) and len(ids) >= 15, ids)
need = {"G1": "DeleteAccountButton", "G7": "reset-password", "G8": "0011", "G9": "aiohttp", "G10": "?token=", "G11": "closed-captions"}
for k, word in need.items():
    r = next((x for x in rows if x["id"] == k), None)
    ok("gold row %s covers '%s' with full 40-hex base/head refs where it replays a commit" % (k, word),
       r and word.lower() in json.dumps(r).lower() and all(len(r[x]) >= 40 for x in ("base", "head")), r and r.get("title"))
ok("every runnable row names a repo and a head", all(r.get("repo") and r.get("head") for r in rows if not (r.get("gate") or "none") == "none"))
# pure judge
tp = {"id": "T", "gate": "antigaming", "kind": "true_positive", "expect": ["A_VACUOUS"]}
ok("judge: expected rule present => CAUGHT", rp.judge_gold(tp, {"verdict": "FAIL", "summary": "s", "details": {"findings": [{"rule": "A_VACUOUS"}]}})[0] == "CAUGHT")
ok("judge NEGATIVE: FLAG but the expected rule is missing => MISSED", rp.judge_gold(tp, {"verdict": "FLAG", "summary": "s", "details": {"findings": [{"rule": "OTHER"}]}})[0] == "MISSED")
ok("judge NEGATIVE: PASS on a true positive => MISSED", rp.judge_gold(tp, {"verdict": "PASS", "summary": "s", "details": {}})[0] == "MISSED")
ok("judge: UNVERIFIED (infra) => UNMEASURED, never MISSED", rp.judge_gold(tp, {"verdict": "UNVERIFIED", "summary": "no docker", "details": {}})[0] == "UNMEASURED")
ok("judge: a miss on a row with `pending` => EXPECTED_AFTER_MERGE", rp.judge_gold(dict(tp, pending="landing"), {"verdict": "PASS", "summary": "s", "details": {}})[0] == "EXPECTED_AFTER_MERGE")
ok("judge: a catch on a row with `pending` is still CAUGHT (the landing check exists)", rp.judge_gold(dict(tp, pending="landing"), {"verdict": "FAIL", "summary": "s", "details": {"findings": [{"rule": "A_VACUOUS"}]}})[0] == "CAUGHT")
bn = {"id": "B", "gate": "antigaming", "kind": "false_positive_fixed"}
ok("judge: benign row PASS => CLEAN", rp.judge_gold(bn, {"verdict": "PASS", "summary": "", "details": {}})[0] == "CLEAN")
ok("judge NEGATIVE: benign row FLAG => FALSE_POSITIVE", rp.judge_gold(bn, {"verdict": "FLAG", "summary": "x", "details": {}})[0] == "FALSE_POSITIVE")
rvr = {"id": "R", "gate": "reviewer", "kind": "true_positive", "expect_findings": [{"file_re": "auth\\.py$", "min_severity": "high"}]}
ok("judge: reviewer finding on auth.py at high => CAUGHT", rp.judge_gold(rvr, {"verdict": "FLAG", "summary": "", "details": {"findings": [{"file": "app/auth.py", "severity": "high"}]}})[0] == "CAUGHT")
ok("judge NEGATIVE: reviewer finding at medium only => MISSED", rp.judge_gold(rvr, {"verdict": "FLAG", "summary": "", "details": {"findings": [{"file": "app/auth.py", "severity": "medium"}]}})[0] == "MISSED")
ok("judge: gate 'none' => UNCOVERED", rp.judge_gold({"gate": "none", "kind": "known_gap"}, None)[0] == "UNCOVERED")
ok("judge: 'pending:x' gate => EXPECTED_AFTER_MERGE", rp.judge_gold({"gate": "pending:x", "kind": "true_positive", "pending": "later"}, None)[0] == "EXPECTED_AFTER_MERGE")

# end to end on a fixture repo with its own gold file (real gates, real entry point)
GR = os.path.join(T, "goldrepos")
os.makedirs(GR)
env_keep = dict(os.environ)
os.environ["OVN_REPOS_DIR"] = GR
d = os.path.join(GR, "goldfx")
os.makedirs(d)
sh(d, "git", "init", "-q", "-b", "main")
b0 = commit(d, {"app/m.py": "def f():\n    return 1\n", "tests/__init__.py": ""}, "init")
h_vac = commit(d, {"tests/test_new.py": "def test_health():\n    assert True\n"}, "feat: add health test")
h_ok = commit(d, {"tests/test_real.py": "from app.m import f\n\n\ndef test_f():\n    assert f() == 1\n"}, "feat: add real test")
h_route = commit(d, {"app/auth.py": ROUTE_NOAUTH}, "feat: add reset route")
gold_fx = {"version": 2, "rows": [
    {"id": "X1", "repo": "goldfx", "base": b0, "head": h_vac, "gate": "antigaming", "kind": "true_positive", "expect": ["A_VACUOUS"]},
    {"id": "X2", "repo": "goldfx", "base": h_vac, "head": h_ok, "gate": "antigaming", "kind": "benign"},
    {"id": "X3", "repo": "goldfx", "base": h_ok, "head": h_route, "gate": "reviewer", "kind": "true_positive", "expect_findings": [{"file_re": "auth\\.py$", "min_severity": "high"}]},
    {"id": "X4", "repo": "goldfx", "base": h_vac, "head": h_ok, "gate": "antigaming", "kind": "true_positive", "expect": ["A_VACUOUS"]},   # seeded WRONG expectation
    {"id": "X5", "repo": "goldfx", "base": b0, "head": h_vac, "gate": "landing:no_such_check", "kind": "true_positive", "pending": "not built yet"},
    {"id": "X6", "repo": "goldfx", "base": b0, "head": h_ok, "gate": "none", "kind": "known_gap"}]}
def shadow_snapshot():
    out = {}
    for fn in sorted(os.listdir(os.path.join(STATE, "qa_shadow"))):
        out[fn] = os.path.getsize(os.path.join(STATE, "qa_shadow", fn))
    return out


snap0 = shadow_snapshot()
gf = os.path.join(T, "gold_fx.json")
json.dump(gold_fx, open(gf, "w"))
p = subprocess.run(["env", "-i", "PATH=" + MINPATH, "NTFY_SERVER=http://127.0.0.1:9", "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + GR, "HOME=" + T, "QA_PAUSED_REPOS=none",
                    PY, os.path.join(QA, "qa_replay.py"), "--gold", "--gold-file", gf, "--json"], capture_output=True, text=True, timeout=300)
js = None
try:
    js = json.loads(p.stdout.strip().splitlines()[-1])
except Exception:  # noqa: BLE001
    pass
st = {r["id"]: r["status"] for r in (js or {}).get("results", [])}
ok("gold --gold end to end: vacuous test CAUGHT, honest test CLEAN, reset route CAUGHT by the reviewer (model-free)", st.get("X1") == "CAUGHT" and st.get("X2") == "CLEAN" and st.get("X3") == "CAUGHT", (st, p.stderr[-200:]))
ok("NEGATIVE control: a row with a wrong expectation is reported MISSED, not silently CAUGHT", st.get("X4") == "MISSED", st)
ok("a missing landing check is EXPECTED_AFTER_MERGE; a gate-less row is UNCOVERED", st.get("X5") == "EXPECTED_AFTER_MERGE" and st.get("X6") == "UNCOVERED", st)
ok("--gold exits 0 by default and writes nothing to qa_shadow", p.returncode == 0 and shadow_snapshot() == snap0, (p.returncode, shadow_snapshot(), snap0))
p2 = subprocess.run(["env", "-i", "PATH=" + MINPATH, "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + GR, "HOME=" + T, "QA_PAUSED_REPOS=none", PY, os.path.join(QA, "qa_replay.py"),
                     "--gold", "--gold-file", gf, "--strict"], capture_output=True, text=True, timeout=300)
ok("--gold --strict exits 1 when a true positive is MISSED", p2.returncode == 1, p2.returncode)
p3 = subprocess.run(["env", "-i", "PATH=" + MINPATH, "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + GR, "HOME=" + T, "QA_PAUSED_REPOS=none", PY, os.path.join(QA, "qa_replay.py"),
                     "--gold", "--gold-file", gf, "--only", "X1,X2,X3", "--strict"], capture_output=True, text=True, timeout=300)
ok("BENIGN control: --only X1,X2,X3 --strict exits 0 (all caught/clean)", p3.returncode == 0, (p3.returncode, p3.stdout[-300:]))
os.environ.clear()
os.environ.update(env_keep)

# the real gold set against the real clones where they (and the commits) exist (Mac dev + box): informational, caught rows must stay caught
real_dirs = [x for x in (os.environ.get("QA_REAL_REPOS_DIR"), os.path.expanduser("~/overnight-queue/repos"), os.path.expanduser("~/LocalProjects")) if x and os.path.isdir(x)]
present = []
real_dir = None
for rd0 in real_dirs:
    ids0 = []
    for r in rows:
        if not r.get("repo") or (r.get("gate") or "none") == "none" or r["gate"].startswith("pending:") or r["gate"].startswith("landing:") or r["gate"] == "migrations":
            continue
        cd = os.path.join(rd0, r["repo"])
        if os.path.isdir(cd) and all(subprocess.run(["git", "-C", cd, "cat-file", "-e", x + "^{commit}"], capture_output=True).returncode == 0 for x in (r["base"], r["head"])):
            ids0.append(r["id"])
    if len(ids0) > len(present):
        present, real_dir = ids0, rd0
if present:
    pr = subprocess.run(["env", "-i", "PATH=" + MINPATH, "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + real_dir, "HOME=" + os.path.expanduser("~"), "QA_FETCH_WAIT=0",
                         "QA_PAUSED_REPOS=none", PY, os.path.join(QA, "qa_replay.py"), "--gold", "--json", "--only", ",".join(present)], capture_output=True, text=True, timeout=900)
    try:
        jr = json.loads(pr.stdout.strip().splitlines()[-1])
        stt = {r["id"]: r["status"] for r in jr["results"]}
        print("  info real gold replay (%s, %d rows with commits present): %s" % (real_dir, len(present), json.dumps(jr["totals"], sort_keys=True)))
        bad = {k: v for k, v in stt.items() if v in ("MISSED", "FALSE_POSITIVE", "UNMEASURED")}
        ok("real gold set: every present row is CAUGHT or CLEAN (no MISSED, FALSE_POSITIVE or UNMEASURED)", not bad, bad)
    except Exception:  # noqa: BLE001
        skip("real gold replay", "unparsable output")
else:
    skip("real gold replay", "no real clone with the gold commits on this host")

# ==================================================================================================================== 7. mark-escape script + cron line
print("# 7. mark-escape script (dry run by default) + shipped cron line")
ME = os.path.join(QA, "mark_escapes_2026-10-03.sh")
p = subprocess.run(["bash", ME], capture_output=True, text=True, env={"PATH": os.environ.get("PATH", ""), "OVN_DIR": OVN, "HOME": T})
ok("dry run prints exactly the three mark-escape commands and writes nothing", p.returncode == 0 and p.stdout.count("DRY RUN") == 3 and "06435083" in p.stdout
   and "ae047db6" in p.stdout and "1f92e120" in p.stdout and not os.path.exists(os.path.join(STATE, "qa_ledger.jsonl")), p.stdout[-300:])
p = subprocess.run(["bash", ME, "--apply"], capture_output=True, text=True, env={"PATH": os.environ.get("PATH", ""), "OVN_DIR": OVN, "HOME": T})
ok("NEGATIVE control: --apply without MARK_ESCAPE_CONFIRM=yes refuses (rc 3) and writes nothing", p.returncode == 3 and "refusing" in p.stderr and not os.path.exists(os.path.join(STATE, "qa_ledger.jsonl")), (p.returncode, p.stderr))
p = subprocess.run(["bash", ME, "--apply"], capture_output=True, text=True,
                   env={"PATH": os.environ.get("PATH", ""), "OVN_DIR": OVN, "OVN_REPOS_DIR": os.path.join(T, "no_such_repos"), "HOME": T, "MARK_ESCAPE_CONFIRM": "yes"})
ok("--apply with confirmation runs the three calls against the TEMP ovn dir (no clones there: each answers UNVERIFIED, none crashes)",
   p.stdout.count("== mark-escape") == 3 and p.stdout.count('"verdict": "UNVERIFIED"') == 3 and "Traceback" not in p.stdout + p.stderr, (p.stdout[-300:], p.stderr[-200:]))
refs = [json.loads(l) for l in [x for x in p.stdout.splitlines() if x.startswith("{")]]
ok("the refs used in the script are the escape_ref values recorded in the gold set",
   {"06435083508d955023563f36540d78ff318c6d89", "ae047db63f344f4ed6603dda1f65cc9dc9041da4", "1f92e12053d01a2793bdef9edcee782c4c9666f4"} == {r.get("escape_ref") for r in rows if r.get("escape_ref")})
CT = os.path.join(OQ, "scripts", "cron.txt")
active = [l for l in open(CT).read().splitlines() if l.strip() and not l.lstrip().startswith("#")]
ok("scripts/cron.txt ships exactly two active lines: the baseline refresh for iptv_apps and xlite + the ghost-test canary (2026-10-04)",
   len(active) == 2 and "baseline_refresh_cron.sh" in active[0] and 'OVN_BASELINE_REFRESH_REPOS="iptv_apps xlite"' in active[0] and active[0].startswith("11 */3 ")
   and "ovn_test_collect_canary.sh" in active[1] and active[1].startswith("37 */6 "), active)
ok("the cron line is not installed by any script we ship (no crontab write in the shipped files)", "crontab -" not in "\n".join(active))
ok("qa/baseline_refresh_cron.txt carries the same scoped line", 'OVN_BASELINE_REFRESH_REPOS="iptv_apps xlite"' in open(os.path.join(QA, "baseline_refresh_cron.txt")).read())

shutil.rmtree(T, ignore_errors=True)
print("\nQA h11 gate tests: %d passed, %d failed, %d skipped" % (P, F, S))
sys.exit(1 if F else 0)
