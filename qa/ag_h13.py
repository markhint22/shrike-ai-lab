#!/usr/bin/env python3
"""ag_h13.py - 2026-10-04 audit-driven rules for gate_antigaming.py (all SHADOW: FLAG; the frozen-vendored-edit is FLAG too unless its own mode `antigaming_frozen` is enforce). Imported by gate_antigaming.check(); never executes repo code, only `git grep/log/show` on refs.

  D_DEAD_SYMBOL        a NEWLY ADDED public def/class/func in non-test code whose name has no production referencer (only tests / own definition)
  E_TEST_NOT_COLLECTED a newly added test file the repo's verify command would not collect (qa/test_collection.json, else pytest testpaths)
  F_REVERT_OF_RECENT   a file's diff is >=80% the exact inverse of one of the last 20 commits touching it (+ per-file counter / alert at >=6 per 24h)
  D_FROZEN_EDIT        edit/delete/rename under a frozen vendored path (qa/frozen_paths.json: addons/** for xlite, vendor/**, third_party/**) -> FLAG;
                       FAIL only when the separate gate mode `antigaming_frozen` is flipped to enforce (the shared `antigaming` flip does NOT arm it)
  D_FROZEN_NEWFILE     a NEW file created under a frozen path -> FLAG
  C_FILE_DELETED_LIVE  a deleted non-test file whose symbols still have non-test referencers (or whose tests remain and still reference it)
  C_TEST_ORPHANED      a symbol removed from non-test code that a surviving test file still references
  A_MOCK_ONLY          a python test whose ONLY assertions are assert_called*/call_count on a mock created in the same test
  A_MIRROR_EXPECTED    a GUT assertion whose expected value is computed by calling the same function on the same input as the actual value

Every rule is wrapped: an internal error or a deadline becomes a note, never a finding and never a crash.
"""
import ast
import fnmatch
import json
import os
import re
import time

import qa_common as qc

HERE = os.path.dirname(os.path.abspath(__file__))
PROD_EXT = {".py", ".gd", ".tscn", ".tres", ".godot", ".cfg", ".ts", ".tsx", ".js", ".jsx", ".vue", ".kt", ".swift", ".sh", ".yml", ".yaml",
            ".toml", ".ini", ".html", ".mako", ".sql", ".mjs", ".cjs", ".kts", ".java"}
BOOKKEEPING_RE = re.compile(r"(?:^|/)(?:OVERNIGHT_[A-Z_]+|CLAUDE_QUEUE[A-Z_]*|ROADMAP|AGENTS|README|CHANGELOG)[^/]*$|\.(?:md|txt|rst|uid|import|lock|log|jsonl?)$", re.I)
GEN_NAMES = {"main", "create_app", "handler", "lambda_handler", "upgrade", "downgrade", "setup", "teardown"}
PY_SKIP_DIRS = {"alembic", "scripts", "tools", "migrations", "versions", "docs", "examples"}
PY_OK_DECOS = {"staticmethod", "classmethod", "lru_cache", "cache", "wraps", "contextmanager", "asynccontextmanager", "dataclass", "property"}
MODEL_BASES = re.compile(r"Base|Model|Schema|Enum|Exception|Error|TypedDict|Protocol|Settings|NamedTuple|Mixin|ABC")
CAP_DEAD, CAP_DELETED, CAP_ORPHAN, CAP_REVERT = 15, 10, 10, 12


def _lang(path):
    ext = os.path.splitext(path)[1].lower()
    return {".py": "py", ".gd": "gd"}.get(ext)


def _is_test(path):
    import gate_antigaming as ga
    return ga.is_test_path(path)


def _load_json(name):
    try:
        with open(os.path.join(HERE, name)) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _grep(rd, ref, pattern, fixed=True, word=True, timeout=40, extra=()):
    """-> list of (path, lineno, text) or None when git grep could not run. rc 1 (no match) -> []."""
    args = ["grep", "-n", "-I"] + (["-F"] if fixed else ["-E"]) + (["-w"] if word else []) + list(extra) + ["-e", pattern, ref, "--"]
    rc, out, _ = qc.git(rd, *args, timeout=timeout)
    if rc == 1:
        return []
    if rc != 0:
        return None
    hits = []
    pre = ref + ":"
    for ln in out.splitlines():
        if ln.startswith(pre):
            ln = ln[len(pre):]
        parts = ln.split(":", 2)
        if len(parts) < 3 or not parts[1].isdigit():
            continue
        hits.append((parts[0], int(parts[1]), parts[2]))
    return hits


def _blob(rd, ref, path):
    rc, out, _ = qc.git(rd, "show", "%s:%s" % (ref, path), timeout=30)
    return out if rc == 0 and len(out) < 800000 else None


def _tree_head(repo):
    if getattr(repo, "_tree_head", None) is None:
        rc, out, _ = qc.git(repo.rd, "ls-tree", "-r", "--name-only", repo.head, timeout=60)
        repo._tree_head = set(out.splitlines()) if rc == 0 else set()
    return repo._tree_head


def _prod_path(path):
    return (os.path.splitext(path)[1].lower() in PROD_EXT and not _is_test(path) and not BOOKKEEPING_RE.search(path))


DEF_PY = re.compile(r"^(?:async\s+def|def|class)\s+([A-Za-z]\w*)")
DEF_GD = re.compile(r"^(?:static\s+func|func|class_name|class)\s+([A-Za-z]\w*)")


def _public_defs(lang, text):
    """-> {name: (lineno, kind, headerline)} top-level public symbols in `text`."""
    out = {}
    rx = DEF_PY if lang == "py" else DEF_GD
    for i, ln in enumerate(text.split("\n"), 1):
        m = rx.match(ln)
        if m and not m.group(1).startswith("_"):
            kind = "class" if ln.startswith(("class", "class_name")) else "func"
            out.setdefault(m.group(1), (i, kind, ln))
    return out


def _decorators(lines, lineno):
    """Decorator names directly above 1-based line `lineno` (python)."""
    names = []
    i = lineno - 2
    while i >= 0 and lines[i].lstrip().startswith("@"):
        m = re.match(r"\s*@([\w.]+)", lines[i])
        if m:
            names.append(m.group(1))
        i -= 1
    return names


# Review fix 2026-10-04: the enclosing-symbol scan must also see PRIVATE (`_name`) top-level defs. With the public-only regex a use inside
# `static func _grid_dict_problem` was attributed to the nearest PUBLIC def above it - often the candidate itself ("recursion") - so a public helper
# used only by a private helper of the same file was flagged D_DEAD_SYMBOL (real xlite FP: battle_save_codec.is_cell_key).
ENC_PY = re.compile(r"^(?:async\s+def|def|class)\s+([A-Za-z_]\w*)")
ENC_GD = re.compile(r"^(?:static\s+func|func|class_name|class)\s+([A-Za-z_]\w*)")


def _enclosing(lines, lineno, lang):
    rx = ENC_PY if lang == "py" else ENC_GD
    cur = lines[lineno - 1] if 0 < lineno <= len(lines) else ""
    if cur and not cur[0].isspace() and not rx.match(cur):
        return "<module>"  # module-level statement (runs at import): a real use, not part of any function body
    for i in range(lineno - 1, -1, -1):
        m = rx.match(lines[i])
        if m:
            return m.group(1)
    return None


# ---------------------------------------------------------------------------------------------------------------- D_DEAD_SYMBOL
def rule_dead_symbol(repo, status, diffs, out, deadline):
    cands = []  # (path, name, lineno, kind, lang)
    for path, st in status.items():
        lang = _lang(path)
        if st not in ("A", "M", "R") or not lang or _is_test(path) or path not in diffs:
            continue
        parts = path.split("/")
        if "addons" in parts or (lang == "py" and (set(parts[:-1]) & PY_SKIP_DIRS)) or parts[-1] in ("conftest.py",):
            continue
        txt = repo.blob(repo.head, path)
        if txt is None:
            continue
        added_lines = {n for n, _ in diffs[path].added}
        old = repo.blob(repo.base, diffs[path].old or path) if st in ("M", "R") else None
        old_defs = _public_defs(lang, old) if old else {}
        lines = txt.split("\n")
        for name, (ln, kind, header) in _public_defs(lang, txt).items():
            if ln not in added_lines:
                continue
            if name in old_defs or name in GEN_NAMES or name.startswith("test_") or (name.startswith("__") and name.endswith("__")):
                continue
            if lang == "py":
                decos = _decorators(lines, ln)
                if any(d.split(".")[-1] not in PY_OK_DECOS for d in decos):
                    continue  # route / fixture / task / validator: registered by the decorator, not by a call
                if kind == "class" and (MODEL_BASES.search(header) or "__tablename__" in txt[txt.find(header):txt.find(header) + 1500]):
                    continue
            cands.append((path, name, ln, kind, lang))
    if not cands:
        return
    cand_names = {(p, n) for p, n, *_ in cands}
    info = {}  # name -> dict(prod, tests, via=set of candidate names whose body references it, c=cand tuple)
    for c in cands[:40]:
        path, name, ln, kind, lang = c
        if name in info or time.time() > deadline:
            continue
        hits = _grep(repo.rd, repo.head, name)
        if hits is None:
            continue
        prod = tests = 0
        via = set()
        for hp, hl, ht in hits:
            if re.match(r"\s*#", ht):
                continue
            if _is_test(hp):
                tests += 1
                continue
            if not _prod_path(hp):
                continue
            if hp == path:
                txt = repo.blob(repo.head, path) or ""
                encl = _enclosing(txt.split("\n"), hl, lang)
                if hl == ln or encl == name:
                    continue  # own definition / recursion
                if (path, encl) in cand_names:
                    via.add(encl)  # referenced from the body of another NEW symbol of the same file: live only if that one is
                    continue
            prod += 1
        if not prod and kind == "class" and lang == "gd":
            # a GDScript class is also wired by path (preload/load/.tscn/project.godot autoload) rather than by its class_name
            ph = _grep(repo.rd, repo.head, os.path.basename(path)) or []
            prod += sum(1 for hp, hl, ht in ph if hp != path and _prod_path(hp))
        info[name] = {"prod": prod, "tests": tests, "via": via, "c": c}
    live = {n for n, i in info.items() if i["prod"]}
    changed = True
    while changed:
        changed = False
        for n, i in info.items():
            if n not in live and any(v in live for v in i["via"]):
                live.add(n)
                changed = True
    n_flag = 0
    for name, i in info.items():
        if name in live or n_flag >= CAP_DEAD:
            continue
        path, _n, ln, kind, lang = i["c"]
        why = "only tests reference it (%d test ref(s))" % i["tests"] if i["tests"] else "nothing references it"
        out.append(_F("D_DEAD_SYMBOL", "FLAG", path, ln, "new public %s %s has no production caller: %s" % (kind, name, why), "%s %s" % (kind, name)))
        n_flag += 1
    return


def _F(rule, sev, path, line, msg, text=""):
    import gate_antigaming as ga
    return ga.F(rule, sev, path, line, msg, text)


# ---------------------------------------------------------------------------------------------------------------- E_TEST_NOT_COLLECTED
def _pytest_testpaths(repo, path):
    """testpaths (repo-relative dirs) of the nearest pytest config above `path` at head, or None when there is none / it sets none."""
    tree = _tree_head(repo)
    d = os.path.dirname(path)
    while True:
        for cfg in ("pytest.ini", ".pytest.ini", "tox.ini", "setup.cfg", "pyproject.toml"):
            p = (d + "/" + cfg) if d else cfg
            if p in tree:
                txt = _blob(repo.rd, repo.head, p) or ""
                if cfg in ("tox.ini", "setup.cfg") and "pytest" not in txt:
                    continue
                if cfg == "pyproject.toml" and "pytest" not in txt:
                    continue
                m = re.search(r"^\s*testpaths\s*[=:]\s*(.+)$", txt, re.M)
                if not m:
                    return None
                raw = m.group(1).replace("[", " ").replace("]", " ").replace('"', " ").replace("'", " ").replace(",", " ")
                return [((d + "/") if d else "") + t.strip("./") + "/" for t in raw.split() if t.strip("./")] or None
        if not d:
            return None
        d = os.path.dirname(d)


def rule_test_not_collected(repo, repo_name, status, diffs, out):
    cfg = _load_json("test_collection.json").get(repo_name, {})
    recursive = os.environ.get("OVN_GUT_SUBDIRS", "on") != "off"
    for path, st in status.items():
        if st not in ("A", "R"):
            continue
        lang = _lang(path)
        base = os.path.basename(path)
        txt = None
        if lang == "py":
            if not (re.match(r"test_.*\.py$|.*_test\.py$", base)) or base == "conftest.py":
                continue
            roots = (cfg.get("py") or {}).get("roots")
            if roots is None:
                roots = _pytest_testpaths(repo, path)
            if roots is None:
                continue  # no testpaths => pytest from the repo/package root collects it
            if not any(path.startswith(r) for r in roots):
                out.append(_F("E_TEST_NOT_COLLECTED", "FLAG", path, 1, "new test file is outside the dir(s) the verify command collects (%s)" % ", ".join(roots), base))
        elif lang == "gd" and cfg.get("gd"):
            g = cfg["gd"]
            txt = repo.blob(repo.head, path) or ""
            testy = base.startswith(g.get("prefix", "test_")) or base.endswith("_test.gd") or re.search(r"^\s*func\s+test_\w+", txt, re.M)
            if not testy or "addons/" in path:
                continue
            reason = None
            roots = g.get("roots", ["tests/"])
            under = [r for r in roots if path.startswith(r)]
            if not under:
                reason = "outside %s" % "/".join(roots)
            elif not recursive and "/" in path[len(under[0]):]:
                reason = "in a subdirectory of tests/ (OVN_GUT_SUBDIRS=off)"
            elif not base.startswith(g.get("prefix", "test_")):
                reason = "file name does not start with '%s' (GUT prefix)" % g.get("prefix", "test_")
            elif not re.search(r"^\s*extends\s+(?:GutTest\b|[\"']res://addons/gut/test\.gd[\"'])", txt, re.M):
                reason = "does not extend GutTest"
            if reason:
                out.append(_F("E_TEST_NOT_COLLECTED", "FLAG", path, 1, "new GUT test is never collected: %s" % reason, base))


# ---------------------------------------------------------------------------------------------------------------- frozen vendored paths
def rule_frozen_paths(repo_name, status, st_old, out):
    cfg = _load_json("frozen_paths.json")
    pats = list(cfg.get("default", [])) + list(cfg.get(repo_name, []))
    if not pats:
        return "NA: no frozen_paths"
    # OWN mode switch (review fix 2026-10-04): the shared `antigaming` flip makes ANY FAIL block a merge, so flipping antigaming to enforce
    # would silently start blocking vendored edits too. Here FAIL only when the gate "antigaming_frozen" is itself flipped to enforce
    # (qa/qa_enforce.sh antigaming_frozen enforce | env OVN_QA_ANTIGAMING_FROZEN); shadow (default) => FLAG, off => rule skipped.
    fmode = qc.mode("antigaming_frozen")
    if fmode == "off":
        return "NA: antigaming_frozen mode off"
    edit_sev = "FAIL" if fmode == "enforce" else "FLAG"

    def hit(p):
        return any(fnmatch.fnmatch(p, g) or p.startswith(g.rstrip("*").rstrip("/") + "/") for g in pats)
    n = 0
    for p, s in status.items():
        olds = st_old.get(p)
        if not (hit(p) or (olds and hit(olds))):
            continue
        n += 1
        if s == "A":
            out.append(_F("D_FROZEN_NEWFILE", "FLAG", p, 1, "new file created under a frozen vendored path", ""))
        else:
            out.append(_F("D_FROZEN_EDIT", edit_sev, p, 1, "edit to a frozen vendored path (%s): the fleet must not modify vendored code" % ("deleted" if s == "D" else "modified" if s == "M" else "renamed"), ""))
    return ("checked %d vendored path(s) in diff" % n) if n else "NA: no vendored path in diff"


# ---------------------------------------------------------------------------------------------------------------- F_REVERT_OF_RECENT
TRIVIAL = re.compile(r"^[\s\W_]{0,4}$|^\s*(?:pass|end|else:?|return|break|continue|\)|\]|\}|\{)\s*$")


def _norm_set(rows):
    s = {}
    for _, t in rows:
        t = " ".join(t.split())
        if len(t) < 5 or TRIVIAL.match(t):
            continue
        s[t] = s.get(t, 0) + 1
    return s


def _inverse_fraction(cur_add, cur_rem, prior_add, prior_rem):
    total = sum(cur_add.values()) + sum(cur_rem.values())
    if total < 2:
        return 0.0, total
    inv = sum(min(v, prior_rem.get(k, 0)) for k, v in cur_add.items()) + sum(min(v, prior_add.get(k, 0)) for k, v in cur_rem.items())
    return inv / float(total), total


def _counter_path():
    return os.path.join(qc.state_dir(), "qa_revert_counter.json")


def _record_revert(repo_name, path, sha, no_record):
    """Per-file counter of inverse commits; parks nothing. >=6 distinct commits in 24h => ONE alerts.log warn per (file, day)."""
    if no_record:
        return
    try:
        p = _counter_path()
        try:
            with open(p) as f:
                d = json.load(f)
        except (OSError, ValueError):
            d = {}
        now = time.time()
        key = "%s:%s" % (repo_name, path)
        rows = [r for r in d.setdefault("files", {}).get(key, []) if now - r[0] < 86400 and r[1] != sha] + [[now, sha]]
        d["files"][key] = rows
        day = time.strftime("%Y-%m-%d")
        al = d.setdefault("alerted", {})
        for k in [k for k in al if not k.endswith(day)]:
            al.pop(k, None)
        if len(rows) >= 6 and (key + "|" + day) not in al:
            al[key + "|" + day] = 1
            with open(os.path.join(qc.state_dir(), "alerts.log"), "a") as f:
                f.write("[%s] warn | qa-revert-churn:%s | %s saw %d inverse (revert-of-recent) commits in 24h - the fleet is flip-flopping on it\n" % (
                    time.strftime("%Y-%m-%d %H:%M:%S"), repo_name, path, len(rows)))
        tmp = p + ".tmp%d" % os.getpid()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, p)
    except OSError:
        pass


def rule_revert_of_recent(repo, repo_name, status, diffs, out, deadline, no_record, head_sha=None):
    import gate_antigaming as ga
    n = 0
    for path, fd in diffs.items():
        if n >= CAP_REVERT or time.time() > deadline:
            break
        if status.get(path) not in ("M",) or BOOKKEEPING_RE.search(path) or len(fd.added) + len(fd.removed) > 400:
            continue
        ca, cr = _norm_set(fd.added), _norm_set(fd.removed)
        if sum(ca.values()) + sum(cr.values()) < 2:
            continue
        n += 1
        rc, lg, _ = qc.git(repo.rd, "log", "-n", "20", "--no-merges", "--format=%H", repo.base, "--", path, timeout=30)
        if rc != 0:
            continue
        for sha in lg.split():
            rc, dtext, _ = qc.git(repo.rd, "show", "-U0", "--format=", "--no-color", sha, "--", path, timeout=30)
            if rc != 0 or not dtext:
                continue
            pd = ga.parse_diff(dtext)
            pfd = pd.get(path) or (next(iter(pd.values())) if pd else None)
            if pfd is None:
                continue
            if "\nnew file mode" in "\n" + dtext:
                continue  # the file was CREATED there: deleting lines of a fresh file (duplicate removal etc.) is not a flip-flop
            pa, pr = _norm_set(pfd.added), _norm_set(pfd.removed)
            frac, total = _inverse_fraction(ca, cr, pa, pr)
            ptot = sum(pa.values()) + sum(pr.values())
            undone = (sum(min(v, pr.get(k, 0)) for k, v in ca.items()) + sum(min(v, pa.get(k, 0)) for k, v in cr.items())) / float(ptot) if ptot else 0.0
            if frac >= 0.8 and undone >= 0.5:
                out.append(_F("F_REVERT_OF_RECENT", "FLAG", path, 1, "%d%% of this diff (%d changed lines) is the exact inverse of recent commit %s" % (int(frac * 100), total, sha[:10]), ""))
                _record_revert(repo_name, path, head_sha or repo.head, no_record)
                break


# ---------------------------------------------------------------------------------------------------------------- C_FILE_DELETED_LIVE / C_TEST_ORPHANED
_STRLIT = re.compile(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'")


def _code_ref(text, name):
    """True when `name` appears as an identifier OUTSIDE string literals (a log/label string such as "reset_password target=3" is not a call)."""
    return re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(name), _STRLIT.sub('""', text)) is not None


def _defined_at(repo, ref, name):
    pat = r"(def|class|func|function|fun|signal|enum|const|var|class_name)[[:space:]]+%s([^A-Za-z0-9_]|$)" % name
    h = _grep(repo.rd, ref, pat, fixed=False, word=False, extra=("-e", r"^[[:space:]]*%s[[:space:]]*[:=]" % name))
    return None if h is None else bool(h)


def rule_deleted_live(repo, status, out, deadline):
    n = 0
    for path, st in status.items():
        if st != "D" or _is_test(path) or n >= CAP_DELETED or time.time() > deadline:
            continue
        lang = _lang(path)
        if not lang or "addons" in path.split("/"):
            continue
        old = repo.blob(repo.base, path)
        if not old:
            continue
        n += 1
        syms = [s for s in _public_defs(lang, old) if len(s) >= 5 and s not in GEN_NAMES][:6]
        live, tested = [], []
        for s in syms:
            d = _defined_at(repo, repo.head, s)
            if d is None or d:
                continue  # unknown or moved elsewhere
            hits = _grep(repo.rd, repo.head, s) or []
            for hp, hl, ht in hits:
                if re.match(r"\s*#", ht):
                    continue
                if _is_test(hp):
                    if _code_ref(ht, s):
                        tested.append((s, hp))
                elif _prod_path(hp):
                    live.append((s, hp))
        if live or tested:
            who = live[0] if live else tested[0]
            out.append(_F("C_FILE_DELETED_LIVE", "FLAG", path, 1, "deleted file's symbol %s is still referenced by %s %s (%d non-test, %d test referencer(s))" % (
                who[0], "non-test" if live else "test", who[1], len(live), len(tested)), ""))


def rule_test_orphaned(repo, diffs, out, deadline):
    import gate_antigaming as ga
    syms = ga._removed_syms({k: v for k, v in diffs.items() if _lang(k) or ga.lang_of(k)})
    n = 0
    for s in sorted(syms):
        if n >= CAP_ORPHAN or time.time() > deadline or len(s) < 5:
            continue
        d = _defined_at(repo, repo.head, s)
        if d is None or d:
            continue
        hits = _grep(repo.rd, repo.head, s) or []
        th = [(hp, hl, ht) for hp, hl, ht in hits if _is_test(hp) and not re.match(r"\s*(#|//)", ht) and _code_ref(ht, s)]
        if th:
            n += 1
            out.append(_F("C_TEST_ORPHANED", "FLAG", th[0][0], th[0][1], "symbol %s was removed from non-test code but a surviving test still references it (%d ref(s))" % (s, len(th)), th[0][2]))


# ---------------------------------------------------------------------------------------------------------------- A_MOCK_ONLY
MOCK_CTORS = {"MagicMock", "Mock", "AsyncMock", "NonCallableMock", "PropertyMock", "create_autospec"}


def _root(node):
    while isinstance(node, (ast.Attribute, ast.Call, ast.Subscript)):
        node = node.value if not isinstance(node, ast.Call) else node.func
    return node.id if isinstance(node, ast.Name) else None


def _cname(call):
    f = call.func if isinstance(call, ast.Call) else None
    return (f.attr if isinstance(f, ast.Attribute) else f.id if isinstance(f, ast.Name) else None)


def mock_only_tests(src):
    """-> [(lineno, name, direct)] python test functions whose only assertions are mock call-recorders on mocks created in that test."""
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError):
        return []
    res = []
    for fn in ast.walk(tree):
        if not isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) or not fn.name.startswith("test"):
            continue
        mocks = set()
        npatch = sum(1 for d in fn.decorator_list if "patch" in ast.dump(d)[:120] and isinstance(d, ast.Call))
        args = [a.arg for a in fn.args.args if a.arg not in ("self", "cls")]
        mocks.update(args[:npatch])
        for node in ast.walk(fn):
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call) and _cname(node.value) in MOCK_CTORS:
                for t in node.targets:
                    if isinstance(t, ast.Name):
                        mocks.add(t.id)
            if isinstance(node, (ast.With, ast.AsyncWith)):
                for it in node.items:
                    if isinstance(it.context_expr, ast.Call) and "patch" in (_cname(it.context_expr) or "") and isinstance(it.optional_vars, ast.Name):
                        mocks.add(it.optional_vars.id)
        if not mocks:
            continue
        mock_as, real_as = 0, 0
        for node in ast.walk(fn):
            if isinstance(node, ast.Assert):
                t = node.test
                names = {_root(n) for n in ast.walk(t) if isinstance(n, (ast.Attribute, ast.Name))}
                recorders = any(isinstance(n, ast.Attribute) and n.attr in ("call_count", "called", "call_args", "call_args_list", "await_count", "mock_calls") for n in ast.walk(t))
                if recorders and names & mocks and names <= (mocks | {None}):
                    mock_as += 1
                else:
                    real_as += 1
            elif isinstance(node, ast.Call):
                f = node.func
                if isinstance(f, ast.Attribute) and (f.attr.startswith("assert") or f.attr in ("fail",)):
                    if f.attr.startswith("assert_") and _root(f.value) in mocks:
                        mock_as += 1
                    elif f.attr.startswith("assert_") and re.match(r"assert_(called|not_called|awaited|any_call|has_calls)", f.attr):
                        mock_as += 1  # chained recorder on something we cannot trace to a non-mock
                    else:
                        real_as += 1
                elif (isinstance(f, ast.Attribute) and f.attr == "raises") or (isinstance(f, ast.Name) and f.id in ("raises",)):
                    real_as += 1
            elif isinstance(node, (ast.With, ast.AsyncWith)):
                for it in node.items:
                    ce = it.context_expr
                    if isinstance(ce, ast.Call) and _cname(ce) in ("raises", "assertRaises", "warns"):
                        real_as += 1
        if mock_as and not real_as:
            direct = any(isinstance(n, ast.Expr) and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name) and n.value.func.id in mocks for n in ast.walk(fn))
            res.append((fn.lineno, fn.name, direct))
    return res


def rule_mock_only(repo, status, diffs, out):
    n = 0
    for path, st in status.items():
        if _lang(path) != "py" or st not in ("A", "M", "R") or not _is_test(path) or path not in diffs or n >= 10:
            continue
        txt = repo.blob(repo.head, path)
        if not txt:
            continue
        added = {a for a, _ in diffs[path].added}
        try:
            tree = ast.parse(txt)
        except (SyntaxError, ValueError):
            continue
        spans = {}
        for fn in ast.walk(tree):
            if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
                spans[fn.lineno] = getattr(fn, "end_lineno", fn.lineno)
        for ln, name, direct in mock_only_tests(txt):
            if any(ln <= a <= spans.get(ln, ln) for a in added):
                n += 1
                out.append(_F("A_MOCK_ONLY", "FLAG", path, ln, "test %s asserts only mock call-recording on a mock created in the test%s: it cannot fail on product behaviour" % (
                    name, " (the test itself calls the mock)" if direct else ""), name))


# ---------------------------------------------------------------------------------------------------------------- A_MIRROR_EXPECTED
BUILTIN_CALLS = {"Vector2", "Vector2i", "Vector3", "Color", "float", "int", "str", "abs", "sqrt", "floor", "ceil", "round", "max", "min", "clamp", "len",
                 "Array", "Dictionary", "snappedf", "pow", "absf", "maxf", "minf", "clampf", "roundi", "floori", "ceili", "lerp", "is_equal_approx",
                 "String", "bool", "range", "typeof", "PackedStringArray", "Rect2", "Rect2i", "sign", "signf"}
GUT_EQ = re.compile(r"^\s*(assert_eq|assert_almost_eq|assert_eq_deep|assert_almost_ne|assert_ne|assert_gt|assert_lt|assert_ge|assert_le)\s*\((.*)\)\s*$")


def _split_args(s):
    out, depth, cur, q = [], 0, "", None
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
            continue
        if ch in "\"'":
            q = ch
            cur += ch
        elif ch in "([{":
            depth += 1
            cur += ch
        elif ch in ")]}":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def _calls(expr):
    """{normalised call text} of non-builtin calls in `expr` (callee + args, outermost and nested)."""
    res = set()
    for m in re.finditer(r"([A-Za-z_][\w.]*)\s*\(", expr):
        if m.group(1).split(".")[-1] in BUILTIN_CALLS:
            continue
        depth, i = 0, m.end() - 1
        for j in range(i, len(expr)):
            if expr[j] == "(":
                depth += 1
            elif expr[j] == ")":
                depth -= 1
                if depth == 0:
                    res.add(re.sub(r"\s+", "", expr[m.start():j + 1]))
                    break
    return res


def mirror_expected_asserts(src):
    """-> [(lineno, assertion_text)] GUT assertions whose expected arg mirrors the actual arg's call on the same input."""
    res = []
    funcs = re.split(r"(?m)^(?=(?:static\s+)?func\s)", src)
    line_no = 1
    for chunk in funcs:
        if not re.match(r"(?:static\s+)?func\s+test_", chunk):
            line_no += chunk.count("\n")
            continue
        assigns = {}
        for i, ln in enumerate(chunk.split("\n")):
            m = re.match(r"\s*(?:var\s+)?([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?(?::=|=)\s*(.+)$", ln)
            if m and "(" in m.group(2) and not ln.lstrip().startswith("assert"):
                assigns[m.group(1)] = m.group(2).strip()
            elif m and not ln.lstrip().startswith("assert"):
                assigns.pop(m.group(1), None)
            a = GUT_EQ.match(ln)
            if not a:
                continue
            args = _split_args(a.group(2))
            if len(args) < 2:
                continue

            def resolve(e):
                e = e.strip()
                return assigns.get(e, e) if re.fullmatch(r"[A-Za-z_]\w*", e) else e
            act, exp = resolve(args[0]), resolve(args[1])
            ca, ce = _calls(act), _calls(exp)
            if ca and ce and (ca & ce):
                res.append((line_no + i, ln.strip()[:120]))
        line_no += chunk.count("\n")
    return res


def rule_mirror_expected(repo, status, diffs, out):
    n = 0
    for path, st in status.items():
        if _lang(path) != "gd" or st not in ("A", "M", "R") or not _is_test(path) or path not in diffs or n >= 10:
            continue
        txt = repo.blob(repo.head, path)
        if not txt:
            continue
        added = {a for a, _ in diffs[path].added}
        for ln, text in mirror_expected_asserts(txt):
            if ln in added:
                n += 1
                out.append(_F("A_MIRROR_EXPECTED", "FLAG", path, ln, "expected value is computed by calling the function under test on the same input as the actual value", text))


# ---------------------------------------------------------------------------------------------------------------- entry
def run_all(repo, repo_name, status, st_raw, diffs, findings, notes, deadline, no_record):
    """Run every h13 rule; each is isolated. Returns the frozen-path state string. `st_raw` carries '\\0old:<new>' -> old path for renames."""
    st_old = {k[5:]: v for k, v in st_raw.items() if k.startswith("\0old:")}
    frozen = "NA"
    steps = [("frozen_paths", lambda: rule_frozen_paths(repo_name, status, st_old, findings)),
             ("dead_symbol", lambda: rule_dead_symbol(repo, status, diffs, findings, deadline)),
             ("test_not_collected", lambda: rule_test_not_collected(repo, repo_name, status, diffs, findings)),
             ("revert_of_recent", lambda: rule_revert_of_recent(repo, repo_name, status, diffs, findings, deadline, no_record)),
             ("deleted_live", lambda: rule_deleted_live(repo, status, findings, deadline)),
             ("test_orphaned", lambda: rule_test_orphaned(repo, diffs, findings, deadline)),
             ("mock_only", lambda: rule_mock_only(repo, status, diffs, findings)),
             ("mirror_expected", lambda: rule_mirror_expected(repo, status, diffs, findings))]
    for name, fn in steps:
        if time.time() > deadline and name != "frozen_paths":
            notes.append("h13 rules skipped from %s (deadline)" % name)
            break
        try:
            r = fn()
            if name == "frozen_paths":
                frozen = r
        except Exception as ex:  # noqa: BLE001 - a rule bug must never change the verdict
            notes.append("h13 rule %s errored: %s: %s" % (name, type(ex).__name__, str(ex)[:80]))
    return frozen
