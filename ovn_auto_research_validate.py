#!/usr/bin/env python3
"""Validate + normalise a research agent's proposed roadmap lines before they are appended.

The research agent is a headless LLM; its output is untrusted input to the fleet's planner.
ovn_planner.sh only picks up lines matching  ^- \\[ \\] \\[P[1-4]\\] \\[ready\\]  so anything
off-format would sit inert, and a duplicate of an existing feature would waste a planner pass.

usage: ovn_auto_research_validate.py <proposed.md> <existing_roadmap.md> [max_items=12]
stdout: the accepted lines (normalised: status forced to [ready], one line each)
stderr: one "reject: <reason>: <title>" line per dropped item, and a final "accepted N/M" line.
exit 0 always (zero accepted is a valid outcome: an infra repo can be genuinely complete).
"""
import re
import sys

LINE_RE = re.compile(
    r"^- \[ \] \[P([1-4])\] \[(?:ready|decomposed|needs-decompose|needs-research)\] "
    r"(?P<title>[^—]{3,400}?) — (?P<body>.+?) (?P<meta>\{cat: [^}]+\})\s*$"
)
# an item must point at real code: a path-ish token with a known extension
PATHISH_RE = re.compile(r"[\w./-]+\.(?:py|ts|tsx|js|vue|gd|kt|swift|sh|sql|md|json|yml|yaml|toml|html)\b")
MAX_LEN = 1500


def norm(title):
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


def main():
    proposed, existing = sys.argv[1], sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    try:
        ex_text = open(existing, encoding="utf-8").read()
    except OSError:
        ex_text = ""
    ex_titles = set()
    for ln in ex_text.splitlines():
        m = re.match(r"^- \[[ x]\] \[P[1-4]\] \[[a-z-]+\] ([^—]+?)(?: — |$)", ln)
        if m:
            ex_titles.add(norm(m.group(1)))
    seen, out, total = set(), [], 0
    try:
        lines = open(proposed, encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    for ln in lines:
        if not ln.strip().startswith("- [ ]"):
            continue
        total += 1
        m = LINE_RE.match(ln.strip())
        if not m:
            sys.stderr.write("reject: bad format: %s\n" % ln[:80])
            continue
        title = m.group("title").strip()
        key = norm(title)
        if len(ln) > MAX_LEN:
            sys.stderr.write("reject: too long: %s\n" % title)
        elif key in ex_titles or key in seen:
            sys.stderr.write("reject: duplicate title: %s\n" % title)
        elif not PATHISH_RE.search(m.group("body")):
            sys.stderr.write("reject: cites no file path: %s\n" % title)
        elif len(out) >= cap:
            sys.stderr.write("reject: over cap: %s\n" % title)
        else:
            seen.add(key)
            out.append("- [ ] [P%s] [ready] %s — %s %s" % (m.group(1), title, m.group("body").strip(), m.group("meta")))
    for ln in out:
        print(ln)
    sys.stderr.write("accepted %d/%d\n" % (len(out), total))


if __name__ == "__main__":
    main()
