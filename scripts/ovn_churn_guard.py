#!/usr/bin/env python3
"""ovn_churn_guard.py - automatic CHURN-LOOP guard for the overnight fleet (2026-10-07).

Problem (live 2026-10-07): the 27B fleet ping-ponged on one file for 115 commits in 3h (tests/test_enemy_faction_map.gd:
'fix: revert get_faction argument to int' <-> 'test: update default faction test to use string input'), every commit green so no
gate objected, all driven by ONE nonsensical open queue item. Earlier: 214 commits on damage_preview.gd, 12 on track_engagement.
The QA rule F_REVERT_OF_RECENT only wrote an alerts.log warn; nothing PARKED the item. This guard does.

Per repo in OVN_CHURN_REPOS (default 'iptv_apps xlite'):
  1. fetch origin/overnight/feature in the repo's live clone (FETCH ONLY - the checkout is never touched), read `git log --raw` of the
     last OVN_CHURN_WINDOW_H hours (default 3), drop bookkeeping (chore(/chore:/docs(queue subjects; queue/backlog/roadmap/*.md/state files;
     commits touching > OVN_CHURN_MAX_FILES files).
  2. a FILE is CHURNING when, in the window, it was touched by n >= OVN_CHURN_MIN (default 8) commits AND it OSCILLATES:
        R >= 3   content revisits: the blob a commit leaves behind is byte-identical to a state the file already had earlier in the
                 window (the file went A -> B -> A). This is the one signal a legit staged feature never produces.
        AND (V >= 2   subjects with revert/restore/undo/rollback wording,
             OR  D*3 >= n   >= one third of the commits repeat an earlier subject (token-Jaccard >= 0.6)).
     A legit staged feature (one file, one new step per commit, distinct subjects, content only ever moves forward) has R == 0 and is
     never flagged however many steps it has.
     A test<->source PAIR (same stem, one is a test) is churning when both were touched >= OVN_CHURN_PAIR_MIN (6) times, the commits
     touching either alternate test/source/test/source for >= 6 flips, and the pair's pooled R/V/D pass the same oscillation test.
  3. every OPEN queue line ('- [ ] ' not already HUMAN-ONLY/AUTO-SKIP/HARD FILE BAN/BLOCKED/(retired-/[CLAUDE] - exactly the picker's
     exclusion set) whose text names the file's repo-relative path or basename is PARKED by inserting
     '[AUTO-SKIP churn-loop: <relpath> touched by <N> fleet commits in <H>h - needs Claude; recovery:none]' after '- [ ] ' (AUTO-SKIP is what every
     selector in run_overnight.sh / lib_item_select.sh filters on; 'recovery:none' inside the bracket keeps ovn_recover_parked.sh from
     decomposing the item and re-queuing the very loop - it excludes any AUTO-SKIP bracket containing 'recovery:').
  4. the edit is made in a TEMPORARY detached worktree of origin/overnight/feature (never in the live checkout), committed with the
     fleet identity and pushed NON-force with fetch + re-apply on the new tip + retry (up to 5 attempts; the fleet pushes every minute).
  2b. (2026-10-09, harness-credit-integrity item 6) TWO MORE triggers, both through the same park path:
        FAST WINDOW  the same oscillation test over a 1h window with OVN_CHURN_PER_HOUR (default 4; 0 = off) commits instead of 8 in 3h: the 3h rule took
                     ~2.7 h to see a loop that was already obvious (xlite remove/restore ping-pong: 12 and 9 landed cycles, 21 pairs).
        REMOVE/RESTORE PAIR  two commits touching the SAME file within OVN_CHURN_PINGPONG_GAP_MIN (30) minutes whose subjects read '(remove|delete|drop) ... X'
                     and '(restore|re-add|revert) ... X' for the same identifier X (either order) park the file's open items immediately - no commit-count
                     threshold. 'remove X' then 'add unrelated Y' never matches. OVN_CHURN_PINGPONG=off disables just this rule.
  5. one deduped alerts.log line per (repo, file, day): 'warn | churn-guard:<repo> | <file> had N fleet commits in Xh - parked K queue item(s)'
     (when no open item matches the alert says so: the loop then comes from the backlog/roadmap and a human/Claude must look).

Review hardening (2026-10-07): matching looks only at the item's HEAD (path before ' - ' / em dash, never its VERIFY clause or prose), bare basenames
only count when no other tracked file shares them, manual-bug / EMERGENCY lines are never parked (alert says so), the file is edited byte-exactly
(CRLF, invalid utf-8, trailing spaces preserved; post-check = only N tag insertions, commit touches only OVERNIGHT_PROGRESS.md), interactive
'Co-Authored-By: Claude' commits are ignored, plain 'chore:' (aider code) commits count, stale /tmp/wt-churnguard-* are swept, and a WATCH pass
(OVN_CHURN_WIDE_H=12h, >=OVN_CHURN_WIDE_MIN=14 commits, >=4 revisits) raises ALERT-ONLY lines for slow loops. OVN_CHURN_PARK=off = alert only, never writes.
queue_refill.py ignores a leading [AUTO-SKIP/HUMAN-ONLY ...] tag when deduping so the roadmap cannot re-pull the original text of a parked item.
Safety: OVN_CHURN_GUARD=off kill switch; DRY_RUN=1 prints what it would park and changes nothing (no push, no alert, no seen-state);
at most OVN_CHURN_MAX_PARK (default 10) lines per run; checked lines and other repos are never touched; ANY infrastructure failure
(fetch/push/git/lock) logs a line, changes nothing and exits 0.

  ovn_churn_guard.py                  one pass
  ovn_churn_guard.py --replay HOURS   read-only calibration: slide the detector over the last HOURS hours and print every file that
                                      WOULD have been flagged (no parking, no alerts)
Env (tests): OVN_CHURN_PER_HOUR OVN_CHURN_PINGPONG OVN_CHURN_PINGPONG_GAP_MIN OVN_DIR OVN_REPOS_DIR OVN_STATE_DIR OVN_CHURN_REPOS OVN_CHURN_WINDOW_H OVN_CHURN_MIN OVN_CHURN_PAIR_MIN OVN_CHURN_MAX_PARK
OVN_CHURN_MAX_FILES OVN_CHURN_REMOTE OVN_CHURN_BRANCH OVN_CHURN_PUSH_TRIES OVN_CHURN_BEFORE_PUSH_HOOK (shell command run before the first push attempt)
"""
import collections
import datetime
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.environ.get("OVN_DIR") or os.path.dirname(HERE)
REPOS = os.environ.get("OVN_REPOS_DIR") or os.path.join(OVN, "repos")
STATE = os.environ.get("OVN_STATE_DIR") or os.path.join(OVN, "state")

BOOKKEEP_SUBJECT = re.compile(r"^(chore\(|docs\(queue)", re.I)
BOOKKEEP_FILE = re.compile(
    r"(^|/)(OVERNIGHT_[A-Z_]+|CLAUDE_QUEUE[A-Z_]*|ROADMAP|AGENTS|README|CHANGELOG)[^/]*$|\.(md|txt|rst|uid|import|lock|log|jsonl?)$|(^|/)(backlog|roadmap|state)/",
    re.I)
REVERT_WORDS = re.compile(r"\b(revert|restore|undo|roll ?back|back to|reinstate)\b", re.I)
INELIGIBLE = re.compile(r"HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|(?-i:BLOCKED)|\(retired-|\[CLAUDE\]", re.I)  # == the pickers' exclusion set
# never parked by this guard (each has its own escalation path; AUTO-SKIP "parks it where nobody looks"): manual-test bugs (lib_bug_escalate.sh) and EMERGENCY lines
PROTECTED = re.compile(r"\[feat:[^\]]*-manual-[0-9a-f]{8}(\.r[0-9]+)?\]|Manual-test bug \(reported by Mark.*src:manual|\[bug-escalated|EMERGENCY", re.I)
RAW_RE = re.compile(r"^:\d+ \d+ ([0-9a-f]+) ([0-9a-f]+) ([A-Z])\d*\t(.+)$")


def envi(name, default):
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


WINDOW_H = envi("OVN_CHURN_WINDOW_H", 3)
MIN_N = envi("OVN_CHURN_MIN", 8)
PAIR_MIN = envi("OVN_CHURN_PAIR_MIN", 6)
MAX_PARK = envi("OVN_CHURN_MAX_PARK", 10)
MAX_FILES = envi("OVN_CHURN_MAX_FILES", 25)
PUSH_TRIES = envi("OVN_CHURN_PUSH_TRIES", 5)
WIDE_H = envi("OVN_CHURN_WIDE_H", 12)      # alert-only WATCH pass (slow loops): window / min commits
WIDE_MIN = envi("OVN_CHURN_WIDE_MIN", 14)
PER_HOUR = envi("OVN_CHURN_PER_HOUR", 4)    # fast pass: this many commits on ONE file within 1h (+ the usual oscillation test); 0 disables
PINGPONG = os.environ.get("OVN_CHURN_PINGPONG", "on") != "off"
PINGPONG_GAP_S = envi("OVN_CHURN_PINGPONG_GAP_MIN", 30) * 60
REMOTE = os.environ.get("OVN_CHURN_REMOTE", "origin")
BRANCH = os.environ.get("OVN_CHURN_BRANCH", "overnight/feature")
REF = "%s/%s" % (REMOTE, BRANCH)
DRY = os.environ.get("DRY_RUN", "") not in ("", "0")
PARK = os.environ.get("OVN_CHURN_PARK", "on") != "off"   # off => detect + alert only, never write to the branch
FLEET_ID = ["-c", "user.name=shrike-fleet", "-c", "user.email=22970726+markhint22@users.noreply.github.com"]
FLEET_ENV = dict(os.environ, GIT_AUTHOR_NAME="shrike-fleet", GIT_COMMITTER_NAME="shrike-fleet",
                 GIT_AUTHOR_EMAIL="22970726+markhint22@users.noreply.github.com", GIT_COMMITTER_EMAIL="22970726+markhint22@users.noreply.github.com")


def log(msg):
    print("%s [churn-guard] %s" % (time.strftime("%F %T"), msg), flush=True)


def git(args, cwd=None, timeout=120, env=None):
    try:
        p = subprocess.run(["git", "-c", "core.quotepath=off"] + args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        return 255, "", str(e)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


# ---------------------------------------------------------------------------------------------------------------- detection
def parse_log(text):
    """-> list of {'sha','t','s','f': {path: (old_blob, new_blob, status)}} for `git log --raw --no-abbrev --format=@@%H|%ct|%s`."""
    out, cur = [], None
    for line in text.split("\n"):
        if line.startswith("@@"):
            parts = line[2:].split("|", 2)
            if len(parts) < 3:
                cur = None
                continue
            try:
                t = int(parts[1])
            except ValueError:
                cur = None
                continue
            cur = {"sha": parts[0], "t": t, "s": parts[2], "f": {}}
            out.append(cur)
        elif cur is not None and line.startswith(":"):
            m = RAW_RE.match(line)
            if m:
                cur["f"][m.group(4).split("\t")[-1]] = (m.group(1), m.group(2), m.group(3))
    return out


def toks(subject):
    s = re.sub(r"^\w+(\([^)]*\))?!?:\s*", "", subject.lower())
    return set(re.findall(r"[a-z_][a-z0-9_]+", s))


def osc_stats(commits, path_set):
    """commits: time-ordered commits touching any of path_set. -> (R, V, D).
    R = commits whose resulting blob of a tracked file equals a state that file already had in the window (A->B->A);
    V = commits whose subject has revert/restore wording; D = commits whose subject repeats an earlier one (Jaccard >= 0.6)."""
    seen = {}
    r = 0
    for c in commits:
        hit = False
        for p in path_set:
            b = c["f"].get(p)
            if not b:
                continue
            st = seen.setdefault(p, set())
            if st and b[1] in st:
                hit = True
            if not st:
                st.add(b[0])
            st.add(b[1])
        r += 1 if hit else 0
    v = sum(1 for c in commits if REVERT_WORDS.search(c["s"]))
    d, prev = 0, []
    for c in commits:
        t = toks(c["s"])
        if any(len(t & u) / float(max(1, len(t | u))) >= 0.6 for u in prev):
            d += 1
        prev.append(t)
    return r, v, d


def oscillates(r, v, d, n, min_r=3, min_v=2):
    return r >= min_r and (v >= min_v or d * 3 >= n)


def is_test_path(p):
    b = os.path.basename(p)
    return bool(re.match(r"(test_|.*_test\.|.*\.test\.|.*\.spec\.)", b)) or bool(re.search(r"(^|/)(tests?|__tests__)/", p))


def stem(p):
    b = os.path.splitext(os.path.basename(p))[0]
    b = re.sub(r"\.(test|spec)$", "", b)
    b = re.sub(r"^test_", "", b)
    b = re.sub(r"_test$", "", b)
    return b


def detect(commits, now, window_h=None, min_n=None, pair_min=None, min_r=3, min_v=2, pairs=True):
    """-> list of dicts {file, n, R, V, D, kind} sorted by n desc. Pure function over parsed commits."""
    window_h = WINDOW_H if window_h is None else window_h
    min_n = MIN_N if min_n is None else min_n
    pair_min = PAIR_MIN if pair_min is None else pair_min
    lo = now - window_h * 3600
    win = sorted((c for c in commits if lo <= c["t"] <= now and not BOOKKEEP_SUBJECT.match(c["s"])), key=lambda c: c["t"])
    byfile = collections.defaultdict(list)
    for c in win:
        files = [p for p in c["f"] if not BOOKKEEP_FILE.search(p)]
        if not files or len(files) > MAX_FILES:
            continue
        for p in files:
            byfile[p].append(c)
    found = {}
    for p, cl in byfile.items():
        n = len(cl)
        if n < min_n:
            continue
        r, v, d = osc_stats(cl, [p])
        if oscillates(r, v, d, n, min_r, min_v):
            found[p] = {"file": p, "n": n, "R": r, "V": v, "D": d, "kind": "file"}
    # test <-> source pairs (fewer touches needed, but they must alternate AND oscillate)
    bystem = collections.defaultdict(list)
    for p in byfile:
        bystem[stem(p)].append(p)
    for st, ps in (bystem.items() if pairs else ()):
        tests = [p for p in ps if is_test_path(p)]
        srcs = [p for p in ps if not is_test_path(p)]
        for t in tests:
            for s in srcs:
                if len(byfile[t]) < pair_min or len(byfile[s]) < pair_min:
                    continue
                union = sorted({c["sha"]: c for c in byfile[t] + byfile[s]}.values(), key=lambda c: c["t"])
                seq = []
                for c in union:
                    has_t, has_s = t in c["f"], s in c["f"]
                    if has_t != has_s:
                        seq.append("T" if has_t else "S")
                flips = sum(1 for a, b in zip(seq, seq[1:]) if a != b)
                if flips < pair_min:
                    continue
                r, v, d = osc_stats(union, [t, s])
                if not oscillates(r, v, d, len(union)):
                    continue
                for p in (t, s):
                    if p not in found:
                        found[p] = {"file": p, "n": len(byfile[p]), "R": r, "V": v, "D": d, "kind": "pair(%s)" % os.path.basename(s if p == t else t)}
    # a churning file also "names" its same-stem counterpart that was touched in the window (the live loop's queue item named the SOURCE
    # file scripts/battle/enemy_faction_map.gd while the ping-pong happened in tests/test_enemy_faction_map.gd)
    for p, ch in found.items():
        ch["aliases"] = sorted(q for q in bystem[stem(p)] if q != p and is_test_path(q) != is_test_path(p))
    return sorted(found.values(), key=lambda x: (-x["n"], x["file"]))


REMOVE_VERB = re.compile(r"\b(remov\w*|delet\w*|drop(?:s|ped|ping)?)\b(.*)$", re.I)
RESTORE_VERB = re.compile(r"\b(restor\w*|re-?add\w*|revert\w*|reinstat\w*|undo|undid|put back)\b(.*)$", re.I)
_PP_STOP = frozenset("""the and for from with that this into onto back out all any not but are was were has have had its it's their there then than
    unused dead code file files test tests case cases function functions method methods class classes import imports line lines call calls check checks
    argument arguments param params parameter parameters value values default defaults type types input inputs output update updated updates fix fixed
    add added adds new old extra test_ assert asserts assertion assertions only also still when after before instead because using use uses used
    original previous previously change changes changed behavior behaviour logic handling helper helpers module removal deletion restoration undo undid
    revert reverted restore restored remove removed delete deleted""".split())


def _pp_idents(text):
    """identifier-like tokens of a commit-subject fragment: snake_case / CamelCase / any word >= 5 chars that is not boilerplate."""
    out = set()
    for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", text):
        tl = t.lower()
        if tl in _PP_STOP:
            continue
        out.add(tl)
    return out


def _pp_side(subject):
    """-> ('remove'|'restore'|None, identifier set) for a commit subject (type prefix 'fix(scope):' stripped; a leading 'revert' is the restore verb itself)."""
    m_rv = re.match(r"^\s*revert\b[:(!]?(.*)$", subject, re.I)
    if m_rv:
        return "restore", _pp_idents(m_rv.group(1))
    s = re.sub(r"^\w+(\([^)]*\))?!?:\s*", "", subject)
    m_rm, m_rs = REMOVE_VERB.search(s), RESTORE_VERB.search(s)
    if m_rs and (not m_rm or m_rs.start() <= m_rm.start()):
        return "restore", _pp_idents(m_rs.group(2))
    if m_rm:
        return "remove", _pp_idents(m_rm.group(2))
    return None, set()


def detect_pingpong(commits, now, window_h=None, gap_s=None):
    """-> churner dicts for files with a REMOVE/RESTORE pair: two commits touching the same (non-bookkeeping) file within gap_s seconds whose subjects read
    'remove|delete|drop ... X' and 'restore|re-add|revert ... X' for the same identifier X (either order). Pure function over parsed commits."""
    window_h = WINDOW_H if window_h is None else window_h
    gap_s = PINGPONG_GAP_S if gap_s is None else gap_s
    lo = now - window_h * 3600
    win = sorted((c for c in commits if lo <= c["t"] <= now and not BOOKKEEP_SUBJECT.match(c["s"])), key=lambda c: c["t"])
    byfile = collections.defaultdict(list)
    for c in win:
        files = [p for p in c["f"] if not BOOKKEEP_FILE.search(p)]
        if not files or len(files) > MAX_FILES:
            continue
        for p in files:
            byfile[p].append(c)
    found = {}
    for p, cl in byfile.items():
        # tokens that merely NAME the file (its basename / stem / directories) are in every subject about it and prove nothing about a shared identifier
        own = {t.lower() for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", p)} | {os.path.splitext(os.path.basename(p))[0].lower(), stem(p).lower()}
        sides = [(c, k, ids - own) for c, k, ids in ((c,) + _pp_side(c["s"]) for c in cl)]
        for i, (c1, k1, ids1) in enumerate(sides):
            if k1 is None or not ids1:
                continue
            for c2, k2, ids2 in sides[i + 1:]:
                if c2["t"] - c1["t"] > gap_s:
                    break
                if k2 is None or k2 == k1 or not ids2:
                    continue
                shared = ids1 & ids2
                if shared:
                    x = sorted(shared)[0]
                    found[p] = {"file": p, "n": len(cl), "R": 0, "V": 2, "D": 0, "kind": "remove/restore(%s)" % x, "win": window_h}
                    break
            if p in found:
                break
    return sorted(found.values(), key=lambda x: (-x["n"], x["file"]))


def merge_churners(*lists):
    """Union by file, first list wins (the established 3h detector keeps its numbers); order = n desc for plan_parking's 'highest-n file wins'."""
    seen = {}
    for lst in lists:
        for c in lst:
            seen.setdefault(c["file"], c)
    return sorted(seen.values(), key=lambda x: (-x["n"], x["file"]))


# ---------------------------------------------------------------------------------------------------------------- queue matching / parking
def open_lines(text):
    """-> list of (index, line) of eligible open queue lines (the pickers' exclusion set + protected bug/EMERGENCY lines)."""
    return [(i, ln) for i, ln, _ in classify_lines(text) if _ == "eligible"]


def classify_lines(text):
    """-> [(index, line, 'eligible'|'protected')] for every open '- [ ] ' line the pickers could still select."""
    out = []
    for i, ln in enumerate(text.split("\n")):
        if ln.startswith("- [ ] ") and not INELIGIBLE.search(ln):
            out.append((i, ln, "protected" if PROTECTED.search(ln) else "eligible"))
    return out


SEP_RE = re.compile(r"\s(?:\u2014|\u2013|--|-)\s")
PATHLIKE = re.compile(r"[\w\-/]+\.[A-Za-z0-9]{1,8}(?![\w])")
TOKEN_RE = re.compile(r"[^\s`'\"\\,;()<>|=]+")


def item_head(line):
    """The part of an open queue line that says WHAT the item edits: text after '- [ ] ' and its leading [tags], cut at ' VERIFY' (a VERIFY clause
    only RUNS files) and, when present, at the first ' - ' / em-dash separator ('<path> - <description>': the description may merely READ other files)."""
    t = line[len("- [ ] "):]
    t = re.sub(r"^(\s*(\[[^\]]*\]|\([^)]*\)))+", "", t).strip()
    m = re.search(r"VERIFY", t)
    if m:
        t = t[:m.start()]
    m = SEP_RE.search(t)
    if m and m.start() <= 240 and PATHLIKE.search(t[:m.start()]):  # no path before the separator => the path comes later: keep the whole pre-VERIFY text
        t = t[:m.start()]
    return t


def names_file(line, relpath, ambiguous=None):
    """True when the item's HEAD names relpath: its full path, a '/'-bounded path suffix ('battle/x.gd'), or - only when no OTHER tracked file shares
    the basename (ambiguous = set of such basenames from the branch tree; None = unknown => treated as ambiguous) - the bare basename."""
    base = os.path.basename(relpath)
    for tok in TOKEN_RE.findall(item_head(line)):
        tok = tok.strip("*").rstrip(".:")
        if tok.startswith("./"):
            tok = tok[2:]
        if not tok:
            continue
        if tok == relpath or (("/" in tok) and relpath.endswith("/" + tok)):
            return True
        if tok == base and ambiguous is not None and base not in ambiguous:
            return True
    return False


def names_churner(line, ch, ambiguous=None):
    return any(names_file(line, p, ambiguous) for p in [ch["file"]] + list(ch.get("aliases", [])))


def tag_text(relpath, n, window_h):
    rel = re.sub(r"[\]\[\r\n]", "_", relpath)  # a ']' in the path would end the AUTO-SKIP bracket early (recover_parked/bridge regexes use [^\]]*)
    return "[AUTO-SKIP churn-loop: %s touched by %d fleet commits in %dh - needs Claude; recovery:none] " % (rel, n, window_h)


def plan_parking(text, churners, window_h, budget, ambiguous=None):
    """-> (new_text, parked Counter {file: count}, protected [(file, line)]). Only matched lines change (the tag is inserted after '- [ ] ');
    one tag per line (highest-n file wins); cap = budget. Line endings / unrelated bytes are preserved (split/join on '\\n' only)."""
    lines = text.split("\n")
    parked = collections.Counter()
    protected = []
    for idx, ln, kind in classify_lines(text):
        for ch in churners:  # sorted by n desc
            if names_churner(ln, ch, ambiguous):
                if kind == "protected":
                    protected.append((ch["file"], ln))
                elif sum(parked.values()) < budget:
                    lines[idx] = "- [ ] " + tag_text(ch["file"], ch["n"], ch.get("win", window_h)) + ln[len("- [ ] "):]
                    parked[ch["file"]] += 1
                break
    return "\n".join(lines), parked, protected


# ---------------------------------------------------------------------------------------------------------------- alerts
def alert(level, who, msg, key):
    """One deduped line per key. Returns True if written."""
    os.makedirs(STATE, exist_ok=True)
    seen_f = os.path.join(STATE, "churn_guard_seen.txt")
    try:
        with open(seen_f) as f:
            if key in {l.rstrip("\n") for l in f}:
                return False
    except OSError:
        pass
    try:
        with open(seen_f, "a") as f:
            f.write(key + "\n")
        with open(os.path.join(STATE, "alerts.log"), "a") as f:
            f.write("[%s] %s | %s | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, who, msg))
    except OSError as e:
        log("could not write alert (%s)" % e)
        return False
    return True


# ---------------------------------------------------------------------------------------------------------------- git side
def fetch(clone):
    rc, _, err = git(["fetch", "-q", REMOTE, BRANCH], cwd=clone, timeout=90)
    if rc != 0:
        log("%s: infra (fetch failed: %s) - skipped" % (os.path.basename(clone), err.strip()[:120]))
        return False
    return True


def read_history(clone, hours_back):
    # --invert-grep: interactive Claude Code sessions (Co-Authored-By: Claude) reach overnight/feature through develop merges; their commits are never the fleet's churn
    rc, out, err = git(["log", REF, "--since=%d seconds ago" % int(hours_back * 3600 + 600), "--no-merges", "--raw", "--no-abbrev",
                        "--regexp-ignore-case", "--invert-grep", "--grep=Co-Authored-By: Claude", "--format=@@%H|%ct|%s"], cwd=clone, timeout=120)
    if rc != 0:
        log("%s: infra (git log failed: %s) - skipped" % (os.path.basename(clone), err.strip()[:120]))
        return None
    return parse_log(out)


def cleanup_worktree(clone, wt):
    if not wt:
        return
    git(["worktree", "remove", "--force", wt], cwd=clone, timeout=60)
    git(["worktree", "prune"], cwd=clone, timeout=60)
    shutil.rmtree(wt, ignore_errors=True)


def sweep_stale_worktrees(repo, clone):
    """A SIGKILL/reboot mid-pass leaves /tmp/wt-churnguard-<repo>.* behind (+ an admin entry in the clone). The wrapper's lock guarantees no live pass
    exists, so anything older than 30 min is stale. Best effort."""
    try:
        for name in os.listdir("/tmp"):
            d = os.path.join("/tmp", name)
            if name.startswith("wt-churnguard-%s." % repo) and os.path.isdir(d) and time.time() - os.path.getmtime(d) > 1800:
                cleanup_worktree(clone, d)
                log("%s: removed stale worktree %s" % (repo, d))
    except OSError:
        pass


def read_bytes_text(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", "surrogateescape")


def write_bytes_text(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("utf-8", "surrogateescape"))


def only_tags_added(old, new, n):
    """Paranoid post-check: same number of lines, exactly n lines differ and each differing line is the old line with the park tag inserted after '- [ ] '."""
    a, b = old.split("\n"), new.split("\n")
    if len(a) != len(b):
        return False
    diff = [(x, y) for x, y in zip(a, b) if x != y]
    return len(diff) == n and all(y.startswith("- [ ] [AUTO-SKIP churn-loop: ") and y.endswith(x[len("- [ ] "):]) and x.startswith("- [ ] ") for x, y in diff)


def apply_and_push(repo, clone, churners, budget, ambiguous):
    """Park matching open lines in a temp worktree of origin/overnight/feature and push NON-force. The edit is re-applied (not rebased) on a fresh tip
    after every rejected push, so a textual conflict cannot exist and no half-merged state is ever pushed. -> (ok, parked Counter); never raises."""
    wt = None
    try:
        wt = tempfile.mkdtemp(prefix="wt-churnguard-%s." % repo, dir="/tmp")
        os.rmdir(wt)  # git worktree add wants to create it
        rc, _, err = git(["worktree", "add", "--quiet", "--detach", wt, REF], cwd=clone, timeout=120)
        if rc != 0:
            log("%s: infra (worktree add failed: %s)" % (repo, err.strip()[:120]))
            return False, collections.Counter()
        hook = os.environ.get("OVN_CHURN_BEFORE_PUSH_HOOK", "")
        for attempt in range(1, PUSH_TRIES + 1):
            prog = os.path.join(wt, "OVERNIGHT_PROGRESS.md")
            try:
                text = read_bytes_text(prog)
            except OSError:
                log("%s: no OVERNIGHT_PROGRESS.md on %s - nothing to park" % (repo, REF))
                return True, collections.Counter()
            new, parked, _prot = plan_parking(text, churners, WINDOW_H, budget, ambiguous)
            if not parked:
                return True, parked  # nothing (left) to park - e.g. someone parked it between ticks
            if new == text or not only_tags_added(text, new, sum(parked.values())):
                log("%s: infra (post-check failed: edit is not exactly %d tag insertion(s)) - nothing pushed" % (repo, sum(parked.values())))
                return False, collections.Counter()
            write_bytes_text(prog, new)
            first = sorted(parked, key=lambda k: -parked[k])[0]
            more = len(parked) - 1
            msg = "chore(queue): park %d item(s) in a churn loop on %s%s - fleet churn-loop guard (%dh window)\n\n%s\n" % (
                sum(parked.values()), first, (" (+%d more file%s)" % (more, "s" if more > 1 else "")) if more else "", WINDOW_H,
                "\n".join("- %s: %d item(s), %d fleet commits in %dh" % (c["file"], parked[c["file"]], c["n"], c.get("win", WINDOW_H))
                          for c in churners if parked[c["file"]]))
            rc, _, err = git(["add", "--", "OVERNIGHT_PROGRESS.md"], cwd=wt)
            rc2, _, err2 = git(FLEET_ID + ["-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", msg], cwd=wt, env=FLEET_ENV)
            if rc or rc2:
                log("%s: infra (commit failed: %s)" % (repo, (err + err2).strip()[:120]))
                return False, collections.Counter()
            # the commit must touch exactly one file, else abort before pushing anything
            rc3, names, _ = git(["diff", "--name-only", "HEAD~1", "HEAD"], cwd=wt)
            if rc3 or names.strip() != "OVERNIGHT_PROGRESS.md":
                log("%s: infra (commit touches %r) - nothing pushed" % (repo, names.strip()[:80]))
                return False, collections.Counter()
            if hook and attempt == 1:
                subprocess.run(hook, shell=True, cwd=clone, timeout=60)
            rc, _, err = git(["push", "-q", "--no-verify", REMOTE, "HEAD:refs/heads/%s" % BRANCH], cwd=wt, timeout=90)
            if rc == 0:
                return True, parked
            log("%s: push attempt %d/%d rejected (%s)" % (repo, attempt, PUSH_TRIES, err.strip().replace("\n", " ")[:100]))
            time.sleep(min(2 * attempt, 6))
            rc, _, err = git(["fetch", "-q", REMOTE, BRANCH], cwd=wt, timeout=90)
            if rc != 0:
                log("%s: infra (refetch failed)" % repo)
                return False, collections.Counter()
            git(["reset", "-q", "--hard", REF], cwd=wt)  # re-apply the edit on the new tip (never a rebase: no conflict state can exist)
        return False, collections.Counter()
    except Exception as e:  # never propagate: infra trouble => no change
        log("%s: infra (%s: %s)" % (repo, type(e).__name__, e))
        return False, collections.Counter()
    finally:
        cleanup_worktree(clone, wt)


def add_tree_aliases(clone, churners):
    """-> set of AMBIGUOUS basenames (more than one tracked file has it; None when the tree could not be read).
    Also adds same-stem counterparts (test <-> source) that exist on the branch tip as aliases, so an item that names only the source file of a churning
    test (or vice versa) is still parked. Best effort: a git failure just leaves the in-window aliases."""
    rc, out, _ = git(["ls-tree", "-r", "--name-only", REF], cwd=clone, timeout=60)
    if rc != 0:
        return None
    stems = {stem(c["file"]) for c in churners}
    bystem = collections.defaultdict(list)
    bases = collections.Counter()
    for p in out.split("\n"):
        if not p:
            continue
        bases[os.path.basename(p)] += 1
        if not BOOKKEEP_FILE.search(p) and stem(p) in stems:
            bystem[stem(p)].append(p)
    for c in churners:
        extra = [q for q in bystem[stem(c["file"])] if q != c["file"] and is_test_path(q) != is_test_path(c["file"])]
        c["aliases"] = sorted(set(c.get("aliases", [])) | set(extra))
    return {b for b, k in bases.items() if k > 1}


def one_repo(repo, now, state):
    clone = os.path.join(REPOS, repo)
    if not (os.path.isdir(os.path.join(clone, ".git")) or os.path.isfile(os.path.join(clone, ".git"))):
        log("%s: infra (no clone at %s) - skipped" % (repo, clone))
        return
    if not DRY:
        sweep_stale_worktrees(repo, clone)
    if not fetch(clone):
        return
    commits = read_history(clone, max(WINDOW_H, WIDE_H))
    if commits is None:
        return
    today = time.strftime("%Y-%m-%d")
    churners = detect(commits, now)
    # 2026-10-09: fast 1h window (PER_HOUR commits) and the remove/restore ping-pong rule feed the same park path (see the module docstring, 2b)
    if PER_HOUR > 0:
        churners = merge_churners(churners, [dict(c, win=1) for c in detect(commits, now, window_h=1, min_n=PER_HOUR, pair_min=PER_HOUR)])
    if PINGPONG:
        churners = merge_churners(churners, detect_pingpong(commits, now))
    # alert-only WATCH pass: slower / longer loops (wide window, higher n, >=4 revisits). Never parks.
    names = {c["file"] for c in churners}
    watch = [] if WIDE_H <= WINDOW_H else [w for w in detect(commits, now, window_h=WIDE_H, min_n=WIDE_MIN, min_r=4, min_v=3, pairs=False) if w["file"] not in names]
    for w in watch:
        log("%s: WATCH %s n=%d R=%d V=%d D=%d in %dh (alert only)" % (repo, w["file"], w["n"], w["R"], w["V"], w["D"], WIDE_H))
        if not DRY:
            alert("warn", "churn-guard:%s" % repo, "WATCH %s: %d fleet commits in %dh with %d content revisits (slow oscillation) - NOT parked (alert only); a human/Claude should look" % (
                w["file"], w["n"], WIDE_H, w["R"]), "%s|WATCH|%s|%s" % (repo, w["file"], today))
    if not churners:
        log("%s: no churning files (window %dh, min %d, %d commits scanned)" % (repo, WINDOW_H, MIN_N, len(commits)))
        return
    ambiguous = add_tree_aliases(clone, churners)
    for c in churners:
        log("%s: CHURNING %s n=%d R=%d V=%d D=%d [%s]%s" % (repo, c["file"], c["n"], c["R"], c["V"], c["D"], c["kind"], (" win=%dh" % c["win"]) if c.get("win") else ""))
    rc, text, _ = git(["show", "%s:OVERNIGHT_PROGRESS.md" % REF], cwd=clone)
    if rc != 0:
        log("%s: infra (cannot read OVERNIGHT_PROGRESS.md on %s)" % (repo, REF))
        return
    budget = max(0, MAX_PARK - state["parked"])
    _, would, protected = plan_parking(text, churners, WINDOW_H, budget, ambiguous)
    if DRY or not PARK:
        tag = "DRY_RUN" if DRY else "PARK=off"
        for c in churners:
            log("%s: %s would park %d item(s) for %s" % (repo, tag, would.get(c["file"], 0), c["file"]))
        for idx, ln in open_lines(text):
            for c in churners:
                if names_churner(ln, c, ambiguous):
                    log("%s: %s would park line: %s" % (repo, tag, ln[:140]))
                    break
        for f, ln in protected:
            log("%s: %s protected (bug/EMERGENCY, never parked) names %s: %s" % (repo, tag, f, ln[:100]))
        if DRY:
            return
    parked = collections.Counter()
    if would and PARK:
        ok, parked = apply_and_push(repo, clone, churners, budget, ambiguous)
        if not ok:
            alert("warn", "churn-guard:%s" % repo, "could not push the churn-loop park to %s after %d attempts (will retry next tick); churning: %s" % (
                BRANCH, PUSH_TRIES, ", ".join(c["file"] for c in churners[:3])), "%s|PUSHFAIL|%s" % (repo, today))
            return
        state["parked"] += sum(parked.values())
        log("%s: parked %d item(s): %s" % (repo, sum(parked.values()), dict(parked)))
    elif PARK and any(names_churner(ln, c, ambiguous) for _, ln in open_lines(text) for c in churners):
        log("%s: matching items exist but the per-run cap (%d) is exhausted - next tick" % (repo, MAX_PARK))
        return
    for c in churners:
        k = parked.get(c["file"], 0)
        nprot = sum(1 for f, _ in protected if f == c["file"])
        if not PARK:
            msg = "%s had %d fleet commits in %dh - ALERT ONLY (OVN_CHURN_PARK=off): %d open queue item(s) would be parked" % (c["file"], c["n"], c.get("win", WINDOW_H), would.get(c["file"], 0))
        else:
            msg = "%s had %d fleet commits in %dh - parked %d queue item(s)" % (c["file"], c["n"], c.get("win", WINDOW_H), k)
            if k == 0:
                msg += " (no open queue item names it: the loop may come from the backlog/roadmap or an already-parked item - a human/Claude should look)"
        if nprot:
            msg += "; %d manual-bug/EMERGENCY item(s) name it and were left active (never auto-parked)" % nprot
        alert("warn", "churn-guard:%s" % repo, msg, "%s|%s|%s" % (repo, c["file"], today))


def replay(hours):
    now = int(time.time())
    for repo in os.environ.get("OVN_CHURN_REPOS", "iptv_apps xlite").split():
        clone = os.path.join(REPOS, repo)
        if not os.path.isdir(clone):
            continue
        commits = read_history(clone, hours + max(WINDOW_H, WIDE_H))
        if commits is None:
            continue
        best = {}
        t = now - hours * 3600
        while t <= now:
            for c in detect(commits, t):
                b = best.get(c["file"])
                if b is None or c["n"] > b["n"]:
                    best[c["file"]] = dict(c, at=t)
            if WIDE_H > WINDOW_H:
                for c in detect(commits, t, window_h=WIDE_H, min_n=WIDE_MIN, min_r=4, min_v=3, pairs=False):
                    if c["file"] not in best:
                        best[c["file"]] = dict(c, at=t, kind="WATCH")
            t += 600
        print("## %s: last %dh, window %dh, min %d: %d commits, %d file(s) flagged" % (repo, hours, WINDOW_H, MIN_N, len(commits), len(best)))
        for c in sorted(best.values(), key=lambda x: -x["n"]):
            print("  n=%-4d R=%-3d V=%-3d D=%-3d %-12s first-peak %s  %s" % (
                c["n"], c["R"], c["V"], c["D"], c["kind"], datetime.datetime.fromtimestamp(c["at"]).strftime("%m-%d %H:%M"), c["file"]))


def main():
    if os.environ.get("OVN_CHURN_GUARD", "on") == "off":
        log("disabled (OVN_CHURN_GUARD=off)")
        return 0
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if len(sys.argv) >= 3 and sys.argv[1] == "--replay":
        replay(int(sys.argv[2]))
        return 0
    now = int(time.time())
    state = {"parked": 0}
    for repo in os.environ.get("OVN_CHURN_REPOS", "iptv_apps xlite").split():
        try:
            one_repo(repo, now, state)
        except Exception as e:
            log("%s: infra (%s: %s) - no change" % (repo, type(e).__name__, e))
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except SystemExit:
        rc = 0
    except Exception as e:
        log("infra (%s: %s)" % (type(e).__name__, e))
        rc = 0
    sys.exit(0)
