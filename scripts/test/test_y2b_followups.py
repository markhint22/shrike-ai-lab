#!/usr/bin/env python3
"""Y2b follow-ups (2026-11-08) for claude_queue_bridge.body_key. Hermetic, no box, no network, no ntfy.
  D1  path-free prose that merely CONTAINS a closing-annotation marker is never peeled as a tail (147-pair matrix + the three review examples); real closing annotations still normalise; the re-tag rate on the
      real CLAUDE_QUEUE.md + CLAUDE_QUEUE_DONE.md stays >= 99.5%
  D2  the date gate of ALREADY DONE is tested in EVERY layer on its own (unit regex, header regex, _PROVEN_RE, whole line), so a mutant of one layer can no longer hide behind the others
  D3  _peel_tail uses index arithmetic: same output as the copy-based reference on the real corpus + fuzz, and it makes no prefix copy (tracemalloc), linear on a 1 MB line
  label  the bridge docstring and run_all.sh say the done-check is shadow by default, not 'default ON'
  MUTANTS  copies of the sources with one substitution each; at least one check must fail on every mutant
Env Y2B_ROOT points at another copy of the overnight-queue tree (the mutant runner)."""
import importlib.util
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tracemalloc

os.environ["TZ"] = "UTC"
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.abspath(os.path.join(HERE, "..", ".."))
ROOT = os.environ.get("Y2B_ROOT") or REAL
BR = os.path.join(ROOT, "claude_queue_bridge.py")
BASE = os.path.realpath(tempfile.mkdtemp(prefix="y2b-"))
FAILS, PASSES = [], [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


def rd(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


spec = importlib.util.spec_from_file_location("cqb_y2b", BR)
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


def KB(t, repo="r"):
    return B.body_key(repo, t)


# ------------------------------------------------------------------------------------------------ D1: prose tails
D1_NAMED = [
    ("Retry failed jobs with backoff (see below) NOTE: explain backoff jitter", "Retry failed jobs with backoff (see below) NOTE: explain timeouts"),
    ("Reduce bundle size by 10% (target). DONE (tree-shake lodash)", "Reduce bundle size by 10% (target). DONE (tree-shake moment)"),
    ("Fix typo in README. ALREADY DONE (verified 2026-01-01) in the header, still wrong in the footer", "Fix typo in README. ALREADY DONE (verified 2026-01-01) in the header, still wrong in the sidebar"),
]
for i_, (a_, c_) in enumerate(D1_NAMED):
    chk("D1 review example %d: distinct keys" % i_, KB("- [ ] " + a_) != KB("- [ ] " + c_), a_)

HEADS = ["Retry failed jobs with backoff", "Reduce bundle size by 10% (target).", "Fix typo in README.", "Parse the log (see below)", "Add a flag to the CLI -",
         "Cache the result for one hour; see notes.", "Rename the column (old name kept)"]
TAILS = [
    ("NOTE: explain backoff jitter", "NOTE: explain timeouts"),
    ("DONE (tree-shake lodash)", "DONE (tree-shake moment)"),
    ("DONE (2026-01-01 cutoff) and purge queue", "DONE (2026-01-01 cutoff) and flush cache"),
    ("DONE (x @ abc1234) then log metrics", "DONE (x @ abc1234) then emit events"),
    ("DONE 2026-01-01 sidebar only", "DONE 2026-01-01 header only"),
    ("**DONE** badge in the header", "**DONE** badge in the sidebar"),
    ("✅ DONE badge for finished", "✅ DONE badge for failed"),
    ("— DONE badge for finished", "— DONE badge for failed"),
    ("ALREADY DONE (verified 2026-01-01) in the header, still wrong in the footer", "ALREADY DONE (verified 2026-01-01) in the header, still wrong in the sidebar"),
    ("ALREADY DONE (verified 2026-01-01), header only", "ALREADY DONE (verified 2026-01-01), footer only"),
    ("ALREADY DONE the way the spec says", "ALREADY DONE the way the doc says"),
    ("ALREADY DONE verified 2026-01-01 for header", "ALREADY DONE verified 2026-01-01 for footer"),
    ("ALREADY DONE for 2026-01-01 header", "ALREADY DONE for 2026-01-01 footer"),
    ("STALE TICKET, no action needed text", "STALE TICKET, no action needed banner"),
    ("**STALE TICKET** badge", "**STALE TICKET** label"),
    ("STALE TICKET, no action (verified 2026-01-01) badge", "STALE TICKET, no action (verified 2026-01-01) label"),
    ("SKIPPED (verified 2026-01-01) rows", "SKIPPED (verified 2026-01-01) cols"),
    ("(done 2026-01-01: x) support", "(done 2026-01-01: y) support"),
    ("- TRIAGE column", "- TRIAGE badge"),
    ("(2026-01-01 cutoff handling)", "(2026-01-01 cutoff logging)"),
    ("(see line 12)", "(see line 13)"),
]
bad_ = [(h_, a_[:40]) for h_ in HEADS for a_, c_ in TAILS if KB("- [ ] " + h_ + " " + a_) == KB("- [ ] " + h_ + " " + c_)]
chk("D1 matrix: %d path-free prose pairs (%d heads x %d tails) all keep distinct keys" % (len(HEADS) * len(TAILS), len(HEADS), len(TAILS)), not bad_, bad_[:4])
# one assertion per marker family, so a mutant of one gate names itself
for a_, c_ in TAILS:
    ok_ = all(KB("- [ ] " + h_ + " " + a_) != KB("- [ ] " + h_ + " " + c_) for h_ in HEADS)
    chk("D1 family distinct: %s" % a_[:50], ok_)

# real closing annotations (no path, no task prose after the header) still normalise to the open form
BASE_T = "Add retry with backoff to the sync worker and log each attempt"
CLOSED_OK = [
    " (cat:impl; multifile:no) NOTE: checked by hand",
    " (cat:impl; multifile:no) DONE (shipped abc)",
    " (cat:impl) ✅ DONE (2026-11-05, repo @ abc1234)",
    " (cat:impl) **DONE** (2026-11-05)",
    " — DONE",
    " ALREADY DONE (verified 2026-11-05): the worker already retries",
    " ALREADY DONE — verified 2026-11-05: the worker already retries",
    " **ALREADY DONE, stale item (verified 2026-09-05):** the worker already retries",
    " ALREADY DONE by the fleet — verified 2026-09-05.",
    " STALE TICKET, no action (verified 2026-11-05) - superseded",
    " **STALE TICKET** - superseded",
    " SKIPPED (verified 2026-09-08) - out of scope",
    " (done 2026-09-12: claude sweep) tests pass",
    " — TRIAGE 2026-10-12 DONE: stale",
    " (2026-11-05)",
    " (2026-10-17 claude sweep: VERIFY text corrected)",
]
for cl_ in CLOSED_OK:
    chk("D1 closing annotation still normalised: %r" % cl_[:48], KB(BASE_T + cl_) == KB(BASE_T), cl_)
chk("D1 legacy dated-header DONE still normalised", KB("[T3] a thing (2026-09-04, gitlark @ 6a483f1) — DONE (async db fixture).") == KB("[T3] a thing (2026-09-04, gitlark @ 6a483f1) \u2014"))

# real queue + archive re-tag rate (same measure as test_y2_bridge_harvest N1 / test_y2_fixes r2/2)
_CATRE = re.compile(r"\(cat:[^)]*\)")
_rf = [os.path.join(REAL, "..", "..", f) for f in ("CLAUDE_QUEUE_DONE.md", "CLAUDE_QUEUE.md")]
if all(os.path.exists(f_) for f_ in _rf):
    n_, ok_ = 0, 0
    for f_ in _rf:
        for ln_ in rd(f_).splitlines():
            m_ = B.CHECKED_ITEM_RE.match(ln_)
            if not m_ or "[CLAUDE]" not in ln_:
                continue
            repo_ = B.infer_repo(m_.group(1), "")
            c_ = _CATRE.search(m_.group(1))
            if not repo_ or not c_:
                continue
            raw_ = B.REPO_PREFIX_RE.sub("", re.sub(r"^\[CLAUDE\]\s*", "", m_.group(1)[:c_.end()]))
            n_ += 1
            ok_ += B.body_key(repo_, ln_) == B.body_key(repo_, _CATRE.sub("(cat:test; multifile:yes)", raw_) + " [feat:%s-20261107-newtag]" % repo_)
    print("  real queue+archive re-tag match: %d/%d = %.2f%%" % (ok_, n_, 100.0 * ok_ / max(n_, 1)))
    chk("D1 real queue+archive re-tag match rate >= 99.5%% (%d/%d)" % (ok_, n_), n_ < 100 or ok_ * 1000 >= n_ * 995, (ok_, n_))

# bare NOTE: only straight after a bounded annotation
chk("D1 NOTE: after a bounded (cat:..) group is a tail", KB("Do the thing in the worker (cat:impl; multifile:no) NOTE: aside") == KB("Do the thing in the worker"))
chk("D1 NOTE: after task prose / a plain parenthetical is task text", KB("Do the thing (see below) NOTE: aside") != KB("Do the thing (see below)"))

# ------------------------------------------------------------------------------------------------ D2: the date gate of ALREADY DONE, one assertion per layer
AD_UNITS = [rx for rx, kind, shape in B.TAIL_UNITS if shape == "already"]
PROSE_AD = "ALREADY DONE the way the spec says in a/x.py"
chk("D2 one ALREADY DONE unit", len(AD_UNITS) == 1, len(AD_UNITS))
chk("D2 layer 1 (unit regex): no date / verified date in the first 100 chars -> no match", not AD_UNITS[0].match(PROSE_AD) and not AD_UNITS[0].match("ALREADY DONE the way the spec says"))
chk("D2 layer 1: a dated ALREADY DONE does match", bool(AD_UNITS[0].match("ALREADY DONE (verified 2026-01-01) - x")))
chk("D2 layer 2 (header regex): needs a verified / date header", not B._HDR_AD.match("ALREADY DONE the way the spec says") and bool(B._HDR_AD.match("ALREADY DONE (verified 2026-01-01)")) and bool(B._HDR_AD.match("ALREADY DONE verified 2026-01-01:")))
chk("D2 layer 3 (_PROVEN_RE): needs a verified date", not B._PROVEN_RE.match("ALREADY DONE the way the spec says") and bool(B._PROVEN_RE.match("ALREADY DONE (verified 2026-01-01) x")))
chk("D2 layer 4 (_tail_ok): an undated ALREADY DONE tail is never ok after a sentence end", not B._tail_ok("f", ".", PROSE_AD, None, 0, "already"))
chk("D2 whole line: undated 'ALREADY DONE ... a/x.py' vs its b/y.py twin keep distinct keys",
    KB("- [ ] Parse the log. ALREADY DONE the way the spec says in a/x.py") != KB("- [ ] Parse the log. ALREADY DONE the way the spec says in b/y.py"))
chk("D2 whole line, no path: undated ALREADY DONE twins stay distinct", KB("- [ ] Parse the log. ALREADY DONE the way the spec says") != KB("- [ ] Parse the log. ALREADY DONE the way the doc says"))
chk("D2 whole line, letter before the marker (no sentence end): undated twins stay distinct",
    KB("- [ ] Parse the log ALREADY DONE the way the spec says in a/x.py") != KB("- [ ] Parse the log ALREADY DONE the way the spec says in b/y.py"))
chk("D2 whole line: the dated twin IS a closing annotation (peeled)", KB("- [ ] Parse the log. ALREADY DONE (verified 2026-01-01) - see a/x.py") == KB("- [ ] Parse the log."))

# header-shaped weak tails still need a closing token before them and no file path in the tail (gates layered behind the header check)
GATE_PAIRS = [
    ("Mark the job DONE (2026-01-01, r @ abc1234) - then purge queue", "Mark the job DONE (2026-01-01, r @ abc1234) - then flush cache"),
    ("Wrap the call (see x) DONE (2026-01-01, r @ abc1234) - emit in a/x.py", "Wrap the call (see x) DONE (2026-01-01, r @ abc1234) - emit in b/y.py"),
    ("Mark the thing ALREADY DONE 2026-01-01 - header only", "Mark the thing ALREADY DONE 2026-01-01 - footer only"),   # header-shaped free tail, letter before it, no `verified`: not proven
]
for i_, (a_, c_) in enumerate(GATE_PAIRS):
    chk("D2 weak-tail gate pair %d: distinct keys" % i_, KB("- [ ] " + a_) != KB("- [ ] " + c_), a_)


# ------------------------------------------------------------------------------------------------ D3: index arithmetic, identical behaviour
def ref_peel(body):
    """The round-6 algorithm (a prefix copy per token start), driven by the module's CURRENT unit table and _tail_ok: the only difference to B._peel_tail is the copying."""
    t = " ".join(body.split())
    n = len(t)
    lo = max(0, n - B.TAIL_WINDOW)
    if lo and not t[lo - 1].isspace():
        sp = t.find(" ", lo)
        lo = n if sp < 0 else sp + 1
    pos = lo
    while pos < n:
        if pos == 0 or t[pos - 1] == " ":
            before = t[:pos].rstrip()
            if before:
                for rx, kind, shape in B.TAIL_UNITS:
                    m = rx.match(t, pos)
                    if m and B._tail_ok(kind, before[-1], m.group(0), t, len(before), shape):
                        return before
        pos += 1
    return None


def chain(fn, body):
    out, b_ = [], body
    for _ in range(B.MAX_PEELS):
        nb = fn(b_)
        if nb is None:
            break
        out.append(nb)
        b_ = nb
    return out


corp, nlines = [], 0
for f_ in _rf:
    for ln_ in rd(f_).splitlines():
        corp.append(ln_)
if corp:
    diff_ = [ln_[-80:] for ln_ in corp if chain(B._peel_tail, ln_) != chain(ref_peel, ln_)]
    chk("D3 index-arithmetic _peel_tail == copy-based reference on the real corpus (%d lines)" % len(corp), not diff_, diff_[:2])
    diff_n = [ln_[-80:] for ln_ in corp[:3000] if chain(lambda x: B._peel_tail(x, False), ln_) != chain(ref_peel, ln_)]
    chk("D3 same with normalized=False", not diff_n)

VOC = ["DONE", "**DONE**", "✅", "NOTE:", "ALREADY DONE", "STALE TICKET,", "no action", "(verified", "2026-01-01)", "2026-01-01", "(cat:impl)", "(cat:x;", "multifile:no)", "(auto-closed", "2026-02-02:", "x)", "(",
       ")", "—", "-", "_(DONE", "x)_", "<!--", "closed", "-->", "a/x.py", "word", "words", "the", "TRIAGE", "(done", "claude", "@", "abc1234", "SKIPPED", "(REOPENED", "(retired", ":", ".", "  ", "\t", "(2026-03-03,", "r", "@ abc1234)", "**"]
rnd = random.Random(20261108)
fz_bad = []
for _i in range(6000):
    body = " ".join(rnd.choice(VOC) for _ in range(rnd.randint(1, 18)))
    if chain(B._peel_tail, body) != chain(ref_peel, body):
        fz_bad.append(body)
    if B._peel_tail(body) != ref_peel(body):
        fz_bad.append(body)
chk("D3 fuzz: 6000 random marker soups give identical peels (single + chain)", not fz_bad, fz_bad[:2])
long_ = ("word " * 400) + "(cat:a) DONE (2026-01-01, r @ abc1234)"
chk("D3 window edge: a long line peels the same", chain(B._peel_tail, long_) == chain(ref_peel, long_) and len(chain(B._peel_tail, long_)) >= 2)

huge = "x " * 500000
huge = huge.rstrip()
tracemalloc.start()
B._peel_tail(huge, True)
cur_, peak_ = tracemalloc.get_traced_memory()
tracemalloc.stop()
chk("D3 no prefix copy: a no-peel pass over a 1 MB normalised line allocates < 200 KB (peak %d B)" % peak_, peak_ < 200000, peak_)
line40 = ("word " * 200000) + " (cat:a)" * 40
t0 = time.time()
k40 = KB(line40)
el_ = time.time() - t0
chk("D3 1 MB line with a 40-group peel chain keys in < 1.0 s (%.3f s)" % el_, el_ < 1.0, el_)
chk("D3 that chain peels all 40 groups (key == the bare text key)", k40 == KB("word " * 200000))
t0 = time.time()
KB("x " * 500000)
el_ = time.time() - t0
chk("D3 1 MB of 1-char tokens keys in < 1.0 s (%.3f s)" % el_, el_ < 1.0, el_)

for nm_, sh_ in (("proofless DONE parentheticals behind (cat:..) groups", "DONE (web) (cat:a) " * 5000), ("bare NOTE: soup", "NOTE: " * 17000), ("(cat:..) NOTE: pairs", "(cat:a) NOTE: " * 7000)):
    t0 = time.time()
    KB(sh_)
    el_ = time.time() - t0
    chk("D1 context scans stay linear: 100 KB %s keys in < 1.0 s (%.3f s)" % (nm_, el_), el_ < 1.0, el_)

# ------------------------------------------------------------------------------------------------ labels
import ast
_doc = ast.get_docstring(ast.parse(rd(BR))) or ""
_i = _doc.index("OVN_HARVEST_DONE_CHECK")
_seg = _doc[max(0, _i - 60):_i + 160]
chk("label: bridge docstring does not call the done-check 'default ON'", "default ON" not in _seg, _seg)
chk("label: bridge docstring says the done-check is shadow by default", "default `shadow`" in _seg, _seg)
_ra = rd(os.path.join(ROOT, "scripts", "test", "run_all.sh"))
_y2 = [ln_ for ln_ in _ra.splitlines() if "test_y2_bridge_harvest.py" in ln_ and "echo" in ln_]
chk("label: run_all.sh Y2 bridge-harvest section exists and does not say 'default ON'", len(_y2) == 1 and "default ON" not in _y2[0] and "shadow by default" in _y2[0], _y2)
chk("label: run_all.sh registers this test before the final pass line", "test_y2b_followups.py" in _ra and _ra.index("test_y2b_followups.py") < _ra.index("finish || rc=1"))

# ------------------------------------------------------------------------------------------------ mutants
MUTANTS = [
    ("D1 NOTE: peeled after any boundary char", "claude_queue_bridge.py", "and not _PATH_RE.search(g) and t is not None and _ends_with_bounded(t, e)", "and not _PATH_RE.search(g)"),
    ("D1 closing shape unchecked", "claude_queue_bridge.py", "def _closing_shape_ok(shape, g, stamped=None):\n", "def _closing_shape_ok(shape, g, stamped=None):\n    return True\n"),
    ("D1 proofless DONE parenthetical accepted", "claude_queue_bridge.py", 'and not m.group("colon") and not (stamped is not None and stamped()):', "and False:"),
    ("D1 prose after the header accepted", "claude_queue_bridge.py", "    return bool(_PAREN_CHAIN_RE.match(rem))", "    return True"),
    ("D1 completion-header context ignored", "claude_queue_bridge.py", "stamped = lambda: bool(_DATED_HDR_END_RE.search(t, max(0, e - 160), e)) or _ends_with_bounded(t, e)", "stamped = lambda: False"),
    ("D1 dated parenthetical takes any prose after the date", "claude_queue_bridge.py", '(?=[,;)]|\\s+claude\\b)"', '"'),
    ("D2 ALREADY DONE unit without the date gate", "claude_queue_bridge.py", 'ALREADY DONE\\*{0,2}" + _TAIL_DATE + r".*$"', 'ALREADY DONE\\*{0,2}" + r".*$"'),
    ("D2 ALREADY DONE header without the date gate", "claude_queue_bridge.py", '+ _D + r"\\b)" + _COLON)\n_HDR_SKIPPED', '+ _D + r"\\b|)" + _COLON)\n_HDR_SKIPPED'),
    ("D2 _PROVEN_RE without the verified date", "claude_queue_bridge.py", 'ALREADY DONE\\*{0,2}\\b[^\\n]{0,60}?\\b" + _VER + r"\\s*\\(?\\s*" + _D + r"|STALE TICKET,\\s*no action\\s*\\(" + _VER + r"|SKIPPED\\s*\\(" + _VER + r"|\\*\\*STALE TICKET\\*\\*|\\(done\\s+" + _D)\n', 'ALREADY DONE\\*{0,2}\\b|STALE TICKET,\\s*no action\\s*\\(" + _VER + r"|SKIPPED\\s*\\(" + _VER + r"|\\*\\*STALE TICKET\\*\\*|\\(done\\s+" + _D)\n'),
    ("D2 free tails need no sentence end / proof", "claude_queue_bridge.py", "        return bool(_PROVEN_RE.match(g)) and not _PATH_RE.search(g)   # date+`verified`", "        return not _PATH_RE.search(g)   # date+`verified`"),
    ("D3 prefix copied per token start", "claude_queue_bridge.py", "        bch = t[e - 1]\n", "        bch = t[e - 1]\n        _cp = t[:pos].rstrip()\n"),
    ("label: docstring says default ON again", "claude_queue_bridge.py", "default `shadow`: it only logs the would-skip", "default ON: it only logs the would-skip"),
    ("label: run_all says default ON again", "scripts/test/run_all.sh", "done-check shadow by default (enforce skips)", "done-check default ON"),
    ("label: run_all drops this test", "scripts/test/run_all.sh", "test_y2b_followups.py", "test_y2b_gone.py"),
]


def mutants():
    bad = 0
    for name, rel, old, new in MUTANTS:
        mq = os.path.join(BASE, "mut")
        shutil.rmtree(mq, ignore_errors=True)
        os.makedirs(os.path.join(mq, "scripts", "test"))
        shutil.copy(os.path.join(REAL, "claude_queue_bridge.py"), os.path.join(mq, "claude_queue_bridge.py"))
        shutil.copy(os.path.join(REAL, "scripts", "test", "run_all.sh"), os.path.join(mq, "scripts", "test", "run_all.sh"))
        p_ = os.path.join(mq, rel)
        s = open(p_, encoding="utf-8").read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        with open(p_, "w", encoding="utf-8") as f:
            f.write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, Y2B_ROOT=mq, Y2B_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


if os.environ.get("Y2B_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
shutil.rmtree(BASE, ignore_errors=True)
print("test_y2b_followups: %d passed, %d failed" % (PASSES[0], len(FAILS)))
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
sys.exit(1 if FAILS else 0)
