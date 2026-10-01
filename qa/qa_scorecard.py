#!/usr/bin/env python3
"""qa_scorecard.py - S12 one-page scorecards and the escape-rate report, read from state/qa_ledger.jsonl + state/qa_shadow/*.jsonl.

    qa_scorecard.py feature --repo R --feat TAG [--json]
    qa_scorecard.py promote --repo R --from REF --to REF [--json]
    qa_scorecard.py report  [--days N] [--repo R] [--mature-days 7] [--json]

A scorecard is a row of CELLS, never a composite score. Cell vocabulary: PASS FAIL FLAG NA UNVERIFIED.
  gate cell  = worst verdict among shadow records of that gate whose ref matches one of the feature's commits (or the promote --to SHA).
               NA          -> the gate has no shadow log at all (not deployed / never ran anywhere)
               UNVERIFIED  -> the gate log exists but has no record covering this feature (it did not run on it, or could not run)
  ledger cells (escape / weak-oracle) are facts from the ledger; their cell is NA when there is nothing to say yet (too young / unknown).
Read-only: never writes anywhere, never fetches, always exit 0.
"""
import collections
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_ledger as ql  # noqa: E402

KNOWN_GATES = ["antigaming", "scanners", "migrations", "baseline_verify", "acceptance_card", "staging_check", "release_candidate", "device_lane"]
SEVERITY = {"FAIL": 5, "FLAG": 4, "UNVERIFIED": 3, "PASS": 2, "NA": 1}
RISK_ORDER = {"A": 3, "B": 2, "C": 1}
DAY = 86400
ESCAPE_TYPES = ("revert", "hotfix", "emergency", "test_watch_red", "escape")


def norm_gate(g):
    g = (g or "").lower()
    for pre in ("gate_", "qa_"):
        if g.startswith(pre):
            g = g[len(pre):]
    return g


def load_shadow():
    d = os.path.join(qc.state_dir(), "qa_shadow")
    res = collections.defaultdict(list)
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return res
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        try:
            with open(os.path.join(d, n), "rb") as f:
                for raw in f:
                    try:
                        r = json.loads(raw.decode("utf-8", "replace"))
                    except ValueError:
                        continue
                    if not isinstance(r, dict):
                        continue
                    if not isinstance(r.get("gate"), str):
                        r["gate"] = ""
                    g = norm_gate(r.get("gate") or n[:-6])
                    if g == "ledger":
                        continue
                    res[g].append(r)
        except OSError:
            continue
    return res


def ref_matches(ref, shas):
    if not isinstance(ref, str):
        return False
    ref = ref.strip()
    if len(ref) < 7:
        return False
    return any(s.startswith(ref) or ref.startswith(s[:len(ref)]) for s in shas)


def gate_cell(gate, shadow, repo, shas):
    if gate not in shadow:
        return "NA", "no shadow log for this gate"
    hits = [r for r in shadow[gate] if (not r.get("repo") or r.get("repo") in (repo, "*")) and ref_matches(r.get("ref"), shas)]
    if not hits:
        return "UNVERIFIED", "gate log has no record for these commits"
    def vd(r):
        v = r.get("verdict")
        return v if isinstance(v, str) and v in SEVERITY else "UNVERIFIED"  # an unreadable verdict is never read as PASS
    worst = max(hits, key=lambda r: SEVERITY[vd(r)])
    sm = worst.get("summary")
    return vd(worst), (sm if isinstance(sm, str) else "")[:80]


def events_by_rec(evs):
    m = collections.defaultdict(list)
    for e in evs:
        if e.get("rec"):
            m[e["rec"]].append(e)
    return m


def escape_cell(recs, evm, now):
    """FAIL if any attributed escape event, PASS if every record is mature (>=7d) with none, NA if too young/unknown."""
    evs = [e for r in recs for e in evm.get(r["key"], []) if e["type"] in ESCAPE_TYPES]
    if evs:
        return "FAIL", ",".join(sorted(set("%s(%s)" % (e["type"], e.get("confidence", "?")) for e in evs)))
    if recs and all(now - r["epoch"] >= 7 * DAY for r in recs):
        if any(r["commit_basis"] != "time-window" for r in recs):
            return "UNVERIFIED", "mature, no escape seen, but some records have no attributed commits (events need files)"
        return "PASS", "no git evidence of an escape in 7d (lower bound: no prod telemetry, weak attribution) - NOT proof of no escape"
    return "NA", "too young (<7d) to call"


def build_rows(recs, evs, shadow, repo, to_sha=None):
    now = int(time.time())
    evm = events_by_rec(evs)
    groups = collections.OrderedDict()
    for r in sorted(recs, key=lambda x: x["epoch"]):
        groups.setdefault(r.get("feat_tag") or ("item:" + r["key"]), []).append(r)
    gates = [g for g in KNOWN_GATES] + sorted(g for g in shadow if g not in KNOWN_GATES)
    rows = []
    for feat, rs in groups.items():
        shas = [s for r in rs for s in r["commits"]]
        if to_sha:
            shas = shas + [to_sha]
        cells = collections.OrderedDict()
        notes = {}
        for g in gates:
            cells[g], notes[g] = gate_cell(g, shadow, repo, shas)
        cells["escape"], notes["escape"] = escape_cell(rs, evm, now)
        wk = [r.get("weak_oracle") for r in rs if r.get("weak_oracle") is not None]
        cells["oracle"] = "NA" if not wk else ("FLAG" if any(wk) else "PASS")
        notes["oracle"] = "VERIFY is existence-only" if any(wk) else ("VERIFY runs a test/runner" if wk else "no VERIFY text found")
        risk = max((r["risk"] for r in rs), key=lambda x: RISK_ORDER.get(x, 0))
        rows.append({"feature": feat, "records": len(rs), "risk": risk, "tier": ",".join(sorted(set(r["tier"] for r in rs))),
                     "commits": len(set(shas)) - (1 if to_sha else 0), "landed": rs[0]["ts"][:16] + "Z", "type": rs[0].get("type", ""),
                     "flags": sorted(set(f for r in rs for f in r.get("flags", []) if f != "stage")), "cells": cells, "notes": notes,
                     "events": [dict((k, e.get(k)) for k in ("type", "ts", "ref", "confidence", "note")) for r in rs for e in evm.get(r["key"], [])]})
    return rows


def render(title, rows, extra_lines):
    out = [title, "=" * min(100, max(len(title), 60))]
    if not rows:
        out.append("(no ledger records match)")
    cols = list(rows[0]["cells"].keys()) if rows else []
    hdr = "  ".join(c[:10].ljust(10) for c in cols)
    for r in rows:
        out.append("")
        out.append("%s  [risk %s, tier %s, %d rec, %d commit(s), landed %s]%s" % (
            r["feature"][:60], r["risk"], r["tier"], r["records"], r["commits"], r["landed"], ("  flags:" + ",".join(r["flags"])) if r["flags"] else ""))
        out.append("  " + hdr)
        out.append("  " + "  ".join(r["cells"][c].ljust(10) for c in cols))
        for ev in r["events"]:
            out.append("  ! %s %s %s (%s) %s" % (ev["type"], (ev["ts"] or "")[:10], ev["ref"], ev["confidence"], (ev["note"] or "")[:60]))
        bad = [(c, r["notes"][c]) for c in cols if r["cells"][c] in ("FAIL", "FLAG") or (c == "escape" and r["cells"][c] in ("PASS", "UNVERIFIED"))]
        for c, n in bad:
            out.append("  > %s: %s" % (c, n))
    out += [""] + extra_lines
    out.append("Cells: PASS FAIL FLAG NA UNVERIFIED. NA gate = no shadow log exists; UNVERIFIED gate = log exists but nothing covers this feature.")
    out.append("No composite score by design. escape=FAIL means a later revert/hotfix/EMERGENCY/manual-mark was attributed to it.")
    return "\n".join(out)


# ------------------------------------------------------------------ commands
def cmd_feature(argv):
    repo, feat = ql.opt(argv, "--repo"), ql.opt(argv, "--feat")
    recs, evs = ql.load_ledger()
    sel = [r for r in recs if (not repo or r["repo"] == repo) and feat and (r.get("feat_tag") == feat or feat in (r.get("feat_tag") or "") or r["key"] == feat)]
    rows = build_rows(sel, evs, load_shadow(), repo)
    if "--json" in argv:
        print(json.dumps(rows, indent=1, sort_keys=True))
        return 0
    extra = []
    for r in sel[:12]:
        extra.append("  rec %s %s tier %s risk %s (%s) commits=%s basis=%s" % (r["key"], r["ts"][:16], r["tier"], r["risk"], r["risk_basis"][:40],
                                                                        ",".join(s[:8] for s in r["commits"]) or "-", r["commit_basis"]))
    print(render("FEATURE SCORECARD  %s / %s" % (repo or "*", feat), rows, extra))
    return 0


def cmd_promote(argv):
    repo, frm, to = ql.opt(argv, "--repo"), ql.opt(argv, "--from"), ql.opt(argv, "--to")
    rd = qc.repo_dir(repo) if repo else None
    if not (rd and frm and to):
        print("usage: promote --repo R --from REF --to REF (and the repo needs a clone)")
        return 0
    rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", to + "^{commit}")
    to_sha = out.strip() if rc == 0 else ""
    rc, out, err = qc.git(rd, "log", "--no-merges", "--format=%H", "%s..%s" % (frm, to))
    if rc != 0:
        print("UNVERIFIED: git log %s..%s failed: %s" % (frm, to, err[:120]))
        return 0
    shas = [s for s in out.split() if s]
    recs, evs = ql.load_ledger()
    sel, matched = [], set()
    for r in recs:
        if r["repo"] == repo and any(c in shas for c in r["commits"]):
            sel.append(r)
            matched.update(c for c in r["commits"] if c in shas)
    rows = build_rows(sel, evs, load_shadow(), repo, to_sha=to_sha or None)
    unmatched = [s for s in shas if s not in matched]
    housekeeping = 0
    human = 0
    for s in unmatched:
        rc, o, _ = qc.git(rd, "show", "-s", "--format=%s", s)
        if ql.HOUSEKEEPING.search(o.strip()):
            housekeeping += 1
        else:
            human += 1
    extra = ["Range %s..%s: %d non-merge commits; %d belong to %d ledger feature(s); %d pipeline housekeeping; %d other (human / not attributed)."
             % (frm, to, len(shas), len(matched), len(rows), housekeeping, human)]
    if human:
        extra.append("  The %d unattributed commit(s) have NO ledger row: they are not covered by this card (read them, or mark-escape later)." % human)
    if "--json" in argv:
        print(json.dumps({"range": [frm, to], "commits": len(shas), "unattributed": human, "features": rows}, indent=1, sort_keys=True))
        return 0
    print(render("PROMOTE SCORECARD  %s  %s..%s" % (repo, frm, to), rows, extra))
    return 0


def pct(n, d):
    return "%.1f%%" % (100.0 * n / d) if d else "n/a"


def per100(n, d):
    return "%.1f" % (100.0 * n / d) if d else "n/a"


def cmd_report(argv):
    days = int(ql.opt(argv, "--days", "30") or 30)
    mature = int(ql.opt(argv, "--mature-days", "7") or 7)
    repo = ql.opt(argv, "--repo")
    now = int(time.time())
    recs, evs = ql.load_ledger()
    recs = [r for r in recs if now - r["epoch"] <= days * DAY and (not repo or r["repo"] == repo)]
    evm = events_by_rec(evs)

    def strong(e):
        return e["type"] in ("revert", "escape") or (e["type"] == "hotfix" and e.get("confidence") == "strong") or \
               (e["type"] in ("emergency", "test_watch_red") and e.get("confidence") == "file-overlap")

    feats = collections.OrderedDict()
    for r in sorted(recs, key=lambda x: x["epoch"]):
        feats.setdefault((r["repo"], r.get("feat_tag") or "item:" + r["key"]), []).append(r)
    rows = []
    for (rp, ft), rs in feats.items():
        es = [e for r in rs for e in evm.get(r["key"], []) if e["type"] in ESCAPE_TYPES]
        rows.append({"repo": rp, "feat": ft, "risk": max((r["risk"] for r in rs), key=lambda x: RISK_ORDER.get(x, 0)), "type": rs[0].get("type", ""),
                     "mature": all(now - r["epoch"] >= mature * DAY for r in rs), "any": bool(es), "strong": any(strong(e) for e in es),
                     "types": sorted(set(e["type"] for e in es)), "has_commits": any(r["commits"] for r in rs)})
    lines = ["ESCAPE REPORT  last %dd%s  (generated %s)" % (days, ("  repo=" + repo) if repo else "", ql.iso(now)), "=" * 78]
    lines.append("landed records: %d   features: %d   (features younger than %dd are excluded from rates: their 7d windows are still open)"
                 % (len(recs), len(rows), mature))
    mat = [x for x in rows if x["mature"]]
    lines.append("mature features: %d   escaped (strong signals): %d   escaped (any signal): %d   -> per 100: strong %s, any %s"
                 % (len(mat), sum(x["strong"] for x in mat), sum(x["any"] for x in mat),
                    per100(sum(x["strong"] for x in mat), len(mat)), per100(sum(x["any"] for x in mat), len(mat))))
    lines.append("Escapes are UNDERCOUNTED: no prod telemetry; a signal needs a revert/fix/EMERGENCY commit or a manual mark-escape.")
    out = {"days": days, "records": len(recs), "features": len(rows), "mature_features": len(mat)}

    def table(title, keyfn):
        d = collections.defaultdict(lambda: [0, 0, 0, 0])
        for x in rows:
            k = keyfn(x)
            d[k][0] += 1
            if x["mature"]:
                d[k][1] += 1
                d[k][2] += int(x["strong"])
                d[k][3] += int(x["any"])
        lines.append("")
        lines.append("%-22s %9s %8s %8s %7s  %9s %9s" % (title, "features", "mature", "esc-str", "esc-any", "str/100", "any/100"))
        for k in sorted(d):
            f, m, s, a = d[k]
            lines.append("%-22s %9d %8d %8d %7d  %9s %9s" % (str(k)[:22], f, m, s, a, per100(s, m), per100(a, m)))
        out[title] = {str(k): v for k, v in d.items()}

    table("repo", lambda x: x["repo"])
    table("risk class", lambda x: x["risk"])
    table("type", lambda x: x["type"] or "?")
    table("risk x repo", lambda x: "%s/%s" % (x["risk"], x["repo"]))

    wk = [r.get("weak_oracle") for r in recs if r.get("weak_oracle") is not None]
    untested = sum(1 for r in recs if "untested-change" in r.get("flags", []))
    suspect = sum(1 for r in recs if "redgreen-suspect" in r.get("flags", []))
    lines.append("")
    lines.append("weak-oracle share (VERIFY existence-only): %s of %d records with VERIFY text found (%d of %d records had no item text -> unknown)"
                 % (pct(sum(wk), len(wk)), len(wk), len(recs) - len(wk), len(recs)))
    lines.append("status flags on landed records: untested-change %d (%s), redgreen:SUSPECT %d (%s)" % (untested, pct(untested, len(recs)), suspect, pct(suspect, len(recs))))
    lines.append("commit attribution: %d of %d records have time-window commits (events by file overlap only work for those)"
                 % (sum(1 for r in recs if r["commits"]), len(recs)))
    # stage-unverified counts come straight from outcomes.jsonl (those never land, so they are not ledger rows)
    su = collections.Counter()
    tot = collections.Counter()
    unreadable = 0
    try:
        with open(ql.paths()["outcomes"], "rb") as f:
            for raw in f:
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    unreadable += 1
                    continue
                if not isinstance(d, dict) or not isinstance(d.get("repo"), str) or not isinstance(d.get("status", ""), (str, type(None))):
                    unreadable += 1
                    continue
                e = ql.epoch(d.get("ts"))
                if not e or now - e > days * DAY or (repo and d.get("repo") != repo):
                    continue
                tot[d.get("repo")] += 1
                if "stage-unverified" in (d.get("status") or ""):
                    su[d.get("repo")] += 1
    except OSError:
        pass
    lines.append("stage-unverified outcomes (staged work the verifier could not confirm): %d total  %s" % (sum(su.values()),
                 ", ".join("%s=%d" % (k, v) for k, v in sorted(su.items()))))
    if unreadable:
        lines.append("WARNING: %d outcomes.jsonl line(s) were unreadable (bad json / non-object / wrong field types) and are NOT in the stage-unverified counts." % unreadable)
    out["stage_unverified"] = dict(su)
    out["unreadable_outcome_rows"] = unreadable
    ev_types = collections.Counter(e["type"] for e in evs if now - e.get("epoch", 0) <= days * DAY and (not repo or e.get("repo") == repo))
    unattr = collections.Counter(e["type"] for e in evs if not e.get("rec") and e["type"] != "escape" and now - e.get("epoch", 0) <= days * DAY
                                 and (not repo or e.get("repo") == repo))
    lines.append("events in window: " + (", ".join("%s=%d" % kv for kv in sorted(ev_types.items())) or "none") +
                 "   repo-level EMERGENCY/test-watch events with no attributable feature: " + (", ".join("%s=%d" % kv for kv in sorted(unattr.items())) or "none"))
    if "--json" in argv:
        print(json.dumps(out, indent=1, sort_keys=True, default=str))
    else:
        print("\n".join(lines))
    return 0


def main(argv):
    if not argv or argv[0] not in ("feature", "promote", "report"):
        sys.stderr.write(__doc__)
        return 2
    try:
        return {"feature": cmd_feature, "promote": cmd_promote, "report": cmd_report}[argv[0]](argv[1:])
    except Exception as ex:  # noqa: BLE001 - a scorecard must never crash a caller
        print("UNVERIFIED: scorecard crashed: %s: %s" % (type(ex).__name__, ex))
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
