"""P2 notify quality (2026-11-02): ovn_notify.py - OVN_NOTIFY_DISABLE honoured by forward (N4), separate digest / emergency budgets (N10), the `heartbeat` subcommand (N8),
the quiet 'all good' digest (N6) and the once-per-day `escalate` (N7). Local fake upstream, injected clock, TZ pinned; nothing touches a real channel."""
import importlib.util, io, json, os, sys, tempfile, threading, time
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()
from http.server import BaseHTTPRequestHandler, HTTPServer

os.environ["TZ"] = "UTC"; time.tzset()
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.environ.get("OVN_NOTIFY_SRC") or os.path.join(ROOT, "scripts", "ovn_notify.py")
T = tempfile.mkdtemp()
ST = os.path.join(T, "q", "state"); os.makedirs(ST)
for k in ("OVN_NOTIFY_DISABLE", "OVN_NOTIFY_DAILY_CAP", "OVN_NOTIFY_DIGEST_CAP", "OVN_NOTIFY_EMERGENCY_CAP", "OVN_DIGEST_QUIET", "OVN_ESC_TEST", "OVN_DIGEST_DEDUPE"):
    os.environ.pop(k, None)
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_p2")
posts = []


class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        posts.append({"title": self.headers.get("Title"), "prio": self.headers.get("Priority"), "body": self.rfile.read(n).decode()})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")


srv = HTTPServer(("127.0.0.1", 0), Fake); threading.Thread(target=srv.serve_forever, daemon=True).start()
os.environ["OVN_NOTIFY_UPSTREAM"] = "http://127.0.0.1:%d" % srv.server_port
spec = importlib.util.spec_from_file_location("ovn_notify_p2", SRC); N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)
CLOCK = [1762041600.0]   # 2025-11-02 00:00:00 UTC
N.now = lambda: CLOCK[0]
ok_n = bad_n = 0


def ok(label, cond):
    global ok_n, bad_n
    if cond: ok_n += 1; print("  ok   " + label)
    else: bad_n += 1; print("  FAIL " + label)


def reset(**caps):
    del posts[:]
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    N.DIGEST_CAP = caps.get("digest", 24); N.EMERGENCY_CAP = caps.get("emergency", 20); N.DAILY_CAP_EXPLICIT = False; N.DAILY_CAP = 40
    os.environ.pop("OVN_NOTIFY_DISABLE", None); os.environ["OVN_DIGEST_DEDUPE"] = "off"


def shadow():
    try: return open(os.path.join(ST, "notify_shadow.log")).read()
    except OSError: return ""


# ---- N4: OVN_NOTIFY_DISABLE is honoured by forward itself (not only by the relay's classify)
reset(); os.environ["OVN_NOTIFY_DISABLE"] = "1"
r = N.forward("DOWN: site", "b", "urgent", kind="emergency")
ok("N4: OVN_NOTIFY_DISABLE=1 -> forward pushes nothing and records nothing", r == "disabled" and not posts and not os.path.exists(os.path.join(ST, "notify_sent.jsonl")))
r = N.forward("Shrike hourly", "b", kind="heartbeat")
ok("N4: ... heartbeat too", r == "disabled" and not posts)
os.environ.pop("OVN_NOTIFY_DISABLE")

# ---- N10: separate budgets
reset(digest=3, emergency=2)
rs = [N.forward("Shrike hourly - %d to look at" % i, "body%d" % i, kind="digest") for i in range(4)]
ok("N10: digest budget (3 here): the 4th digest is capped", rs == ["sent", "sent", "sent", "capped"])
re_ = [N.forward("Emergency %d" % i, "b", "urgent", kind="emergency") for i in range(3)]
ok("N10: an exhausted digest budget does NOT starve emergencies (2 sent), the emergency budget caps the 3rd", re_ == ["sent", "sent", "capped"])
reset(digest=2, emergency=2)
N.forward("Emergency A", "b", kind="emergency"); N.forward("Emergency B", "b", kind="emergency"); N.forward("Emergency C", "b", kind="emergency")
ok("N10: ... and digests keep their own budget when emergencies are exhausted", N.forward("Shrike hourly", "x", kind="digest") == "sent")
ev = N._read_jsonl(os.path.join(ST, "notify_events.jsonl"))
ok("N10: the capped emergency is recorded as an event (so the heartbeat can report it)", any(e.get("action") == "capped" and e.get("kind") == "emergency" and e.get("key") == "Emergency C" for e in ev))
reset(digest=24, emergency=20); N.DAILY_CAP_EXPLICIT = True; N.DAILY_CAP = 2
N.forward("E1", "b", kind="emergency"); N.forward("E2", "b", kind="emergency")
ok("N10: an explicit OVN_NOTIFY_DAILY_CAP stays a total ceiling (backward compatible)", N.forward("E3", "b", kind="emergency") == "capped")
ok("N10: ... and never blocks a heartbeat", N.forward("ntfy alive x", "b", kind="heartbeat") == "sent")

# ---- N8: heartbeat
reset(digest=1, emergency=1)
N.forward("Shrike hourly", "b", kind="digest"); N.forward("Shrike hourly", "b2", kind="digest")          # 1 sent, 1 capped
N.forward("Mac jobs: x", "b", kind="emergency"); CLOCK[0] += 600
N.forward("Mac jobs: x", "b", kind="emergency"); N.forward("Other emergency", "b", kind="emergency")     # 1 deduped (same title), 1 capped
for _ in range(3):
    N.handle_publish("t", {"title": "Backlog refilled", "priority": "low"}, "x")                           # 3 dropped
CLOCK[0] += 3600 * 5; n0 = len(posts)
t, b = N.heartbeat_text()
ok("N8: title is 'ntfy alive YYYY-MM-DD' (local date, TZ pinned UTC)", t == "ntfy alive 2025-11-02")
ok("N8: body counts sent/24h, capped, dropped and names the last emergency with its age", b.startswith("2 sent/24h, 2 capped, 3 dropped (3 backlog-refilled), last emergency Mac jobs: x 5h") and "[suppressed 2]" in b)
res = N.do_heartbeat()
ok("N8: the heartbeat is pushed with priority default (3)", "-> sent" in res and len(posts) == n0 + 1 and posts[-1]["prio"] == "default" and posts[-1]["title"] == "ntfy alive 2025-11-02")
res2 = N.do_heartbeat()
ok("N8: never deduped (a second heartbeat the same day is sent too) and exempt from the caps (both budgets were exhausted)", "-> sent" in res2 and len(posts) == n0 + 2)
t3, b3 = N.heartbeat_text()
ok("N8: '[suppressed N]' is reported ONCE: gone from the heartbeat after the next one went out", "[suppressed" not in b3)
ok("N8: heartbeat rows do not count as 'sent' in the next line", b3.startswith("2 sent/24h"))
ok("N8: --dry-run returns the text and posts nothing", N.do_heartbeat(dry=True).startswith("ntfy alive 2025-11-02:") and len(posts) == n0 + 2)
reset(); t, b = N.heartbeat_text()
# Y1 contract: the heartbeat is ONE message; the FIRST line is stable for old consumers, a cron-beats status line may follow (never more than 2 lines)
b_lines = b.split("\n")
ok("N8: a quiet day still says so ('0 sent/24h ... last emergency none' as the first line)", b_lines[0] == "0 sent/24h, 0 capped, 0 dropped, last emergency none")
ok("N8: ... and any extra line is only the optional beats line (<= 2 lines total)", len(b_lines) <= 2 and (len(b_lines) == 1 or b_lines[1].startswith(("beats:", "cron beats:"))))
ok("N8: CLI wires `heartbeat`", N.main(["x", "heartbeat", "--dry-run"]) == 0)

# ---- N6: no 'all good' digest while the heartbeat vouches for liveness
reset()
N.compose_update_ex = lambda window=3600, at=None: ("✅ Shrike hourly — all good", "Pass rate: -", 0, ("", False))
r = N.do_update()
ok("N6: no heartbeat in the last 26 h -> the all-good digest IS still sent (it is the only sign of life)", len(posts) == 1 and "(sent)" in r)
N.forward("ntfy alive x", "b", kind="heartbeat"); CLOCK[0] += 3600; del posts[:]
r = N.do_update()
ok("N6: heartbeat alive -> an all-good hour sends NO digest", not posts and r.startswith("skipped: nothing to look at"))
ok("N6: ... and stamps notify_last_update so the check is not redone every minute", os.path.exists(os.path.join(ST, "notify_last_update")))
N.compose_update_ex = lambda window=3600, at=None: ("⚠️ Shrike hourly — 1 to look at", "• x", 1, ("", False))
CLOCK[0] += 3600; r = N.do_update()
ok("N6: something to look at -> the digest goes out even with a live heartbeat", len(posts) == 1 and "(sent)" in r)
N.compose_update_ex = lambda window=3600, at=None: ("✅ Shrike hourly — all good", "Pass rate: -", 0, ("", False))
os.environ["OVN_DIGEST_QUIET"] = "off"; CLOCK[0] += 3600; del posts[:]
N.do_update()
ok("N6: OVN_DIGEST_QUIET=off (kill switch) restores the hourly all-good digest", len(posts) == 1)
os.environ["OVN_DIGEST_QUIET"] = "shadow"; CLOCK[0] += 3600; del posts[:]
N.do_update()
ok("N6: OVN_DIGEST_QUIET=shadow sends it and logs 'would skip'", len(posts) == 1 and "OVN_DIGEST_QUIET | would skip the all-good digest" in shadow())
os.environ.pop("OVN_DIGEST_QUIET")
reset(); N.forward("ntfy alive x", "b", kind="heartbeat"); del posts[:]
N.do_update(force=True)
ok("N6: --force still sends an all-good digest on demand (heartbeat alive)", len(posts) == 1)
reset(); N.forward("ntfy alive x", "b", kind="heartbeat")
ok("N6: heartbeat_alive: fresh = True, 27 h later = False", N.heartbeat_alive(CLOCK[0] + 3600) and not N.heartbeat_alive(CLOCK[0] + 27 * 3600))

# ---- N7: escalate = ONE emergency push per signature per local day
reset(); os.environ.pop("OVN_ESC_TEST", None)
r = N.escalate("hyg:gitlark", "Hygiene stuck 4h: gitlark", "body", "OVN_ESC_TEST")
ok("N7: default mode is shadow: no push, one 'would escalate' line", r == "shadow" and not posts and "OVN_ESC_TEST | would escalate" in shadow())
n_lines = shadow().count("would escalate"); N.escalate("hyg:gitlark", "Hygiene stuck 4h: gitlark", "body", "OVN_ESC_TEST")
ok("N7: the shadow line is written once per signature per day", shadow().count("would escalate") == n_lines)
os.environ["OVN_ESC_TEST"] = "on"
r1 = N.escalate("hyg:gitlark", "Hygiene stuck 4h: gitlark", "body", "OVN_ESC_TEST")
ok("N7: on -> one URGENT push", r1 == "sent" and len(posts) == 1 and posts[0]["prio"] == "urgent")
r2 = N.escalate("hyg:gitlark", "Hygiene stuck 5h: gitlark", "body", "OVN_ESC_TEST")
ok("N7: the same signature again the same day -> nothing (even with a changed title)", r2 == "already-today" and len(posts) == 1)
r3 = N.escalate("hyg:iptv_apps", "Hygiene stuck 4h: iptv_apps", "body", "OVN_ESC_TEST")
ok("N7: another signature is its own escalation", r3 == "sent" and len(posts) == 2)
CLOCK[0] += 86400
r4 = N.escalate("hyg:gitlark", "Hygiene stuck 28h: gitlark", "body", "OVN_ESC_TEST")
ok("N7: the next day it escalates again", r4 == "sent" and len(posts) == 3)
reset(digest=24, emergency=0); os.environ["OVN_ESC_TEST"] = "on"
r5 = N.escalate("sigX", "X", "b", "OVN_ESC_TEST"); N.EMERGENCY_CAP = 5
r6 = N.escalate("sigX", "X", "b", "OVN_ESC_TEST")
ok("N7: a capped escalation does NOT consume the day (retries when budget returns)", r5 == "capped" and r6 == "sent")
os.environ["OVN_ESC_TEST"] = "off"
ok("N7: off -> nothing at all", N.escalate("sigY", "Y", "b", "OVN_ESC_TEST") == "off")
os.environ.pop("OVN_ESC_TEST")
ok("N7: CLI `escalate` without --sig/--title/--flag is a usage error", N.main(["x", "escalate", "--sig", "a"]) == 2)

print("p2 notify quality: %d passed, %d failed" % (ok_n, bad_n))
sys.exit(1 if bad_n else 0)
