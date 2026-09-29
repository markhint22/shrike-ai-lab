import json, sys
sys.path.insert(0, "scripts")
from ovn_outcome_buckets import bucket_from_severity

windows = {
    "a_baseline_0928_pre21cdt": ("2026-09-28T05:00:00Z", "2026-09-29T02:00:00Z"),
    "b_post11bugfix_0928-21cdt_to_0929-08cdt": ("2026-09-29T02:00:00Z", "2026-09-29T13:00:00Z"),
    "c_post_morningsweep_0929-08cdt_to_now": ("2026-09-29T13:00:00Z", "2026-09-30T23:59:59Z"),
}

rows = []
with open("state/outcomes.jsonl") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            pass

for wname, (start, end) in windows.items():
    print("=== %s [%s .. %s] ===" % (wname, start, end))
    overall = {"good":0,"bad":0,"benign":0}
    per_repo = {}
    for r in rows:
        ts = r.get("ts","")
        if not (start <= ts < end):
            continue
        b = bucket_from_severity(r.get("severity"))
        overall[b]+=1
        repo = r.get("repo","?")
        per_repo.setdefault(repo, {"good":0,"bad":0,"benign":0})
        per_repo[repo][b]+=1
    tot_nb = overall["good"]+overall["bad"]
    rate = (overall["good"]/tot_nb*100) if tot_nb else float("nan")
    good = overall["good"]; bad = overall["bad"]; benign = overall["benign"]
    print("  OVERALL: good=%d bad=%d benign=%d nonbenign_n=%d pass_rate=%.1f%%" % (good, bad, benign, tot_nb, rate))
    for repo, c in sorted(per_repo.items()):
        n = c["good"]+c["bad"]
        r_rate = (c["good"]/n*100) if n else float("nan")
        print("    %-25s good=%3d bad=%3d benign=%3d n=%3d rate=%.1f%%" % (repo, c["good"], c["bad"], c["benign"], n, r_rate))
    print()
