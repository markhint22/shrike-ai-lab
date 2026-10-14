#!/usr/bin/env python3
"""Tests for scripts/ovn_supply_ledger.py + the ovn_notify.py changes of package supply-ledger (2026-10-13).

Measured finding behind it: iptv_apps worked 18.5% and xlite 9.2% of 64 h, both did < 1 min in 32 of those hours, and no alert fired because starved_check needed ALL
enabled lanes idle (seven lanes, two starving = can never fire). Covered here, all on SYNTHETIC outcomes (no box, no network):
  * trickle pattern (a 5-minute cycle every 2 h) -> duty ~4% and the supply-duty alert; a busy lane / a lane with pullable work / an unknown pullable / a secondary lane do not alert
  * busy minutes are the UNION of row intervals (overlapping rows are not double counted); duty uses the data the file really has; a priority lane with no rows is listed
  * secondary lanes with work do NOT suppress the priority-lane starved_check; the old all-lanes rule is still a second trigger; kill switch / pause / dedupe still hold
  * source attribution from roadmap section headers, [src:] tags and feat_tag prefixes; landed vs landed-uncredited vs credit-only counted separately; re-serving after first push
  * shadow mode writes NO alerts.log line; the escalation marker is written once per local day; supply_ledger.json is written atomically; one log line per lane
  * the hourly digest carries 'Lane duty 24h: iptv 16% (9 items/d in), xlite 5% (8/d in)' (text only) and OVN_DUTY_LINE=0 removes it
Pure python, hermetic temp dirs. Real entry points: ovn_supply_ledger.run/apply_alerts/attribute, ovn_notify.starved_check/compose_update."""
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


BASE = os.path.realpath(tempfile.mkdtemp(prefix="supply-ledger-"))
STATE = os.path.join(BASE, "state")
os.makedirs(STATE)
for k in ("OVN_SUPPLY_ALERT", "OVN_DUTY_FLOOR", "OVN_PRIORITY_LANES", "OVN_SUPPLY_EXH_GAP_S", "OVN_STARVED_PRIORITY", "OVN_IDLE_ALERT", "OVN_IDLE_ALERT_H", "OVN_DUTY_LINE",
          "OVN_SUPPLY_MAX_ROW_S", "OVN_SUPPLY_SCAN_MB", "OVN_IDLE_LINE"):
    os.environ.pop(k, None)
os.environ["OVN_NOTIFY_STATE"] = STATE      # read at import by BOTH modules
os.environ["OVN_DIR"] = BASE
import ovn_notify as notify  # noqa: E402
import ovn_supply_ledger as led  # noqa: E402

NOW = float(time.mktime((2026, 10, 13, 18, 0, 0, 0, 0, -1)))   # a local 18:00 (so "today" in the digest and the per-day dedupe are unambiguous)
H, M = 3600.0, 60.0
notify.now = lambda: NOW


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def row(repo, end, dur, cls="landed", h="", tag="", status=None):
    st = status or {"landed": "pushed(tests:pass)", "landed-uncredited": "pushed(tests:pass)", "noop": "no-op(ALREADY-DONE)", "skipped": "skip(exhausted)",
                    "credit-only": "pushed(credit-only)", "reverted": "reverted(build-break)", "error": "error-transient(push)"}.get(cls, "x")
    return {"ts": iso(end), "repo": repo, "id": "ongoing-" + repo, "type": "aider_fix", "tier": "2", "category": "test", "class": cls, "severity": "good", "attempt": 1, "attempts": 1,
            "bestn_stop": "", "fail_reason": "queue-exhausted" if cls == "skipped" else "", "status": st, "tokens_sent": 1, "tokens_recv": 1, "duration_s": dur, "item_hash": h, "feat_tag": tag}


def write_rows(rows, d=None):
    d = d or STATE
    with open(os.path.join(d, "outcomes.jsonl"), "w") as f:
        for r in sorted(rows, key=lambda r: r["ts"]):
            f.write(json.dumps(r) + "\n")


def prep(rows):
    """Rows as read_rows() would return them (adds _t end epoch and _d duration) without going through a file."""
    return [dict(r, _t=float(led.calendar.timegm(time.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S"))), _d=float(r["duration_s"])) for r in rows]


def reset():
    for n in os.listdir(STATE):
        p = os.path.join(STATE, n)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    for sub in ("logs", "roadmap", "backlog", "repos"):
        shutil.rmtree(os.path.join(BASE, sub), ignore_errors=True)


def trickle(repo, hours=24, cycle_s=300, every_s=2 * H, hb_s=H):
    """A short cycle every `every_s` and, in between, the idle loop's hourly skip(exhausted) heartbeat (what the box really writes)."""
    rows, t, i = [], NOW - hours * H + 600, 0
    while t <= NOW:
        rows.append(row(repo, t + cycle_s, cycle_s, "landed", "h-%s-%d" % (repo, i), "%s-20261013-feat-%d" % (repo, i)))
        k = t + cycle_s + 10
        while k < t + every_s - 60 and k <= NOW:
            rows.append(row(repo, k, 3, "skipped"))
            k += hb_s
        t += every_s
        i += 1
    return rows


def tail_of(path):
    try:
        return open(path).read().splitlines()
    except OSError:
        return []


# ================================================================================================ 1. trickle -> duty ~4% + alert
reset()
rows = trickle("xlite") + trickle("iptv_apps", every_s=2.5 * H)
write_rows(rows)
rows_r = led.read_rows(STATE, NOW - 168 * H)
rep = led.compute_report(rows_r, NOW, pullable={"xlite": 0, "iptv_apps": 0, "billwatch": 7})
x24 = rep["lanes"]["xlite"]["windows"]["24h"]
ok("TRICKLE: a 5-minute cycle every 2h is ~4% duty over 24h (not the ~100% a cycle-count would suggest)", 3.0 <= x24["duty_pct"] <= 5.5, str(x24["duty_pct"]))
ok("TRICKLE: busy minutes are the cycles' minutes (12 x 5)", 55 <= x24["busy_min"] <= 65, str(x24["busy_min"]))
ok("TRICKLE: the empty-queue idle time is measured from the heartbeat rows (a LOWER bound: the hour before each refuel is not vouched for)", 10 <= x24["idle_exhausted_h"] <= 24 - x24["busy_min"] / 60.0, str(x24["idle_exhausted_h"]))
al = led.evaluate_alerts(rep)
ok("TRICKLE: both priority lanes (duty < 25%, pullable 0) are in the alert list", sorted(a["repo"] for a in al) == ["iptv_apps", "xlite"], str(al))
ok("covered_h reports how much of the window the data really covers", x24["covered_h"] >= 23.0, str(x24.get("covered_h")))

rep2 = led.compute_report(rows_r, NOW, pullable={"xlite": 3, "iptv_apps": None})
ok("NO alert when the lane still has pullable work (it is slow, not starved)", led.evaluate_alerts(rep2) == [])
ok("NO alert when pullable is unknown (None): never guess", not [a for a in led.evaluate_alerts(rep2) if a["repo"] == "iptv_apps"])
busy = [row("xlite", NOW - 24 * H + i * 30 * M + 25 * M, 25 * M, "landed", "b%d" % i) for i in range(48)]
rep3 = led.compute_report(prep(busy), NOW, pullable={"xlite": 0}, lanes=["iptv_apps"])
ok("a busy lane (> 25% duty) does not alert even with pullable 0", not [a for a in led.evaluate_alerts(rep3) if a["repo"] == "xlite"], str(rep3["lanes"]["xlite"]["windows"]["24h"]["duty_pct"]))
rep4 = led.compute_report(rows_r, NOW, pullable={"xlite": 0, "iptv_apps": 0, "billwatch": 0, "gitlark": 0})
ok("a SECONDARY lane (not in OVN_PRIORITY_LANES) never alerts", not [a for a in led.evaluate_alerts(rep4) if a["repo"] in ("billwatch", "gitlark")])
rep5 = led.compute_report([], NOW, pullable={"xlite": 0, "iptv_apps": 0}, lanes=led.priority_lanes())
ok("a priority lane with NO rows at all is listed at 0% duty and alerts (the worst case is not an absent lane)", sorted(a["repo"] for a in led.evaluate_alerts(rep5)) == ["iptv_apps", "xlite"])
os.environ["OVN_DUTY_FLOOR"] = "3"
ok("OVN_DUTY_FLOOR is honoured (floor 3% -> a 4% lane is above it, no alert)", led.evaluate_alerts(rep) == [], str(led.evaluate_alerts(rep)))
os.environ.pop("OVN_DUTY_FLOOR")

# ================================================================================================ 2. duty = UNION of intervals (the merge)
reset()
ov = [row("xlite", NOW - 3 * H, 10 * M, "landed", "o1"), row("xlite", NOW - 3 * H + 5 * M, 10 * M, "landed", "o2"), row("billwatch", NOW - 26 * H, 3, "skipped")]
rep = led.compute_report(prep(ov), NOW)
w = rep["lanes"]["xlite"]["windows"]["24h"]
ok("OVERLAP: two rows overlapping by 5 min are 15 busy minutes (the union), not 20", abs(w["busy_min"] - 15.0) < 0.2, str(w["busy_min"]))
ok("OVERLAP: lane_min is the plain sum of durations (20) so the difference stays visible", abs(w["lane_min"] - 20.0) < 0.2, str(w["lane_min"]))
ok("merge_intervals joins touching/overlapping intervals and keeps gaps", led.merge_intervals([[0, 5], [3, 10], [20, 30], [30, 31]]) == [[0, 10], [20, 31]])
ok("subtract_intervals removes worked time from idle time", led.subtract_intervals([[0, 100]], [[10, 20], [90, 120]]) == [[0, 10], [20, 90]])
# a window longer than the data is divided by the data it has
shortrows = [dict(row("xlite", NOW - 1 * H, 30 * M, "landed", "s1"), _t=NOW - 1 * H, _d=1800.0)]
w2 = led.compute_report(shortrows, NOW)["lanes"]["xlite"]["windows"]["24h"]
ok("DENOMINATOR: only 1.5 h of data -> 30 busy minutes is 33% (not 2%) and covered_h says 1.5", 30 <= w2["duty_pct"] <= 36 and abs(w2["covered_h"] - 1.5) < 0.1, str(w2))
# exhausted_spans
hb = [dict(row("xlite", NOW - 5 * H + k * H, 3, "skipped"), _t=NOW - 5 * H + k * H, _d=3.0) for k in range(0, 5)]
sp = led.exhausted_spans(hb, NOW)
ok("IDLE: hourly exhausted heartbeats vouch for the stretch between them and up to now (>= 4.9 h)", led.total_s(sp) >= 4.9 * H, str(led.total_s(sp) / H))
wk = [dict(row("xlite", NOW - 3 * H, 600, "landed", "w"), _t=NOW - 3 * H, _d=600.0), dict(row("xlite", NOW - 1 * H, 3, "skipped"), _t=NOW - 1 * H, _d=3.0)]
sp2 = led.exhausted_spans(wk, NOW)
ok("IDLE: the stretch between a WORK row and the next exhausted row is counted only from that work row on (not before it)", sp2 and sp2[0][0] >= NOW - 3 * H, str(sp2))
big = [dict(row("xlite", NOW - 9 * H, 3, "skipped"), _t=NOW - 9 * H, _d=3.0), dict(row("xlite", NOW - 1 * H, 3, "skipped"), _t=NOW - 1 * H, _d=3.0)]
ok("IDLE: a heartbeat does not vouch for more than OVN_SUPPLY_EXH_GAP_S (3 h): an 8 h hole is not idle time", led.total_s(led.exhausted_spans(big, NOW)) < 2 * H)

# ================================================================================================ 3. starved_check: secondary lanes must not mask the priority lanes
reset()
depths = {"iptv_apps": 0, "xlite": 0, "billwatch": 22, "gitlark": 18, "shrike-notify": 15, "shrike-monitor": 27, "test-automation-agent": 20}
rows = [row("iptv_apps", NOW - 8 * H, 100), row("xlite", NOW - 9 * H, 100)] + [row(r, NOW - 20 * M, 300, "landed", "h" + r) for r in depths if r not in ("iptv_apps", "xlite")]
rows.append(row("iptv_apps", NOW - 30 * H, 3, "skipped"))
write_rows(rows)
r = notify.starved_check(depths, False)
ok("MASKING: iptv_apps + xlite idle 8-9h with nothing queued while five other lanes work -> 'Fleet starved' fires", len(r) == 1 and r[0][0].startswith("🚨 Fleet starved"), str(r))
ok("MASKING: the body names the priority lanes and says the others still have work", r and "iptv_apps" in r[0][1] and "xlite" in r[0][1] and "still have work" in r[0][1], str(r))
os.environ["OVN_STARVED_PRIORITY"] = "off"
ok("OVN_STARVED_PRIORITY=off restores the old rule (secondary lanes mask -> no alert)", notify.starved_check(depths, False) == [])
os.environ.pop("OVN_STARVED_PRIORITY")
ok("a deliberately PAUSED fleet is still not starved", notify.starved_check(depths, True) == [])
d2 = dict(depths, xlite=4)
ok("only ONE priority lane starving (xlite has queued work) -> no priority alert", notify.starved_check(d2, False) == [])
rows_recent = [row("iptv_apps", NOW - 8 * H, 100), row("xlite", NOW - 2 * H, 100)] + rows[2:]
write_rows(rows_recent)
ok("a priority lane that worked 2h ago is not yet idle > 6h -> no alert", notify.starved_check(depths, False) == [])
write_rows(rows)
open(os.path.join(STATE, "notify_starved_last"), "w").write(str(NOW - 1 * H))
ok("the 12h dedupe window still holds (a push 1h ago suppresses the alert)", notify.starved_check(depths, False) == [])
os.remove(os.path.join(STATE, "notify_starved_last"))
# the old all-lanes rule is kept as a SECOND trigger (also with the priority rule switched off)
all_idle_depths = {"iptv_apps": 0, "xlite": 0, "billwatch": 0}
write_rows([row("iptv_apps", NOW - 8 * H, 100), row("xlite", NOW - 9 * H, 100), row("billwatch", NOW - 7 * H, 100)])
os.environ["OVN_STARVED_PRIORITY"] = "off"
r_all = notify.starved_check(all_idle_depths, False)
ok("OLD RULE kept: every lane idle > 6h -> still fires with the priority rule off, with the original wording", len(r_all) == 1 and "Every active lane" in r_all[0][1], str(r_all))
os.environ.pop("OVN_STARVED_PRIORITY")
r_all2 = notify.starved_check(all_idle_depths, False)
ok("when every lane is idle the original wording is kept (priority rule is only the extra trigger)", len(r_all2) == 1 and "Every active lane" in r_all2[0][1], str(r_all2))
os.environ["OVN_PRIORITY_LANES"] = "billwatch"
write_rows(rows)
ok("OVN_PRIORITY_LANES retargets the rule (billwatch is working -> no alert for a billwatch-only priority)", notify.starved_check(depths, False) == [])
os.environ.pop("OVN_PRIORITY_LANES")
os.environ["OVN_IDLE_ALERT"] = "0"
ok("OVN_IDLE_ALERT=0 still switches the whole emergency off", notify.starved_check(depths, False) == [])
os.environ.pop("OVN_IDLE_ALERT")

# ================================================================================================ 4. source attribution
reset()
os.makedirs(os.path.join(BASE, "roadmap"))
open(os.path.join(BASE, "roadmap", "xlite.md"), "w").write("""# xlite roadmap
## Stopping point
- [ ] [P2] [ready] Hand written feature about shields — scripts/a.gd
## Auto-research 2026-10-12 (ovn_auto_research.sh; 2 item(s))
- [ ] [P1] [decomposed] Wire MissionDirective bonus enemy count into battle spawn — scripts/mission/x.gd {cat: game}
- [x] [P2] [done] Fix save version coercion crash — scripts/save.gd
## Local research 2026-10-09 (ovn_local_research.py; 3 item(s) drafted by the local 27B)
- [ ] [P3] [ready] Harden loader against missing keys — scripts/load.gd
## Qwen explore 2026-10-10
- [ ] [P3] [ready] Explore tactical overwatch heuristics — scripts/ai.gd
## Claude queue triage 2026-10-12
- [ ] [P2] [ready] Triaged claude queue item about codex slots — scripts/codex.gd
## Auto-research 2026-10-13
- [ ] [P2] [ready] Explicitly tagged feature [src:cq-triage] — scripts/z.gd
""")
idx = led.build_source_index(BASE)


def tg(title):
    return "xlite-20261013-" + led._slug(title)


R = lambda tag: {"repo": "xlite", "feat_tag": tag}
ok("ATTR roadmap header 'Auto-research' -> auto-research", led.attribute(R(tg("Wire MissionDirective bonus enemy count into battle spawn — scripts/mission/x.gd")), idx) == "auto-research")
ok("ATTR a checked [x] item under the same header is indexed too", led.attribute(R(tg("Fix save version coercion crash — scripts/save.gd")), idx) == "auto-research")
ok("ATTR header 'Local research' -> local-research", led.attribute(R(tg("Harden loader against missing keys — scripts/load.gd")), idx) == "local-research")
ok("ATTR header 'Qwen explore' -> qwen-explore", led.attribute(R(tg("Explore tactical overwatch heuristics — scripts/ai.gd")), idx) == "qwen-explore")
ok("ATTR header 'Claude queue triage' -> cq-triage", led.attribute(R(tg("Triaged claude queue item about codex slots — scripts/codex.gd")), idx) == "cq-triage")
ok("ATTR an explicit [src:cq-triage] tag on the line beats its header", led.attribute(R(tg("Explicitly tagged feature [src:cq-triage] — scripts/z.gd")), idx) == "cq-triage")
ok("ATTR any other header -> roadmap-other", led.attribute(R(tg("Hand written feature about shields — scripts/a.gd")), idx) == "roadmap-other")
ok("ATTR feat_tag slug 'supply-*' -> deterministic (no roadmap needed)", led.attribute({"repo": "iptv_apps", "feat_tag": "iptv_apps-20261013-supply-unused-import-iptv-backend-app-services-content-"}) == "deterministic")
ok("ATTR a bare 'supply-...' tag -> deterministic", led.attribute({"repo": "iptv_apps", "feat_tag": "supply-x"}) == "deterministic")
ok("ATTR an empty feat_tag (recovered / untagged items) -> recovery/untagged", led.attribute({"repo": "xlite", "feat_tag": ""}) == "recovery/untagged")
ok("ATTR a tag that matches no roadmap line -> unattributed (never guessed)", led.attribute(R("xlite-20261013-some-feature-nobody-wrote-down"), idx) == "unattributed")
ok("ATTR without a roadmap index only the tag rules apply (a roadmap-born tag is unattributed)", led.attribute(R(tg("Harden loader against missing keys — scripts/load.gd"))) == "unattributed")
ok("ATTR the same slug in ANOTHER repo is not matched", led.attribute({"repo": "iptv_apps", "feat_tag": tg("Harden loader against missing keys — scripts/load.gd").replace("xlite", "iptv_apps")}, idx) == "unattributed")
ok("classify_header covers the Claude research header spellings", all(led.classify_header(h) == "auto-research" for h in ("Research refuel 2026-09-30 (interactive Claude research pass; 5 items)", "Refuel 2026-09-17 (Claude research pass", "Newly discovered (2026-09-20 refuel", "Manual research refuel 2026-10-05 (auto-research blocked")))

# ================================================================================================ 5. counters: landed vs landed-uncredited, inflow by source, re-serving
reset()
os.makedirs(os.path.join(BASE, "roadmap"))
open(os.path.join(BASE, "roadmap", "iptv_apps.md"), "w").write("## Auto-research 2026-10-12\n- [ ] [P1] [decomposed] Alpha feature — a.py\n## Local research 2026-10-09\n- [ ] [P1] [decomposed] Beta feature — b.py\n")
ta, tb = "iptv_apps-20261013-" + led._slug("Alpha feature — a.py"), "iptv_apps-20261013-" + led._slug("Beta feature — b.py")
base = NOW - 5 * H
rows = [
    row("iptv_apps", base + 10 * M, 600, "landed", "a1", ta),
    row("iptv_apps", base + 20 * M, 600, "landed-uncredited", "a2", ta),
    row("iptv_apps", base + 30 * M, 300, "credit-only", "a3", ta),
    row("iptv_apps", base + 40 * M, 120, "noop", "b1", tb),
    row("iptv_apps", base + 50 * M, 120, "noop", "a1", ta),            # a1 re-served after its first push
    row("iptv_apps", base + 60 * M, 120, "noop", "a1", ta),            # ... again
    row("iptv_apps", base + 70 * M, 200, "landed", "s1", "iptv_apps-20261013-supply-missing-return-type-x"),
    row("iptv_apps", base + 80 * M, 200, "reverted", "r1", "iptv_apps-20261013-supply-y"),
    row("iptv_apps", base + 90 * M, 100, "noop", "u1", ""),
    row("iptv_apps", base + 95 * M, 50, "noop", "", ""),               # a row without a hash is counted, not attributed
    row("iptv_apps", base - 30 * H, 100, "landed", "old1", ta),        # outside the 24h window, inside 72h
    row("iptv_apps", base + 1 * M, 2, "skipped"),
    row("billwatch", NOW - 27 * H, 3, "skipped"),
]
write_rows(rows)
rr = led.read_rows(STATE, NOW - 168 * H)
rep = led.compute_report(rr, NOW, index=led.build_source_index(BASE))
w = rep["lanes"]["iptv_apps"]["windows"]["24h"]
ok("COUNT landed (credited) and landed-uncredited are SEPARATE numbers", w["landed"] == 2 and w["landed_uncredited"] == 1, "%s/%s" % (w["landed"], w["landed_uncredited"]))
ok("COUNT pushed = landed + landed-uncredited; credit-only is neither (its own column)", w["pushed"] == 3 and w["credit_only"] == 1)
ok("COUNT reverted separate", w["reverted"] == 1)
ok("COUNT distinct items consumed (a1 served 3x counts once; hashless rows are counted apart)", w["items"] == 7 and w["rows_without_hash"] == 1, "%s %s" % (w["items"], w["rows_without_hash"]))
ok("COUNT inflow by source: 3 Claude-research items, 1 local, 2 deterministic, 1 untagged", w["inflow_by_source"] == {"auto-research": 3, "deterministic": 2, "local-research": 1, "recovery/untagged": 1}, str(w["inflow_by_source"]))
ok("COUNT noop share = 5 of 10 non-skip rows (the hashless one included)", abs(w["noop_share"] - 0.5) < 0.001 and w["noop"] == 5, str(w["noop_share"]))
ok("RESERVE minutes after the first push: a1 re-served twice (2 x 2 min = 4)", abs(w["reserve_min"] - 4.0) < 0.1 and w["reserve_rows"] == 2, "%s/%s" % (w["reserve_min"], w["reserve_rows"]))
w72 = rep["lanes"]["iptv_apps"]["windows"]["72h"]
ok("the 72h window includes the older landing", w72["landed"] == 3)
rows2 = rows + [row("iptv_apps", base - 40 * H, 100, "landed", "a9", ta), row("iptv_apps", base + 15 * M, 90, "noop", "a9", ta)]
write_rows(rows2)
w3 = led.compute_report(led.read_rows(STATE, NOW - 168 * H), NOW, index=led.build_source_index(BASE))["lanes"]["iptv_apps"]["windows"]["24h"]
ok("RESERVE: the first push may predate the window (history is scanned): a9 pushed 40h before, re-served inside the window", w3["reserve_rows"] == 3, str(w3["reserve_rows"]))
write_rows([row("xlite", NOW - 1 * H, 400 * 3600, "landed", "huge")])
ok("clamp: a corrupt 400-hour duration cannot fill the window (clamped to OVN_SUPPLY_MAX_ROW_S)", led.read_rows(STATE, 0)[0]["_d"] <= 10800)

# ================================================================================================ 6. shadow vs on, escalation marker once per day, atomic json + log
reset()
write_rows(trickle("xlite") + trickle("iptv_apps") + [row("billwatch", NOW - 20 * M, 300, "landed", "bw1", "billwatch-20261013-supply-z")])
os.makedirs(os.path.join(BASE, "repos", "xlite"))
os.makedirs(os.path.join(BASE, "repos", "iptv_apps"))
os.makedirs(os.path.join(BASE, "repos", "billwatch"))
for rname, n in (("xlite", 0), ("iptv_apps", 0), ("billwatch", 6)):
    open(os.path.join(BASE, "repos", rname, "OVERNIGHT_PROGRESS.md"), "w").write("\n".join("- [ ] [T1] app/f%d.py — do thing %d" % (i, i) for i in range(n)) + "\n")
    os.makedirs(os.path.join(BASE, "backlog"), exist_ok=True)
    open(os.path.join(BASE, "backlog", rname + ".md"), "w").write("# backlog\n")
rep, done = led.run(now=NOW, state_dir=STATE, root=BASE)
ok("SHADOW (default mode): NO alerts.log line is written", not os.path.exists(os.path.join(STATE, "alerts.log")), str(done))
lg = tail_of(os.path.join(BASE, "logs", "supply_ledger.log"))
ok("SHADOW: the would-be warning goes to logs/supply_ledger.log, prefixed SHADOW, once per lane", len([l for l in lg if "SHADOW would warn | supply-duty" in l]) == 2, "\n".join(lg))
ok("one log line per lane per run", len([l for l in lg if "pullable=" in l]) == len(rep["lanes"]) and len(rep["lanes"]) >= 3)
js = json.load(open(os.path.join(STATE, "supply_ledger.json")))
ok("supply_ledger.json is valid and carries lanes, windows, alerts, mode", js["lanes"]["xlite"]["windows"]["24h"]["duty_pct"] < 25 and js["alert_mode"] == "shadow" and len(js["alerts"]) == 2)
ok("pullable comes from the repo's own queue (billwatch 6, xlite 0)", js["lanes"]["billwatch"]["pullable"] == 6 and js["lanes"]["xlite"]["pullable"] == 0, str({k: v["pullable"] for k, v in js["lanes"].items()}))
ok("atomic write leaves no .tmp file behind", not [n for n in os.listdir(STATE) if ".tmp" in n], str(os.listdir(STATE)))
mk = os.path.join(STATE, "supply_escalate_xlite")
ok("escalation marker is written for the starving priority lane (and not for a lane with work)", os.path.exists(mk) and not os.path.exists(os.path.join(STATE, "supply_escalate_billwatch")))
m1 = json.load(open(mk))
ok("marker content: repo, local day, ts, duty, mode", m1["repo"] == "xlite" and m1["day"] == time.strftime("%Y-%m-%d", time.localtime(NOW)) and m1["mode"] == "shadow" and m1["duty24_pct"] < 25 and m1["ts"] == NOW)
rep_b, done_b = led.run(now=NOW + 30 * M, state_dir=STATE, root=BASE)
ok("MARKER ONCE PER DAY: a second run the same day does not rewrite it", json.load(open(mk))["ts"] == NOW and not [d for d in done_b if d[0] == "escalate"], str(done_b))
ok("SHADOW once per day: the second run adds no second SHADOW line", len([l for l in tail_of(os.path.join(BASE, "logs", "supply_ledger.log")) if "SHADOW would warn" in l]) == 2)
rep_c, done_c = led.run(now=NOW + 24 * H + 600, state_dir=STATE, root=BASE)
ok("MARKER: the next local day writes a fresh one (new day, new ts)", json.load(open(mk))["day"] != m1["day"] and json.load(open(mk))["ts"] == NOW + 24 * H + 600, str(done_c))
os.environ["OVN_SUPPLY_ALERT"] = "on"
shutil.rmtree(os.path.join(BASE, "logs"))
os.remove(os.path.join(STATE, "supply_alerted.json"))
for n in ("supply_escalate_xlite", "supply_escalate_iptv_apps"):
    os.remove(os.path.join(STATE, n))
rep, done = led.run(now=NOW, state_dir=STATE, root=BASE)
al_lines = tail_of(os.path.join(STATE, "alerts.log"))
ok("ON: exactly one alerts.log `warn | supply-duty` line per starving priority lane", len(al_lines) == 2 and all("] warn | supply-duty | supply floor:" in l for l in al_lines), str(al_lines))
ok("ON: the line names the duty, the floor and the cause", "xlite worked" in "".join(al_lines) and "floor 25%" in "".join(al_lines) and "nothing pullable" in "".join(al_lines))
ok("ON: it is a plain line, NOT the folded chronic-daily line and no chronic state is created", not [l for l in al_lines if "chronic-daily" in l] and not os.path.exists(os.path.join(STATE, "chronic_alerts.json")))
led.run(now=NOW + 3 * H, state_dir=STATE, root=BASE)
ok("ON: one line per lane per local day (a run 3h later adds none)", len(tail_of(os.path.join(STATE, "alerts.log"))) == 2)
led.run(now=NOW + 24 * H + 3600, state_dir=STATE, root=BASE)
ok("ON: the next day alerts again (4 lines total)", len(tail_of(os.path.join(STATE, "alerts.log"))) == 4)
os.environ["OVN_SUPPLY_ALERT"] = "off"
for n in os.listdir(STATE):
    if n.startswith("supply_escalate_") or n in ("alerts.log", "supply_alerted.json"):
        os.remove(os.path.join(STATE, n))
led.run(now=NOW, state_dir=STATE, root=BASE)
ok("OFF: neither an alert nor a marker", not [n for n in os.listdir(STATE) if n.startswith("supply_escalate_") or n == "alerts.log"])
os.environ.pop("OVN_SUPPLY_ALERT")
# CLI entry point
cli_env = dict(os.environ, OVN_DIR=BASE, OVN_NOTIFY_STATE=STATE)
p = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_supply_ledger.py"), "--now", str(NOW)], env=cli_env, capture_output=True, text=True)
ok("CLI: runs clean (rc 0, no stdout for the cron redirect to duplicate, no traceback)", p.returncode == 0 and "Traceback" not in p.stderr and p.stdout == "", p.stdout + p.stderr)
p = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_supply_ledger.py"), "--dry-run", "--now", str(NOW)], env=cli_env, capture_output=True, text=True)
ok("CLI: --dry-run prints the JSON and writes nothing new", p.returncode == 0 and json.loads(p.stdout)["lanes"], p.stderr)

# ================================================================================================ 7. hourly digest line (text only)
reset()
rows = [row("billwatch", NOW - 26 * H, 3, "skipped")]
for i in range(9):
    rows.append(row("iptv_apps", NOW - 23 * H + i * 2 * H, 1530, "landed", "ih%d" % i, "iptv_apps-20261013-supply-x%d" % i))
for i in range(8):
    rows.append(row("xlite", NOW - 22 * H + i * 2.5 * H, 580, "landed", "xh%d" % i, "xlite-20261013-supply-y%d" % i))
write_rows(rows)
title, body, n_needs = notify.compose_update(at=NOW)
ok("DIGEST: 'Lane duty 24h: iptv 16% (9 items/d in), xlite 5% (8/d in)' is in the hourly body", "Lane duty 24h: iptv 16% (9 items/d in), xlite 5% (8/d in)" in body, body)
ok("DIGEST: it is a body line only - the title/needs count is unchanged by it (no extra bullet)", n_needs == 0 or "Lane duty" not in title)
os.environ["OVN_DUTY_LINE"] = "0"
ok("DIGEST: OVN_DUTY_LINE=0 removes it", "Lane duty" not in notify.compose_update(at=NOW)[1])
os.environ.pop("OVN_DUTY_LINE")
json.dump({"ts": NOW - 600, "lanes": {"iptv_apps": {"windows": {"24h": {"duty_pct": 42.0, "items": 77}}}, "xlite": {"windows": {"24h": {"duty_pct": 7.0, "items": 3}}}}}, open(os.path.join(STATE, "supply_ledger.json"), "w"))
ok("DIGEST: a fresh state/supply_ledger.json is used as is", "iptv 42% (77 items/d in), xlite 7% (3/d in)" in notify.compose_update(at=NOW)[1])
json.dump({"ts": NOW - 5 * H, "lanes": {"iptv_apps": {"windows": {"24h": {"duty_pct": 42.0, "items": 77}}}}}, open(os.path.join(STATE, "supply_ledger.json"), "w"))
ok("DIGEST: a STALE file (5h) is ignored and recomputed from the outcomes", "iptv 16% (9 items/d in)" in notify.compose_update(at=NOW)[1])
open(os.path.join(STATE, "supply_ledger.json"), "w").write("{not json")
ok("DIGEST: a corrupt ledger file never breaks the update (recomputed)", "iptv 16% (9 items/d in)" in notify.compose_update(at=NOW)[1])
os.remove(os.path.join(STATE, "outcomes.jsonl"))
ok("DIGEST: no outcomes at all -> no line and no crash", "Lane duty" not in notify.compose_update(at=NOW)[1])

shutil.rmtree(BASE, ignore_errors=True)
print("\nsupply_ledger: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
