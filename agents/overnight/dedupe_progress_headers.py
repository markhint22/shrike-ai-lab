#!/usr/bin/env python3
"""Merge duplicate top-level "## " markdown section headers in-place.

Written 2026-08-24 because xlite's OVERNIGHT_PROGRESS.md kept accumulating a
second/third "## Decisions Made" header - each overnight aider cycle tends to
append near wherever it last edited (often near the bottom, after
"## Completed"), rather than scrolling up to find the existing header near
the top of the file. An in-doc instruction telling the model not to do this
was tried first and failed twice within two cycles, so this merges
duplicate same-titled sections back into one automatically, in first-seen
order, content concatenated in encounter order - no reliance on the model's
compliance.

Usage: dedupe_progress_headers.py <file>
Prints "unchanged" if there were no duplicates (file left untouched), or
"merged: <title1>, <title2>, ..." listing which header titles had
duplicates (file rewritten in place).
"""
import re
import sys

HEADER_RE = re.compile(r"^## (?!#)(.*)$")


def dedupe(text):
    lines = text.splitlines()
    first_header_idx = next(
        (i for i, line in enumerate(lines) if HEADER_RE.match(line)), len(lines)
    )
    preamble = lines[:first_header_idx]

    sections = []  # list of (title, content_lines)
    i = first_header_idx
    while i < len(lines):
        m = HEADER_RE.match(lines[i])
        title = m.group(1).strip()
        j = i + 1
        while j < len(lines) and not HEADER_RE.match(lines[j]):
            j += 1
        sections.append((title, lines[i + 1 : j]))
        i = j

    order = []
    buckets = {}
    dup_titles = []
    seen_counts = {}
    for title, content in sections:
        # Trim blank lines from each occurrence's own edges before merging,
        # so concatenating occurrence N's tail directly against occurrence
        # N+1's head matches this doc convention's back-to-back bullet
        # lists (no blank line between entries) instead of leaving a stray
        # blank line in the middle of the merged list.
        while content and content[0].strip() == "":
            content = content[1:]
        while content and content[-1].strip() == "":
            content = content[:-1]
        if title not in buckets:
            buckets[title] = []
            order.append(title)
        else:
            seen_counts[title] = seen_counts.get(title, 1) + 1
            if title not in dup_titles:
                dup_titles.append(title)
        buckets[title].extend(content)

    if not dup_titles:
        return None, []

    out = list(preamble)
    for idx, title in enumerate(order):
        content = buckets[title]
        while content and content[-1].strip() == "":
            content.pop()
        out.append(f"## {title}")
        out.extend(content)
        if idx != len(order) - 1:
            out.append("")

    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n", dup_titles


def main():
    if len(sys.argv) != 2:
        print("usage: dedupe_progress_headers.py <file>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    with open(path, "r") as f:
        original = f.read()

    merged, dup_titles = dedupe(original)
    if merged is None or merged == original:
        print("unchanged")
        return

    with open(path, "w") as f:
        f.write(merged)
    print("merged: " + ", ".join(dup_titles))


if __name__ == "__main__":
    main()
