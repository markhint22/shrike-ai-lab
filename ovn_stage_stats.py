#!/usr/bin/env python3
"""Multi-stage runner stats — headlines INDEPENDENTLY-VERIFIED completion (verified==true only), so the
numbers can't be inflated by the pipeline's own self-reported 'pass'. Also: step pass-rate, timing,
re-decomposition, and top failure causes with example excerpts."""
import json, glob, collections, os, statistics
os.chdir(os.path.expanduser("~/overnight-queue"))
runs = {}
step_durs, fails, fail_ex, redecomp = [], collections.Counter(), {}, 0
for fp in sorted(glob.glob("state/stage_runs/*.jsonl")):
    for line in open(fp):
        try: o = json.loads(line)
        except: continue
        r = o.get("run")
        if not r: continue
        runs.setdefault(r, {"tier": None, "passed": 0, "total": 0, "verified": None})
        e = o.get("event")
        if e == "summary":
            runs[r].update(tier=o.get("tier"), passed=o.get("passed",0), total=o.get("total",0), verified=o.get("verified"))
        elif e == "verify": runs[r]["verified"] = o.get("verified")
        elif e == "decomposed": runs[r]["tier"] = o.get("tier")
        elif e == "redecomposed": redecomp += 1
        elif "verdict" in o:
            runs[r].setdefault("tsent",0); runs[r].setdefault("trecv",0)
            runs[r]["tsent"]+=o.get("tokens_sent",0) or 0; runs[r]["trecv"]+=o.get("tokens_recv",0) or 0
            if o.get("duration_s"): step_durs.append(o["duration_s"])
            if o["verdict"] == "fail" and o.get("fail_reason"):
                fails[o["fail_reason"]] += 1
                fail_ex.setdefault(o["fail_reason"], o.get("excerpt","")[:140])
done = [r for r in runs.values() if r["total"]]
print(f"=== multi-stage runner: {len(done)} completed item-runs ===")
by = collections.defaultdict(lambda: {"items":0,"verified":0,"false":0,"legacy":0})
for r in done:
    t = str(r["tier"]); by[t]["items"] += 1; full = (r["passed"]==r["total"] and r["total"])
    if r.get("verified") is True and full: by[t]["verified"] += 1
    elif r.get("verified") is False: by[t]["false"] += 1
    elif r.get("verified") is None: by[t]["legacy"] += 1
for t in sorted(by):
    b = by[t]
    extra = []
    if b["false"]: extra.append(f"{b['false']} false-pass CAUGHT")
    if b["legacy"]: extra.append(f"{b['legacy']} legacy-unverified")
    print(f"  T{t}: {b['items']} items | VERIFIED-complete {b['verified']}" + (f"  ({', '.join(extra)})" if extra else ""))
# token spend / value-per-task
tsent=sum(r.get("tsent",0) for r in done); trecv=sum(r.get("trecv",0) for r in done)
vr_runs=[r for r in done if r.get("verified") is True and r["passed"]==r["total"] and r["total"]]
if tsent or trecv:
    print(f"  tokens: {tsent:,} sent + {trecv:,} generated across {len(done)} runs"
          + (f"; ~{(tsent+trecv)//max(1,len(vr_runs)):,}/verified-item" if vr_runs else " (0 verified yet)"))
tv = sum(b["verified"] for b in by.values()); ti = sum(b["items"] for b in by.values())
print(f"  OVERALL verified higher-tier completion: {tv}/{ti} ({100*tv//ti if ti else 0}%) | re-decompositions: {redecomp}")
unver = [r for r in done if r.get("verified") is None]
if unver: print(f"  NOTE: {len(unver)} run(s) predate the verify layer (unknown-honesty; re-run to confirm)")
if step_durs: print(f"  step timing: median {int(statistics.median(step_durs))}s, max {max(step_durs)}s")
if fails:
    print("  FAIL causes (attack these):")
    for k,v in fails.most_common(): print(f"    {k}: {v}" + (f'  e.g. «{fail_ex.get(k,"")}»' if fail_ex.get(k) else ""))
