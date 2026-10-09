#!/usr/bin/env python3
"""scripts/ovn_spec_rules.py - rule set for backlog item lines (spec-compiler-v2 part C2, 2026-10-09).

  lint_item(line, ctx)    -> (line2, [Finding])
  lint_batch(lines, ctx)  -> [(line2, [Finding]), ...]   same order as `lines`; batch rules (R06 reorder, R07) see the other lines
  lint_static(line, only) -> (line2, [Finding])           R01-R03 only, no ctx (the `ovn_spec_gate.py lint` filter and queue_refill's repairs)

Finding = {"rule": "R0x", "sev": "repair" | "reject" | "flag", "msg": str, "evidence": str|list|dict}
  repair  the line was rewritten (line2 differs)        reject  the item can never land: quarantine        flag  report (or hold, R06)

  R01 repair  bare `VERIFY: <cmd> (cat:` -> backticked, when <cmd> starts with grep|test|ls|python|pytest|cd|godot|npm|npx|./gradlew, its quotes balance and it
              carries no prose word (passes/should/...); a trailing sentence period glued to the last token is dropped
  R02 repair  vacuous echo idiom `cmd && echo FAIL || echo PASS` (always exit 0) -> `! ( cmd )` / `cmd`   (ovn_backlog_eligibility.normalize_vacuous_echo)
  R03 repair  backticked grep/test/ls/cat/stat cmd whose WHOLE following sentence is exactly a whitelisted post-change verdict ([which|it] [must] fails [with "No such file or
              directory"] | returns non-zero [exit code] | no matches | No such file [or directory], optionally 'after the change/fix') -> `! cmd`; any other wording
              (old/current/today/initially/when/because/before/if/passes ...) leaves the line untouched and emits an R03 'flag' finding for human review
  R04 reject  TARGET path (text before the first ' - ') is vendored (addons/) or matches .queue-hard-banned-files at the ref
  R05 flag    non-actionable: leading Verify/Ensure/Check/Confirm/Run/Review with no change verb, an 'If ... delete' conditional, 'manual inspection',
              or a prose VERIFY that cannot be run
  R06 flag    Delete/Remove of `func X` / `X()` in file F while `git grep -nw X` finds references in files other than F that no EARLIER Remove/Delete item of the
              same [feat] batch removes. Replay: the 10-09 enemy_faction_map batch (delete get_faction, delete get_all_factions, THEN remove the tests that call
              them) produced 10 remove/restore commits in 8 minutes. Batch time: the finding names the reorder; queue time (queue_refill): HOLD.
  R07 flag    one (file, symbol) is added by one open item and deleted by another
  R08 flag    a modify-verb item names a backticked `sym(` / identifier that the (non-test) target file does not define and no item verb creates (e.g. 'scores' in
              recompute_representative, which has no score input); builtins and the repo's own module names are not flagged
  R10 reject  model-written "send N requests and assert 429" test items; the deterministic rate-limit collector (ovn_work_supply, supply:rate-limit; limiter.enabled
              + reset fixture) is the only sanctioned form and is never flagged

Every repository read goes through Ctx and happens AT THE REF (default origin/overnight/feature), never the working tree.
"""
import ast
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_backlog_eligibility import (  # noqa: E402
    extract_verify, item_target, is_open_item, normalize_vacuous_echo)
from ovn_spec_classify import clean_bare_verify  # noqa: E402

ITEM_RE = re.compile(r"^- \[ \] \[(T[1-5])\]\s+(?P<target>.+?)\s+—\s+(?P<body>.*)$")
FEAT_RE = re.compile(r"\[feat:([^\]]+)\]")
R01_CMDS = re.compile(r"^(grep|test|ls|python3?|pytest|cd|godot|npm|npx|\./gradlew)\b")
PROSE_WORDS = {"passes", "pass", "succeeds", "should", "must", "returns", "exits", "fails", "works", "verifies", "ensure", "ensures", "is", "are", "with", "then"}
CHANGE_WORDS = re.compile(r"\b(add|create|remove|delete|modify|update|replace|rename|fix|implement|write|change|extract|move|wire|define|introduce|refactor|convert|drop|set|make|use|call|return|raise|handle|guard|split|merge|inline|reorder|wrap)\b", re.I)
LEAD_VERIFY_VERBS = {"verify", "ensure", "check", "confirm", "run", "review"}
DELETE_V = {"delete", "remove", "drop"}
ADD_V = {"add", "create", "implement", "define", "introduce", "write"}
MODIFY_V = {"modify", "update", "change", "fix", "extend", "refactor", "rename", "replace", "adjust", "use", "wire", "rework", "make", "set", "route"}
STOP_IDENT = {"none", "true", "false", "self", "cls", "list", "dict", "str", "int", "float", "bool", "bytes", "tuple", "set", "type", "object", "test", "tests",
              "null", "void", "return", "async", "await", "print", "len", "range", "super", "args", "kwargs", "data", "name", "value", "result", "error", "path"}


def finding(rule, sev, msg, evidence=""):
    return {"rule": rule, "sev": sev, "msg": msg, "evidence": evidence}


def parse(line):
    """{'tier','target','body','verify_raw','feat'} of an open item line, or None."""
    m = ITEM_RE.match(line.strip())
    if not m:
        return None
    body = m.group("body")
    text = re.split(r"\sVERIFY:", body, maxsplit=1)[0]
    fm = FEAT_RE.search(line)
    return {"tier": m.group(1), "target": m.group("target").strip().strip("`"), "text": text.strip(), "feat": fm.group(1) if fm else None}


def _lead_verb(text):
    m = re.match(r"\W*([A-Za-z]+)", text)
    return m.group(1).lower() if m else ""


# ---------------------------------------------------------------- repo context at a ref
class Ctx:
    """Reads a repository at a ref only. tree(), refs(sym) and show(path) are cached; every failure degrades to empty (rules then say nothing)."""

    EXCLUDES = (":!addons", ":!OVERNIGHT_*", ":!docs", ":!*.md")

    def __init__(self, repo_dir, ref="origin/overnight/feature", banned=None):
        self.repo_dir, self.ref = repo_dir, ref
        self._tree = None
        self._show = {}
        self._refs = {}
        self._banned = banned
        self.git_calls = 0

    def _git(self, *args, timeout=30):
        self.git_calls += 1
        try:
            return subprocess.run(["git", "-C", self.repo_dir] + list(args), capture_output=True, text=True, errors="replace", timeout=timeout)
        except (OSError, subprocess.SubprocessError):
            return None

    def tree(self):
        if self._tree is None:
            r = self._git("ls-tree", "-r", "--name-only", self.ref)
            self._tree = set(r.stdout.split("\n")) - {""} if r is not None and r.returncode == 0 else set()
        return self._tree

    def show(self, path):
        if path not in self._show:
            r = self._git("show", "%s:%s" % (self.ref, path))
            self._show[path] = r.stdout if r is not None and r.returncode == 0 else None
        return self._show[path]

    def refs(self, sym):
        """[(path, lineno, text)] of whole-word, fixed-string hits of `sym` at the ref, outside addons/, OVERNIGHT_*, docs/ and *.md (scene/resource files included)."""
        if sym not in self._refs:
            r = self._git("grep", "-nw", "-F", "-e", sym, self.ref, "--", ".", *self.EXCLUDES)
            out = []
            if r is not None and r.returncode == 0:
                pre = self.ref + ":"
                for l in r.stdout.split("\n"):
                    if not l.startswith(pre):
                        continue
                    parts = l[len(pre):].split(":", 2)
                    if len(parts) == 3 and parts[1].isdigit():
                        out.append((parts[0], int(parts[1]), parts[2]))
            self._refs[sym] = out
        return self._refs[sym]

    def banned(self):
        if self._banned is None:
            self._banned = []
            txt = self.show(".queue-hard-banned-files") or ""
            for raw in txt.split("\n"):
                p = raw.strip()
                if p and not p.startswith("#"):
                    try:
                        self._banned.append(re.compile(p))
                    except re.error:
                        pass
        return self._banned


# ---------------------------------------------------------------- static repairs R01-R03
def _balanced(cmd):
    try:
        shlex.split(cmd)
        return True
    except ValueError:
        return False


def _r01(line):
    """bare `VERIFY: cmd (cat:` -> `VERIFY: \\`cmd\\` (cat:`"""
    if re.search(r"VERIFY:\s*`", line):
        return line, None
    m = re.search(r"VERIFY:\s*(.+?)(\s*\(cat:)", line)
    if not m:
        return line, None
    cmd = clean_bare_verify(m.group(1))
    if not R01_CMDS.match(cmd) or "`" in cmd or not _balanced(cmd):
        return line, None
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return line, None
    if any(t.lower() in PROSE_WORDS for t in toks[1:]):
        return line, None
    new = line[:m.start()] + "VERIFY: `%s`" % cmd + m.group(2) + line[m.end():]
    return new, finding("R01", "repair", "bare VERIFY clause backticked", cmd)


def _r02(line):
    new, n = normalize_vacuous_echo(line)
    if not n:
        return line, None
    return new, finding("R02", "repair", "vacuous echo idiom (always exit 0) replaced by a real exit code", extract_verify(line))


_R03_PHRASE = re.compile(r"fails?|returns?\s+(?:a\s+)?non-?zero|no matches|No such file", re.I)
# R03 (a narrated failure becomes `! cmd`) is a WHITELIST, never a blacklist. The sentence that follows the backticked command (up to the first period, a `(cat:`, a
# ` [feat:` tag or an HTML comment) must be EXACTLY the verdict of the command as it stands after the change - an optional lead-in ("which", "it now must"), the verdict
# (fails / returns non-zero [exit code] / no matches / No such file [or directory]) and an optional "after the change/fix" - and nothing else. Any other word (a temporal or
# conditional qualifier: old / current / today / initially / until / when / because / before / if / passes / "(expected: red)" ...) means the narration is not provably the
# post-change verdict, so the line is left UNTOUCHED and an R03 "flag" finding is emitted for human review. Never invert on ambiguity.
_R03_NARR = re.compile(
    r"""^\s*[,:\u2014\u2013-]?\s*
        (?:(?:which|it|this|that|command)\s+)?(?:(?:now|then)\s+)?(?:(?:must|should)\s+)?
        (?:fails?(?:\s+with\s+["']?No\s+such\s+file\s+or\s+directory["']?)?
          |returns?\s+(?:a\s+)?non-?zero(?:\s+(?:exit\s+)?(?:code|status))?
          |no\s+matches
          |No\s+such\s+file(?:\s+or\s+directory)?)
        (?:\s+(?:after|once|following)\s+(?:the\s+|this\s+)?(?:change|fix|edit|patch|removal|deletion|rename|refactor)(?:\s+is\s+applied)?)?
        \s*$""", re.I | re.X)
# R03 is only safe for commands whose exit code IS the narrated verdict (grep/test/ls/cat/stat). A test runner (pytest/npm/godot/gradlew) narrating "fails"
# usually means "fails before the change, passes after"; `python -c` narration ("fails with X when Y") is conditional, so it is not in the list either.
_R03_CMDS = {"grep", "egrep", "fgrep", "rg", "test", "[", "ls", "cat", "stat"}


def _r03_cmd_ok(cmd):
    """True when every `&&`/`||`/`;` clause starts with an R03-safe command (cd allowed) and at least one is not just `cd`; a single pipe disqualifies (`! a | b`
    negates b's exit code, not a's)."""
    clauses, cur, q, i = [], "", "", 0           # quote-aware split: a `;` inside `python3 -c "a; b"` is not a clause break
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
            clauses.append(cur)
            cur = ""
            i += 1
        elif ch == ";":
            clauses.append(cur)
            cur = ""
        elif ch == "|":                          # a single pipe: `! a | b` negates b's exit code, not a's
            return False
        else:
            cur += ch
        i += 1
    clauses.append(cur)
    if q:
        return False
    real = 0
    for clause in clauses:
        toks = clause.split()
        if not toks:
            return False
        w = toks[0]
        if w == "cd":
            continue
        if w in _R03_CMDS:
            real += 1
            continue
        return False
    return real > 0


def _r03_sentence(line, end):
    """The narration sentence after the command (line[end:]): cut at `(cat:` / ` [feat:` / `<!--`, then at the first sentence-ending period. The sentence text (may be empty)."""
    rem = line[end:]
    cuts = [i for i in (rem.find("(cat:"), rem.find(" [feat:"), rem.find("<!--")) if i >= 0]
    if cuts:
        rem = rem[:min(cuts)]
    se = re.search(r"\.(?=\s|$)", rem)
    return (rem[:se.start()] if se else rem)


def _r03(line):
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if not m:
        return line, None
    cmd = m.group(1).strip()
    if cmd.startswith("!") or cmd.startswith("test !"):
        return line, None
    if not _r03_cmd_ok(cmd):
        return line, None
    sent = _r03_sentence(line, m.end())
    if not sent.strip():
        return line, None
    if "`" in sent or not _R03_NARR.match(sent):
        if _R03_PHRASE.search(sent):         # narrates a failure in a form we cannot prove is the post-change verdict: flag, never rewrite
            return line, finding("R03", "flag", "VERIFY narrates a failure in a form R03 does not recognise as the post-change verdict: left untouched for human review", sent.strip()[:120])
        return line, None
    neg = "! ( %s )" % cmd if re.search(r"&&|\|\||;", cmd) else "! %s" % cmd
    s = m.start(1) - 1                       # the opening backtick
    e = m.end() + len(sent.rstrip())         # through the narration; the sentence's period (and anything after) stays
    new = line[:s] + "`%s`" % neg + line[e:]
    return new, finding("R03", "repair", "VERIFY narrates that the command fails after the change: negated so the exit code matches", cmd)


STATIC_RULES = (("R01", _r01), ("R02", _r02), ("R03", _r03))


def lint_static(line, only=None):
    fs = []
    for rid, fn in STATIC_RULES:
        if only is not None and rid not in only:
            continue
        line, f = fn(line)
        if f:
            fs.append(f)
    return line, fs


# ---------------------------------------------------------------- symbol helpers
_NOISE_WORDS = {"definition", "definitions", "signature", "signatures", "body", "bodies", "block", "blocks", "declaration", "declarations", "call", "calls", "parameter",
                "parameters", "param", "params", "name", "names", "is", "are", "in", "that", "from", "and", "or", "with", "as", "to", "the", "a", "an", "of", "entirely",
                "completely", "and", "its", "it", "this", "these", "those", "which", "for", "on", "at", "by", "when", "if", "unused", "dead", "obsolete", "old", "stale"}
_KIND_WORDS = r"(?:constant|const|method|function|func|helper|class|variable|member|signal|property|attribute|field)"


def _symbols(text):
    """Symbol names an item text points at, in order of appearance: `func X`/`def X`/`method X` (X not a noise word like 'definition'), backticked `X(`, bare X(),
    and a backticked `X` followed by a kind word (`X` constant / method / function ...)."""
    found = []
    for rx in (r"\b(?:func|function|def|method)\s+`?([A-Za-z_]\w*)", r"`([A-Za-z_]\w*)\s*\(", r"\b([A-Za-z_]\w*)\(\)", r"`([A-Za-z_]\w*)`\s+" + _KIND_WORDS + r"\b"):
        for m in re.finditer(rx, text):
            if m.group(1).lower() not in _NOISE_WORDS:
                found.append((m.start(1), m.group(1)))
    out = []
    for _, sym in sorted(found):
        if sym not in out:
            out.append(sym)
    return out


_NOT_DEF_OBJECT = re.compile(r"^\W*(delete|remove|drop)\s+(?:all\s+|the\s+|any\s+|every\s+|obsolete\s+|stale\s+|broken\s+)*(tests?|test\s+cases?|calls?|call\s+sites?|references?|usages?|callers?|imports?|uses?|assertions?|mocks?|fixtures?)\b", re.I)


_DEL_HEAD = re.compile(r"^\W*(?:delete|remove|drop)\s+(?:(?:the|unused|dead|entire|entirely|obsolete|stale|deprecated|old|legacy|whole|all|both)\s+)*", re.I)
_NON_DEF_NEXT = {"parameter", "parameters", "param", "params", "argument", "arguments", "arg", "args", "field", "fields", "key", "keys", "line", "lines", "import", "imports",
                 "comment", "comments", "docstring", "decorator", "annotation", "annotations", "type", "hint", "default", "branch", "case", "clause", "block", "statement",
                 "call", "calls", "usage", "usages", "reference", "references", "test", "tests", "assertion", "assertions", "mock", "mocks", "fixture", "fixtures",
                 "file", "files", "entry", "entries", "attribute", "attributes", "return", "check", "checks", "guard"}
_OTHER_DEF_REMAINS = {"first", "second", "duplicate", "duplicated", "redundant", "extra", "stray", "leftover", "other"}
_OBJ_END = re.compile(r"\b(?:from|in|inside|within|of|at|on|since|because|so|as|that|which|where|with|after|before|once|when)\b|[.;]\s")


def _delete_symbols(p):
    """The symbols whose DEFINITION a Delete/Remove item deletes: the object of the verb (`func X`, `X()`, `X` constant/method ...). Empty for 'remove the tests that call
    ...', 'remove the `p: T` parameter from `f`', 'delete the file containing ...' items (the object is not the symbol); at most 4."""
    text = p["text"]
    if _lead_verb(text) not in DELETE_V or _NOT_DEF_OBJECT.match(text):
        return []
    rest = text[_DEL_HEAD.match(text).end():]
    first = re.match(r"`?([A-Za-z_]+)", rest)
    if first and first.group(1).lower() in _NON_DEF_NEXT and not rest.startswith("`"):
        return []
    cut = _OBJ_END.search(rest)
    phrase = rest[:cut.start()] if cut else rest
    found = []
    for rx in (r"\b(?:func|function|def|method|helper|constant|const|class|variable|signal)\s+`?([A-Za-z_]\w*)", r"`([A-Za-z_]\w*)\s*(?:\([^`]*\))?`", r"\b([A-Za-z_]\w*)\(\)"):
        for mm in re.finditer(rx, phrase):
            ident = mm.group(1)
            nxt = re.match(r"[\s`]*([A-Za-z_]+)", phrase[mm.end():])
            before = set(re.findall(r"[A-Za-z_]+", phrase[:mm.start(1)].lower()))
            # another definition remains ('the first/duplicate/redundant def X'), or the object is calls/usages/imports of X rather than X itself
            if ident.lower() in _NOISE_WORDS or (nxt and nxt.group(1).lower() in _NON_DEF_NEXT) or before & (_NON_DEF_NEXT | _OTHER_DEF_REMAINS):
                continue
            found.append((mm.start(1), ident))
    out = []
    for _, sym in sorted(found):
        if sym not in out:
            out.append(sym)
    return out[:4]


def _add_symbols(p):
    if _lead_verb(p["text"]) not in ADD_V:
        return []
    return _symbols(p["text"])[:4]


def _is_test_path(path):
    return bool(re.search(r"(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$", path))


# ---------------------------------------------------------------- per-item rules
def _r04(p, ctx):
    t = p["target"]
    if t.startswith("addons/"):
        return finding("R04", "reject", "vendored target (addons/): never editable by the fleet", t)
    pats = ctx.banned() if ctx is not None else []
    for rx in pats:
        if rx.search(t):
            return finding("R04", "reject", "hard-banned target (.queue-hard-banned-files)", t)
    return None


def _r05(line, p):
    text = p["text"]
    lead = _lead_verb(text)
    if lead in LEAD_VERIFY_VERBS and not CHANGE_WORDS.search(re.sub(r"^\W*[A-Za-z]+", "", text, count=1)):
        return finding("R05", "flag", "item only verifies/ensures/checks - it changes nothing", text[:120])
    if re.match(r"^\W*if\b", text, re.I) or re.search(r"\bif\b[^.]{0,80}\b(delete|remove)\b", text, re.I):
        return finding("R05", "flag", "conditional item ('If ... delete'): not an action", text[:120])
    if re.search(r"manual inspection", line, re.I):
        return finding("R05", "flag", "needs manual inspection", text[:120])
    v = extract_verify(line)
    if v and not re.search(r"VERIFY:\s*`", line):
        c = clean_bare_verify(v)
        if not (R01_CMDS.match(c) and _balanced(c)) or "`" in c:
            return finding("R05", "flag", "VERIFY is prose, not a runnable command", c[:120])
    return None


_R10_SEND = re.compile(r"\b(?:send|sends|sending|make|makes|making|fire|fires|firing|issue|issues|post|posts|hit|hits|call|calls|loop|loops|repeat|repeats|submit|submits)\b[^.]{0,40}\b(?:\d+|N|many|multiple|several|rapid)\b[^.]{0,30}\brequests?\b", re.I)
_R10_429 = re.compile(r"\b429\b|too many requests", re.I)


def _r10(line, p):
    if "supply:" in line:                    # the sanctioned deterministic collector's items
        return None
    text = p["text"]
    if _R10_SEND.search(text) and _R10_429.search(text):
        return finding("R10", "reject", "model-written 'send N requests, assert 429' test: only the deterministic rate-limit collector may emit these", text[:120])
    return None


def _py_names(src):
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError):
        return None
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(n.name)
        elif isinstance(n, ast.Name):
            names.add(n.id)
        elif isinstance(n, ast.arg):
            names.add(n.arg)
        elif isinstance(n, ast.Attribute):
            names.add(n.attr)
        elif isinstance(n, ast.alias):
            names.add((n.asname or n.name).split(".")[0])
        elif isinstance(n, ast.keyword) and n.arg:
            names.add(n.arg)
        elif isinstance(n, ast.ExceptHandler) and n.name:
            names.add(n.name)
    return names


def _module_stems(ctx):
    if getattr(ctx, "_stems", None) is None:
        ctx._stems = {os.path.splitext(os.path.basename(t))[0] for t in ctx.tree()}
    return ctx._stems


_PY_BUILTINS = set(dir(__import__("builtins"))) | {"self", "cls", "super"}


def _r08(p, ctx):
    if ctx is None or _lead_verb(p["text"]) not in MODIFY_V:
        return None
    if _is_test_path(p["target"]):          # a test names the code under test, which lives in other files
        return None
    if re.search(r"\b(create|add|introduce|new|define|implement)\b", p["text"], re.I):
        return None
    t = p["target"]
    if not t.endswith((".py", ".gd")) or t not in ctx.tree():
        return None
    if re.search(r"\bimport(?:s|ed|ing)?\b", p["text"], re.I):   # the item brings names in with an import
        return None
    src = ctx.show(t)
    if src is None:
        return None
    names = _py_names(src) if t.endswith(".py") else None
    if t.endswith(".py") and names is None:
        return None
    missing = []
    for tok in re.findall(r"`([^`]+)`", p["text"]):
        tok = tok.strip()
        fm = re.fullmatch(r"([A-Za-z_]\w*)\s*\(.*\)?", tok)
        if fm:
            ident = fm.group(1)
        elif re.fullmatch(r"[A-Za-z_]\w*", tok) and len(tok) >= 4 and tok.lower() not in STOP_IDENT:
            ident = tok
        else:
            continue
        if ident in _PY_BUILTINS or ident in _module_stems(ctx):   # a builtin, or an importable module of the repo (the item brings it in with an import)
            continue
        defined = (ident in names) if names is not None else bool(re.search(r"\b%s\b" % re.escape(ident), src))
        if not defined and ident not in missing:
            missing.append(ident)
    if missing:
        return finding("R08", "flag", "names symbol(s) the target file does not define and the item does not create", missing)
    return None


# ---------------------------------------------------------------- batch rules R06 / R07
def _r06(idx, parsed, ctx):
    p = parsed[idx]
    if p is None or ctx is None:
        return None
    F = p["target"]
    for sym in _delete_symbols(p):
        hits = {path for path, _, _ in ctx.refs(sym) if path != F}
        if not hits:
            continue
        covered = set()
        for j in range(idx):
            q = parsed[j]
            if q is not None and q["feat"] == p["feat"] and _lead_verb(q["text"]) in DELETE_V and q["target"] in hits:
                covered.add(q["target"])
        remaining = hits - covered
        if not remaining:
            continue
        later = [j + 1 for j in range(idx + 1, len(parsed))
                 if parsed[j] is not None and parsed[j]["feat"] == p["feat"] and _lead_verb(parsed[j]["text"]) in DELETE_V and parsed[j]["target"] in remaining]
        prod = sorted(h for h in remaining if not _is_test_path(h))
        ev = {"symbol": sym, "files": sorted(remaining)[:8], "production_refs": prod[:8], "reorder_after_items": later}
        if later and not prod:
            msg = "deletes %s while tests still reference it; move this item after item(s) %s" % (sym, ",".join(map(str, later)))
        elif prod:
            msg = "deletes %s while production code still references it" % sym
        else:
            msg = "deletes %s while other files still reference it and no earlier item removes them" % sym
        return finding("R06", "flag", msg, ev)
    return None


def lint_batch(lines, ctx=None):
    lined = []
    parsed = []
    for line in lines:
        line2, fs = lint_static(line)
        lined.append((line2, fs))
        parsed.append(parse(line2) if is_open_item(line2) else None)
    adds, dels = {}, {}
    for i, p in enumerate(parsed):
        if p is None:
            continue
        for a in _add_symbols(p):
            adds.setdefault((p["target"], a), []).append(i)
        for d in _delete_symbols(p):
            dels.setdefault((p["target"], d), []).append(i)
    out = []
    for i, (line2, fs) in enumerate(lined):
        p = parsed[i]
        fs = list(fs)
        if p is not None:
            for f in (_r04(p, ctx), _r05(line2, p), _r06(i, parsed, ctx), _r08(p, ctx), _r10(line2, p)):
                if f:
                    fs.append(f)
            for key in dels:
                if key in adds and (i in dels[key] or i in adds[key]):
                    fs.append(finding("R07", "flag", "one open item adds and another deletes the same symbol in the same file", {"file": key[0], "symbol": key[1]}))
                    break
        out.append((line2, fs))
    return out


def lint_item(line, ctx=None):
    return lint_batch([line], ctx)[0]


if __name__ == "__main__":
    sys.stderr.write("library: use ovn_spec_gate.py\n")
    sys.exit(2)
