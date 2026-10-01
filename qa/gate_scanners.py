#!/usr/bin/env python3
"""gate_scanners.py - GATE S5: baseline-aware deterministic scanners over the CHANGED files of a range.

Tools: ruff (lint+security subset), mypy, bandit, semgrep (small LOCAL ruleset qa/semgrep_rules.yml, no registry/network),
gitleaks (redacted: rule id + file:line only), pip-audit (changed requirements*.txt), npm audit (changed package(-lock).json).

usage:
  gate_scanners.py check    --repo R --base REF --head REF [--tools a,b] [--baseline auto|stored|base|none] [--timeout S]
                            [--no-record] [--enforce-exit]
  gate_scanners.py baseline --repo R --ref REF [--tools a,b] [--timeout S]

Only findings NOT present in the baseline count. Fingerprint = tool + rule + file + normalized text of the flagged line
(stable across line shifts); comparison is a multiset (a bad line copied twice is one new finding).
Baseline sources (--baseline): stored = state/qa_baselines/scanners/<repo>.json; base = scan the same changed files at --base
(rename-aware); auto = stored when it has a usable cell for that tool, else base. pip-audit / npm audit ALWAYS use base (the
advisory DB moves with time, a stored baseline would report every newly published advisory as "new").
A tool that is missing / times out / cannot reach the network is UNVERIFIED for that cell - never PASS.
Suppression comments (noqa / nosec / nosemgrep / gitleaks:allow, repo .gitleaks.toml / .gitleaksignore / .semgrepignore) are
IGNORED: a gate that honours them lets the author of a change silence the gate on that very change.
A changed source file that cannot be scanned (missing, too large, binary) is counted in details.skipped and turns a would-be PASS
into UNVERIFIED; policy-excluded paths (vendored dirs, generated JS) are counted too. The range is merge-base(base,head)..head.
Secrets are never printed: gitleaks output is reduced to rule id + file:line (the matched line is only hashed).
"""
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "scanners"
HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.join(HERE, "semgrep_rules.yml")
ALL_TOOLS = ("ruff", "mypy", "bandit", "semgrep", "gitleaks", "pip-audit", "npm-audit")
# tools whose NEW findings are reported in details but do not drive the verdict (set after noise measurement; env override)
ADVISORY = set(filter(None, os.environ.get("QA_SCANNERS_ADVISORY", "mypy").split(",")))
AUDIT_TOOLS = ("pip-audit", "npm-audit")
# unambiguously vendored / generated: excluded at any depth
EXCLUDE_DIRS = {"node_modules", ".venv", "venv", "site-packages", ".git", "__pycache__", "Pods", ".gradle", "DerivedData", ".next", "htmlcov"}
# plausible real package names (app/env, app/build, app/vendor ...): Python is ALWAYS scanned there, only JS/TS (minified bundles) is skipped
GENERATED_JS_DIRS = {"env", "dist", "build", "vendor", "coverage"}
TEST_RE = re.compile(r"(^|/)(tests?|__tests__|e2e|fixtures)/|(^|/)test_[^/]*\.py$|_test\.py$|(^|/)conftest\.py$|\.(test|spec)\.[jt]sx?$")
PY_EXT = (".py",)
JS_EXT = (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs")
MAX_BYTES = 1000000
RUFF_SELECT = "F,E9,PLE,B006,B015,B018,B023,B024,B025,B026,B032,S102,S301,S302,S307,S324,S501,S506,S602,S605,S608"
RUFF_IGNORE = "F401,F403,F405,F841,F811,F541,PLE0605,PLE1205,PLE1206"
BANDIT_SKIP = "B310,B101,B311,B404,B603,B607,B105,B106,B107,B110,B112,B108,B104"
SEMGREP_ENV = {"SEMGREP_SEND_METRICS": "off", "SEMGREP_ENABLE_VERSION_CHECK": "0", "SEMGREP_FORCE_COLOR": "0", "NO_COLOR": "1"}
GENERIC_GL = {"generic-api-key", "curl-auth-header", "curl-auth-user"}
BLOCKING_RUFF = {"F821", "F822", "F823", "E902", "syntax-error"}


# ---------------------------------------------------------------- tool discovery
def find_tool(name):
    """env QA_TOOL_<NAME> > ~/qa-venv/bin > ~/qa-tools/bin > PATH. None when missing."""
    ov = os.environ.get("QA_TOOL_" + name.upper().replace("-", "_"))
    if ov:
        return ov if os.path.exists(ov) else None
    for d in (os.path.expanduser("~/qa-venv/bin"), os.path.expanduser("~/qa-tools/bin")):
        p = os.path.join(d, name)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return shutil.which(name)


# ---------------------------------------------------------------- findings
def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip())


def mk(tool, rule, file, line, sev, msg, text=None):
    return {"tool": tool, "rule": rule, "file": file, "line": int(line or 0), "sev": sev, "msg": redact_msg(msg)[:200], "text": text}


class Lines:
    """Cached line text lookup under a root (for fingerprints)."""

    def __init__(self, root):
        self.root, self.c = root, {}

    def get(self, rel, n):
        if rel not in self.c:
            try:
                with open(os.path.join(self.root, rel), "r", errors="replace") as f:
                    self.c[rel] = f.read().splitlines()
            except OSError:
                self.c[rel] = []
        ls = self.c[rel]
        return ls[n - 1] if 0 < n <= len(ls) else ""


def fp_of(tool, rule, file, text):
    raw = "|".join((tool, rule, file, norm(text)))
    return hashlib.sha1(raw.encode("utf-8", "replace")).hexdigest()[:20]


def fingerprint(f, lines):
    text = f["text"] if f.get("text") is not None else lines.get(f["file"], f["line"])
    f["ntext"] = norm(text)
    return fp_of(f["tool"], f["rule"], f["file"], text)


def relto(fn, root):
    """Path of a tool-reported file relative to root (tools report absolute, symlink-resolved paths: /var vs /private/var)."""
    if os.path.isabs(fn):
        return os.path.relpath(os.path.realpath(fn), os.path.realpath(root))
    return fn[2:] if fn.startswith("./") else fn


def is_test(path):
    return bool(TEST_RE.search(path))


def excluded_reason(path):
    """Why a path is not scanned by policy (None = scan it)."""
    parts = path.split("/")
    if any(p in EXCLUDE_DIRS for p in parts[:-1]):
        return "vendored_dir"
    if path.endswith(JS_EXT) and any(p in GENERATED_JS_DIRS for p in parts[:-1]):
        return "generated_js_dir"
    return None


def unscannable_reason(root, f):
    """For a changed source file (py/js ext) that no tool can read: the reason, else None."""
    p = os.path.join(root, f)
    if os.path.islink(p):
        return "symlink"
    if not os.path.isfile(p):
        return "missing"
    try:
        if os.path.getsize(p) > MAX_BYTES:
            return "too_large"
        with open(p, "rb") as fh:
            if b"\0" in fh.read(8192):
                return "binary"
    except OSError:
        return "unreadable"
    return None


REDACT_RE = re.compile(r"[A-Za-z0-9_\-+/=]{24,}")
STR_RE = re.compile(r"(\"[^\"]*\"|'[^']*')")


def redact_msg(msg, strings=False):
    """Tool messages can embed literal source values (mypy: Literal['ghp_...']); token-like runs are always removed,
    quoted string literals too when strings=True (mypy)."""
    msg = msg or ""
    if strings:
        msg = STR_RE.sub("<str>", msg)
    return REDACT_RE.sub("<redacted>", msg)


def advisory(f):
    """Findings that are listed but never move the verdict: advisory tools, and gitleaks hits in tests/docs (fake tokens by design)."""
    if f["tool"] in ADVISORY:
        return True
    return f["tool"] == "gitleaks" and (is_test(f["file"]) or f["file"].lower().endswith((".md", ".rst", ".txt")) or f["file"].startswith(("docs/", "doc/")))


def blocking(f):
    t, r, s = f["tool"], f["rule"], (f["sev"] or "").upper()
    if t == "gitleaks":
        # generic heuristics (a Content-Type header matched curl-auth-header in replay) are FLAG at most; provider-specific rules block
        return r not in GENERIC_GL
    if t == "semgrep":
        return s == "ERROR"
    if t == "bandit":
        return s == "HIGH" and f.get("conf", "") != "LOW"
    if t == "ruff":
        return r in BLOCKING_RUFF
    if t == "mypy":
        return r == "syntax"
    if t == "npm-audit":
        return s in ("HIGH", "CRITICAL")
    return False


# ---------------------------------------------------------------- tool runners: (status, findings, note)
def chunks(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def usable_files(root, files, exts):
    out = []
    for f in files:
        p = os.path.join(root, f)
        if f.endswith(exts) and unscannable_reason(root, f) is None:
            out.append(f)
    return out


def run_ruff(root, files, timeout, ctx):
    exe = find_tool("ruff")
    if not exe:
        return "UNVERIFIED", [], "ruff not installed"
    fs = usable_files(root, files, PY_EXT)
    if not fs:
        return "NA", [], "no python files"
    res = []
    for ch in chunks(fs, 800):
        rc, out, err = qc.run([exe, "check", "--isolated", "--no-cache", "--ignore-noqa", "--output-format", "json", "--target-version", "py312",
                               "--select", RUFF_SELECT, "--ignore", RUFF_IGNORE] + ch, cwd=root, timeout=timeout)
        if rc in (124, 127):
            return "UNVERIFIED", [], "ruff %s" % ("timed out" if rc == 124 else "missing")
        try:
            data = json.loads(out or "[]")
        except ValueError:
            return "UNVERIFIED", [], "ruff gave unparsable output (rc=%s)" % rc
        for d in data:
            fn = relto(d.get("filename") or "", root)
            if fn.startswith(".."):
                continue
            code = d.get("code") or "syntax-error"
            if code.startswith("S") and is_test(fn):
                ctx["test_skipped"] = ctx.get("test_skipped", 0) + 1
                continue
            res.append(mk("ruff", code, fn, (d.get("location") or {}).get("row"), "ERROR" if code in BLOCKING_RUFF else "WARNING", d.get("message")))
    return "OK", res, ""


MYPY_RE = re.compile(r"^(.+?):(\d+)(?::\d+)?: error: (.*?)(?:\s+\[([\w\-]+)\])?$")
MYPY_SKIP = {"import-not-found", "import-untyped", "import", "no-redef", "name-defined"}


def run_mypy(root, files, timeout, ctx):
    """mypy per top-level directory (cwd = that dir, so `app.x` imports resolve and duplicate-module clashes between
    unrelated sub-projects cannot abort the run). A group that dies without producing any error line is reported in the note."""
    exe = find_tool("mypy")
    if not exe:
        return "UNVERIFIED", [], "mypy not installed"
    fs = usable_files(root, files, PY_EXT)
    if not fs:
        return "NA", [], "no python files"
    groups = {}
    for f in fs:
        g = f.split("/", 1)[0] if "/" in f else ""
        groups.setdefault(g, []).append(f[len(g) + 1:] if g else f)
    res, bad, deadline = [], [], time.time() + timeout
    for g, gf in sorted(groups.items()):
        left = int(deadline - time.time())
        if left < 5:
            return "UNVERIFIED", [], "mypy timed out (budget %ds)" % timeout
        cwd = os.path.join(root, g) if g else root
        rc, out, err = qc.run([exe, "--ignore-missing-imports", "--follow-imports=silent", "--no-error-summary", "--show-error-codes",
                               "--no-pretty", "--no-color-output", "--show-column-numbers", "--cache-dir=/dev/null",
                               "--namespace-packages", "--explicit-package-bases"] + gf, cwd=cwd, timeout=left)
        if rc == 124:
            return "UNVERIFIED", [], "mypy timed out"
        if rc == 127:
            return "UNVERIFIED", [], "mypy missing"
        want, parsed = set(gf), False
        for line in out.splitlines():
            m = MYPY_RE.match(line)
            if not m:
                continue
            parsed = True
            fn, ln, msg, code = m.group(1), m.group(2), m.group(3), m.group(4) or "mypy"
            if fn not in want or code in MYPY_SKIP:
                continue
            res.append(mk("mypy", code, (g + "/" + fn) if g else fn, ln, "ERROR" if code == "syntax" else "WARNING", redact_msg(msg, strings=True)))
        if rc not in (0, 1) and not parsed:
            bad.append(g or ".")
    if bad and len(bad) == len(groups):
        return "UNVERIFIED", [], "mypy fatal in every group (%s)" % ",".join(bad)[:120]
    return "OK", res, ("mypy fatal in group(s): %s" % ",".join(bad))[:160] if bad else ""


def run_bandit(root, files, timeout, ctx):
    exe = find_tool("bandit")
    if not exe:
        return "UNVERIFIED", [], "bandit not installed"
    fs = usable_files(root, files, PY_EXT)
    if not fs:
        return "NA", [], "no python files"
    res = []
    for ch in chunks(fs, 800):
        rc, out, err = qc.run([exe, "-q", "-f", "json", "--ignore-nosec", "-s", BANDIT_SKIP] + ch, cwd=root, timeout=timeout)
        if rc in (124, 127):
            return "UNVERIFIED", [], "bandit %s" % ("timed out" if rc == 124 else "missing")
        try:
            data = json.loads(out[out.index("{"):]) if "{" in out else {}
        except ValueError:
            return "UNVERIFIED", [], "bandit gave unparsable output (rc=%s)" % rc
        if "results" not in data:
            return "UNVERIFIED", [], "bandit produced no result block (rc=%s)" % rc
        for d in data["results"]:
            fn = relto(d.get("filename") or "", root)
            if is_test(fn):
                ctx["test_skipped"] = ctx.get("test_skipped", 0) + 1
                continue
            f = mk("bandit", d.get("test_id", "B?"), fn, d.get("line_number"), d.get("issue_severity"), d.get("issue_text"))
            f["conf"] = (d.get("issue_confidence") or "").upper()
            res.append(f)
    return "OK", res, ""


def run_semgrep(root, files, timeout, ctx):
    exe = find_tool("semgrep")
    if not exe:
        return "UNVERIFIED", [], "semgrep not installed"
    if not os.path.isfile(RULES):
        return "UNVERIFIED", [], "semgrep ruleset missing"
    fs = usable_files(root, files, PY_EXT + JS_EXT)
    if not fs:
        return "NA", [], "no scannable files"
    res = []
    for ch in chunks(fs, 1500):
        rc, out, err = qc.run([exe, "scan", "--config", RULES, "--metrics=off", "--disable-version-check", "--quiet", "--json", "--disable-nosem",
                               "--timeout", "20", "--no-git-ignore", "--max-target-bytes", str(MAX_BYTES)] + ch,
                              cwd=root, timeout=timeout, env=SEMGREP_ENV)
        if rc in (124, 127):
            return "UNVERIFIED", [], "semgrep %s" % ("timed out" if rc == 124 else "missing")
        try:
            data = json.loads(out)
        except ValueError:
            return "UNVERIFIED", [], "semgrep gave unparsable output (rc=%s): %s" % (rc, norm(err)[:120])
        for e in data.get("errors", []):
            if e.get("level") == "error" and "Rule" in str(e.get("type", "")):
                return "UNVERIFIED", [], "semgrep ruleset error: %s" % norm(str(e.get("message") or e.get("long_msg")))[:120]
        for d in data.get("results", []):
            fn = d.get("path") or ""
            if is_test(fn):
                ctx["test_skipped"] = ctx.get("test_skipped", 0) + 1
                continue
            rid = (d.get("check_id") or "?").split(".")[-1]
            ex = d.get("extra") or {}
            res.append(mk("semgrep", rid, fn, (d.get("start") or {}).get("line"), ex.get("severity", "WARNING"), (ex.get("message") or "").split("\n")[0]))
    return "OK", res, ""


def run_gitleaks(root, files, timeout, ctx):
    """ctx: {'repo_path','base','head'} -> commit-range scan (only NEW commits); None base -> directory scan of root."""
    exe = find_tool("gitleaks")
    if not exe:
        return "UNVERIFIED", [], "gitleaks not installed"
    tmp = tempfile.mkdtemp(prefix="qa-gl-")
    rep = os.path.join(tmp, "r.json")
    try:
        # trusted config (built-in rules only, so a repo .gitleaks.toml allowlist cannot silence the scan), an EMPTY ignore file
        # (.gitleaksignore in the repo cannot either), and gitleaks:allow comments are not honoured
        cfg, ign = os.path.join(tmp, "trusted.toml"), os.path.join(tmp, "empty.gitleaksignore")
        with open(cfg, "w") as fh:
            fh.write("[extend]\nuseDefault = true\n")
        open(ign, "w").close()
        common = ["--redact", "--no-banner", "--exit-code", "0", "-f", "json", "-r", rep, "-c", cfg, "-i", ign, "--ignore-gitleaks-allow"]
        if ctx.get("range"):
            cmd = [exe, "git"] + common + ["--log-opts", ctx["range"], ctx["repo_path"]]
        else:
            cmd = [exe, "dir"] + common + [root]
        rc, out, err = qc.run(cmd, timeout=timeout, env={"GITLEAKS_CONFIG": "", "GITLEAKS_CONFIG_TOML": ""})
        if rc in (124, 127):
            return "UNVERIFIED", [], "gitleaks %s" % ("timed out" if rc == 124 else "missing")
        if rc != 0:
            return "UNVERIFIED", [], "gitleaks failed rc=%s" % rc
        try:
            data = json.load(open(rep)) if os.path.exists(rep) else []
        except ValueError:
            return "UNVERIFIED", [], "gitleaks report unparsable"
        res = []
        fset = set(files) if files is not None else None
        for d in data or []:
            fn = relto(d.get("File") or "", root)
            if fset is not None and ctx.get("range") is None and fn not in fset:
                continue
            # the matched line is hashed for the fingerprint, NEVER emitted
            text = hashlib.sha1((d.get("Line") or d.get("Match") or "").encode("utf-8", "replace")).hexdigest()[:12]
            res.append(mk("gitleaks", d.get("RuleID", "?"), fn, d.get("StartLine"), "ERROR", "potential secret (redacted)", text=text))
        return "OK", res, ""
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


REQ_PIN = re.compile(r"^\s*([A-Za-z0-9_.\-]+)(?:\[[^\]]*\])?\s*==\s*([A-Za-z0-9_.\-+!]+)")


def run_pip_audit(root, files, timeout, ctx):
    exe = find_tool("pip-audit")
    reqs = [f for f in files if re.search(r"(^|/)requirements[^/]*\.txt$", f) and os.path.isfile(os.path.join(root, f))]
    if not reqs:
        return "NA", [], "no requirements files"
    if not exe:
        return "UNVERIFIED", [], "pip-audit not installed"
    res, skipped, pinned_total = [], 0, 0
    tmp = tempfile.mkdtemp(prefix="qa-pa-")
    try:
        for rq in reqs:
            lines, pins = [], {}
            for ln in open(os.path.join(root, rq), errors="replace"):
                m = REQ_PIN.match(ln)
                if m:
                    lines.append("%s==%s" % (m.group(1), m.group(2)))
                    pins[m.group(1).lower().replace("_", "-")] = norm(ln)
                elif ln.strip() and not ln.lstrip().startswith(("#", "-")):
                    skipped += 1
            pinned_total += len(lines)
            if not lines:
                continue
            tf = os.path.join(tmp, "req.txt")
            open(tf, "w").write("\n".join(lines) + "\n")
            rc, out, err = qc.run([exe, "-r", tf, "--no-deps", "--disable-pip", "-f", "json", "--progress-spinner", "off"], timeout=timeout)
            if rc in (124, 127):
                return "UNVERIFIED", [], "pip-audit %s" % ("timed out" if rc == 124 else "missing")
            try:
                data = json.loads(out)
            except ValueError:
                return "UNVERIFIED", [], "pip-audit failed (network?) rc=%s: %s" % (rc, norm(err)[-120:])
            for dep in data.get("dependencies", []):
                for v in dep.get("vulns", []) or []:
                    key = dep["name"].lower().replace("_", "-")
                    res.append(mk("pip-audit", v.get("id", "VULN"), rq, 0, "WARNING",
                                  "%s==%s: %s" % (dep["name"], dep.get("version"), norm(v.get("description", ""))[:100]),
                                  text="%s==%s" % (key, dep.get("version"))))
        if pinned_total == 0:
            return "UNVERIFIED", [], "no pinned (==) requirements to audit (%d unpinned)" % skipped
        return "OK", res, ("%d unpinned requirement lines not auditable" % skipped) if skipped else ""
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def run_npm_audit(root, files, timeout, ctx):
    dirs = sorted({os.path.dirname(f) for f in files if os.path.basename(f) in ("package.json", "package-lock.json")
                   and not any(p in EXCLUDE_DIRS for p in f.split("/")[:-1])})
    if not dirs:
        return "NA", [], "no package manifests"
    exe = find_tool("npm")
    if not exe:
        return "UNVERIFIED", [], "npm not installed"
    res, notes = [], []
    for d in dirs:
        full = os.path.join(root, d)
        if not os.path.isfile(os.path.join(full, "package-lock.json")):
            notes.append("%s has no package-lock.json" % (d or "."))
            continue
        rc, out, err = qc.run([exe, "audit", "--json", "--package-lock-only", "--no-fund", "--no-update-notifier"], cwd=full, timeout=timeout,
                              env={"npm_config_update_notifier": "false"})
        if rc in (124, 127):
            return "UNVERIFIED", [], "npm audit %s" % ("timed out" if rc == 124 else "missing")
        try:
            data = json.loads(out)
        except ValueError:
            return "UNVERIFIED", [], "npm audit unparsable (rc=%s)" % rc
        if "error" in data or "vulnerabilities" not in data:
            return "UNVERIFIED", [], "npm audit error: %s" % norm(str((data.get("error") or {}).get("code") or (data.get("error") or {}).get("summary") or "no vulnerabilities block"))[:120]
        lock = (d + "/" if d else "") + "package-lock.json"
        for name, v in data["vulnerabilities"].items():
            titles = [x.get("title") for x in v.get("via", []) if isinstance(x, dict) and x.get("title")]
            res.append(mk("npm-audit", "npm-audit:" + name, lock, 0, (v.get("severity") or "low").upper(), titles[0] if titles else "vulnerable dependency",
                          text="%s|%s" % (name, v.get("severity"))))
    if not res and notes and len(notes) == len(dirs):
        return "UNVERIFIED", [], "; ".join(notes)[:160]
    return "OK", res, "; ".join(notes)[:160]


RUNNERS = {"ruff": run_ruff, "mypy": run_mypy, "bandit": run_bandit, "semgrep": run_semgrep, "gitleaks": run_gitleaks,
           "pip-audit": run_pip_audit, "npm-audit": run_npm_audit}


# ---------------------------------------------------------------- git helpers
def name_status(rd, base, head):
    """-> (changed new paths [ACMR], rename map new->old). NUL-separated (-z): non-ASCII / odd names are never quoted or lost."""
    rc, out, _ = qc.git(rd, "-c", "core.quotepath=off", "diff", "-z", "--name-status", "-M", "--diff-filter=ACMR", "%s..%s" % (base, head), timeout=120)
    files, ren = [], {}
    if rc != 0:
        return None, {}
    tok = out.split("\0")
    i = 0
    while i < len(tok):
        st = tok[i]
        if not st:
            i += 1
        elif st[0] in "RC" and i + 2 < len(tok):
            files.append(tok[i + 2])
            if st[0] == "R":
                ren[tok[i + 2]] = tok[i + 1]
            i += 3
        elif i + 1 < len(tok):
            files.append(tok[i + 1])
            i += 2
        else:
            i += 1
    return files, ren


def tracked_files(root):
    rc, out, _ = qc.git(root, "ls-files", "-z", timeout=60)
    if rc != 0:
        return []
    return [f for f in out.split("\0") if f and excluded_reason(f) is None]


def neutralize(wt):
    """The worktree is a throwaway checkout: remove repo-controlled files that make tools skip paths."""
    for n in (".semgrepignore", ".gitleaksignore", ".gitleaks.toml", ".bandit"):
        try:
            os.remove(os.path.join(wt, n))
        except OSError:
            pass


def scan_tool(tool, root, files, timeout, ctx):
    t0 = time.time()
    ctx = dict(ctx)
    try:
        st, res, note = RUNNERS[tool](root, files, timeout, ctx)
    except Exception as ex:  # noqa: BLE001 - a crashing tool is an UNVERIFIED cell, not a crashed gate
        st, res, note = "UNVERIFIED", [], "%s crashed: %s: %s" % (tool, type(ex).__name__, str(ex)[:100])
    lines = Lines(root)
    for f in res:
        f["fp"] = fingerprint(f, lines)
    return {"status": st, "findings": res, "note": note, "ms": int((time.time() - t0) * 1000), "test_skipped": ctx.get("test_skipped", 0)}


def parse_args(argv):
    o = {"repo": None, "base": None, "head": None, "ref": None, "tools": ",".join(ALL_TOOLS), "baseline": "auto",
         "timeout": os.environ.get("QA_SCANNERS_TIMEOUT", "150")}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    o["tools"] = [t for t in o["tools"].split(",") if t in ALL_TOOLS]
    try:
        o["timeout"] = int(o["timeout"])
        if o["timeout"] < 1:
            raise ValueError
    except ValueError:
        o["error"] = "invalid --timeout %r (need a positive integer of seconds)" % (o["timeout"],)
        o["timeout"] = 150
    return o


def baseline_path(repo):
    return os.path.join(qc.state_dir(), "qa_baselines", GATE, repo + ".json")


def load_baseline(repo):
    try:
        with open(baseline_path(repo)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def parallel(jobs, workers=3):
    """jobs: {name: callable}; returns {name: result}."""
    out = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {n: ex.submit(fn) for n, fn in jobs.items()}
        for n, fu in futs.items():
            out[n] = fu.result()
    return out


# ---------------------------------------------------------------- baseline
def full_scan(o):
    """Scan every tracked file at --ref. -> (sha, {tool: scan result}) or (None, error string)."""
    repo, ref = o["repo"], o["ref"]
    if not repo or not ref:
        return None, "needs --repo and --ref"
    rd = qc.repo_dir(repo)
    if not rd:
        return None, "no clone for repo"
    sha = qc.git(rd, "rev-parse", "--verify", "-q", ref + "^{commit}")[1].strip()
    if not sha:
        return None, "ref not found"
    with qc.worktree(rd, sha) as wt:
        if not wt:
            return None, "could not create worktree"
        neutralize(wt)
        files = tracked_files(wt)
        bt = max(o["timeout"], 600)
        # audits are intentionally not stored (see module doc); gitleaks scans the tree, not history
        tools = [t for t in o["tools"] if t not in AUDIT_TOOLS]
        return sha, parallel({t: (lambda t=t: scan_tool(t, wt, files, bt, {"range": None})) for t in tools})


def do_findings(argv):
    """Diagnostic: list every finding of a full scan (redacted) - used to classify real vs false positive."""
    o = parse_args(argv)
    if o.get("error"):
        return qc.verdict("UNVERIFIED", GATE, o["repo"] or "?", o["ref"] or "?", o["error"])
    sha, res = full_scan(o)
    if sha is None:
        return qc.verdict("UNVERIFIED", GATE, o["repo"] or "?", o["ref"] or "?", res)
    rows = [{"tool": f["tool"], "rule": f["rule"], "at": "%s:%d" % (f["file"], f["line"]), "sev": f["sev"], "msg": f["msg"]}
            for r in res.values() for f in r["findings"]]
    return qc.verdict("PASS", GATE, o["repo"], o["ref"], "%d findings" % len(rows), {"findings": rows, "cells": {t: {"status": r["status"], "n": len(r["findings"]), "note": r["note"]} for t, r in res.items()}})


def do_baseline(argv):
    o = parse_args(argv)
    repo, ref = o["repo"], o["ref"]
    if o.get("error"):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", ref or "?", o["error"])
    sha, res = full_scan(o)
    if sha is None:
        return qc.verdict("UNVERIFIED", GATE, repo or "?", ref or "?", "baseline: " + res)
    cells, fps = {}, {}
    for t, r in res.items():
        cells[t] = {"status": r["status"], "n": len(r["findings"]), "ms": r["ms"], "note": r["note"]}
        if r["status"] in ("OK", "NA"):
            for f in r["findings"]:
                e = fps.setdefault(f["fp"], {"tool": t, "rule": f["rule"], "file": f["file"], "n": 0})
                e["n"] += 1
    ok = [t for t, c in cells.items() if c["status"] == "OK"]
    doc = {"repo": repo, "ref": ref, "sha": sha, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "cells": cells, "fingerprints": fps}
    bp = baseline_path(repo)
    if ok:
        os.makedirs(os.path.dirname(bp), exist_ok=True)
        tmp = bp + ".tmp%d" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(doc, f, sort_keys=True)
        os.replace(tmp, bp)
    v = "PASS" if ok else "UNVERIFIED"
    return qc.verdict(v, GATE, repo, ref, "baseline %s: %d fingerprints from %s; unverified cells: %s" % (
        "stored" if ok else "NOT stored", sum(e["n"] for e in fps.values()), ",".join(ok) or "none",
        ",".join(t for t, c in cells.items() if c["status"] == "UNVERIFIED") or "none"), {"action": "baseline", "sha": sha, "cells": cells})


# ---------------------------------------------------------------- check
def do_check(argv):
    o = parse_args(argv)
    repo, base, head = o["repo"], o["base"], o["head"]
    if not (repo and base and head):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", head or "?", "check needs --repo --base --head")
    if o.get("error"):
        return qc.verdict("UNVERIFIED", GATE, repo, head, o["error"])
    if qc.mode(GATE) == "off":
        return qc.verdict("NA", GATE, repo, head, "gate is off")
    rd = qc.repo_dir(repo)
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "no clone for repo")
    for r in (base, head):
        if qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")[0] != 0:
            return qc.verdict("UNVERIFIED", GATE, repo, head, "ref %s not found" % r)
    # the range is merge-base..head: a develop that moved ahead of the branch must not make develop's own changes "the branch's"
    rc, mbo, _ = qc.git(rd, "merge-base", base, head)
    mb = mbo.strip().splitlines()[0] if rc == 0 and mbo.strip() else ""
    if not mb:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "no merge-base between %s and %s" % (base, head))
    allfiles, ren = name_status(rd, mb, head)
    if allfiles is None:
        return qc.verdict("UNVERIFIED", GATE, repo, head, "git diff failed")
    skipped = Counter()
    files = []
    for f in allfiles:
        why = excluded_reason(f)
        if why:
            skipped[why] += 1
        else:
            files.append(f)
    tools = list(o["tools"])
    if not allfiles:
        # a secret added and removed again inside the range leaves no net diff but is still in history
        rc, cnt, _ = qc.git(rd, "rev-list", "--count", "%s..%s" % (mb, head))
        if rc != 0 or not cnt.strip().isdigit():
            return qc.verdict("UNVERIFIED", GATE, repo, head, "git rev-list failed")
        if cnt.strip() == "0" or "gitleaks" not in tools:
            return qc.verdict("NA", GATE, repo, head, "no changed files")
    if not files:
        tools = [t for t in tools if t == "gitleaks"]
    policy_all = bool(allfiles) and not files
    bmode = o["baseline"]
    stored = load_baseline(repo) if bmode in ("auto", "stored") else None
    t = o["timeout"]
    cells, new_all, unscannable, test_skipped = {}, [], {}, 0
    with qc.worktree(rd, head) as hwt:
        if not hwt:
            return qc.verdict("UNVERIFIED", GATE, repo, head, "could not create worktree")
        neutralize(hwt)
        for f in files:
            if f.endswith(PY_EXT + JS_EXT):
                why = unscannable_reason(hwt, f)
                if why:
                    unscannable.setdefault(why, []).append(f)
        hres = parallel({tool: (lambda tool=tool: scan_tool(tool, hwt, files, t, {"range": "%s..%s" % (mb, head), "repo_path": rd} if tool == "gitleaks" else {}))
                         for tool in tools})
        test_skipped = sum(r.get("test_skipped", 0) for r in hres.values())
        # decide which tools need a base-ref scan
        need_base = []
        for tool in tools:
            r = hres[tool]
            if r["status"] != "OK" or not r["findings"]:
                continue
            sc = (stored or {}).get("cells", {}).get(tool, {})
            use_stored = tool not in AUDIT_TOOLS and bmode != "base" and sc.get("status") in ("OK", "NA") and bmode != "none"
            if bmode == "none":
                continue
            if bmode == "stored" and tool not in AUDIT_TOOLS and not use_stored:
                continue
            if not use_stored:
                need_base.append(tool)
        bres = {}
        if need_base:
            with qc.worktree(rd, mb) as bwt:
                if bwt:
                    neutralize(bwt)
                    old_of = {new: old for new, old in ren.items()}
                    bfiles = [old_of.get(f, f) for f in files]
                    bres = parallel({tool: (lambda tool=tool: scan_tool(tool, bwt, bfiles, t, {"range": None} if tool == "gitleaks" else {}))
                                     for tool in need_base})
        for tool in tools:
            r = hres[tool]
            cell = {"status": r["status"], "n": len(r["findings"]), "new": 0, "ms": r["ms"], "note": r["note"], "baseline": "n/a"}
            if r["status"] == "OK" and r["findings"]:
                sc = (stored or {}).get("cells", {}).get(tool, {})
                if bmode == "none":
                    basecnt, cell["baseline"] = Counter(), "none"
                elif tool in bres:
                    br = bres[tool]
                    if br["status"] == "NA":
                        br = {"status": "OK", "findings": [], "note": ""}
                    if br["status"] != "OK":
                        cell.update(status="UNVERIFIED", note="baseline scan at base was %s: %s" % (br["status"], br["note"]))
                        cells[tool] = cell
                        continue
                    basecnt, cell["baseline"] = Counter(f["fp"] for f in br["findings"]), "base"
                elif tool not in AUDIT_TOOLS and bmode != "base" and sc.get("status") in ("OK", "NA"):
                    fpm = stored["fingerprints"]
                    basecnt, cell["baseline"] = Counter({k: v["n"] for k, v in fpm.items() if v["tool"] == tool}), "stored@" + stored["sha"][:8]
                else:
                    cell.update(status="UNVERIFIED", note="no baseline for %s (mode=%s)" % (tool, bmode))
                    cells[tool] = cell
                    continue
                remaining = Counter(basecnt)
                for f in r["findings"]:
                    alt = fp_of(f["tool"], f["rule"], ren[f["file"]], f["ntext"]) if f["file"] in ren else None
                    if remaining[f["fp"]] > 0:
                        remaining[f["fp"]] -= 1
                    elif alt and remaining[alt] > 0:     # same finding, file was renamed
                        remaining[alt] -= 1
                    else:
                        new_all.append(f)
                        cell["new"] += 1
            cells[tool] = cell
    # verdict
    real = [f for f in new_all if not advisory(f)]
    advis = [f for f in new_all if advisory(f)]
    blk = [f for f in real if blocking(f)]
    unver = [t for t, c in cells.items() if c["status"] == "UNVERIFIED" and t not in ADVISORY]
    unscanned_txt = ", ".join("%d %s" % (len(v), k) for k, v in sorted(unscannable.items()) if k != "symlink")
    n_unscanned = sum(len(v) for k, v in unscannable.items() if k != "symlink")
    brief = lambda fs: [{"tool": f["tool"], "rule": f["rule"], "at": "%s:%d" % (f["file"], f["line"]), "sev": f["sev"], "msg": f["msg"]} for f in fs[:40]]
    for k, v in unscannable.items():
        skipped["unscannable_" + k] += len(v)
    details = {"files": len(allfiles), "scanned_files": len(files), "skipped": dict(skipped), "unscannable": {k: v[:5] for k, v in unscannable.items()},
               "test_findings_excluded": test_skipped, "merge_base": mb, "cells": cells, "new": brief(sorted(real, key=lambda f: (not blocking(f), f["tool"], f["file"], f["line"]))),
               "advisory_new": brief(advis), "advisory_tools": sorted(ADVISORY), "baseline_mode": bmode,
               "stored_baseline": (stored or {}).get("sha", None)}
    cnt = Counter("%s:%s" % (f["tool"], f["rule"]) for f in real)
    nloc = len({(f["file"], f["line"]) for f in real})
    top = ", ".join("%s x%d" % kv for kv in cnt.most_common(4))
    if blk:
        v, s = "FAIL", "%d new blocking finding(s) of %d new (%d location(s)): %s" % (len(blk), len(real), nloc, top)
    elif real:
        v, s = "FLAG", "%d new finding(s) at %d location(s): %s" % (len(real), nloc, top)
    elif unver and not any(c["status"] == "OK" and t not in ADVISORY for t, c in cells.items()):
        v, s = "UNVERIFIED", "no scanner could run: " + "; ".join("%s: %s" % (t, cells[t]["note"]) for t in unver)[:250]
    elif unver:
        v, s = "UNVERIFIED", "no new findings but cells unverified: " + "; ".join("%s: %s" % (t, cells[t]["note"]) for t in unver)[:230]
    elif n_unscanned:
        v, s = "UNVERIFIED", "no new findings but %d changed source file(s) could not be scanned (%s)" % (n_unscanned, unscanned_txt)
    elif policy_all:
        v, s = "UNVERIFIED", "all %d changed file(s) are excluded by policy (%s); only the secret scan ran" % (
            len(allfiles), ", ".join("%d %s" % (n, k) for k, n in sorted(skipped.items())))
    elif all(c["status"] == "NA" for c in cells.values()):
        v, s = "NA", "nothing applicable to scan"
    else:
        extra = "; %d advisory new" % len(advis) if advis else ""
        if skipped:
            extra += "; skipped: " + ", ".join("%d %s" % (n, k) for k, n in sorted(skipped.items()))
        v, s = "PASS", "no new findings (%d pre-existing suppressed by baseline%s)" % (sum(c["n"] for c in cells.values()), extra)
    return qc.verdict(v, GATE, repo, head, s, details)


def main(argv):
    if argv and argv[0] == "baseline":
        return qc.main_guard(GATE, do_baseline, argv[1:] + ["--no-record"])
    if argv and argv[0] == "findings":
        return qc.main_guard(GATE, do_findings, argv[1:] + ["--no-record"])
    if argv and argv[0] == "check":
        return qc.main_guard(GATE, do_check, argv[1:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
