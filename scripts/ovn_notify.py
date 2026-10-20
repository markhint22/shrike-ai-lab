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
        OVN_IDLE_LINE=0 (no "Lane idle" lines in the hourly update), OVN_IDLE_ALERT=0 (no "Fleet starved" emergency), OVN_IDLE_ALERT_H (default 6)
        OVN_STARVED_PRIORITY=off ("Fleet starved" only when EVERY lane is idle, not when the priority lanes are), OVN_PRIORITY_LANES (default iptv_apps,xlite),
        OVN_DUTY_LINE=0 (no "Lane duty 24h" line in the hourly update)
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
IDLE_LANE_S = 30 * 60               # a lane with nothing pullable whose last real attempt is older than this is "idle" (hourly update line)
STARVED_DEDUP_S = 12 * 3600         # "Fleet starved" is pushed at most once per 12 h
IDLE_SCAN_BYTES = int(os.environ.get("OVN_IDLE_SCAN_MB", "64")) * 1_000_000   # idle lanes write a skip row every ~3 s: the last real attempt can be far back
NOTE_WINDOW = 6 * 3600
LAN = [ipaddress.ip_network(n) for n in ("127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "::1/128")]

# messages the hourly update replaces - never pushed, never listed
DROP_RE = re.compile(r"overnight queue|backlog refilled|lock contention|lock-orphan|hourly|daily prod promote|feature complete|research-batch scorecard", re.I)  # scorecard: a history of graded batches, not an action item (stays in logs/ovn_batch_scorecard.log)
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


def compose_update(window=3600, at=None):
    """Return (title, body, needs_count). Pure function of state + the clock (`at` for tests)."""
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
    if empty:
        needs.insert(0, {"title": "Queue empty: %s" % ", ".join(empty), "text": empty_cause_text(sup, empty) or "that lane has nothing to do until the refuel adds work (work supply runs every 30 min)", "prio": "high", "ts": t})
    for bn in reversed(boot_notes(t if at else None)):   # 2026-10-10: a reboot / silent queue is at least as important as an empty queue
        needs.insert(0, {"title": bn["title"], "text": bn["text"], "prio": bn["prio"], "ts": t})
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
        for bn in boot_notes():     # the boot line is reported ONCE per boot (the next update would otherwise repeat it for up to 2 h)
            if bn.get("boot"):
                open(_p("notify_boot_reported"), "w").write(str(bn["boot"]))
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
