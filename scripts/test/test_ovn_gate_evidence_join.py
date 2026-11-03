#!/usr/bin/env python3
"""K1 evidence join repair (2026-11-03): ovn_gate_evidence_report.py joins + --explain, qa/qa_flag_sample.py hand-label worksheet.

Row shapes below are copied from the box's real state (2026-11-03, read-only; no secrets in these shapes): a card_credit FLAG whose ref is an INTERMEDIATE commit and whose outcome
row (written ~4 s later) has an EMPTY commits list and only head_after (the cycle tip); an antigaming FLAG whose ref is base..head and whose outcome rows carry head_before/head_after;
a card_credit item_key that is sha1(path|desc)[:16] (a different hash space than outcomes.item_hash = md5).
Root causes proven on the real data: 477/1011 card_credit and 179/226 antigaming FLAG/FAIL rows were unjoined (358 card_credit rows predate the first non-empty outcomes.commits;
sha is an ancestor of the cycle tip in 35 of 40 git-checked samples; antigaming ranges join through base == head_before or `git rev-list base..head`).
MUTANTS (each breaks a copy of the module / tool and the matching scenario must FAIL): drop the sha join, drop the cycle join, drop the head_before/base join, drop the git range
join, accept a git-rejected cycle join, re-add item_key as an item hash, drop the window-opens-at-first-hop rule, in the sampler: stop skipping labelled rows / stop round-robin."""
import calendar
import hashlib
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
SAMPLER = os.path.join(OQ, "qa", "qa_flag_sample.py")
GOV = os.path.join(OQ, "scripts", "ovn_gate_governor.py")
PY = sys.executable
P = F = 0
for k in list(os.environ):
    if k.startswith("OVN_GER_") or k.startswith("OVN_QA_") or k in ("QA_STATE_DIR", "OVN_STATE_DIR", "OVN_DIR"):
        del os.environ[k]
os.environ.update({"TZ": "UTC", "NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "OVN_GER_GIT": "off"})
T = os.path.realpath(tempfile.mkdtemp(prefix="gev-join-"))
_n = [0]


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:600]) if extra else ""))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mutant(src_path, name, old, new):
    src = open(src_path).read()
    assert old in src, "mutation anchor missing: " + old
    d = os.path.join(T, "mut-" + name)
    os.makedirs(os.path.join(d, "qa"), exist_ok=True)
    # a mutated copy keeps the tree shape (the sampler loads ../ovn_gate_evidence_report.py)
    shutil.copy(SRC, os.path.join(d, "ovn_gate_evidence_report.py"))
    out = os.path.join(d, os.path.relpath(src_path, OQ))
    open(out, "w").write(src.replace(old, new, 1))
    return load(out, name)


def ts(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


NOW = float(calendar.timegm((2026, 11, 3, 12, 0, 0)))
T0 = NOW - 5 * 86400


def sha(n):
    return hashlib.sha1(("k1-%s" % n).encode()).hexdigest()


class S(object):
    def __init__(self):
        _n[0] += 1
        self.d = os.path.join(T, "st%d" % _n[0])
        os.makedirs(os.path.join(self.d, "qa_shadow"))
        self.sh, self.outs = {}, []

    def credit(self, t, repo, ref, key="f4f5a4c0ac3bcab6"):
        self.sh.setdefault("card_credit", []).append({"details": {"card_existed": False, "credit_without_card": True, "item_key": key, "path": "app/x.py", "verify_passed_at_head": None},
                                                      "gate": "card_credit", "mode": "shadow", "ms": 3, "ref": ref, "repo": repo, "summary": "credit_without_card: no S0 card exists for the credited item",
                                                      "ts": ts(t), "verdict": "FLAG"})

    def anti(self, t, repo, base, head, rule="D_DEAD_SYMBOL"):
        self.sh.setdefault("antigaming", []).append({"details": {"code_files": 1, "counts": {rule: 1}, "findings": [{"file": "a.gd", "line": 4, "msg": "m", "rule": rule, "sev": "FLAG", "snip": "s"}], "frozen": "NA: no manifest",
                                                                 "notes": [], "truncated": False}, "gate": "antigaming", "mode": "shadow", "ms": 91, "ref": "%s..%s" % (base, head), "repo": repo,
                                                     "summary": "1 finding(s)", "ts": ts(t), "verdict": "FLAG"})

    def flag(self, gate_name, t, repo, ref, verdict="FLAG"):
        self.sh.setdefault(gate_name, []).append({"details": {}, "gate": gate_name, "mode": "shadow", "ms": 3, "ref": ref, "repo": repo, "summary": "finding", "ts": ts(t), "verdict": verdict})

    def out(self, t, repo, cls="landed", commits=(), before="", after="", ih="", feat="", status="pushed(tests:pass)", fail=""):
        self.outs.append({"ts": ts(t), "repo": repo, "id": "ongoing-" + repo, "type": "aider_fix", "tier": "3", "category": "schema", "class": cls, "severity": "good", "attempt": 1, "attempts": 1, "bestn_stop": "",
                          "fail_reason": fail, "status": status, "item_hash": ih, "feat_tag": feat, "commits": list(commits), "head_before": before, "head_after": after})

    def flush(self):
        for g, rows in self.sh.items():
            open(os.path.join(self.d, "qa_shadow", g + ".jsonl"), "w").write("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        open(os.path.join(self.d, "outcomes.jsonl"), "w").write("".join(json.dumps(r, sort_keys=True) + "\n" for r in self.outs))
        return self.d


def gate(rep, n):
    return next(g for g in rep["gates"] if g["gate"] == n)


def run_cli(args, extra_env=None):
    env = dict(os.environ)
    env.update(extra_env or {})
    return subprocess.run([PY, SRC] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, env=env)


# ------------------------------------------------------------------------------------------------------------------------ scenarios
def scen_credit(m, strict=False, unv=True):
    """card_credit: (1) sha == outcome head_after -> sha; (2) INTERMEDIATE commit, outcome 4 s later with empty commits -> cycle; (3) credit with no row near -> unjoined;
    (4) item_key that is a prefix of an UNRELATED row's item_hash must not join."""
    s = S()
    s.credit(T0, "billwatch", sha(1))
    s.out(T0 + 4, "billwatch", after=sha(1), ih="aa" * 16)                         # 1: tip == credited commit
    s.credit(T0 + 1000, "gitlark", sha(2))
    s.out(T0 + 1004, "gitlark", after=sha(99), before=sha(98), ih="bb" * 16)       # 2: intermediate commit, row ~4 s later, commits [] (pre-2026-10-22 shape)
    s.credit(T0 + 2000, "xlite", sha(3))
    s.out(T0 + 9000, "xlite", after=sha(97), ih="cc" * 16)                         # 3: nearest row is 7000 s later: not this cycle
    s.credit(T0 + 3000, "iptv_apps", sha(4), key="deadbeefdeadbeef")
    s.out(T0 + 90000, "iptv_apps", cls="landed", ih="deadbeefdead" + "0" * 20)      # 4: unrelated row whose item_hash starts with the credit's item_key
    d = s.flush()
    if unv:
        os.environ["OVN_GER_CYCLE_UNVERIFIED"] = "on"
    try:
        rep = m.build(d, 30, now=NOW, strict=strict)
    finally:
        os.environ.pop("OVN_GER_CYCLE_UNVERIFIED", None)
    g = gate(rep, "card_credit")
    return rep, g


def scen_anti(m, git=None):
    s = S()
    # base == head_before of the cycle row (same cycle), head not a recorded tip
    s.anti(T0, "xlite", sha(10), sha(11))
    s.out(T0 + 50, "xlite", before=sha(10), after=sha(12), ih="d1" * 16)
    # event head == head_before of a LATER row: that row is the NEXT item, must NOT join
    s.anti(T0 + 500, "gitlark", sha(20), sha(21))
    s.out(T0 + 900, "gitlark", before=sha(21), after=sha(22), ih="d2" * 16)
    # exact tip
    s.anti(T0 + 1000, "billwatch", sha(30), sha(31))
    s.out(T0 + 1010, "billwatch", after=sha(31), ih="d3" * 16)
    rep = m.build(s.flush(), 30, now=NOW, git=git)
    return rep, gate(rep, "antigaming")


def scen_window(m):
    """antigaming BASE join: the landing row PRECEDES the event by > slack (2000 s) and a revert lands 600 s before the event: the window opens at the first matched row -> bad.
    Post-hoc gate (scanners) sha-joined to a row 20 h earlier, and an antigaming base join 20 h earlier: NOT green (cap OVN_GER_BACK_S / join kind) -> unresolved."""
    s = S()
    s.anti(T0 + 7000, "gitlark", sha(50), sha(52))
    s.out(T0 + 5000, "gitlark", before=sha(50), after=sha(51), ih="e2" * 16)                                        # landed 2000 s BEFORE the event
    s.out(T0 + 5500, "gitlark", cls="reverted", status="reverted(build-break)", fail="build-red", ih="e2" * 16)      # reverted 1500 s before the event (> slack)
    s.flag("scanners", T0 + 72000, "billwatch", sha(60))
    s.out(T0, "billwatch", after=sha(60), ih="e3" * 16)                                                             # the sha-joined row landed 20 h before the scanners FLAG
    s.flag("scanners", T0 + 80000, "iptv_apps", sha(61))
    s.out(T0 + 78000, "iptv_apps", after=sha(61), ih="e5" * 16)                                                     # sha-joined row 2000 s earlier (> slack, < cap): still not green for a post-hoc gate
    s.anti(T0 + 72000, "xlite", sha(70), sha(72))
    s.out(T0, "xlite", before=sha(70), after=sha(71), ih="e4" * 16)                                                 # base join to a row 20 h earlier
    rep = m.build(s.flush(), 30, now=NOW)
    return gate(rep, "antigaming"), gate(rep, "scanners")


M = load(SRC, "ger_real")

print("card_credit joins (real shapes)")
rep, g = scen_credit(M)
ok("joined_by: 1 sha + 1 cycle; 2 unjoined", g["flag_fail_joined_by"] == {"sha": 1, "cycle-unverified": 1} and g["flag_fail_unjoined"] == 2, g)
ok("unjoined reasons honest (no-key for the far row and the item_key lookalike)", g["flag_fail_unjoined_why"] == {"no-key": 2}, g["flag_fail_unjoined_why"])
ok("item_key prefix lookalike does not join an unrelated row", g["flag_fail_unjoined"] >= 1 and g["flag_fail_joined_by"].get("hash", 0) == 0, g)
ok("a credit whose nearest row is 7000 s later is not cycle-joined", g["flag_fail_unjoined"] == 2)
ok("card_credit joined rows are green (landed rows), decided", g["flag_fail_decided"] == 2 and g["flag_fail_green"] == 2, g)
_, gd = scen_credit(M, unv=False)
ok("DEFAULT: an unverifiable (no clone) cycle join is NOT joined/decided: joined_by {sha:1}, decided 1, cycle-time-only 1",
   gd["flag_fail_joined_by"] == {"sha": 1} and gd["flag_fail_decided"] == 1 and gd["flag_fail_unjoined_why"] == {"no-key": 2, "cycle-time-only": 1} and gd["flag_fail_cycle_time_only"] == 1, gd)
rep_s, gs = scen_credit(M, strict=True)
ok("--strict: the cycle join is dropped (only sha remains)", gs["flag_fail_joined_by"] == {"sha": 1} and gs["flag_fail_unjoined"] == 3, gs)
ok("report carries the git/strict flags", rep_s["strict"] is True and rep["strict"] is False and rep["git_verified_joins"] is False)

print("antigaming joins")
rep, a = scen_anti(M)
ok("base==head_before joins as 'base'; exact tip joins as 'sha'", a["flag_fail_joined_by"] == {"base": 1, "sha": 1}, a)
ok("event head == LATER row's head_before is NOT a join (that is the next item)", a["flag_fail_unjoined"] == 1, a)

print("window opens at the first matched row")
wa, wsc = scen_window(M)
ok("base join: landing 2000 s before the event + revert 1500 s before it -> bad (window opens at the first matched row)", wa["flag_fail_reverted_parked"] == 1, wa)
ok("antigaming base join to a row 20 h earlier is capped: unresolved, not green", wa["flag_fail_green"] == 0 and wa["flag_fail_unresolved"] == 1, wa)
ok("scanners FLAG sha-joined to a row 20 h earlier is NOT a false positive (flag_fail_green == 0, unresolved 2 incl. a 2000 s-earlier row)", wsc["flag_fail_green"] == 0 and wsc["flag_fail_unresolved"] == 2 and wsc["flag_fail_joined_by"] == {"sha": 2}, wsc)

print("git-verified range + ancestry (real throw-away repo)")
repos = os.path.join(T, "repos")
rd = os.path.join(repos, "xlite")
os.makedirs(rd)
envg = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e.x", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@e.x")


def git(*a):
    return subprocess.run(["git", "-C", rd] + list(a), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, env=envg, check=True).stdout.strip()


git("init", "-q", "-b", "main")
shas = []
for i in range(4):
    open(os.path.join(rd, "f%d" % i), "w").write(str(i))
    git("add", "-A")
    git("commit", "-q", "-m", "c%d" % i)
    shas.append(git("rev-parse", "HEAD"))
git("checkout", "-q", "-b", "side", shas[0])
open(os.path.join(rd, "side"), "w").write("s")
git("add", "-A")
git("commit", "-q", "-m", "side")
side = git("rev-parse", "HEAD")
os.environ["OVN_GER_GIT"] = "on"
GIT = M.Git(repos)
os.environ["OVN_GER_GIT"] = "off"
ok("Git.range returns the commits of base..head", GIT.range("xlite", shas[0], shas[3]) == set(shas[1:]), GIT.range("xlite", shas[0], shas[3]))
ok("Git.is_ancestor true/false/unknown", GIT.is_ancestor("xlite", shas[1], shas[3]) is True and GIT.is_ancestor("xlite", side, shas[3]) is False and GIT.is_ancestor("nope", shas[1], shas[3]) is None)


def scen_git(m):
    s = S()
    # antigaming range base..tip covering 3 commits; the outcome row only knows an intermediate head_after (shas[2]); head (shas[3]) is not a recorded tip
    s.anti(T0 + 5000, "xlite", shas[0], shas[2])
    s.out(T0 + 4000, "xlite", after=shas[1], before=sha(7), ih="f1" * 16)
    # card_credit: credited commit shas[2] is an ancestor of the cycle tip shas[3] (git-verified cycle)
    s.credit(T0 + 8000, "xlite", shas[2])
    s.out(T0 + 8004, "xlite", after=shas[3], ih="f2" * 16)
    # card_credit: credited commit is NOT an ancestor of the row's tip (the 12% the time-only rule would misattribute) -> rejected
    s.credit(T0 + 9000, "xlite", side)
    s.out(T0 + 9004, "xlite", after=shas[3], ih="f3" * 16)
    os.environ["OVN_GER_GIT"] = "on"
    try:
        return m.build(s.flush(), 30, now=NOW, git=GIT if m is M else m.Git(repos))
    finally:
        os.environ["OVN_GER_GIT"] = "off"


rg = scen_git(M)
ga, gc = gate(rg, "antigaming"), gate(rg, "card_credit")
ok("antigaming range join (git rev-list base..head) -> 'range'", ga["flag_fail_joined_by"] == {"range": 1} and ga["flag_fail_unjoined"] == 0, ga)
ok("card_credit cycle join git-verified; the non-ancestor credit is rejected", gc["flag_fail_joined_by"] == {"cycle": 1} and gc["flag_fail_unjoined"] == 1, gc)
ok("git_verified_joins reported", rg["git_verified_joins"] is True)
rn = M.build(S().flush() if False else (lambda s: (s.anti(T0 + 5000, "xlite", shas[0], shas[2]), s.out(T0 + 4000, "xlite", after=shas[1], ih="f1" * 16), s.flush())[2])(S()), 30, now=NOW, git=M.Git(None))
ok("without a clone the range event is honestly unjoined (no-key)", gate(rn, "antigaming")["flag_fail_unjoined"] == 1)

def scen_commit_missing(m):
    """clone exists but does NOT contain the credited commit -> is_ancestor unknown -> time-only: unjoined by default (cycle-time-only), 'cycle-unverified' when opted in."""
    s = S()
    s.credit(T0 + 8000, "xlite", sha(77))
    s.out(T0 + 8004, "xlite", after=shas[3], ih="f9" * 16)
    d = s.flush()
    res = {}
    os.environ["OVN_GER_GIT"] = "on"
    try:
        for flag in ("off", "on"):
            os.environ["OVN_GER_CYCLE_UNVERIFIED"] = flag
            res[flag] = m.build(d, 30, now=NOW, git=GIT if m is M else m.Git(repos))
    finally:
        os.environ.pop("OVN_GER_CYCLE_UNVERIFIED", None)
        os.environ["OVN_GER_GIT"] = "off"
    return res


rm = scen_commit_missing(M)
gm0, gm1 = gate(rm["off"], "card_credit"), gate(rm["on"], "card_credit")
ok("commit missing from the clone: default -> unjoined cycle-time-only, decided 0", gm0["flag_fail_unjoined_why"] == {"cycle-time-only": 1} and gm0["flag_fail_decided"] == 0 and gm0["proxy_precision"] is None, gm0)
ok("commit missing from the clone: OVN_GER_CYCLE_UNVERIFIED=on -> counted as cycle-unverified (never as git-verified 'cycle')", gm1["flag_fail_joined_by"] == {"cycle-unverified": 1}, gm1)
fact = " ".join(rm["off"]["known_facts"])
ok("known fact is truthful: counts git-verified / unverified / time-only separately, no blanket 'verified ... when a clone is present'",
   "0 git-verified" in fact and "1 time-only candidate(s) NOT counted" in fact and "when a clone is present" not in fact, fact)
rv = scen_git(M)
fv = " ".join(rv["known_facts"])
ok("git-verified cycle join is reported as verified in the known fact", "1 git-verified" in fv, fv)

print("--explain and --json")
st = S()
st.credit(T0, "billwatch", sha(1))
st.out(T0 + 4, "billwatch", after=sha(1), ih="aa" * 16)
sd = st.flush()
r = run_cli(["--state", sd, "--explain", "--days", "30"], {"OVN_GER_NOW": str(int(NOW))})
ok("--explain lists the gate, clean days, events, joined/decided, precision and blockers", r.returncode == 0 and "card_credit: HOLD" in r.stdout and "clean days" in r.stdout and "FLAG/FAIL events" in r.stdout
   and "joined + decided" in r.stdout and "proxy precision" in r.stdout and "blocker:" in r.stdout, r.stdout + r.stderr)
r = run_cli(["--state", sd, "--json", "--days", "30"], {"OVN_GER_NOW": str(int(NOW))})
jj = json.loads(r.stdout)
cc = gate(jj, "card_credit")
ok("--json exposes flag_fail_joined_by / flag_fail_unjoined_why", cc["flag_fail_joined_by"] == {"sha": 1} and cc["flag_fail_unjoined_why"] == {})
r = run_cli(["--state", sd, "--days", "30"], {"OVN_GER_NOW": str(int(NOW))})
ok("plain report prints the join line", "join: 1 of 1 FLAG/FAIL joined by" in r.stdout, r.stdout)

print("hand-label worksheet (qa_flag_sample.py)")
SM = load(SAMPLER, "sampler_real")
gov = load(GOV, "gov_real")
ok("sampler key replicates the governor's line_key", SM.line_key("qa:antigaming", "antigaming.jsonl", "xlite", "r", "t") == gov.line_key("qa:antigaming", "antigaming.jsonl", "xlite", "r", "t"))


def scen_sample(sm, label_first=True):
    s = S()
    rules = ["D_DEAD_SYMBOL"] * 30 + ["A_TEST_DELETED"] * 12 + ["F_CLAIM_TEST_ONLY"] * 4
    for i, rule in enumerate(rules):
        s.anti(T0 + i * 600, "xlite", sha(500 + i), sha(600 + i), rule=rule)
    s.out(T0 + 5, "xlite", after=sha(600), ih="aa" * 16)                      # i=0 joined (green)
    d = s.flush()
    if label_first:
        lab = sm.event_key([e for e in sm.ger.load_qa_shadow(d) if e.ts == T0 + 3 * 600][0])
        os.makedirs(os.path.join(d, "gate_governor"))
        open(os.path.join(d, "gate_governor", "labels.jsonl"), "w").write(json.dumps({"gate": "qa:antigaming", "key": lab, "label": "fp", "ts": ts(NOW)}) + "\n")
    return d, lab if label_first else None


d, lab = scen_sample(SM)
rep = SM.sample(d, 30, {"antigaming"}, 40, now=NOW, git=SM.ger.Git(None))
ag = rep["antigaming"]
sigs = [r["signature"] for r in ag["rows"]]
ok("lists exactly 40 of the 45 unlabelled (46 total - 1 labelled)", ag["listed"] == 40 and ag["already_labelled"] == 1 and ag["unlabelled"] == 45, {k: v for k, v in ag.items() if k != "rows"})
ok("an already-labelled event is never listed again", lab not in [r["key"] for r in ag["rows"]])
ok("every rule is represented before the noisiest one repeats (first 3 rows = 3 distinct signatures)", len(set(sigs[:3])) == 3, sigs[:6])
ok("each row carries the governor label command", all(r["label_cmd"].startswith("python3 scripts/ovn_gate_governor.py label qa:antigaming l:") for r in ag["rows"]))
ok("the joined (green) event is listed in its signature's rotation", any(r["outcome"] == "green" for r in ag["rows"]))
ok("no label key is duplicated", len(set(r["key"] for r in ag["rows"])) == 40)
r = subprocess.run([PY, SAMPLER, "--state", d, "--gate", "antigaming", "--limit", "5", "--write"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, env=dict(os.environ, OVN_GER_NOW=str(int(NOW))))
ok("CLI lists 5 and --write stores state/qa_flag_sample/antigaming.json", r.returncode == 0 and os.path.isfile(os.path.join(d, "qa_flag_sample", "antigaming.json")) and r.stdout.count("label qa:antigaming") == 5, r.stdout + r.stderr)

print("worksheet keys/commands match what the governor accepts (all gate kinds)")
FIXS = os.path.join(HERE, "fixtures_gate_evidence", "state")
NOWF = float(calendar.timegm((2026, 10, 18, 12, 0, 0)))
repw = SM.sample(FIXS, 30, None, 100, now=NOWF, git=SM.ger.Git(None))
ok("fixture worksheet covers item_verify and spec_gate", "item_verify" in repw and "spec_gate" in repw, sorted(repw))
reg_ids = SM.registry_ids()
ok("registry ids loaded; spec_gate / executor not in it", "item_verify" in reg_ids and "qa:antigaming" in reg_ids and "spec_gate" not in reg_ids)
govreg = gov.load_registry()
for gname, d in sorted(repw.items()):
    for r in d["rows"]:
        raised = False
        try:
            gov.find_gate(govreg, r["gate"])
        except KeyError:
            raised = True
        ok("%s: label command printed iff the governor can find the gate (find_gate raises: %s)" % (gname, raised), (not raised) == r["labelable"] and (r["label_cmd"].startswith("python3 scripts/ovn_gate_governor.py label ") == r["labelable"]), r)
        break
ok("spec_gate rows say the governor cannot label them (no command that would raise KeyError)", all((not r["labelable"]) and "not in ops/gate_registry.json" in r["label_cmd"] for r in repw["spec_gate"]["rows"]), repw["spec_gate"]["rows"][:1])
# the governor's own keys for the stage_event gates, from its own collector over the same journals (fixture runs + one real-shaped red_before 'RB weak' run)
RBS = os.path.join(T, "rbstate")
shutil.copytree(FIXS, RBS)
open(os.path.join(RBS, "stage_runs", "billwatch-20261017-180000-1234567.jsonl"), "w").write(
    json.dumps({"run": "20261017-180000-1234567", "repo": "billwatch", "tier": 1, "item": "[T1] y.py - item [feat:billwatch-20261017-rb]", "event": "decomposed", "steps": 1}) + "\n"
    + json.dumps({"run": "20261017-180000-1234567", "event": "red_before", "mode": "shadow", "detail": "RB weak: the new test passes without the source change"}) + "\n")
repw = SM.sample(RBS, 30, None, 100, now=NOWF, git=SM.ger.Git(None))
ok("red_before RB-weak event is in the worksheet", len(repw.get("red_before", {}).get("rows", [])) == 1, sorted(repw))
os.environ["OVN_GG_STATE"], os.environ["OVN_GG_NOW"] = RBS, str(int(NOWF))
try:
    for gid in ("item_verify", "red_before"):
        recs = gov.collect(gov.find_gate(govreg, gid), gov.Ctx(days=30))
        gkeys = {x.key for x in recs}
        mine = [r for r in repw.get(gid, {}).get("rows", [])]
        ok("%s: every worksheet key is a key of the governor's own record (so 'labelled>=N' counts it)" % gid, bool(gkeys) and bool(mine) and all(r["key"] in gkeys for r in mine) and all(r["key"].startswith("run:") for r in mine), (sorted(gkeys)[:3], mine[:1]))
finally:
    os.environ.pop("OVN_GG_STATE", None)
    os.environ.pop("OVN_GG_NOW", None)
ok("item_verify worksheet is non-empty (fixture has refuse: rows)", len(repw.get("item_verify", {}).get("rows", [])) >= 1)

print("mutation proofs (each mutant must break its scenario)")
m1 = mutant(SRC, "nosha", '("sha", self.by_commit, [c[:12] for c in ev.commits if SHA_RE.match(c)]),', '("sha", self.by_commit, []),')
_, g1 = scen_credit(m1)
ok("MUTANT sha join dropped: unjoined count test fails (joined_by no longer has sha)", g1["flag_fail_joined_by"] != {"sha": 1, "cycle-unverified": 1} or g1["flag_fail_unjoined"] != 2, g1)
_, g1s = scen_credit(m1, strict=True)
ok("... and with exact keys only the unjoined count rose (3 -> 4): the sha join was carrying one row", g1s["flag_fail_unjoined"] > gs["flag_fail_unjoined"], g1s)
m2 = mutant(SRC, "nocycle", 'not strict and ev.gate in cycle_gates()', 'False and ev.gate in cycle_gates()')
_, g2 = scen_credit(m2)
ok("MUTANT cycle join dropped: the pre-commits-era credit is unjoined -> scenario fails", g2["flag_fail_joined_by"] != {"sha": 1, "cycle-unverified": 1}, g2)
m3 = mutant(SRC, "nobase", '("base", self.by_hbefore, [ev.base[:12]] if SHA_RE.match(ev.base or "") else []),', '("base", self.by_hbefore, []),')
_, a3 = scen_anti(m3)
ok("MUTANT base==head_before join dropped -> scenario fails", a3["flag_fail_joined_by"] != {"base": 1, "sha": 1}, a3)
m3b = mutant(SRC, "lineage", '("sha", self.by_commit, [c[:12] for c in ev.commits if SHA_RE.match(c)]),', '("sha", self.by_commit, [c[:12] for c in ev.commits if SHA_RE.match(c)] + [c[:12] for c in ev.commits]), ("lin", self.by_hbefore, [c[:12] for c in ev.commits]),')
_, a3b = scen_anti(m3b)
ok("MUTANT head==later head_before accepted as a join -> scenario fails (guards the lineage mistake)", a3b["flag_fail_unjoined"] != 1, a3b)
m4 = mutant(SRC, "norange", "shas = self.git.range(ev.repo, ev.base, ev.commits[0])", "shas = None")
rg4 = scen_git(m4)
ok("MUTANT git range join dropped -> the range event is unjoined -> scenario fails", gate(rg4, "antigaming")["flag_fail_joined_by"] != {"range": 1}, gate(rg4, "antigaming"))
m5 = mutant(SRC, "noreject", "                if v is False:\n                    break", "                if False:\n                    break")
rg5 = scen_git(m5)
ok("MUTANT git-rejected cycle join accepted -> scenario fails", gate(rg5, "card_credit")["flag_fail_unjoined"] != 1, gate(rg5, "card_credit"))
m6 = mutant(SRC, "itemkey", 'out.append(Ev(r.get("gate") or stem, str(v), t, r.get("repo") or "", [head_of(r.get("ref"))], [], "", r, src="qa_shadow", base=base_of(r.get("ref"))))',
            'out.append(Ev(r.get("gate") or stem, str(v), t, r.get("repo") or "", [head_of(r.get("ref"))], [det.get("item_key")] if det.get("item_key") else [], "", r, src="qa_shadow", base=base_of(r.get("ref"))))')
_, g6 = scen_credit(m6)
ok("MUTANT item_key used as item_hash: lookalike row falsely joins -> scenario fails", g6["flag_fail_joined_by"].get("hash", 0) > 0 or g6["flag_fail_unjoined"] != 2, g6)
m7 = mutant(SRC, "nowin", 'lo = max(min([ev.ts] + ft) - slack_s, ev.ts - slack_s - fnum("OVN_GER_BACK_S", 3600))', "lo = ev.ts - slack_s")
w7, _ = scen_window(m7)
ok("MUTANT window pinned to the event: the pre-event revert is missed -> scenario fails", w7["flag_fail_reverted_parked"] != 1, w7)
m7b = mutant(SRC, "uncapped", 'lo = max(min([ev.ts] + ft) - slack_s, ev.ts - slack_s - fnum("OVN_GER_BACK_S", 3600))', "lo = min([ev.ts] + ft) - slack_s")
w7b, w7bs = scen_window(m7b)
ok("MUTANT uncapped back-window: 20 h-old rows count (green false positive) -> scenario fails", w7b["flag_fail_green"] != 0 or w7bs["flag_fail_green"] != 0, (w7b, w7bs))
m7c = mutant(SRC, "alljoins", 'if ev.join in ("range", "base", "cycle", "cycle-unverified") and ev.gate in back_gates():', "if True:")
w7c, w7cs = scen_window(m7c)
ok("MUTANT back-window for every join/gate: scanners sha-join to a 20 h row turns green -> scenario fails", w7cs["flag_fail_green"] != 0, w7cs)
m10 = mutant(SRC, "unvdefault", "if v is None and not cycle_unverified():", "if False:")
_, g10 = scen_credit(m10, unv=False)
ok("MUTANT unverified cycle join counted by default -> scenario fails", g10["flag_fail_decided"] != 1 or g10["flag_fail_cycle_time_only"] != 1, g10)
r10 = scen_commit_missing(m10)
ok("MUTANT ... also with the commit missing from the clone", gate(r10["off"], "card_credit")["flag_fail_decided"] != 0, gate(r10["off"], "card_credit"))
m11 = mutant(SAMPLER, "stagekey", '    if ev.src == "stage_runs" and ev.file:\n        return "run:" + ev.file.replace(".jsonl", "")\n', "")
rw11 = m11.sample(RBS, 30, {"item_verify"}, 100, now=NOWF, git=m11.ger.Git(None))
ok("MUTANT stage_event key built with line_key: worksheet key no longer the governor's run:<file> -> scenario fails", not all(r["key"].startswith("run:") for r in rw11["item_verify"]["rows"]), rw11["item_verify"]["rows"][:1])
m12 = mutant(SAMPLER, "alllab", "def labelable(ev, reg=None):\n    return gate_id(ev) in (registry_ids() if reg is None else reg)", "def labelable(ev, reg=None):\n    return True")
rw12 = m12.sample(FIXS, 30, {"spec_gate"}, 100, now=NOWF, git=m12.ger.Git(None))
ok("MUTANT every gate labelable: spec_gate gets an unacceptable command -> scenario fails", any(r["labelable"] for r in rw12["spec_gate"]["rows"]), rw12["spec_gate"]["rows"][:1])
m8 = mutant(SAMPLER, "nolab", "        if (gate_id(e), key) in labels:", "        if False:")
d8, lab8 = scen_sample(m8)
r8 = m8.sample(d8, 30, {"antigaming"}, 100, now=NOW, git=m8.ger.Git(None))
ok("MUTANT sampler lists labelled events again -> scenario fails", lab8 in [x["key"] for x in r8["antigaming"]["rows"]], r8["antigaming"]["unlabelled"])
m9 = mutant(SAMPLER, "norr", "    queues.sort(key=lambda q: (-len(q[1]), q[0]))\n", "    queues.sort(key=lambda q: (-len(q[1]), q[0]))\n    queues = [(\"flat\", [x for _, qq in queues for x in qq])]\n")
d9, _ = scen_sample(m9)
r9 = m9.sample(d9, 30, {"antigaming"}, 40, now=NOW, git=m9.ger.Git(None))
ok("MUTANT no round-robin across rules: the noisiest rule fills the sample -> scenario fails", len(set(x["signature"] for x in r9["antigaming"]["rows"][:3])) < 3, [x["signature"] for x in r9["antigaming"]["rows"][:3]])

shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
