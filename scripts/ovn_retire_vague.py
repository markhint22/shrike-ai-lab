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
EXT = r"(py|vue|ts|tsx|js|jsx|kts|kt|gd|swift|gradle|toml|ya?ml|json|cfg|ini|sh|html|css|md|txt|env)"
# "names a file" REQUIRES a real code extension. An earlier version also treated
# any word/word as a path (HAS_PATH), which false-matched prose like "empty/zero
# result" / "and/or" / "input/output" and kept genuinely-vague items forever
# (billwatch "A service module: ... `if cached:`" no-op'd every cycle). Extension
# required, so prose slashes no longer count as a file reference.
HAS_FILE  = re.compile(r"[A-Za-z0-9_./-]+\." + EXT + r"\b")
# a relative path with a slash AND a known code extension -> existence-checkable
SLASH_FILE = re.compile(r"[A-Za-z0-9_.-]*/[A-Za-z0-9_./-]*\." + EXT + r"\b")
SKIP      = re.compile(r"human|HUMAN|AUTO-SKIP|decision|DELETE:|retired-", re.I)
# A file-CREATION item legitimately names a path that does not exist yet.
CREATE_INTENT = re.compile(r"\bcreate\b|does not exist yet|new pure|new module|new helper|add a new (pytest|vitest|test) file|write only a new", re.I)

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
    return False

def classify(line):
    body = line[len("- [ ]"):]
    if SKIP.search(body):
        return None
    if not HAS_FILE.search(body):
        return "vague"
    slash_paths = set(m.group(0) for m in SLASH_FILE.finditer(body))
    if slash_paths:
        if CREATE_INTENT.search(body):
            return None  # create-new-file item: missing path is expected, not dead
        if not any(_path_exists(p) for p in slash_paths):
            return "dead-path"
    return None  # keep

def process(path):
    if not os.path.exists(path):
        return (0, 0)
    lines = open(path).read().splitlines()
    out, vague, dead = [], [], []
    for ln in lines:
        cls = classify(ln) if ln.startswith("- [ ]") else None
        if cls == "vague":
            vague.append(ln[len("- [ ] "):])
        elif cls == "dead-path":
            dead.append(ln[len("- [ ] "):])
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
    open(path, "w").write("\n".join(out) + "\n")
    return (len(vague), len(dead))

if __name__ == "__main__":
    tv = td = 0
    for p in sys.argv[1:]:
        v, d = process(p)
        if v:
            print("  retired %d vague from %s" % (v, p))
        if d:
            print("  retired %d dead-path from %s" % (d, p))
        tv += v; td += d
    # keep the "retired N" line the runner greps on, covering both classes
    print("  total retired: %d (vague=%d dead-path=%d)" % (tv + td, tv, td))
