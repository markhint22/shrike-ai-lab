"""ovn_notify.py idle-lane signal (2026-10-09): the hourly update's "Lane idle <N>h: <repo>" line and the "Fleet starved <N>h" emergency.

Before: "Fleet stalled 3h" needed sum(depths) > 10, so an EMPTY queue never raised anything and both lanes sat idle 11.5 of 36 h.
Fixture: a real-shaped outcomes.jsonl read as BYTES (two NUL-byte lines in the middle), skip rows (class "skipped", the idle loop's own heartbeat) mixed with
real attempts, a fake root with tasks.json + per-repo OVERNIGHT_PROGRESS.md, and an injected clock (N.now). Nothing here touches the network: urlopen is a counter.
usage: test_notify_idle_lane.py   env: OVN_NOTIFY_SRC=<path to a (mutated) ovn_notify.py> (used by the .sh wrapper's mutation checks)"""
import calendar, importlib.util, json, os, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.environ.get("OVN_NOTIFY_SRC") or os.path.join(ROOT, "scripts", "ovn_notify.py")
T = tempfile.mkdtemp()
Q = os.path.join(T, "q")
ST = os.path.join(Q, "state")
os.makedirs(ST)
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_test", OVN_NOTIFY_DAILY_CAP="50", OVN_NOTIFY_UPSTREAM="http://127.0.0.1:9", OVN_LLM_HEALTH_URL="http://127.0.0.1:9/x")
for k in ("OVN_IDLE_LINE", "OVN_IDLE_ALERT", "OVN_IDLE_ALERT_H", "OVN_NOTIFY_DISABLE"):
    os.environ.pop(k, None)
spec = importlib.util.spec_from_file_location("ovn_notify_idle", SRC)
N = importlib.util.module_from_spec(spec)
spec.loader.exec_module(N)

ok_n = bad_n = 0


def ok(label, cond):
    global ok_n, bad_n
    if cond:
        ok_n += 1
        print("  ok   " + label)
    else:
        bad_n += 1
        print("  FAIL " + label)


BASE = calendar.timegm((2026, 10, 9, 12, 0, 0))   # the injected "now" (UTC)
CLOCK = [BASE]
N.now = lambda: CLOCK[0]
N.http_ok = lambda *a, **k: True                   # the model-health probe must not count as network traffic
URLOPEN = []


class _Resp:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *a): return False


def _urlopen(req, timeout=0):
    URLOPEN.append(req.full_url)
    return _Resp()


N.urllib.request.urlopen = _urlopen
N.shutil.disk_usage = lambda p: __import__("collections").namedtuple("du", "total used free")(100, 40, 60)      # the host's real disk fullness must not leak into the emergency list (a 92%-full dev Mac did)


def iso(ago_s, at=None):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime((at or BASE) - ago_s))


def row(repo, ago_s, skip=False):
    if skip:
        return {"ts": iso(ago_s), "repo": repo, "id": "ongoing-" + repo, "type": "aider_fix", "class": "skipped", "severity": "expected", "status": "skip(exhausted)", "fail_reason": "queue-exhausted"}
    return {"ts": iso(ago_s), "repo": repo, "id": "item-1", "type": "aider_fix", "class": "landed", "severity": "good", "status": "landed"}


def write_outcomes(rows, compact=True):
    """Compact JSON lines as the real writer emits them, plus two NUL-byte garbage lines in the middle (the 2 old corrupt rows)."""
    lines = [json.dumps(r, separators=(",", ":") if compact else None).encode() for r in rows]
    mid = len(lines) // 2
    lines[mid:mid] = [b'{"ts":"2026-10-0\x00\x00\x00 broken', b'\x00\x00\x00\x00']
    with open(os.path.join(ST, "outcomes.jsonl"), "wb") as f:
        f.write(b"\n".join(lines) + b"\n")


def set_queue(depths, enabled=("iptv_apps", "xlite")):
    os.makedirs(Q, exist_ok=True)
    for name, n in depths.items():
        d = os.path.join(Q, "repos", name)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w").write("# progress\n" + "".join("- [ ] item %d\n" % i for i in range(n)) + "- [x] done\n")
    json.dump([{"repo": "repos/" + r, "enabled": True} for r in enabled] + [{"repo": "repos/billwatch", "enabled": False}], open(os.path.join(Q, "tasks.json"), "w"))


def reset():
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    CLOCK[0] = BASE
    del URLOPEN[:]


H = 3600
# ======================================================================= (a) hourly update line
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 2 * H + 5 * 60), row("iptv_apps", 2 * H), row("xlite", 10 * 60)] + [row("iptv_apps", s, skip=True) for s in range(5, 600, 3)] + [row("xlite", s, skip=True) for s in range(2, 400, 3)])
title, body, needs = N.compose_update(at=BASE)
ok("idle line: last NON-skip row 2h ago + nothing pullable -> 'Lane idle 2h: iptv_apps' (skip rows from seconds ago do not count as activity)", "Lane idle 2h: iptv_apps" in body.split("\n"))
ok("a lane with a real attempt 10 min ago gets no idle line", "xlite" not in "".join(l for l in body.split("\n") if l.startswith("Lane idle")))
ok("the existing 'Queue empty:' text is kept", any(l.startswith("• Queue empty: ") for l in body.split("\n")) and title.startswith("⚠️"))
ok("NUL-byte lines in the middle of outcomes.jsonl are ignored (no crash, rows around them still counted)", N._last_real_attempts()[0].get("iptv_apps") == BASE - 2 * H)

# skip rows ONLY in the last hours, one old real row: still idle, measured from the real row
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 5 * H), row("xlite", 40 * 60)] + [row("iptv_apps", s, skip=True) for s in range(1, 3000, 7)] + [row("xlite", s, skip=True) for s in range(1, 3000, 7)])
b = N.compose_update(at=BASE)[1].split("\n")
ok("skip rows only since the last real attempt -> still idle, measured from the real row (5h)", "Lane idle 5h: iptv_apps" in b)
ok("idle 40 min (< 1h) is shown as '<1h'", "Lane idle <1h: xlite" in b)

# skip rows that miss the byte fast path (spaced JSON, or only a status of skip(...)) must still not count as a real attempt
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
r_spaced = row("iptv_apps", 60, skip=True)
r_status = {"ts": iso(90), "repo": "xlite", "status": "skip(exhausted)"}
write_outcomes([row("iptv_apps", 4 * H), row("xlite", 3 * H), r_spaced, r_status], compact=False)
b = N.compose_update(at=BASE)[1].split("\n")
ok("a skip row in spaced JSON (no byte fast path) and a status-only skip row are not activity", "Lane idle 4h: iptv_apps" in b and "Lane idle 3h: xlite" in b)

# a lane with NO real row in the scanned window: idle at least as long as the window reaches back
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 8 * H, skip=True), row("xlite", 10 * 60), row("iptv_apps", 5, skip=True)])
ok("no real attempt anywhere in the scanned window -> idle for (at least) the window length", "Lane idle 8h: iptv_apps" in N.compose_update(at=BASE)[1].split("\n"))

# boundaries and negative controls
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 30 * 60), row("xlite", 31 * 60)])
b = N.compose_update(at=BASE)[1].split("\n")
ok("exactly 30 min since the last attempt is NOT idle yet; 31 min is", not any("iptv_apps" in l for l in b if l.startswith("Lane idle")) and "Lane idle <1h: xlite" in b)
reset()
set_queue({"iptv_apps": 4, "xlite": 0})
write_outcomes([row("iptv_apps", 5 * H), row("xlite", 5 * H)])
b = N.compose_update(at=BASE)[1].split("\n")
ok("pullable > 0 -> that lane is not idle even though it has not attempted anything for 5h", not any("iptv_apps" in l for l in b if l.startswith("Lane idle")) and "Lane idle 5h: xlite" in b)
set_queue({"iptv_apps": 0, "xlite": 0, "billwatch": 0})
write_outcomes([row("iptv_apps", 3 * H), row("xlite", 3 * H), row("billwatch", 9 * H)])
ok("a lane that is not enabled in tasks.json is never reported", not any("billwatch" in l for l in N.compose_update(at=BASE)[1].split("\n") if l.startswith("Lane idle")))
os.remove(os.path.join(ST, "outcomes.jsonl"))
ok("no outcomes file -> no idle lines and no crash", not any(l.startswith("Lane idle") for l in N.compose_update(at=BASE)[1].split("\n")))
os.environ["OVN_IDLE_LINE"] = "0"
write_outcomes([row("iptv_apps", 3 * H), row("xlite", 3 * H)])
ok("kill switch OVN_IDLE_LINE=0 removes the idle lines", not any(l.startswith("Lane idle") for l in N.compose_update(at=BASE)[1].split("\n")))
del os.environ["OVN_IDLE_LINE"]
ok("...and they are back without it", any(l.startswith("Lane idle") for l in N.compose_update(at=BASE)[1].split("\n")))
before = len(URLOPEN)
N.compose_update(at=BASE)
ok("composing the hourly text pushes nothing (no new channel)", len(URLOPEN) == before)


def starved(res):
    return [e for e in res if "starved" in e[0]]


# ======================================================================= (b) Fleet starved emergency
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 7 * H), row("xlite", 7 * H + 120)] + [row("iptv_apps", s, skip=True) for s in range(1, 500, 3)])
res = starved(N.emergency_checks())
ok("both lanes idle 7h + empty queue -> exactly one 'Fleet starved 7h' emergency", len(res) == 1 and res[0][0] == "🚨 Fleet starved 7h" and "iptv_apps" in res[0][1] and "xlite" in res[0][1])
ok("computing the emergency list alone never consumes the dedupe window (only a 'sent' push does)", not os.path.exists(os.path.join(ST, "notify_starved_last")) and len(starved(N.emergency_checks())) == 1)
orig_forward = N.forward
FWD = []
RESULT = ["sent"]
N.forward = lambda title, body, priority="default", tags="", kind="emergency", dry=False: FWD.append(title) or ("dry" if dry else RESULT[0])
MARK = os.path.join(ST, "notify_starved_last")
N.do_check()
ok("a 'sent' push writes the dedupe marker", os.path.exists(MARK))
CLOCK[0] = BASE + 1 * H
ok("an hour later: deduped (state file), no second emergency", starved(N.emergency_checks()) == [])
CLOCK[0] = BASE + 12 * H - 60
ok("just under 12 h later: still deduped", starved(N.emergency_checks()) == [])
CLOCK[0] = BASE + 12 * H + 1
res = starved(N.emergency_checks())
ok("after 12 h it fires again (once), with the longer idle time in the title", len(res) == 1 and res[0][0] == "🚨 Fleet starved 19h")
CLOCK[0] = BASE

# the dedupe marker is written ONLY after a 'sent' push: capped / failed / deduped / dry results keep the emergency alive for the next 10-minute check
for bad in ("capped", "failed", "deduped"):
    reset()
    set_queue({"iptv_apps": 0, "xlite": 0})
    write_outcomes([row("iptv_apps", 7 * H), row("xlite", 8 * H)])
    del FWD[:]
    RESULT[0] = bad
    out = N.do_check()
    ok("push result '%s': no dedupe marker is written" % bad, not os.path.exists(MARK) and "starved" in out)
    CLOCK[0] = BASE + 600
    N.do_check()
    ok("push result '%s': the next check tries the emergency again (not lost for 12 h)" % bad, len(FWD) == 2)
    RESULT[0] = "sent"
    N.do_check()
    ok("...and once it is finally 'sent' the marker is written and the window is consumed", os.path.exists(MARK) and len(FWD) == 3)
    N.do_check()
    ok("...after which nothing more is forwarded", len(FWD) == 3)
    CLOCK[0] = BASE
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 7 * H), row("xlite", 8 * H)])
RESULT[0] = "sent"
N.do_check(dry=True)
ok("a dry run (forward -> 'dry') writes no marker", not os.path.exists(MARK))
N.forward = orig_forward

# pushes go through the ONE existing emergency path: do_check -> forward, nothing else
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 7 * H), row("xlite", 8 * H)])
calls = []
N.forward = lambda title, body, priority="default", tags="", kind="emergency", dry=False: calls.append((title, kind, dry)) or "sent"
out = N.do_check()
ok("do_check forwards the starved emergency exactly once, as kind=emergency", len(calls) == 1 and calls[0][1] == "emergency" and "starved" in calls[0][0])
N.do_check()
ok("the next 10-minute check forwards nothing (deduped)", len(calls) == 1)
N.forward = orig_forward
reset()
write_outcomes([row("iptv_apps", 7 * H), row("xlite", 8 * H)])
N.do_check()
ok("one real do_check = exactly one HTTP post upstream (no extra push channel)", len(URLOPEN) == 1 and URLOPEN[0].endswith("/t_test"))
del URLOPEN[:]
N.do_update(force=True)
ok("the hourly update is still the only other push: exactly one post, with the idle lines inside its body", len(URLOPEN) == 1)

# negative controls
reset()
set_queue({"iptv_apps": 0, "xlite": 1})
write_outcomes([row("iptv_apps", 9 * H), row("xlite", 9 * H)])
ok("pullable > 0 anywhere -> no starved emergency", starved(N.emergency_checks()) == [])
reset()
set_queue({"iptv_apps": 0, "xlite": 0})
write_outcomes([row("iptv_apps", 9 * H), row("xlite", 20 * 60)])
ok("only ONE lane idle (the other attempted 20 min ago) -> no starved emergency", starved(N.emergency_checks()) == [])
write_outcomes([row("iptv_apps", 5 * H + 50 * 60), row("xlite", 9 * H)])
ok("idle 5h50 (under the 6h threshold) -> no starved emergency", starved(N.emergency_checks()) == [])
os.environ["OVN_IDLE_ALERT_H"] = "4"
ok("OVN_IDLE_ALERT_H=4 lowers the threshold", len(starved(N.emergency_checks())) == 1)
del os.environ["OVN_IDLE_ALERT_H"]
reset()
write_outcomes([row("iptv_apps", 9 * H), row("xlite", 9 * H)])
open(os.path.join(ST, "PAUSED"), "w").write("x")
ok("a deliberately PAUSED fleet is not 'starved'", starved(N.emergency_checks()) == [])
os.remove(os.path.join(ST, "PAUSED"))
os.environ["OVN_IDLE_ALERT"] = "0"
ok("kill switch OVN_IDLE_ALERT=0 -> no starved emergency", starved(N.emergency_checks()) == [])
del os.environ["OVN_IDLE_ALERT"]
ok("...and it fires without the kill switch", len(starved(N.emergency_checks())) == 1)
reset()
write_outcomes([row("iptv_apps", 9 * H), row("xlite", 9 * H)])
dry = N.do_check(dry=True)
ok("a --dry-run check reports it but does not consume the 12 h window", "starved" in dry and not os.path.exists(os.path.join(ST, "notify_starved_last")) and len(starved(N.emergency_checks())) == 1)
# the existing stalled check is untouched: work queued + nothing landed -> still its own emergency, never 'starved'
reset()
set_queue({"iptv_apps": 12, "xlite": 0})
write_outcomes([row("iptv_apps", 9 * H), row("xlite", 9 * H)])
res = N.emergency_checks()
ok("queued work (> 10) + nothing landed still raises 'Fleet stalled 3h' and not 'starved'", any("Fleet stalled" in e[0] for e in res) and not starved(res))

print("notify_idle_lane: %d passed, %d failed" % (ok_n, bad_n))
sys.exit(1 if bad_n else 0)
