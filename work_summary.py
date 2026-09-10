#!/usr/bin/env python3
"""work_summary.py — a deterministic "what did the fleet actually DO" digest from outcomes.jsonl.

The supervisor push used to only fire on PROBLEMS ("5 items need attention"), so a normal working
night looked silent and you couldn't see throughput. This prints a terse, real summary — landed /
reverted / no-op / parked over a window, broken out by tier (so higher-tier progress is visible) and
the top repos — suitable for the ntfy body.

Usage: work_summary.py [hours]   (default 24)  — reads state/outcomes.jsonl relative to CWD.
"""
import json, sys, time, datetime, collections, os

HOURS = int(sys.argv[1]) if len(sys.argv) > 1 else 24
PATH = os.environ.get("OUTCOMES", "state/outcomes.jsonl")


def main():
    cut = time.time() - HOURS * 3600
    cls = collections.Counter()
    tier_landed = collections.Counter()
    repo_landed = collections.Counter()
    reverted_repos = collections.Counter()
    try:
        f = open(PATH)
    except OSError:
        print(f"(no outcomes file at {PATH})")
        return
    for line in f:
        try:
            o = json.loads(line)
        except Exception:
            continue
        try:
            t = datetime.datetime.fromisoformat(o.get("ts", "").replace("Z", "+00:00")).timestamp()
        except Exception:
            continue
        if t < cut:
            continue
        c = o.get("class", "?")
        cls[c] += 1
        if c == "landed":
            repo_landed[o.get("repo", "?")] += 1
            tr = str(o.get("tier", "?"))
            tier_landed[tr] += 1
        elif c == "reverted":
            reverted_repos[o.get("repo", "?")] += 1

    landed = cls.get("landed", 0)
    lines = [f"Last {HOURS}h: {landed} landed · {cls.get('reverted',0)} reverted · "
             f"{cls.get('noop',0)} no-op · {cls.get('skipped',0)} skipped"]
    # by tier (the higher-tier-progress signal the whole exercise is about)
    if tier_landed:
        order = ["1", "2", "3", "4", "5", "?"]
        tbits = [f"T{t}:{tier_landed[t]}" for t in order if tier_landed.get(t)]
        lines.append("  landed by tier: " + " ".join(tbits))
        hi = tier_landed.get("3", 0) + tier_landed.get("4", 0) + tier_landed.get("5", 0)
        lines.append(f"  higher-tier (T3+) landed: {hi}")
    if repo_landed:
        top = ", ".join(f"{r} {n}" for r, n in repo_landed.most_common(6))
        lines.append("  by repo: " + top)
    if reverted_repos:
        lines.append("  reverts: " + ", ".join(f"{r} {n}" for r, n in reverted_repos.most_common(5)))
    # staged multi-stage higher-tier: VERIFIED completion (independent, not self-reported)
    try:
        import glob as _g
        vr=_c=_l=0
        seen=set()
        for fp in _g.glob("state/stage_runs/*.jsonl"):
            for ln in open(fp):
                try: o=json.loads(ln)
                except: continue
                if o.get("event")=="summary":
                    r=o.get("run");
                    if r in seen: continue
                    seen.add(r)
                    if o.get("verified") is True and o.get("passed")==o.get("total") and o.get("total"): vr+=1
                    elif o.get("verified") is False: _c+=1
                    elif o.get("verified") is None: _l+=1
        if vr or _c or _l:
            lines.append(f"  staged higher-tier (independently verified): {vr} complete"
                         + (f", {_c} false-pass caught" if _c else "") + (f", {_l} legacy-unverified" if _l else ""))
    except Exception: pass
    print("\n".join(lines))


if __name__ == "__main__":
    main()
