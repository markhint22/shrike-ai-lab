#!/usr/bin/env python3
"""Tests for scripts/ovn_supply_report.py + its feeds into ovn_notify.py (hourly update) and ovn_research_trigger_check.py (floor alert) - package supply-aware-alerting, 2026-10-18.

Incident behind it: the phone said "backlog is out for many repos" and nothing else. The causes were: 5 repos excluded from the Mac auto-research allowlist, iptv_apps/xlite auto-research passes
killed at the 1500 s timeout, an xlite reply with real features refused by the parser, every Qwen-explorer proposal rejected as `verify-dialect`, the explorer/auto-research daily caps, lens TTL
cooldowns. Covered here (hermetic temp dirs, synthetic state + the REAL log formats, no box, no network):
  * every cause class is detected from its real evidence line, in priority order, stale evidence is NOT a cause
  * depth (doable / pullable / [ready] / needs-research), burn (distinct items per 24 h), runway hours, last supply source with its time
  * the Mac export (`--export-ar`) parses the real run.log lines; a missing export is said, not guessed
  * hourly update: one line per starving repo (max OVN_SUPPLY_LINES_MAX, rest grouped by cause), 'Queue empty' bullet carries the cause, covered repos lose their 'Lane idle' line, OVN_SUPPLY_LINE=0
  * floor alert (ovn_research_trigger_check.py): the alerts.log warn carries ' | cause: ...'
  * cron entry point writes state/supply_report.json + one log line per starving repo; --dry-run writes nothing
  * MUTANTS: each substitution below must make at least one check fail (a check suite that passes on a mutant proves nothing)
Env SUPPLY_REPORT_PATH loads a different copy of the module (the mutant runner); the notify/trigger integrations see the same copy through sys.modules."""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SCRIPTS)
for k in ("OVN_SUPPLY_RUNWAY_H", "OVN_SUPPLY_FRESH_H", "OVN_AR_STATUS_MAX_H", "OVN_SUPPLY_LINE", "OVN_SUPPLY_LINES_MAX", "OVN_SUPPLY_BURN_H", "OVN_IDLE_LINE", "OVN_DUTY_LINE", "OVN_DIR", "OVN_NOTIFY_STATE"):
    os.environ.pop(k, None)
BASE = os.path.realpath(tempfile.mkdtemp(prefix="supply-report-"))
# 2026-10-18: every run (and every mutant child) leaked this dir: the suite's tmp-leak report counted 1118 entries here. Remove it on any exit (guarded: only our own prefixed dir).
import atexit, shutil  # noqa: E402
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("supply-report-") and os.path.dirname(BASE) == os.path.realpath(tempfile.gettempdir()) else None)
ROOT = os.path.join(BASE, "q")
STATE = os.path.join(ROOT, "state")
os.environ["OVN_DIR"] = ROOT
os.environ["OVN_NOTIFY_STATE"] = STATE
import ovn_notify as notify  # noqa: E402

NOW = float(time.mktime((2026, 10, 18, 16, 8, 0, 0, 0, -1)))
H = 3600.0
notify.now = lambda: NOW
SRC = os.environ.get("SUPPLY_REPORT_PATH") or os.path.join(SCRIPTS, "ovn_supply_report.py")
MUTANT_RUN = bool(os.environ.get("SUPPLY_REPORT_PATH"))


def load(path=None, text=None):
    spec = importlib.util.spec_from_file_location("ovn_supply_report", path or SRC)
    m = importlib.util.module_from_spec(spec)
    sys.modules["ovn_supply_report"] = m
    spec.loader.exec_module(m)
    return m


def stamp(ago_s, fmt="%Y-%m-%d %H:%M:%S"):
    return time.strftime(fmt, time.localtime(NOW - ago_s))


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


class Fx:
    """A throwaway queue root. repos: {name: dict(doable=N, ready=N, burn=N, pull_note=...)}."""

    def __init__(self, repos, ar=None, qwen=None, ws=None):
        import shutil
        shutil.rmtree(ROOT, ignore_errors=True) if os.path.realpath(ROOT).startswith(BASE + os.sep) else sys.exit("unsafe ROOT")
        self.repos = repos
        w(os.path.join(ROOT, "tasks.json"), json.dumps([{"repo": os.path.join(ROOT, "repos", r), "enabled": True} for r in repos]))
        rows = []
        for r, spec in repos.items():
            items = "\n".join("- [ ] [T2] item %s-%d (VERIFY: true)" % (r, i) for i in range(spec.get("doable", 0)))
            w(os.path.join(ROOT, "repos", r, "OVERNIGHT_PROGRESS.md"), "# progress\n" + items + "\n")
            w(os.path.join(ROOT, "backlog", r + ".md"), "# backlog\n")
            rm = "# roadmap\n" + "".join("- [ ] [P1] [ready] feature %d of %s\n" % (i, r) for i in range(spec.get("ready", 0)))
            rm += "".join("- [ ] [P2] [needs-research] idea %d\n" % i for i in range(spec.get("needs", 0)))
            if spec.get("ar_header"):
                rm += "\n## Auto-research %s (ovn_auto_research.sh; 3 item(s))\n" % spec["ar_header"]
            w(os.path.join(ROOT, "roadmap", r + ".md"), rm)
            for i in range(spec.get("burn", 0)):
                rows.append({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 600 - i * 60)), "repo": r, "id": "x%d" % i, "type": "aider_fix", "class": "landed",
                             "status": "ok", "duration_s": 30, "item_hash": "%s-h%d" % (r, i), "feat_tag": ""})
        rows.append({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 30 * H)), "repo": "zz", "id": "old", "class": "landed", "status": "ok", "duration_s": 5, "item_hash": "z", "feat_tag": ""})
        w(os.path.join(STATE, "outcomes.jsonl"), "\n".join(json.dumps(x) for x in rows) + "\n")
        if ar is not None:
            d = {"ts": NOW - 600, "repos": ar.get("repos", {}), "used_today": ar.get("used", 3), "cap": ar.get("cap", 8), "cap_ts": ar.get("cap_ts"), "allowlist": ar.get("allowlist", "iptv_apps xlite"),
                 "bridge_last_pass_ts": NOW - 2 * H}
            w(os.path.join(STATE, "auto_research_status.json"), json.dumps(d))
        w(os.path.join(ROOT, "logs", "qwen_explore.log"), "".join(qwen or []))
        w(os.path.join(ROOT, "logs", "work_supply.log"), "".join(ws or []))
        w(os.path.join(ROOT, "logs", "local_research.log"), "")


def qline(repo, ago_s, result="empty", proposed=0, accepted=0, rejected="-", note=""):
    return "%s %s lens=bug-hunt result=%s files=4 proposed=%d accepted=%d rejected={%s} calls=2 tok=1/1 13s%s\n" % (stamp(ago_s), repo, result, proposed, accepted, rejected, (" note=" + note) if note else "")


def ar_ev(state, ago_s, detail="", acc_ago=None, acc_n=None):
    d = {"last_event_ts": NOW - ago_s, "state": state, "detail": detail}
    if acc_ago is not None:
        d["last_accept_ts"], d["last_accept_n"] = NOW - acc_ago, acc_n
    return d


def rep_for(sr, **kw):
    return sr.collect(now=NOW, root=ROOT, state=STATE, **kw)


def checks(sr):
    out = []

    def chk(name, cond, extra=""):
        out.append((name, bool(cond), extra))

    # --- cause classes -------------------------------------------------------------------------------------------------------------------------------------------------------------
    Fx({"billwatch": {"burn": 6}}, ar={"repos": {"billwatch": ar_ev("excluded", 600, "allowlist OVN_AR_REPOS=iptv_apps xlite", 30 * H, 3)}})
    r = rep_for(sr)["repos"]["billwatch"]
    chk("excluded: class", r["cause_class"] == "excluded", r["causes"])
    chk("excluded: line names the allowlist", "lane excluded" in r["line"] and "OVN_AR_REPOS=iptv_apps xlite" in r["line"], r["line"])
    chk("starving + runway 0 when nothing pullable", r["starving"] and r["runway_h"] == 0.0 and r["pullable"] == 0)

    Fx({"gitlark": {"burn": 3}}, ar={"repos": {"gitlark": ar_ev("timeout", 1800, "claude rc=124 (timeout)")}})
    r = rep_for(sr)["repos"]["gitlark"]
    chk("timeout: class + rc in text", r["cause_class"] == "timeout" and "rc=124" in r["line"], r["causes"])

    Fx({"xlite": {"burn": 3}}, ar={"repos": {"xlite": ar_ev("parser-reject", 1200, "reply had no feature lines")}})
    r = rep_for(sr)["repos"]["xlite"]
    chk("parser-reject: class", r["cause_class"] == "parser-reject" and "rejected by the parser" in r["line"], r["causes"])

    Fx({"shrike-notify": {"burn": 2}}, ar={"repos": {}}, qwen=[qline("shrike-notify", 900, "empty", 4, 0, "verify-dialect:4")])
    r = rep_for(sr)["repos"]["shrike-notify"]
    chk("explorer-rejected: class, count and reason", r["cause_class"] == "explorer-rejected" and "rejected 4" in r["line"] and "verify-dialect:4" in r["line"], r["line"])

    Fx({"a": {}}, ar={"repos": {}, "used": 8, "cap": 8, "cap_ts": NOW - 300})
    r = rep_for(sr)["repos"]["a"]
    chk("cap: auto-research daily cap", r["cause_class"] == "cap" and "8/8" in r["line"], r["causes"])
    Fx({"a": {}}, ar={"repos": {}}, qwen=[qline("a", 400, "skip-cap", note="24 passes today")])
    r = rep_for(sr)["repos"]["a"]
    chk("cap: explorer skip-cap", r["cause_class"] == "cap" and "explorer daily cap" in r["line"] and "24 passes" in r["line"], r["causes"])

    Fx({"a": {}}, ar={"repos": {}}, qwen=[qline("a", 400, "skip-lens-ttl", note="all lenses covered within 4h")])
    r = rep_for(sr)["repos"]["a"]
    chk("cooldown: explorer lens TTL", r["cause_class"] == "cooldown" and "lens TTL" in r["line"], r["causes"])

    Fx({"a": {}}, ar={"repos": {"a": ar_ev("started", 120, "pass started")}})
    r = rep_for(sr)["repos"]["a"]
    chk("in-progress: a pass started 2 min ago", r["cause_class"] == "in-progress", r["causes"])
    Fx({"a": {}}, ar={"repos": {"a": ar_ev("started", 3 * H, "pass started")}})
    r = rep_for(sr)["repos"]["a"]
    chk("started 3h ago with no outcome = timeout", r["cause_class"] == "timeout" and "never ended" in r["line"], r["causes"])

    Fx({"a": {}}, ar={"repos": {"a": ar_ev("excluded", 600, "allowlist")}}, qwen=[qline("a", 900, "empty", 1, 0, "verify-dialect:1")])
    r = rep_for(sr)["repos"]["a"]
    chk("priority: excluded before explorer-rejected, line shows both", [c["class"] for c in r["causes"][:2]] == ["excluded", "explorer-rejected"] and r["line"].index("excluded") < r["line"].index("explorer rejected"), r["causes"])

    Fx({"a": {}}, ar={"repos": {"a": ar_ev("excluded", 10 * H, "allowlist")}})
    r = rep_for(sr)["repos"]["a"]
    chk("stale evidence (10h > 6h) is not a cause", r["cause_class"] != "excluded", r["causes"])

    Fx({"a": {}}, ar=None)
    rp = rep_for(sr)
    r = rp["repos"]["a"]
    chk("no Mac export: said, not guessed", rp["ar_status"] is None and r["sources"]["auto-research"]["state"] == "no-status" and "Mac export missing" in r["line"], r["line"])

    # --- depth, burn, runway ---------------------------------------------------------------------------------------------------------------------------------------------------------
    Fx({"a": {"doable": 12, "burn": 12, "ready": 2, "needs": 3}, "b": {"doable": 5, "burn": 48}, "c": {"doable": 4, "burn": 0}}, ar={"repos": {}})
    rp = rep_for(sr)["repos"]
    chk("depth: doable/pullable/ready/needs", rp["a"]["doable"] == 12 and rp["a"]["pullable"] == 12 and rp["a"]["ready"] == 2 and rp["a"]["needs_research"] == 3, rp["a"])
    chk("burn: distinct items per 24h", rp["a"]["burn_per_day"] == 12.0 and rp["b"]["burn_per_day"] == 48.0, rp["a"]["burn_per_day"])
    chk("runway = pullable / (burn/24): 12 at 12/d = 24h, not starving", rp["a"]["runway_h"] == 24.0 and not rp["a"]["starving"], rp["a"])
    chk("runway 2.5h at 48/d < floor 6h = starving", rp["b"]["runway_h"] == 2.5 and rp["b"]["starving"] and rp["b"]["line"], rp["b"])
    chk("no burn -> runway unknown, a stocked repo is not starving", rp["c"]["runway_h"] is None and not rp["c"]["starving"], rp["c"])
    chk("healthy repo has no line", rp["a"]["line"] is None)

    # --- last supply source --------------------------------------------------------------------------------------------------------------------------------------------------------
    Fx({"a": {"burn": 2}}, ar={"repos": {"a": ar_ev("accepted", 30 * H, "n=3 of 3", 30 * H, 3)}}, qwen=[qline("a", 5 * H, "ok", 3, 2, "-"), qline("a", 3600, "empty", 0, 0, "-")])
    r = rep_for(sr)["repos"]["a"]
    chk("last source = the newest producer (explorer 5h beats auto-research 30h)", r["last_source"]["name"] == "qwen-explore" and "last supply qwen-explore 5h ago (+2)" in r["line"], r["line"])
    Fx({"a": {"burn": 2}}, ar={"repos": {}})
    r = rep_for(sr)["repos"]["a"]
    chk("no producer on record is said", r["last_source"] is None and "last supply: none on record" in r["line"], r["line"])
    Fx({"a": {"burn": 2, "ar_header": stamp(40 * H, "%Y-%m-%d")}}, ar={"repos": {}})
    r = rep_for(sr)["repos"]["a"]
    chk("auto-research roadmap header date is evidence when the Mac is silent", r["last_source"] and r["last_source"]["name"] == "auto-research", r["last_source"])
    Fx({"a": {"burn": 2}}, ar={"repos": {}}, ws=["a: ADDED 3 deterministic item(s) to backlog (4 specs, dropped none)\n"])
    w(os.path.join(STATE, "work_supply_last_a"), str(NOW - 2 * H))
    r = rep_for(sr)["repos"]["a"]
    chk("work supply: ADDED n>0 dated by its last pass", r["last_source"] and r["last_source"]["name"] == "work-supply" and r["last_source"]["n"] == 3, r["last_source"])

    # --- parsers on the real line formats ---------------------------------------------------------------------------------------------------------------------------------------
    log = "\n".join([
        stamp(3000) + " excluded billwatch: not in the research lane allowlist (OVN_AR_REPOS=iptv_apps xlite)",
        stamp(2900) + " candidate order (roundrobin): iptv_apps[accepted48h=4 starving=3.3h]",
        stamp(2800) + " iptv_apps: starting research pass (model=sonnet budget=$4)",
        stamp(1300) + " iptv_apps: claude exited rc=124: ==> /var/x <==",
        stamp(1200) + " xlite: starting research pass (model=sonnet budget=$4)",
        stamp(200) + " xlite: reply had no feature lines and no NONE - treating as a FAILED pass, no cooldown set (see x): - **[needs-research",
        stamp(100) + " test-automation-agent: accepted 5/6",
        stamp(90) + " test-automation-agent: APPENDED 5 [ready] feature(s) to box roadmap and pushed",
        stamp(80) + " run complete: 1 repo(s) researched, 6/8 today",
        stamp(70) + " daily cap reached (8/8) - skip", ""])
    p = sr.parse_ar_log(log)
    rs = p["repos"]
    chk("run.log: excluded + allowlist", rs["billwatch"]["state"] == "excluded" and p["allowlist"] == "iptv_apps xlite", rs.get("billwatch"))
    chk("run.log: rc=124 timeout", rs["iptv_apps"]["state"] == "timeout" and "rc=124" in rs["iptv_apps"]["detail"], rs.get("iptv_apps"))
    chk("run.log: parser reject", rs["xlite"]["state"] == "parser-reject", rs.get("xlite"))
    chk("run.log: accepted n kept as last_accept", rs["test-automation-agent"].get("last_accept_n") == 5, rs.get("test-automation-agent"))
    chk("run.log: cap 8/8", p["cap"] == 8 and p["used_today"] == 8 and p["cap_ts"], p)
    d = os.path.join(BASE, "ar")
    w(os.path.join(d, "run.log"), log)
    w(os.path.join(BASE, "bridge.log"), stamp(500) + " claude_queue_bridge pass complete\n")
    cp = subprocess.run([sys.executable, SRC, "--export-ar", "--ar-dir", d, "--bridge-log", os.path.join(BASE, "bridge.log"), "--now", str(NOW)], capture_output=True, text=True, timeout=60, env=dict(os.environ, PYTHONPATH=SCRIPTS))
    try:
        ex = json.loads(cp.stdout)
    except ValueError:
        ex = {}
    chk("--export-ar prints the status JSON incl. the bridge pass", ex.get("repos", {}).get("xlite", {}).get("state") == "parser-reject" and abs(ex.get("bridge_last_pass_ts", 0) - (NOW - 500)) < 2 and ex.get("ts") == NOW, cp.stdout[:200] + cp.stderr[:200])

    # --- digest grouping + hourly update ---------------------------------------------------------------------------------------------------------------------------------------------
    names = ["r1", "r2", "r3", "r4", "r5"]
    Fx({n: {"burn": 2} for n in names}, ar={"repos": {n: ar_ev("excluded", 600, "allowlist OVN_AR_REPOS=iptv_apps xlite") for n in names[:3]}})
    rp = rep_for(sr)
    dl = sr.digest_lines(rp)
    chk("digest: 5 starving -> 3 lines, last one grouped by cause", len(dl) == 3 and dl[2].startswith("+3 more starving:") and "excluded (r3" in dl[2], dl)
    os.environ["OVN_SUPPLY_LINES_MAX"] = "10"
    chk("digest: OVN_SUPPLY_LINES_MAX=10 -> one line per starving repo", len(sr.digest_lines(rp)) == 5)
    os.environ.pop("OVN_SUPPLY_LINES_MAX")

    Fx({"billwatch": {"burn": 0}, "gitlark": {"doable": 30, "burn": 2}}, ar={"repos": {"billwatch": ar_ev("excluded", 600, "allowlist OVN_AR_REPOS=iptv_apps xlite")}})
    w(os.path.join(STATE, "outcomes.jsonl"), open(os.path.join(STATE, "outcomes.jsonl")).read() + json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 4 * H)), "repo": "billwatch", "class": "landed", "status": "ok", "duration_s": 5, "item_hash": "q", "feat_tag": ""}) + "\n")
    title, body, _n = notify.compose_update(at=NOW)
    chk("hourly: starving repo gets its supply line", re.search(r"^billwatch: pullable 0, ready 0, burn \d+/d, runway 0h; .*cause: lane excluded", body, re.M), body)
    chk("hourly: stocked repo gets none", not re.search(r"^gitlark: pullable", body, re.M), body)
    chk("hourly: 'Queue empty' bullet carries the cause class", "Queue empty: billwatch" in body and "no supply - excluded: billwatch" in body, body)
    chk("hourly: covered repo's Lane idle line is dropped", not re.search(r"Lane idle \S+: billwatch", body), body)
    os.environ["OVN_SUPPLY_LINE"] = "0"
    _t, body0, _n = notify.compose_update(at=NOW)
    chk("hourly: OVN_SUPPLY_LINE=0 removes the lines (and restores the Lane idle line)", not re.search(r"^billwatch: pullable", body0, re.M) and re.search(r"Lane idle \S+: billwatch", body0) is not None, body0)
    os.environ.pop("OVN_SUPPLY_LINE")

    # --- cron entry point ----------------------------------------------------------------------------------------------------------------------------------------------------------------
    Fx({"billwatch": {"burn": 2}, "gitlark": {"burn": 2}}, ar={"repos": {}})
    env = dict(os.environ, OVN_DIR=ROOT, OVN_NOTIFY_STATE=STATE, PYTHONPATH=SCRIPTS)   # a mutant copy lives outside scripts/: its siblings are found through PYTHONPATH
    cp = subprocess.run([sys.executable, SRC, "--now", str(NOW)], capture_output=True, text=True, env=env, timeout=60)
    lg = open(os.path.join(ROOT, "logs", "supply_report.log")).read().splitlines() if os.path.exists(os.path.join(ROOT, "logs", "supply_report.log")) else []
    jd = json.load(open(os.path.join(STATE, "supply_report.json"))) if os.path.exists(os.path.join(STATE, "supply_report.json")) else {}
    chk("cron run: rc 0, state json, one log line per starving repo", cp.returncode == 0 and len(lg) == 2 and set(jd.get("repos", {})) == {"billwatch", "gitlark"} and cp.stdout.count("pullable") == 2, cp.stdout + cp.stderr)
    os.remove(os.path.join(STATE, "supply_report.json"))
    os.remove(os.path.join(ROOT, "logs", "supply_report.log"))
    subprocess.run([sys.executable, SRC, "--dry-run", "--now", str(NOW)], capture_output=True, text=True, env=env, timeout=60)
    chk("--dry-run writes nothing", not os.path.exists(os.path.join(STATE, "supply_report.json")) and not os.path.exists(os.path.join(ROOT, "logs", "supply_report.log")))
    rep_old = {"ts": NOW - 3 * H, "repos": {}}
    w(os.path.join(STATE, "supply_report.json"), json.dumps(rep_old))
    chk("fresh_report: a 3h-old file is not used", sr.fresh_report(NOW, STATE) is None)
    rep_new = {"ts": NOW - 600, "repos": {}}
    w(os.path.join(STATE, "supply_report.json"), json.dumps(rep_new))
    chk("fresh_report: a 10-min-old file is", sr.fresh_report(NOW, STATE) == rep_new)

    # --- floor alert in ovn_research_trigger_check.py (throwaway HOME) -------------------------------------------------------------------------------------------------------------------
    hm = tempfile.mkdtemp(prefix="floor-", dir=BASE)
    q = os.path.join(hm, "overnight-queue")
    os.makedirs(os.path.join(q, "logs"))
    os.makedirs(os.path.join(q, "state"))
    for sub in ("repos/xlite", "backlog", "roadmap"):
        os.makedirs(os.path.join(q, sub), exist_ok=True)
    w(os.path.join(q, "repos", "xlite", "OVERNIGHT_PROGRESS.md"), "# p\n")
    w(os.path.join(q, "backlog", "xlite.md"), "# b\n")
    w(os.path.join(q, "roadmap", "xlite.md"), "# r\n")
    w(os.path.join(q, "tasks.json"), json.dumps([{"repo": os.path.join(q, "repos", "xlite"), "enabled": True}]))
    w(os.path.join(q, "state", "auto_research_status.json"), json.dumps({"ts": time.time(), "repos": {"xlite": {"state": "excluded", "last_event_ts": time.time() - 600, "detail": "allowlist OVN_AR_REPOS=iptv_apps"}}, "allowlist": "iptv_apps"}))
    t0 = time.time()
    rows, t = [], 7.0
    while t >= 0:
        rows.append("%s xlite: backlog low (0) but no [ready] roadmap feature (needs Claude research?)\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t0 - t * 3600)))
        t -= 0.5
    w(os.path.join(q, "logs", "ovn_planner.log"), "".join(rows))
    trig_dir = os.environ.get("OVN_TEST_TRIGGER_DIR") or SCRIPTS
    e2 = {k: v for k, v in os.environ.items() if not k.startswith("OVN_")}
    e2["HOME"] = hm
    subprocess.run([sys.executable, os.path.join(trig_dir, "ovn_research_trigger_check.py"), "2", os.path.join(q, "logs", "ovn_planner.log")], capture_output=True, text=True, env=e2, timeout=90)
    ap = os.path.join(q, "state", "alerts.log")
    al = [x for x in open(ap).read().splitlines() if "roadmap-feature floor" in x] if os.path.exists(ap) else []
    chk("floor alert: one line and it carries ' | cause: lane excluded ...'", len(al) == 1 and " | cause: lane excluded from auto-research" in al[0], al)
    # --- the .sh half: logs one supply line per newly starving repo ----------------------------------------------------------------------------------------------------------------------
    sh_log = os.path.join(q, "logs", "ovn_research_trigger_check.log")
    if os.path.lexists(os.path.join(q, "scripts")):
        os.remove(os.path.join(q, "scripts"))
    os.symlink(trig_dir, os.path.join(q, "scripts"))
    for fn in os.listdir(os.path.join(q, "state")):
        if fn.startswith("research_trigger_alerted_"):
            os.remove(os.path.join(q, "state", fn))
    cp = subprocess.run(["bash", os.path.join(trig_dir, "ovn_research_trigger_check.sh")], capture_output=True, text=True, env=dict(e2, PATH=os.environ.get("PATH", "")), timeout=120)
    lg = open(sh_log).read() if os.path.exists(sh_log) else ""
    chk("trigger .sh logs 'supply: xlite: ... cause: lane excluded' for the newly starving repo", re.search(r"supply: xlite: pullable 0, .*cause: lane excluded", lg) is not None, lg[-600:] + cp.stderr[-300:])
    return out


def run():
    sr = load()
    res = checks(sr)
    return res


if __name__ == "__main__":
    if MUTANT_RUN:
        res = run()
        for n, ok_, extra in res:
            print(("  ok   " if ok_ else "  FAIL ") + n)
        sys.exit(0 if all(o for _, o, _ in res) else 1)
    P = F = 0
    res = run()
    for n, ok_, extra in res:
        if ok_:
            P += 1
            print("  ok   " + n)
        else:
            F += 1
            print("  FAIL %s :: %s" % (n, str(extra)[:400]))
    # ---- mutants: each must be caught ----
    src = open(SRC).read()
    TRIGGER_MUTANTS = {"floor alert suffix dropped": "ovn_research_trigger_check.py", "trigger .sh supply lines off": "ovn_research_trigger_check.sh"}
    mutants = [
        ("cause order: explorer-rejected ahead of excluded", 'CAUSE_ORDER = ("excluded", "timeout", "parser-reject", "explorer-rejected"', 'CAUSE_ORDER = ("explorer-rejected", "excluded", "timeout", "parser-reject"'),
        ("excluded detection removed", 'if ar["state"] == "excluded" and recent(ar["last_event_ts"]):', 'if False:'),
        ("stale evidence counted (fresh window ignored)", "recent = lambda ts: ts is not None and now - ts <= fresh", "recent = lambda ts: ts is not None"),
        ("runway ignores burn", "runway = pull / (burn_day / 24.0)", "runway = float(pull)"),
        ("runway floor ignored (only pullable 0 starves)", "starving = pull == 0 or (runway is not None and runway < runway_floor)", "starving = pull == 0"),
        ("pullable 0 gives no runway", "elif pull == 0:\n            runway = 0.0", "elif pull == 0:\n            runway = None"),
        ("burn counts rows not distinct items", "burn_day = None if items24 is None else (items24 * 24.0 / covered if 0 < covered < 24 else float(items24))", "burn_day = None if items24 is None else 0.0"),
        ("last source picks the oldest producer", "if ts and (best is None or ts > best[1]):", "if ts and (best is None or ts < best[1]):"),
        ("explorer rejection not detected", 'if q["state"] == "rejected" and recent(q.get("last_run_ts")):', "if False:"),
        ("explorer skip-cap not a cap cause", 'if q.get("skip") == "skip-cap" and recent(q.get("last_event_ts")):', "if False:"),
        ("rc=124 timeout state not parsed", 'ev(repo, ts, "timeout", "claude rc=%s%s"', 'ev(repo, ts, "other", "claude rc=%s%s"'),
        ("digest never groups", "if len(st) <= mx:", "if True:"),
        ("missing Mac export guessed as ok", 's["auto-research"] = _src("no-status", detail="no status (Mac export missing)", last_produced_ts=rm_ts)', 's["auto-research"] = _src("none", detail="", last_produced_ts=rm_ts)'),
        ("floor alert suffix dropped", 'return " | cause: " + t if t else ""', 'return ""'),
        ("trigger .sh supply lines off", 'if [ "${OVN_SUPPLY_LINE:-1}" != "0" ]; then', 'if [ "0" != "0" ]; then'),
        ("ready count wrong selector", r'READY_RE = re.compile(r"^- \[ \] \[P[1-4]\] \[ready\]", re.M)', r'READY_RE = re.compile(r"^- \[ \] \[P[1-4]\] \[nope\]", re.M)'),
    ]
    for name, old, new in mutants:
        tfile = None
        if name in TRIGGER_MUTANTS:
            tfile = TRIGGER_MUTANTS[name]
        if tfile is None and old not in src:
            F += 1
            print("  FAIL mutant '%s' does not apply (source drifted)" % name)
            continue
        if tfile:
            tsrc = open(os.path.join(SCRIPTS, tfile)).read()
            if old not in tsrc:
                F += 1
                print("  FAIL mutant '%s' does not apply to %s" % (name, tfile))
                continue
            md = os.path.join(BASE, "mutscripts_%d" % abs(hash(name)))
            os.makedirs(md)
            for fn in os.listdir(SCRIPTS):
                if fn.endswith(".py") or fn.endswith(".sh"):
                    os.symlink(os.path.join(SCRIPTS, fn), os.path.join(md, fn))
            os.remove(os.path.join(md, tfile))
            open(os.path.join(md, tfile), "w").write(tsrc.replace(old, new, 1))
            env = dict(os.environ, SUPPLY_REPORT_PATH=SRC, OVN_TEST_TRIGGER_DIR=md)
            env.pop("OVN_DIR", None)
        else:
            mp = os.path.join(BASE, "mut_%d.py" % abs(hash(name)))
            open(mp, "w").write(src.replace(old, new, 1))
            env = dict(os.environ, SUPPLY_REPORT_PATH=mp)
        cp = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True, env=env, timeout=600)
        if cp.returncode != 0 and "FAIL" in cp.stdout:
            P += 1
            print("  ok   mutant caught: %s (%s)" % (name, re.search(r"FAIL (.*)", cp.stdout).group(1)[:70]))
        else:
            F += 1
            print("  FAIL mutant SURVIVED: %s" % name)
    print("test_ovn_supply_report: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
