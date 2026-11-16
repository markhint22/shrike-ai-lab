"""q-weekend-fixes item 4 (2026-11-15): stale Mac health copy.
state/mac_jobs_health.json on the box was 6.3 days old (the Mac supervisor is not installed); the relay kept pushing EMERGENCIES: 9 x 'Mac jobs: commit-push' (every cooldown) and 2 x 'Mac jobs supervisor
silent' (daily). Now: health older than OVN_MAC_SUP_STALE_H (6 h) = the Mac jobs are UNKNOWN -> at most ONE 'Mac supervision dead (health file Nd old)' WARN note per local day (no push), and a 'Mac jobs: <x>'
emergency repeats at most once per 24 h while UNKNOWN. Legacy knobs: OVN_MAC_SUP_ALERT=emergency|off, OVN_MAC_UNKNOWN_REPEAT=off. The promote-gate evidence-freshness emergency is a different alert and untouched.
Hermetic: fake clock, local fake upstream, temp state, TZ=UTC. Each behaviour is also run against a mutated copy of ovn_notify.py and must FAIL there."""
import importlib.util, json, os, re, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, HTTPServer
os.environ.update(TZ="UTC", NTFY_SERVER="http://127.0.0.1:9"); os.environ.pop("OVN_NOTIFY_DISABLE", None); time.tzset()
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "ovn_notify.py")
T = tempfile.mkdtemp()
POSTS = []
class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        POSTS.append({"title": self.headers.get("Title"), "prio": self.headers.get("Priority"), "body": self.rfile.read(n).decode()})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")
srv = HTTPServer(("127.0.0.1", 0), Fake); threading.Thread(target=srv.serve_forever, daemon=True).start()
os.environ["OVN_NOTIFY_UPSTREAM"] = "http://127.0.0.1:%d" % srv.server_port
CLK = [1795000000.0]   # fixed epoch (2026-11-17 UTC morning)
H = 3600.0

def load(src):
    st = tempfile.mkdtemp(dir=T); os.environ["OVN_NOTIFY_STATE"] = st; os.environ["NTFY_TOPIC"] = "t_q"
    for k in ("OVN_MAC_SUP_ALERT", "OVN_MAC_SUP_STALE_H", "OVN_MAC_UNKNOWN_REPEAT", "OVN_MAC_UNKNOWN_REPEAT_S", "OVN_ESC_MAC_SUPERVISOR", "OVN_NOTIFY_DAILY_CAP"): os.environ.pop(k, None)
    spec = importlib.util.spec_from_file_location("nq_%d" % abs(hash(st)), src); N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)
    N.now = lambda: CLK[0]; N.DIGEST_CAP = 24; N.EMERGENCY_CAP = 50; N.DAILY_CAP_EXPLICIT = False; N.DAILY_CAP = 80
    N.emergency_checks = lambda dry=False: []
    return N, st

def health(st, age_h):
    p = os.path.join(st, "mac_jobs_health.json")
    json.dump({"ts": CLK[0] - age_h * H, "healthy": False}, open(p, "w")); os.utime(p, (CLK[0], CLK[0]))   # fresh mtime: the age must come from ts

def notes(st):
    p = os.path.join(st, "notify_notes.jsonl")
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []

def mac_post(N, key="commit-push", body="bridge cannot push"):
    return N.handle_publish("t_q", {"title": "Mac jobs: " + key, "priority": "urgent", "x-ovn-level": "emergency"}, body, source="192.168.68.50")

def checks(src):
    R = []
    def ok(label, cond): R.append((label, bool(cond)))
    # ---- supervisor verdict ----
    N, st = load(src)
    ok("no health file ever written -> no verdict", N.mac_supervisor_stale() is None and not N.mac_jobs_unknown())
    health(st, 1); ok("1h-old copy is fresh", N.mac_supervisor_stale() is None and not N.mac_jobs_unknown())
    health(st, 5.5); ok("5.5h-old copy is still under the 6h limit", N.mac_supervisor_stale() is None)
    health(st, 7); v = N.mac_supervisor_stale()
    ok("7h-old copy -> 'Mac supervision dead (health file 7h old)'", v is not None and v[0] == "Mac supervision dead (health file 7h old)" and "UNKNOWN" in v[1] and N.mac_jobs_unknown())
    health(st, 6.3 * 24); v = N.mac_supervisor_stale()
    ok("6.3 day old copy -> '(health file 6d old)' (days once >= 1 day)", v is not None and v[0] == "Mac supervision dead (health file 6d old)")
    # ---- do_check: ONE WARN note per day, no push ----
    N, st = load(src); health(st, 6.3 * 24); del POSTS[:]
    out = N.do_check()
    ok("do_check (default): NO push for a dead supervisor", not POSTS and "noted" in out)
    ok("do_check (default): ONE note with the new title", len(notes(st)) == 1 and notes(st)[0]["title"].startswith("Mac supervision dead (health file 6d old)") and notes(st)[0]["prio"] == "default")
    N.do_check(); CLK[0] += 3 * H; health(st, 6.3 * 24 + 3 / 24); N.do_check()
    ok("same local day: still ONE note, still no push", len(notes(st)) == 1 and not POSTS)
    CLK[0] += 24 * H; health(st, 7.5 * 24); N.do_check()
    ok("next local day: exactly one more note", len(notes(st)) == 2 and not POSTS)
    CLK[0] -= 27 * H
    out = N.do_check(dry=True)
    ok("dry-run writes nothing", len(notes(st)) == 2)
    # modes
    N, st = load(src); health(st, 50); os.environ["OVN_MAC_SUP_ALERT"] = "emergency"; del POSTS[:]; N.do_check()
    ok("OVN_MAC_SUP_ALERT=emergency: legacy 'Mac jobs supervisor silent' urgent push", len(POSTS) == 1 and POSTS[0]["title"] == "Mac jobs supervisor silent" and POSTS[0]["prio"] == "urgent")
    N, st = load(src); health(st, 50); os.environ["OVN_MAC_SUP_ALERT"] = "off"; del POSTS[:]; N.do_check()
    ok("OVN_MAC_SUP_ALERT=off: nothing at all", not POSTS and not notes(st))
    os.environ.pop("OVN_MAC_SUP_ALERT", None)
    # ---- 'Mac jobs: <x>' emergency repeat throttle while UNKNOWN ----
    N, st = load(src); health(st, 6.3 * 24); del POSTS[:]
    r1 = mac_post(N); CLK[0] += 4 * H; health(st, 6.3 * 24 + 4 / 24)
    r2 = mac_post(N)
    ok("stale health: first Mac emergency is pushed", r1 == "emergency:sent" and len(POSTS) == 1)
    ok("stale health: the repeat after 4 h (> 3 h cooldown) is DEDUPED, not pushed", r2 == "emergency:deduped" and len(POSTS) == 1)
    ok("stale health: the suppressed repeat is kept as a note for the digest", any(n["title"] == "Mac jobs: commit-push" for n in notes(st)))
    CLK[0] += 21 * H; health(st, 7.3 * 24)
    r3 = mac_post(N)
    ok("stale health: pushed again once 24 h have passed", r3 == "emergency:sent" and len(POSTS) == 2)
    CLK[0] += 1 * H; r4 = mac_post(N, "qa-staging-export")
    ok("a DIFFERENT Mac jobs key has its own clock", r4 == "emergency:sent" and len(POSTS) == 3)
    N.handle_publish("t_q", {"title": "Branch hygiene STUCK: iptv_apps", "priority": "urgent", "x-ovn-level": "emergency"}, "x")
    CLK[0] += 4 * H; N.handle_publish("t_q", {"title": "Branch hygiene STUCK: iptv_apps", "priority": "urgent", "x-ovn-level": "emergency"}, "x")
    ok("non-Mac emergencies keep the plain 3 h cooldown even while the Mac is UNKNOWN", len(POSTS) == 5)
    N, st = load(src); health(st, 0.5); del POSTS[:]
    r1 = mac_post(N); CLK[0] += 4 * H; health(st, 0.5); r2 = mac_post(N)
    ok("FRESH health: the Mac emergency repeats after the plain 3 h cooldown (unchanged)", r1 == "emergency:sent" and r2 == "emergency:sent" and len(POSTS) == 2)
    N, st = load(src); health(st, 6.3 * 24); os.environ["OVN_MAC_UNKNOWN_REPEAT"] = "off"; del POSTS[:]
    r1 = mac_post(N); CLK[0] += 4 * H; health(st, 6.3 * 24); r2 = mac_post(N); os.environ.pop("OVN_MAC_UNKNOWN_REPEAT")
    ok("OVN_MAC_UNKNOWN_REPEAT=off restores the plain cooldown", r2 == "emergency:sent" and len(POSTS) == 2)
    N, st = load(src); del POSTS[:]
    r1 = mac_post(N); CLK[0] += 4 * H; r2 = mac_post(N)
    ok("no health file at all: plain cooldown (unchanged)", r2 == "emergency:sent" and len(POSTS) == 2)
    # ---- review (c): the day file and the health file can be garbage; a future ts is UNKNOWN, never fresh ----
    N, st = load(src); health(st, 6.3 * 24); open(os.path.join(st, "notify_mac_dead_day"), "wb").write(b"\xff\xfe\x00\x80garbage\xc3\x28"); del POSTS[:]
    try: out = N.do_check()
    except Exception as e: out = "EXC %r" % (e,)
    ok("binary/undecodable notify_mac_dead_day: do_check does not crash and emits the WARN once", "noted" in out and len(notes(st)) == 1 and not POSTS)
    N, st = load(src); health(st, 6.3 * 24); open(os.path.join(st, "notify_mac_dead_day"), "w").write("not-a-date"); N.do_check()
    ok("garbled (decodable) notify_mac_dead_day: WARN emitted (day mismatch)", len(notes(st)) == 1)
    N, st = load(src); p = os.path.join(st, "mac_jobs_health.json"); open(p, "wb").write(b"\xff\xfe{ not json"); os.utime(p, (CLK[0] - 9 * H, CLK[0] - 9 * H))
    try: v = N.mac_supervisor_stale()
    except Exception as e: v = "EXC %r" % (e,)
    ok("undecodable health JSON: falls back to the mtime (9h -> stale), no crash", isinstance(v, tuple) and v[0] == "Mac supervision dead (health file 9h old)")
    N, st = load(src); p = os.path.join(st, "mac_jobs_health.json"); open(p, "w").write('{"ts": NaN}'); os.utime(p, (CLK[0] - 9 * H, CLK[0] - 9 * H))
    try: v = N.mac_supervisor_stale()
    except Exception as e: v = "EXC %r" % (e,)
    ok("health ts NaN: falls back to the mtime, no crash", isinstance(v, tuple) and "9h" in v[0])
    N, st = load(src); p = os.path.join(st, "mac_jobs_health.json"); open(p, "w").write('{"ts": 1' + "0" * 400 + '}'); os.utime(p, (CLK[0] - 9 * H, CLK[0] - 9 * H))
    try: v = N.mac_supervisor_stale()
    except Exception as e: v = "EXC %r" % (e,)
    ok("health ts an absurd integer (OverflowError): falls back to the mtime, no crash", isinstance(v, tuple) and "9h" in v[0])
    N, st = load(src); p = os.path.join(st, "mac_jobs_health.json"); json.dump({"ts": CLK[0] + 30 * H}, open(p, "w")); os.utime(p, (CLK[0], CLK[0]))
    v = N.mac_supervisor_stale()
    ok("health ts 30h in the FUTURE: UNKNOWN (stale verdict), never fresh", v is not None and N.mac_jobs_unknown())
    N, st = load(src); p = os.path.join(st, "mac_jobs_health.json"); json.dump({"ts": CLK[0] + 60}, open(p, "w")); os.utime(p, (CLK[0], CLK[0]))
    ok("health ts 1 min ahead (clock skew) is still fresh", N.mac_supervisor_stale() is None and not N.mac_jobs_unknown())
    return R

def run(src):
    CLK[0] = 1795000000.0
    try: return checks(src)
    except Exception as e: return [("EXCEPTION %r" % (e,), False)]

real = run(SRC)
bad = [l for l, c in real if not c]
for l, c in real: print(("  ok   " if c else "  FAIL ") + l)
code = open(SRC, encoding="utf-8").read()
MUT = [
    ("threshold-never-stale", "if age is None or age < MAC_SUP_STALE_S:\n        return None", "if True:\n        return None"),
    ("emergency-default", '(os.environ.get("OVN_MAC_SUP_ALERT", "warn") or "warn")', '(os.environ.get("OVN_MAC_SUP_ALERT", "emergency") or "emergency")'),
    ("no-day-key", "        if open(path).read().strip() == day:\n            return \"already-today\"", "        if False:\n            return \"already-today\""),
    ("throttle-off", 'and mac_jobs_unknown():\n            cool', 'and False:\n            cool'),
    ("throttle-all-keys", 'if key.startswith("Mac jobs:") and', 'if True and'),
    ("day-read-oserror-only", '    except Exception:    # q-weekend-fixes review (c): a missing/binary', '    except OSError:    # q-weekend-fixes review (c): a missing/binary'),
    ("future-ts-fresh", "    if age < -300:", "    if False:"),
    ("age-except-narrow", "    except Exception:    # any unreadable/odd content", "    except (OSError, ValueError, AttributeError, TypeError):    # any unreadable/odd content"),
    ("note-not-written", '    add_note(title, body, "default", "mac-supervision")', '    pass'),
    ("repeat-switch-ignored", 'os.environ.get("OVN_MAC_UNKNOWN_REPEAT", "on") != "off" and mac_jobs_unknown()', 'mac_jobs_unknown()'),
]
n_ok = 0
for name, old, new in MUT:
    if code.count(old) != 1:
        print("  FAIL mutant %s: anchor found %d times" % (name, code.count(old))); bad.append("anchor " + name); continue
    mp = os.path.join(T, "mut_%s.py" % name); open(mp, "w", encoding="utf-8").write(code.replace(old, new))
    res = run(mp)
    nfail = sum(1 for _, c in res if not c)
    if nfail: print("  ok   mutant %s is caught (%d check(s) failed)" % (name, nfail)); n_ok += 1
    else: print("  FAIL mutant %s survived" % name); bad.append("mutant " + name)
print("q-mac-stale: %s (%d failing)" % ("all passed" if not bad else "FAIL", len(bad)))
sys.exit(1 if bad else 0)
