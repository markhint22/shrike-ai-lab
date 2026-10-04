#!/usr/bin/env python3
"""ovn_delete_executor.py - decide whether a queue item is a SAFE whole-file deletion the fleet can do with `git rm`.

Why: udiff cannot express a deletion here ("'/dev/null' is not in the subpath of ..."), so every 'Delete/Remove <file>'
item is an LLM job that can never succeed (measured 2026-09-29: ~43 min/day; one gitlark delete item was attempted 57
times). The caller (run_overnight.sh DELETE-EXECUTOR block) does the git rm + the repo's full verification + credit; this
only DECIDES, conservatively, from the item text and the working tree. Anything doubtful is a SKIP and the item goes down
the normal path exactly as before.

usage: ovn_delete_executor.py check <repo_dir> "<item line>"
stdout: "OK\t<path> [<path>...]"   (paths to git rm; the item's file + its dedicated test ONLY if the item names that test)
        "ALREADY-GONE\t<path>"        (h13: the target is absent AND was tracked then deleted in git history, or the item's own
                                       `VERIFY: test ! -f <path>` already passes - nothing left to delete; caller credits the item)
        "SKIP\t<reason>"
"""
import os
import re
import subprocess
import sys

CODE_EXT = {".py", ".ts", ".tsx", ".js", ".jsx", ".vue", ".kt", ".gd"}
PATH = re.compile(r"[A-Za-z0-9_.@-]+(?:/[A-Za-z0-9_.@\[\]-]+)*\.[A-Za-z0-9]{1,8}")
# whole-FILE deletion phrasing only ("Delete the dead X.py module/file"); identical shape to the agent-validated R1 rule
DELFILE = re.compile(r"^\s*(delete|remove)\b[^.`]{0,40}\b(file|module|class file|test file)\b", re.I)
DELFILE_PATH_FIRST = re.compile(r"^\s*(delete|remove)\s+(the\s+)?(dead\s+|unused\s+|orphan(ed)?\s+|stub\s+|empty\s+)*`?[A-Za-z0-9_./@-]+\.[A-Za-z0-9]{1,8}`?\s*(\(|[,;:.]|$|—|-|because|it |which |as |since )", re.I)
PARTIAL = re.compile(r"\b(function|method|constant|import|field|column|line|lines|block|entry|route|endpoint|export|variable|key|param|parameter|case|branch|dependency)\b", re.I)
PROTECTED_NAMES = {"__init__.py", "conftest.py", "main.py", "app.py", "index.ts", "index.tsx", "index.js", "app.vue", "main.ts", "main.js",
                   "settings.py", "config.py", "package.json", "manage.py", "wsgi.py", "asgi.py", "env.py", "build.gradle", "build.gradle.kts"}
PROTECTED_PARTS = ("alembic/", "migrations/", "/versions/", ".github/", "node_modules/", "/.venv/", "android/app/src/main/AndroidManifest", "project.godot")
GENERIC_STEMS = {"index", "main", "utils", "util", "types", "type", "constants", "config", "models", "model", "helpers", "helper", "common",
                 "base", "core", "app", "api", "store", "test", "tests", "data", "schema", "schemas", "service", "services", "router", "routes"}
IGNORE_REF = re.compile(r"(\.md$|\.rst$|\.txt$|\.lock$|-lock\.json$|^OVERNIGHT_|^docs/|^htmlcov/|^coverage/|\.snap$)")


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def parse(item):
    t = re.sub(r"^- \[[ xX]\]\s*", "", item.strip())
    t = re.sub(r"^(\[[^\]]*\]\s*|\([^)]*\)\s*)+", "", t)
    head, _, desc = t.partition(" — ")
    return head.strip(), desc.strip(), t


def primary_path(head, desc):
    m = PATH.search(head.replace("`", ""))
    if m and head.replace("`", "").strip().startswith(m.group(0)):
        return m.group(0)
    return None


def _name_elsewhere(repo, prim):
    """True when prim has no directory part and a tracked file with that basename exists somewhere else (the item's path is then ambiguous)."""
    if "/" in prim:
        return False
    out = git(repo, "ls-files").stdout.splitlines()
    return any(os.path.basename(f) == prim for f in out)


def decide(repo, item):
    head, desc, full = parse(item)
    if not (DELFILE.match(desc) or DELFILE_PATH_FIRST.match(desc) or re.search(r"VERIFY:\s*`?\s*test\s+!\s+-f\s+", full)):
        return ("SKIP", "not a whole-file delete item")
    lead = desc[:80]
    # "Remove dead function foo() from x.py" / "Delete unused import" etc. are edits, not file deletions
    if PARTIAL.search(lead) and not re.search(r"\b(file|module|class file|test file)\b", lead, re.I):
        return ("SKIP", "partial edit, not a file delete")
    prim = primary_path(head, desc)
    if not prim:
        m = PATH.search(desc.replace("`", ""))
        prim = m.group(0) if m else None
    if not prim:
        return ("SKIP", "no target path")
    if ".." in prim.split("/") or prim.startswith("/"):
        return ("SKIP", "unsafe path")
    if os.path.splitext(prim)[1] not in CODE_EXT:
        return ("SKIP", "not a code file")
    base = os.path.basename(prim)
    if base.lower() in PROTECTED_NAMES or any(p in prim for p in PROTECTED_PARTS):
        return ("SKIP", "protected file")
    if git(repo, "ls-files", "--error-unmatch", "--", prim).returncode != 0:
        # h13 (2026-10-04): an item whose file an EARLIER commit already deleted flailed 6 cycles (xlite elevation.gd): the DELETE handler only acts on an
        # existing file and the item was never credited. Absent now + (deleted in history OR the item's own VERIFY `test ! -f <path>`) = done.
        # Review hardening: lexists (a dangling symlink is still there), literal pathspecs (a `[id].ts` path is not a glob), the VERIFY must be the
        # item's WHOLE check (no `&& <more>` tail that would go unevaluated), and a bare file name (no directory) is ambiguous when a tracked file
        # of that name lives elsewhere - then the named target may simply be mis-pathed, never credit.
        if not os.path.lexists(os.path.join(repo, prim)) and not _name_elsewhere(repo, prim):
            hist = git(repo, "--literal-pathspecs", "log", "--diff-filter=D", "--format=%h", "-1", "--", prim).stdout.strip()
            _pe = re.escape(prim)
            own_verify = re.search(r"VERIFY:\s*(?:`\s*test\s+!\s+-[fe]\s+" + _pe + r"\s*`|test\s+!\s+-[fe]\s+" + _pe + r"\s*(?:\)|\.|,|\[feat:[^\]]*\]|\{[^}]*\}|$))", full)
            if hist or own_verify:
                return ("ALREADY-GONE", prim)
        return ("SKIP", "target not tracked (already gone or wrong path)")
    stem = os.path.splitext(base)[0]
    if stem.lower() in GENERIC_STEMS or len(stem) < 4:
        return ("SKIP", "generic file name - importer search would be unreliable")
    targets = [prim]
    # a dedicated test is deleted too ONLY if the item itself names it
    for p in PATH.findall(full.replace("`", "")):
        if p == prim or p in targets:
            continue
        pb = os.path.basename(p)
        if stem in pb and re.search(r"(^|/)(tests?|__tests__)/|\.test\.|\.spec\.|_test\.|^test_", p) and \
                git(repo, "ls-files", "--error-unmatch", "--", p).returncode == 0:
            targets.append(p)
    # importer search: any OTHER tracked non-doc file that mentions the module name blocks the automatic delete
    needles = {stem}
    if prim.endswith(".py"):
        needles.add(prim[:-3].replace("/", "."))
    refs = set()
    for n in needles:
        r = git(repo, "grep", "-lIw" if n == stem else "-lIF", "--", n)
        for f in r.stdout.splitlines():
            if f in targets or IGNORE_REF.search(f):
                continue
            refs.add(f)
    if refs:
        return ("SKIP", "referenced by: " + ", ".join(sorted(refs)[:3]))
    return ("OK", " ".join(targets))


def main():
    if len(sys.argv) < 4 or sys.argv[1] != "check":
        print("SKIP\tusage")
        return
    act, info = decide(sys.argv[2], sys.argv[3])
    print("%s\t%s" % (act, info))


if __name__ == "__main__":
    main()
