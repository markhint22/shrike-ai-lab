#!/usr/bin/env python3
"""ovn_gate_red_report.py - diagnose a RED branch_hygiene gate in one command (q-contract, 2026-11-25). READ-ONLY: only reads a log (and, with --git, `git log`).

    ovn_gate_red_report.py [--log PATH|-] [--repo NAME] [--since YYYY-MM-DD] [--passes] [--json] [--git DIR [--ref REF]]
    ssh box 'grep -a -E "=== |MERGED|gate FAILED|^FAILED |^ERROR " ~/overnight-queue/logs/branch_hygiene.log' | ovn_gate_red_report.py --log - --git ~/LocalProjects/gitlark

Source: logs/branch_hygiene.log (default $OVN_DIR/logs/branch_hygiene.log, else next to this script). Format (branch_hygiene.sh):
  [branch-hygiene TS] === NAME (repos/NAME) ===        starts a pass for NAME
  [branch-hygiene TS]   MERGED NAME feat (+N) -> develop   the pass landed (green)
  [branch-hygiene TS]   gate FAILED (...) for NAME      the pass is red
  FAILED tests/x.py::t - msg  /  ERROR tests/x.py       pytest short-summary lines of the failing gate
Per repo it prints each RED STREAK (consecutive gate-failed passes): first-failure time, last red time, how it ended (green merge time, or STILL RED), pass count,
the failing test ids (with the number of passes each id failed in, and whether the id was in the FIRST red pass = the cause, or appeared later), the failure CLASS
(contract = openapi/api-tags tests, other), and with --git the commits that landed on REF (default origin/overnight/feature) between the last green merge and the first
red pass (the suspects) and since. Without a clone the commit lines are skipped. Exit 0 always (advisory); --json for machines."""
import argparse, json, os, re, subprocess, sys
from datetime import datetime, timedelta

HDR = re.compile(r"^\[branch-hygiene (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]\s+(.*)$")
SEC = re.compile(r"^=== (\S+) \(")
MERGED = re.compile(r"^MERGED (\S+) ")
RED = re.compile(r"^gate FAILED \([^)]*\) for (\S+)")
TESTID = re.compile(r"^(FAILED|ERROR) (\S+?)(?: - .*)?$")
# the box logs in its local time (CST, UTC-6): git is asked in the same zone (override: OVN_GATE_RED_TZ="+0000", OVN_GATE_RED_TZ_POSIX="UTC0")
LOG_TZ = os.environ.get("OVN_GATE_RED_TZ", "-0600")
LOG_TZ_POSIX = os.environ.get("OVN_GATE_RED_TZ_POSIX", "CST6")
CONTRACT_RE = re.compile(r"test_openapi|test_api_tags|openapi_meta|openapi_tags|test_main_openapi")


def classify(ids):
    if not ids:
        return "unknown"
    return "contract" if all(CONTRACT_RE.search(i) for i in ids) else ("mixed" if any(CONTRACT_RE.search(i) for i in ids) else "other")


def parse(fh, repo=None, since=None):
    passes, cur = [], None
    for raw in fh:
        line = raw.rstrip("\n")
        m = HDR.match(line)
        if m:
            ts, body = m.group(1), m.group(2).strip()
            s = SEC.match(body)
            if s:
                cur = {"repo": s.group(1), "ts": ts, "status": "other", "ids": []}
                if (repo is None or cur["repo"] == repo) and (since is None or ts >= since):
                    passes.append(cur)
                else:
                    cur = None
                continue
            if cur is None:
                continue
            mm = MERGED.match(body)
            if mm and mm.group(1) == cur["repo"]:
                cur["status"] = "merged"
                continue
            rr = RED.match(body)
            if rr and rr.group(1) == cur["repo"]:
                cur["status"] = "red"
            continue
        if cur is not None:
            t = TESTID.match(line.strip())
            if t and ("/" in t.group(2) or "::" in t.group(2)):
                if t.group(2) not in cur["ids"]:
                    cur["ids"].append(t.group(2))
    return passes


def streaks(passes):
    """per repo: list of {first, last, end, n, ids{id:count}, first_ids, ...}. A streak ends at the next MERGED pass; 'other' (nothing to merge / skipped) passes neither extend nor end it."""
    out = {}
    by = {}
    for p in passes:
        by.setdefault(p["repo"], []).append(p)
    for repo, ps in by.items():
        res, cur, last_green = [], None, None
        for p in ps:
            if p["status"] == "red":
                if cur is None:
                    cur = {"repo": repo, "first": p["ts"], "last": p["ts"], "n": 0, "ids": {}, "first_ids": list(p["ids"]), "end": None, "last_green": last_green}
                cur["n"] += 1
                cur["last"] = p["ts"]
                for i in p["ids"]:
                    cur["ids"][i] = cur["ids"].get(i, 0) + 1
                cur.setdefault("passes", []).append({"ts": p["ts"], "ids": p["ids"]})
            elif p["status"] == "merged":
                if cur is not None:
                    cur["end"] = p["ts"]
                    res.append(cur)
                    cur = None
                last_green = p["ts"]
        if cur is not None:
            res.append(cur)
        out[repo] = res
    return out


def git_commits(gdir, ref, after, before=None):
    cmd = ["git", "-C", gdir, "log", ref, "--format=%h %ad %s", "--date=format-local:%m-%d %H:%M", "--after=" + after + " " + LOG_TZ]
    if before:
        cmd.append("--before=" + before + " " + LOG_TZ)
    env = dict(os.environ, TZ=LOG_TZ_POSIX)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30, env=env)
        return [l for l in r.stdout.splitlines() if l.strip()] if r.returncode == 0 else None
    except Exception:
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--log")
    ap.add_argument("--repo")
    ap.add_argument("--since")
    ap.add_argument("--passes", action="store_true", help="list failing ids per red pass")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--git")
    ap.add_argument("--ref", default="origin/overnight/feature")
    a = ap.parse_args(argv)
    log = a.log
    if not log:
        base = os.environ.get("OVN_DIR") or os.path.dirname(os.path.abspath(__file__))
        log = os.path.join(base, "logs", "branch_hygiene.log")
    fh = sys.stdin if log == "-" else open(log, "r", errors="replace")
    passes = parse(fh, a.repo, a.since)
    st = streaks(passes)
    # last pass per repo (is it currently red?)
    nowred = {}
    for p in passes:
        if p["status"] in ("red", "merged"):
            nowred[p["repo"]] = p["status"]
    rows = []
    for repo, ss in sorted(st.items()):
        for s in ss:
            s["class"] = classify(list(s["ids"]))
            if a.git:
                before = s["first"]
                after = s["last_green"] or (datetime.strptime(s["first"], "%Y-%m-%d %H:%M:%S") - timedelta(hours=6)).strftime("%Y-%m-%d %H:%M:%S")
                s["suspects"] = git_commits(a.git, a.ref, after, before)
                s["since"] = git_commits(a.git, a.ref, before, s["end"])
            rows.append(s)
    if a.json:
        print(json.dumps({"streaks": rows, "current": nowred}, indent=1))
        return 0
    if not rows:
        print("no red streaks in range (passes parsed: %d)" % len(passes))
        return 0
    for s in rows:
        state = "ended %s" % s["end"] if s["end"] else "STILL RED"
        print("== %s: RED %s -> %s (%s), %d red pass(es), class=%s" % (s["repo"], s["first"], s["last"], state, s["n"], s["class"]))
        print("   first-failure ids (cause): %s" % (", ".join(s["first_ids"]) or "(none captured: log head/tail cap)"))
        for i, n in sorted(s["ids"].items(), key=lambda kv: -kv[1]):
            tag = "" if i in s["first_ids"] else "  [appeared later]"
            print("     %-90s %3d pass(es)%s" % (i[:90], n, tag))
        if a.passes:
            for p in s.get("passes", []):
                print("     pass %s: %s" % (p["ts"], ", ".join(p["ids"]) or "-"))
        if a.git:
            for key, title in (("suspects", "landed between last green (%s) and first red" % (s["last_green"] or "?")), ("since", "landed from first red to %s" % (s["end"] or "now"))):
                c = s.get(key)
                print("   commits %s: %s" % (title, "n/a (no clone/ref)" if c is None else len(c)))
                for l in (c or [])[:12]:
                    print("      " + l)
    return 0


if __name__ == "__main__":
    sys.exit(main())
