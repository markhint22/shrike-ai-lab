#!/usr/bin/env python3
"""ovn_move_executor.py - deterministic executor for `Move|Rename <file> to <new path>` queue items (2026-10-11, package delplan, iptv F8). SHADOW-first.

Why: a move/rename is structurally beyond a udiff-only editor. Asked to "Move file to .../iptv/data/repository/FavoritesRepository.kt and update package declaration", the 27B
creates a 0-byte target and deletes the source, so nothing compiles (3 no-op(stage-unverified) rows, 1.5-1.7 ks each, 'QUALITY FAIL: FavoritesRepository.kt is a 0-byte file',
iptv 2026-10-11). The same family as the delete / doc items that already have deterministic executors: `git mv`, fix the package/import lines by rule, let the caller verify.

usage: ovn_move_executor.py check <repo_dir> "<item line>"
       ovn_move_executor.py apply <repo_dir> "<item line>"
stdout (one line, tab separated; exit status is always 0) - the contract of ovn_executor_hook (lib_fixup.sh):
  check:  OK\t<files>                   the item is a safe move; <files> = every path `apply` will touch (old path, new path, .uid sidecars, edited referencing files)
          SKIP\t<why>
  apply:  APPLIED\t<files>\t<summary>   working tree edited (renames staged by `git mv`; NOT committed - the caller verifies, commits, credits)
          FAIL\t<why>                   working tree restored
          SKIP\t<why>

Item shape (the item's own path is the SOURCE):  `<src> - Move|Rename [the] [file] [`<src>`] to `<dst>` [and update the package declaration|imports ... [to `<pkg>`]].`
Anything else ('Move content from X to new file' copies, extra instructions after the move, an existing destination, a different extension, a protected / `..` path) is a SKIP and
the item goes down the normal path exactly as before. Env: OVN_MOVE_EXECUTOR=off disables both subcommands.

What a move rewrites (everything else that mentions the file makes the item a SKIP - the caller's repo verification is the final judge, this only DECIDES conservatively):
  .gd  `res://old` path tokens (project.godot autoloads, .tscn/.tres ext_resource, preload/load) -> `res://new`; the .gd.uid sidecar moves with it. Relative `load("x.gd")` references to the file,
       or relative path strings inside the moved file, are a SKIP. class_name references need no change.
  .py  the dotted module path (`app.jobs.x` in imports, mock.patch strings, importlib) -> the new dotted path; `from pkg import x` / relative-import forms of the module are a SKIP, as are
       relative imports inside the moved file when its package changes.
  .kt  the `package` line (item's `to `pkg``, else derived from the destination under src/<set>/java|kotlin) and `import <old pkg>.<Decl>` / fully-qualified `<old pkg>.<Decl>` uses of the file's
       top-level declarations. A wildcard import of the old package, a same-package file that uses a declaration (implicit visibility), the moved file using same-package declarations without
       an import, or a declaration named in a manifest / layout / gradle / proguard file without its qualified name, is a SKIP.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_delete_executor as D  # noqa: E402  (item parsing, protected names, the importer scan primitives)

SUPPORTED = {".gd", ".py", ".kt"}
MOVE_DESC = re.compile(r"^\s*(?:move|rename)\b(?P<mid>[^`]*?)(?:`(?P<src>[^`]+)`\s*)?\bto\b\s*`?(?P<dst>[A-Za-z0-9_.@/\[\]-]+\.[A-Za-z0-9]{1,8})`?(?P<rest>.*)$", re.I | re.S)
UPDATE_CLAUSE = re.compile(r"^\s*[,;.]?\s*(?:and\s+)?(?:then\s+)?update\b[^.]*?\b(?:package|packages|import|imports|references?|namespace|usages?)\b[^.]*?(?:`(?P<pkg>[A-Za-z_][\w.]*)`)?[^.]*\.?\s*$", re.I)
KT_PACKAGE = re.compile(r"^package\s+([A-Za-z_][\w.]*)\s*$", re.M)
KT_DECL = re.compile(r"^(?:(?:public|internal|private|data|sealed|enum|abstract|open|inline|value|annotation|const|lateinit|suspend)\s+)*(?:class|object|interface|typealias|fun|val|var)\s+(?:<[^>]*>\s*)?([A-Za-z_]\w*)", re.M)
CONFIG_EXT = (".xml", ".gradle", ".kts", ".pro", ".cfg", ".properties")


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def _tracked(repo, path):
    return git(repo, "ls-files", "--error-unmatch", "--", path).returncode == 0


def _read(repo, path):
    with open(os.path.join(repo, path), encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read()


class Skip(Exception):
    pass


def _parse(repo, item):
    head, desc, full = D.parse(item)
    m = MOVE_DESC.match(desc)
    if not m:
        raise Skip("not a move/rename item")
    src = D.primary_path(head, desc)
    if not src:
        raise Skip("no source path at the head of the item")
    named_src = m.group("src")
    if named_src and named_src != src:
        raise Skip("the item moves a different file than the one it is headed with (content copy?)")
    if re.search(r"\b(content|contents|copy|copies|split|merge|into)\b", m.group("mid"), re.I):
        raise Skip("content move / copy form, not a whole-file move")
    dst = m.group("dst")
    rest = re.split(r"\sVERIFY:", m.group("rest"), maxsplit=1)[0].strip()
    rest = re.sub(r"\s*(?:\([^()]*\)|\{[^{}]*\}|\[[^\[\]]*\])\s*$", "", rest).strip()
    pkg = None
    if rest.strip(" .,;"):
        um = UPDATE_CLAUSE.match(rest)
        if not um:
            raise Skip("extra instructions beyond the move")
        pkg = um.group("pkg")
    return src, dst, pkg


def _check_paths(repo, src, dst):
    for p in (src, dst):
        if p.startswith("/") or ".." in p.split("/"):
            raise Skip("unsafe path")
    se, de = os.path.splitext(src)[1], os.path.splitext(dst)[1]
    if se != de or se not in SUPPORTED:
        raise Skip("unsupported or changing extension (%s -> %s)" % (se, de))
    for p in (src, dst):
        if os.path.basename(p).lower() in D.PROTECTED_NAMES or any(x in p for x in D.PROTECTED_PARTS):
            raise Skip("protected path")
    if src == dst:
        raise Skip("source and destination are the same")
    if not _tracked(repo, src) or not os.path.isfile(os.path.join(repo, src)):
        raise Skip("source not tracked")
    if os.path.lexists(os.path.join(repo, dst)) or _tracked(repo, dst):
        raise Skip("destination already exists")
    d = os.path.dirname(dst)
    while d:
        if os.path.isfile(os.path.join(repo, d)):
            raise Skip("a file is in the way of the destination directory")
        d = os.path.dirname(d)


def _live_lines(text):
    """[(index, line)] of the non-comment lines of text."""
    return [(i, l) for i, l in enumerate(text.split("\n")) if not D.COMMENT_ONLY.match(l)]


def _gd_plan(repo, src, dst, edits):
    stem = os.path.splitext(os.path.basename(src))[0]
    own = _read(repo, src)
    if re.search(r"""\b(?:preload|load)\s*\(\s*["'](?!res://|user://|uid://)""", own):
        raise Skip("the moved file loads resources by relative path")
    tok = D._token_re(os.path.basename(src))
    for path, _ in D._grep_lines(repo, stem):
        if path == src or D.IGNORE_REF.search(path) or path in edits:
            continue
        text = _read(repo, path)
        out, changed = [], False
        for line in text.split("\n"):
            if D.COMMENT_ONLY.match(line):
                out.append(line)
                continue

            def sub(m):
                nonlocal changed
                if not D._token_resolves(m.group(1), path, src):
                    return m.group(0)
                if m.group(1).startswith("res://") and m.group(1)[len("res://"):] + os.path.basename(src) == src:
                    changed = True
                    return "res://" + dst
                raise Skip("%s references the file by a relative or partial path" % path)
            out.append(tok.sub(sub, line))
        if changed:
            edits[path] = "\n".join(out)
    return [(src + ".uid", dst + ".uid")] if _tracked(repo, src + ".uid") else []


def _py_module(repo, path):
    """Dotted module name of path relative to its topmost package directory (a dir chain carrying tracked __init__.py files); None when the module is not inside a package."""
    parts = path[:-3].split("/")
    d, top = os.path.dirname(path), None
    while d and _tracked(repo, d + "/__init__.py"):
        top = d
        d = os.path.dirname(d)
    if top is None:
        return None
    base = os.path.dirname(top)
    rel = path[len(base) + 1:] if base else path
    return rel[:-3].replace("/", ".")


def _py_plan(repo, src, dst, edits):
    old, new = _py_module(repo, src), None
    own = _read(repo, src)
    stem = os.path.splitext(os.path.basename(src))[0]
    if old is None:
        refs = D._importers(repo, src, [src])
        if refs:
            raise Skip("module outside a package is referenced by %s" % ", ".join(sorted(refs)[:3]))
        return []
    # destination module: same topmost package base, destination directory must be a package chain too
    top_base = src[: len(src) - len(old.replace(".", "/") + ".py")].rstrip("/")
    if top_base and not dst.startswith(top_base + "/"):
        raise Skip("destination leaves the package root")
    rel = dst[len(top_base) + 1:] if top_base else dst
    new = rel[:-3].replace("/", ".")
    ddir = os.path.dirname(dst)
    while ddir and ddir != top_base:                  # every directory between the package root and the destination must already be a package
        if not _tracked(repo, ddir + "/__init__.py"):
            raise Skip("destination directory %s is not a tracked package (no __init__.py)" % ddir)
        ddir = os.path.dirname(ddir)
    if os.path.dirname(dst) != os.path.dirname(src) and re.search(r"^\s*from\s+\.", own, re.M):
        raise Skip("the moved file uses relative imports and its package changes")
    dotted = re.compile(r"(?<![\w.])" + re.escape(old) + r"(?![\w])")
    needles = D._py_needles(src)
    strip = D.other_path_stripper(repo, src, stem)
    word = re.compile(r"(?<!\w)" + re.escape(stem) + r"(?!\w)")
    for path, _ in D._grep_lines(repo, stem):
        if path == src or D.IGNORE_REF.search(path) or path in edits:
            continue
        text = _read(repo, path)
        out, changed = [], False
        for line in text.split("\n"):
            if D.COMMENT_ONLY.match(line) or not word.search(line):
                out.append(line)
                continue
            if dotted.search(line):
                if word.search(strip(dotted.sub(" ", line), path)):
                    raise Skip("%s names the module by its dotted path AND in another form on one line" % path)
                line2 = dotted.sub(new, line)
                changed = True
                out.append(line2)
            elif any(re.search(r"(?<![\w.])" + re.escape(n) + r"(?![\w])", line) for n in needles if n != old):
                raise Skip("%s reaches the module by a partial dotted path" % path)
            elif D._PY_IMPORT.match(line):
                raise Skip("%s imports the module in a form that cannot be rewritten by rule (relative / from-package import)" % path)
            elif word.search(strip(line, path)):
                # review fix (round 2): a multi-line `from x import (\n  stem,\n)` continuation, a backslash continuation, `s.stem.f()` alias use, an importlib string:
                # the module is referenced in a form this rule cannot rewrite -> never "OK, 0 files rewritten" with a stale import left behind
                raise Skip("%s references the module name in a form that cannot be rewritten by rule (continuation line / alias / dynamic import)" % path)
            else:
                out.append(line)
        if changed:
            edits[path] = "\n".join(out)
    return []


def _kt_package_for(dst):
    m = re.search(r"/(?:java|kotlin)/(.+)/[^/]+\.kt$", dst)
    return m.group(1).replace("/", ".") if m else None


def _kt_plan(repo, src, dst, edits, pkg_hint):
    own = _read(repo, src)
    pm = KT_PACKAGE.search(own)
    old = pm.group(1) if pm else ""
    new = pkg_hint or _kt_package_for(dst) or old
    if not old and new:
        raise Skip("the source has no package declaration")
    if new == old:
        return [], None
    decls = sorted(set(KT_DECL.findall(own)))
    if not decls:
        raise Skip("no top-level declarations found")
    if git(repo, "grep", "-lIE", "^import[[:space:]]+" + re.escape(old) + "\\.\\*", "--", "*.kt").stdout.strip():
        raise Skip("a wildcard import of the old package exists")
    others = [f for f in git(repo, "grep", "-lIE", "^package[[:space:]]+" + re.escape(old) + "[[:space:]]*$", "--", "*.kt").stdout.splitlines() if f != src]
    # a same-package file relies on implicit visibility of the declaration: it would need an import after the move
    for f in others:
        t = _read(repo, f)
        for name in decls:
            if re.search(r"(?<![\w.])" + re.escape(name) + r"(?!\w)", re.sub(r"(?m)^\s*(?://.*|\*.*|/\*.*)$", "", t)) and not re.search(r"^import\s+" + re.escape(old + "." + name) + r"\s*$", t, re.M):
                raise Skip("%s (same package) uses %s without an import" % (f, name))
    # ... and so does the moved file for ITS same-package neighbours
    own_code = re.sub(r"(?m)^\s*(?://.*|\*.*|/\*.*)$", "", own)
    for f in others:
        for name in set(KT_DECL.findall(_read(repo, f))):
            if name not in decls and re.search(r"(?<![\w.])" + re.escape(name) + r"(?!\w)", own_code) and not re.search(r"^import\s+[\w.]+\." + re.escape(name) + r"\s*$", own, re.M):
                raise Skip("the moved file uses %s from the old package without an import" % name)
    for name in decls:
        for f in git(repo, "grep", "-lIw", "-F", "-e", name, "--", *["*" + e for e in CONFIG_EXT]).stdout.splitlines():
            if not re.search(re.escape(old + "." + name) + r"(?!\w)", _read(repo, f)):
                raise Skip("%s names %s without its qualified name" % (f, name))
    # rewrites: the package line of the moved file (kept in `edits` under its SOURCE path, written to the destination), qualified uses everywhere else
    edits[src] = KT_PACKAGE.sub("package " + new, own, count=1)
    for name in decls:
        qual = re.compile(r"(?<![\w.])" + re.escape(old + "." + name) + r"(?![\w])")
        for f in git(repo, "grep", "-lIF", "-e", old + "." + name).stdout.splitlines():
            if f == src or D.IGNORE_REF.search(f):
                continue
            t = edits.get(f, _read(repo, f))
            t2 = "\n".join(l if D.COMMENT_ONLY.match(l) else qual.sub(new + "." + name, l) for l in t.split("\n"))
            if t2 != t:
                edits[f] = t2
    return [], (old, new)


def plan(repo, item):
    """-> (moves [(old, new)], edits {path: new text}, summary) or raises Skip. The first move is the file itself."""
    src, dst, pkg = _parse(repo, item)
    _check_paths(repo, src, dst)
    edits = {}
    ext = os.path.splitext(src)[1]
    note = ""
    if ext == ".gd":
        extra = _gd_plan(repo, src, dst, edits)
    elif ext == ".py":
        extra = _py_plan(repo, src, dst, edits)
    else:
        extra, pk = _kt_plan(repo, src, dst, edits, pkg)
        note = (" package %s -> %s" % pk) if pk else " (package unchanged)"
    moves = [(src, dst)] + list(extra)
    summary = "git mv %s -> %s%s; %d referencing file(s) rewritten" % (src, dst, note, len([p for p in edits if p != src]))
    return moves, edits, summary


def _files(moves, edits):
    out = []
    for a, b in moves:
        out += [a, b]
    out += [p for p in edits if p not in out]
    return out


def apply(repo, item):
    moves, edits, summary = plan(repo, item)
    done, written = [], {}
    try:
        for a, b in moves:
            os.makedirs(os.path.dirname(os.path.join(repo, b)) or repo, exist_ok=True)
            r = git(repo, "mv", "--", a, b)
            if r.returncode != 0:
                raise OSError("git mv %s %s: %s" % (a, b, r.stderr.strip()[:120]))
            done.append((a, b))
        for path, text in edits.items():
            target = dict(moves).get(path, path)          # the moved file's own edits land at its new path
            fp = os.path.join(repo, target)
            before = _read(repo, target)
            with open(fp, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                f.write(text)
            written[target] = before                      # recorded only once the write happened
    except (OSError, UnicodeError) as e:
        for target, old in written.items():
            try:
                with open(os.path.join(repo, target), "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                    f.write(old)
            except OSError:
                pass
        for a, b in reversed(done):
            git(repo, "mv", "--", b, a)
        return ("FAIL", "%s" % e)
    return ("APPLIED", " ".join(_files(moves, edits)), summary)


def main():
    if os.environ.get("OVN_MOVE_EXECUTOR") == "off" or len(sys.argv) < 4 or sys.argv[1] not in ("check", "apply"):
        print("SKIP\tdisabled or usage")
        return
    repo, item = sys.argv[2], sys.argv[3]
    try:
        if sys.argv[1] == "check":
            moves, edits, _ = plan(repo, item)
            print("OK\t" + " ".join(_files(moves, edits)))
        else:
            print("\t".join(apply(repo, item)))
    except Skip as e:
        print("SKIP\t%s" % e)
    except Exception as e:  # never crash the lane: an unexpected shape is a SKIP
        print("SKIP\tinternal error: %s" % str(e)[:150].replace("\n", " "))


if __name__ == "__main__":
    main()
