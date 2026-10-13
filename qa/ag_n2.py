#!/usr/bin/env python3
"""ag_n2.py - 2026-10-13 night-review package `qa` rules for gate_antigaming.py (platform-night P5a/P5c, iptv-night F4). Imported by gate_antigaming.check();
never executes repo code, only `git ls-tree/show` on refs. Every rule is isolated: an internal error or the deadline becomes a note, never a finding or a crash.

  N_NEWPATH_LOOKALIKE  a NEW .py/.ts/.tsx/.gd file lands in a directory that did not exist at base AND the first new path component
                       (a) repeats its parent's name, exactly or within edit distance 2 (`iptv-backend/iptv-backend/tests/x.py` while `iptv-backend/tests/` exists at base;
                           `app/routers/outers/subscription.py` while `app/routers/` exists), or
                       (b) is within edit distance 2 of an existing sibling directory that still holds files at head
                           (`services/` vs `service/`).
                       Both shapes were agent typos that created a file nothing imports / collects (3 stray tests that hid a broken test, a 1-byte junk
                       router file). FLAG; FAIL only when the gate mode `antigaming_newpath` is enforce (qa/qa_enforce.sh antigaming_newpath enforce,
                       env OVN_QA_ANTIGAMING_NEWPATH). `off` skips the rule. Still a second key: it only blocks a merge while the shared `antigaming`
                       gate is ALSO enforce.
  N_EMPTIED_SOURCE     a tracked .py/.ts/.tsx/.gd file that was non-empty at base and is <= 1 byte at head (emptied instead of deleted; 4 such files were
                       on iptv develop on 2026-10-13). `__init__.py` is exempt (an emptied package marker is a normal refactor). FLAG only, never FAIL. A test file that A_TESTFILE_EMPTIED already reported is not reported twice.
                       OVN_QA_AG_N2=off disables the whole module.

`python3 qa/ag_n2.py sweep --repo R [--base B] [--head H]` runs the N_EMPTIED_SOURCE check over a ref range outside the gate (default head = origin/develop,
base = merge-base(head, origin/main)); one JSON line per file, exit 0 always. The default base cannot see a file that is already on origin/main (an emptied file
promoted to main is invisible to it): pass --base <older ref> for a periodic run (docs/QA_GATE_READINESS_2026-10-13.md).
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

NEWPATH_MODE_GATE = "antigaming_newpath"
NEWPATH_EXTS = (".py", ".ts", ".tsx", ".gd")
EMPTIED_EXTS = (".py", ".ts", ".tsx", ".gd")
EMPTIED_SKIP_BASENAMES = ("__init__.py",)   # an emptied package marker is a normal refactor (gitlark 5afb880e1b stripped the re-exports of the modules it deleted); found by the 60-day replay
MIN_NAME_LEN = 4        # both names: a 'v1'/'api'/'app' sized name is within distance 2 of everything
MAX_DIST = 2
CAP = 10


def newpath_mode():
    """off | shadow | enforce for the FAIL severity of N_NEWPATH_LOOKALIKE (a second key on top of the shared `antigaming` flip)."""
    return qc.mode(NEWPATH_MODE_GATE)


def newpath_sev():
    return "FAIL" if newpath_mode() == "enforce" else "FLAG"


def _ga():
    import gate_antigaming as ga
    return ga


def lev(a, b, limit=MAX_DIST):
    """Levenshtein distance, or limit+1 as soon as it is certain to exceed `limit` (names are short; this is O(len^2) at worst)."""
    if a == b:
        return 0
    if abs(len(a) - len(b)) > limit:
        return limit + 1
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        if min(cur) > limit:
            return limit + 1
        prev = cur
    return prev[-1]


def _digits_only_diff(a, b):
    """v1/v2, step3/step4, 0010/0011: names that differ only in their digits are siblings by design, not typos."""
    return re.sub(r"\d+", "", a) == re.sub(r"\d+", "", b)


def lookalike(name, sib):
    if name == sib or len(name) < MIN_NAME_LEN or len(sib) < MIN_NAME_LEN or name.startswith(".") or sib.startswith("."):
        return False
    if _digits_only_diff(name, sib):
        return False
    return lev(name.lower(), sib.lower()) <= MAX_DIST


def dir_index(files):
    """(set of every directory prefix, {dir: set(child dir names)}) of a file list; '' is the repo root."""
    dirs, kids = set(), {}
    for f in files:
        parts = f.split("/")[:-1]
        for i in range(len(parts)):
            d = "/".join(parts[:i + 1])
            parent = "/".join(parts[:i])
            if d not in dirs:
                dirs.add(d)
                kids.setdefault(parent, set()).add(parts[i])
    return dirs, kids


def judge(path, base_dirs, base_kids, sibling_alive=lambda d: True):
    """None, or (kind, detail) for the FIRST path component of `path`'s directory that did not exist at base.
    kind 'doubled'   detail = the existing directory the collapsed path lands in (new dir repeats its parent's name exactly or within distance 2)
    kind 'lookalike' detail = the existing sibling directory the new name is within edit distance 2 of"""
    comps = path.split("/")[:-1]
    for i, name in enumerate(comps):
        prefix = "/".join(comps[:i + 1])
        if prefix in base_dirs:
            continue
        parent = "/".join(comps[:i])
        if i > 0 and (name == comps[i - 1] or lookalike(name, comps[i - 1])):
            # a new directory that repeats its PARENT's name (exactly, or within edit distance 2: `routers/outers/`) - the udiff / planner path was mis-resolved.
            # Only when the collapsed path (the repeated component dropped) is a directory that exists at base, i.e. the file belongs one level up.
            collapsed = "/".join(comps[:i] + comps[i + 1:])
            if collapsed in base_dirs:
                return "doubled", collapsed
        for sib in sorted(base_kids.get(parent, ())):
            if lookalike(name, sib) and sibling_alive("/".join(x for x in (parent, sib) if x)):
                return "lookalike", ("%s/%s" % (parent, sib)) if parent else sib
        return None      # only the first new component is judged: below it every directory is new by definition
    return None


def rule_newpath(repo, status, out, notes, deadline):
    ga = _ga()
    if newpath_mode() == "off":
        return
    cands = [p for p, st in sorted(status.items()) if st in ("A", "R") and p.lower().endswith(NEWPATH_EXTS) and not ga.ignorable(p)
             and not any(c.startswith(".") for c in p.split("/")[:-1])]
    if not cands:
        return
    tree = repo.tree()
    if not tree:
        notes.append("N_NEWPATH_LOOKALIKE skipped: base tree unreadable")
        return
    dirs, kids = dir_index(tree)
    alive = {}

    def sibling_alive(d):    # the sibling must still hold files at head: a directory renamed away in the same diff is not a typo target
        if d not in alive:
            rc, o, _ = qc.git(repo.rd, "ls-tree", "-r", "--name-only", repo.head, "--", d + "/", timeout=30)
            alive[d] = (rc == 0 and bool(o.strip()))
        return alive[d]

    seen, n = set(), 0
    sev = newpath_sev()
    for p in cands:
        if n >= CAP or time.time() > deadline:
            break
        r = judge(p, dirs, kids, sibling_alive)
        if not r:
            continue
        kind, detail = r
        newdir = os.path.dirname(p)
        key = (newdir, kind)
        if key in seen:
            continue
        seen.add(key)
        if kind == "doubled":
            msg = ("new file in `%s/`, a directory that did not exist at base and repeats its parent's name (within edit distance 2): `%s/` exists - the path "
                   "looks mis-resolved, so nothing imports or collects this file" % (newdir, detail))
        else:
            msg = ("new file in `%s/`, a directory that did not exist at base and whose name is within edit distance 2 of the existing sibling `%s/` "
                   "(typo? nothing imports or collects this file)" % (newdir, detail))
        out.append(_ga().F("N_NEWPATH_LOOKALIKE", sev, p, 1, msg, os.path.basename(p)))
        n += 1


def _sizes(rd, ref, paths):
    """{path: byte size} of `paths` at `ref` (missing paths are absent), via batched `git ls-tree -l`."""
    res = {}
    for i in range(0, len(paths), 200):
        chunk = paths[i:i + 200]
        rc, o, _ = qc.git(rd, "-c", "core.quotepath=false", "ls-tree", "-l", "-z", ref, "--", *chunk, timeout=60)
        if rc != 0:
            continue
        for rec in o.split("\0"):
            m = re.match(r"^\d+ \w+ [0-9a-f]+\s+(\d+|-)\t(.+)$", rec)
            if m and m.group(1) != "-":
                res[m.group(2)] = int(m.group(1))
    return res


def emptied_sources(rd, base, head, paths):
    """[(path, old_size, new_size)]: tracked source files of `paths` that are <= 1 byte at head and were non-empty (> 1 byte) at base."""
    paths = [p for p in paths if p.lower().endswith(EMPTIED_EXTS) and os.path.basename(p) not in EMPTIED_SKIP_BASENAMES]
    if not paths:
        return []
    new = _sizes(rd, head, paths)
    small = [p for p in paths if new.get(p, 2) <= 1]
    if not small:
        return []
    old = _sizes(rd, base, small)
    return [(p, old[p], new[p]) for p in small if old.get(p, 0) > 1]


def rule_emptied_source(repo, status, diffs, out, notes):
    ga = _ga()
    paths, oldname = [], {}
    for p, st in sorted(status.items()):
        if st in ("M", "R") and not ga.ignorable(p):
            paths.append(p)
            if st == "R" and p in diffs and diffs[p].old:
                oldname[p] = diffs[p].old
    # renamed files: the base size is looked up under the OLD name
    plain = [p for p in paths if p not in oldname]
    hits = emptied_sources(repo.rd, repo.base, repo.head, plain)
    for p, old_n in oldname.items():
        new = _sizes(repo.rd, repo.head, [p]).get(p, 2)
        if new <= 1 and p.lower().endswith(EMPTIED_EXTS) and os.path.basename(p) not in EMPTIED_SKIP_BASENAMES and _sizes(repo.rd, repo.base, [old_n]).get(old_n, 0) > 1:
            hits.append((p, _sizes(repo.rd, repo.base, [old_n])[old_n], new))
    for p, old_n, new_n in hits[:CAP]:
        if any(f["file"] == p and f["rule"] == "A_TESTFILE_EMPTIED" for f in out):
            continue
        out.append(ga.F("N_EMPTIED_SOURCE", "FLAG", p, 1, "tracked source file went from %d bytes to %d (emptied instead of deleted or fixed): the file stays in the tree, "
                        "collects nothing and looks like a real module" % (old_n, new_n), os.path.basename(p)))


def run_all(repo, repo_name, status, st_raw, diffs, findings, notes, deadline, no_record):
    steps = [("newpath", lambda: rule_newpath(repo, status, findings, notes, deadline)),
             ("emptied_source", lambda: rule_emptied_source(repo, status, diffs, findings, notes))]
    for name, fn in steps:
        if time.time() > deadline:
            notes.append("n2 rules skipped from %s (deadline)" % name)
            break
        try:
            fn()
        except Exception as ex:  # noqa: BLE001 - a rule bug must never change the verdict
            notes.append("n2 rule %s errored: %s: %s" % (name, type(ex).__name__, str(ex)[:80]))


# ---------------------------------------------------------------------------------------------------------------- sweep CLI
def sweep(rd, base, head):
    rc, o, _ = qc.git(rd, "-c", "core.quotepath=false", "ls-tree", "-r", "-l", "-z", head, timeout=120)
    if rc != 0:
        return None
    small = []
    for rec in o.split("\0"):
        m = re.match(r"^\d+ blob [0-9a-f]+\s+(\d+)\t(.+)$", rec)
        if m and int(m.group(1)) <= 1 and m.group(2).lower().endswith(EMPTIED_EXTS) and os.path.basename(m.group(2)) not in EMPTIED_SKIP_BASENAMES:
            small.append((m.group(2), int(m.group(1))))
    old = _sizes(rd, base, [p for p, _ in small])
    return [(p, old[p], n) for p, n in small if old.get(p, 0) > 1]


def main(argv):
    if not argv or argv[0] != "sweep":
        print("usage: ag_n2.py sweep --repo R [--base B] [--head H]", file=sys.stderr)
        return 0
    a = {"repo": None, "base": None, "head": "origin/develop"}
    i = 1
    while i < len(argv):
        if argv[i] in ("--repo", "--base", "--head") and i + 1 < len(argv):
            a[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    rd = a["repo"] if a["repo"] and os.path.isdir(a["repo"]) else (qc.repo_dir(a["repo"]) if a["repo"] else None)
    if not rd:
        print(json.dumps({"verdict": "UNVERIFIED", "why": "no clone"}))
        return 0
    if not a["base"]:
        rc, mb, _ = qc.git(rd, "merge-base", a["head"], "origin/main")
        a["base"] = mb.strip() if rc == 0 and mb.strip() else "origin/main"
    res = sweep(rd, a["base"], a["head"])
    if res is None:
        print(json.dumps({"verdict": "UNVERIFIED", "why": "git ls-tree failed", "base": a["base"], "head": a["head"]}))
        return 0
    for p, o, n in res:
        print(json.dumps({"rule": "N_EMPTIED_SOURCE", "sev": "FLAG", "file": p, "base_bytes": o, "head_bytes": n, "base": a["base"], "head": a["head"]}))
    print(json.dumps({"verdict": "FLAG" if res else "PASS", "count": len(res), "base": a["base"], "head": a["head"]}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
