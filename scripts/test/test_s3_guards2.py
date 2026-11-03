#!/usr/bin/env python3
"""S3-guards2 tests (2026-11-03): outcomes F1/F6/F7/F8/F9, cqueue F1/F6. Hermetic temp dirs (tmp_track), no box, no network, no clock (dates injected), TZ pinned, no ntfy.

  1. bridge present_on_ref/autoclose: a test id that appears ONLY in OVERNIGHT_PROGRESS.md / CLAUDE_QUEUE / docs markdown / a code comment is NOT present (the xlite 23b23306 false positive);
     a real `def`/`func`/`it("...")` definition in a code file IS; the landing is tagged item|feature; shadow rows are deduped per (line, tag, day)
  2. bridge harvest done-check: a test-writing item whose named tests are already defined on the ref is logged (shadow, default) / skipped (enforce); an implementation item or an
     item whose test is only mentioned in markdown is never judged done; mode off / unknown mode never enforces by accident
  3. ovn_stub_guard: a FILLED file's leftover one-line placeholder is stripped (enforce) / only logged (shadow default); a pure stub and multi-line forms are untouched
  4. ovn_pingpong_guard: default repo list covers every lane repo; the 'unchanged' and 'no literal ping-pong' lines are logged once, not every pass
  5. MUTANTS: copies of the sources with one substitution each; at least one check must fail on every mutant
Env S3_ROOT points at a different copy of the overnight-queue tree (the mutant runner)."""
import atexit
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

os.environ["TZ"] = "UTC"
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tmp_track  # noqa: E402
tmp_track.install()
REAL = os.path.abspath(os.path.join(HERE, "..", ".."))
Q = os.environ.get("S3_ROOT") or REAL
SC = os.path.join(Q, "scripts")
BASE = os.path.realpath(tempfile.mkdtemp(prefix="s3-guards2-"))
for k in ("OVN_BRIDGE_AUTOCLOSE", "OVN_HARVEST_DONE_CHECK", "OVN_STUB_STRIP", "OVN_PINGPONG_REPOS", "OVN_PINGPONG_MODE", "OVN_STUB_UNDO"):
    os.environ.pop(k, None)
os.environ["OVN_DIR"] = os.path.join(BASE, "q")
os.environ["OVN_STATE_DIR"] = os.path.join(BASE, "q", "state")
os.environ["OVN_REPOS_DIR"] = os.path.join(BASE, "q", "repos")
os.environ["OVN_STUB_GUARD_LOG"] = os.path.join(BASE, "stub_guard.log")
sys.path.insert(0, SC)

FAILS = []
PASSES = [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def rd(path):
    try:
        return open(path).read()
    except OSError:
        return ""


os.environ.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")   # the in-process undo() commits too: it needs an identity on a box with a scratch HOME
GENV = dict(os.environ)


def mkgit(path, branch="develop"):
    os.makedirs(path, exist_ok=True)
    g(path, "init", "-q", "-b", branch)


def g(path, *a):
    return subprocess.run(["git", "-C", path] + list(a), capture_output=True, text=True, env=GENV).stdout


# ------------------------------------------------------------------------------------------------ 1. bridge present_on_ref / autoclose
B = load(os.path.join(Q, "claude_queue_bridge.py"), "claude_queue_bridge_s3")
clones = os.path.join(BASE, "clones")
xl = os.path.join(clones, "xlite")
mkgit(xl)
# the REAL shape of the false positive: the id lives only in the queue text (OVERNIGHT_PROGRESS.md), in docs and in a code COMMENT; mission_data.gd has no such test
w(os.path.join(xl, "OVERNIGHT_PROGRESS.md"), "- [ ] [T4] tests/test_mission_data.gd — add test_is_valid_uses_validators\n  VERIFY: `godot -gtest=test_is_valid_uses_validators`\n")
w(os.path.join(xl, "CLAUDE_QUEUE.md"), "- [ ] [CLAUDE] xlite/ — test_is_valid_uses_validators\n")
w(os.path.join(xl, "docs", "plan.txt"), "func test_docs_only_name()\n")
w(os.path.join(xl, "notes.md"), "def test_markdown_only_name():\n")
w(os.path.join(xl, "tests", "test_mission_data.gd"), "extends GutTest\n# TODO test_commented_only_name should exist someday\nfunc test_is_valid_rejects_oob():\n\tpass\n")
w(os.path.join(xl, "tests", "test_py.py"), "import pytest\n\nasync def test_async_defined():\n    pass\n\n\ndef test_probe_body_contains_ok():\n    pass\n")
w(os.path.join(xl, "web", "a.test.ts"), 'describe("suite", () => {\n  it("renders the link", () => {})\n  test("form hidden", () => {})\n})\n')
g(xl, "add", "-A")
g(xl, "commit", "-q", "-m", "x")
g(xl, "update-ref", "refs/remotes/origin/develop", "HEAD")
P_ = lambda needle: B.present_on_ref(xl, "origin/develop", needle)
chk("present: an id that exists ONLY in OVERNIGHT_PROGRESS.md/CLAUDE_QUEUE.md is NOT present (the xlite false positive)", P_("test_is_valid_uses_validators") is False)
chk("present: an id only in docs/*.txt or a *.md is NOT present", P_("test_docs_only_name") is False and P_("test_markdown_only_name") is False)
chk("present: an id only mentioned in a code COMMENT is NOT present (needs a definition)", P_("test_commented_only_name") is False)
chk("present: a func/async def definition in a code file IS present", P_("test_is_valid_rejects_oob") is True and P_("test_async_defined") is True)
chk("present: pytest -k prefix semantics kept (test_probe_body_contains matches def test_probe_body_contains_ok)", P_("test_probe_body_contains") is True)
chk("present: vitest title in it(...) / test(...) is present", P_("renders the link") is True and P_("form hidden") is True)
chk("present: regex metacharacters in an id are escaped, empty id is false", P_("test_(") is False and P_("") is False and P_("test_is_valid_rejects_oob.*") is False)

L1732 = ('- [ ] [CLAUDE] xlite/ — [T4] tests/test_mission_data.gd — add test. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/test_mission_data.gd -gtest=test_is_valid_uses_validators`. '
         '(cat:godot) [feat:xlite-20261101-wire-the-bounds-and-obstacle-validators-]')
LOK = ('- [ ] [CLAUDE] xlite/ — [T4] tests/test_mission_data.gd — add test. VERIFY: `godot -gtest=test_is_valid_rejects_oob`. (cat:godot) [feat:xlite-20261101-other-feature]')
TAGS = {("xlite", "xlite-20261101-wire-the-bounds-and-obstacle-validators-"), ("xlite", "xlite-20261101-other-feature")}
new, closed = B.autoclose_lines([L1732, LOK], TAGS, clones, "origin/develop", "2026-11-03")
chk("autoclose: the feature landed + the id only in OVERNIGHT_PROGRESS.md must NOT close line 1732; the line whose test is defined in code does", len(closed) == 1 and closed[0][0] == 2 and new[0] == L1732 and new[1].startswith("- [x] "), (closed, new))

OUT = os.path.join(BASE, "outcomes.jsonl")
h_item = B.line_key(LOK)
w(OUT, "\n".join(json.dumps(x) for x in [
    {"class": "landed", "repo": "xlite", "feat_tag": "xlite-20261101-other-feature", "item_line_hash": h_item},
    {"class": "landed", "repo": "xlite", "feat_tag": "xlite-20261101-wire-the-bounds-and-obstacle-validators-", "item_line_hash": "0" * 32}]) + "\n")
hs = B.landed_line_hashes(OUT)
_, c2 = B.autoclose_lines([LOK], B.landed_tags(OUT), clones, "origin/develop", "2026-11-03", hashes=hs)
chk("autoclose: the landing is keyed by the item: a matching line hash says landing=item", len(c2) == 1 and "landing=item" in c2[0][3], c2)
LOK2 = LOK.replace("add test.", "add test (reworded sibling).")
_, c3 = B.autoclose_lines([LOK2], B.landed_tags(OUT), clones, "origin/develop", "2026-11-03", hashes=hs)
chk("autoclose: a different item of the same feature is tagged landing=feature (not item)", len(c3) == 1 and "landing=feature" in c3[0][3], c3)
chk("landed_line_hashes reads item_line_hash and item_hash per (repo, tag)", B.landed_line_hashes(OUT)[("xlite", "xlite-20261101-other-feature")] == {h_item})


def run_ac(mode, queue_text, log):
    qp = os.path.join(BASE, "queue_%s.md" % mode)
    w(qp, queue_text)
    cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "autoclose", "--queue", qp, "--outcomes", OUT, "--repos-dir", clones, "--mode", mode, "--shadow-log", log,
                         "--today", "2026-11-03"], capture_output=True, text=True, env=GENV)
    return qp, cp


QUEUE = "# q\n## s\n" + L1732 + "\n" + LOK + "\n"
LOG = os.path.join(BASE, "state", "bridge_autoclose_shadow.log")
qp, cp = run_ac("shadow", QUEUE, LOG)
run_ac("shadow", QUEUE, LOG)
run_ac("shadow", QUEUE, LOG)
slog = rd(LOG)
chk("autoclose shadow: three hourly passes the same day leave ONE row (dedupe per line, tag, day), only for the really-defined line", slog.count("\n") == 1 and "would-close line 4 xlite" in slog and "1732" not in slog and "validators" not in slog, slog)
chk("autoclose shadow: the queue is untouched", rd(qp) == QUEUE)
qp, cp = run_ac("shadow", QUEUE, LOG.replace("autoclose", "autoclose2"))
cp2 = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "autoclose", "--queue", qp, "--outcomes", OUT, "--repos-dir", clones, "--mode", "shadow", "--shadow-log", LOG, "--today", "2026-11-04"],
                     capture_output=True, text=True, env=GENV)
chk("autoclose shadow: the next day logs the line again (one row per day)", rd(LOG).count("\n") == 2 and "2026-11-04" in rd(LOG), rd(LOG))
qp, cp = run_ac("enforce", QUEUE, os.path.join(BASE, "state", "enf.log"))
t = rd(qp).split("\n")
chk("autoclose enforce: only the defined-in-code line is closed; the progress-file-only line stays open", t[2] == L1732 and t[3].startswith("- [x] "), t)

# ------------------------------------------------------------------------------------------------ 2. harvest done-check
bw = os.path.join(clones, "billwatch")
mkgit(bw, "claude/feature")
w(os.path.join(bw, "tests", "test_geocoder_retry.py"), "def test_is_retryable_error():\n    pass\n")
w(os.path.join(bw, "OVERNIGHT_PROGRESS.md"), "test_only_in_progress_file\n")
g(bw, "add", "-A")
g(bw, "commit", "-q", "-m", "x")
g(bw, "update-ref", "refs/remotes/origin/claude/feature", "HEAD")
T_DONE = "[T4] tests/test_geocoder_retry.py — add a retry test. VERIFY: `pytest tests/test_geocoder_retry.py::test_is_retryable_error -q`. (cat:test) [feat:billwatch-20261103-geocoder-retry-tests]"
T_MD = "[T4] tests/test_geocoder_retry.py — add a retry test. VERIFY: `pytest tests/test_geocoder_retry.py::test_only_in_progress_file -q`. (cat:test) [feat:billwatch-20261103-md-only]"
T_IMPL = "[T3] backend/app/services/geocoder.py — make the retry robust. VERIFY: `pytest tests/test_geocoder_retry.py::test_is_retryable_error -q`. (cat:retry) [feat:billwatch-20261103-impl-item]"
T_NEW = "[T4] tests/test_geocoder_retry.py — add a brand new test. VERIFY: `pytest tests/test_geocoder_retry.py::test_brand_new_thing -q`. (cat:test) [feat:billwatch-20261103-new-test]"
done = lambda task: B.done_check(clones, "billwatch", "origin/claude/feature", task)
chk("done_check: a test-writing item whose named test is already defined is done", done(T_DONE)[0] is True, done(T_DONE))
chk("done_check: an id that only appears in OVERNIGHT_PROGRESS.md is NOT done", done(T_MD)[0] is False, done(T_MD))
chk("done_check: an implementation item naming an existing (maybe red) test is NOT judged done", done(T_IMPL)[0] is False, done(T_IMPL))
chk("done_check: a test that does not exist yet is not done; no VERIFY ids / no clone is not done", done(T_NEW)[0] is False and done("[T4] tests/test_x.py — add. (cat:test)")[0] is False
    and B.done_check(clones, "nope", "origin/claude/feature", T_DONE)[0] is False)


def run_harvest(mode, extra_env=None):
    d = os.path.join(BASE, "h_" + (mode or "default"))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    q = os.path.join(d, "q.md")
    w(q, "# q\n")
    sk = os.path.join(d, "skip.tsv")
    w(sk, "".join("billwatch\t%s\n" % t for t in (T_DONE, T_MD, T_IMPL, T_NEW)))
    dl = os.path.join(d, "harvest_skipped_done.log")
    args = [sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-03", "--repos-dir", clones, "--done-log", dl]
    if mode is not None:
        args += ["--done-mode", mode]
    cp = subprocess.run(args, capture_output=True, text=True, env=dict(GENV, **(extra_env or {})))
    return rd(q), rd(dl), cp


qtxt, dlog, cp = run_harvest(None)
chk("harvest default = shadow: all four lines still harvested, ONE would-skip-done row for the already-done test item", qtxt.count("[CLAUDE]") == 4 and dlog.count("would-skip-done") == 1 and "SHADOW" in dlog and "all 1 named test id(s) defined" in dlog, (qtxt, dlog, cp.stderr))
qtxt, dlog, cp = run_harvest("enforce")
chk("harvest enforce: the already-done test item is NOT harvested; md-only, implementation and new-test items are", qtxt.count("[CLAUDE]") == 3 and "geocoder-retry-tests" not in qtxt and "md-only" in qtxt and "impl-item" in qtxt and "new-test" in qtxt and "ENFORCED" in dlog, (qtxt, dlog))
qtxt, dlog, cp = run_harvest("off")
chk("harvest off: nothing checked, nothing logged", qtxt.count("[CLAUDE]") == 4 and dlog == "", (qtxt, dlog))
qtxt, dlog, cp = run_harvest("bogus")
chk("harvest: an unknown mode falls back to shadow (never enforce by accident)", qtxt.count("[CLAUDE]") == 4 and "SHADOW" in dlog, (qtxt, dlog))
qtxt, dlog, cp = run_harvest(None, {"OVN_HARVEST_DONE_CHECK": "enforce"})
chk("harvest: OVN_HARVEST_DONE_CHECK env selects the mode when --done-mode is absent", qtxt.count("[CLAUDE]") == 3, qtxt)
bsh = rd(os.path.join(Q, "claude_queue_bridge.sh"))
chk("bridge.sh wires the done-check behind OVN_HARVEST_DONE_CHECK (default shadow) and logs to state/harvest_skipped_done.log", "OVN_HARVEST_DONE_CHECK:-shadow" in bsh and "harvest_skipped_done.log" in bsh and "--done-ref" in bsh)

# ------------------------------------------------------------------------------------------------ 3. stub strip
SG = load(os.path.join(SC, "ovn_stub_guard.py"), "ovn_stub_guard_s3")
FILLED = '"""Placeholder - the implement step fills this in."""\n\nimport pytest\n\n\ndef test_null_fields():\n    assert 1\n'
txt, n = SG.strip_marker_text(FILLED)
chk("strip_marker_text: the one-line docstring marker is removed from a filled file (and its blank separator)", n == 1 and txt.startswith("import pytest") and "Placeholder" not in txt, (n, txt))
chk("strip_marker_text: # and // and <!-- --> and /* */ whole-line forms are removed", all(SG.strip_marker_text(a + "\nreal = 1\n")[1] == 1 for a in (
    "# Placeholder - the implement step fills this in.", "// Placeholder - the implement step fills this in.", "<!-- Placeholder - the implement step fills this in. -->", "/* Placeholder - the implement step fills this in. */")))
chk("strip_marker_text: a pure stub is left alone (undo's job), a line with code next to the marker is left alone", SG.strip_marker_text('"""Placeholder - the implement step fills this in."""\n') == ('"""Placeholder - the implement step fills this in."""\n', 0)
    and SG.strip_marker_text("x = 1  # Placeholder - the implement step fills this in\nreal = 2\n")[1] == 0)


def stub_repo(name):
    r = os.path.join(BASE, name)
    mkgit(r, "main")
    w(os.path.join(r, "README"), "x\n")
    g(r, "add", "-A")
    g(r, "commit", "-q", "-m", "init")
    pre = g(r, "rev-parse", "HEAD").strip()
    p = "backend/tests/test_monitor_update_null_fields.py"
    w(os.path.join(r, p), '"""Placeholder - the implement step fills this in."""\n')
    g(r, "add", "-A")
    g(r, "commit", "-q", "-m", "chore: stub new source file before implement")
    stub = g(r, "rev-parse", "HEAD").strip()
    w(os.path.join(r, p), FILLED)
    g(r, "add", "-A")
    g(r, "commit", "-q", "-m", "feat: implement")
    return r, pre, stub, p


r, pre, stub, p = stub_repo("stub_shadow")
head0 = g(r, "rev-parse", "HEAD").strip()
res = SG.undo(r, pre, stub, p)
chk("undo default (shadow): the filled file keeps its placeholder, one shadow row, no commit", res == "strip-shadow" and rd(os.path.join(r, p)) == FILLED and g(r, "rev-parse", "HEAD").strip() == head0 and "would remove 1 leftover" in rd(os.environ["OVN_STUB_GUARD_LOG"]), (res, rd(os.environ["OVN_STUB_GUARD_LOG"])))
os.environ["OVN_STUB_STRIP"] = "enforce"
r, pre, stub, p = stub_repo("stub_enf")
res = SG.undo(r, pre, stub, p)
chk("undo enforce: the placeholder line is stripped in a follow-up commit, the real test body is untouched", res == "stripped" and "Placeholder" not in rd(os.path.join(r, p)) and "def test_null_fields" in rd(os.path.join(r, p))
    and g(r, "log", "-1", "--format=%s").strip().startswith("chore: strip leftover stub placeholder"), (res, g(r, "log", "-1", "--format=%s")))
os.environ["OVN_STUB_STRIP"] = "off"
r, pre, stub, p = stub_repo("stub_off")
chk("undo strip off: nothing happens", SG.undo(r, pre, stub, p) == "strip-off" and rd(os.path.join(r, p)) == FILLED)
os.environ.pop("OVN_STUB_STRIP")

# ------------------------------------------------------------------------------------------------ 4. pingpong default repos + log dedupe
PP = load(os.path.join(SC, "ovn_pingpong_guard.py"), "ovn_pingpong_guard_s3")
seen = []
PP.one_repo = lambda repo, now, state: seen.append(repo)
PP.main()
chk("pingpong default repo list covers every lane repo (gitlark billwatch iptv_apps test-automation-agent xlite shrike-notify shrike-monitor)",
    seen == ["gitlark", "billwatch", "iptv_apps", "test-automation-agent", "xlite", "shrike-notify", "shrike-monitor"], seen)

PP2 = load(os.path.join(SC, "ovn_pingpong_guard.py"), "ovn_pingpong_guard_s3b")
FIX = rd(os.path.join(HERE, "fixtures_k3", "gitlark_status_pingpong.patchlog"))
NOW = 1793491616 + 3600
os.makedirs(os.path.join(os.environ["OVN_REPOS_DIR"], "gitlark", ".git"), exist_ok=True)
MODE = {"log": FIX}


def fake_git(args, cwd=None, timeout=120, env=None):
    if args and args[0] == "log":
        return 0, MODE["log"], ""
    if args and args[0] == "show":
        return 0, "- [ ] [T3] unrelated item\n", ""
    return 0, "", ""


PP2.cg.git = fake_git
PP2.cg.fetch = lambda clone: True
PP2.cg.REPOS = os.environ["OVN_REPOS_DIR"]
PP2.STATE = os.environ["OVN_STATE_DIR"]
PP2.cg.STATE = os.environ["OVN_STATE_DIR"]
os.makedirs(PP2.STATE, exist_ok=True)


def capture(fn, *a):
    old, buf = sys.stdout, io.StringIO()
    sys.stdout = buf
    try:
        fn(*a)
    finally:
        sys.stdout = old
    return buf.getvalue()


o1 = capture(PP2.one_repo, "gitlark", NOW, {"parked": 0})
o2 = capture(PP2.one_repo, "gitlark", NOW, {"parked": 0})
o3 = capture(PP2.one_repo, "gitlark", NOW, {"parked": 0})
chk("pingpong: the first pass logs the PING-PONG finding", "PING-PONG[" in o1 and "unchanged" not in o1, o1)
chk("pingpong: the 'unchanged' line is logged ONCE for a repeated identical state (not on every 20-minute pass)", o2.count("unchanged") == 1 and "unchanged" not in o3 and "PING-PONG[" not in o2, (o2, o3))
MODE["log"] = ""
n1 = capture(PP2.one_repo, "gitlark", NOW, {"parked": 0})
n2 = capture(PP2.one_repo, "gitlark", NOW, {"parked": 0})
chk("pingpong: 'no literal ping-pong' is logged once per repo per day", n1.count("no literal ping-pong") == 1 and n2 == "", (n1, n2))

# ------------------------------------------------------------------------------------------------ 5. mutants
MUTANTS = [
    ("present greps every path (markdown/queue text counts)", "claude_queue_bridge.py", '"-qE", "-e", definition_regex(needle), ref] + list(CODE_PATHSPEC)', '"-qE", "-e", definition_regex(needle), ref]'),
    ("present matches a bare mention, not a definition", "claude_queue_bridge.py", '    n = _ere_escape(needle)\n    return ("(^|', '    n = _ere_escape(needle)\n    return n\n    return ("(^|'),
    ("metacharacters not escaped", "claude_queue_bridge.py", 'return "".join("\\\\" + c if c in _ERE_META else c for c in s)', "return s"),
    ("shadow rows not deduped", "claude_queue_bridge.py", "            if key in row:", "            if False:"),
    ("landing never tagged item/feature", "claude_queue_bridge.py", "                if ok and hashes is not None:", "                if False:"),
    ("done-check judges implementation items done", "claude_queue_bridge.py", 'if not TEST_ITEM_RE.search(task or ""):', "if False:"),
    ("done-check ignores missing tests", "claude_queue_bridge.py", "    missing = [i for i in ids if not present(clone, ref, i)]\n    return (not missing), (\"missing on", "    missing = []\n    return (not missing), (\"missing on"),
    ("done-check default enforce", "claude_queue_bridge.py", 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "shadow"', 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "enforce"'),
    ("done-check enforce never skips", "claude_queue_bridge.py", '                if dmode == "enforce":\n                    continue\n        existing_sigs.add', '                if False:\n                    continue\n        existing_sigs.add'),
    ("strip default enforce", "scripts/ovn_stub_guard.py", 'os.environ.get("OVN_STUB_STRIP", "shadow")', 'os.environ.get("OVN_STUB_STRIP", "enforce")'),
    ("strip also eats a pure stub", "scripts/ovn_stub_guard.py", "    if is_placeholder_only(text):\n        return text, 0\n    out, n", "    out, n"),
    ("strip never wired into undo", "scripts/ovn_stub_guard.py", "if rc == 0 and not is_placeholder_only(body) and MARKER_RE.search(body):", "if False:"),
    ("pingpong default repos lack the new lanes", "scripts/ovn_pingpong_guard.py", 'test-automation-agent xlite shrike-notify shrike-monitor").split()', 'test-automation-agent").split()'),
    ("pingpong unchanged line logged every pass", "scripts/ovn_pingpong_guard.py", 'if quiet and once("UNCH|', 'if quiet or once("UNCH|'),
    ("pingpong 'no literal' logged every pass", "scripts/ovn_pingpong_guard.py", 'if once("NONE|', 'if True or once("NONE|'),
]


def mutants():
    bad = 0
    for name, rel, old, new in MUTANTS:
        mq = os.path.join(BASE, "mut")
        shutil.rmtree(mq, ignore_errors=True)
        os.makedirs(os.path.join(mq, "scripts"))
        for f in os.listdir(SC):
            if f.endswith(".py") or f.endswith(".sh"):
                shutil.copy(os.path.join(SC, f), os.path.join(mq, "scripts", f))
        for f in ("claude_queue_bridge.py", "claude_queue_bridge.sh"):
            shutil.copy(os.path.join(Q, f), os.path.join(mq, f))
        p_ = os.path.join(mq, rel)
        s = open(p_).read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        with open(p_, "w") as f:
            f.write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, S3_ROOT=mq, S3_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


if os.environ.get("S3_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
print("test_s3_guards2: %d passed, %d failed" % (PASSES[0], len(FAILS)))
tmp_track.sweep()
sys.exit(1 if FAILS else 0)
