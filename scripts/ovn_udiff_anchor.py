#!/usr/bin/env python3
"""ovn_udiff_anchor.py - find udiff hunks with NO anchor that aider applied at the END of a large existing file.

2026-10-13 (night review xlite F6).  aider's udiff coder applies a hunk that has no context line and no removed line by APPENDING its added lines to the end of the
file (udiff_coder.do_replace: an empty "before" text means "append").  The 27B writes such hunks for "add a case to display_name()" style edits (`@@ -1,0 +1,2 @@`
with only '+' lines).  On a ~1100-line scripts/units/unit.gd that put `EnemyType.RAIDER:` / `return "Raider"` after _draw(): a parse error, a build-gate fix-up that
removed the stray lines again, and the net-zero guard threw the whole cycle away.  Three identical cycles in a row (the failure text never said "your hunk had no anchor").

usage: ovn_udiff_anchor.py <log-slice-file> <repo-dir> [--rev SHA] [--min-lines N]
  <log-slice-file>  one aider invocation's output (the runner's per-attempt slice of the task log)
  --rev SHA         read the target file as of this commit (the pre-attempt sha); default: the working-tree file
  --min-lines N     only files with MORE than N lines are checked (default $OVN_UDIFF_UNANCHORED_MIN_LINES or 300)
prints one line per unanchored hunk:  <path>\\t<file line count>\\t<hunk header>     (nothing when there is none)

A hunk is UNANCHORED when it has at least one '+' line but no removed line with content and no context line with content (blank context lines do not anchor: they match
anywhere).  A numbered header that places the insertion at the very end of the file (`@@ -N,0 ...` with N within 3 lines of the end) is an intended append and is NOT
flagged; a bare `@@ ... @@`, or numbers pointing anywhere else, are.  New files (not present at --rev) and test files (tests/, test_*, *_test.*, *.test.*, *.spec.*: a new test is normally appended at the end) are never flagged.
PYTHON EOF-TOLERANT ADDITIONS (2026-10-13, reviewer finding): in a .py file a pure-addition hunk whose added lines are all MODULE-LEVEL code (a top-level def / async def / class / decorator+def /
import / UPPER_CASE-or-plain assignment, with only indented bodies, closing brackets and comments in between; the hunk must contain at least one def/class/assignment and parse on its own) still works when aider appends it at the end of the file, and on the box
4 such cycles (iptv playlist.py, main.py ALLOWED_METRIC_FIELDS, subscription.py, ...) landed and were credited.  NOT tolerated (2nd review): a decorator-only hunk (dangling decorator at EOF), an import-only hunk (the edit that uses the import was lost), keyword headers like 'else: x = 1'.  They are not flagged (OVN_UDIFF_PY_EOF_OK=off flags them again).
A hunk that starts INDENTED (a method body, a case branch) or whose first statement is a control-flow line (if/for/return/...) is still flagged: appended at EOF it is a different program.  The script never fails: on any error it prints nothing
and exits 0 (the caller then keeps the old behaviour).
"""
import ast
import keyword
import os
import re
import subprocess
import sys

HDR = re.compile(r"^---[ \t]+(\S.*?)[ \t]*$")
PLUS = re.compile(r"^\+\+\+[ \t]+(\S.*?)[ \t]*$")
NUMS = re.compile(r"-(\d+)(?:,(\d+))?[ \t]+\+(\d+)(?:,(\d+))?")
STOP = re.compile(r"^(Tokens:|Applied edit to |Commit [0-9a-f]{6,}|```)")


def _clean_path(p):
    p = p.split("\t")[0].strip()
    if p.startswith(("a/", "b/")):
        p = p[2:]
    return p


def parse_hunks(text):
    """-> list of (path, header, body_lines).  Tolerates aider's wrapped/padded terminal rendering."""
    lines = [l.rstrip("\r") for l in text.split("\n")]
    out = []
    i, n = 0, len(lines)
    while i < n:
        m = HDR.match(lines[i])
        if not (m and i + 1 < n and PLUS.match(lines[i + 1])):
            i += 1
            continue
        old = _clean_path(m.group(1))
        path = _clean_path(PLUS.match(lines[i + 1]).group(1))
        i += 2
        cur = None
        while i < n:
            ln = lines[i]
            if STOP.match(ln):
                break
            if HDR.match(ln) and i + 1 < n and PLUS.match(lines[i + 1]):
                break
            if ln.startswith("@@"):
                cur = [path, ln.strip(), [], old]
                out.append(cur)
            elif cur is not None and (ln[:1] in ("+", "-", " ") or not ln.strip()):
                cur[2].append(ln)
            # anything else is prose or a terminal-wrapped continuation line: ignore it
            i += 1
    return out


def is_unanchored(body):
    adds = [l for l in body if l.startswith("+") and l[1:].strip()]
    dels = [l for l in body if l.startswith("-") and l[1:].strip()]
    ctx = [l for l in body if l.startswith(" ") and l.strip()]
    return bool(adds) and not dels and not ctx


# a module-level statement that is harmless at the end of a .py file (def/class/decorator/import/assignment).  Control flow (if/for/while/try/with/return/...) is NOT in the list.
# The assignment form `name = v` / `name: T = v` must NOT match a python keyword: 'else: x = 1', 'try: x = 1', 'finally: y = 2', 'except: x = 1', 'class: x = 1' look like an
# annotated assignment to a regex but are control-flow / header lines (2026-10-13 reviewer minor).
_KW = "|".join(sorted(keyword.kwlist, key=len, reverse=True))
PY_ASSIGN = re.compile(r"^(?!(?:%s)\b)[A-Za-z_][A-Za-z0-9_]*\s*(:[^=]+)?=[^=]" % _KW)
PY_DEF = re.compile(r"^(async\s+def\s|def\s|class\s)")
PY_DECO = re.compile(r"^@")
PY_IMPORT = re.compile(r"^(import\s|from\s+\S+\s+import\s)")


def _py_top_kind(t):
    """-> 'def' | 'deco' | 'import' | 'assign' | None for a non-indented added python line."""
    if PY_DEF.match(t):
        return "def"
    if PY_DECO.match(t):
        return "deco"
    if PY_IMPORT.match(t):
        return "import"
    if PY_ASSIGN.match(t):
        return "assign"
    return None


def py_eof_tolerant(path, body):
    """True when every added line of this pure-addition hunk is COMPLETE module-level python that is still valid, and still does its job, after being appended at the end of the file.

    Not tolerated (the hunk stays 'unanchored'): a decorator that is not followed by a def/class in the hunk (a dangling decorator at EOF is a SyntaxError or decorates nothing - the real
    iptv downloads.py '+@limiter.limit(...)' loop), a hunk of imports only (appended imports mean the edit that was supposed to USE them was lost), a hunk that does not parse as a module
    on its own (a def with no body, a keyword header like 'else: x = 1'), an indented first line, and any control-flow line."""
    if not path.endswith(".py"):
        return False
    if (os.environ.get("OVN_UDIFF_PY_EOF_OK", "on") or "on").lower() == "off":
        return False
    seen_top = False
    substantive = False  # at least one def/class/assignment (an import is not a finished edit)
    pending_deco = False
    added = []
    for l in body:
        if not l.startswith("+") or not l[1:].strip():
            continue
        t = l[1:]
        added.append(t)
        if t[:1] in (" ", "\t"):
            if not seen_top:
                return False  # the very first code line is indented: a method / branch body, not a module-level addition
            continue
        if t.startswith("#") or t[:1] in (")", "]", "}"):
            continue
        kind = _py_top_kind(t)
        if kind is None:
            return False
        if pending_deco and kind not in ("def", "deco"):
            return False  # a decorator must be followed by a def/class (or another decorator)
        pending_deco = kind == "deco"
        seen_top = True
        if kind in ("def", "assign"):
            substantive = True
    if pending_deco or not (seen_top and substantive):
        return False
    try:
        ast.parse("\n".join(added) + "\n")  # complete on its own: no dangling decorator, no def without a body, no keyword header
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return False
    return True


def file_line_count(repo, path, rev):
    try:
        if rev:
            data = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (rev, path)], capture_output=True, timeout=30)
            if data.returncode != 0:
                return None
            raw = data.stdout
        else:
            raw = open(repo.rstrip("/") + "/" + path, "rb").read()
    except Exception:
        return None
    return raw.count(b"\n") + (0 if raw.endswith(b"\n") or not raw else 1)


TESTPATH = re.compile(r"(^|/)(tests?|__tests__|spec|specs)/|(^|/)test_[^/]*$|_test\.[A-Za-z0-9]+$|\.(test|spec)\.[A-Za-z0-9]+$")


def is_test_path(path):
    """Appending a new test function at the end of a test file is the normal way to add one: not a misplacement."""
    return bool(TESTPATH.search(path))


def intended_append(header, nlines):
    m = NUMS.search(header)
    if not m:
        return False
    start, length = int(m.group(1)), int(m.group(2)) if m.group(2) is not None else 1
    return start + length >= nlines - 3


def _added_text(body):
    return "\n".join(l[1:] for l in body if l.startswith("+"))


def py_docstring_only(path, body):
    """True when every added line of a pure-addition .py hunk is a bare string-literal statement (docstring text and blank lines only)."""
    if not path.endswith(".py"):
        return False
    import textwrap
    txt = textwrap.dedent(_added_text(body)).strip("\n")
    if not txt.strip():
        return False
    try:
        tree = ast.parse(txt + "\n")
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return False
    return bool(tree.body) and all(isinstance(n, ast.Expr) and isinstance(getattr(n, "value", None), ast.Constant) and isinstance(n.value.value, str) for n in tree.body)


def py_redefines_existing(path, body, repo, rev):
    """True when a pure-addition .py hunk re-declares something the file already defines at --rev.
    Module-level `def`/`class NAME`: NAME already a top-level name (appended at EOF that SHADOWS the real one; gitlark reactions.py 2026-10-17: `class MessageReactionResponse(BaseModel):`
    re-added after get_message_reactions).  Indented non-dunder `def`: the identical stripped signature line already exists in the file (gitlark billing.py 2026-10-17: a second
    `def price_for_tier(self, tier: str) -> str:` + docstring-only body inserted into BillingService; it shadowed the real method and returned None)."""
    if not path.endswith(".py"):
        return False
    top, nested = [], []
    for l in body:
        if not l.startswith("+"):
            continue
        t = l[1:]
        m = re.match(r"^(\s*)(async\s+def|def|class)\s+([A-Za-z_]\w*)", t)
        if not m:
            continue
        if not m.group(1):
            top.append(m.group(3))
        elif not m.group(3).startswith("__") and m.group(2) != "class":
            nested.append(t.strip())
    if not top and not nested:
        return False
    try:
        if rev:
            r = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (rev, path)], capture_output=True, timeout=30)
            if r.returncode != 0:
                return False
            src = r.stdout.decode("utf-8", "replace")
        else:
            src = open(repo.rstrip("/") + "/" + path, errors="replace").read()
        tree = ast.parse(src)
    except Exception:
        return False
    have = {n.name for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))}
    if any(n in have for n in top):
        return True
    lines = {x.strip() for x in src.split("\n")}
    return any(sig in lines for sig in nested)


def scan(text, repo, rev, min_lines):
    seen, found = set(), []
    py_small_ok = (os.environ.get("OVN_UDIFF_PY_DOCSTRING_ANY_SIZE", "on") or "on").lower() != "off"
    for path, header, body, old in parse_hunks(text):
        # 2026-10-17 (gitlark review): size-independent python misplacement.  A context-free hunk is appended at EOF by aider whatever the file size; on a < 300-line file that is
        # harmless for code (the build fails) but SILENT for (a) docstring text (a bare string after the last statement: tests stay green, the docstring is never attached) and
        # (b) a re-declared top-level def/class (shadows the real one).  Both landed on gitlark 10-17 (project_config.py router, reactions.py) and cost ~3h of repair cycles.
        if py_small_ok and old != "/dev/null" and not is_test_path(path) and is_unanchored(body) and (py_docstring_only(path, body) or py_redefines_existing(path, body, repo, rev)):
            n = file_line_count(repo, path, rev)
            key = (path, header)
            if n is not None and key not in seen:
                seen.add(key)
                found.append((path, n, header))
            continue
        if old == "/dev/null" or is_test_path(path) or not is_unanchored(body) or py_eof_tolerant(path, body):
            continue
        n = file_line_count(repo, path, rev)
        if n is None or n <= min_lines or intended_append(header, n):
            continue
        key = (path, header)
        if key not in seen:
            seen.add(key)
            found.append((path, n, header))
    return found


def main(argv):
    args, rev, min_lines = [], "", None
    it = iter(argv)
    for a in it:
        if a == "--rev":
            rev = next(it, "")
        elif a == "--min-lines":
            min_lines = next(it, "")
        else:
            args.append(a)
    if len(args) < 2:
        return 0
    if min_lines in (None, ""):
        min_lines = os.environ.get("OVN_UDIFF_UNANCHORED_MIN_LINES", "300")
    try:
        min_lines = int(min_lines)
    except ValueError:
        min_lines = 300
    try:
        text = open(args[0], errors="replace").read()
        for path, n, header in scan(text, args[1], rev, min_lines):
            print("%s\t%d\t%s" % (path, n, header[:80]))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
