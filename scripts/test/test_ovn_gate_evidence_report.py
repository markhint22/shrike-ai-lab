#!/usr/bin/env python3
"""ovn_gate_evidence_report.py (package K6): per-gate shadow evidence joined with later outcomes, UNVERIFIED kept separate, promote/HOLD rule, tool-missing reason codes,
card_credit no-card noise suppression, OFF-by-default digest hook.

Fixtures: scripts/test/fixtures_gate_evidence/state holds a handful of REAL rows copied read-only from the box (2026-11-01; secrets scrubbed - these shapes carry none): qa_shadow
card_credit/scanners/antigaming/mutation, spec_gate, executor_shadow.log, stage_runs events + stage_credited.ledger, and the outcomes they join to. The join / rule scenarios use
rows of exactly the same shapes written into a temp dir. MUTANTS: each of the join precedence, the 24h window, and the 'UNVERIFIED is not clean' rule is broken in a copy of the
module and the matching scenario must FAIL; the card_credit once-log is broken in a copy and the CLI scenario must FAIL."""
import calendar
import hashlib
import itertools
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
SRC = os.path.join(OQ, "ovn_gate_evidence_report.py")
FIX = os.path.join(HERE, "fixtures_gate_evidence", "state")
PY = sys.executable
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:500]) if extra else ""))


for k in list(os.environ):
    if k.startswith("OVN_GER_") or k.startswith("OVN_QA_") or k in ("QA_STATE_DIR", "OVN_STATE_DIR", "OVN_DIR"):
        del os.environ[k]
# hermetic: never spawn git against real clones (~/overnight-queue/repos on the box); the K1 join tests own the git-verified scenarios
os.environ.update({"TZ": "UTC", "NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "OVN_GER_GIT": "off", "OVN_GER_REPOS": "/nonexistent-ger-repos", "OVN_DIR": "/nonexistent-ovn-dir"})
T = os.path.realpath(tempfile.mkdtemp(prefix="gev-test-"))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mutant(name, old, new):
    src = open(SRC).read()
    assert old in src, "mutation anchor missing: " + old
    p = os.path.join(T, name + ".py")
    open(p, "w").write(src.replace(old, new, 1))
    return load(p, name)


def ts(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


NOW = float(calendar.timegm((2026, 11, 20, 12, 0, 0)))
DAY = 86400


class State(object):
    """Temp state dir writer using the real row shapes."""

    _n = itertools.count()

    def __init__(self, tag):
        self.d = os.path.join(T, "%s-%d" % (tag, next(State._n)))
        os.makedirs(os.path.join(self.d, "qa_shadow"))
        self.outs, self.sh = [], {}

    def shadow(self, gate, t, verdict, repo="billwatch", ref="a" * 40, summary="s", details=None):
        self.sh.setdefault(gate, []).append({"ts": ts(t), "gate": gate, "repo": repo, "ref": ref, "verdict": verdict, "mode": "shadow", "summary": summary,
                                             "details": details or {}, "ms": 5})

    def outcome(self, t, repo="billwatch", cls="landed", status="pushed(tests:pass)", fail="", commits=(), ih="", feat=""):
        self.outs.append({"ts": ts(t), "repo": repo, "id": "ongoing-" + repo, "type": "aider_fix", "tier": "1", "class": cls, "status": status, "fail_reason": fail,
                          "commits": list(commits), "head_after": (commits[-1] if commits else ""), "item_hash": ih, "feat_tag": feat})

    def flush(self):
        for g, rows in self.sh.items():
            open(os.path.join(self.d, "qa_shadow", g + ".jsonl"), "w").write("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        open(os.path.join(self.d, "outcomes.jsonl"), "w").write("".join(json.dumps(r, sort_keys=True) + "\n" for r in self.outs))
        return self.d


def gate(rep, name):
    return next(g for g in rep["gates"] if g["gate"] == name)


def sha(n):
    return hashlib.sha1(str(n).encode()).hexdigest()


# ------------------------------------------------------------------------------------------------------------------------ scenarios (module-parameterised)
def scen_join(m):
    """returns dict of named booleans for the join logic; used for real runs AND mutants."""
    s = State("join")
    t0 = NOW - 10 * DAY
    # 1: FLAG, landed green only                      -> green
    s.shadow("antigaming", t0, "FLAG", ref="b" * 40 + ".." + sha(1))
    s.outcome(t0 + 60, commits=[sha(1)], ih="h1" + "0" * 30)
    # 2: FLAG, landed then the item was reverted 2h later (revert row has the item hash, not the commit) -> bad
    s.shadow("antigaming", t0 + 100, "FLAG", ref=sha(2))
    s.outcome(t0 + 160, commits=[sha(2)], ih="h2" + "0" * 30)
    s.outcome(t0 + 7200, cls="noop", status="no-op(reverted-red)", fail="test-red", ih="h2" + "0" * 30)
    # 3: FLAG, reverted only 30h later -> outside the 24h window -> green
    s.shadow("antigaming", t0 + 200, "FLAG", ref=sha(3))
    s.outcome(t0 + 260, commits=[sha(3)], ih="h3" + "0" * 30)
    s.outcome(t0 + 200 + 30 * 3600, cls="reverted", status="reverted(build-break)", fail="build-red", ih="h3" + "0" * 30)
    # 4: FLAG in another repo with the same item hash as #1 must not join -> unjoined
    s.shadow("antigaming", t0 + 300, "FLAG", repo="gitlark", ref=sha(4), details={"item_key": "h1" + "0" * 14})
    # 5: FAIL, parked
    s.shadow("antigaming", t0 + 400, "FAIL", ref=sha(5))
    s.outcome(t0 + 450, commits=[sha(5)], ih="h5" + "0" * 30)
    s.outcome(t0 + 900, cls="noop", status="no-op(parked)", ih="h5" + "0" * 30)
    # 6: UNVERIFIED with a later green landing: counted ONLY as UNVERIFIED
    s.shadow("antigaming", t0 + 500, "UNVERIFIED", ref=sha(6), summary="part of the diff could not be analysed")
    s.outcome(t0 + 560, commits=[sha(6)])
    # 7: FLAG nothing decisive yet (matched row is a noop) -> unresolved
    s.shadow("antigaming", t0 + 600, "FLAG", ref=sha(7))
    s.outcome(t0 + 650, cls="noop", status="no-op(ALREADY-DONE)", commits=[sha(7)])
    rep = m.build(s.flush(), days=30, now=NOW)
    g = gate(rep, "antigaming")
    fl, fa = g["classes"]["FLAG"], g["classes"]["FAIL"]
    return {
        "green_only": fl["green"] == 2 and fl["reverted_parked"] == 1,            # #1, #3 green; #2 bad
        "later_revert_found_by_item_hash": fl["reverted_parked"] == 1,
        "window_excludes_30h_revert": fl["green"] == 2,
        "other_repo_not_joined": fl["unjoined"] == 1,
        "fail_parked_is_bad": fa["reverted_parked"] == 1 and fa["green"] == 0,
        "noop_is_unresolved": fl["unresolved"] == 1,
        "unverified_separate": g["classes"]["UNVERIFIED"]["n"] == 1 and "green" not in g["classes"]["UNVERIFIED"],
        "unverified_not_in_precision": g["flag_fail_decided"] == 4,                 # 3 FLAG(1,2,3)+1 FAIL decided
        "pct": fl["pct_green"] == 66.7 and fl["pct_reverted_parked"] == 33.3,
    }


def scen_unverified_not_clean(m):
    s = State("clean")
    for i in range(20):                                  # 20 clean days of PASS rows, then today UNVERIFIED too
        s.shadow("gdparse", NOW - i * DAY - 3600, "PASS")
    s.shadow("gdparse", NOW - 600, "UNVERIFIED", summary="gdparse not installed")
    rep = m.build(s.flush(), days=30, now=NOW)
    g = gate(rep, "gdparse")
    return {"unverified_day_breaks_run": g["clean_days"] == 0, "clean_days_without_unverified": True}


def scen_rule(m):
    out = {}

    def mk(tag, days, events, bad_frac, unverified_today=False, decided_all=True):
        s = State(tag)
        for i in range(days):
            s.shadow("migrations", NOW - i * DAY - 7200, "PASS")
        for i in range(events):
            t = NOW - (i % max(days, 1)) * DAY - 30000 - i
            s.shadow("migrations", t, "FLAG", ref=sha(1000 + i))
            bad = i < int(round(events * bad_frac))
            s.outcome(t + 60, commits=[sha(1000 + i)], ih=sha(5000 + i))
            if bad:
                s.outcome(t + 3600, cls="noop", status="no-op(reverted-red)", fail="test-red", ih=sha(5000 + i))
        if unverified_today:
            s.shadow("migrations", NOW - 60, "UNVERIFIED", summary="x")
        return gate(m.build(s.flush(), days=40, now=NOW), "migrations")
    ok_g = mk("r_ok", 15, 40, 0.9)
    out["promote_when_all_met"] = ok_g["recommendation"] == "PROMOTE-CANDIDATE" and ok_g["clean_days"] >= 14
    out["hold_low_precision"] = mk("r_prec", 15, 40, 0.5)["recommendation"] == "HOLD"
    out["hold_29_events"] = mk("r_n", 15, 29, 1.0)["recommendation"] == "HOLD"
    out["hold_13_days"] = mk("r_days", 13, 40, 1.0)["recommendation"] == "HOLD"
    u = mk("r_unv", 15, 40, 1.0, unverified_today=True)
    out["hold_when_unverified_today"] = u["recommendation"] == "HOLD" and u["clean_days"] == 0
    out["reason_text"] = any("clean days" in r for r in mk("r_days2", 13, 40, 1.0)["reasons"])
    return out


# ------------------------------------------------------------------------------------------------------------------------ run
M = load(SRC, "ger")
ok("hermetic: Git() resolves no clone root (OVN_GER_GIT=off, no real repos touched)", M.Git().root is None and M.Git("/nonexistent-ger-repos").root is None)
print("fixtures: real rows copied from the box")
rep = M.build(FIX, days=3650, now=float(calendar.timegm((2026, 11, 1, 20, 0, 0))))
names = {g["gate"] for g in rep["gates"]}
ok("fixture gates present", {"card_credit", "scanners", "antigaming", "mutation", "spec_gate", "executor:ruff", "item_verify"} <= names, sorted(names))
cc = gate(rep, "card_credit")
ok("card_credit: 3 real FLAG rows join to their landed outcomes (green, 0 unjoined)", cc["classes"]["FLAG"]["green"] == 3 and cc["classes"]["FLAG"]["unjoined"] == 0, cc["classes"])
ok("card_credit: all-FLAG fact is reported as silence-worthy", any("card_credit fired FLAG on 3/3" in x and "silence-worthy" in x for x in rep["known_facts"]), rep["known_facts"])
sc = gate(rep, "scanners")
ok("scanners: tool-missing UNVERIFIED rows (real text, no reason_code) are recognised and named",
   sc["unverified"]["reason_codes"].get("tool-missing") == 2 and {"ruff", "bandit", "gitleaks"} <= set(sc["unverified"]["tools_missing"]), sc["unverified"])
ok("scanners: report calls out 'tool missing' and the gate stays HOLD", any(r.startswith("tool missing") for r in sc["reasons"]) and sc["recommendation"] == "HOLD", sc["reasons"])
mu = gate(rep, "mutation")
ok("mutation: wall-cap UNVERIFIED is coded 'cap', not tool-missing (honest reason)", mu["unverified"]["reason_codes"] == {"cap": 1}, mu["unverified"])
iv = gate(rep, "item_verify")
ok("item_verify: stage_runs events + ledger -> 'would have blocked N, credited anyway N'", any("item_verify would have blocked 2 case(s); 2 of them were credited anyway" in x for x in rep["known_facts"]), rep["known_facts"])
ok("item_verify: blocks joined via feat tag", iv["classes"]["FLAG"]["unjoined"] == 0, iv["classes"])
sp = gate(rep, "spec_gate")
ok("spec_gate: quarantine:* -> FAIL joined by feat tag", sp["classes"]["FAIL"]["unjoined"] == 0 and sp["classes"]["FAIL"]["n"] == 2, sp["classes"])
import subprocess as _sp
_ci = _sp.run(["git", "check-ignore", "-q", "--no-index", os.path.join(FIX, "executor_shadow.log")], cwd=HERE, capture_output=True)
ok("fixture executor_shadow.log is not gitignored (must be committable; *.log rule regression)", _ci.returncode != 0, _ci.returncode)
ex = gate(rep, "executor:ruff")
ok("executor_shadow.log: would-apply -> FLAG joined by item_hash", ex["classes"]["FLAG"]["n"] == 2 and ex["classes"]["FLAG"]["unjoined"] == 0, ex["classes"])
ok("no gate in the fixture is a PROMOTE-CANDIDATE", all(g["recommendation"] == "HOLD" for g in rep["gates"]))

print("join logic")
real = scen_join(M)
for k, v in sorted(real.items()):
    ok("join: " + k, v, real)
ok("unverified: a day with an UNVERIFIED row is never clean", scen_unverified_not_clean(M)["unverified_day_breaks_run"])
rule = scen_rule(M)
for k, v in sorted(rule.items()):
    ok("rule: " + k, v, rule)

print("mutation proofs (each mutant must break its scenario)")
m1 = mutant("m_good_wins", 'if any(k == "bad" for _, k in inwin):\n        return "bad"\n    if any(k == "green" for _, k in inwin):\n        return "green"',
            'if any(k == "green" for _, k in inwin):\n        return "green"\n    if any(k == "bad" for _, k in inwin):\n        return "bad"')
r1 = scen_join(m1)
ok("MUTANT green-beats-bad: later revert no longer found -> scenario fails", not all(r1.values()) and not r1["later_revert_found_by_item_hash"], r1)
m2 = mutant("m_nowindow", "if lo <= t <= hi]", "if True]")
r2 = scen_join(m2)
ok("MUTANT no 24h window: the 30h-late revert counts -> scenario fails", not r2["window_excludes_30h_revert"], r2)
m3 = mutant("m_commit_only", "hs = {h for x in first for h in x[3]}", "hs = set()")
r3 = scen_join(m3)
ok("MUTANT no second hop: revert row (item_hash only) is missed -> scenario fails", not r3["later_revert_found_by_item_hash"], r3)
m4 = mutant("m_unv_clean", "if v > 0 and u == 0:", "if v > 0:")
r4 = scen_unverified_not_clean(m4)
ok("MUTANT UNVERIFIED counted as clean: scenario fails", not r4["unverified_day_breaks_run"], r4)
m5 = mutant("m_prec", "elif prec < min_prec:", "elif False:")
r5 = scen_rule(m5)
ok("MUTANT precision check removed: low-precision gate gets promoted -> scenario fails", not r5["hold_low_precision"], r5)
m6 = mutant("m_samebad", 'if cls in BAD_CLASSES or "revert" in st or "park" in st or (r.get("fail_reason") in BAD_FAIL_REASONS):', "if False:")
r6 = scen_join(m6)
ok("MUTANT outcomes never 'bad': scenario fails", not all(r6.values()), r6)

print("CLI, --json, --digest, hook")
env = dict(os.environ, OVN_GER_NOW=str(calendar.timegm((2026, 11, 1, 20, 0, 0))), OVN_STATE_DIR=FIX)
j = subprocess.run([PY, SRC, "--json", "--days", "3650"], capture_output=True, text=True, env=env)
try:
    jd = json.loads(j.stdout)
except ValueError:
    jd = {}
ok("--json is valid JSON with gates + rule + known_facts", j.returncode == 0 and jd.get("gates") and jd.get("rule", {}).get("min_clean_days") == 14 and jd.get("known_facts"), j.stdout[:200] + j.stderr[:200])
t = subprocess.run([PY, SRC, "--days", "3650"], capture_output=True, text=True, env=env)
ok("text report shows the rule, UNVERIFIED separate, and the tool-missing call-out", "UNVERIFIED  n=" in t.stdout and "tool missing:" in t.stdout and "promote only with >= 14 clean days" in t.stdout, t.stdout[:400])
d = subprocess.run([PY, SRC, "--digest", "--days", "3650"], capture_output=True, text=True, env=env)
ok("--digest prints exactly one bullet", len(d.stdout.strip().splitlines()) == 1 and d.stdout.startswith("Gate evidence:"), d.stdout)
e = subprocess.run([PY, SRC, "--days", "3650"], capture_output=True, text=True, env=dict(env, OVN_STATE_DIR=os.path.join(T, "nonexistent")))
ok("missing state dir: no crash, exit 0", e.returncode == 0)
dn = open(os.path.join(OQ, "digest_notify.sh")).read()
ok("digest_notify.sh hook exists and is OFF by default (OVN_GATE_EVIDENCE_DIGEST:-off)", "ovn_gate_evidence_report.py" in dn and 'OVN_GATE_EVIDENCE_DIGEST:-off' in dn)
import re as _re
ok("read-only: the tool has no write/append/remove call", not _re.search(r"open\([^)]*['\"][wax]b?['\"]|os\.remove|shutil\.rmtree|\.write\(", open(SRC).read().split("def main")[0]))

print("gate-code changes")
GS = load(os.path.join(OQ, "qa", "gate_scanners.py"), "gs") if os.path.isfile(os.path.join(OQ, "qa", "gate_scanners.py")) else None
cells = {"ruff": {"status": "UNVERIFIED", "note": "ruff not installed"}, "bandit": {"status": "OK", "note": ""}, "gitleaks": {"status": "UNVERIFIED", "note": "gitleaks failed rc=1"},
         "mypy": {"status": "NA", "note": "mypy not installed"}}
miss = GS.mark_tool_missing(cells)
ok("scanners.mark_tool_missing: only UNVERIFIED 'not installed' cells are coded", miss == ["ruff"] and cells["ruff"]["reason_code"] == "tool-missing"
   and "reason_code" not in cells["gitleaks"] and "reason_code" not in cells["mypy"], (miss, cells))
ok("report honours an explicit reason_code over text", M.unverified_reason({"summary": "whatever", "details": {"reason_code": "tool-missing", "tools_missing": ["ruff"]}}) == ("tool-missing", ["ruff"]))
ok("mutation skip rows get reason_code tool-missing", 'row["reason_code"] = "tool-missing"' in open(os.path.join(OQ, "qa", "gate_mutation.py")).read())

# card_credit once-log via the real CLI
CP = os.path.join(OQ, "qa", "card_pilot_run.py")


def run_credit(script, state, n, extra_env=None):
    e2 = {k: v for k, v in os.environ.items()}
    e2.update(QA_STATE_DIR=state, OVN_QA_CARD_CREDIT="shadow")
    e2.update(extra_env or {})
    for _ in range(n):
        subprocess.run([PY, script, "credit", "--repo", "iptv_apps", "--head", "a" * 40, "--item", "- [x] [T2] app/util.py — Add `never_carded()` that returns 7", "--no-stdout"],
                       capture_output=True, text=True, env=e2, cwd=OQ + "/qa", timeout=60)
    p = os.path.join(state, "qa_shadow", "card_credit.jsonl")
    rows = [json.loads(x) for x in open(p)] if os.path.exists(p) else []
    sk = os.path.join(state, "qa_gate_skips.jsonl")
    skips = [json.loads(x) for x in open(sk)] if os.path.exists(sk) else []
    return rows, skips


st = os.path.join(T, "cc1")
os.makedirs(st)
rows, skips = run_credit(CP, st, 4)
ok("card_credit no-card: 4 credits -> exactly ONE row + ONE one-time note", len(rows) == 1 and rows[0]["verdict"] == "FLAG" and len(skips) == 1 and skips[0]["reason_code"] == "no-cards-for-repo", (len(rows), skips))
st = os.path.join(T, "cc2")
os.makedirs(st)
rows, skips = run_credit(CP, st, 3, {"OVN_QA_CARD_CREDIT_NOCARD": "rows"})
ok("card_credit OVN_QA_CARD_CREDIT_NOCARD=rows restores a row per credit", len(rows) == 3 and not skips, (len(rows), skips))
st = os.path.join(T, "cc3")
os.makedirs(st)
os.makedirs(os.path.join(st, "qa_shadow"))
open(os.path.join(st, "qa_shadow", "card_pilot.jsonl"), "w").write("")
src_cp = open(CP).read()
old = "        if _nocard_is_noise(a.repo):\n"
ok("mutation anchor present in card_pilot_run.py", old in src_cp)
mp = os.path.join(OQ, "qa", "_mut_card_pilot_run_tmp.py")
try:
    open(mp, "w").write(src_cp.replace(old, "        if False:\n", 1))
    st = os.path.join(T, "cc4")
    os.makedirs(st)
    rows, skips = run_credit(mp, st, 4)
    ok("MUTANT card_credit noise suppression removed: 4 rows written -> scenario fails", len(rows) == 4, len(rows))
finally:
    try:
        os.remove(mp)
    except OSError:
        pass

shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
