#!/usr/bin/env python3
"""box_deadman.py - MAC-SIDE off-box dead-man's switch for the GPU box (2026-10-10, package ops; review findings F5/F2/QA-5).

Why: on 2026-10-10 the box hard-froze/lost power 04:58:40-07:20:55 CDT (2h22m). Every alerting job (ovn_notify.py check/update, the hygiene-stuck check,
qa_block_watch) runs ON the box, so a box outage was silent: nobody was told, nothing was queued, and a promote at 09:00 would have run on stale evidence.

Run it every 10 minutes from launchd (scripts/overnight-queue/com.shrike.box-deadman.plist; NOT installed by the code - the lead installs it).
Read-only: one ssh to the box (key auth, BatchMode), nothing is written on the box, no credential is read or printed. ALWAYS exits 0.

What it checks (one ssh round trip):
  unreachable   ssh to the box fails on every address (Tailscale then LAN)
  stalled       overnight-queue.service is active (or activating) and the queue is not paused, but neither a state/outcomes.jsonl row nor a reports/*.md run report
                (one per run_overnight pass, ~70 s even when idle) is newer than DEADMAN_STALE_S (default 1200 s = 20 min)
  unit_down     overnight-queue.service is neither active nor activating, and the queue is not paused
  llm_down      LiteLLM http://localhost:4000/health/readiness on the box does not answer 200
Alert only after DEADMAN_MISSES (default 2) CONSECUTIVE misses of the same kind (20 min of evidence at the 10-minute cadence), ONE alert per episode, a reminder only
after DEADMAN_REMIND_S (default 6 h), and ONE recovery message when the kind clears (it names the box uptime, so an unclean reboot is visible).
Anti-storm / offline-safe: when ssh fails AND the Mac itself has no internet (cannot reach the ntfy host) the miss is NOT counted ("mac-offline": it is the Mac's problem,
not the box's); a gap of more than DEADMAN_MAX_GAP_S (default 30 min, the Mac slept) resets the miss counters instead of letting stale misses add up. Unreachable
suppresses the other kinds (they cannot be known). A kind whose delivery really failed is retried on the next run (alerted is only recorded on delivery).

DELIVERY PATH (decided + justified; consistent with the 2026-09-30 notification policy, docs: memory project_notification-policy-2026-09-30.md):
  The policy is "every sender posts to $NTFY_SERVER/<topic>; the relay on the box (ovn_notify.py serve, :8099) decides what reaches the phone". On the Mac the relay IS the box,
  so the one outage this script exists to catch is exactly the one where the relay is gone. Therefore:
    1. relay first  - POST $NTFY_SERVER/<topic> with Priority urgent + X-Ovn-Level: emergency. The relay applies its own 3 h per-title dedupe and daily cap; its answer
       (action emergency:sent|deduped|capped) counts as delivered/handled. Recoveries go the same way (they land in the hourly update's "Back up:" line).
    2. direct ntfy.sh fallback - ONLY when the relay is unreachable / refuses / reports failed (always the case for kind "unreachable"). Strictly rate limited here,
       because the reason the relay exists is the anonymous per-IP quota (250/day shared by the Mac and the box): at most 1 direct alert per kind per 3 h
       (DEADMAN_DIRECT_COOLDOWN_S) and at most DEADMAN_DIRECT_DAILY_CAP (default 8) direct posts per 24 h, recorded in the state file. Since alerts are debounced
       state TRANSITIONS (not a per-run message) the direct volume is a handful per outage, orders of magnitude below the quota. A recovery whose alert went direct is
       also sent direct (the phone otherwise sees no resolution for up to an hour); a relay-delivered alert gets a relay recovery.
  A dead-man that depended on the thing it watches would be useless; a dead-man that posted every run would recreate the 2026-09-30 quota incident.

usage:  box_deadman.py [--dry-run] [--status] [--send-test [--direct]]
env:    DEADMAN_STATE_DIR (default ~/.box_deadman) DEADMAN_LOG DEADMAN_SSH (ssh command, default 'ssh -o BatchMode=yes -o ConnectTimeout=10 ...')
        DEADMAN_SSH_TARGETS (space separated user@host, default the Tailscale then the LAN address of the box)
        NTFY_SERVER (relay, as everywhere; unset => relay step skipped) NTFY_TOPIC DEADMAN_DIRECT_URL (default https://ntfy.sh) DEADMAN_NET_URL (internet probe)
        DEADMAN_STALE_S DEADMAN_MISSES DEADMAN_REMIND_S DEADMAN_MAX_GAP_S DEADMAN_BOOT_GRACE_S (default 600: no stalled/unit_down verdict in the first 10 min of uptime)
        DEADMAN_DISABLE=1 (do nothing) DEADMAN_LOG_MAX (bytes before the log rotates to .1, default 524288) DEADMAN_NOW (epoch, tests)
Under the test suite (scripts/test/ntfy_guard.sh exports OVN_NTFY_GUARD_LOG) a direct post to the real ntfy.sh is swallowed and logged there, never sent.
"""
import calendar
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_TOPIC = "shrike_ovn_311380987a"   # same default as ovn_notify.py / pause_guard.sh (public in the repo already)
DEFAULT_TARGETS = "mhintermeister@100.79.64.64 mhintermeister@192.168.68.145"
DEFAULT_SSH = "ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=accept-new"
KINDS = ("unreachable", "stalled", "unit_down", "llm_down")

# ONE remote round trip, POSIX sh, read-only. Each line is key=value; a missing command yields an empty value (never an error).
PROBE = r"""cd "$HOME/overnight-queue" 2>/dev/null || { echo nodir=1; exit 0; }
echo "now=$(date +%s)"
echo "up=$(cut -d. -f1 /proc/uptime 2>/dev/null)"
echo "unit=$(systemctl is-active overnight-queue.service 2>/dev/null)"
echo "paused=$([ -e state/PAUSED ] && echo 1 || echo 0)"
echo "mtime=$(stat -c %Y state/outcomes.jsonl 2>/dev/null)"
echo "last=$(tail -n 1 state/outcomes.jsonl 2>/dev/null | grep -a -o '"ts":"[^"]*"' | head -1 | cut -d'"' -f4)"
echo "rep=$(stat -c %Y "reports/$(ls -t reports 2>/dev/null | head -1)" 2>/dev/null)"
echo "llm=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://localhost:4000/health/readiness 2>/dev/null)"
"""


def env_f(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def now():
    try:
        return float(os.environ["DEADMAN_NOW"])
    except (KeyError, ValueError):
        return time.time()


def state_dir():
    return os.environ.get("DEADMAN_STATE_DIR") or os.path.expanduser("~/.box_deadman")


def state_path():
    return os.path.join(state_dir(), "state.json")


def log(msg, t=None):
    line = "%s %s" % (time.strftime("%F %T", time.localtime(t or now())), msg)
    print(line)
    try:
        p = os.environ.get("DEADMAN_LOG") or os.path.join(state_dir(), "deadman.log")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            if os.path.getsize(p) > env_f("DEADMAN_LOG_MAX", 524288):     # one line per 10 min for years: keep one rotated copy, never grow unbounded
                os.replace(p, p + ".1")
        except OSError:
            pass
        with open(p, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_state():
    try:
        with open(state_path()) as f:
            s = json.load(f)
        if isinstance(s, dict):
            s.setdefault("misses", {})
            s.setdefault("alerted", {})
            s.setdefault("direct_sent", [])
            return s
    except (OSError, ValueError):
        pass
    return {"misses": {}, "alerted": {}, "direct_sent": [], "last_run": 0}


def save_state(s):
    try:
        os.makedirs(state_dir(), exist_ok=True)
        tmp = state_path() + ".tmp"
        with open(tmp, "w") as f:
            json.dump(s, f)
        os.replace(tmp, state_path())
    except OSError as e:
        log("WARN cannot save state: %s" % e)


# ---------------------------------------------------------------- probe
def probe_box():
    """-> (dict|None, target|None). dict = parsed key=value lines of the box; None when ssh failed on every target."""
    targets = (os.environ.get("DEADMAN_SSH_TARGETS") or DEFAULT_TARGETS).split()
    ssh = shlex.split(os.environ.get("DEADMAN_SSH") or DEFAULT_SSH)
    for tgt in targets:
        try:
            r = subprocess.run(ssh + [tgt, PROBE], capture_output=True, text=True, timeout=45)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if r.returncode != 0 or "now=" not in r.stdout:
            continue
        d = {}
        for line in r.stdout.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
        return d, tgt
    return None, None


def internet_ok():
    """True when ANY HTTP answer comes back from the ntfy host (even 429): the Mac has a working network. Only a connection-level failure means offline."""
    url = os.environ.get("DEADMAN_NET_URL") or "https://ntfy.sh/v1/health"
    try:
        with urllib.request.urlopen(url, timeout=8):
            return True
    except urllib.error.HTTPError:
        return True
    except Exception:  # noqa: BLE001 - DNS failure, refused, timeout
        return False


def _iso_epoch(v):
    try:
        return calendar.timegm(time.strptime(v[:19], "%Y-%m-%dT%H:%M:%S"))
    except (ValueError, TypeError):
        return None


def _num(v):
    try:
        return int(float(v))
    except (ValueError, TypeError):
        return None


# ---------------------------------------------------------------- pure verdict
def evaluate(p):
    """probe dict (reachable box) -> {kind: detail-string} for every kind that is BAD right now (empty = healthy). Pure; unit-tested."""
    bad = {}
    up = _num(p.get("up"))
    boxnow = _num(p.get("now"))
    grace = env_f("DEADMAN_BOOT_GRACE_S", 600)
    in_grace = up is not None and up < grace
    unit = p.get("unit", "")
    paused = p.get("paused") == "1"
    stale = env_f("DEADMAN_STALE_S", 1200)
    # liveness heartbeat = the newest of: the last outcomes row, the outcomes file mtime, the newest reports/*.md. An exhausted-idle fleet writes NO outcomes rows
    # (verified live 2026-10-10: 42 min without a row while both lanes idled correctly) but run_overnight.sh writes one report per pass (~every 70 s), so
    # outcomes alone would false-alarm; a long busy attempt writes no report but writes an outcomes row when it ends.
    beats = [b for b in (_iso_epoch(p.get("last", "")), _num(p.get("mtime")), _num(p.get("rep"))) if b]
    last = max(beats) if beats else None
    if p.get("nodir"):
        bad["stalled"] = "the box has no ~/overnight-queue directory"
    elif unit in ("active", "activating") and not paused and not in_grace:
        if last is None:
            bad["stalled"] = "no outcomes row and no run report found although the unit is %s" % unit
        elif boxnow is not None and boxnow - last > stale:
            bad["stalled"] = "no outcomes row or run report for %d min although overnight-queue.service is %s" % ((boxnow - last) // 60, unit)
    elif unit not in ("active", "activating") and not paused and not in_grace:
        bad["unit_down"] = "overnight-queue.service is '%s' (not paused)" % (unit or "unknown")
    if p.get("llm", "") != "200" and not in_grace:
        bad["llm_down"] = "LiteLLM on the box answered '%s' (expected 200)" % (p.get("llm") or "nothing")
    return bad


def decide(state, observed, bad, t, need, remind):
    """observed: set of kinds evaluated this run; bad: {kind: detail} among them. -> (to_alert [(kind, detail)], to_recover [kind]); updates miss counters only."""
    miss, alerted = state["misses"], state["alerted"]
    to_alert, to_recover = [], []
    for k in observed:
        if k in bad:
            miss[k] = miss.get(k, 0) + 1
            if miss[k] >= need:
                a = alerted.get(k)
                if a is None or (remind and t - a.get("ts", 0) >= remind):
                    to_alert.append((k, bad[k]))
        else:
            miss[k] = 0
            if k in alerted:
                to_recover.append(k)
    return to_alert, to_recover


# ---------------------------------------------------------------- delivery
def topic():
    return os.environ.get("NTFY_TOPIC") or DEFAULT_TOPIC


def _post(url, title, body, prio, tags, level="", timeout=10):
    """-> (http_status|0, response text). Never raises."""
    req = urllib.request.Request(url, data=body.encode("utf-8"), method="POST")
    req.add_header("Title", title if title.isascii() else "=?UTF-8?B?%s?=" % __import__("base64").b64encode(title.encode("utf-8")).decode())
    req.add_header("Priority", prio)
    if tags:
        req.add_header("Tags", tags)
    if level:
        req.add_header("X-Ovn-Level", level)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:  # noqa: BLE001
        return 0, ""


def send_relay(title, body, prio, tags, level):
    """-> True when the relay accepted AND really pushed (or already pushed) the alert. 'emergency:failed' (its upstream push failed) and
    'emergency:capped' (daily cap hit: the alert is only buffered into the hourly note, never pushed) are NOT delivered, so the strict direct
    fallback applies. 'emergency:deduped' (the same title was pushed within the cooldown) is handled."""
    base = (os.environ.get("NTFY_SERVER") or "").rstrip("/")
    if not base or "ntfy.sh" in base:
        return False
    code, txt = _post("%s/%s" % (base, topic()), title, body, prio, tags, level)
    if not (200 <= code < 300):
        return False
    try:
        action = json.loads(txt).get("action", "")
    except ValueError:
        return True
    return not (action.endswith(":failed") or action.endswith(":capped"))


def direct_allowed(state, kind, level, t):
    """Strict limiter for the direct ntfy.sh fallback. Alerts: 1 per kind per cooldown; everything: DEADMAN_DIRECT_DAILY_CAP per 24 h."""
    hist = [r for r in state["direct_sent"] if t - r.get("ts", 0) < 86400]
    state["direct_sent"] = hist
    if len(hist) >= env_f("DEADMAN_DIRECT_DAILY_CAP", 8):
        return False
    if level == "emergency" and any(r.get("kind") == kind and r.get("level") == "emergency" and t - r["ts"] < env_f("DEADMAN_DIRECT_COOLDOWN_S", 3 * 3600) for r in hist):
        return False
    return True


def send_direct(state, kind, title, body, prio, tags, level, t):
    """-> 'sent' | 'limited' | 'failed'. 'limited' = deliberately suppressed (strict limiter or test guard): the caller treats it as handled, never retries in a tight loop."""
    base = (os.environ.get("DEADMAN_DIRECT_URL") or "https://ntfy.sh").rstrip("/")
    if "ntfy.sh" in base and os.environ.get("OVN_NTFY_GUARD_LOG"):
        try:
            with open(os.environ["OVN_NTFY_GUARD_LOG"], "a") as f:
                f.write("%s pid=%s box_deadman direct post swallowed :: %s\n" % (time.strftime("%F %T"), os.getpid(), title))
        except OSError:
            pass
        return "limited"
    if not direct_allowed(state, kind, level, t):
        return "limited"
    code, _ = _post("%s/%s" % (base, topic()), title, body, prio, tags)
    ok = 200 <= code < 300
    if ok:
        state["direct_sent"].append({"ts": t, "kind": kind, "level": level})
    return "sent" if ok else "failed"


def deliver(state, kind, title, body, level, t, via_hint="", dry=False):
    """level: emergency | recovery. -> (result, channel) with result 'sent'|'limited'|'failed'|'dry'. Relay first (except when the alert being recovered went direct)."""
    prio, tags, xl = ("urgent", "rotating_light", "emergency") if level == "emergency" else ("default", "white_check_mark", "")
    if dry:
        return "dry", "dry"
    if via_hint != "direct" and kind != "unreachable" and send_relay(title, body, prio, tags, xl):
        return "sent", "relay"
    r = send_direct(state, kind, title, body, prio, tags, level, t)
    return r, "direct"


TEXT = {
    "unreachable": ("🚨 GPU box is DOWN (no ssh)", "The GPU box has not answered ssh for 20+ minutes (checked %s). The fleet, the notification relay and every box-side alert are offline until it is back. Check power / UPS / the box console."),
    "stalled": ("🚨 Fleet stalled: no outcomes", "%s. The queue unit is running but nothing is being recorded - check `journalctl -u overnight-queue -n 50` and LiteLLM."),
    "unit_down": ("🚨 Queue service is DOWN", "%s. Check `systemctl status overnight-queue` on the box."),
    "llm_down": ("🚨 Local AI model is down (Mac probe)", "%s for 20+ minutes. The 27B model / LiteLLM cannot serve the fleet - check `docker ps` on the box."),
}


def run(dry=False):
    t = now()
    if os.environ.get("DEADMAN_DISABLE") == "1":
        return "disabled"
    state = load_state()
    need = int(env_f("DEADMAN_MISSES", 2))
    remind = env_f("DEADMAN_REMIND_S", 6 * 3600)
    max_gap = env_f("DEADMAN_MAX_GAP_S", 1800)
    if state.get("last_run") and t - state["last_run"] > max_gap:
        state["misses"].clear()
    probe, tgt = probe_box()
    out = []
    if probe is None:
        if not internet_ok():
            log("mac-offline: ssh to the box failed and the Mac has no internet - not counting a miss", t)
            state["last_run"] = t
            if not dry:
                save_state(state)
            return "mac-offline"
        observed, bad = {"unreachable"}, {"unreachable": "ssh failed on every address"}
        detail_at = ", ".join((os.environ.get("DEADMAN_SSH_TARGETS") or DEFAULT_TARGETS).split())
    else:
        observed, bad = set(KINDS) - {"unreachable"}, evaluate(probe)
        observed.add("unreachable")   # reachable again => the unreachable episode (if any) is over
        detail_at = tgt
    to_alert, to_recover = decide(state, observed, bad, t, need, remind)
    log("probe: %s | bad=%s misses=%s" % ("unreachable" if probe is None else "up=%ss unit=%s paused=%s llm=%s" % (probe.get("up"), probe.get("unit"), probe.get("paused"), probe.get("llm")),
                                         sorted(bad), {k: v for k, v in state["misses"].items() if v}), t)
    for kind, detail in to_alert:
        title, tmpl = TEXT[kind]
        body = tmpl % (detail_at if kind == "unreachable" else detail)
        res, ch = deliver(state, kind, title, body, "emergency", t, dry=dry)
        log("ALERT %s -> %s via %s" % (kind, res, ch), t)
        out.append("alert:%s:%s:%s" % (kind, res, ch))
        if res in ("sent", "limited"):
            state["alerted"][kind] = {"ts": t, "via": ch}
    for kind in to_recover:
        prev = state["alerted"].get(kind, {})
        up = _num((probe or {}).get("up"))
        title = "✅ GPU box recovered" if kind == "unreachable" else "✅ Recovered: %s" % {"stalled": "fleet outcomes flowing again", "unit_down": "queue service is back", "llm_down": "local AI model is back"}[kind]
        body = "%s is clear again (box uptime %s)." % (kind, ("%d min" % (up // 60)) if up is not None else "unknown")
        if kind == "unreachable" and up is not None and up < 4 * 3600:
            body += " The box restarted %d min ago - an unclean reboot/power loss; the outage window is in the box journal (journalctl --list-boots)." % (up // 60)
        res, ch = deliver(state, kind, title, body, "recovery", t, via_hint=prev.get("via", ""), dry=dry)
        log("RECOVER %s -> %s via %s" % (kind, res, ch), t)
        out.append("recover:%s:%s:%s" % (kind, res, ch))
        if res in ("sent", "limited", "dry"):
            state["alerted"].pop(kind, None)
    state["last_run"] = t
    if not dry:
        save_state(state)
    return " ".join(out) or ("ok" if not bad else "bad:" + ",".join(sorted(bad)))


def main(argv):
    try:
        if "--status" in argv:
            print(json.dumps(load_state(), indent=1))
            return 0
        if "--send-test" in argv:
            state = load_state()
            if "--direct" in argv:
                print("direct:", send_direct(state, "test", "Box deadman test (ignore)", "manual delivery test", "low", "wrench", "test", now()))
                save_state(state)
            else:
                print("relay:", send_relay("Box deadman test (ignore)", "manual delivery test", "low", "wrench", ""))
            return 0
        print(run(dry="--dry-run" in argv))
    except Exception as e:  # noqa: BLE001 - a dead-man must never crash launchd into a restart loop
        try:
            log("ERROR %s: %s" % (type(e).__name__, e))
        except Exception:  # noqa: BLE001
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
