#!/usr/bin/env python3
"""scripts/ovn_backlog_eligibility.py - the ONE definition of "can the fleet take this backlog line" (spec-compiler-v2 part A, 2026-10-09).

Why this exists. queue_refill.py parked a backlog line with `re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|BLOCKED", re.I)`. The `re.I` made the lowercase words
blocked / unblocked / test_..._blocked / blocked_reason park the line. Measured on the live backlog (2026-10-09): all 10 open iptv_apps items and both open xlite
items were parked by it (parental PIN lockout, SSRF stream test, content-rights guard, ability_resolver blocked_reason - security items among them), and no
line containing the word 'blocked' had ever reached a queue (477 + 445 T-items). `BLOCKED` is a TAG the harness writes (`BLOCKED ITEM`), so it is matched
CASE-SENSITIVELY; the tags that really are case-insensitive keep re.I.

  PARKED_CI   re.I   AUTO-SKIP | HUMAN-ONLY | HUMAN/ | HARD FILE BAN | (retired- | [CLAUDE]
  PARKED_CS   exact  BLOCKED
The union is deliberately a SUPERSET of what each earlier caller excluded: queue_refill lacked [CLAUDE]/retired/HARD FILE BAN, the work-supply _HELD lacked bare
BLOCKED. The only lines that become pullable are those whose sole match was the lowercase word (scripts/test/test_backlog_eligibility.py proves that).
The bash twin is scripts/lib_parked_pattern.sh (OVN_PARKED_CI_ERE / OVN_PARKED_CS_ERE) - keep the two in step.

Also here (shared by queue_refill, ovn_spec_classify, ovn_spec_rules, ovn_spec_gate so they cannot drift apart):
  norm_line / strip_feat_date   the item identity queue_refill._norm uses (tags stripped, feat date stamp stripped, whitespace collapsed)
  line_hash                     sha1(norm_line)[:12], the stable key of a backlog item
  extract_verify                the VERIFY command of an item line (backticked, or bare up to ' (cat:')
  item_target / load_banned / is_banned_target   the A2 ingest ban filter (.queue-hard-banned-files + addons/)
  normalize_vacuous_echo        A3: `cmd && echo FAIL || echo PASS` -> `! ( cmd )`, `cmd && echo PASS || echo FAIL` -> `cmd`

CLI:  python3 scripts/ovn_backlog_eligibility.py sites [root]   -> lists the sites that still match BLOCKED case-insensitively (exit 1 when any: the deploy pre-flight)
      python3 scripts/ovn_backlog_eligibility.py count <repo_dir> <backlog_file>   -> prints the number of pullable items
      (<repo_dir>/OVERNIGHT_PROGRESS.md and OVERNIGHT_DONE.md are the queued/done sets; the repo's hard-ban list is applied unless OVN_INGEST_BAN_FILTER=off).
"""
import hashlib
import os
import re
import sys

PARKED_CI = re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|HARD FILE BAN|\(retired-|\[CLAUDE\]", re.I)
PARKED_CS = re.compile(r"BLOCKED")
OPEN_ITEM = re.compile(r"^- \[ \] \[T[1-5]\]")


def _tag_parked(line):
    return bool(PARKED_CI.search(line) or PARKED_CS.search(line))


def is_parked(line):
    """PARKED_CI or PARKED_CS, plus the lowercase word `blocked` per OVN_PARKED_BLOCKED_CI:
        on            legacy: any line containing 'blocked' (any case) is parked (kill switch / rollback)
        off           the tag is case-sensitive only: a lowercase 'blocked' item is pullable (forced unlock, no deploy-order guard)
        auto (default) like `off` ONLY when no other site in the tree still matches BLOCKED case-insensitively (see unconverted_blocked_sites); while one does, the line stays
                      parked, because the pre-dispatch / top-item pickers there would skip an unlocked item that then sits in the queue counting as open (deploy-order trap).
    OVN_PARKED_SITES_GUARD=off disables the audit (auto == off)."""
    if _tag_parked(line):
        return True
    if not re.search("blocked", line, re.I):
        return False
    mode = os.environ.get("OVN_PARKED_BLOCKED_CI", "auto")
    if mode == "on":
        return True
    if mode == "off":
        return False
    return sites_guard_active()


def held_by_sites_guard(line):
    """True when `line` is parked ONLY because of the deploy-order guard (it would be pullable once the remaining BLOCKED sites are converted)."""
    return (not _tag_parked(line)) and bool(re.search("blocked", line, re.I)) and os.environ.get("OVN_PARKED_BLOCKED_CI", "auto") not in ("on", "off") and sites_guard_active()


# ---------------------------------------------------------------- deploy-order guard: sites that still match BLOCKED case-insensitively
# The tag BLOCKED (`BLOCKED ITEM`) is matched case-sensitively here and in lib_parked_pattern.sh. Any OTHER place that skips a line with a case-insensitive alternation
# containing BLOCKED (`grep -viE '...|BLOCKED|...'`, `re.compile(r"...|BLOCKED|...", re.I)`) would silently skip an unlocked lowercase-"blocked" item. unconverted_blocked_sites
# finds them (the converted forms - `(?-i:BLOCKED)` in a python regex, a separate case-sensitive `grep -vE 'BLOCKED'` in shell - are not matched).
_SITE_SKIP_DIRS = {"test", "tests", "__pycache__", "node_modules", ".git"}
_SITE_ROOT_DIRS = ("scripts", "qa", "tools")
_ALT_MEMBER = re.compile(r"(?:^|\|)BLOCKED(?:$|\|)")
_VERDICT_ALT = re.compile(r"VERDICT|NEEDS-DECISION")        # the model's one-word verdict (PROCEED|ALREADY-DONE|BLOCKED|NEEDS-DECISION) is not a queue-line filter
_SH_GREP_I = re.compile(r"""grep\s+(?:-[A-Za-z]+\s+)*-[A-Za-z]*i[A-Za-z]*\s+(?:-e\s+)?(?:'([^']*)'|"([^"]*)")""")
_PY_CI_FLAG = re.compile(r"\bre\.I\b|\bre\.IGNORECASE\b|\bIGNORECASE\b")
_STR_LIT = re.compile(r"""[rbfu]*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')""")


def _site_in_line(path, line):
    """True when `line` (one source line) is a case-insensitive alternation that still lists BLOCKED as a member."""
    code = line.lstrip()
    if code.startswith("#"):
        return False
    if path.endswith(".py"):
        code = re.sub(r"\s+#[^\"']*$", "", code)      # a trailing comment without quotes ("# no re.I here") is not code
        if not _PY_CI_FLAG.search(code):
            return False
        return any(_ALT_MEMBER.search(t) and not _VERDICT_ALT.search(t) for t in (m.group(1) or m.group(2) or "" for m in _STR_LIT.finditer(code)))
    for m in _SH_GREP_I.finditer(code):
        t = m.group(1) or m.group(2) or ""
        if _ALT_MEMBER.search(t) and not _VERDICT_ALT.search(t):
            return True
    return False


def unconverted_blocked_sites(root):
    """[(relative path, line number, stripped line)] of every non-test .sh/.py file under `root` (its top level, scripts/, qa/, tools/) that still matches BLOCKED case-insensitively."""
    found = []
    files = []
    try:
        for n in sorted(os.listdir(root)):
            fp = os.path.join(root, n)
            if os.path.isfile(fp) and n.endswith((".sh", ".py")):
                files.append(fp)
        for d in _SITE_ROOT_DIRS:
            for dp, dns, fns in os.walk(os.path.join(root, d)):
                dns[:] = sorted(x for x in dns if x not in _SITE_SKIP_DIRS and not x.startswith("proposals-"))
                files += [os.path.join(dp, n) for n in sorted(fns) if n.endswith((".sh", ".py"))]
    except OSError:
        return found
    for fp in files:
        if os.path.basename(fp) in ("lib_parked_pattern.sh", "ovn_backlog_eligibility.py", "ovn_convert_blocked_sites.py"):
            continue
        try:
            with open(fp, encoding="utf-8", errors="replace") as f:
                for i, raw in enumerate(f, 1):
                    if "BLOCKED" in raw and _site_in_line(fp, raw):
                        found.append((os.path.relpath(fp, root), i, raw.strip()[:160]))
        except OSError:
            continue
    return found


_SITES_CACHE = {}


def sites_root():
    return os.environ.get("OVN_PARKED_SITES_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sites_guard_active():
    """The deploy-order guard: True while OVN_PARKED_SITES_GUARD != off and the tree still has an unconverted BLOCKED site. Cached per process and root."""
    if os.environ.get("OVN_PARKED_SITES_GUARD", "on") == "off":
        return False
    root = sites_root()
    if root not in _SITES_CACHE:
        _SITES_CACHE[root] = unconverted_blocked_sites(root)
    return bool(_SITES_CACHE[root])


def sites_guard_notice():
    root = sites_root()
    sites = _SITES_CACHE.get(root) or []
    if not sites:
        return ""
    first = "%s:%d" % (sites[0][0], sites[0][1])
    return ("%d site(s) still match BLOCKED case-insensitively (first %s) - lowercase-'blocked' backlog items stay held back until they are converted "
            "(docs/patches/ in the spec-compiler-v2 package; OVN_PARKED_BLOCKED_CI=off forces the unlock, OVN_PARKED_SITES_GUARD=off disables this guard)" % (len(sites), first))


def is_open_item(line):
    return bool(OPEN_ITEM.match(line))


# ---------------------------------------------------------------- identity (same as queue_refill._norm)
def strip_feat_date(text):
    def _one(m):
        tag = re.sub(r"-\d{8}-", "-", m.group(0), count=1)
        return re.sub(r"-\d{6}-", "-", tag, count=1)
    return re.sub(r"\[feat:[^\]]+\]", _one, text)


def norm_line(line):
    line = re.sub(r"^(\s*- \[[ xX]\] )(\[(?:AUTO-SKIP|HUMAN-ONLY)[^\]]*\]\s*)+", r"\1", line)
    m = re.search(r"\]\s*(.*)$", line)  # content after the last tag bracket
    content = strip_feat_date((m.group(1) if m else line).strip())
    return re.sub(r"\s+", " ", content.lower())


def line_hash(line):
    return hashlib.sha1(norm_line(line).encode("utf-8", "replace")).hexdigest()[:12]


# ---------------------------------------------------------------- VERIFY extraction (same as queue_refill._extract_verify)
def extract_verify(line):
    m = re.search(r'VERIFY:\s*`([^`]+)`', line)
    if not m:
        m = re.search(r'VERIFY:\s*(.+?)\s*\(cat:', line)
    return m.group(1).strip() if m else None


# ---------------------------------------------------------------- R14 verify packages: VERIFY polarity (2026-10-12, xlite X1)
# The VERIFY contract is "exit 0 = pass", but the decomposer / 27B routinely write ABSENCE checks as `cmd` + prose ("returns no matches", "fails with No such file",
# "returns false"). Every reader that ran the command and took rc==0 as "satisfied" had the polarity inverted: unfinished work was credited (the symbol still exists, grep exits
# 0) and finished work was refused. verify_polarity reads the sentence right after the closing backtick; credit paths then require the exit status to MATCH it.
#   neg      the narration is exactly an absence / failure verdict of an exit-code command (grep family, test/[, ls, cat, stat, find, diff, cmp)
#   pos      the narration is explicitly a presence / success verdict
#   unknown  anything else: no narration, a mixed or time-qualified narration (before/currently/when/if ...), a command that already starts with `!` (already negated, e.g. by R03),
#            or a runner whose exit code is not the narrated fact (pytest/godot/npm/gradlew/python -c). Callers then behave exactly as before.
_POL_NEG = re.compile(
    r"\bfails?\b|\bfailing\b"
    r"|\b(?:returns?|prints?|outputs?|yields?|gives?|produces?|shows?|finds?|has|have|lists?)\s+(?:a\s+|an\s+)?(?:no\s+(?:results?|lines?|output|matches?|hits?|rows?|occurrences?|references?|callers?|usages?|uses)|nothing|empty|false|non-?zero|zero\s+(?:results?|lines?|matches|hits|occurrences)|none)\b"
    r"|\bexits?\s+(?:with\s+)?(?:a\s+)?(?:non-?zero|1\b|status\s+1|code\s+1)"
    r"|\b(?:is|are|was|were|be)\s+(?:absent|missing|removed|gone|deleted|not\s+(?:found|present|defined|exist))"
    r"|\bdoes(?:\s+not|n'?t)\s+exist\b|\bno\s+such\s+file\b|\bnot\s+found\b"
    r"|^\s*(?:no|zero)\s+(?:results?|lines?|output|matches?|hits?|occurrences?)\b|\b(?:with|has|gives?)\s+no\s+(?:results?|lines?|output|matches?|hits?)\b", re.I)
_POL_POS = re.compile(
    r"\bpass(?:es|ed|ing)?\b|\bsucceed(?:s|ed)?\b|\bexits?\s+(?:with\s+)?(?:0\b|zero|status\s+0|code\s+0)|\breturns?\s+(?:a\s+|an\s+|the\s+)?(?:match(?:es)?|results?|lines?|output|true|hits?|exit\s+(?:code\s+)?0|zero\s+exit)\b"
    r"|\b(?:is|are)\s+(?:present|found|defined|exported)\b|\bexists?\b|\bcontains?\b|\bfinds?\s+(?:a\s+|the\s+)?(?:match|line|result)", re.I)
# a narration describing the state BEFORE the change (red state), or conditional on something, says nothing about the post-change verdict
_POL_QUAL = re.compile(r"\b(?:before|currently|today|initially|originally|prior|at\s+present|at\s+the\s+moment|until|pre-?change|pre-?fix|old|previously|when|whenever|if|unless|because|since|while|red|expected:|then\s+pass|but|though|although|otherwise)\b", re.I)
_POL_EXIT_TOOLS = {"test", "[", "ls", "cat", "stat", "find", "diff", "cmp", "readlink"}
_POL_GREP_TOOLS = {"grep", "egrep", "fgrep", "rg", "ag", "zgrep"}


def _split_clauses(cmd):
    """Quote-aware split of a shell command on && || ; | (operators dropped). Returns the list of clause strings, or None when quotes do not balance."""
    out, cur, q, i = [], "", "", 0
    while i < len(cmd):
        ch = cmd[i]
        if q:
            cur += ch
            if ch == q:
                q = ""
        elif ch in "'\"":
            q = ch
            cur += ch
        elif cmd.startswith("&&", i) or cmd.startswith("||", i):
            out.append(cur)
            cur = ""
            i += 1
        elif ch in ";|":
            out.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    out.append(cur)
    return None if q else [c.strip() for c in out if c.strip()]


def verify_tool_class(cmd):
    """'grep' | 'exit' | 'runner' | '' - the class of the command whose exit status ends the clause (the LAST clause: `a | grep x`, `cd d && grep x f`)."""
    cl = _split_clauses(cmd or "")
    if not cl:
        return ""
    toks = cl[-1].split()
    while toks and (toks[0] == "!" or not toks[0].strip("()") or re.match(r"^[A-Za-z_]\w*=", toks[0])):
        toks = toks[1:]
    if not toks:
        return ""
    w = os.path.basename(toks[0].strip("()"))
    if w in _POL_GREP_TOOLS:
        return "grep"
    if w in _POL_EXIT_TOOLS:
        return "exit"
    return "runner"


def _narration_after_backtick(line, m):
    rem = line[m.end():]
    cuts = [i for i in (rem.find("(cat:"), rem.find(" [feat:"), rem.find("<!--")) if i >= 0]
    if cuts:
        rem = rem[:min(cuts)]
    se = re.search(r"\.(?=\s|$)", rem)
    return rem[:se.start()] if se else rem


_NARR_COMPOUND_TAIL = re.compile(r"(?:[\s,;]*\band)?[\s,;]*$", re.I)


def narration_head(text):
    """The part of a VERIFY narration that talks about the FIRST command: everything up to the first backtick (a second command or a quoted symbol starts there), with a trailing
    ' and' / ',' / ';' dropped. 2026-10-13 (iptv F3): `grep -rn "X" d/` returns nothing and `python -c ...` succeeds - the old rule returned 'unknown' for ANY narration containing a
    backtick, so already_satisfied fell back to 'grep exit 0 = satisfied' and credited two items whose class was still in the tree. The head ('returns nothing') is the verdict on the
    first command, which is the one every credit path runs; the tail narrates the second command and is not its verdict. OVN_VERIFY_NARRATION_HEAD=off restores the old unknown."""
    t = re.sub(r"\s+", " ", text.strip().lstrip(",:-\u2014\u2013 ").strip())
    if "`" not in t:
        return t
    if os.environ.get("OVN_VERIFY_NARRATION_HEAD", "on") == "off":
        return t
    raw = t[:t.index("`")]
    # only a JOIN ('... and `cmd2`', '..., `cmd2`', '...; `cmd2`') ends the head of the first command. A backtick that continues the sentence ('returns no lines containing `X`',
    # 'returns no matches for `X`') quotes an operand that NARROWS the claim below what the command itself checks: that stays unknown, exactly as before this fix.
    if not re.search(r"(?:\band|\bthen|[,;&])\s*$", raw, re.I):
        return t
    return _NARR_COMPOUND_TAIL.sub("", raw).strip()


def _polarity_of_text(text):
    t = re.sub(r"\s+", " ", text.strip().lstrip(",:-\u2014\u2013 ").strip())
    if "`" in t:
        # a qualifier ('but', 'before', 'if' ...) anywhere in the narration - quoted spans removed - still makes the whole thing unknown
        if _POL_QUAL.search(re.sub(r"`[^`]*`", " ", t)):
            return "unknown"
        t = narration_head(t)
        if "`" in t:       # kill switch: the old rule (any backtick = unknown)
            return "unknown"
    if not t:
        return "unknown"
    if _POL_QUAL.search(t):
        return "unknown"
    neg, pos = bool(_POL_NEG.search(t)), bool(_POL_POS.search(t))
    if neg and not pos:
        return "neg"
    if pos and not neg:
        return "pos"
    return "unknown"


def verify_clause_and_polarity(line):
    """(command, polarity) of an item line's VERIFY clause. Backticked: the narration is the sentence after the closing backtick. Bare (`VERIFY: grep ... returns no results. (cat:`):
    a trailing negative phrase is split off the clause and the command is what precedes it (only when it is one of the exit-code tools). ('', 'unknown') when there is no clause."""
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if m:
        cmd = m.group(1).strip()
        if cmd.startswith("!") or re.match(r"^test\s+!", cmd):
            return cmd, "unknown"
        pol = _polarity_of_text(_narration_after_backtick(line, m))
        if pol != "unknown" and verify_tool_class(cmd) == "runner":
            pol = "unknown"
        return cmd, pol
    m = re.search(r"VERIFY:\s*(.+?)\s*\(cat:", line)
    if not m:
        return "", "unknown"
    clause = m.group(1).strip()
    if clause.startswith("!"):
        return clause, "unknown"
    # find the earliest negative phrase OUTSIDE quotes; everything before it is the command, everything after is narration
    masked = re.sub(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"", lambda x: "_" * len(x.group(0)), clause)
    nm = _POL_NEG.search(masked)
    if not nm:
        return clause.rstrip(". "), "unknown"
    cmd, tail = clause[:nm.start()].strip(), clause[nm.start():]
    if not cmd or verify_tool_class(cmd) in ("", "runner"):
        return clause.rstrip(". "), "unknown"
    t = tail.rstrip(". ")
    se = re.search(r"\.(?=\s|$)", tail)
    if se:
        t = tail[:se.start()]
    if _polarity_of_text(t) != "neg":
        return clause.rstrip(". "), "unknown"
    return cmd, "neg"


def verify_polarity(line):
    """'pos' | 'neg' | 'unknown': the stated polarity of an item line's VERIFY (see the block comment above)."""
    return verify_clause_and_polarity(line)[1]


def absence_narration_unresolved(line):
    """True when an item's backticked exit-code VERIFY (grep family / ls / test / stat / cat / find) carries a narration that SAYS absence ('returns nothing', 'no matches', 'fails with No such
    file') but the polarity reader could not turn it into `neg` (a red-state / conditional / mixed narration). Such an item must not be credited from 'exit 0 = satisfied': rc 0 there may mean
    the thing is STILL PRESENT (iptv F3, 2026-10-13: two pre-verified credits for classes that were still in the tree). Callers that pre-credit on a bare exit status (queue_refill.already_satisfied)
    refuse these. False for a command that is already negated (`! grep`, `test !`), a runner (pytest / python -c), no narration, or any item whose polarity resolved. OVN_VERIFY_AMBIGUOUS_NEG=off disables."""
    if os.environ.get("OVN_VERIFY_AMBIGUOUS_NEG", "on") == "off":
        return False
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if not m:
        return False
    cmd = m.group(1).strip()
    if cmd.startswith("!") or re.match(r"^test\s+!", cmd) or verify_tool_class(cmd) not in ("grep", "exit"):
        return False
    if verify_polarity(line) != "unknown":
        return False
    narr = re.sub(r"\s+", " ", _narration_after_backtick(line, m).strip().lstrip(",:-\u2014\u2013 ").strip())
    return bool(_POL_NEG.search(narration_head(narr)))


def polarity_verdict(polarity, tool_class, rc):
    """Map a raw exit status to PASS/FAIL given the stated polarity: True = the condition the item states holds. rc 124/126/127 (timeout / not runnable) is never a verdict: None.
    pos / unknown: rc == 0. neg: grep family rc == 1 only (rc >= 2 is an error, not an absence); other exit-code tools any rc other than 0 / 124 / 126 / 127."""
    if rc in (124, 126, 127):
        return None
    if polarity != "neg":
        return rc == 0
    if tool_class == "grep":
        return rc == 1
    return rc != 0


# ---------------------------------------------------------------- A2: hard-banned / vendored targets
_TARGET_RE = re.compile(r"^- \[ \] \[T[1-5]\]\s+(.+?)\s+—\s")


def item_target(line):
    """The TARGET path of an item: the text between the tier tag and the first ' - ' (em dash). Never a VERIFY path. None when the line has no such shape."""
    m = _TARGET_RE.match(line)
    return m.group(1).strip().strip("`") if m else None


def load_banned(repo_root):
    """Compiled patterns of <repo_root>/.queue-hard-banned-files (run_overnight.sh semantics: one unanchored ERE per line, '#' comments and blanks skipped)."""
    out = []
    try:
        with open(os.path.join(repo_root, ".queue-hard-banned-files"), encoding="utf-8", errors="replace") as f:
            for raw in f:
                p = raw.strip()
                if not p or p.startswith("#"):
                    continue
                try:
                    out.append(re.compile(p))
                except re.error:
                    pass
    except OSError:
        pass
    return out


def is_banned_target(line, patterns):
    t = item_target(line)
    if not t:
        return False
    if t.startswith("addons/"):
        return True
    return any(p.search(t) for p in patterns)


# ---------------------------------------------------------------- A3: vacuous echo idiom
# `<cmd> && echo "FAIL" || echo "PASS"` always exits 0 (the last branch is an echo). Measured: 59 xlite lines, 183 fleet-wide, 15 credited as already-satisfied.
_Q = r"""["']?"""
_VAC_FAILPASS = re.compile(r"^(?P<cmd>.+?)\s+&&\s+echo\s+" + _Q + r"FAIL" + _Q + r"\s+\|\|\s+echo\s+" + _Q + r"PASS" + _Q + r"\s*$")
_VAC_PASSFAIL = re.compile(r"^(?P<cmd>.+?)\s+&&\s+echo\s+" + _Q + r"PASS" + _Q + r"\s+\|\|\s+echo\s+" + _Q + r"FAIL" + _Q + r"\s*$")


def repair_vacuous_cmd(cmd):
    """Return the repaired command or None when `cmd` is not the idiom (or is a shape we leave alone: anything with a pipe or awk)."""
    for rx, neg in ((_VAC_FAILPASS, True), (_VAC_PASSFAIL, False)):
        m = rx.match(cmd.strip())
        if not m:
            continue
        inner = m.group("cmd").strip()
        if "|" in inner or "awk" in inner:
            return None
        return "! ( %s )" % inner if neg else inner
    return None


def is_vacuous_cmd(cmd):
    c = cmd.strip()
    return bool(_VAC_FAILPASS.match(c) or _VAC_PASSFAIL.match(c))


def normalize_vacuous_echo(line):
    """Rewrite the VERIFY of an item line. Returns (line2, n_repaired). Only a backticked VERIFY is rewritten; idempotent (a repaired command no longer matches)."""
    m = re.search(r"VERIFY:\s*`([^`]+)`", line)
    if not m:
        return line, 0
    new = repair_vacuous_cmd(m.group(1))
    if new is None:
        return line, 0
    s, e = m.span(1)
    return line[:s] + new + line[e:], 1


# ---------------------------------------------------------------- intake lint: a VERIFY that can never run (intake package, 2026-10-13; xlite night F4/F5, platform P8)
# The 27B planner / recovery step writes VERIFY clauses that cannot execute, and nothing checked at intake: `cd /path/to/xlite && godot ...` (a prompt placeholder, 27+ FAIL rows in one night),
# `cd tests && godot -s test_x.gd` (a GUT test is not a SceneTree script), `-ginclude=` (not a GUT option: "Unknown arguments"). Each loops the item through ALREADY-DONE refusals until the no-op cap.
# This is the DETECTION side (pure text, no repo); the repairs live in ovn_gut_clause.normalize (R16 / the run-time normaliser) and the lint decides what is left. Returns a short reason or None.
_PLACEHOLDER_PATH = re.compile(r"/path/to(?:/|\b)")
# A placeholder only matters where it is a PATH the command uses (a cd, a file argument). Text that merely MENTIONS it - a quoted grep/echo pattern, the pattern argument of grep/rg/sed/awk -
# is data: `grep -q '/path/to/' README.md` (a docs check) must not be rejected. Quoted strings are blanked, except the target of a `cd`, which is judged first.
_PH_CD = re.compile(r"(?:^|[;&|(]\s*)cd\s+[\"']?/path/to(?:/|\b)")
_QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'")
_PATTERN_FIRST = {"grep", "egrep", "fgrep", "rg", "ag", "sed", "awk", "gawk"}
_SEG_SEP = re.compile(r"[;&|]+")


def placeholder_in_path_position(cmd):
    """True when `/path/to` appears as a path the command uses (see above), not as quoted text or a grep/sed/awk pattern argument."""
    if not cmd or "/path/to" not in cmd:
        return False
    if _PH_CD.search(cmd):
        return True
    for seg in _SEG_SEP.split(_QUOTED.sub(" ", cmd)):
        toks = seg.split()
        if toks and os.path.basename(toks[0]) in _PATTERN_FIRST:
            nxt = [i for i, t in enumerate(toks[1:], 1) if not t.startswith("-")]      # the first non-option argument is the pattern
            if nxt:
                toks[nxt[0]] = ""
        if _PLACEHOLDER_PATH.search(" ".join(toks)):
            return True
    return False
_GODOT_S_TEST = re.compile(r"(?:^|[;&|(]\s*)(?:\S*/)?godot[\w.-]*\b[^;&|`]*?\s(?:-s|--script)(?:=|\s+)[\"']?([^\s\"';&|`]+\.gd)\b")
_GUT_RUNNERS = ("gut_cmdln.gd", "gut_cli.gd")
_TEST_PATH = re.compile(r"(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.[a-z]+$")
_GUT_UNKNOWN_OPT = re.compile(r"(?<!\S)-ginclude=")


def unrunnable_verify_reason(cmd):
    """Why the VERIFY command `cmd` can never run / pass as written, or None. Order = specificity."""
    if not cmd:
        return None
    if placeholder_in_path_position(cmd):
        return "placeholder path /path/to/ (the model copied it from its prompt; the cd / file never exists)"
    for m in _GODOT_S_TEST.finditer(cmd):
        t = m.group(1)
        t = t[len("res://"):] if t.startswith("res://") else t
        if os.path.basename(t) in _GUT_RUNNERS or t.startswith("addons/") or not _TEST_PATH.search(t):
            continue
        return "runs a test file as a script (godot -s %s): a GUT test is not a SceneTree script - use addons/gut/gut_cmdln.gd -gtest=res://<test>.gd" % t
    if "gut_cmdln" in cmd and _GUT_UNKNOWN_OPT.search(cmd):
        return "-ginclude is not a GUT option (GUT exits 1 'Unknown arguments')"
    return None


def verify_lint_lines(text):
    """[(line_no_1based, reason)] for every open item of `text` whose VERIFY can never run (extract_verify reads backticked and bare clauses)."""
    out = []
    for n, l in enumerate(text.split("\n"), 1):
        if not is_open_item(l):
            continue
        why = unrunnable_verify_reason(extract_verify(l) or "")
        if why:
            out.append((n, why))
    return out


# ---------------------------------------------------------------- the pullable set
def pullable(backlog_text, progress_text, done_text="", banned=None):
    """Open, un-parked backlog lines that are not already queued / done (same normalisation as queue_refill) and, when `banned` is given, not a banned target."""
    existing = {norm_line(l) for l in (progress_text + "\n" + done_text).split("\n") if l.lstrip().startswith("- [")}
    out = []
    for l in backlog_text.split("\n"):
        if not is_open_item(l) or is_parked(l) or norm_line(l) in existing:
            continue
        if banned is not None and is_banned_target(l, banned):
            continue
        out.append(l)
    return out


def _read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def main(argv):
    if len(argv) == 4 and argv[1] == "count":
        repo, backlog = argv[2], argv[3]
        banned = None if os.environ.get("OVN_INGEST_BAN_FILTER", "on") == "off" else load_banned(repo)
        print(len(pullable(_read(backlog), _read(os.path.join(repo, "OVERNIGHT_PROGRESS.md")), _read(os.path.join(repo, "OVERNIGHT_DONE.md")), banned)))
        return 0
    if len(argv) in (2, 3) and argv[1] == "sites":
        root = argv[2] if len(argv) == 3 else sites_root()
        sites = unconverted_blocked_sites(root)
        for rel, n, text in sites:
            print("%s:%d: %s" % (rel, n, text))
        print("%d site(s) still match BLOCKED case-insensitively under %s" % (len(sites), root))
        return 1 if sites else 0
    if len(argv) == 2 and argv[1] == "verify-lint":
        # stdin item lines -> "<line>\t<reason>" per open item whose VERIFY can never run (ovn_recover_parked.sh: a decomposed child must not inherit such a clause)
        for n, why in verify_lint_lines(sys.stdin.read()):
            print("%d\t%s" % (n, why))
        return 0
    sys.stderr.write("usage: ovn_backlog_eligibility.py count <repo_dir> <backlog_file> | sites [root] | verify-lint (stdin)\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
