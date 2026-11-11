#!/usr/bin/env python3
"""Q2 VERIFY lint (ovn_verify_lint.py, shadow only): behaviour per rule, shadow logging policy, hook wiring, and source mutants (each mutant must make run_checks fail)."""
import importlib.util
import json
import os
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "ovn_verify_lint.py")


def load(path, name="ovl"):
    sp = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def w(p, txt=""):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(txt)


def run_checks(m):
    fails = []

    def chk(name, cond):
        if not cond:
            fails.append(name)
    with tempfile.TemporaryDirectory() as td:
        repo = os.path.join(td, "xrepo")
        st = os.path.join(td, "state")
        w(os.path.join(repo, "scripts/battle.gd"), "func f():\n\tif foo_ready:\n\t\treturn 0\n\tif other: return 1\n")
        w(os.path.join(repo, "billwatch-web/src/a.test.ts"), "x")
        w(os.path.join(repo, "backend/tests/test_x.py"), "def test_one():\n    pass\nclass TestK:\n    def test_two(self):\n        pass\n")
        w(os.path.join(repo, "web/src/m.ts"), "x")
        w(os.path.join(repo, "tests/test_dup.py"), "def test_d():\n    pass\n")
        w(os.path.join(repo, "backend/tests/test_dup.py"), "def test_d():\n    pass\n")
        w(os.path.join(st, "tsc_baseline/xrepo__web.count"), "11\n")
        w(os.path.join(st, "tsc_baseline/xrepo__clean.count"), "0\n")

        def L(item, state=None, sib=()):
            return m.lint_verify(item, repo, state, sib)

        def sus(r, rule):
            return r["verdict"] == "SUSPECT" and r["rule"] == rule
        # ML1
        r = L("- [ ] x VERIFY: `grep -q 'if foo_ready: return 0' scripts/battle.gd` (cat:shell)")
        chk("ml1_flags_oneline_body", sus(r, "ML1"))
        chk("ml1_suggests_A1", "-A1" in r["suggested_verify"])
        chk("ml1_neighbour_ok", L("- [ ] x VERIFY: `grep -q 'if foo_ready:' scripts/battle.gd`")["verdict"] == "OK")
        chk("ml1_real_oneliner_ok", L("- [ ] x VERIFY: `grep -q 'if other: return 1' scripts/battle.gd`")["verdict"] == "OK")
        chk("ml1_header_absent_ok", L("- [ ] x VERIFY: `grep -q 'if nothere: return 0' scripts/battle.gd`")["verdict"] == "OK")
        chk("ml1_multiline_P_ok", L("- [ ] x VERIFY: `grep -Pzo 'if foo_ready:\\n\\s*return 0' scripts/battle.gd`")["verdict"] == "OK")
        chk("ml1_literal_backslash_n", sus(L("- [ ] x VERIFY: `grep -q 'if foo_ready:\\n\\t\\treturn 0' scripts/battle.gd`"), "ML1"))
        # TP1
        r = L("- [ ] x VERIFY: `npx vitest run src/a.test.ts` (cat:test)")
        chk("tp1_flags_subdir", sus(r, "TP1") and r["suggested_verify"].startswith("cd billwatch-web && "))
        chk("tp1_cd_ok", L("- [ ] x VERIFY: `cd billwatch-web && npx vitest run src/a.test.ts`")["verdict"] == "OK")
        chk("tp1_pytest_subdir", sus(L("- [ ] x VERIFY: `pytest tests/test_x.py -q`"), "TP1"))
        chk("tp1_root_path_ok", L("- [ ] x VERIFY: `pytest backend/tests/test_x.py -q`")["verdict"] == "OK")
        chk("tp1_nowhere_ok", L("- [ ] x VERIFY: `pytest tests/test_nowhere.py -q`")["verdict"] == "OK")
        chk("tp1_exists_at_root_and_sub_ok", L("- [ ] x VERIFY: `pytest tests/test_dup.py -q`")["verdict"] == "OK")
        chk("tp1_wrong_cd_silent", L("- [ ] x VERIFY: `cd web && pytest tests/test_x.py -q`")["verdict"] == "OK")
        chk("ml1_P_without_z_ok", L("- [ ] x VERIFY: `grep -qP 'if foo_ready: return 0' scripts/battle.gd`")["verdict"] == "OK")
        # TS1
        r = L("- [ ] x VERIFY: `cd web && npx vue-tsc --noEmit` (cat:ts)", state=st)
        chk("ts1_flags", sus(r, "TS1") and "11" in r["reason"])
        chk("ts1_no_state_silent", L("- [ ] x VERIFY: `cd web && npx vue-tsc --noEmit`")["verdict"] == "OK")
        chk("ts1_zero_baseline_ok", L("- [ ] x VERIFY: `cd clean && npx tsc --noEmit`", state=st)["verdict"] == "OK")
        chk("ts1_named_file_ok", L("- [ ] x VERIFY: `cd web && npx tsc --noEmit src/m.ts`", state=st)["verdict"] == "OK")
        chk("ts1_no_noemit_ok", L("- [ ] x VERIFY: `cd web && npx tsc --version`", state=st)["verdict"] == "OK")
        # PN1
        chk("pn1_flags", sus(L("- [ ] fix thing VERIFY: `cd backend && pytest tests/test_x.py::test_missing -q`"), "PN1"))
        chk("pn1_present_ok", L("- [ ] fix thing VERIFY: `cd backend && pytest tests/test_x.py::test_one -q`")["verdict"] == "OK")
        chk("pn1_class_method_ok", L("- [ ] fix VERIFY: `cd backend && pytest tests/test_x.py::TestK::test_two -q`")["verdict"] == "OK")
        chk("pn1_create_word_ok", L("- [ ] Add test_missing asserting y VERIFY: `cd backend && pytest tests/test_x.py::test_missing -q`")["verdict"] == "OK")
        item = "- [ ] fix thing VERIFY: `cd backend && pytest tests/test_x.py::test_missing -q`"
        chk("pn1_sibling_creates_ok", L(item, sib=[item, "- [ ] backend/tests/test_x.py - Add `test_missing` asserting z VERIFY: `x`"])["verdict"] == "OK")
        chk("pn1_sibling_nocreate_still_flags", sus(L(item, sib=[item, "- [ ] unrelated mentions test_missing only VERIFY: `x`"]), "PN1"))
        # misc
        chk("no_verify_ok", L("- [ ] nothing here")["verdict"] == "OK")
        chk("result_shape", set(L("- [ ] x")) == {"verdict", "reason", "suggested_verify", "rule"})
        # shadow logging policy
        log = os.path.join(td, "out.jsonl")
        os.environ["OVN_VERIFY_LINT_LOG"] = log
        prog = os.path.join(td, "P.md")
        bad = "- [ ] x VERIFY: `grep -q 'if foo_ready: return 0' scripts/battle.gd` (cat:shell)\n"
        w(prog, bad + "- [ ] fine VERIFY: `true`\n")
        before = open(prog).read()
        sd2 = os.path.join(td, "s2")
        for mode_env, expect in (("shadow", 1), ("enforce", 1), ("off", 0)):
            os.environ["OVN_VERIFY_LINT"] = mode_env
            for f in (log, os.path.join(sd2, "verify_lint.seen")):
                if os.path.exists(f):
                    os.remove(f)
            for _ in range(2):   # second pass is deduped
                m.main(["x", "shadow", prog, "--repo-root", repo, "--repo", "xrepo", "--state", sd2])
            n = len(open(log).read().splitlines()) if os.path.exists(log) else 0
            chk("shadow_rows_%s_%d" % (mode_env, expect), n == expect)
        chk("shadow_never_edits_items", open(prog).read() == before)
        os.environ["OVN_VERIFY_LINT"] = "shadow"
        if os.path.exists(log):
            os.remove(log)
        m.main(["x", "shadow", prog, "--repo-root", repo, "--repo", "xrepo", "--state", os.path.join(td, "s3")])
        try:
            row = json.loads(open(log).read().splitlines()[0])
        except Exception:
            row = {}
        chk("row_fields", row.get("rule") == "ML1" and row.get("repo") == "xrepo" and row.get("src") == "planner" and bool(row.get("suggested_verify")))
        del os.environ["OVN_VERIFY_LINT_LOG"]
        os.environ["OVN_VERIFY_LINT"] = "enforce"
        chk("enforce_is_shadow", m.mode() == "shadow")
        os.environ["OVN_VERIFY_LINT"] = "off"
        chk("off_is_off", m.mode() == "off")
        os.environ.pop("OVN_VERIFY_LINT", None)
        chk("default_shadow", m.mode() == "shadow")
    return fails


def hook_checks():
    f = []
    ro = open(os.path.join(ROOT, "run_overnight.sh")).read()
    ig = open(os.path.join(ROOT, "scripts/ovn_item_guard.sh")).read()
    ra = open(os.path.join(ROOT, "scripts/test/run_all.sh")).read()
    if "ovn_verify_lint.py\" shadow" not in ro or ro.index("ovn_verify_lint.py\" shadow") < ro.index("ovn_retire_vague.py"):
        f.append("hook_run_overnight_after_retire_vague")
    if "Q2 VERIFY lint" not in ig or ig.index("Q2 VERIFY lint") > ig.index("AUTO-SKIP after ${_rn} credit refusals"):
        f.append("hook_item_guard_before_auto_skip")
    if "test_q2_verify_lint.sh" not in ra:
        f.append("registered_in_run_all")
    return f


MUTANTS = [
    ('if _count(full, files) == 0 and _count(neigh, files) > 0:', 'if _count(full, files) == 0:'),
    ('if "z" in flags or "P" in flags', 'if "z" in flags'),
    ('if os.path.exists(os.path.join(_root(repo_root, base), rel)):\n                continue', 'if False:\n                continue'),
    ('subs = _find_sub(repo_root, rel) if not base else []', 'subs = _find_sub(repo_root, rel)'),
    ('if bl and bl[1] > 0:', 'if bl:'),
    ('continue                        # specific files named: not the full project', 'pass'),
    ('if _CREATE_WORDS.search(item.split("VERIFY:")[0]):\n        return None', 'if False:\n        return None'),
    ('if any(n in sb and _CREATE_WORDS', 'if any(False and _CREATE_WORDS'),
    ('return "off" if m == "off" else "shadow"', 'return "shadow"'),
    ('if key in old:\n            return res', 'if False:\n            return res'),
    ('return "off" if m == "off" else "shadow"', 'return m'),
]


def main():
    fails = run_checks(load(SRC)) + hook_checks()
    for f in fails:
        print("FAIL", f)
    src = open(SRC).read()
    survived = 0
    for i, (old, new) in enumerate(MUTANTS):
        if old not in src:
            print("MUTANT %d: pattern not found (stale mutant)" % i)
            fails.append("stale_mutant_%d" % i)
            continue
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "mut.py")
            open(p, "w").write(src.replace(old, new, 1))
            try:
                mf = run_checks(load(p, "mut%d" % i))
            except Exception as e:
                mf = ["exception:%s" % e]
        if not mf:
            survived += 1
            print("MUTANT %d SURVIVED: %s" % (i, old[:60]))
            fails.append("mutant_%d_survived" % i)
    print("q2 verify lint: %d failure(s), %d of %d mutants survived" % (len(fails), survived, len(MUTANTS)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
