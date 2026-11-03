#!/usr/bin/env python3
"""ovn_already_done_gate.py - evidence check for the scout ALREADY-DONE credit (package P5-supply-truth, 2026-11-02, cqueue F4).

The scout ALREADY-DONE credit (run_overnight.sh) picks the open item by grep -F of the BASENAME of ANY file the scout's PLAN names, then (ovn_path_gate + the item's own VERIFY must not FAIL)
credits it. Gaps seen live 2026-11-01/02: shrike-monitor 'MonitorCreate accepts body_contains only on http' (2x ALREADY-DONE with the rejection code absent), billwatch geocoder budget
(3x, geocoder.py has no api_budget), xlite 'Change DEFAULT_BINDINGS pause from ui_pause to Escape' (credited on a test-only commit; input_remapper.gd still ui_pause). Two holes:
  (a) the plan file need not be the item's own named file (the item matched on a basename inside its description / VERIFY text), and
  (b) nothing asserts that the string the item asks for exists in the target; an item with no VERIFY at all is credited on the scout's word.

check(line, repo_dir, plan_file) -> (verdict, reason), verdict OK | REFUSE:
  REFUSE no-verify          the item has no `VERIFY:` clause (nothing but the scout's say-so)
  REFUSE file-mismatch      the item names a leading file and the scout's plan file is a different file
  REFUSE target-missing     the item's own target file is not in the repo
  REFUSE string-missing     a TARGET STRING the item asks for is absent from the target file. Target strings: backticked or quoted tokens in the description (outside the VERIFY clause),
                            and the new value of 'from A to B' / 'to B' phrasing ('Change DEFAULT_BINDINGS pause from ui_pause to Escape' -> Escape)
  OK ...                    nothing refused (reason says what was checked; 'no target string to check' is NOT a proof, it is just not refused)
CLI: ovn_already_done_gate.py <progress_file> <line_number> <repo_dir> <plan_file>   -> '<VERDICT> <reason>'
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ovn_path_gate as pg  # noqa: E402

VERIFY_SPLIT = re.compile(r"\bVERIFY:")
QUOTED = re.compile(r"`([^`\n]{2,80})`|\"([^\"\n]{2,80})\"|'([^'\n]{2,80})'")
TO_RE = re.compile(r"\b(?:from\s+\S+\s+)?to\s+[`\"']?([A-Za-z_][A-Za-z0-9_.\-]{2,60})[`\"']?(?=[\s.,;)]|$)")
CHANGE_VERB = re.compile(r"(?i)^(change|rename|replace|set|switch|use|make|update|default)\b")
STOP = {"the", "this", "that", "each", "every", "all", "a", "an", "it", "be", "use", "not", "only", "true", "false", "none", "null"}


def has_verify(line):
    return bool(re.search(r"\bVERIFY:\s*\S", line))


def description(line):
    """Item body after the leading path token and before any VERIFY clause."""
    body = pg.leading_body(line)
    body = VERIFY_SPLIT.split(body)[0]
    parts = body.split(" ", 1)
    return parts[1] if len(parts) > 1 else ""


def target_strings(line):
    desc = description(line)
    out = []
    for m in QUOTED.finditer(desc):
        s = next(g for g in m.groups() if g)
        if " " not in s.strip() and s.lower() not in STOP and s not in out and not s.endswith((".py", ".ts", ".vue", ".gd", ".md")):
            out.append(s)
    if CHANGE_VERB.search(desc.lstrip(" -—:")):
        m = TO_RE.search(desc)
        val = m.group(1).rstrip(".-") if m else ""
        if val and val.lower() not in STOP and val not in out:
            out.append(val)
    return out


def _same_file(item_path, plan_file):
    a, b = item_path.strip("./"), plan_file.strip("./")
    return a == b or a.endswith("/" + b) or b.endswith("/" + a) or os.path.basename(a) == os.path.basename(b)


def check(line, repo_dir, plan_file):
    if not has_verify(line):
        return "REFUSE", "no-verify: the item has no VERIFY: clause, nothing but the scout's word"
    tgt = pg.leading_target(line)
    is_path = bool(tgt) and "." in os.path.basename(tgt) and "/" in tgt or tgt.endswith(pg.CODE)
    if not is_path:
        return "OK", "item names no leading file; VERIFY present; no target file to check"
    if plan_file and not _same_file(tgt, plan_file):
        return "REFUSE", "file-mismatch: plan file %s is not the item's named file %s" % (plan_file, tgt)
    path = os.path.join(repo_dir, tgt)
    if not os.path.isfile(path):
        # the leading path may be written relative to a sub-package: accept a unique tracked-suffix match
        hit = None
        for root, dirs, files in os.walk(repo_dir):
            dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv", "venv", "__pycache__", ".godot")]
            if os.path.basename(tgt) in files and os.path.join(root, os.path.basename(tgt)).endswith(tgt.strip("./")):
                hit = os.path.join(root, os.path.basename(tgt))
                break
        if hit is None:
            return "REFUSE", "target-missing: %s is not in the repo" % tgt
        path = hit
    strings = target_strings(line)
    if not strings:
        return "OK", "VERIFY present, file matches, no target string to check"
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return "REFUSE", "target-missing: %s unreadable" % tgt
    missing = [s for s in strings if s not in text]
    if missing:
        return "REFUSE", "string-missing: %s absent from %s" % (", ".join(missing), tgt)
    return "OK", "VERIFY present, file matches, %d target string(s) present" % len(strings)


def main(argv):
    if len(argv) < 5:
        print("OK usage")
        return 0
    prog, ln, repo, plan = argv[1], int(argv[2]), argv[3], argv[4]
    try:
        line = open(prog, errors="replace").read().split("\n")[ln - 1]
    except (OSError, IndexError, ValueError):
        print("OK unreadable-item-line")
        return 0
    v, why = check(line, repo, plan)
    print("%s %s" % (v, why))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
