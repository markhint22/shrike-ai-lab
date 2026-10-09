#!/usr/bin/env python3
"""bug_brief.py - the BUG-BRIEF stage: research, plan and DECOMPOSE a manual-test bug so the local 27B has the best chance to land the fix.

Why (2026-10-02, decision from Mark: quality over new dev; bugs he logs by hand go first): of 7 real Chickadee Android bugs the fleet landed 1 in a
day (docs/qwen-capability/*). The 27B fails on whole-file context, multi-file steps, existence-only VERIFYs and missing test-first loops. A manual
bug used to become ONE item ("first write a failing test, then fix it, if the cause is not in this file say so"). This stage turns it into a short
list of single-file steps, each naming the exact function and the exact change, each with a REAL test run as its VERIFY, plus the evidence for the
root cause. Everything the model says is checked MECHANICALLY by the harness; the model is advisory.

  brief         research + plan + validate + emit for one bug (on demand); prints the items, optionally applies them
  import-brief  validate + emit a brief authored by Claude / a human (same schema, same checks)   -> see qa/bug_brief.README.md
  (the ingest calls make_brief() / apply for every new manual bug; see manual_notes_ingest.py `brief` and the sweep)

Pipeline: (1) RESEARCH, deterministic (git grep / function ranges): the function the note points at (quoted, numbered lines), its callers, the
existing tests and how they are written, the state/data-model definitions. Compact: a 227 KB god file is never loaded whole, only function ranges.
(2) PLAN: <= 4 model calls through the same local litellm as the locator (Budget + circuit breaker): a strict-JSON brief
{root_cause{hypothesis, evidence[{file,line,quote}]}, approach, steps[{kind,file,function,change,verify}]}; step 1 is a test-first step (one NEW
test file that fails on the current code), then minimal fix steps, then a regression guard. (3) VALIDATE: files exist (or are new test files in the
right dir), every evidence quote exists verbatim, one file per step, the function exists, VERIFY passes the card_lint shell rules and is a real test
run, no step edits a hard-banned or > 120 KB file (the ovn_park_unworkable rules), <= 6 steps; the test-first step is RUN in a throwaway worktree
and must fail for the right reason (a test that already passes is vacuous -> the plan is rejected). (4) EMIT: ordered queue items sharing ONE
[feat:<tag>], each carrying the 'Manual-test bug (reported by Mark' phrase; the first carries the root cause + evidence.

A red test cannot land on its own (the NO-NEW-RED guard reverts it; the stage runner's decompose prompt says "NEVER a failing-test-first step"), so the
test-first step is EMITTED FUSED with the first fix step into ONE item (new test file + the one fix file, multifile:yes). The brief JSON keeps them
separate steps.

Fallback (never block, never fail open silently): model dead / slow / invalid output / validation failure => no change: the single item the ingest
already enqueued stays exactly as it is, the reason is logged and stored. Kill switch OVN_BUG_BRIEF=off.

Env: OVN_BUG_BRIEF (off), OVN_BUG_BRIEF_BUDGET_S (300 wall for the whole stage), OVN_BUG_BRIEF_CALL_TIMEOUT (150 per model call),
OVN_BUG_BRIEF_EXEC (auto|on|off: run the red-proof; auto = every handled language), OVN_BUG_BRIEF_EXEC_TIMEOUT (600 s),
OVN_MANUAL_MODEL (the model alias, 'off' disables), LITELLM_BASE, LITELLM_MASTER_KEY. No network except the local litellm.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import manual_locator as ml  # noqa: E402   (model name, Budget, parse_json_obj, product-path filter, platform layout)
import card_lint as cl  # noqa: E402       (the verify-command shell rules; the same linter the acceptance card uses)

SCHEMA_VERSION = 1
MIN_STEPS, MAX_STEPS = 3, 6
MAX_CALLS = 4                      # model calls for the whole stage (same contract as the locator)
BIG_FILE_BYTES = 120000            # ovn_park_unworkable's default max_bytes: a step never edits a file bigger than this
KINDS = ("test_first", "fix", "guard")
LANGS = ("kt", "gd", "py", "ts")   # languages the stage handles (Swift is routed away from the fleet; xml-only bugs have no test run)
EVIDENCE_CAP_CHARS = 15000         # the 27B context is 65k tokens; the whole prompt stays far below it
ITEM_TIER = "T3"                   # same as manual_notes_ingest.build_item (see its 2026-10-01 comment)
ANNOT = "brief"                    # the (brief:i/K) annotation that marks an emitted item (idempotency key)


def log(msg):
    print("%s bug_brief: %s" % (time.strftime("%F %T"), msg), file=sys.stderr, flush=True)


def enabled():
    return os.environ.get("OVN_BUG_BRIEF", "on").strip().lower() not in ("off", "0", "no", "false", "none")


def _envf(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


# ----------------------------------------------------------------------------------------------------------------------
# git access (read only, never the working tree)
# ----------------------------------------------------------------------------------------------------------------------
class Repo:
    """Read-only view of `ref` in the git repo at `path` (never the working tree, never writes)."""

    def __init__(self, path, ref):
        self.path, self.ref = path, ref
        self._files = None
        self._text = {}
        self._banned = None

    def _git(self, args, timeout=40):
        return ml._git(self.path, args, timeout=timeout)

    def files(self):
        if self._files is None:
            rc, out = self._git(["ls-tree", "-r", "--name-only", self.ref], timeout=90)
            self._files = out.splitlines() if rc == 0 else []
        return self._files

    def fileset(self):
        return set(self.files())

    def exists(self, p):
        return p in self.fileset()

    def text(self, p):
        if p not in self._text:
            rc, out = self._git(["show", "%s:%s" % (self.ref, p)], timeout=40)
            self._text[p] = out if rc == 0 else None
        return self._text[p]

    def size(self, p):
        rc, out = self._git(["cat-file", "-s", "%s:%s" % (self.ref, p)], timeout=20)
        try:
            return int(out.strip()) if rc == 0 else None
        except ValueError:
            return None

    def banned(self):
        """Lines of .queue-hard-banned-files at ref (same parsing as ovn_park_unworkable.banned_list)."""
        if self._banned is None:
            out = []
            t = self.text(".queue-hard-banned-files") or ""
            for ln in t.splitlines():
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    out.append(ln)
            self._banned = out
        return self._banned

    def grep(self, word, prefixes=None, whole=True, max_per_file=3, limit=80):
        """-> [(path, line_no, text)] fixed-string matches (whole word by default), at most `limit`."""
        args = ["grep", "-n", "-I", "-F"] + (["-w"] if whole else []) + ["-m", str(max_per_file), "-e", word, self.ref, "--"] + list(prefixes or ["."])
        rc, out = self._git(args, timeout=40)
        hits = []
        if rc not in (0, 1):
            return hits
        pre = self.ref + ":"
        for ln in out.splitlines():
            if not ln.startswith(pre):
                continue
            m = re.match(r"(.+?):(\d+):(.*)$", ln[len(pre):])
            if m:
                hits.append((m.group(1), int(m.group(2)), m.group(3)))
                if len(hits) >= limit:
                    break
        return hits


def unworkable_why(rpo, path, max_bytes=BIG_FILE_BYTES):
    """The ovn_park_unworkable rules (hard-banned list entry by equality or prefix; bigger than max_bytes), applied to a path in the git tree.
    -> reason or None. A path that does not exist yet is judged by the banned list only (a new file under a banned prefix is still banned)."""
    for b in rpo.banned():
        if path == b or path.startswith(b):
            return "hard-banned file %s" % path
    if rpo.exists(path) and not path.endswith(".md"):
        sz = rpo.size(path)
        if sz is not None and sz > max_bytes:
            return "%s is %dKB (~%dk tokens) - exceeds the model context" % (path, sz // 1024, sz // 3500)
    return None


# ----------------------------------------------------------------------------------------------------------------------
# languages, function ranges
# ----------------------------------------------------------------------------------------------------------------------
def lang_of(path):
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    return {"kt": "kt", "kts": "kt", "java": "kt", "gd": "gd", "py": "py", "ts": "ts", "tsx": "ts", "js": "ts", "jsx": "ts", "mjs": "ts",
            "vue": "ts"}.get(ext, "")


_KT_MOD = r"(?:(?:private|public|internal|protected|override|suspend|inline|open|abstract|operator|tailrec|external|final|actual|expect)\s+)*"
FUNC_RE = {
    "kt": re.compile(r"^\s*" + _KT_MOD + r"fun\s+(?:<[^>]+>\s*)?(?:[\w.<>?,\s]+\.)?(\w+)\s*\("),
    "gd": re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\("),
    "py": re.compile(r"^\s*(?:async\s+)?def\s+(\w+)\s*\("),
    "ts": re.compile(r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*(\w+)|^\s*(?:export\s+)?(?:const|let)\s+(\w+)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*(?::\s*[\w<>\[\]|, ]+)?=>|"
                     r"^\s*(?:public\s+|private\s+|protected\s+|static\s+|async\s+)*(\w+)\s*\([^)]*\)\s*(?::\s*[\w<>\[\]|, ]+)?\s*\{"),
}
_TS_NOT_FUNC = {"if", "for", "while", "switch", "catch", "return", "function", "constructor_"}
TESTFN_RE = {
    "kt": re.compile(r"^\s*@Test\b|^\s*fun\s+`?test|^\s*fun\s+`[^`]+`\s*\("),
    "gd": re.compile(r"^\s*func\s+test_\w+\s*\("),
    "py": re.compile(r"^\s*(?:async\s+)?def\s+test_\w+\s*\("),
    "ts": re.compile(r"^\s*(?:it|test)\s*\(\s*['\"`]"),
}


def _brace_end(lines, i, funcre, limit=420):
    depth, seen = 0, False
    for j in range(i, min(len(lines), i + limit)):
        s = re.sub(r'"(?:\\.|[^"\\])*"', '""', lines[j])
        s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s).split("//")[0]
        for ch in s:
            if ch == "{":
                depth += 1
                seen = True
            elif ch == "}":
                depth -= 1
        if seen and depth <= 0:
            return j
        if not seen and j > i:
            if not lines[j].strip():
                return j - 1            # expression-bodied function ends at the blank line
            if funcre.match(lines[j]) and (len(lines[j]) - len(lines[j].lstrip())) <= (len(lines[i]) - len(lines[i].lstrip())):
                return j - 1
    return min(len(lines) - 1, i + limit - 1)


def _indent_end(lines, i, limit=600):
    ind = len(lines[i]) - len(lines[i].lstrip())
    last = i
    for j in range(i + 1, min(len(lines), i + limit)):
        s = lines[j]
        if not s.strip():
            continue
        if (len(s) - len(s.lstrip())) <= ind and not s.lstrip().startswith((")", "]", "}")):
            break
        last = j
    return last


def function_ranges(text, lang):
    """-> [{name, start, end}] (1-indexed, inclusive) for the functions of a source file. Regex based (no parser): good enough to cut ranges."""
    funcre = FUNC_RE.get(lang)
    if not funcre or not text:
        return []
    lines = text.split("\n")
    out = []
    for i, ln in enumerate(lines):
        m = funcre.match(ln)
        if not m:
            continue
        name = next((g for g in m.groups() if g), None)
        if not name or (lang == "ts" and name in _TS_NOT_FUNC):
            continue
        end = _indent_end(lines, i) if lang in ("py", "gd") else _brace_end(lines, i, funcre)
        out.append({"name": name, "start": i + 1, "end": end + 1})
    return out


def defined_names(text, lang):
    """Names a step may legitimately point at in a file: functions plus class / object / val / var / property declarations."""
    names = {f["name"] for f in function_ranges(text, lang)}
    for m in re.finditer(r"\b(?:class|object|interface|enum|val|var|const|let|signal|struct)\s+(\w+)", text or ""):
        names.add(m.group(1))
    return names


# ----------------------------------------------------------------------------------------------------------------------
# text safety (anything the model wrote that reaches a queue line)
# ----------------------------------------------------------------------------------------------------------------------
_TAGS = re.compile(r"(?i)\b(verify|cat|multifile|src|feat|recovery|polish|tier|brief)\s*:")


def clean_text(s, cap):
    """One line, no markdown, nothing a queue parser could mistake for syntax (same defusing as manual_notes_ingest.sanitize_note, longer cap, plus
    the words the item selectors treat as 'parked': blocked / human/ / hard file ban / retired-)."""
    s = unicodedata.normalize("NFC", str(s))
    out = []
    for ch in s:
        cat = unicodedata.category(ch)
        if ch in "\n\r\t\v\f\x85  ":
            out.append(" ")
        elif cat in ("Cc", "Cf", "Cs", "Co", "Cn"):
            continue
        else:
            out.append(ch)
    s = re.sub(r"\s+", " ", "".join(out)).strip()
    s = s.replace("`", "'")
    s = re.sub(r"<!--|-->", " ", s)
    # the ingest's sanitizer drops < > * { } outright; a model-written CHANGE is code talk where that destroys the meaning ("size < 5" -> "size 5",
    # "price * rate" -> "price rate"), so they become words / parentheses instead (still nothing a queue parser or sed could trip on)
    s = s.replace("=>", " yields ").replace("->", " to ").replace("<=", " at most ").replace(">=", " at least ").replace("<", " less than ").replace(">", " greater than ")
    s = re.sub(r"\s\*\s", " times ", s).replace("*", "(star)").replace("{", "(").replace("}", ")")
    s = re.sub(r"[#~^\\]", " ", s)
    s = s.replace("$(", "( ").replace("${", "( ")
    s = s.replace("[", "(").replace("]", ")").replace("|", "/")
    s = s.replace(" — ", " - ").replace("—", "-").replace("–", "-")
    s = _TAGS.sub(lambda m: m.group(1).lower() + " -", s)
    s = re.sub(r"(?i)auto-skip", "auto skip", s)
    s = re.sub(r"(?i)human-only", "human only", s)
    s = re.sub(r"(?i)human/", "human /", s)
    s = re.sub(r"(?i)blocked", "block-ed", s)
    s = re.sub(r"(?i)hard file ban", "hard-file ban", s)
    s = re.sub(r"(?i)\(retired-", "(retired -", s)
    s = re.sub(r"\s+", " ", s).strip()
    if len(s) > cap:
        s = s[:cap - 3].rstrip() + "..."
    return s.strip()


def _norm_path(p):
    """Strip leading './' (NOT dots of dot-files); '' if it is not a clean relative path."""
    p = re.sub(r"^(\./)+", "", str(p).strip())
    return p


def clip_sentence(s, cap):
    """clean_text, but a too-long text is cut at the last sentence end (or word) instead of mid-word."""
    c = clean_text(s, 100000)
    if len(c) <= cap:
        return c
    cut = c[:cap]
    k = max(cut.rfind(". "), cut.rfind("; "))
    if k >= cap * 0.5:
        return cut[:k + 1]
    return cut[:cut.rfind(" ")].rstrip(" ,;:") + " ..."


def _safe_token(s):
    return re.sub(r"[^A-Za-z0-9_.-]", "", s or "")


# ----------------------------------------------------------------------------------------------------------------------
# (1) RESEARCH (deterministic)
# ----------------------------------------------------------------------------------------------------------------------
_STOP = set("""a an and are as at be been but by can could did do does for from get got had has have how if in into is it its just not of on one only or
our out over so some that the their them then there these they this to up was were what when where which while who why will with would you your also
after again any because before both each even first last later like made make many more most never new next now off once other same still such than too
very want tap taps tapped click clicks clicked clicking press pressed screen page button buttons app showed shows show only listed list option options
displayed instead right away few minutes though probably clear difference worked didnt doesnt wasnt""".split())


def _variants(word):
    w = word.lower()
    v = {w}
    if w.endswith("ies") and len(w) > 5:
        v.add(w[:-3] + "y")
    elif w.endswith("es") and len(w) > 5:
        v.add(w[:-2])
    if w.endswith("s") and len(w) > 4:
        v.add(w[:-1])
    if w.endswith("ing") and len(w) > 6:
        v.add(w[:-3])
    if w.endswith("ed") and len(w) > 5:
        v.add(w[:-2])
    return sorted(x for x in v if len(x) >= 4)


def terms_from(note, flow):
    """-> [{label, variants, weight}] terms of the tester's note + flow: identifiers / quoted text (3), adjacent-word phrases (2), plain words (1)."""
    text = "%s %s" % (note or "", flow or "")
    terms, seen = [], set()

    def add(label, variants, w):
        k = label.lower()
        if k in seen or not variants:
            return
        seen.add(k)
        terms.append({"label": label, "variants": variants, "weight": w})
    for m in re.finditer(r"(?:^|[\s(])(['\"“‘])(.{3,60}?)(['\"”’])(?=$|[\s.,;:!?)])", text):
        p = m.group(2).strip()
        add(p, [p.lower()], 3.0)
    for m in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*", text):
        tok = m.group(0)
        if len(tok) >= 5 and (re.search(r"[a-z][A-Z]", tok) or "_" in tok.strip("_")):
            add(tok, [tok.lower()], 3.0)
    words = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z0-9']*", text)]
    seq = [None if (w in _STOP or len(w) < 3) else w.strip("'") for w in words]
    for w in seq:
        if w and len(w) >= 4:
            add(w, _variants(w), 1.0)
    run = []
    for w in seq + [None]:
        if w:
            run.append(w)
            continue
        for size in (3, 2):
            for i in range(0, len(run) - size + 1):
                g = run[i:i + size]
                add(" ".join(g), sorted({"".join(g), "_".join(g)}), 2.0)
        run = []
    return terms


def _score_range(name, body_l, terms):
    s, hit = 0.0, []
    nl = name.lower()
    for t in terms:
        if any(v in body_l for v in t["variants"]):
            s += t["weight"]
            hit.append(t["label"])
        if any(v in nl for v in t["variants"]):
            s += 3.0
    return s, hit


def _numbered(lines, a, b, cap_lines=60):
    """Numbered source lines [a..b] (1-indexed, inclusive). A long range keeps its head and is cut with a marker."""
    out = []
    n = b - a + 1
    if n > cap_lines:
        b2 = a + cap_lines - 1
        out = ["%d: %s" % (i, lines[i - 1].rstrip()[:200]) for i in range(a, b2 + 1)]
        out.append("   ... (%d more lines of this function not shown)" % (b - b2))
        return "\n".join(out)
    return "\n".join("%d: %s" % (i, lines[i - 1].rstrip()[:200]) for i in range(a, b + 1))


def _hit_windows(lines, terms, a, b, cap_lines=60, ctx=3):
    """For a long range: signature + windows around the lines that match the note's terms (so the evidence is the RELEVANT part)."""
    marks = set(range(a, min(b, a + 3) + 1))
    for i in range(a, b + 1):
        ll = lines[i - 1].lower()
        if any(v in ll for t in terms for v in t["variants"]):
            marks |= set(range(max(a, i - ctx), min(b, i + ctx) + 1))
        if len(marks) >= cap_lines:
            break
    out, prev = [], None
    for i in sorted(marks)[:cap_lines]:
        if prev is not None and i != prev + 1:
            out.append("   ...")
        out.append("%d: %s" % (i, lines[i - 1].rstrip()[:200]))
        prev = i
    return "\n".join(out)


def _decl_lines(text, lang, n=22):
    pat = {"kt": r"^\s{0,4}(?:(?:private|internal|data|sealed|enum|abstract|open)\s+)*(?:class|object|interface)\b",
           "gd": r"^(?:class_name|extends|signal|enum|const|var|@export|@onready|static var)\b",
           "py": r"^(?:class|[A-Z_]{3,}\s*=|from\s+\S+\s+import|import\s)",
           "ts": r"^\s{0,2}(?:export\s+)?(?:interface|type|enum|class|const)\b"}.get(lang)
    if not pat:
        return ""
    out = []
    for i, ln in enumerate(text.split("\n"), 1):
        if re.match(pat, ln):
            out.append("%d: %s" % (i, ln.rstrip()[:160]))
            if len(out) >= n:
                break
    return "\n".join(out)


def _kt_state_block(text, cap=34):
    """The `data class XUiState(...)` block (the state the ViewModel exposes), numbered."""
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        if re.match(r"^\s*data class \w*(?:UiState|State)\b", ln):
            depth, j = 0, i
            while j < min(len(lines), i + cap):
                depth += lines[j].count("(") - lines[j].count(")")
                if depth <= 0 and j > i or (depth <= 0 and "(" in lines[j]):
                    break
                j += 1
            return _numbered(lines, i + 1, min(j + 1, len(lines)), cap_lines=cap)
    return ""


def _is_test_path(p):
    return bool(re.search(r"(^|/)(tests?|__tests__|androidTest|spec)/|[._]test\.|[._]spec\.|Tests?\.(kt|java|swift)$|(^|/)test_[^/]*$", p))


def find_tests(rpo, path, lang):
    """Existing tests that belong to `path`: -> [paths], best first."""
    stem = os.path.splitext(os.path.basename(path))[0]
    sl = stem.lower()
    cands = []
    for f in rpo.files():
        if lang_of(f) != lang or not _is_test_path(f):
            continue
        b = os.path.basename(f).lower()
        bs = os.path.splitext(b)[0]
        if (bs.startswith(sl) and "test" in bs) or bs.startswith("test_" + sl) or bs in (sl + ".test", sl + ".spec") or ("test" in bs and sl in bs):
            cands.append(f)
    cands.sort(key=lambda f: (-_common_prefix(f, path), len(f), f))
    return cands[:6]


def _common_prefix(a, b):
    n = 0
    for x, y in zip(a.split("/"), b.split("/")):
        if x != y:
            break
        n += 1
    return n


def _example_test(rpo, tests, lang):
    """-> (head_text, one_test_function_text, path) of the best existing test (how tests are written in this module)."""
    for p in tests:
        t = rpo.text(p)
        if not t:
            continue
        lines = t.split("\n")
        head = "\n".join("%d: %s" % (i + 1, lines[i][:180]) for i in range(min(48, len(lines))))
        fn = ""
        rx = TESTFN_RE.get(lang)
        for i, ln in enumerate(lines):
            if rx and rx.match(ln):
                j = i
                if lang == "kt" and ln.strip().startswith("@Test"):
                    j = i + 1
                rngs = [r for r in function_ranges(t, lang) if r["start"] >= j + 1]
                if rngs:
                    r = rngs[0]
                    fn = _numbered(lines, i + 1, min(r["end"], i + 28), cap_lines=30)
                else:
                    fn = _numbered(lines, i + 1, min(len(lines), i + 14), cap_lines=14)
                break
        return head, fn, p
    return "", "", ""


def _slug(note, flow):
    words = [w for w in re.findall(r"[A-Za-z][A-Za-z0-9]+", "%s %s" % (flow or "", note or "")) if w.lower() not in _STOP and len(w) >= 4]
    seen, out = set(), []
    for w in words:
        k = w.lower()
        if k not in seen:
            seen.add(k)
            out.append(w[:1].upper() + w[1:].lower() if not re.search(r"[a-z][A-Z]", w) else w[:1].upper() + w[1:])
        if len(out) == 2:
            break
    return "".join(out) or "Bug"


def _nearest_with(rpo, path, name):
    d = os.path.dirname(path)
    fs = rpo.fileset()
    while True:
        cand = (d + "/" + name) if d else name
        if cand in fs:
            return d
        if not d:
            return None
        d = os.path.dirname(d)


def gradle_test_task(build_text):
    """The gradle task that accepts `--tests`: AGP's umbrella `test` lifecycle task does NOT ('Unknown command-line option --tests', measured 2026-10-02 on
    iptv-android), so with product flavors it must be the concrete variant's unit-test task, e.g. testGoogleTvDebugUnitTest (first flavor, debug)."""
    t = build_text or ""
    m = re.search(r"productFlavors\s*\{(.*?)\n\s{0,4}\}", t, re.S)
    if not m:
        return "testDebugUnitTest"
    names = re.findall(r'create\(\s*"(\w+)"\s*\)|^\s{8}(\w+)\s*\{', m.group(1), re.M)
    flavors = [a or b for a, b in names if (a or b) not in ("dimension", "buildConfigField", "resValue")]
    return ("test%s%sDebugUnitTest" % (flavors[0][:1].upper() + flavors[0][1:], "")) if flavors else "testDebugUnitTest"


def test_plan(rpo, path, lang, tests, note, flow):
    """Where the NEW test file goes, what it is called and how to run it (derived from the repo's own conventions). None if the repo has no
    usable convention for this language. -> {path, class, verify, framework, root}"""
    slug = _slug(note, flow)
    stem = os.path.splitext(os.path.basename(path))[0]
    fs = rpo.fileset()
    ex = tests[0] if tests else ""
    if lang == "kt":
        root = _nearest_with(rpo, path, "gradlew")
        if root is None:
            return None
        if ex:
            d = os.path.dirname(ex)
        else:
            m = re.match(r"(.*)/src/main/(java|kotlin)/(.*)$", path)
            if not m:
                return None
            d = "%s/src/test/%s/%s" % (m.group(1), m.group(2), os.path.dirname(m.group(3)))
        base = "%s%sTest" % (stem, slug)
        n = 1
        while "%s/%s.kt" % (d, base) in fs:
            n += 1
            base = "%s%sTest%d" % (stem, slug, n)
        newp = "%s/%s.kt" % (d, base)
        pkg = ""
        if ex:
            m = re.search(r"^package\s+([\w.]+)", rpo.text(ex) or "", re.M)
            pkg = m.group(1) if m else ""
        if not pkg:
            m = re.search(r"/src/test/(?:java|kotlin)/(.*)$", d + "/")
            pkg = m.group(1).strip("/").replace("/", ".") if m else ""
        mod = path[len(root) + 1:].split("/")[0] if root else "app"
        mod = mod if (root + "/" + mod + "/build.gradle.kts" in fs or root + "/" + mod + "/build.gradle" in fs) else "app"
        task = gradle_test_task(rpo.text("%s/%s/build.gradle.kts" % (root, mod)) or rpo.text("%s/%s/build.gradle" % (root, mod)) or "")
        verify = "cd %s && ./gradlew :%s:%s --tests \"%s%s\"" % (root, mod, task, (pkg + ".") if pkg else "", base) if root else \
            "./gradlew :%s:%s --tests \"%s%s\"" % (mod, task, (pkg + ".") if pkg else "", base)
        return {"path": newp, "class": base, "verify": verify, "root": root, "package": pkg,
                "framework": "JUnit5 (org.junit.jupiter) + MockK + kotlinx-coroutines-test as in the example test; one top-level test class named %s" % base}
    if lang == "py":
        root = ""
        d = os.path.dirname(path)
        while True:
            if any(f.startswith((d + "/" if d else "") + "tests/") and f.endswith(".py") for f in fs):
                root = d
                break
            if not d:
                break
            d = os.path.dirname(d)
        tdir = (root + "/tests") if root else "tests"
        if not any(f.startswith(tdir + "/") and os.path.basename(f).startswith("test_") for f in fs):
            return None
        base = "test_%s_%s" % (stem, re.sub(r"[^a-z0-9]+", "_", slug.lower()))
        n = 1
        b0 = base
        while "%s/%s.py" % (tdir, base) in fs:
            n += 1
            base = "%s_%d" % (b0, n)
        newp = "%s/%s.py" % (tdir, base)
        rel = "tests/%s.py" % base
        verify = ("cd %s && python -m pytest %s -q" % (root, rel)) if root else ("python -m pytest %s -q" % rel)
        return {"path": newp, "class": base, "verify": verify, "root": root, "framework": "pytest (plain functions named test_*), imports as the example test does"}
    if lang == "ts":
        pj = _nearest_with(rpo, path, "package.json")
        if pj is None:
            return None
        pkgtxt = rpo.text((pj + "/package.json") if pj else "package.json") or ""
        runner = "vitest" if "vitest" in pkgtxt else ("jest" if "jest" in pkgtxt else "")
        if not runner:
            return None
        ext = ".ts"
        d = os.path.dirname(ex) if ex else os.path.dirname(path)
        base = "%s.%s.test%s" % (stem, re.sub(r"[^a-z0-9]+", "", slug.lower()), ext)
        newp = "%s/%s" % (d, base) if d else base
        rel = newp[len(pj) + 1:] if pj else newp
        verify = ("cd %s && npx %s run %s" % (pj, runner, rel)) if (pj and runner == "vitest") else \
                 ("cd %s && npx %s %s" % (pj, runner, rel)) if pj else ("npx %s run %s" % (runner, rel) if runner == "vitest" else "npx %s %s" % (runner, rel))
        return {"path": newp, "class": base, "verify": verify, "root": pj, "framework": "%s (describe/it/expect as the example test does)" % runner}
    if lang == "gd":
        if "project.godot" not in fs:
            return None
        if ex:
            d = os.path.dirname(ex)
        else:
            counts = {}
            for f in fs:
                if f.endswith(".gd") and _is_test_path(f) and os.path.basename(f).startswith("test_"):
                    counts[os.path.dirname(f)] = counts.get(os.path.dirname(f), 0) + 1
            if not counts:
                return None
            d = sorted(counts, key=lambda k: (-counts[k], k))[0]
        base = "test_%s_%s" % (stem, re.sub(r"[^a-z0-9]+", "_", slug.lower()))
        n = 1
        b0 = base
        while "%s/%s.gd" % (d, base) in fs:
            n += 1
            base = "%s_%d" % (b0, n)
        newp = "%s/%s.gd" % (d, base)
        return {"path": newp, "class": base, "root": "",
                "verify": "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://%s -gexit" % newp,
                "framework": "GUT (extends GutTest, func test_*, assert_eq / assert_true / assert_false), as the example test does"}
    return None


def research(rpo, note, flow, primary, also, prim_files=None, cap=EVIDENCE_CAP_CHARS):
    """Collect compact, numbered, verifiable evidence for the bug. -> dict (see render_research). Never loads a big file into the result:
    only function ranges / hit windows."""
    lang = lang_of(primary)
    terms = terms_from(note, flow)
    r = {"primary": primary, "also": list(also), "lang": lang, "files": [], "callers": [], "tests": [], "example": {}, "state": "", "decls": "",
         "plan": None, "terms": [t["label"] for t in terms][:14], "chars": 0}
    chosen_names = []
    budget = cap
    for idx, p in enumerate([primary] + [a for a in also if a != primary][:2]):
        t = rpo.text(p)
        if t is None:
            continue
        lg = lang_of(p)
        lines = t.split("\n")
        rngs = function_ranges(t, lg)
        scored = []
        for rg in rngs:
            body_l = "\n".join(lines[rg["start"] - 1:rg["end"]])[:20000].lower()
            s, hit = _score_range(rg["name"], body_l, terms)
            if s >= 1.0:
                scored.append((s, rg, hit))
        # a long function that merely mentions a word loses to a short, specific one (the 27B reads what it is shown): size penalty
        scored.sort(key=lambda x: (-(x[0] - 0.03 * max(0, x[1]["end"] - x[1]["start"] - 25)), x[1]["start"]))
        want = 3 if idx == 0 else 2
        keep = [x for x in scored if x[0] >= 2.0][:want]
        keep += [x for x in scored if x[0] < 2.0 and x[1]["end"] - x[1]["start"] <= 40][:max(0, want - len(keep))]
        funcs = []
        for s, rg, hit in sorted(keep, key=lambda x: x[1]["start"]):
            n = rg["end"] - rg["start"] + 1
            txt = _numbered(lines, rg["start"], rg["end"]) if n <= 60 else _hit_windows(lines, terms, rg["start"], rg["end"])
            if len(txt) > budget:
                txt = txt[:max(0, budget)]
            budget -= len(txt)
            funcs.append({"name": rg["name"], "start": rg["start"], "end": rg["end"], "score": round(s, 1), "matched": hit[:6], "text": txt})
            chosen_names.append((rg["name"], p))
        decl = _decl_lines(t, lg)
        entry = {"path": p, "lang": lg, "size": len(t), "lines": len(lines), "funcs": funcs, "decls": decl}
        if not funcs:        # nothing scored: show the windows around raw term hits instead (or the head of the file)
            win = _hit_windows(lines, terms, 1, min(len(lines), 400), cap_lines=40)
            entry["window"] = win if win.count("\n") >= 3 else _numbered(lines, 1, min(len(lines), 40), cap_lines=40)
            budget -= len(entry["window"])
        r["files"].append(entry)
        if idx == 0 and lg == "kt":
            r["state"] = _kt_state_block(t)
    # callers of the chosen functions (product code only, not the definition itself, not tests)
    allowed = set(prim_files) if prim_files else None
    seen = set()
    for name, p in chosen_names[:3]:
        if len(name) < 4:
            continue
        for hp, hl, ht in rpo.grep(name, max_per_file=2, limit=30):
            if hp == p and re.match(r"\s*(?:override\s+|private\s+|suspend\s+|static\s+)*(?:fun|func|def)\b", ht):
                continue
            if _is_test_path(hp) or not ml.is_product_path(hp) or (allowed is not None and hp not in allowed):
                continue
            if re.match(r"\s*(//|#|\*|/\*)", ht):
                continue                       # a comment mentioning the name is not a caller
            if (hp, hl) in seen:
                continue
            seen.add((hp, hl))
            r["callers"].append({"fn": name, "path": hp, "line": hl, "text": ht.strip()[:170]})
            if sum(1 for c in r["callers"] if c["fn"] == name) >= 4:
                break
        if len(r["callers"]) >= 9:
            break
    r["tests"] = find_tests(rpo, primary, lang)
    head, fn, ex = _example_test(rpo, r["tests"], lang) if r["tests"] else ("", "", "")
    if not ex:   # no test for this module: borrow the style of the nearest test of the same language
        near = [f for f in rpo.files() if lang_of(f) == lang and _is_test_path(f)]
        near.sort(key=lambda f: (-_common_prefix(f, primary), len(f), f))
        head, fn, ex = _example_test(rpo, near[:3], lang)
    r["example"] = {"path": ex, "head": head, "fn": fn}
    r["plan"] = test_plan(rpo, primary, lang, r["tests"] or ([ex] if ex else []), note, flow)
    return r


def render_research(r):
    out = []
    for f in r["files"]:
        out.append("FILE %s (%s, %d lines, %d bytes)" % (f["path"], f["lang"], f["lines"], f["size"]))
        if f["decls"]:
            out.append("  declarations:\n" + "\n".join("    " + x for x in f["decls"].split("\n")))
        for fn in f["funcs"]:
            out.append("  FUNCTION %s (lines %d-%d, matched: %s)\n%s" % (fn["name"], fn["start"], fn["end"], ", ".join(fn["matched"]),
                                                                       "\n".join("    " + x for x in fn["text"].split("\n"))))
        if f.get("window"):
            out.append("  RELEVANT LINES (no single function matched):\n" + "\n".join("    " + x for x in f["window"].split("\n")))
    if r["state"]:
        out.append("STATE / DATA MODEL (%s):\n%s" % (r["primary"], "\n".join("    " + x for x in r["state"].split("\n"))))
    if r["callers"]:
        out.append("CALLERS:\n" + "\n".join("  %s called at %s:%d: %s" % (c["fn"], c["path"], c["line"], c["text"]) for c in r["callers"]))
    if r["tests"]:
        out.append("EXISTING TESTS FOR THIS MODULE: " + ", ".join(r["tests"]))
    ex = r["example"]
    if ex.get("path"):
        out.append("HOW TESTS ARE WRITTEN HERE (%s):\n%s%s" % (ex["path"], "\n".join("    " + x for x in ex["head"].split("\n")),
                   ("\n  one existing test:\n" + "\n".join("    " + x for x in ex["fn"].split("\n"))) if ex.get("fn") else ""))
    return "\n".join(out)


# ----------------------------------------------------------------------------------------------------------------------
# (2) PLAN: prompts + bounded model calls
# ----------------------------------------------------------------------------------------------------------------------
def _chat(prompt, timeout=150, max_tokens=1800):
    """One request to the local litellm (same endpoint, key, model alias and <think> stripping as manual_locator.model_chat; its 60 s per-call cap
    is too short for a 1.5k-token plan, so this has its own cap OVN_BUG_BRIEF_CALL_TIMEOUT). -> text or None on ANY problem."""
    name = ml.model_name()
    if name in ("", "off", "none"):
        return None
    timeout = max(5, min(int(timeout), int(_envf("OVN_BUG_BRIEF_CALL_TIMEOUT", 150))))
    base = os.environ.get("LITELLM_BASE", "http://localhost:4000").rstrip("/")
    key = os.environ.get("LITELLM_MASTER_KEY", "sk-shrike-local")
    body = json.dumps({"model": name, "messages": [{"role": "user", "content": prompt}], "temperature": 0.2, "max_tokens": max_tokens}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    old = None
    try:
        try:
            old = signal.signal(signal.SIGALRM, lambda *_a: (_ for _ in ()).throw(TimeoutError("alarm")))
            signal.alarm(timeout + 15)
        except ValueError:
            old = None
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(2 << 20).decode("utf-8", "replace")
        content = json.loads(raw)["choices"][0]["message"]["content"] or ""
        return re.sub(r"(?s)<think>.*?</think>", "", content)
    except Exception:  # noqa: BLE001 - timeout, refused, HTTP error, bad JSON: the caller falls back
        return None
    finally:
        try:
            signal.alarm(0)
            if old is not None:
                signal.signal(signal.SIGALRM, old)
        except Exception:  # noqa: BLE001
            pass


class Budget(ml.Budget):
    """The locator's Budget (hard call cap, wall deadline for the WHOLE stage, circuit breaker: the first failed / hung call marks the model dead and
    nothing waits on it again) with per-call max_tokens. `fn(prompt, timeout=, max_tokens=)` or `fn(prompt)` (tests)."""

    def __init__(self, fn, limit=MAX_CALLS, deadline_s=None):
        super().__init__(fn, limit=limit, deadline_s=_envf("OVN_BUG_BRIEF_BUDGET_S", 300) if deadline_s is None else deadline_s)

    def __call__(self, prompt, max_tokens=1800):
        if self.dead or self.calls >= self.limit or self.remaining() < 8:
            return None
        self.calls += 1
        try:
            try:
                res = self.fn(prompt, timeout=int(max(5, min(_envf("OVN_BUG_BRIEF_CALL_TIMEOUT", 150), self.remaining() - 3))), max_tokens=max_tokens)
            except TypeError:
                res = self.fn(prompt)
        except Exception:  # noqa: BLE001
            res = None
        if res is None:
            self.dead = True
        return res


SCHEMA_EXAMPLE = {
    "root_cause": {
        "hypothesis": "applyDiscount() subtracts the percentage from the price instead of multiplying, so a 10 percent discount on 200 returns 190 instead of 180.",
        "evidence": [{"file": "backend/app/pricing.py", "line": 41, "quote": "return price - percent"}]},
    "approach": "Fix the arithmetic in applyDiscount only; pin it with one test and one neighbouring-behaviour guard.",
    "steps": [
        {"kind": "test_first", "file": "backend/tests/test_pricing_discount.py", "function": "test_discount_is_a_percentage",
         "change": "NEW test: call applyDiscount(200, 10) and assert it equals 180; it fails today because the function returns 190.",
         "verify": "cd backend && python -m pytest tests/test_pricing_discount.py -q"},
        {"kind": "fix", "file": "backend/app/pricing.py", "function": "applyDiscount",
         "change": "Replace `return price - percent` with `return price * (100 - percent) / 100`.",
         "verify": "cd backend && python -m pytest tests/test_pricing_discount.py -q"},
        {"kind": "guard", "file": "backend/tests/test_pricing_discount_guard.py", "function": "test_zero_percent_keeps_price",
         "change": "NEW test: applyDiscount(200, 0) equals 200 and applyDiscount(200, 100) equals 0.",
         "verify": "cd backend && python -m pytest tests/test_pricing_discount_guard.py -q"}]}


def repair_hints(rpo, errors):
    """For 'function X does not exist in <file>' / 'file ... does not exist' errors: the REAL function names of the files involved, so the repair can
    pick one instead of inventing the next name."""
    files, out = [], []
    for e in errors or []:
        for m in re.finditer(r"does not exist in (\S+)|evidence\[\d+\]: the quote .* is NOT in (\S+)", e):
            f = m.group(1) or m.group(2)
            if f and f not in files and rpo.exists(f):
                files.append(f)
    for f in files[:3]:
        lg = lang_of(f)
        names = [x["name"] for x in function_ranges(rpo.text(f) or "", lg)]
        if names:
            out.append("Functions that REALLY exist in %s (use only these names): %s" % (f, ", ".join(names[:45])))
    return "\n".join(out)


def build_plan_prompt(repo_name, platform, note, flow, r, errors=None, prev=None, hints=""):
    plan = r["plan"]
    allowed = [f["path"] for f in r["files"]] + sorted({c["path"] for c in r["callers"]})
    ev = render_research(r)
    parts = [
        "You are the planner for an autonomous coding agent (a 27B model). It fails on vague, multi-file or untested tasks and does well on SMALL steps "
        "that change ONE file, name the exact function and the exact change, and have a real test to run. A human tester reported a bug in the app.",
        "APP: %s   PLATFORM: %s   SCREEN/FLOW: %s\nTESTER NOTE (verbatim): \"%s\"" % (repo_name, platform or "-", flow or "-", note),
        "REAL CODE FOUND BY SEARCH (the line numbers are exact; evidence must come from here):\n" + ev,
        "THE NEW TEST FILE FOR STEP 1 (fixed by the repo's conventions): path = %s ; framework: %s ; run it with exactly: %s"
        % (plan["path"], plan["framework"], plan["verify"]),
        "TASK: write a FIX BRIEF as ONE JSON object, nothing else. Keys: root_cause {hypothesis: one paragraph naming the cause, evidence: 1-3 items "
        "{file, line, quote}}, approach (one or two sentences), steps (3 to %d)." % MAX_STEPS,
        "RULES:\n"
        "1. evidence.quote must be copied VERBATIM (12+ characters) from ONE line of the real code above, and evidence.line must be that line's number. "
        "Do not invent code. If you are unsure of the cause, quote the lines that decide the behaviour the tester saw.\n"
        "2. Step 1 has kind \"test_first\": file is EXACTLY %s ; it creates ONE new test that asserts the CORRECT behaviour and therefore FAILS on today's code "
        "because of the bug (a test that already passes is rejected). change = what the test arranges, calls and asserts, naming the test function. "
        "function = the test function name. verify = %s (you may add a test-name selector).\n"
        "3. Step 2 has kind \"fix\": the SMALLEST change in ONE existing source file that makes step 1's test pass. Its verify runs step 1's test again. "
        "More \"fix\" steps (each ONE file, each leaving every test green, each with its own verify) only if the bug really spans several files.\n"
        "4. The LAST step has kind \"guard\": a regression guard for neighbouring behaviour, ONE test file (new or existing), whose verify runs it.\n"
        "5. EVERY step has exactly one file path (a string, never a list, never two files in the change text), a function (the exact function, method, "
        "property or test name that the step changes or creates), a change (at most 350 characters: the exact edit, naming identifiers; never 'fix the bug' "
        "or 'update the logic'), and a verify that is a real test RUN (never grep / ls / cat / test -e).\n"
        "6. Every step stays in the SAME language as step 1's test (same test runner): a fix that needs another language is another bug. Source files to edit must exist in the real code (the FILE blocks, CALLERS or related files); never edit tests in a fix step; do not touch "
        "files you were not shown unless the evidence proves they are needed.\n"
        "7. Do not write code blocks. The change is a description with identifiers, not a diff.\n"
        "EXAMPLE of the format (a DIFFERENT bug, in Python; yours must use the files, functions and commands above): " + json.dumps(SCHEMA_EXAMPLE)]
    if errors:
        parts.append("YOUR PREVIOUS BRIEF WAS REJECTED BY THE CHECKER FOR:\n- " + "\n- ".join(errors[:10]) + (("\n" + hints) if hints else "") +
                     "\nFix EXACTLY these problems and reply with the corrected JSON object only."
                     + (("\nYour previous JSON:\n" + prev[:3500]) if prev else ""))
    _ = allowed
    return "\n\n".join(parts)


def build_test_prompt(repo_name, note, brief, r, error=None, prev_code=None, vacuous=False):
    plan = r["plan"]
    s1 = brief["steps"][0]
    fn_text = "\n".join("%s" % f["text"] for f in r["files"][:1] for f in f["funcs"][:2])
    ex = r["example"]
    parts = [
        "Write ONE new test file that reproduces a bug. It must FAIL on the current code (because of the bug) and pass once the bug is fixed.",
        "APP: %s. Tester note: \"%s\"\nROOT CAUSE (hypothesis): %s" % (repo_name, note, brief["root_cause"]["hypothesis"]),
        "THE TEST TO WRITE (step 1): %s" % s1["change"],
        "FILE PATH (do not change): %s\nFRAMEWORK: %s\nIt is run with: %s" % (plan["path"], plan["framework"], s1["verify"]),
        "THE CODE UNDER TEST (numbered real lines):\n" + fn_text[:6000],
    ]
    if r["state"]:
        parts.append("STATE CLASS:\n" + r["state"][:2500])
    if ex.get("head"):
        parts.append("AN EXISTING TEST IN THIS MODULE (copy its imports, setup, helpers and style; the numbers are line numbers, not code):\n%s%s"
                     % (ex["head"][:3500], ("\n---\n" + ex["fn"][:1800]) if ex.get("fn") else ""))
    parts.append("RULES: reply with ONLY the complete file content in ONE code fence. Use only APIs that appear above or in the existing test. "
                 "Assert the CORRECT behaviour (so it fails today). Exactly one or two test functions. No placeholders, no TODO, no skipped tests.")
    if vacuous:
        parts.append("YOUR PREVIOUS TEST PASSED ON THE CURRENT CODE, which means it does not reproduce the bug. Rewrite it so it asserts what the tester "
                     "expected and the current code gets wrong.")
    if error:
        parts.append("YOUR PREVIOUS TEST FILE COULD NOT RUN: %s\nFix that (imports, constructor arguments, names) and reply with the corrected file only." % error[:900])
        if prev_code:
            parts.append("Previous file:\n" + prev_code[:3500])
    return "\n\n".join(parts)


def parse_brief_json(text):
    """The brief object from a model reply: the first balanced JSON object that has `steps` / `root_cause` (a reply can echo a fragment or prose
    with braces first), one wrapper level unwrapped ({"brief": {...}}). None if there is no object at all."""
    if not text:
        return None
    first = None
    for m in re.finditer(r"\{", text):
        depth, i, in_str, esc = 0, m.start(), False, False
        for j in range(i, len(text)):
            ch = text[j]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        d = json.loads(text[i:j + 1])
                    except ValueError:
                        break
                    if isinstance(d, dict):
                        if "steps" in d or "root_cause" in d:
                            return d
                        for v in d.values():
                            if isinstance(v, dict) and ("steps" in v or "root_cause" in v):
                                return v
                        first = first or d
                    break
    return first


def extract_code(text):
    """The content of the first code fence (or the whole text if there is no fence)."""
    if not text:
        return None
    m = re.search(r"```[A-Za-z0-9_+-]*\n(.*?)```", text, re.S)
    code = m.group(1) if m else text
    code = code.strip("\n")
    return code if 20 <= len(code) <= 12000 else None


# ----------------------------------------------------------------------------------------------------------------------
# (3) VALIDATE (mechanical; the model is advisory)
# ----------------------------------------------------------------------------------------------------------------------
_KIND_ALIASES = {"test_first": "test_first", "test-first": "test_first", "testfirst": "test_first", "test": "test_first", "repro": "test_first",
                 "reproduce": "test_first", "fix": "fix", "implement": "fix", "guard": "guard", "regression_guard": "guard",
                 "regression-guard": "guard", "regression": "guard"}
INSPECT = re.compile(r"(?i)\b(inspect|investigate|look (?:into|at)|review|examine|debug|figure out|find out|check (?:whether|if|that)|make sure|ensure that|verify that|identify)\b")
SMELL = re.compile(r"(?i)hard-?coded?|\bDEFAULT_[A-Z_]{3,}\b|\bspecial[- ]case\b|\b(constant|static|fixed) (list|array|map)\b")
HEDGE = re.compile(r"(?i)\b(or similar|or equivalent|or something|something like|such as|e\.g\.|for example|if needed|if necessary|if applicable|as appropriate|"
                   r"maybe|perhaps|probably|possibly|might|could be|and so on|etc\.?)(?!\w)")
_IDENT_CAMEL = re.compile(r"\b[A-Za-z_]*[a-z][A-Z]\w*\b|\b[a-z]\w*_\w+\b")
FILE_TOKEN = re.compile(r"[A-Za-z0-9_./-]+\.(?:kt|kts|java|py|ts|tsx|js|jsx|vue|gd|swift|xml|json|yaml|yml)\b")
OK_PATH = re.compile(r"^[A-Za-z0-9_./@+-]+$")
GRADLE_FLAGS = {"--tests", "--console=plain", "--offline", "-q", "--quiet", "--no-daemon", "--continue", "--rerun-tasks", "--info"}
GODOT_FLAGS = {"--headless", "-s", "-gexit", "-gexit_on_success", "-glog=1", "-glog=0"}


def lint_native_verify(cmd, lang):
    """Shell + test-run rules for gradle / godot VERIFY commands (card_lint's allowlist covers python and node only)."""
    errs = []
    segs, problems, substs = cl.parse_shell(cmd)
    for p in problems:
        errs.append("verify shell: %s" % p)
    if substs:
        errs.append("verify may not use command substitution")
    if not segs:
        return errs or ["verify has no command"]
    for i, sg in enumerate(segs):
        if sg["redirs"] or sg.get("neg"):
            errs.append("verify may not redirect or negate")
        if i < len(segs) - 1 and sg["op"] != "&&":
            errs.append("verify may only chain with &&")
    words = [sg["words"] for sg in segs]
    for w in words[:-1]:
        if not (w and w[0] == "cd" and len(w) == 2 and not w[1].startswith("/") and ".." not in w[1].split("/") and OK_PATH.match(w[1])):
            errs.append("only a relative `cd <dir>` may precede the test command")
    last = words[-1]
    if lang == "kt":
        if not last or os.path.basename(last[0]) not in ("gradlew",):
            errs.append("a Kotlin verify must run ./gradlew")
        else:
            toks = last[1:]
            tasks = [t for t in toks if not t.startswith("-") and re.match(r"^:?[\w:]*test\w*$", t)]
            if not tasks:
                errs.append("gradle verify needs a test task (:app:test)")
            if "--tests" in toks and any(t.split(":")[-1] == "test" for t in tasks):
                errs.append("gradle's umbrella `test` task rejects --tests (Unknown command-line option): use the variant unit-test task named in the planned new-test command")
            if "--tests" not in toks or toks.index("--tests") + 1 >= len(toks) or not re.match(r"^[\w.*$]+$", toks[toks.index("--tests") + 1]):
                errs.append("gradle verify must select the test with --tests \"<package.Class[.method]>\"")
            for t in toks:
                if t.startswith("-") and t not in GRADLE_FLAGS:
                    errs.append("gradle flag %s is not allowed" % t)
    elif lang == "gd":
        if not last or os.path.basename(last[0]) not in ("godot", "godot4"):
            errs.append("a GDScript verify must run godot --headless with GUT")
        else:
            toks = last[1:]
            if "--headless" not in toks or not any(t.endswith("addons/gut/gut_cmdln.gd") for t in toks):
                errs.append("godot verify must be `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://<test file> -gexit`")
            sel = [t for t in toks if t.startswith(("-gtest=", "-gdir="))]
            if not sel or not all(re.match(r"^-g(test|dir)=(res://)?[\w./-]+$", t) for t in sel):
                errs.append("godot verify must select the test with -gtest=res://<path>")
            for t in toks:
                if t.startswith("-") and t not in GODOT_FLAGS and not t.startswith(("-gtest=", "-gdir=")):
                    errs.append("godot flag %s is not allowed" % t)
    return errs


def lint_step_verify(cmd, lang, step, repo_root):
    """-> [errors]. A verify must be a REAL test run (not grep / ls / test -e / python -c), pass the card_lint shell rules, and run at most one app."""
    if not isinstance(cmd, str) or not cmd.strip():
        return ["verify is missing"]
    if len(cmd) > 400 or "\n" in cmd:
        return ["verify must be a single line of at most 400 characters"]
    if lang in ("kt", "gd"):
        return lint_native_verify(cmd, lang)
    item = {"path": step.get("file", ""), "desc": "%s %s" % (step.get("change", ""), step.get("file", "")), "tier": ITEM_TIER, "raw": "", "verify": None,
            "cat": "bugfix", "tags": []}
    findings, _info = cl.lint_verify(cmd, item, repo_root)
    errs = ["verify [%s] %s" % (f["rule"], f["msg"]) for f in findings if f["severity"] == "error"]
    segs, _p, _s = cl.parse_shell(cmd)
    ok_run = False
    for sg in segs:
        w, _ = cl._strip_prefix(sg["words"])
        h = cl.head_of(sg["words"])
        a = w[1:] if w else []
        if h == "pytest" or (h == "python" and "-m" in a and "pytest" in a):
            ok_run = True
        if h in ("vitest", "jest") or (h == "npx" and a and os.path.basename(a[0]) in ("vitest", "jest")):
            ok_run = True
        if h == "npm" and a and a[0] in ("test", "t", "run") and (a[0] != "run" or (len(a) > 1 and a[1].startswith("test"))):
            ok_run = True
    if not ok_run:
        errs.append("verify is not a real test run (use pytest / npx vitest / npm test; grep, test -e, python -c and the like are existence checks)")
    return errs


def _norm_kind(k):
    return _KIND_ALIASES.get(re.sub(r"[\s]+", "_", str(k or "").strip().lower()))


def _quotes_tester_literal(change, note):
    """A fix whose change quotes a literal that the tester typed ('Qatar 2', '00s Replay') is special-casing the example."""
    nl = re.sub(r"\s+", " ", (note or "").lower())
    for m in re.finditer(r"['\"]([^'\"]{4,40})['\"]", change or ""):
        lit = re.sub(r"\s+", " ", m.group(1).strip().lower())
        if len(lit) >= 4 and re.search(r"[a-z]", lit) and " " in lit.strip() and lit in nl:
            return True
    return False


def validate_brief(b, rpo, r=None, allowed_edit=None, repo_root=None, require_new_test=True, note=""):
    """Mechanical validation of a brief (model-written or imported). -> {ok, errors[], warnings[], brief}. `brief` is the NORMALIZED copy (strings
    stripped, evidence lines corrected, kinds canonical, ids 1..n). Pure apart from read-only git access through `rpo`. `r` (research) supplies the
    expected new-test path / the platform; without it (imports) a new test file only has to sit in an existing test directory."""
    errs, warns = [], []
    if not isinstance(b, dict):
        return {"ok": False, "errors": ["the brief is not a JSON object"], "warnings": [], "brief": None}
    note_text = note or (b.get("note") if isinstance(b.get("note"), str) else "")
    if len(json.dumps(b, ensure_ascii=False)) > 24000:
        return {"ok": False, "errors": ["the brief is too large"], "warnings": [], "brief": None}
    nb = {"version": SCHEMA_VERSION}
    for k in ("repo", "feat", "note", "flow", "date", "platform"):
        if isinstance(b.get(k), str):
            nb[k] = b[k].strip()[:400]
    rc = b.get("root_cause")
    if not isinstance(rc, dict):
        errs.append("root_cause must be an object {hypothesis, evidence[]}")
        rc = {}
    hyp = rc.get("hypothesis")
    if not isinstance(hyp, str) or not (40 <= len(hyp.strip()) <= 900):
        errs.append("root_cause.hypothesis must be a paragraph of 40 to 900 characters")
        hyp = hyp if isinstance(hyp, str) else ""
    ev_in = rc.get("evidence")
    evidence = []
    if not isinstance(ev_in, list) or not (1 <= len(ev_in) <= 4):
        errs.append("root_cause.evidence must list 1 to 4 {file, line, quote} items")
        ev_in = ev_in if isinstance(ev_in, list) else []
    product_ev = 0
    for i, e in enumerate(ev_in[:4]):
        if not isinstance(e, dict):
            errs.append("evidence[%d] is not an object" % i)
            continue
        f, q, ln = e.get("file"), e.get("quote"), e.get("line")
        f = _norm_path(f) if isinstance(f, str) else ""
        q = q.strip() if isinstance(q, str) else ""
        try:
            ln = int(ln)
        except (TypeError, ValueError):
            ln = 0
        if not f or not rpo.exists(f):
            errs.append("evidence[%d]: file %r does not exist" % (i, f))
            continue
        if len(re.sub(r"\s+", " ", q)) < 8:
            errs.append("evidence[%d]: quote is too short (copy a distinctive line of 8+ characters verbatim)" % i)
            continue
        t = rpo.text(f) or ""
        lines = t.split("\n")
        qn = re.sub(r"\s+", " ", q)
        found = [j + 1 for j, l in enumerate(lines) if qn in re.sub(r"\s+", " ", l)]
        if not found:
            errs.append("evidence[%d]: the quote %r is NOT in %s (quotes must be verbatim)" % (i, q[:60], f))
            continue
        near = [j for j in found if ln and abs(j - ln) <= 5]
        if not near:
            errs.append("evidence[%d]: the quote is in %s at line %s, not near line %s" % (i, f, ",".join(map(str, found[:3])), ln))
            continue
        real = min(near, key=lambda j: abs(j - ln))
        if real != ln:
            warns.append("evidence[%d]: line corrected %d -> %d" % (i, ln, real))
        evidence.append({"file": f, "line": real, "quote": q[:200]})
        if not _is_test_path(f):
            product_ev += 1
    if evidence and not product_ev:
        errs.append("at least one evidence item must be in product code, not a test")
    nb["root_cause"] = {"hypothesis": hyp.strip(), "evidence": evidence}
    nb["approach"] = (b.get("approach") or "").strip()[:700] if isinstance(b.get("approach"), str) else ""
    steps_in = b.get("steps")
    if not isinstance(steps_in, list):
        errs.append("steps must be a list")
        steps_in = []
    if not (MIN_STEPS <= len(steps_in) <= MAX_STEPS):
        errs.append("a brief has %d to %d steps (test_first, fix..., guard); got %d" % (MIN_STEPS, MAX_STEPS, len(steps_in)))
    steps = []
    plan = (r or {}).get("plan") or None
    for i, s in enumerate(steps_in[:MAX_STEPS]):
        tag = "step %d" % (i + 1)
        if not isinstance(s, dict):
            errs.append("%s is not an object" % tag)
            continue
        kind = _norm_kind(s.get("kind"))
        if kind is None:
            errs.append("%s: kind must be one of test_first / fix / guard" % tag)
        f = s.get("file")
        if not isinstance(f, str):
            errs.append("%s: file must be ONE path string (got %s): a step touches exactly one file" % (tag, type(f).__name__))
            f = ""
        f = _norm_path(f) if f else ""
        if f and (not OK_PATH.match(f) or ".." in f.split("/") or f.startswith("/")):
            errs.append("%s: file %r is not ONE clean relative path (several files or odd characters): a step touches exactly one file" % (tag, f[:80]))
            f = ""
        fn = s.get("function")
        fn = fn.strip() if isinstance(fn, str) else ""
        ch = s.get("change")
        ch = re.sub(r"\s+", " ", ch).strip() if isinstance(ch, str) else ""
        vf = s.get("verify")
        vf = vf.strip() if isinstance(vf, str) else ""
        if not fn or len(fn) > 120:
            errs.append("%s: function must name the exact function / method / test (1-120 chars)" % tag)
        if not (12 <= len(ch) <= 420):
            errs.append("%s: change must be 12-420 characters naming the exact edit" % tag)
        elif "```" in ch:
            errs.append("%s: change must be a description, not a code block" % tag)
        elif not re.search(r"[A-Za-z]+[A-Z]\w+|\w+_\w+|\w+\(\)|['\"][^'\"]{2,}['\"]|\.\w+\(", ch):
            errs.append("%s: change names no identifier or literal (too vague: say exactly what to change)" % tag)
        elif HEDGE.search(ch):
            errs.append("%s: the change is not exact (%r): no 'or similar' / 'e.g.' / 'probably' / 'such as' - say precisely what to change" % (tag, HEDGE.search(ch).group(0)))
        steps.append({"id": i + 1, "kind": kind, "file": f, "function": fn[:120], "change": ch[:420], "verify": vf})
    # ordering / counts
    kinds = [s["kind"] for s in steps]
    if steps:
        if kinds[0] != "test_first":
            errs.append("step 1 must be kind test_first (a test that reproduces the bug and fails on the current code)")
        if kinds.count("test_first") != 1:
            errs.append("exactly one test_first step (the first)")
        if kinds[-1] != "guard" or kinds.count("guard") != 1:
            errs.append("the last step must be the only kind guard (a regression-guard test)")
        if not any(k == "fix" for k in kinds):
            errs.append("at least one fix step between test_first and guard")
        if "test_first" in kinds[1:] or "guard" in kinds[:-1]:
            errs.append("order must be test_first, fix..., guard")
    fs = rpo.fileset()
    s1 = steps[0] if steps else None
    tf_file = s1["file"] if s1 and s1["kind"] == "test_first" else ""
    testdirs = {os.path.dirname(f) for f in fs if _is_test_path(f) and lang_of(f)}
    for s in steps:
        tag = "step %d" % s["id"]
        f = s["file"]
        if not f:
            continue
        lg = lang_of(f)
        if lg not in LANGS:
            errs.append("%s: %s is not a Kotlin / GDScript / Python / TypeScript file" % (tag, f))
            continue
        tf_lang = lang_of(tf_file) if tf_file else ""
        if tf_lang and lg != tf_lang:
            errs.append("%s: %s is a %s file but the test-first test is %s: one brief stays in ONE language / test runner (a cross-language fix is two bugs; fix the part the test covers)"
                        % (tag, f, lg, tf_lang))
            continue
        bad = unworkable_why(rpo, f)
        if bad:
            errs.append("%s: %s (a step may never edit a hard-banned or oversize file)" % (tag, bad))
            continue
        exists = f in fs
        if s["kind"] in ("test_first", "guard"):
            if not _is_test_path(f) and not re.search(r"test", os.path.basename(f), re.I):
                errs.append("%s: %s is not a test file" % (tag, f))
            if s["kind"] == "test_first" and exists and require_new_test:
                errs.append("%s: the test_first step must create a NEW test file (%s already exists)" % (tag, f))
            if not exists and os.path.dirname(f) not in testdirs:
                errs.append("%s: new test file %s is not in an existing test directory" % (tag, f))
            if s["kind"] == "test_first" and plan and not exists and f != plan["path"]:
                errs.append("%s: the new test file must be exactly %s" % (tag, plan["path"]))
        else:
            if not exists:
                errs.append("%s: fix file %s does not exist" % (tag, f))
                continue
            if _is_test_path(f) or not ml.is_product_path(f):
                errs.append("%s: %s is not product code (a fix step edits source, not tests/fixtures/docs)" % (tag, f))
                continue
            if allowed_edit is not None and f not in allowed_edit:
                errs.append("%s: %s is outside the platform the bug was reported on" % (tag, f))
            names = defined_names(rpo.text(f) or "", lg)
            ids = re.findall(r"[A-Za-z_]\w*", s["function"])
            if ids and ids[-1] not in names and not re.search(r"\b%s\b" % re.escape(ids[-1]), rpo.text(f) or ""):
                errs.append("%s: function %r does not exist in %s" % (tag, s["function"], f))
        if s["kind"] == "fix" and INSPECT.search(s["change"]):
            errs.append("%s: a fix step says what to CHANGE, not what to %s (the investigation is the planner's job: name the exact edit)" % (tag, INSPECT.search(s["change"]).group(1).lower()))
        if s["kind"] == "fix" and (SMELL.search(s["change"]) or _quotes_tester_literal(s["change"], note_text)):
            errs.append("%s: a fix must change the RULE, not paper over the tester's example (hard-coded / default / special-cased data, or a literal copied from the note)" % tag)
        if s["kind"] == "fix" and exists:
            # an identifier the change relies on must exist (or be introduced by the change): a plan built on an invented helper cannot land
            ftext = rpo.text(f) or ""
            seen_tok = set()
            for m in _IDENT_CAMEL.finditer(s["change"]):
                name = m.group(0)
                if name in seen_tok or name == s["function"] or len(name) < 5:
                    continue
                seen_tok.add(name)
                mk = r"(?i)\b(add|create|introduce|define|declare|new|extract|implement|write|expose|emit|publish|broadcast)\b[^.]{0,70}\b%s\b" % re.escape(name)
                if re.search(r"\b%s\b" % re.escape(name), ftext) or re.search(mk, s["change"]):
                    continue
                # introduced by ANOTHER step of the same brief (named as that step's function, or created in its change)
                if any(o is not s and (re.search(r"\b%s\b" % re.escape(name), o["function"]) or re.search(mk, o["change"])) for o in steps):
                    continue
                if rpo.grep(name, limit=1):
                    continue
                errs.append("%s: the change relies on `%s`, which does not exist anywhere in the repo (invent nothing; to ADD it say 'add a new function %s' in this change, or name it as the function of the step that creates it)" % (tag, name, name))
                break
        # one file only: the change text may not name another file of the repo (the test_first file is the one allowed mention)
        for tok in FILE_TOKEN.findall(s["change"]):
            base = os.path.basename(tok)
            other = [p for p in fs if (p == tok or p.endswith("/" + tok) or (("/" not in tok) and os.path.basename(p) == base))]
            if other and f not in other and tf_file not in other and not any(os.path.basename(f) == base for _ in [0]):
                errs.append("%s: the change names another file (%s): a step touches exactly one file" % (tag, tok))
                break
        vlint = lint_step_verify(s["verify"], lg, s, repo_root)
        errs += ["%s: %s" % (tag, e) for e in vlint]
    # the verify of test_first and of the first fix must run the new test
    if s1 and s1["kind"] == "test_first" and s1["file"]:
        marker = os.path.splitext(os.path.basename(s1["file"]))[0]
        if marker not in s1["verify"] and (not plan or plan["class"] not in s1["verify"]):
            errs.append("step 1: verify must run the new test (%s)" % marker)
        fixes = [s for s in steps if s["kind"] == "fix"]
        if fixes and marker not in fixes[0]["verify"] and (not plan or plan["class"] not in fixes[0]["verify"]):
            errs.append("step %d: the first fix step's verify must run step 1's test (%s) so the fix is proven by the repro" % (fixes[0]["id"], marker))
        guards = [s for s in steps if s["kind"] == "guard"]
        if guards and guards[0]["file"] and os.path.splitext(os.path.basename(guards[0]["file"]))[0] not in guards[0]["verify"]:
            errs.append("step %d: the guard's verify must run the guard test" % guards[0]["id"])
    nb["steps"] = steps
    return {"ok": not errs, "errors": errs, "warnings": warns, "brief": nb}


# ----------------------------------------------------------------------------------------------------------------------
# red proof: run the test-first step on the CURRENT code in a throwaway worktree
# ----------------------------------------------------------------------------------------------------------------------
_FAIL_LINE = re.compile(r"AssertionError|AssertionFailedError|assert |Expected|expected|\[Failed\]|FAILED|toBe|toEqual|to equal|to be ", re.I)
_BROKEN = re.compile(r"SyntaxError|IndentationError|NameError|ModuleNotFoundError|ImportError|Cannot find module|Failed to resolve import|Transform failed|"
                     r"Unresolved reference|e: .*\.kt|Compilation error|compileDebugUnitTestKotlin FAILED|Parse Error|Failed to load script|Failed to compile|"
                     r"SCRIPT ERROR|Could not find|no tests ran|collected 0 items|No tests found|error TS\d+", re.I)


def exec_policy(lang):
    mode = os.environ.get("OVN_BUG_BRIEF_EXEC", "auto").strip().lower()      # auto | on | off
    if mode == "off":
        return False
    if mode == "on":
        return True
    return lang in ("py", "ts", "gd", "kt")   # auto: all four (measured on the box 2026-10-02: a gradle unit-test run in a fresh worktree took 10 s, godot ~20 s)


def _gut_summary(xml_path):
    try:
        import xml.etree.ElementTree as ET
        root = ET.parse(xml_path).getroot()
        return int(root.attrib.get("failures", 0) or 0), int(root.attrib.get("errors", 0) or 0), int(root.attrib.get("tests", 0) or 0)
    except Exception:  # noqa: BLE001
        return None


_UNSAFE_TEST = re.compile(
    r"os\.system|os\.popen|os\.remove|os\.unlink|os\.rmdir|os\.rename|os\.kill|subprocess|shutil\.|socket|urllib|requests\.|httpx|http\.client|ftplib|smtplib|"
    r"\beval\s*\(|\bexec\s*\(|__import__|importlib|ctypes|pty\.|"                                              # python
    r"Runtime\.getRuntime|ProcessBuilder|java\.net|java\.nio\.file\.Files|\.deleteRecursively|\.delete\(\)|System\.exit|"        # kotlin / java
    r"OS\.execute|OS\.shell_open|OS\.kill|DirAccess\.remove|DirAccess\.rename|HTTPRequest|HTTPClient|StreamPeerTCP|FileAccess\.open\([^)]*WRITE|"   # godot
    r"child_process|require\(|fs\.(write|unlink|rm)|process\.exit|fetch\(|XMLHttpRequest|\brm\s+-")                              # ts / shell
_FORBID_PATH = re.compile(r"(/etc/|/home/|/root/|~/|\.ssh|\.env\b|/proc/|/var/)")


def test_failure_evidence(lang, rc, out):
    """-> a short reason when `out` shows a TEST that ran and failed (pytest rc 1 + a failed count / assertion; vitest FAIL + assertion; gradle 'Class > test
    FAILED' / 'N tests completed, M failed' / an assertion error), else ''. A crashed build / runner is not evidence."""
    if lang == "py":
        if rc == 1 and re.search(r"\b\d+ failed\b|\bFAILED\b|AssertionError", out):
            return "pytest: the test fails on the current code"
        return ""
    if lang == "ts":
        if re.search(r"AssertionError|expected .* to |FAIL\s+\S+\.test\.|Tests\s+\d+ failed|\b\d+ failed\b", out) and not re.search(r"Cannot find module|SyntaxError|Failed to resolve", out):
            return "vitest: the test fails on the current code"
        return ""
    if lang == "kt":
        m = re.search(r"^\S.* > .* FAILED\s*$", out, re.M) or re.search(r"\d+ tests? completed, \d+ failed", out) or re.search(r"AssertionFailedError|AssertionError", out)
        if m and not re.search(r"Compilation error|Unresolved reference|^e: ", out, re.M):
            return "gradle: the test fails on the current code"
        return ""
    return ""


def infra_reason(out):
    """The first useful line of a crashed build ('What went wrong:' + the next line), for the not-run reason."""
    m = re.search(r"What went wrong:\s*\n(.+)", out)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()[:160]
    m = re.search(r"(?m)^(?:FAILURE|Error|ERROR|error)[: ].{0,160}", out)
    return re.sub(r"\s+", " ", m.group(0)).strip()[:160] if m else ""


def failure_line(text):
    """The most informative failing-assertion line of a test run's output: pytest's `E   AssertionError: assert 'vod' == 'live'` first, then the first
    line that looks like a failure (never the source line pytest marks with '>')."""
    lines = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text).splitlines()      # GUT / gradle colour codes
    for ln in lines:
        if re.match(r"^E\s+\S", ln) and _FAIL_LINE.search(ln):
            return re.sub(r"\s+", " ", ln[1:]).strip()[:200]
    for ln in lines:
        if _FAIL_LINE.search(ln) and not ln.lstrip().startswith(("collected", "=====", ">")):
            return re.sub(r"\s+", " ", ln).strip()[:200]
    return ""


def unsafe_test_code(code):
    """The red proof EXECUTES a model-written test: refuse code that shells out, touches the network, deletes / writes files outside the test sandbox,
    or reads obvious secrets. -> the offending fragment or None. (The fleet already runs model-written tests all day; this keeps the harness's own
    extra execution to pure assertions.)"""
    m = _UNSAFE_TEST.search(code) or _FORBID_PATH.search(code)
    return m.group(0) if m else None


def red_proof(rp, ref, repo_name, plan, code, lang, timeout=None):
    """Write `code` to plan['path'] in a throwaway worktree of `ref`, run plan's verify there. -> {status, reason, failure_line, ms}
    status: proven-red (fails, for a test-shaped reason) | vacuous (passes on the current code) | invalid (does not compile / import / collect) |
    not-run (infra: no tool, timeout, no worktree). Never raises."""
    timeout = int(timeout or _envf("OVN_BUG_BRIEF_EXEC_TIMEOUT", 600))
    t0 = time.time()
    bad = unsafe_test_code(code)
    if bad:
        return {"status": "invalid", "reason": "the test code uses a forbidden API or path (%s): tests may only assert" % bad[:40], "failure_line": "", "ms": 0}
    if os.path.isabs(plan["path"]) or ".." in plan["path"].split("/"):
        return {"status": "not-run", "reason": "test path escapes the worktree", "failure_line": "", "ms": 0}
    try:
        import qa_common as qc
        import acceptance_card as ac
    except Exception as ex:  # noqa: BLE001
        return {"status": "not-run", "reason": "exec machinery unavailable: %s" % type(ex).__name__, "failure_line": "", "ms": 0}
    home = None
    linked = []
    try:
        with qc.worktree(rp, ref) as wt:
            if wt is None:
                return {"status": "not-run", "reason": "could not create a worktree", "failure_line": "", "ms": 0}
            dst = os.path.join(wt, plan["path"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8") as fh:
                fh.write(code.rstrip("\n") + "\n")
            cmd = plan["verify"]
            xml = None
            if lang in ("py", "ts"):
                venv = None
                if lang == "py":
                    # the repo's own venv: <app root>/.venv (iptv-backend/.venv, backend/.venv ...) first, then acceptance_card's guesses
                    for d in ((plan.get("root") or ""), "backend", ""):
                        for vn in (".venv", "venv"):
                            b = os.path.join(rp, d, vn, "bin")
                            if os.path.exists(os.path.join(b, "pytest")) and os.path.exists(os.path.join(b, "python")):
                                venv = venv or b
                    venv = venv or ac.guess_venv_bin(repo_name)
                env, home = ac._exec_env(wt, venv)
                # node_modules is provisioned by symlink (removed before the worktree is deleted), like acceptance_card.exec_check
                for d in {"", plan.get("root") or ""}:
                    src = os.path.join(rp, d, "node_modules")
                    tgt = os.path.join(wt, d, "node_modules")
                    if os.path.isdir(src) and os.path.isdir(os.path.dirname(tgt)) and not os.path.exists(tgt):
                        os.symlink(src, tgt)
                        linked.append(tgt)
                if lang == "py" and not shutil.which("pytest", path=env["PATH"]) and not shutil.which("python", path=env["PATH"]):
                    return {"status": "not-run", "reason": "no python in the exec env", "failure_line": "", "ms": 0}
            else:
                home = tempfile.mkdtemp(prefix="bug-brief-home-")
                env = dict(os.environ)
                env.update({"CI": "1", "NO_COLOR": "1", "TERM": "dumb", "HTTP_PROXY": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9",
                            "ANTHROPIC_API_KEY": "", "OPENAI_API_KEY": ""})
                if lang == "kt":
                    sdk = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/android-sdk")
                    env["ANDROID_HOME"] = sdk
                    root = plan.get("root") or ""
                    lp = os.path.join(wt, root, "local.properties")
                    if not os.path.exists(lp):
                        with open(lp, "w") as fh:
                            fh.write("sdk.dir=%s\n" % sdk)
                    cmd = cmd + " --offline --console=plain"
                else:       # gd: a `godot` on PATH, an import pass (fresh worktree has no .godot cache), and a junit xml for an honest verdict
                    gb = shutil.which("godot") or shutil.which("godot4") or os.path.expanduser("~/godot/godot4")
                    if not gb or not os.path.exists(gb):
                        return {"status": "not-run", "reason": "godot binary not found", "failure_line": "", "ms": 0}
                    shim = os.path.join(home, "shim")
                    os.makedirs(shim, exist_ok=True)
                    os.symlink(gb, os.path.join(shim, "godot"))
                    env["PATH"] = shim + os.pathsep + env.get("PATH", "/usr/bin:/bin")
                    xml = os.path.join(home, "gut.xml")
                    ac.run_sandboxed("godot --headless --path . --import", wt, env, min(180, timeout))
                    cmd = cmd + " -gjunit_xml_file=%s" % xml
            rc, out, ms = ac.run_sandboxed(cmd, wt, env, timeout) if lang in ("py", "ts") else _run_plain(cmd, wt, env, timeout)
            tail = out[-6000:]
            fl = failure_line(tail)
            if rc == 124:
                return {"status": "not-run", "reason": "timeout after %ds" % timeout, "failure_line": "", "ms": ms}
            if rc == 127 or re.search(r"command not found|No such file or directory: 'gradlew'|\./gradlew: No such file", tail):
                return {"status": "not-run", "reason": "command not found", "failure_line": "", "ms": ms}
            if lang == "gd":
                summ = _gut_summary(xml) if xml and os.path.exists(xml) else None
                if re.search(r"Parse Error|Failed to load script|Failed to compile|SCRIPT ERROR: Parse", tail) or summ is None or summ[2] == 0:
                    return {"status": "invalid", "reason": "the test did not parse / load / run (GUT ran 0 tests)", "failure_line": fl, "ms": ms,
                            "tail": re.sub(r"\s+", " ", tail[-400:])}
                if summ[0] + summ[1] == 0:
                    return {"status": "vacuous", "reason": "the test PASSES on the current code (%d tests)" % summ[2], "failure_line": "", "ms": ms}
                return {"status": "proven-red", "reason": "GUT: the test fails on the current code (%d failure(s), %d error(s), %d test(s) run)" % (summ[0], summ[1], summ[2]),
                        "failure_line": fl, "ms": ms}
            if rc == 0:
                return {"status": "vacuous", "reason": "the test PASSES on the current code", "failure_line": "", "ms": ms}
            if lang == "kt" and re.search(r"offline mode|No cached version|Could not resolve|SDK location not found|Unsupported class file", tail):
                return {"status": "not-run", "reason": "gradle could not run offline here", "failure_line": "", "ms": ms}
            if _BROKEN.search(tail) and not re.search(r"AssertionError|AssertionFailedError|FAILED.*>.*FAILED|expected:? ?<|Expected", tail):
                return {"status": "invalid", "reason": "the test does not compile / import / get collected", "failure_line": fl, "ms": ms,
                        "tail": re.sub(r"\s+", " ", tail[-400:])}
            if lang in ("py", "ts"):
                kind, why = ac.classify_outcome(rc, out, wt)
                if kind in ("broken", "infra"):
                    return {"status": "invalid" if kind == "broken" else "not-run", "reason": "%s: %s" % (kind, why), "failure_line": fl, "ms": ms,
                            "tail": re.sub(r"\s+", " ", tail[-400:])}
                if why.startswith("import-error") or why in ("no-tests-collected", "target-missing"):
                    return {"status": "invalid", "reason": why, "failure_line": fl, "ms": ms, "tail": re.sub(r"\s+", " ", tail[-400:])}
            # POSITIVE evidence of a failing TEST is required: a non-zero exit alone also means "gradle could not configure the build" / "vitest crashed"
            # (2026-10-02 trial: a gradle build that died in 0.8 s was first reported as 'proven red')
            ev = test_failure_evidence(lang, rc, tail)
            if not ev:
                return {"status": "not-run", "reason": "the run failed without a failing test (%s): not proof" % (infra_reason(tail) or "rc %s" % rc), "failure_line": "",
                        "ms": ms, "tail": re.sub(r"\s+", " ", tail[-400:])}
            return {"status": "proven-red", "reason": ev, "failure_line": fl, "ms": ms}
    except Exception as ex:  # noqa: BLE001
        return {"status": "not-run", "reason": "red-proof error: %s" % type(ex).__name__, "failure_line": "", "ms": int((time.time() - t0) * 1000)}
    finally:
        for l in linked:
            try:
                os.unlink(l)
            except OSError:
                pass
        if home:
            shutil.rmtree(home, ignore_errors=True)


def _run_plain(cmd, cwd, env, timeout):
    """bash -c in its own process group with a hard timeout; real HOME / gradle cache stay (gradle and godot need them). -> (rc, output, ms)"""
    import qa_common as qc
    t0 = time.time()
    p = subprocess.Popen(qc.cpu_prefix() + ["bash", "-c", cmd], cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        out, _ = p.communicate()
        rc = 124
    return rc, (out or b"")[-30000:].decode("utf-8", "replace"), int((time.time() - t0) * 1000)


# ----------------------------------------------------------------------------------------------------------------------
# (4) EMIT: queue items
# ----------------------------------------------------------------------------------------------------------------------
def feat_tag(repo, date, note_or_text):
    h = hashlib.sha256(("%s|%s|%s" % (repo, date, re.sub(r"\s+", " ", note_or_text or "").lower())).encode("utf-8")).hexdigest()[:8]
    return "%s-%s-manual-%s" % (repo, (date or time.strftime("%F")).replace("-", ""), h)


def _ev_text(e):
    return "%s:%d '%s'" % (e["file"], e["line"], clean_text(e["quote"], 110))


def emit_items(brief, feat, flow="other", date="", red=None):
    """-> [queue lines]. One line per landing unit, in order, sharing ONE [feat:<tag>]. The test_first step is FUSED with the first fix step (a red
    test cannot land alone); every line carries the 'Manual-test bug (reported by Mark' phrase and (cat:bugfix; ...; src:manual; brief:i/K)."""
    steps = brief["steps"]
    if any(lang_of(x.get("file", "")) == "gd" for x in steps):
        return _emit_items_gd(brief, feat, flow, date, red)
    units = []
    i = 0
    while i < len(steps):
        s = steps[i]
        if s["kind"] == "test_first" and i + 1 < len(steps) and steps[i + 1]["kind"] == "fix":
            units.append(("fused", s, steps[i + 1]))
            i += 2
        else:
            units.append((s["kind"], s, None))
            i += 1
    K = len(units)
    rc = brief["root_cause"]
    lead = "Manual-test bug (reported by Mark, flow %s, %s)" % (_safe_token(flow) or "other", date or time.strftime("%F"))
    lines = []
    for n, (kind, a, b) in enumerate(units, 1):
        mark = "%s [brief step %d of %d]" % (lead, n, K)
        if kind == "fused":
            fix, test = b, a
            rp_txt = ""
            if red and red.get("status") == "proven-red":
                rp_txt = " Harness-verified: on today's code this test FAILS (%s)." % clean_text(red.get("failure_line") or red.get("reason", ""), 150)
            elif red and red.get("status") in ("not-run", "invalid", "skipped"):
                rp_txt = " (The test-first step was not executed by the harness: %s.)" % clean_text(red.get("reason", ""), 100)
            body = ("%s TEST-FIRST then FIX, land both in this one step (a red test alone cannot land). ROOT-CAUSE HYPOTHESIS (the quoted lines are verified to exist, "
                    "the diagnosis is not proven): %s EVIDENCE: %s. "
                    "(A) NEW test file %s (NEW): %s%s (B) Then in %s, function %s: %s If the cause is not where the evidence points, say so."
                    % (mark, clip_sentence(rc["hypothesis"], 560), "; ".join(_ev_text(e) for e in rc["evidence"][:3]), test["file"],
                       clip_sentence(test["change"], 380), rp_txt, fix["file"], clean_text(fix["function"], 80), clip_sentence(fix["change"], 400)))
            path, also, verify, multi = fix["file"], [test["file"]], fix["verify"], "yes"
        elif kind == "fix":
            body = ("%s FIX in function %s: %s Hypothesis (see step 1): %s" % (mark, clean_text(a["function"], 80), clip_sentence(a["change"], 400),
                                                                             clip_sentence(rc["hypothesis"], 200)))
            path, also, verify, multi = a["file"], [], a["verify"], "no"
        elif kind == "guard":
            body = ("%s REGRESSION GUARD, add only after the fix steps landed: %s (NEW test, function %s)." % (mark, clip_sentence(a["change"], 400),
                                                                                                                clean_text(a["function"], 80)))
            path, also, verify, multi = a["file"], [], a["verify"], "no"
        else:                      # a standalone test_first (not followed by a fix): cannot land red; kept only for completeness
            body = "%s TEST: %s" % (mark, clip_sentence(a["change"], 400))
            path, also, verify, multi = a["file"], [], a["verify"], "no"
        also_txt = (" Also look at: %s." % ", ".join(also)) if also else ""
        line = "- [ ] [%s] %s — %s%s VERIFY: `%s`. (cat:bugfix; multifile:%s; src:manual; %s:%d/%d) [feat:%s]" % (
            ITEM_TIER, path, body, also_txt, verify.replace("`", "'"), multi, ANNOT, n, K, feat)
        lines.append(line)
    return lines


# 2026-10-02: what ovn_stage_runner.sh's _doable filter drops (a line naming a tests/*.gd or test_*.gd file) - kept in step with that grep.
GD_TEST_REF = re.compile(r"\btests?/[A-Za-z0-9_./-]*\.gd\b|\btest_[A-Za-z0-9_]*\.gd\b")


def _no_gd_test_refs(text):
    return GD_TEST_REF.sub("the existing GUT tests", text or "")


def _emit_items_gd(brief, feat, flow="other", date="", red=None):
    """GDScript: SOURCE-ONLY fix items. 2026-10-02 FIX (review): ovn_stage_runner.sh never picks a line naming a tests/*.gd file and its GODOT MODE
    decompose rules forbid creating/modifying GUT files (the 27B cannot author GUT tests), so the fused test-first item and the guard item of a
    gd brief could never land. Only the fix steps are emitted, each verified by `gdparse <file>` (the stage runner's mandatory Godot verify) and
    free of any test-file path; the full GUT suite is run by the runner's own gate. A proven-red reference test stays in state/bug_briefs/<feat>.json
    for harness-side application."""
    fixes = [s for s in brief["steps"] if s["kind"] == "fix"]
    K = len(fixes)
    rc = brief["root_cause"]
    lead = "Manual-test bug (reported by Mark, flow %s, %s)" % (_safe_token(flow) or "other", date or time.strftime("%F"))
    rp_txt = ""
    if red and red.get("status") == "proven-red":
        rp_txt = " A harness-held test fails on today's code (%s)." % clean_text(red.get("failure_line") or red.get("reason", ""), 150)
    lines = []
    for n, a in enumerate(fixes, 1):
        mark = "%s [brief step %d of %d]" % (lead, n, K)
        body = ("%s FIX (source only, do NOT create or edit any test file) in function %s: %s ROOT-CAUSE HYPOTHESIS (the quoted lines are verified to exist, "
                "the diagnosis is not proven): %s EVIDENCE: %s.%s If the cause is not where the evidence points, say so."
                % (mark, clean_text(a["function"], 80), clip_sentence(a["change"], 400), clip_sentence(rc["hypothesis"], 400),
                   "; ".join(_ev_text(e) for e in rc["evidence"][:3]), rp_txt))
        body = _no_gd_test_refs(body)
        line = "- [ ] [%s] %s — %s VERIFY: `gdparse %s`. (cat:bugfix; multifile:no; src:manual; %s:%d/%d) [feat:%s]" % (
            ITEM_TIER, a["file"], body, a["file"], ANNOT, n, K, feat)
        lines.append(line)
    return lines


def check_items_parse(lines, feat):
    """Every emitted line must parse the way the pipeline parses items (card_lint.parse_item_line) and keep the marker phrase + feat tag."""
    bad = []
    for ln in lines:
        it = cl.parse_item_line(ln)
        if not it or not it.get("path") or not it.get("verify"):
            bad.append("does not parse as a queue item: %s" % ln[:80])
        if "Manual-test bug (reported by Mark" not in ln or ("[feat:%s]" % feat) not in ln or ln.count("VERIFY:") != 1:
            bad.append("marker / feat tag / single VERIFY missing: %s" % ln[:80])
        if re.search(r"AUTO-SKIP|HUMAN-ONLY|HARD FILE BAN|(?-i:BLOCKED)|\[CLAUDE\]", ln, re.I):
            bad.append("contains a parked-item keyword: %s" % ln[:80])
        if "\n" in ln:
            bad.append("multi-line item")
        if GD_TEST_REF.search(ln):
            bad.append("an item names a GDScript test file (the stage runner would never pick it): %s" % ln[:80])
    return bad


# ----------------------------------------------------------------------------------------------------------------------
# progress-file edit (pure) - the caller applies it atomically through manual_notes_ingest.edit_progress
# ----------------------------------------------------------------------------------------------------------------------
_PARKED = re.compile(r"AUTO-SKIP|HUMAN-ONLY|human/|\[CLAUDE\]|(?-i:BLOCKED)|\(retired-|\[unworkable", re.I)


def apply_to_text(text, feat, lines, insert_if_missing=False):
    """Replace the single open item tagged [feat:<feat>] by `lines` (same position). Idempotent. -> (new_text|None, why).
    why: replaced | inserted | already-briefed | skip: <reason> (the file is returned unchanged)."""
    tag = "[feat:%s]" % feat
    src = text.split("\n")
    idx = [i for i, l in enumerate(src) if tag in l and l.lstrip().startswith("- [")]
    if any(re.search(r"\b%s:\d+/\d+\)" % ANNOT, src[i]) for i in idx):
        return text, "already-briefed"
    if not idx:
        if not insert_if_missing:
            return text, "skip: the item is no longer in the queue (done, retired or removed)"
        for i, l in enumerate(src):
            if re.match(r"^## Next Steps\s*$", l):
                return "\n".join(src[:i + 1] + lines + src[i + 1:]), "inserted"
        return None, "no '## Next Steps' section"
    single = [i for i in idx if src[i].lstrip().startswith("- [ ]") and not _PARKED.search(src[i])]
    if not single:
        return text, "skip: the single item is already done or parked"
    i = single[0]
    return "\n".join(src[:i] + lines + src[i + 1:]), "replaced"


# ----------------------------------------------------------------------------------------------------------------------
# the stage
# ----------------------------------------------------------------------------------------------------------------------
def _fallback(why, **extra):
    d = {"status": "fallback", "why": why, "items": [], "brief": None, "calls": extra.pop("calls", 0)}
    d.update(extra)
    log("fallback to the single item: %s" % why)
    return d


def make_brief(rp, ref, note, flow, primary, also=None, platform=None, model_fn=None, exec_red=None, repo_name="", feat="", date="",
               deadline_s=None, allowed_edit=None):
    """Research + plan + validate (+ red proof) + emit for ONE bug. NEVER raises. -> {status: ok|fallback, why, brief, items, calls, red_proof,
    research: {...}, attempts: [...]}. `model_fn(prompt, timeout=, max_tokens=) -> text|None`; default = the local litellm."""
    t0 = time.time()
    try:
        return _make_brief(rp, ref, note, flow, primary, also or [], platform, model_fn, exec_red, repo_name or os.path.basename(rp.rstrip("/")),
                           feat, date, deadline_s, allowed_edit)
    except Exception as ex:  # noqa: BLE001
        return _fallback("bug_brief error: %s: %s" % (type(ex).__name__, str(ex)[:120]), seconds=round(time.time() - t0, 1))


_UI_FILE = re.compile(r"(Screen|Activity|Fragment|Page|Composable|Dialog|View|Component|Cell|Row|Sheet)\.(kt|java|vue|tsx|jsx|swift)$")
_LOGIC_FILE = re.compile(r"(ViewModel|Presenter|Controller|Service|Repository|Manager|Store|UseCase|Reducer)\.(kt|java|ts|js|py|gd)$|/(stores?|services?|viewmodels?)/[^/]+\.(ts|js)$")


def pick_anchor(primary, also):
    """-> (anchor, others). A screen / composable / view cannot be unit-tested the way its view model / service / store can, so when the located primary
    is a UI file and an 'also look at' file is its testable logic (same platform, not a test), the logic file anchors the research and the test plan
    (the evidence still includes the UI file). Otherwise the primary stays."""
    if _UI_FILE.search(primary) and not _LOGIC_FILE.search(primary):
        for a in also:
            if a != primary and _LOGIC_FILE.search(a) and not _is_test_path(a) and lang_of(a) == lang_of(primary):
                return a, [primary] + [x for x in also if x not in (a, primary)]
    return primary, [x for x in also if x != primary]


def _make_brief(rp, ref, note, flow, primary, also, platform, model_fn, exec_red, repo_name, feat, date, deadline_s, allowed_edit):
    t0 = time.time()
    rpo = Repo(rp, ref)
    primary, also = pick_anchor(primary, also) if primary else (primary, also)
    if not primary or not rpo.exists(primary):
        return _fallback("the located file %s does not exist at %s" % (primary, ref))
    lang = lang_of(primary)
    if lang not in LANGS:
        return _fallback("language of %s is not handled (Kotlin / GDScript / Python / TypeScript only)" % primary)
    bad = unworkable_why(rpo, primary)
    if bad:
        return _fallback("the located file is unworkable: %s (a brief cannot route around a ban; the item parks as before)" % bad)
    if model_fn is None and ml.model_name() in ("", "off", "none"):
        return _fallback("model is off (OVN_MANUAL_MODEL)")
    layout = ml.detect_layout(rpo.files())
    prod = [f for f in rpo.files() if ml.is_product_path(f)]
    if allowed_edit is None:
        plat = ml.plat_of(primary, layout) if layout else None
        if layout and plat:
            _prim, allowed_edit = ml.candidates_for_platform(prod, layout, plat)
        else:
            allowed_edit = None
    r = research(rpo, note, flow, primary, also, prim_files=allowed_edit)
    if not r["files"] or not any(f["funcs"] or f.get("window") for f in r["files"]):
        return _fallback("research found no code evidence in %s" % primary)
    if not r["plan"]:
        return _fallback("no test convention found for %s (no test directory / runner to put a repro test in)" % lang)
    budget = Budget(model_fn or _chat, deadline_s=deadline_s)
    do_exec = exec_policy(lang) if exec_red is None else bool(exec_red)
    max_plan_calls = 2 if do_exec else 3
    out = {"status": "fallback", "why": "", "brief": None, "items": [], "calls": 0, "red_proof": None, "attempts": [],
           "research": {"files": [f["path"] for f in r["files"]], "functions": [fn["name"] for f in r["files"] for fn in f["funcs"]],
                        "callers": len(r["callers"]), "tests": r["tests"], "test_plan": r["plan"], "chars": len(render_research(r)), "terms": r["terms"]}}
    errors, prev, nb, vres = None, None, None, None
    plan_calls = 0
    while plan_calls < max_plan_calls:
        txt = budget(build_plan_prompt(repo_name, platform, note, flow, r, errors, prev, repair_hints(rpo, errors)), max_tokens=2000)
        plan_calls += 1
        if txt is None:
            out["why"] = "model dead / slow / refused (%s)" % ("circuit breaker open" if budget.dead else "no budget left")
            out["calls"] = budget.calls
            return _fallback(out["why"], calls=budget.calls, research=out["research"], attempts=out["attempts"])
        d = parse_brief_json(txt)
        if not d:
            errors, prev = ["the reply was not a single JSON object"], None
            out["attempts"].append({"call": budget.calls, "errors": errors, "reply_head": txt[:300]})
            continue
        vres = validate_brief(d, rpo, r, allowed_edit=allowed_edit, repo_root=None, note=note)
        out["attempts"].append({"call": budget.calls, "errors": vres["errors"][:12], "ok": vres["ok"], "reply_head": txt[:300]})
        if vres["ok"]:
            nb = vres["brief"]
            break
        errors, prev = vres["errors"], json.dumps(d, ensure_ascii=False)
    if nb is None:
        return _fallback("the plan failed validation after %d attempt(s): %s" % (plan_calls, "; ".join((errors or ["?"])[:3])), calls=budget.calls,
                         research=out["research"], attempts=out["attempts"])
    nb.update({"repo": repo_name, "platform": platform or "", "note": note, "flow": flow, "date": date})
    # ---- red proof of the test-first step
    red = {"status": "skipped", "reason": "execution of the test-first step is off for %s (OVN_BUG_BRIEF_EXEC)" % lang, "failure_line": ""}
    code = None
    if do_exec:
        code, prev_code, err, vac = None, None, None, False
        for attempt in (1, 2):
            txt = budget(build_test_prompt(repo_name, note, nb, r, err, prev_code, vac), max_tokens=1800)
            if txt is None:
                red = {"status": "not-run", "reason": "model unavailable for the test author call", "failure_line": ""}
                break
            code = extract_code(txt)
            if not code:
                err, prev_code, vac = "the reply had no usable code block", None, False
                red = {"status": "invalid", "reason": "the test author returned no usable code", "failure_line": ""}
                continue
            red = red_proof(rp, ref, repo_name, r["plan"], code, lang)
            if red["status"] in ("proven-red", "not-run"):
                break
            if red["status"] == "vacuous" and attempt == 1:
                err, prev_code, vac = None, code, True
                continue
            if red["status"] == "invalid" and attempt == 1:
                err, prev_code, vac = red.get("reason", "") + " :: " + red.get("tail", ""), code, False
                continue
            break
        if red["status"] == "vacuous":
            out["red_proof"] = red
            return _fallback("the test-first step is VACUOUS: its test passes on the current code (%s)" % red["reason"], calls=budget.calls,
                             research=out["research"], attempts=out["attempts"], red_proof=red, brief=nb)
        if red["status"] == "proven-red":
            nb["steps"][0]["reference_test"] = code
            nb["steps"][0]["red_proof"] = {"failure_line": red.get("failure_line", ""), "reason": red.get("reason", "")}
    out["red_proof"] = red
    nb["red_proof"] = {"status": red["status"], "reason": red.get("reason", ""), "failure_line": red.get("failure_line", "")}
    feat = feat or feat_tag(repo_name, date, note)
    nb["feat"] = feat
    items = emit_items(nb, feat, flow, date, red)
    bad = check_items_parse(items, feat)
    if bad:
        return _fallback("emitted items do not parse as queue items: %s" % bad[0], calls=budget.calls, research=out["research"], attempts=out["attempts"])
    out.update({"status": "ok", "why": "", "brief": nb, "items": items, "calls": budget.calls, "feat": feat, "seconds": round(time.time() - t0, 1),
                "warnings": (vres or {}).get("warnings", [])})
    return out


def import_brief(path_or_obj, rp, ref, repo_name="", feat="", flow="", date="", platform="", allowed_edit=None, exec_red=False):
    """Validate + emit a brief authored by Claude / a human (same schema, same mechanical checks; no model call, no red proof unless exec_red and the
    brief carries a reference_test on step 1). -> same shape as make_brief."""
    try:
        if isinstance(path_or_obj, dict):
            b = path_or_obj
        else:
            with open(path_or_obj, encoding="utf-8") as fh:
                b = json.load(fh)
    except (OSError, ValueError) as ex:
        return _fallback("cannot read the brief: %s" % ex)
    rpo = Repo(rp, ref)
    repo_name = repo_name or b.get("repo") or os.path.basename(rp.rstrip("/"))
    flow = flow or b.get("flow") or "other"
    date = date or b.get("date") or time.strftime("%F")
    feat = feat or b.get("feat") or feat_tag(repo_name, date, b.get("note") or (b.get("root_cause") or {}).get("hypothesis", ""))
    if not re.fullmatch(r"[A-Za-z0-9._-]{3,120}", feat):
        return _fallback("the feat tag %r is not a clean tag" % feat[:40])
    # a human / Claude brief may put its test-first file anywhere in a test dir, so no expected path is imposed (r=None)
    v = validate_brief(b, rpo, None, allowed_edit=allowed_edit)
    if not v["ok"]:
        return _fallback("the brief failed validation: %s" % "; ".join(v["errors"][:6]), errors=v["errors"])
    nb = v["brief"]
    nb.update({"repo": repo_name, "feat": feat, "flow": flow, "date": date})
    if platform:
        nb["platform"] = platform
    red = {"status": "skipped", "reason": "imported brief: the test-first step was not executed by the harness", "failure_line": ""}
    ref_code = b["steps"][0].get("reference_test") if isinstance(b.get("steps"), list) and b["steps"] and isinstance(b["steps"][0], dict) else None
    if exec_red and isinstance(ref_code, str) and ref_code.strip():
        s1 = nb["steps"][0]
        lg = lang_of(s1["file"])
        plan = {"path": s1["file"], "verify": s1["verify"], "root": "", "class": os.path.splitext(os.path.basename(s1["file"]))[0]}
        red = red_proof(rp, ref, repo_name, plan, ref_code, lg)
        if red["status"] == "vacuous":
            return _fallback("the imported test-first step is VACUOUS: %s" % red["reason"], red_proof=red, brief=nb)
        if red["status"] == "proven-red":
            nb["steps"][0]["reference_test"] = ref_code
    nb["red_proof"] = {"status": red["status"], "reason": red.get("reason", ""), "failure_line": red.get("failure_line", "")}
    items = emit_items(nb, feat, flow, date, red)
    bad = check_items_parse(items, feat)
    if bad:
        return _fallback("emitted items do not parse as queue items: %s" % bad[0])
    return {"status": "ok", "why": "", "brief": nb, "items": items, "calls": 0, "feat": feat, "red_proof": red, "warnings": v["warnings"], "source": "import"}


# ----------------------------------------------------------------------------------------------------------------------
# state record
# ----------------------------------------------------------------------------------------------------------------------
def save_brief_record(feat, result, ovn_dir=None):
    """state/bug_briefs/<feat>.json (atomic). Best effort: never raises."""
    try:
        d = os.path.join(ovn_dir or os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue"), "state", "bug_briefs")
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".brief.", dir=d)
        with os.fdopen(fd, "w") as fh:
            json.dump(result, fh, indent=1, sort_keys=True, ensure_ascii=False)
        os.replace(tmp, os.path.join(d, re.sub(r"[^A-Za-z0-9._-]", "_", feat) + ".json"))
        return True
    except Exception:  # noqa: BLE001
        return False


# ----------------------------------------------------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------------------------------------------------
def _resolve_repo(args):
    rp = args.repo_path
    if not rp:
        try:
            import manual_notes_ingest as mn
            rp = mn.repo_path(args.repo)
        except Exception:  # noqa: BLE001
            rp = None
    if not rp or not os.path.exists(os.path.join(rp, ".git")):
        print("ERROR: no clone for repo %r (give --repo-path)" % args.repo)
        return None, None
    ref = args.ref
    if not ref:
        for cand in ("origin/overnight/feature", "origin/develop", "HEAD"):
            rc, _ = ml._git(rp, ["rev-parse", "--verify", "-q", cand + "^{commit}"])
            if rc == 0:
                ref = cand
                break
    return rp, ref


def _print_result(res, as_json=False):
    if as_json:
        print(json.dumps(res, indent=1, ensure_ascii=False, sort_keys=True))
        return
    print("STATUS: %s%s   model calls: %s" % (res["status"], ("  (%s)" % res["why"]) if res.get("why") else "", res.get("calls", 0)))
    if res.get("red_proof"):
        print("RED PROOF: %s %s %s" % (res["red_proof"]["status"], res["red_proof"].get("reason", ""), res["red_proof"].get("failure_line", "")))
    for a in res.get("attempts") or []:
        print("  plan attempt (call %s): %s" % (a.get("call"), "valid" if a.get("ok") else "; ".join(a.get("errors", [])[:4])))
    for ln in res.get("items", []):
        print(ln)


def _already_briefed(args, rp, ref, feat):
    """Idempotency BEFORE any model call: does the target (local progress file, or origin's OVERNIGHT_PROGRESS.md) already carry brief:i/K items for feat?"""
    try:
        if args.progress_file:
            text = open(args.progress_file, encoding="utf-8").read()
        else:
            text = Repo(rp, ref).text("OVERNIGHT_PROGRESS.md") or ""
        return apply_to_text(text, feat, [], insert_if_missing=False)[1] == "already-briefed"
    except Exception:  # noqa: BLE001
        return False


def _apply(args, res, rp):
    """Apply to a local progress file (--progress-file, tests / trials) or to the live clone through the ingest's atomic edit (--apply)."""
    if res["status"] != "ok":
        return 0
    feat = res["feat"]
    if args.progress_file:
        with open(args.progress_file, encoding="utf-8") as fh:
            text = fh.read()
        new, why = apply_to_text(text, feat, res["items"], insert_if_missing=args.insert)
        if new is not None and new != text:
            with open(args.progress_file, "w", encoding="utf-8") as fh:
                fh.write(new)
        print("APPLY(progress-file): %s" % why)
        return 0
    if args.apply:
        import manual_notes_ingest as mn
        with mn.StateLock():
            ok, msg = mn.edit_progress(args.repo, rp, lambda t: apply_to_text(t, feat, res["items"], insert_if_missing=args.insert),
                                       "chore(queue): decompose manual-test bug into a test-first brief (%s)" % feat)
        print("APPLY(live clone): %s %s" % ("ok" if ok else "FAILED", msg))
        return 0 if ok else 1
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("brief", "import-brief"):
        p = sub.add_parser(name)
        p.add_argument("--repo", required=(name == "brief"), default="")
        p.add_argument("--repo-path", default="", help="a git clone to READ (default: the ingest's repos/<repo>)")
        p.add_argument("--ref", default="", help="git ref to read (default origin/overnight/feature)")
        p.add_argument("--flow", default="other")
        p.add_argument("--date", default="")
        p.add_argument("--platform", default="")
        p.add_argument("--feat", default="", help="the [feat:] tag (default: derived from repo/date/note)")
        p.add_argument("--progress-file", default="", help="apply to this OVERNIGHT_PROGRESS.md (a local file) instead of printing only")
        p.add_argument("--apply", action="store_true", help="apply to the LIVE clone through the ingest's atomic edit (hold/reset/edit/commit/push/release)")
        p.add_argument("--insert", action="store_true", help="if the single item is not in the queue, insert the items at the top of Next Steps")
        p.add_argument("--json", action="store_true")
        p.add_argument("--out", default="", help="write the full result JSON here")
        if name == "brief":
            p.add_argument("--note", required=True)
            p.add_argument("--path", default="", help="the located primary file (default: run the locator)")
            p.add_argument("--also", action="append", default=[])
            p.add_argument("--exec", dest="exec_red", choices=("auto", "on", "off"), default="auto")
        else:
            p.add_argument("file")
            p.add_argument("--exec", dest="exec_red", choices=("on", "off"), default="off")
    args = ap.parse_args(argv)
    if not enabled():
        print("STATUS: fallback  (OVN_BUG_BRIEF=off)")
        return 0
    rp, ref = _resolve_repo(args)
    if not rp:
        return 2
    if args.cmd == "import-brief":
        res = import_brief(args.file, rp, ref, repo_name=args.repo, feat=args.feat, flow=args.flow if args.flow != "other" else "", date=args.date,
                           platform=args.platform, exec_red=(args.exec_red == "on"))
    else:
        primary, also = args.path, list(args.also)
        feat = args.feat or feat_tag(args.repo, args.date or time.strftime("%F"), mn_clean(args.note))
        args.feat = feat
        if (args.progress_file or args.apply) and _already_briefed(args, rp, ref, feat):
            print("STATUS: skipped  (already briefed: the queue already holds the brief items for [feat:%s]; no model call)" % feat)
            return 0
        if not primary:
            import manual_notes_ingest as mn
            loc = mn.locate_v2(rp, ref, mn.clean_for_locator(args.note), args.flow, platform=args.platform or None, use_model=True, repo_name=args.repo)
            good = [c for c in loc["candidates"] if c.get("located")]
            if not good:
                print("STATUS: fallback  (the locator found no file: needs-triage)")
                return 0
            primary, also = good[0]["path"], loc.get("also", [])
        res = make_brief(rp, ref, mn_clean(args.note), args.flow, primary, also, args.platform or None, repo_name=args.repo, feat=args.feat,
                         date=args.date or time.strftime("%F"), exec_red={"auto": None, "on": True, "off": False}[args.exec_red])
    _print_result(res, args.json)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(res, fh, indent=1, sort_keys=True, ensure_ascii=False)
    return _apply(args, res, rp)


def mn_clean(note):
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", note or "")).strip()[:400]


if __name__ == "__main__":
    sys.exit(main())
