#!/usr/bin/env python3
"""Tests for qa/phase0_report.py (read-only Phase 0 exit and precondition report). Fixtures are temp dirs; no network, no git,
no real state. Every verdict has a negative control (seeded bad input -> the bad cell) and benign controls (clean input -> PASS).
The CLI is run as a subprocess under env -i with NTFY_SERVER set, by absolute path, to pin the real entry point.
PHASE0_QA_DIR=<dir holding another copy of qa/> runs the suite against that copy (mutation proofs)."""
import calendar
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.environ.get("PHASE0_QA_DIR") or os.path.join(OVN, "qa")
CLI = os.path.join(QA, "phase0_report.py")
GOLD_DEFAULT = os.path.join(QA, "gold_set.json")
PY = sys.executable
P = F = 0

NOW = calendar.timegm(time.strptime("2026-10-15T12:00:00", "%Y-%m-%dT%H:%M:%S"))


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


def iso(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


def write_jsonl(path, rows, raw_lines=()):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
        for line in raw_lines:
            f.write(line + "\n")


def outcome_rows(hours_back_range, good, bad, benign=0):
    """Spread good/bad/benign outcomes evenly across the given hour offsets (ages in hours)."""
    rows = []
    for age in hours_back_range:
        ts = iso(NOW - age * 3600)
        for _ in range(good):
            rows.append({"ts": ts, "repo": "billwatch", "severity": "good", "class": "landed", "status": "pushed"})
        for _ in range(bad):
            rows.append({"ts": ts, "repo": "billwatch", "severity": "bad", "class": "failed", "status": "verify-failed"})
        for _ in range(benign):
            rows.append({"ts": ts, "repo": "billwatch", "severity": "neutral", "class": "noop", "status": "already-done"})
    return rows


def ledger_rows(span_days, n=10):
    """n landed rows spanning span_days, ending at NOW."""
    rows = []
    for i in range(n):
        e = NOW - int(span_days * 86400 * (i / max(1, n - 1)))
        rows.append({"kind": "landed", "key": "k%d" % i, "ts": iso(e), "epoch": e, "repo": "billwatch"})
    return rows


def fixture_gold(path, pending_ids=()):
    rows = [{"id": "G1", "repo": "billwatch", "gate": "antigaming", "kind": "true_positive"}]
    for pid in pending_ids:
        rows.append({"id": pid, "repo": "billwatch", "gate": "pending:thing", "kind": "true_positive"})
    with open(path, "w") as f:
        json.dump({"version": 2, "rows": rows}, f)


def clean_state(root, gold_pending=()):
    """A benign state dir: 80 pct pass over 72 h, no stall, 8 days of ledger, gold with no pending rows (or the given pending)."""
    st = os.path.join(root, "state")
    os.makedirs(os.path.join(st, "qa_blocked"))
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(0, 72, 3), good=8, bad=2))
    write_jsonl(os.path.join(st, "qa_ledger.jsonl"), ledger_rows(8.0))
    gold = os.path.join(root, "gold.json")
    fixture_gold(gold, gold_pending)
    return st, gold


def run_cli(args, cwd=None, env=None, absolute=True):
    script = CLI if absolute else os.path.relpath(CLI, cwd)
    e = env if env is not None else {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": "/nonexistent",
                                     "NTFY_SERVER": "http://127.0.0.1:9/x"}
    p = subprocess.run([PY, script] + args, cwd=cwd or OVN, env=e, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


def parse_lines(out):
    res = []
    for line in out.splitlines():
        line = line.strip()
        if line:
            res.append(json.loads(line))
    return res


def by_name(cells):
    return {c["criterion"]: c for c in cells}


def tree_digest(root):
    h = hashlib.sha256()
    for dp, dn, fn in sorted(os.walk(root)):
        dn.sort()
        for n in sorted(fn):
            p = os.path.join(dp, n)
            h.update(os.path.relpath(p, root).encode())
            h.update(str(os.stat(p).st_mtime_ns).encode())
            with open(p, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-phase0-test-"))
try:
    # 1 benign: clean state -> precondition PASS, ledger PASS, gold PASS, overall precondition met
    print("== benign")
    st, gold = clean_state(os.path.join(T, "benign"))
    rc, out, err = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold], env={"PATH": "/usr/bin:/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x"})
    lines = parse_lines(out)
    cells = by_name(lines)
    ok("benign exit 0", rc == 0, err[:200])
    ok("benign 48h pass rate PASS", cells.get("pass_rate_48h", {}).get("verdict") == "PASS", json.dumps(cells.get("pass_rate_48h")))
    ok("benign 72h pass rate PASS", cells.get("pass_rate_72h", {}).get("verdict") == "PASS", json.dumps(cells.get("pass_rate_72h")))
    ok("benign pass rate value 80.0", cells.get("pass_rate_72h", {}).get("value") == 80.0, json.dumps(cells.get("pass_rate_72h")))
    ok("benign hygiene PASS", cells.get("hygiene_stall", {}).get("verdict") == "PASS", json.dumps(cells.get("hygiene_stall")))
    ok("benign ledger PASS (8 days)", cells.get("ledger_coverage", {}).get("verdict") == "PASS", json.dumps(cells.get("ledger_coverage")))
    ok("benign gold PASS (none pending)", cells.get("gold_open", {}).get("verdict") == "PASS", json.dumps(cells.get("gold_open")))
    ok("benign overall precondition met", lines[-1].get("precondition_met") is True and lines[-1].get("precondition") == "PASS", json.dumps(lines[-1]))
    ok("benign manual items NA", cells.get("manual_items", {}).get("verdict") == "NA")
    ok("benign escape events NA (info)", cells.get("escape_events", {}).get("verdict") == "NA")

    # 2 negative: a 3 h QA-block stall -> hygiene FAIL and precondition not met
    print("== stall negative")
    st, gold = clean_state(os.path.join(T, "stall"))
    rec = {"repo": "iptv_apps", "since": iso(NOW - 3 * 3600), "gate": "antigaming"}
    with open(os.path.join(st, "qa_blocked", "iptv_apps.json"), "w") as f:
        json.dump(rec, f)
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    lines = parse_lines(out)
    cells = by_name(lines)
    ok("stall 3h -> hygiene FAIL", cells.get("hygiene_stall", {}).get("verdict") == "FAIL", json.dumps(cells.get("hygiene_stall")))
    ok("stall value 3.0 h", cells.get("hygiene_stall", {}).get("value") == 3.0, json.dumps(cells.get("hygiene_stall")))
    ok("stall: precondition FAIL and not met", lines[-1].get("precondition") == "FAIL" and lines[-1].get("precondition_met") is False, json.dumps(lines[-1]))
    # benign stall control: 1 h stall -> PASS
    with open(os.path.join(st, "qa_blocked", "iptv_apps.json"), "w") as f:
        json.dump({"repo": "iptv_apps", "since": iso(NOW - 3600)}, f)
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("stall 1h -> hygiene PASS (benign control)", by_name(parse_lines(out)).get("hygiene_stall", {}).get("verdict") == "PASS")

    # 3 negative: 60 pct pass rate over 48 h and 72 h -> FAIL on both
    print("== pass-rate negative")
    root = os.path.join(T, "lowpass")
    st, gold = clean_state(root)
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(0, 72, 3), good=6, bad=4))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    cells = by_name(parse_lines(out))
    ok("60 pct -> pass_rate_48h FAIL", cells.get("pass_rate_48h", {}).get("verdict") == "FAIL", json.dumps(cells.get("pass_rate_48h")))
    ok("60 pct -> pass_rate_72h FAIL", cells.get("pass_rate_72h", {}).get("verdict") == "FAIL", json.dumps(cells.get("pass_rate_72h")))
    # benign boundary: exactly 75 pct -> PASS
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(0, 72, 3), good=3, bad=1))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("75 pct boundary -> PASS (benign control)", by_name(parse_lines(out)).get("pass_rate_72h", {}).get("verdict") == "PASS")
    # benign-only rows are not counted as a pass rate: UNVERIFIED, not PASS
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(0, 72, 3), good=0, bad=0, benign=5))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("only benign rows -> pass rate UNVERIFIED", by_name(parse_lines(out)).get("pass_rate_48h", {}).get("verdict") == "UNVERIFIED")
    # window edge: rows only older than 72 h do not count
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(80, 90, 2), good=5, bad=0))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("rows older than 72 h ignored -> UNVERIFIED", by_name(parse_lines(out)).get("pass_rate_72h", {}).get("verdict") == "UNVERIFIED")

    # 4 empty / missing state dir -> every machine cell UNVERIFIED, exit 0, nothing created
    print("== empty state")
    empty = os.path.join(T, "empty_state")
    os.makedirs(empty)
    before = tree_digest(T)
    rc, out, err = run_cli(["--state-dir", empty, "--now", str(NOW), "--gold", os.path.join(T, "no_gold.json")])
    lines = parse_lines(out)
    cells = by_name(lines)
    ok("empty state exit 0", rc == 0, err[:200])
    ok("empty: pass_rate_48h UNVERIFIED", cells.get("pass_rate_48h", {}).get("verdict") == "UNVERIFIED")
    ok("empty: pass_rate_72h UNVERIFIED", cells.get("pass_rate_72h", {}).get("verdict") == "UNVERIFIED")
    ok("empty: hygiene UNVERIFIED", cells.get("hygiene_stall", {}).get("verdict") == "UNVERIFIED")
    ok("empty: ledger UNVERIFIED", cells.get("ledger_coverage", {}).get("verdict") == "UNVERIFIED")
    ok("empty: gold UNVERIFIED", cells.get("gold_open", {}).get("verdict") == "UNVERIFIED")
    ok("empty: never PASS anywhere", not any(c.get("verdict") == "PASS" for c in lines), json.dumps(lines)[:300])
    ok("empty: overall UNVERIFIED", lines[-1].get("verdict") == "UNVERIFIED" and lines[-1].get("precondition_met") is False)
    ok("empty: nothing created under empty dir", sorted(os.listdir(empty)) == [], str(os.listdir(empty)))
    rc, out, _ = run_cli(["--state-dir", os.path.join(T, "does_not_exist"), "--now", str(NOW)])
    ok("nonexistent state dir exit 0 and no dir created", rc == 0 and not os.path.exists(os.path.join(T, "does_not_exist")))
    ok("empty run did not touch the fixture tree", tree_digest(T) == before)

    # 5 malformed JSON lines are skipped and counted, never fatal
    print("== malformed")
    root = os.path.join(T, "malformed")
    st, gold = clean_state(root)
    write_jsonl(os.path.join(st, "outcomes.jsonl"), outcome_rows(range(0, 72, 3), good=8, bad=2),
                raw_lines=["{not json", "[1,2,3]", '"just a string"', "{\"ts\": \"x\", \"severity\": "])
    rc, out, err = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    cells = by_name(parse_lines(out))
    ok("malformed exit 0", rc == 0, err[:200])
    ok("malformed: pass rate still computed (PASS)", cells.get("pass_rate_72h", {}).get("verdict") == "PASS", json.dumps(cells.get("pass_rate_72h")))
    ok("malformed: counted as FLAG outcomes_malformed=4", cells.get("outcomes_malformed", {}).get("value") == 4, json.dumps(cells.get("outcomes_malformed")))

    # 5b malformed qa_blocked record -> hygiene UNVERIFIED (cannot prove no stall), not PASS
    st2, gold2 = clean_state(os.path.join(T, "badblock"))
    with open(os.path.join(st2, "qa_blocked", "broken.json"), "w") as f:
        f.write("{oops")
    rc, out, _ = run_cli(["--state-dir", st2, "--now", str(NOW), "--gold", gold2])
    ok("unreadable block record -> hygiene UNVERIFIED", by_name(parse_lines(out)).get("hygiene_stall", {}).get("verdict") == "UNVERIFIED")

    # 6 ledger negative control: 3 days of ledger -> FLAG (not PASS)
    print("== ledger and gold")
    root = os.path.join(T, "shortledger")
    st, gold = clean_state(root)
    write_jsonl(os.path.join(st, "qa_ledger.jsonl"), ledger_rows(3.0))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("3 days of ledger -> FLAG", by_name(parse_lines(out)).get("ledger_coverage", {}).get("verdict") == "FLAG")

    # 7 gold pending rows counted
    root = os.path.join(T, "goldpending")
    st, gold = clean_state(root, gold_pending=("G9", "G10"))
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    cells = by_name(parse_lines(out))
    ok("two pending gold rows -> gold FLAG value 2", cells.get("gold_open", {}).get("verdict") == "FLAG" and cells.get("gold_open", {}).get("value") == 2,
       json.dumps(cells.get("gold_open")))
    ok("pending gold row is not a precondition failure", parse_lines(out)[-1].get("precondition") == "PASS")

    # 8 escape events counted in info cell (only strong types inside 30 days)
    root = os.path.join(T, "escapes")
    st, gold = clean_state(root)
    ev = [{"kind": "event", "key": "a", "type": "revert", "ts": iso(NOW - 2 * 86400), "repo": "billwatch"},
          {"kind": "event", "key": "b", "type": "hotfix", "ts": iso(NOW - 2 * 86400), "repo": "billwatch"},
          {"kind": "event", "key": "c", "type": "revert", "ts": iso(NOW - 90 * 86400), "repo": "billwatch"}]
    write_jsonl(os.path.join(st, "qa_ledger.jsonl"), ledger_rows(8.0) + ev)
    rc, out, _ = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    ok("one strong escape in 30 days counted (hotfix and old revert excluded)",
       by_name(parse_lines(out)).get("escape_events", {}).get("value") == 1)

    # 9 read-only proof: full tree digest unchanged after a run on a populated state
    print("== read-only")
    root = os.path.join(T, "readonly")
    st, gold = clean_state(root)
    write_jsonl(os.path.join(st, "qa_ledger.jsonl"), ledger_rows(8.0))
    d0 = tree_digest(root)
    run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold])
    d1 = tree_digest(root)
    ok("tree checksum unchanged after run (no-write proof)", d0 == d1)
    ok("no qa_shadow or qa_gate_modes created", not os.path.exists(os.path.join(st, "qa_shadow")) and not os.path.exists(os.path.join(st, "qa_gate_modes.json")))

    # 10 entry point: absolute and relative path under env -i, NTFY_SERVER set; no --now -> still runs
    print("== entry point")
    root = os.path.join(T, "entry")
    st, gold = clean_state(root)
    envmin = {"PATH": "/usr/bin:/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x", "OVN_DIR": root}
    rc_a, out_a, err_a = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold], env=envmin)
    ok("absolute path under env -i exit 0 and JSON", rc_a == 0 and parse_lines(out_a)[-1].get("criterion") == "overall", err_a[:200])
    rc_r, out_r, err_r = run_cli(["--state-dir", st, "--now", str(NOW), "--gold", gold], cwd=OVN, env=envmin, absolute=False)
    ok("relative path under env -i exit 0 and JSON", rc_r == 0 and parse_lines(out_r)[-1].get("criterion") == "overall", err_r[:200])
    ok("absolute and relative agree on verdicts", [json.loads(x).get("verdict") for x in out_a.splitlines()] == [json.loads(x).get("verdict") for x in out_r.splitlines()])
    rc_n, out_n, _ = run_cli(["--state-dir", st, "--now", "not-a-time"], env=envmin)
    ok("bad --now is UNVERIFIED overall, exit 0", rc_n == 0 and parse_lines(out_n)[-1].get("verdict") == "UNVERIFIED")
finally:
    shutil.rmtree(T, ignore_errors=True)

print("RESULT %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
