#!/usr/bin/env python3
"""scripts/ovn_placeholder_report.py - READ-ONLY report (and shadow alert feed) of generated placeholder files that LANDED on develop. q-fri-shapes 2026-11-20.

The pre-scout "stub new source file" step writes `Placeholder - the implement step fills this in.` into a brand-new file so aider only has to edit it. When the step never fills it, the file stays
on the branch and reaches develop: a test stub (`describe.skip`, a bare comment, an empty py/gd test) LOOKS like coverage but asserts nothing (47 files on 2026-11-20: billwatch 5, gitlark 5,
iptv_apps 15, monitor 3, notify 2, taa 2, xlite 15). branch_hygiene's stub-leak flag only sees the merge CANDIDATE and only placeholder-ONLY SOURCE files; this scans the develop TREE.

  report [--repos-dir DIR | --repo PATH ...] [--ref origin/develop] [--min-age-h 24] [--json]
        per repo: every file of the ref that carries the marker, older than --min-age-h (age = last commit touching the file on the ref), with a kind:
          stub-skip      the marker plus a skipped suite (describe.skip / it.skip / xit / pytest.mark.skip / @Ignore): green and empty
          marker-only    nothing but the marker / comment delimiters / import-export boilerplate
          no-real-assert a TEST file with real-looking code but no reachable non-tautological assertion (the Z1 judge ovn_placeholder_scan.py says `stub`)
          marker-leftover  the marker comment is still there above real code (cosmetic: not a coverage lie)
        and a `test` flag. Default repos dir: $OVN_REPOS_DIR or ~/overnight-queue/repos (every subdirectory with a .git). Read-only: never fetches, never writes. rc 0 always.
  alert  --repo PATH --state DIR [--ref origin/develop] [--min-age-h 24] [--day YYYY-MM-DD] [--dry-run]
        SHADOW feed for branch_hygiene (OVN_PLACEHOLDER_LANDED=shadow|off): appends one row per (repo, file, blob sha) NOT reported in the last 7 days to state/placeholder_landed.log, and ONE alerts.log `warn` per
        run that found new files. Dedupe state: state/placeholder_landed.seen (epoch, repo, path, sha); both files are trimmed to their last ~5000 lines (tmp + replace). Nothing is enforced, nothing is blocked. stub-skip / marker-only / no-real-assert are the alerting kinds;
        marker-leftover rows are logged (so the report is complete) but never alert. --dry-run prints and writes nothing. rc 0 always, fast (git grep + one `git log -1` per hit, 20 s budget).

Never raises: any git/IO failure yields an empty result for that repo.
"""
import json
import os
import re
import subprocess
import sys
import time

MARKER = "Placeholder - the implement step fills this in"
MARKER_RE = re.compile(r"Placeholder - the implement step fills (?:this )?in")
BUDGET_S = float(os.environ.get("OVN_PLACEHOLDER_BUDGET_S", "20") or 20)
MAX_FILES = 400
REWARN_S = 7 * 86400                                                # a (repo, file, blob sha) key warns at most once per 7 days
KEEP_LINES = int(os.environ.get("OVN_PLACEHOLDER_KEEP_LINES", "5000") or 5000)   # placeholder_landed.log / .seen are trimmed to their last N lines
SKIP_RE = re.compile(r"\b(?:describe|it|test)\.skip\b|\bxit\b|\bxdescribe\b|pytest\.mark\.skip|@Ignore|@Disabled|unittest\.skip|@pytest\.mark\.skip")
_COMMENT_ONLY = re.compile(r"^(?:#|//|/\*|\*|<!--|-->|\"\"\"|''')")
_BOILER = re.compile(r"^(?:export \{\}|import .*|from .* import .*|<template>.*</template>|extends \w+|pass|\.\.\.)$")


def _git(repo, *args, timeout=20):
    try:
        r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, errors="replace", timeout=timeout)
        return r.returncode, r.stdout
    except Exception:
        return 1, ""


def is_test_path(path):
    p = path.replace("\\", "/")
    parts = p.split("/")
    base = parts[-1]
    if any(x in ("tests", "test", "__tests__", "spec", "specs", "androidTest", "UITests") for x in parts[:-1]):
        return True
    return bool(re.search(r"(^test_|_test\.|\.test\.|\.spec\.|Tests?\.[A-Za-z]+$)", base))


_SCAN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ovn_placeholder_scan.py")


def _scan_verdict(path, body):
    """`real` | `stub` from the Z1 judge (ovn_placeholder_scan.py: a test file is real only with a reachable test holding a non-tautological assertion); '' when it cannot run (fail open)."""
    try:
        if not os.path.isfile(_SCAN):
            return ""
        r = subprocess.run([sys.executable, _SCAN, path, MARKER], input=body, capture_output=True, text=True, errors="replace", timeout=10)
        v = r.stdout.strip().split("\n")[-1].strip() if r.returncode == 0 else ""
        return v if v in ("real", "stub") else ""
    except Exception:
        return ""


def classify(body, path=""):
    """-> kind of a marker-carrying file body: stub-skip | marker-only | no-real-assert | marker-leftover."""
    if SKIP_RE.search(body):
        return "stub-skip"
    real = 0
    for ln in body.splitlines():
        s = ln.strip()
        if not s or MARKER_RE.search(s) or _COMMENT_ONLY.match(s) or _BOILER.match(s):
            continue
        real += 1
    if real == 0:
        return "marker-only"
    if path and is_test_path(path) and _scan_verdict(path, body) == "stub":
        return "no-real-assert"
    return "marker-leftover"


def resolve_ref(repo, ref):
    for r in ([ref] if ref else []) + ["origin/develop", "develop"]:
        rc, _o = _git(repo, "rev-parse", "--verify", "--quiet", r + "^{commit}", timeout=10)
        if rc == 0:
            return r
    return ""


def scan_repo(repo, ref="origin/develop", min_age_h=24.0, now=None):
    """-> [{"path", "kind", "test", "age_h", "ref"}] for files of `ref` carrying the marker and older than min_age_h; [] on any problem."""
    out = []
    try:
        now = now if now is not None else time.time()
        t0 = time.monotonic()
        rf = resolve_ref(repo, ref)
        if not rf:
            return out
        rc, txt = _git(repo, "grep", "-l", "-z", "-I", "-F", "-e", MARKER, rf, "--", timeout=30)
        if rc not in (0, 1):
            return out
        paths = []
        for ent in txt.split("\0"):
            if ent.startswith(rf + ":"):
                paths.append(ent[len(rf) + 1:])
        for path in sorted(paths)[:MAX_FILES]:
            if time.monotonic() - t0 > BUDGET_S:
                break
            rc, ct = _git(repo, "log", "-1", "--format=%ct", rf, "--", path, timeout=15)
            try:
                age_h = (now - int(ct.strip())) / 3600.0
            except ValueError:
                continue
            if age_h < min_age_h:
                continue
            rc, body = _git(repo, "show", "%s:%s" % (rf, path), timeout=15)
            if rc != 0 or len(body) > 400000:
                continue
            rc, sha = _git(repo, "rev-parse", "%s:%s" % (rf, path), timeout=10)
            out.append({"path": path, "kind": classify(body, path), "test": is_test_path(path), "age_h": round(age_h, 1), "ref": rf, "sha": sha.strip() if rc == 0 else ""})
    except Exception:
        return out
    return out


def repos_from(args_repos, repos_dir):
    if args_repos:
        return [r for r in args_repos if os.path.isdir(os.path.join(r, ".git")) or os.path.isfile(os.path.join(r, ".git"))]
    d = repos_dir or os.environ.get("OVN_REPOS_DIR") or os.path.expanduser("~/overnight-queue/repos")
    try:
        return [os.path.join(d, n) for n in sorted(os.listdir(d)) if os.path.exists(os.path.join(d, n, ".git"))]
    except OSError:
        return []


def _alerting(row):
    return row["kind"] in ("stub-skip", "marker-only", "no-real-assert")


def _read_lines(path):
    try:
        with open(path) as f:
            return [x for x in f.read().split("\n") if x]
    except OSError:
        return []


def _atomic_write(path, lines):
    """tmp in the same directory + os.replace: a reader never sees a half-written file."""
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as f:
        f.write("".join(x + "\n" for x in lines))
    os.replace(tmp, path)


def _trim(path, keep=None):
    """keep only the last `keep` lines of an append-only log (atomic); a short file is left alone."""
    keep = KEEP_LINES if keep is None else keep
    lines = _read_lines(path)
    if len(lines) > keep:
        _atomic_write(path, lines[-keep:])


def alert(repo, state, ref, min_age_h, day=None, dry=False, now=None):
    """-> (new_rows). Writes state/placeholder_landed.log + .seen and one alerts.log warn per repo per run with new files; nothing when dry.
    Dedupe is PER FILE: a (repo, path, blob sha) key reported in the last 7 days is not reported again (it re-warns after 7 days, or at once when the file's content changed)."""
    try:
        name = os.path.basename(os.path.abspath(repo))
        day = day or time.strftime("%Y-%m-%d", time.gmtime(now if now is not None else time.time()))
        rows = scan_repo(repo, ref, min_age_h, now)
        seen_p = os.path.join(state, "placeholder_landed.seen")
        t_now = int(now if now is not None else time.time())
        seen_lines = _read_lines(seen_p)
        last = {}
        for ln in seen_lines:
            f = ln.split("\t")
            if len(f) == 4 and f[0].isdigit():
                last[(f[1], f[2], f[3])] = int(f[0])
        new = [r for r in rows if t_now - last.get((name, r["path"], r.get("sha", "")), -REWARN_S) >= REWARN_S]
        if dry or not new:
            return new
        os.makedirs(state, exist_ok=True)
        _atomic_write(seen_p, (seen_lines + ["%d\t%s\t%s\t%s" % (t_now, name, r["path"], r.get("sha", "")) for r in new])[-KEEP_LINES:])
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now if now is not None else time.time()))
        with open(os.path.join(state, "placeholder_landed.log"), "a") as f:
            for r in new:
                f.write(json.dumps({"ts": stamp, "day": day, "repo": name, "path": r["path"], "kind": r["kind"], "test": r["test"], "age_h": r["age_h"], "ref": r["ref"], "sha": r.get("sha", "")}) + "\n")
        _trim(os.path.join(state, "placeholder_landed.log"))
        al = [r for r in new if _alerting(r)]
        if al:
            ts = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(now if now is not None else time.time()))
            sample = ", ".join(r["path"] for r in al[:4])
            msg = "%d placeholder file(s) landed on %s and still carry the generated stub (%d test stub(s)) - they look like coverage but assert nothing; shadow report, nothing blocks: %s%s (python3 scripts/ovn_placeholder_report.py report --repo %s)" % (
                len(al), al[0]["ref"], sum(1 for r in al if r["test"]), sample, " ..." if len(al) > 4 else "", repo)
            with open(os.path.join(state, "alerts.log"), "a") as f:
                f.write("[%s] warn | placeholder-landed:%s | %s\n" % (ts, name, msg))
        return new
    except Exception:
        return []


def main(argv):
    a = list(argv[1:])

    def opt(name, default=None, multi=False):
        vals = []
        while name in a:
            i = a.index(name)
            vals.append(a[i + 1] if i + 1 < len(a) else default)
            del a[i:i + 2]
        return vals if multi else (vals[-1] if vals else default)
    try:
        cmd = a.pop(0) if a else "report"
        ref = opt("--ref", "origin/develop")
        age = float(opt("--min-age-h", "24") or 24)
        if cmd == "alert":
            repo, state = opt("--repo"), opt("--state")
            dry = "--dry-run" in a
            if not repo or not state:
                print(__doc__)
                return 0
            for r in alert(repo, state, ref, age, opt("--day"), dry):
                if dry:
                    print("\t".join([os.path.basename(os.path.abspath(repo)), r["kind"], "test" if r["test"] else "src", str(r["age_h"]), r["path"]]))
            return 0
        if cmd != "report":
            print(__doc__)
            return 0
        repos = repos_from(opt("--repo", multi=True), opt("--repos-dir"))
        js = "--json" in a
        allrows = {}
        for r in repos:
            allrows[os.path.basename(os.path.abspath(r))] = scan_repo(r, ref, age)
        if js:
            print(json.dumps({"min_age_h": age, "ref": ref, "repos": allrows}))
            return 0
        tot = 0
        for n, rows in allrows.items():
            tests = sum(1 for x in rows if x["test"])
            print("%s: %d file(s) (%d test)  %s" % (n, len(rows), tests, " ".join("%s=%d" % (k, sum(1 for x in rows if x["kind"] == k)) for k in ("stub-skip", "marker-only", "no-real-assert", "marker-leftover"))))
            for x in rows:
                print("  %-15s %s %6.1fh  %s" % (x["kind"], "T" if x["test"] else "S", x["age_h"], x["path"]))
            tot += len(rows)
        print("TOTAL %d file(s) in %d repo(s) (ref %s, older than %gh)" % (tot, len(allrows), ref, age))
    except Exception as e:
        print("placeholder-report-error:%s" % type(e).__name__, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
