#!/usr/bin/env python3
"""scripts/ovn_local_research.py: the "covered" rule (2026-10-09).

Old rule: evidence was covered if ANY roadmap line, of ANY status, ever named its file. iptv_apps' 171 untested-function and 10 unlimited-router
findings were all "covered" and every pass logged "only 1 piece(s) of evidence - nothing to research".
New rule (OVN_LR_COVERED_MODE=open, default): covered only by an OPEN line naming the same file AND the same symbol or a line range containing the
evidence line; [x] lines and [decomposed] lines without open sub-items do not cover a gap that still exists.

Hermetic: temp dirs only, no model, no network (evidence-only runs never call the model).
Mutation checks at the bottom prove each rule is load-bearing: break the logic and the semantic checks must fail.
"""
import datetime
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "ovn_local_research.py")
if not os.path.exists(SCRIPT):
    SCRIPT = os.path.expanduser("~/overnight-queue/scripts/ovn_local_research.py")
P = F = 0


def ok(name, cond, detail=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(detail)[:300]) if detail else ""))


def load(path, name="lr_under_test"):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


NOW = time.time()
TODAY = datetime.date.today().strftime("%Y%m%d")
OLD = (datetime.date.today() - datetime.timedelta(days=5)).strftime("%Y%m%d")
META = "{cat: backend; size: S; multifile: no; research: none}"
F_ = "iptv-backend/app/services/foo.py"
EV_BAR = {"kind": "untested-function", "file": F_, "line": 40, "text": "public function `bar` is referenced by no test"}
EV_BAZ = {"kind": "untested-function", "file": F_, "line": 90, "text": "public function `baz` is referenced by no test"}
EV_ROUTER = {"kind": "no-rate-limit", "file": "iptv-backend/app/routers/r.py", "line": 7, "text": "3 route(s) and no @limiter.limit (other routers use it)"}


def rm_line(status, title, body="", box=" "):
    return "- [%s] [P2] [%s] %s — %s %s" % (box, status, title, body, META)


def slug_tag(lr, feature_text, date):
    """Same tag the planner writes: [feat:<repo>-<YYYYMMDD>-<slug>]."""
    return "[feat:demo-%s-%s]" % (date, lr.feat_slug(feature_text))


def semantics(lr):
    """Every rule of the new covered(); returns {name: bool} - all must be True for the real module, and each mutant must break at least one."""
    r = {}

    def cov(roadmap, ev, backlog="", progress=""):
        return lr.make_covered("open", roadmap, backlog, progress, now=NOW)(ev)

    ready_sym = rm_line("ready", "Test bar", "`%s` function `bar` has no test" % F_)
    r["ready line naming file+symbol covers"] = cov(ready_sym, EV_BAR) is True
    r["same file, different symbol is NOT covered"] = cov(ready_sym, EV_BAZ) is False
    r["[x] line naming file+symbol does not cover"] = cov(rm_line("ready", "Test bar", "`%s` function `bar`" % F_, box="x"), EV_BAR) is False
    r["[done] status does not cover"] = cov(rm_line("done", "Test bar", "`%s` function `bar`" % F_), EV_BAR) is False
    line_rm = rm_line("ready", "Fix thing", "see `%s:30-45`" % F_)
    r["file:line range containing the evidence line covers"] = cov(line_rm, EV_BAR) is True
    r["file:line range NOT containing the evidence line does not cover"] = cov(line_rm, EV_BAZ) is False
    # [decomposed]
    title = "Add tests for bar — `%s` function `bar`" % F_
    dec = "- [ ] [P2] [decomposed] %s %s" % (title, META)
    ftext = title + " " + META  # the planner slugs the text after the status marker
    old_closed = "- [x] [T2] %s — done VERIFY: true. %s" % (F_, slug_tag(lr, ftext, OLD))
    r["decomposed >24h old, sub-items all done, gap still present -> NOT covered"] = cov(dec, EV_BAR, backlog=old_closed) is False
    r["decomposed with no feat tag anywhere (unknown age) -> NOT covered"] = cov(dec, EV_BAR) is False
    open_sub = "- [ ] [T2] %s — cover the first function VERIFY: true. %s" % (F_, slug_tag(lr, ftext, OLD))
    r["decomposed with an OPEN sub-item covers (even if old)"] = cov(dec, EV_BAR, backlog=open_sub) is True
    r["open sub-item in the progress file counts too"] = cov(dec, EV_BAR, progress=open_sub) is True
    held = open_sub.replace("[T2]", "[T2] [AUTO-SKIP: x]")
    r["held (AUTO-SKIP) sub-item does not keep it open"] = cov(dec, EV_BAR, backlog=held) is False
    today_closed = "- [x] [T2] %s — done VERIFY: true. %s" % (F_, slug_tag(lr, ftext, TODAY))
    r["decomposed <24h ago (same-day tag), no open sub-item -> covered (grace)"] = cov(dec, EV_BAR, backlog=today_closed) is True
    r["decomposed sub-item for a DIFFERENT symbol does not cover bar"] = cov(dec, EV_BAZ, backlog=open_sub) is False
    # backlog/progress open T-lines
    bl = "- [ ] [T2] %s — add a test for `bar` VERIFY: true." % F_
    r["open backlog T-line naming file+symbol covers"] = cov("# roadmap\n", EV_BAR, backlog=bl) is True
    r["open backlog T-line for another symbol does not cover"] = cov("# roadmap\n", EV_BAZ, backlog=bl) is False
    r["checked-off backlog line does not cover"] = cov("# roadmap\n", EV_BAR, backlog=bl.replace("- [ ]", "- [x]")) is False
    tag_only = "- [ ] [T2] %s — cover the first function VERIFY: true. [feat:demo-%s-add-tests-for-bar-in-foo]" % (F_, TODAY)
    r["a symbol that only appears inside a [feat:] tag slug does not cover"] = cov("# roadmap\n", EV_BAR, backlog=tag_only) is False
    # symbol-less kind
    rl =rm_line("ready", "Rate-limit the r router", "`iptv-backend/app/routers/r.py` has no limiter")
    r["symbol-less kind: open line naming the file and the kind covers"] = cov(rl, EV_ROUTER) is True
    r["symbol-less kind: open line naming the file about something else does not"] = cov(rm_line("ready", "Rename things", "`iptv-backend/app/routers/r.py` is ugly"), EV_ROUTER) is False
    # a bare path substring is not a symbol (bar must not match inside barrier)
    r["symbol match is word-bounded"] = cov(rm_line("ready", "Fix barrier", "`%s` function `barrier`" % F_), EV_BAR) is False
    return r


def evidence_run(d, *flags, env_extra=None):
    env = dict(os.environ, OVN_DIR=d)
    env.pop("OVN_LR_COVERED_MODE", None)
    env.update(env_extra or {})
    r = subprocess.run([sys.executable, SCRIPT, "demo", *flags], capture_output=True, text=True, env=env)
    return r.stdout + r.stderr


def make_fixture(roadmap, backlog=None, progress=None):
    d = tempfile.mkdtemp(prefix="lrc-")
    app = os.path.join(d, "repos", "demo", "iptv-backend", "app", "services")
    os.makedirs(app)
    os.makedirs(os.path.join(d, "repos", "demo", "iptv-backend", "tests"))
    os.makedirs(os.path.join(d, "roadmap"))
    os.makedirs(os.path.join(d, "backlog"))
    for n in ("alpha", "beta"):
        body = "".join("def fn_%s_%d(x):\n    a = x + 1\n    b = a + 1\n    c = b + 1\n    d = c + 1\n    e = d + 1\n    f = e + 1\n    return f\n\n\n" % (n, i) for i in range(6))
        open(os.path.join(app, n + ".py"), "w").write(body)
    open(os.path.join(d, "roadmap", "demo.md"), "w").write(roadmap)
    if backlog is not None:
        open(os.path.join(d, "backlog", "demo.md"), "w").write(backlog)
    if progress is not None:
        open(os.path.join(d, "repos", "demo", "OVERNIGHT_PROGRESS.md"), "w").write(progress)
    return d


lr = load(SCRIPT)

print("== covered(): semantics of the open rule ==")
sem = semantics(lr)
for k, v in sem.items():
    ok(k, v)

print("== legacy mode reproduces the old behaviour (mutation control) ==")
xline = rm_line("ready", "Old thing", "`%s` was handled" % F_, box="x")
leg = lr.make_covered("legacy", xline, now=NOW)
opn = lr.make_covered("open", xline, now=NOW)
ok("legacy: an [x] line naming the file covers EVERY evidence item of that file", leg(EV_BAR) and leg(EV_BAZ))
ok("open: the same [x] line covers none", not opn(EV_BAR) and not opn(EV_BAZ))
st = {}
lr.make_covered("legacy", xline, stats=st)(EV_BAR)
ok("stats counter counts covered findings", st.get("covered") == 1, st)

print("== replay: iptv evidence census (171 untested functions + 10 unlimited routers, roadmap names every file in [x]/[decomposed] lines) ==")
d = tempfile.mkdtemp(prefix="lrc-census-")
try:
    app = os.path.join(d, "iptv-backend", "app")
    os.makedirs(os.path.join(app, "services"))
    os.makedirs(os.path.join(app, "routers"))
    os.makedirs(os.path.join(d, "iptv-backend", "tests"))
    files, total = [], 0
    sizes = [15] * 3 + [14] * 9  # 12 files, 45 + 126 = 171 functions
    for i, n in enumerate(sizes):
        rel = "iptv-backend/app/services/svc%02d.py" % i
        files.append(rel)
        total += n
        with open(os.path.join(d, rel), "w") as f:
            for j in range(n):
                f.write("def public_fn_%d_%d(x):\n    a = x + 1\n    b = a + 1\n    c = b + 1\n    d = c + 1\n    e = d + 1\n    g = e + 1\n    return g\n\n\n" % (i, j))
    ok("fixture really has 171 untested public functions", total == 171, total)
    # the limiter exists in one router; ten other routers have routes and none
    open(os.path.join(app, "routers", "limited.py"), "w").write("@router.get('/a')\n@limiter.limit('5/minute')\ndef a():\n    return 1\n")
    routers = []
    for i in range(10):
        rel = "iptv-backend/app/routers/r%02d.py" % i
        routers.append(rel)
        open(os.path.join(d, rel), "w").write("@router.get('/x')\ndef x():\n    return 1\n")
    ev = lr.py_untested_functions(d) + lr.py_unlimited_routers(d)
    ok("collectors find 171 + 10 findings", len(ev) == 181, len(ev))
    road = "# roadmap\n"
    for i, rel in enumerate(files + routers):
        if i % 2:
            road += rm_line("ready", "Earlier work %d" % i, "`%s` was handled long ago" % rel, box="x") + "\n"
        else:  # a [decomposed] whose sub-items are long gone (no tag in backlog)
            road += rm_line("decomposed", "Earlier feature %d" % i, "touched `%s` once" % rel) + "\n"
    leg = lr.make_covered("legacy", road, now=NOW)
    opn = lr.make_covered("open", road, now=NOW)
    ok("legacy: all 181 findings are 'covered' (the bug)", all(leg(e) for e in ev))
    uncovered = [e for e in ev if not opn(e)]
    per_file = {e["file"] for e in uncovered}
    ok("open: every file that has no open roadmap line yields >=1 uncovered evidence item", per_file == set(files + routers), sorted(set(files + routers) - per_file))
    ok("open: all 181 are uncovered (no open line anywhere)", len(uncovered) == 181, len(uncovered))
    # one file gets a real open line for ONE function: that function (only) becomes covered
    road2 = road + rm_line("ready", "Test fn", "`%s` function `public_fn_0_3` has no test" % files[0]) + "\n"
    opn2 = lr.make_covered("open", road2, now=NOW)
    mine = [e for e in ev if e["file"] == files[0]]
    ok("open: an open line for one symbol covers just that symbol (14 of 15 remain)", sum(1 for e in mine if not opn2(e)) == 14, sum(1 for e in mine if not opn2(e)))
    # evidence cap unchanged: collect() still returns at most MAX_EVIDENCE (14) after skipping
    ok("MAX_EVIDENCE is still 14", lr.MAX_EVIDENCE == 14)
    got = lr.collect(d, skip=opn)
    ok("collect(): capped at MAX_EVIDENCE with the open rule", len(got) == 14, len(got))
    got_l = lr.collect(d, skip=leg)
    ok("collect(): legacy rule leaves nothing to research (the 'only N piece(s)' symptom)", len(got_l) == 0, len(got_l))
finally:
    shutil.rmtree(d, ignore_errors=True)

print("== end to end (--evidence-only, --force) through main() ==")
road_x = "# roadmap\n" + rm_line("ready", "Old", "`iptv-backend/app/services/alpha.py:1` handled", box="x") + "\n"
d1 = make_fixture(road_x)
out_open = evidence_run(d1, "--force", "--evidence-only")
out_leg = evidence_run(d1, "--force", "--evidence-only", env_extra={"OVN_LR_COVERED_MODE": "legacy"})
ok("default (open) mode: [x]-covered file still yields evidence", "services/alpha.py" in out_open, out_open)
ok("legacy mode: the same file is skipped", "services/alpha.py" not in out_leg and "services/beta.py" in out_leg, out_leg)
road_open = "# roadmap\n" + rm_line("ready", "Test alpha_0", "`iptv-backend/app/services/alpha.py` function `fn_alpha_0` has no test") + "\n"
d2 = make_fixture(road_open)
out2 = evidence_run(d2, "--force", "--evidence-only")
ok("open line for fn_alpha_0 hides exactly that finding", "fn_alpha_0`" not in out2 and "fn_alpha_1`" in out2, out2)
bl = "- [ ] [T2] iptv-backend/app/services/beta.py — add a test for `fn_beta_2` VERIFY: true.\n"
d3 = make_fixture("# roadmap\n", backlog=bl)
out3 = evidence_run(d3, "--force", "--evidence-only")
ok("an open BACKLOG line also covers (read from backlog/<repo>.md)", "fn_beta_2`" not in out3 and "fn_beta_3`" in out3, out3)
pg = "- [ ] [T2] iptv-backend/app/services/beta.py — add a test for `fn_beta_4` VERIFY: true.\n"
d4 = make_fixture("# roadmap\n", progress=pg)
out4 = evidence_run(d4, "--force", "--evidence-only")
ok("an open PROGRESS line also covers (repos/<repo>/OVERNIGHT_PROGRESS.md)", "fn_beta_4`" not in out4 and "fn_beta_5`" in out4, out4)
# the 'nothing to research' message names the cause
d5 = make_fixture("# roadmap\n")
for n in ("alpha", "beta"):  # cover all but one finding so evidence < 2
    pass
cover_all = "# roadmap\n" + "".join(rm_line("ready", "T%s%d" % (n, i), "`iptv-backend/app/services/%s.py` function `fn_%s_%d`" % (n, n, i)) + "\n" for n in ("alpha", "beta") for i in range(6) if (n, i) != ("beta", 5))
open(os.path.join(d5, "roadmap", "demo.md"), "w").write(cover_all.replace("[ready]", "[needs-research]"))
out5 = evidence_run(d5, "--force")
ok("<2 evidence: message reports covered count and mode", "only 1 piece(s) of evidence" in out5 and "11 finding(s) covered by open lines, mode=open" in out5, out5)
for x in (d1, d2, d3, d4, d5):
    shutil.rmtree(x, ignore_errors=True)

print("== mutation checks: every rule must be load-bearing ==")
src = open(SCRIPT).read()
mutants = {
    "symbol check always True": ('return any(re.search(r"(?<![\\w])%s(?![\\w])" % re.escape(s), line) for s in syms)', "return True"),
    "[x] lines treated as open": ('            if box != " ":\n                continue\n', "            pass\n"),
    "[decomposed] always open": ("                if open_sub or recent:", "                if True:"),
    "decomposed ignores open sub-items": ("                if open_sub or recent:", "                if recent:"),
    "line-range rule removed": ("        if lo <= e[\"line\"] <= hi:\n            return True\n", "        pass\n"),
    "held sub-items count as open": ('if l.lstrip().startswith("- [ ]") and not HELD_RE.search(l):', 'if l.lstrip().startswith("- [ ]"):'),
    "checked backlog lines count as open": ('if l.startswith("- [ ]") and not HELD_RE.search(l):', 'if l.startswith("- ["):'),
    "feat tag slug counts as evidence": ('    line = re.sub(r"\\[feat:[^\\]]*\\]", "", line)', "    pass"),
    "word boundary dropped":('(?<![\\w])%s(?![\\w])', '%s'),
}
tmpd = tempfile.mkdtemp(prefix="lrc-mut-")
try:
    for name, (a, b) in mutants.items():
        assert a in src, "mutation anchor missing for %r - update the test" % name
        mp = os.path.join(tmpd, "mut.py")
        open(mp, "w").write(src.replace(a, b, 1))
        mod = load(mp, "mut_" + re.sub(r"\W", "_", name))
        broken = [k for k, v in semantics(mod).items() if not v]
        ok("mutant '%s' is caught (%d semantic check(s) fail)" % (name, len(broken)), len(broken) >= 1)
    # default-mode mutation: legacy as the default must fail the end-to-end open-mode check
    a = 'os.environ.get("OVN_LR_COVERED_MODE", "open")'
    assert a in src
    mp = os.path.join(tmpd, "mut_default.py")
    open(mp, "w").write(src.replace(a, 'os.environ.get("OVN_LR_COVERED_MODE", "legacy")', 1))
    dm = make_fixture(road_x)
    env = dict(os.environ, OVN_DIR=dm)
    env.pop("OVN_LR_COVERED_MODE", None)
    r = subprocess.run([sys.executable, mp, "demo", "--force", "--evidence-only"], capture_output=True, text=True, env=env)
    ok("mutant 'legacy is the default' is caught by the e2e check", "services/alpha.py" not in (r.stdout + r.stderr))
    shutil.rmtree(dm, ignore_errors=True)
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

print("local research covered: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
