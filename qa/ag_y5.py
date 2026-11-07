#!/usr/bin/env python3
"""ag_y5.py - 2026-11-04 package Y5 rules for gate_antigaming.py: two SHADOW-ONLY FLAG sub-keys (never FAIL, no gate mode is read or changed).

  Y_SKIP_ADDED  (sub-key skip_added)  a skip/xfail/todo/disabled marker was ADDED to an EXISTING test (pytest.mark.skip/skipif/xfail, pytest.skip(), unittest.skip*,
                `it.skip` / `xit` / `describe.skip` / `test.skip` / `.todo` / `.fixme`, GUT `pending(`, `@Disabled` / `@Ignore`, `XCTSkip`, `skipTest(`) AND the same diff did not
                otherwise touch that test semantically: no other added code line inside the test's own span (a marker-only edit, or an edit that only moved the
                marker). A test whose body was also rewritten is the ordinary B_SKIP_ADDED business; a brand-new test carrying a marker is not "existing".
                Incident: billwatch afa62b13 put @pytest.mark.skip on the failing `test_headers_present_on_500` and was credited.
  Y_ASSERT_DROP (sub-key assert_drop) a MODIFIED test file lost most of its oracle: non-blank lines fell by more than 50% (file >= 20 lines at base), OR every
                effective assertion is gone (>= 1 at base, 0 now), OR the assertion count / the test count fell by more than 50% (>= 4 at base). Not reported when the
                other test files of the same diff gained at least half of the removed lines (a split / move).
                Also: a deletion-dominant diff (>= 50 removed lines and >= 90% of the changed lines are removals) that nets >= 3 fewer tests, or >= 5 fewer
                assertions (and >= 20%), even when the file shrank by less than half. Deleted files stay with A_TESTFILE_DELETED.
                Incident: shrike-notify efd06bc1 deleted 381 of 382 lines of backend/tests/test_subscribe_api.py and was pushed.

2026-11-06 review fixes: (1) markers are matched on a MASKED copy of the new file (comments and string contents blanked: tokenize for Python, ga.mask_text for
JS/TS/Kotlin/Swift/GDScript), so `# TODO consider pytest.mark.skip` or a docstring/`"pytest.mark.skip"` string never fires; (2) assert_drop weights every test by its
parametrize / `.each` / subTest-loop case count and does NOT flag a consolidation that preserves the case count (6 tests/12 asserts -> 1 parametrized test of 6 cases/2 asserts);
(3) only UNCONDITIONAL skip/xfail/todo is Y_SKIP_ADDED: skipif/skipUnless/skipIf with a real condition, `xfail(cond, ...)`, `test.skip(cond, ...)` and a skip inside an
`if`/`else` guard are conditional and left to B_SKIP_ADDED; when Y and B flag the SAME marker the B row is tagged `dup_of` and the gate's rule counts count the marker once.

Every finding carries `subkey` (see qa_common.ANTIGAMING_SUBKEYS) so the evidence report and qa/qa_precision_sample.py can count them apart from the other rules.
OVN_QA_AG_Y5=off disables the module. Isolated like ag_n2: an error becomes a note.
"""
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

MIN_LINES = 20          # base size below which a line-ratio is noise
MIN_ASSERTS = 4         # base assertion / test count below which a ratio is noise
DROP_RATIO = 0.5
DOM_MIN_REMOVED = 50    # deletion-dominant shape: >= 50 removed lines ...
DOM_FRAC = 0.9          # ... and >= 90% of the changed lines are removals
CAP = 10

_MARK_RES = [
    re.compile(r"pytest\.mark\.(?:skip|skipif|xfail|todo)\b|\bpytest\.(?:skip|xfail)\s*\(|unittest\.(?:skip\w*|expectedFailure)|@skip(?:If|Unless)?\b|"
               r"\.skipTest\s*\(|\braise\s+(?:unittest\.)?SkipTest"),
    re.compile(r"(?<![\w$])(?:it|test|describe|context|suite)\s*\.\s*(?:skip|todo|fixme)\b|(?<![\w$.])x(?:it|describe|test|context)\s*\("),
    re.compile(r"@(?:org\.junit\.)?(?:Ignore|Disabled)\b|\bXCTSkip\b|(?<![\w.])pending\s*\("),
]


def _ga():
    import gate_antigaming as ga
    return ga


def _is_marker(text):
    return any(r.search(text) for r in _MARK_RES)


def _mask_py(text):
    """Blank comments and string tokens (newlines kept) with tokenize; None when the file cannot be tokenized."""
    import io
    import tokenize
    out = list(text)
    starts = [0]
    for m in re.finditer("\n", text):
        starts.append(m.end())

    def off(r, c):
        return starts[r - 1] + c if r - 1 < len(starts) else len(text)
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.COMMENT or tok.type == tokenize.STRING or getattr(tokenize, "FSTRING_MIDDLE", -1) == tok.type:
                a, b = off(*tok.start), off(*tok.end)
                for k in range(a, min(b, len(out))):
                    if out[k] != "\n":
                        out[k] = " "
    except (tokenize.TokenError, IndentationError, SyntaxError, ValueError):
        return None
    return "".join(out)


def _mask_line(line, lang):
    """Fallback single-line mask: strings and trailing comments blanked."""
    out, i, n = list(line), 0, len(line)
    hash_c = lang in ("py", "gd")
    while i < n:
        c = line[i]
        if (hash_c and c == "#") or (not hash_c and line[i:i + 2] == "//"):
            for k in range(i, n):
                out[k] = " "
            break
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            for k in range(i + 1, min(j, n)):
                out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


def _masked_lines(text, lang):
    """Lines of `text` with comments / string contents blanked, same line numbering as text."""
    ga = _ga()
    m = None
    try:
        if lang == "py":
            m = _mask_py(text)
        elif lang:
            m = ga.mask_text(text, lang)
    except Exception:  # noqa: BLE001
        m = None
    if m is not None and len(m) == len(text):
        return m.split("\n")
    return [_mask_line(ln, lang) for ln in text.split("\n")]


_COND_NAME = re.compile(r"\b(?:skipif|skipIf|skipUnless|xfail|skip|todo|fixme)\b")


MAX_MARKS_PER_LINE = 16  # D7: marker tokens examined per added line
ARG_WINDOW = 4096        # D7: characters after a marker token that argument parsing may look at
JOIN_LINES = 10          # D5: continuation lines joined to a marker line whose call is still open


def _all_args(text, name_end):
    """Top-level argument texts of the call that starts after text[name_end:] (empty list when there is no call / no arguments)."""
    m = _OPEN_PAREN.match(text, name_end)
    if not m:
        return []
    i = m.end()
    out, cur, depth, q = [], [], 0, None
    while i < len(text):
        c = text[i]
        if q:
            cur.append(c)
            if c == "\\" and i + 1 < len(text):
                i += 1
                cur.append(text[i])
            elif c == q:
                q = None
        elif c in "\"'`":
            q = c
            cur.append(c)
        elif c in "([{":
            depth += 1
            cur.append(c)
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur).strip())
    return [a for a in out if a]


_OPEN_PAREN = re.compile(r"\s*\(")
_OPEN_PAREN_WS = re.compile(r"\s*\(\s*")
_STR_ARG = re.compile(r"""^[rbfuRBFU]*["'`]""")
_BARE_NAME = re.compile(r"^[A-Za-z_$][\w$]*$")


def _is_condition_expr(arg, bare_ok=False):
    """True when a first argument is clearly a boolean condition: not a string literal, not a keyword arg, not a constant, and not a bare name
    unless the caller says the call shape makes a bare name a condition (bare_ok, see _positional / the arity rule in _is_conditional)."""
    if not arg or _STR_ARG.match(arg) or re.match(r"^[A-Za-z_]\w*\s*=(?!=)", arg):
        return False
    if _BARE_NAME.match(arg):
        return bool(bare_ok) and not re.match(r"^(?:True|False|true|false|None|null|undefined)$", arg)
    return not re.match(r"^(?:True|False|true|false|1|0)$", arg)


def _positional(args):
    """Positional arguments of a call: everything that is not a `name=value` keyword argument."""
    return [a for a in args if not re.match(r"^[A-Za-z_]\w*\s*=(?!=)", a)]


def _first_arg(text, name_end):
    """The first top-level argument text after the '(' that follows text[name_end:], or None when the marker has no call parentheses / no argument."""
    m = _OPEN_PAREN_WS.match(text, name_end)
    if not m:
        return None
    a = m.end()
    depth, i, q = 0, a, None
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\":
                i += 1
            elif c == q:
                q = None
        elif c in "\"'`":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        i += 1
    arg = text[a:i].strip()
    return arg or None


def _is_conditional(text, mline, new_lines, ln):
    """True when the added marker only skips under a condition (platform/env guard): skipif/skipIf/skipUnless with a non-constant condition, xfail/skip(<cond>, ...)
    (first argument is neither a string nor a keyword), or an inline skip nested under an if/elif/else guard. Unconditional skip/xfail/todo/pending -> False."""
    const = re.compile(r"^(?:True|False|true|false|1|0)$")
    full = text
    for k, m in enumerate(_COND_NAME.finditer(mline)):
        if k >= MAX_MARKS_PER_LINE:
            break                                            # D7: a pathological one-line bundle with thousands of marker tokens: bounded work, uncertain => not conditional (FLAG)
        nm = m.group(0)
        text = full[:m.end() + ARG_WINDOW]                   # D7: argument parsing never scans (or copies) past a fixed window
        arg = _first_arg(text, m.end()) if nm not in ("todo", "fixme") else None
        if nm in ("skipif", "skipIf", "skipUnless"):
            if arg is None or const.match(arg):
                continue
            return True
        if nm in ("xfail", "skip"):
            args = _all_args(text, m.end())
            if any(re.match(r"condition\s*=(?!=)", a) for a in args):
                return True                                  # explicit condition= keyword
            pos = _positional(args)
            has_reason_kw = any(re.match(r"reason\s*=(?!=)", a) for a in args)
            if nm == "xfail":
                # BARE-NAME RULE (xfail): a bare name first argument is a CONDITION when the call has a second positional argument or a reason= keyword
                # (`xfail(IS_WIN, reason='r')`, `xfail(IS_WIN, 'r')`); a lone `xfail(REASON)` / `xfail(REASON, strict=True)` is the reason string -> unconditional.
                # Any non-name, non-string, non-constant expression is a condition either way.
                if pos and _is_condition_expr(pos[0], bare_ok=len(pos) >= 2 or has_reason_kw):
                    return True
            elif re.search(r"(?<![\w.$])(?:it|test|describe)\.skip\s*$", mline[:m.end()]) and (
                    (len(pos) >= 2 and _STR_ARG.match(pos[1])) or len(pos) == 1) and _is_condition_expr(pos[0], bare_ok=True):
                # D6: Playwright's signature is test.skip(condition[, description]): a LONE non-string argument (`test.skip(isMobile)`,
                # `test.skip(browserName === 'webkit')`) is a condition; a lone string literal / constant (`test.skip('r')`, `test.skip(true)`) stays unconditional.
                # BARE-NAME RULE (Playwright): test.skip(<cond>, 'reason') has a STRING second argument and a non-string first one; a bare name there is a
                # fixture/flag (`test.skip(isMobile, 'Desktop only')`). The title forms (title, fn) / (title, details, fn) never have (x, 'str'), and
                # it.skip(nameVar, fn) / skip(REASON) (one positional, or second argument not a string) are NOT conditions.
                return True
    # inline call guarded by an enclosing if/elif/else block (ANY ancestor block, not only the previous line): same-line `if A: pytest.skip()` / `if (A) test.skip()`,
    # else walk up through strictly decreasing indents; an if/elif/else header among the ancestors up to the enclosing def/it/test makes the skip conditional.
    mk = re.search(r"\b(?:pytest\.(?:skip|xfail)|skipTest|SkipTest|(?<![\w.$])(?:it|test)\.skip)\b", mline)
    if mk:
        if re.search(r"(?<![\w.])(?:if|elif|else)\b[^\n]*$", mline[:mk.start()]) and re.match(r"\s*(?:\}\s*)?(?:if|elif|else)\b", mline):
            return True
        cur = _indent(new_lines[ln - 1]) if ln - 1 < len(new_lines) else 0
        for j in range(ln - 2, max(-1, ln - 400), -1):
            pl = new_lines[j]
            if not pl.strip() or _is_comment(pl) or _indent(pl) >= cur:
                continue
            cur = _indent(pl)
            if re.match(r"\s*(?:\}\s*)?(?:if|elif|else)\b", pl):
                return True
            if re.match(r"\s*(?:async\s+)?(?:def|class|fun|func|function)\b|\s*(?:x|f)?(?:it|test|describe)\b", pl):
                return False                                     # reached the enclosing test / class: nothing above it guards this skip
            if cur == 0:
                break
    return False


def _join_open_call(text, mlines, new_lines, ln):
    """D5: a marker line whose call is still open (black-formatted `@pytest.mark.skipif(` + condition on the next line) is joined with up to JOIN_LINES following
    lines of the NEW file (whole-line comments dropped) until the parentheses balance, so the arguments can be classified. Balance is measured on the masked text."""
    depth = mlines[ln - 1].count("(") - mlines[ln - 1].count(")")
    if depth <= 0:
        return text
    parts = [text]
    for j in range(ln, min(len(new_lines), ln + JOIN_LINES)):
        if not new_lines[j].strip() or _is_comment(new_lines[j]):
            continue
        parts.append(new_lines[j])
        ml = mlines[j] if j < len(mlines) else new_lines[j]
        depth += ml.count("(") - ml.count(")")
        if depth <= 0:
            break
    return "\n".join(parts)


def _indent(s):
    return len(s) - len(s.lstrip())


def _is_comment(s):
    t = s.strip()
    return t.startswith(("#", "//", "/*", "*"))


def _span(lines, idx, decorator):
    """(start, end) 1-based inclusive line range of the test a marker at lines[idx] belongs to, or None when no def/it line is found."""
    ga = _ga()
    start = None
    rng = range(idx + 1, min(len(lines), idx + 12)) if decorator else range(idx, max(-1, idx - 60), -1)
    for i in rng:
        if re.search(r"\b(?:def|fun|func|function)\s+`?[A-Za-z_]\w*", lines[i]) or re.search(
                r"""(?<![\w$])(?:x|f)?(?:it|test|describe)\s*(?:\.\s*\w+)?\s*\(""", lines[i]):
            start = i
            break
    if start is None:
        return None
    ind = _indent(lines[start])
    end = start
    for j in range(start + 1, len(lines)):
        s = lines[j]
        if not s.strip():
            continue
        if _indent(s) <= ind:
            if s.lstrip().startswith(("}", ")", "]", "end")) and _indent(s) == ind:
                end = j
            break
        end = j
    return start + 1, end + 1


_INLINE_SKIP = re.compile(r"^\s*(?:await\s+)?(?:pytest\.(?:skip|xfail)|self\.skipTest|(?:it|test)\.(?:skip|fixme))\s*\(")


def _is_inline_call(masked_line, text):
    """True for a statement-form skip INSIDE a test body (`test.skip()`, `test.skip(cond, 'r')`, `pytest.skip('r')`): a complete call on one line that does not open a
    test body itself. `it.skip('title', () => {` / `test.skip('title', async () => {` are declarations (the marker line carries its own title), not inline calls."""
    if not _INLINE_SKIP.match(masked_line):
        return False
    m = _INLINE_SKIP.match(text)
    args = _all_args(text, m.end() - 1) if m else []
    if re.search(r"=>|\bfunction\b|\basync\b|[{(]\s*$", text.rstrip()) or (len(args) >= 2 and re.search(r"=>|\bfunction\b", args[-1])):
        return False
    return True


def _target(lines, idx, decorator, inline=False):
    """Name of the def / test title a marker at lines[idx] applies to. Like gate_antigaming._target_name but a quoted title of ANY length counts (the shared helper
    needs >= 3 characters, so `test('b', ...)` was never found and its inline skip went unseen), and an inline skip call is matched upward only."""
    rng = range(idx + 1, min(len(lines), idx + 12)) if decorator else range(idx - 1 if inline else idx, max(-1, idx - 60), -1)
    for i in rng:
        m = re.search(r"\b(?:def|fun|func|function)\s+`?([A-Za-z_]\w*)", lines[i])
        if m:
            return m.group(1)
        m = re.search(r"""(?<![\w$])(?:it|test|describe)\s*(?:\.\s*\w+)?\s*\(\s*["'`]([^"'`]+)["'`]""", lines[i])
        if m:
            return m.group(1)
    return None


def rule_skip_added(repo, status, diffs, out, notes):
    ga = _ga()
    n = 0
    for p, st in sorted(status.items()):
        if st != "M" or not ga.lang_of(p) or ga.ignorable(p) or not ga.is_test_path(p):
            continue
        fd = diffs.get(p)
        if not fd:
            continue
        old_txt, new_txt = repo.blob(repo.base, fd.old or p), repo.blob(repo.head, p)
        if old_txt is None or new_txt is None:
            continue
        new_lines = new_txt.split("\n")
        mlines = _masked_lines(new_txt, ga.lang_of(p))
        old_norm = set(ga._norm_line(ga._strip_markers(t)) for _, t in fd.removed if t.strip())
        # marker detection runs on the MASKED line: a marker word inside a comment / string / docstring is not a marker; conditional skips are not Y_SKIP_ADDED
        marks = [(ln, t) for ln, t in fd.added if t.strip() and ln - 1 < len(mlines) and _is_marker(mlines[ln - 1])
                 and not _is_conditional(_join_open_call(t, mlines, new_lines, ln), mlines[ln - 1], new_lines, ln)]
        mark_lns = set(ln for ln, _ in marks)
        for ln, text in marks:
            rest = ga._norm_line(ga._strip_markers(text))
            inline = _is_inline_call(mlines[ln - 1], text)
            decorator = rest.startswith("@") or ((not rest or len(rest) < 6) and not inline)
            existing = False
            if len(rest) >= 6 and rest in old_norm and not rest.startswith("@") and not inline:
                existing = True                      # the same code line, only the marker is new (`it(` -> `it.skip(`)
            else:
                tgt = _target(new_lines, ln - 1, decorator, inline)
                if tgt and re.search(r"\b(def|fun|func|class|function)\s+`?%s\b|[\"'`]%s[\"'`]" % (re.escape(tgt), re.escape(tgt)), old_txt):
                    existing = True
            if not existing:
                continue
            sp = _span(new_lines, ln - 1, decorator)
            if sp is None:
                touched = None                       # cannot delimit the test: say so, still FLAG (uncertain => FLAG)
            else:
                touched = [(l2, t2) for l2, t2 in fd.added if sp[0] <= l2 <= sp[1] and l2 not in mark_lns and t2.strip() and not _is_comment(t2)
                           and ga._norm_line(ga._strip_markers(t2)) not in old_norm]
            if touched:
                continue                             # the test was also rewritten in this diff: B_SKIP_ADDED's business, not a bare skip
            f = ga.F("Y_SKIP_ADDED", "FLAG", p, ln, "skip/xfail/todo marker added to an existing test the diff did not otherwise change%s" % (
                "" if sp else " (test span not found)"), text)
            f["subkey"] = "skip_added"
            for b in out:   # the same marker already reported by B: keep that row visible but count the event once (gate_antigaming skips `dup_of` rows in counts)
                if b.get("file") == p and b.get("line") == ln and str(b.get("rule", "")).startswith("B_SKIP_ADDED"):
                    b["dup_of"] = "Y_SKIP_ADDED"
            out.append(f)
            n += 1
            if n >= CAP:
                notes.append("y5 skip_added capped at %d" % CAP)
                return


def _nonblank(text):
    return sum(1 for s in text.split("\n") if s.strip())


def _assert_counts(lang, text):
    """(effective assertion total, test count) or None when the file cannot be parsed reliably."""
    ga = _ga()
    try:
        if lang == "py":
            m = ga.PyModule(text)
            tests = m.tests()
            # assertions moved into a helper still count (benign refactor): total over every function of the module, not only the tests
            total = max(sum(t.eff for t in tests.values()), sum(f.eff for f in m.funcs.values()))
        else:
            tests = ga.extract_tests_text(lang, text)
            total = sum(t.eff for t in tests.values())
    except (SyntaxError, ValueError, RecursionError):
        return None
    return total, len(tests)


RANGE_CAP = 100         # a range() of more cases than this is NOT credited (counts as unknown = 1): range(1000000) must not hide a gutted file
MULT_CAP = 1000         # cap on the stacked parametrize x subTest multiplicity of one def


def _range_len(node):
    """Case count of range(N) / range(a, b[, step]) built from integer constants, else None (also None above RANGE_CAP: unbounded-looking ranges earn no credit)."""
    import ast
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "range" and 1 <= len(node.args) <= 3 and not node.keywords):
        return None
    vals = []
    for a in node.args:
        if isinstance(a, ast.UnaryOp) and isinstance(a.op, ast.USub) and isinstance(a.operand, ast.Constant):
            a = ast.Constant(-a.operand.value) if isinstance(a.operand.value, int) else a
        if not (isinstance(a, ast.Constant) and isinstance(a.value, int) and not isinstance(a.value, bool)):
            return None
        vals.append(a.value)
    try:
        n = len(range(*vals))
    except (ValueError, OverflowError):
        return None
    return n if n <= RANGE_CAP else None


def _count_elts(node, consts):
    import ast
    if isinstance(node, ast.Name) and node.id in consts:
        node = consts[node.id]
    n = _range_len(node)
    if n is not None:
        return max(1, n)
    if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        return max(1, len(node.elts))
    return 1


def _py_mults(text):
    """{def lineno: case multiplicity} from stacked parametrize decorators (literal or module-level list) and `for x in <literal>: with self.subTest` loops."""
    import ast
    tree = ast.parse(text)
    consts = {n.targets[0].id: n.value for n in tree.body if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name)}
    out = {}
    for n in ast.walk(tree):
        if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        m = 1
        for d in n.decorator_list:
            if isinstance(d, ast.Call) and getattr(d.func, "attr", getattr(d.func, "id", "")) == "parametrize" and len(d.args) >= 2:
                m *= _count_elts(d.args[1], consts)
        sub = 1
        for f in ast.walk(n):
            if isinstance(f, ast.For) and any(isinstance(w, ast.With) and "subTest" in ast.dump(w) for w in ast.walk(f)):
                sub = max(sub, _count_elts(f.iter, consts))
        out[n.lineno] = min(m * sub, MULT_CAP)
    return out


def _js_each_counts(text):
    """{1-based line: case count} for `it.each([...])` / `test.each([...])` / `describe.each([...])` (array literal, or a tagged-template table: rows - header)."""
    ga = _ga()
    masked = ga.mask_text(text, "js")
    starts = ga._line_index(text)
    out = {}
    for m in re.finditer(r"\.each\s*(\(\s*\[|`)", masked):
        ln = ga._lineof(starts, m.start())
        if m.group(1) == "`":
            j = text.find("`", m.end())
            rows = [r for r in text[m.end(): j if j > 0 else len(text)].split("\n") if r.strip()]
            out[ln] = max(1, len(rows) - 1)
            continue
        op = m.end() - 1
        cl = ga.match_close(masked, op)
        if cl < 0:
            continue
        body = masked[op + 1: cl]
        depth, n, seen = 0, 0, False
        for c in body:
            if c in "([{":
                if depth == 0:
                    n += 1
                    seen = True
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif depth == 0 and c not in " \t\n," and not seen:
                pass
        # elements that are scalars at depth 0 (`[1, 2, 3]`): count commas instead
        if n == 0 and body.strip():
            n = len([x for x in body.split(",") if x.strip()])
        out[ln] = max(1, n)
    return out


def _weighted(lang, text):
    """(cases, weighted assertions): every test counts once per parametrize/each/subTest case. None when it cannot be computed."""
    ga = _ga()
    try:
        if lang == "py":
            m = ga.PyModule(text)
            mult = _py_mults(text)
            ts = m.tests().values()
            return sum(mult.get(t.line, 1) for t in ts), sum(t.eff * mult.get(t.line, 1) for t in ts)
        tests = ga.extract_tests_text(lang, text)
        each = _js_each_counts(text) if lang == "js" else {}
        return sum(each.get(t.line, 1) for t in tests.values()), sum(t.eff * each.get(t.line, 1) for t in tests.values())
    except Exception:  # noqa: BLE001
        return None


def rule_assert_drop(repo, status, diffs, out, notes):
    ga = _ga()
    changed = [p for p, st in sorted(status.items()) if st == "M" and ga.lang_of(p) and not ga.ignorable(p) and ga.is_test_path(p) and p in diffs]
    added_lines = {p: len(diffs[p].added) for p in diffs if p in status and ga.is_test_path(p)}
    n = 0
    for p in changed:
        fd = diffs[p]
        old_txt, new_txt = repo.blob(repo.base, fd.old or p), repo.blob(repo.head, p)
        if old_txt is None or new_txt is None:
            continue
        lang = ga.lang_of(p)
        ol, nl = _nonblank(old_txt), _nonblank(new_txt)
        moved = sum(v for q, v in added_lines.items() if q != p) >= DROP_RATIO * max(1, ol - nl)
        why = []
        if ol >= MIN_LINES and nl < ol * (1 - DROP_RATIO) and not moved:
            why.append("non-blank lines %d -> %d (%d%% removed)" % (ol, nl, int(round(100.0 * (ol - nl) / ol))))
        oc, nc = _assert_counts(lang, old_txt), _assert_counts(lang, new_txt)
        # parametrize / .each / subTest consolidation: when the weighted CASE count did not fall (and the file really gained parametrization) this is a refactor,
        # not oracle loss; only "every assertion removed" still counts
        consolidated = False
        wo, wn = _weighted(lang, old_txt), _weighted(lang, new_txt)
        if wo and wn and nc is not None and wn[0] > nc[1] and wn[0] >= wo[0] and wn[1] >= wo[1] * (1 - DROP_RATIO):
            consolidated = True
        if oc is None or nc is None:
            notes.append("y5 assert_drop: assertion counts unavailable for %s (line ratio only)" % p)
        else:
            if oc[0] >= 1 and nc[0] == 0:
                why.append("every effective assertion removed (%d -> 0)" % oc[0])
            elif oc[0] >= MIN_ASSERTS and nc[0] < oc[0] * (1 - DROP_RATIO) and not moved:
                why.append("assertions %d -> %d" % (oc[0], nc[0]))
            if oc[1] >= MIN_ASSERTS and nc[1] < oc[1] * (1 - DROP_RATIO) and not moved:
                why.append("tests %d -> %d" % (oc[1], nc[1]))
        if consolidated:
            why = [w for w in why if w.startswith("every effective assertion")]
        if not why and not moved and not consolidated and oc is not None and nc is not None:
            # deletion-dominant diff (shrike-notify efd06bc1: 381 of 382 changed lines were deletions, 7 of ~40 tests, only 35% of the file): the file shrank
            # by less than half, but the change did nothing except delete oracle. Needs a real net loss, not a rewrite.
            rem, add = len(fd.removed), len(fd.added)
            dlt, dea = oc[0] - nc[0], oc[1] - nc[1]
            if rem >= DOM_MIN_REMOVED and rem >= DOM_FRAC * (rem + add) and (dea >= 3 or (dlt >= 5 and dlt >= 0.2 * oc[0])):
                why.append("deletion-dominant diff (%d of %d changed lines removed): tests %d -> %d, assertions %d -> %d" % (rem, rem + add, oc[1], nc[1], oc[0], nc[0]))
        if not why:
            continue
        f = ga.F("Y_ASSERT_DROP", "FLAG", p, 1, "test file lost most of its oracle: " + "; ".join(why), os.path.basename(p))
        f["subkey"] = "assert_drop"
        out.append(f)
        n += 1
        if n >= CAP:
            notes.append("y5 assert_drop capped at %d" % CAP)
            return


def run_all(repo, repo_name, status, st_raw, diffs, findings, notes, deadline, no_record):
    steps = [("skip_added", lambda: rule_skip_added(repo, status, diffs, findings, notes)),
             ("assert_drop", lambda: rule_assert_drop(repo, status, diffs, findings, notes))]
    for name, fn in steps:
        if time.time() > deadline:
            notes.append("y5 rules skipped from %s (deadline)" % name)
            break
        try:
            fn()
        except Exception as ex:  # noqa: BLE001 - a rule bug must never change the verdict
            notes.append("y5 rule %s errored: %s: %s" % (name, type(ex).__name__, str(ex)[:80]))
