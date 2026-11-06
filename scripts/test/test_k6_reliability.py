#!/usr/bin/env python3
"""Tests for package K6-reliability (2026-11-03): ops/cron_beats_check.py (deadman check over per-cron beats), the manifest + the '#OFF#' wrapper proposals in cron.txt, the beats line in the
08:00 ovn_notify heartbeat, the supply-forecast per-run heartbeat row and the explorer gate-skip row (parse_qwen_log must ignore it). Hermetic temp dirs, injected clocks, TZ pinned,
nothing touches ntfy / the relay / the box.

K6_ROOT=<dir> runs the same checks against a different copy of the queue tree (mutant runner at the end: every mutant must make at least one check fail). --no-mutants skips the runner."""
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("K6_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
os.environ["TZ"] = "UTC"
time.tzset()
for k in ("OVN_NOTIFY_DISABLE", "OVN_BEATS_CRONTAB", "OVN_BEATS_IN_HEARTBEAT", "OVN_BEATS_DIR", "OVN_BEATS_MANIFEST", "OVN_BEATS_CHECK", "OVN_SUPPLY_FORECAST", "OVN_Q"):
    os.environ.pop(k, None)
os.environ["NTFY_SERVER"] = "http://127.0.0.1:9"
os.environ["OVN_NOTIFY_DISABLE"] = "1"
BASE = os.path.realpath(tempfile.mkdtemp(prefix="k6-rel-"))
import atexit  # noqa: E402
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("k6-rel-") else None)
P = F = 0


def check(name, cond):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


CHK = os.path.join(ROOT, "ops", "cron_beats_check.py")
C = load(CHK, "cron_beats_check_k6")
NOW = 1_800_000_000


def beat(d, job, age_s, rc=0):
    w(os.path.join(d, job), "ts=%d rc=%d start=%d dur=1 last_ok=%d\n" % (NOW - age_s, rc, NOW - age_s - 1, NOW - age_s if rc == 0 else 0))


# =========================================================================== 1. manifest + verdicts
M = C.parse_manifest("# c\n\nfast 10 1\nslow 1440 0   # trailing\nbad name 5 0\nzero 0 0\nnoint x 0\nfast 99 0\nnocrit 60\n")
check("M1 manifest: comments, blanks, malformed, zero interval and duplicates are skipped", M == [("fast", 10, True), ("slow", 1440, False), ("nocrit", 60, False)])
JOBS = [("fast", 10, True), ("slow", 1440, False), ("mid", 60, False)]
d1 = os.path.join(BASE, "b1")
check("V1 no beat anywhere -> 'not installed' ONE line, never N alarms", C.summary_line(C.evaluate(JOBS, d1, NOW)) == "cron beats: not installed (0/3 jobs wrapped; report only)")
beat(d1, "fast", 60); beat(d1, "slow", 1440 * 60 * 2); beat(d1, "mid", 60 * 60 * 3 + 5)
R = {r["job"]: r for r in C.evaluate(JOBS, d1, NOW)["rows"]}
check("V2 fresh beat is ok", R["fast"]["status"] == "ok")
check("V3 a daily job 2 days old is still ok (limit = interval x3 = 3 days)", R["slow"]["status"] == "ok")
check("V4 a beat just over interval x3 is stale (60 min job, 3h5s)", R["mid"]["status"] == "stale")
beat(d1, "mid", 60 * 60 * 3 - 5)
check("V5 ... and just under is ok (boundary)", {r["job"]: r["status"] for r in C.evaluate(JOBS, d1, NOW)["rows"]}["mid"] == "ok")
beat(d1, "mid", 10, rc=1)
r = {r["job"]: r for r in C.evaluate(JOBS, d1, NOW)["rows"]}["mid"]
check("V6 fresh beat with rc!=0 is 'failing' (informational), not a silent job", r["status"] == "failing" and r["rc"] == 1 and C.summary_line(C.evaluate(JOBS, d1, NOW)) == "cron beats: 3/3 ok")
# never vs pending: tracking since = the oldest beat in the dir
d2 = os.path.join(BASE, "b2")
beat(d2, "slow", 60)                                      # tracking started 1 minute ago
R = {r["job"]: r["status"] for r in C.evaluate(JOBS, d2, NOW)["rows"]}
check("V7 a job without a beat is 'pending' while tracking is younger than interval x3 (a freshly wrapped job is not dead)", R["fast"] == "pending" and R["mid"] == "pending")
d3 = os.path.join(BASE, "b3")
beat(d3, "slow", 3600 * 5)                                # tracking started 5 h ago
R = {r["job"]: r["status"] for r in C.evaluate(JOBS, d3, NOW)["rows"]}
check("V8 ... and 'never' once tracking is older than interval x3 (fast: 30 min; mid: 3 h)", R["fast"] == "never" and R["mid"] == "never" and R["slow"] == "ok")
line = C.summary_line(C.evaluate(JOBS, d3, NOW))
check("V9 summary names the silent jobs, CRITICAL first with a '!' marker", line.startswith("cron beats: 1/3 ok; CRITICAL 2 silent: !fast(never)") and "mid(never)" in line)
w(os.path.join(d3, "garbage"), "not a beat")
w(os.path.join(d3, "fast"), "ts=notnum rc=\n")
check("V10 an unreadable / garbage beat file counts as no beat (never raises)", {r["job"]: r["status"] for r in C.evaluate(JOBS, d3, NOW)["rows"]}["fast"] == "never")
many = [("j%d" % i, 10, False) for i in range(9)]
d4 = os.path.join(BASE, "b4"); beat(d4, "j0", 3600 * 9)
check("V11 more than 5 silent jobs are summarised as '+N more'", "+4 more" in C.summary_line(C.evaluate(many, d4, NOW)))
check("V12 a critical-free silent set says STALE, not CRITICAL", C.summary_line(C.evaluate([("a", 10, False), ("b", 10, False)], d4, NOW)).count("STALE") == 1)
# --- review fixes (2026-11-03): persisted tracking start, partial rollout, crontab-aware judging
SINCE_JOBS = [("fast", 15, False), ("dailyok", 1440, False), ("dailyghost", 1440, True), ("hourlyghost", 60, True)]
dw = os.path.join(BASE, "bw")
beat(dw, "fast", 60); beat(dw, "dailyok", 86400)
w(os.path.join(dw, ".since"), "%d\n" % (NOW - 5 * 86400))          # first beat ever: 5 days ago (a persisted marker)
RW = {r["job"]: r["status"] for r in C.evaluate(SINCE_JOBS, dw, NOW)["rows"]}
check("W1 a critical daily job that never ran is 'never' (not 'pending') even though other jobs keep beating (tracking start is the persisted marker, not the oldest latest-beat)", RW["dailyghost"] == "never" and RW["hourlyghost"] == "never" and RW["fast"] == "ok" and RW["dailyok"] == "ok")
check("W2 ... and the report names both critical ghosts", "!dailyghost(never)" in C.summary_line(C.evaluate(SINCE_JOBS, dw, NOW)))
dw2 = os.path.join(BASE, "bw2")
beat(dw2, "fast", 60); beat(dw2, "dailyok", 86400)
w(os.path.join(dw2, ".since"), "%d\n" % (NOW - 3600))               # tracking started 1 h ago: daily ghost still pending
check("W3 with a young marker a daily job is still pending (never needs interval x3 of tracking)", {r["job"]: r["status"] for r in C.evaluate(SINCE_JOBS, dw2, NOW)["rows"]}["dailyghost"] == "pending")
check("W3b the verdict does not move when other jobs re-beat (marker is persisted)", {r["job"]: r["status"] for r in C.evaluate(SINCE_JOBS, dw, NOW + 7200)["rows"]}["dailyghost"] == "never")
# partial rollout: only wrapped jobs are judged
RP = C.evaluate(SINCE_JOBS, dw, NOW, wrapped={"fast", "dailyok"})
check("W4 partial rollout: unwrapped jobs are 'unwrapped' (not judged), never 'never'", {r["job"]: r["status"] for r in RP["rows"]} == {"fast": "ok", "dailyok": "ok", "dailyghost": "unwrapped", "hourlyghost": "unwrapped"})
check("W5 partial rollout: the line has no CRITICAL/STALE and counts the unwrapped jobs", C.summary_line(RP) == "cron beats: 2/2 ok, 2 unwrapped")
check("W6 a wrapped job IS judged (wrapped={'dailyghost'} -> never)", {r["job"]: r["status"] for r in C.evaluate(SINCE_JOBS, dw, NOW, wrapped={"dailyghost"})["rows"]}["dailyghost"] == "never")
CT = "# c\n#OFF# 0 * * * * /x/ops/cron_beat.sh offjob ./a.sh\n0 * * * * cd /q && /q/ops/cron_beat.sh hourly env A=1 ./h.sh >> l 2>&1\n*/5 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n0 4 * * * ./plain.sh\n"
check("W7 wrapped_jobs reads active lines only ('#OFF#' proposals, comments and unwrapped lines do not count)", C.wrapped_jobs(CT) == {"hourly", "fast"} and C.wrapped_jobs("") == set() and C.wrapped_jobs(None) == set())
dt = os.path.join(BASE, "bt")
sn = C.track_wrapped(dt, {"late"}, NOW - 600)
sn2 = C.track_wrapped(dt, {"late"}, NOW)
check("W8 first-seen-wrapped marker is written once and never moves", sn == {"late": NOW - 600} and sn2 == {"late": NOW - 600})
w(os.path.join(dt, ".since"), "%d\n" % (NOW - 9 * 86400)); beat(dt, "other", 60)
LJ = [("late", 60, True), ("other", 60, False)]
dg = os.path.join(BASE, "bg"); w(os.path.join(dg, ".wrapped.gj"), "garbage\n")
C.track_wrapped(dg, {"gj"}, NOW)
check("W8b a garbage marker is healed (re-stamped), then stable", C.track_wrapped(dg, {"gj"}, NOW + 5) == {"gj": NOW})
check("W9 a job wrapped late (marker 10 min old) is pending despite an old global marker; once its marker is old it is never", {r["job"]: r["status"] for r in C.evaluate(LJ, dt, NOW, wrapped={"late", "other"}, seen={"late": NOW - 600})["rows"]}["late"] == "pending" and {r["job"]: r["status"] for r in C.evaluate(LJ, dt, NOW, wrapped={"late", "other"}, seen={"late": NOW - 4 * 3600})["rows"]}["late"] == "never")
ctf = os.path.join(BASE, "ct.txt"); w(ctf, "*/5 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n")
dm = os.path.join(BASE, "bm"); beat(dm, "fast", 60); w(os.path.join(dm, ".since"), "%d\n" % (NOW - 5 * 86400))
manm = os.path.join(BASE, "mm.manifest"); w(manm, "fast 15 1\nghost 60 1\nqtmp_reaper 1440 0\n")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcm = C.main(["x", "--manifest", manm, "--beats", dm, "--crontab", ctf, "--now", str(NOW), "--strict", "--line"])
check("W10 main(): with only 'fast' wrapped in the crontab, unwrapped ghost/qtmp_reaper do not alarm (rc 0, no CRITICAL)", rcm == 0 and "CRITICAL" not in buf.getvalue() and "2 unwrapped" in buf.getvalue())
w(ctf, "*/5 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n0 * * * * /q/ops/cron_beat.sh ghost /q/g.sh\n")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcm = C.main(["x", "--manifest", manm, "--beats", dm, "--crontab", ctf, "--now", str(NOW), "--strict", "--line"])
check("W11 main(): once ghost is wrapped and past its window it is CRITICAL never (rc 1 with --strict)... but its first-seen marker starts now, so it is pending first", rcm == 0 and "1 pending" in buf.getvalue())
beat(dm, "fast", -4 * 3600 + 60)                               # 'fast' keeps beating, so only the ghost is silent
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcm = C.main(["x", "--manifest", manm, "--beats", dm, "--crontab", ctf, "--now", str(NOW + 4 * 3600), "--strict", "--line"])
check("W12 ... and 4 h later (interval x3 = 3 h) it is CRITICAL never, rc 1", rcm == 1 and "CRITICAL 1 silent: !ghost(never)" in buf.getvalue())
beat(dm, "fast", -99 * 3600 + 60)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcm = C.main(["x", "--manifest", manm, "--beats", dm, "--crontab", os.path.join(BASE, "no_such_crontab"), "--now", str(NOW + 99 * 3600), "--strict", "--line"])
check("W13 an unreadable crontab judges nothing as 'never' (rc 0)", rcm == 0 and "never" not in buf.getvalue())
# main(): exit codes
d5 = os.path.join(BASE, "b5"); beat(d5, "fast", 3600 * 9); beat(d5, "mid", 5)
man = os.path.join(BASE, "m.manifest"); w(man, "fast 10 1\nmid 60 0\n")
ct5 = os.path.join(BASE, "ct5.txt"); w(ct5, "*/10 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n0 * * * * /q/ops/cron_beat.sh mid /q/m.sh\n")   # both jobs are wrapped in the live crontab


def run_main(*args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = C.main(["x", "--manifest", man, "--beats", d5, "--crontab", ct5, "--now", str(NOW)] + list(args))
    return rc, buf.getvalue()


rc, out = run_main()
check("E1 default exit is 0 even with a critical job silent (report only) and details are listed", rc == 0 and "CRITICAL 1 silent: !fast(9h)" in out and "stale" in out)
rc, out = run_main("--strict")
check("E2 --strict exits 1 when a CRITICAL job is silent", rc == 1)
rc, out = run_main("--line")
check("E3 --line prints exactly one line", out.count("\n") == 1)
rc, out = run_main("--json")
check("E4 --json is parseable and carries the rows", '"status": "stale"' in out)
check("E5 a missing manifest is an empty report, exit 0 (never a traceback)", C.main(["x", "--manifest", os.path.join(BASE, "nope"), "--beats", d5]) == 0)

# =========================================================================== 2. cron expression -> longest gap
iv = C.cron_interval_minutes
check("I1 */20 -> 20, 7,37 -> 30, 10,30,50 -> 20 (max gap incl. wrap)", iv("*/20 * * * *") == 20 and iv("7,37 * * * *") == 30 and iv("10,30,50 * * * *") == 20)
check("I2 hourly 0 * -> 60, 0 */3 -> 180, 0 */6 -> 360, 17 3 daily -> 1440", iv("0 * * * *") == 60 and iv("0 */3 * * *") == 180 and iv("0 */6 * * *") == 360 and iv("17 3 * * *") == 1440)
check("I3 the LONGEST gap wins (0 8,20 -> 720; 5 1,2,3 -> 1320 wrap)", iv("0 8,20 * * *") == 720 and iv("5 1,2,3 * * *") == 1320)
check("I4 day-of-week restricted -> 10080, day-of-month restricted -> 44640, * * * * * -> 1", iv("0 4 * * 1") == 10080 and iv("0 4 1 * *") == 44640 and iv("* * * * *") == 1)
check("I5 unparseable -> None", iv("garbage") is None and iv("a b c d e") is None)

# =========================================================================== 3. derive / propose
CRON = """# comment
NTFY_SERVER=http://127.0.0.1:9
0 */3 * * * cd /h/q && NTFY_TOPIC=t SUPERVISOR_USE_LOCAL=1 ./supervisor.sh >> logs/supervisor.log 2>&1
20 * * * * cd /h/q && python3 scripts/ovn_notify.py update >> logs/n.log 2>&1
*/10 * * * * cd /h/q && python3 scripts/ovn_notify.py check >> logs/n.log 2>&1
*/20 * * * * /h/q/fleet_autofix.sh >> /h/q/logs/fa.log 2>&1
3,33 * * * * cd $HOME/q && python3 scripts/ovn_work_supply.py gitlark --max 12 >> logs/ws.log 2>&1
9,39 * * * * cd $HOME/q && python3 scripts/ovn_work_supply.py billwatch --max 12 >> logs/ws.log 2>&1
40 3 * * * cd ~/q && [ -s prework/queue.tsv ] && timeout 300 ./ovn_prework.sh >> logs/p.log 2>&1
*/10 * * * * cd ~/q && flock -n state/g.lock sh -c 'for r in a b; do python3 scripts/ovn_spec_gate.py scan $r; done' >> logs/g.log 2>&1
30 9 * * * cd /h/q && ./scripts/two_cmds.sh && ./scripts/other.sh >> logs/t.log 2>&1
"""
cj = C.cron_jobs(CRON)
names = [j for j, _, _ in cj]
check("D1 job names: script basename; scripts with several lines get the next plain word (ovn_notify_update/_check, ovn_work_supply_gitlark)", names[:6] == ["supervisor", "ovn_notify_update", "ovn_notify_check", "fleet_autofix", "ovn_work_supply_gitlark", "ovn_work_supply_billwatch"])
dv = C.derive(CRON)
check("D2 derive lists wrappable jobs with their longest-gap interval", "supervisor 180 0" in dv and "ovn_notify_check 10 0" in dv and "ovn_work_supply_gitlark 30 0" in dv and "fleet_autofix 20 0" in dv)
check("D3 derive omits compound lines (a job that cannot carry the wrapper would read 'never' forever)", "ovn_prework" not in dv and "ovn_spec_gate" not in dv and "two_cmds" not in dv)
pr = C.propose(CRON, "/h/q/ops/cron_beat.sh")
pl = [x for x in pr.splitlines()]
check("D4 propose: cd stays first, wrapper next, env assignments move behind `env`, redirect stays outside",
      "#OFF# 0 */3 * * * cd /h/q && /h/q/ops/cron_beat.sh supervisor env NTFY_TOPIC=t SUPERVISOR_USE_LOCAL=1 ./supervisor.sh >> logs/supervisor.log 2>&1" in pl)
check("D5 propose: no cd / no env shapes", "#OFF# */20 * * * * /h/q/ops/cron_beat.sh fleet_autofix /h/q/fleet_autofix.sh >> /h/q/logs/fa.log 2>&1" in pl and
      "#OFF# 20 * * * * cd /h/q && /h/q/ops/cron_beat.sh ovn_notify_update python3 scripts/ovn_notify.py update >> logs/n.log 2>&1" in pl)
check("D6 propose: compound lines are NOT wrapped, listed as comments for a human", sum(1 for x in pl if x.startswith("# NOT WRAPPED")) == 3 and not any("cron_beat.sh ovn_prework" in x for x in pl))
check("D7 propose: every wrapped line is a '#OFF#' proposal (nothing active)", all(x.startswith("#") for x in pl))
check("D8 derive and propose agree on the wrappable set (same job names)", sorted(l.split()[0] for l in dv.splitlines() if not l.startswith("#")) == sorted(re.search(r"cron_beat\.sh (\S+)", x).group(1) for x in pl if x.startswith("#OFF#")))

# the repo's own files
MANIFEST = os.path.join(ROOT, "scripts", "cron_beats.manifest")
SNAP = os.path.join(ROOT, "ops", "crontab.box.snapshot.txt")
CRONTXT = os.path.join(ROOT, "scripts", "cron.txt")
mj = {j: (i, c) for j, i, c in C.parse_manifest(open(MANIFEST).read())}
snap = C.derive(open(SNAP).read())
sj = {l.split()[0]: int(l.split()[1]) for l in snap.splitlines() if not l.startswith("#")}
# (the live crontab has more lines of ovn_work_supply / ovn_local_research than the older snapshot, so those two carry a per-repo suffix in the manifest)
check("R1 every wrappable job of the committed box crontab snapshot is in the manifest with the SAME interval", all((j in mj and mj[j][0] == i) or any(m.startswith(j + "_") and mj[m][0] == i for m in mj) for j, i in sj.items()) and len(sj) > 40)
crit = sorted(j for j, (i, c) in mj.items() if c)
check("R2 critical flags: hygiene x4, reconcile, pause/lock guards, gpu autoswap, autofix, notifier x2, hourly backup, queue_health", crit == sorted(
    ["branch_hygiene_1", "branch_hygiene_2", "branch_hygiene_3", "branch_hygiene_4", "reconcile_branches", "pause_guard", "lock_guard", "gpu_autoswap", "fleet_autofix", "ovn_notify_update", "ovn_notify_check", "box_home_backup_hourly", "queue_health"]))
ct = open(CRONTXT).read().splitlines()
active_wrap = [l for l in ct if not l.lstrip().startswith("#") and "cron_beat.sh" in l]
off_wrap = [l for l in ct if l.startswith("#OFF#") and "ops/cron_beat.sh" in l]
check("R3 cron.txt carries '#OFF#' beat-wrapper proposals and NONE of them is active", len(off_wrap) >= 40 and not active_wrap)
wrapped_names = [re.search(r"ops/cron_beat\.sh (\S+)", l).group(1) for l in off_wrap if re.search(r"ops/cron_beat\.sh (\S+)", l)]
check("R4 every wrapped job name in the proposals is a manifest job", all(n in mj for n in wrapped_names))
check("R6 the wrapper and the queue-tmp reaper / checker are executable files", all(os.access(os.path.join(ROOT, "ops", f), os.X_OK) for f in ("cron_beat.sh", "qtmp_reaper.sh", "cron_beats_check.py")))

# =========================================================================== 4. heartbeat line in ovn_notify
ST = os.path.join(BASE, "nq", "state")
os.makedirs(ST)
os.environ.update(OVN_NOTIFY_STATE=ST, NTFY_TOPIC="t_k6", OVN_BEATS_MANIFEST=man, OVN_BEATS_CHECK=CHK)
sys.modules.pop("ovn_notify", None)
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_notify as N  # noqa: E402
N.now = lambda: NOW
CTH = os.path.join(BASE, "cth.txt"); w(CTH, "0 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n0 * * * * /q/ops/cron_beat.sh mid /q/m.sh\n")
os.environ["OVN_BEATS_CRONTAB"] = CTH
t, b = N.heartbeat_text(NOW)
lines = b.split("\n")
check("H0 DEFAULT (flag unset, wrappers wrapped but no beat yet): ONE extra line says so (Y1: no longer silently omitted)", len(lines) == 2 and lines[0].startswith("0 sent/24h") and lines[1] == "beats: not rolled out (2 wrapped jobs, no beat yet)")
_CT0 = os.path.join(BASE, "ct0.txt"); w(_CT0, "0 * * * * /q/f.sh\n")
os.environ["OVN_BEATS_CRONTAB"] = _CT0
t, b = N.heartbeat_text(NOW)
lines = b.split("\n")
check("H0b DEFAULT, no crontab entry uses cron_beat.sh: exactly 'beats: not rolled out (0 wrapped jobs)', once", len(lines) == 2 and lines[1] == "beats: not rolled out (0 wrapped jobs)" and b.count("not rolled out") == 1)
os.environ["OVN_BEATS_IN_HEARTBEAT"] = "off"
t, b = N.heartbeat_text(NOW)
check("H0c OVN_BEATS_IN_HEARTBEAT=off still omits it", "\n" not in b)
del os.environ["OVN_BEATS_IN_HEARTBEAT"]
os.environ["OVN_BEATS_CRONTAB"] = CTH
os.environ["OVN_BEATS_IN_HEARTBEAT"] = "on"
t, b = N.heartbeat_text(NOW)
lines = b.split("\n")
check("H1 OVN_BEATS_IN_HEARTBEAT=on adds ONE beats line even uninstalled ('not installed')", len(lines) == 2 and lines[0].startswith("0 sent/24h") and lines[1] == "cron beats: not installed (0/2 jobs wrapped; report only)")
del os.environ["OVN_BEATS_IN_HEARTBEAT"]
beat(os.path.join(ST, "beats"), "fast", 60); beat(os.path.join(ST, "beats"), "mid", 60)
t, b = N.heartbeat_text(NOW)
check("H2 default + installed (beats exist): the line reads '2/2 ok'", b.split("\n")[1] == "cron beats: 2/2 ok")
beat(os.path.join(ST, "beats"), "fast", 3600 * 9)
t, b = N.heartbeat_text(NOW)
check("H3 a silent critical job shows up in the 08:00 line", b.split("\n")[1].startswith("cron beats: 1/2 ok; CRITICAL 1 silent: !fast(9h)"))
os.environ["OVN_BEATS_IN_HEARTBEAT"] = "off"
check("H4 OVN_BEATS_IN_HEARTBEAT=off removes the line", "cron beats" not in N.heartbeat_text(NOW)[1])
del os.environ["OVN_BEATS_IN_HEARTBEAT"]
os.environ["OVN_BEATS_CHECK"] = os.path.join(BASE, "missing_checker.py")
check("H5 a missing checker adds nothing and never raises", "cron beats" not in N.heartbeat_text(NOW)[1])
w(os.path.join(BASE, "broken.py"), "raise RuntimeError('boom')\n")
os.environ["OVN_BEATS_CHECK"] = os.path.join(BASE, "broken.py")
check("H6 a checker that raises adds nothing and never breaks the heartbeat", "cron beats" not in N.heartbeat_text(NOW)[1] and N.heartbeat_text(NOW)[0].startswith("ntfy alive"))
os.environ["OVN_BEATS_CHECK"] = CHK
posts = []
orig = N.forward
N.forward = lambda *a, **k: posts.append((a, k)) or "disabled"
res = N.do_heartbeat(dry=True)
check("H7 --dry-run returns the text with the beats line and pushes nothing", "cron beats:" in res and not posts)
N.forward = orig

# =========================================================================== 5. supply forecast per-run heartbeat row
SFP = os.path.join(ROOT, "scripts", "ovn_supply_forecast.py")
sf = load(SFP, "ovn_supply_forecast_k6")
fcq = {"mode": "shadow", "ts": NOW, "runway_floor_h": 24.0, "target_h": 48.0, "repos": {"a": {"short": False, "line": "a ok"}, "b": {"short": False, "line": "b ok"}}}
sroot = os.path.join(BASE, "sf"); sstate = os.path.join(sroot, "state"); os.makedirs(sstate)
sf.write_outputs(fcq, root=sroot, state=sstate, stamp="T1")
sf.write_outputs(fcq, root=sroot, state=sstate, stamp="T2")
lg = open(os.path.join(sroot, "logs", "supply_forecast.log")).read().splitlines()
check("S1 a healthy run (no repo short) still writes ONE heartbeat row per run: quiet != dead", lg == ["T1 hb mode=shadow checked=2 short=0 floor_h=24", "T2 hb mode=shadow checked=2 short=0 floor_h=24"])
fcs = dict(fcq, repos={"a": {"short": True, "line": "a: runway 0h"}, "b": {"short": False, "line": "b ok"}})
sf.write_outputs(fcs, root=sroot, state=sstate, stamp="T3")
lg = open(os.path.join(sroot, "logs", "supply_forecast.log")).read().splitlines()
check("S2 a run with a short repo writes the heartbeat AND the per-repo [shadow] row", lg[-2] == "T3 hb mode=shadow checked=2 short=1 floor_h=24" and lg[-1] == "T3 [shadow] a: runway 0h")
check("S3 the heartbeat row carries no '[mode]' tag (the per-repo rows own that token)", all("[shadow]" not in l for l in lg if " hb " in l))

# =========================================================================== 6. explorer gate-skip row is invisible to the supply report parser
SR = load(os.path.join(ROOT, "scripts", "ovn_supply_report.py"), "ovn_supply_report_k6")
real = "2026-11-02 17:36:17 test-automation-agent lens=dead-code result=empty files=6 proposed=4 accepted=0 rejected={verify-dialect:4} calls=2 tok=9599/1206 69s\n"
gate = "2026-11-03 09:00:00 test-automation-agent gate-skip: next pass in 120s (explorer idle by design; one heartbeat per 1800s)\n"
check("Q1 parse_qwen_log gives the same result with and without gate-skip rows", SR.parse_qwen_log(real) == SR.parse_qwen_log(real + gate) and "test-automation-agent" in SR.parse_qwen_log(real + gate))

# --- rollback scenario (review fix 2026-11-03): a stale beat of a job whose wrapper line was rolled back must not alarm
dr = os.path.join(BASE, "brb")
beat(dr, "fast", 60); beat(dr, "mid", 3600 * 30); beat(dr, "slow", 86400 * 20)      # mid: 30 h old (interval 180m -> would be stale); slow: 20 d old
w(os.path.join(dr, ".since"), "%d\n" % (NOW - 30 * 86400))
RB_JOBS = [("fast", 15, True), ("mid", 180, True), ("slow", 1440, True)]
RB = C.evaluate(RB_JOBS, dr, NOW, wrapped={"fast"})
check("X1 rollback: stale beats of jobs no longer wrapped are not stale (mid -> orphan-beat, slow past 7 d -> ignored 'unwrapped'); the wrapped job is ok", {r["job"]: r["status"] for r in RB["rows"]} == {"fast": "ok", "mid": "orphan-beat", "slow": "unwrapped"})
check("X2 rollback: the line has no STALE/CRITICAL and reports the orphan as info", C.summary_line(RB) == "cron beats: 1/1 ok, 1 unwrapped, 1 orphan-beat")
ctr = os.path.join(BASE, "ct_rb.txt"); w(ctr, "*/5 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n#OFF# 0 * * * * /q/ops/cron_beat.sh mid /q/m.sh\n0 * * * * /q/m.sh\n")
manr = os.path.join(BASE, "rb.manifest"); w(manr, "fast 15 1\nmid 180 1\nslow 1440 1\n")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcr = C.main(["x", "--manifest", manr, "--beats", dr, "--crontab", ctr, "--now", str(NOW), "--strict"])
check("X3 main(): rollback of a wrapped cron line (live crontab no longer wraps it) -> rc 0 under --strict, no STALE/CRITICAL, orphan-beat shown", rcr == 0 and "STALE" not in buf.getvalue().replace("orphan", "") and "CRITICAL" not in buf.getvalue() and "orphan-beat" in buf.getvalue())
w(ctr, "*/5 * * * * /q/ops/cron_beat.sh fast /q/f.sh\n0 * * * * /q/ops/cron_beat.sh mid /q/m.sh\n")
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rcr = C.main(["x", "--manifest", manr, "--beats", dr, "--crontab", ctr, "--now", str(NOW), "--strict"])
check("X4 main(): while the line IS wrapped the same 30 h old beat is stale/CRITICAL (rc 1 --strict)", rcr == 1 and "CRITICAL" in buf.getvalue())
only = C.evaluate([("mid", 180, True)], dr, NOW, wrapped=set())
check("X5 only orphan beats left -> 'not installed' collapse (no alarm)", C.summary_line(only).startswith("cron beats: not installed") and not only["installed"])
check("X6 unreadable crontab (wrapped=set()) never alarms even with old beats", all(r["status"] in ("orphan-beat", "unwrapped") for r in C.evaluate(RB_JOBS, dr, NOW, wrapped=set())["rows"]))
check("X7 legacy mode (wrapped=None) still judges every beat", {r["job"]: r["status"] for r in C.evaluate(RB_JOBS, dr, NOW)["rows"]}["mid"] == "stale")

print("  %d passed, %d failed" % (P, F))
if "--no-mutants" in sys.argv:
    sys.exit(1 if F else 0)
if F:
    sys.exit(1)

# =========================================================================== mutants
MUT = [
    ("checker: factor 3 -> 30", "ops/cron_beats_check.py", "FACTOR = 3.0", "FACTOR = 30.0"),
    ("checker: stale never fires", "ops/cron_beats_check.py", 'st = "stale" if age > lim else', 'st = "stale" if age > lim * 1000 else'),
    ("checker: never is always pending", "ops/cron_beats_check.py", 'st = "never" if start is not None and now - start > lim else "pending"', 'st = "pending"'),
    ("checker: tracking start derived from oldest latest-beat again", "ops/cron_beats_check.py", "    since = read_since(beats_dir)\n", "    since = min(have) if have else None\n"),
    ("checker: beat of unwrapped job judged (rollback false alarm)", "ops/cron_beats_check.py", "if wrapped is not None and job not in wrapped:\n            st = \"orphan-beat\"", "if False:\n            st = \"orphan-beat\""),
    ("checker: orphan beats never expire", "ops/cron_beats_check.py", 'age <= ORPHAN_DAYS * 86400 else "unwrapped"', 'age <= ORPHAN_DAYS * 86400 * 1000 else "unwrapped"'),
    ("checker: orphan beats count as installed", "ops/cron_beats_check.py", '"installed": bool(live)}', '"installed": bool(have)}'),
    ("checker: orphan counted as silent in the line", "ops/cron_beats_check.py", 'not in ("unwrapped", "orphan-beat")]', 'not in ("unwrapped",)]'),
    ("checker: unwrapped jobs judged", "ops/cron_beats_check.py", "if wrapped is not None and job not in wrapped:", "if False:"),
    ("checker: #OFF# proposals count as wrapped", "ops/cron_beats_check.py", 'if ln.lstrip().startswith("#"):\n            continue', "pass"),
    ("checker: first-seen marker ignored (always re-stamped)", "ops/cron_beats_check.py", "            if v.isdigit():\n                seen[job] = int(v)\n                continue", "            pass"),
    ("checker: garbage marker never healed", "ops/cron_beats_check.py", "            if os.path.exists(p):\n                os.unlink(p)", "            pass"),
    ("checker: per-job marker ignored", "ops/cron_beats_check.py", "start = seen.get(job, since)", "start = since"),
    ("checker: unreadable crontab = all wrapped", "ops/cron_beats_check.py", "wrapped = wrapped_jobs(ct) if ct is not None else set()\n    res =", "wrapped = wrapped_jobs(ct) if ct is not None else None\n    res ="),
    ("notify: beats line default always on", "scripts/ovn_notify.py", 'if not res["installed"] and mode not in ("on", "1", "yes", "true"):', "if False:"),
    ("checker: uninstalled does not collapse", "ops/cron_beats_check.py", 'if not res["installed"]:', "if False:"),
    ("checker: critical flag ignored in the line", "ops/cron_beats_check.py", "crit = [r for r in bad if r[\"critical\"]]", "crit = []"),
    ("checker: strict never fails", "ops/cron_beats_check.py", 'if "--strict" in argv and any(', 'if False and any('),
    ("checker: min gap instead of max gap", "ops/cron_beats_check.py", "return max(max(gaps), 1)", "return max(min(gaps), 1)"),
    ("checker: dow restriction ignored", "ops/cron_beats_check.py", 'if f[4] != "*":\n        return 10080', 'if False:\n        return 10080'),
    ("checker: duplicates accepted", "ops/cron_beats_check.py", "or f[0] in seen:", ":"),
    ("checker: derive keeps compound lines", "ops/cron_beats_check.py", "if iv and _wrap_parts(s):", "if iv:"),
    ("checker: propose drops env", "ops/cron_beats_check.py", '("env " + env + " ") if env else ""', '""'),
    ("checker: propose wraps compound lines", "ops/cron_beats_check.py", "if not m or re.search(r\"(&&|", "if not m or re.search(r\"(NEVERMATCH|"),
    ("checker: failing counted as silent", "ops/cron_beats_check.py", 'ok = sum(1 for r in rows if r["status"] in ("ok", "failing"))', 'ok = sum(1 for r in rows if r["status"] in ("ok",))'),
    ("notify: beats line never added", "scripts/ovn_notify.py", "beats = cron_beats_line(t)", 'beats = ""'),
    ("notify: kill switch ignored", "scripts/ovn_notify.py", 'if mode in ("off", "0", "no", "false"):', 'if False:'),
    ("notify: checker exceptions escape", "scripts/ovn_notify.py", "        return mod.summary_line(res)[:300]\n    except Exception:\n        return \"\"", "        return mod.summary_line(res)[:300]\n    except KeyboardInterrupt:\n        return \"\""),
    ("forecast: no heartbeat row", "scripts/ovn_supply_forecast.py", 'f.write("%s hb mode=%s', 'f.write("") and ("%s hb mode=%s'),
    ("forecast: heartbeat carries the mode tag", "scripts/ovn_supply_forecast.py", '"%s hb mode=%s checked', '"%s [shadow] hb mode=%s checked'),
]
tmpd = tempfile.mkdtemp(prefix="k6-mut-")
bad = 0
try:
    for sub in ("ops", "scripts"):
        os.makedirs(os.path.join(tmpd, sub))
        for fn in os.listdir(os.path.join(ROOT, sub)):
            if fn.endswith((".py", ".manifest", ".txt", ".sh")) and os.path.isfile(os.path.join(ROOT, sub, fn)):
                shutil.copy(os.path.join(ROOT, sub, fn), os.path.join(tmpd, sub))
    for name, f, old, new in MUT:
        src = open(os.path.join(ROOT, f)).read()
        if old not in src:
            print("  MUTANT SETUP FAIL (pattern not found): " + name)
            bad += 1
            continue
        open(os.path.join(tmpd, f), "w").write(src.replace(old, new, 1))
        r = subprocess.run([sys.executable, os.path.abspath(__file__), "--no-mutants"], env=dict(os.environ, K6_ROOT=tmpd), capture_output=True, text=True, timeout=300)
        killed = r.returncode != 0
        print("  %s MUTANT %s" % ("killed  " if killed else "SURVIVED", name))
        bad += 0 if killed else 1
        shutil.copy(os.path.join(ROOT, f), os.path.join(tmpd, f))
finally:
    shutil.rmtree(tmpd, ignore_errors=True)
print("  mutants: %d of %d survived" % (bad, len(MUT)))
sys.exit(1 if bad else 0)
