#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_verify_lint.py - Q2 VERIFY lint (SHADOW ONLY), 2026-11-10.

lint_verify(item_line, repo_root, state_dir=None) -> {"verdict", "reason", "suggested_verify", "rule"}

verdict is "OK" (nothing found) or "SUSPECT" (the VERIFY clause will very likely fail, or pass, for a reason that has nothing to do with the work). Rules fire only on evidence read from
the repo tree (the linter never executes a VERIFY):

  ML1  multiline-literal-grep   a plain (non -z/-P) grep whose literal spans lines or joins a block header and its body on one line (`if X: return 0`, a literal \\n) matches 0
                                lines in the target files while the header part alone matches (GDScript/Python put the body on the NEXT line).
  TP1  test-path-subdir         pytest/vitest/jest run from the repo root (no `cd`) citing a test path that exists only under a subdir (billwatch-web/, backend/ ...).
  TS1  full-project-tsc         `tsc --noEmit` / `vue-tsc` over the whole project when state/tsc_baseline/<repo>__<dir>.count records pre-existing errors (> 0): the clause
                                fails no matter what the item edits. Without a baseline record the rule stays silent.
  PN1  pytest-name-missing      `pytest path::name` (or `-k name`) where the test file exists but defines no such test, and the item does not say it creates/adds it.

  NEGGREP1 whole-file-negative-grep (q-landing-quality 2026-11-12) `! grep -q PAT FILE` / `[ "$(grep -c PAT FILE)" -eq 0 ]` where PAT currently matches >= 2 lines of FILE and the item does not say
                                it removes every occurrence (gitlark c3b579b7: "Remove cursor-pointer from the <h1>" with a file-wide `! grep -q cursor-pointer` was satisfied by deleting the class from
                                every clickable card). The verdict carries the current match count. OVN_VERIFY_LINT_NEGGREP=off disables it.

  q-verify-shapes (2026-11-18, SHADOW; BACKEND_IMPORT_ROOT ROUTES_PATH_ATTR K_FILTER_ZERO_TESTS COLLECT_ONLY_GREP_HELPER ONE_LINER_MISSING_IMPORT NODEID_WRONG_FILE TEST_NAME_DOES_NOT_EXIST DIRTY_PATH):
                                VERIFY shapes that can never pass, read from the tree (see the section comment below and docs/VERIFY_SHAPES_2026-11-18.md).
                                OVN_VERIFY_LINT_PARK=on (default OFF) lets the item guard park an item whose last 2 picks were ALREADY-DONE/landed-uncredited when it carries a PARK_RULES verdict.

Mode: env OVN_VERIFY_LINT = off | shadow (default). `enforce` (shared with the older ovn_verify_shape_lint) is treated as shadow: THIS linter never changes an item.
Shadow rows go to state/verify_lint.jsonl (OVN_VERIFY_LINT_LOG overrides), deduped per (repo, item hash, rule) through state/verify_lint.seen.

CLI
  ovn_verify_lint.py check '<item line>' --repo-root DIR [--state DIR]       one item, JSON
  ovn_verify_lint.py shadow FILE --repo-root DIR [--state DIR] [--repo NAME]  every open item of a progress file -> jsonl rows (hooks use this; never raises, rc 0)
  ovn_verify_lint.py replay FILE... [--state DIR] [--trees DIR]               read-only: counts per rule (all rules, no log writes); --trees DIR/<repo> = the repo tree for FILE's dir name
  ovn_verify_lint.py park-cycle --outcomes F --repo R --prog P --repo-root D --state S [--n 2]   item-guard hook for OVN_VERIFY_LINT_PARK (TSV: trip count rule line_no key why)
"""
import glob
import hashlib
import json
import os
import re
import shlex
import signal
import sys
import time as _time

HERE = os.path.dirname(os.path.abspath(__file__))
OK, SUSPECT = "OK", "SUSPECT"
MAX_FILES = 400
MAX_LINE = 4000                     # ReDoS hardening: longer lines are skipped by _count
MAX_FILE_BYTES = 2 * 1024 * 1024    # ... and files over this are skipped
MAX_PAT = 400
BUDGET_S = float(os.environ.get("OVN_VERIFY_LINT_BUDGET_S", "2") or 2)   # wall-clock budget per item (lint_verify)


class Budget(Exception):
    """per-item time budget exhausted: degrade to verdict 'unknown'."""


_DEADLINE = [0.0]


def _check_budget():
    if _DEADLINE[0] and _time.monotonic() > _DEADLINE[0]:
        raise Budget()


def _alarm(signum, frame):
    raise Budget()


def _unsafe_pattern(p):
    """True for patterns prone to catastrophic backtracking (quantified group containing a quantifier or alternation, or stacked quantifiers) or absurdly long."""
    if len(p) > MAX_PAT:
        return True
    return re.search(r"\((?:[^()\\]|\\.)*(?:[+*]|\{\d*,\d*\}|\|)(?:[^()\\]|\\.)*\)\)?(?:[+*]|\{\d*,)", p) is not None or re.search(r"(?<!\\)[+*][+*]", p) is not None
_BODY_KW = r"(?:return|continue|break|pass|push_error|push_warning|queue_free|raise|print)"


def mode():
    m = (os.environ.get("OVN_VERIFY_LINT", "shadow") or "shadow").strip().lower()
    return "off" if m == "off" else "shadow"


def _res(verdict=OK, reason="", suggested="", rule=""):
    return {"verdict": verdict, "reason": reason, "suggested_verify": suggested, "rule": rule}


# ---------------------------------------------------------------- parsing
def extract_verify(line):
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if m:
        return m.group(1)
    m = re.search(r"VERIFY:\s*(.+?)\.?\s*\(cat:", line)
    if m:
        return m.group(1).strip()
    m = re.search(r"VERIFY:\s*(.+)$", line)
    return m.group(1).strip() if m else None


def split_stages(text):
    """quote-aware split on top-level && || ; |  -> [stage_text]; a lone unbalanced quote makes the whole text one stage."""
    out, cur, q, i, n = [], [], None, 0, len(text)
    while i < n:
        c = text[i]
        if q:
            cur.append(c)
            if c == q:
                q = None
            elif c == "\\" and q == '"' and i + 1 < n:
                cur.append(text[i + 1])
                i += 1
        elif c in "'\"":
            q = c
            cur.append(c)
        elif c == "\\" and i + 1 < n:
            cur.append(c)
            cur.append(text[i + 1])
            i += 1
        elif text.startswith("&&", i) or text.startswith("||", i):
            out.append("".join(cur))
            cur = []
            i += 1
        elif c in ";|":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


def _toks(stage):
    try:
        return shlex.split(stage)
    except ValueError:
        return stage.split()


def _walk(clause):
    """yield (base_subdir, tokens) per stage, tracking a leading `cd DIR` (base accumulates across && stages)."""
    base = ""
    for st in split_stages(clause):
        t = _toks(st)
        while t and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t[0]):   # VAR=val prefix
            t = t[1:]
        if not t:
            continue
        if t[0] == "cd" and len(t) > 1:
            base = os.path.normpath(os.path.join(base, t[1])) if not t[1].startswith("/") else t[1]
            continue
        yield base, t


def _root(repo_root, base):
    return base if base.startswith("/") else os.path.join(repo_root, base)


# ---------------------------------------------------------------- ML1
def _bre_to_py(p, extended):
    if extended:
        return p
    # BRE: \| \( \) \{ \} are operators, bare ones literal
    p = re.sub(r"\\([|(){}+?])", lambda m: "\x00" + m.group(1), p)
    p = re.sub(r"([|(){}+?])", r"\\\1", p)
    return p.replace("\x00", "")


def _grep_args(tokens):
    """-> (pattern, files, flags) or None."""
    flags, pats, rest, i = set(), [], [], 1
    while i < len(tokens):
        a = tokens[i]
        if a == "--":
            rest += tokens[i + 1:]
            break
        if a.startswith("--"):
            if a in ("--regexp",) and i + 1 < len(tokens):
                pats.append(tokens[i + 1])
                i += 1
            elif a.startswith("--regexp="):
                pats.append(a.split("=", 1)[1])
            else:
                flags.add(a)
        elif a.startswith("-") and len(a) > 1:
            letters = a[1:]
            if "e" in letters and letters.endswith("e") and i + 1 < len(tokens):
                pats.append(tokens[i + 1])
                i += 1
            elif letters[0] in "ABCm" and len(letters) == 1:
                i += 1                      # -A 3
            else:
                flags.update(letters)
        else:
            rest.append(a)
        i += 1
    if not pats:
        if not rest:
            return None
        pats, rest = [rest[0]], rest[1:]
    return pats[0], rest, flags


def _expand(root, specs, recursive):
    files = []
    for s in specs:
        p = s if os.path.isabs(s) else os.path.join(root, s)
        for g in (glob.glob(p) or [p]):
            if os.path.isdir(g):
                if recursive:
                    for dp, dn, fn in os.walk(g):
                        dn[:] = [d for d in dn if d not in (".git", "node_modules", ".venv", "__pycache__")]
                        files += [os.path.join(dp, f) for f in fn]
                        if len(files) > MAX_FILES:
                            return files[:MAX_FILES]
            elif os.path.isfile(g):
                files.append(g)
    return files[:MAX_FILES]


def _count(rx, files):
    n = 0
    for f in files:
        try:
            if os.path.getsize(f) > MAX_FILE_BYTES:
                continue
            with open(f, "r", errors="replace") as fh:
                for ln in fh:
                    _check_budget()
                    if len(ln) > MAX_LINE:
                        continue
                    if rx.search(ln):
                        n += 1
        except OSError:
            pass
    return n


def rule_ml1(clause, repo_root):
    for base, t in _walk(clause):
        if t[0] not in ("grep", "egrep", "rg") or t[0] == "rg":
            continue
        ga = _grep_args(t)
        if not ga:
            continue
        pat, specs, flags = ga
        if "z" in flags or "P" in flags or "--null-data" in flags or "v" in flags or not specs:
            continue
        ext = "E" in flags or t[0] == "egrep"
        fixed = "F" in flags
        header = body = None
        if "\\n" in pat or "\n" in pat:
            parts = re.split(r"\\n|\n", pat)
            header, body = parts[0], " ".join(p.strip() for p in parts[1:])
        else:
            m = re.match(r"^(.*?:)\s*(" + _BODY_KW + r"\b.*)$", pat)
            if m and re.search(r"\b(if|elif|else|for|while|match|func|try|except)\b", m.group(1)):
                header, body = m.group(1), m.group(2)
        if header is None:
            continue
        hdr_core = header.rstrip().rstrip(":")
        if not hdr_core.strip():
            continue
        root = _root(repo_root, base)
        files = _expand(root, specs, "r" in flags or "R" in flags)
        if not files:
            continue
        try:
            full = re.compile(re.escape(pat) if fixed else _bre_to_py(pat, ext))
            neigh = re.compile(re.escape(hdr_core) if fixed else _bre_to_py(hdr_core, ext))
        except re.error:
            continue
        if not fixed and (_unsafe_pattern(pat) or _unsafe_pattern(hdr_core)):
            continue                        # ReDoS guard: skip rather than run a backtracking-prone model-written pattern
        if _count(full, files) == 0 and _count(neigh, files) > 0:
            a_ = hdr_core.replace("'", "'\"'\"'")
            b_ = (body or "").replace("'", "'\"'\"'")
            target = " ".join(shlex.quote(s) for s in specs)
            sug = "grep -A1 -E '%s' %s | grep -qE '%s'" % (a_, target, b_) if b_ else ""
            return _res(SUSPECT, "ML1: grep literal %r spans lines (block header + body) so it matches 0 lines, while its header part %r matches; the body sits on the next line" % (pat, hdr_core), sug, "ML1")
    return None


# ---------------------------------------------------------------- TP1
_RUNNER = re.compile(r"(?:^|/)(pytest|py\.test|vitest|jest)$")
_TESTLIKE = re.compile(r"(\.py|\.[cm]?[jt]sx?|\.gd)(::.*)?$")


def _find_sub(repo_root, rel):
    hits = []
    try:
        subs = sorted(d for d in os.listdir(repo_root) if os.path.isdir(os.path.join(repo_root, d)) and not d.startswith(".") and d not in ("node_modules", "venv", ".venv", "__pycache__"))
    except OSError:
        return hits
    for d in subs:
        if os.path.exists(os.path.join(repo_root, d, rel)):
            hits.append(d)
    return hits


def rule_tp1(clause, repo_root):
    for base, t in _walk(clause):
        exe = None
        for i, a in enumerate(t[:4]):
            if _RUNNER.search(a) or (a in ("npx", "python", "python3", "-m") and i + 1 < len(t) and _RUNNER.search(t[i + 1])):
                exe = i
                if a in ("npx", "python", "python3", "-m"):
                    exe = i + 1
                break
        if exe is None:
            continue
        for a in t[exe + 1:]:
            if a.startswith("-") or not _TESTLIKE.search(a):
                continue
            rel = a.split("::", 1)[0]
            if os.path.isabs(rel):
                continue
            if os.path.exists(os.path.join(_root(repo_root, base), rel)):
                continue
            subs = _find_sub(repo_root, rel) if not base else []
            if subs:
                d = subs[0]
                return _res(SUSPECT, "TP1: test path %r does not exist from the repo root but exists under %s/ - the runner is invoked from the root (no cd), so it collects nothing / errors" % (rel, d),
                            "cd %s && %s" % (d, clause.strip()), "TP1")
    return None


# ---------------------------------------------------------------- TS1
def _tsc_baseline(state_dir, repo_root, base):
    if not state_dir:
        return None
    repo = os.path.basename(os.path.abspath(repo_root))
    d = os.path.basename(base.rstrip("/")) if base else ""
    cands = []
    if d:
        cands.append("%s__%s.count" % (repo, d))
    else:
        cands += [os.path.basename(f) for f in glob.glob(os.path.join(state_dir, "tsc_baseline", "%s__*.count" % repo))]
    for c in cands:
        p = os.path.join(state_dir, "tsc_baseline", c)
        try:
            n = int(open(p).read().split()[0])
            return c, n
        except (OSError, ValueError, IndexError):
            continue
    return None


def rule_ts1(clause, repo_root, state_dir):
    for base, t in _walk(clause):
        j = None
        for i, a in enumerate(t[:3]):
            if a in ("tsc", "vue-tsc") or a.endswith("/tsc") or a.endswith("/vue-tsc"):
                j = i
                break
        if j is None:
            continue
        args = t[j + 1:]
        if any(not a.startswith("-") and re.search(r"\.[cm]?tsx?$|\.vue$", a) for a in args):
            continue                        # specific files named: not the full project
        if "--noEmit" not in args and "--noemit" not in [a.lower() for a in args]:
            continue
        bl = _tsc_baseline(state_dir, repo_root, base)
        if bl and bl[1] > 0:
            return _res(SUSPECT, "TS1: full-project %s --noEmit but the recorded baseline (%s) is %d pre-existing errors, so this VERIFY fails regardless of the item" % (t[j], bl[0], bl[1]),
                        "run the project tsc and compare the error count to the baseline (ovn_tsc_gate.sh), or grep the tsc output for the touched file only", "TS1")
    return None


# ---------------------------------------------------------------- PN1
_CREATE_WORDS = re.compile(r"\b(create|creates|creating|add|adds|adding|write|writes|new test|introduce|implement)\b", re.I)


def _defined(src, name):
    return re.search(r"(?:def|class|func)\s+%s\b" % re.escape(name), src) is not None


def rule_pn1(item, clause, repo_root, siblings=()):
    if _CREATE_WORDS.search(item.split("VERIFY:")[0]):
        return None
    for base, t in _walk(clause):
        if not any(_RUNNER.search(a) for a in t[:4]) or not any("pytest" in a or "py.test" in a for a in t[:4]):
            continue
        names = []
        for a in t[1:]:
            if "::" in a and not a.startswith("-"):
                path, rest = a.split("::", 1)
                names.append((path, [x for x in re.split(r"::", re.sub(r"\[.*\]$", "", rest)) if x]))
        for path, nm in names:
            p = os.path.join(_root(repo_root, base), path)
            if not os.path.isfile(p):
                continue
            try:
                src = open(p, errors="replace").read()
            except OSError:
                continue
            for n in nm:
                if not _defined(src, n):
                    if any(n in sb and _CREATE_WORDS.search(sb.split("VERIFY:")[0]) for sb in siblings if sb != item):
                        continue            # a sibling open item creates it: an ordering matter, not a bad VERIFY
                    return _res(SUSPECT, "PN1: %s::%s - %s defines no %r (pytest collects nothing, rc 4/5)" % (path, "::".join(nm), path, n), "", "PN1")
    return None


# ---------------------------------------------------------------- API
# ---------------------------------------------------------------- NEGGREP1
_ALL_WORDS = re.compile(r"\b(?:every|all|each|any|anywhere|everywhere|entirely|throughout|whole|completely|no remaining|no more|no longer (?:use|contain)s?|zero)\b|\bremove (?:the )?(?:last|remaining)\b", re.I)


def _neg_greps(clause):
    """-> [(base, tokens)] for grep calls whose success means 'ZERO matches': `! grep ...` stages and `$(grep -c ...)` compared to 0."""
    out = []
    for base, t in _walk(clause):
        if t and t[0] == "!" and len(t) > 1 and t[1] in ("grep", "egrep"):
            out.append((base, t[1:]))
    for m in re.finditer(r"grep\s+[^)`|]*?(?:\)|`)\s*\"?\s*(?:-eq|==|=)\s*0\b", clause):
        seg = m.group(0)
        seg = re.sub(r"(?:\)|`)\s*\"?\s*(?:-eq|==|=)\s*0\b$", "", seg)
        tk = _toks(seg)
        if tk and tk[0] == "grep" and any(re.match(r"^-[A-Za-z]*c", a) for a in tk[1:]):
            out.append(("", tk))
    for m in re.finditer(r"grep\s+(-[A-Za-z]*c[A-Za-z]*\s+[^|;&]*?)\|\s*(?:grep\s+-q\s+['\"]?\^0\$|tr\b.*?\|\s*grep\s+-q\s+['\"]?\^0\$)", clause):
        tk = _toks("grep " + m.group(1))
        out.append(("", tk))
    return out


def rule_neggrep1(item, clause, repo_root):
    if os.environ.get("OVN_VERIFY_LINT_NEGGREP", "shadow").strip().lower() == "off":
        return None
    if _ALL_WORDS.search(re.sub(r"VERIFY:.*$", "", item or "", flags=re.S)):
        return None                         # the item itself says every occurrence goes
    mcd = re.match(r"\s*cd\s+(\S+)\s*&&", clause)
    base0 = mcd.group(1).strip("'\"") if mcd else ""
    for base, t in _neg_greps(clause):
        ga = _grep_args(t)
        if not ga:
            continue
        pat, specs, flags = ga
        if "v" in flags or "z" in flags or "P" in flags or "r" in flags or "R" in flags or not specs or not pat.strip():
            continue                        # -r: a directory-wide ban (`! grep -rq secret src/`) is a different, usually intended, shape
        ext = "E" in flags or t[0] == "egrep"
        fixed = "F" in flags
        root = _root(repo_root, base or base0)
        files = _expand(root, specs, False)
        if not files or len(files) > 40:
            continue                        # a glob over many files: not the single-file shape this rule is about
        if not fixed and _unsafe_pattern(pat):
            continue
        try:
            rx = re.compile(re.escape(pat) if fixed else _bre_to_py(pat, ext), re.I if "i" in flags else 0)
        except re.error:
            continue
        n = _count(rx, files)
        if n >= 2:
            return _res(SUSPECT, "NEGGREP1: file-wide negative grep for %r currently matches %d lines of %s; satisfying it removes every occurrence, but the item does not say it removes all of them (scope the check to the element the item names)" % (pat, n, " ".join(specs)),
                        "", "NEGGREP1")
    return None


# ---------------------------------------------------------------- q-verify-shapes (2026-11-18, SHADOW rules)
# VERIFY clauses that can NEVER pass for reasons the rules above cannot see (the ALREADY-DONE / landed-uncredited loop: credit-by-evidence replay credited 0 of 78 rows because of them).
# Names: BACKEND_IMPORT_ROOT ROUTES_PATH_ATTR K_FILTER_ZERO_TESTS COLLECT_ONLY_GREP_HELPER ONE_LINER_MISSING_IMPORT NODEID_WRONG_FILE TEST_NAME_DOES_NOT_EXIST DIRTY_PATH.
# All read the repo tree only (never execute a VERIFY, never import repo code, never spawn pytest). Verdicts are SHADOW: the journal row is the only effect, except the opt-in
# OVN_VERIFY_LINT_PARK=on park (park_cycle below; default OFF) which only ever considers the rules named in PARK_RULES.
NEW_RULES = ("BACKEND_IMPORT_ROOT", "ROUTES_PATH_ATTR", "K_FILTER_ZERO_TESTS", "COLLECT_ONLY_GREP_HELPER", "ONE_LINER_MISSING_IMPORT", "NODEID_WRONG_FILE", "TEST_NAME_DOES_NOT_EXIST", "DIRTY_PATH")
# rules whose corpus replay met >= 80% precision with n >= 20 (see docs/VERIFY_SHAPES_2026-11-18.md); the park consults ONLY these (env OVN_VERIFY_LINT_PARK_RULES overrides, comma list)
PARK_RULES = ("NODEID_WRONG_FILE",)
_FASTAPI_INCLUDED_ROUTER_MIN = (0, 140)   # observed _IncludedRouter wrappers (no .path/.methods/.endpoint/.dependant) at 0.143.3; plain APIRoute at 0.115.0
_TEST_CONF = re.compile(r"^\s*(python_files|python_functions|python_classes|doctest_modules)\b", re.M)


def _head(item):
    return re.sub(r"VERIFY:.*$", "", item or "", flags=re.S)


_TESTY = re.compile(r"(?:^|/)(?:tests?|__tests__|spec|specs|e2e)/|(?:^|/)test_[^/]*$|[._]tests?\.[A-Za-z]+$|[._]spec\.[A-Za-z]+$|_test\.py$|(?:^|/)conftest\.py$")


def _lead_path(item):
    """the item's leading target: the first path-with-extension in the text before VERIFY (tags like [T1] / [CLAUDE] repo/ - are ignored)."""
    m = re.search(r"[\w@./-]+\.[A-Za-z]{1,5}\b", re.sub(r"\[[^\]]*\]", " ", _head(item)))
    return m.group(0) if m else ""


def _lead_is_test(item):
    """True when the item's own target is a test file: the item writes/extends tests, so a test name its VERIFY selects may legitimately not exist yet."""
    lp = _lead_path(item)
    if lp and _TESTY.search(lp):
        return True
    return re.search(r"\b(?:add|adds|create|creates|write|writes|extend|extends|new)\b[^.]{0,60}\btests?\b", _head(item), re.I) is not None   # 'and add a test asserting ...'


def _names_it(item, *needles):
    h = _head(item).lower()
    return any(n and n.lower() in h for n in needles)


def split_stages_sep(text):
    """like split_stages but keeps the separator in front of every stage: [(stage, sep)] with sep in '', '&&', '||', ';', '|'."""
    out, cur, q, i, n, sep = [], [], None, 0, len(text), ""
    def flush(nsep):
        out.append(("".join(cur).strip(), sep))
    while i < n:
        c = text[i]
        if q:
            cur.append(c)
            if c == q:
                q = None
            elif c == "\\" and q == '"' and i + 1 < n:
                cur.append(text[i + 1])
                i += 1
        elif c in "'\"":
            q = c
            cur.append(c)
        elif c == "\\" and i + 1 < n:
            cur.append(c)
            cur.append(text[i + 1])
            i += 1
        elif text.startswith("&&", i) or text.startswith("||", i):
            flush(text[i:i + 2])
            sep, cur = text[i:i + 2], []
            i += 1
        elif c in ";|":
            flush(c)
            sep, cur = c, []
        else:
            cur.append(c)
        i += 1
    flush("")
    return [(s, p) for s, p in out if s]


def _walk_sep(clause):
    base = ""
    for st, sep in split_stages_sep(clause):
        t = _toks(st)
        while t and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t[0]):
            t = t[1:]
        if not t:
            continue
        if t[0] == "cd" and len(t) > 1:
            base = os.path.normpath(os.path.join(base, t[1])) if not t[1].startswith("/") else t[1]
            continue
        yield base, t, sep


_PYEXE = re.compile(r"(?:^|/)python[0-9.]*$")


def _py_c(t):
    """python[3] [-flags] -c CODE -> CODE, else None."""
    t = t[1:] if t and t[0] == "!" else t
    for i, a in enumerate(t[:6]):
        if _PYEXE.search(a):
            j = i + 1
            while j < len(t) and t[j].startswith("-") and t[j] != "-c":
                j += 1
            if j + 1 < len(t) and t[j] == "-c":
                return t[j + 1]
            return None
    return None


def _is_pytest(t):
    t = t[1:] if t and t[0] == "!" else t
    return any(_RUNNER.search(a) and ("pytest" in a or "py.test" in a) for a in t[:4]) or any(a == "pytest" for a in t[:4])


# ---- a. BACKEND_IMPORT_ROOT
def rule_backend_import_root(clause, repo_root):
    if "PYTHONPATH" in clause or "sys.path" in clause:
        return None
    for base, t in _walk(clause):
        code = _py_c(t)
        if not base or base.startswith("/") or code is None:
            continue
        root = _root(repo_root, base)
        if not (os.path.isdir(os.path.join(root, "app")) or os.path.isfile(os.path.join(root, "app.py"))):
            continue
        for m in re.finditer(r"(?:\bfrom|\bimport)\s+([A-Za-z_]\w*)\.app\b", code):
            x = m.group(1)
            if x == "app" or os.path.exists(os.path.join(root, x)) or os.path.exists(os.path.join(root, x + ".py")):
                continue
            return _res(SUSPECT, "BACKEND_IMPORT_ROOT: the one-liner runs inside %s/ where only `app` is importable, but imports %s.app (the repo-root package name; %s/%s does not exist) -> ModuleNotFoundError" % (base, x, base, x),
                        clause.replace(x + ".app", "app"), "BACKEND_IMPORT_ROOT")
    return None


# ---- b. ROUTES_PATH_ATTR
def _ver(s):
    m = re.match(r"(\d+)\.(\d+)", s or "")
    return (int(m.group(1)), int(m.group(2))) if m else None


def _fastapi_version(repo_root, root):
    """installed version from a venv dist-info when present, else the requirement spec ('==' pins; anything else floats to the latest = affected). None when fastapi is not declared."""
    for d in (root, repo_root):
        for g in glob.glob(os.path.join(d, ".venv", "lib", "python*", "site-packages", "fastapi-*.dist-info")):
            v = _ver(os.path.basename(g)[len("fastapi-"):])
            if v:
                return v
    for d in dict.fromkeys((root, repo_root)):
        for f in glob.glob(os.path.join(d, "requirements*.txt")) + [os.path.join(d, "pyproject.toml")]:
            try:
                txt = open(f, errors="replace").read(200000)
            except OSError:
                continue
            m = re.search(r"(?im)^\s*[\"']?fastapi(?:\[[^\]]*\])?\s*(==|>=|~=|>|<=|<)?\s*([0-9][\w.]*)?", txt)
            if m:
                if m.group(1) == "==" and _ver(m.group(2)):
                    return _ver(m.group(2))
                if m.group(1) in ("<=", "<") and _ver(m.group(2)):
                    return _ver(m.group(2))
                return (999, 0)
    return None


def rule_routes_path_attr(clause, repo_root):
    for base, t in _walk(clause):
        code = _py_c(t)
        if code is None or not re.search(r"\bapp\.(?:router\.)?routes\b", code):
            continue
        if not re.search(r"(?<![\w.])(?!os\b|sys\b|self\b)\w+\.(?:path|methods|endpoint|dependant|dependency|path_format)\b", code):
            continue
        v = _fastapi_version(repo_root, _root(repo_root, base))
        if v is None or v < _FASTAPI_INCLUDED_ROUTER_MIN:
            continue
        return _res(SUSPECT, "ROUTES_PATH_ATTR: iterates app.routes and reads route attributes (.path/.methods/.endpoint/.dependant): on FastAPI >= %d.%d (declared %s) include_router entries are _IncludedRouter wrappers without those attributes -> AttributeError" % (_FASTAPI_INCLUDED_ROUTER_MIN + ("floating/latest" if v[0] >= 999 else ".".join(map(str, v)),)),
                    "use app.openapi()['paths'] (and its methods/parameters) instead of walking app.routes", "ROUTES_PATH_ATTR")
    return None


# ---- c/d/f. pytest test-name model (static: def test*/class names/module+dir names/marks; parametrize files match on any text)
_VALUE_OPTS = {"-k", "-m", "-p", "-c", "-o", "-W", "-n", "--rootdir", "--tb", "--maxfail", "--ignore", "--ignore-glob", "--deselect", "--junitxml", "--cov", "--cov-report", "--cov-fail-under", "--durations",
               "--basetemp", "--confcutdir", "--import-mode", "-r", "--log-level", "--timeout", "--color", "--capture", "--override-ini", "--cov-config", "--maxprocesses", "--dist", "--lf-opt", "--rootdir"}


def _pytest_parts(t):
    """-> (targets, k_expr or None, flags)"""
    t = t[1:] if t and t[0] == "!" else t
    i = 0
    while i < len(t) and not (_RUNNER.search(t[i]) and "pytest" in t[i]) and t[i] != "pytest":
        i += 1
    if i >= len(t):
        for j, a in enumerate(t):
            if a == "pytest":
                i = j
        if i >= len(t):
            return [], None, set()
    targets, k, flags, j = [], None, set(), i + 1
    while j < len(t):
        a = t[j]
        if a == "-k" and j + 1 < len(t):
            k = t[j + 1]
            j += 2
            continue
        if a.startswith("-k") and len(a) > 2 and not a.startswith("--"):
            k = a[2:].lstrip("=")
        elif a.startswith("--keyword="):
            k = a.split("=", 1)[1]
        elif a in _VALUE_OPTS and j + 1 < len(t):
            j += 2
            continue
        elif a.startswith("-"):
            flags.add(a)
        else:
            targets.append(a)
        j += 1
    return targets, k, flags


_CONF_OK = {"python_files": {"test_*.py", "*_test.py", "tests.py"}, "python_functions": {"test_*", "test*"}, "python_classes": {"Test*"}}


def _test_conf_custom(root, repo_root):
    """True when a pytest config changes WHICH files/functions/classes are collected away from the conventional test_*.py / test* / Test* (or turns doctest collection on)."""
    for d in dict.fromkeys((root, repo_root)):
        for f in ("pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini"):
            try:
                txt = open(os.path.join(d, f), errors="replace").read(100000)
            except OSError:
                continue
            for m in re.finditer(r"(?m)^\s*(python_files|python_functions|python_classes|doctest_modules)\s*[=:]\s*(.*)$", txt):
                key, val = m.group(1), m.group(2).strip()
                if key == "doctest_modules":
                    if val.lower() in ("true", "1", "yes"):
                        return True
                    continue
                vals = {x.strip("\"',[] ") for x in re.split(r"[\s,]+", val) if x.strip("\"',[] ")}
                if not vals or not vals <= _CONF_OK[key]:
                    return True
    return False


def _collect_tests(root, targets):
    """-> (entries, files_seen). entries = [(relpath, names_set(lower), fuzzy_text_or_None, nodeid)]; names include fn, class, module, dirs, marks."""
    files = []
    specs = [x.split("::", 1)[0] for x in targets if x.split("::", 1)[0].endswith(".py") or os.path.isdir(os.path.join(root, x.split("::", 1)[0]))]
    if not specs:
        for d in ("tests", "test"):
            if os.path.isdir(os.path.join(root, d)):
                specs.append(d)
        if not specs:
            specs = ["."]
    for s in specs:
        p = os.path.join(root, s)
        if os.path.isfile(p):
            files.append(p)
        elif os.path.isdir(p):
            for dp, dn, fn in os.walk(p):
                dn[:] = [d for d in dn if d not in (".git", "node_modules", ".venv", "venv", "__pycache__", "site-packages")]
                files += [os.path.join(dp, f) for f in fn if f.endswith(".py") and (f.startswith("test_") or f.endswith("_test.py"))]
                _check_budget()
                if len(files) > MAX_FILES:
                    break
    ents = []
    for f in files[:MAX_FILES]:
        _check_budget()
        try:
            if os.path.getsize(f) > MAX_FILE_BYTES:
                continue
            src = open(f, errors="replace").read()
        except OSError:
            continue
        rel = os.path.relpath(f, root)
        fuzzy = src.lower() if re.search(r"parametrize|pytest\.param|params\s*=|__getattr__|importlib|exec\(|globals\(\)", src) else None
        parts = [x.lower() for x in rel.split(os.sep)]
        mod = [parts[-1], parts[-1][:-3] if parts[-1].endswith(".py") else parts[-1]]
        cls_stack, lines = [], src.split("\n")
        filemarks = {m.lower() for ln in lines if ln.startswith("pytestmark") for m in re.findall(r"pytest\.mark\.(\w+)", ln)}
        for idx, ln in enumerate(lines):
            if len(ln) > MAX_LINE:
                continue
            mc = re.match(r"^(\s*)class\s+(\w+)", ln)
            ind = len(ln) - len(ln.lstrip())
            if mc:
                cls_stack = [c for c in cls_stack if c[0] < len(mc.group(1))] + [(len(mc.group(1)), mc.group(2))]
                continue
            md = re.match(r"^(\s*)(?:async\s+)?def\s+(test\w*)\s*\(", ln)
            if not md:
                continue
            dind = len(md.group(1))
            cls_stack = [c for c in cls_stack if c[0] < dind]
            marks = []
            for back in range(1, 7):
                if idx - back < 0:
                    break
                pm = re.match(r"^\s*@pytest\.mark\.(\w+)", lines[idx - back])
                if pm:
                    marks.append(pm.group(1).lower())
            names = set(parts[:-1]) | set(mod) | {md.group(2).lower()} | {c[1].lower() for c in cls_stack} | set(marks) | filemarks
            nid = "::".join([rel] + [c[1] for c in cls_stack] + [md.group(2)])
            ents.append((rel, names, fuzzy, nid))
    return ents, len(files)


def _restrict_nodeids(ents, targets):
    """`file.py::Class::test` targets select only matching tests (a `-k` then filters THAT selection). Returns [] when a node id selects nothing (PN1's matter, not ours)."""
    sel = [x for x in targets if "::" in x]
    if not sel:
        return ents
    keep = []
    for x in sel:
        f, rest = x.split("::", 1)
        chain = [c for c in re.sub(r"\[.*\]$", "", rest).split("::") if c]
        for e in ents:
            if os.path.normpath(e[0]) == os.path.normpath(f) or e[0].endswith(os.sep + os.path.normpath(f)) and all(c.lower() in e[1] for c in chain):
                if all(c.lower() in e[1] for c in chain):
                    keep.append(e)
    return keep


def _k_matcher(expr):
    """-> callable(names_set, fuzzy_text) -> bool, or None when the expression is not one pytest accepts / we cannot model."""
    toks = re.findall(r"\(|\)|[^\s()]+", expr or "")
    if not toks or len(toks) > 40:
        return None
    py = []
    for tk in toks:
        if tk in ("and", "or", "not", "(", ")"):
            py.append(tk)
        elif re.match(r"^[\w:+\-.\[\]\\/]+$", tk):
            py.append("M(%r)" % tk.lower())
        else:
            return None
    code = " ".join(py)
    try:
        compile(code, "<k>", "eval")
    except SyntaxError:
        return None

    def run(names, fuzzy):
        def M(term):
            return any(term in n for n in names) or (fuzzy is not None and term in fuzzy)
        return bool(eval(code, {"__builtins__": {}}, {"M": M}))
    return run


def rule_k_filter(item, clause, repo_root, siblings=()):
    for base, t in _walk(clause):
        if not _is_pytest(t):
            continue
        targets, k, flags = _pytest_parts(t)
        if not k or "--collect-only" in flags or "--co" in flags:
            continue
        root = _root(repo_root, base)
        if _test_conf_custom(root, repo_root) or "--doctest-modules" in flags:
            continue
        for x in targets:
            if x.endswith(".py") and not os.path.exists(os.path.join(root, x.split("::")[0])):
                break
        else:
            m = _k_matcher(k)
            if m is None:
                continue
            terms = [w for w in re.findall(r"[^\s()]+", k) if w not in ("and", "or", "not")]
            if not any("::" in x for x in targets) and _lead_is_test(item):
                continue                    # the item writes tests: a filter selecting a test it has yet to add may pass later (an explicit ::node id fixes the selection, so no excuse then)
            ents, nfiles = _collect_tests(root, targets)
            ents = _restrict_nodeids(ents, targets)
            if not ents:
                continue
            if any(m(n, fz) for _r, n, fz, _id in ents):
                continue
            single = len(terms) == 1 and len(re.findall(r"[^\s()]+", k)) == 1 and terms[0].lower().startswith("test_")
            if single:
                return _res(SUSPECT, "TEST_NAME_DOES_NOT_EXIST: pytest -k %s selects no test: no test function/class/module name in %d collected test(s) contains it (rc 5, 'no tests ran')" % (k, len(ents)), "", "TEST_NAME_DOES_NOT_EXIST")
            return _res(SUSPECT, "K_FILTER_ZERO_TESTS: pytest -k %r selects zero of %d collected test(s) (no function/class/module/dir/mark name matches) -> rc 5 'no tests ran'" % (k, len(ents)), "", "K_FILTER_ZERO_TESTS")
    return None


def rule_collect_grep(item, clause, repo_root):
    prev = None
    for base, t, sep in _walk_sep(clause):
        if prev is not None and sep == "|" and t[0] in ("grep", "egrep"):
            ptoks, pbase = prev
            targets, k, flags = _pytest_parts(ptoks)
            ga = _grep_args(t)
            prev = None
            if ga and ("--collect-only" in flags or "--co" in flags) and not k and ptoks[0] != "!":
                pat, specs, gflags = ga
                if specs or gflags & {"v", "c", "L", "z", "P"} or not pat.strip():
                    continue
                root = _root(repo_root, pbase)
                if _test_conf_custom(root, repo_root) or any("::" in x for x in targets):
                    continue
                ents, nf = _collect_tests(root, targets)
                if not ents or _unsafe_pattern(pat):
                    continue
                try:
                    rx = re.compile(re.escape(pat) if "F" in gflags else _bre_to_py(pat, "E" in gflags or t[0] == "egrep"), re.I if "i" in gflags else 0)
                except re.error:
                    continue
                blob = "\n".join(e[3] + "\n" + " ".join(sorted(e[1])) for e in ents)
                if rx.search(blob) or any(e[2] is not None and (pat.lower() in e[2]) for e in ents):
                    continue
                if _lead_is_test(item) and not pat.lstrip("^").startswith("_"):
                    continue                # the item writes tests: a test it adds may carry that word (a leading-underscore name is a helper/fixture, never a collected id)
                return _res(SUSPECT, "COLLECT_ONLY_GREP_HELPER: `pytest --collect-only | grep %s` - %r is not part of any collected test id/name (%d test(s)); collect-only lists tests, not helpers/fixtures" % (pat, pat, len(ents)), "", "COLLECT_ONLY_GREP_HELPER")
            continue
        prev = (t, base) if _is_pytest(t) else None
    return None


# ---- e. ONE_LINER_MISSING_IMPORT
def _free_names(code):
    import builtins
    import symtable
    top = symtable.symtable(code, "<c>", "exec")
    defined, used = set(), set()
    for s in top.get_symbols():
        if s.is_assigned() or s.is_imported() or s.is_namespace() or s.is_parameter():
            defined.add(s.get_name())
        elif s.is_referenced():
            used.add(s.get_name())
    q = list(top.get_children())
    while q:
        tb = q.pop(0)
        for s in tb.get_symbols():
            if s.is_declared_global() and s.is_assigned():
                defined.add(s.get_name())
            elif s.is_global() and s.is_referenced() and not s.is_assigned():
                used.add(s.get_name())
        q += tb.get_children()
    return sorted(n for n in used - defined if not hasattr(builtins, n))


def _always_names(tree):
    """Names loaded on EVERY execution of the one-liner (short-circuit operands, conditional-expression branches, lambda/def bodies, later comprehension clauses and except handlers are skipped:
    a name only reachable behind `x or isinstance(y, Path)` never raises when x is true)."""
    import ast
    out = set()

    def visit(n):
        if isinstance(n, ast.Name):
            if isinstance(n.ctx, ast.Load):
                out.add(n.id)
            return
        if isinstance(n, ast.BoolOp):
            visit(n.values[0])
            return
        if isinstance(n, ast.IfExp):
            visit(n.test)
            return
        if isinstance(n, (ast.Lambda, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            return
        if isinstance(n, (ast.ListComp, ast.SetComp, ast.GeneratorExp, ast.DictComp)):
            visit(n.generators[0].iter)
            return
        if isinstance(n, ast.If):
            visit(n.test)
            return
        if isinstance(n, (ast.For, ast.AsyncFor)):
            visit(n.iter)
            return
        if isinstance(n, ast.While):
            visit(n.test)
            return
        if isinstance(n, ast.Try):
            for b in n.body:
                visit(b)
            return
        for c in ast.iter_child_nodes(n):
            visit(c)
    visit(tree)
    return out


def rule_one_liner_import(clause, repo_root):
    import ast
    for base, t in _walk(clause):
        code = _py_c(t)
        if not code or len(code) > MAX_LINE or "import *" in code:
            continue
        try:
            tree = ast.parse(code)
            always = _always_names(tree)
            free = [n for n in _free_names(code) if n in always]
        except (SyntaxError, ValueError, RecursionError):
            continue
        if free:
            return _res(SUSPECT, "ONE_LINER_MISSING_IMPORT: the python -c one-liner uses %s but never imports/defines %s -> NameError" % (", ".join(free[:4]), "it" if len(free) == 1 else "them"), "", "ONE_LINER_MISSING_IMPORT")
    return None


# ---- f. NODEID_WRONG_FILE (+ vitest/jest file) and TEST_NAME_DOES_NOT_EXIST for vitest -t
_NODEID_UNEXPANDED = re.compile(r"[*?\[{$~`]")
_CREATE_TEST_STEP = re.compile(r"\b(?:create|add)\s+(?:the\s+|a\s+|new\s+)*test\s+files?\b", re.I)   # staged flow: a 'Create test file' step makes the VERIFY target later


def rule_nodeid_file(item, clause, repo_root, siblings=()):
    for base, t in _walk(clause):
        if not _is_pytest(t):
            continue
        targets, k, flags = _pytest_parts(t)
        root = _root(repo_root, base)
        for x in targets:
            rel = x.split("::", 1)[0]
            if not rel.endswith(".py") or os.path.isabs(rel) or os.path.exists(os.path.join(root, rel)):
                continue
            if _NODEID_UNEXPANDED.search(rel):
                continue                    # glob / brace / $VAR / ~ / backtick: the shell expands it, never a literal missing file
            if not base and _find_sub(repo_root, rel):
                continue                    # TP1 owns "exists only under a subdir"
            bn = os.path.basename(rel)
            if _names_it(item, bn, rel) or _lead_is_test(item) or any(_CREATE_TEST_STEP.search(_head(sb)) for sb in siblings if sb != item) or any(bn in sb and sb != item and _CREATE_WORDS.search(_head(sb)) for sb in siblings):
                continue                    # the item (or an open sibling) creates that file
            where = "exists at %s from the repo root but not from %s/" % (rel, base) if base and os.path.exists(os.path.join(repo_root, rel)) else "does not exist on this tree"
            return _res(SUSPECT, "NODEID_WRONG_FILE: pytest target %s %s and the item does not create it (pytest rc 4 'file or directory not found')" % (rel, where), "", "NODEID_WRONG_FILE")
    return None


def _vitest_titles(src):
    if "${" in src or ".each" in src:
        return None
    tests = [m.group(2) for m in re.finditer(r"\b(?:it|test)(?:\.(?:only|skip|concurrent|todo))?\s*\(\s*(['\"`])((?:\\.|(?!\1).)*)\1", src)]
    desc = [m.group(2) for m in re.finditer(r"\bdescribe(?:\.(?:only|skip|concurrent))?\s*\(\s*(['\"`])((?:\\.|(?!\1).)*)\1", src)]
    if "`" in "".join(tests + desc):
        return None
    return tests, desc


def rule_vitest_t(item, clause, repo_root):
    for base, t in _walk(clause):
        j = next((i for i, a in enumerate(t[:5]) if a == "vitest" or a.endswith("/vitest")), None)
        if j is None:
            continue
        pat, files, i = None, [], j + 1
        while i < len(t):
            a = t[i]
            if a in ("-t", "--testNamePattern") and i + 1 < len(t):
                pat = t[i + 1]
                i += 2
                continue
            if a.startswith("--testNamePattern="):
                pat = a.split("=", 1)[1]
            elif not a.startswith("-") and re.search(r"\.[cm]?[jt]sx?$", a):
                files.append(a)
            i += 1
        if pat is None or len(files) != 1 or len(pat) > 200:
            continue
        p = os.path.join(_root(repo_root, base), files[0])
        if not os.path.isfile(p) or os.path.getsize(p) > MAX_FILE_BYTES:
            continue
        titles = _vitest_titles(open(p, errors="replace").read())
        if titles is None or not titles[0]:
            continue
        tests, desc = titles
        if _unsafe_pattern(pat):
            continue
        try:
            rx = re.compile(pat)
        except re.error:
            rx = re.compile(re.escape(pat))
        cands = list(tests) + [d + " " + x for d in desc[:60] for x in tests[:200]]
        if any(rx.search(c) for c in cands):
            continue
        if _lead_is_test(item):
            continue
        return _res(SUSPECT, "TEST_NAME_DOES_NOT_EXIST: vitest -t %r matches none of the %d test title(s) in %s -> 'No test found' / all skipped" % (pat, len(tests), files[0]), "", "TEST_NAME_DOES_NOT_EXIST")
    return None


# ---- h. DIRTY_PATH
_STD_FALLBACK = {"os", "sys", "re", "json", "unittest", "asyncio", "collections", "itertools", "functools", "pathlib", "subprocess", "typing", "dataclasses", "http", "importlib", "inspect", "logging", "math", "random", "shutil", "sqlite3", "tempfile", "time", "urllib", "uuid", "xml", "zipfile", "argparse", "ast", "base64", "csv", "datetime", "decimal", "enum", "glob", "hashlib", "io", "pickle", "platform", "secrets", "signal", "socket", "ssl", "string", "textwrap", "threading", "traceback", "venv", "compileall", "py_compile", "pydoc", "timeit", "trace", "doctest", "zoneinfo"}
_STD_MODS = set(getattr(sys, "stdlib_module_names", ())) | _STD_FALLBACK | {"pytest", "pip", "ruff", "mypy", "black", "flake8", "alembic", "uvicorn", "pylint", "coverage", "build", "isort", "bandit", "venv", "http", "json", "pyright", "playwright", "behave", "tox", "nox", "pre_commit", "poetry", "mkdocs", "sphinx"}


def _mod_exists(root, mod):
    p = os.path.join(root, *mod.split("."))
    return os.path.isfile(p + ".py") or os.path.isdir(p)


def rule_dirty_path(item, clause, repo_root):
    for base, t in _walk(clause):
        t2 = t[1:] if t and t[0] == "!" else t
        if not t2 or not _PYEXE.search(t2[0]):
            continue
        root = _root(repo_root, base)
        mods = []
        if len(t2) > 2 and t2[1] == "-m":
            if t2[2] == "unittest":
                mods = [a for a in t2[3:] if re.match(r"^[A-Za-z_][\w.]*$", a) and "." in a]
            elif t2[2] not in _STD_MODS and re.match(r"^[A-Za-z_][\w.]*$", t2[2]):
                mods = [t2[2]]
        elif len(t2) > 1 and not t2[1].startswith("-") and t2[1].endswith(".py"):
            rel = t2[1]
            if not os.path.isabs(rel) and not os.path.exists(os.path.join(root, rel)):
                if _names_it(item, os.path.basename(rel), rel):
                    continue                # the item names that script: it is the thing being created
                return _res(SUSPECT, "DIRTY_PATH: VERIFY runs script %s which does not exist from %s and the item does not create it" % (rel, base or "the repo root"), "", "DIRTY_PATH")
            continue
        for mod in mods:
            parts = mod.split(".")
            if parts[0] in _STD_MODS:
                continue
            k = 0                           # longest prefix that resolves to a module file or package dir
            while k < len(parts) and _mod_exists(root, ".".join(parts[:k + 1])):
                if os.path.isfile(os.path.join(root, *parts[:k + 1]) + ".py"):
                    k = len(parts)
                    break
                k += 1
            if k >= len(parts):
                continue                    # resolves (the tail is a class / test attribute)
            miss = "/".join(parts[:k + 1])
            if _names_it(item, miss) and _CREATE_WORDS.search(_head(item)):
                continue                    # the item creates exactly that module path
            if k > 0 or (parts[-1].startswith("test") and not _mod_exists(repo_root, mod)):
                return _res(SUSPECT, "DIRTY_PATH: VERIFY runs module %s but %s(.py) does not exist from %s (ModuleNotFoundError / 'No module named')" % (mod, miss, base or "the repo root"), "", "DIRTY_PATH")
    return None


def _all_rules(item_line, clause, repo_root, state_dir, siblings):
    """every rule's verdict in a fixed order (the Q2 rules first, so the first SUSPECT keeps meaning what it always meant)."""
    fns = (lambda: rule_ml1(clause, repo_root), lambda: rule_tp1(clause, repo_root), lambda: rule_ts1(clause, repo_root, state_dir),
           lambda: rule_pn1(item_line, clause, repo_root, siblings), lambda: rule_neggrep1(item_line, clause, repo_root),
           lambda: rule_backend_import_root(clause, repo_root), lambda: rule_routes_path_attr(clause, repo_root),
           lambda: rule_k_filter(item_line, clause, repo_root, siblings), lambda: rule_collect_grep(item_line, clause, repo_root),
           lambda: rule_one_liner_import(clause, repo_root), lambda: rule_nodeid_file(item_line, clause, repo_root, siblings),
           lambda: rule_vitest_t(item_line, clause, repo_root), lambda: rule_dirty_path(item_line, clause, repo_root))
    out = []
    for f in fns:
        try:
            r = f()
        except Budget:
            raise
        except Exception as e:      # one rule's bug never hides the others or leaks
            r = None
        if r:
            out.append(r)
    return out


def lint_verify(item_line, repo_root, state_dir=None, siblings=(), _all=False):
    """_all=False (default, every legacy caller): the first of the five Q2 rules that fires, as always. _all=True (lint_all): [every rule's verdict incl. the q-verify-shapes rules]."""
    armed = False
    old = None
    try:
        _DEADLINE[0] = _time.monotonic() + BUDGET_S
        try:
            old = signal.signal(signal.SIGALRM, _alarm)
            signal.setitimer(signal.ITIMER_REAL, BUDGET_S)
            armed = True
        except (ValueError, AttributeError, OSError):
            pass                            # non-main thread / no SIGALRM: the cooperative deadline in _count still applies
        return _lint_verify(item_line, repo_root, state_dir, siblings, _all)
    except Budget:
        return _res("unknown", "lint-budget-exceeded")
    except Exception as e:
        return _res(OK, "lint-error:%s" % type(e).__name__)
    finally:
        _DEADLINE[0] = 0.0
        if armed:
            try:
                signal.setitimer(signal.ITIMER_REAL, 0)
                signal.signal(signal.SIGALRM, old if old is not None else signal.SIG_DFL)
            except Exception:
                pass


def _lint_verify(item_line, repo_root, state_dir=None, siblings=(), _all=False):
    try:
        clause = extract_verify(item_line)
        if not clause:
            return [] if _all else _res()
        if _all:
            return _all_rules(item_line, clause, repo_root, state_dir, siblings)
        for r in (rule_ml1(clause, repo_root), rule_tp1(clause, repo_root), rule_ts1(clause, repo_root, state_dir), rule_pn1(item_line, clause, repo_root, siblings), rule_neggrep1(item_line, clause, repo_root)):
            if r:
                return r
    except Budget:
        raise
    except Exception as e:   # a linter bug must never leak into the queue
        return [] if _all else _res(OK, "lint-error:%s" % type(e).__name__)
    return [] if _all else _res()


def lint_all(item_line, repo_root, state_dir=None, siblings=()):
    """-> [result] for EVERY rule that fires (the five Q2 rules + the q-verify-shapes rules): shadow journal, replay, park. [] when nothing fires, the budget is exhausted or anything errors."""
    r = lint_verify(item_line, repo_root, state_dir, siblings, _all=True)
    return r if isinstance(r, list) else []          # a dict = budget exhausted / linter error: no findings


def _h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:12]


def _state(state_dir):
    return state_dir or os.environ.get("OVN_STATE_DIR") or os.path.join(HERE, "state")


def _shadow_log_new(item_line, repo_root, repo, state_dir, source, siblings):
    """q-verify-shapes: one journal row per NEW (repo, item, rule) finding of the NEW_RULES (same files / row shape / dedupe as shadow_log). Never raises."""
    try:
        res = [r for r in lint_all(item_line, repo_root, state_dir, siblings) if r["verdict"] == SUSPECT and r["rule"] in NEW_RULES]
        if not res:
            return
        sd = _state(state_dir)
        os.makedirs(sd, exist_ok=True)
        repo = repo or os.path.basename(os.path.abspath(repo_root))
        seen = os.path.join(sd, "verify_lint.seen")
        old = set()
        try:
            old = set(open(seen).read().split("\n"))
        except OSError:
            pass
        log = os.environ.get("OVN_VERIFY_LINT_LOG") or os.path.join(sd, "verify_lint.jsonl")
        for r in res:
            key = "%s %s %s" % (repo, _h(item_line), r["rule"])
            if key in old:
                continue
            old.add(key)
            with open(seen, "a") as f:
                f.write(key + "\n")
            row = {"ts": _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime()), "repo": repo, "src": source, "item": _h(item_line), "rule": r["rule"],
                   "reason": r["reason"], "suggested_verify": r["suggested_verify"], "line": item_line.strip()[:240]}
            with open(log, "a") as f:
                f.write(json.dumps(row) + "\n")
    except Exception:
        pass


def shadow_log(item_line, repo_root, repo=None, state_dir=None, source="scan", siblings=()):
    """lint one item; append a row for a NEW (repo,item,rule) finding. Returns the result. Never raises; writes nothing in mode off."""
    if mode() == "off":
        return _res()
    _shadow_log_new(item_line, repo_root, repo, state_dir, source, siblings)   # q-verify-shapes rules (own findings; the legacy rows below are unchanged)
    res = lint_verify(item_line, repo_root, state_dir, siblings)
    if res["verdict"] != SUSPECT:
        return res
    try:
        sd = _state(state_dir)
        os.makedirs(sd, exist_ok=True)
        repo = repo or os.path.basename(os.path.abspath(repo_root))
        key = "%s %s %s" % (repo, _h(item_line), res["rule"])
        seen = os.path.join(sd, "verify_lint.seen")
        old = set()
        try:
            old = set(open(seen).read().split("\n"))
        except OSError:
            pass
        if key in old:
            return res
        with open(seen, "a") as f:
            f.write(key + "\n")
        log = os.environ.get("OVN_VERIFY_LINT_LOG") or os.path.join(sd, "verify_lint.jsonl")
        import time
        row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": repo, "src": source, "item": _h(item_line), "rule": res["rule"],
               "reason": res["reason"], "suggested_verify": res["suggested_verify"], "line": item_line.strip()[:240]}
        with open(log, "a") as f:
            f.write(json.dumps(row) + "\n")
    except Exception:
        pass
    return res


def park_cycle(outcomes, repo, prog_path, repo_root, state_dir, now, n=2, hours=48.0):
    """OVN_VERIFY_LINT_PARK hook (the item guard calls it right after record_outcome; the guard itself checks OVN_VERIFY_LINT_PARK=on). Trips when the item the cycle just worked has
    >= n bad picks (already-done / landed-uncredited, since its last credited landing) AND its open line carries a verdict from PARK_RULES (env OVN_VERIFY_LINT_PARK_RULES overrides).
    Reuses ovn_pick_cap (line identification: never parks a guess). Returns {trip,count,rule,line_no,key,why}; never raises."""
    out = {"trip": False, "count": 0, "rule": "", "line_no": 0, "key": "", "why": ""}
    try:
        rules = tuple(x for x in (os.environ.get("OVN_VERIFY_LINT_PARK_RULES") or ",".join(PARK_RULES)).split(",") if x in NEW_RULES)
        if not rules:
            out["why"] = "no-park-rules"
            return out
        sys.path.insert(0, HERE)
        import ovn_pick_cap as pc
        kinds = tuple(x for x in (os.environ.get("OVN_VERIFY_LINT_PARK_KINDS") or "already-done,landed-uncredited").split(",") if x in pc.BAD_KINDS) or pc.DEFAULT_KINDS
        rows = pc.load(outcomes)
        r = pc.cycle(rows, repo, prog_path, now, n, hours, kinds)
        out.update({"count": r["count"], "line_no": r["line_no"], "key": r["key"], "why": r["why"]})
        if not r["trip"] or not r["line_no"]:
            return out
        with open(prog_path, errors="replace") as f:
            line = f.read().split("\n")[r["line_no"] - 1]
        sib = list(open_items(prog_path, False))
        hit = [x for x in lint_all(line, repo_root, state_dir, sib) if x["verdict"] == SUSPECT and x["rule"] in rules]
        if hit:
            out.update({"trip": True, "rule": hit[0]["rule"], "why": hit[0]["reason"][:160]})
        else:
            out["why"] = "no-park-verdict"
    except Exception as e:
        out.update({"trip": False, "why": "error:%s" % type(e).__name__})
    return out


def _replay_items(path, default_root, trees):
    """replay corpus: (item_line, repo_root, repo). A CLAUDE_QUEUE*.md file (the parked-to-CLAUDE corpus; open AND closed lines, de-duplicated by text) maps each `[CLAUDE] repo/ - ` line to trees/<repo>."""
    if os.path.basename(path).startswith("CLAUDE_QUEUE") and trees:
        seen = set()
        for ln in open(path, errors="replace"):
            m = re.match(r"- \[[ xX]\] .*?\[CLAUDE\] ([\w.-]+)/", ln)
            if not m or "VERIFY" not in ln:
                continue
            body = re.sub(r"<!--.*$", "", ln.rstrip("\n")).strip()
            key = (m.group(1), body)
            tr = os.path.join(trees, m.group(1))
            if key in seen or not os.path.isdir(tr):
                continue
            seen.add(key)
            yield body, tr, m.group(1)
        return
    for it in open_items(path):
        yield it, default_root, None


def open_items(path, with_verify=True):
    try:
        for ln in open(path, errors="replace"):
            if ln.startswith("- [ ] ") and (not with_verify or "VERIFY" in ln):
                yield ln.rstrip("\n")
    except OSError:
        return


def main(argv):
    a = argv[1:]
    if not a:
        print(__doc__)
        return 2

    def opt(name, default=None):
        if name in a:
            i = a.index(name)
            v = a[i + 1] if i + 1 < len(a) else default
            del a[i:i + 2]
            return v
        return default
    cmd = a.pop(0)
    root, state, repo = opt("--repo-root"), opt("--state"), opt("--repo")
    if cmd == "check":
        print(json.dumps(lint_verify(a[0], root or os.getcwd(), state)))
        return 0
    if cmd == "shadow":
        sib = list(open_items(a[0], False))
        for it in open_items(a[0]):
            shadow_log(it, root or os.path.dirname(os.path.abspath(a[0])), repo, state, "planner", sib)
        return 0
    if cmd == "replay":
        trees = opt("--trees")
        tot = {"items": 0, "SUSPECT": 0}
        by = {}
        for f in a:
            rr = os.path.join(trees, os.path.basename(os.path.dirname(os.path.abspath(f)))) if trees else os.path.dirname(os.path.abspath(f))
            sib = list(open_items(f, False))
            for it, rr2, rname in _replay_items(f, rr, trees):
                it_root = rr2
                tot["items"] += 1
                rs = [r for r in lint_all(it, it_root, state, sib) if r["verdict"] == SUSPECT]
                if rs:
                    tot["SUSPECT"] += 1
                parked = bool(re.search(r"AUTO-SKIP|HUMAN-ONLY|\[CLAUDE\]|BLOCKED", it))
                for r in rs:
                    by.setdefault(r["rule"], []).append((rname or os.path.basename(os.path.dirname(os.path.abspath(f))), "parked" if parked else "doable", _h(re.sub(r"^.*?(?=\[T\d\])", "", it, count=1)) , it[:110], r["reason"][:200]))
        print(json.dumps({"totals": tot, "by_rule": {k: len(v) for k, v in by.items()},
                          "by_rule_doable": {k: sum(1 for x in v if x[1] == "doable") for k, v in by.items()}}))
        for k, v in by.items():
            for x in v:
                print(k, *x, sep=" | ")
        return 0
    if cmd == "park-cycle":     # item-guard hook (OVN_VERIFY_LINT_PARK=on): TSV trip count rule line_no key why
        now = int(opt("--now", str(int(_time.time()))))
        r = park_cycle(opt("--outcomes", ""), repo or "", opt("--prog", ""), root or os.getcwd(), state, now, int(opt("--n", "2") or 2), float(opt("--hours", "48") or 48))
        print("\t".join([str(int(r["trip"])), str(r["count"]), r["rule"] or "-", str(r["line_no"]), r["key"], r["why"] or "-"]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
