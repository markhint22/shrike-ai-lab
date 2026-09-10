#!/usr/bin/env python3
"""Merge duplicate top-level "## " markdown section headers in-place, and
collapse adjacent duplicate "- " bullet entries.

Written 2026-08-24 because xlite's OVERNIGHT_PROGRESS.md kept accumulating a
second/third "## Decisions Made" header - each overnight aider cycle tends to
append near wherever it last edited (often near the bottom, after
"## Completed"), rather than scrolling up to find the existing header near
the top of the file. An in-doc instruction telling the model not to do this
was tried first and failed twice within two cycles, so this merges
duplicate same-titled sections back into one automatically, in first-seen
order, content concatenated in encounter order - no reliance on the model's
compliance.

Extended later the same day: once dedupe_gd_duplicate_functions.py started
auto-collapsing duplicate function definitions back to one clean copy, each
duplication ATTEMPT still left its own identical Decisions Made bullet line
behind (that script only touches .gd files) - two real, back-to-back
occurrences of this were fixed by hand before adding this pass. Only
collapses bullets that are directly ADJACENT and byte-identical (matching
every real case seen so far); a non-adjacent or non-identical repeat is left
alone, same conservative posture as the header merge and the GDScript fix.

Usage: dedupe_progress_headers.py <file>
Prints "unchanged" if nothing needed changing, or a comma-joined summary of
what changed (header title(s) merged and/or bullet count collapsed).
"""
import re
import sys

HEADER_RE = re.compile(r"^## (?!#)(.*)$")
BULLET_RE = re.compile(r"^- ")


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


def dedupe_bullets(text):
    """Drop any bullet block that's byte-identical to an EARLIER one in the
    same file, not just the immediately adjacent one - a real case had 4
    unrelated entries sitting between two exact-duplicate lines. Matching is
    strict byte-equality on the whole block, so this only ever catches a
    genuine re-log of the same event, never two merely-similar entries.
    """
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if BULLET_RE.match(line)]
    if len(starts) < 2:
        return None, 0

    blocks = []  # (start, end)
    for idx, start in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        # A block also ends early at a header line (bullets never span a
        # "## " boundary in this doc's convention).
        for k in range(start + 1, end):
            if HEADER_RE.match(lines[k]):
                end = k
                break
        blocks.append((start, end))

    keep = [True] * len(blocks)
    seen = set()
    removed = 0
    for i, (start, end) in enumerate(blocks):
        body = tuple(lines[start:end])
        if body in seen:
            keep[i] = False
            removed += 1
        else:
            seen.add(body)

    if not removed:
        return None, 0

    # Reconstruct by walking every ORIGINAL block in order: the gap between
    # consecutive blocks (any legitimate non-bullet content, e.g. a header)
    # is always preserved regardless of keep/drop, and only a dropped
    # block's own lines are omitted.
    out = list(lines[: blocks[0][0]])
    for i, (start, end) in enumerate(blocks):
        if i > 0:
            out.extend(lines[blocks[i - 1][1] : start])
        if keep[i]:
            out.extend(lines[start:end])
    out.extend(lines[blocks[-1][1] :])

    result = "\n".join(out)
    if not result.endswith("\n"):
        result += "\n"
    return result, removed


def main():
    if len(sys.argv) != 2:
        print("usage: dedupe_progress_headers.py <file>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    with open(path, "r") as f:
        original = f.read()

    changes = []
    current = original

    merged, dup_titles = dedupe(current)
    if merged is not None and merged != current:
        current = merged
        changes.append("merged headers: " + ", ".join(dup_titles))

    bullet_merged, removed_count = dedupe_bullets(current)
    if bullet_merged is not None and bullet_merged != current:
        current = bullet_merged
        changes.append(f"collapsed {removed_count} duplicate bullet line(s)")

    if not changes:
        print("unchanged")
        return

    with open(path, "w") as f:
        f.write(current)
    print("; ".join(changes))


if __name__ == "__main__":
    main()
