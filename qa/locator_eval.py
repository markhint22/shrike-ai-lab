#!/usr/bin/env python3
"""locator_eval.py - MEASURE the manual-notes locator against real history (never a guess).

A case = a REAL bug-fix commit whose message describes a user-visible problem. Its note is what a human tester would have written
(drafted by the local Qwen from the commit, then deterministically stripped of code identifiers / paths and checked for leaks of the
labelled file names). Its label = the non-test product files the fix changed. The locator runs against the PARENT commit (the code as
it was when the bug existed; read-only `git grep <sha>`, nothing is checked out or written in the clones) and is scored hit@1 / hit@3.

  locator_eval.py mine   --clones DIR --repos billwatch,gitlark,iptv_apps --out cands.json [--per-repo 120]
  locator_eval.py draft  --cands cands.json --out set.json [--want 60]        (local Qwen; one request at a time)
  locator_eval.py run    --set locator_eval_set.json --clones DIR --baseline OLD_manual_notes_ingest.py --out results.json
                         [--arms v1,v2det,v2,v2all] [--limit N]
  locator_eval.py report --results results.json

Arms: v1 = the locator as shipped before v2 (deterministic only, no platform, no product filter beyond its own); v2det = platform +
product-only filter, no model; v2 = v2det + agentic loop on weak/ambiguous results; v2all = agentic loop on every note; v2np = v2 with NO platform given (infer from flow/words, else needs-triage = counted as a miss);
v2b = a second independent v2 run (model sampling variance).
"""
import argparse
import collections
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import manual_locator as ml  # noqa: E402
import manual_notes_ingest as mn  # noqa: E402

BRANCH = "origin/overnight/feature"


def git(repo, *a, timeout=120):
    p = subprocess.run(["git", "-C", repo] + list(a), capture_output=True, timeout=timeout)
    return p.returncode, p.stdout.decode("utf-8", "replace")


# ------------------------------------------------------------------------------------------------------------------ mining
def product_label(path):
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    return ext in mn.SRC_EXT and ml.is_product_path(path) and not mn.EXCLUDE_FILE.search(path)


def mine(args):
    out = []
    for name in args.repos.split(","):
        rp = os.path.join(args.clones, name)
        rc, txt = git(rp, "ls-tree", "-r", "--name-only", BRANCH)
        layout = ml.detect_layout(txt.splitlines())
        rc, log = git(rp, "log", BRANCH, "--no-merges", "-n", "5000", "--format=%H\x1f%P\x1f%s\x1f%an")
        n = 0
        for ln in log.splitlines():
            sha, parents, subj, au = (ln.split("\x1f") + ["", "", "", ""])[:4]
            if not re.match(r"(?i)^(fix|bugfix)\b", subj) or len(parents.split()) != 1:
                continue
            if re.search(r"(?i)\b(test|tests|lint|ci|workflow|typo|docs?|dependabot|bump|import error|syntax error|undefined name|type hint)\b", subj):
                continue
            rc, ns = git(rp, "show", "--name-status", "--format=", "-M", sha)
            mod, other = [], 0
            for l in ns.splitlines():
                parts = l.split("\t")
                if len(parts) >= 2 and parts[0] == "M" and product_label(parts[1]):
                    mod.append(parts[1])
                elif len(parts) >= 2 and product_label(parts[-1]):
                    other += 1                          # added/renamed/deleted product file: the file did not exist at the parent
            if not (1 <= len(mod) <= 4) or other > 1:
                continue
            plats = collections.Counter(ml.plat_of(f, layout) or "single" for f in mod)
            clients = [p for p in plats if p not in ("backend", "single")]
            plat = max(clients, key=lambda p: plats[p]) if clients else ("backend" if "backend" in plats else "single")
            out.append({"repo": name, "sha": sha, "parent": parents.strip(), "subject": subj[:200], "author": au, "labels": mod, "platform": plat})
            n += 1
            if n >= args.per_repo:
                break
        print("%s: %d candidate fix commits" % (name, n), flush=True)
    json.dump(out, open(args.out, "w"), indent=1)
    return 0


# ------------------------------------------------------------------------------------------------------------------ drafting
_IDENT = re.compile(r"[A-Za-z0-9_.-]*[/\\][A-Za-z0-9_./\\-]*|\b[A-Za-z0-9_-]+\.(py|vue|kt|kts|swift|ts|tsx|js|jsx|mjs|xml|json|gd|java|sql|html|css|gradle)\b|"
                    r"\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*\b|\b[A-Za-z0-9]+_[A-Za-z0-9_]+\b|\b[A-Z0-9]{2,}_[A-Z0-9_]+\b|"
                    r"\b\w+\(\)|`[^`]*`")


def strip_identifiers(note):
    s = _IDENT.sub(" ", note)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"\s+([.,;:!?])", r"\1", s)
    return s


def stems(path):
    base = os.path.basename(path).rsplit(".", 1)[0]
    words = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", base)
    return re.sub(r"[^a-z0-9]", "", base.lower()), [w.lower() for w in words]


def leaks(note, labels):
    """True if the note names a labelled file or one of the identifiers (whole stem, letters only)."""
    flat = re.sub(r"[^a-z0-9]", "", note.lower())
    for p in labels:
        st, _w = stems(p)
        if len(st) >= 6 and st in flat:
            return True
        if os.path.basename(p).lower() in note.lower():
            return True
    return False


def draft(args):
    cands = json.load(open(args.cands))
    out, seen = [], 0
    for c in cands:
        if len(out) >= args.want * 2:
            break
        rp = os.path.join(args.clones, c["repo"])
        rc, diff = git(rp, "show", "--format=%B", "-U2", c["sha"], "--", *c["labels"])
        diff = diff[:3800]
        prompt = (
            "Below is a bug-fix commit from a %s app project (platform: %s). Decide whether the bug it fixes is something an end user "
            "or a human tester would SEE while using the app (wrong/missing data, a button or screen misbehaving, wrong ordering, "
            "an error shown, a feature not working). Developer-only problems (build, imports, types, refactors, logging, CI) are NOT user-visible.\n"
            "If it is user-visible, write the note a NON-TECHNICAL tester would log after hitting the problem: 1 or 2 plain sentences "
            "describing what they did and what went wrong versus what they expected, in everyday words. STRICT: no code names, no file or "
            "function or class names, no camelCase or snake_case words, no API paths, no technical jargon (no 'null', 'JSON', 'endpoint', "
            "'query', 'schema'); you may quote text that is visible on screen. Also give a short screen/flow label of 2-4 words like a "
            "tester would (for example 'Home Page Countries Filter').\n"
            "Reply with ONLY JSON: {\"user_visible\": true|false, \"note\": \"...\", \"flow\": \"...\"}\n\n"
            "COMMIT:\n%s" % (c["repo"], c["platform"], diff))
        txt = ml.model_chat(prompt, timeout=90, max_tokens=500)
        d = ml.parse_json_obj(txt or "") or {}
        seen += 1
        if not d.get("user_visible") or not isinstance(d.get("note"), str):
            continue
        note = strip_identifiers(d["note"])
        if len(note.split()) < 7 or leaks(note, c["labels"]):
            print("  drop (leak/short): %s" % c["subject"][:70], flush=True)
            continue
        c = dict(c, note=note[:400], flow=re.sub(r"\s+", " ", str(d.get("flow") or "other"))[:60])
        out.append(c)
        print("%s %s [%s] %s\n    -> %s" % (c["repo"], c["sha"][:8], c["platform"], c["subject"][:80], note[:160]), flush=True)
        json.dump(out, open(args.out, "w"), indent=1)
    print("drafted %d user-visible cases from %d commits" % (len(out), seen))
    return 0


# ------------------------------------------------------------------------------------------------------------------ running
def load_baseline(path):
    spec = importlib.util.spec_from_file_location("mn_v1", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def run_case(arm, c, clones, v1):
    rp = os.path.join(clones, c["repo"])
    ref = c["parent"]
    t = time.time()
    info = {"calls": 0}
    try:
        if arm == "v1":
            res = v1.locate(rp, ref, c["note"], c["flow"])
            cands = [x for x in res["candidates"] if x["located"]]
            paths = [x["path"] for x in cands]
        else:
            old = mn.STRONG_SCORE
            if arm == "v2all":
                mn.STRONG_SCORE = 1e9
            try:
                plat = c["platform"] if (c["platform"] != "single" and arm != "v2np") else ""
                res = mn.locate_v2(rp, ref, c["note"], c["flow"], platform=plat, use_model=(arm != "v2det"), repo_name=c["repo"])
            finally:
                mn.STRONG_SCORE = old
            cands = [x for x in res["candidates"] if x["located"]] if res["status"] == "located" else []
            paths = [x["path"] for x in cands]
            info = {"calls": (res.get("agentic") or {}).get("calls", 0), "ranked_by": res.get("ranked_by"), "status": res["status"],
                    "agentic_ok": (res.get("agentic") or {}).get("ok"), "reasons": [x.get("evidence", "")[:140] for x in cands],
                    "queries": (res.get("agentic") or {}).get("queries"), "platform": res.get("platform")}
    except Exception as ex:  # noqa: BLE001
        paths, info = [], {"error": "%s: %s" % (type(ex).__name__, ex)}
    labels = set(c["labels"])
    return dict(info, paths=paths[:3], hit1=bool(paths[:1] and paths[0] in labels), hit3=any(p in labels for p in paths[:3]),
                secs=round(time.time() - t, 1))


def run(args):
    cases = json.load(open(args.set))
    if args.limit:
        cases = cases[:args.limit]
    v1 = load_baseline(args.baseline)
    arms = args.arms.split(",")
    results = {"arms": arms, "cases": []}
    for i, c in enumerate(cases):
        row = {"id": i, "repo": c["repo"], "platform": c["platform"], "sha": c["sha"][:10], "subject": c["subject"], "note": c["note"],
               "labels": c["labels"], "arms": {}}
        for arm in arms:
            row["arms"][arm] = run_case(arm, c, args.clones, v1)
        results["cases"].append(row)
        print("[%d/%d] %s %s  %s" % (i + 1, len(cases), c["repo"], c["platform"],
              "  ".join("%s:%s%s" % (a, "H1" if row["arms"][a]["hit1"] else ("H3" if row["arms"][a]["hit3"] else "--"), "") for a in arms)), flush=True)
        json.dump(results, open(args.out, "w"), indent=1)
    report_dict(results)
    return 0


def pct(n, d):
    return "%3d%%" % round(100.0 * n / d) if d else "  - "


def report_dict(results):
    arms, cases = results["arms"], results["cases"]
    groups = [("ALL", lambda r: True)]
    for k in sorted({r["repo"] for r in cases}):
        groups.append(("repo " + k, lambda r, k=k: r["repo"] == k))
    for k in sorted({r["platform"] for r in cases}):
        groups.append(("platform " + k, lambda r, k=k: r["platform"] == k))
    print("\n%-22s %4s | %s" % ("group", "n", " | ".join("%-13s" % (a + " h@1/h@3") for a in arms)))
    for name, f in groups:
        rows = [r for r in cases if f(r)]
        cells = []
        for a in arms:
            cells.append("%-13s" % ("%s / %s" % (pct(sum(r["arms"][a]["hit1"] for r in rows), len(rows)),
                                                 pct(sum(r["arms"][a]["hit3"] for r in rows), len(rows)))))
        print("%-22s %4d | %s" % (name, len(rows), " | ".join(cells)))
    for a in arms:
        rows = [r["arms"][a] for r in cases]
        print("%s: triage/no-candidate %d, errors %d, mean model calls %.2f, mean secs %.1f" % (
            a, sum(1 for r in rows if not r["paths"]), sum(1 for r in rows if r.get("error")),
            sum(r.get("calls", 0) for r in rows) / max(1, len(rows)), sum(r["secs"] for r in rows) / max(1, len(rows))))


def report(args):
    results = json.load(open(args.results))
    report_dict(results)
    last = results["arms"][-1]
    print("\nMISSES for arm %s (hit@3 false):" % last)
    for r in results["cases"]:
        if not r["arms"][last]["hit3"]:
            print("- [%s/%s] %s\n    labels: %s\n    got: %s" % (r["repo"], r["platform"], r["note"][:140], ", ".join(r["labels"]),
                                                                  ", ".join(r["arms"][last]["paths"]) or "(none)"))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("mine")
    a.add_argument("--clones", required=True)
    a.add_argument("--repos", default="billwatch,gitlark,iptv_apps")
    a.add_argument("--out", required=True)
    a.add_argument("--per-repo", type=int, default=120)
    a = sub.add_parser("draft")
    a.add_argument("--cands", required=True)
    a.add_argument("--clones", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--want", type=int, default=60)
    a = sub.add_parser("run")
    a.add_argument("--set", required=True)
    a.add_argument("--clones", required=True)
    a.add_argument("--baseline", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--arms", default="v1,v2det,v2,v2all")
    a.add_argument("--limit", type=int, default=0)
    a = sub.add_parser("report")
    a.add_argument("--results", required=True)
    args = ap.parse_args(argv)
    return {"mine": mine, "draft": draft, "run": run, "report": report}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
