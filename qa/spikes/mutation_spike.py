#!/usr/bin/env python3
"""mutation_spike.py - SPIKE W2a: is diff-scoped mutation testing (mutmut 3.x) feasible per feature on the GPU box?

    python3 qa/spikes/mutation_spike.py check --repo <name> --base <ref> --head <ref>
            [--cap 600] [--max-children 4] [--service <dir>] [--python <path>] [--keep <dir>] [--survivors 10]
            [--report <file>] [--no-record] [--enforce-exit]
    python3 qa/spikes/mutation_spike.py cleanup --repo <name> --keep <dir>

What it does (advisory only - this gate NEVER returns FAIL):
  1. Finds the non-test .py files changed between base..head and, via `git diff -U0` + `ast`, the CHANGED FUNCTIONS in them.
  2. Makes a detached worktree of <head>, symlinks the clone's service venv into it, writes a [mutmut] config
     (source_paths=<pkg>, only_mutate=<changed files>, also_copy=every top-level entry of the service dir).
  3. Runs `mutmut run <globs of the changed functions' mutants>` under a hard wall cap (default 600 s), niced, in its own
     process group (the whole group is killed on timeout so no orphan workers survive).
  4. Reads mutants/**/*.meta, counts killed / survived / no-tests / timeout, and shows the worst survivors (diff + heuristic
     noise label).
Verdicts: PASS (every mutant of the changed functions killed), FLAG (survivors or untested functions), NA (nothing to mutate),
UNVERIFIED (timeout, missing tool/venv, red baseline, mutmut error). Exit 0 always (spec rule 2) except enforce+FAIL (never FAIL).

mutmut 3.8.0 note: importing mutmut loads its config immediately, so `mutmut --version` in a directory with no source dir
(e.g. $HOME) prints a FileNotFoundError traceback. That is NOT a broken install; run it inside a project (see MUTATION_SPIKE.md).
"""
import ast
import fnmatch
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import qa_common as qc  # noqa: E402

GATE = "mutation_spike"
STATUS = {1: "killed", 3: "killed", 0: "survived", 5: "no_tests", 33: "no_tests", 34: "skipped", 35: "suspicious",
          36: "timeout", 24: "timeout", -24: "timeout", 152: "timeout", 37: "caught_by_typecheck", 2: "interrupted", None: "not_checked"}
SKIP_ENTRIES = {".venv", "venv", "env", "mutants", "__pycache__", ".git", "htmlcov", "node_modules", ".pytest_cache", ".mypy_cache",
                ".ruff_cache", ".coverage", "mutmut-run.log"}
PHASES = [("Generating mutants", "generate"), ("Running stats", "stats"), ("Running clean tests", "clean"),
          ("Running mutation testing", "mutate")]


# ---------------------------------------------------------------- arg parsing
def parse(argv):
    o = {"cap": 600, "max_children": 4, "service": "", "python": "", "keep": "", "survivors": 10, "report": "", "repo": "", "unwrap_decorators": 0, "select_tests": 0, "pytest_arg": [], "paths": "",
         "base": "", "head": ""}
    flags = {"no-record", "unwrap-decorators", "select-tests"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in flags:
            if a[2:] == "unwrap-decorators":
                o["unwrap_decorators"] = 1
            if a[2:] == "select-tests":
                o["select_tests"] = 1
            i += 1
        elif a == "--pytest-arg" and i + 1 < len(argv):
            o["pytest_arg"].append(argv[i + 1])
            i += 2
        elif a.startswith("--") and a[2:].replace("-", "_") in o and i + 1 < len(argv):
            k = a[2:].replace("-", "_")
            o[k] = type(o[k])(argv[i + 1]) if not isinstance(o[k], str) else argv[i + 1]
            i += 2
        else:
            i += 1
    return o


# ---------------------------------------------------------------- git / ast helpers
def is_test_path(p):
    b = os.path.basename(p)
    parts = p.split("/")
    return (b.startswith("test_") or b.endswith("_test.py") or b == "conftest.py" or "tests" in parts[:-1] or "test" in parts[:-1]
            or "alembic" in parts or "migrations" in parts)


def hunks(rd, base, head, path):
    """New-side line ranges touched by the diff of `path` ((start, end) inclusive; pure deletions give (a, a+1))."""
    rc, out, _ = qc.git(rd, "diff", "-U0", "%s..%s" % (base, head), "--", path, timeout=60)
    res = []
    if rc != 0:
        return res
    for m in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", out, re.M):
        a = int(m.group(1))
        n = int(m.group(2)) if m.group(2) is not None else 1
        res.append((a, a + n - 1) if n > 0 else (a, a + 1))
    return res


def functions_in(src):
    """Top-level functions and methods of top-level classes: [(qualname, cls|None, name, first_line, last_line)]."""
    tree = ast.parse(src)
    res = []

    def span(n):
        first = min([n.lineno] + [d.lineno for d in n.decorator_list])
        return first, n.end_lineno

    def skipped_by_mutmut(n):
        """mutmut 3.8 never mutates a decorated function (decorators run at definition time), except a single
        @staticmethod / @classmethod. FastAPI route handlers (@router.get/post/...) are therefore invisible to it."""
        d = n.decorator_list
        if not d:
            return False
        return not (len(d) == 1 and isinstance(d[0], ast.Name) and d[0].id in ("staticmethod", "classmethod"))

    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            s, e = span(n)
            res.append((n.name, None, n.name, s, e, skipped_by_mutmut(n), isinstance(n, ast.AsyncFunctionDef)))
        elif isinstance(n, ast.ClassDef):
            for m in n.body:
                if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    s, e = span(m)
                    res.append(("%s.%s" % (n.name, m.name), n.name, m.name, s, e, skipped_by_mutmut(m), isinstance(m, ast.AsyncFunctionDef)))
    return res


def unwrap_decorators(path, names):
    """EXPERIMENTAL (--unwrap-decorators): in the throwaway worktree copy, turn `@dec\ndef f(): ...` of the named module-level
    functions into `def f(): ...\nf = dec(f)` so mutmut can mutate them while the decorator (e.g. FastAPI route registration)
    still runs, after the def. Returns the number of functions rewritten."""
    src = open(path, encoding="utf-8").read()
    tree = ast.parse(src)
    lines = src.split("\n")
    edits = []
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in names and n.decorator_list:
            decs = [ast.get_source_segment(src, d) for d in n.decorator_list]
            if any(x is None for x in decs):
                continue
            first = min(d.lineno for d in n.decorator_list)
            expr = n.name
            for d in reversed(decs):
                expr = "%s(%s)" % (d, expr)
            edits.append((first, n.lineno, n.end_lineno, "%s = %s" % (n.name, expr.replace("\n", " "))))
    for first, deflineno, end, stmt in sorted(edits, reverse=True):
        lines.insert(end, stmt)                    # after the function body (lines are 1-based: index `end` is the next line)
        del lines[first - 1:deflineno - 1]         # drop the decorator lines
    if edits:
        open(path, "w", encoding="utf-8").write("\n".join(lines))
    return len(edits)


def changed_functions(rd, base, head, wt, relpath):
    """(functions changed, module-level-only?) for one file."""
    full = os.path.join(wt, relpath)
    try:
        src = open(full, encoding="utf-8").read()
        funcs = functions_in(src)
    except (OSError, SyntaxError, UnicodeDecodeError):
        return [], False
    rc, _, _ = qc.git(rd, "cat-file", "-e", "%s:%s" % (base, relpath))
    new_file = rc != 0
    hs = [(1, 10 ** 9)] if new_file else hunks(rd, base, head, relpath)
    hit = [f for f in funcs if any(not (b < f[3] or a > f[4]) for a, b in hs)]
    return hit, bool(hs) and not hit


def mangled_globs(module, fn):
    q, cls, name = fn[0], fn[1], fn[2]
    if cls:
        return "%s.xǁ%sǁ%s__mutmut_*" % (module, cls, name)
    return "%s.x_%s__mutmut_*" % (module, name)


# ---------------------------------------------------------------- environment discovery
def find_service(rd, wt, relpaths, forced=""):
    """Service root (relative dir) for a changed file: nearest ancestor that has tests/ or pytest config, preferring one with a
    .venv in the clone. Returns None if there is none."""
    def ok(d):
        p = os.path.join(wt, d)
        return os.path.isdir(os.path.join(p, "tests")) or any(os.path.exists(os.path.join(p, f)) for f in ("pytest.ini", "setup.cfg", "pyproject.toml"))
    res = {}
    for rp in relpaths:
        if forced:
            res[rp] = forced
            continue
        d = os.path.dirname(rp)
        found = None
        while True:
            if ok(d) and d != "":
                found = d
                if os.path.isdir(os.path.join(rd, d, ".venv")) or os.path.isdir(os.path.join(rd, d, "venv")):
                    break
            if d == "":
                break
            d = os.path.dirname(d)
        res[rp] = found
    return res


def venv_python(rd, service, forced=""):
    if forced:
        return forced if os.path.exists(forced) else None
    cands = []
    for base in (os.path.join(rd, service), rd):
        for v in (".venv", "venv"):
            cands.append(os.path.join(base, v, "bin", "python"))
    for c in cands:
        if os.path.exists(c):
            return c
    return None


def qa_site_packages():
    base = os.environ.get("QA_VENV") or os.path.expanduser("~/qa-venv")
    import glob
    g = sorted(glob.glob(os.path.join(base, "lib", "python3*", "site-packages")))
    return (base, g[0]) if g else (base, None)


def py_minor(python):
    rc, out, _ = qc.run([python, "-c", "import sys;print('%d.%d' % sys.version_info[:2])"], timeout=30, polite=False)
    return out.strip() if rc == 0 else None


def can_import_mutmut(python):
    rc, _, _ = qc.run([python, "-c", "import mutmut"], timeout=60, polite=False)
    return rc == 0


def mutmut_cmd(python, sp, args):
    """argv that runs mutmut's CLI under `python`; mutmut comes from the python itself or is appended (lowest priority) from the
    QA venv site-packages so the repo's own pytest/deps always win."""
    if sp is None:
        return [python, "-m", "mutmut"] + args
    code = "import sys; sys.path.append(%r); sys.argv[0]='mutmut'; from mutmut.__main__ import cli; sys.exit(cli())" % sp
    return [python, "-c", code] + args


def pytest_cmd(python, sp, args):
    """pytest under `python`; the mutated modules import mutmut's trampoline, so a borrowed mutmut must be importable too."""
    if sp is None:
        return [python, "-m", "pytest"] + args
    code = "import sys; sys.path.append(%r); import pytest; sys.exit(pytest.main(sys.argv[1:]))" % sp
    return [python, "-c", code] + args


# ---------------------------------------------------------------- process control
def run_group(cmd, cwd, timeout, env=None, log_path=None, markers=None):
    """Run cmd niced in its own process group; kill the whole group on timeout. Returns (rc, tail, timed_out, phase_times)."""
    e = dict(os.environ)
    e.update(env or {})
    e["PYTHONDONTWRITEBYTECODE"] = "1"
    full = qc.cpu_prefix() + list(cmd)
    t0 = time.time()
    c0 = os.times()
    phase = {}
    buf = {"data": b""}
    try:
        p = subprocess.Popen(full, cwd=cwd, env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                             start_new_session=True)
    except FileNotFoundError as ex:
        return 127, str(ex), False, {}
    logf = open(log_path, "wb") if log_path else None

    def reader():
        tail = b""
        while True:
            chunk = p.stdout.read1(65536) if hasattr(p.stdout, "read1") else p.stdout.read(65536)
            if not chunk:
                break
            if logf:
                logf.write(chunk)
            tail = (tail + chunk)[-8192:]
            for mk, name in (markers or []):
                if name not in phase and mk.encode() in tail:
                    phase[name] = round(time.time() - t0, 1)
            buf["data"] = tail

    th = threading.Thread(target=reader, daemon=True)
    th.start()
    timed_out = False
    try:
        p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(p.pid, sig)
            except ProcessLookupError:
                break
            try:
                p.wait(timeout=8)
                break
            except subprocess.TimeoutExpired:
                continue
        try:
            os.killpg(p.pid, signal.SIGKILL)  # belt and braces for orphaned workers
        except (ProcessLookupError, PermissionError):
            pass
    th.join(timeout=5)
    if logf:
        logf.close()
    phase["total"] = round(time.time() - t0, 1)
    c1 = os.times()
    # CPU seconds consumed by the reaped process tree: immune to box contention, unlike wall time
    phase["_cpu_s"] = round((c1.children_user + c1.children_system) - (c0.children_user + c0.children_system), 1)
    return (124 if timed_out else p.returncode), buf["data"].decode("utf-8", "replace"), timed_out, phase


# ---------------------------------------------------------------- mutmut result reading
def read_results(service_dir, globs):
    out = []
    mroot = os.path.join(service_dir, "mutants")
    for dp, _, fns in os.walk(mroot):
        for fn in fns:
            if not fn.endswith(".meta"):
                continue
            try:
                data = json.load(open(os.path.join(dp, fn)))
            except (OSError, ValueError):
                continue
            for k, v in (data.get("exit_code_by_key") or {}).items():
                if any(fnmatch.fnmatchcase(k, g) for g in globs):
                    out.append((k, STATUS.get(v, "suspicious" if v is not None else "not_checked"), v))
    return sorted(out)


LOG_RX = re.compile(r"\b(log|logger|logging|_log|print|warnings\.warn|warn)\b[\w.]*\s*\(")
MSG_RX = re.compile(r"\b(detail|message|msg|reason|description|help_text|error)\s*=")


def classify(diff):
    """Heuristic label for a survivor's diff. Advisory only - the spike notes record what a human decided after reading each."""
    minus = [l[1:] for l in diff.splitlines() if l.startswith("-") and not l.startswith("---")]
    plus = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
    ch = minus + plus
    if not ch:
        return "unknown"
    if "".join("".join(minus).split()) == "".join("".join(plus).split()):
        return "equivalent:whitespace-only"
    if all(LOG_RX.search(c) for c in ch):
        return "noise:logging/print"
    if all(MSG_RX.search(c) for c in ch):
        return "noise:message text (detail=/message=)"
    if re.search(r"\b(timeout|retries|max_\w+|limit|sleep)\b", "\n".join(ch), re.I):
        return "candidate:tuning-constant (often equivalent in tests)"
    return "candidate"


SECRET_RX = re.compile(r"""(?:(?:sk|pk|rk|ghp|gho|ghu|ghs|ghr|xox[abp])[-_][A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}|['"][A-Za-z0-9/+=_-]{32,}['"])""")


def redact(text):
    """Survivor diffs are source lines; never echo anything that looks like a credential literal (spec rule 5)."""
    return SECRET_RX.sub("[REDACTED]", text)


def show_diff(python, sp, service_dir, name, timeout=60):
    rc, out, _ = qc.run(mutmut_cmd(python, sp, ["show", name]), cwd=service_dir, timeout=timeout, polite=False,
                        env={"PYTHONPATH": ""})
    return out if rc == 0 else ""


def select_tests(sdir, modules, names, limit=25):
    """Diff-scoped test selection (--select-tests): test files under <service>/tests that mention a changed module's dotted path
    or a changed function name. Returns relative paths ([] -> caller falls back to the full suite). This trades fidelity for time:
    tests that reach the function only indirectly are not run, so survivors can be over-reported."""
    hits = []
    tdir = os.path.join(sdir, "tests")
    pats = [re.compile(r"\b" + re.escape(m) + r"\b") for m in modules] + [re.compile(r"\b" + re.escape(n) + r"\b") for n in names if len(n) > 3]
    for dp, _, fns in os.walk(tdir):
        for fn in fns:
            if not fn.endswith(".py") or fn == "conftest.py":
                continue
            full = os.path.join(dp, fn)
            try:
                txt = open(full, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            if any(p.search(txt) for p in pats):
                hits.append(os.path.relpath(full, sdir))
    return sorted(hits) if 0 < len(hits) <= limit else []


def cfg_escape(s):
    return s.replace("%", "%%")


def write_config(service_dir, pkg, only, extra_args, skip=(), selection=()):
    entries = sorted(e for e in os.listdir(service_dir)
                     if e not in SKIP_ENTRIES and e not in skip and e not in ("setup.cfg", pkg) and not e.startswith(".venv")
                     and not os.path.islink(os.path.join(service_dir, e)))
    marker = "# --- qa mutation_spike (generated) ---"
    cfg = os.path.join(service_dir, "setup.cfg")
    existing = ""
    if os.path.exists(cfg):
        existing = open(cfg).read()
        if marker in existing:  # our own block from an earlier run in a kept worktree: keep its deselects, rewrite the rest
            old = existing[existing.index(marker):]
            m = re.search(r"^pytest_add_cli_args=(.*?)(?=^\S|\Z)", old, re.S | re.M)
            if m:
                extra_args = list(extra_args) + [x.strip() for x in m.group(1).splitlines() if x.strip() and x.strip() not in extra_args]
            existing = existing[:existing.index(marker)]
        elif "[mutmut]" in existing:
            return False
        if existing and not existing.endswith("\n"):
            existing += "\n"
    body = [marker, "[mutmut]", "source_paths=" + pkg,
            "only_mutate=" + "\n  ".join(only), "also_copy=" + "\n  ".join(entries),
            "use_setproctitle=false", "track_dependencies=false"]
    if extra_args:
        body.append("pytest_add_cli_args=" + "\n  ".join(extra_args))
    if selection:
        body.append("pytest_add_cli_args_test_selection=" + "\n  ".join(cfg_escape(x) for x in selection))
    with open(cfg, "w") as f:
        f.write(existing + "\n".join(body) + "\n")
    return True


def check(argv):
    t0 = time.time()
    o = parse(argv)
    repo, base, head = o["repo"], o["base"], o["head"]
    if not (repo and base and head):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", head or "?", "usage: check --repo R --base B --head H")
    rd = qc.repo_dir(repo)
    ref = head
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, ref, "no clone for repo %s" % repo)
    deadline = t0 + o["cap"]
    files = [f for f in qc.changed_files(rd, base, head) if f.endswith(".py") and not is_test_path(f)]
    if o["paths"]:  # restrict a wide range (feature = several commits) to named files, comma-separated, repo-relative
        keep = [x for x in o["paths"].split(",") if x]
        files = [f for f in files if any(f == k or f.startswith(k.rstrip("/") + "/") for k in keep)]
    if not files:
        return qc.verdict("NA", GATE, repo, ref, "no changed non-test python files")
    qbase, sp = qa_site_packages()

    if o["keep"]:
        wt_ctx = KeptWorktree(rd, head, o["keep"])
    else:
        wt_ctx = qc.worktree(rd, head)
    with wt_ctx as wt:
        if wt is None:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "could not create worktree for %s" % head)
        svc_of = find_service(rd, wt, files, o["service"])
        usable = [f for f in files if svc_of.get(f)]
        if not usable:
            return qc.verdict("NA", GATE, repo, ref, "changed python files are not inside a service with tests: %s" % ", ".join(files[:3]))
        # one service per run: the one with the most changed files (others are listed as skipped)
        counts = {}
        for f in usable:
            counts[svc_of[f]] = counts.get(svc_of[f], 0) + 1
        service = max(counts, key=lambda k: counts[k])
        in_svc = [f for f in usable if svc_of[f] == service]
        skipped_other = [f for f in usable if svc_of[f] != service]
        # package dir = first path component under the service dir; files directly in the service root cannot be mutated
        pkgs = {}
        for f in in_svc:
            rel = os.path.relpath(f, service)
            first = rel.split(os.sep)[0]
            if os.sep in rel:
                pkgs.setdefault(first, []).append(rel)
        if not pkgs:
            return qc.verdict("NA", GATE, repo, ref, "changed files sit directly in the service root, not in a package dir")
        pkg = max(pkgs, key=lambda k: len(pkgs[k]))
        rels = pkgs[pkg]
        funcs, globs, module_only, fn_names = [], [], [], []
        skipped_decorated, n_unwrapped = [], 0
        mod_files = []
        for rel in rels:
            hit, modonly = changed_functions(rd, base, head, wt, os.path.join(service, rel))
            module = rel[:-3].replace(os.sep, ".")
            if module.endswith(".__init__"):
                module = module[:-9]
            if hit:
                mod_files.append(rel)
            if modonly:
                module_only.append(rel)
            if o["unwrap_decorators"]:
                names = {f[2] for f in hit if f[5] and f[1] is None}
                if names:
                    try:
                        n_unwrapped += unwrap_decorators(os.path.join(wt, service, rel), names)
                    except (OSError, SyntaxError, UnicodeDecodeError):
                        pass
                    hit = [f[:5] + (False if f[2] in names else f[5], f[6]) for f in hit]
            for fn in hit:
                if fn[5]:
                    skipped_decorated.append("%s:%s%s" % (rel, fn[0], " (async)" if fn[6] else ""))
                    continue
                funcs.append((rel, fn))
                globs.append(mangled_globs(module, fn))
                fn_names.append("%s:%s" % (rel, fn[0]))
        if not globs and skipped_decorated:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "all %d changed function(s) are decorated (e.g. route handlers); mutmut 3.8 never "
                              "mutates decorated functions" % len(skipped_decorated),
                              {"skipped_decorated": skipped_decorated, "service": service, "hint": "extract the logic into an undecorated helper, "
                               "or try --unwrap-decorators (experimental)"})
        if not globs:
            return qc.verdict("NA", GATE, repo, ref, "no changed function bodies (module-level/constant-only change%s)" %
                              (": " + ", ".join(module_only[:2]) if module_only else ""), {"module_level_only": module_only})
        py = venv_python(rd, service, o["python"])
        qa_py = os.path.join(qbase, "bin", "python")
        sp_use = None
        det = {"loadavg_1m": round(os.getloadavg()[0], 1) if hasattr(os, "getloadavg") else None, "service": service, "package": pkg, "files": mod_files, "functions": fn_names, "other_service_files_skipped": skipped_other, "skipped_decorated": skipped_decorated, "unwrapped_decorators": n_unwrapped, "pytest_args": o["pytest_arg"],
               "module_level_only": module_only, "cap_s": o["cap"], "max_children": o["max_children"]}
        if py is None:
            if os.path.exists(qa_py):
                py = qa_py
                det["python"] = "qa-venv fallback (no service venv)"
            else:
                return qc.verdict("UNVERIFIED", GATE, repo, ref, "no service venv for %s/%s and no QA venv at %s" % (repo, service, qbase), det)
        elif not can_import_mutmut(py):
            if sp is None:
                return qc.verdict("UNVERIFIED", GATE, repo, ref, "mutmut not installed (no QA venv at %s)" % qbase, det)
            m1, m2 = py_minor(py), py_minor(qa_py) if os.path.exists(qa_py) else None
            if not m1 or m1 != m2:
                return qc.verdict("UNVERIFIED", GATE, repo, ref, "service python %s != QA venv python %s; mutmut cannot be borrowed" % (m1, m2), det)
            sp_use = sp
        det.setdefault("python", "service venv" + (" + borrowed mutmut" if sp_use else ""))
        sdir = os.path.join(wt, service)
        # venv symlink into the worktree (the venv is NOT copied; tests run with the clone's installed deps)
        for v in (".venv", "venv"):
            cand = os.path.join(rd, service, v)
            if os.path.isdir(cand):
                link = os.path.join(sdir, v)
                if not os.path.lexists(link):
                    os.symlink(cand, link)
                break
        # tests that locate files via Path(__file__).parents[N] see mutmut's extra "mutants/" level: the service dir plays the
        # role the repo root had. Symlink the repo-root FILES into the service dir (only if absent) so they still resolve.
        linked = []
        if service not in ("", "."):
            for e in sorted(os.listdir(wt)):
                src, dst = os.path.join(wt, e), os.path.join(sdir, e)
                if os.path.isfile(src) and not os.path.lexists(dst) and e not in ("setup.cfg", "pyproject.toml"):
                    os.symlink(src, dst)
                    linked.append(e)
        det["repo_root_files_linked_into_service"] = len(linked)
        if py.startswith(rd):  # run the worktree-local path so relative imports resolve to the worktree
            py = os.path.join(sdir, os.path.relpath(py, os.path.join(rd, service)))
        only = list(mod_files)
        sel = []
        if o["select_tests"]:
            mods = [(r[:-3].replace(os.sep, ".")[:-9] if r.endswith("__init__.py") else r[:-3].replace(os.sep, ".")) for r in mod_files]
            sel = select_tests(sdir, mods, sorted({f[1][2] for f in funcs}))
        det["tests_selected"] = sel if sel else "all"
        xd = [a for a in o["pytest_arg"] if a.startswith(("-n", "--numprocesses", "--dist"))]
        if xd:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "pytest-xdist args %s are refused: workers hide mutmut's per-function test "
                              "stats and every function would look untested (measured)" % xd, det)
        if not write_config(sdir, pkg, only, [cfg_escape(x) for x in o["pytest_arg"]], skip=set(linked), selection=sel):
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "service already has a [mutmut] config; not overriding", det)
        det["cfg_written"] = True

        def remaining():
            return deadline - time.time()

        attempts = 0
        deselected = [x.replace("%%", "%") for x in re.findall(r"^\s*(--(?:deselect|ignore)=\S.*)$", open(os.path.join(sdir, "setup.cfg")).read(), re.M)]
        user_args = [cfg_escape(x) for x in o["pytest_arg"]]
        res_rows, phases, timed_out, rc, tail = [], {}, False, 0, ""
        while True:
            attempts += 1
            if remaining() < 20:
                return qc.verdict("UNVERIFIED", GATE, repo, ref, "cap of %ss exhausted before mutmut could run" % o["cap"], det)
            logp = os.path.join(sdir, "mutmut-run.log")
            rc, tail, timed_out, phases = run_group(mutmut_cmd(py, sp_use, ["run", "--max-children", str(o["max_children"])] + globs),
                                                    sdir, remaining(), env={"PYTHONPATH": ""}, log_path=logp,
                                                    markers=[(m, n) for m, n in PHASES])
            baseline_red = re.search(r"failed to collect stats|Failed to run clean test", tail) is not None
            if baseline_red and not timed_out:
                # mutmut stops at the first red test of its clean run (-x). Tests that are red in the plain tree (preexisting) or
                # only in mutmut's relocated layout cannot be mutation-tested: deselect them (collection errors: --ignore the
                # module), at most 40 in 3 rounds, and say so in the verdict. Unattributable failures -> UNVERIFIED.
                clean_tail = re.sub(r"\r", "\n", tail)
                found = re.findall(r"^FAILED (\S+?)(?: - .*)?$", clean_tail, re.M)
                errs = re.findall(r"^ERROR (\S+?\.py)(?: - .*)?$", clean_tail, re.M)
                if attempts == 1 and os.path.isdir(os.path.join(sdir, "mutants")) and remaining() > 90:
                    # mutmut stops at the FIRST red test (-x). Enumerate ALL of them with one plain pytest pass in mutmut's own layout
                    # (mutants/ dir) instead of paying one full mutmut round per failing test.
                    rc2, out2, _ = qc.run(pytest_cmd(py, sp_use, ["-q", "--no-header", "-rfE", "-p", "no:cacheprovider"] + list(deselected) + list(sel)),
                                          cwd=os.path.join(sdir, "mutants"), timeout=max(60, min(remaining() - 60, 420)),
                                          env={"PYTHONPATH": "", "PYTHONDONTWRITEBYTECODE": "1"})
                    if rc2 != 124:
                        found = re.findall(r"^FAILED (\S+?)(?: - .*)?$", out2, re.M) or found
                        errs = re.findall(r"^ERROR (\S+?\.py)(?: - .*)?$", out2, re.M) or errs
                ids = ["--deselect=" + i for i in found] + ["--ignore=" + i for i in errs]
                ids = [i for i in dict.fromkeys(ids) if i not in deselected]
                if not ids or attempts > 3 or len(deselected) + len(ids) > 40:
                    det["deselected_preexisting_failures"] = len(deselected)
                    return qc.verdict("UNVERIFIED", GATE, repo, ref, "clean test run is red under mutmut (%d tests deselected so far; "
                                      "unparseable failure, repeated failure or too many); mutation results would be meaningless" % len(deselected), det)
                deselected += ids
                cfgp = os.path.join(sdir, "setup.cfg")
                txt = open(cfgp).read()
                txt = re.sub(r"\npytest_add_cli_args=.*?(?=\n\S|\Z)", "", txt, flags=re.S).rstrip("\n") + "\n"
                txt += "pytest_add_cli_args=" + "\n  ".join(user_args + [cfg_escape(i) for i in deselected]) + "\n"
                open(cfgp, "w").write(txt)
                continue
            break
        if not timed_out and "BadTestExecutionCommandsException" in tail:
            # pytest could not even start under mutmut (usage error / import error at HEAD). Ask pytest itself why.
            rc3, out3, err3 = qc.run(pytest_cmd(py, sp_use, ["-q", "--no-header", "--co", "-p", "no:cacheprovider"]), cwd=os.path.join(sdir, "mutants"),
                                  timeout=60, env={"PYTHONPATH": ""})
            why = [l for l in (out3 + "\n" + err3).splitlines() if l.startswith("E ") or "Error" in l][-3:]
            det["pytest_error"] = " | ".join(x.strip()[:160] for x in why)
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "pytest cannot start at HEAD under mutmut (the commit itself looks broken): %s" %
                              (det["pytest_error"] or "see mutmut-run.log"), det)
        det["cpu_s"] = phases.pop("_cpu_s", None)
        det["phases_s"] = phases
        order = [n for _, n in PHASES if n in phases] + ["total"]
        det["phase_durations_s"] = {order[i]: round(phases[order[i + 1]] - phases[order[i]], 1) for i in range(len(order) - 1)}
        det["deselected_tests"] = deselected[:10]
        det["deselected_count"] = len(deselected)
        det["mutmut_attempts"] = attempts
        det["mutmut_tail"] = re.sub(r"[\r\x1b][^\n]{0,80}", "", tail)[-300:] if (timed_out or rc not in (0,)) else ""
        res_rows = read_results(sdir, globs)
        counts = {}
        for _, st, _c in res_rows:
            counts[st] = counts.get(st, 0) + 1
        det["counts"] = counts
        det["mutants_total"] = len(res_rows)
        tested = sum(v for k, v in counts.items() if k not in ("not_checked", "no_tests"))
        killed = counts.get("killed", 0) + counts.get("caught_by_typecheck", 0)
        survived = counts.get("survived", 0)
        det["mutation_score_pct"] = round(100.0 * killed / tested, 1) if tested else None
        if not timed_out and "could not find any test case for any mutant" in tail:
            # mutmut aborts when NO test executes any mutated code: every changed function is untested
            det["untested_functions"] = fn_names
            det["survivors_total"] = 0
            det["wall_s"] = round(time.time() - t0, 1)
            return qc.verdict("FLAG", GATE, repo, ref, "no test executes any of the %d changed function(s) (%d mutants unreachable)%s" %
                              (len(funcs), len(res_rows), (" [%d red tests were deselected - they may be the only covering tests]" % len(deselected)) if deselected else ""), det)
        if timed_out:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "hit the %ss wall cap (partial: %d/%d mutants checked, %d survived)" %
                              (o["cap"], len(res_rows) - counts.get("not_checked", 0), len(res_rows), survived), det)
        if rc != 0 and not res_rows:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "mutmut failed (rc=%s) before producing results" % rc, det)
        if not res_rows:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "mutmut produced no mutants for the changed functions (globs matched nothing)", det)
        unchecked = counts.get("not_checked", 0)
        if unchecked:
            return qc.verdict("UNVERIFIED", GATE, repo, ref, "%d of %d mutants were not checked (rc=%s)" % (unchecked, len(res_rows), rc), det)
        surv = [k for k, st, _c in res_rows if st == "survived"]
        notest = sorted({k.split("__mutmut_")[0] for k, st, _c in res_rows if st == "no_tests"})
        shown = []
        for name in surv[: max(0, o["survivors"])]:
            d = show_diff(py, sp_use, sdir, name)
            body = "\n".join(l for l in d.splitlines()[1:] if not l.startswith(("---", "+++")))
            shown.append({"mutant": name, "label": classify(body), "diff": redact(body)[:400]})
        det["survivors_shown"] = shown
        det["survivors_total"] = len(surv)
        det["untested_functions"] = notest
        det["wall_s"] = round(time.time() - t0, 1)
        if o["report"]:
            try:
                with open(o["report"], "w") as f:
                    json.dump({"all": [{"mutant": k, "status": st} for k, st, _ in res_rows], "details": det}, f, indent=1)
            except OSError:
                pass
        sfx = (" [%d red tests deselected]" % len(deselected) if deselected else "") + \
              (" [test selection: %d files, survivors may be over-reported]" % len(sel) if sel else "")
        if surv or notest:
            return qc.verdict("FLAG", GATE, repo, ref, "%d survived, %d untested function(s) of %d mutants in %d changed function(s), score %s%%%s" %
                              (len(surv), len(notest), len(res_rows), len(funcs), det["mutation_score_pct"], sfx), det)
        return qc.verdict("PASS", GATE, repo, ref, "all %d mutants of %d changed function(s) killed%s" % (len(res_rows), len(funcs), sfx), det)


class KeptWorktree:
    """Persistent worktree at <keep>/wt reused across runs (warm mutmut cache). Caller removes it with `cleanup`."""

    def __init__(self, rd, head, keep):
        self.rd, self.head, self.keep = rd, head, keep

    def __enter__(self):
        os.makedirs(self.keep, exist_ok=True)
        wt = os.path.join(self.keep, "wt")
        if os.path.isdir(wt):
            rc, _, _ = qc.git(wt, "checkout", "-q", "-f", "--detach", self.head, timeout=120)
            return wt if rc == 0 else None
        rc, _, _ = qc.git(self.rd, "worktree", "add", "-q", "--detach", wt, self.head, timeout=120)
        return wt if rc == 0 else None

    def __exit__(self, *a):
        return False


def cleanup(argv):
    o = parse(argv)
    rd = qc.repo_dir(o["repo"])
    if rd and o["keep"]:
        qc.git(rd, "worktree", "remove", "--force", os.path.join(o["keep"], "wt"))
        qc.git(rd, "worktree", "prune")
        import shutil
        shutil.rmtree(o["keep"], ignore_errors=True)
    print(json.dumps({"cleaned": o["keep"]}))
    return 0


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] not in ("check", "cleanup"):
        print(__doc__)
        return 0
    if argv[0] == "cleanup":
        return cleanup(argv[1:])
    return qc.main_guard(GATE, check, argv[1:])


if __name__ == "__main__":
    sys.exit(main())
