#!/usr/bin/env python3
"""Runner-owned OVERNIGHT_PROGRESS.md bookkeeping (2026-08-25 Tier-1 hardening).

The local model is unreliable at maintaining its own progress doc — it re-adds
done items, duplicates section headers, renumbers wrong, and burns its whole
token budget on doc surgery instead of code. So it no longer edits the doc at
all; it declares outcomes as trailer lines in its COMMIT MESSAGE, and this
script does the (deterministic, minimal) doc edit after a verified push.

Recognised commit-message trailers (case-insensitive, one per line, anywhere in
the message; a leading "- " is tolerated):

    DONE: <text of the Next Steps item that was completed>
    DECISION: <one line: what was decided and why>
    NEW: <one short new Next Steps item to add>

Design posture — SAFE BY DEFAULT, mirrors the conservative dedupe_*.py scripts:
  * Only ever marks-in-place or appends. NEVER restructures sections, renumbers,
    moves content between sections, or rewrites existing item text.
  * DONE matches an existing open item only on a STRONG normalized match; an
    ambiguous/weak match is skipped and reported, never guessed (guessing could
    mark the wrong item done). Unmatched DONE text is appended as a recorded
    completed item rather than dropped (covers autonomous new work).
  * Preserves the doc's existing done-style (strikethrough for numbered items,
    [x] for checkbox items) rather than imposing one format on a human-curated
    doc. New items are added as GFM `- [ ]` checkboxes.
  * Idempotent: re-running with the same trailers produces no further change.

Usage:  git log --format=%B <before>..<after> | update_progress.py <doc.md>
Prints one line: a summary of what changed, or exactly "unchanged".
Exit status is always 0 unless the doc path is unreadable (so the runner can
treat a bookkeeping hiccup as non-fatal).
"""
import datetime
import re
import sys

ITEM_START = re.compile(r'^\s*(?:\d+\.|[-*]\s*\[[ xX]\]|[-*])\s+')
CHECKBOX_OPEN = re.compile(r'^(\s*[-*]\s*)\[\s\](\s+)')
DONE_MARKERS = ('~~', '✅', '[x]', '[X]')


def normalize(text):
    """Collapse an item/trailer to a comparable key: strip markdown, list
    markers, done-annotations, dates, punctuation; lowercase; single-space."""
    t = text
    t = re.sub(r'✅.*$', '', t)              # drop "✅ Done ..." tail
    t = re.sub(r'\bdone\b.*$', '', t, flags=re.I)
    t = re.sub(r'\d{4}-\d{2}-\d{2}', '', t)      # dates
    t = t.replace('~~', '').replace('**', '').replace('`', '')
    t = re.sub(r'^\s*(?:\d+\.|[-*]\s*\[[ xX]\]|[-*])\s+', '', t)  # list marker
    t = re.sub(r'[^a-z0-9 ]+', ' ', t.lower())
    return re.sub(r'\s+', ' ', t).strip()


def token_overlap(a, b):
    sa, sb = set(a.split()), set(b.split())
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def parse_trailers(commit_text):
    """Return (dones, decisions, news) from the commit message stream."""
    dones, decisions, news = [], [], []
    for raw in commit_text.splitlines():
        line = raw.strip()
        line = re.sub(r'^[-*]\s+', '', line)     # tolerate "- DONE:"
        m = re.match(r'(?i)^(done|decision|new)\s*:\s*(.+)$', line)
        if not m:
            continue
        kind, val = m.group(1).lower(), m.group(2).strip()
        if not val:
            continue
        if kind == 'done':
            dones.append(val)
        elif kind == 'decision':
            decisions.append(val)
        else:
            news.append(val)
    return dones, decisions, news


def find_section_bounds(lines, title):
    """Return (header_idx, body_start, body_end_exclusive) for a '## <title>'
    section, or None. body_end is the next '## ' header or EOF."""
    header_idx = None
    for i, ln in enumerate(lines):
        if re.match(r'^##\s+' + re.escape(title) + r'\s*$', ln.strip()):
            header_idx = i
            break
    if header_idx is None:
        return None
    end = len(lines)
    for j in range(header_idx + 1, len(lines)):
        if re.match(r'^##\s+', lines[j]):
            end = j
            break
    return header_idx, header_idx + 1, end


def item_spans(lines, start, end):
    """Yield (item_start_idx, item_end_idx_exclusive) for each list item in
    [start, end). An item spans from its marker line up to the next marker line
    or a blank-line-separated non-list block."""
    spans = []
    i = start
    cur = None
    while i < end:
        if ITEM_START.match(lines[i]):
            if cur is not None:
                spans.append((cur, i))
            cur = i
        i += 1
    if cur is not None:
        spans.append((cur, end))
    return spans


def is_done_item(first_line):
    return any(mk in first_line for mk in DONE_MARKERS)


def mark_done_in_place(lines, item_start):
    """Mark the item's first line done, preserving the doc's existing style."""
    line = lines[item_start]
    cb = CHECKBOX_OPEN.match(line)
    if cb:
        lines[item_start] = CHECKBOX_OPEN.sub(r'\1[x]\2', line, count=1)
        return
    # numbered / bare-bullet item -> strikethrough + ✅ (the convention already
    # in these docs). Split marker from content, wrap the content only.
    m = ITEM_START.match(line)
    marker = m.group(0)
    content = line[len(marker):].rstrip()
    today = datetime.date.today().isoformat()
    lines[item_start] = f"{marker}~~{content}~~ ✅ Done {today}"


def main():
    if len(sys.argv) < 2:
        print("usage: update_progress.py <doc.md>  (commit messages on stdin)",
              file=sys.stderr)
        return 2
    path = sys.argv[1]
    try:
        with open(path, 'r', encoding='utf-8') as f:
            original = f.read()
    except OSError as e:
        print(f"cannot read {path}: {e}", file=sys.stderr)
        return 2

    commit_text = sys.stdin.read()
    dones, decisions, news = parse_trailers(commit_text)
    if not (dones or decisions or news):
        print("unchanged")
        return 0

    lines = original.split('\n')
    today = datetime.date.today().isoformat()
    changes = []

    ns = find_section_bounds(lines, 'Next Steps')

    # --- DONE matching. STRICT to avoid false-marking the wrong item when the
    #     list has near-identical siblings (e.g. seven "Delete .../X.py" items):
    #     a real match is an item whose normalized text is a UNIQUE exact
    #     substring of / superset of the DONE key, or a token-overlap winner
    #     that clears a high bar AND beats the runner-up by a clear margin.
    #     Anything ambiguous is SKIPPED and logged, never guessed. ---
    STRONG = 0.75      # token-overlap floor for a fuzzy match
    MARGIN = 0.15      # winner must beat runner-up by this much
    NEWWORK = 0.40     # below this against every item => genuinely new work

    def classify(spans, key, done_state):
        """Return ('exact-unique', idx) | ('exact-many', None) |
        ('fuzzy', idx) | ('weak', best_score) | ('none', 0.0)."""
        exact, scored = [], []
        for (s, _e) in spans:
            if is_done_item(lines[s]) != done_state:
                continue
            ik = normalize(lines[s])
            if not ik:
                continue
            if key in ik or ik in key:
                exact.append(s)
            else:
                scored.append((token_overlap(key, ik), s))
        if len(exact) == 1:
            return 'exact-unique', exact[0]
        if len(exact) > 1:
            return 'exact-many', None
        scored.sort(reverse=True)
        if scored and scored[0][0] >= STRONG and (
                len(scored) == 1 or scored[0][0] - scored[1][0] >= MARGIN):
            return 'fuzzy', scored[0][1]
        return ('weak', scored[0][0]) if scored else ('none', 0.0)

    for done in dones:
        key = normalize(done)
        if not key:
            continue
        spans = item_spans(lines, ns[1], ns[2]) if ns else []
        kind, val = classify(spans, key, False)
        if kind in ('exact-unique', 'fuzzy'):
            mark_done_in_place(lines, val)
            changes.append(f"marked done: {done[:60]}")
            continue
        if kind == 'exact-many':
            changes.append(f"SKIPPED ambiguous DONE (matches several items): "
                           f"{done[:50]}")
            continue
        # Not a confident open match. Is it an already-done item (idempotent
        # re-run, or the model re-declaring something already finished)?
        dkind, _dval = classify(spans, key, True)
        if dkind in ('exact-unique', 'exact-many', 'fuzzy'):
            continue  # already done — no-op
        # Neither open nor done matched confidently. Only RECORD it as new
        # work when it's clearly unrelated to every listed item; a middling
        # score means "probably an existing item, worded differently" — do NOT
        # guess and do NOT duplicate; skip and log for the supervisor/human.
        best_open = val if kind == 'weak' else 0.0
        if best_open >= NEWWORK:
            changes.append(f"SKIPPED unmatched DONE (ambiguous, ~{best_open:.2f}): "
                           f"{done[:50]}")
            continue
        comp = find_section_bounds(lines, 'Completed')
        target_end = comp[2] if comp is not None else (ns[2] if ns else None)
        if target_end is not None:
            lines.insert(target_end, f"- [x] {done} (done {today})")
            changes.append(f"recorded completed (no prior item): {done[:50]}")
            ns = find_section_bounds(lines, 'Next Steps')

    # --- NEW: append open checkbox items (dedup by normalized text). ---
    if news and ns:
        existing = {normalize(lines[s]) for (s, _e) in item_spans(lines, ns[1], ns[2])}
        insert_at = ns[2]
        added = 0
        for item in news:
            if normalize(item) in existing:
                continue
            lines.insert(insert_at + added, f"- [ ] {item}")
            existing.add(normalize(item))
            added += 1
            changes.append(f"added item: {item[:60]}")
        if added:
            ns = find_section_bounds(lines, 'Next Steps')

    # --- DECISION: append under ## Decisions Made (create if missing). ---
    if decisions:
        dm = find_section_bounds(lines, 'Decisions Made')
        if dm is None:
            if lines and lines[-1].strip() != '':
                lines.append('')
            lines.append('## Decisions Made')
            lines.append('')
            dm = find_section_bounds(lines, 'Decisions Made')
        existing = set()
        for k in range(dm[1], dm[2]):
            existing.add(normalize(lines[k]))
        insert_at = dm[2]
        added = 0
        for dec in decisions:
            if normalize(dec) in existing:
                continue
            lines.insert(insert_at + added, f"- {today}: {dec}")
            existing.add(normalize(dec))
            added += 1
            changes.append(f"recorded decision: {dec[:50]}")

    updated = '\n'.join(lines)
    if updated == original:
        print("unchanged")
        return 0
    with open(path, 'w', encoding='utf-8') as f:
        f.write(updated)
    print("; ".join(changes) if changes else "updated")
    return 0


if __name__ == '__main__':
    sys.exit(main())
