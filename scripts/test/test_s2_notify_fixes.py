"""S2 notify fixes (2026-11-03): vercel_state_check (stable prod escalation title, rolling 24h, age from createdAt, recovered-branch / commit-author noise) and ovn_notify
(OVN_ESC_HYGIENE default on, dropped-message detail + heartbeat class breakdown, Mac supervisor staleness escalation). Hermetic: fake clock, fake push, temp state, TZ=UTC, nothing
posts anywhere. Each fix is mutation-proofed: a mutated temp copy of the source must make the same checks FAIL (run via `python3 test_s2_notify_fixes.py`)."""
import importlib.util, json, os, shutil, sys, tempfile, threading, time, types
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()
from http.server import BaseHTTPRequestHandler, HTTPServer

os.environ.update(TZ="UTC", NTFY_SERVER="http://127.0.0.1:9", OVN_NOTIFY_DISABLE="")
os.environ.pop("OVN_NOTIFY_DISABLE", None)
time.tzset()
HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
VSRC = os.path.join(OQ, "vercel_state_check.py")
NSRC = os.path.join(OQ, "scripts", "ovn_notify.py")
SCR = os.path.abspath(os.path.join(OQ, "..", "..", "scripts")) if os.path.isdir(os.path.join(OQ, "..", "..", "scripts")) else ""
T = tempfile.mkdtemp()
posts = []


class Fake(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        posts.append({"title": self.headers.get("Title"), "prio": self.headers.get("Priority"), "body": self.rfile.read(n).decode()})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")


srv = HTTPServer(("127.0.0.1", 0), Fake); threading.Thread(target=srv.serve_forever, daemon=True).start()
os.environ["OVN_NOTIFY_UPSTREAM"] = "http://127.0.0.1:%d" % srv.server_port
os.environ["OVN_MAC_STATE"] = os.path.join(T, "macstate")
D1 = 86400.0
CLK = [1762117200.0]    # 2025-11-02 21:00:00 UTC
FAILS = []


def make_checker(sink):
    def ok(label, cond):
        print(("  ok   " if cond else "  FAIL ") + label)
        if not cond:
            sink.append(label)
    return ok


# ------------------------------------------------------------------ vercel_state_check
def load_vsc(src):
    d = tempfile.mkdtemp(dir=T); os.makedirs(os.path.join(d, "overnight-queue"))
    dst = os.path.join(d, "overnight-queue", "vercel_state_check.py"); shutil.copy(src, dst)
    spec = importlib.util.spec_from_file_location("vsc_%d" % abs(hash(d)), dst); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    m.time = types.SimpleNamespace(time=lambda: CLK[0], strftime=time.strftime, gmtime=time.gmtime, localtime=time.localtime)
    m.PROJECTS, m.STATE, m.token, m.RETRY = ["p"], os.path.join(d, "state.json"), (lambda: "tok"), False
    return m


def vsc_checks(m, ok):
    pushed = []
    m.push = lambda title, body, urgent, dry: pushed.append((title, body, urgent)) or True
    def dep(uid, state, age_s, target=None, branch="develop", msg="", code="build_failed"):
        return dict(uid=uid, url=uid + ".vercel.app", createdAt=int((CLK[0] - age_s) * 1000), target=target, readyState=state, errorMessage=msg, errorCode=code,
                    meta={"githubCommitRef": branch, "githubCommitSha": uid})
    def poll(rows):
        m.api = lambda tok, path: {"projects": [{"name": "p", "id": "p1"}]} if "/v9/projects" in path else {"deployments": rows}
        import contextlib, io
        with contextlib.redirect_stdout(io.StringIO()):
            m.main()
    # F1: prod newest ERROR for ~1d, last READY 13d ago
    prod = [dep("e1", "ERROR", D1, "production", "main", "vercel.ts schema validation failed"), dep("e0", "ERROR", 5 * D1, "production", "main"), dep("r0", "READY", 13 * D1, "production", "main")]
    open(m.STATE, "w").write("{}")
    for _ in range(3):
        poll(prod); CLK[0] += 1800
    first = [x for x in pushed if x[0] == "Vercel PRODUCTION p: ERROR"]
    esc = [x for x in pushed if "still ERROR" in x[0]]
    ok("F1: the per-deployment prod push names the last READY age (after a failed promote: 'last READY production deploy 13d ago')", len(first) == 1 and "last READY production deploy 13d ago" in first[0][1])
    ok("F1: 3rd poll -> one urgent escalation with a STABLE title (no poll count) and age from createdAt, not the poll counter",
       len(esc) == 1 and esc[0][0] == "Vercel PRODUCTION p still ERROR" and esc[0][2] and "ERROR for 25h" in esc[0][1] and "3 polls" in esc[0][1] and "13d ago" in esc[0][1])
    del pushed[:]
    for _ in range(4):
        poll(prod); CLK[0] += 1800        # now 2h later, past local midnight (UTC): 23:00 -> 01:00
    ok("F1: 2h later, across local midnight, no second urgent push (rolling 24h, not calendar day)", not [x for x in pushed if "still ERROR" in x[0]])
    CLK[0] += 23 * 3600
    poll(prod)
    esc2 = [x for x in pushed if "still ERROR" in x[0]]
    ok("F1: > 24h after the last escalation it fires again, with the SAME title (relay cooldown can match)", len(esc2) == 1 and esc2[0][0] == "Vercel PRODUCTION p still ERROR" and not any(c.isdigit() for c in esc2[0][0]))
    ok("F1: the escalation marker is an epoch timestamp (rolling window)", isinstance(json.load(open(m.STATE)).get("esc_p"), (int, float)))
    # F4: recovered branch / commit author noise
    open(m.STATE, "w").write("{}"); del pushed[:]
    poll([dep("x1", "ERROR", 7200, msg="Build failed: tsc exited 1"), dep("x2", "READY", 3600)])
    ok("F4: an ERROR preview superseded by a READY deployment of the same branch is NOT reported as failing", not [x for x in pushed if "previews failing" in x[0]])
    open(m.STATE, "w").write("{}"); del pushed[:]
    poll([dep("x1", "READY", 7200), dep("x2", "ERROR", 3600, msg="Build failed: tsc exited 1")])
    ok("F4: control: newest develop deployment ERROR -> ONE preview note", len([x for x in pushed if "previews failing" in x[0]]) == 1)
    open(m.STATE, "w").write("{}"); del pushed[:]
    poll([dep("g1", "BLOCKED", 3600, msg="The deployment was blocked because the commit author does not have permission to deploy", code="")])
    ok("F4: the gitlark 'commit author lacks permission' BLOCKED preview is known noise: no note", not [x for x in pushed if "previews failing" in x[0]])
    open(m.STATE, "w").write("{}"); del pushed[:]
    poll([dep("g2", "BLOCKED", 3600, msg="Blocked: unknown reason", code="")])
    ok("F4: control: another BLOCKED reason still notes", len([x for x in pushed if "previews failing" in x[0]]) == 1)


def mutate_file(src, old, new, name):
    s = open(src).read()
    if s.count(old) != 1:
        raise SystemExit("mutation anchor for %s found %d times: %r" % (name, s.count(old), old))
    p = os.path.join(T, "mut_" + name + "_" + os.path.basename(src)); open(p, "w").write(s.replace(old, new)); return p


def run_vsc(src, label):
    sink = []; CLK[0] = 1762117200.0
    vsc_checks(load_vsc(src), make_checker(sink) if label == "real" else (lambda l, c: (not c) and sink.append(l)))
    return sink


# ------------------------------------------------------------------ ovn_notify
def load_notify(src):
    st = tempfile.mkdtemp(dir=T); os.environ["OVN_NOTIFY_STATE"] = st; os.environ["NTFY_TOPIC"] = "t_s2"
    for k in ("OVN_ESC_HYGIENE", "OVN_ESC_PROMOTE_RED", "OVN_ESC_MAC_SUPERVISOR", "OVN_HB_DROP_CLASSES", "OVN_NOTIFY_DAILY_CAP", "OVN_DIGEST_DEDUPE"):
        os.environ.pop(k, None)
    spec = importlib.util.spec_from_file_location("notify_%d" % abs(hash(st)), src); N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)
    N.now = lambda: CLK[0]; N.DIGEST_CAP = 24; N.EMERGENCY_CAP = 20; N.DAILY_CAP_EXPLICIT = False; N.DAILY_CAP = 40
    return N, st


def notify_checks(N, st, ok):
    del posts[:]
    # F3
    r = N.escalate("hygiene_stuck:taa", "Branch hygiene STUCK 4h: taa", "gate red", "OVN_ESC_HYGIENE")
    ok("F3: OVN_ESC_HYGIENE defaults to ON: one emergency push", r == "sent" and len(posts) == 1 and posts[0]["prio"] == "urgent")
    r2 = N.escalate("hygiene_stuck:taa", "Branch hygiene STUCK 5h: taa", "gate red", "OVN_ESC_HYGIENE")
    ok("F3: ... once per day per repo", r2 == "already-today" and len(posts) == 1)
    os.environ["OVN_ESC_HYGIENE"] = "off"; ok("F3: env kill switch off still works", N.escalate("h:x", "t", "b", "OVN_ESC_HYGIENE") == "off")
    os.environ["OVN_ESC_HYGIENE"] = "shadow"; ok("F3: env shadow still works", N.escalate("h:y", "t", "b", "OVN_ESC_HYGIENE") == "shadow"); os.environ.pop("OVN_ESC_HYGIENE")
    ok("F3: OVN_ESC_PROMOTE_RED stays shadow by default (only hygiene was flipped)", N.escalate("p:x", "t", "b", "OVN_ESC_PROMOTE_RED") == "shadow")
    # F5
    del posts[:]
    body7 = "7 items need attention: " + "x" * 400
    N.handle_publish("t", {"title": "Overnight queue: 7 item(s) need attention", "priority": "default"}, body7)
    for i in range(51):
        N.handle_publish("t", {"title": "🎉 Feature complete: billwatch-2026-%d" % i, "priority": "default"}, "all landed")
    ev = [json.loads(l) for l in open(os.path.join(st, "notify_events.jsonl"))]
    na = [e for e in ev if "need attention" in e.get("key", "")]
    ok("F5: a dropped 'need attention' event keeps the first 200 chars of its body", len(na) == 1 and na[0].get("detail", "").startswith("7 items need attention: xxx") and len(na[0]["detail"]) == 200)
    N.handle_publish("t", {"title": "Overnight queue: 1 item(s) need attention", "priority": "default"}, "one")
    CLK[0] += 60
    t, b = N.heartbeat_text()
    ok("F5: heartbeat breaks '53 dropped' down by class", "53 dropped (51 feature-complete, 2 need-attention)" in b)
    os.environ["OVN_HB_DROP_CLASSES"] = "off"; t, b = N.heartbeat_text(); os.environ.pop("OVN_HB_DROP_CLASSES")
    ok("F5: OVN_HB_DROP_CLASSES=off restores the plain count", "53 dropped," in b and "(" not in b.split("last emergency")[0])
    # F6 box side
    mp = os.path.join(st, "mac_jobs_health.json")
    ok("F6: no box copy ever written (supervisor never deployed) -> no verdict", N.mac_supervisor_stale() is None)
    json.dump({"ts": CLK[0] - 3600}, open(mp, "w")); os.utime(mp, (CLK[0], CLK[0]))
    ok("F6: a 1h-old copy is fresh", N.mac_supervisor_stale() is None)
    json.dump({"ts": CLK[0] - 15 * 3600}, open(mp, "w")); os.utime(mp, (CLK[0], CLK[0]))
    v = N.mac_supervisor_stale()
    ok("F6: a copy whose ts is 15h old (fresh mtime: age comes from the JSON ts) -> stale verdict with a STABLE title", v is not None and v[0] == "Mac jobs supervisor silent" and "15h" in v[1])
    N.emergency_checks = lambda dry=False: []
    del posts[:]; out = N.do_check()
    sh = open(os.path.join(st, "notify_shadow.log")).read()
    ok("F6: do_check: default shadow = a 'would escalate' line only, no push", not posts and "OVN_ESC_MAC_SUPERVISOR | would escalate" in sh and "Mac jobs supervisor silent -> shadow" in out)
    os.environ["OVN_ESC_MAC_SUPERVISOR"] = "on"; N.do_check(); r2 = N.do_check()
    ok("F6: flag on -> ONE urgent push per day", len(posts) == 1 and posts[0]["title"] == "Mac jobs supervisor silent" and posts[0]["prio"] == "urgent" and "already-today" in r2)
    os.environ.pop("OVN_ESC_MAC_SUPERVISOR")


def run_notify(src, label):
    sink = []; CLK[0] = 1762117200.0
    N, st = load_notify(src)
    notify_checks(N, st, make_checker(sink) if label == "real" else (lambda l, c: (not c) and sink.append(l)))
    return sink


print("== real sources")

sink_real = []
CLK[0] = 1762117200.0; vsc_checks(load_vsc(VSRC), make_checker(sink_real))
CLK[0] = 1762117200.0; N0, st0 = load_notify(NSRC); notify_checks(N0, st0, make_checker(sink_real))
FAILS.extend(sink_real)

print("== mutants (each must make at least one check fail)")
V = [("stable-title-lost", '"Vercel PRODUCTION %s still ERROR" % name', '"Vercel PRODUCTION %s still ERROR (%d polls)" % (name, n_err)'),
     ("calendar-day", 'if now_s - last_esc >= ESCALATE_EVERY_S:', 'if time.strftime("%Y-%m-%d", time.gmtime(now_s)) != time.strftime("%Y-%m-%d", time.gmtime(last_esc)):'),
     ("age-from-polls", 'fmt_age(age_of(prod[0])), n_err', 'fmt_age(n_err * 1800), n_err'),
     ("recovered-branch", 'if k and k in newest and st(newest[k]) == "READY" and newest[k] is not d:', 'if False:'),
     ("author-noise", 'if NOISE_MSG_RE.search(d.get("errorMessage") or ""):', 'if False:'),
     ("no-last-ready", '"%s | %s" % ((prod[0].get("errorMessage") or "newest production deploy is not live")[:120], last_ready_text(prod, now_s))', '"%s" % (prod[0].get("errorMessage") or "newest production deploy is not live")[:120]')]
for name, old, new in V:
    try:
        failed = run_vsc(mutate_file(VSRC, old, new, name), "mut")
    except SystemExit as e:
        failed = None; print("  FAIL mutant %s: %s" % (name, e)); FAILS.append("mutant " + name)
    if failed is not None:
        print(("  ok   " if failed else "  FAIL ") + "vercel mutant %s is caught (%d check(s) failed)" % (name, len(failed)))
        if not failed: FAILS.append("mutant " + name)
Nm = [("hygiene-default-shadow", '"OVN_DIGEST_QUIET", "OVN_ESC_HYGIENE", "OVN_HB_DROP_CLASSES")', '"OVN_DIGEST_QUIET", "OVN_HB_DROP_CLASSES")'),
      ("no-event-detail", 'row["detail"] = re.sub', 'pass  # row["detail"] = re.sub'),
      ("no-class-breakdown", 'if dropped and _mode("OVN_HB_DROP_CLASSES") != "off":', 'if False:'),
      ("mac-sup-never-stale", 'if age < MAC_SUP_STALE_S:\n        return None', 'if True:\n        return None'),
      ("mac-sup-not-wired", 'if ms:        #', 'if False:        #')]
for name, old, new in Nm:
    try:
        failed = run_notify(mutate_file(NSRC, old, new, name), "mut")
    except SystemExit as e:
        failed = None; print("  FAIL mutant %s: %s" % (name, e)); FAILS.append("mutant " + name)
    if failed is not None:
        print(("  ok   " if failed else "  FAIL ") + "notify mutant %s is caught (%d check(s) failed)" % (name, len(failed)))
        if not failed: FAILS.append("mutant " + name)
shutil.rmtree(T, ignore_errors=True)
print("s2 notify fixes: %s (%d failing)" % ("FAIL" if FAILS else "all passed", len(FAILS)))
sys.exit(1 if FAILS else 0)
