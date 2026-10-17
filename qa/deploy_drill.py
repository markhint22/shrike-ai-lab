#!/usr/bin/env python3
"""deploy_drill.py - QA Phase 4: BROKEN-DEPLOY DRILL. Proves, on fixtures only, that the promote evidence would HOLD a broken staging result.

  python3 qa/deploy_drill.py run [--min-hours H] [--samples N] [--interval-s S] [--mutant cors|write_read|recency] [--no-record]

It NEVER touches real staging or prod: every probe goes to a loopback stub server started by this process (QA_SMOKE_ALLOW_LOCAL=1 is set only for the
duration of the drill, the probe's own URL allow-list refuses everything else), the state dir is a private temp dir (QA_STATE_DIR), the staging-deploy and
prod-deploy evidence are in-memory fixtures, and nothing is pushed or notified. The password used against the stub is random per run and is scrubbed from the report.

Injected failure classes (the 4 REQUIRED ones, each must make the promote HOLD with the gate in ENFORCE mode on fixtures):
  stale_sha         staging serves a healthy but OLD build (provenance FAIL in the soak probe; staging_check relation MISMATCH_BEHIND -> promote_gate.decide_block)
  health_500        /health answers 500
  cors_failure      the CORS preflight from the real frontend origin carries no allow-origin
  readback_failure  the DB write succeeds (2xx) but the row is not visible on read-back
Outage classes (must hold at the END of the replay; a FAIL of the drill when not): outage_after_clean (2 h clean, then staging drops every connection: probe rows are
UNVERIFIED with no served sha) and dead_probe (2 h clean, then the cron stops writing rows). Both exercise the soak summary's recency check.
Extra, informational (reported, not part of the 4-of-4): slow (every request slower than the slow threshold), late_onset (clean for the first N samples,
then 500s: the case that sets the soak minimum), and the POSTCHECK fixtures (prod deploy FAILED -> promote_postcheck.evaluate says FAILED so the EMERGENCY
path fires; the promoted SHA never appears -> never SUCCESS).
A control run (clean stub) must NOT hold, or the drill reports a false-positive gate.

How "would hold" is decided: for each class the drill replays N soak samples (default 12 at 15 min = 3 h, synthetic timestamps), and after EVERY sample asks the
real code the real question: soak_probe.summarize(...) -> promote_gate.decide_soak_block("enforce", decision, repo, allow-list=[repo]) (+ staging_check/decide_block
for the stale class). The promote "would proceed" at the first sample where nothing blocks; the class is HELD only if that never happens.
Soak minimum: the drill reports each class's detection time (hours from the first sample to the first bad one) and `recommended_min_hours` = the slowest detection
+ one interval, rounded up to 15 min (floor 1 h). The late_onset class proves why the number matters: with a minimum shorter than its onset the promote passes
BEFORE the failure appears (reported as not held).
Verdict (shadow-recorded to state/qa_shadow/deploy_drill.jsonl): PASS (4/4 held, control proceeds, late_onset held at the configured minimum) | FAIL (a required class
would not hold, or the control was blocked) | FLAG (all 4 held but late_onset slipped past the configured minimum). Exit code 0 always.
"""
import contextlib
import json
import math
import os
import secrets
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

GATE = "deploy_drill"
REPO = "drillrepo"
ORIGIN = "https://app.drill.example"
OLD_SHA = "a" * 40
CAND_SHA = "b" * 40
REQUIRED = ("stale_sha", "health_500", "cors_failure", "readback_failure")
# Must hold AT THE END of the replay (a promote attempted after the outage): a clean streak that is followed by an unreachable staging / a dead probe is no soak.
# The promote legitimately passes BEFORE the outage (2 h clean), so "never passes" is the wrong test for these two.
OUTAGE = ("outage_after_clean", "dead_probe")


# ------------------------------------------------------------------------------------------------ the stub staging server (loopback, scripted failure modes)
class StubStaging:
    """A tiny in-memory 'staging backend'. Modes: clean | stale_sha | health_500 | cors_missing | bad_readback | readback_once (ONE lost write, an overlapping QA writer) | slow | boom (500 on the business endpoint) | down (drops every connection: staging unreachable).
    Records every request in .hits as (method, path). `slow_s` is the per-request delay of the slow mode."""

    def __init__(self, email="drill@example.com", password="drill-pass", served_sha=CAND_SHA, stale_sha=OLD_SHA, slow_s=0.12):
        self.mode, self.email, self.password = "clean", email, password
        self.served_sha, self.stale_sha, self.slow_s = served_sha, stale_sha, slow_s
        self.notes, self.next_id, self.hits, self.lock = {}, 1, [], threading.Lock()
        self.lost_left = 1
        stub = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):  # silence
                pass

            def _send(self, code, obj=None, headers=None):
                body = json.dumps(obj if obj is not None else {}).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                for k, v in (headers or {}).items():
                    self.send_header(k, v)
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def _body(self):
                n = int(self.headers.get("Content-Length") or 0)
                try:
                    return json.loads(self.rfile.read(n).decode() or "{}") if n else {}
                except ValueError:
                    return {}

            def _authed(self):
                return self.headers.get("Authorization", "") == "Bearer stub-token-" + stub.password[:4]

            def handle_any(self):
                with stub.lock:
                    stub.hits.append((self.command, self.path.split("?")[0]))
                    mode = stub.mode
                if mode == "down":                      # unreachable staging: no HTTP response at all (soak probe: UNVERIFIED, no served sha)
                    self.close_connection = True
                    return
                if mode == "slow":
                    time.sleep(stub.slow_s)
                path = self.path.split("?")[0]
                if self.command == "OPTIONS":
                    h = {}
                    org = self.headers.get("Origin", "")
                    if mode != "cors_missing" and org == ORIGIN:
                        h = {"Access-Control-Allow-Origin": org, "Access-Control-Allow-Methods": "GET,POST,DELETE", "Access-Control-Allow-Headers": "authorization"}
                    return self._send(200, {}, h)
                if path == "/health":
                    if mode == "health_500":
                        return self._send(500, {"detail": "boom"})
                    return self._send(200, {"status": "ok", "commit": stub.stale_sha if mode == "stale_sha" else stub.served_sha})
                if path == "/api/auth/login" and self.command == "POST":
                    b = self._body()
                    if b.get("email") == stub.email and b.get("password") == stub.password:
                        return self._send(200, {"access_token": "stub-token-" + stub.password[:4]})
                    return self._send(401, {"detail": "bad credentials"})
                if not self._authed():
                    return self._send(401, {"detail": "unauthorized"})
                if path == "/api/items" and self.command == "GET":
                    if mode == "boom":
                        return self._send(500, {"detail": "boom"})
                    return self._send(200, {"items": [1, 2]})
                if path == "/api/notes" and self.command == "POST":
                    b = self._body()
                    with stub.lock:
                        nid = stub.next_id
                        stub.next_id += 1
                        lost = mode == "bad_readback" or (mode == "readback_once" and stub.lost_left > 0)
                        if mode == "readback_once" and stub.lost_left > 0:
                            stub.lost_left -= 1
                        if not lost:
                            stub.notes[nid] = b.get("title", "")
                    return self._send(201, {"id": nid})
                if path == "/api/notes" and self.command == "GET":
                    with stub.lock:
                        return self._send(200, [{"id": k, "title": v} for k, v in stub.notes.items()])
                if path.startswith("/api/notes/") and self.command == "DELETE":
                    with stub.lock:
                        stub.notes.pop(int(path.rsplit("/", 1)[1]) if path.rsplit("/", 1)[1].isdigit() else -1, None)
                    return self._send(204, {})
                return self._send(404, {"detail": "not found"})

            do_GET = do_POST = do_DELETE = do_OPTIONS = handle_any

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.httpd.daemon_threads = True
        self.base = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def drill_config(email_env="QA_SMOKE_DRILL_EMAIL", pw_env="QA_SMOKE_DRILL_PASSWORD"):
    """A staging_smoke-format config for the stub (same cells as the real ones: health, login, one business endpoint, write+read-back, cors)."""
    return {"defaults": {"timeout_s": 5, "deny_origin": "https://evil.example"}, "repos": {REPO: {
        "health": {"path": "/health", "json_has": "status"},
        "login": {"kind": "json", "path": "/api/auth/login", "token_key": "access_token",
                  "creds": {"email_env": email_env, "password_env": pw_env, "file": REPO}},
        "business": [{"name": "items (authenticated)", "path": "/api/items", "auth": True, "json_has": "items"},
                     {"name": "auth guard rejects anonymous", "path": "/api/items", "auth": False, "expect_status": 401}],
        "write_read": {"name": "create note, read it back, delete it",
                       "write": {"method": "POST", "path": "/api/notes", "body": {"title": "soak {marker}"}, "capture": {"id": "id"}},
                       "read": {"path": "/api/notes", "expect_in_list": {"field": "id", "value": "{id}"}},
                       "cleanup": {"method": "DELETE", "path": "/api/notes/{id}"}},
        "cors": {"path": "/api/items", "origins": [ORIGIN]}}}}


@contextlib.contextmanager
def sandbox_env(email, password, state_dir):
    """Process env for the duration of a drill: loopback allowed for the staging allow-list, private state dir, stub credentials."""
    keys = ("QA_SMOKE_RETRY_S", "OVN_SOAK_RETRY_SLEEP_S", "QA_SMOKE_ALLOW_LOCAL", "QA_STATE_DIR", "QA_SMOKE_DRILL_EMAIL", "QA_SMOKE_DRILL_PASSWORD")
    old = {k: os.environ.get(k) for k in keys}
    os.environ.update({"QA_SMOKE_RETRY_S": "0", "OVN_SOAK_RETRY_SLEEP_S": "0", "QA_SMOKE_ALLOW_LOCAL": "1", "QA_STATE_DIR": state_dir, "QA_SMOKE_DRILL_EMAIL": email, "QA_SMOKE_DRILL_PASSWORD": password})
    try:
        yield
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


# ------------------------------------------------------------------------------------------------ replay
def anc_fixture(a, b):
    """Fixture lineage: only identical shas are related (OLD is behind CAND, never a descendant of it)."""
    return a == b


def pg_decide(*a):
    import promote_gate as pg
    return pg.decide_soak_block(*a)


def replay(stub, mode_at, n, interval_s, min_h, skip, t0, candidate=CAND_SHA, silent_after=None):
    """Run n real probes against the stub (mode_at(i) -> mode for sample i) with synthetic timestamps, then walk the prefixes asking promote_gate.
    `silent_after` (a sample count): the final summary is read at that sample's time although only n rows exist (the probe went quiet).
    -> dict(rows, first_pass_index, first_bad_index, last_summary)."""
    import promote_gate as pg
    import soak_probe as sp
    conf = drill_config()
    cfg, dfl = conf["repos"][REPO], conf["defaults"]
    rows = []
    for i in range(n):
        stub.mode = mode_at(i)
        rows.append(sp.sample(REPO, stub.base, cfg, dfl, candidate=candidate, ts=t0 + i * interval_s, skip=skip,
                              slow_threshold_ms=int(stub.slow_s * 1000 * 0.5) if stub.mode == "slow" else 8000))
        rows[-1]["_t"] = t0 + i * interval_s
    first_pass, first_bad, last = None, None, None
    for i in range(n):
        s = sp.summarize(rows[:i + 1], REPO, candidate, now=t0 + i * interval_s, is_anc=anc_fixture, min_h=min_h, interval_s=interval_s)
        last = s
        if first_bad is None and sp.is_bad(rows[i]):
            first_bad = i
        if first_pass is None and not pg.decide_soak_block("enforce", s["decision"], REPO, [REPO]):   # the promote proceeds at the first sample the enforced gate lets through
            first_pass = i
    if silent_after is not None:
        last = sp.summarize(rows, REPO, candidate, now=t0 + silent_after * interval_s, is_anc=anc_fixture, min_h=min_h, interval_s=interval_s)
    return {"rows": rows, "first_pass_index": first_pass, "first_bad_index": first_bad, "last": last}


def staging_check_holds():
    """The stale-SHA class through the REAL staging_check.decide -> promote_gate.decide_block (enforce): the mocked provider is an in-memory deploy list."""
    import promote_gate as pg
    import staging_check as sc
    deps = sc.normalize([{"id": "stale0001", "status": "SUCCESS", "createdAt": "2026-10-17T08:00:00Z", "meta": {"commitHash": OLD_SHA, "branch": "develop"}}])

    def is_anc(a, b):  # OLD is an ancestor of the candidate, not the reverse
        return (a, b) == (OLD_SHA, CAND_SHA)
    rel, reason, served = sc.decide(CAND_SHA, deps, is_anc)
    block, unverified, why = pg.decide_block("enforce", sc.VERDICT_OF[rel], rel, True, "ok")
    return {"relation": rel, "served": served[:10], "block": block, "reason": why, "detail": reason[:120]}


def postcheck_cases():
    """promote_postcheck.evaluate on prod-deploy fixtures: it must say FAILED for a failed deploy of the promoted SHA and never SUCCESS when it never appears."""
    import promote_postcheck as pp
    import staging_check as sc

    def dep(i, status, sha, ts):
        return {"id": i, "status": status, "createdAt": ts, "meta": {"commitHash": sha, "branch": "main"}}
    cases = []
    failed = sc.normalize([dep("prod0001", "FAILED", CAND_SHA, "2026-10-17T09:00:00Z"), dep("prod0000", "SUCCESS", OLD_SHA, "2026-10-16T09:00:00Z")])
    st, _ = pp.evaluate(REPO, CAND_SHA, failed)
    cases.append({"case": "prod deploy of the promoted sha FAILED (prod still on the old build)", "status": st, "detects": st == "FAILED", "action": "EMERGENCY push + alerts.log ERROR"})
    stale = sc.normalize([dep("prod0000", "SUCCESS", OLD_SHA, "2026-10-16T09:00:00Z")])
    st, _ = pp.evaluate(REPO, CAND_SHA, stale)
    cases.append({"case": "promoted sha never appears as a prod deploy (stale / not deployed)", "status": st, "detects": st != "SUCCESS", "action": "keeps polling, UNVERIFIED alerts.log WARN at timeout; never SUCCESS"})
    ok = sc.normalize([dep("prod0002", "SUCCESS", CAND_SHA, "2026-10-17T09:00:00Z")])
    st, _ = pp.evaluate(REPO, CAND_SHA, ok)
    cases.append({"case": "control: healthy prod deploy of the promoted sha", "status": st, "detects": st != "SUCCESS", "control": True, "action": "SUCCESS logged"})
    return cases


def remove_own_state(state):
    """Delete the drill's private temp dir, and ONLY that: absolute, named drill-state-*, a direct child of the temp root, not a symlink. -> True when removed."""
    import shutil
    if not (os.path.isabs(state) and os.path.basename(state).startswith("drill-state-") and not os.path.islink(state) and os.path.isdir(state)
            and os.path.realpath(os.path.dirname(state)) == os.path.realpath(tempfile.gettempdir())):
        return False
    shutil.rmtree(state, ignore_errors=True)
    return True


def ceil_quarter(h):
    return math.ceil(h * 4 - 1e-9) / 4.0


def run_drill(min_h=None, samples=12, interval_s=900, mutant="", late_onset_index=5, work=None):
    import soak_probe as sp
    min_h = sp.min_hours() if min_h is None else float(min_h)
    skip = {"cors": ("cors",), "write_read": ("write_read",)}.get(mutant, ())
    stale_save = sp.STALE_FACTOR
    if mutant == "recency":                      # remove the recency check from the summary: the outage classes must then 'not hold'
        sp.STALE_FACTOR = 10 ** 9
    try:
        return _run_drill(min_h, samples, interval_s, mutant, late_onset_index, work, skip)
    finally:
        sp.STALE_FACTOR = stale_save


def _run_drill(min_h, samples, interval_s, mutant, late_onset_index, work, skip):
    import soak_probe as sp
    email, password = "drill-%s@example.com" % secrets.token_hex(3), secrets.token_urlsafe(14) + "Aa1"
    own_state = work is None
    state = work or tempfile.mkdtemp(prefix="drill-state-")
    t0 = 1_800_000_000.0           # a fixed synthetic origin: the drill never depends on the wall clock
    classes = []
    with sandbox_env(email, password, state):
        import staging_smoke as ss
        ss.SECRETS[:] = []
        stub = StubStaging(email, password).start()
        try:
            def run_class(name, mode_at, required, expect, note="", n=None, end_only=False, silent_after=None):
                r = replay(stub, mode_at, n or samples, interval_s, min_h, skip, t0, silent_after=silent_after)
                held = r["first_pass_index"] is None
                end_blocked = bool(pg_decide("enforce", r["last"]["decision"], REPO, [REPO]))
                if end_only:
                    held = end_blocked
                extra = {}
                if name == "stale_sha":
                    sc_hold = staging_check_holds()
                    extra["staging_check"] = sc_hold
                    held = held or sc_hold["block"]
                detect_h = None if r["first_bad_index"] is None else round(r["first_bad_index"] * interval_s / 3600.0, 2)
                classes.append({"class": name, "required": required, "held": held, "expected_held": expect, "soak_would_hold": r["first_pass_index"] is None,
                                "promote_passes_at_sample": r["first_pass_index"], "blocked_at_end": end_blocked, "detected_after_h": detect_h, "last_verdict": r["last"]["verdict"],
                                "last_decision": r["last"]["decision"], "sample_verdicts": [x["verdict"] for x in r["rows"]], "note": note, **extra,
                                "summary": r["last"]["summary"][:200], "stale": r["last"].get("stale"), "signatures": sorted({s for x in r["rows"] for s in (x["details"].get("signatures") or [])})[:5]})
            run_class("control_clean", lambda i: "clean", False, False, "a clean staging must let the promote through (false-positive check)")
            run_class("stale_sha", lambda i: "stale_sha", True, True)
            run_class("health_500", lambda i: "health_500", True, True)
            run_class("cors_failure", lambda i: "cors_missing", True, True)
            run_class("readback_failure", lambda i: "bad_readback", True, True)
            run_class("slow", lambda i: "slow", False, True, "informational: every request slower than the slow threshold (3 samples are enough to show it is held)", n=3)
            run_class("late_onset", lambda i: "clean" if i < late_onset_index else "boom", False, True,
                      "clean for %d sample(s), then 500s on the business endpoint: the promote must not pass before the onset" % late_onset_index)
            run_class("outage_after_clean", lambda i: "clean" if i < 9 else "down", False, True,
                      "2 h clean, then staging drops every connection (rows UNVERIFIED, no served sha): a promote after the outage must be held", n=16, end_only=True)
            run_class("dead_probe", lambda i: "clean", False, True, "2 h clean, then the probe cron stops writing rows (the summary is read 1.75 h later): no current coverage = no soak",
                      n=9, end_only=True, silent_after=16)
            assert all(h[0] in ("GET", "POST", "DELETE", "OPTIONS") for h in stub.hits)
            hits = len(stub.hits)
        finally:
            stub.stop()
    if own_state:
        remove_own_state(state)
    postcheck = postcheck_cases()
    by = {c["class"]: c for c in classes}
    req = [by[n] for n in REQUIRED]
    not_held = [c["class"] for c in req if not c["held"]]
    control = by["control_clean"]
    control_ok = control["promote_passes_at_sample"] is not None
    late = by["late_onset"]
    detections = [c["detected_after_h"] for c in classes if c["detected_after_h"] is not None]
    rec = max(1.0, ceil_quarter(max(detections) + interval_s / 3600.0)) if detections else None
    outage_not_held = [c["class"] for c in classes if c["class"] in OUTAGE and not c["held"]]
    pc_ok = all(c["detects"] for c in postcheck if not c.get("control")) and not postcheck[-1]["detects"]
    if not_held or outage_not_held or not control_ok or not pc_ok:
        verdict = "FAIL"
        bits = []
        if not_held or outage_not_held:
            bits.append("would not hold: %s" % ", ".join(not_held + outage_not_held))
        if not control_ok:
            bits.append("control (clean) was BLOCKED: the gate is a false positive")
        if not pc_ok:
            bits.append("postcheck fixtures not detected")
        summary = "%d of %d injected failure classes would hold the promote; %s" % (len(REQUIRED) - len(not_held), len(REQUIRED), "; ".join(bits))
    elif not late["held"]:
        verdict = "FLAG"
        summary = "4 of 4 injected failure classes would hold the promote, but the soak minimum %.2fh is shorter than the late-onset failure (promote passed at sample %s): raise it to >= %.2fh" % (
            min_h, late["promote_passes_at_sample"], rec)
    else:
        verdict = "PASS"
        summary = "4 of 4 injected failure classes would hold the promote (enforce, fixtures); control proceeds at sample %s; late-onset caught at min %.2fh; postcheck detects a failed prod deploy" % (
            control["promote_passes_at_sample"], min_h)
    report = {"verdict": verdict, "summary": summary, "classes_required": len(REQUIRED), "classes_held": len(REQUIRED) - len(not_held), "not_held": not_held, "outage_not_held": outage_not_held,
              "mutant": mutant or None, "min_hours": min_h, "interval_s": interval_s, "samples": samples, "recommended_min_hours": rec,
              "control_proceeds": control_ok, "late_onset_held_at_min": late["held"], "classes": classes, "postcheck": postcheck,
              "stub_requests": hits, "touched_real_staging_or_prod": False}
    return scrub_report(report, password, email)


def scrub_report(rep, *secrets_):
    s = json.dumps(rep)
    for v in secrets_:
        if v and len(v) >= 4:
            s = s.replace(v, "***")
    return json.loads(s)


# ------------------------------------------------------------------------------------------------ cli
def _opt(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def main(argv):
    if not argv or argv[0] != "run":
        print(__doc__)
        return 0
    try:
        mh = _opt(argv, "--min-hours")
        rep = run_drill(min_h=float(mh) if mh else None, samples=int(_opt(argv, "--samples", "12")), interval_s=int(_opt(argv, "--interval-s", "900")),
                        mutant=_opt(argv, "--mutant", "") or "")
        res = qc.verdict(rep["verdict"], GATE, "drill", "fixtures", rep["summary"],
                         {k: rep[k] for k in ("classes_held", "classes_required", "not_held", "mutant", "min_hours", "recommended_min_hours", "control_proceeds",
                                              "late_onset_held_at_min", "touched_real_staging_or_prod")})
        if "--no-record" not in argv and not rep["mutant"]:
            qc.record(res)
        print(json.dumps(dict(rep, ts=res["ts"]), sort_keys=True))
    except Exception as ex:  # noqa: BLE001
        print(json.dumps({"verdict": "UNVERIFIED", "summary": "deploy_drill crashed: %s: %s" % (type(ex).__name__, str(ex)[:160])}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
