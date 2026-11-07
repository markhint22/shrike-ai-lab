#!/usr/bin/env python3
"""Tests for package Z3 (2026-11-07): scripts/ovn_landing_gates.py + scripts/lib_landing_gates.sh (B0 editor-example-leak, B1 step-diff-mismatch, B2 tone-lint,
B3 repair-new-route, B4 test-item-src-edit, B5 call-dropped, B6 landing-cap). Fixtures are the real 2026-11-06/07 incident diffs (billwatch 4d66fd49 / 9a092fdd, shrike-notify
1d796d5 + eea6e65, shrike-monitor 10b7f8d, xlite 1559869d, monitor/gitlark test items that edited source). Every assertion must FAIL on the pre-Z3 behaviour (= no gate):
test_z3_landing_gates.sh runs this file against mutated copies of the module (Z3_MODULE_DIR=<dir holding the mutated ovn_landing_gates.py + lib_landing_gates.sh>)."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
MODDIR = os.environ.get("Z3_MODULE_DIR") or SCRIPTS
spec = importlib.util.spec_from_file_location("ovn_landing_gates", os.path.join(MODDIR, "ovn_landing_gates.py"))
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)
LIB = os.path.join(MODDIR, "lib_landing_gates.sh")
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


def diff(path, removed=(), added=(), new=False, ctx_before=("",), start=10):
    h = "diff --git a/%s b/%s\n" % (path, path)
    if new:
        h += "new file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n" % (path, len(added))
    else:
        h += "--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n" % (path, path, start, len(removed) + len(ctx_before), start, len(added) + len(ctx_before))
        h += "".join(" " + c + "\n" for c in ctx_before)
    h += "".join("-" + r + "\n" for r in removed) + "".join("+" + a + "\n" for a in added)
    return h


def rules(res):
    return sorted(k for k, v in res.items() if v)


# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B1 step-diff-mismatch")
STEP = 'Add role="link" and tabindex="0" to root div in UnifiedBillCard.vue'
bad = diff("billwatch-web/src/components/UnifiedBillCard.vue", ["          <span>Trending</span>"], ["          <span>Buzz</span>"])
good = diff("billwatch-web/src/components/UnifiedBillCard.vue", ['  <div class="card">'], ['  <div class="card" role="link" tabindex="0">'])
r = G.analyse(bad, STEP)
ok("B1a incident 4d66fd49 (step says role/tabindex, diff is Trending->Buzz) is flagged", r["step-diff-mismatch"] and "role" in " ".join(r["step-diff-mismatch"][0]["missing"]),
   json.dumps(r["step-diff-mismatch"]))
ok("B1b a diff that really adds role=\"link\" tabindex=\"0\" is NOT flagged", not G.analyse(good, STEP)["step-diff-mismatch"])
ok("B1c quote style and spacing are normalised (role='link'  tabindex = '0')",
   not G.check_step_diff(STEP, G.parse_diff(diff("a.vue", [], ["<div role='link'   tabindex = '0'>"], ctx_before=("x",)))))
ok("B1d backticked name present only in the post-image of the touched file is accepted",
   not G.check_step_diff("Update `flush_due_held` handling in broker.py", G.parse_diff(diff("broker.py", ["a = 1"], ["a = 2"])), post_text="def flush_due_held(): pass"))
ok("B1e a step with no quoted/identifier tokens is never flagged", not G.check_step_diff("Make the page nicer", G.parse_diff(bad)))
ok("B1f file names in the step text are not 'symbols' (SavedSearchesView.vue)", not G.step_tokens("Update SavedSearchesView.vue to replace native confirm()"))
ok("B1g removal step is satisfied by the token in the REMOVED lines",
   not G.check_step_diff('Remove @click="clearError" from the banner', G.parse_diff(diff("a.vue", ['<div @click="clearError">'], ["<div>"]))))
ok("B1h hallucinated test name: step names test_x_y but diff edits source only",
   G.check_step_diff("Add test_decode_status_codes_invalid_json to backend/tests/test_persistence.py",
                     G.parse_diff(diff("backend/app/persistence.py", ["x"], ["def decode_status_codes(raw): pass"]))) != [])
ok("B1i a token touching the end of a TRUNCATED commit subject is dropped",
   not G.step_tokens("Add test_decode_status_codes_invalid", "", truncated=True) and G.step_tokens("Add test_decode_status_codes_invalid", "", truncated=False))
ok("B1j ratio knob: 1 of 3 missing is below the 0.5 default",
   not G.check_step_diff('Set `aa_bb_cc` and `dd_ee_ff` and `gg_hh_ii`', G.parse_diff(diff("m.py", [], ["aa_bb_cc = 1", "dd_ee_ff = 2"], ctx_before=("c",)))))

ok("B1k a dict literal that gained extra keys after the quoted part still matches (corpus FP b9c3daba)",
   not G.check_step_diff('Add `responses={401: {"description": "Unauthorized"}}` to the route', G.parse_diff(diff("r.py", [], ['@router.get("/x", responses={401: {"description": "Unauthorized"}, 422: {"description": "Invalid"}})']))))
# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B2 tone-lint")
t1 = G.parse_diff(diff("billwatch-web/src/components/UnifiedBillCard.vue", ["        Trending"], ["        Buzz"]))
ok("B2a Trending -> Buzz in a .vue template is flagged", [f["token"] for f in G.check_tone(t1)] == ["Buzz"])
t2 = G.parse_diff(diff("backend/app/main.py", [], ['    return {"greeting": "Hey there! Welcome to shrike-notify."}']))
ok("B2b +return {\"greeting\": \"Hey ... is flagged", len(G.check_tone(t2)) == 1)
t3 = G.parse_diff(diff("billwatch-web/src/components/UnifiedBillCard.vue", [':aria-label="`Bill ${bill.number}: ${bill.title}`"'], [':aria-label="`Hey, check out ${bill.number}: ${bill.title}`"']))
ok("B2c aria-label rewritten to 'Hey, check out' is flagged", G.check_tone(t3) != [])
t4 = G.parse_diff(diff("a.py", ['"""Hey! helper."""'], ['"""Hey! helper v2."""']))
ok("B2d a token that was already in the file's removed lines is NOT 'new'", G.check_tone(t4) == [])
ok("B2e the item/step text asking for the word suppresses it", G.check_tone(t2, "Change the greeting to say Hey") == [])
t5 = G.parse_diff(diff("a.py", [], ["# Yoga class, the Heyday of HeyCorp", "yo = 1  # hey there"]))
ok("B2f longer identifiers / lowercase prose are not flagged", G.check_tone(t5) == [])
t6 = G.parse_diff(diff("docs/NOTES.md", [], ["Hey team"]))
ok("B2g docs are out of scope", G.check_tone(t6) == [])
ok("B2h the token list is configurable", [f["token"] for f in G.check_tone(G.parse_diff(diff("a.py", [], ['x = "Aloha friend"'])), tokens="Aloha|Hey")] == ["Aloha"])
t7 = G.parse_diff(diff("backend/app/static/console.html", ["<h1>shrike-monitor</h1>"], ["<h1>Yo, shrike-monitor</h1>"]))
ok("B2i monitor console <h1> 'Yo, shrike-monitor' is flagged", [f["token"] for f in G.check_tone(t7)] == ["Yo"])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B3 repair-new-route")
rd = diff("backend/app/main.py", [], ['@app.get("/greet")', "def greet():", '    return {"greeting": "Hey there!"}'])
ok("B3a repair round adding @app.get(\"/greet\") is flagged", G.analyse(rd, "", "", "repair")["repair-new-route"] != [])
ok("B3b the same diff in an ordinary step is not a B3 finding", G.analyse(rd, "", "", "step")["repair-new-route"] == [])
ok("B3c a repair that edits a handler body is fine", G.analyse(diff("backend/app/main.py", ["    return 1"], ["    return 2"]), "", "", "repair")["repair-new-route"] == [])
ok("B3d router.post / add_api_route / express app.get('/x') are all routes",
   all(G.check_repair_routes(G.parse_diff(diff(p, [], [l]))) for p, l in [("a.py", '@router.post("/x")'), ("a.py", 'app.add_api_route("/x", f)'), ("a.js", "app.get('/x', h)")]))
ok("B3e a route added in a TEST file during repair is ignored", G.check_repair_routes(G.parse_diff(diff("backend/tests/test_x.py", [], ['@app.get("/probe")']))) == [])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B4 test-item-src-edit")
src_edit = G.parse_diff(diff("backend/app/services/scheduler.py", ["a"], ["b"]) + diff("backend/tests/test_scheduler.py", [], ["def test_x(): pass"], new=True))
ok("B4a cat:test item that edits scheduler.py is flagged", [f["file"] for f in G.check_test_item_scope(src_edit, "[T3] x (cat:test; multifile:no)")] == ["backend/app/services/scheduler.py"])
ok("B4b 'Create test file ...' step text is a test item", G.check_test_item_scope(src_edit, "", "Create test file backend/tests/test_scheduler.py with ...") != [])
ok("B4c a feature item (cat:python) touching source is not a test item", G.check_test_item_scope(src_edit, "[T3] x (cat:python)", "add foo") == [])
ok("B4d a test item that only touches test files is clean", G.check_test_item_scope(G.parse_diff(diff("backend/tests/test_a.py", [], ["x"])), "(cat:test)") == [])
ok("B4e declared files all tests => test item without a cat tag", G.is_test_item("", "tidy", "backend/tests/test_a.py web/src/__tests__/b.spec.ts"))
ok("B4f same-basename source companion (old scope check allowed it) is flagged here",
   G.check_test_item_scope(G.parse_diff(diff("app/foo.py", ["a"], ["b"])), "(cat:test)", "", "tests/test_foo.py") != [])
ok("B4g docs/json next to a test item are not 'source'", G.check_test_item_scope(G.parse_diff(diff("docs/openapi.json", ["a"], ["b"])), "(cat:test)") == [])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B5 call-dropped")
GD_OLD = """extends Node

func sync_from_battle(units: Array, fallen: Array = []) -> void:
	var updated = []
	for e in _entries:
		updated.append(e)
	_entries = updated
	_save_roster()

func other() -> void:
	pass
"""
GD_NEW = """extends Node

func sync_from_battle(units: Array, fallen: Array = []) -> void:
	var updated = []
	for e in _entries:
		updated.append(e)
	_entries = updated
	_ensure_squad_deployed()

func _ensure_squad_deployed() -> void:
	if get_deployed_count() > 0:
		return
	_save_roster()

func other() -> void:
	pass
"""
r = G.check_call_drop("scripts/roster/roster_manager.gd", GD_OLD, GD_NEW)
ok("B5a xlite 1559869d: sync_from_battle loses _save_roster()", [(f["function"], f["call"]) for f in r] == [("sync_from_battle", "_save_roster")], json.dumps(r))
PY_OLD = "def run(db):\n    rows = load(db)\n    flush(db)\n    db.commit()\n    return len(rows)\n"
ok("B5b python AST: a lost `db.commit()` statement is flagged", [f["call"] for f in G.check_call_drop("a.py", PY_OLD, "def run(db):\n    rows = load(db)\n    flush(db)\n    return len(rows)\n")] == ["commit"])
ok("B5c call still mentioned (moved into a variable / passed on) is not flagged",
   G.check_call_drop("a.py", PY_OLD, "def run(db):\n    rows = load(db)\n    flush(db)\n    fn = db.commit\n    fn()\n    return len(rows)\n") == [])
ok("B5d a mostly rewritten function is a refactor, not a drop",
   G.check_call_drop("a.py", PY_OLD, "def run(db):\n    items = fetch(db)\n    store(items)\n    audit(items)\n    return items\n") == [])
ok("B5e builtins / logging calls (print, log.info) dropped are ignored",
   G.check_call_drop("a.py", "def f(x):\n    a = x + 1\n    b = a * 2\n    print(a)\n    return b\n", "def f(x):\n    a = x + 1\n    b = a * 2\n    return b\n") == [])
ok("B5f unparsable python is skipped, never an error", G.check_call_drop("a.py", PY_OLD, "def run(:\n") == [])
ok("B5g identical text => nothing", G.check_call_drop("a.py", PY_OLD, PY_OLD) == [])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B6 landing-cap")
NOW = 1799000000


def ts(off_h):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - int(off_h * 3600)))


rows = [{"ts": ts(h), "class": c, "item_hash": "aaa"} for h, c in [(1, "landed"), (2, "landed-uncredited"), (3, "landed"), (30, "landed"), (4, "noop"), (5, "reverted")]]
rows += [{"ts": ts(1), "class": "landed", "item_hash": "bbb"}, {"ts": ts(1), "class": "landed", "item_hash": ""}]
c = G.landing_counts(rows, NOW)
ok("B6a counts landed + landed-uncredited inside 24h only, per hash", c == {"aaa": 3, "bbb": 1}, str(c))
ok("B6b a wider window picks up the 30h-old row", G.landing_counts(rows, NOW, 48)["aaa"] == 4)
ok("B6g sibling items sharing a [feat:] item_hash but with different LINE hashes are counted separately (84 of 341 hashes would false-trip at feat level)",
   G.landing_counts([{"ts": ts(1), "class": "landed", "item_hash": "feat", "item_line_hash": "l%d" % i} for i in range(5)], NOW) == {"l0": 1, "l1": 1, "l2": 1, "l3": 1, "l4": 1})
ok("B6h the same LINE landing 3x is counted as 3", G.landing_counts([{"ts": ts(i + 1), "class": "landed-uncredited", "item_hash": "feat", "item_line_hash": "same"} for i in range(3)], NOW) == {"same": 3})
tmp = tempfile.mkdtemp(prefix="z3-test-")
op = os.path.join(tmp, "outcomes.jsonl")
with open(op, "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
    f.write("garbage not json\n")
out = subprocess.run([PY, os.path.join(MODDIR, "ovn_landing_gates.py"), "cap-check", "--outcomes", op, "--hash", "aaa", "--now", str(NOW), "--n", "4", "--pending", "1"], capture_output=True, text=True).stdout
ok("B6c cap-check --pending: 3 stored + a not-yet-written landing reaches N=4 (the CLI knob stays; item_guard no longer uses it)", json.loads(out)["over"] is True, out)
out = subprocess.run([PY, os.path.join(MODDIR, "ovn_landing_gates.py"), "cap-check", "--outcomes", op, "--hash", "aaa", "--now", str(NOW), "--n", "4"], capture_output=True, text=True).stdout
ok("B6d without the pending landing 3 < 4 is not over", json.loads(out)["over"] is False, out)
prog = os.path.join(tmp, "OVERNIGHT_PROGRESS.md")
open(prog, "w").write("# P\n- [ ] item one [feat:x]\n- [ ] item two\n- [x] item one [feat:x]\n")
ok("B6e park_item tags ONLY the open line with the AUTO-SKIP marker", G.park_item(prog, "- [ ] item one [feat:x]", 5) == 1 and open(prog).read().count("AUTO-SKIP landed 5x in 24h") == 1
   and "- [ ] item two\n" in open(prog).read() and "- [x] item one [feat:x]" in open(prog).read())
ok("B6f park_item is idempotent (an already parked line is skipped)", G.park_item(prog, "item one [feat:x]", 6) == 0)

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B0 editor-example-leak")
LEAK = "The user wants to change the greeting to be more casual. Looking at the UnifiedBillCard.vue component, I don't see an explicit \"greeting\""
ok("B0a the editor reasoning about the aider few-shot is detected", G.check_editor_leak(LEAK) != [])
ok("B0b a normal editor log is clean", G.check_editor_leak("I will add a test class at the end of the file.\n--- a/x.py\n+++ b/x.py") == [])
ok("B0c tool_call architect is recorded", G.check_editor_leak("<tool_call> <function=Read>\n" + LEAK)[0]["tool_call_architect"] is True)
ok("B0d show_greeting.py is detected too", G.check_editor_leak("Switch the greeting text from Hello to Hey in show_greeting.py") != [])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== CLI + shell glue (real git repo, bash)")
repo = os.path.join(tmp, "repo")
os.makedirs(repo)
ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", NTFY_SERVER="http://127.0.0.1:9", OVN_NOTIFY_DISABLE="1", TZ="UTC",
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
for k in ("OVN_Z3_STEP_DIFF", "OVN_Z3_TONE", "OVN_Z3_REPAIR_ROUTE", "OVN_Z3_TEST_SRC", "OVN_Z3_CALL_DROP", "OVN_Z3_LANDING_CAP", "OVN_Z3_EDITOR_LEAK"):
    ENV.pop(k, None)


def sh(cmd, env=None):
    p = subprocess.run(cmd, cwd=repo, env=env or ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def git(*a):
    return sh(["git", "-c", "user.name=t", "-c", "user.email=t@t"] + list(a))


git("init", "-q")
os.makedirs(os.path.join(repo, "backend/app"))
open(os.path.join(repo, "backend/app/main.py"), "w").write("from fastapi import FastAPI\napp = FastAPI()\n\n\n@app.get('/health')\ndef health():\n    return {'ok': True}\n")
git("add", "-A")
git("commit", "-q", "-m", "base")


def dirty_greet():
    with open(os.path.join(repo, "backend/app/main.py"), "a") as f:
        f.write('\n\n@app.get("/greet")\ndef greet():\n    return {"greeting": "Hey there! Welcome."}\n')


def clean():
    git("reset", "-q", "--hard", "HEAD")
    git("clean", "-fdq")


def gate(kind, extra_env=None, desc="", item="", alog=""):
    env = dict(ENV)
    env.update(extra_env or {})
    sd = os.path.join(tmp, "state")
    shutil.rmtree(sd, ignore_errors=True)
    script = '. "%s"; z3_step_gate "%s" "%s" "$1" "$2" "" "$3" "%s" "lbl"; echo "rc=$? refuse=$Z3_REFUSE"' % (LIB, repo, kind, sd)
    p = subprocess.run(["bash", "-c", script, "x", desc, item, alog], env=env, capture_output=True, text=True)
    log = ""
    try:
        log = open(os.path.join(sd, "landing_gates_shadow.log")).read()
    except OSError:
        pass
    return p.stdout.strip(), log


dirty_greet()
o, log = gate("repair", desc="", item="[T3] x (cat:python)")
ok("S1 shadow (default): the repair route + tone are JOURNALLED and rc=0, nothing refused", "rc=0 refuse=" in o and "repair-new-route" in log and "tone-lint" in log and '"mode": "shadow"' in log, o + "|" + log[:200])
o, log = gate("repair", {"OVN_Z3_REPAIR_ROUTE": "enforce"}, item="[T3] x (cat:python)")
ok("S2 OVN_Z3_REPAIR_ROUTE=enforce refuses the repair round (rc=1, reason names the rule)", o.startswith("rc=1 refuse=repair-new-route"), o)
o, log = gate("step", {"OVN_Z3_REPAIR_ROUTE": "enforce"}, item="[T3] x (cat:python)")
ok("S3 the same diff in a normal step is NOT refused by the repair gate", o.startswith("rc=0") and "repair-new-route" not in log, o)
o, log = gate("repair", {"OVN_Z3_TONE": "enforce"}, item="[T3] x (cat:python)")
ok("S4 OVN_Z3_TONE=enforce refuses on the greeting", o.startswith("rc=1 refuse=tone-lint"), o)
o, log = gate("repair", {"OVN_Z3_REPAIR_ROUTE": "off", "OVN_Z3_TONE": "off"}, item="[T3] x (cat:python)")
ok("S5 off = silent: no journal rows for the disabled gates", o.startswith("rc=0") and "repair-new-route" not in log and "tone-lint" not in log, o + "|" + log)
o, log = gate("repair", {"OVN_Z3_REPAIR_ROUTE": "bogus"}, item="")
ok("S6 an invalid flag value degrades to shadow, not enforce", o.startswith("rc=0") and "repair-new-route" in log, o)
clean()
# B4 via shell: test item editing source
with open(os.path.join(repo, "backend/app/main.py"), "a") as f:
    f.write("\nX = 1\n")
o, log = gate("step", {"OVN_Z3_TEST_SRC": "enforce"}, desc="Add test for health", item="[T3] backend/tests/test_h.py - Add test (cat:test; multifile:no)")
ok("S7 OVN_Z3_TEST_SRC=enforce refuses a test item that edited app source", o.startswith("rc=1 refuse=test-item-src-edit"), o)
o, log = gate("step", {}, desc="Add test for health", item="[T3] backend/tests/test_h.py - Add test (cat:test; multifile:no)")
ok("S8 default (shadow) journals it and lets it through", o.startswith("rc=0") and "test-item-src-edit" in log, o)
clean()
# B0 via shell
leak = os.path.join(tmp, "step.log")
open(leak, "w").write(LEAK)
with open(os.path.join(repo, "backend/app/main.py"), "a") as f:
    f.write("\nY = 2\n")
o, log = gate("step", {}, alog=leak)
ok("S9 B0 shadow: leak journalled, rc=0", o.startswith("rc=0") and "editor-example-leak" in log, o + log)
o, log = gate("step", {"OVN_Z3_EDITOR_LEAK": "enforce"}, alog=leak)
ok("S10 B0 enforce refuses", o.startswith("rc=1 refuse=editor-example-leak"), o)
clean()
o, log = gate("step", {"OVN_Z3_EDITOR_LEAK": "enforce"}, alog=leak)
ok("S11 a clean tree with a leak log is still judged on the log only (diff empty)", "editor-example-leak" in o or o.startswith("rc=1"), o)
# CLI step-check exit/shape and fail-open
p = subprocess.run([PY, os.path.join(MODDIR, "ovn_landing_gates.py"), "step-check", "--diff", "/nonexistent/path", "--desc", "x"], capture_output=True, text=True)
ok("C1 step-check with an unreadable diff exits 0 with valid JSON (fail-open)", p.returncode == 0 and "findings" in json.loads(p.stdout))
p = subprocess.run(["bash", "-c", '. "%s"; z3_step_gate /nonexistent step x y z "" "%s" l; echo rc=$?' % (LIB, tmp)], capture_output=True, text=True)
ok("C2 z3_step_gate on a missing worktree is rc=0", "rc=0" in p.stdout, p.stdout)
# B6 via shell
sd = os.path.join(tmp, "st6")
os.makedirs(sd)
with open(os.path.join(sd, "outcomes.jsonl"), "w") as f:
    for h in (1, 2, 3):
        f.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - h * 600)), "class": "landed", "item_hash": "hhh"}) + "\n")
rd = os.path.join(tmp, "rd6")
os.makedirs(rd)
subprocess.run(["git", "-C", rd, "init", "-q"], env=ENV)
open(os.path.join(rd, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n- [ ] the item\n")
subprocess.run(["git", "-C", rd, "-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], env=ENV)
subprocess.run(["git", "-C", rd, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "b"], env=ENV)
p = subprocess.run(["bash", "-c", '. "%s"; z3_landing_cap "%s" "%s" hhh "- [ ] the item" lbl 0; echo rc=$?' % (LIB, sd, rd)], env=ENV, capture_output=True, text=True)
ok("S12 B6 shadow: journals the cap and does NOT park", "rc=0" in p.stdout and "PARKED" not in p.stdout and '"rule":"landing-cap"' in open(os.path.join(sd, "landing_gates_shadow.log")).read()
   and "AUTO-SKIP" not in open(os.path.join(rd, "OVERNIGHT_PROGRESS.md")).read(), p.stdout + p.stderr)
env6 = dict(ENV, OVN_Z3_LANDING_CAP="enforce")
p = subprocess.run(["bash", "-c", '. "%s"; z3_landing_cap "%s" "%s" hhh "- [ ] the item" lbl 0; echo rc=$?' % (LIB, sd, rd)], env=env6, capture_output=True, text=True)
ok("S13 B6 enforce: parks the open line with AUTO-SKIP and commits it", "PARKED 1" in p.stdout and "AUTO-SKIP landed 3x in 24h" in open(os.path.join(rd, "OVERNIGHT_PROGRESS.md")).read()
   and "landing cap" in subprocess.run(["git", "-C", rd, "log", "-1", "--format=%s"], capture_output=True, text=True).stdout, p.stdout + p.stderr)
p = subprocess.run(["bash", "-c", '. "%s"; z3_landing_cap "%s" "%s" hhh "- [ ] the item" lbl 0; echo rc=$?' % (LIB, sd, rd)], env=dict(ENV, OVN_Z3_LANDING_CAP="off"), capture_output=True, text=True)
ok("S14 B6 off is silent", p.stdout.strip() == "rc=0")

# B5 via shell: enforce is accepted but never vetoes (FLAG only)
open(os.path.join(repo, "backend/app/jobs.py"), "w").write("def run(db):\n    rows = load(db)\n    flush(db)\n    db.commit()\n    return len(rows)\n")
git("add", "-A")
git("commit", "-q", "-m", "jobs")
open(os.path.join(repo, "backend/app/jobs.py"), "w").write("def run(db):\n    rows = load(db)\n    flush(db)\n    return len(rows)\n")
o, log = gate("step", {"OVN_Z3_CALL_DROP": "enforce"}, desc="tidy run", item="[T3] x (cat:python)")
ok("S15 B5 is FLAG-only: OVN_Z3_CALL_DROP=enforce journals call-dropped but rc=0 (never a veto)", o.startswith("rc=0") and "call-dropped" in log and '"mode": "shadow"' in log, o + "|" + log[:300])
clean()

# B6 wired into the REAL ovn_item_guard.sh landing path
print("== B6 in ovn_item_guard.sh (landing path)")
gd = os.path.join(tmp, "g")
grepo, gstate = os.path.join(gd, "repo"), os.path.join(gd, "state")
os.makedirs(grepo)
os.makedirs(os.path.join(gstate, "item_fails"))
subprocess.run(["git", "-C", grepo, "init", "-q"], env=ENV)
ITEM = "- [ ] [T3] backend/x.py - do the thing (cat:python) [feat:myrepo-20261107-thing]"
open(os.path.join(grepo, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n## Next Steps\n" + ITEM + "\n")
subprocess.run(["git", "-C", grepo, "add", "-A"], env=ENV)
subprocess.run(["git", "-C", grepo, "commit", "-q", "-m", "b"], env=ENV)
HH = "0123456789abcdef0123456789abcdef"
with open(os.path.join(gstate, "outcomes.jsonl"), "w") as f:
    for h in (1, 2, 3):
        f.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - h * 900)), "class": "landed-uncredited", "item_hash": HH, "item_line_hash": __import__("hashlib").md5(ITEM[len("- [ ] "):].encode()).hexdigest()}) + "\n")
tl = os.path.join(gd, "task.log")
open(tl, "w").write("stage-item-hash %s\nstage-item-line %s\n" % (HH, ITEM[len("- [ ] "):]))
GUARD = os.path.join(MODDIR, "ovn_item_guard.sh")
if not os.path.exists(GUARD):
    GUARD = os.path.join(SCRIPTS, "ovn_item_guard.sh")
# the guard must see the (possibly mutated) lib next to it: copy the guard + its sibling libs into a scratch scripts dir
gs = os.path.join(gd, "scripts")
shutil.copytree(SCRIPTS, gs, ignore=shutil.ignore_patterns("test", "__pycache__", "cov"))
shutil.copy(GUARD, os.path.join(gs, "ovn_item_guard.sh"))
shutil.copy(LIB, os.path.join(gs, "lib_landing_gates.sh"))
shutil.copy(os.path.join(MODDIR, "ovn_landing_gates.py"), os.path.join(gs, "ovn_landing_gates.py"))
r1 = subprocess.run(["bash", os.path.join(gs, "ovn_item_guard.sh"), grepo, "pushed(tests:pass) stage(higher-tier)", gstate, "ongoing-myrepo", tl], env=ENV, capture_output=True, text=True)
shadow = open(os.path.join(gstate, "landing_gates_shadow.log")).read() if os.path.exists(os.path.join(gstate, "landing_gates_shadow.log")) else ""
ok("S16 item_guard landing path: shadow journals the cap (3 rows, the current landing is one of them, >= N=3), progress untouched", '"rule":"landing-cap"' in shadow and "AUTO-SKIP" not in open(os.path.join(grepo, "OVERNIGHT_PROGRESS.md")).read(),
   r1.stdout + r1.stderr + shadow)
r2 = subprocess.run(["bash", os.path.join(gs, "ovn_item_guard.sh"), grepo, "pushed(tests:pass) stage(higher-tier)", gstate, "ongoing-myrepo", tl], env=dict(ENV, OVN_Z3_LANDING_CAP="enforce"), capture_output=True, text=True)
ok("S17 item_guard landing path: OVN_Z3_LANDING_CAP=enforce parks the item (AUTO-SKIP landed 3x) and commits", "AUTO-SKIP landed 3x in 24h" in open(os.path.join(grepo, "OVERNIGHT_PROGRESS.md")).read(), r2.stdout + r2.stderr)


# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== D1/D2 B6 via item_guard: count the current landing once; the park is pushed and reported")
import hashlib


def guard_env(name, nrows, bare=False):
    d = os.path.join(tmp, name)
    gr, gst = os.path.join(d, "repo"), os.path.join(d, "state")
    os.makedirs(gr)
    os.makedirs(os.path.join(gst, "item_fails"))
    g = lambda *a: subprocess.run(["git", "-C", gr, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), env=ENV, capture_output=True, text=True)
    g("init", "-q")
    g("checkout", "-q", "-b", "overnight/feature")
    open(os.path.join(gr, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n## Next Steps\n" + ITEM + "\n")
    g("add", "-A")
    g("commit", "-q", "-m", "b")
    origin = os.path.join(d, "origin.git")
    if bare:
        subprocess.run(["git", "init", "-q", "--bare", origin], env=ENV)
        g("remote", "add", "origin", origin)
        g("push", "-q", "-u", "origin", "overnight/feature")
    with open(os.path.join(gst, "outcomes.jsonl"), "w") as f:
        for h in range(1, nrows + 1):   # row 1 = THIS cycle (record_outcome already ran), the others are earlier landings
            f.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - h * 900)), "class": "landed-uncredited", "item_hash": HH,
                                "item_line_hash": hashlib.md5(ITEM[len("- [ ] "):].encode()).hexdigest()}) + "\n")
    t = os.path.join(d, "task.log")
    open(t, "w").write("stage-item-hash %s\nstage-item-line %s\n" % (HH, ITEM[len("- [ ] "):]))
    return gr, gst, t, origin


def run_guard(gr, gst, t, **env):
    return subprocess.run(["bash", os.path.join(gs, "ovn_item_guard.sh"), gr, "pushed(tests:pass) stage(higher-tier)", gst, "ongoing-myrepo", t],
                          env=dict(ENV, **env), capture_output=True, text=True)


gr, gst, t, _o = guard_env("d1a", 2)
r = run_guard(gr, gst, t, OVN_Z3_LANDING_CAP="enforce")
ok("D1a 2 real landings (prior + current row) with N=3 are NOT parked (the old pending=1 double-counted the current landing: 'landed 3x')",
   "AUTO-SKIP" not in open(os.path.join(gr, "OVERNIGHT_PROGRESS.md")).read() and "PARKED" not in r.stdout, r.stdout + r.stderr)
gr, gst, t, _o = guard_env("d1b", 3)
r = run_guard(gr, gst, t, OVN_Z3_LANDING_CAP="enforce")
ok("D1b the 3rd real landing parks and says 'landed 3x' (exactly N)", "AUTO-SKIP landed 3x in 24h" in open(os.path.join(gr, "OVERNIGHT_PROGRESS.md")).read(), r.stdout + r.stderr)
gr, gst, t, _o = guard_env("d1c", 2)
r = run_guard(gr, gst, t)
ok("D1c shadow with 2 landings journals no landing-cap row", not os.path.exists(os.path.join(gst, "landing_gates_shadow.log")) or "landing-cap" not in open(os.path.join(gst, "landing_gates_shadow.log")).read())

gr, gst, t, origin = guard_env("d2", 3, bare=True)
r = run_guard(gr, gst, t, OVN_Z3_LANDING_CAP="enforce")
rem = subprocess.run(["git", "--git-dir", origin, "show", "overnight/feature:OVERNIGHT_PROGRESS.md"], capture_output=True, text=True).stdout
ok("D2a the park commit is PUSHED to origin (bare) like the sibling guards", "AUTO-SKIP landed 3x" in rem, rem + r.stderr)
subprocess.run(["git", "-C", gr, "fetch", "-q", "origin"], env=ENV)
subprocess.run(["git", "-C", gr, "reset", "-q", "--hard", "origin/overnight/feature"], env=ENV)
ok("D2b the stage runner's `reset --hard origin/overnight/feature` no longer erases the park", "AUTO-SKIP landed 3x" in open(os.path.join(gr, "OVERNIGHT_PROGRESS.md")).read())
ok("D2c the PARKED notice reaches the cycle log (stdout) and the reason on stderr (not /dev/null)", "PARKED 1" in r.stdout and "landing-cap parked" in r.stderr, r.stdout + "|" + r.stderr)
# push race: the remote moved under us -> merge (never rebase) + retry
gr, gst, t, origin = guard_env("d2r", 3, bare=True)
other = os.path.join(tmp, "d2r", "other")
subprocess.run(["git", "clone", "-q", origin, other], env=ENV, capture_output=True)
open(os.path.join(other, "x.txt"), "w").write("x")
for c in (["add", "-A"], ["commit", "-q", "-m", "other"], ["push", "-q", "origin", "overnight/feature"]):
    subprocess.run(["git", "-C", other, "-c", "user.name=t", "-c", "user.email=t@t"] + c, env=ENV, capture_output=True)
r = run_guard(gr, gst, t, OVN_Z3_LANDING_CAP="enforce")
rem = subprocess.run(["git", "--git-dir", origin, "show", "overnight/feature:OVERNIGHT_PROGRESS.md"], capture_output=True, text=True).stdout
ok("D2d a non-fast-forward push is merged and retried: park reaches origin", "AUTO-SKIP landed 3x" in rem, r.stderr)

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== D3 bounded journal / bounded work")
big = os.path.join(repo, "gen_big.py")
with open(big, "w") as f:
    for i in range(400000):
        f.write('def f%d(): return "Hey"\n' % i)
sd3 = os.path.join(tmp, "st3")
shutil.rmtree(sd3, ignore_errors=True)
t0 = time.time()
script = '. "%s"; z3_step_gate "%s" step "" "" "" "" "%s" lbl; echo rc=$?' % (LIB, repo, sd3)
p = subprocess.run(["bash", "-c", script], env=ENV, capture_output=True, text=True)
el = time.time() - t0
jl = os.path.join(sd3, "landing_gates_shadow.log")
jtxt = open(jl).read() if os.path.exists(jl) else ""
rows3 = [json.loads(x) for x in jtxt.splitlines() if x.strip()]
tone = [r for r in rows3 if r.get("rule") == "tone-lint"]
ok("D3a a 20MB single-file add of 400k matching lines yields <= 51 tone rows (50 + one 'truncated N more')", 0 < len(tone) <= 51 and any(r.get("truncated") for r in tone), "%d rows" % len(tone))
ok("D3b the journal from that one call is small (< 100 KB) and valid JSON per line", len(jtxt) < 100000 and len(rows3) == len([x for x in jtxt.splitlines() if x.strip()]), str(len(jtxt)))
ok("D3c the call stays bounded (< 60 s) and rc=0", el < 60 and "rc=0" in p.stdout, "%.1fs %s" % (el, p.stdout))
p = subprocess.run(["bash", "-c", '. "%s"; _z3_worktree_diff "%s" | wc -c' % (LIB, repo)], env=dict(ENV, OVN_Z3_MAX_DIFF_BYTES="100000"), capture_output=True, text=True)
ok("D3f the diff handed to the gate is capped at OVN_Z3_MAX_DIFF_BYTES", p.stdout.strip().isdigit() and 0 < int(p.stdout.strip()) <= 100000, p.stdout + p.stderr)
os.remove(big)
os.environ["OVN_Z3_MAX_DIFF_BYTES"] = "2000"
late = diff("a.py", [], ['x = %d' % i for i in range(400)] + ['y = "Hey"'])
ok("D3g module scans only the first OVN_Z3_MAX_DIFF_BYTES of a diff (bounded work)", G.analyse(late)["tone-lint"] == [])
del os.environ["OVN_Z3_MAX_DIFF_BYTES"]
ok("D3g' ...and sees it when the diff fits", G.analyse(late)["tone-lint"] != [])
# direct module bound
many = diff("a.py", [], ['x = "Hey"'] * 5000)
ok("D3d module: findings per rule capped (analyse)", len(G.analyse(many)["tone-lint"]) <= 51 and G.analyse(many)["tone-lint"][-1].get("truncated") == 4950)
# rotation
sd4 = os.path.join(tmp, "st4")
os.makedirs(sd4)
with open(os.path.join(sd4, "landing_gates_shadow.log"), "w") as f:
    for i in range(3000):
        f.write(json.dumps({"rule": "old", "i": i, "pad": "x" * 60}) + "\n")
dirty_greet()
script = '. "%s"; z3_step_gate "%s" repair "" "[T3] x (cat:python)" "" "" "%s" lbl; echo rc=$?' % (LIB, repo, sd4)
subprocess.run(["bash", "-c", script], env=dict(ENV, OVN_Z3_JOURNAL_MAX_BYTES="100000"), capture_output=True, text=True)
jl4 = os.path.join(sd4, "landing_gates_shadow.log")
lines4 = open(jl4).read().splitlines()
ok("D3e the journal is rotated by size (kept the last half, whole lines only, new rows appended)", os.path.getsize(jl4) < 100000 and all(json.loads(x) for x in lines4) and
   any('"tone-lint"' in x for x in lines4) and json.loads(lines4[0]).get("rule") == "old" and json.loads(lines4[0])["i"] > 0 and not [f for f in os.listdir(sd4) if ".rot." in f], "%d %s" % (os.path.getsize(jl4), os.listdir(sd4)))
clean()

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== shadow mode changes nothing (no intent-to-add in the real index)")
open(os.path.join(repo, "brand_new.py"), "w").write('x = "Hey there"\n')
gate("step", {}, desc="x", item="")
st = git("status", "--porcelain")[1]
ok("IX1 after a shadow gate a brand-new file is still untracked ('??'), not ' A'; the index is empty", "?? brand_new.py" in st and git("diff", "--cached", "--name-only")[1].strip() == "" and " A " not in st, st)
o, log = gate("step", {}, desc="x", item="")
ok("IX2 ...and the new file's content was still seen by the gate (tone-lint journalled)", "tone-lint" in log and "brand_new.py" in log, log[:200])
clean()

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== D4 B1 rename / replace / from-to steps (the old token legitimately disappears)")
for desc, d_ok, d_bad in [
    ("Rename `old_name` to `new_name` in a.py", diff("a.py", ["def old_name(): pass"], ["def new_name(): pass"]), diff("a.py", ["x"], ["y = 1"])),
    ("Change the error message from 'Not found' to 'Missing'", diff("a.py", ['raise E("Not found")'], ['raise E("Missing")']), diff("a.py", ["x"], ["y = 1"])),
    ("Replace `old_thing()` with `new_thing()` in b.py", diff("b.py", ["old_thing()"], ["new_thing()"]), diff("b.py", ["x"], ["y = 1"])),
    ("Change the label `Trending` to `Hotness`", diff("c.vue", ["  Trending"], ["  Hotness"]), diff("c.vue", ["x"], ["y = 1"])),
    ("Replace a_helper() with b_helper() in d.py", diff("d.py", ["a_helper()"], ["b_helper()"]), diff("d.py", ["x"], ["y = 1"])),
    ("Switch from old_client to new_client in e.py", diff("e.py", ["import old_client"], ["import new_client"]), diff("e.py", ["x"], ["y = 1"])),
]:
    ok("D4 correct step not flagged: " + desc, not G.check_step_diff(desc, G.parse_diff(d_ok)), json.dumps(G.check_step_diff(desc, G.parse_diff(d_ok))))
    ok("D4 ... but the NEW side missing IS still flagged: " + desc, G.check_step_diff(desc, G.parse_diff(d_bad)) != [])
ok("D4 only tokens that must be ADDED are counted (rename)", [t["tok"] for t in G.step_tokens("Rename `old_name` to `new_name` in a.py")] == ["new_name"])
ok("D4 true positive kept: billwatch role=link/tabindex still flagged", G.analyse(bad, STEP)["step-diff-mismatch"] != [])

# ---------------------------------------------------------------------------------------------------------------------------------------------------------
print("== B2 exemptions (tests / fixtures / locale / docs / data files) + precedence slip")
for path, line in [("tests/test_chat.py", 'assert reply == "Hi there, how can I help?"'), ("tests/fixtures/cards.py", 'CARDS = ["Fizz Buzz"]'), ("src/locales/es.ts", "greeting: 'Yo soy'"),
                   ("web/src/__tests__/a.test.ts", "expect(t('Yo')).toBe(1)"), ("docs/index.html", "<h1>Whoa</h1>"), ("docs/guide.rst", "Hey you"), ("data/notes.txt", "Hey there"),
                   ("src/i18n/en.json", '{"a": "Hey"}'), ("backend/testdata/s.py", 'x = "Yo"'), ("README.rst", "Hey"), ("seed/names.csv", "Hey,Yo"), ("notes/todo.txt", "Hey team"), ("config/app.yaml", "motd: Hey"), ("assets/banner.svg", "<text>Yo</text>"), ("web/strings.po", "msgstr \"Hey\"")]:
    ok("B2 exempt: " + path, G.check_tone(G.parse_diff(diff(path, [], [line]))) == [])
ok("B2 product source is still linted (.vue/.py/.html)", all(G.check_tone(G.parse_diff(diff(p, [], [l]))) for p, l in [("web/src/Card.vue", "<b>Hey!</b>"), ("app/main.py", 'x = "Yo, hi"'), ("app/static/index.html", "<h1>Buzz</h1>")]))

print("== B4 test-helper directories are test paths")
for pth in ["tests/helpers/util.py", "scripts/test_helpers/helper.gd", "backend/conftest.py", "web/src/__mocks__/api.ts", "app/fixtures/x.py", "app/testdata/x.json", "lib/testutils/x.kt", "lib/test_support/x.py"]:
    ok("B4 test path: " + pth, G.is_test_path(pth) and not G.is_source_path(pth))
ok("B4 a test item editing scripts/test_helpers/helper.gd is NOT flagged", G.check_test_item_scope(G.parse_diff(diff("scripts/test_helpers/helper.gd", ["a"], ["b"])), "(cat:test)") == [])
ok("B4 ...but app source still is", G.check_test_item_scope(G.parse_diff(diff("scripts/game/helper.gd", ["a"], ["b"])), "(cat:test)") != [])

print("== B0 paraphrased replays + every attempt")
for txt in ["I will update the greeting in the file to be more casual as requested", "make the greeting more casual", "Switch the greeting from \"Hello\" to \"Hey\"", "Hello -> Hey", "the greeting should sound casual", "Hello there, Hey"]:
    ok("B0 paraphrase detected: " + txt[:50], G.check_editor_leak(txt) != [])
ok("B0 an ordinary log line is not a leak", G.check_editor_leak("Applied edit to app/greeting.py\nAdded a unit test for the casual router") == [])
leak_nf = os.path.join(tmp, "noedit.log")
open(leak_nf, "w").write("Please add files\n" + LEAK)
sd5 = os.path.join(tmp, "st5")
p = subprocess.run(["bash", "-c", '. "%s"; z3_leak_gate "%s" "%s" lbl step; echo rc=$?' % (LIB, leak_nf, sd5)], env=ENV, capture_output=True, text=True)
ok("B0 z3_leak_gate journals on its own (no diff, no edit needed): shadow rc=0", "rc=0" in p.stdout and "editor-example-leak" in open(os.path.join(sd5, "landing_gates_shadow.log")).read(), p.stdout + p.stderr)
p = subprocess.run(["bash", "-c", '. "%s"; z3_leak_gate "%s" "%s" lbl step; echo "rc=$? $Z3_REFUSE"' % (LIB, leak_nf, sd5)], env=dict(ENV, OVN_Z3_EDITOR_LEAK="enforce"), capture_output=True, text=True)
ok("B0 z3_leak_gate enforce returns 1", p.stdout.startswith("rc=1 editor-example-leak"), p.stdout)
runner = open(os.path.join(SCRIPTS, "..", "ovn_stage_runner.sh")).read()
ok("B0 the stage runner calls z3_leak_gate for non-successful attempts", 'z3_leak_gate "$atmp" state' in runner and '[ "$rc" != 0 ] && [ "$fa" != "landing-gate" ]' in runner)

shutil.rmtree(tmp, ignore_errors=True)
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
