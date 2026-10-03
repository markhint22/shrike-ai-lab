#!/usr/bin/env python3
"""staging_check.py - gate S10b: does the STAGING backend actually serve the release-candidate SHA?  (read-only, shadow)

  python3 qa/staging_check.py check  --repo <name> [--sha <sha> | --release-plan] [--provider auto|railway|file|http] [--no-record]
  python3 qa/staging_check.py export --repo <name> [--env staging|production]
                                                                # Mac only: writes state/staging_deploys/<repo>.json (or prod_deploys/ for --env production, read by
                                                                # promote_postcheck.py) for the box to read

Evidence providers (tried in this order with --provider auto; the first that yields a deployment list wins):
  http    GET <staging>/health (+ / ) and look for a commit field (commit|commit_sha|git_sha|sha|release). None of our backends
          expose one today (see README: add `"commit": os.getenv("RAILWAY_GIT_COMMIT_SHA")` to each /health) - the provider is
          there so that adding the field makes this gate need no CLI at all.
  railway `railway deployment list --json --environment staging --service <id>` from an ISOLATED cwd after
          `railway link --project <id> --environment staging --service <id>` (account login; the same model deploy_watch.sh uses).
          Needs the Railway CLI + login: present on the Mac, NOT on the GPU box.
  file    state/staging_deploys/<repo>.json written by `export` on the Mac and copied to the box (rsync/scp). Stale (>QA_STAGING_MAX_AGE_S,
          default 1800s) or missing => UNVERIFIED.

Relations (candidate C vs the SUCCESSFUL latest staging deploy S):
  MATCH            S == C
  MATCH_SUPERSET   C is an ancestor of S (staging runs C plus newer develop commits: smoke on S covers C; PASS but noted)
  BUILDING         the latest deploy (of the candidate or a descendant) is still in progress: verdict UNVERIFIED, promote_gate HOLDS (enforce)
  MISMATCH_BEHIND  S is an ancestor of C (staging has not deployed the candidate yet)
  MISMATCH_DIVERGED / MISMATCH_FAILED (latest deploy FAILED/CRASHED: staging is silently serving an OLDER build - the billwatch 2026-09 incident)
  UNVERIFIED       no evidence, deploy still building, commit unknown to the local clone, ...
Verdict: MATCH/MATCH_SUPERSET -> PASS, MISMATCH_* -> FAIL (shadow: logged, never blocks), UNVERIFIED -> UNVERIFIED. Exit 0 always except
enforce+FAIL+--enforce-exit. No tokens are ever printed; only deployment ids/status/commit hashes appear in output.
"""
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "staging_check"

# project/service ids are public identifiers (same ones deploy_watch.sh hardcodes), not secrets.
RAILWAY = {
    "billwatch": {"project": "38d377fc-d005-41fc-9675-e84659ef7ce1", "service": "31f8e4dd-5827-48a8-9d36-d09dc6ce64c2"},
    "iptv_apps": {"project": "5adaa84c-5dd0-40ee-8265-deb5870ee87e", "service": "58dcc554-8c73-4fa1-8c0f-653de8f31784"},
    "gitlark": {"project": "a6a9ae6b-8df9-4d05-8169-25bf13d92293", "service": "de12ff53-2434-4b7e-8a32-eb77e02c14dd"},
}
IN_PROGRESS = {"BUILDING", "DEPLOYING", "INITIALIZING", "QUEUED", "WAITING", "NEEDS_APPROVAL"}
DEAD = {"FAILED", "CRASHED"}
IGNORED = {"REMOVED", "SKIPPED"}  # superseded builds - never "the latest"
COMMIT_KEYS = ("commit", "commit_sha", "git_sha", "git_commit", "sha", "release")


# ---------------------------------------------------------------- pure decision logic (unit-tested)
def normalize(deploys):
    """Accept railway json list -> [{id,status,commit,created,branch}] newest first, superseded builds dropped."""
    out = []
    for d in deploys or []:
        if not isinstance(d, dict):
            continue
        meta = d.get("meta") or {}
        out.append({"id": str(d.get("id", ""))[:8], "status": str(d.get("status", "")).upper(), "created": d.get("createdAt", ""),
                    "commit": (meta.get("commitHash") or d.get("commit") or "").lower(), "branch": meta.get("branch") or d.get("branch") or ""})
    out = [d for d in out if d["status"] not in IGNORED]
    out.sort(key=lambda d: d["created"], reverse=True)
    return out


def decide(cand, deploys, is_ancestor):
    """cand: full candidate sha. deploys: normalize() output. is_ancestor(a, b) -> True/False/None(unknown).
    Returns (relation, reason, served_sha)."""
    if not deploys:
        return "UNVERIFIED", "no staging deployments found", ""
    latest = deploys[0]
    if latest["status"] in IN_PROGRESS:
        # 2026-10-03: a deploy of the candidate (or a descendant) still in flight is NOT "unknown": the healthy staging smoke would hit the OLD build, so
        # promote_gate holds on BUILDING. Any other in-flight commit (unknown / unrelated) stays plain UNVERIFIED (proceeds).
        c = latest["commit"]
        if re.fullmatch(r"[0-9a-f]{7,40}", c or "") and re.fullmatch(r"[0-9a-f]{7,40}", cand.lower()):
            cl = cand.lower()
            if c == cl or c.startswith(cl) or cl.startswith(c) or is_ancestor(cl, c) is True:
                return "BUILDING", "latest staging deploy %s of the candidate (or a descendant) is %s - staging still serves the previous build" % (
                    latest["id"], latest["status"]), c
        return "UNVERIFIED", "latest staging deploy %s is %s (retry later)" % (latest["id"], latest["status"]), latest["commit"]
    if latest["status"] in DEAD:
        ok = next((d for d in deploys if d["status"] == "SUCCESS"), None)
        served = ok["commit"] if ok else ""
        return "MISMATCH_FAILED", "latest staging deploy %s (%s) %s - staging is serving %s" % (
            latest["id"], latest["commit"][:10], latest["status"], (served[:10] or "nothing")), served
    if latest["status"] != "SUCCESS":
        return "UNVERIFIED", "latest staging deploy %s has status %s" % (latest["id"], latest["status"]), latest["commit"]
    s = latest["commit"]
    if not s:
        return "UNVERIFIED", "deployment %s has no commit hash" % latest["id"], ""
    if not re.fullmatch(r"[0-9a-f]{7,40}", s):
        return "UNVERIFIED", "staging commit %r of deployment %s is not a usable hex hash (>=7 chars); cannot compare" % (s[:12], latest["id"]), ""
    if not re.fullmatch(r"[0-9a-f]{7,40}", cand.lower()):
        return "UNVERIFIED", "candidate %r is not a usable hex hash" % cand[:12], s
    cand = cand.lower()
    if s == cand or s.startswith(cand) or cand.startswith(s):
        return "MATCH", "staging serves the candidate", s
    anc_c_in_s = is_ancestor(cand, s)
    if anc_c_in_s is None:
        return "UNVERIFIED", "staging commit %s is unknown to the local clone (fetch needed)" % s[:10], s
    if anc_c_in_s:
        return "MATCH_SUPERSET", "staging serves %s which contains the candidate" % s[:10], s
    if is_ancestor(s, cand):
        return "MISMATCH_BEHIND", "staging serves %s, BEHIND the candidate (not deployed yet)" % s[:10], s
    return "MISMATCH_DIVERGED", "staging serves %s which does not contain the candidate and is not an ancestor of it" % s[:10], s


VERDICT_OF = {"MATCH": "PASS", "MATCH_SUPERSET": "PASS", "MISMATCH_BEHIND": "FAIL", "MISMATCH_DIVERGED": "FAIL", "MISMATCH_FAILED": "FAIL", "BUILDING": "UNVERIFIED", "UNVERIFIED": "UNVERIFIED"}


# ---------------------------------------------------------------- providers
def staging_url(repo):
    try:
        with open(os.path.join(qc.state_dir(), "staging_url_" + repo)) as f:
            return f.read().split()[0].rstrip("/")
    except (OSError, IndexError):
        return ""


def provider_http(repo):
    url = staging_url(repo)
    if not url:
        return None, "no staging url"
    for path in ("/health", "/"):
        try:
            r = urllib.request.urlopen(urllib.request.Request(url + path, headers={"User-Agent": "qa-staging-check"}), timeout=15)
            j = json.loads(r.read().decode("utf-8", "replace"))
        except Exception:  # noqa: BLE001
            continue
        if isinstance(j, dict):
            for k in COMMIT_KEYS:
                v = j.get(k)
                if isinstance(v, str) and re.fullmatch(r"[0-9a-f]{7,40}", v.lower()):
                    return [{"id": "http", "status": "SUCCESS", "createdAt": "9999", "commit": v.lower(), "branch": ""}], "http %s%s field %s" % (url, path, k)
    return None, "health exposes no commit field"


def railway_fetch(repo, env="staging"):
    """Returns (raw_list|None, note). Isolated cwd so we never disturb a human's `railway link` state.
    env: "staging" (the gate's evidence) or "production" (promote_postcheck.py: did the PROMOTED sha deploy?). Read-only either way."""
    cfg = RAILWAY.get(repo)
    if not cfg:
        return None, "no railway config for %s" % repo
    if not shutil.which("railway"):
        return None, "railway CLI not installed on this host"
    cwd = tempfile.mkdtemp(prefix="qa-railway-")
    try:
        rc, out, err = qc.run(["railway", "link", "--project", cfg["project"], "--environment", env, "--service", cfg["service"]],
                              cwd=cwd, timeout=60, polite=False)
        if rc != 0:
            return None, "railway link failed (rc=%s; login expired?)" % rc
        rc, out, err = qc.run(["railway", "deployment", "list", "--json", "--environment", env, "--service", cfg["service"], "--limit", "8"],
                              cwd=cwd, timeout=60, polite=False)
        if rc != 0 or "[" not in out:
            return None, "railway deployment list failed (rc=%s)" % rc
        try:
            return json.loads(out[out.index("["):]), "railway cli"
        except ValueError:
            return None, "railway output not JSON"
    finally:
        shutil.rmtree(cwd, ignore_errors=True)


def deploys_file(repo, kind="staging_deploys"):
    return os.path.join(qc.state_dir(), kind, repo + ".json")


def has_staging(repo):
    """True when the repo has a staging backend we can have evidence about (railway config, a staging url, or an exported deploy list)."""
    return repo in RAILWAY or bool(staging_url(repo)) or os.path.exists(deploys_file(repo))


def file_evidence_state(repo, kind="staging_deploys"):
    """(state, age_s) of the exported deploy list: ok | stale | missing. A corrupt / empty / unreadable file is "missing" (unusable evidence).
    promote_gate fails CLOSED (enforce mode) on stale/missing for a repo that has staging; everything else about this gate fails open."""
    try:
        with open(deploys_file(repo, kind)) as f:
            j = json.load(f)
        age = time.time() - float(j.get("fetched_at", 0))
        if not j.get("deployments"):
            return "missing", age
        return ("ok" if age <= float(os.environ.get("QA_STAGING_MAX_AGE_S", "1800")) else "stale"), age
    except (OSError, ValueError, TypeError, AttributeError):
        return "missing", -1.0


def provider_file(repo):
    try:
        with open(deploys_file(repo)) as f:
            j = json.load(f)
        age = time.time() - float(j.get("fetched_at", 0))
        maxage = float(os.environ.get("QA_STAGING_MAX_AGE_S", "1800"))
        if age > maxage:
            return None, "exported deploy list is stale (%ds old, max %ds)" % (age, maxage)
        return j.get("deployments"), "exported file (%ds old)" % age
    except (OSError, ValueError, TypeError):
        return None, "no exported deploy list"


def gather(repo, provider):
    notes = []
    order = ["http", "railway", "file"] if provider == "auto" else [provider]
    for p in order:
        if p == "http":
            d, n = provider_http(repo)
        elif p == "railway":
            raw, n = railway_fetch(repo)
            d = raw
        elif p == "file":
            d, n = provider_file(repo)
        else:
            d, n = None, "unknown provider %s" % p
        notes.append("%s: %s" % (p, n))
        if d:
            return normalize(d), p, notes
    return [], "none", notes


# ---------------------------------------------------------------- commands
def args_of(argv):
    o = {"repo": "", "sha": "", "provider": "auto", "base": "", "head": "", "env": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--release-plan":
            o["release_plan"] = True
            i += 1
        elif a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def candidate_sha(repo, o):
    if o["sha"]:
        return o["sha"], ""
    if o.get("head") and o.get("release_plan") is None:
        return o["head"], ""
    import release_candidate as rc  # same dir
    plan, err = rc.compute_plan(repo, {"main": "origin/main", "develop": "origin/develop", "date": ""})
    if err or not plan:
        return "", (err or {}).get("summary", "release plan failed")
    return plan["candidate"], ""


def cmd_check(argv):
    o = args_of(argv)
    repo = o["repo"]
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: check --repo <name> [--sha S]")
    rd = qc.repo_dir(repo)
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "no clone for repo %s" % repo)
    if repo not in RAILWAY and not staging_url(repo) and not os.path.exists(deploys_file(repo)):
        return qc.verdict("NA", GATE, repo, "?", "repo %s has no staging backend (no railway config, no state/staging_url_%s)" % (repo, repo))
    sha, why = candidate_sha(repo, o)
    if not sha:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "no candidate sha: " + why)
    rcv, full, _ = qc.git(rd, "rev-parse", "--verify", "-q", sha + "^{commit}")
    if rcv != 0:
        return qc.verdict("UNVERIFIED", GATE, repo, sha[:10], "candidate %s unknown to the local clone" % sha[:10])
    full = full.strip()
    deploys, prov, notes = gather(repo, o["provider"])
    if not deploys:
        return qc.verdict("UNVERIFIED", GATE, repo, full[:10], "no staging deployment evidence (" + "; ".join(notes)[:260] + ")",
                          {"candidate": full, "providers": notes})

    def is_anc(a, b):
        if qc.git(rd, "cat-file", "-e", a + "^{commit}")[0] != 0 or qc.git(rd, "cat-file", "-e", b + "^{commit}")[0] != 0:
            return None
        return qc.git(rd, "merge-base", "--is-ancestor", a, b)[0] == 0

    rel, reason, served = decide(full, deploys, is_anc)
    det = {"relation": rel, "candidate": full, "staging_commit": served, "provider": prov, "providers": notes,
           "latest": deploys[0] if deploys else None, "recent": [{"id": d["id"], "status": d["status"], "commit": d["commit"][:10]} for d in deploys[:5]]}
    return qc.verdict(VERDICT_OF[rel], GATE, repo, full[:10], "%s: %s" % (rel, reason), det)


def cmd_export(argv):
    o = args_of(argv)
    repo = o["repo"]
    env = o.get("env") or "staging"
    if env not in ("staging", "production"):
        return qc.verdict("UNVERIFIED", GATE, repo or "?", "export", "bad --env %r (staging|production)" % env)
    raw, note = railway_fetch(repo, env)
    if not raw:
        return qc.verdict("UNVERIFIED", GATE, repo or "?", "export", "could not fetch railway deployments: " + note)
    slim = [{"id": d.get("id"), "status": d.get("status"), "createdAt": d.get("createdAt"),
             "meta": {"commitHash": (d.get("meta") or {}).get("commitHash"), "branch": (d.get("meta") or {}).get("branch")}} for d in raw if isinstance(d, dict)]
    path = deploys_file(repo, "staging_deploys" if env == "staging" else "prod_deploys")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"repo": repo, "fetched_at": time.time(), "deployments": slim}, f)
    os.replace(tmp, path)  # atomic
    return qc.verdict("NA", GATE, repo, "export", "exported %d deployments to %s" % (len(slim), path), {"count": len(slim)})


def main(argv):
    if not argv or argv[0] not in ("check", "export"):
        print(__doc__)
        return 2
    return qc.main_guard(GATE, cmd_export if argv[0] == "export" else cmd_check, argv[1:] + (["--no-record"] if argv[0] == "export" else []))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
