#!/usr/bin/env python3
"""ovn_landing_gates.py - package Z3 (2026-11-07) landing-quality gates. Deterministic, LLM-free, stdlib only (Python 3.9+).

Incident class: the 2026-11-07 landing audit (H1-H9). Staged steps whose diff did something other than their text, a hallucinated greeting test satisfied by a new
public route, product copy rewritten to "Hey/Yo/Buzz", a rewritten function that silently dropped its `_save_roster()` call, test items that edited app source, one
item landing 7 times in a day. Every gate here is SHADOW by default: it journals a finding and changes nothing. Each has its own env flag
(off | shadow | enforce) read by scripts/lib_landing_gates.sh; this module only computes verdicts.

  B1 step-diff-mismatch  OVN_Z3_STEP_DIFF      tokens quoted in the step text (`code`, attr="value", 'literal', snake_case/CamelCase names) must show up in the step's
                                               added lines (post-image for names that legitimately pre-exist). Flag when >= OVN_Z3_STEPDIFF_RATIO (0.5) of them are absent.
  B2 tone-lint           OVN_Z3_TONE           greeting/slang tokens (OVN_Z3_TONE_TOKENS, default Hey|Yo|Buzz|Hi there|Howdy|Oh no|Whoa|Yikes) newly ADDED in a line of a
                                               file, and not already used in that file's removed lines, and not named by the item/step text.
  B3 repair-new-route    OVN_Z3_REPAIR_ROUTE   a "repair staged item to pass verification" diff may not ADD a route decorator / app.get|post(...) / add_api_route(...).
  B4 test-item-src-edit  OVN_Z3_TEST_SRC       an item that only creates/changes tests (cat:test, or every declared file is a test file) may not touch a non-test source file.
  B5 call-dropped        OVN_Z3_CALL_DROP      (FLAG only, no enforce) a function lost a bare statement call it made before and no longer mentions the name (py by AST,
                                               gd by indentation), and was not mostly rewritten.
  B6 landing-cap         OVN_Z3_LANDING_CAP    an item hash that landed >= OVN_Z3_LANDING_CAP_N (3) times in OVN_Z3_LANDING_CAP_H (24) hours is parked.
  B0 editor-example-leak OVN_Z3_EDITOR_LEAK    root cause of the Hey/Yo/Buzz copy: aider's editor-whole few-shot ("Change the greeting to be more casual" /
                                               show_greeting.py) is replayed when the architect hands the editor no actionable instruction. The step log is checked.

CLI (stdout is one JSON line):
  step-check   --desc T [--item T] [--kind step|repair] [--files "a b"] (--diff FILE|- | --repo R --base REV [--head REV])
  leak-check   --log FILE
  cap-check    --outcomes FILE --hash H [--now EPOCH] [--window-h 24] [--n 4]
  cap-park     --progress FILE --text ITEM_TEXT --count N
  corpus       --repo R --since 7.days [--rev REV ...]       (read-only git; per-commit findings of B1-B5)
"""
import argparse
import ast
import json
import os
import re
import subprocess
import sys
import time

# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# diff parsing
# ----------------------------------------------------------------------------------------------------------------------------------------------------------


class FileDiff(object):
    def __init__(self, path, old_path=None):
        self.path = path
        self.old_path = old_path or path
        self.added = []      # (new_lineno, text)
        self.removed = []    # (old_lineno, text)
        self.context = []    # text of context lines (only when the diff has context)
        self.is_new = False
        self.is_deleted = False
        self.hunks = []      # Z5: [{"rem": [(old_lineno, text)], "add": [(new_lineno, text)]}] one per @@ block


def parse_diff(text):
    files, cur, old_ln, new_ln = [], None, 0, 0
    for raw in text.split("\n"):
        if raw.startswith("diff --git "):
            m = re.match(r"diff --git a/(.*?) b/(.*)$", raw)
            cur = FileDiff(m.group(2), m.group(1)) if m else None
            if cur:
                files.append(cur)
            continue
        if cur is None:
            continue
        if raw.startswith("new file mode"):
            cur.is_new = True
        elif raw.startswith("deleted file mode"):
            cur.is_deleted = True
        elif raw.startswith("rename to "):
            cur.path = raw[len("rename to "):]
        elif raw.startswith("+++ "):
            p = raw[4:].strip()
            if p.startswith("b/"):
                cur.path = p[2:]
        elif raw.startswith("--- "):
            p = raw[4:].strip()
            if p.startswith("a/"):
                cur.old_path = p[2:]
        elif raw.startswith("@@"):
            m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw)
            if m:
                old_ln, new_ln = int(m.group(1)), int(m.group(2))
            cur.hunks.append({"rem": [], "add": []})
        elif raw.startswith("+"):
            cur.added.append((new_ln, raw[1:]))
            if cur.hunks:
                cur.hunks[-1]["add"].append((new_ln, raw[1:]))
            new_ln += 1
        elif raw.startswith("-"):
            cur.removed.append((old_ln, raw[1:]))
            if cur.hunks:
                cur.hunks[-1]["rem"].append((old_ln, raw[1:]))
            old_ln += 1
        elif raw.startswith(" "):
            cur.context.append(raw[1:])
            old_ln += 1
            new_ln += 1
    return files


TEST_PATH_RE = re.compile(
    r"(^|/)(tests?|__tests__|__fixtures__|__snapshots__|spec|specs|androidTest|androidUnitTest|e2e|fixtures?|__mocks__|testdata|test_data|test-data|mocks?|"
    r"test_?helpers?|test-helpers?|testhelpers?|test_?utils?|test-utils?|testutils?|test_?support|test-support|testsupport|testing|testlib|test_?lib|snapshots?)/|"
    r"(^|/)(conftest|test_?helpers?|test_?utils?|testutils?|test_?support)\.\w+$|"
    r"(^|/)(test_[^/]*\.\w+|conftest\.py|[^/]*_test\.\w+|[^/]*\.(test|spec)\.\w+|[^/]*(Test|Tests|Spec)\.(kt|java|swift))$")


def is_test_path(p):
    return bool(TEST_PATH_RE.search(p or ""))


DOC_EXT = (".md", ".txt", ".rst", ".lock", ".json", ".yml", ".yaml", ".toml", ".cfg", ".ini", ".svg", ".png", ".jpg", ".csv")
SRC_EXT = (".py", ".gd", ".ts", ".tsx", ".js", ".jsx", ".vue", ".kt", ".java", ".swift", ".html", ".htm", ".xml", ".sh", ".css", ".scss", ".jinja", ".j2")


def is_source_path(p):
    p = p or ""
    return p.endswith(SRC_EXT) and not is_test_path(p)


def _lines_text(fd):
    return "\n".join(t for _, t in fd.added)


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B1 step-diff consistency
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

_ATTR_RE = re.compile(r"(?<![\w-])([A-Za-z_:@][\w:.-]*)\s*=\s*(\"[^\"\n]{1,60}\"|'[^'\n]{1,60}')")
_BT_RE = re.compile(r"`([^`\n]{2,70})`")
_QUOTE_RE = re.compile(r"(?<![\w=])(\"[^\"\n]{3,60}\"|'[^'\n]{3,60}')")
_SNAKE_RE = re.compile(r"(?<![\w./-])([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(?![\w/-]|\.[A-Za-z]{1,5}\b)")
_CAMEL_RE = re.compile(r"(?<![\w./-])([A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+|[a-z]+[A-Z][A-Za-z0-9]*)(?![\w/-]|\.[A-Za-z]{1,5}\b)")
_STOP_WORDS = {"OpenAPI", "GitHub", "JavaScript", "TypeScript", "FastAPI", "PostgreSQL", "SQLAlchemy", "LiteLLM", "WebSocket", "SwiftUI", "iOS", "tvOS", "macOS", "YouTube", "PyTest", "VoiceOver", "TalkBack", "NotImplementedError"}
_GENERIC_IDENT = {"python_3", "end_to_end", "per_file", "e_g", "i_e", "side_effect", "type_check", "case_insensitive", "read_only", "non_empty", "must_not"}


def _is_pathlike(tok):
    return "/" in tok or bool(re.search(r"\.(py|ts|tsx|js|jsx|vue|kt|swift|gd|md|json|html|css|xml|sh|yml|yaml|toml|txt)$", tok))


# D4 (2026-11-07 review): in a rename / replace / "from X to Y" step the OLD token legitimately disappears, so only the NEW side (and tokens after add/insert/create/use/set)
# must show up in the added lines. These regexes capture the old side; any token overlapping one of those spans is not required.
_OLD_SIDE_RES = [
    re.compile(r"\b(?:rename|renaming)\s+(.{1,80}?)\s+(?:to|as|into)\s", re.I),
    re.compile(r"\b(?:replace|replacing|swap|swapping)\s+(.{1,80}?)\s+(?:with|by|for|to|into)\s", re.I),
    re.compile(r"\b(?:change|changing|convert|switch|update|migrate|move)\s+(.{1,80}?)\s+(?:to|into)\s", re.I),
    re.compile(r"\bfrom\s+(.{1,80}?)\s+(?:to|into)\s", re.I),
    re.compile(r"\binstead of\s+(.{1,60}?)(?:[,;.]|\s+(?:and|in|on|at)\s|$)", re.I),
    re.compile(r"(.{1,60}?)\s*(?:->|\u2192)\s", re.I),
]


def old_side_spans(desc):
    out = []
    for rx in _OLD_SIDE_RES:
        for m in rx.finditer(desc or ""):
            out.append(m.span(1))
    return out


def step_tokens(desc, files="", truncated=None):
    """-> list of dicts {kind: attr|quoted|ident, tok, strong}. Pure; the step text may be truncated (commit subject): a token touching a >= 68 char text end is dropped."""
    desc = desc or ""
    trunc = (len(desc) >= 68) if truncated is None else bool(truncated)
    fnames = set()
    for f in re.split(r"[\s,]+", files or ""):
        if f:
            fnames.add(f)
            fnames.add(os.path.basename(f))
            fnames.add(os.path.splitext(os.path.basename(f))[0])
    seen, out = set(), []

    old_spans = old_side_spans(desc)

    def add(kind, tok, strong, end, start=None):
        if trunc and end >= len(desc.rstrip()) and kind != "attr":
            return
        if start is not None and any(a < end and start < b for a, b in old_spans):
            return          # the OLD side of a rename/replace/from-to phrase: it is expected to disappear
        key = (kind, tok)
        if key not in seen:
            seen.add(key)
            out.append({"kind": kind, "tok": tok, "strong": strong})
    spans = []
    for m in _ATTR_RE.finditer(desc):
        if trunc and m.end() >= len(desc.rstrip()) and not (m.group(2)[-1] in "\"'"):
            continue
        add("attr", m.group(1) + "=" + m.group(2), True, m.end(), m.start())
        spans.append(m.span())
    for m in _BT_RE.finditer(desc):
        t = m.group(1).strip()
        if any(a <= m.start() < b for a, b in spans):
            continue
        spans.append(m.span())
        if _is_pathlike(t) or t in fnames or re.match(r"^</?\w+/?>$", t) or " " in t.strip() and not re.search(r"[()=\"']", t):
            continue
        # a backticked call/expression: keep the identifier part for matching, but the literal for strong
        add("quoted", t, True, m.end(), m.start())
    for m in _QUOTE_RE.finditer(desc):
        if any(a <= m.start() < b for a, b in spans):
            continue
        spans.append(m.span())
        t = m.group(1)
        if _is_pathlike(t.strip("\"'")) or t.strip("\"'") in fnames:
            continue
        add("quoted", t, True, m.end(), m.start())
    masked = list(desc)
    for a, b in spans:
        for i in range(a, b):
            masked[i] = " "
    mt = "".join(masked)
    for rx in (_SNAKE_RE, _CAMEL_RE):
        for m in rx.finditer(mt):
            t = m.group(1)
            if len(t) < 6 or t in fnames or t in _GENERIC_IDENT or t in _STOP_WORDS or _is_pathlike(t) or re.search(r"(Error|Exception)$", t):
                continue
            add("ident", t, False, m.end(), m.start(1))
    return out


def _norm(s):
    return re.sub(r"\s+", "", (s or "").replace("'", '"'))


def check_step_diff(desc, diff_files, post_text=None, files="", ratio=0.5, truncated=None):
    """-> findings list (rule step-diff-mismatch) for one step. post_text: concatenated post-image text of touched files (lenient pool for names that pre-exist)."""
    toks = step_tokens(desc, files, truncated)
    if not toks or not diff_files:
        return []
    # a removal step ("Remove X", "Delete the X") is satisfied by the token in the REMOVED lines
    removal = bool(re.match(r"^\s*(?:\[T\d\]\s*)?(remove|delete|drop|strip|clean up|get rid of)\b", desc or "", re.I))
    added = "\n".join(_lines_text(f) for f in diff_files)
    if removal:
        added = added + "\n" + "\n".join(t for f in diff_files for _, t in f.removed)
    # a module/component name that is the stem of a touched file is the file, not a symbol the step must add
    stems = set()
    for f in diff_files:
        b = os.path.basename(f.path)
        stems.add(os.path.splitext(b)[0])
        stems.add(b)
    toks = [t for t in toks if t["tok"] not in stems]
    if not toks:
        return []
    added_n = _norm(added)
    pool_n = _norm(added + "\n" + (post_text or "") + "\n" + "\n".join("\n".join(f.context) for f in diff_files))
    missing = []
    for t in toks:
        tok = t["tok"]
        if t["kind"] == "attr":
            name, val = tok.split("=", 1)
            nm = name.lstrip(":@").lower()
            ok = (nm in added.lower() or name.lower() in added.lower()) and _norm(val) in added_n
            # an attribute value may legitimately pre-exist when the step only binds it
            if not ok and post_text is not None and _norm(tok) in _norm(post_text) and _norm(tok) not in added_n:
                ok = False
        elif t["kind"] == "quoted":
            core = tok.strip("\"'")
            ok = _norm(tok) in added_n or (len(core) >= 3 and _norm(core) in added_n)
            # a literal that was closed differently (dict/call with extra keys after the quoted part) still matches on its opening part
            if not ok and re.search(r"[{(\[]", tok):
                head = _norm(tok).rstrip("})]")
                ok = len(head) >= 8 and head in added_n
            if not ok and not re.search(r"[\"'=]", tok):
                ok = _norm(tok) in pool_n
            if not ok and re.match(r"^[\w.]+(\(.*\))?$", tok):
                head = re.match(r"^[\w.]+", tok).group(0)
                ok = _norm(head.split(".")[-1]) in pool_n
        else:
            ok = _norm(tok) in pool_n
        if not ok:
            missing.append(tok)
    if len(missing) / float(len(toks)) >= ratio and missing:
        return [{"rule": "step-diff-mismatch", "sev": "FLAG", "tokens": len(toks), "missing": missing[:8],
                 "msg": "%d of %d tokens quoted in the step text are not in the step's diff: %s" % (len(missing), len(toks), ", ".join(missing[:6]))}]
    return []


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B2 tone lint
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

DEFAULT_TONE = "Hey|Yo|Buzz|Hi there|Howdy|Oh no|Whoa|Yikes"


def tone_regex(tokens=None):
    toks = [t.strip() for t in (tokens or os.environ.get("OVN_Z3_TONE_TOKENS") or DEFAULT_TONE).split("|") if t.strip()]
    if not toks:
        toks = DEFAULT_TONE.split("|")
    alt = "|".join(re.escape(t) for t in toks)
    # capitalised as written (a lowercase "yo"/"hey" in code or prose is not the tell); not inside a longer identifier (HeyCorp, Yoga)
    return re.compile(r"(?<![A-Za-z0-9_])(?:%s)(?![A-Za-z0-9_])" % alt)


# B2: only product-copy file types are linted; tests / fixtures / locale catalogues / docs / data files legitimately contain greetings ("Hi there, how can I help?", "Yo soy")
TONE_EXEMPT_DIR_RE = re.compile(r"(^|/)(docs?|documentation|locales?|i18n|l10n|translations?|lang|languages|messages|intl|fixtures?|__fixtures__|testdata|test_data|test-data|__snapshots__|snapshots?|samples?|examples?|mocks?|__mocks__|seeds?|data)/", re.I)
TONE_EXEMPT_FILE_RE = re.compile(r"(^|/)(?:[a-z]{2}(?:[-_][A-Za-z]{2,4})?\.(?:ts|js|json|yml|yaml|po|arb)|(?:messages|strings|translations?|locale|locales)\.\w+)$")


def tone_exempt(path):
    p = path or ""
    if not p.endswith(SRC_EXT):
        return True         # .md/.txt/.rst/.json/.yml/.csv/.po/.svg/... : docs and data, not product copy
    if is_test_path(p) or TONE_EXEMPT_DIR_RE.search(p) or TONE_EXEMPT_FILE_RE.search(p):
        return True
    return os.path.basename(p).upper().startswith(("OVERNIGHT", "CLAUDE", "AGENTS", "README", "CHANGELOG"))


def check_tone(diff_files, text="", tokens=None):
    rx = tone_regex(tokens)
    findings = []
    ctxt = text or ""
    for fd in diff_files:
        if fd.is_deleted or tone_exempt(fd.path):
            continue
        prior = {}
        for _, t in fd.removed:
            for m in rx.finditer(t):
                prior[m.group(0)] = prior.get(m.group(0), 0) + 1
        for ln, t in fd.added:
            for m in rx.finditer(t):
                w = m.group(0)
                if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(w), ctxt):
                    continue        # the item/step text itself asks for it
                if prior.get(w, 0) > 0:
                    prior[w] -= 1   # already present before (re-added / moved line)
                    continue
                findings.append({"rule": "tone-lint", "sev": "FLAG", "file": fd.path, "line": ln, "token": w, "snip": t.strip()[:120],
                                 "msg": "greeting/slang token %r added to %s:%d" % (w, fd.path, ln)})
    return findings


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B3 repair may not add a route
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

ROUTE_RES = [
    re.compile(r"^\s*@\s*[\w.]+\.(get|post|put|patch|delete|head|options|websocket|api_route|route)\s*\("),
    re.compile(r"\b(app|router|api|bp|blueprint|\w+_router)\.(add_api_route|add_url_rule|add_route|include_router)\s*\("),
    re.compile(r"\b(app|router)\.(get|post|put|patch|delete|all)\s*\(\s*[\"'`]/"),
    re.compile(r"^\s*@(Get|Post|Put|Patch|Delete|Request)Mapping\b"),
    re.compile(r"^\s*(get|post|put|delete|patch)\s*\(\s*[\"']/"),       # ktor routing
]


def check_repair_routes(diff_files):
    out = []
    for fd in diff_files:
        if is_test_path(fd.path) or fd.is_deleted or not fd.path.endswith((".py", ".ts", ".js", ".kt", ".java", ".swift", ".go")):
            continue
        for ln, t in fd.added:
            if any(r.search(t) for r in ROUTE_RES):
                out.append({"rule": "repair-new-route", "sev": "FLAG", "file": fd.path, "line": ln, "snip": t.strip()[:120],
                            "msg": "a repair-to-pass-verification step added a route/endpoint at %s:%d" % (fd.path, ln)})
    return out


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B4 test-creation items may not edit non-test source
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

_TEST_ITEM_RE = re.compile(r"\bcat:test\b")
_TEST_VERB_RE = re.compile(r"^\s*(?:\[T\d\]\s*)?(?:create|add|write|extend|expand)\s+(?:a\s+|an\s+|the\s+|new\s+)*(?:(?:unit|integration|regression|pytest|vitest|gut|e2e)\s+)*(?:tests?|test\s+file|test\s+case|spec|specs)\b", re.I)


def is_test_item(item="", desc="", files=""):
    """A test-creation item: tagged cat:test, or the step text is 'Create/Add test ...', or it declares only test files."""
    if _TEST_ITEM_RE.search(item or ""):
        return True
    if _TEST_VERB_RE.search(re.sub(r"^\[T\d\]\s*", "", desc or "")):
        return True
    decl = [f for f in re.split(r"[\s,]+", files or "") if f]
    return bool(decl) and all(is_test_path(f) for f in decl)


def check_test_item_scope(diff_files, item="", desc="", files=""):
    if not is_test_item(item, desc, files):
        return []
    bad = [fd for fd in diff_files if is_source_path(fd.path) and not fd.is_deleted and (fd.added or fd.removed)]
    # a non-source companion (docs, lockfile, json fixture) is not an app-source edit
    return [{"rule": "test-item-src-edit", "sev": "FLAG", "file": fd.path, "added": len(fd.added), "removed": len(fd.removed),
             "msg": "a test-creation item edited non-test source %s (+%d/-%d)" % (fd.path, len(fd.added), len(fd.removed))} for fd in bad]


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B7 assert-weaken (Z5, 2026-11-08): a diff to a TEST file that makes its assertions weaker. Incidents of 2026-11-08: shrike-monitor 08c7146 replaced
# `"detail" not in r.json()` / `"RuntimeError" not in r.text` with two IDENTICAL positive asserts; iptv 872a3906/adf34327 flipped `== 422` to `== 200`; iptv f9cf73dc replaced
# `== original_*` with `is not None`; test-automation-agent 6b686f31 deleted 4 invalid-cron parametrize cases. Flag only (OVN_Z3_ASSERT_WEAKEN, shadow default).
# Sub-kinds (finding["kind"]): negative-removed, status-flip, compare-to-weak, duplicate-assert, case-deleted.
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

_NEG_ASSERT_RE_PRE = re.compile(
    r"\bassert\b[^#\n]*?\bnot\s+in\b|\bassert\s+not\b|\bassertNotIn\b|\bassertNotEqual\b|\bassertFalse\b|\bassertNotIsInstance\b|\bassert_not_called\b|\bassert_not_called_with\b|\brefute\b|"
    r"\bassert_not\w*\b|\bassert_false\b|\bassert_ne\b|\.not\.(?:toContain|toBe|toEqual|toHaveProperty|toMatch|toHaveBeenCalled\w*|toBeInTheDocument|toBeVisible|toThrow\w*|toHaveLength|toStrictEqual)\b|"
    r"\btoBeFalsy\(|\bassertNotRegex\b")
_NEG_ASSERT_RE_Z7 = re.compile(
    r"\bassert\b[^#\n]*?\bnot\s+in\b|\bassert\b[^#\n]*?!=|\bassert\s+not\b|\bassertNotIn\b|\bassertNotEqual\b|\bassertFalse\b|\bassertNotIsInstance\b|\bassert_not_called\b|\bassert_not_called_with\b|\brefute\b|"
    r"\bassert_not\w*\b|\bassert_false\b|\bassert_ne\b|\.not\.(?:toContain|toBe|toEqual|toHaveProperty|toMatch|toHaveBeenCalled\w*|toBeInTheDocument|toBeVisible|toThrow\w*|toHaveLength|toStrictEqual)\b|"
    r"\btoBeFalsy\(|\bassertNotRegex\b")


class _NegAssert:
    """`.search` picks the Z7 pattern (adds `assert ... !=`) only while OVN_Z7_ASSERT_RECALL is on, so `off` restores the pre-Z7 matching exactly."""
    @staticmethod
    def search(t):
        return (_NEG_ASSERT_RE_Z7 if _z7_on() else _NEG_ASSERT_RE_PRE).search(t)


_NEG_ASSERT_RE = _NegAssert()
_ASSERTISH_RE = re.compile(r"\bassert\w*\b|\bexpect\s*\(|\bshould\b|\brefute\b|\bverify\b")
_STATUS_RE = re.compile(r"\b([1-5]\d\d)\b")
_WEAK_RE = re.compile(r"\bis\s+not\s+None\b|\bassertIsNotNone\b|\bassertTrue\(\s*True\s*\)|\bassert\s+True\b|\.toBeDefined\(\)|\.toBeTruthy\(\)|\.not\.toBeNull\(\)|\.not\.toBeUndefined\(\)|\bassert\s+\w+\s*$|\bassert_not_null\b|\bassert_true\(\s*true\s*\)")
_STRONG_RE = re.compile(r"\bassert\b[^#\n]*?(?:==|\bin\b)|\bassertEqual\b|\bassertIn\b|\.toBe\((?!\s*(?:true|false)\s*\))|\.toEqual\(|\.toStrictEqual\(|\.toContain\(|\.toHaveLength\(|\.toMatch\(|\bassert_eq\b|\bassert_equal\b")  # toBe(true/false) = existence check, not a comparison
_TESTDEF_RE = re.compile(r"^\s*(?:async\s+)?def\s+test_|^\s*func\s+test_|^\s*(?:it|test|describe)(?:\.\w+)?\s*\(|^\s*@Test\b|^\s*fun\s+`?test")
_PARAM_RE = re.compile(r"parametrize|\b(?:it|test|describe)\.each\b|\bwith_data\b|@(?:pytest\.)?fixture\(.*params")
_CASE_RE = re.compile(r"^\s*(?:pytest\.param\(|\(.*\)\s*,?\s*(?:#.*)?$|\[.*\]\s*,?\s*(?:#.*)?$|[\"'`][^\"'`]*[\"'`]\s*,?\s*(?:#.*)?$|\{.*\}\s*,?\s*(?:#.*)?$)")
_NO_ASSERT_WORDS_RE = re.compile(r"^\s*(?:#|//|\*|/\*)")


def _norm_line(t):
    return re.sub(r"\s+", " ", (t or "").strip()).rstrip(";,")


def _is_comment(t):
    return bool(_NO_ASSERT_WORDS_RE.match(t or ""))


def _status_shape(t):
    return _STATUS_RE.sub("N", _norm_line(t))


def _status_codes(t):
    return [int(x) for x in _STATUS_RE.findall(t or "")]


_EMPTY_ASSERT_RE = re.compile(r"==\s*(?:\[\]|\{\}|\(\)|\"\"|''|0\b|None\b)|\blen\([^)]*\)\s*==\s*0|toHaveLength\(0\)|toEqual\(\[\]\)|toBe\(0\)|\bis\s+None\b")
_SUBJ_TOKEN_RE = re.compile(r"[A-Za-z_][\w]*(?:\.[A-Za-z_]\w*)*(?:\(\))?")
_SUBJ_STOP = {"assert", "not", "in", "is", "None", "True", "False", "and", "or", "expect", "toBe", "toEqual", "toContain", "self", "len", "str", "set", "list", "dict"}


def _polarity_key(t):
    t = re.sub(r"\bnot\s+in\b", "in", t)
    t = re.sub(r"\bassert\s+not\b", "assert", t)
    if _z7_on():
        t = t.replace("!=", "==")
    t = t.replace(".not.", ".").replace("assertNotIn", "assertIn").replace("assertFalse", "assertTrue").replace("assertNotEqual", "assertEqual")
    return _norm_line(t)


def _subject_tokens(t):
    t = re.sub(r"\"[^\"]*\"|'[^']*'", " ", t)
    return set(x for x in _SUBJ_TOKEN_RE.findall(t) if x not in _SUBJ_STOP and len(x) > 1)


# Z7 (2026-11-09) recall extension: kinds polarity-flip, status-flip-src, literal-swap, assertion-deleted, orphan-assert-deleted. Flag only (shadow evidence): a legitimate test update that
# accompanies a legitimate behaviour change looks the same, so every Z7 finding carries `src_changed` and the kinds that need a source change in the same diff never fire without one.
# OVN_Z7_ASSERT_RECALL=off restores the Z5 behaviour exactly.
_LIT_RE = re.compile(r"\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'|(?<![\w.])-?\d+(?:\.\d+)?(?:e-?\d+)?(?![\w.])")
_CMP_RE = re.compile(r"==|\bassertEqual\b|\.toBe\(|\.toEqual\(|\.toStrictEqual\(|\bassert_eq\b|\bassert_equal\b|\bassertAlmostEqual\b|\.toBeCloseTo\(")
_ASSIGN_RE = re.compile(r"^\s*(?:async\s+)?def\s+\w+\s*\(([^)]*)\)|^\s*(?:for\s+)?([A-Za-z_][\w, ]*?)\s*(?::[^=]+)?=(?!=)|\bas\s+([A-Za-z_]\w*)|\bfor\s+([A-Za-z_][\w, ]*)\s+in\b")


def _z7_on():
    return os.environ.get("OVN_Z7_ASSERT_RECALL", "on").strip().lower() != "off"


def _lit_shape(t):
    return _norm_line(_LIT_RE.sub("L", t))


def _lits(t):
    return [x for x in _LIT_RE.findall(t or "")]


def _lit_delta(new, old):
    """The part of literal `new` that is not shared (common prefix/suffix) with `old`."""
    n, o = new.strip("\"'"), old.strip("\"'")
    i = 0
    while i < min(len(n), len(o)) and n[i] == o[i]:
        i += 1
    j = 0
    while j < min(len(n), len(o)) - i and n[len(n) - 1 - j] == o[len(o) - 1 - j]:
        j += 1
    return n[i:len(n) - j].strip()


def _lit_explained(new, olds, src_added):
    """True when the source diff itself introduces the value `new` (a deliberate change the test follows)."""
    bare = new.strip("\"'")
    if re.fullmatch(r"-?\d+(?:\.\d+)?", bare):
        return bool(re.search(r"(?<![\w.])%s(?![\w.])" % re.escape(bare), src_added))
    for d in ([_lit_delta(new, o) for o in olds] or [bare]):
        if len(d) >= 2 and re.search(r"(?<!\w)%s(?!\w)" % re.escape(d), src_added):
            return True
    return False


def _assert_root(t):
    m = re.search(r"\bassert(?:\w*)\b\s*\(?\s*(?:not\s+)?([A-Za-z_]\w*)", t)
    return m.group(1) if m else ""


def _bound_names(lines):
    names = set()
    for t in lines:
        for m in _ASSIGN_RE.finditer(t):
            for g in m.groups():
                if g:
                    names |= set(re.findall(r"[A-Za-z_]\w*", g))
    return names



def check_assert_weaken(diff_files, old_text_fn=None, new_text_fn=None, repair=False):
    """B7. Deterministic per-hunk heuristics (see above). old_text_fn(path) -> pre-image text, only needed for the deleted-parametrize-case check."""
    out = []
    for fd in diff_files:
        if fd.is_deleted or fd.is_new or not is_test_path(fd.path):
            continue
        if not (fd.removed and fd.added) and not fd.removed:
            continue
        src_touched = any(is_source_path(o.path) and not o.is_deleted and (o.added or o.removed) for o in diff_files)
        file_added_norm = set(_norm_line(t) for _, t in fd.added)
        src_added = "\n".join(t for o in diff_files if is_source_path(o.path) and not o.is_deleted for _, t in o.added)
        file_ctx_neg = [t for t in fd.context if _NEG_ASSERT_RE.search(t)]
        old_text = None
        found = {}   # kind -> (lineno, text)

        def hit(kind, ln, txt):
            found.setdefault(kind, (ln, _norm_line(txt)[:120]))
        new_text = None
        for h in fd.hunks:
            rem = [(ln, t) for ln, t in h["rem"] if not _is_comment(t)]
            add = [(ln, t) for ln, t in h["add"] if not _is_comment(t)]
            if not rem:
                continue
            add_norm = set(_norm_line(t) for _, t in add)
            rem_testdef = any(_TESTDEF_RE.match(t) for _, t in rem)
            add_testdef = any(_TESTDEF_RE.match(t) for _, t in add)
            # a test whose `def`/`it(` line is itself edited or removed is a rewritten / retired test (its intent changed), not an in-place weakening of one that stays
            retired = rem_testdef
            # (1) a negative assertion removed (not merely moved/reworded to another negative one)
            if not retired:
                add_neg = sum(1 for _, t in add if _NEG_ASSERT_RE.search(t))
                add_pk = set(_polarity_key(t) for _, t in add)
                add_subj = set()
                for _, t in add:
                    if (_STRONG_RE.search(t) or _EMPTY_ASSERT_RE.search(t)) and not _WEAK_RE.search(t):
                        add_subj |= _subject_tokens(t)
                add_empty = any(_EMPTY_ASSERT_RE.search(t) and _ASSERTISH_RE.search(t) for _, t in add)
                for ln, t in rem:
                    if _NEG_ASSERT_RE.search(t) and _norm_line(t) not in file_added_norm and _ASSERTISH_RE.search(t):
                        if _polarity_key(t) in add_pk:
                            # expectation flipped (`assert not x` -> `assert x`). Z5 skipped it (the behaviour under test may have changed on purpose); Z7 reports it as evidence when the
                            # SAME literal/operands now assert the opposite (shrike-monitor deacf45: `"secret=xyz" not in result` -> `"secret=xyz" in result`)
                            if _z7_on():
                                hit("polarity-flip", ln, t + "  ->  " + next((a for _, a in add if _polarity_key(a) == _polarity_key(t)), ""))
                            continue
                        if _subject_tokens(t) & add_subj and not any(_norm_line(x) == _norm_line(y) for (_, x), (_, y) in zip(add, add[1:])):
                            continue      # replaced by a stronger comparison on the same subject
                        if add_empty:
                            continue      # replaced by an emptiness check
                        if any(_subject_tokens(c) & _subject_tokens(t) for c in file_ctx_neg):
                            continue      # a sibling negative assertion on the same subject is still there
                        rem_neg = sum(1 for _, x in rem if _NEG_ASSERT_RE.search(x))
                        if rem_neg > add_neg:
                            hit("negative-removed", ln, t)
                            break
            # (2) status expectation flipped from an error code to a success code. Only for a TEST-ONLY change: a commit that also edits app source changed the behaviour on purpose.
            for ln, t in ([] if src_touched else rem):
                if not _ASSERTISH_RE.search(t):
                    continue
                oc = [c for c in _status_codes(t) if 400 <= c <= 499]
                if not oc:
                    continue
                shape = _status_shape(t)
                for _, a in add:
                    ac = [c for c in _status_codes(a) if 200 <= c <= 299]
                    if ac and _status_shape(a) == shape:
                        hit("status-flip", ln, t + "  ->  " + a)
                        break
            if _z7_on():
                # (2b) error status -> success status although a SOURCE file changed too (the expectation was bent to the new implementation)
                if src_touched:
                    for ln, t in rem:
                        if not _ASSERTISH_RE.search(t) or retired:
                            continue
                        oc = [c for c in _status_codes(t) if c in (400, 401, 403, 404, 405, 409, 422)]
                        if not oc:
                            continue
                        shape = _status_shape(t)
                        for _, a in add:
                            if _ASSERTISH_RE.search(a) and _status_shape(a) == shape and [c for c in _status_codes(a) if 200 <= c <= 299]:
                                hit("status-flip-src", ln, t + "  ->  " + a)
                                break
                # (2c) literal swap in an unchanged assertion shape while a SOURCE file changed (60.0 -> 0.5; shrike-notify df2145b)
                if src_touched and not retired:
                    for ln, t in rem:
                        if not (_ASSERTISH_RE.search(t) and _CMP_RE.search(t)) or _is_comment(t):
                            continue
                        lt = _lits(t)
                        if not lt:
                            continue
                        sh = _lit_shape(t)
                        for _, a in add:
                            if _ASSERTISH_RE.search(a) and _lit_shape(a) == sh and _lits(a) != lt and _norm_line(a) != _norm_line(t) and not (set(_status_codes(t)) and [c for c in _status_codes(a) if 200 <= c <= 299] and found.get("status-flip-src")):
                                la = _lits(a)
                                new_l = [x for x in la if x not in lt]
                                # a NEW literal that the source diff itself introduces (a renamed label, a new status code) is an expectation following a deliberate change; the swap is only
                                # evidence when the source diff does not contain the value the test now expects (shrike-notify df2145b: source returns 0.0, test now expects 0.5)
                                if new_l and all(_lit_explained(x, [y for y in lt if y not in la], src_added) for x in new_l):
                                    continue
                                hit("literal-swap", ln, t + "  ->  " + a)
                                break
                # (2d) assertion lines deleted with nothing asserting in their place
                if not retired:
                    if new_text is None and callable(new_text_fn):
                        new_text = new_text_fn(fd.path) or ""
                    new_norm = set(_norm_line(x) for x in new_text.split("\n")) if new_text else None
                    del_ass = [(ln, t) for ln, t in rem if _ASSERTISH_RE.search(t) and not _WEAK_RE.search(t) and not _is_comment(t) and _norm_line(t) not in add_norm and _norm_line(t) not in file_added_norm]
                    add_ass = [1 for _, t in add if _ASSERTISH_RE.search(t)]
                    if del_ass and len(add_ass) < len(del_ass):
                        keep = [x for x in del_ass if new_norm is None or _norm_line(x[1]) not in new_norm]    # still elsewhere in the new file = a de-duplication, not a loss
                        if keep and len(keep) > len(add_ass):
                            hit("assertion-deleted", keep[0][0], keep[0][1])
                # (2e) a test is retired but ONE of the assertions in the removed block belonged to a surviving test (its subject name is bound nowhere in the removed lines)
                if retired and fd.path.endswith(".py"):
                    if new_text is None and callable(new_text_fn):
                        new_text = new_text_fn(fd.path) or ""
                    rem_defs = [re.match(r"\s*(?:async\s+)?def\s+(test_\w+)", t) for _, t in rem]
                    rem_defs = [m.group(1) for m in rem_defs if m]
                    deduped = bool(rem_defs) and bool(new_text) and all(re.search(r"def\s+%s\b" % re.escape(n), new_text) for n in rem_defs)   # the same test is still defined: a de-duplication
                    bound = _bound_names([t for _, t in rem])
                    for ln, t in ([] if deduped else rem):
                        if not _ASSERTISH_RE.search(t) or _is_comment(t) or _norm_line(t) in add_norm:
                            continue
                        r = _assert_root(t)
                        if r and r not in bound and r not in ("self", "True", "False", "None", "len", "isinstance", "any", "all", "pytest", "response", "result", "resp") and not r[0].isupper():
                            if _norm_line(t) not in file_added_norm:
                                hit("orphan-assert-deleted", ln, t)
                                break
            # (3) strong comparison replaced by an existence check
            if not retired:
                strong_rem = sum(1 for _, t in rem if _STRONG_RE.search(t) and not _WEAK_RE.search(t))
                strong_add = sum(1 for _, t in add if _STRONG_RE.search(t) and not _WEAK_RE.search(t))
                weak_add = [(ln, t) for ln, t in add if _WEAK_RE.search(t) and _ASSERTISH_RE.search(t)]
                if strong_rem > strong_add and weak_add and not any(_WEAK_RE.search(t) for _, t in rem):
                    hit("compare-to-weak", weak_add[0][0], weak_add[0][1])
            # (4) identical consecutive positive assertions in the replacement while the hunk removed a different assertion
            ad = [t for _, t in h["add"]]
            for i in range(len(ad) - 1):
                if h["add"][i + 1][0] == h["add"][i][0] + 1 and _norm_line(ad[i]) == _norm_line(ad[i + 1]) and _ASSERTISH_RE.search(ad[i]) and not _is_comment(ad[i]):
                    if any(_ASSERTISH_RE.search(t) and _norm_line(t) != _norm_line(ad[i]) for _, t in rem):
                        hit("duplicate-assert", h["add"][i][0], ad[i])
                        break
            # (5) parametrize / each cases deleted (their values vanish; removed with the test itself is retirement)
            if old_test_ok(old_text_fn) and not retired:
                if old_text is None:
                    old_text = old_text_fn(fd.old_path) or ""
                old_lines = old_text.split("\n")
                gone = [(ln, t) for ln, t in rem if _CASE_RE.match(t) and _norm_line(t) not in add_norm and not _ASSERTISH_RE.search(t) and not _TESTDEF_RE.match(t)]
                if gone:
                    ln0 = gone[0][0]
                    window = old_lines[max(0, ln0 - 25):max(0, ln0 - 1)]
                    if any(_PARAM_RE.search(w) for w in window):
                        hit("case-deleted", ln0, gone[0][1])
        if found.get("assertion-deleted") and any(k in found for k in ("negative-removed", "compare-to-weak", "duplicate-assert", "status-flip", "status-flip-src", "polarity-flip")):
            found.pop("assertion-deleted")     # the more specific kind already names the loss
        for kind, (ln, txt) in sorted(found.items()):
            out.append({"rule": "assert-weaken", "sev": "FLAG", "kind": kind, "file": fd.path, "line": ln, "text": txt,
                        "msg": "test %s weakened (%s) at %s:%s: %s" % ("assertions", kind, fd.path, ln, txt[:80])}
                       if not _z7_on() else
                       {"rule": "assert-weaken", "sev": "FLAG", "kind": kind, "file": fd.path, "line": ln, "text": txt, "src_changed": bool(src_touched),
                        "tier": "strong" if (kind in ("polarity-flip", "status-flip-src") or (repair and kind in ("literal-swap", "assertion-deleted", "orphan-assert-deleted"))) else "weak",
                        "msg": "test %s weakened (%s) at %s:%s: %s" % ("assertions", kind, fd.path, ln, txt[:80])})
    return out


def old_test_ok(fn):
    return callable(fn)


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B5 dropped call
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

_IGNORE_CALLS = set("""print len str int float bool list dict set tuple range enumerate zip sorted reversed min max sum abs round isinstance issubclass getattr setattr hasattr type super
    open repr id hash iter next any all map filter format join strip split lower upper replace startswith endswith get items keys values pop append extend add update remove discard
    push_warning push_error printerr prints assert_true assert_false assert_eq assert_eq assert_ne assert_gt assert_lt expect assert_not_null assert_null info debug warning error
    exception log logger console""".split())


def _py_funcs(text):
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return None
    out = {}

    class V(ast.NodeVisitor):
        def __init__(self):
            self.stack = []

        def visit_ClassDef(self, n):
            self.stack.append(n.name)
            self.generic_visit(n)
            self.stack.pop()

        def _fn(self, n):
            q = ".".join(self.stack + [n.name])
            stmts = set()
            for sub in ast.walk(n):
                if isinstance(sub, ast.Expr) and isinstance(sub.value, ast.Call):
                    f = sub.value.func
                    nm = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
                    if nm:
                        stmts.add(nm)
                elif isinstance(sub, ast.Expr) and isinstance(sub.value, ast.Await) and isinstance(sub.value.value, ast.Call):
                    f = sub.value.value.func
                    nm = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
                    if nm:
                        stmts.add(nm)
            end = getattr(n, "end_lineno", n.lineno)
            seg = "\n".join(text.split("\n")[n.lineno - 1:end])
            out[q] = {"stmt_calls": stmts, "text": seg, "start": n.lineno, "end": end}
            self.stack.append(n.name)
            self.generic_visit(n)
            self.stack.pop()
        visit_FunctionDef = _fn
        visit_AsyncFunctionDef = _fn
    V().visit(tree)
    return out


_GD_FUNC_RE = re.compile(r"^(\s*)(?:static\s+)?func\s+(\w+)\s*\(")
_GD_STMT_CALL_RE = re.compile(r"^\s*(?:await\s+)?(?:[A-Za-z_][\w]*\.)*([A-Za-z_]\w*)\s*\(.*\)\s*(?:#.*)?$")


def _gd_funcs(text):
    lines = text.split("\n")
    out, i = {}, 0
    while i < len(lines):
        m = _GD_FUNC_RE.match(lines[i])
        if not m:
            i += 1
            continue
        ind = len(m.group(1).expandtabs(4))
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > ind and len(lines[j].expandtabs(4)) - len(lines[j].expandtabs(4).lstrip()) > ind):
            j += 1
        body = lines[i:j]
        stmts = set()
        for ln in body[1:]:
            sm = _GD_STMT_CALL_RE.match(ln)
            if sm and not ln.strip().startswith(("if ", "elif ", "while ", "for ", "match ", "return", "func ", "var ", "#")):
                stmts.add(sm.group(1))
        out[m.group(2)] = {"stmt_calls": stmts, "text": "\n".join(body), "start": i + 1, "end": j}
        i = j
    return out


def _funcs(path, text):
    if path.endswith(".py"):
        return _py_funcs(text)
    if path.endswith(".gd"):
        return _gd_funcs(text)
    return None


def check_call_drop(path, old_text, new_text, removed_linenos=None, added_linenos=None):
    """FLAG a function that lost a bare statement call. removed_linenos/added_linenos (sets) restrict to functions the diff touched."""
    fo, fn = _funcs(path, old_text or ""), _funcs(path, new_text or "")
    if not fo or fn is None:
        return []
    out = []
    for q, o in fo.items():
        n = fn.get(q)
        if n is None:
            continue
        if o["text"] == n["text"]:
            continue
        old_lines, new_lines = o["text"].split("\n"), n["text"].split("\n")
        # mostly rewritten functions are refactors, not accidents
        common = len(set(l.strip() for l in old_lines) & set(l.strip() for l in new_lines))
        if len(old_lines) >= 4 and common < 0.4 * len(set(l.strip() for l in old_lines)):
            continue
        for name in sorted(o["stmt_calls"]):
            if name in _IGNORE_CALLS or name.startswith("assert") or name in n["stmt_calls"]:
                continue
            if re.search(r"(?<![\w])%s(?![\w])" % re.escape(name), n["text"]):
                continue        # the name is still mentioned (kept, passed around, or called in an expression)
            # the call must have disappeared: the old body had it as a statement and the new body has no trace of the name
            out.append({"rule": "call-dropped", "sev": "FLAG", "file": path, "function": q, "call": name, "line": n["start"],
                        "msg": "%s lost the statement call %s() it made before (%s)" % (q, name, path)})
    return out


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B0 editor example leak (aider editor-whole few-shot replay)
# ----------------------------------------------------------------------------------------------------------------------------------------------------------

LEAK_RE = re.compile(
    r"change the greeting to be more casual|show_greeting\.py|switch the greeting text from|the user wants to change the greeting|"
    r"make the greeting (?:more )?casual|greeting\b.{0,60}\bcasual|casual\b.{0,60}\bgreeting|"
    r"[\"'`]?Hello[\"'`]?\s*(?:->|\u2192|=>|to|with)\s*[\"'`]?Hey\b|\bHello\b.{0,12}\bHey\b|\"Hello\"\s*(?:to|->)\s*\"Hey\"", re.I)


def check_editor_leak(log_text):
    m = LEAK_RE.search(log_text or "")
    if not m:
        return []
    tool = bool(re.search(r"<tool_call>|<function=", log_text or ""))
    return [{"rule": "editor-example-leak", "sev": "FLAG", "tool_call_architect": tool, "snip": log_text[max(0, m.start() - 40):m.end() + 60].replace("\n", " ")[:160],
             "msg": "the aider editor replayed its built-in 'Change the greeting to be more casual' example (architect gave no actionable instruction)"}]


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# B6 per-item landing cap
# ----------------------------------------------------------------------------------------------------------------------------------------------------------


def _parse_ts(s):
    try:
        import calendar
        return calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ"))
    except (ValueError, TypeError):
        return 0


def landing_counts(rows, now, window_h=24):
    """rows: iterable of outcome dicts -> {key: count of landed* rows in the trailing window}. key = item_line_hash (the WHOLE item line: sibling items of one [feat:] tag
    share item_hash and legitimately land many times, 84 of 341 hashes in 7 days at N=4) and item_hash only for legacy rows without a line hash."""
    lo = now - window_h * 3600
    c = {}
    for r in rows:
        if not str(r.get("class", "")).startswith("landed"):
            continue
        h = r.get("item_line_hash") or r.get("item_hash") or ""
        if not h:
            continue
        ts = _parse_ts(r.get("ts", ""))
        if lo < ts <= now + 60:
            c[h] = c.get(h, 0) + 1
    return c


def read_outcomes(path, tail_bytes=8 * 1024 * 1024):
    rows = []
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            sz = f.tell()
            f.seek(max(0, sz - tail_bytes))
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return rows
    for ln in data.split("\n"):
        ln = ln.strip()
        if ln.startswith("{"):
            try:
                rows.append(json.loads(ln))
            except ValueError:
                pass
    return rows


def park_item(progress_path, text, count, window_h=24):
    """Tag the open progress line(s) equal to `text` with the usual reversible AUTO-SKIP marker. Returns the number tagged."""
    marker = "[AUTO-SKIP landed %dx in %dh - one item keeps landing without closing; review] " % (count, window_h)
    cur = (text or "").strip()
    if cur.startswith("- [ ] "):
        cur = cur[len("- [ ] "):].strip()
    try:
        lines = open(progress_path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return 0
    n = 0
    for i, ln in enumerate(lines):
        if not ln.startswith("- [ ] ") or "AUTO-SKIP" in ln or "[CLAUDE]" in ln:
            continue
        if ln[len("- [ ] "):].strip() == cur:
            lines[i] = "- [ ] " + marker + ln[len("- [ ] "):]
            n += 1
    if n:
        open(progress_path, "w", encoding="utf-8").write("\n".join(lines))
    return n


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# git helpers + commit-level corpus
# ----------------------------------------------------------------------------------------------------------------------------------------------------------


def git(repo, *args, **kw):
    p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, errors="replace", timeout=kw.get("timeout", 60))
    return p.stdout if p.returncode == 0 else ""


def post_image(repo, rev, paths, cap=400000):
    parts = []
    for p in paths:
        t = git(repo, "show", "%s:%s" % (rev, p))
        if t:
            parts.append(t[:cap])
    return "\n".join(parts)


def _envint(name, default):
    try:
        return int(os.environ.get(name, "") or default)
    except ValueError:
        return default


def cap_findings(res, n=None):
    """D3: bound the journal rows one call can produce. First n findings per rule, then ONE 'truncated N more' row (sev INFO) so the volume is still visible."""
    n = _envint("OVN_Z3_MAX_FINDINGS", 50) if n is None else n
    for k, v in list(res.items()):
        if len(v) > n:
            extra = len(v) - n
            res[k] = v[:n] + [{"rule": k, "sev": "INFO", "truncated": extra, "msg": "truncated %d more %s finding(s)" % (extra, k)}]
    return res


def analyse(diff_text, desc="", item="", kind="step", files="", post_text=None, repo=None, base=None, head=None, truncated=None):
    """Run B1-B5 + B7 on one diff. Returns {rule: [findings]}."""
    diff_text = (diff_text or "")[:_envint("OVN_Z3_MAX_DIFF_BYTES", 2 * 1024 * 1024)]   # D3: bounded work on huge diffs (the tail is simply not scanned)
    fds = parse_diff(diff_text)
    res = {}
    ratio = float(os.environ.get("OVN_Z3_STEPDIFF_RATIO", "0.5") or 0.5)
    res["step-diff-mismatch"] = check_step_diff(desc, fds, post_text, files, ratio, truncated) if (desc or "").strip() else []
    res["tone-lint"] = check_tone(fds, (desc or "") + "\n" + (item or ""))
    res["repair-new-route"] = check_repair_routes(fds) if kind == "repair" else []
    res["test-item-src-edit"] = check_test_item_scope(fds, item, desc, files)
    res["assert-weaken"] = check_assert_weaken(fds, (lambda pth: git(repo, "show", "%s:%s" % (base, pth))) if (repo and base) else None,
                                               (lambda pth: (git(repo, "show", "%s:%s" % (head, pth)) if head != "WORKTREE" else _read(os.path.join(repo, pth)))) if (repo and head) else None,
                                               repair=(kind == "repair"))
    drops = []
    if repo and base and head:
        for fd in fds[:_envint("OVN_Z3_MAX_FILES", 200)]:
            if fd.is_new or fd.is_deleted or not fd.path.endswith((".py", ".gd")) or is_test_path(fd.path):
                continue
            old = git(repo, "show", "%s:%s" % (base, fd.old_path))
            new = git(repo, "show", "%s:%s" % (head, fd.path)) if head != "WORKTREE" else _read(os.path.join(repo, fd.path))
            drops += check_call_drop(fd.path, old, new, set(l for l, _ in fd.removed))
    res["call-dropped"] = drops
    return cap_findings(res)


def _read(p, limit=None):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read(limit) if limit else f.read()
    except OSError:
        return ""


# ----------------------------------------------------------------------------------------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------------------------------------------------------------------------------------


def _cmd_step(a):
    if a.diff:
        cap = _envint("OVN_Z3_MAX_DIFF_BYTES", 2 * 1024 * 1024)
        diff = sys.stdin.read(cap) if a.diff == "-" else _read(a.diff, cap)
    else:
        gargs = ["diff", "-U1", "--no-color", a.base] + ([a.head] if a.head and a.head != "WORKTREE" else [])
        diff = git(a.repo, *gargs) if a.repo else ""
    post = None
    if a.repo:
        paths = [fd.path for fd in parse_diff(diff) if not fd.is_deleted][:_envint("OVN_Z3_MAX_FILES", 200)]
        if a.head and a.head != "WORKTREE":
            post = post_image(a.repo, a.head, paths)
        else:
            post = "\n".join(_read(os.path.join(a.repo, p), 400000) for p in paths)
    res = analyse(diff, a.desc or "", a.item or "", a.kind, a.files or "", post, a.repo if a.base else None, a.base, a.head or "WORKTREE")
    out = {"findings": [dict(f, rule=k) for k, v in res.items() for f in v], "counts": dict((k, len(v)) for k, v in res.items() if v)}
    print(json.dumps(out))
    return 0


def _cmd_leak(a):
    print(json.dumps({"findings": check_editor_leak(_read(a.log))}))
    return 0


def _cmd_cap_check(a):
    now = int(a.now) if a.now else int(time.time())
    c = landing_counts(read_outcomes(a.outcomes), now, a.window_h).get(a.hash, 0) + a.pending
    print(json.dumps({"hash": a.hash, "count": c, "n": a.n, "over": c >= a.n}))
    return 0


def _cmd_cap_park(a):
    print(park_item(a.progress, a.text, a.count))
    return 0


def _cmd_corpus(a):
    revs = a.rev or ["origin/overnight/feature", "origin/develop", "origin/claude/feature"]
    seen, shas = set(), []
    for r in revs:
        for ln in git(a.repo, "log", "--no-merges", "--since=" + a.since, "--author=shrike-fleet", "--format=%H", r).split("\n"):
            if ln and ln not in seen:
                seen.add(ln)
                shas.append(ln)
    for sha in shas:
        subj = git(a.repo, "show", "-s", "--format=%s", sha).strip()
        m = re.match(r"^\w+\([^)]*\): staged step [\d.]+ . (.*)$", subj)
        desc = m.group(1) if m else ""
        kind = "repair" if "repair staged item" in subj else "step"
        diff = git(a.repo, "show", "-U1", "--no-color", "--format=", sha, timeout=120)
        fds = parse_diff(diff)
        post = post_image(a.repo, sha, [fd.path for fd in fds if not fd.is_deleted])
        res = analyse(diff, desc, "", kind, "", post, a.repo, sha + "~1", sha, truncated=len(subj) >= 70)
        print(json.dumps({"repo": os.path.basename(a.repo.rstrip("/")), "sha": sha[:8], "subject": subj[:100], "kind": kind, "staged": bool(m),
                          "findings": [dict(f, rule=k) for k, v in res.items() for f in v]}))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("step-check")
    s.add_argument("--desc", default="")
    s.add_argument("--item", default="")
    s.add_argument("--kind", default="step", choices=["step", "repair"])
    s.add_argument("--files", default="")
    s.add_argument("--diff", default="")
    s.add_argument("--repo", default="")
    s.add_argument("--base", default="")
    s.add_argument("--head", default="")
    s.set_defaults(fn=_cmd_step)
    s = sp.add_parser("leak-check")
    s.add_argument("--log", required=True)
    s.set_defaults(fn=_cmd_leak)
    s = sp.add_parser("cap-check")
    s.add_argument("--outcomes", required=True)
    s.add_argument("--hash", required=True)
    s.add_argument("--now", default="")
    s.add_argument("--window-h", type=int, default=int(os.environ.get("OVN_Z3_LANDING_CAP_H", "24") or 24))
    s.add_argument("--n", type=int, default=int(os.environ.get("OVN_Z3_LANDING_CAP_N", "3") or 3))
    s.add_argument("--pending", type=int, default=0, help="landings of this cycle not yet in outcomes.jsonl (item_guard runs before record_outcome)")
    s.set_defaults(fn=_cmd_cap_check)
    s = sp.add_parser("cap-park")
    s.add_argument("--progress", required=True)
    s.add_argument("--text", required=True)
    s.add_argument("--count", type=int, required=True)
    s.set_defaults(fn=_cmd_cap_park)
    s = sp.add_parser("corpus")
    s.add_argument("--repo", required=True)
    s.add_argument("--since", default="7.days")
    s.add_argument("--rev", action="append")
    s.set_defaults(fn=_cmd_corpus)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except Exception as ex:  # a gate must never break the pipeline: report and exit 0
        print(json.dumps({"error": "%s: %s" % (type(ex).__name__, str(ex)[:200]), "findings": []}))
        return 0


if __name__ == "__main__":
    sys.exit(main())
