#!/usr/bin/env python3
"""gate_antigaming.py - S3 anti-gaming diff gate (deterministic, no LLM, never executes repo code).

    python3 qa/gate_antigaming.py check --repo <name|path> --base <ref> --head <ref> [--no-record] [--enforce-exit]

Flags changes that weaken the oracle or remove safety:
  A  tests: assertions removed / weakened / turned into no-ops, test functions or cases deleted      (A_*)
  B  new skip / xfail / .skip / @Ignore / noqa / type: ignore / eslint-disable / pragma: no cover
     added to EXISTING tests or code                                                                   (B_*)
  C  deleted or narrowed try/except, raise-validation in NON-test files                               (C_*)
  D  edits to files in state/qa_frozen_tests.json ({repo: {path: sha256}}); manifest absent => NA     (D_*)
  E  a test that remains but has zero effective assertions left                                       (E_*)
  F  coverage-threshold lowered / --ignore / --deselect added in test config                          (F_*)
  2026-10-04 (qa/ag_h13.py, see its docstring): D_DEAD_SYMBOL, E_TEST_NOT_COLLECTED, F_REVERT_OF_RECENT, D_FROZEN_EDIT (vendored paths, FAIL),
  D_FROZEN_NEWFILE, C_FILE_DELETED_LIVE, C_TEST_ORPHANED, A_MOCK_ONLY, A_MIRROR_EXPECTED
FAIL only for high-confidence gaming (frozen-test edit, all assertions gone from a surviving test, an assertion
replaced by a tautology). Everything uncertain is FLAG. Could not analyse (bad refs, git error, deadline with no
findings) => UNVERIFIED, exit 0. See qa/gate_antigaming.README.md and docs/QA_GATES_SPEC.md.
"""
import ast
import bisect
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import textwrap
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "antigaming"
MAX_BLOB = 800000
MAX_FILES = 400
MAX_FINDINGS = 60

CODE_EXT = {".py": "py", ".ts": "js", ".tsx": "js", ".js": "js", ".jsx": "js", ".mjs": "js", ".cjs": "js", ".vue": "js",
            ".kt": "kt", ".kts": "kt", ".gd": "gd", ".swift": "swift"}
SKIP_DIRS = {"node_modules", "vendor", "dist", "build", ".venv", "venv", "site-packages", "Pods", "__pycache__",
             ".gradle", ".git", "migrations", "versions", "generated", ".next", "coverage"}
CONFIG_NAMES = {"pyproject.toml", "setup.cfg", "pytest.ini", "tox.ini", ".coveragerc", "codecov.yml", ".codecov.yml",
                "jest.config.js", "jest.config.ts", "jest.config.cjs", "jest.config.mjs", "vitest.config.ts",
                "vitest.config.js", "package.json"}


def lang_of(path):
    return CODE_EXT.get(os.path.splitext(path)[1].lower())


def ignorable(path):
    parts = path.split("/")
    if any(p in SKIP_DIRS for p in parts[:-1]):
        return True
    b = parts[-1]
    return b.endswith((".min.js", ".d.ts", ".lock")) or b in ("package-lock.json",)


def is_test_path(path):
    lang = lang_of(path)
    parts = path.split("/")
    base = parts[-1]
    segs = [p.lower() for p in parts[:-1]]
    if lang == "py":
        return (base.startswith("test_") or base.endswith("_test.py") or base == "conftest.py"
                or any(s in ("tests", "test", "__tests__", "e2e", "integration_tests") for s in segs))
    if lang == "js":
        return bool(re.search(r"\.(test|spec)\.[cm]?[jt]sx?$", base)) or any(
            s in ("__tests__", "e2e", "cypress", "tests", "test") for s in segs)
    if lang == "kt":
        return ("src/test/" in path or "src/androidTest/" in path or re.search(r"Tests?\.kt$", base) is not None
                or "/androidTest/" in path)
    if lang == "gd":
        return base.startswith("test_") or any(s in ("test", "tests") for s in segs)
    if lang == "swift":
        return base.endswith(("Tests.swift", "Test.swift")) or any(s.endswith("tests") for s in segs)
    return False


# ------------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------------
_STR_RE = re.compile(r"""("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')""")


def snip(s, n=140):
    """One-line, secret-safe evidence: long string literals are replaced, whitespace collapsed, truncated."""
    s = " ".join((s or "").split())
    s = _STR_RE.sub(lambda m: m.group(0) if len(m.group(0)) <= 26 else m.group(0)[0] + "<str>" + m.group(0)[0], s)
    s = re.sub(r"[A-Za-z0-9_\-]{32,}", "<redacted>", s)
    return s[:n]


def short(s, n=40):
    """Identifier/test-name shortening (no secret redaction: names are not values)."""
    s = " ".join((s or "").split())
    return s if len(s) <= n else s[:n - 1] + "~"


class Finding(dict):
    pass


def F(rule, sev, path, line, msg, text="", old_line=None):
    d = Finding(rule=rule, sev=sev, file=path, line=line, msg=msg, snip=snip(text))
    if old_line:
        d["old_line"] = old_line
    return d


# ------------------------------------------------------------------------------------------------------------------
# assertion ranking (shared concepts: 0 tautology / no-op, 1 shape-only, 2 call-recorded, 3 partial, 4 exact)
# ------------------------------------------------------------------------------------------------------------------
PY_ASSERT_RANK = {
    "assertEqual": 4, "assertEquals": 4, "assertDictEqual": 4, "assertListEqual": 4, "assertTupleEqual": 4,
    "assertSetEqual": 4, "assertSequenceEqual": 4, "assertMultiLineEqual": 4, "assertCountEqual": 4,
    "assertAlmostEqual": 4, "assertIs": 4, "assertIsNone": 4, "assertJSONEqual": 4, "assertEqualsIgnoringOrder": 4,
    "assert_called_with": 4, "assert_called_once_with": 4, "assert_has_calls": 4, "assert_any_call": 4,
    "assert_awaited_with": 4, "assert_awaited_once_with": 4, "assert_array_equal": 4, "assert_allclose": 4,
    "assertIn": 3, "assertNotIn": 3, "assertGreater": 3, "assertGreaterEqual": 3, "assertLess": 3, "assertLessEqual": 3,
    "assertRegex": 3, "assertNotRegex": 3, "assertNotEqual": 3, "assertIsNot": 3, "assert_not_called": 3,
    "assertRegexpMatches": 3, "assert_awaited": 2, "assert_called": 1, "assert_called_once": 2, "assert_awaited_once": 2,
    "assertTrue": 1, "assertFalse": 1, "assertIsNotNone": 1, "assertIsInstance": 1, "assertNotIsInstance": 1,
}
PY_RAISES = {"raises", "warns", "assertRaises", "assertRaisesRegex", "assertWarns", "assertWarnsRegex"}
GENERIC_EXC = {"Exception", "BaseException"}


def _is_taut_expr(e):
    if isinstance(e, ast.Constant):
        return bool(e.value) or e.value is Ellipsis
    if isinstance(e, ast.UnaryOp) and isinstance(e.op, ast.Not):
        return isinstance(e.operand, ast.Constant) and not e.operand.value
    if isinstance(e, ast.BoolOp) and isinstance(e.op, ast.Or):
        if any(_is_taut_expr(v) for v in e.values):
            return True
        dumps = [ast.dump(v) for v in e.values]  # `x or not x`
        for v in e.values:
            if isinstance(v, ast.UnaryOp) and isinstance(v.op, ast.Not) and ast.dump(v.operand) in dumps:
                return True
        return False
    if isinstance(e, ast.Compare) and len(e.ops) == 1 and isinstance(e.ops[0], (ast.Eq, ast.Is, ast.GtE, ast.LtE)):
        if ast.dump(e.left) == ast.dump(e.comparators[0]) and not isinstance(e.left, ast.Call):
            return True
    if isinstance(e, (ast.Tuple, ast.List, ast.Dict, ast.Set)) and getattr(e, "elts", getattr(e, "keys", None)):
        return True  # assert (x, "msg") is always true
    return False


def _rank_expr(e):
    """Rank of ONE assert condition (BoolOp-And operands are split by the caller)."""
    if _is_taut_expr(e):
        return 0
    if isinstance(e, ast.Compare) and len(e.ops) == 1 and isinstance(e.ops[0], (ast.Eq, ast.Is)) and isinstance(e.left, ast.Call) \
            and ast.dump(e.left) == ast.dump(e.comparators[0]):
        return 1  # foo() == foo(): a determinism check at best, pins no value (rank 1 so exact -> self-compare is a weakening; not "vacuous" for new tests)
    if isinstance(e, ast.Compare):
        r = []
        for op, comp in zip(e.ops, e.comparators):
            if isinstance(op, ast.Eq):
                r.append(4)
            elif isinstance(op, ast.Is):
                r.append(4)
            elif isinstance(op, ast.IsNot):
                r.append(1 if (isinstance(comp, ast.Constant) and comp.value is None) else 3)
            elif isinstance(op, ast.NotEq):
                r.append(1 if (isinstance(comp, ast.Constant) and comp.value is None) else 3)
            else:
                r.append(3)
        return min(r)
    return 1  # bare truthiness / isinstance / not X / call result


def _split_and(e):
    if isinstance(e, ast.BoolOp) and isinstance(e.op, ast.And):
        out = []
        for v in e.values:
            out += _split_and(v)
        return out
    return [e]


def _call_name(call):
    f = call.func
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return None


def _first_arg_name(call):
    if call.args:
        a = call.args[0]
        if isinstance(a, ast.Name):
            return a.id
        if isinstance(a, ast.Attribute):
            return a.attr
    return None


class PyUnits(ast.NodeVisitor):
    """Collect assertion units of one function body: (lineno, rank, normalized text)."""

    def __init__(self):
        self.units = []
        self.calls = set()
        self.names = set()

    def visit_Name(self, node):
        self.names.add(node.id)

    def visit_Attribute(self, node):
        self.names.add(node.attr)
        self.generic_visit(node)

    def visit_Assert(self, node):
        for part in _split_and(node.test):
            try:
                txt = "assert " + ast.unparse(part)
            except Exception:  # noqa: BLE001
                txt = "assert <expr>"
            self.units.append((node.lineno, _rank_expr(part), txt))
        # do not descend: the asserted expression is not a separate unit

    def visit_Try(self, node):
        swallow = False
        for h in node.handlers:
            t = h.type
            nm = []
            for x in (t.elts if isinstance(t, ast.Tuple) else [t]):
                nm.append(None if x is None else (x.id if isinstance(x, ast.Name) else (x.attr if isinstance(x, ast.Attribute) else "?")))
            if any(n in (None, "AssertionError", "Exception", "BaseException") for n in nm) and not any(
                    isinstance(r, ast.Raise) for b in h.body for r in ast.walk(b)):
                swallow = True
        start = len(self.units)
        for b in node.body:
            self.visit(b)
        if swallow:  # an assertion whose failure is caught and dropped can never fail the test
            for i in range(start, len(self.units)):
                u = self.units[i]
                self.units[i] = (u[0], 0, "swallowed: " + u[2])
        for h in node.handlers:
            for b in h.body:
                self.visit(b)
        for b in node.orelse + node.finalbody:
            self.visit(b)

    def visit_With(self, node):
        start = len(self.units)
        for it in node.items:
            self.visit(it.context_expr)
        n_ctx = len(self.units)
        for b in node.body:
            self.visit(b)
        empty = all(isinstance(b, ast.Pass) or (isinstance(b, ast.Expr) and isinstance(b.value, ast.Constant)) for b in node.body)
        if empty:  # `with pytest.raises(X): pass` - nothing can raise
            for i in range(start, n_ctx):
                u = self.units[i]
                if re.match(r"(?:\w+\.)*(?:raises|warns|assertRaises\w*|assertWarns\w*)\(", u[2]):
                    self.units[i] = (u[0], 0, "empty-with: " + u[2])

    visit_AsyncWith = visit_With

    def visit_Raise(self, node):
        e = node.exc
        nm = _call_name(e) if isinstance(e, ast.Call) else (e.id if isinstance(e, ast.Name) else None)
        if nm == "AssertionError":
            self.units.append((node.lineno, 4, "raise AssertionError"))
        self.generic_visit(node)

    def visit_Call(self, node):
        nm = _call_name(node)
        if nm:
            self.calls.add(nm)
            if nm in PY_RAISES:
                broad = _first_arg_name(node) in GENERIC_EXC
                try:
                    txt = ast.unparse(node)
                except Exception:  # noqa: BLE001
                    txt = nm
                self.units.append((node.lineno, 1 if broad else 3, txt))
            elif nm in PY_ASSERT_RANK or nm.startswith("assert"):
                rank = PY_ASSERT_RANK.get(nm, 3)
                args = node.args
                if nm in ("assertTrue", "assertFalse") and args and isinstance(args[0], ast.Constant):
                    rank = 0 if bool(args[0].value) == (nm == "assertTrue") else rank
                if nm in ("assertEqual", "assertEquals", "assertIs") and len(args) >= 2 and ast.dump(args[0]) == ast.dump(args[1]) \
                        and not isinstance(args[0], ast.Call):
                    rank = 0
                elif nm in ("assertEqual", "assertEquals", "assertIs") and args and any(
                        isinstance(a, ast.Constant) and isinstance(a.value, bool) for a in args[:2]):
                    rank = 1  # assertEqual(True, x) is just assertTrue(x)
                try:
                    txt = ast.unparse(node)
                except Exception:  # noqa: BLE001
                    txt = nm
                self.units.append((node.lineno, rank, txt))
            elif nm == "fail" and isinstance(node.func, ast.Attribute):
                self.units.append((node.lineno, 3, "fail()"))
        self.generic_visit(node)


class FuncInfo:
    __slots__ = ("qual", "line", "end", "units", "calls", "names", "eff", "params", "norm", "src", "tries", "handler_breadth",
                 "raises", "decorators", "uses_suppress", "try_lines", "deps", "handlers", "trys")


def _breadth(h):
    t = h.type
    if t is None:
        return 3
    names = []
    elts = t.elts if isinstance(t, ast.Tuple) else [t]
    for x in elts:
        names.append(x.id if isinstance(x, ast.Name) else (x.attr if isinstance(x, ast.Attribute) else "?"))
    if "BaseException" in names:
        return 3
    if "Exception" in names:
        return 2
    return 1


def _handler_names(h):
    t = h.type
    if t is None:
        return frozenset(["*"])
    out = set()
    for x in (t.elts if isinstance(t, ast.Tuple) else [t]):
        out.add(x.id if isinstance(x, ast.Name) else (x.attr if isinstance(x, ast.Attribute) else "?"))
    return frozenset(out)


def _handlers_widened(of, nf):
    """True when a guard was WIDENED, not removed: some old try whose body statements all persist in a new try (extra guards inside are fine) now has a
    strictly wider handler (`except ValueError` -> `except (ValueError, TypeError)`), and no exception type the old function handled is lost.
    Requiring the protected statements to persist stops 'delete the try, and a different try elsewhere already catches the same type' from passing."""
    old_t = set().union(*of.handlers) if of.handlers else set()
    new_t = set().union(*nf.handlers) if nf.handlers else set()
    if not nf.handlers or not (("*" in new_t) or (old_t <= new_t)):
        return False
    for obody, ohs in of.trys:
        oh = set().union(*ohs) if ohs else set()
        for nbody, nhs in nf.trys:
            nh = set().union(*nhs) if nhs else set()
            if obody and obody <= nbody and (oh < nh or ("*" in nh and "*" not in oh)):
                return True
    return False


def _import_only(body):
    return all(isinstance(s, (ast.Import, ast.ImportFrom, ast.Pass)) or (isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant))
               for s in body)


class PyModule:
    def __init__(self, text):
        self.tree = ast.parse(text)
        self.lines = text.split("\n")
        self.funcs = {}
        self.file_tries = 0
        self.file_raises = 0
        self.defs = set()
        self._walk(self.tree.body, [])
        for n in ast.walk(self.tree):
            if isinstance(n, getattr(ast, "TryStar", ast.Try)) or isinstance(n, ast.Try):
                if n.handlers and not _import_only(n.body):
                    self.file_tries += 1
            elif isinstance(n, ast.Raise):
                self.file_raises += 1

    def _walk(self, body, stack):
        for n in body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                self.defs.add(n.name)
                self._add(n, stack)
            elif isinstance(n, ast.ClassDef):
                self.defs.add(n.name)
                self._walk(n.body, stack + [n.name])

    def _add(self, n, stack):
        fi = FuncInfo()
        fi.qual = ".".join(stack + [n.name])
        fi.line = n.lineno
        fi.end = getattr(n, "end_lineno", n.lineno)
        pu = PyUnits()
        for s in n.body:
            pu.visit(s)
        fi.units, fi.calls, fi.names = pu.units, pu.calls, pu.names
        fi.eff = sum(1 for u in pu.units if u[1] > 0)
        fi.params = None
        fi.decorators = []
        for d in n.decorator_list:
            try:
                fi.decorators.append(ast.unparse(d))
            except Exception:  # noqa: BLE001
                pass
            if isinstance(d, ast.Call) and _call_name(d) == "parametrize" and len(d.args) >= 2 \
                    and isinstance(d.args[1], (ast.List, ast.Tuple)):
                fi.params = (fi.params or 1) * len(d.args[1].elts)
        try:
            fi.norm = "\n".join(ast.unparse(s) for s in n.body)
        except Exception:  # noqa: BLE001
            fi.norm = ""
        fi.src = "\n".join(self.lines[n.lineno - 1:fi.end])
        tries = [t for t in ast.walk(n) if isinstance(t, ast.Try) and t.handlers and not _import_only(t.body)]
        fi.tries = len(tries)
        fi.try_lines = [t.lineno for t in tries]
        fi.handler_breadth = max([_breadth(h) for t in tries for h in t.handlers] or [0])
        fi.raises = sum(1 for r in ast.walk(n) if isinstance(r, ast.Raise) and r.exc is not None)
        fi.handlers = [_handler_names(h) for t in tries for h in t.handlers]
        fi.trys = [(frozenset(ast.unparse(b) for b in t.body), [_handler_names(h) for h in t.handlers]) for t in tries]
        # FastAPI-style dependencies (`x = Depends(require_admin)` in the signature or `dependencies=[Depends(..)]` in the decorator) run BEFORE the
        # body: validation that moved there is delegated, not dropped
        fi.deps = set()
        for part in [n.args] + list(n.decorator_list):
            for c in ast.walk(part):
                if isinstance(c, ast.Call) and _call_name(c) in ("Depends", "Security") and c.args:
                    fi.deps.add(ast.unparse(c.args[0]) if hasattr(ast, "unparse") else "?")
        body_txt = fi.src
        fi.uses_suppress = bool(re.search(r"suppress\(|@\w*(retry|catch|handle|guard|safe)\w*", body_txt, re.I)) or any(
            re.search(r"retry|catch|handle|guard|safe|suppress", d, re.I) for d in fi.decorators)
        self.funcs[fi.qual] = fi

    def tests(self):
        out = {}
        for q, f in self.funcs.items():
            if f.qual.split(".")[-1].startswith("test"):
                out[q] = f
        return out


# ------------------------------------------------------------------------------------------------------------------
# non-Python languages: masking, test extraction, assertion units
# ------------------------------------------------------------------------------------------------------------------
def mask_text(text, lang):
    """Blank comments and string contents (offsets/newlines preserved) so bracket matching is reliable."""
    out = list(text)
    n = len(text)
    i = 0
    hash_comment = lang == "gd"
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if hash_comment and c == "#":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif not hash_comment and two == "//":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif not hash_comment and two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if text[k] != "\n":
                    out[k] = " "
            i = j
        elif text[i:i + 3] == '"""' and lang in ("kt", "swift", "gd"):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            for k in range(i + 3, max(i + 3, j - 3)):
                if text[k] != "\n":
                    out[k] = " "
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
        elif c == "`" and lang in ("kt", "swift"):
            # `fun \`it's a name\`()`: a backticked identifier is not a string; its apostrophe must not open a char literal
            j = text.find("`", i + 1)
            nl = text.find("\n", i + 1)
            if j < 0 or (0 <= nl < j):
                i += 1
            else:
                for k in range(i + 1, j):
                    out[k] = " "
                i = j + 1
        elif c == "`" and lang == "js":
            j = i + 1
            while j < n and text[j] != "`":
                j += 2 if text[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                if text[k] != "\n":
                    out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


def match_close(masked, open_idx):
    o = masked[open_idx]
    cl = {"(": ")", "{": "}", "[": "]"}[o]
    d = 0
    for i in range(open_idx, len(masked)):
        ch = masked[i]
        if ch == o:
            d += 1
        elif ch == cl:
            d -= 1
            if d == 0:
                return i
    return -1


JS_TEST_RE = re.compile(r"(?<![\w.$])(?:x|f)?(?:it|test|specify)(?:\s*\.\s*(?:only|skip|concurrent|serial|fixme|todo|failing|"
                        r"each\s*(?:\((?:[^()]|\([^()]*\))*\)|`[^`]*`)))*\s*\(")
JS_DESC_RE = re.compile(r"(?<![\w.$])(?:x|f)?(?:describe|context|suite)(?:\s*\.\s*(?:only|skip|each\s*\((?:[^()]|\([^()]*\))*\)))*\s*\(")
TITLE_RE = re.compile(r"""\s*(?:`((?:\\.|[^`\\])*)`|"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')""")


class TInfo:
    __slots__ = ("qual", "line", "units", "eff", "norm", "src", "calls", "params")


def _line_index(text):
    starts = [0]
    for m in re.finditer("\n", text):
        starts.append(m.end())
    return starts


def _lineof(starts, off):
    return bisect.bisect_right(starts, off)


JS_RANK = {
    "toBe": 4, "toEqual": 4, "toStrictEqual": 4, "toHaveBeenCalledWith": 4, "toHaveBeenLastCalledWith": 4,
    "toHaveBeenNthCalledWith": 4, "toMatchObject": 4, "toMatchSnapshot": 4, "toMatchInlineSnapshot": 4,
    "toHaveLength": 4, "toBeNull": 4, "toBeUndefined": 4, "toBeCloseTo": 4, "toHaveBeenCalledTimes": 4,
    "toHaveTextContent": 4, "toHaveValue": 4, "toBeNaN": 4,
    "toContain": 3, "toContainEqual": 3, "toMatch": 3, "toBeGreaterThan": 3, "toBeGreaterThanOrEqual": 3, "toBeLessThan": 3,
    "toBeLessThanOrEqual": 3, "toHaveProperty": 3, "toBeInTheDocument": 3, "toBeVisible": 3, "toHaveAttribute": 3,
    "toHaveClass": 3, "toThrowErrorMatchingSnapshot": 4,
    "toBeDefined": 1, "toBeTruthy": 1, "toBeFalsy": 1, "toBeInstanceOf": 1, "toHaveBeenCalled": 1, "toBeCalled": 1,
    "toThrow": 2, "toThrowError": 2,
}
KT_RANK = {"assertEquals": 4, "assertSame": 4, "assertNull": 4, "assertContentEquals": 4, "assertContains": 3,
           "assertNotEquals": 3, "assertNotSame": 3, "assertTrue": 1, "assertFalse": 1, "assertNotNull": 1, "assertIs": 1,
           "assertIsNot": 1, "assertFails": 1, "assertFailsWith": 3, "assertThrows": 3, "verify": 3, "assertArrayEquals": 4,
           "assertThat": 3, "shouldBe": 4, "shouldNotBe": 3, "shouldBeNull": 4, "isEqualTo": 4, "isNotNull": 1, "isTrue": 1,
           "isFalse": 1, "isNull": 4}
GD_RANK = {"assert_eq": 4, "assert_eq_deep": 4, "assert_same": 4, "assert_null": 4, "assert_almost_eq": 4,
           "assert_signal_emitted_with_parameters": 4, "assert_ne": 3, "assert_gt": 3, "assert_lt": 3, "assert_gte": 3,
           "assert_lte": 3, "assert_has": 3, "assert_does_not_have": 3, "assert_string_contains": 3, "assert_between": 3,
           "assert_called": 3, "assert_call_count": 4, "assert_true": 1, "assert_false": 1, "assert_not_null": 1,
           "assert_is": 1, "assert_signal_emitted": 1, "assert_not_same": 3, "assert_typeof": 1}
SW_RANK = {"XCTAssertEqual": 4, "XCTAssertNil": 4, "XCTAssertIdentical": 4, "XCTAssertEqualWithAccuracy": 4,
           "XCTAssertNotEqual": 3, "XCTAssertGreaterThan": 3, "XCTAssertLessThan": 3, "XCTAssertGreaterThanOrEqual": 3,
           "XCTAssertLessThanOrEqual": 3, "XCTAssertTrue": 1, "XCTAssertFalse": 1, "XCTAssertNotNil": 1, "XCTAssertThrowsError": 2,
           "XCTAssertNoThrow": 1, "XCTAssert": 1}

_JS_UNIT_RE = re.compile(r"(?<![\w$])(?:expect\s*\(|expect\.assertions\s*\(|expect\.hasAssertions\s*\(|assert(?:\.\w+)?\s*\(|"
                         r"t\.(?:is|deepEqual|true|false|truthy|falsy|throws|not)\s*\()|\.should\b|cy\.[\w.]*should\s*\(")
_KT_UNIT_RE = re.compile(r"(?<![\w.$])(assert\w*|verify|verifyOrder|verifySequence)\s*(?:<[^>]*>)?\s*[({]|\.(shouldBe\w*|shouldNotBe\w*|"
                         r"isEqualTo|isNotNull|isNull|isTrue|isFalse)\b")
_GD_UNIT_RE = re.compile(r"(?<![\w.])(assert_\w+|assert)\s*\(")
_SW_UNIT_RE = re.compile(r"(?<![\w.])(XCTAssert\w*|XCTFail)\s*\(|#expect\s*\(|#require\s*\(")


def _stmt_end(masked, start, hard=500):
    depth = 0
    n = len(masked)
    i = start
    while i < n and i - start < hard:
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth < 0:
                return i
        elif depth == 0 and c == ";":
            return i
        elif depth == 0 and c == "\n":
            j = i + 1
            while j < n and masked[j] in " \t":
                j += 1
            if j >= n or masked[j] not in ".?:&|+":
                return i
        i += 1
    return min(i, n)


def _rank_js(stmt_orig, stmt_masked):
    s = stmt_orig
    if re.search(r"expect\s*\(\s*(true|false|null|undefined|\d+|'[^']*'|\"[^\"]*\")\s*\)\s*\.\s*(?:not\s*\.\s*)?(?:toBe|toEqual|toStrictEqual)"
                 r"\(\s*\1\s*\)", s) or re.search(r"expect\s*\(\s*true\s*\)\s*\.\s*toBeTruthy\(\)", s) \
            or re.search(r"\bassert(?:\.ok)?\s*\(\s*(true|1)\s*[,)]", s) or re.search(r"expect\s*\(\s*(\d+)\s*\)\.toBe\(\s*\1\s*\)", s):
        return 0
    if "expect.assertions" in s or "expect.hasAssertions" in s:
        return 2
    ms = re.findall(r"\.\s*(not\s*\.\s*)?(to\w+)\s*\(?", stmt_masked)
    if ms:
        neg, name = ms[-1]
        r = JS_RANK.get(name, 3)
        if name in ("toBe", "toEqual", "toStrictEqual") and re.search(r"\(\s*(true|false)\s*\)\s*;?\s*$", s.strip()):
            r = 1  # toBe(true) == toBeTruthy()
        if neg and r == 4:
            r = 1 if name in ("toBeNull", "toBeUndefined", "toBeNaN") else 3
        elif neg and r == 1:
            r = 1
        return r
    m = re.search(r"assert\.(\w+)", stmt_masked)
    if m:
        nm = m.group(1).lower()
        if "equal" in nm or nm in ("is", "strictequal", "deepequal", "match"):
            return 4 if "not" not in nm else 3
        if nm in ("ok", "istrue", "isfalse", "exists", "isok", "isdefined"):
            return 1
        return 3
    if "should" in stmt_masked:
        return 4 if re.search(r"\.(equal|eql|be)\b", stmt_masked) else 3
    return 3


def _rank_named(table, name, stmt_orig):
    r = table.get(name, 3)
    if re.search(r"\b(assertTrue|assert_true|XCTAssertTrue)\s*\(\s*true\s*\)", stmt_orig, re.I) or \
            re.search(r"\b(assertFalse|assert_false|XCTAssertFalse)\s*\(\s*false\s*\)", stmt_orig, re.I):
        return 0
    if name in ("assertEquals", "assertSame", "assert_eq", "XCTAssertEqual") and re.search(r"\(\s*(true|false|True|False)\s*,|,\s*(true|false|True|False)\s*[,)]", stmt_orig):
        return 1  # assertEquals(false, x) == assertFalse(x)
    if re.match(r"\s*(?:assert|require|check)\s*\(\s*(?:true|!\s*false|1\s*==\s*1|\w+\s*\|\|\s*true)\s*[,)]", stmt_orig):
        return 0  # Kotlin assert(true) / assert(x || true): can never fail (2026-10-03: closed-captions 'placeholder test' false credit)
    m = re.match(r"\s*\w+\s*\(\s*([\w.\"'0-9]+)\s*,\s*([\w.\"'0-9]+)\s*[,)]", stmt_orig)
    if m and name in ("assertEquals", "assert_eq", "XCTAssertEqual") and m.group(1) == m.group(2):
        return 0
    return r


def extract_units(lang, orig, masked, a, b, starts):
    """Assertion units inside masked[a:b] -> [(line, rank, normalized text)]."""
    out = []
    seg = masked[a:b]
    if lang == "js":
        it = _JS_UNIT_RE.finditer(seg)
    elif lang == "kt":
        it = _KT_UNIT_RE.finditer(seg)
    elif lang == "gd":
        it = _GD_UNIT_RE.finditer(seg)
    else:
        it = _SW_UNIT_RE.finditer(seg)
    last_end = -1
    for m in it:
        s0 = a + m.start()
        if s0 < last_end and lang == "js":  # nested matcher chains: one statement
            continue
        e0 = _stmt_end(masked, s0)
        last_end = e0
        so, sm = orig[s0:e0], masked[s0:e0]
        if lang == "js":
            if re.match(r"\.should|cy\.", sm) is None and sm.startswith("expect.") is False and "expect" in sm[:7] and ".to" not in sm \
                    and ".resolves" not in sm and ".rejects" not in sm and ".not" not in sm:
                continue  # bare `expect(x)` with no matcher is not an assertion
            rank = _rank_js(so, sm)
        elif lang == "kt":
            nm = m.group(1) or m.group(2)
            rank = _rank_named(KT_RANK, nm, so)
        elif lang == "gd":
            nm = m.group(1)
            rank = _rank_named(GD_RANK, nm, so)
            if nm == "assert":
                rank = 4 if "==" in sm else 1
        else:
            nm = m.group(1) or "#expect"
            rank = _rank_named(SW_RANK, nm, so) if m.group(1) else (4 if "==" in sm else 1)
        out.append((_lineof(starts, s0), rank, " ".join(so.split())[:200]))
    return out


def extract_tests_text(lang, text):
    """Return {qual: TInfo}. Raises ValueError when the file cannot be parsed reliably."""
    masked = mask_text(text, lang)
    starts = _line_index(text)
    res = {}
    spans = []  # (kind, start, end, title)

    def add(qual, a, b, line):
        base = qual
        k = 2
        while qual in res:
            qual = "%s#%d" % (base, k)
            k += 1
        ti = TInfo()
        ti.qual, ti.line = qual, line
        ti.units = extract_units(lang, text, masked, a, b, starts)
        ti.eff = sum(1 for u in ti.units if u[1] > 0)
        ti.src = text[a:b]
        ti.norm = " ".join(masked[a:b].split())
        ti.calls = set(re.findall(r"([A-Za-z_]\w{3,})\s*\(", masked[a:b]))
        ti.params = None
        res[qual] = ti

    if lang == "js":
        descs = []
        for m in JS_DESC_RE.finditer(masked):
            op = m.end() - 1
            cl = match_close(masked, op)
            if cl < 0:
                raise ValueError("unbalanced describe at line %d" % _lineof(starts, m.start()))
            t = TITLE_RE.match(text, m.end())
            title = next((g for g in t.groups() if g is not None), "?") if t else "?"
            descs.append((op, cl, title))
        for m in JS_TEST_RE.finditer(masked):
            op = m.end() - 1
            cl = match_close(masked, op)
            if cl < 0:
                raise ValueError("unbalanced test call at line %d" % _lineof(starts, m.start()))
            t = TITLE_RE.match(text, m.end())
            line = _lineof(starts, m.start())
            title = next((g for g in t.groups() if g is not None), None) if t else None
            if title is None:
                title = "<anon@%d>" % line
            path = [d[2] for d in descs if d[0] < m.start() < d[1]]
            add(" > ".join(path + [title]), op, cl, line)
    elif lang == "kt":
        for m in re.finditer(r"@(?:org\.junit\.(?:jupiter\.api\.)?)?(?:Test|ParameterizedTest|RepeatedTest)\b[^\n]*\n(?:\s*@[\w.]+(?:\([^)]*\))?\s*\n)*\s*"
                             r"(?:(?:public|internal|private|override|suspend)\s+)*fun\s+(`[^`]+`|\w+)\s*\(", text):
            name = m.group(1).strip("`")
            op_paren = m.end() - 1
            cp = match_close(masked, op_paren) if masked[op_paren] == "(" else -1
            if cp < 0:
                raise ValueError("unbalanced fun params")
            br = masked.find("{", cp)
            if br < 0 or br - cp > 400:
                continue
            ce = match_close(masked, br)
            if ce < 0:
                raise ValueError("unbalanced fun body")
            add(name, br, ce, _lineof(starts, m.start()))
    elif lang == "swift":
        for m in re.finditer(r"\bfunc\s+(test\w*)\s*\(", text):
            cp = match_close(masked, m.end() - 1)
            br = masked.find("{", cp) if cp >= 0 else -1
            if br < 0 or br - cp > 200:
                continue
            ce = match_close(masked, br)
            if ce < 0:
                raise ValueError("unbalanced func body")
            add(m.group(1), br, ce, _lineof(starts, m.start()))
    elif lang == "gd":
        lines = text.split("\n")
        mlines = masked.split("\n")
        offs = starts
        i = 0
        while i < len(lines):
            m = re.match(r"^(\s*)func\s+(test\w*)\s*\(", mlines[i])
            if m:
                ind = len(m.group(1))
                j = i + 1
                while j < len(lines):
                    if mlines[j].strip() and (len(mlines[j]) - len(mlines[j].lstrip())) <= ind:
                        break
                    j += 1
                a = offs[i]
                b = offs[j] if j < len(offs) else len(text)
                add(m.group(2), a, b, i + 1)
                i = j
            else:
                i += 1
    return res


# ------------------------------------------------------------------------------------------------------------------
# diff parsing / git access
# ------------------------------------------------------------------------------------------------------------------
class FileDiff:
    def __init__(self, path):
        self.path = path
        self.old = path
        self.status = "M"
        self.removed = []  # (old_lineno, text)
        self.added = []  # (new_lineno, text)


def parse_diff(text):
    files = {}
    cur = None
    in_hunk = False
    ol = nl = 0
    for line in text.split("\n"):
        if line.startswith("diff --git "):
            cur = None
            in_hunk = False
            continue
        if not in_hunk:
            if line.startswith("--- "):
                cur_old = line[4:].split("\t")[0]
                cur = {"old": None if cur_old == "/dev/null" else cur_old[2:], "new": None}
                continue
            if line.startswith("+++ ") and cur is not None:
                cn = line[4:].split("\t")[0]
                cur["new"] = None if cn == "/dev/null" else cn[2:]
                key = cur["new"] or cur["old"]
                fd = files.setdefault(key, FileDiff(key))
                fd.old = cur["old"] or key
                cur = fd
                continue
        if line.startswith("@@"):
            m = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
            if m and isinstance(cur, FileDiff):
                in_hunk = True
                ol, nl = int(m.group(1)), int(m.group(3))
            continue
        if in_hunk and isinstance(cur, FileDiff):
            if line.startswith("-"):
                cur.removed.append((ol, line[1:]))
                ol += 1
            elif line.startswith("+"):
                cur.added.append((nl, line[1:]))
                nl += 1
    return files


class Repo:
    def __init__(self, rd, base, head):
        self.rd, self.base, self.head = rd, base, head
        self._c = {}
        self.unanalysed = []  # reasons part of the diff could NOT be examined; with no findings the verdict must be UNVERIFIED, never PASS
        self.oversize = set()

    def tree(self):
        if getattr(self, "_tree", None) is None:
            rc, out, _ = qc.git(self.rd, "ls-tree", "-r", "--name-only", self.base, timeout=60)
            self._tree = set(out.splitlines()) if rc == 0 else set()
        return self._tree

    def defined_in_base(self, name, lang="py"):
        """Is `name` defined (def/class/function/const/...) anywhere in the base tree? None when git grep could not run."""
        k = ("def", name, lang)
        if k not in self._c:
            pat = r"(def|class|function|fun|func|interface|const|let|var|val|type|struct|enum|object)[[:space:]]+%s([^A-Za-z0-9_]|$)|^[[:space:]]*%s[[:space:]]*[:=]" % (name, name)
            specs = ["*.py"] if lang == "py" else ["*.ts", "*.tsx", "*.js", "*.jsx", "*.vue", "*.mjs"]
            rc, out, _ = qc.git(self.rd, "grep", "-I", "-l", "-E", "-e", pat, self.base, "--", *specs, timeout=60)
            self._c[k] = True if rc == 0 else (False if rc == 1 else None)
        return self._c[k]

    def nontest_refs(self, name, lang="py"):
        """Number of references to `name` in NON-test files at base, excluding its own def/import lines. None if unknown."""
        k = ("refs", name, lang)
        if k not in self._c:
            specs = ["*.py"] if lang == "py" else ["*.ts", "*.tsx", "*.js", "*.jsx", "*.vue", "*.mjs"]
            rc, out, _ = qc.git(self.rd, "grep", "-I", "-n", "-w", "-e", name, self.base, "--", *specs, timeout=60)
            if rc not in (0, 1):
                self._c[k] = None
            else:
                n = 0
                for ln in out.splitlines():
                    parts = ln.split(":", 3)
                    if len(parts) < 4:
                        continue
                    path, text = parts[1], parts[3]
                    if is_test_path(path) or re.match(r"\s*(from\s|import\s|export\s+\{)", text) or re.search(
                            r"\b(def|class|function|fun|func|const|let|var)\s+%s\b" % re.escape(name), text):
                        continue
                    n += 1
                self._c[k] = n
        return self._c[k]

    def blob(self, ref, path):
        k = (ref, path)
        if k not in self._c:
            rc, out, _ = qc.git(self.rd, "show", "%s:%s" % (ref, path))
            if rc == 0 and len(out) > MAX_BLOB:
                self.oversize.add(path)
            self._c[k] = out if rc == 0 and len(out) <= MAX_BLOB else None
        return self._c[k]


# ------------------------------------------------------------------------------------------------------------------
# rules
# ------------------------------------------------------------------------------------------------------------------
SKIP_STRONG = [
    re.compile(r"pytest\.mark\.(?:skip|skipif|xfail)\b|\bpytest\.(?:skip|xfail)\s*\(|unittest\.skip\w*|@skip(?:If|Unless)?\b|"
               r"\braise\s+(?:unittest\.)?SkipTest"),
    re.compile(r"(?<![\w$])(?:it|test|describe|context|suite)\s*\.\s*(?:skip|todo|fixme)\b|(?<![\w$.])x(?:it|describe|test|context)\s*\(|"
               r"(?<![\w$])(?:it|test|describe|context)\s*\.\s*only\b|(?<![\w$.])f(?:it|describe)\s*\("),
    re.compile(r"@(?:org\.junit\.)?(?:Ignore|Disabled)\b|\bXCTSkip\b|(?<![\w.])pending\s*\("),
    re.compile(r"#\s*pragma:\s*no\s*cover|//\s*istanbul\s+ignore|/\*\s*istanbul\s+ignore|c8\s+ignore"),
]
SKIP_WEAK = [
    re.compile(r"#\s*noqa\b|#\s*type:\s*ignore|#\s*pylint:\s*disable|#\s*nosec\b|#\s*mypy:\s*ignore-errors|#\s*pyright:\s*ignore"),
    re.compile(r"eslint-disable|@ts-ignore|@ts-nocheck|@Suppress\(|swiftlint:disable|detekt"),
]
MARKER_STRIP = [
    re.compile(r"\s*#\s*(?:noqa|type:\s*ignore|pylint:\s*disable|nosec|pragma:\s*no\s*cover)[^\n]*"),
    re.compile(r"\s*(?://|/\*)\s*(?:eslint-disable[^\n]*|@ts-ignore[^\n]*|@ts-nocheck[^\n]*|swiftlint:disable[^\n]*|istanbul ignore[^\n]*)"),
    re.compile(r"\.\s*(?:skip|todo|fixme|only)\b"),
    re.compile(r"(?<![\w$.])[xf](?=(?:it|describe|test|context)\s*\()"),
]


def _strip_markers(line):
    for r in MARKER_STRIP:
        line = r.sub("", line)
    return line.strip()


def _norm_line(s):
    return " ".join(s.split())


def rule_suppressions(repo, fd, old_text, new_text, is_test, out):
    """B: skip/xfail/noqa/... added to EXISTING tests or code."""
    if new_text is None:
        return
    strong_new = []
    weak_new = []
    old_set = None
    new_lines = new_text.split("\n")
    for ln, text in fd.added:
        s = text.strip()
        if not s:
            continue
        sk = next((r for r in SKIP_STRONG if r.search(text)), None)
        wk = next((r for r in SKIP_WEAK if r.search(text)), None)
        if not sk and not wk:
            continue
        if old_text is None:
            continue  # brand-new file: nothing existing was suppressed
        if old_set is None:  # lines this diff removed: a marker-only edit shows up as -line / +line#marker
            old_set = set(_norm_line(_strip_markers(t)) for _, t in fd.removed if t.strip())
        rest = _norm_line(_strip_markers(text))
        existing = False
        if len(rest) >= 6 and rest in old_set and not rest.startswith("@"):
            existing = True  # same code line, only the marker is new
        elif sk and (not rest or rest.startswith("@") or len(rest) < 6 or re.search(r"\b(pytest|self)\.(skip|xfail)\(|\braise\s", text)):
            tgt = _target_name(new_lines, ln - 1, rest.startswith("@") or not rest)
            if tgt and re.search(r"\b(def|fun|func|class|function)\s+`?%s\b|[\"'`]%s[\"'`]" % (re.escape(tgt), re.escape(tgt)), old_text):
                existing = True
        if not existing:
            continue
        if sk:
            strong_new.append((ln, text))
        else:
            weak_new.append((ln, text))
    for ln, text in strong_new:
        kind = "pragma: no cover" if re.search(r"no\s*cover|istanbul|c8 ignore", text) else "skip/xfail/ignore"
        sev = "FLAG"
        out.append(F("B_SKIP_ADDED" if (is_test and kind != "pragma: no cover") else "B_COVERAGE_EXCLUDED" if kind != "skip/xfail/ignore"
                     else "B_SKIP_ADDED_NONTEST", sev, fd.path, ln, "%s added to existing %s" % (kind, "test" if is_test else "code"), text))
    for ln, text in weak_new:
        out.append(F("B_SUPPRESSION_ADDED", "FLAG", fd.path, ln, "lint/type suppression added to existing line", text))


def _target_name(lines, idx, decorator):
    """For a decorator/inline marker at lines[idx]: the def/it-title it applies to."""
    rng = range(idx + 1, min(len(lines), idx + 12)) if decorator else range(idx, max(-1, idx - 40), -1)
    for i in rng:
        m = re.search(r"\b(?:def|fun|func|function)\s+`?([A-Za-z_]\w*)", lines[i])
        if m:
            return m.group(1)
        m = re.search(r"""(?<![\w$])(?:it|test|describe)\s*(?:\.\s*\w+)?\s*\(\s*["'`]([^"'`]{3,})["'`]""", lines[i])
        if m:
            return m.group(1)
    return None


def _sim(a, b):
    if not a or not b:
        return 0.0
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    if sm.real_quick_ratio() < 0.6 or sm.quick_ratio() < 0.6:
        return 0.0
    return sm.ratio()


def pair_units(old_units, new_units):
    """SequenceMatcher on unit texts -> list of (old_unit, new_unit) for replaced units."""
    a = [u[2] for u in old_units]
    b = [u[2] for u in new_units]
    pairs = []
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "replace":
            for k in range(min(i2 - i1, j2 - j1)):
                pairs.append((old_units[i1 + k], new_units[j1 + k]))
    return pairs


def compare_test(path, qn, o, n, helper_gain, file_units_dropped, out):
    """Compare same-named test old vs new. o/n expose .units .eff .calls .params .line."""
    moved = any(helper_gain.get(c, 0) > 0 for c in n.calls)
    pairs = pair_units(o.units, n.units)
    weak = [(a, b) for a, b in pairs if b[1] < a[1]]
    noop = [(a, b) for a, b in pairs if b[1] == 0 and a[1] > 0]
    if o.eff > 0 and n.eff == 0 and not moved:
        ln = n.line
        out.append(F("E_ZERO_ASSERTS", "FAIL", path, ln, "test %s kept but all %d assertion(s) removed or neutered" % (qn, o.eff),
                     (noop[0][1][2] if noop else "(no assertions left)"), old_line=o.units[0][0] if o.units else None))
        return
    if noop and n.eff < o.eff:
        a, b = noop[0]
        out.append(F("A_ASSERT_NOOP", "FAIL", path, b[0], "assertion in %s replaced by a tautology (was: %s)" % (qn, snip(a[2], 60)),
                     b[2], old_line=a[0]))
        return
    # 2026-10-03 FP (shrike-monitor bd7d0346): `pytest.raises` replaced by three stronger dict asserts after a deliberate contract change. A swap is
    # only a weakening when the test's NET assertion strength is lower: fewer effective assertions OR a lower rank total.
    net_not_lower = n.eff >= o.eff and sum(u[1] for u in n.units) >= sum(u[1] for u in o.units)
    if weak and net_not_lower:
        weak = []
    if weak:
        a, b = weak[0]
        out.append(F("A_ASSERT_WEAKENED", "FLAG", path, b[0], "assertion in %s weakened (rank %d->%d; was: %s)" % (qn, a[1], b[1], snip(a[2], 60)),
                     b[2], old_line=a[0]))
    elif n.eff < o.eff and not moved and file_units_dropped:
        out.append(F("A_ASSERT_DROPPED", "FLAG", path, n.line, "test %s lost %d of %d assertion(s)" % (qn, o.eff - n.eff, o.eff),
                     (o.units[-1][2] if o.units else ""), old_line=o.units[0][0] if o.units else None))
    if o.params and n.params is not None and n.params < o.params:
        out.append(F("A_PARAM_CASES_DROPPED", "FLAG", path, n.line, "test %s parametrize cases %d -> %d" % (qn, o.params, n.params), ""))


def _removed_syms(diffs):
    sym = re.compile(r"\b(?:def|class|function|fun|func|interface|struct|enum)\s+`?([A-Za-z_]\w*)|"
                     r"\b(?:const|let|var|val)\s+([A-Za-z_]\w*)\s*[:=]")
    rem, add = set(), set()
    for fd in diffs.values():
        tst = is_test_path(fd.path) or is_test_path(fd.old)
        for _, t in fd.removed:
            if not tst:
                for m in sym.finditer(t):
                    rem.add(m.group(1) or m.group(2))
        for _, t in fd.added:
            for m in sym.finditer(t):
                add.add(m.group(1) or m.group(2))
    return {s for s in rem - add if len(s) >= 4}


def _stem(path):
    b = os.path.basename(path)
    b = os.path.splitext(b)[0]
    b = re.sub(r"\.(test|spec)$", "", b)
    b = re.sub(r"^test_|_test$|Tests?$|^test", "", b)
    return b.lower()


def _imported_names(text, lang):
    """[(name, module)] imported by `text` (py: from X import a, b ; js: import {a} from 'X')."""
    out = []
    if lang == "py":
        for m in re.finditer(r"^[ \t]*from[ \t]+([\w.]+)[ \t]+import[ \t]+(\([^)]*\)|[^\n]+)", text, re.M):
            for part in m.group(2).strip("()").replace("\\", " ").split(","):
                part = part.strip().split(" as ")[0].strip()
                if re.fullmatch(r"[A-Za-z_]\w*", part):
                    out.append((part, m.group(1)))
    elif lang == "js":
        for m in re.finditer(r"import\s+(?:\w+\s*,\s*)?\{([^}]*)\}\s*from\s*['\"]([^'\"]+)['\"]", text):
            for part in m.group(1).split(","):
                part = part.strip().split(" as ")[0].strip()
                if re.fullmatch(r"[A-Za-z_$][\w$]*", part):
                    out.append((part, m.group(2)))
    return out


def _first_party(repo, lang, mod):
    tree = repo.tree()
    if lang == "py":
        if getattr(repo, "_tops", None) is None:
            tops = set()
            for tp in tree:
                if tp.endswith(".py"):
                    for seg in tp[:-3].split("/"):
                        tops.add(seg)
                    for seg in tp.split("/")[:-1]:
                        tops.add(seg)
            repo._tops = tops
        return mod.split(".")[0] in repo._tops and mod.split(".")[0] not in ("os", "sys", "re", "json", "typing", "pytest", "unittest")
    return mod.startswith((".", "@/"))


def _py_module_exists(repo, mod):
    if getattr(repo, "_pytails", None) is None:
        tails = set()
        for tp in repo.tree():
            if tp.endswith(".py"):
                parts = tp[:-3].split("/")
                if parts[-1] == "__init__":
                    parts = parts[:-1]
                for i in range(len(parts)):
                    tails.add(".".join(parts[i:]))
        repo._pytails = tails
    return (not repo._pytails) or mod in repo._pytails


def dead_reason(repo, lang, old_text, body):
    """A deleted test whose first-party subject is undefined (or has no callers outside tests) at base: deleting it weakens nothing."""
    if lang not in ("py", "js"):
        return None
    used = []
    for nm, mod in _imported_names(old_text, lang):
        if len(nm) >= 3 and _first_party(repo, lang, mod) and re.search(r"\b%s\b" % re.escape(nm), body):
            if lang == "py" and not _py_module_exists(repo, mod):
                return "%s (module %s missing at base)" % (nm, mod)
            used.append(nm)
    used = sorted(set(used))
    for nm in used:
        if repo.defined_in_base(nm, lang) is False:
            return nm
    if used and all(repo.nontest_refs(nm, lang) == 0 for nm in used):
        return used[0] + " (no callers outside tests)"
    return None


def orphan_file_reason(repo, lang, path, old_text):
    """Whole test file: imports a first-party module missing at base, or every first-party name it imports is undefined / has no
    callers outside tests => the file guarded nothing live."""
    tree = repo.tree()
    if not tree or old_text is None or lang not in ("py", "js"):
        return None
    if lang == "py":
        tails = set()
        for tp in tree:
            if tp.endswith(".py"):
                parts = tp[:-3].split("/")
                if parts[-1] == "__init__":
                    parts = parts[:-1]
                for i in range(len(parts)):
                    tails.add(".".join(parts[i:]))
        tops = {t.split(".")[0] for t in tails}
        for m in re.finditer(r"^[ \t]*(?:from|import)[ \t]+([A-Za-z_][\w.]*)", old_text, re.M):
            mod = m.group(1)
            if mod.split(".")[0] in tops and mod not in tails and _first_party(repo, lang, mod):
                return mod
    else:
        d = os.path.dirname(path)
        for m in re.finditer(r"""(?:from|import|require\()\s*['"]((?:\.{1,2}/|@/)[^'"]+)['"]""", old_text):
            spec = m.group(1)
            exts = ["", ".ts", ".tsx", ".js", ".jsx", ".vue", ".mjs", "/index.ts", "/index.js", "/index.vue"]
            if spec.startswith("."):
                base = os.path.normpath(os.path.join(d, spec))
                ok = any(base + e in tree for e in exts)
            else:
                rest = spec[2:]
                ok = any(("src/" + rest + e) in tree or any(tp.endswith("/src/" + rest + e) for tp in tree) for e in exts)
            if not ok and not spec.endswith((".css", ".scss", ".json", ".svg", ".png")):
                return spec
    names = sorted({nm for nm, mod in _imported_names(old_text, lang) if len(nm) >= 3 and _first_party(repo, lang, mod)})
    if names and all(repo.defined_in_base(nm, lang) is False or repo.nontest_refs(nm, lang) == 0 for nm in names):
        return "all imported subjects dead (%s)" % names[0]
    return None


PLACEHOLDER_RE = re.compile(r"placeholder|\bTODO\b.{0,40}\b(?:test|assert)|replace with (?:actual|real)|to be implemented|not implemented", re.I)


def _only_trivial_body(lang, src):
    """True when the test body makes no call (so 'placeholder'/'TODO' text can be trusted): a test that calls helpers (`check_response(f())  # TODO: add test`)
    is under-detected, not a placeholder. Comments and string literals are masked first; js/kt/swift look only after the first '{'."""
    if lang == "py":
        try:
            fn = ast.parse(textwrap.dedent(src)).body[0]
            return not any(isinstance(n, ast.Call) for x in fn.body for n in ast.walk(x))
        except (SyntaxError, IndexError, ValueError, AttributeError):
            return False
    inner = mask_text(src, lang)
    i = inner.find("{")
    return i >= 0 and not re.search(r"\b\w+\s*\(", inner[i + 1:])


def vacuous_new_test(lang, t):
    """Reason string when a NEWLY ADDED test `t` (FuncInfo/TInfo: .units .eff .src) cannot fail, else ''.
      * it has assertions and EVERY one is a tautology (`assert True`, `assert 1 == 1`, `assert x or True`, `assert_true(true)`, `assert(true)`), or
      * it has NO assertion and its body is a placeholder (pass / ... / docstring-only / empty block, or says 'placeholder').
    A test that only asserts through helpers it calls (no recognised assertion, real body) is NOT judged: that is an under-detection, not a proof."""
    if t.units:
        if all(u[1] == 0 for u in t.units):
            return "all %d assertion(s) are tautologies (%s)" % (len(t.units), snip(t.units[0][2], 50))
        return ""
    src = t.src or ""
    if PLACEHOLDER_RE.search(src) and _only_trivial_body(lang, src):
        return "no assertion and the body says it is a placeholder"
    body = src
    if lang == "py":
        try:
            fn = ast.parse(textwrap.dedent(src)).body[0]
            stmts = [x for x in fn.body if not (isinstance(x, ast.Expr) and isinstance(x.value, ast.Constant) and isinstance(x.value.value, str))]
            if all(isinstance(x, ast.Pass) or (isinstance(x, ast.Expr) and isinstance(x.value, ast.Constant)) for x in stmts):
                return "no assertion and the body is empty (pass / ... / docstring only)"
        except (SyntaxError, IndexError, ValueError, AttributeError):
            return ""
        return ""
    if lang in ("js", "kt", "swift"):
        inner = mask_text(body, lang)
        if lang in ("kt", "swift"):  # src is the body from its '{' up to (excluding) the closing '}'
            if inner.lstrip().startswith("{") and not inner.lstrip()[1:].strip():
                return "no assertion and the body is empty"
        else:
            m = re.search(r"\{(.*)\}\s*\)?\s*;?\s*$", inner, re.S)
            if m is not None and not m.group(1).strip():
                return "no assertion and the body is empty"
    return ""


def analyze_tests(repo, diffs, status, out, deadline, notes):
    """A + E for every changed test file (all languages)."""
    removed_syms = _removed_syms(diffs)
    deleted_nontest_stems = {_stem(p) for p, s in status.items() if s == "D" and not is_test_path(p)}
    deleted_nontest_stems.discard("")
    deleted_modules = set()
    for dp, ds in status.items():
        if ds == "D" and dp.endswith(".py") and not is_test_path(dp):
            parts = dp[:-3].split("/")
            for i in range(len(parts) - 1):
                deleted_modules.add(".".join(parts[i:]))
    old_tests, new_tests = {}, {}  # path -> {qual: info}
    helper_old, helper_new = {}, {}
    for p, st in status.items():
        lang = lang_of(p)
        if not lang or not is_test_path(p) or ignorable(p):
            continue
        fd = diffs.get(p)
        oldp = fd.old if fd else p
        o_txt = repo.blob(repo.base, oldp) if st in ("M", "D", "R") else None
        n_txt = repo.blob(repo.head, p) if st in ("M", "A", "R") else None
        if (st in ("M", "D", "R") and o_txt is None) or (st in ("M", "A", "R") and n_txt is None):
            repo.unanalysed.append("test file %s unreadable or over %d bytes" % (p, MAX_BLOB))
            notes.append("blob-skip %s" % p)
            continue
        try:
            if lang == "py":
                om = PyModule(o_txt) if o_txt is not None else None
                nm = PyModule(n_txt) if n_txt is not None else None
                old_tests[p] = om.tests() if om else {}
                new_tests[p] = nm.tests() if nm else {}
                helper_old[p] = {q.split(".")[-1]: f.eff for q, f in om.funcs.items()} if om else {}
                helper_new[p] = {q.split(".")[-1]: f.eff for q, f in nm.funcs.items()} if nm else {}
            else:
                old_tests[p] = extract_tests_text(lang, o_txt) if o_txt is not None else {}
                new_tests[p] = extract_tests_text(lang, n_txt) if n_txt is not None else {}
                helper_old[p], helper_new[p] = {}, {}
        except (SyntaxError, ValueError, RecursionError) as ex:
            notes.append("parse-skip %s: %s" % (p, type(ex).__name__))
            repo.unanalysed.append("test file %s could not be parsed" % p)
            old_tests.pop(p, None)
            new_tests.pop(p, None)
            continue
        if time.time() > deadline:
            notes.append("deadline during test analysis")
            repo.unanalysed.append("deadline during test analysis")
            break
    # vacuous assertions that are NEW (a brand-new or edited test whose assertion can never fail)
    for p, nt in new_tests.items():
        for q, n in nt.items():
            o = old_tests.get(p, {}).get(q)
            if o is None and any(q in ot for ot in old_tests.values()):
                o = next(ot[q] for ot in old_tests.values() if q in ot)   # moved/renamed test file: the test is not new
            if o is None:
                why = vacuous_new_test(lang_of(p), n)
                if why:  # A_VACUOUS (FAIL): 3 of 3 true positives in the 2026-10-03 shadow data; supersedes the weaker A_VACUOUS_ASSERT for this test
                    out.append(F("A_VACUOUS", "FAIL", p, n.units[0][0] if n.units else n.line,
                                 "newly added test %s proves nothing: %s" % (q, why), n.units[0][2] if n.units else ""))
                    continue
            old_zero = {u[2] for u in o.units if u[1] == 0} if o else set()
            zeros = [u for u in n.units if u[1] == 0 and u[2] not in old_zero]
            if o and len(zeros) <= sum(1 for u in o.units if u[1] == 0):
                zeros = []  # the test already carried this many vacuous assertions (pre-existing, merely edited)
            if not zeros:
                continue
            if any(f["file"] == p and f["rule"] in ("E_ZERO_ASSERTS", "A_ASSERT_NOOP") and q in f["msg"] for f in out):
                continue
            out.append(F("A_VACUOUS_ASSERT", "FLAG", p, zeros[0][0], "test %s has %d assertion(s) that can never fail (tautology, constant, "
                         "self-comparison or swallowed)" % (q, len(zeros)), zeros[0][2]))
    # pool of tests that exist only in the new side (for rename detection)
    added_pool = []
    for p, nt in new_tests.items():
        for q, ti in nt.items():
            if q not in old_tests.get(p, {}):
                added_pool.append(ti)
    all_new_names = {q.split(" > ")[-1] for nt in new_tests.values() for q in nt}
    for p in sorted(old_tests):
        ot, nt = old_tests[p], new_tests.get(p, {})
        st = status[p]
        gain = {k: helper_new[p].get(k, 0) - helper_old[p].get(k, 0) for k in helper_new[p]}
        tot_old = sum(t.eff for t in ot.values())
        tot_new = sum(t.eff for t in nt.values())
        dropped_file = tot_new < tot_old
        deleted = []
        for q, o in ot.items():
            n = nt.get(q)
            if n is None:
                deleted.append((q, o))
            elif st != "D":
                compare_test(p, q, o, n, gain, dropped_file, out)
        # deleted tests
        gone = []
        for q, o in deleted:
            if o.eff == 0:
                continue
            if q.split(" > ")[-1] in all_new_names:
                continue
            if re.sub(r"#\d+$", "", q) in {re.sub(r"#\d+$", "", k) for k in nt}:
                continue  # a same-named copy remains: the deleted one was a duplicate
            if any(_sim(o.norm, a.norm) >= 0.75 for a in added_pool) or any(
                    o.units and [u[2] for u in o.units] == [u[2] for u in a.units] for a in added_pool):
                continue
            # duplicate of a test that remains in the same file (dedupe), or a test that was already dead
            if any(o.units and [u[2] for u in o.units] == [u[2] for u in t.units] for t in nt.values()) or any(
                    _sim(o.norm, t.norm) >= 0.9 for t in nt.values()):
                continue
            fd0 = diffs.get(p)
            old_blob = repo.blob(repo.base, fd0.old if fd0 else p)
            if old_blob is not None and dead_reason(repo, lang_of(p), old_blob, o.src):
                continue
            body = o.src
            if any(re.search(r"\b%s\b" % re.escape(s), body) for s in removed_syms):
                continue  # subject removed in the same diff
            if any(m in body for m in deleted_modules):
                continue  # test of a module that is deleted in the same diff
            if p.endswith(".py") and deleted_modules:
                oldb = repo.blob(repo.base, (diffs.get(p).old if diffs.get(p) else p))
                if oldb and any(any(mod.endswith(dm) for dm in deleted_modules) for mod in re.findall(
                        r"^[ \t]*(?:from|import)[ \t]+([\w.]+)", oldb, re.M)):
                    continue  # the test file imports a module deleted in the same diff
            gone.append((q, o))
        if gone:
            subj = _stem(p)
            if st == "D" or not nt:  # file deleted, or emptied of every test
                fd0 = diffs.get(p)
                if orphan_file_reason(repo, lang_of(p), p, repo.blob(repo.base, fd0.old if fd0 else p)):
                    continue
            if (st == "D" or not nt) and (subj in deleted_nontest_stems or any(subj and subj in s for s in deleted_nontest_stems)):
                continue
            if st == "D":
                out.append(F("A_TESTFILE_DELETED", "FLAG", p, 1, "test file deleted (%d test(s) with assertions: %s) and its subject was not deleted"
                             % (len(gone), ", ".join(short(q) for q, _ in gone[:3])), ""))
            elif nt and not dropped_file and len(nt) >= len(ot) - len(gone) + 1:
                # tests were rewritten/renamed: the file still has at least as many effective assertions as before and gained tests
                notes.append("offset-deletion %s: %d test(s) replaced, file assertions %d -> %d" % (p, len(gone), tot_old, tot_new))
            else:
                q, o = gone[0]
                out.append(F("A_TEST_DELETED", "FLAG", p, o.line, "%d test(s) with assertions deleted and not found elsewhere: %s"
                             % (len(gone), ", ".join(short(q) for q, _ in gone[:4])), "", old_line=o.line))


def _guard_regex_counts(lines):
    t = c = r = 0
    for _, s in lines:
        if re.match(r"\s*(?:\}\s*)?try\b", s):
            t += 1
        if re.search(r"\bcatch\b\s*[({]|\.catch\s*\(|\bexcept\b[^\n]*:\s*$", s):
            c += 1
        if re.search(r"\bthrow\b|\brequire(?:NotNull)?\s*\(|\bcheckNotNull\s*\(|\braise\s", s):
            r += 1
    return t, c, r


def _guard_sigs(text):
    """(signature, line) for every try/catch line: normalized line + next non-blank line (so a moved/duplicated guard keeps its
    signature but an unwrapped one - same body, no try above it - loses it)."""
    lines = text.split("\n")
    out = []
    for i, l in enumerate(lines):
        if re.match(r"\s*(?:\}\s*)?try\b", l) or re.search(r"\bcatch\b\s*[({]|\.catch\s*\(", l):
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            out.append((_norm_line(l) + " || " + (_norm_line(lines[j]) if j < len(lines) else ""), i + 1, l))
    return out


def rule_error_handling(repo, fd, old_text, new_text, added_all, out, notes, added_guard_total=None, removed_guard_total=0):
    """C: error handling / validation deleted or narrowed in NON-test files."""
    lang = lang_of(fd.path)
    if old_text is None or new_text is None or not new_text.strip():
        return  # (a file emptied to nothing is a module removal, not an error-handling edit)
    if lang == "py":
        try:
            om, nm = PyModule(old_text), PyModule(new_text)
        except (SyntaxError, RecursionError):
            notes.append("c-regex-fallback %s" % fd.path)
            om = nm = None
        if om is not None:
            for q, of in om.funcs.items():
                nf = nm.funcs.get(q)
                if nf is None or nf.uses_suppress:
                    continue
                # a newly called module function that itself has try/except = the guard was delegated, not dropped
                delegated = any(nm.funcs[c].tries > 0 for c in _new_callees(nm, nf, of))
                # 2026-10-02: a raise that MOVED into a helper (same module, or a helper newly defined elsewhere in this diff) is delegated, not dropped.
                # Real false positive: billwatch get_current_user's inline 'raise HTTPException(401 inactive)' became check_user_active(user), moved to
                # core/dependencies.py in the same change.
                new_names = (nf.calls | nf.names) - (of.calls | of.names)
                delegated_raise = any(nm.funcs[c].raises > 0 for c in _new_callees(nm, nf, of)) or (
                    any(re.match(r"(?:async\s+)?def\s+%s\s*\(" % re.escape(n), l) for n in new_names for l in added_all)
                    and any(re.match(r"raise\b", l) for l in added_all))
                widened = _handlers_widened(of, nf)  # 2026-10-03 FP: `except ValueError` -> `except (ValueError, TypeError)` (+ new isinstance guards)
                if nf.tries < of.tries and nm.file_tries < om.file_tries and not delegated and not widened:
                    ol = of.try_lines[0] if of.try_lines else of.line
                    out.append(F("C_ERRORHANDLING_REMOVED", "FLAG", fd.path, nf.line,
                                 "%s lost %d try/except guard(s) (%d -> %d)" % (q, of.tries - nf.tries, of.tries, nf.tries),
                                 _first_removed_try(fd, of), old_line=ol))
                elif nf.tries == of.tries and of.tries and nf.handler_breadth < of.handler_breadth and nm.file_tries <= om.file_tries:
                    out.append(F("C_HANDLER_NARROWED", "FLAG", fd.path, nf.line,
                                 "%s: exception handler narrowed (breadth %d -> %d)" % (q, of.handler_breadth, nf.handler_breadth),
                                 _first_removed_try(fd, of), old_line=of.line))
                delegated_dep = bool(nf.deps - of.deps)  # 2026-10-03 FP: inline 401/403 raises replaced by `Depends(require_admin)`
                if nf.raises < of.raises and nm.file_raises < om.file_raises and not (nf.tries > of.tries) and not delegated and not delegated_raise \
                        and not delegated_dep \
                        and _sim(of.norm, nf.norm) >= 0.7:  # surgical edit; a wholesale rewrite of the function is not judged here
                    out.append(F("C_VALIDATION_REMOVED", "FLAG", fd.path, nf.line,
                                 "%s lost %d raise statement(s) (%d -> %d)" % (q, of.raises - nf.raises, of.raises, nf.raises), "",
                                 old_line=of.line))
            return
    if lang in ("js", "kt", "swift"):
        from collections import Counter
        so, sn = _guard_sigs(old_text), _guard_sigs(new_text)
        lost = Counter(x[0] for x in so) - Counter(x[0] for x in sn)
        # raw try/catch line counts must also have gone DOWN (a pure move/duplicate/refactor keeps or raises them)
        if lost and len(sn) < len(so) and not (added_guard_total is not None and added_guard_total >= removed_guard_total):
            ev = next(x for x in so if x[0] in lost)
            out.append(F("C_ERRORHANDLING_REMOVED", "FLAG", fd.path, ev[1], "try/catch removed (%d -> %d guard lines)" % (len(so), len(sn)),
                         ev[2], old_line=ev[1]))
        return
    if lang == "py":  # syntax-error fallback
        rem = [(ln, t) for ln, t in fd.removed if t.strip() and _norm_line(t) not in added_all]
        rt, rc, rr = _guard_regex_counts(rem)
        at, ac, ar = _guard_regex_counts(list(fd.added))
        if rc > ac:
            ev = next(((ln, t) for ln, t in rem if "except" in t), rem[0])
            out.append(F("C_ERRORHANDLING_REMOVED", "FLAG", fd.path, ev[0], "except clause removed (regex fallback)", ev[1], old_line=ev[0]))


def _new_callees(nm, nf, of):
    """Names of module-level/same-class functions that nf calls now but of did not."""
    by_last = {}
    for q, f in nm.funcs.items():
        by_last.setdefault(q.split(".")[-1], q)
    return [by_last[c] for c in ((nf.calls | nf.names) - (of.calls | of.names)) if c in by_last and by_last[c] != nf.qual]


CLAIM_RE = re.compile(r"^(feat|fix|perf|refactor)(\([^)]*\))?!?:\s*(.*)$", re.I)
# any 'test' substring (test_x.py, FavoritesRepositoryTest, tests, testing) or spec/fixture/mock/coverage/flaky = the subject itself says it is a test change.
# AUTO_RE: the pipeline's own test-first scaffolding ('staged step N', 'repair staged item') - a step that only adds tests is normal there; the code lands in a later step.
TESTY_RE = re.compile(r"test|\bspecs?\b|fixtures?|mocks?|coverage|flak(?:y|e|iness)", re.I)
AUTO_RE = re.compile(r"staged step \d+|repair staged item", re.I)


ASSERTY_RE = re.compile(r"\bassert|\bexpect\b|\bverify\b|\bshould|XCTAssert|\bfail\s*\(|\braises\b|\bpush_error\b|"
                        r"\b(?:def|func|fun)\s+test|\b(?:it|test|describe)\s*\(|@Test\b|\.toBe|\.toEqual|\.to[A-Z]\w+\(|\bmock\.|\bpatch\b")


LITERAL_LINE_RE = re.compile(r"""(?<![\w.])\d+(?:\.\d+)?(?![\w.])|["']""")


def _subject_names_files(subject, tpaths):
    """True when the commit subject names (full path or basename; NOT a bare stem like `models`) one of the touched test files."""
    sl = subject.lower()
    for t in tpaths:
        base = os.path.basename(t).lower()
        stem = os.path.splitext(base)[0]
        if t.lower() in sl or base in sl:
            return True
    return False


def _support_only_test_change(rd, sha, tpaths):
    """True when the commit's diff of its test files adds/removes no assertion-ish line and no test definition (comments/blank ignored):
    a helper / resource-cleanup / fixture-plumbing edit (xlite 8da3d53f 'fix: free DirAccess' only added `dir.free()` to a test helper)."""
    if not tpaths:
        return False
    rc, out, _ = qc.git(rd, "show", "-U0", "--no-color", "--format=", sha, "--", *tpaths, timeout=60)
    if rc != 0 or not out.strip():
        return False
    changed = 0
    for l in out.splitlines():
        if l[:1] not in ("+", "-") or l.startswith(("+++", "---")):
            continue
        body = l[1:].strip()
        if not body or body.startswith(("#", "//", "/*", "*")):
            continue
        changed += 1
        if ASSERTY_RE.search(body) or LITERAL_LINE_RE.search(body):   # an expected-value/fixture literal edit (`EXPECTED = 200` -> 500) changes what a test proves
            return False
    return changed > 0


def rule_claim_vs_diff(rd, base, head, findings):
    """F: a commit whose conventional-commit subject claims PRODUCT behaviour (feat/fix/perf/refactor) but whose diff touches only test files.
    2026-10-02 real incident: iptv e590eef7 'fix: respect RATE_LIMIT_ENABLED env var in limiter initialization' changed only tests/test_limiter_core.py;
    limiter.py never read the variable, and the next commit rewrote the test to assert just the default. A subject that itself says it is a test
    change ('update limiter test ...') is honest and skipped; docs-only and test:/chore: commits are not this rule's business. Advisory FLAG only."""
    rc, out, _ = qc.git(rd, "log", "--no-merges", "--format=%x1e%H%x1f%s", "--name-only", "%s..%s" % (base, head), timeout=60)
    if rc != 0:
        return
    for block in out.split("\x1e"):
        block = block.strip("\n")
        if not block:
            continue
        head_line, _, files = block.partition("\n")
        sha, _, subj = head_line.partition("\x1f")
        m = CLAIM_RE.match(subj.strip())
        if not m or TESTY_RE.search(m.group(3)) or AUTO_RE.search(subj):
            continue
        paths = [l.strip() for l in files.split("\n") if l.strip()]
        if not paths or not any(is_test_path(x) for x in paths):
            continue
        if any(not (is_test_path(x) or x.lower().endswith((".md", ".txt", ".rst"))) for x in paths):
            continue
        tpaths = [x for x in paths if is_test_path(x)]
        if _subject_names_files(m.group(3), tpaths):
            continue  # 'fix: handle X in tests/test_x.py': the named file IS the test, so a test-only diff is what the subject says
        if _support_only_test_change(rd, sha, tpaths):
            continue  # helper/resource fix inside a test file (no assertion or test definition touched): there is no product claim to fake
        findings.append(F("F_CLAIM_TEST_ONLY", "FLAG", "(commit %s)" % sha[:10], 0,
                          "'%s' claims product behaviour but the commit changes only test files: %s" % (subj.strip()[:80], ", ".join(paths[:3]))))


def _first_removed_try(fd, of):
    for ln, t in fd.removed:
        if re.match(r"\s*(try:|except\b)", t):
            return t
    return ""


COV_RE = re.compile(r"(?:fail[_-]under|cov-fail-under|coverageThreshold)\D{0,40}?(\d{1,3})")


def rule_config(repo, fd, old_text, new_text, out):
    base = os.path.basename(fd.path)
    if base not in CONFIG_NAMES or new_text is None:
        return
    for ln, t in fd.added:
        if re.search(r"--(?:ignore|deselect)\b|norecursedirs|--ignore-glob|(?:^|\s)-k\s*['\"]?\s*not\b|(?:^|\s)-m\s*['\"]?\s*not\b|"
                     r"--maxfail|-p\s+no:|testpaths|--collect-only|\bexit-zero|continue-on-error", t):
            out.append(F("F_TESTS_EXCLUDED", "FLAG", fd.path, ln, "test config now ignores/deselects/narrows tests", t))
    olds = [int(m.group(1)) for _, t in fd.removed for m in [COV_RE.search(t)] if m]
    news = [int(m.group(1)) for _, t in fd.added for m in [COV_RE.search(t)] if m]
    if olds and news and min(news) < max(olds):
        ln = next((l for l, t in fd.added if COV_RE.search(t)), 1)
        out.append(F("F_COVERAGE_LOWERED", "FLAG", fd.path, ln, "coverage threshold lowered %d -> %d" % (max(olds), min(news)), ""))


def rule_frozen(repo_name, status, diffs, repo, out):
    """D: returns a string describing the check state (NA / checked N)."""
    p = os.path.join(qc.state_dir(), "qa_frozen_tests.json")
    try:
        with open(p) as f:
            man = json.load(f)
    except (OSError, ValueError):
        return "NA: no manifest"
    entry = man.get(repo_name) if isinstance(man, dict) else None
    if not isinstance(entry, dict) or not entry:
        return "NA: repo not in manifest"
    n = 0
    touched = set(status)
    for fd in diffs.values():
        touched.add(fd.old)
    for path in sorted(touched):
        if path not in entry:
            continue
        n += 1
        want = str(entry[path]).lower().replace("sha256:", "")
        txt = repo.blob(repo.head, path) if status.get(path) != "D" else None
        # re-read bytes-exact for hashing
        try:  # bytes-exact: qc.git decodes with errors=replace, which would corrupt the hash of non-UTF-8 files
            pr = subprocess.run(["git", "-C", repo.rd, "show", "%s:%s" % (repo.head, path)], capture_output=True, timeout=60)
            rc, got = pr.returncode, (hashlib.sha256(pr.stdout).hexdigest() if pr.returncode == 0 else None)
        except (OSError, subprocess.TimeoutExpired):
            out.append(F("D_FROZEN_UNREADABLE", "FLAG", path, 1, "could not read frozen file at head (infra) - not treated as an edit", ""))
            continue
        if rc != 0 or status.get(path) == "D":
            out.append(F("D_FROZEN_EDIT", "FAIL", path, 1, "frozen test file deleted or renamed", ""))
        elif got != want:
            ln = next((l for l, _ in diffs[path].added), 1) if path in diffs and diffs[path].added else 1
            out.append(F("D_FROZEN_EDIT", "FAIL", path, ln, "frozen test file modified (sha256 differs from manifest)", ""))
    return "checked %d frozen path(s) in diff" % n


# ------------------------------------------------------------------------------------------------------------------
# entry
# ------------------------------------------------------------------------------------------------------------------
def name_status(rd, base, head):
    rc, out, err = qc.git(rd, "-c", "core.quotepath=false", "diff", "--name-status", "-M", "-z", "%s..%s" % (base, head), timeout=120)
    if rc != 0:
        return None
    toks = out.split("\0")
    st = {}
    i = 0
    while i < len(toks) and toks[i]:
        code = toks[i][0]
        if code in "RC":
            st[toks[i + 2]] = "R"
            st["\0old:" + toks[i + 2]] = toks[i + 1]
            i += 3
        else:
            st[toks[i + 1]] = code
            i += 2
    return st


def check(argv):
    args = {"repo": None, "base": None, "head": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--repo", "--base", "--head") and i + 1 < len(argv):
            args[a[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    if not argv or argv[0] != "check" or not all(args.values()):
        return qc.verdict("UNVERIFIED", GATE, args["repo"] or "?", "?", "usage: gate_antigaming.py check --repo R --base B --head H")
    t0 = time.time()
    deadline = t0 + float(os.environ.get("QA_ANTIGAMING_DEADLINE", "40"))
    name = args["repo"]
    rd = name if os.path.isdir(name) else qc.repo_dir(name)
    name = os.path.basename(name.rstrip("/")) if os.path.isdir(name) else name
    ref = "%s..%s" % (args["base"], args["head"])
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "no clone found for repo")
    shas = []
    qc.ensure_commits(rd, (args["base"], args["head"]), wait=float(os.environ.get("QA_FETCH_WAIT", "15")))
    for r in (args["base"], args["head"]):
        rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")
        if rc != 0:
            return qc.verdict("UNVERIFIED", GATE, name, ref, "cannot resolve ref %s" % r)
        shas.append(out.strip())
    base, head = shas
    repo = Repo(rd, base, head)
    st_raw = name_status(rd, base, head)
    if st_raw is None:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "git diff --name-status failed")
    status = {k: v for k, v in st_raw.items() if not k.startswith("\0old:")}
    if not status:
        return qc.verdict("NA", GATE, name, ref, "empty diff", {"files": 0})
    rc, dtext, _ = qc.git(rd, "-c", "core.quotepath=false", "diff", "-U0", "--no-color", "-M", "--src-prefix=a/", "--dst-prefix=b/",
                          "%s..%s" % (base, head), timeout=120)
    if rc != 0:
        return qc.verdict("UNVERIFIED", GATE, name, ref, "git diff failed")
    diffs = parse_diff(dtext)
    for k, fd in diffs.items():
        if status.get(k) == "R":
            fd.old = st_raw.get("\0old:" + k, fd.old)
        fd.status = status.get(k, "M")
    for k, v in status.items():
        if v == "R" and k in diffs:
            diffs[k].old = st_raw.get("\0old:" + k, diffs[k].old)
    findings, notes = [], []
    truncated = False
    if len(status) > MAX_FILES:
        truncated = True
        notes.append("%d files in diff; analysing the first %d code files" % (len(status), MAX_FILES))
    # D: frozen tests (independent of language)
    frozen = rule_frozen(name, status, diffs, repo, findings)
    # A/E: tests
    code_status = {p: s for p, s in status.items() if lang_of(p) and not ignorable(p)}
    if len(code_status) > MAX_FILES:
        repo.unanalysed.append("%d code files in diff; only the first %d analysed" % (len(code_status), MAX_FILES))
        code_status = dict(list(code_status.items())[:MAX_FILES])
    analyze_tests(repo, diffs, code_status, findings, deadline, notes)
    # B, C, F per file
    added_all = set()
    for fd in diffs.values():
        for _, t in fd.added:
            added_all.add(_norm_line(t))
    ag_add = ag_rem = 0  # diff-wide try/catch line balance over non-test regex-language files (a guard moved to a helper nets 0)
    for p2, s2 in code_status.items():
        fd2 = diffs.get(p2)
        if fd2 and not is_test_path(p2) and lang_of(p2) in ("js", "kt", "swift"):
            ag_rem += sum(1 for _, t in fd2.removed if re.match(r"\s*(?:\}\s*)?try\b", t) or re.search(r"\bcatch\b\s*[({]|\.catch\s*\(", t))
            ag_add += sum(1 for _, t in fd2.added if re.match(r"\s*(?:\}\s*)?try\b", t) or re.search(r"\bcatch\b\s*[({]|\.catch\s*\(", t))
    for p, s in code_status.items():
        if time.time() > deadline:
            notes.append("deadline during B/C rules")
            repo.unanalysed.append("deadline during B/C rules")
            truncated = True
            break
        fd = diffs.get(p)
        if not fd:
            continue
        oldp = fd.old or p
        o_txt = repo.blob(base, oldp) if s in ("M", "R") else None
        n_txt = repo.blob(head, p) if s in ("M", "A", "R") else None
        if p in repo.oversize or oldp in repo.oversize:
            repo.unanalysed.append("file %s over %d bytes" % (p, MAX_BLOB))
        tst = is_test_path(p)
        rule_suppressions(repo, fd, o_txt, n_txt, tst, findings)
        if not tst and s in ("M", "R"):
            rule_error_handling(repo, fd, o_txt, n_txt, added_all, findings, notes, ag_add, ag_rem)
    for p, s in status.items():
        if os.path.basename(p) in CONFIG_NAMES and s in ("M", "R") and p in diffs:
            rule_config(repo, diffs[p], None, repo.blob(head, p), findings)
    rule_claim_vs_diff(rd, base, head, findings)
    # 2026-10-04 audit rules (qa/ag_h13.py): D_DEAD_SYMBOL, E_TEST_NOT_COLLECTED, F_REVERT_OF_RECENT, D_FROZEN_EDIT/NEWFILE (vendored paths),
    # C_FILE_DELETED_LIVE, C_TEST_ORPHANED, A_MOCK_ONLY, A_MIRROR_EXPECTED. OVN_QA_AG_H13=off disables them. Isolated: an error becomes a note.
    if os.environ.get("OVN_QA_AG_H13", "on") != "off":
        try:
            import ag_h13
            fz = ag_h13.run_all(repo, name, status, st_raw, diffs, findings, notes,
                                max(deadline, time.time()) + float(os.environ.get("QA_AG_H13_BUDGET", "40")), "--no-record" in argv)
            if frozen.startswith("NA") and not fz.startswith("NA"):
                frozen = fz
        except Exception as ex:  # noqa: BLE001
            notes.append("ag_h13 failed to run: %s: %s" % (type(ex).__name__, str(ex)[:80]))
    # assemble
    order = {"FAIL": 0, "FLAG": 1}
    findings.sort(key=lambda f: (order[f["sev"]], f["file"], f["line"]))
    counts = {}
    for f in findings:
        counts[f["rule"]] = counts.get(f["rule"], 0) + 1
    details = {"files_in_diff": len(status), "code_files": len(code_status), "frozen": frozen, "counts": counts,
               "findings": findings[:MAX_FINDINGS], "notes": notes[:10], "truncated": truncated or len(findings) > MAX_FINDINGS}
    if any(f["sev"] == "FAIL" for f in findings):
        v = "FAIL"
    elif findings:
        v = "FLAG"
    elif repo.unanalysed or (truncated and time.time() > deadline):
        why = sorted(set(repo.unanalysed))[:3] or ["deadline reached before analysis finished"]
        details["unanalysed"] = why
        return qc.verdict("UNVERIFIED", GATE, name, ref, "part of the diff could not be analysed and nothing was found in the rest: %s" % "; ".join(why), details)
    elif not code_status and frozen.startswith("NA"):
        v = "NA"
    else:
        v = "PASS"
    if repo.unanalysed:
        details["unanalysed"] = sorted(set(repo.unanalysed))[:5]
        notes.append("UNANALYSED (verdict covers only the analysed part): " + "; ".join(details["unanalysed"][:3]))
        details["notes"] = notes[:10]
    if findings:
        top = "; ".join("%s %s:%s" % (f["rule"], f["file"], f["line"]) for f in findings[:3])
        summ = "%d finding(s) [%s]: %s" % (len(findings), ",".join("%s=%d" % kv for kv in sorted(counts.items())), top)
    else:
        summ = "no oracle weakening or safety removal found in %d code file(s)" % len(code_status)
    return qc.verdict(v, GATE, name, ref, summ, details)


if __name__ == "__main__":
    sys.exit(qc.main_guard(GATE, check, sys.argv[1:]))
