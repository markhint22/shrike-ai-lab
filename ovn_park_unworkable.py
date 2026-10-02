#!/usr/bin/env python3
"""ovn_park_unworkable.py — park open items the 27B can NEVER land, before a cycle wastes itself on them.

Two measured dead ends (xlite, 2026-09-30: 0 landed all day, ContextWindowExceededError every attempt):
  * the item's target file is on the repo's .queue-hard-banned-files list (a commit touching it is discarded), or
  * the target file is so big that pre-loading it overflows the model context (scripts/battle/battle.gd = 227KB
    ~ 65k tokens vs a 55k usable window): every attempt dies with a context error, no code is ever tried.
Such an item is tagged `[CLAUDE] [unworkable: <why>]` in place, so every doable-item filter skips it and
ovn_park_sweep.py relocates it. Pure text edit, no LLM. Delete-only items are left alone (the delete executor
never loads the file into the model).

usage: ovn_park_unworkable.py <OVERNIGHT_PROGRESS.md> <repo_root> [max_bytes=120000]
prints PARKED=<n>
"""
import os
import re
import sys

PARKED_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|human/|\[CLAUDE\]|BLOCKED|\(retired-", re.I)
PATH_RE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}")
DELETE_RE = re.compile(r"—\s*(delete|remove)\b", re.I)


def banned_list(root):
    out = []
    try:
        for ln in open(os.path.join(root, ".queue-hard-banned-files"), encoding="utf-8"):
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                out.append(ln)
    except OSError:
        pass
    return out


def _check(tok, root, banned, max_bytes):
    path = os.path.join(root, tok)
    if tok.endswith(".md") or not os.path.isfile(path):
        return None
    for b in banned:
        if tok == b or tok.startswith(b):
            return "hard-banned file %s" % tok
    size = os.path.getsize(path)
    if size > max_bytes:
        return "%s is %dKB (~%dk tokens) - exceeds the model context" % (tok, size // 1024, size // 3500)
    return None


def why_unworkable(line, root, banned, max_bytes):
    # 2026-10-02: an item that lists "FILES: a, b" gets EVERY listed file added to the aider chat, so any one of them being banned/too big makes the
    # item unworkable even when the first path in the text is small (xlite: "tests/test_battle_persistence.gd ... FILES: scripts/battle/battle.gd" was
    # never parked and overflowed the 65k context 4 cycles in a row).
    if "FILES:" in line:
        for tok in PATH_RE.findall(line.split("FILES:", 1)[1]):
            why = _check(tok, root, banned, max_bytes)
            if why:
                return why
    for tok in PATH_RE.findall(line):
        if tok.endswith(".md"):
            continue
        path = os.path.join(root, tok)
        if not os.path.isfile(path):
            continue
        for b in banned:
            if tok == b or tok.startswith(b):
                return "hard-banned file %s" % tok
        size = os.path.getsize(path)
        if size > max_bytes:
            return "%s is %dKB (~%dk tokens) - exceeds the model context" % (tok, size // 1024, size // 3500)
        return None  # only the first existing target path counts
    return None


def main():
    prog, root = sys.argv[1], sys.argv[2]
    max_bytes = int(sys.argv[3]) if len(sys.argv) > 3 else 120000
    banned = banned_list(root)
    lines = open(prog, encoding="utf-8").read().split("\n")
    n = 0
    for i, ln in enumerate(lines):
        if not ln.startswith("- [ ] ") or PARKED_RE.search(ln) or DELETE_RE.search(ln):
            continue
        why = why_unworkable(ln, root, banned, max_bytes)
        if why:
            lines[i] = "- [ ] [CLAUDE] [unworkable: %s] %s" % (why, ln[len("- [ ] "):])
            n += 1
    if n:
        open(prog, "w", encoding="utf-8").write("\n".join(lines))
    print("PARKED=%d" % n)


if __name__ == "__main__":
    main()
