"""ovn_notify.py box-deploy line (package L4, 2026-10-18): the hourly update shows the autodeploy verdict (state/autodeploy_report.json written by ops/box_autodeploy.sh) so a box that
runs old code, a stopped deploy job, a rolled-back deploy or an unverified rollback is visible WITHOUT a human reading logs. Text only: it never pushes by itself.
usage: test_notify_autodeploy.py   env: OVN_NOTIFY_SRC=<path to a (mutated) ovn_notify.py> (used by the .sh wrapper's mutants)"""
import calendar, importlib.util, json, os, sys, tempfile
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("OVN_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.environ.get("OVN_NOTIFY_SRC") or os.path.join(ROOT, "scripts", "ovn_notify.py")
T = tempfile.mkdtemp()
ST = os.path.join(T, "q", "state")
os.makedirs(ST)
os.environ["OVN_SUPPLY_LINE"] = "0"
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_test", OVN_NOTIFY_DAILY_CAP="50", OVN_NOTIFY_UPSTREAM="http://127.0.0.1:9", OVN_LLM_HEALTH_URL="http://127.0.0.1:9/x")
os.environ.pop("OVN_AUTODEPLOY_LINE", None)
spec = importlib.util.spec_from_file_location("ovn_notify_ad", SRC)
N = importlib.util.module_from_spec(spec)
spec.loader.exec_module(N)
BASE = calendar.timegm((2026, 10, 18, 12, 0, 0))
N.now = lambda: BASE
N.http_ok = lambda *a, **k: True
N.shutil.disk_usage = lambda p: __import__("collections").namedtuple("du", "total used free")(100, 40, 60)
ok_n = bad_n = 0


def ok(label, cond):
    global ok_n, bad_n
    if cond:
        ok_n += 1; print("  ok   " + label)
    else:
        bad_n += 1; print("  FAIL " + label)


def write(**kw):
    rep = {"ts": BASE - 600, "mode": "shadow", "branch": "claude/feature", "ahead": 3, "oldest_age_h": 2, "stale_threshold_h": 12, "decision": "would_deploy",
           "reasons": [], "line": "Box code [shadow]: @abc1234, 3 commit(s) behind claude/feature (oldest undeployed 2h) - drift: 0 modified - would deploy def5678 (suite PASS)"}
    rep.update(kw)
    json.dump(rep, open(os.path.join(ST, "autodeploy_report.json"), "w"))


def clear():
    try:
        os.remove(os.path.join(ST, "autodeploy_report.json"))
    except OSError:
        pass


clear()
ok("no report file (job never installed): no line, no bullet", N.autodeploy_report(BASE) == (None, None))
write()
line, need = N.autodeploy_report(BASE)
ok("a fresh report: the line is passed through, no bullet while the box is only 2 h behind", line.startswith("Box code [shadow]: @abc1234") and need is None)
t, body, n = N.compose_update(at=BASE)
ok("the hourly update body carries the line", any(l.startswith("Box code [shadow]") for l in body.split("\n")))
write(ahead=40, oldest_age_h=30, decision="blocked", reasons=["no suite PASS recorded for any of the 40 undeployed commits", "x"])
line, need = N.autodeploy_report(BASE)
ok("30 h behind (> stale threshold 12 h) in SHADOW: a 'to look at' bullet naming the age, the count and the first reason, but NOT high priority (shadow can never deploy)", need and "30h behind" in need["title"] and "40 commits" in need["title"] and "no suite PASS" in need["text"] and need["prio"] == "default" and "shadow mode" in need["text"])
write(mode="enforce", ahead=40, oldest_age_h=30, decision="blocked", reasons=["no suite PASS recorded for any of the 40 undeployed commits", "x"])
line, need = N.autodeploy_report(BASE)
ok("30 h behind in ENFORCE: the same bullet is high priority (enforce could have deployed)", need and "30h behind" in need["title"] and need["prio"] == "high" and "shadow mode" not in need["text"])
write(ahead=40, oldest_age_h=30, decision="blocked", reasons=["no suite PASS recorded for any of the 40 undeployed commits", "x"])
t, body, n = N.compose_update(at=BASE)
ok("... which makes the hourly title say 'to look at' and the bullet is shown", t.startswith("⚠️") and "Box code stale" in body)
write(ahead=40, oldest_age_h=30, decision="deployed")
ok("a just-deployed report does not raise the stale bullet", N.autodeploy_report(BASE)[1] is None)
write(decision="rollback_failed", reasons=["ROLLBACK FAILED: human needed"])
line, need = N.autodeploy_report(BASE)
ok("rollback_failed: an URGENT bullet", need and need["prio"] == "urgent" and "ROLLBACK FAILED" in need["title"])
write(decision="rolled_back", reasons=["deploy failed and was rolled back (verified)"])
ok("rolled_back: a high-priority bullet", (N.autodeploy_report(BASE)[1] or {}).get("prio") == "high")
write(ts=BASE - 5 * 3600)
line, need = N.autodeploy_report(BASE)
ok("a report older than 3 h means the cron job stopped: a STALE line and a bullet (a silent deploy job is how fixes sat for hours)", "report is 5h old" in (line or "") and need and "stale" in need["title"].lower())
write(mode="off", ts=BASE - 500 * 3600)
ok("a report left by a switched-OFF job, however old, is neither a line nor a stale bullet", N.autodeploy_report(BASE) == (None, None))
write(mode="shadow", ts=BASE - 500 * 3600)
ok("the same old report in shadow IS still a stale-job bullet (cron stopped)", (N.autodeploy_report(BASE)[1] or {}).get("prio") == "high")
os.environ["OVN_AUTODEPLOY_LINE"] = "0"
ok("OVN_AUTODEPLOY_LINE=0 switches the line and the bullet off", N.autodeploy_report(BASE) == (None, None))
del os.environ["OVN_AUTODEPLOY_LINE"]
open(os.path.join(ST, "autodeploy_report.json"), "w").write("{not json")
ok("a corrupt report never breaks the hourly update", N.autodeploy_report(BASE) == (None, None) and N.compose_update(at=BASE)[0])
write(ahead=5, oldest_age_h=13, stale_threshold_h=24)
ok("the stale threshold comes from the report (13 h < 24 h: no bullet)", N.autodeploy_report(BASE)[1] is None)
print("  notify_autodeploy: %d passed, %d failed" % (ok_n, bad_n))
sys.exit(1 if bad_n else 0)
