#!/usr/bin/env python3
"""ovn_pingpong_guard.py - LITERAL ping-pong guard for the overnight fleet (2026-11-01, package K3).

Problem (live 2026-10-31, gitlark): three fleet commits flipped ONE status literal on ONE line of backend/app/routers/workspaces.py
(10c57462 adds status_code=201, ffc43510 -> 200, 9e8b5919 -> 201): the route's test and its source disagreed about the right value and each
cycle "fixed" whichever side was red. ovn_churn_guard.py needs >= 8 commits in 3h (or 4 in 1h) on a FILE; a literal flipped three times in a day
never reaches that, and the loop burned ~34 BLOCKED cycles before anyone looked.

Rule: in the last OVN_PINGPONG_WINDOW_H hours (default 24) of origin/overnight/feature (fleet commits only: bookkeeping subjects/files and
interactive 'Co-Authored-By: Claude' commits are ignored) a LINE FAMILY is flipping when
  - the line, with every literal masked (numbers, quoted strings, true/false/None/null), is the same text (the "key"; a one-line edit that
    only changes literals keeps the key; an edit that adds the literal, like `, status_code=201`, makes the new line the key's first state),
  - >= OVN_PINGPONG_MIN (default 3) commits set that key to a literal tuple different from its previous state, and
  - at least one of those states is a REVISIT of an earlier one (A -> B -> A). Forward-only edits (1 -> 2 -> 3) are progress, never a ping-pong.

Action, mode OVN_PINGPONG_MODE (default 'shadow'):
  shadow   log-only: state/pingpong_shadow.log (once per repo+line family+day) + ONE alerts.log 'info' line; nothing is written to any branch.
  enforce  in a temporary detached worktree of origin/overnight/feature (never the live checkout), exactly like ovn_churn_guard.py:
             1. every OPEN eligible queue line whose HEAD names the file (or a same-stem test/source counterpart) gets
                '[AUTO-SKIP pingpong: <file> line literal flipped N times in Hh (201/200/201) - needs Claude; recovery:none] ' after '- [ ] '
                (AUTO-SKIP is every picker's exclusion; 'recovery:' keeps ovn_recover_parked.sh from decomposing + re-queuing it);
                manual-bug / EMERGENCY lines are never parked (the alert says so);
             2. ONE follow-up line (once per line family) is added under the first parked item (or at the end of the file):
                '- [ ] [CLAUDE] [AUTO-SKIP pingpong-followup:<id> needs Claude; recovery:none] <file>: ...' citing the likely failing test(s) and the
                competing commits. The AUTO-SKIP wrapper is what claude_queue_bridge.sh harvests, and the bridge keeps the text AFTER the tag, so the
                citation reaches CLAUDE_QUEUE.md; [CLAUDE] keeps every picker away from it.
             3. commit with the fleet identity, push NON-force with fetch + re-apply + retry (the fleet pushes every minute).
  off      detect nothing (same as OVN_PINGPONG_GUARD=off in the wrapper).
2026-11-02 (P4 / outcomes F9) refinements:
  - ANCHOR (OVN_PINGPONG_ANCHOR=on|off, default on): after a key's first state, a later state only counts when the commit REPLACES the line that carried the previous state (the removed line has the
    same masked key and the literal tuple equals the tracked last state). A commit that merely ADDS another line with the same shape (a new test next to an old one: iptv
    test_notifications_service.py 'First notification' / 'Blocked for A' / 'Allowed for B' + a duplicate re-add) is a different line, not a flip: the live false positive.
  - CONFIG-DEFAULT detector (OVN_PINGPONG_BOOL=off|shadow|enforce, default shadow): a `name: bool = True|False` default replaced by the opposite value flips ON/OFF (the gitlark error_reporting_enabled
    default False -> True contradicted the item's own VERIFY). Needs only OVN_PINGPONG_BOOL_MIN (default 2) anchored states, no revisit. shadow = logged (kind=config-default) and never parked; enforce = parked like a literal ping-pong.
  - LOG DEDUPE: the shadow row / per-run PING-PONG line is written once per (repo, line family, COMMIT SET) instead of once per run or per day.
Safety: DRY_RUN=1 prints only; ANY infrastructure failure logs a line, changes nothing and exits 0; at most OVN_PINGPONG_MAX_PARK (10) lines per run.

  ovn_pingpong_guard.py               one pass over OVN_PINGPONG_REPOS (default 'gitlark billwatch iptv_apps test-automation-agent xlite shrike-notify shrike-monitor')
  ovn_pingpong_guard.py --replay FILE read-only: detect on a saved `git log -p -U0 --format=@@%H|%ct|%s` dump (calibration / fixtures)
Env: OVN_DIR OVN_REPOS_DIR OVN_STATE_DIR OVN_CHURN_REMOTE OVN_CHURN_BRANCH (shared with ovn_churn_guard.py), OVN_PINGPONG_{MODE,REPOS,WINDOW_H,MIN,MAX_PARK,MAX_FILES,PUSH_TRIES}
"""
import collections
import hashlib
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ovn_churn_guard as cg  # noqa: E402  (git(), alert(), names_file(), worktree helpers, fleet identity: one implementation of each)

envi = cg.envi
MODE = os.environ.get("OVN_PINGPONG_MODE", "shadow").strip().lower()      # shadow | enforce | off
WINDOW_H = envi("OVN_PINGPONG_WINDOW_H", 24)
MIN_N = envi("OVN_PINGPONG_MIN", 3)
MAX_PARK = envi("OVN_PINGPONG_MAX_PARK", 10)
MAX_FILES = envi("OVN_PINGPONG_MAX_FILES", 25)
PUSH_TRIES = envi("OVN_PINGPONG_PUSH_TRIES", 5)
ANCHOR = os.environ.get("OVN_PINGPONG_ANCHOR", "on").strip().lower() != "off"
BOOL_MODE = os.environ.get("OVN_PINGPONG_BOOL", "shadow").strip().lower()   # off | shadow | enforce
BOOL_MIN = envi("OVN_PINGPONG_BOOL_MIN", 2)
BOOL_DEFAULT = re.compile(r"^\s*[A-Za-z_]\w*\s*:\s*bool\s*=\s*(?:True|False)\b")
DRY = cg.DRY
STATE = cg.STATE

LITERAL = re.compile(r"""("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(?<![\w.])(-?\d+(?:\.\d+)?)(?![\w.])|\b(True|False|true|false|None|null)\b""")
TAG_PREFIX = "[AUTO-SKIP pingpong: "
FOLLOW_PREFIX = "- [ ] [CLAUDE] [AUTO-SKIP pingpong-followup:"


def log(msg):
    print("%s [pingpong-guard] %s" % (time.strftime("%F %T"), msg), flush=True)


# ---------------------------------------------------------------------------------------------------------------- parsing
def parse_patches(text):
    """`git log -p -U0 --no-color --format=@@%H|%ct|%s` -> [{'sha','t','s','hunks': [(path, [removed lines], [added lines])]}]."""
    out, cur, path, hunk = [], None, None, None
    for line in text.split("\n"):
        if line.startswith("@@") and "|" in line and not line.startswith("@@ "):
            parts = line[2:].split("|", 2)
            try:
                cur = {"sha": parts[0], "t": int(parts[1]), "s": parts[2] if len(parts) > 2 else "", "hunks": [], "ctx": []}
            except (ValueError, IndexError):
                cur = None
            else:
                out.append(cur)
            path = hunk = None
            continue
        if cur is None:
            continue
        if line.startswith("diff --git "):
            path = hunk = None
        elif line.startswith("+++ "):
            p = line[4:].strip()
            path = p[2:] if p.startswith("b/") else None   # /dev/null (deleted file): nothing to track
        elif line.startswith("--- "):
            continue
        elif line.startswith("@@ ") and path:
            hunk = (path, [], [])
            cur["hunks"].append(hunk)
            # git's hunk-header function context ("@@ -a +b @@ <nearest preceding top-level line>"): keeps two different tests/functions in
            # one file whose masked lines look identical (assert x == §) from collapsing into ONE key (K3 review fix)
            _hh = line.split("@@", 2)
            cur["ctx"].append(" ".join(_hh[2].split())[:80] if len(_hh) > 2 else "")
        elif hunk is not None and line.startswith("-"):
            hunk[1].append(line[1:])
        elif hunk is not None and line.startswith("+"):
            hunk[2].append(line[1:])
    return out


def mask(line):
    """-> (key, literal tuple) with every literal replaced by a placeholder; key is whitespace-normalised. (None, ()) when the line has no literal."""
    lits = []

    def sub(m):
        lits.append(m.group(0))
        return "§"
    key = " ".join(LITERAL.sub(sub, line).split())
    return (key, tuple(lits)) if lits and len(key) >= 8 else (None, ())


# ---------------------------------------------------------------------------------------------------------------- detection
def detect(commits, now, window_h=None, min_n=None):
    """Pure function over parsed commits -> findings [{'file','key','line','states','commits','n','revisits','fid'}], most commits first."""
    window_h = WINDOW_H if window_h is None else window_h
    min_n = MIN_N if min_n is None else min_n
    lo = now - window_h * 3600
    win = sorted((c for c in commits if lo <= c["t"] <= now and not cg.BOOKKEEP_SUBJECT.match(c["s"])), key=lambda c: c["t"])
    state = {}      # (path, key, hunk ctx) -> {'last': tuple|None, 'seed': tuple|None, 'events': [(commit, tuple)], 'line': str}
    for c in win:
        paths = {h[0] for h in c["hunks"]}
        if not paths or len(paths) > MAX_FILES:
            continue
        for hi, (path, rem, add) in enumerate(c["hunks"]):
            if cg.BOOKKEEP_FILE.search(path):
                continue
            ctx = c["ctx"][hi] if hi < len(c.get("ctx", [])) else ""
            paired = len(rem) == len(add)
            for i, new in enumerate(add):
                nk, nv = mask(new)
                if nk is None:
                    continue
                st = state.setdefault((path, nk, ctx), {"last": None, "seed": None, "events": [], "line": new.strip()})
                if paired:   # the replaced line already had this shape: its literals are the state BEFORE this commit (seed; not an event)
                    ok_, ov = mask(rem[i])
                    if ok_ == nk and st["last"] is None:
                        st["last"] = st["seed"] = ov
                if nv == st["last"]:
                    continue   # same state as before (e.g. a whitespace-only touch): not a flip
                if ANCHOR and st["last"] is not None:
                    # a later state must REPLACE the line that held the previous state; a second line of the same shape elsewhere is not a flip of it
                    rk, rv = mask(rem[i]) if (paired and i < len(rem)) else (None, ())
                    if rk != nk or rv != st["last"]:
                        continue
                st["events"].append((c, nv))
                st["last"] = nv
                st["line"] = new.strip()
    found = []
    for (path, key, ctx), st in state.items():
        ev = st["events"]
        # distinct commits only (one commit touching the same family on two lines counts once)
        shas = []
        for c, _ in ev:
            if c["sha"] not in shas:
                shas.append(c["sha"])
        n = len(shas)
        seq = [v for _, v in ev]
        kind = "literal"
        is_bool = BOOL_MODE != "off" and bool(BOOL_DEFAULT.match(st["line"]))
        if is_bool and n >= BOOL_MIN and len({v for v in seq} | ({st["seed"]} if st["seed"] is not None else set())) >= 2 and n < min_n:
            kind = "config-default"
        elif n < min_n:
            continue
        walk = {st["seed"]} if st["seed"] is not None else set()   # the pre-window state counts: a flip BACK to it is a revisit
        revisits = 0
        for v in seq:
            if v in walk:
                revisits += 1
            walk.add(v)
        if kind == "literal" and revisits < 1:
            if is_bool and n >= BOOL_MIN and len(walk) >= 2:
                kind = "config-default"   # >= min_n forward-only flips of a bool default: still a config flip
            else:
                continue
        bysha = collections.OrderedDict((c["sha"], c) for c, _ in ev)
        found.append({
            "file": path, "key": key, "line": st["line"][:160], "n": n, "revisits": revisits, "kind": kind,
            "states": [" ".join(v) if len(v) <= 3 else " ".join(v[:3]) + " ..." for v in seq],
            "values": ["/".join(x for x in v if re.match(r"^-?\d+(\.\d+)?$|^(True|False|true|false|None|null)$", x)) or " ".join(v)[:30] for v in seq],
            "commits": [(c["sha"][:8], c["s"][:80]) for c in bysha.values()],
            "fid": hashlib.sha1(("%s|%s|%s" % (path, key, ctx)).encode("utf-8", "replace")).hexdigest()[:8],
        })
    return sorted(found, key=lambda f: (-f["n"], f["file"]))


# ---------------------------------------------------------------------------------------------------------------- tests lookup
def find_tests(clone, finding, limit=3):
    """Best-effort 'which test is failing for this line': tracked TEST files on the branch tip that share a distinctive word with the line's string
    literals AND contain one of the flipped literal values. Returns [path, ...] (may be empty)."""
    words = set()
    for m in re.finditer(r"\"([^\"]*)\"|'([^']*)'", finding["line"]):
        for w in re.findall(r"[A-Za-z_]{6,}", re.sub(r"\{[^}]*\}", " ", m.group(1) or m.group(2) or "")):
            words.add(w.lower())
    words |= {w.lower() for w in re.findall(r"[A-Za-z_]{6,}", os.path.splitext(os.path.basename(finding["file"]))[0])}
    vals = {x for v in finding["values"] for x in v.split("/") if x}
    if not words or not vals:
        return []
    rc, out, _ = cg.git(["ls-tree", "-r", "--name-only", cg.REF], cwd=clone, timeout=60)
    if rc != 0:
        return []
    scored = []
    for p in out.split("\n"):
        if not p or not cg.is_test_path(p) or cg.BOOKKEEP_FILE.search(p):
            continue
        rc2, body, _ = cg.git(["show", "%s:%s" % (cg.REF, p)], cwd=clone, timeout=30)
        if rc2 != 0 or len(body) > 400000:
            continue
        low = body.lower()
        hit = sum(1 for w in words if w in low)
        if hit and any(re.search(r"(?<![\w.])%s(?![\w.])" % re.escape(v), body) for v in vals):
            scored.append((-hit, p))
    return [p for _, p in sorted(scored)[:limit]]


# ---------------------------------------------------------------------------------------------------------------- queue edits
def sanitize(s):
    return re.sub(r"[\]\[\r\n]", "_", s)


def tag_text(f):
    return "%s%s line literal flipped %d times in %dh (%s) - needs Claude; recovery:none] " % (TAG_PREFIX, sanitize(f["file"]), f["n"], WINDOW_H, sanitize("/".join(f["values"])[:60]))


def follow_text(f):
    tests = f.get("tests") or []
    t = ("likely failing test(s): %s" % ", ".join(tests)) if tests else "failing test not identified (run the repo's tests that cover this file)"
    commits = "; ".join("%s %s" % (s, sanitize(subj)) for s, subj in f["commits"][:6])
    return ("%s%s needs Claude; recovery:none] %s: the literal on `%s` was flipped %d times in %dh by fleet commits (%s). %s. Competing commits: %s. "
            "The test and the source disagree about the right value - decide it from the product contract, fix both together, and record it in AGENTS.md if it is a contract." % (
                FOLLOW_PREFIX, f["fid"], sanitize(f["file"]), sanitize(f["line"][:100]).replace("`", "'"), f["n"], WINDOW_H, sanitize("/".join(f["values"])[:60]), t, sanitize(commits)))
    # note: the [CLAUDE] marker sits BEFORE the AUTO-SKIP wrapper so the line is ineligible for every picker either way


def plan(text, findings, ambiguous, budget):
    """-> (new_text, parked Counter {file: n}, protected [(file, line)], followups [fid]). Only inserts tags after '- [ ] ' and adds follow-up lines."""
    lines = text.split("\n")
    parked = collections.Counter()
    protected, follow, first_idx = [], [], {}
    for idx, ln, kind in cg.classify_lines(text):
        for f in findings:
            ch = {"file": f["file"], "aliases": f.get("aliases", [])}
            if cg.names_churner(ln, ch, ambiguous):
                if kind == "protected":
                    protected.append((f["file"], ln))
                elif sum(parked.values()) < budget:
                    lines[idx] = "- [ ] " + tag_text(f) + ln[len("- [ ] "):]
                    parked[f["file"]] += 1
                    first_idx.setdefault(f["fid"], idx)
                break
    inserts = []   # (position, text) applied bottom-up so indexes stay valid
    for f in findings:
        if ("pingpong-followup:%s" % f["fid"]) in text:
            continue
        follow.append(f["fid"])
        inserts.append((first_idx[f["fid"]] + 1 if f["fid"] in first_idx else len(lines), follow_text(f)))
    for pos, t in sorted(inserts, key=lambda x: -x[0]):
        if pos >= len(lines):
            if lines and lines[-1] == "":
                lines.insert(len(lines) - 1, t)
            else:
                lines.append(t)
        else:
            lines.insert(pos, t)
    return "\n".join(lines), parked, protected, follow


def only_expected_edits(old, new, n_tags, n_follow):
    """Paranoid post-check: new == old with exactly n_tags tag insertions (after '- [ ] ') and exactly n_follow added follow-up lines."""
    a, b = old.split("\n"), new.split("\n")
    added = [y for y in b if y.startswith(FOLLOW_PREFIX)]
    if len(added) != n_follow or len(b) != len(a) + n_follow:
        return False
    rest = [y for y in b if not y.startswith(FOLLOW_PREFIX)] if n_follow else b
    if len(rest) != len(a):
        return False
    diff = [(x, y) for x, y in zip(a, rest) if x != y]
    return len(diff) == n_tags and all(x.startswith("- [ ] ") and y.startswith("- [ ] " + TAG_PREFIX) and y.endswith(x[len("- [ ] "):]) for x, y in diff)


def apply_and_push(repo, clone, findings, budget, ambiguous):
    """-> (ok, parked Counter, n_follow). Edit in a temp worktree of origin/<branch>; push NON-force; re-apply on a fresh tip after a rejected push."""
    wt = None
    try:
        wt = tempfile.mkdtemp(prefix="wt-pingpong-%s." % repo, dir="/tmp")
        os.rmdir(wt)
        rc, _, err = cg.git(["worktree", "add", "--quiet", "--detach", wt, cg.REF], cwd=clone, timeout=120)
        if rc != 0:
            log("%s: infra (worktree add failed: %s)" % (repo, err.strip()[:120]))
            return False, collections.Counter(), 0
        for attempt in range(1, PUSH_TRIES + 1):
            prog = os.path.join(wt, "OVERNIGHT_PROGRESS.md")
            try:
                text = cg.read_bytes_text(prog)
            except OSError:
                log("%s: no OVERNIGHT_PROGRESS.md on %s - nothing to do" % (repo, cg.REF))
                return True, collections.Counter(), 0
            new, parked, _prot, follow = plan(text, findings, ambiguous, budget)
            if not parked and not follow:
                return True, parked, 0
            if new == text or not only_expected_edits(text, new, sum(parked.values()), len(follow)):
                log("%s: infra (post-check failed: edit is not exactly %d tag(s) + %d follow-up(s)) - nothing pushed" % (repo, sum(parked.values()), len(follow)))
                return False, collections.Counter(), 0
            cg.write_bytes_text(prog, new)
            first = findings[0]
            msg = "chore(queue): park %d item(s) + 1 Claude follow-up for a literal ping-pong on %s - pingpong guard (%dh window)\n\n%s\n" % (
                sum(parked.values()), first["file"], WINDOW_H,
                "\n".join("- %s: literal flipped %d times (%s); commits %s" % (f["file"], f["n"], "/".join(f["values"])[:60], ", ".join(s for s, _ in f["commits"])) for f in findings))
            rc, _, err = cg.git(["add", "--", "OVERNIGHT_PROGRESS.md"], cwd=wt)
            rc2, _, err2 = cg.git(cg.FLEET_ID + ["-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", msg], cwd=wt, env=cg.FLEET_ENV)
            if rc or rc2:
                log("%s: infra (commit failed: %s)" % (repo, (err + err2).strip()[:120]))
                return False, collections.Counter(), 0
            rc3, names, _ = cg.git(["diff", "--name-only", "HEAD~1", "HEAD"], cwd=wt)
            if rc3 or names.strip() != "OVERNIGHT_PROGRESS.md":
                log("%s: infra (commit touches %r) - nothing pushed" % (repo, names.strip()[:80]))
                return False, collections.Counter(), 0
            rc, _, err = cg.git(["push", "-q", "--no-verify", cg.REMOTE, "HEAD:refs/heads/%s" % cg.BRANCH], cwd=wt, timeout=90)
            if rc == 0:
                return True, parked, len(follow)
            log("%s: push attempt %d/%d rejected (%s)" % (repo, attempt, PUSH_TRIES, err.strip().replace("\n", " ")[:100]))
            time.sleep(min(2 * attempt, 6))
            rc, _, err = cg.git(["fetch", "-q", cg.REMOTE, cg.BRANCH], cwd=wt, timeout=90)
            if rc != 0:
                return False, collections.Counter(), 0
            cg.git(["reset", "-q", "--hard", cg.REF], cwd=wt)
        return False, collections.Counter(), 0
    except Exception as e:  # never propagate
        log("%s: infra (%s: %s)" % (repo, type(e).__name__, e))
        return False, collections.Counter(), 0
    finally:
        cg.cleanup_worktree(clone, wt)


# ---------------------------------------------------------------------------------------------------------------- driver
def once(key):
    """True the first time `key` is seen (persisted in state/pingpong_seen.txt)."""
    fp = os.path.join(STATE, "pingpong_seen.txt")
    try:
        with open(fp) as f:
            if key in {l.rstrip("\n") for l in f}:
                return False
    except OSError:
        pass
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(fp, "a") as f:
            f.write(key + "\n")
    except OSError:
        pass
    return True


def commit_set(f):
    """Stable id of the commits behind a finding: a re-detection of the SAME commits is not new information (2026-11-02, F9: the same iptv family was reported every run)."""
    return hashlib.sha1(",".join(sorted(s for s, _ in f["commits"])).encode()).hexdigest()[:10]


def shadow_log(repo, f, would_park, today):
    if not once("SHADOW|%s|%s|%s" % (repo, f["fid"], commit_set(f))):
        return
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(os.path.join(STATE, "pingpong_shadow.log"), "a") as fh:
            fh.write("%s %s %s %s-pingpong n=%d revisits=%d values=%s would-park=%d tests=%s commits=%s line=%s\n" % (
                time.strftime("%F %T"), repo, f["file"], "config-default" if f.get("kind") == "config-default" else "literal", f["n"], f["revisits"], "/".join(f["values"])[:60], would_park,
                ",".join(f.get("tests") or []) or "-", ",".join(s for s, _ in f["commits"]), f["line"][:100]))
    except OSError as e:
        log("could not write shadow log (%s)" % e)
    cg.alert("info", "pingpong-guard:%s" % repo, "SHADOW %s: line literal flipped %d times in %dh (%s) by fleet commits %s - would park %d queue item(s) + add a Claude follow-up (OVN_PINGPONG_MODE=enforce)" % (
        f["file"], f["n"], WINDOW_H, "/".join(f["values"])[:40], ",".join(s for s, _ in f["commits"][:4]), would_park), "PPS|%s|%s|%s" % (repo, f["fid"], commit_set(f)))


def one_repo(repo, now, state):
    clone = os.path.join(cg.REPOS, repo)
    if not (os.path.isdir(os.path.join(clone, ".git")) or os.path.isfile(os.path.join(clone, ".git"))):
        log("%s: infra (no clone at %s) - skipped" % (repo, clone))
        return
    if not cg.fetch(clone):
        return
    rc, out, err = cg.git(["log", cg.REF, "--since=%d seconds ago" % int(WINDOW_H * 3600 + 600), "--no-merges", "-p", "-U0", "--no-color", "--no-ext-diff",
                           "--regexp-ignore-case", "--invert-grep", "--grep=Co-Authored-By: Claude", "--format=@@%H|%ct|%s"], cwd=clone, timeout=180)
    if rc != 0:
        log("%s: infra (git log failed: %s) - skipped" % (repo, err.strip()[:120]))
        return
    findings = detect(parse_patches(out), now)
    if not findings:
        if once("NONE|%s|%s" % (repo, time.strftime("%Y-%m-%d"))):   # S3-guards2: once per repo per day, not every 20-minute pass
            log("%s: no literal ping-pong (window %dh, min %d commits)" % (repo, WINDOW_H, MIN_N))
        return
    today = time.strftime("%Y-%m-%d")
    ambiguous = cg.add_tree_aliases(clone, findings)   # fills f['aliases'] with same-stem test/source counterparts
    quiet = 0
    for f in findings:
        f["tests"] = find_tests(clone, f)
        if once("LOG|%s|%s|%s" % (repo, f["fid"], commit_set(f))):
            log("%s: PING-PONG[%s] %s n=%d revisits=%d values=%s commits=%s" % (repo, f.get("kind", "literal"), f["file"], f["n"], f["revisits"], "/".join(f["values"])[:40], ",".join(s for s, _ in f["commits"])))
        else:
            quiet += 1
    if quiet and once("UNCH|%s|%d|%s" % (repo, quiet, "-".join(sorted(commit_set(f) for f in findings)))):   # S3-guards2: this line repeated ~5x per 20 min with identical content; log it once per distinct state
        log("%s: %d known ping-pong finding(s) unchanged (same commit set already logged)" % (repo, quiet))
    rc, text, _ = cg.git(["show", "%s:OVERNIGHT_PROGRESS.md" % cg.REF], cwd=clone)
    if rc != 0:
        log("%s: infra (cannot read OVERNIGHT_PROGRESS.md on %s)" % (repo, cg.REF))
        return
    budget = max(0, MAX_PARK - state["parked"])
    # config-default findings are shadow-only (logged, never parked) unless OVN_PINGPONG_BOOL=enforce
    actionable = [f for f in findings if f.get("kind") != "config-default" or BOOL_MODE == "enforce"]
    _, would, protected, would_follow = plan(text, actionable, ambiguous, budget)
    if DRY or MODE != "enforce":
        for f in findings:
            log("%s: %s would park %d item(s) for %s%s" % (repo, "DRY_RUN" if DRY else "SHADOW", would.get(f["file"], 0), f["file"],
                                                         " + add follow-up %s" % f["fid"] if f["fid"] in would_follow else ""))
            if not DRY:
                shadow_log(repo, f, would.get(f["file"], 0), today)
        for fl, ln in protected:
            log("%s: protected (bug/EMERGENCY, never parked) names %s: %s" % (repo, fl, ln[:100]))
        return
    if not would and not would_follow:
        log("%s: nothing left to park (already parked / follow-up present)" % repo)
        return
    ok, parked, n_follow = apply_and_push(repo, clone, actionable, budget, ambiguous)
    if not ok:
        cg.alert("warn", "pingpong-guard:%s" % repo, "could not push the literal ping-pong park to %s (will retry next tick); flipping: %s" % (
            cg.BRANCH, ", ".join(f["file"] for f in findings[:3])), "PPF|%s|%s" % (repo, today))
        return
    state["parked"] += sum(parked.values())
    log("%s: parked %d item(s), %d follow-up(s)" % (repo, sum(parked.values()), n_follow))
    for f in findings:
        k = parked.get(f["file"], 0)
        msg = "%s: line literal flipped %d times in %dh (%s) - parked %d queue item(s) + Claude follow-up %s" % (f["file"], f["n"], WINDOW_H, "/".join(f["values"])[:40], k, f["fid"])
        if k == 0:
            msg += " (no open queue item names it: the loop may come from the backlog/roadmap - a human/Claude should look)"
        if any(fl == f["file"] for fl, _ in protected):
            msg += "; manual-bug/EMERGENCY item(s) name it and were left active"
        cg.alert("warn", "pingpong-guard:%s" % repo, msg, "PP|%s|%s|%s" % (repo, f["fid"], today))


def main():
    if MODE == "off" or os.environ.get("OVN_PINGPONG_GUARD", "on") == "off":
        log("disabled")
        return 0
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    if len(sys.argv) >= 3 and sys.argv[1] == "--replay":
        with open(sys.argv[2], encoding="utf-8", errors="replace") as fh:
            commits = parse_patches(fh.read())
        for f in detect(commits, max([c["t"] for c in commits] or [0]) + 1, window_h=10 ** 6):
            print("n=%d revisits=%d %s values=%s commits=%s line=%s" % (f["n"], f["revisits"], f["file"], "/".join(f["values"]), ",".join(s for s, _ in f["commits"]), f["line"]))
        return 0
    now = int(time.time())
    state = {"parked": 0}
    for repo in os.environ.get("OVN_PINGPONG_REPOS", "gitlark billwatch iptv_apps test-automation-agent xlite shrike-notify shrike-monitor").split():
        try:
            one_repo(repo, now, state)
        except Exception as e:
            log("%s: infra (%s: %s) - no change" % (repo, type(e).__name__, e))
    return 0


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        pass
    except Exception as e:
        log("infra (%s: %s)" % (type(e).__name__, e))
    sys.exit(0)
