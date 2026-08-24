#!/usr/bin/env python3
"""Remove exact duplicate GDScript function definitions.

Written 2026-08-24 after xlite's TurnManager.get_phase_display_name() was
independently re-duplicated by 4 separate overnight cycles (each producing a
BYTE-IDENTICAL copy of the function) - each occurrence broke GDScript
parsing project-wide, since duplicate function names in one class are a
compile error, and TurnManager is a class_name global referenced by many
other scripts. Doc-instruction fixes and even prior automated commits
fixing ONE occurrence didn't stop the NEXT cycle from reintroducing it, so
this is a small mechanical guard. Compares every function to every
same-named function seen earlier in the file, not just the immediately
preceding one - a real case had the duplicates interleaved (fn_a, fn_b,
fn_a again, fn_b again) rather than back-to-back. Only removes a later
occurrence when its body is byte-identical to an earlier one; a genuine
semantic conflict (same name, different body) is left alone and reported,
never auto-resolved.

Usage: dedupe_gd_duplicate_functions.py <file.gd>
Prints "unchanged" (file untouched) or "removed duplicate(s): <names>".
"""
import re
import sys

FUNC_RE = re.compile(r"^(?:static )?func (\w+)\(")
DOC_RE = re.compile(r"^##")


def find_units(lines):
    """Return list of (name, start, end) - start/end both include each
    unit's own leading doc-comment, so end is the NEXT unit's doc-comment
    start (not its bare `func` line) - otherwise a unit's trailing slice
    would swallow the next unit's doc-comment, corrupting body comparison.
    """
    starts = [i for i, line in enumerate(lines) if FUNC_RE.match(line)]
    doc_starts = []
    names = []
    for start in starts:
        doc_start = start
        while doc_start > 0 and DOC_RE.match(lines[doc_start - 1]):
            doc_start -= 1
        doc_starts.append(doc_start)
        names.append(FUNC_RE.match(lines[start]).group(1))

    units = []
    for idx, doc_start in enumerate(doc_starts):
        end = doc_starts[idx + 1] if idx + 1 < len(doc_starts) else len(lines)
        units.append((names[idx], doc_start, end))
    return units


def trimmed(lines, start, end):
    chunk = lines[start:end]
    while chunk and chunk[-1].strip() == "":
        chunk.pop()
    return chunk


def dedupe(text):
    lines = text.splitlines()
    units = find_units(lines)
    if len(units) < 2:
        return None, []

    seen_bodies = {}  # name -> first-occurrence trimmed body
    keep = []
    removed = []
    for name, start, end in units:
        body = trimmed(lines, start, end)
        if name in seen_bodies:
            if body == seen_bodies[name]:
                removed.append(name)
                continue  # drop this unit - exact duplicate of an earlier one
            # Same name, different body - a real conflict. Leave both
            # occurrences in place untouched; don't guess which is right.
        else:
            seen_bodies[name] = body
        keep.append((start, end))

    if not removed:
        return None, []

    preamble_end = units[0][1]
    out_lines = lines[:preamble_end]
    for start, end in keep:
        out_lines.extend(lines[start:end])

    result = "\n".join(out_lines)
    if not result.endswith("\n"):
        result += "\n"
    return result, removed


def main():
    if len(sys.argv) != 2:
        print("usage: dedupe_gd_duplicate_functions.py <file.gd>", file=sys.stderr)
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
