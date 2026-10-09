#!/usr/bin/env python3
"""scripts/ovn_local_research.py: the Claude-free roadmap refuel (deterministic evidence + local model + gates).
Fixture queue dir + a stub OpenAI-compatible model server; no GPU, no network beyond localhost."""
import datetime
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "ovn_local_research.py")
VALIDATOR = os.path.join(ROOT, "ovn_auto_research_validate.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:200]) if extra else ""))


REPLY = {"text": ""}
HITS = {"n": 0}


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        HITS["n"] += 1
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"choices": [{"message": {"content": REPLY["text"]}}], "usage": {"prompt_tokens": 10, "completion_tokens": 5}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = http.server.HTTPServer(("127.0.0.1", 0), H)
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


def make_fixture(roadmap="# roadmap\n"):
    d = tempfile.mkdtemp(prefix="lr-")
    repo = os.path.join(d, "repos", "demo", "iptv-backend", "app", "routers")
    os.makedirs(repo)
    os.makedirs(os.path.join(d, "repos", "demo", "iptv-backend", "tests"))
    os.makedirs(os.path.join(d, "roadmap"))
    os.makedirs(os.path.join(d, "scripts"))
    for n in ("a", "b", "d"):  # a uses the limiter, b and d do not (d keeps evidence available after b is covered by an appended item)
        body = "from app.core.limiter import limiter\n" if n == "a" else ""
        dec = "@limiter.limit('5/minute')\n" if n == "a" else ""
        open(os.path.join(repo, n + ".py"), "w").write(body + "@router.get('/x')\n" + dec + "def x():\n    return 1\n")
    # plus enough swallowed-exception evidence so >=2 pieces exist
    open(os.path.join(repo, "c.py"), "w").write("def f():\n    try:\n        g()\n    except Exception:\n        pass\n")
    open(os.path.join(d, "roadmap", "demo.md"), "w").write(roadmap)
    open(os.path.join(d, "scripts", "ovn_log_tokens.sh"), "w").write("#!/bin/sh\nexit 0\n")
    shutil.copy(VALIDATOR, os.path.join(d, "ovn_auto_research_validate.py"))
    sh("git", "init", "-q", cwd=d)
    sh("git", "add", "-A", cwd=d)
    sh("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init", cwd=d)
    return d


def run(d, *flags, env_extra=None):
    env = dict(os.environ, OVN_DIR=d, LITELLM_BASE="http://127.0.0.1:%d" % PORT)
    env.update(env_extra or {})
    r = sh(sys.executable, SCRIPT, "demo", *flags, env=env)
    return r.stdout + r.stderr


GOOD_A = ("- [ ] [P2] [ready] Rate-limit the b router — `iptv-backend/app/routers/b.py:1` has 1 route without `@limiter.limit`; apply the existing "
          "limiter and add a 429 test in `iptv-backend/tests/test_b_rate_limit.py` {cat: backend; size: S; multifile: no; research: none}")
GOOD_C = ("- [ ] [P3] [ready] Log the swallowed exception in c.f — `iptv-backend/app/routers/c.py:4` catches Exception then `pass`; log it and add a test "
          "in `iptv-backend/tests/test_c_logging.py` {cat: backend; size: S; multifile: no; research: none}")
BAD_PATH = ("- [ ] [P2] [ready] Harden the zzz service — `iptv-backend/app/services/zzz_does_not_exist.py:9` is unprotected; add auth and a test "
            "in `iptv-backend/tests/test_zzz.py` {cat: backend; size: S; multifile: no; research: none}")

# --- collectors / evidence
d = make_fixture()
out = run(d, "--evidence-only")
ok("evidence: names the router with no rate limit (and not the limited one)", "no-rate-limit] iptv-backend/app/routers/b.py" in out and "routers/a.py" not in out, out)
ok("evidence: names the swallowed exception", "swallowed-exception] iptv-backend/app/routers/c.py:4" in out, out)
out_skip = run(d, "--evidence-only", env_extra={"OVN_LR_SKIP_KINDS": "py_unlimited_routers,py_swallowed"})
ok("OVN_LR_SKIP_KINDS drops the mechanical collectors (work supply owns them) and keeps no others' evidence hidden",
   "no-rate-limit" not in out_skip and "swallowed-exception" not in out_skip, out_skip)
ok("evidence-only never calls the model or writes anything", HITS["n"] == 0 and open(os.path.join(d, "roadmap", "demo.md")).read() == "# roadmap\n")

# --- full pass: valid items appended, invented path rejected, only roadmap committed
REPLY["text"] = "\n".join([GOOD_A, GOOD_C, BAD_PATH])
before_hits = HITS["n"]
out = run(d)
rm = open(os.path.join(d, "roadmap", "demo.md")).read()
ok("pass: calls the local model exactly once", HITS["n"] == before_hits + 1)
ok("pass: both evidence-grounded items appended as [ready]", "Rate-limit the b router" in rm and "Log the swallowed exception" in rm, out)
ok("NEGATIVE: an item naming a path that does not exist is rejected", "zzz_does_not_exist" not in rm and "does not exist" in out, out)
last = sh("git", "show", "--stat", "--format=%s", "HEAD", cwd=d).stdout
ok("pass: commits ONLY roadmap/demo.md", "roadmap/demo.md" in last and last.count("|") == 1, last)
ok("pass: sets cooldown marker + daily count", os.path.exists(os.path.join(d, "state", "local_research_demo")) and
   open(os.path.join(d, "state", "local_research_count_demo_%s" % datetime.date.today().isoformat())).read().strip() == "1")
ok("pass: writes one alerts.log line", "local-research:demo" in open(os.path.join(d, "state", "alerts.log")).read())

# --- gating
out = run(d)
ok("BENIGN gate: a [ready] feature already on the roadmap => skipped, model not called", "already has a [ready]" in out and HITS["n"] == before_hits + 1, out)
d2 = make_fixture()
REPLY["text"] = GOOD_A
run(d2)
rm2 = open(os.path.join(d2, "roadmap", "demo.md"))
# make it not-ready again, then cooldown should apply
txt = rm2.read().replace("[ready]", "[decomposed]")
open(os.path.join(d2, "roadmap", "demo.md"), "w").write(txt)
h = HITS["n"]
out = run(d2)
ok("cooldown: second pass within the cooldown is skipped without a model call", "cooldown" in out and HITS["n"] == h, out)
out = run(d2, "--force")
ok("--force bypasses cooldown", HITS["n"] == h + 1, out)
open(os.path.join(d2, "roadmap", "demo.md"), "w").write(open(os.path.join(d2, "roadmap", "demo.md")).read().replace("[ready]", "[decomposed]"))
out = run(d2, env_extra={"OVN_LR_MAX_PER_DAY": "1", "OVN_LR_COOLDOWN_H": "0"})
ok("daily cap: stops at OVN_LR_MAX_PER_DAY", "daily cap" in out, out)

# --- failure modes
d3 = make_fixture()
out = run(d3, env_extra={"LITELLM_BASE": "http://127.0.0.1:1"})
ok("model unreachable => no cooldown set, nothing appended (will retry next tick)", "model call failed" in out and not os.path.exists(os.path.join(d3, "state", "local_research_demo"))
   and open(os.path.join(d3, "roadmap", "demo.md")).read() == "# roadmap\n", out)
REPLY["text"] = "NONE"
out = run(d3)
ok("model says NONE => 0 accepted, cooldown set, roadmap untouched", "0 items accepted" in out and os.path.exists(os.path.join(d3, "state", "local_research_demo"))
   and open(os.path.join(d3, "roadmap", "demo.md")).read() == "# roadmap\n", out)
d4 = make_fixture()
h = HITS["n"]
out = run(d4, env_extra={"OVN_LOCAL_RESEARCH": "off"})
ok("kill switch OVN_LOCAL_RESEARCH=off => nothing happens", "skip" in out and HITS["n"] == h and not os.path.exists(os.path.join(d4, "state", "local_research_demo")), out)

# --- covered evidence is not re-proposed (the roadmap already names the file)
d5 = make_fixture("# roadmap\n- [x] [P2] [ready] Old item — `iptv-backend/app/routers/b.py:1` was handled {cat: backend; size: S; multifile: no; research: none}\n")
# 2026-10-09: the default rule is now 'open' (an [x] line no longer covers - see test_local_research_covered.py); this asserts the preserved legacy mode
out = run(d5, "--evidence-only", env_extra={"OVN_LR_COVERED_MODE": "legacy"})
ok("legacy mode: evidence whose file the roadmap already names is skipped (b.py), the rest remains (c.py)", "routers/b.py" not in out and "routers/c.py" in out, out)

srv.shutdown()
for x in (d, d2, d3, d4, d5):
    shutil.rmtree(x, ignore_errors=True)
print("local research: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
