#!/usr/bin/env bash
# ovn_godot_report.sh — hourly snapshot of xlite/godot-specific pass rate, so we can watch whether
# the 2026-09-14/15 fixes (decompose-prompt bug, stuck test-file loop, phantom stale-summary
# reporting) hold up over real unattended time, and decide whether to greenlight future Godot work.
#
# Filters out the SAME noise classes identified during the 2026-09-14/15 investigation (queue-
# exhausted idle cycles, the now-fixed phantom "skip(exhausted) stage(higher-tier)" cycles, model
# API blips) so the reported rate reflects genuine attempts only — see
# project_godot-overnight-0of20-was-a-reporting-bug-2026-09-15.md for why this matters: the naive
# unfiltered number looked like a total capability collapse when the real story was very different.
#
# Writes to state/godot_report.txt (latest) + appends to logs/godot_report.log.
# Cron: 10 * * * *  cd ~/overnight-queue && ./ovn_godot_report.sh >> logs/godot_report.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
OUT="state/godot_report.txt"
python3 - <<'PY' | tee "$OUT"
import json, time, datetime, collections

def is_noise(o):
    st = (o.get("status") or "").lower()
    fr = (o.get("fail_reason") or "").lower()
    return ("exhaust" in st or "exhaust" in fr or fr in ("model-api-error", "timeout")
            or "api error" in st)

def load(hours):
    cut = time.time() - hours * 3600
    rows = []
    try:
        f = open("state/outcomes.jsonl")
    except OSError:
        return rows
    for l in f:
        try:
            o = json.loads(l)
        except Exception:
            continue
        if o.get("type") != "aider_fix" or o.get("category") != "godot":
            continue
        try:
            t = datetime.datetime.fromisoformat(o.get("ts", "").replace("Z", "+00:00")).timestamp()
        except Exception:
            continue
        if t >= cut:
            rows.append(o)
    return rows

now = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
print(f"=== godot pass-rate report {now} ===")
for label, hrs in (("last 6h", 6), ("last 24h", 24), ("last 72h", 72)):
    rows = load(hrs)
    real = [o for o in rows if not is_noise(o)]
    noise_n = len(rows) - len(real)
    if not real:
        print(f"[{label}] no genuine godot attempts (raw={len(rows)}, noise-filtered={noise_n})")
        continue
    cls = collections.Counter(o.get("class") for o in real)
    landed = cls.get("landed", 0)
    total = len(real)
    fr = collections.Counter(o.get("fail_reason") for o in real if o.get("class") != "landed" and o.get("fail_reason"))
    print(f"[{label}] genuine attempts={total} (raw={len(rows)}, filtered-noise={noise_n}) "
          f"landed={landed} ({100*landed//total}%) reverted={cls.get('reverted',0)} noop={cls.get('noop',0)}")
    if fr:
        print("         fail causes: " + ", ".join(f"{k}:{v}" for k, v in fr.most_common()))
print()
print("Reminder: a 'landed' godot item still needs a manual signature/behavior spot-check — the")
print("verify gate does not catch interface drift (see project_godot-staging-reenabled-2026-09-14.md).")
PY
