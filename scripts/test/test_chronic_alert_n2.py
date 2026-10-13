#!/usr/bin/env python3
"""Tests for scripts/ovn_chronic_alert.py (package qa, 2026-10-13, platform-night G5): chronic conditions (gpu-util, roadmap-floor) are folded into ONE daily
`info | chronic-daily` alerts.log line; the FIRST sighting of a condition is still written at once with its original level and wording (a real alert is never lost
or delayed); OVN_CHRONIC_DAILY=off restores the legacy per-condition lines. Also: the local-research refuel notice is level info.
Pure python, no network. Real entry points: ovn_chronic_alert.note, `ovn_stats.py --gpu-alert`, `ovn_research_trigger_check.py`."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SCRIPTS)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


for _k in ("OVN_CHRONIC_DAILY", "OVN_CHRONIC_DIGEST_HOUR", "OVN_CHRONIC_ACTIVE_H", "OVN_CHRONIC_ONSET_GAP_H", "OVN_CHRONIC_QUIET_H", "OVN_CHRONIC_LOCK_WAIT_S"):
    os.environ.pop(_k, None)
# The onset/repeat/digest scenarios below sample a condition sparsely (a few calls per simulated day) to keep them short; the real emitters call every 15-30 min. The
# quiet-gap rule (silence > 12 h = the condition cleared, so its return is a new onset) is therefore switched off for those scenarios (env, read at import) and tested
# on its own further down with the real default.
os.environ["OVN_CHRONIC_QUIET_H"] = "100000"
import ovn_chronic_alert as ca  # noqa: E402
_QUIET_DEFAULT = 12.0

D0 = time.mktime((2026, 10, 13, 12, 0, 0, 0, 0, -1))     # a local noon
H = 3600.0


def mk():
    return tempfile.mkdtemp(prefix="chronic-n2-")


def alerts(d):
    p = os.path.join(d, "alerts.log")
    return open(p).read().splitlines() if os.path.exists(p) else []


def line(tag, msg, lvl="warn", now=D0):
    return "[%s] %s | %s | %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), lvl, tag, msg)


# ------------------------------------------------------------------------------------------------------------------ unit: onset / repeat / digest
d = mk()
w = ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26% over the last 24h"), D0)
ok("ONSET: the first sighting writes the emitter's OWN line at once (level warn kept)", w and alerts(d) == [w] and "] warn | gpu-util | GPU busy only 26%" in alerts(d)[0])
for i in range(1, 25):
    ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26% over the last 24h", now=D0 + i * 0.25 * H), D0 + i * 0.25 * H)
ok("REPEAT: 24 more samples over 6 h write NOTHING (was one line per 6 h)", len(alerts(d)) == 1, str(alerts(d)))
# next day, 06:00 -> before the digest hour: nothing
day1_6 = D0 + 18 * H
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 24% now", now=day1_6), day1_6)
ok("before OVN_CHRONIC_DIGEST_HOUR (7): still nothing", len(alerts(d)) == 1)
day1_8 = D0 + 20 * H   # 08:00 next day
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 22% now", now=day1_8), day1_8)
a = alerts(d)
ok("first note() at/after 07:00 the next day writes ONE digest line, level info, tag chronic-daily", len(a) == 2 and "] info | chronic-daily |" in a[1], str(a))
ok("the digest names the tag, its CURRENT text and when it was last seen", "gpu-util: GPU busy only 22% now (last seen 08:00)" in a[1], a[-1])
for i in range(1, 10):
    ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 22% now", now=day1_8 + i * 0.25 * H), day1_8 + i * 0.25 * H)
ok("at most ONE digest per local day (9 more samples the same day: nothing)", len(alerts(d)) == 2)
day2_8 = D0 + 44 * H
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 20% now", now=day2_8), day2_8)
ok("the day after: one more digest (one line per day while the condition persists)", len(alerts(d)) == 3 and "] info | chronic-daily |" in alerts(d)[2])
shutil.rmtree(d)

# two chronic tags collapse into ONE line
d = mk()
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%"), D0)
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "roadmap-feature floor: xlite has had backlog 0 for 7.1h"), D0 + 0.5 * H)
ok("two different conditions each get their ONSET line (both are real new alerts)", len(alerts(d)) == 2 and "roadmap-feature floor" in alerts(d)[1])
t = D0 + 20 * H
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "roadmap-feature floor: xlite has had backlog 0 for 27.1h", now=t), t)
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 21%", now=t), t)
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "roadmap-feature floor: xlite has had backlog 0 for 27.3h", now=t + 600), t + 600)
a = alerts(d)
ok("next morning BOTH chronic conditions are ONE digest line (was 1 gpu + 1 floor)", len(a) == 3 and a[2].count("|") >= 2 and "gpu-util: " in a[2] and "roadmap-floor:xlite: " in a[2] and "2 chronic condition(s)" in a[2], str(a))
shutil.rmtree(d)

# a condition that cleared is not reported
d = mk()
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%"), D0)
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "floor 7h"), D0)
t = D0 + 30 * H      # 18:00 the next day: the floor tag was last seen 30 h ago (> the 26 h window), gpu-util is refreshed right now
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 21%", now=t - 600), t - 600)
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 21%", now=t), t)
a = alerts(d)
ok("a condition NOT refreshed for > 26 h (it cleared) is left out of the digest", len(a) == 3 and "gpu-util: " in a[2] and "roadmap-floor" not in a[2], str(a))
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "floor 7h", now=t + 600), t + 600)
ok("at most ONE digest per local day: a tag that was left out of it (not seen for 30 h) and is noted again later the same day does NOT trigger a second digest", len(alerts(d)) == 3, str(alerts(d)))
# re-onset after the gap: the tag was silent > 36 h -> a fresh onset line
t2 = D0 + 100 * H
ca.note(d, "roadmap-floor:xlite", line("ongoing-xlite", "floor 7h again", now=t2), t2)
ok("a condition that returns after > 36 h of silence is a NEW onset (written at once)", "floor 7h again" in alerts(d)[-1] and "] warn | ongoing-xlite" in alerts(d)[-1], str(alerts(d)))
shutil.rmtree(d)

# digest hour is tunable; garbage falls back
d = mk()
ca.note(d, "gpu-util", line("gpu-util", "x"), D0)
t = D0 + 14 * H     # 02:00 next day
os.environ["OVN_CHRONIC_DIGEST_HOUR"] = "1"
ca.note(d, "gpu-util", line("gpu-util", "x", now=t), t)
ok("OVN_CHRONIC_DIGEST_HOUR=1: the 02:00 note() already writes the digest", len(alerts(d)) == 2, str(alerts(d)))
os.environ["OVN_CHRONIC_DIGEST_HOUR"] = "zz"
ok("a garbage digest hour falls back to 7", ca.digest_hour() == 7)
del os.environ["OVN_CHRONIC_DIGEST_HOUR"]
shutil.rmtree(d)

# kill switch + fail-safe
os.environ["OVN_CHRONIC_DAILY"] = "off"
ok("OVN_CHRONIC_DAILY=off => enabled() is False", ca.enabled() is False)
del os.environ["OVN_CHRONIC_DAILY"]
ok("default => enabled()", ca.enabled() is True)
d = mk()
open(os.path.join(d, ca.STATE_FILE), "w").write("{not json")
w = ca.note(d, "gpu-util", line("gpu-util", "x"), D0)
ok("a corrupt state file is treated as empty: the onset line is written", w and len(alerts(d)) == 1)
shutil.rmtree(d)
d = mk()
os.makedirs(os.path.join(d, "alerts.log"))      # alerts.log is a directory: unwritable
try:
    w = ca.note(d, "gpu-util", line("gpu-util", "x"), D0)
    ok("an unwritable alerts.log never raises (returns None)", w is None)
except Exception as ex:  # noqa: BLE001
    ok("an unwritable alerts.log never raises (returns None)", False, repr(ex))
shutil.rmtree(d)

# ------------------------------------------------------------------------------------------------------------------ reviewer fixes: quiet-gap re-onset + locking
import fcntl  # noqa: E402
import threading  # noqa: E402

ca.QUIET_GAP_H = _QUIET_DEFAULT
d = mk()
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%"), D0)
for i in range(1, 9):   # every 15 min for 2 h: the condition holds -> REPEAT, silent
    ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%", now=D0 + i * 0.25 * H), D0 + i * 0.25 * H)
ok("QUIET: a condition sampled every 15 min stays silent (no regression of the fold)", len(alerts(d)) == 1, str(alerts(d)))
t = D0 + 2 * H + 13 * H     # silent for 13 h (> 12 h), still inside the 36 h onset gap, same local day boundary irrelevant
w = ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 23% (again)", now=t), t)
ok("QUIET: the condition went silent 13 h and came back inside 36 h -> a NEW onset line, level warn, original wording (was folded into the daily info line)",
   w is not None and "] warn | gpu-util | GPU busy only 23% (again)" in alerts(d)[-1] and len(alerts(d)) == 2, str(alerts(d)))
t2 = t + 11 * H             # a silence of 11 h (< 12 h) is NOT a clear
ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 22%", now=t2), t2)
ok("QUIET: an 11 h silence (under the 12 h gap) is still a repeat (nothing written, no onset)", len(alerts(d)) == 2, str(alerts(d)))
shutil.rmtree(d)
ca.QUIET_GAP_H = float(os.environ["OVN_CHRONIC_QUIET_H"])

# locking: the read-modify-write is serialized. A slow reader (the sleep in _load) makes the unlocked race deterministic: both threads read the empty state and both write an onset.
d = mk()
_orig_load = ca._load


def _slow_load(path):
    r = _orig_load(path)
    time.sleep(0.4)
    return r


ca._load = _slow_load
res = []
th = [threading.Thread(target=lambda: res.append(ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%"), D0))) for _ in range(2)]
t0 = time.time()
for x in th:
    x.start()
for x in th:
    x.join()
ca._load = _orig_load
ok("LOCK: two simultaneous first-sightings of one tag write exactly ONE onset line (a duplicate onset = the unlocked race)", len(alerts(d)) == 1 and sum(1 for r in res if r) == 1, str(alerts(d)) + str(res))
ok("LOCK: the lock file exists next to the state", os.path.exists(os.path.join(d, ca.LOCK_FILE)))
shutil.rmtree(d)

d = mk()
ca._load = _slow_load
th = [threading.Thread(target=lambda tg=tg: ca.note(d, tg, line(tg, "msg " + tg), D0)) for tg in ("gpu-util", "roadmap-floor:xlite", "roadmap-floor:iptv_apps")]
for x in th:
    x.start()
for x in th:
    x.join()
ca._load = _orig_load
st = json.load(open(os.path.join(d, ca.STATE_FILE)))
ok("LOCK: three different tags noted at once all survive in the state (an unlocked last-writer-wins would lose two)",
   sorted(st["active"]) == ["gpu-util", "roadmap-floor:iptv_apps", "roadmap-floor:xlite"] and sorted(st["reported"]) == sorted(st["active"]) and len(alerts(d)) == 3, str(st) + str(alerts(d)))
shutil.rmtree(d)

# fail-open: a lock that cannot be taken within LOCK_WAIT_S must not lose the alert
d = mk()
hold = os.open(os.path.join(d, ca.LOCK_FILE), os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(hold, fcntl.LOCK_EX)
_w0 = ca.LOCK_WAIT_S
ca.LOCK_WAIT_S = 0.3
t0 = time.time()
w = ca.note(d, "gpu-util", line("gpu-util", "GPU busy only 26%"), D0)
dt = time.time() - t0
ca.LOCK_WAIT_S = _w0
fcntl.flock(hold, fcntl.LOCK_UN)
os.close(hold)
ok("LOCK: a held lock times out (bounded wait) and the onset line is STILL written (fail-open)", w is not None and len(alerts(d)) == 1 and 0.25 <= dt < 5, "dt=%.2f %s" % (dt, alerts(d)))
shutil.rmtree(d)

# ------------------------------------------------------------------------------------------------------------------ integration: ovn_stats.py --gpu-alert
STATS = os.path.join(SCRIPTS, "ovn_stats.py")


def gpu_dir():
    d = mk()
    os.makedirs(os.path.join(d, "state"))
    tf = os.path.join(d, "tasks.json")
    json.dump([{"id": "ongoing-xlite", "enabled": True}], open(tf, "w"))
    now = time.time()
    open(os.path.join(d, "state", "gpu_util.log"), "w").write("".join("%d %d 1000\n" % (now - 3600 * 23 + i * 3500, 90 if i < 6 else 2) for i in range(23)))
    return d, {"OVN_STATE_DIR": os.path.join(d, "state"), "OVN_TASKS_FILE": tf}


def run_stats(env):
    e = {k: v for k, v in os.environ.items() if not k.startswith("OVN_CHRONIC")}
    e.update(env)
    return subprocess.run([sys.executable, STATS, "--gpu-alert"], capture_output=True, text=True, env=e, timeout=60)


def gpu_lines(d):
    return [ln for ln in alerts(os.path.join(d, "state")) if "gpu-util" in ln]


d, env = gpu_dir()
run_stats(env)
ok("ovn_stats --gpu-alert: first low-GPU sighting writes the original warn line", len(gpu_lines(d)) == 1 and "] warn | gpu-util | GPU busy only 26.1%" in gpu_lines(d)[0], str(alerts(os.path.join(d, "state"))))
for _ in range(5):
    run_stats(env)
ok("... 5 more runs write nothing (chronic repeat)", len(gpu_lines(d)) == 1)
ok("no legacy .gpu_util_alerted stamp in chronic mode (state is chronic_alerts.json)", not os.path.exists(os.path.join(d, "state", ".gpu_util_alerted")) and os.path.exists(os.path.join(d, "state", "chronic_alerts.json")))
shutil.rmtree(d)
d, env = gpu_dir()
env["OVN_CHRONIC_DAILY"] = "off"
run_stats(env)
run_stats(env)
ok("OVN_CHRONIC_DAILY=off: the legacy 6h-deduped line (one line for 2 runs) and the legacy stamp", len(gpu_lines(d)) == 1 and os.path.exists(os.path.join(d, "state", ".gpu_util_alerted")), str(gpu_lines(d)))
os.remove(os.path.join(d, "state", ".gpu_util_alerted"))
run_stats(env)
ok("OVN_CHRONIC_DAILY=off: after the stamp is gone the legacy path alerts again", len(gpu_lines(d)) == 2)
shutil.rmtree(d)
d, env = gpu_dir()
open(os.path.join(d, "state", "gpu_util.log"), "w").write("".join("%d 80 1000\n" % (time.time() - 3600 * 23 + i * 3500) for i in range(23)))
run_stats(env)
ok("BENIGN: a busy GPU writes nothing in chronic mode either", gpu_lines(d) == [] and not os.path.exists(os.path.join(d, "state", "chronic_alerts.json")))
shutil.rmtree(d)

# ------------------------------------------------------------------------------------------------------------------ integration: floor + gpu share ONE daily line
TC = os.path.join(SCRIPTS, "ovn_research_trigger_check.py")
d = mk()
os.makedirs(os.path.join(d, "overnight-queue", "logs"))
os.makedirs(os.path.join(d, "overnight-queue", "state"))
st = os.path.join(d, "overnight-queue", "state")
now = time.time()
with open(os.path.join(d, "overnight-queue", "logs", "ovn_planner.log"), "w") as f:
    t = 7.0
    while t >= 0:
        f.write("%s xlite: backlog low (0) but no [ready] roadmap feature (needs Claude research?)\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now - t * 3600)))
        t -= 0.5
e = {k: v for k, v in os.environ.items() if not k.startswith("OVN_")}
e["HOME"] = d
subprocess.run([sys.executable, TC, "2", os.path.join(d, "overnight-queue", "logs", "ovn_planner.log")], capture_output=True, text=True, env=e, timeout=60)
floor = [ln for ln in alerts(st) if "roadmap-feature floor" in ln]
ok("floor: first sighting writes the lane's ORIGINAL warn line (onset)", len(floor) == 1 and "] warn | ongoing-xlite | roadmap-feature floor: xlite has had backlog 0" in floor[0], str(alerts(st)))
for _ in range(3):
    subprocess.run([sys.executable, TC, "2", os.path.join(d, "overnight-queue", "logs", "ovn_planner.log")], capture_output=True, text=True, env=e, timeout=60)
ok("floor: repeats the same day write nothing more", len([ln for ln in alerts(st) if "roadmap-feature floor" in ln]) == 1)
cs = json.load(open(os.path.join(st, "chronic_alerts.json")))
ok("floor: the lane is tracked as roadmap-floor:xlite in the shared chronic state", "roadmap-floor:xlite" in cs["active"] and "roadmap-floor:xlite" in cs["reported"], str(cs))
shutil.rmtree(d)

print("\nchronic alert n2 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
