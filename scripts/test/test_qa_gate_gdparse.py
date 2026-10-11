#!/usr/bin/env python3
"""Tests for qa/gate_gdparse.py (gates gdparse + gdlint cells; analysis F12, 2026-10-10) and its helper qa/gdtoolkit_run.py.

Part A is hermetic and runs everywhere: a FAKE python (a script standing in for the interpreter that has gdtoolkit; it speaks the helper's JSON protocol and
decides from file CONTENT markers: SYNTAX_ERROR -> parse_error, TOOL_CRASH -> tool_error, `LINT:<rule>` per line -> a lint problem) drives the real gate
against throwaway git repos: NA / PASS / FLAG-in-shadow / FAIL-when-enforced, pre-existing vs new damage, renames, advisory baseline-relative lint,
UNVERIFIED (tool missing, crash, timeout, oversize file, bad ref), never-PASS-on-unchecked, mode switches, exit codes, no scratch dirs left, live clone untouched.
Part B runs the REAL gdtoolkit when a python that can import it is found (QA_TEST_GDTOOLKIT_PYTHON, ~/qa-venv/bin/python, or this interpreter); otherwise it
prints SKIP (the box run uses the scratch venv)."""
import json, os, shutil, stat, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
GATE = os.path.join(QA, "gate_gdparse.py")

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:500]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-gdparse-test-"))
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(OVN, "repos")
TMP = os.path.join(T, "tmp")
os.makedirs(os.path.join(OVN, "state"))
os.makedirs(TMP)

FAKEPY = os.path.join(T, "fakepy")
with open(FAKEPY, "w") as f:
    f.write('''#!/usr/bin/env python3
import json, os, sys, time
a = sys.argv[1:]
if a[:1] == ["-I"]:
    a = a[1:]
if a[:1] == ["-c"]:
    sys.exit(0)                       # the `import gdtoolkit, lark` availability probe
helper, mode, root = a[0], a[1], a[2]
if os.environ.get("FAKE_HANG"):
    time.sleep(60)
files = json.loads(sys.stdin.read() or "[]")
res = {}
for rel in files:
    code = open(os.path.join(root, rel), "rb").read().decode("utf-8", "replace")
    r = {"ok": True, "kind": "ok", "err": "", "problems": []}
    if "TOOL_CRASH" in code:
        r.update(ok=False, kind="tool_error", err="RuntimeError: boom")
    elif "SYNTAX_ERROR" in code:
        r.update(ok=False, kind="parse_error", err="line 1 col 1: Unexpected token")
    elif mode == "lint":
        for i, l in enumerate(code.splitlines(), 1):
            if "LINT:" in l:
                r["problems"].append([l.split("LINT:")[1].split()[0], i, "msg %d" % i])
    res[rel] = r
print(json.dumps({"version": "fake", "results": res}))
''')
os.chmod(FAKEPY, 0o755)


def git(cwd, *a):
    p = subprocess.run(["git", "-C", cwd] + list(a), capture_output=True, text=True, timeout=60)
    return p.stdout.strip()


def new_repo(name):
    path = os.path.join(REPOS, name)
    os.makedirs(path)
    git(path, "init", "-q")
    git(path, "config", "user.email", "t@t")
    git(path, "config", "user.name", "t")
    return path


def put(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def commit(root, msg="c"):
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", msg)
    return git(root, "rev-parse", "HEAD")


def gate(repo, base, head, env=None, extra=None, timeout=120):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS, "TMPDIR": TMP, "LANG": "C",
         "QA_GDTOOLKIT_PYTHON": FAKEPY, "QA_FETCH_WAIT": "0"}
    e.update(env or {})
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [sys.executable, GATE, "check", "--repo", repo, "--base", base, "--head", head,
                                                                           "--no-record"] + (extra or []), cwd=T, capture_output=True, text=True, timeout=timeout)
    try:
        js = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        js = {"verdict": "NO-JSON", "summary": p.stdout + p.stderr, "details": {}}
    js.setdefault("details", {})
    return p.returncode, js


print("== NA cases")
R = new_repo("g1")
put(R, "README.md", "x\n")
b0 = commit(R)
put(R, "README.md", "y\n")
b1 = commit(R)
rc, js = gate("g1", b0, b1)
ok("no changed .gd => NA", rc == 0 and js["verdict"] == "NA" and "no changed .gd" in js["summary"], js)
put(R, "addons/gut/x.gd", "SYNTAX_ERROR\n")
put(R, ".godot/y.gd", "SYNTAX_ERROR\n")
b2 = commit(R)
rc, js = gate("g1", b1, b2)
ok("only vendored addons/.godot .gd changed => NA (not scanned, not PASS)", js["verdict"] == "NA" and js["details"]["skipped"] == {"vendored_dir": 2}, js)
rc, js = gate("g1", b0, b1, env={"OVN_QA_GDPARSE": "off"})
ok("mode off => NA", js["verdict"] == "NA" and "off" in js["summary"], js)

print("== PASS / FLAG / FAIL")
R = new_repo("g2")
put(R, "scripts/a.gd", "extends Node\n")
put(R, "README.md", "x\n")
base = commit(R)
put(R, "scripts/a.gd", "extends Node\nvar x = 1\n")
put(R, "tests/test_new.gd", "extends GutTest\n")
h_ok = commit(R)
rc, js = gate("g2", base, h_ok)
ok("clean changed .gd => PASS (2 parsed), no would_be_verdict", js["verdict"] == "PASS" and js["details"]["files"] == 2 and not js["details"]["would_be_verdict"], js)
put(R, "tests/test_new.gd", "SYNTAX_ERROR\n")
h_bad = commit(R)
rc, js = gate("g2", base, h_bad)
d = js["details"]
ok("parse error in a changed test file => FLAG in shadow (the shipped default), would_be_verdict FAIL", js["verdict"] == "FLAG" and d["would_be_verdict"] == "FAIL"
   and d["n_parse_errors"] == 1 and d["parse_errors"][0]["file"] == "tests/test_new.gd" and d["parse_errors"][0]["preexisting"] is False, js)
ok("summary says GUT would silently skip it", "GUT would silently skip" in js["summary"], js["summary"])
rc, js = gate("g2", base, h_bad, env={"OVN_QA_GDPARSE": "enforce"})
ok("same range, mode enforce => FAIL (exit 0 without --enforce-exit)", js["verdict"] == "FAIL" and rc == 0, (rc, js))
rc, js = gate("g2", base, h_bad, env={"OVN_QA_GDPARSE": "enforce"}, extra=["--enforce-exit"])
ok("enforce + --enforce-exit => exit 1", rc == 1 and js["verdict"] == "FAIL", (rc, js))
rc, js = gate("g2", base, h_bad, extra=["--enforce-exit"])
ok("shadow + --enforce-exit => still exit 0", rc == 0 and js["verdict"] == "FLAG", (rc, js))
put(R, "tests/test_new.gd", "extends GutTest\n")
h_fixed = commit(R)
rc, js = gate("g2", base, h_fixed)
ok("benign control: the broken file fixed again before head => PASS", js["verdict"] == "PASS", js)
rc, js = gate("g2", h_ok, h_bad)
ok("a file that was parseable at base and broken at head is NEW damage", js["details"]["parse_errors"][0]["preexisting"] is False and js["details"]["n_preexisting"] == 0, js)
put(R, "tests/test_new.gd", "SYNTAX_ERROR still\n")
h_bad2 = commit(R)
rc, js = gate("g2", h_bad, h_bad2)
ok("still broken at base AND head (touched, left broken) => still FLAG, marked preexisting", js["verdict"] == "FLAG" and js["details"]["parse_errors"][0]["preexisting"] is True
   and js["details"]["n_preexisting"] == 1, js)
git(R, "mv", "tests/test_new.gd", "tests/test_renamed.gd")
h_ren = commit(R)
rc, js = gate("g2", h_bad2, h_ren)
ok("rename of a file broken at base: found under the new name, preexisting via the rename map",
   js["verdict"] == "FLAG" and js["details"]["parse_errors"][0]["file"] == "tests/test_renamed.gd" and js["details"]["parse_errors"][0]["preexisting"] is True, js)
put(R, "weird name é/ünïcode file.gd", "SYNTAX_ERROR\n")
h_w = commit(R)
rc, js = gate("g2", h_ren, h_w)
ok("odd file names (spaces, unicode) are parsed, not dropped", js["verdict"] == "FLAG" and "ünïcode" in js["details"]["parse_errors"][0]["file"], js)
ok("scratch dirs removed", not [x for x in os.listdir(TMP) if x.startswith("qa-gdparse-")], os.listdir(TMP))
ok("live clone untouched: clean status, one worktree", git(R, "status", "--porcelain") == "" and len(git(R, "worktree", "list").splitlines()) == 1)

print("== gdlint: advisory, baseline-relative")
R = new_repo("g3")
put(R, "a.gd", "extends Node\nvar a # LINT:rule-one\nvar b # LINT:rule-one\n")
base = commit(R)
put(R, "a.gd", "# header moved every line down\n# another\nextends Node\nvar a # LINT:rule-one\nvar b # LINT:rule-one\n")
h1 = commit(R)
rc, js = gate("g3", base, h1)
ok("same findings shifted down by edits => 0 new (fingerprint ignores line numbers), verdict PASS", js["verdict"] == "PASS" and js["details"]["gdlint"]["new"] == 0
   and js["details"]["gdlint"]["head_total"] == 2 and js["details"]["gdlint"]["base_total"] == 2, js)
put(R, "a.gd", "extends Node\nvar a # LINT:rule-one\nvar b # LINT:rule-one\nvar c # LINT:rule-one\nvar d # LINT:rule-two\n")
put(R, "new.gd", "extends Node\nvar z # LINT:rule-three\n")
h2 = commit(R)
rc, js = gate("g3", base, h2)
gl = js["details"]["gdlint"]
ok("excess findings are new: +1 rule-one in a.gd, +1 rule-two, +1 rule-three in a NEW file = 3", gl["new"] == 3 and gl["by_rule"] == {"rule-one": 1, "rule-two": 1, "rule-three": 1}, gl)
ok("advisory only: new lint findings never change the verdict (still PASS)", js["verdict"] == "PASS" and "3 new advisory" in js["summary"], js)
put(R, "a.gd", "SYNTAX_ERROR # LINT:rule-one\n")
h3 = commit(R)
rc, js = gate("g3", base, h3)
ok("a file that does not parse is not linted (no lint noise from it) and is a FLAG", js["verdict"] == "FLAG" and js["details"]["gdlint"]["head_total"] == 1, js)
rc, js = gate("g3", base, h2, env={"QA_GDLINT": "off"})
ok("QA_GDLINT=off skips the lint cell, parse still runs", js["verdict"] == "PASS" and js["details"]["gdlint"]["status"] == "NA", js)

print("== UNVERIFIED, never PASS")
R = new_repo("g4")
put(R, "a.gd", "extends Node\n")
base = commit(R)
put(R, "a.gd", "extends Node\nvar x\n")
put(R, "b.gd", "TOOL_CRASH\n")
h = commit(R)
rc, js = gate("g4", base, h)
ok("tool crashed on a changed file => UNVERIFIED (not PASS, not a parse error)", js["verdict"] == "UNVERIFIED" and js["details"]["tool_errors"].get("b.gd"), js)
rc, js = gate("g4", base, h, env={"QA_GDTOOLKIT_PYTHON": os.path.join(T, "no-such-python")})
ok("gdtoolkit missing in SHADOW => NA naming the install step (details.gdtoolkit_missing), never PASS, not UNVERIFIED noise", js["verdict"] == "NA" and "not installed" in js["summary"] and js["details"].get("gdtoolkit_missing") is True, js)
rc, js = gate("g4", base, h, env={"QA_GDTOOLKIT_PYTHON": os.path.join(T, "no-such-python"), "OVN_QA_GDPARSE": "enforce"})
ok("gdtoolkit missing while ENFORCED => UNVERIFIED (an enforced gate that could not check never reads clean)", js["verdict"] == "UNVERIFIED" and "not installed" in js["summary"], js)
t0 = time.time()
rc, js = gate("g4", base, h, env={"FAKE_HANG": "1"}, extra=["--timeout", "3"])
ok("hanging gdtoolkit => UNVERIFIED, bounded", js["verdict"] == "UNVERIFIED" and time.time() - t0 < 30, (js, time.time() - t0))
put(R, "big.gd", "# " + "x" * 1100000 + "\n")
put(R, "b.gd", "extends Node\n")
h_big = commit(R)
rc, js = gate("g4", base, h_big)
ok("an over-size changed .gd cannot be checked => UNVERIFIED (never a clean PASS)", js["verdict"] == "UNVERIFIED" and js["details"]["unscannable"].get("big.gd") == "too_large", js)
rc, js = gate("g4", base, "no-such-ref")
ok("unknown ref => UNVERIFIED", js["verdict"] == "UNVERIFIED" and "not found" in js["summary"], js)
rc, js = gate("nonexistent-repo", base, h)
ok("unknown repo => UNVERIFIED", js["verdict"] == "UNVERIFIED", js)
p = subprocess.run([sys.executable, GATE, "check", "--repo", "g4", "--no-record"], capture_output=True, text=True, env=dict(os.environ, OVN_DIR=OVN), timeout=60)
ok("missing --base/--head => UNVERIFIED JSON, exit 0", p.returncode == 0 and json.loads(p.stdout.strip().splitlines()[-1])["verdict"] == "UNVERIFIED", p.stdout + p.stderr)
rc, js = gate("g4", base, h, extra=["--timeout", "0"])
ok("bad --timeout => UNVERIFIED with a clear message", js["verdict"] == "UNVERIFIED" and "timeout" in js["summary"], js)
ok("no scratch dirs left after the failure paths either", not [x for x in os.listdir(TMP) if x.startswith("qa-gdparse-")], os.listdir(TMP))
ok("the gate wrote nothing outside its temp dirs (state untouched: --no-record)", not os.path.exists(os.path.join(OVN, "state", "qa_shadow")))

print("== recorded as a shadow row when recording is on")
env = {"PATH": os.environ.get("PATH", ""), "HOME": T, "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS, "TMPDIR": TMP, "QA_GDTOOLKIT_PYTHON": FAKEPY}
p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE, "check", "--repo", "g4", "--base", base, "--head", h],
                   capture_output=True, text=True, timeout=60, cwd=T)
rows = open(os.path.join(OVN, "state", "qa_shadow", "gdparse.jsonl")).read().splitlines() if os.path.exists(os.path.join(OVN, "state", "qa_shadow", "gdparse.jsonl")) else []
ok("one row in state/qa_shadow/gdparse.jsonl with gate=gdparse mode=shadow", len(rows) == 1 and json.loads(rows[0])["gate"] == "gdparse" and json.loads(rows[0])["mode"] == "shadow", rows)

print("== the gate is picked up by the shadow runner glob and by qa_enforce's gate list (name gate_gdparse.py), default mode shadow")
ok("file name matches gate_*.py", os.path.basename(GATE) == "gate_gdparse.py")
sys.path.insert(0, QA)
import qa_common as qc  # noqa: E402
os.environ["OVN_DIR"] = OVN
os.environ.pop("OVN_QA_GDPARSE", None)
ok("default mode for the new gate is shadow", qc.mode("gdparse") == "shadow")

# ------------------------------------------------------------------------------------------------ Part B: the real tool
print("== Part B: real gdtoolkit")
cands = [os.environ.get("QA_TEST_GDTOOLKIT_PYTHON"), os.path.expanduser("~/qa-venv/bin/python"), sys.executable]
REALPY = None
for c in cands:
    if c and os.path.exists(c) and subprocess.run([c, "-I", "-c", "import gdtoolkit, lark"], capture_output=True).returncode == 0:
        REALPY = c
        break
if not REALPY:
    print("  SKIP no python with gdtoolkit found (set QA_TEST_GDTOOLKIT_PYTHON); the hermetic part above passed")
else:
    R = new_repo("real")
    good = ('extends Node\nclass_name Foo\nsignal done(x)\n@export var speed: float = 1.0\n@onready var n = $Child\nvar d := {"a": 1}\n\n\n'
            'func _ready() -> void:\n\tawait get_tree().process_frame\n\tprint("hi")\n')
    put(R, "ok.gd", good)
    put(R, "long.gd", "extends Node\n\n\nvar x = '" + "y" * 140 + "'\n")
    put(R, "README.md", "x\n")
    base = commit(R)
    put(R, "ok.gd", good + "\n\nfunc more(a: int) -> int:\n\treturn a + 1\n")
    put(R, "long.gd", "extends Node\n\n\nvar x = '" + "y" * 140 + "'\nvar z = '" + "w" * 150 + "'\n")
    put(R, "broken.gd", "extends Node\nfunc (:\n\tpass pass\n")
    put(R, "bin.gd", "extends Node\n\xff\xfe\n")
    with open(os.path.join(R, "latin1.gd"), "wb") as f:
        f.write(b"extends Node\nvar s = '\xe9\xff'\n")
    h = commit(R)
    rc, js = gate("real", base, h, env={"QA_GDTOOLKIT_PYTHON": REALPY})
    d = js["details"]
    bad = {p["file"] for p in d.get("parse_errors", [])}
    ok("real gdtoolkit: syntax-broken file and a non-UTF-8 file are parse errors; valid GDScript 4 is not", {"broken.gd", "latin1.gd"} <= bad and "ok.gd" not in bad and js["verdict"] == "FLAG", js)
    ok("real gdtoolkit: the lint cell is baseline-relative (one NEW long line in long.gd, the old one is not counted)", d["gdlint"]["status"] == "OK"
       and any(x["at"].startswith("long.gd") and x["rule"] == "max-line-length" for x in d["gdlint"]["new_list"]) and
       len([x for x in d["gdlint"]["new_list"] if x["at"].startswith("long.gd")]) == 1, d.get("gdlint"))
    put(R, "broken.gd", "extends Node\n")
    os.remove(os.path.join(R, "latin1.gd"))
    os.remove(os.path.join(R, "bin.gd"))
    h2 = commit(R)
    rc, js = gate("real", base, h2, env={"QA_GDTOOLKIT_PYTHON": REALPY})
    ok("real gdtoolkit: once the broken files are valid the range is PASS", js["verdict"] == "PASS" and js["details"]["n_parse_errors"] == 0, js)
    out = subprocess.run([REALPY, "-I", os.path.join(QA, "gdtoolkit_run.py"), "parse", R], input=json.dumps(["ok.gd", "nope.gd"]), capture_output=True, text=True, timeout=60)
    r = json.loads(out.stdout)
    ok("helper: a missing file is a tool_error (not a parse error, not ok)", r["results"]["nope.gd"]["kind"] == "tool_error" and r["results"]["ok.gd"]["kind"] == "ok", r)

shutil.rmtree(T, ignore_errors=True)
print("\nqa_gate_gdparse: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
