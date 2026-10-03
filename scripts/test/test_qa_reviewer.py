#!/usr/bin/env python3
"""Tests for qa/gate_reviewer.py (S8 advisory Qwen reviewer + refuter) and qa/qa_reviewer_label.py.

The REAL entry point runs exactly as cron would: absolute and relative path, `env -i`, minimal PATH, NTFY_SERVER set. The model is a STUB
http server started by this test on 127.0.0.1 (a thread, shut down at the end): no real model, no network, no ntfy. Every behaviour has a
negative control (seeded bad answer -> dropped / refuted / UNVERIFIED) and a benign control (good answer -> recorded / PASS).
QA_REVIEWER_TEST_GATE=<path> points the suite at a mutated copy of the gate (used to prove each test fails on broken code)."""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
GATE_ABS = os.environ.get("QA_REVIEWER_TEST_GATE") or os.path.join(OVN, "qa", "gate_reviewer.py")
GATE_REL = os.path.join("qa", "gate_reviewer.py")
LABEL_ABS = os.path.join(OVN, "qa", "qa_reviewer_label.py")
PY = sys.executable
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


# ---------------------------------------------------------------------------------------------------------------- stub model server
SCEN = {"review": None, "refute": None, "hang": False}
CALLS = {"review": 0, "refute": 0, "max_prompt_chars": 0}
HANG = threading.Event()


def find_line(prompt, needle):
    """(lineno, code) of the first prompt line whose code contains needle: lines are '%5s %s %s' (no, kind, code)."""
    for ln in prompt.split("\n"):
        if needle in ln and ln[:5].strip().isdigit():
            return int(ln[:5]), ln[8:]
    return None, None


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        prompt = body["messages"][-1]["content"]
        CALLS["max_prompt_chars"] = max(CALLS["max_prompt_chars"], len(prompt))
        if SCEN["hang"]:
            HANG.wait(40)
            return
        kind = "refute" if "you are the REFUTER" in prompt else "review"
        CALLS[kind] += 1
        fn = SCEN[kind]
        out = fn(prompt) if callable(fn) else fn
        content = out if isinstance(out, str) else json.dumps(out)
        resp = {"choices": [{"message": {"content": content}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 100, "completion_tokens": 20}}
        data = json.dumps(resp).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Srv(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request, client_address):   # a handler that raises on purpose must not spray tracebacks
        pass


srv = Srv(("127.0.0.1", 0), H)
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
with socket.socket() as _s:           # a port nobody listens on (dead model)
    _s.bind(("127.0.0.1", 0))
    DEAD_PORT = _s.getsockname()[1]


def reset(review=None, refute=None, hang=False):
    SCEN.update({"review": review if review is not None else {"findings": []}, "refute": refute if refute is not None else {"refuted": True, "reason": "x"},
                 "hang": hang})
    CALLS.update({"review": 0, "refute": 0, "max_prompt_chars": 0})


# ---------------------------------------------------------------------------------------------------------------- repos
T = tempfile.mkdtemp(prefix="qa-reviewer-test-")
REPOS = os.path.join(T, "repos")
STATE = os.path.join(T, "state")
os.makedirs(REPOS)
os.makedirs(STATE)
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/relay-does-not-exist", "OVN_DIR": T,
       "OVN_REPOS_DIR": REPOS, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0",
       "QA_REVIEWER_URL": "http://127.0.0.1:%d" % PORT, "QA_REVIEWER_DEADLINE": "30", "QA_REVIEWER_CALL_TIMEOUT": "10"}


def sh(cmd, cwd=None, env=None):
    p = subprocess.run(cmd, cwd=cwd, env=env or ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


_n = [0]


def mkrepo(before, after):
    _n[0] += 1
    name = "r%d" % _n[0]
    d = os.path.join(REPOS, name)
    os.makedirs(d)
    g = lambda *a: sh(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a])  # noqa: E731
    g("init", "-q")
    for path, txt in before.items():
        os.makedirs(os.path.dirname(os.path.join(d, path)) or d, exist_ok=True)
        open(os.path.join(d, path), "w").write(txt)
    g("add", *before.keys())
    g("commit", "-q", "-m", "before")
    for path, txt in after.items():
        full = os.path.join(d, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write(txt)
        g("add", path)
    g("commit", "-q", "-m", "after")
    return name


def run_gate(repo, base="HEAD~1", head="HEAD", extra=(), env=None, rel=False, record=False, enforce=False):
    e = dict(ENV)
    if env:
        e.update(env)
    script = GATE_REL if rel else GATE_ABS
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, script, "check", "--repo", repo, "--base", base, "--head", head]
    if not record:
        cmd.append("--no-record")
    if enforce:
        cmd.append("--enforce-exit")
    t0 = time.time()
    p = subprocess.run(cmd, cwd=OVN if rel else T, capture_output=True, text=True)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}
    res["_rc"], res["_wall"], res["_raw"] = p.returncode, time.time() - t0, p.stdout + p.stderr
    return res


BEFORE = "def helper(x):\n    return x\n\n\n" + "".join("def filler_%d():\n    return %d\n\n\n" % (i, i) for i in range(12))
NEWCODE = ("def transfer(user, item):\n"
           "    if user.id != item.owner_id:\n"
           "        raise PermissionError('no')\n"
           "    item.owner_id = user.id\n"
           "    return item\n")
AFTER = BEFORE + "\n" + NEWCODE
R_MAIN = mkrepo({"app/svc.py": BEFORE}, {"app/svc.py": AFTER})


def counts(res):
    return res.get("details", {}).get("counts", {})


def drops(res):
    return res.get("details", {}).get("dropped", {})


def one_finding(quote="item.owner_id = user.id", line=None, at="item.owner_id = user.id", **kw):
    """review stub: cite `quote` at the printed line number of `at` (default: of the quote itself) unless `line` is forced."""
    def fn(prompt):
        no, _ = find_line(prompt, at)
        f = {"file": "app/svc.py", "line": line if line is not None else (no or 1), "quote": quote,
             "claim": "ownership is reassigned to the caller after the check, so any user can steal an item", "severity": "high"}
        f.update(kw)
        return {"findings": [f]}
    return fn


# ---------------------------------------------------------------------------------------------------------------- entry point + benign control
reset(review={"findings": []})
for rel in (True, False):
    if not rel:
        reset(review={"findings": []})         # the counters below describe ONE run
    res = run_gate(R_MAIN, rel=rel)
    ok("entry point (%s path, env -i, minimal PATH): one JSON line, benign control PASS, exit 0" % ("relative" if rel else "absolute"),
       res["verdict"] == "PASS" and res["_rc"] == 0 and res.get("gate") == "reviewer" and counts(res).get("proposed") == 0, str(res)[:300])
ok("benign control made exactly one review call and no refuter call", CALLS["review"] == 1 and CALLS["refute"] == 0, str(CALLS))
ok("every request stays under the ~12k-token ceiling", CALLS["max_prompt_chars"] / 2.8 < 12000, str(CALLS))

# ---------------------------------------------------------------------------------------------------------------- harness verification
reset(review=one_finding(quote="if (user.id == item.owner_id) { return item.secret; }"))   # real line number, invented code
res = run_gate(R_MAIN)
ok("hallucinated quote (not in the diff) is REJECTED: verified=0, dropped.quote_not_found=1, refuter never called, verdict PASS",
   counts(res).get("proposed") == 1 and counts(res).get("verified") == 0 and drops(res).get("quote_not_found") == 1 and CALLS["refute"] == 0
   and res["verdict"] == "PASS" and not res["details"].get("findings"), str(res)[:400])

reset(review=one_finding(line=9999))
res = run_gate(R_MAIN)
ok("real quote but line outside every hunk is REJECTED (dropped.line_outside_hunk), refuter not called",
   counts(res).get("verified") == 0 and drops(res).get("line_outside_hunk") == 1 and CALLS["refute"] == 0 and res["verdict"] == "PASS", str(res)[:400])

reset(review=one_finding(quote="    return x"))      # exists in the file but is an unchanged (context/removed) line, not an ADDED line of the hunk
res = run_gate(R_MAIN)
ok("quote that is only a CONTEXT line (not added) is rejected", counts(res).get("verified") == 0 and CALLS["refute"] == 0, str(res)[:300])

reset(review=one_finding(quote="def helper(x):"))
res = run_gate(R_MAIN)
ok("quote from an unchanged line far from the change is rejected", counts(res).get("verified") == 0, str(res)[:300])

reset(review=one_finding(file="app/other.py"))
res = run_gate(R_MAIN)
ok("finding naming a different file is rejected (wrong_file)", drops(res).get("wrong_file") == 1 and counts(res).get("verified") == 0, str(res)[:300])

reset(review=one_finding(claim=""))
res = run_gate(R_MAIN)
ok("schema-invalid finding (empty claim) is rejected (malformed)", drops(res).get("malformed") == 1 and counts(res).get("verified") == 0, str(res)[:300])

NEUTRAL = "the owner field is reassigned to the caller after the check, so the item silently changes owner"   # no auth-bypass wording: the severity floor must not apply
reset(review=lambda p: {"findings": [{k: v for k, v in one_finding(claim=NEUTRAL)(p)["findings"][0].items() if k != "severity"}]}, refute={"refuted": False, "reason": "r"})
res = run_gate(R_MAIN)
ok("missing severity (seen from the real model) does NOT discard a verified finding: coerced to medium and counted",
   counts(res).get("survived") == 1 and res["details"]["findings"][0]["severity"] == "medium" and res["details"].get("severity_defaulted") == 1, str(res)[:300])
reset(review=one_finding(severity="catastrophic", claim=NEUTRAL), refute={"refuted": False, "reason": "r"})
res = run_gate(R_MAIN)
ok("unknown severity value is coerced to medium too (a label, not evidence)", counts(res).get("survived") == 1 and res["details"]["findings"][0]["severity"] == "medium", str(res)[:300])
reset(review=one_finding(severity="medium"), refute={"refuted": False, "reason": "r"})   # default claim says 'any user can steal an item' = an authorization bypass
res = run_gate(R_MAIN)
f9 = res["details"]["findings"][0]
ok("2026-10-03 severity floor: a 'medium' finding that reads as an auth bypass is raised to high and marked severity_raised", f9["severity"] == "high" and f9.get("severity_raised") is True, str(f9)[:300])
reset(review=one_finding(severity="medium", claim=NEUTRAL), refute={"refuted": False, "reason": "r"})
res = run_gate(R_MAIN)
f9 = res["details"]["findings"][0]
ok("CONTROL: the same finding with neutral wording stays medium and is not marked raised", f9["severity"] == "medium" and not f9.get("severity_raised"), str(f9)[:300])

reset(review=one_finding(quote="x = 1"))
res = run_gate(R_MAIN)
ok("too-short quote is rejected (quote_too_short)", drops(res).get("quote_too_short") == 1, str(res)[:300])

reset(review=lambda p: {"findings": [{"file": "app/svc.py", "line": find_line(p, "item.owner_id = user.id")[0], "quote": "item.owner_id = user.id",
                                       "claim": "c%d" % i, "severity": "low"} for i in range(5)]},
      refute={"refuted": True, "reason": "x"})
res = run_gate(R_MAIN)
ok("more than 3 findings per chunk: proposed counts all 5, only 3 are processed (3 verified, 3 refuter calls), 2 dropped over_cap",
   counts(res).get("proposed") == 5 and drops(res).get("over_cap") == 2 and counts(res).get("verified") == 3 and CALLS["refute"] == 3, str(res)[:400] + str(CALLS))

reset(review="this is not json at all")
res = run_gate(R_MAIN)
ok("garbled model answer is never PASS: UNVERIFIED, bad_json counted", res["verdict"] == "UNVERIFIED" and drops(res).get("bad_json") == 1 and res["_rc"] == 0, str(res)[:300])

# ---------------------------------------------------------------------------------------------------------------- refuter
reset(review=one_finding(), refute={"refuted": True, "reason": "check at line 2 already guards the case"})
res = run_gate(R_MAIN)
ok("refuter kills the finding: verified=1 refuted=1 survived=0 -> PASS, nothing recorded as a finding",
   counts(res).get("verified") == 1 and counts(res).get("refuted") == 1 and counts(res).get("survived") == 0 and res["verdict"] == "PASS"
   and not res["details"]["findings"] and CALLS["refute"] == 1, str(res)[:400])

for label, ans in (("missing key", {"reason": "?"}), ("non-boolean", {"refuted": "false", "reason": "?"}), ("garbage text", "I think it is fine")):
    reset(review=one_finding(), refute=ans)
    res = run_gate(R_MAIN)
    ok("refuter answer %s defaults to REFUTED (finding killed)" % label, counts(res).get("survived") == 0 and counts(res).get("refuted") == 1 and res["verdict"] == "PASS",
       str(res)[:300])

reset(review=one_finding(), refute={"refuted": False, "reason": "owner_id is overwritten with the caller id after the check"})
res = run_gate(R_MAIN)
f0 = (res["details"].get("findings") or [{}])[0]
ok("survivor is recorded: FLAG (never FAIL), counts 1/1/1, id + file + real line + quote + claim + severity",
   res["verdict"] == "FLAG" and counts(res) == {"proposed": 1, "verified": 1, "refuted": 0, "refute_unavailable": 0, "survived": 1}
   and f0.get("file") == "app/svc.py" and f0.get("quote") == "item.owner_id = user.id" and f0.get("severity") == "high" and len(f0.get("id", "")) == 12
   and isinstance(f0.get("line"), int) and f0["line"] >= 1, str(res)[:500])
ok("the recorded line is the quote's real line in the file", (lambda ls: ls[f0["line"] - 1].strip() == "item.owner_id = user.id")(open(os.path.join(REPOS, R_MAIN, "app/svc.py")).read().split("\n")), str(f0))
res = run_gate(R_MAIN, env={"OVN_QA_REVIEWER": "enforce"}, enforce=True)
ok("even in enforce mode with --enforce-exit a FLAG exits 0 (the gate can never block)", res["verdict"] == "FLAG" and res["_rc"] == 0, str(res["_rc"]))

# ---------------------------------------------------------------------------------------------------------------- recording
rec = os.path.join(T, "state", "qa_shadow", "reviewer.jsonl")
res = run_gate(R_MAIN, record=True)
ok("default run appends one line to state/qa_shadow/reviewer.jsonl", os.path.isfile(rec) and len(open(rec).read().strip().splitlines()) == 1)
res = run_gate(R_MAIN, record=False)
ok("--no-record writes nothing", len(open(rec).read().strip().splitlines()) == 1)

# ---------------------------------------------------------------------------------------------------------------- NA: docs / test-only / generated / lockfile
reset(review=one_finding())
r_test = mkrepo({"tests/test_a.py": "def test_a():\n    assert 1\n"}, {"tests/test_a.py": "def test_a():\n    assert 1 == 1\n    assert 2 == 2\n"})
res = run_gate(r_test)
ok("test-only diff -> NA and NO model call", res["verdict"] == "NA" and CALLS["review"] == 0, str(res)[:300])
r_doc = mkrepo({"README.md": "a\n", "package-lock.json": "{}\n"}, {"README.md": "b\n", "package-lock.json": '{"a": 1}\n'})
res = run_gate(r_doc)
ok("docs + lockfile only -> NA, no model call", res["verdict"] == "NA" and CALLS["review"] == 0, str(res)[:300])
r_gen = mkrepo({"app/models_pb2.py": "x = 1\n"}, {"app/models_pb2.py": "x = 2\ny = 3\nz = 4\n"})
res = run_gate(r_gen)
ok("generated file only -> NA (skipped, listed), no model call", res["verdict"] == "NA" and CALLS["review"] == 0 and any(s["reason"] == "generated" for s in res["details"]["skipped"]), str(res)[:300])
r_kt = mkrepo({"app/A.swift": "let a = 1\n"}, {"app/A.swift": "let a = 2\nlet b = 3\n"})   # 2026-10-03: kotlin + gdscript are enabled now; swift is the still-disabled language
res = run_gate(r_kt)
ok("language not enabled (swift) -> NA with the reason listed", res["verdict"] == "NA" and CALLS["review"] == 0 and any("lang-not-enabled" in s["reason"] for s in res["details"]["skipped"]), str(res)[:300])
r_mix = mkrepo({"tests/test_a.py": "x = 1\n", "app/svc.py": BEFORE}, {"tests/test_a.py": "x = 2\n", "app/svc.py": AFTER})
reset(review={"findings": []})
res = run_gate(r_mix)
ok("mixed diff: only the product file is reviewed (test file never reaches the model)", CALLS["review"] == 1 and "tests/test_a.py" not in str(res["details"].get("skipped")), str(CALLS))

# ---------------------------------------------------------------------------------------------------------------- dead / hung model
t0 = time.time()
res = run_gate(R_MAIN, env={"QA_REVIEWER_URL": "http://127.0.0.1:%d" % DEAD_PORT})
ok("dead model (connection refused) -> UNVERIFIED, exit 0, fast", res["verdict"] == "UNVERIFIED" and res["_rc"] == 0 and res["_wall"] < 8, "%s %.1fs" % (res["verdict"], res["_wall"]))
reset(hang=True)
res = run_gate(R_MAIN, env={"QA_REVIEWER_DEADLINE": "9", "QA_REVIEWER_CALL_TIMEOUT": "3"})
ok("HUNG model (accepts, never replies) -> UNVERIFIED within the deadline (circuit breaker, one timeout only)",
   res["verdict"] == "UNVERIFIED" and res["_wall"] < 9 and res["details"].get("model_calls") == 1 and res["_rc"] == 0, "%s %.1fs %s" % (res["verdict"], res["_wall"], res["details"].get("model_calls")))
reset(hang=True)
res = run_gate(R_MAIN, env={"QA_ACCEPTANCE_LLM_TIMEOUT": "500", "QA_REVIEWER_DEADLINE": "12", "QA_REVIEWER_CALL_TIMEOUT": "2"})
ok("a stray QA_ACCEPTANCE_LLM_TIMEOUT in the environment cannot stretch this gate's per-call cap (acceptance_card.call_model honours it)",
   res["verdict"] == "UNVERIFIED" and res["_wall"] < 5, "%s %.1fs" % (res["verdict"], res["_wall"]))
HANG.set()
HANG.clear()


# model answers the review, then the refuter call fails (the handler raises -> connection dropped) => the verified finding must NOT be
# recorded as a survivor and the verdict must not be PASS
def flaky_review(p):
    return one_finding()(p)


reset(review=flaky_review, refute=lambda p: (_ for _ in ()).throw(RuntimeError("boom")))   # handler raises -> connection drops -> call fails
res = run_gate(R_MAIN)
ok("refuter call fails after a verified finding: not recorded, counted refute_unavailable, verdict UNVERIFIED (not PASS, not FLAG)",
   res["verdict"] == "UNVERIFIED" and counts(res).get("refute_unavailable") == 1 and counts(res).get("survived") == 0 and not res["details"]["findings"], str(res)[:400])

# ---------------------------------------------------------------------------------------------------------------- chunking, huge files, partial coverage
big_body = "".join("def fn_%d(a, b):\n    total = a + b + %d\n    return total * %d\n\n\n" % (i, i, i) for i in range(1400))   # ~ 60k chars of added code
r_big = mkrepo({"app/big.py": "x = 1\n", "app/small.py": BEFORE}, {"app/big.py": "x = 1\n" + big_body, "app/small.py": AFTER})
reset(review={"findings": []})
res = run_gate(r_big)
ok("a huge file is SKIPPED and listed with a reason; the small file is still reviewed; PASS only for what was reviewed",
   any(s["file"] == "app/big.py" and s["reason"].startswith(("huge", "single-hunk")) for s in res["details"]["skipped"]) and CALLS["review"] == 1 and res["verdict"] == "PASS", str(res)[:400])
ok("no request carried the huge file (every prompt under the ceiling)", CALLS["max_prompt_chars"] / 2.8 < 12000, str(CALLS))
_filler = "".join("line_%03d = %d\n" % (i, i) for i in range(420))
_blocks = {}
for _k in range(8):            # 8 hunks (>6 unchanged lines apart), each ~40 long added lines: ~35k chars of diff => needs 2+ chunks
    _blocks[_k * 50 + 25] = "".join("added_%d_%d = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'\n" % (_k, j) for j in range(40))
_after = "".join(("line_%03d = %d\n" % (i, i)) + _blocks.get(i, "") for i in range(420))
r_mid = mkrepo({"app/mid.py": _filler}, {"app/mid.py": _after})
reset(review={"findings": []})
res = run_gate(r_mid)
ok("a mid-size file is split into several chunks, each under the ceiling, all reviewed", res["details"].get("chunks_total", 0) >= 2 and res["details"]["chunks_reviewed"] == res["details"]["chunks_total"]
   and CALLS["max_prompt_chars"] / 2.8 < 12000 and res["verdict"] == "PASS", str(res["details"])[:400])
res = run_gate(r_mid, env={"QA_REVIEWER_MAX_CALLS": "1"})
ok("call cap reached before every chunk was reviewed and nothing survived -> UNVERIFIED (partial coverage is never a PASS)", res["verdict"] == "UNVERIFIED" and res["details"]["complete"] is False
   and "partial" in res["summary"], str(res)[:400])

_filler2 = "".join("line_%03d = %d\n" % (i, i) for i in range(900))
_after2 = "".join(("line_%03d = %d\n" % (i, i)) + ("".join("added_%d_%d = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'\n" % (i, j) for j in range(40)) if i % 50 == 25 else "") for i in range(900))
r_many = mkrepo({"app/many.py": _filler2}, {"app/many.py": _after2})
reset(review={"findings": []})
res = run_gate(r_many)
ok("a file with MANY medium hunks whose total diff exceeds the per-file budget is skipped as huge (not sent in pieces), NA when nothing else is reviewable",
   res["verdict"] == "NA" and CALLS["review"] == 0 and any(x["file"] == "app/many.py" and x["reason"].startswith("huge") for x in res["details"]["skipped"]), str(res)[:400])
reset(hang=True)
res = run_gate(r_mid, env={"QA_REVIEWER_DEADLINE": "14", "QA_REVIEWER_CALL_TIMEOUT": "3"})
ok("circuit breaker: a hung model with SEVERAL chunks pending costs exactly ONE timed-out call (not one per chunk), UNVERIFIED",
   res["verdict"] == "UNVERIFIED" and res["details"].get("model_calls") == 1 and res["details"].get("chunks_total", 0) >= 2 and res["_wall"] < 8,
   "%s calls=%s %.1fs" % (res["verdict"], res["details"].get("model_calls"), res["_wall"]))
HANG.set()
HANG.clear()
reset(review={"findings": []})

# ---------------------------------------------------------------------------------------------------------------- redaction
AKIA = "AKIA" + "IOSFODNN7EXAMPLE"
SKL = "sk_live_" + "abcdefghijklmnop1234567890"
PW = "hunter2" + "hunter2xyz"
SECRET_AFTER = BEFORE + "\n" + "AWS_ACCESS_KEY = '%s'\nPASSWORD = '%s'\nSTRIPE = '%s'\n" % (AKIA, PW, SKL)
r_sec = mkrepo({"app/svc.py": BEFORE}, {"app/svc.py": SECRET_AFTER})
reset(review=lambda p: {"findings": [{"file": "app/svc.py", "line": find_line(p, "AWS_ACCESS_KEY")[0], "quote": "AWS_ACCESS_KEY = '%s'" % AKIA,
                                       "claim": "hard-coded credentials %s and %s and password %s committed" % (AKIA, SKL, PW), "severity": "high"}]},
      refute={"refuted": False, "reason": "the key %s is a real-looking literal, password=%s" % (AKIA, PW)})
res = run_gate(r_sec, record=True)
blob = res["_raw"] + open(rec).read()
ok("secret-looking strings are redacted from findings, stdout and the shadow record (AWS key, sk_live, password literal)",
   res["verdict"] == "FLAG" and AKIA not in blob and SKL not in blob and PW not in blob and "<redacted>" in blob, blob[-500:])
ok("redacted finding still verified against the RAW quote (verified=1 survived=1)", counts(res).get("verified") == 1 and counts(res).get("survived") == 1, str(counts(res)))

# ---------------------------------------------------------------------------------------------------------------- safety: live clone untouched, no leftovers
before_wt = sh(["git", "-C", os.path.join(REPOS, R_MAIN), "worktree", "list"])[1]
st = sh(["git", "-C", os.path.join(REPOS, R_MAIN), "status", "--porcelain"])[1]
reset(review=one_finding(), refute={"refuted": False, "reason": "r"})
run_gate(R_MAIN, record=True)
ok("no worktree left behind and the clone's working tree is untouched",
   sh(["git", "-C", os.path.join(REPOS, R_MAIN), "worktree", "list"])[1] == before_wt and sh(["git", "-C", os.path.join(REPOS, R_MAIN), "status", "--porcelain"])[1] == st == "")
ok("gate is auto-discovered by qa_run_shadow.sh (qa/gate_*.py naming) and takes no lock", os.path.basename(GATE_REL).startswith("gate_") and "run.lock" not in open(os.path.join(OVN, "qa", "gate_reviewer.py")).read().replace('"run.lock"', ""),
   "")
res = run_gate(R_MAIN, env={"OVN_QA_REVIEWER": "off"})
ok("mode off -> NA without calling the model", res["verdict"] == "NA", str(res)[:200])
ok("unknown ref -> UNVERIFIED exit 0; unknown repo -> UNVERIFIED", run_gate(R_MAIN, base="nope")["verdict"] == "UNVERIFIED" and run_gate("no-such-repo-zz")["verdict"] == "UNVERIFIED")

# ---------------------------------------------------------------------------------------------------------------- labelling CLI + report
if os.path.exists(LABEL_ABS):
    shutil.rmtree(os.path.join(T, "state"), ignore_errors=True)
    os.makedirs(os.path.join(T, "state", "qa_shadow"))
    LEDG = os.path.join(T, "state", "qa_ledger.jsonl")

    def label(*args, env=None):
        e = dict(ENV)
        if env:
            e.update(env)
        p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, LABEL_ABS] + list(args), cwd=T, capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr

    def shadow_rows(n, t0=None):
        t0 = t0 or time.time() - 3 * 86400
        rows = []
        for i in range(n):
            ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t0))
            rows.append({"gate": "reviewer", "repo": "billwatch", "ref": "aaa..bbb", "ts": ts, "verdict": "FLAG", "mode": "shadow", "summary": "", "ms": 1,
                         "details": {"counts": {"proposed": 3, "verified": 2, "survived": 1},
                                     "findings": [{"id": "f%011d" % i, "file": "app/f%d.py" % (i % 5), "line": 3, "quote": "q q q q", "claim": "c", "severity": "low", "refuter": "r"}]}})
        with open(os.path.join(T, "state", "qa_shadow", "reviewer.jsonl"), "w") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
    shadow_rows(60)
    rc, out = label("label", "--id", "f%011d" % 0, "--label", "TP", "--note", "real")
    ok("label: TP stored", rc == 0 and os.path.isfile(os.path.join(T, "state", "qa_reviewer_labels.jsonl")), out)
    rc, out = label("label", "--id", "zzzzzzzzzzzz", "--label", "TP")
    ok("label: unknown finding id is refused (non-zero), nothing stored", rc != 0 and len(open(os.path.join(T, "state", "qa_reviewer_labels.jsonl")).read().strip().splitlines()) == 1, out)
    rc, out = label("label", "--id", "f%011d" % 1, "--label", "maybe")
    ok("label: invalid label refused", rc != 0, out)
    rc, out = label("report")
    ok("report with 1 labelled finding REFUSES to print a percentage", rc == 0 and "%" not in out.split("precision")[-1].split("\n")[0] and "not computed" in out, out)
    for i in range(1, 30):
        label("label", "--id", "f%011d" % i, "--label", "TP" if i % 3 else "FP")
    rc, out = label("report")
    ok("report with 30 labelled (<50) still refuses a percentage", "not computed" in out and "precision: " in out and "n=30" in out, out)
    for i in range(30, 52):
        label("label", "--id", "f%011d" % i, "--label", "TP" if i % 2 else "FP")
    label("label", "--id", "f%011d" % 52, "--label", "unclear")
    rc, out = label("report")
    ok("report with >=50 decisive labels prints precision with sample size and a Wilson interval", "precision: " in out and "n=52" in out and "not computed" not in out and "%" in out and "95%" in out, out)
    label("label", "--id", "f%011d" % 0, "--label", "FP")
    rc, out = label("report", "--json")
    d = json.loads(out)
    ok("latest label per finding wins (relabel TP -> FP is counted once)", d["labelled"] == 53 and d["fp"] == (d["labelled"] - d["tp"] - d["unclear"]), out[:300])
    ok("unclear labels are excluded from precision's denominator", d["unclear"] == 1 and d["decisive"] == d["tp"] + d["fp"], out[:300])
    bar = d.get("bar_met")
    ok("bar line: >=50 decisive AND >=60% needed; reports met/not met explicitly", bar in (True, False) and "bar" in label("report")[1], out[:300])

    # ledger join: a revert/hotfix on the same file within 7 days AFTER the finding is auto-suggested as TP; other repo / other file / too late are not
    now = time.time()
    shadow_rows(3, t0=now - 2 * 86400)
    evs = [{"kind": "event", "type": "hotfix", "repo": "billwatch", "epoch": int(now - 86400), "overlap": ["app/f0.py"], "confidence": "strong", "key": "k1", "ref": "abc", "note": "fix: boom", "rec": "r1"},
           {"kind": "event", "type": "hotfix", "repo": "gitlark", "epoch": int(now - 86400), "overlap": ["app/f1.py"], "key": "k2", "ref": "abd", "rec": "r2"},
           {"kind": "event", "type": "hotfix", "repo": "billwatch", "epoch": int(now - 86400), "overlap": ["app/zzz.py"], "key": "k3", "ref": "abe", "rec": "r3"},
           {"kind": "event", "type": "hotfix", "repo": "billwatch", "epoch": int(now - 10 * 86400), "overlap": ["app/f2.py"], "key": "k4", "ref": "abf", "rec": "r4"},
           {"kind": "landed", "key": "r5", "repo": "billwatch", "files": ["app/f2.py"], "epoch": int(now - 3 * 86400), "ts": "2026-10-01T00:00:00Z", "commits": [], "risk": "B"},
           {"kind": "event", "type": "revert", "repo": "billwatch", "epoch": int(now - 3600), "rec": "r5", "key": "k5", "ref": "abg", "note": "Revert x"}]
    with open(LEDG, "w") as fh:
        for e in evs:
            fh.write(json.dumps(e) + "\n")
    os.remove(os.path.join(T, "state", "qa_reviewer_labels.jsonl"))
    rc, out = label("report", "--json")
    d = json.loads(out)
    sug = {s["id"]: s for s in d["suggested_tp"]}
    ok("ledger join: finding on app/f0.py with a later hotfix touching it within 7d IS suggested TP", "f%011d" % 0 in sug and sug["f%011d" % 0]["evidence"][0]["type"] == "hotfix", out[:500])
    ok("ledger join: revert whose LANDED record touched the file is suggested via rec->files (f2)", "f%011d" % 2 in sug and any(e["type"] == "revert" for e in sug["f%011d" % 2]["evidence"]), out[:500])
    ok("ledger join NEGATIVE controls: other repo, other file, and a hotfix that predates the finding are NOT suggested", "f%011d" % 1 not in sug and len(sug) == 2, str(sorted(sug)))
    ok("suggestions are never counted as labels (precision inputs stay 0)", d["labelled"] == 0 and d["tp"] == 0, out[:300])
    rc, out = label("list", "--unlabelled")
    ok("list shows unlabelled findings with id/file/claim", rc == 0 and "f%011d" % 0 in out and "app/f0.py" in out, out[:300])
else:
    print("  skip qa_reviewer_label.py not present")

srv.shutdown()
srv.server_close()
HANG.set()
shutil.rmtree(T, ignore_errors=True)
print("\nreviewer tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
