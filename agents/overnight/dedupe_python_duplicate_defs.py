#!/usr/bin/env python3
"""Remove exact duplicate top-level Python class/function definitions.

Written 2026-08-25 after test-automation-agent's
`TestOrchestratorExecutePhaseIntegration` test class was independently
re-added, byte-identical, by 2 SEPARATE overnight cycles two apart (added
in one cycle, re-added verbatim two cycles later) - Python silently lets a
later definition shadow an earlier same-named one at module scope, so the
first copy just became dead, invisible-to-pytest code rather than a
parse error (unlike the GDScript case this mirrors, where a duplicate is a
hard compile error). Mirrors dedupe_gd_duplicate_functions.py's approach:
compares every top-level `class`/`def` block to every same-name-and-kind
block seen earlier in the file (not just the adjacent one), and removes a
later occurrence only when its body is byte-identical to an earlier one -
a genuine same-name-different-body conflict is left alone and reported,
never auto-resolved.

Only considers column-0 (unindented) `class Name` / `def name(` lines as
block boundaries - this targets exactly the observed failure shape (whole
top-level test classes/functions re-added), not indented methods inside a
class, which is a different (and so far unobserved) risk.

Usage: dedupe_python_duplicate_defs.py <file.py>
Prints "unchanged" (file untouched) or "removed duplicate(s): <names>".
"""
import re
import sys

DEF_RE = re.compile(r"^(class|def)\s+(\w+)")


def find_units(lines):
    """Return list of (kind, name, start, end)."""
    starts = []
    for i, line in enumerate(lines):
        m = DEF_RE.match(line)
        if m:
            starts.append((i, m.group(1), m.group(2)))

    units = []
    for idx, (start, kind, name) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        units.append((kind, name, start, end))
    return units


def trimmed(lines, start, end):
    chunk = lines[start:end]
    while chunk and chunk[0].strip() == "":
        chunk = chunk[1:]
    while chunk and chunk[-1].strip() == "":
        chunk = chunk[:-1]
    return chunk


def dedupe(text):
    lines = text.splitlines()
    units = find_units(lines)
    if len(units) < 2:
        return None, []

    seen_bodies = {}  # (kind, name) -> first-occurrence trimmed body
    decisions = []  # True = keep, False = drop, one per unit in file order
    removed = []
    for kind, name, start, end in units:
        key = (kind, name)
        body = trimmed(lines, start, end)
        if key in seen_bodies and body == seen_bodies[key]:
            decisions.append(False)
            removed.append(name)
            continue  # exact duplicate of an earlier same-name unit
        # Either the first occurrence, or a same-name conflict with a
        # DIFFERENT body - keep both in that case rather than guess.
        if key not in seen_bodies:
            seen_bodies[key] = body
        decisions.append(True)

    if not removed:
        return None, []

    # Walk every original unit in order: the gap between consecutive units
    # (any content outside a unit's own start:end range - blank lines,
    # comments, module-level statements) is always preserved regardless of
    # keep/drop, and only a DROPPED unit's own line range is omitted - this
    # keeps the diff minimal instead of reformatting untouched spacing.
    out = list(lines[: units[0][2]])
    for i, (kind, name, start, end) in enumerate(units):
        if i > 0:
            out.extend(lines[units[i - 1][3] : start])
        if decisions[i]:
            out.extend(lines[start:end])
    out.extend(lines[units[-1][3] :])

    while out and out[-1].strip() == "":
        out.pop()
    result = "\n".join(out)
    if not result.endswith("\n"):
        result += "\n"
    return result, removed


def main():
    if len(sys.argv) != 2:
        print("usage: dedupe_python_duplicate_defs.py <file.py>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    with open(path, "r") as f:
        original = f.read()

    merged, removed = dedupe(original)
    if merged is None or merged == original:
        print("unchanged")
        return

    with open(path, "w") as f:
        f.write(merged)
    print("removed duplicate(s): " + ", ".join(removed))


if __name__ == "__main__":
    main()
