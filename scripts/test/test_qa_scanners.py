#!/usr/bin/env python3
"""Tests for qa/gate_scanners.py (GATE S5).

Two layers:
  * LOGIC tests use stub tools (QA_TOOL_<NAME> overrides) so they run identically on the Mac and on the box:
    baseline/fingerprint stability, rename-awareness, multiset counting, UNVERIFIED on missing tool / timeout / garbage,
    pip-audit + npm audit parsing (mocked: no network), verdict mapping, secret redaction, CLI/exit-code contract.
  * REAL-TOOL tests (ruff, bandit, semgrep, gitleaks, mypy) run only where the tool exists (the GPU box); elsewhere they print
    SKIP and are counted as skipped - never as passed.
The gate is always invoked as the real entry point: absolute path AND relative path from scripts/overnight-queue, under
`env -i` with a minimal PATH and NTFY_SERVER set. No test touches the network or ntfy.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
GATE = os.path.join(OQ, "qa", "gate_scanners.py")
RULES = os.path.join(OQ, "qa", "semgrep_rules.yml")
P = F = S = 0
HOME = os.path.expanduser("~")


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def skip(name, why):
    global S
    S += 1
    print("  SKIP " + name + " (" + why + ")")


T = tempfile.mkdtemp(prefix="qa-scanners-test-")
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(T, "repos")
os.makedirs(os.path.join(OVN, "state"))
os.makedirs(REPOS)
BIN = os.path.join(T, "bin")
os.makedirs(BIN)


def sh(cmd, cwd=None, env=None):
    e = dict(os.environ)
    e.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})
    if env:
        e.update(env)
    p = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def stub(name, body):
    """Write an executable python stub tool into BIN and return its path."""
    p = os.path.join(BIN, name)
    with open(p, "w") as f:
        f.write("#!%s\n%s\n" % (sys.executable, body))
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)
    return p


# stub ruff: flags every line containing BADTHING (code X999), absolute filename like the real tool
STUB_RUFF = stub("ruff", r'''
import sys, json, os
files = [a for a in sys.argv[1:] if a.endswith(".py")]
out = []
for f in files:
    for i, l in enumerate(open(f, errors="replace"), 1):
        if "BADTHING" in l:
            out.append({"code": "X999", "filename": os.path.abspath(f), "location": {"row": i, "column": 1}, "message": "bad thing"})
        if "SYNTAXERR" in l:
            out.append({"code": None, "filename": os.path.abspath(f), "location": {"row": i, "column": 1}, "message": "invalid syntax"})
print(json.dumps(out)); sys.exit(1 if out else 0)
''')
STUB_SLEEP = stub("sleeper", "import time; time.sleep(30)")
STUB_GARBAGE = stub("garbage", "print('this is not json at all'); import sys; sys.exit(3)")
STUB_PIPAUDIT = stub("pip-audit", r'''
import sys, json
req = sys.argv[sys.argv.index("-r") + 1]
deps = []
for l in open(req):
    n, v = l.strip().split("==")
    vulns = [{"id": "PYSEC-TEST-1", "fix_versions": ["9.9"], "description": "seeded vuln"}] if n == "vulnpkg" else []
    deps.append({"name": n, "version": v, "vulns": vulns})
print(json.dumps({"dependencies": deps})); sys.exit(1 if any(d["vulns"] for d in deps) else 0)
''')
STUB_PIPAUDIT_NET = stub("pip-audit-net", "import sys; sys.stderr.write('Failed to establish a new connection: Name or service not known'); sys.exit(1)")
STUB_NPM = stub("npm", r'''
import sys, json, os
lock = json.load(open("package-lock.json"))
vulns = {}
for k, v in lock.get("seeded", {}).items():
    vulns[k] = {"name": k, "severity": v, "via": [{"title": "seeded advisory for " + k}], "range": "*", "fixAvailable": True}
print(json.dumps({"auditReportVersion": 2, "vulnerabilities": vulns})); sys.exit(1 if vulns else 0)
''')
STUB_NPM_NET = stub("npm-net", "import sys, json; print(json.dumps({'error': {'code': 'ENOTFOUND', 'summary': 'network'}})); sys.exit(1)")


def gate(args, tools=None, rel=False, extra_env=None, timeout=300):
    """Run the gate as cron would: env -i, minimal PATH, NTFY_SERVER set. Returns (exit code, result dict | None, stdout)."""
    env = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": HOME, "NTFY_SERVER": "http://127.0.0.1:9", "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS,
           "LANG": "C.UTF-8"}
    for k, v in (tools or {}).items():
        env["QA_TOOL_" + k.upper().replace("-", "_")] = v
    if extra_env:
        env.update(extra_env)
    if rel:
        cmd, cwd = ["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, "qa/gate_scanners.py"] + args, OQ
    else:
        cmd, cwd = ["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE] + args, "/"
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = None
    return p.returncode, res, p.stdout + p.stderr


def mkrepo(name, files):
    d = os.path.join(REPOS, name)
    os.makedirs(d)
    sh(["git", "init", "-q", "-b", "main"], cwd=d)
    commit(name, files, "init")
    return d


def commit(name, files, msg, remove=()):
    d = os.path.join(REPOS, name)
    for rel, content in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)
    for rel in remove:
        sh(["git", "rm", "-q", "-f", rel], cwd=d)
    sh(["git", "add", "--"] + list(files.keys()), cwd=d)
    sh(["git", "commit", "-q", "--allow-empty", "-m", msg], cwd=d)
    return sh(["git", "rev-parse", "HEAD"], cwd=d)[1].strip()


def sha(name, ref="HEAD"):
    return sh(["git", "rev-parse", ref], cwd=os.path.join(REPOS, name))[1].strip()


def chk(repo, base, head, tools, extra=None, **kw):
    return gate(["check", "--repo", repo, "--base", base, "--head", head, "--no-record"] + (extra or []), tools=tools, **kw)


print("== logic tests (stub tools) ==")
RT = {"ruff": STUB_RUFF}
base_code = "def f():\n    x = 1  # BADTHING pre-existing\n    return x\n"
b0 = None
mkrepo("lg", {"a.py": base_code, "keep.py": "def g():\n    return 1\n"})
b0 = sha("lg")

# baseline command
rc, res, out = gate(["baseline", "--repo", "lg", "--ref", b0, "--tools", "ruff"], tools=RT)
bp = os.path.join(OVN, "state", "qa_baselines", "scanners", "lg.json")
ok("baseline: exit 0 + verdict PASS + file stored under state/qa_baselines/scanners/<repo>.json", rc == 0 and res and res["verdict"] == "PASS" and os.path.isfile(bp), out)
bl = json.load(open(bp))
ok("baseline: stores the pre-existing finding fingerprint (count 1)", sum(e["n"] for e in bl["fingerprints"].values()) == 1 and bl["sha"] == b0)
ok("baseline: records per-tool cell status", bl["cells"]["ruff"]["status"] == "OK")
ok("baseline: not written to shadow log (no gate record side effect)", not os.path.exists(os.path.join(OVN, "state", "qa_shadow", "scanners.jsonl")))

# benign: change that adds clean code only -> PASS, pre-existing suppressed
h1 = commit("lg", {"keep.py": "def g():\n    return 2\n"}, "clean change")
rc, res, out = chk("lg", b0, h1, RT, ["--tools", "ruff"])
ok("benign control: clean change -> PASS", rc == 0 and res["verdict"] == "PASS", res)

# the changed file contains the PRE-EXISTING finding, shifted by new lines above -> still no new finding
h2 = commit("lg", {"a.py": "import os\n\n\n" + base_code}, "shift lines only")
rc, res, out = chk("lg", b0, h2, RT, ["--tools", "ruff"])
ok("baseline-aware: pre-existing finding with shifted line numbers is NOT new -> PASS", res["verdict"] == "PASS", res)
ok("baseline-aware: cell says baseline came from the stored file", res["details"]["cells"]["ruff"]["baseline"].startswith("stored@"), res["details"]["cells"])

# NEGATIVE: add a genuinely new finding
h3 = commit("lg", {"a.py": "import os\n\n\n" + base_code + "\ndef h():\n    y = 2  # BADTHING new one\n    return y\n"}, "add new finding")
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff"])
ok("negative control: a NEW finding -> FLAG (non-blocking class) and reported with file:line", res["verdict"] == "FLAG" and any(n["at"] == "a.py:9" for n in res["details"]["new"]), res)

# multiset: copying the pre-existing bad line again must count as ONE new finding
h4 = commit("lg", {"a.py": base_code + "def dup():\n    x = 1  # BADTHING pre-existing\n    return x\n"}, "duplicate bad line")
rc, res, out = chk("lg", b0, h4, RT, ["--tools", "ruff"])
ok("multiset: duplicating an existing bad line yields exactly 1 new finding", res["verdict"] == "FLAG" and res["details"]["cells"]["ruff"]["new"] == 1, res)

# blocking class (syntax error) -> FAIL
h5 = commit("lg", {"s.py": "x = (  # SYNTAXERR\n"}, "syntax error file")
rc, res, out = chk("lg", b0, h5, RT, ["--tools", "ruff"])
ok("negative control: blocking class (syntax error) -> FAIL", res["verdict"] == "FAIL", res)

# rename of a file holding a pre-existing finding is not 'new' (base mode and stored mode)
rd = os.path.join(REPOS, "lg")
sh(["git", "checkout", "-q", "-b", "ren", b0], cwd=rd)
sh(["git", "mv", "a.py", "renamed_a.py"], cwd=rd)
sh(["git", "commit", "-q", "-m", "rename"], cwd=rd)
hr = sha("lg")
for mode in ("base", "stored"):
    rc, res, out = chk("lg", b0, hr, RT, ["--tools", "ruff", "--baseline", mode])
    ok("rename-aware (%s baseline): moved file with pre-existing finding -> PASS" % mode, res["verdict"] == "PASS", res)
sh(["git", "checkout", "-q", "main"], cwd=rd)

# baseline=base works with no stored baseline at all
os.rename(bp, bp + ".bak")
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff"])
ok("no stored baseline -> falls back to scanning the same files at base (still FLAG on the new one only)", res["verdict"] == "FLAG" and res["details"]["cells"]["ruff"]["baseline"] == "base" and res["details"]["cells"]["ruff"]["new"] == 1, res)
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff", "--baseline", "none"])
ok("--baseline none counts every finding (2)", res["details"]["cells"]["ruff"]["new"] == 2, res)
os.rename(bp + ".bak", bp)

# test files are excluded from S-class/semgrep/bandit noise by the gate (stub emits X999 so use the tests/ path with ruff stub: still reported for non-S)
# UNVERIFIED cases
rc, res, out = chk("lg", b0, h3, {"ruff": "/nonexistent/ruff"}, ["--tools", "ruff"])
ok("missing tool -> UNVERIFIED (never PASS), exit 0", rc == 0 and res["verdict"] == "UNVERIFIED" and res["details"]["cells"]["ruff"]["status"] == "UNVERIFIED", res)
rc, res, out = chk("lg", b0, h3, {"ruff": STUB_SLEEP}, ["--tools", "ruff", "--timeout", "2"])
ok("tool timeout -> UNVERIFIED, exit 0", rc == 0 and res["verdict"] == "UNVERIFIED" and "timed out" in res["details"]["cells"]["ruff"]["note"], res)
rc, res, out = chk("lg", b0, h3, {"ruff": STUB_GARBAGE}, ["--tools", "ruff"])
ok("tool prints garbage -> UNVERIFIED, exit 0", rc == 0 and res["verdict"] == "UNVERIFIED", res)
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff"], extra_env={"OVN_QA_SCANNERS": "off"})
ok("mode off -> NA", res["verdict"] == "NA", res)

# a missing tool must not mask findings from another tool
rc, res, out = chk("lg", b0, h3, {"ruff": STUB_RUFF, "bandit": "/nonexistent/bandit"}, ["--tools", "ruff,bandit"])
ok("one tool missing + another finds something -> verdict still FLAG, missing cell listed UNVERIFIED",
   res["verdict"] == "FLAG" and res["details"]["cells"]["bandit"]["status"] == "UNVERIFIED", res)

# contract: bad args / bad repo / bad ref
rc, res, out = gate(["check", "--repo", "nope", "--base", "a", "--head", "b", "--no-record"], tools=RT)
ok("unknown repo -> UNVERIFIED exit 0", rc == 0 and res["verdict"] == "UNVERIFIED", out)
rc, res, out = chk("lg", "deadbeef", h3, RT)
ok("unknown ref -> UNVERIFIED exit 0", rc == 0 and res["verdict"] == "UNVERIFIED", out)
rc, res, out = gate(["check", "--repo", "lg", "--no-record"], tools=RT)
ok("missing args -> UNVERIFIED exit 0", rc == 0 and res["verdict"] == "UNVERIFIED", out)
rc, res, out = chk("lg", h3, h3, RT)
ok("empty range -> NA", res["verdict"] == "NA", res)

# exit code contract
rc, res, out = chk("lg", b0, h5, RT, ["--tools", "ruff"], extra_env={"OVN_QA_SCANNERS": "enforce"})
ok("enforce mode without --enforce-exit: exit 0 even on FAIL", rc == 0 and res["verdict"] == "FAIL")
rc, res, out = chk("lg", b0, h5, RT, ["--tools", "ruff", "--enforce-exit"], extra_env={"OVN_QA_SCANNERS": "enforce"})
ok("enforce mode + --enforce-exit + FAIL -> exit 1", rc == 1)
rc, res, out = chk("lg", b0, h5, RT, ["--tools", "ruff", "--enforce-exit"])
ok("shadow mode + --enforce-exit + FAIL -> still exit 0", rc == 0 and res["mode"] == "shadow")

# entry point exactly as run: relative path from scripts/overnight-queue
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff"], rel=True)
ok("relative-path entry point under env -i works (FLAG)", rc == 0 and res and res["verdict"] == "FLAG", out)
ok("exactly one JSON line is the last stdout line", out.strip().splitlines()[-1].startswith("{"))
# shadow record is written when --no-record is absent
rc, res, out = gate(["check", "--repo", "lg", "--base", b0, "--head", h3, "--tools", "ruff"], tools=RT)
ok("without --no-record the result is appended to state/qa_shadow/scanners.jsonl", os.path.isfile(os.path.join(OVN, "state", "qa_shadow", "scanners.jsonl")))

print("== dependency audits (mocked, no network) ==")
mkrepo("dp", {"requirements.txt": "fastapi==0.1.0\nvulnpkg==1.0.0\nloose>=2\n", "web/package.json": "{}", "web/package-lock.json": json.dumps({"seeded": {"oldvuln": "moderate"}})})
d0 = sha("dp")
d1 = commit("dp", {"requirements.txt": "fastapi==0.1.0\nvulnpkg==1.0.0\nloose>=2\nrequests==2.0.0\n"}, "add a clean pin")
rc, res, out = chk("dp", d0, d1, {"pip-audit": STUB_PIPAUDIT}, ["--tools", "pip-audit"])
ok("pip-audit: a pre-existing vuln that is unchanged is not new -> PASS", res["verdict"] == "PASS" and res["details"]["cells"]["pip-audit"]["baseline"] == "base", res)
ok("pip-audit: unpinned lines are noted, not silently dropped", "unpinned" in res["details"]["cells"]["pip-audit"]["note"], res["details"]["cells"])
d2 = commit("dp", {"requirements.txt": "fastapi==0.1.0\nvulnpkg==1.0.0\nvulnpkg2==1\nloose>=2\n"}, "swap pin")
d3 = commit("dp", {"requirements-dev.txt": "vulnpkg==3.0.0\n"}, "new requirements file with a vulnerable pin")
rc, res, out = chk("dp", d2, d3, {"pip-audit": STUB_PIPAUDIT}, ["--tools", "pip-audit"])
ok("negative control: newly added vulnerable pin -> FLAG with the advisory id", res["verdict"] == "FLAG" and any(n["rule"] == "PYSEC-TEST-1" for n in res["details"]["new"]), res)
rc, res, out = chk("dp", d2, d3, {"pip-audit": STUB_PIPAUDIT_NET}, ["--tools", "pip-audit"])
ok("pip-audit with no network -> UNVERIFIED (not PASS)", res["verdict"] == "UNVERIFIED", res)
rc, res, out = chk("dp", d2, d3, {"pip-audit": "/nonexistent/pip-audit"}, ["--tools", "pip-audit"])
ok("pip-audit missing -> UNVERIFIED", res["verdict"] == "UNVERIFIED", res)
d4 = commit("dp", {"web/package-lock.json": json.dumps({"seeded": {"oldvuln": "moderate", "evilpkg": "critical"}})}, "lock adds a critical advisory")
rc, res, out = chk("dp", d3, d4, {"npm": STUB_NPM}, ["--tools", "npm-audit"])
ok("negative control: npm audit new critical vuln -> FAIL (pre-existing moderate one suppressed)",
   res["verdict"] == "FAIL" and [n["rule"] for n in res["details"]["new"]] == ["npm-audit:evilpkg"], res)
d5 = commit("dp", {"web/package-lock.json": json.dumps({"seeded": {"oldvuln": "moderate", "evilpkg": "critical", "meh": "low"}})}, "lock adds a low advisory")
rc, res, out = chk("dp", d4, d5, {"npm": STUB_NPM}, ["--tools", "npm-audit"])
ok("npm audit new low-severity vuln -> FLAG (not blocking)", res["verdict"] == "FLAG", res)
rc, res, out = chk("dp", d4, d5, {"npm": STUB_NPM_NET}, ["--tools", "npm-audit"])
ok("npm audit network error -> UNVERIFIED", res["verdict"] == "UNVERIFIED", res)
d6 = commit("dp", {"web/package.json": '{"name": "x"}'}, "package.json only change")
rc, res, out = chk("dp", d5, d6, {"npm": STUB_NPM}, ["--tools", "npm-audit"])
ok("npm audit on package.json change audits the sibling lockfile; all pre-existing -> PASS", res["verdict"] == "PASS", res)
rc, res, out = chk("dp", d5, d6, {"pip-audit": STUB_PIPAUDIT, "npm": STUB_NPM}, ["--tools", "pip-audit"])
ok("pip-audit with no requirements change -> NA", res["verdict"] == "NA", res)

print("== review-fix regressions (stub tools): false-confidence cases ==")
sys.path.insert(0, os.path.join(OQ, "qa"))
import gate_scanners as gs_mod  # noqa: E402
# honour-suppression stubs: a line containing the marker is skipped UNLESS the gate passed the ignore flag
STUB_RUFF_NOQA = stub("ruff-noqa", r"""
import sys, json, os
ign = "--ignore-noqa" in sys.argv
out = []
for f in [a for a in sys.argv[1:] if a.endswith(".py")]:
    for i, l in enumerate(open(f, errors="replace"), 1):
        if "BADTHING" in l and not ("noqa" in l and not ign):
            out.append({"code": "X999", "filename": os.path.abspath(f), "location": {"row": i, "column": 1}, "message": "bad"})
print(json.dumps(out)); sys.exit(1 if out else 0)
""")
STUB_BANDIT = stub("bandit", r"""
import sys, json, os
ign = "--ignore-nosec" in sys.argv
res = []
for f in [a for a in sys.argv[1:] if a.endswith(".py")]:
    for i, l in enumerate(open(f, errors="replace"), 1):
        if "BADTHING" in l and not ("nosec" in l and not ign):
            res.append({"test_id": "B602", "issue_severity": "HIGH", "issue_confidence": "HIGH", "filename": os.path.abspath(f), "line_number": i, "issue_text": "bad"})
print(json.dumps({"results": res})); sys.exit(1 if res else 0)
""")
STUB_SEMGREP = stub("semgrep", r"""
import sys, json
ign = "--disable-nosem" in sys.argv
res = []
for f in [a for a in sys.argv[1:] if a.endswith((".py", ".js"))]:
    for i, l in enumerate(open(f, errors="replace"), 1):
        if "BADTHING" in l and not ("nosem" in l and not ign):
            res.append({"path": f, "check_id": "r.qa-test-rule", "start": {"line": i}, "extra": {"severity": "ERROR", "message": "bad"}})
print(json.dumps({"results": res, "errors": []}))
""")
# gitleaks stub: records argv, scans the commit range (git mode) or the tree (dir mode) for SECRETMARK, writes a gitleaks-shaped report
STUB_GITLEAKS = stub("gitleaks", r"""
import sys, json, os, subprocess
a = sys.argv[1:]
log = os.environ.get("STUB_ARGV_LOG")
if log:
    open(log, "a").write(json.dumps(a) + "\n")
rep = a[a.index("-r") + 1]
cfg = a[a.index("-c") + 1] if "-c" in a else None
if cfg and log:
    open(log, "a").write(json.dumps({"cfg": open(cfg).read()}) + "\n")
found = []
if a[0] == "git":
    rng, repo = a[a.index("--log-opts") + 1], a[-1]
    out = subprocess.run(["git", "-C", repo, "log", "-p", "--format=", rng], capture_output=True, text=True).stdout
    fn = None
    for l in out.splitlines():
        if l.startswith("+++ b/"):
            fn = l[6:]
        elif "SECRETMARK" in l and l.startswith("+"):
            found.append({"RuleID": "github-pat", "File": fn, "StartLine": 1, "Line": l, "Match": "REDACTED"})
else:
    root = a[-1]
    for dp, dn, fns in os.walk(root):
        for f in fns:
            q = os.path.join(dp, f)
            if ".git" in q.split(os.sep):
                continue
            for i, l in enumerate(open(q, errors="replace"), 1):
                if "SECRETMARK" in l:
                    found.append({"RuleID": "github-pat", "File": os.path.relpath(q, root), "StartLine": i, "Line": l, "Match": "REDACTED"})
json.dump(found, open(rep, "w"))
""")
STUB_MYPY = stub("mypy", r"""
import sys, os
tok = os.environ["STUB_TOKEN"]
f = [x for x in sys.argv[1:] if x.endswith(".py")][0]
print('%s:2:5: error: Incompatible types in assignment (expression has type "Literal[\'%s\']", variable has type "int")  [assignment]' % (f, tok))
sys.exit(1)
""")

# 1. non-ASCII path: was silently dropped (git quotes the name) -> PASS
mkrepo("na", {"app/ok.py": "x = 1\n"})
na0 = sha("na")
na1 = commit("na", {"app/ünï/bad.py": "y = 1  # BADTHING\n", "app/sp ace/bad.py": "y = 1  # BADTHING\n"}, "non-ascii + space path")
rc, res, out = chk("na", na0, na1, RT, ["--tools", "ruff"])
ats = sorted(n["at"] for n in (res or {}).get("details", {}).get("new", []))
ok("non-ASCII changed path is scanned (was silently dropped -> PASS)", res and res["verdict"] == "FLAG" and "app/ünï/bad.py:1" in ats and "app/sp ace/bad.py:1" in ats, res)

# 2. suppression comments must not silence the gate
mkrepo("sup", {"app/ok.py": "x = 1\n"})
s0 = sha("sup")
s1 = commit("sup", {"app/a.py": "z = 1  # BADTHING  # noqa  # nosec  # nosem\n"}, "suppressed bad line")
for tool, stubp in (("ruff", STUB_RUFF_NOQA), ("bandit", STUB_BANDIT), ("semgrep", STUB_SEMGREP)):
    rc, res, out = chk("sup", s0, s1, {tool: stubp}, ["--tools", tool])
    want = "FAIL" if tool != "ruff" else "FLAG"
    ok("suppression comment does not hide a finding: %s still reports (verdict %s)" % (tool, want), res and res["verdict"] == want, res)
# gitleaks: ignore flags + trusted config passed, repo-controlled files not honoured
alog = os.path.join(T, "gl_argv.log")
rc, res, out = chk("sup", s0, s1, {"gitleaks": STUB_GITLEAKS}, ["--tools", "gitleaks"], extra_env={"STUB_ARGV_LOG": alog})
lg = open(alog).read() if os.path.exists(alog) else ""
ok("gitleaks is run with --ignore-gitleaks-allow, an explicit trusted -c config and an explicit -i ignore file",
   "--ignore-gitleaks-allow" in lg and '"-c"' in lg and '"-i"' in lg and "useDefault = true" in lg, lg[:300])
# neutralize(): repo-controlled skip files are removed from the throwaway worktree
nd = tempfile.mkdtemp(prefix="neut-", dir=T)
for n in (".semgrepignore", ".gitleaksignore", ".gitleaks.toml", ".bandit", "keep.txt"):
    open(os.path.join(nd, n), "w").write("*\n")
try:
    gs_mod.neutralize(nd)
    left = sorted(os.listdir(nd))
except Exception as ex:  # noqa: BLE001
    left = ["ERR " + repr(ex)]
ok("neutralize removes .semgrepignore/.gitleaksignore/.gitleaks.toml/.bandit but nothing else", left == ["keep.txt"], left)

# 3. excluded dirs: real package names must be scanned; only truly vendored dirs are skipped
mkrepo("ex", {"app/ok.py": "x = 1\n"})
e0 = sha("ex")
files = {("app/%s/m.py" % d): "y = 1  # BADTHING\n" for d in ("env", "build", "vendor", "dist", "coverage", "mocks")}
e1 = commit("ex", files, "bad code in env/build/vendor/dist/coverage/mocks packages")
rc, res, out = chk("ex", e0, e1, RT, ["--tools", "ruff"])
got = sorted(n["at"] for n in (res or {}).get("details", {}).get("new", []))
ok("python under app/{env,build,vendor,dist,coverage,mocks}/ is scanned (was skipped -> PASS)", res and res["verdict"] == "FLAG" and len(got) == 6, got)
rc, res, out = chk("ex", e0, e1, {"bandit": STUB_BANDIT}, ["--tools", "bandit"])
ok("bandit still scans app/mocks/ (not a test dir)", res and any(n["at"].startswith("app/mocks/") for n in res["details"]["new"]), res)
e2 = commit("ex", {"app/node_modules/pkg/m.py": "y = 1  # BADTHING\n", "app/venv/lib/x.py": "y = 1  # BADTHING\n"}, "only vendored dirs changed")
rc, res, out = chk("ex", e1, e2, RT, ["--tools", "ruff"])
ok("every changed file in a vendored dir -> UNVERIFIED with counts (was NA 'no changed files')",
   res and res["verdict"] == "UNVERIFIED" and res["details"].get("skipped", {}).get("vendored_dir") == 2, res)
e3 = commit("ex", {"app/dist/bundle.js": "var a=1;\n", "app/ok3.py": "x = 3\n"}, "generated js + clean py")
rc, res, out = chk("ex", e2, e3, RT, ["--tools", "ruff"])
ok("generated JS in dist/ is a COUNTED skip (details.skipped + summary), PASS stays honest",
   res and res["verdict"] == "PASS" and res["details"].get("skipped", {}).get("generated_js_dir") == 1 and "skipped" in res["summary"], res)

# 4. changed source files no tool can read -> UNVERIFIED, never PASS/NA
mkrepo("un", {"app/ok.py": "x = 1\n"})
u0 = sha("un")
u1 = commit("un", {"app/bin.py": "\0\1\2binary\n"}, "binary file named .py")
rc, res, out = chk("un", u0, u1, RT, ["--tools", "ruff"])
ok("binary *.py -> UNVERIFIED with reason (no false E902 FAIL, no silent PASS)", res and res["verdict"] == "UNVERIFIED" and res["details"].get("unscannable", {}).get("binary") == ["app/bin.py"], res)
u2 = commit("un", {"app/big.py": "x = 1\n" * 300000}, "oversize py")
rc, res, out = chk("un", u1, u2, RT, ["--tools", "ruff"])
ok("oversize *.py (> 1MB) -> UNVERIFIED too_large", res and res["verdict"] == "UNVERIFIED" and "too_large" in res["details"].get("unscannable", {}), res)
u3 = commit("un", {"app/big.py": "x = 1\n" * 300000, "app/new.py": "y = 1  # BADTHING\n"}, "oversize + real finding")
rc, res, out = chk("un", u1, u3, RT, ["--tools", "ruff"])
ok("a real finding still wins over an unscanned file (FLAG)", res and res["verdict"] == "FLAG", res)

# 5. stale develop: merge-base range, develop's own change must not be blamed on the branch
mkrepo("sd", {"bad.py": "x = 1  # BADTHING\n", "ok.py": "y = 1\n"})
sd0 = sha("sd")
sdr = os.path.join(REPOS, "sd")
sh(["git", "checkout", "-q", "-b", "feat"], cwd=sdr)
sd_feat = commit("sd", {"ok2.py": "z = 1\n"}, "feature: clean file only")
sh(["git", "checkout", "-q", "main"], cwd=sdr)
sd_dev = commit("sd", {"bad.py": "x = 1\n"}, "develop fixes the bad line")
rc, res, out = chk("sd", sd_dev, sd_feat, RT, ["--tools", "ruff"])
ok("develop moved ahead: only the branch's own change is scanned -> PASS (was FLAG on develop's fixed line)",
   res and res["verdict"] == "PASS" and res["details"]["files"] == 1 and res["details"].get("merge_base") == sd0, res)

# 6. secret added then removed inside the range is still in history
mkrepo("sr", {"app/ok.py": "x = 1\n"})
sr0 = sha("sr")
commit("sr", {"app/cfg.py": "T = 'SECRETMARK'\n"}, "add secret")
sr2 = commit("sr", {}, "remove secret", remove=["app/cfg.py"])
rc, res, out = chk("sr", sr0, sr2, {"gitleaks": STUB_GITLEAKS}, ["--tools", "gitleaks"])
ok("secret committed then removed within the range -> FAIL (was NA 'no changed files')", res and res["verdict"] == "FAIL" and res["details"]["new"][0]["at"].startswith("app/cfg.py"), res)
rc, res, out = chk("sr", sr0, sr0, {"gitleaks": STUB_GITLEAKS}, ["--tools", "gitleaks"])
ok("really empty range stays NA", res and res["verdict"] == "NA", res)

# 7. bad --timeout is a clear UNVERIFIED, not a crash
for bad in ("abc", "0", "-5"):
    rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff", "--timeout", bad])
    ok("--timeout %s -> UNVERIFIED 'invalid --timeout' (not 'gate crashed')" % bad, rc == 0 and res and res["verdict"] == "UNVERIFIED" and "invalid --timeout" in res["summary"], res)
rc, res, out = gate(["baseline", "--repo", "lg", "--ref", b0, "--timeout", "abc"], tools=RT)
ok("baseline with bad --timeout -> UNVERIFIED invalid --timeout", res and "invalid --timeout" in res["summary"], res)

# 8. messages never carry source string literals / token-like runs (mypy embeds Literal['...'])
TOK2 = "gh" + "p_" + "Qw3rTy7uIo9pAs1dFg5hJk7lZx9cVb1nM3"
mkrepo("my", {"pkg/ok.py": "x = 1\n"})
m0_ = sha("my")
m1_ = commit("my", {"pkg/m.py": "x: int = 1\n"}, "new typed module")
rc, res, out = chk("my", m0_, m1_, {"mypy": STUB_MYPY}, ["--tools", "mypy", "--baseline", "none"], extra_env={"STUB_TOKEN": TOK2, "QA_SCANNERS_ADVISORY": ""})
ok("mypy message with an embedded Literal['token'] is redacted in the output", res and res["details"]["new"] and TOK2 not in out and TOK2[:10] not in out, out[:400])
rc, res, out = chk("my", m0_, m1_, {"mypy": STUB_MYPY}, ["--tools", "mypy", "--baseline", "none"], extra_env={"STUB_TOKEN": TOK2})
ok("same, advisory (default) path: advisory_new has no token", res and res["details"]["advisory_new"] and TOK2 not in out, out[:400])
rm_ = getattr(gs_mod, "redact_msg", lambda m, strings=False: m)
ok("redact_msg unit: token-like runs and quoted strings", TOK2 not in rm_("x " + TOK2) and "secretval" not in rm_("a 'secretval' b", strings=True))

# 9. scratch dirs are cleaned up even when a tool times out
tdir = tempfile.mkdtemp(prefix="tmpcheck-", dir=T)
rc, res, out = chk("lg", b0, h3, {"ruff": STUB_SLEEP, "gitleaks": STUB_GITLEAKS}, ["--tools", "ruff,gitleaks", "--timeout", "2"], extra_env={"TMPDIR": tdir})
ok("tool timeout leaves no qa-wt-*/qa-gl-* scratch dirs behind", res is not None and not [d for d in os.listdir(tdir) if d.startswith("qa-")], os.listdir(tdir))
rc, res, out = chk("lg", b0, h3, RT, ["--tools", "ruff"], extra_env={"TMPDIR": tdir})
ok("normal run leaves no scratch dirs behind", not [d for d in os.listdir(tdir) if d.startswith("qa-")], os.listdir(tdir))

print("== real-tool tests (box) ==")
sys.path.insert(0, os.path.join(OQ, "qa"))
import gate_scanners as gs  # noqa: E402
_op = os.environ.get("PATH", "")
os.environ["PATH"] = "/usr/bin:/bin:/usr/local/bin"   # same PATH the gate sees under env -i
have = {t: gs.find_tool(t) for t in ("ruff", "bandit", "semgrep", "gitleaks", "mypy")}
os.environ["PATH"] = _op
print("  tools found: " + ", ".join("%s=%s" % (k, "yes" if v else "no") for k, v in have.items()))

TOKEN = "gh" + "p_" + "aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bD1fH3jL5"   # assembled at runtime: never a literal in the repo
BAD = '''import subprocess
import os
import pickle
import requests


def run(cmd, blob, user):
    subprocess.run(cmd, shell=True)
    eval(cmd)
    pickle.loads(blob)
    requests.get("https://example.invalid", verify=False)
    cur.execute(f"SELECT * FROM users WHERE id = {user}")
    return undefined_name_here
'''
CLEAN = '''import subprocess


def run(cmd):
    subprocess.run(["ls", cmd], check=True)
    return len(cmd)
'''
mkrepo("rt", {"app/ok.py": CLEAN, "README.md": "hi\n"})
r0 = sha("rt")
r_clean = commit("rt", {"app/ok2.py": CLEAN}, "benign: clean new module")
r_bad = commit("rt", {"app/bad.py": BAD}, "seeded insecure module")
r_secret = commit("rt", {"app/cfg.py": "TOKEN_VALUE = '%s'\n" % TOKEN}, "seeded secret")
r_test_secret = commit("rt", {"tests/test_x.py": "FAKE = '%s'\n" % TOKEN.replace("aB3", "xY7")}, "fake token in a test file")
r_rules = {}

if have["ruff"] or have["bandit"] or have["semgrep"] or have["gitleaks"]:
    rc, res, out = chk("rt", r0, r_clean, None)
    ok("real tools: benign clean module -> PASS", rc == 0 and res["verdict"] == "PASS", res)
else:
    skip("real tools: benign clean module", "no scanner installed")

if have["semgrep"]:
    rc, res, out = chk("rt", r_clean, r_bad, None, ["--tools", "semgrep", "--baseline", "base"])
    rules = {n["rule"] for n in res["details"]["new"]}
    ok("semgrep negative control: seeded insecure module -> FAIL", res["verdict"] == "FAIL", res)
    ok("semgrep rules fire: shell-true, eval, pickle, verify=False, sql-fstring",
       {"qa-shell-true-nonliteral", "qa-eval-exec-nonliteral", "qa-unsafe-deserialization", "qa-tls-verify-disabled", "qa-sql-built-from-string"} <= rules, rules)
    rc, res, out = chk("rt", r0, r_clean, None, ["--tools", "semgrep"])
    ok("semgrep benign control: list-form subprocess + literal SQL params -> no findings", res["verdict"] == "PASS", res)
else:
    skip("semgrep negative/benign controls", "semgrep not installed")

if have["ruff"]:
    rc, res, out = chk("rt", r_clean, r_bad, None, ["--tools", "ruff", "--baseline", "base"])
    ok("ruff negative control: undefined name -> FAIL (F821 is blocking)", res["verdict"] == "FAIL" and any(n["rule"] == "F821" for n in res["details"]["new"]), res)
else:
    skip("ruff negative control", "ruff not installed")

if have["bandit"]:
    rc, res, out = chk("rt", r_clean, r_bad, None, ["--tools", "bandit", "--baseline", "base"])
    ok("bandit negative control: shell=True -> FAIL (B602 HIGH)", res["verdict"] == "FAIL" and any(n["rule"] == "B602" for n in res["details"]["new"]), res)
else:
    skip("bandit negative control", "bandit not installed")

if have["gitleaks"]:
    rc, res, out = chk("rt", r_bad, r_secret, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("gitleaks negative control: committed token in app code -> FAIL", res["verdict"] == "FAIL" and res["details"]["new"][0]["tool"] == "gitleaks", res)
    ok("gitleaks output NEVER contains the secret (rule id + file:line only)", TOKEN not in out and TOKEN[:12] not in out and TOKEN[-12:] not in out, "secret leaked into output")
    rc, res, out = chk("rt", r_secret, r_test_secret, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("gitleaks: fake token inside tests/ is listed as advisory and does not move the verdict -> PASS",
       res["verdict"] == "PASS" and any(a["tool"] == "gitleaks" for a in res["details"]["advisory_new"]), res)
    r_gen = commit("rt", {"app/gen.py": "x = 1  # k\napi_key = '%s'\n" % "zQ4wE8rT2yU6iO0pA3sD7fG1hJ5kL9xC"}, "generic key")
    rc, res, out = chk("rt", r_test_secret, r_gen, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("gitleaks: a generic-api-key style hit in app code never FAILs (FLAG or nothing)", res["verdict"] in ("FLAG", "PASS"), res)
else:
    skip("gitleaks negative control + redaction", "gitleaks not installed")

if have["mypy"]:
    m0 = commit("rt", {"pkg/m.py": "def f(x: int) -> int:\n    return x\n"}, "typed")
    m1 = commit("rt", {"pkg/m.py": "def f(x: int) -> int:\n    return 'a' + x\n"}, "type error")
    rc, res, out = chk("rt", m0, m1, None, ["--tools", "mypy", "--baseline", "base"], extra_env={"QA_SCANNERS_ADVISORY": ""})
    ok("mypy negative control: new type error is reported (non-advisory config) -> FLAG", res["verdict"] == "FLAG", res)
    rc, res, out = chk("rt", m0, m1, None, ["--tools", "mypy", "--baseline", "base"])
    ok("mypy is ADVISORY by default: new type error listed in details but verdict PASS", res["verdict"] == "PASS" and len(res["details"]["advisory_new"]) >= 1, res)
else:
    skip("mypy controls", "mypy not installed")

# --- review-fix regressions with the REAL tools (box) ---
SHELL_BAD = "import subprocess\n\n\ndef run(cmd):\n    subprocess.run(cmd, shell=True)%s\n"
mkrepo("rr", {"app/ok.py": CLEAN})
rr0 = sha("rr")
rr_sup = commit("rr", {"app/sup.py": SHELL_BAD % "  # nosec # nosemgrep # noqa"}, "suppressed shell=True")
rr_plain = commit("rr", {"app/plain.py": SHELL_BAD % ""}, "plain shell=True")
nu = dd = rr_plain
for tool in ("ruff", "bandit", "semgrep"):
    if have[tool]:
        rc, res, out = chk("rr", rr0, rr_sup, None, ["--tools", tool, "--baseline", "base"])
        ok("REAL %s: shell=True with nosec/nosemgrep/noqa comments still reported (suppression ignored)" % tool, res["verdict"] == ("FLAG" if tool == "ruff" else "FAIL"), res)
        nu = commit("rr", {"app/ünï/b_%s.py" % tool: SHELL_BAD % ""}, "non-ascii dir %s" % tool)
        rc, res, out = chk("rr", rr_plain, nu, None, ["--tools", tool, "--baseline", "base"])
        ok("REAL %s: bad code under a non-ASCII path is scanned and reported" % tool, res["verdict"] == ("FLAG" if tool == "ruff" else "FAIL") and "ünï" in json.dumps(res, ensure_ascii=False), res)
        dd = commit("rr", {"app/%s/m_%s.py" % (d, tool): SHELL_BAD % "" for d in ("env", "build", "vendor", "dist", "mocks")}, "bad code in ambiguous dir names %s" % tool)
        rc, res, out = chk("rr", nu, dd, None, ["--tools", tool, "--baseline", "base"])
        ok("REAL %s: bad code in app/{env,build,vendor,dist,mocks}/ is reported (was PASS)" % tool, res["verdict"] == ("FLAG" if tool == "ruff" else "FAIL"), res)
    else:
        skip("REAL %s review-fix regressions" % tool, "%s not installed" % tool)
if have["semgrep"]:
    rr_si = commit("rr", {".semgrepignore": "*\n", "app/si.py": SHELL_BAD % ""}, "repo .semgrepignore hides the new file")
    rc, res, out = chk("rr", dd, rr_si, None, ["--tools", "semgrep", "--baseline", "base"])
    ok("REAL semgrep: a committed .semgrepignore of '*' cannot hide a new bad file", res["verdict"] == "FAIL", res)
if have["gitleaks"]:
    T3 = "gh" + "p_" + "Zx9Cv7Bn5Mq3We1Rt8Yu6Io4Pl2Ka0Sd7Fg3"
    gl0 = sha("rr")
    gl1 = commit("rr", {"app/allow.py": "TOKEN_VALUE = '%s'  # gitleaks:allow\n" % T3}, "token with gitleaks:allow")
    rc, res, out = chk("rr", gl0, gl1, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("REAL gitleaks: '# gitleaks:allow' does not silence a provider token -> FAIL", res["verdict"] == "FAIL", res)
    ok("REAL gitleaks: token not in output", T3 not in out and T3[:12] not in out)
    T4 = TOKEN.replace("aB3", "cD4")
    gl2 = commit("rr", {".gitleaks.toml": '[extend]\nuseDefault = true\n[allowlist]\nregexes = ["ghp_[A-Za-z0-9]+"]\n', "app/al2.py": "TOKEN_VALUE = '%s'\n" % T4}, "repo allowlist config + token")
    rc, res, out = chk("rr", gl1, gl2, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("REAL gitleaks: a committed .gitleaks.toml allowlist does not silence the token -> FAIL", res["verdict"] == "FAIL", res)
    T5 = TOKEN.replace("aB3", "eF6")
    gl3 = commit("rr", {"app/gone.py": "TOKEN_VALUE = '%s'\n" % T5}, "token added")
    gl4 = commit("rr", {}, "token removed again", remove=["app/gone.py"])
    rc, res, out = chk("rr", gl2, gl4, None, ["--tools", "gitleaks", "--baseline", "base"])
    ok("REAL gitleaks: token committed then removed inside the range -> FAIL (was NA)", res["verdict"] == "FAIL", res)
if have["mypy"]:
    T6 = "gh" + "p_" + "Pl3Ok5Ij7Uh9Yg1Tf3Rd5Es7Aw9Qz1Xc3Vb"
    my0 = commit("rr", {"pkg/typed.py": "x: int = 1\n"}, "typed")
    my1 = commit("rr", {"pkg/lit.py": "from typing import Literal\ny: Literal['%s'] = 'x'\nz: int = y\n" % T6}, "literal in a mypy message")
    rc, res, out = chk("rr", my0, my1, None, ["--tools", "mypy", "--baseline", "base"], extra_env={"QA_SCANNERS_ADVISORY": ""})
    ok("REAL mypy: Literal['token'] in a mypy message never appears in output", T6 not in out and T6[:10] not in out, out[:300])

if have["semgrep"]:
    # per-rule seeded positives + benign negatives straight through the real semgrep with the shipped ruleset
    POS = {
        "qa-shell-true-nonliteral": "import subprocess\ndef f(c):\n    subprocess.run(c, shell=True)\n",
        "qa-shell-true-literal": "import subprocess\nsubprocess.run('ls', shell=True)\n",
        "qa-os-system-nonliteral": "import os\ndef f(c):\n    os.system('rm ' + c)\n",
        "qa-eval-exec-nonliteral": "def f(c):\n    exec(c)\n",
        "qa-unsafe-deserialization": "import yaml\ndef f(c):\n    return yaml.load(c)\n",
        "qa-tls-verify-disabled": "import requests\nrequests.post('https://x', verify=False)\n",
        "qa-hardcoded-secret": "api_token = 'Zk3pQ9vX2mL8nR5tY7wB4cD6'\n",
        "qa-sql-built-from-string": "def f(cur, u):\n    cur.execute('SELECT * FROM t WHERE a = %s' % u)\n",
        "qa-fastapi-write-route-no-auth": "from fastapi import APIRouter\nrouter = APIRouter()\n@router.post('/items')\nasync def make(item: dict):\n    return item\n",
        "qa-log-sensitive-value": "import logging\nlogger = logging.getLogger('x')\ndef f(api_key):\n    logger.info(f'using {api_key}')\n",
        "qa-except-swallows": "def f():\n    try:\n        g()\n    except Exception:\n        pass\n",
        "qa-mutable-default-arg": "def f(a, b=[]):\n    return b\n",
        "qa-js-eval": "eval(userInput);\n",
        "qa-js-innerhtml-assign": "el.innerHTML = userInput;\n",
    }
    NEG = {
        "qa-shell-true-nonliteral": "import subprocess\ndef f(c):\n    subprocess.run(['ls', c], check=True)\n",
        "qa-os-system-nonliteral": "import os\nos.system('true')\n",
        "qa-eval-exec-nonliteral": "import ast\ndef f(c):\n    return ast.literal_eval(c)\n",
        "qa-unsafe-deserialization": "import yaml\ndef f(c):\n    return yaml.safe_load(c)\n",
        "qa-tls-verify-disabled": "import requests\nrequests.post('https://x', verify=True)\n",
        "qa-hardcoded-secret": "import os\napi_token = os.environ['API_TOKEN']\nsecret_key = 'change-me-please-12345'\n",
        "qa-sql-built-from-string": "def f(cur, u):\n    cur.execute('SELECT * FROM t WHERE a = %s', (u,))\n",
        "qa-fastapi-write-route-no-auth": "from fastapi import APIRouter, Depends\nrouter = APIRouter()\n@router.post('/items')\nasync def make(item: dict, user=Depends(get_user)):\n    return item\n@router.delete('/x', dependencies=[Depends(get_user)])\nasync def rm():\n    return 1\n@router.post('/login')\nasync def login(item: dict):\n    return item\nsecured_router = APIRouter(prefix='/s', dependencies=[Depends(get_user)])\n@secured_router.post('/y')\nasync def y(item: dict):\n    return item\n",
        "qa-log-sensitive-value": "import logging\nlogger = logging.getLogger('x')\ndef f(api_key):\n    logger.info('key present: %s', bool(api_key))\n",
        "qa-except-swallows": "import logging\nlogger = logging.getLogger('x')\ndef f():\n    try:\n        g()\n    except Exception as e:\n        logger.error('boom %s', e)\n",
        "qa-mutable-default-arg": "def f(a, b=None):\n    return b or []\n",
        "qa-js-eval": "const x = JSON.parse(userInput);\n",
        "qa-js-innerhtml-assign": "el.textContent = userInput;\n",
    }
    sem = have["semgrep"]
    bad_rules = []
    for rule, code in POS.items():
        d = tempfile.mkdtemp(prefix="sg-pos-", dir=T)
        fn = "case.js" if rule.startswith("qa-js") else "case.py"
        open(os.path.join(d, fn), "w").write(code)
        st, found, note = gs.run_semgrep(d, [fn], 120, {})
        if st != "OK" or rule not in {f["rule"] for f in found}:
            bad_rules.append(("positive", rule, st, note[:80]))
    ok("semgrep ruleset: every one of %d rules fires on its seeded positive" % len(POS), not bad_rules, bad_rules)
    bad_neg = []
    for rule, code in NEG.items():
        d = tempfile.mkdtemp(prefix="sg-neg-", dir=T)
        fn = "case.js" if rule.startswith("qa-js") else "case.py"
        open(os.path.join(d, fn), "w").write(code)
        st, found, note = gs.run_semgrep(d, [fn], 120, {})
        if st != "OK" or rule in {f["rule"] for f in found}:
            bad_neg.append(("benign fired", rule, st, [f["rule"] for f in found]))
    ok("semgrep ruleset: no rule fires on its benign look-alike", not bad_neg, bad_neg)
    d = tempfile.mkdtemp(prefix="sg-test-", dir=T)
    os.makedirs(os.path.join(d, "tests"))
    open(os.path.join(d, "tests", "test_a.py"), "w").write(POS["qa-shell-true-nonliteral"])
    st, found, note = gs.run_semgrep(d, ["tests/test_a.py"], 120, {})
    ok("semgrep: findings in test files are excluded", st == "OK" and not found, (st, found))
    ok("semgrep ruleset file is valid YAML with the expected number of rules", open(RULES).read().count("\n  - id: ") == 14)
else:
    skip("per-rule semgrep positives/negatives", "semgrep not installed")

print("== severity classification (unit) ==")
fk = lambda tool, rule, file="app/x.py", sev="WARNING", **kw: dict(tool=tool, rule=rule, file=file, sev=sev, **kw)
ok("blocking: provider-specific gitleaks rule blocks, generic ones do not",
   gs.blocking(fk("gitleaks", "github-pat")) and not gs.blocking(fk("gitleaks", "generic-api-key")) and not gs.blocking(fk("gitleaks", "curl-auth-header")))
ok("advisory: gitleaks hits in tests/docs are advisory, in app code are not",
   gs.advisory(fk("gitleaks", "github-pat", "tests/t.py")) and gs.advisory(fk("gitleaks", "github-pat", "docs/a.md")) and not gs.advisory(fk("gitleaks", "github-pat")))
ok("blocking: semgrep ERROR yes / WARNING no; bandit HIGH yes / MEDIUM no; npm high yes / low no",
   gs.blocking(fk("semgrep", "r", sev="ERROR")) and not gs.blocking(fk("semgrep", "r")) and gs.blocking(fk("bandit", "B602", sev="HIGH", conf="HIGH"))
   and not gs.blocking(fk("bandit", "B314", sev="MEDIUM", conf="HIGH")) and gs.blocking(fk("npm-audit", "n", sev="HIGH")) and not gs.blocking(fk("npm-audit", "n", sev="LOW")))
print("== entry point hygiene ==")
rc, res, out = gate([], tools=RT)
ok("no subcommand prints usage, does not crash", "usage" in out.lower() and rc == 2, out[:200])
rc, res, out = gate(["check", "--repo", "lg", "--base", b0, "--head", h3, "--tools", "ruff"], tools=RT, rel=True)
ok("env -i with minimal PATH (no HOME-based PATH entries): runs", rc == 0 and res is not None, out)
ok("py_compile clean under this interpreter", subprocess.run([sys.executable, "-m", "py_compile", GATE]).returncode == 0)
py312 = shutil.which("python3.12") or ("/usr/bin/python3.12" if os.path.exists("/usr/bin/python3.12") else None)
if py312:
    ok("py_compile clean under python3.12", subprocess.run([py312, "-m", "py_compile", GATE]).returncode == 0)
else:
    skip("python3.12 compile", "python3.12 not on this machine")

shutil.rmtree(T, ignore_errors=True)
print("\nscanners tests: %d passed, %d failed, %d skipped" % (P, F, S))
sys.exit(1 if F else 0)
