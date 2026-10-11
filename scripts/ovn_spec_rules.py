#!/usr/bin/env python3
"""scripts/ovn_spec_rules.py - rule set for backlog item lines (spec-compiler-v2 part C2, 2026-10-09).

  lint_item(line, ctx)    -> (line2, [Finding])
  lint_batch(lines, ctx)  -> [(line2, [Finding]), ...]   same order as `lines`; batch rules (R06 reorder, R07) see the other lines
  lint_static(line, only) -> (line2, [Finding])           static repairs R01-R03 + R11, no ctx (the `ovn_spec_gate.py lint` filter and queue_refill's repairs)

Finding = {"rule": "R0x", "sev": "repair" | "reject" | "flag", "msg": str, "evidence": str|list|dict}
  repair  the line was rewritten (line2 differs)        reject  the item can never land: quarantine        flag  report (or hold, R06)

  R01 repair  bare `VERIFY: <cmd> (cat:` -> backticked, when <cmd> starts with grep|test|ls|python|pytest|cd|godot|npm|npx|./gradlew, its quotes balance and it
              carries no prose word (passes/should/...); a trailing sentence period glued to the last token is dropped
  R02 repair  vacuous echo idiom `cmd && echo FAIL || echo PASS` (always exit 0) -> `! ( cmd )` / `cmd`   (ovn_backlog_eligibility.normalize_vacuous_echo)
  R03 repair  backticked grep/test/ls/cat/stat cmd whose WHOLE following sentence is exactly a whitelisted post-change verdict ([which|it] [must] fails [with "No such file or
              directory"] | returns non-zero [exit code] | no matches | No such file [or directory], optionally 'after the change/fix') -> `! cmd`; any other wording
              (old/current/today/initially/when/because/before/if/passes ...) leaves the line untouched and emits an R03 'flag' finding for human review
  R11 repair  a GUT VERIFY that calls addons/gut/cli/gut_cli.gd -> addons/gut/gut_cmdln.gd (gut_cli.gd `extends Node`: it is not a SceneTree script and can never be a `godot -s`
              entry point, so the clause can never pass; xlite techs_data: 20 lines, ALREADY-DONE x6 + fixup-undid-item x3, 2026-10-09)
  R12 flag    a VERIFY names a TEST path (.gd/.py) that does not exist at the ref and that neither this item nor a sibling item of the same [feat] batch creates (xlite
              roster-coerce: `godot -s tests/test_roster_coercion.gd`, a file nothing ever created); batch rule, shadow-only until armed in OVN_SPEC_GATE_ENFORCE_RULES
  R04 reject  TARGET path (text before the first ' - ') is vendored (addons/) or matches .queue-hard-banned-files at the ref
  R05 flag    non-actionable: leading Verify/Ensure/Check/Confirm/Run/Review with no change verb, an 'If ... delete' conditional, 'manual inspection',
              or a prose VERIFY that cannot be run
  R06 flag    Delete/Remove of `func X` / `X()` in file F while `git grep -nw X` finds references in files other than F that no EARLIER Remove/Delete item of the
              same [feat] batch removes. Replay: the 10-09 enemy_faction_map batch (delete get_faction, delete get_all_factions, THEN remove the tests that call
              them) produced 10 remove/restore commits in 8 minutes. Batch time: the finding names the reorder; queue time (queue_refill): HOLD.
  R07 flag    one (file, symbol) is added by one open item and deleted by another
  R08 flag    a modify-verb item names a backticked `sym(` / identifier that the (non-test) target file does not define and no item verb creates (e.g. 'scores' in
              recompute_representative, which has no score input); builtins and the repo's own module names are not flagged
  R13 reject  a VERIFY runs a TEST file as a script (`godot --headless -s tests/test_x.gd`, `cd tests && godot -s test_x.gd`): a GUT test (extends GutTest / res://addons/gut/test.gd) is
              not a SceneTree script, so the clause can never pass (xlite save_manager group: 4 cycles of ALREADY-DONE refused by its own failing VERIFY, 2026-10-11). Fine when the file
              exists at the ref and `extends SceneTree|MainLoop`; a not-yet-existing path is flagged when the repo carries addons/gut. The GUT runner (addons/gut/gut_cmdln.gd) is never flagged.
              Complements R12 (path missing) and R11 (gut_cli.gd); the existing-path resolution (res://, ./, cd-dirs, bare names) is R12's.
  R14 flag    HOLD-class: an item whose VERIFY asserts a tracked file ABSENT (`test ! -f P`) while another item of the same [feat] batch that deletes P comes LATER in the list and this
              item does not delete P itself (a 'test asserts absence' item ordered before the delete can never go green: xlite delete-root-level-stubs, 2026-10-11). Releases itself once P is gone
  R15 flag    shadow evidence for the cheap reachability pre-check: a typing / doc item (type hints, return-type retype, docstring / `##` doc comment, supply:gd-missing-doc) whose target
              function(s) are defined in the target file but have ZERO production callers (no non-comment reference outside tests; a call from inside the same file counts) is work on dead
              code - convert it to a delete item (with its tests) or drop it (xlite aim_modifiers.calc_suppression_aim_penalty: 3 retype commits on a function nothing calls, 2026-10-11).
              Only .gd / .py targets; engine callbacks (_ready, _process, ...), dunders and decorated python functions are never judged dead
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
from ovn_spec_classify import clean_bare_verify, declared_paths  # noqa: E402

ITEM_RE = re.compile(r"^- \[ \] \[(T[1-5])\]\s+(?P<target>.+?)\s+—\s+(?P<body>.*)$")
FEAT_RE = re.compile(r"\[feat:([^\]]+)\]")
R01_CMDS = re.compile(r"^(grep|test|ls|python3?|pytest|cd|godot|npm|npx|\./gradlew)\b")
PROSE_WORDS = {"passes", "pass", "succeeds", "should", "must", "returns", "exits", "fails", "works", "verifies", "ensure", "ensures", "is", "are", "with", "then",
               # 2026-10-10 (reviewer): narration glued after a real command ("grep -n X f shows a match near line 41") ran through bash -c, grep took the words as files and exited 2
               "shows", "show", "shown", "near", "contains", "contain", "appears", "appear", "matches", "matched", "exists", "exist", "has", "have", "does", "outputs", "prints", "reports"}
# commands whose exit status says nothing about the thing being checked: the LAST command of a pipeline (`grep -c x f | wc -l` is 0 whatever grep found) or of a `;` / `||` chain
ALWAYS_ZERO_CMDS = {"echo", "printf", "wc", "cat", "head", "tail", "sort", "uniq", "cut", "tr", "true", ":", "awk", "gawk", "mawk"}
_PLAIN_WORD = re.compile(r"^[A-Za-z0-9][A-Za-z0-9']*$")
_QUOTED = re.compile(r"'[^']*'" + r'|"(?:[^"\\]|\\.)*"')
_CONJ_PROSE = re.compile(r"(?<!\S)(?:and|or)(?!\S)")
_OPS = {"&&", "||", ";", "|", "&", "(", ")", "|&", ";;"}
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


def bare_verify(line):
    """The bare (unbackticked) `VERIFY: cmd [.] (cat:` clause of an item line as (match, cleaned_cmd), or None. The ONE safety test for 'this bare clause is a runnable
    command and not prose' (R01 repairs with it, ovn_credit_items.py `bare-verify` / lib_verify_clause.sh shadow_check run it): starts with a known tool word, quotes balance,
    no backtick, no prose word (passes/should/...); a trailing sentence period glued to the last token is dropped."""
    if re.search(r"VERIFY:\s*`", line):
        return None
    m = re.search(r"VERIFY:\s*(.+?)(\s*\(cat:)", line)
    if not m:
        return None
    cmd = clean_bare_verify(m.group(1))
    if not R01_CMDS.match(cmd) or "`" in cmd or not _balanced(cmd):
        return None
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return None
    if any(t.lower() in PROSE_WORDS for t in toks[1:]):
        return None
    if _prose_tail_or_vacuous(cmd):
        return None
    return m, cmd


def _structure(cmd):
    """(pipelines, comparison_redirect) of a shell clause: pipelines = [(op_before, [[word, ...] per piped command])], quote-aware (shlex punctuation mode); None when it cannot be parsed.
    comparison_redirect = an unquoted `>` followed by a word starting with `=` (`wc -l >= 2`: bash would create a file named `=`)."""
    try:
        lx = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lx.whitespace_split = True
        toks = list(lx)
    except ValueError:
        return None
    pipelines, cur_pipe, cur_cmd, op, cmp_redir, skip = [], [], [], None, False, False
    for i, t in enumerate(toks):
        if skip:
            skip = False
            continue
        if t in _OPS:
            if cur_cmd:
                cur_pipe.append(cur_cmd)
            cur_cmd = []
            if t in ("|", "|&"):
                continue
            if cur_pipe:
                pipelines.append((op, cur_pipe))
            cur_pipe, op = [], t
            continue
        if t and set(t) <= set("<>&") and t != "&":          # a redirect operator: its target word is not an argument
            if t.startswith(">") and i + 1 < len(toks) and toks[i + 1].startswith("="):
                cmp_redir = True
            skip = True
            continue
        cur_cmd.append(t)
    if cur_cmd:
        cur_pipe.append(cur_cmd)
    if cur_pipe:
        pipelines.append((op, cur_pipe))
    return pipelines, cmp_redir


def _prose_tail_or_vacuous(cmd):
    """True when a bare clause that passed the tool-word / quote / prose-word tests is still not a trustworthy check: (0) it joins two commands with a bare English `and` / `or` (quoted ones are fine), (1) it ends in a run of >= 3 plain words (trailing narration:
    `grep -n X f shows a match near line 41`), (2) it compares with an unquoted `>=` (a redirect, not a comparison), or (3) its exit status is that of an always-0 command
    (`grep -c x f | wc -l`, `... | awk '{print}'`, `a || echo MISSING`). (`cmd && echo X`, whose status is cmd's, is fine; the `&& echo PASS || echo FAIL` idiom never gets here: PASS/FAIL are prose words.)"""
    if _CONJ_PROSE.search(_QUOTED.sub("''", cmd)):      # an UNQUOTED English `and` / `or` between two "commands" (bash would hand it to grep as a file name and exit 2)
        return True
    st = _structure(cmd)
    if st is None:
        return True
    pipelines, cmp_redir = st
    if cmp_redir or not pipelines:
        return cmp_redir or not pipelines
    op, last_pipe = pipelines[-1]
    words = last_pipe[-1]
    run = 0
    for w in reversed(words[1:]):
        if _PLAIN_WORD.match(w):
            run += 1
        else:
            break
    if run >= 3:
        return True
    prog = os.path.basename(words[0]) if words else ""
    if prog in ALWAYS_ZERO_CMDS and not (prog in ("awk", "gawk", "mawk") and any("exit" in w for w in words[1:])):
        if len(last_pipe) > 1:
            return True
        if op in (None, ";", "||"):
            return True
    return False


def _r01(line):
    """bare `VERIFY: cmd (cat:` -> `VERIFY: \\`cmd\\` (cat:`"""
    b = bare_verify(line)
    if b is None:
        return line, None
    m, cmd = b
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


_GUT_CLI = re.compile(r"addons/gut/cli/gut_cli\.gd")


def _r11(line):
    """GUT VERIFY calling addons/gut/cli/gut_cli.gd (a Node, never a `-s` entry point) -> addons/gut/gut_cmdln.gd. Only the text from `VERIFY:` on is touched."""
    i = line.find("VERIFY:")
    if i < 0 or not _GUT_CLI.search(line[i:]):
        return line, None
    new = line[:i] + _GUT_CLI.sub("addons/gut/gut_cmdln.gd", line[i:])
    return new, finding("R11", "repair", "GUT VERIFY called addons/gut/cli/gut_cli.gd (extends Node, cannot be a -s entry point): rewritten to addons/gut/gut_cmdln.gd", extract_verify(line) or "")


STATIC_RULES = (("R01", _r01), ("R02", _r02), ("R03", _r03), ("R11", _r11))
STATIC_RULE_IDS = tuple(r for r, _ in STATIC_RULES)


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


_R12_CD = re.compile(r"(?:^|[;&|(]\s*)cd\s+(?:--\s+)?(?:\"([^\"]+)\"|'([^']+)'|([^\s;&|()]+))")


def _r12_cd_dirs(v):
    """Every repo-relative directory a VERIFY could be running its test path from after a `cd` (`cd iptv-backend && python3 -m pytest tests/x.py`): each cd'd dir taken on its own
    (a subshell / `;` restarts from the root) AND composed with the previous ones (`cd a && cd b` = a/b). Absolute, `~`, `$VAR` and `..`-escaping dirs are dropped."""
    out, cur = [], ""
    for m in _R12_CD.finditer(v):
        d = (m.group(1) or m.group(2) or m.group(3) or "").strip()
        if not d or d.startswith(("/", "~", "$", "-")):
            continue
        for cand in (os.path.normpath(d), os.path.normpath(os.path.join(cur, d)) if cur else ""):
            if cand and cand != "." and not cand.startswith("..") and cand not in out:
                out.append(cand)
        cur = os.path.normpath(os.path.join(cur, d)) if cur else os.path.normpath(d)
        if cur.startswith(".."):
            cur = ""
    return out


_R12_PATH = re.compile(r"(?<![\w./-])((?:res://)?[A-Za-z0-9_./-]+\.(?:gd|py))\b")


def _r12(line, p, sibling_lines, ctx):
    """R12: the item's VERIFY names a TEST file that does not exist at the ref and that nothing in this batch creates. The 27B-decomposed items bypass the red-before check
    work-supply items get, so a VERIFY like `godot -s tests/test_roster_coercion.gd` (no such file, no item creates it) enters the queue and can never go green. A path is
    'created' when the item itself or any sibling of the same [feat] batch declares it (its target, or a path after a Create/Add/Write verb: ovn_spec_classify.declared_paths).
    A bare file name (a GUT `-gtest=test_x.gd`) matches any tracked file with that basename; a path in a `cd <pkg> && pytest tests/x.py` clause is also tried under <pkg>/. Needs the ref's tree: with none (git failure) the rule says nothing."""
    if ctx is None:
        return None
    v = extract_verify(line)
    if not v:
        return None
    tree = ctx.tree()
    if not tree:
        return None
    names = {os.path.basename(t) for t in tree}
    declared = set(declared_paths(line))
    if p.get("feat"):
        for sl in sibling_lines:
            if FEAT_RE.search(sl) and FEAT_RE.search(sl).group(1) == p["feat"]:
                declared |= set(declared_paths(sl))
    dnames = {os.path.basename(d) for d in declared}
    cds = _r12_cd_dirs(v)
    missing = []
    for m in _R12_PATH.finditer(v):
        t = m.group(1)
        if t.startswith("res://"):
            t = t[len("res://"):]
        if t.startswith("./"):
            t = t[2:]
        if t.startswith("addons/") or not _is_test_path(t) or os.path.basename(t) in ("gut_cmdln.gd", "gut_cli.gd"):
            continue
        base = os.path.basename(t)
        exists = (t in tree) if "/" in t else (base in names)
        if not exists and "/" in t:
            # `cd <pkg> && pytest tests/x.py`: the path is relative to the cd'd directory, so <pkg>/<path> is the tracked file (a cd-prefixed pytest clause on an EXISTING test
            # file was rejected: 2026-10-10 reviewer replay, 31 xlite / 21 iptv / 25 billwatch / 14 gitlark / 13 TAA false R12 hits).
            exists = any(os.path.normpath(d + "/" + t) in tree for d in cds)
        if exists or t in declared or base in dnames:
            continue
        if t not in missing:
            missing.append(t)
    if missing:
        return finding("R12", "reject", "VERIFY names test path(s) that do not exist and that neither this item nor a sibling item creates: it can never go green", missing[:4])
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


# ---------------------------------------------------------------- R13 / R14 / R15 (delplan, 2026-10-11)
_R13_GODOT = re.compile(r"(?:^|[;&|(]\s*)(?:\S*/)?godot[\w.-]*\b[^;&|`]*?\s(?:-s|--script)\s+[\"']?([^\s\"';&|`]+\.gd)\b")
_R13_RUNNERS = ("gut_cmdln.gd", "gut_cli.gd")
_SCENE_TREE_SCRIPT = re.compile(r"^\s*extends\s+(?:SceneTree|MainLoop)\b", re.M)


def _r13(line, ctx):
    v = extract_verify(line)
    if not v or ctx is None:
        return None
    flagged = []
    tree = None
    for m in _R13_GODOT.finditer(v):
        t = m.group(1)
        if t.startswith("res://"):
            t = t[len("res://"):]
        if t.startswith("./"):
            t = t[2:]
        if t.startswith("addons/") or os.path.basename(t) in _R13_RUNNERS or not _is_test_path(t):
            continue
        tree = ctx.tree() if tree is None else tree
        if not tree:
            return None
        found = None
        if "/" in t and t in tree:
            found = t
        else:
            for d in _r12_cd_dirs(v):
                if os.path.normpath(d + "/" + t) in tree:
                    found = os.path.normpath(d + "/" + t)
                    break
            if found is None and "/" not in t:
                same = sorted(x for x in tree if os.path.basename(x) == t)
                found = same[0] if same else None
        if found is not None:
            src = ctx.show(found)
            if src is None or _SCENE_TREE_SCRIPT.search(src):
                continue
        elif not any(x.startswith("addons/gut/") for x in tree):
            continue          # not a GUT project, and the file does not exist yet: nothing says it is not a SceneTree script
        if t not in flagged:
            flagged.append(t)
    if flagged:
        return finding("R13", "reject", "VERIFY runs a test file as a script (godot -s <test>.gd): a GUT test is not a SceneTree script, so it can never pass - use addons/gut/gut_cmdln.gd -gtest=<file>", flagged[:4])
    return None


_R14_ABSENT = (re.compile(r"(?<![\w!])test\s+!\s+-[fe]\s+[\"']?([^\s\"'&|;`)\]]+)"), re.compile(r"(?<![\w])!\s+test\s+-[fe]\s+[\"']?([^\s\"'&|;`)\]]+)"),
               re.compile(r"\[\s+!\s+-[fe]\s+[\"']?([^\s\"'&|;`)\]]+)"))
_DELETE_PATH_V = DELETE_V | {"retire", "prune"}


def _absent_paths(v):
    out = []
    for rx in _R14_ABSENT:
        for m in rx.finditer(v or ""):
            if m.group(1) not in out:
                out.append(m.group(1))
    return out


def _deletes_path(p, path):
    """True when the item's lead verb deletes `path`: it is the item's target, or the delete text names it (full path or file name)."""
    if _lead_verb(p["text"]) not in _DELETE_PATH_V:
        return False
    return p["target"] == path or path in p["text"] or os.path.basename(path) in p["text"]


def _r14(idx, parsed, lines, ctx):
    p = parsed[idx]
    if p is None or ctx is None or not p.get("feat"):
        return None
    v = extract_verify(lines[idx])
    paths = _absent_paths(v)
    if not paths:
        return None
    tree = ctx.tree()
    if not tree:
        return None
    for P in paths:
        if P not in tree or _deletes_path(p, P):
            continue
        later = [j + 1 for j in range(idx + 1, len(parsed))
                 if parsed[j] is not None and parsed[j]["feat"] == p["feat"] and _deletes_path(parsed[j], P)]
        earlier = [j for j in range(idx) if parsed[j] is not None and parsed[j]["feat"] == p["feat"] and _deletes_path(parsed[j], P)]
        if later and not earlier:
            return finding("R14", "flag", "VERIFY needs %s absent but the item that deletes it comes later (item %s): move this item after the delete" % (P, ",".join(map(str, later))),
                           {"path": P, "delete_items": later})
    return None


_R15_TYPING_DOC = re.compile(
    r"type[- ]hints?|type annotations?|\bannotat(?:e|es|ed|ing|ion|ions)\b|\bretype\b|\btyping\b|return[- ]type|\bdocstrings?\b|doc[- ]comments?|"
    r"\bfrom (?:float|int|str|string|bool)\s+to\s+(?:float|int|str|string|bool)\b|supply:gd-missing-doc", re.I)
_GD_LIFECYCLE = {"_init", "_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_unhandled_key_input", "_draw", "_enter_tree", "_exit_tree", "_notification",
                 "_to_string", "_get", "_set", "_get_property_list", "_gui_input", "_integrate_forces", "_shortcut_input", "_get_configuration_warnings", "_validate_property", "_run", "_cleanup"}
_COMMENT_LINE = re.compile(r"^\s*(?:#|//)")


def _r15_symbols(text):
    """Candidate function names an item text points at: the `a`, `b` list after 'functions:', `func X` / `X(` forms, and every backticked identifier (the caller keeps only the ones the
    target file really defines as a function, so a backticked type name or keyword is harmless)."""
    syms = []
    m = re.search(r"\bfunctions?\b[^`]*?:\s*((?:`[A-Za-z_]\w*`(?:\s*,\s*|\s+and\s+)?)+)", text)
    if m:
        syms += re.findall(r"`([A-Za-z_]\w*)`", m.group(1))
    syms += _symbols(text)
    syms += re.findall(r"`([A-Za-z_]\w*)(?:\([^`]*\))?`", text)
    out = []
    for s_ in syms:
        if s_ not in out and s_.lower() not in STOP_IDENT and s_ not in _GD_LIFECYCLE and not (s_.startswith("__") and s_.endswith("__")):
            out.append(s_)
    return out[:8]


def _r15(p, ctx):
    if ctx is None or _lead_verb(p["text"]) in _DELETE_PATH_V:
        return None
    t = p["target"]
    if not t.endswith((".gd", ".py")) or _is_test_path(t) or t not in ctx.tree():
        return None
    if not _R15_TYPING_DOC.search(p["text"]):
        return None          # a signature merely mentioning `-> bool` is not a typing item; an Add/Create item with no typing/doc phrase builds new code (zero callers is its normal state)
    src = ctx.show(t)
    if src is None:
        return None
    lines_ = src.split("\n")
    syms = _r15_symbols(p["text"])
    if not syms:
        return None
    dead, judged = [], 0
    for sym in syms:
        if judged >= 4:
            break
        if t.endswith(".gd"):
            defrx = re.compile(r"^\s*(?:@[\w.()\", ]+\s+)*(?:static\s+)?func\s+%s\b" % re.escape(sym))
        else:
            defrx = re.compile(r"^\s*(?:async\s+)?def\s+%s\b" % re.escape(sym))
        defs = [i for i, l in enumerate(lines_) if defrx.match(l)]
        if len(defs) != 1:
            continue                                  # not defined here (R08's business) or defined twice: say nothing
        if t.endswith(".py") and any(lines_[k].lstrip().startswith("@") for k in (defs[0] - 1,) if k >= 0):
            return None                               # decorated python function (route / fixture / property): reached by a framework, not by a caller
        judged += 1
        tests_only, live = [], False
        for path, ln, text in ctx.refs(sym):
            if _COMMENT_LINE.match(text) or (path == t and ln - 1 == defs[0]):
                continue
            if _is_test_path(path):
                tests_only.append(path)
                continue
            live = True
            break
        if live:
            return None                               # one reachable symbol keeps the whole item meaningful
        dead.append({"symbol": sym, "tests_only": sorted(set(tests_only))[:4]})
    if judged and len(dead) == judged:
        return finding("R15", "flag", "typing/doc item on code with zero production callers (%s): convert it to a delete item (with its tests) or drop it" % ", ".join(d["symbol"] for d in dead), dead)
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
            for f in (_r04(p, ctx), _r05(line2, p), _r06(i, parsed, ctx), _r08(p, ctx), _r10(line2, p), _r12(line2, p, [l for l, _ in lined], ctx),
                      _r13(line2, ctx), _r14(i, parsed, [l for l, _ in lined], ctx), _r15(p, ctx)):
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
