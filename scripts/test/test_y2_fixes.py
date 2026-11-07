#!/usr/bin/env python3
"""Y2 reviewer-defect fixes (2026-11-06). Hermetic temp dirs, no box, no network, no ntfy.
  1. done-check / creation path needs an EXACT identifier: ConfigLoaderBase does not satisfy `class ConfigLoader`, test_retry_backoff_policy does not satisfy `test_retry`; never ledgered as done on a prefix
  2. body_key strips `<!-- closed ... -->`, `ALREADY DONE (verified ...)` and the real `(auto-closed ... id(s) ...)` suffix shapes (copied from CLAUDE_QUEUE_DONE.md): a re-tagged duplicate is NOT re-harvested
  3. no DeprecationWarning (positional maxsplit/count/flags) from the bridge under `python -W error::DeprecationWarning`"""
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

os.environ["TZ"] = "UTC"
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
os.environ["OVN_HARVEST_DONE_CHECK"] = "enforce"    # r1/r2 sections below test the enforced behaviour; the DEFAULTS (shadow) are tested in section r3
os.environ["OVN_HARVEST_LEDGER_MODE"] = "enforce"
HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.abspath(os.path.join(HERE, "..", ".."))
BR = os.path.join(REAL, "claude_queue_bridge.py")
BASE = os.path.realpath(tempfile.mkdtemp(prefix="y2fix-"))
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", HOME=BASE)
FAILS, PASSES = [], [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


def w(p, t):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(t)


def rd(p):
    try:
        return open(p).read()
    except OSError:
        return ""


def g(d, *a):
    return subprocess.run(["git", "-C", d] + list(a), capture_output=True, text=True, env=GENV).stdout


spec = importlib.util.spec_from_file_location("cqb_y2fix", BR)
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

# ---------------------------------------------------------------- 1. exact identifier
repos = os.path.join(BASE, "repos")
bw = os.path.join(repos, "billwatch")
os.makedirs(bw)
g(bw, "init", "-q")
w(os.path.join(bw, "app", "cfg.py"), "class ConfigLoaderBase:\n    pass\n\n\nclass Exact:\n    pass\n")
w(os.path.join(bw, "tests", "test_r.py"), "def test_retry_backoff_policy():\n    pass\n\n\ndef test_exact_name():\n    pass\n")
w(os.path.join(bw, "tests", "test_js.spec.ts"), "it('retries on error', () => {})\n")
g(bw, "add", "-A")
g(bw, "commit", "-q", "-m", "x")
REF = "HEAD"
T_CLS = "[T2] app/new_config.py — Create `class ConfigLoader` that loads the config. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-cl]"
T_TST = "[T3] tests/test_retry.py — Add test `test_retry` asserting retry. VERIFY: `pytest tests/test_retry.py::test_retry -v`. (cat:test) [feat:billwatch-20261106-rt]"
T_CLS_OK = "[T2] app/cfg.py — Create `class Exact` for things. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-ex]"
T_TST_OK = "[T3] tests/test_r.py — Add test `test_exact_name` asserting x. VERIFY: `pytest tests/test_r.py::test_exact_name -v`. (cat:test) [feat:billwatch-20261106-ex2]"
chk("exact: `class ConfigLoader` NOT done when only ConfigLoaderBase exists", B.done_check(repos, "billwatch", REF, T_CLS)[0] is False, B.done_check(repos, "billwatch", REF, T_CLS))
chk("exact: `test_retry` NOT done when only test_retry_backoff_policy exists", B.done_check(repos, "billwatch", REF, T_TST)[0] is False, B.done_check(repos, "billwatch", REF, T_TST))
chk("exact: an exactly defined class IS done", B.done_check(repos, "billwatch", REF, T_CLS_OK)[0] is True, B.done_check(repos, "billwatch", REF, T_CLS_OK))
chk("exact: an exactly defined test IS done", B.done_check(repos, "billwatch", REF, T_TST_OK)[0] is True, B.done_check(repos, "billwatch", REF, T_TST_OK))
chk("exact: superstring in it('...') form does not match a prefix word", not B.present_on_ref(bw, REF, "retr", exact=True) and B.present_on_ref(bw, REF, "retries", exact=True))
chk("exact: legacy prefix matcher unchanged for autoclose (present_on_ref default)", B.present_on_ref(bw, REF, "test_retry") is True)

# harvest end to end: not skipped, no 'done' row in ledger
d = os.path.join(BASE, "h1")
os.makedirs(d)
q, sk, led = os.path.join(d, "q.md"), os.path.join(d, "s.tsv"), os.path.join(d, "led.tsv")
w(q, "# q\n")
w(sk, "billwatch\t%s\nbillwatch\t%s\nbillwatch\t%s\n" % (T_CLS, T_TST, T_TST_OK))
cp = subprocess.run([sys.executable, BR, "harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-06", "--ledger", led, "--repos-dir", repos, "--done-ref", REF,
                     "--done-log", os.path.join(d, "done.log")], capture_output=True, text=True, env=GENV)
qt = rd(q)
chk("harvest: prefix-only creation items are harvested, the exactly-done one is skipped", "class ConfigLoader`" in qt and "`test_retry`" in qt and "test_exact_name" not in qt, (qt, cp.stderr))
chk("harvest: ledger never records 'done' for a prefix match (only for the exact one)", len(re.findall(r"\tdone\t", rd(led))) == 1 and rd(led).count("\tharvested\t") == 2, rd(led))

# ---------------------------------------------------------------- 2. body_key on real closed-line shapes
RAW = "[T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py::test_zz`. (cat:impl; multifile:no) [feat:billwatch-20261106-aaa]"
k = B.body_key("billwatch", RAW)
BASEL = "- [x] [CLAUDE] billwatch/ — " + RAW
SHAPES = {
    "closed-comment sweep": BASEL + " <!-- closed 2026-10-23 claude-queue sweep: done/already-done/obsolete (see repo commits) -->",
    "closed-comment sweep 2 + recovery meta": BASEL.replace("(cat:impl; multifile:no)", "(cat:impl; recovery:decomposed)") + " <!-- closed 2026-10-27 claude-queue sweep 2: done/already-done/obsolete (see repo commits) -->",
    "closed-comment reviewed": BASEL + " <!-- closed 2026-11-02: done by reviewed package or verified already done/decided -->",
    "ALREADY DONE verified": RAW.join(["- [x] [CLAUDE] billwatch/ — ", ""]) + " ALREADY DONE (verified 2026-09-08) - max_length + field_validator already present on X.",
    "ALREADY DONE re-verified": RAW.join(["- [x] [CLAUDE] billwatch/ — ", ""]) + " ALREADY DONE (re-verified 2026-09-10).",
    "ALREADY DONE xlite": RAW.join(["- [x] [CLAUDE] billwatch/ — ", ""]) + " ALREADY DONE (xlite, verified 2026-09-12) - see test_save_manager.gd::test_x",
    "ALREADY DONE stale bold": RAW.join(["- [x] [CLAUDE] billwatch/ — ", ""]) + " — **ALREADY DONE, stale item (verified 2026-09-05):** a prior pass had implemented it (`x.kt`).",
    "real autoclose suffix": BASEL + " (auto-closed 2026-11-04: [feat:billwatch-20261106-aaa] landed, all 1 named test id(s) present on origin/claude/feature; landing=item)",
    "autoclose + closed comment": BASEL + " (auto-closed 2026-11-04: [feat:billwatch-20261106-aaa] landed, all 2 named test id(s) present on origin/claude/feature; landing=feature) <!-- closed 2026-11-05: done -->",
}
for name, line in SHAPES.items():
    chk("body_key: %s -> same key as the raw task" % name, B.body_key("billwatch", line) == k, (B.body_key("billwatch", line), line[-120:]))
chk("body_key: different text still a different key", B.body_key("billwatch", RAW.replace("exact thing", "other thing") + " <!-- closed 2026-10-23 x -->") != k)

# probe: re-tagged duplicate of each annotated closed line is NOT re-harvested (queue and archive)
RETAG = RAW.replace("billwatch-20261106-aaa", "billwatch-20261107-newtag").replace("(cat:impl; multifile:no)", "(cat:test; multifile:yes)")
for i, (name, line) in enumerate(SHAPES.items()):
    for where in ("archive", "queue"):
        d = os.path.join(BASE, "p_%d_%s" % (i, where))
        os.makedirs(d)
        q, sk, a = os.path.join(d, "q.md"), os.path.join(d, "s.tsv"), os.path.join(d, "done.md")
        w(q, "# q\n## s\n" + (line + "\n" if where == "queue" else ""))
        w(a, "<!-- archived -->\n" + (line + "\n" if where == "archive" else ""))
        w(sk, "billwatch\t%s\n" % RETAG)
        cp = subprocess.run([sys.executable, BR, "harvest", "--queue", q, "--autoskip", sk, "--archive", a, "--today", "2026-11-06", "--ledger", os.path.join(d, "led.tsv")],
                            capture_output=True, text=True, env=GENV)
        chk("probe: re-tagged duplicate of '%s' (%s) not re-harvested" % (name, where), rd(q).count("- [ ]") == 0 and "nothing new" in cp.stderr, (rd(q), cp.stderr))

# ---------------------------------------------------------------- 3. no DeprecationWarning
code = ("import runpy,sys\nsys.argv=['x','--help']\n"
        "import importlib.util as u\ns=u.spec_from_file_location('m',%r)\nm=u.module_from_spec(s)\ns.loader.exec_module(m)\n"
        "m.named_new_defs('Add `class X` here. VERIFY: `pytest a`')\nm.body_key('r','- [x] a <!-- closed d -->')\n"
        "m.definition_regex('x'); m.exact_definition_regex('x')\n" % BR)
cp = subprocess.run([sys.executable, "-W", "error::DeprecationWarning", "-c", code], capture_output=True, text=True, env=GENV)
chk("no DeprecationWarning (python -W error::DeprecationWarning) on import + named_new_defs/body_key", cp.returncode == 0, cp.stderr[-300:])
cp = subprocess.run([sys.executable, "-W", "error::DeprecationWarning", "-m", "py_compile", BR], capture_output=True, text=True)
chk("py_compile clean under -W error::DeprecationWarning", cp.returncode == 0, cp.stderr[-300:])
src = rd(BR)
bad = re.findall(r"re\.(?:split|sub|subn)\((?:[^()]|\([^()]*\))*,\s*\d+\s*\)", src)
chk("source: no positional maxsplit/count in re.split/sub/subn", not bad, bad)

# ---------------------------------------------------------------- round 2 (2026-11-06): defects 1-3
# (1) a genuinely NEW item must not be judged done because the identifier exists ELSEWHERE in the repo
r2 = os.path.join(BASE, "repos2")
cw = os.path.join(r2, "billwatch")
os.makedirs(cw)
g(cw, "init", "-q")
w(os.path.join(cw, "app", "old.py"), "class Config:\n    pass\n\n\nclass RateLimitPolicyEngine:\n    pass\n\n\nclass Twice:\n    pass\n")
w(os.path.join(cw, "app", "other.py"), "class Twice:\n    pass\n")
w(os.path.join(cw, "app", "target.py"), "class Settings:\n    pass\n")
g(cw, "add", "-A")
g(cw, "commit", "-q", "-m", "x")
I_CFG = "[T2] app/new_config.py — Create `class Config` that loads the config. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-cfg]"
I_CFG_HERE = "[T2] app/old.py — Create `class Config` that loads the config. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-cfg2]"
I_SET_HERE = "[T2] app/target.py — Create `class Settings` for it. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-set]"
I_NOFILE_GENERIC = "Create `class Config` that loads the config. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-g]"
I_NOFILE_UNIQUE = "Create `class RateLimitPolicyEngine` for limits. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-u]"
I_NOFILE_DUP = "Create `class Twice` for it. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-d]"
I_UNIQ_ELSEWHERE = "[T2] app/new_engine.py — Create `class RateLimitPolicyEngine` for limits. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-ue]"
dc = lambda t: B.done_evidence(r2, "billwatch", "HEAD", t)
chk("r2/1: a non-generic name defined uniquely in ANOTHER file is not done when the item names a different target file", dc(I_UNIQ_ELSEWHERE)[:2] == (False, False), dc(I_UNIQ_ELSEWHERE))
chk("r2/1: `class Config` in app/old.py does NOT make 'Create class Config in app/new_config.py' done", dc(I_CFG)[0] is False and B.done_check(r2, "billwatch", "HEAD", I_CFG)[0] is False, dc(I_CFG))
chk("r2/1: the item's OWN target file holding the exact definition is done AND strong", dc(I_CFG_HERE)[:2] == (True, True) and dc(I_SET_HERE)[:2] == (True, True), (dc(I_CFG_HERE), dc(I_SET_HERE)))
chk("r2/1: no target file + generic/short name (Config) is never done even though it is defined once", dc(I_NOFILE_GENERIC)[:2] == (False, False), dc(I_NOFILE_GENERIC))
chk("r2/1: no target file + non-generic name defined in exactly one file: done but NOT strong", dc(I_NOFILE_UNIQUE)[:2] == (True, False), dc(I_NOFILE_UNIQUE))
chk("r2/1: no target file + name defined in two files is not done", dc(I_NOFILE_DUP)[:2] == (False, False), dc(I_NOFILE_DUP))
chk("r2/1: is_generic_name: <=6 chars or stoplist", B.is_generic_name("Config") and B.is_generic_name("main") and B.is_generic_name("Manager") and not B.is_generic_name("RateLimitPolicyEngine"))
d = os.path.join(BASE, "h2")
os.makedirs(d)
q, sk, led = os.path.join(d, "q.md"), os.path.join(d, "s.tsv"), os.path.join(d, "led.tsv")
w(q, "# q\n")
w(sk, "billwatch\t%s\nbillwatch\t%s\nbillwatch\t%s\nbillwatch\t%s\n" % (I_CFG, I_CFG_HERE, I_NOFILE_UNIQUE, I_NOFILE_GENERIC))
args = [sys.executable, BR, "harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-06", "--ledger", led, "--repos-dir", r2, "--done-ref", "HEAD", "--done-log", os.path.join(d, "done.log")]
cp = subprocess.run(args, capture_output=True, text=True, env=GENV)
qt, lt = rd(q), rd(led)
chk("r2/1 harvest: the genuinely new Config item and the generic no-file item are harvested; target-file-done and weak-unique are skipped", "app/new_config.py" in qt and "Create `class Config` that loads the config. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261106-g]" in qt and "app/old.py" not in qt and "RateLimitPolicyEngine" not in qt, (qt, cp.stderr))
chk("r2/1 harvest: ledger 'done' ONLY for the strong (target file + exact) item; the weak one leaves no ledger row at all", lt.count("\tdone\t") == 1 and len(lt.splitlines()) == 3 and B.body_key("billwatch", I_NOFILE_UNIQUE) not in lt, lt)

# (2) body_key drops every closing tail: measure the re-tag match rate on real-shaped closed lines (+ the real archive when it is on disk)
TASKS = [
    ("billwatch", "[T2] backend/app/routers/civic.py — Add helper `parse_zip(z: str) -> str | None` that returns the 5-digit zip. VERIFY: `pytest tests/test_civic.py::test_parse_zip -v`. (cat:logic; multifile:no)"),
    ("gitlark", "[T1] backend/tests/test_github_integration_create_pr.py — Create test file with `pytest.mark.asyncio` tests that mock `httpx.AsyncClient.post`. VERIFY: `python -m pytest backend/tests/test_github_integration_create_pr.py::test_create_pr_success -v` (cat:test; recovery:decomposed)"),
    ("xlite", "[T2] scripts/battle/save_manager.gd — Implement a versioning wrapper function `wrap_save_data(data: Dictionary, version: int) -> Dictionary`. VERIFY: Run `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/save_tests`. (cat:godot; multifile:no)"),
    ("iptv_apps", "[T1] iptv-backend/app/services/tmdb.py — Add pure helper function `parse_episode_identifier(title: str)`. VERIFY: python -c \"assert 1\" (cat:logic; recovery:decomposed)"),
]
TAILS = [
    " [feat:%s-20261011-aaa] — TRIAGE 2026-10-12 DONE: scripts/battle/battle.gd:4489 `RosterManager.sync_from_battle(_units)`; RosterManager.sync_f",
    " ALREADY DONE (verified 2026-09-08).",
    " _(ALREADY-SATISFIED 2026-09-09: GitHubIntegrationService.create_pull_request + tests already cover URL/payload)_",
    " _(duplicate of an already-checked-off item (see above): same helper)_",
    " (done 2026-09-12: claude @ abc1234) tests pass",
    " STALE TICKET, no action (verified 2026-09-08) - same phantom-API issue - already lives in the real sc",
    " <!-- closed 2026-10-23 claude-queue sweep: done/already-done/obsolete -->",
    " [feat:%s-20261011-bbb] (auto-closed 2026-11-04: [feat:x] landed, all 1 named test id(s) present on origin/claude/feature; landing=item)",
]
CATRE = re.compile(r"\(cat:[^)]*\)")
tot = okc = 0
badl = []
for repo, task in TASKS:
    retag = CATRE.sub("(cat:test; multifile:yes)", task) + " [feat:%s-20261107-newtag]" % repo
    for tl in TAILS:
        line = "- [x] [CLAUDE] %s/ — %s%s" % (repo, task, tl.replace("%s", repo))
        tot += 1
        if B.body_key(repo, line) == B.body_key(repo, retag):
            okc += 1
        else:
            badl.append(line[-100:])
chk("r2/2: fixture of real-shaped closed lines: re-tag key match rate >95%% (%d/%d)" % (okc, tot), okc * 100.0 / tot > 95.0, badl)
rate_files = [os.path.join(REAL, "..", "..", f) for f in ("CLAUDE_QUEUE_DONE.md", "CLAUDE_QUEUE.md")]
if all(os.path.exists(f) for f in rate_files):
    n = ok2 = 0
    for f in rate_files:
        for ln in rd(f).splitlines():
            m = B.CHECKED_ITEM_RE.match(ln)
            if not m or "[CLAUDE]" not in ln:
                continue
            repo = B.infer_repo(m.group(1), "")
            c = CATRE.search(m.group(1))
            if not repo or not c:
                continue
            raw = B.REPO_PREFIX_RE.sub("", re.sub(r"^\[CLAUDE\]\s*", "", m.group(1)[:c.end()]))
            n += 1
            ok2 += B.body_key(repo, ln) == B.body_key(repo, CATRE.sub("(cat:test; multifile:yes)", raw) + " [feat:%s-20261107-newtag]" % repo)
    print("  real archive+queue re-tag match rate: %d/%d = %.2f%%" % (ok2, n, 100.0 * ok2 / max(n, 1)))
    chk("r2/2: REAL CLAUDE_QUEUE_DONE.md + CLAUDE_QUEUE.md closed lines: re-tag match rate >95%", n < 100 or ok2 * 100.0 / n > 95.0, (ok2, n))

# (3) operators/case/punctuation carry meaning: pairs that used to collide are distinct keys; whitespace/noise still normalized
PAIRS = [("Assert `x == 1` in the parser. VERIFY: `pytest a`", "Assert `x != 1` in the parser. VERIFY: `pytest a`"),
         ("Reject when n > 3 in the parser. VERIFY: `pytest a`", "Reject when n >= 3 in the parser. VERIFY: `pytest a`"),
         ("Create `class foo` in the module. VERIFY: `pytest a`", "Create `class Foo` in the module. VERIFY: `pytest a`"),
         ("Clamp to [0, 1) in the scorer. VERIFY: `pytest a`", "Clamp to [0, 1] in the scorer. VERIFY: `pytest a`"),
         ("Add retry when x < 5 for the call. VERIFY: `pytest a`", "Add retry when x <= 5 for the call. VERIFY: `pytest a`")]
for a_, b_ in PAIRS:
    ka, kb = B.body_key("billwatch", "[T1] app/a.py — " + a_ + " (cat:impl)"), B.body_key("billwatch", "[T1] app/a.py — " + b_ + " (cat:impl)")
    chk("r2/3: distinct keys: %r vs %r" % (a_[:34], b_[:34]), ka != kb)
chk("r2/3: still repo-scoped", B.body_key("billwatch", "[T1] app/a.py — Do the thing here now. (cat:impl)") != B.body_key("gitlark", "[T1] app/a.py — Do the thing here now. (cat:impl)"))
chk("r2/3: whitespace and the known noise are still normalized", B.body_key("billwatch", "- [ ] [CLAUDE] billwatch/ — [T1] app/a.py — Do  the thing   here now. (cat:impl; multifile:no) [feat:x-1]") == B.body_key("billwatch", "[T1] app/a.py — Do the thing here now. (cat:test) [feat:y-2]"))
dh = os.path.join(BASE, "h3")
os.makedirs(dh)
q3, sk3, led3 = os.path.join(dh, "q.md"), os.path.join(dh, "s.tsv"), os.path.join(dh, "led.tsv")
w(q3, "# q\n\n- [x] [CLAUDE] billwatch/ — [T1] app/a.py — Assert `x == 1` in the parser module for sure. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-1-a]\n")
w(sk3, "billwatch\t[T1] app/a.py — Assert `x != 1` in the parser module for sure. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-2-b]\n")
subprocess.run([sys.executable, BR, "harvest", "--queue", q3, "--autoskip", sk3, "--today", "2026-11-06", "--ledger", led3], capture_output=True, text=True, env=GENV)
chk("r2/3 harvest: the `!=` item is NOT suppressed by the closed `==` item", "x != 1" in rd(q3), rd(q3))


# ================================================================================================ r3 (Y2 round 3: D2-D6; D1 + D4 ledger/defaults are also in test_y2_bridge_harvest.py)
R3_REF = {}


def r3_checks(script, M):
    """Run every r3 regression check against bridge script `script` / module `M`. Returns the list of FAILED check names (so mutants and the old code can be run through the same checks)."""
    bad = []

    def c(name, cond, detail=""):
        if not cond:
            bad.append(name + " :: " + str(detail)[:200])

    envd = dict(GENV)
    saved = {k: os.environ.pop(k, None) for k in ("OVN_HARVEST_DONE_CHECK", "OVN_HARVEST_LEDGER_MODE")}   # the file-level enforce env is for r1/r2: r3 tests the real defaults
    for k in saved:
        envd.pop(k, None)
    work = tempfile.mkdtemp(prefix="r3-", dir=BASE)

    def run(*a, env=None):
        return subprocess.run([sys.executable, script] + list(a), capture_output=True, text=True, env=env or envd)

    # ---- D2: a marker in the MIDDLE of a task never merges it with a different task
    PROBES = [("Handle ALREADY DONE state in %s parser. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Wrap strings with _(msg) gettext in %s. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Handle (coverage: branch A) in %s too. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Parse the (done flag) in %s now. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Handle STALE TICKET state in %s now. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Handle DONE state in %s now. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Support the (cat: dog) form in %s now. VERIFY: `pytest a`", "foo.py", "bar.py"),
              ("Say TRIAGE in %s now. VERIFY: `pytest a`", "foo.py", "bar.py")]
    for tmpl, x, y in PROBES:
        c("D2 distinct keys: " + tmpl[:30], M.body_key("billwatch", "[T1] app/a.py — " + tmpl % x + " (cat:impl)") != M.body_key("billwatch", "[T1] app/a.py — " + tmpl % y + " (cat:impl)"))
    # ...and via the harvest path: a ticked task A must not suppress a different raw task B that only shares the text before the marker
    q, sk, led = os.path.join(work, "d2q.md"), os.path.join(work, "d2s.tsv"), os.path.join(work, "d2l.tsv")
    w(q, "# q\n- [x] [CLAUDE] billwatch/ — [T1] app/a.py — Handle ALREADY DONE state in foo.py parser. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-1-a]\n")
    w(sk, "billwatch\t[T1] app/a.py — Handle ALREADY DONE state in bar.py lexer. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-2-b]\n")
    run("harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-06", "--ledger", led, "--ledger-mode", "enforce")
    c("D2 harvest: the different task B is harvested", "bar.py lexer" in rd(q), rd(q))
    # real closing shapes are still cut
    base = "[T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest a`."
    for tail in (" (cat:impl; multifile:no) ALREADY DONE (verified 2026-09-08).", " (cat:impl) _(ALREADY-SATISFIED 2026-09-09: x)_", " (cat:impl) (done 2026-09-12: claude) ok", " (cat:impl) STALE TICKET, no action (verified)",
                 " (cat:impl) DONE (shipped abc)", " (cat:impl) [feat:b-1-x] — TRIAGE 2026-10-12 DONE: x"):
        c("D2 closing shape still cut: " + tail[:40], M.body_key("billwatch", "- [x] [CLAUDE] billwatch/ — " + base + tail) == M.body_key("billwatch", base + " (cat:test) [feat:b-2-y]"))

    # ---- D3: commented-out defs / docstrings / reference files are not evidence
    r = os.path.join(work, "d3")
    bwd = os.path.join(r, "billwatch")
    os.makedirs(bwd)
    g(bwd, "init", "-q")
    w(os.path.join(bwd, "tests", "test_dates.py"), "# def test_parse_dates_tz():\n#     pass\n\"\"\"def test_other_thing\"\"\"\n    # class Hidden:\n\ndef test_real_one():\n    pass\n")
    w(os.path.join(bwd, "src", "old.py"), "class ReportBuilder:\n    pass\n")
    w(os.path.join(bwd, "src", "other.py"), "class Third:\n    pass\n")
    w(os.path.join(bwd, "src", "new_done.py"), "class DoneBuilder:\n    pass\n")
    w(os.path.join(bwd, "src", "new_done2.py"), "class DoneBuilder:\n    pass\n")
    g(bwd, "add", "-A")
    g(bwd, "commit", "-q", "-m", "x")
    ev = lambda t: M.done_evidence(r, "billwatch", "HEAD", t)
    c("D3a: `# def test_x` comment is not a definition", ev("[T1] tests/test_dates.py — Add `test_parse_dates_tz` covering tz. VERIFY: `pytest tests/test_dates.py`. (cat:test)")[0] is False)
    c("D3a: one-line docstring is not a definition", ev("[T1] tests/test_dates.py — Add `test_other_thing` covering it. VERIFY: `pytest tests/test_dates.py`. (cat:test)")[0] is False)
    c("D3a: a REAL def is still done+strong", ev("[T1] tests/test_dates.py — Add `test_real_one` covering it. VERIFY: `pytest tests/test_dates.py`. (cat:test)")[:2] == (True, True))
    c("D3b: def only in the REFERENCE file is not done", ev("Create `class ReportBuilder` in src/new_report.py modelled on src/old.py. VERIFY: `pytest a`. (cat:impl)")[:2] == (False, False), ev("Create `class ReportBuilder` in src/new_report.py modelled on src/old.py. VERIFY: `pytest a`. (cat:impl)"))
    c("D3b: only reference files named -> not done", ev("Create `class ReportBuilder` modelled on src/old.py. VERIFY: `pytest a`. (cat:impl)")[0] is False)
    c("D3b: def in the item's OWN new file (reference elsewhere) is done", ev("Create `class DoneBuilder` in src/new_done.py modelled on src/old.py. VERIFY: `pytest a`. (cat:impl)")[0] is True)
    c("D3b: several target files are never strong evidence", ev("Create `class DoneBuilder` in src/new_done.py and src/new_done2.py. VERIFY: `pytest a`. (cat:impl)")[:2] == (True, False), ev("Create `class DoneBuilder` in src/new_done.py and src/new_done2.py. VERIFY: `pytest a`. (cat:impl)"))
    c("D3b: a def in only ONE of several target files is not done (no union)", ev("Create `class ReportBuilder` in src/old.py and src/other.py. VERIFY: `pytest a`. (cat:impl)")[0] is False)

    # ---- D4: defaults are SHADOW (done-check and ledger-skip): log, never act
    c("D4 mode defaults", (M.done_check_mode(None), M.ledger_mode(None)) == ("shadow", "shadow"), (M.done_check_mode(None), M.ledger_mode(None)))
    q, sk, led, dl, ll = (os.path.join(work, n) for n in ("d4q.md", "d4s.tsv", "d4l.tsv", "d4d.log", "d4ll.log"))
    w(q, "# q\n- [x] [CLAUDE] billwatch/ — [T1] src/new_done.py — Create `class DoneBuilder` in the module for real. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-1-a]\n")
    w(sk, "billwatch\t[T1] src/new_done.py — Create `class DoneBuilder` in the module for real. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-9-z]\n"
          "billwatch\t[T1] src/old.py — Create `class ReportBuilder` for the reports in full. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-8-y]\n")
    run("harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-06", "--ledger", led, "--ledger-log", ll, "--repos-dir", r, "--done-ref", "HEAD", "--done-log", dl)
    c("D4: default harvests both lines (ledger hit + done-evidence item are only LOGGED)", rd(q).count("- [ ]") == 2, rd(q))
    c("D4: would-skip rows are tagged SHADOW", "SHADOW ledger-skip" in rd(ll) and "SHADOW would-skip-done" in rd(dl) and "ENFORCED" not in rd(ll) + rd(dl), (rd(ll), rd(dl)))
    c("D4: shadow writes no `done` ledger row and never rewrites closed", "\tdone\t" not in rd(led) and rd(led).count("\tclosed\t") == 1, rd(led))
    q2 = os.path.join(work, "d4q2.md")
    w(q2, "# q\n- [x] [CLAUDE] billwatch/ — [T1] src/new_done.py — Create `class DoneBuilder` in the module for real. VERIFY: `pytest a`. (cat:impl) [feat:billwatch-1-a]\n")
    run("harvest", "--queue", q2, "--autoskip", sk, "--today", "2026-11-06", "--ledger", os.path.join(work, "d4l2.tsv"), "--repos-dir", r, "--done-ref", "HEAD", "--ledger-mode", "enforce", "--done-mode", "enforce")
    c("D4: explicit enforce opts in (ledger-skip + done-skip act)", rd(q2).count("- [ ]") == 0, rd(q2))

    # ---- D5: an invalid utf-8 byte never kills the pass
    bq, bs, ba = os.path.join(work, "d5q.md"), os.path.join(work, "d5s.tsv"), os.path.join(work, "d5a.md")
    open(bq, "wb").write(b"# q\n- [ ] note \xff\xfe bad byte\n")
    open(bs, "wb").write(b"billwatch\t[T1] app/a.py \xe2\x80\x94 Do the exact thing here in full \xff now. VERIFY: `pytest a`. (cat:impl)\n")
    open(ba, "wb").write(b"# arch \xff\n")
    cp = run("harvest", "--queue", bq, "--autoskip", bs, "--archive", ba, "--today", "2026-11-06")
    c("D5 harvest survives invalid bytes in queue/archive/autoskip", cp.returncode == 0 and "Traceback" not in cp.stderr, cp.stderr[-300:])
    cp = run("signatures", "--queue", bq, "--archive", ba)
    c("D5 signatures survives", cp.returncode == 0, cp.stderr[-300:])
    prog = os.path.join(work, "d5p.md")
    task = "[T1] app/a.py — Do the exact thing described here in full."
    open(prog, "wb").write(b"- [ ] keep \xff this line\n- [ ] [AUTO-SKIP] " + task.encode() + b"\n")
    sigf = os.path.join(work, "d5sig.txt")
    w(sigf, M.task_sig(task) + "\n")
    cp = run("retire", "--progress", prog, "--signatures", sigf, "--today", "2026-11-06")
    got = open(prog, "rb").read()
    c("D5 retire: survives, retires the match and round-trips the untouched invalid byte", cp.returncode == 0 and b"- [ ] keep \xff this line" in got and b"- [x] [AUTO-SKIP]" in got, (cp.stderr[-200:], got))
    # autoclose reads the queue strictly too
    cp = run("autoclose", "--queue", bq, "--outcomes", os.path.join(work, "none.jsonl"), "--repos-dir", r, "--mode", "enforce", "--today", "2026-11-06")
    c("D5 autoclose survives and leaves the queue bytes untouched", cp.returncode == 0 and open(bq, "rb").read().count(b"\xff\xfe") == 1, cp.stderr[-200:])

    # ---- D6: rewrites are atomic (temp + os.replace): a failing replace leaves the original byte-identical, and no temp file is left behind
    prog2 = os.path.join(work, "d6p.md")
    orig6 = "- [ ] [AUTO-SKIP] " + task + "\n- [ ] other\n"
    w(prog2, orig6)
    sp = importlib.util.spec_from_file_location("cqb_d6", script)
    M2 = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(M2)

    def boom(*a, **k):
        raise OSError("ENOSPC")
    M2.os.replace = boom
    ns = type("NS", (), dict(progress=prog2, signatures=sigf, today="2026-11-06"))()
    try:
        M2.cmd_retire(ns)
        raised = False
    except OSError:
        raised = True
    M2.os.replace = os.replace if False else __import__("os").replace
    c("D6 retire: failure at the replace step leaves the original untouched (no in-place truncate/rewrite)", raised and rd(prog2) == orig6, (raised, rd(prog2)))
    c("D6: no temp file left behind", [f for f in os.listdir(work) if f.startswith(".d6p.md")] == [], os.listdir(work))
    os.environ.update({k: v for k, v in saved.items() if v is not None})
    return bad


# mutants (each must be caught)
MUT = [
    ("done-check ignores the target file", "    files = target_files(task)\n    if not files and has_named_paths(task):", "    files = []\n    if False:"),
    ("weak evidence is ledgered", "                    if dstrong and key not in ledger:", "                    if True:"),
    ("generic names allowed without a file", "    if generic:\n", "    if False:\n"),
    ("body_key keeps closing tails", "        nb = _peel_tail(body)", "        nb = None"),
    ("body_key lowercases/drops operators", '    body = " ".join(body.split()).rstrip(" .")', '    body = " ".join(re.findall(r"[a-z0-9]+", body.lower()))'),
]
orig = rd(BR)
for name, old, newv in MUT:
    mp = os.path.join(BASE, "mut_bridge.py")
    if old not in orig:
        chk("mutant applies: " + name, False, "source drifted")
        continue
    w(mp, orig.replace(old, newv, 1))
    sp = importlib.util.spec_from_file_location("cqb_mut", mp)
    M = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(M)
    caught = False
    caught |= M.done_evidence(r2, "billwatch", "HEAD", I_CFG)[0] or M.done_evidence(r2, "billwatch", "HEAD", I_NOFILE_GENERIC)[0] or M.done_evidence(r2, "billwatch", "HEAD", I_UNIQ_ELSEWHERE)[0]
    caught |= M.body_key("billwatch", "x/ — [T1] a.py — Fix the thing in module. (cat:impl)") != M.body_key("billwatch", "x/ — [T1] a.py — Fix the thing in module. (cat:impl) ALREADY DONE (v) _(x)_") and False
    line = "- [x] [CLAUDE] billwatch/ — " + TASKS[0][1] + TAILS[0].replace("%s", "billwatch")
    caught |= M.body_key("billwatch", line) != M.body_key("billwatch", CATRE.sub("(cat:test; multifile:yes)", TASKS[0][1]) + " [feat:billwatch-1-n]")
    caught |= M.body_key("billwatch", "[T1] a.py — Assert `x == 1` in it. (cat:impl)") == M.body_key("billwatch", "[T1] a.py — Assert `x != 1` in it. (cat:impl)")
    if name == "weak evidence is ledgered":
        d4 = os.path.join(BASE, "h4")
        os.makedirs(d4, exist_ok=True)
        q4, sk4, l4 = os.path.join(d4, "q.md"), os.path.join(d4, "s.tsv"), os.path.join(d4, "l.tsv")
        w(q4, "# q\n")
        w(sk4, "billwatch\t%s\n" % I_NOFILE_UNIQUE)
        subprocess.run([sys.executable, mp, "harvest", "--queue", q4, "--autoskip", sk4, "--today", "2026-11-06", "--ledger", l4, "--repos-dir", r2, "--done-ref", "HEAD"], capture_output=True, text=True, env=GENV)
        caught |= "\tdone\t" in rd(l4)
    chk("mutant caught: " + name, caught)

# r3: the real code passes every check; each r3 mutant must fail at least one
_bad = r3_checks(BR, B)
chk("r3: all D2-D6 regression checks pass on the real bridge", not _bad, _bad)
# (the r6 free-tail gates are layered -- unit regex AND _tail_ok -- so single-substitution mutants of one layer are equivalent here; they are killed in test_y2_bridge_harvest.py)
R3_MUT = [
    ("D2 cat/coverage cut matches mid-text groups", 'r"\\((?:cat|coverage):[^()]*\\)$"', 'r"\\((?:cat|coverage):[^()]*\\).*$"'),
    ("D3a definitions may sit mid-line (comments/docstrings count)", 'DEF_LEAD = "^[[:space:]]*((async|', 'DEF_LEAD = "(^|[^A-Za-z0-9_])((async|'),
    ("D3b reference files count as targets", "REFERENCE_CTX_RE.search(body[max(0, pm.start() - 40):pm.start()])", "False"),
    ("D3b union of target files is evidence", "all(present(clone, ref, i, paths=[f]) for f in files)", "present(clone, ref, i, paths=files)"),
    ("D3b multi-file evidence may be strong", "(done and len(files) == 1)", "done"),
    ("D3b reference-only item treated as no-file", "    if not files and has_named_paths(task):", "    if False:"),
    ("D4 done-check default enforce", 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "shadow"', 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "on"'),
    ("D4 ledger default enforce", 'os.environ.get("OVN_HARVEST_LEDGER_MODE") or "shadow"', 'os.environ.get("OVN_HARVEST_LEDGER_MODE") or "enforce"'),
    ("D5 read_text strict", 'with open(path, encoding="utf-8", errors="replace") as f:\n        return f.read()\n\n\ndef read_text_raw', 'with open(path, encoding="utf-8") as f:\n        return f.read()\n\n\ndef read_text_raw'),
    ("D5 read_text_raw strict", 'errors="surrogateescape", newline="") as f:', 'errors="strict", newline="") as f:'),
    ("D5 retire rewrites untouched lines from the lossy copy", "out.append(raw)   # untouched", "out.append(ln)   # untouched"),
    ("D6 in-place write instead of temp + os.replace", "os.replace(tmp, path)", "shutil.copyfile(tmp, path)"),
]
for name, old, newv in R3_MUT:
    mp = os.path.join(BASE, "mut_r3.py")
    if old not in orig:
        chk("r3 mutant applies: " + name, False, "source drifted")
        continue
    w(mp, orig.replace(old, newv, 1))
    sp = importlib.util.spec_from_file_location("cqb_mut_r3", mp)
    M = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(M)
    try:
        mb = r3_checks(mp, M)
    except Exception as e:   # a mutant that crashes the checks is also a detection
        mb = ["crash: %r" % e]
    chk("r3 mutant caught: " + name, bool(mb))

shutil.rmtree(BASE, ignore_errors=True)
print("\n%d passed, %d failed" % (PASSES[0], len(FAILS)))
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
sys.exit(1 if FAILS else 0)
