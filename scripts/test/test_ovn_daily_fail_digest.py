#!/usr/bin/env python3
"""scripts/ovn_daily_fail_digest.py (r11 acct, platform P11): the READ-ONLY 24 h fail digest.

Fixture state (built here, timestamps relative to a fixed --now): outcomes with landed / landed-uncredited / credit-only / reverted / no-op(reverted-red) rows (status text differing only in
counts/shas), a net-zero row, benign scout verdicts, idle skip rows, rows older than the window, a malformed line and an out-of-order old row; a cycle_walltime ledger; a verify shadow log
with fleet and test-pollution (repo=tmp.*) rows; research_trigger_starving.json.
Covers: the numbers, the root-cause grouping, GPU sinks, starvation, walltime, shadow-gate pollution, the backward block reader (vs a naive read, tiny blocks, lines straddling blocks),
the 20 MB-style tail read, READ-ONLY (state dir byte-identical, works on a read-only dir), CLI (--json/--md/--hours/--top, bad args rc 2, missing state rc 0) and MUTATION controls
(a normaliser / window / stale-run mutant must fail the matching assertion). Run: python3 test_ovn_daily_fail_digest.py (exit 0 = all pass)."""
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("OVN_SCRIPTS") or os.path.dirname(HERE)
SRC = os.path.join(SCRIPTS, "ovn_daily_fail_digest.py")
sys.path.insert(0, SCRIPTS)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def load(path, name="digest_under_test"):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


D = load(SRC)
NOW = 1760200000.0   # fixed "now"
iso = lambda ago_h: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - ago_h * 3600))


def row(ago_h, repo, cls, status, sev=None, fr="", dur=60, ts_=0, tr_=0, feat="", ih="", tier="2"):
    sev = sev or {"landed": "good", "reverted": "bad", "noop": "bad", "skipped": "expected"}.get(cls, "neutral")
    return {"ts": iso(ago_h), "repo": repo, "id": "ongoing-" + repo, "type": "aider_fix", "tier": tier, "category": "godot", "class": cls, "severity": sev, "attempt": 1, "attempts": 1,
            "bestn_stop": "", "fail_reason": fr, "status": status, "tokens_sent": ts_, "tokens_recv": tr_, "duration_s": dur, "item_hash": ih, "feat_tag": feat}


def build_state(root, extra_rows=()):
    st = os.path.join(root, "state"); os.makedirs(st)
    rows = [
        # landed: 2 credited, 3 uncredited, 1 credit-only
        row(20, "iptv_apps", "landed", "pushed(tests:pass)", dur=300, feat="F-land"),
        row(19, "xlite", "landed", "pushed(tests:pass)", dur=200, feat="F-land2"),
        row(18, "xlite", "landed-uncredited", "pushed(tests:pass)", sev="neutral", dur=861, feat="F-uncred"),
        row(17, "xlite", "landed-uncredited", "pushed(tests:pass)", sev="neutral"),
        row(16, "iptv_apps", "landed-uncredited", "pushed(tests:pass)", sev="neutral"),
        row(15, "iptv_apps", "credit-only", "pushed(tests:pass) [credit-only]", sev="neutral", dur=77, feat="F-credonly"),
        # bad: 4x no-op(reverted-red) whose status differs only by counts/shas/paths -> ONE signature (fail_reason empty), 2x reverted with fail_reason, 1 net-zero
        row(14, "xlite", "noop", "no-op(reverted-red) [baseline-red:3]", dur=400, ts_=40000, tr_=1000, feat="F-sink"),
        row(13, "xlite", "noop", "no-op(reverted-red) [baseline-red:5]", dur=500, ts_=41000, tr_=1000, feat="F-sink"),
        row(12, "xlite", "noop", "no-op(reverted-red)", dur=450, ts_=42000, tr_=900, feat="F-sink"),
        row(11, "iptv_apps", "noop", "no-op(reverted-red)", dur=100, feat="F-other"),
        row(2.5, "iptv_apps", "reverted", "reverted(commit 4aa9c1c9e2 broke 12 tests)", dur=40, feat="F-other"),
        row(2.2, "iptv_apps", "reverted", "reverted(commit 0badf00d99 broke 7 tests)", dur=50, feat="F-other"),
        row(10, "xlite", "reverted", "reverted(tests-failed)", fr="test-regression", dur=250, feat="F-sink"),
        row(9, "xlite", "reverted", "reverted(tests-failed)", fr="test-regression", dur=250),
        row(8, "iptv_apps", "noop", "no-op(net-zero)", fr="net-zero", dur=90, ts_=9000),
        # benign
        row(7, "iptv_apps", "noop", "no-op(ALREADY-DONE)", sev="neutral", dur=30),
        row(6, "xlite", "noop", "no-op(ungrounded-plan)", sev="neutral", dur=33),
        # idle skips
        row(5, "iptv_apps", "skipped", "skip(exhausted)", fr="queue-exhausted", dur=2),
        row(4, "iptv_apps", "skipped", "skip(exhausted)", fr="queue-exhausted", dur=3),
        row(3, "xlite", "skipped", "skip(exhausted)", fr="queue-exhausted", dur=2),
        # outside the window (30h ago): must not be counted
        row(30, "xlite", "reverted", "reverted(tests-failed)", fr="test-regression", dur=999),
    ] + list(extra_rows)
    # an out-of-order OLD row in the middle of fresh rows must not truncate the read
    rows.insert(5, row(40, "xlite", "reverted", "reverted(tests-failed)", fr="test-regression", dur=1))
    with open(os.path.join(st, "outcomes.jsonl"), "w") as f:
        for i, r in enumerate(rows):
            f.write(json.dumps(r) + "\n")
            if i == 8:
                f.write("{this is not json\n")
    with open(os.path.join(st, "cycle_walltime.jsonl"), "w") as f:
        for r in ({"ts": iso(10), "repo": "xlite", "duration_s": 450, "gen_s": 62, "verify_s": 300, "fixup_s": 45, "verify_basis": "markers"},
                  {"ts": iso(9), "repo": "xlite", "duration_s": 200, "gen_s": 50, "verify_s": 0, "fixup_s": 0, "verify_basis": "none"},
                  {"ts": iso(50), "repo": "xlite", "duration_s": 9999, "gen_s": 1, "verify_s": 1, "fixup_s": 1, "verify_basis": "markers"}):
            f.write(json.dumps(r) + "\n")
    with open(os.path.join(st, "verify_gate_shadow.log"), "w") as f:
        f.write("%s repo=xlite line=3 result=PASS cmd=pytest\n" % iso(8))
        f.write("%s repo=iptv_apps line=9 result=FAIL rc=1 cmd=pytest\n" % iso(7))
        f.write("%s repo=tmp.VdAbPPHC3q line=4 result=NO_VERIFY_CLAUSE\n" % iso(6))
        f.write("%s repo=tmp.VdAbPPHC3q line=4 path_gate=OK target=app/foo.py\n" % iso(5))
        f.write("%s repo=xlite line=1 result=PASS cmd=old\n" % iso(60))
    with open(os.path.join(st, "research_trigger_starving.json"), "w") as f:
        json.dump({"checked_at": NOW, "starving": [{"repo": "xlite", "starving_since": NOW - 6.4 * 3600, "hours": 6.4}]}, f)
    build_state.rows = [r for r in rows if epoch_of(r["ts"]) >= NOW - 24 * 3600]
    return st


def epoch_of(ts):
    return D.epoch_of(ts)


def run_cli(st, *args):
    return subprocess.run([sys.executable, SRC, "--state-dir", st, "--now", str(NOW)] + list(args), capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)


def tree_hash(root):
    h = hashlib.sha256()
    for dp, dn, fn in sorted(os.walk(root)):
        dn.sort()
        for n in sorted(fn):
            p = os.path.join(dp, n)
            st = os.stat(p)
            h.update(("%s|%d|%d\n" % (os.path.relpath(p, root), st.st_size, int(st.st_mtime_ns))).encode())
            h.update(open(p, "rb").read())
    return h.hexdigest()


T = tempfile.mkdtemp(prefix="digest-")
try:
    st = build_state(os.path.join(T, "a"))
    d = D.build(st, 24, NOW, 10)

    # ---- the numbers
    ok("window: 20 in-window rows (the 30h and the out-of-order 40h rows are out), 1 unreadable line", d["window"]["rows"] == 20 and d["window"]["malformed"] == 1, str(d["window"]))
    ok("classes counted over the window only", d["classes"] == {"credit-only": 1, "landed": 2, "landed-uncredited": 3, "noop": 7, "reverted": 4, "skipped": 3}, str(d["classes"]))
    ok("buckets: good 2, bad 9 (4 reverted-red + net-zero + 4 reverted), benign 9; pass rate 2/11 = 18.2", d["buckets"] == {"good": 2, "bad": 9, "benign": 9, "pass_rate": 18.2}, str(d["buckets"]))
    ok("an out-of-order OLD row between fresh rows did not truncate the window (the xlite rows after it are counted)", d["bad"]["by_repo"].get("xlite") == 5, str(d["bad"]["by_repo"]))
    # ---- bad rows by class / repo / signature
    b = d["bad"]
    ok("bad total 9; by class noop 5 / reverted 4", b["total"] == 9 and b["by_class"] == {"noop": 5, "reverted": 4}, str(b))
    ok("by repo xlite 5 / iptv_apps 2 and the repo x class cross-tab", b["by_repo"] == {"iptv_apps": 4, "xlite": 5} and b["by_repo_class"]["xlite"] == {"noop": 3, "reverted": 2}, str(b["by_repo_class"]))
    sig = {s["signature"]: s for s in b["by_signature"]}
    ok("statuses differing only in counts/shas group into ONE signature: 4 x noop/no-op(reverted-red) (a [baseline-red:N] tag differs) and 2 x reverted/reverted(commit <sha> broke N tests)", sig.get("noop/no-op(reverted-red)", {}).get("n") == 4 and sig.get("reverted/reverted(commit <sha> broke N tests)", {}).get("n") == 2, str(list(sig)))
    ok("a fail_reason is the signature when present (reverted/test-regression x2, noop/net-zero x1)", sig.get("reverted/test-regression", {}).get("n") == 2 and sig.get("noop/net-zero", {}).get("n") == 1)
    ok("signatures are ordered by count then name; first is the 4x one", b["by_signature"][0]["signature"] == "noop/no-op(reverted-red)")
    ok("the example is the LATEST row of the signature with its exact status text", sig["noop/no-op(reverted-red)"]["example"]["status"] == "no-op(reverted-red)" and sig["noop/no-op(reverted-red)"]["example"]["repo"] == "iptv_apps")
    ok("signature repos / tokens / seconds aggregate", sig["noop/no-op(reverted-red)"]["repos"] == {"iptv_apps": 1, "xlite": 3} and sig["noop/no-op(reverted-red)"]["seconds"] == 400 + 500 + 450 + 100 and sig["noop/no-op(reverted-red)"]["tokens"] == 41000 + 42000 + 42900, str(sig["noop/no-op(reverted-red)"]))
    # ---- landing accounting
    ok("landing: 2 landed, 3 uncredited (60% of pushes), 1 credit-only, 1 net-zero", d["landing"] == {"landed": 2, "landed_uncredited": 3, "credit_only": 1, "net_zero": 1, "uncredited_share_of_pushes": 0.6}, str(d["landing"]))
    # ---- starvation
    ok("starvation: idle-skip rows + seconds per repo, and the trigger-check's starving hours merged in",
       d["starvation"] == {"iptv_apps": {"skip_exhausted_rows": 2, "skip_exhausted_seconds": 5}, "xlite": {"skip_exhausted_rows": 1, "skip_exhausted_seconds": 2, "starving_hours": 6.4}}, str(d["starvation"]))
    # ---- GPU sinks
    sinks = {s["item"]: s for s in d["gpu_sinks"]}
    ok("GPU sinks: F-sink (landed nothing) leads with its seconds; items that landed (F-land) are excluded", d["gpu_sinks"][0]["item"] == "F-sink" and "F-land" not in sinks and "F-land2" not in sinks, str(d["gpu_sinks"]))
    ok("GPU sinks: an item whose cycles pushed code as landed-uncredited (F7) is NOT a sink (live false positive: a 14 min test-unlock item listed although it pushed)", "F-uncred" not in sinks, str(d["gpu_sinks"]))
    ok("GPU sinks: a credit-only push (progress file only, no code) still counts as landing nothing", "F-credonly" in sinks and sinks["F-credonly"]["seconds"] == 77, str(sinks.get("F-credonly")))
    _sd = os.path.join(T, "scriptsdir"); os.makedirs(_sd)
    for _f in ("ovn_daily_fail_digest.py", "ovn_outcome_buckets.py"):
        shutil.copy(os.path.join(SCRIPTS, _f), _sd)
    _env = {k: v for k, v in os.environ.items() if k != "PYTHONDONTWRITEBYTECODE"}
    subprocess.run([sys.executable, os.path.join(_sd, "ovn_daily_fail_digest.py"), "--state-dir", st, "--json"], capture_output=True, text=True, env=_env, timeout=60)
    ok("running the digest from a scripts dir creates no __pycache__ there (read-only promise; PYTHONDONTWRITEBYTECODE not set)", not os.path.exists(os.path.join(_sd, "__pycache__")), str(os.listdir(_sd)))
    ok("F-sink: 4 cycles, 400+500+450+250 s, share of busy time computed (skips excluded from busy)", sinks["F-sink"]["cycles"] == 4 and sinks["F-sink"]["seconds"] == 1600 and sinks["F-sink"]["share_of_busy"] is not None, str(sinks.get("F-sink")))
    busy = sum(int(r["duration_s"]) for r in build_state.rows if r["class"] != "skipped")
    ok("busy seconds = every non-skipped in-window row's duration (skip rows excluded)", d["busy_seconds"] == busy, "%s vs %s" % (d["busy_seconds"], busy))
    # ---- walltime
    ok("walltime: per repo sums over the window; verify measured only on marker rows (1 of 2); the 50h row is out", d["walltime"] == {"xlite": {"rows": 2, "busy_s": 650, "gen_s": 112, "verify_s": 300, "fixup_s": 45, "rows_with_verify_markers": 1}}, str(d["walltime"]))
    # ---- shadow gate + pollution
    vs = d["verify_shadow"]
    ok("shadow rows of FLEET repos in the window counted by result (the 60h row is out; the 2 tmp.* rows are NOT counted: intake package P8)", vs["rows"] == 2 and vs["results"] == {"result=FAIL": 1, "result=PASS": 1}, str(vs))
    ok("foreign (repo=tmp.*) rows are labelled as test pollution with an example, outside the counts", vs["foreign_rows"] == 2 and vs["foreign_labels"] == {"tmp.VdAbPPHC3q": 2} and vs["foreign_examples"] and "repo=tmp.VdAbPPHC3q" in vs["foreign_examples"][0], str(vs))
    ok("not_covered names the signals that need logs/git", len(d["not_covered"]) == 4)

    # ---- CLI + markdown + JSON
    r = run_cli(st)
    md = r.stdout
    ok("CLI default = markdown, rc 0", r.returncode == 0 and md.startswith("# Fleet fail digest - last 24h"), md[:80])
    ok("markdown: headline numbers", "20 outcome rows (1 unreadable). good 2 / bad 9 / benign 9, pass rate 18.2%." in md and "3 landed-uncredited (60% of pushes)" in md and "1 credit-only" in md, md[:400])
    ok("markdown: the signature table has the exact example status text", "| 4 | `noop/no-op(reverted-red)` |" in md and "`reverted(commit 0badf00d99 broke 7 tests)`" in md, md)
    ok("markdown: GPU sink, starvation, walltime and pollution WARNING sections", "## GPU time that landed nothing" in md and "- xlite: 1 idle-skip rows" in md and "starving 6.4h" in md and "measured on 1 rows" in md and "WARNING: 2 row(s) from non-fleet repo labels" in md)
    r = run_cli(st, "--json")
    j = json.loads(r.stdout)
    ok("--json prints the same document as build()", r.returncode == 0 and j["buckets"] == d["buckets"] and j["bad"]["total"] == 9 and j["window"]["rows"] == 20)
    r = run_cli(st, "--json", "--top", "1")
    ok("--top 1 limits signatures and sinks", len(json.loads(r.stdout)["bad"]["by_signature"]) == 1 and len(json.loads(r.stdout)["gpu_sinks"]) == 1)
    r = run_cli(st, "--json", "--hours", "6.5")
    jj = json.loads(r.stdout)
    ok("--hours 6.5 narrows the window (rows from <= 6.5 h ago only: 3 skips + the 2 reverted + ... )", jj["window"]["rows"] == 6 and jj["window"]["hours"] == 6.5 and jj["bad"]["total"] == 2, str(jj["window"]))
    ok("bad argument => rc 2 with usage on stderr", subprocess.run([sys.executable, SRC, "--bogus"], capture_output=True, text=True).returncode == 2 and subprocess.run([sys.executable, SRC, "--hours"], capture_output=True, text=True).returncode == 2)
    r = subprocess.run([sys.executable, SRC, "--state-dir", os.path.join(T, "nope"), "--now", str(NOW)], capture_output=True, text=True)
    ok("missing state dir => rc 0 and an empty digest (never raises into a scheduled review)", r.returncode == 0 and "0 outcome rows" in r.stdout and "none." in r.stdout)

    # ---- READ-ONLY
    h0 = tree_hash(os.path.join(T, "a"))
    run_cli(st); run_cli(st, "--json")
    ok("READ-ONLY: the state dir (names, sizes, mtimes, bytes) is identical after runs", tree_hash(os.path.join(T, "a")) == h0)
    ro = os.path.join(T, "a")
    modes = []
    for dp, dn, fn in os.walk(ro):
        for n in dn + fn:
            p = os.path.join(dp, n); modes.append((p, os.stat(p).st_mode)); os.chmod(p, stat.S_IRUSR | stat.S_IXUSR if os.path.isdir(p) else stat.S_IRUSR)
    os.chmod(ro, stat.S_IRUSR | stat.S_IXUSR)
    r = run_cli(st)
    ok("READ-ONLY: works on a read-only state dir (it writes nothing)", r.returncode == 0 and "20 outcome rows" in r.stdout)
    os.chmod(ro, stat.S_IRWXU)
    for p, m in modes:
        os.chmod(p, m)
    src_text = open(SRC).read()
    ok("READ-ONLY (static): the script opens no file for writing and runs no subprocess/git", "open(" in src_text and not any(w in src_text for w in ("'w')", '"w")', "'a')", '"a")', "'wb'", "subprocess", "os.system", "os.remove", "shutil")))

    # ---- the backward block reader vs a naive read (tiny blocks, lines straddling blocks)
    lines = ["%s repo=r line=%d result=PASS %s" % (iso(i / 10.0), i, "x" * (i % 37)) for i in range(400, 0, -1)]   # oldest first
    pth = os.path.join(T, "tail.log")
    open(pth, "w").write("\n".join(lines) + "\n")
    ts_plain = lambda ln: D.epoch_of(ln.split(" ", 1)[0])
    cut = NOW - 12 * 3600
    naive = [l for l in lines if ts_plain(l) >= cut]
    for blk in (7, 64, 1000, 1 << 20):
        got = list(reversed(list(D.read_tail_lines(pth, cut, ts_plain, block=blk))))
        ok("tail reader == naive read at block=%d (%d lines)" % (blk, len(naive)), got == naive, "%d vs %d" % (len(got), len(naive)))
    big = os.path.join(T, "big.jsonl")
    with open(big, "w") as f:
        for i in range(40000):
            f.write(json.dumps(row(100 + i / 1000.0, "xlite", "skipped", "skip(exhausted)")) + "\n")
        for i in range(30):
            f.write(json.dumps(row(2 - i / 100.0, "xlite", "noop", "no-op(reverted-red)")) + "\n")
    t0 = time.time()
    rws, bad = D.load_rows(big, NOW - 24 * 3600)
    ok("a 10 MB log with 30 fresh rows: only the 30 are read and it is fast (< 1.5 s)", len(rws) == 30 and bad == 0 and time.time() - t0 < 1.5, "%d rows %.2fs" % (len(rws), time.time() - t0))
    open(os.path.join(T, "empty.jsonl"), "w").close()
    ok("empty / missing files => no rows, no error", D.load_rows(os.path.join(T, "empty.jsonl"), 0) == ([], 0) and D.load_rows(os.path.join(T, "missing.jsonl"), 0) == ([], 0))

    # ---- normaliser unit
    ok("core_of: counts, shas, paths and [tags] are normalised away", D.core_of("No-Op(reverted-red) [baseline-red:3] 4aa9c1c9e2 in app/x/y.py rc=124") == "no-op(reverted-red) <sha> in <path> rc=n".replace("rc=n", "rc=N"), D.core_of("No-Op(reverted-red) [baseline-red:3] 4aa9c1c9e2 in app/x/y.py rc=124"))
    ok("core_of: empty status and a 200-char status are bounded", D.core_of("") == "(empty status)" and len(D.core_of("x" * 200)) == 70)

    # ---- MUTATION controls: each mutant must break the matching assertion
    def mutant(a, b, name):
        s = open(SRC).read()
        assert s.count(a) == 1, a
        mp = os.path.join(T, name + ".py")
        open(mp, "w").write(s.replace(a, b))
        shutil.copy(os.path.join(SCRIPTS, "ovn_outcome_buckets.py"), os.path.join(T, "ovn_outcome_buckets.py"))   # the mutant imports it from its own dir
        return load(mp, name)
    m1 = mutant('s = _NUM.sub("N", s)', 's = s', "m_nonum")
    sigs1 = {x["signature"]: x["n"] for x in m1.build(st, 24, NOW, 10)["bad"]["by_signature"]}
    ok("MUTATION: without digit normalisation 'broke 12 tests' / 'broke 7 tests' no longer group", sigs1.get("reverted/reverted(commit <sha> broke N tests)") is None and sigs1.get("noop/no-op(reverted-red)") == 4, str(sigs1))
    m2 = mutant('s = _SHA.sub("<sha>", s)', 's = s', "m_nosha")
    sigs2 = {x["signature"]: x["n"] for x in m2.build(st, 24, NOW, 10)["bad"]["by_signature"]}
    ok("MUTATION: without sha normalisation the two shas no longer group", sigs2.get("reverted/reverted(commit <sha> broke N tests)") is None and sum(1 for k in sigs2 if k.startswith("reverted/reverted(commit")) == 2, str(sigs2))
    s_all = open(SRC).read()
    a1, a2 = 'if isinstance(r, dict) and epoch_of(r.get("ts")) >= cutoff:', 'if e and e < cutoff_epoch:'
    assert s_all.count(a1) == 1 and s_all.count(a2) == 1
    mp3 = os.path.join(T, "m_nocut.py"); open(mp3, "w").write(s_all.replace(a1, 'if isinstance(r, dict):').replace(a2, 'if False:'))
    shutil.copy(os.path.join(SCRIPTS, "ovn_outcome_buckets.py"), os.path.join(T, "ovn_outcome_buckets.py"))
    m3 = load(mp3, "m_nocut")
    ok("MUTATION: without the window check (both layers) the out-of-window rows are counted (rows 20 -> more)", m3.build(st, 24, NOW, 10)["window"]["rows"] > 20)
    m4 = mutant('stale_stop=25', 'stale_stop=1', "m_stale1")
    ok("MUTATION: stale_stop=1 lets one stray old row truncate the window (the out-of-order fixture row)", m4.build(st, 24, NOW, 10)["window"]["rows"] < 20)
    try:
        m8 = mutant('for k, v in items.items() if v["landed"] == 0 and v["seconds"] > 0', 'for k, v in items.items() if v["seconds"] > 0', "m_sinks_landed")
        ok("MUTATION: sinks that include landed items would list F-land (the sink assertion would fail)", "F-land" in {s["item"] for s in m8.build(st, 24, NOW, 10)["gpu_sinks"]})
    except AssertionError:
        ok("MUTATION: sink filter present in source", False)
    try:
        m9 = mutant('if r.get("class") in LANDING_CLASSES:', 'if r.get("class") == "landed":', "m_sinks_uncred")
        ok("MUTATION: counting only class=landed makes F-uncred a false sink (the F7 assertion would fail)", "F-uncred" in {s["item"] for s in m9.build(st, 24, NOW, 10)["gpu_sinks"]})
    except AssertionError:
        ok("MUTATION: landing-class filter present in source", False)
    ok("MUTATION sanity: the unmutated module excludes landed items from the sinks", "F-land" not in {s["item"] for s in D.build(st, 24, NOW, 10)["gpu_sinks"]})
finally:
    for dp, dn, fn in os.walk(T):
        for n in dn + fn:
            try:
                os.chmod(os.path.join(dp, n), stat.S_IRWXU)
            except OSError:
                pass
    shutil.rmtree(T, ignore_errors=True)

print("ovn_daily_fail_digest: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
