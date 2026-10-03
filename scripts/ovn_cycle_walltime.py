#!/usr/bin/env python3
"""ovn_cycle_walltime.py — per-cycle wall-time ledger: where did each cycle's seconds go
(2026-10-03, Phase 6 observability).

WHY: the 2026-10-03 diagnosis found xlite cycles of ~2800s of which ~2700s was GUT VERIFY
sitting at its 900s timeout (3x per cycle) while the GPU idled (17 of 23 samples under 5%).
Nothing measured generation-vs-everything-else, so a loop that was 97% non-generation looked
like an ordinary slow cycle. This writes state/cycle_walltime.jsonl, one row per
outcomes.jsonl row, and alerts when a lane spends more than 50% of its cycle on non-generation
work three cycles running.

Per row: duration_s (as recorded) split into
  gen_s     model generation. Measured from state/stage_runs/<run>.jsonl step rows when the
            outcome names a stage_run (basis "stage_runs"); otherwise ESTIMATED from the row's
            token counts (tokens_sent / OVN_WT_PREFILL_TPS + tokens_recv / OVN_WT_DECODE_TPS,
            default 1500 / 25 tok/s; basis "est-tokens"). Cycle logs carry no per-phase
            timestamps, so a precise split is not recoverable for non-stage rows - the basis
            field says which one you are looking at.
  verify_s  seconds the cycle log PROVES were spent in verification: every
            "VERIFY timed out (rc=N) after Ns" it contains (a timeout is an exact, logged
            number). Verification that finished under its cap is not separately timed in the
            logs and lands in other_s.
  other_s   everything else (duration_s - gen_s - verify_s, floor 0).
nongen_frac = (duration_s - gen_s) / duration_s.

Incremental: byte-offset cursor on outcomes.jsonl (state/.cycle_walltime.cursor), exactly like
ovn_derive_legacy_logs.py; safe to run from cron every few minutes. Pure observability: never
edits anything but its own ledger/cursor/dedup files and one alerts.log line; exits 0.

Usage: ovn_cycle_walltime.py [state_dir=state] [logs_dir=logs] [--now EPOCH]
"""
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:  # reuse the triage's UTC-record -> local-run-dir correlation (verified against live data)
    import ovn_failure_triage as _tri
except Exception:  # fail-safe: without it, rows still get ledgered via the token estimate
    _tri = None

ALERT_FRAC = 0.5          # non-generation share that counts as "bad"
ALERT_STREAK = 3          # consecutive bad cycles of one lane
ALERT_DEDUP_S = 6 * 3600  # one alerts.log line per lane per 6h
MIN_DURATION_S = 30       # shorter rows are scout/skip noise, not a cycle worth judging
_TIMEOUT_RE = re.compile(r"VERIFY timed out \(rc=\d+\) after (\d+)s")


def _f(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def _epoch(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def _num(v):
    try:
        return max(0.0, float(v))
    except (TypeError, ValueError):
        return 0.0


def stage_gen_seconds(state_dir, run):
    """Sum of step duration_s in state/stage_runs/<run>.jsonl (step rows have no "event" key)."""
    if not run or not re.match(r"^[A-Za-z0-9_.-]+$", str(run)):
        return None
    d = os.path.join(state_dir, "stage_runs")
    # the file is named <repo>-<run>.jsonl; match on the run suffix
    try:
        names = [n for n in os.listdir(d) if n.endswith("-%s.jsonl" % run) or n == "%s.jsonl" % run]
    except OSError:
        return None
    total, found = 0.0, False
    for n in names:
        try:
            with open(os.path.join(d, n)) as f:
                for line in f:
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if isinstance(r, dict) and "event" not in r and "duration_s" in r:
                        total += _num(r.get("duration_s"))
                        found = True
        except OSError:
            continue
    return total if found else None


def log_verify_seconds(state_dir, logs_dir, rec, idx=None):
    """Seconds of logged verify timeouts for this row's cycle log (0.0 if none/unfindable).
    idx: a prebuilt _tri._build_run_dir_index(logs_dir); run() builds it ONCE (it costs ~0.15s
    on a 23k-entry logs/, so a per-row rebuild made the first live run take ~45 minutes)."""
    if _tri is None or not logs_dir or not os.path.isdir(logs_dir):
        return 0.0
    try:
        epoch = _tri._epoch_of_ts(rec.get("ts") or "")
        if not epoch:
            return 0.0
        if idx is None:
            idx = _tri._build_run_dir_index(logs_dir)
        path = _tri.find_task_log(logs_dir, idx, rec.get("id") or "?", epoch)
        if not path:
            return 0.0
        text = _tri._read_tail(path, max_bytes=800000)
    except Exception:
        return 0.0
    total = 0.0
    for line in text.splitlines():
        m = _TIMEOUT_RE.search(line)
        if m:
            total += float(m.group(1))
    return total


def split_row(state_dir, logs_dir, rec, idx=None):
    dur = _num(rec.get("duration_s"))
    verify = min(dur, log_verify_seconds(state_dir, logs_dir, rec, idx))
    gen = stage_gen_seconds(state_dir, rec.get("stage_run"))
    basis = "stage_runs"
    if gen is None:
        basis = "est-tokens"
        gen = (_num(rec.get("tokens_sent")) / max(1.0, _f("OVN_WT_PREFILL_TPS", 1500))
               + _num(rec.get("tokens_recv")) / max(1.0, _f("OVN_WT_DECODE_TPS", 25)))
    gen = min(gen, max(0.0, dur - verify))
    other = max(0.0, dur - gen - verify)
    frac = round((dur - gen) / dur, 3) if dur > 0 else 0.0
    return {
        "ts": rec.get("ts"), "repo": rec.get("repo") or "?", "id": rec.get("id") or "?",
        "status": rec.get("status") or "", "duration_s": round(dur), "gen_s": round(gen),
        "verify_s": round(verify), "other_s": round(other), "nongen_frac": frac, "basis": basis,
    }


def _read_ledger_tail(path, n=400):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 200000))
            lines = f.read().decode("utf-8", errors="replace").splitlines()
    except OSError:
        return []
    out = []
    for ln in lines[-n:]:
        try:
            r = json.loads(ln)
            if isinstance(r, dict):
                out.append(r)
        except Exception:
            continue
    return out


def check_alerts(state_dir, repos, now):
    """One alerts.log line per lane whose last ALERT_STREAK ledger rows are all above
    ALERT_FRAC non-generation; deduped per lane for ALERT_DEDUP_S. Returns the alert lines."""
    ledger = _read_ledger_tail(os.path.join(state_dir, "cycle_walltime.jsonl"))
    dedup_path = os.path.join(state_dir, ".cycle_walltime_alerted.json")
    try:
        with open(dedup_path) as f:
            dedup = json.load(f)
        if not isinstance(dedup, dict):
            dedup = {}
    except Exception:
        dedup = {}
    fired = []
    for repo in sorted(repos):
        rows = [r for r in ledger if r.get("repo") == repo and _num(r.get("duration_s")) >= MIN_DURATION_S]
        last = rows[-ALERT_STREAK:]
        if len(last) < ALERT_STREAK or not all(_num(r.get("nongen_frac")) > ALERT_FRAC for r in last):
            continue
        # token-count estimates alone (no stage_runs measurement, no logged verify timeout) can
        # undercount multi-attempt cycles; only alert on rows backed by a measured basis
        if not all(r.get("basis") == "stage_runs" or _num(r.get("verify_s")) > 0 for r in last):
            continue
        if now - _num(dedup.get(repo)) < ALERT_DEDUP_S:
            continue
        tot = sum(_num(r["duration_s"]) for r in last) or 1.0
        gen = sum(_num(r["gen_s"]) for r in last)
        ver = sum(_num(r["verify_s"]) for r in last)
        msg = ("cycle-walltime: %s spent %d%% of its last %d cycles outside model generation "
               "(gen %ds, logged verify timeouts %ds, other %ds of %ds) - the GPU is idle for that time"
               % (repo, round(100 * (tot - gen) / tot), ALERT_STREAK, gen, ver, tot - gen - ver, tot))
        line = "[%s] warn | ongoing-%s | %s" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), repo, msg)
        try:
            with open(os.path.join(state_dir, "alerts.log"), "a") as f:
                f.write(line + "\n")
        except OSError:
            continue
        dedup[repo] = now
        fired.append(line)
    if fired:
        try:
            with open(dedup_path + ".tmp", "w") as f:
                json.dump(dedup, f, sort_keys=True)
            os.replace(dedup_path + ".tmp", dedup_path)
        except OSError:
            pass
    return fired


def _flush(ledger_path, cursor, rows, pos):
    """Append rows then persist the cursor (ledger first: a crash between the two can only
    re-ledger <= one chunk, never lose rows)."""
    if rows:
        with open(ledger_path, "a") as f:
            for r in rows:
                f.write(json.dumps(r, sort_keys=True) + "\n")
    with open(cursor + ".tmp", "w") as f:
        f.write(str(pos))
    os.replace(cursor + ".tmp", cursor)


def run(state_dir, logs_dir, now=None):
    now = now if now is not None else time.time()
    outcomes = os.path.join(state_dir, "outcomes.jsonl")
    cursor = os.path.join(state_dir, ".cycle_walltime.cursor")
    ledger_path = os.path.join(state_dir, "cycle_walltime.jsonl")
    if not os.path.exists(outcomes):
        return {"rows": 0, "alerts": []}
    # single-instance: overlapping cron runs must not each append the same rows
    lock_f = None
    try:
        import fcntl
        lock_f = open(os.path.join(state_dir, ".cycle_walltime.lock"), "w")
        fcntl.flock(lock_f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except ImportError:
        pass
    except OSError:
        return {"rows": 0, "alerts": [], "locked": True}
    first_run = not os.path.exists(cursor)
    try:
        with open(cursor) as f:
            start = int(f.read().strip() or "0")
    except Exception:
        start = 0
    # first run: only backfill the last OVN_WT_BACKFILL_H hours (default 24); older rows are
    # skipped (cursor still advances past them) so a long history is never scanned per-row
    backfill_cut = now - _f("OVN_WT_BACKFILL_H", 24) * 3600 if first_run else 0.0
    max_rows = int(_f("OVN_WT_MAX_ROWS", 3000))   # per-run cap; the rest is picked up next run
    chunk = int(_f("OVN_WT_FLUSH_EVERY", 200))
    idx = None
    if _tri is not None and logs_dir and os.path.isdir(logs_dir):
        try:
            idx = _tri._build_run_dir_index(logs_dir)
        except Exception:
            idx = None
    out_rows, repos, total, pending = [], set(), 0, 0
    pos = start
    with open(outcomes, "rb") as f:
        f.seek(0, os.SEEK_END)
        end = f.tell()
        if start > end:
            start = 0
        f.seek(start)
        pos = start
        for raw in f:
            if not raw.endswith(b"\n"):
                break  # half-written line: pick it up next run
            pos += len(raw)
            pending += 1
            try:
                rec = json.loads(raw.decode("utf-8", errors="replace"))
            except Exception:
                continue
            if not isinstance(rec, dict) or _num(rec.get("duration_s")) <= 0:
                continue
            if backfill_cut and _epoch(rec.get("ts") or "") < backfill_cut:
                continue
            row = split_row(state_dir, logs_dir, rec, idx)
            out_rows.append(row)
            total += 1
            if row["duration_s"] >= MIN_DURATION_S:
                repos.add(row["repo"])
            if pending >= chunk:
                _flush(ledger_path, cursor, out_rows, pos)
                out_rows, pending = [], 0
            if total >= max_rows:
                break
    _flush(ledger_path, cursor, out_rows, pos)
    res = {"rows": total, "alerts": check_alerts(state_dir, repos, now)}
    if lock_f:
        lock_f.close()
    return res


def main(argv):
    args, now, i = [], None, 0
    while i < len(argv):
        if argv[i] == "--now" and i + 1 < len(argv):
            now = float(argv[i + 1]); i += 2
        else:
            args.append(argv[i]); i += 1
    state_dir = args[0] if args else "state"
    logs_dir = args[1] if len(args) > 1 else "logs"
    try:
        res = run(state_dir, logs_dir, now)
    except Exception as e:  # never raise out of a cron observability job
        print("ovn_cycle_walltime: %s" % e, file=sys.stderr)
        return 0
    print("cycle_walltime: %d new row(s), %d alert(s)" % (res["rows"], len(res["alerts"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
