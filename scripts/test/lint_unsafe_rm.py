#!/usr/bin/env python3
"""Unsafe-deletion lint (2026-10-16, HOME-deletion incident). usage: lint_unsafe_rm.py <root> [<root>...]   exit 1 + one line per finding.

Background: `tmp="$(mktemp -d)"` failed, tmp was empty, HOME became /home and `rm -rf "$HOME"` deleted a real home directory. A recursive delete whose target is built
from a variable can erase far more than intended when the variable is empty or equal to HOME. Rules (shell files: .sh/.bash/no extension with a shell shebang):
  R1  rm -r*  target "$VAR/..." / "${VAR}/..." / "$VAR"/* (variable-led path or glob): empty VAR makes it an absolute path / the root glob.
      OK only as "${VAR:?}/..." (aborts when empty/unset), or with a same-line [ -n "$VAR" ] / [ -z "$VAR" ] || guard, or via safe_rm_rf.
  R2  rm -r*  of HOME itself or a tilde path: "$HOME" / "${HOME}" / "$HOME"/* / ~ / ~/* . Use safe_rm_rf (refuses HOME, /home, /, shallow paths, anything outside the sandbox).
  R3  rm -r*  of an UNQUOTED variable ($VAR word-splits and can vanish): unsafe unless guarded.
  R4  find <var-led or unquoted path> ... -delete: same hazard as R1/R3 (an empty unquoted path makes find walk the CURRENT directory).
  R5  python shutil.rmtree / os.removedirs of HOME-derived or root literal paths (expanduser("~"), Path.home(), os.environ["HOME"], "/").
A bare quoted "$VAR" target is NOT flagged by R1 (rm -rf "" is a no-op), but R2 covers the HOME case.
Skipped: full-line comments, backslash-escaped generated/mutation text, markdown/json/patch/fixtures.
"""
import os, re, sys

FLAGS = re.compile(r'(?<![\w./-])rm((?:\s+-{1,2}[a-zA-Z-]+)+)(?=\s)')
SKIP_DIRS = {".git", "__pycache__", "fixtures", "fixtures_qagate", "fixtures_qa_migrations", "assets"}
SELF = ("lint_unsafe_rm.py", "test_no_unsafe_rm.sh")


def seg_end(s, i):
    q = False
    while i < len(s):
        c = s[i]
        if c == '"' and (i == 0 or s[i - 1] != '\\'):
            q = not q
        elif not q and c in ";|&)\n'#":
            return i
        i += 1
    return i


def guarded(var, line):
    v = re.escape(var)
    return bool(re.search(r'-n\s+"?\$\{?%s\}?"?' % v, line) or re.search(r'-z\s+"?\$\{?%s\}?"?\s*\|\|' % v, line)
                or re.search(r'\$\{%s:\?' % v, line))


def lint_shell_line(line):
    out = []
    if line.lstrip().startswith("#") or '\\"' in line:
        return out
    for m in FLAGS.finditer(line):
        flags = m.group(1)
        if not re.search(r'-[a-zA-Z]*[rR]|--recursive', flags):
            continue
        seg = line[m.end():seg_end(line, m.end())]
        for tok in seg.split():
            raw = tok
            if raw.startswith("-"):
                continue
            t = raw.strip("'")
            if t.startswith("~") or t.startswith('"~'):
                out.append(("R2", "rm -r of a tilde path: " + raw)); continue
            mm = re.match(r'^"?\$\{?([A-Za-z_][A-Za-z0-9_]*|[0-9@*])(:\?[^}]*)?\}?("?)(.*)$', t)
            if not mm:
                continue
            var, guard, endq, rest = mm.group(1), mm.group(2), mm.group(3), mm.group(4)
            quoted = t.startswith('"')
            rest = rest.rstrip('"')
            if var == "HOME" and not guard and rest in ("", "/", "/*", "*"):
                out.append(("R2", "rm -r of HOME itself: " + raw)); continue
            if not quoted:
                if guard or guarded(var, line):
                    continue
                out.append(("R3", "rm -r of an unquoted variable: " + raw)); continue
            if rest.startswith("/") or rest.startswith("*") or raw.endswith('"/*"'):
                if guard or guarded(var, line):
                    continue
                out.append(("R1", 'rm -r of "$%s..." with no :? / -n guard: %s' % (var, raw)))
    return out


def lint_find_line(line):
    out = []
    if line.lstrip().startswith("#") or '\\"' in line:
        return out
    for m in re.finditer(r'(?<![\w./-])find\s+((?:-[HLP]\s+)*)([^\s;|&]+)(?=[^;|&]*\s-delete\b)', line):
        p = m.group(2)
        mm = re.match(r'^"?\$\{?([A-Za-z_][A-Za-z0-9_]*)(:\?[^}]*)?\}?("?)(.*)$', p)
        if not mm:
            continue
        var, guard, endq, rest = mm.groups()
        quoted = p.startswith('"')
        if guard or guarded(var, line):
            continue
        if not quoted:
            out.append(("R4", "find <unquoted $%s> -delete: %s" % (var, p)))
        elif rest.rstrip('"').startswith("/"):
            out.append(("R4", 'find "$%s/..." -delete with no :? guard: %s' % (var, p)))
    return out


PY_BAD = re.compile(r'(shutil\.rmtree|os\.removedirs|rmtree)\(\s*(os\.path\.expanduser\(\s*["\']~["\']\s*\)|Path\.home\(\)|pathlib\.Path\.home\(\)|os\.environ\[["\']HOME["\']\]|os\.environ\.get\(["\']HOME["\'][^)]*\)|["\']/["\']|["\']/home["\']|["\']~["\'])')


def lint_py_line(line):
    if line.lstrip().startswith("#"):
        return []
    return [("R5", "python recursive delete of a HOME/root path")] if PY_BAD.search(line) else []


def is_shell(path, head):
    if path.endswith((".sh", ".bash")):
        return True
    first = head.split("\n")[0]
    return "." not in os.path.basename(path) and first.startswith("#!") and ("bash" in first or "/sh" in first)


def lint_text(path, text):
    res = []
    shell = is_shell(path, text[:200])
    py = path.endswith(".py")
    for i, l in enumerate(text.split("\n"), 1):
        found = []
        if shell:
            found = lint_shell_line(l) + lint_find_line(l)
        elif py:
            found = lint_py_line(l)
        for rule, msg in found:
            res.append("%s:%d: %s: %s   | %s" % (path, i, rule, msg, l.strip()[:140]))
    return res


def lint_root(root):
    res = []
    for d, ds, fs in os.walk(root):
        ds[:] = [x for x in ds if x not in SKIP_DIRS]
        for f in fs:
            if f in SELF:
                continue
            p = os.path.join(d, f)
            if f.endswith((".md", ".json", ".patch", ".txt", ".log", ".yaml", ".yml", ".plist", ".service", ".gd", ".kt", ".swift")) or os.path.islink(p):
                continue
            try:
                text = open(p, errors="replace").read()
            except OSError:
                continue
            res += lint_text(p, text)
    return res


if __name__ == "__main__":
    allf = []
    for r in (sys.argv[1:] or ["."]):
        allf += lint_root(r)
    for x in allf:
        print(x)
    print("unsafe-rm lint: %d finding(s)" % len(allf))
    sys.exit(1 if allf else 0)
