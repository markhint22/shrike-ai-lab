#!/usr/bin/env python3
"""baseline_verify.py - BASELINE-RELATIVE full-suite verification (gate S4, key: baseline).

Problem: ovn_stage_runner.sh full_verify() demands the WHOLE suite green. One pre-existing red test makes every staged
step 'stage-unverified' and discards finished work. This library stores the red-test-id set of a repo (deterministically,
24h expiry) and compares a verify run's failing set against it:

    new_failures  = failing now, not in the baseline          -> FAIL
    preexisting   = failing now, also in the baseline         -> tolerated
    fixed         = in the baseline, passing now

Verdicts: PASS (no new failures, even if pre-existing red remains) | FAIL (new failures vs a live baseline; a bare non-baselineable gate
failure such as QUALITY/SEMANTIC FAIL is NA since 2026-10-03: the runner already enforces it) | UNVERIFIED (could not tell: no/expired baseline AND failures present, truncated/unparseable log,
runner failed for an unparseable reason). Never a guess. Library + CLI; wired into ovn_stage_runner.sh in SHADOW only (2026-10-02, see baseline.README.md).

CLI (one JSON line on stdout, exit 0 always; mode via qa_common.mode("baseline")):
  baseline_verify.py snapshot --repo R --failing-file F [--format auto|pytest|vitest|gradle|gut|verify-log|ids]
                              [--commit SHA] [--source TAG] [--accept-growth]
  baseline_verify.py compare  --repo R --failing-file F [--format ...] [--base-sha S] [--runner-failed]
  baseline_verify.py refresh  --repo R [--ref origin/overnight/feature]   (python/pytest repos: run suite in a worktree + snapshot)
  baseline_verify.py shadow-log --repo R --result-file F --runner-decision verified|not_verified --run ID   (staged-runner hook: one paired row)
  baseline_verify.py show     --repo R
  baseline_verify.py parse    --failing-file F [--format ...]              (debug: print parsed ids)
  baseline_verify.py replay   --logs-dir D [--days N] [--out FILE]         (historical estimate over state/stage_runs)
Common flags: --no-record (skip shadow log).  State: $OVN_DIR/state/qa_baselines/verify/<repo>.json (atomic replace, no locks).

Hard design rules (past incidents):
  * Only deterministic code writes a baseline: snapshot input must be a COMPLETE parse of a real run log (truncated/timeouted
    logs are refused, never half-stored). 'ids' format (hand-fed id list) is accepted only with --source starting 'deterministic:'.
  * Never auto-widen: a snapshot whose red set contains ids not in the active baseline does NOT replace it; it is kept as
    pending_growth, a growth alert is logged, and compare surfaces it. Widening needs an explicit --accept-growth from a human
    or from a deterministic caller (e.g. a clean-base refresh).
  * Fresh baselines over MAX_BASELINE (default 300 ids, env OVN_QA_BASELINE_MAX) are refused: a mostly-red suite means baseline
    relative verification is meaningless and a person should look.
"""
import argparse
import collections
import glob
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "baseline"
TTL_S = int(os.environ.get("OVN_QA_BASELINE_TTL_S", "86400"))
MAX_BASELINE = int(os.environ.get("OVN_QA_BASELINE_MAX", "300"))
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


# ----------------------------------------------------------------------------------------------------------------- parsers
def strip_ansi(t):
    return ANSI.sub("", t)


_SECRET_PATTERNS = [
    (re.compile(r"(://[^/\s:@\[\]]*:)[^@/\s]+(@)"), r"\1***\2"),                                   # url credentials
    (re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=\-]{8,}"), "Bearer ***"),
    (re.compile(r"(?i)((?:password|passwd|pwd|secret|token|api[_-]?key|apikey|auth(?:orization)?)\w{0,6}\s*[=:]\s*[\"']?)[A-Za-z0-9+/=_.\-~]{6,}"), r"\1***"),
    (re.compile(r"\b(?:sk|pk|rk|ghp|gho|ghs|xox[abp])[-_][A-Za-z0-9_\-]{16,}"), "***"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "***"),
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*"), "***"),            # JWT
    (re.compile(r"\b(?=[A-Za-z0-9+/=]*\d)(?=[A-Za-z0-9+/=]*[A-Za-z])[A-Za-z0-9+/=]{32,}\b"), "***"),  # long mixed token-like blob
]


def redact(s):
    """Spec hard rule 5: ids come from test output (param ids can carry credentials) and are echoed to stdout, the baseline file and
    growth_alerts.jsonl. Redact url credentials and token-like strings. Applied identically at snapshot and compare time."""
    for pat, repl in _SECRET_PATTERNS:
        s = pat.sub(repl, s)
    return s


def _result(fmt, ids=None, hard=None, complete=True, reasons=None, expected=None):
    ids = [redact(i) for i in (ids or [])]
    hard = [redact(i) for i in (hard or [])]
    return {"format": fmt, "ids": sorted(set(ids)), "hard": sorted(set(hard)), "complete": bool(complete),
            "reasons": list(reasons or []), "expected": expected}


def _cut_msg(s):
    """Strip ' - message' from a pytest short-summary id, bracket-aware (param ids may contain ' - ')."""
    depth = 0
    for i, ch in enumerate(s):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth = max(0, depth - 1)
        elif depth == 0 and s.startswith(" - ", i):
            return s[:i].strip()
    return s.strip()


_PYTEST_SUMMARY = re.compile(r"(?:^|\s)(\d+) (failed|passed|errors?|skipped|xfailed|xpassed|warnings?|deselected|rerun|subtests passed)\b")
_PYTEST_FINAL = re.compile(r"^(=+ )?((\d+ \w+( \w+)?(, )?)+| *no tests ran| *Interrupted:.*)\s*in [\d.]+s.*$|^no tests ran in [\d.]+s")
_PYTEST_ID = re.compile(r"^(FAILED|ERROR) (\S.*)$")


def parse_pytest(text, prefix=""):
    """pytest -q (also -n xdist). ids = FAILED/ERROR node ids from the short test summary. complete=False if the run was
    truncated (timeout mid-progress-bar) or the parsed id count is below the summary's failed+error count."""
    lines = strip_ansi(text).splitlines()
    ids = set()
    for l in lines:
        m = _PYTEST_ID.match(l)
        if not m:
            continue
        nid = _cut_msg(m.group(2))
        if "::" in nid or re.match(r"^[\w./\-]+\.py", nid) or "/" in nid:
            ids.add(prefix + nid)
    final = None
    internal = any(l.startswith("INTERNALERROR>") for l in lines)
    for l in reversed(lines):
        s = l.strip()
        if s and _PYTEST_FINAL.match(s):
            final = s
            break
    reasons = []
    expected = None
    complete = True
    progress = any(re.match(r"^[.FEsxX]+\s*(\[\s*\d+%\])?$", l.strip()) and len(l.strip()) > 3 for l in lines)
    if final is None:
        complete = False
        reasons.append("pytest run has no final summary line (truncated or timed out)" if (progress or ids or text.strip()) else "empty pytest output")
    else:
        n = 0
        for cnt, kind in _PYTEST_SUMMARY.findall(final):
            if kind in ("failed", "error", "errors"):
                n += int(cnt)
        expected = n
        if len(ids) < n:
            complete = False
            reasons.append("summary says %d failed/error but only %d ids parsed" % (n, len(ids)))
    if internal:
        complete = False
        reasons.append("pytest INTERNALERROR (the run crashed; the failing set is unknowable)")
    return _result("pytest", ids, None, complete, reasons, expected)


def parse_vitest(text, prefix=""):
    lines = strip_ansi(text).splitlines()
    ids = set()
    pat = re.compile(r"^\s*(?:FAIL|×|✗|✖)\s+(\S+\.(?:test|spec)\.[cm]?[jt]sx?)(?:\s*\[[^\]]*\])?(?:\s*>\s*(.+?))?(?:\s+\d+ms)?\s*$")
    for l in lines:
        m = pat.match(l)
        if m:
            ids.add(prefix + m.group(1) + ((" > " + re.sub(r"\s+", " ", m.group(2).strip())) if m.group(2) else ""))
    complete = any(re.match(r"^\s*Test Files\s", l) for l in lines)
    return _result("vitest", ids, None, complete, [] if complete else ["vitest run has no 'Test Files' summary (truncated or crashed)"])


def parse_gradle(text, prefix=""):
    lines = strip_ansi(text).splitlines()
    ids = set()
    for l in lines:
        m = re.match(r"^> Task (\S+) FAILED$", l)
        if m:
            ids.add(prefix + "task:" + m.group(1).lstrip(":"))
            continue
        m = re.match(r"^([\w.$]+(?: > [^\n]*?)+) FAILED$", l)
        if m:
            ids.add(prefix + m.group(1))
            continue
        # compiler errors: a per-SOURCE-FILE id (no line numbers, no /tmp/stage-* prefix) so a compile error in a NEW file is a new
        # failure even though the coarse 'task:...' id is already in the baseline
        m = (re.match(r"^e: (?:file://)?(\S+?\.(?:kt|kts)):\s*\(?\d+", l)          # new 'e: file:///p.kt:3:4' and old 'e: /p.kt: (3, 4)'
             or re.match(r"^e: (?:file://)?(\S+?\.(?:kt|kts))\b", l))
        if m:
            ids.add(prefix + "kotlinc:" + re.sub(r"^/tmp/[^/]+/", "", m.group(1)))
            continue
        m = re.match(r"^(?:file://)?(\S+?\.java):\d+: error:", l)                 # javac
        if m:
            ids.add(prefix + "javac:" + re.sub(r"^/tmp/[^/]+/", "", m.group(1)))
    failed = any(l.startswith("BUILD FAILED") for l in lines)
    complete = failed or any(l.startswith("BUILD SUCCESSFUL") for l in lines)
    reasons = [] if complete else ["gradle has no BUILD SUCCESSFUL/FAILED line (timeout?)"]
    if failed and not ids:
        # a failed build whose failing tasks/tests we could not identify: the failing SET is unknowable, never 'no failing tests'
        complete = False
        reasons.append("gradle BUILD FAILED but no failing task/test/compile id could be parsed")
    return _result("gradle", ids, None, complete, reasons)


def parse_gut(text, prefix=""):
    lines = strip_ansi(text).splitlines()
    ids = set()
    try:
        start = max(i for i, l in enumerate(lines) if "Run Summary" in l)
    except ValueError:
        start = None
    expected = None
    if start is not None:
        cur_file, cur_test = None, None
        for l in lines[start:]:
            if l.startswith("res://"):
                cur_file, cur_test = l.strip(), None
            elif l.startswith("- "):
                cur_test = l[2:].strip()
            elif "[Failed" in l and cur_file and cur_test:
                ids.add(prefix + cur_file + "::" + cur_test)
            m = re.match(r"^\s*Failing\s+(\d+)", l)
            if m:
                expected = int(m.group(1))
    hard = set()
    for l in lines:
        m = re.search(r"Parse Error: (.+)$", l)
        if m:
            ids.add(prefix + "godot-parse:" + re.sub(r"\s+", " ", m.group(1))[:160])
        m = re.search(r'Failed to (?:load|compile) script "?([^"\s]+)', l)
        if m:
            ids.add(prefix + "godot-load:" + m.group(1))
    complete = any("---- Totals ----" in l for l in lines)
    reasons = [] if complete else ["GUT run has no Totals block (crashed or timed out)"]
    if expected is not None:
        got = len([i for i in ids if "::" in i])
        if got < expected:
            complete = False
            reasons.append("GUT says %d failing but %d parsed" % (expected, got))
    return _result("gut", ids, hard, complete, reasons, expected)


STAGE_ORDER = ["pytest", "gradle", "gut", "vitest", "shell", "docker"]   # == ovn_stage_runner.sh full_verify() order
_SECTION = re.compile(r"^-- (pytest FULL in (\S+)|gradlew test FULL in (\S+)|GUT FULL --|vitest FULL --|docker build FULL in (\S+)|"
                      r"python tests exist but|QUALITY FAIL|SEMANTIC FAIL|semantic OK)")


def parse_verify_log(text):
    """The staged runner's <run>.verify.log (see ovn_stage_runner.sh full_verify). Splits into the '-- ... --' sections it writes
    and dispatches per section. Hard (non-baselineable) failures: QUALITY FAIL, SEMANTIC FAIL, fail-closed (python tests but no
    venv), shell syntax errors, docker build errors."""
    raw = strip_ansi(text).splitlines()
    secs, cur = [], None
    for l in raw:
        m = _SECTION.match(l)
        if m:
            cur = {"head": l, "kind": None, "label": "", "body": []}
            h = m.group(1)
            if h.startswith("pytest"):
                cur["kind"], cur["label"] = "pytest", m.group(2)
            elif h.startswith("gradlew"):
                cur["kind"], cur["label"] = "gradle", m.group(3)
            elif h.startswith("GUT"):
                cur["kind"] = "gut"
            elif h.startswith("vitest"):
                cur["kind"] = "vitest"
            elif h.startswith("docker"):
                cur["kind"], cur["label"] = "docker", m.group(4)
            else:
                cur["kind"] = "gate"
            secs.append(cur)
            continue
        if cur is None:
            cur = {"head": "", "kind": "preamble", "label": "", "body": []}
            secs.append(cur)
        cur["body"].append(l)
    ids, hard, reasons, complete, kinds, stage_bad = set(), set(), [], True, [], []
    for s in secs:
        body = "\n".join(s["body"])
        k = s["kind"]
        if k == "pytest":
            p = parse_pytest(body, prefix="[%s] " % s["label"] if s["label"] else "")
            kinds.append("pytest")
        elif k == "gradle":
            p = parse_gradle(body, prefix="[%s] " % s["label"])
            kinds.append("gradle")
        elif k == "gut":
            p = parse_gut(body)
            kinds.append("gut")
        elif k == "vitest":
            p = parse_vitest(body)
            kinds.append("vitest")
        elif k == "docker":
            bad = re.search(r"(?m)^(ERROR: failed to (solve|build)|The command .* returned a non-zero code|failed to solve)", body)
            if bad:
                hard.add("docker-build:%s" % s["label"])
                stage_bad.append(("docker", True))
            kinds.append("docker")
            continue
        elif k == "gate":
            h = s["head"]
            if h.startswith("-- QUALITY FAIL") or h.startswith("-- SEMANTIC FAIL"):
                hard.add(re.sub(r"\s+", " ", h[3:])[:160])
            elif h.startswith("-- python tests exist but"):
                hard.add("fail-closed: python tests exist but no venv pytest found")
            continue
        else:
            # preamble / trailing text: shell-syntax failures from `bash -n`
            for l in s["body"]:
                if re.search(r": line \d+: .*(syntax error|unexpected)", l):
                    hard.add("shell-syntax: " + re.sub(r"/tmp/\S+?/(?=\S)", "", l.strip())[:140])
            continue
        ids |= set(p["ids"])
        hard |= set(p["hard"])
        stage_bad.append((k, bool(p["ids"]) or bool(p["hard"]) or not p["complete"]))
        if not p["complete"]:
            complete = False
            reasons += ["%s: %s" % (s["label"] or k, r) for r in p["reasons"]]
    for l in raw:
        if re.search(r": line \d+: .*(syntax error|unexpected EOF)", l):
            hard.add("shell-syntax: " + re.sub(r"/tmp/\S+?/(?=\S)", "", l.strip())[:140])
    if not kinds and not hard:
        complete = False
        reasons.append("verify log has no recognizable test stage (empty or unknown format)")
    # Runner stage order and short-circuit: full_verify() runs each later stage only `if vok=1`, so after the first failing stage the
    # rest NEVER RAN. Record which stage kinds may therefore have been skipped; compare_sets() must not call that a PASS.
    first_bad = None
    for k, bad in stage_bad:
        if bad:
            first_bad = k
            break
    skipped = []
    if first_bad in STAGE_ORDER:
        skipped = list(STAGE_ORDER[STAGE_ORDER.index(first_bad) + 1:])
        if first_bad == "gradle":
            skipped.insert(0, "gradle")  # further gradle projects are skipped too
    return _result("verify-log", ids, hard, complete, reasons) | {"kinds": kinds, "skipped_stages": skipped, "first_failed_stage": first_bad}


def parse_ids(text):
    ids = [l.strip() for l in text.splitlines() if l.strip() and not l.startswith("#")]
    return _result("ids", ids, None, True, [])


def detect_format(text):
    t = strip_ansi(text)
    if re.search(r"(?m)^-- (pytest FULL|gradlew test FULL|GUT FULL|vitest FULL)", t) or "independent full-verify" in t:
        return "verify-log"
    if "Test Files" in t and re.search(r"(?m)^\s*(FAIL|✓|×)\s", t):
        return "vitest"
    if "---- Totals ----" in t or "Run Summary" in t:
        return "gut"
    if re.search(r"(?m)^(> Task |BUILD (SUCCESSFUL|FAILED))", t):
        return "gradle"
    if re.search(r"(?m)^(FAILED|ERROR) \S+|\bin [\d.]+s\b|^[.FEsxX]+\s*\[", t):
        return "pytest"
    if t.strip() and all(re.match(r"^[\w./\-\[\]:<> ,=()\"'|]+$", l) for l in t.splitlines() if l.strip()):
        return "ids"
    return "pytest"


def parse_text(text, fmt="auto"):
    if fmt == "auto":
        fmt = detect_format(text)
    fn = {"pytest": parse_pytest, "vitest": parse_vitest, "gradle": parse_gradle, "gut": parse_gut,
          "verify-log": parse_verify_log, "ids": parse_ids}.get(fmt)
    if fn is None:
        raise ValueError("unknown --format %r" % fmt)
    return fn(text)


# -------------------------------------------------------------------------------------------------------- baseline store
def store_dir():
    return os.path.join(qc.state_dir(), "qa_baselines", "verify")


def _safe_repo(repo):
    if not re.match(r"^[\w.\-]+$", repo or ""):
        raise ValueError("bad repo name %r" % repo)
    return repo


def baseline_path(repo):
    return os.path.join(store_dir(), _safe_repo(repo) + ".json")


def load_baseline(repo):
    try:
        with open(baseline_path(repo)) as f:
            d = json.load(f)
        return d if isinstance(d, dict) and isinstance(d.get("failing"), list) else None
    except (OSError, ValueError):
        return None


def save_baseline(repo, data):
    os.makedirs(store_dir(), exist_ok=True)
    p = baseline_path(repo)
    tmp = "%s.tmp.%d" % (p, os.getpid())
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    os.replace(tmp, p)


def baseline_age(bl, now=None):
    return (now if now is not None else time.time()) - float(bl.get("ts", 0))


def active(bl, now=None):
    """Baseline dict if present and younger than its TTL, else None."""
    return bl if bl and baseline_age(bl, now) <= float(bl.get("ttl_s", TTL_S)) else None


def log_growth(repo, info):
    try:
        os.makedirs(store_dir(), exist_ok=True)
        with open(os.path.join(store_dir(), "growth_alerts.jsonl"), "a") as f:
            f.write(json.dumps(dict(info, repo=repo, ts=time.time()), sort_keys=True) + "\n")
    except OSError:
        pass


def _iso(ts=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts if ts is not None else time.time()))


def snapshot_set(repo, parsed, commit="", source="", accept_growth=False, now=None):
    """Pure-ish: apply the snapshot rules. Returns (status, info) and writes the store when allowed.
    status: stored | stored_fresh | stored_shrunk | growth_pending | refused_incomplete | refused_hard | refused_too_red | refused_hand_fed"""
    now = now if now is not None else time.time()
    if parsed["format"] == "ids" and not str(source).startswith("deterministic:"):
        return "refused_hand_fed", {"why": "ids-format snapshots need --source deterministic:<tool>; baselines are never LLM/hand written"}
    if not parsed["complete"]:
        return "refused_incomplete", {"why": "; ".join(parsed["reasons"]) or "incomplete parse"}
    if parsed["hard"]:
        return "refused_hard", {"why": "run has non-baselineable failures (%s): not a clean red-test snapshot" % "; ".join(parsed["hard"][:3])}
    new = set(parsed["ids"])
    old_bl = load_baseline(repo)
    cur = active(old_bl, now)
    hist = list((old_bl or {}).get("history", []))[-19:]
    base = {"version": 1, "repo": repo, "ts": now, "iso": _iso(now), "commit": commit, "source": source, "parser": parsed["format"],
            "failing": sorted(new), "count": len(new), "ttl_s": TTL_S, "pending_growth": None}
    if len(new) > MAX_BASELINE:
        return "refused_too_red", {"why": "%d red ids exceeds OVN_QA_BASELINE_MAX=%d" % (len(new), MAX_BASELINE)}
    if cur is not None:
        added = sorted(new - set(cur["failing"]))
        if added and not accept_growth:
            pend = {"ts": now, "iso": _iso(now), "commit": commit, "source": source, "added": added, "candidate_count": len(new)}
            keep = dict(cur)
            keep["pending_growth"] = pend
            save_baseline(repo, keep)
            log_growth(repo, {"kind": "growth_pending", "added": added[:50], "n_added": len(added), "commit": commit})
            return "growth_pending", {"added": added, "kept_count": len(cur["failing"]), "why": "red set grew; active baseline NOT widened"}
        status = "stored_shrunk" if set(cur["failing"]) - new else "stored"
        if added:
            log_growth(repo, {"kind": "growth_accepted", "added": added[:50], "n_added": len(added), "commit": commit, "source": source})
            status = "stored_grown_accepted"
    else:
        status = "stored_fresh"
        if old_bl:
            # expired (or otherwise inactive) baseline replaced: waiting out the TTL must not be a silent way to widen the red set
            added = sorted(new - set(old_bl.get("failing", [])))
            if added:
                log_growth(repo, {"kind": "growth_accepted_after_expiry", "added": added[:50], "n_added": len(added), "commit": commit,
                                  "source": source, "expired_age_s": int(baseline_age(old_bl, now))})
                status = "stored_fresh_grown"
    hist.append({"ts": now, "commit": commit, "count": len(new)})
    base["history"] = hist
    save_baseline(repo, base)
    return status, {"count": len(new)}


def _test_file_of(tid):
    t = re.sub(r"^\[[^\]]*\]\s*", "", tid)
    return t.split("::")[0].split(" > ")[0]


def _stem(path):
    b = os.path.basename(path)
    b = re.sub(r"\.(test|spec)\.[cm]?[jt]sx?$|\.(py|kt|java|gd|ts|tsx|js|vue)$", "", b)
    return re.sub(r"^test_|_test$|Test$|Tests$", "", b).lower()


def overlap(preexisting, changed_files):
    """Pre-existing red ids that sit in the area THIS change touched (the change might have made an already-red test worse, which
    id-set comparison cannot see). Heuristics: test file edited itself; test stem related to an edited source stem (either prefix of the
    other); migration tests vs an alembic/migrations edit; kotlinc:<file> exact file; gradle task ids vs any edit under the [package] dir."""
    ch = [c for c in (changed_files or []) if c]
    if not ch:
        return []
    chs = [(c, _stem(c)) for c in ch]
    out = []
    for tid in preexisting:
        label = re.match(r"^\[([^\]]*)\]", tid)
        label = label.group(1) if label else ""
        body = re.sub(r"^\[[^\]]*\]\s*", "", tid)
        hit = False
        if body.startswith(("kotlinc:", "javac:")):
            f = body.split(":", 1)[1]
            hit = any(c.endswith(f) or f.endswith(c) for c, _ in chs)
        elif body.startswith("task:"):
            hit = bool(label) and any(c.startswith(label + "/") for c, _ in chs)
        else:
            tf = _test_file_of(tid)
            ts = _stem(tf)
            for c, cs in chs:
                if c.endswith(tf) or tf.endswith(c):
                    hit = True
                elif ts and cs and (ts == cs or ts.startswith(cs) or cs.startswith(ts)):
                    hit = True
                elif "migration" in ts and re.search(r"(alembic|migrations)/", c):
                    hit = True
                if hit:
                    break
        if hit:
            out.append(tid)
    return out


_STAGE_FILES = {
    "gradle": re.compile(r"(?i)\.(kt|kts|java|gradle|properties|xml|pro|toml)$|(^|/)gradlew?$"),
    "gut": re.compile(r"(?i)\.(gd|tscn|tres|godot|import|cfg)$|(^|/)project\.godot$"),
    "vitest": re.compile(r"(?i)\.(js|jsx|ts|tsx|mjs|cjs|vue|json|css)$"),
    "docker": re.compile(r"(?i)(^|/)(Dockerfile[^/]*|[^/]*\.dockerfile|\.dockerignore|docker-compose[^/]*\.ya?ml)$"),
    "pytest": re.compile(r"(?i)\.(py|ini|cfg|toml|txt)$"),
}


def _bash_n(path):
    import subprocess
    try:
        r = subprocess.run(["bash", "-n", path], capture_output=True, text=True, timeout=20)
        return r.returncode == 0, (r.stderr or "")[:200]
    except (OSError, subprocess.SubprocessError) as ex:
        return None, str(ex)[:200]


def skipped_stage_check(parsed, changed_files, worktree=None):
    """The runner skips every full_verify stage after the first failing one. A PASS is only honest if the skipped stages are
    irrelevant to this change or were run independently here. Returns (verdict|None, note, hard[]):
      * None  -> nothing skipped / all skipped stages provably irrelevant (or checked here: `bash -n` on changed .sh files);
      * UNVERIFIED -> a skipped stage applies to the change (or the changed files are unknown) and cannot be run by this gate;
      * hard list -> an independently run check failed (e.g. bash -n)."""
    skipped = list(parsed.get("skipped_stages") or [])
    if not skipped:
        return None, "", []
    ch = [c for c in (changed_files or []) if c]
    if not ch:
        return "UNVERIFIED", "stage(s) %s were skipped after the first failing stage and the changed files are unknown, so a pass cannot be claimed" % ",".join(skipped), []
    unchecked, hard = [], []
    for k in skipped:
        if k == "shell":
            for c in ch:
                if not c.endswith(".sh"):
                    continue
                path = os.path.join(worktree, c) if worktree else None
                if not path or not os.path.isfile(path):
                    unchecked.append("shell:%s (cannot read changed file)" % c)
                    continue
                okk, err = _bash_n(path)
                if okk is None:
                    unchecked.append("shell:%s (bash unavailable)" % c)
                elif not okk:
                    hard.append("shell-syntax: %s: %s" % (c, err.strip().replace("\n", " ")))
        elif k in _STAGE_FILES:
            rel = [c for c in ch if _STAGE_FILES[k].search(c)]
            if k == "pytest":
                continue
            if rel:
                unchecked.append("%s:%s" % (k, rel[0]))
    if hard:
        return "FAIL", "independent check of a skipped stage failed: " + "; ".join(hard[:2]), hard
    if unchecked:
        return "UNVERIFIED", "stage(s) skipped after the first failing stage apply to this change and were not run (%s): cannot claim PASS" % "; ".join(unchecked[:3]), []
    return None, "skipped stages %s do not apply to the %d changed file(s)" % (",".join(skipped), len(ch)), []


def compare_sets(parsed, bl, runner_failed=False, now=None, changed_files=None, strict_overlap=False, worktree=None):
    """Core decision. parsed = parser result; bl = stored baseline dict or None. Returns (verdict, summary, details)."""
    now = now if now is not None else time.time()
    ids = set(parsed["ids"])
    hard = list(parsed["hard"])
    cur = active(bl, now)
    d = {"format": parsed["format"], "failing_count": len(ids), "hard_failures": hard[:10], "new_failures": [], "preexisting": [], "fixed": [],
         "baseline": None, "growth": None}
    if bl:
        d["baseline"] = {"commit": bl.get("commit"), "iso": bl.get("iso"), "age_s": int(baseline_age(bl, now)), "count": len(bl["failing"]),
                         "expired": cur is None}
        pg = bl.get("pending_growth")
        h = bl.get("history") or []
        if pg:
            d["growth"] = {"kind": "pending", "added": pg.get("added", [])[:50], "n_added": len(pg.get("added", [])), "since": pg.get("iso")}
        elif len(h) >= 2 and h[-1]["count"] > h[-2]["count"]:
            d["growth"] = {"kind": "accepted", "from": h[-2]["count"], "to": h[-1]["count"]}
    if not parsed["complete"]:
        return "UNVERIFIED", "cannot compare: " + ("; ".join(parsed["reasons"]) or "incomplete log"), d
    if hard:
        # QUALITY/SEMANTIC/fail-closed/syntax/docker: about THIS change, never baseline-tolerated
        base_ids = set(cur["failing"]) if cur else set()
        d["new_failures"] = sorted(ids - base_ids)
        d["preexisting"] = sorted(ids & base_ids)
        d["runner_enforced"] = hard[:10]
        # 2026-10-03 (diagnosis F3): all 17 baseline FAILs just echoed the runner's own QUALITY/SEMANTIC FAIL, which it already enforces (the staged
        # runner reverted/repaired those), so the FAIL carried no independent signal and polluted release_candidate. Only what THIS gate alone can
        # know - NEW failing tests vs a live baseline - may FAIL; a bare runner-enforced gate failure is NA (still listed in details).
        if cur is not None and d["new_failures"]:
            return "FAIL", "%d NEW failing test(s) vs baseline (%d pre-existing tolerated); the runner also reports: %s" % (
                len(d["new_failures"]), len(d["preexisting"]), "; ".join(hard[:1])), d
        return "NA", "runner-enforced gate failure (%s): not repeated here, the baseline gate adds no independent signal" % "; ".join(hard[:2]), d
    if not ids:
        if runner_failed:
            return "UNVERIFIED", "runner reported failure but no failing test ids could be parsed (infra/format?) - not guessing", d
        d["fixed"] = sorted(cur["failing"]) if cur else []
        return "PASS", "no failing tests", d
    if cur is None:
        why = "baseline expired (%dh old)" % int(baseline_age(bl, now) / 3600) if bl else "no baseline for repo"
        d["new_failures"] = None
        return "UNVERIFIED", "%d failing test(s) and %s - not guessing" % (len(ids), why), d
    base_ids = set(cur["failing"])
    new, pre, fixed = sorted(ids - base_ids), sorted(ids & base_ids), sorted(base_ids - ids)
    d.update(new_failures=new, preexisting=pre, fixed=fixed)
    if new:
        return "FAIL", "%d NEW failing test(s) vs baseline (%d pre-existing tolerated)" % (len(new), len(pre)), d
    sv, snote, shard = skipped_stage_check(parsed, changed_files, worktree)
    d["skipped_stages"] = list(parsed.get("skipped_stages") or [])
    d["skipped_stage_note"] = snote
    if sv:
        if shard:
            d["hard_failures"] = shard
        return sv, snote, d
    risk = overlap(pre, changed_files)
    d["masked_risk"] = risk[:10]
    if risk and strict_overlap:
        return "UNVERIFIED", "no new failures, but %d pre-existing red test(s) are in the area this change touched - cannot rule out it made them worse" % len(risk), d
    return "PASS", "no new failures (%d pre-existing red tolerated, %d fixed)%s" % (
        len(pre), len(fixed), " [RISK: %d pre-existing red overlap changed files]" % len(risk) if risk else ""), d


# ------------------------------------------------------------------------------------------------------------------- CLI
def _read(path):
    with open(path, errors="replace") as f:
        return f.read()


class _JsonArgParser(argparse.ArgumentParser):
    """CLI contract (spec hard rule 9): bad arguments must yield an UNVERIFIED JSON line and exit 0, never argparse's exit 2."""
    def error(self, message):
        raise ValueError("bad arguments: %s" % message)

    def exit(self, status=0, message=None):
        raise ValueError("bad arguments: %s" % (message or "exit"))


def _parse_args(argv):
    ap = _JsonArgParser(prog="baseline_verify.py", add_help=False, allow_abbrev=False)
    ap.add_argument("cmd", choices=["snapshot", "compare", "refresh", "show", "parse", "replay", "shadow-log"])
    ap.add_argument("--repo")
    ap.add_argument("--failing-file")
    ap.add_argument("--format", default="auto")
    ap.add_argument("--commit", default="")
    ap.add_argument("--base-sha", default="")
    ap.add_argument("--source", default="")
    ap.add_argument("--accept-growth", action="store_true")
    ap.add_argument("--runner-failed", action="store_true", help="the real runner already judged this run failed")
    ap.add_argument("--changed-file", action="append", default=[], help="file changed by the step/item (repeatable)")
    ap.add_argument("--changed-files-from", help="newline separated list of changed files")
    ap.add_argument("--strict-overlap", action="store_true", help="PASS->UNVERIFIED when a pre-existing red test overlaps changed files")
    ap.add_argument("--ref", default="origin/overnight/feature")
    ap.add_argument("--logs-dir")
    ap.add_argument("--days", type=int, default=0)
    ap.add_argument("--out")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--no-record", action="store_true")
    ap.add_argument("--result-file", help="shadow-log: the JSON line `compare --no-record` printed")
    ap.add_argument("--runner-decision", default="", help="shadow-log: what the staged runner finally decided (verified|not_verified)")
    ap.add_argument("--run", default="", help="shadow-log: staged run id")
    ap.add_argument("--label", default="", help="shadow-log: which full_verify call (first)")
    ap.add_argument("--worktree", default="", help="checkout of the change under test (lets the gate run bash -n on skipped shell stages)")
    return ap.parse_args(argv)


def _v(v, repo, ref, summary, details=None):
    return qc.verdict(v, GATE, repo or "?", ref or "", summary, details)


def _load_failing(a):
    if not a.failing_file or not os.path.isfile(a.failing_file):
        return None, "failing file missing: %s" % a.failing_file
    return parse_text(_read(a.failing_file), a.format), None


def _ancestor_note(repo, bl_commit, base_sha):
    if not (repo and bl_commit and base_sha):
        return None
    rd = qc.repo_dir(repo)
    if not rd:
        return "repo clone not found; ancestry unchecked"
    rc, _, _ = qc.git(rd, "merge-base", "--is-ancestor", bl_commit, base_sha)
    return None if rc == 0 else ("baseline commit is not an ancestor of base-sha (rc=%d); red set may have drifted" % rc)


def cmd_compare(a):
    p, err = _load_failing(a)
    if err:
        return _v("UNVERIFIED", a.repo, a.base_sha, err)
    bl = load_baseline(a.repo)
    ch = list(a.changed_file)
    if a.changed_files_from and os.path.isfile(a.changed_files_from):
        ch += [l.strip() for l in _read(a.changed_files_from).splitlines() if l.strip()]
    v, summ, det = compare_sets(p, bl, runner_failed=a.runner_failed, changed_files=ch, strict_overlap=a.strict_overlap,
                                worktree=a.worktree or None)
    if bl and a.base_sha:
        note = _ancestor_note(a.repo, bl.get("commit"), a.base_sha)
        if note:
            det["warning"] = note
    if det.get("growth"):
        summ += " [GROWTH ALERT: baseline red set grew]"
    return _v(v, a.repo, a.base_sha, summ, det)


def cmd_snapshot(a):
    p, err = _load_failing(a)
    if err:
        return _v("UNVERIFIED", a.repo, a.commit, err)
    status, info = snapshot_set(a.repo, p, a.commit, a.source or "snapshot-cli", a.accept_growth)
    if status.startswith("stored"):
        return _v("PASS", a.repo, a.commit, "baseline %s (%d red ids)" % (status, info["count"]), dict(info, status=status))
    if status == "growth_pending":
        return _v("FLAG", a.repo, a.commit, "GROWTH ALERT: %d new red ids vs active baseline; baseline NOT widened" % len(info["added"]),
                  dict(info, status=status))
    return _v("UNVERIFIED", a.repo, a.commit, "snapshot refused (%s): %s" % (status, info.get("why", "")), dict(info, status=status))


def _find_pytest(repo_path):
    """Same discovery as full_verify(): a .venv/bin/pytest within 4 levels of the repo clone."""
    base = repo_path.rstrip("/")
    cands = []
    for root, dirs, files in os.walk(base):
        depth = root[len(base):].count(os.sep)
        if depth > 3:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git")]
        if root.endswith(os.path.join(".venv", "bin")) and "pytest" in files:
            cands.append(os.path.join(root, "pytest"))
    cands.sort(key=len)
    return cands[0] if cands else None


def cmd_refresh(a):
    rd = qc.repo_dir(a.repo)
    if not rd:
        return _v("UNVERIFIED", a.repo, a.ref, "repo clone not found")
    vp = _find_pytest(rd)
    if not vp:
        return _v("NA", a.repo, a.ref, "no .venv/bin/pytest in the clone (refresh supports python/pytest repos only)")
    pkg = os.path.relpath(os.path.dirname(os.path.dirname(os.path.dirname(vp))), rd)
    rc0, sha, _ = qc.git(rd, "rev-parse", a.ref)
    with qc.worktree(rd, a.ref) as wt:
        if not wt:
            return _v("UNVERIFIED", a.repo, a.ref, "could not create worktree for %s" % a.ref)
        cwd = os.path.join(wt, pkg) if pkg != "." else wt
        if not os.path.isdir(cwd):
            return _v("NA", a.repo, a.ref, "package dir %s absent at %s" % (pkg, a.ref))
        rc, out, err = qc.run([vp, "-q", "-o", "addopts=", "-p", "no:cacheprovider"], cwd=cwd, timeout=a.timeout)
    if rc == 124:
        return _v("UNVERIFIED", a.repo, a.ref, "suite timed out after %ss; baseline not updated" % a.timeout)
    # 2026-10-02: ALWAYS prefix "[pkg] ", including "." for a repo-root venv: parse_verify_log() labels the section "-- pytest FULL in . --" and
    # prefixes its ids "[.] ", so an unprefixed refresh set would never match a single id at compare time (every red id would read as NEW).
    parsed = parse_pytest(out, prefix="[%s] " % pkg)
    status, info = snapshot_set(a.repo, parsed, sha.strip(), "deterministic:refresh", a.accept_growth)
    if status.startswith("stored"):
        return _v("PASS", a.repo, a.ref, "refreshed baseline %s (%d red ids)" % (status, info["count"]), dict(info, status=status))
    if status == "growth_pending":
        return _v("FLAG", a.repo, a.ref, "GROWTH ALERT on refresh: +%d red ids" % len(info["added"]), dict(info, status=status))
    return _v("UNVERIFIED", a.repo, a.ref, "refresh refused (%s): %s" % (status, info.get("why", "")), dict(info, status=status))


def _trim(v, n=50):
    return v[:n] if isinstance(v, list) else v


def cmd_shadow_log(a):
    """Append ONE row to state/qa_shadow/baseline.jsonl pairing the baseline verdict (the JSON `compare --no-record` printed for the
    staged runner's FIRST red full_verify, passed via --result-file) with what the runner ACTUALLY decided at the end of its verify flow
    (--runner-decision verified|not_verified; it may differ from the first call: try_regen / repair rounds can turn a red run green).
    The row is the canonical gate row (ts/gate/repo/verdict/mode/summary/details) plus: run, label, kind, runner{first,final},
    would_have_rescued (baseline says no NEW failure = verdict PASS), real_rescue (would_have_rescued AND the runner finally rejected),
    n_new/n_pre and trimmed new_failures/preexisting. Missing/unparseable result file => an UNVERIFIED row (never silence, never a guess)."""
    res, why = None, ""
    try:
        res = json.loads(_read(a.result_file))
        if not isinstance(res, dict) or res.get("verdict") not in qc.VERDICTS:
            res, why = None, "result file is not a gate verdict"
    except (OSError, ValueError, TypeError) as ex:
        why = "result file unreadable: %s" % type(ex).__name__
    final = a.runner_decision if a.runner_decision in ("verified", "not_verified") else "unknown"
    if res is None:
        row = _v("UNVERIFIED", a.repo, a.base_sha, "baseline comparison unavailable (%s) - hook error swallowed, runner unaffected" % why)
    else:
        row = dict(res)
        row["details"] = dict(res.get("details") or {})
        for k in ("new_failures", "preexisting", "fixed", "masked_risk", "hard_failures"):
            if k in row["details"]:
                row["details"][k] = _trim(row["details"][k])
    det = (res or {}).get("details") or {}
    nf, pre = det.get("new_failures"), det.get("preexisting")
    rescue = bool(res and res.get("verdict") == "PASS")
    row.update({"kind": "staged_shadow", "run": a.run, "label": a.label or "first", "runner": {"first": "not_verified", "final": final},
                "would_have_rescued": rescue, "real_rescue": rescue and final == "not_verified",
                "n_new": len(nf) if isinstance(nf, list) else None, "n_pre": len(pre) if isinstance(pre, list) else None,
                "new_failures": _trim(nf), "preexisting": _trim(pre)})
    return row


def cmd_show(a):
    bl = load_baseline(a.repo)
    if not bl:
        return _v("NA", a.repo, "", "no baseline stored")
    cur = active(bl)
    return _v("PASS", a.repo, bl.get("commit", ""), "baseline %d ids, age %dh%s" % (len(bl["failing"]), baseline_age(bl) / 3600, "" if cur else " EXPIRED"),
              {"baseline": {k: bl.get(k) for k in ("iso", "commit", "source", "parser", "count", "pending_growth", "history")},
               "failing": bl["failing"][:100], "expired": cur is None})


def cmd_parse(a):
    p, err = _load_failing(a)
    if err:
        return _v("UNVERIFIED", "?", "", err)
    return _v("PASS", "?", "", "parsed %d ids, %d hard, complete=%s" % (len(p["ids"]), len(p["hard"]), p["complete"]), p)


# ----------------------------------------------------------------------------------------------------------------- replay
_RUN_TS = re.compile(r"-(\d{8})-(\d{6})-\d+")


def _run_ts(name):
    m = _RUN_TS.search(name)
    return time.mktime(time.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")) if m else None


def _norm_item(s):
    return re.sub(r"\s+", " ", (s or ""))[:140]


def load_runs(logs_dir):
    runs = []
    for jf in glob.glob(os.path.join(logs_dir, "*.jsonl")):
        base = os.path.basename(jf)[:-6]
        verified, item, tier, files = None, "", None, set()
        try:
            for l in open(jf, errors="replace"):
                try:
                    e = json.loads(l)
                except ValueError:
                    continue
                if e.get("event") == "verify":
                    verified = e.get("verified")
                elif e.get("event") == "decomposed" and not item:
                    item, tier = e.get("item", ""), e.get("tier")
                    for st in e.get("plan") or []:
                        fl = st.get("files") or []
                        files |= set(fl.split() if isinstance(fl, str) else fl)
                    files |= set(re.findall(r"[\w./\-]+\.(?:py|kt|java|ts|tsx|vue|gd|js|swift|sh)\b", item))
                elif e.get("step") is not None and e.get("files"):
                    fl = e["files"]
                    files |= set(fl.split() if isinstance(fl, str) else fl)
        except OSError:
            continue
        if verified is None:
            continue
        ts = _run_ts(base)
        if ts is None:
            continue
        repo = base.split("-20")[0]
        lf = os.path.join(logs_dir, base + ".verify.log")
        runs.append({"name": base, "repo": repo, "ts": ts, "verified": bool(verified), "item": _norm_item(item), "tier": tier, "files": sorted(files),
                     "log": lf if os.path.isfile(lf) else None})
    runs.sort(key=lambda r: (r["repo"], r["ts"]))
    return runs


def _mk_bl(ids, ts, window_s):
    return {"failing": sorted(ids), "ts": ts, "ttl_s": window_s, "commit": "", "history": []} if ids else None


def replay(logs_dir, days=0, window_s=86400):
    """Estimate how many historical failed staged verifies baseline-relative verify would have rescued.
    No clean-base re-run exists in the logs, so 'pre-existing' is PROXIED by the same test id failing in OTHER items' runs of the
    same repo within 24h with no green (verified) run of that repo in between (a green run proves the suite was green then):
      A = failed in >=1 earlier other-item run          (what a baseline taken from the previous failed run would hold)
      B = failed in >=2 distinct earlier other items    (high confidence)
      C = failed in >=1 other-item run before OR after  (adds 'the next run fails the same id too' = base was already red)
    Each run is judged by the real compare_sets() with an in-memory baseline built from the proxy."""
    runs = load_runs(logs_dir)
    cutoff = (max((r["ts"] for r in runs), default=0) - days * 86400) if days else 0
    out = {"runs_total": 0, "verified_true": 0, "verified_false": 0, "never_reached_full_verify": 0, "classes": collections.Counter(),
           "by_repo": {}, "proxy_A": collections.Counter(), "proxy_B": collections.Counter(), "proxy_C": collections.Counter(),
           "samples": {"A_rescued": [], "C_rescued": [], "A_partial": []}}
    idfreq = collections.Counter()
    by_repo = collections.defaultdict(list)
    for r in runs:
        by_repo[r["repo"]].append(r)
    for repo, rs in by_repo.items():
        for r in rs:
            r["p"] = parse_verify_log(_read(r["log"])) if (r["log"] and not r["verified"]) else None
        rb = out["by_repo"].setdefault(repo, collections.Counter())
        for i, r in enumerate(rs):
            if r["ts"] < cutoff:
                continue
            out["runs_total"] += 1
            if r["verified"]:
                out["verified_true"] += 1
                continue
            out["verified_false"] += 1
            rb["failed"] += 1
            if r["p"] is None:
                out["never_reached_full_verify"] += 1
                rb["never_reached_full_verify"] += 1
                continue
            p = r["p"]
            ids = set(p["ids"])

            def neighbours(direction):
                res = []
                j = i + direction
                while 0 <= j < len(rs) and abs(rs[j]["ts"] - r["ts"]) <= window_s:
                    o = rs[j]
                    if o["verified"]:
                        break  # green run: suite was green, nothing earlier/later is evidence
                    if o["p"] and o["p"]["complete"] and o["item"] != r["item"]:
                        res.append((o["item"], set(o["p"]["ids"])))
                    j += direction
                return res
            prev, nxt = neighbours(-1), neighbours(+1)
            union = lambda L: set().union(*[x for _, x in L]) if L else set()  # noqa: E731
            cnt = collections.defaultdict(set)
            for it, x in prev:
                for t in x:
                    cnt[t].add(it)
            bases = {"A": union(prev), "B": {t for t, its in cnt.items() if len(its) >= 2}, "C": union(prev) | union(nxt)}
            if not p["complete"]:
                cls = "incomplete_log"
            elif p["hard"] and not ids:
                cls = "gate_fail_only_quality_semantic_other"
            elif p["hard"]:
                cls = "gate_fail_plus_test_fail"
            elif not ids:
                cls = "no_parsed_failure"
            else:
                cls = "test_failures_only"
            out["classes"][cls] += 1
            rb[cls] += 1
            if ids:
                for t in ids:
                    idfreq[t] += 1
            if cls in ("test_failures_only", "gate_fail_plus_test_fail"):
                for tag in "ABC":
                    v, _, d = compare_sets(p, _mk_bl(bases[tag], r["ts"], window_s), runner_failed=True, now=r["ts"], changed_files=r["files"])
                    out["proxy_" + tag][cls + ":" + v] += 1
                    if cls == "test_failures_only":
                        if v == "PASS":
                            out["proxy_" + tag]["PASS_with_overlap_risk" if d.get("masked_risk") else "PASS_clean_no_overlap"] += 1
                        rb["rescued_" + tag] += v == "PASS"
                        if v == "PASS" and tag in "AC" and len(out["samples"][tag + "_rescued"]) < 60:
                            out["samples"][tag + "_rescued"].append({"run": r["name"], "item": r["item"][:90], "n": len(ids), "pre": d["preexisting"][:3], "risk": d.get("masked_risk", [])[:2]})
                        if tag == "A" and v == "FAIL" and d["preexisting"] and len(out["samples"]["A_partial"]) < 30:
                            out["samples"]["A_partial"].append({"run": r["name"], "new": d["new_failures"][:3], "pre_n": len(d["preexisting"])})
    out["top_recurring_ids"] = idfreq.most_common(15)
    for k in ("classes", "proxy_A", "proxy_B", "proxy_C"):
        out[k] = dict(out[k])
    out["by_repo"] = {k: dict(v) for k, v in out["by_repo"].items()}
    return out


def cmd_replay(a):
    if not a.logs_dir or not os.path.isdir(a.logs_dir):
        return _v("UNVERIFIED", "?", "", "--logs-dir missing")
    t0 = time.time()
    res = replay(a.logs_dir, a.days)
    res["replay_s"] = round(time.time() - t0, 1)
    if a.out:
        with open(a.out, "w") as f:
            json.dump(res, f, indent=1, sort_keys=True)
    res_small = dict(res)
    res_small["samples"] = {k: v[:5] for k, v in res["samples"].items()}
    A, C = res["proxy_A"], res["proxy_C"]
    return _v("PASS", "*", "", "replay: %d not-verified runs (%d reached full_verify); rescued A=%d C=%d" % (
        res["verified_false"], res["verified_false"] - res["never_reached_full_verify"], A.get("test_failures_only:PASS", 0),
        C.get("test_failures_only:PASS", 0)), res_small)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)

    def fn(av):
        a = _parse_args(av)
        if a.cmd in ("snapshot", "compare", "refresh", "show", "shadow-log"):
            if not a.repo:
                return _v("UNVERIFIED", "?", "", "--repo required")
            _safe_repo(a.repo)
        return {"snapshot": cmd_snapshot, "compare": cmd_compare, "refresh": cmd_refresh, "show": cmd_show, "parse": cmd_parse,
                "replay": cmd_replay, "shadow-log": cmd_shadow_log}[a.cmd](a)
    if argv[:1] == ["shadow-log"] and qc.mode(GATE) == "off":
        argv.append("--no-record")  # mode=off (qa_mode.sh rollback): compute nothing durable, write no row
    return qc.main_guard(GATE, fn, argv)


if __name__ == "__main__":
    sys.exit(main())
