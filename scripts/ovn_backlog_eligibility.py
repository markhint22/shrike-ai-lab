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
    sys.stderr.write("usage: ovn_backlog_eligibility.py count <repo_dir> <backlog_file> | sites [root]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
