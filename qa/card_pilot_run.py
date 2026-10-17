#!/usr/bin/env python3
"""card_pilot_run.py - Phase 2 SHADOW pilot of gate S0 (acceptance cards), see qa/card_pilot_run.README.md and docs/QA_PLAN_2026-10-01.md section 7.

    python3 qa/card_pilot_run.py run    [--config F] [--repo NAME ...] [--max-cards N] [--llm-url URL] [--dry-run] [--no-record]
    python3 qa/card_pilot_run.py credit --repo NAME [--repo-path DIR] --head SHA [--item "<progress line>" | env OVN_CC_ITEM] [--no-stdout]

`run` (nightly cron, OFF until Mark flips OVN_QA_CARD_PILOT): picks up to N (default 6) open, not-yet-carded, S0-eligible items from the allow-listed
areas in qa/card_pilot.json (TAA backlog, iptv entitlement/paywall/RevenueCat), drafts a card with the local Qwen, lints it (card_lint, unchanged),
executes the verify_cmd at the base ref in a detached worktree (acceptance_card.exec_check) and appends one `kind: "card"` row per item to
state/qa_shadow/card_pilot.jsonl: verdict, lint errors, ms, model call count, GPU seconds.

  * GPU discipline: the pilot never takes run.lock or a verify lock. It SKIPS (UNVERIFIED, zero model calls) when run.lock is held (detected read-only
    with fuser/lsof, no flock attempt; when neither exists the answer is "unknown" and it skips) or a GPU-wait marker file exists in the state dir.
    The idle check is repeated between cards.
  * Cap: at most max_requests_per_night model requests per night (counted from the jsonl rows of the same night, every attempt counts, failed ones too).
  * A model failure (timeout, HTTP error, unparseable JSON, cap reached, non-loopback URL) is UNVERIFIED, never an error: exit code is always 0.
  * Out-of-scope items (GDScript, Swift, Kotlin, Vue/TSX/CSS/HTML, non-code, audit items) are excluded by acceptance_card/card_lint BEFORE any model call.
  * No behaviour change anywhere: shadow rows only. OVN_QA_CARD_PILOT=enforce is accepted but behaves exactly like shadow (there is no enforce path).

`credit` is the S2 shadow advisory called from lib_auto_credit.sh after an item was auto-credited (OVN_QA_CARD_CREDIT=off|shadow, default shadow): it logs to
state/qa_shadow/card_credit.jsonl whether a stored card existed for the item (credit_without_card) and whether its verify_cmd passes at the head sha.
It never changes what gets credited.
"""
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import types
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import card_lint as cl  # noqa: E402
import acceptance_card as ac  # noqa: E402

GATE = "card_pilot"
CREDIT_GATE = "card_credit"
DEFAULT_CONFIG = os.path.join(HERE, "card_pilot.json")
ROWS_FILE = "card_pilot.jsonl"
DEFAULT_MAX_CARDS = 6
DEFAULT_NIGHT_CAP = 12
DEFAULT_MAX_ATTEMPTS = 3          # an item that produced no card in this many nights is parked (no model call) instead of heading the list forever
# The credit hook (lib_auto_credit.sh) runs this under `timeout -k 20 180`. The inner timeouts must sum to well under that, so the SIGTERM never fires on a
# healthy-but-slow check: worktree add + pytest probe + the verify run, plus <= 45 s of cleanup (worktree remove 30 + prune 15). test_qa_card_pilot.py asserts the sum.
CREDIT_WT_TIMEOUT = 50
CREDIT_PROBE_TIMEOUT = 20
CREDIT_EXEC_TIMEOUT = 40
CREDIT_CLEANUP_BUDGET = 45
HOOK_TIMEOUT = 180
CREDIT_SLOTS = 2                  # at most this many concurrent credit checks (each is a full checkout + a verify run)


# ------------------------------------------------------------------------------------------------------------------------ helpers
def item_key(path, desc):
    """Stable identity of a backlog item across runs (path + first 100 chars of the description, whitespace-normalised)."""
    d = re.sub(r"\s+", " ", desc or "").strip()[:100]
    return hashlib.sha1(("%s|%s" % (path, d)).encode("utf-8", "replace")).hexdigest()[:16]


def night_key(now=None):
    """The 'night' a run belongs to: local date of (now - 12h), so a run at 23:00 and one at 04:00 share the cap."""
    t = (time.time() if now is None else now) - 12 * 3600
    return time.strftime("%Y-%m-%d", time.localtime(t))


def _int(x, default=0):
    """int() that never raises (a hand-edited / corrupted jsonl row must not turn every night into UNVERIFIED)."""
    try:
        return int(x)
    except (TypeError, ValueError):
        return default


def load_config(path=None):
    with open(path or os.environ.get("OVN_CARD_PILOT_CONFIG") or DEFAULT_CONFIG) as f:
        cfg = json.load(f)
    cfg.setdefault("max_cards", DEFAULT_MAX_CARDS)
    cfg.setdefault("max_requests_per_night", DEFAULT_NIGHT_CAP)
    cfg.setdefault("exec_timeout", ac.EXEC_TIMEOUT)
    cfg.setdefault("lock_file", "run.lock")
    cfg.setdefault("gpu_busy_markers", [])
    cfg.setdefault("extra_locks", [])               # other lock files whose holder uses the GPU (e.g. hygiene.lock), checked read-only like run.lock
    cfg.setdefault("busy_process_patterns", [])     # pgrep -f regexes of LLM-using children that run AFTER run_overnight released run.lock
    cfg.setdefault("gpu_util_log", "gpu_util.log")  # state file, lines `epoch util_pct mem_mb`; a fresh high sample = busy; absent/stale = no signal
    cfg.setdefault("gpu_util_busy_pct", 25)
    cfg.setdefault("gpu_util_max_age_s", 1200)
    cfg.setdefault("max_attempts", DEFAULT_MAX_ATTEMPTS)
    cfg.setdefault("base_refs", ["origin/claude/feature", "origin/develop", "HEAD"])
    cfg.setdefault("llm", {})
    cfg.setdefault("repos", {})
    return cfg


def rows_path():
    return os.path.join(qc.state_dir(), "qa_shadow", ROWS_FILE)


def night_used(rows, night):
    """Model requests already spent tonight: one `kind: "call"` row per request (written before the request, so a killed run still counts) plus, for older
    card rows that predate call rows, their model_calls. A non-numeric model_calls counts as 0 instead of raising."""
    used = 0
    for r in rows:
        if r.get("night") != night:
            continue
        if r.get("kind") == "call":
            used += 1
        elif r.get("kind") == "card" and not r.get("calls_logged"):
            used += _int(r.get("model_calls"))
    return used


def read_rows(path=None):
    out = []
    try:
        with open(path or rows_path(), errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if isinstance(d, dict):
                    out.append(d)
    except OSError:
        pass
    return out


def append_row(row):
    """Append one card row (never raises; the run summary is written by qc.main_guard)."""
    try:
        d = os.path.join(qc.state_dir(), "qa_shadow")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, ROWS_FILE), "a") as f:
            f.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception:  # noqa: BLE001
        pass


# ------------------------------------------------------------------------------------------------------------------------ idle check
def lock_held(lock_path):
    """True/False/None (unknown). READ-ONLY: it never opens the lock for locking, so it cannot make the runner's own non-blocking flock fail.
    Uses fuser, else lsof; a missing file means not held."""
    if not os.path.exists(lock_path):
        return False
    for cmd in (["fuser", lock_path], ["lsof", "-t", "--", lock_path]):
        try:
            r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            continue
        # fuser (Linux: pids on stdout, rc 0 = in use / rc 1 = unused; macOS: rc 0 even when unused) and lsof -t (pids on stdout): the PIDs on stdout are the answer
        if r.stdout.strip():
            return True
        if r.returncode in (0, 1):
            return False
    return None


def _process_running(patterns):
    """First pgrep -f pattern that matches a live process, else None. Fails OPEN (no pgrep = no signal): run.lock stays the fail-closed check."""
    for pat in patterns or []:
        try:
            r = subprocess.run(["pgrep", "-f", "--", pat], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            return None
        mine = {str(os.getpid()), str(os.getppid())}
        if [x for x in r.stdout.split() if x not in mine]:
            return pat
    return None


def _gpu_util_busy(path, busy_pct, max_age_s, now=None):
    """(pct, age_s) of the newest sample when it is fresh and >= busy_pct, else None."""
    try:
        with open(path, errors="replace") as f:
            lines = f.readlines()[-3:]
    except OSError:
        return None
    for line in reversed(lines):
        parts = line.split()
        if len(parts) >= 2:
            try:
                ts, pct = float(parts[0]), float(parts[1])
            except ValueError:
                continue
            age = (time.time() if now is None else now) - ts
            return (pct, age) if 0 <= age <= max_age_s and pct >= busy_pct else None
    return None


def fleet_busy(cfg, state_dir=None):
    """Reason string when the GPU/fleet is NOT known idle, else None. Fail closed: an undeterminable run.lock state counts as busy.
    Signals (all read-only): marker files, run.lock + extra_locks (hygiene.lock), LLM-using children that outlive run.lock (planner, refill, work supply, explore),
    and a fresh high state/gpu_util.log sample. run.lock alone is NOT enough: run_overnight releases it before those children start."""
    sd = state_dir or qc.state_dir()
    for m in cfg.get("gpu_busy_markers", []):
        if os.path.exists(os.path.join(sd, m)):
            return "gpu-wait marker present: %s" % m
    for lf in [cfg.get("lock_file", "run.lock")] + list(cfg.get("extra_locks") or []):
        h = lock_held(os.path.join(sd, lf))
        if h is True:
            return "%s is held (fleet cycle in flight)" % lf
        if h is None:
            return "%s state unknown (no fuser/lsof): skipping to stay off the GPU" % lf
    pat = _process_running(cfg.get("busy_process_patterns"))
    if pat:
        return "an LLM-using fleet process is running (%s)" % pat
    ub = _gpu_util_busy(os.path.join(sd, cfg.get("gpu_util_log", "gpu_util.log")), float(cfg.get("gpu_util_busy_pct", 25)), float(cfg.get("gpu_util_max_age_s", 1200)))
    if ub:
        return "gpu_util.log shows the GPU busy (%.0f%% %.0f s ago)" % ub
    return None


class RunLock:
    """Exclusive, non-blocking flock on the pilot's OWN lock file (state/card_pilot.lock; never run.lock/hygiene.lock): two overlapping `run`s (a manual run during
    the 03:35 cron, or `--repo X` twice) would otherwise read the same night count and each spend the whole cap. Released by the kernel when the process dies."""

    def __init__(self, path):
        self.path, self.fd = path, None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return None
        self.fd = fd
        return self

    def __exit__(self, *a):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None


# ------------------------------------------------------------------------------------------------------------------------ item selection
def _resolve_ref(rpath, refs):
    for r in refs:
        rc, _, _ = qc.git(rpath, "rev-parse", "--verify", "-q", r + "^{commit}")
        if rc == 0:
            return r
    return None


def in_allow_list(item, rcfg):
    path = item.get("path", "")
    allow = rcfg.get("path_allow") or []
    if allow and not any(re.search(p, path) for p in allow):
        return False
    if any(re.search(p, path) for p in rcfg.get("path_deny") or []):
        return False
    kws = rcfg.get("keyword_allow") or []
    if kws:
        hay = path + " " + item.get("desc", "")
        if not any(re.search(k, hay) for k in kws):
            return False
    return True


def open_items(rpath, ref, rcfg):
    """Open backlog items read from the progress files AT `ref` (git show; the live working tree is never read or touched)."""
    items = []
    for pf in rcfg.get("progress_files") or ["OVERNIGHT_PROGRESS.md"]:
        rc, out, _ = qc.git(rpath, "show", "%s:%s" % (ref, pf))
        if rc != 0:
            continue
        for line in out.splitlines():
            if not re.match(r"^\s*-\s*\[ \]", line):
                continue
            it = cl.parse_item_line(line)
            if not it or any("HUMAN" in t.upper() for t in it["tags"]):
                continue
            items.append(it)
    return items


def already_carded(rows):
    """{(repo, key)} of items that already have a usable card row (a card, or a lint/exec verdict). UNVERIFIED rows without a card are retried."""
    s = set()
    for r in rows:
        if r.get("kind") == "card" and (r.get("card") or r.get("verdict") in ("PASS", "FAIL", "FLAG")):
            s.add((r.get("repo"), r.get("item_key")))
    return s


def failed_attempts(rows):
    """{(repo, key): n} nights-worth of attempts that produced NO card because of the item itself (timeout, bad JSON, crash). Attempts that were cut short by the night
    cap or by the fleet becoming busy are not the item's fault and do not count."""
    n = {}
    for r in rows:
        if r.get("kind") != "card" or r.get("card") or r.get("verdict") != "UNVERIFIED":
            continue
        e = str(r.get("llm_error") or "")
        if "cap reached" in e or "fleet busy" in e:
            continue
        k = (r.get("repo"), r.get("item_key"))
        n[k] = n.get(k, 0) + 1
    return n


def pick_items(cfg, only_repos, rows, limit):
    """[(repo, rpath, ref, item)], round-robin over repos so one repo cannot starve the other; plus excluded-reason counts."""
    carded = already_carded(rows)
    attempts = failed_attempts(rows)
    max_att = _int(cfg.get("max_attempts"), DEFAULT_MAX_ATTEMPTS)
    per = []
    excluded = {}
    seen = set()
    for repo, rcfg in cfg["repos"].items():
        if only_repos and repo not in only_repos:
            continue
        rpath = qc.repo_dir(repo)
        if not rpath:
            excluded["repo clone not found: " + repo] = 1
            continue
        ref = _resolve_ref(rpath, cfg["base_refs"])
        if not ref:
            excluded["no base ref: " + repo] = 1
            continue
        picks = []
        for it in open_items(rpath, ref, rcfg):
            if not in_allow_list(it, rcfg):
                excluded["outside allow-list"] = excluded.get("outside allow-list", 0) + 1
                continue
            ok, why = cl.eligibility(it)           # GDScript/Swift/Kotlin/Vue/non-code: no model call, ever
            if not ok:
                excluded[why] = excluded.get(why, 0) + 1
                continue
            if cl.classify_item(it)["kind"] == "nochange":
                excluded["no-change item"] = excluded.get("no-change item", 0) + 1
                continue
            k = item_key(it["path"], it["desc"])
            if (repo, k) in carded or (repo, k) in seen:
                continue
            seen.add((repo, k))
            if max_att > 0 and attempts.get((repo, k), 0) >= max_att:
                excluded["parked: %d failed attempts" % max_att] = excluded.get("parked: %d failed attempts" % max_att, 0) + 1
                continue
            picks.append((repo, rpath, ref, it))
        picks.sort(key=lambda x: attempts.get((x[0], item_key(x[3]["path"], x[3]["desc"])), 0))   # stable: items that keep failing go to the back
        per.append(picks)
    out = []
    i = 0
    while len(out) < limit and any(i < len(p) for p in per):
        for p in per:
            if i < len(p) and len(out) < limit:
                out.append(p[i])
        i += 1
    return out, excluded


# ------------------------------------------------------------------------------------------------------------------------ the model budget
class Budget:
    """Counts every model request (including failed ones) against the per-night cap; installed over acceptance_card.call_model."""

    def __init__(self, used, cap, idle_fn=None, on_call=None):
        self.used, self.cap, self.item_calls, self.exhausted = used, cap, 0, False
        self.idle_fn, self.on_call, self.busy = idle_fn, on_call, None
        self.cur = None
        self._real = None

    def left(self):
        return self.cap - self.used

    def __enter__(self):
        self._real = ac.call_model
        ac.call_model = self._call
        return self

    def __exit__(self, *a):
        ac.call_model = self._real

    def _call(self, prompt, url, model, key, timeout=ac.LLM_TIMEOUT):
        if self.left() <= 0:
            self.exhausted = True
            raise ac.ModelError("night request cap reached (%d)" % self.cap)
        if self.idle_fn:                               # re-checked right before EVERY request, not just between cards
            why = self.idle_fn()
            if why:
                self.busy = why
                raise ac.ModelError("fleet busy: " + why)
        self.used += 1
        self.item_calls += 1
        if self.on_call:                               # recorded BEFORE the request, so a run killed mid-item still counts it against the night cap
            self.on_call(self.cur)
        return self._real(prompt, url, model, key, timeout)


def _is_model_failure(res):
    d = res.get("details") or {}
    return res["verdict"] == "UNVERIFIED" and not d.get("card") and bool((d.get("llm") or {}).get("errors") or (d.get("llm") or {}).get("error"))


def card_row(repo, ref, it, res, calls, ms):
    d = res.get("details") or {}
    llm = d.get("llm") or {}
    lint = d.get("lint") or {}
    ex = d.get("exec") or {}
    card = d.get("card")
    errs = [e["rule"] for e in lint.get("errors", [])]
    gpu = llm.get("gpu_s")
    return {
        "kind": "card", "ts": res.get("ts") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "night": night_key(), "repo": repo, "base": ref,
        "item_key": item_key(it["path"], it["desc"]), "path": it["path"], "tier": it.get("tier"), "desc": it["desc"][:300],
        "verdict": res["verdict"], "summary": res.get("summary", "")[:300],
        "lint_ok": bool(card) and not errs, "lint_errors": errs, "lint_flags": [e["rule"] for e in lint.get("flags", [])],
        "exec_outcome": ex.get("outcome"), "exec_reason": ex.get("reason"),
        "fail_before": ex.get("outcome") == "failed", "weak": ex.get("outcome") == "passed",
        "risk_class": d.get("risk_class"), "needs_human_review": d.get("needs_human_review"),
        "model_calls": calls, "calls_logged": True, "gpu_s": gpu if gpu is not None else 0.0, "gpu_s_source": "timings" if gpu else "none",
        "wall_s": llm.get("wall_s"), "ms": ms,
        "llm_error": llm.get("error"),
        "card": ({"bullets": card.get("bullets"), "verify_cmd": card.get("verify_cmd"), "files": card.get("files"),
                  "risk_class": card.get("risk_class")} if card else None),
    }


# ------------------------------------------------------------------------------------------------------------------------ run
def run(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="card_pilot_run.py run")
    ap.add_argument("cmd")
    ap.add_argument("--config")
    ap.add_argument("--repo", action="append")
    ap.add_argument("--max-cards", type=int)
    ap.add_argument("--llm-url")
    ap.add_argument("--model")
    ap.add_argument("--dry-run", action="store_true", help="select items and run the idle check, make no model call and write no card row")
    ap.add_argument("--no-record", action="store_true")
    a = ap.parse_args(argv)
    cfg = load_config(a.config)
    url = a.llm_url or os.environ.get("LITELLM_BASE") or cfg["llm"].get("default_url") or ac.DEFAULT_URL
    model = a.model or os.environ.get("OVN_MODEL") or cfg["llm"].get("model") or ac.DEFAULT_MODEL
    limit = a.max_cards if a.max_cards is not None else int(cfg["max_cards"])
    mode = qc.mode(GATE)
    det = {"run": True, "mode_note": "enforce behaves as shadow (no enforce path)" if mode == "enforce" else None, "model_calls": 0, "cards": 0,
           "night": night_key(), "cap": int(cfg["max_requests_per_night"]), "limit": limit}

    def done(v, why, **extra):
        det.update(extra)
        return qc.verdict(v, GATE, ",".join(a.repo) if a.repo else "*", "-", why, det)

    if not ac._loopback(url):
        return done("UNVERIFIED", "refusing non-loopback model url (the pilot talks only to the local litellm); no model call made")
    busy = fleet_busy(cfg)
    if busy:
        return done("UNVERIFIED", "fleet not idle, skipped with zero model calls: " + busy, skipped=busy)
    if a.dry_run:
        return _run_locked(a, cfg, url, model, limit, det, done, None)
    with RunLock(os.path.join(qc.state_dir(), "card_pilot.lock")) as lk:
        if lk is None:
            return done("UNVERIFIED", "another card pilot run is in flight (state/card_pilot.lock held): skipped with zero model calls so the night cap cannot be spent twice", skipped="locked")
        return _run_locked(a, cfg, url, model, limit, det, done, lk)


def _run_locked(a, cfg, url, model, limit, det, done, lk):
    qc.sweep_stale_scratch(repo_paths=[p for p in (qc.repo_dir(r) for r in cfg["repos"]) if p])
    rows = read_rows()                      # read AFTER the lock was taken: the count cannot be stale
    night = night_key()
    used = night_used(rows, night)
    det["requests_used_before"] = used
    if used >= int(cfg["max_requests_per_night"]):
        return done("UNVERIFIED", "per-night request cap already reached (%d/%d), zero model calls" % (used, cfg["max_requests_per_night"]), skipped="cap")
    picks, excluded = pick_items(cfg, a.repo, rows, limit)
    det["excluded"] = excluded
    det["selected"] = len(picks)
    if not picks:
        return done("NA", "no eligible not-yet-carded items in the allow-listed areas")
    if a.dry_run:
        det["dry_run_items"] = [{"repo": r, "path": it["path"], "desc": it["desc"][:100]} for r, _p, _ref, it in picks]
        return done("NA", "dry run: %d item(s) would be carded, no model call made" % len(picks))
    key_fail = 0
    stop = None
    verdicts = {}
    t_run = time.time()
    def _log_call(cur):
        repo_, key_ = cur or (None, None)
        append_row({"kind": "call", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "night": night, "repo": repo_, "item_key": key_})

    with Budget(used, int(cfg["max_requests_per_night"]), idle_fn=lambda: fleet_busy(cfg), on_call=None if a.no_record else _log_call) as bud:
        for n, (repo, rpath, ref, it) in enumerate(picks):
            if n:
                busy = fleet_busy(cfg)
                if busy:
                    stop = "fleet became busy: " + busy
                    break
            if bud.left() <= 0:
                stop = "per-night request cap reached"
                break
            bud.item_calls = 0
            bud.cur = (repo, item_key(it["path"], it["desc"]))
            t0 = time.time()
            ns = types.SimpleNamespace(repo=repo, base=ref, head=None, card_json=None, no_exec=False, repair=False, venv_bin=None,
                                       exec_timeout=int(cfg["exec_timeout"]), llm_url=url, model=model)
            try:
                res = ac.evaluate_item(ns, it, rpath)
            except Exception as ex:  # noqa: BLE001 - one bad item must not kill the run; it is a data point
                res = qc.verdict("UNVERIFIED", ac.GATE, repo, ref, "card evaluation crashed: %s: %s" % (type(ex).__name__, ex), {"item": {}})
            row = card_row(repo, ref, it, res, bud.item_calls, int((time.time() - t0) * 1000))
            if bud.exhausted and not row["card"]:
                row["llm_error"] = row["llm_error"] or "night request cap reached"
            if bud.busy and not row["card"]:
                row["llm_error"] = "fleet busy: " + bud.busy
            if not a.no_record:
                append_row(row)
            verdicts[row["verdict"]] = verdicts.get(row["verdict"], 0) + 1
            det["cards"] += 1 if row["card"] else 0
            if bud.busy:
                stop = "fleet became busy: " + bud.busy
                break
            if _is_model_failure(res):
                key_fail += 1
                if key_fail >= 2:
                    stop = "two consecutive model failures: %s" % (row["llm_error"] or "?")
                    break
            else:
                key_fail = 0
            if bud.exhausted:
                stop = "per-night request cap reached"
                break
        det["model_calls"] = bud.used - used
    det.update(verdicts=verdicts, stopped=stop, wall_s=round(time.time() - t_run, 1))
    if det["cards"] == 0:
        return done("UNVERIFIED", "no card produced (%s)" % (stop or "model failures"))
    return done("PASS", "%d card(s) written in shadow (%s)%s" % (det["cards"], json.dumps(verdicts, sort_keys=True), "; stopped: " + stop if stop else ""))


# ------------------------------------------------------------------------------------------------------------------------ S2 shadow hook
def latest_card(rows, repo, key):
    best = None
    for r in rows:
        if r.get("kind") == "card" and r.get("repo") == repo and r.get("item_key") == key and r.get("card") and (r["card"] or {}).get("verify_cmd"):
            best = r
    return best


def _take_slot(base, n):
    """Non-blocking flock on one of n slot files (base.0 .. base.n-1); returns the held fd or None when all are taken. The kernel frees it if we die."""
    try:
        os.makedirs(os.path.dirname(base), exist_ok=True)
    except OSError:
        return None
    for i in range(n):
        try:
            fd = os.open("%s.%d" % (base, i), os.O_RDWR | os.O_CREAT, 0o644)
        except OSError:
            continue
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except OSError:
            os.close(fd)
    return None


def credit(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="card_pilot_run.py credit")
    ap.add_argument("cmd")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--repo-path")
    ap.add_argument("--head", required=True)
    ap.add_argument("--item")
    ap.add_argument("--exec-timeout", type=int, default=CREDIT_EXEC_TIMEOUT)
    ap.add_argument("--no-stdout", action="store_true")
    ap.add_argument("--no-record", action="store_true")
    a = ap.parse_args(argv)
    text = a.item or os.environ.get("OVN_CC_ITEM", "")
    it = cl.parse_item_line(text if text.lstrip().startswith("-") else "- [x] " + text) if text.strip() else None
    if not it:
        return qc.verdict("UNVERIFIED", CREDIT_GATE, a.repo, a.head, "could not parse the credited item line", {"credit_without_card": None})
    key = item_key(it["path"], it["desc"])
    det = {"item_key": key, "path": it["path"], "card_existed": False, "credit_without_card": True, "verify_passed_at_head": None}
    row = latest_card(read_rows(), a.repo, key)
    if row is None:
        return qc.verdict("FLAG", CREDIT_GATE, a.repo, a.head, "credit_without_card: no S0 card exists for the credited item", det)
    det.update(card_existed=True, credit_without_card=False, card_verdict=row.get("verdict"), card_lint_ok=bool(row.get("lint_ok")))
    verify = row["card"]["verify_cmd"]
    if not row.get("lint_ok"):
        return qc.verdict("FLAG", CREDIT_GATE, a.repo, a.head, "a card exists but it was lint-rejected, its verify_cmd was not executed", det)
    # re-lint with the CURRENT linter before executing anything: a stored command is never trusted blindly
    f, _info = cl.lint_verify(verify, it, None)
    if any(x["severity"] == "error" and x["rule"] in ac.UNSAFE_RULES for x in f):
        return qc.verdict("FLAG", CREDIT_GATE, a.repo, a.head, "stored verify_cmd fails the current safety lint, not executed", det)
    # bounded concurrency: each check is a full checkout + a verify run, and the hook fires once per credited item
    slot = _take_slot(os.path.join(qc.state_dir(), "card_credit.lock"), CREDIT_SLOTS)
    if slot is None:
        return qc.verdict("UNVERIFIED", CREDIT_GATE, a.repo, a.head, "%d credit checks already in flight: skipped (advisory only)" % CREDIT_SLOTS, det)
    try:
        rp = a.repo_path or qc.repo_dir(a.repo)
        qc.sweep_stale_scratch(repo_paths=[rp] if rp and os.path.isdir(rp) else [])
        ex = ac.exec_check(a.repo_path or a.repo, a.head, verify, ac.guess_venv_bin(a.repo), a.exec_timeout,
                           wt_timeout=CREDIT_WT_TIMEOUT, probe_timeout=CREDIT_PROBE_TIMEOUT)
    finally:
        os.close(slot)
    det["exec"] = {k: ex.get(k) for k in ("outcome", "reason", "rc", "ms")}
    if ex["outcome"] == "passed":
        det["verify_passed_at_head"] = True
        return qc.verdict("PASS", CREDIT_GATE, a.repo, a.head, "a card existed and its verify_cmd passes at the credited head", det)
    if ex["outcome"] in ("failed", "broken"):
        det["verify_passed_at_head"] = False
        return qc.verdict("FLAG", CREDIT_GATE, a.repo, a.head, "item credited but its card's verify_cmd FAILS at head (%s)" % ex["reason"], det)
    return qc.verdict("UNVERIFIED", CREDIT_GATE, a.repo, a.head, "card verify could not run at head: %s" % ex["reason"], det)


# ------------------------------------------------------------------------------------------------------------------------ entry
def main(argv):
    if not argv or argv[0] not in ("run", "credit"):
        print("usage: card_pilot_run.py run|credit ...", file=sys.stderr)
        return 2
    gate = CREDIT_GATE if argv[0] == "credit" else GATE
    qc.install_term_handlers()      # `timeout` (SIGTERM) must unwind the finally blocks: no leaked worktree / temp HOME / orphaned verify
    if qc.mode(gate) == "off":
        if "--no-stdout" not in argv:
            print(json.dumps(qc.verdict("NA", gate, "*", "-", "OVN_QA_%s=off: nothing done" % gate.upper(), {"off": True}), sort_keys=True))
        return 0
    argv = list(argv)
    quiet = "--no-stdout" in argv
    if quiet:
        so = sys.stdout
        sys.stdout = open(os.devnull, "w")
    try:
        return qc.main_guard(gate, credit if argv[0] == "credit" else run, [x for x in argv if x != "--no-stdout"])
    finally:
        if quiet:
            sys.stdout = so


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
