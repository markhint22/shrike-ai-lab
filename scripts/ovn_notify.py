#!/usr/bin/env python3
"""ovn_notify.py - ONE notification policy for the whole fleet (2026-09-30).

Why: ~30 scripts each pushed their own long message to ntfy.sh (shared anonymous per-IP quota of 250/day). The quota ran out, every
alert was dropped for a day, and the phone feed was unreadable. Now:

  * every script still posts to "$NTFY_BASE/<topic>" (NTFY_BASE defaults to https://ntfy.sh, so nothing else in the scripts changes);
    in production NTFY_BASE points at THIS relay (`serve`), which decides what actually reaches the phone:
        EMERGENCY  pushed at once, deduped (same title at most once per 3h), capped per day
                   = production site DOWN, local AI model cannot restart, deploys that need a human (priority urgent),
                     fleet stalled, disk almost full
        DROP       chatty per-cycle/per-hour messages that the hourly update now replaces
        NOTE       everything else: buffered (state/notify_notes.jsonl), never pushed on its own
  * `update`  builds the ONE short hourly message from outcomes.jsonl + the buffered notes and pushes it.
  * `check`   (every 10 min) raises emergencies the scripts cannot see themselves (fleet stalled, model down, disk, relay down).

usage:  ovn_notify.py serve [--port 8099]
        ovn_notify.py update [--dry-run] [--force]
        ovn_notify.py check  [--dry-run]
        ovn_notify.py heartbeat [--dry-run]
        ovn_notify.py escalate --sig S --title T [--body B] --flag OVN_ESC_X [--rolling-h N] [--dry-run]
env:    OVN_NOTIFY_STATE (state dir), OVN_NOTIFY_UPSTREAM, NTFY_TOPIC, OVN_NOTIFY_DAILY_CAP (default 40), OVN_NOTIFY_DISABLE=1 (drop all pushes)
        OVN_IDLE_LINE=0 (no "Lane idle" lines in the hourly update), OVN_IDLE_ALERT=0 (no "Fleet starved" emergency), OVN_IDLE_ALERT_H (default 6)
        OVN_STARVED_PRIORITY=off ("Fleet starved" only when EVERY lane is idle, not when the priority lanes are), OVN_PRIORITY_LANES (default iptv_apps,xlite),
        OVN_DUTY_LINE=0 (no "Lane duty 24h" line in the hourly update)
        2026-11-01 (K4 digest noise), each OVN_*=off|shadow|on, default shadow (shadow = state/notify_shadow.log "would ..." lines, behaviour unchanged; on = enforce):
        OVN_DIGEST_DEDUPE   (one digest per (title with digits folded, UTC hour); two went out at 01:20)
        OVN_EMPTY_ONCE      ('Queue empty' bullet: one line, only when the set of empty repos changes or every OVN_EMPTY_REPEAT_H=6 h)
        OVN_PASSRATE_MIN    ('Pass rate' headline only with >= OVN_PASSRATE_MIN_N=5 good+bad outcomes in the window)
        2026-11-02 (P2 notify quality): OVN_EMPTY_ONCE and OVN_PASSRATE_MIN now default to ON (their shadow logs were clean; OVN_*=off / =shadow are the kill switches).
        OVN_DIGEST_QUIET    (off|shadow|on, default on): no hourly digest when there is nothing to look at ("all good"), UNLESS no heartbeat went out in the last 26 h
                            (then the all-good digest is the only sign of life and keeps being sent: the quiet mode is self-protecting until the heartbeat cron is enabled)
        OVN_NOTIFY_DIGEST_CAP (default 24) / OVN_NOTIFY_EMERGENCY_CAP (default 20): SEPARATE per-24h budgets; OVN_NOTIFY_DAILY_CAP, when set explicitly, stays a total ceiling too.
        `heartbeat` : one priority-3 'ntfy alive <date>' message (never deduped, exempt from every cap) so SILENCE of the channel is detectable; carries sent/capped/dropped
                      counts, the last emergency and '[suppressed N]' for emergencies that were capped/deduped since the previous heartbeat.
        `escalate --sig S --title T --body B --flag OVN_ESC_X [--rolling-h N]`: ONE emergency-class push per signature per local day (mode shadow|on|off, default shadow = notify_shadow.log only);
                      with --rolling-h N the key is a rolling N-hour window (state/notify_escalated_rolling.json), not the calendar day.
        2026-11-04 (Y6 notify fixes 2): the 'Daily prod promote' summary is NEVER dropped any more: it is folded into the next hourly digest as ONE bullet (promoted repos + UNVERIFIED/HELD/BLOCKED lists,
                      state/notify_promote.json, cleared only after a digest was really sent); the research-batch scorecard is ONE weekly digest line (state/notify_scorecard*.json).
                      OVN_ESC_MAC_SUPERVISOR now defaults to ON (once per day; OVN_ESC_MAC_SUPERVISOR=off|shadow is the kill switch).
                      OVN_BULLET_ONCE (off|shadow|on, default on): 'Features ready to test' / 'Batch health' / 'Branch reconcile CONFLICT' bullets show only when their state changed or every
                      OVN_BULLET_REPEAT_H (6) h. The reconcile bullet names repo + branch. 'Suite red' notes/escalations drop the harness's own fixture tests (test_fake_a.sh, test_fail.sh, test_does_not_exist.sh).
"""
import base64
import email.header
import calendar
import glob
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = os.environ.get("OVN_NOTIFY_STATE") or os.path.expanduser("~/overnight-queue/state")
ROOT = os.path.dirname(STATE.rstrip("/")) if os.path.basename(STATE.rstrip("/")) == "state" else os.path.expanduser("~/overnight-queue")
UPSTREAM = os.environ.get("OVN_NOTIFY_UPSTREAM", "https://ntfy.sh").rstrip("/")
TOPIC = os.environ.get("NTFY_TOPIC", "shrike_ovn_311380987a")
DAILY_CAP = int(os.environ.get("OVN_NOTIFY_DAILY_CAP", "40"))
DAILY_CAP_EXPLICIT = "OVN_NOTIFY_DAILY_CAP" in os.environ    # an explicitly set total cap is still honoured (on top of the per-kind budgets); the default 40 is NOT a ceiling any more (N10)
DIGEST_CAP = int(os.environ.get("OVN_NOTIFY_DIGEST_CAP", "24"))
EMERGENCY_CAP = int(os.environ.get("OVN_NOTIFY_EMERGENCY_CAP", "20"))
HEARTBEAT_FRESH_S = 26 * 3600
EMERGENCY_COOLDOWN = 3 * 3600
IDLE_LANE_S = 30 * 60               # a lane with nothing pullable whose last real attempt is older than this is "idle" (hourly update line)
STARVED_DEDUP_S = 12 * 3600         # "Fleet starved" is pushed at most once per 12 h
IDLE_SCAN_BYTES = int(os.environ.get("OVN_IDLE_SCAN_MB", "64")) * 1_000_000   # idle lanes write a skip row every ~3 s: the last real attempt can be far back
NOTE_WINDOW = 6 * 3600
LAN = [ipaddress.ip_network(n) for n in ("127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "::1/128")]

# messages the hourly update replaces - never pushed, never listed
DROP_RE = re.compile(r"overnight queue|backlog refilled|lock contention|lock-orphan|hourly|feature complete", re.I)
# Y6: these two used to be DROPPED. The prod-promote summary (promoted repos + the UNVERIFIED list) never reached the phone; it is now folded into the next digest as one bullet. The research-batch
# scorecard (a history of graded batches, not an action item) becomes one WEEKLY digest line.
PROMOTE_RE = re.compile(r"daily prod promote", re.I)
SCORECARD_RE = re.compile(r"research-batch scorecard", re.I)
# the queue test-suite's own deliberately failing fixtures: never a real "suite red" signal (Y1 fixes the leak at the source; this is the defensive filter in the naming)
FIXTURE_TESTS = ("test_fake_a.sh", "test_fail.sh", "test_does_not_exist.sh")
# messages that are real emergencies by content (in addition to priority urgent / explicit level header)
EMERGENCY_RE = re.compile(r"\bDOWN\b|auto-restart FAILED|fleet stalled|model is down|disk almost full|notification relay", re.I)


def _p(name):
    return os.path.join(STATE, name)


# flags whose shadow log was reviewed clean and that now default to ON (2026-11-02, N6); the env var still switches them off / back to shadow
# 2026-11-03 (S2/F3): OVN_ESC_HYGIENE is ON by default (a hygiene gate stuck >= 4h sat red 6h with only a priority-3 digest line; one fire/day was the sane shadow count). Kill switch: OVN_ESC_HYGIENE=off|shadow.
# OVN_ESC_PROMOTE_RED stays shadow (flip with env after reviewing notify_shadow.log); there is no OVN_ESC_SUITE flag in the code base.
# 2026-11-04 (Y6): OVN_ESC_MAC_SUPERVISOR is ON too (the Mac supervisor sat dead 2 days, its shadow line was the only trace) and so is OVN_BULLET_ONCE.
_DEFAULT_ON = ("OVN_EMPTY_ONCE", "OVN_PASSRATE_MIN", "OVN_DIGEST_QUIET", "OVN_ESC_HYGIENE", "OVN_HB_DROP_CLASSES", "OVN_ESC_MAC_SUPERVISOR", "OVN_BULLET_ONCE")


def _mode(flag):
    """off | shadow | on for an OVN_* flag; unset or unrecognised = shadow (new enforcement behaviour ships log-only), except the _DEFAULT_ON flags (on)."""
    dflt = "on" if flag in _DEFAULT_ON else "shadow"
    v = (os.environ.get(flag) or dflt).strip().lower()
    return v if v in ("off", "shadow", "on") else dflt


def _shadow(flag, msg):
    """One 'would ...' line for a flag in shadow mode. Never raises."""
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(_p("notify_shadow.log"), "a") as f:
            f.write("[%s] %s | would %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now())), flag, msg))
    except OSError:
        pass


def now():
    return time.time()


def clean_title(t):
    """Strip leading emoji/symbols and collapse spaces: '🚨 Deploy failed: X' -> 'Deploy failed: X'."""
    t = re.sub(r"^[^\w(\[]+", "", (t or "").strip())
    return re.sub(r"\s+", " ", t)[:90]


def short(body, n=110):
    """First sentence/line of a body, capped - the hourly update lists headlines only."""
    s = re.sub(r"\s+", " ", (body or "").strip())
    m = re.match(r"(.{20,}?[.!?])(\s|$)", s)
    s = m.group(1) if m else s
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def classify(title, priority="default", level=""):
    if os.environ.get("OVN_NOTIFY_DISABLE"):
        return "drop"
    lv = (level or "").lower()
    if lv == "emergency":
        return "emergency"
    if lv == "digest":
        return "digest"
    if (priority or "").lower() in ("urgent", "max", "5"):
        return "emergency"
    t = title or ""
    if DROP_RE.search(t) and not EMERGENCY_RE.search(t):
        return "drop"
    if EMERGENCY_RE.search(t) and "recover" not in t.lower():
        return "emergency"
    return "note"


def _read_jsonl(path):
    out = []
    try:
        with open(path, "rb") as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    except OSError:
        pass
    return out


def _append_jsonl(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def suite_red_filter(title, body=""):
    """Y6/6: 'Suite red xN: a, b +2' without the harness's own fixture tests. -> (title, body) or None when every named test is a fixture (not a real signal).
    Titles that are not 'Suite red' pass through unchanged."""
    m = re.match(r"^(\W*Suite red x\d+:\s*)(.*)$", title or "", re.I)
    if not m:
        return title, body
    fixture = lambda n: os.path.basename(n.strip().split(":")[0].strip()) in FIXTURE_TESTS
    toks = [x for x in re.split(r"\s*,\s*", m.group(2).strip()) if x]
    keep, more = [], ""
    for tk in toks:
        mm = re.match(r"^(.*?)\s*(\+\d+)$", tk)       # the last token may carry the ' +N' remainder
        name, extra = (mm.group(1), mm.group(2)) if mm else (tk, "")
        if name and not fixture(name):
            keep.append(name)
        if extra:
            more = extra
    if not keep and not more:
        return None
    pre, sep, rest = (body or "").partition("): ")
    if not sep:
        pre, rest = "", body or ""
    segs = [x for x in rest.split("; ") if not any(fx in x for fx in FIXTURE_TESTS)]
    nb = (pre + sep if sep else "") + "; ".join(segs)
    return m.group(1) + ", ".join(keep) + ((" " if keep else "") + more if more else ""), nb


RECONCILE_RE = re.compile(r"branch reconcile conflict(?! cleared)", re.I)


def add_note(title, body, priority, source=""):
    f = suite_red_filter(title, body)
    if f is None:
        _event("filtered", "note", clean_title(title), "only harness fixture tests named: %s" % body)
        return
    title, body = f
    text = short(body)
    if RECONCILE_RE.search(title or ""):
        text = re.sub(r"\s+", " ", body or "").strip()[:600]     # Y6/4: keep the full conflict set (repo + branch), the 110-char cut left 'develop->overnight/...'
    _append_jsonl(_p("notify_notes.jsonl"), {"ts": now(), "title": clean_title(title), "text": text, "prio": priority or "default", "source": source})


def sent_today():
    cutoff = now() - 86400
    return [r for r in _read_jsonl(_p("notify_sent.jsonl")) if r.get("ts", 0) >= cutoff and r.get("ok")]


def _event(action, kind, key="", detail=""):
    """Record that a message was capped / deduped / dropped (the heartbeat reports them; silence must be countable). Trimmed to the last 24 h when it passes 1 MB. Never raises."""
    try:
        p = _p("notify_events.jsonl")
        row = {"ts": now(), "action": action, "kind": kind, "key": key}
        if detail:
            row["detail"] = re.sub(r"\s+", " ", detail).strip()[:200]     # S2/F5: a dropped message's body must stay auditable (what were the 7 'need attention' items?)
        _append_jsonl(p, row)
        if os.path.getsize(p) > 1_000_000:
            cut = now() - 86400
            keep = [r for r in _read_jsonl(p) if r.get("ts", 0) >= cut]
            with open(p + ".tmp", "w") as f:
                for r in keep:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
            os.replace(p + ".tmp", p)
    except OSError:
        pass


def _hdr(v):
    """HTTP header value; non-ASCII (emoji) titles use RFC 2047, which ntfy decodes."""
    return v if v.isascii() else "=?UTF-8?B?%s?=" % base64.b64encode(v.encode("utf-8")).decode()


def fix_header(v):
    """Undo http.server's latin-1 header decoding: raw UTF-8 bytes (emoji) arrive as mojibake ('ð\x9f\x94´'), and RFC 2047 words stay encoded."""
    if not v:
        return v
    try:
        if "=?" in v:
            v = str(email.header.make_header(email.header.decode_header(v)))
        else:
            v = v.encode("latin-1").decode("utf-8")
    except (UnicodeError, ValueError):
        pass
    return v


def _digest_key(key):
    """A digest's dedupe key: the title with digit runs folded ('2 to look at' and '3 to look at' are the SAME hourly digest)."""
    return re.sub(r"\d+", "#", key or "")


def _body_hash(body):
    import hashlib
    return hashlib.md5((body or "").encode("utf-8", "replace")).hexdigest()[:12]


def forward(title, body, priority="default", tags="", kind="emergency", dry=False):
    """Push ONE message upstream, honoring the per-kind daily budgets and the per-title emergency cooldown. Returns 'sent' | 'deduped' | 'capped' | 'failed' | 'dry' | 'disabled'.
    kind 'heartbeat' is never deduped and exempt from every cap. OVN_NOTIFY_DISABLE=1 pushes nothing at all (tests, ntfy_guard.sh)."""
    if os.environ.get("OVN_NOTIFY_DISABLE"):
        return "disabled"
    key = clean_title(title)
    hist = sent_today()
    if kind == "emergency":
        if any(r.get("key") == key and r.get("kind") == "emergency" and now() - r["ts"] < EMERGENCY_COOLDOWN for r in hist):
            if not dry:
                _event("deduped", kind, key)
            return "deduped"
    if kind == "digest" and _mode("OVN_DIGEST_DEDUPE") != "off":
        dk, hr, bh = _digest_key(key), int(now() // 3600), _body_hash(body)
        # same folded title AND same body in the same UTC hour: a changed body (new problem, different items, a boot line) is NEW
        # information and must go out; records written before this field existed (no "bh") never suppress.
        if any(r.get("kind") == "digest" and _digest_key(r.get("key", "")) == dk and int(r.get("ts", 0) // 3600) == hr
               and r.get("bh") == bh for r in hist):
            if _mode("OVN_DIGEST_DEDUPE") == "on":
                if not dry:
                    _event("deduped", kind, key)
                return "deduped"
            if not dry:
                _shadow("OVN_DIGEST_DEDUPE", "suppress a second digest in the same hour: %s" % key)
    if kind != "heartbeat":
        # N10: digests and emergencies have SEPARATE budgets (a day of hourly digests must not starve an emergency); an explicit OVN_NOTIFY_DAILY_CAP is a total ceiling as well
        mine = sum(1 for r in hist if r.get("kind") == kind)
        budget = {"digest": DIGEST_CAP, "emergency": EMERGENCY_CAP}.get(kind)
        total = sum(1 for r in hist if r.get("kind") != "heartbeat")
        if (budget is not None and mine >= budget) or (DAILY_CAP_EXPLICIT and total >= DAILY_CAP) or (budget is None and total >= DAILY_CAP):
            if not dry:
                _event("capped", kind, key)
            return "capped"
    if dry:
        return "dry"
    req = urllib.request.Request("%s/%s" % (UPSTREAM, TOPIC), data=(body or "").encode("utf-8"), method="POST")
    req.add_header("Title", _hdr(title))
    req.add_header("Priority", priority)
    if tags:
        req.add_header("Tags", tags)
    ok, code = False, 0
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            code = r.status
            ok = 200 <= r.status < 300
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0
    _append_jsonl(_p("notify_sent.jsonl"), {"ts": now(), "key": key, "kind": kind, "ok": ok, "code": code, "bh": _body_hash(body)})
    if not ok:
        # an undeliverable EMERGENCY must still reach the next hourly update (a failed hourly update itself is simply retried next hour)
        if kind == "emergency":
            add_note("[undelivered] " + title, body, priority, "forward-failed-%s" % code)
        return "failed"
    return "sent"


def handle_publish(topic, headers, body, source=""):
    """Decide what to do with one publish. headers: dict with lower-case keys. Returns the action string."""
    title = headers.get("title", "") or topic
    prio = headers.get("priority", "default")
    cls = classify(title, prio, headers.get("x-ovn-level", ""))
    if cls == "drop":
        if not os.environ.get("OVN_NOTIFY_DISABLE"):
            _event("dropped", "drop", clean_title(title), body)
        return "dropped"
    if cls == "note" and PROMOTE_RE.search(title or ""):
        fold_promote(body)
        return "folded:promote"
    if cls == "note" and SCORECARD_RE.search(title or ""):
        fold_scorecard(title)
        return "folded:scorecard"
    if cls in ("emergency", "digest"):
        res = forward(title, short(body, 200) if cls == "emergency" else body, "urgent" if cls == "emergency" else "default",
                      headers.get("tags", ""), kind=cls)
        if res in ("deduped", "capped"):
            add_note(title, body, prio, source)
        return "emergency:" + res if cls == "emergency" else "digest:" + res
    add_note(title, body, prio, source)
    return "noted"


# ---------------------------------------------------------------- relay server
class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _allowed(self):
        try:
            ip = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            return False
        return any(ip in n for n in LAN)

    def _reply(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._reply(200 if self.path.startswith("/health") else 404, {"ok": self.path.startswith("/health")})

    def do_POST(self):
        if not self._allowed():
            return self._reply(403, {"error": "forbidden"})
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        topic = self.path.strip("/").split("/")[0] or TOPIC
        hdrs = {k.lower(): fix_header(v) for k, v in self.headers.items()}
        act = handle_publish(topic, hdrs, body, source=self.client_address[0])
        self._reply(200, {"id": "ovn%d" % int(now() * 1000), "event": "message", "topic": topic, "action": act})

    do_PUT = do_POST


def serve(port):
    srv = ThreadingHTTPServer(("0.0.0.0", port), _Handler)
    srv.daemon_threads = True
    srv.serve_forever()


# ---------------------------------------------------------------- hourly update
def _outcomes_since(cutoff):
    path = _p("outcomes.jsonl")
    rows = []
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - 4_000_000))
            for line in f:
                try:
                    d = json.loads(line)
                    t = calendar.timegm(time.strptime(d["ts"][:19], "%Y-%m-%dT%H:%M:%S"))
                except Exception:
                    continue
                if t >= cutoff:
                    rows.append(d)
    except OSError:
        pass
    return rows


def _doable(repo_dir):
    """Open, takeable items. P5-supply-truth: the filter now lives in ovn_supply_filter (one definition shared with ovn_supply_report / fleet_stats)."""
    try:
        import ovn_supply_filter as f
    except ImportError:
        import importlib.util
        spec = importlib.util.spec_from_file_location("ovn_supply_filter", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ovn_supply_filter.py"))
        f = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(f)
    c = f.count_repo(repo_dir)
    return None if c is None else c["doable"]


def _enabled_repos():
    """Repos with at least one enabled lane in tasks.json; None when tasks.json is absent/unreadable (then every repo counts, as before)."""
    try:
        tasks = json.load(open(os.path.join(ROOT, "tasks.json")))
        return {os.path.basename(str(t.get("repo", ""))) for t in tasks if t.get("enabled") is True}
    except Exception:
        return None


def queue_depths():
    out = {}
    active = _enabled_repos()
    for d in sorted(glob.glob(os.path.join(ROOT, "repos", "*"))):
        n = _doable(d)
        name = os.path.basename(d)
        if n is not None and name not in ("social-media-manager", "task-manager-platform", "shrike-labs-website") and (not active or name in active):
            out[name] = n
    return out


def _last_real_attempts():
    """({repo: epoch of its newest NON-skip outcomes row}, epoch of the oldest row scanned or None). Read as bytes: 2 old rows hold NUL bytes
    and are simply unparseable; ts is UTC. Skip rows (class "skipped", status "skip(...)") are the idle loop's own heartbeat, not work; so are landed-late attribution rows."""
    last, first = {}, None
    try:
        size = os.path.getsize(_p("outcomes.jsonl"))
        with open(_p("outcomes.jsonl"), "rb") as f:
            f.seek(max(0, size - IDLE_SCAN_BYTES))
            for line in f:
                if b'"class":"skipped"' in line and first is not None:
                    continue    # fast path: the bulk of the file; only the very first parseable row is needed from a skip row (lower bound)
                try:
                    d = json.loads(line)
                    t = calendar.timegm(time.strptime(d["ts"][:19], "%Y-%m-%dT%H:%M:%S"))
                except Exception:
                    continue
                if first is None:
                    first = t
                if d.get("class") in ("skipped", "landed-late") or str(d.get("status", "")).startswith("skip"):
                    continue   # landed-late (D4) is an attribution row stamped at reconcile time, not a lane attempt: it must not reset the idle-lane clock
                if t > last.get(d.get("repo"), 0):
                    last[d.get("repo")] = t
    except OSError:
        pass
    return last, first


def idle_lanes(depths, at=None):
    """[(repo, idle_seconds)] for active lanes with nothing pullable (depth 0) whose last real attempt is older than IDLE_LANE_S.
    A lane with no real attempt in the scanned window is idle for at least as long as the window reaches back."""
    t = at or now()
    last, first = _last_real_attempts()
    if first is None:
        return []   # no outcomes data at all: cannot tell
    return [(repo, t - last.get(repo, first)) for repo, n in sorted(depths.items()) if n == 0 and t - last.get(repo, first) > IDLE_LANE_S]


def _hours(secs):
    return "%dh" % int(secs // 3600) if secs >= 3600 else "<1h"


def _pass_counts(rows):
    """(good, bad) over outcome rows, using the canonical severity axis (benign/skip/error excluded)."""
    good = sum(1 for r in rows if r.get("severity") == "good")
    bad = sum(1 for r in rows if r.get("severity") == "bad")
    return good, bad


def _pct(good, bad):
    return "%d%%" % round(100.0 * good / (good + bad)) if (good + bad) else "-"


def stats_line(t, rows_hour):
    """'Pass rate: last hour 5/6 (83%) · today 40/46 (87%)' + a per-tier split for today."""
    lt = time.localtime(t)
    midnight = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, 0, 0, 0, 0, 0, -1))
    today = _outcomes_since(midnight)
    gh, bh = _pass_counts(rows_hour)
    gd, bd = _pass_counts(today)
    out = "Pass rate: last hour %d/%d (%s) · today %d/%d (%s)" % (gh, gh + bh, _pct(gh, bh), gd, gd + bd, _pct(gd, bd))
    try:
        min_n = int(os.environ.get("OVN_PASSRATE_MIN_N", "5"))
    except ValueError:
        min_n = 5
    if gd + bd < min_n and _mode("OVN_PASSRATE_MIN") != "off":
        # K4: "Pass rate: today 1/1 (100%)" / "0/2 (0%)" is noise, not a rate
        if _mode("OVN_PASSRATE_MIN") == "on":
            # only the TODAY half of the headline is a too-small sample: keep the last-hour figure and (below) the tier split
            out = "Outcomes today: %d (fewer than %d, no pass rate yet) · last hour %d/%d (%s)" % (gd + bd, min_n, gh, gh + bh, _pct(gh, bh))
        else:
            _shadow("OVN_PASSRATE_MIN", "replace the pass-rate headline (%d good+bad today < %d): %s" % (gd + bd, min_n, out))
    tiers = {}
    for r in today:
        sev = r.get("severity")
        if sev in ("good", "bad"):
            g, b = tiers.get(str(r.get("tier") or "?"), (0, 0))
            tiers[str(r.get("tier") or "?")] = (g + (sev == "good"), b + (sev == "bad"))
    if tiers:
        out += "\nBy tier today: " + " · ".join("T%s %d/%d" % (k, g, g + b) for k, (g, b) in sorted(tiers.items()))
    return out


# 2026-10-10: the credit-integrity change (10-09) split green pushes into 'landed' (credited) and 'landed-uncredited' (pushed, neutral for the
# pass rate). Both are real pushes: the stall emergency counts either as activity; the hourly line shows them separately. OVN_NOTIFY_LANDED_CLASSES
# overrides the activity classes (comma list) if the class vocabulary changes again.
# 2026-10-11 (r11 acct, iptv F7): 'credit-only' (a push that changed only the progress/done files, no code) is NOT activity for the stall emergency: a lane that only
# does no-edit + bookkeeping credits pushes no code, which is exactly the stall "Fleet stalled" exists to flag, so counting it would mask it (reviewer, fixer round 2: safe default).
# The hourly line counts it apart ('+N credit-only') and the pass rate ignores it. To treat it as activity anyway: OVN_NOTIFY_LANDED_CLASSES=landed,landed-uncredited,credit-only.
LANDED = tuple(c.strip() for c in os.environ.get("OVN_NOTIFY_LANDED_CLASSES", "landed,landed-uncredited").split(",") if c.strip()) or ("landed", "landed-uncredited")


# 2026-10-11: the outcomes vocabulary says "reverted" (423 rows on the box on 10-10, zero "revert"), so the hourly 'Undone (broke tests)' line never fired. Accept both.
REVERTED = ("revert", "reverted")


# ---------------------------------------------------------------- box reboot / silent-queue detector (2026-10-10, package ops)
# 2026-10-10: the box hard-froze 04:58:40-07:20:55 CDT (2h22m) and the hourly update never mentioned it (it only said "nothing landed"). The Mac-side
# scripts/box_deadman.py pages while the box is DOWN; this is the box's own after-the-fact line in the hourly update: "Box rebooted 52m ago after a 2h22m
# outage" + whether the queue unit and LiteLLM came back by themselves. Update text only (no push channel of its own); OVN_BOOT_NOTE=0 turns it off; needs a real
# queue root (ROOT/reports) so a test or scratch STATE dir never inherits the host's uptime.
BOOT_WINDOW_S = 2 * 3600            # a boot younger than this is reported (once per boot)
SILENT_S = int(os.environ.get("OVN_SILENT_S", "1800"))   # unit active + not paused + no heartbeat this long = "Queue silent"
BOOT_GRACE_S = 600                  # no "silent" verdict in the first 10 min of uptime (the loop is still starting)


def _uptime_s():
    try:
        with open(os.environ.get("OVN_UPTIME_FILE") or "/proc/uptime") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError, IndexError):
        return None


def _unit_state():
    """systemctl is-active of the queue unit; None when systemd is not available (or OVN_UNIT_STATE unset on a test host)."""
    if "OVN_UNIT_STATE" in os.environ:
        return os.environ["OVN_UNIT_STATE"] or None
    try:
        return subprocess.run(["systemctl", "is-active", "overnight-queue.service"], capture_output=True, text=True, timeout=10).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def _last_heartbeat(cut):
    """Epoch of the newest sign of life at or before `cut`: an outcomes row or a reports/<run>.md (one per run_overnight pass, ~70 s even when every lane is idle -
    an exhausted-idle fleet writes NO outcomes rows). None when neither exists."""
    best = None
    for r in _outcomes_since(cut - 6 * 3600):
        try:
            ts = calendar.timegm(time.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S"))
        except Exception:
            continue
        if ts <= cut and (best is None or ts > best):
            best = ts
    rd = os.path.join(ROOT, "reports")
    try:
        names = sorted((n for n in os.listdir(rd) if n.endswith(".md")), reverse=True)
    except OSError:
        names = []
    for n in names[:2000]:
        try:
            m = os.stat(os.path.join(rd, n)).st_mtime
        except OSError:
            continue
        if m <= cut:
            if best is None or m > best:
                best = m
            break
    return best


def _dur(secs):
    secs = int(secs)
    return "%dh%02dm" % (secs // 3600, secs % 3600 // 60) if secs >= 3600 else "%dm" % (secs // 60)


def boot_notes(at=None):
    """[{'title','text','prio','boot': boot_epoch|None}] for the hourly update: a recent boot (once per boot, with the outage length when the queue went quiet before it) and/or a
    silent queue. Pure function of /proc/uptime, the unit state, outcomes/reports and the clock; never raises."""
    try:
        if os.environ.get("OVN_BOOT_NOTE") == "0" or not os.path.isdir(os.path.join(ROOT, "reports")):
            return []
        t = at or now()
        up = _uptime_s()
        unit = _unit_state()
        paused = os.path.exists(_p("PAUSED"))
        out = []
        if up is not None and up < BOOT_WINDOW_S:
            boot = t - up
            try:
                reported = float(open(_p("notify_boot_reported")).read().strip())
            except (OSError, ValueError):
                reported = None
            if reported is None or abs(reported - boot) > 300:
                prev = _last_heartbeat(boot - 30)
                gap = (boot - prev) if prev else None
                unclean = gap is not None and gap > SILENT_S and not paused
                llm_ok = http_ok(os.environ.get("OVN_LLM_HEALTH_URL", "http://127.0.0.1:4000/health/readiness"))
                running = unit in ("active", "activating") if unit is not None else None
                state = "queue unit %s, LiteLLM %s" % (unit if unit is not None else "unknown", "answering" if llm_ok else "NOT answering")
                title = "Box rebooted %s ago" % _dur(up) + (" after a %s outage" % _dur(gap) if unclean else "")
                text = ("no queue activity for %s before the boot (no clean shutdown trail: check power/UPS/BMC, journalctl --list-boots); " % _dur(gap) if unclean else "clean restart; ") + state
                bad = unclean or running is False or not llm_ok
                out.append({"title": title, "text": text, "prio": "high" if bad else "default", "boot": boot})
        if unit in ("active", "activating") and not paused and (up is None or up >= BOOT_GRACE_S):
            hb = _last_heartbeat(t)
            if hb is not None and t - hb > SILENT_S:
                out.append({"title": "Queue silent %s" % _dur(t - hb), "text": "overnight-queue.service is %s but no outcomes row or run report for %s" % (unit, _dur(t - hb)), "prio": "high", "boot": None})
        return out
    except Exception:  # noqa: BLE001 - an informational line must never break the hourly update
        return []


def duty_line(t):
    """'Lane duty 24h: iptv 16% (9 items/d in), xlite 5% (8/d in)' for the priority lanes, or None. Never raises."""
    try:
        _d = os.path.dirname(os.path.abspath(__file__))
        if _d not in sys.path:
            sys.path.insert(0, _d)
        import ovn_supply_ledger as led
        rep = None
        try:
            with open(_p("supply_ledger.json")) as f:
                cand = json.load(f)
            if isinstance(cand, dict) and 0 <= t - float(cand.get("ts", 0)) < 2 * 3600:
                rep = cand
        except (OSError, ValueError, TypeError):
            pass
        if rep is None:
            rows = led.read_rows(STATE, t - 24 * 3600 - 3 * 3600)
            if not rows:
                return None
            rep = led.compute_report(rows, t, lanes=led.priority_lanes(), windows=(24,))
        return led.digest_line(rep)
    except Exception:
        return None


def supply_report(t, depths=None):
    """The supply report (ovn_supply_report) for the hourly update: state/supply_report.json when < 2 h old, else computed in-process against THIS module's ROOT/STATE.
    None when OVN_SUPPLY_LINE=0 or anything fails (the update must never break on it)."""
    if os.environ.get("OVN_SUPPLY_LINE", "1") == "0":
        return None
    try:
        _d = os.path.dirname(os.path.abspath(__file__))
        if _d not in sys.path:
            sys.path.insert(0, _d)
        import ovn_supply_report as sr
        return sr.fresh_report(t, STATE) or sr.collect(now=t, root=ROOT, state=STATE, depths=depths)
    except Exception:
        return None


def supply_lines(rep):
    """One concise line per starving repo (max OVN_SUPPLY_LINES_MAX, the rest grouped by cause); [] when none or no report."""
    try:
        import ovn_supply_report as sr
        return sr.digest_lines(rep) if rep else []
    except Exception:
        return []


def forecast_lines(t):
    """2026-11-01 (K5): ONE bullet `Supply runway < 24h: ...` from state/supply_forecast.json (ovn_supply_forecast, mode `on` only; < 3 h old). [] otherwise; never raises. OVN_FORECAST_LINE=0 turns it off."""
    if os.environ.get("OVN_FORECAST_LINE", "1") == "0":
        return []
    try:
        _d = os.path.dirname(os.path.abspath(__file__))
        if _d not in sys.path:
            sys.path.insert(0, _d)
        import ovn_supply_forecast as sf
        return sf.digest_lines(sf.fresh_forecast(t, STATE))
    except Exception:
        return []


def slo_lines(t):
    """2026-10-18 (package L5-fleet-slo): ONE line from ovn_fleet_slo when an SLO has been in breach > 1 h (plus one when the SLO summary itself went stale). [] unless
    its mode is `on` (default shadow; `ovn_fleet_slo.py mode off` is the rollback). Reads state/fleet_slo.json of THIS module's STATE; never raises."""
    try:
        _d = os.path.dirname(os.path.abspath(__file__))
        if _d not in sys.path:
            sys.path.insert(0, _d)
        import ovn_fleet_slo as slo
        return slo.update_lines(STATE, t)
    except Exception:
        return []


def empty_cause_text(rep, empty):
    """'excluded: gitlark, shrike-monitor · cap: billwatch' for the 'Queue empty' bullet (primary cause class of each empty repo); None without a report."""
    try:
        by = {}
        for r in empty:
            rec = ((rep or {}).get("repos") or {}).get(r) or {}
            if rec.get("cause_class"):
                by.setdefault(rec["cause_class"], []).append(r)
        if not by:
            return None
        import ovn_supply_report as sr
        return "no supply - " + " · ".join("%s: %s" % (c, ", ".join(rs)) for c, rs in sorted(by.items(), key=lambda kv: sr.CAUSE_ORDER.index(kv[0])))
    except Exception:
        return None


def autodeploy_report(t):
    """state/autodeploy_report.json (ops/box_autodeploy.sh) -> (line, need) for the hourly update; (None, None) when OVN_AUTODEPLOY_LINE=0 or the job never ran.
    A report older than 3 h means the cron job stopped: that is itself a line AND a 'to look at' bullet (a silent deploy job is how fixes sat undeployed for hours, 2026-10-18).
    need = {title, text, prio} when the box is stale beyond the report's stale_threshold_h (default 12) or a deploy/rollback failed. Never raises."""
    if os.environ.get("OVN_AUTODEPLOY_LINE", "1") == "0":
        return None, None
    try:
        p = _p("autodeploy_report.json")
        rep = json.load(open(p))
        if rep.get("mode") == "off":
            return None, None            # a switched-off job is not a stale one
        age = t - float(rep.get("ts") or os.path.getmtime(p))
        if age > 3 * 3600:
            msg = "Box code: autodeploy report is %s old (cron job not running?)" % _hours(age)
            return msg, {"title": "Box autodeploy report stale", "text": "last run %s ago - check ops/box_autodeploy.sh in the crontab" % _hours(age), "prio": "high"}
        line = str(rep.get("line") or "").strip() or None
        need = None
        ahead, oldest = int(rep.get("ahead") or 0), float(rep.get("oldest_age_h") if rep.get("oldest_age_h") is not None else -1)
        thr = float(rep.get("stale_threshold_h") or 12)
        reasons = [str(x) for x in (rep.get("reasons") or [])]
        if rep.get("decision") in ("rollback_failed",):
            need = {"title": "Box deploy ROLLBACK FAILED", "text": "; ".join(reasons[:2]) or "see state/deploy_ledger.jsonl", "prio": "urgent"}
        elif rep.get("decision") == "rolled_back":
            need = {"title": "Box deploy rolled back", "text": "; ".join(reasons[:2]) or "see state/deploy_ledger.jsonl", "prio": "high"}
        elif ahead > 0 and oldest >= thr and rep.get("decision") != "deployed":
            # shadow mode can never deploy: the staleness is still reported every hour (line + bullet) but is not an urgent action item until enforce is on
            enforcing = rep.get("mode") == "enforce"
            need = {"title": "Box code stale: %dh behind %s (%d commits)" % (oldest, rep.get("branch", "claude/feature"), ahead),
                    "text": ("; ".join(reasons[:2]) or "no blocker recorded") + ("" if enforcing else " (shadow mode: nothing deploys automatically; OVN_AUTODEPLOY=enforce or box_autodeploy.sh deploy-sha)"),
                    "prio": "high" if enforcing else "default"}
        return line, need
    except Exception:
        return None, None


EMPTY_STATE = "notify_empty_state.json"


def _empty_gate(empty, t):
    """K4: (emit, sig). The 'Queue empty' bullet is emitted when the SET of empty repos changed since the last digest that carried it, or OVN_EMPTY_REPEAT_H (6) h passed.
    Read-only: do_update records the state (_empty_commit) only after a successful send. mode off = always emit; shadow = always emit + log the would-be suppression."""
    sig = ",".join(empty)
    mode = _mode("OVN_EMPTY_ONCE")
    if mode == "off" or not empty:
        return True, sig
    try:
        rep_s = float(os.environ.get("OVN_EMPTY_REPEAT_H", "6")) * 3600
    except ValueError:
        rep_s = 6 * 3600
    try:
        with open(_p(EMPTY_STATE)) as f:
            st = json.load(f)
        same = st.get("sig") == sig and t - float(st.get("ts", 0)) < rep_s
    except (OSError, ValueError, TypeError, AttributeError):
        same = False
    if same and mode == "shadow":
        _shadow("OVN_EMPTY_ONCE", "drop the unchanged 'Queue empty: %s' bullet" % sig)
        return True, sig
    return (not same), sig


def _empty_commit(sig, t):
    """Record that a digest carried the 'Queue empty' bullet for `sig` (kept at its first-emit time so the 6 h repeat is measured from the last emission)."""
    try:
        os.makedirs(STATE, exist_ok=True)
        try:
            with open(_p(EMPTY_STATE)) as f:
                st = json.load(f)
        except (OSError, ValueError):
            st = {}
        if sig:
            if st.get("sig") != sig or t - float(st.get("ts", 0) or 0) >= _empty_repeat_s():
                st = {"sig": sig, "ts": t}
        else:
            st = {}
        tmp = _p(EMPTY_STATE) + ".tmp"
        with open(tmp, "w") as f:
            json.dump(st, f)
        os.replace(tmp, _p(EMPTY_STATE))
    except OSError:
        pass


def _empty_repeat_s():
    try:
        return float(os.environ.get("OVN_EMPTY_REPEAT_H", "6")) * 3600
    except ValueError:
        return 6 * 3600


# ---------------------------------------------------------------- Y6: folded daily promote / weekly scorecard / bullet gate
PROMOTE_FILE = "notify_promote.json"
SCORECARD_FILE = "notify_scorecard.json"
SCORECARD_SHOWN = "notify_scorecard_shown.json"
BULLET_STATE = "notify_bullet_state.json"
_LAST = {}          # what the last compose_update_ex put into the digest (do_update commits it only after a REAL send)


def _load_json(name, default):
    try:
        with open(_p(name)) as f:
            v = json.load(f)
        return v if isinstance(v, type(default)) else default
    except (OSError, ValueError):
        return default


def _save_json(name, obj):
    try:
        os.makedirs(STATE, exist_ok=True)
        tmp = _p(name) + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, _p(name))
    except OSError:
        pass


def promote_summary(body):
    """'Promoted: a b · UNVERIFIED (...): x' from the daily_promote body (the 'No change' lines and the dated first line are noise); (text, has_warning)."""
    parts, warn = [], False
    for ln in (body or "").splitlines()[1:]:
        ln = ln.strip()
        if re.match(r"^(Promoted:|UNVERIFIED|⚠)", ln):
            parts.append(re.sub(r"\s+", " ", ln))
            warn = warn or ln.startswith("⚠")
    if not parts:
        parts = [short(body, 200)]
    return " · ".join(parts), warn


def fold_promote(body):
    """The daily promote summary is kept until a digest that carries it was really sent (never dropped; the relay used to throw it away). At most the newest 5 pending."""
    rows = _load_json(PROMOTE_FILE, [])
    text, warn = promote_summary(body)
    rows.append({"ts": now(), "text": text, "warn": warn})
    _save_json(PROMOTE_FILE, rows[-5:])


def fold_scorecard(title):
    """Latest research-batch scorecard headline (one weekly digest line)."""
    _save_json(SCORECARD_FILE, {"ts": now(), "text": re.sub(r"^research-batch scorecard:\s*", "", clean_title(title), flags=re.I)})


def scorecard_line(t):
    """-> (line, entry ts) once per OVN_SCORECARD_EVERY_H (168) h and only for a scorecard newer than the one last shown; (None, None) otherwise."""
    sc = _load_json(SCORECARD_FILE, {})
    if not sc.get("ts"):
        return None, None
    shown = _load_json(SCORECARD_SHOWN, {})
    try:
        every = float(os.environ.get("OVN_SCORECARD_EVERY_H", "168")) * 3600
    except ValueError:
        every = 168 * 3600
    if sc["ts"] <= float(shown.get("entry_ts", 0) or 0) or t - float(shown.get("at", 0) or 0) < every:
        return None, None
    return "Research batches (weekly): %s" % sc.get("text", ""), sc["ts"]


GATED_BULLETS = (
    ("features_ready", re.compile(r"^Features ready to test", re.I), "title"),
    ("batch_health", re.compile(r"^Batch health", re.I), "text"),
    ("reconcile_conflict", RECONCILE_RE, "text"),
)


def _feature_names(text):
    """Sorted set of the feature names in a 'Features ready to test' body ('All sub-items landed ... for: a (id1); b (id2); +3 more') - the '+N more' tail is not a name."""
    part = (text or "").split("for:", 1)[-1]
    return sorted({x.strip() for x in part.split(";") if x.strip() and not re.match(r"^\+\d+ more$", x.strip())})


def _bullet_repeat_s():
    try:
        return float(os.environ.get("OVN_BULLET_REPEAT_H", "6")) * 3600
    except ValueError:
        return 6 * 3600


def reconcile_text(text):
    """'billwatch develop→overnight/feature; iptv_apps main→develop' from the reconcile alert body (tokens look like 'develop→overnight/feature:billwatch')."""
    toks = re.findall(r"([\w/.-]+(?:→|->)[\w/.-]+(?:\([^)]*\))?):([A-Za-z0-9_-]+)", text or "")
    seen = []
    for br, repo in toks:
        x = "%s %s" % (repo, br)
        if x not in seen:
            seen.append(x)
    return "; ".join(seen)


def apply_bullet_gate(needs, t):
    """Y6/4+7: reconcile bullet names repo+branch; the three repeating bullets are shown only when their signature changed or OVN_BULLET_REPEAT_H (6) h passed since the last digest that
    carried them. Read-only (state is committed by do_update after a real send); records what it would commit in _LAST['bullets']."""
    mode = _mode("OVN_BULLET_ONCE")
    out, emit = [], []
    try:
        st = _load_json(BULLET_STATE, {})
        for n in needs:
            for key, rx, basis in GATED_BULLETS:
                if rx.search(n["title"]):
                    break
            else:
                out.append(n)
                continue
            if key == "reconcile_conflict":
                nice = reconcile_text(n.get("text", ""))
                if nice:
                    n = dict(n, text=nice)
            # the title carries only a count ('Features ready to test: 2'); the NAMES are in the body, so a changed list must change the signature
            sig = (_digest_key(n["title"]) + "|" + "|".join(_feature_names(n.get("text")))) if basis == "title" else (n.get("text") or n["title"])
            rec = st.get(key) or {}
            same = rec.get("sig") == sig and t - float(rec.get("ts", 0) or 0) < _bullet_repeat_s()
            if mode != "off" and same:
                if mode == "on":
                    continue
                _shadow("OVN_BULLET_ONCE", "drop the unchanged '%s' bullet" % n["title"])
            out.append(n)
            emit.append((key, sig))
    except Exception:       # noqa: BLE001 - a gate problem must never swallow the digest
        return needs
    _LAST["bullets"] = emit
    return out


def commit_digest_state(t):
    """After a digest was REALLY sent: clear the promote rows it carried, stamp the scorecard line, record the gated bullets."""
    if _LAST.get("promote_ts"):
        keep = [r for r in _load_json(PROMOTE_FILE, []) if r.get("ts") not in _LAST["promote_ts"]]
        _save_json(PROMOTE_FILE, keep)
    if _LAST.get("scorecard_ts"):
        _save_json(SCORECARD_SHOWN, {"at": t, "entry_ts": _LAST["scorecard_ts"]})
    if _LAST.get("bullets"):
        st = _load_json(BULLET_STATE, {})
        for key, sig in _LAST["bullets"]:
            rec = st.get(key) or {}
            if rec.get("sig") != sig or t - float(rec.get("ts", 0) or 0) >= _bullet_repeat_s():
                st[key] = {"sig": sig, "ts": t}
        _save_json(BULLET_STATE, st)


def compose_update(window=3600, at=None):
    """Return (title, body, needs_count). Pure function of state + the clock (`at` for tests)."""
    r = compose_update_ex(window, at)
    return r[0], r[1], r[2]


def compose_update_ex(window=3600, at=None):
    """compose_update plus (current empty-repo signature, whether the 'Queue empty' bullet was emitted): (title, body, needs_count, (sig, emitted))."""
    t = at or now()
    rows = _outcomes_since(t - window)
    landed, reverted, uncredited, credit_only = {}, {}, 0, 0
    for r in rows:
        if r.get("class") == "landed":
            landed[r.get("repo")] = landed.get(r.get("repo"), 0) + 1
        elif r.get("class") == "landed-uncredited":
            uncredited += 1
        elif r.get("class") == "credit-only":
            credit_only += 1
        elif r.get("class") in REVERTED:
            reverted[r.get("repo")] = reverted.get(r.get("repo"), 0) + 1
    last_digest = 0.0
    try:
        last_digest = float(open(_p("notify_last_update")).read().strip() or 0)
    except (OSError, ValueError):
        pass
    since = max(last_digest, t - 6 * 3600)
    seen, needs = set(), []
    rank = {"urgent": 3, "max": 3, "high": 2, "default": 1, "low": 0, "min": 0}
    # most severe first, then newest, so the 3 bullets shown are the ones that matter
    for n in sorted(_read_jsonl(_p("notify_notes.jsonl")), key=lambda r: (-rank.get(str(r.get("prio", "default")).lower(), 1), -r.get("ts", 0))):
        if n.get("ts", 0) < since or n["title"] in seen:
            continue
        seen.add(n["title"])
        needs.append(n)
    recovered = [n["title"] for n in needs if re.search(r"recover", n["title"], re.I)]
    needs = [n for n in needs if not re.search(r"recover|start|complete|fixed|\bok\b", n["title"], re.I)]
    _LAST.clear()
    needs = apply_bullet_gate(needs, t)
    lines = [stats_line(t, rows)]
    tot = sum(landed.values())
    unc = " (+%d uncredited)" % uncredited if uncredited else ""
    if credit_only:
        unc += " (+%d credit-only)" % credit_only   # r11 F7: bookkeeping-only pushes are shown, never inside the landed count
    if tot:
        lines.append("Landed %d: %s%s" % (tot, " · ".join("%s %d" % (k, v) for k, v in sorted(landed.items(), key=lambda kv: -kv[1])), unc))
    elif uncredited or credit_only:
        lines.append("Nothing credited this hour%s" % unc)
    else:
        lines.append("Nothing landed this hour")
    if reverted:
        lines.append("Undone (broke tests): " + " · ".join("%s %d" % (k, v) for k, v in sorted(reverted.items())))
    depths = queue_depths()
    low = sorted((v, k) for k, v in depths.items() if v <= 3)
    lines.append("Queues low: " + ", ".join("%s (%d)" % (k, v) for v, k in low) if low else "Queues stocked")
    # 2026-10-09: both lanes sat idle 11.5 of 36 h without any line saying so (an empty queue never tripped "Fleet stalled", which needs >10 queued items).
    # OVN_IDLE_LINE=0 turns the line off. Hourly-update text only: no push channel of its own.
    sup = supply_report(t, depths)   # 2026-10-18: ovn_supply_report (read once: the idle lines, the supply lines and the 'Queue empty' bullet all use it)
    if os.environ.get("OVN_IDLE_LINE", "1") != "0":
        _covered = set(r for r, rec in ((sup or {}).get("repos") or {}).items() if rec.get("starving") and rec.get("line"))   # the supply line below already says it (with the cause)
        for repo, age in idle_lanes(depths, t):
            if repo not in _covered:
                lines.append("Lane idle %s: %s" % (_hours(age), repo))
    # 2026-10-13: duty of the product lanes next to their input rate, so a lane that "ran" 5% of the day is visible in the one hourly update (no push of its own).
    # OVN_DUTY_LINE=0 turns it off. Read from state/supply_ledger.json when fresh (<2 h), else computed in-process by ovn_supply_ledger; any failure = no line.
    if os.environ.get("OVN_DUTY_LINE", "1") != "0":
        dl = duty_line(t)
        if dl:
            lines.append(dl)
    # 2026-10-18: "backlog is out" said nothing about WHY. One line per starving repo: depth, burn, runway, last supply source, root cause (ovn_supply_report). Text only: no push of its own.
    lines.extend(supply_lines(sup))
    lines.extend(forecast_lines(t))   # 2026-11-01 (K5): runway-forecast bullet (mode on only)
    lines.extend(slo_lines(t))   # 2026-10-18: fleet SLO breach > 1 h (mode on only; no push of its own)
    _ad_line, _ad_need = autodeploy_report(t)   # 2026-10-18 (L4): box vs repo drift + gated auto-deploy verdict; text only, no push of its own
    if _ad_line:
        lines.append(_ad_line)
    if _ad_need:
        needs.insert(0, {"title": _ad_need["title"], "text": _ad_need["text"], "prio": _ad_need["prio"], "ts": t})
    if recovered:
        lines.append("Back up: " + ", ".join(re.sub(r"^.*?:\s*", "", t) for t in recovered[:4]))
    # 2026-10-08: an EMPTY active queue is the most important thing to know (the lane is idle) and used to hide under an "all good" title.
    empty = sorted(k for v, k in low if v == 0)
    emitted_empty = ("", False)
    if empty:
        _emit, _sig = _empty_gate(empty, t)
        emitted_empty = (_sig, _emit)
        if _emit:
            needs.insert(0, {"title": "Queue empty: %s" % ", ".join(empty), "text": empty_cause_text(sup, empty) or "that lane has nothing to do until the refuel adds work (work supply runs every 30 min)", "prio": "high", "ts": t})
    promo = None
    prow = [r for r in _load_json(PROMOTE_FILE, []) if isinstance(r, dict) and r.get("text")]
    if prow:   # Y6/1: the daily prod promote (promoted repos, UNVERIFIED/HELD/BLOCKED) is ONE bullet in the next digest and is never dropped
        newest = prow[-1]
        promo = {"title": "Daily prod promote", "text": newest["text"] + (" (+%d earlier summary)" % (len(prow) - 1) if len(prow) > 1 else ""),
                 "prio": "high" if any(r.get("warn") for r in prow) else "default", "ts": t}
        needs.insert(0, promo)
        _LAST["promote_ts"] = [r.get("ts") for r in prow]
    _sc_line, _sc_ts = scorecard_line(t)
    if _sc_line:
        lines.append(_sc_line)
        _LAST["scorecard_ts"] = _sc_ts
    for bn in reversed(boot_notes(t if at else None)):   # 2026-10-10: a reboot / silent queue is at least as important as an empty queue
        needs.insert(0, {"title": bn["title"], "text": bn["text"], "prio": bn["prio"], "ts": t})
    shown = needs[:3]
    if promo is not None and promo not in shown:
        shown[-1] = promo      # a promote summary must never be pushed into the '+N more' tail
    title = ("⚠️ Shrike hourly — %d to look at" % len(needs)) if needs else "✅ Shrike hourly — all good"
    body = "\n".join((["• %s — %s" % (n["title"], n["text"]) if n["text"] and n["text"].lower() not in n["title"].lower() else "• " + n["title"] for n in shown]) +
                     (["(+%d more, see alerts.log)" % (len(needs) - 3)] if len(needs) > 3 else []) + lines)
    return title, body, len(needs), emitted_empty


def do_update(dry=False, force=False):
    try:
        last = float(open(_p("notify_last_update")).read().strip() or 0)
    except (OSError, ValueError):
        last = 0
    if not force and now() - last < 50 * 60:
        return "skipped: last update %dm ago" % ((now() - last) / 60)
    title, body, needs_n, (empty_sig, empty_emitted) = compose_update_ex()
    if dry:
        return "%s\n%s" % (title, body)
    # N6: an "all good" digest is noise; send a digest only when there is something to look at. The daily heartbeat is the proof of life, so the quiet mode only applies while a
    # heartbeat went out in the last 26 h - without one (cron not enabled yet) the all-good digest is the only sign of life and is still sent.
    # the due weekly scorecard line forces the digest out (otherwise an all-good week would never deliver it and commit_digest_state would never run)
    if needs_n == 0 and _mode("OVN_DIGEST_QUIET") != "off" and not force and not _LAST.get("scorecard_ts"):
        if heartbeat_alive():
            if _mode("OVN_DIGEST_QUIET") == "on":
                os.makedirs(STATE, exist_ok=True)
                open(_p("notify_last_update"), "w").write(str(now()))
                return "skipped: nothing to look at (heartbeat covers liveness)"
            _shadow("OVN_DIGEST_QUIET", "skip the all-good digest: %s" % title)
    res = forward(title, body, "default", "", kind="digest")
    if res == "sent":
        commit_digest_state(now())      # only a really delivered digest consumes the promote summary / scorecard line / bullet cooldowns
    if res in ("sent", "capped", "deduped"):
        if res != "deduped" and _mode("OVN_EMPTY_ONCE") != "off":
            if not empty_sig:
                _empty_commit("", now())            # no lane empty any more: the next emptiness is a state change
            elif empty_emitted:
                _empty_commit(empty_sig, now())
        os.makedirs(STATE, exist_ok=True)
        open(_p("notify_last_update"), "w").write(str(now()))
        # a 'deduped' digest was NOT delivered: never mark the boot note reported (it is the only copy of a changed state)
        for bn in (boot_notes() if res != "deduped" else []):     # the boot line is reported ONCE per boot (the next update would otherwise repeat it for up to 2 h)
            if bn.get("boot"):
                open(_p("notify_boot_reported"), "w").write(str(bn["boot"]))
    return "%s (%s)" % (title, res)


# ---------------------------------------------------------------- heartbeat / escalation (2026-11-02, P2 notify quality)
def drop_class(key):
    """Short class label of a dropped title for the heartbeat breakdown: 'feature-complete', 'need-attention', the DROP_RE keyword, or 'other'."""
    k = (key or "").lower()
    if "need attention" in k:
        return "need-attention"
    m = DROP_RE.search(k)
    return m.group(0).replace(" ", "-") if m else "other"


def heartbeat_alive(t=None):
    """True when a heartbeat was delivered within HEARTBEAT_FRESH_S (26 h)."""
    t = now() if t is None else t
    return any(r.get("kind") == "heartbeat" and r.get("ok") and t - r.get("ts", 0) < HEARTBEAT_FRESH_S for r in _read_jsonl(_p("notify_sent.jsonl")))


def cron_beats_line(t=None):
    """K6 (2026-11-03): ONE report line about the per-cron beats (ops/cron_beat.sh -> state/beats/<job>, judged by ops/cron_beats_check.py against scripts/cron_beats.manifest) so silent-success
    and dead crons are distinguishable. Shadow: report only, never a push of its own. OVN_BEATS_IN_HEARTBEAT=auto (default): once the wrappers are installed (a beat exists) the full line appears; before the rollout ONE line 'beats: not rolled out (N wrapped jobs)' says so (Y1; it used to be omitted silently); =on always adds it (also 'not installed'); =off never. A missing checker/manifest or any error -> ''."""
    mode = os.environ.get("OVN_BEATS_IN_HEARTBEAT", "auto").strip().lower()
    if mode in ("off", "0", "no", "false"):
        return ""
    try:
        import importlib.util
        here = os.path.dirname(os.path.abspath(__file__))
        chk = os.environ.get("OVN_BEATS_CHECK") or os.path.join(here, "..", "ops", "cron_beats_check.py")
        man = os.environ.get("OVN_BEATS_MANIFEST") or os.path.join(here, "cron_beats.manifest")
        if not (os.path.isfile(chk) and os.path.isfile(man)):
            return ""
        spec = importlib.util.spec_from_file_location("_ovn_cron_beats_check", chk)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        with open(man, errors="replace") as fh:
            jobs = mod.parse_manifest(fh.read())
        bdir = os.environ.get("OVN_BEATS_DIR") or _p("beats")
        tt = now() if t is None else t
        ct = mod.load_crontab()
        wrapped = mod.wrapped_jobs(ct) if ct is not None else set()
        res = mod.evaluate(jobs, bdir, tt, wrapped=wrapped, seen=mod.track_wrapped(bdir, wrapped, tt))
        if not res["installed"] and mode not in ("on", "1", "yes", "true"):
            # Y1 (2026-11-04): was "" (silently omitted, indistinguishable from a broken checker). Say once, in one short line, that the beats are not rolled out.
            return "beats: not rolled out (%d wrapped jobs%s)" % (len(wrapped), ", no beat yet" if wrapped else "")
        return mod.summary_line(res)[:300]
    except Exception:
        return ""


def heartbeat_text(t=None):
    """-> (title, body). 'ntfy alive YYYY-MM-DD' + 'N sent/24h, M capped, K dropped, last emergency <title> <age>' (+ ' [suppressed N]': emergencies capped/deduped since the previous heartbeat)."""
    t = now() if t is None else t
    sent_rows = _read_jsonl(_p("notify_sent.jsonl"))
    events = _read_jsonl(_p("notify_events.jsonl"))
    cut = t - 86400
    sent = sum(1 for r in sent_rows if r.get("ok") and r.get("kind") != "heartbeat" and r.get("ts", 0) >= cut)
    capped = sum(1 for r in events if r.get("action") == "capped" and r.get("ts", 0) >= cut)
    drop_rows = [r for r in events if r.get("action") == "dropped" and r.get("ts", 0) >= cut]
    dropped = len(drop_rows)
    last_hb = max([r.get("ts", 0) for r in sent_rows if r.get("kind") == "heartbeat" and r.get("ok")] or [cut])
    suppressed = sum(1 for r in events if r.get("kind") == "emergency" and r.get("action") in ("capped", "deduped") and r.get("ts", 0) > last_hb)
    em = [r for r in sent_rows if r.get("ok") and r.get("kind") == "emergency"]
    last = ("%s %s ago" % (em[-1].get("key", "?"), _dur(t - em[-1].get("ts", t)))) if em else "none"
    body = "%d sent/24h, %d capped, %d dropped, last emergency %s" % (sent, capped, dropped, last)
    if dropped and _mode("OVN_HB_DROP_CLASSES") != "off":       # S2/F5: '53 dropped' said nothing; name the classes
        by = {}
        for r in drop_rows:
            c = drop_class(r.get("key", ""))
            by[c] = by.get(c, 0) + 1
        body = body.replace("%d dropped" % dropped, "%d dropped (%s)" % (dropped, ", ".join("%d %s" % (n, c) for c, n in sorted(by.items(), key=lambda kv: (-kv[1], kv[0])))), 1)
    if suppressed:
        body += " [suppressed %d]" % suppressed
    beats = cron_beats_line(t)
    if beats:
        body += "\n" + beats
    return "ntfy alive %s" % time.strftime("%Y-%m-%d", time.localtime(t)), body


def do_heartbeat(dry=False):
    """Send the heartbeat (priority 3 = default). Never deduped, exempt from the caps. -> result string."""
    title, body = heartbeat_text()
    if dry:
        return "%s: %s" % (title, body)
    return "%s: %s -> %s" % (title, body, forward(title, body, "default", "white_check_mark", kind="heartbeat"))


ROLLING_FILE = "notify_escalated_rolling.json"


def escalate(sig, title, body, flag, dry=False, rolling_h=None):
    """ONE emergency-class push per signature per local day (or, with rolling_h, per rolling window of that many hours: a calendar-day key re-armed 2 h after a push at 22:00).
    `flag` is an OVN_* mode variable: off = nothing, shadow = a 'would escalate' line in notify_shadow.log only, on = push.
    The window is only consumed by a delivered push (a capped/failed one retries on the next run). -> 'off' | 'shadow' | 'already-today' | 'already-recent' | 'fixtures-only' | forward()'s result."""
    mode = _mode(flag)
    if mode == "off":
        return "off"
    f = suite_red_filter(title, body)      # Y6/6: a 'Suite red' naming only the harness's own fixture tests is not a signal
    if f is None:
        if not dry:
            _event("filtered", "emergency", clean_title(title), "only harness fixture tests named")
        return "fixtures-only"
    title, body = f
    day = time.strftime("%Y-%m-%d", time.localtime(now()))
    path = _p("notify_escalated.json")
    try:
        seen = json.load(open(path))
        seen = seen if isinstance(seen, dict) else {}
    except (OSError, ValueError):
        seen = {}
    roll_s = float(rolling_h) * 3600 if rolling_h else 0
    roll = _load_json(ROLLING_FILE, {}) if roll_s else {}

    def _recent(key):
        try:
            return now() - float(roll.get(key, 0)) < roll_s
        except (TypeError, ValueError):
            return False

    def _stamp(key):
        roll[key] = now()
        _save_json(ROLLING_FILE, {k: v for k, v in roll.items() if isinstance(v, (int, float)) and now() - v < 7 * 86400})

    if mode == "shadow":
        if roll_s:
            if not _recent("shadow:" + sig) and not dry:
                _shadow(flag, "escalate (emergency push, once per %gh) %s: %s" % (rolling_h, sig, clean_title(title)))
                _stamp("shadow:" + sig)
        elif seen.get("shadow:" + sig) != day and not dry:
            _shadow(flag, "escalate (emergency push, once per day) %s: %s" % (sig, clean_title(title)))
            seen["shadow:" + sig] = day
            _save_escalated(path, seen, day)
        return "shadow"
    if roll_s:
        if _recent(sig):
            return "already-recent"
    elif seen.get(sig) == day:
        return "already-today"
    res = forward(title, body, "urgent", "rotating_light", kind="emergency", dry=dry)
    if res in ("sent", "deduped") and not dry:
        if roll_s:
            _stamp(sig)
        else:
            seen[sig] = day
            _save_escalated(path, seen, day)
    return res


def _save_escalated(path, seen, day):
    try:
        os.makedirs(STATE, exist_ok=True)
        seen = {k: v for k, v in seen.items() if v == day}      # yesterday's signatures are forgotten
        with open(path + ".tmp", "w") as f:
            json.dump(seen, f)
        os.replace(path + ".tmp", path)
    except OSError:
        pass


# ---------------------------------------------------------------- emergency checks
def _bad_since(name, is_bad, minutes):
    """Persist the moment a condition first went bad; True once it has stayed bad for `minutes`."""
    p = _p("notify_bad_" + name)
    if not is_bad:
        try:
            os.remove(p)
        except OSError:
            pass
        return False
    try:
        t0 = float(open(p).read())
    except (OSError, ValueError):
        t0 = now()
        os.makedirs(STATE, exist_ok=True)
        open(p, "w").write(str(t0))
    return now() - t0 >= minutes * 60


def http_ok(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def _priority_lanes():
    """Lanes whose starvation must never be masked by the others: OVN_PRIORITY_LANES (comma list, default iptv_apps,xlite; same variable as ovn_supply_ledger)."""
    return [x.strip() for x in os.environ.get("OVN_PRIORITY_LANES", "iptv_apps,xlite").split(",") if x.strip()]


def starved_check(depths, paused, dry=False):
    """'Fleet starved <N>h': nothing pullable and idle longer than OVN_IDLE_ALERT_H (default 6) for EITHER (a) every active lane (the original rule) OR (b) every
    PRIORITY lane that is active (OVN_PRIORITY_LANES, default iptv_apps,xlite; OVN_STARVED_PRIORITY=off drops (b)), not paused (a pause is deliberate idleness).
    2026-10-13: (a) alone could never fire with seven lanes and two of them starving (the five secondary lanes always had work: iptv idle 11 h, xlite 15 h, no alert),
    the secondary lanes masked the product lanes. Deduped to once per 12 h through state/notify_starved_last, which do_check() writes only after the push was 'sent'
    (a dry run, a capped or a failed push never consume the window). OVN_IDLE_ALERT=0 = off."""
    if paused or os.environ.get("OVN_IDLE_ALERT", "1") == "0" or not depths:
        return []
    # idle_lanes() only lists lanes with nothing pullable, so "every active lane is idle" already means "the queue is empty"
    idle = idle_lanes(depths)
    thr = float(os.environ.get("OVN_IDLE_ALERT_H", "6")) * 3600
    all_idle = len(idle) == len(depths) and all(age > thr for _, age in idle)
    prio = [l for l in _priority_lanes() if l in depths] if os.environ.get("OVN_STARVED_PRIORITY", "on") != "off" else []
    ages = dict(idle)
    prio_idle = bool(prio) and all(ages.get(l, 0) > thr for l in prio)
    if not (all_idle or prio_idle):
        return []
    try:
        if now() - float(open(_p("notify_starved_last")).read().strip()) < STARVED_DEDUP_S:
            return []
    except (OSError, ValueError):
        pass
    # the dedupe marker is NOT written here: do_check() writes it only after forward() returned 'sent' (a capped / failed push must not
    # consume the 12 h window, the emergency would be lost until it expires)
    if all_idle:
        return [("🚨 Fleet starved %s" % _hours(min(age for _, age in idle)),
                 "Every active lane (%s) has been idle for more than %g h and nothing is queued. The fleet needs new work, it will not recover on its own." % (", ".join(sorted(depths)), thr / 3600))]
    others = sorted(k for k in depths if k not in prio and depths[k] > 0)
    return [("🚨 Fleet starved %s" % _hours(min(ages[l] for l in prio)),
             "The priority lane(s) %s have been idle for more than %g h with nothing queued%s. The fleet needs new work for them, it will not recover on its own." % (
                 ", ".join(sorted(prio)), thr / 3600, (" (%s still have work, which is why 'every lane idle' never tripped)" % ", ".join(others)) if others else ""))]


def emergency_checks(dry=False):
    """Return [(title, body)] for conditions that warrant an immediate push."""
    out = []
    llm = os.environ.get("OVN_LLM_HEALTH_URL", "http://127.0.0.1:4000/health/readiness")
    if _bad_since("llm", not http_ok(llm), 20):
        out.append(("🚨 Local AI model is down", "The 27B model has not answered for 20+ minutes, so the fleet cannot work. Check the GPU box."))
    paused = os.path.exists(_p("PAUSED"))
    rows = _outcomes_since(now() - 3 * 3600)
    depths = queue_depths()
    if _bad_since("stalled", (not paused) and sum(depths.values()) > 10 and not any(r.get("class") in LANDED for r in rows), 0):
        out.append(("🚨 Fleet stalled 3h", "Nothing has landed in 3 hours although work is queued and the fleet is not paused."))
    out.extend(starved_check(depths, paused, dry))
    try:
        du = shutil.disk_usage(ROOT)
        if du.used / du.total >= 0.92:
            out.append(("🚨 Disk almost full", "The GPU box disk is %d%% full." % (100 * du.used / du.total)))
    except OSError:
        pass
    return out


MAC_SUP_STALE_S = float(os.environ.get("OVN_MAC_SUP_STALE_H", "3")) * 3600


def mac_supervisor_stale():
    """S2/F6: the Mac mac_jobs_health supervisor (launchd, every 10 min) scp's its health.json to state/mac_jobs_health.json on every run. On 2026-11-02 it silently stopped (no plist loaded) and
    the copy sat 15 h stale with nobody told, because every alert comes FROM the supervisor. -> (stable title, body) when the box copy is older than OVN_MAC_SUP_STALE_H (default 3 h; age from the
    JSON `ts`, else the file mtime), None when fresh or when no copy was ever written (supervisor never deployed). The title carries NO age (a changing title defeats the relay's per-title cooldown)."""
    path = _p("mac_jobs_health.json")
    try:
        mt = os.path.getmtime(path)
    except OSError:
        return None
    try:
        ts = float(json.load(open(path)).get("ts") or mt)
    except (OSError, ValueError, AttributeError, TypeError):
        ts = mt
    age = now() - max(ts, 0)
    if age < MAC_SUP_STALE_S:
        return None
    return ("Mac jobs supervisor silent", "No mac_jobs_health.json from the Mac for %s (limit %g h). The Mac supervisor is not running or the Mac is off/asleep: Mac job alerts (vercel-state-check, claude-queue bridge) are not being checked. "
            "Check `launchctl list | grep mac-jobs-health` on the Mac." % (_hours(age), MAC_SUP_STALE_S / 3600))


def mark_starved_sent():
    os.makedirs(STATE, exist_ok=True)
    open(_p("notify_starved_last"), "w").write(str(now()))


def do_check(dry=False):
    res = []
    for title, body in emergency_checks(dry=dry):
        r = forward(title, body, "urgent", "rotating_light", kind="emergency", dry=dry)
        if r == "sent" and title.startswith("🚨 Fleet starved"):
            mark_starved_sent()
        res.append("%s -> %s" % (title, r))
    ms = mac_supervisor_stale()
    if ms:        # S2/F6: once per day, flag OVN_ESC_MAC_SUPERVISOR (default ON since Y6 = emergency push once a day; shadow = notify_shadow.log only; off = nothing)
        res.append("%s -> %s" % (ms[0], escalate("mac_supervisor", ms[0], ms[1], "OVN_ESC_MAC_SUPERVISOR", dry=dry)))
    return "\n".join(res) or "no emergencies"


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "serve":
        port = int(argv[argv.index("--port") + 1]) if "--port" in argv else 8099
        serve(port)
    elif cmd == "update":
        print(do_update(dry="--dry-run" in argv, force="--force" in argv))
    elif cmd == "check":
        print(do_check(dry="--dry-run" in argv))
    elif cmd == "heartbeat":
        print(do_heartbeat(dry="--dry-run" in argv))
    elif cmd == "escalate":
        def _arg(name, d=""):
            return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else d
        if not _arg("--sig") or not _arg("--title") or not _arg("--flag"):
            print("escalate needs --sig, --title and --flag")
            return 2
        try:
            _roll = float(_arg("--rolling-h")) if _arg("--rolling-h") else None
        except ValueError:
            _roll = None
        print(escalate(_arg("--sig"), _arg("--title"), _arg("--body"), _arg("--flag"), dry="--dry-run" in argv, rolling_h=_roll))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
