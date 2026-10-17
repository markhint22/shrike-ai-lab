#!/usr/bin/env python3
"""qa/gpu_ledger.py (Phase 5, shadow): GPU seconds per stage, per landed feature and per ISO week, derived ONLY from existing logs.

Fixtures with hand-computable sums: outcome wall seconds, token-ledger estimates (rates pinned by toks.jsonl + OVN_GPU_PREFILL_TOKS), measured reviewer gpu_s, spec-gate
rows (exec ms is CPU and must NOT be counted as GPU), a card source. Checks attribution (item_hash / feat_tag / commit head), the unattributed remainder, the weekly table,
window handling, hostile rows, the 1% reconcile against an INDEPENDENT sum computed here, merge idempotency, flags, that the module cannot reach the GPU (no process /
network imports), the real CLI, and MUTANTS (a wrong seconds source or a broken weekly bucket must be caught)."""
import calendar
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
PY = sys.executable
if not os.path.isfile(os.path.join(QA, "gpu_ledger.py")):
    print("  SKIP: qa/gpu_ledger.py not installed here")
    sys.exit(0)

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:500]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="gpuledger-test-"))
for k in list(os.environ):
    if k.startswith("OVN_QA_") or k in ("QA_STATE_DIR", "OVN_DIR", "OVN_REPOS_DIR", "OVN_GPU_PREFILL_TOKS"):
        os.environ.pop(k, None)
STATE = os.path.join(T, "state")
os.makedirs(os.path.join(STATE, "qa_shadow"))
os.environ["QA_STATE_DIR"] = STATE
os.environ["OVN_GPU_PREFILL_TOKS"] = "1000"


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


GL = load(os.path.join(QA, "gpu_ledger.py"), "gpu_ledger_under_test")
import qa_ledger as ql  # noqa: E402

NOW = 1_800_000_000          # Fri 2027-01-15 08:00 UTC
DAY = 86400


def iso(e):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))


def jl(rel, rows):
    p = os.path.join(STATE, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        for r in rows:
            f.write((r if isinstance(r, str) else json.dumps(r)) + "\n")


def landed(repo, i, feat, ihash, commit, age_days):
    e = NOW - int(age_days * DAY)
    return {"kind": "landed", "key": "k%s%d" % (repo, i), "repo": repo, "ts": iso(e), "epoch": e, "risk": "B", "tier": "2", "status": "pushed", "risk_basis": "t",
            "commit_basis": "t", "feat_tag": feat, "item_hash": ihash, "commits": [commit], "subjects": [], "files": ["a.py"], "flags": []}


C1, C2, C3 = "a" * 40, "b" * 40, "c" * 40
RECS = [landed("billwatch", 1, "bw-feat-1", "h1", C1, 1), landed("billwatch", 2, "bw-feat-2", "h2", C2, 2), landed("gitlark", 3, "gl-feat-3", "h3", C3, 3)]
# decode 50 tok/s (median of 40,50,60), prefill 1000 tok/s (env)
jl("toks.jsonl", [{"ts": iso(NOW - 100), "tok_s_best": 40.0}, {"ts": iso(NOW - 90), "tok_s_best": 50.0}, {"ts": iso(NOW - 80), "tok_s_best": 60.0}, {"ts": iso(NOW), "tok_s_best": 0}])
OUTC = [
    {"ts": iso(NOW - 1 * DAY), "repo": "billwatch", "item_hash": "h1", "feat_tag": "bw-feat-1", "duration_s": 300, "class": "landed"},
    {"ts": iso(NOW - 1 * DAY - 900), "repo": "billwatch", "item_hash": "h1", "feat_tag": "", "duration_s": 200, "class": "failed"},          # earlier failed attempt, same item
    {"ts": iso(NOW - 2 * DAY), "repo": "billwatch", "item_hash": "", "feat_tag": "bw-feat-2", "duration_s": 100, "class": "landed"},     # joins by feat_tag
    {"ts": iso(NOW - 3 * DAY), "repo": "gitlark", "item_hash": "h3", "feat_tag": "", "duration_s": 60, "class": "landed"},
    {"ts": iso(NOW - 2 * DAY), "repo": "billwatch", "item_hash": "never", "feat_tag": "", "duration_s": 40, "class": "noop"},            # never landed: unattributed
]
jl("outcomes.jsonl", OUTC)
TOK = [
    {"ts": iso(NOW - DAY), "source": "planner", "repo": "billwatch", "tokens_sent": 2000, "tokens_recv": 100},          # 2 s + 2 s = 4 s dev
    {"ts": iso(NOW - DAY), "source": "stage-decompose", "repo": "billwatch", "tokens_sent": 1000, "tokens_recv": 0},   # 1 s dev
    {"ts": iso(NOW - DAY), "source": "local-research", "repo": "gitlark", "tokens_sent": 3000, "tokens_recv": 50},     # 3 + 1 = 4 s research
    {"ts": iso(NOW - DAY), "source": "card-draft", "repo": "gitlark", "tokens_sent": 500, "tokens_recv": 50},          # card has a MEASURED source: not estimated from tokens
    {"ts": iso(NOW - DAY), "source": "qwen-explore", "repo": "gitlark", "tokens_sent": 9000, "tokens_recv": 900},       # the same pass is a qwen_explore.jsonl row: not summed twice
    {"ts": iso(NOW - DAY), "source": "supervisor-review", "repo": "billwatch", "tokens_sent": 5000, "tokens_recv": 500},  # remote review, not a local GPU call
]
jl("token_ledger.jsonl", TOK)
REV = [
    {"ts": iso(NOW - DAY), "gate": "reviewer", "repo": "billwatch", "ref": "z" * 7 + ".." + C1[:12], "verdict": "PASS", "details": {"usage": {"gpu_s": 0.8, "prompt_tokens": 5}}},
    {"ts": iso(NOW - DAY), "gate": "reviewer", "repo": "billwatch", "ref": C2, "verdict": "PASS", "details": {"usage": {"gpu_s": 2.2}}},
    {"ts": iso(NOW - DAY), "gate": "reviewer", "repo": "billwatch", "ref": C1, "verdict": "NA", "details": {"counts": {}}},              # no model call: 0 s
    {"ts": iso(NOW - DAY), "gate": "reviewer", "repo": "gitlark", "ref": "d" * 40, "verdict": "PASS", "details": {"usage": {"gpu_s": 1.0}}},  # head not in the ledger: unattributed
]
jl("qa_shadow/reviewer.jsonl", REV)
SPEC = [{"ts": iso(NOW - DAY), "repo": "billwatch", "feat": "bw-feat-1", "exec": {"ms": 90000}, "mode": "shadow"},
        {"ts": iso(NOW - DAY), "repo": "billwatch", "feat": "bw-feat-2", "exec": {"ms": 1000}, "gpu_s": 5.0}]
jl("spec_gate.jsonl", SPEC)
jl("qwen_explore.jsonl", [{"ts": iso(NOW - DAY), "repo": "gitlark", "secs": 20, "result": "empty"}])
jl("qa_shadow/acceptance.jsonl", [{"ts": iso(NOW - DAY), "gate": "acceptance", "repo": "gitlark", "ref": C3, "details": {"meta": {"gpu_s": 3.0}}}])

D = GL.derive(STATE, RECS, NOW, 14)
feat = {f["key"]: f for f in D["features"]}
bw1, bw2, gl3 = feat["billwatch|bw-feat-1"], feat["billwatch|bw-feat-2"], feat["gitlark|gl-feat-3"]
ok("stage mapping", [GL.token_stage(s) for s in ("planner", "stage-decompose", "local-research", "explore", "card-draft", "reviewer-x", "mutation_scan", "spec-check", "recover_parked")]
   == ["dev", "dev", "research", "research", "card", "reviewer", "mutation", "spec_gate", "dev"])
ok("rates: decode = median tok_s_best (50, zero ignored), prefill from env", D["decode_tok_s"] == 50.0 and D["prefill_tok_s"] == 1000.0, (D["decode_tok_s"], D["prefill_tok_s"]))
ok("dev seconds of a feature = ALL its attempts (landed 300 + failed 200, joined by item_hash)", bw1["stages"].get("dev") == 500.0, bw1)
ok("outcome joined by feat_tag when there is no item_hash", bw2["stages"].get("dev") == 100.0, bw2)
ok("reviewer gpu_s attributed by the head commit of base..head (0.8) and by a bare sha (2.2); the NA row adds 0", bw1["stages"].get("reviewer") == 0.8 and bw2["stages"].get("reviewer") == 2.2, (bw1, bw2))
ok("spec_gate: CPU exec ms is NOT GPU (bw-feat-1 has no spec_gate stage); an explicit gpu_s is", bw1["stages"].get("spec_gate", 0) == 0 and bw2["stages"].get("spec_gate") == 5.0, (bw1, bw2))
ok("spec_gate CPU seconds reported separately", sum(D["spec_gate_cpu_s"].values()) == 91.0, D["spec_gate_cpu_s"])
ok("card gpu_s (details.meta.gpu_s) attributed by commit head", gl3["stages"].get("card") == 3.0 and gl3["stages"].get("dev") == 60.0, gl3)
ok("total_s of a feature is the sum of its stages", bw1["total_s"] == 500.8 and gl3["total_s"] == 63.0, (bw1["total_s"], gl3["total_s"]))
src = D["sources"]
ok("outcomes source total = 700 s (incl. the unattributed 40)", src["outcomes"]["seconds"] == 700.0 and src["outcomes"]["attributed_s"] == 660.0, src["outcomes"])
ok("token estimate: (2000/1000 + 100/50) + 1 + (3 + 1) = 9 s (card-draft, qwen-explore and supervisor-review rows are NOT estimated)", abs(src["token_ledger"]["seconds"] - 9.0) < 1e-6 and src["token_ledger"]["rows"] == 3, src["token_ledger"])
ok("research = local-research 4 s + measured explore 20 s ONLY (qwen-explore not counted twice)", abs(sum(r["seconds"] for r in D["weeks"] if r["stage"] == "research") - 24.0) < 1e-6, [r for r in D["weeks"] if r["stage"] == "research"])
ok("reviewer source = 4.0 s, 4 rows", src["reviewer"]["seconds"] == 4.0 and src["reviewer"]["rows"] == 4, src["reviewer"])
ok("sources block lists absent logs as present=False with 0 rows (mutation)", src["mutation"]["present"] is False and src["mutation"]["rows"] == 0 and src["acceptance"]["present"] is True)
wk = {(r["repo"], r["stage"]): r["seconds"] for r in D["weeks"]}
ok("weekly rows keep the UNATTRIBUTED cost (the never-landed 40 s noop sits in billwatch dev: 500+100+40+4+1 = 645)", abs(wk[("billwatch", "dev")] - 645.0) < 1e-6, wk)
ok("weekly landed counts: 3 features all landed in ISO week %s" % GL.week_of(NOW - DAY), D["weeks_landed"] == {GL.week_of(NOW - DAY): 3}, D["weeks_landed"])
ok("weekly per-repo landed: billwatch 2, gitlark 1", {r["repo"]: r["landed"] for r in D["weeks"] if r["repo"] in ("billwatch", "gitlark")} == {"billwatch": 2, "gitlark": 1})
tbl = GL.weekly_table(D)
ok("weekly table is markdown with every stage column and a min/landed figure", "| week | landed |" in tbl and all(s in tbl.splitlines()[0] for s in GL.STAGES) and "min / landed" in tbl.splitlines()[0], tbl[:300])
wk_total_min = sum(r["seconds"] for r in D["weeks"]) / 60.0
ok("min/landed in the table = total minutes / 3 landed features", ("%.2f" % (wk_total_min / 3)) in tbl, (wk_total_min / 3, tbl))

# ---------------------------------------------------------------- 1% reconcile against an INDEPENDENT sum
indep = sum(float(r["duration_s"]) for r in OUTC) + 9.0 + 4.0 + 20.0 + 3.0 + 5.0   # + tokens + reviewer + explore + card + spec_gate gpu_s (tokens: 9.0 after the exclusions)
rec = GL.reconcile(D, STATE, NOW, 14)
ok("reconcile: ledger weekly total within 1% of the raw logs", rec["ok"] and abs(rec["ledger_weekly_total_s"] - indep) / indep <= 0.01, (rec, indep))
ok("reconcile: every source within 1%", all(v["rel_err"] <= 0.01 for v in rec["per_source"].values()), rec["per_source"])

# ---------------------------------------------------------------- window, hostile rows
jl("outcomes.jsonl", OUTC + [
    {"ts": iso(NOW - 40 * DAY), "repo": "billwatch", "item_hash": "h1", "duration_s": 9999},      # outside the 14 d window
    {"ts": "garbage", "repo": "billwatch", "duration_s": 5},
    {"ts": iso(NOW - DAY), "repo": "billwatch", "duration_s": -5},
    {"ts": iso(NOW - DAY), "repo": "billwatch", "duration_s": True},
    {"ts": iso(NOW - DAY), "repo": "billwatch", "duration_s": "12"},
    {"ts": iso(NOW - DAY), "repo": "../etc", "duration_s": 7},
    "not json", "[1]", "\x00\x00",
])
D2 = GL.derive(STATE, RECS, NOW, 14)
ok("rows outside the window are excluded; negative / bool / string seconds and bad ts are skipped (not summed)", D2["sources"]["outcomes"]["seconds"] == 707.0 and D2["skipped_rows"] >= 4, (D2["sources"]["outcomes"], D2["skipped_rows"]))
ok("a hostile repo name is bucketed as '?', never used as a path", any(r["repo"] == "?" for r in D2["weeks"]) and not any("etc" in r["repo"] for r in D2["weeks"]))
ok("hostile input still reconciles", GL.reconcile(D2, STATE, NOW, 14)["ok"])
jl("outcomes.jsonl", OUTC + [{"ts": iso(NOW - 6 * DAY), "repo": "billwatch", "item_hash": "", "feat_tag": "", "duration_s": 777}])    # Sat of the PREVIOUS ISO week
D3 = GL.derive(STATE, RECS, NOW, 1)
ok("--days 1: the window is aligned to Monday of the current ISO week (all of this week kept, the previous week's row dropped)",
   D3["sources"]["outcomes"]["seconds"] == 700.0 and GL.derive(STATE, RECS, NOW, 14)["sources"]["outcomes"]["seconds"] == 1477.0, D3["sources"]["outcomes"])
ok("window_start is a Monday 00:00 UTC", time.gmtime(GL.window_start(NOW, 1)).tm_wday == 0 and GL.window_start(NOW, 1) % DAY == 0 and GL.window_start(NOW, 1) <= NOW - DAY)
jl("outcomes.jsonl", OUTC)

# ---------------------------------------------------------------- merge_write: idempotent, keeps old keys, replaces recomputed ones
path = os.path.join(STATE, "qa_shadow", "gpu_ledger.jsonl")
okw, n1 = GL.merge_write(D, path)
okw2, n2 = GL.merge_write(D, path)
ok("merge_write twice -> same row count (idempotent)", okw and okw2 and n1 == n2 and len(open(path).read().splitlines()) == n1)
with open(path, "a") as f:
    f.write(json.dumps({"kind": "feature", "key": "old|feature", "repo": "billwatch", "total_s": 1}) + "\n")
GL.merge_write(D, path)
rows = [json.loads(l) for l in open(path)]
ok("rows of keys not recomputed are kept, recomputed ones are replaced (no duplicate keys)", any(r["key"] == "old|feature" for r in rows) and len(set(r["key"] for r in rows)) == len(rows))
ok("feature + week rows both present", {r["kind"] for r in rows} >= {"feature", "week"})

# ---------------------------------------------------------------- flags + run
for val, want in ((None, "shadow"), ("off", "off"), ("shadow", "shadow"), ("enforce", "shadow"), ("zzz", "shadow")):
    if val is None:
        os.environ.pop("OVN_QA_GPU_LEDGER", None)
    else:
        os.environ["OVN_QA_GPU_LEDGER"] = val
    ok("OVN_QA_GPU_LEDGER=%r -> %s" % (val, want), GL.mode() == want)
os.environ["OVN_QA_GPU_LEDGER"] = "off"
for f in ("gpu_ledger.jsonl", "gpu_ledger_weekly.md"):
    p = os.path.join(STATE, "qa_shadow", f)
    if os.path.exists(p):
        os.unlink(p)
out = GL.cmd_run([], now=NOW)
ok("off: nothing written", out["mode"] == "off" and not os.path.exists(path))
os.environ.pop("OVN_QA_GPU_LEDGER")
ql.append_lines(RECS)
out = GL.cmd_run([], now=NOW)
ok("shadow run: writes the jsonl and the weekly markdown, reports a passing reconcile", out["wrote"] == 2 and os.path.exists(path) and os.path.exists(os.path.join(STATE, "qa_shadow", "gpu_ledger_weekly.md"))
   and out["reconcile"]["ok"] and out["features"] == 3, out)
size = os.path.getsize(path)
out = GL.cmd_run(["--no-record"], now=NOW)
ok("--no-record writes nothing", out["wrote"] == 0 and os.path.getsize(path) == size)
src_text = open(os.path.join(QA, "gpu_ledger.py")).read()
ok("the module cannot reach the GPU: no subprocess / socket / urllib / requests / http imports", not any(("import " + m) in src_text for m in ("subprocess", "socket", "urllib", "requests", "http")))

# ---------------------------------------------------------------- real CLI
env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "QA_STATE_DIR": STATE, "HOME": T, "OVN_GPU_PREFILL_TOKS": "1000"}
p = subprocess.run([PY, os.path.join(QA, "gpu_ledger.py"), "run", "--no-record", "--days", "100000"], env=env, capture_output=True, text=True)
j = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {}
ok("CLI run: exit 0, valid JSON, reconcile ok", p.returncode == 0 and j.get("reconcile", {}).get("ok") is True, p.stdout + p.stderr)
p = subprocess.run([PY, os.path.join(QA, "gpu_ledger.py"), "report"], env=dict(env, QA_STATE_DIR=os.path.join(T, "nowhere")), capture_output=True, text=True)
ok("CLI report on an empty state dir: exit 0", p.returncode == 0, p.stderr)

# ---------------------------------------------------------------- week rows are complete and never shrink (the cron re-runs hourly with a sliding window)
W_NOW1 = calendar.timegm((2026, 10, 17, 8, 0, 0))
W_NOW2 = calendar.timegm((2026, 10, 28, 8, 0, 0))
jl("outcomes.jsonl", [{"ts": iso(calendar.timegm((2026, 10, d, 9, 0, 0))), "repo": "billwatch", "item_hash": "", "feat_tag": "", "duration_s": 3600} for d in (12, 13, 14, 15, 16)])
for f in ("token_ledger.jsonl", "qwen_explore.jsonl", "spec_gate.jsonl", "qa_shadow/reviewer.jsonl", "qa_shadow/acceptance.jsonl"):
    jl(f, [])
wa = GL.derive(STATE, [], W_NOW1, 14)
wb = GL.derive(STATE, [], W_NOW2, 14)
sec = lambda d: {r["week"]: r["seconds"] for r in d["weeks"] if r["stage"] == "dev"}  # noqa: E731
ok("ISO week straddling the window start is summed WHOLE (18000 s at both run times)", sec(wa).get("2026-W42") == 18000.0 and sec(wb).get("2026-W42") == 18000.0, (sec(wa), sec(wb)))
wpath = os.path.join(STATE, "qa_shadow", "w_test.jsonl")
GL.merge_write(wa, wpath)
GL.merge_write(wb, wpath)
ok("merge_write after the window slid keeps the complete week row", [r["seconds"] for r in map(json.loads, open(wpath)) if r["key"] == "week|2026-W42|billwatch|dev"] == [18000.0])
shrunk = {"features": [], "weeks": [{"kind": "week", "key": "week|2026-W42|billwatch|dev", "week": "2026-W42", "repo": "billwatch", "stage": "dev", "seconds": 10800.0, "landed": 0}]}
GL.merge_write(shrunk, wpath)
ok("a smaller recomputed week value never overwrites a larger stored one", [r["seconds"] for r in map(json.loads, open(wpath)) if r["key"] == "week|2026-W42|billwatch|dev"] == [18000.0])
ok("the weekly md/jsonl atomic_write mode is 0644 like the sibling state files", oct(os.stat(wpath).st_mode & 0o777) == "0o644", oct(os.stat(wpath).st_mode & 0o777))

# ---------------------------------------------------------------- survivors of the first review: ISO year, reconcile tolerance, ref guard, default rates
ok("week_of uses the ISO year (2027-01-01 is 2026-W53, not 2027-W53)", GL.week_of(calendar.timegm((2027, 1, 1, 12, 0, 0))) == "2026-W53" and GL.week_of(calendar.timegm((2026, 12, 28, 12, 0, 0))) == "2026-W53")
jl("outcomes.jsonl", [{"ts": iso(NOW - DAY), "repo": "billwatch", "duration_s": 1000}])
dd = GL.derive(STATE, [], NOW, 14)
bad = json.loads(json.dumps(dd))
bad["sources"]["outcomes"]["seconds"] *= 1.05
bad["weeks"][0]["seconds"] *= 1.05
ok("reconcile flags a 5% discrepancy (tolerance is 1%)", GL.reconcile(dd, STATE, NOW, 14)["ok"] and not GL.reconcile(bad, STATE, NOW, 14)["ok"] and GL.RECONCILE_TOL == 0.01)
saved_pre = os.environ.pop("OVN_GPU_PREFILL_TOKS")
os.remove(os.path.join(STATE, "toks.jsonl"))
ok("default rates: decode 45 tok/s, prefill 1500 tok/s when nothing is configured", GL.rates(STATE) == (45.0, 1500.0) and GL.DEFAULT_PREFILL == 1500.0, GL.rates(STATE))
os.environ["OVN_GPU_PREFILL_TOKS"] = saved_pre
short = [dict(landed("billwatch", 9, "bw-short", "hs", "abcd", 1))]
jl("qa_shadow/reviewer.jsonl", [{"ts": iso(NOW - DAY), "gate": "reviewer", "repo": "billwatch", "ref": "abcd", "details": {"usage": {"gpu_s": 9.0}}}])
ds = GL.derive(STATE, short, NOW, 14)
ok("a ref shorter than 7 chars is never bound to a feature (stays unattributed)", ds["sources"]["reviewer"]["attributed_s"] == 0.0 and ds["sources"]["reviewer"]["seconds"] == 9.0, ds["sources"]["reviewer"])

# ---------------------------------------------------------------- MUTANTS
CHECK = r'''
import sys, json
sys.path.insert(0, sys.argv[1])
import gpu_ledger as gl
d = gl.derive(sys.argv[2], json.load(open(sys.argv[3])), 1800000000, 14)
rec = gl.reconcile(d, sys.argv[2], 1800000000, 14)
f = {x["key"]: x for x in d["features"]}
print(json.dumps({"dev1": f["billwatch|bw-feat-1"]["stages"].get("dev"), "rec_ok": rec["ok"], "tot": rec["ledger_weekly_total_s"]}))
'''
jl("outcomes.jsonl", OUTC)
jl("token_ledger.jsonl", TOK)
jl("qa_shadow/reviewer.jsonl", REV)
jl("spec_gate.jsonl", SPEC)
jl("qwen_explore.jsonl", [{"ts": iso(NOW - DAY), "repo": "gitlark", "secs": 20, "result": "empty"}])
jl("qa_shadow/acceptance.jsonl", [{"ts": iso(NOW - DAY), "gate": "acceptance", "repo": "gitlark", "ref": C3, "details": {"meta": {"gpu_s": 3.0}}}])
jl("toks.jsonl", [{"ts": iso(NOW - 100), "tok_s_best": 40.0}, {"ts": iso(NOW - 90), "tok_s_best": 50.0}, {"ts": iso(NOW - 80), "tok_s_best": 60.0}, {"ts": iso(NOW), "tok_s_best": 0}])
rj = os.path.join(T, "recs.json")
json.dump(RECS, open(rj, "w"))


def run_variant(moddir):
    p = subprocess.run([PY, "-I", "-c", CHECK, moddir, STATE, rj], capture_output=True, text=True, env={"PATH": os.environ.get("PATH", ""), "OVN_GPU_PREFILL_TOKS": "1000"})
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def good(r):
    return bool(r) and r["dev1"] == 500.0 and r["rec_ok"] is True and abs(r["tot"] - indep) / indep <= 0.01


def mutate(label, old, new):
    d = os.path.join(T, "mut_" + label)
    os.makedirs(d)
    for f in ("gpu_ledger.py", "qa_common.py", "qa_ledger.py", "phase5_common.py", "wip_cap.py"):
        shutil.copy(os.path.join(QA, f), os.path.join(d, f))
    s = open(os.path.join(d, "gpu_ledger.py")).read()
    if old not in s:
        return "needle-missing"
    open(os.path.join(d, "gpu_ledger.py"), "w").write(s.replace(old, new, 1))
    return run_variant(d)


ok("mutant control: unmodified code passes the same check", good(run_variant(QA)), run_variant(QA))
ok("MUTANT wrong seconds source (duration_s * 2) is caught by the absolute expectations", not good(mutate("dur", 'return num(r.get("duration_s"))', 'return (num(r.get("duration_s")) or 0) * 2')))
ok("MUTANT weekly bucket drops half the seconds is caught by the 1% reconcile", not good(mutate("wk", "week[(week_of(e), repo, stage)] += sec\n", "week[(week_of(e), repo, stage)] += sec * 0.5\n")))
ok("MUTANT attribution by item_hash removed is caught", not good(mutate("attr", 'k = by_hash.get((repo, row["item_hash"]))', "k = None")))
r_tok = mutate("tok", "(b or 0.0) / dec", "0.0")
ok("MUTANT token estimate ignores the decode term: caught by the EXACT total (the 1% reconcile alone would not see 4 s of 740)", isinstance(r_tok, dict) and abs(r_tok["tot"] - indep) > 0.01
   and abs(run_variant(QA)["tot"] - indep) < 0.01, r_tok)

shutil.rmtree(T, ignore_errors=True) if os.path.basename(T).startswith("gpuledger-test-") else None
print("\nPASS=%d FAIL=%d" % (P, F))
sys.exit(1 if F else 0)
