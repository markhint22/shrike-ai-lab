#!/usr/bin/env python3
"""Dependency/import landing gate (2026-10-03, QA track 'landing' / diagnosis A4).

Incident: a fleet commit removed `aiohttp` from iptv_apps requirements.txt while app code still
imported it; the Chickadee prod deploy crash-looped on ModuleNotFoundError and nothing caught it
before the promote. Two independent checks:

  removed  --repo DIR --before SHA [--after SHA]
      For every package REMOVED from a requirements*.txt / pyproject.toml between the two commits
      (and not still declared anywhere else in the tree), fail if a non-test source file still
      imports its top-level module. Scoped to deleted requirement lines only, so a pre-existing
      mismatch can never block a cycle that did not touch dependencies.

  clean-import  --repo DIR
      Build a fresh venv from the project's requirements.txt ONLY (cached by sha256 of that file),
      then `python -c "import app.main"` inside it. FAILs only on ModuleNotFoundError for a
      third-party module (the exact crash class); every other outcome - no app/main.py, pip or
      venv trouble, timeout, an app that needs env/DB to import - is UNVERIFIED (exit 0).

  gate     --repo DIR --before SHA [--after SHA]
      `removed` (when the diff touches dependency files) then `clean-import` (when it does).
      With no --before it runs clean-import only (hourly/hygiene use: cheap, cache-hit by hash).

Exit: 0 = pass or UNVERIFIED (infra failure never blocks), 1 = real failure. Output lines start
with DEP-GATE. OVN_DEP_GATE: default 'shadow' (report, always exit 0; set 'enforce' once the first
real venv builds are verified), 'off' disables. `removed` is advisory (a transitive provider can hide or
fake a loss); clean-import is the authority. A pip failure is negatively cached for OVN_DEP_NEG_TTL
seconds (default 6h) so an offline box / bad pin does not stall every pass.
Env: OVN_DEP_CACHE (venv cache dir, default ~/.cache/ovn-dep-venvs), OVN_DEP_PYTHON (interpreter
for the venv), OVN_DEP_PIP_TIMEOUT (default 600), OVN_DEP_IMPORT_TIMEOUT (default 60).
"""
import argparse
import ast
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

# distribution name (normalised) -> import name, for the known mismatches
IMPORT_NAME = {
    "pyjwt": "jwt", "python-jose": "jose", "pillow": "PIL", "pyyaml": "yaml",
    "beautifulsoup4": "bs4", "psycopg2-binary": "psycopg2", "scikit-learn": "sklearn", "python-multipart": "multipart",
    "opencv-python": "cv2", "opencv-python-headless": "cv2", "python-dateutil": "dateutil",
    "python-dotenv": "dotenv", "attrs": "attr", "msgpack-python": "msgpack",
    "pyopenssl": "OpenSSL", "pycryptodome": "Crypto", "python-magic": "magic",
    "email-validator": "email_validator", "pydantic-settings": "pydantic_settings",
    "google-api-python-client": "googleapiclient", "google-auth-oauthlib": "google_auth_oauthlib",
    "google-auth-httplib2": "google_auth_httplib2",
}
# packages that never provide a directly imported module (tooling / extras / servers)
NO_IMPORT = {"google-auth", "google-cloud-storage", "protobuf",   # google.* namespace: clean-import decides
             "pip", "wheel", "gunicorn", "uvloop", "httptools", "watchfiles", "websockets", "pytest",
             "pytest-asyncio", "pytest-cov", "pytest-xdist", "ruff", "mypy", "flake8", "black", "isort",
             "pylint", "coverage", "pip-tools"}
TEST_PATH_RE = re.compile(r"(^|/)(tests?|testing|e2e|__tests__)(/|$)|(^|/)test_[^/]*\.py$|_test\.py$|(^|/)conftest\.py$")
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "env", "__pycache__", "alembic.backup", "site-packages",
             "build", "dist", ".tox"}


def norm(name):
    return re.sub(r"[-_.]+", "-", name.strip().lower())


def import_name(dist):
    n = norm(dist)
    if n in IMPORT_NAME:
        return IMPORT_NAME[n]
    return n.replace("-", "_")


def req_names_from_text(text):
    """Distribution names declared in a requirements.txt body."""
    out = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or line.startswith("-") or "://" in line or line.startswith((".", "/")):
            continue
        m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if m:
            out.add(norm(m.group(1)))
    return out


def pyproject_names_from_text(text):
    try:
        import tomllib
        d = tomllib.loads(text)
    except Exception:
        return set()
    out = set()
    proj = d.get("project", {})
    lists = [proj.get("dependencies", [])] + list(proj.get("optional-dependencies", {}).values())
    for lst in lists:
        for item in lst:
            m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", item)
            if m:
                out.add(norm(m.group(1)))
    poetry = d.get("tool", {}).get("poetry", {})
    for k in poetry.get("dependencies", {}):
        if k.lower() != "python":
            out.add(norm(k))
    return out


def names_from_file(name, text):
    base = os.path.basename(name)
    if base == "pyproject.toml":
        return pyproject_names_from_text(text)
    return req_names_from_text(text)


def is_dep_file(path):
    b = os.path.basename(path)
    return (b.startswith("requirements") and b.endswith(".txt")) or b == "pyproject.toml"


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def changed_dep_files(repo, before, after):
    rc, out = git(repo, "diff", "--no-renames", "--name-only", before, after)
    if rc != 0:
        return None
    return [f for f in out.splitlines() if is_dep_file(f)]


def declared_after(repo, after):
    """All distribution names still declared by ANY dependency file at `after`."""
    rc, out = git(repo, "ls-tree", "-r", "--name-only", after)
    names = set()
    for f in out.splitlines():
        if is_dep_file(f) and not TEST_PATH_RE.search(f):
            rc, txt = git(repo, "show", f"{after}:{f}")
            if rc == 0:
                names |= names_from_file(f, txt)
    return names


def imports_in(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return set()
    mods = set()
    try:
        for node in ast.walk(ast.parse(text)):
            if isinstance(node, ast.Import):
                mods |= {a.name.split(".")[0] for a in node.names}
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                mods.add(node.module.split(".")[0])
    except SyntaxError:
        for m in re.finditer(r"^\s*(?:import|from)\s+([A-Za-z_][A-Za-z0-9_]*)", text, re.M):
            mods.add(m.group(1))
    return mods


def source_importers(repo, modules):
    """{module: [relative non-test .py files importing it]}"""
    hits = {m: [] for m in modules}
    for dp, dns, fns in os.walk(repo):
        dns[:] = [d for d in dns if d not in SKIP_DIRS and not d.startswith(".venv")]
        for fn in fns:
            if not fn.endswith(".py"):
                continue
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, repo)
            if TEST_PATH_RE.search(rel):
                continue
            got = imports_in(full)
            for m in modules:
                if m in got:
                    hits[m].append(rel)
    return {m: v for m, v in hits.items() if v}


def check_removed(repo, before, after):
    """-> (status, lines) status in PASS|FAIL|UNVERIFIED"""
    files = changed_dep_files(repo, before, after)
    if files is None:
        return "UNVERIFIED", [f"cannot diff {before}..{after}"]
    removed = set()
    for f in files:
        rc, old = git(repo, "show", f"{before}:{f}")
        old_names = names_from_file(f, old) if rc == 0 else set()
        rc, new = git(repo, "show", f"{after}:{f}")
        new_names = names_from_file(f, new) if rc == 0 else set()   # file deleted -> all removed
        removed |= old_names - new_names
    if not removed:
        return "PASS", ["no dependency removed"]
    still = declared_after(repo, after)
    removed -= still
    # a sibling distribution providing the same import module (psycopg2-binary -> psycopg2) is a swap, not a loss
    swapped = {import_name(n) for n in still}
    removed = {r for r in removed if import_name(r) not in swapped}
    removed = {r for r in removed if r not in NO_IMPORT}
    if not removed:
        return "PASS", ["removed dependencies are still declared elsewhere / not importable"]
    # the working tree is the post-cycle state the caller is gating (HEAD == after)
    mods = {import_name(r): r for r in removed}
    hits = source_importers(repo, set(mods))
    if not hits:
        return "PASS", [f"removed {sorted(removed)}: no remaining non-test import"]
    lines = [f"removed dependency '{mods[m]}' is still imported (module '{m}') by: {', '.join(sorted(v)[:5])}"
             for m, v in sorted(hits.items())]
    return "FAIL", lines


def find_project(repo):
    """(project_dir, requirements_file) for the first python backend with app/main.py."""
    cands = []
    for dp, dns, fns in os.walk(repo):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        if os.path.basename(dp) == "app" and "main.py" in fns:
            proj = os.path.dirname(dp)
            for d in (proj, os.path.dirname(proj)):
                rf = os.path.join(d, "requirements.txt")
                if os.path.isfile(rf) and os.path.commonpath([d, repo]) == os.path.abspath(repo):
                    cands.append((proj, rf))
                    break
    cands.sort(key=lambda c: len(c[0]))
    return cands[0] if cands else (None, None)


def _run(cmd, cwd, timeout, env=None):
    nice = shutil.which("nice")
    if nice:
        cmd = [nice, "-n", "15", *cmd]
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def check_clean_import(repo):
    proj, rf = find_project(os.path.abspath(repo))
    if not proj:
        return "UNVERIFIED", ["no app/main.py + requirements.txt backend found"]
    h = hashlib.sha256(open(rf, "rb").read()).hexdigest()[:20]
    cache = os.environ.get("OVN_DEP_CACHE") or os.path.join(os.path.expanduser("~"), ".cache", "ovn-dep-venvs")
    venv = os.path.join(cache, h)
    py = os.path.join(venv, "bin", "python")
    ptmo = int(os.environ.get("OVN_DEP_PIP_TIMEOUT", "600"))
    itmo = int(os.environ.get("OVN_DEP_IMPORT_TIMEOUT", "60"))
    neg = venv + ".fail"
    ttl = int(os.environ.get("OVN_DEP_NEG_TTL", str(6 * 3600)))
    try:
        if not os.path.isfile(os.path.join(venv, ".ok")):
            try:
                if time.time() - os.path.getmtime(neg) < ttl:
                    return "UNVERIFIED", ["pip install failed recently (negative cache); not retrying yet"]
            except OSError:
                pass
            os.makedirs(cache, exist_ok=True)
            with open(venv + ".lock", "w") as lk:
                try:
                    import fcntl
                    fcntl.flock(lk, fcntl.LOCK_EX)   # one builder per hash; others wait, then see .ok
                except Exception:  # noqa: BLE001
                    pass
                if not os.path.isfile(os.path.join(venv, ".ok")):
                    shutil.rmtree(venv, ignore_errors=True)
                    base = os.environ.get("OVN_DEP_PYTHON") or ("python3.12" if shutil.which("python3.12") else "python3")  # the repos' real venvs are 3.12; box default python3 is 3.14 (wheels missing)
                    r = _run([base, "-m", "venv", venv], proj, 120)
                    if r.returncode != 0:
                        return "UNVERIFIED", ["venv creation failed: " + r.stderr.strip()[-200:]]
                    r = _run([py, "-m", "pip", "install", "-q", "--disable-pip-version-check", "-r", rf],
                             os.path.dirname(rf), ptmo)
                    if r.returncode != 0:
                        shutil.rmtree(venv, ignore_errors=True)
                        open(neg, "w").close()
                        return "UNVERIFIED", ["pip install from requirements.txt failed (infra or unresolvable pin): "
                                              + (r.stderr.strip().splitlines() or [""])[-1][:200]]
                    open(os.path.join(venv, ".ok"), "w").close()
                    _prune(cache, keep=6, current=h)
        if not os.path.isfile(os.path.join(venv, ".ok")) or not os.path.isfile(py):
            return "UNVERIFIED", ["clean venv incomplete (missing .ok or python)"]
        try:
            os.utime(venv)   # mark in use so the mtime-ranked _prune keeps it
        except OSError:
            pass
        env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "VIRTUAL_ENV")}
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        r = _run([py, "-c", "import app.main"], proj, itmo, env=env)
    except subprocess.TimeoutExpired:
        return "UNVERIFIED", ["timed out"]
    except Exception as e:  # noqa: BLE001 - infra failure must never block
        return "UNVERIFIED", [f"error: {type(e).__name__}: {e}"]
    if r.returncode == 0:
        return "PASS", [f"import app.main OK in clean venv built from {os.path.relpath(rf, repo)} ({h})"]
    m = re.search(r"ModuleNotFoundError: No module named '([^']+)'", r.stderr)
    if m:
        top = m.group(1).split(".")[0]
        local = os.path.isdir(os.path.join(proj, top)) or os.path.isfile(os.path.join(proj, top + ".py"))
        if not local:
            return "FAIL", [f"import app.main fails in a clean venv built from {os.path.relpath(rf, repo)}: "
                            f"module '{top}' is imported but not in requirements.txt (prod would crash-loop)"]
    return "UNVERIFIED", ["import app.main failed for a non-dependency reason: "
                          + (r.stderr.strip().splitlines() or ["?"])[-1][:200]]


def _prune(cache, keep, current):
    try:
        ents = [os.path.join(cache, d) for d in os.listdir(cache)]
        ents = [e for e in ents if os.path.isdir(e) and os.path.basename(e) != current]
        ents.sort(key=os.path.getmtime, reverse=True)
        for e in ents[keep - 1:]:
            if not os.path.isdir(e) or e.endswith((".lock", ".fail")):
                continue
            if time.time() - os.path.getmtime(e) < 86400:
                continue   # used within a day: may be in use by a concurrent cycle/hygiene run
            shutil.rmtree(e, ignore_errors=True)
    except OSError:
        pass


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["removed", "clean-import", "gate"])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--before")
    ap.add_argument("--after", default="HEAD")
    a = ap.parse_args(argv)
    mode = os.environ.get("OVN_DEP_GATE", "shadow")
    if mode == "off":
        return 0
    repo = os.path.abspath(a.repo)
    results = []
    touched = True
    if a.cmd in ("removed", "gate") and a.before:
        results.append(("removed",) + check_removed(repo, a.before, a.after))
        files = changed_dep_files(repo, a.before, a.after)
        touched = files is None or bool(files)
    elif a.cmd == "removed":
        results.append(("removed", "UNVERIFIED", ["--before required"]))
    if a.cmd == "clean-import" or (a.cmd == "gate" and touched):
        results.append(("clean-import",) + check_clean_import(repo))
    failed = False
    for name, status, lines in results:
        for ln in lines:
            print(f"DEP-GATE {name} {status}: {ln}")
        failed |= status == "FAIL"
    if failed and mode == "shadow":
        print("DEP-GATE (shadow) would FAIL - not blocking")
        return 0
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
