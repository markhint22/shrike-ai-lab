"""Y6 notify fixes 2 (2026-11-04): ovn_notify.py + vercel_state_check.py.
 1 daily prod promote folded into the next digest as ONE bullet (never dropped, cleared only by a REAL send); research-batch scorecard = ONE weekly digest line
 2 OVN_ESC_MAC_SUPERVISOR defaults to ON (once per day, kill switch env)
 3 escalate --rolling-h: once per ROLLING window (not calendar day)
 4 'Branch reconcile CONFLICT' bullet names repo + branch, 6 h cooldown
 5 vercel prod ERROR -> READY: ONE low-priority recovery line
 6 'Suite red' naming/escalation ignores the harness fixture tests
 7 'Features ready to test' / 'Batch health' bullets only on a state change or every 6 h (OVN_BULLET_ONCE)
Hermetic: injected clock, urlopen captured (no network), TZ=UTC. env OVN_NOTIFY_SRC / OVN_VSC_SRC = (mutated) copies used by the .sh wrapper's mutation checks."""
import calendar, importlib.util, json, os, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tmp_track
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.environ.get("OVN_NOTIFY_SRC") or os.path.join(ROOT, "scripts", "ovn_notify.py")
VSRC = os.environ.get("OVN_VSC_SRC") or os.path.join(ROOT, "vercel_state_check.py")
os.environ["TZ"] = "UTC"; time.tzset()
T = tempfile.mkdtemp()
Q = os.path.join(T, "q"); ST = os.path.join(Q, "state"); os.makedirs(ST)
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_y6", OVN_NOTIFY_UPSTREAM="http://127.0.0.1:9", OVN_LLM_HEALTH_URL="http://127.0.0.1:9/x", OVN_SUPPLY_LINE="0", OVN_IDLE_LINE="0")
for k in ("OVN_NOTIFY_DISABLE", "OVN_NOTIFY_DAILY_CAP", "OVN_ESC_MAC_SUPERVISOR", "OVN_ESC_TEST", "OVN_BULLET_ONCE", "OVN_BULLET_REPEAT_H", "OVN_DIGEST_DEDUPE", "OVN_DIGEST_QUIET", "OVN_SCORECARD_EVERY_H"):
    os.environ.pop(k, None)
spec = importlib.util.spec_from_file_location("ovn_notify_y6", SRC)
N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)

ok_n = bad_n = 0
def ok(label, cond):
    global ok_n, bad_n
    if cond: ok_n += 1; print("  ok   " + label)
    else: bad_n += 1; print("  FAIL " + label)

BASE = calendar.timegm((2026, 11, 4, 9, 20, 0))
CLOCK = [BASE]
N.now = lambda: CLOCK[0]
N.http_ok = lambda *a, **k: True
POSTS = []
class _Resp:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *a): return False
N.urllib.request.urlopen = lambda req, timeout=0: (POSTS.append({"title": req.get_header("Title"), "prio": req.get_header("Priority"), "body": (req.data or b"").decode()}), _Resp())[1]
N.shutil.disk_usage = lambda p: __import__("collections").namedtuple("du", "total used free")(100, 40, 60)
N.boot_notes = lambda at=None: []
N.autodeploy_report = lambda t: (None, None)
N.slo_lines = lambda t: []
N.duty_line = lambda t: None
N.forecast_lines = lambda t: []
N.supply_report = lambda t, d=None: None
N.queue_depths = lambda: {"iptv_apps": 20, "xlite": 20}

def reset():
    for f in os.listdir(ST):
        os.remove(os.path.join(ST, f))
    CLOCK[0] = BASE; del POSTS[:]
    for k in ("OVN_BULLET_ONCE", "OVN_BULLET_REPEAT_H", "OVN_ESC_MAC_SUPERVISOR", "OVN_SCORECARD_EVERY_H"): os.environ.pop(k, None)
def digest():
    """send one hourly digest (forced); -> (result, body of the posted digest or '')"""
    n = len(POSTS); r = N.do_update(force=True)
    return r, (POSTS[-1]["body"] if len(POSTS) > n else "")
def jl(name):
    try: return [json.loads(x) for x in open(os.path.join(ST, name))]
    except OSError: return []
def pending():
    try: return json.load(open(os.path.join(ST, "notify_promote.json")))
    except (OSError, ValueError): return []
def shadow():
    try: return open(os.path.join(ST, "notify_shadow.log")).read()
    except OSError: return ""

PROMOTE_BODY = "Daily prod promote Wed 09:00\nPromoted: billwatch iptv_apps shrike-labs-website\nNo change: gitlark\nUNVERIFIED (promoted without staging provenance): shrike-labs-website"

# ---------------------------------------------------------------- 1 promote folded, never dropped
reset()
ok("1: 'Daily prod promote' is no longer classified as a drop", N.classify("Daily prod promote") == "note")
act = N.handle_publish("t", {"title": "Daily prod promote", "priority": "default"}, PROMOTE_BODY)
ok("1: handle_publish folds it (not 'dropped'), and records no drop event", act == "folded:promote" and not [e for e in jl("notify_events.jsonl") if e.get("action") == "dropped"])
ok("1: pending promote stored", len(pending()) == 1)
title, body, n = N.compose_update(at=CLOCK[0])
ok("1: the digest carries ONE promote bullet with the repos and the UNVERIFIED list", body.count("Daily prod promote") == 1 and "Promoted: billwatch iptv_apps shrike-labs-website" in body
   and "UNVERIFIED (promoted without staging provenance): shrike-labs-website" in body and n == 1 and "1 to look at" in title)
ok("1: the 'No change' line and the dated header are not in the bullet", "No change" not in body and "Wed 09:00" not in body)
ok("1: a dry compose does not consume it", len(pending()) == 1)
real_fwd = N.forward
N.forward = lambda *a, **k: "capped"
r, _ = digest()
ok("1: a CAPPED digest keeps the promote summary (never dropped)", len(pending()) == 1)
N.forward = lambda *a, **k: "deduped"
digest()
ok("1: a DEDUPED digest keeps it too", len(pending()) == 1)
N.forward = real_fwd
r, b = digest()
ok("1: the sent digest contains the bullet", "Daily prod promote — Promoted:" in b and "UNVERIFIED" in b)
ok("1: ... and a real send consumes it (next digest does not repeat it)", pending() == [])
CLOCK[0] += 3600
ok("1: next digest has no promote bullet", "Daily prod promote" not in N.compose_update(at=CLOCK[0])[1])
# an all-good hour + a pending promote is NOT swallowed by the quiet-digest skip
reset(); N.handle_publish("t", {"title": "Daily prod promote"}, PROMOTE_BODY)
N.heartbeat_alive = lambda t=None: True
r, b = digest()
ok("1: the quiet 'all good' skip never swallows a pending promote", "Daily prod promote" in b)
# 4+ other high bullets: the promote bullet is still one of the 3 shown
reset(); N.handle_publish("t", {"title": "Daily prod promote"}, PROMOTE_BODY)
for i in range(5): N.add_note("Problem %d" % i, "something %d broke" % i, "high")
b = N.compose_update(at=CLOCK[0])[1]
ok("1: with many other bullets the promote summary stays among the shown ones", "Daily prod promote — " in b)
# even three boot/silent lines ahead of it cannot push it into the '+N more' tail
reset(); N.handle_publish("t", {"title": "Daily prod promote"}, PROMOTE_BODY)
N.boot_notes = lambda at=None: [{"title": "Boot %d" % i, "text": "rebooted", "prio": "high"} for i in range(3)]
b = N.compose_update(at=CLOCK[0])[1]
N.boot_notes = lambda at=None: []
ok("1: three boot lines ahead of it cannot push the promote bullet out of the shown ones", "Daily prod promote — " in b and b.count("• ") == 3)
# blocked / held -> priority high (warn)
reset(); N.handle_publish("t", {"title": "Daily prod promote"}, "Daily prod promote Wed 09:00\nPromoted: a\n⚠ BLOCKED (gate/conflict — stayed on last-good): billwatch")
ok("1: a BLOCKED line is carried", "BLOCKED" in N.compose_update(at=CLOCK[0])[1])

# scorecard: one weekly line
reset()
act = N.handle_publish("t", {"title": "Research-batch scorecard: 292 batch(es) graded D/F", "priority": "default"}, "long body")
ok("1: scorecard is folded (not dropped, not a bullet)", act == "folded:scorecard")
title, body, n = N.compose_update(at=CLOCK[0])
ok("1: ONE weekly scorecard line in the digest, not a 'to look at' bullet", body.count("Research batches (weekly): 292 batch(es) graded D/F") == 1 and n == 0)
digest()
CLOCK[0] += 24 * 3600
N.handle_publish("t", {"title": "Research-batch scorecard: 300 batch(es) graded D/F"}, "x")
ok("1: a day later (new scorecard) it is NOT shown again", "Research batches" not in N.compose_update(at=CLOCK[0])[1])
CLOCK[0] += 7 * 24 * 3600
N.handle_publish("t", {"title": "Research-batch scorecard: 310 batch(es) graded D/F"}, "x")
ok("1: after a week it shows the latest scorecard", "Research batches (weekly): 310" in N.compose_update(at=CLOCK[0])[1])

# ---------------------------------------------------------------- 2 mac supervisor default on
reset()
ok("2: OVN_ESC_MAC_SUPERVISOR defaults to ON in code", N._mode("OVN_ESC_MAC_SUPERVISOR") == "on")
for v in ("off", "shadow"):
    os.environ["OVN_ESC_MAC_SUPERVISOR"] = v
    ok("2: kill switch %s honoured" % v, N._mode("OVN_ESC_MAC_SUPERVISOR") == v)
os.environ.pop("OVN_ESC_MAC_SUPERVISOR")
json.dump({"ts": CLOCK[0] - 50 * 3600}, open(os.path.join(ST, "mac_jobs_health.json"), "w"))
os.utime(os.path.join(ST, "mac_jobs_health.json"), (CLOCK[0], CLOCK[0]))
out = N.do_check()
mac = lambda: [x for x in POSTS if x["title"] == "Mac jobs supervisor silent"]
ok("2: a 50h-silent Mac supervisor pushes ONE urgent emergency with no env", len(mac()) == 1 and mac()[0]["prio"] == "urgent")
N.do_check(); CLOCK[0] += 3600; N.do_check()
ok("2: ... once per day", len(mac()) == 1)

# ---------------------------------------------------------------- 3 rolling escalation
reset()
os.environ["OVN_ESC_TEST"] = "on"
CLOCK[0] = calendar.timegm((2026, 11, 4, 22, 0, 0))
r1 = N.escalate("hy:x", "STUCK x", "b", "OVN_ESC_TEST", rolling_h=24)
CLOCK[0] = calendar.timegm((2026, 11, 5, 0, 5, 0))     # past midnight: the calendar-day key would re-arm here
r2 = N.escalate("hy:x", "STUCK x", "b", "OVN_ESC_TEST", rolling_h=24)
ok("3: rolling 24h: a second push after the midnight roll is suppressed", r1 == "sent" and r2 == "already-recent" and len(POSTS) == 1)
CLOCK[0] = calendar.timegm((2026, 11, 5, 22, 1, 0))
r3 = N.escalate("hy:x", "STUCK x", "b", "OVN_ESC_TEST", rolling_h=24)
ok("3: ... and goes out again after 24h", r3 == "sent" and len(POSTS) == 2)
r4 = N.escalate("hy:y", "STUCK y", "b", "OVN_ESC_TEST", rolling_h=24)
ok("3: another repo has its own key", r4 == "sent")
reset(); os.environ["OVN_ESC_TEST"] = "on"
CLOCK[0] = calendar.timegm((2026, 11, 4, 22, 0, 0)); N.escalate("d:x", "T", "b", "OVN_ESC_TEST")
CLOCK[0] = calendar.timegm((2026, 11, 5, 0, 5, 0))
ok("3: without --rolling-h the old per-calendar-day key is unchanged", N.escalate("d:x", "T2", "b", "OVN_ESC_TEST") == "sent")
reset(); os.environ["OVN_ESC_TEST"] = "on"; real_fwd = N.forward; N.forward = lambda *a, **k: "failed"
N.escalate("hy:z", "T", "b", "OVN_ESC_TEST", rolling_h=24); N.forward = real_fwd
ok("3: a failed push does not consume the rolling window", N.escalate("hy:z", "T", "b", "OVN_ESC_TEST", rolling_h=24) == "sent")
os.environ.pop("OVN_ESC_TEST")

# ---------------------------------------------------------------- 4 reconcile bullet: repo + branch, 6 h cooldown
RB = "Branches diverged with CONFLICTING edits (auto-reconcile couldn't resolve, needs a human): develop→overnight/feature:billwatch main→develop:iptv_apps. Resolve the merge manually."
reset()
N.add_note("🔴 Branch reconcile CONFLICT", RB, "high")
b = N.compose_update(at=CLOCK[0])[1]
ok("4: the bullet names the repo AND the branch (not truncated)", "billwatch develop→overnight/feature" in b and "iptv_apps main→develop" in b and "…" not in b.split("\n")[0] and "iptv_apps." not in b)
ok("4: annotated conflict tokens keep their repo", N.reconcile_text("x develop→claude/feature(progress-deferred 6h+):xlite main→develop(sanity):gitlark") == "xlite develop→claude/feature(progress-deferred 6h+); gitlark main→develop(sanity)")
r, sent = digest()
ok("4: sent once", "billwatch develop→overnight/feature" in sent)
CLOCK[0] += 3600; N.add_note("🔴 Branch reconcile CONFLICT", RB, "high")
ok("4: the same conflict set within 6h is not shown again (cooldown)", "reconcile CONFLICT" not in N.compose_update(at=CLOCK[0])[1])
RB2 = RB.replace("iptv_apps", "gitlark"); CLOCK[0] += 5
N.add_note("🔴 Branch reconcile CONFLICT", RB2, "high")
ok("4: a CHANGED conflict set shows at once", "gitlark main→develop" in N.compose_update(at=CLOCK[0])[1])
reset(); N.add_note("🔴 Branch reconcile CONFLICT", RB, "high"); digest()
CLOCK[0] += 6 * 3600 + 60; N.add_note("🔴 Branch reconcile CONFLICT", RB, "high")
ok("4: after 6h it is shown again", "billwatch develop→overnight/feature" in N.compose_update(at=CLOCK[0])[1])

# ---------------------------------------------------------------- 7 repeated bullets: only on a state change or every 6 h
reset()
N.add_note("Features ready to test: 2", "All sub-items landed on the feature branch for: iptv-a (1); iptv-b (2)", "default"); digest()
CLOCK[0] += 3600; N.add_note("Features ready to test: 3", "All sub-items landed on the feature branch for: xlite-c (3); xlite-d (4); xlite-e (5)", "default")
ok("7: 'Features ready to test' with a DIFFERENT feature list an hour later shows immediately (key = title + body names)", "Features ready to test: 3" in N.compose_update(at=CLOCK[0])[1] and "xlite-c" in N.compose_update(at=CLOCK[0])[1])
digest()
CLOCK[0] += 3600; N.add_note("Features ready to test: 4", "All sub-items landed on the feature branch for: xlite-e (5); xlite-d (4); xlite-c (3)", "default")
ok("7: the SAME feature set (other order / count text) is still suppressed within 6h", "Features ready" not in N.compose_update(at=CLOCK[0])[1])
CLOCK[0] += 6 * 3600; N.add_note("Features ready to test: 1", "All sub-items landed on the feature branch for: xlite-c (3)", "default")
ok("7: ... and a changed set shows again after 6h", "Features ready to test: 1" in N.compose_update(at=CLOCK[0])[1])
reset()
N.add_note("Batch health: paused 1 straggler item(s)", "Batch(es) graded F: x", "default"); digest()
CLOCK[0] += 3600; N.add_note("Batch health: paused 1 straggler item(s)", "Batch(es) graded F: x", "default")
ok("7: an identical 'Batch health' bullet is suppressed", "Batch health" not in N.compose_update(at=CLOCK[0])[1])
N.add_note("Batch health: paused 4 straggler item(s)", "Batch(es) graded F: x, y, z", "default")
ok("7: a changed 'Batch health' state shows", "Batch health: paused 4" in N.compose_update(at=CLOCK[0])[1])
reset(); os.environ["OVN_BULLET_ONCE"] = "off"
N.add_note("Batch health: paused 1 straggler item(s)", "same", "default"); digest()
CLOCK[0] += 3600; N.add_note("Batch health: paused 1 straggler item(s)", "same", "default")
ok("7: OVN_BULLET_ONCE=off kill switch: repeats as before", "Batch health" in N.compose_update(at=CLOCK[0])[1])
os.environ["OVN_BULLET_ONCE"] = "shadow"
ok("7: shadow: still shown + a 'would drop' line", "Batch health" in N.compose_update(at=CLOCK[0])[1] and "would drop the unchanged 'Batch health" in shadow())
os.environ.pop("OVN_BULLET_ONCE")
reset()
N.add_note("Batch health: paused 1 straggler item(s)", "same", "default")
N.forward = lambda *a, **k: "capped"; digest(); N.forward = real_fwd
CLOCK[0] += 1800; N.add_note("Batch health: paused 1 straggler item(s)", "same", "default")
ok("7: a digest that was NOT delivered does not start the cooldown", "Batch health" in N.compose_update(at=CLOCK[0])[1])
reset()
N.add_note("Batch health: paused 1 straggler item(s)", "same", "default"); N.compose_update(at=CLOCK[0])
ok("7: composing alone (dry run) writes no cooldown state", not os.path.exists(os.path.join(ST, "notify_bullet_state.json")))

# reconcile bullet: a different repo/branch set an hour later is not swallowed
reset()
N.add_note("Branch reconcile CONFLICT", "reconcile conflict: develop->overnight/feature:billwatch", "high"); digest()
CLOCK[0] += 3600; N.add_note("Branch reconcile CONFLICT", "reconcile conflict: develop->overnight/feature:gitlark", "high")
ok("7: a reconcile conflict on ANOTHER repo an hour later shows", "gitlark" in N.compose_update(at=CLOCK[0])[1])

# ---------------------------------------------------------------- 1b weekly scorecard forces a digest when the digest would be all-good
reset()
os.environ.pop("OVN_DIGEST_QUIET", None)
_hb_prev = N.heartbeat_alive; N.heartbeat_alive = lambda t=None: True
n0 = len(POSTS); N.handle_publish("t", {"title": "Research-batch scorecard: 12 batch(es) graded A"}, "x")
res = N.do_update()
ok("1b: a due weekly scorecard sends the digest even when nothing else is to look at", len(POSTS) == n0 + 1 and "Research batches (weekly): 12 batch(es) graded A" in POSTS[-1]["body"] and "all good" in res)
ok("1b: ... and the scorecard is stamped as shown", os.path.exists(os.path.join(ST, "notify_scorecard_shown.json")))
CLOCK[0] += 3600; n1 = len(POSTS); res = N.do_update()
ok("1b: the next all-good hour is quiet again (skipped)", len(POSTS) == n1 and res.startswith("skipped"))
N.heartbeat_alive = _hb_prev

# ---------------------------------------------------------------- 6 suite red: fixtures are not a signal
reset()
N.add_note("Suite red x4: test_fail.sh, test_does_not_exist.sh, test_fake_a.sh", "the queue test suite has failed the same way 4 runs in a row (sig 2951efb1805b): test_fail.sh: x; test_fake_a.sh: y", "high")
ok("6: a 'Suite red' naming ONLY fixtures writes no note", jl("notify_notes.jsonl") == [])
N.add_note("Suite red x3: scripts/test/test_fail.sh, test_real_thing.sh, test_fake_a.sh", "the queue test suite has failed the same way 3 runs in a row (sig abc): test_fail.sh: x; test_real_thing.sh: boom", "high")
rows = jl("notify_notes.jsonl")
ok("6: a mixed one keeps only the real test in the title", len(rows) == 1 and "test_real_thing.sh" in rows[0]["title"] and "test_fail.sh" not in rows[0]["title"] and "test_fake_a" not in rows[0]["title"])
N.add_note("Suite red x2: test_a.sh", "x", "high"); N.add_note("Features ready to test: 1", "x", "default")
ok("6: other titles pass through", len(jl("notify_notes.jsonl")) == 3)
os.environ["OVN_ESC_TEST"] = "on"; del POSTS[:]
ok("6: escalate of a fixtures-only suite red is 'fixtures-only' and pushes nothing", N.escalate("suite_red:x", "Suite red x4: test_fail.sh, test_fake_a.sh", "b", "OVN_ESC_TEST") == "fixtures-only" and not POSTS)
r = N.escalate("suite_red:y", "Suite red x4: test_fail.sh, test_real.sh", "the queue test suite has failed (sig y): test_fail.sh: x; test_real.sh: z", "OVN_ESC_TEST")
ok("6: a real name still escalates, without the fixture in the push", r == "sent" and "test_real.sh" in POSTS[-1]["title"] and "test_fail.sh" not in POSTS[-1]["title"] + POSTS[-1]["body"])
os.environ.pop("OVN_ESC_TEST")

# ---------------------------------------------------------------- 5 vercel prod ERROR -> READY recovery
vs = importlib.util.spec_from_file_location("vsc_y6", VSRC); M = importlib.util.module_from_spec(vs); vs.loader.exec_module(M)
M.PROJECTS, M.STATE = ["p"], os.path.join(T, "vstate.json")
M.token = lambda: "tok"
M._mac_hb = lambda name: None
pushed = []
M.push = lambda title, body, urgent, dry: pushed.append((title, urgent, body))
def vrun(rows, state=None):
    del pushed[:]
    if state is not None: open(M.STATE, "w").write(json.dumps(state))
    deps = [dict(uid=u, createdAt=int(time.time() * 1000 - age * 1000), target=t, readyState=s, errorMessage="boom", meta={}) for u, t, s, age in rows]
    M.api = lambda tok, path: {"projects": [{"name": "p", "id": "p1"}]} if "/v9/projects" in path else {"deployments": deps}
    M.main()
    return json.load(open(M.STATE))
open(M.STATE, "w").write("{}")
st = vrun([("e1", "production", "ERROR", 3600)])
ok("5: prod ERROR -> urgent alert (baseline)", len(pushed) == 1 and pushed[0][1] is True)
st = vrun([("e1", "production", "ERROR", 7200), ("r1", "production", "READY", 60)])
ok("5: ERROR -> READY: ONE recovery line, low priority, names the project", len(pushed) == 1 and pushed[0][0] == "Vercel PRODUCTION p recovered: READY" and pushed[0][1] == "low")
ok("5: ... the alert state is forgotten", "prod_p" not in st and "esc_p" not in st)
st = vrun([("e1", "production", "ERROR", 7200), ("r1", "production", "READY", 60)])
ok("5: ... and it is sent ONCE (next poll silent)", pushed == [])
st = vrun([("r1", "production", "READY", 60)], state={})
ok("5: a healthy project that never alerted gets no recovery line", pushed == [])
st = vrun([("e2", "production", "ERROR", 60)], state={"prod_p": "e2"})
ok("5: still ERROR (same alerted deployment) is not a recovery", all("recovered" not in p[0] for p in pushed))
st = vrun([("r2", "production", "READY", 60)], state={"esc_p": time.time() - 100})
ok("5: an escalated-only project (esc marker) recovers too", len(pushed) == 1 and "recovered" in pushed[0][0])
st = vrun([("r3", "production", "READY", 60)], state={"prod_p": "e9"})
M.push = lambda title, body, urgent, dry: False
st = vrun([("r3", "production", "READY", 60)], state={"prod_p": "e9"})
ok("5: a recovery line no channel took keeps the state (retried next poll)", st.get("prod_p") == "e9")

print("%d passed, %d failed" % (ok_n, bad_n))
sys.exit(1 if bad_n else 0)
