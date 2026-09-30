#!/usr/bin/env python3
"""Extra coverage tests for scripts/ovn_failure_triage.py (runs the REAL file in place, imported by path
and via subprocess CLI). Hermetic: temp state/logs dirs only. Exit 0 = all pass."""
import builtins, importlib.util, io, json, os, subprocess, sys, tempfile, time, contextlib
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "ovn_failure_triage.py")
if not os.path.exists(SCRIPT):
    SCRIPT = os.path.expanduser("~/overnight-queue/scripts/ovn_failure_triage.py")
if not os.path.exists(SCRIPT):
    print("  SKIP: ovn_failure_triage.py not found"); sys.exit(0)
SCRIPT = os.path.abspath(SCRIPT)
sys.path.insert(0, os.path.dirname(SCRIPT))
spec = importlib.util.spec_from_file_location("ovn_failure_triage", SCRIPT)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond: P += 1
    else:
        F += 1; print("  FAIL: %s %s" % (name, extra))

def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def cli(*a, stdin=None):
    r = subprocess.run([sys.executable, SCRIPT] + list(a), capture_output=True, text=True, stdin=subprocess.DEVNULL if stdin is None else None, input=stdin)
    return r.returncode, r.stdout, r.stderr

tmp = tempfile.mkdtemp(prefix="w3c-ft-")
def fresh():
    d = tempfile.mkdtemp(dir=tmp); s = os.path.join(d, "state"); l = os.path.join(d, "logs")
    os.makedirs(s); os.makedirs(l); return s, l

# ---- registry / dir index / helpers -------------------------------------------------------
s, l = fresh()
open(os.path.join(s, "failure_clusters.json"), "w").write("{not json")
ok("corrupt registry -> {}", m.load_registry(s) == {})
ok("listdir failure -> []", m._build_run_dir_index(os.path.join(tmp, "does-not-exist")) == [])
os.makedirs(os.path.join(l, "20260101-000000")); os.makedirs(os.path.join(l, "notarundir"))
os.makedirs(os.path.join(l, "99999999-999999"))   # matches regex, fails strptime
idx = m._build_run_dir_index(l)
ok("only the valid run dir indexed (non-matching + unparsable skipped)", [n for _, n in idx] == ["20260101-000000"], str(idx))
ok("_epoch_of_ts bad -> None", m._epoch_of_ts("garbage") is None)
ok("_epoch_of_ts good", m._epoch_of_ts("2026-01-01T00:00:00Z") is not None)
ok("find_task_log None epoch", m.find_task_log(l, idx, "x", None) is None)
ok("find_task_log empty index", m.find_task_log(l, [], "x", 5.0) is None)
ok("find_task_log exhausts candidates -> None", m.find_task_log(l, idx, "nolog", idx[0][0] + 10) is None)
ok("_read_tail missing file -> ''", m._read_tail(os.path.join(tmp, "nofile")) == "")
big = os.path.join(tmp, "big.log"); open(big, "w").write("A" * 50000 + "TAIL")
t = m._read_tail(big, max_bytes=100)
ok("_read_tail returns only the tail", len(t) == 100 and t.endswith("TAIL"))

# ---- extractors -----------------------------------------------------------------------------
es = m.extract_signature
ok("aider subpath", es("x\nfoo is not in the subpath of bar\n") == "aider:is-not-in-subpath")
ok("aider hunk", es("Hunk FAILED to apply\n") == "aider:hunk-failed-to-apply")
ok("aider no-exact", es("SearchReplaceNoExactMatch") == "aider:diff-no-exact-match")
ok("aider UnifiedDiffNoMatch", es("UnifiedDiffNoMatch") == "aider:diff-no-exact-match")
ok("kotlin param", es("No parameter with name 'foo' found") == "kotlin:no-param-found:<X>")
ok("gradle FAILURE", es("blah\nFAILURE: Build failed with an exception 42\n").startswith("gradle:Build failed with an exception #"))
ok("gdscript", es("SCRIPT ERROR: Parse Error at 12\n").startswith("gdscript:"))
ok("js FAIL", es("  FAIL src/foo.test.ts\n").startswith("js:src/foo.test.ts") or es("  FAIL src/foo.test.ts\n").startswith("js:"))
ok("js plugin", es("x [plugin vite:foo] broke\n").startswith("js:"))
ok("js AssertionError (no pytest line)", es("Traceback\nAssertionError: expected 1 got 2\n").startswith("js:AssertionError"))
ok("pytest summary .py::", es("FAILED tests/foo.py::test_bar - AssertionError: no\n").startswith("python:pytest-failed:"))
ok("python FAILED non-.py", es("FAILED foo - bad thing\n").startswith("python:pytest-failed:foo"))
ok("python exception", es("ValueError: bad 12\n") == "python:ValueError: bad #")
ok("pipeline marker", es("junk\n--- BUILD-GATE: commit structurally broke the build ---\n").startswith("pipeline:build-gate"))
ok("fallback generic hash", es("some\nrandom\ntext\n").startswith("generic:tail-hash:"))
ok("fallback on empty log", es("").startswith("generic:tail-hash:"))
ok("status signature: no-op", m._status_signature({"status": "no-op"}).startswith("pipeline:flail"))
ok("status signature: other -> None", m._status_signature({"status": "landed"}) is None)
ok("status signature: missing -> None", m._status_signature({}) is None)
orig = m.EXTRACTORS
m.EXTRACTORS = []
ok("no extractor matches -> generic:no-signature", es("anything") == "generic:no-signature")
m.EXTRACTORS = orig

# ---- detection pass -------------------------------------------------------------------------
now = time.time()
def dirname_for(epoch):
    return time.strftime("%Y%m%d-%H%M%S", time.localtime(epoch))
def rec(i, ts_epoch, **kw):
    r = {"id": i, "repo": "billwatch", "ts": iso(ts_epoch) if ts_epoch is not None else "", "class": "reverted", "item_hash": "h" + i}
    r.update(kw); return r
def write_outcomes(s, recs, raw_extra=()):
    with open(os.path.join(s, "outcomes.jsonl"), "w") as f:
        for r in recs: f.write(json.dumps(r) + "\n")
        for x in raw_extra: f.write(x + "\n")

s, l = fresh()
ok("no outcomes file -> processed 0", m.process_new_records(s, l)["processed"] == 0)
older = os.path.join(l, dirname_for(now - 1800)); newer = os.path.join(l, dirname_for(now - 600))
os.makedirs(older); os.makedirs(newer)
open(os.path.join(older, "t1.log"), "w").write("x\nValueError: boom 7\n")
write_outcomes(s, [
    rec("t1", now - 300),                                   # log found by walking back past the newer dir
    rec("t2", now - 300),                                   # no log anywhere -> no-log signature
    rec("t3", None, fail_reason="oops", status="weird"),    # no ts -> no epoch -> no-log
    rec("t4", now - 300, **{"class": "landed"}),                   # good -> skipped
], raw_extra=["", "{bad json"])
open(os.path.join(s, ".failure_triage.cursor"), "w").write("not-a-number")
res = m.process_new_records(s, l)
ok("garbage cursor restarts from 0, processed all 4 valid records", res["processed"] == 4, str(res))
sigs = sorted(c["signature"] for c in res["new_clusters"])
ok("walk-back found the older dir's log", any(x.startswith("python:ValueError: boom #") for x in sigs), str(sigs))
ok("no-log signatures for t2/t3", sum(1 for x in sigs if x.startswith("no-log:")) == 2, str(sigs))
# second pass: cursor at EOF -> nothing new
ok("second pass processes nothing", m.process_new_records(s, l)["processed"] == 0)
# cursor beyond EOF -> rotated, restart: same records recur -> counts increment (existing entries, samples appended)
open(os.path.join(s, ".failure_triage.cursor"), "w").write("99999999")
res2 = m.process_new_records(s, l)
ok("cursor > size restarts from top", res2["processed"] == 4 and not res2["new_clusters"], str(res2))
reg = m.load_registry(s)
ok("recurring clusters count incremented", all(e["count"] == 2 for e in reg.values()), str({k: e["count"] for k, e in reg.items()}))
# flail record with bare-generic log -> status signature fallback
s, l = fresh(); d = os.path.join(l, dirname_for(now - 600)); os.makedirs(d)
open(os.path.join(d, "f1.log"), "w").write("model prose only\nCREDITED=0\n")
write_outcomes(s, [rec("f1", now - 300, **{"class": "noop", "status": "no-op"})])
res = m.process_new_records(s, l)
ok("generic log + no-op status -> pipeline:flail cluster", any("pipeline:flail" in c["signature"] for c in res["new_clusters"]), str(res))
# generic log + non-noop status keeps generic
s, l = fresh(); d = os.path.join(l, dirname_for(now - 600)); os.makedirs(d)
open(os.path.join(d, "g1.log"), "w").write("model prose only\n")
write_outcomes(s, [rec("g1", now - 300)])
res = m.process_new_records(s, l)
ok("generic log stays generic when status is not no-op", res["new_clusters"][0]["signature"].startswith("generic:tail-hash"), str(res))

# regression: fixed cluster recurs
s, l = fresh(); d = os.path.join(l, dirname_for(now - 600)); os.makedirs(d)
open(os.path.join(d, "r1.log"), "w").write("ValueError: again\n")
write_outcomes(s, [rec("r1", now - 300)])
m.process_new_records(s, l)
reg = m.load_registry(s); key = next(iter(reg)); reg[key]["status"] = "fixed"; reg[key]["fix_commit"] = "abc1234"
m.save_registry(s, reg)
with open(os.path.join(s, "outcomes.jsonl"), "a") as f:
    f.write(json.dumps(rec("r1", now - 100, item_hash="h2")) + "\n")
res = m.process_new_records(s, l)
ok("regression detected", len(res["regressions"]) == 1 and res["regressions"][0]["fix_commit"] == "abc1234", str(res))
rc, out, err = cli(s, l)
ok("cmd_detect no-new path", rc == 0 and "no new outcomes.jsonl records" in out, out)
# detect with regression + new cluster printed via CLI
s2, l2 = fresh(); d = os.path.join(l2, dirname_for(now - 600)); os.makedirs(d)
open(os.path.join(d, "r1.log"), "w").write("ValueError: again\n")
write_outcomes(s2, [rec("r1", now - 300)])
rc, out, err = cli(s2, l2)
ok("cmd_detect prints NEW cluster", rc == 0 and "NEW  billwatch ::" in out and "1 new failure cluster" in out, out)
reg = m.load_registry(s2); k2 = next(iter(reg)); reg[k2]["status"] = "fixed"; reg[k2]["fix_commit"] = "deadbee"; m.save_registry(s2, reg)
with open(os.path.join(s2, "outcomes.jsonl"), "a") as f:
    f.write(json.dumps(rec("r1", now - 100)) + "\n")
rc, out, err = cli(s2, l2)
ok("cmd_detect prints REGRESSION", "REGRESSION  billwatch" in out and "previously fixed by deadbee" in out, out)
with open(os.path.join(s2, "outcomes.jsonl"), "a") as f:
    f.write(json.dumps(rec("zz", now - 50, **{"class": "landed"})) + "\n")
rc, out, err = cli(s2, l2)
ok("cmd_detect no clusters/regressions line", "no new clusters, no regressions" in out, out)

# ---- digest ---------------------------------------------------------------------------------
s, l = fresh()
old_iso = iso(now - 10 * 3600); new_iso = iso(now - 600)
long_sig = "x" * 200
m.save_registry(s, {
    "billwatch::newsig": {"first_seen": new_iso, "count": 3, "status": "new"},
    "gitlark::oldsig": {"first_seen": old_iso, "count": 9, "status": "new"},
    "gitlark::" + long_sig: {"first_seen": new_iso, "count": 1, "status": "new"},
    "iptv::fixedsig": {"first_seen": old_iso, "count": 4, "status": "fixed", "fix_commit": "c0ffee1",
                        "regression_events": [{"ts": "bad"}, {"ts": old_iso}, {"ts": new_iso}]},
    "iptv::oldreg": {"first_seen": "", "count": 2, "status": "fixed", "fix_commit": "c0ffee2",
                      "regression_events": [{"ts": old_iso}]},
})
rc, out, err = cli(s, l, "--digest", "3")
ok("digest rc 0", rc == 0)
ok("digest NEW line", "NEW: billwatch :: newsig (x3)" in out, out)
ok("digest old cluster not re-announced", "oldsig" not in out)
ok("digest long signature truncated", "…" in out and long_sig not in out)
ok("digest REGRESSION line", "REGRESSION: iptv :: fixedsig (previously fixed by c0ffee1, now seen 4x total)" in out, out)
ok("digest old regression event not in window", "oldreg" not in out)

# ---- ack ------------------------------------------------------------------------------------
s, l = fresh()
m.save_registry(s, {"billwatch::alpha-one": {"status": "new"}, "billwatch::alpha-two": {"status": "new"}, "gitlark::beta": {"status": "new"}})
rc, out, err = cli(s, l, "--ack", "billwatch", "nomatch", "--commit", "c1", "--generator-addressed", "yes", "--yes")
ok("ack no match -> rc1", rc == 1 and "no cluster matches" in err, err)
rc, out, err = cli(s, l, "--ack", "billwatch", "ALPHA", "--commit", "c1", "--generator-addressed", "yes", "--yes")
ok("ack ambiguous -> rc1 listing keys", rc == 1 and "ambiguous" in err and "billwatch::alpha-one" in err and "billwatch::alpha-two" in err, err)
rc, out, err = cli(s, l, "--ack", "gitlark", "beta", "--commit", "c1", "--generator-addressed", "no")
ok("ack non-interactive w/o --yes refused", rc == 1 and "refusing to apply" in err, err)
ok("...and registry unchanged", m.load_registry(s)["gitlark::beta"]["status"] == "new")
rc, out, err = cli(s, l, "--ack", "gitlark", "beta", "--commit", "c1")
ok("ack missing --generator-addressed -> parser error (rc2)", rc == 2 and "requires both" in err, err)
rc, out, err = cli(s, l, "--ack", "gitlark", "beta", "--generator-addressed", "no")
ok("ack missing --commit -> parser error (rc2)", rc == 2, err)
rc, out, err = cli(s, l, "--ack", "gitlark", "beta", "--commit", "c9", "--generator-addressed", "unsure", "--yes")
ok("ack --yes applies", rc == 0 and "acked:" in out and m.load_registry(s)["gitlark::beta"]["fix_commit"] == "c9", out + err)

# interactive confirmation paths (in-process, tty + input patched)
class A: pass
def run_ack(answer):
    a = A(); a.state_dir = s; a.ack = ("billwatch", "alpha-one"); a.commit = "c2"; a.generator_addressed = "yes"; a.yes = False
    real_isatty, real_input = sys.stdin.isatty, builtins.input
    sys.stdin = type("TTY", (), {"isatty": lambda self: True, "read": lambda self, *x: "", "readline": lambda self: ""})()
    builtins.input = lambda prompt="": answer
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = m.cmd_ack(a)
    finally:
        builtins.input = real_input; sys.stdin = sys.__stdin__
    return rc, buf.getvalue()
rc, out = run_ack("n")
ok("interactive 'n' aborts", rc == 1 and "aborted" in out and m.load_registry(s)["billwatch::alpha-one"]["status"] == "new", out)
rc, out = run_ack("YES")
ok("interactive 'YES' applies", rc == 0 and m.load_registry(s)["billwatch::alpha-one"]["status"] == "fixed", out)

# main() in-process (covers argparse wiring of digest/detect/ack through main)
s, l = fresh()
old = sys.argv
sys.argv = ["ovn_failure_triage.py", s, l]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = m.main()
sys.argv = old
ok("main() detect on empty state", rc == 0 and "no new outcomes" in buf.getvalue())

print("failure_triage_more: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
