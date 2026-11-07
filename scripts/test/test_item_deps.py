#!/usr/bin/env python3
"""Y4: tests + mutants for scripts/ovn_item_deps.py (behaviour-dependency gate + production-before-test ordering).
Fixture group_iptv_wipe_shared.md = the REAL iptv_apps 'wipe-the-shared' feature lines (T3 production item + 4 test items) from origin/claude/feature, 2026-11-05.
Run by test_item_deps.sh (OVN_TEST_TMP = scratch dir owned by the wrapper)."""
import importlib.util, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MOD = os.path.join(ROOT, "scripts", "ovn_item_deps.py")
FIX = os.path.join(HERE, "fixtures", "item_deps")
TMP = os.environ.get("OVN_TEST_TMP") or sys.exit("OVN_TEST_TMP required")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1; print("  ok   " + name)
    else:
        F += 1; print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def load(path, name="ovn_item_deps_t"):
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def run(modpath, args, stdin="", env=None):
    e = dict(os.environ); e.update({"NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "TZ": "UTC"}); e.update(env or {})
    p = subprocess.run([sys.executable, "-I", modpath] + args, input=stdin, capture_output=True, text=True, env=e, timeout=60)
    return p.returncode, p.stdout, p.stderr


GRP = open(os.path.join(FIX, "group_iptv_wipe_shared.md")).read()
OPEN = [l for l in GRP.split("\n") if l.startswith("- [ ] ")]
PROD, TESTS = OPEN[0], OPEN[1:]


def item(tier, path, desc, verify, cat, feat="f1", done=False):
    return "- [%s] [T%d] %s — %s VERIFY: `%s`. (cat:%s; multifile:no) [feat:%s]" % ("x" if done else " ", tier, path, desc, verify, cat, feat)


def core(modpath):
    """Behaviour contract; returns the list of failed check names (real module AND every mutant)."""
    bad = []

    def chk(n, c):
        if not c:
            bad.append(n)
    prog = os.path.join(TMP, "p.md"); open(prog, "w").write(GRP)
    cand = "\n".join(OPEN) + "\n"
    # 1 real group, enforce: only the production line survives
    rc, out, _ = run(modpath, ["item-filter", "--progress", prog, "--mode", "enforce"], cand)
    chk("enforce-real-group-only-prod", rc == 0 and [l for l in out.split("\n") if l] == [PROD])
    # 2 shadow: output byte-identical, journal rows exist for the 4 tests
    log = os.path.join(TMP, "shadow.log")
    for x in (log, log + ".lock"):
        if os.path.exists(x): os.remove(x)
    rc, out, _ = run(modpath, ["item-filter", "--progress", prog, "--mode", "shadow", "--repo", "iptv_apps", "--log", log], cand)
    rows = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
    chk("shadow-unchanged", out == cand)
    chk("shadow-logs-4-would-defer", len(rows) == 4 and all(r["event"] == "would_defer_item" and r["count"] == 1 for r in rows))
    chk("shadow-row-names-prereq", rows and rows[0]["waiting_on"][0]["kind"] in ("name_contains", "stem_overlap") and "discover.py" in rows[0]["waiting_on"][0]["tier_text"])
    run(modpath, ["item-filter", "--progress", prog, "--mode", "shadow", "--repo", "iptv_apps", "--log", log], cand)
    rows2 = [json.loads(l) for l in open(log)]
    chk("shadow-repeat-merges-not-duplicates", len(rows2) == 4 and all(r["count"] == 2 for r in rows2))
    # 3 default mode is shadow
    rc, out, _ = run(modpath, ["item-filter", "--progress", prog], cand, {"OVN_ITEM_DEPS": ""})
    chk("default-is-shadow", out == cand)
    rc, out, _ = run(modpath, ["item-filter", "--progress", prog, "--mode", "bogus"], cand)
    chk("bogus-mode-is-shadow", out == cand)
    # 4 off
    rc, out, _ = run(modpath, ["item-filter", "--progress", prog, "--mode", "off"], cand)
    chk("off-unchanged", out == cand)
    # 5 prerequisite ticked -> nothing deferred
    done_prog = os.path.join(TMP, "pd.md"); open(done_prog, "w").write(GRP.replace(PROD, PROD.replace("- [ ]", "- [x]", 1)))
    rc, out, _ = run(modpath, ["item-filter", "--progress", done_prog, "--mode", "enforce"], "\n".join(TESTS) + "\n")
    chk("ticked-prereq-releases", [l for l in out.split("\n") if l] == TESTS)
    # 6 parked prerequisite: hold (default) vs release
    park_prog = os.path.join(TMP, "pk.md"); open(park_prog, "w").write(GRP.replace(PROD, PROD.replace("- [ ] ", "- [ ] [AUTO-SKIP staged: x] ", 1)))
    rc, out, _ = run(modpath, ["item-filter", "--progress", park_prog, "--mode", "enforce"], "\n".join(TESTS) + "\n")
    chk("parked-prereq-holds", out.strip() == "")
    rc, out, _ = run(modpath, ["item-filter", "--progress", park_prog, "--mode", "enforce"], "\n".join(TESTS) + "\n", {"OVN_ITEM_DEPS_PARKED": "release"})
    chk("parked-prereq-release-opt", [l for l in out.split("\n") if l] == TESTS)
    # 7 fail-open: unreadable/garbage progress, missing progress
    rc, out, _ = run(modpath, ["item-filter", "--progress", os.path.join(TMP, "nope.md"), "--mode", "enforce"], cand)
    chk("missing-progress-failopen", rc == 0 and out == cand)
    # 8 no feat tag / other group -> never blocked
    solo = os.path.join(TMP, "solo.md")
    a = item(3, "b/app/routers/x.py", "Modify `frobnicate_widget` to add auth", "pytest b/tests/test_x.py", "endpoint", feat="")
    t = item(3, "b/tests/test_x.py", "Add `test_frobnicate_widget_denied` to verify 403", "pytest b/tests/test_x.py::test_frobnicate_widget_denied -q", "test", feat="")
    open(solo, "w").write(a + "\n" + t + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", solo, "--mode", "enforce"], t + "\n")
    chk("untagged-never-blocked", out.strip() == t)
    other = os.path.join(TMP, "other.md")
    t2 = t.replace("[feat:]", "[feat:g2]") if "[feat:]" in t else t + " [feat:g2]"
    open(other, "w").write(item(3, "b/app/routers/x.py", "Modify `frobnicate_widget` to add auth", "pytest b/tests/test_x.py", "endpoint", feat="g1") + "\n" + t2 + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", other, "--mode", "enforce"], t2 + "\n")
    chk("other-feature-group-never-blocks", out.strip() == t2)
    # 9 production never waits on a test
    pt = os.path.join(TMP, "pt.md")
    prod = item(2, "b/app/routers/y.py", "Modify `handle_gizmo` to check scope", "pytest b/tests/test_y.py", "endpoint", feat="g3")
    tst = item(2, "b/tests/test_y.py", "Add `test_handle_gizmo_scope` to assert scope check", "pytest b/tests/test_y.py::test_handle_gizmo_scope -q", "test", feat="g3")
    open(pt, "w").write(tst + "\n" + prod + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", pt, "--mode", "enforce"], prod + "\n" + tst + "\n")
    chk("prod-not-blocked-test-blocked", out.strip() == prod)
    # 10 new_file: B's VERIFY runs a file an open sibling creates
    nf = os.path.join(TMP, "nf.md")
    mk = item(3, "b/tests/test_rate.py", "Create a new test file b/tests/test_rate.py with a smoke test", "pytest b/tests/test_rate.py -q", "test", feat="g4")
    use = item(3, "b/app/core/limiter.py", "Set the limit on the limiter", "pytest b/tests/test_rate.py -q", "python", feat="g4")
    open(nf, "w").write(mk + "\n" + use + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", nf, "--mode", "enforce"], use + "\n")
    chk("new-file-sibling-defers", out.strip() == "")
    rc, out, _ = run(modpath, ["item-filter", "--progress", nf, "--mode", "enforce"], mk + "\n")
    chk("new-file-creator-not-deferred", out.strip() == mk)
    # 11 verify_creates
    vc = os.path.join(TMP, "vc.md")
    adder = item(3, "b/tests/test_a.py", "Add `test_quota_exceeded` covering the quota path", "pytest b/tests/test_a.py::test_quota_exceeded -q", "test", feat="g5")
    runner = item(4, "b/app/svc.py", "Tidy the quota service", "pytest b/tests/test_a.py::test_quota_exceeded -q", "python", feat="g5")
    open(vc, "w").write(adder + "\n" + runner + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", vc, "--mode", "enforce"], runner + "\n")
    chk("verify-creates-defers", out.strip() == "")
    # 12 verify_missing needs --tree
    vm = os.path.join(TMP, "vm.md"); tree = os.path.join(TMP, "tree"); os.makedirs(tree, exist_ok=True)
    maker = item(2, "b/app/newmod.py", "Add module b/app/newmod.py with `compute_total`", "python -c 'import b.app.newmod'", "python", feat="g6")
    needs = item(3, "b/app/other.py", "Wire compute into other", "pytest b/app/newmod.py -q", "python", feat="g6")
    open(vm, "w").write(maker + "\n" + needs + "\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", vm, "--mode", "enforce", "--tree", tree], needs + "\n")
    chk("verify-missing-with-tree-defers", out.strip() == "")
    os.makedirs(os.path.join(tree, "b", "app"), exist_ok=True); open(os.path.join(tree, "b", "app", "newmod.py"), "w").write("x=1\n")
    rc, out, _ = run(modpath, ["item-filter", "--progress", vm, "--mode", "enforce", "--tree", tree], needs + "\n")
    chk("verify-missing-path-exists-no-defer", out.strip() == needs)
    # 13 order: reversed real group -> production first, tests keep relative order
    rev = "\n".join(reversed(OPEN)) + "\n"
    rc, out, err = run(modpath, ["order"], rev)
    got = [l for l in out.split("\n") if l]
    chk("order-prod-first", got and got[0] == PROD and sorted(got) == sorted(OPEN))
    rc, out, _ = run(modpath, ["order"], "\n".join(OPEN) + "\n")
    chk("order-stable-when-already-ok", out == "\n".join(OPEN) + "\n")
    mixed = "# header\n" + rev.rstrip("\n") + "\nnot an item\n"
    rc, out, _ = run(modpath, ["order"], mixed)
    ol = out.split("\n")
    chk("order-non-item-lines-keep-slots", ol[0] == "# header" and ol[-2] == "not an item" and ol[1] == PROD)
    rc, out, _ = run(modpath, ["order"], rev, {"OVN_PLANNER_ITEM_ORDER": "off"})
    chk("order-off-keeps-input", out == rev)
    rc, out, _ = run(modpath, ["order"], "")
    chk("order-empty-ok", rc == 0 and out == "")
    # unrelated items keep their order
    u1 = item(2, "b/app/a.py", "Add `alpha_one` helper", "pytest b/tests/test_a.py", "python", feat="g7")
    u2 = item(2, "b/app/b.py", "Add `beta_two` helper", "pytest b/tests/test_b.py", "python", feat="g7")
    rc, out, _ = run(modpath, ["order"], u2 + "\n" + u1 + "\n")
    chk("order-unrelated-untouched", out == u2 + "\n" + u1 + "\n")
    # 13b (review fix 1) production item whose VERIFY runs the sibling test FILE (the usual shape, no python -c): production still goes first, whichever order is listed
    sp = item(2, "app/users.py", "Add inactive check to `get_current_user`", "pytest app/tests/test_users.py -q", "python", feat="g8")
    st = item(2, "app/tests/test_users.py", "Add `test_get_current_user_inactive` asserting an inactive user gets 403", "pytest app/tests/test_users.py -q", "test", feat="g8")
    for nm, inp in (("test-listed-first", [st, sp]), ("prod-listed-first", [sp, st])):
        rc, out, _ = run(modpath, ["order"], "\n".join(inp) + "\n")
        chk("order-sibling-verify-" + nm, [l for l in out.split("\n") if l] == [sp, st])
    sp2 = item(2, "app/users.py", "Add inactive check to `get_current_user`", "pytest app/tests/test_users.py::test_get_current_user_inactive -q", "python", feat="g8")
    rc, out, _ = run(modpath, ["order"], st + "\n" + sp2 + "\n")
    chk("order-sibling-verify-id-shape", [l for l in out.split("\n") if l] == [sp2, st])
    # 13c (review fix 2) enforce + parked prerequisite: one stuck_on_parked_prereq escalation row per item per day (repeat runs merge), none in shadow/release
    elog = os.path.join(TMP, "esc.log")
    for x in (elog, elog + ".lock"):
        if os.path.exists(x): os.remove(x)
    for _ in range(2):
        run(modpath, ["item-filter", "--progress", park_prog, "--mode", "enforce", "--log", elog, "--repo", "r"], "\n".join(TESTS) + "\n")
    rows = [json.loads(l) for l in open(elog)] if os.path.exists(elog) else []
    esc = [r for r in rows if r.get("event") == "stuck_on_parked_prereq"]
    chk("parked-escalation-emitted-per-item", len(esc) == len(TESTS) and all(r.get("count") == 2 for r in esc))
    chk("parked-escalation-still-journals-deferred", any(r.get("event") == "deferred_item" for r in rows))
    for x in (elog, elog + ".lock"):
        if os.path.exists(x): os.remove(x)
    run(modpath, ["item-filter", "--progress", park_prog, "--mode", "shadow", "--log", elog], "\n".join(TESTS) + "\n")
    run(modpath, ["item-filter", "--progress", park_prog, "--mode", "enforce", "--log", elog], "\n".join(TESTS) + "\n", {"OVN_ITEM_DEPS_PARKED": "release"})
    rows = [json.loads(l) for l in open(elog)] if os.path.exists(elog) else []
    chk("parked-escalation-none-in-shadow-or-release", not [r for r in rows if r.get("event") == "stuck_on_parked_prereq"])
    # 14 real-fixture: stage_order alone does NOT see the dependency (documents the gap this closes)
    return bad


def mutants(src):
    M = {
        "no-name-contains": ('kind = "name_contains"', 'kind = ""'),
        "shadow-filters": ('if mode == "enforce" and not release:\n                continue', 'if not release:\n                continue'),
        "enforce-never-drops": ('if mode == "enforce" and not release:\n                continue', 'if False:\n                continue'),
        "done-ignored": ('if a is b or a["it"]["done"] or a["removal"]:', 'if a is b or a["removal"]:'),
        "parked-always-released": ('release = mode == "enforce" and d.get("stuck_parked") and parked_mode == "release"', 'release = mode == "enforce" and d.get("stuck_parked")'),
        "no-dedupe": ('if r.get("decision_id") == rec["decision_id"]:', 'if False:'),
        "verify-edge-kept": ('if k in ("verify_ref", "verify_file") and by_id[a]["test_only"] and not by_id[b]["test_only"]:', 'if False:'),
        "no-prod-wins": ('edges = _acyclic(_prod_wins(edges, nodes))', 'edges = _acyclic(edges)'),
        "no-escalation": ('if d["blocked"] and d.get("stuck_parked") and a.log and mode == "enforce" and parked_mode != "release":', 'if False:'),
        "escalation-in-release": ('and mode == "enforce" and parked_mode != "release":', 'and mode == "enforce":'),
        "escalation-no-day-merge": ('merge_s=86400)', 'merge_s=None)'),
        "order-noop": ("order = so.topo(nodes, edges)", "order = [n['id'] for n in nodes]"),
        "prod-waits-too": ('if b["test_only"] and not a["test_only"]:', 'if not a["test_only"]:'),
        "default-enforce": ('os.environ.get("OVN_ITEM_DEPS", "shadow")', 'os.environ.get("OVN_ITEM_DEPS", "enforce")'),
        "failopen-removed": ('        sys.stdout.write("\\n".join(lines))\n        return 0\n    parked_mode', '        raise\n    parked_mode'),
    }
    out = {}
    for name, (old, new) in M.items():
        if src.count(old) < 1:
            out[name] = None
            continue
        out[name] = src.replace(old, new, 1)
    return out


def main():
    print("== real module")
    bad = core(MOD)
    ok("contract: all checks pass on the real module", not bad, bad)
    src = open(MOD).read()
    print("== mutants (each must break at least one check)")
    mdir = os.path.join(TMP, "mut"); os.makedirs(mdir, exist_ok=True)
    for name, code in mutants(src).items():
        if code is None:
            ok("mutant anchor present: " + name, False); continue
        mp = os.path.join(mdir, "ovn_item_deps.py")
        open(mp, "w").write(code)
        # the mutant imports ovn_stage_order from its own dir: copy it next to it
        so_src = open(os.path.join(ROOT, "scripts", "ovn_stage_order.py")).read()
        open(os.path.join(mdir, "ovn_stage_order.py"), "w").write(so_src)
        b2 = core(mp)
        ok("mutant caught: " + name, bool(b2), "survived")
    print("== gap documented: ovn_stage_order alone lets all 4 test lines through on the real group")
    so_py = os.path.join(ROOT, "scripts", "ovn_stage_order.py")
    prog = os.path.join(TMP, "p.md")
    rc, out, _ = run(so_py, ["item-filter", "--progress", prog, "--mode", "enforce"], "\n".join(OPEN) + "\n")
    ok("stage_order alone keeps all 5 lines (the gap)", len([l for l in out.split("\n") if l]) == 5)
    print("\npassed %d failed %d" % (P, F))
    return 1 if F else 0


sys.exit(main())
