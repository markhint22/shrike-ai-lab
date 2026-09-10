#!/usr/bin/env python3
"""Unit tests for the overnight-queue Python helpers:
  ovn_classify.py, ovn_generate_items.py, ovn_retire_vague.py, ovn_stats.py
Run: python3 test_helpers.py   (exit 0 = all pass). No pytest dependency.
"""
import os, sys, tempfile, shutil, subprocess, importlib.util

SCRIPTS = os.environ.get("OVN_SCRIPTS", os.path.expanduser("~/overnight-queue/scripts"))
sys.path.insert(0, SCRIPTS)

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))

def load(mod):
    spec = importlib.util.spec_from_file_location(mod, os.path.join(SCRIPTS, mod + ".py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

# ---------------- ovn_classify ----------------
def test_classify():
    C = load("ovn_classify")
    cases = [
        ("`x/foo.py` — add `Query(10, ge=1, le=100)` bounds. One file.", "py", "validation", None, "test-covered"),
        ("`a/b.vue` — add `type=\"button\"` to the button. One file.", "vue", "a11y", "T1", "test-covered"),
        ("`s/t.ts` — guard with `Array.isArray(response.data)`. One file.", "ts", "validation", None, "test-covered"),
        ("`m/n.py` — change `def __repr__(self):` to `def __repr__(self) -> str:`. One file.", "py", "typing", None, "test-covered"),
        ("`v/w.swift` — add device-code login flow.", "swift", None, None, "unverifiable"),
        ("`scripts/battle/damage.gd` — add a pure clamp helper for damage values.", "gdscript", None, None, "test-covered"),
        ("`v/w.kt` — add a Leanback launcher activity.", "kotlin", None, None, "unverifiable"),
        ("`d/e.py` — implement real cyclomatic complexity via stdlib ast across the module.", "py", "feature", "T4", "test-covered"),
        ("`README.md` — remove the deprecated bullet.", "md", "docs", None, "unverifiable"),
        ("`k/l.py` — change the bare `except:` to `except Exception:`. One file.", "py", "syntax", "T1", "test-covered"),
    ]
    for text, lang, typ, cx, verif in cases:
        c = C.classify(text)
        ok("classify.lang " + lang, c["lang"] == lang, "got %s" % c["lang"])
        if typ:  ok("classify.type " + typ, c["type"] == typ, "got %s for: %s" % (c["type"], text[:40]))
        if cx:   ok("classify.cx " + cx, c["complexity"] == cx, "got %s" % c["complexity"])
        ok("classify.verif " + verif, c["verif"] == verif, "got %s" % c["verif"])
    # tag round-trips into the {lang·type·cx·verif} shape
    tag = C.tag(C.classify("`x/y.py` add Query bounds"))
    ok("classify.tag shape", tag.startswith("{") and tag.count("·") == 3 and tag.endswith("}"), tag)

# ---------------- ovn_generate_items ----------------
def test_generate():
    G = load("ovn_generate_items")
    d = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(d, "app"))
        # a bare-except (HIGH) + an untyped __repr__ (LOW) in the SAME file -> one item (per-file)
        open(os.path.join(d, "app", "svc.py"), "w").write(
            "class A:\n    def __repr__(self):\n        return 'a'\n    def f(self):\n        try:\n            pass\n        except:\n            pass\n")
        # a second file with only an untyped __init__
        open(os.path.join(d, "app", "other.py"), "w").write("class B:\n    def __init__(self, x):\n        self.x = x\n")
        # a vue with a target=_blank missing rel
        open(os.path.join(d, "app", "v.vue"), "w").write('<template><a href="x" target="_blank">y</a></template>\n')
        found = G.scan(d)
        rels = {k: v for k, v in found.items()}
        ok("generate finds svc.py", "app/svc.py" in rels)
        ok("generate one-item-per-file", list(rels.keys()).count("app/svc.py") == 1)
        # bare-except should win (HIGH) over __repr__ (LOW) in svc.py
        ok("generate prioritizes bare-except", rels.get("app/svc.py", ("", ""))[0] == "HIGH", str(rels.get("app/svc.py")))
        ok("generate finds other.py __init__", "app/other.py" in rels)
        ok("generate finds vue rel", "app/v.vue" in rels and rels["app/v.vue"][0] == "HIGH")
        # dedup: already-referenced file is skipped by main()
        prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
        open(prog, "w").write("# P\n\n## Next Steps\n- [ ] `app/svc.py` already queued\n")
        out = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_generate_items.py"), d, "12"],
                             capture_output=True, text=True)
        body = open(prog).read()
        ok("generate skips already-referenced svc.py", body.count("`app/svc.py`") == 1, "count=%d" % body.count("`app/svc.py`"))
        ok("generate appended others", "app/other.py" in body or "app/v.vue" in body)
        ok("generate reports count", "GENERATED=" in out.stdout)
    finally:
        shutil.rmtree(d)

# ---------------- ovn_retire_vague ----------------
def test_retire():
    R = load("ovn_retire_vague")
    d = tempfile.mkdtemp()
    try:
        os.chdir(d)
        open(os.path.join(d, "real.py"), "w").write("x = 1\n")  # a file that exists
        prog = os.path.join(d, "OVERNIGHT_PROGRESS.md")
        open(prog, "w").write(
            "# P\n\n## Next Steps\n"
            "- [ ] [HIGH] `real.py` — change something. One file.\n"          # valid -> keep
            "- [ ] [MED] A service module: add a helper, empty/zero result.\n"  # vague (no file) -> retire
            "- [ ] [LOW] `gone/missing.py` — fix a thing. One file.\n"          # dead-path -> retire
            "- [ ] [MED] `newpkg/parser.py` — Create a new pure parser module. One file.\n"  # create-intent, missing file -> KEEP
            "- [ ] (human/Claude) do a big multi-file thing.\n"                 # human -> keep
        )
        v, dead = R.process(prog)
        body = open(prog).read()
        ok("retire vague count", v == 1, "v=%d" % v)
        ok("retire dead-path count", dead == 1, "dead=%d" % dead)
        # 2026-09-01: a 'create a new file' item names a path that doesn't exist
        # YET — it must NOT be retired as dead-path (this bug silently ate every
        # new-module/new-test item across all repos).
        ok("retire keeps create-new-file item", "- [ ] [MED] `newpkg/parser.py`" in body, body)
        ok("retire keeps valid item", "- [ ] [HIGH] `real.py`" in body)
        ok("retire keeps human item", "human/Claude" in body and "- [ ] (human/Claude)" in body)
        ok("retire tagged vague", "retired-vague" in body)
        ok("retire tagged dead-path", "retired-dead-path" in body)
        # the loose-path false-positive regression: "empty/zero" must NOT count as a file
        ok("retire empty/zero not a file", body.count("retired-vague) [MED] A service module") == 1)
    finally:
        os.chdir("/"); shutil.rmtree(d)

# ---------------- ovn_stats ----------------
def test_stats():
    d = tempfile.mkdtemp()
    try:
        log = os.path.join(d, "task_stats.log")
        import time
        now = int(time.time())
        rows = [
            (now, "billwatch", "pass",   "{py·validation·T2·test-covered}", "a.py"),
            (now, "billwatch", "pass",   "{vue·a11y·T1·test-covered}", "b.vue"),
            (now, "gitlark",   "noop:flail",   "{py·typing·T1·test-covered}", "c.py"),
            (now, "gitlark",   "revert", "{ts·bugfix·T3·test-covered}", "d.ts"),
            (now, "iptv",      "error",  "{py·other·T1·test-covered}", "e.py"),
            (now, "shrike",    "noop:blocked", "{swift·other·T2·unverifiable}", "f.swift"),
            (now, "xlite",     "skip",   "{godot·data·T2·unverifiable}", "g.tres"),
        ]
        with open(log, "w") as fh:
            for r in rows:
                fh.write("\t".join(str(x) for x in r) + "\n")
        env = dict(os.environ)
        # point ovn_stats at our fixture by symlinking into a fake HOME layout
        fakehome = tempfile.mkdtemp()
        os.makedirs(os.path.join(fakehome, "overnight-queue", "state"))
        shutil.copy(log, os.path.join(fakehome, "overnight-queue", "state", "task_stats.log"))
        env["HOME"] = fakehome
        out = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_stats.py"), "24"],
                             capture_output=True, text=True, env=env).stdout
        ok("stats landed=2", "2 landed" in out, out.splitlines()[1] if len(out.splitlines())>1 else out)
        ok("stats failed=1", "1 failed" in out)
        ok("stats noop=2 (both cause-tagged)", "2 no-op" in out)
        ok("stats errored=1", "1 errored" in out)
        ok("stats pass-rate 66%", "66%" in out, [l for l in out.splitlines() if 'pass-rate' in l])
        # 2026-09-09: the per-tier breakdown moved to ovn_tier_stats.py (reads
        # outcomes.jsonl, has explicit tiers + no-op/timeout/token detail this
        # script's 'cx'-tag inference couldn't show) - see test_ntfy_stats.sh.
        # Assert the OLD line is gone so a stale reintroduction doesn't silently
        # produce two slightly-different tier lines in the same digest.
        ntfy_out = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_stats.py"), "24", "--ntfy"],
                                  capture_output=True, text=True, env=env).stdout
        ok("ntfy no longer emits its own Tiers line (superseded)",
           not any(l.startswith("Tiers:") for l in ntfy_out.splitlines()), ntfy_out)
        # no-op CAUSE breakdown: distinguishes a real bug (flail/done) from
        # under-specified (blocked). Fixture has 1 flail + 1 blocked.
        cause_line = next((l for l in ntfy_out.splitlines() if l.startswith("No-op causes:")), "")
        ok("ntfy shows No-op causes line", cause_line != "", ntfy_out)
        ok("ntfy causes count flailed", "flailed 1" in cause_line, cause_line)
        ok("ntfy causes count blocked", "blocked 1" in cause_line, cause_line)
        # an exhausted-repo 'skip' row must NOT inflate the no-op count (the whole
        # point: idle != wasted). Fixture has 2 noop + 1 skip -> still "2 no-op".
        ok("skip is not counted as a no-op", "2 no-op" in out)
        # 2026-09-09: idle_repos()/"Exhausted repos" was removed from the ntfy output - superseded
        # by ovn_planning_stats.py's "Stuck dry" line in the digest (see test_ntfy_stats.sh), which
        # checks the same condition more precisely (requires planner AND refill to both agree a
        # repo is out of work, not just a same-instant doable-count snapshot). Assert it's gone so
        # a stale reintroduction doesn't silently duplicate that signal in the same digest.
        rdir = tempfile.mkdtemp()
        os.makedirs(os.path.join(rdir, "emptyrepo")); os.makedirs(os.path.join(rdir, "busyrepo"))
        open(os.path.join(rdir, "emptyrepo", "OVERNIGHT_PROGRESS.md"), "w").write(
            "## Next Steps\n- [x] done\n- [ ] [AUTO-SKIP] parked earlier\n")
        open(os.path.join(rdir, "busyrepo", "OVERNIGHT_PROGRESS.md"), "w").write(
            "## Next Steps\n- [ ] `a.py` real work. One file.\n")
        env2 = dict(env); env2["OVN_REPOS_DIR"] = rdir; env2["OVN_ACTIVE_REPOS"] = "emptyrepo busyrepo"
        nout = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_stats.py"), "24", "--ntfy"],
                              capture_output=True, text=True, env=env2).stdout
        ok("ntfy no longer emits its own Exhausted-repos line (superseded)",
           not any(l.startswith("Exhausted repos") for l in nout.splitlines()), nout)
        shutil.rmtree(rdir)
        shutil.rmtree(fakehome)
    finally:
        shutil.rmtree(d)

if __name__ == "__main__":
    for t in (test_classify, test_generate, test_retire, test_stats):
        print("== %s ==" % t.__name__)
        t()
    print("\nPython helpers: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
