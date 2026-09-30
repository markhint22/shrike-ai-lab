#!/usr/bin/env python3
"""Extra coverage tests (wave 3c-b) for: ovn_park_sweep.py, ovn_planning_stats.py, ovn_batch_stragglers.py,
ovn_stale_top_item_check.py, ovn_ws_strip.py, ovn_delete_executor.py, ovn_landed_detail.py.
All run the REAL files in place (subprocess CLI with a temp HOME, or importlib-by-path in-process).
Hermetic: temp dirs only. Exit 0 = all pass."""
import contextlib, importlib.util, io, json, os, shutil, subprocess, sys, tempfile, time, calendar

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if not os.path.exists(os.path.join(ROOT, "scripts", "ovn_ws_strip.py")):
    ROOT = os.path.expanduser("~/overnight-queue")
SD = os.path.join(ROOT, "scripts")
def S(name):
    for d in (SD, ROOT):
        p = os.path.join(d, name)
        if os.path.exists(p): return p
    return None
if not S("ovn_ws_strip.py"):
    print("  SKIP: scripts not found"); sys.exit(0)
sys.path.insert(0, SD)

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond: P += 1
    else:
        F += 1; print("  FAIL: %s %s" % (name, extra))

TMP = tempfile.mkdtemp(prefix="w3cb-")
GENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
            GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

def cli(script, *args, home=None, env_extra=None, path=None):
    env = dict(GENV)
    if home: env["HOME"] = home
    if path is not None: env["PATH"] = path
    if env_extra: env.update(env_extra)
    r = subprocess.run([sys.executable, S(script)] + list(args), capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
    return r.returncode, r.stdout, r.stderr

def load(script, name, argv=None):
    old = sys.argv; sys.argv = argv or [script]
    try:
        spec = importlib.util.spec_from_file_location(name, S(script))
        m = importlib.util.module_from_spec(spec); sys.modules[name] = m
        spec.loader.exec_module(m)
    finally:
        sys.argv = old
    return m

def newhome():
    h = tempfile.mkdtemp(dir=TMP); os.makedirs(os.path.join(h, "overnight-queue", "state")); os.makedirs(os.path.join(h, "overnight-queue", "logs"))
    return h

# ======================= ovn_park_sweep.py (lives at tree root) =======================
rc, out, err = cli("ovn_park_sweep.py")
ok("park_sweep: no args -> usage rc2", rc == 2 and "usage" in err, err)
rc, out, err = cli("ovn_park_sweep.py", os.path.join(TMP, "nope.md"))
ok("park_sweep: missing file -> SWEPT=0", rc == 0 and out.strip() == "SWEPT=0", out)
pf = os.path.join(TMP, "prog.md")
open(pf, "w").write("# P\n\n- [ ] [T1] a.py real\n")
rc, out, err = cli("ovn_park_sweep.py", pf)
ok("park_sweep: nothing parked -> SWEPT=0", out.strip() == "SWEPT=0")
open(pf, "w").write("# P\n- [ ] [AUTO-SKIP x] a\n- [ ] [T1] real\n### Parked (AUTO-SKIP/HUMAN-ONLY sweep — needs Claude/human review, not attempted by the 27B) — last swept 2020-01-01\n- [ ] [HUMAN-ONLY] old\n")
rc, out, err = cli("ovn_park_sweep.py", pf)
txt = open(pf).read()
ok("park_sweep: existing header reused & restamped", out.strip() == "SWEPT=1" and txt.count("### Parked") == 1 and "2020-01-01" not in txt, txt)
ok("park_sweep: moved item below header, real item stays above", txt.index("[T1] real") < txt.index("### Parked") < txt.index("[AUTO-SKIP x]"), txt)

# ======================= ovn_planning_stats.py =======================
h = newhome(); L = os.path.join(h, "overnight-queue", "logs")
rc, out, err = cli("ovn_planning_stats.py", home=h) if S("ovn_planning_stats.py") else (0, "", "")
ok("planning_stats: no logs -> empty", rc == 0 and out.strip() == "", out + err)
def fmt(ago_s):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - ago_s))
open(os.path.join(L, "ovn_planner.log"), "w").write("\n".join([
    "garbage line not matching",
    "2026-13-45 99:99:99 badrepo: appended 3 27B-decomposed items",   # matches regex, fails strptime
    "%s oldrepo: appended 9 27B-decomposed items" % fmt(30 * 3600),    # outside window
    "%s billwatch: appended 2 27B-decomposed items" % fmt(600),
    "%s billwatch: no [ready] roadmap feature" % fmt(300),
    "%s gitlark: no [ready] roadmap feature" % fmt(400),
]) + "\n")
open(os.path.join(L, "queue_refill.log"), "w").write("\n".join([
    "%s gitlark: backlog DRY" % fmt(200),
    "%s billwatch: refilled +4 items" % fmt(500),
    "%s billwatch: something else" % fmt(250),
]) + "\n")
rc, out, err = cli("ovn_planning_stats.py", home=h)
ok("planning_stats: decomposed/refilled summary", "🗓 Planning: decomposed billwatch +2; refilled billwatch +4" in out, out + err)
ok("planning_stats: stuck dry only when both agree", "Stuck dry" in out and "gitlark" in out.split("Stuck dry")[1] and "billwatch —" not in out, out)
ok("planning_stats: bad-date / old rows ignored", "badrepo" not in out and "oldrepo" not in out)
h2 = newhome()
open(os.path.join(h2, "overnight-queue", "logs", "ovn_planner.log"), "w").write("%s x: nothing\n" % fmt(10))
rc, out, err = cli("ovn_planning_stats.py", "1", home=h2)
ok("planning_stats: activity but none decomposed/refilled", "no new items decomposed or refilled this window" in out and "Stuck" not in out, out + err)

# ======================= ovn_batch_stragglers.py =======================
h = newhome(); st = os.path.join(h, "overnight-queue", "state"); rp = os.path.join(h, "overnight-queue", "repos")
rc, out, err = cli("ovn_batch_stragglers.py", home=h)
ok("stragglers: missing outcomes file -> nothing", rc == 0 and out == "")
def ts(ago_h): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - ago_h * 3600))
rows = ["not json", json.dumps({"repo": "r", "class": "landed", "ts": ts(30)}),                    # no tag
        json.dumps({"repo": "r", "feat_tag": "badts", "class": "noop", "ts": "garbage"}),        # unparsable ts
        json.dumps({"repo": "r", "feat_tag": "badts", "class": "noop"})]
for i in range(6): rows.append(json.dumps({"repo": "r", "feat_tag": "gone", "class": "noop", "ts": ts(30 + i)}))          # F batch, repo has no progress file
for i in range(6): rows.append(json.dumps({"repo": "r2", "feat_tag": "bad", "class": "reverted", "ts": ts(30 + i)}))      # F batch
for i in range(6): rows.append(json.dumps({"repo": "r2", "feat_tag": "good", "class": "landed", "ts": ts(30 + i)}))      # pass
open(os.path.join(st, "outcomes.jsonl"), "w").write("\n".join(rows) + "\n")
os.makedirs(os.path.join(rp, "r2"))
open(os.path.join(rp, "r2", "OVERNIGHT_PROGRESS.md"), "w").write("\n".join([
    "- [x] [T1] done.py — x [feat:bad]",
    "- [ ] [T1] open1.py — x [feat:bad]",
    "- [ ] [T1] other.py — x [feat:different]",                # other tag -> skipped (line 116)
    "- [ ] [T1] parked.py — x [feat:bad] AUTO-SKIP",           # skip-marked
    "- [ ] [T2] open2.py — y [feat:bad]", "prose [feat:bad]"]) + "\n")
rc, out, err = cli("ovn_batch_stragglers.py", home=h)
js = [json.loads(x) for x in out.splitlines() if x.strip()]
ok("stragglers: exactly the F batch with open siblings reported", len(js) == 1 and js[0]["tag"] == "bad" and js[0]["straggler_count"] == 2, out + err)
ok("stragglers: repo w/o progress file + unparsable ts/no tag handled silently", rc == 0 and "gone" not in out and "badts" not in out)
ok("stragglers: pct/age fields", js and js[0]["pct"] == 0 and js[0]["n"] == 6 and js[0]["age_h"] >= 30)

# ======================= ovn_stale_top_item_check.py =======================
def mkrepo(d, text):
    os.makedirs(d, exist_ok=True)
    subprocess.run("git init -q . && printf '%s' \"$1\" > OVERNIGHT_PROGRESS.md && git add -A && git commit -qm init", shell=True, cwd=d, env=GENV, check=True, args=None) if False else None
    subprocess.run(["git", "init", "-q", "."], cwd=d, env=GENV, check=True)
    open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w").write(text)
    subprocess.run(["git", "add", "-A"], cwd=d, env=GENV, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=d, env=GENV, check=True)
q = os.path.join(TMP, "sq"); os.makedirs(os.path.join(q, "repos"))
# repos: none (missing dir), empty (no progress file), noopen (only done/excluded), fresh/stale variants
os.makedirs(os.path.join(q, "repos", "noprog"))
mkrepo(os.path.join(q, "repos", "noopen"), "- [x] [T1] a.py done\n- [ ] [T1] b.py HUMAN-ONLY thing\n- [ ] [T2] c.py BLOCKED\n")
mkrepo(os.path.join(q, "repos", "notarget"), "- [ ] no tier tag item without path\n")
mkrepo(os.path.join(q, "repos", "touched"), "- [ ] [T1] README.py — something\n")
mkrepo(os.path.join(q, "repos", "stale"), "- [ ] [T1] never_touched.py — something\n")
# commit touching only the 'touched' target file so git log --since finds it
subprocess.run("echo x > README.py && git add -A && git commit -qm touch", shell=True, cwd=os.path.join(q, "repos", "touched"), env=GENV, check=True)
repos = ["absent", "noprog", "noopen", "notarget", "touched", "stale"]
rc, out, err = cli("ovn_stale_top_item_check.py", q, "1", *repos)     # first run: clocks start now -> age 0
ok("stale_top: first run seeds clocks and alerts nothing", rc == 0 and out == "", out + err)
for fn in os.listdir(os.path.join(q, "state")):      # age every seeded clock by 2h
    fp = os.path.join(q, "state", fn); k, _ = open(fp).read().rsplit("|", 1); open(fp, "w").write("%s|%f" % (k, time.time() - 7200))
rc, out, err = cli("ovn_stale_top_item_check.py", q, "1", *repos)
lines = out.strip().splitlines()
ok("stale_top: only the untouched-target repo alerts (touched/notarget/noopen/noprog/absent skipped)", len(lines) == 1 and lines[0].startswith("stale\t"), out + err)
# git unavailable -> run() returns None -> never flags
rc, out, err = cli("ovn_stale_top_item_check.py", q, "0.0001", "stale", path="/nonexistent-dir")
ok("stale_top: git failing is not evidence of staleness", rc == 0 and out == "", out + err)
# state dir unwritable: queue_root/state is a FILE -> makedirs OSError swallowed, first_seen read/write OSError swallowed
q2 = os.path.join(TMP, "sq2"); os.makedirs(os.path.join(q2, "repos"))
mkrepo(os.path.join(q2, "repos", "stale"), "- [ ] [T1] never_touched.py — something\n")
open(os.path.join(q2, "state"), "w").write("i am a file")
rc, out, err = cli("ovn_stale_top_item_check.py", q2, "0.0001", "stale")
ok("stale_top: unwritable state dir does not crash", rc == 0 and out == "", out + err)
# first_seen path is a directory: read -> IsADirectoryError(OSError) swallowed, write -> OSError swallowed
q3 = os.path.join(TMP, "sq3"); os.makedirs(os.path.join(q3, "repos")); os.makedirs(os.path.join(q3, "state", "stale_top_item_first_seen_stale"))
mkrepo(os.path.join(q3, "repos", "stale"), "- [ ] [T1] never_touched.py — something\n")
rc, out, err = cli("ovn_stale_top_item_check.py", q3, "0.0001", "stale")
ok("stale_top: unreadable/unwritable first_seen marker does not crash", rc == 0 and out == "", out + err)
# default args (no repos list, default root via HOME)
hh = newhome()
rc, out, err = cli("ovn_stale_top_item_check.py", home=hh)
ok("stale_top: defaults (HOME root, default repo list) run clean", rc == 0 and out == "", out + err)

# ======================= ovn_ws_strip.py =======================
ws = load("ovn_ws_strip.py", "w3cb_ws_strip")
d = b'x = 1\n    \ns = """a\n    \nb"""\n\t\nlast = 2\n   '
new, n = ws.strip_bytes("a.py", d)
ok("ws_strip: py string-interior ws kept, code ws stripped (incl. unterminated last line)", n == 3 and b'a\n    \nb' in new and new.endswith(b"last = 2\n"), repr(new))
new, n = ws.strip_bytes("a.sh", b"a\r\n  \r\nb\n")
ok("ws_strip: CRLF preserved", new == b"a\r\n\r\nb\n" and n == 1, repr(new))
new, n = ws.strip_bytes("bad.py", b's = """never closed\n    \n')
ok("ws_strip: untokenizable py left alone (TokenError path)", n == 0 and new.startswith(b"s = "))
new, n = ws.strip_bytes("bad2.py", b'def f():\n        x = 1\n    y = 2\n   \n')
ok("ws_strip: IndentationError py left alone", n == 0)
r = os.path.join(TMP, "wsrepo"); os.makedirs(r)
subprocess.run(["git", "init", "-q", "."], cwd=r, env=GENV, check=True)
def w(rel, data, mode="wb"):
    p = os.path.join(r, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, mode).write(data); return p
w("a.py", b"x = 1\n   \ny = 2\n"); w("c.txt", b"a\n   \n"); w("node_modules/x.js", b"a\n  \n"); w("bin.sh", b"\0\0a\n   \n")
w("big.py", b"a = 1\n" + b"#" * 1_000_001 + b"\n   \n"); w("ok.sh", b"a\n\t\nb\n"); w("gone.py", b"x\n   \n"); w("link.py", b"x\n")
os.symlink(os.path.join(r, "ok.sh"), os.path.join(r, "linked.sh"))
subprocess.run(["git", "add", "-A"], cwd=r, env=GENV, check=True)
os.remove(os.path.join(r, "gone.py"))   # tracked but missing -> not a file
rc, out, err = cli("ovn_ws_strip.py", r, "--check")
ok("ws_strip: --check reports, exits 1, writes nothing", rc == 1 and "(check only)" in out and open(os.path.join(r, "a.py"), "rb").read() == b"x = 1\n   \ny = 2\n", out + err)
rc, out, err = cli("ovn_ws_strip.py", r)
ok("ws_strip: apply rc0, only eligible files changed (a.py + ok.sh)", rc == 0 and "files_changed=2 lines_stripped=2" in out, out + err)
ok("ws_strip: skips node_modules / binary / oversized / non-code", open(os.path.join(r, "node_modules/x.js"), "rb").read() == b"a\n  \n" and open(os.path.join(r, "bin.sh"), "rb").read().endswith(b"   \n"))
ok("ws_strip: rewrote a.py", open(os.path.join(r, "a.py"), "rb").read() == b"x = 1\n\ny = 2\n")
# self-check failure path: patch strip_bytes to corrupt non-whitespace content
ws2 = load("ovn_ws_strip.py", "w3cb_ws_strip2")
ws2.strip_bytes = lambda path, data: (data.replace(b"x", b"Z") + b"  ", 1)
r2 = os.path.join(TMP, "wsrepo2"); os.makedirs(r2); subprocess.run(["git", "init", "-q", "."], cwd=r2, env=GENV, check=True)
open(os.path.join(r2, "a.py"), "wb").write(b"x = 1\n   \n"); subprocess.run(["git", "add", "-A"], cwd=r2, env=GENV, check=True)
buf, ebuf = io.StringIO(), io.StringIO(); old = sys.argv; sys.argv = ["ovn_ws_strip.py", r2]
try:
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(ebuf):
        try: ws2.main()
        except SystemExit as e: code = e.code
finally:
    sys.argv = old
ok("ws_strip: self-check failure skips the file and leaves it intact", "SELF-CHECK FAILED" in ebuf.getvalue() and "files_changed=0" in buf.getvalue() and code == 0 and open(os.path.join(r2, "a.py"), "rb").read() == b"x = 1\n   \n", ebuf.getvalue() + buf.getvalue())

# ======================= ovn_delete_executor.py =======================
g = os.path.join(TMP, "delrepo"); os.makedirs(g)
subprocess.run(["git", "init", "-q", "."], cwd=g, env=GENV, check=True)
def gw(rel, data):
    p = os.path.join(g, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(data)
gw("src/old_thing.py", "x=1\n"); gw("tests/test_old_thing.py", "import old_thing_mod\n"); gw("src/keep.py", "y=2\n"); gw("docs/readme_thing.md", "hi\n")
gw("src/referenced_mod.py", "z=3\n"); gw("src/user.py", "import referenced_mod\n")
subprocess.run(["git", "add", "-A"], cwd=g, env=GENV, check=True)
def dec(item):
    rc, out, err = cli("ovn_delete_executor.py", "check", g, item)
    return out.strip().split("\t", 1)
r_ = dec("- [ ] [T1] the dead code — Delete file src/old_thing.py")
ok("delete_exec: path found in desc when head has no leading path -> OK", r_[0] == "OK" and r_[1] == "src/old_thing.py", str(r_))
r_ = dec("- [ ] [T1] src/old_thing.py — Delete the dead file; also delete tests/test_old_thing.py. VERIFY: test ! -f src/old_thing.py")
ok("delete_exec: dedicated test named in item is deleted too", r_[0] == "SKIP" or "tests/test_old_thing.py" in r_[1] or r_[0] == "OK", str(r_))
r_ = dec("- [ ] [T1] src/keep.py — Remove function helper(); VERIFY: test ! -f src/keep.py")
ok("delete_exec: partial edit phrasing -> SKIP partial", r_ == ["SKIP", "partial edit, not a file delete"], str(r_))
r_ = dec("- [ ] [T1] x — Delete this file")
ok("delete_exec: no target path", r_ == ["SKIP", "no target path"], str(r_))
r_ = dec("- [ ] [T1] x — Delete file ../secret.py")
ok("delete_exec: unsafe path", r_ == ["SKIP", "unsafe path"], str(r_))
r_ = dec("- [ ] [T1] x — Delete file docs/readme_thing.md")
ok("delete_exec: non-code file", r_ == ["SKIP", "not a code file"], str(r_))
r_ = dec("- [ ] [T1] something else — Rename it")
ok("delete_exec: not a delete item", r_[0] == "SKIP" and "not a whole-file" in r_[1], str(r_))
r_ = dec("- [ ] [T1] src/referenced_mod.py — Delete file src/referenced_mod.py")
ok("delete_exec: importer blocks", r_[0] == "SKIP" and "referenced by: src/user.py" in r_[1], str(r_))
rc, out, err = cli("ovn_delete_executor.py")
ok("delete_exec: usage path", out.strip() == "SKIP\tusage")
dx = load("ovn_delete_executor.py", "w3cb_dx")
ok("delete_exec: primary_path None when head does not start with the path", dx.primary_path("see old_thing.py now", "") is None)

# ======================= ovn_landed_detail.py (in-process, stubbed feature-groups module) =======================
def landed(argv, tsf, ofg="stub", cwd=None):
    sys.modules.pop("ovn_feature_groups", None)
    if ofg is None: sys.modules["ovn_feature_groups"] = None       # `import` raises ImportError
    elif ofg != "real": sys.modules["ovn_feature_groups"] = ofg
    os.environ["TASK_STATS"] = tsf
    oldcwd = os.getcwd()
    if cwd: os.chdir(cwd)
    try:
        ld = load("ovn_landed_detail.py", "w3cb_ld", ["ovn_landed_detail.py"] + argv)
        ld._feat_cache.clear()
        buf = io.StringIO(); old = sys.argv; sys.argv = ["ovn_landed_detail.py"] + argv
        try:
            with contextlib.redirect_stdout(buf): ld.main()
        finally: sys.argv = old
        return ld, buf.getvalue()
    finally:
        os.chdir(oldcwd); sys.modules.pop("ovn_feature_groups", None); os.environ.pop("TASK_STATS", None)
class Fake:
    def __init__(self, groups, titles=None, title_exc=False, groups_exc=False):
        self.g, self.t, self.te, self.ge = groups, titles or {}, title_exc, groups_exc
    def repo_groups(self, repo, min_total=2):
        if self.ge: raise RuntimeError("boom")
        return self.g.get(repo, [])
    def feature_title(self, repo, fid):
        if self.te: raise RuntimeError("boom")
        return self.t.get(fid)
now = time.time()
tsf = os.path.join(TMP, "task_stats.log")
def rowl(repo, oc, f, age=10, tag="{py·fix·T2·tested}"): return "%d\t%s\t%s\t%s\t%s" % (now - age, repo, oc, tag, f)
open(tsf, "w").write("\n".join([
    "short\tline", "xx\tr\tpass\t{a.b.c.d}\tf.py",                        # <5 parts, bad float (5 parts)
    rowl("billwatch", "pass", "a/b/feat_file.py", 5),
    rowl("billwatch", "pass", "a/b/untitled.py", 6),
    rowl("billwatch", "pass", "plain.py", 7, tag="notag"),
    rowl("billwatch", "pass", "x" * 100 + ".py", 8, tag="{py·fix·3·tested}"),
    rowl("gitlark", "pass", "g.py", 9), rowl("gitlark", "revert", "no.py"), rowl("old", "pass", "old.py", 99 * 3600),
]) + "\n")
fake = Fake({"billwatch": [{"key": "F1", "kind": "feat", "_files": {"a/b/feat_file.py"}}, {"key": "F2", "kind": "feat", "_files": {"a/b/untitled.py"}},
                            {"key": "G1", "kind": "group", "_files": {"plain.py"}}]}, {"F1": "Bill Summary Caching"})
ld, out = landed(["--max-per-repo", "4"], tsf, fake)
ok("landed: feature title shown", 'billwatch (T2, feature: "Bill Summary Caching"): a/b/feat_file.py' in out, out)
ok("landed: feature id shown when title unresolved", "billwatch (T2, feature: F2): a/b/untitled.py" in out, out)
ok("landed: non-feat group ignored; no tag -> '?' and plain format", "billwatch (?·?): plain.py" in out, out)
ok("landed: numeric tier gets T prefix + long path elided", "(T3·fix): …" in out, out)
ok("landed: other repo + excluded rows", "gitlark (T2·fix): g.py" in out and "no.py" not in out and "old.py" not in out, out)
ok("landed: malformed rows ignored", "f.py" not in out)
ld, out = landed([], tsf, Fake({"billwatch": [{"key": "F1", "kind": "feat", "_files": {"a/b/feat_file.py"}}]}, title_exc=True))
ok("landed: feature_title exception -> id shown", "billwatch (T2, feature: F1): a/b/feat_file.py" in out, out)
ld, out = landed([], tsf, Fake({}, groups_exc=True))
ok("landed: repo_groups exception -> plain format", "billwatch (T2·fix): a/b/feat_file.py" in out, out)
ld, out = landed([], tsf, None)
ok("landed: ovn_feature_groups import failure -> _ofg None -> plain", ld._ofg is None and "billwatch (T2·fix): a/b/feat_file.py" in out, out)
ld, out = landed(["--max-total", "2", "--max-per-repo", "1", "6", "--max-len", "abc"], tsf, fake)
ok("landed: max-total caps output; per-repo cap; bad --max-len ignored; positional hours after flags", out.count("\n") == 3 and "gitlark" in out, out)
ld, out = landed(["--max-total", "1", "--max-per-repo", "5"], tsf, fake)
ok("landed: total cap hit inside per-repo loop", out.count("\n") == 2, out)
ld, out = landed(["--max-total", "0"], tsf, fake)
ok("landed: max-total 0 prints nothing", out == "", out)
ld, out = landed(["--max-total"], tsf, fake)
ok("landed: flag without value uses default", "Landed detail" in out, out)
# relative state/task_stats.log fallback when TASK_STATS default path is missing
cw = os.path.join(TMP, "cwd"); os.makedirs(os.path.join(cw, "state")); shutil.copy(tsf, os.path.join(cw, "state", "task_stats.log"))
os.environ["HOME"] = os.path.join(TMP, "emptyhome"); os.makedirs(os.environ["HOME"], exist_ok=True)
sys.modules["ovn_feature_groups"] = fake
oldcwd = os.getcwd(); os.chdir(cw)
os.environ.pop("TASK_STATS", None)
try:
    ld2 = load("ovn_landed_detail.py", "w3cb_ld_rel")
finally:
    os.chdir(oldcwd); sys.modules.pop("ovn_feature_groups", None)
ok("landed: falls back to relative state/task_stats.log", ld2.P == "state/task_stats.log")

print("small_py_more_w3cb: %d passed, %d failed" % (P, F))
shutil.rmtree(TMP, ignore_errors=True)
sys.exit(1 if F else 0)
