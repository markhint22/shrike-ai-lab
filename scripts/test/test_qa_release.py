#!/usr/bin/env python3
"""Tests for qa/release_candidate.py, qa/staging_check.py, qa/staging_smoke.py (gate S10 / key: release).

Runs every gate through its REAL entry point, exactly as cron would: absolute path AND a relative path from scripts/overnight-queue,
under `env -i` with a minimal PATH and NTFY_SERVER set. Never touches real state (OVN_DIR is a temp dir), never reaches the network
(the 'staging' backend is a localhost fake; the railway CLI is a stub on PATH). Negative controls (seeded bad -> FAIL/FLAG/UNVERIFIED)
and benign controls (-> PASS) for each gate.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))  # scripts/overnight-queue
QA = os.path.join(OQ, "qa")
sys.path.insert(0, QA)
import release_candidate as rcm  # noqa: E402
import staging_check as scm  # noqa: E402
import staging_smoke as ssm  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="qa-release-test-")
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(T, "repos")
STATE = os.path.join(OVN, "state")
os.makedirs(os.path.join(STATE, "qa_shadow"))
os.makedirs(REPOS)
GITENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
          "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "HOME": T, "PATH": os.environ.get("PATH", "")}
GREEN = "chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=tests-green)"
NOGATE = "chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=no-tests)"
SYNC = "chore(sync): reconcile main -> develop (branch guard)"
MINPATH = "/usr/bin:/bin:/usr/local/bin"  # deliberately WITHOUT /opt/homebrew/bin so a real railway CLI can never be reached
PY = sys.executable


def sh(cwd, *cmd, check=True):
    p = subprocess.run(list(cmd), cwd=cwd, env=GITENV, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError("%s -> %s %s" % (cmd, p.stdout, p.stderr))
    return p.stdout.strip()


def mkrepo(name):
    origin = os.path.join(T, "origin-%s.git" % name)
    work = os.path.join(REPOS, name)
    sh(T, "git", "init", "-q", "--bare", "-b", "main", origin)
    sh(T, "git", "clone", "-q", origin, work)
    sh(work, "git", "checkout", "-q", "-b", "main")
    return origin, work


def commit(work, fname, msg):
    with open(os.path.join(work, fname), "a") as f:
        f.write(msg + "\n")
    sh(work, "git", "add", fname)
    sh(work, "git", "commit", "-q", "-m", msg)
    return sh(work, "git", "rev-parse", "HEAD")


def hyg_merge(work, tag, subject=GREEN, extra_commits=1):
    """Fleet-style: feature branch off develop, N commits, --no-ff merge with a hygiene subject. Returns (merge_sha, [feature commit shas])."""
    sh(work, "git", "checkout", "-q", "-b", "feat-" + tag, "develop")
    shas = [commit(work, "f_%s.txt" % tag, "feat(x): change %s-%d" % (tag, i)) for i in range(extra_commits)]
    sh(work, "git", "checkout", "-q", "develop")
    sh(work, "git", "merge", "-q", "--no-ff", "-m", subject, "feat-" + tag)
    return sh(work, "git", "rev-parse", "HEAD"), shas


def publish(work):
    sh(work, "git", "push", "-q", "origin", "main", "develop")
    sh(work, "git", "fetch", "-q", "origin")


def base_repo(name):
    origin, work = mkrepo(name)
    commit(work, "a.txt", "init")
    commit(work, "a.txt", "chore: second")
    sh(work, "git", "push", "-q", "origin", "main")
    sh(work, "git", "checkout", "-q", "-b", "develop")
    return origin, work


def gate(script, *args, env_extra=None, rel=False, cwd=None):
    """Run a gate through its real entry point under env -i. Returns (rc, last-json, stdout, stderr)."""
    path = os.path.join("qa", script) if rel else os.path.join(QA, script)
    env = ["env", "-i", "PATH=" + MINPATH, "NTFY_SERVER=http://127.0.0.1:9", "OVN_DIR=" + OVN, "OVN_REPOS_DIR=" + REPOS, "HOME=" + T]
    env += list(env_extra or [])
    p = subprocess.run(env + [PY, path] + list(args), cwd=(cwd or (OQ if rel else T)), capture_output=True, text=True, timeout=300)
    last = None
    try:
        last = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        pass
    return p.returncode, last, p.stdout, p.stderr


def shadow_row(gate_name, repo, ref, verdict="FAIL"):
    with open(os.path.join(STATE, "qa_shadow", gate_name + ".jsonl"), "a") as f:
        f.write(json.dumps({"gate": gate_name, "repo": repo, "ref": ref, "verdict": verdict, "summary": "seeded"}) + "\n")


# ======================================================================= pure helpers
print("# release_candidate: pure logic")
ok("classify green", rcm.classify(GREEN) == "green")
ok("classify no-tests is NOT green", rcm.classify(NOGATE) == "nogate")
ok("classify back-merge", rcm.classify(SYNC) == "sync")
ok("classify direct commit", rcm.classify("fix: manual hotfix") == "other")
st = rcm.effective_status([("s3", SYNC), ("s2", GREEN), ("s1", NOGATE)])
ok("sync inherits status of nearest older commit", st["s3"] == "green" and st["s2"] == "green" and st["s1"] == "nogate")
st = rcm.effective_status([("s2", SYNC), ("s1", "fix: direct")])
ok("sync on top of an ungated commit is NOT green", st["s2"] == "other")
ok("sync sitting directly on main is green", rcm.effective_status([("s1", SYNC)])["s1"] == "green")
ok("release name plain", rcm.pick_release_name("20261001", set()) == "release/20261001")
ok("release name collision -> -2", rcm.pick_release_name("20261001", {"release/20261001"}) == "release/20261001-2")
ok("release name collision -> -3", rcm.pick_release_name("20261001", {"release/20261001", "release/20261001-2"}) == "release/20261001-3")
toks = rcm.fail_tokens([{"gate": "antigaming", "repo": "r", "verdict": "FAIL", "ref": "deadbee1..cafe1234"},
                        {"gate": "scanners", "repo": "other", "verdict": "FAIL", "ref": "aaaaaaa1"},
                        {"gate": "staging_smoke", "repo": "r", "verdict": "FAIL", "ref": "bbbbbbb2"},
                        {"gate": "scanners", "repo": "r", "verdict": "PASS", "ref": "ccccccc3"},
                        {"gate": "migrations", "repo": "r", "verdict": "FAIL", "ref": "x", "details": {"head": "dddddddd4"}}], "r")
tk = [t for t, g in toks]
ok("fail_tokens: base..head keeps only the head", "cafe1234" in tk and "deadbee1" not in tk, tk)
ok("fail_tokens: other repo / non-code gates / PASS rows ignored", "aaaaaaa1" not in tk and "bbbbbbb2" not in tk and "ccccccc3" not in tk, tk)
ok("fail_tokens: details.head is read", "dddddddd4" in tk, tk)

# ======================================================================= release_candidate scenarios
print("# release_candidate: scenarios through the real entry point")
DATE = "20261001"

# 1 benign: tip is a green merge, no FAIL
o1, w1 = base_repo("benign")
hyg_merge(w1, "a")
tip1, _ = hyg_merge(w1, "b", extra_commits=2)
publish(w1)
rc, j, out, err = gate("release_candidate.py", "plan", "--repo", "benign", "--date", DATE, "--no-record")
ok("benign: exit 0, one JSON line last", rc == 0 and j is not None, err)
ok("benign: PASS and candidate == develop tip", j and j["verdict"] == "PASS" and j["ref"] == tip1[:10], j and j["summary"])
d = (j or {}).get("details", {})
ok("benign: release/%s named, main can fast-forward" % DATE, d.get("release_branch") == "release/" + DATE and d.get("ff_main_possible") is True, d.get("release_branch"))
ok("benign: commit list since main + features listed", d.get("commits_total") == 3 + 0 or d.get("commits_total") == 3, d.get("commits_total"))
ok("benign: features extracted", len(d.get("features", [])) == 3, d.get("features"))
rc, j2, _, _ = gate("release_candidate.py", "plan", "--repo", "benign", "--date", DATE, "--no-record", rel=True)
ok("benign: relative-path invocation from scripts/overnight-queue gives the same verdict", j2 and j2["verdict"] == "PASS" and j2["ref"] == j["ref"])
rc, j3, _, _ = gate("release_candidate.py", "check", "--repo", "benign", "--base", "origin/main", "--head", "origin/develop", "--no-record")
ok("benign: `check` alias (qa_replay contract) works", j3 and j3["verdict"] == "PASS")
rec = os.path.join(STATE, "qa_shadow", "release_candidate.jsonl")
before = os.path.exists(rec)
gate("release_candidate.py", "plan", "--repo", "benign", "--date", DATE)
ok("shadow log written when --no-record is absent, not before", (not before) and os.path.exists(rec) and len(open(rec).read().strip().splitlines()) == 1)

# 2 negative control: a QA FAIL on a commit INSIDE the tip merge -> tip held back, candidate = previous green
o2, w2 = base_repo("failinrange")
prev2, _ = hyg_merge(w2, "a")
tip2, feat2 = hyg_merge(w2, "b", extra_commits=2)
publish(w2)
shadow_row("antigaming", "failinrange", "%s..%s" % (prev2, feat2[1]))  # base..head style ref, head is inside tip merge
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "failinrange", "--date", DATE, "--no-record")
d = (j or {}).get("details", {})
ok("FAIL in range: tip is NOT the candidate (held back), FLAG", j and j["verdict"] == "FLAG" and j["ref"] == prev2[:10], j and j["summary"])
ok("FAIL in range: reason names the gate and sha", any("antigaming" in s["reason"] and feat2[1][:10] in s["reason"] for s in d.get("skipped", [])), d.get("skipped"))
ok("FAIL in range: held_back lists the tip", d.get("held_back") and d["held_back"][0]["sha"] == tip2[:10], d.get("held_back"))
# a FAIL on the *base* of a base..head ref must not taint
o2b, w2b = base_repo("basefail")
prevb, _ = hyg_merge(w2b, "a")
tipb, _ = hyg_merge(w2b, "b")
publish(w2b)
shadow_row("antigaming", "basefail", "%s..%s" % (prevb, tipb), verdict="PASS")
main_b = sh(w2b, "git", "rev-parse", "origin/main")
shadow_row("scanners", "basefail", "%s..%s" % (prevb, main_b))  # FAIL whose head is an old commit already in main (outside the range), base is a good commit
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "basefail", "--date", DATE, "--no-record")
ok("FAIL row whose BASE is a good commit does not poison it (PASS on tip)", j and j["verdict"] == "PASS", j and j["summary"])
shadow_row("scanners", "basefail", "%s..zzzzzzz" % prevb)  # head unresolvable: we cannot tell which commit it condemns -> never PASS
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "basefail", "--date", DATE, "--no-record")
ok("FAIL row with an unresolvable head -> UNVERIFIED (was a silent PASS)", j and j["verdict"] == "UNVERIFIED", j and j["summary"])

# 3 ungated direct commit on top of a green merge
o3, w3 = base_repo("ungated")
g3, _ = hyg_merge(w3, "a")
commit(w3, "z.txt", "fix: manual change straight on develop")
publish(w3)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "ungated", "--date", DATE, "--no-record")
ok("direct/ungated tip commit is held back; candidate = last green merge", j and j["verdict"] == "FLAG" and j["ref"] == g3[:10], j and j["summary"])
ok("ungated: reason says so", any("ungated" in s["reason"] or "not a green" in s["reason"] for s in j["details"].get("skipped", [])))

# 3b gate=no-tests merge is not green
o3b, w3b = base_repo("notests")
g3b, _ = hyg_merge(w3b, "a")
hyg_merge(w3b, "b", subject=NOGATE)
publish(w3b)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "notests", "--date", DATE, "--no-record")
ok("gate=no-tests merge is never a candidate", j and j["ref"] == g3b[:10] and j["verdict"] == "FLAG", j and j["summary"])

# 4 sync back-merge on top of green inherits green (the real shape: promote merge on main, back-merged into develop)
o4, w4 = base_repo("sync")
hyg_merge(w4, "a")
g4, _ = hyg_merge(w4, "b")
sh(w4, "git", "checkout", "-q", "main")
sh(w4, "git", "merge", "-q", "--no-ff", "-m", "release: promote develop -> main (20260930-0900)", "develop")
sh(w4, "git", "checkout", "-q", "develop")
hyg_merge(w4, "c")
sh(w4, "git", "merge", "-q", "--no-ff", "-m", SYNC, "main")
sync4 = sh(w4, "git", "rev-parse", "HEAD")
publish(w4)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "sync", "--date", DATE, "--no-record")
ok("back-merge tip inherits green -> PASS, candidate == tip, contains main", j and j["verdict"] == "PASS" and j["ref"] == sync4[:10] and j["details"]["ff_main_possible"], j and j["summary"])
ok("promote merge on main is excluded from 'commits since main'", j["details"]["commits_total"] == 1, j["details"].get("commits_total"))

# 5 main diverged (a direct commit on main not yet back-merged): no develop commit contains main -> UNVERIFIED fallback
o5, w5 = base_repo("diverged")
hyg_merge(w5, "a")
hyg_merge(w5, "b")
sh(w5, "git", "checkout", "-q", "main")
commit(w5, "hot.txt", "fix: hotfix straight on main")
sh(w5, "git", "checkout", "-q", "develop")
publish(w5)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "diverged", "--date", DATE, "--no-record")
ok("main has an un-back-merged commit: UNVERIFIED fallback to develop tip, never PASS", j and j["verdict"] == "UNVERIFIED" and j["details"]["fallback"] is True, j and j["summary"])
ok("diverged: every skip reason is 'does not contain main'", all("does not contain main" in s["reason"] for s in j["details"]["skipped"]), j["details"]["skipped"][:2])
ok("diverged: ff_main_possible is False", j["details"]["ff_main_possible"] is False)

# 6 no green merge at all
o6, w6 = base_repo("nogreen")
commit(w6, "z.txt", "feat: direct 1")
commit(w6, "z.txt", "feat: direct 2")
publish(w6)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "nogreen", "--date", DATE, "--no-record")
ok("no green hygiene merge -> UNVERIFIED fallback", j and j["verdict"] == "UNVERIFIED" and j["details"]["fallback"], j and j["summary"])

# 7 nothing to release
o7, w7 = base_repo("same")
publish(w7)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "same", "--date", DATE, "--no-record")
ok("develop == main -> NA", j and j["verdict"] == "NA", j and j["summary"])

# 8 name collision + idempotent re-plan
sh(w1, "git", "push", "-q", "origin", "develop:refs/heads/release/%s" % DATE)  # same sha as candidate -> reuse
sh(w1, "git", "fetch", "-q", "origin")
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "benign", "--date", DATE, "--no-record")
ok("existing release branch AT the candidate is reused (idempotent)", j["details"]["release_branch"] == "release/" + DATE and j["details"]["release_branch_exists"], j["details"].get("release_branch"))
sh(w1, "git", "push", "-q", "origin", "origin/main:refs/heads/release/%s" % DATE, "--force")  # now it exists but at a different sha
sh(w1, "git", "fetch", "-q", "origin")
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "benign", "--date", DATE, "--no-record")
ok("existing release branch at ANOTHER sha -> new name release/%s-2" % DATE, j["details"]["release_branch"] == "release/%s-2" % DATE, j["details"].get("release_branch"))

# 9 UNVERIFIED on infra problems (never FAIL/PASS)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "no-such-repo", "--no-record")
ok("unknown repo -> UNVERIFIED exit 0", rc == 0 and j and j["verdict"] == "UNVERIFIED")
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "benign", "--develop", "origin/nope", "--no-record")
ok("missing develop ref -> UNVERIFIED", rc == 0 and j and j["verdict"] == "UNVERIFIED")
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "benign", "--no-record", env_extra=["PATH=/nonexistent"])
ok("no git on PATH -> UNVERIFIED (not PASS, not FAIL), exit 0", rc == 0 and j and j["verdict"] in ("UNVERIFIED",), (j or {}).get("summary"))

# ----------------------------------------------------------------------- cut: never touches the live clone, never pushes in shadow
print("# release_candidate: cut")


def refs_snapshot(work):
    return sh(work, "git", "for-each-ref") + "|" + sh(work, "git", "worktree", "list") + "|" + sh(work, "git", "branch", "-a")


def origin_refs(origin):
    return sh(origin, "git", "for-each-ref", "--format=%(refname) %(objectname)")


# fresh repo for cut so the release/ branches pushed above do not interfere
oc, wc = base_repo("cutme")
hyg_merge(wc, "a")
tipc, _ = hyg_merge(wc, "b", extra_commits=2)
publish(wc)
snap_before, orig_before = refs_snapshot(wc), origin_refs(oc)
rc, j, _, err = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", DATE, "--no-record")
ok("cut (shadow): PASS, ff of main simulated OK", rc == 0 and j and j["verdict"] == "PASS" and j["details"]["ff_main_simulation"] == "ok", (j or {}).get("summary", err))
ok("cut (shadow): reports what it WOULD push, pushed=False", j and j["details"]["pushed"] is False and any("git push origin release/%s" % DATE in s for s in j["details"]["would_push"]))
ok("cut: live clone untouched (refs, worktrees, branches identical)", refs_snapshot(wc) == snap_before)
ok("cut: remote untouched", origin_refs(oc) == orig_before)
ok("cut: scratch dir removed", j["details"]["scratch_dir"] is None and not [x for x in os.listdir(tempfile.gettempdir()) if x.startswith("qa-release-") and os.path.exists(os.path.join(tempfile.gettempdir(), x, "clone"))])
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", DATE, "--really-push", "--no-record")
ok("cut --really-push in SHADOW mode is REFUSED, nothing pushed", j and j["details"].get("push_refused", "").startswith("mode is shadow") and j["details"]["pushed"] is False and origin_refs(oc) == orig_before, (j or {}).get("summary"))
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", DATE, "--really-push", "--no-record", env_extra=["OVN_QA_RELEASE_CANDIDATE=off"])
ok("cut --really-push with mode=off is refused too", origin_refs(oc) == orig_before)
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", DATE, "--keep", "--no-record")
kept = (j or {}).get("details", {}).get("scratch_dir")
ok("cut --keep leaves a real local branch in a scratch clone", kept and os.path.isdir(kept) and sh(kept, "git", "rev-parse", "--abbrev-ref", "HEAD") != "", kept)
ok("cut --keep: the scratch clone has branch release/%s at the candidate" % DATE, kept and sh(kept, "git", "rev-parse", "release/" + DATE) == tipc, kept)
if kept:
    shutil.rmtree(os.path.dirname(kept), ignore_errors=True)
# enforce + really-push: pushes the BRANCH only; main + tags untouched
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", DATE, "--really-push", "--no-record", env_extra=["OVN_QA_RELEASE_CANDIDATE=enforce"])
after = origin_refs(oc)
ok("cut --really-push in ENFORCE pushes release/%s (branch only)" % DATE, j and j["details"]["pushed"] is True and ("refs/heads/release/%s %s" % (DATE, tipc)) in after, (j or {}).get("summary"))
main_sha_origin = sh(oc, "git", "rev-parse", "refs/heads/main")
ok("cut --really-push never moves main and creates no tag", main_sha_origin == sh(wc, "git", "rev-parse", "origin/main") and "refs/tags" not in after)
# negative control: main diverged -> ff impossible -> cut FAILs and refuses to push even in enforce
od, wd = base_repo("cutdiv")
hyg_merge(wd, "a")
sh(wd, "git", "checkout", "-q", "main")
commit(wd, "hot.txt", "fix: hotfix on main")
sh(wd, "git", "checkout", "-q", "develop")
publish(wd)
orig_d = origin_refs(od)
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutdiv", "--date", DATE, "--really-push", "--no-record", env_extra=["OVN_QA_RELEASE_CANDIDATE=enforce"])
ok("diverged main: cut verdict is FAIL (main cannot fast-forward) and nothing is pushed", j and j["verdict"] == "FAIL" and j["details"]["pushed"] is False and origin_refs(od) == orig_d, (j or {}).get("summary"))
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutdiv", "--date", DATE, "--no-record", "--enforce-exit", env_extra=["OVN_QA_RELEASE_CANDIDATE=enforce"])
ok("enforce + FAIL + --enforce-exit => exit 1", rc == 1)
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutdiv", "--date", DATE, "--no-record", "--enforce-exit")
ok("shadow + FAIL + --enforce-exit => exit 0 (never blocks)", rc == 0)
# --run-gates: sibling gate_*.py are run against main..candidate; a FAIL propagates
gd = os.path.join(T, "gates")
os.makedirs(gd)
open(os.path.join(gd, "gate_fake.py"), "w").write("import json,sys\nprint(json.dumps({'verdict':'FAIL','summary':'seeded gate failure'}))\n")
open(os.path.join(gd, "gate_good.py"), "w").write("import json\nprint(json.dumps({'verdict':'PASS','summary':'ok'}))\n")
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261002", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + gd])
ok("--run-gates: a FAIL from a gate script makes the cut FAIL", j and j["verdict"] == "FAIL" and j["details"]["gates"]["gate_fake"]["verdict"] == "FAIL" and j["details"]["gates"]["gate_good"]["verdict"] == "PASS", (j or {}).get("summary"))
open(os.path.join(gd, "gate_fake.py"), "w").write("raise SystemExit(3)\n")
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261003", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + gd])
ok("--run-gates: a crashing gate script is UNVERIFIED for that gate AND the cut is UNVERIFIED (never PASS)", j and j["details"]["gates"]["gate_fake"]["verdict"] == "UNVERIFIED" and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))

# ---- review regressions (FALSE CONFIDENCE class): each of these was a silent PASS before the fix
print("# review regressions")


def gatedir(name, **scripts):
    d = os.path.join(T, name)
    os.makedirs(d, exist_ok=True)
    for fn, body in scripts.items():
        open(os.path.join(d, fn + ".py"), "w").write(body)
    return d


PASSG = "import json\nprint(json.dumps({'verdict':'PASS','summary':'ok'}))\n"
for label, body, want in (("gate prints UNVERIFIED", "import json\nprint(json.dumps({'verdict':'UNVERIFIED','summary':'could not'}))\n", "UNVERIFIED"),
                          ("gate crashes (exit 3)", "raise SystemExit(3)\n", "UNVERIFIED"),
                          ("gate prints FLAG", "import json\nprint(json.dumps({'verdict':'FLAG','summary':'meh'}))\n", "FLAG"),
                          ("gate prints a bogus verdict", "import json\nprint(json.dumps({'verdict':'GREAT'}))\n", "UNVERIFIED"),
                          ("gate prints PASS but exits 3", "import json\nprint(json.dumps({'verdict':'PASS'}))\nraise SystemExit(3)\n", "UNVERIFIED")):
    gd2 = gatedir("g_" + label.split()[1], gate_a=PASSG, gate_b=body)
    rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261004", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + gd2])
    ok("cut --run-gates: %s -> %s, not PASS" % (label, want), j and j["verdict"] == want, (j or {}).get("summary"))
gd2 = gatedir("g_hang", gate_a=PASSG, gate_b="import time\ntime.sleep(60)\n")
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261004", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + gd2, "QA_RELEASE_GATE_TIMEOUT=2"])
ok("cut --run-gates: a HUNG gate (timeout) -> UNVERIFIED, not PASS", j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
os.makedirs(os.path.join(T, "g_empty"), exist_ok=True)
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261004", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + os.path.join(T, "g_empty")])
ok("cut --run-gates with ZERO gate scripts -> UNVERIFIED, not PASS", j and j["verdict"] == "UNVERIFIED" and "ZERO" in j["summary"], (j or {}).get("summary"))
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261004", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + os.path.join(T, "nonexistent")])
ok("cut --run-gates with a MISSING gates dir -> UNVERIFIED, not PASS", j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
gd2 = gatedir("g_allpass", gate_a=PASSG, gate_b=PASSG)
rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", "cutme", "--date", "20261004", "--run-gates", "--no-record", env_extra=["QA_GATES_DIR=" + gd2])
ok("benign control: all gates PASS -> cut PASS", j and j["verdict"] == "PASS", (j or {}).get("summary"))

# FAIL rows whose ref cannot be resolved to a commit must not give a silent PASS
for ref in ("claude/feature", "HEAD~2", "origin/develop", "", "0123456789abcdef"):
    nm = "unres" + str(abs(hash(ref)) % 10000)
    ou, wu = base_repo(nm)
    hyg_merge(wu, "a")
    hyg_merge(wu, "b")
    publish(wu)
    shadow_row("gate_antigaming", nm, ref)
    rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", nm, "--date", DATE, "--no-record")
    ok("FAIL row with unresolvable ref %r -> UNVERIFIED, not PASS" % ref, j and j["verdict"] == "UNVERIFIED" and j["details"]["coverage"]["unresolved_fail_rows"] == 1, (j or {}).get("summary"))
    rc, j, _, _ = gate("release_candidate.py", "cut", "--repo", nm, "--date", DATE, "--no-record")
    ok("  ... and cut is UNVERIFIED too (%r)" % ref, j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
nm = "unresother"
ou, wu = base_repo(nm)
hyg_merge(wu, "a")
publish(wu)
shadow_row("gate_antigaming", "some-other-repo", "claude/feature")
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", nm, "--date", DATE, "--no-record")
ok("benign control: unresolvable FAIL row of ANOTHER repo does not affect this repo (PASS)", j and j["verdict"] == "PASS", (j or {}).get("summary"))

# vacuity warning must not vanish after the gate's own first recorded run
ov, wv = base_repo("vac")
hyg_merge(wv, "a")
publish(wv)
for i in (1, 2, 3):
    rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "vac", "--date", DATE)  # recorded
    ok("recorded run #%d: PASS still says the no-FAIL check is vacuous" % i, j and j["verdict"] == "PASS" and "vacuous" in j["summary"], (j or {}).get("summary"))
shadow_row("gate_antigaming", "vac", "f" * 7, verdict="PASS")  # a real code-gate row for this repo => not vacuous any more
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "vac", "--date", DATE, "--no-record")
ok("benign control: once a real code gate has rows for the repo the warning goes away", j and j["verdict"] == "PASS" and "vacuous" not in j["summary"], (j or {}).get("summary"))

# forged green: a direct (non-merge) commit whose message merely contains gate=tests-green
ok("classify: non-merge commit with the green text is NOT green", rcm.classify(GREEN, is_merge=False) == "other")
ok("effective_status honours is_merge=False", rcm.effective_status([("s1", GREEN, False)])["s1"] == "other")
of, wf = base_repo("forged")
g_f, _ = hyg_merge(wf, "a")
commit(wf, "z.txt", "chore: sneaky direct commit (branch-hygiene, gate=tests-green)")
publish(wf)
rc, j, _, _ = gate("release_candidate.py", "plan", "--repo", "forged", "--date", DATE, "--no-record")
ok("forged direct commit claiming gate=tests-green is held back (FLAG on the real merge)", j and j["verdict"] == "FLAG" and j["ref"] == g_f[:10], (j or {}).get("summary"))

# history subcommand on the sync repo (has a real 'release: promote' merge on main)
rc, j, _, _ = gate("release_candidate.py", "history", "--repo", "sync", "--n", "5")
ok("history: replays the promote on main and agrees the tip was the candidate", j and j["details"]["n"] == 1 and j["details"]["tip_ok"] == 1 and j["details"]["ff_impossible"] == 0, (j or {}).get("summary"))

# ======================================================================= staging_check
print("# staging_check")
ANC, TIP = "a" * 40, "b" * 40


def anc(a, b):
    return {("a" * 40, "b" * 40): True}.get((a, b), False if (a in (ANC, TIP) and b in (ANC, TIP)) else None)


def dep(status, sha, created="2026-10-01T10:00:00Z", did="d1"):
    return {"id": did + "xxxxxxxx", "status": status, "createdAt": created, "meta": {"commitHash": sha, "branch": "develop"}}


nd = scm.normalize
ok("decide MATCH", scm.decide(TIP, nd([dep("SUCCESS", TIP)]), anc)[0] == "MATCH")
ok("decide MATCH with short sha", scm.decide(TIP, nd([dep("SUCCESS", TIP[:10])]), anc)[0] == "MATCH")
ok("decide MATCH_SUPERSET (staging ahead)", scm.decide(ANC, nd([dep("SUCCESS", TIP)]), anc)[0] == "MATCH_SUPERSET")
ok("decide MISMATCH_BEHIND (candidate newer than staging)", scm.decide(TIP, nd([dep("SUCCESS", ANC)]), anc)[0] == "MISMATCH_BEHIND")
ok("decide MISMATCH_DIVERGED", scm.decide("c" * 40, nd([dep("SUCCESS", ANC)]), lambda a, b: False)[0] == "MISMATCH_DIVERGED")
r = scm.decide(TIP, nd([dep("FAILED", TIP, "2026-10-01T11:00:00Z", "n"), dep("SUCCESS", ANC, "2026-10-01T10:00:00Z", "o")]), anc)
ok("decide: latest deploy FAILED -> MISMATCH_FAILED naming the older build still served (the billwatch incident)", r[0] == "MISMATCH_FAILED" and r[2] == ANC, r)
ok("decide: CRASHED counts as failed", scm.decide(TIP, nd([dep("CRASHED", TIP)]), anc)[0] == "MISMATCH_FAILED")
ok("decide: the candidate's own deploy still building -> BUILDING (promote_gate holds; verdict stays UNVERIFIED)", scm.decide(TIP, nd([dep("BUILDING", TIP)]), anc)[0] == "BUILDING" and scm.VERDICT_OF["BUILDING"] == "UNVERIFIED")
ok("decide: an unrelated in-flight deploy -> UNVERIFIED (retry later), never a hold", scm.decide(TIP, nd([dep("BUILDING", "e" * 40)]), lambda a, b: False)[0] == "UNVERIFIED")
ok("decide: REMOVED/SKIPPED builds are never 'latest'", scm.decide(TIP, nd([dep("REMOVED", ANC, "2026-10-01T12:00:00Z"), dep("SUCCESS", TIP, "2026-10-01T10:00:00Z")]), anc)[0] == "MATCH")
for bad in ("4", "bbb", "bbbbbb", "zzzzzzzz", "b" * 6):
    ok("decide: staging commit %r (too short/not hex) -> UNVERIFIED, never MATCH" % bad, scm.decide(TIP, nd([dep("SUCCESS", bad)]), anc)[0] == "UNVERIFIED", scm.decide(TIP, nd([dep("SUCCESS", bad)]), anc))
ok("decide: 7-char prefix of the candidate is still a MATCH", scm.decide(TIP, nd([dep("SUCCESS", TIP[:7])]), anc)[0] == "MATCH")
ok("decide: candidate itself garbage -> UNVERIFIED", scm.decide("4", nd([dep("SUCCESS", TIP)]), anc)[0] == "UNVERIFIED")
ok("decide: no deployments -> UNVERIFIED", scm.decide(TIP, [], anc)[0] == "UNVERIFIED")
ok("decide: unknown commit in local clone -> UNVERIFIED (never FAIL)", scm.decide(TIP, nd([dep("SUCCESS", "d" * 40)]), lambda a, b: None)[0] == "UNVERIFIED")

# real entry point: stub `railway` on PATH (it must be invoked as `railway link ...` then `railway deployment list --json ...`)
sc_repo = "cutme"
cand_full = sh(wc, "git", "rev-parse", "origin/develop")
parent_full = sh(wc, "git", "rev-parse", "origin/develop~1")
RW = os.path.join(T, "stubbin")
os.makedirs(RW)
RAILWAY_STUB = os.path.join(RW, "railway")


def write_stub(deploys, link_rc=0, list_rc=0):
    open(os.path.join(T, "deploys.json"), "w").write(json.dumps(deploys))
    open(RAILWAY_STUB, "w").write("#!/bin/sh\ncase \"$1 $2\" in\n  'link --project') exit %d;;\n  'deployment list') [ %d -ne 0 ] && exit %d; cat %s; exit 0;;\nesac\nexit 9\n" % (
        link_rc, list_rc, list_rc, os.path.join(T, "deploys.json")))
    os.chmod(RAILWAY_STUB, 0o755)


# the stub config maps repo -> ids; point the module at our repo name for the subprocess via the real RAILWAY dict key 'billwatch'
# (we reuse repo name billwatch by symlinking a clone) so the REAL config path is exercised
os.symlink(os.path.join(REPOS, "cutme"), os.path.join(REPOS, "billwatch"))
write_stub([dep("SUCCESS", cand_full)])
envp = ["PATH=%s:%s" % (RW, MINPATH)]
rc, j, _, err = gate("staging_check.py", "check", "--repo", "billwatch", "--release-plan", "--no-record", env_extra=envp)
ok("staging_check real entry (railway stub): MATCH -> PASS", rc == 0 and j and j["verdict"] == "PASS" and j["details"]["relation"] == "MATCH", (j or {}).get("summary", err))
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", rel=True, env_extra=envp)
ok("staging_check relative-path entry, explicit --sha", j and j["verdict"] == "PASS")
write_stub([dep("SUCCESS", parent_full)])
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", env_extra=envp)
ok("NEGATIVE: staging serves an older commit -> FAIL MISMATCH_BEHIND", j and j["verdict"] == "FAIL" and j["details"]["relation"] == "MISMATCH_BEHIND", (j or {}).get("summary"))
write_stub([dep("FAILED", cand_full, "2026-10-01T11:00:00Z", "n"), dep("SUCCESS", parent_full, "2026-10-01T10:00:00Z", "o")])
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", env_extra=envp)
ok("NEGATIVE: latest staging deploy FAILED (silent stale serving) -> FAIL", j and j["verdict"] == "FAIL" and j["details"]["relation"] == "MISMATCH_FAILED", (j or {}).get("summary"))
write_stub([dep("SUCCESS", cand_full)], list_rc=1)
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", env_extra=envp)
ok("railway CLI error -> UNVERIFIED (never FAIL)", rc == 0 and j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
write_stub([dep("SUCCESS", cand_full)], link_rc=1)
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", env_extra=envp)
ok("railway link failure (expired login) -> UNVERIFIED", j and j["verdict"] == "UNVERIFIED")
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record")
ok("no railway CLI and no exported file (the GPU box) -> UNVERIFIED with the reason", j and j["verdict"] == "UNVERIFIED" and "railway CLI not installed" in json.dumps(j["details"]["providers"]), (j or {}).get("summary"))
# file provider (the box path): export format -> check
os.makedirs(os.path.join(STATE, "staging_deploys"), exist_ok=True)
fpath = os.path.join(STATE, "staging_deploys", "billwatch.json")
json.dump({"repo": "billwatch", "fetched_at": time.time(), "deployments": [dep("SUCCESS", cand_full)]}, open(fpath, "w"))
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record")
ok("file provider (exported on the Mac, read on the box): MATCH", j and j["verdict"] == "PASS" and j["details"]["provider"] == "file", (j or {}).get("summary"))
json.dump({"repo": "billwatch", "fetched_at": time.time() - 7200, "deployments": [dep("SUCCESS", cand_full)]}, open(fpath, "w"))
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record")
ok("NEGATIVE: stale exported file is NOT trusted -> UNVERIFIED", j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
os.remove(fpath)
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", "f" * 40, "--no-record", env_extra=envp)
ok("candidate unknown to the clone -> UNVERIFIED", j and j["verdict"] == "UNVERIFIED")
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "nope", "--no-record")
ok("unknown repo -> UNVERIFIED exit 0", rc == 0 and j and j["verdict"] == "UNVERIFIED")
rc, j, _, _ = gate("staging_check.py", "check", "--repo", "benign", "--no-record")
ok("repo with no staging backend (website/xlite/agent shape) -> NA, not UNVERIFIED", rc == 0 and j and j["verdict"] == "NA", (j or {}).get("summary"))
# no token ever printed: environment secret placed in env must not appear in output
rc, j, out, err = gate("staging_check.py", "check", "--repo", "billwatch", "--sha", cand_full, "--no-record", env_extra=envp + ["RAILWAY_TOKEN=SUPERSECRET-TOKEN-123"])
ok("no env secret leaks into stdout/stderr", "SUPERSECRET" not in out + err)

# ======================================================================= staging_smoke against a localhost fake staging backend
print("# staging_smoke")


class Fake(BaseHTTPRequestHandler):
    S = {}  # shared mode/state

    def log_message(self, *a):
        pass

    def _send(self, code, body=None, ctype="application/json", extra=None):
        data = (json.dumps(body) if not isinstance(body, str) else body).encode() if body is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode() if n else ""

    def _auth(self):
        return self.headers.get("Authorization") == "Bearer TOKEN-ABC-123"

    def do_OPTIONS(self):
        S = Fake.S
        o = self.headers.get("Origin", "")
        if S.get("cors") == "none":
            return self._send(200, {})
        if S.get("cors") == "reflect_all" or o == "https://front.example":
            return self._send(200, {}, extra={"Access-Control-Allow-Origin": o})
        return self._send(400, {}, extra={})

    def do_GET(self):
        S = Fake.S
        S.setdefault("log", []).append(("GET", self.path))
        p = self.path
        if p == "/health":
            if S.get("health") == "502":
                return self._send(502, {"message": "Application failed to respond"})
            if S.get("health") == "html":
                return self._send(200, "<html>spa</html>", ctype="text/html")
            return self._send(200, {"status": "healthy"})
        if p == "/front":
            return self._send(200, "<html><div id=root>MARKER</div></html>", ctype="text/html")
        if p == "/api/open":
            return self._send(200, {"items": []})
        if p == "/api/guarded":
            if S.get("guard") == "open" or self._auth():
                return self._send(200, {"ok": True})
            return self._send(401, {"detail": "no"})
        if p == "/api/me":
            if not self._auth():
                return self._send(401, {})
            return self._send(200, {"display_name": S.get("display_name", "")})
        if p == "/api/things":
            if not self._auth():
                return self._send(401, {})
            return self._send(200, [{"id": i} for i in S.get("things", [])])
        return self._send(404, {})

    def do_POST(self):
        S = Fake.S
        body = self._body()
        S.setdefault("log", []).append(("POST", self.path))
        if self.path == "/api/login":
            if S.get("login") == "401":
                return self._send(401, {"detail": "bad"})
            S["login_body"] = body
            return self._send(200, {"access_token": "TOKEN-ABC-123"})
        if self.path == "/api/things":
            if not self._auth():
                return self._send(401, {})
            tid = len(S.get("things", [])) + 1 + S.get("n", 0)
            if S.get("write") != "drop":  # 'drop' = 201 but not persisted: the classic fake-success
                S.setdefault("things", []).append(tid)
            return self._send(201, {"id": tid})
        return self._send(404, {})

    def do_PATCH(self):
        S = Fake.S
        body = json.loads(self._body() or "{}")
        S.setdefault("log", []).append(("PATCH", self.path))
        if self.path == "/api/me" and self._auth():
            if S.get("write") != "drop":
                S["display_name"] = body.get("display_name", "")
            return self._send(200, {"ok": True})
        return self._send(401, {})

    def do_DELETE(self):
        S = Fake.S
        S.setdefault("log", []).append(("DELETE", self.path))
        if self.path.startswith("/api/things/") and self._auth():
            try:
                S["things"].remove(int(self.path.rsplit("/", 1)[1]))
            except (ValueError, KeyError):
                pass
            return self._send(204, None)
        return self._send(401, {})


srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % PORT

CFG = {"defaults": {"timeout_s": 5, "deny_origin": "https://evil.example"}, "repos": {
    "fakeapp": {
        "health": {"path": "/health", "json_has": "status"},
        "login": {"kind": "json", "path": "/api/login", "token_key": "access_token",
                  "creds": {"email_env": "T_EMAIL", "password_env": "T_PW", "file": "fakeapp"}},
        "business": [{"name": "open", "path": "/api/open", "auth": False, "json_has": "items"},
                     {"name": "guarded (auth)", "path": "/api/guarded", "auth": True},
                     {"name": "anonymous rejected", "path": "/api/guarded", "auth": False, "expect_status": 401}],
        "write_read": {"name": "create thing", "write": {"method": "POST", "path": "/api/things", "body": {"n": "{marker}"}, "capture": {"id": "id"}},
                       "read": {"path": "/api/things", "expect_in_list": {"field": "id", "value": "{id}"}},
                       "cleanup": {"method": "DELETE", "path": "/api/things/{id}"}},
        "frontend": {"url": BASE + "/front", "contains": "MARKER"},
        "cors": {"path": "/api/open", "origins": ["https://front.example"]}},
    "fakeapp2": {  # PATCH-style write (billwatch shape) + no-login repo (gitlark shape)
        "health": {"path": "/health"},
        "login": {"kind": "none", "reason": "oauth only", "token_env": "T_TOKEN"},
        "business": [{"name": "open", "path": "/api/open", "auth": False}],
        "write_read": {"name": "patch me", "requires_token": True, "write": {"method": "PATCH", "path": "/api/me", "body": {"display_name": "x-{marker}"}},
                       "read": {"path": "/api/me", "expect_json_equals": {"display_name": "x-{marker}"}}}}}}
CFGP = os.path.join(T, "smoke.config.json")
json.dump(CFG, open(CFGP, "w"))
SENV = ["QA_SMOKE_ALLOW_LOCAL=1", "T_EMAIL=tester@example.test", "T_PW=pw-for-test-SECRET9"]


def smoke(repo="fakeapp", extra=None, rel=False, env=None, base=None):
    return gate("staging_smoke.py", "check", "--repo", repo, "--base-url", base or BASE, "--config", CFGP, "--no-record", *(extra or []),
                env_extra=SENV + (env or []), rel=rel)


def reset(**kw):
    Fake.S.clear()
    Fake.S.update(kw)


def step(j, prefix):
    return next((s for s in j["details"]["steps"] if s["name"].startswith(prefix)), None)


reset()
t0 = time.time()
rc, j, out, err = smoke()
ok("smoke benign: PASS, every step ok", rc == 0 and j and j["verdict"] == "PASS" and all(s["status"] == "ok" for s in j["details"]["steps"]), (j or {}).get("summary", err))
ok("smoke benign: ran health, login, 3 business, write_read+cleanup, frontend, cors x2", j and len(j["details"]["steps"]) == 10, [s["name"] for s in (j or {"details": {"steps": []}})["details"]["steps"]])
ok("smoke benign: the write was cleaned up on the server (DELETE issued, list empty)", ("DELETE", "/api/things/1") in Fake.S["log"] and Fake.S["things"] == [])
ok("smoke benign: runtime recorded", j and j["ms"] is not None and j["ms"] < 20000)
rc, jr, _, _ = smoke(rel=True)
ok("smoke benign via relative path", jr and jr["verdict"] == "PASS")
ok("SECRETS: password / token / email never in stdout or stderr", all(s not in out + err for s in ("pw-for-test-SECRET9", "TOKEN-ABC-123", "tester@example.test")))
rec2 = os.path.join(STATE, "qa_shadow", "staging_smoke.jsonl")
reset()
gate("staging_smoke.py", "check", "--repo", "fakeapp", "--base-url", BASE, "--config", CFGP, env_extra=SENV)  # recorded run
ok("SECRETS: shadow log contains no secret either", os.path.exists(rec2) and all(s not in open(rec2).read() for s in ("pw-for-test-SECRET9", "TOKEN-ABC-123", "tester@example.test")))

# negative controls: each seeded defect must FAIL the right step
reset(health="502")
rc, j, _, _ = smoke()
ok("NEG health 502 -> FAIL (health step)", j and j["verdict"] == "FAIL" and step(j, "health")["status"] == "fail", (j or {}).get("summary"))
ok("NEG health 502: dependent steps are skipped, not run", j and step(j, "login")["status"] == "skip")
reset(health="html")
rc, j, _, _ = smoke()
ok("NEG health 200 but HTML (SPA fallback) -> FAIL", j and j["verdict"] == "FAIL" and "content-type" in step(j, "health")["detail"], (j or {}).get("summary"))
reset(login="401")
rc, j, _, _ = smoke()
ok("NEG login rejected -> FAIL, dependent auth steps skipped", j and j["verdict"] == "FAIL" and step(j, "login")["status"] == "fail" and step(j, "write_read")["status"] == "skip", (j or {}).get("summary"))
reset(write="drop")
rc, j, _, _ = smoke()
ok("NEG write returns 201 but is not persisted -> FAIL on read-back", j and j["verdict"] == "FAIL" and step(j, "write_read: create")["status"] == "fail" and "read-back" in step(j, "write_read: create")["detail"], (j or {}).get("summary"))
reset(guard="open")
rc, j, _, _ = smoke()
ok("NEG protected endpoint answers anonymous requests -> FAIL (auth guard)", j and j["verdict"] == "FAIL" and step(j, "business: anonymous")["status"] == "fail", (j or {}).get("summary"))
reset(cors="none")
rc, j, _, _ = smoke()
ok("NEG missing CORS allow-origin for the real frontend -> FAIL", j and j["verdict"] == "FAIL" and step(j, "cors: https://front.example")["status"] == "fail", (j or {}).get("summary"))
reset(cors="reflect_all")
rc, j, _, _ = smoke()
ok("NEG CORS reflects an arbitrary origin -> FAIL", j and j["verdict"] == "FAIL" and step(j, "cors: deny")["status"] == "fail", (j or {}).get("summary"))
CFG2 = json.loads(json.dumps(CFG))
CFG2["repos"]["fakeapp"]["frontend"]["contains"] = "NOT-THERE"
json.dump(CFG2, open(CFGP, "w"))
reset()
rc, j, _, _ = smoke()
ok("NEG frontend marker missing -> FAIL", j and j["verdict"] == "FAIL" and step(j, "frontend")["status"] == "fail")
json.dump(CFG, open(CFGP, "w"))

# infra problems must be UNVERIFIED, never FAIL/PASS
rc, j, _, _ = smoke(base="http://127.0.0.1:9")
ok("connection refused -> UNVERIFIED (never fail closed on infra), exit 0", rc == 0 and j and j["verdict"] == "UNVERIFIED", (j or {}).get("summary"))
reset()
rc, j, _, _ = gate("staging_smoke.py", "check", "--repo", "fakeapp", "--base-url", BASE, "--config", CFGP, "--no-record", env_extra=["QA_SMOKE_ALLOW_LOCAL=1"])
ok("credentials not provisioned -> UNVERIFIED (login), not FAIL", j and j["verdict"] == "UNVERIFIED" and step(j, "login")["status"] == "unverified", (j or {}).get("summary"))
rc, j, _, _ = gate("staging_smoke.py", "check", "--repo", "fakeapp", "--base-url", BASE, "--config", "/nonexistent.json", "--no-record", env_extra=SENV)
ok("missing config -> UNVERIFIED", rc == 0 and j and j["verdict"] == "UNVERIFIED")
# production / non-staging URLs are refused outright
rc, j, _, _ = gate("staging_smoke.py", "check", "--repo", "fakeapp", "--base-url", "https://billwatch-production.up.railway.app", "--config", CFGP, "--no-record", env_extra=SENV)
ok("REFUSES a production URL (no request is made)", j and j["verdict"] == "UNVERIFIED" and "REFUSING" in j["summary"], (j or {}).get("summary"))
rc, j, _, _ = gate("staging_smoke.py", "check", "--repo", "fakeapp", "--base-url", BASE, "--config", CFGP, "--no-record", env_extra=["T_EMAIL=a@b.c", "T_PW=zzzzzzzz"])
ok("localhost refused unless QA_SMOKE_ALLOW_LOCAL=1 (tests only)", j and "REFUSING" in j["summary"])

# N/A by design: repo without a login mechanism -> FLAG (PARTIAL), and works with a token
reset()
rc, j, _, _ = smoke("fakeapp2")
ok("no-login repo (gitlark shape): FLAG PARTIAL, N/A steps listed - NOT a silent PASS", j and j["verdict"] == "FLAG" and "PARTIAL" in j["summary"] and step(j, "write_read")["status"] == "na", (j or {}).get("summary"))
reset()
rc, j, out, err = smoke("fakeapp2", env=["T_TOKEN=TOKEN-ABC-123"])
ok("same repo with a staging token: PATCH write + read-back -> PASS", j and j["verdict"] == "PASS", (j or {}).get("summary"))
ok("token from env never printed", "TOKEN-ABC-123" not in out + err)
reset(write="drop")
rc, j, _, _ = smoke("fakeapp2", env=["T_TOKEN=TOKEN-ABC-123"])
ok("NEG PATCH not persisted -> FAIL", j and j["verdict"] == "FAIL")

# credentials: auto-register + creds file (0600), then reuse
os.makedirs(os.path.join(STATE, "qa_creds"), exist_ok=True)
os.environ["OVN_DIR"] = OVN
ssm_creds = {"email": "saved@example.test", "password": "saved-pw-XYZ"}
ssm.save_creds("unit", ssm_creds["email"], ssm_creds["password"])
st_ = os.stat(os.path.join(STATE, "qa_creds", "unit.json"))
ok("creds file saved with mode 0600", (st_.st_mode & 0o777) == 0o600, oct(st_.st_mode))
os.environ["OVN_DIR"] = OVN
e, p_, src = ssm.resolve_creds("zzz", {"file": "unit"})
ok("resolve_creds reads the state/qa_creds file", (e, p_, src) == ("saved@example.test", "saved-pw-XYZ", "file"))
os.environ["QA_X_EMAIL"], os.environ["QA_X_PW"] = "env@example.test", "env-pw"
ok("resolve_creds: env beats file", ssm.resolve_creds("zzz", {"email_env": "QA_X_EMAIL", "password_env": "QA_X_PW", "file": "unit"})[2] == "env")
# repo_default parsing from a real git repo (janitor-style defaults), read via `git show`
oj, wj = base_repo("janitorrepo")
os.makedirs(os.path.join(wj, "scripts"))
open(os.path.join(wj, "scripts", "e2e_janitor.py"), "w").write('X = {"premium": ("stg@example.test", os.getenv("E2E_STAGING_PREMIUM_PASSWORD", "Default-Pw-1")), "free": ("f@example.test", os.getenv("E2E_STAGING_FREE_PASSWORD", "Free-Pw-2"))}\n')
sh(wj, "git", "add", "scripts")
sh(wj, "git", "commit", "-q", "-m", "janitor")
publish(wj)
os.environ["OVN_REPOS_DIR"] = REPOS
e, p_, src = ssm.resolve_creds("janitorrepo", {"repo_default": {"git_path": "scripts/e2e_janitor.py", "password_env_name": "E2E_STAGING_PREMIUM_PASSWORD"}})
ok("repo_default: email + password parsed from the repo's janitor via git show", (e, p_) == ("stg@example.test", "Default-Pw-1") and src == "repo_default", (e, src))

# real config sanity (static)
real = json.load(open(os.path.join(QA, "staging_smoke.conf")))
for r in ("billwatch", "gitlark", "iptv_apps"):
    c = real["repos"].get(r, {})
    ok("real config %s has health/login/business/write_read/frontend/cors" % r, all(k in c for k in ("health", "login", "business", "write_read", "frontend", "cors")))
txt = open(os.path.join(QA, "staging_smoke.conf")).read()
ok("real config contains no password-looking values", "Pass" not in txt and "Test-2026" not in txt and "Staging-" not in txt)

ok("is_staging: Railway staging host accepted", ssm.is_staging("https://billwatch-staging.up.railway.app"))
ok("is_staging: arbitrary host containing 'staging' REFUSED (creds would be sent there)", not ssm.is_staging("https://staging.evil.example") and not ssm.is_staging("https://x-staging.up.railway.app.evil.example"))
ok("is_staging: production Railway host refused", not ssm.is_staging("https://billwatch-production.up.railway.app"))
rc, j, _, _ = smoke("fakeapp", base="https://staging.evil.example")
ok("smoke entry point refuses https://staging.evil.example before any request", j and j["verdict"] == "UNVERIFIED" and "REFUSING" in j["summary"], (j or {}).get("summary"))

srv.shutdown()
shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
