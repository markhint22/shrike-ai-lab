#!/usr/bin/env python3
"""2026-10-10 work-supply package (analysis_1010 F1/F2/F3/F7(py side), IPTV-1, IPTV-7, B5, B9a, BX-10).

  F1/B5/BX-10  ovn_work_supply.pullable_count accepts the LIST ovn_backlog_eligibility.pullable() returns (it raised TypeError on every call and used a looser local count)
  F2           ovn_spec_classify._OTHER_EXC no longer treats an exception NAME quoted in ruff's F401 message (`app.x.SSRFError` imported but unused) as a crash
  F3           _filter: a PARKED (AUTO-SKIP / [CLAUDE] / HUMAN-ONLY) supply line is not 'open' and does not hold the file; the gap is reported as 'parked'
  IPTV-1       queue_refill.relocate_new_tests: position-based rewrite, `cd <dir> && pytest tests/x.py` is read relative to the cd (no iptv-backend/iptv-backend/)
  IPTV-7/B9a   a bad-spec / no-verdict is printed with the offending spec text and the reason; the infra alert carries them and escalates (error) while the streak lasts

Every check runs against the real module AND against a MUTANT (the source with exactly one piece of logic broken) and must FAIL on the mutant - a green run proves
the check bites. The anchor of a mutation must exist exactly once, otherwise the test itself fails. No kill -0, no grep on comments, all temp paths realpath'ed."""
import contextlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
ROOT = os.path.abspath(os.path.join(SCRIPTS, ".."))
os.environ["OVN_PARKED_SITES_GUARD"] = "off"     # the eligibility module would otherwise scan the temp dir's parent for unconverted BLOCKED sites
os.environ.pop("OVN_INGEST_BAN_FILTER", None)
sys.path.insert(0, SCRIPTS)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def rd(*parts):
    try:
        with open(os.path.join(*parts), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def wr(p, body):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(body)


# ---------------------------------------------------------------- module loading (+ mutants)
SUPPLY_SRC = rd(SCRIPTS, "ovn_work_supply.py")
_n = [0]


def load_supply(src=None, tag="real"):
    """The supply module in a temp dir next to ovn_mission_lint.py and ovn_backlog_eligibility.py (what a deployed scripts/ dir looks like)."""
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="supplyr10-"))
    wr(os.path.join(d, "ovn_work_supply.py"), SUPPLY_SRC if src is None else src)
    for f in ("ovn_mission_lint.py", "ovn_backlog_eligibility.py"):
        shutil.copy(os.path.join(SCRIPTS, f), d)
    spec = importlib.util.spec_from_file_location("ovn_work_supply_r10_%s_%d" % (tag, _n[0]), os.path.join(d, "ovn_work_supply.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m._moddir = d
    return m


def mutate(src, old, new):
    c = src.count(old)
    if c != 1:
        ok("mutation anchor exists exactly once: %r" % old[:80], False, "found %d" % c)
        return None
    return src.replace(old, new)


def mut_check(label, chk, old, new, src=None, loader=None):
    """chk(M) is True on the real module and False on the mutant."""
    src = SUPPLY_SRC if src is None else src
    loader = loader or load_supply
    ok("%s: passes on the real module" % label, bool(chk(loader())))
    ms = mutate(src, old, new)
    if ms is None:
        return
    crash = ""
    try:
        bad = bool(chk(loader(ms, "mut")))
    except Exception as e:
        bad, crash = False, " [mutant raised %s]" % type(e).__name__
    ok("MUTATION caught (%s): the same check FAILS when the logic is broken%s" % (label, crash), not bad)


# ---------------------------------------------------------------- fixtures
def mk(kind, file, symbols, tier="T2", cat="python"):
    return {"kind": kind, "file": file, "tier": tier, "cat": cat, "text": "do the thing %s" % ",".join(symbols), "verify": "false", "symbols": symbols}


def env_dir(files, backlog="# backlog\n", progress="# progress\n", done="", banned=None):
    d = os.path.realpath(tempfile.mkdtemp(prefix="ovnr10-"))
    clone = os.path.join(d, "repos", "demo")
    for rp, body in files.items():
        wr(os.path.join(clone, rp), body)
    wr(os.path.join(clone, "OVERNIGHT_PROGRESS.md"), progress)
    if done:
        wr(os.path.join(clone, "OVERNIGHT_DONE.md"), done)
    if banned:
        wr(os.path.join(clone, ".queue-hard-banned-files"), banned)
    wr(os.path.join(d, "backlog", "demo.md"), backlog)
    os.makedirs(os.path.join(d, "state"), exist_ok=True)
    return d


def run_main(M, d, *flags, spec=None):
    M.OVN_DIR = d
    M.MIN_BACKLOG = 24
    if spec is not None:
        M.spec_check = spec
    buf, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
        M.main(["ovn_work_supply.py", "demo"] + list(flags))
    return buf.getvalue()


OPEN_ROUTER = {"iptv-backend/app/routers/limited.py": "from app.core.limiter import limiter\n@router.get('/a')\n@limiter.limit('5/minute')\ndef a(request):\n    return 1\n",
               "iptv-backend/app/routers/open_router.py": "@router.get('/x')\ndef x():\n    return 1\n@router.post('/y')\nasync def y(body):\n    return 2\n"}   # exactly one no-rate-limit gap
T_NORMAL = "- [ ] [T2] app/a.py — fix a. VERIFY: `false`. (cat:python; multifile:no; supply:swallowed-exception)"
T_PARKED = "- [ ] [AUTO-SKIP after 2 no-op cycles] [T2] app/b.py — fix b. VERIFY: `false`. (cat:python)"
T_BANNED = "- [ ] [T2] addons/gut/x.gd — vendored. VERIFY: `false`. (cat:godot)"
T_QUEUED = "- [ ] [T2] app/d.py — fix d. VERIFY: `false`. (cat:python)"
T_OPEN_E = "- [ ] [T2] app/e.py — fix e. VERIFY: `false`. (cat:python)"
T_PARKED_F = "- [ ] [CLAUDE] [T2] app/f.py — fix f. VERIFY: `false`. (cat:python)"

# ================================================================ F1 / B5 / BX-10: pullable_count
print("== F1/B5/BX-10 pullable_count accepts the list pullable() returns")
BL = "\n".join([T_NORMAL, T_PARKED, T_BANNED, T_QUEUED]) + "\n"
PR = "\n".join([T_QUEUED, T_OPEN_E, T_PARKED_F]) + "\n"          # 2 doable open (d, e) + 1 parked


def chk_list(M):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        a = M.pullable_count(BL, PR, "")                       # pullable = [normal, banned-target] (no ban list given) + 2 doable queued = 4
        b = M.pullable_count(BL, PR, "", [])                   # [] = no repo ban patterns, but addons/ is always vendored: pullable = [normal] -> 3
        c = M.pullable_count(BL, PR, "")                       # second call: still no warning
    msg = err.getvalue()
    return a == 4 and b == 3 and c == 4 and "TypeError" not in msg and "failed" not in msg and "unusable" not in msg


mut_check("(F1) a list result counts as open_count(progress) + len(list); banned patterns reach pullable()", chk_list,
          "            if isinstance(n, (list, tuple)):\n                return open_count(progress_text) + _distinct_lines(n)\n",
          "            if False:\n                return open_count(progress_text) + _distinct_lines(n)\n")
mut_check("(F1b) the banned patterns are handed to pullable()", chk_list,
          "            if banned is not None and _accepts_banned(fn):", "            if False:")


def chk_warn_once(M):
    """A pullable() that always fails warns ONCE per process (it used to print one line per call), and the local count is used."""
    d = os.path.realpath(tempfile.mkdtemp(prefix="elig-"))
    wr(os.path.join(d, "scripts", "ovn_backlog_eligibility.py"), "def pullable(b, p, d=''):\n    raise RuntimeError('boom')\n")
    M2 = M
    os.unlink(os.path.join(M2._moddir, "ovn_backlog_eligibility.py"))     # force the $OVN_DIR/scripts lookup
    M2._WARNED.clear()
    M2.OVN_DIR = d
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        r = [M2.pullable_count("- [ ] [T2] c — y\n", "") for _ in range(3)]
    return r == [1, 1, 1] and err.getvalue().count("RuntimeError: boom") == 1


mut_check("(F1c) the failure warning is printed once per process", chk_warn_once,
          "    if msg not in _WARNED:\n        _WARNED.add(msg)\n        sys.stderr.write(msg + \"\\n\")", "    sys.stderr.write(msg + \"\\n\")")


def chk_main_exhausted_uses_ban(M):
    """--on-exhausted needs pullable == 0: the only backlog item targets a vendored addon (queue_refill quarantines it), so the lane IS exhausted."""
    d = env_dir(OPEN_ROUTER, backlog="# backlog\n" + T_BANNED + "\n")
    out = run_main(M, d, "--on-exhausted", "--dry-run", spec=lambda repo, lines: {i: "red" for i in range(len(lines))})
    return "not exhausted" not in out and "gaps found" in out


mut_check("(F1d) main passes the repo's ban patterns to the pullable count", chk_main_exhausted_uses_ban,
          "have = pullable_count(backlog_t, progress_t, done_t, _load_banned(root))", "have = pullable_count(backlog_t, progress_t, done_t, None)")



def chk_dedupe_twins(M):
    """Identical backlog twins (same content, any whitespace / feat date) are ONE item for the lane: the old local count deduped them, pullable() does not."""
    twin_ws = T_NORMAL.replace("— fix a.", "—   fix  a.")
    twin_feat = T_NORMAL.replace("(cat:python;", "[feat:demo-20261009-q] (cat:python;")
    twin_feat2 = T_NORMAL.replace("(cat:python;", "[feat:demo-20261010-q] (cat:python;")
    bl = "\n".join([T_NORMAL, T_NORMAL, twin_ws, twin_feat, twin_feat2, T_OPEN_E.replace("app/e.py", "app/g.py")]) + "\n"
    # 2 doable open in PR (d, e) + distinct pullable: T_NORMAL(+ws twin), feat-tagged twin pair, g  -> normal, normal+feat, g  = 3 distinct
    return M.pullable_count(bl, PR, "") == 2 + 3


mut_check("(F1e) identical backlog twins are counted once", chk_dedupe_twins,
          "return open_count(progress_text) + _distinct_lines(n)", "return open_count(progress_text) + len(n)")

# ================================================================ F2: spec classifier
print("== F2 ruff F401 messages that name an exception class are red, not bad-spec")
import ovn_spec_classify as C  # noqa: E402

LINE = "- [ ] [T1] iptv-backend/app/core/limiter.py — remove. VERIFY: `python3 -m ruff check --select F401 --no-cache iptv-backend/app/core/limiter.py`. (cat:python; multifile:no; supply:unused-import)"
RUFF = {
    "SSRFError": "iptv-backend/app/core/limiter.py:3:30: F401 [*] `app.services.url_safety.SSRFError` imported but unused   |   help: Remove unused import: `app.services.url_safety.SSRFError` Found 1 error. [*] 1 fixable with the `--fix` option.",
    "IntegrityError": "iptv-backend/app/services/x.py:1:1: F401 [*] `sqlalchemy.exc.IntegrityError` imported but unused Found 1 error.",
    "HTTPException": "x.py:4:20: F401 [*] `fastapi.HTTPException` imported but unused Found 2 errors.",
}
for name, tail in RUFF.items():
    ok("ruff rc 1 naming %s -> red/assert" % name, C.classify(LINE, 1, tail) == ("red", "assert"), C.classify(LINE, 1, tail))
for exc in ("ZeroDivisionError: division by zero", "AttributeError: 'NoneType' object has no attribute 'x'", "builtins.KeyError: 'x'", "Traceback (most recent call last): File \"<string>\", line 1",
            "E       ValueError  tests/x.py:3: ValueError"):
    ok("NEGATIVE: a real crash '%s' is still bad-spec/crash-unexplained" % exc[:34], C.classify(LINE, 1, exc) == ("bad-spec", "crash-unexplained"), C.classify(LINE, 1, exc))
for exc in ("TypeError [ERR_INVALID_ARG_TYPE]: The path argument must be of type string", "Uncaught RangeError [ERR_OUT_OF_RANGE]: bad",
            "File \"/app/x.py\", line 3, in f x = 1/0 ZeroDivisionError", "Traceback-less File \"a.py\", line 9 in g raise ValueError"):
    ok("round-2: a crash without a trailing colon '%s' is still bad-spec/crash-unexplained" % exc[:34], C.classify(LINE, 1, exc) == ("bad-spec", "crash-unexplained"), C.classify(LINE, 1, exc))
for ex in ("note: File \"a.py\", line 3 mentions `app.x.SSRFError` imported but unused F401", "bare TypeError was named in a doc", "File \"a.py\", line 3 AssertionError"):
    ok("round-2 NEGATIVE: '%s' is not a crash" % ex[:34], C.classify(LINE, 1, ex) == ("red", "assert"), C.classify(LINE, 1, ex))
ok("NEGATIVE: AssertionError with a dotted name stays red", C.classify(LINE, 1, "x.AssertionError: no") == ("red", "assert"))
_old = C._OTHER_EXC
C._OTHER_EXC = re.compile(r"Traceback \(most recent call last\)|\b(?!Assertion)[A-Za-z]+(?:Error|Exception)\b")      # the pre-fix pattern
mut = C.classify(LINE, 1, RUFF["SSRFError"])
C._OTHER_EXC = _old
ok("MUTATION (the old any-identifier-ending-in-Error pattern): the SSRFError ruff case flips back to bad-spec/crash-unexplained, so the check bites", mut == ("bad-spec", "crash-unexplained"), mut)
_ff = C._frame_then_bare_exc
C._OTHER_EXC = re.compile(r"Traceback \(most recent call last\)|(?<![\w.`'\"/-])(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\s*:"
                          r"|(?:^|\s)E {2,}(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\b(?![\w`'\"])")      # the round-1 pattern (no '[CODE]' form)
C._frame_then_bare_exc = lambda t: False                                                                                       # ... and no File-frame form
mut2 = [C.classify(LINE, 1, t) for t in ("TypeError [ERR_X]: m", "File \"a.py\", line 3 in f ZeroDivisionError")]
C._OTHER_EXC = _old
C._frame_then_bare_exc = _ff
ok("MUTATION (round-1 pattern): the node '[ERR_X]' and bare-name-after-File-frame crashes flip to red, so the round-2 checks bite", mut2 == [("red", "assert")] * 2, mut2)

# round-3: the File-frame form was ONE regex (lazy span + \Z anchor), quadratic or worse in the tail length; a long tail with many frames must classify in linear time
PERF_TAIL = "".join('File "a.py", line %d in f ' % i for i in range(2500))        # ~65 KB, 2500 frames, no exception name anywhere
PERF_SCRIPT = ("import sys,time,json; sys.path.insert(0, sys.argv[1]); import ovn_spec_classify as C; t=time.time(); "
               "r=C.classify(sys.argv[2], 1, sys.argv[3]); print(json.dumps([r, time.time()-t]))")


def perf_run(scripts_dir):
    import json
    t0 = time.time()
    try:
        o = subprocess.run([sys.executable, "-c", PERF_SCRIPT, scripts_dir, LINE, PERF_TAIL], capture_output=True, text=True, timeout=90)
    except subprocess.TimeoutExpired:
        return None, time.time() - t0
    try:
        return json.loads(o.stdout.strip().splitlines()[-1]), time.time() - t0
    except Exception:
        return None, time.time() - t0


res, el = perf_run(SCRIPTS)
ok("round-3: a 65 KB tail with 2500 `File` frames classifies in well under a second (linear)", res is not None and el < 5 and res[1] < 1.0 and res[0] == ["red", "assert"], (res, el))
_csrc = rd(SCRIPTS, "ovn_spec_classify.py")
_anchor = "    return bool(_FINAL_BARE_EXC.search(text, cut))\n"
if _csrc.count(_anchor) != 1:
    ok("MUTATION anchor (perf) exists exactly once", False)
else:
    _md = os.path.realpath(tempfile.mkdtemp(prefix="clsperf-"))
    _old_rx = r"""(?s:File \"[^\"\n]+\", line \d+\b.*?(?<![\w.`'\"/-])(?:[A-Za-z_]\w*\.)*(?!Assertion)[A-Za-z]\w*(?:Error|Exception)\s*\Z)"""
    wr(os.path.join(_md, "ovn_spec_classify.py"), _csrc.replace(_anchor, "    return bool(re.search(r'''%s''', text))\n" % _old_rx))
    mres, mel = perf_run(_md)
    shutil.rmtree(_md, ignore_errors=True)
    ok("MUTATION caught (round-3 perf): the old single lazy regex needs seconds on the same tail, so the speed check bites", mres is None or mres[1] > 1.0 or mel > 3.0, (mres, mel))

# ================================================================ F3: parked lines are not 'open'
print("== F3 parked supply lines do not count as open / held-by-file")
GAP = mk("gd-missing-doc", "scripts/a.gd", ["foo", "bar"], cat="godot")
SUP = "(cat:godot; multifile:no; supply:%s) [feat:demo-20261009-%s]"
PARKED_OWN = "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] scripts/a.gd — Add docs: `foo`, `bar`. VERIFY: `x`. " + SUP % ("gd-missing-doc", "a")
LIVE_OWN = "- [ ] [T2] scripts/a.gd — Add docs: `foo`, `bar`. VERIFY: `x`. " + SUP % ("gd-missing-doc", "a")
PARKED_OTHER_KIND = "- [ ] [CLAUDE] [T2] scripts/a.gd — Add return type. VERIFY: `x`. " + SUP % ("gd-missing-void", "b")
LIVE_OTHER_KIND = "- [ ] [T2] scripts/a.gd — Add return type. VERIFY: `x`. " + SUP % ("gd-missing-void", "b")
PARKED_OLD_GAP = "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] scripts/a.gd — Add docs: `foo`. VERIFY: `x`. " + SUP % ("gd-missing-doc", "a")


def chk_parked(M):
    t = 1000.0
    return (M._filter(GAP, [PARKED_OWN], {}, {}, now=t) == "parked"
            and M._filter(GAP, [LIVE_OWN], {}, {}, now=t) == "open"
            and M._filter(GAP, [PARKED_OWN.replace("[AUTO-SKIP after 2 credit refusals: VERIFY failed]", "[HUMAN-ONLY]")], {}, {}, now=t) == "parked"
            and M._filter(GAP, [PARKED_OWN.replace("[AUTO-SKIP after 2 credit refusals: VERIFY failed]", "[CLAUDE]")], {}, {}, now=t) == "parked")


def chk_parked_other_kind(M):
    t = 1000.0
    return (M._filter(GAP, [PARKED_OTHER_KIND], {}, {}, now=t) is None             # a parked item of ANOTHER kind does not hold the file
            and M._filter(GAP, [LIVE_OTHER_KIND], {}, {}, now=t) == "held-by-file"       # a live one still does
            and M._filter(GAP, [PARKED_OWN, LIVE_OTHER_KIND], {}, {}, now=t) == "held-by-file")   # live beats parked


def chk_parked_old_gap(M):
    """The parked line is about the gap with ONE symbol; the file now has two (`bar` was added): that is a new gap, it is not blocked by the old parked item."""
    return M._filter(GAP, [PARKED_OLD_GAP], {}, {}, now=1000.0) in (None, "resupply")


mut_check("(F3a) a parked supply line of this gap is reported 'parked', a live one 'open'", chk_parked,
          "    live_open = [l for l in on_file if _OPEN_RE.match(l) and not _is_parked_line(l)]     # parked lines are open boxes the fleet never takes\n",
          "    live_open = [l for l in on_file if _OPEN_RE.match(l)]\n")
mut_check("(F3b) a parked line of another kind does not hold the file; a live one does", chk_parked_other_kind,
          "    live_open = [l for l in on_file if _OPEN_RE.match(l) and not _is_parked_line(l)]     # parked lines are open boxes the fleet never takes\n",
          "    live_open = [l for l in on_file if _OPEN_RE.match(l)]\n")
mut_check("(F3c) a parked line that names fewer symbols does not block the grown gap", chk_parked_old_gap,
          "_covers(l, spec) for l in mine):", "True for l in mine):")


def chk_xlite_shape(M):
    """The xlite case: N gaps, every one with a parked line -> 'N gaps found, N filtered (... open=0 ... parked=N)', 0 specs, nothing added."""
    files = {"scripts/m%d.gd" % i: "extends Node\n\nfunc pub_%d(x) -> int:\n    var a = 1\n    var b = 2\n    var c = 3\n    var d = 4\n    var e = 5\n    return a + x\n" % i for i in range(1, 4)}
    prog = "# progress\n"
    probe = load_supply()
    d0 = env_dir(files)
    os.environ["OVN_SUPPLY_GD_DOCS"] = "on"
    os.environ["OVN_SUPPLY_GD_DOCS_MODEL"] = "on"      # docexec gate: model-path gd-doc items need the explicit override (this test is about the parked filter)
    try:
        gaps = [g for g in probe.collect_all(os.path.join(d0, "repos", "demo")) if g["kind"] == "gd-missing-doc"]
        for g in gaps:
            prog += "- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] %s — %s VERIFY: `x`. (cat:godot; multifile:no; supply:gd-missing-doc) [feat:demo-20261009-x]\n" % (g["file"], g["text"])
        d = env_dir(files, progress=prog)
        out = run_main(M, d, "--dry-run", "--force", spec=lambda repo, lines: {i: "red" for i in range(len(lines))})
    finally:
        os.environ.pop("OVN_SUPPLY_GD_DOCS", None)
        os.environ.pop("OVN_SUPPLY_GD_DOCS_MODEL", None)
    n = len(gaps)
    return n == 3 and ("%d gaps found, %d filtered (seen=0 open=0 done-cooldown=0 held-by-file=0 parked=%d), 0 specs" % (n, n, n)) in out


mut_check("(F3d) end to end: every gap has a parked line -> parked=N, open=0 (it used to say open=N)", chk_xlite_shape,
          "    live_open = [l for l in on_file if _OPEN_RE.match(l) and not _is_parked_line(l)]     # parked lines are open boxes the fleet never takes\n",
          "    live_open = [l for l in on_file if _OPEN_RE.match(l)]\n")

# ================================================================ IPTV-7 / B9a: bad-spec reporting + escalation
print("== IPTV-7/B9a bad-spec is named in the log and the alert; a long streak escalates")
SPEC_NAMES = {}


def bad_spec_stub(M):
    def stub(repo, lines):
        M.LAST_SPEC_DETAIL.clear()
        for i in range(len(lines)):
            M.LAST_SPEC_DETAIL[i] = "crash-unexplained crashed instead of asserting: Traceback (rc=1)"
        return {i: "bad-spec" for i in range(len(lines))}
    return stub


def chk_bad_spec_printed(M):
    d = env_dir(OPEN_ROUTER)
    out = run_main(M, d, "--dry-run", "--force", spec=bad_spec_stub(M))
    return ("spec dropped as bad-spec" in out and "iptv-backend/app/routers/open_router.py" in out and "crash-unexplained crashed instead of asserting" in out and "(rc=1)" in out
            and "DRY-RUN 1 specs, 0 red-before" in out)


mut_check("(IPTV-7a) a bad-spec is printed with the spec text and the reason", chk_bad_spec_printed,
          '            print("%s: spec dropped as %s - %s" % (repo, v, note))\n', "            pass\n")


def chk_alert_text(M):
    d = env_dir(OPEN_ROUTER)
    for _ in range(3):
        run_main(M, d, "--force", spec=bad_spec_stub(M))
    al = rd(d, "state", "alerts.log")
    warn = [l for l in al.split("\n") if "no usable verdict" in l]
    return len(warn) == 1 and " warn " in (" " + warn[0].split("] ", 1)[-1] + " ") and "offending:" in warn[0] and "app/routers/open_router.py" in warn[0] and "crash-unexplained" in warn[0]


mut_check("(IPTV-7b) the streak warn (3 passes) names the offending spec and why", chk_alert_text,
          '    detail = (" | offending: " + " || ".join(notes[:3])) if notes else ""\n', '    detail = ""\n')


def chk_escalation(M):
    d = os.path.realpath(tempfile.mkdtemp(prefix="esc-"))
    os.makedirs(os.path.join(d, "state"))
    M.OVN_DIR = d
    M.INFRA_ESCALATE_AFTER, M.INFRA_REALERT_EVERY = 12, 48
    for _ in range(12 + 48):
        M._bump_infra("demo", True, ["spec X [bad-spec]: why"])
    lines = rd(d, "state", "alerts.log").split("\n")
    warns = [l for l in lines if "no usable verdict for" in l]
    errs = [l for l in lines if "STILL no usable spec verdict" in l]
    after = len(errs)
    M._bump_infra("demo", False)                       # a clean pass resets the streak
    for _ in range(12):
        M._bump_infra("demo", True)
    errs2 = [l for l in rd(d, "state", "alerts.log").split("\n") if "STILL no usable spec verdict" in l]
    return (len(warns) == 1 and after == 2 and "after 12 consecutive" in errs[0] and "after 60 consecutive" in errs[1] and "spec X [bad-spec]: why" in errs[0]
            and " error | " in errs[0].replace("] error |", " error |") and len(errs2) == 3)


mut_check("(IPTV-7c) the same specs escalate to an 'error' alert at 12 passes and every 48 after; a clean pass resets", chk_escalation,
          "(n == INFRA_ESCALATE_AFTER or (n > INFRA_ESCALATE_AFTER", "(False or (n > INFRA_ESCALATE_AFTER")


def chk_spec_check_detail(M):
    """spec_check() keeps the reason columns of ovn_spec_check.sh (detail / sub / rc) in LAST_SPEC_DETAIL."""
    d = os.path.realpath(tempfile.mkdtemp(prefix="sc-"))
    wr(os.path.join(d, "scripts", "ovn_spec_check.sh"),
       "#!/usr/bin/env bash\nprintf '1\\tbad-spec\\tcrashed instead of asserting: boom\\tcrash-unexplained\\t1\\n2\\tred\\t\\tassert\\t1\\n3\\tbad-spec\\tTIMEOUT after 60s\\tunrunnable\\t124\\n'\n")
    M.OVN_DIR = d
    with contextlib.redirect_stderr(io.StringIO()):
        v = M.spec_check("demo", ["- [ ] a", "- [ ] b", "- [ ] c"])
    det = M.LAST_SPEC_DETAIL
    return (v == {0: "bad-spec", 1: "red", 2: "bad-spec"} and "crash-unexplained" in det[0] and "boom" in det[0] and det[0].endswith("(rc=1)")
            and "unrunnable" in det[2] and "TIMEOUT" in det[2] and det[2].endswith("(rc=124)"))


mut_check("(IPTV-7d) spec_check keeps the verdict reason columns", chk_spec_check_detail,
          '            LAST_SPEC_DETAIL[int(m.group(1)) - 1] = (', '            _ = (')

# ================================================================ IPTV-1: relocate_new_tests
print("== IPTV-1 relocate_new_tests never doubles the collected-dir prefix")
QR_PATH = os.path.join(ROOT, "queue_refill.py")
QR_SRC = rd(QR_PATH)


def load_qr(src=None, tag="real"):
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="qrr10-"))
    wr(os.path.join(d, "queue_refill.py"), QR_SRC if src is None else src)
    os.makedirs(os.path.join(d, "scripts"))
    for f in ("ovn_backlog_eligibility.py", "ovn_spec_rules.py", "ovn_spec_gate.py", "ovn_spec_classify.py"):
        if os.path.exists(os.path.join(SCRIPTS, f)):
            shutil.copy(os.path.join(SCRIPTS, f), os.path.join(d, "scripts"))
    spec = importlib.util.spec_from_file_location("queue_refill_r10_%s_%d" % (tag, _n[0]), os.path.join(d, "queue_refill.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def iptv_repo():
    r = os.path.realpath(tempfile.mkdtemp(prefix="iptvrepo-"))
    os.makedirs(os.path.join(r, "iptv-backend", "tests"))
    os.makedirs(os.path.join(r, "iptv-backend", "app", "jobs"))
    wr(os.path.join(r, "iptv-backend", "app", "jobs", "test_stray_existing.py"), "def test_x(): assert 1\n")
    return r


SUPPLY_SHAPE = "- [ ] [T2] iptv-backend/tests/test_x_pure.py — Add pure tests. VERIFY: `cd iptv-backend && python3 -m pytest tests/test_x_pure.py`. (cat:python; multifile:no; supply:pure-function-tests)"
CD_NEW = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — Add a test. VERIFY: `cd iptv-backend && python3 -m pytest app/jobs/test_foo.py -q`. (cat:python)"
ROOT_NEW = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — Add a test. VERIFY: `pytest iptv-backend/app/jobs/test_foo.py -q`. (cat:python)"
CD_EXISTING = "- [ ] [T2] iptv-backend/app/jobs/test_stray_existing.py — Extend. VERIFY: `cd iptv-backend && python3 -m pytest app/jobs/test_stray_existing.py`. (cat:python)"
# the shape ovn_work_supply ACTUALLY emits (ovn_work_supply.py: verify_pure_tests(...) + " && cd iptv-backend && python3 -m pytest <rel> -q"): an ast check on the ROOT-relative path first,
# the cd MID-command, then pytest on the cd-relative path (the live iptv_apps OVERNIGHT_PROGRESS.md lines ~1985-2088 have exactly this)
_W = load_supply()
REAL_SUPPLY = ("- [ ] [T2] iptv-backend/tests/test_x_pure.py — NEW test file for `iptv-backend/app/services/x.py`. Test code only. VERIFY: `" + _W.verify_pure_tests("iptv-backend/tests/test_x_pure.py", ["f"], "iptv-backend")
               + " && cd iptv-backend && python3 -m pytest tests/test_x_pure.py -q`. (cat:test; multifile:no; supply:pure-function-tests) [feat:demo-1]")
MID_CD_NEW = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — Add a test. VERIFY: `true && cd iptv-backend && pytest app/jobs/test_foo.py -q`. (cat:python)"
QUOTED_CD = "- [ ] [T2] iptv-backend/tests/test_x_pure.py — t. VERIFY: `cd \"iptv-backend\" && python3 -m pytest tests/test_x_pure.py -q`. (cat:python)"
DOT_CD = "- [ ] [T2] iptv-backend/tests/test_x_pure.py — t. VERIFY: `cd ./iptv-backend && python3 -m pytest tests/test_x_pure.py -q`. (cat:python)"
CHAINED_CD = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — t. VERIFY: `cd iptv-backend && cd app && pytest jobs/test_foo.py -q`. (cat:python)"
SUBSHELL_CD = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — t. VERIFY: `(cd iptv-backend && true) && pytest iptv-backend/app/jobs/test_foo.py -q`. (cat:python)"
UNKNOWN_CD = "- [ ] [T2] iptv-backend/app/jobs/test_foo.py — t. VERIFY: `cd /tmp && pytest app/jobs/test_foo.py -q`. (cat:python)"


def chk_reloc(Q):
    r = iptv_repo()
    l1, m1 = Q.relocate_new_tests(SUPPLY_SHAPE, r)
    l2, m2 = Q.relocate_new_tests(CD_NEW, r)
    l3, m3 = Q.relocate_new_tests(ROOT_NEW, r)
    l4, m4 = Q.relocate_new_tests(CD_EXISTING, r)
    return (l1 == SUPPLY_SHAPE and m1 == []                                                                # already correct once the cd is read: untouched
            and "iptv-backend/iptv-backend" not in l1 + l2 + l3 + l4
            and "iptv-backend/tests/test_foo.py — Add a test" in l2 and "pytest tests/test_foo.py -q" in l2 and "app/jobs/test_foo.py" not in l2   # moved, cd-relative in the VERIFY
            and "pytest iptv-backend/tests/test_foo.py -q" in l3 and "app/jobs" not in l3                  # no cd: root-relative, as before
            and l4 == CD_EXISTING and m4 == [])                                                            # an existing file (found through the cd) is never moved


def chk_reloc_real(Q):
    """Round-3: the REAL supply shape (cd mid-command) is left untouched - the pytest half must stay `tests/test_x_pure.py`, never `iptv-backend/tests/...` after the cd."""
    r = iptv_repo()
    l, m = Q.relocate_new_tests(REAL_SUPPLY, r)
    return l == REAL_SUPPLY and m == [] and "cd iptv-backend && python3 -m pytest tests/test_x_pure.py -q" in l and "iptv-backend/iptv-backend" not in l


def chk_reloc_mid(Q):
    """A genuinely outside path after a mid-command cd is moved and written cd-relative; the description path (root-relative) is moved root-relative."""
    r = iptv_repo()
    l, m = Q.relocate_new_tests(MID_CD_NEW, r)
    return ("true && cd iptv-backend && pytest tests/test_foo.py -q" in l and "iptv-backend/tests/test_foo.py — Add a test" in l
            and ("app/jobs/test_foo.py", "tests/test_foo.py") in m and "iptv-backend/app/jobs" not in l and "iptv-backend/iptv-backend" not in l)


def chk_reloc_forms(Q):
    r = iptv_repo()
    outs = {k: Q.relocate_new_tests(v, r) for k, v in (("q", QUOTED_CD), ("dot", DOT_CD), ("ch", CHAINED_CD), ("sub", SUBSHELL_CD), ("unk", UNKNOWN_CD))}
    return (outs["q"] == (QUOTED_CD, [])                                                                  # cd "iptv-backend" is parsed: already correct
            and outs["dot"] == (DOT_CD, [])                                                               # cd ./iptv-backend: no spurious tests/x -> tests/x 'move'
            and "pytest ../tests/test_foo.py -q" in outs["ch"][0] and "iptv-backend/tests/test_foo.py — t" in outs["ch"][0]   # chained cds add up (iptv-backend/app -> ../tests)
            and "(cd iptv-backend && true) && pytest iptv-backend/tests/test_foo.py -q" in outs["sub"][0]                   # a subshell cd ends at its ')': pytest runs from the root
            and "pytest app/jobs/test_foo.py -q" in outs["unk"][0])                                       # a cd to an unknown place: the VERIFY path is not guessed at


_CWD_ANCHOR = "            cd = _cwd_at(vtext, m.start() - vstart)\n"
_NOCD = "            cd = _cwd_at(vtext[:0], 0)\n"                                                           # mutant: the cd is never followed
_FIRSTCD = "            cd = _cwd_at(vtext, len(vtext)) if _cwd_at(vtext, len(vtext)) else ''\n"            # mutant: ONE cd for the whole line (the round-2 behaviour)
mut_check("(IPTV-1a) a cd-relative path is read relative to the cd; replacements are positional", chk_reloc, _CWD_ANCHOR, _NOCD, src=QR_SRC, loader=load_qr)
mut_check("(IPTV-1b) the rewrite is written relative to the cd", chk_reloc,
          "        new = os.path.relpath(new_full, cd) if cd else new_full\n", "        new = new_full\n", src=QR_SRC, loader=load_qr)
mut_check("(IPTV-1d, round-3) the REAL supply shape (ast check, cd mid-command, pytest) is untouched: the cd is resolved per path position", chk_reloc_real,
          _CWD_ANCHOR, _FIRSTCD, src=QR_SRC, loader=load_qr)
mut_check("(IPTV-1e, round-3) a path after a mid-command cd is moved and written relative to that cd", chk_reloc_mid, _CWD_ANCHOR, _NOCD, src=QR_SRC, loader=load_qr)
mut_check("(IPTV-1f, round-3) quoted / ./ / chained / subshell / unknown cd forms", chk_reloc_forms, _CWD_ANCHOR, _FIRSTCD, src=QR_SRC, loader=load_qr)
def legacy_replace(line, moves):
    for old, new in moves:
        line = line.replace(old, new)
    return line


# the pre-fix behaviour on the exact work-supply shape (documents the incident): tests/test_x_pure.py -> iptv-backend/tests/..., then a substring replace hit the target too
ok("the legacy substring replace doubles the prefix on the supply shape (the incident this fixes)",
   "iptv-backend/iptv-backend/tests/test_x_pure.py" in legacy_replace(SUPPLY_SHAPE, [("tests/test_x_pure.py", "iptv-backend/tests/test_x_pure.py")]))


def chk_reloc_cli(Q):
    """End to end through queue_refill.py: the supply-shaped line lands in OVERNIGHT_PROGRESS.md unchanged (no RELOCATED_TESTS, no doubled directory)."""
    r = iptv_repo()
    wr(os.path.join(r, "OVERNIGHT_PROGRESS.md"), "")
    bl = os.path.join(r, "bl.md")
    wr(bl, SUPPLY_SHAPE + "\n")
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(Q.__file__), "queue_refill.py"), os.path.join(r, "OVERNIGHT_PROGRESS.md"), bl, "5"],
                         capture_output=True, text=True, timeout=120, env=dict(os.environ, OVN_SPEC_GATE="off")).stdout
    prog = rd(r, "OVERNIGHT_PROGRESS.md")
    return "REFILL=1" in out and "RELOCATED_TESTS" not in out and SUPPLY_SHAPE in prog and "iptv-backend/iptv-backend" not in prog


mut_check("(IPTV-1c) end to end through queue_refill.py: the supply line is pulled untouched", chk_reloc_cli,
          _CWD_ANCHOR, _NOCD, src=QR_SRC, loader=load_qr)

print("\nsupply r10: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
