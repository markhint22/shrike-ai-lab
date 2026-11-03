#!/usr/bin/env python3
"""qa_flag_sample.py - the hand-label worksheet for shadow-gate FLAGs (package K1, 2026-11-03). Read-only unless --write; never changes a gate mode.

Why: every gate's precision in ovn_gate_evidence_report.py is a PROXY (FLAG, then the work was later reverted/parked). item_verify / card_credit / red_before look
terrible on that proxy, but a flagged item is reverted for many reasons that have nothing to do with the gate, so the proxy can neither promote nor condemn a gate.
Only hand labels can. This lists, per gate, the N (default 40) MOST INFORMATIVE FLAG/FAIL events that nobody has labelled yet, so the scarce human minutes go where they
move the evidence most:

    qa_flag_sample.py [--gate G ...] [--limit 40] [--days 30] [--json] [--write] [--strict] [--state DIR]

Ordering (deterministic, no randomness):
  1. group the gate's unlabelled FLAG/FAIL events by SIGNATURE (antigaming: the rule ids in details.counts; card_credit: credit_without_card / card_existed; spec_gate: the rule in the
     action; else the first words of the summary) so every rule gets looked at, not only the noisiest one;
  2. inside a signature interleave the outcome buckets  blind (unjoined / unresolved: the proxy says nothing) -> green (proxy says false positive) -> bad (proxy says true
     positive), most recent first, so each signature calibrates the proxy in both directions;
  3. round-robin across signatures (largest first) and cut at --limit.
Already-labelled events (state/gate_governor/labels.jsonl, written by ovn_gate_governor.py label) are skipped, so re-running after labelling shows the NEXT 40.

Each line carries the exact command that records the verdict:   python3 scripts/ovn_gate_governor.py label <gate-id> <key> tp|fp --note "why"
(the key is the governor's own: line_key for qa_shadow rows, 'run:<file>' for the stage_event gates item_verify / red_before. spec_gate and executor:* are NOT in ops/gate_registry.json,
so the governor cannot take a label for them: the worksheet says so instead of printing a command that would raise KeyError).
--write stores the worksheet as state/qa_flag_sample/<gate>.json (the ONLY file this tool ever writes). qa/gold_set.json is NOT touched: its schema is replay-based (base/head/expect).

Pure stdlib. Exit 0 (2 on usage error)."""
import argparse
import collections
import hashlib
import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_reporter():
    spec = importlib.util.spec_from_file_location("ovn_gate_evidence_report", os.path.join(os.path.dirname(HERE), "ovn_gate_evidence_report.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


ger = _load_reporter()


def line_key(*parts):
    """Identical to ovn_gate_governor.line_key (so labels recorded from this worksheet are the governor's labels)."""
    return "l:" + hashlib.md5("|".join(str(p) for p in parts).encode()).hexdigest()[:10]


def gate_id(ev):
    return ("qa:" + ev.gate) if ev.src == "qa_shadow" else ev.gate


def registry_ids():
    """Gate ids the governor knows (ops/gate_registry.json): only those can take a `label` (find_gate raises KeyError otherwise)."""
    try:
        with open(os.path.join(os.path.dirname(HERE), "ops", "gate_registry.json")) as f:
            return {g["id"] for g in json.load(f).get("gates", [])}
    except (OSError, ValueError, KeyError, TypeError):
        return set()


def event_key(ev):
    """The key the governor's own record for this event carries (so `label` is counted by its labelled>=N criterion):
    qa_shadow rows (jsonl evidence)  -> line_key(gate_id, <gate>.jsonl, repo, ref|verify, ts)
    stage_event gates (item_verify, red_before) -> "run:<stage run file minus .jsonl>"  (ovn_gate_governor._c_stage_event)
    anything else (spec_gate, executor:*) has no governor record: the key is a stable worksheet id only (see labelable())."""
    if ev.src == "qa_shadow":
        r = ev.row
        return line_key(gate_id(ev), ev.gate + ".jsonl", r.get("repo", ""), r.get("ref") or r.get("verify") or "", r.get("ts"))
    if ev.src == "stage_runs" and ev.file:
        return "run:" + ev.file.replace(".jsonl", "")
    return line_key(gate_id(ev), ev.src, ev.repo, int(ev.ts), ev.feat or (ev.hashes[0] if ev.hashes else ""))


def labelable(ev, reg=None):
    return gate_id(ev) in (registry_ids() if reg is None else reg)


def signature(ev):
    r = ev.row or {}
    det = r.get("details") if isinstance(r.get("details"), dict) else {}
    if ev.gate == "antigaming":
        return "+".join(sorted((det.get("counts") or {}).keys())) or "none"
    if ev.gate == "card_credit":
        return "credit_without_card" if det.get("credit_without_card") else "card_existed" if det.get("card_existed") else "other"
    if ev.gate == "spec_gate":
        return str(r.get("action") or "?")
    if ev.gate in ("item_verify",):
        return str(r.get("decision") or "?")[:40]
    return " ".join(str(r.get("summary") or r.get("detail") or r.get("action") or "-").split()[:4])


def load_labels(sd):
    out = {}
    try:
        for ln in open(os.path.join(sd, "gate_governor", "labels.jsonl"), errors="replace"):
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if isinstance(r, dict) and r.get("gate") and r.get("key") and r.get("label") in ("tp", "fp"):
                out[(r["gate"], r["key"])] = r["label"]
    except OSError:
        pass
    return out


def rank(items, limit):
    """items: [(ev, bucket, sig)] -> the `limit` most informative, per the module docstring."""
    by_sig = collections.defaultdict(lambda: collections.defaultdict(list))
    for it in items:
        by_sig[it[2]][it[1]].append(it)
    queues = []
    for sig, bk in by_sig.items():
        for b in bk.values():
            b.sort(key=lambda x: -x[0].ts)
        order, n = [], 0
        while True:                                   # interleave blind -> green -> bad
            took = False
            for name in ("blind", "green", "bad"):
                if bk.get(name):
                    order.append(bk[name].pop(0))
                    took = True
            if not took:
                break
            n += 1
        queues.append((sig, order))
    queues.sort(key=lambda q: (-len(q[1]), q[0]))
    out = []
    while len(out) < limit and any(q[1] for q in queues):
        for sig, q in queues:
            if q and len(out) < limit:
                out.append(q.pop(0))
    return out


def sample(sd, days=30, gates=None, limit=40, strict=False, now=None, git=None):
    now = now if now is not None else float(os.environ.get("OVN_GER_NOW") or time.time())
    window_s, slack_s = ger.fnum("OVN_GER_WINDOW_H", 24) * 3600, ger.fnum("OVN_GER_SLACK_S", 900)
    since = now - days * 86400
    evs = [e for e in ger.load_qa_shadow(sd) + ger.load_spec_gate(sd) + ger.load_executor(sd) + ger.load_stage_events(sd) if e.ts >= since and e.cls in ger.FACING]
    if gates:
        evs = [e for e in evs if e.gate in gates]
    outs = ger.Outcomes(ger.read_jsonl(os.path.join(sd, "outcomes.jsonl")), git if git is not None else ger.Git())
    labels = load_labels(sd)
    per = collections.defaultdict(list)
    total = collections.Counter()
    labelled = collections.Counter()
    for e in evs:
        total[e.gate] += 1
        key = event_key(e)
        if (gate_id(e), key) in labels:
            labelled[e.gate] += 1
            continue
        res = ger.resolve(e, outs, now, window_s, slack_s, strict)
        bucket = "green" if res == "green" else "bad" if res == "bad" else "blind"
        per[e.gate].append((e, bucket, signature(e), key, res))
    report = {}
    reg = registry_ids()
    for g in sorted(per):
        pick = rank([(x[0], x[1], x[2]) for x in per[g]], limit)
        meta = {id(x[0]): x for x in per[g]}
        rows = []
        for e, bucket, sig in pick:
            _, _, _, key, res = meta[id(e)]
            r = e.row or {}
            lab_ok = labelable(e, reg)
            rows.append({"gate": gate_id(e), "key": key, "ts": ger.time.strftime(ger.TS_FMT, ger.time.gmtime(e.ts)), "repo": e.repo, "ref": str(r.get("ref") or r.get("item_key") or e.feat or "")[:90],
                         "signature": sig, "outcome": res, "joined_by": e.join or "", "summary": str(r.get("summary") or r.get("detail") or r.get("action") or "")[:160],
                         "labelable": lab_ok, "label_cmd": ("python3 scripts/ovn_gate_governor.py label %s %s tp|fp --note \"why\"" % (gate_id(e), key)) if lab_ok
                         else "(gate %s is not in ops/gate_registry.json: the governor cannot record a label for it; judge it by hand and note it in the worksheet)" % gate_id(e)})
        report[g] = {"flag_fail_events": total[g], "already_labelled": labelled[g], "unlabelled": len(per[g]), "listed": len(rows), "rows": rows}
    return report


def render(rep):
    L = []
    for g, d in sorted(rep.items()):
        L.append("== %s: %d FLAG/FAIL events, %d already labelled, %d unlabelled; the %d most informative to label ==" % (g, d["flag_fail_events"], d["already_labelled"], d["unlabelled"], d["listed"]))
        for i, r in enumerate(d["rows"], 1):
            L.append("%2d. [%s] %s %s  sig=%s outcome=%s(%s)\n      %s\n      %s" % (i, r["key"], r["ts"], r["repo"], r["signature"], r["outcome"], r["joined_by"] or "-", r["summary"], r["label_cmd"]))
        L.append("")
    return "\n".join(L).rstrip() or "no unlabelled FLAG/FAIL events"


def main(argv=None):
    ap = argparse.ArgumentParser(description="most informative unlabelled FLAGs per gate (hand-label worksheet)")
    ap.add_argument("--gate", action="append")
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--state")
    a = ap.parse_args(argv)
    sd = ger.state_dir(a.state)
    rep = sample(sd, a.days, set(a.gate) if a.gate else None, a.limit, a.strict)
    if a.write:
        d = os.path.join(sd, "qa_flag_sample")
        os.makedirs(d, exist_ok=True)
        for g, v in rep.items():
            with open(os.path.join(d, g.replace(":", "_") + ".json"), "w") as f:
                json.dump(v, f, indent=1, sort_keys=True)
    print(json.dumps(rep, indent=1, sort_keys=True) if a.json else render(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
