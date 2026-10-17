#!/usr/bin/env python3
"""Tests for qa/card_pilot_run.py, qa/card_pilot_report.py and the S2 `credit` shadow advisory (Phase 2 S0 card pilot).

Real entry points under `env -i` with a minimal PATH; the model is a fake litellm on loopback (no network). Fixture = a throwaway git repo named like the
real TAA clone with a progress file; state lives in a per-case temp OVN_DIR so real state is never touched. Stdlib only.
Includes MUTANTS: the linter's existence-only rule, the per-night request cap and the run.lock idle check are each broken in a COPY of qa/ and the matching
assertion must then fail (proving the tests can see the defect).
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
QUEUE = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(QUEUE, "qa")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:400]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-cardpilot-test-"))
if not os.path.isdir(T) or len(T) < 8:
    print("FATAL: no temp dir")
    sys.exit(1)
REPOS = os.path.join(T, "repos")
os.makedirs(REPOS)
SECRET = "sk-TESTSECRET-do-not-print"
REPO = "test-automation-agent"

# ------------------------------------------------------------------------------------------------------------------------ fake litellm
class Fake(http.server.BaseHTTPRequestHandler):
    responder = None     # callable(prompt) -> ("ok", card) | ("500",) | ("garbage",)
    seen = []
    lock = threading.Lock()

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        prompt = body["messages"][1]["content"]
        with Fake.lock:
            Fake.seen.append(prompt)
            step = Fake.responder(prompt) if Fake.responder else ("500",)
        if step[0] == "500":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"{}")
            return
        content = json.dumps(step[1]) if step[0] == "ok" else "this is not json at all"
        resp = {"choices": [{"message": {"content": content}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 900, "completion_tokens": 120},
                "timings": {"prompt_ms": 400.0, "predicted_ms": 1100.0}}
        data = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Srv(http.server.ThreadingHTTPServer):
    daemon_threads = True


srv = Srv(("127.0.0.1", 0), Fake)
URL = "http://127.0.0.1:%d" % srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

# ------------------------------------------------------------------------------------------------------------------------ fixture repo
CLONE = os.path.join(REPOS, REPO)
os.makedirs(os.path.join(CLONE, "app"))
os.makedirs(os.path.join(CLONE, "tests"))
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def g(*a):
    return subprocess.run(["git", "-C", CLONE] + list(a), capture_output=True, text=True, env=GENV)


I_GOOD = "app/util.py — Add `slugify(s)` that returns the lowercase string with spaces replaced by hyphens"
I_ECHO = "app/util.py — Add `titlecase(s)` that returns the string with every word capitalised"
I_EXIST = "app/util.py — Add `shout(s)` that returns the string upper-cased with an exclamation mark appended"
I_WEAK = "app/util.py — Update `existing()` so that it returns the integer 1"
I_AUTH = "app/auth_util.py — Add `check_token(t)` that returns False for an expired subscription token and raises ValueError for an empty token"
OUT_OF_SCOPE = ["game/unit.gd — Add `take_damage(n)` to Unit", "ios/App/View.swift — Add a `title` label to the view", "android/app/Main.kt — Add `fun greet()` to the activity",
                "web/src/Foo.vue — Add a field `x` and bind it to a textarea"]
PROGRESS = "# progress\n" + "".join("- [ ] [T2] %s\n" % x for x in (I_GOOD, I_ECHO, I_EXIST, I_WEAK, I_AUTH)) + "".join("- [ ] [T2] %s\n" % x for x in OUT_OF_SCOPE) \
    + "- [x] [T2] app/util.py — Add `done_thing()` that returns 3\n- [ ] [HUMAN-ONLY] [T2] app/util.py — Add `human_thing()` that returns 4\n"
open(os.path.join(CLONE, "app", "__init__.py"), "w").write("")
open(os.path.join(CLONE, "app", "util.py"), "w").write("def existing():\n    return 1\n")
open(os.path.join(CLONE, "app", "auth_util.py"), "w").write("def other():\n    return 0\n")
open(os.path.join(CLONE, "tests", "test_util.py"), "w").write("import unittest\nfrom app.util import existing\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(existing(), 1)\n")
open(os.path.join(CLONE, "OVERNIGHT_PROGRESS.md"), "w").write(PROGRESS)
g("init", "-q", "-b", "develop")
g("add", "-A")
g("commit", "-q", "-m", "base")
BASE = g("rev-parse", "HEAD").stdout.strip()
open(os.path.join(CLONE, "app", "util.py"), "a").write("\ndef slugify(s):\n    return s.lower().replace(' ', '-')\n")
g("add", "-A")
g("commit", "-q", "-m", "head: add slugify")
HEAD = g("rev-parse", "HEAD").stdout.strip()
g("checkout", "-q", BASE)

CARD_GOOD = {"bullets": ["`slugify('A b')` returns `'a-b'`", "`slugify('X')` returns `'x'`", "`slugify` is importable from `app.util`"],
             "verify_cmd": "python -c \"from app.util import slugify; assert slugify('A b') == 'a-b'\"", "files": ["app/util.py"], "risk_class": "C", "needs_human_review": False}
CARD_ECHO = dict(CARD_GOOD, bullets=["`titlecase('a b')` returns `'A B'`", "`titlecase('x')` returns `'X'`", "`titlecase` is importable from `app.util`"],
                 verify_cmd="grep -q titlecase app/util.py || echo not-yet")
CARD_EXIST = dict(CARD_GOOD, bullets=["`shout('a')` returns `'A!'`", "`shout('')` returns `'!'`", "`shout` is importable from `app.util`"], verify_cmd="test -e app/util.py")
CARD_WEAK = dict(CARD_GOOD, bullets=["`existing()` returns `1`", "`existing()` returns an int", "`existing` is importable from `app.util`"],
                 verify_cmd="python -c \"from app.util import existing; assert existing() == 1\"")
CARD_AUTH = {"bullets": ["`check_token('')` raises ValueError", "`check_token('expired')` returns False", "`check_token` is importable from `app.auth_util`"],
             "verify_cmd": "python -c \"from app.auth_util import check_token; assert check_token('expired') is False\"", "files": ["app/auth_util.py"],
             "risk_class": "C", "needs_human_review": False}
BY_KEY = {"slugify": CARD_GOOD, "titlecase": CARD_ECHO, "shout": CARD_EXIST, "existing()": CARD_WEAK, "check_token": CARD_AUTH}


def by_item(prompt):
    head = prompt.split("TARGET FILE")[0]
    for k, c in BY_KEY.items():
        if "`" + k.split("(")[0] in head:
            return ("ok", c)
    return ("500",)


def mkcfg(name="cfg.json", **over):
    cfg = {"max_cards": 6, "max_requests_per_night": 12, "exec_timeout": 60, "lock_file": "run.lock", "gpu_busy_markers": ["art_window.hold", "gpu_wait"],
           "base_refs": ["HEAD"], "llm": {}, "repos": {REPO: {"progress_files": ["OVERNIGHT_PROGRESS.md"], "path_allow": ["."], "path_deny": []}}}
    cfg.update(over)
    p = os.path.join(T, name)
    json.dump(cfg, open(p, "w"))
    return p


PYBIN = os.path.dirname(sys.executable)
MINPATH = PYBIN + ":/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
_ovn_n = [0]


def fresh_ovn():
    _ovn_n[0] += 1
    d = os.path.join(T, "ovn%d" % _ovn_n[0])
    os.makedirs(os.path.join(d, "state"))
    return d


def cli(script, args, ovn, extra_env=None, qa=QA, timeout=240):
    env = {"PATH": MINPATH, "NTFY_SERVER": "http://127.0.0.1:9/relay", "OVN_DIR": ovn, "OVN_REPOS_DIR": REPOS, "HOME": T, "LITELLM_MASTER_KEY": SECRET}
    env.update(extra_env or {})
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, os.path.join(qa, script)] + list(args)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        res = {"verdict": "?", "summary": "unparseable output: " + p.stdout[-300:] + p.stderr[-300:], "details": {}}
    return p, res


def rows(ovn, name="card_pilot.jsonl"):
    out = []
    try:
        for line in open(os.path.join(ovn, "state", "qa_shadow", name)):
            out.append(json.loads(line))
    except OSError:
        pass
    return out


def card_rows(ovn):
    return [r for r in rows(ovn) if r.get("kind") == "card"]


def run_pilot(ovn, cfg=None, args=(), env=None, qa=QA, responder=by_item, url=URL):
    Fake.responder = responder
    Fake.seen = []
    return cli("card_pilot_run.py", ["run", "--config", cfg or mkcfg(), "--llm-url", url] + list(args), ovn, env, qa)


def mutate(path, old, new):
    s = open(path).read()
    assert s.count(old) == 1, "mutation anchor not unique/present in %s: %r (%d)" % (path, old, s.count(old))
    open(path, "w").write(s.replace(old, new))


def mutant_qa(name):
    d = os.path.join(T, name)
    shutil.copytree(QA, d, ignore=shutil.ignore_patterns("__pycache__", "device_lane", "spikes", "acceptance_pilot"))
    return d


# ======================================================================================================================== 1. dry run + selection
print("selection: allow-list, scope, dedupe, caps")
ovn = fresh_ovn()
p, res = run_pilot(ovn, args=["--dry-run"])
ok("dry run: exit 0, NA, no model call, no card row", p.returncode == 0 and res["verdict"] == "NA" and not Fake.seen and not card_rows(ovn), res)
items = [d["desc"][:30] for d in res["details"].get("dry_run_items", [])]
ok("dry run selects only the eligible python items (5), not GDScript/Swift/Kotlin/Vue, not [x], not HUMAN-ONLY", res["details"].get("selected") == 5, res["details"])
ok("out-of-scope reasons are counted", sum(res["details"]["excluded"].values()) >= 4, res["details"]["excluded"])

# ======================================================================================================================== 2. the main run
print("run: good card / swallowed status / existence-only / weak (passes before the change)")
ovn = fresh_ovn()
p, res = run_pilot(ovn)
rs = card_rows(ovn)
ok("run: exit 0 and a PASS summary", p.returncode == 0 and res["verdict"] == "PASS" and res["details"]["cards"] == 5, res)
ok("one model request per card, none for out-of-scope items", len(Fake.seen) == 5 and not any(x in " ".join(Fake.seen) for x in ("take_damage", "View.swift", "greet", "textarea")), len(Fake.seen))
by = {r["path"] + "|" + r["desc"][:12]: r for r in rs}
good = next(r for r in rs if "slugify" in r["desc"])
echo = next(r for r in rs if "titlecase" in r["desc"])
exist = next(r for r in rs if "shout" in r["desc"])
weak = next(r for r in rs if "Update `existing" in r["desc"])
ok("good card: PASS, lint-clean, fails before the change", good["verdict"] == "PASS" and good["lint_ok"] and good["fail_before"] and not good["weak"], good)
ok("`|| echo` card is REJECTED by lint (FAIL: swallow-or-handler), lint_ok false", echo["verdict"] == "FAIL" and not echo["lint_ok"] and "swallow-or-handler" in echo["lint_errors"], echo)
ok("existence-only card (`test -e`) is REJECTED (existence-only)", exist["verdict"] == "FAIL" and "existence-only" in exist["lint_errors"], exist)
ok("a card whose verify passes BEFORE the change is flagged weak (FLAG)", weak["verdict"] == "FLAG" and weak["weak"] is True and weak["exec_outcome"] == "passed", weak)
ok("rows carry verdict, lint errors, ms, model call count, GPU seconds", all(r["model_calls"] == 1 and r["gpu_s"] == 1.5 and isinstance(r["ms"], int) and "lint_errors" in r and r["night"] for r in rs), rs[0])
ok("the API key never reaches stdout/stderr/state", SECRET not in p.stdout + p.stderr and SECRET not in open(os.path.join(ovn, "state", "qa_shadow", "card_pilot.jsonl")).read())
ok("a run summary row is also logged (gate card_pilot)", any(r.get("gate") == "card_pilot" and (r.get("details") or {}).get("run") for r in rows(ovn)))
p, res = run_pilot(ovn)
ok("second run the same night: already-carded items are not re-drafted (zero requests)", res["verdict"] == "NA" and not Fake.seen, (res, len(Fake.seen)))
p, res = run_pilot(fresh_ovn(), args=["--max-cards", "2"])
ok("--max-cards 2 writes exactly 2 cards", res["details"]["cards"] == 2 and len(Fake.seen) == 2, res["details"])
p, res = run_pilot(fresh_ovn(), cfg=mkcfg("cfg_cap6.json", max_cards=3))
ok("config max_cards 3 is honoured", res["details"]["cards"] == 3, res["details"])

# ======================================================================================================================== 3. out of scope = zero model calls
print("scope: GDScript / Swift / Kotlin / Vue cost nothing")
cl_prog = os.path.join(T, "oos_prog")
oos_repo = os.path.join(REPOS, "oos-repo")
shutil.copytree(CLONE, oos_repo)
subprocess.run(["git", "-C", oos_repo, "checkout", "-q", "develop"], capture_output=True, env=GENV)
open(os.path.join(oos_repo, "OVERNIGHT_PROGRESS.md"), "w").write("# p\n" + "".join("- [ ] [T2] %s\n" % x for x in OUT_OF_SCOPE + ["docs/NOTES.md — Add a section about retries"]))
subprocess.run(["git", "-C", oos_repo, "commit", "-q", "-am", "oos"], capture_output=True, env=GENV)
cfg_oos = mkcfg("cfg_oos.json", repos={"oos-repo": {"progress_files": ["OVERNIGHT_PROGRESS.md"], "path_allow": ["."], "path_deny": []}})
p, res = run_pilot(fresh_ovn(), cfg=cfg_oos)
ok("only out-of-scope items: NA, zero model calls, no card rows", res["verdict"] == "NA" and not Fake.seen, (res, len(Fake.seen)))
ok("the exclusion reasons name the language", any("GDScript" in k or "Swift" in k or "Kotlin" in k or "Vue" in k or "UI" in k for k in res["details"]["excluded"]) or sum(res["details"]["excluded"].values()) >= 5, res["details"]["excluded"])

# ======================================================================================================================== 4. non-loopback refusal
print("loopback only")
ovn = fresh_ovn()
p, res = run_pilot(ovn, url="http://192.0.2.1:4000")
ok("non-loopback URL: UNVERIFIED, exit 0, refused with zero calls and no rows", p.returncode == 0 and res["verdict"] == "UNVERIFIED" and "non-loopback" in res["summary"] and not Fake.seen and not card_rows(ovn), res)
p, res = run_pilot(fresh_ovn(), url="http://localhost.evil.example:4000")
ok("a look-alike hostname is refused too", res["verdict"] == "UNVERIFIED" and "non-loopback" in res["summary"], res)

# ======================================================================================================================== 5. model failure is UNVERIFIED, not an error
print("model failure")
ovn = fresh_ovn()
p, res = run_pilot(ovn, responder=lambda pr: ("500",))
rs = card_rows(ovn)
ok("model 500s: exit 0, UNVERIFIED (not an error)", p.returncode == 0 and res["verdict"] == "UNVERIFIED" and res["details"]["cards"] == 0, res)
ok("it stops after 2 consecutive failed items (2 attempts each = 4 requests), rows are UNVERIFIED with the reason", len(Fake.seen) == 4 and len(rs) == 2 and all(r["verdict"] == "UNVERIFIED" and r["llm_error"] for r in rs), (len(Fake.seen), rs))
p, res = run_pilot(ovn, responder=by_item)
ok("failed (UNVERIFIED, no card) items are retried on the next run", res["verdict"] == "PASS" and res["details"]["cards"] >= 3, res)
p, res = run_pilot(fresh_ovn(), responder=lambda pr: ("garbage",))
ok("unparseable model output: UNVERIFIED, exit 0", p.returncode == 0 and res["verdict"] == "UNVERIFIED", res)

# ======================================================================================================================== 6. night cap
print("per-night request cap")
CAP = 3
ovn = fresh_ovn()
cfg_cap = mkcfg("cfg_cap.json", max_requests_per_night=CAP)
p, res = run_pilot(ovn, cfg=cfg_cap)
ok("cap 3: at most 3 model requests, run stops with the cap reason", len(Fake.seen) == CAP and res["details"]["cards"] == CAP, (len(Fake.seen), res["details"]))
p, res = run_pilot(ovn, cfg=cfg_cap)
n_rows_before = len(card_rows(ovn))
p, res = run_pilot(ovn, cfg=cfg_cap)
ok("a second run the same night is UNVERIFIED with ZERO model calls (cap already used), stopped by the UP-FRONT check, no rows written",
   res["verdict"] == "UNVERIFIED" and not Fake.seen and "already reached" in res["summary"] and len(card_rows(ovn)) == n_rows_before, res)
ovn = fresh_ovn()
p, res = run_pilot(ovn, cfg=cfg_cap, responder=lambda pr: ("500",))
ok("failed attempts and retries count against the cap (never more than 3 requests even when every call fails)", len(Fake.seen) <= CAP, len(Fake.seen))

# ======================================================================================================================== 7. fleet-idle discipline
print("fleet idle: run.lock / GPU-wait marker")
lockdir = os.path.join(T, "lockproc")
os.makedirs(lockdir)
ovn = fresh_ovn()
lockfile = os.path.join(ovn, "state", "run.lock")
holder = subprocess.Popen([sys.executable, "-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(120)", lockfile],
                          stdout=subprocess.PIPE, text=True)
holder.stdout.readline()
have_probe = bool(shutil.which("fuser") or shutil.which("lsof"))
try:
    p, res = run_pilot(ovn)
    probe_works = "run.lock is held" in res["summary"]
    if have_probe:
        ok("run.lock held by another process: UNVERIFIED, ZERO model calls, no rows", res["verdict"] == "UNVERIFIED" and "run.lock" in res["summary"] and not Fake.seen and not card_rows(ovn), res)
    else:
        ok("no fuser/lsof: the idle check fails CLOSED (skips, zero model calls)", res["verdict"] == "UNVERIFIED" and not Fake.seen, res)
finally:
    holder.kill()
    holder.wait()
if have_probe and probe_works:
    p, res = run_pilot(ovn)
    ok("lock released: the same state runs normally (the probe did not leave the lock taken)", res["verdict"] == "PASS", res)
ovn = fresh_ovn()
open(os.path.join(ovn, "state", "art_window.hold"), "w").write("")
p, res = run_pilot(ovn)
ok("GPU-wait/art-window marker present: UNVERIFIED, zero model calls", res["verdict"] == "UNVERIFIED" and "marker" in res["summary"] and not Fake.seen, res)
src = open(os.path.join(QA, "card_pilot_run.py")).read()
code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
lh = code[code.index("def lock_held"):code.index("def _process_running")]
ok("the pilot never locks run.lock/hygiene.lock: lock_held is read-only, the only flocks are on its OWN card_pilot.lock / card_credit.lock slots",
   "fcntl" not in lh and "O_CREAT" not in lh and 'RunLock(os.path.join(qc.state_dir(), "card_pilot.lock"))' in code and 'card_credit.lock' in code
   and "lockf(" not in code and "acquire_lock" not in code and code.count("fcntl.flock(") == 2)

# ======================================================================================================================== 8. mode flag
print("OVN_QA_CARD_PILOT")
ovn = fresh_ovn()
p, res = run_pilot(ovn, env={"OVN_QA_CARD_PILOT": "off"})
ok("off: NA, zero model calls, nothing written", p.returncode == 0 and res["verdict"] == "NA" and not Fake.seen and not rows(ovn), res)
ovn = fresh_ovn()
p, res = run_pilot(ovn, env={"OVN_QA_CARD_PILOT": "enforce"}, args=["--enforce-exit"])
ok("enforce is accepted but behaves as shadow: exit 0, cards written, the summary says so", p.returncode == 0 and res["verdict"] == "PASS" and len(card_rows(ovn)) == 5 and "no enforce path" in (res["details"].get("mode_note") or ""), res)
ovn = fresh_ovn()
json.dump({"card_pilot": "off"}, open(os.path.join(ovn, "state", "qa_gate_modes.json"), "w"))
p, res = run_pilot(ovn)
ok("the state/qa_gate_modes.json flip file is honoured (off)", res["verdict"] == "NA" and not Fake.seen, res)
ok("the shipped config parses and names both pilot areas", set(json.load(open(os.path.join(QA, "card_pilot.json")))["repos"]) == {"test-automation-agent", "iptv_apps"})

# ======================================================================================================================== 9. real config selection (allow-list, iptv entitlement area)
print("allow-list")
ip = os.path.join(REPOS, "iptv_apps")
os.makedirs(os.path.join(ip, "iptv-backend", "app", "routers"))
open(os.path.join(ip, "iptv-backend", "app", "routers", "subscription.py"), "w").write("def a():\n    return 1\n")
open(os.path.join(ip, "iptv-backend", "app", "routers", "channels.py"), "w").write("def b():\n    return 1\n")
open(os.path.join(ip, "OVERNIGHT_PROGRESS.md"), "w").write("# p\n- [ ] [T3] iptv-backend/app/routers/subscription.py — Modify `revenuecat_webhook` to return `{\"status\": \"stale\"}` for an out-of-order event\n"
                                                            "- [ ] [T2] iptv-backend/app/routers/channels.py — Add `list_channels()` that returns a list of names\n"
                                                            "- [ ] [T2] iptv-android/app/src/main/java/X/RevenueCatManager.kt — Replace the entitlement id constant\n")
subprocess.run(["git", "-C", ip, "init", "-q", "-b", "develop"], capture_output=True, env=GENV)
subprocess.run(["git", "-C", ip, "add", "-A"], capture_output=True, env=GENV)
subprocess.run(["git", "-C", ip, "commit", "-q", "-m", "x"], capture_output=True, env=GENV)
real = json.load(open(os.path.join(QA, "card_pilot.json")))
real["base_refs"] = ["HEAD"]
cfg_real = os.path.join(T, "cfg_real.json")
json.dump(real, open(cfg_real, "w"))
p, res = run_pilot(fresh_ovn(), cfg=cfg_real, args=["--dry-run", "--repo", "iptv_apps"])
sel = res["details"].get("dry_run_items", [])
ok("iptv: only the entitlement/RevenueCat backend item is selected (not channels.py, not Kotlin)", len(sel) == 1 and "revenuecat_webhook" in sel[0]["desc"], res["details"])

# ======================================================================================================================== 10. MUTANTS
print("mutants: the tests must see these defects")
def existence_rejected(qa):
    ovn_m = fresh_ovn()
    run_pilot(ovn_m, qa=qa)
    r = next((x for x in card_rows(ovn_m) if "shout" in x["desc"]), None)
    return bool(r) and r["verdict"] == "FAIL" and "existence-only" in r["lint_errors"]


ok("[control] unmodified linter rejects the existence-only card", existence_rejected(QA))
mq = mutant_qa("mut_lint")
mutate(os.path.join(mq, "card_lint.py"), 'out.append(_f("existence-only", "error",', 'out.append(_f("existence-only", "flag",')
ok("[mutant] linter's existence-only rule broken -> the rejection assertion FAILS (defect is detected)", not existence_rejected(mq))

mq = mutant_qa("mut_cap")
mutate(os.path.join(mq, "card_pilot_run.py"), "        if self.left() <= 0:\n            self.exhausted = True", "        if False:\n            self.exhausted = True")
mutate(os.path.join(mq, "card_pilot_run.py"), "            if bud.left() <= 0:\n                stop =", "            if False:\n                stop =")
ovn_m = fresh_ovn()
run_pilot(ovn_m, cfg=cfg_cap, qa=mq)
ok("[mutant] per-night cap check removed -> more than 3 requests are sent (the cap test would fail)", len(Fake.seen) > CAP, len(Fake.seen))

mq = mutant_qa("mut_idle")
mutate(os.path.join(mq, "card_pilot_run.py"), "        if h is True:\n            return \"%s is held", "        if False:\n            return \"%s is held")
ovn_m = fresh_ovn()
lf = os.path.join(ovn_m, "state", "run.lock")
holder = subprocess.Popen([sys.executable, "-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(120)", lf], stdout=subprocess.PIPE, text=True)
holder.stdout.readline()
try:
    run_pilot(ovn_m, qa=mq)
    ok("[mutant] run.lock check removed -> the pilot runs while the lock is held (the idle test would fail)", (not have_probe) or bool(Fake.seen), len(Fake.seen))
finally:
    holder.kill()
    holder.wait()

# ======================================================================================================================== 11. report
print("report: reproduces the acceptance pilot's lint pass rate; sample sheet")
FIX = os.path.join(QA, "acceptance_pilot", "taa_norepair_cards.jsonl")
rep_state = fresh_ovn()
out_dir = os.path.join(T, "rep_out")
p = subprocess.run([sys.executable, os.path.join(QA, "card_pilot_report.py"), "--state-dir", os.path.join(rep_state, "state"), "--no-state", "--input", FIX, "--out", out_dir],
                   capture_output=True, text=True, env={"PATH": MINPATH, "HOME": T})
m = json.loads(p.stdout.strip().splitlines()[-1])
ok("report on the 30-card TAA fixture: lint pass rate 21/30 = 0.7 (the pilot's own number)", p.returncode == 0 and m["cards"] == 30 and m["lint_pass"] == 21 and m["lint_pass_rate"] == 0.7, m)
ok("fail-before rate, GPU minutes per card and class A share are computed", m["fail_before"] == 21 and m["fail_before_rate"] == 0.7 and m["gpu_min_per_card"] is not None and m["class_a_share"] == 0.7, m)
sheet = open(os.path.join(out_dir, "card_sample.md")).read()
ok("sample sheet holds 20 class A cards (## 1 .. ## 20, no 21st)", "\n## 20. " in sheet and "\n## 21. " not in sheet and m["sample_cards"] == 20, m["sample_cards"])
ok("nothing is auto-approved: every decision box is empty, no ticked box", sheet.count("Decision: [ ] sensible") == 20 and "[x]" not in sheet.lower().replace("sensible", ""), sheet[:200])
ok("the report writes only card_sample.md (no other state)", os.listdir(out_dir) == ["card_sample.md"], os.listdir(out_dir))
rr = json.loads(open(os.path.join(rep_state, "state", "qa_shadow", "card_pilot.jsonl")).read().splitlines()[-1]) if os.path.exists(os.path.join(rep_state, "state", "qa_shadow", "card_pilot.jsonl")) else None
ok("the report did not write into the shadow log", rr is None)
ovn = fresh_ovn()
run_pilot(ovn)
p = subprocess.run([sys.executable, os.path.join(QA, "card_pilot_report.py"), "--state-dir", os.path.join(ovn, "state"), "--out", os.path.join(T, "rep2")], capture_output=True, text=True,
                   env={"PATH": MINPATH, "HOME": T})
m = json.loads(p.stdout.strip().splitlines()[-1])
ok("report on the pilot's own rows: 5 cards, lint 3/5 pass (good, weak, auth are lint-clean)", m["cards"] == 5 and m["lint_pass"] == 3 and m["lint_pass_rate"] == 0.6, m)
ok("weak (verify already passes at base: `|| echo`, `test -e`, existing() = 3 cards) is counted; fail-before counts the good + auth cards", m["weak_passes_before"] == 3 and m["fail_before"] == 2, m)
ok("GPU minutes per card from timings: 1.5 s = 0.025 min", m["gpu_min_per_card"] == 0.025, m)
ok("class A: the auth item is floored to A by the linter (1 of 5)", m["class_a"] == 1 and m["class_a_share"] == 0.2, m)
sheet = open(os.path.join(T, "rep2", "card_sample.md")).read()
ok("a short sample is labelled as a shortfall instead of padded", "Shortfall" in sheet and "check_token" in sheet, sheet[:300])
p = subprocess.run([sys.executable, os.path.join(QA, "card_pilot_report.py"), "--state-dir", os.path.join(fresh_ovn(), "state"), "--out", os.path.join(T, "rep3")], capture_output=True, text=True,
                   env={"PATH": MINPATH, "HOME": T})
ok("report on an empty state dir: exit 0, no crash, 0 cards", p.returncode == 0 and json.loads(p.stdout.strip().splitlines()[-1])["cards"] == 0, p.stdout + p.stderr)

# ======================================================================================================================== 12. S2 credit advisory (python half)
print("credit advisory: credit_without_card / verify at head")
ovn = fresh_ovn()
run_pilot(ovn)           # leaves cards for the 5 python items
LINE = "- [ ] [T2] " + I_GOOD
LINE_NOCARD = "- [ ] [T2] app/util.py — Add `never_carded()` that returns 7"


def credit(line, head, ovn_, env=None):
    return cli("card_pilot_run.py", ["credit", "--repo", REPO, "--head", head, "--item", line, "--exec-timeout", "60"], ovn_, env)


p, res = credit(LINE, HEAD, ovn)
ok("card exists and its verify passes at the head that added slugify -> PASS, verify_passed_at_head", res["verdict"] == "PASS" and res["details"]["card_existed"] is True
   and res["details"]["verify_passed_at_head"] is True and res["details"]["credit_without_card"] is False, res)
p, res = credit(LINE, BASE, ovn)
ok("card exists but its verify FAILS at head -> FLAG (advisory only), verify_passed_at_head false", res["verdict"] == "FLAG" and res["details"]["verify_passed_at_head"] is False, res)
p, res = credit(LINE_NOCARD, HEAD, ovn)
ok("no card for the credited item -> credit_without_card", res["details"]["credit_without_card"] is True and res["details"]["card_existed"] is False and "credit_without_card" in res["summary"], res)
p, res = credit(LINE_NOCARD, HEAD, ovn)
cc = rows(ovn, "card_credit.jsonl")
ok("rows land in state/qa_shadow/card_credit.jsonl (gate card_credit), default mode shadow", len(cc) == 4 and all(r["gate"] == "card_credit" and r["mode"] == "shadow" for r in cc), cc[:1])
n0 = len(cc)
p, res = credit(LINE, HEAD, ovn, {"OVN_QA_CARD_CREDIT": "off"})
ok("OVN_QA_CARD_CREDIT=off: nothing logged", len(rows(ovn, "card_credit.jsonl")) == n0 and res["verdict"] == "NA", res)
ok("a card whose lint rejected it is never executed at head", credit("- [ ] [T2] " + I_EXIST, HEAD, ovn)[1]["verdict"] == "FLAG"
   and "exec" not in credit("- [ ] [T2] " + I_EXIST, HEAD, ovn)[1]["details"])
p, res = cli("card_pilot_run.py", ["credit", "--repo", REPO, "--head", HEAD, "--item", "garbage line"], ovn)
ok("an unparseable item line: UNVERIFIED, exit 0", p.returncode == 0 and res["verdict"] == "UNVERIFIED", res)

# ======================================================================================================================== 13. REPAIR (review of a5fac0b): leaks, idle signals, mutants, serialisation, parking
print("repair: SIGTERM cleanup (no leaked worktree / temp dirs / orphaned verify)")
import importlib.util
import signal
import tempfile as _tf
sys.path.insert(0, QA)


def load_mod(qa_dir, name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(qa_dir, "card_pilot_run.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


cpr = load_mod(QA, "cpr_real")
KEY_SLUG = cpr.item_key(*[cpr.cl.parse_item_line("- [ ] [T2] " + I_GOOD)[k] for k in ("path", "desc")])


def write_rows(ovn_, rs, name="card_pilot.jsonl"):
    d = os.path.join(ovn_, "state", "qa_shadow")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name), "a") as f:
        for r in rs:
            f.write(json.dumps(r) + "\n")


def leak_case(qa_dir):
    """credit check whose verify sleeps; SIGTERM it (what `timeout 180` does). Returns (started, leftover scratch dirs, worktree count, verify still alive)."""
    ovn_l = fresh_ovn()
    tdir = os.path.join(T, "tmp_leak_%d" % _ovn_n[0])
    os.makedirs(tdir)
    tag = "zzleakmark%d_%d" % (os.getpid(), _ovn_n[0])
    verify = "python -c \"import time; time.sleep(90)  # %s\"" % tag
    write_rows(ovn_l, [{"kind": "card", "repo": REPO, "item_key": KEY_SLUG, "night": "x", "verdict": "PASS", "lint_ok": True,
                        "card": {"verify_cmd": verify, "bullets": [], "files": ["app/util.py"], "risk_class": "C"}}])
    env = {"PATH": MINPATH, "OVN_DIR": ovn_l, "OVN_REPOS_DIR": REPOS, "HOME": T, "TMPDIR": tdir}
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, os.path.join(qa_dir, "card_pilot_run.py"), "credit", "--repo", REPO, "--repo-path", CLONE,
                                                                  "--head", HEAD, "--item", "- [ ] [T2] " + I_GOOD, "--exec-timeout", "120"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def sleeper_pids():
        r_ = subprocess.run(["pgrep", "-f", tag], capture_output=True, text=True)
        return [x for x in r_.stdout.split() if x != str(os.getpid())]
    t_end = time.time() + 60
    while time.time() < t_end and not sleeper_pids():
        time.sleep(0.2)
    time.sleep(0.5)
    started = bool(sleeper_pids())
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    time.sleep(0.5)
    left = [n for n in os.listdir(tdir) if n.startswith(("qa-wt-", "qa-acc-home-"))]
    wts = [l for l in g("worktree", "list").stdout.splitlines() if l.strip()]
    pids = sleeper_pids()
    alive = bool(pids)
    for x in pids:
        try:
            os.kill(int(x), signal.SIGKILL)
        except OSError:
            pass
    return started, left, len(wts), alive


started, left, nwt, alive = leak_case(QA)
ok("verify started before the SIGTERM (the test really interrupts a running check)", started)
ok("SIGTERM mid-verify: no qa-wt-*/qa-acc-home-* directory is left behind", not left, left)
ok("SIGTERM mid-verify: no leaked git worktree entry (only the main checkout remains)", nwt == 1, nwt)
ok("SIGTERM mid-verify: the verify process (own session) is killed, not orphaned", not alive)
mq = mutant_qa("mut_term")
mutate(os.path.join(mq, "card_pilot_run.py"), "    qc.install_term_handlers()", "    pass")
started, left, nwt, alive = leak_case(mq)
ok("[mutant] SIGTERM handler removed -> the leak is detected (dirs / worktree / process left)", started and (bool(left) or nwt > 1 or alive), (left, nwt, alive))
g("worktree", "prune")

print("repair: stale scratch sweep + budget arithmetic")
d_sw = os.path.join(T, "sweep_tmp")
os.makedirs(os.path.join(d_sw, "qa-wt-old", "wt"))
os.makedirs(os.path.join(d_sw, "qa-wt-new"))
os.makedirs(os.path.join(d_sw, "qa-acc-home-old"))
os.makedirs(os.path.join(d_sw, "unrelated-old"))
os.makedirs(os.path.join(T, "sweep_target"))
os.symlink(os.path.join(T, "sweep_target"), os.path.join(d_sw, "qa-wt-link"))
old = time.time() - 4 * 3600
for n in ("qa-wt-old", "qa-acc-home-old", "unrelated-old"):
    os.utime(os.path.join(d_sw, n), (old, old))
os.utime(os.path.join(d_sw, "qa-wt-link"), (old, old), follow_symlinks=False)
_old_td = _tf.tempdir
_tf.tempdir = d_sw
try:
    import qa_common as _qc
    nrem = _qc.sweep_stale_scratch(max_age_s=7200)
finally:
    _tf.tempdir = _old_td
left = sorted(os.listdir(d_sw))
ok("sweep removes old qa-wt-*/qa-acc-home-* dirs only (fresh, unrelated and symlinked ones stay, symlink target untouched)",
   nrem == 2 and left == ["qa-wt-link", "qa-wt-new", "unrelated-old"] and os.path.isdir(os.path.join(T, "sweep_target")), (nrem, left))
hook_src = open(os.path.join(QUEUE, "scripts", "lib_auto_credit.sh")).read()
ok("the hook's outer timeout matches the constant and sends a hard kill after a grace period (timeout -k)", hook_src.count("timeout -k 30 %d python3" % cpr.HOOK_TIMEOUT) == 2, cpr.HOOK_TIMEOUT)
tot = cpr.CREDIT_WT_TIMEOUT + cpr.CREDIT_PROBE_TIMEOUT + cpr.CREDIT_EXEC_TIMEOUT + cpr.CREDIT_CLEANUP_BUDGET
ok("sum of the inner credit timeouts (worktree add + pytest probe + run + cleanup) stays below the hook's 180 s", tot < cpr.HOOK_TIMEOUT, tot)

print("repair: idle detection beyond run.lock")
have_pgrep = bool(shutil.which("pgrep"))


def util_log(ovn_, pct, age):
    open(os.path.join(ovn_, "state", "gpu_util.log"), "w").write("%d %d 23629\n" % (time.time() - age, pct))


ovn = fresh_ovn()
util_log(ovn, 90, 60)
p, res = run_pilot(ovn)
ok("a fresh high gpu_util.log sample = busy: UNVERIFIED, zero model calls", res["verdict"] == "UNVERIFIED" and "gpu_util" in res["summary"] and not Fake.seen, res)
ovn = fresh_ovn()
util_log(ovn, 90, 7200)
p, res = run_pilot(ovn)
ok("a stale gpu_util.log sample is no signal (the pilot runs)", res["verdict"] == "PASS" and Fake.seen, res)
ovn = fresh_ovn()
util_log(ovn, 3, 60)
p, res = run_pilot(ovn)
ok("a fresh LOW sample is idle", res["verdict"] == "PASS", res)
if have_pgrep:
    tag = "zz_fake_planner_%d" % os.getpid()
    sl = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)", tag])
    try:
        time.sleep(0.5)
        ovn = fresh_ovn()
        p, res = run_pilot(ovn, cfg=mkcfg("cfg_proc.json", busy_process_patterns=[tag]))
        ok("an LLM-using child that outlives run.lock (matched by pgrep -f) = busy: zero model calls", res["verdict"] == "UNVERIFIED" and "fleet process" in res["summary"] and not Fake.seen, res)
    finally:
        sl.kill()
        sl.wait()
    p, res = run_pilot(fresh_ovn(), cfg=mkcfg("cfg_proc2.json", busy_process_patterns=[tag]))
    ok("the same pattern with nothing running is idle", res["verdict"] == "PASS", res)
ovn = fresh_ovn()
hl = os.path.join(ovn, "state", "hygiene.lock")
holder = subprocess.Popen([sys.executable, "-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(120)", hl],
                          stdout=subprocess.PIPE, text=True)
holder.stdout.readline()
try:
    p, res = run_pilot(ovn, cfg=mkcfg("cfg_hyg.json", extra_locks=["hygiene.lock"]))
    ok("hygiene.lock held (branch-hygiene LLM review) = busy: zero model calls", (not have_probe) or (res["verdict"] == "UNVERIFIED" and "hygiene.lock" in res["summary"] and not Fake.seen), res)
finally:
    holder.kill()
    holder.wait()
shipped = json.load(open(os.path.join(QA, "card_pilot.json")))
ok("the shipped config drops the marker names nothing writes and adds hygiene.lock + the child patterns",
   shipped["gpu_busy_markers"] == ["coder_window.hold"] and "hygiene.lock" in shipped["extra_locks"] and any("planner" in x for x in shipped["busy_process_patterns"]), shipped)


def unknown_state(qa):
    ovn_u = fresh_ovn()
    open(os.path.join(ovn_u, "state", "run.lock"), "w").write("")
    pr, rs_ = run_pilot(ovn_u, qa=qa, env={"PATH": "/nonexistent"}, args=["--dry-run"])
    return "unknown" in rs_["summary"]


ok("[control] no fuser/lsof: an existing run.lock of unknown state = busy", unknown_state(QA))
mq = mutant_qa("mut_unknown")
mutate(os.path.join(mq, "card_pilot_run.py"), "        if h is None:\n            return \"%s state unknown", "        if False:\n            return \"%s state unknown")
ok("[mutant] unknown treated as idle -> detected", not unknown_state(mq))

print("repair: idle re-check between cards and before every request")


def mid_run_busy(qa):
    """The fake model grabs run.lock after its FIRST answer (a fleet cycle starts mid-pilot)."""
    ovn_m = fresh_ovn()
    lf_ = os.path.join(ovn_m, "state", "run.lock")
    holders = []

    def resp(prompt):
        r = by_item(prompt)
        if not holders:
            hp = subprocess.Popen([sys.executable, "-c", "import fcntl,sys,time\nf=open(sys.argv[1],'w'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(120)", lf_],
                                  stdout=subprocess.PIPE, text=True)
            hp.stdout.readline()
            holders.append(hp)
        return r
    try:
        pr, rs_ = run_pilot(ovn_m, qa=qa, responder=resp)
    finally:
        for hp in holders:
            hp.kill()
            hp.wait()
    return rs_, len(Fake.seen)


if have_probe:
    rs_, nseen = mid_run_busy(QA)
    ok("the fleet starts mid-run: the pilot stops after the card in flight (<= 1 request) and says so", nseen == 1 and "busy" in (rs_["details"].get("stopped") or ""), (nseen, rs_["details"]))
    mq = mutant_qa("mut_mid")
    mutate(os.path.join(mq, "card_pilot_run.py"), "            if n:\n                busy = fleet_busy(cfg)", "            if False:\n                busy = fleet_busy(cfg)")
    mutate(os.path.join(mq, "card_pilot_run.py"), "        if self.idle_fn:  ", "        if False:  ")
    rs_, nseen = mid_run_busy(mq)
    ok("[mutant] both mid-run idle re-checks removed -> the run keeps spending GPU (detected)", nseen > 1, nseen)
    mq = mutant_qa("mut_mid2")
    mutate(os.path.join(mq, "card_pilot_run.py"), "            if n:\n                busy = fleet_busy(cfg)", "            if False:\n                busy = fleet_busy(cfg)")
    rs_, nseen = mid_run_busy(mq)
    ok("the per-request check alone still stops it (defence in depth)", nseen == 1, nseen)

print("repair: path_deny, re-lint of stored commands, night key, round-robin")
rc_ = {"path_allow": ["^backend/.*\\.py$"], "path_deny": ["(^|/)alembic/env\\.py$"]}
ok("path_deny wins over path_allow (alembic/env.py is never carded)", cpr.in_allow_list({"path": "backend/alembic/env.py", "desc": "x"}, rc_) is False
   and cpr.in_allow_list({"path": "backend/app/x.py", "desc": "x"}, rc_) is True)
mq = mutant_qa("mut_deny")
mutate(os.path.join(mq, "card_pilot_run.py"), '    if any(re.search(p, path) for p in rcfg.get("path_deny") or []):\n        return False', "    pass")
mm = load_mod(mq, "cpr_mut_deny")
ok("[mutant] path_deny ignored -> detected", mm.in_allow_list({"path": "backend/alembic/env.py", "desc": "x"}, rc_) is True)

t_late = time.mktime((2026, 10, 16, 23, 0, 0, 0, 0, -1))
t_early = time.mktime((2026, 10, 17, 4, 0, 0, 0, 0, -1))
ok("night_key: 23:00 and 04:00 of the next day share one night", cpr.night_key(t_late) == cpr.night_key(t_early) == "2026-10-16", (cpr.night_key(t_late), cpr.night_key(t_early)))
mq = mutant_qa("mut_night")
mutate(os.path.join(mq, "card_pilot_run.py"), "(time.time() if now is None else now) - 12 * 3600", "(time.time() if now is None else now) - 0 * 3600")
mm = load_mod(mq, "cpr_mut_night")
ok("[mutant] the 12 h shift removed -> detected", mm.night_key(t_late) != mm.night_key(t_early))

ovn = fresh_ovn()
UNSAFE = "touch app/EVIL_MARK"
write_rows(ovn, [{"kind": "card", "repo": REPO, "item_key": KEY_SLUG, "night": "x", "verdict": "PASS", "lint_ok": True,
                  "card": {"verify_cmd": UNSAFE, "bullets": [], "files": ["app/util.py"], "risk_class": "C"}}])


def relint(qa):
    pr, rs_ = cli("card_pilot_run.py", ["credit", "--repo", REPO, "--repo-path", CLONE, "--head", HEAD, "--item", "- [ ] [T2] " + I_GOOD], ovn, qa=qa)
    return rs_


r_ = relint(QA)
ok("a stored verify_cmd that fails the CURRENT safety lint is never executed (FLAG, no exec)", r_["verdict"] == "FLAG" and "safety lint" in r_["summary"] and "exec" not in r_["details"], r_)
mq = mutant_qa("mut_relint")
mutate(os.path.join(mq, "card_pilot_run.py"), 'if any(x["severity"] == "error" and x["rule"] in ac.UNSAFE_RULES for x in f):', "if False:")
r_ = relint(mq)
ok("[mutant] the re-lint removed -> the stored command would be executed (detected)", "exec" in r_["details"], r_)

rr_repo = os.path.join(REPOS, "rr-repo")
if not os.path.isdir(rr_repo):
    shutil.copytree(CLONE, rr_repo)
os.environ["OVN_REPOS_DIR"] = REPOS
os.environ["OVN_DIR"] = fresh_ovn()
cfg_rr = cpr.load_config(mkcfg("cfg_rr.json", base_refs=["HEAD"], repos={REPO: {"progress_files": ["OVERNIGHT_PROGRESS.md"], "path_allow": ["."], "path_deny": []},
                                                                     "rr-repo": {"progress_files": ["OVERNIGHT_PROGRESS.md"], "path_allow": ["."], "path_deny": []}}))
picks, _ex = cpr.pick_items(cfg_rr, None, [], 4)
ok("round-robin: the first 2 picks come from different repos (one repo cannot starve the other)", len({x[0] for x in picks[:2]}) == 2, [x[0] for x in picks])
mq = mutant_qa("mut_rr")
mutate(os.path.join(mq, "card_pilot_run.py"), "    out = []\n    i = 0\n    while len(out) < limit", "    per = [sum(per, [])]\n    out = []\n    i = 0\n    while len(out) < limit")
mm = load_mod(mq, "cpr_mut_rr")
picks, _ex = mm.pick_items(cfg_rr, None, [], 4)
ok("[mutant] sequential instead of round-robin -> detected", len({x[0] for x in picks[:2]}) == 1, [x[0] for x in picks])

print("repair: serialisation, killed-run accounting, corrupt rows")
import fcntl as _fc
ovn = fresh_ovn()
lkp = os.path.join(ovn, "state", "card_pilot.lock")
fd_l = os.open(lkp, os.O_RDWR | os.O_CREAT)
_fc.flock(fd_l, _fc.LOCK_EX)
p, res = run_pilot(ovn)
ok("an overlapping run (state/card_pilot.lock held) is UNVERIFIED with zero model calls: the night cap cannot be spent twice", res["verdict"] == "UNVERIFIED" and "in flight" in res["summary"] and not Fake.seen, res)
mq = mutant_qa("mut_lock")
mutate(os.path.join(mq, "card_pilot_run.py"), "        if lk is None:\n            return done(", "        if False:\n            return done(")
p, res = run_pilot(ovn, qa=mq)
ok("[mutant] lock check removed -> the overlapping run spends GPU (detected)", len(Fake.seen) > 0, res)
os.close(fd_l)
ovn = fresh_ovn()
open(os.path.join(ovn, "state", "card_pilot.lock"), "w").close()   # lock file present but no longer held
p, res = run_pilot(ovn)
ok("lock released: a run on a state with a stale lock FILE runs normally", res["verdict"] == "PASS", res)
calls = [r for r in rows(ovn) if r.get("kind") == "call"]
ok("one `call` row is written per model request (before the request)", len(calls) >= len(Fake.seen) and len(Fake.seen) > 0, (len(calls), len(Fake.seen)))

ovn = fresh_ovn()
write_rows(ovn, [{"kind": "call", "night": cpr.night_key(), "repo": REPO, "item_key": "k%d" % i} for i in range(12)])
p, res = run_pilot(ovn)
ok("requests of a run that was KILLED mid-item (call rows without a card row) still count against the night cap", res["verdict"] == "UNVERIFIED" and "already reached" in res["summary"] and not Fake.seen, res)
ovn = fresh_ovn()
write_rows(ovn, [{"kind": "card", "repo": REPO, "item_key": "zzz", "night": cpr.night_key(), "verdict": "UNVERIFIED", "model_calls": "twelve", "card": None},
                 {"kind": "card", "repo": REPO, "item_key": "yyy", "night": cpr.night_key(), "verdict": "UNVERIFIED", "model_calls": None, "card": None}])
p, res = run_pilot(ovn)
ok("a non-numeric model_calls row does not break every later run (no 'gate crashed')", "gate crashed" not in res["summary"] and res["verdict"] == "PASS", res)

print("repair: items that never produce a card go to the back, then are parked")
ovn = fresh_ovn()
fail_row = {"kind": "card", "repo": REPO, "item_key": KEY_SLUG, "night": "2026-01-01", "verdict": "UNVERIFIED", "card": None, "llm_error": "timeout", "model_calls": 2}
write_rows(ovn, [fail_row])
p, res = run_pilot(ovn, args=["--dry-run"])
order = [d["desc"] for d in res["details"]["dry_run_items"]]
ok("an item with a failed attempt is retried but LAST (the other items go first)", len(order) == 5 and "slugify" in order[-1] and "slugify" not in order[0], order)
mq = mutant_qa("mut_order")
mutate(os.path.join(mq, "card_pilot_run.py"), "        picks.sort(key=", "        (lambda *a, **k: None)(key=")
p, res = run_pilot(ovn, qa=mq, args=["--dry-run"])
order_m = [d["desc"] for d in res["details"]["dry_run_items"]]
ok("[mutant] attempt ordering removed -> the failing item heads the list again (detected)", "slugify" in order_m[0], order_m)
write_rows(ovn, [fail_row, fail_row])
p, res = run_pilot(ovn, args=["--dry-run"])
order = [d["desc"] for d in res["details"]["dry_run_items"]]
ok("after 3 failed attempts the item is PARKED (not selected, reason counted)", len(order) == 4 and not any("slugify" in x for x in order)
   and any("parked" in k for k in res["details"]["excluded"]), res["details"])
mq = mutant_qa("mut_park")
mutate(os.path.join(mq, "card_pilot_run.py"), "            if max_att > 0 and attempts", "            if False and attempts")
p, res = run_pilot(ovn, qa=mq, args=["--dry-run"])
ok("[mutant] parking removed -> detected", any("slugify" in d["desc"] for d in res["details"]["dry_run_items"]))
ovn = fresh_ovn()
cap_row = dict(fail_row, llm_error="night request cap reached (12)")
write_rows(ovn, [cap_row, cap_row, cap_row, dict(fail_row, llm_error="fleet busy: run.lock is held")])
p, res = run_pilot(ovn, args=["--dry-run"])
ok("attempts cut short by the night cap or a busy fleet are not the item's fault: never parked", len(res["details"]["dry_run_items"]) == 5, res["details"])

srv.shutdown()
shutil.rmtree(T, ignore_errors=True)
print("\ntest_qa_card_pilot: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
