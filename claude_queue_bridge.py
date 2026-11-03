#!/usr/bin/env python3
"""claude_queue_bridge.py — the two-way bridge between the Claude queue and the 27B.

Runs MAC-SIDE (CLAUDE_QUEUE.md lives only in the shared repo). Four subcommands, orchestrated
by claude_queue_bridge.sh as Passes A-D each cycle:

  harvest    (Pass A) — REFILL the Claude queue from the 27B's ceiling failures. Reads AUTO-SKIP
             items (the ovn_item_guard tag = "tried N cycles, kept reverting") that the fleet
             surfaced, dedups against what's already in CLAUDE_QUEUE.md (+ --archive, see below),
             and appends the new ones under a dated "Auto-harvested from 27B ceiling" section.
             The 27B's proven failures become Claude's inbox — evidence-based, not a guess.

  prework    (Pass B) — SCHEDULE 27B prework for every CODE-ABLE Claude item that doesn't already
             have a briefing. Emits `<repo>\t<task>` lines (to stdout) for items lacking
             prework/<repo>-<slug>.md, so the caller can append them to the server's
             prework/queue.tsv. Skips human/hardware/account/DNS/submission items (no code to
             prework) and already-checked items. (Never needs --archive: archived items are
             checked-off by definition, so they'd never be prework candidates anyway.)

  signatures (feeds Pass C) — print `repo\tnormsig` for every checked-off item with a known
             repo, across --queue and --archive, so claude_queue_bridge.sh knows which
             server-side AUTO-SKIP lines are safe to retire.

  retire     (Pass C) — flip a single repo's unchecked AUTO-SKIP progress-file lines to `[x]`
             when their signature matches a signatures-file entry, closing the loop so the 27B
             stops re-flagging code Claude already fixed.

  autoclose  (Pass A2, P5-supply-truth 2026-11-02) — close a harvested `[CLAUDE]` line when the fleet later LANDED the same feature. Matching is by `[feat:TAG]` (never by line
             text: 125 of 177 open lines were stale because the fleet had landed the feature under different wording/paths): the tag must have a class=landed|credit-only row in
             outcomes.jsonl for that repo AND every test id the line's VERIFY names (`::test_x`, `-t "title"`, `test_x`) must exist on <ref> (default origin/develop) in the repo clone.
             That is a PRESENCE proof, not an execution of the VERIFY. Mode OVN_BRIDGE_AUTOCLOSE (default `shadow`): shadow only logs what it would close
             (state/bridge_autoclose_shadow.log), `enforce` flips the line to [x], `off` skips. harvest uses the same tag match so a closed feature is not re-opened.

IMPORTANT — dedup relies on task_sig(), not bare norm_sig(): a queue-formatted line carries a
"[CLAUDE] <repo>/ — " prefix that the raw AUTO-SKIP task text never has, so norm_sig()'s
first-12-words comparison would silently never match across that boundary (this was the actual
dominant cause of a 20x+ per-item duplication bug in CLAUDE_QUEUE.md, fixed 2026-09-10 —
see cc973c1). Any new code comparing queue text against autoskip/progress text MUST use
task_sig(), never norm_sig() directly.

--archive is how harvest/signatures see items moved out of the live queue by
archive_claude_queue_done.py (run as Pass D, after retire). This is NOT optional plumbing:
without it, archiving an item would make harvest/retire treat it as unknown again and
re-introduce the exact duplication bug this file was fixed to prevent.

Usage:
  claude_queue_bridge.py prework    --queue CLAUDE_QUEUE.md --prework-list <file of existing prework basenames>
  claude_queue_bridge.py harvest    --queue CLAUDE_QUEUE.md --autoskip <file: repo<TAB>task lines> [--archive CLAUDE_QUEUE_DONE.md]
  claude_queue_bridge.py signatures --queue CLAUDE_QUEUE.md [--archive CLAUDE_QUEUE_DONE.md]
  claude_queue_bridge.py autoclose  --queue CLAUDE_QUEUE.md --outcomes <outcomes.jsonl> --repos-dir <dir with <repo>/ clones> [--archive ...] [--mode shadow|enforce|off]
  claude_queue_bridge.py retire     --progress <repo's OVERNIGHT_PROGRESS.md> --signatures <file: one normsig per line>
"""
import argparse, json, os, re, subprocess, sys, datetime

# canonical repo basenames + aliases seen in CLAUDE_QUEUE headers/inline text
REPO_ALIASES = {
    "billwatch": "billwatch", "policylogs": "billwatch",
    "gitlark": "gitlark",
    "iptv_apps": "iptv_apps", "iptv": "iptv_apps", "chickadee": "iptv_apps",
    "test-automation-agent": "test-automation-agent", "specpilot": "test-automation-agent",
    "xlite": "xlite",
    "shrike-labs-website": "shrike-labs-website", "shrike-website": "shrike-labs-website",
    "shrike-notify": "shrike-notify",
    "shrike-monitor": "shrike-monitor",
}
REPO_TOKEN_RE = re.compile(
    r"\b(billwatch|policylogs|gitlark|iptv_apps|iptv|chickadee|"
    r"test-automation-agent|specpilot|xlite|shrike-labs-website|shrike-website|"
    r"shrike-notify|shrike-monitor)\b", re.I)

# an item is NOT code-able (no prework possible) if it's human/hardware/ops work
NON_CODEABLE_RE = re.compile(
    r"\(human\)|\bhuman/QA\b|\bhardware\b|real[- ]device|real device|"
    r"App Store|Play Store|Appstore|submission|certification|"
    r"\bDNS\b|custom domain|domain canonicaliz|registrar|"
    r"register (the |a )?(github app|account)|developer account|"
    r"ad spend|pricing decision|wire .*fly deploy|FLY_API_TOKEN|"
    r"service account|Xcode build/run|icon/top-shelf|asset-design|art assets",
    re.I)

ITEM_RE = re.compile(r"^\s*- \[ \] (.+)$")
CHECKED_ITEM_RE = re.compile(r"^\s*- \[[xX]\] (.+)$")
HEADER_RE = re.compile(r"^#{2,4}\s+(.+)$")
# 2026-10-03: an escalated manual bug ('[CLAUDE] [bug-escalated: ...]', the bug-first hand-off) is harvested/retired exactly like an AUTO-SKIP line
AUTOSKIP_LINE_RE = re.compile(r"^(\s*)- \[ \] (.*(?:AUTO-SKIP|\[CLAUDE\]\s*\[bug-escalated).*)$")
AUTOSKIP_TAG_RE = re.compile(r"\[AUTO-SKIP[^\]]*\]\s*|\[CLAUDE\]\s*\[bug-escalated[^\]]*\]\s*")
FEAT_TAG_RE = re.compile(r"\[feat:([^\]\s]+)\]")


def slug(task):
    s = re.sub(r"[^a-z0-9]+", "-", task.lower())[:50]
    return s.strip("-")


def infer_repo(item_text, current_header):
    for src in (item_text, current_header):
        m = REPO_TOKEN_RE.search(src or "")
        if m:
            return REPO_ALIASES[m.group(1).lower()]
    return None


def norm_sig(text):
    """collapse a task to a comparable signature (lowercase alnum words, first 12)."""
    words = re.findall(r"[a-z0-9]+", text.lower())
    return " ".join(words[:12])


LEADING_TAGS_RE = re.compile(r"^(\[[^\]]+\]\s*)+")
REPO_PREFIX_RE = re.compile(
    r"^(?:billwatch|policylogs|gitlark|iptv_apps|iptv|chickadee|"
    r"test-automation-agent|specpilot|xlite|shrike-labs-website|shrike-website|"
    r"shrike-notify|shrike-monitor)/\s*(?:—|-|—)?\s*", re.I)


def task_sig(text):
    """norm_sig() after stripping leading `[TAG]` markers and a `repo/ — ` prefix.

    A queue-formatted item ("[CLAUDE] gitlark/ — [T1] some task...") and the
    bare AUTO-SKIP task it was harvested from ("[T1] some task...") must
    collapse to the SAME signature, or cross-format dedup (harvest against the
    queue, retire against checked-off queue items) never actually matches —
    norm_sig()'s first-12-words comparison is offset by the extra "claude
    <repo>" words baked into every queue line, so two genuinely identical
    tasks compare unequal. Use this (not bare norm_sig) for any comparison
    between queue text and raw autoskip/task text.
    """
    # a queue line often nests tags around the repo prefix, e.g.
    # "[CLAUDE] gitlark/ — [T1] task..." — strip leading [TAG]s, then a repo/
    # prefix, then [TAG]s again (the [T1] that was hiding behind "gitlark/ — ").
    stripped = LEADING_TAGS_RE.sub("", text)
    stripped = REPO_PREFIX_RE.sub("", stripped)
    stripped = LEADING_TAGS_RE.sub("", stripped)
    sig = norm_sig(stripped)
    # 2026-10-03 (A7-1): the first 12 words of a '[T3] <long android path> ...' line are consumed by the file path, so three different bugs in
    # StreamsViewModel.kt shared ONE signature (harvest dropped two as duplicates; retire would have closed all three). A [feat:ID] tag is unique per
    # bug (and per retest round), so it is part of the signature whenever the line carries one.
    m = FEAT_TAG_RE.search(text)
    if m:
        sig += " feat " + m.group(1).lower()
    return sig


def iter_items(lines):
    """yield (item_text, current_header) for each unchecked item."""
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = ITEM_RE.match(ln)
        if m:
            yield m.group(1).strip(), header


def iter_all_items(lines):
    """yield (item_text, current_header) for every item, checked or not.

    Harvest dedup must see checked-off items too: an AUTO-SKIP task that was
    resolved and flipped to `- [x]` in CLAUDE_QUEUE.md would otherwise drop out
    of the "already have this" signature set, and the next harvest re-adds it
    as a fresh `- [ ]` duplicate the moment the server re-surfaces the same
    AUTO-SKIP line (which it does every cycle by design, since AUTO-SKIP items
    are never auto-credited server-side).
    """
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = ITEM_RE.match(ln) or CHECKED_ITEM_RE.match(ln)
        if m:
            yield m.group(1).strip(), header


def strip_autoskip_task(line):
    """Extract the task text from an unchecked AUTO-SKIP progress-file line,
    mirroring claude_queue_bridge.sh's sed extraction exactly (same source of
    truth as what gets harvested into CLAUDE_QUEUE.md). Returns None if the
    line isn't an unchecked AUTO-SKIP item.
    """
    m = AUTOSKIP_LINE_RE.match(line)
    if not m:
        return None
    task = AUTOSKIP_TAG_RE.sub("", m.group(2)).strip()
    return task


def checked_signatures_by_repo(lines):
    """yield (repo, norm_sig) for every CHECKED `- [x]` item whose repo can be
    inferred — used to know which AUTO-SKIP tasks are safe to retire server-side.
    """
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = CHECKED_ITEM_RE.match(ln)
        if not m:
            continue
        text = m.group(1).strip()
        repo = infer_repo(text, header)
        if repo:
            yield repo, task_sig(text)


def read_lines_optional(path):
    """Read a file's lines, or return [] if path is falsy/missing.

    Used for --archive: CLAUDE_QUEUE_DONE.md may not exist yet, and callers
    that don't care about archived history (e.g. cmd_prework, which only
    ever looks at open items) never pass --archive at all.
    """
    if not path:
        return []
    try:
        return open(path, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return []


def cmd_signatures(args):
    """Print `repo\\tnormsig` for every checked-off item with a known repo,
    across --queue and (if given) --archive — consumed by the bridge shell
    script to know what's safe to retire. Archived items must still count:
    they were checked off for a real reason and shouldn't become "unknown"
    (and therefore un-retirable on the server) just because they moved out
    of the live queue file.
    """
    lines = open(args.queue, encoding="utf-8").read().splitlines() + read_lines_optional(args.archive)
    seen = set()
    for repo, sig in checked_signatures_by_repo(lines):
        key = (repo, sig)
        if key in seen:
            continue
        seen.add(key)
        sys.stdout.write(f"{repo}\t{sig}\n")


def cmd_retire(args):
    """Flip unchecked AUTO-SKIP lines in a single repo's OVERNIGHT_PROGRESS.md
    to `- [x]` when their task signature matches an already-checked-off
    CLAUDE_QUEUE.md item — closes the loop so the 27B stops re-flagging code
    Claude already fixed. Rewrites --progress in place if anything changed.
    Prints RETIRED=<n>.
    """
    sigs = {
        s.strip() for s in open(args.signatures, encoding="utf-8").read().splitlines() if s.strip()
    }
    lines = open(args.progress, encoding="utf-8").read().splitlines()
    retired = 0
    out = []
    for ln in lines:
        task = strip_autoskip_task(ln)
        if task and len(task) >= 20 and task_sig(task) in sigs:
            m = AUTOSKIP_LINE_RE.match(ln)
            indent = m.group(1)
            out.append(
                f"{indent}- [x] {m.group(2)} "
                f"(retired {args.today}: resolved via Claude, see shared/CLAUDE_QUEUE.md)"
            )
            retired += 1
        else:
            out.append(ln)
    if retired:
        with open(args.progress, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    sys.stderr.write(f"RETIRED={retired}\n")


def cmd_prework(args):
    lines = open(args.queue, encoding="utf-8").read().splitlines()
    existing = set()
    if args.prework_list:
        for b in open(args.prework_list, encoding="utf-8").read().splitlines():
            b = b.strip()
            if b.endswith(".md"):
                existing.add(b[:-3])  # strip .md -> "<repo>-<slug>"
    emitted = 0
    seen = set()
    for item, header in iter_items(lines):
        # strip leading [P1]/[CLAUDE]/[CLAUDE/HUMAN] tags for the task body
        body = re.sub(r"^(\[[^\]]+\]\s*)+", "", item).strip()
        body = re.sub(r"~\d+d\s*(\(human[^)]*\))?", "", body).strip()
        if NON_CODEABLE_RE.search(item):
            continue
        repo = infer_repo(item, header)
        if not repo:
            continue
        key = f"{repo}-{slug(body)}"
        if key in existing or key in seen:
            continue
        seen.add(key)
        # keep the task text single-line + reasonably short for the prework prompt
        task = re.sub(r"\s+", " ", body)[:400]
        sys.stdout.write(f"{repo}\t{task}\n")
        emitted += 1
    sys.stderr.write(f"prework: emitted {emitted} code-able items lacking a briefing\n")


# ---------------------------------------------------------------------------------------------- autoclose (P5-supply-truth)
LANDED_CLASSES = ("landed", "credit-only")
VERIFY_RE = re.compile(r"VERIFY:\s*`([^`]+)`")
TEST_ID_RES = (
    re.compile(r"::([A-Za-z_][A-Za-z0-9_]*)"),                 # pytest path::test_name (also path::Class::test_name)
    re.compile(r"""\s-t\s+(?:"([^"]+)"|'([^']+)')"""),         # vitest/jest -t "title"
    re.compile(r"\b(test_[A-Za-z0-9_]+)"),                     # bare test_ names (pytest -k, gut)
)


def feat_tag_of(text):
    m = FEAT_TAG_RE.search(text or "")
    return m.group(1) if m else None


def landed_tags(outcomes_path):
    """{(repo, feat_tag)} that have a landed/credit-only row in an outcomes.jsonl (unparseable rows skipped). Keyed by repo: a tag landed for billwatch must not close a gitlark line."""
    tags = set()
    try:
        fh = open(outcomes_path, "rb")
    except OSError:
        return tags
    with fh:
        for raw in fh:
            try:
                r = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if isinstance(r, dict) and r.get("class") in LANDED_CLASSES and r.get("feat_tag"):
                tags.add((str(r.get("repo") or ""), str(r["feat_tag"])))
    return tags


def landed_line_hashes(outcomes_path):
    """{(repo, feat_tag): {item_line_hash,...}} from landed/credit-only rows (S3-guards2: the landing is keyed by the ITEM, not only the feature: siblings of one [feat:] tag are different items)."""
    out = {}
    try:
        fh = open(outcomes_path, "rb")
    except OSError:
        return out
    with fh:
        for raw in fh:
            try:
                r = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if isinstance(r, dict) and r.get("class") in LANDED_CLASSES and r.get("feat_tag"):
                out.setdefault((str(r.get("repo") or ""), str(r["feat_tag"])), set())
                for k in ("item_line_hash", "item_hash"):
                    if r.get(k):
                        out[(str(r.get("repo") or ""), str(r["feat_tag"]))].add(str(r[k]))
    return out


def line_key(text):
    """md5 of the harvested task text (the part after '[CLAUDE] <repo>/ - ', checkbox stripped): the same shape the fleet hashes (outcomes item_line_hash) when the text is unchanged."""
    import hashlib
    body = re.sub(r"^\s*- \[[ xX]\] ", "", text or "")
    body = re.sub(r"^\[CLAUDE\]\s*\S+?/\s*[\u2014-]\s*", "", body)
    return hashlib.md5(body.encode("utf-8")).hexdigest()


def _tag_landed(tags, repo, tag):
    """True when (repo, tag) landed. An outcomes row with no repo field (legacy) matches any repo."""
    return (repo, tag) in tags or ("", tag) in tags


def named_test_ids(line):
    """Test ids the line's VERIFY command names ([] when there is no VERIFY or it names none)."""
    m = VERIFY_RE.search(line)
    if not m:
        return []
    cmd = m.group(1)
    ids = []
    bare = re.sub(r"\S+\.(?:py|ts|tsx|js|gd|kt|swift)\b(?:::\S+)?", " ", cmd)   # a test FILE name (tests/test_x.py) is not a test id: only names inside the file are
    for rx in TEST_ID_RES:
        for g in rx.findall(bare if rx is TEST_ID_RES[2] else cmd):
            g = next((x for x in g if x), "") if isinstance(g, tuple) else g
            if g and g not in ids:
                ids.append(g)
    return ids


# S3-guards2 (2026-11-03, outcomes F1 / cqueue F1): the old `git grep -qF <id> <ref>` searched EVERY file, so the queue's own text (OVERNIGHT_PROGRESS.md, CLAUDE_QUEUE*, docs) proved
# "the test exists" - 3 of 7 shadow would-close lines were not justified (xlite is_valid_uses_validators exists only as queue text, the work was never done). Now: code/test paths only
# (markdown/text/log/json/queue/doc paths are excluded) AND the id must be DEFINED (def/func/fun/function/fn/class <id>..., or it/test/describe("...<id>...")), not merely mentioned.
CODE_PATHSPEC = ("--", ".", ":(exclude)*.md", ":(exclude)*.markdown", ":(exclude)*.txt", ":(exclude)*.log", ":(exclude)*.json", ":(exclude)*.jsonl", ":(exclude)*.csv", ":(exclude)*.rst",
                 ":(exclude)OVERNIGHT_PROGRESS.md", ":(exclude)*OVERNIGHT_PROGRESS*", ":(exclude)*CLAUDE_QUEUE*", ":(exclude,glob)**/docs/**", ":(exclude,glob)docs/**")
_ERE_META = set(".[]{}()*+?^$|\\")


def _ere_escape(s):
    return "".join("\\" + c if c in _ERE_META else c for c in s)


def definition_regex(needle):
    """POSIX ERE (git grep -E, portable: no \\b or \\s) that matches a DEFINITION of `needle`: `def|func|fun|function|fn|class <needle>...` (an identifier may continue after it: pytest -k is a
    substring match) or `it|test|describe|specify(...'<...needle...>`. A bare mention (comment, queue text, string elsewhere) does not match."""
    n = _ere_escape(needle)
    return ("(^|[^A-Za-z0-9_])(def|func|fun|function|fn|class)[[:space:]]+" + n +
            "|(^|[^A-Za-z0-9_.])(it|test|describe|specify)(\\.[a-z]+)?[[:space:]]*\\([[:space:]]*['\"`][^'\"`]*" + n)


def present_on_ref(repo_dir, ref, needle):
    """True when `needle` is DEFINED in a code/test file of <ref> in the clone (git grep: path-independent, so a wrong path in the line does not matter; markdown/queue/doc files never count)."""
    if not needle or not needle.strip():
        return False
    try:
        r = subprocess.run(["git", "-C", repo_dir, "grep", "-qE", "-e", definition_regex(needle), ref] + list(CODE_PATHSPEC), capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


def verify_on_develop(repo_dir, ref, line, present=present_on_ref):
    """(ok, why): the line names >= 1 test id and every one exists on <ref>."""
    ids = named_test_ids(line)
    if not ids:
        return False, "no named test id in VERIFY"
    missing = [i for i in ids if not present(repo_dir, ref, i)]
    return (not missing), ("missing on %s: %s" % (ref, ", ".join(missing)) if missing else "all %d named test id(s) present on %s" % (len(ids), ref))


def closed_tags(lines):
    """feat tags of CHECKED lines (queue + archive): a closed feature is never re-harvested."""
    out = set()
    for ln in lines:
        m = CHECKED_ITEM_RE.match(ln)
        if m:
            t = feat_tag_of(m.group(1))
            if t:
                out.add(t)
    return out


def autoclose_mode(arg=None):
    v = (arg or os.environ.get("OVN_BRIDGE_AUTOCLOSE") or "shadow").strip().lower()
    return v if v in ("shadow", "enforce", "off") else "shadow"


def _shadow(path, msg):
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass


def _shadow_once(path, key, msg):
    """Append msg unless an existing row of the same day already carries `key` (one row per (line, tag, day): the hourly pass used to repeat it up to 6x)."""
    if not path:
        return False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for row in f:
                if key in row:
                    return False
    except OSError:
        pass
    _shadow(path, msg)
    return True


def autoclose_lines(lines, tags, repos_dir, ref, today, present=present_on_ref, hashes=None):
    """(new_lines, closed:[(lineno, repo, tag, why)]). Pure apart from the git grep: only open lines that carry a [feat:] tag whose tag landed AND whose named test ids are DEFINED in code on the ref.
    `hashes` ({(repo, tag): {line hashes}} from landed_line_hashes) tags the reason with how the landing matched: 'item' (this very line landed) or 'feature' (a sibling/other wording of the tag landed)."""
    out, closed, header = [], [], ""
    for i, ln in enumerate(lines):
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
        m = ITEM_RE.match(ln)
        tag = feat_tag_of(m.group(1)) if m else None
        if m and tag:
            repo = infer_repo(m.group(1), header)
            if repo and _tag_landed(tags, repo, tag):
                ok, why = verify_on_develop(os.path.join(repos_dir, repo), ref, ln, present)
                if ok and hashes is not None:
                    hs = hashes.get((repo, tag), set()) | hashes.get(("", tag), set())
                    why += "; landing=%s" % ("item" if line_key(m.group(1)) in hs else "feature")
                if ok:
                    closed.append((i + 1, repo, tag, why))
                    out.append(ln.replace("- [ ]", "- [x]", 1) + " (auto-closed %s: [feat:%s] landed, %s)" % (today, tag, why))
                    continue
        out.append(ln)
    return out, closed


def cmd_autoclose(args):
    mode = autoclose_mode(args.mode)
    if mode == "off":
        sys.stderr.write("autoclose: off\n")
        return
    lines = open(args.queue, encoding="utf-8").read().splitlines()
    new, closed = autoclose_lines(lines, landed_tags(args.outcomes), args.repos_dir, args.ref, args.today, hashes=landed_line_hashes(args.outcomes))
    for lineno, repo, tag, why in closed:
        _shadow_once(args.shadow_log, "%s %s would-close line %d %s [feat:%s] (" % (args.today, "ENFORCED" if mode == "enforce" else "SHADOW", lineno, repo, tag),
                     "%s %s would-close line %d %s [feat:%s] (%s)" % (args.today, "ENFORCED" if mode == "enforce" else "SHADOW", lineno, repo, tag, why))
    if mode == "enforce" and closed:
        with open(args.queue, "w", encoding="utf-8") as f:
            f.write("\n".join(new) + "\n")
    sys.stderr.write("autoclose: mode=%s %s=%d\n" % (mode, "closed" if mode == "enforce" else "would-close", len(closed)))


TEST_ITEM_RE = re.compile(r"cat:test\b|\[T\d\]\s+\S*(?:/tests?/|tests?/|test_[^/\s]*\.|\.test\.|\.spec\.|_test\.|Tests?\.(?:kt|swift)|\.test\b)", re.I)


def done_check(repos_dir, repo, ref, task, present=present_on_ref):
    """(done, why) for the pre-harvest check (S3-guards2, cqueue F6: 22 of 31 recent harvested lines were stale on arrival). True only for a TEST-writing item (target path or cat:test says so)
    whose VERIFY names >= 1 test id and EVERY one is DEFINED in a code/test file of <ref> (same definition-only guard as the autoclose: queue/markdown text never counts). An implementation item that names an
    existing (red) test is NOT judged done - the test existing proves nothing about the behaviour."""
    if not TEST_ITEM_RE.search(task or ""):
        return False, "not a test-writing item"
    ids = named_test_ids(task)
    if not ids:
        return False, "no named test id in VERIFY"
    clone = os.path.join(repos_dir, repo)
    if not os.path.isdir(clone):
        return False, "no clone"
    missing = [i for i in ids if not present(clone, ref, i)]
    return (not missing), ("missing on %s: %s" % (ref, ", ".join(missing)) if missing else "all %d named test id(s) defined on %s" % (len(ids), ref))


def done_check_mode(arg=None):
    v = (arg or os.environ.get("OVN_HARVEST_DONE_CHECK") or "shadow").strip().lower()
    return v if v in ("shadow", "enforce", "off") else "shadow"


def cmd_harvest(args):
    lines = open(args.queue, encoding="utf-8").read().splitlines() + read_lines_optional(args.archive)
    existing_sigs = {task_sig(t) for t, _ in iter_all_items(lines)}
    mode = autoclose_mode(getattr(args, "mode", None))
    closed = {("", t) for t in closed_tags(lines)} | (landed_tags(args.outcomes) if getattr(args, "outcomes", "") else set()) if mode != "off" else set()
    dmode = done_check_mode(getattr(args, "done_mode", None)) if getattr(args, "repos_dir", "") else "off"
    new_items = []
    for ln in open(args.autoskip, encoding="utf-8").read().splitlines():
        if "\t" not in ln:
            continue
        repo, task = ln.split("\t", 1)
        repo, task = repo.strip(), task.strip()
        if not repo or len(task) < 20:   # guard: never harvest a stub/garbage task
            continue
        if task_sig(task) in existing_sigs:
            continue
        tag = feat_tag_of(task)
        if tag and _tag_landed(closed, repo, tag):      # P5: a feature already closed (or landed by the fleet) is not re-opened under different wording
            _shadow(getattr(args, "shadow_log", ""), "%s %s would-not-reharvest %s [feat:%s]" % (args.today, "ENFORCED" if mode == "enforce" else "SHADOW", repo, tag))
            if mode == "enforce":
                continue
        if dmode != "off":
            done, dwhy = done_check(args.repos_dir, repo, getattr(args, "done_ref", "origin/claude/feature"), task)
            if done:
                sg = task_sig(task)[:24]
                tagm = "%s %s would-skip-done %s sig=%s" % (args.today, "ENFORCED" if dmode == "enforce" else "SHADOW", repo, sg)
                _shadow_once(getattr(args, "done_log", ""), tagm + " (", "%s (%s) %s" % (tagm, dwhy, task[:90]))
                if dmode == "enforce":
                    continue
        existing_sigs.add(task_sig(task))
        new_items.append((repo, task))
    if not new_items:
        sys.stderr.write("harvest: nothing new to add\n")
        return
    today = args.today
    block = [f"\n## Auto-harvested from 27B ceiling [{today}] — the fleet tried these N cycles and kept reverting; Claude to implement\n"]
    for repo, task in new_items:
        block.append(f"- [ ] [CLAUDE] {repo}/ — {task}\n")
    with open(args.queue, "a", encoding="utf-8") as f:
        f.write("".join(block))
    sys.stderr.write(f"harvest: appended {len(new_items)} new items to {args.queue}\n")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("prework")
    pp.add_argument("--queue", required=True)
    pp.add_argument("--prework-list", default="")
    hp = sub.add_parser("harvest")
    hp.add_argument("--queue", required=True)
    hp.add_argument("--autoskip", required=True)
    hp.add_argument("--archive", default="")
    hp.add_argument("--today", default=datetime.date.today().isoformat())
    hp.add_argument("--outcomes", default="")
    hp.add_argument("--mode", default="")
    hp.add_argument("--shadow-log", default="")
    hp.add_argument("--repos-dir", default="")
    hp.add_argument("--done-ref", default="origin/claude/feature")
    hp.add_argument("--done-mode", default="")
    hp.add_argument("--done-log", default="")
    ap = sub.add_parser("autoclose")
    ap.add_argument("--queue", required=True)
    ap.add_argument("--outcomes", required=True)
    ap.add_argument("--repos-dir", required=True)
    ap.add_argument("--ref", default="origin/develop")
    ap.add_argument("--mode", default="")
    ap.add_argument("--shadow-log", default="")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    sp = sub.add_parser("signatures")
    sp.add_argument("--queue", required=True)
    sp.add_argument("--archive", default="")
    rp = sub.add_parser("retire")
    rp.add_argument("--progress", required=True)
    rp.add_argument("--signatures", required=True)
    rp.add_argument("--today", default=datetime.date.today().isoformat())
    args = p.parse_args()
    {
        "prework": cmd_prework,
        "harvest": cmd_harvest,
        "signatures": cmd_signatures,
        "retire": cmd_retire,
        "autoclose": cmd_autoclose,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
