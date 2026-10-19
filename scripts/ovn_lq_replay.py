#!/usr/bin/env python3
"""ovn_lq_replay.py - replay scripts/ovn_landing_quality.py over the real commit history of a repo (read-only) to MEASURE each rule's false-positive rate.

usage: ovn_lq_replay.py <repo_dir> [--since '10 days ago'] [--ref HEAD] [--rules R1,R2]
stdout: JSON lines {"repo","sha","subject","rule","path","detail"} for each finding, then one summary line {"summary":true,"commits":N,"errors":E,"by_rule":{RULE:n}}.
A plain commit is checked against its first parent (one landing). A STAGED item lands as several commits ("staged step 0 .. K-1", then a `mark staged T3 item (K/K)` commit):
the stage runner's gate sees the whole item, so a unit is `step0^ .. the (K/K) marker` (a helper added in step 0 and wired in step 1 is one clean landing, not an unwired helper).
Pure stdlib; only runs git log/diff/show/grep."""
import importlib.util
import re
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_checker():
    spec = importlib.util.spec_from_file_location("ovn_landing_quality", os.path.join(HERE, "ovn_landing_quality.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    repo = argv[1]
    since, ref = "10 days ago", "HEAD"
    i = 2
    while i < len(argv):
        if argv[i] == "--since":
            since = argv[i + 1]; i += 2
        elif argv[i] == "--ref":
            ref = argv[i + 1]; i += 2
        else:
            i += 1
    lq = load_checker()
    log = subprocess.run(["git", "-C", repo, "log", "--no-merges", "--since=" + since, "--format=%H%x09%s", ref], capture_output=True, text=True, errors="replace").stdout.splitlines()
    by_rule, errors, n = {}, 0, 0
    name = os.path.basename(os.path.abspath(repo))
    chron = [l.partition("\t")[::2] for l in reversed(log)]   # [(sha, subject)] oldest first
    units, skip_to = [], -1
    for i, (sha, subj) in enumerate(chron):
        if i <= skip_to:
            continue
        head = sha
        if re.search(r"staged step 0\b", subj):
            for j in range(i + 1, min(i + 40, len(chron))):
                m = re.search(r"mark staged \w+ item \((\d+)/(\d+)\)", chron[j][1])
                if m and m.group(1) == m.group(2):
                    head, skip_to = chron[j][0], j
                    break
        units.append((sha, head, subj))
    for sha, head, subj in units:
        n += 1
        try:
            found = lq.check(repo, sha + "^", head)
        except Exception:   # noqa: BLE001 - a root commit / bad parent is simply not replayable
            errors += 1
            continue
        for rule, path, detail in found:
            by_rule[rule] = by_rule.get(rule, 0) + 1
            print(json.dumps({"repo": name, "sha": sha[:10], "subject": subj[:90], "rule": rule, "path": path, "detail": detail}))
    print(json.dumps({"summary": True, "repo": name, "commits": n, "errors": errors, "by_rule": by_rule}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
