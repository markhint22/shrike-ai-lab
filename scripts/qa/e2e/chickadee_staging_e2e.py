#!/usr/bin/env python3
"""chickadee_staging_e2e.py - live-staging e2e v2 for Chickadee (iptv_apps): named cells, stdlib HTTP only, runs on the GPU BOX (no Mac-sleep dependency).

  python3 chickadee_staging_e2e.py [--base URL] [--state-dir DIR] [--cells a,b,...] [--out FILE] [--list-cells] [--budget N] [--timeout S]

WHY: the SSRF guard, /api/referrals, /api/vod, the rate-limit key/middleware and the ?token= playback fix (gold row G10) reached prod with no live check; the only
live check was the 17-cell RevenueCat lifecycle on a sleeping Mac. This runner gives the promote gate (qa/promote_gate.py, shadow) live evidence per staging commit.

CELLS (default run, in this order): health_provenance, auth_login, ssrf_refusal, playback_token, referral_flow, vod_catalog, rate_limit_sanity.
`revenuecat_lifecycle` (scripts/qa/rc_lifecycle_e2e.py) is a registered cell too but needs the Railway CLI, so it only runs on the Mac (qa-staging-e2e.sh) or by
`--cells revenuecat_lifecycle`; it is NOT part of the box run and its ~40 requests are outside this runner's budget.
Cell result: {cell, verdict, ms, detail}. Verdicts: PASS | FAIL | NA | UNVERIFIED (same vocabulary as qa_common; FLAG is only produced when results are aggregated).
  FAIL        only an HTTP response that contradicts the cell's expectation (a private-IP import accepted, ?token= playback 401, a second referral redeem accepted, ...)
  UNVERIFIED  anything infrastructural: no response (refused / timeout / DNS), 502/503/504 from Railway's edge, 429 outside the rate cell, credentials not provisioned
              or REJECTED (401/403 on a canonical login = test data, check state/qa_creds), budget/deadline exhausted, openapi unavailable, a login that did not succeed,
              a /health commit that differs from an export older than 2 min (the Mac export lags deploys; re-read once after QA_E2E_REREAD_WAIT_S, default 5 s),
              a served commit that is NOT in the deploy export at its FIRST sighting (a fast build can switch over inside the snapshot's first minutes): remembered in
              state/staging_e2e_unlisted.json, result `retry: true` (qa/staging_e2e_run.sh repeats next tick); FAIL only if an export taken after that sighting still lacks it,
              a proxy answer that is neither our auth rejection nor evidence that auth passed (404 'Stream not found', 5xx). NEVER FAIL.
              Exception that IS a verdict: an app-generated 502/504 (JSON `detail`) on an SSRF probe = the server tried the outbound fetch = FAIL.
              playback_token: the proxy re-raises the origin's status ('Upstream returned N for stream'), so 401/403 only fails the cell when it is NOT that passthrough.
  NA          the route the cell exercises is absent from staging's /openapi.json, or the referral flow cannot run because email verification is required and the
              staging override REFERRAL_REQUIRE_VERIFIED_EMAIL=false is not set. Never a fake PASS.
ROUTES ARE DERIVED, not remembered: every path / body field / query parameter comes from staging's public /openapi.json fetched at run start (verified against the
repo router at origin/develop when this runner was written: streams.py import/relay/xtream/proxy, referrals.py, vod.py, auth.py).

SAFETY
  * Host guard: the base URL host must contain "staging", not "production", and end with .up.railway.app (credentials are sent there). Loopback only with
    QA_E2E_ALLOW_LOCAL=1 (tests). A refused base exits 2 BEFORE any request.
  * Request budget <= 80 per run (hard, incl. the openapi fetch; the last 8 are reserved for cleanup deletes) and <= 1 request/s per host (QA_E2E_MIN_INTERVAL_S
    may LOWER it for loopback hosts only - tests; a real host is always >= 1 s). No redirects are followed. Response bodies are read at most 64 KiB (the openapi document: 4 MiB).
  * SSRF probes use LITERAL private IPs only (127.0.0.1, 169.254.169.254, [::1], 10.0.0.1) and a bad scheme: a working guard refuses them without any outbound fetch.
  * Credentials: env QA_E2E_{FREE,PREMIUM}_{EMAIL,PASSWORD} or state/qa_creds/iptv_apps.json (must be mode 600; {"premium": {"email","password"}, "free": {...}};
    a flat {"email","password"} is the premium account, which is what qa/staging_smoke.py stores). Absent => the cells that need them are UNVERIFIED. Only the two
    canonical staging accounts are ever used for logins; any user a cell creates is named qa-e2e-* and deleted by the same run (cleanup runs in `finally`).
  * Redaction: every credential/token seen this run (and any JWT / bearer / password= / ?token= pattern) is scrubbed from every detail, stdout and stderr; nothing
    secret is ever written to the output file. Request bodies are never logged.
TIME: the cells stop starting work after QA_E2E_DEADLINE_S (600 s) and every request's timeout is bounded by what is left of it (cells after it are UNVERIFIED 'run deadline
  exceeded'); cleanup deletes get QA_E2E_CLEANUP_GRACE_S (120 s) more. SIGTERM (qa_timeout sends it before its SIGKILL) stops the cells, runs the cleanup deletes for at most
  QA_E2E_TERM_CLEANUP_S (20 s) and still writes the result with `terminated: true` (unfinished cells UNVERIFIED), so the wrapper's 900 s kill never lands mid-run.
OUTPUT JSON {ts, base, staging_commit, deploy_commit, cells:[...], requests, request_budget, cell_requests, cleanup:{attempted, failed}, retry, partial, terminated}. staging_commit = the commit /health serves,
deploy_commit = latest SUCCESS commit of state/staging_deploys/iptv_apps.json (what qa/staging_e2e_run.sh compares to decide whether to run again).

DEPLOY (box): the runner lives at ~/overnight-queue/scripts/qa/e2e/chickadee_staging_e2e.py - the ONLY place qa/staging_e2e_run.sh looks (besides the repo tree and
QA_E2E_RUNNER). That directory does not exist by default: `ssh box 'mkdir -p ~/overnight-queue/scripts/qa/e2e'` first, then copy the file there.
FIRST RUN BY HAND (the lead, before the cron line): on the box, with state/qa_creds/iptv_apps.json in place,
    cd ~/overnight-queue && python3 scripts/qa/e2e/chickadee_staging_e2e.py --out /tmp/e2e_first.json
and record which cells came back PASS / NA / UNVERIFIED (referral_flow is NA until staging sets REFERRAL_REQUIRE_VERIFIED_EMAIL=false or auto-verifies test mail).
"""
import json
import os
import re
import secrets as _secrets
import signal
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = "iptv_apps"
DEFAULT_BASE = "https://chickadeestream-backend-staging.up.railway.app"
VERDICTS = ("PASS", "FAIL", "NA", "UNVERIFIED")
BOX_CELLS = ("health_provenance", "auth_login", "ssrf_refusal", "playback_token", "referral_flow", "vod_catalog", "rate_limit_sanity")
MAC_CELLS = ("revenuecat_lifecycle",)
ALL_CELLS = BOX_CELLS + MAC_CELLS
BUDGET = 80
CLEANUP_RESERVE = 8
MIN_INTERVAL_S = 1.0
GATEWAY = (502, 503, 504)
MAX_BODY = 65536
OPENAPI_MAX = 4 * 1024 * 1024   # staging serves a ~240 KB /openapi.json: the 64 KiB cap that protects against endless proxy bodies would truncate it
RATE_REQUESTS = 30
PRIVATE_TARGETS = ("http://127.0.0.1:1/", "http://169.254.169.254/", "http://[::1]/", "http://10.0.0.1/")
BAD_SCHEME = "file:///etc/"
DEADLINE_S = 600.0       # the cells stop starting work after this (QA_E2E_DEADLINE_S); the wrapper's hard kill (qa_timeout, 900 s) must stay AFTER deadline + cleanup grace
CLEANUP_GRACE_S = 120.0  # cleanup deletes (reserved budget) may run this long past the deadline (QA_E2E_CLEANUP_GRACE_S)
TERM_CLEANUP_S = 20.0    # after SIGTERM the cleanup deletes get this long (QA_E2E_TERM_CLEANUP_S): qa_timeout waits 30 s before its SIGKILL
SSRF_SUFFIX = {"import": "playlist.m3u", "relay": ""}  # import only fetches playlist-shaped URLs (is_m3u_url); a bare URL would be stored as a single stream


# ------------------------------------------------------------------------------------------------------------------------------- redaction
class Redactor:
    """Masks every secret registered with add() (plain, JSON-escaped and URL-quoted forms) plus well-known credential shapes."""
    PATTERNS = [
        (re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*"), "[jwt]"),
        (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}"), r"\1[redacted]"),
        (re.compile(r"(?i)([\"']?(?:password|passwd|secret|access_token|refresh_token|token|authorization)[\"']?\s*[:=]\s*[\"']?)[^\"'&\s,}]{3,}"), r"\1[redacted]"),
        (re.compile(r"([?&]token=)[^&\s\"']+"), r"\1[redacted]"),
    ]

    def __init__(self):
        self.secrets = []

    def add(self, v):
        if isinstance(v, str) and len(v) >= 4 and v not in self.secrets:
            self.secrets.append(v)
        return v

    def scrub(self, s):
        s = str(s)
        for sec in sorted(self.secrets, key=len, reverse=True):
            for form in (sec, json.dumps(sec)[1:-1], urllib.parse.quote(sec, safe=""), urllib.parse.quote_plus(sec)):
                if form:
                    s = s.replace(form, "***")
        for rx, rep in self.PATTERNS:
            s = rx.sub(rep, s)
        return s


# ------------------------------------------------------------------------------------------------------------------------------- http
class BudgetExceeded(Exception):
    pass


class Terminated(BaseException):
    """Raised by the SIGTERM handler inside the cell phase (BaseException: no `except Exception` in a cell can swallow it)."""


TERM = {"at": None, "armed": False, "raised": False}   # SIGTERM bookkeeping (module state: there is one handler per process)


def _on_term(signum, frame):
    if TERM["at"] is None:
        TERM["at"] = time.time()
    if TERM["armed"] and not TERM["raised"]:
        TERM["raised"] = True    # raise ONCE: the cleanup that follows must never be interrupted a second time
        raise Terminated()


def install_term_handler():
    """SIGTERM (what qa_timeout sends first) -> stop the cells, run the cleanup deletes, still write a partial result. Main thread only."""
    try:
        signal.signal(signal.SIGTERM, _on_term)
    except (ValueError, OSError):
        pass  # not the main thread / unsupported: the run simply keeps the deadline-only behaviour


class Resp:
    def __init__(self, status=0, headers=None, text="", err=""):
        self.status, self.headers, self.text, self.err = status, headers or {}, text, err

    def json(self):
        try:
            return json.loads(self.text)
        except ValueError:
            return None

    @property
    def infra(self):
        """No HTTP answer at all, or a gateway error: says nothing about the application."""
        return self.status == 0 or self.status in GATEWAY


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None  # a 3xx surfaces as an HTTPError: nothing is ever fetched on a server's say-so


def is_loopback(host):
    return (host or "").lower() in ("127.0.0.1", "localhost")


def effective_interval(host, env=None):
    """1 request/s per host. QA_E2E_MIN_INTERVAL_S may only LOWER it, and only for loopback hosts (tests); a real host is never faster than MIN_INTERVAL_S."""
    env = os.environ if env is None else env
    if is_loopback(host) and env.get("QA_E2E_MIN_INTERVAL_S", "") != "":
        try:
            return max(0.0, float(env["QA_E2E_MIN_INTERVAL_S"]))
        except ValueError:
            pass
    return MIN_INTERVAL_S


class Client:
    def __init__(self, base, budget=BUDGET, reserve=CLEANUP_RESERVE, interval=MIN_INTERVAL_S, timeout=20.0, sleep=time.sleep, clock=time.monotonic, wall=time.time):
        self.base = base.rstrip("/")
        self.wall = wall
        self.deadline = None   # epoch: no NEW cell request starts after it, and every request timeout is bounded by what is left (None = unbounded)
        self.hard = None       # epoch: the last moment a cleanup request may run
        self.cut = False       # True once a request was refused (or shortened to nothing) because the deadline / SIGTERM was reached
        self.budget, self.reserve, self.interval, self.timeout = budget, min(reserve, budget), interval, timeout
        self.sleep, self.clock = sleep, clock
        self.count, self.last = 0, None
        self.sleeps = []
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect)
        self._open = self.opener.open

    def remaining(self, cleanup=False):
        """Seconds this request may still take (None = unbounded). After SIGTERM cell requests get nothing and cleanup requests get TERM_CLEANUP_S in total."""
        if cleanup:
            cap = self.hard
            if TERM["at"] is not None:
                t = TERM["at"] + float(os.environ.get("QA_E2E_TERM_CLEANUP_S", TERM_CLEANUP_S))
                cap = t if cap is None else min(cap, t)
        else:
            if TERM["at"] is not None:
                return 0.0
            cap = self.deadline
        return None if cap is None else cap - self.wall()

    def request(self, method, path, body=None, headers=None, cleanup=False, max_body=MAX_BODY):
        limit = self.budget if cleanup else self.budget - self.reserve
        if self.count >= limit:
            raise BudgetExceeded("request budget %d exhausted" % self.budget)
        rem = self.remaining(cleanup)
        if rem is not None and rem <= 0.05:
            self.cut = True
            raise BudgetExceeded("run deadline exceeded" if TERM["at"] is None else "run terminated (SIGTERM)")
        if self.last is not None and self.interval > 0:
            wait = self.interval - (self.clock() - self.last)
            if wait > 0:
                if rem is not None:
                    wait = min(wait, max(0.0, rem - 0.1))
                self.sleeps.append(wait)
                self.sleep(wait)
                rem = self.remaining(cleanup)
                if rem is not None and rem <= 0.05:
                    self.cut = True
                    raise BudgetExceeded("run deadline exceeded" if TERM["at"] is None else "run terminated (SIGTERM)")
        timeout = self.timeout if rem is None else max(0.1, min(self.timeout, rem))
        self.count += 1
        self.last = self.clock()
        h = {"User-Agent": "qa-staging-e2e/2", "Accept": "application/json, */*"}
        h.update(headers or {})
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            h["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=h)
        try:
            r = self._open(req, timeout=timeout)
            try:
                raw = r.read(max_body)
            finally:
                r.close()
            return Resp(r.status, {k.lower(): v for k, v in r.headers.items()}, raw.decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            try:
                raw = e.read(max_body)
            except Exception:  # noqa: BLE001
                raw = b""
            return Resp(e.code, {k.lower(): v for k, v in (e.headers or {}).items()}, raw.decode("utf-8", "replace"))
        except urllib.error.URLError as e:
            return Resp(0, err=_err_kind(e.reason))
        except Exception as e:  # noqa: BLE001 - timeouts while reading, resets, http.client errors
            return Resp(0, err=_err_kind(e))


def _err_kind(ex):
    if isinstance(ex, socket.gaierror):
        return "dns"
    if isinstance(ex, ConnectionRefusedError):
        return "refused"
    if isinstance(ex, (socket.timeout, TimeoutError)):
        return "timeout"
    return "error"


def check_base(base):
    """Host guard. Raises ValueError (before any request) for anything that is not a Railway staging host (loopback only with QA_E2E_ALLOW_LOCAL=1)."""
    u = urllib.parse.urlparse(base)
    host = (u.hostname or "").lower()
    if os.environ.get("QA_E2E_ALLOW_LOCAL") == "1" and is_loopback(host):
        return host
    if u.scheme != "https" or "staging" not in host or "production" in host or not host.endswith(".up.railway.app"):
        raise ValueError("REFUSING %r: the e2e only ever talks to a Railway STAGING host (host must contain 'staging', end with .up.railway.app, be https)" % (host or base)[:80])
    return host


# ------------------------------------------------------------------------------------------------------------------------------- openapi
class OpenAPI:
    def __init__(self, doc):
        self.doc = doc if isinstance(doc, dict) else {}
        self.paths = self.doc.get("paths") if isinstance(self.doc.get("paths"), dict) else {}

    def _ref(self, node, depth=0):
        while isinstance(node, dict) and "$ref" in node and depth < 8:
            cur = self.doc
            for part in str(node["$ref"]).lstrip("#/").split("/"):
                cur = cur.get(part, {}) if isinstance(cur, dict) else {}
            node, depth = cur, depth + 1
        return node if isinstance(node, dict) else {}

    def op(self, method, path):
        o = (self.paths.get(path) or {}).get(method.lower())
        return o if isinstance(o, dict) else None

    def find(self, method, suffix):
        """The shortest published path ending in `suffix` that has `method` (shortest = the real router prefix, not a nested lookalike)."""
        c = sorted((p for p in self.paths if p.endswith(suffix) and self.op(method, p)), key=len)
        return c[0] if c else None

    def find_re(self, method, rx):
        c = sorted((p for p in self.paths if re.search(rx, p) and self.op(method, p)), key=len)
        return c[0] if c else None

    def body_schema(self, method, path):
        o = self.op(method, path) or {}
        content = ((o.get("requestBody") or {}).get("content") or {}).get("application/json") or {}
        return self._ref(content.get("schema") or {})

    def body_props(self, method, path):
        return set((self.body_schema(method, path).get("properties") or {}).keys())

    def body_required(self, method, path):
        return list(self.body_schema(method, path).get("required") or [])

    def query_params(self, method, path):
        o = self.op(method, path) or {}
        return {p.get("name"): bool(p.get("required")) for p in o.get("parameters", []) if isinstance(p, dict) and p.get("in") == "query"}

    def response(self, method, path):
        """-> (type, property names) of the first 2xx JSON response schema."""
        o = self.op(method, path) or {}
        for code, r in sorted((o.get("responses") or {}).items()):
            if str(code).startswith("2"):
                s = self._ref(((r or {}).get("content") or {}).get("application/json", {}).get("schema") or {})
                return s.get("type"), set((s.get("properties") or {}).keys())
        return None, set()


# ------------------------------------------------------------------------------------------------------------------------------- context
def state_dir_default():
    return os.environ.get("QA_STATE_DIR") or os.path.join(os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue"), "state")


def load_creds(state_dir, env=None):
    """-> ({"premium": (email, pw)|None, "free": ...}, note). Env wins over the file; the file must be mode 600."""
    env = os.environ if env is None else env
    out, note = {"premium": None, "free": None}, ""
    for acct in out:
        e, p = env.get("QA_E2E_%s_EMAIL" % acct.upper()), env.get("QA_E2E_%s_PASSWORD" % acct.upper())
        if e and p:
            out[acct] = (e, p)
    path = os.path.join(state_dir, "qa_creds", REPO + ".json")
    if os.path.exists(path) and not all(out.values()):
        try:
            if os.stat(path).st_mode & 0o077:
                note = "creds file %s is group/other accessible (must be mode 600): ignored" % os.path.basename(path)
            else:
                with open(path) as f:
                    j = json.load(f)
                if isinstance(j, dict):
                    cand = {"premium": j.get("premium") if isinstance(j.get("premium"), dict) else ({"email": j.get("email"), "password": j.get("password")} if j.get("email") else None),
                            "free": j.get("free") if isinstance(j.get("free"), dict) else None}
                    for acct, v in cand.items():
                        if not out[acct] and v and v.get("email") and v.get("password"):
                            out[acct] = (v["email"], v["password"])
        except (OSError, ValueError):
            note = "creds file unreadable"
    return out, note


def load_deploy(state_dir, now=None, max_age=None):
    """Latest staging deploy facts from the Mac export. -> dict(state, commit, latest_status, age_s): state ok | missing | stale | building | nosuccess."""
    now = time.time() if now is None else now
    max_age = float(os.environ.get("QA_STAGING_MAX_AGE_S", "1800")) if max_age is None else max_age
    try:
        with open(os.path.join(state_dir, "staging_deploys", REPO + ".json")) as f:
            j = json.load(f)
        age = now - float(j.get("fetched_at", 0))
        deps = [d for d in (j.get("deployments") or []) if isinstance(d, dict) and str(d.get("status", "")).upper() not in ("REMOVED", "SKIPPED")]
        deps.sort(key=lambda d: str(d.get("createdAt", "")), reverse=True)
        if not deps:
            return {"state": "missing", "commit": "", "latest_status": "", "age_s": age, "commits": set(), "success_created": None}
        latest = str(deps[0].get("status", "")).upper()
        succ = next((d for d in deps if str(d.get("status", "")).upper() == "SUCCESS"), None)
        commit = ((succ or {}).get("meta") or {}).get("commitHash") or (succ or {}).get("commit") or ""
        commit = str(commit).lower()
        listed = set()
        for d in deps:
            h = str(((d.get("meta") or {}).get("commitHash")) or d.get("commit") or "").lower()
            if h:
                listed.add(h)
        extra = {"commits": listed, "success_created": _iso_epoch((succ or {}).get("createdAt"))}
        if age > max_age:
            return dict({"state": "stale", "commit": commit, "latest_status": latest, "age_s": age}, **extra)
        if latest in ("BUILDING", "DEPLOYING", "INITIALIZING", "QUEUED", "WAITING", "NEEDS_APPROVAL"):
            return dict({"state": "building", "commit": commit, "latest_status": latest, "age_s": age}, **extra)
        if not succ or not commit:
            return dict({"state": "nosuccess", "commit": "", "latest_status": latest, "age_s": age}, **extra)
        return dict({"state": "ok", "commit": commit, "latest_status": latest, "age_s": age}, **extra)
    except (OSError, ValueError, TypeError, AttributeError):
        return {"state": "missing", "commit": "", "latest_status": "", "age_s": -1.0, "commits": set(), "success_created": None}


def _iso_epoch(v):
    """'2026-10-09T07:25:01.123Z' -> epoch seconds, None when unusable."""
    import calendar
    try:
        return float(calendar.timegm(time.strptime(str(v)[:19], "%Y-%m-%dT%H:%M:%S")))
    except (ValueError, TypeError, OverflowError):
        return None


class Ctx:
    def __init__(self, client, redactor, state_dir, creds, creds_note, deploy):
        self.c, self.R, self.state_dir, self.creds, self.creds_note, self.deploy = client, redactor, state_dir, creds, creds_note, deploy
        self.api = None            # OpenAPI (None = could not fetch)
        self.api_note = ""
        self.tokens = {}           # canonical account -> access token
        self.auth = {}             # canonical account -> ok | fail | unverified | absent
        self.health = None
        self.cleanups = []         # callables run (in reverse) after the cells, each wrapped
        self.retry = False         # a cell wants this run repeated at the next cron tick (health_provenance: unlisted commit seen for the first time)
        self.skipped = False       # a cell was skipped because the run deadline had passed
        self.ts = int(time.time())

    def bearer(self, tok):
        return {"Authorization": "Bearer " + tok}

    def snippet(self, resp, n=70):
        return self.R.scrub((resp.text or "").strip().replace("\n", " ")[:n])


def _http_desc(r):
    if r.status == 0:
        return "no response (%s)" % (r.err or "error")
    return "HTTP %d" % r.status


def infra_detail(r):
    return "%s (infrastructure, not a verdict)" % _http_desc(r)


def pick_token(ctx):
    """Premium preferred (stream import / VOD need it); free as a fallback. -> (name, token)|(None, None)."""
    for n in ("premium", "free"):
        if ctx.tokens.get(n):
            return n, ctx.tokens[n]
    return None, None


def need_token(ctx, prefer="premium"):
    """-> (token, None) or (None, (verdict, detail)) when the cell cannot run for lack of a login."""
    if ctx.tokens.get(prefer):
        return ctx.tokens[prefer], None
    st = ctx.auth.get(prefer, "absent")
    return None, ("UNVERIFIED", "%s account login did not succeed (%s)" % (prefer, st))


def openapi_or(ctx):
    if ctx.api is None:
        return ("UNVERIFIED", "openapi unavailable: %s" % ctx.api_note)
    return None


# ------------------------------------------------------------------------------------------------------------------------------- cells
EXPORT_FRESH_S = 120.0      # a mismatch is only a verdict against a deploy snapshot this young (the Mac export runs every ~10 min and may lag a fresh deploy)
SWITCHOVER_S = 600.0        # a served commit that IS in the list but is not the latest SUCCESS is only a FAIL once that latest deploy is older than this


def _same_commit(a, b):
    return bool(a) and bool(b) and (a == b or a.startswith(b) or b.startswith(a))


UNLISTED_FILE = "staging_e2e_unlisted.json"
UNLISTED_KEEP_S = 7 * 86400


def _unlisted_first_seen(state_dir, served, now):
    """Remember (state/staging_e2e_unlisted.json) when `served` was FIRST seen serving without being in the deploy export. -> that epoch (now on the first sighting).
    Best effort: an unwritable state dir just means every sighting is a first one (UNVERIFIED, never a false FAIL)."""
    path = os.path.join(state_dir, UNLISTED_FILE)
    try:
        with open(path) as f:
            seen = json.load(f)
        seen = seen if isinstance(seen, dict) else {}
    except (OSError, ValueError):
        seen = {}
    seen = {k: v for k, v in seen.items() if isinstance(v, (int, float)) and now - v < UNLISTED_KEEP_S}
    first = seen.get(served)
    if first is None:
        first = seen[served] = now
        try:
            with open(path + ".tmp", "w") as f:
                json.dump(seen, f, sort_keys=True)
            os.replace(path + ".tmp", path)
        except OSError:
            pass
    return first


def _unlisted_forget(state_dir, served):
    path = os.path.join(state_dir, UNLISTED_FILE)
    try:
        with open(path) as f:
            seen = json.load(f)
        if isinstance(seen, dict) and seen.pop(served, None) is not None:
            with open(path + ".tmp", "w") as f:
                json.dump(seen, f, sort_keys=True)
            os.replace(path + ".tmp", path)
    except (OSError, ValueError):
        pass


def provenance_mismatch(ctx, served):
    """/health serves a commit other than the latest SUCCESS deploy of the Mac export. -> (FAIL|UNVERIFIED|PASS, why).
    The export can lag a deploy by up to 30 min, so: re-read the snapshot once after a short wait; a match then is fine.
    A served commit that is NOT in the deploy list may simply be a deploy created after the export (a fast cached build can switch over inside the snapshot's first
    minutes), so the FIRST sighting is never a verdict: it is remembered (state/staging_e2e_unlisted.json), the result asks for a retry at the next cron tick (ctx.retry),
    and only an export taken AFTER that first sighting that still lacks the commit convicts (FAIL). A snapshot older than EXPORT_FRESH_S cannot convict a listed-but-older
    commit (UNVERIFIED 'export lags the deploy'); a listed commit that is not the latest SUCCESS is a FAIL once that latest deploy is older than SWITCHOVER_S."""
    wait = float(os.environ.get("QA_E2E_REREAD_WAIT_S", "5"))
    if wait > 0:
        ctx.c.sleep(wait)
    d = load_deploy(ctx.state_dir)
    ctx.deploy = d
    msg = "staging serves %s but the latest SUCCESS deploy is %s" % (served[:10], d["commit"][:10])
    if d["state"] != "ok":
        return "UNVERIFIED", "%s; after re-reading the export it is not usable (%s)" % (msg, d["state"])
    if _same_commit(served, d["commit"]):
        _unlisted_forget(ctx.state_dir, served)
        return "PASS", ""
    if not any(_same_commit(served, c) for c in d["commits"]):
        now = time.time()
        first = _unlisted_first_seen(ctx.state_dir, served, now)
        if first < now - d["age_s"]:    # the export was taken after we first saw this commit serving, and still does not list it
            return "FAIL", msg + " (not in the deploy list, still missing from an export taken after it was first seen serving)"
        ctx.retry = True
        lag = " export lags the deploy? (snapshot %d s old)." % d["age_s"] if d["age_s"] > EXPORT_FRESH_S else ""
        return "UNVERIFIED", "%s; the commit is not in the deploy list yet (a deploy newer than the export?).%s It convicts only if an export taken after this sighting still lacks it (retry next run)" % (msg, lag)
    if d["age_s"] > EXPORT_FRESH_S:
        return "UNVERIFIED", "%s; export lags the deploy? (snapshot %d s old, a verdict needs < %d s)" % (msg, d["age_s"], EXPORT_FRESH_S)
    created = d.get("success_created")
    if created is not None and time.time() - created < SWITCHOVER_S:
        return "UNVERIFIED", "%s; the latest SUCCESS deploy is only %d s old (traffic switch-over)" % (msg, time.time() - created)
    return "FAIL", msg + " (an older deploy is still serving)"


def cell_health_provenance(ctx):
    r = ctx.c.request("GET", "/health")
    if r.infra:
        return "UNVERIFIED", infra_detail(r)
    if r.status != 200:
        return "FAIL", "/health returned HTTP %d: %s" % (r.status, ctx.snippet(r))
    j = r.json()
    if not isinstance(j, dict):
        return "FAIL", "/health did not return a JSON object (content-type %s)" % r.headers.get("content-type", "?")
    ctx.health = j
    fails, unv, ok = [], [], []
    if j.get("status") != "healthy":
        fails.append("status=%r (want 'healthy')" % str(j.get("status"))[:30])
    else:
        ok.append("healthy")
    mig = j.get("migrations")
    if mig == "current":
        ok.append("migrations current")
    elif mig in (None, "unknown"):
        unv.append("migrations=%s (cannot tell whether the DB is at the alembic head)" % mig)
    else:
        fails.append("migrations=%r db_revision=%s alembic_head=%s" % (str(mig)[:30], str(j.get("db_revision"))[:40], str(j.get("alembic_head"))[:40]))
    served = str(j.get("commit") or "").lower()
    d = ctx.deploy
    if not re.fullmatch(r"[0-9a-f]{7,40}", served):
        unv.append("/health exposes no usable commit field")
    elif d["state"] != "ok":
        unv.append("no fresh deploy evidence to compare the served commit with (%s)" % d["state"])
    elif _same_commit(served, d["commit"]):
        _unlisted_forget(ctx.state_dir, served)
        ok.append("serves latest SUCCESS deploy %s" % served[:10])
    else:
        verdict, why = provenance_mismatch(ctx, served)
        if verdict == "PASS":
            ok.append("serves latest SUCCESS deploy %s (export caught up)" % served[:10])
        else:
            (fails if verdict == "FAIL" else unv).append(why)
    if fails:
        return "FAIL", "; ".join(fails)
    if unv:
        return "UNVERIFIED", "; ".join(unv) + (" | ok: " + ", ".join(ok) if ok else "")
    return "PASS", ", ".join(ok)


def cell_auth_login(ctx):
    bad = openapi_or(ctx)
    if bad:
        return bad
    login = ctx.api.find("post", "/auth/login")
    me = ctx.api.find("get", "/auth/me")
    if not login or not me:
        return "NA", "route %s absent from openapi" % ("/auth/login" if not login else "/auth/me")
    props = ctx.api.body_props("post", login)
    user_field = "email" if "email" in props or "username" not in props else "username"
    fails, unv, ok = [], [], []
    for acct in ("premium", "free"):
        cred = ctx.creds.get(acct)
        if not cred:
            ctx.auth[acct] = "absent"
            unv.append("%s credentials not provisioned (env QA_E2E_%s_* or state/qa_creds/%s.json)" % (acct, acct.upper(), REPO) + ((": " + ctx.creds_note) if ctx.creds_note else ""))
            continue
        r = ctx.c.request("POST", login, {user_field: cred[0], "password": cred[1]})
        if r.infra or r.status == 429:
            ctx.auth[acct] = "unverified"
            unv.append("%s login: %s" % (acct, infra_detail(r) if r.infra else "HTTP 429 (rate limited)"))
            continue
        if r.status in (401, 403):
            # a wrong / rotated password in state/qa_creds or janitor drift is a TEST-DATA problem, not a product verdict: a real login regression is caught by the
            # revenuecat_lifecycle cell (fresh user register + login) and by 200-without-token / 5xx below
            ctx.auth[acct] = "unverified"
            unv.append("%s login HTTP %d: credentials rejected, check state/qa_creds/%s.json (or the staging account was reset)" % (acct, r.status, REPO))
            continue
        j = r.json() if r.status == 200 else None
        tok = (j or {}).get("access_token") or (j or {}).get("token") if isinstance(j, dict) else None
        if r.status == 200 and tok:
            ctx.tokens[acct] = ctx.R.add(tok)
            ctx.auth[acct] = "ok"
            ok.append("%s login 200 + token" % acct)
        else:
            ctx.auth[acct] = "fail"
            fails.append("%s login HTTP %d%s" % (acct, r.status, "" if r.status != 200 else " without access_token"))
    anon = ctx.c.request("GET", me)
    if anon.infra:
        unv.append("anonymous %s: %s" % (me, infra_detail(anon)))
    elif anon.status in (401, 403):
        ok.append("anonymous %s -> %d" % (me, anon.status))
    else:
        fails.append("anonymous GET %s returned HTTP %d (want 401)" % (me, anon.status))
    if fails:
        return "FAIL", "; ".join(fails)
    if unv:
        return "UNVERIFIED", "; ".join(unv) + (" | ok: " + ", ".join(ok) if ok else "")
    return "PASS", ", ".join(ok)


def app_generated_error(r):
    """True when a 502/504 came from the APPLICATION (FastAPI HTTPException: a JSON object with a `detail`), not from Railway's edge ("Application failed to
    respond": no `detail`, or HTML). An app-made 502 on a private-IP probe means the server tried to fetch it (relay: connection refused -> 502)."""
    j = r.json()
    if not isinstance(j, dict) or "detail" not in j:
        return False
    return "failed to respond" not in str(j.get("detail", "")).lower()


def classify_refusal(r):
    """One SSRF probe: 'refused' (clean 4xx refusal) | 'accepted' (2xx/3xx or a job id: the guard is open) | 'error' (5xx/other 4xx) | 'unverified'."""
    if r.status in (502, 504) and app_generated_error(r):
        return "accepted"   # the app itself answered "Failed to fetch ...": it tried the outbound fetch, i.e. the guard did not stop a private target
    if r.infra:
        return "unverified"
    if r.status in (401, 429):
        return "unverified"
    body = (r.text or "")
    if r.status == 403 and "premium" in body.lower():
        return "unverified"
    if r.status < 400 or '"job_id"' in body:
        return "accepted"
    if r.status in (400, 403, 422):
        return "refused"
    return "error"


def cell_ssrf_refusal(ctx):
    bad = openapi_or(ctx)
    if bad:
        return bad
    tok, why = need_token(ctx, "premium")
    imp = ctx.api.find("post", "/streams/import")
    rel = ctx.api.find("get", "/streams/relay")
    xt = ctx.api.find("post", "/streams/import/xtream")
    probes = []  # (label, method, path, body)
    if imp and "url" in ctx.api.body_props("post", imp):
        for t in PRIVATE_TARGETS + (BAD_SCHEME,):
            probes.append(("import %s" % t, "POST", imp, {"url": t + SSRF_SUFFIX["import"]}))
    if rel and "url" in ctx.api.query_params("get", rel):
        for t in PRIVATE_TARGETS + (BAD_SCHEME,):
            probes.append(("relay %s" % t, "GET", rel + "?url=" + urllib.parse.quote(t + SSRF_SUFFIX["relay"], safe=""), None))
    if xt and "server_url" in ctx.api.body_props("post", xt):
        for t in PRIVATE_TARGETS[:2]:
            probes.append(("xtream %s" % t, "POST", xt, {"server_url": t.rstrip("/"), "username": "qa-e2e", "password": "qa-e2e-x"}))
    if not probes:
        return "NA", "import/relay/xtream routes (or their url/server_url fields) are absent from openapi"
    if why:
        return why
    counts = {"refused": 0, "accepted": 0, "error": 0, "unverified": 0}
    notes = []
    for label, method, path, body in probes:
        r = ctx.c.request(method, path, body, ctx.bearer(tok))
        k = classify_refusal(r)
        counts[k] += 1
        if k in ("accepted", "error"):
            notes.append("%s -> %s%s" % (label, _http_desc(r), (" " + ctx.snippet(r, 50)) if (k == "error" or r.status in GATEWAY) else ""))
    summary = "%d probes: %d refused, %d accepted, %d server error, %d unverified" % (len(probes), counts["refused"], counts["accepted"], counts["error"], counts["unverified"])
    if counts["accepted"] or counts["error"]:
        return "FAIL", summary + " | " + "; ".join(notes[:4])
    if counts["unverified"]:
        return "UNVERIFIED", summary
    return "PASS", summary


def upstream_passthrough(r):
    """The proxy re-raises the origin's 4xx/5xx verbatim (`Upstream returned N for stream`): the request already passed authentication and the stream lookup, so a
    401/403 here belongs to the THIRD-PARTY origin (the test stream points at example.com), not to our auth."""
    return "upstream returned" in (r.text or "").lower()


def is_auth_rejection(r):
    """Our own auth refusing the request: 401/403 that is not the upstream origin's status passed through (WWW-Authenticate: Bearer / 'Could not validate credentials')."""
    return r.status in (401, 403) and not upstream_passthrough(r)


def auth_passed(r):
    """Evidence that auth let the request through: a 2xx, or the origin's status passed through by the proxy handler. 404 'Stream not found', 5xx and other 4xx say nothing."""
    return (200 <= r.status < 300) or (not r.infra and r.status != 429 and upstream_passthrough(r))


def cell_playback_token(ctx):
    """Gold row G10: a player that cannot set headers sends ?token=<access token>; 7d87fbd1 made that a 401 for the web player and Roku."""
    bad = openapi_or(ctx)
    if bad:
        return bad
    proxy = ctx.api.find_re("get", r"/streams/\{[^}]+\}/proxy$")
    if not proxy:
        return "NA", "stream proxy route absent from openapi"
    if "token" not in ctx.api.query_params("get", proxy):
        return "NA", "%s has no ?token= query parameter in openapi" % proxy
    create = ctx.api.find("post", "/streams")
    delete = ctx.api.find_re("delete", r"/streams/\{[^}]+\}$")
    if not create or not delete or not {"name", "url"} <= ctx.api.body_props("post", create):
        return "NA", "stream create/delete routes (name,url) absent from openapi: no owned stream to proxy"
    tok, why = need_token(ctx, "premium")
    if why:
        return why
    r = ctx.c.request("POST", create, {"name": "qa-e2e-pb-%d" % ctx.ts, "url": "https://example.com/qa-e2e/live.m3u8"}, ctx.bearer(tok))
    if r.infra or r.status == 429:
        return "UNVERIFIED", "could not create the owned test stream: " + (infra_detail(r) if r.infra else "HTTP 429")
    sid = (r.json() or {}).get("id") if r.status in (200, 201) and isinstance(r.json(), dict) else None
    if sid is None:
        return "UNVERIFIED", "could not create the owned test stream: HTTP %d %s" % (r.status, ctx.snippet(r, 50))

    def drop():
        return ctx.c.request("DELETE", re.sub(r"\{[^}]+\}", str(sid), delete), headers=ctx.bearer(tok), cleanup=True).status
    ctx.cleanups.append(drop)
    path = re.sub(r"\{[^}]+\}", str(sid), proxy)
    with_tok = ctx.c.request("GET", path + "?token=" + urllib.parse.quote(tok, safe=""))
    if with_tok.infra or with_tok.status == 429:
        return "UNVERIFIED", "proxy ?token= request: " + (infra_detail(with_tok) if with_tok.infra else "HTTP 429")
    if is_auth_rejection(with_tok):
        return "FAIL", "GET %s with the access token in the token query parameter -> HTTP %d: rejected (web player / Roku playback broken; gold row G10)" % (proxy, with_tok.status)
    if not auth_passed(with_tok):
        return "UNVERIFIED", "proxy ?token= request gave HTTP %d %s: neither an auth rejection nor evidence that auth passed" % (with_tok.status, ctx.snippet(with_tok, 50))
    anon = ctx.c.request("GET", path)
    if anon.infra:
        return "UNVERIFIED", "anonymous proxy request: " + infra_detail(anon)
    if auth_passed(anon):
        return "FAIL", "anonymous GET %s returned HTTP %d (want 401/403): the proxy is open without a token" % (proxy, anon.status)
    if not is_auth_rejection(anon):
        return "UNVERIFIED", "anonymous proxy request gave HTTP %d %s: no clear auth rejection to compare with" % (anon.status, ctx.snippet(anon, 50))
    return "PASS", "access token in the token query parameter accepted (HTTP %d, auth passed), no token -> %d" % (with_tok.status, anon.status)


def cell_referral_flow(ctx):
    bad = openapi_or(ctx)
    if bad:
        return bad
    a = ctx.api
    reg, login = a.find("post", "/auth/register"), a.find("post", "/auth/login")
    create, redeem = a.find("post", "/referrals"), a.find("post", "/referrals/redeem")
    delacct = a.find("delete", "/account/me")
    missing = [n for n, p in (("register", reg), ("login", login), ("referrals", create), ("referrals/redeem", redeem), ("DELETE account/me", delacct)) if not p]
    if missing:
        return "NA", "route(s) absent from openapi: " + ", ".join(missing)
    extra = [f for f in a.body_required("post", reg) if f not in ("email", "username", "password")]
    if extra or "code" not in a.body_props("post", redeem):
        return "NA", "register requires fields %s / redeem has no `code` field: the flow cannot be driven generically" % (",".join(extra) or "-")
    reg_props = a.body_props("post", reg)
    users = {}

    def make(tag):
        email = "qa-e2e-%s-%d@example.com" % (tag, ctx.ts)
        pw = ctx.R.add("Qa-e2e-%s-aA1!" % _secrets.token_hex(8))
        ctx.R.add(email)
        body = {"email": email, "password": pw}
        if "username" in reg_props:
            body["username"] = "qae2e%s%d" % (tag, ctx.ts)
        r = ctx.c.request("POST", reg, body)
        if r.infra or r.status == 429:
            return None, "register %s: %s" % (tag, infra_detail(r) if r.infra else "HTTP 429 (rate limited)")
        if r.status not in (200, 201):
            return None, "register %s rejected: HTTP %d %s" % (tag, r.status, ctx.snippet(r, 50))
        verified = (r.json() or {}).get("email_verified") if isinstance(r.json(), dict) else None
        lg = ctx.c.request("POST", login, {"email": email, "password": pw})
        j = lg.json() if lg.status == 200 else None
        tok = (j or {}).get("access_token") if isinstance(j, dict) else None
        if not tok:
            return None, "login of the fresh %s user failed: %s (user %s is left behind)" % (tag, _http_desc(lg), "qa-e2e-" + tag)
        ctx.R.add(tok)

        def drop(tok=tok):
            return ctx.c.request("DELETE", delacct, headers=ctx.bearer(tok), cleanup=True).status
        ctx.cleanups.append(drop)
        return {"token": tok, "verified": bool(verified), "email": email}, ""

    for tag in ("a", "b"):
        u, why = make(tag)
        if not u:
            return "UNVERIFIED", why
        users[tag] = u
    ha, hb = ctx.bearer(users["a"]["token"]), ctx.bearer(users["b"]["token"])

    def rejected(r):
        return not r.infra and r.status != 429 and 400 <= r.status < 500

    codes = []
    for _ in range(2):
        r = ctx.c.request("POST", create, headers=ha)
        if r.infra or r.status == 429:
            return "UNVERIFIED", "create code: " + (infra_detail(r) if r.infra else "HTTP 429")
        j = r.json() if r.status in (200, 201) else None
        code = (j or {}).get("code") if isinstance(j, dict) else None
        if not code:
            return "FAIL", "POST %s -> HTTP %d without a code: %s" % (create, r.status, ctx.snippet(r, 50))
        ctx.R.add(code)
        codes.append(code)
    r1 = ctx.c.request("POST", redeem, {"code": codes[0]}, hb)
    if r1.infra or r1.status == 429:
        return "UNVERIFIED", "redeem: " + (infra_detail(r1) if r1.infra else "HTTP 429")
    if not (200 <= r1.status < 300):
        if rejected(r1) and not (users["a"]["verified"] and users["b"]["verified"]):
            return "NA", ("valid redeem rejected (HTTP %d) and the fresh test users are not email-verified: the staging override REFERRAL_REQUIRE_VERIFIED_EMAIL=false "
                          "is not set, so the flow cannot be exercised (never a fake PASS)" % r1.status)
        return "FAIL", "a valid referral redeem was rejected with HTTP %d although both users are verified" % r1.status
    r2 = ctx.c.request("POST", redeem, {"code": codes[0]}, hb)
    if r2.infra or r2.status == 429:
        return "UNVERIFIED", "second redeem: " + (infra_detail(r2) if r2.infra else "HTTP 429")
    if not rejected(r2):
        return "FAIL", "the SAME code was accepted twice by the same account (second redeem -> HTTP %d)" % r2.status
    r3 = ctx.c.request("POST", redeem, {"code": codes[1]}, ha)
    if r3.infra or r3.status == 429:
        return "UNVERIFIED", "self redeem: " + (infra_detail(r3) if r3.infra else "HTTP 429")
    if not rejected(r3):
        return "FAIL", "an account redeemed its OWN code (self redeem -> HTTP %d)" % r3.status
    return "PASS", "create 201 x2, redeem 200, second redeem -> %d, self redeem -> %d" % (r2.status, r3.status)


def cell_vod_catalog(ctx):
    bad = openapi_or(ctx)
    if bad:
        return bad
    vod = ctx.api.find("get", "/vod")
    if not vod:
        return "NA", "/api/vod absent from openapi"
    name, tok = pick_token(ctx)
    if not tok:
        return "UNVERIFIED", "no canonical account login succeeded (%s)" % (", ".join("%s=%s" % kv for kv in sorted(ctx.auth.items())) or "no credentials")
    typ, keys = ctx.api.response("get", vod)
    r = ctx.c.request("GET", vod, headers=ctx.bearer(tok))
    if r.infra or r.status == 429:
        return "UNVERIFIED", infra_detail(r) if r.infra else "HTTP 429"
    if r.status != 200:
        return "FAIL", "GET %s -> HTTP %d: %s" % (vod, r.status, ctx.snippet(r))
    j = r.json()
    if "json" not in r.headers.get("content-type", "json").lower() or not isinstance(j, dict):
        return "FAIL", "GET %s did not return a JSON object" % vod
    want = sorted(keys) if keys else []
    missing = [k for k in want if k not in j]
    if missing:
        return "FAIL", "catalog keys missing: %s (openapi promises %s)" % (",".join(missing), ",".join(want))
    if "items" in j and not isinstance(j["items"], list):
        return "FAIL", "catalog `items` is %s, not a list" % type(j["items"]).__name__
    note = "catalog keys %s" % ",".join(want or sorted(j)[:4])
    genres = ctx.api.find("get", vod.rstrip("/") + "/genres")
    if genres:
        g = ctx.c.request("GET", genres, headers=ctx.bearer(tok))
        if g.infra or g.status == 429:
            return "UNVERIFIED", "genres: " + (infra_detail(g) if g.infra else "HTTP 429")
        if g.status != 200:
            return "FAIL", "GET %s -> HTTP %d: %s" % (genres, g.status, ctx.snippet(g))
        if not isinstance(g.json(), list):
            return "FAIL", "GET %s did not return a list" % genres
        note += ", genres list of %d" % len(g.json())
    return "PASS", "200 JSON, " + note


HOT_ROUTES = (("/api/streams", "?limit=1"), ("/api/streams/categories", ""), ("/api/vod", ""), ("/api/vod/genres", ""), ("/api/subscription/status", ""),
              ("/api/profiles", ""), ("/api/auth/me", ""))


def cell_rate_limit_sanity(ctx):
    bad = openapi_or(ctx)
    if bad:
        return bad
    routes = [p + q for p, q in HOT_ROUTES if ctx.api.op("get", p)]
    if not routes:
        return "NA", "none of the hot read routes are in openapi"
    name, tok = pick_token(ctx)
    if not tok:
        return "UNVERIFIED", "no canonical account login succeeded"
    n429, retry_after, ok2xx, first429, other = 0, 0, 0, None, 0
    for i in range(RATE_REQUESTS):
        r = ctx.c.request("GET", routes[i % len(routes)], headers=ctx.bearer(tok))
        if r.status == 429:
            n429 += 1
            first429 = first429 or i + 1
        if "retry-after" in r.headers:
            retry_after += 1
        if 200 <= r.status < 300:
            ok2xx += 1
        elif r.status != 429:
            other += 1
    if n429 or retry_after:
        return "FAIL", "%d of %d sequential GETs over %d hot route(s) (<=1 req/s) returned 429 (first at request %s), %d carried retry-after" % (
            n429, RATE_REQUESTS, len(routes), first429 or "-", retry_after)
    if ok2xx < RATE_REQUESTS * 0.8:
        return "UNVERIFIED", "only %d of %d hot-route GETs succeeded (%d other statuses): cannot judge the limiter" % (ok2xx, RATE_REQUESTS, other)
    return "PASS", "%d GETs over %d route(s) at <=1 req/s: %d x 2xx, zero 429, no retry-after" % (RATE_REQUESTS, len(routes), ok2xx)


def cell_revenuecat_lifecycle(ctx):
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(here, ".."))
    try:
        import rc_lifecycle_e2e as rc
    except ImportError:
        return "UNVERIFIED", "rc_lifecycle_e2e.py not found next to the runner (Mac-only cell)"
    finally:
        sys.path.pop(0)
    cell = rc.revenuecat_lifecycle(ctx.c.base)
    return cell["verdict"], cell["detail"]


CELL_FUNCS = {"health_provenance": cell_health_provenance, "auth_login": cell_auth_login, "ssrf_refusal": cell_ssrf_refusal, "playback_token": cell_playback_token,
              "referral_flow": cell_referral_flow, "vod_catalog": cell_vod_catalog, "rate_limit_sanity": cell_rate_limit_sanity,
              "revenuecat_lifecycle": cell_revenuecat_lifecycle}
NEEDS_API = {"auth_login", "ssrf_refusal", "playback_token", "referral_flow", "vod_catalog", "rate_limit_sanity"}


def run_cell(ctx, name, deadline):
    t0, n0 = time.time(), ctx.c.count
    try:
        if time.time() > deadline:
            v, d = "UNVERIFIED", "run deadline exceeded before this cell started"
            ctx.skipped = True
        else:
            v, d = CELL_FUNCS[name](ctx)
    except BudgetExceeded as ex:
        v, d = "UNVERIFIED", str(ex)
    except Exception as ex:  # noqa: BLE001 - one broken cell never takes the run down, and never becomes a FAIL
        v, d = "UNVERIFIED", "cell crashed: %s" % type(ex).__name__
    if v not in VERDICTS:
        v, d = "UNVERIFIED", "cell returned an invalid verdict %r" % (v,)
    return {"cell": name, "verdict": v, "ms": int((time.time() - t0) * 1000), "detail": ctx.R.scrub(d)[:400]}, ctx.c.count - n0


def fetch_openapi(ctx):
    r = ctx.c.request("GET", "/openapi.json", max_body=OPENAPI_MAX)
    if r.infra:
        ctx.api_note = infra_detail(r)
        return
    j = r.json() if r.status == 200 else None
    if isinstance(j, dict) and isinstance(j.get("paths"), dict):
        ctx.api = OpenAPI(j)
    else:
        ctx.api_note = "GET /openapi.json -> HTTP %d without a paths document" % r.status


def run_cleanups(ctx):
    """Delete everything the cells created (reverse order). -> (attempted, failed). A delete counts as failed unless HTTP 200/204; the count is part of the result so a
    leftover qa-e2e-* user / stream is visible (best effort otherwise: the staging janitor handles leftovers)."""
    attempted = failed = 0
    for fn in reversed(ctx.cleanups):
        attempted += 1
        try:
            if fn() not in (200, 204):
                failed += 1
        except Exception:  # noqa: BLE001
            failed += 1
    ctx.cleanups = []
    return attempted, failed


def run(base, cells=None, state_dir=None, budget=BUDGET, timeout=20.0, interval=None, client=None, now=None):
    """Run the cells. -> result dict. Raises ValueError for a refused base (before any request)."""
    host = check_base(base)
    state_dir = state_dir or state_dir_default()
    R = Redactor()
    creds, note = load_creds(state_dir)
    for v in creds.values():
        for s in v or ():
            R.add(s)
    ctx = Ctx(client or Client(base, budget=budget, interval=effective_interval(host) if interval is None else interval, timeout=timeout), R, state_dir, creds, note,
              load_deploy(state_dir, now))
    names = [c for c in (cells or BOX_CELLS) if c in CELL_FUNCS]
    deadline = time.time() + float(os.environ.get("QA_E2E_DEADLINE_S", DEADLINE_S))
    if hasattr(ctx.c, "deadline"):    # every request timeout is bounded by what is left of the run; cleanup gets its own grace past the deadline
        ctx.c.deadline = deadline
        ctx.c.hard = deadline + float(os.environ.get("QA_E2E_CLEANUP_GRACE_S", CLEANUP_GRACE_S))
    results, per_cell, cleanup = [], {}, (0, 0)
    terminated = False
    TERM["armed"], TERM["raised"] = True, False
    try:
        if names and any(n in NEEDS_API for n in names):
            try:
                fetch_openapi(ctx)
            except BudgetExceeded as ex:
                ctx.api_note = str(ex)
        for n in names:
            if TERM["at"] is not None:
                break
            res, used = run_cell(ctx, n, deadline)
            results.append(res)
            per_cell[n] = used
    except (Terminated, KeyboardInterrupt):
        terminated = True
    finally:
        TERM["armed"] = False    # the cleanup below is never interrupted: SIGTERM only shortens its time budget (Client.remaining)
        cleanup = run_cleanups(ctx)
    terminated = terminated or TERM["at"] is not None
    for n in names:               # a SIGTERM leaves cells unfinished: report each honestly, never as PASS
        if terminated and n not in per_cell:
            results.append({"cell": n, "verdict": "UNVERIFIED", "ms": 0, "detail": "run terminated (SIGTERM) before this cell finished"})
    health = ctx.health or {}
    served = str(health.get("commit") or "").lower() or None
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "base": base, "staging_commit": served, "deploy_commit": ctx.deploy["commit"] or None,
            "cells": results, "requests": ctx.c.count, "request_budget": ctx.c.budget, "cell_requests": per_cell,
            "cleanup": {"attempted": cleanup[0], "failed": cleanup[1]}, "retry": bool(ctx.retry),
            "partial": bool(terminated or ctx.skipped or getattr(ctx.c, "cut", False)), "terminated": bool(terminated)}


def parse_args(argv):
    o = {"base": os.environ.get("QA_E2E_BASE", ""), "state-dir": "", "cells": "", "out": "", "budget": str(BUDGET), "timeout": "20"}
    flags = set()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            flags.add(a)
            i += 1
    return o, flags


def default_base(state_dir):
    try:
        with open(os.path.join(state_dir, "staging_url_" + REPO)) as f:
            u = f.read().split()[0]
        if u:
            return u
    except (OSError, IndexError):
        pass
    return DEFAULT_BASE


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    o, flags = parse_args(argv)
    if "--list-cells" in flags:
        print("\n".join(ALL_CELLS))
        return 0
    sd = o["state-dir"] or state_dir_default()
    base = o["base"] or default_base(sd)
    cells = [c for c in o["cells"].split(",") if c] or list(BOX_CELLS)
    unknown = [c for c in cells if c not in CELL_FUNCS]
    if unknown:
        sys.stderr.write("unknown cell(s): %s (known: %s)\n" % (",".join(unknown), ",".join(ALL_CELLS)))
        return 2
    try:
        budget = max(1, min(BUDGET, int(o["budget"])))
        timeout = max(0.1, min(60.0, float(o["timeout"])))
    except ValueError:
        sys.stderr.write("bad --budget/--timeout\n")
        return 2
    install_term_handler()
    try:
        res = run(base, cells, sd, budget, timeout)
    except ValueError as ex:
        sys.stderr.write("%s\n" % ex)
        return 2
    text = json.dumps(res, sort_keys=True)
    if o["out"]:
        tmp = o["out"] + ".tmp"
        with open(tmp, "w") as f:
            f.write(text + "\n")
        os.replace(tmp, o["out"])
        for c in res["cells"]:
            print("%-20s %-10s %5dms  %s" % (c["cell"], c["verdict"], c["ms"], c["detail"][:140]))
        print("requests %d/%d, cleanup %d deletes (%d failed), staging commit %s" % (res["requests"], res["request_budget"], res["cleanup"]["attempted"], res["cleanup"]["failed"],
                                                                              (res["staging_commit"] or "?")[:10]))
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
