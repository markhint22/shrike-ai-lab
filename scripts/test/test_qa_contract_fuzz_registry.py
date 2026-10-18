#!/usr/bin/env python3
"""Tests for the Phase 4 contract-fuzz extension: the repo registry (qa/contract_fuzz_repos.json: billwatch, gitlark), form-body logins, the per-repo auth_loss_max, the pinned
tool installer (qa/fuzz_tool_install.sh) and the cron proposal. Hermetic: no schemathesis, no repo venv and no network are needed."""
import http.server, json, os, re, subprocess, sys, tempfile, threading
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__))); import tmp_track; tmp_track.install()   # 2026-10-17: every mkdtemp() below is removed at exit (the suite leaked these dirs)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
sys.path.insert(0, QA)
import contract_fuzz as cf  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="cf-reg-test-")
os.environ.pop("OVN_FUZZ_CONFIG_JSON", None)
os.environ.pop("OVN_FUZZ_REGISTRY", None)

print("== the shipped registry")
reg = cf.load_registry()
ok("billwatch and gitlark are registered; iptv_apps stays in code", set(reg) == {"billwatch", "gitlark"} and "iptv_apps" in cf.REPOS, sorted(reg))
for name in ("billwatch", "gitlark", "iptv_apps"):
    c = cf.config(name)
    ok("%s: config() resolves with every required key and compilable exclude patterns" % name, c and all(k in c for k in cf.REQUIRED_KEYS) and all(re.compile(p) for p, _ in c["exclude_paths"]))
    ok("%s: every exclusion carries a reason" % name, all(r for _, r in c["exclude_paths"]), [p for p, r in c["exclude_paths"] if not r])
    ok("%s: env holds placeholders only (blank, a {tmp} path, or 'dummy'/'contract-fuzz'), no real-looking secret" % name,
       all(v == "" or v in ("false", "development") or "{tmp}" in v or "dummy" in v or "contract-fuzz" in v for v in c["env"].values()), {k: v for k, v in c["env"].items() if v})
ok("an unknown repo is NA (config None)", cf.config("no-such-repo") is None)
bw, gl = cf.config("billwatch"), cf.config("gitlark")
ok("billwatch: form login (OAuth2PasswordRequestForm), password has a special character (its validator demands one)", "form" in bw["auth"]["login"] and re.search(r"[!@#$%^&*]", bw["auth"]["register"]["json"]["password"]))
ok("billwatch: every outbound-service key is blank (its lifespan runs sync / AI jobs that only bail out because the key is empty)",
   all(bw["env"].get(k) == "" for k in ("CONGRESS_API_KEY", "FEC_API_KEY", "GOOGLE_CIVIC_API_KEY", "ANTHROPIC_API_KEY", "STRIPE_SECRET_KEY", "SENDGRID_API_KEY", "FIREBASE_CREDENTIALS_JSON")), bw["env"])
for path in ("/api/bills/sync", "/api/bills/sync/sponsors", "/api/legislators/sync", "/api/civic/representatives", "/api/finance/search/fec", "/api/feedback", "/api/auth/forgot-password",
             "/api/billing/checkout", "/api/billing/webhook", "/api/analytics/summaries/generate-batch", "/api/bills/{bill_id}/chat", "/api/export/account"):
    ok("billwatch excludes %s (outbound or destroys the throwaway user)" % path, any(re.search(p, path) for p, _ in bw["exclude_paths"]))
for path in ("/api/bills", "/api/alerts", "/api/auth/me", "/health", "/api/topics", "/api/bills/{bill_id}"):
    ok("billwatch still fuzzes %s" % path, not any(re.search(p, path) for p, _ in bw["exclude_paths"]))
for path in ("/api/github/repos", "/api/github/app/install", "/api/auth/github/callback", "/api/billing/checkout", "/api/connectors/x", "/api/repo-analysis/run", "/api/conversations/1"):
    ok("gitlark excludes %s" % path, any(re.search(p, path) for p, _ in gl["exclude_paths"]))
ok("gitlark: no throwaway login (OAuth only) and the 'lost its auth' rule is disabled for it", not gl.get("auth") and gl["auth_loss_max"] > 1)
lost, share = cf.auth_loss({"responses": 1000, "unauthorized": 990}, max_share=gl["auth_loss_max"])
ok("... so a 99% 401 wall is not 'lost auth' for gitlark, but still is for a repo that logs in", lost is False and cf.auth_loss({"responses": 1000, "unauthorized": 990})[0] is True)

print("== registry loading is defensive")
def regfile(obj, raw=None):
    p = os.path.join(T, "reg%d.json" % len(os.listdir(T)))
    open(p, "w").write(raw if raw is not None else json.dumps(obj))
    return p


good = {k: v for k, v in reg["billwatch"].items()}
ok("a corrupt registry file yields {} (never raises)", cf.load_registry(regfile(None, "{not json")) == {})
ok("a missing registry file yields {}", cf.load_registry(os.path.join(T, "nope.json")) == {})
bad = dict(good)
del bad["app"]
ok("an entry missing a required key is dropped; comment keys ('_x') are ignored", cf.load_registry(regfile({"_c": "x", "a": bad, "b": good, "c": "str", "d": dict(good, env=[])})) == {"b": good})
os.environ["OVN_FUZZ_REGISTRY"] = regfile({"zed": good})
ok("OVN_FUZZ_REGISTRY points the loader at another file; the in-code table still wins its names", cf.config("zed") is not None and cf.config("billwatch") is None and cf.config("iptv_apps") is not None)
os.environ.pop("OVN_FUZZ_REGISTRY")
os.environ["OVN_FUZZ_CONFIG_JSON"] = regfile({"billwatch": dict(good, app="x.main:app")})
ok("OVN_FUZZ_CONFIG_JSON still overrides a registry entry (tests/trials)", cf.config("billwatch")["app"] == "x.main:app")
os.environ.pop("OVN_FUZZ_CONFIG_JSON")
ok("in-code REPOS wins over a registry entry of the same name", (lambda: (os.environ.__setitem__("OVN_FUZZ_REGISTRY", regfile({"iptv_apps": dict(good, app="evil:app")})), cf.config("iptv_apps")["app"])[1])() == "app.main:app")
os.environ.pop("OVN_FUZZ_REGISTRY")

print("== form login body")
seen = {}


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        seen["ct"], seen["body"] = self.headers.get("Content-Type"), self.rfile.read(n).decode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"access_token": "t"}')


srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
code, body = cf.http("POST", "http://127.0.0.1:%d/login" % srv.server_address[1], form={"username": "a@b.c", "password": "p w&"})
ok("form= sends application/x-www-form-urlencoded with escaped values", code == 200 and seen["ct"] == "application/x-www-form-urlencoded" and seen["body"] == "username=a%40b.c&password=p+w%26", seen)
code, body = cf.http("POST", "http://127.0.0.1:%d/login" % srv.server_address[1], {"email": "a"})
ok("json body is unchanged", seen["ct"] == "application/json" and json.loads(seen["body"]) == {"email": "a"}, seen)
srv.shutdown()

print("== check() on a registry repo degrades to UNVERIFIED/NA, never crashes")
env_s = dict(os.environ, QA_STATE_DIR=os.path.join(T, "st"), OVN_DIR=T, HOME=T, OVN_REPOS_DIR=os.path.join(T, "norepos"))
p = subprocess.run([sys.executable, os.path.join(QA, "contract_fuzz.py"), "check", "--repo", "gitlark", "--no-record"], env=env_s, capture_output=True, text=True, timeout=60)
j = json.loads(p.stdout.strip().splitlines()[-1])
ok("gitlark with no clone: exit 0 and UNVERIFIED 'no clone' (not NA: it IS configured now)", p.returncode == 0 and j["verdict"] == "UNVERIFIED" and "no clone" in j["summary"], j)
p = subprocess.run([sys.executable, os.path.join(QA, "contract_fuzz.py"), "check", "--repo", "nope", "--no-record"], env=env_s, capture_output=True, text=True, timeout=60)
ok("an unregistered repo is still NA 'repo not configured'", json.loads(p.stdout.strip().splitlines()[-1])["verdict"] == "NA")

print("== qa/fuzz_tool_install.sh reuses the P1 installer (ops/qa_tools_install.sh), schemathesis only")
inst = os.path.join(QA, "fuzz_tool_install.sh")
fake = os.path.join(T, "ovn")
os.makedirs(os.path.join(fake, "ops"))
log = os.path.join(T, "inst.log")
open(os.path.join(fake, "ops", "qa_tools_install.sh"), "w").write('#!/usr/bin/env bash\necho "P1 args=[$*] skip=[${QA_TOOLS_SKIP:-}] ovn=[${OVN_DIR:-}]" >> "' + log + '"\nexit ${FAKE_RC:-0}\n')
e = {"PATH": os.environ["PATH"], "HOME": T, "OVN_DIR": fake}
p = subprocess.run(["bash", inst], env=e, capture_output=True, text=True, timeout=60)
ok("default is a DRY RUN delegated to the P1 installer", p.returncode == 0 and "args=[--dry-run]" in open(log).read(), (p.stdout, p.stderr))
for tool in ("bandit", "semgrep", "pip-audit", "mutmut", "mypy", "ruff", "gitleaks"):
    ok("all other tools are skipped so only schemathesis is installed (%s)" % tool, tool in open(log).read().split("skip=[")[1].split("]")[0].split())
ok("schemathesis itself is NOT in the skip list", "schemathesis" not in open(log).read().split("skip=[")[1].split("]")[0].split())
open(log, "w").close()
p = subprocess.run(["bash", inst, "--check"], env=dict(e, FAKE_RC="1"), capture_output=True, text=True, timeout=60)
ok("--check passes --check through and returns the installer's exit code (1 = missing)", p.returncode == 1 and "args=[--check]" in open(log).read())
open(log, "w").close()
p = subprocess.run(["bash", inst, "--apply"], env=e, capture_output=True, text=True, timeout=60)
ok("--apply passes NO flag (the real install), and only on request", p.returncode == 0 and "args=[]" in open(log).read())
open(log, "w").close()
p = subprocess.run(["bash", inst, "--bogus"], env=e, capture_output=True, text=True, timeout=60)
ok("an unknown flag is refused (exit 2) and the installer is not run", p.returncode == 2 and open(log).read() == "")
p = subprocess.run(["bash", inst], env=dict(e, OVN_DIR=os.path.join(T, "empty")), capture_output=True, text=True, timeout=60)
ok("a missing P1 installer is refused loudly (exit 2), no fallback installer exists", p.returncode == 2 and "P1 installer not found" in p.stderr)
src = open(inst).read()
ok("the wrapper contains no pip / venv / rm of its own (one installer, one set of safety checks)", not re.search(r"\bpip\b.*install|-m venv|\brm\s", src.replace("pip-audit", "")), "pip/venv/rm found")
p = subprocess.run(["bash", inst], env={"PATH": os.environ["PATH"], "HOME": T, "OVN_DIR": os.path.abspath(os.path.join(QA, ".."))}, capture_output=True, text=True, timeout=60)
ok("against the REAL P1 installer in this tree: dry-run works and installs nothing", p.returncode == 0 and "DRY RUN" in p.stdout and not os.path.exists(os.path.join(QA, "..", "qa-tools")), (p.stdout[-300:], p.stderr[-200:]))

print("== cron proposal + wrapper")
prop = open(os.path.join(QA, "phase4_cron.proposed.txt")).read()
lines = [l for l in prop.splitlines() if l and not l.startswith("#")]
ok("the proposal has the fuzz, soak and drill lines and every one is a valid 5-field cron entry", len(lines) == 3 and all(re.match(r"^(\S+\s+){5}cd ~/overnight-queue && ", l) for l in lines), lines)
ok("the proposal says it is NOT installed and lists the order (tool, baseline, creds, then cron)", "NOT installed" in prop and "--accept-baseline" in prop and "fuzz_tool_install.sh --apply" in prop and "ops/qa_tools_install.sh" in prop)
wrap = open(os.path.join(QA, "contract_fuzz_cron.sh")).read()
m = re.search(r'^for r in \$\{OVN_FUZZ_REPOS:-([^}]*)\}; do', wrap, re.M)
default_repos = m.group(1).split() if m else []
ok("the nightly wrapper's LOOP default (not its header comment) is exactly the registry: iptv_apps + billwatch + gitlark", sorted(default_repos) == sorted(set(cf.REPOS) | set(cf.load_registry())) and default_repos[:1] == ["iptv_apps"], default_repos)
ok("the nightly wrapper is still shadow (no push / notify)", "never pushes/notifies" in wrap)
print("== find_schemathesis search order")
fake_home, fake_ovn = os.path.join(T, "home"), os.path.join(T, "ovn")
st_new = os.path.join(fake_ovn, "qa-tools", ".venv", "bin", "schemathesis")
st_old = os.path.join(fake_home, "qa-venv", "bin", "schemathesis")
for pth in (st_new, st_old):
    os.makedirs(os.path.dirname(pth), exist_ok=True)
    open(pth, "w").write("#!/bin/sh\n")
    os.chmod(pth, 0o755)
saved = {k: os.environ.get(k) for k in ("HOME", "OVN_DIR", "PATH", "OVN_FUZZ_SCHEMATHESIS")}
os.environ.update({"HOME": fake_home, "OVN_DIR": fake_ovn, "PATH": "/usr/bin:/bin"})
os.environ.pop("OVN_FUZZ_SCHEMATHESIS", None)
try:
    ok("~/qa-venv wins over the install venv", cf.find_schemathesis() == st_old, cf.find_schemathesis())
    os.remove(st_old)
    ok("with no ~/qa-venv and none on PATH the P1 install venv (qa-tools/.venv) is the fallback (the 2026-10-16 wipe case)", cf.find_schemathesis() == st_new, cf.find_schemathesis())
    os.environ["OVN_FUZZ_SCHEMATHESIS"] = st_new
    ok("OVN_FUZZ_SCHEMATHESIS is honoured first", cf.find_schemathesis() == st_new)
    os.environ.pop("OVN_FUZZ_SCHEMATHESIS")
    os.remove(st_new)
    ok("nothing installed -> None (the caller reports UNVERIFIED)", cf.find_schemathesis() is None)
finally:
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
ok("the acceptance checklist doc exists and names --accept-baseline, triage and the 0-outbound rule", all(x in open(os.path.join(QA, "contract_fuzz.ACCEPT_BASELINE.md")).read() for x in ("--accept-baseline", "blocked_outbound", "Triage")))

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
