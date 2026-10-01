#!/usr/bin/env python3
"""staging_smoke.py - gate S10c: REAL smoke test of a STAGING backend (shadow). Replaces the 3-check staging_smoke.sh.

  python3 qa/staging_smoke.py check --repo <billwatch|gitlark|iptv_apps> [--base-url URL] [--config FILE] [--no-record]

Steps (declared per repo in qa/staging_smoke.conf):
  health      GET health path -> 2xx/307, JSON content-type, expected key
  login       the repo's staging TEST account -> bearer token (credentials are never printed; see README for where they come from)
  business    one or more real endpoints (public, authenticated, and an anonymous-must-be-rejected guard)
  write_read  one DB write with the test account, read-back through a DIFFERENT request, cleanup (always attempted)
  frontend    curl the frontend and look for a marker (no staging frontend exists today: this loads the PROD frontend asset only)
  cors        OPTIONS preflight from each REAL frontend origin must echo it; an arbitrary origin must NOT be reflected

Verdicts: any step FAIL -> FAIL | no FAIL but a step could not run for infra reasons (no response, creds not provisioned) -> UNVERIFIED |
all steps ran except some that are N/A by design (e.g. gitlark has no password login) -> FLAG ("PARTIAL", lists the gaps) | else PASS.
Only an HTTP response can FAIL a step; timeouts / DNS / refused connections are UNVERIFIED (never fail closed on infra).
Safety: refuses any base URL that is not staging (host must contain "staging"; localhost only with QA_SMOKE_ALLOW_LOCAL=1 for tests).
stdlib only (runs under the box's python3.12 and the Mac python3). Exit 0 always except enforce + FAIL + --enforce-exit.
"""
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "staging_smoke"
HERE = os.path.dirname(os.path.abspath(__file__))
SECRETS = []  # every credential / token seen this run; scrubbed from the final output


def secret(v):
    if v and len(v) >= 4 and v not in SECRETS:
        SECRETS.append(v)
    return v


def scrub(obj):
    s = json.dumps(obj, ensure_ascii=False)
    for v in sorted(SECRETS, key=len, reverse=True):
        s = s.replace(json.dumps(v)[1:-1], "***").replace(v, "***")
    return json.loads(s)


# ---------------------------------------------------------------- http
def http(method, url, headers=None, body=None, form=None, timeout=20):
    """-> (status, headers_dict_lowercased, text, err). status 0 == no HTTP response (err says why, class name only)."""
    h = {"User-Agent": "qa-staging-smoke/1", "Accept": "*/*"}
    h.update(headers or {})
    data = None
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        r = urllib.request.urlopen(req, timeout=timeout)
        return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read(2000000).decode("utf-8", "replace"), ""
    except urllib.error.HTTPError as e:
        try:
            txt = e.read(2000000).decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            txt = ""
        return e.code, {k.lower(): v for k, v in e.headers.items()}, txt, ""
    except Exception as e:  # noqa: BLE001 - timeouts, DNS, refused, TLS
        return 0, {}, "", type(e).__name__


def http_retry(*a, **k):
    r = http(*a, **k)
    if r[0] == 0:  # one retry for transient network trouble only
        time.sleep(2)
        r = http(*a, **k)
    return r


def jload(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def sub(v, vars_):
    if isinstance(v, str):
        for k, val in vars_.items():
            v = v.replace("{%s}" % k, str(val))
        return v
    if isinstance(v, dict):
        return {k: sub(x, vars_) for k, x in v.items()}
    if isinstance(v, list):
        return [sub(x, vars_) for x in v]
    return v


# ---------------------------------------------------------------- credentials
def creds_file(name):
    return os.path.join(qc.state_dir(), "qa_creds", name + ".json")


def parse_repo_default(repo, spec):
    """Documented staging password lives as os.getenv(ENV, "<default>") next to the email in the repo's own janitor script.
    Read it from origin/develop with `git show` (read-only). Returns (email, password) or (None, None). Never printed."""
    rd = qc.repo_dir(repo)
    if not rd:
        return None, None
    env_name = spec.get("password_env_name", "")
    for ref in ("origin/develop", "origin/main", "HEAD"):
        rc, out, _ = qc.git(rd, "show", "%s:%s" % (ref, spec["git_path"]))
        if rc == 0:
            m = re.search(r'\(\s*"([^"]+@[^"]+)"\s*,\s*os\.getenv\(\s*"%s"\s*,\s*"([^"]*)"\s*\)' % re.escape(env_name), out)
            if m:
                return m.group(1), os.environ.get(env_name) or m.group(2)
    return None, None


def resolve_creds(repo, spec):
    """-> (email, password, source) ; source in env|file|repo_default|none"""
    e, p = os.environ.get(spec.get("email_env", "")), os.environ.get(spec.get("password_env", ""))
    if e and p:
        return e, p, "env"
    try:
        with open(creds_file(spec.get("file", repo))) as f:
            j = json.load(f)
        if j.get("email") and j.get("password"):
            return j["email"], j["password"], "file"
    except (OSError, ValueError):
        pass
    if spec.get("repo_default"):
        e, p = parse_repo_default(repo, spec["repo_default"])
        if e and p:
            return e, p, "repo_default"
    return None, None, "none"


def save_creds(name, email, password):
    d = os.path.join(qc.state_dir(), "qa_creds")
    os.makedirs(d, mode=0o700, exist_ok=True)
    path = creds_file(name)
    fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"email": email, "password": password}, f)
    os.replace(path + ".tmp", path)


# ---------------------------------------------------------------- steps
class Run:
    def __init__(self, repo, base, cfg, defaults):
        self.repo, self.base, self.cfg = repo, base.rstrip("/"), cfg
        self.timeout = int(defaults.get("timeout_s", 20))
        self.deny_origin = defaults.get("deny_origin", "https://evil.example")
        self.steps, self.token, self.token_state = [], "", "none"  # token_state: ok|na|unverified|fail|none
        self.vars = {"marker": time.strftime("%H%M%S") + "-" + secrets.token_hex(2)}
        self.creds_source = "none"

    def add(self, name, status, detail="", t0=None):
        self.steps.append({"name": name, "status": status, "ms": int((time.time() - t0) * 1000) if t0 else 0, "detail": str(detail)[:240]})
        return status

    def url(self, path):
        return self.base + path

    def auth_h(self):
        return {"Authorization": "Bearer " + self.token} if self.token else {}

    # -- health
    def health(self):
        t0 = time.time()
        spec = self.cfg.get("health") or {"path": "/health"}
        st, hd, txt, err = http_retry("GET", self.url(spec["path"]), timeout=self.timeout)
        if st == 0:
            return self.add("health", "unverified", "no HTTP response (%s)" % err, t0)
        if not (200 <= st < 300 or st == 307):
            return self.add("health", "fail", "HTTP %d (502 = startup crash / bad async driver; 404 = wrong URL)" % st, t0)
        if not hd.get("content-type", "").startswith("application/json"):
            return self.add("health", "fail", "content-type %r - API is serving HTML/other, expected JSON" % hd.get("content-type", ""), t0)
        j = jload(txt)
        key = spec.get("json_has")
        if key and not (isinstance(j, dict) and key in j):
            return self.add("health", "fail", "JSON body lacks %r" % key, t0)
        return self.add("health", "ok", "HTTP %d json" % st, t0)

    # -- login
    def login(self):
        t0 = time.time()
        spec = self.cfg.get("login") or {"kind": "none"}
        if spec["kind"] == "none":
            tok = os.environ.get(spec.get("token_env", ""), "")
            if tok:
                self.token, self.token_state = secret(tok), "ok"
                self.creds_source = "env-token"
                return self.add("login", "ok", "using bearer token from $%s (not validated beyond business steps)" % spec["token_env"], t0)
            self.token_state = "na"
            return self.add("login", "na", spec.get("reason", "no login mechanism"), t0)
        c = spec.get("creds", {})
        email, pw, src = resolve_creds(self.repo, c)
        secret(email)
        secret(pw)
        self.creds_source = src
        if not (email and pw) and c.get("auto_register"):
            ar = c["auto_register"]
            email = ar["email"]
            pw = secrets.token_urlsafe(18) + "aA1!"
            secret(email)
            secret(pw)
            body = {"email": email, "password": pw}
            body.update(ar.get("body", {}))
            st, hd, txt, err = http_retry("POST", self.url(ar["path"]), body=body, timeout=self.timeout)
            if st == 0:
                self.token_state = "unverified"
                return self.add("login", "unverified", "register: no HTTP response (%s)" % err, t0)
            if st in (200, 201):
                save_creds(c.get("file", self.repo), email, pw)
                self.creds_source = "auto_register(saved)"
            elif st in (400, 409, 422):
                self.token_state = "unverified"
                return self.add("login", "unverified", "smoke account exists but no stored credentials (provision state/qa_creds/%s.json or env %s/%s)" % (
                    c.get("file", self.repo), c.get("email_env"), c.get("password_env")), t0)
            else:
                self.token_state = "fail"
                return self.add("login", "fail", "auto-register HTTP %d" % st, t0)
        elif not (email and pw):
            self.token_state = "unverified"
            return self.add("login", "unverified", "credentials not provisioned (env %s/%s, state/qa_creds/%s.json)" % (
                c.get("email_env"), c.get("password_env"), c.get("file", self.repo)), t0)
        if spec["kind"] == "form":
            st, hd, txt, err = http_retry("POST", self.url(spec["path"]), form={spec.get("user_field", "username"): email, "password": pw}, timeout=self.timeout)
        else:
            st, hd, txt, err = http_retry("POST", self.url(spec["path"]), body={"email": email, "password": pw}, timeout=self.timeout)
        if st == 0:
            self.token_state = "unverified"
            return self.add("login", "unverified", "no HTTP response (%s)" % err, t0)
        j = jload(txt)
        tok = j.get(spec.get("token_key", "access_token")) if isinstance(j, dict) else None
        if st == 200 and tok:
            self.token, self.token_state = secret(tok), "ok"
            return self.add("login", "ok", "HTTP 200, token issued (creds from %s)" % self.creds_source, t0)
        self.token_state = "fail"
        return self.add("login", "fail", "login HTTP %d%s (creds from %s)" % (st, "" if tok or st != 200 else " but no token in body", self.creds_source), t0)

    # -- business
    def business(self):
        for b in self.cfg.get("business", []):
            t0 = time.time()
            name = "business: " + b["name"]
            if b.get("auth"):
                if self.token_state in ("na",):
                    self.add(name, "na", "needs login (N/A for this repo)", t0)
                    continue
                if self.token_state != "ok":
                    self.add(name, "skip", "login did not succeed", t0)
                    continue
            st, hd, txt, err = http_retry("GET", self.url(b["path"]), headers=self.auth_h() if b.get("auth") else {}, timeout=self.timeout)
            if st == 0:
                self.add(name, "unverified", "no HTTP response (%s)" % err, t0)
                continue
            want = b.get("expect_status")
            if want:
                self.add(name, "ok" if st == want else "fail", "HTTP %d (expected %d)" % (st, want), t0)
                continue
            if not (200 <= st < 300):
                self.add(name, "fail", "HTTP %d" % st, t0)
                continue
            j = jload(txt)
            if b.get("json_has") and not (isinstance(j, dict) and b["json_has"] in j):
                self.add(name, "fail", "JSON lacks %r" % b["json_has"], t0)
            elif b.get("json_type") == "list" and not isinstance(j, list):
                self.add(name, "fail", "expected JSON list, got %s" % type(j).__name__, t0)
            elif b.get("json_type") == "dict" and not isinstance(j, dict):
                self.add(name, "fail", "expected JSON object, got %s" % type(j).__name__, t0)
            elif j is None:
                self.add(name, "fail", "body is not JSON (HTML fallback?)", t0)
            elif b.get("json_equals") and any(not (isinstance(j, dict) and j.get(k) == v) for k, v in b["json_equals"].items()):
                bad = [k for k, v in b["json_equals"].items() if not (isinstance(j, dict) and j.get(k) == v)]
                self.add(name, "fail", "unexpected value for field(s): %s" % ",".join(bad), t0)
            else:
                self.add(name, "ok", "HTTP %d" % st, t0)

    # -- write + read-back
    def write_read(self):
        wr = self.cfg.get("write_read")
        if not wr:
            return
        t0 = time.time()
        name = "write_read: " + wr.get("name", "write then read")
        if self.token_state == "na" or (wr.get("requires_token") and self.token_state != "ok"):
            self.add(name, "na", "needs an authenticated test account (N/A: %s)" % (self.cfg.get("login", {}).get("reason", "no token"))[:150], t0)
            return
        if self.token_state != "ok":
            self.add(name, "skip", "login did not succeed", t0)
            return
        w = sub(wr["write"], self.vars)
        st, hd, txt, err = http_retry(w["method"], self.url(w["path"]), headers=self.auth_h(), body=w.get("body"), timeout=self.timeout)
        if st == 0:
            self.add(name, "unverified", "write: no HTTP response (%s)" % err, t0)
            return
        if not (200 <= st < 300):
            self.add(name, "fail", "write HTTP %d" % st, t0)
            return
        j = jload(txt)
        for var, key in (w.get("capture") or {}).items():
            if isinstance(j, dict) and key in j:
                self.vars[var] = j[key]
        try:
            self._read_back(name, wr, t0)
        finally:
            cl = wr.get("cleanup")
            if cl:
                t1 = time.time()
                c = sub(cl, self.vars)
                if "{" in c["path"]:
                    self.add("write_read: cleanup", "fail", "could not build cleanup path (write response lacked the id)", t1)
                else:
                    cs, _, _, cerr = http(c["method"], self.url(c["path"]), headers=self.auth_h(), timeout=self.timeout)
                    ok = 200 <= cs < 300
                    self.add("write_read: cleanup", "ok" if ok else ("unverified" if cs == 0 else "fail"), "HTTP %d" % cs if cs else "no response (%s)" % cerr, t1)

    def _read_back(self, name, wr, t0):
        r = sub(wr["read"], self.vars)
        if "{" in r["path"]:
            self.add(name, "fail", "write response did not return the id needed to read back", t0)
            return
        st, hd, txt, err = http_retry("GET", self.url(r["path"]), headers=self.auth_h(), timeout=self.timeout)
        if st == 0:
            self.add(name, "unverified", "read-back: no HTTP response (%s)" % err, t0)
            return
        if not (200 <= st < 300):
            self.add(name, "fail", "read-back HTTP %d" % st, t0)
            return
        j = jload(txt)
        if "expect_json_equals" in r:
            bad = [k for k, v in r["expect_json_equals"].items() if not (isinstance(j, dict) and j.get(k) == v)]
            if bad:
                self.add(name, "fail", "write NOT visible on read-back (fields differ: %s)" % ",".join(bad), t0)
                return
        if "expect_in_list" in r:
            e = r["expect_in_list"]
            lst = j if isinstance(j, list) else (next((v for v in j.values() if isinstance(v, list)), []) if isinstance(j, dict) else [])
            if not any(isinstance(i, dict) and str(i.get(e["field"])) == str(e["value"]) for i in lst):
                self.add(name, "fail", "written row not found in list on read-back", t0)
                return
        self.add(name, "ok", "write HTTP 2xx and visible on read-back", t0)

    # -- frontend
    def frontend(self):
        f = self.cfg.get("frontend")
        if not f:
            return
        t0 = time.time()
        st, hd, txt, err = http_retry("GET", f["url"], timeout=self.timeout)
        if st == 0:
            self.add("frontend", "unverified", "no HTTP response (%s)" % err, t0)
        elif st != 200 or "text/html" not in hd.get("content-type", ""):
            self.add("frontend", "fail", "%s -> HTTP %d %s" % (f["url"], st, hd.get("content-type", "")), t0)
        elif f.get("contains") and f["contains"] not in txt:
            self.add("frontend", "fail", "HTML lacks marker %r" % f["contains"], t0)
        else:
            self.add("frontend", "ok", "%s HTTP 200 html (%s)" % (f["url"], f.get("note", "")[:90]), t0)

    # -- cors
    def cors(self):
        c = self.cfg.get("cors")
        if not c:
            return
        pre = {"Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "authorization"}
        for origin in c.get("origins", []):
            t0 = time.time()
            st, hd, txt, err = http_retry("OPTIONS", self.url(c["path"]), headers=dict(pre, Origin=origin), timeout=self.timeout)
            acao = hd.get("access-control-allow-origin", "")
            if st == 0:
                self.add("cors: %s" % origin, "unverified", "no HTTP response (%s)" % err, t0)
            elif acao in (origin, "*") and 200 <= st < 300:
                self.add("cors: %s" % origin, "ok", "preflight %d, allow-origin %s" % (st, acao), t0)
            else:
                self.add("cors: %s" % origin, "fail", "preflight %d, allow-origin %r - browser calls from the real frontend will fail" % (st, acao), t0)
        t0 = time.time()
        st, hd, txt, err = http_retry("OPTIONS", self.url(c["path"]), headers=dict(pre, Origin=self.deny_origin), timeout=self.timeout)
        acao = hd.get("access-control-allow-origin", "")
        if st == 0:
            self.add("cors: deny arbitrary origin", "unverified", "no HTTP response (%s)" % err, t0)
        elif acao == self.deny_origin:
            self.add("cors: deny arbitrary origin", "fail", "arbitrary origin %s is REFLECTED in allow-origin" % self.deny_origin, t0)
        else:
            self.add("cors: deny arbitrary origin", "ok", "allow-origin %r" % acao, t0)


def load_config(path):
    with open(path) as f:
        return json.load(f)


def base_url_for(repo, flag):
    if flag:
        return flag
    try:
        with open(os.path.join(qc.state_dir(), "staging_url_" + repo)) as f:
            return f.read().split()[0]
    except (OSError, IndexError):
        return ""


def is_staging(url):
    host = urllib.parse.urlparse(url).hostname or ""
    if os.environ.get("QA_SMOKE_ALLOW_LOCAL") == "1" and host in ("127.0.0.1", "localhost"):
        return True
    # allowlist: only Railway-hosted staging hosts (credentials are sent to this host; never trust an arbitrary *staging* name)
    return host.endswith(".up.railway.app") and "staging" in host and "production" not in host


def args_of(argv):
    o = {"repo": "", "base-url": "", "config": os.path.join(HERE, "staging_smoke.conf"), "base": "", "head": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return o


def cmd_check(argv):
    o = args_of(argv)
    repo = o["repo"]
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: check --repo <name>")
    try:
        conf = load_config(o["config"])
    except (OSError, ValueError) as ex:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "cannot read smoke config: %s" % type(ex).__name__)
    cfg = (conf.get("repos") or {}).get(repo)
    if not cfg:
        return qc.verdict("NA", GATE, repo, "?", "no smoke config for repo %s" % repo)
    base = base_url_for(repo, o["base-url"])
    if not base:
        return qc.verdict("UNVERIFIED", GATE, repo, "?", "no staging URL (state/staging_url_%s)" % repo)
    if not is_staging(base):
        return qc.verdict("UNVERIFIED", GATE, repo, base[:60], "REFUSING: %s is not a staging URL (this gate never touches production)" % urllib.parse.urlparse(base).hostname)
    t0 = time.time()
    run = Run(repo, base, cfg, conf.get("defaults", {}))
    run.health()
    if run.steps[0]["status"] in ("unverified", "fail"):
        for n in ("login", "business", "write_read", "frontend", "cors"):
            if n in cfg or n == "business":
                run.add(n, "skip", "health did not pass")
        # frontend + cors do not need a healthy backend session, but a dead backend makes them meaningless
    else:
        run.login()
        run.business()
        run.write_read()
        run.frontend()
        run.cors()
    by = {}
    for s in run.steps:
        by.setdefault(s["status"], []).append(s["name"])
    fails, unv, na = by.get("fail", []), by.get("unverified", []), by.get("na", [])
    total_ms = int((time.time() - t0) * 1000)
    det = {"base_url": base, "steps": run.steps, "counts": {k: len(v) for k, v in by.items()}, "creds_source": run.creds_source, "runtime_ms": total_ms}
    if fails:
        v, s = "FAIL", "%d step(s) FAILED: %s" % (len(fails), "; ".join("%s (%s)" % (x["name"], x["detail"]) for x in run.steps if x["status"] == "fail")[:300])
    elif unv:
        v, s = "UNVERIFIED", "could not run: %s" % "; ".join("%s (%s)" % (x["name"], x["detail"]) for x in run.steps if x["status"] == "unverified")[:300]
    elif na:
        v, s = "FLAG", "PARTIAL smoke: %d ok, N/A by design: %s" % (len(by.get("ok", [])), "; ".join(na))
    else:
        v, s = "PASS", "all %d smoke steps passed in %dms" % (len(by.get("ok", [])), total_ms)
    res = qc.verdict(v, GATE, repo, urllib.parse.urlparse(base).hostname or "", s, det, ms=total_ms)
    return scrub(res)


def main(argv):
    if not argv or argv[0] not in ("check",):
        print(__doc__)
        return 2
    return qc.main_guard(GATE, cmd_check, argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
