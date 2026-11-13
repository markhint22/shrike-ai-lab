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

Mode: env OVN_VERIFY_LINT = off | shadow (default). `enforce` (shared with the older ovn_verify_shape_lint) is treated as shadow: THIS linter never changes an item.
Shadow rows go to state/verify_lint.jsonl (OVN_VERIFY_LINT_LOG overrides), deduped per (repo, item hash, rule) through state/verify_lint.seen.

CLI
  ovn_verify_lint.py check '<item line>' --repo-root DIR [--state DIR]       one item, JSON
  ovn_verify_lint.py shadow FILE --repo-root DIR [--state DIR] [--repo NAME]  every open item of a progress file -> jsonl rows (hooks use this; never raises, rc 0)
  ovn_verify_lint.py replay FILE... [--state DIR]                             read-only: counts per rule (no log writes), for false-positive review
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


def lint_verify(item_line, repo_root, state_dir=None, siblings=()):
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
        return _lint_verify(item_line, repo_root, state_dir, siblings)
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


def _lint_verify(item_line, repo_root, state_dir=None, siblings=()):
    try:
        clause = extract_verify(item_line)
        if not clause:
            return _res()
        for r in (rule_ml1(clause, repo_root), rule_tp1(clause, repo_root), rule_ts1(clause, repo_root, state_dir), rule_pn1(item_line, clause, repo_root, siblings), rule_neggrep1(item_line, clause, repo_root)):
            if r:
                return r
    except Budget:
        raise
    except Exception as e:   # a linter bug must never leak into the queue
        return _res(OK, "lint-error:%s" % type(e).__name__)
    return _res()


def _h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:12]


def _state(state_dir):
    return state_dir or os.environ.get("OVN_STATE_DIR") or os.path.join(HERE, "state")


def shadow_log(item_line, repo_root, repo=None, state_dir=None, source="scan", siblings=()):
    """lint one item; append a row for a NEW (repo,item,rule) finding. Returns the result. Never raises; writes nothing in mode off."""
    if mode() == "off":
        return _res()
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
        tot = {"items": 0, "SUSPECT": 0}
        by = {}
        for f in a:
            rr = os.path.dirname(os.path.abspath(f))
            sib = list(open_items(f, False))
            for it in open_items(f):
                tot["items"] += 1
                r = lint_verify(it, rr, state, sib)
                if r["verdict"] == SUSPECT:
                    tot["SUSPECT"] += 1
                    by.setdefault(r["rule"], []).append((os.path.basename(rr), it[:110], r["reason"][:200]))
        print(json.dumps({"totals": tot, "by_rule": {k: len(v) for k, v in by.items()}}))
        for k, v in by.items():
            for x in v:
                print(k, *x, sep=" | ")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
