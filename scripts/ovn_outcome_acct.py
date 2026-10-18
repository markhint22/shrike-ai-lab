#!/usr/bin/env python3
"""ovn_outcome_acct.py - outcome accounting reconcile (package D4, 2026-10-18).

record_outcome() now stamps every state/outcomes.jsonl row with  commits=[sha...], head_before, head_after.  A cycle whose commit was HELD (VERIFY-SKIP,
lock-contended, verify-timeout hold) writes a non-landing row; the commit is pushed by a LATER cycle, which records its own landing (or none: iptv_apps had
0 pushed rows while 4 commits landed). This script closes that gap by attribution:

    reconcile   for every recent row that carries commits and is not itself a landing, check whether ALL those commits are now reachable from one of the
                repo's remote-tracking branches (origin/overnight/feature, origin/claude/feature, origin/develop, ...). If so append ONE row
                class="landed-late", severity="neutral", status="landed-late(held-commit)" with the same repo/id/tier/category/item_hash/feat_tag,
                late_of_ts = the held row's ts, commits/head_*, landed_branch. Idempotent: a held row already named by a landed-late row's late_of_ts
                (same repo) is never written twice.
    commits     print the JSON commit list for <repo_dir> <before> <after> (what lib_outcome_acct.sh ovn_oa_commits prints).
    attribute   print, for a sha, the outcome row(s) that name it (ts, class, status) - the "which cycle made this commit" lookup.

Additive and advisory: landed-late is severity neutral, so it never changes a pass rate (readers that count class == "landed" ignore it; ovn_outcome_buckets
buckets it benign), and the original held row is never rewritten. Read-only on the repos (no fetch unless --fetch), appends to outcomes.jsonl only.
A held commit whose sha was rewritten by `git pull --rebase` is matched by stable patch-id. Concurrent reconciles are serialised by a non-blocking flock
(state/outcome_reconcile.lock): the loser skips. Readers (ovn_batch_scorecard, ovn_daily_fail_digest) never count a landed-late row as a cycle.
Never fatal: any git/IO problem skips that row. OVN_OUTCOME_RECONCILE=off disables the in-runner call (run_overnight.sh).
usage: ovn_outcome_acct.py reconcile --state-dir D --repos-dir R [--branches a,b] [--window-h 96] [--fetch] [--dry-run]
"""
import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

LANDING_CLASSES = frozenset({"landed", "landed-uncredited", "credit-only", "landed-late"})
# classes whose commit can legitimately reach origin LATER: a held commit (class held: verify-timeout hold; class error: VERIFY-SKIP "verify-skipped", lock-contended)
# or an unrecognized status. A revert/no-op/skip row never owns a commit (HEAD is reset), so a commit list there could only be a foreign commit that arrived mid-cycle.
HELD_CLASSES = frozenset({"held", "error", "unknown"})
DEFAULT_BRANCHES = ("overnight/feature", "claude/feature", "develop")
TAIL_BYTES = 8 * 1024 * 1024   # bound the scan: outcomes.jsonl grows without limit
SHA_CHARS = set("0123456789abcdefABCDEF")


def _valid_sha(s):
    return isinstance(s, str) and 7 <= len(s) <= 40 and set(s) <= SHA_CHARS


def parse_ts(ts):
    """'2026-10-18T07:26:00Z' -> epoch seconds, or None."""
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except (TypeError, ValueError):
        return None


def read_rows(path, tail_bytes=TAIL_BYTES):
    """Rows of outcomes.jsonl (the last tail_bytes of it). Malformed lines (incl. the cut first line of a tail read) are skipped, never fatal."""
    rows = []
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > tail_bytes:
                fh.seek(size - tail_bytes - 1)
                fh.readline()   # drop the partial line (seeking one byte early keeps a line that starts exactly at the cut)
            data = fh.read().decode("utf-8", "replace")
    except OSError:
        return rows
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict):
            rows.append(r)
    return rows


def row_commits(row):
    """The valid sha list of a row (old-format rows have none)."""
    c = row.get("commits")
    if not isinstance(c, list):
        return []
    return [x for x in c if _valid_sha(x)]


def is_candidate(row):
    """A held-class row that carries commits (see HELD_CLASSES): those commits can only reach origin later. The stage runner's unverified row (class noop, status
    "no-op(stage-unverified) ...") is the other owner of never-verified commits: they may be pushed by a later stage run, so it is a candidate too."""
    if not row_commits(row):
        return False
    return row.get("class") in HELD_CLASSES or str(row.get("status", "")).startswith("no-op(stage-unverified)")


def _git(repo_dir, *args, timeout=20):
    try:
        return subprocess.run(["git", "-C", repo_dir] + list(args), capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None


def _patch_ids(repo_dir, ref, since_epoch, max_count=400):
    """{patch-id: sha} of the commits on <ref> committed at or after since_epoch (bounded). A commit rewritten by `git pull --rebase` keeps its patch-id."""
    try:
        log = subprocess.run(["git", "-C", repo_dir, "log", "-p", "--no-color", "--max-count=%d" % max_count, "--after=%d" % int(since_epoch), ref],
                             capture_output=True, timeout=60)
        if log.returncode != 0 or not log.stdout:
            return {}
        pid = subprocess.run(["git", "-C", repo_dir, "patch-id", "--stable"], input=log.stdout, capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return {}
    res = {}
    for line in pid.stdout.decode("utf-8", "replace").splitlines():
        parts = line.split()
        if len(parts) == 2:
            res[parts[0]] = parts[1]
    return res


def _own_patch_id(repo_dir, sha):
    try:
        show = subprocess.run(["git", "-C", repo_dir, "diff-tree", "-p", "--no-color", "--root", sha], capture_output=True, timeout=20)
        if show.returncode != 0 or not show.stdout:
            return None, None
        pid = subprocess.run(["git", "-C", repo_dir, "patch-id", "--stable"], input=show.stdout, capture_output=True, timeout=20)
        t = subprocess.run(["git", "-C", repo_dir, "show", "-s", "--format=%ct", sha], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None, None
    parts = pid.stdout.decode("utf-8", "replace").split()
    try:
        return (parts[0] if parts else None), int(t.stdout.strip())
    except ValueError:
        return None, None


def cycle_commits(repo_dir, before, after, since=None, cap=20):
    """Python twin of lib_outcome_acct.sh ovn_oa_commits. Without since: after --not before. With since (the cycle start epoch): only NON-MERGE commits whose AUTHOR date is
    >= since (author date survives a rebase), newest <cap> kept, oldest first - the upstream commits that arrived with a mid-cycle `pull --rebase` / merge sit between
    before and after too, and are not this cycle's."""
    if not (_valid_sha(before) and _valid_sha(after)) or before == after:
        return []
    if since is None:
        r = _git(repo_dir, "rev-list", "--reverse", "--max-count=%d" % cap, after, "--not", before)
        return r.stdout.split() if r is not None and r.returncode == 0 else []
    r = _git(repo_dir, "log", "--reverse", "--no-merges", "--max-count=500", "--format=%H %at", after, "--not", before)
    if r is None or r.returncode != 0:
        return []
    res = []
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and int(parts[1]) >= since:
            res.append(parts[0])
    return res[-cap:]


def landed_branch(repo_dir, shas, branches, cache=None, since_epoch=None):
    """The first remote-tracking branch that contains EVERY sha, or None (a missing ref / unknown sha is simply 'not landed').

    A sha is "contained" when it is an ancestor of the branch OR (fallback) a commit with the same stable patch-id is on the branch: run_overnight.sh's
    `git push || git pull --rebase && git push` rewrites a held commit's sha, and the ancestor check alone would never see it land."""
    for br in branches:
        ref = "refs/remotes/origin/" + br
        r = _git(repo_dir, "rev-parse", "-q", "--verify", ref)
        if r is None or r.returncode != 0:
            continue
        ok = True
        for sha in shas:
            m = _git(repo_dir, "merge-base", "--is-ancestor", sha, ref)
            if m is not None and m.returncode == 0:
                continue
            # per-run caches (a candidate that never lands is re-checked every 10 min, and many stale ones used to starve the 60 s cap): the sha's own patch-id once,
            # the branch's patch-id window once per (repo, branch) - sized for the oldest candidate (since_epoch) - instead of once per candidate and branch
            ck = ("own", repo_dir, sha)
            if cache is not None and ck in cache:
                own, ct = cache[ck]
            else:
                own, ct = _own_patch_id(repo_dir, sha)   # None when the object is gone: cannot be proven landed
                if cache is not None:
                    cache[ck] = (own, ct)
            if own is None:
                ok = False
                break
            pk = ("pids", repo_dir, br)
            if cache is not None and pk in cache:
                pids = cache[pk]
            else:
                lo = ct - 86400
                if since_epoch is not None:
                    lo = min(lo, since_epoch - 86400)
                pids = _patch_ids(repo_dir, ref, lo, max_count=1500 if since_epoch is not None else 400)
                if cache is not None:
                    cache[pk] = pids
            if own not in pids:
                ok = False
                break
        if ok:
            return br
    return None


def reconcile(state_dir, repos_dir, branches=DEFAULT_BRANCHES, window_h=96.0, fetch=False, dry_run=False, now=None):
    """Append landed-late rows. Returns the list of rows written (or that would be, with dry_run).

    The read-dedupe-append runs under an exclusive non-blocking flock (state/outcome_reconcile.lock): a concurrent reconcile (several lanes finishing in the same
    second, a manual run during a cron run) skips - the holder is already doing the job - so the same held row can never get two landed-late rows."""
    if dry_run:
        return _reconcile_locked(state_dir, repos_dir, branches, window_h, fetch, dry_run, now)
    try:
        lk = open(os.path.join(state_dir, "outcome_reconcile.lock"), "a")
    except OSError:
        return []
    try:
        try:
            fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return []
        return _reconcile_locked(state_dir, repos_dir, branches, window_h, fetch, dry_run, now)
    finally:
        lk.close()


def _reconcile_locked(state_dir, repos_dir, branches, window_h, fetch, dry_run, now):
    path = os.path.join(state_dir, "outcomes.jsonl")
    rows = read_rows(path)
    now = time.time() if now is None else now
    done = {(r.get("repo"), r.get("late_of_ts")) for r in rows if r.get("class") == "landed-late"}
    fetched = set()
    cache = {}
    out = []
    # rows are appended ONE AT A TIME as they are found (the runner caps this process at 60 s: a late kill must keep what was already proven, and the done-set
    # above makes the next run skip it)
    fh = None
    if not dry_run:
        try:
            fh = open(path, "a", encoding="utf-8")
        except OSError:
            return []
    for r in rows:
        if not is_candidate(r):
            continue
        repo, ts = r.get("repo"), r.get("ts")
        if (repo, ts) in done:
            continue
        t = parse_ts(ts)
        if t is None or now - t > window_h * 3600:
            continue
        rd = os.path.join(repos_dir, str(repo))
        if not repo or not os.path.isdir(os.path.join(rd, ".git")) and not os.path.isfile(os.path.join(rd, ".git")):
            continue
        if fetch and rd not in fetched:
            fetched.add(rd)
            _git(rd, "fetch", "-q", "origin", timeout=60)
        shas = row_commits(r)
        br = landed_branch(rd, shas, branches, cache, now - window_h * 3600)
        if br is None:
            continue
        new = {
            "ts": datetime.fromtimestamp(now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "repo": repo, "id": r.get("id", ""), "type": r.get("type", ""),
            "tier": r.get("tier", "?"), "category": r.get("category", "other"),
            "class": "landed-late", "severity": "neutral",
            "attempt": 1, "attempts": 1, "bestn_stop": "", "fail_reason": "",
            "status": "landed-late(held-commit)",
            "tokens_sent": 0, "tokens_recv": 0, "duration_s": 0,
            "item_hash": r.get("item_hash", ""), "feat_tag": r.get("feat_tag", ""),
            "commits": shas, "head_before": r.get("head_before", ""), "head_after": r.get("head_after", ""),
            "late_of_ts": ts, "late_of_status": str(r.get("status", ""))[:80], "landed_branch": br,
        }
        if fh is not None:
            try:
                fh.write(json.dumps(new, separators=(",", ":")) + "\n")   # one write per row: O_APPEND keeps concurrent writers' lines whole
                fh.flush()
            except OSError:
                break
        out.append(new)
        done.add((repo, ts))
    if fh is not None:
        fh.close()
    return out


def attribute(state_dir, sha):
    """Rows (any class) whose commits list names sha (prefix match, >= 7 chars)."""
    if not _valid_sha(sha):
        return []
    res = []
    for r in read_rows(os.path.join(state_dir, "outcomes.jsonl")):
        if any(c.startswith(sha) or sha.startswith(c) for c in row_commits(r)):
            res.append({"ts": r.get("ts"), "repo": r.get("repo"), "class": r.get("class"), "status": r.get("status"), "late_of_ts": r.get("late_of_ts")})
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    rc = sub.add_parser("reconcile")
    rc.add_argument("--state-dir", required=True)
    rc.add_argument("--repos-dir", required=True)
    rc.add_argument("--branches", default=",".join(DEFAULT_BRANCHES))
    rc.add_argument("--window-h", type=float, default=96.0)
    rc.add_argument("--fetch", action="store_true")
    rc.add_argument("--dry-run", action="store_true")
    cm = sub.add_parser("commits")
    cm.add_argument("repo_dir"); cm.add_argument("before"); cm.add_argument("after")
    cm.add_argument("--since", type=int, default=None, help="cycle start epoch: used when before is not an ancestor of after (rebase/merge mid-cycle)")
    at = sub.add_parser("attribute")
    at.add_argument("--state-dir", required=True); at.add_argument("sha")
    a = ap.parse_args(argv)
    if a.cmd == "reconcile":
        br = tuple(b for b in a.branches.split(",") if b)
        wrote = reconcile(a.state_dir, a.repos_dir, br, a.window_h, a.fetch, a.dry_run)
        for n in wrote:
            print("%s %s %s late_of=%s branch=%s commits=%d" % ("would-write" if a.dry_run else "wrote", n["repo"], n["class"], n["late_of_ts"], n["landed_branch"], len(n["commits"])))
        print("reconcile: %d landed-late row(s) %s" % (len(wrote), "found (dry-run)" if a.dry_run else "written"))
    elif a.cmd == "commits":
        if not (_valid_sha(a.before) and _valid_sha(a.after)) or a.before == a.after:
            print("[]")
        else:
            print(json.dumps(cycle_commits(a.repo_dir, a.before, a.after, a.since)))
    else:
        print(json.dumps(attribute(a.state_dir, a.sha), indent=1))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:   # never fatal for the runner
        print("ovn_outcome_acct: %s" % e, file=sys.stderr)
        sys.exit(0)
