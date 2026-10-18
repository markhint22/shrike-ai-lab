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

       ovn_auto_research_validate.py --cap-arith <run.log> <burn/day> <claude_share> <lane repos> <ceil> <explicit 0|1> <cap_now>
stdout: "<cap><TAB><arithmetic line for run.log>" (daily pass cap derived from the fleet's burn rate, see cap_arithmetic()).

       ovn_auto_research_validate.py --normalize <reply.txt> [--default-cat <cat>]
stdout: canonical "- [ ] [P<n>] [ready] <title> — <body> {cat: ...}" lines recovered from the agent's raw reply. 2026-10-18: the agent's final reply is
        not always in the canonical form (a real xlite reply was bold markdown "- **[needs-research → ready] P1 · bug · units/status** `...`" with no
        title/body separator and no {cat:} meta, so the old checkbox-only grep found 0 lines, so the whole pass was thrown away as FAILED). The tolerant
        parser accepts bullets (-, *, 1.), bold, a missing checkbox, "[status] P1" or "[P1] [status]" headers (any status incl. "needs-research → ready"),
        "· kind · area" tags, a missing or non-em-dash separator and a missing/misplaced {cat:} meta. It still rejects prose (no bullet), bullets with no
        priority P1-P4, and priorities outside 1-4: those are reported on stderr ("normalize: ...") and never emitted.
        OVN_AR_NORMALIZE=off makes it emit only already-canonical lines (the old behaviour).

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


# ---------------------------------------------------------------------------------------------------------------------------------------------------
# --normalize: tolerant recovery of feature lines from a raw agent reply (see the module docstring).
BULLET_RE = re.compile(r"^(?:[-*•]|\d{1,2}[.)])\s+")
STATUS_WORD_RE = re.compile(r"\b(ready|decomposed|needs[- ]decompose|needs[- ]research)\b", _I)
CATS = ("backend", "web", "mobile", "game", "infra", "test")
META_RE = re.compile(r"\{cat:[^}]*\}")
SEP_RE = re.compile(r"\s(?:—|–|--|-)\s")   # em dash, en dash, '--', spaced hyphen


def _header(text):
    """Consume '[ ]' / '[status]' / '[P1]' / bare 'P1' header tokens from the front of text.
    returns (priority or None, status_seen, rest). A bracket group that is none of those ends the header."""
    pos, prio, status = 0, None, False
    while True:
        m = re.match(r"\s*\[([^\]]*)\]", text[pos:])
        if m:
            inner = m.group(1).strip()
            pm = re.fullmatch(r"P([0-9])", inner, re.I)
            if inner == "":
                pos += m.end(); continue
            if pm:
                if prio is None:
                    prio = pm.group(1)
                pos += m.end(); continue
            if STATUS_WORD_RE.search(inner):
                status = True; pos += m.end(); continue
            break
        m = re.match(r"\s*P([0-9])\b", text[pos:], re.I) if prio is None else None
        if m:
            prio = m.group(1); pos += m.end(); continue
        break
    return prio, status, text[pos:]


def _title_from(kind, area, rest):
    """No title in the line (bold-header form): '<kind> <area>: <first clause of the text>', no em dash, <= 110 chars, cut at a word boundary."""
    clause = re.split(r"(?<=[.!?])\s|\s—\s", rest.strip(), maxsplit=1)[0].replace("`", "").replace("—", "-").strip()
    head = " ".join(x for x in (kind, area) if x)
    t = (head + ": " if head else "") + clause
    if len(t) > 110:
        t = t[:110].rsplit(" ", 1)[0]
        if t.count("(") > t.count(")"):
            t = t[:t.rindex("(")]
        t = t.rstrip(" ,;:(")
    return t


def normalize_line(raw, default_cat="backend"):
    """-> (canonical line | None, note | None). note is set for a bullet that looked like a feature but could not be recovered."""
    s = raw.strip()
    if LINE_RE.match(s):
        return s, None                          # already canonical: passed through byte-for-byte
    bm = BULLET_RE.match(s)
    if bm:
        s = s[bm.end():]
    elif not s.startswith("["):
        return None, None                       # prose / blank / heading: ignored silently
    kind = area = ""
    inner_rest = None
    if s.startswith("**") and s.count("**") >= 2:
        close = s.index("**", 2)
        prio, status, tags = _header(s[2:close])
        if prio is not None:
            if tags.strip(" \t·•|:-") != "":
                parts = [x.strip() for x in re.split(r"[·•|]", tags) if x.strip()]
                kind = parts[0].lower() if parts else ""
                area = parts[1] if len(parts) > 1 else ""
            inner_rest = s[close + 2:]
            header_ok = True
    if inner_rest is None:
        prio, status, rest = _header(s.replace("**", "") if s.startswith("**") else s)
        header_ok = prio is not None
        inner_rest = rest
    if not header_ok or prio is None:
        return None, "no priority [P1-P4] in the header: " + raw.strip()[:80] if bm else None
    if prio not in "1234" or len(prio) != 1 or prio == "0":
        return None, "priority P%s is outside P1-P4: %s" % (prio, raw.strip()[:80])
    if not status and not re.match(r"^\s*-\s*\[ \]", raw.strip()) and not raw.strip().startswith("[ ]"):
        return None, "no status ([ready] ...) and no checkbox: " + raw.strip()[:80]
    rest = inner_rest.replace("**", "").strip().lstrip("·•|:- ").strip()
    meta = None
    mm = META_RE.search(rest)
    if mm:
        meta = mm.group(0)
        rest = (rest[:mm.start()] + rest[mm.end():]).strip()
    rest = rest.rstrip()
    sm = SEP_RE.search(rest)
    # tags form ("** P1 . bug . area **" header): the text after it is prose, never "title - body", so the title is derived
    if not (kind or area) and sm and sm.start() >= 3 and rest[:sm.start()].count("`") % 2 == 0 and sm.start() < 200:
        title, body = rest[:sm.start()].strip(), rest[sm.end():].strip()
    else:
        title, body = _title_from(kind, area, rest), rest
    title = title.replace("`", "").replace("—", "-").strip()
    if len(title) < 3 or len(body) < 3:
        return None, "empty title or body: " + raw.strip()[:80]
    if meta is None:
        cat = kind if kind in CATS else ("test" if kind in ("test", "tests") else default_cat)
        files = set(PATHISH_RE.findall(body))
        meta = "{cat: %s; size: %s; multifile: %s; research: repo}" % (cat, "M" if len(files) > 2 else "S", "yes" if len(files) > 1 else "no")
    return "- [ ] [P%s] [ready] %s — %s %s" % (prio, title, body, meta), None


def normalize_reply(text, default_cat="backend"):
    out, notes, canonical = [], [], 0
    for ln in text.splitlines():
        if os.environ.get("OVN_AR_NORMALIZE", "on") == "off":
            if ln.startswith("- [ ]"):
                out.append(ln)
            continue
        line, note = normalize_line(ln, default_cat)
        if note:
            notes.append(note)
        if line:
            if line != ln.strip():
                canonical += 1
            out.append(line)
    return out, notes, canonical


def cap_arithmetic(log_path, burn=100.0, share=0.5, nrepos=7, ceil_=16, explicit=False, cap_now=8, now=None):
    """Daily pass cap derived from the fleet's burn rate. -> (cap, one-line explanation for run.log).
    passes = ceil(burn * share / avg_accepted_per_pass); avg is measured from run.log "<repo>: accepted N/M" lines of the last 7 days
    (>= 3 samples, floor 1.0; else a 4.5 default = the 10-08..10-18 measured mean); clamped to [nrepos, ceil_]. explicit=True keeps cap_now."""
    import math, time
    now = time.time() if now is None else now
    pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \S+: accepted (\d+)/\d+\s*$")
    vals = []
    try:
        with open(log_path, errors="replace") as fh:
            for ln in fh:
                m = pat.match(ln)
                if m:
                    try:
                        t = time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S"))
                    except ValueError:
                        continue
                    if now - t <= 7 * 86400:
                        vals.append(int(m.group(2)))
    except OSError:
        pass
    measured = len(vals) >= 3
    avg = max(1.0, sum(vals) / len(vals)) if measured else 4.5
    want = int(math.ceil(burn * share / avg))
    cap = max(nrepos, min(want, ceil_))
    if explicit:
        cap = cap_now
    src = "measured over %d pass(es) in 7d" % len(vals) if measured else "default 4.5 (only %d pass(es) logged in 7d)" % len(vals)
    return cap, ("cap arithmetic: burn=%g items/day x claude_share=%g = %g needed/day; avg_accepted_per_pass=%.2f (%s) -> %d pass(es)/day; "
                 "clamp[%d lane repos .. %d] -> cap=%d%s" % (burn, share, burn * share, avg, src, want, nrepos, ceil_, cap,
                                                              " (OVN_AR_MAX_PER_DAY explicit override)" if explicit else ""))


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
    if len(sys.argv) > 2 and sys.argv[1] == "--cap-arith":
        a = sys.argv[2:]
        try:
            cap, text = cap_arithmetic(a[0], float(a[1]), float(a[2]), int(float(a[3])), int(float(a[4])), a[5] == "1", int(float(a[6])))
        except (IndexError, ValueError):
            cap, text = 8, "cap arithmetic: bad arguments - keeping cap=8"
        print("%d\t%s" % (cap, text))
        return
    if len(sys.argv) > 2 and sys.argv[1] == "--normalize":
        cat = "backend"
        if "--default-cat" in sys.argv:
            cat = sys.argv[sys.argv.index("--default-cat") + 1]
        if cat not in CATS:
            cat = "backend"
        try:
            with open(sys.argv[2], encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
        except OSError:
            txt = ""
        out, notes, changed = normalize_reply(txt, cat)
        for n in notes:
            sys.stderr.write("normalize: reject: %s\n" % n)
        if changed:
            sys.stderr.write("normalize: recovered %d line(s) from a non-canonical form\n" % changed)
        for ln in out:
            print(ln)
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
