#!/usr/bin/env python3
"""P5-supply-truth tests (2026-11-02): outcomes F4, cqueue F3 + F4. Hermetic temp dirs, no box, no network, no clock (all dates injected), TZ pinned.

  1. ovn_supply_filter: ONE doable definition; open == doable + sum(excluded); ovn_notify._doable and fleet_stats.queue_counts agree with it (fleet_stats used to count [CLAUDE] lines as doable)
  2. ovn_supply_report.collect: doable AND pullable AND excluded-by-reason in the record and in the line; runway computed from doable (old json keys kept)
  3. claude_queue_bridge autoclose: closes a harvested line by [feat:] tag when the fleet landed it AND the named test ids exist on the ref; shadow mode only logs; wrong path in the line is irrelevant;
     harvest does not re-open a closed/landed feature (enforce) and only logs it (shadow)
  4. ovn_already_done_gate: no VERIFY / wrong file / absent target string are refused (the xlite pause case), a real done item passes
  5. MUTANTS: copies of the source with one substitution each; at least one check must fail on every mutant
Env P5_ROOT points at a different copy of the overnight-queue tree (the mutant runner)."""
import atexit
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

os.environ["TZ"] = "UTC"
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.abspath(os.path.join(HERE, "..", ".."))
Q = os.environ.get("P5_ROOT") or REAL
SC = os.path.join(Q, "scripts")
BASE = os.path.realpath(tempfile.mkdtemp(prefix="p5-supply-truth-"))
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("p5-supply-truth-") else None)
for k in ("OVN_SUPPLY_RUNWAY_BASIS", "OVN_BRIDGE_AUTOCLOSE", "OVN_ALREADY_DONE_STRICT"):
    os.environ.pop(k, None)
os.environ["OVN_DIR"] = os.path.join(BASE, "q")
os.environ["OVN_NOTIFY_STATE"] = os.path.join(BASE, "q", "state")
sys.path.insert(0, SC)
sys.path.insert(0, Q)

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
    open(path, "w").write(text)


# ------------------------------------------------------------------------------------------------ 1. filter
import ovn_supply_filter as F  # noqa: E402

PROG = "\n".join(
    ["- [x] done one"]
    + ["- [ ] [T2] doable %d" % i for i in range(19)]
    + ["- [ ] [CLAUDE] [T3] routed %d" % i for i in range(13)]
    + ["- [ ] [AUTO-SKIP after 3 cycles] [T3] stuck %d" % i for i in range(14)]
    + ["- [ ] [T1] HUMAN-ONLY set a key", "- [ ] BLOCKED ITEM waiting", "- [ ] (retired-vague) old", "- [ ] AUTO-SKIP and [CLAUDE] both", "  - [ ] indented is not an item", "ordinary human prose line"]
) + "\n"
c = F.count_text(PROG)
chk("filter: doable 19 / open 50", c["doable"] == 19 and c["open"] == 50, c)
chk("filter: excluded by reason claude=13 human-only=1 blocked=1 retired=1; first-match order puts the both-tag line under auto-skip (15)", c["excluded"] == {"claude": 13, "auto-skip": 15, "human-only": 1, "blocked": 1, "retired": 1}, c)
chk("filter: open == doable + sum(excluded)", c["open"] == c["doable"] + sum(c["excluded"].values()), c)
chk("filter: excluded_str largest first", F.excluded_str(c["excluded"]).startswith("auto-skip=15 claude=13"), F.excluded_str(c["excluded"]))
chk("filter: a bare 'human' word is not an exclusion", F.exclusion("- [ ] a human readable message") is None)
chk("filter: count_repo of a missing dir is None", F.count_repo(os.path.join(BASE, "nope")) is None)

REPOS = os.path.join(BASE, "q", "repos")
w(os.path.join(REPOS, "billwatch", "OVERNIGHT_PROGRESS.md"), PROG)
notify = load(os.path.join(SC, "ovn_notify.py"), "ovn_notify_p5")
chk("notify._doable == shared filter (19)", notify._doable(os.path.join(REPOS, "billwatch")) == 19, notify._doable(os.path.join(REPOS, "billwatch")))
chk("notify._doable: unreadable repo -> None", notify._doable(os.path.join(REPOS, "zzz")) is None)
fs = load(os.path.join(Q, "fleet_stats.py"), "fleet_stats_p5")
done, doable = fs.queue_counts(os.path.join(REPOS, "billwatch"))
chk("fleet_stats.queue_counts doable == notify doable (it used to include the [CLAUDE] lines: 32)", (done, doable) == (1, 19), (done, doable))
chk("fleet_stats.queue_detail carries the excluded breakdown", (fs.queue_detail(os.path.join(REPOS, "billwatch")) or {}).get("excluded", {}).get("claude") == 13)

# ------------------------------------------------------------------------------------------------ 2. report
sr = load(os.path.join(SC, "ovn_supply_report.py"), "ovn_supply_report_p5")
sys.modules.setdefault("ovn_supply_report", sr)
led = sys.modules.get("ovn_supply_ledger") or load(os.path.join(SC, "ovn_supply_ledger.py"), "ovn_supply_ledger")
sys.modules["ovn_supply_ledger"] = led
led.current_pullable = lambda root, names: {n: 52 for n in names}
led.compute_report = lambda rows, now, **kw: {"lanes": {"billwatch": {"pullable": 52, "windows": {"24h": {"items": 48, "covered_h": 24, "landed": 10}}}}}
os.makedirs(os.path.join(BASE, "q", "state"), exist_ok=True)
rep = sr.collect(now=1_700_000_000.0, root=os.path.join(BASE, "q"), state=os.path.join(BASE, "q", "state"), repos=["billwatch"], depths={"billwatch": 19})
r = rep["repos"]["billwatch"]
chk("report: doable 19 AND pullable 52 in the record", (r["doable"], r["pullable"]) == (19, 52), r)
chk("report: excluded counts by reason + open", r["excluded"].get("claude") == 13 and r["excluded"].get("auto-skip") == 15 and r["open"] == 50, r)
chk("report: pullable_not_in_progress 33, old keys kept", r["pullable_not_in_progress"] == 33 and all(k in r for k in ("ready", "needs_research", "burn_per_day", "runway_h", "starving", "sources", "causes")), r)
chk("report: default basis eligible (19 doable + 0 backlog at 2/h = 9.5h), pullable runway kept (26h)", (r["runway_h"], r["runway_pullable_h"], r["runway_basis"], r["eligible"]) == (9.5, 26.0, "eligible", 19), r)
os.environ["OVN_SUPPLY_RUNWAY_BASIS"] = "doable"
rdb = sr.collect(now=1_700_000_000.0, root=os.path.join(BASE, "q"), state=os.path.join(BASE, "q", "state"), repos=["billwatch"], depths={"billwatch": 19})["repos"]["billwatch"]
chk("report: OVN_SUPPLY_RUNWAY_BASIS=doable still available", rdb["runway_basis"] == "doable" and rdb["runway_h"] == 9.5, rdb)
os.environ.pop("OVN_SUPPLY_RUNWAY_BASIS")
os.environ["OVN_SUPPLY_RUNWAY_BASIS"] = "pullable"
rp = sr.collect(now=1_700_000_000.0, root=os.path.join(BASE, "q"), state=os.path.join(BASE, "q", "state"), repos=["billwatch"], depths={"billwatch": 19})["repos"]["billwatch"]
chk("report: OVN_SUPPLY_RUNWAY_BASIS=pullable restores the old runway", rp["runway_h"] == 26.0 and rp["runway_basis"] == "pullable", rp)
os.environ.pop("OVN_SUPPLY_RUNWAY_BASIS")
# FX-P5: runway from ELIGIBLE supply (doable + eligible backlog). queue_refill moves backlog into the progress file when doable < 15, so doable 0 + a full backlog is NOT starving
Q2 = os.path.join(BASE, "q2")
w(os.path.join(Q2, "repos", "fullbacklog", "OVERNIGHT_PROGRESS.md"), "- [x] done\n")
w(os.path.join(Q2, "backlog", "fullbacklog.md"), "".join("- [ ] [T2] src/f%d.py - item %d. VERIFY: `pytest -k f%d`\n" % (i, i, i) for i in range(40)))
w(os.path.join(Q2, "repos", "allheld", "OVERNIGHT_PROGRESS.md"), "- [x] done\n")
w(os.path.join(Q2, "backlog", "allheld.md"), "".join(("- [ ] [T2] [CLAUDE] src/h%d.py - held %d\n" if i % 2 else "- [ ] [T2] [AUTO-SKIP after 3 cycles] src/h%d.py - held %d\n") % (i, i) for i in range(40)))
led.current_pullable = lambda root, names: {n: 40 for n in names}
led.compute_report = lambda rows, now, **kw: {"lanes": {n: {"pullable": 40, "windows": {"24h": {"items": 48, "covered_h": 24, "landed": 5}}} for n in ("fullbacklog", "allheld")}}
os.makedirs(os.path.join(Q2, "state"), exist_ok=True)
r2 = sr.collect(now=1_700_000_000.0, root=Q2, state=os.path.join(Q2, "state"), repos=["fullbacklog", "allheld"], depths={"fullbacklog": 0, "allheld": 0})["repos"]
chk("report: doable 0 + 40 eligible backlog items is NOT starving (runway 20h)", r2["fullbacklog"]["eligible"] == 40 and r2["fullbacklog"]["starving"] is False and r2["fullbacklog"]["runway_h"] == 20.0, r2["fullbacklog"])
chk("report: 40 pullable but every backlog line [CLAUDE]/AUTO-SKIP IS starving (eligible 0, runway 0)", r2["allheld"]["pullable"] == 40 and r2["allheld"]["eligible"] == 0 and r2["allheld"]["starving"] is True and r2["allheld"]["runway_h"] == 0.0, r2["allheld"])
os.environ["OVN_SUPPLY_RUNWAY_BASIS"] = "pullable"
r2p = sr.collect(now=1_700_000_000.0, root=Q2, state=os.path.join(Q2, "state"), repos=["allheld"], depths={"allheld": 0})["repos"]["allheld"]
chk("report: basis=pullable keeps the old figure for the all-held repo (not starving)", r2p["starving"] is False and r2p["runway_basis"] == "pullable", r2p)
os.environ.pop("OVN_SUPPLY_RUNWAY_BASIS")
chk("filter.eligible_backlog dedupes against progress/done and drops held lines", len(F.eligible_backlog("- [ ] [T2] a - x\n- [ ] [T2] a - x\n- [ ] [T2] [CLAUDE] b - y\n- [ ] [T2] c - z\n", "- [ ] [T2] c - z\n")) == 1)

line = sr.repo_line("billwatch", dict(r, causes=[], last_source=None), 1_700_000_000.0)
chk("report line prints doable, pullable and the excluded counts", "doable 19, pullable 52 (excluded from doable: auto-skip=15 claude=13" in line, line)

# ------------------------------------------------------------------------------------------------ 3. bridge
B = load(os.path.join(Q, "claude_queue_bridge.py"), "claude_queue_bridge_p5")
rd = os.path.join(BASE, "clones")
gitrepo = os.path.join(rd, "billwatch")
os.makedirs(gitrepo)
env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def git(*a):
    return subprocess.run(["git", "-C", gitrepo] + list(a), capture_output=True, text=True, env=env)


git("init", "-q", "-b", "develop")
w(os.path.join(gitrepo, "web", "src", "pages", "__tests__", "SearchPage.test.ts"), 'it("renders link", () => {})\ntest("form hidden", () => {})\n')
w(os.path.join(gitrepo, "tests", "test_alert_filter.py"), "def test_build_alert_filter_conditions():\n    pass\n")
git("add", "-A")
git("commit", "-q", "-m", "x")
git("update-ref", "refs/remotes/origin/develop", "HEAD")

L1 = '- [ ] [CLAUDE] billwatch/ — [T2] billwatch-web/src/pages/SearchPage.test.ts — assert link. VERIFY: `npx vitest run src/pages/SearchPage.test.ts -t "form hidden"`. (cat:test) [feat:billwatch-20261101-search-link]'
L2 = '- [ ] [CLAUDE] billwatch/ — [T2] tests/test_alert_filter.py — add test. VERIFY: `pytest tests/test_alert_filter.py::test_build_alert_filter_conditions -v` (cat:test) [feat:billwatch-20261101-alert-filter]'
L3 = '- [ ] [CLAUDE] billwatch/ — [T2] tests/test_missing.py — add test. VERIFY: `pytest tests/test_missing.py::test_not_there_yet -v` (cat:test) [feat:billwatch-20261101-missing]'
L4 = '- [ ] [CLAUDE] billwatch/ — [T2] tests/test_alert_filter.py — add test. VERIFY: `pytest tests/test_alert_filter.py::test_build_alert_filter_conditions -v` (cat:test) [feat:billwatch-20261101-not-landed]'
L5 = '- [ ] [CLAUDE] billwatch/ — [T2] some line with no VERIFY at all [feat:billwatch-20261101-noverify]'
QUEUE = "# Claude queue\n## Section\n" + "\n".join([L1, L2, L3, L4, L5]) + "\n"
OUT = os.path.join(BASE, "outcomes.jsonl")
rows = [
    {"class": "landed", "repo": "billwatch", "feat_tag": "billwatch-20261101-search-link", "status": "pushed(tests:pass)"},
    {"class": "credit-only", "repo": "billwatch", "feat_tag": "billwatch-20261101-alert-filter"},
    {"class": "landed", "repo": "billwatch", "feat_tag": "billwatch-20261101-missing"},
    {"class": "noop", "repo": "billwatch", "feat_tag": "billwatch-20261101-not-landed"},
    {"class": "landed", "repo": "billwatch", "feat_tag": "billwatch-20261101-noverify"},
]
w(OUT, "\n".join(json.dumps(x) for x in rows) + "\nnot json at all\n")
chk("bridge: landed_tags reads landed + credit-only, skips noop and garbage", B.landed_tags(OUT) == {("billwatch", t) for t in ("billwatch-20261101-search-link", "billwatch-20261101-alert-filter", "billwatch-20261101-missing", "billwatch-20261101-noverify")}, B.landed_tags(OUT))
chk("bridge: named_test_ids parses ::name, -t title and test_ names", B.named_test_ids(L1) == ["form hidden"] and B.named_test_ids(L2)[0] == "test_build_alert_filter_conditions", (B.named_test_ids(L1), B.named_test_ids(L2)))


def run_ac(mode, queue_text, log):
    qp = os.path.join(BASE, "queue_%s.md" % mode)
    w(qp, queue_text)
    cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "autoclose", "--queue", qp, "--outcomes", OUT, "--repos-dir", rd, "--mode", mode, "--shadow-log", log, "--today", "2026-11-02"], capture_output=True, text=True)
    return qp, cp


log_sh = os.path.join(BASE, "state", "bridge_autoclose_shadow.log")
qp, cp = run_ac("shadow", QUEUE, log_sh)
chk("autoclose shadow: queue file untouched", open(qp).read() == QUEUE, cp.stderr)
slog = open(log_sh).read() if os.path.exists(log_sh) else ""
chk("autoclose shadow: logs the 2 closable lines (search-link by TAG although its path is wrong; alert-filter), not missing/not-landed/noverify", slog.count("would-close") == 2 and "search-link" in slog and "alert-filter" in slog and "missing" not in slog and "noverify" not in slog, slog)
chk("autoclose shadow: stderr says would-close=2", "would-close=2" in cp.stderr, cp.stderr)
qp, cp = run_ac("enforce", QUEUE, os.path.join(BASE, "state", "enf.log"))
t = open(qp).read().split("\n")
chk("autoclose enforce: L1+L2 flipped to [x] with the reason; L3 (test absent on develop), L4 (not landed), L5 (no VERIFY) stay open", t[2].startswith("- [x] ") and "auto-closed 2026-11-02" in t[2] and t[3].startswith("- [x] ") and t[4] == L3 and t[5] == L4 and t[6] == L5, t)
qp, cp = run_ac("off", QUEUE, os.path.join(BASE, "state", "off.log"))
chk("autoclose off: nothing happens", open(qp).read() == QUEUE and "off" in cp.stderr)
os.environ["OVN_BRIDGE_AUTOCLOSE"] = "bogus"
chk("autoclose: an unknown mode value falls back to shadow (never enforce by accident)", B.autoclose_mode() == "shadow" and B.autoclose_mode(None) == "shadow")
os.environ.pop("OVN_BRIDGE_AUTOCLOSE")
chk("autoclose: default mode is shadow", B.autoclose_mode() == "shadow")
tp = os.path.join(BASE, "tp.md")
w(tp, "## s\n- [x] [CLAUDE] billwatch/ — x [feat:abc-1]\n- [ ] [CLAUDE] billwatch/ — y [feat:abc-2]\n")
chk("bridge: closed_tags reads only checked lines", B.closed_tags(open(tp).read().split("\n")) == {"abc-1"})
# FX-P5: landed tags are keyed by (repo, tag): a tag landed for billwatch must not close/suppress a gitlark line
GL = '- [ ] [CLAUDE] gitlark/ — [T2] tests/test_alert_filter.py — add test. VERIFY: `pytest tests/test_alert_filter.py::test_build_alert_filter_conditions -v` (cat:test) [feat:billwatch-20261101-alert-filter]'
yes = lambda repo_dir, ref, needle: True
_n, _c = B.autoclose_lines([L2, GL], B.landed_tags(OUT), rd, "origin/develop", "2026-11-02", present=yes)
chk("autoclose: a tag landed for billwatch closes the billwatch line but NOT the gitlark line carrying the same tag", len(_c) == 1 and _c[0][1] == "billwatch" and _n[1] == GL and _n[0].startswith("- [x]"), (_c, _n))
w(os.path.join(BASE, "o_gl.jsonl"), json.dumps({"class": "landed", "repo": "gitlark", "feat_tag": "billwatch-20261101-alert-filter"}) + "\n")
_n, _c = B.autoclose_lines([L2, GL], B.landed_tags(os.path.join(BASE, "o_gl.jsonl")), rd, "origin/develop", "2026-11-02", present=yes)
chk("autoclose: ... and a row landed for gitlark closes only the gitlark line", len(_c) == 1 and _c[0][1] == "gitlark" and _n[0] == L2, (_c, _n))
AS2 = os.path.join(BASE, "autoskip2.tsv")
w(AS2, "gitlark\t[T2] reworded gitlark item with enough words to pass the guard [feat:billwatch-20261101-alert-filter]\n")
hq = os.path.join(BASE, "hq_repo.md")
w(hq, "## s\n" + L2 + "\n")
subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", hq, "--autoskip", AS2, "--outcomes", OUT, "--mode", "enforce", "--today", "2026-11-02"], capture_output=True, text=True)
chk("harvest enforce: a billwatch-landed tag does not suppress harvesting the same tag for gitlark", "reworded gitlark item" in open(hq).read(), open(hq).read()[-300:])

# harvest must not re-open a closed / landed feature, matched by tag
AUTOSKIP = os.path.join(BASE, "autoskip.tsv")
w(AUTOSKIP, "billwatch\t[T2] rewritten wording that shares no words with the queue line VERIFY: `pytest x::test_zz` [feat:billwatch-20261101-search-link]\nbillwatch\t[T2] a genuinely new item with its own words and tag [feat:billwatch-20261101-brand-new]\n")


def harvest(mode):
    qp = os.path.join(BASE, "hq_%s.md" % mode)
    w(qp, QUEUE.replace(L1, L1.replace("- [ ]", "- [x]", 1)))
    lg = os.path.join(BASE, "state", "h_%s.log" % mode)
    subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", qp, "--autoskip", AUTOSKIP, "--outcomes", OUT, "--mode", mode, "--shadow-log", lg, "--today", "2026-11-02"], capture_output=True, text=True)
    return open(qp).read(), (open(lg).read() if os.path.exists(lg) else "")


qt, lg = harvest("enforce")
chk("harvest enforce: a closed/landed feature is not re-opened under new wording; the new item is", "rewritten wording" not in qt and "brand-new" in qt, qt[-400:])
qt, lg = harvest("shadow")
chk("harvest shadow: still appends (old behaviour) but logs would-not-reharvest", "rewritten wording" in qt and "would-not-reharvest" in lg, (qt[-300:], lg))

# ------------------------------------------------------------------------------------------------ 4. already-done gate
G = load(os.path.join(SC, "ovn_already_done_gate.py"), "ovn_already_done_gate_p5")
xl = os.path.join(BASE, "xlite")
w(os.path.join(xl, "scripts", "settings", "input_remapper.gd"), 'const DEFAULT_BINDINGS = {\n\t"pause": "ui_pause",\n}\n')
w(os.path.join(xl, "tests", "test_input_remapper.gd"), "func test_no_pause_conflict():\n\tpass\n")
ITEM = '- [ ] [T3] scripts/settings/input_remapper.gd - Change DEFAULT_BINDINGS pause from ui_pause to Escape. VERIFY: `grep -q Escape scripts/settings/input_remapper.gd` (cat:bug)'
v, why = G.check(ITEM, xl, "scripts/settings/input_remapper.gd")
chk("gate: the xlite pause case (target still ui_pause, no 'Escape') is REFUSED string-missing", v == "REFUSE" and why.startswith("string-missing") and "Escape" in why, (v, why))
w(os.path.join(xl, "scripts", "settings", "input_remapper.gd"), 'const DEFAULT_BINDINGS = {\n\t"pause": "Escape",\n}\n')
v, why = G.check(ITEM, xl, "scripts/settings/input_remapper.gd")
chk("gate: once Escape is in the target it passes", v == "OK" and "present" in why, (v, why))
v, why = G.check(ITEM, xl, "tests/test_input_remapper.gd")
chk("gate: plan file (the test) differs from the item's named file -> file-mismatch", v == "REFUSE" and why.startswith("file-mismatch"), (v, why))
v, why = G.check("- [ ] [T3] scripts/settings/input_remapper.gd - Change pause to Escape", xl, "scripts/settings/input_remapper.gd")
chk("gate: item without a VERIFY clause is REFUSED no-verify", v == "REFUSE" and why.startswith("no-verify"), (v, why))
v, why = G.check(ITEM.replace("scripts/settings/input_remapper.gd -", "scripts/settings/gone.gd -"), xl, "scripts/settings/gone.gd")
chk("gate: target file missing -> target-missing", v == "REFUSE" and why.startswith("target-missing"), (v, why))
v, why = G.check('- [ ] [T2] src/geocoder.py - Add an api_budget counter `api_budget` to the geocoder. VERIFY: `pytest -k budget`', xl, "src/geocoder.py")
chk("gate: backticked target string on a missing file also refuses (billwatch geocoder case)", v == "REFUSE", (v, why))
w(os.path.join(xl, "src", "geocoder.py"), "def geocode():\n    pass\n")
v, why = G.check('- [ ] [T2] src/geocoder.py - Add an api_budget counter `api_budget` to the geocoder. VERIFY: `pytest -k budget`', xl, "src/geocoder.py")
chk("gate: ... and refuses string-missing when the file exists without api_budget", v == "REFUSE" and why.startswith("string-missing"), (v, why))
prog = os.path.join(BASE, "prog.md")
w(prog, "- [x] a\n" + ITEM + "\n")
cp = subprocess.run([sys.executable, os.path.join(SC, "ovn_already_done_gate.py"), prog, "2", xl, "scripts/settings/input_remapper.gd"], capture_output=True, text=True)
chk("gate CLI prints 'OK ...' for the fixed target", cp.stdout.startswith("OK "), cp.stdout + cp.stderr)
chk("gate: an item with no leading path and a VERIFY is not refused (nothing to check)", G.check("- [ ] [T3] Tidy the thing. VERIFY: `true`", xl, "x.py")[0] == "OK")
runner = open(os.path.join(Q, "run_overnight.sh")).read()
chk("run_overnight.sh wires the gate behind OVN_ALREADY_DONE_STRICT (default shadow)", 'OVN_ALREADY_DONE_STRICT:-shadow' in runner and "ovn_already_done_gate.py" in runner)
bsh = open(os.path.join(Q, "claude_queue_bridge.sh")).read()
chk("bridge.sh wires autoclose behind OVN_BRIDGE_AUTOCLOSE (default shadow)", 'OVN_BRIDGE_AUTOCLOSE:-shadow' in bsh and " autoclose " in bsh)

# ------------------------------------------------------------------------------------------------ 5. mutants
MUTANTS = [
    ("filter ignores [CLAUDE]", "scripts/ovn_supply_filter.py", r'("claude", re.compile(r"\[CLAUDE\]", re.I))', r'("claude", re.compile(r"NEVER_MATCHES_CLAUDE"))'),
    ("notify keeps its own filter", "scripts/ovn_notify.py", 'return None if c is None else c["doable"]', 'return None if c is None else c["open"]'),
    ("fleet_stats counts [CLAUDE] as doable again", "fleet_stats.py", "c = ovn_supply_filter.count_text(text)", 'c = {"open": 0, "doable": sum(1 for l in text.split("\\n") if l.startswith("- [ ]") and "AUTO-SKIP" not in l), "excluded": {}}'),
    ("report runway from pullable", "scripts/ovn_supply_report.py", 'want = want if want in ("pullable", "doable", "eligible") else "eligible"', 'want = "pullable"'),
    ("report runway from doable only (false starving)", "scripts/ovn_supply_report.py", 'want = want if want in ("pullable", "doable", "eligible") else "eligible"', 'want = "doable"'),
    ("eligible backlog no longer dedupes vs progress", "scripts/ovn_supply_filter.py", "if k in queued or k in seen:", "if False:"),
    ("eligible backlog counts held lines", "scripts/ovn_supply_filter.py", "if not _OPEN_T.match(l) or exclusion(l):\n            continue\n        if elig is not None:", "if not _OPEN_T.match(l):\n            continue\n        if False:"),
    ("landed_tags ignores the repo field", "claude_queue_bridge.py", 'tags.add((str(r.get("repo") or ""), str(r["feat_tag"])))', 'tags.add(("", str(r["feat_tag"])))'),
    ("report drops excluded counts", "scripts/ovn_supply_report.py", '"excluded": {} if det is None else det["excluded"],', '"excluded": {},'),
    ("report line omits the excluded counts", "scripts/ovn_supply_report.py", '" (excluded from doable: %s)" % exc if exc else ""', '""'),
    ("autoclose matches nothing by tag", "claude_queue_bridge.py", "if repo and _tag_landed(tags, repo, tag):", "if False:"),
    ("autoclose skips the test-presence proof", "claude_queue_bridge.py", "ok, why = verify_on_develop(os.path.join(repos_dir, repo), ref, ln, present)", 'ok, why = True, "mutant"'),
    ("autoclose treats a line with no named test as proven", "claude_queue_bridge.py", 'return False, "no named test id in VERIFY"', 'return True, "no named test id in VERIFY"'),
    ("autoclose shadow enforces", "claude_queue_bridge.py", 'if mode == "enforce" and closed:', "if closed:"),
    ("autoclose default mode enforce", "claude_queue_bridge.py", 'or "shadow").strip().lower()', 'or "enforce").strip().lower()'),
    ("harvest re-opens closed features in enforce", "claude_queue_bridge.py", '            if mode == "enforce":\n                continue\n        existing_sigs.add', '            if False:\n                continue\n        existing_sigs.add'),
    ("gate skips the no-VERIFY refusal", "scripts/ovn_already_done_gate.py", "    if not has_verify(line):", "    if False:"),
    ("gate skips the string check", "scripts/ovn_already_done_gate.py", "    missing = [s for s in strings if s not in text]", "    missing = []"),
    ("gate skips the file-mismatch check", "scripts/ovn_already_done_gate.py", "    if plan_file and not _same_file(tgt, plan_file):", "    if False:"),
    ("runner gate default enforce", "run_overnight.sh", "OVN_ALREADY_DONE_STRICT:-shadow", "OVN_ALREADY_DONE_STRICT:-enforce"),
]


def mutants():
    bad = 0
    for name, rel, old, new in MUTANTS:
        mq = os.path.join(BASE, "mut")
        shutil.rmtree(mq, ignore_errors=True)
        os.makedirs(os.path.join(mq, "scripts"))
        for f in os.listdir(os.path.join(Q, "scripts")):
            if f.endswith(".py"):
                shutil.copy(os.path.join(Q, "scripts", f), os.path.join(mq, "scripts", f))
        for f in ("fleet_stats.py", "claude_queue_bridge.py", "claude_queue_bridge.sh", "run_overnight.sh"):
            shutil.copy(os.path.join(Q, f), os.path.join(mq, f))
        p = os.path.join(mq, rel)
        s = open(p).read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        if rel == "claude_queue_bridge.py" and name == "autoclose default mode enforce":
            pass
        open(p, "w").write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, P5_ROOT=mq, P5_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


if os.environ.get("P5_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
print("test_p5_supply_truth: %d passed, %d failed" % (PASSES[0], len(FAILS)))
sys.exit(1 if FAILS else 0)
