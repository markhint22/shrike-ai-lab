#!/usr/bin/env python3
"""scripts/ovn_ruff_fix_executor.py - the harness-applied fixer for `supply:unused-import` items (2026-10-09): ruff removes the names, no model cycle is spent.

Why: an unused-import item is the most mechanical edit there is, and the model still burned cycles on it (5 NEEDS-DECISION scout cycles when the old wording read as
'delete the file'). ruff F401 --fix does it exactly; this wrapper only decides WHEN it may run and PROVES that nothing but import names changed.

usage:
  ovn_ruff_fix_executor.py check <repo_dir> "<item line>"   -> `OK<TAB><file>` or `SKIP<TAB><why>` (exit 0)
  ovn_ruff_fix_executor.py apply <repo_dir> <file | item line>
        -> `OK<TAB><file><TAB>removed N line(s)`          the file changed, the proof held, F401 is clean (exit 0)
           `PARTIAL<TAB><file><TAB>...`                   the proof held but ruff could not fix every finding with a SAFE fix; the rest is left for a model/human (exit 0)
           `NOOP<TAB><file><TAB>...`                      ruff changed nothing (exit 0)
           `SKIP<TAB><why>`                               refused before touching anything (exit 0)
           `FAIL<TAB><why>`                               ruff crashed or the proof failed: the file is restored byte-identical (exit 1)
Never commits, never stages, never uses --unsafe-fixes.

`check` says OK only for an item containing `supply:unused-import`, naming a TRACKED .py file that is not an __init__.py (re-exports), with no `# noqa` on any of its
import lines. `apply` re-checks all of that, refuses a file with uncommitted changes (the live clone may be mid-edit), runs
`<venv python> -m ruff check --select F401 --fix --isolated --no-cache <file>` and then proves, from the before/after text:
  1. the ast of the file with EVERY Import/ImportFrom node stripped is identical before and after (nothing but imports changed),
  2. the lines outside import statements are identical (comments, blank lines, formatting),
  3. every remaining import statement is an earlier one with a subset of its names (nothing added, renamed or re-ordered),
  4. the line count did not grow.
A failed proof restores the file from the bytes read before ruff ran (not `git checkout`: that would also throw away uncommitted work, and apply refuses such files anyway).
HOOK CONTRACT (run_overnight.sh's RUFF-EXECUTOR hook): the proof above shows only that imports were removed and F401 is clean - it does NOT show that the program still behaves the
same (an import kept for its side effect, e.g. an ORM model import that registers a mapper, or an unmarked re-export, is "unused" to ruff). So the hook MUST commit-then-gate:
commit the change, run the item's VERIFY AND the repo's build/test gate (the same one a model edit has to pass), and revert the commit when either is red. Never accept an
executor edit on the strength of this script's OK alone.
env: OVN_RUFF_PY overrides the repo's venv python (tests)."""
import ast
import copy
import os
import re
import subprocess
import sys


def _venv_python(repo):
    env = os.environ.get("OVN_RUFF_PY")
    if env and os.path.exists(env):
        return env
    for cand in ("iptv-backend/.venv/bin/python", ".venv/bin/python", "backend/.venv/bin/python"):
        p = os.path.join(repo, cand)
        if os.path.exists(p):
            return p
    return None


def item_file(line):
    """The .py path an item names: `- [ ] [T1] <path> — ...` (any number of leading [tags]), else the last .py token of its VERIFY clause."""
    m = re.match(r"^\s*- \[[ xX]\]\s+(?:\([^)]*\)\s*)?(?:\[[^\]]*\]\s*)*(\S+?\.py)(?=\s|$)", line)
    if m:
        return m.group(1)
    v = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if v:
        toks = [t for t in v.group(1).split() if t.endswith(".py")]
        if toks:
            return toks[-1]
    return None


def _git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)


def noqa_import_line(text):
    """First 1-based line of an import statement carrying `# noqa`, else None. None as well when the file does not parse (the caller reports that separately)."""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return None
    lines = text.split("\n")
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            for ln in range(node.lineno, (node.end_lineno or node.lineno) + 1):
                if re.search(r"#\s*noqa", lines[ln - 1], re.I):
                    return ln
    return None


def eligible(repo, line_or_file):
    """(file, None) when the executor may touch it, else (None, why)."""
    rel = item_file(line_or_file) if (" " in line_or_file.strip() or line_or_file.lstrip().startswith("-")) else line_or_file
    if not rel:
        return None, "no .py file named in the item"
    if os.path.isabs(rel) or ".." in rel.split("/"):
        return None, "path outside the repo: %s" % rel
    if os.path.basename(rel) == "__init__.py":
        return None, "%s is an __init__.py (re-exports are never auto-removed)" % rel
    if not rel.endswith(".py"):
        return None, "%s is not a python file" % rel
    if _git(repo, "ls-files", "--error-unmatch", "--", rel).returncode != 0:
        return None, "%s is not a tracked file" % rel
    full = os.path.join(repo, rel)
    if not os.path.isfile(full):
        return None, "%s does not exist" % rel
    try:
        with open(full, encoding="utf-8") as f:
            text = f.read()
        ast.parse(text)
    except (OSError, UnicodeDecodeError, SyntaxError) as e:
        return None, "%s cannot be parsed (%s)" % (rel, type(e).__name__)
    n = noqa_import_line(text)
    if n:
        return None, "noqa on import line %d of %s" % (n, rel)
    return rel, None


def check(repo, line):
    if "supply:unused-import" not in line:
        return "SKIP\tnot a supply:unused-import item"
    rel, why = eligible(repo, line)
    return ("OK\t%s" % rel) if rel else ("SKIP\t%s" % why)


# ---------------------------------------------------------------- the proof
class _StripImports(ast.NodeTransformer):
    def generic_visit(self, node):
        for fld in ("body", "orelse", "finalbody"):
            v = getattr(node, fld, None)
            if isinstance(v, list):
                setattr(node, fld, [n for n in v if not isinstance(n, (ast.Import, ast.ImportFrom))])
        return super().generic_visit(node)


def _stripped_dump(tree):
    return ast.dump(_StripImports().visit(copy.deepcopy(tree)))


def _imports(tree):
    out = []
    for n in sorted((x for x in ast.walk(tree) if isinstance(x, (ast.Import, ast.ImportFrom))), key=lambda x: (x.lineno, x.col_offset)):
        names = tuple((a.name, a.asname) for a in n.names)
        out.append((type(n).__name__, getattr(n, "module", None), getattr(n, "level", 0), names, n.lineno, n.end_lineno or n.lineno))
    return out


def _non_import_lines(text, imps):
    skip = set()
    for *_, a, b in imps:
        skip.update(range(a, b + 1))
    return [l for i, l in enumerate(text.split("\n"), 1) if i not in skip]


def prove_import_only(before, after):
    """(True, removed_line_count) when `after` differs from `before` only by removed import names/statements, else (False, why)."""
    try:
        tb, ta = ast.parse(before), ast.parse(after)
    except SyntaxError as e:
        return False, "the result does not parse: %s" % e
    if len(after.splitlines()) > len(before.splitlines()):
        return False, "the line count grew"
    if _stripped_dump(tb) != _stripped_dump(ta):
        return False, "code outside import statements changed (ast with imports stripped differs)"
    ib, ia = _imports(tb), _imports(ta)
    if _non_import_lines(before, ib) != _non_import_lines(after, ia):
        return False, "lines outside import statements changed"
    j = 0
    for kind, mod, lvl, names, *_ in ib:
        if j < len(ia):
            k2, m2, l2, n2, *_ = ia[j]
            if (k2, m2, l2) == (kind, mod, lvl) and n2 and _is_subsequence(n2, names):
                j += 1
    if j != len(ia):
        return False, "an import statement was added, renamed or re-ordered"
    return True, len(before.splitlines()) - len(after.splitlines())


def _is_subsequence(small, big):
    it = iter(big)
    return all(any(x == y for y in it) for x in small)


def _ruff(py, repo, rel, *extra):
    return subprocess.run([py, "-m", "ruff", "check", "--select", "F401"] + list(extra) + ["--isolated", "--no-cache", rel], cwd=repo, capture_output=True, text=True, timeout=120)


def apply(repo, target):
    rel, why = eligible(repo, target)
    if not rel:
        return 0, "SKIP\t%s" % why
    st = _git(repo, "status", "--porcelain", "--", rel)
    if st.stdout.strip():
        return 0, "SKIP\t%s has uncommitted changes (the clone may be mid-edit)" % rel
    py = _venv_python(repo)
    if not py:
        return 1, "FAIL\tno venv python with ruff found in %s" % repo
    full = os.path.join(repo, rel)
    with open(full, "rb") as f:
        before_b = f.read()
    try:
        before = before_b.decode("utf-8")
    except UnicodeDecodeError:
        return 0, "SKIP\t%s is not valid utf-8" % rel

    def restore():
        with open(full, "wb") as f:
            f.write(before_b)

    try:
        r = _ruff(py, repo, rel, "--fix")   # safe fixes only: --unsafe-fixes is never passed
    except Exception as e:
        restore()
        return 1, "FAIL\truff could not run (%s: %s); file restored" % (type(e).__name__, e)
    if r.returncode not in (0, 1):
        restore()
        return 1, "FAIL\truff exited %d (%s); file restored" % (r.returncode, (r.stderr or r.stdout).strip().split("\n")[-1][:120])
    with open(full, "rb") as f:
        after_b = f.read()
    if after_b == before_b:
        left = _ruff(py, repo, rel)
        return 0, "NOOP\t%s\truff made no safe fix%s" % (rel, "" if left.returncode == 0 else " (F401 findings remain: they need a manual edit)")
    try:
        after = after_b.decode("utf-8")
    except UnicodeDecodeError:
        restore()
        return 1, "FAIL\tthe result is not valid utf-8; file restored"
    okp, info = prove_import_only(before, after)
    if not okp:
        restore()
        return 1, "FAIL\t%s: %s; file restored" % (rel, info)
    left = _ruff(py, repo, rel)
    if left.returncode == 0:
        return 0, "OK\t%s\tremoved %d line(s)" % (rel, info)
    return 0, "PARTIAL\t%s\tremoved %d line(s); F401 findings remain (no safe fix for them)" % (rel, info)


def main(argv):
    if len(argv) != 4 or argv[1] not in ("check", "apply"):
        print("usage: ovn_ruff_fix_executor.py check|apply <repo_dir> <item line | file>")
        return 2
    repo = os.path.abspath(argv[2])
    if argv[1] == "check":
        print(check(repo, argv[3]))
        return 0
    rc, msg = apply(repo, argv[3])
    print(msg)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
