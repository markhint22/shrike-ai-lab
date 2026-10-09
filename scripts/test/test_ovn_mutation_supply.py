#!/usr/bin/env python3
"""scripts/ovn_mutation_supply.py: mutation-survivor supply for GDScript (2026-10-09).

Default mode runs anywhere: a SHIM `godot` (python) decides GUT pass/fail from file content - test files carry `#SHIM_NEED <src>::<text>` lines (the
stand-in for an assertion: it fails unless the source still contains <text>), shim_rules.json can make a source "fail to parse" or "hang" for chosen text.
Covers: the mutant generator (operators at code positions only; comments/strings/->/shifts/unary/exponent skipped; addons, tests, battle.gd, banned paths
skipped), classify_gut on text cut from REAL GUT 9.4 logs, verify() (surviving mutant => 1, killed by assertion => 0, parse-error mutant => 1 (not a
kill), real-code test failing => 1, stale line => 1, test reading the source => 1, timeout => 1, live clone never modified), scan (survivors file, cache hit,
cap, baseline-unclean skip, ref archive not working tree), collect (survivors only, never runs a mutant, single physical line, no redirect characters, staleness)
and an end-to-end round trip through the REAL ovn_spec_check.sh. The same battery then runs against MUTATED copies of the tool: each mutant must fail it.

`--live` (box only: needs ~/godot/godot4 and a repos/xlite clone): git archive of repos/xlite HEAD into a scratch dir under $HOME; scan with the real engine,
a known-weak synthetic test must verify RED and the strengthened one GREEN, and a real survivor must verify RED."""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOL = os.path.join(ROOT, "scripts", "ovn_mutation_supply.py")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_mutation_supply as M  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def sh(*a, cwd=None, env=None, inp=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env, input=inp)


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]

# ---------------------------------------------------------------- real GUT 9.4.0 output (captured on the box, 2026-10-09)
GUT_PASS = ("---  GUT  ---\n\x1b[1m[INFO]:  \x1b[0musing [/home/x/.local/share/godot/app_userdata/XLite] for temporary output.\nGodot version:  4.3.0\nGUT version:  9.4.0\n\x1b[4m\n\n"
            "res://tests/test_ability_cost.gd\n\x1b[0m* test_can_afford_exact_boundary\n* test_can_afford_zero_cost\n\x1b[1m10/10 passed.\n\x1b[0m\n\n\n"
            "\x1b[33m==============================================\n\x1b[0m\x1b[33m= Run Summary\n\x1b[0m\n---- Totals ----\nScripts           1\nTests             10\n"
            "  Passing         10\nAsserts           11\nTime              0.004s\n\n\n\x1b[32m---- All tests passed! ----\n\x1b[0m\n")
GUT_FAIL = ("---  GUT  ---\nGUT version:  9.4.0\n\x1b[4m\n\nres://tests/test_ability_cost.gd\n\x1b[0m* test_can_afford_exact_boundary\n\x1b[31m    [Failed]:  \x1b[0mShould afford when AP equals cost\n"
            "      at line -1\n* test_can_afford_insufficient_ap\n\x1b[1m8/10 passed.\n\x1b[0m\n\n\n---- Totals ----\nScripts           1\nTests             10\n  Passing         8\n"
            "  Failing         2\nAsserts           11\nTime              0.019s\n\n\n\x1b[31m---- 2 failing tests ----\n\x1b[0m\n")
GUT_PARSE = ("SCRIPT ERROR: Parse Error: Function \"assert_str()\" not found in base self.\n          at: GDScript::reload (res://test/battle/test_squad_score.gd:6)\n"
             "ERROR: Failed to load script \"res://test/battle/test_squad_score.gd\" with error \"Parse error\".\n   at: load (modules/gdscript/gdscript.cpp:2936)\n"
             "---- Totals ----\nScripts           0\nTests             0\nTime              0.001s\n")
GUT_PARSE_AND_FAILED = GUT_FAIL + "SCRIPT ERROR: Parse Error: Expected expression after \"+\" operator.\n          at: GDScript::reload (res://scripts/units/x.gd:8)\n"
GUT_NO_TESTS = "---  GUT  ---\nGUT version:  9.4.0\n---- Totals ----\nScripts           1\nTests             0\nTime              0.001s\n"


# ---------------------------------------------------------------- shim godot
SHIM = r'''#!%(py)s
import json, os, re, sys, time
args = sys.argv[1:]
log = os.environ.get("SHIM_LOG")
if log:
    open(log, "a").write("%%s | %%s\n" %% (os.getcwd(), " ".join(args)))
if "--import" in args:
    os.makedirs(".godot", exist_ok=True)
    open(".godot/global_script_class_cache.cfg", "w").write("x")
    sys.exit(0)
t = [a for a in args if a.startswith("-gtest=")]
if not t:
    sys.exit(0)
test = t[0][len("-gtest=res://"):]
if not os.path.exists(test):
    print("Tests             0")
    sys.exit(0)
rules = {}
if os.path.exists("shim_rules.json"):
    rules = json.load(open("shim_rules.json"))
srcs = {}
for dp, dns, fns in os.walk("scripts"):
    for fn in fns:
        if fn.endswith(".gd"):
            p = os.path.join(dp, fn)
            srcs[p] = open(p).read()
for p, txt in srcs.items():
    for pat in rules.get("timeout", []):
        if pat in txt:
            time.sleep(3600)
for p, txt in srcs.items():
    for pat in rules.get("parse_error", []):
        if pat in txt:
            print("\x1b[31m    [Failed]:  \x1b[0mcould not run")
            print("SCRIPT ERROR: Parse Error: Expected expression after operator.")
            print("          at: GDScript::reload (res://%%s:8)" %% p)
            print("---- Totals ----\nScripts           1\nTests             3\n  Passing         0\n  Failing         3")
            sys.exit(1)
ttxt = open(test).read()
fails = [m for m in re.findall(r"#SHIM_NEED (\S+)::(.*)", ttxt) if m[1].strip() not in srcs.get(m[0], "")]
n = max(1, len(re.findall(r"func test_", ttxt)))
print("---  GUT  ---\nGUT version:  9.4.0\n\nres://%%s" %% test)
for f in fails:
    print("\x1b[31m    [Failed]:  \x1b[0mexpected %%s in %%s\n      at line -1" %% (f[1].strip(), f[0]))
print("---- Totals ----\nScripts           1\nTests             %%d\n  Passing         %%d" %% (n, n - len(fails)))
if fails:
    print("  Failing         %%d" %% len(fails))
print("Asserts           %%d" %% n)
sys.exit(1 if fails else 0)
''' % {"py": sys.executable}

SRC_COST = ("class_name AbilityCost\n\n\nstatic func can_afford(action_points: int, cost: int) -> bool:\n\treturn action_points >= cost\n\n\n"
            "static func remaining_ap(action_points: int, cost: int) -> int:\n\tcost = maxi(cost, 0)\n\tvar result: int = action_points - cost\n\tif result < 0:\n\t\treturn 0\n\treturn result\n")
TEST_COST = ("extends GutTest\n\nfunc test_can_afford():\n\tassert_true(AbilityCost.can_afford(3, 3))\n#SHIM_NEED scripts/units/ability_cost.gd::action_points >= cost\n"
             "func test_clamped():\n\tassert_eq(AbilityCost.remaining_ap(1, 5), 0)\n#SHIM_NEED scripts/units/ability_cost.gd::if result < 0:\n")
KILLER = "#SHIM_NEED scripts/units/ability_cost.gd::action_points - cost\n"
FILES = {
    "project.godot": 'config_version=5\n[application]\nconfig/name="Fx"\n',
    ".gitignore": ".godot/\n",
    "addons/gut/gut_cmdln.gd": "extends SceneTree\n",
    "shim_rules.json": json.dumps({"timeout": ["return a + b # slowmark"], "parse_error": ["return a + c"]}),
    "scripts/units/ability_cost.gd": SRC_COST,
    "tests/test_ability_cost.gd": TEST_COST,
    "scripts/units/dmg.gd": "class_name Dmg\nstatic func dmg(a, b):\n\treturn a - b\n",
    "tests/test_dmg.gd": "extends GutTest\nfunc test_dmg():\n\tassert_eq(Dmg.dmg(3, 0), 3)\n",
    "scripts/units/cmp.gd": "class_name Cmp\nstatic func ge(a, b):\n\treturn a >= b\n",
    "tests/test_cmp.gd": "extends GutTest\nfunc test_ge():\n\tassert_true(Cmp.ge(3, 1))\n",
    "scripts/units/untested.gd": "class_name Untested\nstatic func f(a, b):\n\treturn a - b\n",
    "scripts/units/dirty.gd": "class_name Dirty\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_dirty.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Dirty.f(1, 1), 0)\n#SHIM_NEED scripts/units/dirty.gd::text that is not there\n",
    "scripts/units/slow.gd": "class_name Slow\nstatic func f(a, b):\n\treturn a - b # slowmark\n",
    "tests/test_slow.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Slow.f(1, 1), 0)\n",
    "scripts/units/pe.gd": "class_name Pe\nstatic func f(a, c):\n\treturn a - c\n",
    "tests/test_pe.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Pe.f(1, 1), 0)\n",
    "scripts/battle/battle.gd": "class_name Battle\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_battle.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Battle.f(1, 1), 0)\n",
    "scripts/units/banned_one.gd": "class_name BannedOne\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_banned_one.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(BannedOne.f(1, 1), 0)\n",
    # a sibling test (not the paired tests/test_xk.gd) already kills xk's mutant: it is not a survivor
    "scripts/units/xk.gd": "class_name Xk\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_xk.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Xk.f(3, 0), 3)\n",
    "tests/test_xk_extra.gd": "extends GutTest\nfunc test_f2():\n\tassert_eq(Xk.f(5, 3), 2)\n#SHIM_NEED scripts/units/xk.gd::return a - b\n",
    # a sibling that is RED on the real code proves nothing: xr's mutant stays a survivor
    "scripts/units/xr.gd": "class_name Xr\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_xr.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(Xr.f(3, 0), 3)\n",
    "tests/test_xr_bad.gd": "extends GutTest\nfunc test_f2():\n\tassert_eq(Xr.f(5, 3), 2)\n#SHIM_NEED scripts/units/xr.gd::text the real code lacks\n",
    # the hard-ban list holds `tests/test_mission_select` (an unanchored regex in run_overnight.sh): the TEST file of this pair is banned although its source is not
    "scripts/mission/mission_select_foo.gd": "class_name MissionSelectFoo\nstatic func f(a, b):\n\treturn a - b\n",
    "tests/test_mission_select_foo.gd": "extends GutTest\nfunc test_f():\n\tassert_eq(MissionSelectFoo.f(3, 0), 3)\n",
    ".queue-hard-banned-files": "# banned\nscripts/units/banned_one.gd\ntests/test_mission_select\n",
}


def make_ovn(extra_files=None):
    """An OVN_DIR with repos/xlite (a clone whose origin/overnight/feature holds FILES), state/, scripts/ (the spec-check libs)."""
    d = tempfile.mkdtemp(prefix="mut-ovn-")
    d = os.path.realpath(d)
    os.makedirs(os.path.join(d, "scripts"))
    os.makedirs(os.path.join(d, "state"))
    for f in ("ovn_spec_check.sh", "lib_verify_clause.sh", "lib_gut_xml.sh"):
        shutil.copy(os.path.join(ROOT, "scripts", f), os.path.join(d, "scripts", f))
    shutil.copy(TOOL, os.path.join(d, "scripts", "ovn_mutation_supply.py"))
    shim = os.path.join(d, "godot-shim")
    open(shim, "w").write(SHIM)
    os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC)
    origin = os.path.join(d, "origin.git")
    sh("git", "init", "-q", "--bare", origin)
    clone = os.path.join(d, "repos", "xlite")
    os.makedirs(os.path.dirname(clone))
    sh("git", "clone", "-q", origin, clone)
    files = dict(FILES)
    files.update(extra_files or {})
    for rp, body in files.items():
        fp = os.path.join(clone, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    sh(*GIT, "checkout", "-q", "-b", "overnight/feature", cwd=clone)
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "init", cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)
    return d, clone, shim


def env_for(d, shim, **kw):
    e = dict(os.environ, OVN_DIR=d, OVN_GODOT_BIN=shim, HOME=d, OVN_MUT_TIMEOUT="2")
    for k in ("OVN_SUPPLY_MUTATION", "OVN_MUTATION_SCAN", "OVN_MUT_REF", "OVN_MUT_MAX", "SHIM_LOG"):
        e.pop(k, None)
    e.update({k: str(v) for k, v in kw.items()})
    return e


def tree_state(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [x for x in dns if x != ".git"]
        for fn in fns:
            p = os.path.join(dp, fn)
            out[os.path.relpath(p, root)] = open(p, "rb").read()
    return out


def commit_push(clone, msg="change"):
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", msg, cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)


# ---------------------------------------------------------------- the battery (parameterised on the tool script)
def battery(tool, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)

    d, clone, shim = make_ovn()
    shutil.copy(tool, os.path.join(d, "scripts", "ovn_mutation_supply.py"))
    tool_in = os.path.join(d, "scripts", "ovn_mutation_supply.py")
    env = env_for(d, shim)

    def run(*a, **kw):
        return sh(sys.executable, tool_in, *a, env=kw.get("env", env), cwd=kw.get("cwd"))

    def vrun(test, src, line, o, m, occ=None, repo=None, e=None):
        a = ["verify", repo or clone, test, src, str(line), o, m] + ([str(occ)] if occ else [])
        r = run(*a, env=e or env)
        return r.returncode, r.stdout + r.stderr

    # ---- verify: the survivor is RED, the killing test turns it GREEN
    before = tree_state(clone)
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 10, "-", "+")
    chk("verify: surviving mutant (line 10 `-` -> `+`) => exit 1 'survived'", rc == 1 and "survived" in out, (rc, out))
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 10, "minus", "plus")
    chk("verify: token NAMES are accepted (minus plus)", rc == 1 and "survived" in out, (rc, out))
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 5, "ge", "gt")
    chk("verify: an already-killed mutant (>= -> >) => exit 0 'killed' (test + source untouched)", rc == 0 and "killed" in out, (rc, out))
    chk("verify never modified the repo it was pointed at (no mutant in the live clone)", tree_state(clone) == before)
    with open(os.path.join(clone, "tests/test_ability_cost.gd"), "a") as f:
        f.write(KILLER)
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 10, "minus", "plus")
    chk("verify: after a killing test exists => exit 0", rc == 0 and "killed" in out, (rc, out))
    chk("verify: still no mutant left in the clone's source", read(os.path.join(clone, "scripts/units/ability_cost.gd")) == SRC_COST)
    # real-code test failing: a NEED on text the real source does not contain
    with open(os.path.join(clone, "tests/test_ability_cost.gd"), "a") as f:
        f.write("#SHIM_NEED scripts/units/ability_cost.gd::text the real code lacks\n")
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 10, "minus", "plus")
    chk("verify: test failing on the REAL code => exit 1 (even though it also 'kills' the mutant)", rc == 1 and "real code" in out, (rc, out))
    sh("git", "checkout", "--", "tests/test_ability_cost.gd", cwd=clone)
    # parse-error mutant is NOT a kill: pe.gd `a - c` -> `a + c` is a shim 'parse error'
    with open(os.path.join(clone, "tests/test_pe.gd"), "a") as f:
        f.write("#SHIM_NEED scripts/units/pe.gd::return a - c\n")
    rc, out = vrun("tests/test_pe.gd", "scripts/units/pe.gd", 3, "-", "+")
    chk("verify: a mutant that BREAKS PARSING (SCRIPT ERROR + failures) is not a kill => exit 1", rc == 1 and "not a kill" in out, (rc, out))
    # timeout: slow.gd mutant hangs
    with open(os.path.join(clone, "tests/test_slow.gd"), "a") as f:
        f.write("#SHIM_NEED scripts/units/slow.gd::return a - b\n")
    rc, out = vrun("tests/test_slow.gd", "scripts/units/slow.gd", 3, "-", "+")
    chk("verify: a mutant that hangs (timeout) is not a kill => exit 1", rc == 1 and "not a kill" in out and "timeout" in out, (rc, out))
    # test missing
    rc, out = vrun("tests/test_nope.gd", "scripts/units/ability_cost.gd", 10, "-", "+")
    chk("verify: test file missing => exit 1, message does not look like a crash (spec check would call that bad-spec)",
        rc == 1 and not re.search(r"Traceback|No such file|FileNotFoundError", out), (rc, out))
    # stale line / token
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 6, "-", "+")
    chk("verify: no such code site on that line => exit 1 'stale'", rc == 1 and "stale" in out, (rc, out))
    rc, out = vrun("tests/test_ability_cost.gd", "scripts/units/ability_cost.gd", 10, "-", "-")
    chk("verify: nonsense mutation => exit 1", rc == 1, (rc, out))
    # a test that reads the source text is not a kill
    with open(os.path.join(clone, "tests/test_dmg.gd"), "a") as f:
        f.write("func test_cheat():\n\tvar s = get_script().source_code\n#SHIM_NEED scripts/units/dmg.gd::return a - b\n")
    rc, out = vrun("tests/test_dmg.gd", "scripts/units/dmg.gd", 3, "-", "+")
    chk("verify: a test that reads source_code => exit 1 (not behaviour)", rc == 1 and "source" in out, (rc, out))

    # ---- scan (ref archive, not the working tree)
    log = os.path.join(d, "shim.log")
    e2 = env_for(d, shim, SHIM_LOG=log)
    # a LOCAL-ONLY commit (never pushed): the scan must use origin/overnight/feature, not HEAD or the working tree
    with open(os.path.join(clone, "scripts/units/dmg.gd"), "a") as f:
        f.write("static func extra(a, b):\n\treturn a - b\n")
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "local only", cwd=clone)
    sh("git", "checkout", "--", "tests/test_dmg.gd", "tests/test_pe.gd", "tests/test_slow.gd", cwd=clone)
    r = run("scan", clone, "--max-mutants", "100", "--json", env=e2)
    try:
        summ = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        summ = {}
    chk("scan: prints a JSON summary", bool(summ) and r.returncode == 0, (r.stdout, r.stderr))
    surv_path = os.path.join(d, "state", "mutation_survivors_xlite.json")
    cache_path = os.path.join(d, "state", "mutation_scan_xlite.json")
    sv = json.load(open(surv_path)) if os.path.exists(surv_path) else {"survivors": []}
    got = {(s["file"], s["line"], s["orig"], s["mut"]) for s in sv["survivors"]}
    want = {("scripts/units/ability_cost.gd", 10, "-", "+"), ("scripts/units/dmg.gd", 3, "-", "+"), ("scripts/units/cmp.gd", 3, ">=", ">"), ("scripts/units/xr.gd", 3, "-", "+")}
    chk("scan: survivors are exactly the weakly-tested sites (ability_cost -, dmg -, cmp >=, xr - whose sibling is red on real code); the unpushed commit's extra() was not scanned; "
        "xk (killed by a sibling test) and mission_select_foo (banned test file) are absent", got == want, got)
    sh("git", "reset", "-q", "--hard", "origin/overnight/feature", cwd=clone)
    cache_txt = json.dumps(json.load(open(cache_path))) if os.path.exists(cache_path) else ""
    chk("scan: untested.gd, battle.gd, banned_one.gd, addons never mutated", cache_txt and not any(x in cache_txt for x in ("untested.gd", "battle.gd", "banned_one", "addons", "mission_select")), "")
    ent = json.load(open(cache_path))["files"] if os.path.exists(cache_path) else {}
    chk("scan: dirty.gd baseline not green => skipped, no mutants recorded", ent.get("scripts/units/dirty.gd", {}).get("baseline") == "unclean" and not ent["scripts/units/dirty.gd"]["mutants"], ent.get("scripts/units/dirty.gd"))
    xk = ent.get("scripts/units/xk.gd", {}).get("mutants", {})
    chk("scan: xk's mutant is recorded 'killed_elsewhere' by the sibling tests/test_xk_extra.gd (NOT a survivor)",
        [(m["status"], m.get("killed_by")) for m in xk.values()] == [("killed_elsewhere", "tests/test_xk_extra.gd")], xk)
    chk("scan: xr's sibling test is red on the real code, so it is not counted as a kill (xr stays a survivor)",
        [m["status"] for m in ent.get("scripts/units/xr.gd", {}).get("mutants", {}).values()] == ["survived"], ent.get("scripts/units/xr.gd"))
    chk("scan: summary counts the sibling kill", summ.get("killed_elsewhere") == 1, summ)
    chk("scan: the survivors file carries others_sha for every survivor", all("others_sha" in s_ for s_ in sv["survivors"]), sv["survivors"])
    st_pe = [m["status"] for m in ent.get("scripts/units/pe.gd", {}).get("mutants", {}).values()]
    chk("scan: parse-error mutant recorded as 'error' (neither killed nor survived)", st_pe == ["error"], st_pe)
    st_sl = [m["status"] for m in ent.get("scripts/units/slow.gd", {}).get("mutants", {}).values()]
    chk("scan: hanging mutant recorded as 'timeout'", st_sl == ["timeout"], st_sl)
    n_runs = sum(1 for l in read(log).splitlines() if "-gtest" in l)
    run("scan", clone, "--max-mutants", "100", "--json", env=e2)
    n_runs2 = sum(1 for l in read(log).splitlines() if "-gtest" in l)
    chk("scan: second pass is a CACHE HIT (no GUT run at all)", n_runs > 0 and n_runs2 == n_runs, (n_runs, n_runs2))
    for f_ in (cache_path, surv_path):
        os.remove(f_)
    open(log, "w").close()
    r = run("scan", clone, "--max-mutants", "2", "--json", env=e2)
    summ = json.loads(r.stdout.strip().splitlines()[-1])
    chk("scan: --max-mutants 2 runs at most 2 mutants", summ.get("ran") == 2, summ)
    r = run("scan", clone, env=env_for(d, shim, OVN_MUTATION_SCAN="off"))
    chk("scan: OVN_MUTATION_SCAN=off is a no-op", "off" in r.stdout and r.returncode == 0, r.stdout)
    r = run("scan", clone, "--max-mutants", "100", "--json", env=env_for(d, "/nonexistent/godot"))
    chk("scan: missing godot binary is a clean skip (exit 0)", r.returncode == 0 and "not found" in r.stdout, (r.returncode, r.stdout))
    run("scan", clone, "--max-mutants", "100", "--json", env=e2)

    # ---- collect: survivors file only, never runs a mutant (run in a subprocess: collect reads env at call time, and mutants run in parallel threads)
    ce = dict(os.environ, OVN_DIR=d, OVN_GODOT_BIN="/nonexistent/godot", OVN_SUPPLY_MUTATION="1")
    specs = collect_via(tool_in, clone, ce)
    off_specs = collect_via(tool_in, clone, dict(ce, OVN_SUPPLY_MUTATION="0"))
    chk("collect: off unless OVN_SUPPLY_MUTATION=1", off_specs == [] and len(specs) > 0, (len(specs), off_specs))
    by_file = {s["file"]: s for s in specs}
    chk("collect: one spec per source/test pair (ability_cost, dmg, cmp, xr) with the spec fields (kind, T2, cat test)",
        set(by_file) == {"tests/test_ability_cost.gd", "tests/test_dmg.gd", "tests/test_cmp.gd", "tests/test_xr.gd"}
        and all(s["kind"] == "gd-mutation-survivor" and s["tier"] == "T2" and s["cat"] == "test" for s in specs), set(by_file))
    sp = by_file.get("tests/test_ability_cost.gd", {})
    chk("collect: item text names the test, line, source, original and mutated token",
        "Add a GUT test in tests/test_ability_cost.gd that fails when line 10 of scripts/units/ability_cost.gd (`-`) is mutated to `+`" in sp.get("text", ""), sp.get("text"))
    v = sp.get("verify", "")
    chk("collect: VERIFY is ONE physical line, no backtick, no redirect characters, resolves $OVN_DIR with a $HOME fallback",
        v and "\n" not in v and not re.search(r"[`<>]", v) and "${OVN_DIR:-$HOME/overnight-queue}/scripts/ovn_mutation_supply.py verify . " in v, v)
    cmpv = by_file.get("tests/test_cmp.gd", {}).get("verify", "")
    chk("collect: a `>=` -> `>` survivor is spelled `ge gt` in the VERIFY (no literal angle bracket)", " ge gt" in cmpv and ">" not in cmpv, cmpv)
    with open(os.path.join(clone, "scripts/units/dmg.gd"), "a") as f:
        f.write("# moved\n")
    specs2 = collect_via(tool_in, clone, ce)
    chk("collect: a survivor whose source changed since the scan is dropped (and the others stay)",
        "tests/test_dmg.gd" not in {s["file"] for s in specs2} and "tests/test_cmp.gd" in {s["file"] for s in specs2}, [s["file"] for s in specs2])
    sh("git", "checkout", "--", "scripts/units/dmg.gd", cwd=clone)
    # a survivor whose edit target (the test file) is on the hard-ban list is never emitted (hand-written survivors file with CORRECT shas, so only the ban can drop it)
    sp_ = os.path.join(d, "state", "mutation_survivors_xlite.json")
    saved_sv = read(sp_)
    svj = json.loads(saved_sv)
    msrc, mtst = "scripts/mission/mission_select_foo.gd", "tests/test_mission_select_foo.gd"
    svj["survivors"].append({"file": msrc, "test": mtst, "line": 3, "col": 10, "occ": 1, "orig": "-", "mut": "+", "snippet": "return a - b", "others_sha": M.sha(""),
                             "src_sha": M.sha_file(os.path.join(clone, msrc)), "test_sha": M.sha_file(os.path.join(clone, mtst))})
    open(sp_, "w").write(json.dumps(svj))
    specs_b = collect_via(tool_in, clone, ce)
    chk("collect: a survivor whose TEST file is on .queue-hard-banned-files (tests/test_mission_select) is not emitted", specs_b is not None and mtst not in {s["file"] for s in specs_b}
        and "tests/test_xr.gd" in {s["file"] for s in specs_b}, [s["file"] for s in specs_b or []])
    open(sp_, "w").write(saved_sv)
    # a NEW sibling test that references the source since the scan: the survivor is dropped (that test may already kill it), the others stay
    open(os.path.join(clone, "tests/test_dmg_more.gd"), "w").write("extends GutTest\nfunc test_more():\n\tassert_eq(Dmg.dmg(9, 4), 5)\n")
    specs_c = collect_via(tool_in, clone, ce)
    chk("collect: a sibling test added since the scan drops that survivor only", specs_c is not None and "tests/test_dmg.gd" not in {s["file"] for s in specs_c}
        and "tests/test_cmp.gd" in {s["file"] for s in specs_c}, [s["file"] for s in specs_c or []])
    os.remove(os.path.join(clone, "tests/test_dmg_more.gd"))

    # ---- a changed test invalidates the cache entry for that file only
    open(log, "w").close()
    with open(os.path.join(clone, "tests/test_cmp.gd"), "a") as f:
        f.write("#SHIM_NEED scripts/units/cmp.gd::a >= b\n")
    commit_push(clone, "cmp test")
    run("scan", clone, "--max-mutants", "100", "--json", env=e2)
    sv = json.load(open(surv_path))
    got = {(s["file"], s["line"]) for s in sv["survivors"]}
    chk("scan: after cmp's test was strengthened (pushed) its survivor is gone, the others remain", ("scripts/units/cmp.gd", 3) not in got and ("scripts/units/dmg.gd", 3) in got, got)
    gl = [l for l in read(log).splitlines() if "-gtest" in l]
    chk("scan: only cmp.gd was re-run (cache keyed by src sha + test sha)", gl and all("tests/test_cmp.gd" in l for l in gl), gl[:3])

    # ---- end to end through the REAL ovn_spec_check.sh: red before, passes-before (= green) after a killing test lands on origin
    home = tempfile.mkdtemp(prefix="mut-home-")
    os.symlink(d, os.path.join(home, "overnight-queue"))
    e3 = dict(env_for(d, shim), HOME=home)
    e3.pop("OVN_DIR", None)
    specs = [s for s in collect_via(tool_in, clone, ce) if s["file"] == "tests/test_ability_cost.gd"]
    if specs:
        line = "- [ ] [T2] %s \u2014 %s VERIFY: `%s`. (cat:test; multifile:no; supply:gd-mutation-survivor) [feat:x]" % (specs[0]["file"], specs[0]["text"], specs[0]["verify"])
        lf = os.path.join(d, "item.md")
        open(lf, "w").write(line + "\n")
        r = sh("bash", os.path.join(d, "scripts", "ovn_spec_check.sh"), "xlite", lf, env=e3)
        chk("spec check (real script): survivor item is 'red' before the test is added", re.search(r"^1\tred\b", r.stdout, re.M) is not None, (r.stdout, r.stderr))
        with open(os.path.join(clone, "tests/test_ability_cost.gd"), "a") as f:
            f.write(KILLER)
        commit_push(clone, "killing test")
        r = sh("bash", os.path.join(d, "scripts", "ovn_spec_check.sh"), "xlite", lf, env=e3)
        chk("spec check (real script): after the killing test lands the same VERIFY passes", re.search(r"^1\tpasses-before\b", r.stdout, re.M) is not None, (r.stdout, r.stderr))
    else:
        chk("spec check: a survivor spec for ability_cost exists", False)
    shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(home, ignore_errors=True)
    return bad


COLLECT_PY = ("import sys,json,importlib.util;sp=importlib.util.spec_from_file_location('m',sys.argv[1]);m=importlib.util.module_from_spec(sp);"
              "sp.loader.exec_module(m);print(json.dumps(list(m.collect(sys.argv[2]))))")


def collect_via(tool_in, root, env):
    r = sh(sys.executable, "-c", COLLECT_PY, tool_in, root, env=env)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def read(p):
    try:
        return open(p).read()
    except OSError:
        return ""


# ---------------------------------------------------------------- unit-level checks (no subprocess)
SAMPLE = '''class_name Fx
const E = 1e-5
static func f(a: int, b: int) -> int:
	var x = -a + b  # a - b < c
	var s = "a - b" + 'x < y'
	if a >= b and x != -1:
		return a - b
	elif a < b:
		x += 2
		x -= b
	return (a
		- b) + a * 2 << 1
@export_range(0, 1 - 2)
@export var w = 4 + 1
signal sig(a)
func g():
	print("x" + str(1 - 2))
	return -1 - 2 + 3e-2 - .5 + """multi
- line < """ + r"raw - x"
'''
sites = M.mutation_sites(SAMPLE)
got = [(s["line"], s["orig"], s["mut"], s["occ"]) for s in sites]
ok("generator: operators at code positions only (comments, strings, ->, <<, unary signs, 3e-2, annotation args, print lines skipped)",
   got == [(4, "+", "-", 1), (5, "+", "-", 1), (6, ">=", ">", 1), (6, "!=", "==", 1), (7, "-", "+", 1), (8, "<", "<=", 1), (9, "+=", "-=", 1), (10, "-=", "+=", 1),
           (12, "-", "+", 1), (12, "+", "-", 1), (14, "+", "-", 1), (18, "-", "+", 1), (18, "+", "-", 1), (18, "-", "+", 2), (18, "+", "-", 2), (19, "+", "-", 1)], got)
ok("generator: apply_mutant replaces exactly the chosen site", M.apply_mutant(SAMPLE, 7, "-", "+").split("\n")[6] == "\t\treturn a + b"
   and M.apply_mutant(SAMPLE, 18, "-", "+", 2).split("\n")[17].count("+") == 3, M.apply_mutant(SAMPLE, 18, "-", "+", 2))
ok("generator: apply_mutant on a missing site returns None", M.apply_mutant(SAMPLE, 3, "<", "<=") is None)
ok("generator: result is deterministic", [s for s in M.mutation_sites(SAMPLE)] == sites)

tmp = tempfile.mkdtemp(prefix="mut-elig-")
for rp in ("scripts/a.gd", "scripts/battle/battle.gd", "scripts/battle/other.gd", "scripts/sub/battle.gd", "addons/gut/x.gd", "tests/test_a.gd", "scripts/banned/y.gd", "scripts/keep.gd"):
    os.makedirs(os.path.dirname(os.path.join(tmp, rp)), exist_ok=True)
    open(os.path.join(tmp, rp), "w").write("class_name X\nfunc f(a, b):\n\treturn a - b\n")
open(os.path.join(tmp, ".queue-hard-banned-files"), "w").write("# c\nscripts/banned/\n")
ok("eligible sources skip addons, tests, scripts/battle/battle.gd, any battle.gd and .queue-hard-banned-files paths",
   M.eligible_sources(tmp) == ["scripts/a.gd", "scripts/keep.gd", "scripts/battle/other.gd"], M.eligible_sources(tmp))
open(os.path.join(tmp, "tests/test_keep.gd"), "w").write("extends GutTest\nconst K = preload(\"res://scripts/keep.gd\")\nfunc test_x():\n\tassert_eq(K.f(1,1), 0)\n")
open(os.path.join(tmp, "tests/test_a.gd"), "w").write("extends GutTest\nfunc test_x():\n\tassert_eq(X.f(1,1), 0)\n")
ok("test_for: tests/test_<stem>.gd must exist AND reference the stem or class_name", M.test_for(tmp, "scripts/keep.gd") == "tests/test_keep.gd" and M.test_for(tmp, "scripts/a.gd") == "tests/test_a.gd"
   and M.test_for(tmp, "scripts/battle/other.gd") is None)
shutil.rmtree(tmp, ignore_errors=True)

ok("classify_gut: real all-pass log => pass", M.classify_gut(0, GUT_PASS)[0] == "pass", M.classify_gut(0, GUT_PASS))
ok("classify_gut: real failing log (rc 1) => fail", M.classify_gut(1, GUT_FAIL)[0] == "fail")
ok("classify_gut: failing log with rc 0 (older GUT exits 0 on failures) => still fail", M.classify_gut(0, GUT_FAIL)[0] == "fail")
ok("classify_gut: parse-error log => error (not fail, not pass)", M.classify_gut(0, GUT_PARSE)[0] == "error")
ok("classify_gut: failures PLUS a SCRIPT ERROR => error (a broken mutant is not a kill)", M.classify_gut(1, GUT_PARSE_AND_FAILED)[0] == "error")
ok("classify_gut: zero tests => error", M.classify_gut(0, GUT_NO_TESTS)[0] == "error")
ok("classify_gut: timeout => timeout", M.classify_gut("timeout", "")[0] == "timeout")

# ---------------------------------------------------------------- other_tests: ranking + the cap-aware sha (reviewer round 2: sources with dozens of referencing tests)
tmp = tempfile.mkdtemp(prefix="mut-others-")
def _w(rp, body):
    os.makedirs(os.path.dirname(os.path.join(tmp, rp)), exist_ok=True)
    open(os.path.join(tmp, rp), "w").write(body)
_w("scripts/unit.gd", "class_name Unit\nfunc f(a, b):\n\treturn a - b\n")
_w("tests/test_unit.gd", "extends GutTest\nfunc test_x():\n\tassert_eq(Unit.f(1, 1), 0)\n")
_w("tests/test_unit_more.gd", "extends GutTest\n# unit\n")
_w("tests/b_heavy.gd", "extends GutTest\n# unit unit unit unit unit\n")
_w("tests/c_mid.gd", "extends GutTest\n# unit unit unit\n")
_w("tests/a_misc.gd", "extends GutTest\n# unit\n")
_w("tests/z_low.gd", "extends GutTest\n# unit\n")
_w("tests/unrelated.gd", "extends GutTest\n# nothing to see\n")
_o = M.other_tests(tmp, "scripts/unit.gd", "tests/test_unit.gd", cap=3)
ok("other_tests: name match first, then the MOST referencing tests, capped (test_unit_more, b_heavy, c_mid; not the alphabetically early a_misc)",
   _o[0] == ["tests/test_unit_more.gd", "tests/b_heavy.gd", "tests/c_mid.gd"], _o[0])
_w("tests/z_low.gd", "extends GutTest\n# unit - but edited\n")
_w("tests/a_misc.gd", "extends GutTest\n# unit - also edited\n")
_o2 = M.other_tests(tmp, "scripts/unit.gd", "tests/test_unit.gd", cap=3)
ok("other_tests: the sha covers only the capped candidates - editing tests that rank below the cap leaves it (and the scan cache) untouched", _o2 == _o, (_o, _o2))
_w("tests/c_mid.gd", "extends GutTest\n# unit unit unit - edited\n")
_o3 = M.other_tests(tmp, "scripts/unit.gd", "tests/test_unit.gd", cap=3)
ok("other_tests: editing a candidate that IS run changes the sha", _o3[0] == _o[0] and _o3[1] != _o[1], _o3)
os.environ["OVN_MUT_OTHERS_MAX"] = "5"
_o5 = M.other_tests(tmp, "scripts/unit.gd", "tests/test_unit.gd")
del os.environ["OVN_MUT_OTHERS_MAX"]
ok("other_tests: OVN_MUT_OTHERS_MAX raises the cap (5 candidates, still ranked)", len(_o5[0]) == 5 and _o5[0][:3] == _o[0], _o5[0])
shutil.rmtree(tmp, ignore_errors=True)

# ---------------------------------------------------------------- the battery against the real tool
if "--live" in sys.argv:
    GB = os.path.join(os.path.expanduser("~"), "godot", "godot4")
    XL = os.environ.get("OVN_LIVE_XLITE", os.path.join(os.path.expanduser("~"), "overnight-queue", "repos", "xlite"))
    if not (os.access(GB, os.X_OK) and os.path.isdir(os.path.join(XL, ".git"))):
        print("  SKIP --live: need %s and %s" % (GB, XL))
        sys.exit(0)
    S = tempfile.mkdtemp(prefix="scratch-mutlive-", dir=os.path.expanduser("~"))
    print("  live: scratch=" + S)
    rd = os.path.join(S, "repos", "xlite")
    os.makedirs(rd)
    sh("bash", "-c", "git -C '%s' archive HEAD | tar -x -C '%s'" % (XL, rd))
    sh("git", "init", "-q", cwd=rd)
    sh("git", "add", "-A", cwd=rd)
    sh(*GIT, "commit", "-q", "-m", "snap", cwd=rd)
    os.makedirs(os.path.join(S, "state"))
    env = dict(os.environ, OVN_DIR=S, OVN_GODOT_BIN=GB, OVN_MUT_TIMEOUT="60")
    # a synthetic weak test: `5 - 0` survives `-` -> `+`; the strengthened one kills it
    os.makedirs(os.path.join(rd, "scripts", "mutlive"), exist_ok=True)
    open(os.path.join(rd, "scripts/mutlive/probe.gd"), "w").write("class_name MutLiveProbe\n\nstatic func sub(a: int, b: int) -> int:\n\treturn a - b\n")
    open(os.path.join(rd, "tests/test_probe.gd"), "w").write("extends GutTest\n\nfunc test_sub_zero():\n\tassert_eq(MutLiveProbe.sub(5, 0), 5)\n")
    sh("git", "add", "-A", cwd=rd)
    sh(*GIT, "commit", "-q", "-m", "probe", cwd=rd)
    r = sh(sys.executable, TOOL, "verify", rd, "tests/test_probe.gd", "scripts/mutlive/probe.gd", "4", "minus", "plus", env=env)
    ok("live: weak probe test => verify exits 1 (survived)", r.returncode == 1 and "survived" in r.stdout, r.stdout + r.stderr)
    open(os.path.join(rd, "tests/test_probe.gd"), "w").write("extends GutTest\n\nfunc test_sub():\n\tassert_eq(MutLiveProbe.sub(5, 3), 2)\n")
    r = sh(sys.executable, TOOL, "verify", rd, "tests/test_probe.gd", "scripts/mutlive/probe.gd", "4", "minus", "plus", env=env)
    ok("live: strengthened probe test => verify exits 0 (killed)", r.returncode == 0 and "killed" in r.stdout, r.stdout + r.stderr)
    sh("git", "add", "-A", cwd=rd)
    sh(*GIT, "commit", "-q", "-m", "probe strong", cwd=rd)
    mx = os.environ.get("OVN_LIVE_MAX", "400")
    r = sh(sys.executable, TOOL, "scan", rd, "--max-mutants", mx, "--json", env=env)
    print("  live: " + r.stdout.strip()[-400:])
    sv = json.load(open(os.path.join(S, "state", "mutation_survivors_xlite.json")))
    files = {s["file"] for s in sv["survivors"]}
    ok("live: scan found survivors in >= 10 files (--max-mutants %s): %d files, %d survivors" % (mx, len(files), len(sv["survivors"])), len(files) >= 10)
    if sv["survivors"]:
        s0 = sv["survivors"][0]
        r = sh(sys.executable, TOOL, "verify", rd, s0["test"], s0["file"], str(s0["line"]), M.TOKNAME[s0["orig"]], M.TOKNAME[s0["mut"]], *( [str(s0["occ"])] if s0["occ"] > 1 else []), env=env)
        ok("live: a real survivor (%s:%d `%s`->`%s`) verifies RED (exit 1, survived)" % (s0["file"], s0["line"], s0["orig"], s0["mut"]), r.returncode == 1 and "survived" in r.stdout, r.stdout + r.stderr)
    shutil.rmtree(S, ignore_errors=True)
    print("ovn_mutation_supply (live): %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)

bad = battery(TOOL, "real")
ok("real tool passes the whole battery (%d failed assertion(s))" % bad, bad == 0)
if os.environ.get("MUT_TEST_REAL_ONLY"):   # developer shortcut: skip the (slow) tool-mutation pass
    print("ovn_mutation_supply (real tool only): %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)

src = open(TOOL).read()
MUTANTS = [
    ("parse-error guard removed", '    if bad:\n        return "error", bad.group(0)\n', ""),
    ("survivor counted as kill", 'if st == "fail":\n            return 0,', 'if st in ("fail", "pass"):\n            return 0,'),
    ("real-code check removed", 'if st != "pass":\n            return 1, "the test does not pass on the real code', 'if False:\n            return 1, "the test does not pass on the real code'),
    ("source-reading guard removed", '"source_code" in ttext', "False"),
    ("stale-site guard removed", "if mutated is None:\n        return 1, ", "if False:\n        return 1, "),
    ("mutant written into the live repo", 'with open(os.path.join(work, src_rel), "w", encoding="utf-8") as f:\n            f.write(mutated)', 'with open(os.path.join(repo_dir, src_rel), "w", encoding="utf-8") as f:\n            f.write(mutated)'),
    ("scan cache ignored", 'if mkey(s) not in ent["mutants"]]', "if True]"),
    ("ban check removed", "if not is_banned(rp, root):", "if True:"),
    ("test-path ban removed from test_for", "if list_banned(tp, root):   # the item's edit target", "if False:   # the item's edit target"),
    ("test-path ban removed from collect", "or list_banned(tp, root):   # the edit target", "or False:   # the edit target"),
    ("sibling-test kill check removed", "killer = killed_elsewhere(scratch, src, tp, ent, orig_text, mutated)", "killer = None"),
    ("sibling red-on-real gate removed", 'good = [ot for ot in cands if base.get(ot) == "pass"]', "good = list(cands)"),
    ("collect sibling-sha check removed", 'if other_tests(root, src, tp)[1] != s.get("others_sha", sha("")):', "if False:"),
    ("baseline gate removed", 'ent["baseline"] = "ok" if st_ == "pass" else "unclean"', 'ent["baseline"] = "ok"'),
    ("collect staleness check removed", 'if sha_file(sp) != s["src_sha"] or sha_file(tpp) != s["test_sha"]:', "if False:"),
    ("collect gate removed", 'if os.environ.get("OVN_SUPPLY_MUTATION", "0") != "1":', "if False:"),
    ("literal tokens in the VERIFY", "TOKNAME[s[\"orig\"]], TOKNAME[s[\"mut\"]], occ)", "s[\"orig\"], s[\"mut\"], occ)"),
    ("working tree scanned instead of the ref", 'subprocess.Popen(["git", "-C", repo_dir, "archive", ref]', 'subprocess.Popen(["git", "-C", repo_dir, "archive", "HEAD"]'),
]
tmpd = tempfile.mkdtemp(prefix="mut-mutants-")
jobs = []
for i, (name, old, new) in enumerate(MUTANTS):
    if src.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src.count(old))
        continue
    mp = os.path.join(tmpd, "mut%d.py" % i)
    open(mp, "w").write(src.replace(old, new))
    jobs.append((name, mp))
from concurrent.futures import ThreadPoolExecutor  # noqa: E402
with ThreadPoolExecutor(max_workers=int(os.environ.get("MUT_TEST_JOBS", "6"))) as ex:
    results = list(ex.map(lambda j: battery(j[1], "mutant"), jobs))
for (name, _), mb in zip(jobs, results):
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, mb), mb > 0)
shutil.rmtree(tmpd, ignore_errors=True)

print("ovn_mutation_supply: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
