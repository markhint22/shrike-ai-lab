#!/usr/bin/env python3
"""Y2 tests (2026-11-04): bridge harvest ledger + precise done-check + shadow dedupe + stale cron header. Hermetic temp dirs, no box, no network, no ntfy, dates injected, TZ pinned.

  1. body_key: stable across checkbox / [CLAUDE] repo/ prefix / [feat:] tag / trailing (cat:..) metadata; different text = different key
  2. harvest ledger: a harvested line is never appended again even when the queue file is wiped; a re-tagged / re-metadata'd re-surfacing of a ticked or archived line is NOT harvested
     (the old 12-word+feat-tag signature missed it); an unrelated new line still is
  3. done-check: default ON (enforce); `on` alias; a pure creation item whose named class/test is DEFINED in code is skipped + logged ONCE per (repo, line, tag, day); a creation item that also says
     modify/replace is never judged done; markdown-only / queue-text-only mentions never count; mode off / unknown never enforce
  4. autoclose shadow dedupe survives a shifting line number; OVN_BRIDGE_AUTOCLOSE_REQUIRE_ITEM=on makes enforce close only the line that itself landed
  5. bridge.sh wiring (default done-check on, ledger args); cron.txt header no longer says heartbeat/pingpong/forecast are NOT installed
  6. MUTANTS: copies of the sources with one substitution each; at least one check must fail on every mutant
Env Y2_ROOT points at a different copy of the overnight-queue tree (the mutant runner)."""
import importlib.util
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
Q = os.environ.get("Y2_ROOT") or REAL
BASE = os.path.realpath(tempfile.mkdtemp(prefix="y2-bridge-"))
for k in ("OVN_BRIDGE_AUTOCLOSE", "OVN_HARVEST_DONE_CHECK", "OVN_BRIDGE_AUTOCLOSE_REQUIRE_ITEM", "OVN_HARVEST_LEDGER_MODE"):
    os.environ.pop(k, None)
spec = importlib.util.spec_from_file_location("cqb_y2", os.path.join(Q, "claude_queue_bridge.py"))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

FAILS = []
PASSES = [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


def w(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def rd(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""


GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", HOME=BASE)


def g(d, *a):
    return subprocess.run(["git", "-C", d] + list(a), capture_output=True, text=True, env=GENV).stdout


# ------------------------------------------------------------------------------------------------ fixture clone (billwatch) with code + markdown
clones = os.path.join(BASE, "repos")
bw = os.path.join(clones, "billwatch")
os.makedirs(bw)
g(bw, "init", "-q")
w(os.path.join(bw, "app", "broker.py"), "class SubscriberLimitError(Exception):\n    pass\n")
w(os.path.join(bw, "tests", "test_existing.py"), "def test_already_there():\n    assert True\n")
w(os.path.join(bw, "OVERNIGHT_PROGRESS.md"), "- [ ] Add `class OnlyInMarkdownError(Exception)`\n- Add `test_only_in_md` here\n")
w(os.path.join(bw, "CLAUDE_QUEUE.md"), "Add `test_only_in_queue_text`\n")
g(bw, "add", "-A")
g(bw, "commit", "-q", "-m", "x")

T_DONE = "[T2] app/broker.py — Add `class SubscriberLimitError(Exception)` to the broker module. VERIFY: `python -c \"import app.broker\"`. (cat:impl; multifile:no) [feat:billwatch-20261104-limit]"
T_MODIFY = "[T2] app/broker.py — Add `class SubscriberLimitError(Exception)` and modify `Broker.subscribe` to raise it. VERIFY: `pytest tests/test_x.py`. (cat:impl) [feat:billwatch-20261104-limit2]"
T_MD = "[T2] app/other.py — Add `class OnlyInMarkdownError(Exception)` to the module. VERIFY: `python -c 1`. (cat:impl) [feat:billwatch-20261104-md]"
T_TEST_DONE = "[T3] tests/test_existing.py — Add `test_already_there` asserting true. VERIFY: `pytest tests/test_existing.py::test_already_there -v`. (cat:test) [feat:billwatch-20261104-t1]"
T_QTXT = "[T3] tests/test_q.py — Add `test_only_in_queue_text` asserting stuff. VERIFY: `pytest tests/test_q.py -v`. (cat:test) [feat:billwatch-20261104-t2]"
T_NEW = "[T1] app/new_thing.py — Add `class BrandNewThing` with a frobnicate method that does a real job. VERIFY: `pytest tests/test_new.py`. (cat:impl) [feat:billwatch-20261104-new]"

# ------------------------------------------------------------------------------------------------ 1. body_key
L_OPEN = "- [ ] [CLAUDE] billwatch/ — [T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py`. (cat:impl; multifile:no) [feat:billwatch-20261104-aaa]"
L_TICK = "- [x] [CLAUDE] billwatch/ — [T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py`. (cat:impl; multifile:no) [feat:billwatch-20261104-aaa] (auto-closed 2026-11-04: landed)"
RAW = "[T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py`. (cat:test; multifile:yes) [feat:billwatch-20261105-zzz]"
k0 = B.body_key("billwatch", L_OPEN)
chk("body_key: same for open/ticked(auto-closed)/raw task with another feat tag + metadata", k0 == B.body_key("billwatch", L_TICK) == B.body_key("billwatch", RAW), (k0, B.body_key("billwatch", L_TICK), B.body_key("billwatch", RAW)))
chk("body_key: different text or different repo = different key", k0 != B.body_key("billwatch", RAW.replace("exact thing", "other thing")) and k0 != B.body_key("gitlark", RAW))
chk("body_key: a difference AFTER the first 12 words is still a different key (task_sig would collapse them)", B.body_key("billwatch", RAW.replace("in full.", "in full with extra tail words.")) != k0)

# ------------------------------------------------------------------------------------------------ 2. harvest ledger


def harvest(tag, queue_text, tasks, archive_text=None, ledger=True, lmode="enforce"):
    d = os.path.join(BASE, "h_" + tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    q = os.path.join(d, "q.md")
    w(q, queue_text)
    sk = os.path.join(d, "skip.tsv")
    w(sk, "".join("billwatch\t%s\n" % t for t in tasks))
    args = [sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-04"]
    if archive_text is not None:
        a = os.path.join(d, "done.md")
        w(a, archive_text)
        args += ["--archive", a]
    if ledger:
        args += ["--ledger", os.path.join(d, "state", "harvest_ledger.tsv"), "--ledger-log", os.path.join(d, "state", "ledger_skips.log")]
        if lmode:
            args += ["--ledger-mode", lmode]
    cp = subprocess.run(args, capture_output=True, text=True, env=GENV)
    return d, rd(q), cp


TASK_A = "[T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py`. (cat:impl; multifile:no) [feat:billwatch-20261104-aaa]"
d, qt, cp = harvest("l1", "# q\n", [TASK_A])
LP = os.path.join(d, "state", "harvest_ledger.tsv")
chk("ledger: first harvest appends the line and records a harvested key", qt.count("[CLAUDE]") == 1 and "harvested" in rd(LP), (qt, cp.stderr))
# wipe the queue completely (line ticked + archived + the archive rewritten away): only the ledger remembers
q = os.path.join(d, "q.md")
w(q, "# q\n")
for _ in range(2):
    cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", q, "--autoskip", os.path.join(d, "skip.tsv"), "--today", "2026-11-04", "--ledger", LP,
                         "--ledger-log", os.path.join(d, "state", "ledger_skips.log"), "--ledger-mode", "enforce"], capture_output=True, text=True, env=GENV)
chk("ledger: a harvested key is never re-harvested after the line is gone from queue AND archive", rd(q).count("[CLAUDE]") == 0 and "nothing new" in cp.stderr, (rd(q), cp.stderr))
chk("ledger: the skip is logged once per (day, key)", rd(os.path.join(d, "state", "ledger_skips.log")).count("ledger-skip") == 1, rd(os.path.join(d, "state", "ledger_skips.log")))

RESURFACED = "[T1] app/a.py — Do the exact thing described here in full. VERIFY: `pytest tests/test_a.py`. (cat:test; multifile:yes) [feat:billwatch-20261105-different-round]"
d, qt, cp = harvest("l2", "# q\n## s\n" + L_TICK + "\n", [RESURFACED])
chk("ledger: a TICKED line re-surfaced with another feat tag + metadata is not harvested (task_sig would differ)", qt.count("- [ ]") == 0, qt)
d, qt, cp = harvest("l3", "# q\n", [RESURFACED], archive_text="<!-- archived -->\n" + L_TICK + "\n")
chk("ledger: an ARCHIVED line re-surfaced with another feat tag is not harvested", qt.count("- [ ]") == 0, qt)
d, qt, cp = harvest("l4", "# q\n", [RESURFACED, "[T1] app/b.py — A completely different task that is genuinely new for this repo today. VERIFY: `pytest tests/test_b.py`."])
chk("ledger: an unrelated new line is still harvested (the re-surfaced one is not: only archive-less queue is empty here)", qt.count("- [ ]") == 2, qt)
# D1 (Y2 r3): harvest -> tick -> N passes: the key moves harvested -> closed ONCE; latest row wins so the ledger does not grow by one `closed` row per pass
d, qt, cp = harvest("l7", "# q\n", [TASK_A])
LP7, Q7 = os.path.join(d, "state", "harvest_ledger.tsv"), os.path.join(d, "q.md")
w(Q7, rd(Q7).replace("- [ ] [CLAUDE]", "- [x] [CLAUDE]"))
for _ in range(3):
    cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", Q7, "--autoskip", os.path.join(d, "skip.tsv"), "--today", "2026-11-04", "--ledger", LP7, "--ledger-mode", "enforce"],
                        capture_output=True, text=True, env=GENV)
rows7 = rd(LP7).splitlines()
chk("ledger idempotent (D1): harvest, tick, 3 passes -> exactly 1 harvested + 1 closed row (no growth per pass)", len(rows7) == 2 and sum("\tclosed\t" in r for r in rows7) == 1, rows7)
open(os.path.join(d, "state", "l.tsv"), "w").write("k1\tharvested\tr\t\td\nk1\tclosed\tr\t\td\nk2\tclosed\tr\t\td\nk2\tclosed\tr\t\td\n")
chk("load_ledger: latest row wins (harvested -> closed)", B.load_ledger(os.path.join(d, "state", "l.tsv")) == {"k1": "closed", "k2": "closed"})
d, qt, cp = harvest("l6", "# q\n## s\n" + L_TICK + "\n", [RESURFACED], lmode=None)
chk("ledger default is SHADOW (Y2 r3 D4): the re-surfaced ticked line is harvested again and the would-skip is only logged", qt.count("- [ ]") == 1 and "SHADOW ledger-skip" in rd(os.path.join(d, "state", "ledger_skips.log")), (qt, cp.stderr))
chk("ledger_mode(): default shadow, on=enforce, off, unknown=shadow", (B.ledger_mode(None), B.ledger_mode("on"), B.ledger_mode("off"), B.ledger_mode("bogus")) == ("shadow", "enforce", "off", "shadow"))
chk("ledger: harvest without --ledger keeps working (arg optional)", harvest("l5", "# q\n", [TASK_A], ledger=False)[1].count("[CLAUDE]") == 1)

# ------------------------------------------------------------------------------------------------ 3. done-check
TASKS = [T_DONE, T_MODIFY, T_MD, T_TEST_DONE, T_QTXT, T_NEW]


def run_done(tag, mode, env=None):
    d = os.path.join(BASE, "dc_" + tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    q = os.path.join(d, "q.md")
    w(q, "# q\n")
    sk = os.path.join(d, "skip.tsv")
    w(sk, "".join("billwatch\t%s\n" % t for t in TASKS))
    dl = os.path.join(d, "state", "harvest_skipped_done.log")
    args = [sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "harvest", "--queue", q, "--autoskip", sk, "--today", "2026-11-04", "--repos-dir", clones, "--done-ref", "HEAD", "--done-log", dl]
    if mode is not None:
        args += ["--done-mode", mode]
    cp = subprocess.run(args, capture_output=True, text=True, env=dict(GENV, **(env or {})))
    return rd(q), rd(dl), cp, d, args


qt, dl, cp, d, args = run_done("default", None)
chk("done-check default is SHADOW (Y2 r3 D4): all six harvested, the two already-defined items only logged as SHADOW", qt.count("[CLAUDE]") == 6 and dl.count("SHADOW") == 2 and "ENFORCED" not in dl, (qt, dl, cp.stderr))
qt, dl, cp, d, args = run_done("enf", "enforce")
chk("done-check enforce: the two already-defined items are skipped, the four others harvested", qt.count("[CLAUDE]") == 4 and "to the broker module" not in qt and "test_already_there" not in qt, (qt, cp.stderr))
chk("done-check: modify-and-add, markdown-only class, queue-text-only test and new class are NOT judged done", "modify `Broker.subscribe`" in qt and "OnlyInMarkdownError" in qt and "test_only_in_queue_text" in qt and "BrandNewThing" in qt, qt)
chk("done-check: log rows are ENFORCED, one per skipped line, keyed per (repo, line, tag)", dl.count("would-skip-done") == 2 and dl.count("ENFORCED") == 2 and "tag=billwatch-20261104-limit " in dl and " k=" in dl, dl)
subprocess.run(args, capture_output=True, text=True, env=GENV)
chk("done-check: a second pass the same day adds no log rows", rd(os.path.join(d, "state", "harvest_skipped_done.log")).count("would-skip-done") == 2, rd(os.path.join(d, "state", "harvest_skipped_done.log")))
qt2 = run_done("on", "on")[0]
chk("done-check: `on` is an alias of enforce", qt2.count("[CLAUDE]") == 4)
qt3, dl3 = run_done("shadow", "shadow")[:2]
chk("done-check shadow: everything harvested, rows tagged SHADOW", qt3.count("[CLAUDE]") == 6 and dl3.count("SHADOW") == 2, (qt3, dl3))
qt4, dl4 = run_done("off", "off")[:2]
chk("done-check off: nothing checked", qt4.count("[CLAUDE]") == 6 and dl4 == "")
qt5, dl5 = run_done("bogus", "bogus")[:2]
chk("done-check: unknown mode falls back to shadow (never enforces by accident)", qt5.count("[CLAUDE]") == 6 and "SHADOW" in dl5)
qt6 = run_done("env", None, env={"OVN_HARVEST_DONE_CHECK": "shadow"})[0]
chk("done-check: env OVN_HARVEST_DONE_CHECK=shadow gives shadow", qt6.count("[CLAUDE]") == 6)
qt7 = run_done("env2", None, env={"OVN_HARVEST_DONE_CHECK": "enforce"})[0]
chk("done-check: env OVN_HARVEST_DONE_CHECK=enforce opts in", qt7.count("[CLAUDE]") == 4)
chk("named_new_defs: pure creation yes; modify verb no; non-creation no", B.named_new_defs(T_DONE) == ["SubscriberLimitError"] and B.named_new_defs(T_MODIFY) == [] and B.named_new_defs("Fix `class X` handling") == [])

# ------------------------------------------------------------------------------------------------ 4. autoclose shadow dedupe with shifting line numbers + require-item
LA = '- [ ] [CLAUDE] billwatch/ — [T3] tests/test_existing.py — add test. VERIFY: `pytest tests/test_existing.py::test_already_there -v`. (cat:test) [feat:billwatch-20261104-t1]'
LB = LA.replace("add test.", "add a sibling test.").replace("t1]", "t3]")
OUT = os.path.join(BASE, "outcomes.jsonl")
w(OUT, "\n".join(json.dumps(x) for x in [
    {"class": "landed", "repo": "billwatch", "feat_tag": "billwatch-20261104-t1", "item_line_hash": B.line_key(LA)},
    {"class": "landed", "repo": "billwatch", "feat_tag": "billwatch-20261104-t3", "item_line_hash": "0" * 32}]) + "\n")
LOG = os.path.join(BASE, "state", "ac_shadow.log")


def run_ac(mode, text, log=LOG, env=None):
    qp = os.path.join(BASE, "acq_%s.md" % mode)
    w(qp, text)
    cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "autoclose", "--queue", qp, "--outcomes", OUT, "--repos-dir", clones, "--ref", "HEAD", "--mode", mode, "--shadow-log", log,
                         "--today", "2026-11-04"], capture_output=True, text=True, env=dict(GENV, **(env or {})))
    return qp, cp


run_ac("shadow", "# q\n## s\n" + LA + "\n")
run_ac("shadow", "# q\n## s\n\n\n\n" + LA + "\n")          # same line, line number shifted
run_ac("shadow", "# q\n## s\n- [x] other\n" + LA + "\n")  # shifted again
slog = rd(LOG)
chk("autoclose shadow: the same line on three passes (line number shifting) leaves ONE row", slog.count("would-close") == 1, slog)
LOG2 = os.path.join(BASE, "state", "ac_shadow2.log")
run_ac("shadow", "# q\n## s\n" + LA + "\n" + LB + "\n", LOG2)
chk("autoclose shadow: two different lines of different tags get one row each, tagged item/feature", rd(LOG2).count("would-close") == 2 and "landing=item" in rd(LOG2) and "landing=feature" in rd(LOG2), rd(LOG2))
qp, cp = run_ac("enforce", "# q\n## s\n" + LA + "\n" + LB + "\n", os.path.join(BASE, "state", "e1.log"))
chk("autoclose enforce default: closes both (feature-level landing, old behaviour kept)", rd(qp).count("- [x]") == 2, rd(qp))
qp, cp = run_ac("enforce", "# q\n## s\n" + LA + "\n" + LB + "\n", os.path.join(BASE, "state", "e2.log"), {"OVN_BRIDGE_AUTOCLOSE_REQUIRE_ITEM": "on"})
chk("autoclose enforce + REQUIRE_ITEM=on: only the line that itself landed is closed", rd(qp).count("- [x]") == 1 and LB in rd(qp), rd(qp))

# ------------------------------------------------------------------------------------------------ 5. wiring + stale cron header
bsh = rd(os.path.join(Q, "claude_queue_bridge.sh"))
chk("bridge.sh: done-check AND ledger-skip default shadow (opt-in enforce), ledger + ledger-log passed to harvest", "OVN_HARVEST_DONE_CHECK:-shadow" in bsh and "OVN_HARVEST_LEDGER_MODE:-shadow" in bsh and "--ledger-mode" in bsh and "--ledger " in bsh and "harvest_ledger.tsv" in bsh and "--ledger-log" in bsh)
cron = rd(os.path.join(Q, "scripts", "cron.txt"))
head = "\n".join(cron.split("\n")[:5])
chk("cron.txt header: not everything is NOT INSTALLED; pingpong, forecast and heartbeat named as installed",
    "NOT INSTALLED (the integrator" not in head and "pingpong" in head.lower() and "forecast" in head.lower() and "heartbeat" in head.lower() and "ARE installed in the box crontab" in head, head)
chk("cron.txt: the pingpong, forecast and heartbeat section headers say INSTALLED", "INSTALLED on the box since 2026-11-01 (shadow mode" in cron and "forecast line IS INSTALLED" in cron and "heartbeat line IS INSTALLED" in cron)
for stale in ("Shipped OFF (not installed): enable by removing", "supply engine (PROPOSED, NOT INSTALLED;", "notify quality (PROPOSED, NOT INSTALLED"):
    chk("cron.txt: stale phrase gone: " + stale[:40], stale not in cron)

# ------------------------------------------------------------------------------------------------ 7. Y2 r4 N1: body_key peels only TRAILING annotation groups (no mid-text cuts)
KB = lambda t: B.body_key("billwatch", t)
# the 13 probes of review r4 (scratchpad/findings5/r4_probe.py) + the gettext shape: every pair is two DIFFERENT tasks that differ only AFTER the marker word/shape, so they must have distinct keys
N1_PAIRS = [
    ("status DONE, comma", "Transition the order to status DONE, then emit OrderClosed in src/orders.py. VERIFY: `pytest -k a`", "Transition the order to status DONE, then log metrics in src/stats.py. VERIFY: `pytest -k b`"),
    ("status DONE:", "Set job.state to DONE: update the cache in api/jobs.py and retry", "Set job.state to DONE: purge the queue in api/queue.py and notify"),
    ("- TRIAGE mid", "Add a - TRIAGE column to the tickets table in models/ticket.py with default none", "Add a - TRIAGE badge to the tickets list in views/List.vue with colour"),
    ("(retired mid, ends with paren)", "Remove the (retired flag) handling from parser/a.py when value is None (see line 12)", "Remove the (retired flag) handling from lexer/b.py when value is empty (see line 40)"),
    ("(auto-closed mid)", "Rename (auto-closed state) enum in a.py to Closed and fix imports (all callers)", "Rename (auto-closed state) enum in b.py to Closed and fix imports (all views)"),
    ("ALREADY DONE mid", "Return ALREADY DONE, if the user exists in services/a.py", "Return ALREADY DONE, if the token exists in services/b.py"),
    ("html comment in task", "Strip <!-- markers --> from templates/a.html output in render()", "Strip <!-- markers --> from templates/b.html output in render()"),
    ("coverage tail", "Add coverage for parse() in a.py (coverage: branch A) [feat:t1]", "Add coverage for parse() in b.py (coverage: branch A) [feat:t1]"),
    ("cat then done word", "Handle empty list (cat:impl) DONE: flag in a.py", "Handle empty list (cat:impl) DONE: flag in b.py"),
    ("_( gettext", "Wrap labels in _(HOME-TITLE)_ style keys in a.vue", "Wrap labels in _(HOME-TITLE)_ style keys in b.vue"),
    ("gettext key at the END of the line", "Rename the key _(HOME-TITLE)_", "Rename the key _(HOME-SUBTITLE)_"),
    ("html comment at the END of the task", "Remove the <!-- foo -->", "Remove the <!-- bar -->"),
    ("(2026-...) date paren mid", "Bump TTL (2026-12-01) in a.py", "Bump TTL (2026-12-01) in b.py"),
    ("STALE TICKET prose", "Ensure the STALE TICKET, cleanup job in a.py deletes rows", "Ensure the STALE TICKET, cleanup job in b.py deletes rows"),
    ("DONE (paren) mid", "Mark the row DONE (see docs) when it ships in a.py", "Mark the row DONE (see docs) when it ships in b.py"),
    ("TRIAGE with a date, mid", "Add a - TRIAGE 2026-10-01 column to a.py", "Add a - TRIAGE 2026-10-01 column to b.py"),
    ("(done D) mid-line", "Compute (done 2026-01-01 ratio) for a.py tickets", "Compute (done 2026-01-01 ratio) for b.py tickets"),
]
for nm, a_, c_ in N1_PAIRS:
    chk("N1 distinct keys: " + nm, KB(a_) != KB(c_), (KB(a_), a_))
    chk("N1 distinct keys even after a closing annotation: " + nm, KB(a_ + " (cat:impl) [feat:x-1]") != KB(c_ + " (cat:impl) [feat:x-1]"))
chk("N1 probe 8 (feat tag only): same text with another [feat:] tag IS the same task (re-tag), a different task with the same tag is not", KB("[feat:x] Add foo to a.py") == KB("[feat:y] Add foo to a.py") and KB("[feat:x] Add foo to a.py") != KB("[feat:x] Add foo to b.py"))
chk("N1 a tail annotation never swallows prose BEFORE it: the retired suffix of line A does not equal task B", KB("Remove the (retired flag) handling from parser/a.py (see line 12) (retired 2026-10-01: resolved)") == KB("Remove the (retired flag) handling from parser/a.py (see line 12)") != KB("Remove the (retired flag) handling from lexer/b.py (see line 12)"))
# real closing annotations still normalise to the untagged line
N1_BASE = "[T1] backend/app/x.py \u2014 Add `class FooBar` with method baz. VERIFY: `pytest tests/test_x.py::test_foo` passes"
N1_TAILS = ["", " (cat:impl; multifile:no)", " [feat:abc-1]", " (cat:impl; multifile:no) [feat:abc-1]", " (coverage:schema-x)",
            " (auto-closed 2026-11-04: [feat:abc-1] landed, all 1 named test id(s) present on origin/claude/feature; landing=item)",
            " <!-- closed 2026-10-23 by claude: done -->", " <!-- landed 2026-09-27 (repo claude/feature e9e360a) -->", " <!-- VERIFIED 2026-09-30 (Claude): already wrapped (x) -->",
            " \u2014 ALREADY DONE (verified 2026-10-01)", " ALREADY DONE (re-verified 2026-09-10).", " \u2014 **ALREADY DONE, stale item (verified 2026-09-05):** a prior pass had it",
            " STALE TICKET, no action (verified 2026-09-08) - same issue", " **STALE TICKET** \u2014 gone", " \u2014 TRIAGE 2026-10-12 DONE: x.py:3 defines it", " \u2014 **TRIAGE 2026-10-01**: stale",
            " _(ALREADY-SATISFIED 2026-10-01: exists)_", " _(duplicate of an already-checked-off item (see above): same)_", " _(RESOLVED 2026-09-15: ALREADY-SATISFIED \u2014 a `(x,` with a comma) \u2014 not a gap.)_",
            " (done 2026-09-08: claude fixed)", " (retired 2026-10-01: resolved via Claude, see shared/CLAUDE_QUEUE.md)", " DONE (shrike-monitor @ 9b99999, verified 2026-10-01).", " \u2705 DONE", " \u2014 DONE",
            " **DONE** (2026-10-01)", " (REOPENED 2026-10-02)", " (REOPENED 2026-10-02: tick had no landing)", " (2026-10-01)", " SKIPPED (2026-10-01)", " SKIPPED (verified 2026-09-08) - out of scope",
            " (cat:impl) [feat:abc-1] (auto-closed 2026-11-04: [feat:abc-1] landed, all 1 named test id(s) present on x; landing=item) (retired 2026-11-05: resolved) <!-- closed 2026-11-06: done -->",
            " (cat:impl) \u2705 DONE (2026-10-01) [feat:abc-1]", " <!-- STOPPED 2026-09-27 (repo): fork --> \u2014 TRIAGE 2026-10-12 DONE: backend/x.py:31 defines it; more (text)"]
for tl in N1_TAILS:
    for pre in ("- [x] [CLAUDE] billwatch/ \u2014 ", "- [ ] [CLAUDE] billwatch/ \u2014 ", ""):
        chk("N1 closing annotation still normalised: %r" % (tl[:60] or "(none)"), KB(pre + N1_BASE + tl) == KB(N1_BASE), (pre, tl))
        break
for pre in ("- [x] [CLAUDE] billwatch/ \u2014 ", "- [ ] [CLAUDE] billwatch/ \u2014 "):
    chk("N1 closing annotation + checkbox/prefix variants: ticked+reopened line == untagged line", KB(pre + N1_BASE + " (cat:impl) (REOPENED 2026-10-02)") == KB(N1_BASE))
# measured on the real queue + archive: re-tag match rate (the same measure as test_y2_fixes r2/2)
_CATRE = __import__("re").compile(r"\(cat:[^)]*\)")
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
            raw_ = B.REPO_PREFIX_RE.sub("", __import__("re").sub(r"^\[CLAUDE\]\s*", "", m_.group(1)[:c_.end()]))
            n_ += 1
            ok_ += B.body_key(repo_, ln_) == B.body_key(repo_, _CATRE.sub("(cat:test; multifile:yes)", raw_) + " [feat:%s-20261107-newtag]" % repo_)
    print("  real queue+archive re-tag match: %d/%d = %.2f%%" % (ok_, n_, 100.0 * ok_ / max(n_, 1)))
    chk("N1 real queue+archive re-tag match rate >= 99.5%% (%d/%d)" % (ok_, n_), n_ < 100 or ok_ * 1000 >= n_ * 995, (ok_, n_))

# ------------------------------------------------------------------------------------------------ 7b. Y2 r5 findings (review_y2_r5): N1 residual (39 probe pairs) + R1 (linear time) + R2 (_P2 bounded)
# every pair is two DIFFERENT tasks that differ only after/around a marker word; false-DISTINCT is acceptable, a collision is not
R5_PAIRS = [
 ("Set order.status to DONE (see docs) then emit OrderClosed in src/orders.py","Set order.status to DONE (see docs) then log metrics in src/stats.py"),
 ("Mark the job DONE (2026-01-01 cutoff) and purge queue in api/q.py","Mark the job DONE (2026-01-01 cutoff) and flush cache in api/c.py"),
 ("Rename state DONE (verified by tests) to FINISHED in models/a.py","Rename state DONE (verified by tests) to FINISHED in models/b.py"),
 ("Handle NOTE: prefix in parser/a.py","Handle NOTE: prefix in lexer/b.py"),
 ("Strip the trailing NOTE: block in docs/a.md","Strip the trailing NOTE: block in docs/b.md"),
 ("Add `(done 2026-01-01: x)` parse support in a/dates.py","Add `(done 2026-01-01: x)` parse support in b/dates.py"),
 ("Parse (done 2026-02-02, x) markers in tools/a.py","Parse (done 2026-02-02, x) markers in tools/b.py"),
 ("Render the - TRIAGE 2026-10-12 DONE: column in ui/a.vue","Render the - TRIAGE 2026-10-12 DONE: column in ui/b.vue"),
 ("Support <!-- closed 2026-01-01 by x --> comments in md/a.py","Support <!-- closed 2026-01-01 by x --> comments in md/b.py"),
 ("Escape <!-- landed 2026-01-01 --> in render/a.py then test","Escape <!-- landed 2026-01-01 --> in render/b.py then test"),
 ("Keep _(ALREADY-SATISFIED 2026-01-01: x)_ keys in i18n/a.json","Keep _(ALREADY-SATISFIED 2026-01-01: x)_ keys in i18n/b.json"),
 ("Return ALREADY DONE by the book if user exists in svc/a.py","Return ALREADY DONE by the book if user exists in svc/b.py"),
 ("Return ALREADY DONE, stale item flagged in svc/a.py","Return ALREADY DONE, stale item flagged in svc/b.py"),
 ("Show STALE TICKET, no action needed text in ui/a.vue","Show STALE TICKET, no action needed text in ui/b.vue"),
 ("Show STALE TICKET - banner in ui/a.vue","Show STALE TICKET - banner in ui/b.vue"),
 ("Remove (retired 2026-01-01 flag) handling from p/a.py (see line 12)","Remove (retired 2026-01-01 flag) handling from p/b.py (see line 12)"),
 ("Remove (auto-closed 2026-01-01 state) handling from p/a.py (cat:impl)","Remove (auto-closed 2026-01-01 state) handling from p/b.py (cat:impl)"),
 ("Fix (cat:impl) marker parse in x/a.py (see notes)","Fix (cat:impl) marker parse in x/b.py (see notes)"),
 ("Fix (coverage:x) badge in x/a.py (and docs)","Fix (coverage:x) badge in x/b.py (and docs)"),
 ("Handle REOPENED (again) state in w/a.py (n/a)","Handle REOPENED (again) state in w/b.py (n/a)"),
 ("Handle (REOPENED once) state in w/a.py then retest","Handle (REOPENED once) state in w/b.py then retest"),
 ("Parse SKIPPED (verified 2026-01-01) - reason ... in k/a.py","Parse SKIPPED (verified 2026-01-01) - reason ... in k/b.py"),
 ("Print (2026-01-01) as date in fmt/a.py (UTC) now","Print (2026-01-01) as date in fmt/b.py (UTC) now"),
 ("Print SKIPPED (2026-01-01) rows in fmt/a.py (UTC) now","Print SKIPPED (2026-01-01) rows in fmt/b.py (UTC) now"),
 ("Wrap result in (cat:x) then DONE (shipped abc) emit in f/a.py","Wrap result in (cat:x) then DONE (shipped abc) emit in f/b.py"),
 ("Compute value; ** DONE ** status in log/a.py","Compute value; ** DONE ** status in log/b.py"),
 ("Print **DONE** (2026-01-01) badge in ui/a.vue (x)","Print **DONE** (2026-01-01) badge in ui/b.vue (x)"),
 ("Print ✅ DONE badge in ui/a.vue for finished","Print ✅ DONE badge in ui/b.vue for finished"),
 ("Return DONE (shrike @ abc) status from api/a.py","Return DONE (shrike @ abc) status from api/b.py"),
 ("Emit `foo()` DONE (2026-01-01, x) event in ev/a.py","Emit `foo()` DONE (2026-01-01, x) event in ev/b.py"),
 ("Handle f(x)) DONE 2026-01-01 repo@abc: event in ev/a.py","Handle f(x)) DONE 2026-01-01 repo@abc: event in ev/b.py"),
 ("Add x) NOTE: handler in ev/a.py","Add x) NOTE: handler in ev/b.py"),
 ("Add y — NOTE: handler in ev/a.py","Add y — NOTE: handler in ev/b.py"),
 ("Fix a) DONE (2026-01-01 repo @ h) path in z/a.py","Fix a) DONE (2026-01-01 repo @ h) path in z/b.py"),
 ("Fix a_ DONE (2026-01-01) path in z/a.py","Fix a_ DONE (2026-01-01) path in z/b.py"),
 ("Fix a> NOTE: path in z/a.py","Fix a> NOTE: path in z/b.py"),
 ("Fix x] NOTE: path in z/a.py","Fix x] NOTE: path in z/b.py"),
 ("Add `x` ALREADY DONE stale item (cat:impl) in a/z.py","Add `x` ALREADY DONE stale item (cat:impl) in b/z.py"),
 ("Handle (auto-closed 2026-01-01: a (b) c) shape in s/a.py then","Handle (auto-closed 2026-01-01: a (b) c) shape in s/b.py then"),
]
for i_, (a_, c_) in enumerate(R5_PAIRS):
    chk("R5 distinct keys (probe pair %02d): %s" % (i_, a_[:60]), KB("- [ ] " + a_) != KB("- [ ] " + c_), a_)
for i_, (a_, c_) in enumerate([("Handle NOTE: prefix in the parser", "Handle NOTE: prefix in the lexer"), ("Show the **DONE** badge when finished", "Show the **DONE** badge when approved"), ("Set DONE (see docs) when it ships", "Set DONE (see docs) when it fails"), ("Print \u2705 DONE for finished jobs", "Print \u2705 DONE for failed jobs")]):
    chk("R5 distinct keys, prose without a file path or closing token (extra pair %d)" % i_, KB("- [ ] " + a_) != KB("- [ ] " + c_), a_)
chk("R5 all 39 probe pairs present", len(R5_PAIRS) == 39, len(R5_PAIRS))
R5_BASE = "Add `def foo_bar` to src/a.py and wire it in src/b.py VERIFY: `pytest tests/test_a.py::test_x`"
R5_CLOSED = [" (auto-closed 2026-11-05: [feat:T] landed, all 1 named test id(s) present on origin/develop; landing=item)", " (cat:impl; multifile:no)", " DONE (2026-11-05, repo @ abc1234)", " — DONE", " ✅ DONE",
             " **DONE** (2026-11-05)", " ALREADY DONE (verified 2026-11-05)", " <!-- closed 2026-11-05 by claude: done -->", " _(ALREADY-SATISFIED 2026-11-05: x)_", " (retired 2026-11-05: resolved)",
             " — TRIAGE 2026-10-12 DONE: stale", " (done 2026-09-12: claude x) tests pass", " (cat:impl; multifile:no) DONE (2026-11-05, repo @ abc)", " (2026-11-05)"]
for cl_ in R5_CLOSED:
    chk("R5 closed shape after a VERIFY backtick re-keys to the open form: %r" % cl_[:40], KB(R5_BASE + cl_) == KB(R5_BASE), cl_)
chk("R5 real closed free-text tail with files in it still peels (DONE (repo @ sha, verified D) - note naming a file)", KB("Do x in y.py. (cat:logic) DONE (shrike-monitor @ 9b68488, verified 2026-09-08) - verified distinct from services/uptime.py's f.") == KB("Do x in y.py."))
# R1: 100 KB shapes finish well under a second each (round 5: 100K spaces timed out > 15 s, `DONE (` + 'verified '*11000 took 7 s)
import time as _t
_N = 100000
R1_SHAPES = {"spaces": " " * _N + "DONE", "spaces_mid": "a" + " " * _N + "b DONE", "DONE_verified": "DONE (" + "verified " * (_N // 9), "ALREADY_rep": "ALREADY DONE " * (_N // 13), "DONE_rep": "DONE (@) " * (_N // 10),
             "cat_rep": "(cat:x) " * (_N // 8), "feat_open": "[feat:" * (_N // 6), "feat_open_400k": "[feat:" * (4 * _N // 6), "autoskip_open": "[AUTO-SKIP" * (_N // 10), "parens_open": "(auto-closed 2026-01-01 " + "(" * _N, "retired_nested": "(retired 2026-01-01: " + "(a " * (_N // 3),
             "comment_open": "<!-- " * (_N // 5), "stars": "*" * _N + "DONE", "dash_rep": " - " * (_N // 3) + "TRIAGE", "triage_rep": " — TRIAGE 2026-01-01 DONE: x" * (_N // 30), "done_date_rep": "x. DONE (2026-01-01, a @ b) " * (_N // 28),
             "note_rep": ") NOTE: x " * (_N // 10), "ws_tabs": "\t \n" * (_N // 3) + "DONE", "gettext": " _(DONE " + "x)" * (_N // 2)}
import signal as _sig


class _R1Timeout(Exception):
    pass


def _r1_alarm(*a_):
    raise _R1Timeout()


_sig.signal(_sig.SIGALRM, _r1_alarm)
for nm_, sh_ in R1_SHAPES.items():
    t0_ = _t.monotonic()
    _sig.alarm(3)   # a quadratic implementation is cut off after 3 s (also keeps the mutant runs short)
    try:
        B.body_key("billwatch", "- [ ] task " + sh_)
    except _R1Timeout:
        pass
    finally:
        _sig.alarm(0)
    d_ = _t.monotonic() - t0_
    chk("R1 body_key is linear: 100 KB shape %s < 1 s (%.3fs)" % (nm_, d_), d_ < 1.0, d_)
    if d_ >= 1.0:
        break   # one slow shape is already a failure; do not burn minutes on the rest
LONGB = "Add thing " + "word " * 30000
chk("R1 a very long line keeps open/closed equivalence (annotation at the end still peels)", KB(LONGB + "(cat:impl) DONE (2026-11-05, r @ abc)") == KB(LONGB) and KB(LONGB + " x") != KB(LONGB + " y"))
chk("R1 a unit glued to a word is not a tail (token starts only)", KB("Call f(cat:impl)") != KB("Call f") and KB("Show x**DONE**") != KB("Show x"))
chk("R1 whitespace-only variants of a task share the key (collapsed before peeling)", KB("Do   the\t thing   (cat:impl)") == KB("Do the thing"))
# R2: the paren-bounding _P2 of the (auto-closed|retired D ...) unit
chk("R2 _P2 is bounded: a (retired D flag) mention followed by more prose stays distinct", KB("Remove (retired 2026-01-01 flag) handling from p/a.py (see line 12)") != KB("Remove (retired 2026-01-01 flag) handling from p/b.py (see line 12)"))

# ------------------------------------------------------------------------------------------------ 8. Y2 r4 N2: untouched lines round-trip byte-for-byte; symlink + temp cleanup in write_text_atomic
N2_TASK = "[T1] app/a.py \u2014 Do the exact thing described here in full."
WEIRD = "formfeed\x0cmid ls\u2028mid nel\x85mid vt\x0b fs\x1c gs\x1d rs\x1e ps\u2029 end"
N2_PROG = ("- [ ] " + WEIRD + "\r\n- [ ] [AUTO-SKIP] " + N2_TASK + "\r\n- [ ] keep \xff-free CRLF line\r\n- [ ] last line without a newline " + WEIRD).encode("utf-8")
sigf2 = os.path.join(BASE, "n2sig.txt")
w(sigf2, B.task_sig(N2_TASK) + "\n")
prog2 = os.path.join(BASE, "n2prog.md")
open(prog2, "wb").write(N2_PROG)
cp = subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "retire", "--progress", prog2, "--signatures", sigf2, "--today", "2026-11-06"], capture_output=True, text=True, env=GENV)
got2 = open(prog2, "rb").read()
exp2 = N2_PROG.replace(("- [ ] [AUTO-SKIP] " + N2_TASK).encode(), ("- [x] [AUTO-SKIP] " + N2_TASK + " (retired 2026-11-06: resolved via Claude, see shared/CLAUDE_QUEUE.md)").encode())
chk("N2 retire: only the retired line changes; \\x0c/U+2028/\\x85/\\x0b/\\x1c-\\x1e/U+2029 lines, CRLF endings and the missing final newline survive byte-for-byte", cp.returncode == 0 and got2 == exp2, (cp.stderr[-200:], got2, exp2))
# retired line is the LAST line without a newline, and an LF file keeps its final newline
open(prog2, "wb").write(("- [ ] a\x0cb\n- [ ] [AUTO-SKIP] " + N2_TASK).encode("utf-8"))
subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "retire", "--progress", prog2, "--signatures", sigf2, "--today", "2026-11-06"], capture_output=True, text=True, env=GENV)
chk("N2 retire: retired last line without a trailing newline gains none; a\\x0cb stays one line", open(prog2, "rb").read() == ("- [ ] a\x0cb\n- [x] [AUTO-SKIP] " + N2_TASK + " (retired 2026-11-06: resolved via Claude, see shared/CLAUDE_QUEUE.md)").encode("utf-8"), open(prog2, "rb").read())
open(prog2, "wb").write(("- [ ] keep\x0c\n- [ ] [AUTO-SKIP] " + N2_TASK + "\n").encode("utf-8"))
subprocess.run([sys.executable, os.path.join(Q, "claude_queue_bridge.py"), "retire", "--progress", prog2, "--signatures", sigf2, "--today", "2026-11-06"], capture_output=True, text=True, env=GENV)
chk("N2 retire: LF file with a final newline keeps exactly one", open(prog2, "rb").read().endswith(b"CLAUDE_QUEUE.md)\n") and open(prog2, "rb").read().startswith(b"- [ ] keep\x0c\n"), open(prog2, "rb").read())
# autoclose enforce
N2_Q = "# q\r\n## s\r\n" + WEIRD + "\r\n" + LA + "\r\n" + WEIRD + "\n" + LB.replace("- [ ]", "- [x]") + "\r\nlast " + WEIRD
qp2, cp2 = run_ac("enforce", N2_Q, os.path.join(BASE, "state", "n2e.log"))
got3 = open(qp2, "rb").read().decode("utf-8", "surrogateescape")
chk("N2 autoclose enforce: closes the landed line, keeps CRLF on it, every other byte (form feed, U+2028, CRLF, missing final newline) identical",
    cp2.returncode == 0 and got3.count("(auto-closed") == 1 and got3.endswith("last " + WEIRD) and got3.replace(" (auto-closed 2026-11-04: [feat:billwatch-20261104-t1] landed, all 1 named test id(s) present on HEAD; landing=item)", "").replace(LA.replace("- [ ]", "- [x]", 1), LA) == N2_Q,
    (cp2.stderr[-200:], got3))
chk("N2 autoclose enforce: the auto-closed suffix sits BEFORE the \\r of its line", "landing=item)\r\n" in got3 or "landing=feature)\r\n" in got3, got3)
# write_text_atomic: symlink target is written through, link stays a link; a failing replace leaves no temp file and the target untouched
sd = os.path.join(BASE, "n2sym")
os.makedirs(sd)
tgt = os.path.join(sd, "real.md")
lnk = os.path.join(sd, "link.md")
w(tgt, "old\n")
os.symlink("real.md", lnk)
B.write_text_atomic(lnk, "new\n")
chk("N2 write_text_atomic: a symlink path is written THROUGH (still a symlink, target updated)", os.path.islink(lnk) and rd(tgt) == "new\n" and rd(lnk) == "new\n", (os.path.islink(lnk), rd(tgt)))
chk("N2 write_text_atomic: no temp file left after a successful write", sorted(os.listdir(sd)) == ["link.md", "real.md"], os.listdir(sd))
_real_replace = os.replace
def _boom(a_, b_):
    raise OSError("simulated replace failure")
os.replace = _boom
try:
    raised_ = False
    try:
        B.write_text_atomic(lnk, "newer\n")
    except OSError:
        raised_ = True
finally:
    os.replace = _real_replace
chk("N2 write_text_atomic: failure at the replace step raises, leaves the target untouched and removes the temp file", raised_ and rd(tgt) == "new\n" and sorted(os.listdir(sd)) == ["link.md", "real.md"], (raised_, os.listdir(sd)))

# ------------------------------------------------------------------------------------------------ 6. mutants
MUTANTS = [
    ("ledger never consulted", "claude_queue_bridge.py", '        if key in ledger and lmode != "off":', "        if False:"),
    ("ledger skip enforces by default", "claude_queue_bridge.py", 'os.environ.get("OVN_HARVEST_LEDGER_MODE") or "shadow"', 'os.environ.get("OVN_HARVEST_LEDGER_MODE") or "enforce"'),
    ("ledger never written for harvested lines", "claude_queue_bridge.py", '        new_rows.append((key, "harvested", repo, tag, args.today))\n', ""),
    ("closed keys never recorded", "claude_queue_bridge.py", "            out.add((body_key(repo, m.group(1)), repo, feat_tag_of(m.group(1))))", "            pass"),
    ("done-check default enforce", "claude_queue_bridge.py", 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "shadow"', 'os.environ.get("OVN_HARVEST_DONE_CHECK") or "on"'),
    ("on alias dropped", "claude_queue_bridge.py", '    if v == "on":\n        v = "enforce"\n    return v if v in ("shadow", "enforce", "off") else "shadow"\n\n\ndef ledger_mode', '    return v if v in ("shadow", "enforce", "off") else "shadow"\n\n\ndef ledger_mode'),
    ("creation items with modify verbs judged done", "claude_queue_bridge.py", "if not CREATE_VERB_RE.search(body) or OTHER_VERB_RE.search(body):", "if not CREATE_VERB_RE.search(body):"),
    ("creation items never judged done", "claude_queue_bridge.py", "        ids = named_new_defs(task)   # Y2:", "        ids = []   # Y2:"),
    ("shadow rows not deduped", "claude_queue_bridge.py", "            if key in row:", "            if False:"),
    ("shadow autoclose key uses the line number", "claude_queue_bridge.py", 'repo, tag, body_key(repo, ltxt))\n        _shadow_once', 'repo, tag, lineno)\n        _shadow_once'),
    ("require-item ignored", "claude_queue_bridge.py", "                    if require_item and not item_landed:", "                    if False:"),
    ("bridge.sh done-check default enforce", "claude_queue_bridge.sh", "OVN_HARVEST_DONE_CHECK:-shadow", "OVN_HARVEST_DONE_CHECK:-on"),
    ("bridge.sh ledger-mode default enforce", "claude_queue_bridge.sh", "OVN_HARVEST_LEDGER_MODE:-shadow", "OVN_HARVEST_LEDGER_MODE:-enforce"),
    ("closed ledger rows never written", "claude_queue_bridge.py", "    append_ledger(ledger_path, new_closed)\n", "    pass\n"),
    ("ledger first-row-wins", "claude_queue_bridge.py", "                    out[parts[0]] = parts[1]", "                    out.setdefault(parts[0], parts[1])"),
    ("bridge.sh drops the ledger", "claude_queue_bridge.sh", '--ledger "${OVN_HARVEST_LEDGER', '--noledger "${OVN_HARVEST_LEDGER'),
    ("cron header regressed", "scripts/cron.txt", "ARE installed in the box crontab", "are not installed"),
    ("N1 gettext _( cut accepts any uppercase key", "claude_queue_bridge.py", "_\\((?:ALREADY-SATISFIED|DONE|RESOLVED|UPDATED|SKIPPED|IMPLEMENTED|REVIEWED|duplicate\\b|", "_\\((?:[A-Z][A-Z-]+|"),
    ("N1 html comment cut needs no closed/date opener", "claude_queue_bridge.py", '<!--\\s*(?:(?:closed|', '<!--\\s*(?:(?:[a-z]+|closed|'),
    ("R2 _P2 greedy to the last paren", "claude_queue_bridge.py", r'_P2 = r"(?:[^()]|\((?:[^()]|\([^()]*\))*\))*"', '_P2 = r".*"'),
    ("R1 tail window unbounded", "claude_queue_bridge.py", "TAIL_WINDOW = 2000", "TAIL_WINDOW = 10 ** 9"),
    ("R1/N1 units may start mid-token", "claude_queue_bridge.py", '        if pos == 0 or t[pos - 1] == " ":', "        if True:"),
    ("N1r5 weak word markers need no closing token", "claude_queue_bridge.py", "    if bch in _BOUNDARY and not _PATH_RE.search(g):", "    if not _PATH_RE.search(g):"),
    ("R1 feat strip unbounded", "claude_queue_bridge.py", '[feat:[^\\]\\n]{0,200}\\]', '[feat:[^\\]]*\\]'),
    ("N1r5 tails peeled without proof or boundary", "claude_queue_bridge.py", "def _tail_ok(kind, bch, g):", "def _tail_ok(kind, bch, g):\n    return True"),
    ("N1r5 weak tails ignore file paths", "claude_queue_bridge.py", "if bch in _BOUNDARY and not _PATH_RE.search(g):", "if bch in _BOUNDARY:"),
    ("N1r5 free tails need no sentence boundary", "claude_queue_bridge.py", "        if bch in _SENT:\n            return True\n        if _EM_TRIAGE_RE", "        if True:\n            return True\n        if _EM_TRIAGE_RE"),
    ("N2 retire splits on every unicode line break", "claude_queue_bridge.py", 'read_text_raw(args.progress).split("\\n")', 'read_text_raw(args.progress).splitlines()'),
    ("N2 autoclose splits on every unicode line break", "claude_queue_bridge.py", 'read_text_raw(args.queue).split("\\n")', 'read_text_raw(args.queue).splitlines()'),
    ("N2 autoclose drops the CR", "claude_queue_bridge.py", "+ n[len(c):] + cr)", "+ n[len(c):])"),
    ("N2 write_text_atomic replaces the link itself", "claude_queue_bridge.py", "    path = os.path.realpath(path)   # Y2 r5", "    path = path   # Y2 r5"),
    ("N2 write_text_atomic leaves the temp on failure", "claude_queue_bridge.py", "            os.unlink(tmp)\n", "            pass\n"),
]


def mutants():
    bad = 0
    for name, rel, old, new in MUTANTS:
        mq = os.path.join(BASE, "mut")
        shutil.rmtree(mq, ignore_errors=True)
        os.makedirs(os.path.join(mq, "scripts"))
        for f in ("claude_queue_bridge.py", "claude_queue_bridge.sh"):
            shutil.copy(os.path.join(Q, f), os.path.join(mq, f))
        shutil.copy(os.path.join(Q, "scripts", "cron.txt"), os.path.join(mq, "scripts", "cron.txt"))
        p_ = os.path.join(mq, rel)
        s = open(p_, encoding="utf-8").read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        with open(p_, "w", encoding="utf-8") as f:
            f.write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, Y2_ROOT=mq, Y2_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


if os.environ.get("Y2_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
print("test_y2_bridge_harvest: %d passed, %d failed" % (PASSES[0], len(FAILS)))
tmp_track.sweep()
sys.exit(1 if FAILS else 0)
