#!/usr/bin/env python3
"""scripts/ovn_failure_ack_candidates.py (qacov B13): DRY-RUN list of failure clusters that look fixed by a shipped commit. Fixture: a temp git repo with commits at controlled
dates + a failure_clusters.json. Pins: only 'new' clusters that stopped recurring (quiet >= N days) AND have a fix/feat commit whose SUBJECT names the family inside the date
window are listed; docs/chore commits and body-only mentions are not evidence; landed-without-commit is 'investigate', never a candidate; the registry file is byte-identical
afterwards (no write path exists). Each rule is also run against a MUTANT of the tool and must fail there."""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.path.join(HERE, "..", "ovn_failure_ack_candidates.py"))
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="ackcand-"))
NOW = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None, microsecond=0)


def iso(days_ago):
    return (NOW - datetime.timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")


try:
    repo = os.path.join(T, "repo")
    os.makedirs(repo)
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

    def git(*a, **kw):
        return subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True, env=dict(env, **kw.get("env", {})))
    git("init", "-q")

    def commit(days_ago, msg):
        d = iso(days_ago)
        open(os.path.join(repo, "f.txt"), "a").write(msg + "\n")
        git("add", "-A")
        r = git("commit", "-q", "-m", msg, env={"GIT_AUTHOR_DATE": d, "GIT_COMMITTER_DATE": d})
        assert r.returncode == 0, r.stderr
        return git("rev-parse", "--short", "HEAD").stdout.strip()
    h_old = commit(40, "fix(runner): hunk failed to apply is retried (too old, before first_seen)")
    h_hunk = commit(12, "fix(aider): hunk failed to apply - normalise the search block")
    h_docs = commit(11, "docs(queue): notes about the hunk failed to apply problem")
    h_body = commit(9.5, "fix(queue): unrelated change\n\nmentions flail only in the body")
    h_flail = commit(9, "fix(runner): flail detector counts a no-usable-change attempt")
    h_late = commit(1, "fix(runner): hunk failed to apply again (newer than last_seen + 3d window)")
    h_cap = commit(10, "fix(stage-runner): escalate a capstone regression-check item")
    h_recent = commit(2.5, "fix(planner): decomposition splits the item into steps")

    def cl(first, last, count=5, status="new"):
        return {"count": count, "first_seen": iso(first), "last_seen": iso(last), "status": status, "fix_commit": None, "generator_addressed": None, "sample_item_hashes": []}
    reg = {
        "r1::aider:hunk-failed-to-apply": cl(30, 11),                  # quiet 11d, window [29d..8d]: h_hunk fits (12d ago), h_old (40d) is before first_seen, h_late (1d) is after the window
        "r1::pipeline:flail: the model attempted it": cl(30, 9),       # flail subject commit at 9d
        "r2::pipeline:flail: the model attempted it": cl(30, 0.2),     # still recurring -> not a candidate
        "r3::pipeline:decompose: could not split": cl(30, 2),          # last seen 2 days ago (< 7 quiet days) with a matching commit at 2.5d: recurring, not a candidate
        "r1::pipeline:capstone: regression check": cl(20, 9),          # capstone at 10d
        "r1::pipeline:capstone: regression check (variant)": cl(20, 9),  # its signature CONTAINS the one above: `--ack r1 <short>` matches both -> ambiguous
        "r1::landed-without-commit": cl(20, 9, 87),                    # investigate, never a candidate
        "r1::some:unknown-signature": cl(20, 9),                       # no family
        "r1::pipeline:decompose: could not split": cl(20, 9),          # family but no commit inside ITS window ([10d..6d] ago; the planner commit is at 2.5d)
        "r1::pipeline:residue: leftovers": cl(20, 9, status="fixed"),  # already fixed
    }
    sd = os.path.join(T, "state")
    os.makedirs(sd)
    regf = os.path.join(sd, "failure_clusters.json")
    json.dump(reg, open(regf, "w"))
    before = open(regf, "rb").read()

    def run(tool=TOOL, *extra):
        r = subprocess.run([sys.executable, tool, sd, "--repo", repo, "--json"] + list(extra), capture_output=True, text=True, timeout=120)
        try:
            return json.loads(r.stdout), r
        except ValueError:
            return None, r
    out, r = run()
    ok("exits 0 and prints JSON", out is not None and r.returncode == 0, (r.stdout[:200], r.stderr[:200]))
    by = {c["key"]: c for c in out["candidates"]}
    hashes = lambda k: [c[0] for c in by[k]["commits"]]
    ok("hunk cluster: exactly the in-window fix commit (not the too-old one, not the docs commit, not the commit past the window)", hashes("r1::aider:hunk-failed-to-apply") == [h_hunk], hashes("r1::aider:hunk-failed-to-apply") if "r1::aider:hunk-failed-to-apply" in by else by)
    ok("flail cluster: the commit whose SUBJECT names it, not the one that only mentions flail in its body", hashes("r1::pipeline:flail: the model attempted it") == [h_flail])
    ok("capstone cluster is a candidate with its commit", hashes("r1::pipeline:capstone: regression check") == [h_cap])
    ok("clusters that are still recurring (last seen 5 hours / 2 days ago) are NOT candidates", "r2::pipeline:flail: the model attempted it" not in by and "r3::pipeline:decompose: could not split" not in by)
    ok("landed-without-commit is listed as investigate and never as a candidate", "r1::landed-without-commit" not in by and [c["key"] for c in out["investigate"]] == ["r1::landed-without-commit"])
    ok("unknown signature, no-commit family and already-fixed clusters are skipped, with counts", out["skipped"] == {"already_fixed": 1, "recurring": 2, "no_family": 1, "no_commit": 1, "bad_dates": 0}, out["skipped"])
    ok("DRY RUN: the registry file is byte-identical afterwards and the tool has no --apply", open(regf, "rb").read() == before and "--apply" not in open(TOOL).read().replace('no --apply', '').replace("`--apply`", ""))
    out2, r2 = run(TOOL, "--quiet-days", "0.1")
    by2 = {c["key"]: c for c in out2["candidates"]}
    ok("--quiet-days 0.1 admits the 2-day-old cluster with its in-window commit (and still not the 5-hour-old one, whose commits are all before its last sighting)",
       [c[0] for c in by2.get("r3::pipeline:decompose: could not split", {"commits": []})["commits"]] == [h_recent] and "r2::pipeline:flail: the model attempted it" not in by2)
    txt = subprocess.run([sys.executable, TOOL, sd, "--repo", repo, "--commands"], capture_output=True, text=True, timeout=120).stdout
    ok("--commands prints the existing --ack command with the FULL signature (unsure; the human decides) for the first commit",
       re.search(r"ovn_failure_triage\.py --ack r1 aider:hunk-failed-to-apply --commit %s --generator-addressed unsure$" % h_hunk, txt, re.M) is not None, txt[-600:])
    ok("a signature with spaces is shell-quoted whole (not cut to 60 characters, no double-quote expansion)",
       "--ack r1 'pipeline:flail: the model attempted it' --commit %s " % h_flail in txt, txt[-600:])
    ok("NO printed command carries --yes (every ack stays an interactive confirmation)", "--yes" not in txt and "--ack" in txt, txt[-400:])
    ok("an ambiguous signature (another cluster contains it) gets an AMBIGUOUS comment, not a command that cmd_ack would refuse",
       "AMBIGUOUS: 2 clusters of r1" in txt and "--ack r1 'pipeline:capstone: regression check' " not in txt and "--ack r1 'pipeline:capstone: regression check (variant)' --commit %s " % h_cap in txt, txt[-900:])
    ok("the output is labelled as hints, not evidence", "HINTS" in txt and "not proof" in txt)
    ok("--commands never executes an ack (registry still identical)", open(regf, "rb").read() == before)
    # unreadable registry: reported, not a crash
    sd2 = os.path.join(T, "empty"); os.makedirs(sd2)
    r3 = subprocess.run([sys.executable, TOOL, sd2, "--repo", repo, "--json"], capture_output=True, text=True, timeout=60)
    ok("missing registry: clean report (exit 0, registry_unreadable counted)", r3.returncode == 0 and json.loads(r3.stdout)["skipped"].get("registry_unreadable") == 1, r3.stderr[:200])

    # ---- mutants: each rule broken once; the matching assertion must fail
    src = open(TOOL).read()

    def mutant(name, old, new):
        assert src.count(old) == 1, (name, src.count(old))
        p = os.path.join(T, "mut_%s.py" % name)
        open(p, "w").write(src.replace(old, new))
        return p
    m = mutant("yes", '--generator-addressed unsure" % (', '--generator-addressed unsure --yes" % (')
    tx = subprocess.run([sys.executable, m, sd, "--repo", repo, "--commands"], capture_output=True, text=True, timeout=120).stdout
    ok("MUTANT (--yes appended to the printed command): the no---yes assertion bites", "--yes" in tx)
    m = mutant("ambig", 'if c.get("ack_matches", 1) != 1:', "if False:")
    tx = subprocess.run([sys.executable, m, sd, "--repo", repo, "--commands"], capture_output=True, text=True, timeout=120).stdout
    ok("MUTANT (ambiguity check removed): the ambiguous capstone signature gets a command again - the AMBIGUOUS assertion bites", "--ack r1 'pipeline:capstone: regression check' " in tx and "AMBIGUOUS" not in tx)
    m = mutant("trunc", "shlex.quote(c[\"signature\"])", "shlex.quote(c[\"signature\"][:20])")
    tx = subprocess.run([sys.executable, m, sd, "--repo", repo, "--commands"], capture_output=True, text=True, timeout=120).stdout
    ok("MUTANT (signature cut short again): the full-signature assertion bites", "--ack r1 'pipeline:flail: the model attempted it' --commit %s " % h_flail not in tx)
    m = mutant("quiet", "if quiet < quiet_days:", "if False:")
    o, _ = run(m)
    ok("MUTANT (quiet filter removed): the still-recurring r3 cluster becomes a candidate - the quiet assertion bites", "r3::pipeline:decompose: could not split" in {c["key"] for c in o["candidates"]})
    m = mutant("subject", "and re.search(grep, p[2], re.I)", "and True")
    o, _ = run(m)
    ok("MUTANT (body-only mentions accepted): the flail cluster picks up the body-only commit - the subject assertion bites", h_body in [c[0] for c in {c["key"]: c for c in o["candidates"]}.get("r1::pipeline:flail: the model attempted it", {"commits": []})["commits"]])
    m = mutant("type", "FIX_TYPES.match(p[2]) and ", "")
    o, _ = run(m)
    ok("MUTANT (docs/chore accepted): the docs commit shows up for the hunk cluster - the type assertion bites", h_docs in [c[0] for c in {c["key"]: c for c in o["candidates"]}.get("r1::aider:hunk-failed-to-apply", {"commits": []})["commits"]])
    m = mutant("window", "until = last + datetime.timedelta(days=after_days)", "until = last + datetime.timedelta(days=3650)")
    o, _ = run(m)
    ok("MUTANT (no upper date bound): the commit past the window is accepted - the window assertion bites", h_late in [c[0] for c in {c["key"]: c for c in o["candidates"]}.get("r1::aider:hunk-failed-to-apply", {"commits": []})["commits"]])
    m = mutant("invest", "        if grep is None:\n            invest.append(row)\n            continue\n", "")
    o, _ = run(m)
    ok("MUTANT (investigate family treated like the others): landed-without-commit disappears from 'investigate' - the investigate assertion bites", o is None or [c["key"] for c in o["investigate"]] != ["r1::landed-without-commit"] or "r1::landed-without-commit" in {c["key"] for c in o["candidates"]})
finally:
    shutil.rmtree(T, ignore_errors=True)
print("  %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
