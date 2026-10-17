#!/usr/bin/env python3
"""qa_gate_precision.py - S8 reviewer label-bar tracker + monthly per-gate 'verdict rule' table (plan section 7, Phase 3). Read-only, advisory.

    qa_gate_precision.py [precision] [--json]            labelled count, precision and whether the bar is met
    qa_gate_precision.py verdict-rule [--month YYYY-MM] [--json]   catches per GPU-minute / CPU-minute for every gate

precision: reads state/qa_shadow/reviewer.jsonl + state/qa_reviewer_labels.jsonl (written by qa_reviewer_label.py; its report logic is REUSED,
there is one definition of a label). The bar before the reviewer may influence anything: >= 50 labelled (decisive TP/FP) findings AND >= 60%
precision. Below 50 it prints "bar NOT MET (insufficient sample)" and never a percentage dressed up as a result; with 0 labels it says exactly that.

verdict-rule: for each state/qa_shadow/<gate>.jsonl row in the month, `catches` = rows whose verdict is FLAG or FAIL; minutes = sum(ms)/60000, counted
as GPU minutes for the gates in OVN_QA_GPU_GATES (default: reviewer) and CPU minutes for the rest (a gate row may carry details.cpu_s, which wins for
CPU gates: wall time on a shared box is inflated by contention). The `rule` column is a SUGGESTION for the monthly review, never an action:
  insufficient data  fewer than QA_RULE_MIN_RUNS (20) scored runs
  retire?            >= QA_RULE_MIN_MINUTES (10) minutes spent and 0 catches
  weak               at least one catch, but catches per minute below QA_RULE_MIN_RATE (0.05)  (an always-green gate with little time spent is `keep`, not weak)
  keep               otherwise
  advisory           gates in OVN_QA_ADVISORY_GATES (default: mutation): their FLAG is a finding (survivors), PASS is the good outcome, so no retire?/weak suggestion is made
The `skipped` column counts state/qa_gate_skips.jsonl rows (a daily gate that was skipped: tooling missing, load, budget); a gate that ONLY skipped is listed as "no runs (N skipped)".
UNVERIFIED rows are counted separately (a gate that cannot run catches nothing but is not 'clean'). Never raises, exit 0 (2 on usage error).
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_reviewer_label as rl  # noqa: E402

MIN_LABELLED = rl.MIN_DECISIVE
BAR_PRECISION = rl.BAR_PRECISION


def num(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def precision_report():
    rep = rl.build_report()
    n_dec = rep["decisive"]
    met = bool(n_dec >= MIN_LABELLED and rep["precision"] is not None and rep["precision"] >= BAR_PRECISION)
    out = {"findings": rep["findings"], "labelled": rep["labelled"], "decisive": n_dec, "tp": rep["tp"], "fp": rep["fp"], "unclear": rep["unclear"],
           "precision": rep["precision"], "ci95": rep["ci95"], "bar_labelled": MIN_LABELLED, "bar_precision": BAR_PRECISION, "bar_met": met,
           "reviewer_runs": rep["totals"]["runs"], "reviewer_verdicts": rep["totals"]["verdicts"]}
    if met:
        out["status"] = "MET"
    elif n_dec < MIN_LABELLED:
        out["status"] = "NOT MET (insufficient sample: %d of %d decisive labels)" % (n_dec, MIN_LABELLED)
    else:
        out["status"] = "NOT MET (precision %.1f%% < %d%%)" % (rep["precision"] * 100, int(BAR_PRECISION * 100))
    return out


def print_precision(rep):
    print("reviewer runs: %d %s" % (rep["reviewer_runs"], json.dumps(rep["reviewer_verdicts"], sort_keys=True)))
    print("findings recorded: %d | labelled: %d (TP %d, FP %d, unclear %d; decisive %d)" % (rep["findings"], rep["labelled"], rep["tp"], rep["fp"],
                                                                                          rep["unclear"], rep["decisive"]))
    if rep["precision"] is None:
        print("precision: n/a (%d decisive labels; a percentage needs >= %d)" % (rep["decisive"], rep["bar_labelled"]))
    else:
        print("precision: %.1f%% (95%% CI %.0f-%.0f%%, n=%d)" % (rep["precision"] * 100, rep["ci95"][0] * 100, rep["ci95"][1] * 100, rep["decisive"]))
    print("bar (>= %d labelled AND >= %d%% precision): %s" % (rep["bar_labelled"], int(rep["bar_precision"] * 100), rep["status"]))


# ----------------------------------------------------------------------------------------------------------------- verdict rule
def gpu_gates():
    return set((os.environ.get("OVN_QA_GPU_GATES") or "reviewer").replace(",", " ").split())


def month_of(ts):
    try:
        t = time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        return "%04d-%02d" % (t.tm_year, t.tm_mon)
    except (TypeError, ValueError):
        return None


def gate_rows():
    d = os.path.join(qc.state_dir(), "qa_shadow")
    try:
        names = sorted(f for f in os.listdir(d) if f.endswith(".jsonl"))
    except OSError:
        return {}
    res = {}
    for f in names:
        rows = [r for r in rl.read_jsonl(os.path.join(d, f)) if r.get("verdict") and month_of(r.get("ts"))]
        if rows:
            res[f[:-6]] = rows
    return res


def advisory_gates():
    """Gates whose FLAG is a finding to read (survivors), not a catch of something wrong: catches/retire/weak do not apply to them."""
    return set((os.environ.get("OVN_QA_ADVISORY_GATES") or "mutation").replace(",", " ").split())


def rule_for(runs, catches, minutes):
    if runs < num("QA_RULE_MIN_RUNS", 20):
        return "insufficient data"
    if catches == 0 and minutes >= num("QA_RULE_MIN_MINUTES", 10):
        return "retire?"
    # `weak` needs at least one catch: a gate that is simply always green (0 catches, little time spent) is not weak, it has not been tested by a bad input yet
    if catches > 0 and minutes > 0 and catches / minutes < num("QA_RULE_MIN_RATE", 0.05):
        return "weak"
    return "keep"


def read_skips(month):
    """{gate: count} of state/qa_gate_skips.jsonl rows in `month` (written by gates that skip a pass: gate_mutation.py)."""
    res = {}
    for r in rl.read_jsonl(os.path.join(qc.state_dir(), "qa_gate_skips.jsonl")):
        if isinstance(r, dict) and r.get("gate") and month_of(r.get("ts")) == month:
            res[r["gate"]] = res.get(r["gate"], 0) + 1
    return res


def verdict_rule(month=None):
    month = month or time.strftime("%Y-%m", time.gmtime())
    gpu = gpu_gates()
    advisory = advisory_gates()
    skips = read_skips(month)
    table = []
    seen = set()
    for gate, rows in sorted(gate_rows().items()):
        rs = [r for r in rows if month_of(r.get("ts")) == month]
        if not rs:
            continue
        seen.add(gate)
        scored = [r for r in rs if r["verdict"] in ("PASS", "FLAG", "FAIL")]
        catches = sum(1 for r in scored if r["verdict"] in ("FLAG", "FAIL"))
        unver = sum(1 for r in rs if r["verdict"] == "UNVERIFIED")
        is_gpu = gate in gpu
        secs = 0.0
        for r in rs:
            cpu = (r.get("details") or {}).get("cpu_s") if isinstance(r.get("details"), dict) else None
            if not is_gpu and isinstance(cpu, (int, float)):
                secs += float(cpu)
            elif isinstance(r.get("ms"), (int, float)):
                secs += r["ms"] / 1000.0
        minutes = secs / 60.0
        kind = "GPU" if is_gpu else "CPU"
        rule = rule_for(len(scored), catches, minutes)
        if gate in advisory and rule != "insufficient data":
            rule = "advisory (FLAG = survivors, not catches)"
        table.append({"gate": gate, "kind": kind, "runs": len(rs), "scored": len(scored), "catches": catches, "unverified": unver,
                      "skipped": skips.get(gate, 0), "minutes": round(minutes, 2),
                      "catches_per_min": round(catches / minutes, 3) if minutes > 0 else None, "rule": rule})
    for gate, n in sorted(skips.items()):    # a gate that only ever SKIPS has no shadow rows: still list it, so a dead gate is visible
        if gate not in seen:
            table.append({"gate": gate, "kind": "GPU" if gate in gpu else "CPU", "runs": 0, "scored": 0, "catches": 0, "unverified": 0, "skipped": n,
                          "minutes": 0.0, "catches_per_min": None, "rule": "no runs (%d skipped)" % n})
    return {"month": month, "gates": table}


def print_rule(rep):
    print("verdict rule, %s (catches = FLAG|FAIL rows; minutes = GPU for %s, CPU for the rest; the rule column is a suggestion)" %
          (rep["month"], ",".join(sorted(gpu_gates())) or "-"))
    print("%-18s %-4s %5s %6s %7s %5s %7s %9s %12s  %s" % ("gate", "kind", "runs", "scored", "catches", "unver", "skipped", "minutes", "catches/min", "rule"))
    for g in rep["gates"]:
        cpm = "-" if g["catches_per_min"] is None else "%.3f" % g["catches_per_min"]
        print("%-18s %-4s %5d %6d %7d %5d %7d %9.2f %12s  %s" % (g["gate"], g["kind"], g["runs"], g["scored"], g["catches"], g["unverified"], g.get("skipped", 0), g["minutes"], cpm, g["rule"]))
    if not rep["gates"]:
        print("(no shadow rows in %s)" % rep["month"])


def main(argv):
    cmd = argv[0] if argv and not argv[0].startswith("--") else "precision"
    rest = argv[1:] if argv and not argv[0].startswith("--") else argv
    as_json = "--json" in rest
    if cmd == "precision":
        rep = precision_report()
        if as_json:
            print(json.dumps(rep, sort_keys=True))
        else:
            print_precision(rep)
        return 0
    if cmd == "verdict-rule":
        month = rest[rest.index("--month") + 1] if "--month" in rest and rest.index("--month") + 1 < len(rest) else None
        if month and not (len(month) == 7 and month[4] == "-" and month[:4].isdigit() and month[5:].isdigit()):
            print("usage: verdict-rule [--month YYYY-MM] [--json]", file=sys.stderr)
            return 2
        rep = verdict_rule(month)
        if as_json:
            print(json.dumps(rep, sort_keys=True))
        else:
            print_rule(rep)
        return 0
    print(__doc__)
    return 2 if cmd not in ("help", "-h", "--help") else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
