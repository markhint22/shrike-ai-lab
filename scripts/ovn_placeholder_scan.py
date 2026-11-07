#!/usr/bin/env python3
"""ovn_placeholder_scan.py <path> <placeholder text>   (file content on stdin)

Prints `real` or `stub`. Used by lib_auto_credit.sh ovn_ac_is_placeholder (package Z1 / Z1 review-fix rounds 1 and 2).

The placeholder text is removed FIRST (replaced by nothing, so a docstring/comment/line that carried it stays well formed). A TEST file (by basename, per language:
py, ts/js spec, gd, kt, swift, go, java, rs-in-tests/) is `real` only when it holds a non-skipped, reachable test function that contains a REAL assertion. Other files are `real`
when >= OVN_AC_PLACEHOLDER_REAL_LINES (default 3) substantive lines remain once comments/docstrings/strings are removed.

How a test file is judged (round 2):
  * python: parsed with the ast module (no regex over raw text). Test functions (module level and in classes, async too) with skip decorators (multi-line included), skipped classes,
    `pytestmark = pytest.mark.skip`, `__test__ = False`, dead code (`if False:`, `while 0:`, after return/raise/pytest.skip(), never-called nested defs) are ignored. A real assertion is an
    `assert` whose test is not constant/tautological (no names or calls at all, identical operands without a call, `x or True`, a non-empty tuple, isinstance(<const>, ..)), a
    pytest.raises/warns/self.assertRaises context manager, or an assert*(...) call whose compared arguments are not constants / identical. Unparseable source falls back to the line heuristic
    run over comment/string-stripped text.
  * ts/js, kotlin, swift, java, go, rust, gdscript: comments AND string/template literals are blanked by a small tokenizer before anything is matched (positions preserved, so the original
    argument text is still available for the tautology check). Skipped regions (it.skip/describe.skip/xit/@Ignore/@Disabled/#[ignore]/@Test(.disabled)/t.Skip/XCTSkip, `if (false) {}`) are blanked.
  * tautologies are NOT real in every language: assertEquals(1, 1), expect(x).toBe(x), expect(true).toBe(true), assert_eq(1,1), XCTAssertEqual(1, 1), assertTrue(true), assert!(true) ...
Residual gaming that is accepted is listed in docs/VERIFY_LINT_Z1_2026-11-07.md.
"""
import ast
import os
import re
import sys

path, ph = sys.argv[1], sys.argv[2]
MIN = int(os.environ.get("OVN_AC_PLACEHOLDER_REAL_LINES", "3") or 3)
src = sys.stdin.read().replace(ph, "") if ph else sys.stdin.read()
base = os.path.basename(path)
ext = os.path.splitext(base)[1].lower()


# ============================ tokenizer: blank comments and string contents ============================
_CFG = {
    #        line comment, block comment (nested?), triple quote, quote chars, backtick mode
    "py": ("#", None, True, "'\"", None),
    "gd": ("#", None, True, "'\"", None),
    "ts": ("//", False, False, "'\"`", "string"),
    "kt": ("//", True, True, "\"'", "ident"),
    "swift": ("//", True, True, "\"", "ident"),
    "java": ("//", False, True, "\"'", None),
    "go": ("//", False, False, "\"'", "string"),
    "rs": ("//", True, False, "\"", None),
}


def blank_src(text, lang):
    """-> (code, nostr). Same length as `text`, newlines kept. `code`: comments and string contents blanked (delimiters kept). `nostr`: comments blanked, strings kept."""
    lc, blk, tri, quotes, bt = _CFG[lang]
    n = len(text)
    code = list(text)
    ns = list(text)
    i = 0

    def blank(a, b, both):
        for k in range(a, b):
            if text[k] != "\n":
                code[k] = " "
                if both:
                    ns[k] = " "

    while i < n:
        c = text[i]
        if text.startswith(lc, i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j, True)
            i = j
            continue
        if blk is not None and text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if blk and text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j, True)
            i = j
            continue
        if c == "`" and bt:
            j = text.find("`", i + 1)
            j = n if j < 0 else j
            if bt == "ident":
                for k in range(i + 1, j):
                    if text[k] != "\n":
                        code[k] = "x"
                        ns[k] = "x"
            else:
                blank(i + 1, j, False)
            i = j + 1
            continue
        if c in quotes:
            if tri and text.startswith(c * 3, i):
                j = text.find(c * 3, i + 3)
                j = n if j < 0 else j
                blank(i + 3, j, False)
                i = j + 3
                continue
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j, n)
            blank(i + 1, j, False)
            i = j + 1
            continue
        i += 1
    return "".join(code), "".join(ns)


def match_close(s, i, o="(", c=")"):
    """index of the bracket closing the one at s[i] (len(s) if unbalanced)"""
    d = 0
    for k in range(i, len(s)):
        if s[k] == o:
            d += 1
        elif s[k] == c:
            d -= 1
            if d == 0:
                return k
    return len(s)


def split_args(s):
    """top-level comma split of an argument string"""
    out, d, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    last = "".join(cur)
    if last.strip() or out:
        out.append(last)
    return [a.strip() for a in out]


# ============================ tautology helpers for the non-python languages ============================
_STR = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'|`[^`]*`")
_CONST_WORD = re.compile(r"\b(?:true|false|null|nil|None|True|False|undefined|NaN|and|or|not|is|nullptr|NULL|Nothing)\b")
_NUM = re.compile(r"\b\d[\w.]*|\.\d+")


def const_only(a):
    """no identifier, call or member access in the expression: only literals and operators"""
    if not a or not a.strip():
        return False
    t = _STR.sub("0", a)
    t = _CONST_WORD.sub("0", t)
    t = _NUM.sub("0", t)
    t = re.sub(r"\[\s*\]|\{\s*\}", "0", t)
    return re.fullmatch(r"[\s0=!<>+\-*/%&|^~(),:?]*", t) is not None


def _norm(a):
    return re.sub(r"\s+", "", a)


def _identical_cmp(a):
    m = re.fullmatch(r"(?P<l>.+?)\s*(?:===|==|<=|>=)\s*(?P<r>.+)", a.strip(), re.S)
    return bool(m) and _norm(m.group("l")) == _norm(m.group("r")) and "(" not in m.group("l")


_ONE_ARG = re.compile(r"(true|false|null|notnull|nil|notnil|defined|undefined|ok|truthy|falsy|empty|unwrap|assert|xctassert)$", re.I)
_ALWAYS = re.compile(r"(thrown?|throws|fails?|raises?|exception|panic|verify|called|invoked|never|eventually|catch)", re.I)


def trivial_args(stem, args):
    """True when the assertion compares constants only / identical operands (so it can never fail)"""
    if _ALWAYS.search(stem):
        return False
    if not args:
        return False
    n = 1 if _ONE_ARG.search(stem) else 2
    first = args[:n]
    if all(const_only(a) for a in first):
        return True
    if len(first) >= 2 and _norm(first[0]) and _norm(first[0]) == _norm(first[1]) and "(" not in first[0]:
        return True
    if len(first) == 1 and _identical_cmp(first[0]):
        return True
    return False


def _args_at(ns, open_idx):
    close = match_close(ns, open_idx)
    return split_args(ns[open_idx + 1:close]), close


# ============================ per-language assertion finders over [a, b) of the blanked code ============================
_TS_EXPECT = re.compile(r"(?<![.\w$])expect(?:\s*\.\s*(?:soft|poll))?\s*\(")
_TS_ASSERT = re.compile(r"(?<![.\w$])assert(?:\s*\.\s*(\w+))?\s*\(")
_KT_ASSERT = re.compile(r"(?<![\w$])(assert\w*|verify\w*|assertThat)\s*(?:<[^<>()]*>)?\s*([({])")
_KT_INFIX = re.compile(r"\bshould(?:Not)?(?:Be\w*|Equal|Throw\w*|Contain\w*|Match\w*|StartWith|EndWith|HaveSize)\b")
_SW_ASSERT = re.compile(r"\b(XCTAssert\w*|XCTUnwrap)\s*\(|(#expect|#require)\s*\(")
_RS_ASSERT = re.compile(r"\b(?:debug_)?(assert(?:_eq|_ne|_matches)?)!\s*\(")
_GO_T = re.compile(r"\bt\.(?:Error|Errorf|Fatal|Fatalf|Fail|FailNow)\s*\(")
_GO_ASSERT = re.compile(r"\b(?:assert|require)\.(\w+)\s*\(")
_GD_ASSERT = re.compile(r"(?<![\w.])(assert\w*)\s*\(")


def real_ts(code, ns, a, b):
    for m in _TS_EXPECT.finditer(code, a, b):
        o = m.end() - 1
        close = match_close(code, o)
        arg = ns[o + 1:close].strip()
        k = close + 1
        matcher, margs = None, []
        while True:
            mm = re.compile(r"\s*\.\s*(\w+)").match(code, k)
            if not mm:
                break
            k = mm.end()
            if mm.group(1) in ("not", "resolves", "rejects"):
                continue
            matcher = mm.group(1)
            mo = re.compile(r"\s*\(").match(code, k)
            if mo:
                margs, _ = _args_at(ns, mo.end() - 1)
            break
        if matcher is None:
            continue   # a bare expect(x) asserts nothing
        if const_only(arg) and all(const_only(x) for x in margs):
            continue
        if margs and _norm(arg) == _norm(margs[0]) and _norm(arg) and "(" not in arg:
            continue
        return True
    for m in _TS_ASSERT.finditer(code, a, b):
        args, _ = _args_at(ns, m.end() - 1)
        if not trivial_args(m.group(1) or "assert", args):
            return True
    return False


def real_kt(code, ns, a, b):
    if _KT_INFIX.search(code, a, b):
        return True
    for m in _KT_ASSERT.finditer(code, a, b):
        if m.group(2) == "{":
            return True
        args, _ = _args_at(ns, m.end() - 1)
        if not trivial_args(m.group(1), args):
            return True
    return False


def real_swift(code, ns, a, b):
    for m in _SW_ASSERT.finditer(code, a, b):
        stem = m.group(1) or m.group(2).lstrip("#")
        args, _ = _args_at(ns, m.end() - 1)
        if stem == "XCTUnwrap":
            if args and not const_only(args[0]):
                return True
            continue
        if not trivial_args(stem, args):
            return True
    return False


def real_rs(code, ns, a, b):
    for m in _RS_ASSERT.finditer(code, a, b):
        args, _ = _args_at(ns, m.end() - 1)
        if not trivial_args(m.group(1), args):
            return True
    return False


def real_go(code, ns, a, b):
    if _GO_T.search(code, a, b):
        return True
    for m in _GO_ASSERT.finditer(code, a, b):
        args, _ = _args_at(ns, m.end() - 1)
        if args and re.fullmatch(r"t|b|s\.T\(\)|suite\.T\(\)", args[0]):
            args = args[1:]
        if not trivial_args(m.group(1), args):
            return True
    return False


def real_gd(code, ns, a, b):
    for m in _GD_ASSERT.finditer(code, a, b):
        args, _ = _args_at(ns, m.end() - 1)
        if not trivial_args(m.group(1), args):
            return True
    return False


REAL = {"ts": real_ts, "kt": real_kt, "java": real_kt, "swift": real_swift, "rs": real_rs, "go": real_go, "gd": real_gd}


def blank_range(s, a, b):
    return s[:a] + re.sub(r"[^\n]", " ", s[a:b]) + s[b:]


def kill_dead(code, ns):
    """blank `if (false) { ... }` / `if (0)` blocks (never executed)"""
    for m in list(re.finditer(r"\bif\s*\(?\s*(?:false|0|nil|null|undefined)\s*\)?\s*\{", code)):
        o = m.end() - 1
        c = match_close(code, o, "{", "}")
        code, ns = blank_range(code, m.start(), c + 1), blank_range(ns, m.start(), c + 1)
    return code, ns


# ============================ ts / js ============================
_TS_MODS_OK = {"only", "concurrent", "sequential", "each", "for", "fails", "fail", "skipIf", "runIf", "failing"}
_TS_SKIP_MODS = {"skip", "todo", "fixme"}
_TS_HEAD = re.compile(r"(?<![.\w$])(xit|xtest|xdescribe|it|test|describe)((?:\s*\.\s*\w+)*)")


def _ts_calls(code):
    """yield (name, mods, call_open, call_close) for each it/test/describe call"""
    for m in _TS_HEAD.finditer(code):
        name = m.group(1)
        mods = [x.strip() for x in m.group(2).split(".") if x.strip()]
        k = m.end()
        pre = code[max(0, m.start() - 9):m.start()]
        if re.search(r"function\s*\*?\s*$", pre):
            continue
        ws = re.compile(r"\s*")
        k = ws.match(code, k).end()
        if k < len(code) and code[k] == "`" and ("each" in mods or "for" in mods):
            k2 = code.find("`", k + 1)
            k = ws.match(code, (len(code) if k2 < 0 else k2 + 1)).end()
        elif k < len(code) and code[k] == "(":
            if set(mods) & {"each", "for", "skipIf", "runIf"}:
                c1 = match_close(code, k)
                k2 = ws.match(code, c1 + 1).end()
                if k2 < len(code) and code[k2] == "(":
                    k = k2
        if k >= len(code) or code[k] != "(":
            continue
        yield name, mods, k, match_close(code, k)


def scan_ts(code, ns):
    code, ns = kill_dead(code, ns)
    for name, mods, o, c in list(_ts_calls(code)):               # pass 1: blank every skipped call (and everything nested in it)
        if (set(mods) & _TS_SKIP_MODS) or name.startswith("x"):
            code, ns = blank_range(code, o, c + 1), blank_range(ns, o, c + 1)
    for name, mods, o, c in _ts_calls(code):                     # pass 2: a real test call with a real assertion
        if name.endswith("describe") or "describe" in mods:
            continue
        if not set(mods) <= _TS_MODS_OK:
            continue                                             # test.beforeEach / test.use / test.step ... are not tests
        if real_ts(code, ns, o, c):
            return True
    return False


# ============================ kotlin / java / swift / rust / go (annotation or name based) ============================
_ANNOT = {
    "kt": re.compile(r"@(?:[\w.]+\.)?(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b"),
    "java": re.compile(r"@(?:[\w.]+\.)?(?:Test|ParameterizedTest|RepeatedTest|TestFactory)\b"),
    "swift": re.compile(r"@Test\b|\bfunc\s+test\w*\s*\("),
    "rs": re.compile(r"#\[\s*(?:\w+::)*test\b"),
    "go": re.compile(r"\bfunc\s+Test\w*\s*\("),
}
_IGNORE = {
    "kt": re.compile(r"@(?:Ignore|Disabled)\b"),
    "java": re.compile(r"@(?:Ignore|Disabled)\b"),
    "swift": re.compile(r"\.disabled\b"),
    "rs": re.compile(r"#\[\s*ignore\b"),
    "go": None,
}
_BODYSKIP = {"swift": re.compile(r"\bXCTSkip\w*\b"), "go": re.compile(r"\bt\.Skip(?:f|Now)?\s*\(")}


def _find_body(code, p, lang):
    """-> (start, end) of the function body following position p, or None"""
    d, seen_close, n = 0, False, len(code)
    k = p
    while k < n:
        ch = code[k]
        if ch == "(":
            d += 1
        elif ch == ")":
            d -= 1
            if d == 0:
                seen_close = True
        elif d == 0:
            if ch == "{":
                return k, match_close(code, k, "{", "}")
            if lang == "kt" and ch == "=" and seen_close and code[k + 1:k + 2] != "=":
                dd, j = 0, k + 1
                while j < n:
                    cj = code[j]
                    if cj in "({[":
                        dd += 1
                    elif cj in ")}]":
                        dd -= 1
                        if dd < 0:
                            break
                    elif cj == "\n" and dd == 0 and re.compile(r"\s*(?:@|fun\b|\}|class\b|object\b|(?:private|public|internal|protected|override|open|abstract)\b)").match(code, j + 1):
                        break
                    j += 1
                return k + 1, j
            if ch == ";" or (ch == "}" and lang != "kt"):
                return None
        k += 1
    return None


def scan_annot(code, ns, lang):
    code, ns = kill_dead(code, ns)
    if lang in ("kt", "java"):                                   # class-level @Ignore/@Disabled
        for m in list(re.finditer(r"@(?:Ignore|Disabled)\b[^{};]*?\bclass\b", code)):
            o = code.find("{", m.end())
            if o >= 0:
                c = match_close(code, o, "{", "}")
                code, ns = blank_range(code, m.start(), c + 1), blank_range(ns, m.start(), c + 1)
    done = set()
    for m in _ANNOT[lang].finditer(code):
        seg = max(code.rfind("}", 0, m.start()), code.rfind("{", 0, m.start()), code.rfind(";", 0, m.start())) + 1
        p = m.end()
        # skip annotation arguments: @Test(expected = X) / @Test("name", .disabled())
        mo = re.compile(r"\s*\(").match(code, p)
        if mo and lang != "go" and m.group(0).startswith(("@", "#")):
            p = match_close(code, mo.end() - 1) + 1
        if m.group(0).startswith("func"):
            p = m.start()                                        # name-based (go / swift XCTest): the signature parens are balanced from the `func`
        body = _find_body(code, p, "kt" if lang == "kt" else lang)
        if body is None or body[0] in done:
            continue
        done.add(body[0])
        header = code[seg:body[0]]
        ig = _IGNORE[lang]
        if ig and ig.search(header):
            continue
        a, b = body
        if lang == "go":
            pass
        if lang == "rs" and re.search(r"#\[\s*should_panic\b", header):
            return True
        bs = _BODYSKIP.get(lang)
        if bs:
            sk = bs.search(code, a, b)
            if sk:
                b = sk.start()
        if REAL[lang](code, ns, a, b):
            return True
    return False


# ============================ gdscript (indentation based) ============================
def scan_gd(code, ns):
    L = code.split("\n")
    N = ns.split("\n")
    i = 0
    fn = re.compile(r"^(\s*)(?:static\s+)?func\s+test\w*\s*\(")
    pos = [0]
    for l in L:
        pos.append(pos[-1] + len(l) + 1)
    while i < len(L):
        m = fn.match(L[i])
        if not m:
            i += 1
            continue
        ind = len(m.group(1))
        # one-liner `func test_a(): assert_eq(..)`: scan the remainder after the signature colon
        close = match_close(L[i], L[i].find("("))
        rest_l = L[i][close + 1:]
        rest_n = N[i][close + 1:]
        j = i + 1
        body = [(rest_l.split(":", 1)[1] if ":" in rest_l else "", rest_n.split(":", 1)[1] if ":" in rest_n else "")]
        dead_ind = None
        ret_ind = None
        while j < len(L):
            l = L[j]
            if not l.strip():
                j += 1
                continue
            li = len(l) - len(l.lstrip())
            if li <= ind:
                break
            if dead_ind is not None and li > dead_ind:
                j += 1
                continue
            dead_ind = None
            if ret_ind is not None and li >= ret_ind:
                j += 1
                continue
            ret_ind = None
            s = l.strip()
            if re.match(r"if\s+\(?\s*(false|0|null)\s*\)?\s*:", s):
                dead_ind = li
                j += 1
                continue
            if re.match(r"return\b", s):
                ret_ind = li
                body.append((l, N[j]))
                j += 1
                continue
            if re.search(r"\bpending\s*\(", s):
                break
            body.append((l, N[j]))
            j += 1
        txt_l = "\n".join(x[0] for x in body)
        txt_n = "\n".join(x[1] for x in body)
        if real_gd(txt_l, txt_n, 0, len(txt_l)):
            return True
        i = max(j, i + 1)
    return False


# ============================ python (ast) ============================
_SKIPN = {"skip"}
_COND_SKIP = {"skipif", "skipIf", "skipUnless"}


def _const_truth(n):
    if isinstance(n, ast.Constant):
        return bool(n.value)
    if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.Not):
        v = _const_truth(n.operand)
        return None if v is None else (not v)
    return None


def _no_source(e):
    return not any(isinstance(x, (ast.Name, ast.Call, ast.Attribute, ast.Subscript, ast.Await, ast.Lambda, ast.Starred,
                                  ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp, ast.NamedExpr)) for x in ast.walk(e))


def _has_call(e):
    return any(isinstance(x, ast.Call) for x in ast.walk(e))


def _trivial_test(e):
    if _no_source(e):
        return True
    if isinstance(e, ast.Tuple) and e.elts:
        return True                                              # assert (cond, "msg") is always true
    if isinstance(e, ast.BoolOp):
        if isinstance(e.op, ast.Or):
            return any(_trivial_test(v) for v in e.values)
        return all(_trivial_test(v) for v in e.values)
    if isinstance(e, ast.Compare):
        ops = [e.left] + list(e.comparators)
        if all(isinstance(o, (ast.Eq, ast.Is, ast.LtE, ast.GtE)) for o in e.ops):
            d = ast.dump(ops[0])
            if all(ast.dump(o) == d for o in ops) and not _has_call(ops[0]):
                return True
    if isinstance(e, ast.Call) and isinstance(e.func, ast.Name) and e.func.id in ("isinstance", "callable", "bool") and e.args and _no_source(e.args[0]):
        return True
    return False


def _fn_name(call):
    f = call.func
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return ""


_PY_ALWAYS = re.compile(r"(raises|warns|logs|fail|called|never|deprecated)", re.I)


def _is_assert_call(c):
    nm = _fn_name(c)
    return nm.startswith("assert") or nm in ("raises", "warns", "deprecated_call")


def _trivial_call(c):
    nm = _fn_name(c)
    if _PY_ALWAYS.search(nm) or not c.args:
        return False
    one = bool(_ONE_ARG.search(nm)) or nm in ("assertIsNone", "assertIsNotNone", "assertTrue", "assertFalse")
    first = c.args[:1] if one else c.args[:2]
    if re.search(r"IsInstance", nm, re.I):
        return _no_source(first[0])
    if all(_no_source(a) for a in first):
        return True
    if len(first) >= 2 and ast.dump(first[0]) == ast.dump(first[1]) and not _has_call(first[0]):
        return True
    return False


def _skip_dec(decos):
    for d in decos:
        call = d if isinstance(d, ast.Call) else None
        names = {x.attr if isinstance(x, ast.Attribute) else x.id for x in ast.walk(d.func if call else d) if isinstance(x, (ast.Attribute, ast.Name))}
        if names & _SKIPN:
            return True
        if call and names & _COND_SKIP and call.args:
            v = _const_truth(call.args[0])
            nm = _fn_name(call)
            if v is True and nm != "skipUnless" or v is False and nm == "skipUnless":
                return True
    return False


def _is_skip_call(st):
    if isinstance(st, ast.Expr) and isinstance(st.value, ast.Call):
        nm = _fn_name(st.value)
        return nm in ("skip", "skipTest")
    return False


def _py_scan(stmts, ctx):
    """-> (found, stopped)"""
    for st in stmts:
        if isinstance(st, ast.Assert):
            if not _trivial_test(st.test):
                return True, False
            continue
        if isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef)):
            ctx["defs"][st.name] = st
            continue
        if isinstance(st, ast.ClassDef):
            continue
        if isinstance(st, (ast.Return, ast.Raise)):
            return False, True
        if _is_skip_call(st):
            return False, True
        if isinstance(st, ast.If):
            v = _const_truth(st.test)
            for br in ([st.body] if v is True else [st.orelse] if v is False else [st.body, st.orelse]):
                f, _ = _py_scan(br, ctx)
                if f:
                    return True, False
            continue
        if isinstance(st, ast.While):
            if _const_truth(st.test) is False:
                continue
            for br in (st.body, st.orelse):
                f, _ = _py_scan(br, ctx)
                if f:
                    return True, False
            continue
        if isinstance(st, (ast.For, ast.AsyncFor)):
            for br in (st.body, st.orelse):
                f, _ = _py_scan(br, ctx)
                if f:
                    return True, False
            continue
        if isinstance(st, (ast.With, ast.AsyncWith)):
            for it in st.items:
                e = it.context_expr
                if isinstance(e, ast.Call) and _is_assert_call(e) and not _trivial_call(e):
                    return True, False
                _note_calls(e, ctx)
            f, stopped = _py_scan(st.body, ctx)
            if f:
                return True, False
            continue
        if isinstance(st, ast.Try) or type(st).__name__ == "TryStar":
            for br in [st.body] + [h.body for h in st.handlers] + [st.orelse, st.finalbody]:
                f, _ = _py_scan(br, ctx)
                if f:
                    return True, False
            continue
        if type(st).__name__ == "Match":
            for case in st.cases:
                f, _ = _py_scan(case.body, ctx)
                if f:
                    return True, False
            continue
        for x in ast.walk(st):
            if isinstance(x, ast.Call):
                if _is_assert_call(x) and not _trivial_call(x):
                    return True, False
        _note_calls(st, ctx)
    return False, False


def _note_calls(node, ctx):
    for x in ast.walk(node):
        if isinstance(x, ast.Call):
            nm = _fn_name(x)
            if nm:
                ctx["calls"].add(nm)


def _py_test_real(fn):
    ctx = {"defs": {}, "calls": set()}
    f, _ = _py_scan(fn.body, ctx)
    if f:
        return True
    for nm in list(ctx["calls"]):
        d = ctx["defs"].get(nm)
        if d is not None and not _skip_dec(d.decorator_list):
            c2 = {"defs": {}, "calls": set()}
            if _py_scan(d.body, c2)[0]:
                return True
    return False


def _class_disabled(cls):
    for st in cls.body:
        if isinstance(st, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "__test__" for t in st.targets) and _const_truth(st.value) is False:
            return True
    return _skip_dec(cls.decorator_list)


def _py_walk_defs(body, skipped):
    for st in body:
        if isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if st.name.startswith("test") and not skipped and not _skip_dec(st.decorator_list):
                if _py_test_real(st):
                    return True
        elif isinstance(st, ast.ClassDef):
            if _py_walk_defs(st.body, skipped or _class_disabled(st)):
                return True
    return False


def scan_py_ast(text):
    """True/False, or None when the source does not parse"""
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return None
    for st in tree.body:
        if isinstance(st, ast.Assign):
            for t in st.targets:
                if isinstance(t, ast.Name):
                    if t.id == "__test__" and _const_truth(st.value) is False:
                        return False
                    if t.id == "pytestmark" and _skip_dec([st.value] if not isinstance(st.value, (ast.List, ast.Tuple)) else list(st.value.elts)):
                        return False
    return _py_walk_defs(tree.body, False)


# ---- fallback: the pre-ast line heuristic, run over comment/string-stripped text ----
def _py_assert_real_line(l):
    s = l.strip()
    m = re.match(r"assert\b\s*\(?\s*(.*)$", s)
    if m and not re.match(r"assert\s*=", s):
        expr = m.group(1).rstrip(")").strip()
        expr = re.split(r",\s*[\"'f]", expr)[0].strip()
        if re.fullmatch(r"(not\s+False|not\s+None\s*is\s*None|True|1|[\"'][^\"']*[\"'])", expr) or expr == "":
            return False
        return True
    if re.search(r"\bself\.assert\w*\(", s):
        return not re.search(r"self\.assert(True|Equal)\(\s*(True|1)\s*(,\s*(True|1))?\s*[,)]", s)
    if re.search(r"\bpytest\.(raises|warns)\(", s):
        return True
    return False


def scan_py_fallback(code):
    skip_dec = re.compile(r"^\s*@\S*\b(skip)\b")
    pending_skip, cur = False, None
    for l in code.split("\n"):
        if not l.strip():
            continue
        ind = len(l) - len(l.lstrip())
        if cur and ind <= cur[0] and not re.match(r"^\s*[)\]]", l):
            cur = None
        if skip_dec.match(l):
            pending_skip = True
            continue
        if re.match(r"^\s*(async\s+)?def\s+test\w*", l):
            cur = (ind, pending_skip)
            pending_skip = False
            continue
        if l.lstrip().startswith("@"):
            continue
        pending_skip = False
        if cur:
            if re.search(r"\b(pytest\.skip|self\.skipTest|unittest\.skip)\(", l):
                cur = (cur[0], True)
                continue
            if not cur[1] and _py_assert_real_line(l):
                return True
    return False


# ============================ dispatch ============================
def kind():
    b = base
    if ext == ".py" and (re.match(r"test_.*\.py$", b) or re.match(r".*_test\.py$", b)):
        return "py"
    if ext in (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs") and re.search(r"\.(test|spec)\.[a-z]+$", b):
        return "ts"
    if ext == ".gd" and re.match(r"(test_.*|.*_test|.*_spec)\.gd$", b):
        return "gd"
    if ext in (".kt", ".kts") and re.search(r"Tests?\.kt$", b):
        return "kt"
    if ext == ".swift" and re.search(r"Tests?\.swift$", b):
        return "swift"
    if ext == ".go" and b.endswith("_test.go"):
        return "go"
    if ext == ".java" and re.match(r"(.*Tests?|Test.*)\.java$", b):
        return "java"
    if ext == ".rs" and (re.search(r"(^|/)tests/", path) or b.endswith("_test.rs") or b == "tests.rs"):
        return "rs"
    return None


_LANG_OF_EXT = {".py": "py", ".gd": "gd", ".ts": "ts", ".tsx": "ts", ".js": "ts", ".jsx": "ts", ".mjs": "ts", ".cjs": "ts", ".kt": "kt", ".kts": "kt",
                ".swift": "swift", ".go": "go", ".java": "java", ".rs": "rs"}


def judge_test(k):
    if k == "py":
        r = scan_py_ast(src)
        if r is not None:
            return r
        code, _ = blank_src(src, "py")
        return scan_py_fallback(code)
    code, ns = blank_src(src, k)
    if k == "ts":
        return scan_ts(code, ns)
    if k == "gd":
        return scan_gd(code, ns)
    return scan_annot(code, ns, k)


k = kind()
if k:
    print("real" if judge_test(k) else "stub")
else:
    lang = _LANG_OF_EXT.get(ext)
    text = blank_src(src, lang)[0] if lang else src
    n = 0
    for raw in text.split("\n"):
        s = raw.strip()
        if not s or (not lang and re.match(r"(#|//|--|/\*|\*)", s)):
            continue
        if re.fullmatch(r"(\"\"\"|''')", s) or re.fullmatch(r"(pass|\.\.\.)", s) or re.fullmatch(r"[\s{}()\[\];,\"'`]+", s):
            continue
        if re.match(r"(import|from|using|use|require|extends|class_name|package)\s", s):
            continue
        n += 1
    print("real" if n >= MIN else "stub")
