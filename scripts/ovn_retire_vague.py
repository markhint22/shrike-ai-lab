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
import re, sys, os
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
    return False

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

def classify(line):
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
            return "dead-path"
    return None  # keep

LAST_GONE = [0]

def process(path):
    LAST_GONE[0] = 0
    if not os.path.exists(path):
        return (0, 0)
    lines = open(path).read().splitlines()
    out, vague, dead, gone = [], [], [], []
    for ln in lines:
        cls = classify(ln) if ln.startswith("- [ ]") else None
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
