#!/usr/bin/env python3
"""qa_reviewer_label.py - label the advisory reviewer's findings TP/FP/unclear and measure its precision (plan section 7, Phase 3).

    qa_reviewer_label.py list   [--unlabelled] [--limit N]
    qa_reviewer_label.py label  --id <finding id> --label TP|FP|unclear [--note TEXT]
    qa_reviewer_label.py report [--json]

State (under $OVN_DIR/state only):
    qa_shadow/reviewer.jsonl      read-only: the gate's results; each surviving finding has a stable 12-hex `id`
    qa_reviewer_labels.jsonl      append-only: {ts, id, label, note, repo, file}; the LATEST label per id wins
    qa_ledger.jsonl               read-only: later revert/hotfix/escape events, joined to SUGGEST true positives

The bar before the reviewer may influence anything (docs/QA_PLAN_2026-10-01.md section 7): >= 50 labelled findings AND >= 60% precision.
So `report` REFUSES to print a percentage until there are 50 decisive (TP or FP) labels; `unclear` never counts toward either side.
Ledger-based suggestions (a revert / hotfix / escape touching the same file within 7 days AFTER the finding) are only SUGGESTIONS: they are
never counted as labels - a human confirms them with `label`. Never raises into a pipeline: it is a manual tool, exit 2 on usage errors.
"""
import calendar
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

MIN_DECISIVE = 50
BAR_PRECISION = 0.60
WINDOW_DAYS = 7
DAY = 86400
LABELS = ("TP", "FP", "unclear")
EVENT_TYPES = ("revert", "hotfix", "escape")


def paths():
    s = qc.state_dir()
    return {"shadow": os.path.join(s, "qa_shadow", "reviewer.jsonl"), "labels": os.path.join(s, "qa_reviewer_labels.jsonl"),
            "ledger": os.path.join(s, "qa_ledger.jsonl")}


def read_jsonl(p):
    rows = []
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict):
                    rows.append(d)
    except OSError:
        pass
    return rows


def epoch_of(ts):
    try:
        return calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
    except (TypeError, ValueError):
        return None


def findings():
    """Every surviving finding ever recorded: {id, repo, file, line, claim, severity, epoch, ts, ref}. First record of an id wins."""
    out, seen = [], set()
    for r in read_jsonl(paths()["shadow"]):
        if r.get("gate") != "reviewer":
            continue
        for f in (r.get("details") or {}).get("findings") or []:
            fid = f.get("id")
            if not fid or fid in seen:
                continue
            seen.add(fid)
            out.append({"id": fid, "repo": r.get("repo"), "file": f.get("file"), "line": f.get("line"), "claim": f.get("claim", ""),
                        "severity": f.get("severity"), "ts": r.get("ts"), "epoch": epoch_of(r.get("ts")), "ref": r.get("ref")})
    return out


def latest_labels():
    cur = {}
    for r in read_jsonl(paths()["labels"]):
        if r.get("id") and r.get("label") in LABELS:
            cur[r["id"]] = r
    return cur


def wilson(tp, n, z=1.96):
    if n <= 0:
        return None
    p = tp / float(n)
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return max(0.0, (c - m) / d), min(1.0, (c + m) / d)


def ledger_evidence(fs):
    """id -> [evidence]: ledger events of type revert/hotfix/escape, same repo, touching the same file, 0 < t_event - t_finding <= 7 days."""
    led = read_jsonl(paths()["ledger"])
    landed = {r.get("key"): r for r in led if r.get("kind") == "landed"}
    events = []
    for e in led:
        if e.get("kind") != "event" or e.get("type") not in EVENT_TYPES:
            continue
        files = set(e.get("overlap") or []) | set(e.get("files") or [])
        if not files and e.get("rec") in landed:            # reverts carry no files: take them from the landed record they undo
            files = set(landed[e["rec"]].get("files") or [])
        try:
            ep = int(e.get("epoch"))
        except (TypeError, ValueError):
            continue
        events.append((e, files, ep))
    res = {}
    for f in fs:
        if f["epoch"] is None or not f["file"]:
            continue
        ev = []
        for e, files, ep in events:
            if e.get("repo") != f["repo"] or f["file"] not in files:
                continue
            dt = ep - f["epoch"]
            if 0 < dt <= WINDOW_DAYS * DAY:
                ev.append({"type": e.get("type"), "ref": str(e.get("ref") or "")[:12], "days_after": round(dt / float(DAY), 2),
                           "confidence": e.get("confidence"), "note": str(e.get("note") or "")[:120]})
        if ev:
            res[f["id"]] = ev
    return res


def build_report():
    fs = findings()
    lab = latest_labels()
    known = {f["id"] for f in fs}
    mine = {i: r for i, r in lab.items() if i in known}
    tp = sum(1 for r in mine.values() if r["label"] == "TP")
    fp = sum(1 for r in mine.values() if r["label"] == "FP")
    un = sum(1 for r in mine.values() if r["label"] == "unclear")
    dec = tp + fp
    rep = {"findings": len(fs), "labelled": len(mine), "tp": tp, "fp": fp, "unclear": un, "decisive": dec, "min_decisive": MIN_DECISIVE,
           "precision": None, "ci95": None, "bar_met": None}
    if dec >= MIN_DECISIVE:
        rep["precision"] = round(tp / float(dec), 4)
        lo, hi = wilson(tp, dec)
        rep["ci95"] = [round(lo, 4), round(hi, 4)]
        rep["bar_met"] = rep["precision"] >= BAR_PRECISION
    unl = [f for f in fs if f["id"] not in mine]
    ev = ledger_evidence(unl)
    rep["suggested_tp"] = [{"id": f["id"], "repo": f["repo"], "file": f["file"], "claim": f["claim"][:160], "evidence": ev[f["id"]]} for f in unl if f["id"] in ev]
    runs = [r for r in read_jsonl(paths()["shadow"]) if r.get("gate") == "reviewer"]
    tot = {"runs": len(runs), "proposed": 0, "verified": 0, "survived": 0}
    verd = {}
    for r in runs:
        c = (r.get("details") or {}).get("counts") or {}
        for k in ("proposed", "verified", "survived"):
            tot[k] += int(c.get(k) or 0)
        verd[r.get("verdict")] = verd.get(r.get("verdict"), 0) + 1
    tot["verdicts"] = verd
    rep["totals"] = tot
    return rep


def cmd_report(args):
    rep = build_report()
    if "--json" in args:
        print(json.dumps(rep, sort_keys=True))
        return 0
    t = rep["totals"]
    print("reviewer runs: %d %s | model proposed %d, harness-verified %d, survived the refuter %d" % (t["runs"], json.dumps(t["verdicts"], sort_keys=True),
                                                                                                    t["proposed"], t["verified"], t["survived"]))
    print("findings recorded: %d | labelled: %d (TP %d, FP %d, unclear %d; decisive %d)" % (rep["findings"], rep["labelled"], rep["tp"], rep["fp"],
                                                                                          rep["unclear"], rep["decisive"]))
    if rep["precision"] is None:
        print("precision: not computed (n=%d decisive labels < %d required; a percentage on this few labels would mislead)" % (rep["decisive"], MIN_DECISIVE))
        print("bar (>= %d labelled AND >= %d%% precision): INSUFFICIENT SAMPLE - the reviewer may influence nothing" % (MIN_DECISIVE, int(BAR_PRECISION * 100)))
    else:
        print("precision: %.1f%% (95%% CI %.0f-%.0f%%, n=%d decisive labels; unclear excluded)" % (rep["precision"] * 100, rep["ci95"][0] * 100,
                                                                                               rep["ci95"][1] * 100, rep["decisive"]))
        print("bar (>= %d labelled AND >= %d%% precision): %s" % (MIN_DECISIVE, int(BAR_PRECISION * 100), "MET" if rep["bar_met"] else "NOT MET"))
    if rep["suggested_tp"]:
        print("\nsuggested TP (unlabelled; a revert/hotfix/escape touched the same file within %d days AFTER the finding - confirm with `label`, NOT counted):" % WINDOW_DAYS)
        for s in rep["suggested_tp"]:
            e = s["evidence"][0]
            print("  %s  %s %s  <- %s %s +%sd (%s)" % (s["id"], s["repo"], s["file"], e["type"], e["ref"], e["days_after"], e.get("confidence") or "-"))
    return 0


def cmd_list(args):
    fs = findings()
    lab = latest_labels()
    lim = 50
    if "--limit" in args:
        try:
            lim = int(args[args.index("--limit") + 1])
        except (ValueError, IndexError):
            pass
    n = 0
    for f in reversed(fs):
        if "--unlabelled" in args and f["id"] in lab:
            continue
        print("%s  %-9s %s:%s [%s] %s  | %s" % (f["id"], (lab.get(f["id"]) or {}).get("label", "-"), f["file"], f["line"], f["severity"], f["repo"], f["claim"][:140]))
        n += 1
        if n >= lim:
            break
    return 0


def cmd_label(args):
    def opt(name):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else None
    fid, lab, note = opt("--id"), opt("--label"), opt("--note") or ""
    if not fid or lab not in LABELS:
        print("usage: qa_reviewer_label.py label --id <finding id> --label TP|FP|unclear [--note TEXT]", file=sys.stderr)
        return 2
    f = next((x for x in findings() if x["id"] == fid), None)
    if f is None:
        print("unknown finding id %r (see `list`); nothing stored" % fid, file=sys.stderr)
        return 2
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "id": fid, "label": lab, "note": note[:300], "repo": f["repo"], "file": f["file"]}
    p = paths()["labels"]
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "a") as fh:
        fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    print("labelled %s %s (%s:%s)" % (fid, lab, f["file"], f["line"]))
    return 0


def main(argv):
    if not argv or argv[0] not in ("list", "label", "report"):
        print(__doc__, file=sys.stderr)
        return 2
    return {"list": cmd_list, "label": cmd_label, "report": cmd_report}[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
