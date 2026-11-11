#!/usr/bin/env python3
"""Y2 before-enforce checklist (2026-11-10) for claude_queue_bridge.body_key. Hermetic, no box, no network, no ntfy. Y2 enforce modes stay OFF/shadow.
  C1  dated-parenthetical collisions: `Cut release (2026-12-01, v2 API)` vs `v3 API` (task text with a date in it) stay distinct; real dated closing annotations still normalise
  C2  the five September ALREADY DONE shapes that keyed differently from their open sibling now normalise (`ALREADY DONE, verified D:`, comma after the bare date, `(duplicate of ..) - verified D`, `found+fixed D:`)
      while prose after a paren header (`ALREADY DONE (verified D) in the header, ..`) and a header with no date stay distinct
  C3  the three previously untested gates: bare `NOTE:` path gate, `@` as the only proof in `DONE (x @ sha)`, `;` in the dated-parenthetical lookahead
  C4  `ledger-rebuild` regenerates the harvest ledger TSV from queue+archive (closed + harvested rows, keeps `done` rows, atomic, never edits the queue)
  MUTANTS  copies of the source with one substitution each; at least one check must fail on every mutant
Env QY2_ROOT points at another copy of the overnight-queue tree (the mutant runner)."""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

os.environ["TZ"] = "UTC"
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.abspath(os.path.join(HERE, "..", ".."))
ROOT = os.environ.get("QY2_ROOT") or REAL
BR = os.path.join(ROOT, "claude_queue_bridge.py")
BASE = os.path.realpath(tempfile.mkdtemp(prefix="qy2-"))
FAILS, PASSES = [], [0]


def chk(name, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   " + name)
    else:
        FAILS.append(name)
        print("  FAIL %s :: %s" % (name, str(detail)[:300]))


spec = importlib.util.spec_from_file_location("cqb_qy2", BR)
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)


def KB(t, repo="shared"):
    return B.body_key(repo, "- [ ] [CLAUDE] shared/ — " + t)


# ------------------------------------------------------------------------------------------------ C1 dated parentheticals
chk("C1 `(D, v2 API)` vs `(D, v3 API)` distinct", KB("Cut release (2026-12-01, v2 API)") != KB("Cut release (2026-12-01, v3 API)"))
chk("C1 `(D; v2 API)` vs `(D; v3 API)` distinct", KB("Cut release (2026-12-01; v2 API)") != KB("Cut release (2026-12-01; v3 API)"))
chk("C1 `(D, rollout A)` vs `(D, rollout B)` distinct", KB("Freeze the schema (2026-12-01, rollout A)") != KB("Freeze the schema (2026-12-01, rollout B)"))
BASE_T = "Add retry with backoff to the sync worker"
for ann in (" (2026-10-01)", " (2026-10-01, claude: done)", " (2026-10-01; claude: done)", " (2026-09-04, gitlark @ 6a483f1)", " (2026-10-01, verified)", " (2026-10-01; verified 2026-10-02)",
            " (2026-10-01, done)", " SKIPPED (2026-10-01)", " (2026-10-17 claude sweep: VERIFY text corrected)"):
    chk("C1 closing annotation still normalises:%s" % ann, KB(BASE_T + ann) == KB(BASE_T), ann)

# ------------------------------------------------------------------------------------------------ C2 September ALREADY DONE shapes
T2 = "Fix the foo handler in the router."
SEPT = [
    " ALREADY DONE, verified 2026-09-03: present at the router",
    " — ALREADY DONE, verified 2026-09-08: no code changes needed",
    " ALREADY DONE by the fleet — verified 2026-09-05, 72 tests pass.",
    " ALREADY DONE (duplicate of the §17 items above) — verified 2026-09-05, plus found + fixed one orphan",
    " ALREADY DONE by the fleet, found+fixed 2026-09-05: the page was already complete",
]
for ann in SEPT:
    chk("C2 closed form keys like the open line:%s" % ann[:55], KB(T2 + ann) == KB(T2), ann)
chk("C2 two different closed bodies of the same open task agree", KB(T2 + SEPT[0]) == KB(T2 + SEPT[2]))
chk("C2 prose after a paren header stays distinct", KB("Fix typo. ALREADY DONE (verified 2026-01-01) in the header, still wrong in the footer") != KB("Fix typo. ALREADY DONE (verified 2026-01-01) in the header, still wrong in the sidebar"))
chk("C2 no date, no peel (stays distinct from the open line)", KB(T2 + " ALREADY DONE (found already fully wired) added test_x") != KB(T2))
chk("C2 `(duplicate of ..)` alone (no verified date) is not a closing annotation", KB("Add a flag (duplicate of line 4)") != KB("Add a flag"))
chk("C2 comma after a paren header is prose", KB("Fix typo. ALREADY DONE (verified 2026-01-01), header only") != KB("Fix typo. ALREADY DONE (verified 2026-01-01), footer only"))
chk("C2 comma after a bare date followed by two different tasks agree on the open form", KB("Fix typo. ALREADY DONE verified 2026-01-01, 12 tests pass") == KB("Fix typo."))

# ------------------------------------------------------------------------------------------------ C3 the three untested gates
HEADS = ["Add a retry loop (cat:impl; multifile:no)"]
chk("C3 bare NOTE: after a bounded annotation, no path: peeled", KB("Add a retry loop (cat:impl; multifile:no) NOTE: explain jitter") == KB("Add a retry loop (cat:impl; multifile:no)"))
chk("C3 bare NOTE: path gate: a NOTE naming a path is task prose (distinct)", KB("Add a retry loop (cat:impl; multifile:no) NOTE: see app/a.py") != KB("Add a retry loop (cat:impl; multifile:no) NOTE: see app/b.py"))
chk("C3 bare NOTE: path gate (bare filename)", KB("Add a retry loop (cat:impl; multifile:no) NOTE: see a.py") != KB("Add a retry loop (cat:impl; multifile:no) NOTE: see b.py"))
chk("C3 `@` is the only proof in `DONE (x @ sha)` (closing): peeled", KB("Reduce bundle size by 10%. DONE (shrike-monitor @ abc1234)") == KB("Reduce bundle size by 10%."))
chk("C3 `@` proof closes a bare DONE even right after a word (no sentence end)", KB("Reduce bundle size DONE (shrike-monitor @ abc1234)") == KB("Reduce bundle size"))
chk("C3 `@` proof: a DONE paren without any proof stays prose", KB("Reduce bundle size by 10%. DONE (tree-shake lodash)") != KB("Reduce bundle size by 10%. DONE (tree-shake moment)"))
chk("C3 `;` in the dated-parenthetical lookahead: `(D; verified)` peeled", KB(BASE_T + " (2026-10-01; verified)") == KB(BASE_T))
chk("C3 `;` in the dated-parenthetical lookahead: `(D; v2 API)` kept", KB("Cut release (2026-12-01; v2 API)") != KB("Cut release (2026-12-01; v3 API)"))

# ------------------------------------------------------------------------------------------------ C4 ledger-rebuild
tq = os.path.join(BASE, "q.md")
ta = os.path.join(BASE, "a.md")
to = os.path.join(BASE, "state", "ledger.tsv")
os.makedirs(os.path.dirname(to))
with open(tq, "w", encoding="utf-8") as f:
    f.write("## Section\n- [x] [CLAUDE] gitlark/ — Closed task alpha ALREADY DONE, verified 2026-09-03: yes\n- [ ] [CLAUDE] gitlark/ — Open hand written task beta\n"
            "## Auto-harvested from 27B ceiling [2026-11-01] - x\n- [ ] [CLAUDE] gitlark/ — Harvested task gamma with detail\n")
with open(ta, "w", encoding="utf-8") as f:
    f.write("## Archive\n- [x] [CLAUDE] gitlark/ — Archived task delta (2026-10-01, claude: done)\n")
with open(to, "w", encoding="utf-8") as f:
    f.write("deadbeefdeadbeefdead\tdone\tgitlark\t\t2026-10-01\nfeedfeedfeedfeedfeed\tharvested\tgitlark\t\t2026-10-01\n")
before = open(tq, encoding="utf-8").read()
cp = subprocess.run([sys.executable, BR, "ledger-rebuild", "--queue", tq, "--archive", ta, "--out", to, "--today", "2026-11-10"], capture_output=True, text=True)
rows = [r.split("\t") for r in open(to, encoding="utf-8").read().splitlines()]
byk = {r[0]: r[1] for r in rows}
chk("C4 ledger-rebuild exits 0", cp.returncode == 0, cp.stderr)
chk("C4 closed task keyed by its OPEN text", byk.get(B.body_key("gitlark", "Closed task alpha")) == "closed", rows)
chk("C4 archived closed task keyed", byk.get(B.body_key("gitlark", "Archived task delta")) == "closed", rows)
chk("C4 harvested open line under an Auto-harvested header is `harvested`", byk.get(B.body_key("gitlark", "Harvested task gamma with detail")) == "harvested", rows)
chk("C4 hand-written open line is not ledgered", B.body_key("gitlark", "Open hand written task beta") not in byk, rows)
chk("C4 existing `done` row kept, stale `harvested` row dropped", byk.get("deadbeefdeadbeefdead") == "done" and "feedfeedfeedfeedfeed" not in byk, rows)
chk("C4 queue file untouched, no temp file left", open(tq, encoding="utf-8").read() == before and not os.path.exists(to + ".new"))

# ------------------------------------------------------------------------------------------------ mutants
MUTANTS = [
    ("C1 dated parenthetical takes any prose after the date", '_DATED_PAREN_AHEAD + _P2', '"(?=[,;)]|\\\\s+claude\\\\b)" + _P2'),
    ("C1 dated parenthetical lookahead: `,` accepts anything", r'\s*[,;]\s*(?:claude\b|(?:re-)?verified\b|', r'\s*[,;]\s*(?:|claude\b|(?:re-)?verified\b|'),
    ("C3 `;` dropped from the dated-parenthetical lookahead", r'\s*[,;]\s*(?:claude\b', r'\s*[,]\s*(?:claude\b'),
    ("C2 header: no comma before `verified`", '(?:\\s*,)?(?:\\s*,?\\s*found', '(?:\\s*found'),
    ("C2 header: `(duplicate of ..)` not recognised", '(?:\\s*\\((?:duplicate|dup)\\s+of\\b[^()]*\\))?', ''),
    ("C2 header: `found+fixed` not recognised", '(?:\\s*,?\\s*found\\s*\\+\\s*fixed\\b)?', ''),
    ("C2 comma after a bare date does not close the header", 'if shape == "already" and rem.startswith(",") and', 'if False and'),
    ("C2 comma after ANY header (paren too) closes it", 'and g[:m.end()].rstrip()[-1:].isdigit():', ':'),
    ("C3 bare NOTE: path gate removed", "return bch in _BOUNDARY and not _PATH_RE.search(g) and t is not None and _ends_with_bounded(t, e)", "return bch in _BOUNDARY and t is not None and _ends_with_bounded(t, e)"),
    ("C3 `@` no longer proof in a DONE (x @ sha) header", '_DONE_TAIL_PROOF_RE = re.compile(r"@|\\b"', '_DONE_TAIL_PROOF_RE = re.compile(r"\\b"'),
    ("C3 `@` no longer proof in the bare DONE closing", '_DONE_PROOF_RE = re.compile(r"\\([^()]*(?:@|\\b"', '_DONE_PROOF_RE = re.compile(r"\\([^()]*(?:\\b"'),
    ("C4 ledger-rebuild drops `done` rows", '        if st == "done" and k not in seen:', '        if False:'),
    ("C4 ledger-rebuild skips the harvested block", 'if m and header.lower().startswith("auto-harvested"):', 'if False:'),
    ("C4 ledger-rebuild not atomic (no temp+replace)", "    os.replace(tmp, args.out)\n", "    shutil_ = None\n"),
]


def mutants():
    bad = 0
    for name, old, new in MUTANTS:
        mq = os.path.join(BASE, "mut")
        shutil.rmtree(mq, ignore_errors=True)
        os.makedirs(os.path.join(mq, "scripts", "test"))
        shutil.copy(os.path.join(REAL, "claude_queue_bridge.py"), os.path.join(mq, "claude_queue_bridge.py"))
        p_ = os.path.join(mq, "claude_queue_bridge.py")
        s = open(p_, encoding="utf-8").read()
        if old not in s:
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            bad += 1
            continue
        with open(p_, "w", encoding="utf-8") as f:
            f.write(s.replace(old, new, 1))
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=dict(os.environ, QY2_ROOT=mq, QY2_NO_MUTANTS="1"))
        if cp.returncode == 0:
            print("  FAIL mutant NOT caught: %s" % name)
            bad += 1
        else:
            print("  ok   mutant caught: %s" % name)
    return bad


if os.environ.get("QY2_NO_MUTANTS") != "1":
    nm = mutants()
    if nm:
        FAILS.append("%d mutant(s) not caught" % nm)
shutil.rmtree(BASE, ignore_errors=True)
print("test_q_y2_enforce_checklist: %d passed, %d failed" % (PASSES[0], len(FAILS)))
if FAILS:
    print("FAILED: " + "; ".join(FAILS))
sys.exit(1 if FAILS else 0)
