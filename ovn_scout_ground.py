#!/usr/bin/env python3
"""ovn_scout_ground.py - ground the scout's planned files against the repo (2026-10-02, harness Y2).

The scout is told to name "existing repo file paths", but nothing checked that they exist: the old 'ungrounded-plan' short-circuit only fires when the
reply has ZERO file-shaped tokens, so any path-SHAPED fiction sailed through (logs 2026-10-02: 'ssrf' vs the real url_safety.py, a hallucinated
billwatch file 'billwatch-backend/app/core/auth.py' whose real home is app/routers/auth.py, wrong module paths for ActiveStreamSession...). The model
then edits a file it was never shown, or asks for it, and the cycle is wasted.

usage: ovn_scout_ground.py <repo_root> <scout_task_log> <item_text_file> [max_bytes=120000]
stdout (tab separated, one decision per line):
  KEEP<TAB><path>                  planned file exists
  NEW<TAB><path>                   does not exist but the ITEM TEXT names it (an author-sanctioned new file) - kept
  SUBST<TAB><planned><TAB><real>   planned path does not exist; exactly one real file matches (path suffix, same basename, or a close basename)
  DROP<TAB><path><TAB><reason>     no such file / ambiguous match - not force-loaded
  ADD<TAB><path><TAB><reason>      symbol resolution: the item names a function/class the scout did not plan; its defining file (or nearest test)
  UNGROUNDED<TAB><reason>          the scout listed files and not one of them is workable (caller no-ops when nothing else is loaded either)

Symbol resolution (only when the scout planned at least one workable file - a fabricated/empty plan is never "rescued"): names in the item text (path
tokens removed first) are looked up as `def X` / `class X` / `fun X` / `func X` / `function X` definitions in tracked, non-test source files. Only
identifiers in a CODE context count: in backticks, called (`name(`), after def/class/fn/function, CamelCase, or a bare snake_case name with >= 3
parts (get_current_user) that is defined in EXACTLY ONE file; ordinary two-part prose words (rate_limit, user_id, last_event) never pull a file in. A symbol defined in 1-2 files adds those files (and, per added file, the nearest
existing test file) unless the scout already planned them. Bounded: at most OVN_SCOUT_MAX_EXTRA (6) extra files, each <= max_bytes, together
<= OVN_SCOUT_EXTRA_TOTAL_BYTES (default 120000) AND planned + extras <= OVN_SCOUT_TOTAL_BYTES (default 160000, so the whole force-loaded set cannot
overflow the model context: lowest-priority extras - tests, then bare-name definitions - are dropped first), never a hard-banned file
(same banned_list/size rule as the scout guard in ovn_park_unworkable.py).

Fixture grounding (2026-11-07, Z2; OVN_SCOUT_FIXTURES=off disables): when the item involves a test that needs DB fixtures (the planned/named test
touches db_session/fixture/model words, or a loaded file is a SQLAlchemy model), the model files the test must construct rows from are ALSO loaded:
the files defining the `ForeignKey("<table>.<col>")` / `relationship("<Class>")` parents of every loaded model, the model classes the item text / test
names, and the nearest + parent `conftest.py` of the test. Evidence (2026-11-06/07): billwatch test_bill_chat_filter_cap.py failed ~12 rows / 2.5h on
`users.password_hash NOT NULL`, `'username' is an invalid keyword argument for User`, `bills.congress_number NOT NULL` because only bill_chat.py was loaded;
gitlark control_plane tests inserted `Workspace(id='<str>')` (UUID column) and mis-mocked async sessions. Same bounds as symbol resolution (shared
OVN_SCOUT_MAX_EXTRA count + byte budgets), admitted AFTER the symbol extras so they never displace them.
"""
import difflib
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import ovn_park_unworkable as _park  # same banned_list / _check as the scout guard
except Exception:  # pragma: no cover - guard module missing: ground without the ban check
    _park = None

PATH_RE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}")
FILEISH_RE = re.compile(r"/|\.(py|ts|tsx|js|jsx|vue|gd|kt|java|go|rb|rs|c|cpp|h|hpp|ya?ml|json|toml|cfg|ini|sh|txt|xml|gradle|properties|swift)$")
SRC_EXT = (".py", ".ts", ".tsx", ".js", ".jsx", ".vue", ".gd", ".kt", ".swift", ".java")
VENDOR_RE = re.compile(r"(^|/)(node_modules|\.venv|venv|site-packages|__pycache__|build|dist|\.git|Pods|alembic/versions)/")
TEST_RE = re.compile(r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]+$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$")
CAMEL_RE = re.compile(r"\b[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+\b")
SNAKE_RE = re.compile(r"\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b")
CREATE_RE = re.compile(r"\bcreate\b|\badd (a|an|this) new\b|\bnew (module|helper|component|service|class|function|method|endpoint|schema|model|utility|util|file)\b"
                       r"|\bwrite (only )?a new\b|\bimplement a new\b|\bscaffold\b|\(NEW\)|\bNEW\b", re.I)
DEF_MODS = r"(?:(?:export|public|private|protected|internal|static|override|open|suspend|async|final|abstract|data|sealed|default|inline)\s+)*"


def tracked_files(root):
    try:
        out = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, timeout=30)
        if out.returncode == 0 and out.stdout.strip():
            return [f for f in out.stdout.split("\n") if f]
    except Exception:
        pass
    res = []
    for d, dns, fns in os.walk(root):
        dns[:] = [x for x in dns if x not in (".git", "node_modules", ".venv", "venv", "__pycache__")]
        for fn in fns:
            res.append(os.path.relpath(os.path.join(d, fn), root))
    return res


def scout_files_list(log_text):
    """Tokens of the model's own 'FILES:' answer (the LAST one: earlier occurrences are the prompt echo), wrap-tolerant."""
    ms = list(re.finditer(r"FILES:[ \t]*", log_text, re.I))
    if not ms:
        return []
    seg = log_text[ms[-1].end():]
    m = re.search(r"\n[ \t]*\n|Tokens:|Applied edit|VERDICT:|PLAN:", seg, re.I)
    if m:
        seg = seg[: m.start()]
    seen, out = set(), []
    for tok in PATH_RE.findall(seg):
        if tok.startswith("./"):
            tok = tok[2:]
        if tok.endswith(".md") or not FILEISH_RE.search(tok) or tok in seen:
            continue
        seen.add(tok)
        out.append(tok)
    return out


def _dir_overlap(a, b):
    """number of trailing directory components shared by two paths (higher = nearer)."""
    da, db = os.path.dirname(a).split("/"), os.path.dirname(b).split("/")
    n = 0
    for x, y in zip(reversed(da), reversed(db)):
        if x != y:
            break
        n += 1
    return n


def resolve_planned(tok, files, fileset, by_base, item_text, root="."):
    """-> ("KEEP"|"NEW"|"SUBST"|"DROP", detail)"""
    if tok in fileset or os.path.isfile(os.path.join(root, tok)):
        return "KEEP", tok
    base = os.path.basename(tok)
    if tok in item_text or (base in item_text and "/" not in tok):
        return "NEW", tok  # the item author named it: a sanctioned new file
    parent = os.path.dirname(tok)
    parent_ok = (not parent) or os.path.isdir(os.path.join(root, parent)) or any(f.startswith(parent + "/") for f in files)
    if TEST_RE.search(tok) and parent_ok:
        return "NEW", tok  # a new test file in an existing tests dir is what "add a test" items legitimately produce
    # 1) path-suffix match: the scout dropped or invented a leading directory (app/models/x.py vs iptv-backend/app/models/x.py)
    suff = [f for f in files if f.endswith("/" + tok)]
    if len(suff) == 1:
        return "SUBST", suff[0]
    if len(suff) > 1:
        return "DROP", "ambiguous: " + ", ".join(sorted(suff)[:3])
    # 2) same basename elsewhere
    same = by_base.get(base, [])
    if len(same) == 1:
        return "SUBST", same[0]
    if len(same) > 1:
        ranked = sorted(same, key=lambda f: -_dir_overlap(tok, f))
        if _dir_overlap(tok, ranked[0]) > _dir_overlap(tok, ranked[1]):
            return "SUBST", ranked[0]
        return "DROP", "ambiguous: " + ", ".join(sorted(same)[:3])
    # 3) the item asks for a NEW file and its directory exists: a creation target, not a fiction
    if CREATE_RE.search(item_text) and parent_ok and parent:
        return "NEW", tok
    # 4) close basename with the same extension (typo / near-miss: user_service.py vs users_service.py)
    ext = os.path.splitext(base)[1]
    pool = [b for b in by_base if os.path.splitext(b)[1] == ext]
    close = difflib.get_close_matches(base, pool, n=3, cutoff=0.85)
    if len(close) == 1 and len(by_base[close[0]]) == 1:
        return "SUBST", by_base[close[0]][0]
    if close:
        cands = sorted({f for c in close for f in by_base[c]})
        return "DROP", "ambiguous: " + ", ".join(cands[:3])
    return "DROP", "no such file in the repo (fictional path)"


BACKTICK_RE = re.compile(r"`([A-Za-z_][A-Za-z0-9_.]*)(?:\(\))?`")
CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\(")
DEFWORD_RE = re.compile(r"\b(?:def|class|fn|func|fun|function)\s+([A-Za-z_][A-Za-z0-9_]*)")


def item_symbols(item_text):
    """{symbol: strong} - strong=True: the item names it in a code context (backticks, call, def/class word, CamelCase); False: a bare snake_case
    name with >= 3 parts, which is only trusted when it is defined in exactly one file (see ground())."""
    body = PATH_RE.sub(" ", item_text)
    syms = {}

    def add(s, strong, minlen):
        if len(s) >= minlen and not s.startswith(("test_", "cat_")) and not s.startswith("__"):
            syms[s] = syms.get(s, False) or strong

    for rx in (BACKTICK_RE,):
        for m in rx.finditer(body):
            for part in m.group(1).split("."):
                add(part, True, 4)
    for m in DEFWORD_RE.finditer(body):
        add(m.group(1), True, 4)
    for m in CALL_RE.finditer(body):
        add(m.group(1), True, 6)
    for m in CAMEL_RE.finditer(body):
        add(m.group(0), True, 6)
    for m in SNAKE_RE.finditer(body):
        tok = m.group(0)
        if tok.count("_") >= 2:  # a two-part snake word (rate_limit, user_id) is as likely prose as code
            add(tok, False, 6)
    return syms


def find_definitions(root, files, syms, max_read=400000):
    """{symbol: [files]} for tracked non-test source files defining the symbol."""
    if not syms:
        return {}
    rx = re.compile(r"^[ \t]*" + DEF_MODS + r"(?:def|class|fun|func|function)\s+(" + "|".join(re.escape(s) for s in sorted(syms)) + r")\b", re.M)
    found = {}
    for f in files:
        if not f.endswith(SRC_EXT) or VENDOR_RE.search(f) or TEST_RE.search(f):
            continue
        try:
            if os.path.getsize(os.path.join(root, f)) > max_read:
                continue
            txt = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in rx.finditer(txt):
            lst = found.setdefault(m.group(1), [])
            if f not in lst:
                lst.append(f)
    return found


def nearest_test(def_file, files):
    stem = os.path.splitext(os.path.basename(def_file))[0]
    pats = (re.compile(r"(^|/)test_%s\.[a-z]+$" % re.escape(stem)), re.compile(r"(^|/)%s_test\.[a-z]+$" % re.escape(stem)),
            re.compile(r"(^|/)%s\.(test|spec)\.[a-z]+$" % re.escape(stem)))
    cands = [f for f in files if any(p.search(f) for p in pats) and not VENDOR_RE.search(f)]
    if not cands:
        return None
    return sorted(cands, key=lambda f: (-_dir_overlap(def_file, f), len(f), f))[0]


# ---- fixture grounding (Z2) ------------------------------------------------------------------------------------------------------------------
DB_HINT_RE = re.compile(r"\b(db_session|async_session|AsyncSession|sessionmaker|sqlalchemy|SQLAlchemy|session\.(add|commit|execute|query)|create_all|conftest|fixtures?|"
                        r"database|persist(?:ed|s)?|foreign[ _]key|rows?|db)\b|\bdb_[a-z]+\b|\bmodels?\b", re.I)
FK_RE = re.compile(r"ForeignKey\(\s*[\"']([A-Za-z_][\w.]*)[\"']")
REL_RE = re.compile(r"relationship\(\s*[\"']([A-Za-z_]\w*)[\"']")
CLASS_RE = re.compile(r"^class\s+([A-Za-z_]\w*)\s*\(", re.M)
TABLE_RE = re.compile(r"__tablename__\s*=\s*[\"']([A-Za-z_]\w*)[\"']")
CAPWORD_RE = re.compile(r"\b[A-Z][A-Za-z0-9]{2,}\b")


def _read(root, path, limit=400000):
    try:
        if os.path.getsize(os.path.join(root, path)) > limit:
            return ""
        return open(os.path.join(root, path), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def model_index(root, files):
    """({table: file}, {Class: file}, {file: text}) over tracked non-test .py files that declare a SQLAlchemy `__tablename__`."""
    tables, classes, texts = {}, {}, {}
    for f in files:
        if not f.endswith(".py") or VENDOR_RE.search(f) or TEST_RE.search(f):
            continue
        txt = _read(root, f)
        if "__tablename__" not in txt and "ForeignKey(" not in txt:
            continue
        texts[f] = txt
        cms = list(CLASS_RE.finditer(txt))
        for i, m in enumerate(cms):
            seg = txt[m.end(): cms[i + 1].start() if i + 1 < len(cms) else len(txt)]
            tm = TABLE_RE.search(seg)
            if tm:
                classes.setdefault(m.group(1), f)
                tables.setdefault(tm.group(1), f)
    return tables, classes, texts


def fixture_candidates(root, files, workable, item_text):
    """[(priority, path, why)] model parents / named models / conftest files that a DB-fixture test needs (see the module docstring); [] when not needed."""
    fileset = set(files)
    tests = [w for w in workable if TEST_RE.search(w)]
    for tok in PATH_RE.findall(item_text):
        tok = tok[2:] if tok.startswith("./") else tok
        if TEST_RE.search(tok) and tok.endswith(SRC_EXT) and tok not in tests:
            tests.append(tok)
    if not tests:
        return []
    tables, classes, mtexts = model_index(root, files)
    loaded_models = [w for w in workable if w in mtexts]
    test_txt = "\n".join(_read(root, t) for t in tests if t in fileset)
    needs = bool(loaded_models) or bool(DB_HINT_RE.search(item_text)) or bool(DB_HINT_RE.search(test_txt))
    if not needs:
        return []
    cands = []
    seeds = list(loaded_models)
    seen_p = set()
    # 1) FK / relationship parents of every loaded model, transitively one more hop is NOT followed (bounded)
    for mf in seeds:
        txt = mtexts[mf]
        for tgt in FK_RE.findall(txt):
            tbl = tgt.rsplit(".", 1)[0].split(".")[-1]
            pf = tables.get(tbl)
            if pf and pf != mf and pf not in seen_p:
                seen_p.add(pf); cands.append((1.5, pf, "fixture: defines table `%s`, ForeignKey parent of %s" % (tbl, mf)))
        for cls in REL_RE.findall(txt):
            pf = classes.get(cls)
            if pf and pf != mf and pf not in seen_p:
                seen_p.add(pf); cands.append((1.5, pf, "fixture: defines `%s`, relationship parent of %s" % (cls, mf)))
    # 2) nearest + parent conftest.py of each test target
    for t in tests:
        d, found = os.path.dirname(t), 0
        while found < 2:
            cf = (d + "/conftest.py") if d else "conftest.py"
            if cf in fileset and cf not in seen_p:
                seen_p.add(cf); cands.append((1.6, cf, "fixture: %s conftest.py of %s" % ("nearest" if found == 0 else "parent", t))); found += 1
            elif cf in fileset:
                found += 1
            if not d:
                break
            d = os.path.dirname(d)
    # 3) model classes the item / test names (User, Bill, Workspace): at most 3, defined in exactly the indexed model files
    named = 0
    for w in CAPWORD_RE.findall(item_text + "\n" + test_txt):
        pf = classes.get(w)
        if pf and pf not in seen_p and pf not in workable and named < 3:
            seen_p.add(pf); named += 1; cands.append((1.7, pf, "fixture: defines model `%s` named by the item/test" % w))
    return cands


def ground(root, log_text, item_text, max_bytes=120000, max_extra=6, extra_total=120000, total_budget=160000):
    files = tracked_files(root)
    fileset = set(files)
    by_base = {}
    for f in files:
        by_base.setdefault(os.path.basename(f), []).append(f)
    banned = _park.banned_list(root) if _park else []

    def too_big_or_banned(path):
        if _park:
            return _park._check(path, root, banned, max_bytes)
        try:
            return "too big" if os.path.getsize(os.path.join(root, path)) > max_bytes else None
        except OSError:
            return None

    out = []
    planned = scout_files_list(log_text)
    workable = []  # files that will be loaded / created
    for tok in planned:
        kind, detail = resolve_planned(tok, files, fileset, by_base, item_text, root)
        if kind == "KEEP":
            out.append(("KEEP", tok)); workable.append(tok)
        elif kind == "NEW":
            out.append(("NEW", tok)); workable.append(tok)
        elif kind == "SUBST":
            why = too_big_or_banned(detail)
            if why:
                out.append(("DROP", tok, "substitute %s rejected: %s" % (detail, why)))
            else:
                out.append(("SUBST", tok, detail)); workable.append(detail)
        else:
            out.append(("DROP", tok, detail))

    # symbol resolution - bounded, scout-omitted definitions only
    # only when the scout's plan is itself grounded (it planned >= 1 workable file): a plan with NO usable file (FILES: NONE, an invented plan like
    # aider's is_prime/sympy few-shot, or all-fictional files) must still reach the ungrounded-plan / scout-ungrounded guards, not be "rescued" into
    # an implement run on top of fabricated plan text.
    def fsize(path):
        try:
            return os.path.getsize(os.path.join(root, path))
        except OSError:
            return 0

    planned_bytes = sum(fsize(w) for w in workable)
    symmap = item_symbols(item_text) if workable else {}
    defs = find_definitions(root, files, set(symmap)) if symmap else {}
    already = set(workable)
    # candidates: (priority, order, path, why, parent def file or None). priority 0 = a definition named in a code context, 1 = a bare snake_case
    # definition, 2/3 = the nearest test of one of those. Lowest priority (highest number) is dropped first when the budget is short.
    cands, order = [], 0
    for sym in sorted(defs):
        dfiles = defs[sym]
        strong = symmap.get(sym, False)
        if len(dfiles) > 2 or any(d in already for d in dfiles):
            continue  # generic name defined everywhere, or the scout already planned a definition
        if not strong and len(dfiles) != 1:
            continue  # a bare prose-shaped name must match exactly one definition
        for d in dfiles:
            cands.append((0 if strong else 1, order, d, "defines `%s` named in the item" % sym, None)); order += 1
            t = nearest_test(d, files)
            if t and t not in already:
                cands.append((2 if strong else 3, order, t, "nearest existing test file of %s" % d, d)); order += 1
    extras, extra_bytes = [], 0
    budget_left = max(0, min(extra_total, total_budget - planned_bytes))
    admitted = set()
    for prio, _o, path, why, parent in sorted(cands):
        if path in already or path in admitted or len(extras) >= max_extra:
            continue
        if parent is not None and parent not in admitted:
            continue  # the definition it tests was not admitted
        if too_big_or_banned(path):
            continue
        sz = fsize(path)
        if extra_bytes + sz > budget_left:
            continue
        extras.append((path, why)); admitted.add(path); extra_bytes += sz
    for path, why in extras:
        out.append(("ADD", path, why)); workable.append(path)

    # fixture grounding (Z2): AFTER the symbol extras so it never displaces them; shares the extra-file count and both byte budgets
    if workable and os.environ.get("OVN_SCOUT_FIXTURES", "on") != "off":
        added_bytes = 0
        for _prio, path, why in sorted(fixture_candidates(root, files, workable, item_text)):
            if path in workable or len(extras) >= max_extra or too_big_or_banned(path):
                continue
            sz = fsize(path)
            if extra_bytes + sz > budget_left:
                continue
            extras.append((path, why)); extra_bytes += sz; added_bytes += sz
            out.append(("ADD", path, why)); workable.append(path)
        if added_bytes:
            sys.stderr.write("--- scout-grounding fixtures: +%d file(s), +%d bytes (~%d tokens) ---\n" % (len([1 for r in out if r[0] == "ADD" and r[2].startswith("fixture:")]), added_bytes, added_bytes // 4))

    if planned and not workable:
        out.append(("UNGROUNDED", "every planned file is fictional/ambiguous (%s)" % ", ".join(planned[:4])))
    return out


def main():
    root, log, item_file = sys.argv[1], sys.argv[2], sys.argv[3]
    max_bytes = int(sys.argv[4]) if len(sys.argv) > 4 else 120000
    try:
        log_text = open(log, encoding="utf-8", errors="replace").read()
    except OSError:
        return
    try:
        item_text = open(item_file, encoding="utf-8", errors="replace").read()
    except OSError:
        item_text = ""
    max_extra = int(os.environ.get("OVN_SCOUT_MAX_EXTRA", "6"))
    extra_total = int(os.environ.get("OVN_SCOUT_EXTRA_TOTAL_BYTES", "120000"))
    total_budget = int(os.environ.get("OVN_SCOUT_TOTAL_BYTES", "160000"))
    for row in ground(root, log_text, item_text, max_bytes, max_extra, extra_total, total_budget):
        print("\t".join(row))


if __name__ == "__main__":
    main()
