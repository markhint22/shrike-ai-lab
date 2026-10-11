#!/usr/bin/env python3
"""ovn_notify.boot_notes (2026-10-10): the hourly update's "Box rebooted 52m ago after a 2h22m outage" / "Queue silent 40m" lines.

The box hard-froze 04:58:40-07:20:55 CDT and the 08:20 hourly update never mentioned it. Time is injected (compose_update(at=...), OVN_UPTIME_FILE, OVN_UNIT_STATE): nothing
reads the host's real uptime or systemd. Run reports and outcomes rows carry controlled mtimes/timestamps. A mutation section breaks each rule in a temp copy of ovn_notify.py
and shows the scenarios then fail."""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "scripts", "ovn_notify.py")
if not os.path.isfile(SRC) or "def boot_notes(" not in open(SRC).read():
    print("  SKIP: scripts/ovn_notify.py with boot_notes() is not installed here")
    sys.exit(0)

P = F = 0
QUIET = False


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        if not QUIET:
            print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="bootnotes-test-"))
import atexit
atexit.register(lambda: shutil.rmtree(T, ignore_errors=True))      # also on a crash / sys.exit
QROOT = os.path.join(T, "q")
STATE = os.path.join(QROOT, "state")
REPORTS = os.path.join(QROOT, "reports")
os.makedirs(STATE)

LLM = {"status": 200}
POSTS = []


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        self.send_response(LLM["status"]); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        POSTS.append({"title": self.headers.get("Title"), "body": self.rfile.read(n).decode()})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")


srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % srv.server_port

BASE = 1_800_000_000          # "now" for the injected-clock scenarios (a Saturday 2027)
UPTIME_FILE = os.path.join(T, "uptime")


def load(path, name):
    env_keep = dict(os.environ)
    os.environ.update(OVN_NOTIFY_STATE=STATE, NTFY_TOPIC="t_test", OVN_NOTIFY_UPSTREAM=URL, OVN_LLM_HEALTH_URL=URL + "/health/readiness", OVN_UPTIME_FILE=UPTIME_FILE, OVN_UNIT_STATE="active")
    for k in ("OVN_BOOT_NOTE", "OVN_SILENT_S", "OVN_IDLE_LINE"):
        os.environ.pop(k, None)
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def world(heartbeats_reports=(), outcomes=(), up=None, unit="active", paused=False, llm=200, boot_reported=None, now=BASE):
    """heartbeats_reports / outcomes: epoch lists (report mtimes / outcomes row ts). up: seconds of uptime at `now`."""
    shutil.rmtree(REPORTS, ignore_errors=True)
    os.makedirs(REPORTS)
    for f in os.listdir(STATE):
        os.remove(os.path.join(STATE, f))
    for i, t in enumerate(sorted(heartbeats_reports)):
        p = os.path.join(REPORTS, "%s-%04d.md" % (time.strftime("%Y%m%d-%H%M%S", time.gmtime(t)), i))
        open(p, "w").write("# r\n")
        os.utime(p, (t, t))
    with open(os.path.join(STATE, "outcomes.jsonl"), "w") as f:
        for t in sorted(outcomes):
            f.write(json.dumps({"ts": iso(t), "repo": "iptv_apps", "class": "landed", "severity": "good"}) + "\n")
    if up is None:
        try:
            os.remove(UPTIME_FILE)
        except OSError:
            pass
    else:
        open(UPTIME_FILE, "w").write("%d.00 123.00\n" % up)
    os.environ["OVN_UNIT_STATE"] = unit
    if paused:
        open(os.path.join(STATE, "PAUSED"), "w").close()
    if boot_reported is not None:
        open(os.path.join(STATE, "notify_boot_reported"), "w").write(str(boot_reported))
    LLM["status"] = llm


def every(start, end, step=300):
    return list(range(int(start), int(end), step))


def suite(N, label=""):
    # ---------- unclean boot: queue silent for 2h22m before the kernel booted 52 min ago
    up = 52 * 60
    boot = BASE - up
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), outcomes=[boot - 8600], up=up)
    notes = N.boot_notes(at=BASE)
    b = [n for n in notes if n["boot"]]
    ok(label + "unclean boot: one boot note", len(b) == 1, notes)
    t = b[0] if b else {}
    ok(label + "unclean boot: title carries uptime AND the outage length (2h22m)", t.get("title") == "Box rebooted 52m ago after a 2h22m outage" or t.get("title", "").startswith("Box rebooted 52m ago after a 2h2"), t)
    ok(label + "unclean boot: prio high, text says no clean shutdown trail + that the queue unit and LiteLLM are fine", t.get("prio") == "high" and "no clean shutdown trail" in t.get("text", "") and "queue unit active, LiteLLM answering" in t.get("text", ""), t)
    ok(label + "boot note carries the boot epoch (used to report once per boot)", abs(t.get("boot", 0) - boot) < 2)

    # ---------- clean restart: heartbeat 100 s before the boot -> no outage claim
    world(heartbeats_reports=every(boot - 3600, boot - 100) + [boot - 100] + every(boot + 60, BASE), up=up)
    t = ([n for n in N.boot_notes(at=BASE) if n["boot"]] or [{}])[0]
    ok(label + "clean restart: 'Box rebooted 52m ago', no outage, prio default", t.get("title") == "Box rebooted 52m ago" and t.get("prio") == "default" and t.get("text", "").startswith("clean restart"), t)

    # ---------- outcomes-only history (no report files) still shows the gap
    world(heartbeats_reports=[], outcomes=every(boot - 3 * 3600, boot - 8520, 600) + every(boot + 100, BASE, 600), up=up)
    t = ([n for n in N.boot_notes(at=BASE) if n["boot"]] or [{}])[0]
    ok(label + "gap detected from outcomes rows alone as well", "outage" in t.get("title", ""), t)

    # ---------- reported ONCE per boot; a different boot is reported again
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), up=up, boot_reported=boot + 2)
    ok(label + "already reported for this boot: no boot note", not [n for n in N.boot_notes(at=BASE) if n["boot"]])
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), up=up, boot_reported=boot - 86400)
    ok(label + "marker of an OLDER boot does not suppress this one", len([n for n in N.boot_notes(at=BASE) if n["boot"]]) == 1)

    # ---------- window / hermetic guards
    world(heartbeats_reports=every(BASE - 5 * 3600, BASE), up=2 * 3600 + 60)
    ok(label + "uptime >= 2 h: no boot note", not [n for n in N.boot_notes(at=BASE) if n["boot"]])
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), up=None)
    ok(label + "no /proc/uptime (Mac, tests): no boot note, no crash", N.boot_notes(at=BASE) == [])
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), up=up)
    os.environ["OVN_BOOT_NOTE"] = "0"
    ok(label + "OVN_BOOT_NOTE=0 kill switch", N.boot_notes(at=BASE) == [])
    os.environ.pop("OVN_BOOT_NOTE")
    shutil.rmtree(REPORTS)
    ok(label + "no reports/ dir (not a real queue root, e.g. a scratch STATE): never inherits the host uptime", N.boot_notes(at=BASE) == [])

    # ---------- pause: a deliberate pause across a reboot is not an 'unclean' outage
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), up=up, paused=True)
    t = ([n for n in N.boot_notes(at=BASE) if n["boot"]] or [{}])[0]
    ok(label + "PAUSED present: boot noted but NOT claimed as an unclean outage", t.get("title") == "Box rebooted 52m ago" and "outage" not in t.get("title", ""), t)

    # ---------- post-boot health: unit down / LiteLLM down are visible and raise the priority
    world(heartbeats_reports=every(boot - 3600, boot - 100) + [boot - 100] + every(boot + 60, BASE), up=up, unit="failed", llm=503)
    t = ([n for n in N.boot_notes(at=BASE) if n["boot"]] or [{}])[0]
    ok(label + "clean boot but unit 'failed' and LiteLLM 503: prio high, text names both", t.get("prio") == "high" and "queue unit failed" in t.get("text", "") and "LiteLLM NOT answering" in t.get("text", ""), t)

    # ---------- silent queue (no boot involved)
    up2 = 5 * 86400
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 2400) + [BASE - 2400], outcomes=[BASE - 2500], up=up2)
    s = N.boot_notes(at=BASE)
    ok(label + "unit active, not paused, no heartbeat for 40 min: 'Queue silent 40m'", len(s) == 1 and s[0]["title"] == "Queue silent 40m" and s[0]["prio"] == "high" and not s[0]["boot"], s)
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 2400) + [BASE - 2400] + [BASE - 70], outcomes=[BASE - 9000], up=up2)
    ok(label + "exhausted-idle fleet (no outcomes rows for hours, a run report 70 s old): NOT silent", N.boot_notes(at=BASE) == [])
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 2400) + [BASE - 2400], up=up2, paused=True)
    ok(label + "paused: never 'silent'", N.boot_notes(at=BASE) == [])
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 2400) + [BASE - 2400], up=up2, unit="inactive")
    ok(label + "unit inactive: not reported as a silent queue (that is a different problem, the Mac dead-man pages it)", N.boot_notes(at=BASE) == [])
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 2400) + [BASE - 2400], up=400)
    ok(label + "first 10 min of uptime: no 'silent' verdict yet", not [n for n in N.boot_notes(at=BASE) if not n["boot"]])
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE - 1700) + [BASE - 1700], up=up2)
    ok(label + "28 min of silence is below the 30 min threshold", N.boot_notes(at=BASE) == [])

    # ---------- the hourly update text
    world(heartbeats_reports=every(boot - 3 * 3600, boot - 8520) + [boot - 8520] + every(boot + 100, BASE), outcomes=[boot - 8600, BASE - 600], up=up)
    title, body, needs = N.compose_update(at=BASE)
    ok(label + "compose_update: the boot note is the FIRST bullet and counts toward 'N to look at'", title.startswith("⚠️ Shrike hourly") and body.split("\n")[0].startswith("• Box rebooted 52m ago after a 2h") and needs >= 1, (title, body[:200]))
    world(heartbeats_reports=every(BASE - 4 * 3600, BASE), outcomes=[BASE - 600], up=up2)
    title, body, needs = N.compose_update(at=BASE)
    ok(label + "compose_update: nothing to report on a healthy long-running box", "Box rebooted" not in body and "Queue silent" not in body, body[:200])

    # ---------- do_update marks the boot as reported (real clock: reports/outcomes relative to time.time())
    now = time.time()
    upr = 600
    bt = now - upr
    world(heartbeats_reports=every(bt - 3 * 3600, bt - 8520) + every(bt + 100, now), outcomes=[bt - 8600], up=upr, now=now)
    del POSTS[:]
    r1 = N.do_update(force=True)
    ok(label + "do_update sends the update with the boot line and stamps the boot as reported", len(POSTS) == 1 and "Box rebooted" in POSTS[0]["body"] and os.path.exists(os.path.join(STATE, "notify_boot_reported")), (r1, POSTS))
    r2 = N.do_update(force=True)
    ok(label + "the NEXT update does not repeat the boot line", len(POSTS) == 2 and "Box rebooted" not in POSTS[1]["body"], POSTS[-1:])


N = load(SRC, "ovn_notify_boot_under_test")
suite(N)

# ================= mutation proofs
MUT = [
    ("outage length ignored (clean/unclean never distinguished)", "unclean = gap is not None and gap > SILENT_S and not paused", "unclean = False"),
    ("silent check looks at outcomes only (the idle-fleet false positive)", "    rd = os.path.join(ROOT, \"reports\")\n    try:\n        names =", "    rd = os.path.join(ROOT, \"reports-disabled\")\n    try:\n        names ="),
    ("boot reported on every update (marker ignored)", "if reported is None or abs(reported - boot) > 300:", "if True:"),
    ("pause ignored by the silent check", "if unit in (\"active\", \"activating\") and not paused and (up is None or up >= BOOT_GRACE_S):", "if unit in (\"active\", \"activating\") and (up is None or up >= BOOT_GRACE_S):"),
    ("boot window never ends", "if up is not None and up < BOOT_WINDOW_S:", "if up is not None:"),
    ("scratch/test roots inherit the host uptime (hermetic guard removed)", "if os.environ.get(\"OVN_BOOT_NOTE\") == \"0\" or not os.path.isdir(os.path.join(ROOT, \"reports\")):", "if os.environ.get(\"OVN_BOOT_NOTE\") == \"0\":"),
    ("do_update never stamps the boot", "            if bn.get(\"boot\"):\n                open(_p(\"notify_boot_reported\"), \"w\").write(str(bn[\"boot\"]))", "            pass"),
    ("compose_update ignores the notes", "    for bn in reversed(boot_notes(t if at else None)):", "    for bn in reversed([]):"),
    ("silent threshold 1 minute", 'SILENT_S = int(os.environ.get("OVN_SILENT_S", "1800"))', 'SILENT_S = int(os.environ.get("OVN_SILENT_S", "60"))'),
    ("unit state / LiteLLM health not reported", 'state = "queue unit %s, LiteLLM %s" % (unit if unit is not None else "unknown", "answering" if llm_ok else "NOT answering")', 'state = "ok"'),
]
if os.environ.get("BOOTNOTES_SKIP_MUTATION") != "1":
    src = open(SRC).read()
    for label, old, new in MUT:
        if old not in src:
            ok("mutation anchor present: " + label, False, "anchor not found in ovn_notify.py (update the test)")
            continue
        mp = os.path.join(T, "mut_ovn_notify.py")
        open(mp, "w").write(src.replace(old, new, 1))
        p0, f0 = P, F
        QUIET = True
        try:
            suite(load(mp, "mut_" + str(abs(hash(label)))), "[mut] ")
        except Exception:      # a mutant that crashes is caught too
            F += 1
        QUIET = False
        caught = F > f0
        P, F = p0, f0
        ok("mutation CAUGHT by the suite: " + label, caught)

shutil.rmtree(T, ignore_errors=True)
print("test_boot_notes: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
