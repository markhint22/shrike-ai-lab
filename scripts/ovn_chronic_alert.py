#!/usr/bin/env python3
"""ovn_chronic_alert.py - collapse CHRONIC alert conditions into ONE daily alerts.log line (2026-10-13, platform-night G5, package qa).

Chronic conditions (an idle GPU, a lane sitting at the roadmap-feature floor) re-alerted every few hours: 54 alert lines in one 24h window, of which gpu-util (4) and
roadmap-floor (2) were the same news repeated. Emitters call

    note(state_dir, tag, onset_line, now=None)    -> the alerts.log line written by this call, or None

instead of appending their own line each time the condition still holds. note() keeps state/chronic_alerts.json
    {"active": {tag: {"seen": epoch, "text": "<short text for the digest>"}}, "reported": {tag: {"ts": epoch, "day": "YYYY-MM-DD"}}, "digest_day": "YYYY-MM-DD"}
and decides:
  ONSET   the tag was never reported, or its last report is older than ONSET_GAP_H (36 h = the condition had gone away), or the emitter went QUIET for more than
          QUIET_GAP_H (12 h; both emitters call note() every 15-30 min while the condition holds, so a longer silence means it cleared and has now RECURRED -
          reviewer fix: a clear + recurrence inside 36 h used to be folded into the daily info line): `onset_line` (the emitter's OWN complete
          alerts.log line, original level and wording) is written NOW. A real new alert is never delayed or downgraded.
  REPEAT  anything else: nothing is written by the emitter. Instead, the FIRST note() call of a local day at or after OVN_CHRONIC_DIGEST_HOUR (default 7) writes ONE
          `info | chronic-daily` line listing every tag that is still active (refreshed within ACTIVE_H = 26 h, each with its last-seen time: the emitters run on
          different cadences, so a window shorter than a day would leave the slower emitter's condition out) and was not already reported today, then marks them.
          No active tag to report = no line. At most one digest line per local day, whatever the number of conditions.
`text` for the digest is the part of `onset_line` after the second ' | ' (the message), truncated.

The read-modify-write of chronic_alerts.json (and the alerts.log append) runs under an exclusive flock on state/chronic_alerts.lock (the gpu-util cron and the research
trigger cron are separate processes: unlocked, two could both write an onset/digest line or lose a state update). Lock wait is bounded (LOCK_WAIT_S, 10 s); if it cannot
be taken the call proceeds unlocked (a possible duplicate beats a lost alert).

OVN_CHRONIC_DAILY=off  -> enabled() is False and every emitter keeps its legacy per-condition line + dedupe (the kill switch). Never raises: an unreadable/unwritable
state = the onset line is written (a duplicate beats a lost alert).
"""
import json
import os
import time

try:
    import fcntl
except ImportError:  # pragma: no cover - non-POSIX: no lock, the same fail-open behaviour as a lock timeout
    fcntl = None

ONSET_GAP_H = float(os.environ.get("OVN_CHRONIC_ONSET_GAP_H", "36"))
ACTIVE_H = float(os.environ.get("OVN_CHRONIC_ACTIVE_H", "26"))
QUIET_GAP_H = float(os.environ.get("OVN_CHRONIC_QUIET_H", "12"))
LOCK_WAIT_S = float(os.environ.get("OVN_CHRONIC_LOCK_WAIT_S", "10"))
STATE_FILE = "chronic_alerts.json"
LOCK_FILE = "chronic_alerts.lock"


class _Lock(object):
    """Bounded-wait exclusive flock; never raises, never blocks forever (acquired=False => the caller proceeds unlocked)."""

    def __init__(self, state_dir):
        self.path, self.fd, self.acquired = os.path.join(state_dir, LOCK_FILE), None, False

    def __enter__(self):
        if fcntl is None:
            return self
        try:
            self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o644)
            deadline = time.time() + LOCK_WAIT_S
            while True:
                try:
                    fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.acquired = True
                    break
                except OSError:
                    if time.time() >= deadline:
                        break
                    time.sleep(0.05)
        except OSError:
            pass
        return self

    def __exit__(self, *exc):
        if self.fd is not None:
            try:
                if self.acquired:
                    fcntl.flock(self.fd, fcntl.LOCK_UN)
                os.close(self.fd)
            except OSError:
                pass
        return False


def enabled():
    return os.environ.get("OVN_CHRONIC_DAILY", "on") != "off"


def digest_hour():
    try:
        h = int(os.environ.get("OVN_CHRONIC_DIGEST_HOUR", "7"))
        return h if 0 <= h <= 23 else 7
    except ValueError:
        return 7


def _load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        if isinstance(d, dict):
            d.setdefault("active", {})
            d.setdefault("reported", {})
            return d
    except (OSError, ValueError):
        pass
    return {"active": {}, "reported": {}}


def _save(path, d):
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def _append(state_dir, line):
    with open(os.path.join(state_dir, "alerts.log"), "a") as f:
        f.write(line.rstrip("\n") + "\n")


def _msg(line):
    parts = line.split(" | ", 2)
    return (parts[2] if len(parts) == 3 else line).strip()


def note(state_dir, tag, onset_line, now=None):
    with _Lock(state_dir):
        return _note(state_dir, tag, onset_line, now)


def _note(state_dir, tag, onset_line, now=None):
    now = time.time() if now is None else now
    lt = time.localtime(now)
    today, ts = time.strftime("%Y-%m-%d", lt), time.strftime("%Y-%m-%d %H:%M:%S", lt)
    path = os.path.join(state_dir, STATE_FILE)
    try:
        st = _load(path)
        prev = st["active"].get(tag)
        quiet = bool(prev) and now - float(prev.get("seen", 0)) > QUIET_GAP_H * 3600   # went silent, now back: a recurrence, not a repeat
        st["active"][tag] = {"seen": now, "text": _msg(onset_line)[:240]}
        rep = st["reported"].get(tag)
        wrote = None
        if not rep or quiet or now - float(rep.get("ts", 0)) > ONSET_GAP_H * 3600:
            _append(state_dir, onset_line)
            st["reported"][tag] = {"ts": now, "day": today}
            wrote = onset_line
        elif st.get("digest_day") != today and lt.tm_hour >= digest_hour():
            st["digest_day"] = today
            due = sorted(t for t, a in st["active"].items()
                         if now - float(a.get("seen", 0)) <= ACTIVE_H * 3600 and st["reported"].get(t, {}).get("day") != today)
            if due:
                body = "; ".join("%s: %s (last seen %s)" % (t, st["active"][t]["text"], time.strftime("%H:%M", time.localtime(float(st["active"][t]["seen"])))) for t in due)
                wrote = "[%s] info | chronic-daily | %d chronic condition(s) still active (one line per day; first reports were earlier): %s" % (ts, len(due), body)
                _append(state_dir, wrote)
                for t in due:
                    st["reported"][t] = {"ts": now, "day": today}
        for t in [t for t, a in st["active"].items() if now - float(a.get("seen", 0)) > ONSET_GAP_H * 3600]:
            del st["active"][t]
        _save(path, st)
        return wrote
    except Exception:  # noqa: BLE001 - observability must never fail its caller; a duplicate line beats a lost alert
        try:
            _append(state_dir, onset_line)
            return onset_line
        except OSError:
            return None
