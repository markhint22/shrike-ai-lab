#!/usr/bin/env python3
"""scripts/ovn_verify_shape_lint.py - VERIFY SHAPE linter (package D1, 2026-10-18).

Audits found the decomposer / backlog generator emitting VERIFY clauses that can NEVER pass (or never fail) no matter what the model edits, so the item burns
cycles until the churn guard parks it. This module classifies one VERIFY clause as

  OK              nothing wrong found
  UNSATISFIABLE   can never exit 0 once the work is done      (S1 grep -n | grep <fn name>, S2 -A/-B window shorter than the real distance, S5 typed-signature grep)
  VACUOUS         always exits 0 (or never reflects the code) (V1 `| wc -l` / display-only tail stage, V2 `|| true|echo` tail, V3 `; echo`, V4 `&& echo A || echo B`)
  UNRUNNABLE      cannot execute as written                   (U1 `cd D && ... D/x` double prefix, U2 pytest path relative to the wrong root, U3 billwatch_backend.app import)

P5 (2026-10-21) shapes, all SHADOW-measured like the rest (found in 24 h of verify_gate_shadow.log FAIL rows): S6 single-line grep chaining a decorator to the def below it, S7 inverted
`raises` polarity (a python -c that calls the very thing the item says raises, with no try/except; a clause that is literally `pytest.raises(...)`), S8 conftest.py as a pytest target
(collects nothing, rc 5), S9 `Model()` instantiated with no args while the class has required fields, U4 `backend.app...` import prefix when the backend's own modules import `app...`
(ModuleNotFoundError at the clause itself); plus rewrites for `test ! -f X && echo .. || echo ..` (V4) and `| wc -l returns N` (V1 -> -eq N, never a presence -ge 1).

P8 (2026-10-26) shapes, own switch OVN_VERIFY_ASYNC_LINT=off|shadow|enforce (default shadow; independent of OVN_VERIFY_LINT_P5): A1 `ast.FunctionDef` searched for a function that is `async def`
in the tree/item (IndexError on every run: gitlark 8, billwatch 4, iptv 14, TAA 8 items all-time), H1 `python -c 'from iptv-backend.app... import x'` (a hyphen in a module path is a SyntaxError
at the clause itself: iptv 16, billwatch 8).

with a REASON and, where it can be done mechanically, a REWRITE (a full replacement clause). The linter is PURE: it parses text (quote-aware) and, when given a repo tree,
READS files to confirm a finding; it never executes a VERIFY. Every rule only fires on evidence; with no tree the tree-dependent rules (S2, U2, S5) stay silent.

Modes (env OVN_VERIFY_LINT = off | shadow | enforce; default shadow):
  off      nothing runs, nothing is logged
  shadow   findings are appended to state/verify_shape_lint.log (JSON lines) and ONE summary line per run goes to state/alerts.log; the item text is never changed
  enforce  at item creation a flagged item is REWRITTEN when every finding has a rewrite and the rewritten clause re-lints OK, otherwise the item is DROPPED
           (the caller quarantines/reports it); an item without findings is untouched.
(OVN_VERIFY_LINT is shared with ovn_verify_malformed's shadow lint, which treats every mode except `off` as shadow, so `enforce` never changes its behaviour.)
Env: OVN_VERIFY_SHAPE_LOG (log path), OVN_VERIFY_ALERTS_LOG (alerts path).

CLI
  ovn_verify_shape_lint.py check '<verify clause>' [--tree DIR]          classify one clause (JSON)
  ovn_verify_shape_lint.py filter [--tree DIR] [--repo NAME] [--dropped FILE]   stdin item lines -> stdout kept lines per mode (planner / supply hook)
  ovn_verify_shape_lint.py audit FILE_OR_DIR... [--tree DIR] [--all] [--json F] [--md F] [--limit N]   classify the VERIFY of every open item (DIR = a repo root:
                                                    OVERNIGHT_PROGRESS.md + backlog files next to it; --all includes [x] items)
"""
import bisect
import contextlib
import io
import json
import os
import re
import shlex
import signal
import sys
import threading
import time
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
OK, UNSAT, VACUOUS, UNRUN = "OK", "UNSATISFIABLE", "VACUOUS", "UNRUNNABLE"
_RANK = {OK: 0, VACUOUS: 1, UNRUN: 2, UNSAT: 3}
_OPS = ("&&", "||", ";", "|")


def mode():
    m = (os.environ.get("OVN_VERIFY_LINT", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "enforce") else "shadow"


# ---------------------------------------------------------------- parsing
def extract_verify(line):
    """(clause, start, end) of the VERIFY clause inside an item line, or None. Backticked form first, then the bare `VERIFY: cmd. (cat:` form."""
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if m:
        return m.group(1), m.start(1), m.end(1)
    m = re.search(r"VERIFY:\s*(.+?)\.?\s*\(cat:", line)
    if m:
        return m.group(1).strip(), m.start(1), m.start(1) + len(m.group(1).rstrip())
    return None


def split_stages(text):
    """Quote-aware split on top-level && || ; |. Returns [(op_before, stage_text, start, end)]. Raises ValueError on unbalanced quotes / substitutions."""
    out, i, n, start, op = [], 0, len(text), 0, ""
    q = None
    depth = 0
    while i < n:
        c = text[i]
        if q:
            if c == "\\" and q == '"' and i + 1 < n:
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            i += 2
            continue
        if c in "'\"":
            q = c
            i += 1
            continue
        if text.startswith("$(", i) or c == "(":
            depth += 1
            i += 2 if c == "$" else 1
            continue
        if c == ")" and depth:
            depth -= 1
            i += 1
            continue
        if depth == 0:
            for o in _OPS:
                if text.startswith(o, i):
                    # `>&2`, `2>&1`, `&>` are redirections, not operators
                    if o == "|" and i + 1 < n and text[i + 1] == "|":
                        continue
                    seg = text[start:i]
                    out.append((op, seg, start, i))
                    op, i = o, i + len(o)
                    start = i
                    break
            else:
                i += 1
                continue
            continue
        i += 1
    if q or depth:
        raise ValueError("unbalanced")
    out.append((op, text[start:], start, n))
    return out


def _argv(seg):
    try:
        return shlex.split(seg)
    except ValueError:
        return []


def _pipelines(stages):
    """Group stages into pipelines: list of lists of stage tuples (a pipeline = stages joined by `|`)."""
    pls, cur = [], []
    for st in stages:
        if st[0] == "|" and cur:
            cur.append(st)
        else:
            if cur:
                pls.append(cur)
            cur = [st]
    if cur:
        pls.append(cur)
    return pls


def _is_grep(argv):
    return bool(argv) and os.path.basename(argv[0]) in ("grep", "egrep", "fgrep", "rg")


def _grep_parse(argv):
    """-> dict(flags=set of single letters, long=set, pattern, files, ctx={'A':n,'B':n}) or None. Handles -e PAT, -A5, -A 5, -nE, --regexp=."""
    if not _is_grep(argv):
        return None
    flags, long_, ctx, pat, files = set(), set(), {}, None, []
    i, a = 1, argv
    endopts = False
    while i < len(a):
        t = a[i]
        if not endopts and t == "--":
            endopts = True
        elif not endopts and t.startswith("--"):
            if t.startswith("--regexp="):
                pat = t.split("=", 1)[1]
            elif t.startswith("--after-context="):
                ctx["A"] = int(t.split("=", 1)[1] or 0) if t.split("=", 1)[1].isdigit() else 0
            elif t.startswith("--before-context="):
                ctx["B"] = int(t.split("=", 1)[1] or 0) if t.split("=", 1)[1].isdigit() else 0
            else:
                long_.add(t)
        elif not endopts and t.startswith("-") and len(t) > 1:
            j = 1
            while j < len(t):
                ch = t[j]
                if ch in "ABC":
                    rest = t[j + 1:]
                    if rest.isdigit():
                        val = int(rest)
                    elif i + 1 < len(a) and a[i + 1].isdigit():
                        val = int(a[i + 1])
                        i += 1
                    else:
                        val = 0
                    if ch in "AC":
                        ctx["A"] = val
                    if ch in "BC":
                        ctx["B"] = val
                    break
                if ch == "e":
                    rest = t[j + 1:]
                    if rest:
                        pat = rest
                    elif i + 1 < len(a):
                        pat = a[i + 1]
                        i += 1
                    break
                if ch in "mf":
                    break
                flags.add(ch)
                j += 1
        else:
            if pat is None:
                pat = t
            else:
                files.append(t)
        i += 1
    if pat is None:
        return None
    return {"flags": flags, "long": long_, "pattern": pat, "files": files, "ctx": ctx}


# a group that repeats AND itself contains a quantifier or an alternation: the classic catastrophic-backtracking shapes ((a+)+, (a|aa)+, (a*)*). Such a model-written pattern is
# never compiled (the rule stays silent); the time budget below is the second line of defence for anything this heuristic misses.
_REDOS = re.compile(r"\((?:[^()\\]|\\.)*[+*|](?:[^()\\]|\\.)*\)\s*(?:[+*]|\{\d*,\d*\})")


def _py_regex(pat, flags, long_):
    """Approximate a grep pattern as a python regex (BRE/ERE/-F); None when it cannot be done safely."""
    try:
        if "F" in flags or "--fixed-strings" in long_:
            rx = re.escape(pat)
        elif "E" in flags or "--extended-regexp" in long_ or "P" in flags:
            rx = pat
        else:  # BRE: \| \( \) \{ \} \+ \? are operators, bare ( ) | + ? { } are literals
            rx = re.sub(r"\\([|(){}+?])|([|(){}+?])", lambda m: m.group(1) if m.group(1) else "\\" + m.group(2), pat)
        if _REDOS.search(rx) or len(rx) > 500:
            return None
        return re.compile(rx, re.I if "i" in flags else 0)
    except re.error:
        return None


def _is_literal(pat):
    return not re.search(r"[\\.*+?|(){}\[\]^$]", pat)


_MAX_READ = int(os.environ.get("OVN_VERIFY_LINT_MAX_READ", str(2 * 1024 * 1024)) or 2097152)
_MAX_LINE = 4000


def _read(tree, rel):
    """Lines of a file under `tree`, or None. Only a REGULAR file that really lives inside the tree and is at most _MAX_READ bytes is read: an absolute path, `..` escape, symlink
    out of the tree, FIFO, /dev/zero, /dev/stdin or a huge file (a model-written VERIFY names the path) is refused instead of hanging the caller. Lines are capped at _MAX_LINE chars."""
    try:
        if not tree or not rel or os.path.isabs(rel) or rel.startswith("~"):
            return None
        root = os.path.realpath(tree)
        real = os.path.realpath(os.path.join(root, rel))
        if real != root and not real.startswith(root + os.sep):
            return None
        st = os.stat(real)
        import stat as _stat
        if not _stat.S_ISREG(st.st_mode) or st.st_size > _MAX_READ:
            return None
        with open(real, encoding="utf-8", errors="replace") as f:
            return [l[:_MAX_LINE] for l in f.read(_MAX_READ + 1).split("\n")]
    except (OSError, ValueError):
        return None


class LintTimeout(Exception):
    """Raised by the time budget; an Exception subclass so lint_verify's never-raises guard turns it into a fail-open OK."""


def _budget_s():
    try:
        return float(os.environ.get("OVN_VERIFY_LINT_BUDGET_S", "2"))
    except ValueError:
        return 2.0


@contextlib.contextmanager
def _time_budget(seconds):
    """Wall-clock budget for one lint (SIGALRM/setitimer; python's re checks signals, so a runaway regex is interruptible). A no-op off the main thread, without setitimer, or when
    another interval timer is already armed (never steal the host process's alarm). seconds <= 0 disables it."""
    armed = False
    old_h = None
    try:
        if seconds and seconds > 0 and hasattr(signal, "setitimer") and threading.current_thread() is threading.main_thread():
            if signal.getitimer(signal.ITIMER_REAL)[0] == 0:
                def _h(signum, frame):
                    raise LintTimeout("lint exceeded %.1fs budget" % seconds)
                old_h = signal.signal(signal.SIGALRM, _h)
                signal.setitimer(signal.ITIMER_REAL, seconds)
                armed = True
    except (ValueError, OSError):
        armed = False
    try:
        yield
    finally:
        if armed:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old_h if old_h is not None else signal.SIG_DFL)


def _find(f, cls, code, reason, rewrite=None, p5_rewrite=False):
    r = {"class": cls, "code": code, "reason": reason, "rewrite": rewrite}
    if p5_rewrite and rewrite:
        r["p5_rewrite"] = True   # the rewrite exists only because of a P5 rule (V1 `wc returns N`, V4 `test` branch): withheld unless OVN_VERIFY_LINT_P5=enforce
    return r


# P5 new shapes + rewrites are gated by their OWN switch, independent of OVN_VERIFY_LINT (which the unproven P5 shapes would otherwise ride along on):
#   OVN_VERIFY_LINT_P5 = off | shadow | enforce; default shadow.  off: P5 findings are not produced.  shadow: produced and logged but never enforced (no drop/rewrite because of them).
#   enforce: P5 findings behave like every other finding (subject to OVN_VERIFY_LINT=enforce).
P5_CODES = frozenset(("S6", "S7", "S8", "S9", "U4"))


def p5_mode():
    m = (os.environ.get("OVN_VERIFY_LINT_P5", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "enforce") else "shadow"


# P8 shapes (A1 async-blind AST search, H1 hyphenated import) have their OWN switch: OVN_VERIFY_ASYNC_LINT = off | shadow | enforce; default shadow.
#   off: not produced.  shadow: produced + logged, never rewritten/dropped.  enforce: behave like every other finding (subject to OVN_VERIFY_LINT=enforce).
P8_CODES = frozenset(("A1", "H1"))


def p8_mode():
    m = (os.environ.get("OVN_VERIFY_ASYNC_LINT", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "enforce") else "shadow"


def _fn_name_shape(s):
    return bool(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{4,}", s)) and ("_" in s or re.search(r"[a-z][A-Z]", s))


# ---------------------------------------------------------------- rules
_GOOD_V = {"pass", "passed", "ok", "okay", "success", "succeeded", "good", "clean"}
_BAD_V = {"fail", "failed", "failure", "bad", "error", "fatal"}
_GOOD_W = _GOOD_V | {"absent", "gone", "removed", "deleted"}
_BAD_W = _BAD_V | {"missing", "present", "still", "remain", "remains", "remaining", "leaked"}
_NEG = re.compile(r"\b(not|no longer|isn't|doesn't|does not|never|without)\b", re.I)


def _msg_polarity(msg):
    """'good' / 'bad' / None for an echo message. A leading verdict token (PASS:, FAIL ...) decides; else whole-word lists; a negation or a mix of both -> None (unclear)."""
    words = re.findall(r"[a-z']+", msg.lower())
    if not words:
        return None
    if words[0] in _GOOD_V:
        return "good"
    if words[0] in _BAD_V:
        return "bad"
    if _NEG.search(msg):
        return None
    g = any(w in _GOOD_W for w in words)
    b = any(w in _BAD_W for w in words) or ("found" in words)
    if g == b:
        return None
    return "good" if g else "bad"


_ZERO_SAYS = re.compile(r"(?:\b(?:returns?|is|are|equals?|gives?|prints?|outputs?|shows?|yields?|be|count)|==|-eq)\s*(?:exactly\s+)?0(?!\d|\.\d)|(?<![\w.])0\s+(?:matches|hits|results|occurrences|lines|references|usages|remaining)\b|\bzero\b", re.I)
_POS_SAYS = re.compile(r"(?:\b(?:returns?|is|are|equals?|should be|should return|at least)|>=?|\u2265|-ge|-gt|-eq)\s*(?:exactly\s+)?[1-9]\d*|\bnon-?zero\b|\bat least one\b|>\s*0", re.I)
_ABSENCE_SAYS = re.compile(r"\b(?:no remaining|none remain\w*|no (?:more|longer|other|leftover|stale|references?|imports?|occurrences?|usages?|uses)|not (?:found|present|exist\w*|referenced|imported)|absent|gone|removed?|delet\w+|dropped?|eliminat\w+|ensure no|without)\b", re.I)


def _wc_expectation(clause, item):
    """The test operator a bare `| wc -l` should become, read from the ITEM TEXT (outside the VERIFY clause): `-eq 0` when the item says the count is 0 / none remain, `-ge 1` for a
    presence check, None (no rewrite: enforce quarantines it) when the polarity is unclear (absence wording without an explicit 0, or both 0 and a positive count). With no item text
    (CLI `check`) the historical presence assumption `-ge 1` is kept."""
    if item is None:
        return "-ge 1"
    text = re.sub(r"`[^`]*`", " ", item.replace(clause, " ", 1))   # backticked code (`stallCount = 0`) is not a statement about the count
    zero, pos, absent = bool(_ZERO_SAYS.search(text)), bool(_POS_SAYS.search(text)), bool(_ABSENCE_SAYS.search(text))
    if zero and not pos:
        return "-eq 0"
    if zero or absent:
        return None
    return "-ge 1"


_WC_WORDS = {"returns", "return", "is", "are", "equals", "equal", "gives", "should", "be", "==", "=", "exactly", "count", "outputs", "prints", "shows", "->", "yields"}


def _rule_tail(clause, stages, pls, tree, item=None):
    out = []
    last = pls[-1]
    ops = [s[0] for s in stages]
    argvs = [_argv(s[1]) for s in stages]
    # V4a: `cmd && exit 1 || exit 0` is an ABSENCE check written long-hand: exit 0 only when cmd FAILED. Its status is already right, but a V2-style `|| exit 0` strip would
    # invert it, so it is classified here and rewritten to the canonical `! ( cmd )`.
    if len(stages) >= 3 and ops[-1] == "||" and ops[-2] == "&&" and argvs[-1][:2] == ["exit", "0"] and len(argvs[-1]) == 2 and argvs[-2][:2] == ["exit", "1"] and len(argvs[-2]) == 2:
        cut = stages[-2][2] - 2
        body = clause[:cut].rstrip()
        # INFORMATIONAL only (class OK, so it is never flagged, counted, logged or rewritten): the status is already right and the long-hand form is a legitimate absence check
        out.append(_find(clause, OK, "V4a", "`cmd && exit 1 || exit 0` is an absence check spelled long-hand (exit 0 iff cmd fails); style note: canonical form is `! ( cmd )`", ("! ( %s )" % body) if body else None))
        return out
    # V4: `cmd && echo A || echo B` - the final executed command is an echo
    if len(stages) >= 3 and ops[-1] == "||" and ops[-2] == "&&" and argvs[-1][:1] in (["echo"], ["printf"]) and argvs[-2][:1] in (["echo"], ["printf"]):
        cut = stages[-2][2] - 2
        body = clause[:cut].rstrip()
        pa, pb = _msg_polarity(" ".join(argvs[-2][1:])), _msg_polarity(" ".join(argvs[-1][1:]))
        rw = None   # polarity unclear -> no rewrite (a guessed rewrite can invert the check); enforce then quarantines the item
        p5rw = False
        if body and pa == "bad" and pb == "good":
            rw = "! ( %s )" % body   # `cmd && echo FAIL || echo PASS` states an ABSENCE check: exit 0 must mean the command did NOT succeed
        elif body and pa == "good" and pb == "bad":
            rw = body
        elif body and _argv(body)[:1] in (["test"], ["["], ["[["]) and not (pb == "good" and pa != "good") and pa != "bad":
            rw = body   # P5: `test ! -f X && echo gone || echo still` - the success branch of a `test` is the intended pass; the bare test is the real check
            p5rw = True
        out.append(_find(clause, VACUOUS, "V4", "`cmd && echo A || echo B` always exits 0: the echo branch decides the status, not the check", rw, p5_rewrite=p5rw))
        return out
    # V2: trailing `|| true|:|echo|printf`
    if len(stages) >= 2 and ops[-1] == "||" and (argvs[-1][:1] in (["true"], [":"], ["echo"], ["printf"], ["exit"]) and (argvs[-1][:1] != ["exit"] or argvs[-1][1:2] == ["0"])):
        cut = stages[-1][2] - 2
        out.append(_find(clause, VACUOUS, "V2", "a trailing `|| %s` forces exit 0, so the clause passes whether or not the check held" % " ".join(argvs[-1][:2]), clause[:cut].rstrip()))
        return out
    # V3: trailing `; echo ...` / `; true`
    if len(stages) >= 2 and ops[-1] == ";" and argvs[-1][:1] in (["echo"], ["true"], [":"], ["printf"]):
        cut = stages[-1][2] - 1
        out.append(_find(clause, VACUOUS, "V3", "a trailing `; %s` makes the clause exit 0 regardless of the check before it" % argvs[-1][0], clause[:cut].rstrip()))
        return out
    # V1: the decisive pipeline ends in a display-only stage (exit status = that stage's, always 0)
    if len(last) >= 2:
        la = _argv(last[-1][1])
        base = os.path.basename(la[0]) if la else ""
        if base in ("wc", "head", "tail", "sort", "uniq", "cat", "nl", "cut", "tr", "tee", "column", "fold") and not (base == "tail" and "-f" in la):
            pipe_start = last[0][2]
            body_end = last[-1][2] - 1
            body = clause[pipe_start:body_end].strip()
            if base == "wc":
                # trailing prose / extra args after wc (`| wc -l returns 2`) make a rewrite broken or a weaker (-ge 1) clause than intended: no rewrite then
                rw = None
                p5rw = False
                extra = [a for a in la[1:] if not a.startswith("-")]
                if not extra:
                    op = _wc_expectation(clause, item)
                    if op:
                        rw = clause[:pipe_start] + 'test "$(%s | %s)" %s' % (body, " ".join(la), op) + clause[last[-1][3]:]
                elif extra[-1].isdigit() and all(w.lower() in _WC_WORDS for w in extra[:-1]):
                    # P5: `| wc -l returns N` states the expected count itself: the rewrite is that exact count (-eq N), never a presence test (-ge 1) - a delete-direction `returns 0` stays 0
                    flags = " ".join(a for a in la if a.startswith("-") or a == la[0])
                    rw = clause[:pipe_start] + 'test "$(%s | %s)" -eq %d' % (body, flags, int(extra[-1])) + clause[last[-1][3]:]
                    p5rw = True
                why = "`| wc` as the last stage always exits 0 (wc counts, it does not test)"
            else:
                rw = clause[:pipe_start] + body + clause[last[-1][3]:]
                p5rw = False
                why = "the clause ends in `| %s`: the pipeline status is that of the display stage (always 0), so the check before it is ignored" % base
            out.append(_find(clause, VACUOUS, "V1", why, rw, p5_rewrite=p5rw))
    return out


_DECL_PREFIX = re.compile(r"\s*(?:async\s+)?(?:def|function|class|func|fn|from|import|export|const|let|var|type|interface|struct|enum|pub|public|private|static|use|require)\b")


def _multi_path_grep(g1, tree):
    """True when the first grep prints a file path in front of each hit (recursive / -H / several files / globs / a directory argument)."""
    if (g1["flags"] & set("rRH")) or (g1["long"] & {"--recursive", "--dereference-recursive", "--with-filename"}) or len(g1["files"]) > 1:
        return True
    for f in g1["files"]:
        if re.search(r"[*?\[]", f) or (tree and os.path.isdir(os.path.join(tree, f))) or f in (".", "./") or f.endswith("/"):
            return True
    return False


def _item_pairs(item, clause, p1, p2):
    """True when one backticked or quoted span of the item text (VERIFY clause removed) contains both p1 and p2 (as literal text)."""
    text = item.replace(clause, " ", 1)
    q1 = re.sub(r"\\(.)", r"\1", p1.lstrip("^")).strip()
    if not q1 or not p2:
        return False
    for m in re.finditer(r"`([^`]+)`|\"([^\"]+)\"|'([^']+)'", text):
        span = m.group(1) or m.group(2) or m.group(3) or ""
        if q1 in span and p2 in span:
            return True
    return False


def _rule_grepn_fn(clause, stages, pls, tree, item=None):
    out = []
    for pl in pls:
        for k in range(len(pl) - 1):
            g1 = _grep_parse(_argv(pl[k][1]))
            g2 = _grep_parse(_argv(pl[k + 1][1]))
            if not g1 or not g2 or g2["files"] or "n" not in g1["flags"] or k != 0 and False:
                continue
            if (g2["flags"] & set("vcLl")) or (g2["long"] & {"--invert-match", "--count", "--files-without-match", "--files-with-matches"}):
                continue   # `| grep -v X` (satisfiable when any line lacks X), -c/-L/-l: not a plain "must contain" filter
            p1, p2 = g1["pattern"], g2["pattern"]
            # the second grep reads grep -n's `LINE:text`; a function NAME is not on the matched line unless p1 contains it
            if not (_is_literal(p2) and _fn_name_shape(p2)) or p2 in p1 or "|" in p1:
                continue
            if g1["ctx"].get("A") or g1["ctx"].get("B"):
                continue
            if _DECL_PREFIX.match(p1):
                continue   # a definition / import line: p2 may be a parameter name or the imported name ON that line (single-line `from m import name`, `def f(x: Query(...))`)
            if _multi_path_grep(g1, tree):
                continue   # -r / -H / several files / a directory: grep prints `path:N:text`, so p2 can match through the PATH
            if item is not None and _item_pairs(item, clause, p1, p2):
                continue   # the item asks to ADD p2 to a line that carries p1 (both inside one quoted/backticked span): after the edit one line holds both
            # tree evidence that the two DO share a line removes the finding
            rx1 = _py_regex(p1, g1["flags"], g1["long"])
            if tree and rx1 and g1["files"]:
                lines = _read(tree, g1["files"][0])
                if lines and any(rx1.search(l) and p2 in l for l in lines):
                    continue
            rw = None
            if tree and g1["files"]:
                lines = _read(tree, g1["files"][0])
                if lines:
                    di = next((i for i, l in enumerate(lines) if re.search(r"\b(def|function|class|func|fn)\s+%s\b" % re.escape(p2), l)), None)
                    if di is not None:
                        hit = next((i for i, l in enumerate(lines) if i > di and rx1 and rx1.search(l)), None)
                        k_win = (hit - di + 2) if hit is not None else 25   # 25 = no anchor in the file yet (the item adds it): a generous, bounded window
                        anchor = ("def %s" % p2) if re.match(r"\s*(async\s+)?def\b", lines[di]) else p2
                        rw = clause[:pl[k][2]] + "grep -n -A %d %s %s | grep -q %s" % (k_win, shlex.quote(anchor), shlex.quote(g1["files"][0]), shlex.quote(p1)) + clause[pl[k + 1][3]:]
            out.append(_find(clause, UNSAT, "S1", "`grep -n %s` prints only the matching line(s) as `N:text`; `%s` looks like an enclosing function name that is not on those lines (and no line carries both), so the second grep cannot match" % (p1, p2), rw))
    return out


def _rule_window(clause, stages, pls, tree, item=None):
    out = []
    if not tree:
        return out
    for pl in pls:
        for k in range(len(pl) - 1):
            g1 = _grep_parse(_argv(pl[k][1]))
            g2 = _grep_parse(_argv(pl[k + 1][1]))
            if not g1 or not g2 or g2["files"] or not (g1["ctx"].get("A") or g1["ctx"].get("B")) or not g1["files"]:
                continue
            lines = _read(tree, g1["files"][0])
            rx1, rx2 = _py_regex(g1["pattern"], g1["flags"], g1["long"]), _py_regex(g2["pattern"], g2["flags"], g2["long"])
            if not lines or not rx1 or not rx2:
                continue
            A, B = g1["ctx"].get("A", 0), g1["ctx"].get("B", 0)
            m1 = [i for i, l in enumerate(lines) if rx1.search(l)]
            if not m1:
                continue
            m2 = [j for j, l in enumerate(lines) if rx2.search(l)]   # computed ONCE: the old m1 x len(lines) scans were quadratic
            if not m2:
                continue   # the target text is not in the file at all: not a window problem (red-before is legitimate)
            ok = any((lambda p: p < len(m2) and m2[p] <= min(len(lines) - 1, i + A))(bisect.bisect_left(m2, max(0, i - B))) for i in m1)
            if ok:
                continue
            fwd, back = [], []
            for i in m1:
                p = bisect.bisect_left(m2, i + A + 1)      # nearest match strictly beyond the -A window
                if p < len(m2):
                    fwd.append(m2[p] - i)
                q = bisect.bisect_right(m2, i - B - 1) - 1  # nearest match strictly before the -B window
                if q >= 0:
                    back.append(i - m2[q])
            if not fwd and not back:
                continue
            if fwd and (not back or min(fwd) <= min(back)):
                d = min(fwd)
                seg = pl[k][1]
                new = re.sub(r"-A\s*%d\b|-A%d\b" % (A, A), "-A %d" % (d + 2), seg, count=1) if g1["ctx"].get("A") else seg
                if new == seg and g1["ctx"].get("A"):
                    new = re.sub(r"-C\s*%d\b|-C%d\b" % (A, A), "-C %d" % (d + 2), seg, count=1)
                rw = clause[:pl[k][2]] + new + clause[pl[k][3]:] if new != seg else None
                out.append(_find(clause, UNSAT, "S2", "grep -A %d window ends %d line(s) before `%s` (nearest match is %d lines after the anchor in %s)" % (A, d - A, g2["pattern"], d, g1["files"][0]), rw))
            else:
                d = min(back)
                seg = pl[k][1]
                new = re.sub(r"-B\s*%d\b|-B%d\b" % (B, B), "-B %d" % (d + 2), seg, count=1)
                rw = clause[:pl[k][2]] + new + clause[pl[k][3]:] if new != seg else None
                out.append(_find(clause, UNSAT, "S2", "grep -B %d window is %d line(s) short of `%s` (nearest match is %d lines before the anchor in %s)" % (B, d - B, g2["pattern"], d, g1["files"][0]), rw))
    return out


def _cd_target(argv):
    if len(argv) == 2 and argv[0] == "cd" and not argv[1].startswith(("/", "~", "-", "$", "..")) and argv[1].strip("./"):
        return argv[1].rstrip("/")
    return None


def _quoted_at(text, pos):
    """True when text[pos] sits inside a '...' or "..." string (quote-aware scan from the start)."""
    q, i = None, 0
    while i < pos:
        c = text[i]
        if q:
            if c == "\\" and q == '"':
                i += 2
                continue
            if c == q:
                q = None
        elif c == "\\":
            i += 2
            continue
        elif c in "'\"":
            q = c
        i += 1
    return q is not None


def _rule_double_prefix(clause, stages, pls, tree, item=None):
    out = []
    for si, st in enumerate(stages):
        d = _cd_target(_argv(st[1]))
        if not d:
            continue
        # scan only the stages up to the NEXT cd (`cd ..`, `cd /abs`, `cd other`): after it the cwd, hence the path meaning, changed
        later = []
        for s2 in stages[si + 1:]:
            if _argv(s2[1])[:1] == ["cd"]:
                break
            later.append(s2)
        if tree and os.path.isdir(os.path.join(tree, d, d)):
            continue
        tok = re.compile(r"(?<![\w./\-])%s/[^\s;&|)]*" % re.escape(d))
        edits = []   # (abs_start, abs_end) of the `d/` prefix to delete: only UNQUOTED path tokens, and in a grep stage only its FILE operands (never the search pattern)
        for s2 in later:
            seg = s2[1]
            g = _grep_parse(_argv(seg))
            files = set(g["files"]) if g else None
            for m in tok.finditer(seg):
                if _quoted_at(seg, m.start()):
                    continue
                if files is not None and m.group(0) not in files:
                    continue
                edits.append((s2[2] + m.start(), s2[2] + m.start() + len(d) + 1))
        if not edits:
            continue
        # a token like `backend/app/x.py` after `cd backend` resolves to backend/backend/app/x.py
        new = clause
        for a0, b0 in sorted(edits, reverse=True):
            new = new[:a0] + new[b0:]
        out.append(_find(clause, UNRUN, "U1", "after `cd %s` the path `%s/...` resolves to %s/%s/... which does not exist (double prefix)" % (d, d, d, d), new))
        break
    return out


_PY_ROOTS = ("backend", "billwatch-backend", "iptv-backend", "api", "server", "src", "app")


def _runner_heals_py_root(clause, tree, sub, missing):
    """Mirror of the verify runner's N4-A retry (lib_verify_clause.sh _verify_py_cwd): a clause that does not start with `cd`, whose missing relative path is under tests/, is re-run
    from the FIRST existing of backend / billwatch-backend / iptv-backend. U2 stays silent exactly when that retry would pick `sub`."""
    if clause.lstrip().startswith("cd ") or not all(p.startswith("tests/") for p in missing):
        return False
    first = next((c for c in ("backend", "billwatch-backend", "iptv-backend") if os.path.isdir(os.path.join(tree, c))), None)
    return first == sub


def _rule_pytest_root(clause, stages, pls, tree, item=None):
    out = []
    if not tree:
        return out
    cwd_rel = ""
    for si, st in enumerate(stages):
        a = _argv(st[1])
        d = _cd_target(a)
        if d:
            cwd_rel = os.path.normpath(os.path.join(cwd_rel, d))
            continue
        if "pytest" not in a and not ("-m" in a and "pytest" in a):
            continue
        paths = [t.split("::")[0] for t in a if not t.startswith("-") and re.search(r"\.py(::|$)|(^|/)tests?/?$", t) and not t.endswith("pytest")]
        if not paths:
            continue
        cwd = os.path.join(tree, cwd_rel)
        missing = [p for p in paths if not os.path.exists(os.path.join(cwd, p))]
        if not missing:
            continue
        cands = set()
        for sub in sorted(os.listdir(tree)) if os.path.isdir(tree) else []:
            sp = os.path.join(tree, sub)
            if os.path.isdir(sp) and not sub.startswith(".") and all(os.path.exists(os.path.join(sp, p)) for p in missing):
                cands.add(sub)
        if cwd_rel == "" and len(cands) == 1 and _runner_heals_py_root(clause, tree, next(iter(cands)), missing):
            break   # lib_verify_clause.sh _verify_py_root/_verify_py_cwd re-runs this clause from <root> on its own: not a defect, nothing to count or rewrite
        if cwd_rel == "" and len(cands) == 1:
            sub = next(iter(cands))
            rw = clause[:st[2]] + "cd %s && " % sub + clause[st[2]:].lstrip() if si == 0 or stages[si][0] == "&&" or True else None
            rw = clause[:st[2]] + (" " if st[2] and clause[st[2] - 1] != " " else "") + "cd %s && " % sub + clause[st[2]:].lstrip()
            out.append(_find(clause, UNRUN, "U2", "pytest path %s does not exist at the repo root but does under %s/ (suite lives there)" % (", ".join(missing), sub), rw))
        elif cwd_rel and not cands and any(os.path.exists(os.path.join(tree, p)) for p in missing):
            out.append(_find(clause, UNRUN, "U2", "pytest path %s does not exist under %s/ but does at the repo root" % (", ".join(missing), cwd_rel), None))
        elif not cands:
            continue   # the file may be created by the item itself
        break
    return out


def _rule_import(clause, stages, pls, tree, item=None):
    out = []
    m = re.search(r"\b([A-Za-z][A-Za-z0-9]*)_backend\.(app|src)\b", clause)
    if not m:
        return out
    root = m.group(1)
    if tree and (os.path.isdir(os.path.join(tree, root + "_backend")) or os.path.isfile(os.path.join(tree, root + "_backend.py"))):
        return out
    hy = root + "-backend"
    if tree and not os.path.isdir(os.path.join(tree, hy)) and os.path.isdir(os.path.join(tree, "backend")):
        hy = "backend"
    fixed = re.sub(r"\b%s_backend\.(app|src)\b" % re.escape(root), r"\1", clause)
    rw = None
    if re.search(r"\bpython3?\b", clause) and not re.search(r"\bcd\b", clause) and (not tree or os.path.isdir(os.path.join(tree, hy))):
        rw = "cd %s && %s" % (hy, fixed)
    out.append(_find(clause, UNRUN, "U3", "`%s_backend.%s` is not an importable package: the project directory is `%s/` and its modules import as `%s...` from inside it" % (root, m.group(2), hy, m.group(2)), rw))
    return out


_SIG = re.compile(r"^(?:async\s+)?def\s+(\w+)\(([^)]*)\)")


def _rule_signature(clause, stages, pls, tree, item=None):
    out = []
    if not tree:
        return out
    for st in stages:
        g = _grep_parse(_argv(st[1]))
        if not g or not g["files"]:
            continue
        pat = g["pattern"]
        if "E" in g["flags"] and "\\(" not in pat:
            continue
        pat_s = pat.replace("\\(", "(").replace("\\)", ")")
        m = _SIG.match(pat_s)
        if not m or not m.group(2).strip() or ":" in m.group(2) or "*" in m.group(2) and False:
            continue
        name = m.group(1)
        params = [p.strip() for p in m.group(2).split(",") if p.strip()]
        if not params or any(not re.fullmatch(r"\*{0,2}\w+(=[^,]+)?", p) for p in params):
            continue
        lines = _read(tree, g["files"][0])
        if not lines:
            continue
        real = next((l.strip() for l in lines if re.match(r"\s*(async\s+)?def\s+%s\(" % re.escape(name), l)), None)
        if not real or pat_s in real or (":" not in real.split(")")[0] and "->" not in real):
            continue   # absent (red-before), already matching, or the real def is untyped too
        rx = r"def %s\(" % re.escape(name) + "".join(r".*\b%s\b" % re.escape(p.lstrip("*").split("=")[0]) for p in params)
        rw = clause[:st[2]] + "grep -qE %s %s" % (shlex.quote(rx), shlex.quote(g["files"][0])) + clause[st[3]:]
        out.append(_find(clause, UNSAT, "S5", "`%s` can never match the typed signature in %s: `%s`" % (pat, g["files"][0], real[:120]), rw))
        break
    return out


# ---------------------------------------------------------------- P5 shapes
_SEP_TAIL = re.compile(r"(?:\.\*|\.\+|\\n|\\s[*+]|\s)+$")


def _rule_decorator_def(clause, stages, pls, tree, item=None):
    """S6: ONE grep pattern that chains a decorator to the def under it (`@router.get.*def name`, `@x\\n def f`). grep matches line by line and a decorator and its def are always on different
    lines, so the clause can never pass (unless grep -z / -P multi-line). Rewrite: a -A window anchored on the decorator, piped to a grep for the def."""
    out = []
    for st in stages:
        g = _grep_parse(_argv(st[1]))
        if not g or not g["files"] or (g["flags"] & set("zP")) or (g["long"] & {"--null-data", "--perl-regexp"}):
            continue
        pat = g["pattern"]
        at = pat.find("@")
        if at < 0:
            continue
        md = re.search(r"(?:(?<![A-Za-z0-9_])|(?<=\\n))(?:async\s+)?def\b", pat[at:])   # `\ndef`: the n of a literal \n is a word char, so a plain \b would miss it
        if not md:
            continue
        cut = at + md.start()
        dec, deff = _SEP_TAIL.sub("", pat[:cut]), pat[cut:]
        dec = _SEP_TAIL.sub("", re.sub(r"\((?:\?:)?async(?:\s|\\s)*[*+]?\)\?$", "", dec))   # `(async )?def` / `(?:async\s+)?def`: the optional async belongs to the def part
        if len(dec) < 2 or dec == "@":
            continue
        E = "E" in g["flags"] or "P" in g["flags"] or "--extended-regexp" in g["long"]
        Fx = "F" in g["flags"] or "--fixed-strings" in g["long"]
        rw = None
        if len(g["files"]) == 1 and not _multi_path_grep(g, tree):
            mode_f = "-F " if Fx else ("-E " if E else "")
            qflag = "-q" + ("F" if Fx else ("E" if E else ""))
            if E and "\\n" in dec:
                dec = dec.replace("\\n", "")
            rw = clause[:st[2]] + (" " if st[2] and clause[st[2] - 1] != " " else "") + "grep %s-A 6 %s %s | grep %s %s" % (mode_f, shlex.quote(dec), shlex.quote(g["files"][0]), qflag, shlex.quote(deff)) + clause[st[3]:]
        out.append(_find(clause, UNSAT, "S6", "one grep pattern `%s` needs the decorator and the `def` on the SAME line, but a decorator always sits on the line above its def: it can never match" % pat[:80], rw))
        break
    return out


def _norm_args(a):
    return re.sub(r"\s+", "", (a or "").replace('"', "'"))


_RAISES_ITEM = re.compile(r"`([A-Za-z_][\w.]*)\(([^`]*)\)`[^`\n]{0,60}?\b(?:raises?|throws?)\b", re.I)


def _rule_raises_polarity(clause, stages, pls, tree, item=None):
    """S7: the item says X raises, the clause treats the exception as failure. (i) the clause IS `pytest.raises(...): ...` prose - not a command (UNRUNNABLE); (ii) a python -c that calls the
    function the item says raises, with no try/except/raises around it: when the work is right the call raises and the clause exits 1 (UNSATISFIABLE). No rewrite (what to assert is the author's call)."""
    out = []
    first = _argv(stages[0][1])[:1] if stages else []
    if first and re.match(r"^(?:pytest|unittest\.TestCase\.assert|self\.assert)?\.?raises?\(|^pytest\.raises\(", first[0]):
        out.append(_find(clause, UNRUN, "S7", "the clause starts with `%s`: that is a python context manager, not a shell command (rc 127)" % first[0][:40], None))
        return out
    if item is None or not re.search(r"\bpython[0-9.]*\s+(?:-\S+\s+)*-c\b|/python[0-9.]*\s+-c\b", clause):
        return out
    if re.search(r"\btry\s*:|\bexcept\b|\braises?\b|assertRaises|\bwith\s+\w+\.raises|suppress\(", clause):
        return out
    text = item.replace(clause, " ", 1)
    for m in _RAISES_ITEM.finditer(text):
        callee = m.group(1).split(".")[-1]
        # the call must be on the FAILING input: the item has to name a literal failing argument list (`f("bogus")`, `f(-1)`) and the clause must call the callee with exactly that list.
        # A symbolic item arg (`parse(x) raises on bad input`) cannot be matched, and a clause that calls with valid input (`parse('3')`) is a normal positive test: silent either way.
        iargs = _norm_args(m.group(2))
        if not iargs or re.fullmatch(r"[A-Za-z_][\w.]*(?:,[A-Za-z_][\w.]*)*", iargs):
            continue
        if len(callee) >= 4 and any(_norm_args(c) == iargs for c in re.findall(r"\b%s\s*\(([^()]*)\)" % re.escape(callee), clause)):
            out.append(_find(clause, UNSAT, "S7", "the item says `%s(...)` raises, but this python -c calls it with no try/except: once the code is right it raises and the clause exits 1" % callee, None))
            break
    return out


def _rule_conftest_target(clause, stages, pls, tree, item=None):
    """S8: `pytest .../conftest.py` collects nothing (rc 5) however correct the fixtures are. Rewrite: run the directory that holds it."""
    out = []
    for st in stages:
        a = _argv(st[1])
        if not any(os.path.basename(t) == "pytest" or t == "pytest" for t in a) or not any(t.split("::")[0].endswith("conftest.py") and not t.startswith("-") for t in a):
            continue
        new = re.sub(r"(?<![\w./-])((?:[\w.-]+/)*)conftest\.py(?:::\S+)?", lambda m: (m.group(1).rstrip("/") or "."), st[1], count=1)
        out.append(_find(clause, UNSAT, "S8", "pytest is pointed at conftest.py: it defines fixtures, collects no tests and exits 5 (no tests collected)",
                         clause[:st[2]] + new + clause[st[3]:] if new != st[1] else None))
        break
    return out


_IMP = re.compile(r"\bfrom\s+([\w.]+)\s+import\s+([\w\s,]+)")


def _required_fields(tree_mod_lines, cls, depth=0):
    """Names of required (no default) fields of a pydantic model / dataclass `cls` defined in the module source, or None when it cannot be told (own __init__, unparsable, unknown base)."""
    import ast
    try:
        mod = ast.parse("\n".join(tree_mod_lines))
    except (SyntaxError, ValueError, RecursionError):
        return None
    classes = {n.name: n for n in mod.body if isinstance(n, ast.ClassDef)}

    def walk(name, d):
        node = classes.get(name)
        if node is None or d > 3:
            return None
        bases = [b.id if isinstance(b, ast.Name) else b.attr if isinstance(b, ast.Attribute) else "" for b in node.bases]
        deco = [(x.func if isinstance(x, ast.Call) else x) for x in node.decorator_list]
        is_dc = any((isinstance(x, ast.Name) and x.id == "dataclass") or (isinstance(x, ast.Attribute) and x.attr == "dataclass") for x in deco)
        if "BaseModel" not in bases and not is_dc and not any(b in classes for b in bases):
            return None
        if any(isinstance(n, ast.FunctionDef) and n.name == "__init__" for n in node.body):
            return None
        req = []
        for b in bases:
            if b in classes:
                r = walk(b, d + 1)
                if r is None:
                    return None
                req += r
        for n in node.body:
            if not isinstance(n, ast.AnnAssign) or not isinstance(n.target, ast.Name):
                continue
            if "ClassVar" in ast.dump(n.annotation):
                continue
            v = n.value
            if v is None:
                req.append(n.target.id)
            elif isinstance(v, ast.Call) and ((isinstance(v.func, ast.Name) and v.func.id == "Field") or (isinstance(v.func, ast.Attribute) and v.func.attr == "Field")):
                has_default = any(k.arg in ("default", "default_factory") for k in v.keywords) or (v.args and not (isinstance(v.args[0], ast.Constant) and v.args[0].value is Ellipsis))
                if not has_default:
                    req.append(n.target.id)
        return req
    return walk(cls, depth)


def _rule_bare_instantiation(clause, stages, pls, tree, item=None):
    """S9: `from m import Model; Model()` where Model (read from the tree) has required fields: the call raises a validation error before any assert runs. Tree-dependent (silent without one)."""
    out = []
    if not tree or not re.search(r"\bpython[0-9.]*\b.*-c\b", clause):
        return out
    for im in _IMP.finditer(clause):
        mod, names = im.group(1), [n.strip() for n in im.group(2).split(",") if n.strip()]
        for cls in names:
            if not re.search(r"(?<![\w.])%s\(\s*\)" % re.escape(cls), clause):
                continue
            rel = mod.replace(".", "/")
            for pre in ("", "backend/", "src/"):
                for suf in (".py", "/__init__.py"):
                    lines = _read(tree, pre + rel + suf)
                    if lines is None:
                        continue
                    req = _required_fields(lines, cls)
                    if req:
                        out.append(_find(clause, UNSAT, "S9", "`%s()` is called with no arguments but %s has required field(s) %s: it raises before any assert runs" % (cls, cls, ", ".join(req[:4])), None))
                        return out
    return out


def _rule_backend_prefix(clause, stages, pls, tree, item=None):
    """U4: `from backend.app.x import Y` when backend/'s own modules import `from app.x ...` (the app is rooted AT backend/): from the repo root `app` is not found - ModuleNotFoundError at
    the clause itself. Tree-dependent. Rewrite: cd backend and drop the prefix (only when the clause has no cd of its own)."""
    out = []
    m = re.search(r"\b(?:from|import)\s+backend\.(app|src)\b", clause)
    if not m or not tree or re.search(r"\bcd\b", clause):
        return out
    base = os.path.join(tree, "backend", m.group(1))
    if not os.path.isdir(base):
        return out
    own = pkg = 0
    n_seen = 0
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "__pycache__", ".venv", "venv")]
        for f in files:
            if not f.endswith(".py"):
                continue
            n_seen += 1
            if n_seen > 300:
                break
            lines = _read(tree, os.path.relpath(os.path.join(root, f), tree))
            for l in lines or []:
                if re.match(r"\s*(?:from|import)\s+%s(?:\.|\s)" % m.group(1), l):
                    own += 1
                elif re.match(r"\s*(?:from|import)\s+backend\.%s\b" % m.group(1), l):
                    pkg += 1
        if n_seen > 300:
            break
    if own and not pkg:
        fixed = re.sub(r"\b(from|import)\s+backend\.(app|src)\b", r"\1 \2", clause)
        out.append(_find(clause, UNRUN, "U4", "`backend.%s` is not importable from the repo root: backend/'s modules import `%s...` (the package root is backend/), so the import fails with ModuleNotFoundError" % (m.group(1), m.group(1)),
                         "cd backend && " + fixed))
    return out


_PY_C = re.compile(r"(?:^|[\s;&|(])(?:\S*/)?python[0-9.]*\s+(?:-\S+\s+)*-c\b")


# `type(n).__name__ == 'FunctionDef'` / `n.__class__.__name__ in ('FunctionDef',)`: the same blind spot spelled by name (flagged, never mechanically rewritten)
_FD_NAME = re.compile(r"""__name__\s*(?:==|!=|in)\s*[(\[]?\s*['"]FunctionDef['"]|['"]FunctionDef['"]\s*==\s*\S*__name__""")


def _rule_async_ast(clause, stages, pls, tree, item=None):
    """A1: a python -c that walks the AST for `ast.FunctionDef` (and never `AsyncFunctionDef`) to find a function that is `async def`: ast.walk never yields it, the list is empty and the clause dies
    with IndexError / prints nothing on EVERY run, however correct the code is. Evidence required: the item says `async def NAME`, or a .py file named in the clause (read from the tree) defines
    `async def NAME` and no plain `def NAME`. Rewrite (only when every occurrence is the 2nd argument of isinstance): widen it to (ast.FunctionDef, ast.AsyncFunctionDef)."""
    out = []
    if ("ast.FunctionDef" not in clause and not _FD_NAME.search(clause)) or "AsyncFunctionDef" in clause or not _PY_C.search(clause):
        return out
    names = [n for n in dict.fromkeys(re.findall(r"""['"]([A-Za-z_][A-Za-z0-9_]+)['"]""", clause)) if n not in ("utf-8", "utf8", "__main__")]
    files = [f for f in re.findall(r"[A-Za-z0-9_./-]+\.py\b", clause)]
    hit = None
    for n in names:
        if item and re.search(r"\basync\s+def\s+%s\b" % re.escape(n), item):
            hit = n
            break
        if tree:
            for f in files:
                lines = _read(tree, f)
                if lines and any(re.match(r"\s*async\s+def\s+%s\b" % re.escape(n), l) for l in lines) and not any(re.match(r"\s*def\s+%s\b" % re.escape(n), l) for l in lines):
                    hit = n
                    break
            if hit:
                break
    if not hit:
        return out
    total = len(re.findall(r"\bast\.FunctionDef\b", clause))
    pat = re.compile(r"isinstance\(\s*([\w.\[\]]+)\s*,\s*ast\.FunctionDef\s*\)")
    rw = pat.sub(r"isinstance(\1, (ast.FunctionDef, ast.AsyncFunctionDef))", clause) if (total and not _FD_NAME.search(clause) and len(pat.findall(clause)) == total) else None
    out.append(_find(clause, UNSAT, "A1", "`%s` is `async def`, but the clause only matches `ast.FunctionDef`: ast.walk never yields it (empty list -> IndexError / no output on every run). Match (ast.FunctionDef, ast.AsyncFunctionDef)" % hit, rw))
    return out


_HY_RE = r"([A-Za-z_]\w*(?:-\w+)+)((?:\.\w+)*)"


def _hyphen_import_stmt(stage):
    """(hyphenated_module, dotted_rest) when the python -c SOURCE of this stage has a real import statement (at statement start, outside any string literal) naming a hyphenated module; else None.
    Prose such as print('removed from user-facing text') is a STRING token, so it never matches. Falls back to a statement-anchored regex when the source cannot be extracted/tokenized."""
    src = None
    try:
        parts = shlex.split(stage)
        for i, a in enumerate(parts):
            if a == "-c" and i + 1 < len(parts):
                src = parts[i + 1]
                break
    except ValueError:
        pass
    if src is None:
        mm = re.search(r"""(?:^|[;\n'"])\s*(?:from|import)\s+""" + _HY_RE, stage)
        return (mm.group(1), mm.group(2)) if mm else None
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        toks = None
    if toks is None:
        mm = re.search(r"(?:^|[;\n])[ \t]*(?:from|import)\s+" + _HY_RE, src)
        return (mm.group(1), mm.group(2)) if mm else None
    sig = [t for t in toks if t.type not in (tokenize.COMMENT, tokenize.ENCODING)]
    start = True
    for i, t in enumerate(sig):
        if t.type in (tokenize.NEWLINE, tokenize.NL, tokenize.INDENT, tokenize.DEDENT) or (t.type == tokenize.OP and t.string == ";"):
            start = True
            continue
        if start and t.type == tokenize.NAME and t.string in ("from", "import"):
            line = ""
            j = i + 1
            while j < len(sig) and sig[j].type not in (tokenize.NEWLINE, tokenize.NL, tokenize.ENDMARKER) and not (sig[j].type == tokenize.OP and sig[j].string == ";"):
                tj = sig[j]
                line += (" " if tj.type == tokenize.NAME and line and not line.endswith((".", "-")) else "") + tj.string
                j += 1
            mm = re.match(r"\s*" + _HY_RE, line)
            if mm:
                return mm.group(1), mm.group(2)
        start = False
    return None


def _rule_hyphen_import(clause, stages, pls, tree, item=None):
    """H1: `python -c 'from iptv-backend.app.x import y'` / `import foo-bar`: a hyphen cannot appear in a Python module path, so the clause is a SyntaxError before it tests anything. Only python -c
    stages are inspected (a grep pattern may legitimately contain `from a-b import`). Rewrite: `cd <dir> && <clause with the dir prefix dropped>` when the dir exists in the tree (or ends in -backend
    with no tree) and the clause has no cd of its own."""
    out = []
    for st in stages:
        if not _PY_C.search(st[1]):
            continue
        m = _hyphen_import_stmt(st[1])
        if not m:
            continue
        hy, rest = m
        rw = None
        if rest and not re.search(r"\bcd\b", clause) and re.match(r"\s*(?:\S*/)?python[0-9.]*\b", clause) and (os.path.isdir(os.path.join(tree, hy)) if tree else hy.endswith("-backend")):
            rw = "cd %s && %s" % (hy, re.sub(r"\b(from|import)\s+%s\." % re.escape(hy), r"\1 ", clause))
        out.append(_find(clause, UNRUN, "H1", "`%s%s` has a hyphen in a module path: a SyntaxError at the clause itself (the project directory is `%s/`; its modules import from inside it)" % (hy, rest, hy), rw))
        break
    return out


_RULES = (_rule_tail, _rule_grepn_fn, _rule_window, _rule_double_prefix, _rule_pytest_root, _rule_import, _rule_signature,
          _rule_decorator_def, _rule_raises_polarity, _rule_conftest_target, _rule_bare_instantiation, _rule_backend_prefix)
_RULES = _RULES + (_rule_async_ast, _rule_hyphen_import)   # P8 (own switch OVN_VERIFY_ASYNC_LINT)


def _gate_p5(findings, codes=None):
    """Drop the gated findings and withhold P5-only rewrites (what OVN_VERIFY_LINT_P5 / OVN_VERIFY_ASYNC_LINT != enforce means for ENFORCEMENT). `codes` = the codes to drop (default P5_CODES);
    P5-only rewrites are withheld only when the P5 codes are part of the gate."""
    drop = P5_CODES if codes is None else frozenset(codes)
    out = []
    for f in findings:
        if f["code"] in drop:
            continue
        if f.get("p5_rewrite") and (drop & P5_CODES):
            f = dict(f, rewrite=None)
        out.append(f)
    return out


def lint_verify(clause, tree=None, item=None, gate=None):
    """-> {"class", "findings": [...], "clause"}; the class is the worst finding (UNSAT > UNRUN > VACUOUS > OK). `item` = the full item line (some rewrites depend on what the item
    says, e.g. a `| wc -l` that must be 0). Never raises and never runs longer than OVN_VERIFY_LINT_BUDGET_S (default 2s; a timeout fails open as OK)."""
    findings = []
    if gate is None:
        gate = p5_mode() == "off"
    try:
        with _time_budget(_budget_s()):
            stages = split_stages(clause)
            pls = _pipelines(stages)
            for rule in _RULES:
                findings.extend(rule(clause, stages, pls, tree, item))
    except Exception as e:   # a lint bug must never stop a refill
        return {"class": OK, "findings": [], "clause": clause, "error": "%s: %s" % (type(e).__name__, e)}
    if p8_mode() == "off":
        findings = [f for f in findings if f["code"] not in P8_CODES]
    if gate:
        findings = _gate_p5(findings, None if gate is True else gate)
    cls = max((f["class"] for f in findings), key=lambda c: _RANK[c], default=OK)
    return {"class": cls, "findings": findings, "clause": clause}


def fix_clause(clause, tree=None, rounds=4, item=None, gate=None):
    """Apply rewrites until the clause lints OK. -> (new_clause, remaining_findings). A finding without a rewrite stays."""
    cur = clause
    for _ in range(rounds):
        r = lint_verify(cur, tree, item, gate)
        if r["class"] == OK:
            return cur, []
        rw = next((f["rewrite"] for f in r["findings"] if f["class"] != OK and f.get("rewrite") and f["rewrite"] != cur), None)
        if not rw:
            return cur, [f for f in r["findings"] if f["class"] != OK]
        cur = rw
    return cur, [f for f in lint_verify(cur, tree, item, gate)["findings"] if f["class"] != OK]


# ---------------------------------------------------------------- item hooks
def _state_dir():
    return os.path.abspath(os.path.join(HERE, "..", "state"))


def _log_path():
    return os.environ.get("OVN_VERIFY_SHAPE_LOG") or os.path.join(_state_dir(), "verify_shape_lint.log")


def _alerts_path():
    return os.environ.get("OVN_VERIFY_ALERTS_LOG") or os.path.join(os.path.dirname(_log_path()), "alerts.log")


def _append(path, text):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)
    except OSError:
        pass


def lint_item_line(line, tree=None, md=None):
    """-> (decision, line_out, result). decision: ok | flagged (shadow: unchanged) | rewritten | dropped. result None when the line has no VERIFY clause."""
    md = md or mode()
    if md == "off":
        return "ok", line, None
    ex = extract_verify(line)
    if not ex:
        return "ok", line, None
    clause, s, e = ex
    res = lint_verify(clause, tree, line)
    if res["class"] == OK:
        return "ok", line, res
    if md != "enforce":
        return "flagged", line, res
    # P5-only findings are logged (flagged) but never rewritten/dropped unless OVN_VERIFY_LINT_P5=enforce; P8 (A1/H1) likewise unless OVN_VERIFY_ASYNC_LINT=enforce
    gate = p5_mode() != "enforce"
    gate = frozenset((P5_CODES if gate else frozenset()) | (P8_CODES if p8_mode() != "enforce" else frozenset())) or False
    if gate and lint_verify(clause, tree, line, gate)["class"] == OK:
        return "flagged", line, res
    new, left = fix_clause(clause, tree, item=line, gate=gate)
    if left or new == clause:
        return "dropped", line, res
    return "rewritten", line[:s] + new + line[e:], res


def log_flagged(flagged, repo, where, md, total):
    """flagged = [(line, decision, result)]: one JSON row per item to state/verify_shape_lint.log + ONE summary line to state/alerts.log."""
    rows = [{"ts": time.strftime("%F %T"), "repo": repo, "where": where, "mode": md, "decision": d, "class": r["class"],
             "codes": [f["code"] for f in r["findings"]], "reasons": [f["reason"] for f in r["findings"]],
             "rewrite": next((f["rewrite"] for f in r["findings"] if f.get("rewrite")), None), "clause": r["clause"][:300]} for _, d, r in flagged]
    if not rows or md == "off":
        return
    _append(_log_path(), "".join(json.dumps(x, sort_keys=True) + "\n" for x in rows))
    _append(_alerts_path(), "%s info | verify-lint | %s %s: %d of %d item VERIFY clause(s) flagged (mode=%s: %s)\n" % (
        time.strftime("%F %T"), repo or "-", where or "-", len(rows), total, md, ",".join(sorted({c for x in rows for c in x["codes"]}))))


def process_lines(lines, tree=None, repo="", where="", md=None):
    """Lint item lines per mode. -> (kept_lines, dropped[(line, result)], flagged_count). Shadow never changes text; enforce rewrites or drops."""
    md = md or mode()
    kept, dropped, flagged = [], [], []
    for ln in lines:
        d, out, res = lint_item_line(ln, tree, md)
        if d == "ok":
            kept.append(out)
            continue
        flagged.append((ln, d, res))
        if d == "dropped":
            dropped.append((ln, res))
        else:
            kept.append(out)
    log_flagged(flagged, repo, where, md, len(lines))
    return kept, dropped, len(flagged)


# ---------------------------------------------------------------- audit
def _collect(paths, include_done):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for name in ("OVERNIGHT_PROGRESS.md", "OVERNIGHT_DONE.md") if include_done else ("OVERNIGHT_PROGRESS.md",):
                fp = os.path.join(p, name)
                if os.path.isfile(fp):
                    files.append(fp)
            bd = os.path.join(p, "backlog")
            if os.path.isdir(bd):
                files += [os.path.join(bd, f) for f in sorted(os.listdir(bd)) if f.endswith(".md")]
        elif os.path.isfile(p):
            files.append(p)
    return files


def audit(paths, tree=None, include_done=False, limit=None):
    rows = []
    for fp in _collect(paths, include_done):
        pat = re.compile(r"^\s*- \[[ xX]\] " if include_done else r"^\s*- \[ \] ")
        with open(fp, encoding="utf-8", errors="replace") as f:
            for no, ln in enumerate(f, 1):
                ln = ln.rstrip("\n")
                if not pat.match(ln):
                    continue
                ex = extract_verify(ln)
                if not ex:
                    continue
                res = lint_verify(ex[0], tree, ln)
                rows.append({"file": fp, "line": no, "class": res["class"], "findings": res["findings"], "clause": ex[0], "item": ln[:160]})
                if limit and len(rows) >= limit:
                    return rows
    return rows


def _fmt_summary(rows):
    cnt = {}
    for r in rows:
        cnt[r["class"]] = cnt.get(r["class"], 0) + 1
    return "items with VERIFY=%d  " % len(rows) + "  ".join("%s=%d" % (k, cnt.get(k, 0)) for k in (OK, UNSAT, VACUOUS, UNRUN))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]

    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            v = args[i + 1] if i + 1 < len(args) else default
            del args[i:i + 2]
            return v
        return default
    tree = opt("--tree")
    if cmd == "check":
        r = lint_verify(args[0], tree)
        print(json.dumps(r, indent=1))
        return 0
    if cmd == "filter":
        repo, dropped_f = opt("--repo", ""), opt("--dropped")
        lines = [l.rstrip("\n") for l in sys.stdin]
        kept, dropped, _ = process_lines(lines, tree, repo, "filter")
        sys.stdout.write("".join(l + "\n" for l in kept))
        if dropped_f and dropped:
            _append(dropped_f, "".join("%s  <!-- verify-lint:%s %s -->\n" % (l, ",".join(f["code"] for f in r["findings"]), time.strftime("%F %T")) for l, r in dropped))
        return 0
    if cmd == "audit":
        include_done = "--all" in args
        if include_done:
            args.remove("--all")
        jf, mf, lim = opt("--json"), opt("--md"), opt("--limit")
        rows = audit(args, tree, include_done, int(lim) if lim else None)
        bad = [r for r in rows if r["class"] != OK]
        print(_fmt_summary(rows))
        for r in bad:
            f = r["findings"][0]
            print("%-13s %s %s:%d  %s" % (r["class"], f["code"], os.path.basename(r["file"]), r["line"], f["reason"][:150]))
            if f.get("rewrite"):
                print("              rewrite: %s" % f["rewrite"][:200])
        if jf:
            with open(jf, "w") as fh:
                json.dump(rows, fh, indent=1)
        if mf:
            with open(mf, "w") as fh:
                fh.write("# VERIFY shape audit\n\n%s\n\n" % _fmt_summary(rows))
                for r in bad:
                    f = r["findings"][0]
                    fh.write("- **%s/%s** `%s:%d` %s\n  - clause: `%s`\n%s" % (r["class"], f["code"], os.path.basename(r["file"]), r["line"], f["reason"], r["clause"][:240], ("  - rewrite: `%s`\n" % f["rewrite"]) if f.get("rewrite") else ""))
        return 0
    print("unknown command %s" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
