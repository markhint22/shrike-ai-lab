#!/usr/bin/env python3
"""card_pilot_report.py - the Phase 2 measures of the S0 card pilot (docs/QA_PLAN_2026-10-01.md section 7), read-only.

    python3 qa/card_pilot_report.py [--state-dir DIR] [--input F.jsonl ...] [--no-state] [--out DIR] [--sample 20] [--json]

Reads state/qa_shadow/card_pilot.jsonl (rows written by card_pilot_run.py) and/or any --input file in EITHER format: the pilot's own `kind: "card"` rows or
the acceptance_card.py pilot's cards.jsonl (qa/acceptance_pilot/*.jsonl). Prints:

  lint pass rate           cards with no lint error / cards drafted
  fail-before rate         cards whose verify_cmd FAILED at the base ref / cards drafted (and of the lint-clean ones); 'weak' = it already passed
  GPU minutes per card     mean GPU seconds per drafted card / 60 (model timings; wall seconds when the server reported none, labelled)
  class A share            cards whose final risk class is A / cards drafted

and writes <out>/card_sample.md (default <state>/qa_shadow/card_sample.md): up to --sample (20) class A cards for Mark to read, with an EMPTY decision
box per card. It approves nothing and writes nothing else: the plan's bar is "Mark samples 20 class A cards, at least 80% sensible".
The last stdout line is one JSON object (the same numbers). Exit code 0 always.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

BAR_LINT = None          # the plan sets no lint-rate bar for Phase 2, it asks to MEASURE it
BAR_GPU_MIN = 3.0        # plan: 1.5-3 GPU-min on T3+/class A items, ~0.5 averaged
BAR_SENSIBLE = 0.8


def normalize(rec):
    """-> dict(repo, path, desc, verdict, has_card, lint_ok, lint_errors, exec_outcome, risk, gpu_s, wall_s, calls, card, tier) or None when the row is not a card row."""
    if rec.get("kind") == "card":
        return {"repo": rec.get("repo"), "path": rec.get("path"), "desc": rec.get("desc"), "tier": rec.get("tier"), "verdict": rec.get("verdict"),
                "has_card": bool(rec.get("card")), "lint_ok": bool(rec.get("lint_ok")), "lint_errors": rec.get("lint_errors") or [],
                "exec_outcome": rec.get("exec_outcome"), "risk": (rec.get("risk_class") or ((rec.get("card") or {}).get("risk_class")) or None),
                "gpu_s": rec.get("gpu_s") if rec.get("gpu_s_source") == "timings" else None, "wall_s": rec.get("wall_s"), "calls": rec.get("model_calls"),
                "card": rec.get("card"), "needs_human_review": rec.get("needs_human_review"), "summary": rec.get("summary")}
    res = rec.get("result")
    if isinstance(res, dict) and "details" in res and "verdict" in res:        # acceptance_card.py pilot format
        d = res.get("details") or {}
        card = d.get("card")
        lint = d.get("lint") or {}
        errs = [e.get("rule") for e in lint.get("errors", [])]
        llm = d.get("llm") or {}
        it = rec.get("item") or {}
        return {"repo": res.get("repo"), "path": it.get("path"), "desc": it.get("desc"), "tier": it.get("tier"), "verdict": res.get("verdict"),
                "has_card": bool(card), "lint_ok": bool(card) and not errs, "lint_errors": errs,
                "exec_outcome": (d.get("exec") or {}).get("outcome"), "risk": d.get("risk_class") or ((card or {}).get("risk_class") if card else None),
                "gpu_s": llm.get("gpu_s") or None, "wall_s": llm.get("wall_s"), "calls": llm.get("attempts"), "card": card,
                "needs_human_review": d.get("needs_human_review"), "summary": res.get("summary")}
    return None


def load(paths):
    out = []
    for p in paths:
        try:
            with open(p, errors="replace") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    n = normalize(d) if isinstance(d, dict) else None
                    if n:
                        out.append(n)
        except OSError:
            pass
    return out


def measures(rows):
    cards = [r for r in rows if r["has_card"]]
    n = len(cards)
    lint_ok = [r for r in cards if r["lint_ok"]]
    execd = [r for r in cards if r["exec_outcome"]]
    fb = [r for r in cards if r["exec_outcome"] == "failed"]
    fb_clean = [r for r in lint_ok if r["exec_outcome"] == "failed"]
    weak = [r for r in cards if r["exec_outcome"] == "passed"]
    gpu = [r["gpu_s"] for r in cards if r["gpu_s"]]
    wall = [r["wall_s"] for r in cards if r["wall_s"]]
    a = [r for r in cards if (r["risk"] or "").upper() == "A"]
    rules = {}
    for r in cards:
        for e in r["lint_errors"]:
            rules[e] = rules.get(e, 0) + 1
    vc = {}
    for r in rows:
        vc[r["verdict"]] = vc.get(r["verdict"], 0) + 1

    def rate(x, y):
        return round(x / y, 3) if y else None
    if gpu:
        gmin, gsrc = round(sum(gpu) / len(gpu) / 60.0, 3), "gpu-timings (%d of %d cards)" % (len(gpu), n)
    elif wall:
        gmin, gsrc = round(sum(wall) / len(wall) / 60.0, 3), "wall-clock fallback: the model server reported no timings"
    else:
        gmin, gsrc = None, "no data"
    return {"rows": len(rows), "cards": n, "verdicts": vc, "lint_pass": len(lint_ok), "lint_pass_rate": rate(len(lint_ok), n), "lint_error_rules": rules,
            "exec_ran": len(execd), "fail_before": len(fb), "fail_before_rate": rate(len(fb), n), "fail_before_rate_of_lint_clean": rate(len(fb_clean), len(lint_ok)),
            "weak_passes_before": len(weak), "gpu_min_per_card": gmin, "gpu_min_source": gsrc,
            "gpu_min_total": round((sum(gpu) if gpu else sum(wall)) / 60.0, 2) if (gpu or wall) else None,
            "class_a": len(a), "class_a_share": rate(len(a), n)}


def pct(x):
    return "n/a" if x is None else "%.1f%%" % (100.0 * x)


def sample_sheet(rows, k):
    a = [r for r in rows if r["has_card"] and (r["risk"] or "").upper() == "A"]
    seen, picked = set(), []
    a = sorted(a, key=lambda r: not r["lint_ok"])   # lint-clean cards first (the ones that could be used), then rejected ones; stable = file order within each
    for r in a:                              # one card per item (deterministic, no cherry-picking)
        key = (r["repo"], r["path"], (r["desc"] or "")[:100])
        if key in seen:
            continue
        seen.add(key)
        picked.append(r)
    picked = picked[:k]
    L = ["# S0 acceptance cards - class A sample for Mark", "",
         "Read each card and decide only: **would you accept this as the definition of done for the item?** Bar from the QA plan: at least %d%% sensible (%d of %d)."
         % (int(BAR_SENSIBLE * 100), -(-int(BAR_SENSIBLE * 100) * len(picked) // 100), len(picked)),
         "Nothing here is auto-approved: this sheet changes no state, and a card's `verify_cmd` has not been accepted by anyone until you say so.", "",
         "Class A cards available: %d (%d unique items). Shown: %d." % (len(a), len(seen), len(picked)), ""]
    if len(picked) < k:
        L += ["**Shortfall: only %d class A cards exist, not %d. Do not read a pass rate off a sample this small.**" % (len(picked), k), ""]
    for i, r in enumerate(picked, 1):
        c = r["card"] or {}
        L += ["## %d. %s%s" % (i, r["path"], "  [%s]" % r["tier"] if r["tier"] else ""), "",
              "- repo: `%s`  verdict: **%s**  exec before change: `%s`  lint errors: %s  needs_human_review: %s"
              % (r["repo"], r["verdict"], r["exec_outcome"], ", ".join(r["lint_errors"]) or "none", r["needs_human_review"]),
              "- item: %s" % (r["desc"] or "").replace("\n", " "), "- bullets:"]
        L += ["  - %s" % b for b in (c.get("bullets") or [])]
        L += ["- verify_cmd: `%s`" % (c.get("verify_cmd") or "").replace("`", "'"), "- files: %s" % ", ".join(c.get("files") or []), "",
              "Decision: [ ] sensible   [ ] not sensible   note: ____________", ""]
    L += ["---", "Tally: sensible ___ / %d  (bar: %d)" % (len(picked), -(-int(BAR_SENSIBLE * 100) * len(picked) // 100)), ""]
    return "\n".join(L), len(picked)


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="card_pilot_report.py")
    ap.add_argument("--state-dir")
    ap.add_argument("--input", action="append", default=[])
    ap.add_argument("--no-state", action="store_true", help="read only the --input files, not state/qa_shadow/card_pilot.jsonl")
    ap.add_argument("--out")
    ap.add_argument("--sample", type=int, default=20)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    sd = a.state_dir or qc.state_dir()
    paths = list(a.input)
    if not a.no_state:
        paths.insert(0, os.path.join(sd, "qa_shadow", "card_pilot.jsonl"))
    rows = load(paths)
    m = measures(rows)
    out_dir = a.out or os.path.join(sd, "qa_shadow")
    os.makedirs(out_dir, exist_ok=True)
    sheet, nsheet = sample_sheet(rows, a.sample)
    sp = os.path.join(out_dir, "card_sample.md")
    with open(sp, "w") as f:
        f.write(sheet)
    m["sample_sheet"] = sp
    m["sample_cards"] = nsheet
    m["inputs"] = paths
    m["gpu_bar_min_per_class_a_card"] = BAR_GPU_MIN
    if not a.json:
        print("S0 card pilot - Phase 2 measures (shadow; nothing here changes behaviour)")
        print("  rows read              %d (%d with a drafted card)" % (m["rows"], m["cards"]))
        print("  verdicts               %s" % json.dumps(m["verdicts"], sort_keys=True))
        print("  lint pass rate         %s  (%d of %d)" % (pct(m["lint_pass_rate"]), m["lint_pass"], m["cards"]))
        print("  fail-before rate       %s of cards, %s of lint-clean cards  (weak = verify already passes at base: %d)"
              % (pct(m["fail_before_rate"]), pct(m["fail_before_rate_of_lint_clean"]), m["weak_passes_before"]))
        print("  GPU minutes per card   %s  [%s]  total %s" % (m["gpu_min_per_card"], m["gpu_min_source"], m["gpu_min_total"]))
        print("  class A share          %s  (%d of %d)" % (pct(m["class_a_share"]), m["class_a"], m["cards"]))
        if m["lint_error_rules"]:
            print("  lint rejections        %s" % json.dumps(m["lint_error_rules"], sort_keys=True))
        print("  sample sheet           %s  (%d class A cards; Mark decides, bar >= %d%% sensible)" % (sp, nsheet, int(BAR_SENSIBLE * 100)))
    print(json.dumps(m, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
