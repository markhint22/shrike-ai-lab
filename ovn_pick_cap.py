#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_pick_cap.py - per-item PICK CAP (package q-already-done-credit, 2026-11-13). SHADOW by default.

Problem (nov12-13 fleet review): ~20-25% of cycles went to items that never land: TAA 3f096a1a landed three duplicate commits then came back as ALREADY-DONE three more times; xlite 5de203e0 was
picked 10 times in 10 h. Every existing cap misses this class: ovn_item_guard.sh's rolling day cap EXCLUDES no-op(ALREADY-DONE), the no-op streak is CONSECUTIVE (any other cycle resets it) and
landed-uncredited cycles take the guard's landing branch and exit before any cap runs.

This is a pure function over state/outcomes.jsonl (record_outcome writes the cycle's row BEFORE the guard runs). For one item key it counts the BAD PICKS inside a rolling window (default 24 h)
since the item's last CREDITED landing (class landed / credit-only), where a bad pick is a row whose class/status is one of
  noop ALREADY-DONE | landed-uncredited | reverted-red (no-op(reverted*), reverted*) | fixup-undid (no-op(fixup-undid-item*)).
Other results (stage-unverified, timeout, ...) are not counted: the existing day cap / streak caps own them. At >= N (default 4) the item "trips".

key = item_hash (the FEATURE-level identity every guard counter and the fleet review use; the line hash of one item changes between picks, xlite 5de203e0 showed 5 different line hashes in 10 picks).
Siblings of one [feat:] tag share it, so a credited landing only forgives the bad picks of the SAME item line (item_line_hash), never the picks of its siblings'; the bad picks of a feature
group therefore pool (the fleet parks the picked line only, the siblings stay workable).

CLI
  ovn_pick_cap.py check --outcomes F --repo R --key K [--n 4] [--hours 24] [--now EPOCH]   -> prints JSON {trip, count, kinds, ...}; rc 0 always
  ovn_pick_cap.py cycle --outcomes F --repo R --prog OVERNIGHT_PROGRESS.md [--n 4] [--hours 24] [--kinds a,b]   -> guard hook (TSV: trip count kinds line_no key why)
  ovn_pick_cap.py replay --outcomes F [--n 4] [--hours 24] [--kinds a,b] [--since ISO] [--until ISO]    -> read-only corpus replay: capped items, cycles / GPU minutes saved, later-landed (false capping) list
"""
import hashlib
import json
import re
import sys
import time
from calendar import timegm

BAD_KINDS = ("already-done", "landed-uncredited", "reverted-red", "fixup-undid")
CREDITED = ("landed", "credit-only")


def parse_ts(s):
    try:
        return timegm(time.strptime(str(s), "%Y-%m-%dT%H:%M:%SZ"))
    except (ValueError, TypeError):
        return None


def kind_of(row):
    """the bad-pick kind of an outcomes row, '' when the row is not one."""
    cls = str(row.get("class") or "")
    st = str(row.get("status") or "")
    if cls == "landed-uncredited":
        return "landed-uncredited"
    if cls == "noop" and st.startswith("no-op(ALREADY-DONE"):
        return "already-done"
    if st.startswith("no-op(fixup-undid-item"):
        return "fixup-undid"
    if cls in ("noop", "reverted") and (st.startswith("reverted") or st.startswith("no-op(reverted")):
        return "reverted-red"
    return ""


def row_key(row):
    return str(row.get("item_hash") or row.get("item_line_hash") or "")


def row_line(row):
    return str(row.get("item_line_hash") or "")


def load(path):
    rows = []
    try:
        with open(path, errors="replace") as f:
            for ln in f:
                ln = ln.strip()
                if not ln.startswith("{"):
                    continue
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                t = parse_ts(r.get("ts"))
                if t is None:
                    continue
                r["_t"] = t
                rows.append(r)
    except OSError:
        pass
    rows.sort(key=lambda r: r["_t"])
    return rows


def count_picks(rows, repo, key, now, n=4, hours=24, kinds=BAD_KINDS):
    """bad picks of (repo, key) in (now-hours, now], since the last credited landing. rows = load() output."""
    lo = now - hours * 3600
    bad = []
    for r in rows:
        if r["_t"] > now or str(r.get("repo")) != repo or row_key(r) != key:
            continue
        if str(r.get("class")) in CREDITED:
            bad = [b for b in bad if b[3] != row_line(r)]     # a credited landing forgives the bad picks of that very item line
            continue
        k = kind_of(r)
        if k in kinds and r["_t"] > lo:
            bad.append((r["_t"], k, float(r.get("duration_s") or 0), row_line(r)))
    mix = {}
    for _, k, _d, _l in bad:
        mix[k] = mix.get(k, 0) + 1
    return {"trip": len(bad) >= n, "count": len(bad), "n": n, "kinds": mix, "gpu_s": sum(b[2] for b in bad)}


PARKED = re.compile(r"AUTO-SKIP|HUMAN-ONLY|HARD FILE BAN|\[CLAUDE\]|BLOCKED")


def _md5(t):
    return hashlib.md5(t.encode("utf-8", "replace")).hexdigest()


def _body(line):
    return re.sub(r"^- \[[ xX]\] ", "", line.rstrip("\n"))


def _item_hash(body):
    """== lib_item_select.sh ovn_item_hash: feat-tag identity with the date stamp stripped, else the md5 of the text."""
    f = re.search(r"\[feat:[^\]]+\]", body)
    if f:
        ft = re.sub(r"-\d{6}-", "-", re.sub(r"-\d{8}-", "-", f.group(0)))
        return _md5(ft)
    return _md5(body)


def cycle(rows, repo, prog_path, now, n=4, hours=24, kinds=BAD_KINDS, fresh_s=900):
    """what the item guard asks right after record_outcome wrote this cycle's row: does the item the cycle just worked trip the cap, and which OPEN progress line is it?
    line_no 0 = nothing to park (the item was credited this cycle, or its open line cannot be identified uniquely: never park a guess)."""
    last = None
    for r in rows:
        if str(r.get("repo")) == repo and r["_t"] <= now + 5:
            last = r
    out = {"trip": False, "count": 0, "kinds": {}, "line_no": 0, "key": "", "why": ""}
    if last is None or now - last["_t"] > fresh_s:
        out["why"] = "no-fresh-row"
        return out
    key = row_key(last)
    if not key:
        out["why"] = "row-has-no-item"
        return out
    res = count_picks(rows, repo, key, last["_t"], n, hours, kinds)
    # only a cycle whose OWN result is a bad pick can trip (a landing/other result of an item that already has bad picks parks nothing)
    out.update({"trip": bool(res["trip"] and kind_of(last) in kinds), "count": res["count"], "kinds": res["kinds"], "key": key})
    if not out["trip"]:
        return out
    cand = []
    try:
        with open(prog_path, errors="replace") as f:
            for i, ln in enumerate(f, 1):
                if not ln.startswith("- [ ] ") or PARKED.search(ln):
                    continue
                b = _body(ln)
                if row_line(last) and _md5(b) == row_line(last):
                    cand = [i]
                    break
                if not row_line(last) and _item_hash(b) == key:
                    cand.append(i)
    except OSError:
        pass
    out["line_no"] = cand[0] if len(cand) == 1 else 0
    if not out["line_no"]:
        out["why"] = "no-unique-open-line" if cand else "no-open-line"
    return out


def replay(rows, n=4, hours=24, kinds=BAD_KINDS):
    """walk the corpus once. Returns (events, summary). An event is the FIRST row of an item at which the cap would trip; every later row of the same item (same repo+key) before it is
    credited is a cycle the cap would have saved; a later credited landing marks the cap as a FALSE capping (the item landed after >= n bad tries)."""
    state = {}
    events = []
    for r in rows:
        key = row_key(r)
        if not key:
            continue
        sk = (str(r.get("repo")), key)
        st = state.setdefault(sk, {"bad": [], "capped": None})
        if str(r.get("class")) in CREDITED:
            if st["capped"] is not None and st["capped"].get("landed") is None:
                st["capped"]["landed"] = r
                st["capped"]["landed_same_line"] = (row_line(r) == row_line(st["capped"]["trip_row"]))
            st["bad"] = [b for b in st["bad"] if b[3] != row_line(r)]
            continue
        k = kind_of(r)
        if k not in kinds:
            k = ""
        lo = r["_t"] - hours * 3600
        if st["capped"] is not None:
            if st["capped"].get("landed") is not None:
                continue                          # after the item landed the replay stops attributing savings
            st["capped"]["saved"].append(r)       # the item would have been parked: this pick would not have happened
            continue
        if k:
            st["bad"] = [b for b in st["bad"] if b[0] > lo] + [(r["_t"], k, r, row_line(r))]
            if len(st["bad"]) >= n:
                ev = {"repo": sk[0], "key": key, "trip_row": r, "kinds": [b[1] for b in st["bad"]], "saved": [], "landed": None}
                st["capped"] = ev
                events.append(ev)
    saved = [x for ev in events for x in ev["saved"]]
    summ = {"capped_items": len(events), "saved_cycles": len(saved), "saved_gpu_min": round(sum(float(x.get("duration_s") or 0) for x in saved) / 60.0, 1),
            "capped_then_landed": sum(1 for ev in events if ev["landed"] is not None),
            "capped_then_landed_same_line": sum(1 for ev in events if ev["landed"] is not None and ev.get("landed_same_line")), "rows": len(rows)}
    return events, summ


def main(argv):
    a = argv[1:]
    if not a:
        print(__doc__)
        return 2

    def opt(name, default=None):
        if name in a:
            i = a.index(name)
            v = a[i + 1] if i + 1 < len(a) else default
            del a[i:i + 2]
            return v
        return default
    cmd = a.pop(0)
    outcomes = opt("--outcomes")
    n = int(opt("--n", "4") or 4)
    hours = float(opt("--hours", "24") or 24)
    kinds = tuple(x for x in (opt("--kinds", ",".join(BAD_KINDS)) or "").split(",") if x in BAD_KINDS) or BAD_KINDS
    rows = load(outcomes) if outcomes else []
    if cmd == "check":
        now = int(opt("--now", str(int(time.time()))))
        repo, key = opt("--repo", ""), opt("--key", "")
        print(json.dumps(count_picks(rows, repo, key, now, n, hours, kinds) if key else {"trip": False, "count": 0, "n": n, "kinds": {}, "gpu_s": 0}))
        return 0
    if cmd == "cycle":      # guard hook: prints 'TRIP<TAB>count<TAB>kinds<TAB>line_no<TAB>key<TAB>why'
        now = int(opt("--now", str(int(time.time()))))
        r = cycle(rows, opt("--repo", ""), opt("--prog", ""), now, n, hours, kinds)
        print("\t".join([str(int(r["trip"])), str(r["count"]), ",".join("%sx%s" % (v, k) for k, v in sorted(r["kinds"].items())), str(r["line_no"]), r["key"], r["why"] or "-"]))
        return 0
    if cmd == "replay":
        since, until = opt("--since"), opt("--until")
        if since:
            rows = [r for r in rows if r["_t"] >= parse_ts(since)]
        if until:
            rows = [r for r in rows if r["_t"] <= parse_ts(until)]
        events, summ = replay(rows, n, hours, kinds)
        print(json.dumps(summ))
        for ev in events:
            tr = ev["trip_row"]
            print("CAP", ev["repo"], ev["key"][:8], tr["ts"], ",".join(ev["kinds"]), "saved=%d" % len(ev["saved"]),
                  "LANDED-AFTER=%s%s" % (ev["landed"]["ts"] if ev["landed"] else "no", "(same-line)" if ev["landed"] and ev.get("landed_same_line") else ""), sep=" | ")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
