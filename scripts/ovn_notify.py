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
env:    OVN_NOTIFY_STATE (state dir), OVN_NOTIFY_UPSTREAM, NTFY_TOPIC, OVN_NOTIFY_DAILY_CAP (default 40), OVN_NOTIFY_DISABLE=1 (drop all pushes)
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
EMERGENCY_COOLDOWN = 3 * 3600
NOTE_WINDOW = 6 * 3600
LAN = [ipaddress.ip_network(n) for n in ("127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "::1/128")]

# messages the hourly update replaces - never pushed, never listed
DROP_RE = re.compile(r"overnight queue|backlog refilled|lock contention|lock-orphan|hourly|daily prod promote|feature complete", re.I)
# messages that are real emergencies by content (in addition to priority urgent / explicit level header)
EMERGENCY_RE = re.compile(r"\bDOWN\b|auto-restart FAILED|fleet stalled|model is down|disk almost full|notification relay", re.I)


def _p(name):
    return os.path.join(STATE, name)


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


def add_note(title, body, priority, source=""):
    _append_jsonl(_p("notify_notes.jsonl"), {"ts": now(), "title": clean_title(title), "text": short(body), "prio": priority or "default", "source": source})


def sent_today():
    cutoff = now() - 86400
    return [r for r in _read_jsonl(_p("notify_sent.jsonl")) if r.get("ts", 0) >= cutoff and r.get("ok")]


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


def forward(title, body, priority="default", tags="", kind="emergency", dry=False):
    """Push ONE message upstream, honoring the daily cap and the per-title emergency cooldown. Returns 'sent' | 'deduped' | 'capped' | 'failed' | 'dry'."""
    key = clean_title(title)
    hist = sent_today()
    if kind == "emergency":
        if any(r.get("key") == key and r.get("kind") == "emergency" and now() - r["ts"] < EMERGENCY_COOLDOWN for r in hist):
            return "deduped"
    if len(hist) >= DAILY_CAP:
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
    _append_jsonl(_p("notify_sent.jsonl"), {"ts": now(), "key": key, "kind": kind, "ok": ok, "code": code})
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
        return "dropped"
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
    try:
        lines = open(os.path.join(repo_dir, "OVERNIGHT_PROGRESS.md"), errors="replace").read().split("\n")
    except OSError:
        return None
    bad = re.compile(r"AUTO-SKIP|HUMAN-ONLY|human/|\[CLAUDE\]|BLOCKED ITEM|\(retired-", re.I)   # same filter as run_overnight/queue_refill (a bare "human" matched ordinary item text)
    return sum(1 for l in lines if l.startswith("- [ ]") and not bad.search(l))


def queue_depths():
    out = {}
    for d in sorted(glob.glob(os.path.join(ROOT, "repos", "*"))):
        n = _doable(d)
        if n is not None and os.path.basename(d) not in ("social-media-manager", "task-manager-platform", "shrike-labs-website"):
            out[os.path.basename(d)] = n
    return out


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
    tiers = {}
    for r in today:
        sev = r.get("severity")
        if sev in ("good", "bad"):
            g, b = tiers.get(str(r.get("tier") or "?"), (0, 0))
            tiers[str(r.get("tier") or "?")] = (g + (sev == "good"), b + (sev == "bad"))
    if tiers:
        out += "\nBy tier today: " + " · ".join("T%s %d/%d" % (k, g, g + b) for k, (g, b) in sorted(tiers.items()))
    return out


def compose_update(window=3600, at=None):
    """Return (title, body, needs_count). Pure function of state + the clock (`at` for tests)."""
    t = at or now()
    rows = _outcomes_since(t - window)
    landed, reverted = {}, {}
    for r in rows:
        if r.get("class") == "landed":
            landed[r.get("repo")] = landed.get(r.get("repo"), 0) + 1
        elif r.get("class") == "revert":
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
    lines = [stats_line(t, rows)]
    tot = sum(landed.values())
    if tot:
        lines.append("Landed %d: %s" % (tot, " · ".join("%s %d" % (k, v) for k, v in sorted(landed.items(), key=lambda kv: -kv[1]))))
    else:
        lines.append("Nothing landed this hour")
    if reverted:
        lines.append("Undone (broke tests): " + " · ".join("%s %d" % (k, v) for k, v in sorted(reverted.items())))
    depths = queue_depths()
    low = sorted((v, k) for k, v in depths.items() if v <= 3)
    lines.append("Queues low: " + ", ".join("%s (%d)" % (k, v) for v, k in low) if low else "Queues stocked")
    if recovered:
        lines.append("Back up: " + ", ".join(re.sub(r"^.*?:\s*", "", t) for t in recovered[:4]))
    shown = needs[:3]
    title = ("⚠️ Shrike hourly — %d to look at" % len(needs)) if needs else "✅ Shrike hourly — all good"
    body = "\n".join((["• %s — %s" % (n["title"], n["text"]) if n["text"] and n["text"].lower() not in n["title"].lower() else "• " + n["title"] for n in shown]) +
                     (["(+%d more, see alerts.log)" % (len(needs) - 3)] if len(needs) > 3 else []) + lines)
    return title, body, len(needs)


def do_update(dry=False, force=False):
    try:
        last = float(open(_p("notify_last_update")).read().strip() or 0)
    except (OSError, ValueError):
        last = 0
    if not force and now() - last < 50 * 60:
        return "skipped: last update %dm ago" % ((now() - last) / 60)
    title, body, _ = compose_update()
    if dry:
        return "%s\n%s" % (title, body)
    res = forward(title, body, "default", "", kind="digest")
    if res in ("sent", "capped"):
        os.makedirs(STATE, exist_ok=True)
        open(_p("notify_last_update"), "w").write(str(now()))
    return "%s (%s)" % (title, res)


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


def emergency_checks():
    """Return [(title, body)] for conditions that warrant an immediate push."""
    out = []
    llm = os.environ.get("OVN_LLM_HEALTH_URL", "http://127.0.0.1:4000/health/readiness")
    if _bad_since("llm", not http_ok(llm), 20):
        out.append(("🚨 Local AI model is down", "The 27B model has not answered for 20+ minutes, so the fleet cannot work. Check the GPU box."))
    paused = os.path.exists(_p("PAUSED"))
    rows = _outcomes_since(now() - 3 * 3600)
    depths = queue_depths()
    if _bad_since("stalled", (not paused) and sum(depths.values()) > 10 and not any(r.get("class") == "landed" for r in rows), 0):
        out.append(("🚨 Fleet stalled 3h", "Nothing has landed in 3 hours although work is queued and the fleet is not paused."))
    try:
        du = shutil.disk_usage(ROOT)
        if du.used / du.total >= 0.92:
            out.append(("🚨 Disk almost full", "The GPU box disk is %d%% full." % (100 * du.used / du.total)))
    except OSError:
        pass
    return out


def do_check(dry=False):
    res = []
    for title, body in emergency_checks():
        res.append("%s -> %s" % (title, forward(title, body, "urgent", "rotating_light", kind="emergency", dry=dry)))
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
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
