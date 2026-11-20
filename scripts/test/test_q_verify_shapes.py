#!/usr/bin/env python3
"""q-verify-shapes (2026-11-18): the SHADOW VERIFY-shape rules of ovn_verify_lint.py (BACKEND_IMPORT_ROOT ROUTES_PATH_ATTR K_FILTER_ZERO_TESTS COLLECT_ONLY_GREP_HELPER ONE_LINER_MISSING_IMPORT
NODEID_WRONG_FILE TEST_NAME_DOES_NOT_EXIST DIRTY_PATH), shadow logging, the OVN_VERIFY_LINT_PARK function (park_cycle) and ovn_item_hazards.py (DELETE_ALL_TESTS). Every behaviour is also run against
a source MUTANT (one piece of logic broken); each mutant must make run_checks fail."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VL = os.path.join(ROOT, "ovn_verify_lint.py")
HZ = os.path.join(ROOT, "ovn_item_hazards.py")


def load(path, name):
    sp = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def w(p, txt=""):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(txt)


def run_checks(vl, hz):
    fails = []

    def chk(name, cond):
        if not cond:
            fails.append(name)
    with tempfile.TemporaryDirectory() as td:
        repo = os.path.join(td, "xrepo")
        st = os.path.join(td, "state")
        os.environ.pop("OVN_VERIFY_LINT", None)
        os.environ.pop("OVN_VERIFY_LINT_PARK_RULES", None)
        w(os.path.join(repo, "backend/app/__init__.py"))
        w(os.path.join(repo, "backend/app/main.py"), "app = None\n")
        w(os.path.join(repo, "backend/requirements.txt"), "fastapi>=0.115.0\nuvicorn\n")
        w(os.path.join(repo, "backend/tests/test_x.py"), "import pytest\n\ndef test_one():\n    pass\n\nclass TestK:\n    def test_two(self):\n        pass\n\n@pytest.mark.slow\ndef test_slow_case():\n    pass\n")
        w(os.path.join(repo, "backend/tests/test_marked.py"), "import pytest\n\n@pytest.mark.zebra\ndef test_marked():\n    pass\n")
        w(os.path.join(repo, "backend/tests/test_m.py"), "import pytest\n\npytestmark = pytest.mark.apple\n\ndef test_m1():\n    pass\n")
        w(os.path.join(repo, "pinned143/app/main.py"), "app = None\n")
        w(os.path.join(repo, "pinned143/requirements.txt"), "fastapi==0.143.3\n")
        w(os.path.join(repo, "backend/tests/test_p.py"), "import pytest\n\n@pytest.mark.parametrize('env', ['prod', 'dev'])\ndef test_env(env):\n    pass\n")
        w(os.path.join(repo, "pinned/app/main.py"), "app = None\n")
        w(os.path.join(repo, "pinned/requirements.txt"), "fastapi==0.115.0\n")
        w(os.path.join(repo, "pinned/tests/test_x.py"), "def test_one():\n    pass\n")
        w(os.path.join(repo, "pinned/pytest.ini"), "[pytest]\npython_files = test_*.py\npython_classes = Test*\npython_functions = test_*\n")
        w(os.path.join(repo, "custom/app/main.py"), "x=1\n")
        w(os.path.join(repo, "custom/pytest.ini"), "[pytest]\npython_files = *_check.py\n")
        w(os.path.join(repo, "custom/tests/test_x.py"), "def test_one():\n    pass\n")
        w(os.path.join(repo, "tests/test_root.py"), "def test_r():\n    pass\n")
        w(os.path.join(repo, "tools/helper.py"), "X = 1\n")
        w(os.path.join(repo, "web/src/a.test.ts"), "describe('suite', () => {\n  it('renders labels', () => {})\n  test('clicks', () => {})\n})\n")
        w(os.path.join(repo, "web/src/each.test.ts"), "it('plain', () => {})\nit.each([1,2])('case %s', () => {})\n")
        SRC = "- [ ] [T1] backend/app/main.py - Add the thing. "          # lead target = a SOURCE file: the item cannot create tests
        TST = "- [ ] [T1] backend/tests/test_x.py - Add a test for the thing. "   # lead target = a test file

        def v(item, clause=None, tail=""):
            line = item + ("VERIFY: `%s`%s" % (clause, tail) if clause else "")
            rs = vl.lint_all(line, repo, st)
            return rs[0] if rs else vl.lint_verify(line, repo, st)

        def rule(item, clause):
            return v(item, clause)["rule"]
        # ---- a BACKEND_IMPORT_ROOT
        chk("a_flag", rule(SRC, 'cd backend && python3 -c "from backend.app.main import app; print(1)"') == "BACKEND_IMPORT_ROOT")
        chk("a_flag_import_form", rule(SRC, 'cd backend && python -c "import backend.app.main"') == "BACKEND_IMPORT_ROOT")
        chk("a_ok_app", rule(SRC, 'cd backend && python3 -c "from app.main import app; print(1)"') == "")
        chk("a_ok_pythonpath", rule(SRC, 'cd backend && PYTHONPATH=.. python3 -c "from backend.app.main import app"') == "")
        chk("a_ok_syspath", rule(SRC, "cd backend && python3 -c \"import sys; sys.path.insert(0, '..'); from backend.app.main import app\"") == "")
        w(os.path.join(repo, "backend/backend/__init__.py"))
        chk("a_ok_when_pkg_exists", rule(SRC, 'cd backend && python3 -c "from backend.app.main import app"') == "")
        os.remove(os.path.join(repo, "backend/backend/__init__.py"))
        os.rmdir(os.path.join(repo, "backend/backend"))
        chk("a_ok_no_cd", rule(SRC, 'python3 -c "from backend.app.main import app"') == "")
        chk("a_ok_no_app_dir", rule(SRC, 'cd web && python3 -c "from web.app.main import app"') == "")
        chk("a_hyphen_dir", (lambda: (w(os.path.join(repo, "billwatch-backend/app/x.py")), rule(SRC, 'cd billwatch-backend && python -c "from billwatch_backend.app.x import y"'))[1])() == "BACKEND_IMPORT_ROOT")
        # ---- b ROUTES_PATH_ATTR
        rp = 'cd backend && python3 -c "from app.main import app; paths = [r.path for r in app.routes]; assert \'/x\' in paths"'
        chk("b_flag_floating", rule(SRC, rp) == "ROUTES_PATH_ATTR")
        chk("b_flag_dependency", rule(SRC, 'cd backend && python3 -c "from app.main import app; print([d.dependant for d in app.routes])"') == "ROUTES_PATH_ATTR")
        chk("b_ok_pinned_old", rule(SRC, rp.replace("cd backend", "cd pinned")) == "")
        chk("b_ok_openapi", rule(SRC, 'cd backend && python3 -c "from app.main import app; assert \'/x\' in app.openapi()[\'paths\']"') == "")
        chk("b_ok_router_routes", rule(SRC, 'cd backend && python3 -c "from app.routers.r import router; print([r.path for r in router.routes])"') == "")
        chk("b_ok_os_path", rule(SRC, 'cd backend && python3 -c "import os; from app.main import app; print(os.path.join(\'a\'), len(app.routes))"') == "")
        w(os.path.join(repo, "backend/.venv/lib/python3.12/site-packages/fastapi-0.115.0.dist-info/METADATA"))
        chk("b_venv_version_wins", rule(SRC, rp) == "")
        import shutil
        shutil.rmtree(os.path.join(repo, "backend/.venv"))
        # ---- c K_FILTER_ZERO_TESTS / f TEST_NAME_DOES_NOT_EXIST (-k)
        chk("c_flag_prod", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k prod") == "K_FILTER_ZERO_TESTS")
        chk("c_ok_matching", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k one") == "")
        chk("c_ok_or", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k 'prod or two'") == "")
        chk("c_flag_and", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k 'one and two'") == "K_FILTER_ZERO_TESTS")
        chk("c_ok_not", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k 'not one'") == "")
        chk("c_flag_not_all", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k 'not test'") == "K_FILTER_ZERO_TESTS")
        chk("c_ok_class_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k TestK") == "")
        chk("c_ok_module_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k test_x") == "")
        chk("c_ok_mark_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k slow") == "")
        chk("c_ok_parametrize_text", rule(SRC, "cd backend && python3 -m pytest tests/test_p.py -q -k prod") == "")
        chk("c_ok_custom_conf", rule(SRC, "cd custom && python3 -m pytest tests -q -k prod") == "")
        chk("c_ok_case_insensitive", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k TWO") == "")
        chk("c_node_id_fixed_selection", rule(TST, "cd backend && python3 -m pytest tests/test_x.py::test_one -q -k prod") == "K_FILTER_ZERO_TESTS")
        chk("c_node_id_ok_when_matching", rule(TST, "cd backend && python3 -m pytest tests/test_x.py::test_one -q -k one") == "")
        chk("c_test_writer_item_excused", rule(TST, "cd backend && python3 -m pytest tests/test_x.py -q -k prod") == "")
        chk("c_ok_bad_expr_not_modelled", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k 'a=b'") == "")
        chk("c_dir_target", rule(SRC, "cd backend && python3 -m pytest tests -q -k nonesuch") == "K_FILTER_ZERO_TESTS")
        chk("c_ok_collect_only_not_k_rule", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q -k prod") == "")
        chk("f_k_single_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k test_missing_name") == "TEST_NAME_DOES_NOT_EXIST")
        chk("f_k_single_name_ok_when_defined", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k test_one") == "")
        chk("f_k_single_name_writer_ok", rule(TST, "cd backend && python3 -m pytest tests/test_x.py -q -k test_missing_name") == "")
        chk("f_k_single_name_phrase_writer_ok", rule("- [ ] [T2] log the swallowed error and add a test asserting the record. ", "cd backend && python3 -m pytest tests -q -k test_logged_record") == "")
        # ---- d COLLECT_ONLY_GREP_HELPER
        chk("d_flag", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep _mk") == "COLLECT_ONLY_GREP_HELPER")
        chk("d_flag_helper_even_in_test_writer", rule(TST, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep _mk") == "COLLECT_ONLY_GREP_HELPER")
        chk("d_ok_test_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep test_two") == "")
        chk("d_ok_class", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep TestK") == "")
        chk("d_ok_and_not_pipe", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q && grep _mk tests/test_x.py") == "")
        chk("d_ok_grep_v_c", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep -c _mk") == "")
        chk("d_ok_writer_plain_word", rule(TST, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q | grep retry") == "")
        chk("d_ok_without_collect_only", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q | grep _mk") == "")
        # ---- e ONE_LINER_MISSING_IMPORT
        chk("e_flag", rule(SRC, 'python3 -c "from app.services.m import metrics; assert isinstance(metrics, MetricsRegistry)"') == "ONE_LINER_MISSING_IMPORT")
        chk("e_flag_logging", rule(SRC, "python3 -c \"r = logging.LogRecord('a', 20, '', 0, 'm', None, None)\"") == "ONE_LINER_MISSING_IMPORT")
        chk("e_ok_imported", rule(SRC, 'python3 -c "import logging; r = logging.getLogger()"') == "")
        chk("e_ok_short_circuit", rule(SRC, 'python3 -c "import os; assert 1 or Path(os.sep)"') == "")
        chk("e_ok_short_circuit_isinstance", rule(SRC, "python3 -c \"import os; x = 'Path' in 'Path(1)' or isinstance(os, Path)\"") == "")
        chk("e_ok_comprehension_and_lambda", rule(SRC, 'python3 -c "x = [i for i in range(3)]; f = lambda a: a + 1; print(x, f(1))"') == "")
        chk("e_ok_star_import", rule(SRC, 'python3 -c "from os.path import *; print(join(1))"') == "")
        chk("e_ok_syntax_error_other_rule", rule(SRC, 'python3 -c "from m import X; try: X(); except ValueError: pass"') == "")
        chk("e_ok_builtins", rule(SRC, 'python3 -c "print(len([1]), isinstance(1, int), __name__)"') == "")
        chk("e_ok_def_and_class", rule(SRC, 'python3 -c "def f():\\n  return 1\\nprint(f())"') == "" and rule(SRC, "python3 -c \"class A: pass\nprint(A())\"") == "")
        chk("e_flag_in_function_body_called", rule(SRC, 'python3 -c "import inspect; print(inspect.getsource(app.services.x))"') == "ONE_LINER_MISSING_IMPORT")
        # ---- f NODEID_WRONG_FILE
        chk("f_flag_missing_file", rule(SRC, "cd backend && python3 -m pytest tests/test_nope.py::test_a -q") == "NODEID_WRONG_FILE")
        chk("f_flag_missing_plain", rule(SRC, "cd backend && python3 -m pytest tests/test_nope.py -q") == "NODEID_WRONG_FILE")
        chk("f_ok_file_exists", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py::test_one -q") == "")
        chk("f_ok_item_is_test_writer", rule(TST.replace("test_x.py", "test_nope.py"), "cd backend && python3 -m pytest tests/test_nope.py -q") == "")
        chk("f_ok_item_names_file", rule("- [ ] [T1] backend/app/main.py - see tests/test_nope.py and cover it. ", "cd backend && python3 -m pytest tests/test_nope.py -q") == "")
        chk("f_wrong_cwd_flagged", rule(SRC, "cd backend && python3 -m pytest tests/test_root.py -q") == "NODEID_WRONG_FILE")
        chk("f_ok_sibling_creates", (vl.lint_all(SRC + "VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q`", repo, st, ["- [ ] [T1] backend/tests/test_nope.py - Create the test file. VERIFY: `true`"]) or [{"rule": ""}])[0]["rule"] == "")
        for nm, tgt in (("star", "tests/test_*.py"), ("brace", "tests/test_{a,b}.py"), ("var", "$T/test_a.py"), ("home", "~/x/test_a.py"), ("qmark", "tests/test_?.py"), ("class", "tests/test_[ab].py")):
            chk("f_unexpanded_%s_skipped" % nm, rule(SRC, "cd backend && python3 -m pytest %s -q" % tgt) == "")
        chk("f_unexpanded_tick_skipped", vl.rule_nodeid_file(SRC, "cd backend && python3 -m pytest tests/test_`x`.py -q", repo) is None and vl.rule_nodeid_file(SRC, "cd backend && python3 -m pytest tests/test_nope.py -q", repo) is not None)
        chk("f_unexpanded_with_nodeid_skipped", rule(SRC, "cd backend && python3 -m pytest tests/test_*.py::test_a -q") == "")
        chk("f_param_id_still_flagged", rule(SRC, "cd backend && python3 -m pytest 'tests/test_nope.py::test_a[1]' -q") == "NODEID_WRONG_FILE")
        chk("f_staged_sibling_create_test_file_ok", (vl.lint_all(SRC + "VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q`", repo, st, ["- [ ] [T1] Step 1/2: Create test file for the retry helper. VERIFY: `true`"]) or [{"rule": ""}])[0]["rule"] == "")
        chk("f_staged_sibling_without_create_flagged", (vl.lint_all(SRC + "VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q`", repo, st, ["- [ ] [T1] Step 1/2: Review the test file layout. VERIFY: `true`"]) or [{"rule": ""}])[0]["rule"] == "NODEID_WRONG_FILE")
        chk("f_tp1_keeps_precedence", rule(SRC, "python3 -m pytest tests/test_x.py -q") == "TP1")
        chk("f_vitest_title_missing", rule(SRC, "cd web && npx vitest run src/a.test.ts -t 'nonexistent title'") == "TEST_NAME_DOES_NOT_EXIST")
        chk("f_vitest_title_present", rule(SRC, "cd web && npx vitest run src/a.test.ts -t 'renders labels'") == "")
        chk("f_vitest_describe_prefix", rule(SRC, "cd web && npx vitest run src/a.test.ts -t 'suite renders'") == "")
        chk("f_vitest_regex_alternation", rule(SRC, "cd web && npx vitest run src/a.test.ts -t 'clicks|zzz'") == "")
        chk("f_vitest_each_skipped", rule(SRC, "cd web && npx vitest run src/each.test.ts -t 'nope'") == "")
        chk("f_vitest_writer_item_ok", rule("- [ ] [T1] web/src/a.test.ts - Add test cases for labels. ", "cd web && npx vitest run src/a.test.ts -t 'nonexistent title'") == "")
        # ---- h DIRTY_PATH
        chk("h_flag_unittest_module", rule(SRC, "python3 -m unittest tools.test_nope.TestX.test_y -v") == "DIRTY_PATH")
        chk("h_flag_dash_m_module", rule(SRC, "python3 -m tools.test_nope") == "DIRTY_PATH")
        chk("h_ok_existing_module", rule(SRC, "python3 -m tools.helper") == "")
        chk("h_ok_attr_tail_of_module", rule(SRC, "python3 -m unittest tools.helper.Cls.test_y") == "")
        chk("h_flag_script", rule(SRC, "python3 tools/missing_script.py") == "DIRTY_PATH")
        chk("h_ok_script_exists", rule(SRC, "python3 tools/helper.py") == "")
        chk("h_ok_stdlib_and_tools", rule(SRC, "python3 -m json.tool x.json") == "" and rule(SRC, "python3 -m pytest tests -q") == "" and rule(SRC, "python3 -m venv .venv") == "")
        chk("h_ok_item_creates_module", rule("- [ ] [T1] Create tools/test_new.py with the helper. ", "python3 -m unittest tools.test_new.TestX") == "")
        chk("h_ok_unrelated_testlike_module_elsewhere", rule(SRC, "python3 -m somepkg.run") == "")
        chk("a_ok_no_cd_with_root_app", (lambda: (w(os.path.join(repo, "app/main.py")), rule(SRC, 'python3 -c "from nopkg.app.main import app"'), shutil.rmtree(os.path.join(repo, "app")))[1])() == "")
        chk("b_flag_pinned_143", rule(SRC, rp.replace("cd backend", "cd pinned143")) == "ROUTES_PATH_ATTR")
        chk("c_ok_dir_name", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py -q -k tests") == "")
        chk("c_ok_mark_decorator", rule(SRC, "cd backend && python3 -m pytest tests/test_marked.py -q -k zebra") == "")
        chk("c_ok_pytestmark_file", rule(SRC, "cd backend && python3 -m pytest tests/test_m.py -q -k apple") == "")
        chk("c_node_id_restricts_selection", rule(TST, "cd backend && python3 -m pytest tests/test_x.py::test_one -q -k two") == "K_FILTER_ZERO_TESTS")
        chk("c_conventional_conf_not_custom", rule(SRC, "cd pinned && python3 -m pytest tests -q -k prod") == "K_FILTER_ZERO_TESTS")
        chk("d_ok_and_sep_no_pipe", rule(SRC, "cd backend && python3 -m pytest tests/test_x.py --collect-only -q && grep -q _mk") == "")
        chk("d_ok_parametrize_text", rule(SRC, "cd backend && python3 -m pytest tests/test_p.py --collect-only -q | grep prod") == "")
        chk("f_tp1_subdir_not_double_reported", "NODEID_WRONG_FILE" not in [r["rule"] for r in vl.lint_all(SRC + "VERIFY: `python3 -m pytest tests/test_x.py -q`", repo, st)] and "TP1" in [r["rule"] for r in vl.lint_all(SRC + "VERIFY: `python3 -m pytest tests/test_x.py -q`", repo, st)])
        chk("f_ok_test_writer_other_missing_file", rule(TST, "cd backend && python3 -m pytest tests/test_zzz.py -q") == "")
        chk("f_vitest_each_with_plain_titles_skipped", rule(SRC, "cd web && npx vitest run src/each.test.ts -t 'case 1'") == "")
        chk("h_ok_std_first_component", rule(SRC, "python3 -m unittest os.test_thing") == "")
        chk("h_ok_item_names_script", rule("- [ ] [T1] tools/new_script.py - Create it. ", "python3 tools/new_script.py") == "")
        chk("first_is_q2_when_both_fire", vl.lint_verify(SRC + "VERIFY: `python3 -m pytest tests/test_x.py -q && python3 -c \"x = Foo()\"`", repo, st)["rule"] == "TP1")
        # ---- shared: precedence + all-rules + budget + never raises
        both = SRC + "VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q -k prod && python3 -c \"x = Foo()\"`"
        names = [r["rule"] for r in vl.lint_all(both, repo, st)]
        chk("all_rules_report_each", "NODEID_WRONG_FILE" in names and "ONE_LINER_MISSING_IMPORT" in names)
        chk("first_result_keeps_q2_precedence", vl.lint_verify("- [ ] [T1] a - b. VERIFY: `pytest backend/tests/test_x.py::test_zzz -q`", repo, st)["rule"] in ("TP1", "PN1"))
        chk("legacy_lint_verify_api_unchanged_for_new_shapes", all(vl.lint_verify(SRC + "VERIFY: `%s`" % c, repo, st)["verdict"] == "OK" for c in ("cd backend && python3 -m pytest tests/test_nope.py -q", 'python3 -c "x = Foo()"', "cd backend && python3 -m pytest tests/test_x.py -q -k prod")))
        chk("lint_all_is_list", isinstance(vl.lint_all(SRC + "VERIFY: `true`", repo, st), list))
        chk("never_raises_on_garbage", vl.lint_verify("- [ ] x VERIFY: `python3 -c \"'`", repo, st)["verdict"] in ("OK", "SUSPECT", "unknown"))
        chk("new_rules_listed", set(vl.NEW_RULES) == {"BACKEND_IMPORT_ROOT", "ROUTES_PATH_ATTR", "K_FILTER_ZERO_TESTS", "COLLECT_ONLY_GREP_HELPER", "ONE_LINER_MISSING_IMPORT", "NODEID_WRONG_FILE", "TEST_NAME_DOES_NOT_EXIST", "DIRTY_PATH"})
        chk("verdict_shape", set(v(SRC, "cd backend && python3 -m pytest tests/test_nope.py").keys()) == {"verdict", "reason", "suggested_verify", "rule"})
        # ---- shadow logging: one row per rule, deduped, off writes nothing, journal is the only effect
        log = os.path.join(td, "vl.jsonl")
        os.environ["OVN_VERIFY_LINT_LOG"] = log
        try:
            vl.shadow_log(both, repo, "xrepo", st, "test")
            vl.shadow_log(both, repo, "xrepo", st, "test")
            rows = [json.loads(x) for x in open(log)] if os.path.exists(log) else []
            chk("shadow_row_per_rule_deduped", sorted(r["rule"] for r in rows) == sorted(set(r["rule"] for r in rows)) and {"NODEID_WRONG_FILE", "ONE_LINER_MISSING_IMPORT"} <= {r["rule"] for r in rows})
            os.environ["OVN_VERIFY_LINT"] = "off"
            before = os.path.getsize(log)
            vl.shadow_log(both.replace("Foo", "Bar"), repo, "xrepo", st, "test")
            chk("shadow_off_writes_nothing", os.path.getsize(log) == before)
            os.environ["OVN_VERIFY_LINT"] = "enforce"
            chk("enforce_is_shadow", vl.mode() == "shadow")
        finally:
            os.environ.pop("OVN_VERIFY_LINT", None)
            os.environ.pop("OVN_VERIFY_LINT_LOG", None)
        # ---- park_cycle (OVN_VERIFY_LINT_PARK): default PARK_RULES, 2 bad picks, exact line, env override, never raises
        import hashlib
        item = SRC + "VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q`"
        body = item[len("- [ ] "):]
        lh = hashlib.md5(body.encode()).hexdigest()
        prog = os.path.join(td, "PROG.md")
        w(prog, "- [ ] [T0] other - first. VERIFY: `true`\n" + item + "\n")
        now = int(time.time())

        def jr(dt_min, cls, status, key="k1", line=lh):
            t = now - int(dt_min * 60)
            return json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)), "repo": "r", "class": cls, "status": status, "item_hash": key, "item_line_hash": line, "duration_s": 30}) + "\n"
        out = os.path.join(td, "out.jsonl")
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)") + jr(1, "landed-uncredited", "pushed(tests:pass)"))
        pc = vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)
        chk("park_two_picks_trips", pc["trip"] and pc["rule"] == "NODEID_WRONG_FILE" and pc["line_no"] == 2 and pc["count"] == 2)
        w(out, jr(1, "noop", "no-op(ALREADY-DONE)"))
        chk("park_one_pick_no", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)") + jr(1, "noop", "no-op(reverted-red)"))
        chk("park_default_kinds_exclude_reverted", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)") + jr(40, "landed", "pushed(tests:pass)") + jr(1, "noop", "no-op(ALREADY-DONE)"))
        chk("park_credited_landing_forgives", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)", line="deadbeef") + jr(1, "noop", "no-op(ALREADY-DONE)", line="deadbeef"))
        w(prog, "- [ ] [T0] other - first. VERIFY: `true`\n" + item)
        chk("park_unidentifiable_line_never_parks", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)") + jr(1, "noop", "no-op(ALREADY-DONE)"))
        w(prog, "- [ ] [T0] other. VERIFY: `true`\n- [ ] " + body.replace("test_nope", "test_x") + "\n")
        chk("park_no_verdict_no_park", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        w(prog, "- [ ] [T0] other - first. VERIFY: `true`\n" + item + "\n")
        os.environ["OVN_VERIFY_LINT_PARK_RULES"] = "ONE_LINER_MISSING_IMPORT"
        chk("park_rules_env_override_excludes", not vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"])
        os.environ["OVN_VERIFY_LINT_PARK_RULES"] = "bogus,TP1"
        chk("park_rules_env_unknown_names_dropped", vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["why"] == "no-park-rules")
        os.environ.pop("OVN_VERIFY_LINT_PARK_RULES", None)
        chk("park_default_rules_are_proven_ones", tuple(vl.PARK_RULES) == ("NODEID_WRONG_FILE",))
        w(out, "garbage\n{not json\n")
        chk("park_garbage_outcomes_never_raise", vl.park_cycle(out, "r", prog, repo, st, now, 2, 48)["trip"] is False)
        chk("park_missing_files_never_raise", vl.park_cycle("/nonexistent/o", "r", "/nonexistent/p", repo, st, now)["trip"] is False)
        w(out, jr(50, "noop", "no-op(ALREADY-DONE)") + jr(1, "noop", "no-op(ALREADY-DONE)"))
        r_ = subprocess.run([sys.executable, vl.__file__, "park-cycle", "--outcomes", out, "--repo", "r", "--prog", prog, "--repo-root", repo, "--state", st, "--now", str(now)], capture_output=True, text=True)
        chk("park_cli_tsv", r_.stdout.strip().split("\t")[:4] == ["1", "2", "NODEID_WRONG_FILE", "2"])
        # ---- replay --trees CLI
        pf = os.path.join(td, "rp", "xrepo", "OVERNIGHT_PROGRESS.md")
        w(pf, item + "\n")
        r_ = subprocess.run([sys.executable, vl.__file__, "replay", pf, "--trees", td], capture_output=True, text=True)
        chk("replay_trees", r_.returncode == 0 and "NODEID_WRONG_FILE" in r_.stdout.split("\n")[0])
        # ---- item hazards
        H = hz.detect
        chk("hz_replace_all_billwatch", (H("- [ ] [T1] billwatch-backend/tests/test_auth_refresh_success.py — Replace entire file content with only the `_mk` fixture definition and a single trivial test function `test_mk_helper_works`, removing all other imports and tests. VERIFY: `true`") or ("", ""))[0] == "REPLACE_ALL")
        chk("hz_replace_file_content_with", (H("- [ ] [T1] tests/test_a.py — Replace the file content with a minimal version containing only the helper. VERIFY: `true`") or ("",))[0] == "REPLACE_ALL")
        chk("hz_remove_all_existing", (H("- [ ] [T1] backend/tests/test_a.py — Remove all existing tests from the file and add one smoke test. VERIFY: `true`") or ("",))[0] == "REMOVE_ALL")
        chk("hz_delete_all_tests_phrase", (H("- [ ] [T1] backend/tests/test_a.py — Delete all the other tests, keep the first. VERIFY: `true`") or ("",))[0] == "REMOVE_ALL")
        chk("hz_delete_file_unjustified", (H("- [ ] [T1] backend/tests/test_a.py — Delete the entire test file. VERIFY: `test ! -f backend/tests/test_a.py`") or ("",))[0] == "DELETE_FILE")
        chk("hz_delete_file_justified_ok", H("- [ ] [T1] backend/tests/test_a.py — Delete the entire test file for the removed `X` service. VERIFY: `true`") is None)
        chk("hz_delete_file_orphan_ok", H("- [ ] [T1] backend/tests/test_delivery.py — Delete the entire file as all tests target removed dead code. VERIFY: `true`") is None)
        chk("hz_scoped_removal_ok", H("- [ ] [T1] backend/tests/test_d.py — Remove all test cases and assertions that call `commit_task_to_git` or `dispatch_flow`. VERIFY: `true`") is None)
        chk("hz_scoped_removal_referencing_ok", H("- [ ] [T1] backend/tests/test_f.py — Remove all test cases and imports referencing `filter_monitors`, keeping only tests for X. VERIFY: `true`") is None)
        chk("hz_deleted_functions_scope_ok", H("- [ ] [T1] iptv-backend/tests/test_d.py — Create new test file containing only the valid assertions, removing all tests for deleted functions. VERIFY: `true`") is None)
        chk("hz_source_file_not_a_test", H("- [ ] [T1] backend/app/x.py — Replace the entire file content with a new implementation. VERIFY: `true`") is None)
        chk("hz_gut_substring_not_replace", H("- [ ] [T1] tests/test_a.gd — the parse error GUT swallows by skipping the whole file. VERIFY: `true`") is None)
        chk("hz_verify_text_ignored", H("- [ ] [T1] tests/test_a.py — Add a test. VERIFY: `grep -c 'replace the entire file' tests/test_a.py`") is None)
        chk("hz_tags_ignored", H("- [ ] [AUTO-SKIP after 4 no-op cycles — replace the entire file, remove all tests] [T1] tests/test_a.py — Add a test. VERIFY: `true`") is None)
        chk("hz_never_raises", H(None) is None and H("") is None)
        hp = os.path.join(td, "hz", "xrepo", "OVERNIGHT_PROGRESS.md")
        hl = "- [ ] [T1] backend/tests/test_a.py — Replace the entire file content with a trivial test. VERIFY: `true`"
        parked = "- [ ] [AUTO-SKIP after 4 no-op cycles — x] [T1] backend/tests/test_b.py — Replace the entire file content with a trivial test. VERIFY: `true`"
        safe = "- [ ] [T1] backend/app/ok.py — Add the helper. VERIFY: `true`"
        w(hp, "# Progress\n" + hl + "\n" + parked + "\n" + safe + "\n- [x] done one\n")
        hlog = os.path.join(td, "hz.log")
        os.environ["OVN_ITEM_HAZARD_LOG"] = hlog
        try:
            orig = open(hp).read()
            os.environ.pop("OVN_ITEM_HAZARD", None)
            chk("hz_default_mode_shadow", hz.mode() == "shadow")
            n = hz.scan(hp, "xrepo", os.path.join(td, "hzst"))
            chk("hz_shadow_logs_not_edits", n == 0 and open(hp).read() == orig)
            lg = open(hlog).read() if os.path.exists(hlog) else ""
            chk("hz_shadow_row_text", "would-refuse delete-all-tests" in lg and lg.count("would-refuse") == 2 and "parked=1" in lg and "parked=0" in lg and "kind=REPLACE_ALL" in lg)
            hz.scan(hp, "xrepo", os.path.join(td, "hzst"))
            chk("hz_shadow_deduped", open(hlog).read().count("would-refuse") == 2)
            os.environ["OVN_ITEM_HAZARD"] = "bogus"
            chk("hz_unknown_mode_is_shadow", hz.mode() == "shadow")
            os.environ["OVN_ITEM_HAZARD"] = "off"
            os.remove(hlog)
            os.remove(os.path.join(td, "hzst", "item_hazards.seen"))
            hz.scan(hp, "xrepo", os.path.join(td, "hzst"))
            chk("hz_off_writes_nothing", not os.path.exists(hlog) and open(hp).read() == orig)
            os.environ["OVN_ITEM_HAZARD"] = "enforce"
            n = hz.scan(hp, "xrepo", os.path.join(td, "hzst2"))
            after = open(hp).read()
            chk("hz_enforce_retires_unparked_only", n == 1 and "(retired-hazard-delete-all-tests) [T1] backend/tests/test_a.py" in after and parked in after and safe in after and "- [x] done one" in after)
            chk("hz_enforce_removes_open_line", hl not in after.replace("- [x] (retired-hazard-delete-all-tests) " + hl[len("- [ ] "):], ""))
            chk("hz_enforce_keeps_one_retired_section", after.count("### Retired (hazard") == 1)
            chk("hz_enforce_idempotent", hz.scan(hp, "xrepo", os.path.join(td, "hzst2")) == 0 and open(hp).read() == after)
            chk("hz_scan_missing_file_never_raises", hz.scan("/nonexistent/P.md") == 0)
        finally:
            for k in ("OVN_ITEM_HAZARD", "OVN_ITEM_HAZARD_LOG"):
                os.environ.pop(k, None)
        r_ = subprocess.run([sys.executable, hz.__file__, "replay", hp, "--all"], capture_output=True, text=True)
        chk("hz_replay_cli", r_.returncode == 0 and '"REPLACE_ALL"' in r_.stdout.split("\n")[0])
    return fails


# (file key, old, new): each must make run_checks fail
MUTANTS = [
    ("vl", 'if x == "app" or os.path.exists(os.path.join(root, x)) or os.path.exists(os.path.join(root, x + ".py")):', 'if x == "app":'),
    ("vl", 'if "PYTHONPATH" in clause or "sys.path" in clause:\n        return None', 'if False:\n        return None'),
    ("vl", "if not base or base.startswith(\"/\") or code is None:", "if base.startswith(\"/\") or code is None:"),
    ("vl", "_FASTAPI_INCLUDED_ROUTER_MIN = (0, 140)", "_FASTAPI_INCLUDED_ROUTER_MIN = (9, 0)"),
    ("vl", "if v is None or v < _FASTAPI_INCLUDED_ROUTER_MIN:", "if v is None:"),
    ("vl", "(?<![\\w.])(?!os\\b|sys\\b|self\\b)", "(?<![\\w.])"),
    ("vl", "if m.group(1) == \"==\" and _ver(m.group(2)):\n                    return _ver(m.group(2))", "if False:\n                    return None"),
    ("vl", 'for g in glob.glob(os.path.join(d, ".venv", "lib", "python*", "site-packages", "fastapi-*.dist-info")):', "for g in []:"),
    ("vl", "if any(m(n, fz) for _r, n, fz, _id in ents):", "if True:"),
    ("vl", "return any(term in n for n in names) or (fuzzy is not None and term in fuzzy)", "return any(term in n for n in names)"),
    ("vl", "return any(term in n for n in names) or (fuzzy is not None and term in fuzzy)", "return any(n == term for n in names)"),
    ("vl", "names = set(parts[:-1]) | set(mod)", "names = set(mod)"),
    ("vl", "| set(marks) | filemarks", "| filemarks"),
    ("vl", "if not any(\"::\" in x for x in targets) and _lead_is_test(item):", "if _lead_is_test(item):"),
    ("vl", "if not any(\"::\" in x for x in targets) and _lead_is_test(item):", "if False:"),
    ("vl", "ents = _restrict_nodeids(ents, targets)", "pass"),
    ("vl", "if not vals or not vals <= _CONF_OK[key]:", "if True:"),
    ("vl", "if not vals or not vals <= _CONF_OK[key]:", "if False:"),
    ("vl", 'single = len(terms) == 1 and len(re.findall(r"[^\\s()]+", k)) == 1 and terms[0].lower().startswith("test_")', "single = False"),
    ("vl", 'if not k or "--collect-only" in flags or "--co" in flags:', "if not k:"),
    ("vl", "if prev is not None and sep == \"|\" and t[0] in (\"grep\", \"egrep\"):", "if prev is not None and t[0] in (\"grep\", \"egrep\"):"),
    ("vl", "if specs or gflags & {\"v\", \"c\", \"L\", \"z\", \"P\"} or not pat.strip():", "if specs or not pat.strip():"),
    ("vl", "if _lead_is_test(item) and not pat.lstrip(\"^\").startswith(\"_\"):", "if _lead_is_test(item):"),
    ("vl", "if _lead_is_test(item) and not pat.lstrip(\"^\").startswith(\"_\"):", "if False:"),
    ("vl", "if rx.search(blob) or any(e[2] is not None and (pat.lower() in e[2]) for e in ents):", "if rx.search(blob):"),
    ("vl", "free = [n for n in _free_names(code) if n in always]", "free = _free_names(code)"),
    ("vl", "if isinstance(n, ast.BoolOp):\n            visit(n.values[0])\n            return", "if False:\n            return"),
    ("vl", "if not code or len(code) > MAX_LINE or \"import *\" in code:", "if not code or len(code) > MAX_LINE:"),
    ("vl", "return sorted(n for n in used - defined if not hasattr(builtins, n))", "return sorted(n for n in used - defined)"),
    ("vl", "if not base and _find_sub(repo_root, rel):\n                continue", "if False:\n                continue"),
    ("vl", "if _names_it(item, bn, rel) or _lead_is_test(item) or any(", "if any("),
    ("vl", "if _names_it(item, bn, rel) or _lead_is_test(item) or any(", "if _names_it(item, bn, rel) or any("),
    ("vl", "if not rel.endswith(\".py\") or os.path.isabs(rel) or os.path.exists(os.path.join(root, rel)):", "if not rel.endswith(\".py\") or os.path.isabs(rel):"),
    ("vl", "if _NODEID_UNEXPANDED.search(rel):\n                continue", "if False:\n                continue"),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[?\\[{$~`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*\\[{$~`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*?{$~`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*?\\[$~`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*?\\[{~`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*?\\[{$`]"'),
    ("vl", 'r"[*?\\[{$~`]"', 'r"[*?\\[{$~]"'),
    ("vl", "any(_CREATE_TEST_STEP.search(_head(sb)) for sb in siblings if sb != item) or ", "False or "),
    ("vl", "if any(rx.search(c) for c in cands):", "if True:"),
    ("vl", "cands = list(tests) + [d + \" \" + x for d in desc[:60] for x in tests[:200]]", "cands = list(tests)"),
    ("vl", "if \"${\" in src or \".each\" in src:", "if False:"),
    ("vl", "        if _lead_is_test(item):\n            continue\n        return _res(SUSPECT, \"TEST_NAME_DOES_NOT_EXIST: vitest", "        return _res(SUSPECT, \"TEST_NAME_DOES_NOT_EXIST: vitest"),
    ("vl", "if k >= len(parts):\n                continue", "if False:\n                continue"),
    ("vl", "if os.path.isfile(os.path.join(root, *parts[:k + 1]) + \".py\"):\n                    k = len(parts)\n                    break", "if False:\n                    break"),
    ("vl", "if parts[0] in _STD_MODS:\n                continue", "if False:\n                continue"),
    ("vl", "if _names_it(item, miss) and _CREATE_WORDS.search(_head(item)):\n                continue", "if False:\n                continue"),
    ("vl", "if _names_it(item, os.path.basename(rel), rel):\n                    continue", "if False:\n                    continue"),
    ("vl", 'r = park_cycle(opt("--outcomes", ""), repo or "", opt("--prog", ""),', 'r = park_cycle(opt("--outcomes", ""), "", opt("--prog", ""),'),
    ("vl", "        if _all:\n            return _all_rules(item_line, clause, repo_root, state_dir, siblings)", "        if True:\n            return _all_rules(item_line, clause, repo_root, state_dir, siblings)"),
    ("vl", "r = lint_verify(item_line, repo_root, state_dir, siblings, _all=True)", "r = lint_verify(item_line, repo_root, state_dir, siblings, _all=False)"),
    ("vl", "_shadow_log_new(item_line, repo_root, repo, state_dir, source, siblings)   # q-verify-shapes", "pass   # q-verify-shapes"),
    ("vl", "            if key in old:\n                continue\n            old.add(key)", "            old.add(key)"),
    ("vl", "PARK_RULES = (\"NODEID_WRONG_FILE\",)", "PARK_RULES = (\"NODEID_WRONG_FILE\", \"DIRTY_PATH\")"),
    ("vl", "kinds = tuple(x for x in (os.environ.get(\"OVN_VERIFY_LINT_PARK_KINDS\") or \"already-done,landed-uncredited\").split(\",\") if x in pc.BAD_KINDS) or pc.DEFAULT_KINDS", "kinds = pc.BAD_KINDS"),
    ("vl", "r = pc.cycle(rows, repo, prog_path, now, n, hours, kinds)", "r = pc.cycle(rows, repo, prog_path, now, 1, hours, kinds)"),
    ("vl", "if not r[\"trip\"] or not r[\"line_no\"]:\n            return out", "if not r[\"trip\"]:\n            return out"),
    ("vl", "x[\"verdict\"] == SUSPECT and x[\"rule\"] in rules]", "x[\"verdict\"] == SUSPECT]"),
    ("vl", "rules = tuple(x for x in (os.environ.get(\"OVN_VERIFY_LINT_PARK_RULES\") or \",\".join(PARK_RULES)).split(\",\") if x in NEW_RULES)", "rules = tuple((os.environ.get(\"OVN_VERIFY_LINT_PARK_RULES\") or \",\".join(PARK_RULES)).split(\",\"))"),
    ("hz", "if not any(_TESTY.search(p) for p in paths):\n            return None", "if False:\n            return None"),
    ("hz", "(?:replace|rewrite|overwrite|empty|wipe)\\w*", "(?:replace|rewrite|overwrite|empty|wipe|gut)\\w*"),
    ("hz", "if \"`\" in rest or _SCOPED_ANY.search(rest) or _DEAD.search(head):\n                continue", "if False:\n                continue"),
    ("hz", "if m and not _JUSTIFIED.search(head):", "if m:"),
    ("hz", "return re.sub(r\"\\[[^\\]]*\\]\", \" \", h)", "return h"),
    ("hz", "h = re.sub(r\"VERIFY:.*$\", \"\", line or \"\", flags=re.S)", "h = line or \"\""),
    ("hz", "retire = [i for i, _ in hits if not PARKED.search(lines[i])]", "retire = [i for i, _ in hits]"),
    ("hz", "return m if m in (\"off\", \"shadow\", \"enforce\") else \"shadow\"", "return m"),
    ("hz", "if md != \"enforce\":\n            return 0", "if False:\n            return 0"),
    ("hz", "            if key in seen:\n                continue", "            if False:\n                continue"),
    ("hz", "if md == \"off\" or not os.path.isfile(path):", "if not os.path.isfile(path):"),
]


def main():
    fails = run_checks(load(VL, "vl_real"), load(HZ, "hz_real"))
    for f in fails:
        print("FAIL", f)
    srcs = {"vl": open(VL).read(), "hz": open(HZ).read()}
    survived = 0
    for i, (key, old, new) in enumerate(MUTANTS):
        if old not in srcs[key]:
            print("MUTANT %d: pattern not found (stale mutant): %s" % (i, old[:70]))
            fails.append("stale_mutant_%d" % i)
            continue
        with tempfile.TemporaryDirectory() as td:
            pv, ph = VL, HZ
            if key == "vl":
                pv = os.path.join(td, "ovn_verify_lint.py")
                open(pv, "w").write(srcs["vl"].replace(old, new, 1))
                # park_cycle imports ovn_pick_cap from the module's own directory
                open(os.path.join(td, "ovn_pick_cap.py"), "w").write(open(os.path.join(ROOT, "ovn_pick_cap.py")).read())
            else:
                ph = os.path.join(td, "ovn_item_hazards.py")
                open(ph, "w").write(srcs["hz"].replace(old, new, 1))
            try:
                mf = run_checks(load(pv, "vl_mut%d" % i), load(ph, "hz_mut%d" % i))
            except Exception as e:
                mf = ["exception:%s" % e]
        if not mf:
            survived += 1
            print("MUTANT %d SURVIVED: %s -> %s" % (i, old[:70], new[:40]))
            fails.append("mutant_%d_survived" % i)
    print("q-verify-shapes: %d failure(s), %d of %d mutants survived" % (len(fails), survived, len(MUTANTS)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
