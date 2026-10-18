#!/usr/bin/env python3
"""Applied-migration immutability check (2026-10-18, test-automation-agent audit).

A cycle that EDITS or DELETES a migration file that already exists on the production
ref rewrites history: fresh databases get a different schema than prod, and a column
added to the baseline AND by a later migration fails with "duplicate column" (live:
test-automation-agent 3114b2a edited 0001_baseline.py to 'align with the models' ->
llm_input_tokens added twice -> 3 migration tests red for every later cycle, baseline-red
masked it as a kept landing, hygiene gate failed 6 passes).

Usage: check_applied_migration_immutable.py <repo> <before_sha> <after_sha> [prod_ref]
Exit 0 = clean (or nothing to judge), 1 = an applied migration was modified/deleted.
New files and edits to files NOT on prod_ref (default origin/main, then main) are fine.
"""
import subprocess
import sys


def git(repo, *args):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def main(argv):
    if len(argv) < 4:
        print("usage: check_applied_migration_immutable.py <repo> <before> <after> [prod_ref]")
        return 0
    repo, before, after = argv[1:4]
    refs = [argv[4]] if len(argv) > 4 else ["origin/main", "main"]
    ref = next((r for r in refs if git(repo, "rev-parse", "--verify", "-q", r + "^{commit}")[0] == 0), None)
    if not ref:
        return 0  # no prod ref to compare against: advisory gate stays silent
    rc, out = git(repo, "diff", "--name-status", "--diff-filter=MDR", before, after, "--", ".")
    if rc != 0:
        return 0
    bad = []
    for line in out.splitlines():
        parts = line.split("\t")
        path = parts[1] if len(parts) > 1 else ""
        if "alembic/versions/" not in path and "/migrations/versions/" not in path:
            continue
        if not path.endswith(".py"):
            continue
        if git(repo, "cat-file", "-e", "%s:%s" % (ref, path))[0] == 0:
            bad.append("%s (%s)" % (path, parts[0]))
    for b in bad:
        print("  ✗ APPLIED-MIGRATION-EDIT: %s exists on %s and was modified/deleted - write a NEW migration instead" % (b, ref))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
