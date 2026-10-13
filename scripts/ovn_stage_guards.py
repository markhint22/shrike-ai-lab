#!/usr/bin/env python3
"""scripts/ovn_stage_guards.py - deterministic guards for the staged runner (ovn_stage_runner.sh) and the implement step (run_overnight.sh). 2026-10-13, package `stage`.

Every guard is plain text / filesystem / AST logic: no model call, no network. The bash side is scripts/lib_stage_guards.sh (thin wrappers + kill switches); the unit tests are
scripts/test/test_stage_guards.py.

  step-mistarget   <wt> <desc> <files...>      xlite F3: a Verify/Check/Confirm plan step whose `files` name a path that does not exist (and is not a test file the step may add) is
                                               MIS-TARGETED. Such a step is refused (the staged runner created and filled a fabricated 52-line scripts/mission/codex_manager.gd for it).
  item-mistarget   <wt> <item>                 xlite F3: an item whose own VERIFY greps a file that does not exist in the pristine tree (and that the item does not create) was aimed at a
                                               wrong path: its VERIFY goes green the moment ANY step creates that file. Park / escalate, never create.
  named-tests-item <item>                      the same for a whole queue-item line
  named-tests      <desc> [<verify>]           iptv F2: the test functions an "Add test ..." item / step promises (names after the add-verb; pytest node ids of its VERIFY).
  resolve-tests    <wt> <name>...              iptv F2: where those functions live in the tree: JSON {found:[{name,kind,path,cls,node}], missing:[...], unverifiable:[...]} (env OVN_SG_CONTEXT = the
                                               promise text; a name not found whose context points only at test files of a language we cannot read with confidence (not Kotlin/Java/Swift) is unverifiable, not missing).
  create-exists    <repo> <item>               xlite F7: a `Create <test file>` item whose target already exists with the named test functions (or, naming none, with every asserted call it names) is already done.
  new-tests        <wt> <base-ref>             iptv F6: node ids of the python test functions the diff base..HEAD ADDED.

Exit 0 = the guard FIRED (mis-targeted / missing / exists) and a one-line reason is printed; exit 1 = nothing to report; exit 2 = usage error. (resolve-tests / new-tests / named-tests always exit 0 and print.)
"""
import ast
import json
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ovn_backlog_eligibility as E  # noqa: E402

_SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".godot", "build", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".gradle", "dist"}

_READONLY_VERB = re.compile(r"^\s*(?:verify|check|confirm)\b", re.I)
_CREATE_VERB = re.compile(r"\b(?:create|add|new|introduce|write|generate)\b", re.I)
_REMOVE_VERB = re.compile(r"\b(?:delete|remove|retire|rename|move|drop|prune)\b", re.I)
_TEST_BASENAME = re.compile(r"^(?:test_.*|.*_test\.[A-Za-z0-9]+|.*\.(?:spec|test)\.[A-Za-z0-9]+)$")


def _body(item):
    """The item text without the checkbox / (tags) / [T3] / [feat:..] prefixes."""
    b = re.sub(r"^\s*- \[[ xX]\] ", "", item.strip())
    b = re.sub(r"^\([^)]*\) ", "", b)
    return re.sub(r"^(\[[^\]]*\]\s*)+", "", b)


def item_desc(item):
    """The description part of an item line: everything before ` VERIFY:` (and before a trailing (cat:...) tag)."""
    d = re.split(r"\bVERIFY:", _body(item), maxsplit=1)[0]
    return re.sub(r"\s*\(cat:[^)]*\).*$", "", d).strip()


def item_action(item):
    """The instruction after the leading `<path> — ` of the description ('Verify no other suffixes ...'); the whole description when there is no leading path."""
    d = item_desc(item)
    m = re.match(r"^\S+\s+(?:—|–|-)\s+(.*)$", d, re.S)
    return (m.group(1) if m else d).strip()


def item_target(item):
    t = _body(item).split(" ")[0] if _body(item) else ""
    return t.replace("`", "").split(":")[0]


def is_test_path(p):
    base = os.path.basename(p)
    parts = p.replace("\\", "/").split("/")
    return bool(_TEST_BASENAME.match(base)) or any(x in ("tests", "test", "__tests__") for x in parts[:-1])


# ---------------------------------------------------------------- xlite F3: mis-targeted steps / items
def step_mistarget(wt, desc, files):
    """Reason string when a read-only (Verify/Check/Confirm) plan step names files that do not exist; None otherwise. A missing TEST file is fine (a verification step may add a test)."""
    if not _READONLY_VERB.match(desc or ""):
        return None
    missing = [f for f in files if f and not os.path.exists(os.path.join(wt, f)) and not is_test_path(f)]
    if not missing:
        return None
    return "read-only step (%s) names non-existent file(s): %s - refusing to create it" % ((desc or "").strip()[:60], ", ".join(missing[:4]))


_GREP_TOOLS = {"grep", "egrep", "fgrep", "rg", "ag", "zgrep"}
_OPT_WITH_ARG = {"-e", "-f", "-m", "-A", "-B", "-C", "-d", "-D", "--include", "--exclude", "--exclude-dir", "--max-count", "--regexp", "--file", "--label", "--context"}
_SHORT_WITH_ARG = "efmABCdD"


def grep_file_operands(clause):
    """File / directory operands of ONE grep-family clause (pattern and options removed), or None when the clause is not a grep or does not parse."""
    try:
        toks = shlex.split(clause)
    except ValueError:
        return None
    while toks and (toks[0] == "!" or re.match(r"^[A-Za-z_]\w*=", toks[0])):
        toks.pop(0)
    if not toks or os.path.basename(toks[0]) not in _GREP_TOOLS:
        return None
    pat_given = False
    ops = []
    i = 1
    while i < len(toks):
        t = toks[i]
        if t == "--":
            rest = toks[i + 1:]
            if not pat_given and rest:
                rest = rest[1:]
            ops += rest
            break
        if t.startswith("--"):
            if "=" in t:
                if t.split("=", 1)[0] in ("--regexp", "--file"):
                    pat_given = True
                i += 1
                continue
            if t in _OPT_WITH_ARG:
                if t in ("--regexp", "--file"):
                    pat_given = True
                i += 2
                continue
            i += 1
            continue
        if t.startswith("-") and len(t) > 1:
            consumed_next = False
            for k, ch in enumerate(t[1:], 1):
                if ch in _SHORT_WITH_ARG:
                    if ch in "ef":
                        pat_given = True
                    if k == len(t) - 1:      # value is the next token
                        consumed_next = True
                    break
            i += 2 if consumed_next else 1
            continue
        if not pat_given:
            pat_given = True
        else:
            ops.append(t)
        i += 1
    return ops


_PATH_EXT = re.compile(r"\.[A-Za-z][A-Za-z0-9]{0,7}$")


def looks_like_path(op):
    """True only for a token that is plausibly a repo-relative file / directory operand: it contains a '/' or ends in a file extension, and carries no shell / prose punctuation. A narration word
    ('line', '41', 'matches'), a trailing-period token ('parental.py.') or a process-substitution fragment ('<(grep') is NOT a path and is never judged (2026-10-13 reviewer replay: a dozen false
    mis-target verdicts on items whose VERIFY was not backticked)."""
    if not op or any(c in op for c in " \t\n<>()|&;,!\"'=") or op[-1] in ".,:)":
        return False
    return "/" in op or bool(_PATH_EXT.search(op))


def _suppresses_missing_file_errors(toks):
    """True when a grep clause silences 'No such file' (stderr redirected away, `-s` / `--no-messages`): a missing operand is then expected, not an error the VERIFY would trip over."""
    for t in toks[1:]:
        if t.startswith("2>") or t == "--no-messages":
            return True
        if re.match(r"^-[A-Za-z]+$", t) and "s" in t[1:] and toks[0] in _GREP_TOOLS:
            return True
    return False


def _split_ops(cmd):
    """Quote-aware split of a shell command on && || ; | KEEPING the operator that precedes each clause: [(op_before, clause), ...] with op_before in ('', '&&', '||', ';', '|'). None when quotes do not
    balance. (E._split_clauses drops the operators; the mis-target judge needs them to tell a presence check from an `||` alternative or an absence idiom.)"""
    out, cur, q, i, op = [], "", "", 0, ""
    while i < len(cmd):
        ch = cmd[i]
        if q:
            cur += ch
            if ch == q:
                q = ""
        elif ch in "'\"":
            q = ch
            cur += ch
        elif cmd.startswith("&&", i) or cmd.startswith("||", i):
            out.append((op, cur))
            cur, op = "", cmd[i:i + 2]
            i += 1
        elif ch in ";|":
            out.append((op, cur))
            cur, op = "", ch
        else:
            cur += ch
        i += 1
    out.append((op, cur))
    return None if q else [(o, c.strip()) for o, c in out if c.strip()]


_FOUND_IS_BAD_MSG = re.compile(r"\b(?:fail\w*|bad|error|still|leak\w*|remain\w*|violat\w*)\b", re.I)


def _is_grep_clause(clause):
    toks = clause.split()
    while toks and (toks[0] == "!" or re.match(r"^[A-Za-z_]\w*=", toks[0])):
        toks = toks[1:]
    return bool(toks) and os.path.basename(toks[0]) in _GREP_TOOLS


def _absence_or_alternative(ops, i):
    """True when the grep clause ops[i] is NOT a plain presence check, so a missing operand is not evidence of a mis-aim (reviewer 2026-10-13, shapes 1 and 2):
      - negated (`! grep -q X missing.py`);
      - one side of an `||` alternative with another grep (`grep -q X app/a.py || grep -q X app/b.py`: either file may be the one that exists);
      - an absence idiom: `grep -q X f && echo FAIL ...` (found = bad) or a later clause inspecting `$?` (`grep X f; test $? -ne 0`)."""
    op_before, clause = ops[i]
    toks = clause.split()
    if toks and toks[0] == "!":
        return True
    if i + 1 < len(ops) and ops[i + 1][0] == "||" and _is_grep_clause(ops[i + 1][1]):
        return True
    if op_before == "||" and i > 0 and _is_grep_clause(ops[i - 1][1]):
        return True
    if any("$?" in c for _o, c in ops[i + 1:]):
        return True
    if i + 1 < len(ops) and ops[i + 1][0] == "&&":
        nxt = ops[i + 1][1].split()
        if nxt and nxt[0] in ("echo", "printf") and _FOUND_IS_BAD_MSG.search(ops[i + 1][1]):
            return True
    return False


def verify_missing_operands(wt, cmd, pkg_dirs=()):
    """Relative file operands of the grep-family stages of `cmd` that do not exist under wt (a `cd <dir>` stage moves the base). Globs, absolute paths, shell expansions and anything that does not
    look like a path (looks_like_path) are never judged; neither are operands of an absence check / `||` alternative (_absence_or_alternative), nor an operand that does exist under one of `pkg_dirs`
    (a package-relative VERIFY: item `billwatch-backend/app/x.py` greps `app/x.py`)."""
    ops = _split_ops(cmd or "")
    if not ops:
        return []
    base = ""
    missing = []
    # A count-based verdict (`grep -r X a b 2>/dev/null | wc -l` returns 0) is an absence check whose verdict is the COUNT: a missing file is simply zero matches, not a mis-aim.
    if any(cl.split()[:1] == ["wc"] for _o, cl in ops):
        return []
    for i, (_o, cl) in enumerate(ops):
        toks = cl.split()
        if _suppresses_missing_file_errors(toks):
            continue          # the author tolerates a missing operand (2>/dev/null, grep -s): not a mis-aim
        if toks and toks[0] == "cd" and len(toks) >= 2:
            tgt = toks[1].strip("'\"")
            if not tgt.startswith(("/", "~", "$")):
                base = os.path.normpath(os.path.join(base, tgt))
            continue
        fops = grep_file_operands(cl)
        if fops and _absence_or_alternative(ops, i):
            continue
        for op in fops or []:
            if not op or op.startswith(("/", "-", "~")) or any(c in op for c in "*?[]{}$`") or op in (".", "./") or not looks_like_path(op):
                continue
            rel = os.path.normpath(os.path.join(base, op))
            if rel.startswith(".."):
                continue
            if not os.path.exists(os.path.join(wt, rel)) and not any(os.path.exists(os.path.join(wt, d, rel)) for d in pkg_dirs):
                missing.append(rel)
    return missing


def item_mistarget(wt, item):
    """Reason string when the item's own VERIFY greps a file that does not exist in the pristine tree and the item does not create it; None otherwise (absence checks / delete items are never judged)."""
    # ONLY a backticked VERIFY clause is judged: for a bare clause (`VERIFY: shows a match near line 41`) verify_clause_and_polarity hands back the narration as the "command" and its words
    # would be read as file operands.
    bm = re.search(r"VERIFY:\s*`([^`]+)`", item or "")
    if not bm:
        return None
    cmd = bm.group(1).strip()
    if E.verify_clause_and_polarity(item)[1] == "neg":
        return None
    action = item_action(item)
    if _REMOVE_VERB.search(action[:160]):
        return None
    tdir = os.path.dirname(item_target(item))
    pkg_dirs = ["/".join(tdir.split("/")[:k]) for k in range(1, len(tdir.split("/")) + 1)] if tdir else []
    missing = verify_missing_operands(wt, cmd, pkg_dirs)
    if not missing:
        return None
    creates = bool(_CREATE_VERB.search(action))
    desc = item_desc(item)
    tgt = item_target(item)
    left = []
    for m in missing:
        if creates and (m == tgt or os.path.basename(m) in desc):
            continue          # the item itself creates that path
        left.append(m)
    if not left:
        return None
    return "the item's own VERIFY greps non-existent file(s) %s (not created by the item) - the item is aimed at a wrong path" % ", ".join(sorted(set(left))[:4])


# ---------------------------------------------------------------- iptv F2: named tests must exist and pass
_NAME = r"[`'\"]?(test_[A-Za-z0-9_]+)(?![A-Za-z0-9_]*\.[A-Za-z0-9])"
_ADD_NAMED = re.compile(r"\b(?:add|create|write|implement|introduce|include)\b[^.;:\n]*?\btests?(?:\s+(?:function|case|method))?(?:\s+(?:named|called))?\s+" + _NAME
                        + r"((?:\s*(?:,|and|&)\s*" + _NAME + r")*)", re.I)
_ADD_TEST_WORD = re.compile(r"\b(?:add|create|write|implement|introduce|include)\b[^.;:\n]*?\btests?\b", re.I)
_NODE_ID = re.compile(r"::(?:[A-Za-z_][A-Za-z0-9_]*::)?(test_[A-Za-z0-9_]+)")
_NAME_TOKEN = re.compile(r"test_[A-Za-z0-9_]+")


def named_tests(desc, verify=""):
    """Test function names an 'Add test ...' description promises, in order, deduplicated. Names come from the add-verb phrase ('Add test test_x', 'Add tests test_a and test_b') and, when the
    description does ask for a test, from the pytest node ids of its VERIFY ('pytest f.py::test_x'). A description without an add-verb + 'test' never yields names (a 'Mirror test_x' reference is not a promise)."""
    out = []
    d = desc or ""
    for m in _ADD_NAMED.finditer(d):
        names = [m.group(1)] + _NAME_TOKEN.findall(m.group(2) or "")
        for n in names:
            if n not in out:
                out.append(n)
    if out or _ADD_TEST_WORD.search(d):
        for n in _NODE_ID.findall(verify or ""):
            if n not in out:
                out.append(n)
    return out


def _walk(wt, exts):
    for dp, dns, fns in os.walk(wt):
        dns[:] = [x for x in dns if x not in _SKIP_DIRS]
        for fn in fns:
            if fn.endswith(exts):
                yield os.path.join(dp, fn)


def _py_defs(path):
    """{name: class-or-None} of the test functions in a python file (module level and one class deep)."""
    out = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            tree = ast.parse(f.read())
    except (OSError, SyntaxError, ValueError):
        return out
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out.setdefault(node.name, None)
        elif isinstance(node, ast.ClassDef):
            for sub in node.body:
                if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    out.setdefault(sub.name, node.name)
    return out


_GD_FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(test_[A-Za-z0-9_]+)\s*\(", re.M)


# Test functions in the other languages the fleet's repos carry. They are only LOCATED (the by-node-id run is python only), but locating them matters: iptv_apps has Kotlin / Swift tests named
# `fun test_createSource_triggersAutoMap()` / `func test_x()`, and a promise to add one must not be reported 'missing' just because it is not python (2026-10-13 reviewer repro).
_OTHER_LANGS = (
    ("kt", (".kt", ".kts", ".java"), re.compile(r"\b(?:fun|void)\s+`?(test_[A-Za-z0-9_]+)`?\s*\(")),
    ("swift", (".swift",), re.compile(r"\bfunc\s+`?(test_[A-Za-z0-9_]+)`?\s*\(")),
    ("js", (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"), re.compile(r"(?:\bfunction\s+(test_[A-Za-z0-9_]+)\s*\(|\b(?:test|it)(?:\.\w+)?\(\s*[`'\"](test_[A-Za-z0-9_]+)[`'\"]|\b(?:const|let|var)\s+(test_[A-Za-z0-9_]+)\s*=)")),
    ("rs", (".rs",), re.compile(r"\bfn\s+(test_[A-Za-z0-9_]+)\s*\(")),
)
_NONPY_TEST_PATH = re.compile(r"[\w./-]+\.(?:kt|kts|java|swift|ts|tsx|js|jsx|mjs|cjs|rs|m|mm|cs|dart|rb|go|php)\b")
_PYGD_PATH = re.compile(r"[\w./-]+\.(?:py|gd)\b")


# Languages whose test functions this guard LOCATES with a regex it trusts (Kotlin / Java / Swift: the fleet's native iptv_apps tests). A promised test of one of THOSE that is defined nowhere is MISSING
# (second review 2026-10-13: it used to fail open as 'unverifiable', so a never-written Kotlin / Swift test was credited). Every other non-python language stays unverifiable.
_VERIFIABLE_EXTS = (".kt", ".kts", ".java", ".swift")


def unverifiable_context(context):
    """True when the text a promise came from (item line / step descriptions) points at test files of a language this guard cannot read with confidence (TS / JS / Rust / ObjC / C# / Dart ...), and
    at no python / GDScript file: a test promised there can be neither located nor run, so it must never be reported missing (no finding). A context naming ONLY Kotlin / Java / Swift files is
    verifiable (resolve_tests locates `fun test_x` / `func test_x`), so a promised test defined nowhere is missing."""
    c = context or ""
    if _PYGD_PATH.search(c):
        return False
    paths = _NONPY_TEST_PATH.findall(c)
    return any(not p.lower().endswith(_VERIFIABLE_EXTS) for p in paths)


def resolve_tests(wt, names, context=""):
    """Where the named tests are defined: python (def / method), GDScript (func), and Kotlin / Java / Swift / TS / JS / Rust files under wt (located, never run). missing = names with no definition
    anywhere; unverifiable = names not found whose `context` points only at a language we do not read (they are NOT in missing)."""
    found = []
    want = set(names)
    seen = {n: False for n in names}
    for p in _walk(wt, (".py",)):
        defs = _py_defs(p)
        for n in want & set(defs):
            rel = os.path.relpath(p, wt)
            cls = defs[n]
            found.append({"name": n, "kind": "py", "path": rel, "cls": cls, "node": "%s::%s%s" % (rel, (cls + "::") if cls else "", n)})
            seen[n] = True
    for p in _walk(wt, (".gd",)):
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                txt = f.read()
        except OSError:
            continue
        for n in want & set(_GD_FUNC.findall(txt)):
            rel = os.path.relpath(p, wt)
            found.append({"name": n, "kind": "gd", "path": rel, "cls": None, "node": rel})
            seen[n] = True
    for kind, exts, rx in _OTHER_LANGS:
        for p in _walk(wt, exts):
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    txt = f.read()
            except OSError:
                continue
            hit = set()
            for m in rx.finditer(txt):
                hit.update(g for g in m.groups() if g)
            for n in want & hit:
                rel = os.path.relpath(p, wt)
                found.append({"name": n, "kind": kind, "path": rel, "cls": None, "node": rel})
                seen[n] = True
    notfound = [n for n in names if not seen[n]]
    unver = notfound if (notfound and unverifiable_context(context)) else []
    missing = [n for n in notfound if n not in unver]
    return {"found": found, "missing": missing, "unverifiable": unver}


def new_tests(wt, base):
    """Node ids ('path::[Class::]name') of the python test functions defined at HEAD in files changed since `base` whose `def test_x` line was ADDED by the diff."""
    try:
        diff = subprocess.run(["git", "-C", wt, "diff", "-U0", "--no-color", base + "..HEAD", "--", "*.py"], capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    cur, added = None, {}
    for ln in diff.splitlines():
        if ln.startswith("+++ b/"):
            cur = ln[6:]
        elif ln.startswith("+") and not ln.startswith("+++") and cur:
            m = re.match(r"^\+\s*(?:async\s+)?def\s+(test_[A-Za-z0-9_]+)\s*\(", ln)
            if m:
                added.setdefault(cur, []).append(m.group(1))
    out = []
    for rel, names in added.items():
        defs = _py_defs(os.path.join(wt, rel))
        for n in names:
            if n in defs:
                out.append("%s::%s%s" % (rel, (defs[n] + "::") if defs[n] else "", n))
    return out


def named_tests_item(item):
    """named_tests() of a whole queue-item line (description + its VERIFY command)."""
    return named_tests(item_desc(item), E.extract_verify(item) or "")


# ---------------------------------------------------------------- xlite F7: Create <test file> that already exists
_BACKTICK = re.compile(r"`([^`]+)`")
_TRAIL_CMP = re.compile(r"\s*(?:==|!=|<=|>=|<|>)\s*\S+\s*$")
_CALL_HEAD = re.compile(r"^[A-Za-z_][\w.]*(?:\(|\.)")


def _is_call_with_args(sp):
    """A code span that is a call (or call chain) with at least one NON-EMPTY argument list: `a.b("x")`, `Aggro.new().is_valid_directive(5)`. Not `Unit.display_name()`, not a bare identifier."""
    if not _CALL_HEAD.match(sp) or sp.count("(") != sp.count(")") or "(" not in sp:
        return False
    return bool(re.search(r"\([^()]*[^()\s][^()]*\)", sp))


def _norm_code(t):
    return re.sub(r"\s+", " ", (t or "").replace("'", '"')).strip()


def _anchors(desc):
    """Assertion-grade evidence an item names inside backticks: a CALL WITH ARGUMENTS such as `FileAccess.file_exists("res://scripts/battle/save_manager.gd") == false` or
    `Aggro.new().is_valid_directive(5)` (a trailing comparison is dropped). A bare identifier (`submit_feedback`, `EVENT_REGISTRATION_SUCCESS`) is NOT evidence: every existing test file for that
    function mentions it (2026-10-13 reviewer replay: ~15 false 'already done' hits). Normalized (whitespace, quote style), order-preserving, deduplicated."""
    out = []
    for span in _BACKTICK.findall(desc or ""):
        sp = _TRAIL_CMP.sub("", span.strip())
        if _is_call_with_args(sp):
            n = _norm_code(sp)
            if n not in out:
                out.append(n)
    return out


def create_exists(repo, item):
    """(True, path, names, why) ONLY when the item says Create/Add/Write for a TEST file that already exists in `repo` AND the file demonstrably already does what the item asks for:
      (a) the item NAMES test function(s) (`Create tests test_a and test_b`, `Add test test_x`) and every one of them is defined in the file; or
      (b) it names none, but it names >= 1 backticked CALL WITH ARGUMENTS (`FileAccess.file_exists("res://...")`; see _anchors) and EVERY such call occurs verbatim in the file.
    The file merely containing OTHER test functions - or merely mentioning the function under test - proves nothing: `Add a test case verifying X` is the normal way to add a test to a file that
    already has some (2026-10-13 reviewer replay: ~15 of 26 open-queue hits were that false 'already done', and a flipped OVN_CREATE_EXISTS=on would have credited them without the test ever being
    written). An item that names neither a function nor such a call is never short-circuited.
    The true case it exists for (xlite 2026-10-13): the file is already there with the item's assertion; the implement step would only append a duplicate class body (extends GutTest twice,
    the fix-up undid the item)."""
    action = item_action(item)
    if not re.match(r"^\s*(?:create|add|write|generate)\b", action, re.I) or _REMOVE_VERB.search(action[:100]):
        return (False, "", [], "not a create item")
    tgt = item_target(item)
    if not tgt or not is_test_path(tgt) or not tgt.endswith((".gd", ".py")):
        return (False, tgt, [], "target is not a test file")
    p = os.path.join(repo, tgt)
    if not os.path.isfile(p):
        return (False, tgt, [], "target does not exist")
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            txt = f.read()
    except OSError:
        return (False, tgt, [], "unreadable")
    have = set(_GD_FUNC.findall(txt)) if tgt.endswith(".gd") else {n for n in _py_defs(p) if n.startswith("test_")}
    if not have:
        return (False, tgt, [], "the file defines no test function")
    tbase = os.path.basename(tgt)
    desc = item_desc(item)
    wanted = []
    for n in _NAME_TOKEN.findall(desc):
        if n == os.path.splitext(tbase)[0] or n in wanted:
            continue
        wanted.append(n)
    wanted = [n for n in wanted if n not in (tbase,)]
    if wanted:
        missing = [n for n in wanted if n not in have]
        if missing:
            return (False, tgt, wanted, "the file lacks named test(s): " + ", ".join(missing[:4]))
        return (True, tgt, wanted, "target exists with the named test function(s)")
    anchors = _anchors(desc)
    if not anchors:
        return (False, tgt, [], "the item names no test function and no asserted call: an existing file with other tests proves nothing")
    ntxt = _norm_code(txt)
    absent = [a for a in anchors if a not in ntxt]
    if absent:
        return (False, tgt, anchors, "the file does not contain: " + ", ".join(absent[:4]))
    return (True, tgt, anchors[:4], "target exists and contains every asserted call the item names")


# ---------------------------------------------------------------- CLI
def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "step-mistarget" and len(argv) >= 4:
        r = step_mistarget(argv[2], argv[3], argv[4:])
        if r:
            print(r)
            return 0
        return 1
    if cmd == "item-mistarget" and len(argv) == 4:
        r = item_mistarget(argv[2], argv[3])
        if r:
            print(r)
            return 0
        return 1
    if cmd == "named-tests" and len(argv) >= 3:
        print("\n".join(named_tests(argv[2], argv[3] if len(argv) > 3 else "")))
        return 0
    if cmd == "named-tests-item" and len(argv) == 3:
        print("\n".join(named_tests_item(argv[2])))
        return 0
    if cmd == "resolve-tests" and len(argv) >= 3:
        print(json.dumps(resolve_tests(argv[2], argv[3:], os.environ.get("OVN_SG_CONTEXT", ""))))
        return 0
    if cmd == "create-exists" and len(argv) == 4:
        ok, path, names, why = create_exists(argv[2], argv[3])
        if ok:
            print("%s\t%s\t%s" % (path, ",".join(names), why))
            return 0
        return 1
    if cmd == "new-tests" and len(argv) == 4:
        print("\n".join(new_tests(argv[2], argv[3])))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
