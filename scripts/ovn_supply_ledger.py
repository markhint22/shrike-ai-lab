#!/usr/bin/env python3
"""ovn_supply_ledger.py - per-lane WORK-SUPPLY ledger (2026-10-13, package supply-ledger). Read-only, deterministic, no model calls.

Why: in the 64 h before the five secondary lanes were enabled, iptv_apps worked 11.9 h (18.5% duty) and xlite 5.9 h (9.2%); in 32 of those 64 hours BOTH did less than a
minute and the GPU averaged 12%. Nothing said so: ovn_notify.starved_check needs ALL enabled lanes idle for 6 h (seven lanes, two starving = it can never fire), the trickle
pattern (one short cycle every 2-3 h) never opens a 6 h gap, and no metric attributed an item to the source that supplied it. This module measures it.

Per lane, over 24 h and 72 h, from state/outcomes.jsonl (a row's `ts` is its END, UTC; it ran [ts - duration_s, ts]; class "skipped" rows are the idle loop's heartbeat):
  busy_min        wall-clock minutes the lane worked (UNION of the row intervals, clipped to the window)     duty_pct = busy_min / window
  lane_min        sum of the row durations (== busy_min unless rows overlap)
  idle_exhausted_h  hours the lane sat idle with nothing pullable, from its skip(exhausted) heartbeat rows (one per ~1-2 h now): the stretch between an exhausted-skip
                  row and the lane's previous row, minus time it worked; see exhausted_spans(). A LOWER bound (a stretch that ends in a work row is not counted).
  items           DISTINCT item_hash values attempted     landed / landed_uncredited / credit_only / reverted  (kept SEPARATE: landed is credited work, landed-uncredited is a
                  push the credit gate did not accept; pushed = landed + landed_uncredited)
  noop_share      share of the lane's non-skip rows that were no-ops (+ noop_min)
  reserve_min     minutes spent RE-SERVING an item after its first push (same item_hash, later row; the first push may predate the window, history is scanned for it)
  inflow_by_source  distinct items consumed by where they came from (see attribute()). `inflow` here means "items that entered work in the window", not "lines added to a file".

attribute(row, index=None) -> source, importable. Order: no feat_tag = "recovery/untagged"; feat_tag slug "supply-*" = "deterministic"; otherwise the roadmap section header (or an
explicit `[src:<name>]` tag on the roadmap line) that holds the feature the tag was cut from: "## Auto-research ..." / "## Research refuel" / "## Refuel" / "## Newly discovered" =
"auto-research" (Claude-authored research, automatic or interactive), "## Local research" = "local-research", Qwen exploration = "qwen-explore", Claude-queue triage = "cq-triage",
any other header = "roadmap-other"; a tag with no roadmap match = "unattributed" (never guessed). `index` is build_source_index(root); without it only the first two rules apply.

Outputs: state/supply_ledger.json (atomic write), one line per lane per run appended to logs/supply_ledger.log (rotated at 2 MB), and the alert below.

ALERT (OVN_SUPPLY_ALERT=shadow|on|off, default shadow): one alerts.log `warn | supply-duty` line per lane per local day when the lane is in OVN_PRIORITY_LANES (default
iptv_apps,xlite), its 24 h duty is below OVN_DUTY_FLOOR (default 25 %) AND it has nothing pullable right now. It is NOT folded into the chronic-daily line (that line is the
thing that made six months of 'runway <1d' invisible). In shadow mode the would-be line goes to logs/supply_ledger.log only. In both modes (on or shadow) the FIRST sighting of a
local day writes state/supply_escalate_<repo> (JSON, written once per day, never refreshed); the Mac-side ovn_auto_research.sh reads it for its own gated extra research pass
(OVN_AUTO_RESEARCH_ESCALATE, default shadow = log only). OVN_SUPPLY_ALERT=off writes neither.

usage:  ovn_supply_ledger.py [--print] [--dry-run] [--now EPOCH]
cron (proposed, NOT installed):  */30 * * * * cd ~/overnight-queue && python3 scripts/ovn_supply_ledger.py >> logs/supply_ledger.log 2>&1
env:    OVN_DIR (queue root, default ~/overnight-queue), OVN_NOTIFY_STATE (state dir), OVN_SUPPLY_ALERT, OVN_DUTY_FLOOR, OVN_PRIORITY_LANES, OVN_SUPPLY_EXH_GAP_S (default 10800: longest stretch one heartbeat row may vouch for),
        OVN_SUPPLY_SCAN_MB (default 64), OVN_SUPPLY_MAX_ROW_S (default 10800: a row longer than that is clamped, a corrupt duration must not fill a window)
"""
import calendar
import glob
import importlib.util
import json
import os
import re
import sys
import time

ROOT = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
STATE = os.environ.get("OVN_NOTIFY_STATE") or os.path.join(ROOT, "state")
WINDOWS_H = (24, 72)
SCAN_H = 168                                  # history scanned: windows + enough to find the first push of an item served inside the 72 h window
PUSHED = ("landed", "landed-uncredited")
DETERMINISTIC, RECOVERY, UNATTRIBUTED, ROADMAP_OTHER = "deterministic", "recovery/untagged", "unattributed", "roadmap-other"
SOURCES = ("auto-research", "local-research", "qwen-explore", "cq-triage", DETERMINISTIC, RECOVERY, ROADMAP_OTHER, UNATTRIBUTED)
_TAG_RE = re.compile(r"^(.*?)-(\d{8})-(.*)$")
_ITEM_RE = re.compile(r"^- \[[ xX]\] (?:\[P\d\] )?(?:\[[A-Za-z-]+\] )?(.*)$")
_SRC_RE = re.compile(r"\[src:([A-Za-z0-9_-]+)\]")


def _envf(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def priority_lanes():
    raw = os.environ.get("OVN_PRIORITY_LANES", "iptv_apps,xlite")
    return [x.strip() for x in raw.split(",") if x.strip()]


def alert_mode():
    m = os.environ.get("OVN_SUPPLY_ALERT", "shadow").strip().lower()
    return m if m in ("shadow", "on", "off") else "shadow"


# ----------------------------------------------------------------------------------------------------------- intervals
def merge_intervals(ivs, gap=0.0):
    """Union of [start, end] intervals; two intervals closer than `gap` seconds are joined. Returns a sorted list of [start, end]."""
    out = []
    for s, e in sorted((s, e) for s, e in ivs if e >= s):
        if out and s <= out[-1][1] + gap:
            if e > out[-1][1]:
                out[-1][1] = e
        else:
            out.append([s, e])
    return out


def clip_intervals(ivs, lo, hi):
    return [[max(s, lo), min(e, hi)] for s, e in ivs if min(e, hi) > max(s, lo)]


def subtract_intervals(a, b):
    """a minus b, both already merged/sorted."""
    out = []
    for s, e in a:
        cur = s
        for bs, be in b:
            if be <= cur or bs >= e:
                continue
            if bs > cur:
                out.append([cur, bs])
            cur = max(cur, be)
            if cur >= e:
                break
        if cur < e:
            out.append([cur, e])
    return out


def total_s(ivs):
    return sum(e - s for s, e in ivs)


# ----------------------------------------------------------------------------------------------------------- source attribution
def classify_header(header):
    """Roadmap section header text -> source name (see the module docstring)."""
    h = (header or "").lower()
    if re.search(r"local[ -]research", h):
        return "local-research"
    if re.search(r"qwen[ -]?explor", h):
        return "qwen-explore"
    if re.search(r"cq[ -]?triage|claude[ _-]?queue", h):
        return "cq-triage"
    if re.search(r"auto-research|research refuel|research pass|refuel|newly discovered", h):
        return "auto-research"
    return ROADMAP_OTHER


def _slug(text):
    """The slug ovn_planner.sh puts in a [feat:<repo>-<YYYYMMDD>-<slug>] tag: lowercase, non-alnum runs -> '-', trimmed, first 40 chars."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:40] or "item"


def build_source_index(root):
    """{(repo, slug40): source} from roadmap/<repo>.md: each feature line's source is its explicit [src:x] tag, else the nearest `## ` header above it. First line wins."""
    idx = {}
    for path in glob.glob(os.path.join(root, "roadmap", "*.md")):
        repo = os.path.basename(path)[:-3]
        header = ""
        try:
            lines = open(path, errors="replace").read().split("\n")
        except OSError:
            continue
        for ln in lines:
            if ln.startswith("## "):
                header = ln[3:]
                continue
            m = _ITEM_RE.match(ln)
            if not m:
                continue
            src = _SRC_RE.search(ln)
            source = src.group(1).lower() if src else classify_header(header)
            idx.setdefault((repo, _slug(m.group(1))), source)
    return idx


def attribute(row, index=None):
    """Source of the item a outcomes row worked on (see the module docstring for the rules)."""
    tag = str(row.get("feat_tag") or "")
    explicit = row.get("src")
    if isinstance(explicit, str) and explicit.strip():
        return explicit.strip().lower()
    if not tag:
        return RECOVERY
    m = _TAG_RE.match(tag)
    slug = m.group(3) if m else tag
    if slug.startswith("supply-") or tag.startswith("supply-"):
        return DETERMINISTIC
    if index:
        repo = str(row.get("repo") or (m.group(1) if m else ""))
        src = index.get((repo, slug)) or index.get((repo, slug[:40]))
        if src is None:
            for (r, s), v in index.items():     # the tag may carry a shorter slug than the index key (feature text shorter than 40 chars)
                if r == repo and slug and s.startswith(slug):
                    src = v
                    break
        if src is not None:
            return src
    return UNATTRIBUTED


# ----------------------------------------------------------------------------------------------------------- reading
def read_rows(state_dir, since, max_bytes=None):
    """Rows of state/outcomes.jsonl with ts >= since, each with `_t` (end epoch) and `_d` (duration seconds). Tail-read; unparseable lines are skipped."""
    if max_bytes is None:
        max_bytes = int(_envf("OVN_SUPPLY_SCAN_MB", 64) * 1_000_000)
    max_row = _envf("OVN_SUPPLY_MAX_ROW_S", 10800)
    path = os.path.join(state_dir, "outcomes.jsonl")
    rows = []
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - max_bytes))
            for line in f:
                try:
                    d = json.loads(line)
                    t = calendar.timegm(time.strptime(str(d["ts"])[:19], "%Y-%m-%dT%H:%M:%S"))
                except Exception:
                    continue
                if not isinstance(d, dict) or t < since:
                    continue
                try:
                    dur = float(d.get("duration_s") or 0)
                except (TypeError, ValueError):
                    dur = 0.0
                d["_t"], d["_d"] = float(t), max(0.0, min(dur, max_row))
                rows.append(d)
    except OSError:
        pass
    return rows


def _is_skip(r):
    """Rows that are NOT work: the idle loop's skip heartbeat, and D4's landed-late attribution rows (stamped with the reconcile time, no duration, no cycle - they would
    otherwise refresh a starved lane's 'last real work' and inflate its row/item counters)."""
    return r.get("class") in ("skipped", "landed-late") or str(r.get("status", "")).startswith("skip")


def _is_exhausted_skip(r):
    return _is_skip(r) and ("exhausted" in str(r.get("status", "")) or r.get("fail_reason") == "queue-exhausted")


def _doable_fallback(bt, pt):
    held = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|\(retired-|\[CLAUDE\]")
    return sum(1 for l in (bt + "\n" + pt).split("\n") if re.match(r"^- \[ \] \[T[1-5]\]", l) and not held.search(l))


def current_pullable(root, repos):
    """{repo: items the fleet can take next, or None when the repo is not on this box}: the same definition ovn_research_trigger_check uses
    (ovn_work_supply.pullable_count), with the plain open-T-item count as the fallback."""
    def rd(p):
        try:
            return open(p, errors="replace").read()
        except OSError:
            return ""
    mod = None
    try:
        sup = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ovn_work_supply.py")
        spec = importlib.util.spec_from_file_location("ovn_work_supply_for_ledger", sup)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception:
        mod = None
    out = {}
    for repo in repos:
        bl = os.path.join(root, "backlog", repo + ".md")
        rd_ = os.path.join(root, "repos", repo)
        if not os.path.isfile(bl) and not os.path.isdir(rd_):
            out[repo] = None
            continue
        bt, pt, dt = rd(bl), rd(os.path.join(rd_, "OVERNIGHT_PROGRESS.md")), rd(os.path.join(rd_, "OVERNIGHT_DONE.md"))
        n = None
        if mod is not None:
            try:
                n = mod.pullable_count(bt, pt, dt)
            except Exception:
                n = None
        out[repo] = n if isinstance(n, int) and not isinstance(n, bool) else _doable_fallback(bt, pt)
    return out


def exhausted_spans(lane_rows, now, max_gap=None):
    """Merged [start, end] spans in which the lane was idle with nothing pullable, from its skip(exhausted) heartbeat rows (a LOWER bound).
    An exhausted-skip row says "the lane looked and found nothing"; if the lane's previous row (of any kind) ended at most `max_gap` seconds earlier (default
    OVN_SUPPLY_EXH_GAP_S = 10800), the whole stretch between them was idle-and-empty (a lane with work does not skip). The heartbeat is now ONE row per ~1-2 h
    (it was one per ~12 s on 10-09), so a fixed bridging distance would measure nothing. The stretch from the lane's LAST exhausted-skip row to `now` counts too
    when that row is the lane's newest row and is at most max_gap old. A stretch that ends in a WORK row (refuel arrived at an unknown moment inside it) is not counted."""
    if max_gap is None:
        max_gap = _envf("OVN_SUPPLY_EXH_GAP_S", 10800)
    rs = sorted(lane_rows, key=lambda r: r["_t"])
    spans = []
    prev_end = None
    for r in rs:
        start = r["_t"] - r["_d"]
        if _is_exhausted_skip(r):
            lo = start if prev_end is None or start - prev_end > max_gap else min(prev_end, start)
            spans.append([lo, r["_t"]])
        prev_end = max(prev_end, r["_t"]) if prev_end is not None else r["_t"]
    if rs and _is_exhausted_skip(rs[-1]) and 0 <= now - rs[-1]["_t"] <= max_gap:
        spans.append([rs[-1]["_t"], now])
    return merge_intervals(spans)


# ----------------------------------------------------------------------------------------------------------- compute
def _lane_window(rows_all, rows_win, lo, hi, denom_s, index, exh):
    """Metrics of ONE lane in [lo, hi]. rows_all = every scanned row of the lane (to find first pushes), rows_win = those ending inside the window or overlapping it."""
    work = [r for r in rows_win if not _is_skip(r)]
    busy_ivs = merge_intervals(clip_intervals([[r["_t"] - r["_d"], r["_t"]] for r in work], lo, hi))
    busy_s = total_s(busy_ivs)
    idle_s = total_s(subtract_intervals(clip_intervals(exh, lo, hi), busy_ivs))
    inwin = [r for r in work if lo <= r["_t"] <= hi]          # rows that FINISHED in the window (the counters)
    classes = {}
    for r in inwin:
        classes[r.get("class")] = classes.get(r.get("class"), 0) + 1
    hashes = {}
    no_hash = 0
    for r in inwin:
        h = r.get("item_hash") or ""
        if not h:
            no_hash += 1
            continue
        hashes.setdefault(h, r)
    inflow = {}
    for h, r in hashes.items():
        s = attribute(r, index)
        inflow[s] = inflow.get(s, 0) + 1
    landed_hashes = {r.get("item_hash") for r in inwin if r.get("class") in PUSHED and r.get("item_hash")}
    # re-serving: rows of an item AFTER its first push (first push searched over all scanned history, charged only inside the window)
    first_push = {}
    for r in sorted((r for r in rows_all if not _is_skip(r) and r.get("item_hash")), key=lambda r: r["_t"]):
        if r.get("class") in PUSHED and r["item_hash"] not in first_push:
            first_push[r["item_hash"]] = r["_t"]
    re_rows = [r for r in inwin if r.get("item_hash") in first_push and r["_t"] > first_push[r["item_hash"]]]
    noop = [r for r in inwin if r.get("class") == "noop"]
    landed, unc = classes.get("landed", 0), classes.get("landed-uncredited", 0)
    return {
        "window_h": round((hi - lo) / 3600.0, 2),
        "rows": len(inwin),
        "busy_min": round(busy_s / 60.0, 1),
        "lane_min": round(sum(r["_d"] for r in inwin) / 60.0, 1),
        "duty_pct": round(100.0 * busy_s / denom_s, 1) if denom_s > 0 else 0.0,
        "idle_exhausted_h": round(idle_s / 3600.0, 2),
        "items": len(hashes),
        "rows_without_hash": no_hash,
        "items_pushed": len(landed_hashes),
        "landed": landed,
        "landed_uncredited": unc,
        "pushed": landed + unc,
        "credit_only": classes.get("credit-only", 0),
        "reverted": classes.get("reverted", 0) + classes.get("revert", 0),
        "noop": len(noop),
        "noop_share": round(len(noop) / float(len(inwin)), 3) if inwin else 0.0,
        "noop_min": round(sum(r["_d"] for r in noop) / 60.0, 1),
        "reserve_rows": len(re_rows),
        "reserve_min": round(sum(r["_d"] for r in re_rows) / 60.0, 1),
        "inflow_by_source": dict(sorted(inflow.items(), key=lambda kv: -kv[1])),
    }


def compute_report(rows, now, pullable=None, index=None, windows=WINDOWS_H, lanes=None, data_start=None):
    """Pure function of the rows + the clock. `pullable` {repo: int|None} adds the live queue state; `lanes` forces lanes into the report (the priority lanes are
    always listed: a lane with NO rows at all is the worst case, not an absent one). `data_start` = earliest instant the rows can speak for (default: the first row):
    a window longer than the data is divided by the data it has, never by hours nobody recorded."""
    ds = data_start if data_start is not None else (min(r["_t"] - r["_d"] for r in rows) if rows else now)
    by_lane = {}
    for r in rows:
        if r.get("repo"):
            by_lane.setdefault(str(r["repo"]), []).append(r)
    names = sorted(set(by_lane) | set(lanes or ()) | set((pullable or {}).keys()))
    rep = {"ts": now, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "version": 1, "data_start": ds, "lanes": {}}
    for lane in names:
        lr = by_lane.get(lane, [])
        exh = exhausted_spans(lr, now)
        wins = {}
        for h in windows:
            lo = now - h * 3600
            denom = max(60.0, now - max(lo, ds))
            rw = [r for r in lr if r["_t"] >= lo and r["_t"] - r["_d"] <= now]
            wins["%dh" % h] = _lane_window(lr, rw, lo, now, denom, index, exh)
            wins["%dh" % h]["covered_h"] = round(min(float(h), max(0.0, (now - ds) / 3600.0)), 2)
        real = [r["_t"] for r in lr if not _is_skip(r)]
        rep["lanes"][lane] = {"pullable": (pullable or {}).get(lane), "last_work_ts": max(real) if real else None, "windows": wins}
    return rep


# ----------------------------------------------------------------------------------------------------------- alert + escalation
def evaluate_alerts(report, floor=None, prio=None):
    """[{repo, duty24, pullable, ...}] for priority lanes under the duty floor with nothing pullable. pullable None (unknown) never alerts."""
    floor = _envf("OVN_DUTY_FLOOR", 25) if floor is None else floor
    out = []
    for lane in (priority_lanes() if prio is None else prio):
        rec = report["lanes"].get(lane)
        if not rec or rec.get("pullable") is None or rec["pullable"] != 0:
            continue
        w = rec["windows"].get("24h")
        if w and w["duty_pct"] < floor:
            out.append({"repo": lane, "duty24": w["duty_pct"], "floor": floor, "pullable": 0, "idle_exhausted_h": w["idle_exhausted_h"], "items_24h": w["items"], "busy_min": w["busy_min"]})
    return out


def _load_json(path, default):
    try:
        v = json.load(open(path))
        return v if isinstance(v, type(default)) else default
    except (OSError, ValueError):
        return default


def _atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def apply_alerts(alerts, now, state_dir=None, root=None, mode=None):
    """Write at most one line per lane per local day (alerts.log in `on` mode, logs/supply_ledger.log in `shadow`), and the once-per-day escalation marker
    state/supply_escalate_<repo>. Returns [(kind, repo, line)] for what was written. Never raises."""
    state_dir = state_dir or STATE
    root = root or ROOT
    mode = mode or alert_mode()
    done = []
    if mode == "off" or not alerts:
        return done
    day = time.strftime("%Y-%m-%d", time.localtime(now))
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now))
    seen_path = os.path.join(state_dir, "supply_alerted.json")
    seen = _load_json(seen_path, {})
    changed = False
    for a in alerts:
        repo = a["repo"]
        msg = ("supply floor: %s worked %.0f%% of the last 24h (%.0f min; floor %.0f%%) and has nothing pullable - idle with an empty queue %.1fh, %d item(s) taken in 24h. "
               "Needs new work (research pass / supply), not more patience" % (repo, a["duty24"], a["busy_min"], a["floor"], a["idle_exhausted_h"], a["items_24h"]))
        key = ("warn:" if mode == "on" else "shadow:") + repo
        if seen.get(key) != day:
            try:
                if mode == "on":
                    line = "[%s] warn | supply-duty | %s" % (stamp, msg)
                    with open(os.path.join(state_dir, "alerts.log"), "a") as f:
                        f.write(line + "\n")
                else:
                    line = "[%s] SHADOW would warn | supply-duty | %s" % (stamp, msg)
                    log_line(root, line)
                seen[key] = day
                changed = True
                done.append(("alert" if mode == "on" else "shadow", repo, line))
            except OSError:
                pass
        mk = os.path.join(state_dir, "supply_escalate_%s" % repo)
        if _load_json(mk, {}).get("day") != day:     # once per local day: an existing marker of today is never rewritten
            try:
                _atomic_write(mk, json.dumps({"repo": repo, "day": day, "ts": now, "duty24_pct": a["duty24"], "pullable": 0, "mode": mode}, sort_keys=True) + "\n")
                done.append(("escalate", repo, mk))
            except OSError:
                pass
    if changed:
        try:
            _atomic_write(seen_path, json.dumps(seen, indent=1, sort_keys=True))
        except OSError:
            pass
    return done


# ----------------------------------------------------------------------------------------------------------- output
def lane_line(lane, rec, stamp):
    parts = []
    for k in ("24h", "72h"):
        w = rec["windows"].get(k)
        if not w:
            continue
        src = ",".join("%s:%d" % (s, n) for s, n in w["inflow_by_source"].items()) or "-"
        parts.append("%s duty=%.0f%% busy=%.0fm idle_exh=%.1fh items=%d landed=%d unc=%d noop=%.0f%% reserve=%.0fm src=%s" % (
            k, w["duty_pct"], w["busy_min"], w["idle_exhausted_h"], w["items"], w["landed"], w["landed_uncredited"], 100 * w["noop_share"], w["reserve_min"], src))
    return "[%s] %s pullable=%s | %s" % (stamp, lane, "?" if rec.get("pullable") is None else rec["pullable"], " | ".join(parts))


def log_line(root, line):
    path = os.path.join(root, "logs", "supply_ledger.log")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        if os.path.getsize(path) > 2_000_000:
            keep = open(path, errors="replace").read().split("\n")[-4000:]
            _atomic_write(path, "\n".join(keep))
    except OSError:
        pass
    with open(path, "a") as f:
        f.write(line + "\n")


def digest_line(report, prio=None):
    """'Lane duty 24h: iptv 16% (9 items/d in), xlite 5% (8/d in)' for the priority lanes; None when the report has none of them."""
    parts = []
    for lane in (priority_lanes() if prio is None else prio):
        rec = report["lanes"].get(lane)
        w = rec and rec["windows"].get("24h")
        if not w:
            continue
        name = re.sub(r"_apps$", "", lane)
        parts.append("%s %.0f%% (%d%s/d in)" % (name, w["duty_pct"], w["items"], "" if parts else " items"))
    return "Lane duty 24h: " + ", ".join(parts) if parts else None


def run(now=None, state_dir=None, root=None, dry=False):
    now = float(now if now is not None else time.time())
    state_dir = state_dir or STATE
    root = root or ROOT
    rows = read_rows(state_dir, now - SCAN_H * 3600)
    prio = priority_lanes()
    lanes = sorted(set(prio) | {r["repo"] for r in rows if r.get("repo")})
    rep = compute_report(rows, now, pullable=current_pullable(root, lanes), index=build_source_index(root), lanes=prio)
    rep["priority_lanes"] = prio
    rep["duty_floor"] = _envf("OVN_DUTY_FLOOR", 25)
    rep["alert_mode"] = alert_mode()
    alerts = evaluate_alerts(rep)
    rep["alerts"] = alerts
    if dry:
        return rep, []
    _atomic_write(os.path.join(state_dir, "supply_ledger.json"), json.dumps(rep, indent=1, sort_keys=True))
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now))
    for lane, rec in sorted(rep["lanes"].items()):
        log_line(root, lane_line(lane, rec, stamp))
    return rep, apply_alerts(alerts, now, state_dir, root)


def main(argv):
    now = float(argv[argv.index("--now") + 1]) if "--now" in argv else None
    rep, _ = run(now=now, dry="--dry-run" in argv)
    if "--print" in argv or "--dry-run" in argv:
        print(json.dumps(rep, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
