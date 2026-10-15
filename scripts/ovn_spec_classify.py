#!/usr/bin/env python3
"""scripts/ovn_spec_classify.py - verdict classifier for ovn_spec_check.sh (spec-compiler-v2 part C1, 2026-10-09).

classify(item_line, rc, out_tail) -> (verdict, sub)

  verdict (unchanged set, ovn_work_supply parses it with `^(\\d+)\\t(\\w[\\w-]*)`):  red | passes-before | no-verify | bad-spec
  sub     red      assert | new-target
          bad-spec unrunnable | crash-unexplained | no-tests-collected | no-rc
          other    ""

Rules, first match wins (rc = the VERIFY's exit code, out_tail = the last ~300 chars of its output):
  no VERIFY in the line                                   no-verify
  rc 0                                                    passes-before
  rc 124 / 126 / 127                                      bad-spec/unrunnable
  NameError / SyntaxError / IndentationError              bad-spec/crash-unexplained   (the VERIFY itself is broken, it asserts nothing)
  GUT "Could not find script"                             red/new-target if the item declares that script, else bad-spec/crash-unexplained
  GUT ran nothing behind exit 0 ("Failed to load script", "Parse Error", "Nothing was run", "Tests 0", class_names not imported, or the runner's GUT-load-failed /
  GUT-not-imported markers): NEVER passes-before (intake package, platform P3: GUT exits 0 when it could not load or find the script, so a brand-new test target read as
  already passing); bad-spec/crash-unexplained, or red/new-target when the only thing missing is a script the item declares
  pytest rc 5 / "no tests ran" / "collected 0 items"      bad-spec/no-tests-collected, unless the item creates that test (red/new-target)
  ModuleNotFoundError / "cannot import name" / FileNotFoundError / "No such file" / pytest rc 4 ("not found:")
                                                          red/new-target ONLY when the missing module/path maps onto a path the item DECLARES (its target path
                                                          or a path introduced by a Create/Add/Write verb), else bad-spec/crash-unexplained
  AssertionError, or rc 1 with no other exception/Traceback  red/assert   (ZeroDivisionError/AttributeError/TypeError/... => bad-spec/crash-unexplained)
  anything else                                           bad-spec/crash-unexplained

Misclassifications this replaces (probed on the old regex classifier): a legit new-module `python3 -c "from app.services.zzz_new import foo"` was bad-spec;
`python3 -c "assert 1==2"` was bad-spec because the Traceback regex matched AssertionError; pytest -k selecting nothing (rc 5) was red; a bare no-backtick VERIFY was
no-verify while queue_refill._extract_verify accepted it.

CLI (used by ovn_spec_check.sh; shares extract_verify with queue_refill via ovn_backlog_eligibility so the two parsers agree):
  ovn_spec_classify.py canon <file>              the file with every bare `VERIFY: cmd (cat:` rewritten to `VERIFY: \\`cmd\\`` (line numbers preserved)
  ovn_spec_classify.py extract                   stdin item line -> its VERIFY command (empty when none)
  ovn_spec_classify.py rows <file> <rows.tsv>    rows.tsv: n TAB RESULT TAB rc TAB why TAB tail  ->  n TAB verdict TAB detail TAB sub TAB rc   (one per row)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_backlog_eligibility import extract_verify, item_target  # noqa: E402

CREATE_VERB = re.compile(r"\b(create|add|write|introduce|new|implement|define)\b", re.I)
PATH_RE = re.compile(r"(?<![\w./:-])((?:[\w.-]+/)*[\w.-]+\.(?:py|gd|ts|tsx|js|jsx|kt|swift|vue|json|md|sh|tscn|tres))(?![\w/])")
_FATAL_VERIFY = re.compile(r"\b(NameError|SyntaxError|IndentationError)\b")
_NO_TESTS = re.compile(r"no tests ran|collected 0 items|no-tests-ran")
# GUT exits 0 when it could not load / find / import the script it was asked to run: output that says so is never a pass
_GUT_NORUN = re.compile(r"Failed to load script|Parse Error|GUT-load-failed|GUT-not-imported|class_names have not been imported")
# ... and, behind an EXIT 0 only (a nonzero exit with 'Nothing was run' is X2's FAIL for a not-yet-written test function: a legitimate red-before, left as it was):
_GUT_NORUN_RC0 = re.compile(r"Could not find script|Nothing was run|(?<![\w.])Tests\s+0(?!\d)")
# any exception other than AssertionError (ZeroDivisionError, AttributeError, TypeError, ...) or a Traceback means the VERIFY crashed instead of asserting
# 2026-10-10 (F2): the old pattern matched ANY identifier ending in Error/Exception - including the import names ruff prints in its F401 messages
# (`app.core.ssrf.SSRFError` imported but unused) - so every unused-import-of-an-exception gap was a permanent bad-spec. A real crash prints a Traceback, or an
# exception name followed by ':' ("ZeroDivisionError: division by zero", "builtins.KeyError: 'x'"), or (pytest) `E   SomeError` on its own line. The tail
# reaches us with newlines turned into spaces, so a name merely quoted in a message (preceded by a backtick/quote, followed by a backtick/space) never counts.
# Also a crash (round-2 review): node's `TypeError [ERR_X]: msg` (code in brackets before the colon) and a bare final exception name after a Python `File "x", line N` frame.
_OTHER_EXC = re.compile(
    r"Traceback \(most recent call last\)"
    r"|(?<![\w.`'\"/-])(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\s*(?::|\[[A-Z][A-Z0-9_]*\])"
    r"|(?:^|\s)E {2,}(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\b(?![\w`'\"])")
# Round-3 review: the File-frame form used to be ONE regex (`File "x", line N` + lazy `.*?` + a final bare name + \Z): super-linear (a 50 KB tail with 1000 frames did not finish in
# 100 s). Now two linear steps: the first frame, then a bare exception name at the very END of the text (searched only in the last 300 chars: no real exception name is longer).
_FRAME = re.compile(r"File \"[^\"\n]+\", line \d+\b")
_FINAL_BARE_EXC = re.compile(r"(?<![\w.`'\"/-])(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\s*\Z")


def _frame_then_bare_exc(text):
    """A Python `File "x", line N` frame followed by a line-final bare exception name (not AssertionError)."""
    fm = _FRAME.search(text)
    if not fm:
        return False
    cut = max(fm.end(), len(text) - 300)
    return bool(_FINAL_BARE_EXC.search(text, cut))


_MISSING_FILE = re.compile(r"FileNotFoundError|No such file|can't open file|file or directory not found|ERROR: not found|not found: ")
_MISSING_MOD = re.compile(r"ModuleNotFoundError|ImportError|cannot import name|No module named")


def clean_bare_verify(cmd):
    """A bare VERIFY clause ends at ' (cat:' and usually carries the sentence period (`pytest x.py -q. (cat:`): drop one trailing '.' glued to the last token.
    A '.' that is its own argument (`ls .`) or part of '..'/'./' is kept."""
    c = cmd.strip()
    if len(c) > 1 and c.endswith(".") and not c[-2].isspace() and c[-2] not in "./":
        return c[:-1]
    return c


def verify_of(line):
    """The VERIFY command the way queue_refill._extract_verify reads it (a bare clause gets its sentence period cleaned)."""
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if m:
        return m.group(1).strip()
    c = extract_verify(line)
    return clean_bare_verify(c) if c else None


def declared_paths(line):
    """Paths the item says it brings into existence or changes: its target (text before the first ' - ') plus every path named after a Create/Add/Write verb in
    the body (the text between ' - ' and the VERIFY clause)."""
    out = set()
    t = item_target(line)
    if t:
        out.add(t.strip("`"))
    parts = re.split(r"\s—\s", line, maxsplit=1)
    if len(parts) == 2:
        body = re.split(r"VERIFY:", parts[1])[0].replace("res://", "")
        m = CREATE_VERB.search(body)
        if m:
            out.update(PATH_RE.findall(body[m.start():]))
    return {p for p in out if p}


def _noext(p):
    p = p.strip().strip("`'\"")
    for pre in ("res://", "./"):
        if p.startswith(pre):
            p = p[len(pre):]
    return re.sub(r"\.(py|gd|ts|tsx|js|jsx|kt|swift|vue|json|md|sh|tscn|tres)$", "", p)


def _canon_ref(ref):
    ref = ref.strip().strip("`'\"")
    if "/" in ref or re.search(r"\.(py|gd|ts|tsx|js|jsx|kt|swift|vue|json|md|sh|tscn|tres)$", ref):
        return _noext(ref)                      # a path
    return ref.replace(".", "/")                # a dotted module


def maps_onto(ref, declared):
    """True when a missing module (dotted) or path `ref` is one of the declared paths (suffix match on whole path components, extension ignored)."""
    r = _canon_ref(ref)
    if not r:
        return False
    for d in declared:
        dn = _noext(d)
        if dn == r or dn.endswith("/" + r) or r.endswith("/" + dn):
            return True
    return False


def _missing_refs(text, vcmd):
    refs = []
    refs += re.findall(r"No module named '([\w.]+)'", text)
    for name, mod in re.findall(r"cannot import name '(\w+)' from '([\w.]+)'", text):
        refs.append(mod)
    refs += re.findall(r"No such file or directory: '([^']+)'", text)
    refs += re.findall(r"([^\s:'\"]+): No such file or directory", text)
    refs += re.findall(r"can't open file '([^']+)'", text)
    refs += [x for x in re.findall(r"Could not find script:?\s*(\S+)", text) if "/" in x or "." in x]
    refs += [x.split("::")[0] for x in re.findall(r"(?:file or directory not found|ERROR: not found):?\s*(\S+)", text)]
    if ("GUT-target-missing" in text or "Could not find script" in text) and not refs:
        refs += [x.replace("res://", "") for x in re.findall(r"-gtest=([^\s'\"]+)", vcmd or "")]
        for g in re.findall(r"-gdir=([^\s'\"]+)", vcmd or ""):          # -gdir=res://a,res://b: a directory that never existed (B1b)
            refs += [x.replace("res://", "") for x in g.split(",") if x]
    return [r.strip().rstrip(".,;") for r in refs if r.strip()]


def _declared_in_cmd(vcmd, declared):
    toks = re.findall(r"[\w./:-]+", vcmd or "")
    return any(maps_onto(t, declared) for t in toks if "/" in t or "." in t)


_GUT_ENV_MARKERS = re.compile(r"GUT-not-imported|class_names have not been imported")
_LOAD_FAIL_REF = re.compile(r"Failed to load script\s+[\"']?([^\"'\s]+\.gd)|\((res://[^:)\s]+\.gd):\d+\)")


def _gut_load_failure_is_new_target(text, vcmd, declared):
    """True when GUT could not load/parse scripts, EVERY failing script maps onto a path the item declares, none of them is the test file the VERIFY runs (-gtest), and the output is not
    the unseeded-import-cache failure. Narrows 'Failed to load script' / 'Parse Error' behind a nonzero exit: a missing/broken class the item creates is a legitimate red-before; a
    test file that does not even load, or a script nobody declared, stays bad-spec (the VERIFY or the environment is broken)."""
    if _GUT_ENV_MARKERS.search(text) or not declared:
        return False
    refs = [a or b for a, b in _LOAD_FAIL_REF.findall(text)]
    if not refs:
        return False
    tests = [_noext(x) for g in re.findall(r"-gtest=([^\s'\"]+)", vcmd or "") for x in g.split(",") if x]
    return all(maps_onto(r, declared) and _noext(r) not in tests for r in refs)


def classify(item_line, rc, out_tail):
    vcmd = verify_of(item_line)
    if not vcmd:
        return "no-verify", ""
    if rc is None:
        return "bad-spec", "no-rc"
    text = out_tail or ""
    gut_norun = "gut_cmdln" in vcmd and bool(_GUT_NORUN.search(text) or (rc == 0 and _GUT_NORUN_RC0.search(text)))
    if rc == 0 and "GUT-target-missing" not in text and "no-tests-ran" not in text and not gut_norun:
        return "passes-before", ""
    if rc in (124, 126, 127):
        return "bad-spec", "unrunnable"
    if _FATAL_VERIFY.search(text):
        return "bad-spec", "crash-unexplained"
    declared = declared_paths(item_line)
    if "Could not find script" in text or "GUT-target-missing" in text:
        refs = _missing_refs(text, vcmd)
        if refs and all(maps_onto(r, declared) for r in refs) or (not refs and _declared_in_cmd(vcmd, declared)):
            return "red", "new-target"
        return "bad-spec", "crash-unexplained"
    if gut_norun and rc != 0 and _gut_load_failure_is_new_target(text, vcmd, declared):
        return "red", "new-target"                 # a bug-fix / create item whose red-before IS a script the item declares failing to load or parse (not the test file, not an import-cache problem)
    if gut_norun:                                  # GUT ran nothing (failed to load / parse the script, nothing imported, 0 tests) behind exit 0 or a bare failure: not an assertion, never a pass
        return "bad-spec", "crash-unexplained"
    # (pytest prints 'no tests ran' after a 'not found' error too: a missing target is judged as missing, not as an empty collection)
    if rc != 5 and (rc == 4 or _MISSING_FILE.search(text) or _MISSING_MOD.search(text)):
        refs = _missing_refs(text, vcmd)
        if refs:
            if all(maps_onto(r, declared) for r in refs):
                return "red", "new-target"
        elif rc == 4 and _declared_in_cmd(vcmd, declared):
            return "red", "new-target"
        return "bad-spec", "crash-unexplained"
    if rc == 5 or _NO_TESTS.search(text):
        # the item creates that test: the pytest target file is one of its declared paths
        if any(maps_onto(t, declared) for t in re.findall(r"[\w./-]+\.py", vcmd)):
            return "red", "new-target"
        return "bad-spec", "no-tests-collected"
    if "AssertionError" in text:
        return "red", "assert"
    if rc == 1 and not (_OTHER_EXC.search(text) or _frame_then_bare_exc(text)):
        return "red", "assert"
    return "bad-spec", "crash-unexplained"


# ---------------------------------------------------------------- CLI
def _canon(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("- [ ]") and not re.search(r"VERIFY:\s*`[^`]+`", line):
                c = extract_verify(line)
                if c:
                    c = clean_bare_verify(c)
                    if "`" not in c:
                        line = re.sub(r"VERIFY:\s*.+?(\s*\(cat:)", lambda m: "VERIFY: `%s`%s" % (c, m.group(1)), line, count=1)
            out.append(line)
    sys.stdout.write("\n".join(out) + "\n")


def _rows(itemfile, rowsfile):
    items = {}
    with open(itemfile, encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            items[n] = raw.rstrip("\n")
    with open(rowsfile, encoding="utf-8", errors="replace") as f:
        for raw in f:
            p = raw.rstrip("\n").split("\t")
            if len(p) < 3:
                continue
            n = int(p[0])
            result, rc_s = p[1], p[2]
            why = p[3] if len(p) > 3 else ""
            tail = p[4] if len(p) > 4 else ""
            line = items.get(n, "")
            try:
                rc = int(rc_s)
            except ValueError:
                rc = None
            if result == "NO_VERIFY_CLAUSE":
                v, sub, detail = "no-verify", "", ""
            elif result in ("SKIPPED_DENYLIST",):
                v, sub, detail = "bad-spec", "denylisted", "SKIPPED_DENYLIST"
            elif result in ("PASS", "FAIL", "TIMEOUT", "UNRUNNABLE"):
                if result == "FAIL" and rc == 0:
                    rc = 1                      # GUT / pytest "no tests ran" detected a failure behind a zero exit code
                if result == "PASS":
                    rc = 0
                v, sub = classify(line, rc, tail if result != "TIMEOUT" else "")
                detail = ""
                if v == "bad-spec" and sub == "crash-unexplained":
                    detail = "crashed instead of asserting: %s" % re.sub(r".*tail=", "", tail)[:120]
                elif v == "bad-spec" and sub == "unrunnable":
                    detail = "%s %s" % (result, why)
                elif v == "bad-spec":
                    detail = why
            else:
                v, sub, detail = "bad-spec", "no-rc", "%s %s" % (result or "unknown", why)
            sys.stdout.write("%d\t%s\t%s\t%s\t%s\n" % (n, v, detail.replace("\t", " ").replace("\n", " "), sub, "" if rc is None else rc))


def main(argv):
    if len(argv) >= 3 and argv[1] == "canon":
        _canon(argv[2])
        return 0
    if len(argv) >= 2 and argv[1] == "extract":
        v = verify_of(sys.stdin.readline().rstrip("\n"))
        sys.stdout.write((v or "") + "\n")
        return 0
    if len(argv) >= 4 and argv[1] == "rows":
        _rows(argv[2], argv[3])
        return 0
    sys.stderr.write("usage: ovn_spec_classify.py canon <file> | extract | rows <file> <rows.tsv>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
