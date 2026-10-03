#!/usr/bin/env python3
"""prod_alembic_check.py - promote-time check: is PROD's alembic revision a STRICT ANCESTOR of the candidate's migration head?  (read-only, SHADOW)

  python3 qa/prod_alembic_check.py check  --repo <name> [--sha <sha>] [--no-record]
  python3 qa/prod_alembic_check.py record --repo <name> --revision <rev>     # operator, on a host with READ-ONLY prod access: writes the snapshot

Why (2026-10-03): a fleet-landed docstring-only migration (0011_..., no `revision =`) reached prod. Nothing compared what prod's database is at
with what the release is about to apply. This gate parses alembic/versions/*.py of the candidate commit (git only, nothing is executed, no DB),
builds the revision graph and compares it with prod's current revision.

Read-only prod source (the ONLY one; no DB credential is ever read or printed here):
  state/prod_alembic/<repo>.json = {"revision": "<rev>", "fetched_at": <epoch>}   written by `record` from `alembic current` / SELECT version_num
  run against a replica or a read-only role (same operator model as qa/prodshape.py collect). Missing / corrupt / older than
  QA_PROD_ALEMBIC_MAX_AGE_S (default 86400) => the prod half is UNVERIFIED (never a block).

Verdicts: PASS  prod == head (nothing pending) or prod is a strict ancestor of the single head (N pending migrations)
          FAIL  a migration file has no revision id (the 0011 incident) | several heads | prod's revision is not in the candidate's history (prod ahead / diverged)
          UNVERIFIED  no prod snapshot / stale / candidate unknown | NA  the repo has no alembic migrations
The structural FAILs (no revision, several heads) need no prod snapshot. SHADOW: promote_to_prod.sh logs it and writes ONE alerts.log WARN per
(repo, sha); it never blocks a promote.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "prod_alembic"
VERSIONS_RE = re.compile(r"(^|/)(alembic|migrations)/versions/[^/]+\.py$")
REV_RE = re.compile(r"^[ \t]*revision[ \t]*(?::[^=\n]+)?=[ \t]*['\"]([^'\"]+)['\"]", re.M)
DOWN_RE = re.compile(r"^[ \t]*down_revision[ \t]*(?::[^=\n]+)?=[ \t]*(None|['\"][^'\"]+['\"]|\([^)]*\)|\[[^\]]*\])", re.M)
Q_RE = re.compile(r"['\"]([^'\"]+)['\"]")


def snapshot_path(repo):
    return os.path.join(qc.state_dir(), "prod_alembic", repo + ".json")


# ---------------------------------------------------------------- pure logic (unit-tested)
def parse_versions(files):
    """files: {path: text} -> (revs {rev: [down,...]}, bad [paths with no usable `revision =`])."""
    revs, bad = {}, []
    for path, text in sorted(files.items()):
        m = REV_RE.search(text or "")
        if not m:
            bad.append(path)
            continue
        d = DOWN_RE.search(text)
        downs = [] if (not d or d.group(1) == "None") else Q_RE.findall(d.group(1))
        revs[m.group(1)] = downs
    return revs, bad


def heads_of(revs):
    seen = {d for ds in revs.values() for d in ds}
    return sorted(r for r in revs if r not in seen)


def ancestors(rev, revs):
    out, stack = set(), list(revs.get(rev, []))
    while stack:
        r = stack.pop()
        if r in out:
            continue
        out.add(r)
        stack.extend(revs.get(r, []))
    return out


def decide(prod_rev, revs, bad):
    """-> (verdict, reason). prod_rev None = no usable prod snapshot."""
    if not revs and not bad:
        return "NA", "no alembic migrations"
    if bad:
        return "FAIL", "migration file(s) without a revision id (alembic ignores them; the 0011 incident): %s" % ", ".join(os.path.basename(b) for b in bad[:4])
    hs = heads_of(revs)
    if len(hs) != 1:
        return "FAIL", "%d alembic heads in the candidate (%s) - upgrade head would refuse" % (len(hs), ", ".join(hs[:4]) or "none")
    head = hs[0]
    if not prod_rev:
        return "UNVERIFIED", "no read-only prod alembic snapshot (candidate head %s)" % head
    if prod_rev == head:
        return "PASS", "prod is already at the candidate head %s (no pending migrations)" % head
    if prod_rev in ancestors(head, revs):
        n = len([r for r in ancestors(head, revs) | {head} if prod_rev in ancestors(r, revs)])
        return "PASS", "prod revision %s is a strict ancestor of head %s (%d pending migration(s))" % (prod_rev, head, n)
    return "FAIL", "prod revision %s is NOT in the candidate's history (head %s): prod is ahead of / diverged from this release" % (prod_rev, head)


# ---------------------------------------------------------------- IO
def read_prod_rev(repo):
    """-> (rev|None, note). Never raises."""
    try:
        with open(snapshot_path(repo)) as f:
            j = json.load(f)
        rev = str(j.get("revision") or "").strip()
        age = time.time() - float(j.get("fetched_at", 0))
        if not rev:
            return None, "prod alembic snapshot has no revision"
        mx = float(os.environ.get("QA_PROD_ALEMBIC_MAX_AGE_S", "86400"))
        if age > mx:
            return None, "prod alembic snapshot is stale (%ds old, max %ds)" % (age, mx)
        return rev, "snapshot %ds old" % age
    except (OSError, ValueError, TypeError, AttributeError):
        return None, "no prod alembic snapshot"


def load_files(rd, sha):
    rc, out, _ = qc.git(rd, "ls-tree", "-r", "--name-only", sha)
    if rc != 0:
        return None
    files = {}
    for p in out.split("\n"):
        if p and VERSIONS_RE.search(p) and not p.endswith("__init__.py"):
            rc2, txt, _ = qc.git(rd, "show", "%s:%s" % (sha, p))
            if rc2 == 0:
                files[p] = txt
    return files


def check_ref(repo, sha):
    """Library entry used by promote_gate: -> dict(verdict, summary)."""
    rd = qc.repo_dir(repo)
    if not rd:
        return {"verdict": "UNVERIFIED", "summary": "no clone for %s" % repo}
    files = load_files(rd, sha)
    if files is None:
        return {"verdict": "UNVERIFIED", "summary": "candidate %s unknown to the local clone" % sha[:10]}
    revs, bad = parse_versions(files)
    prod, note = read_prod_rev(repo)
    v, why = decide(prod, revs, bad)
    if v == "UNVERIFIED" and prod is None:
        why += " (%s)" % note
    return {"verdict": v, "summary": why}


def args_of(argv):
    o = {"repo": "", "sha": "", "revision": ""}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and argv[i][2:] in o and i + 1 < len(argv):
            o[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def cmd_check(argv):
    o = args_of(argv)
    repo = o["repo"]
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: check --repo <name> [--sha S]")
    rd = qc.repo_dir(repo)
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "no clone for repo %s" % repo)
    sha = o["sha"] or "origin/develop"
    rc, full, _ = qc.git(rd, "rev-parse", "--verify", "-q", sha + "^{commit}")
    if rc != 0:
        return qc.verdict("UNVERIFIED", GATE, repo, sha[:10], "candidate %s unknown to the local clone" % sha[:10])
    full = full.strip()
    r = check_ref(repo, full)
    return qc.verdict(r["verdict"], GATE, repo, full[:10], r["summary"], {"candidate": full})


def cmd_record(argv):
    o = args_of(argv)
    if not o["repo"] or not re.fullmatch(r"[A-Za-z0-9_.-]+", o["repo"]) or not re.fullmatch(r"[A-Za-z0-9_.-]+", o["revision"]):
        return qc.verdict("UNVERIFIED", GATE, o["repo"] or "?", "record", "usage: record --repo <name> --revision <alembic revision id>")
    path = snapshot_path(o["repo"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"repo": o["repo"], "revision": o["revision"], "fetched_at": time.time()}, f)
    os.replace(tmp, path)
    return qc.verdict("NA", GATE, o["repo"], "record", "recorded prod alembic revision %s" % o["revision"])


def main(argv):
    if not argv or argv[0] not in ("check", "record"):
        print(__doc__)
        return 2
    return qc.main_guard(GATE, cmd_record if argv[0] == "record" else cmd_check, argv[1:] + (["--no-record"] if argv[0] == "record" else []))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
