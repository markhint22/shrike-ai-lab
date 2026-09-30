#!/usr/bin/env python3
"""Strip whitespace-ONLY lines (spaces/tabs, nothing else) in tracked source files.

Why (2026-09-30 throughput analysis): a whitespace-only blank line in a source file is the dominant cause of the
27B's udiff failing to apply (the model emits a truly empty context line; the file has "    "). One item that failed
7/7 applied in 33s once they were stripped. Affected files: gitlark 179/746, billwatch 77/600, test-automation-agent
83/566, iptv_apps 33/732.

Scope is deliberately tiny and semantics-preserving: ONLY lines matching ^[ \t]+$ are emptied (code lines keep
their trailing whitespace - no noise diff). For Python, whitespace-only lines INSIDE a multi-line string literal are
left alone (they are data). Line endings are preserved. Code extensions only; generated/vendored dirs skipped.

usage: ovn_ws_strip.py <repo_root> [--check]   (--check: report only, exit 1 if anything would change)
"""
import io
import os
import re
import subprocess
import sys
import tokenize

EXTS = {".py", ".ts", ".tsx", ".js", ".jsx", ".vue", ".kt", ".gd", ".java", ".css", ".scss", ".sh"}
SKIP_DIRS = ("node_modules/", ".venv/", "venv/", "dist/", "build/", "vendor/", "site-packages/", ".gradle/", "Pods/", "htmlcov/", "coverage/", "migrations/versions_generated/")
WS_ONLY = re.compile(rb"^[ \t]+(\r?\n?)$")
MAX_BYTES = 1_000_000


def py_string_lines(data):
    """1-based line numbers that fall strictly inside a multi-line string token (continuation lines)."""
    inside = set()
    try:
        for tok in tokenize.generate_tokens(io.StringIO(data.decode("utf-8", "replace")).readline):
            if tok.type == tokenize.STRING and tok.end[0] > tok.start[0]:
                inside.update(range(tok.start[0] + 1, tok.end[0] + 1))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return None   # cannot tokenize safely -> leave the whole file alone
    return inside


def strip_bytes(path, data):
    ext = os.path.splitext(path)[1]
    protected = set()
    if ext == ".py":
        protected = py_string_lines(data)
        if protected is None:
            return data, 0
    out, n = [], 0
    for i, line in enumerate(data.splitlines(keepends=True), 1):
        m = WS_ONLY.match(line)
        if m and i not in protected:
            out.append(m.group(1) if m.group(1) else b"")
            n += 1
        else:
            out.append(line)
    return b"".join(out), n


def tracked(root):
    r = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True)
    return [p for p in r.stdout.decode("utf-8", "replace").split("\0") if p]


def main():
    root = sys.argv[1]
    check = "--check" in sys.argv
    files = changed = lines = 0
    for rel in tracked(root):
        if os.path.splitext(rel)[1] not in EXTS or any(s in rel + "/" or rel.startswith(s) for s in SKIP_DIRS):
            continue
        p = os.path.join(root, rel)
        if not os.path.isfile(p) or os.path.islink(p) or os.path.getsize(p) > MAX_BYTES:
            continue
        data = open(p, "rb").read()
        if b"\0" in data[:4096]:
            continue
        files += 1
        new, n = strip_bytes(rel, data)
        # self-check: removing ALL whitespace from old and new must give identical bytes, i.e. the edit is whitespace-only
        # (a file ending in a whitespace-only line with no newline legitimately loses that line - still whitespace-only)
        if n and re.sub(rb"\s+", b"", new) != re.sub(rb"\s+", b"", data):
            print("SELF-CHECK FAILED, skipping %s" % rel, file=sys.stderr)
            continue
        if n and new != data:
            changed += 1
            lines += n
            if not check:
                open(p, "wb").write(new)
    print("files_scanned=%d files_changed=%d lines_stripped=%d%s" % (files, changed, lines, " (check only)" if check else ""))
    sys.exit(1 if (check and changed) else 0)


if __name__ == "__main__":
    main()
