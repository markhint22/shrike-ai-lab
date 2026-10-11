#!/usr/bin/env python3
"""scripts/ovn_failure_ack_candidates.py - DRY-RUN list of failure clusters that look already fixed by a shipped commit (qacov B13, 2026-10-10).

state/failure_clusters.json had 264 clusters, 263 'new' and 1 'fixed': the Phase 6c/6d discipline (`ovn_failure_triage.py --ack ... --commit <hash> --generator-addressed ..`
after every real fix) was not followed for ten days, so the digest cannot tell a genuinely new signature from a permanently unacked one, and a regression can only fire for
the single fixed entry. This tool does the legwork of the one-time bulk ack WITHOUT doing it: it never writes the registry, it has no --apply. A human (or the lead) reads the
list, confirms each commit really fixes that cluster, and runs the printed `--ack` command (the existing, confirmed path).

usage: ovn_failure_ack_candidates.py [state_dir] [--repo <git dir>] [--quiet-days N] [--before-days N] [--after-days N] [--commands] [--json]
  state_dir       default $OVN_DIR/state (OVN_DIR default: parent of this scripts/ dir)
  --repo          the git repository whose history holds the fixes (default: the one containing this script; on the box ~/overnight-queue is one)
  --quiet-days    a cluster is a candidate only if it has not recurred for N days (default 7): a fix that worked stops the recurrences
  --after-days    a fix commit may be dated at most N days AFTER the cluster's last recurrence (default 3); it must be dated on/after the cluster's first_seen
  --before-days   ... and at most N days BEFORE the last recurrence (default 1: a commit a day before the last sighting can still be what stopped it; earlier ones did not)
  --commands      also print an `ovn_failure_triage.py --ack` command per candidate, with the FULL signature (generator-addressed = unsure; the human decides yes/no). It never
                  carries --yes: each ack stays an interactive confirmation that shows the matched cluster, so pasting a block cannot apply anything unreviewed. A signature that
                  another cluster of the same repo contains (cmd_ack would refuse it as ambiguous) gets a comment instead of a command. The commit list is a HINT (subject
                  matched a family regex inside a date window), not evidence that the commit fixed that cluster.
  --json          machine output

How a commit is matched to a cluster: the signature's FAMILY (table FAMILIES below: regex on the signature -> `git log -i -E --grep` terms). Commits are searched by subject/body
and limited to the date window above. Families that are NOT safe to bulk-ack are listed separately as 'investigate' (landed-without-commit: what it means operationally was never
verified). A cluster that is still recurring, already 'fixed', or has no family/commit is not a candidate. Exit 0 always (it is a report).
"""
import datetime
import json
import os
import re
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# (signature regex, git --grep ERE, note). First match wins. Terms are deliberately specific to the fix, not to the symptom's generic words.
FAMILIES = [
    (r"landed-without-commit", None, "investigate: 87 events, may be the landed-uncredited population or a phantom-landing counter; confirm against outcomes before any ack"),
    (r"hunk-failed-to-apply", r"hunk|failed to apply|search/replace", "aider edit-format failures"),
    (r"is-not-in-subpath", r"subpath|is not in the subpath", "aider path normalisation"),
    (r"build-gate", r"build[- ]gate|build[- ]break|compile gate|does not compile|would not load", "commit broke the build"),
    (r"flail", r"flail|no usable change|no-op", "model produced no usable change"),
    (r"decompose: could not split", r"decompos|planner", "planner/decomposition"),
    (r"scout: already done", r"already[- ]done|already[- ]satisfied|scout", "scout already-done handling"),
    (r"scout: made up a plan", r"made up|invent|ground(ed|ing)|names no real file", "scout plan grounding"),
    (r"capstone", r"capstone", "capstone regression check"),
    (r"migration-gate|migration|alembic", r"migration|alembic", "migration chain"),
    (r"residue", r"residue", "residue guard"),
    (r"tests-red", r"tests?[- ]red|test[- ]red|regression test|revert", "tests red after a change"),
    (r"staged: gave up", r"staged|escalat", "staged pipeline escalation"),
    (r"verify: failed, repair rounds", r"verify|repair round|fix-?up", "verify repair rounds"),
]


def parse_ts(s):
    try:
        return datetime.datetime.strptime(str(s)[:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def family_of(sig):
    for rx, grep, note in FAMILIES:
        if re.search(rx, sig):
            return rx, grep, note
    return None, None, ""


FIX_TYPES = re.compile(r"^(fix|feat|perf|refactor)(\([^)]*\))?!?:", re.I)


def git_commits(repo, grep, since, until, limit=5):
    """-> [(hash, iso date, subject)] of fix/feat/perf/refactor commits whose SUBJECT matches `grep` (ERE, case-insensitive; a term that only appears deep in the body
    or in a docs/chore/test commit is not evidence of a fix) dated within [since, until]."""
    cmd = ["git", "-C", repo, "log", "-i", "-E", "--grep=" + grep, "--since=" + since.strftime("%Y-%m-%dT%H:%M:%S") + "Z", "--until=" + until.strftime("%Y-%m-%dT%H:%M:%S") + "Z",
           "--format=%h%x09%aI%x09%s", "-n", "200"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for line in r.stdout.splitlines():
        p = line.split("\t", 2)
        if len(p) == 3 and FIX_TYPES.match(p[2]) and re.search(grep, p[2], re.I):
            out.append((p[0], p[1], p[2]))
    return out[:limit]


def ack_matches(reg, repo_name, sig):
    """How many clusters `ovn_failure_triage.py --ack <repo> <sig>` would match (cmd_ack: same repo prefix, case-insensitive substring of the key). 1 = unambiguous."""
    prefix, needle = repo_name + "::", sig.lower()
    return sum(1 for k in reg if k.startswith(prefix) and needle in k.lower())


def ack_command(c):
    """-> the printable line for one candidate: an --ack command with the FULL signature and no --yes, or a comment when cmd_ack would refuse it as ambiguous."""
    if c.get("ack_matches", 1) != 1:
        return "    # AMBIGUOUS: %d clusters of %s contain this full signature, `--ack` would refuse it - ack this one by hand with a longer partial" % (c["ack_matches"], c["repo"])
    return "    # hint only - read the commit, then (asks for confirmation):  python3 scripts/ovn_failure_triage.py --ack %s %s --commit %s --generator-addressed unsure" % (
        shlex.quote(c["repo"]), shlex.quote(c["signature"]), c["commits"][0][0])


def candidates(state_dir, repo, quiet_days=7, before_days=1, after_days=3, now=None):
    """-> (candidates, investigate, skipped counts). Pure over the registry file and `git log`; writes nothing."""
    now = now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    try:
        reg = json.load(open(os.path.join(state_dir, "failure_clusters.json")))
    except (OSError, ValueError):
        return [], [], {"registry_unreadable": 1}
    cands, invest = [], []
    skipped = {"already_fixed": 0, "recurring": 0, "no_family": 0, "no_commit": 0, "bad_dates": 0}
    for key, e in sorted(reg.items(), key=lambda kv: -int(kv[1].get("count", 0) or 0)):
        if e.get("status") != "new":
            skipped["already_fixed"] += 1
            continue
        first, last = parse_ts(e.get("first_seen")), parse_ts(e.get("last_seen"))
        if not first or not last:
            skipped["bad_dates"] += 1
            continue
        quiet = (now - last).total_seconds() / 86400.0
        repo_name, _, sig = key.partition("::")
        rx, grep, note = family_of(sig)
        if rx is None:
            skipped["no_family"] += 1
            continue
        row = {"key": key, "repo": repo_name, "signature": sig, "count": e.get("count", 0), "first_seen": e.get("first_seen"), "last_seen": e.get("last_seen"),
               "quiet_days": round(quiet, 1), "family": rx, "note": note, "commits": [], "ack_matches": ack_matches(reg, repo_name, sig)}
        if grep is None:
            invest.append(row)
            continue
        if quiet < quiet_days:
            skipped["recurring"] += 1
            continue
        since = first
        until = last + datetime.timedelta(days=after_days)
        lo = last - datetime.timedelta(days=before_days)
        row["commits"] = [c for c in git_commits(repo, grep, since, until) if (parse_ts(c[1]) or lo) >= lo]
        if not row["commits"]:
            skipped["no_commit"] += 1
            continue
        cands.append(row)
    return cands, invest, skipped


def main(argv):
    args = [a for a in argv[1:]]

    def opt(name, default):
        if name in args:
            i = args.index(name)
            try:
                v = args[i + 1]
            except IndexError:
                return default
            del args[i:i + 2]
            return v
        return default
    ovn = os.environ.get("OVN_DIR") or os.path.dirname(HERE)
    repo = opt("--repo", HERE)
    try:
        quiet, before, after = float(opt("--quiet-days", 7)), float(opt("--before-days", 1)), float(opt("--after-days", 3))
    except ValueError:
        print("ovn_failure_ack_candidates: --quiet-days/--before-days/--after-days must be numbers", file=sys.stderr)
        return 2
    as_json, commands = "--json" in args, "--commands" in args
    args = [a for a in args if a not in ("--json", "--commands")]
    state_dir = args[0] if args else os.path.join(ovn, "state")
    cands, invest, skipped = candidates(state_dir, repo, quiet, before, after)
    if as_json:
        print(json.dumps({"candidates": cands, "investigate": invest, "skipped": skipped}, indent=1))
        return 0
    print("failure-cluster ack HINTS (DRY RUN - nothing is written; no --apply exists; the commits are subject matches, not proof): %d candidate(s), %d to investigate; skipped %s" % (len(cands), len(invest), skipped))
    for c in cands:
        print("\n%s  [%dx, %s .. %s, quiet %.1fd, family %s]" % (c["key"][:150], c["count"], c["first_seen"][:10], c["last_seen"][:16], c["quiet_days"], c["family"]))
        for h, d, s in c["commits"]:
            print("    %s  %s  %s" % (h, d[:16], s[:110]))
        if commands:
            print(ack_command(c))
    for c in invest:
        print("\nINVESTIGATE (not bulk-ackable): %s  [%dx, last %s, quiet %.1fd] - %s" % (c["key"][:120], c["count"], c["last_seen"][:16], c["quiet_days"], c["note"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
