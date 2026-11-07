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

Y2 (2026-11-04): harvest also keeps a persisted LEDGER (--ledger, state/harvest_ledger.tsv) of stable item keys (body_key: repo + full normalized text, feat tag/metadata/checkbox/prefix removed): a key that was
ever harvested, or is ticked/archived, is never harvested again, whatever the 12-word signature or feat tag of its re-surfacing. The pre-harvest done-check (OVN_HARVEST_DONE_CHECK, default ON) skips a line
whose named test/new class/def is already DEFINED in code (never markdown/queue text). Autoclose stays shadow; OVN_BRIDGE_AUTOCLOSE_REQUIRE_ITEM=on makes enforce additionally require that the line ITSELF landed (landing=item).

ENFORCE POLICY (Y2 r6): do NOT enable OVN_HARVEST_LEDGER_MODE=enforce, OVN_HARVEST_DONE_CHECK=enforce or OVN_BRIDGE_AUTOCLOSE=enforce until a 1-2 week SHADOW log (state/harvest_ledger_skips.log,
state/harvest_skipped_done.log, state/bridge_autoclose_shadow.log) shows ZERO would-skip of non-duplicates. body_key is a heuristic; a false collision in enforce silently loses a task.

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
import argparse, json, os, re, shutil, subprocess, sys, tempfile, datetime

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


def read_text(path):
    """Read-only text read: an invalid byte (hand edit, truncated box transfer) becomes U+FFFD instead of killing the whole pass (Y2 r3 D5)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def read_text_raw(path):
    """Text read for files that are REWRITTEN: invalid bytes become lone surrogates so write_text_atomic round-trips them byte-for-byte."""
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:   # newline="": no CRLF/CR -> LF translation on read (Y2 r5 N2: the rewrite must be byte-exact)
        return f.read()


def clean_text(s):
    """Surrogate-escaped text -> display-safe text (replacement chars): for regexes, hashing, git args and logs."""
    return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def write_text_atomic(path, text):
    """Y2 r3 D6: temp file in the same directory + fsync + os.replace, so a crash / ENOSPC mid-write can never truncate the target. Keeps the target's mode. Y2 r5: resolves symlinks first; the temp file is removed on ANY failure."""
    path = os.path.realpath(path)   # Y2 r5: write THROUGH a symlink (os.replace on the link path would swap the link for a regular file and leave the real target stale)
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(path) + ".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        try:
            shutil.copymode(path, tmp)
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_lines_optional(path):
    """Read a file's lines, or return [] if path is falsy/missing.

    Used for --archive: CLAUDE_QUEUE_DONE.md may not exist yet, and callers
    that don't care about archived history (e.g. cmd_prework, which only
    ever looks at open items) never pass --archive at all.
    """
    if not path:
        return []
    try:
        return read_text(path).splitlines()
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
    lines = read_text(args.queue).splitlines() + read_lines_optional(args.archive)
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
        s.strip() for s in read_text(args.signatures).splitlines() if s.strip()
    }
    raw_lines = read_text_raw(args.progress).split("\n")   # Y2 r5 (N2): split on "\n" ONLY (str.splitlines also splits on \x0b \x0c \x1c-\x1e \x85 U+2028/9 and eats \r\n), so rewriting never alters an untouched byte
    retired = 0
    out = []
    for raw in raw_lines:
        cr = "\r" if raw.endswith("\r") else ""
        ln = clean_text(raw[:-1] if cr else raw)
        task = strip_autoskip_task(ln)
        if task and len(task) >= 20 and task_sig(task) in sigs:
            m = AUTOSKIP_LINE_RE.match(ln)
            indent = m.group(1)
            out.append(
                f"{indent}- [x] {m.group(2)} "
                f"(retired {args.today}: resolved via Claude, see shared/CLAUDE_QUEUE.md)" + cr
            )
            retired += 1
        else:
            out.append(raw)   # untouched lines keep their original bytes (CRLF, form feeds, a missing final newline)
    if retired:
        write_text_atomic(args.progress, "\n".join(out))
    sys.stderr.write(f"RETIRED={retired}\n")


def cmd_prework(args):
    lines = read_text(args.queue).splitlines()
    existing = set()
    if args.prework_list:
        for b in read_text(args.prework_list).splitlines():
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


# Y2 r3 D3: a definition must START its line (after indentation and declaration modifiers). A `# def test_x():` comment, a one-line docstring `"""def test_x"""` or a `// function x` comment is not a definition.
DEF_LEAD = "^[[:space:]]*((async|export|default|public|private|protected|internal|static|final|abstract|open|override|pub|suspend|data|sealed|inline|const|declare|unsafe|extern)[[:space:]]+)*"
TEST_LEAD = "^[[:space:]]*(\\}\\)?;?[[:space:]]*)?"


def definition_regex(needle):
    """POSIX ERE (git grep -E, portable: no \\b or \\s) that matches a DEFINITION of `needle`: `def|func|fun|function|fn|class <needle>...` (an identifier may continue after it: pytest -k is a
    substring match) or `it|test|describe|specify(...'<...needle...>`. A bare mention (comment, queue text, string elsewhere) does not match."""
    n = _ere_escape(needle)
    return (DEF_LEAD + "(def|func|fun|function|fn|class)[[:space:]]+" + n +
            "|" + TEST_LEAD + "(it|test|describe|specify)(\\.[a-z]+)?[[:space:]]*\\([[:space:]]*['\"`][^'\"`]*" + n)


def exact_definition_regex(needle):
    """Like definition_regex but the identifier must match EXACTLY (Y2 fix): `class ConfigLoader` does not match `class ConfigLoaderBase`, `test_retry` does not match `test_retry_backoff_policy`.
    POSIX ERE (no \\b): the name must be followed by a non-identifier char (or end of line) and, in the it/test('...') form, delimited on both sides."""
    n = _ere_escape(needle)
    nb = "($|[^A-Za-z0-9_])"
    return (DEF_LEAD + "(def|func|fun|function|fn|class)[[:space:]]+" + n + nb +
            "|" + TEST_LEAD + "(it|test|describe|specify)(\\.[a-z]+)?[[:space:]]*\\([[:space:]]*['\"`]([^'\"`]*[^A-Za-z0-9_])?" + n + "([^A-Za-z0-9_]|['\"`])")


def present_on_ref(repo_dir, ref, needle, exact=False, paths=None):
    """True when `needle` is DEFINED in a code/test file of <ref> in the clone (git grep: path-independent, so a wrong path in the line does not matter; markdown/queue/doc files never count)."""
    if not needle or not needle.strip():
        return False
    try:
        r = subprocess.run(["git", "-C", repo_dir, "grep", "-qE", "-e", (exact_definition_regex if exact else definition_regex)(needle), ref] + (["--"] + list(paths) if paths else list(CODE_PATHSPEC)), capture_output=True, timeout=60)
    except (OSError, UnicodeError, subprocess.SubprocessError):
        return False
    return r.returncode == 0


def present_exact_on_ref(repo_dir, ref, needle, paths=None):
    """present_on_ref with an EXACT identifier match (the done-check must never judge new work done because a longer/prefixed name exists). `paths`: restrict to these files."""
    return present_on_ref(repo_dir, ref, needle, exact=True, paths=paths)


def def_files_on_ref(repo_dir, ref, needle):
    """Set of code files of <ref> that EXACTLY define `needle` (repo-wide)."""
    if not needle or not needle.strip():
        return set()
    try:
        r = subprocess.run(["git", "-C", repo_dir, "grep", "-lE", "-e", exact_definition_regex(needle), ref] + list(CODE_PATHSPEC), capture_output=True, text=True, timeout=60)
    except (OSError, UnicodeError, subprocess.SubprocessError):
        return set()
    return {ln.split(":", 1)[1] if ":" in ln else ln for ln in r.stdout.splitlines() if ln.strip()} if r.returncode == 0 else set()


def verify_on_develop(repo_dir, ref, line, present=present_on_ref):
    """(ok, why): the line names >= 1 test id and every one exists on <ref>."""
    ids = named_test_ids(line)
    if not ids:
        return False, "no named test id in VERIFY"
    missing = [i for i in ids if not present(repo_dir, ref, i)]
    return (not missing), ("missing on %s: %s" % (ref, ", ".join(missing)) if missing else "all %d named test id(s) present on %s" % (len(ids), ref))


# ---------------------------------------------------------------------------------------------- harvest ledger (Y2, 2026-11-04)
# Root cause of the "27B ceiling" re-harvest flood (cqueue 2026-11-04: 109 fragment lines, 88 stale): dedup was ONLY task_sig() = first 12 words (+ feat tag) matched against the queue+archive
# of THIS pass. (1) The AUTO-SKIP lines on the box are never retired when the work lands, so every cycle surfaces fresh fragments of already-landed features; (2) a re-worded / re-tagged
# re-surfacing of a line that was ticked or archived has a different 12-word+tag signature, so it was appended again; (3) the only landed-tag guard was shadow (logged, not enforced), and
# nothing remembered what had ever been harvested once a line left the queue file (hand edit, archive rewrite). The ledger gives every item a STABLE key (repo + full normalized text, with
# [feat:] tag, trailing (cat:..; multifile:..) metadata, checkbox and [CLAUDE] repo/ prefix removed) that is persisted: a key that was ever harvested, or is ticked/archived, is never
# harvested again. The ledger is rebuilt from queue+archive on every pass, so losing the file loses nothing about closed lines.
# Y2 round 5 (N1): body_key strips only TRAILING annotation groups from the END of the line. A closed/annotated line is `<task text> <annotation>*`; every annotation is a recognised, SHAPE-BOUNDED unit that must
# run to the end of the (remaining) text, and body_key peels them one at a time from the right (a loop), never cutting from a mid-text marker. Prose that merely contains a marker word
# ("status DONE, then emit X in a.py", "Add a - TRIAGE column ...", "Remove the (retired flag) handling ... (see line 12)", "_(HOME-TITLE)_ keys in a.vue") is not a unit because (1) each unit needs its real
# opener shape (date, `(verified`, `, no action`, `)_` closer ...), (2) bracketed units are bounded (no unbalanced parens) and must end the line, (3) the weaker word markers (DONE, NOTE:, (done D)) must also
# sit right after a closing token ( `)` `]` `>` `_` `*` `-` ), and (4) text after a marker is never discarded unless the unit is an explicit free-text tail (ALREADY DONE / STALE TICKET / TRIAGE D / (done D ...) / NOTE:).
# Y2 round 6 (R1/N1 residual): peeling is LINEAR (token starts only, last TAIL_WINDOW chars only, whitespace collapsed first) and units are typed b/f/w (see below); a free-text tail is peeled only behind a proven
# opener / closing token and never when it names a file path. Prefer false-DISTINCT over false-collision.
# ENFORCE WARNING: body_key is a heuristic. OVN_HARVEST_LEDGER_MODE and the done-check / autoclose enforce modes MUST NOT be switched to `enforce` until a 1-2 week SHADOW log
# (state/harvest_ledger_skips.log, harvest_skipped_done.log, bridge_autoclose_shadow.log) shows ZERO would-skip lines that are not true duplicates. In enforce a false collision silently and permanently loses a task.
_D = r"\d{4}-\d\d-\d\d"
_P2 = r"(?:[^()]|\((?:[^()]|\([^()]*\))*\))*"      # paren-balanced text, 2 levels deep: the `id(s)` in the real auto-closed suffix holds a ")"
_VER = r"(?:re-)?verified\b"
# Y2 round 6 (R1 linear time + N1 residual). Every unit is tried ONLY at a token start (never searched from every offset), only inside the last TAIL_WINDOW chars, on whitespace-collapsed text, so the cost
# of a peel is O(window), not O(n^2) (round 5: 100 KB of spaces = timeout, `DONE (` + "verified "*11000 = 7 s). Each entry is (regex matched AT the token start, kind):
#   b = BOUNDED unit: a fixed shape that must end the line (`(cat:..)`, `(auto-closed D ..)`, `<!-- closed .. -->`, `_(..)_`): no further task prose can follow it.
#   f = FREE-TEXT tail behind a STRONG opener (date/`verified`/`no action`/em-dash+date+verdict): peeled only when a sentence/closing token ends the text before it.
#   w = FREE-TEXT tail behind a WEAK opener (DONE, NOTE:, check mark, bold): peeled only after a closing token AND only when the swallowed tail names no file path (a tail that names a path is task prose).
# Anything that is not a recognised end-anchored group is NOT peeled: a false-DISTINCT pair only costs one re-harvest, a false collision silently loses a task (enforce mode), so every doubt resolves to "distinct".
_BOUNDARY = ")]>_*-—"
_SENT = _BOUNDARY + ".!?`:;"
TAIL_WINDOW = 2000
MAX_PEELS = 40
_PATH_RE = re.compile(r"[\w.@~-]+/[\w./@~-]*[\w]\.[A-Za-z0-9]{1,6}\b|\b[\w-]+\.(?:py|js|jsx|ts|tsx|vue|md|json|sh|swift|kt|kts|gd|html|css|yml|yaml|toml|txt|sql|cfg|ini|xml|plist|gradle)\b")
_TAIL_DATE = r"(?=.{0,100}?(?:\b" + _VER + r"\s*\(?\s*" + _D + r"|\b" + _D + r"))"
TAIL_UNITS = (
    (re.compile(r"\((?:cat|coverage):[^()]*\)$"), "b"),                                                   # `(cat:impl; multifile:no)` / `(coverage:x)`
    (re.compile(r"\((?:auto-closed|retired)\s+" + _D + _P2 + r"\)$"), "b"),                               # `(auto-closed D: [feat:T] landed, all N named test id(s) present on REF; landing=item)` / `(retired D: ...)`
    (re.compile(r"\(REOPENED\b" + _P2 + r"\)$"), "b"),
    (re.compile(r"(?:SKIPPED\s*)?\(" + _D + r"\b" + _P2 + r"\)$"), "b"),                                  # dated parenthetical `(2026-10-01)` / `SKIPPED (2026-10-01)`
    (re.compile(r"SKIPPED\s*\((?:re-)?verified\s+" + _D + r"\).*$", re.S), "f"),                              # `SKIPPED (verified D) - reason ...`
    (re.compile(r"<!--\s*(?:(?:closed|landed|DONE|STOPPED|retagged|reviewed|verified|reopened|resolved|decided|obsolete|skipped|already)\b|[^\n]{0,40}?" + _D + r")(?:(?!-->).)*-->$", re.S | re.I), "b"),   # `<!-- closed D by claude: done -->`; a plain `<!-- markers -->` in task prose is not one
    (re.compile(r"_\((?:ALREADY-SATISFIED|DONE|RESOLVED|UPDATED|SKIPPED|IMPLEMENTED|REVIEWED|duplicate\b|" + _D + r").*\)_$", re.S), "b"),   # `_(ALREADY-SATISFIED D: ...)_`: a known opener AND the `)_` closer at the very end
    (re.compile(r"(?:[—-]\s*)?\*{0,2}ALREADY DONE\*{0,2}" + _TAIL_DATE + r".*$", re.S), "f"),               # ALREADY DONE only with a verified-date / date in its first 100 chars
    (re.compile(r"(?:[—-]\s*)?\*\*STALE TICKET\*\*.*$", re.S), "f"),
    (re.compile(r"(?:[—-]\s*)?STALE TICKET,\s*no action\s*\((?:re-)?verified\b[^()]*\).*$", re.S), "f"),
    (re.compile(r"[—-]\s+\*{0,2}TRIAGE\s+" + _D + r"(?:\*{0,2}:|\s+[A-Z]{3,}\b).*$", re.S), "f"),   # ` — TRIAGE 2026-10-12 DONE: ...`
    (re.compile(r"\(done\s+" + _D + r"\s*:\s*claude\b.*$", re.S), "f"),                                      # `(done 2026-09-12: claude ...) tests pass`
    (re.compile(r"(?:✅\s*|[—-]\s+)?\*{0,2}DONE\*{0,2}\s*\([^()]*(?:\b" + _VER + r"|@)[^()]*\).*$", re.S), "w"),   # `DONE (shrike-monitor @ H, verified D)`
    (re.compile(r"(?:✅\s*|[—-]\s+)?\*{0,2}DONE\*{0,2}\s*(?:\(" + _D + r"|" + _D + r"\b|$).*$", re.S), "w"),   # `DONE (D, repo @ H)` / `DONE D repo@H: ...` / bare trailing `DONE`
    (re.compile(r"\*{0,2}DONE\*{0,2}\s*\(.*$", re.S), "w"),                                                  # `(cat:impl) DONE (shipped abc)`
    (re.compile(r"\*\*DONE\*\*.*$", re.S), "w"),                                                              # bold `**DONE** (D)`
    (re.compile(r"✅\s*DONE\b.*$", re.S), "w"),
    (re.compile(r"(?:✅\s*|[—-]\s+)?\*{0,2}NOTE:.*$", re.S), "w"),
)
# a feat tag / AUTO-SKIP tag is a bracketed token wherever it sits (leading or trailing) and never part of the task identity (bounded bodies: no quadratic scan on a run of unclosed `[feat:`)
BODY_STRIP_RES = (re.compile(r"\[feat:[^\]\n]{0,200}\]"), re.compile(r"\[AUTO-SKIP[^\]\n]{0,200}\]"))


def _peel_tail(body):
    """Remove ONE trailing annotation group from `body` (None if the end of the text is not one). Linear in the tail window: units are matched only at token starts inside the last TAIL_WINDOW chars."""
    t = " ".join(body.split())
    n = len(t)
    lo = max(0, n - TAIL_WINDOW)
    if lo and not t[lo - 1].isspace():
        sp = t.find(" ", lo)
        lo = n if sp < 0 else sp + 1
    pos = lo
    while pos < n:
        if pos == 0 or t[pos - 1] == " ":
            before = t[:pos].rstrip()
            if before:
                bch = before[-1]
                for rx, kind in TAIL_UNITS:
                    m = rx.match(t, pos)
                    if not m:
                        continue
                    if not _tail_ok(kind, bch, m.group(0)):
                        continue
                    return before
        pos += 1
    return None


_BARE_DONE_RE = re.compile(r"(?:[—-]\s+|✅\s*)?\*{0,2}DONE\*{0,2}\s*(?:\([^()]{0,120}\)|" + _D + r"\S{0,40})?\.?")
_DONE_PROOF_RE = re.compile(r"\([^()]*(?:@|\b" + _VER + r"|" + _D + r")")
_EM_TRIAGE_RE = re.compile(r"—\s+\*{0,2}TRIAGE\s+" + _D)
_PROVEN_RE = re.compile(r"(?:[—-]\s*)?\*{0,2}ALREADY DONE\*{0,2}\b[^\n]{0,60}?\b" + _VER + r"\s*\(?\s*" + _D + r"|STALE TICKET,\s*no action\s*\(" + _VER + r"|SKIPPED\s*\(" + _VER + r"|\*\*STALE TICKET\*\*|\(done\s+" + _D)


_STRONG_DONE_RE = re.compile(r"\*{0,2}DONE\*{0,2}\s*\([^()]*@\s*[0-9a-f]{6,}[^()]*\b" + _VER + r"\s*" + _D + r"[^()]*\)")   # `DONE (repo @ 9b68488, verified 2026-09-08) - <free note naming files>`: commit AND dated verification inside the opener


def _tail_ok(kind, bch, g):
    """May the unit text `g` (match from its token start to the end) be peeled, given the last char `bch` of the text before it?"""
    if kind == "b":
        return True
    if kind == "f":
        if bch in _SENT:
            return True
        if _EM_TRIAGE_RE.match(g):          # an em-dash TRIAGE <date> VERDICT group is a deliberate annotation (its tail names files by design)
            return True
        return bool(_PROVEN_RE.match(g)) and not _PATH_RE.search(g)   # date+`verified` proof in the opener, no path in the tail
    if bch in _BOUNDARY and not _PATH_RE.search(g):
        return True
    if bch in _SENT and _STRONG_DONE_RE.match(g):
        return True
    return bool(_BARE_DONE_RE.fullmatch(g)) and (bch in _SENT or g[:1] in ("—", "-", "✅", "*") or bool(_DONE_PROOF_RE.search(g)))   # bare `DONE` / `DONE (D, repo @ H)` closing


def body_key(repo, text):
    """Stable item key: sha1(repo + the whitespace-normalized task body). Independent of checkbox state, the harvest prefix, the feat tag and every TRAILING annotation group (cat/coverage metadata, auto-closed/retired,
    ALREADY DONE, DONE, TRIAGE, _(..)_, (done D ..), <!-- closed -->, dated parentheticals): they are peeled one at a time from the END of the line, never cut from a mid-text match. Case, operators and punctuation
    are KEPT (`==` vs `!=`, `>` vs `>=`, `class foo` vs `class Foo` are different tasks). Linear time (R1): only the last TAIL_WINDOW chars can hold annotations; the rest of a very long line is simply hashed."""
    import hashlib
    body = " ".join((text or "").split())   # one linear pass: whitespace runs collapse before anything else looks at the text
    body = re.sub(r"^- \[[ xX]\] ", "", body)
    for rx in BODY_STRIP_RES:
        body = rx.sub(" ", body)
    for _ in range(MAX_PEELS):
        nb = _peel_tail(body)
        if nb is None:
            break
        body = nb
    body = LEADING_TAGS_RE.sub("", body)
    body = REPO_PREFIX_RE.sub("", body)
    body = LEADING_TAGS_RE.sub("", body)
    body = " ".join(body.split()).rstrip(" .")
    return hashlib.sha1((repo + "|" + body).encode("utf-8", "replace")).hexdigest()[:20]


def load_ledger(path):
    """{key: state} from the ledger TSV (key, state, repo, feat_tag, date). Missing/unreadable file = empty. LATEST row wins (Y2 r3 D1): harvested -> closed is a state transition, so a key that was
    harvested and later ticked reads as `closed` and is not re-appended every pass."""
    out = {}
    if not path:
        return out
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for row in f:
                parts = row.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0]:
                    out[parts[0]] = parts[1]
    except OSError:
        pass
    return out


def append_ledger(path, rows):
    """Append (key, state, repo, tag, date) rows (no-op without a path; never raises)."""
    if not path or not rows:
        return
    try:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            for key, state, repo, tag, day in rows:
                f.write("%s\t%s\t%s\t%s\t%s\n" % (key, state, repo, tag or "", day))
    except OSError:
        pass


def closed_keys(lines):
    """{(key, repo, tag)} of every CHECKED line (queue + archive) whose repo can be inferred."""
    out, header = set(), ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = CHECKED_ITEM_RE.match(ln)
        if not m:
            continue
        repo = infer_repo(m.group(1), header)
        if repo:
            out.add((body_key(repo, m.group(1)), repo, feat_tag_of(m.group(1))))
    return out


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


def autoclose_lines(lines, tags, repos_dir, ref, today, present=present_on_ref, hashes=None, require_item=False):
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
                    item_landed = line_key(m.group(1)) in hs
                    why += "; landing=%s" % ("item" if item_landed else "feature")
                    if require_item and not item_landed:
                        out.append(ln)   # Y2: enforce only closes the line that itself landed; a sibling landing under the same [feat:] tag proves nothing about this line
                        continue
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
    raw_lines = read_text_raw(args.queue).split("\n")   # Y2 r5 (N2): "\n" only, see cmd_retire
    final_nl = bool(raw_lines) and raw_lines[-1] == ""
    if final_nl:
        raw_lines.pop()
    crs = [("\r" if x.endswith("\r") else "") for x in raw_lines]
    raw_cores = [x[:-1] if cr else x for x, cr in zip(raw_lines, crs)]
    lines = [clean_text(x) for x in raw_cores]
    req = os.environ.get("OVN_BRIDGE_AUTOCLOSE_REQUIRE_ITEM", "off").strip().lower() == "on"
    new, closed = autoclose_lines(lines, landed_tags(args.outcomes), args.repos_dir, args.ref, args.today, hashes=landed_line_hashes(args.outcomes), require_item=(mode == "enforce" and req))
    for lineno, repo, tag, why in closed:
        # Y2: dedupe per (repo, line text hash, tag, day): the line NUMBER shifts every pass (appends/archives), which is why the old key repeated rows 20+ times a day
        ltxt = lines[lineno - 1] if 0 < lineno <= len(lines) else ""
        k = "%s %s would-close %s [feat:%s] k=%s " % (args.today, "ENFORCED" if mode == "enforce" else "SHADOW", repo, tag, body_key(repo, ltxt))
        _shadow_once(args.shadow_log, k, "%s(line %d; %s)" % (k, lineno, why))
    if mode == "enforce" and closed:
        out = []
        for raw, raw_core, cr, c, n in zip(raw_lines, raw_cores, crs, lines, new):   # unchanged lines keep their original bytes; a closed line = original + the appended auto-closed suffix (before its CR)
            out.append(raw if n == c else raw_core.replace("- [ ]", "- [x]", 1) + n[len(c):] + cr)
        write_text_atomic(args.queue, "\n".join(out) + ("\n" if final_nl else ""))
    sys.stderr.write("autoclose: mode=%s %s=%d\n" % (mode, "closed" if mode == "enforce" else "would-close", len(closed)))


TEST_ITEM_RE = re.compile(r"cat:test\b|\[T\d\]\s+\S*(?:/tests?/|tests?/|test_[^/\s]*\.|\.test\.|\.spec\.|_test\.|Tests?\.(?:kt|swift)|\.test\b)", re.I)


CREATE_VERB_RE = re.compile(r"^\s*(?:\[[^\]]+\]\s*)*(?:\S+\s+[\u2014-]\s+)?(?:add|create|define|introduce|write)\b", re.I)
OTHER_VERB_RE = re.compile(r"\b(?:modify|replace|update|change|wire|call|rename|remove|delete|fix|make|extend|refactor|import)\b", re.I)
NEW_DEF_RES = (re.compile(r"`(?:class|def|func|function|fun)\s+([A-Za-z_][A-Za-z0-9_]*)"), re.compile(r"`(test_[A-Za-z0-9_]+)"))


def named_new_defs(task):
    """Identifiers a PURE creation item ('Add/Create ... `class X` / `test_y`', no modify/replace/update verb before its VERIFY) says it introduces ([] for any other item)."""
    body = re.split(r"\bVERIFY:", task or "", maxsplit=1)[0]
    if not CREATE_VERB_RE.search(body) or OTHER_VERB_RE.search(body):
        return []
    ids = []
    for rx in NEW_DEF_RES:
        for g in rx.findall(body):
            if g not in ids:
                ids.append(g)
    return ids


GENERIC_NAMES = {"config", "settings", "main", "app", "base", "test", "tests", "model", "models", "client", "util", "utils", "helper", "helpers", "handler", "manager", "service", "router", "index", "item", "data", "error", "result", "schema"}
TARGET_PATH_RE = re.compile(r"(?<![\w./-])((?:[\w.-]+/)*[\w.-]+\.(?:py|ts|tsx|js|jsx|mjs|kt|java|swift|gd|go|rs|rb|sh|sql|cs|cpp|c|h))(?![\w/-])")


def is_generic_name(name):
    return len(name) <= 6 or name.lower() in GENERIC_NAMES


REFERENCE_CTX_RE = re.compile(r"(?:modell?ed|based|similar|same as|\blike\b|\bsee\b|copy|copied|mirror|follow|pattern|\bper\b|\bfrom\b|imitat|as in|reference|\bref\b|derived|inspired|compare|\bvs\b)[^.;]*$", re.I)


def target_files(task):
    """File path(s) the item names as its OWN target: the leading `[Tn] path -` one when present, else the code paths named before VERIFY that are not REFERENCE files (Y2 r3 D3: a path introduced by
    'modelled on / based on / like / see / copied from ...' is where the pattern lives, not where the item's work goes, so a definition there proves nothing)."""
    body = re.split(r"\bVERIFY:", task or "", maxsplit=1)[0]
    m = re.match(r"^\s*(?:\[[^\]]+\]\s*)*(?:\S+/\s+[\u2014-]\s+)?(?:\[[^\]]+\]\s*)*`?(" + TARGET_PATH_RE.pattern[len("(?<![\\w./-])"):-len("(?![\\w/-])")] + r")`?\s+[\u2014-]\s", body)
    if m:
        return [m.group(1)]
    out = []
    for pm in TARGET_PATH_RE.finditer(body):
        g = pm.group(1)
        if g in out or REFERENCE_CTX_RE.search(body[max(0, pm.start() - 40):pm.start()]):
            continue
        out.append(g)
    return out


def has_named_paths(task):
    body = re.split(r"\bVERIFY:", task or "", maxsplit=1)[0]
    return bool(TARGET_PATH_RE.search(body))


def done_evidence(repos_dir, repo, ref, task, present=present_exact_on_ref):
    """(done, strong, why). done: the item's named identifiers are all DEFINED where the item says they live. strong: the evidence is a named TARGET FILE of the item holding the EXACT definition (only
    strong evidence may be remembered in the ledger). With no named file: every id must be non-generic (> 6 chars, not Config/Settings/main/...) and defined in exactly ONE file repo-wide, and the result
    is never strong (skip this pass only). Generic names without a named file are never done."""
    if TEST_ITEM_RE.search(task or ""):
        ids = named_test_ids(task) or named_new_defs(task)
        if not ids:
            return False, False, "no named test id in VERIFY"
    else:
        ids = named_new_defs(task)   # Y2: a pure creation item whose named new class/def/test already exists in code
        if not ids:
            return False, False, "not a test-writing or pure creation item"
    clone = os.path.join(repos_dir, repo)
    if not os.path.isdir(clone):
        return False, False, "no clone"
    files = target_files(task)
    if not files and has_named_paths(task):
        return False, False, "only reference file(s) named (modelled on/based on ...), no target file of its own"
    if files:
        # every id must be defined in EVERY target file (never the union: a def in one file says nothing about another); more than one target file is never strong evidence
        missing = [i for i in ids if not all(present(clone, ref, i, paths=[f]) for f in files)]
        done = not missing
        return done, (done and len(files) == 1), ("missing in %s on %s: %s" % (",".join(files), ref, ", ".join(missing)) if missing else "all %d named test id(s) defined in target file %s on %s" % (len(ids), ",".join(files), ref))
    generic = [i for i in ids if is_generic_name(i)]
    if generic:
        return False, False, "no target file named and generic/short name(s) never judged done: %s" % ", ".join(generic)
    for i in ids:
        if len(def_files_on_ref(clone, ref, i)) != 1:
            return False, False, "no target file named and %s is not defined in exactly one file repo-wide" % i
    return True, False, "no target file named; each id uniquely defined repo-wide on %s (weak evidence: skip this pass only)" % ref


def done_check(repos_dir, repo, ref, task, present=present_exact_on_ref):
    """(done, why) for the pre-harvest check (S3-guards2, cqueue F6). See done_evidence for the rules; an implementation item that names an existing (red) test is NOT judged done."""
    d, _s, why = done_evidence(repos_dir, repo, ref, task, present)
    return d, why


def done_check_mode(arg=None):
    """Y2 r3 D4: default SHADOW (log what would be skipped, skip nothing, write no `done` ledger rows) until the done log has been reviewed; enforce is opt-in (`enforce` or its alias `on`).
    An unknown value falls back to shadow (never enforces by accident)."""
    v = (arg or os.environ.get("OVN_HARVEST_DONE_CHECK") or "shadow").strip().lower()
    if v == "on":
        v = "enforce"
    return v if v in ("shadow", "enforce", "off") else "shadow"


def ledger_mode(arg=None):
    """Y2 r3 D4: ledger-skip mode. Default SHADOW (log `would-skip`, harvest anyway); `enforce` (alias `on`) skips a key that was ever harvested/ticked/archived; `off` disables the ledger skip AND its writes.
    Unknown values fall back to shadow."""
    v = (arg or os.environ.get("OVN_HARVEST_LEDGER_MODE") or "shadow").strip().lower()
    if v == "on":
        v = "enforce"
    return v if v in ("shadow", "enforce", "off") else "shadow"


def cmd_harvest(args):
    lines = read_text(args.queue).splitlines() + read_lines_optional(args.archive)
    existing_sigs = {task_sig(t) for t, _ in iter_all_items(lines)}
    ledger_path = getattr(args, "ledger", "") or ""
    lmode = ledger_mode(getattr(args, "ledger_mode", None))
    if lmode == "off":
        ledger_path = ""
    ledger = load_ledger(ledger_path)
    new_closed = [(k, "closed", r, t, args.today) for k, r, t in sorted(closed_keys(lines), key=lambda x: x[0]) if ledger.get(k) != "closed"]
    for k, _, _, _, _ in new_closed:
        ledger[k] = "closed"
    append_ledger(ledger_path, new_closed)
    new_rows = []
    mode = autoclose_mode(getattr(args, "mode", None))
    closed = {("", t) for t in closed_tags(lines)} | (landed_tags(args.outcomes) if getattr(args, "outcomes", "") else set()) if mode != "off" else set()
    dmode = done_check_mode(getattr(args, "done_mode", None)) if getattr(args, "repos_dir", "") else "off"
    new_items = []
    for ln in read_text(args.autoskip).splitlines():
        if "\t" not in ln:
            continue
        repo, task = ln.split("\t", 1)
        repo, task = repo.strip(), task.strip()
        if not repo or len(task) < 20:   # guard: never harvest a stub/garbage task
            continue
        if task_sig(task) in existing_sigs:
            continue
        key = body_key(repo, task)
        if key in ledger and lmode != "off":   # Y2: ever harvested, or ticked/archived: never again (even re-worded sig / re-tagged / line since deleted) -- enforce only; shadow logs and harvests as before
            _shadow_once(getattr(args, "ledger_log", ""), "%s %s ledger-skip %s k=%s " % (args.today, "ENFORCED" if lmode == "enforce" else "SHADOW", repo, key), "%s %s ledger-skip %s k=%s state=%s %s" % (args.today, "ENFORCED" if lmode == "enforce" else "SHADOW", repo, key, ledger[key], task[:90]))
            if lmode == "enforce":
                continue
        tag = feat_tag_of(task)
        if tag and _tag_landed(closed, repo, tag):      # P5: a feature already closed (or landed by the fleet) is not re-opened under different wording
            _wk = "%s %s would-not-reharvest %s [feat:%s] k=%s" % (args.today, "ENFORCED" if mode == "enforce" else "SHADOW", repo, tag, key)
            _shadow_once(getattr(args, "shadow_log", ""), _wk, _wk)
            if mode == "enforce":
                continue
        if dmode != "off":
            done, dstrong, dwhy = done_evidence(args.repos_dir, repo, getattr(args, "done_ref", "origin/claude/feature"), task)
            if done:
                tagm = "%s %s would-skip-done %s tag=%s k=%s" % (args.today, "ENFORCED" if dmode == "enforce" else "SHADOW", repo, tag or "-", key)   # one row per (repo, line, tag, day)
                _shadow_once(getattr(args, "done_log", ""), tagm, "%s (%s) %s" % (tagm, dwhy, task[:90]))
                if dmode == "enforce":
                    if dstrong and key not in ledger:   # target file + exact definition only: remembered so a done-skipped line is not re-checked against git every hour
                        ledger[key] = "done"
                        new_rows.append((key, "done", repo, tag, args.today))
                    continue      # weak evidence: skipped THIS pass only, never ledgered
        existing_sigs.add(task_sig(task))
        if key not in ledger:   # shadow mode can reach here with a known key: never overwrite/duplicate its state (closed must stay closed)
            ledger[key] = "harvested"
            new_rows.append((key, "harvested", repo, tag, args.today))
        new_items.append((repo, task))
    if not new_items:
        append_ledger(ledger_path, new_rows)
        sys.stderr.write("harvest: nothing new to add\n")
        return
    today = args.today
    block = [f"\n## Auto-harvested from 27B ceiling [{today}] — the fleet tried these N cycles and kept reverting; Claude to implement\n"]
    for repo, task in new_items:
        block.append(f"- [ ] [CLAUDE] {repo}/ — {task}\n")
    with open(args.queue, "a", encoding="utf-8") as f:
        f.write("".join(block))
    append_ledger(ledger_path, new_rows)
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
    hp.add_argument("--ledger", default="")
    hp.add_argument("--ledger-log", default="")
    hp.add_argument("--ledger-mode", default="")
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
