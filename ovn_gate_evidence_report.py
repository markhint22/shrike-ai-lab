#!/usr/bin/env python3
"""ovn_gate_evidence_report.py - per-gate PROMOTION EVIDENCE for the shadow QA gates (package K6, 2026-11-01). Read-only, advisory, never changes a gate mode.

Why: shadow gates write rows but nothing decided promotion. This joins every FLAG / FAIL / UNVERIFIED verdict with the LATER outcome of the same work
(state/outcomes.jsonl) and applies one fixed rule:   PROMOTE-CANDIDATE only with  >= 14 clean days AND >= 30 FLAG/FAIL events AND proxy precision >= 0.8;
otherwise HOLD, with every failing reason listed. A PROMOTE-CANDIDATE is a suggestion for a human (ovn_gate_governor.py promote still has its own criteria).

    ovn_gate_evidence_report.py [--days N] [--gate G] [--json] [--digest] [--state DIR]

Sources (formats are the real ones; see scripts/test/fixtures_gate_evidence):
  state/qa_shadow/<gate>.jsonl   {ts, gate, repo, ref (sha or base..head), verdict PASS|FLAG|FAIL|NA|UNVERIFIED, summary, details}  (qa/qa_common.py record())
  state/spec_gate.jsonl          {ts, repo, feat, item_key, action: pass|flag:<rule>|quarantine:<rule>, ...}      -> FLAG for flag:*, FAIL for quarantine:*
  state/executor_shadow.log      TSV: ts repo tool mode action item_hash reason stamp                              -> gate executor:<tool>; would-apply = FLAG
  state/stage_runs/*.jsonl       events item_verify (decision refuse:* = would-block) and red_before (detail "RB weak*"); time = the run id (UTC)
  state/outcomes.jsonl           later outcome rows (class, status, fail_reason, commits, item_hash, feat_tag)
  state/stage_credited.ledger    stage run files whose item WAS credited (item_verify: "would have blocked, credited anyway")

Join (an event is matched to outcome rows of the SAME repo within [event - slack, event + window]; window default 24h, slack 15 min):
  by commit (the verdict's ref / head sha is in outcome.commits or head_after) OR item_hash OR feat tag, then every row sharing the item_hash / feat tag of those (two hops: a later revert row carries the item, not the commit).
  outcome of an event:  BAD  = any matched row later reverted or parked (class reverted, status revert*/park*, fail_reason build-red|ts-regression|test-red)
                        GREEN = no bad row and a matched row landed (class landed / landed-late / credit-only / landed-uncredited)
                        unresolved = nothing decisive yet (still inside the window, or nothing matched); unjoined = no key matched any outcome row
  % reverted/parked = BAD / (BAD+GREEN) is the TRUE-POSITIVE proxy; % green = GREEN / (BAD+GREEN) is the FALSE-POSITIVE proxy. Unresolved events are shown, never guessed.
  A flagged item is reverted/parked for MANY reasons (a red test unrelated to the gate), so the proxy over-states precision. It is a floor on the evidence needed, not proof.

UNVERIFIED is reported SEPARATELY and is never clean: a day with any UNVERIFIED row, or with no verified (PASS/FLAG/FAIL) row at all, is not a clean day. 'Days of clean
evidence' = the trailing run of consecutive UTC days (ending today, or yesterday if today has no rows yet) that are clean. UNVERIFIED rows get a reason code:
tool-missing (ruff/bandit/gitleaks/mutmut... not installed; reason_code written by gate_scanners.py/gate_mutation.py, or recognised from older rows' text), cap (time/chunk cap),
partial (partial analysis), other.

Digest hook: digest_notify.sh appends ONE bullet from `--digest` only when OVN_GATE_EVIDENCE_DIGEST=on (default off).
Env: OVN_STATE_DIR / QA_STATE_DIR / OVN_DIR (state dir)  OVN_GER_NOW (epoch, tests)  OVN_GER_WINDOW_H (24)  OVN_GER_SLACK_S (900)
     OVN_GER_MIN_DAYS (14) OVN_GER_MIN_EVENTS (30) OVN_GER_MIN_PRECISION (0.8)
Pure stdlib. Exit 0 always (2 on usage error).
"""
import argparse
import calendar
import collections
import glob
import json
import os
import re
import sys
import time

TS_FMT = "%Y-%m-%dT%H:%M:%SZ"
FACING = ("FLAG", "FAIL")
BAD_CLASSES = {"reverted", "parked"}
BAD_FAIL_REASONS = {"build-red", "ts-regression", "test-red"}
GREEN_CLASSES = {"landed", "landed-late", "credit-only", "landed-uncredited"}
TOOL_RE = re.compile(r"\b([A-Za-z][\w.-]*) (?:is )?not installed")
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")


def fnum(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def state_dir(arg=None):
    if arg:
        return arg
    for k in ("OVN_STATE_DIR", "QA_STATE_DIR"):
        if os.environ.get(k):
            return os.environ[k]
    return os.path.join(os.environ.get("OVN_DIR") or os.path.join(os.path.expanduser("~"), "overnight-queue"), "state")


def epoch(ts):
    try:
        return calendar.timegm(time.strptime(ts, TS_FMT))
    except (TypeError, ValueError):
        return None


def run_id_epoch(run):
    try:
        return calendar.timegm(time.strptime(str(run)[:15], "%Y%m%d-%H%M%S"))
    except (TypeError, ValueError):
        return None


def day_of(t):
    return time.strftime("%Y-%m-%d", time.gmtime(t))


def read_jsonl(path):
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict):
                    yield d
    except OSError:
        return


# ------------------------------------------------------------------------------------------------------------------ unverified reason codes
def unverified_reason(row):
    """-> (code, tools). Prefers the explicit reason_code the gates now write; falls back to the text of older rows."""
    det = row.get("details") or {}
    if not isinstance(det, dict):
        det = {}
    code = det.get("reason_code")
    tools = list(det.get("tools_missing") or [])
    cells = det.get("cells") or {}
    if isinstance(cells, dict):
        for t, c in cells.items():
            if isinstance(c, dict) and c.get("status") == "UNVERIFIED" and (c.get("reason_code") == "tool-missing" or TOOL_RE.search(c.get("note") or "")):
                if t not in tools:
                    tools.append(t)
    summ = row.get("summary") or ""
    if not tools:
        tools = [m for m in TOOL_RE.findall(summ)]
    if code == "tool-missing" or tools:
        return "tool-missing", sorted(set(tools))
    if code:
        return str(code), []
    s = summ.lower()
    if "cap" in s or "timeout" in s or "timed out" in s:
        return "cap", []
    if "partial" in s or "could not be analysed" in s:
        return "partial", []
    return "other", []


# ------------------------------------------------------------------------------------------------------------------ events
class Ev(object):
    __slots__ = ("gate", "cls", "ts", "repo", "commits", "hashes", "feat", "row", "credited", "src")

    def __init__(self, gate, cls, ts, repo, commits=(), hashes=(), feat="", row=None, credited=None, src=""):
        self.gate, self.cls, self.ts, self.repo = gate, cls, ts, repo
        self.commits, self.hashes, self.feat = [c for c in commits if c], [h for h in hashes if h], feat or ""
        self.row, self.credited, self.src = row or {}, credited, src


def head_of(ref):
    ref = str(ref or "")
    return ref.split("..")[-1].strip()


def load_qa_shadow(sd):
    out = []
    for p in sorted(glob.glob(os.path.join(sd, "qa_shadow", "*.jsonl"))):
        stem = os.path.splitext(os.path.basename(p))[0]
        for r in read_jsonl(p):
            t = epoch(r.get("ts"))
            v = r.get("verdict")
            if t is None or not v:
                continue
            det = r.get("details") if isinstance(r.get("details"), dict) else {}
            hashes = [det.get("item_key")] if det.get("item_key") else []
            out.append(Ev(r.get("gate") or stem, str(v), t, r.get("repo") or "", [head_of(r.get("ref"))], hashes, "", r, src="qa_shadow"))
    return out


def load_spec_gate(sd):
    out = []
    for r in read_jsonl(os.path.join(sd, "spec_gate.jsonl")):
        t = epoch(r.get("ts"))
        a = str(r.get("action") or "")
        if t is None:
            continue
        cls = "PASS" if a == "pass" else "FAIL" if a.startswith("quarantine") else "FLAG" if a.startswith("flag") else "NA"
        k = str(r.get("item_key") or "").split("-")[0]
        out.append(Ev("spec_gate", cls, t, r.get("repo") or "", [], [k], r.get("feat") or "", r, src="spec_gate"))
    return out


def load_executor(sd):
    out = []
    try:
        f = open(os.path.join(sd, "executor_shadow.log"), errors="replace")
    except OSError:
        return out
    with f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 6:
                continue
            t = epoch(p[0])
            if t is None:
                continue
            act = p[4]
            cls = "FLAG" if act.startswith("would-") else "UNVERIFIED" if act.startswith("error") else "NA"
            out.append(Ev("executor:" + p[2], cls, t, p[1], [], [p[5]], "", {"action": act, "reason": p[6] if len(p) > 6 else ""}, src="executor_shadow"))
    return out


def load_stage_events(sd):
    """item_verify / red_before from state/stage_runs/*.jsonl. The run's item (decomposed event) gives the feat tag; the run id gives the time."""
    out = []
    ledger = set()
    try:
        for ln in open(os.path.join(sd, "stage_credited.ledger"), errors="replace"):
            ledger.add(os.path.basename(ln.strip()))
    except OSError:
        pass
    for p in sorted(glob.glob(os.path.join(sd, "stage_runs", "*.jsonl"))):
        feat, repo, evs = "", "", []
        try:
            f = open(p, errors="replace")
        except OSError:
            continue
        with f:
            for line in f:
                if "item_verify" not in line and "red_before" not in line and '"decomposed"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(r, dict):
                    continue
                if r.get("event") == "decomposed":
                    repo = r.get("repo") or repo
                    m = re.search(r"\[feat:([^\]]+)\]", r.get("item") or "")
                    feat = m.group(1) if m else feat
                elif r.get("event") in ("item_verify", "red_before"):
                    evs.append(r)
        base = os.path.basename(p)
        for r in evs:
            t = run_id_epoch(r.get("run"))
            if t is None:
                continue
            if r["event"] == "item_verify":
                d = str(r.get("decision") or "")
                cls = "FLAG" if d.startswith("refuse") else "PASS" if d == "OK" else "NA"
            else:
                d = str(r.get("detail") or "")
                cls = "FLAG" if d.startswith("RB weak") else "PASS" if d.startswith("RB ok") else "NA"
            out.append(Ev(r["event"], cls, t, repo or r.get("repo") or "", [], [], feat, r, credited=(base in ledger), src="stage_runs"))
    return out


# ------------------------------------------------------------------------------------------------------------------ outcomes + join
def outcome_kind(r):
    cls = str(r.get("class") or "")
    st = str(r.get("status") or "").lower()
    if cls in BAD_CLASSES or "revert" in st or "park" in st or (r.get("fail_reason") in BAD_FAIL_REASONS):
        return "bad"
    if cls in GREEN_CLASSES:
        return "green"
    return "neutral"


class Outcomes(object):
    def __init__(self, rows):
        self.by_commit = collections.defaultdict(list)
        self.by_hash = collections.defaultdict(list)
        self.by_feat = collections.defaultdict(list)
        for r in rows:
            t = epoch(r.get("ts"))
            if t is None:
                continue
            hs = [str(h)[:12] for h in (r.get("item_hash"), r.get("item_line_hash")) if h]
            rec = (t, outcome_kind(r), r.get("repo") or "", hs, r.get("feat_tag") or "")
            for c in list(r.get("commits") or []) + [r.get("head_after")]:
                if c and SHA_RE.match(str(c)):
                    self.by_commit[str(c)[:12]].append(rec)
            for h in hs:
                self.by_hash[h].append(rec)
            if r.get("feat_tag"):
                self.by_feat[r["feat_tag"]].append(rec)

    def match(self, ev):
        """-> (matched_any, [(t, kind)]). Two hops, same repo: (1) rows sharing the event's commit / item_hash / feat tag; (2) every row sharing the item_hash or feat tag of a
        hop-1 row. The second hop is what finds a LATER revert/park: that row carries the item, never the landed commit."""
        def ok_repo(rec):
            return (not ev.repo) or (not rec[2]) or rec[2] == ev.repo
        first = []
        for idx, ks in ((self.by_commit, [c[:12] for c in ev.commits if SHA_RE.match(c)]),
                        (self.by_hash, [h[:12] for h in ev.hashes if h]),
                        (self.by_feat, [ev.feat] if ev.feat else [])):
            for k in ks:
                first += [x for x in idx.get(k, []) if ok_repo(x)]
        if not first:
            return None, []
        hs = {h for x in first for h in x[3]}
        fs = {x[4] for x in first if x[4]}
        seen = {id(x): x for x in first}
        for h in hs:
            for x in self.by_hash.get(h, []):
                if ok_repo(x):
                    seen[id(x)] = x
        for f in fs:
            for x in self.by_feat.get(f, []):
                if ok_repo(x):
                    seen[id(x)] = x
        return True, [(x[0], x[1]) for x in seen.values()]


def resolve(ev, outs, now, window_s, slack_s):
    """-> 'bad' | 'green' | 'unresolved' | 'unjoined'."""
    key, recs = outs.match(ev)
    if key is None:
        return "unjoined"
    inwin = [(t, k) for (t, k) in recs if ev.ts - slack_s <= t <= ev.ts + window_s]
    if any(k == "bad" for _, k in inwin):
        return "bad"
    if any(k == "green" for _, k in inwin):
        return "green"
    return "unresolved"


# ------------------------------------------------------------------------------------------------------------------ report
def clean_days(evs, now):
    days = collections.defaultdict(lambda: [0, 0])      # day -> [verified rows, unverified rows]
    for e in evs:
        if e.cls == "UNVERIFIED":
            days[day_of(e.ts)][1] += 1
        elif e.cls in ("PASS", "FLAG", "FAIL"):
            days[day_of(e.ts)][0] += 1
    d = int(now // 86400) * 86400
    if day_of(d) not in days:
        d -= 86400
    n = 0
    while True:
        v, u = days.get(day_of(d), (0, 0))
        if v > 0 and u == 0:
            n += 1
            d -= 86400
        else:
            break
    return n


def pct(a, b):
    return None if not b else round(100.0 * a / b, 1)


def build(sd, days=30, only=None, now=None):
    now = now if now is not None else float(os.environ.get("OVN_GER_NOW") or time.time())
    window_s = fnum("OVN_GER_WINDOW_H", 24) * 3600
    slack_s = fnum("OVN_GER_SLACK_S", 900)
    min_days, min_events, min_prec = int(fnum("OVN_GER_MIN_DAYS", 14)), int(fnum("OVN_GER_MIN_EVENTS", 30)), fnum("OVN_GER_MIN_PRECISION", 0.8)
    since = now - days * 86400
    evs = [e for e in load_qa_shadow(sd) + load_spec_gate(sd) + load_executor(sd) + load_stage_events(sd) if e.ts >= since]
    if only:
        evs = [e for e in evs if e.gate == only]
    outs = Outcomes(read_jsonl(os.path.join(sd, "outcomes.jsonl")))
    # qa_gate_skips.jsonl: daily passes that never ran (e.g. mutmut missing). Not verdict rows: shown as skips, never as clean evidence.
    skips = collections.defaultdict(collections.Counter)
    for r in read_jsonl(os.path.join(sd, "qa_gate_skips.jsonl")):
        t = epoch(r.get("ts"))
        if t is not None and t >= since and r.get("gate") and (not only or r["gate"] == only):
            code = r.get("reason_code") or ("tool-missing" if TOOL_RE.search(str(r.get("reason") or "")) else "other")
            skips[r["gate"]][code] += 1
            if code == "tool-missing":
                skips[r["gate"]]["_last_tool_missing"] = max(skips[r["gate"]]["_last_tool_missing"], t)
    by_gate = collections.defaultdict(list)
    for e in evs:
        by_gate[e.gate].append(e)
    gates = []
    for g in sorted(set(by_gate) | set(skips)):
        ge = by_gate.get(g, [])
        total = collections.Counter(e.cls for e in ge)
        classes = {}
        for c in FACING + ("UNVERIFIED",):
            sel = [e for e in ge if e.cls == c]
            if not sel:
                continue
            res = collections.Counter(resolve(e, outs, now, window_s, slack_s) for e in sel) if c != "UNVERIFIED" else collections.Counter()
            ent = {"n": len(sel)}
            if c != "UNVERIFIED":
                b, gr = res["bad"], res["green"]
                ent.update({"reverted_parked": b, "green": gr, "unresolved": res["unresolved"], "unjoined": res["unjoined"],
                            "pct_reverted_parked": pct(b, b + gr), "pct_green": pct(gr, b + gr)})
            classes[c] = ent
        ff = [e for e in ge if e.cls in FACING]
        res_all = collections.Counter(resolve(e, outs, now, window_s, slack_s) for e in ff)
        b, gr = res_all["bad"], res_all["green"]
        prec = (float(b) / (b + gr)) if (b + gr) else None
        unv = [e for e in ge if e.cls == "UNVERIFIED"]
        codes = collections.Counter()
        tools = {}
        for e in unv:
            code, tl = unverified_reason(e.row)
            codes[code] += 1
            for t in tl:
                x = tools.setdefault(t, {"n": 0, "last": 0})
                x["n"] += 1
                x["last"] = max(x["last"], e.ts)
        cd = clean_days(ge, now)
        sk = {k: v for k, v in skips.get(g, {}).items() if not k.startswith("_")}
        reasons = []
        if sk:
            reasons.append("%d daily-pass skip(s) (%s): the gate did not run - not evidence" % (sum(sk.values()), ", ".join("%s %d" % kv for kv in sorted(sk.items()))))
            if sk.get("tool-missing"):
                tools.setdefault("(tool for skipped pass, e.g. mutmut)", {"n": sk["tool-missing"], "last": skips[g]["_last_tool_missing"]})
        if cd < min_days:
            reasons.append("clean days %d < %d" % (cd, min_days))
        if len(ff) < min_events:
            reasons.append("FLAG/FAIL events %d < %d" % (len(ff), min_events))
        if prec is None:
            reasons.append("proxy precision n/a (0 joined+decided FLAG/FAIL events)")
        elif b + gr < min_events:
            # extra guard (stricter than the stated rule): a precision over a handful of decided events is not evidence (2026-11-01: antigaming had 197 FLAG/FAIL but only 8 decided)
            reasons.append("only %d FLAG/FAIL events are joined+decided (< %d): proxy precision %.2f is not trustworthy" % (b + gr, min_events, prec))
        elif prec < min_prec:
            reasons.append("proxy precision %.2f < %.2f" % (prec, min_prec))
        if unv:
            reasons.append("%d UNVERIFIED row(s) in window (%s): never counted as clean" % (len(unv), ", ".join("%s %d" % kv for kv in codes.most_common())))
        if tools:
            reasons.append("tool missing: " + ", ".join("%s (%d rows, last %s)" % (t, v["n"], day_of(v["last"])) for t, v in sorted(tools.items())))
        # UNVERIFIED rows are listed as notes; they block promotion through clean_days (a day with one is not clean), never by being counted as clean
        hard = [r for r in reasons if "UNVERIFIED" not in r and not r.startswith("tool missing") and "daily-pass skip" not in r]
        rec = "HOLD" if hard else "PROMOTE-CANDIDATE"
        gates.append({"gate": g, "rows": len(ge), "verdicts": dict(total), "classes": classes, "flag_fail_events": len(ff),
                      "flag_fail_decided": b + gr, "flag_fail_reverted_parked": b, "flag_fail_green": gr, "flag_fail_unresolved": res_all["unresolved"],
                      "flag_fail_unjoined": res_all["unjoined"], "proxy_precision": None if prec is None else round(prec, 3), "clean_days": cd,
                      "unverified": {"n": len(unv), "reason_codes": dict(codes), "tools_missing": tools}, "skips": sk,
                      "recommendation": rec, "reasons": reasons})
    return {"generated": time.strftime(TS_FMT, time.gmtime(now)), "days": days, "window_h": window_s / 3600.0,
            "rule": {"min_clean_days": min_days, "min_flag_fail_events": min_events, "min_proxy_precision": min_prec},
            "gates": gates, "known_facts": known_facts(gates, by_gate, sd)}


def known_facts(gates, by_gate, sd):
    facts = []
    G = {g["gate"]: g for g in gates}
    iv = by_gate.get("item_verify")
    if iv:
        blocks = [e for e in iv if e.cls == "FLAG"]
        cred = [e for e in blocks if e.credited]
        facts.append("item_verify would have blocked %d case(s); %d of them were credited anyway (stage_credited.ledger)%s." % (
            len(blocks), len(cred), " - the gate has never stopped a credit, so its precision cannot be judged from outcomes alone" if blocks and len(cred) == len(blocks) else ""))
    cc = by_gate.get("card_credit")
    if cc:
        fl = sum(1 for e in cc if e.cls == "FLAG")
        nocard = sum(1 for e in cc if (e.row.get("details") or {}).get("credit_without_card"))
        facts.append("card_credit fired FLAG on %d/%d row(s) (%d are credit_without_card): the acceptance-card pilot is not producing cards, so the FLAG carries no signal%s." % (
            fl, len(cc), nocard, "; silence-worthy" if fl == len(cc) else ""))
    for name in ("mutation", "scanners"):
        g = G.get(name)
        if g:
            u = g["unverified"]
            tm = u["tools_missing"]
            facts.append("%s: %d UNVERIFIED of %d row(s); reason codes %s; tool-missing: %s." % (
                name, u["n"], g["rows"], json.dumps(u["reason_codes"], sort_keys=True),
                ", ".join("%s (last %s)" % (t, day_of(v["last"])) for t, v in sorted(tm.items())) if tm else "none seen in window"))
    return facts


def render(rep):
    L = ["Gate evidence report  %s  (last %dd; join window %gh)" % (rep["generated"], rep["days"], rep["window_h"]),
         "Rule: promote only with >= %(min_clean_days)d clean days, >= %(min_flag_fail_events)d FLAG/FAIL events, proxy precision >= %(min_proxy_precision)g; else HOLD." % rep["rule"],
         "Proxy: %reverted/parked = true-positive proxy, %green = false-positive proxy. UNVERIFIED is separate and never clean.", ""]
    for g in rep["gates"]:
        L.append("%-18s %s   rows=%d clean_days=%d  FLAG/FAIL=%d" % (g["gate"], g["recommendation"], g["rows"], g["clean_days"], g["flag_fail_events"]))
        for c, e in sorted(g["classes"].items()):
            if c == "UNVERIFIED":
                L.append("    UNVERIFIED  n=%d (separate, not clean) reasons=%s" % (e["n"], json.dumps(g["unverified"]["reason_codes"], sort_keys=True)))
            else:
                f = lambda v: "n/a" if v is None else "%g%%" % v  # noqa: E731
                L.append("    %-10s n=%d  reverted/parked=%d (%s)  green=%d (%s)  unresolved=%d  unjoined=%d" % (
                    c, e["n"], e["reverted_parked"], f(e["pct_reverted_parked"]), e["green"], f(e["pct_green"]), e["unresolved"], e["unjoined"]))
        for r in g["reasons"]:
            L.append("    - " + r)
    L += ["", "Known facts (computed from the data above):"] + ["  * " + x for x in rep["known_facts"]]
    return "\n".join(L)


def digest(rep):
    """ONE short bullet for the digest."""
    gs = rep["gates"]
    cand = [g["gate"] for g in gs if g["recommendation"] == "PROMOTE-CANDIDATE"]
    unv = sum(g["unverified"]["n"] for g in gs)
    tm = sorted({t for g in gs for t in g["unverified"]["tools_missing"]})
    return "Gate evidence: %d shadow gate(s), %d promote-candidate(s)%s, %d UNVERIFIED row(s) not counted clean%s" % (
        len(gs), len(cand), (" (" + ", ".join(cand) + ")") if cand else " (all HOLD)", unv, ("; tool missing: " + ", ".join(tm)) if tm else "")


def main(argv=None):
    ap = argparse.ArgumentParser(description="per-gate promotion evidence (read-only)")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--gate")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--digest", action="store_true", help="print the single digest bullet (digest_notify.sh calls this only when OVN_GATE_EVIDENCE_DIGEST=on)")
    ap.add_argument("--state")
    a = ap.parse_args(argv)
    try:
        rep = build(state_dir(a.state), a.days, a.gate)
    except Exception as ex:  # noqa: BLE001 - advisory tool, never break a caller
        print("ovn_gate_evidence_report: failed: %s: %s" % (type(ex).__name__, ex), file=sys.stderr)
        return 0
    if a.digest:
        print(digest(rep))
    elif a.json:
        print(json.dumps(rep, sort_keys=True, indent=1))
    else:
        print(render(rep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
