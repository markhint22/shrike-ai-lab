#!/usr/bin/env python3
"""ovn_hygiene_sigstreak.py - same-failing-tests streak detector for branch_hygiene gates (2026-11-01, package K3 item 4).

Why: ovn_hygiene_stuck_check.sh ages a stuck gate by TIME (alert after 2h) and hygiene_gate_streak alerts at 3/6 consecutive failures, but neither says that the gate is
failing on the SAME tests every pass. That is the signature of a deterministic break (a contract test the fleet cannot satisfy, a frozen-file mismatch: gitlark's
workspace-conversation status test) rather than flakiness or an environment fault, and it needs a human/Claude, not another pass. The streak alert names the first failing
test once in a sentence; nothing named the test SET, the commits that last touched it, or fired separately for a stable signature.

Reads logs/hygiene_gate/<YYYYmmdd-HHMMSS>.<repo>.<kind>.<rand> (branch_hygiene.sh keeps the full gate output of every gate whose output is longer than
OVN_HYGIENE_GATE_HEAD+TAIL lines; a short output is shown in the main log and not kept, so a short GREEN gate leaves no file - the review flag below is the liveness check).
Per (repo, kind), chronologically:
  - the failing test set of a file = pytest 'FAILED|ERROR path::name', '--- GUT-FAIL-ID: path::name', gradle 'Class > test FAILED' (ANSI stripped); an empty set = not a
    test failure (green or infra); more than OVN_HYG_SIG_MAX_IDS (30) ids = a baseline/env break, never a signature;
  - files within OVN_HYG_SIG_MERGE_S (600) of the previous file of the same (repo, kind) are ONE pass (the retry-on-timeout re-run writes a second file);
  - a signature streak = the trailing run of passes whose failing set is non-empty and IDENTICAL; it counts when run >= OVN_HYG_SIG_N (default 3), the newest file is younger than
    OVN_HYG_SIG_MAX_AGE_H (12h) AND state/branch_hygiene_review_<repo> exists (branch_hygiene clears that flag when a merge goes through: no flag = the streak is over).
Mode OVN_HYG_SIGSTREAK:
  shadow (default)  state/hygiene_sigstreak_shadow.log line + ONE alerts.log 'info' line per signature; nothing is pushed.
  on                ONE alerts.log 'crit' line per signature and an 'ALERT<TAB>repo<TAB>title<TAB>body' line on stdout, which ovn_hygiene_stuck_check.sh sends as an
                    URGENT (emergency-class) relay alert naming the tests and the commits that last touched them.
  off               nothing.
Once per signature: state/hygiene_sigstreak_<mode>_seen_<repo>__<kind> holds the signature hash; it is removed when the streak ends, so a later streak alerts again.
Never raises: any problem prints a line to stderr and exits 0.
Env: OVN_DIR (cwd) OVN_STATE_DIR OVN_HYGIENE_GATE_DIR OVN_REPOS_DIR OVN_HYG_SIG_N OVN_HYG_SIG_MERGE_S OVN_HYG_SIG_MAX_IDS OVN_HYG_SIG_MAX_AGE_H OVN_HYG_SIG_REF
"""
import hashlib
import os
import re
import subprocess
import sys
import time

OVN = os.environ.get("OVN_DIR") or os.getcwd()
STATE = os.environ.get("OVN_STATE_DIR") or os.path.join(OVN, "state")
GATE_DIR = os.environ.get("OVN_HYGIENE_GATE_DIR") or os.path.join(OVN, "logs", "hygiene_gate")
REPOS = os.environ.get("OVN_REPOS_DIR") or os.path.join(OVN, "repos")
MODE = os.environ.get("OVN_HYG_SIGSTREAK", "shadow").strip().lower()
SEEN_PREFIX = "hygiene_sigstreak_%s_seen_" % ("on" if MODE == "on" else "shadow")   # per mode: promoting shadow -> on mid-streak still pages once


def envi(name, default):
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


N = max(2, envi("OVN_HYG_SIG_N", 3))
MERGE_S = envi("OVN_HYG_SIG_MERGE_S", 600)
MAX_IDS = envi("OVN_HYG_SIG_MAX_IDS", 30)
MAX_AGE_H = envi("OVN_HYG_SIG_MAX_AGE_H", 12)
REF = os.environ.get("OVN_HYG_SIG_REF", "origin/overnight/feature")

NAME_RE = re.compile(r"^(\d{8}-\d{6})\.([^.]+)\.([^.]+)\.[^.]+$")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
PY_FAIL = re.compile(r"^(?:FAILED|ERROR) (\S+?::\S+?)(?: - .*)?$")
GUT_FAIL = re.compile(r"^--- GUT-FAIL-ID: (\S+)")
GRADLE_FAIL = re.compile(r"^(\S+) > (\S.*?) FAILED\s*$")


def say(msg):
    sys.stderr.write("[hyg-sigstreak] %s\n" % msg)


def failing_ids(text):
    """-> frozenset of failing test ids found in one gate output."""
    out = set()
    for raw in ANSI.sub("", text).split("\n"):
        line = raw.rstrip("\r")
        m = PY_FAIL.match(line) or GUT_FAIL.match(line)
        if m:
            out.add(m.group(1))
            continue
        m = GRADLE_FAIL.match(line)
        if m:
            out.add("%s > %s" % (m.group(1), m.group(2)))
    return frozenset(out)


def parse_ts(s):
    """branch_hygiene names its files with `date +%Y%m%d-%H%M%S` (local time)."""
    return time.mktime(time.strptime(s, "%Y%m%d-%H%M%S"))


def load_passes(gate_dir):
    """-> {(repo, kind): [(epoch, ids, filename), ...] oldest first}, same-pass files merged (the later file wins)."""
    files = []
    try:
        names = os.listdir(gate_dir)
    except OSError:
        return {}
    for n in names:
        m = NAME_RE.match(n)
        if not m:
            continue
        try:
            t = parse_ts(m.group(1))
            with open(os.path.join(gate_dir, n), "rb") as f:
                text = f.read(8_000_000).decode("utf-8", "replace")
        except (OSError, ValueError, OverflowError):
            continue
        files.append((t, m.group(2), m.group(3), failing_ids(text), n))
    by = {}
    for t, repo, kind, ids, n in sorted(files):
        seq = by.setdefault((repo, kind), [])
        if seq and t - seq[-1][0] <= MERGE_S:
            seq[-1] = (t, ids, n)
        else:
            seq.append((t, ids, n))
    return by


def trailing_run(seq):
    """-> (run length, ids, first epoch) of the trailing run of identical NON-EMPTY failing sets (0 when the newest pass is not such a failure)."""
    if not seq:
        return 0, frozenset(), 0
    last = seq[-1][1]
    if not last or len(last) > MAX_IDS:
        return 0, frozenset(), 0
    run, first = 0, seq[-1][0]
    for t, ids, _ in reversed(seq):
        if ids != last:
            break
        run += 1
        first = t
    return run, last, first


def git(args, cwd):
    try:
        p = subprocess.run(["git"] + args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.SubprocessError):
        return 255, ""


def last_touchers(repo, ids, limit=3):
    """-> ['path <- sha subject', ...]: the newest commit on the lane tip (REF, else HEAD) that touched each failing test's file (max `limit` distinct files)."""
    clone = os.path.join(REPOS, repo)
    if not os.path.isdir(clone):
        return []
    rc, _ = git(["rev-parse", "--verify", "-q", REF], clone)
    ref = REF if rc == 0 else "HEAD"
    paths = []
    for i in sorted(ids):
        p = i.split("::")[0] if "::" in i else None
        if p is None:        # gradle 'Class > test': find the class file
            cls = i.split(" > ")[0].split(".")[-1]
            rc, out = git(["ls-tree", "-r", "--name-only", ref], clone)
            cand = [x for x in out.split("\n") if re.search(r"/%s\.(kt|java)$" % re.escape(cls), x)]
            p = cand[0] if cand else None
        p = p.replace("res://", "") if p else p
        if p and p not in paths:
            paths.append(p)
    out = []
    for p in paths[:limit]:
        rc, txt = git(["log", "-n", "1", "--format=%h %an: %s", ref, "--", p], clone)
        if rc == 0 and txt.strip():
            out.append("%s <- %s" % (p, txt.strip()[:110]))
    return out


def append(path, line):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as f:
            f.write(line + "\n")
        return True
    except OSError as e:
        say("could not write %s (%s)" % (path, e))
        return False


def main():
    if MODE == "off":
        return 0
    by = load_passes(GATE_DIR)
    seen_dir = STATE
    now = time.time()
    live = set()
    for (repo, kind), seq in sorted(by.items()):
        key = "%s__%s" % (repo, kind)
        seen_p = os.path.join(seen_dir, "%s%s" % (SEEN_PREFIX, key))
        run, ids, first = trailing_run(seq)
        flag = os.path.join(STATE, "branch_hygiene_review_%s" % repo)
        fresh = bool(seq) and now - seq[-1][0] <= MAX_AGE_H * 3600
        if run < N or not fresh or not os.path.exists(flag):
            continue   # streak over / stale: the seen marker is cleared below
        live.add(seen_p)
        sig = hashlib.sha1("\n".join(sorted(ids)).encode("utf-8", "replace")).hexdigest()[:12]
        try:
            with open(seen_p) as f:
                if f.read().strip() == sig:
                    continue
        except OSError:
            pass
        names = sorted(ids)
        shown = ", ".join(names[:4]) + (" (+%d more)" % (len(names) - 4) if len(names) > 4 else "")
        touched = last_touchers(repo, ids)
        since = time.strftime("%F %H:%M", time.localtime(first))
        body = ("hygiene gate (%s) for %s failed %d consecutive passes with the IDENTICAL failing test set (since %s): %s. This is a deterministic break, not flakiness or the environment. "
                "Last touched: %s. Nothing from this lane reaches develop until it is fixed." % (kind, repo, run, since, shown, "; ".join(touched) or "unknown (no clone / test file not found)"))
        title = "Hygiene gate stuck on the SAME tests: %s" % repo
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        if MODE == "on":
            append(os.path.join(STATE, "alerts.log"), "[%s] crit | hygiene-sigstreak:%s | %s" % (ts, repo, body))
            print("ALERT\t%s\t%s\t%s" % (repo, title, body.replace("\t", " ").replace("\n", " ")))
        else:
            append(os.path.join(STATE, "hygiene_sigstreak_shadow.log"), "%s %s %s run=%d sig=%s tests=%s touched=%s" % (ts, repo, kind, run, sig, ",".join(names), " | ".join(touched) or "-"))
            append(os.path.join(STATE, "alerts.log"), "[%s] info | hygiene-sigstreak:%s | SHADOW (OVN_HYG_SIGSTREAK=on would page): %s" % (ts, repo, body))
        try:
            os.makedirs(seen_dir, exist_ok=True)
            with open(seen_p, "w") as f:
                f.write(sig + "\n")
        except OSError as e:
            say("could not record the signature (%s)" % e)
    # ended streaks: forget the signature so a later streak (even the same tests) alerts again
    try:
        for n in os.listdir(seen_dir):
            if n.startswith(SEEN_PREFIX) and os.path.join(seen_dir, n) not in live:
                os.remove(os.path.join(seen_dir, n))
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never propagate
        say("infra (%s: %s)" % (type(e).__name__, e))
    sys.exit(0)
