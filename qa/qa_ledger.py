#!/usr/bin/env python3
"""qa_ledger.py - S12 measurement backbone: a ledger of LANDED items and the defects that escape the gates afterwards.

    qa_ledger.py derive      [--no-record] [--rescan-days 15] [--no-events]
    qa_ledger.py mark-escape --repo R --ref SHA --note TEXT [--no-record]
    qa_ledger.py summary     [--repo R]

State (all under $OVN_DIR/state, never anywhere else):
    qa_ledger.jsonl     append-only. Two line kinds: {"kind":"landed",...} and {"kind":"event",...}
    qa_ledger.cursor    byte offset into outcomes.jsonl (only complete lines are consumed)
    qa_ledger.prev.json last outcome epoch per repo (lower bound of the commit-attribution window)

How a landed record is built (see qa/qa_ledger.README.md for blind spots):
    * source line: an outcomes.jsonl row with class=landed and a pushed*/stage(higher-tier) status.
    * commits: outcomes carry NO sha, so commits are ATTRIBUTED by time: non-housekeeping, non-merge commits on
      origin/{overnight/feature,claude/feature,develop,main} committed in (max(prev outcome of the repo, ts-duration-600s), ts+60s].
    * risk class A/B/C from files (when commits were found) and item text (VERIFY line / item text from OVERNIGHT_PROGRESS.md).
    * weak_oracle: the item's VERIFY command is existence-only (grep/test -f/ls...) with no test runner.
Events are appended by a rescan of every record younger than --rescan-days (idempotent, keyed):
    revert (<=14d), hotfix (later fix commit, same files, <=7d), emergency / test_watch_red (EMERGENCY commit, <=7d, attributed by
    file overlap), escape (manual, mark-escape).

Never touches a live clone (read-only git), never takes run.lock, never prints secrets, always exit 0.
"""
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "ledger"
REF_CANDIDATES = ["origin/overnight/feature", "origin/claude/feature", "origin/develop", "origin/main"]
REVERT_DAYS = 14
HOTFIX_DAYS = 7
EMERGENCY_DAYS = 7
DAY = 86400

HOUSEKEEPING = re.compile(r"^(chore\((queue|sync|overnight|deps|process)\)|fix\(queue\)|feat\(queue\)|chore\(queue|revert\(queue\)|"
                          r"Merge |chore: sync|docs\(queue\)|chore\(archive\))", re.I)
FIX_SUBJ = re.compile(r"^(fix|hotfix)(\(|:|!)", re.I)
# the pipeline's own in-flight repair loop for a staged item ("repair staged item to pass verification (round N)"): same planned feature, not an escape
INFLIGHT_REPAIR = re.compile(r"repair staged item to pass verification|\[EMERGENCY\]|\bstaged step\b", re.I)
REPAIR_SUBJ = re.compile(r"duplicate|misplaced|repair|broken|regress|undo|restore|\bmissing\b|crash|typo|syntax|import error|nameerror|"
                         r"\bfails?\b|failing|hotfix|incorrect|\bwrong\b|\bbug\b", re.I)
IGNORE_FILE = re.compile(r"(^|/)(OVERNIGHT_PROGRESS\.md|CHANGELOG[^/]*|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|poetry\.lock|"
                         r"Pipfile\.lock|__init__\.py|requirements[^/]*\.txt)$|\.md$|\.lock$")
TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec|e2e|androidTest|testing)(/|$)|(^|/)(test_[^/]*|[^/]*_test\.[a-z]+|[^/]*\.(test|spec)\.[a-z]+|"
                       r"conftest\.py|[^/]*Tests?\.(swift|kt))$", re.I)
DOC_PATH = re.compile(r"\.(md|txt|rst|adoc)$|(^|/)(docs?|assets|locales?|i18n|copy)(/|$)", re.I)
A_WORDS = {"auth", "login", "logout", "signup", "password", "passwords", "jwt", "oauth", "token", "tokens", "paywall", "premium",
           "entitlement", "entitlements", "subscription", "subscriptions", "revenuecat", "billing", "payment", "payments", "stripe",
           "checkout", "webhook", "webhooks", "migration", "migrations", "alembic", "dockerfile", "railway", "vercel", "procfile",
           "ntfy", "notify", "alert", "alerts", "alerting", "notification", "notifications", "secrets", "credentials", "permissions"}
A_TEXT = re.compile(r"\b(auth\w*|login|password\w*|jwt|oauth|paywall\w*|premium|revenuecat|entitlement\w*|subscription\w*|billing|stripe|"
                    r"payment\w*|migration\w*|alembic|webhook\w*|prod(uction)? (config|env\w*|deploy\w*)|alert path|ntfy|emergency|"
                    r"is_active|api[_ ]key|secret\w*|credential\w*)\b", re.I)
RUNNER = re.compile(r"pytest|npm (run )?test|npx|vitest|jest|\btsc\b|gradle|go test|cargo|godot|python3? -m|unittest|\.sh\b|make |mypy|ruff|"
                    r"xcodebuild|curl|playwright|alembic|node ", re.I)
FILE_RE = re.compile(r"[\w./@-]+\.(?:py|ts|tsx|js|jsx|vue|gd|swift|kt|sh|json|yml|yaml|toml)")


# ------------------------------------------------------------------ small helpers
def epoch(ts):
    try:
        import calendar
        return calendar.timegm(time.strptime(str(ts)[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:  # noqa: BLE001
        return 0


def iso(e):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))


SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")


def safe_name(x):
    """A repo name must be a plain basename (no separators, no leading '-' or '.', no '..')."""
    return isinstance(x, str) and bool(SAFE_NAME.match(x)) and ".." not in x


def as_str(x, default=""):
    """Scalars -> str; None/dict/list -> default. Hostile rows must not be able to inject unhashable or non-string values."""
    if isinstance(x, bool):
        return default
    if isinstance(x, (str, int, float)):
        return str(x)
    return default


def as_int(x, default):
    try:
        if isinstance(x, (bool, list, dict)) or x is None:
            return default
        v = int(float(x))
        return v if v > 0 else default
    except (ValueError, TypeError, OverflowError):
        return default


def clean_outcome(d):
    """Validate one outcomes.jsonl row. -> (row dict | None, malformed bool). A row that is not a dict, or whose repo/ts/status have the
    wrong type, is MALFORMED (counted and reported, never silently dropped, never allowed to crash the pass). Rows with neither repo
    nor ts that are not landings (foreign line kinds) return (None, False)."""
    if not isinstance(d, dict):
        return None, True
    repo, ts, st, cl = d.get("repo"), d.get("ts"), d.get("status", ""), d.get("class", "")
    if repo is None and ts is None:
        return None, cl in LANDED_CLASSES
    if not safe_name(repo) or not isinstance(ts, str) or not epoch(ts) or not (st is None or isinstance(st, str)) \
            or not (cl is None or isinstance(cl, str)):
        return None, True
    r = {"repo": repo, "ts": ts, "status": st or "", "class": cl or "",
         "id": as_str(d.get("id")), "type": as_str(d.get("type")), "tier": as_str(d.get("tier"), "?") or "?", "category": as_str(d.get("category")),
         "feat_tag": as_str(d.get("feat_tag")), "item_hash": as_str(d.get("item_hash")), "duration_s": as_int(d.get("duration_s"), 1800),
         "attempt": as_int(d.get("attempt"), None)}
    return r, False


def _is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def valid_rec(d):
    """Shape check for a ledger line read back from disk (a hand-edited / corrupted line must not crash readers)."""
    strs = ("key", "repo", "ts", "risk", "tier", "status", "risk_basis", "commit_basis", "feat_tag")
    return (all(isinstance(d.get(k), str) for k in strs) and _is_int(d.get("epoch"))
            and isinstance(d.get("commits"), list) and all(isinstance(x, str) for x in d["commits"])
            and isinstance(d.get("subjects"), list) and isinstance(d.get("files"), list) and all(isinstance(x, str) for x in d["files"])
            and isinstance(d.get("flags"), list))


def valid_event(d):
    return (isinstance(d.get("key"), str) and isinstance(d.get("type"), str) and isinstance(d.get("repo"), str)
            and _is_int(d.get("epoch")) and (d.get("rec") is None or isinstance(d.get("rec"), str)))


def paths():
    s = qc.state_dir()
    return {"ledger": os.path.join(s, "qa_ledger.jsonl"), "cursor": os.path.join(s, "qa_ledger.cursor"),
            "prev": os.path.join(s, "qa_ledger.prev.json"), "outcomes": os.path.join(s, "outcomes.jsonl")}


def rkey(repo, ts, rid, item_hash):
    return hashlib.sha1(("%s|%s|%s|%s" % (repo, ts, rid, item_hash)).encode()).hexdigest()[:16]


def load_ledger(path=None):
    """-> (records list, events list). Tolerates NUL bytes / torn lines."""
    path = path or paths()["ledger"]
    recs, evs = [], []
    try:
        with open(path, "rb") as f:
            for raw in f:
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    continue
                if not isinstance(d, dict):
                    continue
                if d.get("kind") == "landed" and valid_rec(d):
                    recs.append(d)
                elif d.get("kind") == "event" and valid_event(d):
                    evs.append(d)
    except OSError:
        pass
    return recs, evs


def append_lines(objs):
    if not objs:
        return
    os.makedirs(qc.state_dir(), exist_ok=True)
    with open(paths()["ledger"], "a") as f:
        for o in objs:
            f.write(json.dumps(o, ensure_ascii=False, sort_keys=True) + "\n")


# ------------------------------------------------------------------ git access (read-only)
def existing_refs(rd):
    env = os.environ.get("OVN_QA_LEDGER_REFS")
    cands = env.split() if env else REF_CANDIDATES
    return [r for r in cands if qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")[0] == 0]


def git_commits(rd, refs, since, until):
    """Non-merge commits on refs in [since, until] -> list of dicts, newest first. Includes bodies and changed files."""
    if not refs:
        return []
    fmt = "%x01%H%x1f%ct%x1f%an%x1f%s%x1f%b%x02"
    rc, out, _ = qc.git(rd, "log", "--no-merges", "--since=@%d" % since, "--until=@%d" % until, "--format=" + fmt, "--name-only", *refs, timeout=180)
    if rc != 0:
        return []
    res = []
    for chunk in out.split("\x01"):
        if "\x02" not in chunk:
            continue
        head, tail = chunk.split("\x02", 1)
        f = head.split("\x1f")
        if len(f) < 5:
            continue
        try:
            ct = int(f[1])
        except ValueError:
            continue
        res.append({"sha": f[0], "ct": ct, "author": f[2], "subject": f[3], "body": f[4],
                    "files": [l.strip() for l in tail.splitlines() if l.strip()]})
    return res


def emergency_files(rd, sha):
    """File paths mentioned in the lines an EMERGENCY commit ADDED to OVERNIGHT_PROGRESS.md (the item text carries the error excerpt)."""
    rc, out, _ = qc.git(rd, "show", "--format=", "-U0", sha, "--", "OVERNIGHT_PROGRESS.md", timeout=60)
    if rc != 0:
        return []
    found = []
    for line in out.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            found += FILE_RE.findall(line)
    return sorted(set(f for f in found if not IGNORE_FILE.search(f)))[:40]


# ------------------------------------------------------------------ item text / weak oracle / risk
def item_hash_like_pipeline(line):
    """Port of lib_item_select.sh ovn_item_hash (strip checkbox; feat-tag key with date stamp removed, else the text)."""
    text = re.sub(r"^- \[[ xX]\] ", "", line)
    m = re.search(r"\[feat:[^\]]+\]", text)
    if m:
        k = re.sub(r"-\d{8}-", "-", m.group(0), count=1)
        k = re.sub(r"-\d{6}-", "-", k, count=1)
        return hashlib.md5(k.encode()).hexdigest()
    return hashlib.md5(text.encode()).hexdigest()


class ItemTexts(object):
    """Lazy per-repo map feat_tag/item_hash -> item line, read from OVERNIGHT_PROGRESS.md via `git show` (no checkout)."""

    def __init__(self):
        self.cache = {}

    def get(self, repo, rd, refs):
        if repo in self.cache:
            return self.cache[repo]
        by_tag, by_hash = {}, {}
        text = ""
        for ref in (["origin/overnight/feature", "origin/develop", "origin/claude/feature"] if rd else []):
            if ref in refs:
                rc, out, _ = qc.git(rd, "show", "%s:OVERNIGHT_PROGRESS.md" % ref, timeout=60)
                if rc == 0 and out:
                    text = out
                    break
        for line in text.splitlines():
            if not line.startswith("- ["):
                continue
            by_hash.setdefault(item_hash_like_pipeline(line), line)
            m = re.search(r"\[feat:([^\]]+)\]", line)
            if m:
                by_tag.setdefault(m.group(1), line)
        self.cache[repo] = (by_tag, by_hash)
        return self.cache[repo]


def verify_cmd(line):
    m = re.search(r"VERIFY:\s*`([^`]+)`", line or "")
    return m.group(1) if m else ""


def weak_oracle(line):
    """True if the item's VERIFY is existence-only (no test runner); False if a runner is used; None if no VERIFY text available."""
    cmd = verify_cmd(line)
    if not cmd:
        return None
    return RUNNER.search(cmd) is None


def words(path):
    return set(w for w in re.split(r"[^a-z0-9]+", path.lower()) if w)


def risk_class(files, text, tier, category, subjects):
    """-> (class, basis). A = auth/paywall/RevenueCat/billing/migrations/prod config/alert path; B = other source/endpoint change;
    C = tests-only/docs/copy/deletes. Files (from attributed commits) beat text; text is the fallback."""
    files = [f for f in files if f]
    if files:
        non_test = [f for f in files if not TEST_PATH.search(f) and not DOC_PATH.search(f)]
        if not non_test:
            return "C", "files:tests-docs-only"
        for f in non_test:
            if words(f) & A_WORDS:
                return "A", "file:" + f[:80]
        if A_TEXT.search((text or "")[:600]):
            return "A", "text:" + A_TEXT.search(text[:600]).group(0)[:30]
        if all(re.match(r"^(chore: remove file|chore\(remove\)|refactor: delete|remove )", s, re.I) for s in subjects or [""]) and subjects:
            return "C", "subjects:deletes"
        return "B", "files:source"
    # no commits attributed: text/tier/category only
    m = A_TEXT.search((text or "")[:600])
    if m:
        return "A", "text:" + m.group(0)[:30]
    cat = (category or "").lower()
    if cat in ("test", "tests", "docs", "doc", "copy", "style") and str(tier) in ("1", "2", "?", ""):
        return "C", "text-only:category=" + cat
    return "B", "text-only:default"


# ------------------------------------------------------------------ derive: landed records
# 2026-10-09 (harness-credit-integrity round 3): "landed-uncredited" is a green push whose item the auto-credit refused to tick - NOT a landing for the pass rate (neutral),
# but the commit is real code on claude/feature -> develop -> staging -> prod and needs QA / risk classification / escape accounting exactly like a credited landing.
LANDED_CLASSES = ("landed", "landed-uncredited")


def is_landed(d):
    st = d.get("status")
    if not isinstance(st, str):
        return False
    return d.get("class") in LANDED_CLASSES and bool(d.get("repo")) and (st.startswith("pushed") or "stage(higher-tier)" in st)


def read_new_outcomes(offset):
    p = paths()["outcomes"]
    try:
        size = os.path.getsize(p)
    except OSError:
        return [], offset, 0
    if offset > size:
        offset = 0  # rotated/truncated
    rows, bad = [], 0
    with open(p, "rb") as f:
        f.seek(offset)
        data = f.read()
    end = data.rfind(b"\n")
    if end < 0:
        return [], offset, 0
    for raw in data[:end + 1].split(b"\n"):
        if not raw.strip():
            continue
        try:
            rows.append(json.loads(raw.decode("utf-8", "replace")))
        except ValueError:
            bad += 1  # complete-but-unparseable line: counted, then consumed (a torn LAST line has no newline and is never reached)
    return rows, offset + end + 1, bad


def read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def derive_records(rows, existing_keys, claimed, stats=None):
    """-> (new records, prev map). stats (dict) receives 'malformed' (rows rejected by validation) and 'failed' (rows that raised)."""
    stats = stats if stats is not None else {}
    prev = read_json(paths()["prev"], {})
    prev = {k: v for k, v in prev.items() if isinstance(k, str) and _is_int(v)} if isinstance(prev, dict) else {}
    cleaned = []
    stats.setdefault("malformed", 0)
    stats.setdefault("failed", 0)
    for raw in rows:
        r, bad = clean_outcome(raw)
        stats["malformed"] += int(bad)
        if r is not None:
            cleaned.append(r)
    rows = sorted(cleaned, key=lambda r: epoch(r["ts"]))
    landed = [r for r in rows if is_landed(r) and rkey(r["repo"], r["ts"], r.get("id", ""), r.get("item_hash", "")) not in existing_keys]
    by_repo = {}
    for r in landed:
        by_repo.setdefault(r["repo"], []).append(r)
    texts = ItemTexts()
    out = []
    for repo, rs in sorted(by_repo.items()):
        rd = qc.repo_dir(repo)
        refs = existing_refs(rd) if rd else []
        lo = min(epoch(r["ts"]) - int(r.get("duration_s") or 1800) - 700 for r in rs)
        hi = max(epoch(r["ts"]) for r in rs) + 120
        commits = [c for c in git_commits(rd, refs, lo, hi) if not HOUSEKEEPING.search(c["subject"]) and not c["subject"].startswith("Revert ")
                   and not (c["files"] and all(os.path.basename(f) == "OVERNIGHT_PROGRESS.md" for f in c["files"]))] if rd else []
        commits.sort(key=lambda c: c["ct"])
        by_tag, by_hash = texts.get(repo, rd, refs)
        # previous outcome epoch for the repo (any class), from this batch + stored state
        repo_rows = [epoch(r["ts"]) for r in rows if r["repo"] == repo]
        last_prev = prev.get(repo, 0)
        for r in rs:
            try:
                e = epoch(r["ts"])
                dur = int(r.get("duration_s") or 1800)
                earlier = [x for x in repo_rows if x < e]
                pe = max(earlier) if earlier else last_prev
                floor = max(e - dur - 600, pe) if pe else e - dur - 600
                mine = [c for c in commits if floor < c["ct"] <= e + 60 and c["sha"] not in claimed][-4:]  # the 4 closest to the outcome
                for c in mine:
                    claimed.add(c["sha"])
                files = []
                for c in mine:
                    for f in c["files"]:
                        if f not in files:
                            files.append(f)
                line = by_tag.get(r.get("feat_tag") or "") or by_hash.get(r.get("item_hash") or "") or ""
                text = line or ""
                st = r.get("status") or ""
                flags = [n for n, pat in (("untested-change", "untested-change"), ("redgreen-suspect", "redgreen:SUSPECT"), ("after-rebase", "after-rebase"),
                                          ("stage", "stage(higher-tier)")) if pat in st]
                if r.get("class") == "landed-uncredited":
                    flags.append("uncredited")   # real commits, the credit was refused: kept in the ledger (QA + escapes) but visible as not credited
                if not mine and rd:   # 2026-10-03 (integrity A6): "landed" with NO commit in the window = a landing origin never received (or a bookkeeping-only row)
                    flags.append("no-commit")
                rc_, basis = risk_class(files, text, r.get("tier"), r.get("category"), [c["subject"] for c in mine])
                out.append({"kind": "landed", "key": rkey(repo, r["ts"], r.get("id", ""), r.get("item_hash", "")), "ts": r["ts"], "epoch": e,
                            "repo": repo, "id": r.get("id", ""), "type": r.get("type", ""), "tier": str(r.get("tier", "?")),
                            "category": r.get("category", ""), "status": st, "attempt": r.get("attempt"), "feat_tag": r.get("feat_tag", "") or "",
                            "item_hash": r.get("item_hash", "") or "", "risk": rc_, "risk_basis": basis,
                            "commits": [c["sha"] for c in mine], "subjects": [c["subject"][:120] for c in mine], "files": files[:60],
                            "commit_basis": "time-window" if mine else ("no-clone" if not rd else "none"),
                            "item_text_found": bool(line), "weak_oracle": weak_oracle(line), "flags": flags})
            except Exception:  # noqa: BLE001 - one bad row must not freeze the cursor for every later row
                stats["failed"] += 1
    # persist last outcome epoch per repo
    for r in rows:
        prev[r["repo"]] = max(prev.get(r["repo"], 0), epoch(r["ts"]))
    return out, prev


# ------------------------------------------------------------------ landed-without-commit alert
NOCOMMIT_ALERT_MIN = 3


def nocommit_repeats(recs):
    """{(repo, item_hash): n} for item hashes landed >= NOCOMMIT_ALERT_MIN times where the record carries the no-commit flag (and a real hash)."""
    c = {}
    for r in recs:
        if "no-commit" in r.get("flags", []) and r.get("item_hash"):
            k = (r["repo"], r["item_hash"])
            c[k] = c.get(k, 0) + 1
    return {k: n for k, n in c.items() if n >= NOCOMMIT_ALERT_MIN}


def alert_nocommit(recs):
    """One alerts.log warn line per (repo, item hash) when its no-commit landing count first reaches NOCOMMIT_ALERT_MIN (and again at each further +3).
    State: state/qa_ledger.nocommit_alerted.json. Returns the alert lines written. Never raises."""
    sp = os.path.join(qc.state_dir(), "qa_ledger.nocommit_alerted.json")
    done = read_json(sp, {})
    done = done if isinstance(done, dict) else {}
    lines = []
    try:
        for (repo, h), n in sorted(nocommit_repeats(recs).items()):
            k = "%s|%s" % (repo, h)
            if _is_int(done.get(k)) and n < done[k] + NOCOMMIT_ALERT_MIN:
                continue
            done[k] = n
            lines.append("[%s] warn | qa-ledger:%s | item %s was recorded as landed %d times with NO commit reaching origin - the landing is not real "
                         "(commit lost before push?); excluded from the escape-rate denominator" % (time.strftime("%Y-%m-%d %H:%M:%S"), repo, h[:12], n))
        if lines:
            os.makedirs(qc.state_dir(), exist_ok=True)
            with open(os.path.join(qc.state_dir(), "alerts.log"), "a") as f:
                f.write("\n".join(lines) + "\n")
            with open(sp + ".tmp", "w") as f:
                json.dump(done, f)
            os.replace(sp + ".tmp", sp)
    except OSError:
        return []
    return lines


# ------------------------------------------------------------------ events
def overlap(rec_files, other_files):
    rf = [f for f in rec_files if not IGNORE_FILE.search(f)]
    of = [f for f in other_files if not IGNORE_FILE.search(f)]
    rb = {}
    for f in rf:
        rb.setdefault(os.path.basename(f), []).append(f)
    hit = set()
    for g in of:
        if g in rf:
            hit.add(g)
            continue
        for h in rb.get(os.path.basename(g), []):
            if len(os.path.basename(g)) > 3 and (h.endswith(g) or g.endswith(h)):
                hit.add(h)
    return sorted(hit)


def scan_events(recs, existing_ev_keys, now, rescan_days):
    """Detect later outcome events for records younger than rescan_days. Returns new event dicts."""
    new = []
    seen = set(existing_ev_keys)
    commit_owner = {}
    for r in recs:
        for s in r.get("commits", []):
            commit_owner[s] = r

    def add(ev):
        if ev["key"] in seen:
            return
        seen.add(ev["key"])
        new.append(ev)

    by_repo = {}
    for r in recs:
        if now - r["epoch"] <= rescan_days * DAY and (r.get("commits") or r.get("files")):
            by_repo.setdefault(r["repo"], []).append(r)
    for repo, rs in sorted(by_repo.items()):
        rd = qc.repo_dir(repo)
        if not rd:
            continue
        refs = existing_refs(rd)
        lo = min(r["epoch"] for r in rs) - 60
        commits = git_commits(rd, refs, lo, now + 3600)
        for c in commits:
            subj, body = c["subject"], c["body"]
            # ---- reverts
            tgt_shas = re.findall(r"This reverts commit ([0-9a-f]{7,40})", body)
            is_rev = subj.startswith('Revert "') or bool(tgt_shas)
            if is_rev:
                inner = subj[len('Revert "'):-1] if subj.startswith('Revert "') and subj.endswith('"') else ""
                for r in rs:
                    dt = c["ct"] - r["epoch"]
                    if not (0 <= dt <= REVERT_DAYS * DAY):
                        continue
                    by_sha = any(s.startswith(t) or t.startswith(s[:len(t)]) for t in tgt_shas for s in r["commits"])
                    by_subj = bool(inner) and any(s == inner or (len(inner) > 40 and s.startswith(inner[:60])) for s in r["subjects"])
                    if by_sha or by_subj:
                        add({"kind": "event", "key": "revert|%s|%s" % (r["key"], c["sha"][:12]), "rec": r["key"], "repo": repo, "type": "revert",
                             "ts": iso(c["ct"]), "epoch": c["ct"], "ref": c["sha"][:12], "confidence": "sha" if by_sha else "subject",
                             "days_after": round(dt / DAY, 2), "note": subj[:120]})
                continue
            # ---- emergency / test-watch red (repo-level event + attributed events)
            if re.search(r"emergenc", subj, re.I):
                typ = "test_watch_red" if re.search(r"suite red|test-watch", subj, re.I) else "emergency"
                efiles = emergency_files(rd, c["sha"])
                add({"kind": "event", "key": "%s-repo|%s|%s" % (typ, repo, c["sha"][:12]), "rec": None, "repo": repo, "type": typ, "ts": iso(c["ct"]),
                     "epoch": c["ct"], "ref": c["sha"][:12], "confidence": "repo-level", "files": efiles[:20], "note": subj[:120]})
                # one emergency is attributed to the ONE best-explaining record (most overlapping files, then most recent), not to every
                # record that ever touched the file (same dilution fix as hotfix)
                cands = []
                for r in rs:
                    dt = c["ct"] - r["epoch"]
                    if 0 <= dt <= EMERGENCY_DAYS * DAY:
                        ov = overlap(r["files"], efiles)
                        if ov:
                            cands.append((len(ov), r["epoch"], r, ov))
                if cands:
                    _, _, r, ov = max(cands, key=lambda x: (x[0], x[1]))
                    add({"kind": "event", "key": "%s|%s|%s" % (typ, r["key"], c["sha"][:12]), "rec": r["key"], "repo": repo, "type": typ,
                         "ts": iso(c["ct"]), "epoch": c["ct"], "ref": c["sha"][:12], "confidence": "file-overlap", "overlap": ov[:5],
                         "days_after": round((c["ct"] - r["epoch"]) / DAY, 2), "candidates": len(cands), "note": subj[:120]})
                continue
            # ---- hotfix: later fix commit touching >=1 of the same files within 7d. A fix commit is attributed to the ONE
            # landed record that best explains it (most overlapping files, then most recent) - attributing it to every earlier
            # record on a popular file inflated the rate ~5x in the first replay.
            if FIX_SUBJ.search(subj) and not HOUSEKEEPING.search(subj) and not INFLIGHT_REPAIR.search(subj):
                own = commit_owner.get(c["sha"])
                cfiles = [f for f in c["files"] if not IGNORE_FILE.search(f)]
                if not cfiles:
                    continue
                cands = []
                for r in rs:
                    dt = c["ct"] - r["epoch"]
                    if not (0 < dt <= HOTFIX_DAYS * DAY) or c["sha"] in r["commits"]:
                        continue
                    if own is not None and (own["key"] == r["key"] or (r["feat_tag"] and own["feat_tag"] == r["feat_tag"])):
                        continue  # continuation of the same planned feature, not an escape
                    ov = overlap(r["files"], cfiles)
                    if ov:
                        cands.append((len(ov), r["epoch"], r, ov))
                if not cands:
                    continue
                n_ov, _, r, ov = max(cands, key=lambda x: (x[0], x[1]))
                repair = bool(REPAIR_SUBJ.search(subj))
                # judged on a 24-sample read of real flags: repair-subject ~73% real, "non-pipeline fix touching the same file" ~11% real
                # (large human commits overlap everything) -> only a repair-subject on a focused commit (<=12 files) counts as strong
                strong = repair and len(cfiles) <= 12
                add({"kind": "event", "key": "hotfix|%s|%s" % (r["key"], c["sha"][:12]), "rec": r["key"], "repo": repo, "type": "hotfix",
                     "ts": iso(c["ct"]), "epoch": c["ct"], "ref": c["sha"][:12], "confidence": "strong" if strong else "weak",
                     "basis": ("repair-subject" if repair else ("non-pipeline-fix" if own is None else "generic-fix-same-file")) + ("" if len(cfiles) <= 12 else "+wide-commit"), "overlap": ov[:5],
                     "days_after": round((c["ct"] - r["epoch"]) / DAY, 2), "author": c["author"][:30], "note": subj[:120],
                     "fix_landed_by_pipeline": own is not None, "candidates": len(cands)})
    return new


# ------------------------------------------------------------------ commands
def cmd_derive(argv):
    t0 = time.time()
    rescan = 15
    if "--rescan-days" in argv:
        try:
            rescan = int(argv[argv.index("--rescan-days") + 1])
        except (ValueError, IndexError):
            pass
    p = paths()
    if not os.path.exists(p["outcomes"]):
        return qc.verdict("UNVERIFIED", GATE, "*", "-", "state/outcomes.jsonl not found")
    try:
        offset = int(open(p["cursor"]).read().strip() or "0")
    except (OSError, ValueError):
        offset = 0
    rows, new_off, bad_json = read_new_outcomes(offset)
    recs, evs = load_ledger()
    existing = set(r["key"] for r in recs)
    claimed = set(s for r in recs for s in r.get("commits", []))
    stats = {}
    new_recs, prev = derive_records(rows, existing, claimed, stats)
    append_lines(new_recs)
    recs += new_recs
    nc_alerts = alert_nocommit(recs)
    new_evs = []
    scan_error = ""
    if "--no-events" not in argv:
        try:
            new_evs = scan_events(recs, [e["key"] for e in evs], int(time.time()), rescan)
            append_lines(new_evs)
        except Exception as ex:  # noqa: BLE001 - an event-scan crash must not pin the cursor (records are already appended, keyed)
            scan_error = "%s: %s" % (type(ex).__name__, str(ex)[:100])
    skipped = stats.get("malformed", 0) + stats.get("failed", 0) + bad_json
    # cursor/prev are written LAST: a crash above re-reads the rows next run (dedupe by key makes that safe)
    os.makedirs(qc.state_dir(), exist_ok=True)
    with open(p["prev"] + ".tmp", "w") as f:
        json.dump(prev, f)
    os.replace(p["prev"] + ".tmp", p["prev"])
    with open(p["cursor"] + ".tmp", "w") as f:
        f.write(str(new_off))
    os.replace(p["cursor"] + ".tmp", p["cursor"])
    with_commits = sum(1 for r in new_recs if r["commits"])
    no_commit = sum(1 for r in new_recs if "no-commit" in r.get("flags", []))
    summ = "outcomes+%d rows -> +%d landed (%d with commits, %d with NO commit) +%d events" % (len(rows), len(new_recs), with_commits, no_commit, len(new_evs))
    if nc_alerts:
        summ += "; ALERT: %d item(s) landed 3+ times with no commit" % len(nc_alerts)
    v = "PASS" if (new_recs or new_evs or not rows) else "NA"
    # a pass that could not check everything must say so: FLAG, never PASS
    if skipped:
        v = "FLAG"
        summ += "; SKIPPED %d unreadable row(s) (%d bad json, %d malformed fields, %d failed)" % (
            skipped, bad_json, stats.get("malformed", 0), stats.get("failed", 0))
    if scan_error:
        v = "FLAG"
        summ += "; EVENT SCAN FAILED (%s) - escape events were NOT updated this pass" % scan_error
    return qc.verdict(v, GATE, "*", "-", summ,
                      {"rows": len(rows), "new_landed": len(new_recs), "new_landed_with_commits": with_commits, "new_landed_no_commit": no_commit,
                       "new_events": len(new_evs), "ledger_records": len(recs), "skipped_rows": skipped, "bad_json": bad_json,
                       "malformed_rows": stats.get("malformed", 0), "failed_rows": stats.get("failed", 0), "event_scan_error": scan_error},
                      ms=int((time.time() - t0) * 1000))


def opt(argv, name, default=""):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def cmd_mark_escape(argv):
    repo, ref, note = opt(argv, "--repo"), opt(argv, "--ref"), opt(argv, "--note")
    if not repo or not ref:
        return qc.verdict("UNVERIFIED", GATE, repo or "?", ref or "?", "usage: mark-escape --repo R --ref SHA --note TEXT")
    if not safe_name(repo):
        return qc.verdict("UNVERIFIED", GATE, "?", ref[:40], "repo must be a plain name (no path separators, no leading '-' or '.')")
    if ref.startswith("-") or any(ch in ref for ch in "\n\x00 "):
        return qc.verdict("UNVERIFIED", GATE, repo, ref[:40], "ref must be a commit-ish (no leading '-', no whitespace)")
    rd = qc.repo_dir(repo)
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo, ref, "no clone for repo")
    rc, out, _ = qc.git(rd, "rev-parse", "--verify", "-q", ref + "^{commit}")
    if rc != 0:
        return qc.verdict("UNVERIFIED", GATE, repo, ref, "ref does not resolve in the clone")
    sha = out.strip()
    rc, out, _ = qc.git(rd, "show", "-s", "--format=%ct", sha)
    cts = int(out.strip() or 0) if rc == 0 else int(time.time())
    rc, out, _ = qc.git(rd, "show", "--format=", "--name-only", sha)
    sfiles = [l for l in out.splitlines() if l.strip()] if rc == 0 else []
    recs, evs = load_ledger()
    keys = set(e["key"] for e in evs)
    targets, how = [], ""
    for r in recs:
        if r["repo"] == repo and any(s.startswith(sha[:12]) or sha.startswith(s[:12]) for s in r["commits"]):
            targets.append(r)
            how = "commit"
    if not targets:  # the escaped code is in code touched by earlier landed items: attach to those with file overlap in the 30d before
        for r in recs:
            if r["repo"] == repo and 0 <= cts - r["epoch"] <= 30 * DAY and overlap(r["files"], sfiles):
                targets.append(r)
        how = "file-overlap" if targets else ""
    new = []
    for r in targets or [None]:
        k = "escape|%s|%s" % (r["key"] if r else "-", sha[:12])
        if k in keys:
            continue
        new.append({"kind": "event", "key": k, "rec": r["key"] if r else None, "repo": repo, "type": "escape", "ts": iso(int(time.time())),
                    "epoch": int(time.time()), "ref": sha[:12], "confidence": ("manual-" + how) if r else "manual-unattributed", "manual": True,
                    "note": note[:300], "files": sfiles[:20]})
    append_lines(new)
    # an escape that attaches to no landed record is stored but will not show on any scorecard: say so (FLAG), do not claim a clean PASS
    return qc.verdict("PASS" if targets else "FLAG", GATE, repo, sha[:12],
                      "recorded %d escape event(s) (%s)%s" % (len(new), how or "unattributed",
                                                             "" if targets else " - attached to NO landed record, so no scorecard will show it"),
                      {"attached_to": [t["key"] for t in targets], "basis": how or "none"})


def cmd_summary(argv):
    repo = opt(argv, "--repo")
    recs, evs = load_ledger()
    recs = [r for r in recs if not repo or r["repo"] == repo]
    return qc.verdict("PASS" if recs else "NA", GATE, repo or "*", "-", "%d landed records, %d events" % (len(recs), len(evs)),
                      {"records": len(recs), "events": len(evs), "with_commits": sum(1 for r in recs if r["commits"]),
                       "no_commit": sum(1 for r in recs if "no-commit" in r.get("flags", []))})


def main(argv):
    if not argv or argv[0] not in ("derive", "mark-escape", "summary"):
        sys.stderr.write(__doc__)
        return 2
    sub, rest = argv[0], argv[1:]
    fn = {"derive": cmd_derive, "mark-escape": cmd_mark_escape, "summary": cmd_summary}[sub]
    return qc.main_guard(GATE, fn, rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
