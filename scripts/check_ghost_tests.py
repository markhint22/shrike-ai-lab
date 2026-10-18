#!/usr/bin/env python3
"""Ghost-test check (2026-10-18, test-automation-agent audit): flags test_*.py files a cycle added/changed that the
repo's own test command can never collect.  Live: staged steps created ROOT tests/test_execution_engine.py (e5fc16b) and
tests/test_execution_engine_time_budget.py (ae277a2) in a repo whose pytest rootdir is backend/ -> the 'test' was never run,
the item was credited on a vacuous test (and tests/test_flakes_router.py there actually FAILS when run).

Usage: check_ghost_tests.py <repo> <before_sha> <after_sha>      exit 0 clean, 1 ghost test file(s) found.
Heuristic: a 'collection root' is a dir holding pytest.ini / conftest.py / [tool.pytest] pyproject / [tool:pytest] setup.cfg
(at after_sha).  If at least one collection root exists, a changed test file under none of them is a ghost.  No root = silent.
"""
import re
import subprocess
import sys


def git(repo, *a):
    p = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)
    return p.returncode, p.stdout


def roots(repo, sha):
    rc, out = git(repo, "ls-tree", "-r", "--name-only", sha)
    if rc != 0:
        return None
    rs = set()
    for p in out.splitlines():
        base = p.rsplit("/", 1)[-1]
        d = p.rsplit("/", 1)[0] if "/" in p else ""
        if "node_modules" in p or "/venv/" in "/" + p or "/.venv/" in "/" + p:
            continue
        if base in ("pytest.ini", "conftest.py"):
            # tests/conftest.py makes tests/ a root only for itself; its parent dir config decides otherwise
            rs.add(d)
        elif base in ("pyproject.toml", "setup.cfg", "tox.ini"):
            rc2, txt = git(repo, "show", "%s:%s" % (sha, p))
            if rc2 == 0 and re.search(r"\[tool\.pytest|\[tool:pytest|\[pytest\]", txt):
                rs.add(d)
    return rs


def under(path, d):
    return d == "" or path == d or path.startswith(d + "/")


def main(argv):
    if len(argv) < 4:
        return 0
    repo, before, after = argv[1:4]
    rs = roots(repo, after)
    if not rs:
        return 0
    rc, out = git(repo, "diff", "--name-only", "--diff-filter=AM", before, after)
    if rc != 0:
        return 0
    bad = []
    for p in out.splitlines():
        b = p.rsplit("/", 1)[-1]
        if not (p.endswith(".py") and (b.startswith("test_") or b.endswith("_test.py"))):
            continue
        # a root of "" (repo-root config) collects everything below it
        if not any(under(p, d) for d in rs):
            bad.append(p)
    for p in bad:
        print("  ✗ GHOST-TEST: %s is outside every pytest collection root (%s) and will never run" % (p, ", ".join(sorted(r or "." for r in rs))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
