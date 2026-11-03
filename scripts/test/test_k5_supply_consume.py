#!/usr/bin/env python3
"""Tests for package K5-supply (2026-11-03): the forecast's real-repo list, the research_requests CONSUMERS (local research, work supply, trigger check), the explorer verify-dialect
spellings of the dead-code lens, and the K8 mutation-survivor consumer. Hermetic temp dirs, no box, no model, no network, no ntfy (NTFY_SERVER points at a dead port, TZ=UTC).

K5C_SCRIPTS=<dir> runs the same checks against another copy of scripts/ (the mutant runner: every mutant must make at least one check fail). --no-mutants skips the runner."""
import atexit
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("K5C_SCRIPTS") or os.path.abspath(os.path.join(HERE, ".."))
os.environ["TZ"] = "UTC"
time.tzset()
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
BASE = os.path.realpath(tempfile.mkdtemp(prefix="k5-consume-"))
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("k5-consume-") else None)
for k in list(os.environ):
    if k.startswith(("OVN_FORECAST", "OVN_SUPPLY", "OVN_RR_", "OVN_RESEARCH_REQUESTS", "OVN_LR_", "OVN_MUT", "OVN_FLOOR", "OVN_QE_")):
        del os.environ[k]
sys.path.insert(0, SCRIPTS)
P = F = 0


def check(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def r(path):
    try:
        return open(path).read()
    except OSError:
        return ""


def load(name, alias=None):
    spec = importlib.util.spec_from_file_location((alias or name) + "_k5c", os.path.join(SCRIPTS, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    sys.modules[alias or name] = m
    spec.loader.exec_module(m)
    return m


def new_root(label):
    root = os.path.join(BASE, label)
    os.makedirs(os.path.join(root, "state"))
    os.environ["OVN_DIR"] = root
    os.environ["OVN_NOTIFY_STATE"] = os.path.join(root, "state")
    return root


NOW = time.time()


def request(root, name, age_s=60, priority="high", **kw):
    d = {"repo": name, "ts": NOW - age_s, "priority": priority, "shortfall_items": 8, "shortfall_features": 2, "runway_h": 0.0, "burn_per_day": 4.0, "pullable": 0, "ready": 0, "source": "ovn_supply_forecast"}
    d.update(kw)
    w(os.path.join(root, "state", "research_requests", name + ".json"), json.dumps(d))


def consumed(root):
    return r(os.path.join(root, "state", "research_requests_consumed.log"))


# =========================================================================== 1. forecast: only real repos
root = new_root("fc")
for n in ("alpha", "beta", "social-media-manager"):
    w(os.path.join(root, "roadmap", n + ".md"), "# r\n")
w(os.path.join(root, "roadmap", "README.md"), "# docs, not a repo\n")
os.makedirs(os.path.join(root, "repos", "alpha"))
os.makedirs(os.path.join(root, "repos", "social-media-manager"))
os.makedirs(os.path.join(root, "repos", "README"))        # even a stray dir of that name is not a repo
sf = load("ovn_supply_forecast")
check("C1 default_repos = roadmap AND a repos/<name> clone (no README, no clone-less roadmap, no discontinued)", sf.default_repos(root) == ["alpha"], sf.default_repos(root))
check("C2 the forecast json no longer contains a README row", "README" not in sf.collect(now=NOW, root=root, state=os.path.join(root, "state"))["repos"])

# =========================================================================== 2. research_requests reader
root = new_root("rr")
rr = load("ovn_research_requests")
st = os.path.join(root, "state")
check("R1 no request file -> None", rr.active("alpha", now=NOW, state=st) is None)
request(root, "alpha")
check("R2 a fresh request is live", (rr.active("alpha", now=NOW, state=st) or {}).get("priority") == "high")
request(root, "alpha", age_s=7 * 3600)
check("R3 a request older than OVN_RR_MAX_AGE_H (6h) is ignored (the forecast stopped)", rr.active("alpha", now=NOW, state=st) is None)
request(root, "alpha", repo="other")
check("R4 a request naming a different repo is ignored", rr.active("alpha", now=NOW, state=st) is None)
w(os.path.join(st, "research_requests", "alpha.json"), "{not json")
check("R5 a malformed request is ignored, never raises", rr.active("alpha", now=NOW, state=st) is None)
request(root, "alpha")
w(os.path.join(st, "supply_forecast.json"), json.dumps({"ts": NOW - 60, "repos": {"alpha": {"short": False}}}))
check("R6 fresh forecast says the repo is no longer short -> request removed + not live",
      rr.active("alpha", now=NOW, state=st) is None and not os.path.exists(os.path.join(st, "research_requests", "alpha.json")))
check("R7 the removal is logged", "alpha removed" in consumed(root), consumed(root))
request(root, "alpha")
w(os.path.join(st, "supply_forecast.json"), json.dumps({"ts": NOW - 5 * 3600, "repos": {"alpha": {"short": False}}}))
check("R8 a STALE forecast json does not remove a request", rr.active("alpha", now=NOW, state=st) is not None)
os.environ["OVN_RESEARCH_REQUESTS"] = "off"
check("R9 OVN_RESEARCH_REQUESTS=off disables the reader", rr.active("alpha", now=NOW, state=st) is None)
del os.environ["OVN_RESEARCH_REQUESTS"]
request(root, "beta", priority="normal", runway_h=1.0)
request(root, "gamma", priority="high", runway_h=3.0)
os.unlink(os.path.join(st, "supply_forecast.json"))
check("R11 pending(): high with the shorter runway (alpha 0h) before gamma 3h", [x[0] for x in rr.pending(now=NOW, state=st)] == ["alpha", "gamma", "beta"])

# =========================================================================== 3. local research consumer
root = new_root("lr")
os.makedirs(os.path.join(root, "repos", "alpha"))
w(os.path.join(root, "roadmap", "alpha.md"), "# r\n- [ ] [P2] [ready] Existing feature\n")
lr = load("ovn_local_research")


def run_lr(*flags):
    buf = io.StringIO()
    with redirect_stdout(buf):
        lr.main(["x", "alpha"] + list(flags))
    return buf.getvalue()


out = run_lr("--dry-run")
check("L1 no request: a repo with a [ready] feature is skipped (unchanged behaviour)", "already has a [ready] feature - skip" in out, out)
request(root, "alpha")
out = run_lr("--dry-run")
check("L2 live request: the [ready]-feature early exit is bypassed", "research request is live" in out and "already has a [ready]" not in out, out)
check("L3 a DRY RUN never logs a bypass", "bypass-ready-skip" not in consumed(root), consumed(root))
marker = os.path.join(root, "state", "local_research_alpha")
w(marker, str(time.time()))
out = run_lr("--dry-run")
check("L4 the cooldown still applies with a live request", "in cooldown - skip" in out, out)
out = run_lr()
check("L4b a live pass that exits on cooldown leaves NO bypass line (nothing was consumed)", "in cooldown - skip" in out and "bypass-ready-skip" not in consumed(root), consumed(root))
os.unlink(marker)
import datetime  # noqa: E402
w(os.path.join(root, "state", "local_research_count_alpha_%s" % datetime.date.today().isoformat()), "99")
out = run_lr("--dry-run")
check("L5 the daily cap still applies with a live request", "daily cap reached - skip" in out, out)
out = run_lr()
check("L5b a live pass that exits on the daily cap leaves NO bypass line", "daily cap reached - skip" in out and "bypass-ready-skip" not in consumed(root), consumed(root))
os.unlink(os.path.join(root, "state", "local_research_count_alpha_%s" % datetime.date.today().isoformat()))
_rrp = os.path.join(root, "state", "research_requests", "alpha.json")
w(os.path.join(root, "state", "supply_forecast.json"), json.dumps({"ts": time.time(), "repos": {"alpha": {"short": False}}}))
out = run_lr("--dry-run")
check("L5c a dry run does not unlink a request the forecast says is no longer short, and logs nothing", os.path.exists(_rrp) and "removed" not in consumed(root), consumed(root))
os.unlink(os.path.join(root, "state", "supply_forecast.json"))

# =========================================================================== 4. work supply consumer
root = new_root("ws")
os.makedirs(os.path.join(root, "repos", "alpha"))
w(os.path.join(root, "backlog", "alpha.md"), "# b\n" + "".join("- [ ] [T1] scripts/f%d.py - change %d. VERIFY: `true`\n" % (i, i) for i in range(30)))
ws = load("ovn_work_supply")


def run_ws(*flags):
    buf = io.StringIO()
    with redirect_stdout(buf):
        ws.main(["x", "alpha"] + list(flags))
    return buf.getvalue()


out = run_ws("--dry-run")
check("W1 no request: 30 pullable >= 24 -> no supply needed (unchanged)", "no supply needed" in out, out)
request(root, "alpha")
out = run_ws("--dry-run")
check("W2 live request: the MIN_BACKLOG early exit is bypassed (supply pass continues)", "no supply needed" not in out and "research request is live" in out, out)
w(os.path.join(root, "state", "supply_forecast.json"), json.dumps({"ts": time.time(), "repos": {"alpha": {"short": False}}}))
run_ws("--dry-run")
check("W2b a dry run leaves a request the forecast says is no longer short in place and logs nothing", os.path.exists(os.path.join(root, "state", "research_requests", "alpha.json")) and "removed" not in consumed(root), consumed(root))
os.unlink(os.path.join(root, "state", "supply_forecast.json"))
out = run_ws()
check("W3 the bypass is logged", "work-supply alpha bypass-min-backlog" in consumed(root), consumed(root))
request(root, "alpha", age_s=9 * 3600)
out = run_ws("--dry-run")
check("W4 a stale request does not bypass", "no supply needed" in out, out)

# =========================================================================== 5. trigger check: earlier floor alert
root = new_root("tc")
home = os.path.join(BASE, "home")
oq = os.path.join(home, "overnight-queue")
os.makedirs(os.path.join(oq, "state"))
os.makedirs(os.path.join(oq, "logs"))
STARVE = "backlog low (0) but no [ready] roadmap feature (needs Claude research?)"
logp = os.path.join(oq, "logs", "ovn_planner.log")
w(logp, "".join("%s alpha: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(time.time() - h * 3600)), STARVE) for h in (4, 3.5, 3, 0.5)))


def run_tc():
    env = dict(os.environ, HOME=home, OVN_DIR=oq, TZ="UTC")
    for k in ("OVN_NOTIFY_STATE",):
        env.pop(k, None)
    return subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_research_trigger_check.py"), "2", logp], env=env, capture_output=True, text=True, timeout=60)


run_tc()
alerts = r(os.path.join(oq, "state", "alerts.log"))
check("T1 no request: a lane starving 4h (< 6h floor) raises no floor alert", "roadmap-feature floor" not in alerts, alerts)
os.makedirs(os.path.join(oq, "state", "research_requests"))
w(os.path.join(oq, "state", "research_requests", "alpha.json"), json.dumps({"repo": "alpha", "ts": time.time() - 60, "priority": "high", "shortfall_items": 8, "shortfall_features": 2, "runway_h": 0.0}))
run_tc()
alerts = r(os.path.join(oq, "state", "alerts.log"))
check("T2 live request: the same lane raises the floor alert earlier (> 2h) and names the request", "roadmap-feature floor" in alerts and "supply-forecast request live" in alerts, alerts)

# =========================================================================== 6. explorer verify dialect (dead-code lens)
qe = load("ovn_qwen_explore")
fs = {"backend/app/utils/retry_backoff.py", "backend/app/utils/backoff_jitter.py", "backend/app/utils/__init__.py", "backend/app/utils/notes.txt", "backend/tests/test_a.py"}


def norm(v, f=fs):
    n = qe.normalize_verify(v, f)
    return n, qe.verify_dialect_reason(n)


n, why = norm('grep -rn foo .github', {".github/w.yml", "github/z.yml", "a.py"})
check("E0 a dot-directory target is never rewritten to the dot-less directory", "github/z.yml" not in n.replace(".github/w.yml", "") and ".github/w.yml" in n, n)
n, why = norm('! grep -rn "retry_backoff" backend/app/utils --include="*.py"')
check("E1 recursive grep over a directory is expanded to the snapshot's explicit .py files and then accepted",
      why == "" and "-r" not in n.split("'")[0] and n.endswith("backend/app/utils/retry_backoff.py") and "notes.txt" not in n and n.startswith("! grep -n "), n)
n, why = norm('cd backend && ! grep -rn "retry_backoff" app/utils')
check("E2 the leading `cd backend &&` is kept and targets stay relative to it", why == "" and n.startswith("cd backend && ! grep -n retry_backoff app/utils/") and "backend/app" not in n.split("&&", 1)[1], n)
n, why = norm('! grep -n "retry_backoff" backend/app/utils/*.py')
check("E3 a one-level glob is expanded against the snapshot", why == "" and "*" not in n and "backoff_jitter.py" in n, n)
n, why = norm('! grep -rn "x" b/', {"b/%d.py" % i for i in range(14)})
n13, why13 = norm('! grep -rn "x" b/', {"b/%d.py" % i for i in range(12)})
check("E4a exactly 12 files is still expanded", why13 == "" and n13.count(".py") == 12, n13)
check("E4 an expansion over the file cap (12) is left alone and still rejected", why == "verify-dialect" and "-r" in n, n)
n, why = norm('! grep -rn "x" backend/app/utils', set())
check("E5 without a snapshot file list nothing is expanded (still rejected)", why == "verify-dialect", n)
n, why = norm('! grep -rn "x" ../etc')
check("E6 a path with .. is never expanded", why == "verify-dialect", n)
n, why = norm('! grep -rn "x" backend/app/utils | wc -l')
check("E7 a pipe is not rescued", why == "verify-dialect", n)
n, why = norm("test ! -f backend/app/a.py && test ! -f backend/tests/b.py")
check("E8 a chain of negated `test -f` clauses is merged into the one-command form", why == "" and n == "test ! -f backend/app/a.py -a ! -f backend/tests/b.py", n)
n, why = norm("cd backend && test ! -f app/a.py && test ! -e app/b.py")
check("E9 the merge keeps a leading cd", why == "" and n == "cd backend && test ! -f app/a.py -a ! -e app/b.py", n)
n, why = norm("test ! -f a.py && rm -rf x")
check("E10 a chain with anything but negated test clauses is not merged", why == "verify-dialect", n)
check("E11 pytest report flag -rs is accepted", qe.verify_dialect_reason("cd backend && python3 -m pytest tests/test_a.py -q -rs") == "")
check("E12 python3 -c is still refused", qe.verify_dialect_reason('python3 -c "print(1)"') == "verify-dialect")
check("E13 grep -r itself is still refused by the strict check (only the expander may remove it)", qe.verify_dialect_reason('! grep -rn "abcdefghijkl" backend/app') == "verify-dialect")
row = qe.Row("alpha")
for v in ("v1 " + "x" * 300, "v2", "v3", "v4"):
    qe.note_verify_reject(row, v)
check("E14 the row records at most 3 offending VERIFY texts, each cut to 140 chars", len(row.d["verify_rejects"]) == 3 and all(len(x) <= 140 for x in row.d["verify_rejects"]), row.d)

# =========================================================================== 7. K8 mutation-survivor consumer
root = new_root("mu")
xr = os.path.join(root, "repos", "xlite")
os.makedirs(xr)
mu = load("ovn_mutation_supply")
import ovn_work_supply as ws2  # noqa: E402  (the module the consumer imports; loaded with this OVN_DIR)
sys.modules.pop("ovn_work_supply", None)
ws2 = load("ovn_work_supply")
for i in range(5):
    w(os.path.join(xr, "scripts", "u%d.gd" % i), "extends Node\nfunc f(a, b):\n\treturn a - b\n")
    w(os.path.join(xr, "tests", "test_u%d.gd" % i), "extends GutTest\nfunc test_f():\n\tassert_eq(1, 1)\n")
surv = []
for i in range(5):
    src, tp = "scripts/u%d.gd" % i, "tests/test_u%d.gd" % i
    surv.append({"file": src, "test": tp, "line": 3, "col": 10, "occ": 1, "orig": "-", "mut": "+", "snippet": "return a - b", "src_sha": mu.sha_file(os.path.join(xr, src)),
                 "test_sha": mu.sha_file(os.path.join(xr, tp)), "others_sha": mu.other_tests(xr, src, tp)[1]})
w(os.path.join(root, "state", "mutation_survivors_xlite.json"), json.dumps({"survivors": surv}))
w(os.path.join(root, "backlog", "xlite.md"), "# b\n")
os.environ["OVN_SUPPLY_FROZEN"] = "off"
CHECKED = []


def stub_check(repo, lines):
    CHECKED.append(list(lines))
    return {i: "red" for i in range(len(lines))}


ws2.spec_check = stub_check
msg = []
sink = lambda s: msg.append(s)  # noqa: E731
check("M1 repo list defaults to xlite only", mu.supply_repos() == ["xlite"])
os.environ["OVN_MUTATION_REPOS"] = " xlite, iptv_apps ,xlite,../x,billwatch "
check("M2 OVN_MUTATION_REPOS is parsed (trimmed, deduped, no path-like names)", mu.supply_repos() == ["xlite", "iptv_apps", "billwatch"], mu.supply_repos())
del os.environ["OVN_MUTATION_REPOS"]
check("M3 default mode is shadow", mu.supply_mode() == "shadow")
bl = os.path.join(root, "backlog", "xlite.md")
got = mu.supply_repo("xlite", now=NOW, out=sink)
check("M4 shadow: returns the top-3 candidates (default OVN_MUTATION_TOPN)", len(got) == 3 and all("gd-mutation-survivor" in x for x in got), got)
check("M5 shadow: the backlog is NOT touched, no seen state written", r(bl) == "# b\n" and not os.path.exists(os.path.join(root, "state", "work_supply_seen_xlite")))
sh_log = r(os.path.join(root, "state", "mutation_supply_shadow.log"))
check("M6 shadow: one WOULD-APPEND line per item in state/mutation_supply_shadow.log", sh_log.count("WOULD-APPEND") == 3 and "[shadow] xlite" in sh_log, sh_log)
check("M7 shadow still runs the red-before spec check on the candidates", len(CHECKED) == 1 and len(CHECKED[0]) == 3)
os.environ["OVN_MUTATION_SUPPLY"] = "on"
got = mu.supply_repo("xlite", now=NOW, out=sink)
check("M8 on: 3 items appended to backlog/xlite.md, VERIFY = ovn_mutation_supply.py verify", len(got) == 3 and r(bl).count("- [ ] [T2] tests/test_u") == 3 and "ovn_mutation_supply.py verify" in r(bl), r(bl))
check("M9 on: the items are remembered as supplied", r(os.path.join(root, "state", "work_supply_seen_xlite")).count("supplied") == 3)
got = mu.supply_repo("xlite", now=NOW + 60, out=sink)
check("M10 on, second pass: the 3 are deduped (open in the backlog); the remaining 2 survivors fill up to topn", len(got) == 2 and r(bl).count("- [ ] [T2] tests/test_u") == 5, got)
got = mu.supply_repo("xlite", now=NOW + 120, out=sink)
check("M11 on, third pass: nothing left, nothing appended", got == [] and r(bl).count("- [ ] [T2] tests/test_u") == 5)
# cap on pullable
w(bl, "# b\n" + "".join("- [ ] [T1] scripts/g%d.py - change %d. VERIFY: `true`\n" % (i, i) for i in range(30)))
os.unlink(os.path.join(root, "state", "work_supply_seen_xlite"))
before = r(bl)
got = mu.supply_repo("xlite", now=NOW + 180, out=sink)
check("M12 a lane with >= 24 pullable items gets nothing", got == [] and r(bl) == before, got)
# red-before: a non-red verdict is dropped
w(bl, "# b\n")
ws2.spec_check = lambda repo, lines: {i: "passes-before" for i in range(len(lines))}
got = mu.supply_repo("xlite", now=NOW + 240, out=sink)
check("M13 candidates whose VERIFY is not red on the current checkout are dropped", got == [] and r(bl) == "# b\n", got)
ws2.spec_check = lambda repo, lines: None
got = mu.supply_repo("xlite", now=NOW + 250, out=sink)
check("M14 no usable spec verdict (checker unavailable) appends nothing", got == [] and r(bl) == "# b\n", got)
ws2.spec_check = stub_check
os.environ["OVN_MUTATION_TOPN"] = "1"
got = mu.supply_repo("xlite", now=NOW + 300, out=sink)
check("M15 OVN_MUTATION_TOPN caps the pass", len(got) == 1, got)
del os.environ["OVN_MUTATION_TOPN"]
os.environ["OVN_MUTATION_SUPPLY"] = "off"
check("M16 mode off appends nothing", mu.supply_repo("xlite", now=NOW + 400, out=sink) == [])
os.environ["OVN_MUTATION_SUPPLY"] = "shadow"
os.environ["OVN_MUTATION_REPOS"] = "xlite,nosuchrepo"
res = mu.supply_all(now=NOW + 500, out=sink)
check("M17 supply_all walks every listed repo; a repo without a checkout is skipped, not a failure", "nosuchrepo" in res and res["nosuchrepo"] == [] and any("no checkout" in m for m in msg), msg)
# a source changed since the scan -> survivor dropped
w(os.path.join(xr, "scripts", "u0.gd"), "extends Node\nfunc f(a, b):\n\treturn a - b - 0\n")
os.environ["OVN_MUTATION_SUPPLY"] = "shadow"
os.environ.pop("OVN_MUTATION_REPOS")
w(bl, "# b\n")
got = mu.supply_repo("xlite", now=NOW + 600, out=sink)
check("M18 a survivor whose source changed since the scan is not supplied", not any("scripts/u0.gd" in x.split("VERIFY")[0] and "line 3 of scripts/u0.gd" in x for x in got), got)
os.environ["OVN_SUPPLY_MUTATION"] = "0"
check("M19 collect() (the work-supply hook) stays gated by OVN_SUPPLY_MUTATION", list(mu.collect(xr)) == [])

print("\n%d passed, %d failed" % (P, F))
if F:
    sys.exit(1)

# =========================================================================== mutants (each must make this suite fail)
if "--no-mutants" in sys.argv or os.environ.get("K5C_SCRIPTS"):
    sys.exit(0)
MUT = [
    ("explorer: dot-dir target stripped of every leading dot", "ovn_qwen_explore.py", 'full = pre + (t[2:] if t.startswith("./") else t)', 'full = pre + t.lstrip("./") if not t.startswith("./") else pre + t[2:]'),
    ("local research: bypass logged in dry run / before cooldown", "ovn_local_research.py", 'if bypassed and "--dry-run" not in flags:', "if bypassed:"),
    ("local research: dry run removes the request", "ovn_local_research.py", 'remove=("--dry-run" not in flags)', "remove=True"),
    ("work supply: dry run removes the request", "ovn_work_supply.py", "remove=not dry", "remove=True"),
    ("forecast: README accepted as a repo", "ovn_supply_forecast.py", ' and n.upper() != "README"', ""),
    ("forecast: clone-less roadmap accepted", "ovn_supply_forecast.py", ' and os.path.isdir(os.path.join(root, "repos", n))', ""),
    ("requests: stale requests honoured", "ovn_research_requests.py", "if age > _max_age_s() or age < -300:", "if False:"),
    ("requests: wrong-repo file honoured", "ovn_research_requests.py", 'if not d or d.get("repo") != repo:', "if not d:"),
    ("requests: recovered repo's request kept", "ovn_research_requests.py", "if _forecast_says_not_short(repo, st, now):", "if False:"),
    ("requests: kill switch ignored", "ovn_research_requests.py", 'return os.environ.get("OVN_RESEARCH_REQUESTS", "on").strip().lower() != "off"', "return True"),
    ("requests: pending not ordered by priority", "ovn_research_requests.py", '(0 if x[1].get("priority") == "high" else 1, ', "(0, "),
    ("local research: request never bypasses the ready skip", "ovn_local_research.py", "            if not req:\n                print(", "            if True:\n                print("),
    ("local research: request also bypasses cooldown", "ovn_local_research.py", '        try:\n            if time.time() - float(read(marker) or 0) < COOLDOWN_S:', '        try:\n            if not req and time.time() - float(read(marker) or 0) < COOLDOWN_S:'),
    ("local research: request also bypasses daily cap", "ovn_local_research.py", "        if int(read(cnt) or 0) >= MAX_PER_DAY:", "        if not req and int(read(cnt) or 0) >= MAX_PER_DAY:"),
    ("work supply: request never bypasses MIN_BACKLOG", "ovn_work_supply.py", "        if not rq:\n            print(", "        if True:\n            print("),
    ("work supply: bypass not logged", "ovn_work_supply.py", "        if not dry:\n            rq[0].log(", "        if False:\n            rq[0].log("),
    ("trigger check: request does not lower the floor hours", "ovn_research_trigger_check.py", "eff_h = min(floor_h, req_h) if req else floor_h", "eff_h = floor_h"),
    ("explorer: recursive grep not expanded", "ovn_qwen_explore.py", '    if w[0] in ("grep", "egrep", "fgrep"):\n        return _expand_recursive_grep', '    if False:\n        return _expand_recursive_grep'),
    ("explorer: expansion cap removed", "ovn_qwen_explore.py", "if not files or len(files) > GREP_EXPAND_MAX_FILES:", "if not files:"),
    ("explorer: test chain not merged", "ovn_qwen_explore.py", "    if _TEST_CHAIN_RE.match(v.strip()):\n        return _merge_test_chain(v)", "    if False:\n        return _merge_test_chain(v)"),
    ("explorer: -rs flag not accepted", "ovn_qwen_explore.py", "|-r[a-zA-Z]{1,6}|", "|"),
    ("explorer: verify rejects not capped", "ovn_qwen_explore.py", "    if len(lst) < cap:\n        lst.append", "    if True:\n        lst.append"),
    ("mutation: shadow mode appends", "ovn_mutation_supply.py", '        if mode == "shadow":\n            try:', '        if False:\n            try:'),
    ("mutation: topn cap removed", "ovn_mutation_supply.py", "            if len(specs) >= topn:\n                break", "            if False:\n                break"),
    ("mutation: red-before check dropped", "ovn_mutation_supply.py", '            if v == "red":\n                keep.append', '            if True:\n                keep.append'),
    ("mutation: pullable cap removed", "ovn_mutation_supply.py", "    if have >= cap:", "    if False:"),
    ("mutation: dedupe filter removed", "ovn_mutation_supply.py", "            if why not in (None, \"resupply\"):", "            if False:"),
    ("mutation: default repos not xlite", "ovn_mutation_supply.py", 'os.environ.get("OVN_MUTATION_REPOS"), "xlite")', 'os.environ.get("OVN_MUTATION_REPOS"), "xlite,iptv_apps")'),
    ("mutation: mode off still runs", "ovn_mutation_supply.py", '    if mode == "off":\n        return []\n    import ovn_work_supply', '    import ovn_work_supply'),
    ("mutation: seen state not recorded", "ovn_mutation_supply.py", '            seen[ws.spec_key(sp)] = (now, "supplied")', "            pass"),
    ("mutation: collect gate removed", "ovn_mutation_supply.py", 'if os.environ.get("OVN_SUPPLY_MUTATION", "0") != "1":', "if False:"),
]
tmpd = tempfile.mkdtemp(prefix="k5-consume-mut-")
bad = 0
try:
    for fn in os.listdir(SCRIPTS):
        if fn.endswith((".py", ".sh")):
            shutil.copy(os.path.join(SCRIPTS, fn), tmpd)
    for name, f, old, new in MUT:
        src = open(os.path.join(SCRIPTS, f)).read()
        if old not in src:
            print("  MUTANT SETUP FAIL (pattern not found): " + name)
            bad += 1
            continue
        open(os.path.join(tmpd, f), "w").write(src.replace(old, new, 1))
        rr_ = subprocess.run([sys.executable, os.path.abspath(__file__), "--no-mutants"], env=dict(os.environ, K5C_SCRIPTS=tmpd), capture_output=True, text=True, timeout=300)
        killed = rr_.returncode != 0
        print("  %s MUTANT %s" % ("killed  " if killed else "SURVIVED", name))
        bad += 0 if killed else 1
        shutil.copy(os.path.join(SCRIPTS, f), tmpd)
finally:
    shutil.rmtree(tmpd, ignore_errors=True)
print("  mutants: %d of %d survived" % (bad, len(MUT)))
sys.exit(1 if bad else 0)
