#!/usr/bin/env python3
"""ovn_precredit.py - D2 pre-edit already-satisfied credit + duplicate-spend guard for staged items (2026-10-18).

Audit: a staged item whose OWN VERIFY already passes on the pristine tree (a verification-only item, or an item whose test a sibling item already landed) burned 2+ model runs
(~275k tokens) as no-ops (shrike-monitor 051e535 duplicate, shrike-notify severity_map). The old verify_only_pristine_pass preflight only logged. This module is the deterministic
decision half; ovn_stage_runner.sh (stage_precredit_run) calls it BEFORE the planner/model and acts on the verdict according to OVN_STAGE_PRECREDIT=off|shadow|enforce.

CLI (all output is one JSON object on stdout, never a traceback):
  decide --item TEXT --pre RESULT [--progress FILE] [--wt DIR] [--verify-only 0|1]
        RESULT is the pristine stage_item_verify_run verdict (PASS|FAIL|TIMEOUT|UNRUNNABLE|NO_VERIFY_CLAUSE|SKIPPED_DENYLIST, optionally `|why`).
        -> {"decision": "credit"|"duplicate"|"none", "reason": ..., "key": ..., "sibling": ..., "vacuous": bool}
  vacuity --verify CMD [--wt DIR]   -> {"vacuous": bool, "why": ...}
  mark --progress FILE --item TEXT --decision credit|duplicate --note TEXT   -> rewrites the first open line of the item as `- [x] (<note>) ...`; prints {"marked": bool}

Credit rules (every one must hold; anything else is decision "none" and the model runs exactly as before):
  1. the pristine verdict is PASS (an indeterminate verdict is no evidence);
  2. the VERIFY clause is NON-VACUOUS (see vacuity()): not empty, not an always-exit-0 idiom, not `cmd | wc -l` / `| head` (the pipe status hides the verdict), not `|| true`,
     not a collect-only pytest, not an absence check on a path that does not exist, and it contains at least one discriminating command (a test runner, grep, test/[, diff ...);
  3. EITHER the item only asks to verify (verify-only, decided by the runner's stage_item_is_verify_only AND the python guards asks_change()/polarity/whole-suite below) OR the item is an
     ADD-A-TEST item (no edit verb in the description; target file is a test file or the verb is Add/Create/Write ... test) whose VERIFY names a specific test node (`file::test_name` / `-k name`).
     A regression test passes before a behaviour-preserving edit (Refactor/Fix/Modify/Update ...), so a node-named EDIT item is never credited: passing proves nothing about the edit.
Duplicate: rule 1-3 hold, the VERIFY names a specific test node, and another line of the progress file (earlier, or already checked off) carries the same node: that sibling owns the work.
"""
import argparse
import json
import os
import re
import shlex
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    from ovn_backlog_eligibility import extract_verify, is_vacuous_cmd  # type: ignore
except Exception:  # pragma: no cover - fail-safe: a missing sibling module means "no decision"
    extract_verify = None
    is_vacuous_cmd = None

# commands whose exit status is a real verdict
_DISCRIMINATING = {
    "pytest", "py.test", "grep", "egrep", "fgrep", "rg", "test", "[", "[[", "diff", "cmp", "godot", "godot4", "vitest", "jest", "tsc", "vue-tsc", "ruff", "mypy", "flake8", "pylint",
    "gradlew", "./gradlew", "cargo", "go", "npx", "npm", "yarn", "pnpm", "jq", "git",
}
# runners that only count when the sub-command is a real check (`go version`, `npm --version` are constant)
_SUBCMD_REQUIRED = {"cargo": {"test", "check", "clippy", "build"}, "go": {"test", "vet", "build"}, "npx": {"vitest", "jest", "tsc", "vue-tsc", "eslint"},
                    "npm": {"test", "run", "t"}, "yarn": {"test", "run"}, "pnpm": {"test", "run", "exec"}}
_TEST_RUNNERS = {"pytest", "py.test", "godot", "godot4", "vitest", "jest", "gradlew", "./gradlew"}
# a pipeline whose LAST stage is one of these reports that stage's status, not the producer's (the repo shells run without pipefail)
_STATUS_HIDING_TAIL = {"wc", "head", "tail", "cat", "sort", "uniq", "tee", "cut", "tr", "nl", "less", "more", "xargs", "column", "paste", "fold", "rev", "yes"}
_TRIVIAL = {"true", ":", "echo", "printf", "exit", "ls", "pwd", "sleep", "date", "cd", "false", "whoami", "env", "hostname", "uname"}
_MASK_TAIL = re.compile(r"(?:\|\||;)\s*(?:true|:|exit\s+0|echo\b[^|;&]*|printf\b[^|;&]*)\s*$")
_COMPARE = re.compile(r"(?:\s-(?:eq|ne|ge|gt|le|lt)\s|\s(?:=|==|!=)\s)")


def _split_top(cmd):
    """Quote- and paren-aware split of CMD on top-level && || ; | -> list of (operator_before, clause). None when quotes/parens do not balance."""
    out, cur, op, q, depth, i, n = [], [], "", "", 0, 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if q:
            cur.append(ch)
            if ch == "\\" and q == '"' and i + 1 < n:
                cur.append(cmd[i + 1]); i += 1
            elif ch == q:
                q = ""
        elif ch in "'\"":
            q = ch; cur.append(ch)
        elif ch == "\\" and i + 1 < n:
            cur.append(ch); cur.append(cmd[i + 1]); i += 1
        elif ch in "([{":   # `$(` is counted once, by its `(`
            depth += 1; cur.append(ch)
        elif ch in ")]}" and depth > 0 and not (ch == "]" and False):
            depth -= 1; cur.append(ch)
        elif depth == 0 and cmd.startswith(("&&", "||"), i):
            out.append((op, "".join(cur).strip())); cur = []; op = cmd[i:i + 2]; i += 1
        elif depth == 0 and ch in ";|":
            out.append((op, "".join(cur).strip())); cur = []; op = ch
        else:
            cur.append(ch)
        i += 1
    if q or depth != 0:
        return None
    out.append((op, "".join(cur).strip()))
    return [(o, c) for o, c in out if c or o]


def _first_word(clause):
    c = clause.strip()
    while c.startswith("!"):
        c = c[1:].strip()
    # leading VAR=val and env prefixes
    while True:
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*=\S*)\s+", c)
        if not m:
            break
        c = c[m.end():]
    if c.startswith("timeout "):
        c = re.sub(r"^timeout\s+(?:-\S+\s+)*\S+\s+", "", c)
    if c.startswith("(") or c.startswith("{"):
        c = c[1:].strip()
    w = c.split(None, 1)[0] if c.split() else ""
    return os.path.basename(w) if "/" in w and not w.startswith("./") else w


def _clause_words(clause):
    try:
        return shlex.split(clause, posix=True)
    except ValueError:
        return clause.split()


def _is_inverted_grep(clause):
    w = _clause_words(clause)
    if not w or os.path.basename(w[0]) not in ("grep", "egrep", "fgrep", "rg"):
        return False
    return any(x == "--invert-match" or (x.startswith("-") and not x.startswith("--") and "v" in x[1:] and len(x) <= 6) for x in w[1:])


def _is_python_pytest(clause):
    return bool(re.search(r"\bpython3?\s+-m\s+(?:pytest|unittest)\b", clause))


def _path_tokens(clause):
    for w in _clause_words(clause):
        if w.startswith("-") or "=" in w and not "/" in w:
            continue
        if re.search(r"[A-Za-z0-9_]\.[A-Za-z0-9]{1,6}$", w) and not w.startswith("$"):
            yield w.split("::", 1)[0]


def vacuity(cmd, wt=None):
    """-> (vacuous: bool, why: str). `why` for a non-vacuous VERIFY names the discriminating command that was found."""
    c = (cmd or "").strip()
    if not c:
        return True, "no VERIFY clause"
    if is_vacuous_cmd is not None and is_vacuous_cmd(c):
        return True, "always-exit-0 echo idiom (`cmd && echo FAIL || echo PASS`)"
    if _MASK_TAIL.search(c):
        return True, "exit status masked by a trailing `|| true` / `; echo` / `|| exit 0`"
    parts = _split_top(c)
    if parts is None:
        return True, "unbalanced quotes/parens: not an honest runnable VERIFY"
    # `a || b`: the right side may only rescue the verdict when it is itself a real check
    for op, cl in parts:
        if op == "||" and _first_word(cl) in _TRIVIAL | {"true"}:
            return True, "`|| %s` rescues a failing verdict" % _first_word(cl)
    # status-hiding pipeline tails (top-level pipe whose last stage is wc/head/tail/...)
    for idx, (op, cl) in enumerate(parts):
        if op == "|":
            nxt = parts[idx + 1][0] if idx + 1 < len(parts) else ""
            if nxt != "|" and _first_word(cl) in _STATUS_HIDING_TAIL:
                return True, "pipeline ends in `%s`: its status hides the verdict (bare `grep | wc -l` is always exit 0)" % _first_word(cl)
    # a pipeline whose last stage is `grep -v` exits 0 when ANY line survives the filter, i.e. when the thing it filters for is still there: the verdict is inverted for "ensure no X" items
    for idx, (op, cl) in enumerate(parts):
        if op == "|":
            nxt = parts[idx + 1][0] if idx + 1 < len(parts) else ""
            if nxt != "|" and _is_inverted_grep(cl):
                return True, "pipeline ends in `grep -v`: exit 0 means matching lines REMAIN (inverted verdict)"
    # comparing HEAD with the working tree on the pristine tree is identical by construction
    if re.search(r"\bgit\s+(?:show|cat-file(?:\s+-p)?)\s+HEAD(?:~0)?:", c) and any(_first_word(cl) in ("diff", "cmp") for _, cl in parts):
        return True, "compares `git show HEAD:...` with the working tree: identical on the pristine tree, can never fail"
    for _, cl in parts:
        if _first_word(cl) == "git" and re.match(r"git\s+diff\b", cl.strip().lstrip("!").strip()) and re.search(r"--quiet|--exit-code", cl):
            gw = _clause_words(cl)[2:]
            gw = gw[:gw.index("--")] if "--" in gw else gw   # words after `--` are paths, not refs
            refs = [w for w in gw if not w.startswith("-") and w != "HEAD"]
            if not refs:
                return True, "`git diff --quiet` against HEAD/index on the pristine tree always passes"
    # a count with no comparison anywhere is not a verdict
    if re.search(r"\bwc\s+-l\b", c) and not _COMPARE.search(c) and not re.search(r"(?:^|\s)(?:test|\[\[?)\s", c):
        return True, "a bare `wc -l` count with no comparison"
    words_all = [w for _, cl in parts for w in [_first_word(cl)] if w]
    non_cd = [w for w in words_all if w not in ("cd", "export", "set", "source", ".")]
    if not non_cd:
        return True, "no command"
    if all(w in _TRIVIAL for w in non_cd):
        return True, "only trivial commands (%s): exit status is constant" % ",".join(sorted(set(non_cd)))
    # collect-only / help pytest never runs a test
    if re.search(r"(?:--collect-only|--co\b|--help\b|(?:^|\s)-h(?:\s|$)|--version\b)", c) and any(w in ("pytest", "py.test") or _is_python_pytest(c) for w in non_cd):
        return True, "pytest collect-only/help runs no test"
    if re.search(r"\bpytest\b.*\s-k\s+[\"']{2}", c):
        return True, "pytest -k with an empty expression"
    # an absence check (`! cmd`) on a path that does not exist passes for the wrong reason
    if wt and any(cl.lstrip().startswith("!") for _, cl in parts):
        for _, cl in parts:
            if not cl.lstrip().startswith("!"):
                continue
            for p in _path_tokens(cl):
                if not os.path.exists(os.path.join(wt, p)):
                    return True, "absence check on a path that does not exist (%s): green for the wrong reason" % p
    def _real(cl):
        w = _first_word(cl)
        if _is_python_pytest(cl):
            return True
        if w not in _DISCRIMINATING:
            return False
        if w == "git":   # only `git diff --exit-code|--quiet <ref>` is a verdict (plain `git diff` always exits 0)
            gw = _clause_words(cl.strip().lstrip("!").strip())
            return len(gw) > 1 and gw[1] == "diff" and any(x in ("--exit-code", "--quiet") for x in gw)
        need = _SUBCMD_REQUIRED.get(w)
        return not need or bool(need & set(_clause_words(cl)[1:]))
    if not any(_real(cl) for _, cl in parts):
        # `python script.py`-style is covered above; anything else is unrecognised -> never credit on it
        return True, "no recognised discriminating command in the VERIFY (%s)" % ",".join(sorted(set(non_cd)))[:80]
    found = next((_first_word(cl) for _, cl in parts if _real(cl)), "python -m pytest")
    return False, found


_NODE_RE = re.compile(r"([A-Za-z0-9_./-]+\.(?:py|gd|ts|tsx|js|jsx|kt|java|swift))::([A-Za-z0-9_:\[\]\-]+)")
_K_RE = re.compile(r"(?:^|\s)-k\s+(?:\"([^\"]+)\"|'([^']+)'|(\S+))")
_FILE_RE = re.compile(r"([A-Za-z0-9_./-]*test[A-Za-z0-9_./-]*\.(?:py|gd|ts|tsx|js|jsx|kt|java|swift)|[A-Za-z0-9_./-]*_test\.gd)")


def _is_leaf_test(name):
    """A node id leaf must be a test FUNCTION/method (`test_x`, `test_x[param]`), never a class (`TestFollow`): a class id already passes on the pristine tree because its sibling tests exist."""
    leaf = name.split("::")[-1].split("[", 1)[0]
    return bool(leaf) and not leaf[0].isupper()


def test_keys(cmd):
    """Specific test nodes a VERIFY runs: `file::name` / `file::Class::name` for each pytest LEAF node id. Empty = file-wide, class-level, `-k` (substring match: also hits pre-existing tests) or no test."""
    keys = []
    for m in _NODE_RE.finditer(cmd or ""):
        if _is_leaf_test(m.group(2)):
            keys.append("%s::%s" % (m.group(1).lstrip("./"), m.group(2)))
    return sorted(set(keys))


def _norm_item(s):
    return re.sub(r"\s+", " ", s or "").strip()


def _item_lines(progress_text):
    for n, ln in enumerate(progress_text.split("\n")):
        m = re.match(r"^- \[( |x|X)\] (.*)$", ln)
        if m:
            yield n, m.group(1) != " ", m.group(2)


def find_sibling(progress_text, item, keys):
    """-> (sibling description or None, own line index). Sibling = a DIFFERENT progress line carrying one of KEYS that is either already checked off, or sits above this item."""
    me = _norm_item(item)
    own = None
    lines = list(_item_lines(progress_text))
    for n, done, body in lines:
        if not done and me and (_norm_item(body) == me or _norm_item(body).startswith(me[:80])):
            own = n; break
    for n, done, body in lines:
        if n == own:
            continue
        if _norm_item(body) == me:
            continue
        v = extract_verify(body) if extract_verify else None
        if not v:
            continue
        shared = set(test_keys(v)) & set(keys)
        if shared and (done or own is None or n < own):
            return "%s line %d%s: %s" % (sorted(shared)[0], n + 1, " (done)" if done else "", _norm_item(body)[:100]), own
    return None, own


_EDIT_VERBS = re.compile(r"\b(fix|fixes|fixing|refactor|refactors|modify|modifies|update|updates|replace|replaces|change|changes|remove|removes|rename|renames|migrate|migrates|delete|deletes|rewrite|rewrites|"
                         r"extend|wire|swap|move|implement|handle|handles|store|stores|accept|accepts|reject|rejects|route|routes|use|uses|call|calls|set|sets|return|returns|raise|raises|emit|emits|make|makes)\b", re.I)
_CHANGE_VERBS_VERIFY = re.compile(r"\b(attach|attached|attaches|apply|applied|applies|place|placed|places|wrap|wrapped|wraps|inject|injected|register|registered|added|created|exposed|"
                                  r"wired|set|replaced|removed|renamed|moved|changed|updated)\b", re.I)
_NEGATIVE_POLARITY = re.compile(r"\b(no other|no more|no remaining|no longer|no remaining|never|not (?:referenced|used|imported|present|called|contain\w*|exist\w*)|nothing (?:else )?(?:references|imports|uses|calls))\b|\bno\s+\w+(?:\s+\w+)?\s+(?:references|imports|uses|calls|remain)", re.I)
_NEG_ANY = re.compile(r"\b(?:no|not|never|nothing|none|nor|neither|unused)\b", re.I)
_IDENT_RE = re.compile(r"`([^`]{3,})`|\b([A-Za-z]+_[A-Za-z0-9_]+|[a-z]+[A-Z][A-Za-z0-9]*|[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*)\b|\b(\w{3,}\(\))")
_NEG_VERIFY = r"(?:^|[\s;&|(])!\s|\s-[a-zA-Z]*[Lvc]\b|--files-without-match|\bwc\s+-l|\|\s*grep\s+-[a-z]*v"
_TESTFILE_RE = re.compile(r"(?:^|/)(?:tests?/|test_[^/]*$|[^/]*_test\.[a-z]+$|[^/]*\.(?:test|spec)\.[a-z]+$|[^/]*Tests?\.(?:kt|java|swift)$)")
_SUITE_WORDS = re.compile(r"\b(tests?|suite|passes|passing|green)\b", re.I)


def _split_item(item):
    """-> (target path or '', description) of `[T3] path — description. VERIFY: ...`."""
    body = re.split(r"VERIFY:", item or "", maxsplit=1)[0]
    m = re.match(r"^\s*(?:\[[^\]]*\]\s*)*(\S+)\s+[\u2014\u2013-]+\s+(.*)$", body, re.S)
    if m:
        return m.group(1).strip("`'\""), m.group(2).strip()
    return "", body.strip()


def is_add_test_item(item):
    """True only for an item that ADDS a test: no edit verb in the description AND (target file is a test file OR the description is `Add/Create/Write ... test`)."""
    path, desc = _split_item(item)
    if _EDIT_VERBS.search(desc):
        return False
    if path and _TESTFILE_RE.search(path):
        return True
    return bool(re.match(r"^\W*(?:add|adds|create|creates|write|writes)\b[^.]{0,120}\btest", desc, re.I))


def asks_change(item, v):
    """-> why-string when an item the runner classed verify-only actually asks for a change / the VERIFY cannot prove it, else ''."""
    _, desc = _split_item(item)
    if _EDIT_VERBS.search(desc):
        return "the description names an edit verb (%s): not a verification-only item" % _EDIT_VERBS.search(desc).group(1)
    if _CHANGE_VERBS_VERIFY.search(desc):
        return "the description asks for a change/placement (%s), a loose VERIFY does not prove it" % _CHANGE_VERBS_VERIFY.search(desc).group(1)
    neg = _NEGATIVE_POLARITY.search(desc) or _NEG_ANY.search(desc)
    if neg and not re.search(_NEG_VERIFY, v or ""):
        return "negative-polarity description (`%s`) with a positively-polarised VERIFY: a pass could mean the opposite" % neg.group(0)
    parts = _split_top(v or "") or []
    real = [_first_word(cl) for _, cl in parts]
    runs_tests = any(w in _TEST_RUNNERS for w in real) or any(_is_python_pytest(cl) for _, cl in parts) or any(w in ("npm", "yarn", "pnpm", "npx", "cargo", "go") for w in real)
    if re.match(r"^\W*ensure\b", desc, re.I) and not runs_tests:
        return "an `Ensure ...` item whose VERIFY is only a grep/diff: ensure asks for a state the loose check cannot prove"
    if runs_tests and not test_keys(v) and not _SUITE_WORDS.search(desc):
        return "a whole-file/suite test run proves nothing about what the description names"
    suite_claim = runs_tests and not test_keys(v) and _SUITE_WORDS.search(desc)   # `Verify the test suite passes`: the claim IS the suite, no identifier needed
    idents = [next(g for g in m.groups() if g).strip("`() ") for m in _IDENT_RE.finditer(desc)]
    if suite_claim:
        return ""
    if not idents:
        return "the description names no code identifier (snake_case/CamelCase/`x`/x()): the VERIFY cannot be tied to the claim"
    if idents and not any(i and i in (v or "") for i in idents):
        return "the VERIFY mentions none of the description's identifiers (%s): a green VERIFY proves nothing about the claim" % ",".join(idents[:3])
    return ""


def decide(item, pre, progress_text="", wt=None, verify_only=False):
    res = {"decision": "none", "reason": "", "key": "", "sibling": "", "vacuous": False}
    verdict = (pre or "").split("|", 1)[0].strip()
    if verdict != "PASS":
        res["reason"] = "pristine verdict %s is not PASS" % (verdict or "empty")
        return res
    v = extract_verify(item) if extract_verify else None
    if not v:
        res["reason"] = "no extractable VERIFY clause"
        return res
    vac, why = vacuity(v, wt)
    res["vacuous"] = vac
    if vac:
        res["reason"] = "vacuous VERIFY: " + why
        return res
    keys = test_keys(v)
    res["key"] = ",".join(keys)
    add_test = is_add_test_item(item)
    if keys and add_test and progress_text:
        sib, _ = find_sibling(progress_text, item, keys)
        if sib:
            res.update(decision="duplicate", sibling=sib, reason="the VERIFY test node already belongs to a sibling item and passes (%s)" % why)
            return res
    if verify_only:
        bad = asks_change(item, v)
        if bad:
            res["reason"] = "verify-only classification rejected: " + bad
            return res
        res.update(decision="credit", reason="verify-only item, non-vacuous VERIFY (%s) already PASSES on the pristine tree" % why)
        return res
    if keys and add_test:
        res.update(decision="credit", reason="add-a-test item: specific test node(s) %s named by the VERIFY already PASS on the pristine tree (%s)" % (res["key"], why))
        return res
    if keys:
        res["reason"] = "item is an EDIT (not an add-a-test item) and its VERIFY test node passes before the change: a regression test proves nothing about the edit (model still runs)"
        return res
    res["reason"] = "item asks for a change and its VERIFY names no specific test node: a green file-wide/grep VERIFY does not prove the change (model still runs)"
    return res


def mark(progress_path, item, decision, note):
    try:
        text = open(progress_path, encoding="utf-8").read()
    except OSError:
        return False
    lines = text.split("\n")
    me = _norm_item(item)
    for i, ln in enumerate(lines):
        if ln.startswith("- [ ] ") and _norm_item(ln[6:]) == me:
            lines[i] = "- [x] (%s) %s" % (note.replace("\n", " ").strip(), ln[6:])
            break
    else:
        key = me[:55]
        for i, ln in enumerate(lines):
            if ln.startswith("- [ ] ") and key and key in _norm_item(ln):
                lines[i] = "- [x] (%s) %s" % (note.replace("\n", " ").strip(), ln[6:])
                break
        else:
            return False
    tmp = progress_path + ".tmp.%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    os.replace(tmp, progress_path)
    return True


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("decide"); d.add_argument("--item", required=True); d.add_argument("--pre", default="")
    d.add_argument("--progress", default=""); d.add_argument("--wt", default=""); d.add_argument("--verify-only", default="0")
    v = sub.add_parser("vacuity"); v.add_argument("--verify", required=True); v.add_argument("--wt", default="")
    m = sub.add_parser("mark"); m.add_argument("--progress", required=True); m.add_argument("--item", required=True)
    m.add_argument("--decision", required=True); m.add_argument("--note", required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == "decide":
            ptxt = ""
            if a.progress:
                try:
                    ptxt = open(a.progress, encoding="utf-8", errors="replace").read()
                except OSError:
                    ptxt = ""
            out = decide(a.item, a.pre, ptxt, a.wt or None, a.verify_only == "1")
        elif a.cmd == "vacuity":
            vac, why = vacuity(a.verify, a.wt or None)
            out = {"vacuous": vac, "why": why}
        else:
            out = {"marked": mark(a.progress, a.item, a.decision, a.note)}
    except Exception as e:  # never a traceback: the caller treats this as "no decision"
        out = {"decision": "none", "reason": "internal error: %s" % e, "key": "", "sibling": "", "vacuous": False}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
