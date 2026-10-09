#!/usr/bin/env python3
"""scripts/ovn_ruff_fix_executor.py: check/apply for `supply:unused-import` items. ruff F401 --fix, then PROOF (ast with imports stripped, non-import lines,
import statements only shrink, line count) or the file is restored byte-identical.

Two kinds of fixture: a repo whose .venv/bin/python is a thin wrapper around a python that has the REAL ruff (skipped explicitly, exit 0, when ruff is genuinely
absent and OVN_REQUIRE_TOOLS is unset), and a repo whose .venv/bin/python is a FAKE ruff that misbehaves on demand (rewrites another line, adds an import, explodes an
import, crashes half way, ...) - those need no ruff at all. Every refusal and every proof clause is also run against a mutant of the executor and must fail there."""
import ast
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
EXEC = os.path.join(SCRIPTS, "ovn_ruff_fix_executor.py")
SRC = open(EXEC, encoding="utf-8").read()
sys.path.insert(0, SCRIPTS)
import ovn_ruff_fix_executor as X  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def find_tools_py(mods):
    for c in (os.environ.get("OVN_TEST_TOOLS_PY"), sys.executable, os.path.expanduser("~/overnight-queue/repos/iptv_apps/iptv-backend/.venv/bin/python"),
              os.path.expanduser("~/aider-venv/bin/python")):
        if c and os.path.exists(c) and all(subprocess.run([c, "-m", m, "--version"], capture_output=True).returncode == 0 for m in mods):
            return c
    return None


TOOLS = find_tools_py(("ruff",))
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]

FAKE = '''#!%s
"""fake `python -m ruff ...` for the executor tests. FAKE_MODE picks the misbehaviour, FAKE_LOG records every argv, FAKE_REAL_PY is the real ruff python."""
import os
import sys

args = sys.argv[1:]
if os.environ.get("FAKE_LOG"):
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write(" ".join(args) + "\\n")
mode = os.environ.get("FAKE_MODE", "passthrough")
real = os.environ.get("FAKE_REAL_PY")
fix = "--fix" in args
path = args[-1]
if not fix:
    if mode == "passthrough_left":
        sys.exit(1)
    if mode == "passthrough" and real:
        os.execv(real, [real] + args)
    sys.exit(0)
src = open(path).read()
if mode in ("passthrough", "passthrough_left"):
    os.execv(real, [real] + args)
elif mode == "extra_line":            # removes the unused import AND rewrites another code line
    open(path, "w").write(src.replace("import os\\n", "").replace("x = 1", "x = 2"))
elif mode == "comment_line":          # removes the unused import AND edits a comment
    open(path, "w").write(src.replace("import os\\n", "").replace("# keep this comment", "# changed comment"))
elif mode == "semicolon_ast":         # changes code that shares a line with an import: invisible to a line comparison, visible to the ast
    open(path, "w").write(src.replace("x = 1", "x = 2"))
elif mode == "adds_import":           # swaps an import for a different one: same line count, same everything else
    open(path, "w").write(src.replace("import json", "import sys"))
elif mode == "explode":               # same names, but the import statement grows from 1 line to 4
    open(path, "w").write(src.replace("from typing import List, Dict", "from typing import (\\n    List,\\n    Dict,\\n)"))
elif mode == "syntax":
    open(path, "w").write("import (\\n")
elif mode == "crash":                 # half-written file and exit code 2
    open(path, "w").write("garbage")
    sys.exit(2)
elif mode == "noop":
    pass
sys.exit(0)
''' % sys.executable


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def mkrepo(files, fake=False):
    d = os.path.realpath(tempfile.mkdtemp(prefix="rfx-"))
    run(["git", "init", "-q"], cwd=d)
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, rp)) or d, exist_ok=True)
        with open(os.path.join(d, rp), "w") as f:
            f.write(body)
    run(["git", "add", "--"] + list(files), cwd=d)
    run(GIT + ["commit", "-q", "-m", "init"], cwd=d)
    vp = os.path.join(d, ".venv", "bin", "python")
    os.makedirs(os.path.dirname(vp))
    with open(vp, "w") as f:
        f.write(FAKE if fake else '#!/bin/sh\nexec "%s" "$@"\n' % (TOOLS or "/bin/false"))
    os.chmod(vp, 0o755)
    return d


def rd(d, rp):
    with open(os.path.join(d, rp), "rb") as f:
        return f.read()


def execute(script, op, repo, target, mode=None, log=None):
    env = dict(os.environ)
    env.pop("OVN_RUFF_PY", None)
    if mode:
        env["FAKE_MODE"] = mode
    if log:
        env["FAKE_LOG"] = log
    if TOOLS:
        env["FAKE_REAL_PY"] = TOOLS
    r = subprocess.run([sys.executable, script, op, repo, target], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout.strip()


def item(path, kind="unused-import"):
    return "- [ ] [T1] %s — Delete the unused import(s) from the import statement(s) in %s (ruff F401): `os`. VERIFY: `python3 -m ruff check --select F401 --no-cache %s`. (cat:python; multifile:no; supply:%s) [feat:demo-1-supply-x]" % (path, path, path, kind)


# ---------------------------------------------------------------- item parsing (in-process)
print("== item parsing")
ok("item_file: a plain supply line", X.item_file(item("iptv-backend/app/a.py")) == "iptv-backend/app/a.py")
ok("item_file: leading tags and a done prefix", X.item_file("- [x] (pre-verified: x) [AUTO-SKIP y] [T1] app/b.py — text") == "app/b.py"
   and X.item_file("- [ ] [AUTO-SKIP z] [T2] app/c.py — text") == "app/c.py")
ok("item_file: falls back to the last .py token of the VERIFY clause", X.item_file("- [ ] something odd VERIFY: `python3 -m ruff check --select F401 app/d.py`.") == "app/d.py")
ok("item_file: nothing to find", X.item_file("- [ ] [T1] no path here") is None)

# ---------------------------------------------------------------- refusals (no ruff needed: they happen before ruff runs)
BASE = {"app/a.py": "import os\nx = 1\n", "app/__init__.py": "import os\nfrom .a import x\n", "app/n.py": "import os  # noqa: F401\nimport json\nprint(json)\n",
        "app/n2.py": "import json\nimport os  # noqa\nprint(json)\n", "app/ok.py": "import os\nx = 1\n"}
_refusal_cache = {}


def refusal_results(script):
    if script in _refusal_cache:
        return _refusal_cache[script]
    repo = mkrepo(BASE, fake=True)
    with open(os.path.join(repo, "app", "untracked.py"), "w") as f:
        f.write("import os\nx = 1\n")
    with open(os.path.join(repo, "app", "ok.py"), "a") as f:      # uncommitted change: apply must refuse, the clone may be mid-edit
        f.write("y = 2\n")
    log = os.path.join(repo, "fake.log")
    res = {}

    def both(key, path, line=None, mode="noop", want_check="SKIP"):
        before = rd(repo, path) if os.path.exists(os.path.join(repo, path)) else b""
        c_rc, c_out = execute(script, "check", repo, line or item(path))
        a_rc, a_out = execute(script, "apply", repo, path, mode=mode, log=log)
        res[key] = c_out.startswith(want_check) and a_out.startswith("SKIP") and a_rc == 0 and (rd(repo, path) == before if before else True)
        return c_out, a_out
    both("init", "app/__init__.py")
    both("noqa", "app/n.py")
    both("noqa_other_import", "app/n2.py")
    both("untracked", "app/untracked.py")
    both("dirty", "app/ok.py", want_check="OK")        # check passes (it only looks at the item), apply refuses the dirty file
    _, c_out = execute(script, "check", repo, item("app/a.py", kind="missing-docstring"))
    res["not_supply"] = c_out.startswith("SKIP")
    _, c_out = execute(script, "check", repo, "- [ ] [T1] app/a.py — x (supply:unused-import)")
    res["good"] = c_out == "OK\tapp/a.py"
    _, c_out = execute(script, "check", repo, item("../escape.py"))
    res["escape"] = c_out.startswith("SKIP")
    _, c_out = execute(script, "check", repo, "- [ ] [T1] README — no python (supply:unused-import)")
    res["no_py"] = c_out.startswith("SKIP")
    res["no_ruff_call_on_refusals"] = not os.path.exists(log) or "--fix" not in open(log).read()
    _refusal_cache[script] = res
    return res


def mutant_script(old, new):
    assert SRC.count(old) == 1, (old, SRC.count(old))
    d = tempfile.mkdtemp(prefix="rfxmut-")
    p = os.path.join(d, "ovn_ruff_fix_executor.py")
    with open(p, "w") as f:
        f.write(SRC.replace(old, new))
    return p


def mut(label, chk, old, new):
    ok("%s (real executor)" % label, bool(chk(EXEC)))
    ok("MUTATION caught: %s" % label, not chk(mutant_script(old, new)))


print("== refusals")
mut("check/apply refuse an __init__.py (re-exports)", lambda s: refusal_results(s)["init"], 'if os.path.basename(rel) == "__init__.py":', "if False:")
mut("check/apply refuse a file with # noqa on an import line (the unused one)", lambda s: refusal_results(s)["noqa"], "    n = noqa_import_line(text)\n    if n:", "    n = None\n    if n:")
mut("... and when the noqa sits on a DIFFERENT import line of the same file", lambda s: refusal_results(s)["noqa_other_import"], "    n = noqa_import_line(text)\n    if n:", "    n = None\n    if n:")
mut("check/apply refuse an untracked file", lambda s: refusal_results(s)["untracked"], 'if _git(repo, "ls-files", "--error-unmatch", "--", rel).returncode != 0:', "if False:")
mut("apply refuses a file with uncommitted changes (byte-identical afterwards)", lambda s: refusal_results(s)["dirty"], "    if st.stdout.strip():", "    if False:")
mut("check only OKs supply:unused-import items", lambda s: refusal_results(s)["not_supply"], 'if "supply:unused-import" not in line:', "if False:")
ok("check OK for a tracked, plain file: `OK<TAB><file>`", refusal_results(EXEC)["good"])
ok("check SKIPs paths that escape the repo and items naming no .py file", refusal_results(EXEC)["escape"] and refusal_results(EXEC)["no_py"])
ok("refusals never reach ruff (no --fix call recorded)", refusal_results(EXEC)["no_ruff_call_on_refusals"])

# ---------------------------------------------------------------- the proof, with a misbehaving fake ruff (no real ruff needed)
FILES_PROOF = {
    "app/p.py": "import os\n# keep this comment\nimport json\nfrom typing import List, Dict\n\nx = 1\nprint(json, List, Dict)\n",
    "app/semi.py": "import os; x = 1\nprint(x)\n",
}


def proof_case(script, mode, path="app/p.py", op_target=None):
    repo = mkrepo(FILES_PROOF, fake=True)
    before = rd(repo, path)
    rc, out = execute(script, "apply", repo, op_target or path, mode=mode)
    after = rd(repo, path)
    status = run(["git", "status", "--porcelain", "--", path], cwd=repo).stdout.strip()
    return rc, out, before, after, status


def chk_fail_restored(mode, path="app/p.py"):
    def chk(script):
        rc, out, before, after, status = proof_case(script, mode, path)
        return rc == 1 and out.startswith("FAIL") and after == before and status == ""
    return chk


print("== the proof: a result that is not import-only is rejected and the file restored byte-identical")
ok("extra code line rewritten next to the import removal -> FAIL, restored byte-identical", chk_fail_restored("extra_line")(EXEC))
mut("a comment edited next to the import removal -> FAIL, restored (the non-import-lines clause)", chk_fail_restored("comment_line"), "    if _non_import_lines(before, ib) != _non_import_lines(after, ia):", "    if False:")
mut("code sharing a line with an import changed (invisible to the line comparison) -> FAIL (the ast clause)", chk_fail_restored("semicolon_ast", "app/semi.py"),
    "    if _stripped_dump(tb) != _stripped_dump(ta):", "    if False:")
mut("an import swapped for another one -> FAIL (the import-structure clause)", chk_fail_restored("adds_import"), "    if j != len(ia):", "    if False:")
mut("an import statement that grows (same names, more lines) -> FAIL (the line-count clause)", chk_fail_restored("explode"), "    if len(after.splitlines()) > len(before.splitlines()):", "    if False:")
ok("a result that does not parse -> FAIL, restored", chk_fail_restored("syntax")(EXEC))
mut("ruff crashing half way (garbage left in the file, rc 2) -> FAIL and the file is restored", chk_fail_restored("crash"), "            f.write(before_b)", "            pass")


def chk_noop(script):
    rc, out, before, after, status = proof_case(script, "noop")
    return rc == 0 and out.startswith("NOOP") and after == before and status == ""


ok("ruff changing nothing -> NOOP, exit 0, file untouched", chk_noop(EXEC))


def chk_argv(script):
    repo = mkrepo(FILES_PROOF, fake=True)
    log = os.path.join(repo, "argv.log")
    execute(script, "apply", repo, "app/p.py", mode="noop", log=log)
    first = open(log).read().split("\n")[0].split()
    return ("--fix" in first and "--unsafe-fixes" not in first and "--isolated" in first and "--select" in first and first[first.index("--select") + 1] == "F401"
            and first[-1] == "app/p.py" and "--no-cache" in first and "-m" in first and first[first.index("-m") + 1] == "ruff")


mut("ruff is run as `-m ruff check --select F401 --fix --isolated --no-cache <file>` and NEVER with --unsafe-fixes", chk_argv,
    'r = _ruff(py, repo, rel, "--fix")', 'r = _ruff(py, repo, rel, "--fix", "--unsafe-fixes")')


def chk_partial(script):
    repo = mkrepo(FILES_PROOF, fake=True)
    rc, out = execute(script, "apply", repo, "app/p.py", mode="passthrough_left")
    return TOOLS is None or (rc == 0 and out.startswith("PARTIAL") and b"import os" not in rd(repo, "app/p.py"))


# ---------------------------------------------------------------- with the REAL ruff
print("== real ruff")
if TOOLS is None:
    if os.environ.get("OVN_REQUIRE_TOOLS"):
        ok("real-ruff tests: ruff is required (OVN_REQUIRE_TOOLS set) but absent", False)
    else:
        print("  SKIP real-ruff tests (ruff is not available here; set OVN_REQUIRE_TOOLS=1 to make this a failure)")
else:
    def indep_stripped(text):
        """Independent of the module under test: ast dump with every Import/ImportFrom statement dropped, bodies compared."""
        t = ast.parse(text)
        for n in ast.walk(t):
            for fld in ("body", "orelse", "finalbody"):
                v = getattr(n, fld, None)
                if isinstance(v, list):
                    setattr(n, fld, [c for c in v if not isinstance(c, (ast.Import, ast.ImportFrom))])
        return ast.dump(t)

    GOOD = {
        "app/a.py": "import os\nimport json\nfrom typing import List, Dict\n\nx: Dict = {}\nprint(json)\n",
        "app/b.py": "import os, sys\nfrom typing import (\n    List,\n    Dict,\n)\n\nx: Dict = {}\nprint(sys.argv)\n",
        "app/c.py": "from __future__ import annotations\nimport os\n\n\ndef f():\n    return 1\n",
        "app/d.py": "import numpy as np\nimport json\n\nprint(json.dumps({}))\n",
        "app/e.py": "from . import sibling\nfrom .. import parent\nimport json\n\nprint(json)\n",
        "app/f.py": "import json  # used below\nimport re  # because reasons\n\nprint(json)\n",
        "app/g.py": "from typing import Any, Optional\n\n\ndef g(a: Optional[int]) -> int:\n    return a or 0\n",
        "app/h.py": "import asyncio\nimport logging\n\nlogger = logging.getLogger(__name__)\n",
        "app/i.py": "import os.path\nimport json\nfrom collections import OrderedDict, defaultdict\n\nd = defaultdict(list)\nprint(json, d)\n",
        "app/j.py": "import datetime\nimport time\nfrom dataclasses import dataclass, field\n\n\n@dataclass\nclass C:\n    n: int = 0\n",
    }
    repo = mkrepo(GOOD)
    results = []
    for rp in sorted(GOOD):
        before_t = GOOD[rp]
        rc, out = execute(EXEC, "apply", repo, item(rp))
        after_t = rd(repo, rp).decode()
        v = run([TOOLS, "-m", "ruff", "check", "--select", "F401", "--isolated", "--no-cache", rp], cwd=repo).returncode
        results.append((rp, rc == 0 and out.startswith("OK\t%s" % rp), indep_stripped(before_t) == indep_stripped(after_t), v == 0, len(after_t.splitlines()) <= len(before_t.splitlines()) and after_t != before_t))
    ok("10 files with unused imports: apply -> OK, the ast outside imports is untouched, the VERIFY (ruff F401, rc 0) is green, no file grew",
       all(all(r[1:]) for r in results), [r for r in results if not all(r[1:])])
    nums = run(["git", "diff", "--numstat"], cwd=repo).stdout.strip().split("\n")
    added = [l[1:] for l in run(["git", "diff", "-U0"], cwd=repo).stdout.split("\n") if l.startswith("+") and not l.startswith("+++")]
    ok("git diff touches exactly those 10 files; every ADDED line is an import statement (a shortened name list), everything else is a deletion",
       len(nums) == 10 and added and all(l.startswith(("from ", "import ")) for l in added), (nums, added))
    a_after = rd(repo, "app/a.py").decode()
    ok("app/a.py: exactly the unused names went (os, List) - json and Dict stay", a_after == "import json\nfrom typing import Dict\n\nx: Dict = {}\nprint(json)\n", a_after)
    # a real-world case ruff rewrites more than names: removing the only statement of an if-branch inserts `pass`
    repo2 = mkrepo({"app/cond.py": "import json\nif json:\n    import os\nelse:\n    import sys\n"})
    b4 = rd(repo2, "app/cond.py")
    rc, out = execute(EXEC, "apply", repo2, "app/cond.py")
    ok("ruff inserts `pass` where it removed a lone import: the proof rejects it (FAIL) and the file is restored byte-identical", rc == 1 and out.startswith("FAIL") and rd(repo2, "app/cond.py") == b4, out)
    repo3 = mkrepo({"app/s.py": "import os; x = 1\nprint(x)\n"})
    rc, out = execute(EXEC, "apply", repo3, "app/s.py")
    ok("the semicolon form `import os; x = 1` is refused by the proof (conservative) and restored", rc == 1 and out.startswith("FAIL") and rd(repo3, "app/s.py") == b"import os; x = 1\nprint(x)\n", out)
    mut("PARTIAL when ruff cannot fix everything with a safe fix (the safe part is kept)", chk_partial, '    return 0, "PARTIAL', '    return 0, "OK')

    def chk_only_f401(script):
        r = mkrepo({"app/q.py": "import os\n\nprint(f'hello')\n"})
        rc, out = execute(script, "apply", r, "app/q.py")
        return rc == 0 and out.startswith("OK") and rd(r, "app/q.py") == b"\nprint(f'hello')\n"
    mut("only F401 is fixed: another rule's safe fix (F541 here) in the same file never sneaks in", chk_only_f401, '"check", "--select", "F401"', '"check", "--select", "F401,F541"')

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
