#!/usr/bin/env python3
"""qa/promote_manifest.py + qa/rollback_drill.py (Phase 5, shadow).

Fixture repos with a linear develop history, prod-<ts>-<repo> tags at known commits and hand-written QA shadow rows. Checks: a candidate with a FAIL gate says HOLD in its
summary; the manifest records the PREVIOUS prod tag (and says so on a first promote); batch size; release branch; staging match / mismatch / soak; env-gate FAILs only count on the
candidate itself; the exclusions the release planner already makes; the ledger event; history manifests for the last promote of billwatch / iptv_apps / shrike-labs-website are valid
JSON with the prior tag; no edit of daily_promote.sh / promote_to_prod.sh; the rollback drill restores the previous tag byte for byte (compared with hashes taken from the fixture),
fails on a broken tree / a failing smoke / a modified checkout, leaves the real clone untouched and no scratch dir behind; MUTANTS (HOLD logic removed, wrong prior tag, wrong drill tag)."""
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
QA = os.path.join(OQ, "qa")
PY = sys.executable
if not os.path.isfile(os.path.join(QA, "promote_manifest.py")):
    print("  SKIP: qa/promote_manifest.py not installed here")
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


T = os.path.realpath(tempfile.mkdtemp(prefix="pmanifest-test-"))
for k in list(os.environ):
    if k.startswith("OVN_QA_") or k in ("QA_STATE_DIR", "OVN_DIR", "OVN_REPOS_DIR", "QA_RELEASE_FAIL_MAX_AGE_H"):
        os.environ.pop(k, None)
STATE = os.path.join(T, "state")
REPOS = os.path.join(T, "repos")
os.makedirs(os.path.join(STATE, "qa_shadow"))
os.makedirs(REPOS)
os.environ["QA_STATE_DIR"] = STATE
os.environ["OVN_REPOS_DIR"] = REPOS


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


PM = load(os.path.join(QA, "promote_manifest.py"), "promote_manifest_under_test")
RD_ = load(os.path.join(QA, "rollback_drill.py"), "rollback_drill_under_test")
import qa_ledger as ql  # noqa: E402

GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def git(rd, *a):
    return subprocess.run(["git", "-C", rd] + list(a), env=GENV, capture_output=True, text=True, check=True).stdout.strip()


def content(n):
    return "version = %d\n" % n, bytes([n, 0, 255, n, 10, 13])


def make_repo(name, tags=("20261001-0900", "20261002-0900", "20261003-0900"), tag_at=(2, 4, 6), n=9, break_at=None):
    """linear branch with commits 1..n (app.py + data.bin change each time); tags at the given commit numbers; returns (dir, [sha1..shan])."""
    rd = os.path.join(REPOS, name)
    os.makedirs(rd)
    git(rd, "init", "-q", "-b", "develop")
    shas = []
    for i in range(1, n + 1):
        txt, blob = content(i)
        if break_at == i:
            txt = "def broken(:\n"
        open(os.path.join(rd, "app.py"), "w").write(txt)
        open(os.path.join(rd, "data.bin"), "wb").write(blob)
        git(rd, "add", "-A")
        git(rd, "commit", "-q", "-m", ("feat: add thing %d" if i % 2 else "fix: thing %d") % i)
        shas.append(git(rd, "rev-parse", "HEAD"))
    for ts, at in zip(tags, tag_at):
        git(rd, "tag", "prod-%s-%s" % (ts, name), shas[at - 1])
    git(rd, "update-ref", "refs/remotes/origin/main", shas[tag_at[-1] - 1] if tag_at else shas[0])
    return rd, shas


def shadow(rows, fname="gates.jsonl"):
    with open(os.path.join(STATE, "qa_shadow", fname), "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def gate_row(gate, repo, ref, verdict, ts="2026-10-02T00:00:00Z", **kw):
    return dict({"gate": gate, "repo": repo, "ref": ref, "verdict": verdict, "ts": ts, "summary": "x", "details": {}}, **kw)


def now_iso(off=0):
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + off))


def staging_file(repo, commit, status="SUCCESS", age_h=5.0):
    d = os.path.join(STATE, "staging_deploys")
    os.makedirs(d, exist_ok=True)
    json.dump({"repo": repo, "fetched_at": time.time(), "deployments": [{"id": "dep1", "status": status, "createdAt": now_iso(-age_h * 3600), "meta": {"commitHash": commit, "branch": "develop"}}]},
              open(os.path.join(d, repo + ".json"), "w"))


def clear_staging():
    shutil.rmtree(os.path.join(STATE, "staging_deploys"), ignore_errors=True)


RD, S = make_repo("fixrepo")
CAND = S[8]
T3 = "prod-20261003-0900-fixrepo"

# ---------------------------------------------------------------- 1. prior tag, batch, no gates
shadow([])
man = PM.build("fixrepo", RD, CAND, None, time.time(), False, [])
ok("manifest records the PREVIOUS prod tag (newest tag that is not the candidate) with its sha", man["prior_prod_tag"]["tag"] == T3 and man["prior_prod_tag"]["sha"] == S[5], man["prior_prod_tag"])
ok("prior tag ts parsed from the tag name", man["prior_prod_tag"]["ts"] == "2026-10-03T09:00:00Z")
ok("batch size = commits since the prior tag (3), features 2 (7, 9 are odd=feat... 7,9), fixes 1 (8)", man["batch"] == {"commits": 3, "merges": 0, "features": 2, "fixes": 1}, man["batch"])
ok("schema, repo, candidate, rollback command", man["schema"] == "promote_manifest/1" and man["repo"] == "fixrepo" and man["candidate_sha"] == CAND and man["rollback"]["command"] == "git checkout " + T3)
ok("main_sha from origin/main", man["main_sha"] == S[5])
ok("no gate rows in range -> PROCEED-UNVERIFIED (vacuous pass: nothing gated this batch)", man["decision"] == "PROCEED-UNVERIFIED" and "vacuous" in man["summary"], man["summary"])
GP = gate_row("scanners", "fixrepo", S[6], "PASS")        # one real code-facing PASS in the range
ok("one code-facing PASS row in range -> PROCEED (history staging is 'not reconstructible', not unverified)",
   PM.build("fixrepo", RD, CAND, None, time.time(), False, [GP])["decision"] == "PROCEED")
ok("decide(): empty gates -> PROCEED-UNVERIFIED, never a bare PROCEED", PM.decide({}, {"match": True, "evidence": "ok", "verdict": "PASS"}, [], {"tag": "t"}) == ("PROCEED-UNVERIFIED", ["no code-facing gate evidence in range (vacuous pass)"]))
ok("decide(): only ENVIRONMENT gates in range is still vacuous for the code",
   PM.decide({"staging_check": {"verdict": "PASS", "env": True, "fail_rows": 0, "rows": 1}}, {"match": True, "evidence": "ok", "verdict": "PASS"}, [], {"tag": "t"})[0] == "PROCEED-UNVERIFIED")
GOODG = {"scanners": {"verdict": "PASS", "env": False, "fail_rows": 0, "rows": 1}}
ok("decide(): one code-facing PASS -> PROCEED", PM.decide(GOODG, {"match": True, "evidence": "ok", "verdict": "PASS"}, [], {"tag": "t"}, 3, 1)[0] == "PROCEED")
_old_cov = PM.COVERAGE_MIN_PCT
PM.COVERAGE_MIN_PCT = 50
ok("decide(): coverage below OVN_QA_MANIFEST_COVERAGE_PCT (1 of 10 commits gated, 50% wanted) -> PROCEED-UNVERIFIED", PM.decide(GOODG, {"match": True, "evidence": "ok", "verdict": "PASS"}, [], {"tag": "t"}, 10, 1)[0] == "PROCEED-UNVERIFIED")
ok("decide(): coverage at the threshold -> PROCEED", PM.decide(GOODG, {"match": True, "evidence": "ok", "verdict": "PASS"}, [], {"tag": "t"}, 10, 5)[0] == "PROCEED")
PM.COVERAGE_MIN_PCT = _old_cov
mcov = PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("scanners", "fixrepo", S[6], "PASS"), gate_row("baseline", "fixrepo", S[7], "PASS")])
ok("build(): covered commits (gate rows' heads in the range) are counted", mcov["decision"] == "PROCEED")
man2 = PM.build("fixrepo", RD, CAND, "prod-20261001-0900-fixrepo", time.time(), False, [])
ok("--prior-tag overrides: batch counted from that tag (7 commits: 3..9? tag at 2 -> 7)", man2["prior_prod_tag"]["tag"] == "prod-20261001-0900-fixrepo" and man2["batch"]["commits"] == 7, man2["batch"])
ok("an unknown --prior-tag yields no prior (never a guess)", PM.build("fixrepo", RD, CAND, "prod-nope", time.time(), False, [])["prior_prod_tag"] is None)

# ---------------------------------------------------------------- 2. HOLD when a gate FAILs in the range
rows_fail = [gate_row("antigaming", "fixrepo", S[7], "FAIL"), gate_row("scanners", "fixrepo", S[6], "PASS"), gate_row("baseline", "fixrepo", S[8], "PASS")]
mf = PM.build("fixrepo", RD, CAND, None, time.time(), False, rows_fail)
ok("a candidate with a FAIL gate says HOLD in its summary field", mf["decision"] == "HOLD" and mf["summary"].startswith("HOLD ") and "antigaming FAIL" in mf["summary"], mf["summary"])
ok("gate verdicts per gate recorded (FAIL / PASS / PASS)", {g: v["verdict"] for g, v in mf["gates"].items()} == {"antigaming": "FAIL", "scanners": "PASS", "baseline": "PASS"}, mf["gates"])
ok("a FAIL outside the range (at/under the prior tag) does not hold", PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("antigaming", "fixrepo", S[3], "FAIL"), GP])["decision"] == "PROCEED")
ok("a FAIL for ANOTHER repo does not hold", PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("antigaming", "otherrepo", S[7], "FAIL"), GP])["decision"] == "PROCEED")
ok("the base of a 'base..head' ref is not the judged commit (FAIL with head under the prior tag, base inside the range)",
   PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("antigaming", "fixrepo", S[7][:12] + ".." + S[3][:12], "FAIL"), GP])["decision"] == "PROCEED")
ok("a 'base..head' FAIL with the head in range holds", PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("antigaming", "fixrepo", S[0][:12] + ".." + S[7][:12], "FAIL")])["decision"] == "HOLD")
ok("staged_shadow baseline FAILs are excluded exactly as the release planner does", PM.build("fixrepo", RD, CAND, None, time.time(), False,
   [gate_row("baseline", "fixrepo", S[7], "FAIL", kind="staged_shadow")])["decision"] == "PROCEED")
ok("latest verdict wins for a gate without FAIL rows (PASS then UNVERIFIED -> UNVERIFIED -> PROCEED-UNVERIFIED)", PM.build("fixrepo", RD, CAND, None, time.time(), False,
   [gate_row("scanners", "fixrepo", S[6], "PASS", ts="2026-10-02T00:00:00Z"), gate_row("scanners", "fixrepo", S[7], "UNVERIFIED", ts="2026-10-03T00:00:00Z")])["decision"] == "PROCEED-UNVERIFIED")
mu = PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("antigaming", "fixrepo", "unknownref", "FAIL")])
ok("a FAIL row that cannot be resolved to a commit -> PROCEED-UNVERIFIED and listed (never silently PROCEED)", mu["decision"] == "PROCEED-UNVERIFIED" and mu["unresolved_fail_rows"], mu)
ok("environment gate FAIL on the candidate itself holds", PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("staging_check", "fixrepo", CAND, "FAIL")])["decision"] == "HOLD")
ok("environment gate FAIL on some other commit does not", PM.build("fixrepo", RD, CAND, None, time.time(), False, [gate_row("staging_check", "fixrepo", S[7], "FAIL"), GP])["decision"] == "PROCEED")
fp = PM.build("fixrepo", RD, S[3], "prod-20261001-0900-fixrepo", time.time(), False, [])
ok("first-promote style: a candidate with a prior but nothing else", fp["prior_prod_tag"]["tag"] == "prod-20261001-0900-fixrepo")
RD1, S1 = make_repo("firstrepo", tags=("20261001-0900",), tag_at=(5,))
mfirst = PM.build("firstrepo", RD1, S1[8], None, time.time(), False, [])
ok("a repo with ONE earlier prod tag uses it as the prior (batch counted from it)", mfirst["prior_prod_tag"]["tag"] == "prod-20261001-0900-firstrepo" and mfirst["batch"]["commits"] == 4, mfirst["batch"])
RD0, S0 = make_repo("barerepo", tags=(), tag_at=())
mbare = PM.build("barerepo", RD0, S0[8], None, time.time(), False, [])
ok("no prod tag at all: prior null, rollback command null, batch 1, PROCEED-UNVERIFIED mentioning 'no prior prod tag'", mbare["prior_prod_tag"] is None and mbare["rollback"]["command"] is None
   and mbare["decision"] == "PROCEED-UNVERIFIED" and "no prior prod tag" in mbare["summary"] and mbare["batch"]["commits"] == 1, mbare)

# ---------------------------------------------------------------- 3. release branch
git(RD, "branch", "release/20261004", CAND)
ok("a release/* branch pointing at the candidate is recorded", PM.build("fixrepo", RD, CAND, None, time.time(), False, [])["release_branch"] == "release/20261004")
ok("none when no release branch points there", PM.build("fixrepo", RD, S[7], None, time.time(), False, [])["release_branch"] is None)

# ---------------------------------------------------------------- 4. live: staging match / mismatch / soak (file provider)
shadow([gate_row("scanners", "fixrepo", S[6], "PASS", ts=now_iso())])
clear_staging()
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--no-write"])
ok("live, no staging evidence at all -> PROCEED-UNVERIFIED (staging not matched)", out["decision"] == "PROCEED-UNVERIFIED" and "staging not matched" in out["summary"], out["summary"])
staging_file("fixrepo", CAND, age_h=5.0)
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--no-write"])
mm = out["manifest"]
ok("live, staging serves the candidate -> match true, soak ~5 h, PROCEED", mm["staging"]["match"] is True and mm["soak_hours"] is not None and 4.9 <= mm["soak_hours"] <= 5.2 and out["decision"] == "PROCEED", (mm["staging"], mm["soak_hours"], out["summary"]))
staging_file("fixrepo", S[6], age_h=5.0)
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--no-write"])
ok("live, staging serves an OLDER commit -> match false, HOLD", out["manifest"]["staging"]["match"] is False and out["decision"] == "HOLD" and "staging does not serve" in out["summary"], out["summary"])
staging_file("fixrepo", CAND, status="FAILED")
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--no-write"])
ok("live, the latest staging deploy FAILED -> HOLD", out["decision"] == "HOLD", out["summary"])
ok("history never claims staging evidence (match null)", PM.build("fixrepo", RD, CAND, None, time.time(), False, [])["staging"]["match"] is None)

# ---------------------------------------------------------------- 5. files + ledger event
staging_file("fixrepo", CAND, age_h=2.0)
outd = os.path.join(T, "manifests")
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--out-dir", outd])
path = out["path"]
j = json.load(open(path))
ok("file written as <repo>-<YYYYMMDD-HHMMSS>.json, valid JSON, same decision", os.path.basename(path).startswith("fixrepo-") and path.endswith(".json") and j["decision"] == out["decision"] and j["prior_prod_tag"]["tag"] == T3, path)
recs, evs = ql.load_ledger()
mevs = [e for e in evs if e["type"] == "promote_manifest"]
ok("one ledger event appended: type promote_manifest, repo, ref, prior tag, no record attribution", len(mevs) == 1 and mevs[0]["repo"] == "fixrepo" and mevs[0]["ref"] == CAND[:12] and mevs[0]["prior_tag"] == T3 and mevs[0]["rec"] is None, mevs)
PM.write_manifest(j, outd, stamp=os.path.basename(path)[len("fixrepo-"):-5])
ok("rewriting the same manifest does not duplicate its ledger event", len([e for e in ql.load_ledger()[1] if e["type"] == "promote_manifest"]) == 1)
sc = subprocess.run([PY, os.path.join(QA, "qa_scorecard.py"), "report", "--days", "30"], capture_output=True, text=True, env=dict(os.environ))
ok("qa_scorecard does not report the manifest event as an unattributed escape", "promote_manifest=1" in sc.stdout and "no attributable feature: none" in sc.stdout, sc.stdout[-400:] + sc.stderr[-200:])
ok("a bad candidate / repo name is reported, nothing written", "error" in PM.cmd_generate(["--repo", "fixrepo", "--candidate", "nonexistentref", "--no-write"]) and "error" in PM.cmd_generate(["--repo", "../x"]))

# ---------------------------------------------------------------- 6. history for the last promote of the three promoted repos
for nm in ("billwatch", "iptv_apps", "shrike-labs-website"):
    make_repo(nm, tags=("20261008-0900", "20261009-0900", "20261013-0900"), tag_at=(3, 6, 8))
hd = os.path.join(T, "hist")
for nm in ("billwatch", "iptv_apps", "shrike-labs-website"):
    r = PM.cmd_history(["--repo", nm, "--n", "1", "--out-dir", hd])
    pth = r["wrote"][0] if r.get("wrote") else None
    try:
        d = json.load(open(pth))
    except (OSError, ValueError, TypeError):
        d = {}
    ok("history manifest for the last promote of %s: valid JSON containing the prior tag" % nm,
       d.get("prior_prod_tag", {}).get("tag") == "prod-20261009-0900-" + nm and d.get("promoted_tag") == "prod-20261013-0900-" + nm and d.get("source") == "history" and d["batch"]["commits"] == 2, (r, d.get("prior_prod_tag")))
r = PM.cmd_history(["--repo", "billwatch", "--n", "5", "--out-dir", hd, "--no-write"])
ok("history --n 5 over 3 tags yields 3 promotes, the oldest with no prior (first promote)", len(r["promotes"]) == 3 and r["promotes"][-1]["prior"] is None and r["promotes"][0]["prior"] == "prod-20261009-0900-billwatch", r)
ok("history on a repo with no prod tags is an error row, not a crash", "error" in PM.cmd_history(["--repo", "barerepo", "--no-write"]))

# ---------------------------------------------------------------- 7. flags
for val, want in ((None, "shadow"), ("off", "off"), ("shadow", "shadow"), ("enforce", "shadow"), ("x", "shadow")):
    if val is None:
        os.environ.pop("OVN_QA_PROMOTE_MANIFEST", None)
    else:
        os.environ["OVN_QA_PROMOTE_MANIFEST"] = val
    ok("OVN_QA_PROMOTE_MANIFEST=%r -> %s" % (val, want), PM.mode() == want)
os.environ["OVN_QA_PROMOTE_MANIFEST"] = "off"
before = sorted(os.listdir(outd))
out = PM.cmd_generate(["--repo", "fixrepo", "--candidate", CAND, "--out-dir", outd])
ok("off: nothing written", out["mode"] == "off" and sorted(os.listdir(outd)) == before)
dr = subprocess.run([PY, os.path.join(QA, "rollback_drill.py"), "run", "--repo", "fixrepo", "--no-record"], capture_output=True, text=True, env=dict(os.environ))
ok("off also switches the rollback drill off", '"mode": "off"' in dr.stdout, dr.stdout)
os.environ.pop("OVN_QA_PROMOTE_MANIFEST")

# ---------------------------------------------------------------- 8. promote scripts are untouched, the patch is documented and NOT applied
for f in ("daily_promote.sh", "promote_to_prod.sh"):
    txt = open(os.path.join(OQ, f)).read()
    ok("%s has no reference to the manifest (no edit made)" % f, "promote_manifest" not in txt and "rollback_drill" not in txt)
pd = os.path.join(QA, "patches", "promote_manifest.md")
ok("qa/patches/promote_manifest.md exists and says NOT applied", os.path.isfile(pd) and "NOT applied" in open(pd).read())

# ---------------------------------------------------------------- 9. rollback drill
def scratch_dirs():
    return sorted(d for d in os.listdir(tempfile.gettempdir()) if d.startswith("rbdrill-"))


def state_of(rd):
    return (git(rd, "rev-parse", "HEAD"), git(rd, "status", "--porcelain"), git(rd, "for-each-ref"), sorted(os.listdir(rd)))


pre_state, pre_scratch = state_of(RD), scratch_dirs()
OUTF = os.path.join(T, "hashes.txt")
res = RD_.drill("fixrepo", RD, None, "sha256sum app.py data.bin > '%s' 2>/dev/null || shasum -a 256 app.py data.bin > '%s'" % (OUTF, OUTF))
txt2, blob2 = content(6)   # the PREVIOUS tag of fixrepo: tags at 2, 4, 6 -> previous of the newest = commit 4
txt4, blob4 = content(4)
got = {l.split()[1]: l.split()[0] for l in open(OUTF).read().splitlines() if l.strip()}
ok("drill picks the PREVIOUS prod tag (second newest: the one a rollback of the latest promote restores)", res["details"]["tag"] == "prod-20261002-0900-fixrepo" and res["details"]["sha"] == S[3], res["details"].get("tag"))
ok("drill restores the previous tag content BYTE FOR BYTE (hashes taken inside the scratch checkout equal the fixture's v4 bytes)",
   got.get("app.py") == hashlib.sha256(txt4.encode()).hexdigest() and got.get("data.bin") == hashlib.sha256(blob4).hexdigest(), (got, res["summary"]))
ok("drill PASS with integrity detail and the smoke recorded", res["verdict"] == "PASS" and res["details"]["restored_identical"] is True and res["details"]["smokes"][0]["name"] == "custom", res)
ok("the real clone is untouched (HEAD, status, refs, worktree listing) and no scratch dir is left behind", state_of(RD) == pre_state and scratch_dirs() == pre_scratch)
res = RD_.drill("fixrepo", RD, "prod-20261003-0900-fixrepo")
ok("--tag selects an explicit tag; default smoke = compileall of the tracked python files -> PASS", res["verdict"] == "PASS" and res["details"]["tag"] == "prod-20261003-0900-fixrepo"
   and res["details"]["smokes"][0]["name"].startswith("compileall(1 py"), res)
RDb, Sb = make_repo("brokenrepo", break_at=4)
res = RD_.drill("brokenrepo", RDb, None)
ok("failure injection: the previous tag contains a syntax error -> FAIL (a rollback target that cannot build is not a rollback)", res["verdict"] == "FAIL" and "smoke FAILED" in res["summary"], res)
res = RD_.drill("fixrepo", RD, None, "exit 3")
ok("failure injection: a failing custom smoke -> FAIL", res["verdict"] == "FAIL" and res["details"]["smokes"][0]["status"] == "FAIL", res)
res = RD_.drill("fixrepo", RD, None, "sleep 0 && true")
ok("custom smoke passing -> PASS", res["verdict"] == "PASS")
res = RD_.drill("barerepo", RD0, None)
ok("no prod tag -> UNVERIFIED (never PASS)", res["verdict"] == "UNVERIFIED" and "no prod-<ts>-barerepo tag" in res["summary"], res)
ok("unknown --tag -> UNVERIFIED", RD_.drill("fixrepo", RD, "prod-bogus")["verdict"] == "UNVERIFIED")
res = RD_.drill("firstrepo", RD1, None)
ok("a single prod tag: the drill restores that one", res["details"]["tag"] == "prod-20261001-0900-firstrepo" and res["verdict"] == "PASS", res)
RDn = os.path.join(REPOS, "noncode")
os.makedirs(RDn)
git(RDn, "init", "-q", "-b", "develop")
open(os.path.join(RDn, "notes.txt"), "w").write("hi\n")
git(RDn, "add", "-A")
git(RDn, "commit", "-q", "-m", "docs: notes")
git(RDn, "tag", "prod-20261001-0900-noncode")
res = RD_.drill("noncode", RDn, None)
ok("a tree with nothing to smoke -> UNVERIFIED (identical restore but no build evidence), not PASS", res["verdict"] == "UNVERIFIED" and res["details"]["restored_identical"] is True, res)
RDp = os.path.join(REPOS, "nodepkg")
os.makedirs(RDp)
git(RDp, "init", "-q", "-b", "develop")
open(os.path.join(RDp, "package.json"), "w").write('{"scripts": {"build": "vite build"}}\n')
git(RDp, "add", "-A")
git(RDp, "commit", "-q", "-m", "chore: pkg")
git(RDp, "tag", "prod-20261001-0900-nodepkg")
res = RD_.drill("nodepkg", RDp, None)
ok("package.json parses -> PASS, the build script is noted as not run (offline)", res["verdict"] == "PASS" and any("build script" in n for n in res["details"]["notes"]), res)
open(os.path.join(RDp, "package.json"), "w").write("{not json\n")
git(RDp, "add", "-A")
git(RDp, "commit", "-q", "-m", "chore: break pkg")
git(RDp, "tag", "prod-20261002-0900-nodepkg")
res = RD_.drill("nodepkg", RDp, "prod-20261002-0900-nodepkg")
ok("invalid package.json at the target tag -> FAIL", res["verdict"] == "FAIL", res)
# integrity() failure injection on a manually modified checkout
scr = tempfile.mkdtemp(prefix="rbdrill-")
cl = os.path.join(scr, "clone")
subprocess.run(["git", "clone", "-q", "--no-checkout", "--shared", RD, cl], check=True, capture_output=True)
subprocess.run(["git", "-C", cl, "checkout", "-q", "--detach", "prod-20261002-0900-fixrepo"], check=True, capture_output=True)
ok("integrity(): pristine checkout is identical", RD_.integrity(RD, cl, "prod-20261002-0900-fixrepo")[0] is True)
open(os.path.join(cl, "app.py"), "a").write("# tampered\n")
ok("integrity(): a modified file is detected", RD_.integrity(RD, cl, "prod-20261002-0900-fixrepo")[0] is False)
git(cl, "checkout", "--", "app.py")
open(os.path.join(cl, "stray.txt"), "w").write("x")
ok("integrity(): an untracked file is detected", RD_.integrity(RD, cl, "prod-20261002-0900-fixrepo")[0] is False)
ok("integrity(): a tag whose tree differs from the checkout is detected", RD_.integrity(RD, cl, "prod-20261003-0900-fixrepo")[0] is False)
ok("safe_cleanup removes only rbdrill-* directly under the temp root", RD_.safe_cleanup(scr) is True and not os.path.exists(scr))
keep = os.path.join(T, "keepme")
os.makedirs(keep)
ok("safe_cleanup refuses anything else (a non-rbdrill dir, the real clone, HOME)", RD_.safe_cleanup(keep) is False and os.path.isdir(keep) and RD_.safe_cleanup(RD) is False and RD_.safe_cleanup(os.path.expanduser("~")) is False and os.path.isdir(RD))
p = subprocess.run([PY, os.path.join(QA, "rollback_drill.py"), "run", "--repo", "fixrepo", "--no-record"], env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "HOME": T},
                   capture_output=True, text=True)
jj = json.loads(p.stdout.strip().splitlines()[-1])
ok("CLI: exit 0, one JSON line, verdict PASS, no row written with --no-record", p.returncode == 0 and jj["verdict"] == "PASS" and not os.path.exists(os.path.join(STATE, "qa_shadow", "rollback_drill.jsonl")), p.stdout + p.stderr)
p = subprocess.run([PY, os.path.join(QA, "rollback_drill.py"), "run", "--repo", "fixrepo"], env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "HOME": T}, capture_output=True, text=True)
ok("CLI: without --no-record one rollback_drill row is appended", p.returncode == 0 and len(open(os.path.join(STATE, "qa_shadow", "rollback_drill.jsonl")).read().splitlines()) == 1)
p = subprocess.run([PY, os.path.join(QA, "rollback_drill.py"), "run", "--repo", "nope-repo", "--no-record"], env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "HOME": T}, capture_output=True, text=True)
ok("CLI: unknown repo -> UNVERIFIED, exit 0", p.returncode == 0 and json.loads(p.stdout.strip().splitlines()[-1])["verdict"] == "UNVERIFIED")
ok("no scratch directory left behind by any drill", scratch_dirs() == pre_scratch, scratch_dirs())

# ---------------------------------------------------------------- 9b. review fixes
import release_candidate as rcand  # noqa: E402
import qa_common as qc  # noqa: E402
ok("rollback_drill and the Phase 5 observers are NON_CODE_GATES", {"rollback_drill", "wip_cap", "gpu_ledger", "promote_manifest"} <= rcand.NON_CODE_GATES)
drill_fail = qc.verdict("FAIL", "rollback_drill", "fixrepo", "prod-20261013-0900-fixrepo", "restore of the tag is NOT byte-identical")
ok("a rollback_drill FAIL row is not counted as a code FAIL (no cross-gate pollution)", rcand.counts_as_fail(drill_fail) is False and rcand.fail_rows([drill_fail], "fixrepo") == [])
mdrill = PM.build("fixrepo", RD, CAND, None, time.time(), False, [GP, drill_fail])
ok("promote manifest ignores a drill FAIL: no unresolved FAIL row, no hold, no 'FAIL row(s) cannot be resolved'", mdrill["unresolved_fail_rows"] == [] and mdrill["decision"] == "PROCEED" and "rollback_drill" not in mdrill["gates"], mdrill["summary"])
drill_fail_on_cand = dict(drill_fail, ref=CAND)
mon = PM.build("fixrepo", RD, CAND, None, time.time(), False, [GP, drill_fail_on_cand])
ok("even a drill row whose ref IS the candidate sha does not hold and is not listed as a gate", mon["decision"] == "PROCEED" and "rollback_drill" not in mon["gates"] and mon["unresolved_fail_rows"] == [], mon["gates"])
# release planner: the same row must not downgrade a PASS
rows_rc = [gate_row("antigaming", "fixrepo", S[7], "PASS"), drill_fail]
ok("release_candidate.fail_tokens/unresolved logic never sees the drill row", not [r for r in rcand.fail_rows(rows_rc, "fixrepo")])
# prod_tags is sorted by the timestamp in the name even when git lists them differently; the candidate is always in its own range
RDs, Ss = make_repo("sortrepo")
git(RDs, "config", "tag.sort", "-refname")
ok("prod_tags sorts oldest -> newest whatever order git lists them in", [t[1] for t in PM.prod_tags(RDs, "sortrepo")] == ["prod-20261001-0900-sortrepo", "prod-20261002-0900-sortrepo", "prod-20261003-0900-sortrepo"], PM.prod_tags(RDs, "sortrepo"))
ok("prior tag is the NEWEST other tag under a reversed git tag listing", PM.build("sortrepo", RDs, Ss[8], None, time.time(), False, [])["prior_prod_tag"]["tag"] == "prod-20261003-0900-sortrepo")
old_cand = S[3]          # candidate OLDER than the prior tag: the base..cand range is empty, the candidate must still be in its own range
mold = PM.build("fixrepo", RD, old_cand, T3, time.time(), False, [gate_row("antigaming", "fixrepo", old_cand, "FAIL")])
ok("the candidate is always part of its own range (a FAIL on it holds even when it is older than the prior tag)", mold["decision"] == "HOLD", mold["summary"])
# rollback drill: partial smoke on non-python stacks
RDg = os.path.join(REPOS, "godotrepo")
os.makedirs(RDg)
git(RDg, "init", "-q", "-b", "develop")
open(os.path.join(RDg, "tool.py"), "w").write("x = 1\n")
open(os.path.join(RDg, "project.godot"), "w").write("config_version=5\n")
for i in range(6):
    open(os.path.join(RDg, "scene%d.tscn" % i), "w").write("[gd_scene]\n")
git(RDg, "add", "-A")
git(RDg, "commit", "-q", "-m", "feat: game")
git(RDg, "tag", "prod-20261001-0900-godotrepo")
res = RD_.drill("godotrepo", RDg, None)
ok("a Godot project whose only smoke is compileall of a stray .py file -> UNVERIFIED (partial smoke), not PASS", res["verdict"] == "UNVERIFIED" and res["details"]["restored_identical"] is True
   and any("partial" in n for n in res["details"]["notes"]) and any(r.get("partial") for r in res["details"]["smokes"]), res)
res = RD_.drill("godotrepo", RDg, None, "true")
ok("with an explicit smoke command the same repo can PASS", res["verdict"] == "PASS", res)
RDm = os.path.join(REPOS, "lowpy")
os.makedirs(RDm)
git(RDm, "init", "-q", "-b", "develop")
open(os.path.join(RDm, "a.py"), "w").write("x = 1\n")
for i in range(8):
    open(os.path.join(RDm, "f%d.dat" % i), "w").write("d\n")
git(RDm, "add", "-A")
git(RDm, "commit", "-q", "-m", "feat: x")
git(RDm, "tag", "prod-20261001-0900-lowpy")
ok("python under 25% of the tracked files -> partial -> UNVERIFIED", RD_.drill("lowpy", RDm, None)["verdict"] == "UNVERIFIED")
ok("a python repo (all python) still PASSes the default smoke", RD_.drill("fixrepo", RD, None)["verdict"] == "PASS")
# drill safety guards (each guard on its own)
keep2 = os.path.join(tempfile.gettempdir(), "notdrill-" + str(os.getpid()))
os.makedirs(keep2)
ok("safe_cleanup refuses a non-rbdrill dir directly under the temp root (prefix guard)", RD_.safe_cleanup(keep2) is False and os.path.isdir(keep2))
shutil.rmtree(keep2)
nested = os.path.join(T, "nest", "rbdrill-nested")
os.makedirs(nested)
ok("safe_cleanup refuses an rbdrill-* dir that is NOT directly under the temp root (parent guard)", RD_.safe_cleanup(nested) is False and os.path.isdir(nested))
ok("safe_cleanup refuses an empty string", RD_.safe_cleanup("") is False)
os.environ["AWS_SECRET_ACCESS_KEY"] = "s3cr3t"
os.environ["HTTPS_PROXY"] = "http://proxy:1"
os.environ["GITHUB_TOKEN"] = "tok"
se = RD_.scrub_env("/scratch/x")
ok("scrub_env: HOME is the scratch dir, proxies disabled, offline flag, no secrets / proxy / token variables leak", se["HOME"] == "/scratch/x" and se["NO_PROXY"] == "*" and se["OVN_OFFLINE"] == "1"
   and "AWS_SECRET_ACCESS_KEY" not in se and "HTTPS_PROXY" not in se and "GITHUB_TOKEN" not in se and se.get("GIT_TERMINAL_PROMPT") == "0", sorted(se))
for k in ("AWS_SECRET_ACCESS_KEY", "HTTPS_PROXY", "GITHUB_TOKEN"):
    os.environ.pop(k, None)
seen_cmds = []
_orig_run = RD_.qc.run


def _spy(cmd, *a, **kw):
    seen_cmds.append(list(cmd))
    return _orig_run(cmd, *a, **kw)


RD_.qc.run = _spy
RD_.drill("fixrepo", RD, None)
RD_.qc.run = _orig_run
clone_cmds = [c for c in seen_cmds if c[:2] == ["git", "clone"]]
ok("the scratch clone is `git clone --shared` (no object copy, no hardlinks into the real clone)", clone_cmds and "--shared" in clone_cmds[0] and "--local" not in clone_cmds[0], seen_cmds)

# ---------------------------------------------------------------- 10. MUTANTS
CHECK = r'''
import sys, json, time
sys.path.insert(0, sys.argv[1])
import promote_manifest as pm, rollback_drill as rd
repo, cand = "fixrepo", sys.argv[2]
rows = [{"gate":"antigaming","repo":repo,"ref":sys.argv[3],"verdict":"FAIL","ts":"2026-10-02T00:00:00Z","summary":"x","details":{}}]
m = pm.build(repo, sys.argv[4], cand, None, time.time(), False, rows)
d = rd.drill(repo, sys.argv[4], None, "true")
print(json.dumps({"hold": m["decision"] == "HOLD" and m["summary"].startswith("HOLD"), "prior": (m["prior_prod_tag"] or {}).get("tag"), "drill_tag": d["details"].get("tag")}))
'''


def variant(moddir):
    env = {"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "HOME": T, "TMPDIR": tempfile.gettempdir()}
    p = subprocess.run([PY, "-I", "-c", CHECK, moddir, CAND, S[7], RD], capture_output=True, text=True, env=env)
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def good(r):
    return isinstance(r, dict) and r["hold"] is True and r["prior"] == T3 and r["drill_tag"] == "prod-20261002-0900-fixrepo"


def mutate(label, fname, old, new):
    d = os.path.join(T, "mut_" + label)
    os.makedirs(d)
    for f in ("promote_manifest.py", "rollback_drill.py", "qa_common.py", "qa_ledger.py", "phase5_common.py", "release_candidate.py", "staging_check.py"):
        shutil.copy(os.path.join(QA, f), os.path.join(d, f))
    s = open(os.path.join(d, fname)).read()
    if old not in s:
        raise SystemExit("mutation needle not found in %s: %r" % (fname, old))
    open(os.path.join(d, fname), "w").write(s.replace(old, new, 1))
    return variant(d)


ok("mutant control: the unmodified code passes (HOLD, prior tag, drill tag)", good(variant(QA)), variant(QA))
ok("MUTANT HOLD removed (a FAIL gate no longer holds): the HOLD test FAILS", not good(mutate("hold", "promote_manifest.py", "    if hold:\n        return \"HOLD\", hold", "    if False:\n        return \"HOLD\", hold")))
ok("MUTANT wrong prior tag (oldest instead of newest): the prior-tag test FAILS", not good(mutate("prior", "promote_manifest.py", "ts, t, sha = cands[-1]", "ts, t, sha = cands[0]")))
ok("MUTANT drill restores the wrong tag (newest instead of previous): the drill-tag test FAILS", not good(mutate("drilltag", "rollback_drill.py", "pick = tags[-2] if len(tags) >= 2 else tags[-1]", "pick = tags[-1]")))
ok("MUTANT FAIL gate counting disabled in gate_verdicts: the HOLD test FAILS", not good(mutate("failcount", "promote_manifest.py", 'g["fail_rows"] += 1  ', 'g["fail_rows"] += 0  ')))

shutil.rmtree(T, ignore_errors=True) if os.path.basename(T).startswith("pmanifest-test-") else None
print("\nPASS=%d FAIL=%d" % (P, F))
sys.exit(1 if F else 0)
