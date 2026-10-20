#!/usr/bin/env python3
"""Tests for scripts/ovn_gate_governor.py (package L3-gate-governor, 2026-10-18). Run by test_ovn_gate_governor.sh (and directly: python3 test_ovn_gate_governor.py).

Evidence shapes are the REAL ones read from the GPU box journals on 2026-10-18 (fixtures_gate_governor/: four stage_runs journals incl. the item_verify `refuse:` + pushed shape that let
~27 false credits land, outcomes.jsonl, stage_credited.ledger, qa_shadow rows, shadow logs, task-log lines); synthetic journals are used where a scenario needs an exact count.

Every behaviour that protects the pipeline has a MUTANT: the scenario passes against the real governor and FAILS against a copy with the guard removed (class TestMutants). Stale mutants
(the text to mutate is no longer in the source exactly once) fail the suite, so a refactor cannot silently turn a mutant test into a no-op.
Pure stdlib; every temp dir is a tempfile.TemporaryDirectory under TMPDIR (run_all.sh points TMPDIR at a private disk-backed dir).
"""
import calendar
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import warnings

warnings.simplefilter("ignore", ResourceWarning)   # the one-line open(..).read() helpers in these tests are throw-away
HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.dirname(os.path.dirname(HERE))
GOV = os.path.join(OVN, "scripts", "ovn_gate_governor.py")
WRAP = os.path.join(OVN, "scripts", "ovn_gate_governor.sh")
REG = os.path.join(OVN, "ops", "gate_registry.json")
FIX = os.path.join(HERE, "fixtures_gate_governor")
NOW = calendar.timegm((2026, 10, 19, 0, 55, 0, 0, 0, 0))   # just after the newest fixture journal
GITENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t.com", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t.com", "GIT_CONFIG_NOSYSTEM": "1"}


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def runid(ts, pid=1111):
    return time.strftime("%Y%m%d-%H%M%S", time.gmtime(ts)) + "-%d" % pid


class Box:
    """A throw-away queue root: <root>/state, <root>/ops/gate_registry.json, <root>/logs."""

    def __init__(self, registry=None, gov=GOV):
        self.td = tempfile.TemporaryDirectory(prefix="gg_test.")
        self.root = os.path.realpath(self.td.name)
        self.state = os.path.join(self.root, "state")
        os.makedirs(self.state)
        os.makedirs(os.path.join(self.root, "ops"))
        os.makedirs(os.path.join(self.root, "logs"))
        os.makedirs(os.path.join(self.root, "scripts"))
        shutil.copy(os.path.join(OVN, "scripts", "ovn_landing_quality.py"), os.path.join(self.root, "scripts", "ovn_landing_quality.py"))   # source of the default enforced LQ rules
        self.reg = os.path.join(self.root, "ops", "gate_registry.json")
        shutil.copy(registry or REG, self.reg)
        self.gov = gov
        self.env_extra = {}
        self.n = 0

    def close(self):
        self.td.cleanup()

    @property
    def flags(self):
        return os.path.join(self.state, "pilot_flags.env")

    def env(self, **kw):
        e = {k: v for k, v in os.environ.items() if not k.startswith(("OVN_", "QA_"))}
        e.update(OVN_DIR=self.root, OVN_GG_STATE=self.state, OVN_GG_REGISTRY=self.reg, OVN_GG_NOW=str(NOW), OVN_GG_GIT="0", OVN_GG_WHO="test@gg", TZ="UTC")
        e.update(self.env_extra)
        e.update(kw)
        return e

    def run(self, *args, **kw):
        p = subprocess.run([sys.executable, "-I", self.gov] + list(args), capture_output=True, text=True, env=self.env(**kw), timeout=120)
        return p.returncode, p.stdout + p.stderr

    def report(self, gate, days=14, extra=()):
        rc, out = self.run("report", "--gate", gate, "--days", str(days), "--json", *extra)
        assert rc == 0, out
        return json.loads(out)[0]

    def flags_text(self):
        try:
            return open(self.flags).read()
        except OSError:
            return None

    def write_flags(self, text):
        with open(self.flags, "w") as f:
            f.write(text)

    # --- seeding
    def seed_fixture(self):
        for sub in ("stage_runs", "qa_shadow"):
            shutil.copytree(os.path.join(FIX, sub), os.path.join(self.state, sub))
        for fn in ("outcomes.jsonl", "stage_credited.ledger"):
            shutil.copy(os.path.join(FIX, fn), os.path.join(self.state, fn))
        for fn in os.listdir(FIX):
            if fn.endswith(".log.txt"):
                dst = os.path.join(self.state, fn[:-4])
                shutil.copy(os.path.join(FIX, fn), dst)
                os.utime(dst, (NOW, NOW))
        d = os.path.join(self.root, "logs", "20261018-034847")
        os.makedirs(d)
        shutil.copy(os.path.join(FIX, "tasklog_lines.txt"), os.path.join(d, "ongoing-xlite.log"))

    def journal(self, repo, item, ts, events, pushed=0, verified=True):
        """A stage run journal in the real shape: decomposed first line (repo+item), events, summary."""
        self.n += 1
        rid = runid(ts, 5000 + self.n)
        fn = "%s-%s.jsonl" % (repo, rid)
        lines = [{"run": rid, "repo": repo, "tier": 4, "item": item, "event": "decomposed", "steps": 1}]
        lines += [dict(e, run=rid) for e in events]
        lines.append({"run": rid, "event": "summary", "tier": 4, "passed": 1, "total": 1, "verified": verified, "commits_pushed": pushed})
        d = os.path.join(self.state, "stage_runs")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, fn), "w") as f:
            f.write("".join(json.dumps(x) + "\n" for x in lines))
        return fn

    def outcome(self, repo, ts, cls, item_hash="", status="", **kw):
        r = {"ts": iso(ts), "repo": repo, "id": "ongoing-" + repo, "class": cls, "status": status or cls, "item_hash": item_hash}
        r.update(kw)
        with open(os.path.join(self.state, "outcomes.jsonl"), "a") as f:
            f.write(json.dumps(r) + "\n")

    def mistarget_evidence(self, n=25, span_days=6.0, newest_age_h=1.0):
        """n item-mistarget(shadow) lines (real shape of state/stage_guards_shadow.log) spread over span_days, newest newest_age_h before NOW."""
        lines = []
        for i in range(n):
            ts = NOW - newest_age_h * 3600 - (span_days * 86400.0) * (1 - i / float(max(1, n - 1)))
            lines.append("%s item-mistarget(shadow) repo=stage-gitlark.ab%02d :: the item's own VERIFY greps non-existent file(s) backend/x%02d.py (not created by the item) :: [T4] backend/x%02d.py - verify it" % (iso(ts), i, i, i))
        with open(os.path.join(self.state, "stage_guards_shadow.log"), "w") as f:
            f.write("\n".join(lines) + "\n")
        return lines

    def label_all(self, gate, n, fp=0, days=14):
        rep = self.report(gate, days, ["--candidates", "200"])
        keys = [c["key"] for c in rep["fp_candidates"]]
        assert len(keys) >= n, (len(keys), n)
        for i, k in enumerate(keys[:n]):
            rc, out = self.run("label", gate, k, "fp" if i < fp else "tp")
            assert rc == 0, out

    def make_promotable(self, gate="item_mistarget", labelled=20, fp=0):
        self.mistarget_evidence()
        self.label_all(gate, labelled, fp)
        assert self.run("attest", gate, "replay", "--ref", "replayed 5 days of journals")[0] == 0
        assert self.run("attest", gate, "cost", "--ref", "timed on the box", "--p90-s", "3")[0] == 0


def load_module(path, box):
    spec = importlib.util.spec_from_file_location("gg_mod_%d" % abs(hash(path)), path)
    m = importlib.util.module_from_spec(spec)
    old = {k: os.environ.get(k) for k in ("OVN_DIR", "OVN_GG_STATE", "OVN_GG_NOW", "OVN_GG_REGISTRY")}
    os.environ.update(OVN_DIR=box.root, OVN_GG_STATE=box.state, OVN_GG_NOW=str(NOW), OVN_GG_REGISTRY=box.reg)
    try:
        spec.loader.exec_module(m)
    finally:
        pass
    m._restore_env = old
    return m


def restore_env(m):
    for k, v in m._restore_env.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
# scenarios: each takes a governor path and returns True when the guarded behaviour holds. Used by the plain tests (real governor) AND by the mutant tests (mutated copy must FAIL).
# ----------------------------------------------------------------------------------------------------------------------------------------------------------------
def s_promote_refuses_without_evidence(gov):
    b = Box(gov=gov)
    try:
        b.mistarget_evidence()
        rc, out = b.run("promote", "item_mistarget", "--apply")
        return rc == 1 and "REFUSED" in out and b.flags_text() is None
    finally:
        b.close()


def s_promote_applies_when_criteria_met(gov):
    b = Box(gov=gov)
    try:
        b.make_promotable()
        rc, out = b.run("promote", "item_mistarget", "--apply")
        t = b.flags_text() or ""
        return rc == 0 and "export OVN_STAGE_ITEM_MISTARGET='enforce'" in t and "gate-governor" in t and "rollback" in out.lower()
    finally:
        b.close()


def s_19_labels_refused(gov):
    b = Box(gov=gov)
    try:
        b.make_promotable(labelled=19)
        rc, out = b.run("promote", "item_mistarget", "--apply")
        return rc == 1 and b.flags_text() is None
    finally:
        b.close()


def s_one_fp_in_20_refused(gov):
    """exactly 5% FP is NOT below 5%"""
    b = Box(gov=gov)
    try:
        b.make_promotable(labelled=20, fp=1)
        rc, out = b.run("promote", "item_mistarget", "--apply")
        return rc == 1 and b.flags_text() is None
    finally:
        b.close()


def s_stale_evidence_refused(gov):
    b = Box(gov=gov)
    try:
        b.mistarget_evidence(newest_age_h=24 * 4)   # newest shadow row 4 days old
        b.label_all("item_mistarget", 20, 0, days=30)
        b.run("attest", "item_mistarget", "replay", "--ref", "x")
        b.run("attest", "item_mistarget", "cost", "--ref", "x", "--p90-s", "3")
        rc, out = b.run("promote", "item_mistarget", "--apply", OVN_GG_PROMO_DAYS="30")
        return rc == 1 and b.flags_text() is None
    finally:
        b.close()


def s_override_needs_flag_and_reason(gov):
    b = Box(gov=gov)
    try:
        b.mistarget_evidence()
        rc1, _ = b.run("promote", "item_mistarget", "--apply", "--i-checked-the-samples")   # no reason
        no_write = b.flags_text() is None
        rc2, out2 = b.run("promote", "item_mistarget", "--apply", "--i-checked-the-samples", "--reason", "read all 25 samples by hand")
        aud = [json.loads(x) for x in open(os.path.join(b.state, "gate_governor", "audit.jsonl"))]
        ov = [a for a in aud if a.get("action") == "promote"]
        return rc1 == 1 and no_write and rc2 == 0 and "OVERRIDE" in out2 and ov and ov[-1]["override"] is True and ov[-1]["unmet"] and "read all 25" in ov[-1]["reason"]
    finally:
        b.close()


def s_non_pilot_channels_never_written(gov):
    """qa gates belong to qa_enforce.sh, cron-launched gates never see pilot_flags.env: the governor refuses (override flag or not) and says what to do instead"""
    b = Box(gov=gov)
    try:
        b.seed_fixture()
        rc, out = b.run("promote", "qa:baseline", "--apply", "--i-checked-the-samples", "--reason", "x")
        rc2, out2 = b.run("promote", "verify_lint", "--apply", "--i-checked-the-samples", "--reason", "x")
        return (rc == 1 and "qa_enforce.sh" in out and rc2 == 1 and "never source" in out2 and "OVN_VERIFY_LINT=enforce" in out2 and b.flags_text() is None
                and not os.path.exists(os.path.join(b.state, "qa_gate_modes.json")))
    finally:
        b.close()


def s_rollback_restores_byte_identical(gov):
    b = Box(gov=gov)
    try:
        orig = "export OVN_ARCHITECT=1\n# hand written\nOVN_BESTOF_N=3\n"
        b.write_flags(orig)
        rc, out = b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "test")
        changed = b.flags_text() != orig
        rc2, out2 = b.run("rollback", "--apply")
        return rc == 0 and changed and rc2 == 0 and b.flags_text() == orig and "VERIFIED" in out2
    finally:
        b.close()


def s_rollback_to_absent(gov):
    b = Box(gov=gov)
    try:
        rc, _ = b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "test")
        existed = os.path.exists(b.flags)
        rc2, out2 = b.run("rollback", "--apply")
        return rc == 0 and existed and rc2 == 0 and not os.path.exists(b.flags)
    finally:
        b.close()


def s_other_lines_preserved(gov):
    b = Box(gov=gov)
    try:
        b.write_flags("# keep me\nexport OVN_ARCHITECT=1\nexport OVN_EDIT_FORMAT='diff'  # pilot\n")
        rc, _ = b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t")
        t = b.flags_text() or ""
        return rc == 0 and "# keep me\n" in t and "export OVN_ARCHITECT=1\n" in t and "export OVN_EDIT_FORMAT='diff'  # pilot\n" in t and t.count("OVN_STAGE_ITEM_VERIFY") == 1
    finally:
        b.close()


def s_demote_needs_no_evidence(gov):
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_STAGE_ITEM_VERIFY='enforce'\n")
        rc, out = b.run("demote", "item_verify", "--apply", "--reason", "stalled")
        t = b.flags_text() or ""
        return rc == 0 and "OVN_STAGE_ITEM_VERIFY='shadow'" in t and "enforce" not in t.split("#")[0]
    finally:
        b.close()


def s_off_disables_writes(gov):
    b = Box(gov=gov)
    try:
        rc, out = b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t", OVN_GATE_GOVERNOR="off")
        return rc == 1 and "disabled" in out and b.flags_text() is None   # a refused promote is NOT rc 0 (a caller checking only the exit code must not think it worked)
    finally:
        b.close()


def s_unsafe_value_refused(gov):
    b = Box(gov=gov)
    m = load_module(gov, b)
    try:
        try:
            m.write_flags({"OVN_STAGE_ITEM_VERIFY": "enforce; rm -rf x"}, "t", "promote", "")
            return False
        except RuntimeError:
            return b.flags_text() is None
    finally:
        restore_env(m)
        b.close()


def _enforce_item_verify(b):
    b.write_flags("export OVN_STAGE_ITEM_VERIFY='enforce'\n")


def _blocks(b, repo, item, n, age_h_start=0.5, step_h=0.5):
    for i in range(n):
        b.journal(repo, item, NOW - (age_h_start + i * step_h) * 3600,
                  [{"event": "item_verify", "mode": "enforce", "pre": "FAIL", "post": "FAIL", "decision": "refuse:the item's own VERIFY is RED after the change"}], pushed=0, verified=False)


def s_watchdog_repeat_block_demotes(gov):
    b = Box(gov=gov)
    try:
        _enforce_item_verify(b)
        _blocks(b, "gitlark", "[T4] backend/a.py - do a thing", 3)
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        t = b.flags_text() or ""
        return rc == 0 and "OVN_STAGE_ITEM_VERIFY='shadow'" in t and "AUTO-DEMOTED" in open(os.path.join(b.state, "alerts.log")).read()
    finally:
        b.close()


def s_watchdog_below_threshold_keeps(gov):
    b = Box(gov=gov)
    try:
        _enforce_item_verify(b)
        _blocks(b, "gitlark", "[T4] backend/a.py - do a thing", 2)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before and not os.path.exists(os.path.join(b.state, "alerts.log"))
    finally:
        b.close()


def s_watchdog_shadow_never_writes(gov):
    b = Box(gov=gov)
    try:
        _enforce_item_verify(b)
        _blocks(b, "gitlark", "[T4] backend/a.py - do a thing", 4)
        before = b.flags_text()
        rc, out = b.run("watchdog")   # default mode = shadow
        al = open(os.path.join(b.state, "alerts.log")).read()
        return rc == 0 and b.flags_text() == before and "WOULD DEMOTE" in al and "AUTO-DEMOTED" not in al
    finally:
        b.close()


def _qa_alert_only_trip(b):
    b.env_extra["OVN_QA_BASELINE"] = "enforce"
    os.makedirs(os.path.join(b.state, "qa_shadow"), exist_ok=True)
    with open(os.path.join(b.state, "qa_shadow", "baseline.jsonl"), "w") as f:
        for i in range(4):
            f.write(json.dumps({"gate": "baseline", "mode": "enforce", "repo": "xlite", "ref": "base..tip", "ts": iso(NOW - (0.3 + 0.1 * i) * 3600), "verdict": "FAIL", "summary": "red"}) + "\n")


def s_watchdog_alerts_once(gov):
    """a REAL alert (an enforced qa gate stalling a lane: alert-only) is emitted once per TTL, in the alerts log AND as one high-priority note, however often the watchdog runs"""
    b = Box(gov=gov)
    try:
        _qa_alert_only_trip(b)
        b.run("watchdog")
        b.run("watchdog")
        b.run("watchdog")
        al = [l for l in open(os.path.join(b.state, "alerts.log")) if "gate-governor" in l]
        notes = [json.loads(l) for l in open(os.path.join(b.state, "notify_notes.jsonl"))]
        return len(al) == 1 and " warn |" in al[0] and len(notes) == 1 and notes[0]["prio"] == "high" and notes[0]["source"] == "gate_governor"
    finally:
        b.close()


def s_shadow_would_demote_is_quiet(gov):
    """report-only governor: 4 different items each refused 3x on one lane = ONE `info` line (not one per item), and NO hourly-update note for a demotion that never happens"""
    b = Box(gov=gov)
    try:
        _enforce_item_verify(b)
        for k in range(4):
            _blocks(b, "gitlark", "[T4] backend/q%d.py - thing %d" % (k, k), 3)
        for _ in range(2):
            b.run("watchdog")   # default governor mode = shadow
        al = [l for l in open(os.path.join(b.state, "alerts.log")) if "gate-governor" in l]
        return len(al) == 1 and "WOULD DEMOTE" in al[0] and " info |" in al[0] and not os.path.exists(os.path.join(b.state, "notify_notes.jsonl"))
    finally:
        b.close()


def _stall_setup(b, blocks_now=4, blocks_prev=1, landed=False, paused=False, label_fp=True, old_landing=False, prev_mode="enforce"):
    """label_fp: a human labelled one in-window refusal fp (the evidence that makes a stall `proven`). old_landing: a landing 10h ago (outside stall_h=6, inside hard_stall_h=18), so the lane
    is stalled but NOT hard-stalled."""
    _enforce_item_verify(b)
    # distinct items so only the lane-stall trigger can fire; 'now' window = last 6h, 'prev' = the 6h before
    first = None
    for i in range(blocks_now):
        fn = b.journal("iptv_apps", "[T3] iptv-backend/a%d.py - item %d" % (i, i), NOW - (0.3 + i * 0.5) * 3600,
                       [{"event": "item_verify", "mode": "enforce", "decision": "refuse:the item's own VERIFY is RED after the change"}])
        first = first or fn
    for i in range(blocks_prev):
        b.journal("iptv_apps", "[T3] iptv-backend/p%d.py - prev %d" % (i, i), NOW - (7 + i * 0.5) * 3600,
                  [{"event": "item_verify", "mode": prev_mode, "decision": "refuse:the item's own VERIFY is RED after the change"}])
    if label_fp:
        assert b.run("label", "item_verify", "run:" + first.replace(".jsonl", ""), "fp", "--note", "gate was wrong here")[0] == 0
    if old_landing:
        b.outcome("iptv_apps", NOW - 10 * 3600, "landed", item_hash="hold", status="pushed(tests:pass)")
    for i in range(3):
        b.outcome("iptv_apps", NOW - (0.5 + i) * 3600, "noop", item_hash="h%d" % i, status="no-op(stage-unverified)")
    if landed:
        b.outcome("iptv_apps", NOW - 2 * 3600, "landed", item_hash="hl", status="pushed(tests:pass)")
    if paused:
        open(os.path.join(b.state, "PAUSED"), "w").close()


def s_stall_demotes(gov):
    b = Box(gov=gov)
    try:
        _stall_setup(b)
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and "lane_stall" in out and "OVN_STAGE_ITEM_VERIFY='shadow'" in (b.flags_text() or "")
    finally:
        b.close()


def s_stall_with_landing_keeps(gov):
    b = Box(gov=gov)
    try:
        _stall_setup(b, landed=True)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before
    finally:
        b.close()


def s_stall_not_risen_keeps(gov):
    b = Box(gov=gov)
    try:
        _stall_setup(b, blocks_now=4, blocks_prev=5)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before
    finally:
        b.close()


def s_stall_paused_keeps(gov):
    b = Box(gov=gov)
    try:
        _stall_setup(b, paused=True)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before
    finally:
        b.close()


def s_watchdog_member_removes_only_that_rule(gov):
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_LQ_RULES_ENFORCE='DUP_DEF,TAUTOLOGY'\n")
        for i in range(3):
            b.journal("billwatch", "[T3] billwatch-backend/t.py - same item", NOW - (0.4 + i * 0.5) * 3600,
                      [{"event": "landing_quality", "mode": "enforce", "detail": "TAUTOLOGY tests/test_x.py assert .. or True"}])
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        t = b.flags_text() or ""
        return rc == 0 and "OVN_LQ_RULES_ENFORCE='DUP_DEF'" in t
    finally:
        b.close()


def s_qa_trip_is_alert_only(gov):
    b = Box(gov=gov)
    try:
        b.env_extra["OVN_QA_BASELINE"] = "enforce"
        os.makedirs(os.path.join(b.state, "qa_shadow"))
        with open(os.path.join(b.state, "qa_shadow", "baseline.jsonl"), "w") as f:
            for i in range(4):
                f.write(json.dumps({"gate": "baseline", "mode": "enforce", "repo": "xlite", "ref": "base..tip", "ts": iso(NOW - (0.3 + 0.1 * i) * 3600), "verdict": "FAIL", "summary": "red"}) + "\n")
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        al = open(os.path.join(b.state, "alerts.log")).read() if os.path.exists(os.path.join(b.state, "alerts.log")) else ""
        return rc == 0 and "alert-only" in out and b.flags_text() is None and "qa_enforce.sh" in out + al
    finally:
        b.close()


def s_credit_join_counts(gov):
    b = Box(gov=gov)
    try:
        b.seed_fixture()
        rep = b.report("item_verify")
        # independent count from the fixture journals: refuse decisions of runs that pushed
        n_refuse, n_cred = 0, 0
        led = {os.path.basename(x.strip()) for x in open(os.path.join(FIX, "stage_credited.ledger"))}
        for fn in os.listdir(os.path.join(FIX, "stage_runs")):
            rows = [json.loads(x) for x in open(os.path.join(FIX, "stage_runs", fn))]
            if any(r.get("event") == "item_verify" and str(r.get("decision", "")).startswith("refuse") for r in rows):
                n_refuse += 1
                s = [r for r in rows if r.get("event") == "summary"][0]
                if fn in led or s.get("commits_pushed", 0) > 0:
                    n_cred += 1
        return n_refuse >= 1 and rep["would_block"] == n_refuse and rep["credited_despite_would_block"] == n_cred and n_cred >= 1
    finally:
        b.close()


def s_git_revert_join(gov):
    """a credited commit later reverted in git is counted as confirmed-bad (strong)"""
    b = Box(gov=gov)
    try:
        repo = os.path.join(b.root, "repos", "gitlark")
        os.makedirs(repo)
        env = dict(os.environ, GIT_AUTHOR_DATE=iso(NOW - 3600), GIT_COMMITTER_DATE=iso(NOW - 3600), **GITENV)
        g = lambda *a: subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True, env=env, check=True).stdout.strip()
        g("init", "-q", "-b", "main")
        open(os.path.join(repo, "a.txt"), "w").write("1\n")
        g("add", "-A")
        g("commit", "-q", "-m", "base")
        open(os.path.join(repo, "a.txt"), "w").write("2\n")
        g("commit", "-q", "-am", "fleet change")
        bad = g("rev-parse", "HEAD")
        g("revert", "--no-edit", "HEAD")
        item = "[T4] backend/a.py - do a thing [feat:gitlark-20261018-do-a-thing]"
        t0 = NOW - 3 * 3600
        b.journal("gitlark", item, t0, [{"event": "item_verify", "mode": "shadow", "decision": "refuse:the item's own VERIFY is RED after the change"}], pushed=1)
        import hashlib
        h = hashlib.md5(b"[feat:gitlark-do-a-thing]").hexdigest()
        b.outcome("gitlark", t0 + 600, "landed", item_hash=h, status="pushed(tests:pass)", head_after=bad, commits=[bad])
        rc, out = b.run("report", "--gate", "item_verify", "--days", "7", "--json", OVN_GG_GIT="1", OVN_REPOS_DIR=os.path.join(b.root, "repos"))
        rep = json.loads(out)[0]
        return rc == 0 and rep["would_block"] == 1 and rep["credited_despite_would_block"] == 1 and rep["later_bad_strong"] == 1
    finally:
        b.close()


def s_selfcheck_detects_drift(gov):
    b = Box(gov=gov)
    try:
        reg = json.load(open(REG))
        for g in reg["gates"]:
            if g["id"] == "item_verify":
                g["default"] = "enforce"      # the code says shadow
        json.dump(reg, open(b.reg, "w"))
        # selfcheck reads source files under OVN_DIR: point it at the real tree
        rc, out = b.run("selfcheck", OVN_DIR=OVN)
        return rc == 1 and "item_verify" in out and "defaults" in out
    finally:
        b.close()


def s_unverified_rate_blocks(gov):
    b = Box(gov=gov)
    try:
        b.seed_fixture()
        rep = b.report("qa:scanners")
        c = [x for x in rep["criteria"] if x["name"].startswith("unverified")]
        return len(c) == 1 and c[0]["ok"] is False and rep["promotable"] is False
    finally:
        b.close()


def s_label_latest_wins_and_only_would_blocks_count(gov):
    b = Box(gov=gov)
    try:
        b.mistarget_evidence(n=5, span_days=1)
        rep = b.report("item_mistarget")
        k = rep["fp_candidates"][0]["key"]
        b.run("label", "item_mistarget", k, "fp")
        b.run("label", "item_mistarget", k, "tp")        # latest wins
        b.run("label", "item_mistarget", "l:doesnotexist", "fp")   # not a would-block of this window: ignored
        rep = b.report("item_mistarget")
        return rep["labelled"] == 1 and rep["labelled_tp"] == 1 and rep["labelled_fp"] == 0 and all(c["key"] != k for c in rep["fp_candidates"])
    finally:
        b.close()


def s_repeat_block_steps_of_one_feature_not_one_item(gov):
    """three DIFFERENT steps (distinct item text) of one multi-step feature [feat:..] refused within 6h are not 'the same item blocked 3 times'"""
    b = Box(gov=gov)
    try:
        _enforce_item_verify(b)
        for i in range(3):
            _blocks(b, "billwatch", "[T3] billwatch-backend/step%d.py - step %d of the feature [feat:billwatch-20261018-auth-rework]" % (i, i), 1, age_h_start=0.5 + i)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before and not os.path.exists(os.path.join(b.state, "alerts.log"))
    finally:
        b.close()


def s_lq_rule_under_shadow_master_blocks_nothing(gov):
    """the runner journals landing_quality with mode=<master switch>: a SHADOW master blocked nothing, so its rule findings are would-blocks, never enforced blocks to demote; master off = ignored"""
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_STAGE_LANDING_QUALITY='shadow'\nexport OVN_LQ_RULES_ENFORCE='DUP_DEF'\n")
        for i in range(3):
            b.journal("xlite", "[T3] xlite/x.gd - same item", NOW - (0.4 + i * 0.5) * 3600, [{"event": "landing_quality", "mode": "shadow", "detail": "DUP_DEF\tx.py\tdup"}])
        for i in range(2):
            b.journal("xlite", "[T3] xlite/y.gd - other item", NOW - (4 + i * 0.5) * 3600, [{"event": "landing_quality", "mode": "off", "detail": "DUP_DEF\tx.py\tdup"}])
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        rep = b.report("lq_rule:DUP_DEF")
        return (rc == 0 and b.flags_text() == before and "AUTO-DEMOTED" not in (open(os.path.join(b.state, "alerts.log")).read() if os.path.exists(os.path.join(b.state, "alerts.log")) else "")
                and rep["enforced_blocks"] == 0 and rep["would_block"] == 3)
    finally:
        b.close()


def s_multi_variable_export_line(gov):
    """`export A=enforce B=enforce` is valid bash and both are live: list sees both, demoting A keeps B enforced (and the file still sources)"""
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_STAGE_ITEM_VERIFY=enforce OVN_STAGE_RED_BEFORE=enforce\n")
        rc, out = b.run("list")
        seen = (re.search(r"item_verify\s+enforce\s+pilot_flags\.env", out) and re.search(r"red_before\s+enforce\s+pilot_flags\.env", out))
        rc2, out2 = b.run("demote", "item_verify", "--apply", "--reason", "t")
        t = b.flags_text() or ""
        got = subprocess.run(["bash", "-c", '. "$1"; echo "$OVN_STAGE_ITEM_VERIFY/$OVN_STAGE_RED_BEFORE"', "_", b.flags], capture_output=True, text=True, env={"PATH": os.environ["PATH"]}).stdout.strip()
        return bool(seen) and rc2 == 0 and got == "shadow/enforce" and "OVN_STAGE_RED_BEFORE" in t
    finally:
        b.close()


def s_complex_flag_lines_fail_closed(gov):
    """a conditional/computed assignment the parser cannot read: (1) one AFTER our governed line would silently override it -> the write is REFUSED (rc 1, file untouched, line named);
    (2) one BEFORE it hides the real mode, so demote must not claim 'already shadow': our later line wins and the result is verified"""
    b = Box(gov=gov)
    try:
        after = "export OVN_STAGE_ITEM_VERIFY='enforce'\n[ -z \"${NOPE:-}\" ] && export OVN_STAGE_ITEM_VERIFY=enforce\n"
        b.write_flags(after)
        rc, out = b.run("demote", "item_verify", "--apply")
        ok1 = rc == 1 and b.flags_text() == after and "line 2" in out
        rc_l, out_l = b.run("list")
        ok1 = ok1 and "WARNING" in out_l and "line 2" in out_l
        before = '[ -z "${NOPE:-}" ] && export OVN_STAGE_ITEM_VERIFY=enforce\n'
        b.write_flags(before)
        rc2, out2 = b.run("demote", "item_verify", "--apply")
        t = b.flags_text() or ""
        got = subprocess.run(["bash", "-c", '. "$1"; echo "$OVN_STAGE_ITEM_VERIFY"', "_", b.flags], capture_output=True, text=True, env={"PATH": os.environ["PATH"]}).stdout.strip()
        return ok1 and rc2 == 0 and got == "shadow" and t.startswith(before)
    finally:
        b.close()


def s_rollback_is_idempotent(gov):
    """a retried `rollback --apply` must not re-apply the change that was just rolled back; a NEW change is rolled back again normally"""
    b = Box(gov=gov)
    try:
        orig = "export OVN_ARCHITECT=1\n"
        b.write_flags(orig)
        b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t")
        promoted = b.flags_text()
        r1 = b.run("rollback", "--apply")
        a1 = b.flags_text()
        r2 = b.run("rollback", "--apply")
        r3 = b.run("rollback", "--apply")
        a3 = b.flags_text()
        b.run("promote", "red_before", "--apply", "--i-checked-the-samples", "--reason", "t")
        r4 = b.run("rollback", "--apply")
        a4 = b.flags_text()
        return (promoted != orig and r1[0] == 0 and a1 == orig and r2[0] == 0 and r3[0] == 0 and a3 == orig and "already rolled back" in r2[1] and r4[0] == 0 and a4 == orig)
    finally:
        b.close()


def s_backups_are_pruned(gov):
    b = Box(gov=gov)
    try:
        for i in range(8):
            if i % 2 == 0:
                b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t", OVN_GG_BACKUP_KEEP="3")
            else:
                b.run("demote", "item_verify", "--apply", OVN_GG_BACKUP_KEEP="3")
        d = os.path.join(b.state, "gate_governor", "backups")
        n = len([f for f in os.listdir(d) if f.endswith((".env", ".absent"))])
        rc, out = b.run("rollback", "--apply", OVN_GG_BACKUP_KEEP="3")
        return n <= 4 and rc == 0 and "VERIFIED" in out
    finally:
        b.close()


def s_off_keeps_manual_way_down(gov):
    """OVN_GATE_GOVERNOR=off stops automation and promotion; demote and rollback must keep working (incident path), and a disabled promote/label exits non-zero"""
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_STAGE_ITEM_VERIFY='enforce'\n")
        rc, out = b.run("demote", "item_verify", "--apply", OVN_GATE_GOVERNOR="off")
        ok1 = rc == 0 and "OVN_STAGE_ITEM_VERIFY='shadow'" in (b.flags_text() or "")
        rc2, out2 = b.run("rollback", "--apply", OVN_GATE_GOVERNOR="off")
        ok2 = rc2 == 0 and b.flags_text() == "export OVN_STAGE_ITEM_VERIFY='enforce'\n"
        rc3, _ = b.run("label", "item_verify", "l:x", "fp", OVN_GATE_GOVERNOR="off")
        rc4, _ = b.run("watchdog", OVN_GATE_GOVERNOR="off")
        return ok1 and ok2 and rc3 == 1 and rc4 == 0
    finally:
        b.close()


def s_stall_without_evidence_is_alert_only(gov):
    """a gate refusing bad work is WORKING: 4 refusals + 0 landings in 6h (with a landing 10h ago) and no label saying they were wrong -> alert, no demotion"""
    b = Box(gov=gov)
    try:
        _stall_setup(b, label_fp=False, old_landing=True)
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        al = open(os.path.join(b.state, "alerts.log")).read() if os.path.exists(os.path.join(b.state, "alerts.log")) else ""
        return rc == 0 and b.flags_text() == before and "no evidence" in out + al and "AUTO-DEMOTED" not in al
    finally:
        b.close()


def s_stall_hard_demotes_without_label(gov):
    """liveness wins eventually: 0 landings for hard_stall_h (18h) and still refusing -> demote even with no label"""
    b = Box(gov=gov)
    try:
        _stall_setup(b, label_fp=False)   # no landing anywhere in the window
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and "hard stall" in out and "OVN_STAGE_ITEM_VERIFY='shadow'" in (b.flags_text() or "")
    finally:
        b.close()


def s_stall_baseline_includes_shadow_would_blocks(gov):
    """a freshly enforced gate has no enforced history; its shadow would-blocks in the previous window are the baseline, so 4 now vs 5 before is NOT a rise"""
    b = Box(gov=gov)
    try:
        _stall_setup(b, blocks_now=4, blocks_prev=5, prev_mode="shadow")
        before = b.flags_text()
        rc, out = b.run("watchdog", OVN_GATE_GOVERNOR="enforce")
        return rc == 0 and b.flags_text() == before
    finally:
        b.close()


def s_enforced_doc_executor_apply_is_not_a_refusal(gov):
    """doc_executor: `apply` in enforce mode is an edit that was MADE, not a block; in shadow `would-apply` is the would-block"""
    b = Box(gov=gov)
    try:
        rows = []
        for i in range(4):
            rows.append("%s\tgitlark\tdoc\ton\tapply\th%d\tdetail\tcyc" % (iso(NOW - (0.2 + i * 0.3) * 3600), i))
        for i in range(2):
            rows.append("%s\tgitlark\tdoc\tshadow\twould-apply\ts%d\tdetail\tcyc" % (iso(NOW - (30 + i) * 3600), i))
        with open(os.path.join(b.state, "executor_shadow.log"), "w") as f:
            f.write("\n".join(rows) + "\n")
        rep = b.report("doc_executor")
        return rep["enforced_blocks"] == 0 and rep["would_block"] == 2
    finally:
        b.close()


def s_no_deprecation_warnings(gov):
    """python 3.13+ DeprecationWarning (positional maxsplit) polluted cron.log on every flags read: a strict -W error run over a quoted/commented flags file must be clean"""
    b = Box(gov=gov)
    try:
        b.write_flags("export OVN_STAGE_ITEM_VERIFY='enforce'  # tagged\nOVN_BESTOF_N=3 # note\nexport OVN_EDIT_FORMAT=\"diff\"\n")
        p = subprocess.run([sys.executable, "-I", "-W", "error::DeprecationWarning", gov, "list"], capture_output=True, text=True, env=b.env(), timeout=120)
        return p.returncode == 0 and "Deprecation" not in p.stdout + p.stderr and "item_verify" in p.stdout
    finally:
        b.close()


MUTANTS = [
    # (name, old text (must occur exactly once), new text, scenario that must pass on the real governor and fail on the mutant)
    ("promote-skips-criteria", "    if unmet and not override:", "    if False and not override:", s_promote_refuses_without_evidence),
    ("min-labelled-lowered", 'rep.get("labelled", 0) >= crit["min_labelled"]', 'rep.get("labelled", 0) >= 1', s_19_labels_refused),
    ("fp-boundary-inclusive", 'fp is not None and fp < crit["max_fp_rate"]', 'fp is not None and fp <= crit["max_fp_rate"]', s_one_fp_in_20_refused),
    ("stale-evidence-ok", 'fresh is not None and fresh <= crit["max_stale_days"]', "True", s_stale_evidence_refused),
    ("override-needs-no-reason", 'if not (args.reason or "").strip():', "if False:", s_override_needs_flag_and_reason),
    ("non-pilot-channel-writable", '    if g["channel"] != "pilot_env":\n        print("REFUSED: " + owner_hint(g, to))\n        return 1\n    if RANK[to] <= RANK[cur]:', '    if False:\n        print("REFUSED: " + owner_hint(g, to))\n        return 1\n    if RANK[to] <= RANK[cur]:', s_non_pilot_channels_never_written),
    ("no-backup", 'shutil.copy2(flags_path(), os.path.join(backup_dir(), bid + ".env"))', "pass", s_rollback_restores_byte_identical),
    ("other-lines-dropped", "        else:\n            out.append(ln)\n    while out and out[-1]", "        else:\n            pass\n    while out and out[-1]", s_other_lines_preserved),
    ("unsafe-value-allowed", "if not ENV_RE.match(var) or not VALUE_RE.match(val):", "if False:", s_unsafe_value_refused),
    ("off-mode-ignored", 'if mode == "off" and args.cmd not in ("list", "status", "selfcheck", "demote", "rollback"):', 'if False and args.cmd not in ("list", "status", "selfcheck", "demote", "rollback"):', s_off_disables_writes),
    ("off-blocks-manual-demote", 'args.cmd not in ("list", "status", "selfcheck", "demote", "rollback"):\n        print("OVN_GATE_GOVERNOR=off', 'args.cmd not in ("list", "status", "selfcheck"):\n        print("OVN_GATE_GOVERNOR=off', s_off_keeps_manual_way_down),
    ("off-refusal-exits-zero", 'return 1 if args.cmd in ("promote", "label", "attest") else 0', "return 0", s_off_keeps_manual_way_down),
    ("repeat-keyed-on-feature-hash", "ik = exact_item_key(r.item) if r.item else r.key", "ik = item_hash(r.item) if r.item else r.key", s_repeat_block_steps_of_one_feature_not_one_item),
    ("lq-ignores-master-mode", '"enforce" if m == "enforce" else "shadow", True, None, run["item"]))', '"enforce", True, None, run["item"]))', s_lq_rule_under_shadow_master_blocks_nothing),
    ("lq-counts-master-off", 'if (e.get("mode") or "").strip().lower() == "off":', 'if (e.get("mode") or "").strip().lower() == "never":', s_lq_rule_under_shadow_master_blocks_nothing),
    ("flags-parse-first-var-only", "    for t in toks:\n        m = ASSIGN_RE.match(t)", "    for t in toks[:1]:\n        m = ASSIGN_RE.match(t)", s_multi_variable_export_line),
    ("flags-rewrite-drops-siblings", '                if v not in updates:\n                    out.append("export %s=%s" % (v, shlex.quote(val)))', "                if v not in updates:\n                    pass", s_multi_variable_export_line),
    ("write-not-verified-after-source", "return all(got.get(n) == expect[n] for n in names)", "return True", s_complex_flag_lines_fail_closed),
    ("demote-trusts-misparse", "if RANK[to] >= RANK[cur] and not cx:", "if RANK[to] >= RANK[cur]:", s_complex_flag_lines_fail_closed),
    ("rollback-not-idempotent", "        if os.path.exists(restored_marker(bid)):\n            print(\"nothing to roll back", "        if False:\n            print(\"nothing to roll back", s_rollback_is_idempotent),
    ("rollback-targets-own-prebackup", "        changes = [i for i in ids if kinds.get(i, \"change\") == \"change\"]\n        if not changes:", "        changes = ids\n        if not changes:", s_rollback_is_idempotent),
    ("backups-never-pruned", "    if len(ids) <= keep:\n        return\n    kinds", "    return\n    kinds", s_backups_are_pruned),
    ("stall-without-proof-demotes", '"proven": bool(fp or hard),', '"proven": True,', s_stall_without_evidence_is_alert_only),
    ("stall-hard-never", "hard = bool(hard_out) and not any(o.get(\"class\") in GOOD_CLASSES for o in hard_out)", "hard = False", s_stall_hard_demotes_without_label),
    ("stall-baseline-enforce-only", 'if r.block and r.ts is not None and w["stall_h"] < (t_now - r.ts) / 3600.0 <= 2 * w["stall_h"]:', 'if r.mode == "enforce" and r.block and r.ts is not None and w["stall_h"] < (t_now - r.ts) / 3600.0 <= 2 * w["stall_h"]:', s_stall_baseline_includes_shadow_would_blocks),
    ("shadow-alert-per-item", '"" if would else t["item"]', 't["item"]', s_shadow_would_demote_is_quiet),
    ("shadow-alert-notifies", "prio_note=not would,", "prio_note=True,", s_shadow_would_demote_is_quiet),
    ("executor-apply-counts-as-refusal", 'bv = ev.get("enforce_block_values", ev.get("block_values", [])) if mode == "enforce" else ev.get("block_values", [])', 'bv = ev.get("block_values", [])', s_enforced_doc_executor_apply_is_not_a_refusal),
    ("positional-maxsplit-reintroduced", "    if toks and toks[0] == \"export\":", "    re.split(r\"\\s+#\", ln, 1)\n    if toks and toks[0] == \"export\":", s_no_deprecation_warnings),
    ("watchdog-always-applies", 'res = run_watchdog(reg, mode == "enforce")', "res = run_watchdog(reg, True)", s_watchdog_shadow_never_writes),
    ("repeat-threshold-off-by-one", 'if len(recent) >= w["repeat_block_n"]:', 'if len(recent) > w["repeat_block_n"]:', s_watchdog_repeat_block_demotes),
    ("repeat-threshold-too-low", 'if len(recent) >= w["repeat_block_n"]:', "if len(recent) >= 1:", s_watchdog_below_threshold_keeps),
    ("alert-not-deduped", "    if t - seen.get(key, 0) < ttl_h * 3600:\n        return False", "    if False:\n        return False", s_watchdog_alerts_once),
    ("stall-ignores-landings", "if landed or not attempts:", "if not attempts:", s_stall_with_landing_keeps),
    ("stall-ignores-rise", "if n >= w[\"stall_min_blocks\"] and n > lane_prev[lane][gid]]", "if n >= w[\"stall_min_blocks\"]]", s_stall_not_risen_keeps),
    ("stall-ignores-pause", 'paused = os.path.exists(os.path.join(state_dir(), "PAUSED"))', "paused = False", s_stall_paused_keeps),
    ("member-demote-drops-all", 'members = [m for m in member_list(g, flags) if m != g["member"]]\n        return {g["env"]: ",".join(members)}', 'members = []\n        return {g["env"]: ",".join(members)}', s_watchdog_member_removes_only_that_rule),
    ("ledger-ignored", 'return run["file"] in ctx.ledger() or (isinstance(pushed, (int, float)) and pushed > 0)', "return False", s_credit_join_counts),
    ("git-revert-join-off", "if any(x.startswith(r) or r.startswith(x[:len(r)]) for r in rev_cache[repo]):", "if False:", s_git_revert_join),
    ("selfcheck-blind", "bad = {d for d in defaults if d and d != codev}", "bad = set()", s_selfcheck_detects_drift),
    ("unverified-ignored", 'ur <= crit["max_unverified_rate"]', "True", s_unverified_rate_blocks),
    ("labels-not-latest-wins", '                        self._labels[(r["gate"], r["key"])] = r   # latest wins', '                        self._labels.setdefault((r["gate"], r["key"]), r)', s_label_latest_wins_and_only_would_blocks_count),
]


class TestScenarios(unittest.TestCase):
    """every scenario passes against the real governor"""

    def check(self, fn):
        self.assertTrue(fn(GOV), fn.__name__)

    def test_scenarios_pass_on_real_governor(self):
        scen = [s_promote_applies_when_criteria_met, s_rollback_to_absent, s_demote_needs_no_evidence, s_qa_trip_is_alert_only]
        for fn in scen:
            with self.subTest(scenario=fn.__name__):
                self.check(fn)


class TestMutants(unittest.TestCase):
    """every guard removed => the scenario that protects it FAILS"""

    @classmethod
    def setUpClass(cls):
        cls.td = tempfile.TemporaryDirectory(prefix="gg_mut.")
        cls.src = open(GOV).read()

    @classmethod
    def tearDownClass(cls):
        cls.td.cleanup()

    def test_mutants_are_killed(self):
        for name, old, new, scen in MUTANTS:
            with self.subTest(mutant=name):
                self.assertEqual(self.src.count(old), 1, "stale mutant %s: the text to mutate must occur exactly once" % name)
                p = os.path.join(self.td.name, "mut_%s.py" % name.replace("-", "_"))
                with open(p, "w") as f:
                    f.write(self.src.replace(old, new))
                self.assertTrue(scen(GOV), "scenario must pass on the real governor: %s" % scen.__name__)
                self.assertFalse(scen(p), "MUTANT SURVIVED: %s (scenario %s still passes with the guard removed)" % (name, scen.__name__))


class TestEvidence(unittest.TestCase):
    def setUp(self):
        self.b = Box()
        self.b.seed_fixture()

    def tearDown(self):
        self.b.close()

    def test_real_shape_counts_against_independent_read(self):
        rows = {}
        for fn in os.listdir(os.path.join(FIX, "stage_runs")):
            for x in open(os.path.join(FIX, "stage_runs", fn)):
                r = json.loads(x)
                if r.get("event"):
                    rows.setdefault(r["event"], []).append(r)
        rep = self.b.report("item_verify")
        self.assertEqual(rep["records"], len(rows["item_verify"]))
        self.assertEqual(rep["would_block"], len([r for r in rows["item_verify"] if r["decision"].startswith("refuse")]))
        rb = self.b.report("red_before")
        self.assertEqual(rb["would_block"], len([r for r in rows["red_before"] if r["detail"].startswith("RB weak")]))
        self.assertGreaterEqual(rb["would_block"], 1)
        web = self.b.report("web_verify")
        self.assertEqual(web["would_block"], len([r for r in rows["web_verify"] if r["detail"].startswith("WEB red")]))
        self.assertGreaterEqual(web["would_block"], 1)

    def test_text_shadow_log_and_repo_normalised(self):
        rep = self.b.report("item_mistarget")
        self.assertEqual(rep["would_block"], len([l for l in open(os.path.join(FIX, "stage_guards_shadow.log.txt")) if "item-mistarget(shadow)" in l]))
        self.assertGreaterEqual(rep["would_block"], 1)
        self.assertEqual(list(rep["by_repo"]), ["gitlark"])   # 'stage-gitlark.lw0c' -> gitlark

    def test_qa_rows_fail_flag_unverified_and_cost(self):
        rep = self.b.report("qa:baseline")
        fx = [json.loads(x) for x in open(os.path.join(FIX, "qa_shadow", "baseline.jsonl"))]
        self.assertEqual(rep["would_block"], len([r for r in fx if r["verdict"] == "FAIL"]))
        self.assertEqual(rep["unverified"], len([r for r in fx if r["verdict"] == "UNVERIFIED"]))
        self.assertIsNotNone(rep["p90_cost_s"])      # ms -> s from the journal
        self.assertEqual(rep["cost_source"], "journal")

    def test_task_log_patterns_split_shadow_and_enforce(self):
        self.assertEqual(self.b.report("fixup_reverify", 30)["would_block"], 2)      # [fixup-verify-fail] + [fixup-tests-lost], mode=shadow
        t = self.b.report("testonly_guard", 30)
        self.assertEqual((t["would_block"], t["enforced_blocks"]), (1, 1))
        self.assertEqual(self.b.report("verify_timeout_hold", 30)["would_block"], 1)
        self.assertEqual(self.b.report("build_break_park", 30)["would_block"], 1)
        self.assertEqual(list(self.b.report("testonly_guard", 30)["by_repo"]), ["xlite"])   # repo from ongoing-xlite.log

    def test_old_log_dir_outside_window_is_skipped(self):
        d = os.path.join(self.b.root, "logs", "20260901-000000")
        os.makedirs(d)
        shutil.copy(os.path.join(FIX, "tasklog_lines.txt"), os.path.join(d, "ongoing-xlite.log"))
        self.assertEqual(self.b.report("fixup_reverify", 30)["would_block"], 2)

    def test_tsv_and_jsonl_gates(self):
        self.assertEqual(self.b.report("doc_executor", 30)["records"], 3)
        so = self.b.report("stage_order", 30)
        fx = [json.loads(x) for x in open(os.path.join(FIX, "stage_order_shadow.log.txt"))]
        self.assertEqual(so["would_block"], len([r for r in fx if r["event"] == "would_skip_item"]))
        self.assertEqual(so["records"], len(fx))
        self.assertEqual(so["undated_records"], len(fx))      # no ts in the real rows: counted, never counted as shadow days
        vl = self.b.report("verify_lint", 30)
        self.assertEqual(vl["records"], 5)
        self.assertEqual(vl["would_block"], 2)

    def test_gate_without_a_journal_is_never_promotable(self):
        rep = self.b.report("supply_mutation")
        self.assertFalse(rep["promotable"])
        self.assertEqual([c["name"] for c in rep["criteria"] if not c["ok"]][0], "evidence")
        self.assertIn("no shadow journal", rep["criteria"][0]["detail"])
        self.assertEqual(rep["channel"], "cron_env")
        self.assertEqual(self.b.run("promote", "supply_mutation", "--apply")[0], 1)

    def test_local_time_parsing_uses_system_tz(self):
        m = load_module(GOV, self.b)
        try:
            os.environ["TZ"] = "America/Chicago"
            time.tzset()
            a = m.parse_ts("2026-10-18 19:40:13")
            os.environ["TZ"] = "UTC"
            time.tzset()
            c = m.parse_ts("2026-10-18 19:40:13")
            self.assertEqual(a - c, 5 * 3600)
            self.assertEqual(m.parse_ts("2026-10-19T00:38:07Z"), calendar.timegm((2026, 10, 19, 0, 38, 7)))
            self.assertEqual(m.parse_ts("20261019-000758", "run"), calendar.timegm((2026, 10, 19, 0, 7, 58)))
        finally:
            restore_env(m)

    def test_item_hash_matches_bash_ovn_item_hash(self):
        m = load_module(GOV, self.b)
        try:
            txt = "- [ ] [T3] a.py - x [feat:xlite-20261018-delete-cover-hit-chance-dead-function-sc]"
            bash = subprocess.run(["bash", "-c", '. "$1"; ovn_item_hash "$2"', "_", os.path.join(OVN, "scripts", "lib_item_select.sh"), txt], capture_output=True, text=True).stdout.strip()
            if len(bash) == 32:
                self.assertEqual(m.item_hash(txt), bash)
            self.assertEqual(m.item_hash(txt), m.item_hash("[T3] other text [feat:xlite-20261019-delete-cover-hit-chance-dead-function-sc]"))   # date segment normalised
        finally:
            restore_env(m)

    def test_report_is_read_only(self):
        before = {}
        for dp, _, fns in os.walk(self.b.state):
            for fn in fns:
                p = os.path.join(dp, fn)
                before[p] = (os.path.getsize(p), os.path.getmtime(p))
        rc, out = self.b.run("report", "--days", "30")
        self.assertEqual(rc, 0)
        after = {}
        for dp, _, fns in os.walk(self.b.state):
            for fn in fns:
                p = os.path.join(dp, fn)
                after[p] = (os.path.getsize(p), os.path.getmtime(p))
        self.assertEqual(before, after)
        self.assertFalse(os.path.exists(self.b.flags))

    def test_report_write_and_note(self):
        rc, out = self.b.run("report", "--days", "30", "--write", "--note")
        self.assertEqual(rc, 0)
        d = os.path.join(self.b.state, "gate_governor", "reports")
        names = sorted(os.listdir(d))
        self.assertEqual([n.split(".")[-1] for n in names], ["json", "md"])
        notes = [json.loads(x) for x in open(os.path.join(self.b.state, "notify_notes.jsonl"))]
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]["prio"], "default")


class TestFlagsFile(unittest.TestCase):
    def test_written_file_sources_under_set_u_and_exports_to_children(self):
        b = Box()
        try:
            b.write_flags("export OVN_ARCHITECT=1\n")
            self.assertEqual(b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t")[0], 0)
            self.assertEqual(b.run("promote", "lq_rule:TAUTOLOGY", "--apply", "--i-checked-the-samples", "--reason", "t")[0], 0)
            self.assertEqual(b.run("promote", "doc_executor", "--apply", "--i-checked-the-samples", "--reason", "t")[0], 0)
            out = subprocess.run(["bash", "-c", 'set -uo pipefail; . "$1"; env | grep -E "^OVN_" | sort', "_", b.flags], capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            env = dict(l.split("=", 1) for l in out.stdout.splitlines())
            self.assertEqual(env["OVN_STAGE_ITEM_VERIFY"], "enforce")
            self.assertEqual(env["OVN_LQ_RULES_ENFORCE"], "DUP_DEF,TAUTOLOGY")      # default member kept, new one added
            self.assertEqual(env["OVN_DOC_EXECUTOR"], "on")                       # enforce spelled 'on' for this gate
            self.assertEqual(env["OVN_ARCHITECT"], "1")
            rc, out = b.run("list")
            self.assertIn("pilot_flags.env", out)
            self.assertRegex(out, r"item_verify\s+enforce\s+pilot_flags\.env")
            self.assertRegex(out, r"lq_rule:TAUTOLOGY\s+enforce\s+pilot_flags\.env")
            self.assertRegex(out, r"doc_executor\s+enforce\s+pilot_flags\.env")
        finally:
            b.close()

    def test_cron_env_gate_ignores_pilot_flags_file(self):
        """pilot_flags.env never reaches cron-launched consumers, so the governor must not report it as the effective source"""
        b = Box()
        try:
            b.write_flags("export OVN_VERIFY_LINT='enforce'\n")
            self.assertRegex(b.run("list")[1], r"verify_lint\s+shadow\s+default")
            self.assertRegex(b.run("list", OVN_VERIFY_LINT="enforce")[1], r"verify_lint\s+enforce\s+env")
        finally:
            b.close()

    def test_effective_precedence_flags_over_env_over_default(self):
        b = Box()
        try:
            self.assertRegex(b.run("list")[1], r"item_verify\s+shadow\s+default")
            rc, out = b.run("list", OVN_STAGE_ITEM_VERIFY="off")
            self.assertRegex(out, r"item_verify\s+off\s+env")
            b.write_flags("OVN_STAGE_ITEM_VERIFY=enforce\n")      # hand-written, un-exported form is still read
            rc, out = b.run("list", OVN_STAGE_ITEM_VERIFY="off")
            self.assertRegex(out, r"item_verify\s+enforce\s+pilot_flags\.env")
        finally:
            b.close()

    def test_qa_modes_resolution_env_file_default(self):
        b = Box()
        try:
            self.assertRegex(b.run("list")[1], r"qa:baseline\s+shadow\s+default")
            with open(os.path.join(b.state, "qa_gate_modes.json"), "w") as f:
                json.dump({"baseline": "enforce"}, f)
            self.assertRegex(b.run("list")[1], r"qa:baseline\s+enforce\s+file")
            self.assertRegex(b.run("list", OVN_QA_BASELINE="off")[1], r"qa:baseline\s+off\s+env")
        finally:
            b.close()

    def test_bad_registry_is_exit_2_and_writes_nothing(self):
        b = Box()
        try:
            open(b.reg, "w").write("{not json")
            rc, out = b.run("promote", "item_verify", "--apply")
            self.assertEqual(rc, 2)
            self.assertIn("REGISTRY ERROR", out)
            self.assertIsNone(b.flags_text())
        finally:
            b.close()

    def test_registry_unsafe_value_rejected(self):
        b = Box()
        try:
            reg = json.load(open(REG))
            reg["gates"][0]["values"] = {"enforce": "enforce;rm"}
            json.dump(reg, open(b.reg, "w"))
            rc, out = b.run("list")
            self.assertEqual(rc, 2)
        finally:
            b.close()

    def test_concurrent_writers_all_land_and_file_stays_valid(self):
        b = Box()
        try:
            gates = ["item_verify", "red_before", "web_verify", "item_mistarget", "fixup_reverify", "testonly_guard", "stage_precredit", "stage_order"]
            procs = [subprocess.Popen([sys.executable, "-I", GOV, "promote", g, "--apply", "--i-checked-the-samples", "--reason", "race"], env=b.env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT) for g in gates]
            for p in procs:
                p.communicate(timeout=120)
                self.assertEqual(p.returncode, 0)
            t = b.flags_text()
            for g, var in zip(gates, ["OVN_STAGE_ITEM_VERIFY", "OVN_STAGE_RED_BEFORE", "OVN_STAGE_WEB_VERIFY", "OVN_STAGE_ITEM_MISTARGET", "OVN_FIXUP_REVERIFY", "OVN_TESTONLY_GUARD", "OVN_STAGE_PRECREDIT", "OVN_STAGE_ORDER"]):
                self.assertEqual(t.count("export %s='enforce'" % var), 1, (g, t))
            self.assertEqual(subprocess.run(["bash", "-n", b.flags]).returncode, 0)
            self.assertEqual(len([f for f in os.listdir(os.path.join(b.state, "gate_governor", "backups")) if f.endswith((".env", ".absent"))]), len(gates))
        finally:
            b.close()

    def test_only_allowed_files_are_written(self):
        b = Box()
        try:
            b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t")
            b.run("demote", "item_verify", "--apply")
            b.run("rollback", "--apply")
            top = sorted(os.listdir(b.state))
            self.assertEqual(top, ["gate_governor", "pilot_flags.env"])      # nothing but the governor's own dir and the one flags file
            self.assertEqual(sorted(os.listdir(os.path.join(b.root, "ops"))), ["gate_registry.json"])
        finally:
            b.close()

    def test_rollback_list_and_unknown_backup(self):
        b = Box()
        try:
            b.run("promote", "item_verify", "--apply", "--i-checked-the-samples", "--reason", "t")
            rc, out = b.run("rollback", "--list")
            self.assertEqual(rc, 0)
            self.assertEqual(len(out.strip().split("\n")), 1)
            self.assertIn("change", out)
            self.assertEqual(b.run("rollback", "--to", "nope", "--apply")[0], 1)
            self.assertEqual(b.run("rollback")[1].count("DRY-RUN"), 1)      # dry-run by default
        finally:
            b.close()

    def test_promote_dry_run_by_default(self):
        b = Box()
        try:
            rc, out = b.run("promote", "item_verify", "--i-checked-the-samples", "--reason", "t")
            self.assertEqual(rc, 0)
            self.assertIn("DRY-RUN", out)
            self.assertIsNone(b.flags_text())
        finally:
            b.close()

    def test_mode_command_persists_and_env_overrides(self):
        b = Box()
        try:
            self.assertIn("shadow", b.run("mode")[1])
            self.assertEqual(b.run("mode", "enforce")[0], 0)
            self.assertIn("enforce", b.run("mode")[1])
            self.assertIn("off (env override)", b.run("mode", OVN_GATE_GOVERNOR="off")[1])
            open(os.path.join(b.state, "gate_governor", "mode"), "w").write("garbage\n")
            self.assertIn("shadow", b.run("mode")[1])        # a typo never enforces
        finally:
            b.close()


class TestRegistry(unittest.TestCase):
    def test_registry_selfchecks_clean_against_this_tree(self):
        b = Box()
        try:
            rc, out = b.run("selfcheck", OVN_DIR=OVN)
            self.assertEqual(rc, 0, out)
        finally:
            b.close()

    def test_registry_covers_every_gate_named_in_the_task(self):
        reg = json.load(open(REG))
        envs = {g["env"] for g in reg["gates"]}
        for e in ("OVN_STAGE_ITEM_VERIFY", "OVN_STAGE_RED_BEFORE", "OVN_STAGE_ITEM_MISTARGET", "OVN_FIXUP_REVERIFY", "OVN_TESTONLY_GUARD", "OVN_DOC_EXECUTOR", "OVN_SUPPLY_MUTATION",
                  "OVN_STAGE_PRECREDIT", "OVN_STAGE_ORDER", "OVN_VERIFY_LINT", "OVN_VERIFY_TIMEOUT_HOLD", "OVN_LQ_RULES_ENFORCE", "OVN_BUILD_BREAK_PARK", "OVN_QA_BASELINE", "OVN_QA_ANTIGAMING",
                  "OVN_QA_SCANNERS", "OVN_QA_MIGRATIONS", "OVN_QA_MUTATION", "OVN_QA_STAGING_CHECK"):
            self.assertIn(e, envs)
        for g in reg["gates"]:
            self.assertTrue(g.get("evidence", {}).get("type"), g["id"])
            if g["evidence"]["type"] != "none":
                self.assertTrue(g["evidence"]["journals"] or g["evidence"].get("patterns"), g["id"])

    def test_lq_rules_registry_matches_code(self):
        reg = json.load(open(REG))
        code = open(os.path.join(OVN, "scripts", "ovn_landing_quality.py")).read()
        import re
        allr = set(re.findall(r"[\"']([A-Z_]+)[\"']", re.search(r"ALL_RULES\s*=\s*\(([^)]*)\)", code).group(1)))
        have = {g["member"] for g in reg["gates"] if g["kind"] == "member"}
        self.assertEqual(have, allr)

    def test_every_pilot_gate_env_is_valid_for_bash_export(self):
        reg = json.load(open(REG))
        import re
        for g in reg["gates"]:
            self.assertRegex(g["env"], r"^[A-Z][A-Z0-9_]*$")
            for v in (g.get("values") or {}).values():
                self.assertRegex(v, r"^[A-Za-z0-9_,.:@+-]*$")


class TestWrapperAndInstaller(unittest.TestCase):
    def test_wrapper_weekly_and_watch_shadow_default(self):
        b = Box()
        try:
            b.seed_fixture()
            e = b.env()
            r = subprocess.run(["bash", WRAP, "weekly"], env=e, capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(os.path.isdir(os.path.join(b.state, "gate_governor", "reports")))
            # watch in shadow with an enforced stalled gate: alert text says WOULD, flags untouched
            _enforce_item_verify(b)
            _blocks(b, "gitlark", "[T4] backend/a.py - do a thing", 4)
            before = b.flags_text()
            r = subprocess.run(["bash", WRAP, "watch"], env=e, capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(b.flags_text(), before)
            self.assertIn("WOULD DEMOTE", open(os.path.join(b.state, "alerts.log")).read())
            # enforce through the persisted mode file: the same wrapper now flips it
            self.assertEqual(b.run("mode", "enforce")[0], 0)
            os.remove(os.path.join(b.state, "gate_governor", "alerted.json"))
            r = subprocess.run(["bash", WRAP, "watch"], env=e, capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("OVN_STAGE_ITEM_VERIFY='shadow'", b.flags_text())
            self.assertIn("cron.log", " ".join(os.listdir(os.path.join(b.state, "gate_governor"))))
        finally:
            b.close()

    def test_wrapper_never_breaks_cron_on_registry_error(self):
        b = Box()
        try:
            open(b.reg, "w").write("garbage")
            r = subprocess.run(["bash", WRAP, "watch"], env=b.env(), capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0)
            self.assertIn("watchdog failed", open(os.path.join(b.state, "alerts.log")).read())
            self.assertEqual(subprocess.run(["bash", WRAP], env=b.env(), capture_output=True, text=True).returncode, 2)   # usage error is the only non-zero
        finally:
            b.close()

    def test_wrapper_watch_is_single_flight(self):
        b = Box()
        try:
            os.makedirs(os.path.join(b.state, "gate_governor"), exist_ok=True)
            import fcntl
            f = open(os.path.join(b.state, "gate_governor", "watchdog.lock"), "a")
            fcntl.flock(f, fcntl.LOCK_EX)
            rc, out = b.run("watchdog")
            f.close()
            self.assertEqual(rc, 0)
            self.assertIn("another run holds the lock", out)
        finally:
            b.close()

    def _stub_crontab(self, td, fail_install=False, corrupt=False, empty=False):
        store = os.path.join(td, "ct.store")
        stub = os.path.join(td, "bin", "crontab")
        os.makedirs(os.path.dirname(stub), exist_ok=True)
        with open(stub, "w") as f:
            f.write('#!/usr/bin/env bash\nS="%s"\ncase "${1:-}" in\n  -l) [ -f "$S" ] || { echo "no crontab for test" >&2; exit 1; }; cat "$S";;\n  *) %s cp "$1" "$S" %s;;\nesac\n' % (
                store, "exit 1;" if fail_install else "", "&& echo '# corrupted' >> \"$S\"" if corrupt else ""))
        os.chmod(stub, 0o755)
        if not empty:
            with open(store, "w") as f:
                f.write("MAILTO=x\n*/5 * * * * echo keepme\n")
        return store

    def _run_inst(self, td, *a, **kw):
        home = os.path.join(td, "home")
        os.makedirs(home, exist_ok=True)
        env = dict(os.environ, HOME=home, PATH=os.path.join(td, "bin") + os.pathsep + os.environ["PATH"], OVN_DIR=OVN, TMPDIR=td)
        env.pop("GG_CRON_BACKUP_DIR", None)
        return subprocess.run(["bash", os.path.join(OVN, "ops", "install_gate_governor_cron.sh")] + list(a), env=env, capture_output=True, text=True, timeout=60)

    def test_installer_dry_run_apply_idempotent_remove(self):
        with tempfile.TemporaryDirectory(prefix="gg_ct.") as td:
            td = os.path.realpath(td)
            store = self._stub_crontab(td)
            orig = open(store).read()
            r = self._run_inst(td)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("DRY-RUN", r.stdout)
            self.assertEqual(open(store).read(), orig)
            r = self._run_inst(td, "--apply")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            t = open(store).read()
            self.assertTrue(t.startswith(orig))                       # outside bytes preserved
            self.assertIn("# >>> GATE-GOVERNOR BEGIN >>>", t)
            self.assertIn("ovn_gate_governor.sh watch", t)
            self.assertIn("ovn_gate_governor.sh weekly", t)
            self.assertEqual(t.count("keepme"), 1)
            bk = os.listdir(os.path.join(td, "home", "crontab-backups"))
            self.assertEqual(len(bk), 1)
            self.assertEqual(open(os.path.join(td, "home", "crontab-backups", bk[0])).read(), orig)
            self.assertEqual(oct(os.stat(os.path.join(td, "home", "crontab-backups", bk[0])).st_mode & 0o777), "0o600")
            r = self._run_inst(td, "--apply")
            self.assertIn("no change", r.stdout)
            self.assertEqual(len(os.listdir(os.path.join(td, "home", "crontab-backups"))), 1)   # no backup when nothing changes
            r = self._run_inst(td, "--apply", "--remove")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual(open(store).read(), orig)                 # byte-exact rollback

    def test_installer_refuses_when_crontab_unreadable_and_restores_on_bad_readback(self):
        with tempfile.TemporaryDirectory(prefix="gg_ct.") as td:
            td = os.path.realpath(td)
            store = self._stub_crontab(td, empty=True)
            r = self._run_inst(td, "--apply")
            self.assertEqual(r.returncode, 2)
            self.assertFalse(os.path.exists(store))
        with tempfile.TemporaryDirectory(prefix="gg_ct.") as td:
            td = os.path.realpath(td)
            store = self._stub_crontab(td, corrupt=True)
            orig = open(store).read()
            r = self._run_inst(td, "--apply")
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("restoring", r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
