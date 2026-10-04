#!/usr/bin/env python3
"""Tests for the 2026-10-04 audit rules in qa/ag_h13.py (via the REAL gate entry point gate_antigaming.py, env -i, temp git repos, no network).
Every rule has a NEGATIVE control (seeded bad -> its rule fires) and a BENIGN control (legit change -> that rule stays silent)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
GATE = os.path.join(OVN, "qa", "gate_antigaming.py")
sys.path.insert(0, os.path.join(OVN, "qa"))
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


T = tempfile.mkdtemp(prefix="qa-agh13-test-")
REPOS, STATE = os.path.join(T, "repos"), os.path.join(T, "state")
os.makedirs(REPOS)
os.makedirs(STATE)
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x", "OVN_DIR": T, "OVN_REPOS_DIR": REPOS,
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0"}


def sh(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


_n = [0]


def mkrepo(*steps, name=None):
    """steps: dicts path->text (None deletes), one commit each. Returns repo name. Gate range is HEAD~1..HEAD unless told otherwise."""
    _n[0] += 1
    name = name or "r%d" % _n[0]
    d = os.path.join(REPOS, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    g = lambda *a: sh(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a])  # noqa: E731
    g("init", "-q")
    for i, step in enumerate(steps):
        for path, txt in step.items():
            full = os.path.join(d, path)
            if txt is None:
                g("rm", "-q", path)
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                open(full, "w").write(txt)
                g("add", path)
        g("commit", "-q", "-m", "c%d" % i)
    return name


def gate(repo, base="HEAD~1", head="HEAD", env=None, record=False):
    e = dict(ENV)
    if env:
        e.update(env)
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, GATE, "check", "--repo", repo, "--base", base, "--head", head] + ([] if record else ["--no-record"])
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}
    return res


def fnd(res, rule):
    return [f for f in res.get("details", {}).get("findings", []) if f["rule"] == rule]


def fires(name, res, rule, sym=None):
    hit = fnd(res, rule)
    if sym:
        hit = [f for f in hit if sym in f["msg"] or sym in f.get("snip", "")]
    ok(name, bool(hit), "verdict=%s rules=%s notes=%s" % (res["verdict"], sorted({f["rule"] for f in res.get("details", {}).get("findings", [])}), res.get("details", {}).get("notes")))


def silent(name, res, rule, sym=None):
    hit = fnd(res, rule)
    if sym:
        hit = [f for f in hit if sym in f["msg"] or sym in f.get("snip", "")]
    ok(name, not hit, "unexpected %s" % [f["msg"] for f in hit])


# ================================================================================================ D_DEAD_SYMBOL (python)
BASE = {"app/use.py": "from app.calc import add\n\n\ndef total(xs):\n    return add(xs[0], xs[1])\n", "app/calc.py": "def add(a, b):\n    return a + b\n",
        "tests/test_calc.py": "from app.calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n"}
CALC2 = ("def add(a, b):\n    return a + b\n\n\ndef bulk_upsert_programs(rows):\n    return len(rows)\n\n\ndef is_stream_visible_to_user(s, u):\n    return True\n\n\n"
         "def used_helper(x):\n    return x * 2\n\n\ndef _private_helper(x):\n    return x\n\n\nclass SomeSchema(BaseModel):\n    x: int\n\n\n"
         "@router.get('/x')\ndef route_fn():\n    return 1\n\n\nclass Orphaned:\n    pass\n")
TESTS2 = "from app.calc import add, bulk_upsert_programs, is_stream_visible_to_user\n\n\ndef test_a():\n    assert bulk_upsert_programs([1]) == 1\n    assert is_stream_visible_to_user(1, 2)\n"
r = mkrepo(BASE, {"app/calc.py": CALC2, "tests/test_calc2.py": TESTS2, "app/use.py": BASE["app/use.py"] + "\n\ndef double(x):\n    from app.calc import used_helper\n    return used_helper(x)\n"})
res = gate(r)
fires("D_DEAD_SYMBOL fires: iptv bulk_upsert_programs (tests only)", res, "D_DEAD_SYMBOL", "bulk_upsert_programs")
fires("D_DEAD_SYMBOL fires: iptv is_stream_visible_to_user (tests only)", res, "D_DEAD_SYMBOL", "is_stream_visible_to_user")
fires("D_DEAD_SYMBOL fires: class with no referencer at all", res, "D_DEAD_SYMBOL", "Orphaned")
silent("BENIGN: new function called by a production file is NOT flagged", res, "D_DEAD_SYMBOL", "used_helper")
silent("BENIGN: private helper not flagged", res, "D_DEAD_SYMBOL", "_private_helper")
silent("BENIGN: pydantic-style model class not flagged", res, "D_DEAD_SYMBOL", "SomeSchema")
silent("BENIGN: route-decorated function not flagged", res, "D_DEAD_SYMBOL", "route_fn")
ok("D_DEAD_SYMBOL is a FLAG (shadow), verdict FLAG not FAIL", res["verdict"] == "FLAG", res["verdict"])
# own-file-only chain: new public helper called only by another NEW dead symbol of the same file is flagged; called by an existing prod function is saved
r = mkrepo(BASE, {"app/calc.py": BASE["app/calc.py"] + "\n\ndef helper_a(x):\n    return x\n\n\ndef add3(a, b, c):\n    return add(add(a, b), c) + helper_a(0)\n"})
res = gate(r)
fires("D_DEAD_SYMBOL: helper_a whose only own-file caller is the (dead) new add3 is flagged too", res, "D_DEAD_SYMBOL", "helper_a")
fires("D_DEAD_SYMBOL fires on add3 (no caller)", res, "D_DEAD_SYMBOL", "add3")
r = mkrepo(BASE, {"app/calc.py": BASE["app/calc.py"] + "\n\ndef helper_b(x):\n    return x\n\n\ndef add4(a, b):\n    return helper_b(a) + b\n", "app/use.py": BASE["app/use.py"].replace("add(xs[0], xs[1])", "add4(xs[0], xs[1])").replace("import add", "import add4")})
res = gate(r)
silent("BENIGN: helper_b called by add4 which production code calls -> neither flagged", res, "D_DEAD_SYMBOL", "helper_b")
silent("BENIGN: add4 called by production code is not flagged", res, "D_DEAD_SYMBOL", "add4")
# REVIEW FIX: a public helper used only by a PRIVATE helper of the same file must not be attributed to the nearest PUBLIC def above it (real xlite FP is_cell_key)
r = mkrepo(BASE, {"app/calc.py": BASE["app/calc.py"] + "\n\ndef is_cell_key(k):\n    return len(k) == 2\n\n\ndef _grid_problem(d):\n    for k in d:\n        if not is_cell_key(k):\n            return 'bad'\n    return ''\n\n\n"
                  "def _use_it(d):\n    return _grid_problem(d)\n", "app/use.py": BASE["app/use.py"] + "\n\ndef check(d):\n    from app.calc import _use_it\n    return _use_it(d)\n"})
silent("REVIEW FIX BENIGN (py): public helper used by a private helper of the same file is not flagged", gate(r), "D_DEAD_SYMBOL", "is_cell_key")
# more benign shapes the audit asked about: re-export, getattr-by-string, .tscn-only wiring, signal method named in a scene, alembic, fixture
r = mkrepo(BASE, {"app/pkg/__init__.py": "from app.pkg.impl import reexported\n", "app/pkg/impl.py": "def reexported():\n    return 1\n",
                  "app/dyn.py": "def dynamic_target():\n    return 1\n",
                  "app/use.py": BASE["app/use.py"].replace("return add(xs[0], xs[1])", "return getattr(xs, 'dynamic_target')()") + "\n\ndef fn():\n    from app.pkg import reexported\n    return reexported()\n",
                  "alembic/versions/0001_x.py": "def upgrade():\n    pass\n\n\ndef downgrade():\n    pass\n\n\ndef backfill_rows():\n    pass\n",
                  "tests/test_fix.py": "import pytest\n\n\n@pytest.fixture\ndef client():\n    return 1\n"})
res = gate(r)
silent("BENIGN: python re-export through __init__ consumed by production", res, "D_DEAD_SYMBOL", "reexported")
silent("BENIGN: python function reached through getattr(o, 'name')", res, "D_DEAD_SYMBOL", "dynamic_target")
silent("BENIGN: alembic migration helpers are never flagged", res, "D_DEAD_SYMBOL", "backfill_rows")
# OVN_QA_AG_H13=off kill switch
res = gate(mkrepo(BASE, {"app/calc.py": CALC2}), env={"OVN_QA_AG_H13": "off"})
ok("kill switch OVN_QA_AG_H13=off silences every h13 rule", not [f for f in res["details"].get("findings", []) if f["rule"] in ("D_DEAD_SYMBOL",)], str(res["verdict"]))

# ---- GDScript
GD_BASE = {"scripts/battle.gd": "extends Node\n\nfunc run():\n\tpass\n", "tests/test_battle.gd": "extends GutTest\n\nfunc test_x():\n\tassert_true(true)\n", "project.godot": "[application]\n"}
GD_NEW = {"scripts/damage_preview.gd": "class_name DamagePreview\nextends RefCounted\n\nstatic func calculate_projected_damage(a, b):\n\treturn a - b\n\nstatic func morale_percent(m):\n\treturn m * 100\n\n"
          "static func apply_with_immunity(d, imm):\n\treturn d - imm\n\nstatic func wired_fn(x):\n\treturn x\n\nfunc _on_timer_timeout():\n\tpass\n\nfunc connect_me():\n\tpass\n",
          "scripts/battle.gd": "extends Node\n\nfunc run():\n\tvar v = DamagePreview.wired_fn(3)\n\ttimer.connect(\"timeout\", Callable(self, \"connect_me\"))\n",
          "tests/test_damage_preview.gd": "extends GutTest\n\nfunc test_a():\n\tassert_eq(DamagePreview.calculate_projected_damage(5, 2), 3)\n\tassert_eq(DamagePreview.morale_percent(1), 100)\n\tassert_eq(DamagePreview.apply_with_immunity(5, 1), 4)\n"}
res = gate(mkrepo(GD_BASE, GD_NEW, name="xlite"))
for s in ("calculate_projected_damage", "morale_percent", "apply_with_immunity"):
    fires("D_DEAD_SYMBOL fires: xlite %s (tests only)" % s, res, "D_DEAD_SYMBOL", s)
silent("BENIGN: gd func called by a production file is NOT flagged (wired_fn)", res, "D_DEAD_SYMBOL", "wired_fn")
silent("BENIGN: gd func referenced via quoted string in connect() is NOT flagged", res, "D_DEAD_SYMBOL", "connect_me")
silent("BENIGN: gd _on_* handler not flagged", res, "D_DEAD_SYMBOL", "_on_timer_timeout")
silent("BENIGN: gd class_name referenced by a production file (DamagePreview.wired_fn) is NOT flagged", res, "D_DEAD_SYMBOL", "DamagePreview")
r = mkrepo(GD_BASE, {"scripts/codec.gd": "class_name Codec\nextends RefCounted\n\nstatic func is_cell_key(k):\n\treturn k.size() == 2\n\nstatic func _grid_problem(d):\n\tfor k in d:\n\t\tif not is_cell_key(k):\n\t\t\treturn \"bad\"\n\treturn \"\"\n",
                     "scripts/battle.gd": "extends Node\n\nfunc run():\n\tvar v = Codec._grid_problem({})\n"}, name="xlite")
silent("REVIEW FIX BENIGN (gd): public static func used by a private static func of the same file is not flagged", gate(r), "D_DEAD_SYMBOL", "is_cell_key")
r = mkrepo(GD_BASE, {"scripts/hud.gd": "class_name Hud\nextends Control\n\nfunc on_end_turn_pressed():\n\tpass\n", "scenes/hud.tscn": "[gd_scene]\n[connection signal=\"pressed\" from=\"B\" to=\".\" method=\"on_end_turn_pressed\"]\n[node name=\"Hud\" script=ExtResource(\"res://scripts/hud.gd\")]\n"}, name="xlite")
res = gate(r)
silent("BENIGN: gd signal handler named only in a .tscn connection is wired", res, "D_DEAD_SYMBOL", "on_end_turn_pressed")
silent("BENIGN: gd class_name wired only by a .tscn script path is not flagged", res, "D_DEAD_SYMBOL", "Hud")

# ================================================================================================ E_TEST_NOT_COLLECTED
IPTV = {"iptv-backend/pytest.ini": "[pytest]\ntestpaths = tests\n", "iptv-backend/tests/test_a.py": "def test_a():\n    assert 1 == 1\n", "iptv-backend/app/x.py": "X = 1\n"}
res = gate(mkrepo(IPTV, {"iptv-backend/app/services/test_epg.py": "def test_e():\n    assert 1 == 1\n"}, name="iptv_apps"))
fires("E_TEST_NOT_COLLECTED fires: iptv test_*.py under app/", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo(IPTV, {"iptv-backend/tests/test_new.py": "def test_e():\n    assert 1 == 1\n"}, name="iptv_apps"))
silent("BENIGN: iptv test under iptv-backend/tests/ is collected", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo({"pkg/pytest.ini": "[pytest]\ntestpaths = tests\n", "pkg/tests/test_a.py": "def test_a():\n    assert 1\n"}, {"pkg/src/test_z.py": "def test_z():\n    assert 1 == 1\n"}))
fires("E_TEST_NOT_COLLECTED fires from nearest pytest.ini testpaths (repo without explicit config)", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo({"pkg/pytest.ini": "[pytest]\n", "pkg/tests/test_a.py": "def test_a():\n    assert 1\n"}, {"pkg/src/test_z.py": "def test_z():\n    assert 1 == 1\n"}))
silent("BENIGN: pytest config without testpaths => collected from rootdir", res, "E_TEST_NOT_COLLECTED")
GUT = "extends GutTest\n\nfunc test_a():\n\tassert_true(true)\n"
res = gate(mkrepo(GD_BASE, {"test/battle/aoe_falloff_test.gd": GUT}, name="xlite"))
fires("E_TEST_NOT_COLLECTED fires: xlite test/ (singular) + *_test.gd", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo(GD_BASE, {"tests/test_not_gut.gd": "extends Node\n\nfunc test_a():\n\tpass\n"}, name="xlite"))
fires("E_TEST_NOT_COLLECTED fires: xlite test not extending GutTest", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo(GD_BASE, {"tests/battle/test_new.gd": GUT, "tests/test_top.gd": GUT}, name="xlite"))
silent("BENIGN: xlite tests/battle/test_new.gd collected (subdirs ON by default)", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo(GD_BASE, {"tests/battle/test_new.gd": GUT}, name="xlite"), env={"OVN_GUT_SUBDIRS": "off"})
fires("kill switch OVN_GUT_SUBDIRS=off: tests/battle/* reported as not collected again", res, "E_TEST_NOT_COLLECTED")
res = gate(mkrepo(GD_BASE, {"tests/helpers/builder.gd": "extends RefCounted\n\nfunc build():\n\tpass\n"}, name="xlite"))
silent("BENIGN: non-test helper file under tests/ is not a test", res, "E_TEST_NOT_COLLECTED")

# ================================================================================================ frozen vendored paths
AD = {"addons/gut/gut.gd": "extends Node\nfunc a():\n\tpass\n", "scripts/a.gd": "extends Node\n"}
res = gate(mkrepo(AD, {"addons/gut/gut.gd": "extends Node\nfunc a():\n\tpass\nfunc skip_missing():\n\tpass\n"}, name="xlite"))
ok("D_FROZEN_EDIT is a FLAG by default (own mode antigaming_frozen=shadow): edit to addons/gut/gut.gd (xlite)", res["verdict"] == "FLAG" and fnd(res, "D_FROZEN_EDIT"), res["verdict"])
res = gate(mkrepo(AD, {"addons/gut/gut.gd": "extends Node\nfunc a():\n\tpass\nfunc skip_missing():\n\tpass\n"}, name="xlite"), env={"OVN_QA_ANTIGAMING": "enforce"})
ok("REVIEW FIX: flipping the SHARED antigaming gate to enforce does NOT arm the vendored-edit FAIL (still FLAG)", res["verdict"] == "FLAG" and fnd(res, "D_FROZEN_EDIT"), res["verdict"])
res = gate(mkrepo(AD, {"addons/gut/gut.gd": "extends Node\nfunc a():\n\tpass\nfunc skip_missing():\n\tpass\n"}, name="xlite"), env={"OVN_QA_ANTIGAMING_FROZEN": "enforce"})
ok("D_FROZEN_EDIT FAIL once antigaming_frozen is itself flipped to enforce", res["verdict"] == "FAIL" and fnd(res, "D_FROZEN_EDIT"), res["verdict"])
res = gate(mkrepo(AD, {"addons/gut/gut.gd": "extends Node\nfunc a():\n\tpass\nfunc skip_missing():\n\tpass\n"}, name="xlite"), env={"OVN_QA_ANTIGAMING_FROZEN": "off"})
silent("antigaming_frozen=off: the vendored rule is skipped", res, "D_FROZEN_EDIT")
res = gate(mkrepo(AD, {"addons/placeholder/x.gd": "extends Node\n"}, name="xlite"))
fires("D_FROZEN_NEWFILE FLAG: new file under addons/", res, "D_FROZEN_NEWFILE")
res = gate(mkrepo(AD, {"scripts/a.gd": "extends Node\nfunc y():\n\tpass\n"}, name="xlite"))
silent("BENIGN: edit outside addons/ is not frozen", res, "D_FROZEN_EDIT")
res = gate(mkrepo({"addons/foo.py": "x = 1\n"}, {"addons/foo.py": "x = 2\n"}, name="billwatch"))
silent("BENIGN: addons/** is frozen only for xlite (other repos unaffected)", res, "D_FROZEN_EDIT")
res = gate(mkrepo({"vendor/lib.py": "x = 1\n"}, {"vendor/lib.py": "x = 2\n"}, name="gitlark"))
ok("default vendor/* frozen for every repo -> D_FROZEN_EDIT", bool(fnd(res, "D_FROZEN_EDIT")), str(res["verdict"]))

# ================================================================================================ F_REVERT_OF_RECENT
V0 = "func calc(a, b):\n\tvar total = a + b\n\tvar scaled = total * 2\n\tvar clipped = max(scaled, 0)\n\treturn clipped\n"
V1 = "func calc(a, b):\n\tvar total = a + b + 1\n\tvar scaled = total * 3\n\tvar clipped = max(scaled, 1)\n\treturn clipped\n"
res = gate(mkrepo({"scripts/d.gd": V0}, {"scripts/d.gd": V1}, {"scripts/d.gd": V0}, name="xlite"))
fires("F_REVERT_OF_RECENT fires: commit exactly inverts the previous commit", res, "F_REVERT_OF_RECENT")
res = gate(mkrepo({"scripts/d.gd": V0}, {"scripts/d.gd": V1}, {"scripts/d.gd": V1.replace("total * 3", "total * 4")}, name="xlite"))
silent("BENIGN: a different follow-up edit is not an inverse", res, "F_REVERT_OF_RECENT")
res = gate(mkrepo({"scripts/d.gd": V0 + "\nfunc other():\n\tpass\n"}, {"scripts/d.gd": V0 + "\nfunc other():\n\tpass\n\nfunc newone():\n\tvar q = 1\n\treturn q\n"}, name="xlite"))
silent("BENIGN: first-ever edit (nothing to invert)", res, "F_REVERT_OF_RECENT")
res = gate(mkrepo({"OVERNIGHT_PROGRESS.md": "a line here one\nsecond line two\n"}, {"OVERNIGHT_PROGRESS.md": "changed here now\nsecond line two x\n"}, {"OVERNIGHT_PROGRESS.md": "a line here one\nsecond line two\n"}, name="xlite"))
silent("BENIGN: bookkeeping files (OVERNIGHT_*.md) are ignored", res, "F_REVERT_OF_RECENT")
# counter: 6 flip-flops in 24h => ONE alerts.log warn (deduped per file/day)
steps = [{"scripts/d.gd": V0}]
for i in range(7):
    steps.append({"scripts/d.gd": V1 if i % 2 == 0 else V0})
r = mkrepo(*steps, name="xlite")
for i in range(1, 8):
    gate(r, base="HEAD~%d" % (8 - i), head="HEAD~%d" % (7 - i) if 7 - i else "HEAD", record=True) if False else None
revs = subprocess.run(["git", "-C", os.path.join(REPOS, r), "rev-list", "--reverse", "HEAD"], capture_output=True, text=True).stdout.split()
for a, b in zip(revs[1:-1], revs[2:]):
    gate(r, base=a, head=b, record=True)
for a, b in zip(revs[1:-1], revs[2:]):
    gate(r, base=a, head=b, record=True)  # replaying the same commits must not double count
alerts = open(os.path.join(T, "state", "alerts.log")).read() if os.path.exists(os.path.join(T, "state", "alerts.log")) else ""
ok("revert counter: >=6 inverse commits in 24h => exactly ONE deduped alerts.log warn", alerts.count("qa-revert-churn:xlite") == 1, alerts[-300:])
ok("revert counter parks nothing (state file only counts)", os.path.exists(os.path.join(T, "state", "qa_revert_counter.json")))

# ================================================================================================ C_FILE_DELETED_LIVE / C_TEST_ORPHANED
LIVE = {"app/helper.py": "def compute_grand_total(xs):\n    return sum(xs)\n", "app/use.py": "from app.helper import compute_grand_total\n\n\ndef report(xs):\n    return compute_grand_total(xs)\n",
        "tests/test_helper.py": "from app.helper import compute_grand_total\n\n\ndef test_t():\n    assert compute_grand_total([1]) == 1\n"}
res = gate(mkrepo(LIVE, {"app/helper.py": None}))
fires("C_FILE_DELETED_LIVE fires: deleted file still referenced by production code (309504f shape)", res, "C_FILE_DELETED_LIVE")
res = gate(mkrepo(LIVE, {"app/helper.py": None, "tests/test_helper.py": None, "app/use.py": "def report(xs):\n    return 0\n"}))
silent("BENIGN: file deleted together with its referencers", res, "C_FILE_DELETED_LIVE")
res = gate(mkrepo(LIVE, {"app/helper.py": None, "app/use.py": "def report(xs):\n    return 0\n"}))
fires("C_FILE_DELETED_LIVE fires: only the test file remains and still references it", res, "C_FILE_DELETED_LIVE")
res = gate(mkrepo(dict(LIVE, **{"docs/NOTES.md": "see compute_grand_total in app/helper.py\n", "CHANGELOG.md": "- added compute_grand_total\n", "OVERNIGHT_PROGRESS.md": "- [x] compute_grand_total\n"}),
                  {"app/helper.py": None, "tests/test_helper.py": None, "app/use.py": "def report(xs):\n    return 0\n", "app/other.py": "# was compute_grand_total before the cleanup\nVALUE = 1\n"}))
silent("REVIEW BENIGN: deleted file whose only remaining referencers are docs/bookkeeping/comments is not a live delete", res, "C_FILE_DELETED_LIVE")
res = gate(mkrepo(LIVE, {"app/helper.py": None, "app/helper2.py": "def compute_grand_total(xs):\n    return sum(xs)\n"}))
silent("BENIGN: symbol moved to another file (still defined) is not a live delete", res, "C_FILE_DELETED_LIVE")
res = gate(mkrepo(LIVE, {"app/helper.py": "def other_thing(xs):\n    return 1\n"}))
fires("C_TEST_ORPHANED fires: symbol removed while a test still imports/calls it (9acac02 shape)", res, "C_TEST_ORPHANED", "compute_grand_total")
res = gate(mkrepo(LIVE, {"app/helper.py": "def other_thing(xs):\n    return 1\n", "tests/test_helper.py": "def test_t():\n    assert 1 == 1\n", "app/use.py": "def report(xs):\n    return 1\n"}))
silent("BENIGN: symbol removed and tests updated", res, "C_TEST_ORPHANED")

res = gate(mkrepo(LIVE, {"app/helper.py": "def other_thing(xs):\n    return 1\n", "tests/test_helper.py": "def test_t():\n    log = 'compute_grand_total target=3'\n    assert log\n", "app/use.py": "def report(xs):\n    return 1\n"}))
silent("BENIGN: test mentions the removed name only inside a string literal (billwatch reset_password gold F3 shape)", res, "C_TEST_ORPHANED")
res = gate(mkrepo({"tests/test_d.py": "def test_a():\n    assert 1 == 1\n\n\ndef test_b():\n    assert 1 == 1\n"}, {"tests/test_d.py": "def test_a():\n    assert 1 == 1\n"}, name="xlite"))
silent("BENIGN: removing lines of a file CREATED by the previous commit (duplicate removal) is not a flip-flop", res, "F_REVERT_OF_RECENT")
res = gate(mkrepo({"app/m.py": "x = 1\n"}, {"app/m.py": "x = 1\n\n\ndef public_helper():\n    return 1\n\n\nVALUE = public_helper()\n"}))
silent("BENIGN: new public function used by a module-level statement (runs at import) is not dead", res, "D_DEAD_SYMBOL", "public_helper")

# ================================================================================================ A_MOCK_ONLY
TM0 = "def test_old():\n    assert 1 == 1\n"
MOCK_ONLY = ("from unittest.mock import MagicMock\n\n\ndef test_notify_called():\n    m = MagicMock()\n    m.send('x')\n    m.send.assert_called_once_with('x')\n\n\n"
             "def test_counts():\n    cb = MagicMock()\n    cb()\n    assert cb.call_count == 1\n")
res = gate(mkrepo({"tests/test_a.py": TM0}, {"tests/test_a.py": MOCK_ONLY}))
fires("A_MOCK_ONLY fires: assert_called_once_with on a MagicMock created in the test", res, "A_MOCK_ONLY", "test_notify_called")
fires("A_MOCK_ONLY fires: assert call_count on a local mock", res, "A_MOCK_ONLY", "test_counts")
REAL = ("from unittest.mock import MagicMock\nfrom app.svc import process\n\n\ndef test_process_notifies():\n    m = MagicMock()\n    out = process(m, 3)\n    assert out == 6\n    m.send.assert_called_once()\n\n\n"
        "from unittest.mock import patch\n\n\n@patch('app.svc.send')\ndef test_patched(send):\n    r = process(None, 2)\n    send.assert_called_once()\n    assert r == 4\n")
res = gate(mkrepo({"tests/test_a.py": TM0}, {"tests/test_a.py": REAL}))
silent("BENIGN: mock assertion PLUS a real return-value assertion is not mock-only", res, "A_MOCK_ONLY")
PATCH_ONLY = "from unittest.mock import patch\n\n\n@patch('app.svc.send')\ndef test_p(send):\n    send('a')\n    send.assert_called_once()\n"
res = gate(mkrepo({"tests/test_a.py": TM0}, {"tests/test_a.py": PATCH_ONLY}))
fires("A_MOCK_ONLY fires: @patch-injected mock called by the test then assert_called_once", res, "A_MOCK_ONLY", "test_p")
res = gate(mkrepo({"tests/test_a.py": MOCK_ONLY}, {"tests/test_a.py": MOCK_ONLY + "\n\ndef test_extra():\n    assert 1 + 1 == 2\n"}))
silent("BENIGN: pre-existing mock-only tests untouched by the diff are not re-flagged", res, "A_MOCK_ONLY", "test_notify_called")

# ================================================================================================ A_MIRROR_EXPECTED
MIR = ("extends GutTest\n\nfunc test_mirror_direct():\n\tassert_eq(Dmg.calc(5, 2), Dmg.calc(5, 2))\n\nfunc test_mirror_var():\n\tvar expected = Dmg.calc(7, 1)\n\tvar got = 1\n\tassert_eq(Dmg.calc(7, 1), expected)\n\n"
       "func test_literal():\n\tassert_eq(Dmg.calc(5, 2), 3)\n\nfunc test_other_input():\n\tassert_eq(Dmg.calc(5, 2), Dmg.calc(10, 4) / 2)\n\nfunc test_builtin():\n\tassert_eq(Vector2(1, 2), Vector2(1, 2))\n")
res = gate(mkrepo(GD_BASE, {"tests/test_mir.gd": MIR}, name="xlite"))
fires("A_MIRROR_EXPECTED fires: assert_eq(f(x), f(x))", res, "A_MIRROR_EXPECTED", "Dmg.calc(5, 2), Dmg.calc(5, 2)")
fires("A_MIRROR_EXPECTED fires: expected var assigned from the same call", res, "A_MIRROR_EXPECTED", "expected")
ok("A_MIRROR_EXPECTED: exactly the 2 mirror assertions flagged (literal / different input / builtin ctor are benign)", len(fnd(res, "A_MIRROR_EXPECTED")) == 2,
   str([f["snip"] for f in fnd(res, "A_MIRROR_EXPECTED")]))

# ================================================================================================ config JSONs absent (gitignored files forgotten by a file-by-file deploy)
QA2 = os.path.join(T, "qa_nojson")
shutil.copytree(os.path.join(OVN, "qa"), QA2, ignore=shutil.ignore_patterns("*.json", "__pycache__", "state", "*.pyc"))
ok("fixture: the copied qa/ dir really lacks frozen_paths.json and test_collection.json", not os.path.exists(os.path.join(QA2, "frozen_paths.json")) and not os.path.exists(os.path.join(QA2, "test_collection.json")))
rname = mkrepo(GD_BASE, {"addons/gut/gut.gd": "extends Node\n", "scripts/dead.gd": "extends RefCounted\n\nstatic func orphan_helper(x):\n\treturn x\n", "tests/battle/test_x.gd": "extends GutTest\n\nfunc test_a():\n\tassert_eq(Dmg.calc(5, 2), 3)\n"}, name="xlite")
cmd = ["env", "-i"] + ["%s=%s" % kv for kv in ENV.items()] + [PY, os.path.join(QA2, "gate_antigaming.py"), "check", "--repo", rname, "--base", "HEAD~1", "--head", "HEAD", "--no-record"]
pp = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
try:
    res = json.loads(pp.stdout.strip().splitlines()[-1])
except Exception:  # noqa: BLE001
    res = {"verdict": "NOJSON", "summary": (pp.stdout + pp.stderr)[-300:], "details": {}}
notes = " ".join(res.get("details", {}).get("notes", []))
ok("JSONs ABSENT: the gate does NOT go UNVERIFIED / crash (verdict %s)" % res["verdict"], res["verdict"] in ("PASS", "FLAG", "NA"), res.get("summary", ""))
ok("JSONs ABSENT: no 'h13 ... errored/failed' note (rules degrade to NA, they do not blow up)", "errored" not in notes and "failed to run" not in notes, notes)
ok("JSONs ABSENT: vendored-path rule is NA (frozen details NA) and raises no D_FROZEN_*", str(res.get("details", {}).get("frozen", "")).startswith("NA") and not fnd(res, "D_FROZEN_EDIT") and not fnd(res, "D_FROZEN_NEWFILE"), str(res.get("details", {}).get("frozen")))
ok("JSONs ABSENT: the JSON-independent rules still fire (D_DEAD_SYMBOL on the orphan helper)", bool(fnd(res, "D_DEAD_SYMBOL")), str([f["rule"] for f in res.get("details", {}).get("findings", [])]))
ok("JSONs ABSENT: GUT collection check is skipped (no test_collection.json => no E_TEST_NOT_COLLECTED for xlite)", not fnd(res, "E_TEST_NOT_COLLECTED"))
# unreadable / malformed JSON behaves the same as absent
open(os.path.join(QA2, "frozen_paths.json"), "w").write("{not json")
open(os.path.join(QA2, "test_collection.json"), "w").write("[1, 2")
pp = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
try:
    res = json.loads(pp.stdout.strip().splitlines()[-1])
except Exception:  # noqa: BLE001
    res = {"verdict": "NOJSON", "summary": (pp.stdout + pp.stderr)[-300:], "details": {}}
ok("MALFORMED JSONs: gate still gives a normal verdict (%s), no crash" % res["verdict"], res["verdict"] in ("PASS", "FLAG", "NA") and "errored" not in " ".join(res.get("details", {}).get("notes", [])))

shutil.rmtree(T, ignore_errors=True)
print("\nag_h13 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
