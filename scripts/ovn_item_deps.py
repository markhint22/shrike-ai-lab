#!/usr/bin/env python3
"""ovn_item_deps.py - behaviour-dependency selection + production-before-test ordering for queue items (package Y4, 2026-11-05).

THE DEFECT (fleet outcomes 2026-11-03..04): test-only items ran BEFORE the production item they assert. iptv "wipe-the-shared" burned 111 min: two T3 test items assert 403 for a
missing/wrong X-Admin-Secret while the item that adds `Depends(require_admin_secret)` to `clear_cache` was open (then parked): the model edited production from a test item (61 of 88
stage scope-violations in the last 400 stage runs are exactly "declared a test file, touched a source file"), the full verify went red, the item ended stage-unverified.
ovn_stage_order.py already orders by shared identifiers; it misses (a) a test item whose NAME embeds the production symbol (test_clear_cache_unauthorized vs `clear_cache`) and a same-tier
test item whose file stem is the production file's stem, (b) a VERIFY / declared file that only an open sibling creates.

RULES (cheap, static; all inside ONE [feat:<id>] group; a prerequisite counts while it is an OPEN queue line, parked ones included):
  name_contains   test-only B names a test/ident token that CONTAINS an identifier (>= 6 chars, snake/Camel/backticked) the open non-test sibling A names
  stem_overlap    test-only B whose test file basename carries A's source-file stem (>= 4 chars) AND whose text shares a distinctive word (>= 5 chars) with A, A not a later tier
  new_file        B's declared file or VERIFY path is a file an open sibling A is told to CREATE ("Create/Add a new ... <path>" or A's own declared file with a create verb)
  verify_creates  B's VERIFY runs a test id (file::test_x / test_x) that an open sibling A is told to add
  verify_missing  (needs --tree) B's VERIFY names a path that does not exist in the working tree and an open sibling mentions that path
Everything ovn_stage_order.build_edges already finds (symbol / verify_file / explicit / tier_stem) is NOT repeated here: that module keeps its own OVN_STAGE_ORDER mode.

MODE OVN_ITEM_DEPS = off | shadow | enforce (default shadow).
  item-filter  stdin = candidate queue lines. shadow: output == input, would-defer rows go to state/item_deps_shadow.log (JSON lines, identical decision merged within
               OVN_ITEM_DEPS_MERGE_WINDOW_S, count+1). enforce: a blocked line is dropped; a line whose open prerequisites are ALL parked is held unless OVN_ITEM_DEPS_PARKED=release.
  order        stdin = freshly decomposed item lines -> the same lines, each production item before the test item that depends on it (stable topological order; the planner calls it).
Fail-safe: any internal error prints the input unchanged and exits 0.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ovn_stage_order as so  # noqa: E402

WORD_RE = re.compile(r"[A-Za-z]{5,}")
CREATE_NEW = re.compile(r"\b(create|creates|add a new|adds a new|new (?:test )?file|write a new)\b", re.I)
GENERIC = set("""
admin secret header headers request response status client server value values should return returns returned existing remove removed update updated function
endpoint endpoints module class method methods parameter parameters pytest assert import imports fixture fixtures monkeypatch cache backend frontend
""".split())


def _mode(m=None):
    v = (m or os.environ.get("OVN_ITEM_DEPS", "shadow") or "shadow").strip().lower()
    return v if v in ("off", "shadow", "enforce") else "shadow"


def _src_idents(n):
    """Identifiers a non-test item names (backticked or snake/Camel in the description, not test_ names)."""
    return [t for t in so.idents(n["desc"]) if len(t) >= 6 and not t.startswith("test_")]


def _words(text):
    return {w.lower() for w in WORD_RE.findall(so.strip_paths(text)) if w.lower() not in so.STOP and w.lower() not in GENERIC}


def _base(p):
    return os.path.basename(p)


def _same_path(a, b):
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


def _creates_path(a):
    """Paths a is told to create: its declared files when the text has a create verb, plus any path it names right after one."""
    d = a["desc"]
    out = []
    if CREATE_NEW.search(d):
        out.extend(so.files_of(a))
        for m in CREATE_NEW.finditer(d):
            out.extend(so.PATH_RE.findall(d[m.end(): m.end() + 120]))
    return list(dict.fromkeys(out))


def _verify_test_ids(verify):
    """Test ids a VERIFY runs: pytest file::...::test_x and -k test_x (a bare path like tests/test_foo.py is NOT an id)."""
    return list(dict.fromkeys(re.findall(r"::(test_[A-Za-z0-9_]+)", verify) + re.findall(r"-k\s+['\"]?(test_[A-Za-z0-9_]+)", verify)))


def _tests_added(a):
    d = so.strip_paths(a["desc"])
    out = []
    for m in so.CREATE_VERBS.finditer(d):
        out.extend(re.findall(r"\b(test_[A-Za-z0-9_]+)", d[m.end(): m.end() + 160]))
    return list(dict.fromkeys(out))


def dep_edges(nodes, tree=""):
    """-> list of (b_id, a_id, kind): node b needs open node a. nodes come from ovn_stage_order._item_nodes (needs it/tier/test_only)."""
    edges = []
    for b in nodes:
        if b["it"]["done"] or b["removal"]:
            continue
        bwords = None
        for a in nodes:
            if a is b or a["it"]["done"] or a["removal"]:
                continue
            kind = ""
            # --- test-only B waiting on a production A
            if b["test_only"] and not a["test_only"]:
                a_ids = _src_idents(a)
                b_toks = so.IDENT_RE.findall(so.strip_paths(b["desc"])) + so.IDENT_RE.findall(b["verify"])
                for ai in a_ids:
                    if any(ai.lower() in t.lower() and t.lower() != ai.lower() for t in b_toks if t.startswith("test_")) or ai in b["mentions"]:
                        kind = "name_contains"
                        break
                if not kind and a.get("tier", 0) <= b.get("tier", 0):
                    stems = [os.path.splitext(_base(f))[0] for f in so.files_of(a)]
                    bn = " ".join(_base(f) for f in so.files_of(b))
                    if any(len(st) >= 4 and st in bn for st in stems):
                        if bwords is None:
                            bwords = _words(b["desc"])
                        if bwords & _words(a["desc"]):
                            kind = "stem_overlap"
            # --- any B waiting on an A that creates a file / test id B uses
            if not kind:
                bpaths = set(so.files_of(b)) | set(b["verify_paths"])
                for cp in _creates_path(a):
                    if any(_same_path(cp, bp) for bp in bpaths) and not any(_same_path(cp, f) for f in so.files_of(b) if CREATE_NEW.search(b["desc"])):
                        kind = "new_file"
                        break
            if not kind:
                vt = _verify_test_ids(b["verify"])
                if vt and set(vt) & set(_tests_added(a)) and not (set(vt) & set(_tests_added(b))):
                    kind = "verify_creates"
            if not kind and tree:
                for vp in b["verify_paths"]:
                    if "/" in vp and not os.path.exists(os.path.join(tree, vp)) and any(_same_path(vp, p) for p in so.PATH_RE.findall(a["desc"]) + so.files_of(a)) \
                            and not any(_same_path(vp, f) for f in so.files_of(b)):
                        kind = "verify_missing"
                        break
            if kind:
                edges.append((b["id"], a["id"], kind))
    return edges


def _prod_wins(edges, nodes):
    """2026-11-06 (Y4 review fix 1): when a test-only item B has a behaviour edge (name_contains/stem_overlap) to production item A, any opposite edge (A needs B: new_file /
    verify_creates / verify_missing, e.g. A's VERIFY names a test id B adds) is dropped, so production-before-test wins and _acyclic never has to pick (it dropped ours)."""
    by_id = {n["id"]: n for n in nodes}
    beh = {(b, a) for b, a, k in edges if k in ("name_contains", "stem_overlap") and by_id[b]["test_only"] and not by_id[a]["test_only"]}
    return [e for e in edges if not ((e[1], e[0]) in beh and e[2] not in ("name_contains", "stem_overlap"))]


def _acyclic(edges):
    """Drop edges that close a cycle (reuse the stage-order cycle breaker; our kinds are weak there)."""
    as_weak = [(b, a, "verify_ref") for b, a, _ in edges]
    kept, _ = so.drop_cycles(as_weak)
    keep = {(b, a) for b, a, _ in kept}
    return [e for e in edges if (e[0], e[1]) in keep]


def decisions(candidates, progress_text, tree=""):
    items = so.parse_progress(progress_text)
    groups = {}
    for it in items:
        if it["feat"]:
            groups.setdefault(it["feat"], []).append(it)
    gn, ge = {}, {}
    for g, grp in groups.items():
        if len(grp) < 2 or len(grp) > so._max_group():
            continue
        nodes = so._item_nodes(grp)
        gn[g] = nodes
        ge[g] = _acyclic(_prod_wins(dep_edges(nodes, tree), nodes))
    res = []
    for c in candidates:
        key = c.strip()
        hit = None
        for g, nodes in gn.items():
            for n in nodes:
                if not n["it"]["done"] and key and n["it"]["text"].strip() == key:
                    hit = (g, n)
                    break
            if hit:
                break
        if not hit:
            res.append({"text": c, "blocked": False, "waiting_on": []})
            continue
        g, n = hit
        byid = {x["id"]: x for x in gn[g]}
        wait = []
        for b, a, k in ge[g]:
            if b == n["id"] and not byid[a]["it"]["done"]:
                an = byid[a]
                wait.append({"line": a + 1, "kind": k, "state": "parked" if an["it"]["parked"] else "open", "tier_text": an["it"]["text"][:110],
                             "item_hash": so.item_hash(an["it"]["text"])})
        res.append({"text": c, "blocked": bool(wait), "waiting_on": wait, "feat": g, "item_hash": so.item_hash(n["it"]["text"]),
                    "stuck_parked": bool(wait) and all(w["state"] == "parked" for w in wait)})
    return res


# ------------------------------------------------------------------------------------------------------------- journal
def _journal(path, rec, merge_s=None):
    """Append a JSON row; an identical decision inside the merge window bumps count/last_ts instead of adding a row. flock on <path>.lock. Never raises."""
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        rec = dict(rec)
        rec.setdefault("ts", now)
        rec["decision_id"] = hashlib.sha1(json.dumps([rec.get("repo"), rec.get("event"), rec.get("item_hash"), so.md5(rec.get("item", "")), [w.get("item_hash") for w in rec.get("waiting_on", [])]],
                                                     sort_keys=True).encode()).hexdigest()[:20]
        win = float(os.environ.get("OVN_ITEM_DEPS_MERGE_WINDOW_S", "21600") or 21600)
        if merge_s:
            win = float(merge_s)
            rec["decision_id"] = hashlib.sha1((rec["decision_id"] + str(rec.get("day", ""))).encode()).hexdigest()[:20]
        lk = open(path + ".lock", "a")
        try:
            import fcntl
            fcntl.flock(lk, fcntl.LOCK_EX)
        except Exception:  # noqa: BLE001
            pass
        rows = []
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                for ln in fh:
                    try:
                        rows.append(json.loads(ln))
                    except ValueError:
                        pass
        merged = False
        for r in reversed(rows[-400:]):
            if r.get("decision_id") == rec["decision_id"]:
                t0 = so._epoch(r.get("last_ts") or r.get("ts"))
                if t0 is not None and time.time() - t0 <= win:
                    r["count"] = int(r.get("count", 1)) + 1
                    r["last_ts"] = now
                    merged = True
                break
        if not merged:
            rec["count"] = 1
            rec["last_ts"] = now
            rows.append(rec)
        cap = int(os.environ.get("OVN_ITEM_DEPS_LOG_ROWS", "2000") or 2000)
        rows = rows[-cap:]
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, sort_keys=True) + "\n")
        os.replace(tmp, path)
        lk.close()
    except Exception as ex:  # noqa: BLE001
        sys.stderr.write("ovn_item_deps journal: %s: %s\n" % (type(ex).__name__, ex))


def cmd_item_filter(a):
    lines = sys.stdin.read().split("\n")
    mode = _mode(a.mode)
    cand = [ln for ln in lines if ln.strip()]
    try:
        if mode == "off" or not os.path.exists(a.progress):
            sys.stdout.write("\n".join(lines))
            return 0
        with open(a.progress, encoding="utf-8", errors="replace") as fh:
            ptxt = fh.read()
        decs = decisions([re.sub(r"^- \[ \] ", "", ln) for ln in cand], ptxt, a.tree)
    except Exception as ex:  # noqa: BLE001
        sys.stderr.write("ovn_item_deps item-filter: %s: %s\n" % (type(ex).__name__, ex))
        sys.stdout.write("\n".join(lines))
        return 0
    parked_mode = (os.environ.get("OVN_ITEM_DEPS_PARKED", "hold") or "hold").strip().lower()
    keep = []
    for ln, d in zip(cand, decs):
        if d["blocked"] and d.get("stuck_parked") and a.log and mode == "enforce" and parked_mode != "release":
            # 2026-11-06 (Y4 review fix 2): same escalation signal as ovn_stage_order (event stuck_on_parked_prereq): every open prerequisite is parked, only a human can unpark
            # it, so the held test item would starve silently. ONE alert event per item per UTC day (dedupe key carries the date; identical rows inside that day merge).
            _journal(a.log, {"event": "stuck_on_parked_prereq", "mode": mode, "parked_mode": parked_mode, "repo": a.repo, "feat": d.get("feat"), "item": d["text"][:160],
                             "item_hash": d["item_hash"], "waiting_on": d["waiting_on"], "stuck_parked": True, "day": time.strftime("%Y-%m-%d", time.gmtime())},
                     merge_s=86400)
        if d["blocked"]:
            release = mode == "enforce" and d.get("stuck_parked") and parked_mode == "release"
            if a.log:
                _journal(a.log, {"event": "would_defer_item" if mode != "enforce" else ("released_parked" if release else "deferred_item"), "mode": mode, "repo": a.repo,
                                 "feat": d.get("feat"), "item": d["text"][:160], "item_hash": d["item_hash"], "waiting_on": d["waiting_on"], "stuck_parked": d["stuck_parked"]})
            if mode == "enforce" and not release:
                continue
        keep.append(ln)
    sys.stdout.write("\n".join(keep) + ("\n" if keep else ""))
    return 0


def order_items(lines):
    """Reorder item lines (a fresh decomposition) so every production item precedes the open test item that depends on it. Stable; non-item lines keep their slot."""
    idx = [i for i, ln in enumerate(lines) if re.match(r"^- \[[ xX]\] ", ln)]
    if len(idx) < 2:
        return list(lines)
    synth = [{"line": k, "done": False, "parked": False, "feat": "", "text": re.sub(r"^- \[[ xX]\] ", "", lines[i]), "files": [], "cat": ""} for k, i in enumerate(idx)]
    for it in synth:
        lead = re.search(r"\[T\d\]\s*([\w./-]+\.\w+)\s+[—-]+\s+", it["text"])
        it["files"] = [lead.group(1)] if lead else []
        c = so.CAT_RE.search(it["text"])
        it["cat"] = c.group(1) if c else ""
    nodes = so._item_nodes(synth)
    edges = list(dep_edges(nodes))
    # 2026-11-06 (Y4 review fix 1): a production item whose VERIFY merely RUNS the sibling test file (`pytest app/tests/test_users.py`) gets a verify_file/verify_ref
    # edge "production needs test item" from stage_order. That is the INVERSE of the behaviour dependency (a test item asserts what the production item creates), and
    # _acyclic then dropped Y4's own edge (all weak), so the planner order was a no-op or even test-first. Running a test file does not make production depend on the
    # test ITEM: drop verify_* edges from a non-test item to a test-only item before merging.
    by_id = {n["id"]: n for n in nodes}
    for b, a, k in so.build_edges(nodes)[0]:
        if k not in ("symbol", "tier_stem", "verify_ref", "verify_file"):
            continue
        if k in ("verify_ref", "verify_file") and by_id[a]["test_only"] and not by_id[b]["test_only"]:
            continue
        edges.append((b, a, k))
    edges = _acyclic(_prod_wins(edges, nodes))
    order = so.topo(nodes, edges)
    out = list(lines)
    for slot, nid in zip(idx, order):
        out[slot] = lines[idx[nid]]
    return out


def cmd_order(a):
    text = sys.stdin.read()
    trailing = text.endswith("\n")
    lines = text.split("\n")
    if trailing:
        lines = lines[:-1]
    try:
        if (os.environ.get("OVN_PLANNER_ITEM_ORDER", "on") or "on").lower() == "off":
            raise RuntimeError("off")
        out = order_items(lines)
        moved = sum(1 for x, y in zip(lines, out) if x != y)
        if moved and a.log:
            sys.stderr.write("item-order: reordered %d of %d item(s) so production precedes its test\n" % (moved, len(lines)))
    except Exception as ex:  # noqa: BLE001
        if str(ex) != "off":
            sys.stderr.write("ovn_item_deps order: %s: %s\n" % (type(ex).__name__, ex))
        out = lines
    sys.stdout.write("\n".join(out) + ("\n" if trailing else ""))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("item-filter")
    f.add_argument("--progress", required=True)
    f.add_argument("--mode", default="")
    f.add_argument("--repo", default="")
    f.add_argument("--log", default="")
    f.add_argument("--tree", default="")
    o = sub.add_parser("order")
    o.add_argument("--log", default="1")
    a = ap.parse_args(argv)
    return {"item-filter": cmd_item_filter, "order": cmd_order}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
