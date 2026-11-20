#!/usr/bin/env python3
"""ovn_gut_ghost_lint.py - GUT ghost-test checker (package q-wave2, 2026-11-17).

GUT (the Godot test runner) collects methods whose name STARTS WITH `test_` (the default prefix). `func _test_x()` starts with an underscore, so it is never run: the file stays green and the
"test" asserts nothing. xlite landed 21 of them in 14 days (test_loc_keys_consistent.gd `_test_walk_scripts_dir`, the Loc/glyph/CodexData batches, README drift tests ...); the model keeps writing the
underscore because GDScript style says private members start with `_`.

scan_text(text, path)   -> [{"line", "name", "path"}]  every `func _test*` definition (static too) in a GUT test file that nothing in the same file calls (a helper `_test_x()` called from a real
                           `test_y()` IS run, so it is not a ghost). Only files that `extends GutTest|GutHookScript|"res://addons/gut/test.gd"` (or sit under a tests/ dir with a test_*.gd name) count.
scan_added(path, added, post_text)   the diff form used by the landing gate: added (lineno, text) pairs, post_text = the file after the change (None = unknown, every added definition counts).
is_test_file(path)      tests/**/test_*.gd | **/test_*.gd | *_test.gd, never addons/ (vendored GUT itself has `_test_running_setup` etc.).
CLI: ovn_gut_ghost_lint.py <file-or-dir> ...   prints `path:line: ghost GUT test <name>`; exit 1 when any, else 0.  --json prints one JSON array.
"""
import json
import os
import re
import sys

FUNC_RE = re.compile(r"^[ \t]*(?:static[ \t]+)?func[ \t]+(_test\w*)[ \t]*\(")
GUT_EXT_RE = re.compile(r"^[ \t]*extends[ \t]+(?:GutTest|GutHookScript|\"res://addons/gut/test\.gd\"|'res://addons/gut/test\.gd')", re.M)


def is_test_file(path):
    p = (path or "").replace("\\", "/")
    if not p.endswith(".gd") or p.startswith("addons/") or "/addons/" in p:
        return False
    base = p.rsplit("/", 1)[-1]
    return base.startswith("test_") or base.endswith("_test.gd") or "/tests/" in "/" + p


def _is_gut(text):
    return bool(GUT_EXT_RE.search(text or "") or re.search(r"^[ \t]*extends[ \t]+\w*Test\w*", text or "", re.M))


_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _strip_comment(ln):
    """drop a trailing `# ...` comment (a # inside a string literal is kept)."""
    i = ln.find("#")
    while i >= 0:
        pre = ln[:i]
        if pre.count('"') % 2 == 0 and pre.count("'") % 2 == 0:
            return pre
        i = ln.find("#", i + 1)
    return ln


def _used_idents(text):
    """one linear pass: the set of identifiers that appear on any non-comment line that is not a `func _test*` definition line. A name that is called, passed as a Callable(self, "_test_x") /
    call("_test_x") string, connected (connect(_test_x)) or merely referenced counts as used: it is a helper, not a never-collected ghost."""
    used = set()
    for ln in (text or "").split("\n"):
        if FUNC_RE.match(ln) or ln.lstrip().startswith("#"):
            continue
        used.update(_IDENT_RE.findall(_strip_comment(ln)))
    return used


def scan_text(text, path=""):
    if path and not is_test_file(path):
        return []
    if not _is_gut(text):
        return []
    defs = []
    for i, ln in enumerate((text or "").split("\n"), 1):
        m = FUNC_RE.match(ln)
        if m:
            defs.append((i, m.group(1)))
    used = _used_idents(text)
    return [{"line": i, "name": n, "path": path} for i, n in defs if n not in used]


def scan_added(path, added, post_text=None):
    """diff form: only definitions on added lines; with post_text the 'called by a real test' escape applies."""
    if not is_test_file(path):
        return []
    out = []
    used = _used_idents(post_text) if post_text is not None and _is_gut(post_text) else None
    for ln, t in added:
        m = FUNC_RE.match(t)
        if not m:
            continue
        name = m.group(1)
        if post_text is not None:
            if not _is_gut(post_text):
                continue
            if name in used:
                continue
        out.append({"line": ln, "name": name, "path": path})
    return out


def main(argv):
    a = argv[1:]
    js = "--json" in a
    a = [x for x in a if x != "--json"]
    found = []
    for p in a:
        paths = []
        if os.path.isdir(p):
            for root, ds, fs in os.walk(p):
                ds[:] = [d for d in ds if d not in (".git", "addons", "node_modules")]
                paths += [os.path.join(root, f) for f in fs if f.endswith(".gd")]
        else:
            paths.append(p)
        for f in sorted(paths):
            try:
                txt = open(f, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            rel = os.path.relpath(f, p) if os.path.isdir(p) else f
            rel = rel.replace(os.sep, "/")
            # a bare directory scan passes paths relative to the directory: they are test files by construction when the directory is tests/
            chk = rel if is_test_file(rel) else ("tests/" + rel if os.path.isdir(p) and rel.endswith(".gd") and os.path.basename(rel).startswith("test_") else rel)
            found += scan_text(txt, chk)
    if js:
        print(json.dumps(found))
    else:
        for g in found:
            print("%s:%d: ghost GUT test %s (GUT only runs test_* methods)" % (g["path"], g["line"], g["name"]))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
