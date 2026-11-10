#!/usr/bin/env python3
"""ovn_ts_unused_imports.py - remove the unused imports tsc/vue-tsc reported for a commit (package Z8b-D, 2026-11-10).

billwatch's tsc ratchet (baseline 76 pre-existing test type errors) reverted 8+ cycles for ONE new error: the model added an unused `vi` import (TS6133 / TS6192 / TS6196). This
deterministic fixer takes the checker output on stdin and removes exactly the imports it names, with these limits:
  * only files the commit touched (git diff <before> <after> --name-only), only .ts/.tsx/.vue, only imports whose lines the commit ADDED (a pre-existing unused import stays: it is in the
    baseline and is not this item's doing),
  * only errors TS6133 ("'x' is declared but its value is never read"), TS6196 ("'x' is declared but never used") and TS6192 ("All imports in import declaration are unused"),
  * only a binding of an `import ... from '...'` declaration (default, `* as ns`, `{ a, b as c, type d }`); a side-effect import (`import 'x'`) has no binding and is never touched,
  * a name tsc flagged is removed only when it really is a binding of that import; the declaration goes away only when no binding is left.
Usage: ovn_ts_unused_imports.py --cwd <dir tsc ran in> --toplevel <repo root> --before <sha> --after <sha> [--dry-run] < tsc-output
Prints one `FIXED <file> <name>` (or `WOULD-FIX` with --dry-run) line per removed binding, then `TOTAL <n> <files>`. Exit 0 always (fail-open).
"""
import argparse
import os
import re
import subprocess
import sys

ERR_RE = re.compile(r"^(?P<file>[^\s(][^(]*)\((?P<line>\d+),(?P<col>\d+)\): error TS(?P<code>6133|6196|6192)\b: (?P<msg>.*)$")
NAME_RE = re.compile(r"^'([^']+)' is declared but")
IMPORT_RE = re.compile(r"(?P<ws>^[ \t]*)import(?P<type>\s+type)?\s+(?P<clause>[^;'\"]*?)\s*\bfrom\s*(?P<q>['\"])(?P<mod>[^'\"\n]+)(?P=q)[ \t]*;?", re.M | re.S)


def parse_clause(clause):
    """-> (default or None, namespace or None, [(raw specifier text, local name)]) or None when not understood."""
    c = clause.strip()
    default = ns = None
    specs = []
    m = re.search(r"\{(.*)\}", c, re.S)
    head = c
    if m:
        head = c[:m.start()].strip().rstrip(",").strip()
        for raw in m.group(1).split(","):
            raw = raw.strip()
            if not raw:
                continue
            mm = re.match(r"^(?:type\s+)?([A-Za-z_$][\w$]*)(?:\s+as\s+([A-Za-z_$][\w$]*))?$", raw)
            if not mm:
                return None
            specs.append((raw, mm.group(2) or mm.group(1)))
        if c[m.end():].strip():
            return None
    if head:
        mm = re.match(r"^\*\s*as\s+([A-Za-z_$][\w$]*)$", head)
        if mm:
            ns = mm.group(1)
        elif re.match(r"^[A-Za-z_$][\w$]*$", head):
            default = head
        else:
            return None
    return default, ns, specs


def rebuild(m, default, ns, specs):
    parts = []
    if default:
        parts.append(default)
    if ns:
        parts.append("* as " + ns)
    if specs:
        parts.append("{ " + ", ".join(r for r, _ in specs) + " }")
    if not parts:
        return ""
    return "%simport%s %s from %s%s%s%s" % (m.group("ws"), m.group("type") or "", ", ".join(parts), m.group("q"), m.group("mod"), m.group("q"), ";" if m.group(0).rstrip().endswith(";") else "")


def added_lines(top, before, after, path):
    r = subprocess.run(["git", "-C", top, "diff", "-U0", "--no-color", before, after, "--", path], capture_output=True, text=True, timeout=60)
    out = set()
    for ln in r.stdout.split("\n"):
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", ln)
        if m:
            start, cnt = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
            out.update(range(start, start + cnt))
    return out


def fix_text(text, errors, added):
    """errors: [(line, code, name|None)]. Returns (new_text, [(name)])  - pure function (tested)."""
    removed = []
    edits = {}      # match.start() -> (match, default, ns, specs)
    for line, code, name in errors:
        hit = None
        for m in IMPORT_RE.finditer(text):
            l0 = text.count("\n", 0, m.start()) + 1
            l1 = l0 + text.count("\n", m.start(), m.end())
            if l0 <= line <= l1:
                hit = (m, l0, l1)
                break
        if not hit:
            continue
        m, l0, l1 = hit
        if added is not None and not (set(range(l0, l1 + 1)) & added):
            continue
        key = m.start()
        parsed = edits.get(key)
        if parsed is None:
            p = parse_clause(m.group("clause"))
            if p is None:
                continue
            parsed = (m,) + p
        _, default, ns, specs = parsed
        if code == "6192":
            names = ([default] if default else []) + ([ns] if ns else []) + [loc for _, loc in specs]
            default, ns, specs = None, None, []
        else:
            if name is None:
                continue
            if default == name:
                default = None
            elif ns == name:
                ns = None
            elif any(loc == name for _, loc in specs):
                specs = [(r, loc) for r, loc in specs if loc != name]
            else:
                continue
            names = [name]
        edits[key] = (m, default, ns, specs)
        removed.extend(names)
    if not edits:
        return text, []
    out, last = [], 0
    for key in sorted(edits):
        m, default, ns, specs = edits[key]
        out.append(text[last:m.start()])
        new = rebuild(m, default, ns, specs)
        if new:
            out.append(new)
            last = m.end()
        else:   # drop the whole declaration including its line break
            last = m.end()
            if text[last:last + 2] == "\r\n":   # keep the file's newline style: swallow a CRLF as one break
                last += 2
            elif text[last:last + 1] == "\n":
                last += 1
    out.append(text[last:])
    return "".join(out), removed


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", required=True)
    ap.add_argument("--toplevel", required=True)
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    try:
        tsc = sys.stdin.read()
        per = {}
        for ln in tsc.split("\n"):
            m = ERR_RE.match(ln.strip())
            if not m:
                continue
            nm = NAME_RE.match(m.group("msg"))
            per.setdefault(m.group("file").strip(), []).append((int(m.group("line")), m.group("code"), nm.group(1) if nm else None))
        touched = set(subprocess.run(["git", "-C", a.toplevel, "diff", "--name-only", a.before, a.after], capture_output=True, text=True, timeout=60).stdout.split("\n"))
        total, files = 0, []
        for rel, errs in sorted(per.items()):
            if not rel.endswith((".ts", ".tsx", ".vue")):
                continue
            full = os.path.normpath(os.path.join(a.cwd, rel))
            top_rel = os.path.relpath(os.path.realpath(full), os.path.realpath(a.toplevel))
            if top_rel not in touched or not os.path.isfile(full):
                continue
            with open(full, encoding="utf-8", newline="") as fh:   # newline="": no translation, CRLF files stay CRLF
                text = fh.read()
            new, names = fix_text(text, errs, added_lines(a.toplevel, a.before, a.after, top_rel))
            if not names:
                continue
            if not a.dry_run:
                with open(full, "w", encoding="utf-8", newline="") as f:
                    f.write(new)
            for n in names:
                print("%s %s %s" % ("WOULD-FIX" if a.dry_run else "FIXED", top_rel, n))
            total += len(names)
            files.append(top_rel)
        print("TOTAL %d %s" % (total, " ".join(files)))
    except Exception as ex:   # never break the gate
        print("ERROR %s: %s" % (type(ex).__name__, str(ex)[:200]))
        print("TOTAL 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
