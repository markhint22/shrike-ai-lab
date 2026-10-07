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

2026-10-02 - scout-guard mode (run_overnight.sh, between the scout and the implement call): the PLANNER can list a banned/oversize file in its
"FILES:" even when the queue item itself is fine (xlite: item "tests/test_battle_persistence.gd - add a test" -> planner FILES: scripts/battle/battle.gd,
227KB -> 80k-token request vs a 65k context -> ContextWindowExceededError 4 cycles running). Same banned_list/prefix + size rules as above:
  ovn_park_unworkable.py --scout-guard <repo_root> <max_bytes> <item_text_file>   (candidate tokens, one per line, on stdin)
      stdout: "DROP<TAB><tok><TAB><why>" per dropped token, then "UNWORKABLE<TAB><why>" iff the item cannot proceed without a dropped file
  ovn_park_unworkable.py --park-line <OVERNIGHT_PROGRESS.md> <line_no> <why>
      tags that one open line "[CLAUDE] [unworkable: <why>]" (same tag format as the sweep); prints PARKED=1|0
"""
import os
import re
import sys

PARKED_RE = re.compile(r"AUTO-SKIP|HUMAN-ONLY|human/|\[CLAUDE\]|BLOCKED|\(retired-", re.I)
PATH_RE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}")
# same "file-shaped" test as run_overnight.sh's _ovn_candidate_tokens: a path separator or a recognised code/doc extension ("datetime.now" is not a file)
FILEISH_RE = re.compile(r"/|\.(py|ts|tsx|js|jsx|vue|gd|kt|java|go|rb|rs|c|cpp|h|hpp|ya?ml|json|toml|cfg|ini|sh|txt|xml|gradle|properties|env)$")
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


def scout_guard(root, tokens, item_text, max_bytes):
    """-> (dropped [(tok, why)], unworkable_why or None). Pure; tokens = every path the scout/plan wants force-loaded."""
    banned = banned_list(root)
    dropped, kept = [], []
    for tok in tokens:
        tok = tok.strip()
        if not tok or tok.endswith(".md"):
            continue
        why = _check(tok, root, banned, max_bytes)
        if why:
            dropped.append((tok, why))
        elif FILEISH_RE.search(tok):
            kept.append((tok, why))
    if not dropped:
        return [], None
    dropped_toks = {t for t, _ in dropped}
    # the item's own target = first path token of the item text that exists on disk (same rule as why_unworkable)
    target = None
    for tok in PATH_RE.findall(item_text or ""):
        if not tok.endswith(".md") and os.path.isfile(os.path.join(root, tok)):
            target = tok
            break
    if target in dropped_toks:
        return dropped, dict(dropped)[target]
    # nothing workable left: no surviving file-shaped candidate (an existing small file, or a not-yet-created one aider can create)
    if not [t for t, _ in kept]:
        return dropped, dropped[0][1]
    return dropped, None


def park_line(prog, lineno, why):
    lines = open(prog, encoding="utf-8").read().split("\n")
    i = lineno - 1
    if not (0 <= i < len(lines)) or not lines[i].startswith("- [ ] ") or PARKED_RE.search(lines[i]):
        return 0
    lines[i] = "- [ ] [CLAUDE] [unworkable: %s] %s" % (why, lines[i][len("- [ ] "):])
    open(prog, "w", encoding="utf-8").write("\n".join(lines))
    return 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--scout-guard":
        root, max_bytes, item_file = sys.argv[2], int(sys.argv[3]), sys.argv[4]
        try:
            item = open(item_file, encoding="utf-8").read()
        except OSError:
            item = ""
        dropped, why = scout_guard(root, sys.stdin.read().split(), item, max_bytes)
        for tok, w in dropped:
            print("DROP\t%s\t%s" % (tok, w))
        if why:
            print("UNWORKABLE\t%s" % why)
        return
    if len(sys.argv) >= 2 and sys.argv[1] == "--park-line":
        print("PARKED=%d" % park_line(sys.argv[2], int(sys.argv[3]), sys.argv[4]))
        return
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
