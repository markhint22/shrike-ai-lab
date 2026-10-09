#!/usr/bin/env python3
"""scripts/ovn_ghost_tests.py - one-time relocation of "ghost" tests (2026-10-09).

A ghost test is a `test_*.py` that lives under iptv-backend/app/{jobs,routers,services}: pytest's testpaths point at iptv-backend/tests, so those files were
never collected and never ran (18-20 of them in iptv_apps; the 2026-10-08 relocation deploy stops NEW ones from being written there, it does not move the old ones).

usage: ovn_ghost_tests.py run <repo> [--dry-run] [--remote <url>] [--backend-dir iptv-backend] [--branch overnight/feature]
  --dry-run   print the plan (which file would move where), change NOTHING (no worktree; the only side effect is the usual fetch of the remote-tracking ref)
  --remote    where to fetch from and push to (default `origin`); a URL is fine - the clone's refs/remotes/origin/<branch> is refreshed from it
Flow, in a lib_worktree.sh worktree of origin/<branch> (the live clone the fleet is editing is never touched):
  for every ghost: `git mv` it into <backend>/tests/ (a name that already exists there gets a `_relocated` suffix), run that ONE file with the repo venv's pytest
  (60 s timeout). Passes -> keep it, commit `chore(tests): relocate ghost test X into the collected dir`. A failure at the NEW location is NOT yet a verdict (the move itself can
  break a test: Path(__file__)-relative paths, relative imports, fixtures, conftest): the file is moved back and run once IN PLACE (`pytest <orig> --rootdir=.`). Only when it
  ALSO fails there (pytest rc 1, no environment signature) is it `git rm`'ed and listed in the body of one closing commit `chore(tests): drop N ghost tests that never ran`;
  if it passes in place it is relocation-sensitive. Anything else is UNDECIDED and the file is left exactly where it was (never deleted, never moved): pytest rc 2/3/4/5, a timeout,
  an rc 1 whose output shows a broken environment (missing module, no DB connection ...), a failure only the relocation causes, and any file whose source mentions `__file__`
  (its result depends on where it lives, so a pass after the move can silently check a different tree).
  Safety (a broken environment must never look like a broken test; test code is deleted only on positive evidence):
    - PREFLIGHT before any change: `pytest <backend>/tests --collect-only` with the same python and env must succeed, else abort (exit 1, nothing touched).
    - after the loop: abort (exit 1, nothing pushed) when no ghost passed but some would be deleted, or when more than half of the ghosts would be deleted.
  Then push NON-force HEAD:<branch>; on a rejection: fetch, rebase, retry once. Aborts (exit 1, nothing pushed) when state/PAUSED exists, before the work and
  again right before the push. A second run finds no ghosts and is a no-op.
env: OVN_DIR (default ~/overnight-queue); OVN_GHOST_PY (a python that has pytest; default the repo's venv); OVN_GHOST_TIMEOUT (pytest seconds, 60);
     OVN_GHOST_PREFLIGHT_TIMEOUT (seconds for the collect-only preflight, 300); OVN_GHOST_GIT_NAME / OVN_GHOST_GIT_EMAIL (commit identity, default the fleet's overnight-fleet identity)
exit: 0 done / nothing to do / dry run, 1 aborted or push failed."""
import os
import re
import subprocess
import sys

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
GHOST_DIRS = ("jobs", "routers", "services")


def sh(cmd, cwd=None, timeout=None, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def git(repo, *args, timeout=60):
    return sh(["git", "-C", repo] + list(args), timeout=timeout)


def paused():
    return os.path.exists(os.path.join(OVN_DIR, "state", "PAUSED"))


def lib_worktree():
    for d in (os.path.dirname(os.path.abspath(__file__)), os.path.join(OVN_DIR, "scripts")):
        p = os.path.join(d, "lib_worktree.sh")
        if os.path.exists(p):
            return p
    return None


def plan_moves(tree_files, backend):
    """[(src, dest)] for every ghost in the given tracked-file list, plus [(src, why)] for the ones that cannot be moved."""
    pat = re.compile(r"^%s/app/(?:%s)/(?:.*/)?(test_[^/]+\.py)$" % (re.escape(backend), "|".join(GHOST_DIRS)))
    existing = set(tree_files)
    used = set()
    moves, skipped = [], []
    for src in sorted(tree_files):
        m = pat.match(src)
        if not m:
            continue
        base = m.group(1)
        dest = "%s/tests/%s" % (backend, base)
        if dest in existing or dest in used:
            dest = "%s/tests/%s_relocated.py" % (backend, base[:-3])
        if dest in existing or dest in used:
            skipped.append((src, "both %s and its _relocated name already exist" % base))
            continue
        used.add(dest)
        moves.append((src, dest))
    return moves, skipped


def find_py(clone, wt, backend):
    env = os.environ.get("OVN_GHOST_PY")
    if env and os.path.exists(env):
        return env
    for base in (wt, clone):
        for cand in ("%s/.venv/bin/python" % backend, ".venv/bin/python", "backend/.venv/bin/python"):
            p = os.path.join(base, cand)
            if os.path.exists(p):
                return p
    return None


# an rc-1 pytest run whose output shows one of these is a broken ENVIRONMENT, not a broken test: never a reason to delete the file
ENV_SIGNS = re.compile(r"No module named|ModuleNotFoundError|ImportError|Connection ?refused|ConnectionError|could not connect|OperationalError|"
                       r"Temporary failure in name resolution|Name or service not known|environment variable", re.I)
MAX_DROP_FRACTION = 0.5


LOCATION_RELATIVE = re.compile(r"__file__")


def location_relative(text):
    """True when the test's source locates things relative to ITS OWN path (`Path(__file__).parent...`): such a test checks a different tree (or nothing) once it is moved,
    so neither its pass nor its failure at the new location says anything about the original. It is left where it is for a human (never moved, never deleted)."""
    return bool(LOCATION_RELATIVE.search(text or ""))


def classify(rc, output):
    """'pass' (rc 0) | 'fail' (rc 1 = pytest ran the tests and one failed, no environment signature) | 'undecided' (everything else: rc 2/3/4/5, timeout 124, env trouble)."""
    if rc == 0:
        return "pass"
    if rc == 1 and not ENV_SIGNS.search(output or ""):
        return "fail"
    return "undecided"


def main(argv):
    if len(argv) < 3 or argv[1] != "run":
        print("usage: ovn_ghost_tests.py run <repo> [--dry-run] [--remote <url>] [--backend-dir D] [--branch B]")
        return 2
    repo, flags = argv[2], argv[3:]

    def opt(name, default):
        return flags[flags.index(name) + 1] if name in flags and flags.index(name) + 1 < len(flags) else default
    dry = "--dry-run" in flags
    remote, backend, branch = opt("--remote", "origin"), opt("--backend-dir", "iptv-backend"), opt("--branch", "overnight/feature")
    if paused():
        print("%s: state/PAUSED exists - abort, nothing done" % repo)
        return 1
    clone = os.path.join(OVN_DIR, "repos", repo)
    if not os.path.isdir(os.path.join(clone, ".git")):
        print("%s: no clone at %s - abort" % (repo, clone))
        return 1
    f = git(clone, "fetch", "-q", remote, "+refs/heads/%s:refs/remotes/origin/%s" % (branch, branch))
    if f.returncode != 0:
        print("%s: fetch of %s %s failed: %s" % (repo, remote, branch, f.stderr.strip()[:200]))
        return 1
    ls = git(clone, "ls-tree", "-r", "--name-only", "origin/%s" % branch)
    if ls.returncode != 0:
        print("%s: origin/%s not found: %s" % (repo, branch, ls.stderr.strip()[:200]))
        return 1
    moves, skipped = plan_moves(ls.stdout.split("\n"), backend)
    for src, why in skipped:
        print("  SKIP %s: %s" % (src, why))
    if not moves:
        print("%s: no ghost tests under %s/app/{%s} - nothing to do" % (repo, backend, ",".join(GHOST_DIRS)))
        return 0
    if dry:
        print("%s: DRY-RUN %d ghost test(s) would be relocated into %s/tests/ (each run once with pytest after the move: pass -> kept; fail at the new place AND in place -> git rm; anything else stays; __file__-users stay):" % (repo, len(moves), backend))
        for src, dest in moves:
            print("  PLAN git mv %s -> %s" % (src, dest))
        return 0
    lib = lib_worktree()
    if lib is None:
        print("%s: lib_worktree.sh not found - abort" % repo)
        return 1
    o = sh(["bash", "-c", 'source "$1"; wt_open "$2" "$3" --detach --tag=ghost', "_", lib, clone, branch])
    wt = o.stdout.strip().split("\n")[-1] if o.returncode == 0 else ""
    if not wt or not os.path.isdir(wt):
        print("%s: could not open a worktree of origin/%s - abort" % (repo, branch))
        return 1
    try:
        return work(repo, clone, wt, moves, backend, branch, remote, lib)
    finally:
        sh(["bash", "-c", 'source "$1"; wt_close "$2" "$3"', "_", lib, clone, wt])


def work(repo, clone, wt, moves, backend, branch, remote, lib):
    sh(["bash", "-c", 'source "$1"; wt_link_envs "$2" "$3"', "_", lib, clone, wt])
    py = find_py(clone, wt, backend)
    if py is None:
        print("%s: no python with pytest found (OVN_GHOST_PY / %s/.venv) - abort" % (repo, backend))
        return 1
    ident = ["-c", "user.name=%s" % os.environ.get("OVN_GHOST_GIT_NAME", "overnight-fleet"), "-c", "user.email=%s" % os.environ.get("OVN_GHOST_GIT_EMAIL", "overnight@shrike-labs.local")]
    tmo = int(os.environ.get("OVN_GHOST_TIMEOUT", "60"))
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", CI="true")
    # PREFLIGHT: the same python + env must be able to collect the existing suite, otherwise "pytest failed" proves nothing about a ghost
    pre_tmo = int(os.environ.get("OVN_GHOST_PREFLIGHT_TIMEOUT", "300"))
    try:
        pre = sh([py, "-m", "pytest", "tests", "--collect-only", "-q", "-p", "no:cacheprovider"], cwd=os.path.join(wt, backend), timeout=pre_tmo, env=env)
        pre_rc, pre_out = pre.returncode, (pre.stdout.strip().split("\n")[-1] if pre.stdout.strip() else pre.stderr.strip()[-160:])
    except (subprocess.TimeoutExpired, OSError) as e:
        pre_rc, pre_out = 124, "%s: %s" % (type(e).__name__, e)
    if pre_rc != 0:
        print("%s: PREFLIGHT failed (pytest %s/tests --collect-only rc %d: %s) - the test environment is broken, no ghost judged, nothing changed" % (repo, backend, pre_rc, pre_out[:160]))
        return 1
    kept, dropped, undecided, commits = [], [], [], 0
    def run_one(path, rootdir=False):
        """(rc, last output line, verdict) of one pytest run of <path> (relative to the backend dir) from the backend dir; rootdir pins --rootdir to the backend dir (used for the
        in-place run: a file outside the configured testpaths still gets the backend's ini/conftest chain)."""
        try:
            r = sh([py, "-m", "pytest", path, "-q", "-x", "-p", "no:cacheprovider"] + (["--rootdir=."] if rootdir else []), cwd=os.path.join(wt, backend), timeout=tmo, env=env)
            return r.returncode, (r.stdout.strip().split("\n")[-1] if r.stdout.strip() else r.stderr.strip()[-120:]), classify(r.returncode, (r.stdout or "") + "\n" + (r.stderr or ""))
        except subprocess.TimeoutExpired:
            return 124, "timed out after %ds" % tmo, "undecided"

    for src, dest in moves:
        try:
            with open(os.path.join(wt, src), encoding="utf-8", errors="replace") as fh:
                src_text = fh.read()
        except OSError:
            src_text = ""
        if location_relative(src_text):
            undecided.append((src, 0, "locates files relative to __file__"))
            print("  UNDECIDED %s (uses __file__: the result would depend on where it lives) - left where it is, not moved, not deleted" % src)
            continue
        os.makedirs(os.path.join(wt, os.path.dirname(dest)), exist_ok=True)
        mv = git(wt, "mv", src, dest)
        if mv.returncode != 0:
            print("  SKIP %s: git mv failed: %s" % (src, mv.stderr.strip()[:120]))
            continue
        rc, tail, verdict = run_one(os.path.relpath(dest, backend))
        if verdict == "fail":
            # a failure at the NEW location may be caused by the move itself (paths, relative imports, fixtures, conftest). Delete only when the very same file ALSO fails
            # where it was written; if it passes (or cannot be judged) there, the relocation broke it and a human decides.
            git(wt, "mv", "-f", dest, src)
            rc0, tail0, verdict0 = run_one(src[len(backend) + 1:], rootdir=True)
            if verdict0 == "fail":
                verdict, tail = "fail", "%s | in place: rc %d: %s" % (tail, rc0, tail0)
            else:
                verdict, tail = "undecided", "failed relocated (%s) but %s in place (rc %d: %s): relocation-sensitive" % (tail, "passes" if verdict0 == "pass" else "is inconclusive", rc0, tail0)
                undecided.append((src, rc, tail))
                print("  UNDECIDED %s (%s) - left where it is, not deleted" % (src, tail[:160]))
                continue
            git(wt, "mv", src, dest)
        base = os.path.basename(dest)
        if verdict == "pass":
            c = git(wt, *ident, "commit", "-q", "-m", "chore(tests): relocate ghost test %s into the collected dir" % base, "--", src, dest)   # src: the staged deletion half of the rename
            if c.returncode != 0:
                print("  FAIL commit of %s: %s" % (dest, c.stderr.strip()[:160]))
                return 1
            commits += 1
            kept.append(dest)
            print("  KEEP %s -> %s (pytest rc 0)" % (src, dest))
        elif verdict == "fail":
            git(wt, "rm", "-q", "-f", "--", dest)
            dropped.append((src, rc, tail))
            print("  DROP %s (pytest rc %d: %s)" % (src, rc, tail[:100]))
        else:
            git(wt, "mv", "-f", dest, src)   # undo exactly this rename (earlier removals stay staged for the closing commit); the temporary worktree is ours
            undecided.append((src, rc, tail))
            print("  UNDECIDED %s (pytest rc %d: %s) - left where it is, not deleted" % (src, rc, tail[:100]))
    if dropped and (not kept or len(dropped) > MAX_DROP_FRACTION * len(moves)):
        print("%s: ABORT - %d of %d ghost(s) would be deleted and %d passed: that looks like an environment problem, not %d broken tests. Nothing pushed "
              "(%d local commit(s) are discarded with the temporary worktree)" % (repo, len(dropped), len(moves), len(kept), len(dropped), commits))
        return 1
    if dropped:
        body = "\n".join("- %s (pytest rc %d: %s)" % (s, rc, t[:100]) for s, rc, t in dropped)
        c = git(wt, *ident, "commit", "-q", "-m", "chore(tests): drop %d ghost tests that never ran" % len(dropped), "-m",
                "These files sat outside pytest's collected dir (%s/tests), so they never ran. Each was tried at its new location with a working test environment "
                "(preflight collect-only passed) and ALSO where it was written (run in place): it failed in both (pytest rc 1, no environment error in the output). "
                "A failing test can still be a real finding (it may assert something the code no longer does): the files are listed below and recoverable from this commit's parent.\n\n%s" % (backend, body))
        if c.returncode != 0:
            print("  FAIL commit of the removals: %s" % c.stderr.strip()[:160])
            return 1
        commits += 1
    if commits == 0:
        print("%s: nothing to push" % repo)
        return 0
    if paused():
        print("%s: state/PAUSED appeared - abort before the push (%d commit(s) stay local in a temporary worktree and are discarded)" % (repo, commits))
        return 1
    p = git(wt, "push", "-q", remote, "HEAD:%s" % branch, timeout=60)
    if p.returncode != 0:
        f = git(wt, "fetch", "-q", remote, branch)
        rb = git(wt, "rebase", "FETCH_HEAD") if f.returncode == 0 else f
        if rb.returncode != 0:
            git(wt, "rebase", "--abort")
            print("%s: push rejected and the rebase failed (%s) - nothing pushed" % (repo, (rb.stderr or f.stderr).strip()[:160]))
            return 1
        p = git(wt, "push", "-q", remote, "HEAD:%s" % branch, timeout=60)
        if p.returncode != 0:
            print("%s: push failed twice (%s) - nothing pushed" % (repo, p.stderr.strip()[:160]))
            return 1
        print("  push was rejected once (non-fast-forward): fetched, rebased, pushed")
    print("%s: PUSHED %d commit(s) to %s %s - kept %d, dropped %d, undecided %d (left in place)" % (repo, commits, remote, branch, len(kept), len(dropped), len(undecided)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
