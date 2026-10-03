#!/usr/bin/env python3
"""Tests for the 2026-10-03 observability track (Phase 6):
  - ovn_failure_triage.py: deploy-failure + landed-without-commit clusters (ack/regression semantics)
  - ovn_cycle_walltime.py: per-cycle generation/verify/other ledger + 3-cycle >50% alert
  - ovn_gpu_util_check.sh + ovn_stats.py --gpu-alert: GPU busy% sampling + deduped alert
  - ovn_real_passrate.py / ovn_stats.py --since: honest pass rate
Fixture rows are shaped from real rows on the box (state/outcomes.jsonl, qa_ledger.jsonl,
staging_deploys/iptv_apps.json as of 2026-10-03). Every behavior has a NEGATIVE control (the seeded
bad input is caught) and a BENIGN control (clean input stays quiet).
Run: python3 test_observability.py  (exit 0 = all pass). No pytest dependency.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("OVN_SCRIPTS") or os.path.dirname(HERE)
sys.path.insert(0, SCRIPTS)
TRI = os.path.join(SCRIPTS, "ovn_failure_triage.py")
WALL = os.path.join(SCRIPTS, "ovn_cycle_walltime.py")
STATS = os.path.join(SCRIPTS, "ovn_stats.py")
GPU = os.path.join(SCRIPTS, "ovn_gpu_util_check.sh")
REAL = os.path.join(SCRIPTS, "ovn_real_passrate.py")

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def iso(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


def wjl(path, rows):
    with open(path, "a") as f:
        for r in rows:
            f.write((r if isinstance(r, str) else json.dumps(r)) + "\n")


def outcome(ts, repo, cls, sev, status, dur=100, ts_=0, tr_=0, ih="", fr="", **kw):
    r = {"ts": ts, "repo": repo, "id": "ongoing-" + repo.replace("_", "-"), "type": "aider_fix", "tier": "2",
         "category": "endpoint", "class": cls, "severity": sev, "attempt": 1, "attempts": 1, "bestn_stop": "",
         "fail_reason": fr, "status": status, "tokens_sent": ts_, "tokens_recv": tr_, "duration_s": dur,
         "item_hash": ih, "feat_tag": ""}
    r.update(kw)
    return r


def ledger(ts, repo, basis, commits, ih=""):
    return {"kind": "landed", "repo": repo, "ts": ts, "commit_basis": basis, "commits": commits,
            "item_hash": ih, "id": "ongoing-" + repo, "status": "pushed(tests:pass)"}


def run(cmd, env=None, **kw):
    e = dict(os.environ)
    e["NTFY_SERVER"] = "http://127.0.0.1:9"   # tests must never reach ntfy.sh or the relay
    e.update(env or {})
    return subprocess.run(cmd, capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL, timeout=120, **kw)


def mk():
    d = tempfile.mkdtemp(prefix="obs-")
    os.makedirs(os.path.join(d, "state"))
    os.makedirs(os.path.join(d, "logs"))
    return d


def tri(d, *extra):
    return run([sys.executable, TRI, os.path.join(d, "state"), os.path.join(d, "logs")] + list(extra))


def registry(d):
    try:
        return json.load(open(os.path.join(d, "state", "failure_clusters.json")))
    except Exception:
        return {}


# ------------------------------------------------------------------ triage: deploy failures
def deploys(d, repo, specs):
    os.makedirs(os.path.join(d, "state", "staging_deploys"), exist_ok=True)
    deps = [{"id": i, "status": st, "createdAt": ca, "meta": {"commitHash": ch * 40, "branch": "develop"}}
            for i, st, ca, ch in specs]
    json.dump({"repo": repo, "fetched_at": 1791038322.9, "deployments": deps},
              open(os.path.join(d, "state", "staging_deploys", repo + ".json"), "w"))


def test_deploy_failures():
    d = mk()
    try:
        # BENIGN control: only SUCCESS/REMOVED deploys -> no cluster
        deploys(d, "billwatch", [("b1", "SUCCESS", "2026-10-03T06:02:33Z", "a"), ("b2", "REMOVED", "2026-10-03T05:02:35Z", "b")])
        r = tri(d)
        ok("deploy benign rc", r.returncode == 0, r.stderr)
        ok("deploy benign: no cluster", registry(d) == {}, str(registry(d)))
        # NEGATIVE control: the real iptv shape (2 FAILED, 1 SUCCESS) -> one cluster, count 2
        deploys(d, "iptv_apps", [("f1", "FAILED", "2026-10-03T14:10:37.412Z", "d"), ("f2", "FAILED", "2026-10-03T07:02:19.355Z", "9"),
                                 ("s1", "SUCCESS", "2026-10-03T06:02:33.989Z", "4")])
        r = tri(d)
        reg = registry(d)
        key = "iptv_apps::deploy-failed:staging"
        ok("deploy cluster created", key in reg, str(list(reg)))
        ok("deploy count 2", reg.get(key, {}).get("count") == 2, str(reg.get(key)))
        ok("deploy NEW printed", "NEW  iptv_apps :: deploy-failed:staging" in r.stdout, r.stdout)
        ok("deploy commit sample", "dddddddd" in reg.get(key, {}).get("sample_item_hashes", []))
        # idempotent: same file, nothing new
        r = tri(d)
        ok("deploy idempotent count", registry(d)[key]["count"] == 2, str(registry(d)[key]))
        ok("deploy idempotent no NEW", "NEW " not in r.stdout, r.stdout)
        # ack, then a NEW failed deploy is a REGRESSION that cron would push high-priority
        a = tri(d, "--ack", "iptv_apps", "deploy-failed", "--commit", "fix123", "--generator-addressed", "no", "--yes")
        ok("deploy ack ok", a.returncode == 0 and registry(d)[key]["status"] == "fixed", a.stdout + a.stderr)
        deploys(d, "iptv_apps", [("f3", "FAILED", "2026-10-03T15:10:00Z", "e"), ("f1", "FAILED", "2026-10-03T14:10:37.412Z", "d"),
                                 ("f2", "FAILED", "2026-10-03T07:02:19.355Z", "9")])
        r = tri(d)
        ok("deploy regression line", "REGRESSION  iptv_apps :: deploy-failed:staging (previously fixed by fix123" in r.stdout, r.stdout)
        # BENIGN control after ack: a later SUCCESS adds nothing
        deploys(d, "iptv_apps", [("s9", "SUCCESS", "2026-10-03T16:10:00Z", "f"), ("f3", "FAILED", "2026-10-03T15:10:00Z", "e")])
        r = tri(d)
        ok("deploy success after ack quiet", "REGRESSION" not in r.stdout, r.stdout)
        # garbage + deploy_status*.json shape + absence tolerated
        open(os.path.join(d, "state", "staging_deploys", "junk.json"), "w").write("{not json")
        json.dump({"gitlark": [{"id": "g1", "status": "CRASHED", "createdAt": "2026-10-03T10:00:00Z"}]},
                  open(os.path.join(d, "state", "deploy_status.json"), "w"))
        r = tri(d)
        ok("garbage tolerated rc", r.returncode == 0, r.stderr)
        ok("deploy_status cluster", "gitlark::deploy-failed:prod" in registry(d), str(list(registry(d))))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = mk()
    try:
        r = tri(d)   # nothing at all: no outcomes, no deploys, no ledger
        ok("absence tolerated", r.returncode == 0 and registry(d) == {}, r.stdout + r.stderr)
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------------ triage: landed without commit
def test_landed_without_commit():
    d = mk()
    try:
        L = os.path.join(d, "state", "qa_ledger.jsonl")
        wjl(L, [ledger("2026-10-03T13:24:10Z", "iptv_apps", "time-window", ["8fa14ddb" * 5]),     # BENIGN: real commit
                ledger("2026-10-03T13:50:00Z", "billwatch", "no-clone", []),                      # BENIGN: could not look
                dict(ledger("2026-10-03T13:55:00Z", "gitlark", "none", []), status="stage(higher-tier)")])  # BENIGN: stage handoff
        r = tri(d)
        ok("lwc benign: no cluster", registry(d) == {}, str(registry(d)))
        wjl(L, [ledger("2026-10-03T14:16:30Z", "xlite", "none", [], "4b4ca7216beeeb74e7fb9aee2b923c20"),
                ledger("2026-10-03T14:50:00Z", "xlite", "none", [], "4b4ca7216beeeb74e7fb9aee2b923c20")])
        r = tri(d)
        key = "xlite::landed-without-commit"
        ok("lwc cluster", key in registry(d), str(registry(d)))
        ok("lwc count 2", registry(d).get(key, {}).get("count") == 2, str(registry(d).get(key)))
        ok("lwc only xlite", list(registry(d)) == [key], str(list(registry(d))))
        r = tri(d)
        ok("lwc cursor idempotent", registry(d)[key]["count"] == 2, str(registry(d)[key]))
        # unterminated trailing line must not be consumed (or counted twice later)
        with open(L, "a") as f:
            f.write(json.dumps(ledger("2026-10-03T15:16:30Z", "xlite", "none", [])))   # no newline yet
        tri(d)
        ok("lwc partial line not consumed", registry(d)[key]["count"] == 2, str(registry(d)[key]))
        with open(L, "a") as f:
            f.write("\n")
        tri(d)
        ok("lwc completed line counted once", registry(d)[key]["count"] == 3, str(registry(d)[key]))
        # ack -> recurrence is a REGRESSION
        a = tri(d, "--ack", "xlite", "landed-without", "--commit", "abc1234", "--generator-addressed", "unsure", "--yes")
        ok("lwc ack", a.returncode == 0 and registry(d)[key]["status"] == "fixed", a.stdout + a.stderr)
        wjl(L, [ledger("2026-10-03T16:00:00Z", "xlite", "none", [])])
        r = tri(d)
        ok("lwc regression", "REGRESSION  xlite :: landed-without-commit" in r.stdout, r.stdout)
        # BENIGN control after ack
        wjl(L, [ledger("2026-10-03T17:00:00Z", "xlite", "time-window", ["c" * 40])])
        r = tri(d)
        ok("lwc benign after ack quiet", "REGRESSION" not in r.stdout, r.stdout)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_seed():
    d = mk()
    try:
        L = os.path.join(d, "state", "qa_ledger.jsonl")
        wjl(L, [ledger("2026-10-03T14:16:30Z", "xlite", "none", [])] * 3)
        deploys(d, "iptv_apps", [("d1", "FAILED", "2026-10-02T10:00:00Z", "abc12345")])
        r = tri(d, "--seed")
        ok("seed rc + message", r.returncode == 0 and "seeded: 1" in r.stdout, r.stdout + r.stderr)
        tri(d)
        ok("seeded: history is not NEW", registry(d) == {}, str(registry(d)))
        wjl(L, [ledger("2026-10-03T15:00:00Z", "xlite", "none", [])])
        tri(d)
        ok("seeded: new phantom row after seed still clusters", "xlite::landed-without-commit" in registry(d), str(registry(d)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_triage_still_clusters_outcomes():
    """Existing behavior intact: a BAD outcomes row still clusters, alongside the new sources."""
    d = mk()
    try:
        wjl(os.path.join(d, "state", "outcomes.jsonl"),
            [outcome("2026-10-03T13:30:12Z", "iptv_apps", "noop", "bad", "no-op(reverted-red)", fr="test-red")])
        wjl(os.path.join(d, "state", "qa_ledger.jsonl"), [ledger("2026-10-03T14:16:30Z", "xlite", "none", [])])
        r = tri(d)
        reg = registry(d)
        ok("outcomes cluster + lwc cluster", len(reg) == 2 and any(k.startswith("iptv_apps::") for k in reg)
           and "xlite::landed-without-commit" in reg, str(list(reg)))
        ok("processed counts both", "processed 2 new record(s)" in r.stdout, r.stdout)
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------------ cycle walltime
def local_dir(epoch):
    return time.strftime("%Y%m%d-%H%M%S", time.localtime(epoch))


def cycle_log(d, epoch, rid, text):
    p = os.path.join(d, "logs", local_dir(epoch))
    os.makedirs(p, exist_ok=True)
    open(os.path.join(p, rid + ".log"), "w").write(text)


XLITE_LOG = ("Tokens: 14k sent, 342 received.\n--- verify: GUT tests in . (90s cap) ---\n"
             + "".join("--- auto-credit: INDETERMINATE line %d (tests/test_damage_preview_projected.gd) - VERIFY timed out "
                       "(rc=124) after 900s; item left open, not counted as a failed attempt ---\n" % n for n in (1837, 1838, 1839)))


def wall(d, now=None, *extra):
    cmd = [sys.executable, WALL, os.path.join(d, "state"), os.path.join(d, "logs")]
    if now is not None:
        cmd += ["--now", str(now)]
    return run(cmd + list(extra))


def ledger_rows(d):
    p = os.path.join(d, "state", "cycle_walltime.jsonl")
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []


def alerts(d):
    p = os.path.join(d, "state", "alerts.log")
    return [l for l in open(p).read().splitlines() if "cycle-walltime" in l] if os.path.exists(p) else []


def test_walltime():
    d = mk()
    try:
        base = time.time() - 6 * 3600
        O = os.path.join(d, "state", "outcomes.jsonl")
        # xlite: real-shaped rows (2778s, 42000 sent, 644 recv) with 3 x 900s logged verify timeouts
        for k in range(3):
            e = base + k * 3300
            cycle_log(d, e - 60, "ongoing-xlite", XLITE_LOG)
            wjl(O, [outcome(iso(e), "xlite", "landed", "good", "pushed(tests:pass)", dur=2778, ts_=42000, tr_=644)])
        # iptv: real-shaped generation-dominated rows (242s, 98900 sent, 3325 recv) -> BENIGN control
        for k in range(3):
            wjl(O, [outcome(iso(base + 100 + k * 600), "iptv_apps", "landed", "good", "pushed(tests:pass)", dur=242,
                            ts_=98900, tr_=3325)])
        wjl(O, ["{this is a malformed row"])
        r = wall(d, base + 3 * 3300 + 10)
        rows = ledger_rows(d)
        ok("walltime rc", r.returncode == 0, r.stderr)
        ok("walltime 6 rows", len(rows) == 6, str(len(rows)))
        x = [r_ for r_ in rows if r_["repo"] == "xlite"]
        ok("xlite verify_s from log", all(r_["verify_s"] == 2700 for r_ in x), str(x[:1]))
        ok("xlite nongen > 0.9", all(r_["nongen_frac"] > 0.9 for r_ in x), str(x[:1]))
        ok("xlite sums to duration", all(abs(r_["gen_s"] + r_["verify_s"] + r_["other_s"] - r_["duration_s"]) <= 1 for r_ in x), str(x[:1]))
        ok("basis est-tokens", all(r_["basis"] == "est-tokens" for r_ in x))
        i_ = [r_ for r_ in rows if r_["repo"] == "iptv_apps"]
        ok("iptv nongen < 0.5 (benign)", all(r_["nongen_frac"] < 0.5 for r_ in i_), str(i_[:1]))
        al = alerts(d)
        ok("one alert, xlite only", len(al) == 1 and "xlite" in al[0], str(al))
        # cursor: nothing re-ledgered
        wall(d, base + 3 * 3300 + 20)
        ok("cursor idempotent", len(ledger_rows(d)) == 6, str(len(ledger_rows(d))))
        # dedup 6h: a 4th bad cycle within 6h -> no second line; after 6h -> a second line
        wjl(O, [outcome(iso(base + 4 * 3300), "xlite", "landed", "good", "pushed(tests:pass)", dur=2778, ts_=42000, tr_=644)])
        wall(d, base + 4 * 3300 + 10)
        ok("dedup within 6h", len(alerts(d)) == 1, str(alerts(d)))
        wjl(O, [outcome(iso(base + 5 * 3300), "xlite", "landed", "good", "pushed(tests:pass)", dur=2778, ts_=42000, tr_=644)])
        wall(d, base + 3 * 3300 + 10 + 6 * 3600 + 60)
        ok("re-alert after 6h", len(alerts(d)) == 2, str(alerts(d)))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    # NEGATIVE/BENIGN streak control: two bad then a good cycle -> no alert
    d = mk()
    try:
        base = time.time() - 3600
        O = os.path.join(d, "state", "outcomes.jsonl")
        wjl(O, [outcome(iso(base + 1), "xlite", "landed", "good", "x", dur=2000, ts_=42000, tr_=644),
                outcome(iso(base + 2), "xlite", "landed", "good", "x", dur=2000, ts_=42000, tr_=644),
                outcome(iso(base + 3), "xlite", "landed", "good", "x", dur=200, ts_=60000, tr_=4000)])
        wall(d, base + 10)
        ok("streak broken by a generation-heavy cycle: no alert", alerts(d) == [], str(alerts(d)))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    # stage_runs basis: measured step seconds are used
    d = mk()
    try:
        base = time.time() - 3600
        sr = os.path.join(d, "state", "stage_runs")
        os.makedirs(sr)
        wjl(os.path.join(sr, "xlite-RUN1.jsonl"), [{"run": "RUN1", "event": "decomposed", "steps": 2},
                                                   {"run": "RUN1", "step": 0, "attempt": 1, "duration_s": 300},
                                                   {"run": "RUN1", "step": 1, "attempt": 1, "duration_s": 100},
                                                   {"run": "RUN1", "event": "verify", "verified": False}])
        wjl(os.path.join(d, "state", "outcomes.jsonl"),
            [outcome(iso(base), "xlite", "noop", "bad", "no-op(stage-unverified) stage(runner)", dur=1000, stage_run="RUN1")])
        wall(d, base + 10)
        rw = ledger_rows(d)
        ok("stage_runs basis + gen 400", rw and rw[0]["basis"] == "stage_runs" and rw[0]["gen_s"] == 400, str(rw))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_walltime_scale():
    """Blocker regression: a few thousand rows + logs must finish quickly (index built once),
    first run backfills only the last 24h, a second instance is locked out, no duplicates."""
    d = mk()
    try:
        now = time.time()
        O = os.path.join(d, "state", "outcomes.jsonl")
        rows = []
        for k in range(3000):
            e = now - 3600 * 20 + k * 5
            rows.append(outcome(iso(e), "iptv_apps", "landed", "good", "pushed(tests:pass)", dur=200,
                                ts_=98900, tr_=3325, id="ongoing-iptv-apps"))
            if k % 3 == 0:
                cycle_log(d, e - 30, "ongoing-iptv-apps", "Tokens: 1k sent.\n")
        # 500 rows older than the backfill window must be skipped on the first run
        for k in range(500):
            rows.append(outcome(iso(now - 3600 * 60 + k), "iptv_apps", "landed", "good", "x", dur=200, ts_=1, tr_=1))
        rows.sort(key=lambda r: r["ts"])
        wjl(O, rows)
        for k in range(2000):   # extra unrelated log dirs to make the index non-trivial
            os.makedirs(os.path.join(d, "logs", "2020%04d-%06d" % (k % 1200 + 101, k)), exist_ok=True)
        t0 = time.time()
        r = wall(d, now)
        dt = time.time() - t0
        n = len(ledger_rows(d))
        ok("3500-row first run is fast (<60s)", r.returncode == 0 and dt < 60, "%.1fs %s" % (dt, r.stderr))
        ok("first run backfills only the last 24h", n == 3000, str(n))
        r = wall(d, now)
        ok("second run adds nothing (cursor)", len(ledger_rows(d)) == 3000, str(len(ledger_rows(d))))
        # lock: a held lock makes a concurrent run a no-op (no duplicate appends)
        import fcntl
        wjl(O, [outcome(iso(now - 10), "iptv_apps", "landed", "good", "x", dur=200, ts_=1, tr_=1)])
        lf = open(os.path.join(d, "state", ".cycle_walltime.lock"), "w")
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        wall(d, now)
        ok("locked: concurrent run is a no-op", len(ledger_rows(d)) == 3000, str(len(ledger_rows(d))))
        fcntl.flock(lf, fcntl.LOCK_UN)
        lf.close()
        wall(d, now)
        ok("unlocked: run picks the new row up", len(ledger_rows(d)) == 3001, str(len(ledger_rows(d))))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    # est-tokens-only slow lane must not alert (negative control is the xlite verify-timeout test)
    d = mk()
    try:
        base = time.time() - 3600
        wjl(os.path.join(d, "state", "outcomes.jsonl"),
            [outcome(iso(base + k), "billwatch", "landed", "good", "x", dur=2000, ts_=1000, tr_=100) for k in range(4)])
        wall(d, base + 100)
        ok("est-tokens-only streak: no alert", alerts(d) == [] and len(ledger_rows(d)) == 4, str(alerts(d)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------------ GPU util
def stub_smi(d, body):
    p = os.path.join(d, "fake-smi.sh")
    open(p, "w").write("#!/usr/bin/env bash\n" + body + "\n")
    os.chmod(p, 0o755)
    return p


def gpu_env(d, tasks_enabled=True):
    tf = os.path.join(d, "tasks.json")
    json.dump([{"id": "ongoing-xlite", "enabled": tasks_enabled}, {"id": "ongoing-x", "enabled": False}], open(tf, "w"))
    return {"OVN_STATE_DIR": os.path.join(d, "state"), "OVN_TASKS_FILE": tf}


def gpu_alerts(d):
    p = os.path.join(d, "state", "alerts.log")
    return [l for l in open(p).read().splitlines() if "gpu-util" in l] if os.path.exists(p) else []


def test_gpu():
    d = mk()
    try:
        env = gpu_env(d)
        # sampling: stub nvidia-smi
        env["OVN_NVIDIA_SMI"] = stub_smi(d, 'echo "37, 23689"')
        r = run(["bash", GPU], env)
        lg = os.path.join(d, "state", "gpu_util.log")
        line = open(lg).read().split() if os.path.exists(lg) else []
        ok("sample appended", r.returncode == 0 and len(line) == 3 and line[1] == "37" and line[2] == "23689", r.stdout + r.stderr + str(line))
        env["OVN_NVIDIA_SMI"] = stub_smi(d, "exit 1")
        r = run(["bash", GPU], env)
        ok("failing nvidia-smi: no sample, rc 0", r.returncode == 0 and len(open(lg).read().splitlines()) == 1, r.stdout)
        env["OVN_NVIDIA_SMI"] = os.path.join(d, "does-not-exist")
        r = run(["bash", GPU], env)
        ok("missing nvidia-smi: rc 0, no sample", r.returncode == 0 and len(open(lg).read().splitlines()) == 1)
        ok("no alert on 1 sample", gpu_alerts(d) == [])
        # NEGATIVE: the diagnosis shape, 17 of 23 samples under 5% -> busy 26% < 40% -> alert
        now = time.time()
        open(lg, "w").write("".join("%d %d 1000\n" % (now - 3600 * 23 + i * 3500, 90 if i < 6 else 2) for i in range(23)))
        r = run([sys.executable, STATS, "--gpu-alert"], env)
        al = gpu_alerts(d)
        ok("alert fired at 26%% busy", len(al) == 1 and "26.1%" in al[0] and "23 samples" in al[0], str(al) + r.stderr)
        run([sys.executable, STATS, "--gpu-alert"], env)
        ok("alert deduped", len(gpu_alerts(d)) == 1, str(gpu_alerts(d)))
        # report shows busy% in ovn_stats output
        ts_ = os.path.join(d, "state", "task_stats.log")
        wjl(ts_, ["%d\txlite\tpass\t{godot·test·T2·verified}\t?" % (now - 60)])
        r = run([sys.executable, STATS, "24"], env)
        ok("stats prints GPU busy", "GPU busy 26.1% over 24h (23 samples" in r.stdout, r.stdout + r.stderr)
        r = run([sys.executable, STATS, "24", "--ntfy"], env)
        ok("ntfy prints GPU busy LOW", "GPU busy 26.1% over 24h" in r.stdout and "LOW" in r.stdout, r.stdout)
        # BENIGN: busy 100% -> no alert (fresh state)
        os.remove(os.path.join(d, "state", ".gpu_util_alerted"))
        os.remove(os.path.join(d, "state", "alerts.log"))
        open(lg, "w").write("".join("%d 80 1000\n" % (now - 3600 * 23 + i * 3500) for i in range(23)))
        run([sys.executable, STATS, "--gpu-alert"], env)
        ok("busy GPU: no alert", gpu_alerts(d) == [])
        # BENIGN: low but too few samples
        open(lg, "w").write("".join("%d 0 1000\n" % (now - 600 * (i + 1)) for i in range(5)))
        run([sys.executable, STATS, "--gpu-alert"], env)
        ok("too few samples: no alert", gpu_alerts(d) == [])
        # BENIGN: low but no lane enabled
        env2 = gpu_env(d, tasks_enabled=False)
        env2["OVN_NVIDIA_SMI"] = "x"
        open(lg, "w").write("".join("%d 0 1000\n" % (now - 600 * (i + 1)) for i in range(20)))
        run([sys.executable, STATS, "--gpu-alert"], env2)
        ok("no enabled lane: no alert", gpu_alerts(d) == [])
        env = gpu_env(d, tasks_enabled=True)   # lane enabled again -> now it fires
        pz = os.path.join(d, "state", "PAUSED")
        open(pz, "w").close()
        run([sys.executable, STATS, "--gpu-alert"], env)
        ok("PAUSED fleet: no alert", gpu_alerts(d) == [])
        os.remove(pz)
        run([sys.executable, STATS, "--gpu-alert"], env)
        ok("same low data, lane enabled: alert", len(gpu_alerts(d)) == 1, str(gpu_alerts(d)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------------ real pass rate
def test_real_passrate():
    d = mk()
    try:
        now = time.time()
        split = now - 6 * 3600
        O = os.path.join(d, "state", "outcomes.jsonl")
        L = os.path.join(d, "state", "qa_ledger.jsonl")
        rows, led = [], []
        # PRE-split iptv: 4 attempts, 2 landed with real commits, 2 plain reverts (item-diverse, alternating = no streak)
        t = now - 20 * 3600
        for k, (cls, sev, st) in enumerate([("landed", "good", "pushed(tests:pass)"), ("reverted", "bad", "reverted(build-break)"),
                                            ("landed", "good", "pushed(tests:pass)"), ("reverted", "bad", "reverted(build-break)")]):
            ts = iso(t + k * 60)
            rows.append(outcome(ts, "iptv_apps", cls, sev, st, ih="pre%d" % k, fr="build-red" if sev == "bad" else ""))
            if cls == "landed":
                led.append(ledger(ts, "iptv_apps", "time-window", ["a" * 40]))
        # POST-split iptv: 12 attempts, 1 landed, 11 bad over 5 distinct items (a broken repo)
        for k in range(12):
            ts = iso(split + 60 * (k + 1))
            if k == 3:
                rows.append(outcome(ts, "iptv_apps", "landed", "good", "pushed(tests:pass)", ih="post-ok"))
                led.append(ledger(ts, "iptv_apps", "time-window", ["b" * 40]))
            else:
                rows.append(outcome(ts, "iptv_apps", "noop", "bad", "no-op(reverted-red)", ih="post%d" % (k % 5), fr="test-red"))
        # xlite: 6 phantom landings (no commit) + 3 real ones, post-split
        for k in range(9):
            ts = iso(split + 4000 + 60 * k)
            rows.append(outcome(ts, "xlite", "landed", "good", "pushed(tests:pass)", ih="xl%d" % k))
            led.append(ledger(ts, "xlite", "none" if k < 6 else "time-window", [] if k < 6 else ["c" * 40]))
        # a landed row with NO ledger entry (unknown) is kept as a win
        rows.append(outcome(iso(split + 9000), "xlite", "landed", "good", "pushed(tests:pass)", ih="nolookup"))
        wjl(O, rows + ["not json"])
        wjl(L, led)
        sys.path.insert(0, SCRIPTS)
        import importlib
        rp = importlib.import_module("ovn_real_passrate")
        lines, res = rp.build(os.path.join(d, "state"), 24.0, split, now)
        w = res["window"]
        # headline: good = 2+1+9+1 = 13, bad = 2+11 = 13 -> 50.0
        ok("headline 50", w["headline"] == 50.0, str(w))
        ok("phantom 6", w["phantom"] == 6, str(w))
        ok("real = 7/20 = 35", w["real"] == 35.0 and w["real_good"] == 7 and w["real_den"] == 20, str(w))
        ok("preexisting streak detected (post iptv 11 bad, 5 items)", w["preexisting"] >= 11, str(w))
        ok("model-attributable higher than real", w["attrib"] > w["real"], str(w))
        pr = res["per_repo"]["iptv_apps"]
        ok("per-repo pre 2/4", pr["pre"]["real_good"] == 2 and pr["pre"]["real_den"] == 4, str(pr["pre"]))
        ok("per-repo post 1/12", pr["post"]["real_good"] == 1 and pr["post"]["real_den"] == 12, str(pr["post"]))
        txt = "\n".join(lines)
        ok("flags NOT HONEST", "HEADLINE NOT HONEST" in txt and "iptv_apps fell" in txt and "phantom" in txt, txt)
        ok("pre->post line", "pre 50% (2/4) -> post 8.3% (1/12)" in txt, txt)
        # pre-split iptv alternating bad rows were NOT labelled pre-existing
        pre_only = [r for r in rp.annotate(rp.load_outcomes(os.path.join(d, "state")), rp.load_commit_evidence(os.path.join(d, "state")))
                    if r.get("item_hash", "") == "pre1"]
        ok("alternating revert between landings is not pre-existing (benign control)",
           len(pre_only) == 1 and not pre_only[0]["_preexisting"])
        # CLI + ovn_stats integration: --since value must not be eaten as hours
        env = {"OVN_STATE_DIR": os.path.join(d, "state")}
        wjl(os.path.join(d, "state", "task_stats.log"), ["%d\tiptv_apps\tpass\t{python·endpoint·T2·verified}\t?" % (now - 60)])
        r = run([sys.executable, STATS, "24", "--since", iso(split)], env)
        ok("stats --since prints real section", "REAL pass rate, last 24h" in r.stdout and "post-deploy comparison" in r.stdout
           and "HEADLINE NOT HONEST" in r.stdout, r.stdout + r.stderr)
        r = run([sys.executable, STATS, "24", "--since=" + iso(split), "--real"], env)
        ok("stats --real only", r.stdout.startswith("REAL pass rate") and "Overnight throughput" not in r.stdout, r.stdout)
        r = run([sys.executable, STATS, "24"], env)
        ok("stats default (no --since) still prints header + real section",
           "Overnight throughput, last 24h" in r.stdout and "REAL pass rate" in r.stdout, r.stdout)
        r = run([sys.executable, STATS, "24", "--ntfy"], env)
        ok("ntfy: flagged headline adds honest line", "HEADLINE NOT HONEST" in r.stdout, r.stdout)
    finally:
        shutil.rmtree(d, ignore_errors=True)
    # BENIGN control: clean data -> honest, no flag, no ntfy noise
    d = mk()
    try:
        now = time.time()
        rows, led = [], []
        for k in range(6):
            ts = iso(now - 3600 + k * 60)
            good = k % 2 == 0
            rows.append(outcome(ts, "billwatch", "landed" if good else "reverted", "good" if good else "bad",
                                "pushed(tests:pass)" if good else "reverted(build-break)", ih="h%d" % k))
            if good:
                led.append(ledger(ts, "billwatch", "time-window", ["d" * 40]))
        wjl(os.path.join(d, "state", "outcomes.jsonl"), rows)
        wjl(os.path.join(d, "state", "qa_ledger.jsonl"), led)
        wjl(os.path.join(d, "state", "task_stats.log"), ["%d\tbillwatch\tpass\t{python·endpoint·T2·verified}\t?" % (now - 60)])
        env = {"OVN_STATE_DIR": os.path.join(d, "state")}
        r = run([sys.executable, STATS, "24", "--ntfy"], env)
        ok("clean ntfy: no honesty noise", "NOT HONEST" not in r.stdout, r.stdout)
        r = run([sys.executable, STATS, "24", "--real"], env)
        ok("clean: consistent", "headline consistent with the real rate" in r.stdout and "headline 50%" in r.stdout and "real 50%" in r.stdout, r.stdout)
        # explicit pre-existing marker
        wjl(os.path.join(d, "state", "outcomes.jsonl"),
            [outcome(iso(now - 30), "billwatch", "reverted", "bad", "reverted(pre-existing-red)", ih="px")])
        r = run([sys.executable, STATS, "24", "--real"], env)
        ok("explicit pre-existing marker separated", "suspected pre-existing-red reverts: 1" in r.stdout, r.stdout)
        # empty window prints nothing extra and does not crash
        r = run([sys.executable, REAL, "--state", os.path.join(d, "state"), "0.0001"])
        ok("empty window rc 0", r.returncode == 0, r.stderr)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_passrate_stage_row():
    d = mk()
    try:
        now = time.time()
        ts1, ts2 = iso(now - 600), iso(now - 300)
        wjl(os.path.join(d, "state", "outcomes.jsonl"),
            [outcome(ts1, "billwatch", "landed", "good", "stage(higher-tier)", ih="s1"),
             outcome(ts2, "billwatch", "landed", "good", "pushed(tests:pass)", ih="p1")])
        wjl(os.path.join(d, "state", "qa_ledger.jsonl"),
            [dict(ledger(ts1, "billwatch", "none", []), status="stage(higher-tier)"),
             ledger(ts2, "billwatch", "none", [])])     # NEGATIVE: pushed + no commit = phantom
        r = run([sys.executable, REAL, "--state", os.path.join(d, "state"), "24"])
        ok("stage row not phantom, pushed row is", "1 phantom landing(s) excluded" in r.stdout, r.stdout + r.stderr)
    finally:
        shutil.rmtree(d, ignore_errors=True)


for fn in (test_deploy_failures, test_landed_without_commit, test_seed, test_triage_still_clusters_outcomes,
           test_walltime, test_walltime_scale, test_gpu, test_real_passrate, test_passrate_stage_row):
    try:
        fn()
    except Exception as e:  # a crash in one group must not hide the others
        F += 1
        import traceback
        traceback.print_exc()
        print("  FAIL: %s crashed: %s" % (fn.__name__, e))

print("test_observability: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
