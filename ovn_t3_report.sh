#!/usr/bin/env bash
# ovn_t3_report.sh — hourly snapshot of higher-tier progress + the failure-cause distribution, so we
# can SEE whether the changes (architect->T3, best-of-N, prompt rule 7, parked-recovery) move the
# needle and WHY items still fail. Writes a terse report to state/t3_report.txt (latest) + appends to
# logs/t3_report.log. Cron: 5 * * * *  cd ~/overnight-queue && ./ovn_t3_report.sh >> logs/t3_report.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
OUT="state/t3_report.txt"
python3 - <<'PY' | tee "$OUT"
import json, time, datetime, collections
def load(hours):
    cut=time.time()-hours*3600; rows=[]
    try: f=open("state/outcomes.jsonl")
    except OSError: return rows
    for l in f:
        try: o=json.loads(l)
        except: continue
        try: t=datetime.datetime.fromisoformat(o.get("ts","").replace("Z","+00:00")).timestamp()
        except: continue
        if t>=cut: rows.append(o)
    return rows

now=datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
print(f"=== T3+ / failure report {now} ===")
for label,hrs in (("last 1h",1),("last 6h",6),("last 24h",24)):
    rows=load(hrs)
    if not rows:
        print(f"[{label}] no outcomes"); continue
    cls=collections.Counter(o.get("class") for o in rows)
    # higher-tier specifically
    hi=[o for o in rows if str(o.get("tier")) in ("3","4","5")]
    hi_land=sum(1 for o in hi if o.get("class")=="landed")
    hi_att=len(hi)
    fr=collections.Counter(o.get("fail_reason") for o in rows if o.get("class") not in ("landed","skipped") and o.get("fail_reason"))
    print(f"[{label}] landed={cls.get('landed',0)} reverted={cls.get('reverted',0)} noop={cls.get('noop',0)} skipped={cls.get('skipped',0)}")
    print(f"         T3+ attempts={hi_att} landed={hi_land}" + (f" ({100*hi_land//hi_att}%)" if hi_att else ""))
    if fr:
        print("         fail causes: " + ", ".join(f"{k}:{v}" for k,v in fr.most_common()))
PY
