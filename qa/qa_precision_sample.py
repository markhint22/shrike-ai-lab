#!/usr/bin/env python3
"""qa_precision_sample.py - labelled-precision harness for the antigaming SUB-KEYS (package Y5, 2026-11-04). Read-only: it never writes a label, never changes a gate mode.

Why: the antigaming proxy precision (reverted/parked vs landed) is 0.33 and cannot promote or condemn a rule. Only hand labels can (qa/qa_flag_sample.py does that per
GATE; this script does it per SUB-KEY, i.e. per rule family such as skip_added / assert_drop, so the new Y5 rules are judged on their own).

    qa_precision_sample.py sample [--subkey K ...] [--n 10] [--days 60] [--excerpt-lines 24] [--json] [--state DIR]
        per sub-key: the N most RECENT unlabelled antigaming FLAG rows whose details.counts contain that sub-key's rule, each with repo, commit sha (head of the range),
        the finding (file:line, message), a diff excerpt (git diff of that file over the row's range from a local clone, read-only; falls back to the finding's snippet
        when no clone / commit is available) and the ONE-LINE command that records the verdict:
            python3 scripts/ovn_gate_governor.py label qa:antigaming <key> tp|fp --note "why"
    qa_precision_sample.py read [--subkey K ...] [--days 60] [--json] [--state DIR]
        labelled precision per sub-key from state/gate_governor/labels.jsonl:  tp / (tp + fp).  An UNLABELLED row is NEVER counted as tp or fp (it is reported as
        `unlabelled` and excluded from the denominator); precision is None (n/a) with zero labels. A label that is neither tp nor fp is ignored.

The governor label key is per ROW (one antigaming run), not per finding: a row that carries two sub-keys has ONE verdict that counts for both (flagged `shared_label` in
the output). Label such a row only if the verdict is the same for both findings; otherwise skip it (the worksheet lists single-sub-key rows first).
Pure stdlib. Exit 0 (2 on usage error)."""
import argparse
import collections
import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

ger = _load("ovn_gate_evidence_report", os.path.join(OVN, "ovn_gate_evidence_report.py"))
fs = _load("qa_flag_sample", os.path.join(HERE, "qa_flag_sample.py"))

GATE = "antigaming"
RULE_OF = dict((v, k) for k, v in qc.GATE_SUBKEYS[GATE].items())   # sub-key -> rule id


def _events(sd, days, now=None):
    now = now if now is not None else float(os.environ.get("OVN_GER_NOW") or time.time())
    since = now - days * 86400
    return [e for e in ger.load_qa_shadow(sd) if e.gate == GATE and e.cls in ger.FACING and e.ts >= since]


def _subkeys(ev):
    det = ev.row.get("details") if isinstance(ev.row.get("details"), dict) else {}
    return sorted(set(qc.GATE_SUBKEYS[GATE][r] for r in (det.get("counts") or {}) if r in qc.GATE_SUBKEYS[GATE]))


def _excerpt(ev, rule, n):
    """(excerpt, source) for the first finding of `rule` in the row: git diff of its file over the row's base..head, else the recorded snippet."""
    det = ev.row.get("details") if isinstance(ev.row.get("details"), dict) else {}
    fnd = next((f for f in (det.get("findings") or []) if isinstance(f, dict) and f.get("rule") == rule), None)
    if not fnd:
        return "", "no finding recorded (details.findings truncated)", None
    base, head = ev.base, ger.head_of(ev.row.get("ref"))
    rd = qc.repo_dir(ev.repo) if ev.repo else None
    if rd and head and base:
        rc, out, _ = qc.git(rd, "diff", "--no-color", "-U2", base, head, "--", fnd.get("file", ""), timeout=30)
        if rc == 0 and out.strip():
            return "\n".join(out.splitlines()[:n]), "git diff %s..%s" % (base[:10], head[:10]), fnd
    elif rd and head:
        rc, out, _ = qc.git(rd, "show", "--no-color", "-U2", "--format=", head, "--", fnd.get("file", ""), timeout=30)
        if rc == 0 and out.strip():
            return "\n".join(out.splitlines()[:n]), "git show %s" % head[:10], fnd
    return str(fnd.get("snip") or ""), "recorded snippet (no clone/commit)", fnd


def sample(sd, subkeys=None, n=10, days=60, excerpt_lines=24, now=None):
    labels = fs.load_labels(sd)
    by = collections.defaultdict(list)
    labelled = collections.Counter()
    total = collections.Counter()
    for e in _events(sd, days, now):
        key = fs.event_key(e)
        for sk in _subkeys(e):
            if subkeys and sk not in subkeys:
                continue
            total[sk] += 1
            if (fs.gate_id(e), key) in labels:
                labelled[sk] += 1
            else:
                by[sk].append((e, key))
    rep = {}
    for sk in sorted(set(qc.GATE_SUBKEYS[GATE].values()) if not subkeys else set(subkeys)):
        rows = sorted(by.get(sk, []), key=lambda x: (len(_subkeys(x[0])), -x[0].ts))[:n]   # single-sub-key rows first, then most recent
        out = []
        for e, key in rows:
            ex, src, fnd = _excerpt(e, RULE_OF.get(sk, ""), excerpt_lines)
            out.append({"key": key, "ts": ger.time.strftime(ger.TS_FMT, ger.time.gmtime(e.ts)), "repo": e.repo, "sha": ger.head_of(e.row.get("ref")), "base": e.base,
                        "subkey": sk, "shared_label": len(_subkeys(e)) > 1,
                        "finding": "%s:%s %s" % (fnd.get("file"), fnd.get("line"), fnd.get("msg")) if fnd else "",
                        "excerpt": ex, "excerpt_source": src,
                        "label_cmd": "python3 scripts/ovn_gate_governor.py label %s %s tp|fp --note \"why\"" % (fs.gate_id(e), key)})
        rep[sk] = {"events": total[sk], "already_labelled": labelled[sk], "unlabelled": len(by.get(sk, [])), "listed": len(out), "rows": out}
    return rep


def read(sd, subkeys=None, days=60, now=None):
    """Labelled precision per sub-key. tp/fp come ONLY from explicit hand labels; unlabelled rows are counted separately and never enter the ratio."""
    labels = fs.load_labels(sd)
    tp, fp, un = collections.Counter(), collections.Counter(), collections.Counter()
    for e in _events(sd, days, now):
        key = fs.event_key(e)
        lab = labels.get((fs.gate_id(e), key))
        for sk in _subkeys(e):
            if subkeys and sk not in subkeys:
                continue
            if lab == "tp":
                tp[sk] += 1
            elif lab == "fp":
                fp[sk] += 1
            else:
                un[sk] += 1
    out = {}
    for sk in sorted(set(qc.GATE_SUBKEYS[GATE].values()) if not subkeys else set(subkeys)):
        d = tp[sk] + fp[sk]
        out[sk] = {"tp": tp[sk], "fp": fp[sk], "labelled": d, "unlabelled": un[sk],
                   "precision": None if d == 0 else round(float(tp[sk]) / d, 3)}
    return out


def render_sample(rep):
    L = []
    for sk, d in sorted(rep.items()):
        L.append("== sub-key %s: %d event(s), %d already labelled, %d unlabelled; listing %d ==" % (sk, d["events"], d["already_labelled"], d["unlabelled"], d["listed"]))
        for i, r in enumerate(d["rows"], 1):
            L.append("%2d. %s %s sha=%s%s\n    %s" % (i, r["ts"], r["repo"], r["sha"][:12], "  [shared label: row has 2 sub-keys]" if r["shared_label"] else "", r["finding"]))
            L.append("    excerpt (%s):" % r["excerpt_source"])
            L += ["      " + x for x in r["excerpt"].splitlines()]
            L.append("    " + r["label_cmd"])
        L.append("")
    return "\n".join(L).rstrip() or "no sub-key events"


def render_read(rep):
    f = lambda v: "n/a" if v is None else "%g" % v  # noqa: E731
    return "\n".join("%-12s labelled=%d (tp %d, fp %d)  unlabelled=%d (never counted)  labelled precision %s" % (
        sk, d["labelled"], d["tp"], d["fp"], d["unlabelled"], f(d["precision"])) for sk, d in sorted(rep.items()))


def main(argv=None):
    ap = argparse.ArgumentParser(description="labelled precision per antigaming sub-key")
    sub = ap.add_subparsers(dest="cmd")
    for name in ("sample", "read"):
        p = sub.add_parser(name)
        p.add_argument("--subkey", action="append")
        p.add_argument("--days", type=int, default=60)
        p.add_argument("--json", action="store_true")
        p.add_argument("--state")
        if name == "sample":
            p.add_argument("--n", type=int, default=10)
            p.add_argument("--excerpt-lines", type=int, default=24)
    a = ap.parse_args(argv)
    if a.cmd not in ("sample", "read"):
        ap.print_usage(sys.stderr)
        return 2
    known = set(qc.GATE_SUBKEYS[GATE].values())
    if a.subkey and not set(a.subkey) <= known:
        print("unknown sub-key; known: %s" % ", ".join(sorted(known)), file=sys.stderr)
        return 2
    sd = ger.state_dir(a.state)
    sk = set(a.subkey) if a.subkey else None
    if a.cmd == "sample":
        rep = sample(sd, sk, a.n, a.days, a.excerpt_lines)
        print(json.dumps(rep, indent=1, sort_keys=True) if a.json else render_sample(rep))
    else:
        rep = read(sd, sk, a.days)
        print(json.dumps(rep, indent=1, sort_keys=True) if a.json else render_read(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
