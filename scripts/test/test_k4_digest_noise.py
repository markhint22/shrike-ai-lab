"""K4 (2026-11-01) digest noise + supply-floor alert.
 ovn_notify.py: OVN_DIGEST_DEDUPE (one digest per title-shape+hour), OVN_EMPTY_ONCE ('Queue empty' only on a state change or every 6h), OVN_PASSRATE_MIN (>=5 outcomes for a headline).
 ovn_research_trigger_check.py: OVN_READY_FLOOR (warn when <= 2 [ready] roadmap features, before the lane is dry).
 Every flag: off = old behaviour, shadow (default) = old behaviour + a 'would ...' log line, on = enforced. Injected clock; urlopen is a counter (no network).
 usage: test_k4_digest_noise.py   env: OVN_NOTIFY_SRC / OVN_TRIGGER_SRC = (mutated) copies, used by the .sh wrapper's mutation checks."""
import calendar, importlib.util, json, os, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmp_track
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.environ.get("OVN_NOTIFY_SRC") or os.path.join(ROOT, "scripts", "ovn_notify.py")
TRIG = os.environ.get("OVN_TRIGGER_SRC") or os.path.join(ROOT, "scripts", "ovn_research_trigger_check.py")
os.environ["TZ"] = "UTC"; time.tzset()   # stats_line() takes "today" from the local midnight: pin it
T = tempfile.mkdtemp()
Q = os.path.join(T, "q"); ST = os.path.join(Q, "state")
os.makedirs(ST)
os.environ["OVN_SUPPLY_LINE"] = "0"
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_test", OVN_NOTIFY_DAILY_CAP="50", OVN_NOTIFY_UPSTREAM="http://127.0.0.1:9", OVN_LLM_HEALTH_URL="http://127.0.0.1:9/x")
os.environ.pop("OVN_NOTIFY_DISABLE", None)   # ntfy_guard.sh exports OVN_NOTIFY_DISABLE=1 for the suite; these tests drive ovn_notify against a local fake upstream
for k in ("OVN_DIGEST_DEDUPE", "OVN_EMPTY_ONCE", "OVN_PASSRATE_MIN", "OVN_PASSRATE_MIN_N", "OVN_EMPTY_REPEAT_H", "OVN_NOTIFY_DISABLE", "OVN_IDLE_LINE"):
    os.environ.pop(k, None)
os.environ["OVN_IDLE_LINE"] = "0"
spec = importlib.util.spec_from_file_location("ovn_notify_k4", SRC)
N = importlib.util.module_from_spec(spec)
spec.loader.exec_module(N)

ok_n = bad_n = 0
def ok(label, cond):
    global ok_n, bad_n
    if cond: ok_n += 1; print("  ok   " + label)
    else: bad_n += 1; print("  FAIL " + label)

BASE = calendar.timegm((2026, 11, 1, 1, 20, 0))
CLOCK = [BASE]
N.now = lambda: CLOCK[0]
N.http_ok = lambda *a, **k: True
URLOPEN = []
class _Resp:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *a): return False
N.urllib.request.urlopen = lambda req, timeout=0: (URLOPEN.append(req.full_url), _Resp())[1]
N.shutil.disk_usage = lambda p: __import__("collections").namedtuple("du", "total used free")(100, 40, 60)
N.boot_notes = lambda at=None: []
N.autodeploy_report = lambda t: (None, None)
N.slo_lines = lambda t: []
N.duty_line = lambda t: None

def iso(ago): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(BASE - ago))
def write_outcomes(rows):
    with open(os.path.join(ST, "outcomes.jsonl"), "w") as f:
        for r in rows: f.write(json.dumps(r) + "\n")
def orow(ago, sev="good", cls="landed", repo="iptv_apps"):
    return {"ts": iso(ago), "repo": repo, "id": "i", "type": "aider_fix", "class": cls, "severity": sev, "status": "x"}
def set_queue(depths):
    for name, n in depths.items():
        d = os.path.join(Q, "repos", name); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, "OVERNIGHT_PROGRESS.md"), "w").write("# p\n" + "".join("- [ ] item %d\n" % i for i in range(n)))
    json.dump([{"repo": "repos/" + r, "enabled": True} for r in depths], open(os.path.join(Q, "tasks.json"), "w"))
def reset():
    for f in os.listdir(ST): os.remove(os.path.join(ST, f))
    CLOCK[0] = BASE; del URLOPEN[:]
def shadow_log():
    try: return open(os.path.join(ST, "notify_shadow.log")).read()
    except OSError: return ""
def modes(**kw):
    for k in ("OVN_DIGEST_DEDUPE", "OVN_EMPTY_ONCE", "OVN_PASSRATE_MIN"): os.environ.pop(k, None)
    for k, v in kw.items(): os.environ[k] = v

H = 3600
# ===================================================== (a) digest dedupe on (key, hour)
reset(); set_queue({"iptv_apps": 9}); write_outcomes([orow(60 * i) for i in range(6)])
modes(OVN_DIGEST_DEDUPE="on")
r1 = N.forward("Shrike hourly - 2 to look at", "b1", kind="digest")
CLOCK[0] += 20 * 60
r2 = N.forward("Shrike hourly - 3 to look at", "b1", kind="digest")
ok("D1 on: a second digest in the same hour (title differs only by a number, SAME body) is deduped, not sent", (r1, r2) == ("sent", "deduped") and len(URLOPEN) == 1)
r2b = N.forward("Shrike hourly - 3 to look at", "b2-different-items", kind="digest")
ok("D1b on: a same-hour digest whose BODY changed (new problem / other items) is NOT deduped (K4 review fix)", r2b == "sent" and len(URLOPEN) == 2)
CLOCK[0] += 45 * 60
ok("D2 on: the next hour's digest goes out", N.forward("Shrike hourly - 3 to look at", "b1", kind="digest") == "sent" and len(URLOPEN) == 3)
reset(); modes(OVN_DIGEST_DEDUPE="on")
N.forward("Shrike hourly - all good", "x", kind="digest"); CLOCK[0] += 60
ok("D3 on: a digest and an emergency are independent (an emergency in the same hour still sends)", N.forward("Deploy failed: X", "y", "urgent", kind="emergency") == "sent")
reset(); modes()   # default = shadow
N.forward("Shrike hourly - 2 to look at", "b1", kind="digest"); CLOCK[0] += 60
r = N.forward("Shrike hourly - 2 to look at", "b1", kind="digest")
ok("D4 default (shadow): the duplicate IS still sent (old behaviour) and the would-suppress line is logged", r == "sent" and len(URLOPEN) == 2 and "OVN_DIGEST_DEDUPE | would suppress a second digest" in shadow_log())
reset(); modes(OVN_DIGEST_DEDUPE="off")
N.forward("Shrike hourly - 2 to look at", "b1", kind="digest"); CLOCK[0] += 60
ok("D5 off: duplicate sent, no shadow line", N.forward("Shrike hourly - 2 to look at", "b1", kind="digest") == "sent" and shadow_log() == "")
reset(); modes(OVN_DIGEST_DEDUPE="on"); set_queue({"iptv_apps": 9}); write_outcomes([orow(60 * i) for i in range(6)])
a = N.do_update(force=True); CLOCK[0] += 10 * 60
b = N.do_update(force=True)
ok("D6 on: do_update twice in one hour sends ONE digest (the 01:20 duplicate)", len(URLOPEN) == 1 and "(deduped)" in b)
# D7 (K4 review fix): a 'deduped' digest was NOT delivered, so it must not mark the boot note as reported
_real_bn = N.boot_notes
N.boot_notes = lambda at=None: [{"title": "Box rebooted 5m ago", "text": "clean restart", "prio": "default", "boot": 1234567.0}]
reset(); modes(OVN_DIGEST_DEDUPE="on"); set_queue({"iptv_apps": 9}); write_outcomes([orow(60 * i) for i in range(6)])
N.do_update(force=True)
_br = os.path.join(ST, "notify_boot_reported")
try: os.remove(_br)
except OSError: pass
CLOCK[0] += 10 * 60
_d7 = N.do_update(force=True)
ok("D7 on: a deduped digest does NOT mark the boot note reported (the reboot line is not swallowed)", "(deduped)" in _d7 and not os.path.exists(_br))
N.boot_notes = _real_bn

# ===================================================== (b) 'Queue empty' once per state change / 6h
def empty_in(body): return any(l.startswith("• Queue empty: ") for l in body.split("\n"))
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_EMPTY_ONCE="on", OVN_DIGEST_DEDUPE="off")
N.do_update(force=True)
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_EMPTY_ONCE="on", OVN_DIGEST_DEDUPE="off")
t1 = N.compose_update(at=BASE)
ok("E1 on: nothing recorded yet -> the bullet appears, a single line for both repos", t1[1].count("Queue empty:") == 1 and "iptv_apps, xlite" in t1[1])
N.do_update(force=True)   # sends + records the state
CLOCK[0] += 1 * H
ok("E2 on: 1h later, same empty set -> the bullet is gone", not empty_in(N.compose_update(at=CLOCK[0])[1]))
CLOCK[0] += 5 * H + 60
ok("E3 on: 6h+ after the last emission the bullet repeats once", empty_in(N.compose_update(at=CLOCK[0])[1]))
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_EMPTY_ONCE="on", OVN_DIGEST_DEDUPE="off")
N.do_update(force=True); CLOCK[0] += H
set_queue({"iptv_apps": 0, "xlite": 7})
ok("E4 on: the empty SET changed (xlite refuelled) -> the bullet appears again with the new set", "Queue empty: iptv_apps" in N.compose_update(at=CLOCK[0])[1] and "xlite" not in [l for l in N.compose_update(at=CLOCK[0])[1].split("\n") if l.startswith("• Queue empty")][0])
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_EMPTY_ONCE="on", OVN_DIGEST_DEDUPE="off")
N.do_update(force=True); CLOCK[0] += H; set_queue({"iptv_apps": 5, "xlite": 5}); N.do_update(force=True)   # recovered, digest sent
CLOCK[0] += H; set_queue({"iptv_apps": 0, "xlite": 0})
ok("E5 on: empty -> recovered -> empty again is a state change: the bullet returns", empty_in(N.compose_update(at=CLOCK[0])[1]))
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_DIGEST_DEDUPE="off")   # default = ON since 2026-11-02 (N6)
N.do_update(force=True); CLOCK[0] += H
ok("E6 default (ON since 2026-11-02): the unchanged bullet is dropped on the next digest, nothing logged as 'would'", not empty_in(N.compose_update(at=CLOCK[0])[1]) and "OVN_EMPTY_ONCE | would drop" not in shadow_log())
reset(); set_queue({"iptv_apps": 0, "xlite": 0}); write_outcomes([]); modes(OVN_DIGEST_DEDUPE="off", OVN_EMPTY_ONCE="shadow")   # the kill switch back to log-only
N.do_update(force=True); CLOCK[0] += H
ok("E6b OVN_EMPTY_ONCE=shadow (kill switch): the unchanged bullet is STILL shown (old behaviour) and the would-drop is logged", empty_in(N.compose_update(at=CLOCK[0])[1]) and "OVN_EMPTY_ONCE | would drop the unchanged 'Queue empty: iptv_apps,xlite'" in shadow_log())
modes(OVN_EMPTY_ONCE="off", OVN_DIGEST_DEDUPE="off"); reset(); set_queue({"iptv_apps": 0, "xlite": 0}); N.do_update(force=True); CLOCK[0] += H
ok("E7 off: always shown, no state file written", empty_in(N.compose_update(at=CLOCK[0])[1]) and not os.path.exists(os.path.join(ST, "notify_empty_state.json")))

# ===================================================== (c) pass-rate headline needs >= 5 outcomes
reset(); set_queue({"iptv_apps": 9}); modes(OVN_PASSRATE_MIN="on")
write_outcomes([orow(60), orow(120, "bad", "reverted")])
ok("P1 on: 2 outcomes today -> no 'Pass rate' headline (a 1/2 'rate' is noise)", "Pass rate:" not in N.compose_update(at=BASE)[1] and "Outcomes today: 2" in N.compose_update(at=BASE)[1])
write_outcomes([orow(60 * i) for i in range(1, 6)])
ok("P2 on: exactly 5 outcomes -> the headline is shown", "Pass rate: last hour 5/5 (100%)" in N.compose_update(at=BASE)[1])
write_outcomes([orow(60 * i) for i in range(1, 5)])
ok("P3 on: 4 outcomes -> still no headline (boundary)", "Pass rate:" not in N.compose_update(at=BASE)[1])
modes(OVN_PASSRATE_MIN="on"); write_outcomes([orow(60), orow(120, "bad", "reverted")])
_b = N.compose_update(at=BASE)[1]
ok("P5 on: a small sample drops ONLY the today rate - the last-hour figure and the 'By tier today' split are kept", "last hour 1/2 (50%)" in _b and "By tier today:" in _b and "Pass rate:" not in _b)
modes(); write_outcomes([orow(60), orow(120, "bad", "reverted")]); reset_shadow = os.path.join(ST, "notify_shadow.log")
ok("P4 default (ON since 2026-11-02): the small-sample headline is replaced, no 'would' line", "Pass rate:" not in N.compose_update(at=BASE)[1] and "Outcomes today: 2" in N.compose_update(at=BASE)[1] and "OVN_PASSRATE_MIN | would replace" not in shadow_log())
modes(OVN_PASSRATE_MIN="shadow"); write_outcomes([orow(60), orow(120, "bad", "reverted")])
ok("P4b OVN_PASSRATE_MIN=shadow (kill switch): the headline is still shown and the would-replace is logged", "Pass rate:" in N.compose_update(at=BASE)[1] and "OVN_PASSRATE_MIN | would replace the pass-rate headline" in shadow_log())

# ===================================================== (d) supply-floor alert at [ready] <= 2
def trig_run(mode, ready, planner_hours_ago=None, extra_env=None, repo="alpha", now_epoch=None):
    d = tempfile.mkdtemp(); od = os.path.join(d, "overnight-queue")
    for s in ("logs", "state", "roadmap"): os.makedirs(os.path.join(od, s))
    open(os.path.join(od, "roadmap", repo + ".md"), "w").write("## Roadmap\n" + "".join("- [ ] [P2] [ready] feature %d\n" % i for i in range(ready)) + "- [ ] [P2] [needs-research] other\n- [x] [P1] [ready] done one\n")
    healthy = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 600))
    open(os.path.join(od, "logs", "ovn_planner.log"), "w").write("%s %s: backlog=40 >= 10 - no planning needed\n" % (healthy, repo))
    env = dict(os.environ, HOME=d, OVN_DIR=od, OVN_READY_FLOOR=mode, TZ="UTC")
    env.update(extra_env or {})
    subprocess.run([sys.executable, TRIG, "2"], env=env, capture_output=True, text=True)
    st = os.path.join(od, "state")
    rd = lambda n: open(os.path.join(st, n)).read() if os.path.exists(os.path.join(st, n)) else ""
    return rd("alerts.log"), rd("roadmap_floor_shadow.log"), rd("roadmap_ready_floor_alerted.json")
al, sh, mk = trig_run("on", 2)
ok("R1 on: 2 [ready] features (a healthy lane, backlog 40, NOT starving) -> a 'roadmap-feature floor' warn in alerts.log", "roadmap-feature floor: alpha has only 2 [ready]" in al and "warn | ongoing-alpha" in al)
ok("R2 the dedupe marker is written (one alert per lane per day)", '"alpha"' in mk)
al, sh, mk = trig_run("on", 3)
ok("R3 on: 3 [ready] features is above the floor -> silent", al == "" and sh == "")
al, sh, mk = trig_run("on", 0)
ok("R4 on: 0 [ready] -> alerts too", "has only 0 [ready]" in al)
al, sh, mk = trig_run("on", 5, extra_env={"OVN_READY_FLOOR_MAX": "6"})
ok("R5 OVN_READY_FLOOR_MAX=6 moves the floor", "has only 5 [ready]" in al)
al, sh, mk = trig_run("shadow", 1)
ok("R6 shadow: alerts.log untouched, 'SHADOW would alert' line in roadmap_floor_shadow.log", al == "" and "SHADOW would alert: " in sh and "has only 1 [ready]" in sh)
d = tempfile.mkdtemp(); od = os.path.join(d, "overnight-queue")
for s_ in ("logs", "state", "roadmap"): os.makedirs(os.path.join(od, s_))
open(os.path.join(od, "roadmap", "alpha.md"), "w").write("- [ ] [P2] [ready] f\n")
open(os.path.join(od, "logs", "ovn_planner.log"), "w").write("%s alpha: backlog=40 >= 10 - no planning needed\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 60)))
for _ in range(3):
    subprocess.run([sys.executable, TRIG, "2"], env=dict(os.environ, HOME=d, OVN_DIR=od, OVN_READY_FLOOR="on", TZ="UTC", OVN_CHRONIC_DAILY="off"), capture_output=True, text=True)
_alp = os.path.join(od, "state", "alerts.log"); _al = open(_alp).read() if os.path.exists(_alp) else ""
ok("R9 on: three runs the same day write ONE alert line per lane (per-day dedupe)", _al.count("roadmap-feature floor: alpha") == 1)
al, sh, mk = trig_run("off", 1)
ok("R7 off: nothing at all", al == "" and sh == "" and mk == "")
d_env = dict(os.environ); d_env.pop("OVN_READY_FLOOR", None)
d = tempfile.mkdtemp(); od = os.path.join(d, "overnight-queue")
for s in ("logs", "state", "roadmap"): os.makedirs(os.path.join(od, s))
open(os.path.join(od, "roadmap", "alpha.md"), "w").write("- [ ] [P2] [ready] f\n")
open(os.path.join(od, "logs", "ovn_planner.log"), "w").write("%s alpha: backlog=40 >= 10 - no planning needed\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 60)))
subprocess.run([sys.executable, TRIG, "2"], env=dict(d_env, HOME=d, OVN_DIR=od), capture_output=True, text=True)
ok("R8 default (env unset) = shadow: alerts.log empty, shadow log written", not os.path.exists(os.path.join(od, "state", "alerts.log")) and os.path.exists(os.path.join(od, "state", "roadmap_floor_shadow.log")))

print("  %d passed, %d failed" % (ok_n, bad_n))
sys.exit(1 if bad_n else 0)
