#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_ad_lint_credit.py - ALREADY-DONE credit by evidence when the item's VERIFY is malformed (package q-already-done-credit, 2026-11-13). SHADOW by default.

Problem: the scout says ALREADY-DONE, the item's own VERIFY FAILS, ovn_credit_verify_gate refuses the credit, the item stays open and comes back (TAA 3f096a1a: 3 duplicate commits and 3 more
ALREADY-DONE verdicts; every refusal read "item's own VERIFY clause FAILED"). 2026-10-13 hand-checks (docs/SCOUT_REFUSAL_PARK_2026-10-13.md): the refused items were genuinely done and the VERIFY
unsatisfiable. The Q2 linter (ovn_verify_lint.py) already identifies the VERIFY shapes that cannot pass (PN1 / TS1 / TP1 / NEGGREP1 / ML1).

evaluate(item_line, repo_dir) -> {"decision": "credit" | "no", "reason", "rule", "evidence": [...]}
  credit only when ALL hold:
   1. the item has a VERIFY and the linter calls it SUSPECT with a rule in LINT_RULES (the VERIFY is malformed, not the code);
   2. the item is not a removal item (an absent string cannot be proven by a present-string check; NEGGREP1 therefore never credits a "remove X" item: it needs a scoped absence check, not built here);
   3. the item's own leading target file exists and EVERY target string the item asks for (ovn_already_done_gate.target_strings) is present in it, there is at least one such string, AND at
      least one SPECIFIC after-state snippet (a backticked code span with a space/operator/call, e.g. `error = result.get('error') or ''`; for Change/Replace items the new value, the LAST span)
      is present verbatim (whitespace- and quote-style-normalised). Bare identifiers alone are never evidence: the first replay credited an item on the identifiers `error` and a function name.
   4. every Python test file the item or its VERIFY names that exists in the repo passes a scoped pytest run (run_tests=True; a test file that cannot be run or fails = no credit).
  Anything else is "no" with the reason; never raises.

Mode (OVN_ALREADY_DONE_CREDIT): off | shadow (default: log 'would-credit already-done-lint-verified', never tick) | enforce (the caller ticks '(already-done, lint-verified)').
Journal: state/already_done_credit_shadow.log (one JSON line per evaluation).

CLI: ovn_ad_lint_credit.py <progress_file> <line_number> <repo_dir> [state_dir]   -> '<credit|no> <rule> <reason>'
     ovn_ad_lint_credit.py replay-item '<item line>' <repo_dir>               -> JSON (no log write)
"""
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "scripts"))

LINT_RULES = ("PN1", "TS1", "TP1", "NEGGREP1", "ML1")
REMOVAL = re.compile(r"(?i)\b(remove|removes|removing|delete|deletes|deleting|drop|drops|dropping|strip|stripping|eliminate|get rid of|no longer)\b")
TEST_PATH = re.compile(r"[A-Za-z0-9_./-]*(?:tests?/[A-Za-z0-9_./-]+|test_[A-Za-z0-9_]+|[A-Za-z0-9_]+_test)\.py")


SPAN = re.compile(r"`([^`\n]{6,200})`")
CHANGE = re.compile(r"(?i)^(change|rename|replace|set|switch|update|convert)\b")


def _norm(t):
    return re.sub(r"\s+", " ", t.replace('"', "'")).strip()


def after_snippets(item_line):
    """specific backticked code spans of the item description (outside the VERIFY clause); for a Change/Replace item only the last span (the new value)."""
    import ovn_already_done_gate as adg
    desc = adg.description(item_line)
    spans = [m.group(1) for m in SPAN.finditer(desc) if re.search(r"[\s(=.\[]", m.group(1)) and not m.group(1).endswith((".py", ".ts", ".vue", ".gd"))]
    if spans and CHANGE.search(desc.lstrip(" -—–:")):
        spans = spans[-1:]
    return spans

SCOPE_REF = re.compile(r"(?i)\b(?:in|inside|within|function|method|class|def|func)\s+(?:the\s+)?(?:(?:function|method|class)\s+)?`([A-Za-z_][\w.$]*)(?:\(\))?`")
CALL_SPAN = re.compile(r"`([A-Za-z_][\w.$]*)\(\)`")


def strip_comments_py(text):
    """Python source with comments and docstrings blanked (same line structure); None when it cannot be parsed (fail closed)."""
    import ast
    import io
    import tokenize
    try:
        tree = ast.parse(text)
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (SyntaxError, ValueError, tokenize.TokenError, RecursionError):
        return None
    lines = text.split("\n")
    mask = [[False] * len(l) for l in lines]

    def blank(r0, c0, r1, c1):
        for r in range(r0, r1 + 1):
            row = mask[r - 1]
            a = c0 if r == r0 else 0
            b = c1 if r == r1 else len(row)
            for c in range(a, min(b, len(row))):
                row[c] = True
    for t in toks:
        if t.type == tokenize.COMMENT:
            blank(t.start[0], t.start[1], t.end[0], t.end[1])
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            b = node.body
            if b and isinstance(b[0], ast.Expr) and isinstance(getattr(b[0], "value", None), ast.Constant) and isinstance(b[0].value.value, str):
                e = b[0]
                # ast col offsets are utf-8 byte offsets: only whole-line docstrings are blanked by column, others by their full lines
                blank(e.lineno, 0, e.end_lineno, len(lines[e.end_lineno - 1]))
    return "\n".join("".join(" " if m else ch for ch, m in zip(l, mk)) for l, mk in zip(lines, mask))


def strip_comments_generic(text):
    """conservative `//`, `/* */` and `#` comment removal that respects ' " ` string literals (a comment marker inside a string is kept). Newlines are preserved. Over-stripping only loses evidence."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if c in "'\"`":
            q = c
            j = i + 1
            while j < n and text[j] != q and not (text[j] == "\n" and q != "`"):
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif two == "//" or c == "#":
            j = text.find("\n", i)
            j = n if j < 0 else j
            i = j
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" if ch == "\n" else " " for ch in text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def strip_comments(path, text):
    """-> comment/docstring-free text or None (cannot determine: fail closed)."""
    if path.endswith(".py"):
        return strip_comments_py(text)
    try:
        return strip_comments_generic(text)
    except Exception:
        return None


def scope_names(desc):
    """function/method/class names the item scopes its change to ('in `helper`', 'the `foo()` function'); only names the text explicitly scopes by."""
    out = []
    for rx in (SCOPE_REF, CALL_SPAN):
        for m in rx.finditer(desc):
            nm = m.group(1)
            if nm not in out:
                out.append(nm)
    return out


def _py_scope_body(stripped, name):
    import ast
    try:
        tree = ast.parse(stripped)
    except (SyntaxError, ValueError, RecursionError):
        return None
    parts = name.split(".")
    found = []

    def walk(body, prefix):
        for node in body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                qual = prefix + [node.name]
                if qual[-len(parts):] == parts:
                    found.append(node)
                walk(node.body, qual)
    walk(tree.body, [])
    if not found:
        return None
    lines = stripped.split("\n")
    return "\n".join("\n".join(lines[n.lineno - 1:n.end_lineno]) for n in found)


def _generic_scope_body(stripped, name, ext):
    nm = re.escape(name.split(".")[-1])
    pats = [r"\b(?:function\*?|func|def|fn|class|interface|struct|impl)\s+%s\b" % nm,
            r"\b(?:const|let|var|val)\s+%s\s*(?::[^=\n]+)?=\s*(?:async\s*)?(?:\(|function|[A-Za-z_$][\w$]*\s*=>)" % nm,
            r"(?m)^[ \t]*(?:(?:public|private|protected|static|async|override|export|final|abstract|get|set)\s+)*%s\s*\([^)\n]*\)\s*(?::[^{\n]+)?\{" % nm]
    m = None
    for p in pats:
        m = re.search(p, stripped)
        if m:
            break
    if not m:
        return None
    if ext in (".gd", ".py"):                     # indentation-scoped: the following lines more indented than the def line
        ls = stripped.rfind("\n", 0, m.start()) + 1
        head = stripped[ls:m.start()]
        base = len(head) - len(head.lstrip())
        lines = stripped[ls:].split("\n")
        body = [lines[0]]
        for l in lines[1:]:
            if l.strip() and (len(l) - len(l.lstrip())) <= base:
                break
            body.append(l)
        return "\n".join(body)
    k = stripped.find("{", m.end() - (1 if stripped[m.end() - 1:m.end()] == "{" else 0))
    if k < 0:
        return None
    depth = 0
    for j in range(k, len(stripped)):
        if stripped[j] == "{":
            depth += 1
        elif stripped[j] == "}":
            depth -= 1
            if depth == 0:
                return stripped[m.start():j + 1]
    return None                                    # unbalanced: cannot determine


def scoped_text(path, stripped, names):
    """text of the named function/method/class bodies (union); None when any named scope cannot be located (fail closed)."""
    ext = os.path.splitext(path)[1]
    bodies = []
    for nm in names:
        b = _py_scope_body(stripped, nm) if ext == ".py" else _generic_scope_body(stripped, nm, ext)
        if b is None:
            return None
        bodies.append(b)
    return "\n".join(bodies)


PASSED = re.compile(r"(?m)\b(\d+) passed\b")


def mode():
    m = os.environ.get("OVN_ALREADY_DONE_CREDIT", "shadow")
    return m if m in ("off", "shadow", "enforce") else "shadow"


def _no(reason, rule="", evidence=()):
    return {"decision": "no", "reason": reason, "rule": rule, "evidence": list(evidence)}


def _find_file(repo_dir, rel):
    p = os.path.join(repo_dir, rel)
    if os.path.isfile(p):
        return p
    base = os.path.basename(rel)
    for root, dirs, files in os.walk(repo_dir):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv", "__pycache__", ".godot")]
        if base in files and os.path.join(root, base).endswith(rel.strip("./")):
            return os.path.join(root, base)
    return None


BARE_TEST = re.compile(r"(?<![\w/.:])(test_[A-Za-z0-9_]+)(?![\w/]|\.py)")
NODE_SUFFIX = re.compile(r"::([A-Za-z0-9_:\[\]\-.]+)")
KEXPR = re.compile(r"""(?:^|\s)-k\s+(?:"([^"]+)"|'([^']+)'|(\S+))""")


def _named_tests(item_line, repo_dir):
    """-> (specs, bare): specs = [(abs test file, node id suffix or None)] for every existing python test file the item / VERIFY names (repo-relative resolution, unique suffix match; an explicit
    'file::test_name' keeps its node id); bare = test_xxx names the text mentions outside any path (the item may be asking to ADD them: they must exist in a named file)."""
    specs = []
    for m in TEST_PATH.finditer(item_line):
        rel = m.group(0).lstrip("./")
        p = _find_file(repo_dir, rel)
        if not p:
            continue
        sm = NODE_SUFFIX.match(item_line, m.end())
        node = sm.group(1).rstrip(".") if sm else None
        if (p, node) not in specs:
            specs.append((p, node))
    bare = []
    for m in BARE_TEST.finditer(item_line):
        if m.group(1) not in bare:
            bare.append(m.group(1))
    return specs, bare


def _run_pytest(path, repo_dir, timeout, node=None, kexpr=None):
    """run the named test (file, file::node, or file -k expr). -> (ok, why). ok only when pytest exits 0 AND its summary reports >= 1 passed (a not-found node, 'no tests ran', an
    all-skipped / all-deselected file are NOT a pass)."""
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", NTFY_SERVER="http://127.0.0.1:9", OVN_NOTIFY_DISABLE="1")
    cwd = repo_dir
    d = os.path.dirname(path)
    while d.startswith(repo_dir) and d != repo_dir:     # run from the nearest ancestor that looks like a python project root (conftest / pytest.ini / pyproject)
        if any(os.path.exists(os.path.join(d, f)) for f in ("pytest.ini", "pyproject.toml", "conftest.py", "setup.cfg")):
            cwd = d
            break
        d = os.path.dirname(d)
    py = sys.executable
    d = os.path.dirname(path)
    while d.startswith(repo_dir):            # the repo's own interpreter (the global python has no pytest on the box): nearest .venv/bin/python up to the repo root
        for v in (".venv", "venv"):
            cand = os.path.join(d, v, "bin", "python")
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                py = cand
                break
        else:
            if d == repo_dir:
                break
            d = os.path.dirname(d)
            continue
        break
    target = path + ("::" + node if node else "")
    cmd = [py, "-m", "pytest", "-q", "-x", "-p", "no:cacheprovider"] + (["-k", kexpr] if kexpr else []) + [target]
    try:
        r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout)
        out = (r.stderr + r.stdout).decode("utf-8", "replace")
        if r.returncode != 0 and "No module named pytest" in out:
            return False, "pytest-unavailable"
        if r.returncode != 0:
            return False, "rc=%d" % r.returncode
        pm = PASSED.search(out)
        if not pm or int(pm.group(1)) < 1 or "no tests ran" in out:
            return False, "no-passed-test(rc=0)"
        return True, "rc=0 passed=%s" % pm.group(1)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except Exception as e:  # pragma: no cover
        return False, "error:%s" % type(e).__name__


def _defines_test(path, name):
    try:
        return re.search(r"(?m)^\s*(?:async\s+)?def\s+%s\b" % re.escape(name), open(path, errors="replace").read()) is not None
    except OSError:
        return False


def evaluate(item_line, repo_dir, state_dir=None, run_tests=True, timeout=60):
    try:
        import ovn_verify_lint as vl
        import ovn_already_done_gate as adg
        import ovn_path_gate as pg
        if not adg.has_verify(item_line):
            return _no("no-verify: nothing to call malformed")
        lint = vl.lint_verify(item_line, repo_dir, state_dir)
        if lint.get("verdict") != vl.SUSPECT or lint.get("rule") not in LINT_RULES:
            return _no("verify-not-malformed: lint verdict %s %s" % (lint.get("verdict"), lint.get("rule", "")))
        rule = lint["rule"]
        desc = adg.description(item_line)
        if REMOVAL.search(desc) or REMOVAL.search(pg.leading_body(item_line).split("VERIFY:")[0]):
            return _no("removal-item: a present-string check cannot prove absence (needs a scoped absence check)", rule)
        tgt = pg.leading_target(item_line)
        if not tgt or not tgt.endswith(pg.CODE):
            return _no("no-target-file: the item names no leading source file", rule)
        path = _find_file(repo_dir, tgt)
        if not path:
            return _no("target-missing: %s is not in the repo" % tgt, rule)
        strings = adg.target_strings(item_line)
        if not strings:
            return _no("no-target-string: nothing concrete to prove present in %s" % tgt, rule)
        try:
            raw = open(path, errors="replace").read()
        except OSError:
            return _no("target-unreadable: %s" % tgt, rule)
        text = strip_comments(path, raw)               # evidence must be CODE: comments and docstrings never count
        if text is None:
            return _no("cannot-strip-comments: %s could not be parsed, so code vs comment is unknown" % tgt, rule)
        missing = [s for s in strings if s not in text]
        if missing:
            return _no("string-missing: %s absent from %s" % (", ".join(missing), tgt), rule)
        snips = after_snippets(item_line)
        names = scope_names(desc)
        if names:                                      # the item scopes the change to a function/method/class: the evidence must sit inside it
            scoped = scoped_text(path, text, names)
            if scoped is None:
                return _no("scope-undetermined: %s not located as a function/method/class in %s" % (", ".join(names), tgt), rule)
            evtext = scoped
        else:
            evtext = text
        if not snips:
            return _no("weak-evidence: no specific code snippet in the item to prove present (identifiers alone are not evidence)", rule)
        nt = _norm(evtext)
        miss = [x for x in snips if _norm(x) not in nt]
        if miss:
            return _no("snippet-missing: %s absent from %s%s" % (" | ".join(miss)[:160], tgt, " (scope %s, comments/docstrings ignored)" % ",".join(names) if names else " (comments/docstrings ignored)"), rule)
        ev = ["lint=%s" % rule, "target=%s" % tgt, "strings-present=%s" % ",".join(strings), "snippets-present=%s" % " | ".join(snips)[:160]]
        if names:
            ev.append("scope=%s" % ",".join(names))
        specs, bare = _named_tests(item_line, repo_dir)
        files = [p for p, _ in specs]
        for b in bare:                                 # a test name the text mentions must exist in a named test file (the item may be asking to add it)
            if not any(_defines_test(p, b) for p in files):
                return _no("named-test-missing: %s is not defined in %s" % (b, ", ".join(os.path.relpath(p, repo_dir) for p in files) or "any named test file"), rule, ev)
        runs = []                                      # (file, node, kexpr)
        for p, node in specs:
            if node:
                if not _defines_test(p, node.split("::")[-1].split("[")[0]):
                    return _no("named-test-missing: %s is not defined in %s" % (node, os.path.relpath(p, repo_dir)), rule, ev)
                runs.append((p, node, None))
        for b in bare:
            for p in files:
                if _defines_test(p, b):
                    runs.append((p, None, b))
                    break
        if not runs:                                   # no node id / name anywhere: the whole named file(s)
            runs = [(p, None, None) for p in files]
        km = KEXPR.search(item_line)
        for p, node, kx in runs:
            rel = os.path.relpath(p, repo_dir) + ("::" + node if node else "") + (" -k " + kx if kx else "")
            if run_tests == "skip":                # replay on a repo the caller must not run tests in: note the test, do not reject on it
                ev.append("test-skipped=%s" % rel)
                continue
            if not run_tests:
                ev.append("test-not-run=%s" % rel)
                return _no("test-not-run: %s exists but run_tests is off" % rel, rule, ev)
            if not node and not kx and km:
                kx = next(g for g in km.groups() if g)
            ok, why = _run_pytest(p, repo_dir, timeout, node, kx)
            ev.append("test=%s:%s" % (rel, why))
            if not ok:
                return _no("test-failed: %s (%s)" % (rel, why), rule, ev)
        tests = runs
        return {"decision": "credit", "reason": "VERIFY malformed (%s); target string(s) present in %s%s" % (lint.get("reason", "")[:120], tgt, "; named test(s) pass" if tests else ""), "rule": rule, "evidence": ev}
    except Exception as e:   # a bug here must never leak into the queue
        return _no("error:%s" % type(e).__name__)


def rotate_log(path, max_bytes=2 * 1024 * 1024, keep=5000):
    """at >= max_bytes keep the last `keep` lines; atomic (temp file in the same dir + os.replace). Never raises."""
    try:
        if os.path.getsize(path) < max_bytes:
            return
        with open(path, "rb") as f:
            lines = f.read().split(b"\n")
        if lines and lines[-1] == b"":
            lines.pop()
        tmp = "%s.rot.%d" % (path, os.getpid())
        with open(tmp, "wb") as f:
            f.write(b"\n".join(lines[-keep:]) + b"\n")
        os.replace(tmp, path)
    except Exception:
        pass


def journal(state_dir, repo, item_line, res, m):
    try:
        import hashlib
        os.makedirs(state_dir, exist_ok=True)
        row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": repo, "mode": m, "decision": res["decision"], "rule": res["rule"], "reason": res["reason"][:300],
               "evidence": res["evidence"], "item": hashlib.md5(re.sub(r"^- \[[ xX]\] ", "", item_line).encode("utf-8", "replace")).hexdigest(),
               "line": item_line.strip()[:200]}
        lp = os.path.join(state_dir, "already_done_credit_shadow.log")
        with open(lp, "a") as f:
            f.write(json.dumps(row) + "\n")
        rotate_log(lp)
    except Exception:
        pass


def main(argv):
    if len(argv) >= 4 and argv[1] == "replay-item":
        print(json.dumps(evaluate(argv[2], argv[3])))
        return 0
    if len(argv) < 4:
        print(__doc__)
        return 2
    prog, ln, repo = argv[1], argv[2], argv[3]
    state = argv[4] if len(argv) > 4 else os.environ.get("OVN_STATE_DIR") or os.path.join(HERE, "state")
    m = mode()
    if m == "off":
        print("no off mode-off")
        return 0
    try:
        line = open(prog, errors="replace").read().split("\n")[int(ln) - 1]
    except (OSError, IndexError, ValueError):
        print("no - unreadable-item-line")
        return 0
    res = evaluate(line, repo, state, run_tests=os.environ.get("OVN_ALREADY_DONE_CREDIT_RUN_TESTS", "on") != "off", timeout=int(os.environ.get("OVN_ALREADY_DONE_CREDIT_TEST_TIMEOUT", "60") or 60))
    journal(state, os.path.basename(os.path.abspath(repo)), line, res, m)
    print("%s %s %s" % (res["decision"], res["rule"] or "-", res["reason"].replace("\n", " ")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
