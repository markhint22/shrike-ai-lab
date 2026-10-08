"""ovn_notify.py: classification, buffering, caps/dedupe, forwarding (against a local fake ntfy), the relay server, the hourly update and the emergency checks."""
import importlib.util, io, json, os, sys, tempfile, threading, time, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "scripts", "ovn_notify.py")
T = tempfile.mkdtemp()
os.environ.update(OVN_NOTIFY_STATE=os.path.join(T, "q", "state"), NTFY_TOPIC="t_test", OVN_NOTIFY_DAILY_CAP="5")
os.makedirs(os.environ["OVN_NOTIFY_STATE"])
posts, mode = [], {"status": 200}


class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        posts.append({"path": self.path, "title": self.headers.get("Title"), "prio": self.headers.get("Priority"), "body": self.rfile.read(n).decode()})
        self.send_response(mode["status"]); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")


srv = HTTPServer(("127.0.0.1", 0), Fake); threading.Thread(target=srv.serve_forever, daemon=True).start()
os.environ["OVN_NOTIFY_UPSTREAM"] = "http://127.0.0.1:%d" % srv.server_port
spec = importlib.util.spec_from_file_location("ovn_notify", SRC); N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)
ST = os.environ["OVN_NOTIFY_STATE"]
ok_n = bad_n = 0


def ok(label, cond):
    global ok_n, bad_n
    if cond: ok_n += 1; print("  ok   " + label)
    else: bad_n += 1; print("  FAIL " + label)


def reset():
    del posts[:]; mode["status"] = 200
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))


# ---- text helpers
ok("clean_title strips leading emoji", N.clean_title("🚨 Deploy failed: gitlark") == "Deploy failed: gitlark")
ok("clean_title keeps a leading bracket/word", N.clean_title("[T3] thing") == "[T3] thing" and N.clean_title("") == "")
ok("short: first sentence of a long body", N.short("Hygiene is stuck for gitlark. More detail follows here and goes on and on.") == "Hygiene is stuck for gitlark.")
ok("short: caps very long text with an ellipsis", len(N.short("x" * 400)) <= 110 and N.short("x" * 400).endswith("…"))
ok("_hdr: ascii unchanged, emoji RFC2047-encoded", N._hdr("abc") == "abc" and N._hdr("🚨 x").startswith("=?UTF-8?B?"))
ok("fix_header repairs raw-UTF-8 (latin-1 mojibake) titles", N.fix_header("🔴 DOWN: x".encode("utf-8").decode("latin-1")) == "🔴 DOWN: x")
ok("fix_header decodes RFC 2047 words and leaves plain/invalid text alone", N.fix_header(N._hdr("🚨 Fleet stalled")) == "🚨 Fleet stalled" and N.fix_header("plain") == "plain" and N.fix_header("") == "" and N.fix_header("caf\xe9") == "caf\xe9")
# ---- classification
ok("explicit emergency header", N.classify("anything", "default", "emergency") == "emergency")
ok("explicit digest header", N.classify("x", "default", "digest") == "digest")
ok("priority urgent -> emergency", N.classify("Deploy failed: x (human)", "urgent") == "emergency")
ok("production site DOWN -> emergency", N.classify("🔴 DOWN: gitlark-backend", "default") == "emergency")
ok("27B restart failure -> emergency", N.classify("27B auto-restart FAILED", "default") == "emergency")
ok("routine digest/refill/cycle titles are dropped", all(N.classify(t) == "drop" for t in ("Overnight queue", "Overnight queue: 5 item(s) need attention", "Backlog refilled", "fleet lock-orphan cleared", "Daily prod promote")))
ok("a recovery is a NOTE, not dropped or emergency", N.classify("✅ Recovered: gitlark-backend") == "note")
ok("hygiene/conflict style messages are NOTES", N.classify("Hygiene stalled — gate red on a feature branch", "high") == "note")
os.environ["OVN_NOTIFY_DISABLE"] = "1"; ok("OVN_NOTIFY_DISABLE=1 drops everything", N.classify("🔴 DOWN: x", "urgent", "emergency") == "drop"); del os.environ["OVN_NOTIFY_DISABLE"]
# ---- handle_publish
reset()
ok("a note is buffered, nothing pushed", N.handle_publish("t", {"title": "Hygiene stalled", "priority": "high"}, "gate red. details") == "noted" and not posts and len(N._read_jsonl(os.path.join(ST, "notify_notes.jsonl"))) == 1)
ok("a dropped message is neither buffered nor pushed", N.handle_publish("t", {"title": "Overnight queue"}, "x") == "dropped" and not posts and len(N._read_jsonl(os.path.join(ST, "notify_notes.jsonl"))) == 1)
r = N.handle_publish("t", {"title": "🔴 DOWN: gitlark-backend", "priority": "default", "tags": "rotating_light"}, "It is down. " + "x" * 300)
ok("an emergency is pushed at once with priority urgent and a capped body", r == "emergency:sent" and len(posts) == 1 and posts[0]["prio"] == "urgent" and len(posts[0]["body"]) <= 200 and posts[0]["path"] == "/t_test")
ok("the emoji title arrives RFC2047-encoded", posts[0]["title"].startswith("=?UTF-8?B?"))
r2 = N.handle_publish("t", {"title": "🔴 DOWN: gitlark-backend"}, "still down")
ok("the same emergency within 3h is deduped (not pushed again) but buffered", r2 == "emergency:deduped" and len(posts) == 1 and any("DOWN" in n["title"] for n in N._read_jsonl(os.path.join(ST, "notify_notes.jsonl"))))
reset()
for i in range(7):
    N.handle_publish("t", {"title": "🔴 DOWN: site%d" % i}, "x")
ok("the daily cap (5 here) stops pushes; the rest are buffered", len(posts) == 5 and len(N.sent_today()) == 5)
ok("digest kind is capped too", N.forward("hourly", "b", kind="digest") == "capped")
reset(); mode["status"] = 429
ok("upstream 429 -> failed, recorded, and the message is kept as an undelivered note", N.forward("🔴 DOWN: x", "body", kind="emergency") == "failed" and any("[undelivered]" in n["title"] for n in N._read_jsonl(os.path.join(ST, "notify_notes.jsonl"))))
reset(); mode["status"] = 429
ok("a failed hourly update is retried later, NOT turned into an 'undelivered' note", N.forward("Shrike hourly", "b", kind="digest") == "failed" and not any("undelivered" in n["title"] for n in N._read_jsonl(os.path.join(ST, "notify_notes.jsonl"))))
reset(); ok("dry run never posts", N.forward("t", "b", dry=True) == "dry" and not posts)
u = N.UPSTREAM; N.UPSTREAM = "http://127.0.0.1:1"
ok("an unreachable upstream is 'failed', not an exception", N.forward("t", "b") == "failed"); N.UPSTREAM = u
# ---- hourly update
reset()
now = time.time(); iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
rows = [{"ts": iso(now - 600), "repo": "gitlark", "class": "landed"}] * 3 + [{"ts": iso(now - 900), "repo": "billwatch", "class": "landed"}, {"ts": iso(now - 300), "repo": "gitlark", "class": "revert"}, {"ts": iso(now - 99999), "repo": "old", "class": "landed"}, {"ts": iso(now - 60), "repo": "x", "class": "skipped"}]
open(os.path.join(ST, "outcomes.jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\nnot json\n")
repos = os.path.join(T, "q", "repos"); os.makedirs(os.path.join(repos, "gitlark")); os.makedirs(os.path.join(repos, "billwatch")); os.makedirs(os.path.join(repos, "shrike-labs-website"))
open(os.path.join(repos, "gitlark", "OVERNIGHT_PROGRESS.md"), "w").write("- [ ] a\n- [ ] b\n- [ ] [AUTO-SKIP x] c\n- [x] d\n- [ ] [T1] make the output human-readable\n- [ ] [HUMAN-ONLY] e\n")
ok("an item that merely says 'human' is still doable; HUMAN-ONLY and AUTO-SKIP are not", N._doable(os.path.join(repos, "gitlark")) == 3)
open(os.path.join(repos, "billwatch", "OVERNIGHT_PROGRESS.md"), "w").write("".join("- [ ] i%d\n" % i for i in range(9)))
open(os.path.join(repos, "shrike-labs-website", "OVERNIGHT_PROGRESS.md"), "w").write("- [ ] z\n")
N.ROOT = os.path.join(T, "q")
t, b, n = N.compose_update(at=now)
ok("quiet hour: 'all good' title", t == "✅ Shrike hourly — all good" and n == 0)
ok("landed line counts per repo, biggest first, old rows excluded", "Landed 4: gitlark 3 · billwatch 1" in b and "old" not in b)
ok("reverts are shown in plain words", "Undone (broke tests): gitlark 1" in b)
ok("low queue is named with its count (website ignored)", "Queues low: gitlark (3)" in b and "website" not in b)
# an EMPTY active queue must not hide under an "all good" title; a repo with every lane disabled is not an active queue
reset(); N.ROOT = os.path.join(T, "q2"); os.makedirs(os.path.join(N.ROOT, "repos", "gitlark")); os.makedirs(os.path.join(N.ROOT, "repos", "billwatch"))
open(os.path.join(N.ROOT, "repos", "gitlark", "OVERNIGHT_PROGRESS.md"), "w").write("- [ ] [AUTO-SKIP x] only a parked item\n")
open(os.path.join(N.ROOT, "repos", "billwatch", "OVERNIGHT_PROGRESS.md"), "w").write("- [x] done\n")
open(os.path.join(N.ROOT, "tasks.json"), "w").write(json.dumps([{"repo": "x/gitlark", "enabled": True}, {"repo": "x/billwatch", "enabled": False}]))
t, b, n = N.compose_update(at=now)
ok("an empty ACTIVE queue turns the title into 'to look at' and is the first bullet", t.startswith("⚠️") and "Queue empty: gitlark" in b.splitlines()[0] and n >= 1)
ok("a repo whose lanes are all disabled is not reported (billwatch at 0)", "billwatch" not in b)
os.unlink(os.path.join(N.ROOT, "tasks.json"))
N.ROOT = os.path.join(T, "q")
ok("research-batch scorecard messages are dropped from the hourly update", N.classify("Research-batch scorecard: 102 batch(es) graded D/F") == "drop")
ok("pass counts use the canonical severity axis (neutral/benign excluded)", N._pass_counts([{"severity": "good"}] * 5 + [{"severity": "bad"}] + [{"severity": "neutral"}] * 3) == (5, 1))
ok("percent helper: 5/6 -> 83%, no data -> '-'", N._pct(5, 1) == "83%" and N._pct(0, 0) == "-")
ok("every hourly update carries a pass-rate line (last hour + today)", "Pass rate: last hour" in b and "today" in b)
for ti, bo, pr in (("Hygiene stalled — gate red on a feature branch", "gitlark has not merged in 3h. More.", "high"), ("Hygiene stalled — gate red on a feature branch", "dup", "high"), ("Deploy failed: x (human)", "needs you", "urgent"), ("✅ Recovered: gitlark-backend", "ok", "low"), ("a", "b", "default"), ("c", "d", "default"), ("e", "f", "low")):
    N.add_note(ti, bo, pr)
t, b, n = N.compose_update(at=now)
ok("attention title counts distinct items", t.startswith("⚠️ Shrike hourly — ") and "to look at" in t and n == 5)
ok("most severe first: the urgent and high notes are the bullets", b.splitlines()[0].startswith("• Deploy failed") and "Hygiene stalled" in b)
ok("at most 3 bullets + an overflow line; recoveries are a separate 'Back up' line", b.count("•") == 3 and "(+2 more" in b and "Back up: gitlark-backend" in b)
ok("duplicates collapse to one bullet", b.count("Hygiene stalled") <= 1)
ok("body stays short (<= 12 lines, <= 700 chars)", len(b.splitlines()) <= 12 and len(b) <= 700)
reset(); open(os.path.join(ST, "notify_last_update"), "w").write(str(time.time() - 600))
ok("update within 50 min of the last one is skipped", N.do_update().startswith("skipped"))
ok("--force sends and stamps the time", "(sent)" in N.do_update(force=True) and len(posts) == 1 and float(open(os.path.join(ST, "notify_last_update")).read()) > time.time() - 5)
ok("the hourly update is pushed with default priority to the configured topic", posts[0]["prio"] == "default" and posts[0]["path"] == "/t_test")
ok("--dry-run returns the text and posts nothing", "Shrike hourly" in N.do_update(dry=True, force=True) and len(posts) == 1)
# ---- emergency checks
reset(); os.environ["OVN_LLM_HEALTH_URL"] = "http://127.0.0.1:1/x"
ok("model down < 20 min: no emergency yet", not [e for e in N.emergency_checks() if "model" in e[0]])
open(os.path.join(ST, "notify_bad_llm"), "w").write(str(time.time() - 1300))
ok("model down >= 20 min -> emergency", any("model is down" in e[0] for e in N.emergency_checks()))
os.environ["OVN_LLM_HEALTH_URL"] = "http://127.0.0.1:%d/ok" % srv.server_port
class G(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self): self.send_response(200); self.send_header("Content-Length", "1"); self.end_headers(); self.wfile.write(b"k")
g = HTTPServer(("127.0.0.1", 0), G); threading.Thread(target=g.serve_forever, daemon=True).start()
os.environ["OVN_LLM_HEALTH_URL"] = "http://127.0.0.1:%d/ok" % g.server_port
ok("model healthy clears the bad-since marker", not [e for e in N.emergency_checks() if "model" in e[0]] and not os.path.exists(os.path.join(ST, "notify_bad_llm")))
open(os.path.join(ST, "outcomes.jsonl"), "w").write("")
ok("work queued + nothing landed in 3h + not paused -> 'Fleet stalled'", any("Fleet stalled" in e[0] for e in N.emergency_checks()))
open(os.path.join(ST, "PAUSED"), "w").write("")
ok("a paused fleet is not 'stalled'", not any("stalled" in e[0] for e in N.emergency_checks())); os.remove(os.path.join(ST, "PAUSED"))
open(os.path.join(ST, "outcomes.jsonl"), "w").write(json.dumps({"ts": iso(time.time() - 60), "repo": "gitlark", "class": "landed"}) + "\n")
ok("a recent landing means not stalled", not any("stalled" in e[0] for e in N.emergency_checks()))
du = N.shutil.disk_usage; N.shutil.disk_usage = lambda p: type("D", (), {"used": 95, "total": 100})()
ok("disk >= 92% -> emergency", any("Disk almost full" in e[0] for e in N.emergency_checks())); N.shutil.disk_usage = du
N.shutil.disk_usage = lambda p: (_ for _ in ()).throw(OSError("x")); ok("a disk_usage error is ignored", isinstance(N.emergency_checks(), list)); N.shutil.disk_usage = du
reset(); open(os.path.join(ST, "notify_bad_llm"), "w").write(str(time.time() - 5000)); os.environ["OVN_LLM_HEALTH_URL"] = "http://127.0.0.1:1/x"
ok("do_check pushes the emergency and reports it", "Local AI model is down -> sent" in N.do_check() and posts)
_before = len(posts); N.do_check(dry=True); ok("do_check --dry-run posts nothing", len(posts) == _before)
reset(); os.environ["OVN_LLM_HEALTH_URL"] = "http://127.0.0.1:%d/ok" % g.server_port
open(os.path.join(ST, "outcomes.jsonl"), "w").write(json.dumps({"ts": iso(time.time() - 60), "repo": "gitlark", "class": "landed"}) + "\n")
_du2 = N.shutil.disk_usage; N.shutil.disk_usage = lambda p: __import__('collections').namedtuple('du', 'total used free')(100, 10, 90)   # the real disk of the machine running the test must not decide this (the Mac data volume is ~97% full)
_dc = N.do_check(); N.shutil.disk_usage = _du2
ok("no emergencies -> says so", _dc == "no emergencies")
# ---- the relay server end to end
reset(); rs = N.ThreadingHTTPServer(("127.0.0.1", 0), N._Handler); threading.Thread(target=rs.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % rs.server_port
def post(path, title, prio="default", body="b", level=None):
    rq = urllib.request.Request(base + path, data=body.encode(), method="POST"); rq.add_header("Title", title); rq.add_header("Priority", prio)
    if level: rq.add_header("X-Ovn-Level", level)
    return json.loads(urllib.request.urlopen(rq, timeout=5).read())
j = post("/shrike_ovn_x", "Hygiene stalled", "high")
ok("relay: a note returns an ntfy-style JSON ack and is buffered", j.get("event") == "message" and j["action"] == "noted" and not posts)
rq = urllib.request.Request(base + "/shrike_ovn_x", data=b"b", method="POST"); rq.add_header("Title", "=?UTF-8?B?8J+UtCBET1dOOiBtb2pp?="); rq.add_header("Priority", "default")
_ack = json.loads(urllib.request.urlopen(rq, timeout=5).read())
ok("relay: an RFC2047-encoded emoji title is decoded and classified as an emergency (DOWN)", _ack["action"].startswith("emergency:") and len(posts) == 1)
reset()
j = post("/shrike_ovn_x", "x", level="emergency")
ok("relay: explicit emergency is forwarded upstream", j["action"].startswith("emergency:") and len(posts) == 1)
rq = urllib.request.Request(base + "/", data=b"x", method="PUT"); rq.add_header("Title", "Overnight queue")
ok("relay: PUT works and a dropped title is acknowledged", json.loads(urllib.request.urlopen(rq, timeout=5).read())["action"] == "dropped")
ok("relay: GET /health answers 200", json.loads(urllib.request.urlopen(base + "/health", timeout=5).read())["ok"] is True)
try: urllib.request.urlopen(base + "/nope", timeout=5); hit404 = False
except urllib.error.HTTPError as e: hit404 = e.code == 404
ok("relay: unknown GET path is 404", hit404)
h = N._Handler.__new__(N._Handler); h.client_address = ("8.8.8.8", 1); ok("relay: public IPs are refused", h._allowed() is False)
h.client_address = ("192.168.68.50", 1); ok("relay: LAN IPs are accepted", h._allowed() is True)
h.client_address = ("100.79.64.64", 1); ok("relay: tailscale IPs are accepted", h._allowed() is True)
h.client_address = ("garbage", 1); ok("relay: a malformed client address is refused", h._allowed() is False)
# ---- CLI
out = io.StringIO(); so = sys.stdout; sys.stdout = out
rc1 = N.main(["x"]); rc2 = N.main(["x", "bogus"]); rc3 = N.main(["x", "update", "--dry-run", "--force"]); rc4 = N.main(["x", "check", "--dry-run"]); sys.stdout = so
ok("CLI: no args / unknown command -> usage, rc 2; update/check dry runs rc 0", (rc1, rc2, rc3, rc4) == (2, 2, 0, 0))
srvcalls = []; N.serve = lambda port: srvcalls.append(port); N.main(["x", "serve", "--port", "9123"]); N.main(["x", "serve"])
ok("CLI: serve passes --port through (default 8099)", srvcalls == [9123, 8099])
print("  %d passed, %d failed" % (ok_n, bad_n)); sys.exit(1 if bad_n else 0)
