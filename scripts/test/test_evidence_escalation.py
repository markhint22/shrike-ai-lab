#!/usr/bin/env python3
"""K1 (2026-11-01): qa/evidence_freshness_check.py escalates to EMERGENCY (alerts.log line + relay push) when the staging deploy export is stale > 6 h or the daily promote was
HELD for EVIDENCE_STALE across more than a day; the deploy_export hint names the 'copy to box fails' cause. Time injected, push injected (nothing touches a network). Mutants must fail."""
import importlib.util, json, os, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
QA = os.path.abspath(os.path.join(HERE, "..", "..", "qa"))
SRC = os.path.join(QA, "evidence_freshness_check.py")
if not os.path.isfile(SRC):
    print("  SKIP: qa/evidence_freshness_check.py not installed here")
    sys.exit(0)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1; print("  ok   " + name)
    else:
        F += 1; print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="evesc-test-"))
for k in ("OVN_QA_STAGING_E2E", "QA_STAGING_MAX_AGE_S", "OVN_EVIDENCE_FRESHNESS", "QA_STATE_DIR", "OVN_DIR", "OVN_EVIDENCE_ESCALATE", "OVN_EVIDENCE_ESCALATE_S"):
    os.environ.pop(k, None)
os.environ["OVN_QA_STAGING_E2E"] = "off"  # e2e sources are not the subject here


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


FM = load(SRC, "esc_under_test")
NOW = 1_800_000_000.0
H = 3600.0


def stamp(t):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))


def mk(name, export_age, holds=()):
    d = os.path.join(T, name); shutil.rmtree(d, ignore_errors=True); os.makedirs(os.path.join(d, "staging_deploys"))
    for repo in ("billwatch", "iptv_apps"):
        json.dump({"repo": repo, "fetched_at": NOW - export_age}, open(os.path.join(d, "staging_deploys", repo + ".json"), "w"))
    with open(os.path.join(d, "alerts.log"), "w") as f:
        for t, repo in holds:
            f.write("[%s] WARN | promote-staging-gate | %s promote SKIPPED: staging_check EVIDENCE_STALE for candidate abc1234567 (enforce); other repos unaffected\n" % (stamp(t), repo))
    return d


def lines(d):
    return [l for l in open(os.path.join(d, "alerts.log")).read().splitlines() if "evidence-freshness" in l]


def scenario(mod, label):
    bad = []
    pushed = []
    push = lambda title, msg: pushed.append((title, msg))
    # export 7 h old => EMERGENCY line + push; hint names the copy-to-box cause
    d = mk("exp7_" + label, 7 * H)
    os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if not any("EMERGENCY | evidence-freshness" in l and "7.0 h old" in l for l in L):
        bad.append("export 7 h old must write an EMERGENCY evidence-freshness line, got %s" % L)
    if len(pushed) != 1:
        bad.append("export 7 h old must push exactly one emergency, pushed %d" % len(pushed))
    if not any("export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale" in l for l in L):
        bad.append("hint must read 'export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale'")
    # export 2 h old => stale-by-30-min WARN only, no emergency, no push
    pushed.clear()
    d = mk("exp2_" + label, 2 * H); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if any("EMERGENCY" in l for l in L) or pushed or not any("WARN | evidence-freshness" in l for l in L):
        bad.append("export 2 h old: WARN only, got %s pushed=%d" % (L, len(pushed)))
    # promote held twice a day apart (26 h) while the export is 1 h old => promote_held_stale EMERGENCY
    pushed.clear()
    d = mk("held_" + label, 1 * H, holds=[(NOW - 28 * H, "billwatch"), (NOW - 2 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    L = lines(d)
    if not any("EMERGENCY" in l and "HELD for EVIDENCE_STALE" in l for l in L) or len(pushed) != 1:
        bad.append("promote held > 1 day must EMERGENCY + push, got %s pushed=%d" % (L, len(pushed)))
    # a single hold 2 h ago (first day) => no escalation
    pushed.clear()
    d = mk("held1_" + label, 1 * H, holds=[(NOW - 2 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    mod.run(d, NOW, push=push)
    if any("EMERGENCY" in l for l in lines(d)) or pushed:
        bad.append("one hold (< 1 day) must not escalate")
    # old holds long recovered (last one 3 days ago) => no escalation
    d = mk("heldold_" + label, 1 * H, holds=[(NOW - 100 * H, "billwatch"), (NOW - 76 * H, "billwatch")]); os.environ["QA_STATE_DIR"] = d
    pushed.clear(); mod.run(d, NOW, push=push)
    if any("EMERGENCY" in l for l in lines(d)) or pushed:
        bad.append("holds that ended 3 days ago must not escalate")
    # dedupe: a second run within 6 h does not push again; at 6 h it does
    d = mk("dd_" + label, 7 * H); os.environ["QA_STATE_DIR"] = d
    pushed.clear(); mod.run(d, NOW, push=push); mod.run(d, NOW + 1 * H, push=push)
    if len(pushed) != 1:
        bad.append("escalation deduped inside 6 h, pushed %d" % len(pushed))
    return bad


bad = scenario(FM, "orig")
ok("scenario passes on the real module", not bad, bad)
os.environ["OVN_EVIDENCE_ESCALATE"] = "shadow"
d = mk("shadow", 7 * H); os.environ["QA_STATE_DIR"] = d
pushed = []; FM.run(d, NOW, push=lambda t, m: pushed.append(t))
ok("OVN_EVIDENCE_ESCALATE=shadow: EMERGENCY line written, NO push", any("EMERGENCY" in l for l in lines(d)) and not pushed)
os.environ["OVN_EVIDENCE_ESCALATE"] = "off"
d = mk("off", 7 * H); os.environ["QA_STATE_DIR"] = d
pushed = []; FM.run(d, NOW, push=lambda t, m: pushed.append(t))
ok("OVN_EVIDENCE_ESCALATE=off: old WARN behaviour, no EMERGENCY, no push", not any("EMERGENCY" in l for l in lines(d)) and not pushed)
os.environ.pop("OVN_EVIDENCE_ESCALATE")
# 2026-11-02 (N4): the old line here, FM.push_emergency("t", "m") unmocked, defaulted to the LIVE relay (127.0.0.1:8099) and paged Mark's phone with a real urgent 't' / 'm' on every
# suite run. push_emergency now has NO live default: unset NTFY_SERVER = no push. Everything below talks to a local stub or to nothing.
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

_posts = []


class _Stub(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        _posts.append({"path": self.path, "title": self.headers.get("Title"), "lvl": self.headers.get("X-Ovn-Level"), "body": self.rfile.read(n).decode()})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")


_srv = HTTPServer(("127.0.0.1", 0), _Stub); threading.Thread(target=_srv.serve_forever, daemon=True).start()


def push_scenario(mod):
    """-> list of broken expectations for mod.push_emergency (unset => no push; stub relay => one emergency POST; OVN_NOTIFY_DISABLE => no push)."""
    bad = []
    saved = {k: os.environ.get(k) for k in ("NTFY_SERVER", "OVN_NOTIFY_DISABLE")}
    try:
        del _posts[:]
        os.environ.pop("NTFY_SERVER", None); os.environ.pop("OVN_NOTIFY_DISABLE", None)
        os.environ["NTFY_SERVER"] = ""    # explicitly empty, like an unset variable in cron-less shells
        if mod.push_emergency("t", "m") is not False:
            bad.append("unset/empty NTFY_SERVER must not push (returned non-False)")
        os.environ["NTFY_SERVER"] = "http://127.0.0.1:%d" % _srv.server_port
        if mod.push_emergency("t", "m") is not True or len(_posts) != 1 or _posts[0]["lvl"] != "emergency" or _posts[0]["title"] != "t":
            bad.append("with a stub relay exactly one emergency POST expected: %r" % _posts)
        os.environ["OVN_NOTIFY_DISABLE"] = "1"
        n0 = len(_posts)
        if mod.push_emergency("t", "m") is not False or len(_posts) != n0:
            bad.append("OVN_NOTIFY_DISABLE=1 must not push")
    finally:
        for k, v in saved.items():
            if v is None: os.environ.pop(k, None)
            else: os.environ[k] = v
    return bad


_pbad = push_scenario(FM)
ok("push_emergency: unset NTFY_SERVER = no push, stub relay = one emergency POST, OVN_NOTIFY_DISABLE = none", not _pbad, _pbad)

print("# mutation checks")
src = open(SRC).read()
muts = {
    "6h threshold disabled": ("if ages and min(ages) > lim:", "if ages and min(ages) > lim * 1000:"),
    "hint without the copy-to-box cause": ("If the export runs but copy to box fails: check ssh to $OVN_SSH and Tailscale", "see logs"),
    "held > 1 day never escalates": ("if holds[-1] - first > HELD_ESCALATE_S:", "if False:"),
    "emergency written as WARN": ('lvl = "EMERGENCY" if key in esc else "WARN"', 'lvl = "WARN"'),
    "no push": ('if key in esc and esc_mode == "on":', "if False:"),
}
for label, (a, b) in muts.items():
    if a not in src:
        ok("mutant [%s] applies" % label, False); continue
    mp = os.path.join(T, "mut_%d.py" % abs(hash(label))); open(mp, "w").write(src.replace(a, b))
    try:
        mm = load(mp, "mut_%d" % abs(hash(label)))
        bm = scenario(mm, "m%d" % abs(hash(label)))
    except Exception as ex:  # noqa: BLE001
        bm = ["crash %s" % ex]
    ok("mutant [%s]: scenario FAILS (%d broken)" % (label, len(bm)), len(bm) > 0)
_PUSH_MUT = {
    "push_emergency falls back to the live relay": ('base = (os.environ.get("NTFY_SERVER") or "").rstrip("/")', 'base = (os.environ.get("NTFY_SERVER") or "http://127.0.0.1:%d" % _srv.server_port).rstrip("/")'),
    "push_emergency ignores OVN_NOTIFY_DISABLE": ('if not base or os.environ.get("OVN_NOTIFY_DISABLE"):', "if not base:"),
}
for label, (a, b) in _PUSH_MUT.items():
    if a not in src:
        ok("mutant [%s] applies" % label, False); continue
    mp = os.path.join(T, "pmut_%d.py" % abs(hash(label))); open(mp, "w").write(src.replace(a, b))
    try:
        mm = load(mp, "pmut_%d" % abs(hash(label)))
        mm._srv = _srv
        os.environ["NTFY_SERVER"] = ""
        bm = push_scenario(mm)
    except Exception as ex:  # noqa: BLE001
        bm = ["crash %s" % ex]
    ok("mutant [%s]: push scenario FAILS (%d broken)" % (label, len(bm)), len(bm) > 0)
shutil.rmtree(T, ignore_errors=True)
print("evidence escalation: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
