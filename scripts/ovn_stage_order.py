#!/usr/bin/env python3
"""ovn_stage_order.py - dependency-aware ordering for staged work (package D3-step-ordering, 2026-10-18).

THE DEFECT. The decomposer emits steps in the order the model thought of them, and the queue holds a feature group's items ([feat:<id>] tag) in the order
the research pass wrote them; the picker takes the first doable T3+ line. Nothing knows that a TEST step/item needs the SOURCE step/item it exercises:
the correct red test then fails the full verify, the item ends stage-unverified, and the runner escalates or lowers the bar until something vacuous lands
(test-automation-agent get_live_role single-org tests credited without the fix; xlite MissionData.is_valid wired to patrol_routes_ok before the T1 item that
defines it).

THE MODEL. A node is a step (a plan entry {desc, files, verify[, depends_on, red_before]}) or a queue item (one OVERNIGHT_PROGRESS.md line). Edges "B needs A":
  explicit     B.depends_on lists A (decomposer output)
  symbol       B's text names a specific identifier (snake_case / CamelCase / backticked) that A creates or modifies; for a TEST-only B this means "B is red until A lands"
  verify_file  B's VERIFY names a file A creates/edits   (weakest: dropped first when it would close a cycle)
  verify_ref   B's VERIFY names an identifier only A creates (weak, same)
Removal semantics reverse the symbol edge: an item that REMOVES a symbol runs after anything that still uses it (and after the tests that cover it), but a
NEGATIVE test ("does not expose", "no longer") runs after the removal.

THREE ACTIONS (mode OVN_STAGE_ORDER = off | shadow | enforce, default shadow):
  plan         steps in -> steps out. A step that runs before its prerequisite is a violation. enforce: a red-by-design TEST-only step lands in the SAME commit as its fix
               step (merged: files union <= OVN_STAGE_ORDER_MERGE_MAX_FILES, default 4, verify = both), otherwise it is reordered after it (stable topological sort).
               shadow: the plan is returned UNCHANGED and the would-have decisions are journaled.
  unmet        runtime gate: which prerequisites of step i are not in the done set. enforce parks the step (and transitively its dependents); shadow only journals.
  item-filter  picker gate over candidate queue lines: a line whose prerequisite items (same [feat:] group) are not done is dropped in enforce (parked until the
               prerequisite lands), journaled only in shadow.
OVN_STAGE_ORDER_PARKED=hold|release (default hold): in enforce, a dependent whose open prerequisites are ALL parked is held (and journaled as stuck_on_parked_prereq); release lets it through.
Everything is fail-safe: any internal error prints the input unchanged and exits 0.
"""
import argparse
import json
import os
import re
import sys

STOP = set("""
add adds added create creates created implement implements update updates modify modifies change changes make makes ensure verify check test tests file files
function functions method methods class classes helper helpers return returns returned should must when with without that this from into onto then than
true false none null self cls args kwargs str int bool float list dict tuple bytes object pytest python python3 grep unittest assert asserts import imports
verifying exists existing existence the and for not its has have are was were can will also each every any all only just same such more than less line lines
signature parameter parameters argument arguments value values type types name names code logic block endpoint endpoints module modules package suite
godot gdparse static func extends bool string array void dict gut test_ cat feat multifile alongside include includes included including check checks
""".split())
CREATE_VERBS = re.compile(r"\b(add|adds|create|creates|implement|implements|introduce|introduces|define|defines|write|writes|extract|extracts|build|builds)\b", re.I)
REMOVE_VERBS = re.compile(r"^\W*(?:\[T\d\]\s*)?(?:[\w./-]+\s+[—-]+\s+)?(?:remove|delete|drop|retire|deprecate|eliminate)\b|\b(?:remove|delete|drop)\b[^.]{0,40}\b(?:function|method|property|class|test cases?|tests?|helper|definition|endpoint)\b", re.I)
NEGATIVE = re.compile(r"\b(?:not|no longer|never|absent|removed|gone|does not|doesn't|cannot|without)\b", re.I)
CLAUSE_END = re.compile(r"\s(?:in|to|into|that|which|from|alongside|so|for|using|with|inside|within|at|by|after|before|verifying|ensuring|asserting|checking|covering|testing|requires|exercising)\s|[.;]\s|$", re.I)
PATH_RE = re.compile(r"[\w][\w./-]*\.(?:py|gd|ts|tsx|js|jsx|vue|kt|swift|sh|md|json|yml|yaml|toml|sql|txt|cfg|ini|tscn|tres|html|css)\b")
TICK_RE = re.compile(r"`([^`]+)`")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{3,}")
TESTPATH_RE = re.compile(r"(?:^|/)(?:tests?|__tests__|spec)/|(?:^|/)test_[^/]*$|_test\.[a-z]+$|\.test\.[a-z]+$|\.spec\.[a-z]+$|(?:^|/)conftest\.py$", re.I)
FEAT_RE = re.compile(r"\[feat:([^\]\s]+)\]")
CAT_RE = re.compile(r"\(cat:([a-z]+)")
PARK_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED|\[CLAUDE\]")
KINDS_WEAK = ("verify_file", "verify_ref", "tier_stem")


def _env_mode(mode=None):
    m = (mode or os.environ.get("OVN_STAGE_ORDER", "shadow") or "shadow").strip().lower()
    return m if m in ("off", "shadow", "enforce") else "shadow"


def split_verify(text):
    """(desc, verify) of an item/step text: everything before / after the first 'VERIFY:' marker."""
    m = re.search(r"\bVERIFY:\s*", text)
    return (text[:m.start()], text[m.end():]) if m else (text, "")


def is_specific(tok, ticked=False):
    if tok.lower() in STOP or tok.lower().startswith(("http", "origin")):
        return False
    if "_" in tok.strip("_"):
        return True
    if re.search(r"[a-z][A-Z]", tok) or re.match(r"[A-Z][a-z]+[A-Z]", tok):
        return True
    return bool(ticked and len(tok) >= 6 and tok.lower() not in STOP and not tok.isupper())


def strip_paths(text):
    return PATH_RE.sub(" ", text)


def idents(text, only_ticked=False):
    """Specific identifiers in text (paths removed first)."""
    out = []
    ticked = set()
    for m in TICK_RE.finditer(text):
        for t in IDENT_RE.findall(strip_paths(m.group(1))):
            ticked.add(t)
    body = strip_paths(text)
    for t in IDENT_RE.findall(body):
        if (not only_ticked or t in ticked) and is_specific(t, t in ticked) and t not in out:
            out.append(t)
    return out


def creates(desc):
    """Identifiers the description introduces: the specific ones in the clause after a create verb."""
    found = []
    for m in CREATE_VERBS.finditer(desc):
        rest = desc[m.end():]
        e = CLAUSE_END.search(rest)
        # a clause that is a backticked signature may contain spaces/'to': take up to the first closing backtick when it opens one
        tk = re.match(r"\s*(?:an?|the|new)?\s*(?:static\s+)?(?:`[^`]+`|[^\s,;]+)", rest)
        clause = rest[: (tk.end() if tk and "`" in tk.group(0) else (e.start() if e else len(rest)))]
        names = [x for x in idents(clause) if x]
        # the declared name is the identifier followed by "(" or after func/def/class/function/method; keep that when present, else the first one
        decl = re.findall(r"(?:def|func|class|function|method|helper|fn)\s+`?([A-Za-z_]\w{2,})", clause)
        if not decl:
            decl = re.findall(r"`?([A-Za-z_]\w{3,})\s*\(", clause)
        pick = [d for d in decl if is_specific(d, True)] or names[:1]
        for p in pick:
            if p not in found:
                found.append(p)
        for t in re.findall(r"\b(test_[A-Za-z0-9_]+)", clause):
            if t not in found:
                found.append(t)
    return found


def files_of(node):
    return [f for f in (node.get("files") or []) if isinstance(f, str)]


def is_test_only(node):
    fs = files_of(node)
    if fs:
        return all(TESTPATH_RE.search(f) for f in fs)
    return node.get("cat") == "test"


def norm_node(raw, idx):
    desc = str(raw.get("desc") or raw.get("text") or "")
    d0, v0 = split_verify(desc)
    verify = str(raw.get("verify") or v0 or "")
    n = {"id": raw.get("id", idx), "desc": d0 if v0 else desc, "verify": verify, "files": raw.get("files") or []}
    n["cat"] = raw.get("cat", "")
    n["explicit"] = [x for x in (raw.get("depends_on") or []) if isinstance(x, (int, str))]
    n["red"] = bool(raw.get("red_before"))
    n["removal"] = bool(REMOVE_VERBS.search(n["desc"]))
    n["test_only"] = is_test_only(n)
    n["creates"] = [c for c in creates(n["desc"]) if c.startswith("test_")] if n["test_only"] else creates(n["desc"])
    n["rm_kind"] = ("ref_after" if re.search(r"\b(?:remaining|leftover|residual|any other|other)\b", n["desc"], re.I) and re.search(r"\breferences?\b", n["desc"], re.I) else
                    "ref" if re.search(r"\b(?:references?|usages?|call ?sites?|calls?|imports?|occurrences?|callers?)\b", n["desc"], re.I) else
                    "test" if n["test_only"] else "def") if n["removal"] else ""
    n["mentions"] = idents(n["desc"])
    n["verify_refs"] = idents(verify)
    n["negative"] = bool(NEGATIVE.search(n["desc"]))
    n["verify_paths"] = [os.path.basename(p) if "/" not in p else p for p in PATH_RE.findall(verify)]
    return n


SCHEMA_PATH_RE = re.compile(r"(?:^|/)(?:models?|schemas?)(?:/|\.py$)|alembic/versions/|(?:^|/)migrations?/")


def _is_schema_node(n):
    return n.get("cat") == "schema" or any(SCHEMA_PATH_RE.search(f) for f in files_of(n))


def build_edges(nodes):
    """-> (edges, notes): edges are (b, a, kind) = node b needs node a. Edges that close a cycle are dropped (weak kinds first) and listed in notes."""
    edges = []
    byid = {n["id"]: n for n in nodes}
    for b in nodes:
        for dep in b["explicit"]:
            a = byid.get(dep) or byid.get(int(dep) if str(dep).isdigit() else dep)
            if a is not None and a is not b:
                edges.append((b["id"], a["id"], "explicit"))
        for a in nodes:
            if a is b:
                continue
            own = set(b["creates"])
            # symbol edges: b's description names something a creates / modifies
            shared_desc = [s for s in b["mentions"] if (s in a["creates"] or s in a["mentions"]) and s not in own]
            if shared_desc:
                if a["removal"]:
                    # removal runs after the consumers/tests of the symbol, except a negative regression test which runs after the removal;
                    # between two removals the DEFINITION goes last (after reference/test removal), never the other way round
                    if b["removal"]:
                        if a["rm_kind"] == "def" and b["rm_kind"] in ("ref", "test"):
                            edges.append((a["id"], b["id"], "symbol"))
                    elif b["negative"] and b["test_only"]:
                        edges.append((b["id"], a["id"], "symbol"))
                    else:
                        edges.append((a["id"], b["id"], "symbol"))
                elif b["removal"]:
                    pass
                elif b["test_only"] and a["test_only"]:
                    if any(s in a["creates"] for s in shared_desc):
                        edges.append((b["id"], a["id"], "symbol"))
                elif b["test_only"] or any(s in a["creates"] for s in shared_desc):
                    edges.append((b["id"], a["id"], "symbol"))
            else:
                shared_ver = [s for s in b["verify_refs"] if s in a["creates"] and s not in own]
                if shared_ver and not a["removal"] and not b["removal"]:
                    edges.append((b["id"], a["id"], "verify_ref"))
            # tier_stem (queue items only): a test-only item waits for lower-tier source items of its group whose module stem its test file name carries
            # (test_usage_role_check.py <- routers/usage.py): the group's tier ladder is the research pass's own build order
            if b.get("tier") and a.get("tier") and b["test_only"] and not a["test_only"] and a["tier"] < b["tier"] and not a["removal"]:
                stems = [os.path.splitext(os.path.basename(f))[0] for f in files_of(a)]
                bn = " ".join(os.path.basename(f) for f in files_of(b))
                if any(len(st) >= 4 and st in bn for st in stems):
                    edges.append((b["id"], a["id"], "tier_stem"))
            # tier_stem for SCHEMA prerequisites (2026-10-20, iptv search_history.profile_id): a non-test item of the group (the endpoint/router that uses the new
            # column) waits for the lower-tier model/migration item whose module stem it shares (models/search.py <- routers/search.py). The 27B ran the T3/T4 endpoint
            # items 8x while the T2 model item was still open: their VERIFY cannot pass without the column -> 8 stage-unverified cycles (~2.5h of GPU). OVN_STAGE_ORDER_SCHEMA_TIER=off disables.
            if (os.environ.get("OVN_STAGE_ORDER_SCHEMA_TIER", "on") != "off" and b.get("tier") and a.get("tier") and a["tier"] < b["tier"]
                    and not b["test_only"] and not a["test_only"] and not a["removal"] and not b["removal"] and _is_schema_node(a) and not _is_schema_node(b)):
                stems = [os.path.splitext(os.path.basename(f))[0] for f in files_of(a)]
                bn = " ".join(os.path.basename(f) for f in files_of(b))
                if any(len(st) >= 4 and st in bn for st in stems):
                    edges.append((b["id"], a["id"], "tier_stem"))
            # verify_file: b's VERIFY runs/greps a file that a creates or edits (a's declared files), b itself does not declare it
            bf = set(files_of(b))
            for vp in b["verify_paths"]:
                for af in files_of(a):
                    if (af == vp or af.endswith("/" + vp) or vp.endswith("/" + af)) and af not in bf and not a["removal"]:
                        edges.append((b["id"], a["id"], "verify_file"))
                        break
    seen, uniq = set(), []
    for e in edges:
        if (e[0], e[1]) not in seen:
            seen.add((e[0], e[1]))
            uniq.append(e)
    return drop_cycles(uniq)   # -> (edges, notes)


def _reach(edges, src, dst):
    adj = {}
    for b, a, _ in edges:
        adj.setdefault(b, []).append(a)
    seen, stack = set(), [src]
    while stack:
        x = stack.pop()
        if x == dst:
            return True
        if x in seen:
            continue
        seen.add(x)
        stack.extend(adj.get(x, []))
    return False


def drop_cycles(edges):
    """Remove edges that close a cycle: weak kinds first (verify_file, verify_ref), then symbol, never explicit. The result is acyclic or explicit-only cyclic."""
    notes = []
    kept = list(edges)
    for kind_set in (("merged",), KINDS_WEAK, ("symbol",)):
        changed = True
        while changed:
            changed = False
            for e in list(kept):
                if e[2] in kind_set:
                    rest = [x for x in kept if x is not e]
                    if _reach(rest, e[1], e[0]):
                        kept = rest
                        notes.append({"dropped": [e[0], e[1], e[2]], "why": "cycle"})
                        changed = True
                        break
    return kept, notes


def topo(nodes, edges):
    """Stable topological order of node ids (original order wins among the ready)."""
    need = {n["id"]: set() for n in nodes}
    for b, a, _ in edges:
        need[b].add(a)
    out, done = [], set()
    remaining = [n["id"] for n in nodes]
    while remaining:
        for nid in remaining:
            if need[nid] <= done:
                out.append(nid)
                done.add(nid)
                remaining.remove(nid)
                break
        else:  # explicit cycle: keep the rest in original order
            out.extend(remaining)
            break
    return out


# ---------------------------------------------------------------------------------------------- step plans
def plan_steps(steps, mode, max_files=None):
    """steps (list of dicts) -> {"steps": [...], "decisions": [...], "changed": bool}"""
    max_files = max_files or int(os.environ.get("OVN_STAGE_ORDER_MERGE_MAX_FILES", "4") or 4)
    nodes = [norm_node(s, i) for i, s in enumerate(steps)]
    edges, cyc_notes = build_edges(nodes)
    pos = {n["id"]: i for i, n in enumerate(nodes)}
    byid = {n["id"]: n for n in nodes}
    decisions = [dict(d, event="cycle_resolved") for d in cyc_notes]
    viol = [(b, a, k) for b, a, k in edges if pos[a] > pos[b]]
    for b, a, k in viol:
        nb, na = byid[b], byid[a]
        red = nb["test_only"] and not na["test_only"] and (k in ("symbol", "explicit") or nb["red"])
        union = sorted(set(files_of(nb)) | set(files_of(na)))
        action = "merge" if (nb["test_only"] != na["test_only"] and len(union) <= max_files) else "reorder"
        decisions.append({"event": "would_reorder" if mode != "enforce" else "reordered", "step": b, "needs": a, "kind": k,
                          "red_by_design": bool(red), "action": action, "desc": nb["desc"][:100], "needs_desc": na["desc"][:100]})
    out_steps = [dict(s) for s in steps]
    for i, s in enumerate(out_steps):
        s.setdefault("id", i)
    deps_of = {n["id"]: sorted({a for b, a, _ in edges if b == n["id"]}, key=lambda x: pos[x]) for n in nodes}
    if mode != "enforce" or not viol:
        for s in out_steps:
            s["deps"] = deps_of.get(s["id"], [])
        return {"steps": out_steps, "decisions": decisions, "changed": False}
    # enforce: merge red-by-design test steps into the step they need, then stable-topological reorder the rest
    work = {s["id"]: dict(s) for s in out_steps}
    absorbed = {}
    for b, a, k in viol:
        nb, na = byid[b], byid[a]
        union = sorted(set(files_of(nb)) | set(files_of(na)))
        if nb["test_only"] != na["test_only"] and len(union) <= max_files and b in work and a in work:
            src_id, tst_id = (a, b) if nb["test_only"] else (b, a)
            if tst_id in absorbed or src_id in absorbed:
                continue
            tgt = work[src_id]
            tgt["desc"] = (str(tgt.get("desc", "")).rstrip(". ") + ". ALSO IN THIS SAME STEP (the test must pass together with the change): " + str(work[tst_id].get("desc", ""))).strip()
            tgt["files"] = list(dict.fromkeys(files_of(tgt) + files_of(work[tst_id])))
            va, vb = str(tgt.get("verify", "")).strip(), str(work[tst_id].get("verify", "")).strip()
            mv = va if (not vb or vb == va) else (vb if not va else "(%s) && (%s)" % (va, vb))
            if mv or "verify" in tgt:   # never invent an empty verify: the runner's jq '// "tests green"' only defaults a MISSING key
                tgt["verify"] = mv
            tgt["merged_from"] = sorted(set(tgt.get("merged_from", []) + [tst_id]), key=str)
            absorbed[tst_id] = src_id
            del work[tst_id]
    live_ids = [s["id"] for s in out_steps if s["id"] in work]
    remap = {}
    for b, a in absorbed.items():
        while a in absorbed:
            a = absorbed[a]
        remap[b] = a
    new_edges = []
    for b, a, k in edges:
        b2, a2 = remap.get(b, b), remap.get(a, a)
        if b2 != a2 and b2 in work and a2 in work:
            # an edge rewritten by a merge is dropped first when it closes a cycle (a test that needed two fix steps now sits in one of them)
            new_edges.append((b2, a2, "merged" if (b2 != b or a2 != a) else k))
    if os.environ.get("OVN_STAGE_ORDER_MERGE_CYCLE_CHECK", "1") != "0":
        seen_e, uniq_e = set(), []
        for e in new_edges:
            if (e[0], e[1]) not in seen_e:
                seen_e.add((e[0], e[1]))
                uniq_e.append(e)
        new_edges, post_notes = drop_cycles(uniq_e)
        decisions.extend(dict(d, event="cycle_resolved", phase="post_merge") for d in post_notes)
    sub_nodes = [n for n in nodes if n["id"] in work]
    order = topo(sub_nodes, new_edges)
    final = []
    for nid in order:
        s = work[nid]
        s["deps"] = sorted({a for b, a, _ in new_edges if b == nid}, key=lambda x: live_ids.index(x) if x in live_ids else 0)
        final.append(s)
    return {"steps": final, "decisions": decisions, "changed": True}


def unmet(steps, i, done):
    """ids of step i's prerequisites that are not in the done set (deps come from the plan's 'deps', else recomputed)."""
    s = steps[i]
    deps = s.get("deps")
    if deps is None:
        deps = [a for b, a, _ in build_edges([norm_node(x, j) for j, x in enumerate(steps)])[0] if b == s.get("id", i)]
    d = set(str(x) for x in done)
    return [x for x in deps if str(x) not in d]


# ---------------------------------------------------------------------------------------------- queue items
def parse_progress(text):
    items = []
    for ln, raw in enumerate(text.split("\n")):
        m = re.match(r"^- \[([ xX])\] (.*)$", raw)
        if not m:
            continue
        body = m.group(2)
        f = FEAT_RE.search(body)
        lead = re.search(r"\[T\d\]\s*([\w./-]+\.\w+)\s+[—-]+\s+", body)
        c = CAT_RE.search(body)
        items.append({"line": ln, "done": m.group(1).lower() == "x", "parked": bool(PARK_RE.search(body)) and m.group(1) == " ", "feat": f.group(1) if f else "",
                      "text": body, "files": [lead.group(1)] if lead else [], "cat": c.group(1) if c else ""})
    return items


def _item_nodes(group):
    nodes = []
    for i, it in enumerate(group):
        body = re.sub(r"^\(.*?\)\s*", "", it["text"], count=1) if it["text"].startswith("(") else it["text"]
        n = norm_node({"id": it["line"], "desc": body, "files": it["files"], "cat": it["cat"]}, it["line"])
        n["test_only"] = (it["cat"] == "test") or is_test_only(n)
        tm = re.search(r"\[T(\d)\]", it["text"])
        n["tier"] = int(tm.group(1)) if tm else 0
        n["it"] = it
        nodes.append(n)
    return nodes


def _max_group():
    try:
        return max(2, int(os.environ.get("OVN_STAGE_ORDER_MAX_GROUP", "60")))
    except ValueError:
        return 60


def item_decisions(candidates, progress_text):
    """For each candidate line (text without '- [ ] ' prefix): {"text":..., "blocked": bool, "waiting_on": [...]}."""
    items = parse_progress(progress_text)
    groups = {}
    for it in items:
        if it["feat"]:
            groups.setdefault(it["feat"], []).append(it)
    gnodes, gedges = {}, {}
    for g, grp in groups.items():
        if len(grp) < 2 or len(grp) > _max_group():
            continue   # >cap: edge building is O(n^2) per group (+ cycle search per edge); fail open (no blocking) instead of stalling the scout
        nodes = _item_nodes(grp)
        gnodes[g] = nodes
        gedges[g] = build_edges(nodes)[0]
    res = []
    for c in candidates:
        key = c.strip()
        hit = None
        for g, nodes in gnodes.items():
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
        byid = {x["id"]: x for x in gnodes[g]}
        wait = []
        for b, a, k in gedges[g]:
            if b == n["id"] and not byid[a]["it"]["done"]:
                an = byid[a]
                wait.append({"line": a + 1, "kind": k, "state": "parked" if an["it"]["parked"] else "open", "tier_text": an["it"]["text"][:110],
                             "red_by_design": bool(n["test_only"] and not an["test_only"])})
        res.append({"text": c, "blocked": bool(wait), "waiting_on": wait, "feat": g, "stuck_parked": bool(wait) and all(w["state"] == "parked" for w in wait)})
    return res


# ---------------------------------------------------------------------------------------------- journaling / cli
def _journal(path, rec, cap=262144, dedupe=False):
    """Append one JSON row. Serialised with flock on <path>.lock (scout, picker and several repos share the file); truncation is an atomic
    tmp+replace; dedupe=True skips a row byte-identical to one in the newest 64KB (a scout cycle re-journals the same decision every time)."""
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        line = json.dumps(rec, ensure_ascii=False)
        lk = None
        try:
            import fcntl
            lk = open(path + ".lock", "a")
            fcntl.flock(lk, fcntl.LOCK_EX)
        except Exception:  # noqa: BLE001 - no flock: best effort, still fail-open
            lk = None
        try:
            if os.path.exists(path):
                size = os.path.getsize(path)
                if dedupe:
                    with open(path, "rb") as fh:
                        fh.seek(max(0, size - 65536))
                        if line in fh.read().decode("utf-8", "replace").split("\n"):
                            return
                if size > cap:
                    with open(path, "rb") as fh:
                        tail = fh.read().split(b"\n")[-500:]
                    tmp = "%s.tmp.%d" % (path, os.getpid())
                    with open(tmp, "wb") as fh:
                        fh.write(b"\n".join(tail))
                    os.replace(tmp, path)
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        finally:
            if lk is not None:
                lk.close()
    except OSError:
        pass


def _read_stdin():
    return sys.stdin.buffer.read().decode("utf-8", "replace")


def cmd_plan(a):
    raw = _read_stdin()
    mode = _env_mode(a.mode)
    try:
        steps = json.loads(raw)
        if mode == "off" or not isinstance(steps, list) or len(steps) < 1:
            sys.stdout.write(json.dumps({"steps": steps if isinstance(steps, list) else [], "decisions": [], "changed": False}))
            return 0
        res = plan_steps(steps, mode)
    except Exception as ex:  # noqa: BLE001 - ordering is advisory
        sys.stderr.write("ovn_stage_order plan: %s: %s\n" % (type(ex).__name__, ex))
        try:
            sys.stdout.write(json.dumps({"steps": json.loads(raw), "decisions": [], "changed": False}))
        except Exception:  # noqa: BLE001
            sys.stdout.write('{"steps":[],"decisions":[],"changed":false}')
        return 0
    if a.log and res["decisions"]:
        for d in res["decisions"]:
            _journal(a.log, dict(d, mode=mode, repo=a.repo, run=a.run, item=(a.item or "")[:160]))
    sys.stdout.write(json.dumps(res))
    return 0


def cmd_unmet(a):
    try:
        steps = json.loads(_read_stdin())
        sys.stdout.write(" ".join(str(x) for x in unmet(steps, a.i, a.done.split())))
    except Exception as ex:  # noqa: BLE001
        sys.stderr.write("ovn_stage_order unmet: %s: %s\n" % (type(ex).__name__, ex))
    return 0


def cmd_item_filter(a):
    lines = _read_stdin().split("\n")
    mode = _env_mode(a.mode)
    cand = [ln for ln in lines if ln.strip()]
    try:
        if mode == "off" or not os.path.exists(a.progress):
            sys.stdout.write("\n".join(lines))
            return 0
        with open(a.progress, encoding="utf-8", errors="replace") as fh:
            ptxt = fh.read()
        decs = item_decisions([re.sub(r"^- \[ \] ", "", ln) for ln in cand], ptxt)
    except Exception as ex:  # noqa: BLE001
        sys.stderr.write("ovn_stage_order item-filter: %s: %s\n" % (type(ex).__name__, ex))
        sys.stdout.write("\n".join(lines))
        return 0
    keep = []
    parked_mode = (os.environ.get("OVN_STAGE_ORDER_PARKED", "hold") or "hold").strip().lower()   # hold (default) | release: enforce lets a dependent of a PARKED prerequisite through
    for ln, d in zip(cand, decs):
        if d["blocked"] and d.get("stuck_parked") and a.log:
            # escalation signal: every open prerequisite is parked (AUTO-SKIP/[CLAUDE]/BLOCKED/HUMAN-ONLY), only a human can unpark it, so the dependent would wait forever
            _journal(a.log, {"event": "stuck_on_parked_prereq", "mode": mode, "parked_mode": parked_mode, "repo": a.repo, "feat": d.get("feat"),
                             "item": d["text"][:160], "waiting_on": d["waiting_on"]}, dedupe=True)
        if d["blocked"] and d.get("stuck_parked") and mode == "enforce" and parked_mode == "release":
            keep.append(ln)
            continue
        if d["blocked"]:
            if a.log:
                _journal(a.log, {"event": "would_skip_item" if mode != "enforce" else "skipped_item", "mode": mode, "repo": a.repo, "feat": d.get("feat"),
                                 "item": d["text"][:160], "waiting_on": d["waiting_on"]}, dedupe=True)
            if mode == "enforce":
                continue
        keep.append(ln)
    sys.stdout.write("\n".join(keep) + ("\n" if keep else ""))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--mode", default="")
    p.add_argument("--repo", default="")
    p.add_argument("--run", default="")
    p.add_argument("--item", default="")
    p.add_argument("--log", default="")
    u = sub.add_parser("unmet")
    u.add_argument("--i", type=int, required=True)
    u.add_argument("--done", default="")
    f = sub.add_parser("item-filter")
    f.add_argument("--progress", required=True)
    f.add_argument("--mode", default="")
    f.add_argument("--repo", default="")
    f.add_argument("--log", default="")
    a = ap.parse_args(argv)
    return {"plan": cmd_plan, "unmet": cmd_unmet, "item-filter": cmd_item_filter}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
