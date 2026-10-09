#!/usr/bin/env python3
"""qa/gut_error_ratchet.py: shadow ratchet over the SCRIPT ERRORs a green GUT suite hides (2026-10-09).

Parser fixtures are cut from a REAL GUT 9.4.0 / Godot 4.3 full-suite log of xlite (394 scripts, 2992 tests all passing, 180 SCRIPT ERRORs at 6 signatures),
plus an ANSI-coloured variant, a zero-error log and a parse-error log (from the import log of the same tree). The CLI is driven with a shim `godot` that
prints a fixture log. Covers: two-line SCRIPT ERROR/at pairs, signatures ignore line numbers, new vs removed detection, the baseline is only ever written by
--update-baseline, per-signature-per-day alert dedupe, shadow mode never exits non-zero (enforce does), kill switch, the live clone is untouched.
The same battery then runs against MUTATED copies of the tool: each mutant must fail it."""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOL = os.path.join(ROOT, "qa", "gut_error_ratchet.py")
sys.path.insert(0, os.path.join(ROOT, "qa"))
import gut_error_ratchet as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]

# ---------------------------------------------------------------- real log excerpts
TXT_A = "Invalid assignment of property or key 'text' with value of type 'String' on a base object of type 'Nil'."
LOG_BASE = (
    "---  GUT  ---\nGodot version:  4.3.0\nGUT version:  9.4.0\n\nres://tests/battle/test_battle_hud.gd\n* test_hud_refresh\n"
    "ERROR: Parameter \"data.tree\" is null.\n   at: get_tree (scene/main/node.h:446)\n"
    "SCRIPT ERROR: Cannot call method 'create_timer' on a null value.\n          at: _end_battle (res://scripts/battle/battle.gd:4554)\n"
    "SCRIPT ERROR: " + TXT_A + "\n          at: _refresh_hit_chance_display (res://scripts/battle/battle.gd:4712)\n"
    "SCRIPT ERROR: " + TXT_A + "\n          at: _refresh_ap_display (res://scripts/battle/battle.gd:4680)\n"
    "SCRIPT ERROR: " + TXT_A + "\n          at: _refresh_ap_display (res://scripts/battle/battle.gd:4680)\n"
    "* test_destroyed_at_zero\nSCRIPT ERROR: Invalid access to property or key 'terrain_theme' on a base object of type 'Nil'.\n"
    "          at: _rebuild_cover_objects (res://scripts/battle/battle.gd:571)\n"
    "res://tests/test_uid_hygiene.gd\n* test_no_orphaned_uid_files\nERROR: Can't free a RefCounted object.\n   at: callp (core/object/object.cpp:766)\n"
    "SCRIPT ERROR: Attempted to free a RefCounted object.\n          at: _check_orphans (res://tests/test_uid_hygiene.gd:21)\n"
    "SCRIPT ERROR: Attempted to free a RefCounted object.\n          at: _check_orphans (res://tests/test_uid_hygiene.gd:21)\n"
    "\n---- Totals ----\nScripts           394\nTests             2992\n  Passing         2992\nAsserts           15740\nTime              5.44s\n\n---- All tests passed! ----\n"
    "WARNING: 214 RIDs of type \"CanvasItem\" were leaked.\n     at: _free_rids (servers/rendering/renderer_canvas_cull.cpp:2485)\n"
)
LOG_ANSI = LOG_BASE.replace("SCRIPT ERROR:", "\x1b[31mSCRIPT ERROR:").replace("\n          at:", "\x1b[0m\n          at:").replace("* test_", "\x1b[0m* test_")
LOG_ZERO = "---  GUT  ---\nGUT version:  9.4.0\n\n---- Totals ----\nScripts           394\nTests             2992\n  Passing         2992\n\n---- All tests passed! ----\n"
LOG_PARSE = ("SCRIPT ERROR: Parse Error: Identifier \"ScreenBg\" not declared in the current scope.\n          at: GDScript::reload (res://scripts/mission/tech_tree.gd:12)\n"
             "SCRIPT ERROR: Parse Error: Function \"assert_str()\" not found in base self.\n          at: GDScript::reload (res://test/battle/test_squad_score.gd:6)\n"
             "ERROR: Failed to load script \"res://test/battle/test_squad_score.gd\" with error \"Parse error\".\n   at: load (modules/gdscript/gdscript.cpp:2936)\n")

SIG_END = " | ".join(("Cannot call method 'create_timer' on a null value.", "_end_battle", "scripts/battle/battle.gd"))
SIG_AP = " | ".join((TXT_A, "_refresh_ap_display", "scripts/battle/battle.gd"))
SIG_HIT = " | ".join((TXT_A, "_refresh_hit_chance_display", "scripts/battle/battle.gd"))
SIG_COVER = " | ".join(("Invalid access to property or key 'terrain_theme' on a base object of type 'Nil'.", "_rebuild_cover_objects", "scripts/battle/battle.gd"))
SIG_UID = " | ".join(("Attempted to free a RefCounted object.", "_check_orphans", "tests/test_uid_hygiene.gd"))
BASE_SIGS = {SIG_END: 1, SIG_HIT: 1, SIG_AP: 2, SIG_COVER: 1, SIG_UID: 2}

NEW_LOG = LOG_BASE + "SCRIPT ERROR: Invalid call. Nonexistent function 'frobnicate' in base 'Nil'.\n          at: _on_new_thing (res://scripts/units/thing.gd:33)\n"
SHIFTED_LOG = LOG_BASE.replace(":4680)", ":4701)").replace(":4712)", ":4733)").replace(":21)", ":30)")

# ---------------------------------------------------------------- parser unit checks (in-process)
c = R.signature_counts(LOG_BASE)
ok("parser: real log excerpt -> 5 signatures with the right counts (ERROR:/WARNING: lines ignored, repeats counted)", c == BASE_SIGS, c)
ok("parser: two-line SCRIPT ERROR/at pairs give (func, file, line)",
   [x[2:] for x in R.parse_log(LOG_BASE)][:2] == [("_end_battle", "scripts/battle/battle.gd", 4554), ("_refresh_hit_chance_display", "scripts/battle/battle.gd", 4712)], R.parse_log(LOG_BASE)[:2])
ok("parser: ANSI-coloured log gives the same signatures", R.signature_counts(LOG_ANSI) == BASE_SIGS, R.signature_counts(LOG_ANSI))
ok("parser: zero-error log -> no signatures", R.signature_counts(LOG_ZERO) == {})
cp = R.signature_counts(LOG_PARSE)
ok("parser: parse-error log -> 2 signatures (GDScript::reload, per file)", len(cp) == 2 and all("GDScript::reload" in s for s in cp), cp)
ok("parser: SCRIPT ERROR with no `at:` line -> func/file '?'", list(R.signature_counts("SCRIPT ERROR: lone message\nnext line\n")) == ["lone message | ? | ?"])
ok("signature ignores line numbers", R.signature_counts(SHIFTED_LOG) == BASE_SIGS, R.signature_counts(SHIFTED_LOG))
ok("signature normalises hex addresses and object ids",
   R.signature_counts("SCRIPT ERROR: bad base 0x7f12ab (Foo) <Node2D#12345>\n          at: f (res://a.gd:1)\n") == R.signature_counts("SCRIPT ERROR: bad base 0xdeadbeef (Foo) <Node2D#999>\n          at: f (res://a.gd:7)\n"))
ok("signature: different message / function / file are different signatures",
   len({k for lg in ("SCRIPT ERROR: m\n          at: f (res://a.gd:1)\n", "SCRIPT ERROR: m2\n          at: f (res://a.gd:1)\n", "SCRIPT ERROR: m\n          at: g (res://a.gd:1)\n",
                     "SCRIPT ERROR: m\n          at: f (res://b.gd:1)\n") for k in R.signature_counts(lg)}) == 4)
new, fixed = R.compare({"a": 1, "b": 3, "c": 1}, {"a": 9, "d": 1})
ok("compare: new = current - baseline, fixed = baseline - current, counts do not matter", new == ["b", "c"] and fixed == ["d"], (new, fixed))

# ---------------------------------------------------------------- CLI battery
SHIM = '''#!%s
import os, sys, time
a = sys.argv[1:]
if os.environ.get("SHIM_LOG"):
    open(os.environ["SHIM_LOG"], "a").write(" ".join(a) + "\\n")
if "--import" in a:
    sys.exit(0)
if os.environ.get("SHIM_SLEEP"):
    time.sleep(float(os.environ["SHIM_SLEEP"]))
sys.stdout.write(open(os.environ["SHIM_OUT"]).read())
sys.exit(0)
''' % sys.executable


def rt(path):
    try:
        return open(path).read()
    except OSError:
        return ""


def rb(path):
    try:
        return open(path, "rb").read()
    except OSError:
        return None


def jl(r):
    """Last stdout line as JSON; {} when a (mutated) tool printed something else."""
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {}


def tree_state(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [x for x in dns if x != ".git"]
        for fn in fns:
            p = os.path.join(dp, fn)
            out[os.path.relpath(p, root)] = open(p, "rb").read()
    return out


def battery(tool, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)

    d = os.path.realpath(tempfile.mkdtemp(prefix="gutr-"))
    os.makedirs(os.path.join(d, "state"))
    shim = os.path.join(d, "godot-shim")
    open(shim, "w").write(SHIM)
    os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC)
    origin = os.path.join(d, "origin.git")
    sh("git", "init", "-q", "--bare", origin)
    clone = os.path.join(d, "repos", "xlite")
    os.makedirs(os.path.dirname(clone))
    sh("git", "clone", "-q", origin, clone)
    os.makedirs(os.path.join(clone, "tests"))
    open(os.path.join(clone, "project.godot"), "w").write("config_version=5\n")
    open(os.path.join(clone, "tests/test_x.gd"), "w").write("extends GutTest\n")
    sh(*GIT, "checkout", "-q", "-b", "overnight/feature", cwd=clone)
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "init", cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)
    out_f = os.path.join(d, "gut.out")
    log = os.path.join(d, "shim.log")
    state = os.path.join(d, "state")
    base_p = os.path.join(state, "gut_script_errors_baseline.json")
    alerts_p = os.path.join(state, "alerts.log")

    def env(**kw):
        e = dict(os.environ, OVN_DIR=d, OVN_GODOT_BIN=shim, SHIM_OUT=out_f, SHIM_LOG=log, HOME=d)
        for k in ("OVN_GUT_RATCHET", "SHIM_SLEEP", "OVN_GUT_TIMEOUT"):
            e.pop(k, None)
        e.update({k: str(v) for k, v in kw.items()})
        return e

    def run(*a, **kw):
        return sh(sys.executable, tool, *a, env=env(**kw))

    def alerts():
        return [l for l in open(alerts_p).read().splitlines()] if os.path.exists(alerts_p) else []

    def put(log_text):
        open(out_f, "w").write(log_text)

    before = tree_state(clone)
    put(LOG_BASE)
    r = run("run", clone)
    chk("run without a baseline: exit 0, lists the signatures, says to review + --update-baseline", r.returncode == 0 and "--update-baseline" in r.stdout and SIG_AP in r.stdout, r.stdout)
    chk("run without a baseline: the baseline file is NOT created automatically", not os.path.exists(base_p))
    chk("run without a baseline: no alert lines", alerts() == [])
    r = run("run", clone, "--update-baseline")
    bl = json.load(open(base_p)) if os.path.exists(base_p) else {}
    chk("--update-baseline writes the baseline (5 signatures with counts) under the repo name", bl.get("xlite", {}).get("signatures") == BASE_SIGS, bl)
    b_bytes = rb(base_p)
    r = run("run", clone, "--json")
    j = jl(r)
    chk("same log: NEW 0, fixed 0, no alert", j.get("new") == [] and j.get("fixed") == [] and alerts() == [], (j, alerts()))
    put(SHIFTED_LOG)
    r = run("run", clone, "--json")
    j = jl(r)
    chk("line numbers moved: still no NEW signature", j.get("new") == [] and alerts() == [], (j, alerts()))
    put(LOG_ANSI)
    r = run("run", clone, "--json")
    j = jl(r)
    chk("ANSI-coloured engine log: still no NEW signature", j.get("new") == [] and j.get("errors") == 7, j)
    put(NEW_LOG)
    r = run("run", clone, "--json")
    j = jl(r)
    new_sig = "Invalid call. Nonexistent function 'frobnicate' in base 'Nil'. | _on_new_thing | scripts/units/thing.gd"
    chk("a NEW signature is detected (and only it), exit 0 in shadow mode", j.get("new") == [new_sig] and r.returncode == 0, (j, r.returncode))
    al = alerts()
    chk("exactly one `warn | gut-script-error | <sig>` line", len(al) == 1 and re.match(r"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] warn \| gut-script-error \| " + re.escape(new_sig) + "$", al[0]) is not None, al)
    run("run", clone)
    chk("same new signature again the same day: deduped (still one line)", len(alerts()) == 1, alerts())
    put(NEW_LOG.replace("_on_new_thing", "_on_other_thing"))
    run("run", clone)
    chk("a second, different new signature adds its own line", len(alerts()) == 2, alerts())
    chk("the baseline file was never modified by plain runs", rb(base_p) == b_bytes)
    put(LOG_BASE.replace("SCRIPT ERROR: Attempted to free a RefCounted object.\n          at: _check_orphans (res://tests/test_uid_hygiene.gd:21)\n", ""))
    r = run("run", clone, "--json")
    j = jl(r)
    chk("a signature that disappeared is reported as fixed (not alerted)", j.get("fixed") == [SIG_UID] and j.get("new") == [], j)
    chk("the live clone's tree is byte-identical after all those runs, and no worktree was added", tree_state(clone) == before and sh("git", "worktree", "list", cwd=clone).stdout.count("\n") == 1)
    chk("the shim was run in a scratch dir, never in the clone", all((d + "/repos") not in l for l in rt(log).splitlines()))

    # modes
    put(NEW_LOG.replace("_on_new_thing", "_on_third_thing"))
    r = run("run", clone, OVN_GUT_RATCHET="enforce")
    chk("enforce (the later flip): a NEW signature exits 1", r.returncode == 1, (r.returncode, r.stdout))
    r = run("run", clone, OVN_GUT_RATCHET="shadow")
    chk("shadow: the same state exits 0", r.returncode == 0, (r.returncode, r.stdout))
    open(log, "w").close()
    r = run("run", clone, OVN_GUT_RATCHET="off")
    chk("OVN_GUT_RATCHET=off: no-op, godot never run", r.returncode == 0 and "off" in r.stdout and rt(log) == "", (r.stdout, rt(log)))
    r = sh(sys.executable, tool, "run", os.path.join(d, "no-such-repo"), env=env())
    chk("internal error (bad repo dir): shadow still exits 0", r.returncode == 0 and "internal error" in r.stdout, (r.returncode, r.stdout, r.stderr))
    chk("godot missing: shadow never raises (exit 0 under the default mode)", run("run", clone, OVN_GODOT_BIN="/nonexistent/godot").returncode == 0)
    put("Godot Engine v4.3\nsome crash text with no GUT summary\n")
    r = run("run", clone, "--json")
    j = jl(r)
    chk("a run that never reached GUT's summary is an error: nothing compared, nothing 'fixed', baseline untouched",
        "did not complete" in j.get("error", "") and j.get("fixed", []) == [] and rb(base_p) == b_bytes, j)
    put(NEW_LOG.replace("_on_new_thing", "_on_third_thing"))
    r = run("run", clone, SHIM_SLEEP=5, OVN_GUT_TIMEOUT=1)
    chk("GUT timeout: reported, exit 0, baseline untouched", r.returncode == 0 and "timed out" in r.stdout and rb(base_p) == b_bytes, r.stdout)
    r = sh(sys.executable, tool, "parse", out_f, env=env())
    chk("parse subcommand prints signatures of a log file", SIG_AP in r.stdout and r.returncode == 0, r.stdout)
    shutil.rmtree(d, ignore_errors=True)
    return bad


bad = battery(TOOL, "real")
ok("real tool passes the whole battery (%d failed assertion(s))" % bad, bad == 0)
if os.environ.get("RATCHET_TEST_REAL_ONLY"):
    print("gut_error_ratchet (real tool only): %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)

src = open(TOOL).read()
MUTANTS = [
    ("line number kept in the signature", 'out.append((" | ".join((msg, func, fil)), msg, func, fil, ln))', 'out.append((" | ".join((msg, func, fil, str(ln))), msg, func, fil, ln))'),
    ("ANSI not stripped", 'lines = ANSI.sub("", text).replace("\\r", "").split("\\n")', 'lines = text.replace("\\r", "").split("\\n")'),
    ("baseline created automatically", "if update_baseline:", "if update_baseline or base is None:"),
    ("alert dedupe removed", "if seen.get(sig) == today:", "if False:"),
    ("alerts never written", "alerted = [s for s in new if alert(s, sd)]", "alerted = []"),
    ("fixed detection removed", "return sorted(set(current) - set(baseline)), sorted(set(baseline) - set(current))", "return sorted(set(current) - set(baseline)), []"),
    ("shadow mode exits non-zero", 'return 1 if (mode == "enforce" and new) else 0', "return 1 if new else 0"),
    ("kill switch removed", 'if os.environ.get("OVN_GUT_RATCHET", "shadow") == "off":', "if False:"),
    ("internal errors exit non-zero", 'return 1 if os.environ.get("OVN_GUT_RATCHET", "shadow") == "enforce" else 0', "return 1"),
    ("empty run compared against the baseline", 'if not re.search(r"^\\s*Tests\\s+\\d+", ANSI.sub("", out), re.M):', "if False:"),
    ("enforce never fails", 'return 1 if (mode == "enforce" and new) else 0', "return 0"),
    ("live clone used instead of an archive", 'p1 = subprocess.Popen(["git", "-C", repo_dir, "archive", ref], stdout=subprocess.PIPE)\n    subprocess.run(["tar", "-x", "-C", dest], stdin=p1.stdout, check=True)',
     'p1 = subprocess.Popen(["git", "-C", repo_dir, "worktree", "add", "-f", "--detach", dest + "/wt", ref], stdout=subprocess.PIPE)\n    subprocess.run(["true"], stdin=p1.stdout, check=True)'),
]
tmpd = tempfile.mkdtemp(prefix="gutr-mutants-")
jobs = []
for i, (name, old, new) in enumerate(MUTANTS):
    if src.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src.count(old))
        continue
    mp = os.path.join(tmpd, "mut%d.py" % i)
    open(mp, "w").write(src.replace(old, new))
    jobs.append((name, mp))
with ThreadPoolExecutor(max_workers=int(os.environ.get("RATCHET_TEST_JOBS", "6"))) as ex:
    results = list(ex.map(lambda j: battery(j[1], "mutant"), jobs))
for (name, _), mb in zip(jobs, results):
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, mb), mb > 0)
shutil.rmtree(tmpd, ignore_errors=True)

print("gut_error_ratchet: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
