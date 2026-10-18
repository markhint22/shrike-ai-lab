#!/usr/bin/env python3
"""ovn_supply_report.py - per-repo WORK-SUPPLY report with a ROOT CAUSE when a repo runs dry (2026-10-18, package supply-aware-alerting). Read-only, no model calls.

Why: on 2026-10-18 ~16:00 the phone got "backlog is out for many repos" and nothing else. The facts that explained it were all on disk but in six places: the Mac auto-research run.log
(billwatch/monitor/TAA/gitlark/notify "excluded ... not in the research lane allowlist"; iptv_apps + xlite hit claude rc=124; an xlite reply with real features rejected by the parser),
the box Qwen explorer log (every proposal rejected as `verify-dialect`, then `skip-lens-ttl`), the work-supply / local-research logs (only two lanes), the planner log, outcomes.jsonl
(the 27B burns ~100 items/day) and the roadmap ([ready] depth). This module joins them: ONE line per starving repo that says how deep the supply is, how fast it is burned, how many hours
of runway are left, which source last produced items, and WHY nothing is being produced now.

Per repo (record keys): doable (OVERNIGHT_PROGRESS open items), pullable (what the fleet can take next, ovn_supply_ledger.current_pullable), ready ([ready] roadmap features),
needs_research, burn_per_day (DISTINCT items attempted in 24 h, ovn_supply_ledger window), runway_h (pullable / burn per hour; 0 when nothing is pullable; None when nothing burns),
sources{auto-research, qwen-explore, work-supply, local-research, claude-queue-bridge} each with last_produced_ts (+ n), last_event_ts, state, detail, last_consumed_ts (an outcomes row whose
item came from that source, ovn_supply_ledger.attribute), `last_source`, `causes` (ordered) and `cause_class` (primary).

Cause classes, in priority order (primary first; the line shows the first two):
  excluded        lane is not in the Mac auto-research allowlist (run.log "excluded <repo>: ... (OVN_AR_REPOS=...)" is that repo's newest event)
  timeout         last auto-research pass ended `claude exited rc=N` (rc=124 = the 1500 s timeout)
  parser-reject   last pass reply was refused by the validator ("reply had no feature lines and no NONE")
  explorer-rejected  last Qwen explorer run proposed items and all were rejected (e.g. 4x verify-dialect)
  explorer-error  last Qwen explorer run ended result=error
  cap             auto-research daily cap used up (run.log "daily cap reached" / "N/8 today") or the explorer's own daily pass cap (result=skip-cap)
  in-progress     an auto-research pass was started recently and has not ended yet (supply is on its way)
  cooldown        the producers are all in cooldown (explorer lens TTL, auto-research / local-research cooldown)
  idle-lane       a producer has no lane / no pass for this repo at all (work supply and local research only run for the lanes cron names)
  ar-unknown      no Mac auto-research status file at all (the producer of [ready] features cannot be seen from the box)
  no-evidence     nothing above applies and nothing recorded a pass: supply is silent
Sources are only named when the evidence says so; the Mac auto-research and the bridge log are not visible from the box, so the Mac exports them with `--export-ar` (JSON) into
state/auto_research_status.json (see cron proposal below). Without that file the report says `auto-research: no status (Mac export missing/stale)` instead of guessing.

Outputs: state/supply_report.json (atomic), one line per starving repo to logs/supply_report.log (rotated at 1 MB) and stdout. A repo is STARVING when pullable == 0 or its runway is below
OVN_SUPPLY_RUNWAY_H (default 6). It never pushes anything itself: ovn_notify.py update (hourly) and ovn_research_trigger_check.{sh,py} read it (no new alerter).

usage:  ovn_supply_report.py [--print] [--json] [--dry-run] [--now EPOCH] [--repos a,b]
        ovn_supply_report.py --export-ar [--ar-dir DIR] [--bridge-log PATH]     # run ON THE MAC: prints the auto-research status JSON for the box
cron (proposed, NOT installed):
  box:  */30 * * * * cd ~/overnight-queue && python3 scripts/ovn_supply_report.py >> logs/supply_report.cron.log 2>&1
  Mac:  17 * * * * python3 $HOME/LocalProjects/shared/scripts/overnight-queue/scripts/ovn_supply_report.py --export-ar | ssh mhintermeister@100.79.64.64 'cat > overnight-queue/state/.ar_status.tmp && mv overnight-queue/state/.ar_status.tmp overnight-queue/state/auto_research_status.json'
env:    OVN_DIR / OVN_NOTIFY_STATE (queue root / state dir), OVN_SUPPLY_RUNWAY_H (6), OVN_SUPPLY_FRESH_H (6: how recent an event must be to be called a cause), OVN_AR_STATUS_MAX_H (4: Mac export older than this = stale),
        OVN_SUPPLY_LINE=0 (hourly update without the supply lines), OVN_SUPPLY_LINES_MAX (3 lines in the hourly update; the rest are grouped), OVN_SUPPLY_BURN_H (24: burn window)
"""
import calendar
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

ROOT = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
STATE = os.environ.get("OVN_NOTIFY_STATE") or os.path.join(ROOT, "state")
SOURCES = ("auto-research", "qwen-explore", "work-supply", "local-research", "claude-queue-bridge")
CAUSE_ORDER = ("excluded", "timeout", "parser-reject", "explorer-rejected", "explorer-error", "cap", "in-progress", "cooldown", "idle-lane", "ar-unknown", "no-evidence")
READY_RE = re.compile(r"^- \[ \] \[P[1-4]\] \[ready\]", re.M)           # same selector as ovn_planner.sh
NEEDS_RE = re.compile(r"^- \[ \] \[P[1-4]\] \[needs-research\]", re.M)
AR_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (.*)$")
QX_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (\S+) lens=(\S+) result=(\S+) .*?proposed=(\d+) accepted=(\d+) rejected=\{([^}]*)\}(.*)$")
HDR_AR = re.compile(r"^## (?:Auto-research|Research refuel|Refuel)\s+(\d{4})-(\d\d)-(\d\d)", re.M | re.I)


def _envf(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def _read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def _epoch(s):
    """Local-time 'YYYY-MM-DD HH:MM:SS' -> epoch (the box and the Mac both log local time)."""
    try:
        return float(time.mktime(time.strptime(s[:19], "%Y-%m-%d %H:%M:%S")))
    except (ValueError, OverflowError):
        return None


def ago(ts, now):
    if not ts:
        return "never"
    s = max(0.0, now - ts)
    if s < 5400:
        return "%dm ago" % max(1, int(s // 60))
    if s < 48 * 3600:
        return "%dh ago" % int(s // 3600)
    return "%dd ago" % int(s // 86400)


# ----------------------------------------------------------------------------------------------------------- Mac auto-research export
def parse_ar_log(text, now=None):
    """run.log text -> {"repos": {repo: {...}}, "used_today", "cap", "cap_ts", "allowlist", "ts"}. Per repo the NEWEST event decides `state`; the newest productive pass is kept apart.
    state: excluded | timeout | parser-reject | accepted | zero | cooldown | ready-skip | started | other.  rc != 0 other than 124 is also `timeout` (detail carries the rc)."""
    repos, out = {}, {"used_today": None, "cap": None, "cap_ts": None, "allowlist": None, "last_ts": None}

    def ev(repo, ts, state, detail):
        r = repos.setdefault(repo, {})
        r.update(last_event_ts=ts, state=state, detail=detail[:160])
        if state in ("accepted", "appended") and detail.startswith("n="):
            n = int(detail[2:].split()[0])
            if n > 0:
                r["last_accept_ts"], r["last_accept_n"] = ts, n

    for line in text.split("\n"):
        m = AR_LINE.match(line.rstrip())
        if not m:
            continue
        ts, msg = _epoch(m.group(1)), m.group(2)
        if ts is None:
            continue
        out["last_ts"] = ts
        x = re.match(r"excluded (\S+): not in the research lane allowlist \(OVN_AR_REPOS=([^)]*)\)", msg)
        if x:
            ev(x.group(1), ts, "excluded", "allowlist OVN_AR_REPOS=" + x.group(2))
            out["allowlist"] = x.group(2)
            continue
        x = re.match(r"run complete: .*?(\d+)/(\d+) today", msg)
        if x:
            out["used_today"], out["cap"] = int(x.group(1)), int(x.group(2))
            continue
        x = re.match(r"daily cap reached \((\d+)/(\d+)\)", msg)
        if x:
            out["used_today"], out["cap"], out["cap_ts"] = int(x.group(1)), int(x.group(2)), ts
            continue
        x = re.match(r"(\S+): (.*)$", msg)
        if not x:
            continue
        repo, rest = x.group(1), x.group(2)
        if repo in ("candidate", "run", "another", "stale", "lock", "ESCALATE", "no", "ssh/starving.json"):
            continue
        if rest.startswith("starting research pass"):
            ev(repo, ts, "started", "pass started")
        elif re.match(r"claude exited rc=(\d+)", rest):
            rc = re.match(r"claude exited rc=(\d+)", rest).group(1)
            ev(repo, ts, "timeout", "claude rc=%s%s" % (rc, " (timeout)" if rc == "124" else ""))
        elif rest.startswith("reply had no feature lines"):
            ev(repo, ts, "parser-reject", "reply had no feature lines and no NONE (validator refused it)")
        elif re.match(r"accepted (\d+)/(\d+)", rest):
            a = re.match(r"accepted (\d+)/(\d+)", rest)
            ev(repo, ts, "accepted", "n=%s of %s" % (a.group(1), a.group(2)))
        elif re.match(r"APPENDED (\d+) ", rest):
            ev(repo, ts, "appended", "n=%s" % re.match(r"APPENDED (\d+) ", rest).group(1))
        elif rest.startswith("0 accepted"):
            ev(repo, ts, "zero", "0 accepted")
        elif rest.startswith("in cooldown"):
            ev(repo, ts, "cooldown", rest)
        elif re.match(r"already has \d+ \[ready\]", rest):
            ev(repo, ts, "ready-skip", rest)
    out["repos"] = repos
    return out


def parse_bridge_log(text):
    """/tmp/claude_queue_bridge.log -> epoch of the last 'pass complete' line (None when absent)."""
    last = None
    for line in text.split("\n"):
        m = AR_LINE.match(line)
        if m and "pass complete" in m.group(2):
            last = _epoch(m.group(1)) or last
    return last


def export_ar(ar_dir=None, bridge_log=None, now=None):
    """The JSON the Mac writes into the box's state/auto_research_status.json."""
    now = float(now if now is not None else time.time())
    ar_dir = ar_dir or os.path.expanduser("~/.ovn_auto_research")
    parsed = parse_ar_log(_read(os.path.join(ar_dir, "run.log")), now)
    parsed["ts"] = now
    parsed["bridge_last_pass_ts"] = parse_bridge_log(_read(bridge_log or "/tmp/claude_queue_bridge.log"))
    return parsed


def load_ar_status(state_dir, now):
    """(status dict | None, stale bool). None when the file is missing/unreadable."""
    try:
        with open(os.path.join(state_dir, "auto_research_status.json")) as f:
            d = json.load(f)
        if not isinstance(d, dict):
            return None, False
        return d, (now - float(d.get("ts") or 0)) > _envf("OVN_AR_STATUS_MAX_H", 4) * 3600
    except (OSError, ValueError, TypeError):
        return None, False


# ----------------------------------------------------------------------------------------------------------- box logs
def parse_qwen_log(text):
    """logs/qwen_explore.log -> {repo: {last_ts, result, lens, proposed, accepted, rejected{reason:n}, note, last_ok_ts, last_ok_n}}."""
    out = {}
    for line in text.split("\n"):
        m = QX_LINE.match(line.rstrip())
        if not m:
            continue
        ts, repo, lens, res, prop, acc, rej, tail = _epoch(m.group(1)), m.group(2), m.group(3), m.group(4), int(m.group(5)), int(m.group(6)), m.group(7), m.group(8)
        if ts is None:
            continue
        rejected = {}
        for part in rej.split(","):
            k, _, v = part.strip().partition(":")
            if k and k != "-" and v.strip().isdigit():
                rejected[k] = int(v)
        nm = re.search(r"note=(.*)$", tail)
        tail = nm.group(1).strip() if nm else ""
        r = out.setdefault(repo, {})
        # a skip row (lens TTL / cooldown) is newer evidence about WHY nothing runs, but must not hide the last REAL run's rejection: keep both
        if res.startswith("skip"):
            r.update(skip_ts=ts, skip_result=res, skip_note=tail)
        else:
            r.update(last_ts=ts, result=res, lens=lens, proposed=prop, accepted=acc, rejected=rejected, note=tail)
        if acc > 0:
            r["last_ok_ts"], r["last_ok_n"] = ts, acc
    return out


def last_repo_lines(text, repos):
    """{repo: newest line of a '<repo>: ...' log without timestamps (work_supply.log, local_research.log)}."""
    out = {}
    for line in text.split("\n"):
        m = re.match(r"^(\S+): (.*)$", line)
        if m and m.group(1) in repos:
            out[m.group(1)] = m.group(2)
    return out


def ar_header_date(roadmap_text):
    """Newest '## Auto-research|Research refuel|Refuel YYYY-MM-DD' header -> epoch of that local day's end (the best a header can say), or None."""
    best = None
    for y, mo, d in HDR_AR.findall(roadmap_text):
        t = _epoch("%s-%s-%s 23:59:59" % (y, mo, d))
        if t and (best is None or t > best):
            best = t
    return best


# ----------------------------------------------------------------------------------------------------------- per-repo evidence
def _src(state, **kw):
    d = {"state": state, "last_produced_ts": None, "last_produced_n": None, "last_event_ts": None, "last_consumed_ts": None, "detail": ""}
    d.update(kw)
    return d


def source_records(repo, now, ctx):
    """One record per source (see SOURCES) from the evidence in ctx (pre-parsed logs/state)."""
    fresh = _envf("OVN_SUPPLY_FRESH_H", 6) * 3600
    s = {}
    # ---- auto-research (Mac) ----
    ar, stale = ctx.get("ar"), ctx.get("ar_stale")
    rm_ts = ar_header_date(ctx["roadmap"].get(repo, ""))
    if ar is None:
        s["auto-research"] = _src("no-status", detail="no status (Mac export missing)", last_produced_ts=rm_ts)
    else:
        r = (ar.get("repos") or {}).get(repo) or {}
        st = r.get("state") or "none"
        cap_hit = ar.get("cap") is not None and ar.get("used_today") is not None and ar["used_today"] >= ar["cap"] and (ar.get("cap_ts") or 0) >= now - fresh
        rec = _src(st, last_event_ts=r.get("last_event_ts"), detail=r.get("detail", ""), last_produced_ts=r.get("last_accept_ts") or rm_ts, last_produced_n=r.get("last_accept_n"))
        rec["cap_hit"] = bool(cap_hit)
        rec["cap"] = (ar.get("used_today"), ar.get("cap"))
        rec["allowlist"] = ar.get("allowlist")
        rec["stale"] = bool(stale)
        s["auto-research"] = rec
    # ---- qwen explorer (box) ----
    q = ctx["qwen"].get(repo)
    if q is None:
        s["qwen-explore"] = _src("none", detail="no explorer run recorded")
    else:
        st = "ok" if q.get("accepted", 0) > 0 and q.get("last_ts") == q.get("last_ok_ts") else "empty"
        if q.get("rejected") and q.get("accepted", 0) == 0 and q.get("proposed", 0) > 0:
            st = "rejected"
        skip_newer = q.get("skip_ts") and q["skip_ts"] > (q.get("last_ts") or 0)
        rec = _src(st, last_event_ts=max(q.get("last_ts") or 0, q.get("skip_ts") or 0) or None, last_produced_ts=q.get("last_ok_ts"), last_produced_n=q.get("last_ok_n"),
                   detail="lens=%s proposed=%s accepted=%s rejected=%s" % (q.get("lens"), q.get("proposed"), q.get("accepted"), ",".join("%s:%d" % kv for kv in sorted(q.get("rejected", {}).items())) or "-"))
        rec["rejected"] = q.get("rejected", {})
        rec["proposed"] = q.get("proposed", 0)
        rec["last_run_ts"] = q.get("last_ts")
        rec["skip"] = q.get("skip_result") if skip_newer else None
        rec["skip_note"] = q.get("skip_note", "") if skip_newer else ""
        rec["error_newer"] = q.get("result") == "error"
        s["qwen-explore"] = rec
    # ---- work supply / local research (box, only the lanes cron names) ----
    for name, key in (("work-supply", "ws"), ("local-research", "lr")):
        last_pass = ctx[key + "_pass"].get(repo)
        line = ctx[key + "_line"].get(repo)
        if last_pass is None and line is None:
            s[name] = _src("idle-lane", detail="no pass recorded for this repo")
            continue
        m = re.search(r"ADDED (\d+)", line or "") or re.search(r"^(\d+) items accepted", line or "") if line else None
        n = int(m.group(1)) if m else 0
        st = "ok" if n > 0 else ("cooldown" if line and "cooldown" in line else "empty")
        old = last_pass is not None and now - last_pass > 3 * 3600
        s[name] = _src("idle-lane" if old and st != "ok" else st, last_event_ts=last_pass, detail=(line or "")[:140], last_produced_ts=last_pass if n > 0 else None, last_produced_n=n or None)
    # ---- Claude queue bridge: reports its own last pass, it feeds CLAUDE_QUEUE.md (Claude work), never the 27B backlog ----
    bts = (ctx.get("ar") or {}).get("bridge_last_pass_ts")
    s["claude-queue-bridge"] = _src("n/a" if not bts else "ok", last_event_ts=bts, detail="feeds CLAUDE_QUEUE.md (Claude-routed work), not the 27B backlog")
    for name, ts in (ctx["consumed"].get(repo) or {}).items():
        if name in s:
            s[name]["last_consumed_ts"] = ts
    return s


def classify(repo, now, srcs):
    """Ordered [(class, text)] explaining why the repo is not getting supply. Only fresh evidence counts as a cause (OVN_SUPPLY_FRESH_H)."""
    fresh = _envf("OVN_SUPPLY_FRESH_H", 6) * 3600
    causes = []
    ar = srcs["auto-research"]
    recent = lambda ts: ts is not None and now - ts <= fresh
    if ar["state"] == "excluded" and recent(ar["last_event_ts"]):
        causes.append(("excluded", "lane excluded from auto-research (%s)" % (ar.get("detail") or "allowlist")))
    if ar["state"] == "timeout" and recent(ar["last_event_ts"]):
        causes.append(("timeout", "last auto-research pass failed (%s, %s)" % (ar.get("detail"), ago(ar["last_event_ts"], now))))
    if ar["state"] == "parser-reject" and recent(ar["last_event_ts"]):
        causes.append(("parser-reject", "auto-research reply rejected by the parser (%s)" % ago(ar["last_event_ts"], now)))
    q = srcs["qwen-explore"]
    if q["state"] == "rejected" and recent(q.get("last_run_ts")):
        causes.append(("explorer-rejected", "explorer rejected %s (%s)" % (sum(q["rejected"].values()) or q.get("proposed"), ", ".join("%s:%d" % kv for kv in sorted(q["rejected"].items())) or "?")))
    if q.get("error_newer") and recent(q.get("last_run_ts")):
        causes.append(("explorer-error", "last explorer run errored"))
    if ar.get("cap_hit"):
        causes.append(("cap", "auto-research daily cap hit (%s/%s)" % ar["cap"]))
    if q.get("skip") == "skip-cap" and recent(q.get("last_event_ts")):
        causes.append(("cap", "explorer daily cap hit (%s)" % (q.get("skip_note") or "skip-cap")))
    if ar["state"] == "started" and recent(ar["last_event_ts"]):
        if now - ar["last_event_ts"] <= 40 * 60:
            causes.append(("in-progress", "auto-research pass in progress (started %s)" % ago(ar["last_event_ts"], now)))
        else:
            causes.append(("timeout", "auto-research pass started %s and never ended" % ago(ar["last_event_ts"], now)))
    cool = []
    if q.get("skip") == "skip-lens-ttl" and recent(q.get("last_event_ts")):
        cool.append("explorer lens TTL (all lenses covered recently)")
    if ar["state"] == "cooldown" and recent(ar["last_event_ts"]):
        cool.append("auto-research cooldown")
    for n in ("work-supply", "local-research"):
        if srcs[n]["state"] == "cooldown" and recent(srcs[n]["last_event_ts"]):
            cool.append(n + " cooldown")
    if cool:
        causes.append(("cooldown", ", ".join(cool)))
    idle = [n for n in ("work-supply", "local-research") if srcs[n]["state"] == "idle-lane"]
    if idle:
        causes.append(("idle-lane", "%s not running for this repo" % " + ".join(idle)))
    if ar["state"] == "no-status":     # the main producer is invisible from here: always say so (never read as "no blocker")
        causes.append(("ar-unknown", "auto-research: no status (Mac export missing)"))
    if not causes:
        causes.append(("no-evidence", "no source has produced items and none recorded a blocker"))
    causes.sort(key=lambda c: CAUSE_ORDER.index(c[0]))
    return causes


def last_source(srcs):
    """(name, ts, n) of the source that most recently PRODUCED items, else None."""
    best = None
    for n in SOURCES:
        ts = srcs[n].get("last_produced_ts")
        if ts and (best is None or ts > best[1]):
            best = (n, ts, srcs[n].get("last_produced_n"))
    return best


# ----------------------------------------------------------------------------------------------------------- collection
def _import(name):
    import importlib
    return importlib.import_module(name)


def collect(now=None, root=None, state=None, repos=None, depths=None):
    """The whole report dict (pure function of the files + the clock)."""
    now = float(now if now is not None else time.time())
    root = root or ROOT
    state = state or STATE
    led = _import("ovn_supply_ledger")
    notify = _import("ovn_notify")
    doable = depths if depths is not None else (notify.queue_depths() if (os.path.abspath(notify.ROOT) == os.path.abspath(root)) else None)   # `depths`: the caller's own enabled-lane filtered counts
    if doable is None:                       # the notify module was imported for another root (tests): recount directly
        doable = {}
        for d in sorted(os.listdir(os.path.join(root, "repos"))) if os.path.isdir(os.path.join(root, "repos")) else []:
            n = notify._doable(os.path.join(root, "repos", d))
            if n is not None and d not in ("social-media-manager", "task-manager-platform", "shrike-labs-website"):
                doable[d] = n
    names = sorted(repos) if repos else sorted(doable)
    burn_h = _envf("OVN_SUPPLY_BURN_H", 24)
    rows = led.read_rows(state, now - 168 * 3600)
    rep_led = led.compute_report(rows, now, pullable=led.current_pullable(root, names), index=led.build_source_index(root), windows=(24, 72), lanes=names)
    ar, stale = load_ar_status(state, now)
    ctx = {"ar": ar, "ar_stale": stale, "roadmap": {}, "consumed": {}}
    for r in names:
        ctx["roadmap"][r] = _read(os.path.join(root, "roadmap", r + ".md"))
    ctx["qwen"] = parse_qwen_log(_read(os.path.join(root, "logs", "qwen_explore.log")))
    for key, log in (("ws", "work_supply.log"), ("lr", "local_research.log")):
        ctx[key + "_line"] = last_repo_lines(_read(os.path.join(root, "logs", log)), set(names))
        ctx[key + "_pass"] = {}
    for r in names:
        for key, fn in (("ws", "work_supply_last_" + r), ("lr", "local_research_" + r)):
            try:
                ctx[key + "_pass"][r] = float(_read(os.path.join(state, fn)).strip())
            except ValueError:
                pass
    index = led.build_source_index(root)
    for row in rows:                                   # last_consumed per source (an outcomes row for an item that source supplied)
        if row.get("repo") in names and not led._is_skip(row) and row.get("feat_tag"):
            src = led.attribute(row, index)
            src = {"deterministic": "work-supply", "local-research": "local-research", "qwen-explore": "qwen-explore", "auto-research": "auto-research"}.get(src)
            if src:
                c = ctx["consumed"].setdefault(row["repo"], {})
                c[src] = max(c.get(src, 0), row["_t"])
    out = {"ts": now, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "version": 1, "ar_status": None if ar is None else ("stale" if stale else "ok"), "repos": {}}
    runway_floor = _envf("OVN_SUPPLY_RUNWAY_H", 6)
    for repo in names:
        lane = rep_led["lanes"].get(repo) or {}
        w = (lane.get("windows") or {}).get("%dh" % 24) or {}
        pull = lane.get("pullable")
        items24 = w.get("items")
        covered = w.get("covered_h") or 0
        burn_day = None if items24 is None else (items24 * 24.0 / covered if 0 < covered < 24 else float(items24))
        if pull is None:
            runway = None
        elif pull == 0:
            runway = 0.0
        elif burn_day:
            runway = pull / (burn_day / 24.0)
        else:
            runway = None
        rm = ctx["roadmap"].get(repo, "")
        srcs = source_records(repo, now, ctx)
        starving = pull == 0 or (runway is not None and runway < runway_floor)
        causes = classify(repo, now, srcs) if starving else []
        ls = last_source(srcs)
        out["repos"][repo] = {
            "doable": doable.get(repo), "pullable": pull, "ready": len(READY_RE.findall(rm)), "needs_research": len(NEEDS_RE.findall(rm)),
            "burn_per_day": None if burn_day is None else round(burn_day, 1), "landed_24h": w.get("landed"), "runway_h": None if runway is None else round(runway, 1),
            "starving": bool(starving), "sources": srcs, "last_source": None if ls is None else {"name": ls[0], "ts": ls[1], "n": ls[2]},
            "causes": [{"class": c, "text": t} for c, t in causes], "cause_class": causes[0][0] if causes else None,
        }
        out["repos"][repo]["line"] = repo_line(repo, out["repos"][repo], now) if starving else None
    return out


# ----------------------------------------------------------------------------------------------------------- text
def repo_line(repo, rec, now):
    """The concise one-liner: depth, burn, runway, last supply source, root cause."""
    def n(v, unit=""):
        return "?" if v is None else ("%g%s" % (v, unit))
    ls = rec.get("last_source")
    last = "last supply %s %s%s" % (ls["name"], ago(ls["ts"], now), " (+%s)" % ls["n"] if ls.get("n") else "") if ls else "last supply: none on record"
    why = " + ".join(c["text"] for c in rec["causes"][:2]) or "ok"
    return "%s: pullable %s, ready %s, burn %s/d, runway %s; %s; cause: %s" % (
        repo, n(rec["pullable"]), n(rec["ready"]), n(rec["burn_per_day"]), "n/a" if rec["runway_h"] is None else "%gh" % rec["runway_h"], last, why)


def starving_lines(rep):
    return [(r, rec["line"]) for r, rec in sorted(rep["repos"].items()) if rec.get("starving") and rec.get("line")]


def digest_lines(rep, max_lines=None):
    """Lines for the hourly update: one per starving repo, at most `max_lines` (OVN_SUPPLY_LINES_MAX, default 4); the rest are grouped by primary cause on one line."""
    mx = int(_envf("OVN_SUPPLY_LINES_MAX", 3)) if max_lines is None else max_lines
    st = starving_lines(rep)
    if len(st) <= mx:
        return [l for _, l in st]
    out = [l for _, l in st[:mx - 1]]
    rest = st[mx - 1:]
    by = {}
    for r, _ in rest:
        by.setdefault(rep["repos"][r]["cause_class"], []).append(r)
    out.append("+%d more starving: %s" % (len(rest), "; ".join("%s (%s)" % (c, ", ".join(rs)) for c, rs in sorted(by.items(), key=lambda kv: CAUSE_ORDER.index(kv[0])))))
    return out


def cause_text(repo, rep=None, now=None):
    """Short 'cause: ...' text for one repo (research-trigger floor alert). Empty string when unknown/healthy. Never raises."""
    try:
        rep = rep or collect(now=now)
        rec = rep["repos"].get(repo)
        if not rec or not rec.get("starving"):
            return ""
        return "; ".join(c["text"] for c in rec["causes"][:2])
    except Exception:
        return ""


def log_lines(rep, root=None, stamp=None):
    root = root or ROOT
    path = os.path.join(root, "logs", "supply_report.log")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.getsize(path) > 1_000_000:
            keep = _read(path).split("\n")[-2000:]
            with open(path, "w") as f:
                f.write("\n".join(keep))
    except OSError:
        pass
    try:
        with open(path, "a") as f:
            for _, l in starving_lines(rep):
                f.write("%s %s\n" % (stamp or time.strftime("%Y-%m-%d %H:%M:%S"), l))
    except OSError:
        pass


def write_state(rep, state=None):
    state = state or STATE
    p = os.path.join(state, "supply_report.json")
    try:
        os.makedirs(state, exist_ok=True)
        tmp = p + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(rep, f, indent=1, sort_keys=True)
        os.replace(tmp, p)
    except OSError:
        pass


def fresh_report(now, state=None, max_age=2 * 3600):
    """state/supply_report.json when younger than max_age, else None."""
    try:
        with open(os.path.join(state or STATE, "supply_report.json")) as f:
            d = json.load(f)
        if isinstance(d, dict) and 0 <= now - float(d.get("ts", 0)) < max_age:
            return d
    except (OSError, ValueError, TypeError):
        pass
    return None


def main(argv):
    now = float(argv[argv.index("--now") + 1]) if "--now" in argv else None
    if "--export-ar" in argv:
        ar_dir = argv[argv.index("--ar-dir") + 1] if "--ar-dir" in argv else None
        bl = argv[argv.index("--bridge-log") + 1] if "--bridge-log" in argv else None
        print(json.dumps(export_ar(ar_dir, bl, now), sort_keys=True))
        return 0
    repos = argv[argv.index("--repos") + 1].split(",") if "--repos" in argv else None
    rep = collect(now=now, repos=repos)
    if "--dry-run" not in argv:
        write_state(rep)
        log_lines(rep)
    if "--json" in argv:
        print(json.dumps(rep, indent=1, sort_keys=True))
    else:
        for _, l in starving_lines(rep):
            print(l)
        if not starving_lines(rep):
            print("no starving repo (%d checked)" % len(rep["repos"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
