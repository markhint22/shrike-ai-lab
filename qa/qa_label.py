#!/usr/bin/env python3
"""qa_label.py - label ANY gate's findings TP/FP/unclear by (gate, rule, id) and measure precision per rule (plan section 7 / analysis F9, 2026-10-10).

Generalises qa_reviewer_label.py (which only knew the reviewer and stays untouched; its labels in state/qa_reviewer_labels.jsonl are read here as
gate=reviewer, rule='-'). Why: antigaming FLAG rules (D_DEAD_SYMBOL 21, F_CLAIM_TEST_ONLY 17, E_TEST_NOT_COLLECTED 24 in 5 days) and scanner / gdparse
findings had no labels at all, so none of them could ever be promoted, and the reviewer's ~1 survivor/day would need ~45 days to reach 50 labels.

    qa_label.py list     [--gate G] [--rule R] [--unlabelled] [--candidates-only] [--limit N]
    qa_label.py label    --gate G --id ID --label TP|FP|unclear [--rule R] [--note TEXT]
    qa_label.py suggest  --gate G --id ID --label TP|FP|unclear --evidence TEXT   (a PRE-READ by Claude: stored apart, NEVER counted)
    qa_label.py report   [--gate G] [--rule R] [--json]
    qa_label.py harvest  --gate G --repo R [--days 60] [--sample 400] [--branch origin/develop] [--seed 1] [--budget-s 3600]
                         [--dry-run] [--ignore-gpu] [--no-record]

State (all under $QA_STATE_DIR | $OVN_DIR/state; nothing else is ever written):
    qa_shadow/<gate>.jsonl      read-only: shadow rows; findings come from details.findings | details.new | details.parse_errors
    qa_label_candidates.jsonl   written ONLY by `harvest` (findings from a historical replay, one row per distinct finding id)
    qa_labels.jsonl             append-only {ts, gate, rule, id, label, note, repo, file, claim, suggested?}; the LATEST label per (gate, rule, id) wins
    qa_label_suggestions.jsonl  append-only {ts, gate, rule, id, label, evidence}: pre-reads. Shown next to the finding, never counted as a label
    qa_reviewer_labels.jsonl    read-only legacy labels (reviewer)
    qa_ledger.jsonl             read-only: later revert/hotfix/escape events, joined to SUGGEST true positives (same rule as qa_reviewer_label.py)

THE BAR (unchanged, docs/QA_PLAN_2026-10-01.md section 7): a (gate, rule) may influence anything only with >= 50 DECISIVE (TP or FP) labels AND >= 60% precision;
the 95% Wilson interval is always printed next to the percentage and its lower bound is what a promotion decision should read. Below 50 decisive labels `report`
REFUSES to print a percentage ("INSUFFICIENT SAMPLE"): a rate on 7 labels misleads. `unclear` counts toward neither side. Even a met bar never flips anything by
itself: this tool only measures. The per-GATE line shows counts only when the gate has more than one rule (no pooled percentage, no pooled bar verdict). A finding id is stable across re-runs: the gate's own `id` when it has one (reviewer), else sha1(gate|repo|rule|file|normalised
message)[:12] (no commit and no line number, so the same finding seen in two overlapping ranges is ONE labelling job).

`harvest` builds a labelling sample from history: a seeded random sample of the repo's non-merge commits in the window, each replayed through
qa_replay.replay_commit (the gate runs with --no-record, in a SCRATCH OVN_DIR/QA_STATE_DIR, niced via qa_common.run), findings appended to qa_label_candidates.jsonl.
The reviewer needs the GPU: for a model gate harvest refuses unless nvidia-smi reports <= QA_LABEL_GPU_IDLE_PCT (30) % utilisation (or --ignore-gpu). Hard budget
--budget-s; a partial harvest says so. Manual tool, exit 0 on success, 2 on usage errors, 3 when it refused to run (GPU busy / no clone)."""
import hashlib
import json
import os
import random
import re
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import qa_reviewer_label as rl  # noqa: E402  (REUSED: wilson, ledger_evidence, read_jsonl, MIN_DECISIVE, BAR_PRECISION)

MIN_DECISIVE = rl.MIN_DECISIVE
BAR_PRECISION = rl.BAR_PRECISION
LABELS = rl.LABELS
MODEL_GATES = {"reviewer"}
FINDING_KEYS = ("findings", "new", "parse_errors")


def paths():
    s = qc.state_dir()
    return {"shadow_dir": os.path.join(s, "qa_shadow"), "labels": os.path.join(s, "qa_labels.jsonl"),
            "cands": os.path.join(s, "qa_label_candidates.jsonl"), "sugg": os.path.join(s, "qa_label_suggestions.jsonl"),
            "legacy": os.path.join(s, "qa_reviewer_labels.jsonl"), "ledger": os.path.join(s, "qa_ledger.jsonl")}


def _norm(s):
    return re.sub(r"\s+", " ", re.sub(r"\d+", "N", str(s or ""))).strip()[:200]


def derive_id(gate, repo, rule, file, msg):
    raw = "|".join((gate, str(repo or ""), str(rule or "-"), str(file or ""), _norm(msg)))
    return hashlib.sha1(raw.encode("utf-8", "replace")).hexdigest()[:12]


def norm_finding(gate, repo, f):
    """One finding dict of any gate -> {id, rule, file, line, claim, severity} or None when it is not a finding."""
    if not isinstance(f, dict):
        return None
    rule = f.get("rule")
    if f.get("tool") and rule:
        rule = "%s:%s" % (f["tool"], rule)        # scanners: ruff:F821
    rule = str(rule) if rule else "-"
    file = f.get("file")
    line = f.get("line")
    if not file and f.get("at"):
        file, _, ln = str(f["at"]).rpartition(":")
        line = line or (int(ln) if ln.isdigit() else None)
    claim = f.get("claim") or f.get("msg") or f.get("err") or ""
    fid = f.get("id") if isinstance(f.get("id"), str) and f.get("id") else derive_id(gate, repo, rule, file, claim)
    return {"id": fid, "rule": rule, "file": file, "line": line, "claim": str(claim)[:240], "severity": f.get("severity") or f.get("sev")}


def findings_of_row(row):
    d = row.get("details") or {}
    for k in FINDING_KEYS:
        v = d.get(k)
        if isinstance(v, list) and v and isinstance(v[0], dict):
            if k == "parse_errors":      # gate_gdparse: {file, err, preexisting}; no rule field of its own
                return [dict(f, rule=f.get("rule") or "parse_error") for f in v]
            return v
    return []


def shadow_findings():
    """Every finding ever recorded by any gate: first sighting of (gate, rule, id) wins."""
    out, seen = [], set()
    d = paths()["shadow_dir"]
    try:
        names = sorted(n for n in os.listdir(d) if n.endswith(".jsonl"))
    except OSError:
        return out
    for n in names:
        for r in rl.read_jsonl(os.path.join(d, n)):
            gate = r.get("gate") or n[:-6]
            for f in findings_of_row(r):
                nf = norm_finding(gate, r.get("repo"), f)
                if not nf:
                    continue
                key = (gate, nf["rule"], nf["id"])
                if key in seen:
                    continue
                seen.add(key)
                nf.update(gate=gate, repo=r.get("repo"), ts=r.get("ts"), epoch=rl.epoch_of(r.get("ts")), ref=r.get("ref"), source="shadow")
                out.append(nf)
    return out


def candidate_findings():
    out, seen = [], set()
    for r in rl.read_jsonl(paths()["cands"]):
        key = (r.get("gate"), r.get("rule"), r.get("id"))
        if not all(key) or key in seen:
            continue
        seen.add(key)
        out.append({"id": r["id"], "rule": r["rule"], "file": r.get("file"), "line": r.get("line"), "claim": r.get("claim", ""), "severity": r.get("severity"),
                    "gate": r["gate"], "repo": r.get("repo"), "ts": r.get("ts"), "epoch": rl.epoch_of(r.get("ts")), "ref": r.get("commit"), "source": "harvest"})
    return out


def all_findings():
    out, seen = [], set()
    for f in shadow_findings() + candidate_findings():
        key = (f["gate"], f["rule"], f["id"])
        if key not in seen:
            seen.add(key)
            out.append(f)
    return out


def latest_labels():
    """(gate, rule, id) -> latest label row. Legacy reviewer labels are included (gate=reviewer, rule='-'), a newer qa_labels.jsonl row wins."""
    cur = {}
    for r in rl.read_jsonl(paths()["legacy"]):
        if r.get("id") and r.get("label") in LABELS:
            cur[("reviewer", "-", r["id"])] = dict(r, gate="reviewer", rule="-")
    for r in rl.read_jsonl(paths()["labels"]):
        if r.get("gate") and r.get("id") and r.get("label") in LABELS:
            cur[(r["gate"], r.get("rule") or "-", r["id"])] = r
    return cur


def latest_suggestions():
    cur = {}
    for r in rl.read_jsonl(paths()["sugg"]):
        if r.get("gate") and r.get("id") and r.get("label") in LABELS:
            cur[(r["gate"], r.get("rule") or "-", r["id"])] = r
    return cur


def stats(tp, fp, un=0):
    """Pure. The refuse-under-50 rule lives here: no precision/CI below MIN_DECISIVE decisive labels."""
    dec = tp + fp
    s = {"tp": tp, "fp": fp, "unclear": un, "decisive": dec, "min_decisive": MIN_DECISIVE, "precision": None, "ci95": None, "wilson_lower": None, "bar_met": None}
    if dec >= MIN_DECISIVE:
        s["precision"] = round(tp / float(dec), 4)
        lo, hi = rl.wilson(tp, dec)
        s["ci95"] = [round(lo, 4), round(hi, 4)]
        s["wilson_lower"] = round(lo, 4)
        s["bar_met"] = s["precision"] >= BAR_PRECISION
    return s


def build_report(gate=None, rule=None):
    fs = [f for f in all_findings() if (not gate or f["gate"] == gate) and (not rule or f["rule"] == rule)]
    known = {(f["gate"], f["rule"], f["id"]): f for f in fs}
    lab = {k: v for k, v in latest_labels().items() if k in known}
    sug = {k: v for k, v in latest_suggestions().items() if k in known}
    groups = {}

    def grp(g, r):
        return groups.setdefault((g, r), {"gate": g, "rule": r, "findings": 0, "labelled": 0, "tp": 0, "fp": 0, "unclear": 0, "suggested": 0})
    for k in known:
        grp(k[0], k[1])["findings"] += 1
    for k, r in lab.items():
        g = grp(k[0], k[1])
        g["labelled"] += 1
        g[{"TP": "tp", "FP": "fp", "unclear": "unclear"}[r["label"]]] += 1
    for k in sug:
        if k not in lab:
            grp(k[0], k[1])["suggested"] += 1
    rows = []
    for (g, r), v in sorted(groups.items()):
        v.update(stats(v["tp"], v["fp"], v["unclear"]))
        rows.append(v)
    per_gate = {}
    for v in rows:
        a = per_gate.setdefault(v["gate"], {"gate": v["gate"], "findings": 0, "labelled": 0, "tp": 0, "fp": 0, "unclear": 0, "rules": 0})
        for k in ("findings", "labelled", "tp", "fp", "unclear"):
            a[k] += v[k]
        a["rules"] += 1
    gates = []
    for g, a in sorted(per_gate.items()):
        a.update(stats(a["tp"], a["fp"], a["unclear"]))
        if a["rules"] > 1:
            # the bar is per (gate, rule): a pooled percentage over several rules could read as promotion evidence for rules with a handful of labels
            a.update(precision=None, ci95=None, wilson_lower=None, bar_met=None, pooled=True)
        gates.append(a)
    agree = [1 if sug[k]["label"] == lab[k]["label"] else 0 for k in lab if k in sug and lab[k]["label"] != "unclear"]
    unl = [f for f in fs if (f["gate"], f["rule"], f["id"]) not in lab]
    ev = rl.ledger_evidence([f for f in unl if f.get("epoch")]) if unl else {}
    suggested_tp = [{"gate": f["gate"], "rule": f["rule"], "id": f["id"], "repo": f["repo"], "file": f["file"], "claim": f["claim"][:160], "evidence": ev[f["id"]]}
                    for f in unl if f["id"] in ev]
    return {"findings": len(fs), "labelled": len(lab), "by_rule": rows, "by_gate": gates, "suggested_tp": suggested_tp[:30],
            "suggestions_total": len(sug), "suggestion_agreement": {"n": len(agree), "agree": sum(agree)}, "min_decisive": MIN_DECISIVE, "bar_precision": BAR_PRECISION}


def _fmt_stats(v):
    if v.get("pooled"):
        return "precision: not shown for a gate-wide pool (the bar is per rule; n=%d decisive over %d rules, see the rule rows)" % (v["decisive"], v["rules"])
    if v["precision"] is None:
        return "precision: not computed (n=%d decisive < %d required; INSUFFICIENT SAMPLE)" % (v["decisive"], MIN_DECISIVE)
    return "precision %.1f%% (95%% Wilson %.0f-%.0f%%, lower bound %.0f%%, n=%d) -> bar %s" % (
        v["precision"] * 100, v["ci95"][0] * 100, v["ci95"][1] * 100, v["wilson_lower"] * 100, v["decisive"], "MET" if v["bar_met"] else "NOT MET")


def cmd_report(o):
    rep = build_report(o.get("gate"), o.get("rule"))
    if o.get("json"):
        print(json.dumps(rep, sort_keys=True))
        return 0
    print("findings known: %d | labelled: %d | pre-read suggestions: %d (never counted; agreement with human labels %d/%d)" % (
        rep["findings"], rep["labelled"], rep["suggestions_total"], rep["suggestion_agreement"]["agree"], rep["suggestion_agreement"]["n"]))
    for a in rep["by_gate"]:
        print("\n[%s] findings %d, labelled %d (TP %d, FP %d, unclear %d) over %d rule(s)\n  %s" % (a["gate"], a["findings"], a["labelled"], a["tp"], a["fp"], a["unclear"],
                                                                                              a["rules"], _fmt_stats(a)))
        for v in rep["by_rule"]:
            if v["gate"] == a["gate"]:
                print("    %-34s findings %4d labelled %3d (TP %d FP %d ?%d) pre-read %d | %s" % (v["rule"], v["findings"], v["labelled"], v["tp"], v["fp"], v["unclear"],
                                                                                                 v["suggested"], _fmt_stats(v)))
    if rep["suggested_tp"]:
        print("\nsuggested TP from the ledger (a revert/hotfix/escape touched the same file within %d days AFTER; confirm with `label`, NOT counted):" % rl.WINDOW_DAYS)
        for s in rep["suggested_tp"][:15]:
            e = s["evidence"][0]
            print("  %s %s/%s %s  <- %s %s +%sd" % (s["id"], s["gate"], s["rule"], s["file"], e["type"], e["ref"], e["days_after"]))
    return 0


def cmd_list(o):
    lab = latest_labels()
    sug = latest_suggestions()
    n = 0
    lim = int(o.get("limit") or 50)
    for f in reversed(all_findings()):
        k = (f["gate"], f["rule"], f["id"])
        if o.get("gate") and f["gate"] != o["gate"]:
            continue
        if o.get("rule") and f["rule"] != o["rule"]:
            continue
        if o.get("unlabelled") and k in lab:
            continue
        if o.get("candidates_only") and f["source"] != "harvest":
            continue
        sg = sug.get(k)
        print("%s %-10s %-24s %-9s %s:%s [%s] %s | %s%s" % (f["id"], f["gate"], f["rule"], (lab.get(k) or {}).get("label", "-"), f["file"], f["line"], f["severity"] or "-",
                                                         f["repo"], f["claim"][:120], ("  (pre-read: %s)" % sg["label"]) if sg and k not in lab else ""))
        n += 1
        if n >= lim:
            break
    return 0


def _find(o):
    gate, fid = o.get("gate"), o.get("id")
    cands = [f for f in all_findings() if f["gate"] == gate and f["id"] == fid and (not o.get("rule") or f["rule"] == o["rule"])]
    return cands[0] if cands else None


def _append(path, row):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as fh:
        fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def cmd_label(o, suggest=False):
    name = "suggest" if suggest else "label"
    if not o.get("gate") or not o.get("id") or o.get("label") not in LABELS or (suggest and not o.get("evidence")):
        print("usage: qa_label.py %s --gate G --id ID --label TP|FP|unclear %s" % (name, "--evidence TEXT" if suggest else "[--rule R] [--note TEXT]"), file=sys.stderr)
        return 2
    f = _find(o)
    if f is None:
        print("unknown finding (gate=%s id=%s%s): see `list`; nothing stored" % (o["gate"], o["id"], " rule=" + o["rule"] if o.get("rule") else ""), file=sys.stderr)
        return 2
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "gate": f["gate"], "rule": f["rule"], "id": f["id"], "label": o["label"], "repo": f["repo"], "file": f["file"]}
    if suggest:
        row["evidence"] = str(o["evidence"])[:600]
        _append(paths()["sugg"], row)
        print("pre-read stored %s/%s %s %s (NOT counted as a label)" % (f["gate"], f["rule"], f["id"], o["label"]))
        return 0
    row["note"] = str(o.get("note") or "")[:300]
    row["claim"] = f["claim"][:160]
    sg = latest_suggestions().get((f["gate"], f["rule"], f["id"]))
    if sg:
        row["suggested"] = sg["label"]
    _append(paths()["labels"], row)
    print("labelled %s/%s %s %s (%s:%s)" % (f["gate"], f["rule"], f["id"], o["label"], f["file"], f["line"]))
    return 0


# ------------------------------------------------------------------------------------------------------------------ harvest
def gpu_util():
    """GPU utilisation percent (max over GPUs) or None when nvidia-smi is missing/unusable (a missing sample is never '0% busy')."""
    smi = os.environ.get("OVN_NVIDIA_SMI", "nvidia-smi")
    rc, out, _ = qc.run([smi, "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], timeout=15, polite=False)
    if rc != 0:
        return None
    vals = [int(x) for x in out.split() if x.isdigit()]
    return max(vals) if vals else None


def sample_commits(shas, n, seed):
    """Pure + deterministic: n distinct commits drawn with a seeded RNG, returned in the order of `shas` (recency)."""
    if n >= len(shas):
        return list(shas)
    pick = set(random.Random(seed).sample(range(len(shas)), n))
    return [s for i, s in enumerate(shas) if i in pick]


def cmd_harvest(o):
    gate, repo = o.get("gate"), o.get("repo")
    if not gate or not repo or not re.match(r"^[a-z0-9_]+$", gate):
        print("usage: qa_label.py harvest --gate G --repo R [--days N] [--sample N] [--branch REF] [--seed S] [--budget-s S] [--dry-run]", file=sys.stderr)
        return 2
    script = os.path.join(os.environ.get("QA_LABEL_GATE_DIR") or HERE, "gate_%s.py" % gate)    # QA_LABEL_GATE_DIR: test seam
    if not os.path.isfile(script):
        print("no gate script %s" % script, file=sys.stderr)
        return 2
    rd = qc.repo_dir(repo)
    if not rd:
        print("no clone for repo %s" % repo, file=sys.stderr)
        return 3
    days, n, seed = int(o.get("days") or 60), int(o.get("sample") or 400), int(o.get("seed") or 1)
    branch, budget = o.get("branch") or "origin/develop", int(o.get("budget_s") or 3600)
    if gate in MODEL_GATES and not o.get("ignore_gpu"):
        thr = int(os.environ.get("QA_LABEL_GPU_IDLE_PCT", "30"))
        u = gpu_util()
        if u is None or u > thr:
            print("refused: gate %s uses the GPU and utilisation is %s (need <= %d%%; nvidia-smi unusable counts as busy). Re-run in an idle window or pass --ignore-gpu."
                  % (gate, "unknown" if u is None else "%d%%" % u, thr), file=sys.stderr)
            return 3
    rc, out, err = qc.git(rd, "log", "--no-merges", "--since=%d.days" % days, "--format=%H", branch)
    if rc != 0:
        print("git log failed: " + err[:200], file=sys.stderr)
        return 2
    shas = [s for s in out.split() if s]
    pick = sample_commits(shas, n, seed)
    summary = {"gate": gate, "repo": repo, "branch": branch, "days": days, "window_commits": len(shas), "sampled": len(pick), "seed": seed, "dry_run": bool(o.get("dry_run"))}
    if o.get("dry_run"):
        summary["first_commits"] = pick[:5]
        print(json.dumps(summary, sort_keys=True))
        return 0
    import qa_replay as qr
    scratch = tempfile.mkdtemp(prefix="qa-label-harvest-")
    t0 = time.time()
    verdicts, new_rows, with_findings, done = {}, [], 0, 0
    known = {(f["gate"], f["rule"], f["id"]) for f in candidate_findings()}
    env = {"OVN_DIR": scratch, "QA_STATE_DIR": os.path.join(scratch, "state"), "OVN_REPOS_DIR": os.path.dirname(os.path.abspath(rd))}
    try:
        os.makedirs(os.path.join(scratch, "state"))
        for sha in pick:
            if time.time() - t0 >= budget:
                summary["stopped"] = "budget %ds spent" % budget
                break
            if qc.git(rd, "rev-parse", "--verify", "-q", sha + "^")[0] != 0:
                continue
            res = qr.replay_commit(script, repo, sha, env=env)
            done += 1
            verdicts[res.get("verdict", "UNVERIFIED")] = verdicts.get(res.get("verdict", "UNVERIFIED"), 0) + 1
            fl = [nf for nf in (norm_finding(gate, repo, f) for f in findings_of_row(res)) if nf]
            if fl:
                with_findings += 1
            for nf in fl:
                key = (gate, nf["rule"], nf["id"])
                if key in known:
                    continue
                known.add(key)
                new_rows.append({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "gate": gate, "repo": repo, "commit": sha, "id": nf["id"], "rule": nf["rule"],
                                 "file": nf["file"], "line": nf["line"], "claim": nf["claim"], "severity": nf["severity"], "source": "harvest"})
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if not o.get("no_record"):
        for r in new_rows:
            _append(paths()["cands"], r)
    summary.update(ranges_run=done, verdicts=verdicts, ranges_with_findings=with_findings, new_candidates=len(new_rows), recorded=not o.get("no_record"),
                   by_rule={r: sum(1 for x in new_rows if x["rule"] == r) for r in sorted({x["rule"] for x in new_rows})}, seconds=int(time.time() - t0))
    print(json.dumps(summary, sort_keys=True))
    return 0


def parse(argv):
    flags = {"--unlabelled": "unlabelled", "--candidates-only": "candidates_only", "--json": "json", "--dry-run": "dry_run", "--ignore-gpu": "ignore_gpu", "--no-record": "no_record"}
    opts = {"--gate", "--rule", "--id", "--label", "--note", "--evidence", "--limit", "--repo", "--days", "--sample", "--branch", "--seed", "--budget-s"}
    o, i = {}, 0
    while i < len(argv):
        a = argv[i]
        if a in flags:
            o[flags[a]] = True
            i += 1
        elif a in opts and i + 1 < len(argv):
            o[a[2:].replace("-", "_")] = argv[i + 1]
            i += 2
        else:
            raise ValueError("unknown or incomplete argument %r" % a)
    return o


def main(argv):
    if not argv or argv[0] not in ("list", "label", "suggest", "report", "harvest"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        o = parse(argv[1:])
        for k in ("limit", "days", "sample", "seed", "budget_s"):
            if k in o:
                int(o[k])
    except ValueError as ex:
        print("usage error: %s" % ex, file=sys.stderr)
        return 2
    cmd = argv[0]
    if cmd == "label":
        return cmd_label(o)
    if cmd == "suggest":
        return cmd_label(o, suggest=True)
    return {"list": cmd_list, "report": cmd_report, "harvest": cmd_harvest}[cmd](o)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
