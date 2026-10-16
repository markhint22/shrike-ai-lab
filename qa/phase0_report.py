#!/usr/bin/env python3
"""phase0_report.py - read-only Phase 0 exit and precondition report (docs/QA_PLAN_2026-10-01.md section 7).

    phase0_report.py [--state-dir DIR] [--now ISO-Z|EPOCH] [--gold PATH]

Prints one JSON line per criterion, then one `overall` line. Exit 0 always.

Precondition (plan section 7, gate builds start only when all three are PASS):
  pass_rate_48h   overnight pass rate over the last 48 h >= 75 pct (good / (good + bad), benign excluded, bucket_from_severity)
  pass_rate_72h   same over the last 72 h
  hygiene_stall   no state/qa_blocked/*.json record held longer than 2 h (the QA-block stall the hourly digest reports)

Phase 0 exit items that a file can answer:
  ledger_coverage landed rows in state/qa_ledger.jsonl span >= 7 days
  gold_open       gold_set.json rows still pending (gate pending:<name> or a pending flag); FLAG while any remain
  escape_events   strong escape events (revert, escape, emergency, test_watch_red) in the last 30 days; info only (NA)

Human items the plan lists (manual-minutes log, tool smoke tests, Sentry origin, staging SHA, timings under load, suite runs) are
reported as NA with a reason: no file on disk can prove them.

Cell vocabulary: PASS FAIL FLAG NA UNVERIFIED. A missing or unreadable input is UNVERIFIED, never PASS. Malformed JSON lines are
skipped and counted in the summary, never fatal.

Read-only by construction: opens files for reading only, never creates or edits anything under the state dir, never takes a lock,
never calls git, ntfy or the network, and never reads or writes qa_gate_modes.json. It does not call qa_common.main_guard because
that helper records the verdict into state/qa_shadow; the same exception-to-UNVERIFIED rule is applied locally instead.
"""
import calendar
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

GATE = "phase0_report"
PASS_RATE_MIN = 75.0
STALL_MAX_H = 2.0
LEDGER_DAYS_MIN = 7.0
ESCAPE_WINDOW_DAYS = 30
STRONG_ESCAPE_TYPES = ("revert", "escape", "emergency", "test_watch_red")
SEVERITY_ORDER = {"FAIL": 4, "UNVERIFIED": 3, "FLAG": 2, "PASS": 1, "NA": 0}

NOT_MACHINE_READABLE = (
    "manual-minutes log, tool smoke tests, Sentry origin, staging SHA, gate timings under load, suite runs: "
    "no file on disk can prove this; a human checks it"
)


def parse_ts(s):
    """ISO-Z string -> epoch int, or None."""
    if not isinstance(s, str):
        return None
    try:
        return calendar.timegm(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None


def parse_now(text):
    """--now accepts an epoch number or an ISO-Z timestamp."""
    if text is None:
        return time.time()
    try:
        return float(text)
    except ValueError:
        e = parse_ts(text)
        if e is None:
            raise ValueError("bad --now %r (want epoch or YYYY-MM-DDTHH:MM:SSZ)" % text)
        return float(e)


def read_jsonl(path):
    """-> (rows, malformed_count, error). error is None when the file was read. Missing file -> ([], 0, 'missing')."""
    if not os.path.isfile(path):
        return [], 0, "missing"
    rows, bad = [], 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    bad += 1
                    continue
                if isinstance(d, dict):
                    rows.append(d)
                else:
                    bad += 1
    except OSError as e:
        return [], 0, "unreadable: %s" % e.__class__.__name__
    return rows, bad, None


def cell(criterion, verdict, summary, **extra):
    d = {"criterion": criterion, "verdict": verdict, "summary": summary[:300]}
    d.update(extra)
    return d


def pass_rate(rows, now, hours, bucket):
    """-> cell for the pass rate over the last `hours` hours."""
    start = now - hours * 3600
    good = bad = benign = 0
    for r in rows:
        ts = parse_ts(r.get("ts"))
        if ts is None or not (start < ts <= now):
            continue
        b = bucket(r.get("severity"))
        if b == "good":
            good += 1
        elif b == "bad":
            bad += 1
        else:
            benign += 1
    name = "pass_rate_%dh" % hours
    n = good + bad
    if n == 0:
        return cell(name, "UNVERIFIED", "no non-benign outcomes in the last %d h (good=0 bad=0 benign=%d)" % (hours, benign),
                    threshold=PASS_RATE_MIN, n=0)
    rate = round(100.0 * good / n, 1)
    v = "PASS" if rate >= PASS_RATE_MIN else "FAIL"
    return cell(name, v, "pass rate %.1f pct over %d h (good=%d bad=%d benign=%d, threshold %.0f)" % (rate, hours, good, bad, benign, PASS_RATE_MIN),
                value=rate, threshold=PASS_RATE_MIN, n=n)


def hygiene_stall(bdir, now):
    """Longest state/qa_blocked record age against STALL_MAX_H."""
    if not os.path.isdir(bdir):
        return cell("hygiene_stall", "UNVERIFIED", "state/qa_blocked directory not found; stall age cannot be measured",
                    threshold=STALL_MAX_H, blocked_repos=None)
    try:
        names = sorted(n for n in os.listdir(bdir) if n.endswith(".json"))
    except OSError as e:
        return cell("hygiene_stall", "UNVERIFIED", "state/qa_blocked unreadable: %s" % e.__class__.__name__, threshold=STALL_MAX_H,
                    blocked_repos=None)
    longest, unreadable = 0.0, 0
    for n in names:
        try:
            with open(os.path.join(bdir, n), "r", encoding="utf-8") as f:
                rec = json.load(f)
            since = parse_ts(rec.get("since")) if isinstance(rec, dict) else None
        except (OSError, ValueError):
            since = None
        if since is None:
            unreadable += 1
            continue
        longest = max(longest, (now - since) / 3600.0)
    longest = round(longest, 2)
    if unreadable:
        return cell("hygiene_stall", "UNVERIFIED", "%d blocked record(s) have no readable since stamp; longest known stall %.2f h" % (unreadable, longest),
                    value=longest, threshold=STALL_MAX_H, blocked_repos=len(names))
    v = "FAIL" if longest > STALL_MAX_H else "PASS"
    return cell("hygiene_stall", v, "longest QA-block stall %.2f h across %d blocked repo(s) (threshold %.0f h)" % (longest, len(names), STALL_MAX_H),
                value=longest, threshold=STALL_MAX_H, blocked_repos=len(names))


def ledger_cells(path, now):
    rows, bad, err = read_jsonl(path)
    if err:
        return [cell("ledger_coverage", "UNVERIFIED", "state/qa_ledger.jsonl %s" % err, threshold=LEDGER_DAYS_MIN),
                cell("escape_events", "UNVERIFIED", "state/qa_ledger.jsonl %s" % err)]
    landed = [r["epoch"] for r in rows if r.get("kind") == "landed" and isinstance(r.get("epoch"), int) and not isinstance(r.get("epoch"), bool)]
    if not landed:
        cov = cell("ledger_coverage", "UNVERIFIED", "ledger has no landed rows (malformed skipped: %d)" % bad, threshold=LEDGER_DAYS_MIN)
    else:
        span = round((max(landed) - min(landed)) / 86400.0, 2)
        v = "PASS" if span >= LEDGER_DAYS_MIN else "FLAG"
        cov = cell("ledger_coverage", v, "ledger landed rows span %.2f days (%d rows; threshold %.0f days)" % (span, len(landed), LEDGER_DAYS_MIN),
                   value=span, threshold=LEDGER_DAYS_MIN, n=len(landed))
    start = now - ESCAPE_WINDOW_DAYS * 86400
    esc = [r for r in rows if r.get("kind") == "event" and r.get("type") in STRONG_ESCAPE_TYPES
           and isinstance(parse_ts(r.get("ts")), int) and start < parse_ts(r.get("ts")) <= now]
    ev = cell("escape_events", "NA", "%d strong escape event(s) in the last %d days (info only; no threshold in plan section 7)" % (len(esc), ESCAPE_WINDOW_DAYS),
              value=len(esc))
    return [cov, ev]


def gold_cell(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        rows = data["rows"]
        if not isinstance(rows, list):
            raise ValueError("rows is not a list")
    except (OSError, ValueError, KeyError, TypeError) as e:
        return cell("gold_open", "UNVERIFIED", "gold set unreadable: %s" % e.__class__.__name__)
    open_ids = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        g = r.get("gate")
        if (isinstance(g, str) and g.startswith("pending:")) or r.get("pending") is True:
            open_ids.append(str(r.get("id")))
    v = "FLAG" if open_ids else "PASS"
    return cell("gold_open", v, "%d of %d gold rows still pending (%s)" % (len(open_ids), len(rows), ",".join(open_ids) or "none"),
                value=len(open_ids), n=len(rows))


def overall(cells):
    worst = "PASS"
    for c in cells:
        if c["verdict"] == "NA":
            continue
        if SEVERITY_ORDER[c["verdict"]] > SEVERITY_ORDER[worst]:
            worst = c["verdict"]
    return worst


def build(state_dir, now, gold_path, bucket=None):
    if bucket is None:
        sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "scripts")))
        from ovn_outcome_buckets import bucket_from_severity as bucket  # noqa: E402
    outcomes, bad, err = read_jsonl(os.path.join(state_dir, "outcomes.jsonl"))
    precond = []
    if err:
        precond += [cell("pass_rate_48h", "UNVERIFIED", "outcomes.jsonl %s" % err, threshold=PASS_RATE_MIN),
                    cell("pass_rate_72h", "UNVERIFIED", "outcomes.jsonl %s" % err, threshold=PASS_RATE_MIN)]
    else:
        precond += [pass_rate(outcomes, now, 48, bucket), pass_rate(outcomes, now, 72, bucket)]
    precond.append(hygiene_stall(os.path.join(state_dir, "qa_blocked"), now))
    exit_cells = ledger_cells(os.path.join(state_dir, "qa_ledger.jsonl"), now) + [gold_cell(gold_path)]
    manual = [cell("manual_items", "NA", NOT_MACHINE_READABLE)]
    if bad:
        exit_cells.append(cell("outcomes_malformed", "FLAG", "%d malformed outcomes.jsonl line(s) skipped" % bad, value=bad))
    prec_v = overall(precond)
    exit_v = overall(exit_cells)
    return precond, exit_cells + manual, prec_v, exit_v


def main(argv):
    args = {"--state-dir": None, "--now": None, "--gold": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in args and i + 1 < len(argv):
            args[a] = argv[i + 1]
            i += 2
            continue
        i += 1
    try:
        state_dir = args["--state-dir"] or qc.state_dir()
        now = parse_now(args["--now"])
        gold = args["--gold"] or os.path.join(HERE, "gold_set.json")
        precond, exit_cells, prec_v, exit_v = build(state_dir, now, gold)
    except Exception as ex:  # noqa: BLE001 - never raise into the caller
        print(json.dumps(cell("overall", "UNVERIFIED", "report crashed: %s: %s" % (type(ex).__name__, str(ex)[:200])), sort_keys=True))
        return 0
    for c in precond:
        print(json.dumps(dict(c, group="precondition"), sort_keys=True))
    for c in exit_cells:
        print(json.dumps(dict(c, group="phase0_exit"), sort_keys=True))
    overall_v = overall([{"verdict": prec_v}, {"verdict": exit_v}])
    print(json.dumps({"criterion": "overall", "verdict": overall_v, "precondition": prec_v, "phase0_exit": exit_v,
                      "precondition_met": prec_v == "PASS", "state_dir": state_dir, "now": int(now),
                      "summary": "precondition %s; phase0 machine items %s" % (prec_v, exit_v)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
