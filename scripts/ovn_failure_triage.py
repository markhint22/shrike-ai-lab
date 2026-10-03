#!/usr/bin/env python3
"""ovn_failure_triage.py — Phase 6c+6d (pipeline-hardening plan): surface NEW classes of
failure on its own, instead of requiring a human/agent to manually grep state/outcomes.jsonl
and per-cycle logs by hand (the way all ~30 bugs found over the prior 2 days were actually
found — hours-to-days after the fact, at huge token cost, purely because someone decided to
go looking). Nothing in the pipeline previously did this proactively. This closes that gap.

DESIGN (matches the incremental-cursor pattern already proven in
ovn_derive_legacy_logs.py — read that file first if this one is unclear):

  1. Read new BAD-bucket records from state/outcomes.jsonl since the last run, using a
     byte-offset cursor (state/.failure_triage.cursor) so re-runs only process NEW records —
     safe to run frequently (cron) without reprocessing history. "BAD" is the canonical
     definition in ovn_outcome_buckets.py (imported, not reimplemented): revert, noop:gate,
     noop:flail — NOT benign skips/already-dones, NOT plain errors.

  2. For each new BAD record, correlate it to its cycle log (logs/<run-ts>/<id>.log) and pull
     a short, normalized error SIGNATURE out of it via an ordered list of (extractor) checks —
     see EXTRACTORS below. The run-ts directory name is LOCAL time (run_overnight.sh's
     `date +%Y%m%d-%H%M%S` at cycle start); outcomes.jsonl's `ts` is UTC, written partway
     through that same cycle (record_outcome() fires after the repo's attempt+verify finish).
     So: convert the record's ts to a true Unix epoch, and find the run-dir with the LARGEST
     start-epoch that is still <= the record's epoch and actually has a <id>.log file
     (walking backward a bounded number of candidates in case that exact cycle didn't happen
     to touch this repo). This was verified against real live data on the GPU box
     (2026-09-29): an iptv_apps reverted(migration-fork) record at ts=20:42:24Z correctly
     resolved to logs/20260929-152602/ongoing-iptv-apps.log (mtime 15:42 local), the run-dir
     immediately preceding it, and a gitlark reverted(build-break) record resolved the same
     way to logs/20260929-140351/ongoing-gitlark.log's real vite/vue build error.
     This ONLY produces correct results when run on the same box/timezone that wrote the
     logs (the GPU box) — documented limitation, not a bug. If no log can be found within
     the lookback window, this still produces a coarse-but-real signature from the record's
     own fail_reason/status fields (already classified once by ovn_classify_fail.sh at write
     time) rather than giving up — see the "no-log:" fallback.

  3. Maintain a registry at state/failure_clusters.json keyed "<repo>::<signature>". Each
     new-shape event creates a "new" entry; a repeat bumps count/last_seen (and appends a
     capped rolling sample of item_hashes so a human can go look at real examples, not just a
     count). The single highest-value signal this tool exists to produce: if an event matches
     a signature whose registry status is "fixed", that's a CONFIRMED REGRESSION of something
     believed resolved — flagged loudly in the detection-pass output, every time it recurs
     (status intentionally stays "fixed" rather than auto-flipping back to "new" — a human
     re-closes it via --ack once actually re-fixed, same discipline as the first fix).
     DEVIATION from the literal spec: an additional "regression_events" list (capped at 10) is
     kept on entries that have regressed, purely as an audit trail — the 3-value status enum
     (new/acknowledged/fixed) from the spec is otherwise honored exactly as written; this
     script never writes "acknowledged" itself (no described trigger reaches it — left as a
     valid manual value for a future human/agent workflow).

  3b. (2026-10-03) Two NON-outcomes sources feed the same registry: FAILED deploys read from
     state/staging_deploys/*.json + state/deploy_status*.json (signature `deploy-failed:<env>`),
     and `landed` rows with no commit behind them from state/qa_ledger.jsonl (signature
     `landed-without-commit`). Same --ack / fixed-cluster-regression semantics as everything else.
  4. CLI: default invocation runs the detection pass and prints a short summary. `--ack <repo>
     <signature-or-partial> --commit <hash> --generator-addressed <yes|no|unsure>` transitions
     a cluster to "fixed" — supports fuzzy/partial signature matching, always prints the full
     matched entry before applying, and refuses to apply in a non-interactive shell without an
     explicit --yes (so a scripted caller can't silently apply the wrong match, but a human
     confirms once interactively without needing to type the whole key).

  5. Pure observability. Does not block, revert, or modify anything else in the pipeline.

Usage:
  ovn_failure_triage.py [state_dir] [logs_dir]                          (detection pass)
  ovn_failure_triage.py [state_dir] [logs_dir] --ack REPO SIG_PARTIAL \\
      --commit <hash> --generator-addressed <yes|no|unsure> [--yes]     (ack a fix)
"""
import argparse
import bisect
import glob
import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ovn_outcome_buckets as buckets  # noqa: E402  (see module docstring — the ONE canonical classifier)

STATE_DIR_DEFAULT = "state"
LOGS_DIR_DEFAULT = "logs"


def _cursor_path(state_dir):
    return os.path.join(state_dir, ".failure_triage.cursor")


def _registry_path(state_dir):
    return os.path.join(state_dir, "failure_clusters.json")


def _outcomes_path(state_dir):
    return os.path.join(state_dir, "outcomes.jsonl")


# ---------------------------------------------------------------------------
# registry I/O
# ---------------------------------------------------------------------------

def load_registry(state_dir):
    path = _registry_path(state_dir)
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def save_registry(state_dir, registry):
    path = _registry_path(state_dir)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(registry, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# log-dir correlation (see module docstring, point 2)
# ---------------------------------------------------------------------------

_RUN_DIR_RE = re.compile(r'^\d{8}-\d{6}$')


def _build_run_dir_index(logs_dir):
    """[(start_epoch, dirname), ...] sorted ascending. start_epoch is computed by
    interpreting the dir's LOCAL-time-formatted name via time.mktime — correct only when
    run on the same box/timezone that named it (the GPU box); see module docstring."""
    out = []
    try:
        names = os.listdir(logs_dir)
    except Exception:
        return out
    for name in names:
        if not _RUN_DIR_RE.match(name):
            continue
        try:
            epoch = time.mktime(time.strptime(name, "%Y%m%d-%H%M%S"))
        except Exception:
            continue
        out.append((epoch, name))
    out.sort()
    return out


def _epoch_of_ts(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def find_task_log(logs_dir, run_dir_index, record_id, record_epoch,
                   max_lookback_s=3 * 3600, max_candidates=40):
    """Find the logs/<run-ts>/<id>.log that most likely produced this outcomes.jsonl record.
    Walks backward from the run-dir with the largest start-epoch <= record_epoch, in case
    that exact cycle didn't touch this repo (concurrent higher-tier sub-flows, etc.), bounded
    by max_lookback_s / max_candidates so a service-restart gap doesn't walk arbitrarily far
    back and attribute a signature to the wrong cycle's log."""
    if record_epoch is None or not run_dir_index:
        return None
    epochs = [e for e, _ in run_dir_index]
    idx = bisect.bisect_right(epochs, record_epoch) - 1
    tried = 0
    while idx >= 0 and tried < max_candidates:
        epoch, name = run_dir_index[idx]
        if record_epoch - epoch > max_lookback_s:
            break
        cand = os.path.join(logs_dir, name, "%s.log" % record_id)
        if os.path.exists(cand):
            return cand
        idx -= 1
        tried += 1
    return None


def _read_tail(path, max_bytes=40000):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - max_bytes))
            data = f.read()
        return data.decode("utf-8", errors="replace")
    except Exception:
        return ""


# ---------------------------------------------------------------------------
# normalization + extractors
# ---------------------------------------------------------------------------

def normalize(s):
    """Strip volatile specifics (hashes, paths, numbers, quoted literals) so two
    occurrences of the SAME underlying failure shape collapse to one signature."""
    s = re.sub(r'\b[0-9a-f]{7,40}\b', '<HASH>', s)
    s = re.sub(r'(?:/[\w.\-]+){2,}', '<PATH>', s)
    s = re.sub(r"'[^']{1,80}'", "'<X>'", s)
    s = re.sub(r'"[^"]{1,80}"', '"<X>"', s)
    s = re.sub(r'\b\d+\b', '#', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s[:300]


def _last_match(pattern, text, flags=re.MULTILINE):
    matches = list(re.finditer(pattern, text, flags))
    return matches[-1] if matches else None


def _ex_aider(text):
    """Aider-mechanical failures (diff/patch application), not a code-quality signal."""
    if 'is not in the subpath' in text:
        return ("aider", "is-not-in-subpath")
    if re.search(r'hunk (failed to apply|FAILED)', text, re.IGNORECASE):
        return ("aider", "hunk-failed-to-apply")
    if 'SearchReplaceNoExactMatch' in text or 'UnifiedDiffNoMatch' in text:
        return ("aider", "diff-no-exact-match")
    return None


def _ex_kotlin(text):
    m = _last_match(r"No parameter with name '([^']+)' found", text)
    if m:
        return ("kotlin", "no-param-found:<X>")
    m = _last_match(r'^FAILURE: (.+)$', text)
    if m:
        return ("gradle", normalize(m.group(1)))
    return None


def _ex_gdscript(text):
    m = _last_match(r'^.*SCRIPT ERROR:.*$', text)
    if m:
        return ("gdscript", normalize(m.group(0)))
    return None


def _ex_pytest_summary(text):
    """Checked BEFORE _ex_js: pytest's "short test summary info" line
    (`FAILED tests/foo.py::test_bar - AssertionError: ...`) also contains the literal
    text "AssertionError:" that _ex_js's generic catch-all would otherwise match first
    (found while writing this file's own test suite) — this is deliberately narrower
    (requires a `.py` path + `::`) so a real pytest failure is never misclassified as a
    JS one just because both frameworks use the word "AssertionError"."""
    m = _last_match(r'^FAILED (\S+\.py::\S+) - (.*)$', text)
    if m:
        return ("python", "pytest-failed:%s %s" % (normalize(m.group(1)), normalize(m.group(2))))
    return None


def _ex_js(text):
    m = _last_match(r'^\s*(?:FAIL|✕|×)\s+(.+)$', text)
    if m:
        return ("js", normalize(m.group(1)))
    m = _last_match(r'\[plugin [^\]]+\][^\n]*', text)
    if m:
        return ("js", normalize(m.group(0)))
    m = _last_match(r'AssertionError:.*', text)
    if m:
        return ("js", normalize(m.group(0)))
    return None


def _ex_python(text):
    m = _last_match(r'^FAILED (\S+) - (.*)$', text)
    if m:
        return ("python", "pytest-failed:%s %s" % (normalize(m.group(1)), normalize(m.group(2))))
    m = _last_match(r'^([A-Za-z_][\w.]*(?:Error|Exception)):\s*(.*)$', text)
    if m:
        return ("python", "%s: %s" % (m.group(1), normalize(m.group(2))))
    return None


# The pipeline's OWN terminal verdict lines, written into every cycle log by run_overnight.sh /
# ovn_stage_runner.sh. These are the most reliable failure signatures available: the pipeline
# itself states why the cycle ended. Found 2026-09-29 by sampling the logs behind the 70% of
# first-run failures that fell through to the generic fallback (which used to DROP every "---"
# annotation line as noise, i.e. it discarded exactly these). The label is what a person reads in
# the digest, so it is plain language, not an internal code. Order does not matter for priority —
# the marker whose LAST occurrence is latest in the log wins (the last verdict is what actually
# ended the cycle); the list order only breaks exact-position ties.
PIPELINE_MARKERS = [
    (r'BUILD-GATE: commit structurally broke the build',
     "build-gate: the commit broke the build (code would not load/compile)"),
    (r'NO-NEW-RED GUARD: commit left the suite red \(a source change broke a previously-green test\)',
     "tests-red: the change broke a test that used to pass"),
    (r'NO-NEW-RED GUARD: commit left the suite red \(the model added failing tests\)',
     "tests-red: the new tests the model wrote fail"),
    (r'NO-NEW-RED GUARD: commit left the suite red',
     "tests-red: the commit left the test suite red"),
    (r'MIGRATION-SAFETY GATE: commit forked/broke the Alembic migration chain',
     "migration-gate: the commit forked or broke the database-migration chain"),
    (r'decompose produced no steps',
     "decompose: could not split the item into steps"),
    (r'regression-check FAILED',
     "capstone: the full-suite regression check found a real failure"),
    (r'escalated to Claude \(staged pipeline landed',
     "staged: gave up and escalated to Claude (beyond the local model)"),
    (r'independent full-verify: FAILED',
     "staged: the independent full verify failed, so nothing was pushed"),
    (r'step \d+ failing after \d+ .{0,6}re-decomposing smaller',
     "staged: a step kept failing and was re-split smaller"),
    (r'Tier-\d fix-up re-verify: fail',
     "fix-up: the repair attempt still fails"),
    (r'Tier-\d fix-up made no change',
     "fix-up: the repair attempt changed nothing"),
    (r'verify FAILED .{0,6}repair round',
     "verify: failed, repair rounds used up"),
    (r'discarding uncommitted working-tree residue',
     "residue: discarded leftovers from an incomplete attempt"),
    (r'scout verdict=ALREADY-DONE',
     "scout: already done (no attempt was made)"),
    (r'no doable T3\+ item found',
     "staged: no doable higher-tier item was found"),
    (r'named zero file-shaped tokens',
     "scout: made up a plan that names no real file"),
]
_PIPELINE_MARKERS_RE = [(re.compile(rx), label) for rx, label in PIPELINE_MARKERS]


def _ex_pipeline(text):
    """Signature from the pipeline's own terminal verdict line (see PIPELINE_MARKERS)."""
    best_pos, best_label = -1, None
    for rx, label in _PIPELINE_MARKERS_RE:
        last = None
        for last in rx.finditer(text):
            pass
        if last is not None and last.start() > best_pos:
            best_pos, best_label = last.start(), label
    if best_label:
        return ("pipeline", best_label)
    return None


def _ex_fallback(text):
    """Coarse-but-real fallback: hash the NORMALIZED last few non-empty, non-pipeline-
    annotation lines of the log tail. Never fails to produce SOME signature.

    2026-09-29: each line is passed through normalize() first (and pure aider token-
    accounting lines are dropped). The original version hashed the RAW last 5 lines, which
    almost never repeat between two occurrences of the same failure shape (differing
    counts, paths, hashes, quoted names) — so nearly every unclassifiable failure became its
    own brand-new cluster, defeating the whole point of clustering and flooding the digest
    with "new signature" noise. Normalizing collapses those specifics the same way every
    other extractor already does."""
    lines = [ln.strip() for ln in text.splitlines()
             if ln.strip() and not ln.strip().startswith('---') and not ln.strip().startswith('Tokens:')]
    tail = [normalize(ln)[:120] for ln in lines[-3:]] if lines else ["<empty-log>"]
    joined = " | ".join(tail)
    h = hashlib.md5(joined.encode('utf-8', errors='replace')).hexdigest()[:12]
    return ("generic", "tail-hash:%s" % h)


# Ordered, first-match-wins (see module docstring). Easy to extend: append a new
# (regex/literal-check, normalizer) function here as new failure shapes get characterized.
EXTRACTORS = [_ex_pytest_summary, _ex_aider, _ex_kotlin, _ex_gdscript, _ex_js, _ex_python,
              _ex_pipeline, _ex_fallback]


def _status_signature(rec):
    """Signature derived from the outcome RECORD rather than the log text — used only when the
    log yields nothing better than the generic fallback. A bare "no-op" status means the model
    attempted the item and produced no usable change (the "flail" bucket); its log just ends in
    the model's own varying prose (plus "CREDITED=0"), which can never be clustered by text —
    2026-09-29: 362 of the 387 events still unclassified after the pipeline-marker extractor
    were exactly this. One cluster per repo says the useful thing ("N flails") instead of
    hundreds of one-off hashes."""
    st = (rec.get("status") or "").strip()
    if st == "no-op":
        return "pipeline:flail: the model attempted it but produced no usable change"
    return None


def extract_signature(text):
    for ex in EXTRACTORS:
        result = ex(text)
        if result:
            tag, sig = result
            return "%s:%s" % (tag, sig)
    # unreachable — _ex_fallback always matches — kept as a defensive last resort.
    return "generic:no-signature"


# ---------------------------------------------------------------------------
# detection pass
# ---------------------------------------------------------------------------

def _upsert_cluster(registry, repo, sig, ts, item_hash, new_clusters, regressions):
    """Create/refresh one cluster in the registry (shared by the outcomes pass and the
    deploy-failure / landed-without-commit passes, so ALL of them get identical --ack and
    fixed-cluster-regression semantics)."""
    key = "%s::%s" % (repo, sig)
    entry = registry.get(key)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if entry is None:
        entry = {
            "first_seen": ts or now_iso,
            "last_seen": ts or now_iso,
            "count": 1,
            "status": "new",
            "fix_commit": None,
            "generator_addressed": None,
            "sample_item_hashes": [item_hash] if item_hash else [],
        }
        registry[key] = entry
        new_clusters.append({"repo": repo, "signature": sig, "key": key})
    else:
        entry["last_seen"] = ts or now_iso
        entry["count"] = entry.get("count", 0) + 1
        if item_hash:
            samples = entry.setdefault("sample_item_hashes", [])
            if item_hash not in samples:
                samples.append(item_hash)
            entry["sample_item_hashes"] = samples[-5:]
        if entry.get("status") == "fixed":
            events = entry.setdefault("regression_events", [])
            events.append({"ts": ts, "item_hash": item_hash})
            entry["regression_events"] = events[-10:]
            regressions.append({
                "repo": repo, "signature": sig, "key": key,
                "fix_commit": entry.get("fix_commit"), "count": entry["count"],
            })


# ---------------------------------------------------------------------------
# non-outcomes sources (2026-10-03, Phase 6 observability): failures that never show up as a BAD
# outcomes.jsonl row but cost the most. (a) a Railway/Vercel/Fly deploy that FAILED, (b) a
# `landed` outcome that has no commit behind it (phantom landing). Both feed the SAME registry,
# so --ack / fixed-cluster-regression behave exactly as for log-derived clusters.
# ---------------------------------------------------------------------------

# COVERAGE NOTE: staging deploys only (state/staging_deploys/, billwatch/gitlark/iptv_apps). Prod
# is read from state/deploy_status*.json, which nothing writes yet - prod deploy failures (e.g. the
# 2026-10-03 Chickadee one) are NOT clustered until a prod exporter feeds that shape.
DEPLOY_FAIL_STATUSES = frozenset({"FAILED", "CRASHED", "BUILD_FAILED", "ERROR", "ERRORED", "FAILURE"})
LANDED_NO_COMMIT_SIG = "landed-without-commit"


def _deploy_seen_path(state_dir):
    return os.path.join(state_dir, ".failure_triage_deploys_seen.json")


def _iter_deploy_records(state_dir):
    """Yield (repo, env, deploy_id, status, created_at, commit) from every exported deploy-state
    file we know of: state/staging_deploys/*.json ({repo, deployments:[{id,status,createdAt,
    meta:{commitHash}}]}) and state/deploy_status*.json (same shape, or a bare list of such
    deployments, or a {repo: [...]} map). Missing/garbled files are skipped, never fatal."""
    paths = []
    sd = os.path.join(state_dir, "staging_deploys")
    if os.path.isdir(sd):
        paths += [("staging", p) for p in sorted(glob.glob(os.path.join(sd, "*.json")))]
    paths += [("prod", p) for p in sorted(glob.glob(os.path.join(state_dir, "deploy_status*.json")))]
    for env, path in paths:
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            continue
        base = os.path.splitext(os.path.basename(path))[0]
        groups = []
        if isinstance(data, dict) and isinstance(data.get("deployments"), list):
            groups.append((data.get("repo") or base, data["deployments"]))
        elif isinstance(data, list):
            groups.append((base, data))
        elif isinstance(data, dict):
            for k, v in data.items():
                if isinstance(v, list):
                    groups.append((k, v))
                elif isinstance(v, dict) and isinstance(v.get("deployments"), list):
                    groups.append((v.get("repo") or k, v["deployments"]))
        for repo, deps in groups:
            for d in deps:
                if not isinstance(d, dict):
                    continue
                meta = d.get("meta") if isinstance(d.get("meta"), dict) else {}
                yield (str(repo), env, str(d.get("id") or ""), str(d.get("status") or "").upper(),
                       str(d.get("createdAt") or d.get("created_at") or ""),
                       str(meta.get("commitHash") or d.get("commit") or ""))


def seed_cursors(state_dir):
    """Install-time seeding so the first run does not report history as NEW: ledger cursor =
    current qa_ledger size, deploy seen-file = every FAILED deploy id in the current files.
    (Prod deploys are only covered if something writes state/deploy_status*.json; nothing in the
    queue does today, so prod deploy failures are NOT clustered - staging only.)"""
    lp = os.path.join(state_dir, "qa_ledger.jsonl")
    if os.path.exists(lp):
        with open(os.path.join(state_dir, ".failure_triage_ledger.cursor"), "w") as f:
            f.write(str(os.path.getsize(lp)))
    seen = {}
    for repo, env, did, status, created, commit in _iter_deploy_records(state_dir):
        if status in DEPLOY_FAIL_STATUSES and did:
            seen[did] = created or "?"
    with open(_deploy_seen_path(state_dir), "w") as f:
        json.dump(seen, f, sort_keys=True)
    return len(seen)


def process_deploy_failures(state_dir, registry, new_clusters, regressions):
    """Cluster each NEWLY seen FAILED deploy (deploy id remembered in a seen-file so a re-run
    counts it once) as `<repo>::deploy-failed:<env>`. Returns the number of new failures."""
    try:
        with open(_deploy_seen_path(state_dir)) as f:
            seen = json.load(f)
        if not isinstance(seen, dict):
            seen = {}
    except Exception:
        seen = {}
    n = 0
    for repo, env, did, status, created, commit in _iter_deploy_records(state_dir):
        if status not in DEPLOY_FAIL_STATUSES or not did or did in seen:
            continue
        seen[did] = created or "?"
        n += 1
        _upsert_cluster(registry, repo, "deploy-failed:%s" % env, created, commit[:8], new_clusters, regressions)
    if n or not os.path.exists(_deploy_seen_path(state_dir)):
        # keep the newest 500 ids so the file stays bounded
        if len(seen) > 500:
            seen = dict(sorted(seen.items(), key=lambda kv: kv[1])[-500:])
        try:
            tmp = _deploy_seen_path(state_dir) + ".tmp"
            with open(tmp, "w") as f:
                json.dump(seen, f, sort_keys=True)
            os.replace(tmp, _deploy_seen_path(state_dir))
        except OSError:
            pass
    return n


def process_landed_without_commit(state_dir, registry, new_clusters, regressions):
    """Cluster `landed` rows of state/qa_ledger.jsonl whose commit lookup came back empty
    (commit_basis == "none": the repo clone was found, and NO commit exists in the cycle's
    window). outcomes.jsonl itself carries no sha, so the ledger (qa_ledger.py) is the only
    place this fact is recorded. "no-clone" is NOT counted: that is 'could not look', not 'looked
    and found nothing'. Byte-offset cursor; an unterminated trailing line is left for next run."""
    path = os.path.join(state_dir, "qa_ledger.jsonl")
    cur_path = os.path.join(state_dir, ".failure_triage_ledger.cursor")
    if not os.path.exists(path):
        return 0
    try:
        with open(cur_path) as f:
            start = int(f.read().strip() or "0")
    except Exception:
        start = 0
    n = 0
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        if start > end:
            start = 0
        f.seek(start)
        pos = start
        for raw in f:
            if not raw.endswith(b"\n"):
                break
            pos += len(raw)
            try:
                rec = json.loads(raw.decode("utf-8", errors="replace"))
            except Exception:
                continue
            if not isinstance(rec, dict) or rec.get("kind") != "landed":
                continue
            if rec.get("commit_basis") != "none" or rec.get("commits"):
                continue
            # stage(higher-tier) rows are a handoff to the stage runner: no commit expected
            if not str(rec.get("status") or "").startswith("pushed"):
                continue
            n += 1
            _upsert_cluster(registry, rec.get("repo") or "?", LANDED_NO_COMMIT_SIG,
                            rec.get("ts") or "", rec.get("item_hash") or "", new_clusters, regressions)
    try:
        with open(cur_path, "w") as f:
            f.write(str(pos))
    except OSError:
        pass
    return n


def _extra_sources(state_dir, registry, new_clusters, regressions):
    """Run the non-outcomes sources; each is isolated so one broken source can't kill the pass."""
    n = 0
    for fn in (process_deploy_failures, process_landed_without_commit):
        try:
            n += fn(state_dir, registry, new_clusters, regressions)
        except Exception as e:  # pure observability: never raise
            print("warning: %s failed: %s" % (fn.__name__, e), file=sys.stderr)
    return n


def process_new_records(state_dir, logs_dir):
    outcomes_path = _outcomes_path(state_dir)
    cursor_path = _cursor_path(state_dir)
    if not os.path.exists(outcomes_path):
        registry = load_registry(state_dir)
        nc, rg = [], []
        extra = _extra_sources(state_dir, registry, nc, rg)
        if extra:
            save_registry(state_dir, registry)
        return {"new_clusters": nc, "regressions": rg, "processed": extra}

    start_offset = 0
    if os.path.exists(cursor_path):
        try:
            with open(cursor_path) as f:
                start_offset = int(f.read().strip() or "0")
        except Exception:
            start_offset = 0

    registry = load_registry(state_dir)
    run_dir_index = _build_run_dir_index(logs_dir)

    new_clusters = []
    regressions = []
    n = 0

    with open(outcomes_path, "rb") as f:
        f.seek(0, os.SEEK_END)
        end_offset = f.tell()
        if start_offset > end_offset:
            start_offset = 0  # file was rotated/truncated — restart from the top
        f.seek(start_offset)
        for raw in f:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            n += 1
            if buckets.bucket_from_outcome_row(rec) != "bad":
                continue

            repo = rec.get("repo") or "?"
            record_id = rec.get("id") or "?"
            item_hash = rec.get("item_hash") or ""
            ts = rec.get("ts") or ""
            record_epoch = _epoch_of_ts(ts)
            log_path = find_task_log(logs_dir, run_dir_index, record_id, record_epoch) if record_epoch else None
            if log_path:
                sig = extract_signature(_read_tail(log_path))
                if sig.startswith("generic:"):
                    sig = _status_signature(rec) or sig
            else:
                fr = rec.get("fail_reason") or "?"
                st = normalize(rec.get("status") or "?")
                sig = "no-log:fail_reason=%s;status=%s" % (fr, st)

            _upsert_cluster(registry, repo, sig, ts, item_hash, new_clusters, regressions)
        end_offset = f.tell()

    with open(cursor_path, "w") as f:
        f.write(str(end_offset))

    n += _extra_sources(state_dir, registry, new_clusters, regressions)
    save_registry(state_dir, registry)
    return {"new_clusters": new_clusters, "regressions": regressions, "processed": n}


def _short_sig(sig, maxlen=90):
    return sig if len(sig) <= maxlen else sig[:maxlen - 1] + "…"


def cmd_digest(args):
    """Read-only window summary for digest_notify.sh (the 3-hourly rollup) — deliberately
    does NOT re-run the detection pass (that's the hourly cron's job; see this script's
    module docstring). Prints two line shapes digest_notify.sh greps for:
      NEW: <repo> :: <signature> (x<count>)          — folded into the routine digest body
      REGRESSION: <repo> :: <signature> (...)         — fires a SEPARATE, high-priority push
    A cluster only counts as "NEW" for a window if it was actually first created inside it
    (first_seen in-window) — an old, still-recurring "new" cluster nobody has acked yet
    isn't re-announced every 3h forever, only once, the window it was born in."""
    registry = load_registry(args.state_dir)
    now_epoch = datetime.now(timezone.utc).timestamp()
    window_start = now_epoch - args.digest * 3600.0
    new_lines = []
    regression_lines = []
    for key, entry in registry.items():
        repo, sig = key.split("::", 1)
        fs = _epoch_of_ts(entry.get("first_seen") or "")
        if fs is not None and fs >= window_start:
            new_lines.append((repo, sig, entry.get("count", 1)))
        hit = False
        for ev in entry.get("regression_events", []) or []:
            ev_epoch = _epoch_of_ts(ev.get("ts") or "")
            if ev_epoch is not None and ev_epoch >= window_start:
                hit = True
                break
        if hit:
            regression_lines.append((repo, sig, entry.get("fix_commit"), entry.get("count", 1)))

    for repo, sig, count in sorted(new_lines):
        print("NEW: %s :: %s (x%d)" % (repo, _short_sig(sig), count))
    for repo, sig, commit, count in sorted(regression_lines):
        print("REGRESSION: %s :: %s (previously fixed by %s, now seen %dx total)"
              % (repo, _short_sig(sig), commit, count))
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_detect(args):
    result = process_new_records(args.state_dir, args.logs_dir)
    if result["processed"] == 0:
        print("no new outcomes.jsonl records since last run")
        return 0
    print("processed %d new record(s)" % result["processed"])
    if result["new_clusters"]:
        print("%d new failure cluster(s) this run:" % len(result["new_clusters"]))
        for c in result["new_clusters"]:
            print("  NEW  %s :: %s" % (c["repo"], c["signature"]))
    if result["regressions"]:
        print("%d FIXED-CLUSTER REGRESSION(S) this run — something believed resolved recurred:"
              % len(result["regressions"]))
        for r in result["regressions"]:
            print("  REGRESSION  %s :: %s (previously fixed by %s, now seen %dx total)"
                  % (r["repo"], r["signature"], r["fix_commit"], r["count"]))
    if not result["new_clusters"] and not result["regressions"]:
        print("no new clusters, no regressions")
    return 0


def cmd_ack(args):
    registry = load_registry(args.state_dir)
    repo, partial = args.ack
    prefix = "%s::" % repo
    partial_lower = partial.lower()
    matches = [k for k in registry if k.startswith(prefix) and partial_lower in k.lower()]
    if not matches:
        print("no cluster matches repo=%s partial=%r" % (repo, partial), file=sys.stderr)
        return 1
    if len(matches) > 1:
        print("ambiguous — %d clusters match, narrow your partial signature:" % len(matches), file=sys.stderr)
        for k in matches:
            print("  %s" % k, file=sys.stderr)
        return 1

    key = matches[0]
    entry = registry[key]
    print("Matched cluster:")
    print("  key: %s" % key)
    print(json.dumps(entry, indent=2, sort_keys=True))

    if not args.yes:
        if not sys.stdin.isatty():
            print("refusing to apply without confirmation in a non-interactive shell — pass --yes",
                  file=sys.stderr)
            return 1
        ans = input("Apply ack (status=fixed, commit=%s, generator_addressed=%s)? [y/N] "
                     % (args.commit, args.generator_addressed))
        if ans.strip().lower() not in ("y", "yes"):
            print("aborted, no change made")
            return 1

    entry["status"] = "fixed"
    entry["fix_commit"] = args.commit
    entry["generator_addressed"] = args.generator_addressed
    registry[key] = entry
    save_registry(args.state_dir, registry)
    print("acked: %s -> fixed (commit=%s, generator_addressed=%s)" % (key, args.commit, args.generator_addressed))
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Cluster BAD-bucket outcomes.jsonl events by error signature; "
                     "flag regressions of clusters already marked fixed.")
    parser.add_argument("state_dir", nargs="?", default=STATE_DIR_DEFAULT)
    parser.add_argument("logs_dir", nargs="?", default=LOGS_DIR_DEFAULT)
    parser.add_argument("--ack", nargs=2, metavar=("REPO", "SIGNATURE_PARTIAL"))
    parser.add_argument("--commit")
    parser.add_argument("--generator-addressed", dest="generator_addressed",
                         choices=["yes", "no", "unsure"])
    parser.add_argument("--seed", action="store_true",
                         help="install-time: mark the current qa_ledger and FAILED deploys as already "
                              "seen (no NEW burst on first run), then exit")
    parser.add_argument("--yes", action="store_true",
                         help="skip interactive confirmation (required in non-interactive shells)")
    parser.add_argument("--digest", type=float, metavar="HOURS",
                         help="read-only window summary for digest_notify.sh — does NOT run "
                              "detection (see cmd_digest docstring)")
    args = parser.parse_args()

    if args.seed:
        print("seeded: %d failed deploy id(s) marked seen, ledger cursor at end" % seed_cursors(args.state_dir))
        return 0
    if args.ack:
        if not args.commit or not args.generator_addressed:
            parser.error("--ack requires both --commit and --generator-addressed")
        return cmd_ack(args)
    if args.digest is not None:
        return cmd_digest(args)
    return cmd_detect(args)


if __name__ == "__main__":
    sys.exit(main())
