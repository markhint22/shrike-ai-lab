#!/usr/bin/env python3
"""Regression tests for ovn_godot_report.sh (lives at the overnight-queue repo root).
Run: python3 test_godot_report.py (exit 0 = all pass). No pytest dependency.

ovn_godot_report.sh reports xlite/godot pass-rate over 6h/24h/72h windows, filtering out
"noise" outcomes (queue-exhausted, model-api-error, timeout) that would otherwise make a
real capability look like it collapsed (see project_godot-overnight-0of20-was-a-reporting-
bug-2026-09-15.md — a real historical incident this exact filtering exists to prevent).
This file had ZERO test coverage before (flagged by ovn_pipeline_audit.sh's untested-active-
script check) despite being wired into cron (10 * * * *).

Runs the real .sh end-to-end against a fake $HOME/overnight-queue/state/outcomes.jsonl
fixture, since its logic is an inline python heredoc rather than an importable module.
"""
import os, sys, subprocess, tempfile, shutil, time, datetime

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
SCRIPT = os.path.join(ROOT, "ovn_godot_report.sh")

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def _iso(hours_ago):
    t = datetime.datetime.utcnow() - datetime.timedelta(hours=hours_ago)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def _mk_home(outcome_lines):
    home = tempfile.mkdtemp()
    ovn = os.path.join(home, "overnight-queue")
    os.makedirs(os.path.join(ovn, "state"), exist_ok=True)
    os.makedirs(os.path.join(ovn, "logs"), exist_ok=True)
    shutil.copy(SCRIPT, os.path.join(ovn, "ovn_godot_report.sh"))
    with open(os.path.join(ovn, "state", "outcomes.jsonl"), "w") as f:
        f.write("\n".join(outcome_lines) + "\n")
    return home, ovn


def _run(home):
    env = dict(os.environ, HOME=home)
    return subprocess.run(["bash", "ovn_godot_report.sh"], cwd=os.path.join(home, "overnight-queue"),
                           capture_output=True, text=True, env=env)


def _row(ts_hours_ago, category="godot", cls="landed", status="pushed(tests:pass)", fail_reason=""):
    import json
    return json.dumps({
        "ts": _iso(ts_hours_ago), "repo": "xlite", "type": "aider_fix",
        "category": category, "class": cls, "status": status, "fail_reason": fail_reason,
    })


def test_genuine_landed_and_reverted_are_counted_and_percentage_computed():
    rows = [_row(1, cls="landed"), _row(1, cls="landed"), _row(1, cls="reverted"), _row(1, cls="noop")]
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        ok("script exits 0", res.returncode == 0, res.stderr)
        six_h_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 6h]")), "")
        ok("6h window shows 4 genuine attempts", "genuine attempts=4" in six_h_line, six_h_line)
        ok("6h window shows 2 landed", "landed=2" in six_h_line, six_h_line)
        ok("6h window computes 50% land rate", "(50%)" in six_h_line, six_h_line)
        ok("6h window shows 1 reverted", "reverted=1" in six_h_line, six_h_line)
        ok("6h window shows 1 noop", "noop=1" in six_h_line, six_h_line)
    finally:
        shutil.rmtree(home)


def test_model_api_error_and_timeout_and_exhausted_are_filtered_as_noise():
    rows = [
        _row(1, cls="landed"),
        _row(1, cls="error", fail_reason="model-api-error"),
        _row(1, cls="error", fail_reason="timeout"),
        _row(1, cls="skipped", status="skip(exhausted) stage(higher-tier)"),
    ]
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        six_h_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 6h]")), "")
        ok("noise entries excluded from genuine attempts (only the 1 landed counts)",
           "genuine attempts=1" in six_h_line, six_h_line)
        ok("raw count still shows all 4", "raw=4" in six_h_line, six_h_line)
        ok("noise-filtered count shows 3", "filtered-noise=3" in six_h_line, six_h_line)
    finally:
        shutil.rmtree(home)


def test_zero_genuine_attempts_reports_explicitly_rather_than_dividing_by_zero():
    rows = [_row(1, cls="error", fail_reason="model-api-error")]
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        ok("script does not crash on all-noise input", res.returncode == 0, res.stderr)
        six_h_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 6h]")), "")
        ok("reports no genuine attempts instead of a ZeroDivisionError",
           "no genuine godot attempts" in six_h_line, six_h_line)
        ok("still surfaces the raw count", "raw=1" in six_h_line, six_h_line)
    finally:
        shutil.rmtree(home)


def test_non_godot_category_entries_are_excluded_entirely():
    rows = [_row(1, category="vue", cls="landed"), _row(1, category="godot", cls="landed")]
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        six_h_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 6h]")), "")
        ok("only the godot-category row is counted, not the vue one",
           "genuine attempts=1" in six_h_line, six_h_line)
    finally:
        shutil.rmtree(home)


def test_entries_outside_the_time_window_are_excluded():
    rows = [_row(1, cls="landed"), _row(48, cls="landed")]  # one inside 6h, one outside
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        six_h_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 6h]")), "")
        ok("6h window only counts the recent row", "genuine attempts=1" in six_h_line, six_h_line)
        day_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 24h]")), "")
        ok("24h window still only counts the recent row (the other is 48h old)",
           "genuine attempts=1" in day_line, day_line)
        three_day_line = next((l for l in res.stdout.splitlines() if l.startswith("[last 72h]")), "")
        ok("72h window counts both rows", "genuine attempts=2" in three_day_line, three_day_line)
    finally:
        shutil.rmtree(home)


def test_output_is_written_to_state_file_as_well_as_stdout():
    rows = [_row(1, cls="landed")]
    home, ovn = _mk_home(rows)
    try:
        res = _run(home)
        state_file = os.path.join(ovn, "state", "godot_report.txt")
        ok("state/godot_report.txt is written", os.path.isfile(state_file))
        if os.path.isfile(state_file):
            written = open(state_file).read()
            ok("state file content matches stdout (tee)", written.strip() == res.stdout.strip(),
               (written, res.stdout))
    finally:
        shutil.rmtree(home)


if __name__ == "__main__":
    if not os.path.isfile(SCRIPT):
        print("  (skip: %s not present on this host)" % SCRIPT)
        print("godot_report: 0 passed, 0 failed")
        sys.exit(0)
    for t in (test_genuine_landed_and_reverted_are_counted_and_percentage_computed,
              test_model_api_error_and_timeout_and_exhausted_are_filtered_as_noise,
              test_zero_genuine_attempts_reports_explicitly_rather_than_dividing_by_zero,
              test_non_godot_category_entries_are_excluded_entirely,
              test_entries_outside_the_time_window_are_excluded,
              test_output_is_written_to_state_file_as_well_as_stdout):
        print("== %s ==" % t.__name__)
        t()
    print("\ngodot_report: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
