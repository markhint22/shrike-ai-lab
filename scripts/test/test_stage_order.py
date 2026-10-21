#!/usr/bin/env python3
"""D3-step-ordering: unit + replay + mutant tests for scripts/ovn_stage_order.py. Run by test_stage_order.sh (which owns the scratch dir: OVN_TEST_TMP).
Replay inputs are REAL data pulled read-only from the GPU box on 2026-10-18 (fixtures/stage_order/): 8 decomposed plans from state/stage_runs and 4 feature groups
from OVERNIGHT_PROGRESS.md (TAA get_live_role, xlite patrol_routes_ok, iptv parental, xlite capture)."""
import importlib.util, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MOD = os.path.join(ROOT, "scripts", "ovn_stage_order.py")
FIX = os.path.join(HERE, "fixtures", "stage_order")
TMP = os.environ.get("OVN_TEST_TMP") or sys.exit("OVN_TEST_TMP (scratch dir from the .sh wrapper) is required")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:300]) if extra else ""))


def load(path, name="ovn_stage_order_t"):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def group(name):
    return open(os.path.join(FIX, name)).read()


def check_core(o):
    """The behavioural contract. Returns the list of failed check names (used for the real module AND for every mutant)."""
    bad = []

    def chk(n, c, _x=None):
        if not c:
            bad.append(n)
    pl = {}
    for r in (json.loads(l) for l in open(os.path.join(FIX, "real_plans.jsonl"))):
        pl[r["run"]] = r
    # --- R1: billwatch auth.py: test-file step BEFORE the impl step that defines should_skip_refresh (real run billwatch-20261017-225811)
    r1 = pl[[k for k in pl if k.startswith("billwatch-20261017-225811")][0]]
    sh = o.plan_steps(r1["plan"], "shadow")
    chk("shadow keeps the model order", [s["desc"] for s in sh["steps"]] == [s["desc"] for s in r1["plan"]] and not sh["changed"])
    chk("shadow journals a would_reorder merge", any(d["event"] == "would_reorder" and d["action"] == "merge" and d["red_by_design"] for d in sh["decisions"]))
    en = o.plan_steps(r1["plan"], "enforce")
    chk("enforce merges test step into the fix step (1 step, both files)", len(en["steps"]) == 1 and len(en["steps"][0]["files"]) == 2)
    chk("merged step verify carries the test verify", "test_auth_interceptor_logic.py" in en["steps"][0]["verify"])
    # --- R2: TAA execution_engine (_finalize flaky_count) real run test-automation-agent-20261018-011309
    r2 = pl[[k for k in pl if k.startswith("test-automation-agent-20261018-011309")][0]]
    e2 = o.plan_steps(r2["plan"], "enforce")
    chk("TAA: red-by-design test merged with the engine change", len(e2["steps"]) == 1 and e2["changed"])
    # --- R3: well-ordered real plans are NOT touched (no false positives): src-then-test, removal refs-then-def, test-removal then def removal
    for pre in ("billwatch-20261017-165843", "gitlark-20261018-020937", "xlite-20261018-025851", "gitlark-20261017-220525"):
        ks = [k for k in pl if k.startswith(pre)]
        if not ks:
            continue
        pr = pl[ks[0]]["plan"]
        e = o.plan_steps(pr, "enforce")
        chk("well-ordered real plan untouched: " + pre, not e["changed"] and [s["desc"] for s in e["steps"]] == [s["desc"] for s in pr], e["decisions"])
    # --- explicit depends_on drives a plain reorder of two non-test steps
    steps = [{"desc": "Wire handler in api.py", "files": ["app/api.py"], "verify": "x", "depends_on": [1]},
             {"desc": "Add helper `make_widget_id` in util.py", "files": ["app/util.py"], "verify": "y"}]
    e = o.plan_steps(steps, "enforce")
    chk("explicit depends_on reorders", [s["id"] for s in e["steps"]] == [1, 0] and e["steps"][1]["deps"] == [1])
    chk("explicit depends_on shadow unchanged", [s["id"] for s in o.plan_steps(steps, "shadow")["steps"]] == [0, 1])
    # --- unmet gate
    chk("unmet lists an unlanded prerequisite", o.unmet(e["steps"], 1, []) == [1])
    chk("unmet clears once the prerequisite landed", o.unmet(e["steps"], 1, ["1"]) == [])
    # --- merge cap: files union too large -> plain reorder after the fix, never merged
    big = [{"desc": "Add test for `parse_thing_x`", "files": ["tests/test_a.py", "tests/test_b.py", "tests/test_c.py"], "verify": "pytest tests"},
           {"desc": "Add `parse_thing_x` function", "files": ["app/p.py", "app/q.py"], "verify": "pytest"}]
    eb = o.plan_steps(big, "enforce")
    chk("over the file cap: reordered not merged", len(eb["steps"]) == 2 and [s["id"] for s in eb["steps"]] == [1, 0])
    # --- cycle: mutual references must resolve (decision recorded), never loop
    cyc = [{"desc": "Add test for `alpha_beta`", "files": ["tests/test_ab.py"], "verify": "pytest tests/test_ab.py"},
           {"desc": "Add `alpha_beta` function", "files": ["app/ab.py"], "verify": "pytest tests/test_ab.py"}]
    ec = o.plan_steps(cyc, "enforce")
    chk("cycle: weak verify edge dropped, plan still produced", ec["steps"] and any(d.get("event") == "cycle_resolved" for d in ec["decisions"]))
    # --- feature-group items (real queue text)
    t = group("group_taa_get_live_role.md")
    its = o.parse_progress(t)
    ds = o.item_decisions([i["text"] for i in its], t)
    chk("TAA: T1/T2 source items are runnable", not ds[0]["blocked"] and not ds[1]["blocked"])
    chk("TAA: T3/T4/T5 test items wait for the source items", all(d["blocked"] for d in ds[2:]), [d["blocked"] for d in ds])
    t2 = t.replace("- [ ] [T1]", "- [x] [T1]").replace("- [ ] [T2]", "- [x] [T2]")
    ds2 = o.item_decisions([i["text"] for i in o.parse_progress(t2) if not i["done"]], t2)
    chk("TAA: test items unblock once T1/T2 are done", not any(d["blocked"] for d in ds2), [d["waiting_on"] for d in ds2])
    t3 = group("group_xlite_patrol.md")
    its3 = o.parse_progress(t3)
    d3 = o.item_decisions([i["text"] for i in its3], t3)
    wire = [d for d, i in zip(d3, its3) if "mission_data.gd" in i["text"]][0]
    chk("xlite: MissionData.is_valid wiring waits for the item defining patrol_routes_ok", wire["blocked"] and wire["waiting_on"][0]["kind"] == "symbol")
    chk("xlite: the defining T1 item itself is runnable", not d3[0]["blocked"])
    t4 = t3.replace("- [ ] [T1] scripts/mission/mission_validator.gd", "- [x] [T1] scripts/mission/mission_validator.gd", 1)
    its4 = [i for i in o.parse_progress(t4) if not i["done"]]
    d4 = o.item_decisions([i["text"] for i in its4], t4)
    wire4 = [d for d, i in zip(d4, its4) if "mission_data.gd" in i["text"]][0]
    chk("xlite: wiring unblocks when the definer is done", not wire4["blocked"], wire4)
    t5 = t3.replace("- [ ] [T1] scripts/mission/mission_validator.gd", "- [ ] [AUTO-SKIP parked] [T1] scripts/mission/mission_validator.gd", 1)
    its5 = o.parse_progress(t5)
    d5 = o.item_decisions([i["text"] for i in its5 if not i["parked"]], t5)
    w5 = [d for d, i in zip(d5, [x for x in its5 if not x["parked"]]) if "mission_data.gd" in i["text"]][0]
    chk("xlite: a PARKED prerequisite keeps its dependent parked (state=parked)", w5["blocked"] and w5["waiting_on"][0]["state"] == "parked")
    # --- removal semantics: negative regression test goes after the removal; ref/test removal goes before the definition removal
    rm = "# n\n- [ ] [T1] app/s.py — Remove the `legacy_flag_x` function definition. VERIFY: `grep -c legacy_flag_x app/s.py` (cat:python) [feat:g]\n- [ ] [T2] tests/test_s.py — Add a regression test `test_legacy_flag_x_not_exposed` asserting `legacy_flag_x` does not exist. VERIFY: `pytest tests/test_s.py` (cat:test) [feat:g]\n"
    ri = o.parse_progress(rm)
    rd = o.item_decisions([i["text"] for i in ri], rm)
    chk("removal: the negative test waits for the removal, the removal does not wait for it", (not rd[0]["blocked"]) and rd[1]["blocked"], rd)
    rm2 = "# n\n- [ ] [T1] app/s.py \u2014 Remove the `legacy_flag_x` function definition. VERIFY: `grep -c legacy_flag_x app/s.py` (cat:python) [feat:g]\n- [ ] [T2] tests/test_s.py \u2014 Remove all test cases for `legacy_flag_x`. VERIFY: `pytest tests/test_s.py` (cat:test) [feat:g]\n"
    r2d = o.item_decisions([i["text"] for i in o.parse_progress(rm2)], rm2)
    chk("removal: the definition removal waits for the removal of its tests", r2d[0]["blocked"] and not r2d[1]["blocked"], r2d)
    # --- D3 repair: merge must not create a mutual dependency (triangle), the merged verify keeps both clauses with '&&', never an empty string
    tri = [{"desc": "Add test verifying foo_bar and baz_qux", "files": ["tests/test_x.py"], "verify": "pytest tests/test_x.py"},
           {"desc": "Add function foo_bar to app/a.py", "files": ["app/a.py"], "verify": "pytest tests/test_a.py"},
           {"desc": "Add function baz_qux to app/b.py that calls foo_bar", "files": ["app/b.py"], "verify": "pytest tests/test_b.py"}]
    et = o.plan_steps(tri, "enforce")
    um = [o.unmet(et["steps"], i, []) for i in range(len(et["steps"]))]
    chk("triangle: at least one step has no unmet prerequisite (no mutual park)", any(not u for u in um), [(s["id"], s["deps"]) for s in et["steps"]])
    chk("triangle: dependency lists are acyclic", not any(a in x["deps"] and x["id"] in next(y for y in et["steps"] if y["id"] == a)["deps"] for x in et["steps"] for a in x["deps"]), [(s["id"], s["deps"]) for s in et["steps"]])
    chk("triangle: foo_bar lands before baz_qux and the test rides with the last one", [s["id"] for s in et["steps"]][0] == 1 and len(et["steps"]) == 2, [(s["id"], s["deps"]) for s in et["steps"]])
    chk("triangle: post-merge cycle recorded as a decision", any(d.get("phase") == "post_merge" for d in et["decisions"]), et["decisions"])
    mg = o.plan_steps([{"desc": "Add test verifying foo_bar", "files": ["tests/test_x.py"], "verify": "pytest tests/test_x.py"},
                       {"desc": "Add function foo_bar to app/a.py", "files": ["app/a.py"], "verify": "pytest tests/test_a.py"}], "enforce")["steps"]
    chk("merged verify combines both clauses with &&", len(mg) == 1 and " && " in mg[0]["verify"] and " || " not in mg[0]["verify"] and "test_x.py" in mg[0]["verify"] and "test_a.py" in mg[0]["verify"], mg)
    nv = o.plan_steps([{"desc": "Add test verifying foo_bar", "files": ["tests/test_x.py"]}, {"desc": "Add function foo_bar to app/a.py", "files": ["app/a.py"]}], "enforce")["steps"]
    chk("merge of steps without verify leaves the key MISSING (runner defaults to 'tests green')", len(nv) == 1 and "verify" not in nv[0], nv)
    # --- D3 repair: the picker matches the FULL line; a long shared prefix must not inherit another item's prerequisites
    lp = "backend/tests/test_long_module_name_for_widgets.py \u2014 Add test case verifying that"
    pg = ("# n\n- [ ] [T3] tests/test_w.py \u2014 Add test verifying `widget_total` returns 3. VERIFY: `pytest tests/test_w.py` (cat:test) [feat:g1]\n"
          "- [ ] [T1] app/w.py \u2014 Add `widget_total` function. VERIFY: `pytest tests/test_w.py` (cat:python) [feat:g1]\n"
          "- [ ] [T3] " + lp + " `plain_other` works. VERIFY: `pytest backend/tests/test_long_module_name_for_widgets.py` (cat:test) [feat:g2]\n"
          "- [ ] [T3] " + lp + " `widget_total` works. VERIFY: `pytest backend/tests/test_long_module_name_for_widgets.py` (cat:test) [feat:g1]\n"
          "- [ ] [T1] app/z.py \u2014 Add `zeta_thing` function (cat:python) [feat:g2]\n")
    pc = [i["text"] for i in o.parse_progress(pg)]
    pd = o.item_decisions([pc[2]], pg)
    chk("independent g2 item sharing a long prefix is not blocked by g1", not pd[0]["blocked"], pd)
    chk("a truncated 80-char candidate no longer matches a different item", not o.item_decisions([pc[3][:80]], pg)[0]["blocked"])
    # --- D3 repair: a PARKED prerequisite is an escalation signal (journaled), still held by default; OVN_STAGE_ORDER_PARKED=release lets the dependent through
    pk = "# n\n- [ ] [AUTO-SKIP after 2 credit refusals] [T2] app/p.py \u2014 Add `park_me_fn` function. VERIFY: `pytest tests/test_p.py` (cat:python) [feat:gp]\n- [ ] [T3] tests/test_p.py \u2014 Add test verifying `park_me_fn` works. VERIFY: `pytest tests/test_p.py` (cat:test) [feat:gp]\n"
    open(os.path.join(TMP, "pk_src.md"), "w").write(pk)
    pdx = o.item_decisions([o.parse_progress(pk)[1]["text"]], pk)[0]
    chk("parked prerequisite: dependent flagged stuck_parked", pdx["blocked"] and pdx.get("stuck_parked") is True, pdx)
    chk("open prerequisite is not stuck_parked", not o.item_decisions([pc[0]], pg)[0].get("stuck_parked"))
    return bad


def cli_parked(modpath):
    """CLI contract: stuck_on_parked_prereq journaled (default hold keeps nothing, release keeps the dependent)."""
    prog = os.path.join(TMP, "pprog.md")
    lg = os.path.join(TMP, "pk.log")
    if os.path.exists(lg):
        os.remove(lg)
    txt = open(os.path.join(TMP, "pk_src.md")).read() if os.path.exists(os.path.join(TMP, "pk_src.md")) else ""
    open(prog, "w").write(txt)
    line = [l for l in txt.split("\n") if l.startswith("- [ ] [T3]")]
    env = dict(os.environ)
    env.pop("OVN_STAGE_ORDER_PARKED", None)
    h = subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--mode", "enforce", "--log", lg], input="\n".join(line).encode(), capture_output=True, timeout=30, env=env)
    held = not h.stdout.decode().strip() and '"stuck_on_parked_prereq"' in open(lg).read()
    env["OVN_STAGE_ORDER_PARKED"] = "release"
    r = subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--mode", "enforce"], input="\n".join(line).encode(), capture_output=True, timeout=30, env=env)
    return held and r.stdout.decode().strip() == line[0]


def cli_enforce_keeps_only_sources(modpath):
    """CLI-level contract used for the mutants of the filter itself: enforce must drop the blocked test items of the TAA group."""
    prog = os.path.join(TMP, "mprog.md")
    open(prog, "w").write(group("group_taa_get_live_role.md"))
    lines = "\n".join(l for l in open(prog).read().split("\n") if l.startswith("- [ ] [T"))
    r = subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--mode", "enforce"], input=lines.encode(), capture_output=True, timeout=30)
    return len([l for l in r.stdout.decode().split("\n") if l.strip()]) == 2


def cli_dedupe(modpath):
    """CLI contract: repeated scout cycles journal each blocked item once (byte-identical rows are skipped), different repos still journal."""
    prog = os.path.join(TMP, "dprog.md")
    open(prog, "w").write(group("group_taa_get_live_role.md"))
    lines = "\n".join(l for l in open(prog).read().split("\n") if l.startswith("- [ ] [T"))
    lg = os.path.join(TMP, "dd.log")
    if os.path.exists(lg):
        os.remove(lg)
    for _ in range(3):
        subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--repo", "a", "--log", lg], input=lines.encode(), capture_output=True, timeout=30)
    n1 = open(lg).read().count('"would_skip_item"')
    subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--repo", "b", "--log", lg], input=lines.encode(), capture_output=True, timeout=30)
    return n1 == 3 and open(lg).read().count('"would_skip_item"') == 6


def cli_cap_and_trunc(modpath):
    """Group-size cap fails open (a 70-item group with a real test-first dependency blocks nothing) and journal truncation is an atomic replace (new inode)."""
    src = ["- [ ] [T3] backend/app/m%d.py \u2014 Add `sym_%d` helper. VERIFY: `pytest` (cat:python; multifile:no) [feat:big]" % (i, i) for i in range(69)]
    tst = "- [ ] [T3] backend/tests/test_sym_0.py \u2014 Add test for the `sym_0` helper. VERIFY: `pytest backend/tests/test_sym_0.py` (cat:test; multifile:no) [feat:big]"
    prog = os.path.join(TMP, "capprog.md")
    open(prog, "w").write("\n".join(src + [tst]) + "\n")
    env = dict(os.environ)
    env.pop("OVN_STAGE_ORDER_MAX_GROUP", None)
    def run(extra):
        e = dict(env)
        e.update(extra)
        return subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--mode", "enforce"], input=tst.encode(), capture_output=True, timeout=60, env=e).stdout.decode().strip()
    control = run({"OVN_STAGE_ORDER_MAX_GROUP": "200"}) == ""   # under a high cap the test-first line IS blocked (proves the control is real)
    capped = run({}) == tst[6:] or run({}) == tst
    lg = os.path.join(TMP, "tr.log")
    open(lg, "w").write(("z" * 400 + "\n") * 1000)
    ino = os.stat(lg).st_ino
    subprocess.run([sys.executable, "-I", modpath, "plan", "--mode", "shadow", "--log", lg], input=b'[{"desc":"Add test for `qq_rr`","files":["t/test_q.py"]},{"desc":"Add `qq_rr` function","files":["a/q.py"]}]', capture_output=True, timeout=30)
    return control and capped and os.stat(lg).st_ino != ino and os.path.getsize(lg) < 262144


def schema_sibling(modpath, extra):
    """True when the T3/T4 router items of a feat group are blocked (enforce) by the open T2 model item and a done model item does not block."""
    feat = "[feat:iptv_apps-20261020-sh-x]"
    t2 = "- [ ] [T2] iptv-backend/app/models/search.py — Add `profile_id` column to `SearchHistory`. VERIFY: `cd iptv-backend && python -c \"print(1)\"`. (cat:python; multifile:no) " + feat
    t3 = "- [ ] [T3] iptv-backend/app/routers/search.py — Update `search_history` endpoint to filter by `active_profile_id(active_profile)`. VERIFY: `cd iptv-backend && python -m pytest tests/test_x.py::test_a -v`. (cat:endpoint; multifile:no) " + feat
    t4 = t3.replace("[T3]", "[T4]").replace("search_history", "search_suggestions")
    prog = os.path.join(TMP, "schema_sib.md")
    env = dict(os.environ)
    env.pop("OVN_STAGE_ORDER", None)
    env.update(extra)
    def run(lines, text):
        open(prog, "w").write("\n".join(lines) + "\n")
        return subprocess.run([sys.executable, "-I", modpath, "item-filter", "--progress", prog, "--mode", "enforce"], input=text.encode(), capture_output=True, timeout=60, env=env).stdout.decode().strip()
    cands = t3[6:] + "\n" + t4[6:]
    open_out = run([t2, t3, t4], cands)
    done_out = run([t2.replace("- [ ]", "- [x]", 1), t3, t4], cands)
    return open_out == "" and len([l for l in done_out.split("\n") if l.strip()]) == 2


def main():
    o = load(MOD)
    print("== U: contract on the real module")
    bad = check_core(o)
    ok("all behavioural checks hold (real module)", bad == [], bad)
    ok("CLI enforce filter drops the blocked test items (real module)", cli_enforce_keeps_only_sources(MOD))
    ok("CLI parked prerequisite: journaled + held by default, released with OVN_STAGE_ORDER_PARKED=release", cli_parked(MOD))
    ok("CLI group cap fails open (70-item group not analysed) + atomic journal truncation", cli_cap_and_trunc(MOD))
    ok("CLI journal dedupe: 3 scout cycles -> 3 rows, other repo adds its own", cli_dedupe(MOD))
    ok("schema sibling: endpoint items wait for the open lower-tier model item (iptv search_history.profile_id)", schema_sibling(MOD, {}))
    ok("schema sibling: kill switch OVN_STAGE_ORDER_SCHEMA_TIER=off restores the old (unblocked) behaviour", not schema_sibling(MOD, {"OVN_STAGE_ORDER_SCHEMA_TIER": "off"}))
    print("== M: mutants of the module must each be CAUGHT by the same contract")
    src = open(MOD).read()
    muts = {
        "M1 no dependency edges": ("    return drop_cycles(uniq)   # -> (edges, notes)", "    return [], []"),
        "M2 merge never happens": ('action = "merge" if (nb["test_only"] != na["test_only"] and len(union) <= max_files) else "reorder"', 'action = "reorder"'),
        "M3 shadow rewrites the plan": ('    if mode != "enforce" or not viol:', "    if not viol:"),
        "M4 unmet gate always empty": ("    return [x for x in deps if str(x) not in d]", "    return []"),
        "M5 enforce keeps blocked items": ('            if mode == "enforce":\n                continue\n        keep.append(ln)', "            pass\n        keep.append(ln)"),
        "M6 done prerequisite still blocks": ('if b == n["id"] and not byid[a]["it"]["done"]:', 'if b == n["id"]:'),
        "M7 symbol edges ignore removal semantics": ('                if a["removal"]:\n', '                if False:\n'),
        "M8 merge ignores the file cap": ("len(union) <= max_files and b in work and a in work", "b in work and a in work"),
        "M10 no cycle check after a merge": ("        new_edges, post_notes = drop_cycles(uniq_e)", "        post_notes = []"),
        "M11 picker matches an 80-char prefix": ('and n["it"]["text"].strip() == key:', 'and (n["it"]["text"].strip() == key or key[:80] in n["it"]["text"]):'),
        "M12 merged verify uses ||": ('"(%s) && (%s)" % (va, vb)', '"(%s) || (%s)" % (va, vb)'),
        "M13 merged verify invented empty": ('            if mv or "verify" in tgt:', "            if True:"),
        "M14 parked prerequisite not journaled": ('_journal(a.log, {"event": "stuck_on_parked_prereq"', '_journal(os.devnull, {"event": "stuck_on_parked_prereq"'),
        "M15 parked release always": ('parked_mode == "release":', 'parked_mode != "never":'),
        "M16 item-filter journal not deduplicated": ('"waiting_on": d["waiting_on"]}, dedupe=True)\n            if mode == "enforce":', '"waiting_on": d["waiting_on"]})\n            if mode == "enforce":'),
        "M17 group-size cap off": ("len(grp) < 2 or len(grp) > _max_group()", "len(grp) < 2"),
        "M18 journal truncation not atomic": ("os.replace(tmp, path)", "open(path, 'wb').write(open(tmp, 'rb').read())"),
        "M19 schema-sibling rule off": ('if (os.environ.get("OVN_STAGE_ORDER_SCHEMA_TIER", "on") != "off" and b.get("tier")', 'if (False and b.get("tier")'),
        "M9 tier_stem rule off": ('if b.get("tier") and a.get("tier") and b["test_only"]', 'if False and b["test_only"]'),
    }
    for name, (old, new) in muts.items():
        if src.count(old) != 1:
            ok(name + " (mutation applies exactly once)", False, src.count(old))
            continue
        mp = os.path.join(TMP, "mut_%s.py" % name.split()[0])
        open(mp, "w").write(src.replace(old, new))
        try:
            mb = check_core(load(mp, "mut_" + name.split()[0]))
            if not cli_enforce_keeps_only_sources(mp):
                mb = mb + ["cli enforce filter"]
            if not cli_parked(mp):
                mb = mb + ["cli parked"]
            if not cli_cap_and_trunc(mp):
                mb = mb + ["cli cap/trunc"]
            if not cli_dedupe(mp):
                mb = mb + ["cli dedupe"]
            if not schema_sibling(mp, {}):
                mb = mb + ["schema sibling"]
        except Exception as ex:  # noqa: BLE001 - a mutant that crashes is also caught
            mb = ["crash:" + type(ex).__name__]
        ok(name + " is caught", bool(mb), "mutant survived")
    print("== C: CLI behaviour (fail-open, modes, journal)")
    env = dict(os.environ)
    env.pop("OVN_STAGE_ORDER", None)
    log = os.path.join(TMP, "so.log")
    plan = json.dumps([{"desc": "Add test for `gamma_delta`", "files": ["tests/test_gd.py"], "verify": "pytest tests/test_gd.py"}, {"desc": "Add `gamma_delta` function", "files": ["app/gd.py"], "verify": "pytest"}])

    def cli(args, stdin, extra=None):
        e = dict(env)
        e.update(extra or {})
        return subprocess.run([sys.executable, "-I", MOD] + args, input=stdin.encode(), capture_output=True, env=e, timeout=30)
    r = cli(["plan", "--log", log, "--repo", "r", "--run", "run1", "--item", "it"], plan)
    j = json.loads(r.stdout)
    ok("default mode is shadow: plan unchanged", r.returncode == 0 and not j["changed"] and len(j["steps"]) == 2)
    ok("shadow journal row written (would_reorder, mode shadow)", os.path.exists(log) and '"would_reorder"' in open(log).read() and '"mode": "shadow"' in open(log).read())
    r = cli(["plan", "--mode", "off"], plan)
    ok("off: passthrough, no decisions", json.loads(r.stdout)["decisions"] == [] and len(json.loads(r.stdout)["steps"]) == 2)
    r = cli(["plan"], plan, {"OVN_STAGE_ORDER": "enforce"})
    ok("enforce via OVN_STAGE_ORDER env merges", json.loads(r.stdout)["changed"] and len(json.loads(r.stdout)["steps"]) == 1)
    r = cli(["plan"], plan, {"OVN_STAGE_ORDER": "bogus"})
    ok("garbage mode falls back to shadow", not json.loads(r.stdout)["changed"])
    r = cli(["plan"], "not json at all")
    ok("garbage input fails open (rc 0, empty plan)", r.returncode == 0 and json.loads(r.stdout)["steps"] == [])
    r = cli(["unmet", "--i", "0", "--done", ""], "garbage")
    ok("unmet on garbage fails open (empty, rc 0)", r.returncode == 0 and r.stdout == b"")
    prog = os.path.join(TMP, "prog.md")
    open(prog, "w").write(group("group_taa_get_live_role.md"))
    lines = "\n".join(l for l in open(prog).read().split("\n") if l.startswith("- [ ] [T"))
    il = os.path.join(TMP, "item.log")
    r = cli(["item-filter", "--progress", prog, "--repo", "taa", "--log", il], lines)
    ok("item-filter shadow passes every line", r.stdout.decode().strip().split("\n") == lines.split("\n"))
    ok("item-filter shadow journals would_skip_item for the 3 test items", open(il).read().count('"would_skip_item"') == 3)
    r = cli(["item-filter", "--progress", prog, "--mode", "enforce"], lines)
    ok("item-filter enforce keeps only the 2 source items", len([l for l in r.stdout.decode().split("\n") if l.strip()]) == 2)
    r = cli(["item-filter", "--progress", os.path.join(TMP, "missing.md"), "--mode", "enforce"], lines)
    ok("item-filter with an unreadable progress file fails open", r.stdout.decode().strip().split("\n") == lines.split("\n"))
    big = os.path.join(TMP, "cap.log")
    open(big, "w").write(("x" * 400 + "\n") * 1000)
    cli(["plan", "--mode", "shadow", "--log", big], plan)
    ok("journal is bounded (cut to the newest rows once over the cap)", os.path.getsize(big) < 262144 and open(big).read().count("\n") <= 502)
    ok("journal lock file is used (flock serialisation)", os.path.exists(log + ".lock"))
    big2 = os.path.join(TMP, "cap2.log")
    open(big2, "w").write(("y" * 400 + "\n") * 1000)
    cli(["plan", "--mode", "shadow", "--log", big2], plan)
    ok("truncation leaves no tmp file behind (atomic replace)", not [f for f in os.listdir(TMP) if f.startswith("cap2.log.tmp")] and os.path.getsize(big2) < 262144)
    mod = load(MOD, "so_cap")
    many = "\n".join("- [ ] [T3] backend/app/m%d.py \u2014 Add `sym_%d` helper. VERIFY: `pytest` (cat:python; multifile:no) [feat:big]" % (i, i) for i in range(70))
    import time
    t0 = time.time()
    dec = mod.item_decisions([l[6:] for l in many.split("\n")], many)
    ok("group above OVN_STAGE_ORDER_MAX_GROUP (60) is not analysed: fail-open, nothing blocked, fast", len(dec) == 70 and not any(d["blocked"] for d in dec) and time.time() - t0 < 5)
    print("\n%d passed, %d failed" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
