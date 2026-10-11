#!/usr/bin/env python3
"""ovn_doc_postcheck.py - net-diff post-check for `supply:gd-missing-doc` commits (2026-10-10, package docexec; analysis[6] BX-01).

Why: a doc item's cycle is credited on the item's own VERIFY alone, and "landed" is counted from the push. Measured on xlite 10-09/10-10: 57 of 127 landed rows
were doc items, 45 of them landed-uncredited; of 71 .gd files touched by doc commits 11 ended with NO net new `##` line (the next cycle's "move doc comment above"
only deleted the lines again) and 10 gained an orphan `##` block (udiff hunks that land at the end of the file / inside a function), mission_summary.gd carried
the same comment twice, loot_table.gd got a duplicated `static func` line (Parse Error). A commit like that is not a landed doc item.

usage: ovn_doc_postcheck.py check <repo_dir> <base_sha> <head> "<item line>"
       ovn_doc_postcheck.py scan  <repo_dir> [<path.gd> ...]          (working-tree files; default: every tracked .gd outside addons/)
stdout (one line, tab separated, exit status always 0):
  check:  OK\\t<file>\\t<n> named func(s) carry a ## line added by this change
          FLAG\\t<code,code,...>\\t<detail>
          SKIP\\t<why>                  (not a gd-missing-doc item, no file, ... - nothing to judge)
  scan:   one `<file>\\torphans=<n>\\tdups=<n>\\tfirst-orphan-line=<n>` line per file with a finding, then `TOTAL\\tfiles=<n>\\torphans=<n>\\tdups=<n>`
Flag codes (every one is relative to BASE, so damage that already existed is never charged to this change):
  no-net-doc   a named func has no `##` line directly above it (annotations count as part of the declaration), or that block was already attached in BASE and not added by this diff
               (a block that BASE had detached by blank lines and this change attached, e.g. the executor's blank-line repair, counts as a gain)
  orphan       the change added a `##` block that is not directly above a declaration (end of file, inside a function body, separated by a blank line)
  duplicate    the change added a `##` block whose text already exists elsewhere in the file, or repeated a line inside one block
  dup-func     a named func is now defined more often than before (the model re-added the whole `func` line)
  func-missing a named func is gone;  file-missing: the file is gone
env: OVN_DOC_POSTCHECK_MIN_DUP (default 12) = shortest normalised block text that counts as a duplicate.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_doc_executor as dx  # noqa: E402  (parse_item / FUNC_RE / anchor: ONE definition of 'the func and where its doc goes')

MIN_DUP = int(os.environ.get("OVN_DOC_POSTCHECK_MIN_DUP", "12"))
# a line a `##` block may legitimately sit directly above: any declaration, an annotation (`@export var`, `@rpc`), the script header (`extends`, `class_name`, `@tool`)
DECL_RE = re.compile(r"^[ \t]*(?:(?:static[ \t]+)?(?:func|var|const|signal|enum|class)\b|class_name\b|extends\b|@\w+)")


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, "--literal-pathspecs"] + list(args), capture_output=True)
    return r.returncode, r.stdout.decode("utf-8", "replace")


# a line that may precede a script-level doc block: Godot attaches a `##` block that follows `extends` / `class_name` / the script annotations (and is then followed by a
# blank line) to the SCRIPT itself - 190 of xlite's 223 whole-tree "orphans" were exactly that shape, which is valid and must not be flagged
HEADER_RE = re.compile(r"^[ \t]*(?:extends\b|class_name\b|@\w+)")


def doc_blocks(lines):
    """-> [(start, end_exclusive, attached)] for every maximal run of `##` lines. attached = the next line (no blank in between) is a declaration, or the block is the script-level
    doc (nothing but `extends` / `class_name` / annotations / plain comments before it)."""
    out, i, n = [], 0, len(lines)
    header_only = True   # no code line seen yet except header lines
    while i < n:
        if lines[i].lstrip().startswith("##"):
            j = i
            while j < n and lines[j].lstrip().startswith("##"):
                j += 1
            out.append((i, j, (j < n and bool(DECL_RE.match(lines[j]))) or header_only))
            i = j
        else:
            l = lines[i]
            if l.strip() and not l.lstrip().startswith("#") and not HEADER_RE.match(l):
                header_only = False
            i += 1
    return out


def _norm(block_lines):
    return re.sub(r"\s+", " ", " ".join(re.sub(r"^\s*##", "", l) for l in block_lines)).strip().lower()


def orphan_count(lines):
    return sum(1 for (s, e, att) in doc_blocks(lines) if not att)


def dup_count(lines):
    """Extra copies: identical (normalised, >= MIN_DUP chars) block texts beyond the first, plus a line repeated back-to-back inside one block."""
    seen, extra = {}, 0
    for (s, e, _att) in doc_blocks(lines):
        t = _norm(lines[s:e])
        if len(t) >= MIN_DUP:
            seen[t] = seen.get(t, 0) + 1
        for k in range(s + 1, e):
            if lines[k].strip() == lines[k - 1].strip() and len(lines[k].strip()) > 5:
                extra += 1
    return extra + sum(c - 1 for c in seen.values())


def first_orphan_line(lines):
    for (s, e, att) in doc_blocks(lines):
        if not att:
            return s + 1
    return 0


def added_lines(repo, base, head, f):
    """Set of 1-based line numbers (in HEAD's file) that the diff base..head adds."""
    rc, out = git(repo, "diff", "-U0", "--no-color", base, head, "--", f)
    add = set()
    if rc != 0:
        return add
    for m in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", out, re.M):
        start, cnt = int(m.group(1)), int(m.group(2)) if m.group(2) is not None else 1
        add.update(range(start, start + cnt))
    return add


def show(repo, rev, f):
    rc, out = git(repo, "show", "%s:%s" % (rev, f))
    return out.split("\n") if rc == 0 else None


def n_funcs(lines, name):
    rx = re.compile(dx.FUNC_RE % re.escape(name))
    return sum(1 for l in lines if rx.match(l))


def doc_block_above(lines, i):
    """(start, end) of the `##` run directly above the declaration of the func at lines[i] (annotations skipped, NO blank line allowed), or None."""
    a = dx.anchor(lines, i)
    j = a
    while j > 0 and lines[j - 1].lstrip().startswith("##"):
        j -= 1
    return (j, a) if j < a else None


def check(repo, base, head, item):
    if "supply:gd-missing-doc" not in item:
        return ("SKIP", "not a gd-missing-doc supply item")
    f, names = dx.parse_item(item)
    if not f or not names:
        return ("SKIP", "no .gd target or function names in the item")
    old, new = show(repo, base, f), show(repo, head, f)
    if new is None:
        return ("FLAG", "file-missing", "%s does not exist at %s" % (f, head[:12]))
    if old is None:
        old = []
    flags, detail = [], []
    added = added_lines(repo, base, head, f)
    if not added and old == new:
        flags.append("no-net-doc")
        detail.append("no net diff on %s" % f)
    else:
        gained, already = [], []
        for name in names:
            rx = re.compile(dx.FUNC_RE % re.escape(name))
            idx = [i for i, l in enumerate(new) if rx.match(l)]
            if not idx:
                flags.append("func-missing")
                detail.append("`%s` is gone" % name)
                continue
            if n_funcs(new, name) > n_funcs(old, name):
                flags.append("dup-func")
                detail.append("`%s` defined %dx (was %dx)" % (name, n_funcs(new, name), n_funcs(old, name)))
            blk = doc_block_above(new, idx[0])
            if blk is None:
                flags.append("no-net-doc")
                detail.append("no ## directly above `%s`" % name)
                continue
            oidx = [i for i, l in enumerate(old) if re.match(dx.FUNC_RE % re.escape(name), l)]
            if any((k + 1) in added for k in range(blk[0], blk[1])) or (oidx and doc_block_above(old, oidx[0]) is None):
                gained.append(name)   # a ## line was added above it, or BASE had the block DETACHED by blank lines and this change attached it (the executor's own repair)
            else:
                already.append(name)  # documented in BASE already: nothing to do for this one
        # every named func must be documented now (checked above); the change must also have DONE something for at least one of them
        if not gained and already and "no-net-doc" not in flags and "func-missing" not in flags:
            flags.append("no-net-doc")
            detail.append("the ## above %s was already there (not added by this change)" % ", ".join("`%s`" % n for n in already))
    d_orph = orphan_count(new) - orphan_count(old)
    if d_orph > 0:
        flags.append("orphan")
        detail.append("+%d orphan ## block(s), first at line %d" % (d_orph, first_orphan_line(new)))
    d_dup = dup_count(new) - dup_count(old)
    if d_dup > 0:
        flags.append("duplicate")
        detail.append("+%d duplicated ## text(s)" % d_dup)
    if flags:
        uniq = []
        for c in flags:
            if c not in uniq:
                uniq.append(c)
        return ("FLAG", ",".join(uniq), "%s: %s" % (f, "; ".join(detail)))
    return ("OK", f, "%d named func(s) carry a ## line added by this change" % len(names))


def scan(repo, paths):
    if not paths:
        rc, out = git(repo, "ls-files")
        paths = [p for p in out.split("\n") if p.endswith(".gd") and not p.startswith("addons/") and "/addons/" not in p]
    rows, to, td, nf = [], 0, 0, 0
    for p in paths:
        try:
            lines = open(os.path.join(repo, p), encoding="utf-8", errors="replace").read().split("\n")
        except OSError:
            continue
        nf += 1
        o, d = orphan_count(lines), dup_count(lines)
        if o or d:
            rows.append("%s\torphans=%d\tdups=%d\tfirst-orphan-line=%d" % (p, o, d, first_orphan_line(lines)))
        to, td = to + o, td + d
    return rows + ["TOTAL\tfiles=%d\torphans=%d\tdups=%d" % (nf, to, td)]


def main(argv):
    if len(argv) >= 6 and argv[1] == "check":
        print("\t".join(check(argv[2], argv[3], argv[4], argv[5])))
    elif len(argv) >= 3 and argv[1] == "scan":
        print("\n".join(scan(argv[2], argv[3:])))
    else:
        print("SKIP\tusage: ovn_doc_postcheck.py check <repo> <base> <head> \"<item>\" | scan <repo> [paths]")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
