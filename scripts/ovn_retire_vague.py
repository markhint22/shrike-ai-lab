#!/usr/bin/env python3
# Pre-cycle sanitizer (run from the repo root). Retires unchecked items the
# scout can never complete, so they stop no-op'ing every cycle forever:
#   (1) VAGUE   - names no file at all -> the file-loading loop has nothing to
#                 open -> no-op(BLOCKED).
#   (2) DEAD-PATH - every explicit relative path it names is MISSING from THIS
#                 clone (e.g. a refill generated against a Mac clone that is tens
#                 of commits behind the server's overnight/feature, where the
#                 file was renamed/moved: shrike's src/pages/PrivacyPage.vue is
#                 actually src/pages/Privacy.vue here). The force-load correctly
#                 refuses a non-existent file, so the model flails on a file it
#                 can never open -> no-op forever.
# Conservative: an item is only DEAD-PATH if it gives one-or-more slash paths AND
# NONE of them exist. An item with at least one existing named file is kept.
import re, sys, os, subprocess
# 2026-10-09: Godot sidecar files. `loadout_preset.gd.uid` used to match as `loadout_preset.gd` (the regex stopped at `.gd` because \b holds before the
# next `.`), so five valid "Delete the orphaned file ...gd.uid" items were classified dead-path - that .gd is gone by definition, only the .uid is left
# - and retired. The compound `<ext>.uid` forms MUST precede their bare extension (alternation order), and .tscn/.tres are real scene/resource files.
# (A bare `uid` extension is deliberately NOT added: it would turn prose like `user.uid` into a "file", keeping vague items alive.)
EXT = r"(gd\.uid|tscn\.uid|tres\.uid|gdshader\.uid|py|vue|ts|tsx|js|jsx|kts|kt|gd|tscn|tres|swift|gradle|toml|ya?ml|json|cfg|ini|sh|html|css|md|txt|env)"
# "names a file" REQUIRES a real code extension. An earlier version also treated
# any word/word as a path (HAS_PATH), which false-matched prose like "empty/zero
# result" / "and/or" / "input/output" and kept genuinely-vague items forever
# (billwatch "A service module: ... `if cached:`" no-op'd every cycle). Extension
# required, so prose slashes no longer count as a file reference.
HAS_FILE  = re.compile(r"[A-Za-z0-9_./-]+\." + EXT + r"\b")
# a relative path with a slash AND a known code extension -> existence-checkable
SLASH_FILE = re.compile(r"[A-Za-z0-9_.-]*/[A-Za-z0-9_./-]*\." + EXT + r"\b")
SKIP      = re.compile(r"human|HUMAN|AUTO-SKIP|decision|DELETE:|\(retired-", re.I)
# A file-CREATION item legitimately names a path that does not exist yet.
# 2026-09-25 FIX: this vocabulary was too narrow and silently ate real, correctly-
# authored creation items across the fleet - confirmed live on gitlark: "Add a new
# minimal, dismissible banner component using useOtaUpdate()..." matched NONE of the
# old phrases (not "create", not "new pure/module/helper", not a pytest/vitest/test
# file), got retired as (retired-dead-path), and the sibling item that mounted the
# component (a separate, already-landed commit) shipped a production build error
# (Could not resolve OtaUpdateBanner.vue) that blocked branch_hygiene entirely until
# fixed by hand. A fleet-wide audit of the 653 existing (retired-dead-path) items
# found ~7% (46) match an explicit creation-intent signal the old regex missed -
# almost entirely the very common "Add a new <noun> <thing>" phrasing, or the
# fleet's own "(NEW)"/"NEW <path>" convention (used across gitlark/iptv_apps/
# billwatch/test-automation-agent as an explicit "this doesn't exist yet" marker,
# never recognized here). Broadened to: any "add a/an/this new X" (not just
# pytest/vitest/test files), "new <component|service|class|function|method|
# endpoint|schema|model|util>", "write/implement a new", "scaffold", and the
# explicit ALL-CAPS "NEW"/"(NEW)" marker (checked case-sensitively - deliberately
# NOT matching everyday lowercase "new", which would be too broad and start
# keeping genuinely dead-path items open on prose coincidence).
CREATE_INTENT = re.compile(
    r"\bcreate\b"
    r"|does not exist yet"
    r"|\badd (a|an|this) new\b"
    r"|\bnew (pure|module|helper|component|service|class|function|method|endpoint|schema|model|utility|util)\b"
    r"|\bwrite (only )?a new\b"
    r"|\bimplement a new\b"
    r"|\bscaffold\b",
    re.I,
)
CREATE_INTENT_MARKER = re.compile(r"\(NEW\)|\bNEW\b")  # case-sensitive: the fleet's own deliberate ALL-CAPS "this is new" tag

def _has_create_intent(body):
    return bool(CREATE_INTENT.search(body) or CREATE_INTENT_MARKER.search(body))

# 2026-11-07 (package Z1): TEST-creation items. "`tests/x.py` - Add test verifying ..." names a test file that does not exist yet BY DEFINITION, but matched none of the
# CREATE_INTENT phrases above (no "create", no "add a new") so the sanitizer retired it as dead-path (366 retired in 24h); the sibling implementation items kept a VERIFY pointing at the
# never-created test file (pytest rc=4 "file or directory not found", landed-uncredited + ALREADY-DONE loops). A missing TEST-FILE path is therefore never dead when the item's own text
# (before its VERIFY clause) says add/write/create ... test(s), or when a sibling item of the same feature creates that path (see process()).
TEST_PATH = re.compile(
    r"(?:^|/)(?:tests?|__tests__|spec|specs)/"
    r"|(?:^|/)test_[^/]*$"
    r"|(?:^|/)[^/]*_test\.[A-Za-z]+$"
    r"|\.(?:test|spec)\.[A-Za-z]+$"
)
TEST_CODE_EXT = re.compile(r"\.(?:py|ts|tsx|js|jsx|mjs|kt|kts|swift|gd)$")

def _is_test_path(p):
    """a test FILE path: test-shaped AND a code extension AND not under docs/ (so `docs/spec/old.md` is a doc, never a test)"""
    return bool(TEST_PATH.search(p)) and bool(TEST_CODE_EXT.search(p)) and not re.search(r"(?:^|/)docs?/", p)

# review-fix (Z1 defect 2): the verb must DIRECTLY govern a test FILE/case as its object (only a few adjectives may sit between), so "Add a missing assertion to the existing test",
# "add a docstring to the test module", "Adding retries makes the tests stable" and "Implement caching so tests run faster" are NOT test-creation. ("implement" dropped as a verb.)
_TC_VERB = r"(?:add|adds|adding|write|writes|writing|create|creates|creating|author|introduce|introduces)"
_TC_MOD = (r"(?:(?:a|an|the|new|missing|failing|regression|unit|pytest|vitest|jest|gut|integration|e2e|focused|small|basic|minimal|dedicated|additional|more|some|\d+"
           r"|table[- ]driven|parametri[sz]ed|parameteri[sz]ed|edge[- ]cases?|boundary|happy[- ]path|negative|error[- ]path|async|snapshot|property[- ]based|component|api|end[- ]to[- ]end)\s+)*")
# Q (2026-11-10, retire_vague recall): a BACKTICKED test name (`Add `test_retry_budget` to tests/test_sync.py`) is a test-creation object too; the existing-guard below still applies.
_TC_OBJ = r"(?:(?:test\s+files?|test[ -]cases?|test[ -]suite|test[ -]module|unit[ -]tests?|tests|test|spec\s+files?|specs?)\b|`test_[A-Za-z0-9_]+(?:\(\))?`)"
_TC_NOT = (r"(?!\s+(?:cases?|files?|suite|module)\b)"   # the object matched only a PREFIX of `test case(s)` / `test file`: let the full alternative decide (so the existing-guard below applies to it)
           r"(?!\s+(?:plan|plans|docs?|documentation|runner|helpers?|fixtures?|run|runs|runtime|speed|stability|data|datas?|utils?|utilities|harness|infra|setup|config)\b)"
           # review r2: `Add a test case to <file>'s existing TestX class` modifies an EXISTING test (the named file is expected to exist): up to three words between the preposition and `existing`
           r"(?!\s+(?:to|in|into|for|of|on)\s+(?:[^\s]+\s+){0,3}?existing\b)")
TEST_CREATE_INTENT = re.compile(r"\b" + _TC_VERB + r"\s+" + _TC_MOD + _TC_OBJ + _TC_NOT, re.I)
FEAT_TAG = re.compile(r"\[feat:([^\]]+)\]")

def _head(body):
    """the item text before its VERIFY clause (the VERIFY names files to RUN, it is not the item's own statement of intent)"""
    return re.split(r"VERIFY:", body, maxsplit=1)[0]

def _head_slash_paths(head):
    return [m.group(0) for m in SLASH_FILE.finditer(head)]

def _test_creation_paths(body):
    """missing-test paths this item CREATES: test-file paths named in the item's own head (not its VERIFY) when the head has a test-creation phrase (verb directly governing a test file/case)"""
    head = _head(body)
    if not TEST_CREATE_INTENT.search(head):
        return set()
    return set(p for p in _head_slash_paths(head) if _is_test_path(p))

def _same_path(p, q):
    """review r2 (defect A): two spellings of one path: equal, or one is a `/`-suffix of the other (`backend/tests/t.py` vs `tests/t.py`, which is what a `cd backend &&` VERIFY says)"""
    p, q = p.lstrip("./"), q.lstrip("./")
    return p == q or p.endswith("/" + q) or q.endswith("/" + p)

def _excuse_spellings(paths, excused):
    """the paths of `paths` that are excused directly or only differ from an excused path by an app-root / `cd <dir>` prefix"""
    return set(p for p in paths if p in excused or any(_same_path(p, e) for e in excused))

def _test_creation(body, missing):
    """kept for callers/tests: True when some missing path is a test file this item creates"""
    return bool(set(missing) & _test_creation_paths(body))

# sibling "creates" a path only when the path is the object of the sibling's OWN create-intent head: the path directly follows a create verb / NEW marker, or is the item's FIRST
# named path (its primary target, `<path> - Create ...`) while the head carries a create-intent phrase; or it is a test file the sibling's head test-creates (_test_creation_paths).
# "Create new retry helper" does NOT make every other path the sibling names (dead or not) "created".
_CREATE_VERB_PATH = re.compile(
    r"(?:\bcreate[sd]?|\badd(?:s|ing)?(?:\s+(?:a|an|the))?\s+new|\bwrite(?:s)?(?:\s+a)?\s+new|\bscaffold|\bNEW|\bintroduce[s]?)\s+(?:file\s+|module\s+|component\s+)?`?(" + SLASH_FILE.pattern + r")"
)
_PATH_NEW_MARK = re.compile("(" + SLASH_FILE.pattern + r")`?\s*\(NEW\)")

def _creation_paths(line):
    """slash paths a still-open sibling item creates (see the rules above)"""
    body = line[len("- [ ]"):]
    head = _head(body)
    if SKIP.search(body):
        return set()
    out = set(_test_creation_paths(body))
    paths = _head_slash_paths(head)
    for m in _CREATE_VERB_PATH.finditer(head):
        out.add(m.group(1))
    for m in _PATH_NEW_MARK.finditer(head):
        out.add(m.group(1))
    if paths and _has_create_intent(head) and not out:
        out.add(paths[0])
    return out

# 2026-09-17: many items (and, critically, RAW PYTEST OUTPUT quoted verbatim
# into an item's text, e.g. "Failing: FAILED tests/test_broker.py::...") are
# authored/emitted relative to an app subdirectory (backend/, app/, src/,
# frontend/, web/, server/) rather than the true git repo root this sanitizer
# runs from. Missed here, this wrongly dead-paths REAL, currently-relevant
# items. Caught live: an EMERGENCY "pytest suite is RED" item on shrike-notify
# named "tests/test_broker.py::test_publish_suppresses_fanout_during_quiet_hours"
# (the real file is backend/tests/test_broker.py) got silently retired as
# dead-path instead of ever being triaged, burying a real, currently-failing
# test indefinitely.
APP_ROOT_PREFIXES = ("backend", "app", "src", "frontend", "web", "server")


# Q (2026-11-10): the repo's file list (tracked + untracked-not-ignored), cached per cwd, with a basename index. The sanitizer's `os.path.exists` + fixed app-root prefixes missed
# paths authored without a deeper prefix: 17 of 50 path mismatches were `tracked file ends with /<path>` (`tests/test_x.py` for `iptv-backend/tests/test_x.py`), ~33 more were a same-named
# test living in ANOTHER test dir. Suffix -> the path exists (never dead); same basename elsewhere -> a missing test path is a MISLOCATED duplicate, not a legitimate creation (see _mislocated_test).
_FILES = {}
_GENERIC_TEST_BASENAMES = ("conftest.py", "__init__.py")

def _repo_files():
    cwd = os.getcwd()
    if cwd not in _FILES:
        files = []
        try:
            r = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], capture_output=True, text=True, timeout=30)
            if r.returncode == 0:
                files = [f for f in r.stdout.split("\n") if f]
        except (OSError, subprocess.SubprocessError):
            files = []
        if not files:
            for root, dirs, fs in os.walk("."):
                dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv", "__pycache__")]
                files.extend(os.path.relpath(os.path.join(root, f), ".") for f in fs)
        by_base = {}
        for f in files:
            by_base.setdefault(f.rsplit("/", 1)[-1], []).append(f)
        _FILES[cwd] = by_base
    return _FILES[cwd]

def _suffix_exists(p):
    """a repo file whose path ends with `/<p>` (p authored without the app-dir prefix it really lives under)"""
    q = p.lstrip("./")
    return bool(q) and any(f.endswith("/" + q) for f in _repo_files().get(q.rsplit("/", 1)[-1], ()))

def _mislocated_test(p):
    """`p` (missing) is a test path whose basename already exists as a test file in ANOTHER dir: creating it is a duplicate at the wrong place, so the test-creation exemption does not excuse it"""
    q = p.lstrip("./")
    base = q.rsplit("/", 1)[-1]
    if not _is_test_path(q) or base in _GENERIC_TEST_BASENAMES:
        return False
    return any(f != q and not f.endswith("/" + q) and _is_test_path(f) for f in _repo_files().get(base, ()))

def _path_exists(p):
    # Tolerate a leading "<repo>/" prefix: items are sometimes authored with the
    # repo dir prepended (e.g. "xlite/scripts/foo.gd"), but the sanitizer runs
    # INSIDE the clone where the file is "scripts/foo.gd". Without this, every such
    # item is wrongly retired as dead-path (silently deleting valid work). Check the
    # literal path AND the path with its first component stripped.
    if os.path.exists(p):
        return True
    if "/" in p and os.path.exists(p.split("/", 1)[1]):
        return True
    # Try common one-level app-root prefixes before giving up (see note above).
    if any(os.path.exists(os.path.join(prefix, p)) for prefix in APP_ROOT_PREFIXES):
        return True
    return _suffix_exists(p)

# h13 (2026-10-04): an item whose own VERIFY is `test ! -f X` with X already absent is DONE (a delete item an earlier commit satisfied); left open it
# flails for cycles (xlite elevation.gd, 6 cycles). Only the bare single-path form is trusted.
GONE_VERIFY = re.compile(r"VERIFY:\s*(?:`\s*test\s+!\s+-[fe]\s+([A-Za-z0-9_./@-]+)\s*`|test\s+!\s+-[fe]\s+([A-Za-z0-9_./@-]+)\s*(?:\)|\.|,|\[feat:[^\]]*\]|\{[^}]*\}|$))")
# h13: a repo-level "run everything" item ("[T4] . - Execute full test suite ...", "[T4] tests - ...") names no concrete file TO CHANGE: the only
# file-shaped token is the tooling in its VERIFY (addons/gut/gut_cmdln.gd), so it passed the HAS_FILE test and then planned FILES: NONE forever.
BARE_TARGET = re.compile(r"^\s*(\[[^\]]*\]\s*)*`?(\.|\./|tests?|tests?/)`?(\s|$)")

def _already_gone(body):
    m = GONE_VERIFY.search(body)
    if not m:
        return False
    p = m.group(1) or m.group(2)
    if p.startswith("/") or ".." in p.split("/"):
        return False
    # review hardening: lexists (dangling symlink still there); also not present under the repo-prefix / app-root spellings _path_exists tolerates
    # (a mis-pathed VERIFY like `test ! -f xlite/scripts/x.gd` passes trivially while the real file stays); a bare name must not exist anywhere tracked
    if os.path.lexists(p) or _path_exists(p):
        return False
    if "/" not in p:
        for root, dirs, files in os.walk("."):
            dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv")]
            if p in files or p in dirs:
                return False
    return True

def classify(line, sibling_creates=None):
    """sibling_creates: {feat_tag: {path,...}} built by process() from the OTHER open items; None = no sibling knowledge (single-line callers)"""
    body = line[len("- [ ]"):]
    if SKIP.search(body):
        return None
    if _already_gone(body):
        return "gone"
    if not HAS_FILE.search(body) or (BARE_TARGET.match(body) and not HAS_FILE.search(re.split(r"VERIFY:", body)[0])):
        return "vague"
    slash_paths = set(m.group(0) for m in SLASH_FILE.finditer(body))
    if slash_paths:
        if _has_create_intent(body):
            return None  # create-new-file item: missing path is expected, not dead
        if not any(_path_exists(p) for p in slash_paths):
            # Z1: paths this item legitimately names before they exist: the test file(s) it creates (head only), and paths a sibling item of the same feature creates.
            # Anything else still missing (a dead non-test path listed beside a test path, docs/spec/*.md ...) keeps the item dead.
            made = set(p for p in _test_creation_paths(body) if not _mislocated_test(p))   # Q: a same-named test already lives in another test dir -> not a creation, a path mismatch
            if sibling_creates:
                m = FEAT_TAG.search(body)
                if m:
                    made |= sibling_creates.get(m.group(1), set())
            excused = _excuse_spellings(slash_paths, made)
            if not (set(slash_paths) - excused):
                return None
            return "dead-path"
    return None  # keep

LAST_GONE = [0]

def process(path):
    LAST_GONE[0] = 0
    if not os.path.exists(path):
        return (0, 0)
    lines = open(path).read().splitlines()
    out, vague, dead, gone = [], [], [], []
    # Z1: path -> creators among the OTHER open items of the same feature ([feat:] tag). Built per item below so an item never counts as its own sibling.
    by_feat = {}
    for i, ln in enumerate(lines):
        if ln.startswith("- [ ]"):
            m = FEAT_TAG.search(ln)
            cp = _creation_paths(ln) if (m and classify(ln, None) is None) else set()   # a sibling that itself gets retired (vague/gone/dead) must not shield
            if cp:
                by_feat.setdefault(m.group(1), []).append((i, cp))
    for i, ln in enumerate(lines):
        sib = None
        if ln.startswith("- [ ]"):
            m = FEAT_TAG.search(ln)
            if m and m.group(1) in by_feat:
                sib = {m.group(1): set().union(*[cp for j, cp in by_feat[m.group(1)] if j != i])}
        cls = classify(ln, sib) if ln.startswith("- [ ]") else None
        if cls == "vague":
            vague.append(ln[len("- [ ] "):])
        elif cls == "dead-path":
            dead.append(ln[len("- [ ] "):])
        elif cls == "gone":
            gone.append(ln[len("- [ ] "):])
        else:
            out.append(ln)
    if vague:
        out.append("")
        out.append("### Retired (vague - no named file; scout can't load a file it isn't given) auto-2026-08-30")
        for r in vague:
            out.append("- [x] (retired-vague) " + r)
    if dead:
        out.append("")
        out.append("### Retired (dead-path - every named file is missing from this clone; likely a stale-clone refill) auto-2026-08-30")
        for r in dead:
            out.append("- [x] (retired-dead-path) " + r)
    if gone:
        out.append("")
        out.append("### Credited (already-done - the item's own `test ! -f` VERIFY passes: the target is already absent) auto-2026-10-04")
        for r in gone:
            out.append("- [x] (already-done, target already absent) " + r)
    open(path, "w").write("\n".join(out) + "\n")
    LAST_GONE[0] = len(gone)   # process() keeps its 2-tuple contract (callers/tests unpack (vague, dead))
    return (len(vague), len(dead))

if __name__ == "__main__":
    tv = td = tg = 0
    for p in sys.argv[1:]:
        v, d = process(p)
        tg += LAST_GONE[0]
        if LAST_GONE[0]:
            print("  credited %d already-done (target absent) from %s" % (LAST_GONE[0], p))
        if v:
            print("  retired %d vague from %s" % (v, p))
        if d:
            print("  retired %d dead-path from %s" % (d, p))
        tv += v; td += d
    # keep the "retired N" line the runner greps on, covering both classes
    # h13: already-done credits are counted in the total (so the runner's `retired [1-9]` grep commits them) but the legacy format is unchanged when there are none
    print("  total retired: %d (vague=%d dead-path=%d%s)" % (tv + td + tg, tv, td, (" already-done=%d" % tg) if tg else ""))
