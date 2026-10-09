#!/usr/bin/env python3
"""contract_fuzz.py - QA-N2: hermetic Schemathesis contract fuzz of a release candidate (SHADOW only; see qa/contract_fuzz.README.md).

    python3 qa/contract_fuzz.py check --repo <name> [--ref <sha|ref>] [--no-record] [--accept-baseline]

Deliberately NOT named gate_*.py: qa_run_shadow.sh runs every gate_*.py after every hygiene merge and a fuzz run takes minutes. This runs
nightly from qa/contract_fuzz_cron.sh and has no enforce path.

What it adds: runtime input-handling evidence (5xx on odd input, responses that violate their declared schema) that the diff-structural
gates cannot give (class of the billwatch /api/alerts 500-since-May and the civic-router 404 P0s).

Hermetic by construction (shared staging, rate limits and outbound SSRF-style fetches are never touched):
  * the candidate ref is checked out in a detached worktree (qa_common.worktree) and started with the repo's OWN venv python, on
    127.0.0.1:<free port>, with a scrubbed environment: SQLite file DB in a temp dir, RATE_LIMIT_ENABLED=false, dummy secrets, every
    outbound-service key blank (the repo's own test-suite bootstrap; the app creates its schema in its lifespan exactly as the tests do);
  * the app runs behind a launcher that blocks every non-loopback connect()/DNS lookup made through Python's socket module and records the
    attempt (blocked_outbound in the verdict). It serves with the stdlib asyncio loop (never uvloop, whose connect/getaddrinfo run in C and
    would bypass the guard). This is a defence in depth, not a sandbox: a native extension with its own sockets would bypass it, so the
    exclude list below (and the `ss -tunap` check in the README) remain the primary protection;
  * routes that fetch URLs / proxy / send mail / call payment stores are excluded from the fuzz (config table below, count in the verdict);
  * the process group is killed and the temp dirs removed in `finally`.
Verdicts: PASS (no signature outside the accepted baseline) | FLAG (new signature, or no baseline yet) | NA (repo not configured / kill switch) |
UNVERIFIED (could not run: no venv, app did not start, schemathesis missing/crashed/timeout). Never FAIL (shadow). Exit code is always 0.
Bodies and tokens are never printed: only METHOD path_template [check] status-or-error-class signatures, counts and redacted log tails.
"""
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

GATE = "contract_fuzz"
SEED = 42
CHECKS = "not_a_server_error,response_schema_conformance"   # 5xx + schema conformance only: no negative_data_rejection, no ignored_auth
PHASES = "examples,fuzzing"                                  # no coverage phase (systematic negative data), no stateful phase
SIG_CAP = 300                                                # signatures stored in details (a first-run row can be long)

# ------------------------------------------------------------------------------------------------ configuration table
# Keyed by repo. Paths: `venv_python` candidates are relative to the LIVE CLONE (the worktree has no venv; an absolute path is allowed);
# `app_dir` is relative to the clone root and to the worktree. `env` values may use {tmp} (the per-run temp dir). Everything here is
# NON-SECRET placeholder data. `exclude_paths` is (regex searched in the OpenAPI path template, reason).
REPOS = {
    "iptv_apps": {
        "clone": "iptv_apps",
        "app_dir": "iptv-backend",
        "venv_python": [".venv/bin/python", "venv/bin/python"],       # same order as iptv_apps/.ovn-verify.sh
        "app": "app.main:app",
        "openapi_path": "/openapi.json",
        "env": {
            "DATABASE_URL": "sqlite:///{tmp}/fuzz.db",               # tests: sqlite + Base.metadata.create_all; the app's lifespan runs init_db() itself
            "RATE_LIMIT_ENABLED": "false",
            "ENVIRONMENT": "development",
            "JWT_SECRET_KEY": "contract-fuzz-dummy-jwt-secret-0123456789",
            "ADMIN_SECRET": "contract-fuzz-dummy-admin-secret",
            "METRICS_TOKEN": "contract-fuzz-dummy-metrics-token",
            "REVENUECAT_WEBHOOK_SECRET": "",
            "STRIPE_SECRET_KEY": "", "STRIPE_WEBHOOK_SECRET": "", "SENDGRID_API_KEY": "", "TMDB_API_KEY": "", "YOUTUBE_API_KEY": "",
            "SENTRY_DSN": "", "REVENUECAT_API_KEY": "", "APPLE_SHARED_SECRET": "", "GOOGLE_SERVICE_ACCOUNT_JSON": "", "FCM_SERVICE_ACCOUNT_JSON": "",
            "APNS_AUTH_KEY": "", "ENABLE_HEALTH_CHECKS": "false",
        },
        "auth": {
            "register": {"path": "/api/auth/register", "json": {"email": "contract-fuzz@example.com", "username": "contractfuzz", "password": "FuzzPass-123456"}},
            "login": {"path": "/api/auth/login", "json": {"email": "contract-fuzz@example.com", "password": "FuzzPass-123456"}, "token_field": "access_token"},
        },
        "exclude_paths": [
            (r"^/api/streams/import", "fetches remote playlists / Xtream servers"),
            (r"^/api/streams/relay$", "relays a caller-supplied URL"),
            (r"^/api/streams/\{stream_id\}/proxy$", "proxies a stream URL"),
            (r"^/api/streams/\{stream_id\}/check$", "probes a stream URL"),
            (r"^/api/streams/sources/\{source_id\}/refresh$", "re-fetches a source playlist"),
            (r"^/api/epg/sources/\{source_id\}/(refresh|auto-map)$", "fetches an XMLTV URL"),
            (r"^/api/discover/", "fetches the remote iptv-org catalog / YouTube"),
            (r"^/api/discovery/channels/add$", "YouTube lookups"),
            (r"^/api/admin/youtube", "YouTube lookups"),
            (r"^/api/content/identify$", "TMDB lookups"),
            (r"^/api/subscription/(apple|google)/", "store receipt verification calls Apple/Google"),
            (r"^/api/subscription/stripe/(checkout|portal)$", "Stripe API"),
            (r"^/api/subscription/cancel$", "Stripe/RevenueCat API"),
            (r"^/api/auth/password/forgot$", "sends mail"),
            (r"^/api/auth/resend-verification-email$", "sends mail"),
            (r"^/api/feedback$", "sends mail"),
            (r"^/api/account/me$", "deletes the throwaway user whose token the run uses"),
            (r"^/api/auth/email$", "changes the throwaway user's email (invalidates its token)"),
        ],
    },
}


def config(repo):
    """The configuration for `repo` or None. OVN_FUZZ_CONFIG_JSON (a path to a JSON object {repo: cfg}) adds/overrides entries (tests, trials);
    exclude_paths there may be plain regex strings or [regex, reason] pairs."""
    table = dict(REPOS)
    extra = os.environ.get("OVN_FUZZ_CONFIG_JSON")
    if extra:
        with open(extra) as f:
            table.update(json.load(f))
    cfg = table.get(repo)
    if cfg is None:
        return None
    cfg = dict(cfg)
    cfg["exclude_paths"] = [(e, "") if isinstance(e, str) else (e[0], e[1] if len(e) > 1 else "") for e in cfg.get("exclude_paths", [])]
    return cfg


# ------------------------------------------------------------------------------------------------ helpers
def env_int(name, default):
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


_REDACT_PATTERNS = [
    re.compile(r"eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*"),                      # JWT
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{6,}"),
    re.compile(r"(?i)((?:authorization|api[_-]?key|x-api-key|secret|token|password|passwd|dsn)[\"']?\s*[:=]\s*[\"']?)[^\s\"',;&]+"),
    re.compile(r"(://)[^@/\s:]+(?::[^@/\s]*)?@"),                                                 # URL userinfo
]
_SECRETISH_KEY = re.compile(r"(?i)SECRET|TOKEN|PASSWORD|PASSWD|KEY|DSN|CREDENTIAL|URL")


def secrets_from(cfg_env, extra=()):
    """Literal strings that must never reach output: every secret-looking config env value (and given extras such as the bearer token)."""
    out = set()
    for k, v in (cfg_env or {}).items():
        if v and _SECRETISH_KEY.search(k) and len(v) >= 4:
            out.add(v)
    for v in extra:
        if v and len(v) >= 4:
            out.add(v)
    return out


def redact(text, secrets=(), limit=300):
    """Scrub known literal secrets and credential-shaped substrings, collapse whitespace, keep the tail."""
    text = text or ""
    for s in sorted(secrets, key=len, reverse=True):
        text = text.replace(s, "***")
    for i, rx in enumerate(_REDACT_PATTERNS):
        if i == 2:
            text = rx.sub(lambda m: m.group(1) + "***", text)
        elif i == 3:
            text = rx.sub(r"\1***@", text)
        else:
            text = rx.sub("***", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[-limit:] if len(text) > limit else text


def tail_file(path, nbytes=4000):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - nbytes))
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def free_port():
    for _ in range(5):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 0))
            return s.getsockname()[1]
    raise RuntimeError("no free port")


_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # never through an ambient proxy: loopback only


def http(method, url, body=None, headers=None, timeout=10):
    """(status, bytes) over loopback; an HTTP error status is returned, a connection problem raises OSError."""
    data = json.dumps(body).encode() if body is not None else None
    h = {"Content-Type": "application/json", "Accept": "application/json"}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with _OPENER.open(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except urllib.error.URLError as e:
        raise OSError(str(e.reason))


def sweep_group(proc):
    """SIGKILL stragglers in the process group of `proc` right after its exit was observed (a leader that died on its own, e.g. the app crashing).
    Only call this at the moment the exit is seen: a long-reaped leader's pid may have been recycled by an unrelated process."""
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGKILL)     # start_new_session => pgid == the leader's pid, recorded at spawn, never re-resolved
    except (ProcessLookupError, PermissionError, OSError):
        pass


def kill_group(proc, grace=5):
    """Terminate the whole process group of `proc` (started with start_new_session), SIGKILL after `grace`s, and reap it.
    A leader that is already gone (reaped) is NOT signalled any more: its pid may belong to an unrelated process by now (use sweep_group
    at the moment the exit is observed to kill stragglers)."""
    if proc is None or proc.poll() is not None:
        return
    pgid = proc.pid                             # start_new_session guarantees pgid == pid; never re-resolved via getpgid
    for sig, wait in ((signal.SIGTERM, grace), (signal.SIGKILL, 10)):
        try:
            os.killpg(pgid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass
        t_end = time.time() + wait
        while time.time() < t_end:
            if proc.poll() is not None:
                sweep_group(proc)               # leader just reaped: children that ignored TERM
                return
            time.sleep(0.05)
    try:
        proc.wait(timeout=5)
    except Exception:  # noqa: BLE001
        pass


def find_schemathesis():
    cands = [os.environ.get("OVN_FUZZ_SCHEMATHESIS"), os.path.expanduser("~/qa-venv/bin/schemathesis"), shutil.which("schemathesis")]
    for c in cands:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


# ------------------------------------------------------------------------------------------------ launcher run INSIDE the repo's venv python
# Installs the outbound guard BEFORE importing the app, checks the app really comes from the worktree (a venv with an editable install of the
# live clone would otherwise fuzz the wrong code), then serves it with uvicorn on loopback.
LAUNCHER = r'''
import errno, importlib, ipaddress, os, socket, sys
sys.path.insert(0, os.getcwd())
# c-ares (aiodns/pycares) resolves in native code, outside any Python-level socket guard: make `import aiodns` fail so aiohttp falls back to
# the thread resolver (socket.getaddrinfo), which the guard below covers.
# uvloop does connect()/getaddrinfo in libuv (C): the Python-level patches below never run under it, so it must not be importable either
# (uvicorn's loop="auto" would pick it; the explicit loop="asyncio" below is the second line).
for _m in ("aiodns", "pycares", "uvloop"):
    sys.modules[_m] = None
_log = os.environ.get("OVN_FUZZ_GUARD_LOG")


def _note(kind, host):
    try:
        with open(_log, "a") as f:
            f.write("%s %s\n" % (kind, host))
    except Exception:
        pass


def _local(host):
    if host is None or host in ("", "localhost", "localhost.localdomain"):
        return True
    if isinstance(host, bytes):
        host = host.decode("ascii", "replace")
    try:
        ip = ipaddress.ip_address(str(host).split("%")[0])
        return ip.is_loopback or ip.is_unspecified
    except ValueError:
        return False


_connect, _connect_ex, _gai, _gbn = socket.socket.connect, socket.socket.connect_ex, socket.getaddrinfo, socket.gethostbyname
_sendto, _sendmsg = socket.socket.sendto, socket.socket.sendmsg


def _is_blocked(sock, address):
    return sock.family in (socket.AF_INET, socket.AF_INET6) and isinstance(address, tuple) and address and not _local(address[0])


def connect(self, address):
    if _is_blocked(self, address):
        _note("connect", address[0])
        raise ConnectionRefusedError(errno.ECONNREFUSED, "outbound connection blocked by contract_fuzz guard")
    return _connect(self, address)


def connect_ex(self, address):
    if _is_blocked(self, address):
        _note("connect", address[0])
        return errno.ECONNREFUSED
    return _connect_ex(self, address)


def sendto(self, data, *args):
    if args and _is_blocked(self, args[-1]):
        _note("udp", args[-1][0])
        raise ConnectionRefusedError(errno.ECONNREFUSED, "outbound datagram blocked by contract_fuzz guard")
    return _sendto(self, data, *args)


def sendmsg(self, buffers, *args):
    if len(args) >= 3 and _is_blocked(self, args[2]):
        _note("udp", args[2][0])
        raise ConnectionRefusedError(errno.ECONNREFUSED, "outbound datagram blocked by contract_fuzz guard")
    return _sendmsg(self, buffers, *args)


def getaddrinfo(host, *a, **k):
    if not _local(host):
        _note("dns", host)
        raise socket.gaierror(socket.EAI_NONAME, "outbound DNS blocked by contract_fuzz guard")
    return _gai(host, *a, **k)


def gethostbyname(host):
    if not _local(host):
        _note("dns", host)
        raise socket.gaierror(socket.EAI_NONAME, "outbound DNS blocked by contract_fuzz guard")
    return _gbn(host)


socket.socket.connect, socket.socket.connect_ex, socket.getaddrinfo, socket.gethostbyname = connect, connect_ex, getaddrinfo, gethostbyname
socket.socket.sendto, socket.socket.sendmsg = sendto, sendmsg

spec, port = sys.argv[1], int(sys.argv[2])
modname, _, attr = spec.partition(":")
mod = importlib.import_module(modname)
root = os.path.realpath(os.getcwd())
if not os.path.realpath(getattr(mod, "__file__", "") or "").startswith(root + os.sep):
    sys.stderr.write("contract_fuzz launcher: %s was imported from outside the worktree (%s)\n" % (modname, getattr(mod, "__file__", "?")))
    sys.exit(3)
import uvicorn
uvicorn.run(getattr(mod, attr or "app"), host="127.0.0.1", port=port, log_level="warning", access_log=False, loop="asyncio")
'''


# ------------------------------------------------------------------------------------------------ report parsing
_SERVER_SIDE_ERROR = re.compile(r"(?i)timeout|connection|reset|protocol|chunked|disconnect|closed|eof|incomplete|broken")


def parse_ndjson(path):
    """Parse a schemathesis 4.x NDJSON event report (--report ndjson) into
    {"signatures": sorted ["METHOD /path [check] class", ...], "complete": bool, "stop_reason": str|None, "operations_total": int|None,
     "operations_selected": int|None, "version": str|None, "seed": int|None, "scenarios": int}.
    class = the response status code for not_a_server_error, "<FailureType>@<status>" for other check failures (response_schema_conformance:
    JsonSchemaError@201); a request that raised becomes "METHOD /path [network_error] <ExceptionType>". Bodies/headers are never read into the result."""
    sigs, out = set(), {"complete": False, "stop_reason": None, "operations_total": None, "operations_selected": None, "version": None, "seed": None,
                        "scenarios": 0, "client_errors": 0}
    with open(path, "rb") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                ev = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if not isinstance(ev, dict) or len(ev) != 1:
                continue
            kind, body = next(iter(ev.items()))
            if not isinstance(body, dict):
                continue
            if kind == "Initialize":
                out["version"], out["seed"] = body.get("schemathesis_version"), body.get("seed")
            elif kind == "LoadingFinished":
                st = (body.get("statistic") or {}).get("operations") or {}
                out["operations_total"], out["operations_selected"] = st.get("total"), st.get("selected")
            elif kind == "EngineFinished":
                out["complete"], out["stop_reason"] = body.get("stop_reason") == "completed", body.get("stop_reason")
            elif kind == "ScenarioFinished":
                out["scenarios"] += 1
                rec = body.get("recorder") or {}
                label = str(rec.get("label") or "")
                m = re.match(r"^([A-Z]+)\s+(\S+)", label)
                if not m:
                    continue
                method, path_t = m.group(1), m.group(2)
                interactions = rec.get("interactions") or {}
                for case_id, checks in (rec.get("checks") or {}).items():
                    status = ((interactions.get(case_id) or {}).get("response") or {}).get("status_code")
                    for chk in checks or []:
                        if chk.get("status") != "failure":
                            continue
                        name = str(chk.get("name"))
                        ftype = (((chk.get("failure_info") or {}).get("failure")) or {}).get("type") or "failure"
                        cls = str(status) if name == "not_a_server_error" else "%s@%s" % (ftype, status if status is not None else "?")
                        sigs.add("%s %s [%s] %s" % (method, path_t, name, cls))
            elif kind == "NonFatalError":
                # a request that raised. Server-indicative types (timeout, reset, protocol error...) are signatures; client-side ones (the HTTP
                # library refusing to SEND a generated header/URL: InvalidHeader, InvalidURL, UnicodeEncodeError...) are only counted.
                val = body.get("value") or {}
                etype = str(val.get("type") or "error")
                m = re.match(r"^([A-Z]+)\s+(\S+)", str(body.get("label") or ""))
                if _SERVER_SIDE_ERROR.search(etype):
                    sigs.add("%s [network_error] %s" % ("%s %s" % (m.group(1), m.group(2)) if m else "-", etype))
                else:
                    out["client_errors"] += 1
    out["signatures"] = sorted(sigs)
    return out


# ------------------------------------------------------------------------------------------------ baseline
def baseline_path(repo):
    return os.path.join(qc.state_dir(), "qa_shadow", "contract_fuzz_baseline_%s.json" % repo)


def load_baseline(repo):
    try:
        with open(baseline_path(repo)) as f:
            b = json.load(f)
        if isinstance(b, dict) and isinstance(b.get("signatures"), list):
            return b
    except (OSError, ValueError):
        pass
    return None


def write_baseline(repo, ref, sha, fingerprint, signatures):
    path = baseline_path(repo)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".cf_baseline.", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as f:
            json.dump({"schema": 1, "repo": repo, "accepted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "ref": ref, "sha": sha,
                       "fingerprint": fingerprint, "signatures": sorted(signatures)}, f, indent=1, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def fuzz_args(seed, max_ex, mode, req_timeout, patterns):
    """The schemathesis flags that decide WHICH requests are made (everything except spec path, url, report dir and credentials).
    The fingerprint hashes exactly this list, so a drift between the constants and the command that really runs is detected."""
    args = ["--seed", str(seed), "-n", str(max_ex), "-w", "1", "--checks", CHECKS, "--phases", PHASES, "--mode", mode,
            "--generation-deterministic", "--no-shrink",          # deterministic implies no example database
            "--no-color", "--request-timeout", str(req_timeout), "--report", "ndjson"]
    if patterns:
        args += ["--exclude-path-regex", "|".join("(?:%s)" % p for p in patterns)]
    return args


def build_cmd(st_bin, spec_path, base, rep_dir, args, config_file=None):
    """Full schemathesis command line: nice/ionice prefix + run + the fuzz args. Credentials never appear here: the bearer token reaches
    schemathesis through `config_file` (headers = Authorization: Bearer ${FUZZ_TOKEN}) and the FUZZ_TOKEN environment variable, because argv is
    visible to every user in `ps`."""
    cmd = qc.cpu_prefix() + [st_bin]
    if config_file:
        cmd += ["--config-file", config_file]
    return cmd + ["run", spec_path, "--url", base] + list(args) + ["--report-dir", rep_dir]


TOKEN_CONFIG = 'headers = { Authorization = "Bearer ${FUZZ_TOKEN}" }\n'
_TRANSIENT_SIG = re.compile(r"^(\S+ \S+) \[network_error\] (?:ReadTimeout|ConnectTimeout|ConnectionError)$")


def retry_filter(transient_sigs):
    """`--include-name-regex` value matching exactly the operations (\"METHOD /path\") whose first pass ended in a timeout / connection error."""
    names = sorted({m.group(1) for m in (_TRANSIENT_SIG.match(x) for x in transient_sigs) if m})
    return "^(?:%s)$" % "|".join(re.escape(n) for n in names) if names else None


def fingerprint(params, excludes):
    """Fuzz parameters a signature set depends on. A baseline recorded under different ones is not comparable (UNVERIFIED, re-accept)."""
    blob = json.dumps({"p": params, "x": sorted(excludes)}, sort_keys=True)
    return hashlib.sha1(blob.encode()).hexdigest()[:16]


# ------------------------------------------------------------------------------------------------ the check
def parse_args(argv):
    a = {"repo": None, "ref": "origin/develop", "accept": False}
    i = 0
    while i < len(argv):
        x = argv[i]
        if x == "check":
            pass
        elif x == "--repo" and i + 1 < len(argv):
            i += 1
            a["repo"] = argv[i]
        elif x == "--ref" and i + 1 < len(argv):
            i += 1
            a["ref"] = argv[i]
        elif x == "--accept-baseline":
            a["accept"] = True
        i += 1
    return a


def check(argv):
    a = parse_args(argv)
    repo, ref = a["repo"] or "?", a["ref"]
    t0 = time.time()
    cap = max(5, env_int("OVN_FUZZ_TIMEOUT_S", 600))
    deadline = t0 + cap
    details = {"cap_s": cap}

    def V(v, summary, extra=None):
        d = dict(details)
        d.update(extra or {})
        return qc.verdict(v, GATE, repo, ref, summary, d, ms=int((time.time() - t0) * 1000))

    if os.environ.get("OVN_CONTRACT_FUZZ", "").lower() == "off":
        return V("NA", "disabled (OVN_CONTRACT_FUZZ=off)")
    cfg = config(repo)
    if cfg is None:
        return V("NA", "repo not configured")

    clone = qc.repo_dir(cfg["clone"])
    if not clone:
        return V("UNVERIFIED", "no clone of %s found" % cfg["clone"])
    py = None
    for cand in cfg["venv_python"]:
        p = cand if os.path.isabs(cand) else os.path.join(clone, cfg["app_dir"], cand)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            py = p
            break
    if not py:
        return V("UNVERIFIED", "no venv: none of %s exists under %s/%s" % (cfg["venv_python"], cfg["clone"], cfg["app_dir"]))
    st_bin = find_schemathesis()
    if not st_bin:
        return V("UNVERIFIED", "schemathesis missing (looked for ~/qa-venv/bin/schemathesis, OVN_FUZZ_SCHEMATHESIS, PATH)")
    if not qc.ensure_commits(clone, [ref], attempts=2, wait=5):
        return V("UNVERIFIED", "cannot resolve ref %s in %s" % (ref, cfg["clone"]))
    rc, sha, _ = qc.git(clone, "rev-parse", "--verify", "-q", ref + "^{commit}")
    sha = sha.strip() if rc == 0 else None
    details["sha"] = sha

    max_ex = env_int("OVN_FUZZ_MAX_EXAMPLES", 25)
    seed = env_int("OVN_FUZZ_SEED", SEED)
    req_timeout = env_int("OVN_FUZZ_REQUEST_TIMEOUT_S", 15)
    start_timeout = env_int("OVN_FUZZ_START_TIMEOUT_S", 60)
    mode_opt = os.environ.get("OVN_FUZZ_MODE", "all")
    if mode_opt not in ("all", "positive", "negative"):
        mode_opt = "all"
    patterns = [p for p, _ in cfg["exclude_paths"]]
    params = {"seed": seed, "max_examples": max_ex, "checks": CHECKS, "phases": PHASES, "mode": mode_opt, "schemathesis": None}
    app_proc = st_proc = None
    tmp = tempfile.mkdtemp(prefix="cfuzz-")
    secrets = secrets_from(cfg.get("env"))
    try:
        with qc.worktree(clone, ref) as wt:
            if wt is None:
                return V("UNVERIFIED", "could not create a worktree of %s at %s" % (cfg["clone"], ref))
            app_cwd = os.path.join(wt, cfg["app_dir"])
            if not os.path.isdir(app_cwd):
                return V("UNVERIFIED", "app dir %s does not exist at %s" % (cfg["app_dir"], ref))
            launcher = os.path.join(tmp, "_launcher.py")
            with open(launcher, "w") as f:
                f.write(LAUNCHER)
            guard_log = os.path.join(tmp, "outbound.log")
            app_log = os.path.join(tmp, "app.log")
            port = free_port()
            base = "http://127.0.0.1:%d" % port
            env = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": tmp, "LANG": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1",
                   "OVN_FUZZ_GUARD_LOG": guard_log}
            for k, v in (cfg.get("env") or {}).items():
                env[k] = str(v).replace("{tmp}", tmp)
            with open(app_log, "wb") as lf:
                app_proc = subprocess.Popen(qc.cpu_prefix() + [py, launcher, cfg["app"], str(port)], cwd=app_cwd, env=env, stdin=subprocess.DEVNULL,
                                            stdout=lf, stderr=subprocess.STDOUT, start_new_session=True)

            # ---- wait for the schema endpoint
            t_start = time.time()
            spec_bytes = None
            wait_until = min(deadline, t_start + start_timeout)
            while time.time() < wait_until:
                if app_proc.poll() is not None:
                    sweep_group(app_proc)
                    return V("UNVERIFIED", "app failed to start: exited rc=%s before serving %s: %s" %
                             (app_proc.returncode, cfg["openapi_path"], redact(tail_file(app_log), secrets)))
                try:
                    code, body = http("GET", base + cfg["openapi_path"], timeout=3)
                    if code == 200:
                        json.loads(body)
                        spec_bytes = body
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(0.3)
            if spec_bytes is None:
                why = "timeout" if time.time() >= deadline else "not ready"
                return V("UNVERIFIED", "app failed to start: %s after %ds waiting for %s: %s" %
                         (why, int(time.time() - t_start), cfg["openapi_path"], redact(tail_file(app_log), secrets)))
            details["startup_s"] = round(time.time() - t_start, 1)
            spec_path = os.path.join(tmp, "openapi.json")
            with open(spec_path, "wb") as f:
                f.write(spec_bytes)
            spec = json.loads(spec_bytes)

            # ---- excluded operations (counted from the schema itself)
            methods = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
            total_ops = excluded = 0
            for pth, item in (spec.get("paths") or {}).items():
                n = sum(1 for m in methods if m in (item or {}))
                total_ops += n
                if any(re.search(p, pth) for p in patterns):
                    excluded += n
            details["operations_total"], details["operations_excluded"] = total_ops, excluded

            # ---- throwaway user -> bearer token (ephemeral DB, never a real account)
            token = None
            auth = cfg.get("auth")
            if auth:
                try:
                    reg = auth.get("register")
                    if reg:
                        http("POST", base + reg["path"], reg.get("json"), timeout=15)
                    lg = auth["login"]
                    code, body = http("POST", base + lg["path"], lg.get("json"), timeout=15)
                    token = json.loads(body).get(lg.get("token_field", "access_token")) if code == 200 else None
                except (OSError, ValueError, AttributeError):
                    token = None
                if not token:
                    return V("UNVERIFIED", "auth bootstrap failed: could not register/login the throwaway user")
                secrets.add(token)

            # ---- schemathesis (the token goes in via a 0600 config file + env var, never argv)
            rep_dir = os.path.join(tmp, "rep")
            cfg_file = None
            if token:
                cfg_file = os.path.join(tmp, "schemathesis.toml")
                fd = os.open(cfg_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w") as f:
                    f.write(TOKEN_CONFIG)
            args = fuzz_args(seed, max_ex, mode_opt, req_timeout, patterns)
            senv = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": tmp, "LANG": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1", "NO_COLOR": "1"}
            if token:
                senv["FUZZ_TOKEN"] = token
            ver_rc, ver_out, _ = qc.run([st_bin, "--version"], timeout=30, polite=False)
            params["schemathesis"] = ver_out.strip().split()[-1] if ver_rc == 0 and ver_out.strip() else None
            params["argv"] = args
            if deadline - time.time() < 3:
                return V("UNVERIFIED", "timeout: %ds cap spent before the fuzz could start" % cap)

            def st_pass(tag, extra_args=()):
                """One schemathesis run bounded by the TOTAL deadline. Returns (rc, ndjson path or None); rc None = wall cap hit (group killed)."""
                nonlocal st_proc
                out_path = os.path.join(tmp, "schemathesis-%s.out" % tag)
                pdir = os.path.join(rep_dir, tag)
                cmd = build_cmd(st_bin, spec_path, base, pdir, list(args) + list(extra_args), cfg_file)
                if tag == "p1":
                    details["argv"] = [redact(x, secrets, 1000) for x in cmd]      # evidence of what really ran (never holds the token)
                with open(out_path, "wb") as lf:
                    st_proc = subprocess.Popen(cmd, cwd=tmp, env=senv, stdin=subprocess.DEVNULL, stdout=lf, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    st_proc.wait(timeout=max(1.0, deadline - time.time()))
                except subprocess.TimeoutExpired:
                    kill_group(st_proc)
                    return None, None, out_path
                nd_ = None
                if os.path.isdir(pdir):
                    for fn in sorted(os.listdir(pdir)):
                        if fn.startswith("ndjson") or fn.endswith(".ndjson"):
                            nd_ = os.path.join(pdir, fn)
                return st_proc.returncode, nd_, out_path

            t_fuzz = time.time()
            st_rc, nd, st_out = st_pass("p1")
            if st_rc is None:
                return V("UNVERIFIED", "timeout: schemathesis exceeded the %ds cap (OVN_FUZZ_TIMEOUT_S)" % cap)
            details["fuzz_s"] = round(time.time() - t_fuzz, 1)
            if app_proc.poll() is not None:
                sweep_group(app_proc)
                return V("UNVERIFIED", "app process died during the fuzz (rc=%s), signatures are incomplete: %s" %
                         (app_proc.returncode, redact(tail_file(app_log), secrets)))
            if nd is None:
                return V("UNVERIFIED", "schemathesis produced no report (rc=%s): %s" % (st_rc, redact(tail_file(st_out), secrets)))
            keep = os.environ.get("OVN_FUZZ_KEEP_REPORT")      # debugging aid / fixture generation: copy the raw report (it holds request bodies!) here
            if keep:
                try:
                    shutil.copyfile(nd, keep)
                except OSError:
                    pass
            parsed = parse_ndjson(nd)
            if not parsed["complete"]:
                return V("UNVERIFIED", "schemathesis did not complete (rc=%s, stop_reason=%s): %s" %
                         (st_rc, parsed["stop_reason"], redact(tail_file(st_out), secrets)))
            details["operations_selected"] = parsed["operations_selected"]
            details["scenarios"] = parsed["scenarios"]
            details["client_side_errors"] = parsed["client_errors"]
            if parsed["operations_total"] is not None and parsed["operations_selected"] is not None:
                if parsed["operations_total"] - parsed["operations_selected"] != excluded:
                    details["exclude_count_mismatch"] = {"ours": excluded, "schemathesis": parsed["operations_total"] - parsed["operations_selected"]}
            details["schemathesis_version"] = parsed["version"]
            observed = parsed["signatures"]
            # A ReadTimeout/ConnectionError on a box shared with the fleet can be a CPU spike, not a bug (seen at load 10-16): re-run only those
            # operations once. One that does not repeat is reported as details.transient_network_errors (counted, not a signature); one that
            # repeats stays a signature. Not enough time left, or an incomplete retry => conservative: they stay signatures.
            transients = [x for x in observed if _TRANSIENT_SIG.match(x)]
            if transients and deadline - time.time() > 10 and app_proc.poll() is None:
                st_rc2, nd2, _ = st_pass("p2", ["--include-name-regex", retry_filter(transients)])
                if st_rc2 is None:
                    return V("UNVERIFIED", "timeout: schemathesis exceeded the %ds cap (OVN_FUZZ_TIMEOUT_S) while re-checking network errors" % cap)
                if app_proc.poll() is not None:
                    sweep_group(app_proc)
                    return V("UNVERIFIED", "app process died during the network-error re-check (rc=%s), signatures are incomplete: %s" %
                             (app_proc.returncode, redact(tail_file(app_log), secrets)))
                parsed2 = parse_ndjson(nd2) if nd2 else None
                if parsed2 and parsed2["complete"]:
                    transient = sorted(set(transients) - set(parsed2["signatures"]))
                    if transient:
                        observed = [x for x in observed if x not in transient]
                        details["transient_network_errors"] = transient[:SIG_CAP]
                        details["transient_network_error_count"] = len(transient)
                else:
                    details["recheck"] = "incomplete: network errors kept as signatures"
            try:
                with open(guard_log) as f:
                    blocked = [ln.split(" ", 1) for ln in f.read().splitlines() if ln.strip()]
            except OSError:
                blocked = []
            hosts = sorted({redact(b[1], secrets, 80) for b in blocked if len(b) == 2})
            details["blocked_outbound"] = len(blocked)
            if hosts:
                details["blocked_outbound_hosts"] = hosts[:10]
            details["signatures"] = observed[:SIG_CAP]
            details["signature_count"] = len(observed)
    finally:
        kill_group(st_proc)
        kill_group(app_proc)
        shutil.rmtree(tmp, ignore_errors=True)

    fp = fingerprint(params, patterns)
    suffix = " [excluded %d/%d ops%s]" % (excluded, total_ops, "; blocked %d outbound attempt(s) (in-process guard; see README for its limits)" % len(blocked) if blocked else "")
    if a["accept"]:
        write_baseline(repo, ref, sha, fp, observed)
        return V("PASS", "baseline accepted: %d signature(s) recorded%s" % (len(observed), suffix), {"baseline_accepted": True})
    base_doc = load_baseline(repo)
    if base_doc is None:
        return V("FLAG", "no baseline: %d signatures observed%s" % (len(observed), suffix))
    if base_doc.get("fingerprint") != fp:
        return V("UNVERIFIED", "baseline was recorded with different fuzz parameters/excludes/schemathesis version; review and re-run --accept-baseline%s" % suffix)
    old = set(base_doc["signatures"])
    new = sorted(set(observed) - old)
    fixed = sorted(old - set(observed))
    extra = {"baseline_signatures": len(old), "fixed": fixed[:SIG_CAP], "fixed_count": len(fixed)}
    if new:
        extra["new"] = new[:10]
        extra["new_count"] = len(new)
        return V("FLAG", "%d new signature(s) vs baseline: %s%s" % (len(new), "; ".join(new[:3]) + (" ..." if len(new) > 3 else ""), suffix), extra)
    return V("PASS", "no new signatures (%d baseline, %d fixed)%s" % (len(old), len(fixed), suffix), extra)


def _term(_sig, _frm):
    raise SystemExit(143)   # let `finally` kill the app / schemathesis groups when cron times us out


def main(argv=None):
    signal.signal(signal.SIGTERM, _term)
    return qc.main_guard(GATE, check, argv)


if __name__ == "__main__":
    sys.exit(main())
