#!/usr/bin/env python3
"""gpu_ledger.py - Phase 5 GPU-seconds-per-stage ledger (docs/QA_PLAN_2026-10-01.md section 9: "GPU minutes per landed feature by stage"). SHADOW.

    gpu_ledger.py run     [--no-record] [--days 14]    derive, merge into state/qa_shadow/gpu_ledger.jsonl + gpu_ledger_weekly.md, print a JSON summary
    gpu_ledger.py report  [--days 14]                  print the weekly table, write nothing
    gpu_ledger.py reconcile [--days 14]                independent re-sum of the raw logs vs the ledger (exit 0 always; verdict in the output)

It only READS existing logs (it never calls the model, never touches the GPU, never takes run.lock). Sources (all under state/; a missing file is a source with 0 rows, listed
as such in the output, never an error):

  stage      source                          GPU seconds taken from
  dev        outcomes.jsonl                  duration_s of every attempt row (wall time of the aider/stage attempt: the GPU-bound part dominates, tests are included - a PROXY)
  dev        token_ledger.jsonl (planner, stage-*, recover_parked, ...)  tokens_sent / prefill rate + tokens_recv / decode rate (ESTIMATE; rates below)
  research   token_ledger.jsonl (local-research, explore, scout ...)     same estimate; qwen_explore.jsonl `secs` (measured wall seconds of an explore pass)
  reviewer   qa_shadow/reviewer.jsonl        details.usage.gpu_s (the llama.cpp timings the reviewer records; MEASURED). Rows without a model call count 0.
  card       qa_shadow/acceptance.jsonl      details.meta.gpu_s / details.usage.gpu_s / details.gpu_s (MEASURED; the card gate records it when it runs; no such log exists today)
  spec_gate  spec_gate.jsonl                 row gpu_s when present (its exec `ms` is CPU test time and is reported separately as cpu_s, never as GPU)
  mutation   qa_shadow/mutation.jsonl        details.gpu_s when present (no such log exists today; the Godot mutation scan runs on CPU)
The `sources` block of every run lists rows seen and seconds per source so an absent stage shows as 0 rows, not as a silent zero.

Rates (the token ledger has no timings): decode = the median tok_s_best of state/toks.jsonl (the live throughput probe), else 45 tok/s; prefill = OVN_GPU_PREFILL_TOKS (default 1500).
Both are printed in the output; `reconcile` does not depend on them (it re-sums the same estimate independently).

Not summed (double counts / not local GPU): token_ledger rows with source qwen-explore (the same pass is a qwen_explore.jsonl row), supervisor-review (remote), and any source that maps
to a stage with its own measured log. outcomes duration_s (aider/stage attempt wall time) and the token_ledger planner / stage-decompose / recover_parked / groom rows are DIFFERENT calls
as far as the logs show (no shared id to dedupe on); both stay under `dev` and are listed separately in `sources`, so the dev number is an upper bound.
The window is aligned down to the Monday of the oldest week, and a week row is never rewritten smaller.

Attribution (per landed feature = ledger record(s) with one feat tag, same grouping as wip_cap.py): an outcomes row joins by item_hash or feat_tag; a spec_gate row by its `feat`;
a reviewer/card row by the head commit of its `ref` (A..B or B) matched to the commits attributed to a ledger record. Everything that cannot be joined (planner calls, research, rows of
items that never landed) stays in the weekly table as UNATTRIBUTED cost, because the plan's metric is total GPU minutes / landed features, not only the cost of the winners.

Outputs: gpu_ledger.jsonl rows {kind:"feature"} (directly attributed seconds per stage, merged by key, older rows kept) and {kind:"week"} (ISO week x repo x stage: seconds, landed
features, minutes per landed feature). Flag OVN_QA_GPU_LEDGER=off|shadow (default shadow; any other value, including 'enforce', behaves as shadow: nothing enforces here).
Always exits 0.
"""
import calendar
import collections
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_ledger as ql  # noqa: E402
import phase5_common as p5  # noqa: E402
import wip_cap as wc  # noqa: E402

ENV = "OVN_QA_GPU_LEDGER"
MODES = ("off", "shadow")
STAGES = ("dev", "card", "reviewer", "mutation", "spec_gate", "research")
DEFAULT_DECODE = 45.0
DEFAULT_PREFILL = 1500.0
RECONCILE_TOL = 0.01


def mode():
    return p5.flag(ENV, MODES, "shadow")[0]


def parse_epoch(ts):
    try:
        return calendar.timegm(time.strptime(str(ts)[:19], "%Y-%m-%dT%H:%M:%S"))
    except (ValueError, TypeError, OverflowError):
        return None


def num(x):
    """A finite non-negative float, else None (bools, NaN, inf, strings, negatives are not seconds)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    x = float(x)
    return x if x == x and x not in (float("inf"), float("-inf")) and x >= 0 else None


def window_start(now, days):
    """Start of the window, ALIGNED DOWN to Monday 00:00 UTC of the ISO week containing now - days*86400, so the oldest week is always summed whole
    (a week row is replaced by key on every run: a half-summed week would overwrite its own complete row)."""
    since = now - days * 86400
    g = time.gmtime(since)
    return calendar.timegm((g.tm_year, g.tm_mon, g.tm_mday, 0, 0, 0)) - g.tm_wday * 86400


def week_of(epoch):
    y, w, _ = time.strftime("%G-%V-%u", time.gmtime(epoch)).split("-")
    return "%s-W%s" % (y, w)


# token_ledger rows that must NOT be summed: qwen-explore is the same explore pass as a qwen_explore.jsonl row (measured wall seconds win); supervisor-review is a remote
# (Claude) review, not a local GPU call; rows that map to a stage with its own MEASURED source (reviewer / card / mutation / spec_gate) are never estimated from tokens.
def token_excluded(row):
    s = str(row.get("source") or "").lower()
    return s == "qwen-explore" or "supervisor" in s or token_stage(s) in ("reviewer", "card", "mutation", "spec_gate")


def token_stage(source):
    s = str(source or "").lower()
    if any(k in s for k in ("research", "explore", "scout")):
        return "research"
    if "card" in s or "acceptance" in s:
        return "card"
    if "review" in s or "refut" in s:
        return "reviewer"
    if "mutat" in s:
        return "mutation"
    if "spec" in s:
        return "spec_gate"
    return "dev"


def rates(state_dir):
    dec = []
    for r in p5.read_jsonl(os.path.join(state_dir, "toks.jsonl")):
        v = num(r.get("tok_s_best"))
        if v:
            dec.append(v)
    decode = wc.median(dec) if dec else DEFAULT_DECODE
    try:
        prefill = float(os.environ.get("OVN_GPU_PREFILL_TOKS", "") or DEFAULT_PREFILL)
        prefill = prefill if prefill > 0 else DEFAULT_PREFILL
    except ValueError:
        prefill = DEFAULT_PREFILL
    return decode, prefill


def first_num(d, paths):
    for p in paths:
        cur = d
        for k in p:
            cur = cur.get(k) if isinstance(cur, dict) else None
        v = num(cur)
        if v is not None:
            return v
    return None


# Each source: (name, relative path, stage fn(row) -> stage, seconds fn(row, decode, prefill) -> seconds|None, ts field)
def _outcome_s(r, dec, pre):
    return num(r.get("duration_s"))


def _token_s(r, dec, pre):
    a, b = num(r.get("tokens_sent")), num(r.get("tokens_recv"))
    if a is None and b is None:
        return None
    return (a or 0.0) / pre + (b or 0.0) / dec


def _reviewer_s(r, dec, pre):
    return first_num(r, [("details", "usage", "gpu_s")]) or 0.0


def _card_s(r, dec, pre):
    return first_num(r, [("details", "meta", "gpu_s"), ("details", "usage", "gpu_s"), ("details", "gpu_s"), ("gpu_s",)]) or 0.0


def _spec_s(r, dec, pre):
    return first_num(r, [("gpu_s",)]) or 0.0


def _mut_s(r, dec, pre):
    return first_num(r, [("details", "gpu_s"), ("gpu_s",)]) or 0.0


def _explore_s(r, dec, pre):
    return num(r.get("secs"))


SKIP_ROW = {"token_ledger": token_excluded}

SOURCES = (
    ("outcomes", "outcomes.jsonl", lambda r: "dev", _outcome_s),
    ("token_ledger", "token_ledger.jsonl", lambda r: token_stage(r.get("source")), _token_s),
    ("qwen_explore", "qwen_explore.jsonl", lambda r: "research", _explore_s),
    ("reviewer", os.path.join("qa_shadow", "reviewer.jsonl"), lambda r: "reviewer", _reviewer_s),
    ("acceptance", os.path.join("qa_shadow", "acceptance.jsonl"), lambda r: "card", _card_s),
    ("spec_gate", "spec_gate.jsonl", lambda r: "spec_gate", _spec_s),
    ("mutation", os.path.join("qa_shadow", "mutation.jsonl"), lambda r: "mutation", _mut_s),
)


def head_of_ref(ref):
    ref = str(ref or "")
    return (ref.split("..")[-1] if ".." in ref else ref).strip()


def build_index(recs):
    """-> (feature key of every record key, index dicts by feat_tag / item_hash / commit prefix)."""
    feats = wc.build_features(recs)
    fk_of_rec, by_feat, by_hash, by_commit = {}, {}, {}, {}
    for f in feats:
        fk = "%s|%s" % (f["repo"], f["key"])
        for rk in f["rec_keys"]:
            fk_of_rec[rk] = fk
        for c in f["commits"]:
            by_commit[c[:10]] = fk
    for r in recs:
        fk = fk_of_rec[r["key"]]
        if r.get("feat_tag"):
            by_feat[(r["repo"], r["feat_tag"])] = fk
        if r.get("item_hash"):
            by_hash[(r["repo"], r["item_hash"])] = fk
    return feats, by_feat, by_hash, by_commit


def attribute(name, row, idx):
    """-> feature key or None."""
    _, by_feat, by_hash, by_commit = idx
    repo = row.get("repo")
    if name == "spec_gate":
        return by_feat.get((repo, row.get("feat")))
    if name in ("reviewer", "acceptance", "mutation"):
        h = head_of_ref(row.get("ref"))
        return by_commit.get(h[:10]) if len(h) >= 7 else None
    return None


def outcome_attr(row, idx):
    _, by_feat, by_hash, _c = idx
    repo = row.get("repo")
    k = None
    if row.get("item_hash"):
        k = by_hash.get((repo, row["item_hash"]))
    if k is None and row.get("feat_tag"):
        k = by_feat.get((repo, row["feat_tag"]))
    return k


def derive(state_dir, recs, now, days):
    """Pure over files + ledger records. -> dict {features, weeks, sources, rates, skipped}."""
    since = window_start(now, days)
    decode, prefill = rates(state_dir)
    idx = build_index(recs)
    feat_stage = collections.defaultdict(lambda: collections.defaultdict(float))
    feat_n = collections.Counter()
    week = collections.defaultdict(float)                    # (week, repo, stage) -> seconds
    cpu = collections.defaultdict(float)
    sources = {}
    skipped = 0
    for name, rel, stage_fn, sec_fn in SOURCES:
        s = {"rows": 0, "seconds": 0.0, "attributed_s": 0.0, "present": os.path.exists(os.path.join(state_dir, rel))}
        skip_fn = SKIP_ROW.get(name)
        for row in p5.read_jsonl(os.path.join(state_dir, rel)):
            if skip_fn and skip_fn(row):
                continue
            e = parse_epoch(row.get("ts"))
            sec = sec_fn(row, decode, prefill)
            if e is None or sec is None:
                skipped += 1
                continue
            if e < since or e > now + 3600:
                continue
            repo = row.get("repo") if ql.safe_name(row.get("repo")) else "?"
            stage = stage_fn(row)
            s["rows"] += 1
            s["seconds"] += sec
            week[(week_of(e), repo, stage)] += sec
            fk = outcome_attr(row, idx) if name == "outcomes" else attribute(name, row, idx)
            if fk:
                feat_stage[fk][stage] += sec
                feat_n[fk] += 1
                s["attributed_s"] += sec
            if name == "spec_gate":
                ms = num((row.get("exec") or {}).get("ms")) if isinstance(row.get("exec"), dict) else None
                if ms:
                    cpu[(week_of(e), repo)] += ms / 1000.0
        sources[name] = {k: (round(v, 3) if isinstance(v, float) else v) for k, v in s.items()}
    feats = []
    for f in idx[0]:
        fk = "%s|%s" % (f["repo"], f["key"])
        if f["epoch"] < since:
            continue
        st = {k: round(v, 3) for k, v in sorted(feat_stage.get(fk, {}).items())}
        feats.append({"kind": "feature", "key": fk, "repo": f["repo"], "feat_tag": "" if f["key"].startswith("rec:") else f["key"], "landed_ts": ql.iso(f["epoch"]),
                      "risk": f["risk"], "stages": st, "total_s": round(sum(st.values()), 3), "rows": feat_n.get(fk, 0)})
    landed_week = collections.Counter()
    landed_week_repo = collections.Counter()
    for f in idx[0]:
        if f["epoch"] >= since:
            landed_week[week_of(f["epoch"])] += 1
            landed_week_repo[(week_of(f["epoch"]), f["repo"])] += 1
    weeks = []
    for (w, repo, stage), sec in sorted(week.items()):
        weeks.append({"kind": "week", "key": "week|%s|%s|%s" % (w, repo, stage), "week": w, "repo": repo, "stage": stage, "seconds": round(sec, 3),
                      "landed": landed_week_repo.get((w, repo), 0)})
    return {"features": feats, "weeks": weeks, "weeks_landed": dict(landed_week), "sources": sources, "decode_tok_s": round(decode, 2),
            "prefill_tok_s": round(prefill, 1), "skipped_rows": skipped, "spec_gate_cpu_s": {"%s|%s" % k: round(v, 2) for k, v in cpu.items()}}


def weekly_table(d):
    """Markdown: one row per ISO week, minutes per landed feature by stage (all repos together; the per-repo rows are in the jsonl)."""
    tot = collections.defaultdict(lambda: collections.defaultdict(float))
    for r in d["weeks"]:
        tot[r["week"]][r["stage"]] += r["seconds"]
    out = ["| week | landed | " + " | ".join(STAGES) + " | total min | min / landed |", "|---|---:|" + "---:|" * (len(STAGES) + 2)]
    for w in sorted(tot):
        n = d["weeks_landed"].get(w, 0)
        cells = ["%.1f" % (tot[w].get(s, 0.0) / 60.0) for s in STAGES]
        total = sum(tot[w].values()) / 60.0
        out.append("| %s | %d | %s | %.1f | %s |" % (w, n, " | ".join(cells), total, ("%.2f" % (total / n)) if n else "n/a"))
    out.append("")
    out.append("stage minutes are TOTAL GPU minutes in the week (attributed + unattributed); min / landed = total / features landed that week. dev = outcome wall time + estimated planner tokens "
               "(decode %.1f tok/s, prefill %.0f tok/s); reviewer/card/mutation are measured gpu_s where the gate records it." % (d["decode_tok_s"], d["prefill_tok_s"]))
    return "\n".join(out)


def raw_totals(state_dir, now, days):
    """INDEPENDENT re-sum of each source straight from the files (does not use derive()/attribution/week bucketing)."""
    since = window_start(now, days)
    decode, prefill = rates(state_dir)
    out = {}
    for name, rel, stage_fn, sec_fn in SOURCES:
        t = 0.0
        skip_fn = SKIP_ROW.get(name)
        for row in p5.read_jsonl(os.path.join(state_dir, rel)):
            if skip_fn and skip_fn(row):
                continue
            e = parse_epoch(row.get("ts"))
            sec = sec_fn(row, decode, prefill)
            if e is None or sec is None or e < since or e > now + 3600:
                continue
            t += sec
        out[name] = t
    return out


def reconcile(d, state_dir, now, days):
    """Ledger weekly totals (summed over weeks/repos/stages) vs the raw source sums, per source and in total. ok when every one is within 1%."""
    raw = raw_totals(state_dir, now, days)
    led = sum(r["seconds"] for r in d["weeks"])
    src_led = sum(s["seconds"] for s in d["sources"].values())
    rt = sum(raw.values())
    per = {}
    ok = True
    for k, v in raw.items():
        got = d["sources"].get(k, {}).get("seconds", 0.0)
        rel = 0.0 if v == 0 and got == 0 else abs(got - v) / max(v, 1e-9)
        per[k] = {"raw_s": round(v, 3), "ledger_s": round(got, 3), "rel_err": round(rel, 6)}
        ok = ok and rel <= RECONCILE_TOL
    rel_total = 0.0 if rt == 0 and led == 0 else abs(led - rt) / max(rt, 1e-9)
    ok = ok and rel_total <= RECONCILE_TOL
    return {"ok": ok, "raw_total_s": round(rt, 3), "ledger_weekly_total_s": round(led, 3), "sources_total_s": round(src_led, 3), "rel_err_total": round(rel_total, 6), "per_source": per}


def merge_write(d, path):
    """Merge feature + week rows into the jsonl BY KEY (a recomputed key replaces its older row, keys not recomputed are kept) and rewrite atomically."""
    existing = collections.OrderedDict()
    for r in p5.read_jsonl(path):
        if isinstance(r.get("key"), str):
            existing[r["key"]] = r
    now_iso = ql.iso(int(time.time()))
    for r in d["features"] + d["weeks"]:
        old = existing.get(r["key"])
        if r.get("kind") == "week" and old and old.get("kind") == "week":
            # a week row never shrinks (logs are append-only: a smaller number means a narrower window or a rotated log, not less GPU time)
            r = dict(r, seconds=max(r["seconds"], old.get("seconds", 0) or 0), landed=max(r.get("landed", 0), old.get("landed", 0) or 0))
        existing[r["key"]] = dict(r, ts=now_iso)
    return p5.atomic_write(path, "".join(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n" for r in existing.values())), len(existing)


def cmd_run(argv, now=None):
    now = time.time() if now is None else now
    m = mode()
    if m == "off":
        return {"mode": "off", "wrote": 0}
    days = int(p5.opt(argv, "--days", "14") or 14)
    sd = qc.state_dir()
    recs, _evs = ql.load_ledger()
    d = derive(sd, recs, now, days)
    rec = reconcile(d, sd, now, days)
    wrote = 0
    if "--no-record" not in argv:
        okw, n = merge_write(d, p5.shadow_path("gpu_ledger.jsonl"))
        okm = p5.atomic_write(p5.shadow_path("gpu_ledger_weekly.md"), weekly_table(d) + "\n")
        wrote = int(okw) + int(okm)
    return {"mode": m, "wrote": wrote, "features": len(d["features"]), "week_rows": len(d["weeks"]), "sources": d["sources"], "reconcile": rec,
            "decode_tok_s": d["decode_tok_s"], "prefill_tok_s": d["prefill_tok_s"], "skipped_rows": d["skipped_rows"]}


def main(argv):
    cmd = argv[0] if argv else "run"
    rest = argv[1:]
    try:
        if cmd == "run":
            print(json.dumps(cmd_run(rest), sort_keys=True))
        elif cmd in ("report", "reconcile"):
            if mode() == "off":
                print("gpu_ledger: OVN_QA_GPU_LEDGER=off")
                return 0
            now, days, sd = time.time(), int(p5.opt(rest, "--days", "14") or 14), qc.state_dir()
            d = derive(sd, ql.load_ledger()[0], now, days)
            print(weekly_table(d) if cmd == "report" else json.dumps(reconcile(d, sd, now, days), indent=1, sort_keys=True))
        else:
            print(__doc__)
    except Exception as ex:  # noqa: BLE001
        print(json.dumps({"error": "%s: %s" % (type(ex).__name__, str(ex)[:200]), "mode": mode()}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
