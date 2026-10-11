#!/usr/bin/env python3
"""qa/prod_alembic_snapshot.py (2026-10-10, review finding F3): the promote's prod-alembic gate never had prod evidence because only a manual `record` wrote
state/prod_alembic/<repo>.json. The snapshot script reads the public prod /health (a local fake server here) and records db_revision through prod_alembic_check.cmd_record,
and the REAL gate (prod_alembic_check.check_ref) then turns UNVERIFIED into PASS for a strict-ancestor upgrade (today's iptv_apps 0012 -> 0013 case).
Negative controls: every bad reading (HTTP 500, HTML, no field, null, 'unknown', hostile text, refused connection) leaves an existing good snapshot untouched and exits 3.
A mutation section breaks each rule in a temp copy and shows the scenarios then fail."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
if not os.path.isfile(os.path.join(QA, "prod_alembic_snapshot.py")) or not os.path.isfile(os.path.join(QA, "prod_alembic_check.py")):
    print("  SKIP: qa/prod_alembic_snapshot.py not installed here")
    sys.exit(0)

P = F = 0
QUIET = False


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        if not QUIET:
            print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="prodsnap-test-"))
import atexit
atexit.register(lambda: shutil.rmtree(T, ignore_errors=True))      # also on a crash / sys.exit
STATE = os.path.join(T, "state")
os.makedirs(STATE)
for k in list(os.environ):
    if k.startswith("QA_PROD_ALEMBIC") or k in ("QA_STATE_DIR", "OVN_DIR", "OVN_REPOS_DIR"):
        os.environ.pop(k)
os.environ["QA_STATE_DIR"] = STATE

RESP = {"status": 200, "body": "", "ctype": "application/json", "hits": 0, "agent": ""}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        RESP["hits"] += 1
        RESP["agent"] = self.headers.get("User-Agent", "")
        data = RESP["body"].encode()
        self.send_response(RESP["status"])
        self.send_header("Content-Type", RESP["ctype"])
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


srv = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d/health" % srv.server_port
os.environ["QA_PROD_ALEMBIC_URL_IPTV_APPS"] = URL
SNAP = os.path.join(STATE, "prod_alembic", "iptv_apps.json")


def health(**kw):
    d = {"status": "healthy", "commit": "6e66666", "db_revision": "0012_referral_hardening", "alembic_head": "0012_referral_hardening", "migrations": "current"}
    d.update(kw)
    RESP.update(status=200, body=json.dumps(d), ctype="application/json")


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    for m in ("prod_alembic_check", "qa_common"):
        sys.modules.pop(m, None)       # a mutant must import its OWN sibling copy
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def clear():
    shutil.rmtree(os.path.join(STATE, "prod_alembic"), ignore_errors=True)


def snap():
    try:
        return json.load(open(SNAP))
    except (OSError, ValueError):
        return None


def mk_repo():
    """A candidate with alembic migrations 0011 -> 0012 -> 0013 (head 0013), like today's iptv_apps promote."""
    rd = os.path.join(T, "repos", "iptv_apps")
    shutil.rmtree(rd, ignore_errors=True)
    os.makedirs(os.path.join(rd, "iptv-backend", "alembic", "versions"))
    v = os.path.join(rd, "iptv-backend", "alembic", "versions")
    for rev, down in (("0011_x", None), ("0012_referral_hardening", "0011_x"), ("0013_sub_last_event_ms", "0012_referral_hardening")):
        open(os.path.join(v, rev + ".py"), "w").write('revision = "%s"\ndown_revision = %s\n' % (rev, ('"%s"' % down) if down else "None"))
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    subprocess.run("git init -q . && git add -A && git commit -qm c && git branch -M develop", shell=True, cwd=rd, env=env, check=True, capture_output=True)
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=rd, capture_output=True, text=True).stdout.strip()
    os.environ["OVN_REPOS_DIR"] = os.path.join(T, "repos")
    return sha


def suite(S, label=""):
    PAC = sys.modules.get("prod_alembic_check")
    # ---- S1 good reading is recorded in the gate's own snapshot format
    clear(); health()
    t0 = time.time()
    ok_, msg = S.refresh("iptv_apps")
    j = snap() or {}
    ok(label + "S1 good /health: recorded", ok_ and j.get("revision") == "0012_referral_hardening", (ok_, msg, j))
    ok(label + "S1 snapshot has exactly the `record` format {repo, revision, fetched_at (fresh)}", set(j) == {"repo", "revision", "fetched_at"} and j.get("repo") == "iptv_apps" and t0 - 2 <= j.get("fetched_at", 0) <= time.time() + 2, j)
    ok(label + "S1 the request identifies itself (plain GET, no credentials)", RESP["agent"].startswith("shrike-prod-alembic-snapshot"), RESP["agent"])

    # ---- S2 the GATE now has evidence: UNVERIFIED -> PASS for a strict-ancestor upgrade (today's 0012 -> 0013 promote); prod ahead -> FAIL
    sha = mk_repo()
    clear()
    before = PAC.check_ref("iptv_apps", sha)
    ok(label + "S2 gate WITHOUT snapshot: UNVERIFIED (the F3 defect: every promote said this)", before["verdict"] == "UNVERIFIED" and "no read-only prod alembic snapshot" in before["summary"], before)
    health()
    S.refresh("iptv_apps")
    after = PAC.check_ref("iptv_apps", sha)
    ok(label + "S2 gate AFTER the snapshot: PASS, 1 pending migration (0012 -> 0013)", after["verdict"] == "PASS" and "strict ancestor" in after["summary"] and "1 pending" in after["summary"], after)
    clear(); health(db_revision="0099_from_the_future")
    S.refresh("iptv_apps")
    ahead = PAC.check_ref("iptv_apps", sha)
    ok(label + "S2 prod revision the candidate does not know: the gate FAILs (prod ahead / diverged) - the snapshot feeds the real gate", ahead["verdict"] == "FAIL", ahead)

    # ---- S3 bad readings never overwrite a good snapshot and never claim success
    bad_cases = [
        ("HTTP 500", dict(status=500, body="boom", ctype="text/plain")),
        ("HTTP 203 (2xx but not 200) with a believable body", dict(status=203, body=json.dumps({"db_revision": "0012_referral_hardening"}), ctype="application/json")),
        ("HTTP 404", dict(status=404, body="{}", ctype="application/json")),
        ("HTML error page with 200", dict(status=200, body="<html>Application failed to respond</html>", ctype="text/html")),
        ("JSON array", dict(status=200, body="[1,2]", ctype="application/json")),
        ("no db_revision field", dict(status=200, body=json.dumps({"status": "healthy"}), ctype="application/json")),
        ("db_revision null", dict(status=200, body=json.dumps({"db_revision": None}), ctype="application/json")),
        ("db_revision empty", dict(status=200, body=json.dumps({"db_revision": "  "}), ctype="application/json")),
        ("db_revision 'unknown'", dict(status=200, body=json.dumps({"db_revision": "unknown"}), ctype="application/json")),
        ("db_revision 'error'", dict(status=200, body=json.dumps({"db_revision": "error"}), ctype="application/json")),
        ("db_revision not a string", dict(status=200, body=json.dumps({"db_revision": 12}), ctype="application/json")),
        ("db_revision with shell/path characters", dict(status=200, body=json.dumps({"db_revision": "0012; rm -rf /"}), ctype="application/json")),
        ("db_revision with a path", dict(status=200, body=json.dumps({"db_revision": "../../etc/passwd"}), ctype="application/json")),
    ]
    for name, resp in bad_cases:
        clear(); health(); S.refresh("iptv_apps"); good = snap()
        RESP.update(resp)
        ok_, msg = S.refresh("iptv_apps")
        ok(label + "S3 %s: not recorded, existing good snapshot untouched, message says so" % name, (not ok_) and snap() == good and "left untouched" in msg, (ok_, msg, snap()))
    clear(); health(); S.refresh("iptv_apps"); good = snap()
    os.environ["QA_PROD_ALEMBIC_URL_IPTV_APPS"] = "http://127.0.0.1:1/health"
    ok_, msg = S.refresh("iptv_apps")
    ok(label + "S3 connection refused: not recorded, snapshot untouched", (not ok_) and snap() == good and "request failed" in msg, (ok_, msg))
    os.environ["QA_PROD_ALEMBIC_URL_IPTV_APPS"] = URL

    # ---- S4 misc
    clear(); health()
    ok_, msg = S.refresh("iptv_apps", dry=True)
    ok(label + "S4 dry run: reports the revision, records nothing", ok_ and "0012_referral_hardening" in msg and snap() is None, (ok_, msg))
    ok_, msg = S.refresh("billwatch")
    ok(label + "S4 repo without a known /health revision field: not recorded, says why", (not ok_) and "no /health URL known" in msg)
    os.environ["QA_PROD_ALEMBIC_SNAPSHOT"] = "0"
    hits = RESP["hits"]
    ok_, msg = S.refresh("iptv_apps")
    os.environ.pop("QA_PROD_ALEMBIC_SNAPSHOT")
    ok(label + "S4 QA_PROD_ALEMBIC_SNAPSHOT=0 kill switch: no request, no write", ok_ and RESP["hits"] == hits and snap() is None, msg)
    clear(); health(db_revision="0013_sub_last_event_ms")
    S.refresh("iptv_apps")
    health(db_revision="0014_next")
    S.refresh("iptv_apps")
    ok(label + "S4 a later reading replaces the earlier one", (snap() or {}).get("revision") == "0014_next")
    clear()
    os.environ["QA_PROD_ALEMBIC_URL_IPTV_APPS"] = "http://127.0.0.1:1/health"      # the default is dead: only an honoured --url can succeed
    ok_, msg = S.refresh("iptv_apps", url="http://127.0.0.1:%d/other" % srv.server_port)
    os.environ["QA_PROD_ALEMBIC_URL_IPTV_APPS"] = URL
    ok(label + "S4 --url override is honoured", ok_ and (snap() or {}).get("revision") == "0014_next", (ok_, msg))


S = load(os.path.join(QA, "prod_alembic_snapshot.py"), "prod_alembic_snapshot_under_test")
suite(S)

# ---- real CLI process: exit codes + output line
clear(); health()
r = subprocess.run([sys.executable, os.path.join(QA, "prod_alembic_snapshot.py"), "--repo", "iptv_apps"], capture_output=True, text=True, env=os.environ, timeout=60)
ok("CLI: exit 0 + one 'prod-alembic-snapshot recorded' line, snapshot written", r.returncode == 0 and "recorded prod alembic revision 0012_referral_hardening" in r.stdout and snap() is not None, r.stdout + r.stderr)
RESP.update(status=500, body="x", ctype="text/plain")
r = subprocess.run([sys.executable, os.path.join(QA, "prod_alembic_snapshot.py"), "--repo", "iptv_apps"], capture_output=True, text=True, env=os.environ, timeout=60)
ok("CLI: exit 3 on a bad reading (never exit 0 for a failed refresh)", r.returncode == 3 and "left untouched" in r.stdout, r.stdout)
r = subprocess.run([sys.executable, os.path.join(QA, "prod_alembic_snapshot.py")], capture_output=True, text=True, env=os.environ, timeout=60)
ok("CLI: no --repo prints usage, exit 2", r.returncode == 2 and "prod_alembic_snapshot.py --repo" in r.stdout)

# ================= mutation proofs
MUT = [
    ("any db_revision accepted (no validation)", "    if v.lower() in NOT_A_REVISION or not REV_OK.match(v):", "    if False:"),
    ("'unknown' & friends not rejected", 'NOT_A_REVISION = {"unknown", "none", "null", "error", "n/a", "na", "unavailable", "pending", "undefined", "false", "true", "current", "head", "base"}', "NOT_A_REVISION = set()"),
    ("non-200 treated as data", '            if r.status != 200:\n                return None, "HTTP %d" % r.status\n', ""),
    ("HTML body accepted as JSON", '    try:\n        j = json.loads(raw)\n    except ValueError:\n        return None, "body is not JSON (HTML error page?)"', "    j = json.loads(raw) if raw.startswith('{') else {'db_revision': 'html-page'}"),
    ("failed refresh overwrites with 'unknown'", '        if j is None:\n            return False, "%s: %s - snapshot left untouched" % (u, note)', '        if j is None:\n            pac.cmd_record(["--repo", repo, "--revision", "unknown"])\n            return False, "%s: %s - snapshot left untouched" % (u, note)'),
    ("nothing is ever recorded", '        res = pac.cmd_record(["--repo", repo, "--revision", rev])', '        res = {"verdict": "NA", "summary": "recorded"}'),
    ("dry run records", '        if dry:\n            return True,', '        if False:\n            return True,'),
    ("kill switch ignored", '        if os.environ.get("QA_PROD_ALEMBIC_SNAPSHOT") == "0":', "        if False:"),
    ("exit code always 0", "    return 0 if ok else 3", "    return 0"),
    ("--url override ignored", "    return override or os.environ.get", "    return os.environ.get"),
]
if os.environ.get("PRODSNAP_SKIP_MUTATION") != "1":
    src = open(os.path.join(QA, "prod_alembic_snapshot.py")).read()
    for label, old, new in MUT:
        if old not in src:
            ok("mutation anchor present: " + label, False, "anchor not found in prod_alembic_snapshot.py (update the test)")
            continue
        mdir = os.path.join(T, "mut")
        shutil.rmtree(mdir, ignore_errors=True)
        shutil.copytree(QA, mdir, ignore=shutil.ignore_patterns("__pycache__", "acceptance_pilot", "device_lane", "patches"))
        open(os.path.join(mdir, "prod_alembic_snapshot.py"), "w").write(src.replace(old, new, 1))
        p0, f0 = P, F
        QUIET = True
        try:
            M = load(os.path.join(mdir, "prod_alembic_snapshot.py"), "mut_" + str(abs(hash(label))))
            suite(M, "[mut] ")
            if label == "exit code always 0":
                RESP.update(status=500, body="x", ctype="text/plain")
                rr = subprocess.run([sys.executable, os.path.join(mdir, "prod_alembic_snapshot.py"), "--repo", "iptv_apps"], capture_output=True, text=True, env=os.environ, timeout=60)
                if rr.returncode != 3:
                    F += 1
        except Exception:
            F += 1
        QUIET = False
        caught = F > f0
        P, F = p0, f0
        ok("mutation CAUGHT by the suite: " + label, caught)

shutil.rmtree(T, ignore_errors=True)
print("test_prod_alembic_snapshot: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
