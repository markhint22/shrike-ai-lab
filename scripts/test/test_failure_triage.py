#!/usr/bin/env python3
"""Regression tests for scripts/ovn_failure_triage.py — Phase 6c+6d of the pipeline-
hardening plan: proactive failure-signature clustering over state/outcomes.jsonl, so a
NEW class of failure (or a REGRESSION of one believed fixed) surfaces on its own instead
of requiring a human/agent to manually grep raw logs hours-to-days after the fact.
Run: python3 test_failure_triage.py   (exit 0 = all pass). No pytest dependency.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

SCRIPTS = os.environ.get("OVN_SCRIPTS", os.path.expanduser("~/overnight-queue/scripts"))
sys.path.insert(0, SCRIPTS)
SCRIPT = os.path.join(SCRIPTS, "ovn_failure_triage.py")

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def write_outcome(state_dir, ts, repo, status, severity, fail_reason="", item_hash="", record_id=None):
    rec = {
        "ts": ts, "repo": repo, "id": record_id or ("ongoing-%s" % repo),
        "type": "aider_fix", "tier": "2", "category": "test", "class": "reverted",
        "severity": severity, "attempt": 1, "fail_reason": fail_reason, "status": status,
        "tokens_sent": 1000, "tokens_recv": 100, "duration_s": 10,
        "item_hash": item_hash, "feat_tag": "",
    }
    with open(os.path.join(state_dir, "outcomes.jsonl"), "a") as f:
        f.write(json.dumps(rec) + "\n")



def ts_for(run_dir, plus_seconds=0):
    """UTC ISO timestamp that correctly correlates to a LOCAL-time-named run dir (the same
    conversion the triage script documents: dir names are local time, record ts is UTC)."""
    epoch = time.mktime(time.strptime(run_dir, "%Y%m%d-%H%M%S")) + plus_seconds
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))

def write_log(logs_dir, run_key, record_id, content):
    d = os.path.join(logs_dir, run_key)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "%s.log" % record_id), "w") as f:
        f.write(content)


def run_cli(state_dir, logs_dir, *extra_args, input_text=None):
    cmd = [sys.executable, SCRIPT, state_dir, logs_dir] + list(extra_args)
    return subprocess.run(cmd, capture_output=True, text=True, input=input_text)


def registry_of(state_dir):
    path = os.path.join(state_dir, "failure_clusters.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# extractor unit tests (direct import, no subprocess)
# ---------------------------------------------------------------------------

def test_extractors(m):
    kt = m.extract_signature("some noise\nFAILURE: No parameter with name 'userId' found\nmore noise\n")
    ok("kotlin no-param signature is non-empty and normalized", bool(kt) and "<X>" in kt, kt)

    gd = m.extract_signature("Godot output\nSCRIPT ERROR: Invalid get index 'hp' (on base: 'Dictionary') at line 88\ndone\n")
    ok("gdscript SCRIPT ERROR signature is non-empty", bool(gd) and gd.startswith("gdscript:"), gd)

    py1 = m.extract_signature("collecting...\nFAILED tests/test_x.py::test_thing - AssertionError: assert 1 == 2\n")
    ok("python pytest-FAILED signature is non-empty", bool(py1) and py1.startswith("python:"), py1)

    py2 = m.extract_signature("Traceback (most recent call last):\n  File \"x.py\", line 3\nValueError: invalid literal for int() with base 10: '12x'\n")
    ok("python exception-class signature is non-empty", bool(py2) and py2.startswith("python:ValueError"), py2)

    js1 = m.extract_signature("running vitest\nFAIL src/components/Foo.test.ts > renders\n")
    ok("js FAIL-line signature is non-empty", bool(js1) and js1.startswith("js:"), js1)

    js2 = m.extract_signature("vite v5 building...\n[plugin vite:vue] src/pages/Detail.vue: Single file component can contain only one <template> element\n")
    ok("js vite-plugin build-error signature is non-empty", bool(js2) and js2.startswith("js:"), js2)

    aider = m.extract_signature("applying patch\nSearchReplaceNoExactMatch: no match found\n")
    ok("aider diff-no-exact-match signature is stable/fixed-shape", aider == "aider:diff-no-exact-match", aider)

    fb = m.extract_signature("completely unrecognized log content\nwith no known error shape\njust noise\n")
    ok("generic fallback still produces a non-empty signature", bool(fb) and fb.startswith("generic:tail-hash:"), fb)

    # two DIFFERENT normalized inputs of the SAME shape collapse to the same signature
    a = m.extract_signature("FAILURE: No parameter with name 'userId' found\n")
    b = m.extract_signature("FAILURE: No parameter with name 'groupId' found\n")
    ok("same failure SHAPE with different param names clusters to one signature", a == b, "%r != %r" % (a, b))


def test_normalize_collapses_specifics(m):
    a = m.normalize("Error at /home/user/repo/app/foo.py line 42, commit a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")
    b = m.normalize("Error at /home/user/repo/app/bar.py line 99, commit ffffffffffffffffffffffffffffffffffffff")
    ok("paths/line-numbers/hashes normalize to the same shape", a == b, "%r != %r" % (a, b))


def test_fallback_signature_clusters_same_shape(m):
    """2026-09-29: the generic fallback used to hash the RAW last 5 lines, so two logs that
    differ only in counts/paths/hashes/quoted names got different signatures and every
    unclassifiable failure became its own 'new' cluster. It now normalizes first."""
    a = m.extract_signature(
        "unknown tool chatter\nApplied edit to /home/u/repo-a/app/foo.py\n"
        "model said: could not reconcile 'alpha_module' after 3 attempts (commit a1b2c3d4e5f6a1b2)\n"
        "Tokens: 14k sent, 294 received.\n")
    b = m.extract_signature(
        "unknown tool chatter\nApplied edit to /home/u/repo-b/app/bar.py\n"
        "model said: could not reconcile 'beta_module' after 7 attempts (commit ffffffffffffffff)\n"
        "Tokens: 80k sent, 9 received.\n")
    ok("same unclassifiable shape with different specifics clusters to ONE fallback signature",
       a == b and a.startswith("generic:tail-hash:"), "%r != %r" % (a, b))
    c = m.extract_signature(
        "unknown tool chatter\nApplied edit to /home/u/repo-a/app/foo.py\n"
        "the build tool crashed with a completely different kind of message\n")
    ok("a genuinely different unclassifiable shape still gets a DIFFERENT fallback signature",
       c != a and c.startswith("generic:tail-hash:"), "%r == %r" % (c, a))


def test_pipeline_marker_extractor(m):
    """The pipeline's own terminal verdict lines are the best signatures available (2026-09-29:
    70% of first-run failures fell to the generic fallback because it discarded them)."""
    bg1 = m.extract_signature("<testsuites>...</testsuites>TSC-RATCHET-SKIP\n--- BUILD-GATE: commit structurally broke the build \u2014 reverting to e71b0e8c37b811c2e7708b1491edafc4a2bf9501 ---\n")
    bg2 = m.extract_signature("<testsuites>...</testsuites>\n--- BUILD-GATE: commit structurally broke the build \u2014 reverting to b8ce648768df5cb92806f7da705614a5c8585d47 ---\n")
    ok("build-gate marker gives a plain-language pipeline signature", bg1.startswith("pipeline:build-gate:"), bg1)
    ok("same marker with different commit hashes clusters to ONE signature", bg1 == bg2, "%r != %r" % (bg1, bg2))

    later = m.extract_signature("verify FAILED \u2014 repair round 1/2 (recovering 2 changed file(s))\n--- BUILD-GATE: commit structurally broke the build \u2014 reverting to abc1234 ---\n")
    earlier = m.extract_signature("--- BUILD-GATE: commit structurally broke the build \u2014 reverting to abc1234 ---\nverify FAILED \u2014 repair round 2/2 (recovering 1 changed file(s))\n")
    ok("the LAST verdict in the log wins (build-gate last)", later.startswith("pipeline:build-gate:"), later)
    ok("the LAST verdict in the log wins (verify-failed last)", earlier.startswith("pipeline:verify:"), earlier)

    dc = m.extract_signature("2026-09-21 03:07:21 [xlite] decompose produced no steps \u2014 abort\nTokens: 0 sent, 0 received\n")
    ok("decompose-no-steps marker", dc.startswith("pipeline:decompose:"), dc)
    cap = m.extract_signature("2026-09-28 07:59:41 [xlite] regression-check FAILED \u2014 a real regression, NOT auto-retrying (see /tmp/x.log)\n")
    ok("capstone regression marker", cap.startswith("pipeline:capstone:"), cap)

    spec = m.extract_signature("FAILED tests/test_x.py::test_y - AssertionError: nope\n--- NO-NEW-RED GUARD: commit left the suite red (a source change broke a previously-green test) \u2014 reverting ---\n")
    ok("a specific pytest signature still outranks the generic pipeline label", spec.startswith("python:pytest-failed"), spec)

    none = m.extract_signature("just some model prose\nwith no verdict line at all\n")
    ok("no marker -> generic fallback still applies", none.startswith("generic:tail-hash:"), none)


# ---------------------------------------------------------------------------
# end-to-end CLI tests via synthetic outcomes.jsonl + logs/
# ---------------------------------------------------------------------------

def test_new_cluster_created():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "some output\nFAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T10:05:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash1")
        res = run_cli(state, logs)
        ok("detect pass exits 0", res.returncode == 0, res.stderr)
        reg = registry_of(state)
        ok("exactly one cluster created", len(reg) == 1, reg)
        entry = list(reg.values())[0]
        ok("new cluster has status=new", entry["status"] == "new", entry)
        ok("new cluster count starts at 1", entry["count"] == 1, entry)
        ok("new cluster records the sample item_hash", "hash1" in entry.get("sample_item_hashes", []), entry)
        ok("stdout reports the new cluster", "new failure cluster" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_flail_clusters_by_status_when_log_is_unclassifiable():
    """A bare 'no-op' outcome (model tried, no usable diff) has a log that just ends in the
    model's own varying prose — text can never cluster it. It should cluster by STATUS instead:
    one meaningful 'flail' cluster per repo, not one hash cluster per event (2026-09-29)."""
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "I will now add a test for the widget.\n * with pytest.raises(ImportError):\nTokens: 40k sent, 513 received.\nCREDITED=0\n")
        write_log(logs, "20260101-110000", "ongoing-testrepo",
                  "Different prose entirely about the gadget module and its 7 helpers.\nTokens: 13k sent, 1.1k received.\nCREDITED=0\n")
        write_outcome(state, ts_for("20260101-100000", 1200), "testrepo", "no-op", "bad", fail_reason="unknown", item_hash="h1")
        write_outcome(state, ts_for("20260101-110000", 1200), "testrepo", "no-op", "bad", fail_reason="unknown", item_hash="h2")
        res = run_cli(state, logs)
        ok("detect pass exits 0", res.returncode == 0, res.stderr)
        reg = registry_of(state)
        ok("two differently-worded flails collapse to ONE cluster", len(reg) == 1, list(reg))
        key = list(reg)[0]
        ok("that cluster is the readable flail label, not a tail-hash", "pipeline:flail:" in key and "tail-hash" not in key, key)
        ok("it counted both events", reg[key]["count"] == 2, reg[key])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_status_signature_only_applies_to_bare_noop_and_never_overrides_a_real_signature():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        # bare no-op whose log DOES contain a real pytest failure: the specific signature must win
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, ts_for("20260101-100000", 1200), "testrepo", "no-op", "bad", fail_reason="unknown", item_hash="h1")
        run_cli(state, logs)
        keys = list(registry_of(state))
        ok("a real extractor signature is NOT overridden by the status fallback",
           len(keys) == 1 and "python:pytest-failed" in keys[0], keys)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_repeat_increments_no_duplicate():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T10:05:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash1")
        run_cli(state, logs)

        write_log(logs, "20260101-103000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T10:35:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash2")
        res = run_cli(state, logs)

        reg = registry_of(state)
        ok("repeat of the same signature does not create a duplicate entry", len(reg) == 1, reg)
        entry = list(reg.values())[0]
        ok("count incremented to 2 on repeat", entry["count"] == 2, entry)
        ok("second sample item_hash appended", set(entry["sample_item_hashes"]) == {"hash1", "hash2"}, entry)
        ok("no new-cluster line printed on a pure repeat", "new failure cluster" not in res.stdout, res.stdout)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_ack_transitions_to_fixed():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T10:05:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash1")
        run_cli(state, logs)
        reg = registry_of(state)
        key = list(reg.keys())[0]
        sig_partial = key.split("::", 1)[1][:20]

        res = run_cli(state, logs, "--ack", "testrepo", sig_partial,
                       "--commit", "abc1234", "--generator-addressed", "yes", "--yes")
        ok("--ack exits 0", res.returncode == 0, res.stderr)
        reg2 = registry_of(state)
        entry = reg2[key]
        ok("status transitioned to fixed", entry["status"] == "fixed", entry)
        ok("fix_commit recorded", entry["fix_commit"] == "abc1234", entry)
        ok("generator_addressed recorded", entry["generator_addressed"] == "yes", entry)

        res_bad = run_cli(state, logs, "--ack", "testrepo", "zzz-no-such-signature-zzz",
                           "--commit", "x", "--generator-addressed", "unsure", "--yes")
        ok("--ack with no match exits non-zero", res_bad.returncode != 0, res_bad.stdout + res_bad.stderr)

        res_noconfirm = run_cli(state, logs, "--ack", "testrepo", sig_partial,
                                 "--commit", "def5678", "--generator-addressed", "no")
        ok("--ack without --yes in non-interactive shell refuses to apply",
           res_noconfirm.returncode != 0, res_noconfirm.stdout + res_noconfirm.stderr)
        reg3 = registry_of(state)
        ok("refused ack left the entry unchanged", reg3[key]["fix_commit"] == "abc1234", reg3[key])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_regression_flagged_after_fixed():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T10:05:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash1")
        run_cli(state, logs)
        reg = registry_of(state)
        key = list(reg.keys())[0]
        sig_partial = key.split("::", 1)[1][:20]
        run_cli(state, logs, "--ack", "testrepo", sig_partial,
                "--commit", "abc1234", "--generator-addressed", "yes", "--yes")
        ok("precondition: cluster is fixed before the recurrence", registry_of(state)[key]["status"] == "fixed")

        # the SAME failure shape recurs later
        write_log(logs, "20260101-120000", "ongoing-testrepo",
                  "FAILED tests/test_a.py::test_one - AssertionError: assert 1 == 2\n")
        write_outcome(state, "2026-01-01T12:05:00Z", "testrepo", "no-op(reverted-red)", "bad",
                      fail_reason="test-red", item_hash="hash3")
        res = run_cli(state, logs)

        ok("regression is reported in stdout", "REGRESSION" in res.stdout, res.stdout)
        entry = registry_of(state)[key]
        ok("status remains fixed (human must re-ack, not auto-reset)", entry["status"] == "fixed", entry)
        ok("count incremented across the regression", entry["count"] == 2, entry)
        ok("regression_events recorded the recurrence", len(entry.get("regression_events", [])) == 1, entry)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_digest_mode_is_readonly_and_window_scoped():
    """digest_notify.sh's 3-hourly rollup calls --digest HOURS — must be read-only (does not
    advance the cursor / mutate the registry) and only reports a cluster as NEW if it was
    actually first created inside the requested window."""
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        now_run_key = time.strftime("%Y%m%d-%H%M%S", time.localtime())
        now_ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        write_log(logs, now_run_key, "ongoing-testrepo", "FAILED tests/test_a.py::test_one - x\n")
        write_outcome(state, now_ts, "testrepo", "no-op(reverted-red)", "bad")
        run_cli(state, logs)
        reg_before = registry_of(state)

        res = run_cli(state, logs, "--digest", "3")
        ok("--digest exits 0", res.returncode == 0, res.stderr)
        ok("--digest reports the cluster as NEW when created just now (within a 3h window)",
           "NEW:" in res.stdout, res.stdout)
        reg_after = registry_of(state)
        ok("--digest does not mutate the registry", reg_before == reg_after, (reg_before, reg_after))

        # a cluster "born" long before the window should not be re-announced as NEW forever
        state2 = os.path.join(tmp, "state2"); os.makedirs(state2)
        write_outcome(state2, "2020-01-01T00:00:00Z", "oldrepo", "no-op(reverted-red)", "bad",
                      fail_reason="ancient-cause")
        run_cli(state2, logs)
        res_old = run_cli(state2, logs, "--digest", "3")
        ok("a cluster first-seen long before the window is not re-announced as NEW",
           "oldrepo" not in res_old.stdout, res_old.stdout)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_cursor_incremental_no_reprocessing():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_log(logs, "20260101-100000", "ongoing-testrepo", "FAILED tests/test_a.py::test_one - x\n")
        write_outcome(state, "2026-01-01T10:05:00Z", "testrepo", "no-op(reverted-red)", "bad", item_hash="hash1")
        run_cli(state, logs)
        reg1 = registry_of(state)
        entry1 = list(reg1.values())[0]
        res2 = run_cli(state, logs)  # no new records
        ok("second run with no new records reports nothing new",
           "no new outcomes.jsonl records" in res2.stdout, res2.stdout)
        reg2 = registry_of(state)
        entry2 = list(reg2.values())[0]
        ok("re-running with no new records does not double-count", entry2["count"] == entry1["count"] == 1, entry2)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_benign_and_good_records_ignored():
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        write_outcome(state, "2026-01-01T10:00:00Z", "testrepo", "pushed(tests:pass)", "good")
        write_outcome(state, "2026-01-01T10:01:00Z", "testrepo", "no-op(ALREADY-DONE)", "neutral")
        write_outcome(state, "2026-01-01T10:02:00Z", "testrepo", "skip(exhausted)", "expected")
        res = run_cli(state, logs)
        reg = registry_of(state)
        ok("good/benign records create zero clusters", len(reg) == 0, reg)
        ok("processed count still reflects all 3 records read", "processed 3 new record" in res.stdout, res.stdout)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_log_correlation_picks_correct_run_dir():
    """Mirrors the real live-data shape verified on the GPU box (2026-09-29): the run-dir
    with the LARGEST start-epoch <= the record's converted-to-local epoch, not an earlier
    or later one, and falls back to no-log: when nothing is close enough."""
    tmp = tempfile.mkdtemp()
    try:
        state = os.path.join(tmp, "state"); logs = os.path.join(tmp, "logs")
        os.makedirs(state); os.makedirs(logs)
        # two candidate run dirs; only the later one (still before the record) has the log
        write_log(logs, "20260101-090000", "ongoing-testrepo", "unrelated older cycle\n")
        write_log(logs, "20260101-095000", "ongoing-testrepo", "FAILED tests/test_x.py::test_y - RealSignatureHere\n")
        local_struct = time.localtime(time.mktime(time.strptime("20260101-100000", "%Y%m%d-%H%M%S")))
        # record ts is 10 minutes after the 09:50 run-dir started, converted through UTC
        # using the box's own offset so this test is timezone-independent.
        utc_epoch = time.mktime(time.strptime("20260101-100000", "%Y%m%d-%H%M%S"))
        ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(utc_epoch))
        write_outcome(state, ts, "testrepo", "no-op(reverted-red)", "bad", fail_reason="test-red")
        res = run_cli(state, logs)
        reg = registry_of(state)
        keys = list(reg.keys())
        ok("resolved signature came from the REAL log content, not the no-log fallback",
           any("RealSignatureHere" in k or "python:" in k for k in keys), (keys, res.stdout))

        # a record far outside the lookback window falls back to no-log:
        state2 = os.path.join(tmp, "state2"); os.makedirs(state2)
        far_ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(utc_epoch + 20 * 3600))
        write_outcome(state2, far_ts, "testrepo", "no-op(reverted-red)", "bad", fail_reason="mystery-cause")
        run_cli(state2, logs)
        reg2 = registry_of(state2)
        keys2 = list(reg2.keys())
        ok("no matching run-dir within lookback falls back to a no-log: signature",
           any(k.split("::", 1)[1].startswith("no-log:") for k in keys2), keys2)
        ok("no-log fallback signature still carries the real fail_reason",
           any("mystery-cause" in k for k in keys2), keys2)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    if not os.path.exists(SCRIPT):
        print("  SKIP: ovn_failure_triage.py not found at %s" % SCRIPT)
        print("failure_triage: 0 passed, 0 failed")
        sys.exit(0)
    try:
        import ovn_failure_triage as m
    except ImportError as e:
        print("  SKIP: ovn_failure_triage.py not importable (%s)" % e)
        print("failure_triage: 0 passed, 0 failed")
        sys.exit(0)

    for t in (test_extractors, test_normalize_collapses_specifics, test_fallback_signature_clusters_same_shape,
              test_pipeline_marker_extractor):
        print("== %s ==" % t.__name__)
        t(m)

    for t in (test_new_cluster_created,
              test_flail_clusters_by_status_when_log_is_unclassifiable,
              test_status_signature_only_applies_to_bare_noop_and_never_overrides_a_real_signature,
              test_repeat_increments_no_duplicate,
              test_ack_transitions_to_fixed,
              test_regression_flagged_after_fixed,
              test_digest_mode_is_readonly_and_window_scoped,
              test_cursor_incremental_no_reprocessing,
              test_benign_and_good_records_ignored,
              test_log_correlation_picks_correct_run_dir):
        print("== %s ==" % t.__name__)
        t()

    print("\nfailure_triage: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
