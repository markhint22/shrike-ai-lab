#!/usr/bin/env python3
"""QA-N1 live-staging e2e v2 (2026-10-09): scripts/qa/e2e/chickadee_staging_e2e.py (box runner), scripts/qa/rc_lifecycle_e2e.py (importable cell), qa/staging_e2e_run.sh
(trigger + serial lock), qa/staging_e2e_ingest.py (shadow rows + one alert per cell/commit), qa/promote_gate.py (shadow evidence line, enforce = commit-matched FAIL only),
qa/qa_scorecard.py (staging_e2e cell), qa/qa_daily_shadow.sh (staging_smoke scheduling), gold row G10.

Everything runs against an IN-PROCESS stub HTTP server impersonating staging (127.0.0.1:0): no network, no Railway CLI, no real credentials (seeded fake ones).
The stub has MODES; each negative control flips ONE cell to FAIL and the test asserts the WHOLE verdict table (every other cell unchanged). Infra controls
(refused / timeout / DNS / 503 / 429) must be UNVERIFIED, never FAIL. At the end every piece of new logic is MUTATED (source rewritten in a temp copy) and the
matching control must stop holding - i.e. the test fails when the logic is broken.
Flaky patterns avoided: no `x | grep -q` under pipefail, no kill -0 on killed children, no greps that can match comments, /private/var paths normalised via realpath."""
import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))                      # scripts/overnight-queue (repo) or ~/overnight-queue (box)
QA = os.path.join(OQ, "qa")
PY = sys.executable


def first_existing(*c):
    return next((x for x in c if os.path.isfile(x)), None)


RUNNER = first_existing(os.path.join(OQ, "scripts", "qa", "e2e", "chickadee_staging_e2e.py"), os.path.join(OQ, "..", "qa", "e2e", "chickadee_staging_e2e.py"))
RC = first_existing(os.path.join(OQ, "scripts", "qa", "rc_lifecycle_e2e.py"), os.path.join(OQ, "..", "qa", "rc_lifecycle_e2e.py"))
if not RUNNER or not RC:
    print("  SKIP: the e2e runner / rc_lifecycle_e2e.py are not present next to this tree (box scratch copy needs scripts/qa synced)")
    sys.exit(0)
RUNNER, RC = os.path.realpath(RUNNER), os.path.realpath(RC)

os.environ["NO_PROXY"] = "127.0.0.1,localhost"  # rc_lifecycle_e2e uses plain urlopen: never let an env proxy sit between the test and its stub
os.environ["QA_E2E_ALLOW_LOCAL"] = "1"          # the host guard accepts loopback ONLY with this (tests)
os.environ["QA_E2E_REREAD_WAIT_S"] = "0"        # the export re-read pause on a provenance mismatch (default 5 s) is off in tests; its own test sets it
os.environ["QA_E2E_MIN_INTERVAL_S"] = "0"       # the 1 req/s throttle may be lowered for loopback ONLY (tests); throttle itself is tested with a fake clock
for k in ("QA_STATE_DIR", "OVN_DIR", "OVN_QA_STAGING_E2E", "QA_E2E_BASE", "QA_E2E_FORCE", "QA_E2E_PREMIUM_EMAIL", "QA_E2E_PREMIUM_PASSWORD", "QA_E2E_FREE_EMAIL", "QA_E2E_FREE_PASSWORD"):
    os.environ.pop(k, None)

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-e2e-test-"))
E = load(RUNNER, "e2e_runner_under_test")
RCM = load(RC, "rc_under_test")

COMMIT = "67ed0626092d5a1be26e7c04242cb684f6169cae"
OTHER = "051c28f9aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
PREMIUM = ("premium.stub@stub.test", "Seed-Premium-Pw-8f2a!xQ")
FREE = ("free.stub@stub.test", "Seed-Free-Pw-1c9d!zR")
PRIVATE_HOSTS = ("127.", "169.254.", "10.", "[::1]", "::1", "localhost")
# secret-shaped seeds are assembled at run time: this file itself holds no scannable secret literal (the scanners gate reads test files too)
SEED_JWT = ".".join(("eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjMifQ", "c2lnbmF0dXJlc2ln"))
SEED_BEARER = "abcdefghijklmnop" + "1234"
SEED_PWKV = "pass" + "word=" + "Hunter2" + "Hunter2"
SEED_TOKKV = "?tok" + "en=" + "abc123def456"


# ==================================================================================================================== the stub
class Stub:
    """Impersonates Chickadee staging. `mode` flags flip one behaviour each (see CONTROLS)."""

    HOT = ("/api/streams", "/api/streams/categories", "/api/vod", "/api/vod/genres", "/api/subscription/status", "/api/profiles", "/api/auth/me")

    def __init__(self, **mode):
        self.mode = dict(mode)
        self.lock = threading.Lock()
        self.requests = []
        self.accounts = {PREMIUM[0]: {"pw": PREMIUM[1], "id": 1, "premium": True, "verified": True, "sub": None},
                         FREE[0]: {"pw": FREE[1], "id": 2, "premium": False, "verified": True, "sub": None}}
        self.tokens = {}          # token -> (email, type)
        self.issued = []          # every token ever issued (secrets for the redaction test)
        self.pw_log = []          # every password a fresh user registered with (ditto)
        self.created_users, self.created_streams = [], []
        self.streams = {}         # id -> (owner, name)
        self.codes = {}           # code -> {owner, status, referee}
        self.redeemed_by = set()
        self.hot_count = 0
        self.hanging, self.release = threading.Event(), threading.Event()   # mode `hang`: a ?token= proxy request parks here (handshake: `hanging` is set when it arrives)
        self.next_id = 100
        self.sub = {}             # user id -> {premium, period_end, latest_ts}
        self.webhook_secret = "stub-webhook-secret-xyz"
        stub = self

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"

            def log_message(self, *a):
                pass

            def _do(self, method):
                u = urllib.parse.urlparse(self.path)
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n) if n else b""
                try:
                    body = json.loads(raw) if raw else None
                except ValueError:
                    body = None
                auth = self.headers.get("Authorization", "")
                with stub.lock:
                    stub.requests.append((method, u.path, u.query))
                if stub.mode.get("delay"):
                    time.sleep(stub.mode["delay"])
                if stub.mode.get("hang") and stub.mode["hang"] in u.path and "token" in u.query:
                    stub.hanging.set()
                    stub.release.wait(120)
                code, payload, hdr = stub.route(method, u.path, urllib.parse.parse_qs(u.query), body, auth)
                data = b"" if code == 204 else (payload if isinstance(payload, bytes) else json.dumps(payload).encode())
                try:
                    self.send_response(code)
                    for k, v in hdr.items():
                        self.send_header(k, v)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except OSError:
                    pass  # the client gave up first (timeout test, 64 KiB body cap): nothing to report

            def do_GET(self):
                self._do("GET")

            def do_POST(self):
                self._do("POST")

            def do_DELETE(self):
                self._do("DELETE")

        class S(ThreadingHTTPServer):
            daemon_threads = True

        self.server = S(("127.0.0.1", 0), H)
        self.port = self.server.server_address[1]
        self.base = "http://127.0.0.1:%d" % self.port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    # ---- openapi (derived by the runner; $ref used on purpose)
    def openapi(self):
        def op(**kw):
            return kw
        j = {"$ref": "#/components/schemas/Json"}
        paths = {
            "/health": {"get": op(responses={"200": {}})},
            "/api/auth/login": {"post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Login"}}}},
                                           responses={"200": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Token"}}}}})},
            "/api/auth/me": {"get": op(security=[{"HTTPBearer": []}], responses={"200": {}})},
            "/api/auth/register": {"post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Register"}}}}, responses={"201": {}})},
            "/api/account/me": {"delete": op(responses={"200": {}})},
            "/api/streams": {"get": op(parameters=[{"name": "limit", "in": "query"}], responses={"200": {"content": {"application/json": {"schema": {"type": "array"}}}}}),
                             "post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/StreamCreate"}}}}, responses={"201": {}})},
            "/api/streams/{stream_id}": {"delete": op(parameters=[{"name": "stream_id", "in": "path", "required": True}], responses={"204": {}})},
            "/api/streams/{stream_id}/proxy": {"get": op(parameters=[{"name": "stream_id", "in": "path", "required": True}, {"name": "token", "in": "query", "required": False}], responses={"200": {}})},
            "/api/streams/import": {"post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Import"}}}}, responses={"200": {}})},
            "/api/streams/import/xtream": {"post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Xtream"}}}}, responses={"200": {}})},
            "/api/streams/relay": {"get": op(parameters=[{"name": "url", "in": "query", "required": True}, {"name": "token", "in": "query"}], responses={"200": {}})},
            "/api/streams/categories": {"get": op(responses={"200": {"content": {"application/json": {"schema": {"type": "array"}}}}})},
            "/api/referrals": {"post": op(responses={"201": {}})},
            "/api/referrals/redeem": {"post": op(requestBody={"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Redeem"}}}}, responses={"200": {}})},
            "/api/vod": {"get": op(parameters=[{"name": "genre", "in": "query"}], responses={"200": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Vod"}}}}})},
            "/api/vod/genres": {"get": op(responses={"200": {"content": {"application/json": {"schema": {"type": "array", "items": {"type": "string"}}}}}})},
            "/api/subscription/status": {"get": op(responses={"200": {}})},
            "/api/profiles": {"get": op(responses={"200": {"content": {"application/json": {"schema": {"type": "array"}}}}})},
        }
        for meth, path in self.mode.get("drop", ()):
            (paths.get(path) or {}).pop(meth, None)
            if path in paths and not paths[path]:
                del paths[path]
        S = {"Json": {"type": "object"}, "Login": {"properties": {"email": {}, "password": {}}, "required": ["email", "password"]},
             "Token": {"properties": {"access_token": {}, "refresh_token": {}, "token_type": {}}}, "Register": {"properties": {"email": {}, "username": {}, "password": {}}, "required": ["email", "username", "password"]},
             "StreamCreate": {"properties": {"name": {}, "url": {}}, "required": ["name", "url"]}, "Import": {"properties": {"url": {}, "content": {}, "name": {}}},
             "Xtream": {"properties": {"server_url": {}, "username": {}, "password": {}}, "required": ["server_url", "username", "password"]},
             "Redeem": {"properties": {"code": {}}, "required": ["code"]}, "Vod": {"type": "object", "properties": {"items": {}, "total": {}}}}
        # staging's real document is ~240 KB: pad ours past the 64 KiB body cap the runner applies to every other response
        return {"openapi": "3.1.0", "info": {"title": "stub", "description": "x" * 150000}, "paths": paths, "components": {"schemas": S}}

    # ---- the application
    def _user(self, tok):
        return self.tokens.get(tok)

    @staticmethod
    def _private(url):
        try:
            u = urllib.parse.urlparse(url)
        except ValueError:
            return True
        if u.scheme not in ("http", "https"):
            return True
        host = (u.hostname or "").lower()
        return any(host.startswith(p.strip("[]")) or host == p.strip("[]") for p in PRIVATE_HOSTS)

    def route(self, method, path, q, body, auth):
        m = self.mode
        tok = auth[7:] if auth.startswith("Bearer ") else None
        with self.lock:
            if path == "/health":
                if m.get("health_503"):
                    return 503, {"detail": "unavailable"}, {}
                return 200, {"status": m.get("status", "healthy"), "commit": m.get("commit", COMMIT), "migrations": m.get("migrations", "current"),
                             "db_revision": "0012_referral_hardening", "alembic_head": "0012_referral_hardening"}, {}
            if path == "/openapi.json":
                return 200, self.openapi(), {}
            if path == "/api/auth/login" and method == "POST":
                if m.get("login_429"):
                    return 429, {"detail": "rate limited"}, {"Retry-After": "60"}
                b = body or {}
                a = self.accounts.get(b.get("email"))
                if not a or a["pw"] != b.get("password") or (a["premium"] and "premium" in m.get("login_reject", ())) or ((not a["premium"]) and "free" in m.get("login_reject", ())):
                    return m.get("login_reject_status", 401), {"detail": "bad credentials"}, {}
                t = "acc-%s-%d" % (os.urandom(6).hex(), a["id"])
                self.tokens[t] = (b["email"], "access")
                self.issued.append(t)
                return 200, {"access_token": t, "refresh_token": "ref-" + t, "token_type": "bearer"}, {}
            if path == "/api/auth/register" and method == "POST":
                b = body or {}
                if not b.get("email") or b["email"] in self.accounts:
                    return 400, {"detail": "exists"}, {}
                self.next_id += 1
                self.accounts[b["email"]] = {"pw": b.get("password"), "id": self.next_id, "premium": False, "verified": bool(m.get("auto_verify", True)), "sub": None}
                self.created_users.append(b["email"])
                self.pw_log.append(b.get("password"))
                return 201, {"id": self.next_id, "email": b["email"], "username": b.get("username"), "email_verified": self.accounts[b["email"]]["verified"]}, {}
            if path == "/api/subscription/revenuecat/webhook" and method == "POST":
                return self._webhook(auth, body)
            u = self._user(tok)
            if path == "/api/auth/me":
                if u is None and not m.get("anon_me_ok"):
                    return 401, {"detail": "Could not validate credentials"}, {}
                if u:
                    self._hot()
                    a = self.accounts[u[0]]
                    return self._maybe_429({"id": a["id"], "email": u[0], "email_verified": a["verified"]})
                return 200, {"id": 0, "email": "anonymous"}, {}
            # proxy accepts ?token= (players cannot set headers)
            mm = re.fullmatch(r"/api/streams/(\d+)/proxy", path)
            if mm:
                qt = (q.get("token") or [None])[0]
                pu = self._user(qt) if qt else u
                if qt and m.get("token_query_playback_only"):
                    pu = self.tokens.get(qt) if (self.tokens.get(qt) or ("", ""))[1] == "playback" else None  # 7d87fbd1: ?token= demanded a playback-type token
                if pu is None and not m.get("open_proxy"):
                    return 401, {"detail": "Could not validate credentials"}, {"WWW-Authenticate": "Bearer"}
                if pu and m.get("proxy_upstream"):   # the real proxy re-raises the ORIGIN's status verbatim: HTTPException(status_code=upstream_status, detail='Upstream returned N for stream')
                    return m["proxy_upstream"], {"detail": "Upstream returned %d for stream" % m["proxy_upstream"]}, {}
                if pu and m.get("proxy_500"):
                    return 500, {"detail": "internal error"}, {}
                if pu and m.get("proxy_not_found"):
                    return 404, {"detail": "Stream not found"}, {}
                s = self.streams.get(int(mm.group(1)))
                if not s and pu:
                    return 404, {"detail": "Stream not found"}, {}
                return 200, b"#EXTM3U\n", {}
            if u is None:
                return 401, {"detail": "Could not validate credentials"}, {}
            email = u[0]
            acct = self.accounts[email]
            if path == "/api/account/me" and method == "DELETE":
                if m.get("delete_fails"):
                    return 500, {"detail": "boom"}, {}
                self.accounts.pop(email, None)
                for t in [t for t, (e, _) in self.tokens.items() if e == email]:
                    del self.tokens[t]
                return 200, {"deleted": True}, {}
            if path == "/api/streams" and method == "POST":
                b = body or {}
                self.next_id += 1
                self.streams[self.next_id] = (email, b.get("name"))
                self.created_streams.append(b.get("name"))
                return 201, {"id": self.next_id, "name": b.get("name")}, {}
            ms = re.fullmatch(r"/api/streams/(\d+)", path)
            if ms and method == "DELETE":
                if m.get("delete_fails"):
                    return 500, {"detail": "boom"}, {}
                self.streams.pop(int(ms.group(1)), None)
                return 204, b"", {}
            if path in ("/api/streams/import", "/api/streams/relay", "/api/streams/import/xtream"):
                if not acct["premium"]:
                    return 403, {"detail": "Stream import requires Premium. Your free trial has ended."}, {}
                url = (body or {}).get("url") if path.endswith("import") else ((body or {}).get("server_url") if path.endswith("xtream") else (q.get("url") or [""])[0])
                accepts = m.get("relay_accepts_private") if path.endswith("relay") else m.get("import_accepts_private")
                if path.endswith("relay") and self._private(url or "") and m.get("relay_guard_missing_502"):
                    return 502, {"detail": "Failed to fetch stream"}, {}   # guard removed: the app tries the fetch, connection refused -> its own 502 (JSON detail)
                if path.endswith("relay") and self._private(url or "") and m.get("relay_edge_502"):
                    return 502, {"status": "error", "code": 502, "message": "Application failed to respond"}, {}   # Railway's edge, not the app
                if self._private(url or "") and not accepts:
                    return 400, {"detail": "URL is not allowed"}, {}
                if path.endswith("import"):
                    return 200, {"success": True, "queued": True, "job_id": "job-1"}, {}
                return 200, {"relayed": True}, {}
            if path == "/api/referrals" and method == "POST":
                code = "REF" + os.urandom(5).hex().upper()
                self.codes[code] = {"owner": email, "status": "pending"}
                return 201, {"code": code, "status": "pending"}, {}
            if path == "/api/referrals/redeem" and method == "POST":
                return self._redeem(email, acct, (body or {}).get("code"))
            if path == "/api/vod":
                self._hot()
                if m.get("vod_500"):
                    return 500, {"detail": "internal error handling %s" % auth}, {}
                if m.get("vod_missing_items"):
                    return self._maybe_429({"total": 5})
                return self._maybe_429({"items": [{"id": 1, "title": "x"}], "total": 1})
            if path == "/api/vod/genres":
                self._hot()
                return self._maybe_429(["Action", "Drama"])
            if path in ("/api/streams", "/api/streams/categories", "/api/profiles") and method == "GET":
                self._hot()
                return self._maybe_429([])
            if path == "/api/subscription/status":
                self._hot()
                s = self.sub.get(acct["id"], {})
                return self._maybe_429({"is_premium": bool(s.get("premium")) or acct["premium"], "tier": "premium" if (s.get("premium") or acct["premium"]) else "free", "is_in_trial": False})
            return 404, {"detail": "not found"}, {}

    def _hot(self):
        self.hot_count += 1

    def _maybe_429(self, payload):
        if self.mode.get("rate_429_at") == self.hot_count:
            return 429, {"detail": "Rate limit exceeded"}, {"Retry-After": "1"}
        return 200, payload, ({"Retry-After": "1"} if self.mode.get("retry_after") else {})

    def _redeem(self, email, acct, code):
        m = self.mode
        if m.get("redeem_reject_all"):
            return 400, {"detail": "This referral code can't be used."}, {}
        ref = self.codes.get(code)
        owner = self.accounts.get(ref["owner"]) if ref else None
        if not m.get("referral_override") and (not acct["verified"] or not owner or not owner["verified"]):
            return 400, {"detail": "This referral code can't be used."}, {}
        if m.get("redeem_500"):
            return 500, {"detail": "boom"}, {}
        if ref is None or (ref["owner"] == email and not m.get("self_redeem_ok")):
            return 400, {"detail": "This referral code can't be used."}, {}
        if not m.get("second_redeem_ok") and (ref["status"] != "pending" or email in self.redeemed_by):
            return 400, {"detail": "This referral code can't be used."}, {}
        ref["status"] = "redeemed"
        self.redeemed_by.add(email)
        return 200, {"days_granted": 7, "trial_ends_at": "2026-10-16T00:00:00Z"}, {}

    def _webhook(self, auth, body):
        if auth != self.webhook_secret:
            return 401, {"detail": "unauthorized"}, {}
        e = (body or {}).get("event") or {}
        uid = int(e.get("app_user_id", 0) or 0)
        s = self.sub.setdefault(uid, {"premium": False, "period_end": 0, "latest_ts": 0})
        now_ms = int(time.time() * 1000)
        t, ts, exp = e.get("type"), e.get("event_timestamp_ms", 0), e.get("expiration_at_ms", 0)
        if t == "INITIAL_PURCHASE":
            s.update(premium=True, period_end=exp, latest_ts=ts)
        elif t == "RENEWAL":
            s.update(premium=True, period_end=exp, latest_ts=max(ts, s["latest_ts"]))
        elif t == "UNCANCELLATION":
            s.update(premium=True, latest_ts=max(ts, s["latest_ts"]))
        elif t == "CANCELLATION":
            if e.get("cancel_reason") == "CUSTOMER_SUPPORT" and exp > now_ms:
                s.update(premium=False)
            elif exp < now_ms and e.get("cancel_reason") == "UNSUBSCRIBE":
                return 200, {"status": "ignored", "reason": "stale"}, {}
        elif t == "EXPIRATION":
            if ts < s["latest_ts"] and not self.mode.get("expiration_never_stale"):
                return 200, {"status": "ignored", "reason": "stale"}, {}
            if not self.mode.get("expiration_never_revokes"):
                s.update(premium=False)
            s["latest_ts"] = max(ts, s["latest_ts"])
        return 200, {"status": "processed"}, {}


# ==================================================================================================================== fixtures
def make_state(name, commit=COMMIT, deploys="ok", creds="ok", creds_mode=0o600, extra_deploys=None, age=60, unlisted_since=None):
    d = os.path.join(T, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, "state", "staging_deploys"))
    st = os.path.join(d, "state")
    now = time.time()
    if deploys != "missing":
        created = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 300))
        dl = [{"id": "dep00001", "status": "SUCCESS", "createdAt": created, "meta": {"commitHash": commit, "branch": "develop"}}]
        if deploys == "building":
            dl.insert(0, {"id": "dep00002", "status": "BUILDING", "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 10)), "meta": {"commitHash": OTHER}})
        if deploys == "failed_latest":
            dl.insert(0, {"id": "dep00002", "status": "FAILED", "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - 10)), "meta": {"commitHash": OTHER}})
        with open(os.path.join(st, "staging_deploys", "iptv_apps.json"), "w") as f:
            json.dump({"repo": "iptv_apps", "fetched_at": now - (4000 if deploys == "stale" else age), "deployments": dl}, f)
    if unlisted_since is not None:   # OTHER was first seen serving (and missing from the export) this many seconds ago: the SECOND sighting that may convict
        json.dump({OTHER: now - unlisted_since}, open(os.path.join(st, "staging_e2e_unlisted.json"), "w"))
    if creds != "absent":
        os.makedirs(os.path.join(st, "qa_creds"), exist_ok=True)
        p = os.path.join(st, "qa_creds", "iptv_apps.json")
        with open(p, "w") as f:
            json.dump({"premium": {"email": PREMIUM[0], "password": PREMIUM[1]}, "free": {"email": FREE[0], "password": FREE[1]}}, f)
        os.chmod(p, creds_mode)
    return st


def run_cells(stub, state, cells=None, **kw):
    return E.run(stub.base, cells, state, **kw)


def verdicts(res):
    return {c["cell"]: c["verdict"] for c in res["cells"]}


BASE_OK = {c: "PASS" for c in E.BOX_CELLS}
PGM = load(os.path.join(QA, "promote_gate.py"), "pg_prelude")   # aggregate_cells / normalize_e2e (pure) - also used by section 7
#@@STUB_END@@  (the G10 replay shim of section 14 exec()s everything above this marker to reuse Stub / make_state / E)


def table(label, stub_modes, state_kw=None, expect=None, cells=None, **kw):
    """Run the full default cell set against a stub with `stub_modes` and assert the WHOLE verdict table: BASE_OK overridden by `expect`."""
    stub = Stub(**stub_modes)
    try:
        st = make_state("tbl", **(state_kw or {}))
        res = run_cells(stub, st, cells, **kw)
        got, want = verdicts(res), dict(BASE_OK, **(expect or {}))
        ok(label, got == want, "got %s want %s | %s" % (got, want, [c["detail"][:90] for c in res["cells"] if got[c["cell"]] != want.get(c["cell"])]))
        return stub, res
    finally:
        stub.stop()


# ==================================================================================================================== 1. benign + request volume + cleanup
print("# 1. benign stub: every default cell PASSes; <= 80 requests; created users/streams are qa-e2e-* and deleted")
stub = Stub()
st = make_state("benign")
res = run_cells(stub, st)
ok("all-good stub: the 7 default cells are PASS in the documented order", verdicts(res) == BASE_OK and [c["cell"] for c in res["cells"]] == list(E.BOX_CELLS), [(c["cell"], c["verdict"], c["detail"][:80]) for c in res["cells"]])
ok("request count <= 80 and the runner's count equals what the server saw (measured: %d)" % len(stub.requests), res["requests"] == len(stub.requests) <= 80 and res["request_budget"] == 80, (res["requests"], len(stub.requests)))
ok("per-cell request volume is reported; total = cells + the openapi fetch + 3 cleanup deletes (stream, 2 users)", res["requests"] - sum(res["cell_requests"].values()) == 4 and res["cell_requests"]["rate_limit_sanity"] == 30, res["cell_requests"])
ok("output carries ts, base, staging_commit (what /health serves), deploy_commit (latest SUCCESS deploy), cells[{cell,verdict,ms,detail}]",
   res["staging_commit"] == COMMIT and res["deploy_commit"] == COMMIT and all(set(c) == {"cell", "verdict", "ms", "detail"} for c in res["cells"]) and res["ts"].endswith("Z"))
ok("users the cells created are prefixed qa-e2e- and every one of them is gone afterwards", stub.created_users and all(e.startswith("qa-e2e-") for e in stub.created_users)
   and set(stub.accounts) == {PREMIUM[0], FREE[0]}, (stub.created_users, list(stub.accounts)))
ok("the stream the playback cell created is qa-e2e-* and deleted", stub.created_streams and all(n.startswith("qa-e2e-") for n in stub.created_streams) and not stub.streams, (stub.created_streams, stub.streams))
ok("only the two canonical accounts ever logged in with a password (logins == 2 + 2 fresh users)", sum(1 for r in stub.requests if r[1] == "/api/auth/login") == 4)
ok("SSRF probes sent LITERAL private targets only (no hostnames to resolve)", all(re.search(r"(127\.0\.0\.1|169\.254\.169\.254|\[::1\]|10\.0\.0\.1|file:)", urllib.parse.unquote(r[2])) for r in stub.requests if r[1] == "/api/streams/relay")
   and len([r for r in stub.requests if r[1] == "/api/streams/relay"]) == 5)
stub.stop()
ok("cleanup is reported: 3 deletes attempted (stream + 2 users), 0 failed; the openapi document (> 64 KiB here, ~240 KB on staging) is read in full", res["cleanup"] == {"attempted": 3, "failed": 0}
   and len(json.dumps(Stub().openapi())) > 150000, res.get("cleanup"))
ok("CELLS registry: 7 box cells + the Mac-only revenuecat_lifecycle; scorecard's E2E_CELLS equals ALL_CELLS", E.BOX_CELLS + E.MAC_CELLS == E.ALL_CELLS and len(E.ALL_CELLS) == 8)

# ==================================================================================================================== 2. negative controls: one FAIL each, everything else unchanged
print("# 2. negative controls: each mutation of the stub flips exactly its cell to FAIL (whole table asserted)")
CONTROLS = [
    ("stub accepts a private-IP import URL", {"import_accepts_private": True}, {"ssrf_refusal": "FAIL"}),
    ("stub relay accepts a private-IP URL", {"relay_accepts_private": True}, {"ssrf_refusal": "FAIL"}),
    ("stub 401s ?token= (7d87fbd1 behaviour, gold row G10)", {"token_query_playback_only": True}, {"playback_token": "FAIL"}),
    ("stub proxy is open without any token", {"open_proxy": True}, {"playback_token": "FAIL"}),
    ("stub returns 429 on hot-route request 20", {"rate_429_at": 20}, {"rate_limit_sanity": "FAIL"}),
    ("stub sends retry-after on a 200 (no 429)", {"retry_after": True}, {"rate_limit_sanity": "FAIL"}),
    ("stub /health reports a commit missing from the export (first seen an hour ago; the export was taken since)", {"commit": OTHER}, {"health_provenance": "FAIL"}, {"unlisted_since": 3600}),
    ("stub /health reports migrations=mismatch", {"migrations": "mismatch"}, {"health_provenance": "FAIL"}),
    ("stub /health reports status != healthy", {"status": "degraded"}, {"health_provenance": "FAIL"}),
    ("stub 500s on /api/vod", {"vod_500": True}, {"vod_catalog": "FAIL"}),
    ("stub /api/vod lacks the `items` catalog key", {"vod_missing_items": True}, {"vod_catalog": "FAIL"}),
    ("referral stub allows a second redeem of the same code", {"second_redeem_ok": True}, {"referral_flow": "FAIL"}),
    ("referral stub allows a self-redeem", {"self_redeem_ok": True}, {"referral_flow": "FAIL"}),
    ("referral stub 500s on a valid redeem (users still deleted)", {"redeem_500": True}, {"referral_flow": "FAIL"}),
    ("stub answers an anonymous /api/auth/me with 200", {"anon_me_ok": True}, {"auth_login": "FAIL"}),
    ("stub 500s the premium canonical login (a server error, not a credentials problem)", {"login_reject": ("premium",), "login_reject_status": 500}, {"auth_login": "FAIL", "ssrf_refusal": "UNVERIFIED", "playback_token": "UNVERIFIED"}),
    ("relay guard missing: the app tries the fetch and answers its OWN 502 (JSON detail)", {"relay_guard_missing_502": True}, {"ssrf_refusal": "FAIL"}),
]
for label, modes, exp, *skw in CONTROLS:
    stub, res = table("control FAIL: " + label, modes, state_kw=(skw[0] if skw else None), expect=exp)
    # a control must never leave users behind either
    ok("  ... no qa-e2e user / stream left behind after: " + label, set(stub.accounts) <= {PREMIUM[0], FREE[0]} and not stub.streams, (list(stub.accounts), stub.streams))

stub, res = table("deletes fail (500): verdicts unchanged but the leftover is VISIBLE in the result", {"delete_fails": True})
ok("  ... cleanup {attempted: 3, failed: 3} so a leftover qa-e2e-* user / stream can be seen and alerted", res["cleanup"] == {"attempted": 3, "failed": 3}, res["cleanup"])

# ==================================================================================================================== 3. infra controls: UNVERIFIED, never FAIL
print("# 3. infrastructure problems are UNVERIFIED (never FAIL)")
s0 = socket.socket()
s0.bind(("127.0.0.1", 0))
dead_port = s0.getsockname()[1]
s0.close()
class Dead:
    base = "http://127.0.0.1:%d" % dead_port
res = E.run(Dead.base, None, make_state("refused"), timeout=2.0)
ok("connection refused: every cell UNVERIFIED, none FAIL", set(verdicts(res).values()) == {"UNVERIFIED"}, verdicts(res))
stub = Stub(delay=2.0)
t0 = time.time()
res = E.run(stub.base, None, make_state("timeout"), timeout=0.3)
ok("timeout (server sleeps 2 s, client 0.3 s): every cell UNVERIFIED, none FAIL, run is quick", set(verdicts(res).values()) == {"UNVERIFIED"} and time.time() - t0 < 10, (verdicts(res), time.time() - t0))
stub.stop()
stub = Stub()
cl = E.Client(stub.base, interval=0)
def dns_fail(req, timeout=None):
    raise urllib.error.URLError(socket.gaierror(-2, "Name or service not known"))
cl._open = dns_fail
res = E.run(stub.base, None, make_state("dns"), client=cl)
ok("DNS failure: every cell UNVERIFIED, none FAIL", set(verdicts(res).values()) == {"UNVERIFIED"} and "no response (dns)" in json.dumps(res), verdicts(res))
r1 = cl.request("GET", "/health")
ok("transport error kinds are mapped (dns here; refused/timeout above)", r1.status == 0 and r1.err == "dns" and r1.infra)
stub.stop()
table("gateway 503 on /health: health UNVERIFIED, nothing else disturbed", {"health_503": True}, expect={"health_provenance": "UNVERIFIED"})
table("429 on login is rate limiting, not a defect: auth UNVERIFIED (+ every cell needing a login, incl. the fresh referral users), never FAIL", {"login_429": True},
      expect={"auth_login": "UNVERIFIED", "ssrf_refusal": "UNVERIFIED", "playback_token": "UNVERIFIED", "vod_catalog": "UNVERIFIED", "rate_limit_sanity": "UNVERIFIED", "referral_flow": "UNVERIFIED"})
table("deploy export missing: provenance cannot be compared -> health UNVERIFIED", {}, state_kw={"deploys": "missing"}, expect={"health_provenance": "UNVERIFIED"})
table("deploy export STALE (>30 min): health UNVERIFIED (never a FAIL on old evidence)", {}, state_kw={"deploys": "stale"}, expect={"health_provenance": "UNVERIFIED"})
table("a newer deploy is BUILDING: health UNVERIFIED (the served commit is legitimately the old one)", {}, state_kw={"deploys": "building"}, expect={"health_provenance": "UNVERIFIED"})
table("latest deploy FAILED but staging serves the latest SUCCESS commit: provenance PASS (a failed deploy is staging_check's business)", {}, state_kw={"deploys": "failed_latest"})
table("credentials absent: auth + the cells needing a login are UNVERIFIED; health and the fresh-user referral flow still PASS", {}, state_kw={"creds": "absent"},
      expect={"auth_login": "UNVERIFIED", "ssrf_refusal": "UNVERIFIED", "playback_token": "UNVERIFIED", "vod_catalog": "UNVERIFIED", "rate_limit_sanity": "UNVERIFIED"})
table("creds file readable by group/other (mode 644) is IGNORED like absent creds", {}, state_kw={"creds_mode": 0o644},
      expect={"auth_login": "UNVERIFIED", "ssrf_refusal": "UNVERIFIED", "playback_token": "UNVERIFIED", "vod_catalog": "UNVERIFIED", "rate_limit_sanity": "UNVERIFIED"})

# ==================================================================================================================== 4. NA: route absent from openapi / verification override missing
print("# 4. NA with a reason: never a fake PASS")
stub, res = table("route missing from openapi (/api/vod): vod_catalog NA", {"drop": (("get", "/api/vod"),)}, expect={"vod_catalog": "NA"})
ok("  ... the NA says which route is absent", "absent from openapi" in next(c for c in res["cells"] if c["cell"] == "vod_catalog")["detail"])
table("referral routes missing from openapi: referral_flow NA", {"drop": (("post", "/api/referrals"),)}, expect={"referral_flow": "NA"})
table("stream proxy route missing from openapi: playback_token NA", {"drop": (("get", "/api/streams/{stream_id}/proxy"),)}, expect={"playback_token": "NA"})
table("ALL ssrf routes missing from openapi: ssrf_refusal NA", {"drop": (("post", "/api/streams/import"), ("get", "/api/streams/relay"), ("post", "/api/streams/import/xtream"))}, expect={"ssrf_refusal": "NA"})
stub, res = table("fresh users are not email-verified and REFERRAL override not set: the valid redeem is rejected -> referral_flow NA (not PASS, not FAIL)", {"auto_verify": False},
                  expect={"referral_flow": "NA"})
ok("  ... the NA names the staging override", "REFERRAL_REQUIRE_VERIFIED_EMAIL=false" in next(c for c in res["cells"] if c["cell"] == "referral_flow")["detail"])
table("unverified users but the staging override IS set: the flow runs and PASSes", {"auto_verify": False, "referral_override": True})
stub, res = table("verified users and the valid redeem is rejected (HTTP 400): that is a FAIL, not an NA", {"redeem_reject_all": True}, expect={"referral_flow": "FAIL"})
ok("  ... the FAIL says both users are verified", "both users are verified" in next(c for c in res["cells"] if c["cell"] == "referral_flow")["detail"])

# ==================================================================================================================== 5. budget, throttle, host guard
print("# 5. request budget, 1 req/s per host, host guard")
stub = Stub()
res = E.run(stub.base, None, make_state("budget"), budget=40)
ok("budget 40: the run stops using requests for cells at 32 (8 reserved for cleanup), total <= 40, remaining cells UNVERIFIED (not FAIL)",
   len(stub.requests) <= 40 and verdicts(res)["rate_limit_sanity"] == "UNVERIFIED" and "FAIL" not in verdicts(res).values(), (len(stub.requests), verdicts(res)))
ok("  ... the cleanup reserve was used: users and stream created before the budget ran out are gone", set(stub.accounts) == {PREMIUM[0], FREE[0]} and not stub.streams, (list(stub.accounts), stub.streams))
stub.stop()
stub = Stub()
res = E.run(stub.base, None, make_state("budget2"), budget=10)
ok("budget 10: <= 10 requests in total, everything beyond the openapi + health probes is UNVERIFIED", len(stub.requests) <= 10 and "FAIL" not in verdicts(res).values(), (len(stub.requests), verdicts(res)))
stub.stop()
stub = Stub()
clock = [0.0]
sleeps = []
def fsleep(s):
    sleeps.append(s)
    clock[0] += s
cl = E.Client(stub.base, interval=1.0, sleep=fsleep, clock=lambda: clock[0])
for _ in range(6):
    cl.request("GET", "/health")
ok("throttle: 6 back-to-back requests to one host wait 1.0 s between each (5 sleeps of >= 1 s)", len(sleeps) == 5 and all(s >= 1.0 - 1e-9 for s in sleeps), sleeps)
cl2 = E.Client(stub.base, interval=1.0, sleep=fsleep, clock=lambda: clock[0])
before = len(sleeps)
cl2.request("GET", "/health")
clock[0] += 0.4
cl2.request("GET", "/health")
ok("throttle: only the REMAINING part of the second is slept (0.6 s after 0.4 s elapsed)", len(sleeps) == before + 1 and abs(sleeps[-1] - 0.6) < 1e-6, sleeps[before:])
stub.stop()
ok("the 1 req/s floor cannot be lowered for a real host (env 0 ignored), only for loopback", E.effective_interval("x-staging.up.railway.app", {"QA_E2E_MIN_INTERVAL_S": "0"}) == 1.0
   and E.effective_interval("127.0.0.1", {"QA_E2E_MIN_INTERVAL_S": "0"}) == 0.0 and E.effective_interval("127.0.0.1", {}) == 1.0)
os.environ.pop("QA_E2E_ALLOW_LOCAL")
bad = ["https://chickadeestream-production.up.railway.app", "https://api.example.com/staging", "https://chickadee-staging.example.com", "http://chickadee-staging.up.railway.app",
       "https://evil.com/?h=chickadee-staging.up.railway.app", "http://127.0.0.1:8000", "https://chickadeestream-staging-production.up.railway.app"]
refused = []
for b in bad:
    try:
        E.check_base(b)
    except ValueError:
        refused.append(b)
ok("host guard refuses production, non-railway, http, look-alike and (without QA_E2E_ALLOW_LOCAL) loopback hosts", refused == bad, set(bad) - set(refused))
ok("host guard accepts the real staging host", E.check_base("https://chickadeestream-backend-staging.up.railway.app") == "chickadeestream-backend-staging.up.railway.app")
class Boom(E.Client):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.touched = 0
        self._open = self._boom

    def _boom(self, *a, **k):
        self.touched += 1
        raise AssertionError("network used")
boom = Boom("https://chickadeestream-production.up.railway.app")
try:
    E.run("https://chickadeestream-production.up.railway.app", None, make_state("guard"), client=boom)
    guard_ok = False
except ValueError:
    guard_ok = boom.touched == 0 and boom.count == 0
ok("a refused base raises BEFORE any request is made (0 requests)", guard_ok)
p = subprocess.run([PY, RUNNER, "--base", "https://chickadeestream-production.up.railway.app", "--state-dir", make_state("guardcli"), "--out", os.path.join(T, "should-not-exist.json")],
                   capture_output=True, text=True, env={k: v for k, v in os.environ.items() if k != "QA_E2E_ALLOW_LOCAL"}, timeout=60)
ok("CLI: production base => exit 2, REFUSING on stderr, no output file", p.returncode == 2 and "REFUSING" in p.stderr and not os.path.exists(os.path.join(T, "should-not-exist.json")), (p.returncode, p.stderr[:200]))
os.environ["QA_E2E_ALLOW_LOCAL"] = "1"

# ==================================================================================================================== 6. redaction (seeded secrets)
print("# 6. a seeded secret never appears in verdict output, stdout, stderr or the output file")
stub = Stub(vod_500=True)   # the 500 body echoes the Authorization header (a leaky server) and the cell prints a body snippet
st = make_state("redact")
outf = os.path.join(T, "redact-out.json")
p = subprocess.run([PY, RUNNER, "--base", stub.base, "--state-dir", st, "--out", outf], capture_output=True, text=True, timeout=120)
blob = p.stdout + p.stderr + open(outf).read()
secrets = [PREMIUM[0], PREMIUM[1], FREE[0], FREE[1]] + list(stub.issued) + ["ref-" + t for t in stub.issued] + [p_ for p_ in stub.pw_log if p_] + list(stub.created_users)
leaked = [s[:8] + "..." for s in secrets if s and s in blob]
ok("seeded passwords, canonical emails and EVERY issued token are absent from stdout + stderr + the JSON file", not leaked and len(stub.issued) >= 4, leaked)
vod_detail = next(c["detail"] for c in json.loads(open(outf).read())["cells"] if c["cell"] == "vod_catalog")
ok("the body echo reached the detail and was masked (the test is not vacuous)", "HTTP 500" in vod_detail and ("***" in vod_detail or "[redacted]" in vod_detail) and "acc-" not in vod_detail, vod_detail)
ok("fresh-user passwords and emails (qa-e2e-*) were seen by the stub (%d) and none leaked" % len(stub.pw_log), len(stub.pw_log) == 2 and not [x for x in stub.pw_log + stub.created_users if x in blob])
stub.stop()
R = E.Redactor()
R.add("S3cr3t-Pw-Value")
jwt = SEED_JWT
txt = R.scrub("login S3cr3t-Pw-Value url-quoted S3cr3t-Pw-Value json \"S3cr3t-Pw-Value\" %s Bearer %s %s %s %s" % (jwt, "abcdefghijklmnop", "pass" + "word=hunter22", SEED_TOKKV, "{\"access_" + "token\": \"zzzz9999\"}"))
ok("Redactor: registered secret, JWT, bearer, password=, ?token= and access_token shapes are all masked", not any(s in txt for s in ("S3cr3t-Pw-Value", jwt, "abcdefghijklmnop", "hunter22", "abc123def456", "zzzz9999")), txt)
ok("Redactor negative control: ordinary diagnostics survive", R.scrub("login HTTP 401 for 4 probes: 3 refused") == "login HTTP 401 for 4 probes: 3 refused")

# ==================================================================================================================== 7. pure helpers
print("# 7. pure helpers: refusal classifier, deploy state, credentials, openapi, CLI")
class RR:
    def __init__(self, status, text="", err=""):
        self.status, self.text, self.err = status, text, err
        self.infra = status == 0 or status in (502, 503, 504)
ok("classify_refusal: 400/422/403 refuse; 200 or a job id accept; 500 error; 401/429/premium-403/gateway/no-response unverified",
   [E.classify_refusal(RR(s, t)) for s, t in ((400, ""), (422, ""), (403, "no"), (200, ""), (200, '{"job_id":"x"}'), (500, ""), (404, ""), (401, ""), (429, ""), (403, "requires Premium"), (503, ""), (0, ""))]
   == ["refused", "refused", "refused", "accepted", "accepted", "error", "error", "unverified", "unverified", "unverified", "unverified", "unverified"])
st = make_state("deploy_unit")
ok("load_deploy: fresh export -> ok + latest SUCCESS commit", E.load_deploy(st)["state"] == "ok" and E.load_deploy(st)["commit"] == COMMIT)
ok("load_deploy: age beyond the limit -> stale; corrupt file -> missing (never raises)", E.load_deploy(st, now=time.time() + 5000)["state"] == "stale")
open(os.path.join(st, "staging_deploys", "iptv_apps.json"), "w").write("{not json")
ok("load_deploy: corrupt export -> missing", E.load_deploy(st)["state"] == "missing")
ok("aggregate over cells: FAIL > UNVERIFIED > FLAG(partial) > PASS > NA", [PGM.aggregate_cells([{"verdict": v} for v in vs]) for vs in (("PASS", "FAIL", "NA"), ("PASS", "UNVERIFIED"), ("PASS", "NA"), ("PASS", "PASS"), ("NA", "NA"), ())]
   == ["FAIL", "UNVERIFIED", "FLAG", "PASS", "NA", "UNVERIFIED"])
env_creds, note = E.load_creds(make_state("creds_unit"), {"QA_E2E_PREMIUM_EMAIL": "e@x.y", "QA_E2E_PREMIUM_PASSWORD": "pwpw1234"})
ok("load_creds: env wins for the account it covers, the 600 file fills the other", env_creds["premium"] == ("e@x.y", "pwpw1234") and env_creds["free"] == FREE)
d = make_state("creds_flat")
json.dump({"email": "flat@x.y", "password": "flatpw99"}, open(os.path.join(d, "qa_creds", "iptv_apps.json"), "w"))
os.chmod(os.path.join(d, "qa_creds", "iptv_apps.json"), 0o600)
ok("load_creds: a flat {email,password} file (what qa/staging_smoke.py stores) is the premium account", E.load_creds(d)[0]["premium"] == ("flat@x.y", "flatpw99") and E.load_creds(d)[0]["free"] is None)
oa = E.OpenAPI(Stub().openapi())
ok("openapi: routes, body fields, query params and response keys are derived through $ref", oa.find("get", "/vod") == "/api/vod" and oa.body_props("post", "/api/referrals/redeem") == {"code"}
   and oa.query_params("get", "/api/streams/relay") == {"url": True, "token": False} and oa.response("get", "/api/vod") == ("object", {"items", "total"}) and oa.find_re("get", r"/streams/\{[^}]+\}/proxy$"))
p = subprocess.run([PY, RUNNER, "--list-cells"], capture_output=True, text=True, timeout=30)
ok("CLI --list-cells prints the 8 cells; an unknown cell exits 2", p.stdout.split() == list(E.ALL_CELLS) and subprocess.run([PY, RUNNER, "--cells", "nope"], capture_output=True, text=True, timeout=30).returncode == 2)
stub = Stub()
p = subprocess.run([PY, RUNNER, "--base", stub.base, "--state-dir", make_state("cli"), "--cells", "health_provenance,vod_catalog"], capture_output=True, text=True, timeout=60)
j = json.loads(p.stdout)
ok("CLI --cells subset without --out prints the JSON result on stdout (health PASS; vod UNVERIFIED because auth_login was not selected so no token exists)",
   p.returncode == 0 and verdicts(j) == {"health_provenance": "PASS", "vod_catalog": "UNVERIFIED"}, (p.stdout[:300], p.stderr[:200]))
stub.stop()

# ==================================================================================================================== 8. rc_lifecycle_e2e: importable cell, CLI unchanged
print("# 8. rc_lifecycle_e2e.py: importable cell revenuecat_lifecycle + unchanged CLI (stub subscription model)")
real_guard = RCM.guard
RCM.guard = lambda base: None   # the cell's own guard demands the word 'staging' in the URL; the stub is loopback (the real guard is tested below)
stub = Stub()
cell = RCM.revenuecat_lifecycle(stub.base, secret_fn=lambda: stub.webhook_secret)
ok("cell revenuecat_lifecycle against the stub: PASS, shape {cell, verdict, ms, detail}", cell["verdict"] == "PASS" and set(cell) == {"cell", "verdict", "ms", "detail"} and cell["cell"] == "revenuecat_lifecycle" and "17" in cell["detail"], cell)
ok("  ... the throwaway account was deleted", not [e for e in stub.accounts if e.startswith("claude-rc-e2e")])
stub.stop()
stub = Stub(expiration_never_revokes=True)
cell = RCM.revenuecat_lifecycle(stub.base, secret_fn=lambda: stub.webhook_secret)
ok("negative control: the server never revokes on EXPIRATION => the cell is FAIL naming the check", cell["verdict"] == "FAIL" and "EXPIRATION of the current period revokes premium" in cell["detail"], cell)
ok("  ... and the account is still deleted", not [e for e in stub.accounts if e.startswith("claude-rc-e2e")])
stub.stop()
def no_secret():
    raise RCM.SecretUnavailable("REVENUECAT_WEBHOOK_SECRET is not set on staging - cannot drive the webhook")
stub = Stub()
cell = RCM.revenuecat_lifecycle(stub.base, secret_fn=no_secret)
ok("no webhook secret (Railway CLI missing) => UNVERIFIED, never FAIL, and the temp account is still deleted", cell["verdict"] == "UNVERIFIED" and not [e for e in stub.accounts if e.startswith("claude-rc-e2e")], cell)
cell = RCM.revenuecat_lifecycle("http://127.0.0.1:%d" % dead_port, secret_fn=lambda: "x")
ok("host not reachable => UNVERIFIED", cell["verdict"] == "UNVERIFIED")
RCM.guard = real_guard
cell = RCM.revenuecat_lifecycle("https://chickadeestream-production.up.railway.app", secret_fn=lambda: "x")
ok("non-staging base => UNVERIFIED (the real guard fires before any request)", cell["verdict"] == "UNVERIFIED" and "non-staging" in cell["detail"], cell)
leaky = RCM.cell_from_results([("check one", False, "tok" + "en=SuperSecretTokenValue and Bearer " + SEED_BEARER)], 5)
ok("cell detail is scrubbed of token/bearer shapes", "SuperSecretTokenValue" not in leaky["detail"] and SEED_BEARER not in leaky["detail"], leaky)
RCM.guard = lambda base: None   # the CLI's own guard demands the word 'staging' in the URL; the stub is loopback
RCM.secret = lambda: stub.webhook_secret
stub.stop()
stub = Stub()
outj = os.path.join(T, "rc-out.json")
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        RCM.main(["--base", stub.base, "--json-out", outj])
    rc_exit = 0
except SystemExit as ex:
    rc_exit = ex.code
lines = buf.getvalue().splitlines()
jj = json.load(open(outj))
ok("CLI unchanged: 17 PASS lines, '17/17 passed', exit 0, old --json-out keys present plus cells",
   rc_exit == 0 and sum(1 for l in lines if l.startswith("PASS ")) == 17 and "17/17 passed" in buf.getvalue() and {"ts", "base", "staging_commit", "passed", "total", "failed"} <= set(jj)
   and jj["passed"] == 17 and jj["failed"] == [] and jj["cells"][0]["verdict"] == "PASS", (rc_exit, lines[-3:], jj))
stub.stop()
stub = Stub(expiration_never_revokes=True)
RCM.secret = lambda: stub.webhook_secret
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        RCM.main(["--base", stub.base, "--json-out", outj])
    rc_exit = 0
except SystemExit as ex:
    rc_exit = ex.code
jj = json.load(open(outj))
ok("CLI negative control: a failing check => exit 1, a FAIL line, failed[] lists it, cell verdict FAIL", rc_exit == 1 and any(l.startswith("FAIL EXPIRATION of the current period") for l in buf.getvalue().splitlines())
   and "EXPIRATION of the current period revokes premium" in jj["failed"] and jj["cells"][0]["verdict"] == "FAIL", (rc_exit, jj))
stub.stop()

# ==================================================================================================================== 9. qa/promote_gate.py pure logic
print("# 9. promote_gate: e2e normalisation, evaluation, decide_e2e_block")
PG = load(os.path.join(QA, "promote_gate.py"), "pg_under_test")
NOW = 1_800_000_000.0
def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
def src(name, verdict_cells, age_s, commit=COMMIT):
    return PG.normalize_e2e({"ts": iso(NOW - age_s), "staging_commit": commit, "cells": [{"cell": "c%d" % i, "verdict": v, "ms": 1, "detail": "d"} for i, v in enumerate(verdict_cells)]}) | {"source": name}
def ev(sources, cand=COMMIT, mode="enforce", anc=lambda a, b: None, bad=()):
    return PG.e2e_evaluate(sources, list(bad), cand, anc, NOW, mode)
D = PG.decide_e2e_block
ok("decide_e2e_block: enforce + FAIL + match + fresh BLOCKS", D("enforce", "FAIL", True, 600))
ok("decide_e2e_block: SHADOW never blocks", not D("shadow", "FAIL", True, 600) and not D("off", "FAIL", True, 600))
ok("decide_e2e_block: no match (None/False) never blocks", not D("enforce", "FAIL", False, 600) and not D("enforce", "FAIL", None, 600))
ok("decide_e2e_block: stale (>= 12 h) or unknown age never blocks", not D("enforce", "FAIL", True, 12 * 3600) and not D("enforce", "FAIL", True, 50 * 3600) and not D("enforce", "FAIL", True, None) and D("enforce", "FAIL", True, 12 * 3600 - 1))
ok("decide_e2e_block: UNVERIFIED / FLAG / PASS / NA never block", not any(D("enforce", v, True, 60) for v in ("UNVERIFIED", "FLAG", "PASS", "NA", "")))
o = ev([src("box", ["PASS", "FAIL"], 600)])
ok("evaluate: FAIL at the candidate, fresh, enforce => block with the failing cell named", o["e2e_block"] and o["e2e_fail_cells"] == ["c1"] and o["e2e_match"] is True and o["e2e_verdict"] == "FAIL", o)
ok("evaluate: same FAIL in shadow does not block but is reported", not ev([src("box", ["FAIL"], 600)], mode="shadow")["e2e_block"] and ev([src("box", ["FAIL"], 600)], mode="shadow")["e2e_verdict"] == "FAIL")
ok("evaluate: FAIL for ANOTHER commit (not equal / not ancestor) never blocks (match false)", not ev([src("box", ["FAIL"], 600, OTHER)])["e2e_block"] and ev([src("box", ["FAIL"], 600, OTHER)])["e2e_match"] is False)
ok("evaluate: candidate is an ANCESTOR of the e2e commit => match true and a FAIL blocks (the e2e ran on a superset)", ev([src("box", ["FAIL"], 600, OTHER)], anc=lambda a, b: a == COMMIT and b == OTHER)["e2e_block"])
ok("evaluate: candidate NEWER than the e2e commit (e2e is an ancestor of it) is no match", not ev([src("box", ["FAIL"], 600, OTHER)], anc=lambda a, b: a == OTHER and b == COMMIT)["e2e_block"])
ok("evaluate: unknown to the clone (is_ancestor None) => no match, never blocks", not ev([src("box", ["FAIL"], 600, OTHER)], anc=lambda a, b: None)["e2e_block"])
ok("evaluate: stale FAIL (13 h) never blocks", not ev([src("box", ["FAIL"], 13 * 3600)])["e2e_block"])
ok("evaluate: an older FAIL source does not beat a newer matching PASS only when the FAIL is stale; a fresh matching FAIL wins over a newer PASS",
   not ev([src("box", ["FAIL"], 13 * 3600), src("mac", ["PASS"], 60)])["e2e_block"] and ev([src("box", ["FAIL"], 3600), src("mac", ["PASS"], 60)])["e2e_block"])
ok("evaluate: UNVERIFIED-only evidence never blocks", not ev([src("box", ["UNVERIFIED", "UNVERIFIED"], 60)])["e2e_block"])
ok("evaluate: no sources + unreadable file => present, UNVERIFIED, never blocks; nothing at all => not present", ev([], bad=("box",))["e2e_present"] and not ev([], bad=("box",))["e2e_block"] and not ev([])["e2e_present"])
leg = PG.normalize_e2e({"ts": iso(NOW - 60), "staging_commit": COMMIT, "passed": 15, "total": 17, "failed": ["a", "b"]})
ok("legacy Mac file {passed,total,failed}: failed => FAIL cell revenuecat_lifecycle; harness-error / total 0 => UNVERIFIED; clean => PASS",
   leg["verdict"] == "FAIL" and leg["cells"][0]["cell"] == "revenuecat_lifecycle" and PG.normalize_e2e({"ts": iso(NOW), "passed": 0, "total": 0, "failed": ["harness-error"]})["verdict"] == "UNVERIFIED"
   and PG.normalize_e2e({"ts": iso(NOW), "passed": 17, "total": 17, "failed": []})["verdict"] == "PASS")
ok("normalize: not an object / no usable ts => None (unreadable)", PG.normalize_e2e([]) is None and PG.normalize_e2e({"cells": []}) is None and PG.normalize_e2e({"ts": "yesterday"}) is None)
sd = os.path.join(T, "pgstate")
os.makedirs(sd, exist_ok=True)
open(os.path.join(sd, "qa_staging_e2e.json"), "w").write("{corrupt")
open(os.path.join(sd, "staging_e2e_box.json"), "w").write(json.dumps({"ts": iso(NOW), "staging_commit": COMMIT, "cells": []}))
srcs, bad_ = PG.read_e2e_sources(sd)
ok("read_e2e_sources: a corrupt file is counted unreadable, the good one is read, nothing raises", [s["source"] for s in srcs] == ["box"] and bad_ == ["mac"])
ok("the scorecard's cell list equals the runner's", load(os.path.join(QA, "qa_scorecard.py"), "sc_unit").E2E_CELLS == E.ALL_CELLS)

# ==================================================================================================================== 10. staging_e2e_ingest.py
print("# 10. ingest: shadow rows, one alert per (cell, commit), idempotent, leak-proof")
QSD = os.path.join(T, "ingest_state")
shutil.rmtree(QSD, ignore_errors=True)
os.makedirs(QSD)
env_ing = dict(os.environ, QA_STATE_DIR=QSD, OVN_DIR=T)
for k in ("OVN_QA_STAGING_E2E",):
    env_ing.pop(k, None)
box = {"ts": iso(time.time() - 120), "base": "x", "staging_commit": COMMIT, "deploy_commit": COMMIT, "requests": 60,
       "cells": [{"cell": "health_provenance", "verdict": "PASS", "ms": 5, "detail": "healthy"}, {"cell": "ssrf_refusal", "verdict": "FAIL", "ms": 9, "detail": "accepted http://127.0.0.1 Bearer " + SEED_BEARER + " " + SEED_PWKV},
                 {"cell": "referral_flow", "verdict": "NA", "ms": 1, "detail": "override not set"}, {"cell": "rate_limit_sanity", "verdict": "UNVERIFIED", "ms": 1, "detail": "x"}]}
json.dump(box, open(os.path.join(QSD, "staging_e2e_box.json"), "w"))
json.dump({"ts": iso(time.time() - 3600), "base": "x", "staging_commit": OTHER, "passed": 17, "total": 17, "failed": []}, open(os.path.join(QSD, "qa_staging_e2e.json"), "w"))
def ingest_cli(env=None):
    p_ = subprocess.run([PY, os.path.join(QA, "staging_e2e_ingest.py")], capture_output=True, text=True, env=env or env_ing, timeout=60)
    return p_, (json.loads(p_.stdout.strip().splitlines()[-1]) if p_.stdout.strip() else {})
p, summ = ingest_cli()
rows = [json.loads(l) for l in open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl"))]
ok("first ingest: exit 0, one summary line, TWO shadow rows (box + mac), gate staging_e2e, repo iptv_apps, ref = the commit the cells ran against",
   p.returncode == 0 and summ.get("verdict") == "NA" and len(rows) == 2 and {r["gate"] for r in rows} == {"staging_e2e"} and {r["repo"] for r in rows} == {"iptv_apps"}
   and {r["ref"] for r in rows} == {COMMIT[:10], OTHER[:10]} and all(r["verdict"] in ("PASS", "FAIL", "FLAG", "NA", "UNVERIFIED") for r in rows), (p.stdout, p.stderr, rows))
byref = {r["ref"]: r for r in rows}
ok("row verdicts: the box result is FAIL (a cell failed), the Mac result PASS; details carry the per-cell table and the source",
   byref[COMMIT[:10]]["verdict"] == "FAIL" and byref[OTHER[:10]]["verdict"] == "PASS" and byref[COMMIT[:10]]["details"]["source"] == "box" and len(byref[COMMIT[:10]]["details"]["cells"]) == 4)
al = open(os.path.join(QSD, "alerts.log")).read().splitlines()
ok("exactly ONE alerts.log WARN, for the FAILed (cell, commit), naming cell and commit", len(al) == 1 and "WARN | qa-staging-e2e | iptv_apps cell ssrf_refusal FAIL at staging %s" % COMMIT[:10] in al[0], al)
blob = open(os.path.join(QSD, "alerts.log")).read() + open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl")).read()
ok("a leaky result file (bearer + password= in a detail) cannot reach alerts.log or the shadow rows", SEED_BEARER not in blob and "Hunter2Hunter2" not in blob and "[redacted]" in blob, blob[-300:])
ingest_cli()
ok("second ingest of the same results: no new rows, no new alert (idempotent)", len(open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl")).read().splitlines()) == 2 and len(open(os.path.join(QSD, "alerts.log")).read().splitlines()) == 1)
box2 = dict(box, ts=iso(time.time() - 60))
json.dump(box2, open(os.path.join(QSD, "staging_e2e_box.json"), "w"))
ingest_cli()
ok("a NEW result for the SAME commit still failing: a third row, but NO second alert (one per cell+commit)", len(open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl")).read().splitlines()) == 3 and len(open(os.path.join(QSD, "alerts.log")).read().splitlines()) == 1)
box3 = dict(box, ts=iso(time.time() - 30), staging_commit=OTHER)
json.dump(box3, open(os.path.join(QSD, "staging_e2e_box.json"), "w"))
ingest_cli()
ok("the same cell FAILing at a NEW commit alerts again (key = cell + commit)", len(open(os.path.join(QSD, "alerts.log")).read().splitlines()) == 2)
open(os.path.join(QSD, "staging_e2e_box.json"), "w").write("{corrupt json")
p, summ = ingest_cli()
ok("a corrupt result file never crashes the ingest (exit 0, reported as unreadable)", p.returncode == 0 and "unreadable" in summ.get("summary", ""), (p.stdout, p.stderr))
box_ok = dict(box, ts=iso(time.time() - 5), staging_commit="1234567abcdef", cells=[{"cell": "health_provenance", "verdict": "PASS", "ms": 1, "detail": "ok"}])
json.dump(box_ok, open(os.path.join(QSD, "staging_e2e_box.json"), "w"))
n_alerts = len(open(os.path.join(QSD, "alerts.log")).read().splitlines())
ingest_cli()
ok("a benign (all PASS) result writes a row and NO alert", len(open(os.path.join(QSD, "alerts.log")).read().splitlines()) == n_alerts)
n_rows = len(open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl")).read().splitlines())
json.dump(dict(box_ok, ts=iso(time.time())), open(os.path.join(QSD, "staging_e2e_box.json"), "w"))
p, summ = ingest_cli(dict(env_ing, OVN_QA_STAGING_E2E="off"))
ok("kill switch OVN_QA_STAGING_E2E=off: nothing ingested", len(open(os.path.join(QSD, "qa_shadow", "staging_e2e.jsonl")).read().splitlines()) == n_rows and "off" in summ.get("summary", ""))

# ==================================================================================================================== 11. scorecard
print("# 11. scorecard: staging_e2e cell says 'evidence found for N cells', never 'verified'")
SC = os.path.join(QA, "qa_scorecard.py")
sc_state = os.path.join(T, "sc_state")
shutil.rmtree(sc_state, ignore_errors=True)
os.makedirs(sc_state)
env_sc = dict(os.environ, QA_STATE_DIR=sc_state, OVN_DIR=T)
p = subprocess.run([PY, SC, "report", "--days", "30"], capture_output=True, text=True, env=env_sc, timeout=60)
ok("no rows yet: the cell is NA and says so", p.returncode == 0 and "no result rows yet" in p.stdout, p.stdout[-300:] + p.stderr[-200:])
box_sc = {"ts": iso(time.time() - 600), "staging_commit": COMMIT, "cells": [{"cell": c, "verdict": v, "ms": 1, "detail": "d"} for c, v in
          (("health_provenance", "PASS"), ("auth_login", "PASS"), ("ssrf_refusal", "FAIL"), ("playback_token", "PASS"), ("referral_flow", "NA"), ("vod_catalog", "PASS"), ("rate_limit_sanity", "UNVERIFIED"))]}
json.dump(box_sc, open(os.path.join(sc_state, "staging_e2e_box.json"), "w"))
json.dump({"ts": iso(time.time() - 3000), "staging_commit": COMMIT, "passed": 17, "total": 17, "failed": []}, open(os.path.join(sc_state, "qa_staging_e2e.json"), "w"))
subprocess.run([PY, os.path.join(QA, "staging_e2e_ingest.py")], capture_output=True, text=True, env=env_sc, timeout=60)
p = subprocess.run([PY, SC, "report", "--days", "30"], capture_output=True, text=True, env=env_sc, timeout=60)
line = next((l for l in p.stdout.splitlines() if l.startswith("staging e2e (shadow)")), "")
ok("report line: last verdict FAIL, evidence found for 6 of 8 cells (PASS/FAIL cells only; NA and UNVERIFIED are not evidence)", "last verdict FAIL" in line and "evidence found for 6 of 8 cells" in line, line)
ok("the summary never claims 'verified'", not re.search(r"\bverified\b", line, re.I) and "referral_flow=NA" in line and "rate_limit_sanity=UNVERIFIED" in line, line)
pj = subprocess.run([PY, SC, "report", "--days", "30", "--json"], capture_output=True, text=True, env=env_sc, timeout=60)
jo = json.loads(pj.stdout)["staging_e2e"]
ok("--json carries {verdict, age_s, found, of}", jo["found"] == 6 and jo["of"] == 8 and jo["verdict"] == "FAIL" and 0 <= jo["age_s"] < 4000, jo)
ok("feature/promote scorecards get a staging_e2e gate column", "staging_e2e" in load(SC, "sc_cols").KNOWN_GATES)

# ==================================================================================================================== 12. staging_e2e_run.sh
print("# 12. staging_e2e_run.sh: trigger on a new deploy commit / 6 h, serial lock, kill switch, honest failure")
def make_box(name, commit=COMMIT, stub_url=None, runner_in_box=True):
    box_dir = os.path.join(T, name)
    shutil.rmtree(box_dir, ignore_errors=True)
    os.makedirs(os.path.join(box_dir, "qa"))
    for f in ("qa_common.py", "qa_timeout.py", "staging_e2e_run.sh"):
        shutil.copy(os.path.join(QA, f), os.path.join(box_dir, "qa", f))
    if runner_in_box:
        os.makedirs(os.path.join(box_dir, "scripts", "qa", "e2e"))
        shutil.copy(RUNNER, os.path.join(box_dir, "scripts", "qa", "e2e", "chickadee_staging_e2e.py"))
    stt = make_state(name + "_s", commit=commit)
    shutil.rmtree(os.path.join(box_dir, "state"), ignore_errors=True)
    shutil.copytree(stt, os.path.join(box_dir, "state"))
    if stub_url:
        open(os.path.join(box_dir, "state", "staging_url_iptv_apps"), "w").write(stub_url + "\n")
    return box_dir
def run_sh(box_dir, extra=None, script=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("OVN_") and not k.startswith("QA_STATE")}
    e.update({"OVN_DIR": box_dir, "QA_E2E_ALLOW_LOCAL": "1", "QA_E2E_MIN_INTERVAL_S": "0"})
    e.update(extra or {})
    p_ = subprocess.run(["bash", script or os.path.join(box_dir, "qa", "staging_e2e_run.sh")], capture_output=True, text=True, env=e, timeout=300)
    return p_
stub = Stub()
bx = make_box("box1", stub_url=stub.base)
p = run_sh(bx)
res_file = os.path.join(bx, "state", "staging_e2e_box.json")
r1 = json.load(open(res_file))
n1 = len(stub.requests)
ok("first run (no previous result): runs, exit 0, writes state/staging_e2e_box.json with 7 PASS cells + deploy_commit", p.returncode == 0 and "run: no previous result" in p.stdout and len(r1["cells"]) == 7
   and all(c["verdict"] == "PASS" for c in r1["cells"]) and r1["deploy_commit"] == COMMIT and n1 > 0, (p.stdout, p.stderr[-300:]))
ok("  ... the lock is released and no temp file is left", not os.path.exists(os.path.join(bx, "state", "staging_e2e.lock")) and not [f for f in os.listdir(os.path.join(bx, "state")) if f.startswith(".staging_e2e_box")])
p = run_sh(bx)
ok("second run, same deploy commit, result fresh: SKIPS ('nothing new'), zero requests to staging", "skip: nothing new" in p.stdout and len(stub.requests) == n1, (p.stdout, len(stub.requests), n1))
json.dump({"repo": "iptv_apps", "fetched_at": time.time(), "deployments": [{"id": "dep00009", "status": "SUCCESS", "createdAt": iso(time.time()), "meta": {"commitHash": OTHER}},
                                                                            {"id": "dep00001", "status": "SUCCESS", "createdAt": iso(time.time() - 3600), "meta": {"commitHash": COMMIT}}]}, open(os.path.join(bx, "state", "staging_deploys", "iptv_apps.json"), "w"))
p = run_sh(bx)
ok("a NEW latest SUCCESS deploy commit => runs again (and records the new deploy_commit)", "run: new staging deploy %s" % OTHER[:10] in p.stdout and len(stub.requests) > n1 and json.load(open(res_file))["deploy_commit"] == OTHER, p.stdout)
n2 = len(stub.requests)
json.dump({"repo": "iptv_apps", "fetched_at": time.time(), "deployments": [{"id": "dep00010", "status": "BUILDING", "createdAt": iso(time.time()), "meta": {"commitHash": COMMIT}},
                                                                            {"id": "dep00009", "status": "SUCCESS", "createdAt": iso(time.time() - 60), "meta": {"commitHash": OTHER}}]}, open(os.path.join(bx, "state", "staging_deploys", "iptv_apps.json"), "w"))
p = run_sh(bx)
ok("latest deploy still BUILDING => skips (waits), zero requests", "skip: latest staging deploy is BUILDING" in p.stdout and len(stub.requests) == n2, p.stdout)
old = json.load(open(res_file))
old["ts"] = iso(time.time() - 7 * 3600)
json.dump(old, open(res_file, "w"))
p = run_sh(bx)
ok("result >= 6 h old => runs again even while a deploy is BUILDING/unchanged", "run: last result is" in p.stdout and len(stub.requests) > n2, p.stdout)
n3 = len(stub.requests)
lock = os.path.join(bx, "state", "staging_e2e.lock")
os.makedirs(lock)
old = json.load(open(res_file))
old["ts"] = iso(time.time() - 7 * 3600)
json.dump(old, open(res_file, "w"))
p = run_sh(bx)
ok("serial lock held (fresh): skips 'busy', zero requests, the foreign lock is NOT removed", "skip: busy" in p.stdout and len(stub.requests) == n3 and os.path.isdir(lock), p.stdout)
os.utime(lock, (946684800, 946684800))
p = run_sh(bx)
ok("a STALE lock (year 2000) is taken over: the run happens and the lock is released", "taking over a stale lock" in p.stdout and len(stub.requests) > n3 and not os.path.exists(lock), p.stdout)
n4 = len(stub.requests)
p = run_sh(bx, {"OVN_QA_STAGING_E2E": "off", "QA_E2E_FORCE": "1"})
ok("kill switch OVN_QA_STAGING_E2E=off wins even over QA_E2E_FORCE=1: no run, zero requests", "disabled" in p.stdout and len(stub.requests) == n4, p.stdout)
p = run_sh(bx, {"QA_E2E_FORCE": "1"})
ok("QA_E2E_FORCE=1 runs regardless of the decision", "run: forced" in p.stdout and len(stub.requests) > n4)
stub.stop()
bx2 = make_box("box2", runner_in_box=False)
p = run_sh(bx2, {"QA_E2E_BASE": "http://127.0.0.1:%d" % dead_port}, script=os.path.join(QA, "staging_e2e_run.sh"))
ok("repo layout: with no runner under OVN_DIR the script resolves scripts/qa/e2e relative to its own qa dir and runs", "run: no previous result" in p.stdout and os.path.exists(os.path.join(bx2, "state", "staging_e2e_box.json")), p.stdout + p.stderr[-200:])
rj = json.load(open(os.path.join(bx2, "state", "staging_e2e_box.json")))
ok("stub unreachable (infra): result written with every cell UNVERIFIED and deploy_commit null so the next hour RETRIES", set(c["verdict"] for c in rj["cells"]) == {"UNVERIFIED"} and rj["deploy_commit"] is None, rj)
p = run_sh(bx2, {"QA_E2E_BASE": "http://127.0.0.1:%d" % dead_port}, script=os.path.join(QA, "staging_e2e_run.sh"))
ok("  ... and it is retried at the next cron tick ('inconclusive')", "run: last result was inconclusive" in p.stdout, p.stdout)
bx3 = make_box("box3")
p = run_sh(bx3, {"QA_E2E_RUNNER": os.path.join(bx3, "nope.py")})
rj = json.load(open(os.path.join(bx3, "state", "staging_e2e_box.json"))) if os.path.exists(os.path.join(bx3, "state", "staging_e2e_box.json")) else {}
ok("runner path that does not exist: logged with the destination + mkdir hint, exit 0, and an honest harness-error result is WRITTEN (never silent)",
   p.returncode == 0 and "runner not found at" in p.stdout and "mkdir -p" in p.stdout and rj.get("cells", [{}])[0].get("cell") == "harness" and rj["cells"][0]["verdict"] == "UNVERIFIED"
   and "runner not found at" in rj["cells"][0]["detail"] and rj.get("deploy_commit") is None, (p.stdout, rj))
crash = os.path.join(bx3, "crash.py")
open(crash, "w").write("import sys\nsys.exit(3)\n")
p = run_sh(bx3, {"QA_E2E_RUNNER": crash})
rj = json.load(open(os.path.join(bx3, "state", "staging_e2e_box.json")))
ok("a crashing runner: exit 0 and an honest harness-error result (cell harness UNVERIFIED, deploy_commit null)", p.returncode == 0 and rj["cells"][0]["cell"] == "harness" and rj["cells"][0]["verdict"] == "UNVERIFIED" and rj["deploy_commit"] is None, rj)

# ==================================================================================================================== 13. qa_daily_shadow.sh: staging_smoke scheduling
print("# 13. qa_daily_shadow.sh runs qa/staging_smoke.py daily (shadow), one alert per (repo, day) on FAIL, serial with the e2e lock")
ds = os.path.join(T, "daily")
shutil.rmtree(ds, ignore_errors=True)
os.makedirs(os.path.join(ds, "qa"))
os.makedirs(os.path.join(ds, "state"))
for f in ("qa_common.py", "qa_timeout.py", "qa_daily_shadow.sh"):
    shutil.copy(os.path.join(QA, f), os.path.join(ds, "qa", f))
open(os.path.join(ds, "qa", "staging_smoke.py"), "w").write(
    "import json,sys\nrepo=sys.argv[sys.argv.index('--repo')+1]\n"
    "v={'iptv_apps':'FAIL','gitlark':'FLAG','billwatch':'PASS'}[repo]\n"
    "print(json.dumps({'verdict':v,'summary':'%s smoke %s' % (repo, v),'ref':'h','repo':repo}))\n")
def daily(args=(), extra=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("OVN_") and not k.startswith("QA_STATE")}
    e.update({"OVN_DIR": ds, "QA_DAILY_REPOS": "zz", "QA_DAILY_STAGING_REPOS": "zz", "QA_GATE_TIMEOUT": "30", "QA_E2E_LOCK_WAIT_S": "1"})
    e.update(extra or {})
    return subprocess.run(["bash", os.path.join(ds, "qa", "qa_daily_shadow.sh")] + list(args), capture_output=True, text=True, env=e, timeout=120)
daily()
daily()
lg = open(os.path.join(ds, "logs", "qa_daily_shadow.log")).read()
alerts = open(os.path.join(ds, "state", "alerts.log")).read().splitlines() if os.path.exists(os.path.join(ds, "state", "alerts.log")) else []
ok("full run logs a staging_smoke line for billwatch, gitlark and iptv_apps with their verdicts", all(x in lg for x in ("staging_smoke billwatch: PASS", "staging_smoke gitlark: FLAG", "staging_smoke iptv_apps: FAIL")), lg[-400:])
ok("smoke FAIL: ONE alerts.log WARN across two runs the same day; PASS and FLAG(PARTIAL gitlark) raise nothing", len(alerts) == 1 and "iptv_apps staging smoke FAIL" in alerts[0], alerts)
ok("the e2e lock is released after every smoke", not os.path.exists(os.path.join(ds, "state", "staging_e2e.lock")))
open(os.path.join(ds, "logs", "qa_daily_shadow.log"), "w").close()
daily(["--staging-only"])
ok("--staging-only (the hourly pass) runs NO smoke", "staging_smoke" not in open(os.path.join(ds, "logs", "qa_daily_shadow.log")).read())
os.makedirs(os.path.join(ds, "state", "staging_e2e.lock"))
open(os.path.join(ds, "logs", "qa_daily_shadow.log"), "w").close()
daily(extra={"QA_DAILY_SMOKE_REPOS": "billwatch"})
ok("lock held by the e2e runner: the smoke is SKIPPED (logged), never run concurrently", "staging_smoke billwatch: SKIPPED" in open(os.path.join(ds, "logs", "qa_daily_shadow.log")).read()
   and os.path.isdir(os.path.join(ds, "state", "staging_e2e.lock")))
os.utime(os.path.join(ds, "state", "staging_e2e.lock"), (946684800, 946684800))
open(os.path.join(ds, "logs", "qa_daily_shadow.log"), "w").close()
daily(extra={"QA_DAILY_SMOKE_REPOS": "billwatch"})
ok("a STALE e2e lock (year 2000, e.g. a killed runner) is swept and the smoke runs; the lock is released afterwards", "staging_smoke billwatch: PASS" in open(os.path.join(ds, "logs", "qa_daily_shadow.log")).read()
   and not os.path.exists(os.path.join(ds, "state", "staging_e2e.lock")))

# ==================================================================================================================== 14. G10 replay against the stub
print("# 14. gold row G10: qa_replay.py --gold over a fixture gold file, gate = the real playback_token cell against the stub (7d87fbd1 vs the hotfix)")
gold = json.load(open(os.path.join(QA, "gold_set.json")))
g10 = next(r for r in gold["rows"] if r["id"] == "G10")
ok("production gold row G10 is a true positive for iptv_apps with the full 7d87fbd1 head, mentions ?token=, names the playback_token cell and no longer reads 'known_gap'",
   g10["kind"] == "true_positive" and g10["head"].startswith("7d87fbd1") and len(g10["head"]) == 40 and "?token=" in g10["title"] and g10["live_check"]["cell"] == "playback_token"
   and g10["gate"].startswith("pending:") and not [r for r in gold["rows"] if r["id"] == "G10" and r is not g10])
gd = os.path.join(T, "gold")
shutil.rmtree(gd, ignore_errors=True)
os.makedirs(os.path.join(gd, "qa"))
os.makedirs(os.path.join(gd, "repos", "iptv_apps"))
subprocess.run(["git", "init", "-q", os.path.join(gd, "repos", "iptv_apps")], capture_output=True)
for f in ("qa_common.py", "qa_replay.py"):
    shutil.copy(os.path.join(QA, f), os.path.join(gd, "qa", f))
shutil.copy(RUNNER, os.path.join(gd, "qa", "chickadee_staging_e2e.py"))
shim = '''#!/usr/bin/env python3
"""test-local replay shim for gold row G10: stands up the stub of staging (the head decides its behaviour: 7d87fbd1 = ?token= accepts only playback-type tokens)
and runs the REAL playback_token cell against it. The stub / fixtures come from test_qa_staging_e2e.py itself (everything above its STUB_END marker)."""
import json, os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc
head = sys.argv[sys.argv.index("--head") + 1]
srcfile = os.environ["G10_STUB_SOURCE"]
prelude = open(srcfile).read().split("#@@" + "STUB_END@@")[0]
ns = {"__name__": "g10_prelude", "__file__": srcfile}
exec(compile(prelude, srcfile, "exec"), ns)
stub = ns["Stub"](token_query_playback_only=head.startswith("7d87fbd1"))
res = ns["E"].run(stub.base, ["auth_login", "playback_token"], ns["make_state"]("g10_shim"))
v = {c["cell"]: c for c in res["cells"]}["playback_token"]
stub.stop()
shutil.rmtree(ns["T"], ignore_errors=True)
print(json.dumps(qc.verdict(v["verdict"], "g10replay", "iptv_apps", head[:10], v["detail"], {"findings": []})))
'''
open(os.path.join(gd, "qa", "gate_g10replay.py"), "w").write(shim)
fx = {"version": 2, "rows": [
    {"id": "G10", "repo": "iptv_apps", "base": g10["base"], "head": g10["head"], "gate": "g10replay", "kind": "true_positive", "catch_verdicts": ["FAIL"]},
    {"id": "G10fixed", "repo": "iptv_apps", "base": g10["head"], "head": "7a986d1b46a30c9a7566135c6e2b10e76cf2a9a6", "gate": "g10replay", "kind": "benign"},
    {"id": "G10wrong", "repo": "iptv_apps", "base": g10["base"], "head": "7a986d1b46a30c9a7566135c6e2b10e76cf2a9a6", "gate": "g10replay", "kind": "true_positive", "catch_verdicts": ["FAIL"]}]}   # seeded WRONG expectation
gf = os.path.join(gd, "gold_fx.json")
json.dump(fx, open(gf, "w"))
envg = {k: v for k, v in os.environ.items() if not k.startswith("OVN_") and not k.startswith("QA_STATE")}
envg.update({"OVN_DIR": gd, "OVN_REPOS_DIR": os.path.join(gd, "repos"), "G10_STUB_SOURCE": os.path.abspath(__file__), "G10_IN_SHIM": "1", "QA_PAUSED_REPOS": "none"})
pg_ = subprocess.run([PY, os.path.join(gd, "qa", "qa_replay.py"), "--gold", "--gold-file", gf, "--json", "--only", "G10,G10fixed,G10wrong"], capture_output=True, text=True, env=envg, timeout=300)
try:
    stt = {r["id"]: r["status"] for r in json.loads(pg_.stdout.strip().splitlines()[-1])["results"]}
except Exception:  # noqa: BLE001
    stt = {}
ok("qa_replay.py --gold: G10 at 7d87fbd1 is CAUGHT (the real cell FAILs on the ?token= 401), the hotfix head is CLEAN, a wrong expectation is MISSED (the replay can tell them apart)",
   stt == {"G10": "CAUGHT", "G10fixed": "CLEAN", "G10wrong": "MISSED"}, (stt, pg_.stdout[-400:], pg_.stderr[-300:]))
ok("the replay recorded nothing to state/qa_shadow", not os.path.exists(os.path.join(gd, "state", "qa_shadow")))

# ==================================================================================================================== 15. mutation checks
print("# 15. mutation checks: break the logic in a temp copy => the matching control stops holding (so the controls above can fail)")
MUT = os.path.join(T, "mut")
os.makedirs(MUT, exist_ok=True)
def mutate_runner(old, new, tag):
    src_ = open(RUNNER).read()
    assert src_.count(old) == 1, "mutation target not found exactly once: %r (%d)" % (old, src_.count(old))
    p_ = os.path.join(MUT, "runner_%s.py" % tag)
    open(p_, "w").write(src_.replace(old, new))
    return load(p_, "runner_mut_" + tag)
def cell_under(mod, modes, cell, state_kw=None, **kw):
    stub_ = Stub(**modes)
    try:
        r = mod.run(stub_.base, None, make_state("mutstate", **(state_kw or {})), **kw)
        return {c["cell"]: c["verdict"] for c in r["cells"]}.get(cell), stub_, r
    finally:
        stub_.stop()
RUNNER_MUTATIONS = [
    ("ssrf: a 2xx / job id is counted as a refusal", 'if r.status < 400 or \'"job_id"\' in body:\n        return "accepted"', 'if r.status < 400 or \'"job_id"\' in body:\n        return "refused"', {"import_accepts_private": True}, "ssrf_refusal"),
    ("playback: a 401 on ?token= is tolerated", "if is_auth_rejection(with_tok):", "if False:", {"token_query_playback_only": True}, "playback_token"),
    ("playback: an open proxy (no token) is tolerated", "if auth_passed(anon):", "if False:", {"open_proxy": True}, "playback_token"),
    ("rate: 429 / retry-after ignored", "if n429 or retry_after:", "if False:", {"rate_429_at": 20}, "rate_limit_sanity"),
    ("health: served commit not compared with the deploy export", 'elif _same_commit(served, d["commit"]):', "elif True:", {"commit": OTHER}, "health_provenance"),
    ("health: migrations state ignored", 'elif mig in (None, "unknown"):', "elif True:", {"migrations": "mismatch"}, "health_provenance"),
    ("referral: second redeem not checked", "if not rejected(r2):", "if False:", {"second_redeem_ok": True}, "referral_flow"),
    ("referral: self redeem not checked", "if not rejected(r3):", "if False:", {"self_redeem_ok": True}, "referral_flow"),
    ("vod: catalog keys not checked", "missing = [k for k in want if k not in j]", "missing = []", {"vod_missing_items": True}, "vod_catalog"),
    ("auth: anonymous /me must-be-401 not checked", "elif anon.status in (401, 403):", "elif True:", {"anon_me_ok": True}, "auth_login"),
]
for label, old, new, modes, cell in RUNNER_MUTATIONS:
    m_ = mutate_runner(old, new, re.sub(r"\W+", "_", label)[:30])
    v_, _s, _r = cell_under(m_, modes, cell)
    ok("mutation [%s]: control no longer FAILs (%s -> %s)" % (label, cell, v_), v_ != "FAIL")
m_ = mutate_runner("return self.status == 0 or self.status in GATEWAY", "return self.status in GATEWAY", "infra")
rr_ = m_.run(Dead.base, ["health_provenance"], make_state("mutinfra"), timeout=2.0)
ok("mutation [infra: 'no response' stops being infrastructure]: the refused-connection control turns into a FAIL", verdicts(rr_)["health_provenance"] == "FAIL", verdicts(rr_))
m_ = mutate_runner("    for fn in reversed(ctx.cleanups):", "    for fn in []:", "cleanup")
v_, s_, r_ = cell_under(m_, {}, "referral_flow")
ok("mutation [cleanup disabled]: qa-e2e users / streams are left behind and the result reports 0 deletes (the cleanup assertions would fail)",
   (bool(set(s_.accounts) - {PREMIUM[0], FREE[0]}) or bool(s_.streams)) and r_["cleanup"]["attempted"] == 0, list(s_.accounts))
m_ = mutate_runner("            if fn() not in (200, 204):\n                failed += 1", "            fn()", "cleanupcount")
v_, s_, r_ = cell_under(m_, {"delete_fails": True}, "referral_flow")
ok("mutation [failed deletes not counted]: leftover users go unreported (cleanup.failed stays 0 while the stub still holds them)", r_["cleanup"]["failed"] == 0 and bool(set(s_.accounts) - {PREMIUM[0], FREE[0]}), r_["cleanup"])
m_ = mutate_runner('r = ctx.c.request("GET", "/openapi.json", max_body=OPENAPI_MAX)', 'r = ctx.c.request("GET", "/openapi.json")', "oacap")
v_, s_, r_ = cell_under(m_, {}, "auth_login")
ok("mutation [openapi read through the 64 KiB cap]: a ~240 KB staging openapi is truncated and every route-dependent cell turns UNVERIFIED (the live run caught exactly this)", v_ == "UNVERIFIED" and "without a paths document" in json.dumps(r_), v_)
m_ = mutate_runner("        s = str(s)\n        for sec in sorted(self.secrets", "        return str(s)\n        for sec in sorted(self.secrets", "redact")
stub = Stub(vod_500=True)
rr_ = m_.run(stub.base, ["auth_login", "vod_catalog"], make_state("mutredact"))
leak = json.dumps(rr_)
ok("mutation [redactor disabled]: the seeded token / password reach the verdict detail (the redaction test would fail)", any(t in leak for t in stub.issued), leak[:200])
stub.stop()
m_ = mutate_runner('if u.scheme != "https" or "staging" not in host or "production" in host or not host.endswith(".up.railway.app"):', "if False:", "guard")
os.environ.pop("QA_E2E_ALLOW_LOCAL")
try:
    m_.check_base("https://chickadeestream-production.up.railway.app")
    guard_broken = True
except ValueError:
    guard_broken = False
os.environ["QA_E2E_ALLOW_LOCAL"] = "1"
ok("mutation [host guard removed]: a production URL is accepted (the guard test would fail)", guard_broken)
m_ = mutate_runner("        if self.count >= limit:", "        if False:", "budget")
stub = Stub()
m_.run(stub.base, None, make_state("mutbudget"), budget=10)
ok("mutation [budget not enforced]: the run exceeds its budget (the budget test would fail)", len(stub.requests) > 10, len(stub.requests))
stub.stop()
m_ = mutate_runner("        if self.last is not None and self.interval > 0:", "        if False:", "throttle")
stub = Stub()
clock = [0.0]
sleeps = []
cl = m_.Client(stub.base, interval=1.0, sleep=fsleep, clock=lambda: clock[0])
for _ in range(4):
    cl.request("GET", "/health")
ok("mutation [throttle removed]: no sleeps between requests (the throttle test would fail)", sleeps == [], sleeps)
stub.stop()

def mutate_pg(old, new, tag):
    d_ = os.path.join(MUT, "pg_" + tag)
    os.makedirs(d_, exist_ok=True)
    shutil.copy(os.path.join(QA, "qa_common.py"), d_)
    s_ = open(os.path.join(QA, "promote_gate.py")).read()
    assert s_.count(old) == 1, (old, s_.count(old))
    open(os.path.join(d_, "promote_gate.py"), "w").write(s_.replace(old, new))
    return load(os.path.join(d_, "promote_gate.py"), "pg_mut_" + tag)
PG_MUTATIONS = [
    ("block without commit match", "age_s is not None and 0 <= age_s < max_age_s)\n", "age_s is not None and 0 <= age_s < max_age_s) or (mode == 'enforce' and verdict == 'FAIL' and age_s is not None and age_s < max_age_s)\n",
     lambda g: g.decide_e2e_block("enforce", "FAIL", False, 600)),
    ("stale evidence still blocks", "0 <= age_s < max_age_s", "0 <= age_s", lambda g: g.decide_e2e_block("enforce", "FAIL", True, 50 * 3600)),
    ("shadow blocks", 'mode == "enforce" and verdict == "FAIL" and match is True', 'mode in ("enforce", "shadow") and verdict == "FAIL" and match is True', lambda g: g.decide_e2e_block("shadow", "FAIL", True, 60)),
    ("UNVERIFIED blocks", 'verdict == "FAIL" and match is True', 'verdict != "PASS" and match is True', lambda g: g.decide_e2e_block("enforce", "UNVERIFIED", True, 60)),
    ("evaluate lets a non-matching FAIL speak for the candidate", 's["counts"] = bool(s["match"] and s["age"] < E2E_MAX_AGE_S)', 's["counts"] = bool(s["age"] < E2E_MAX_AGE_S)',
     lambda g: g.e2e_evaluate([dict(src("box", ["FAIL"], 60, OTHER), source="box"), dict(src("mac", ["PASS"], 600, COMMIT), source="mac")], [], COMMIT, lambda a, b: None, NOW, "enforce")["e2e_verdict"] == "FAIL"),
]
for label, old, new, probe in PG_MUTATIONS:
    g_ = mutate_pg(old, new, re.sub(r"\W+", "_", label)[:24])
    ok("mutation promote_gate [%s]: a block appears where the control demands none" % label, bool(probe(g_)))
def mutate_ingest(old, new, tag):
    d_ = os.path.join(MUT, "ing_" + tag)
    os.makedirs(d_, exist_ok=True)
    for f in ("qa_common.py", "promote_gate.py"):
        shutil.copy(os.path.join(QA, f), d_)
    s_ = open(os.path.join(QA, "staging_e2e_ingest.py")).read()
    assert s_.count(old) == 1, (old, s_.count(old))
    open(os.path.join(d_, "staging_e2e_ingest.py"), "w").write(s_.replace(old, new))
    return d_
d_ = mutate_ingest('    with open(marker, "w"):\n        pass  # only after the line is on disk: a failed append is retried on the next run\n', "    pass\n", "marker")
qsd2 = os.path.join(T, "ing_mut_state")
shutil.rmtree(qsd2, ignore_errors=True)
os.makedirs(qsd2)
json.dump(dict(box, ts=iso(time.time() - 100)), open(os.path.join(qsd2, "staging_e2e_box.json"), "w"))
e_ = dict(os.environ, QA_STATE_DIR=qsd2, OVN_DIR=T)
subprocess.run([PY, os.path.join(d_, "staging_e2e_ingest.py")], capture_output=True, env=e_, timeout=60)
json.dump(dict(box, ts=iso(time.time() - 50)), open(os.path.join(qsd2, "staging_e2e_box.json"), "w"))
subprocess.run([PY, os.path.join(d_, "staging_e2e_ingest.py")], capture_output=True, env=e_, timeout=60)
ok("mutation ingest [dedupe marker not written]: the same (cell, commit) alerts twice (the one-alert test would fail)", len(open(os.path.join(qsd2, "alerts.log")).read().splitlines()) == 2)
d_ = mutate_ingest("        if seen.get(src[\"source\"], 0) >= src[\"ts\"]:\n            continue\n", "", "seen")
shutil.rmtree(qsd2, ignore_errors=True)
os.makedirs(qsd2)
json.dump(dict(box, ts=iso(time.time() - 100)), open(os.path.join(qsd2, "staging_e2e_box.json"), "w"))
for _ in range(2):
    subprocess.run([PY, os.path.join(d_, "staging_e2e_ingest.py")], capture_output=True, env=e_, timeout=60)
ok("mutation ingest [already-ingested check removed]: duplicate shadow rows (the idempotence test would fail)", len(open(os.path.join(qsd2, "qa_shadow", "staging_e2e.jsonl")).read().splitlines()) == 2)
d_ = mutate_ingest("          (re.compile(r\"(?i)(bearer\\s+)[A-Za-z0-9._~+/=-]{8,}\"), r\"\\1[redacted]\"),\n", "", "scrub")
shutil.rmtree(qsd2, ignore_errors=True)
os.makedirs(qsd2)
json.dump(dict(box, ts=iso(time.time() - 100)), open(os.path.join(qsd2, "staging_e2e_box.json"), "w"))
subprocess.run([PY, os.path.join(d_, "staging_e2e_ingest.py")], capture_output=True, env=e_, timeout=60)
ok("mutation ingest [bearer scrub removed]: a bearer token in a detail reaches alerts.log (the leak test would fail)", SEED_BEARER in open(os.path.join(qsd2, "alerts.log")).read())


# ==================================================================================================================== 16. review fixes (qa-staging-e2e-v2 fixer round)
print("# 16. review fixes: relay 502, proxy passthrough, credentials rejected, export lag, cleanup alert, silent Mac source, cron install, enforce typo")
def mutated_copy(path, old, new, tag):
    src_ = open(path).read()
    assert src_.count(old) == 1, "mutation target not found exactly once: %r (%d)" % (old, src_.count(old))
    out_ = os.path.join(MUT, tag + "_" + os.path.basename(path))
    open(out_, "w").write(src_.replace(old, new))
    return out_
def cell_detail(res, cell):
    return next(c["detail"] for c in res["cells"] if c["cell"] == cell)
def one_cell(modes, cell, state_kw=None, mod=None, **kw):
    stub_ = Stub(**modes)
    try:
        r_ = (mod or E).run(stub_.base, None, make_state("fx", **(state_kw or {})), **kw)
        return verdicts(r_)[cell], cell_detail(r_, cell), r_
    finally:
        stub_.stop()

# ---- 16a. SSRF: an app-generated 502 on the relay probe means the server TRIED the fetch (the guard is gone)
R = E.Resp
ok("classify: app 502 with a JSON detail ('Failed to fetch stream') = accepted (the outbound fetch was attempted)", E.classify_refusal(R(502, text='{"detail":"Failed to fetch stream"}')) == "accepted")
ok("classify: app 504 with a JSON detail = accepted", E.classify_refusal(R(504, text='{"detail":"Gateway timeout fetching stream"}')) == "accepted")
ok("classify: Railway edge 502 (JSON without detail / HTML / detail 'Application failed to respond') stays infrastructure = unverified",
   E.classify_refusal(R(502, text='{"status":"error","code":502,"message":"Application failed to respond"}')) == "unverified"
   and E.classify_refusal(R(502, text="<html><body>Application failed to respond</body></html>")) == "unverified"
   and E.classify_refusal(R(502, text='{"detail":"Application failed to respond"}')) == "unverified")
ok("classify: no response and a plain 503 are infrastructure too", E.classify_refusal(R(0, err="timeout")) == "unverified" and E.classify_refusal(R(503, text='{"detail":"busy"}')) == "unverified")
v_, d_, r_ = one_cell({"relay_guard_missing_502": True}, "ssrf_refusal")
ok("relay guard missing -> 502 JSON: ssrf_refusal FAILs and names the relay probes (the import probes still refuse cleanly)", v_ == "FAIL" and "relay" in d_ and "502" in d_ and "import http" not in d_, (v_, d_))
v_, d_, r_ = one_cell({"relay_edge_502": True}, "ssrf_refusal")
ok("relay answers with Railway's EDGE 502 (no app detail): UNVERIFIED, never PASS and never FAIL", v_ == "UNVERIFIED", (v_, d_))
table("relay edge 502 leaves every other cell untouched", {"relay_edge_502": True}, expect={"ssrf_refusal": "UNVERIFIED"})

# ---- 16b. playback_token: the origin's status passed through is not our auth
table("proxy passes the ORIGIN's 403 through ('Upstream returned 403 for stream'): auth passed, no false G10 FAIL", {"proxy_upstream": 403})
table("proxy passes the origin's 401 through: auth passed, no false G10 FAIL", {"proxy_upstream": 401})
table("proxy passes the origin's 404 through (what example.com really answers): PASS", {"proxy_upstream": 404})
v_, d_, r_ = one_cell({"proxy_not_found": True}, "playback_token")
ok("proxy answers 404 'Stream not found' to the ?token= request: UNVERIFIED (not an auth verdict, not 'auth passed')", v_ == "UNVERIFIED" and "neither" in d_, (v_, d_))
v_, d_, r_ = one_cell({"proxy_500": True}, "playback_token")
ok("proxy 500s on the ?token= request: UNVERIFIED", v_ == "UNVERIFIED", (v_, d_))
ok("helpers: is_auth_rejection = 401/403 without the upstream marker; auth_passed = 2xx or an upstream passthrough, never a bare 404 / 500",
   E.is_auth_rejection(R(401, text='{"detail":"Could not validate credentials"}')) and E.is_auth_rejection(R(403, text="{}")) and not E.is_auth_rejection(R(403, text='{"detail":"Upstream returned 403 for stream"}'))
   and E.auth_passed(R(200)) and E.auth_passed(R(403, text='{"detail":"Upstream returned 403 for stream"}')) and E.auth_passed(R(404, text='{"detail":"Upstream returned 404 for stream"}'))
   and not E.auth_passed(R(404, text='{"detail":"Stream not found"}')) and not E.auth_passed(R(500, text='{"detail":"x"}')) and not E.auth_passed(R(401, text='{"detail":"Could not validate credentials"}')))

# ---- 16c. auth_login: a rejected canonical credential is test data, not a product defect
v_, d_, r_ = one_cell({"login_reject": ("premium",)}, "auth_login")
ok("premium canonical login 401: auth_login UNVERIFIED and says to check state/qa_creds (never FAIL)", v_ == "UNVERIFIED" and "state/qa_creds" in d_ and "credentials rejected" in d_, (v_, d_))
table("premium credentials rejected: only the cells that need that login are UNVERIFIED", {"login_reject": ("premium",)},
      expect={"auth_login": "UNVERIFIED", "ssrf_refusal": "UNVERIFIED", "playback_token": "UNVERIFIED"})
table("free canonical login 403: auth_login UNVERIFIED, the premium cells still PASS (the stub also rejects the fresh referral users' logins, hence referral_flow UNVERIFIED)", {"login_reject": ("free",), "login_reject_status": 403},
      expect={"auth_login": "UNVERIFIED", "referral_flow": "UNVERIFIED"})
v_, d_, r_ = one_cell({"login_reject": ("premium",), "login_reject_status": 500}, "auth_login")
ok("a login that 500s stays a FAIL (a server error is not a credentials problem)", v_ == "FAIL", (v_, d_))

# ---- 16d. health_provenance: the Mac export can lag a deploy
def write_export(st_, specs, age=30):
    """specs = [(commit, seconds ago created, status)] newest first."""
    now_ = time.time()
    dl_ = [{"id": "dep%05d" % i, "status": stt, "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ - off)), "meta": {"commitHash": c}} for i, (c, off, stt) in enumerate(specs)]
    json.dump({"repo": "iptv_apps", "fetched_at": now_ - age, "deployments": dl_}, open(os.path.join(st_, "staging_deploys", "iptv_apps.json"), "w"))
def health_of(modes, state_kw=None, mod=None, client_hook=None, state_edit=None):
    stub_ = Stub(**modes)
    try:
        st_ = make_state("fxh", **(state_kw or {}))
        if state_edit:
            state_edit(st_)
        kw_ = {}
        if client_hook:
            kw_["client"] = E.Client(stub_.base, interval=0, sleep=client_hook(st_))
        r_ = (mod or E).run(stub_.base, ["health_provenance"], st_, **kw_)
        return verdicts(r_)["health_provenance"], cell_detail(r_, "health_provenance"), r_
    finally:
        stub_.stop()
v_, d_, r_ = health_of({"commit": OTHER}, {"age": 60, "unlisted_since": 3600})
ok("served commit not in the deploy list, first seen an hour ago, snapshot 60 s old (taken after that sighting): FAIL (the provenance verdict)", v_ == "FAIL" and "not in the deploy list" in d_, (v_, d_))
v_, d_, r_ = health_of({"commit": OTHER}, {"age": 600})
ok("an unlisted served commit with an export snapshot 10 min old: UNVERIFIED 'export lags the deploy' (a deploy finished after the export), never FAIL", v_ == "UNVERIFIED" and "export lags" in d_, (v_, d_))
def listed_old_snapshot(st_):
    write_export(st_, [(COMMIT, 3600, "SUCCESS"), (OTHER, 7200, "SUCCESS")], age=600)
v_, d_, r_ = health_of({"commit": OTHER}, state_edit=listed_old_snapshot)
ok("a LISTED but not-latest served commit with a 10 min old snapshot: UNVERIFIED 'export lags the deploy', never FAIL", v_ == "UNVERIFIED" and "export lags" in d_, (v_, d_))
def lag_hook(st_):
    def hook(wait):
        write_export(st_, [(COMMIT, 20, "SUCCESS"), (OTHER, 5000, "SUCCESS")], age=1)   # the export caught up while the runner paused
    return hook
os.environ.pop("QA_E2E_REREAD_WAIT_S")
waits_ = []
def lag_hook_logged(st_):
    h_ = lag_hook(st_)
    def hook(wait):
        waits_.append(wait)
        h_(wait)
    return hook
v_, d_, r_ = health_of({"commit": COMMIT}, {"commit": OTHER, "age": 600}, client_hook=lag_hook_logged)
ok("mismatch -> the export is re-read after a pause (5 s by default) and the caught-up snapshot makes the cell PASS", v_ == "PASS" and waits_ == [5.0] and r_["deploy_commit"] == COMMIT, (v_, d_, waits_, r_["deploy_commit"]))
os.environ["QA_E2E_REREAD_WAIT_S"] = "0"
def old_listed(st_):
    write_export(st_, [(COMMIT, 120, "SUCCESS"), (OTHER, 7200, "SUCCESS")], age=30)
v_, d_, r_ = health_of({"commit": OTHER}, state_edit=old_listed)
ok("served commit IS listed but is not the latest SUCCESS, which went out only 2 min ago: UNVERIFIED (traffic switch-over)", v_ == "UNVERIFIED" and "switch-over" in d_, (v_, d_))
def old_listed_settled(st_):
    write_export(st_, [(COMMIT, 3600, "SUCCESS"), (OTHER, 7200, "SUCCESS")], age=30)
v_, d_, r_ = health_of({"commit": OTHER}, state_edit=old_listed_settled)
ok("same, but the latest SUCCESS has been out for an hour and the snapshot is fresh: FAIL (an older deploy is really serving)", v_ == "FAIL" and "older deploy" in d_, (v_, d_))
ok("_same_commit: prefix-tolerant both ways, never on empty", E._same_commit("67ed0626ab", "67ed0626") and E._same_commit("67ed0626", "67ed0626ab") and not E._same_commit("", "67ed0626") and not E._same_commit("67ed0626", "051c28f9"))

# ---- 16e. ingest: cleanup failures and a silent source are visible
ING = load(os.path.join(QA, "staging_e2e_ingest.py"), "ing_fix")
def fresh_state(name):
    d_ = os.path.join(T, name)
    shutil.rmtree(d_, ignore_errors=True)
    os.makedirs(d_)
    return d_
def alerts_of(d_):
    try:
        return open(os.path.join(d_, "alerts.log")).read().splitlines()
    except OSError:
        return []
def ing_run(d_, now):
    old_ = os.environ.get("QA_STATE_DIR")
    os.environ["QA_STATE_DIR"] = d_
    try:
        return ING.ingest(d_, now)
    finally:
        if old_ is None:
            os.environ.pop("QA_STATE_DIR", None)
        else:
            os.environ["QA_STATE_DIR"] = old_
GOOD_CELLS = [{"cell": "health_provenance", "verdict": "PASS", "ms": 1, "detail": "ok"}]
t0_ = 1_800_000_000.0
d_ = fresh_state("fx_clean")
json.dump({"ts": iso(t0_ - 100), "staging_commit": COMMIT, "cells": GOOD_CELLS, "cleanup": {"attempted": 3, "failed": 2}}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t0_)
al_ = alerts_of(d_)
ok("a result with cleanup.failed=2 raises ONE alerts.log WARN naming the leftovers, even though every cell PASSed", len(al_) == 1 and "cleanup FAILED for 2 of 3" in al_[0] and "qa-e2e-" in al_[0], al_)
json.dump({"ts": iso(t0_ - 50), "staging_commit": COMMIT, "cells": GOOD_CELLS, "cleanup": {"attempted": 3, "failed": 3}}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t0_ + 10)
ok("a second failing run the same UTC day does not alert again", len(alerts_of(d_)) == 1, alerts_of(d_))
json.dump({"ts": iso(t0_ + 80000), "staging_commit": COMMIT, "cells": GOOD_CELLS, "cleanup": {"attempted": 3, "failed": 1}}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t0_ + 86400 + 100)
ok("the next UTC day alerts again", len(alerts_of(d_)) == 2, alerts_of(d_))
json.dump({"ts": iso(t0_ + 90000), "staging_commit": COMMIT, "cells": GOOD_CELLS, "cleanup": {"attempted": 3, "failed": 0}}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t0_ + 3 * 86400)
ok("cleanup.failed=0 (or no cleanup field at all) never alerts", len(alerts_of(d_)) == 2, alerts_of(d_))
ok("promote_gate.normalize_e2e keeps only integer cleanup counts", PGM.normalize_e2e({"ts": iso(NOW), "cells": [], "cleanup": {"attempted": 3, "failed": 2, "x": "y"}})["cleanup"] == {"attempted": 3, "failed": 2}
   and PGM.normalize_e2e({"ts": iso(NOW), "cells": [], "cleanup": "bad"})["cleanup"] == {} and PGM.normalize_e2e({"ts": iso(NOW), "cells": []})["cleanup"] == {})
HARNESS = {"passed": 0, "total": 0, "failed": ["harness-error"], "cells": [{"cell": "revenuecat_lifecycle", "verdict": "UNVERIFIED", "ms": 0, "detail": "the lifecycle produced no result (harness error)"}]}
d_ = fresh_state("fx_streak")
mac_p = os.path.join(d_, "qa_staging_e2e.json")
for i in range(1, 3):
    json.dump(dict(HARNESS, ts=iso(t0_ + i * 21600 - 21600)), open(mac_p, "w"))
    ing_run(d_, t0_ + i * 21600)
ok("a Mac source that keeps producing only UNVERIFIED (harness error) does NOT alert after 2 results", alerts_of(d_) == [], alerts_of(d_))
json.dump(dict(HARNESS, ts=iso(t0_ + 2 * 21600)), open(mac_p, "w"))
ing_run(d_, t0_ + 3 * 21600)
al_ = alerts_of(d_)
ok("... but alerts ONCE at the 3rd consecutive result, naming the source and the Mac fix (Railway login / launchctl kickstart)", len(al_) == 1 and "mac e2e source gave NO usable evidence for 3" in al_[0] and "launchctl kickstart" in al_[0] and "railway" in al_[0].lower(), al_)
json.dump(dict(HARNESS, ts=iso(t0_ + 3 * 21600)), open(mac_p, "w"))
ing_run(d_, t0_ + 3 * 21600 + 3600)
ok("a 4th result within 6 h of the alert is silent", len(alerts_of(d_)) == 1, alerts_of(d_))
json.dump(dict(HARNESS, ts=iso(t0_ + 4 * 21600)), open(mac_p, "w"))
ing_run(d_, t0_ + 4 * 21600 + 7200)
ok("still broken more than 6 h later: alerts again", len(alerts_of(d_)) == 2, alerts_of(d_))
json.dump({"ts": iso(t0_ + 5 * 21600), "staging_commit": COMMIT, "passed": 17, "total": 17, "failed": []}, open(mac_p, "w"))
ing_run(d_, t0_ + 5 * 21600 + 60)
for i in (6, 7):
    json.dump(dict(HARNESS, ts=iso(t0_ + i * 21600)), open(mac_p, "w"))
    ing_run(d_, t0_ + i * 21600 + 60)
ok("a good result resets the streak: two more harness errors after it do not alert", len(alerts_of(d_)) == 2, alerts_of(d_))
ok("unusable(): needs an UNVERIFIED and no PASS/FAIL; NA-only and mixed results are fine", ING.unusable([{"verdict": "UNVERIFIED"}, {"verdict": "NA"}]) and not ING.unusable([{"verdict": "UNVERIFIED"}, {"verdict": "PASS"}])
   and not ING.unusable([{"verdict": "NA"}]) and not ING.unusable([]) and not ING.unusable([{"verdict": "FAIL"}, {"verdict": "UNVERIFIED"}]))

# ---- 16f. Mac script: a harness error always warns (the old script did)
MACSH = first_existing(os.path.join(OQ, "..", "qa-staging-e2e.sh"))
def mac_run(mode, env_extra=None, sh=None):
    d_ = os.path.realpath(tempfile.mkdtemp(prefix="macsh-", dir=T))
    os.makedirs(os.path.join(d_, "scripts", "qa"))
    os.makedirs(os.path.join(d_, "home"))
    shutil.copy(sh or MACSH, os.path.join(d_, "scripts", "qa-staging-e2e.sh"))
    open(os.path.join(d_, "scripts", "railway_config_guard.py"), "w").write("")
    open(os.path.join(d_, "scripts", "qa", "rc_lifecycle_e2e.py"), "w").write(
        "import json, os, sys\nm = os.environ['FAKE_MODE']\nout = sys.argv[sys.argv.index('--json-out') + 1]\n"
        "if m == 'harness':\n    sys.exit('no webhook secret')\n"
        "bad = ['x'] if m == 'fail' else []\n"
        "json.dump({'ts': '2026-10-09T00:00:00Z', 'staging_commit': 'abcdef1234', 'passed': 1, 'total': 2 if bad else 1, 'failed': bad, 'cells': []}, open(out, 'w'))\nsys.exit(1 if bad else 0)\n")
    for n in ("ssh", "scp"):
        shim = os.path.join(d_, n + "_shim")
        open(shim, "w").write('#!/bin/sh\necho "$@" >> "%s/%s.log"\nexit 0\n' % (d_, n))
        os.chmod(shim, 0o755)
    env = dict(os.environ, HOME=os.path.join(d_, "home"), FAKE_MODE=mode, QA_E2E_SSH=os.path.join(d_, "ssh_shim"), QA_E2E_SCP=os.path.join(d_, "scp_shim"))
    env.pop("QA_E2E_MAC_ALERT", None)
    env.update(env_extra or {})
    p_ = subprocess.run(["bash", os.path.join(d_, "scripts", "qa-staging-e2e.sh")], capture_output=True, text=True, env=env, timeout=120)
    def lines(n):
        try:
            return open(os.path.join(d_, n + ".log")).read().splitlines()
        except OSError:
            return []
    return p_.returncode, lines("ssh"), lines("scp")
if not MACSH:
    print("  SKIP: scripts/qa-staging-e2e.sh is not present next to this tree (box scratch copy without scripts/): Mac-script checks skipped")
else:
    rc_, ssh_, scp_ = mac_run("harness")
    ok("Mac script, harness error (no result file): exit 0, result copied to the box, and an alert is sent even with QA_E2E_MAC_ALERT unset",
       rc_ == 0 and len(scp_) == 1 and len(ssh_) == 1 and "produced NO result" in ssh_[0] and "alerts.log" in ssh_[0], (rc_, ssh_, scp_))
    rc_, ssh_, scp_ = mac_run("fail")
    ok("Mac script, a real lifecycle FAIL with the default QA_E2E_MAC_ALERT: no direct alert (the box ingest alerts once per cell+commit)", rc_ == 0 and ssh_ == [] and len(scp_) == 1, (rc_, ssh_, scp_))
    rc_, ssh_, scp_ = mac_run("fail", {"QA_E2E_MAC_ALERT": "on"})
    ok("Mac script, a real FAIL with QA_E2E_MAC_ALERT=on: the direct warn is sent", rc_ == 0 and len(ssh_) == 1 and "FAILED" in ssh_[0], (rc_, ssh_))
    rc_, ssh_, scp_ = mac_run("pass", {"QA_E2E_MAC_ALERT": "on"})
    ok("Mac script, a passing lifecycle: no alert", rc_ == 0 and ssh_ == [] and len(scp_) == 1, (rc_, ssh_))

# ---- 16g. cron documentation: idempotent install, the staging-only line stays opt-in
CRONF = os.path.join(QA, "promote_alerting_cron.txt")
cron_txt = open(CRONF).read()
active = [l for l in cron_txt.splitlines() if l.strip() and not l.lstrip().startswith("#")]
e2e_lines = [l for l in active if "--staging-only" not in l]
ok("cron doc: the three QA-N1 lines are present once each beside the (existing, test-pinned) hourly --staging-only line",
   len(active) == 4 and sum(1 for l in active if "--staging-only" in l) == 1 and [("staging_e2e_run.sh" in l, "staging_e2e_ingest.py" in l, "evidence_freshness_check.py" in l) for l in e2e_lines] == [(True, False, False), (False, True, False), (False, False, True)], active)
def install_twice(cron_path, pre=("0 5 * * * echo keep-me",)):
    d_ = os.path.realpath(tempfile.mkdtemp(prefix="cronsim-", dir=T))
    os.makedirs(os.path.join(d_, "bin"))
    os.makedirs(os.path.join(d_, "home", "overnight-queue", "qa"))
    shutil.copy(cron_path, os.path.join(d_, "home", "overnight-queue", "qa", "promote_alerting_cron.txt"))
    store = os.path.join(d_, "store")
    open(store, "w").write("\n".join(pre) + "\n")
    open(os.path.join(d_, "bin", "crontab"), "w").write('#!/bin/sh\nif [ "$1" = "-l" ]; then cat "%s"; else t=$(cat); printf "%%s\\n" "$t" > "%s"; fi\n' % (store, store))
    os.chmod(os.path.join(d_, "bin", "crontab"), 0o755)
    cmd = next(l for l in open(cron_path).read().splitlines() if l.startswith("#   (crontab -l"))[len("#   "):]
    env = dict(os.environ, HOME=os.path.join(d_, "home"), PATH=os.path.join(d_, "bin") + os.pathsep + os.environ["PATH"])
    for _ in range(2):
        subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env, timeout=30)
    return open(store).read().splitlines()
tab = install_twice(CRONF)
ok("cron doc: running the documented install command TWICE leaves each of the three lines exactly once and keeps the unrelated entry; no --staging-only line is installed",
   [sum(1 for l in tab if k in l) for k in ("staging_e2e_run.sh", "staging_e2e_ingest.py", "evidence_freshness_check.py", "keep-me", "--staging-only")] == [1, 1, 1, 1, 0], tab)

# ---- 16h. qa_enforce.sh: no stray whitespace edit left in the python block
ENF = os.path.join(QA, "qa_enforce.sh")
ok("qa_enforce.sh keeps `bd = os.path.join(...)` (the stray `bd =os.path` edit is gone)", "bd =os.path" not in open(ENF).read() and "bd = os.path.join(qc.state_dir(), \"qa_blocked\")" in open(ENF).read())

# ---- 16i. mutations of every fix: the matching regression test must stop holding
print("# 16i. mutations of the review fixes")
def run_mut(path, tag):
    return load(path, "fxmut_" + tag)
m_ = run_mut(mutated_copy(RUNNER, 'if r.status in (502, 504) and app_generated_error(r):', 'if False:', "ssrf502"), "ssrf502")
v_, d_, _r = one_cell({"relay_guard_missing_502": True}, "ssrf_refusal", mod=m_)
ok("mutation [app 502 no longer counted as accepted]: relay guard missing turns UNVERIFIED instead of FAIL (control would fail)", v_ != "FAIL", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, 'return "failed to respond" not in str(j.get("detail", "")).lower()', 'return True', "edge502"), "edge502")
v_, d_, _r = one_cell({"relay_edge_502": True}, "ssrf_refusal", mod=m_)
ok("mutation [Railway edge 502 counted as an app 502 when it carries a detail]: unit probe flips (edge detail now 'accepted')",
   m_.classify_refusal(m_.Resp(502, text='{"detail":"Application failed to respond"}')) == "accepted")
m_ = run_mut(mutated_copy(RUNNER, 'return r.status in (401, 403) and not upstream_passthrough(r)', 'return r.status in (401, 403)', "passthru"), "passthru")
v_, d_, _r = one_cell({"proxy_upstream": 403}, "playback_token", mod=m_)
ok("mutation [upstream passthrough treated as our auth rejection]: the origin's 403 becomes a false G10 FAIL", v_ == "FAIL", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, 'return (200 <= r.status < 300) or (not r.infra and r.status != 429 and upstream_passthrough(r))', 'return not r.infra', "authpassed"), "authpassed")
v_, d_, _r = one_cell({"proxy_not_found": True}, "playback_token", mod=m_)
ok("mutation [any non-infra status counts as 'auth passed']: the 404 'Stream not found' control no longer yields UNVERIFIED", v_ != "UNVERIFIED", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, '        if r.status in (401, 403):\n            # a wrong / rotated', '        if False:\n            # a wrong / rotated', "authrej"), "authrej")
v_, d_, _r = one_cell({"login_reject": ("premium",)}, "auth_login", mod=m_)
ok("mutation [credentials rejection no longer mapped to UNVERIFIED]: a rotated password becomes an auth_login FAIL", v_ == "FAIL", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, 'if d["age_s"] > EXPORT_FRESH_S:', 'if False:', "lag"), "lag")
v_, d_, _r = health_of({"commit": OTHER}, state_edit=listed_old_snapshot, mod=m_)
ok("mutation [snapshot age ignored]: a lagging export convicts staging (FAIL)", v_ == "FAIL", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, '    d = load_deploy(ctx.state_dir)\n    ctx.deploy = d\n', '    d = ctx.deploy\n', "reread"), "reread")
v_, d_, _r = health_of({"commit": COMMIT}, {"commit": OTHER, "age": 600}, mod=m_, client_hook=lag_hook)
ok("mutation [export not re-read]: the caught-up export is never seen, the cell does not PASS", v_ != "PASS", (v_, d_))
m_ = run_mut(mutated_copy(RUNNER, 'if created is not None and time.time() - created < SWITCHOVER_S:', 'if False:', "switch"), "switch")
v_, d_, _r = health_of({"commit": OTHER}, mod=m_, state_edit=old_listed)
ok("mutation [switch-over grace removed]: a deploy that went out 2 min ago convicts the old container (FAIL)", v_ == "FAIL", (v_, d_))
def ingest_dir(old, new, tag, pg_old=None, pg_new=None):
    """-> path of a temp copy of staging_e2e_ingest.py (+ qa_common / promote_gate, optionally mutated). Run as a SUBPROCESS: the module cache would otherwise hand the mutated copy the real promote_gate."""
    d_ = os.path.join(MUT, "fxing_" + tag)
    os.makedirs(d_, exist_ok=True)
    shutil.copy(os.path.join(QA, "qa_common.py"), d_)
    pgs = open(os.path.join(QA, "promote_gate.py")).read()
    if pg_old:
        assert pgs.count(pg_old) == 1
        pgs = pgs.replace(pg_old, pg_new)
    open(os.path.join(d_, "promote_gate.py"), "w").write(pgs)
    ing = open(os.path.join(QA, "staging_e2e_ingest.py")).read()
    if old:
        assert ing.count(old) == 1, old
        ing = ing.replace(old, new)
    open(os.path.join(d_, "staging_e2e_ingest.py"), "w").write(ing)
    return os.path.join(d_, "staging_e2e_ingest.py")
REAL_ING = os.path.join(QA, "staging_e2e_ingest.py")
def cli_ingest(script, d2):
    subprocess.run([PY, script], capture_output=True, text=True, env=dict(os.environ, QA_STATE_DIR=d2, OVN_DIR=T), timeout=60)
def cleanup_alert_count(script):
    d2 = fresh_state("fx_mut_clean")
    json.dump({"ts": iso(time.time() - 100), "staging_commit": COMMIT, "cells": GOOD_CELLS, "cleanup": {"attempted": 3, "failed": 2}}, open(os.path.join(d2, "staging_e2e_box.json"), "w"))
    cli_ingest(script, d2)
    return len(alerts_of(d2))
ok("sanity: the unmutated ingest alerts once for the cleanup failure", cleanup_alert_count(REAL_ING) == 1)
ok("mutation [cleanup alert call removed]: leftovers go unreported", cleanup_alert_count(ingest_dir('        if cleanup_alert_once(state_d, src["source"], src.get("cleanup"), now):', '        if False:', "cl1")) == 0)
ok("mutation [normalize_e2e drops the cleanup counts]: leftovers go unreported",
   cleanup_alert_count(ingest_dir(None, None, "cl2", '"verdict": aggregate_cells(cells), "cleanup": cleanup}', '"verdict": aggregate_cells(cells), "cleanup": {}}')) == 0)
def streak_alert_count(script, n):
    d2 = fresh_state("fx_mut_streak")
    for i in range(n):
        json.dump(dict(HARNESS, ts=iso(time.time() - 1000 + i * 100)), open(os.path.join(d2, "qa_staging_e2e.json"), "w"))
        cli_ingest(script, d2)
    return len(alerts_of(d2))
ok("sanity: the unmutated ingest stays silent after 2 harness errors and alerts once at the 3rd", streak_alert_count(REAL_ING, 2) == 0 and streak_alert_count(REAL_ING, 3) == 1)
ok("mutation [streak alert call removed]: a permanently broken Mac lifecycle stays silent", streak_alert_count(ingest_dir('        if streak_alert(state_d, src, now):', '        if False:', "st1"), 3) == 0)
ok("mutation [streak threshold 3 -> 1]: the alert fires after the first harness error (the 'silent after 2' check would fail)", streak_alert_count(ingest_dir('STREAK_N = 3 ', 'STREAK_N = 1 ', "st2"), 2) == 1)
if MACSH:
    bad_sh = os.path.join(MUT, "mac_noalert.sh")
    open(bad_sh, "w").write(open(MACSH).read().replace('if [ "$harness_err" = "1" ]; then', 'if false; then', 1))
    rc_, ssh_, scp_ = mac_run("harness", sh=bad_sh)
    ok("mutation [harness-error warn removed from the Mac script]: nothing is sent (the harness-error test would fail)", ssh_ == [], ssh_)
bad_cron = os.path.join(MUT, "cron_nodedupe.txt")
open(bad_cron, "w").write(cron_txt.replace("grep -vF -e 'qa/staging_e2e_run.sh' -e 'qa/staging_e2e_ingest.py' -e 'qa/evidence_freshness_check.py'", "cat"))
tab2 = install_twice(bad_cron)
ok("mutation [install command without the dedupe filter]: running it twice duplicates the cron lines (the idempotence test would fail)", sum(1 for l in tab2 if "staging_e2e_run.sh" in l) == 2, tab2)
bad_cron2 = os.path.join(MUT, "cron_stagingonly.txt")
open(bad_cron2, "w").write(cron_txt.replace(" | grep -vF -e '--staging-only'", ""))
tab3 = install_twice(bad_cron2)
ok("mutation [install command without the --staging-only filter]: the separate-decision :20 line gets installed (the opt-in test would fail)", sum(1 for l in tab3 if "--staging-only" in l) >= 1, tab3)
ok("mutation [bd whitespace edit restored]: the qa_enforce check would fail", "bd =os.path" in open(ENF).read().replace("bd = os.path", "bd =os.path"))

# ==================================================================================================================== 17. round-3 review fixes
print("# 17. round-3 fixes: commit-less alert key, young-snapshot provenance, G10 doc, runner deploy path, run deadline / SIGTERM, creds alert")

# ---- 17a. alert_once without a staging commit
t17 = 1_800_000_000.0
d_ = fresh_state("fx17_unk")
a1 = ING.alert_once(d_, "health_provenance", "", "/health answered 200 but exposes no commit; status=degraded", t17)
a2 = ING.alert_once(d_, "health_provenance", "", "/health answered 200 but exposes no commit; status=degraded", t17 + 25 * 3600)
a3 = ING.alert_once(d_, "health_provenance", "", "/health answered 200 but exposes no commit; status=degraded", t17 + 25 * 3600 + 5)
a4 = ING.alert_once(d_, "health_provenance", "", "migrations='mismatch' db_revision=x", t17 + 25 * 3600 + 6)
a5 = ING.alert_once(d_, "playback_token", COMMIT, "rejected", t17)
a6 = ING.alert_once(d_, "playback_token", COMMIT, "rejected", t17 + 10)
ok("alert_once, no commit: a FAIL alerts, the same failure 25 h later alerts AGAIN (the old constant 'unknown' marker silenced it for good), the same failure the same day does not",
   (a1, a2, a3) == (True, True, False), (a1, a2, a3))
ok("alert_once, no commit: a DIFFERENT failure signature the same day still alerts; a known commit keeps the one-alert-per-(cell, commit) rule", a4 is True and (a5, a6) == (True, False), (a4, a5, a6))
ok("alert_once, no commit: numbers inside the detail do not make a new signature (a timing or count change is the same failure)",
   ING.alert_once(d_, "vod_catalog", "", "HTTP 500 after 1234 ms", t17) is True and ING.alert_once(d_, "vod_catalog", "", "HTTP 500 after 987 ms", t17 + 5) is False)
d_ = fresh_state("fx17_unk2")
for i_, ts_ in enumerate((t17 - 100, t17 + 25 * 3600 - 100)):
    json.dump({"ts": iso(ts_), "staging_commit": None, "cells": [{"cell": "health_provenance", "verdict": "FAIL", "ms": 1, "detail": "/health returned HTTP 200 but no JSON object"}]},
              open(os.path.join(d_, "staging_e2e_box.json"), "w"))
    ing_run(d_, ts_ + 100)
ok("ingest end to end: two commit-less FAIL results on different days raise two alerts.log lines", len([l for l in alerts_of(d_) if "health_provenance FAIL" in l]) == 2, alerts_of(d_))
m_ing = load(ingest_dir('        tail = "unknown_%s_%s" % (sig, time.strftime("%Y%m%d", time.gmtime(time.time() if now is None else now)))', '        tail = "unknown"', "unk17"), "ing17_unk")
d_ = fresh_state("fx17_unk3")
mm_ = (m_ing.alert_once(d_, "health_provenance", "", "x", t17), m_ing.alert_once(d_, "health_provenance", "", "x", t17 + 25 * 3600))
ok("mutation [commit-less key back to the constant 'unknown']: the 25 h later FAIL is dropped again (the regression test above would fail)", mm_ == (True, False), mm_)

# ---- 17b. health_provenance: a commit missing from a young export is a FIRST sighting, not a verdict
def sighting_file(st_):
    try:
        return json.load(open(os.path.join(st_, "staging_e2e_unlisted.json")))
    except (OSError, ValueError):
        return None
stub_ = Stub(commit=OTHER)
try:
    st_ = make_state("fx17_young", age=30)   # a fresh (30 s) export that lists only COMMIT, while staging already serves OTHER (a deploy created after the export)
    r1_ = E.run(stub_.base, ["health_provenance"], st_)
    v1_, d1_ = verdicts(r1_)["health_provenance"], cell_detail(r1_, "health_provenance")
    ok("young export, served commit missing from it (first sighting): UNVERIFIED (not FAIL), says it convicts only after a later export, result asks for a retry",
       v1_ == "UNVERIFIED" and "not in the deploy list yet" in d1_ and r1_["retry"] is True and r1_["partial"] is False, (v1_, d1_, r1_.get("retry")))
    ok("  ... the first sighting is remembered in state/staging_e2e_unlisted.json", set(sighting_file(st_) or {}) == {OTHER}, sighting_file(st_))
    r2_ = E.run(stub_.base, ["health_provenance"], st_)
    ok("  ... a second run on the SAME export (not taken after the sighting): still UNVERIFIED, the first-seen time is kept", verdicts(r2_)["health_provenance"] == "UNVERIFIED" and r2_["retry"] is True, verdicts(r2_))
    json.dump({OTHER: time.time() - 100}, open(os.path.join(st_, "staging_e2e_unlisted.json"), "w"))   # first seen 100 s ago; the export below is 30 s old = taken AFTER it
    r3_ = E.run(stub_.base, ["health_provenance"], st_)
    v3_, d3_ = verdicts(r3_)["health_provenance"], cell_detail(r3_, "health_provenance")
    ok("  ... an export taken AFTER the first sighting that still lacks the commit: FAIL, retry cleared", v3_ == "FAIL" and "still missing from an export taken after" in d3_ and r3_["retry"] is False, (v3_, d3_))
    write_export(st_, [(OTHER, 20, "SUCCESS"), (COMMIT, 5000, "SUCCESS")], age=1)
    r4_ = E.run(stub_.base, ["health_provenance"], st_)
    ok("  ... once the export lists the commit as the latest SUCCESS it PASSes and the sighting is forgotten", verdicts(r4_)["health_provenance"] == "PASS" and not (sighting_file(st_) or {}).get(OTHER), (verdicts(r4_), sighting_file(st_)))
finally:
    stub_.stop()
def first_sighting(mod):
    stub2_ = Stub(commit=OTHER)
    try:
        st2_ = make_state("fx17_young_m", age=30)
        r_ = mod.run(stub2_.base, ["health_provenance"], st2_)
        return verdicts(r_)["health_provenance"], r_["retry"]
    finally:
        stub2_.stop()
m_ = run_mut(mutated_copy(RUNNER, 'if first < now - d["age_s"]:', 'if True:', "unl17a"), "unl17a")
ok("mutation [the first sighting convicts again = the old behaviour]: a fast deploy inside the young window is a FALSE FAIL (the first-sighting test would fail)", first_sighting(m_)[0] == "FAIL", first_sighting(m_))
m_ = run_mut(mutated_copy(RUNNER, '        ctx.retry = True\n', '        pass\n', "unl17b"), "unl17b")
ok("mutation [no retry requested]: the unlisted commit would count as covered for 6 h (the retry assertion would fail)", first_sighting(m_) == ("UNVERIFIED", False), first_sighting(m_))
# run.sh: a retry result is never recorded as 'covered'
stub_ = Stub()
bx17 = make_box("box17", stub_url=stub_.base)
json.dump({"repo": "iptv_apps", "fetched_at": time.time() - 30, "deployments": [{"id": "dep00099", "status": "SUCCESS", "createdAt": iso(time.time() - 3600), "meta": {"commitHash": OTHER}}]},
          open(os.path.join(bx17, "state", "staging_deploys", "iptv_apps.json"), "w"))
p = run_sh(bx17)
rj = json.load(open(os.path.join(bx17, "state", "staging_e2e_box.json")))
ok("run.sh, served commit not in the young export: the result carries retry=true and deploy_commit is cleared (not recorded as covered)", rj.get("retry") is True and rj["deploy_commit"] is None
   and {c["cell"]: c["verdict"] for c in rj["cells"]}["health_provenance"] == "UNVERIFIED", (p.stdout, rj.get("retry"), rj.get("deploy_commit")))
p = run_sh(bx17)
ok("  ... and the next cron tick runs again instead of skipping 'nothing new'", "run: last result was inconclusive" in p.stdout, p.stdout)
stub_.stop()
sh_mut = os.path.join(bx17, "qa", "staging_e2e_run_mut.sh")
open(sh_mut, "w").write(open(os.path.join(QA, "staging_e2e_run.sh")).read().replace('if not conclusive or d.get("retry") or d.get("partial"):', 'if not conclusive:'))
stub_ = Stub()
open(os.path.join(bx17, "state", "staging_url_iptv_apps"), "w").write(stub_.base + "\n")
json.dump({"repo": "iptv_apps", "fetched_at": time.time() - 30, "deployments": [{"id": "dep00099", "status": "SUCCESS", "createdAt": iso(time.time() - 3600), "meta": {"commitHash": OTHER}}]},
          open(os.path.join(bx17, "state", "staging_deploys", "iptv_apps.json"), "w"))
os.remove(os.path.join(bx17, "state", "staging_e2e_unlisted.json")) if os.path.exists(os.path.join(bx17, "state", "staging_e2e_unlisted.json")) else None
p = run_sh(bx17, {"QA_E2E_FORCE": "1"}, script=sh_mut)
rj = json.load(open(os.path.join(bx17, "state", "staging_e2e_box.json")))
ok("mutation [run.sh ignores retry/partial]: the retry result would be recorded as covered (deploy_commit set)", rj.get("retry") is True and rj["deploy_commit"] == OTHER, (rj.get("retry"), rj.get("deploy_commit")))
stub_.stop()

# ---- 17c. docs/QA_GOLD_SET.md G10 text matches the proxy-passthrough logic
GOLD_MD = first_existing(os.path.join(OQ, "..", "..", "docs", "QA_GOLD_SET.md"))
OLD_G10 = "route (derived from staging's `/openapi.json`) with the access token ONLY in the `token` query parameter: HTTP 401/403 = FAIL (that is exactly what the web player and Roku saw\nafter `7d87fbd1`), anything else = auth accepted = PASS; with no token at all the proxy must answer 401/403.\n"
def g10_doc_ok(txt):
    i_ = txt.find("## G10 live check")
    sec_ = txt[i_:i_ + 4000] if i_ >= 0 else ""
    return all(k in sec_ for k in ("Upstream returned", "UNVERIFIED", "Stream not found", "FAIL")) and "anything else = auth accepted = PASS" not in sec_
if GOLD_MD:
    gtxt = open(GOLD_MD).read()
    ok("QA_GOLD_SET.md 'G10 live check': 401/403 = FAIL only when it is not the origin passthrough; passthrough = auth passed; 404 'Stream not found' / 5xx = UNVERIFIED", g10_doc_ok(gtxt))
    ok("  ... the previous wording ('anything else = auth accepted = PASS') no longer satisfies the check", not g10_doc_ok("## G10 live check\n\n" + OLD_G10))
else:
    print("  SKIP: docs/QA_GOLD_SET.md not present next to this tree (box scratch copy): G10 doc check skipped")

# ---- 17d. runner location: not found is loud, and the destination is one documented path
bx_nf = make_box("box17nf", runner_in_box=False)
shutil.rmtree(os.path.join(bx_nf, "scripts"), ignore_errors=True)
box_script = os.path.join(bx_nf, "qa", "staging_e2e_run.sh")
p = run_sh(bx_nf, {}, script=box_script)
rj = json.load(open(os.path.join(bx_nf, "state", "staging_e2e_box.json"))) if os.path.exists(os.path.join(bx_nf, "state", "staging_e2e_box.json")) else {}
ok("box without scripts/qa/e2e (the real box today): exit 0, log names the exact destination and the mkdir, result file = harness UNVERIFIED 'runner not found at <OVN_DIR>/scripts/qa/e2e/...'",
   p.returncode == 0 and ("%s/scripts/qa/e2e/chickadee_staging_e2e.py" % bx_nf) in rj.get("cells", [{}])[0].get("detail", "") and ("mkdir -p %s/scripts/qa/e2e" % bx_nf) in p.stdout
   and rj["cells"][0]["verdict"] == "UNVERIFIED", (p.stdout, rj))
for i_ in range(3):
    json.dump(dict(rj, ts=iso(t17 + i_ * 3600 - 3 * 3600)), open(os.path.join(bx_nf, "state", "staging_e2e_box.json"), "w"))
    ing_run(bx_nf + "/state", t17 + i_ * 3600 - 3 * 3600 + 60)
ok("  ... three such hourly results trip the 'no usable evidence' alert, so a missing runner can no longer stay silent", any("box e2e source gave NO usable evidence for 3" in l for l in alerts_of(bx_nf + "/state")), alerts_of(bx_nf + "/state"))
open(os.path.join(bx_nf, "qa", "staging_e2e_run_mut.sh"), "w").write(open(box_script).read().replace('  post 127 "runner not found', '  true "runner not found'))
os.remove(os.path.join(bx_nf, "state", "staging_e2e_box.json"))
p = run_sh(bx_nf, {}, script=os.path.join(bx_nf, "qa", "staging_e2e_run_mut.sh"))
ok("mutation [runner-not-found result removed = the old silent skip]: nothing is written (the loud-failure test would fail)", not os.path.exists(os.path.join(bx_nf, "state", "staging_e2e_box.json")), p.stdout)

# ---- 17e. the runner honours its own deadline
class FW:
    def __init__(self, t):
        self.t, self.timeouts = t, []
    def wall(self):
        return self.t
def client17(fw, **kw):
    c_ = E.Client("http://127.0.0.1:1", interval=kw.pop("interval", 0), timeout=20.0, wall=fw.wall, **kw)
    def fake_open(req, timeout=None):
        fw.timeouts.append(timeout)
        fw.t += 30
        raise urllib.error.URLError(ConnectionRefusedError())
    c_._open = fake_open
    return c_
fw = FW(900.0)
c_ = client17(fw)
c_.deadline, c_.hard = 1000.0, 1120.0
c_.request("GET", "/a")
fw.t = 990.0
c_.request("GET", "/b")
fw.t = 999.97
try:
    c_.request("GET", "/c")
    raised_ = False
except E.BudgetExceeded as ex:
    raised_ = "deadline" in str(ex)
ok("Client deadline: every request timeout is min(timeout, time left); once less than 0.05 s is left no request is sent (BudgetExceeded 'deadline exceeded', cut flag set)",
   fw.timeouts == [20.0, 10.0] and raised_ and c_.cut is True, (fw.timeouts, raised_, c_.cut))
fw.t = 1010.0
c_.request("DELETE", "/x", cleanup=True)
fw.t = 1115.0
c_.request("DELETE", "/y", cleanup=True)
fw.t = 1119.99
try:
    c_.request("DELETE", "/z", cleanup=True)
    raised2_ = False
except E.BudgetExceeded:
    raised2_ = True
ok("Client deadline: cleanup requests keep working past the deadline (own grace until `hard`) with a bounded timeout, then stop", fw.timeouts[2:] == [20.0, 5.0] and raised2_, (fw.timeouts, raised2_))
fw = FW(0.0)
c_ = client17(fw, interval=1.0)
c_.clock = lambda: fw.t
c_.sleep = lambda w: (sl_.append(w), setattr(fw, "t", fw.t + w))
sl_ = []
c_.deadline = 10.0
c_.request("GET", "/a")            # the fake origin takes 30 s: the deadline is long gone
try:
    c_.request("GET", "/b")
    thr_ = False
except E.BudgetExceeded:
    thr_ = True
ok("Client deadline: a request past the deadline is refused BEFORE the 1 req/s throttle sleeps", thr_ and sl_ == [], (thr_, sl_))
fw = FW(0.0)
c_ = client17(fw, interval=1.0)
c_.clock = lambda: fw.t
sl_ = []
c_.sleep = lambda w: (sl_.append(w), setattr(fw, "t", fw.t + w))
def quick_open(req, timeout=None):
    fw.timeouts.append(timeout)
    fw.t += 0.2
    raise urllib.error.URLError(ConnectionRefusedError())
c_._open = quick_open
c_.deadline = 1.0
c_.request("GET", "/a")            # t = 0.2: the throttle would wait 0.8 s = exactly what is left; it is cut to what is left minus 0.1 s so the request can still be sent
c_.request("GET", "/b")
ok("Client deadline: the 1 req/s throttle wait never eats the whole time left (0.8 s wait cut to 0.7 s) and the last request still goes out with a 0.1 s timeout",
   len(sl_) == 1 and abs(sl_[0] - 0.7) < 1e-9 and len(fw.timeouts) == 2 and abs(fw.timeouts[1] - 0.1) < 1e-9, (sl_, fw.timeouts))
E.TERM["at"] = 2000.0
fw = FW(2005.0)
c_ = client17(fw)
c_.deadline, c_.hard = 9999.0, 9999.0
try:
    try:
        c_.request("GET", "/a")
        r_term = "sent"
    except E.BudgetExceeded as ex:
        r_term = str(ex)
    c_.request("DELETE", "/c", cleanup=True)
    fw.t = 2021.0
    try:
        c_.request("DELETE", "/d", cleanup=True)
        r_term2 = "sent"
    except E.BudgetExceeded:
        r_term2 = "refused"
finally:
    E.TERM["at"] = None
ok("after SIGTERM: no new cell request starts, cleanup requests get TERM_CLEANUP_S (20 s) in total (the 20 s are over at t=2021: refused)", "SIGTERM" in r_term and fw.timeouts == [15.0] and r_term2 == "refused", (r_term, fw.timeouts, r_term2))

def deadline_run(mod):
    off = {"v": 0.0}
    seen = []
    stub_ = Stub()
    try:
        cl_ = mod.Client(stub_.base, interval=0, timeout=20.0, wall=lambda: time.time() + off["v"])
        real_open = cl_._open
        def slow_open(req, timeout=None):
            seen.append((timeout, cl_.remaining(req.get_method() == "DELETE")))
            off["v"] += 30.0
            return real_open(req, timeout=timeout)
        cl_._open = slow_open
        os.environ["QA_E2E_DEADLINE_S"] = "160"
        try:
            res_ = mod.run(stub_.base, ["auth_login", "playback_token"], make_state("fx17dl"), client=cl_)
        finally:
            os.environ.pop("QA_E2E_DEADLINE_S")
        return res_, seen, stub_.streams.copy(), len(stub_.requests)
    finally:
        stub_.stop()
res_, seen_, left_, nreq_ = deadline_run(E)
vv_ = verdicts(res_)
ok("run() under a slow staging (30 s per request, deadline 160 s): the deadline cuts the remaining requests, cells report UNVERIFIED 'deadline exceeded', result partial=true, nothing left on staging",
   vv_["auth_login"] == "PASS" and vv_["playback_token"] == "UNVERIFIED" and "deadline exceeded" in cell_detail(res_, "playback_token") and res_["partial"] is True and res_["terminated"] is False
   and nreq_ == 7 and not left_ and res_["cleanup"] == {"attempted": 1, "failed": 0}, (vv_, cell_detail(res_, "playback_token"), nreq_, left_, res_["cleanup"]))
ok("  ... every request timeout was bounded by the time left (the 6th had 10 s, not 20 s)", all(t <= max(0.1, rem) + 0.05 for t, rem in seen_) and min(t for t, _ in seen_) < 11.0 and max(t for t, _ in seen_) <= 20.0, seen_)
m_ = run_mut(mutated_copy(RUNNER, "timeout = self.timeout if rem is None else max(0.1, min(self.timeout, rem))", "timeout = self.timeout", "dl17a"), "dl17a")
_r, s2_, _l, _n = deadline_run(m_)
ok("mutation [per-request timeout not bounded by the time left]: the 6th request would wait 20 s with 10 s left (the bounded-timeout assertion fails)", not all(t <= max(0.1, rem) + 0.05 for t, rem in s2_), s2_)
m_ = run_mut(mutated_copy(RUNNER, "        rem = self.remaining(cleanup)\n        if rem is not None and rem <= 0.05:", "        rem = self.remaining(cleanup)\n        if False:", "dl17b"), "dl17b")
r2_, _s, _l, n2_ = deadline_run(m_)
ok("mutation [deadline not checked between requests]: the 7th request goes out and the run is not partial (the deadline assertion fails)", n2_ != 7 or r2_["partial"] is False, (n2_, r2_["partial"]))

# ---- 17f. SIGTERM: stop the cells, clean up, still write a (partial) result
def term_run(runner_path):
    stub_ = Stub(hang="proxy")
    st_ = make_state("fx17term")
    out_ = os.path.join(T, "fx17term_out.json")
    if os.path.exists(out_):
        os.remove(out_)
    env_ = dict(os.environ, QA_E2E_ALLOW_LOCAL="1", QA_E2E_MIN_INTERVAL_S="0", QA_E2E_REREAD_WAIT_S="0", QA_STATE_DIR=st_)
    proc = subprocess.Popen([PY, runner_path, "--base", stub_.base, "--state-dir", st_, "--cells", "auth_login,playback_token,vod_catalog", "--out", out_], env=env_,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        started = stub_.hanging.wait(60)            # handshake: the runner is blocked inside the ?token= request, its stream already created
        if started:
            proc.send_signal(signal.SIGTERM)
        try:
            so_, se_ = proc.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            proc.kill()
            so_, se_ = proc.communicate()
        data_ = json.load(open(out_)) if os.path.exists(out_) else None
        return started, proc.returncode, data_, stub_.streams.copy(), so_ + se_
    finally:
        stub_.release.set()
        if proc.poll() is None:
            proc.kill()
        stub_.stop()
started_, rc_, data_, left_, txt_ = term_run(RUNNER)
vv_ = {c["cell"]: (c["verdict"], c["detail"]) for c in (data_ or {}).get("cells", [])}
ok("SIGTERM while a cell waits on staging: exit 0 and a result IS written; finished cells keep their verdict, the interrupted and later cells are UNVERIFIED 'terminated', terminated/partial = true",
   started_ and rc_ == 0 and data_ is not None and data_["terminated"] is True and data_["partial"] is True and vv_.get("auth_login", ("",))[0] == "PASS"
   and vv_.get("playback_token", ("", ""))[0] == "UNVERIFIED" and "terminated" in vv_["playback_token"][1] and vv_.get("vod_catalog", ("", ""))[0] == "UNVERIFIED" and "terminated" in vv_["vod_catalog"][1],
   (started_, rc_, vv_, txt_[-300:]))
ok("  ... the cleanup still ran: the owned qa-e2e-pb stream is gone from staging and the result counts the delete", data_ is not None and not left_ and data_["cleanup"] == {"attempted": 1, "failed": 0}, (left_, (data_ or {}).get("cleanup")))
m_path = mutated_copy(RUNNER, "        signal.signal(signal.SIGTERM, _on_term)", "        pass", "term17a")
started_, rc_, data_, left_, txt_ = term_run(m_path)
ok("mutation [no SIGTERM handler = the old runner]: the signal kills it mid-run, no result file, the stream is left on staging (the SIGTERM test would fail)", started_ and data_ is None and bool(left_) and rc_ != 0, (rc_, data_, left_))
m_path = mutated_copy(RUNNER, "    except (Terminated, KeyboardInterrupt):\n        terminated = True", "    except KeyboardInterrupt:\n        terminated = True", "term17b")
started_, rc_, data_, left_, txt_ = term_run(m_path)
ok("mutation [Terminated not caught]: the run dies with a traceback and writes no result (the SIGTERM test would fail)", started_ and data_ is None, (rc_, data_))

# ---- 17g. qa_timeout.py: SIGTERM first (opt-in), the wrapper passes the grace
QT = os.path.join(QA, "qa_timeout.py")
def qt_run(script, env_extra=None):
    d_ = os.path.realpath(tempfile.mkdtemp(prefix="qt17-", dir=T))
    marker = os.path.join(d_, "term")
    child = 'trap "echo term > %s; exit 0" TERM; while :; do sleep 0.05; done' % marker
    e_ = {k: v for k, v in os.environ.items() if k != "QA_TIMEOUT_TERM_GRACE_S"}
    e_.update(env_extra or {})
    p_ = subprocess.run([PY, script, "2", "sh", "-c", child], capture_output=True, text=True, env=e_, timeout=120)
    return p_.returncode, os.path.exists(marker)
ok("qa_timeout.py with QA_TIMEOUT_TERM_GRACE_S=5: the child gets SIGTERM first and runs its handler (marker written), exit 124", qt_run(QT, {"QA_TIMEOUT_TERM_GRACE_S": "5"}) == (124, True))
ok("qa_timeout.py default (grace unset): unchanged historical behaviour, SIGKILL at once (handler never runs), exit 124", qt_run(QT) == (124, False))
d_ = os.path.realpath(tempfile.mkdtemp(prefix="qt17b-", dir=T))
p_ = subprocess.run([PY, QT, "2", "sh", "-c", 'trap "" TERM; while :; do sleep 0.05; done'], capture_output=True, text=True, env=dict(os.environ, QA_TIMEOUT_TERM_GRACE_S="1"), timeout=120)
ok("qa_timeout.py: a child that ignores SIGTERM is SIGKILLed once the grace is over (exit 124, no hang)", p_.returncode == 124)
ok("mutation [SIGTERM step removed from qa_timeout.py]: the child never sees SIGTERM (the grace test would fail)", qt_run(mutated_copy(QT, "        if grace > 0:", "        if False:", "qt17"), {"QA_TIMEOUT_TERM_GRACE_S": "5"}) == (124, False))
# run.sh passes the grace, so a hung runner leaves a PARTIAL result instead of a SIGKILL
bx_t = make_box("box17t", runner_in_box=False)
fake = os.path.join(bx_t, "fake_runner.py")
open(fake, "w").write(
    "import importlib.util, json, signal, sys, time\n"
    "spec = importlib.util.spec_from_file_location('real', %r)\nreal = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(real)\nload_deploy = real.load_deploy\n"
    "if __name__ == '__main__':\n"
    "    out = sys.argv[sys.argv.index('--out') + 1]\n"
    "    def h(sig, frm):\n"
    "        json.dump({'ts': time.strftime('%%Y-%%m-%%dT%%H:%%M:%%SZ', time.gmtime()), 'base': None, 'staging_commit': None, 'deploy_commit': 'x', 'terminated': True, 'partial': True,\n"
    "                   'cells': [{'cell': 'health_provenance', 'verdict': 'PASS', 'ms': 1, 'detail': 'ok'}]}, open(out, 'w'))\n"
    "        sys.exit(0)\n"
    "    signal.signal(signal.SIGTERM, h)\n"
    "    while True:\n        time.sleep(0.05)\n" % RUNNER)
p = run_sh(bx_t, {"QA_E2E_RUNNER": fake, "QA_E2E_TIMEOUT_S": "3", "QA_E2E_KILL_GRACE_S": "10"})
rj = json.load(open(os.path.join(bx_t, "state", "staging_e2e_box.json")))
ok("run.sh: a runner that outlives qa_timeout gets SIGTERM first and its PARTIAL result is kept (cell PASS preserved, terminated=true, deploy_commit cleared so the next tick retries)",
   p.returncode == 0 and rj["cells"][0]["cell"] == "health_provenance" and rj.get("terminated") is True and rj["deploy_commit"] is None, (p.stdout, rj))
open(os.path.join(bx_t, "qa", "staging_e2e_run_mut.sh"), "w").write(open(os.path.join(QA, "staging_e2e_run.sh")).read().replace('QA_TIMEOUT_TERM_GRACE_S="${QA_E2E_KILL_GRACE_S:-30}" ', ""))
p = run_sh(bx_t, {"QA_E2E_RUNNER": fake, "QA_E2E_TIMEOUT_S": "3", "QA_E2E_FORCE": "1"}, script=os.path.join(bx_t, "qa", "staging_e2e_run_mut.sh"))
rj = json.load(open(os.path.join(bx_t, "state", "staging_e2e_box.json")))
ok("mutation [run.sh does not ask for the SIGTERM grace]: the runner is SIGKILLed and only a harness-error result remains (the partial-result test would fail)", rj["cells"][0]["cell"] == "harness", rj)

# ---- 17h. ingest: the box runner without credentials is not silent
CREDS_CELLS = [{"cell": "health_provenance", "verdict": "PASS", "ms": 1, "detail": "ok"},
               {"cell": "auth_login", "verdict": "UNVERIFIED", "ms": 1, "detail": "premium credentials not provisioned (env QA_E2E_PREMIUM_* or state/qa_creds/iptv_apps.json); free credentials not provisioned"},
               {"cell": "ssrf_refusal", "verdict": "UNVERIFIED", "ms": 1, "detail": "premium account login did not succeed (absent)"}]
d_ = fresh_state("fx17_creds")
json.dump({"ts": iso(t17 - 100), "staging_commit": COMMIT, "cells": CREDS_CELLS}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t17)
al_ = [l for l in alerts_of(d_) if "canonical credentials" in l]
ok("box result whose auth_login says 'credentials not provisioned' (health_provenance still PASS): ONE alert naming state/qa_creds/iptv_apps.json", len(al_) == 1 and "qa_creds/iptv_apps.json" in al_[0] and "2 of 3" in al_[0], alerts_of(d_))
json.dump({"ts": iso(t17 - 50), "staging_commit": COMMIT, "cells": CREDS_CELLS}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t17 + 10)
json.dump({"ts": iso(t17 + 25 * 3600 - 50), "staging_commit": COMMIT, "cells": CREDS_CELLS}, open(os.path.join(d_, "staging_e2e_box.json"), "w"))
ing_run(d_, t17 + 25 * 3600)
ok("  ... not again the same UTC day, again the next day", len([l for l in alerts_of(d_) if "canonical credentials" in l]) == 2, alerts_of(d_))
d_ = fresh_state("fx17_creds2")
json.dump({"ts": iso(t17 - 100), "staging_commit": COMMIT, "passed": 0, "total": 0, "failed": ["harness-error"], "cells": CREDS_CELLS}, open(os.path.join(d_, "qa_staging_e2e.json"), "w"))
ing_run(d_, t17)
ok("  ... only for the box source (the Mac lifecycle has its own alerts)", not [l for l in alerts_of(d_) if "canonical credentials" in l], alerts_of(d_))
def creds_alert_count(script):
    d2 = fresh_state("fx17_creds_m")
    json.dump({"ts": iso(time.time() - 100), "staging_commit": COMMIT, "cells": CREDS_CELLS}, open(os.path.join(d2, "staging_e2e_box.json"), "w"))
    cli_ingest(script, d2)
    return len([l for l in alerts_of(d2) if "canonical credentials" in l])
ok("sanity: the unmutated ingest alerts once for missing credentials", creds_alert_count(REAL_ING) == 1)
ok("mutation [credentials alert call removed]: the missing creds file stays silent (the credentials test would fail)",
   creds_alert_count(ingest_dir('        if creds_alert_once(state_d, src["source"], res["details"]["cells"], now):', '        if False:', "cr17")) == 0)

shutil.rmtree(T, ignore_errors=True)
print("%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
