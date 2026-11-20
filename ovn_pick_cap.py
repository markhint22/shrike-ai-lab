#!/usr/bin/env python3
"""scripts/overnight-queue/ovn_pick_cap.py - per-item PICK CAP (package q-already-done-credit, 2026-11-13). ENFORCE by default (2026-11-17) for the kinds already-done + landed-uncredited only.

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
  ovn_pick_cap.py skipped --skiplist F --repo R --key K   -> 1/0: item is on the short-lived skip list (cap-noop closed/parked)
  ovn_pick_cap.py replay --outcomes F [--n 4] [--hours 24] [--kinds a,b] [--since ISO] [--until ISO]    -> read-only corpus replay: capped items, cycles / GPU minutes saved, later-landed (false capping) list
"""
import hashlib
import json
import os
import re
import sys
import time
from calendar import timegm

BAD_KINDS = ("already-done", "landed-uncredited", "reverted-red", "fixup-undid")
# 2026-11-17: the kinds the CLI / item guard act on by default. The 46.7 h shadow soak on the real box state showed 12 items capped, 0 landed later on the same line, 6 of 6 hand-checked
# caps correct for exactly these two kinds; reverted-red and fixup-undid produced false caps (items that landed afterwards), so they stay OUT unless named in OVN_PICK_CAP_KINDS / --kinds.
DEFAULT_KINDS = ("already-done", "landed-uncredited")
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
# q-wave2 (2026-11-17): tags/comments the harness appends to an item line AFTER record_outcome hashed it (credit-refusal park, no-op cap, recovery supersede). The row's item_line_hash is the hash of
# the line AS PICKED, so the guard (which runs after those parks in the same cycle) must also match the line with them removed.
TAG_START_RE = re.compile(r"\[(?:AUTO-SKIP|BLOCKED|HUMAN-ONLY|CLAUDE|unworkable|recovery)")
CMT_RE = re.compile(r"\s*<!--.*?-->\s*")
SKIP_TTL_S = 6 * 3600


def _md5(t):
    return hashlib.md5(t.encode("utf-8", "replace")).hexdigest()


def strip_tags(body, greedy=False):
    """remove every park tag `[AUTO-SKIP ...]` etc. with a BALANCED-bracket scan from the tag start, so a reason holding `]` (a pytest id `test_a[p1]`, nested `[x]`) is removed whole. An unbalanced
    tag (a reason with a lone `[`) is removed up to the last `]` of the line before any `<!--` comment, else left alone. greedy=True always removes up to that last `]` (a second candidate form)."""
    out, pos = [], 0
    while True:
        m = TAG_START_RE.search(body, pos)
        if not m:
            out.append(body[pos:])
            break
        out.append(body[pos:m.start()])
        end = -1
        if greedy:
            cmt = body.find("<!--", m.start())
            end = body.rfind("]", m.start(), cmt if cmt >= 0 else len(body))
        else:
            depth = 0
            for i in range(m.start(), len(body)):
                c = body[i]
                if c == "[":
                    depth += 1
                elif c == "]":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            if end < 0:
                cmt = body.find("<!--", m.start())
                end = body.rfind("]", m.start(), cmt if cmt >= 0 else len(body))
        if end < 0:
            out.append(body[m.start():m.start() + 1])    # no closing bracket at all: keep the text, move on
            pos = m.start() + 1
            continue
        pos = end + 1
        while pos < len(body) and body[pos] in " \t":
            pos += 1
    return "".join(out)


def _body(line):
    return re.sub(r"^- \[[ xX]\] ", "", line.rstrip("\n"))


def _norm_forms(body):
    """every text the line could have had when it was hashed: as is, minus park tags (balanced and greedy strip), minus trailing comments, minus both."""
    forms = [body]
    nc = CMT_RE.sub("", body).rstrip()
    for nt in (strip_tags(body), strip_tags(body, True), strip_tags(CMT_RE.sub(" ", body)), strip_tags(CMT_RE.sub(" ", body), True)):
        for f in (nt, nt.rstrip(), CMT_RE.sub("", nt).rstrip()):
            if f not in forms:
                forms.append(f)
    if nc not in forms:
        forms.append(nc)
    return forms


def _item_hash(body):
    """== lib_item_select.sh ovn_item_hash: feat-tag identity with the date stamp stripped, else the md5 of the text."""
    f = re.search(r"\[feat:[^\]]+\]", body)
    if f:
        ft = re.sub(r"-\d{6}-", "-", re.sub(r"-\d{8}-", "-", f.group(0)))
        return _md5(ft)
    return _md5(body)


def classify_line(lines, last, key):
    """find the progress line the cycle's row refers to. lines = the progress file lines. Returns (line_no, why):
      line_no > 0  an OPEN, unparked line to park; why says which step of the chain found it (line-hash | feat-unique | feat-oldest)
      line_no == 0 nothing to park; why is one of noop-closed (the item's line is ticked: nothing left to park), noop-parked (the line already carries a park tag: another guard parked it in
                   this very cycle), no-open-line (no line of this item exists at all), no-unique-open-line (several candidates and no staged-step feat tag to order them by)
    Fallback chain: line hash (tag/comment-stripped forms) -> unique open feat-tag match -> OLDEST open staged-step line of that feat tag.
    NEVER GUESS: a line that WAS found but is closed/parked never falls through to a sibling; and when the row carries a line hash and ANY line of the item's feat class is parked or closed, the
    feat fallbacks are not used at all (the item's own line is most likely that parked/closed line whose text we failed to re-derive: parking an open sibling would park good work).
    The feat fallbacks only run for a row without a line hash, or when every line of the feat class is open and unparked."""
    lh = row_line(last)
    items = []   # (no, open, parked, body)
    for i, ln in enumerate(lines, 1):
        if not ln.startswith("- ["):
            continue
        items.append((i, ln.startswith("- [ ] "), bool(PARKED.search(ln)), _body(ln)))
    if lh:
        hits = [(i, op, pk) for i, op, pk, b in items if any(_md5(f) == lh for f in _norm_forms(b))]
        live = [i for i, op, pk in hits if op and not pk]
        if live:
            return live[0], "line-hash"
        if hits:
            return 0, "noop-parked" if any(op for _i, op, _pk in hits) else "noop-closed"
    feat = [(i, op, pk, b) for i, op, pk, b in items if any(_item_hash(f) == key for f in _norm_forms(b))]
    live_feat = [i for i, op, pk, b in feat if op and not pk]
    if lh and len(live_feat) != len(feat):
        return 0, "noop-parked" if any(op and pk for _i, op, pk, _b in feat) else "noop-closed"
    if len(live_feat) == 1:
        return live_feat[0], "feat-unique"
    if len(live_feat) > 1:
        if all(re.search(r"\[feat:", b) for i, op, pk, b in feat if i in live_feat):
            return live_feat[0], "feat-oldest"    # the staged steps of one feature are written in build order: the oldest open one is the one the loop keeps landing on
        return 0, "no-unique-open-line"
    if feat:
        return 0, "noop-parked" if any(op for _i, op, _pk, _b in feat) else "noop-closed"
    return 0, "no-open-line"


def _skip_load(path, now):
    out = {}
    try:
        with open(path, errors="replace") as f:
            for ln in f:
                p = ln.rstrip("\n").split("\t")
                if len(p) >= 4 and p[3].isdigit() and int(p[3]) > now:
                    out[(p[0], p[1], p[2])] = int(p[3])
    except OSError:
        pass
    return out


def skip_check(path, repo, key, now):
    """1 when (repo, key) is on the short-lived skip list (any line of the item), else 0."""
    return int(any(k[0] == repo and k[1] == key for k in _skip_load(path, now)))


def _skip_add(path, repo, key, line, now, ttl=SKIP_TTL_S):
    cur = _skip_load(path, now)
    new = (repo, key, line) not in cur
    cur[(repo, key, line)] = now + ttl
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "w") as f:
            for (r, k, l), e in sorted(cur.items()):
                f.write("%s\t%s\t%s\t%d\n" % (r, k, l, e))
        os.replace(tmp, path)
    except OSError:
        # the skip list cannot be written (read-only state dir, disk full): report "seen" (False) so the noop verdict is not re-logged every cycle; the guard simply gets no skip entry
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False
    return new


def cycle(rows, repo, prog_path, now, n=4, hours=24, kinds=BAD_KINDS, fresh_s=900, skip_path=""):
    """what the item guard asks right after record_outcome wrote this cycle's row: does the item the cycle just worked trip the cap, and which OPEN progress line is it?
    line_no 0 = nothing to park (see classify_line). A noop-closed / noop-parked verdict is reported ONCE per item line per SKIP_TTL_S (why=noop-closed|noop-parked), afterwards as
    why=noop-closed-seen|noop-parked-seen, and the item is put on the short-lived skip list when skip_path is given."""
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
    try:
        with open(prog_path, errors="replace") as f:
            lines = f.read().split("\n")
    except OSError:
        lines = []
    out["line_no"], out["why"] = classify_line(lines, last, key)
    if out["why"] in ("noop-closed", "noop-parked") and skip_path:
        if not _skip_add(skip_path, repo, key, row_line(last) or "-", now):
            out["why"] += "-seen"
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
    kinds = tuple(x for x in (opt("--kinds", ",".join(DEFAULT_KINDS)) or "").split(",") if x in BAD_KINDS) or DEFAULT_KINDS   # unknown/empty -> the safe default, never "all four"
    rows = load(outcomes) if outcomes else []
    if cmd == "check":
        now = int(opt("--now", str(int(time.time()))))
        repo, key = opt("--repo", ""), opt("--key", "")
        print(json.dumps(count_picks(rows, repo, key, now, n, hours, kinds) if key else {"trip": False, "count": 0, "n": n, "kinds": {}, "gpu_s": 0}))
        return 0
    if cmd == "cycle":      # guard hook: prints 'TRIP<TAB>count<TAB>kinds<TAB>line_no<TAB>key<TAB>why'
        now = int(opt("--now", str(int(time.time()))))
        r = cycle(rows, opt("--repo", ""), opt("--prog", ""), now, n, hours, kinds, skip_path=opt("--skiplist", "") or "")
        print("\t".join([str(int(r["trip"])), str(r["count"]), ",".join("%sx%s" % (v, k) for k, v in sorted(r["kinds"].items())), str(r["line_no"]), r["key"], r["why"] or "-"]))
        return 0
    if cmd == "skipped":    # picker hook: 1 when the item is on the short-lived skip list
        print(skip_check(opt("--skiplist", ""), opt("--repo", ""), opt("--key", ""), int(opt("--now", str(int(time.time()))))))
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
