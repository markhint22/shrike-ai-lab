#!/usr/bin/env python3
"""Validate + normalise a research agent's proposed roadmap lines before they are appended.

The research agent is a headless LLM; its output is untrusted input to the fleet's planner.
ovn_planner.sh only picks up lines matching  ^- \\[ \\] \\[P[1-4]\\] \\[ready\\]  so anything
off-format would sit inert, and a duplicate of an existing feature would waste a planner pass.

usage: ovn_auto_research_validate.py <proposed.md> <existing_roadmap.md> [max_items=12]
stdout: the accepted lines (normalised: status forced to [ready], one line each)
stderr: one "reject: <reason>: <title>" line per dropped item, and a final "accepted N/M" line.
exit 0 always (zero accepted is a valid outcome: an infra repo can be genuinely complete).

       ovn_auto_research_validate.py --open-titles <roadmap.md> [backlog.md]
stdout: one "- <title>" line per OPEN feature (roadmap [ready]/[needs-*] lines + backlog feature groups that still have an open item): the
        "do not repeat" list ovn_auto_research.sh puts in the research prompt.

2026-10-09: proposals that are MECHANICAL gaps (docstrings, comments, unused imports, missing return annotations, deleting dead stubs without a
callers analysis) are rejected - ovn_work_supply.py turns those into finished, red-before-checked items deterministically, and a Claude pass spent
on them is a wasted slot. OVN_AR_MECHANICAL_REJECT=off disables the check.
"""
import os
import re
import sys

LINE_RE = re.compile(
    r"^- \[ \] \[P([1-4])\] \[(?:ready|decomposed|needs-decompose|needs-research)\] "
    r"(?P<title>[^—]{3,400}?) — (?P<body>.+?) (?P<meta>\{cat: [^}]+\})\s*$"
)
# an item must point at real code: a path-ish token with a known extension
PATHISH_RE = re.compile(r"[\w./-]+\.(?:py|ts|tsx|js|vue|gd|kt|swift|sh|sql|md|json|yml|yaml|toml|html)\b")
MAX_LEN = 1500

# Mechanical-gap patterns are matched against the TITLE only: a real bug item may legitimately mention a docstring/comment in its body
# ("...contradicting its own '(idempotent)' docstring").
_I = re.IGNORECASE
MECH_PATTERNS = [
    re.compile(r"\b(add|write|fill in|backfill|document|missing|improve|expand)\b[^—]{0,60}\bdocstrings?\b|^docstrings?\b", _I),
    # comments: only CODE comments. "Add comments and ratings to channel pages" / "Add per-episode comments endpoint" are user-visible features.
    re.compile(r"\b(add|write|improve|expand|update)\b[^—]{0,40}\b(doc|code|inline|explanatory|header)\s+comments?\b"
               r"|\b(add|write)\s+(brief |short |explanatory |clarifying )?comments?\s+(explaining|describing|documenting|clarifying)\b", _I),
    # "Add comments to the watch module" (comments on CODE: a module/file/function/class/helper), as opposed to user-visible comment features on pages/endpoints.
    re.compile(r"\b(add|write)\s+(brief |short |some |inline )?comments?\s+(to|in|for|on)\s+(the\s+)?[\w./-]*\s*(modules?|files?|functions?|classes|class|helpers?|methods?)\b", _I),
    # "Remove duplicate channels on M3U playlist import" is a user-visible feature (singular 'import' = the import FEATURE); only the plural / 'import statement' forms are code hygiene.
    re.compile(r"\bunused imports?\b|\b(clean\s?up|tidy( up)?)\b[^—]{0,30}\bimports\b|\bremove\b[^—]{0,40}\bimports\b|\bremove\b[^—]{0,40}\bimport (statements?|lines?)\b|\bimport (cleanup|sorting|ordering)\b|\bsort imports\b", _I),
    re.compile(r"\breturn[- ](type )?(annotation|hint)s?\b|\bmissing (type )?(annotation|hint)s?\b|\badd(ing)? (missing )?(return )?(type )?(annotations?|hints?)\b|->\s*(None|void)\b", _I),
]
# Only dead-CODE nouns: "Delete empty playlists", "Remove unused refresh tokens", "Drop unused column" are behaviour/data changes, not dead-stub deletes.
DEAD_DELETE_RE = re.compile(
    r"\b(delete|remove|drop|prune)\b[^—]{0,80}\b("
    r"(dead|unused|empty|leftover|never[- ]called)\s+(?:[\w./-]+\s+){0,3}?(code|stubs?|functions?|helpers?|methods?|classes|class|modules?|files?|constants?|predicates?|utils?|utilities)"
    r"|stubs?|never[- ]called)\b", _I)
CALLER_ANALYSIS_RE = re.compile(
    r"\bcallers?\b|\bcall[- ]?sites?\b|\bgrep\b|\breferenced by\b|\bno (non-test )?references?\b|\bzero (non-test )?(callers|references|call sites)\b|\bnothing (calls|imports)\b", _I)
# A real bug that merely touches an import / type hint / dead helper is NOT a mechanical gap. Consequence words in the TITLE ("... causing startup crash",
# "... cause 500 on /watch") or hard failure evidence in the BODY (a crash, traceback, 5xx, raised exception, ImportError, circular import) exempt the item:
# a false reject silently drops a bug, a false accept only costs one mediocre item (the near-dup / quality gates still apply).
# Tightened 2026-10-09 (round 3): bare numbers (a 5xx-looking line number or LOC count), bare "fail*", "raises", "startup", "bug", "cause" are NOT evidence - a docstring
# item whose body says "app/watch.py:512" or "documents what it raises" must stay rejected. Evidence = a concrete failing symptom: crash/traceback/uncaught exception,
# an HTTP 500-504 in an HTTP context (status/response/returns/5xx), a circular import, "fails to <verb>", "startup crash/failure".
_HTTP5 = r"(?:50[0-4])"
BUG_TITLE_RE = re.compile(
    r"\b(crash(es|ed|ing)?|broken|breaks|traceback|(uncaught|unhandled) exceptions?|circular imports?|regression|bugs? (in|where|when|causing)"
    r"|caus(es|ed|ing)|fails? (to|when|on|at|with)|failing (to|with|when)|fails? at (import|startup)"
    r"|startup (crash|failure|error)s?|crash(es)? (on|at) startup|5xx|internal server error"
    r"|http\s*" + _HTTP5 + r"|" + _HTTP5 + r"\s+(error|response|status|on|when|from|in)"
    r"|(returns?|gives?|throws?|raises?|yields?|responds? with)\s+(an?\s+)?(http\s*)?" + _HTTP5 + r")\b", _I)
BUG_BODY_RE = re.compile(
    r"\b(crash(es|ed|ing)?|traceback|(uncaught|unhandled) exceptions?|importerror|nameerror|attributeerror|circular imports?"
    r"|startup (crash|fail\w*)|fails? at (import|startup|runtime)|fails? to (start|import|load|boot)|5xx|internal server error"
    r"|(http|status( code)?|responds? with|response|returns?)\s*:?\s*(an?\s+)?(http\s*)?" + _HTTP5 + r"|" + _HTTP5 + r"\s+(error|response|internal))\b", _I)


def mechanical_gap(title, body):
    """True if the proposal is a mechanical gap the deterministic supply handles."""
    if os.environ.get("OVN_AR_MECHANICAL_REJECT", "on") == "off":
        return False
    if BUG_TITLE_RE.search(title) or BUG_BODY_RE.search(body):
        return False
    if any(p.search(title) for p in MECH_PATTERNS):
        return True
    return bool(DEAD_DELETE_RE.search(title) and not CALLER_ANALYSIS_RE.search(title + " " + body))


def norm(title):
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


STOP = {"the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are", "with", "from", "that", "this", "it", "by", "as", "at", "be", "add", "fix", "new"}


def words(text):
    return {w for w in norm(text).split() if len(w) > 2 and w not in STOP}


def paths(text):
    return set(PATHISH_RE.findall(text))


def near_dup(title, body, existing_items, thresh=0.5):
    """Same file cited AND substantially the same title words -> a re-worded duplicate (title-only dedupe misses these)."""
    tw, tp = words(title), paths(title + " " + body)
    if not tw or not tp:
        return False
    for ex_words, ex_paths in existing_items:
        if tp & ex_paths:
            union = tw | ex_words
            if union and len(tw & ex_words) / len(union) >= thresh:
                return True
    return False


HELD_RE = re.compile(r"HUMAN-ONLY|AUTO-SKIP|\(retired-")


def open_feature_titles(roadmap_text, backlog_text="", cap=40):
    """Titles of features that are still OPEN: roadmap [ready]/[needs-research]/[needs-decompose] lines, plus the backlog feature groups
    (`# --- 27B-decomposed from roadmap [date]: <title> (review + tweak) [feat:ID] ---`) that still have an open, un-held item tagged [feat:ID]."""
    titles = []
    for ln in roadmap_text.splitlines():
        m = re.match(r"^- \[ \] \[P[1-4]\] \[(?:ready|needs-research|needs-decompose)\] (.+?)(?: — |\s*\{cat:|$)", ln)
        if m:
            titles.append(m.group(1).strip())
    headers, open_ids = {}, []
    for ln in backlog_text.splitlines():
        m = re.match(r"^# --- 27B-decomposed from roadmap \[[^\]]*\]: (.*?) \(review \+ tweak\) \[feat:([^\]]+)\]", ln)
        if m:
            headers[m.group(2)] = m.group(1).split(" — ")[0].strip()
        elif ln.startswith("- [ ]") and not HELD_RE.search(ln):
            for fid in re.findall(r"\[feat:([^\]]+)\]", ln):
                if fid not in open_ids:
                    open_ids.append(fid)
    for fid in open_ids:
        titles.append(headers.get(fid) or fid)
    seen, out = set(), []
    for t in titles:
        k = norm(t)
        if k and k not in seen:
            seen.add(k)
            out.append(t[:140])
    return out[:cap]


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--open-titles":
        def rd(p):
            try:
                return open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                return ""
        for t in open_feature_titles(rd(sys.argv[2]), rd(sys.argv[3]) if len(sys.argv) > 3 else ""):
            print("- " + t)
        return
    proposed, existing = sys.argv[1], sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    try:
        ex_text = open(existing, encoding="utf-8").read()
    except OSError:
        ex_text = ""
    ex_titles, ex_items = set(), []
    for ln in ex_text.splitlines():
        m = re.match(r"^- \[[ x]\] \[P[1-4]\] \[[a-z-]+\] ([^—]+?)(?: — |$)", ln)
        if m:
            ex_titles.add(norm(m.group(1)))
            ex_items.append((words(m.group(1)), paths(ln)))
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
        elif mechanical_gap(title, m.group("body")):
            sys.stderr.write("reject: mechanical-gap: handled by supply: %s\n" % title)
        elif key in ex_titles or key in seen:
            sys.stderr.write("reject: duplicate title: %s\n" % title)
        elif near_dup(title, m.group("body"), ex_items):
            sys.stderr.write("reject: near-duplicate of an existing roadmap item (same file, same words): %s\n" % title)
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
