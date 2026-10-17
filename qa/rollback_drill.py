#!/usr/bin/env python3
"""rollback_drill.py - Phase 5 / QA plan 5A rollback drill: prove the PREVIOUS prod tag can be restored and still builds, entirely in a scratch clone. SHADOW (advisory).

    rollback_drill.py run --repo R [--tag prod-<ts>-R] [--smoke-cmd "CMD"] [--no-record]

What it does (read-only on the real clone: a throwaway `git clone --shared` under the temp dir that is always removed afterwards; never pushes, never fetches, no network):
  1. picks the tag: --tag, else the PREVIOUS prod tag (the second newest `prod-<ts>-<repo>`, i.e. what a rollback of the latest promote would restore); with a single tag, that one.
  2. checks it out detached in the scratch clone and verifies the restore BYTE FOR BYTE: the checked-out tree id equals the tag's tree id, `git diff <tag>` is empty and there is no
     modified / untracked file. Any difference is a FAIL.
  3. runs the repo's offline build / health smoke in the scratch tree with a scrubbed environment (no proxies, OVN_OFFLINE=1, no secrets):
       --smoke-cmd / state or env OVN_ROLLBACK_SMOKE_CMD_<REPO> (shell string, run with `sh -c`, 300 s cap) when given, else the heuristics
       - python sources: `python3 -m compileall -q` over the tracked python files (venvs / node_modules / .git excluded)
       - package.json: must parse as JSON (an unparsable manifest is a FAIL); the `build` script is NOT run (installing dependencies needs the network): noted, not counted as a smoke
  A smoke that covers only part of the repo (a native / engine project file in the tree, or python < 25% of the tracked files, with no custom command) is marked partial and caps the
  verdict at UNVERIFIED. Set OVN_ROLLBACK_SMOKE_CMD_<REPO> to make a PASS mean something there. The row is written to qa_shadow but its gate is in release_candidate.NON_CODE_GATES: a drill
  verdict never feeds the release planner or the promote manifest.
  PASS = restore identical AND at least one smoke ran and passed; FAIL = checkout failed, restore differs, or a smoke failed; UNVERIFIED = restore identical but no smoke could run
  (nothing to compile, no command), or no clone / no prod tag. DB downgrades are out of scope (the schema is not rolled back by a code rollback).
Result: one JSON line on stdout and (unless --no-record) one row in state/qa_shadow/rollback_drill.jsonl (the plan's "rollback drill result per repo"). Always exit 0.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_ledger as ql  # noqa: E402
import phase5_common as p5  # noqa: E402
import promote_manifest as pm  # noqa: E402

GATE = "rollback_drill"
SMOKE_TIMEOUT = 300
EXCLUDE_DIRS = {".git", ".venv", "venv", "node_modules", "__pycache__", "dist", "build", ".tox", ".mypy_cache"}
DRILL_PREFIX = "rbdrill-"


def scrub_env(scratch):
    keep = {k: v for k, v in os.environ.items() if k in ("PATH", "LANG", "LC_ALL", "TMPDIR")}
    keep.update({"HOME": scratch, "OVN_OFFLINE": "1", "PYTHONDONTWRITEBYTECODE": "1", "NO_PROXY": "*", "no_proxy": "*", "GIT_TERMINAL_PROMPT": "0"})
    return keep


def safe_cleanup(path):
    """Remove the scratch dir ONLY when it is a real directory named rbdrill-* directly under the temp root (never HOME, never a clone)."""
    try:
        real = os.path.realpath(path)
        root = os.path.realpath(tempfile.gettempdir())
        if os.path.basename(real).startswith(DRILL_PREFIX) and os.path.dirname(real) == root and real != os.path.realpath(os.path.expanduser("~")):
            shutil.rmtree(real, ignore_errors=True)
            return True
    except OSError:
        pass
    return False


def integrity(src, clone, tag):
    """-> (ok, detail). Byte-for-byte: tree id, empty diff vs the tag, nothing modified or untracked."""
    rc1, t_src, _ = pm._g(src, "rev-parse", "--verify", "-q", tag + "^{tree}")
    rc2, t_cl, _ = pm._g(clone, "rev-parse", "--verify", "-q", "HEAD^{tree}")
    if rc1 != 0 or rc2 != 0 or t_src != t_cl:
        return False, "tree id differs (tag %s, checkout %s)" % (t_src[:10], t_cl[:10])
    rc, _o, _e = pm._g(clone, "diff", "--quiet", tag, "--")
    if rc != 0:
        return False, "working tree differs from the tag (git diff)"
    rc, out, _ = pm._g(clone, "status", "--porcelain", "--untracked-files=all")
    if rc != 0 or out.strip():
        return False, "modified/untracked files after checkout: %s" % out.strip().splitlines()[0][:80]
    return True, "tree %s identical, diff empty" % t_cl[:10]


def python_files(clone):
    rc, out, _ = pm._g(clone, "ls-files", "-z", "--", "*.py")
    files = [f for f in out.split("\0") if f]
    return [f for f in files if not (set(f.split("/")[:-1]) & EXCLUDE_DIRS)]


STACK_MARKERS = ("project.godot", "build.gradle", "build.gradle.kts", "Package.swift", "Podfile", "pubspec.yaml", "Cargo.toml", "go.mod", "pom.xml")


def non_python_stack(clone, n_py):
    """-> a reason string when the repo is (also) something the python/package.json heuristics cannot build-check, else ''. Markers: a native / engine project file anywhere in the tree
    (not under an excluded dir), or python being under 25% of the tracked files."""
    rc, out, _ = pm._g(clone, "ls-files", "-z")
    files = [f for f in out.split("\0") if f]
    found = sorted(set(os.path.basename(f) for f in files if os.path.basename(f) in STACK_MARKERS and not (set(f.split("/")[:-1]) & EXCLUDE_DIRS))
                   | set(os.path.basename(f) for f in files if f.endswith(".xcodeproj/project.pbxproj") or f.endswith(".pbxproj")))
    if found:
        return "repo also contains %s which the smoke does not build" % ", ".join(found[:3])
    if files and n_py and n_py * 4 < len(files):
        return "python is %d of %d tracked files" % (n_py, len(files))
    return ""


def smoke(clone, repo, custom, scratch):
    """-> (list of {name, status PASS|FAIL, detail}, notes list)."""
    env = scrub_env(scratch)
    results, notes = [], []
    cmd = custom or os.environ.get("OVN_ROLLBACK_SMOKE_CMD_" + re.sub(r"[^A-Za-z0-9]", "_", repo).upper(), "")
    if cmd:
        try:
            p = subprocess.run(["sh", "-c", cmd], cwd=clone, env=env, capture_output=True, timeout=SMOKE_TIMEOUT)
            results.append({"name": "custom", "status": "PASS" if p.returncode == 0 else "FAIL",
                            "detail": ("rc=%d %s" % (p.returncode, (p.stderr or p.stdout).decode("utf-8", "replace").strip()[-160:]))})
        except subprocess.TimeoutExpired:
            results.append({"name": "custom", "status": "FAIL", "detail": "timeout after %ds" % SMOKE_TIMEOUT})
        return results, notes
    pyf = python_files(clone)
    if pyf:
        try:
            p = subprocess.run([sys.executable, "-m", "compileall", "-q", "-f"] + pyf, cwd=clone, env=env, capture_output=True, timeout=SMOKE_TIMEOUT)
            results.append({"name": "compileall(%d py files)" % len(pyf), "status": "PASS" if p.returncode == 0 else "FAIL",
                            "detail": "" if p.returncode == 0 else (p.stdout + p.stderr).decode("utf-8", "replace").strip()[-200:]})
        except subprocess.TimeoutExpired:
            results.append({"name": "compileall", "status": "FAIL", "detail": "timeout"})
    pj = os.path.join(clone, "package.json")
    if os.path.isfile(pj):
        try:
            with open(pj) as f:
                j = json.load(f)
            results.append({"name": "package.json parses", "status": "PASS", "detail": ""})
            if isinstance(j, dict) and "build" in (j.get("scripts") or {}):
                notes.append("package.json has a build script: not run (dependency install needs the network)")
        except (OSError, ValueError):
            results.append({"name": "package.json parses", "status": "FAIL", "detail": "invalid JSON"})
    if not results:
        notes.append("nothing to smoke: no python files, no package.json, no custom command")
    else:
        stack = non_python_stack(clone, len(pyf))
        if stack:
            for r in results:
                r["partial"] = True
            notes.append("partial smoke only: %s; set OVN_ROLLBACK_SMOKE_CMD_%s to prove the build" % (stack, re.sub(r"[^A-Za-z0-9]", "_", repo).upper()))
    return results, notes


def drill(repo, rd, tag=None, custom_smoke="", now=None):
    """-> result dict (verdict + details). Never raises into the caller except via the caller's own guard."""
    tags = pm.prod_tags(rd, repo)
    if not tags:
        return qc.verdict("UNVERIFIED", GATE, repo, "-", "no prod-<ts>-%s tag in the clone: nothing to roll back to" % repo)
    if tag:
        pick = next((t for t in tags if t[1] == tag), None)
        if not pick:
            return qc.verdict("UNVERIFIED", GATE, repo, tag[:40], "tag %s not found among the repo's prod tags" % tag[:60])
    else:
        pick = tags[-2] if len(tags) >= 2 else tags[-1]
    ts, tag, sha = pick
    scratch = tempfile.mkdtemp(prefix=DRILL_PREFIX)
    try:
        clone = os.path.join(scratch, "clone")
        rc, _o, err = qc.run(["git", "clone", "-q", "--no-checkout", "--shared", rd, clone], timeout=300, polite=False)
        if rc != 0:
            return qc.verdict("UNVERIFIED", GATE, repo, tag, "scratch clone failed: %s" % err.strip()[-120:])
        rc, _o, err = qc.run(["git", "-C", clone, "-c", "advice.detachedHead=false", "checkout", "-q", "--detach", tag], timeout=300, polite=False)
        if rc != 0:
            return qc.verdict("FAIL", GATE, repo, tag, "checkout of %s failed in the scratch clone: %s" % (tag, err.strip()[-120:]), {"tag": tag, "sha": sha})
        ok, idetail = integrity(rd, clone, tag)
        det = {"tag": tag, "sha": sha, "integrity": idetail, "restored_identical": ok, "smokes": [], "notes": []}
        if not ok:
            return qc.verdict("FAIL", GATE, repo, tag, "restore of %s is NOT byte-identical: %s" % (tag, idetail), det)
        res, notes = smoke(clone, repo, custom_smoke, scratch)
        det["smokes"], det["notes"] = res, notes
        bad = [r for r in res if r["status"] != "PASS"]
        if bad:
            return qc.verdict("FAIL", GATE, repo, tag, "restored %s identically but smoke FAILED: %s %s" % (tag, bad[0]["name"], bad[0]["detail"][:100]), det)
        if res and all(r.get("partial") for r in res):
            return qc.verdict("UNVERIFIED", GATE, repo, tag, "restored %s byte-identical and the partial smoke passed, but it does not cover the stack (%s)" % (tag, "; ".join(notes)[:160]), det)
        if not res:
            return qc.verdict("UNVERIFIED", GATE, repo, tag, "restored %s identically but no smoke could run (%s)" % (tag, "; ".join(notes) or "no smoke"), det)
        return qc.verdict("PASS", GATE, repo, tag, "restored %s byte-identical; %d smoke(s) passed (%s)" % (tag, len(res), ", ".join(r["name"] for r in res)), det)
    finally:
        safe_cleanup(scratch)


def main(argv):
    if not argv or argv[0] != "run":
        print(__doc__)
        return 0
    rest = argv[1:]
    repo = p5.opt(rest, "--repo")
    if pm.mode() == "off":      # OVN_QA_PROMOTE_MANIFEST=off switches the whole manifest family off, the drill included
        print(json.dumps({"mode": "off", "gate": GATE}))
        return 0
    try:
        if not ql.safe_name(repo):
            res = qc.verdict("UNVERIFIED", GATE, "?", "-", "usage: run --repo <name>")
        else:
            rd = qc.repo_dir(repo)
            res = drill(repo, rd, p5.opt(rest, "--tag") or None, p5.opt(rest, "--smoke-cmd")) if rd else qc.verdict("UNVERIFIED", GATE, repo, "-", "no clone for repo %s" % repo)
    except Exception as ex:  # noqa: BLE001
        res = qc.verdict("UNVERIFIED", GATE, repo or "?", "-", "drill crashed: %s: %s" % (type(ex).__name__, ex))
    if "--no-record" not in rest:
        qc.record(res)
    print(json.dumps(res, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
