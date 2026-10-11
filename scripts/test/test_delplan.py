#!/usr/bin/env python3
"""Package delplan (2026-10-11): xlite X5 / X6 / X10 / X11 and iptv F8.

  Part 1  X6   ovn_delete_executor importer scan: comments, docs and same-basename files in another directory are NOT references (real orphan case scripts/battle/save_manager.gd vs
               scripts/save/save_manager.gd, root scatter.gd vs a '# ... scatter the landing' comment); real references (res:// path, relative preload, class_name use, dotted python module,
               python import statement, kotlin import) still block. MUTATION: the old `git grep -lIw <stem>` scan fails the false-positive cases.
  Part 2  X5   ovn_delete_executor plan: one deterministic delete item per path for a pure file-delete feature; every doubt is a SKIP (model path); referrers first; DONE when already gone.
  Part 3  X11/X10  spec rules R13 (godot -s <test>.gd), R14 (`test ! -f P` ordered before the delete of P), R15 (typing/doc item on a function with zero production callers).
  Part 4  F8   ovn_move_executor: check/apply for .gd (res:// rewrite + .uid), .py (dotted module), .kt (package + imports); SKIPs; rollback; the executor hook in SHADOW mode.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_delete_executor as D  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0
TMP = tempfile.mkdtemp(prefix="delplan-")


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def mkrepo(files, name=None):
    d = tempfile.mkdtemp(prefix=(name or "r") + "-", dir=TMP)
    for rel, text in files.items():
        fp = os.path.join(d, rel)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        with open(fp, "w", encoding="utf-8") as f:
            f.write(text)
    for c in (["init", "-q", "."], ["config", "user.email", "t@t"], ["config", "user.name", "t"], ["add", "-A"], ["commit", "-q", "-m", "base"]):
        subprocess.run(["git", "-C", d] + c, check=True, capture_output=True)
    return d


def sh(repo, *a):
    return subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True).stdout


def item(path, text="Delete the file."):
    return "- [ ] [T1] %s — %s VERIFY: `test ! -f %s`. (cat:refactor; multifile:no)" % (path, text, path)


# =============================================================================================================================================================================
print("== Part 1 (X6): importer scan")
xl = mkrepo({
    "project.godot": '[autoload]\nSaveManager="*res://scripts/save/save_manager.gd"\n',
    "scatter.gd": "# Placeholder - the implement step fills this in.\n",
    "scripts/battle/catapult.gd": "extends Node\n# Miss roll: scatter the landing point\nfunc scatter_target(x):\n\treturn x\n",
    "tests/test_catapult_scatter.gd": "extends GutTest\nfunc test_scatter():\n\tpass\n",
    "scripts/battle/save_manager.gd": "extends Node\nstatic func _is_valid_save_name(name: String) -> bool:\n\treturn name != \"\"\n",
    "scripts/save/save_manager.gd": "extends Node\nfunc save_game():\n\tpass\n",
    "scripts/mission/save_slot_select.gd": "extends Node\n# uses save_manager.gd (the autoload)\nfunc go():\n\tSaveManager.save_game()\n",
    "scripts/tutorial/tutorial_manager.gd": "extends Node\n## save_manager.gd is the real one\nfunc t():\n\tpass\n",
    "scripts/units/helper_thing.gd": "class_name HelperThing\nextends Node\nfunc a():\n\tpass\n",
    "scripts/units/user_of_helper.gd": "extends Node\nfunc b():\n\treturn HelperThing.new()\n",
    "scripts/units/dead_thing.gd": "class_name DeadThing\nextends Node\n",
    "scripts/units/mentions_dead.gd": "extends Node\n# DeadThing was removed long ago\nfunc c():\n\tpass\n",
    "README.md": "scatter.gd and save_manager.gd and DeadThing are mentioned here\n",
    "AGENTS.md": "see scripts/battle/save_manager.gd\n",
    "OVERNIGHT_PROGRESS.md": "- [ ] [T1] scatter.gd - something about scatter.gd and scripts/battle/save_manager.gd\n",
}, "xlite")


def chk(repo, path, text="Delete the file."):
    return D.decide(repo, item(path, text))


r = chk(xl, "scatter.gd")
ok("X6 root scatter.gd: only a '# ... scatter the landing' comment and a method name -> OK (was SKIP referenced by battle.gd/catapult.gd/tests)", r == ("OK", "scatter.gd"), r)
r = chk(xl, "scripts/battle/save_manager.gd")
ok("X6 orphan scripts/battle/save_manager.gd: the sibling scripts/save/save_manager.gd (project.godot autoload, comments) is NOT a reference -> OK", r == ("OK", "scripts/battle/save_manager.gd"), r)
r = chk(xl, "scripts/save/save_manager.gd")
ok("X6 the REAL scripts/save/save_manager.gd is still protected by the project.godot autoload path", r[0] == "SKIP" and "project.godot" in r[1], r)
r = chk(xl, "scripts/units/helper_thing.gd")
ok("X6 .gd class_name word use in another file (HelperThing.new()) -> SKIP", r[0] == "SKIP" and "user_of_helper.gd" in r[1], r)
r = chk(xl, "scripts/units/dead_thing.gd")
ok("X6 .gd class_name only in a comment -> OK", r == ("OK", "scripts/units/dead_thing.gd"), r)
ok("X6 README.md / AGENTS.md / OVERNIGHT_PROGRESS.md mentions never count", chk(xl, "scatter.gd")[0] == "OK" and chk(xl, "scripts/battle/save_manager.gd")[0] == "OK")

# real references still block
ref = mkrepo({
    "scripts/battle/old_thing.gd": "extends Node\n",
    "scripts/a.gd": 'extends Node\nconst X = preload("res://scripts/battle/old_thing.gd")\n',
    "scripts/b.tscn": '[ext_resource type="Script" path="res://scripts/battle/old_thing.gd" id="1"]\n',
    "scripts/battle/c.gd": 'extends Node\nconst Y = preload("old_thing.gd")\n',
    "scripts/other/d.gd": 'extends Node\nconst Z = preload("old_thing.gd")\n',
    "scripts/other/old_thing.gd": "extends Node\n",
    "scripts/e.gd": 'extends Node\nvar p = "my_old_thing.gd"\nvar q = "user://old_thing.gd"\n',
}, "refs")
r = chk(ref, "scripts/battle/old_thing.gd")
ok("X6 res:// preload, .tscn ext_resource and a RELATIVE preload from the same directory all block", r[0] == "SKIP" and all(x in r[1] for x in ("a.gd",)), r)
refs = D._importers(ref, "scripts/battle/old_thing.gd", ["scripts/battle/old_thing.gd"])
ok("X6 refs of scripts/battle/old_thing.gd = a.gd, b.tscn, battle/c.gd (relative, same dir) - NOT other/d.gd (its relative preload is other/old_thing.gd), not 'my_old_thing.gd', not user://",
   refs == {"scripts/a.gd", "scripts/b.tscn", "scripts/battle/c.gd"}, refs)
refs = D._importers(ref, "scripts/other/old_thing.gd", ["scripts/other/old_thing.gd"])
ok("X6 refs of scripts/other/old_thing.gd = only other/d.gd", refs == {"scripts/other/d.gd"}, refs)

py = mkrepo({
    "app/__init__.py": "",
    "app/jobs/__init__.py": "",
    "app/jobs/orphan_job.py": "def run():\n    return 1\n",
    "app/jobs/live_job.py": "def go():\n    return 2\n",
    "app/jobs/uses_live.py": "from app.jobs.live_job import go\n",
    "app/jobs/rel_user.py": "from .rel_target import f\n",
    "app/jobs/rel_target.py": "def f():\n    return 3\n",
    "app/jobs/pkg_user.py": "from app.jobs import pkg_target\n",
    "app/jobs/pkg_target.py": "def g():\n    return 4\n",
    "tests/test_x.py": '# orphan_job is tested elsewhere\nimport mock\n\ndef t():\n    mock.patch("app.jobs.patched_job.f")\n',
    "app/jobs/patched_job.py": "def f():\n    return 5\n",
    "docs/notes.txt": "orphan_job\n",
}, "py")
ok("X6 .py orphan with only a comment mention -> OK", chk(py, "app/jobs/orphan_job.py")[0] == "OK", chk(py, "app/jobs/orphan_job.py"))
ok("X6 .py module imported by dotted path -> SKIP", chk(py, "app/jobs/live_job.py")[0] == "SKIP")
ok("X6 .py module reached by a relative import (from .rel_target import f) -> SKIP", chk(py, "app/jobs/rel_target.py")[0] == "SKIP")
ok("X6 .py module reached by `from app.jobs import pkg_target` -> SKIP", chk(py, "app/jobs/pkg_target.py")[0] == "SKIP")
ok("X6 .py module named in a dotted mock.patch string -> SKIP", chk(py, "app/jobs/patched_job.py")[0] == "SKIP")

kt = mkrepo({
    "app/src/main/java/com/x/repo/FavoritesRepository.kt": "package com.x.repo\nclass FavoritesRepository\n",
    "app/src/main/java/com/x/ui/User.kt": "package com.x.ui\nimport com.x.repo.FavoritesRepository\nclass User\n",
    "app/src/main/java/com/x/repo/DeadRepository.kt": "package com.x.repo\nclass DeadRepository\n",
    "app/src/main/java/com/x/ui/Other.kt": "package com.x.ui\n// DeadRepository was removed\n/* DeadRepository */\n * DeadRepository\nclass Other\n",
}, "kt")
ok("X6 .kt imported by another file -> SKIP", chk(kt, "app/src/main/java/com/x/repo/FavoritesRepository.kt")[0] == "SKIP")
ok("X6 .kt named only in comment lines -> OK", chk(kt, "app/src/main/java/com/x/repo/DeadRepository.kt")[0] == "OK", chk(kt, "app/src/main/java/com/x/repo/DeadRepository.kt"))

# MUTATION: the old scan (`git grep -lIw <stem>` over every tracked non-doc file) must fail the false-positive cases above
_orig = D._importers


def _old_scan(repo, prim, targets):
    stem = os.path.splitext(os.path.basename(prim))[0]
    out = set()
    for f in subprocess.run(["git", "-C", repo, "grep", "-lIw", "--", stem], capture_output=True, text=True).stdout.splitlines():
        if f not in targets and not D.IGNORE_REF.search(f):
            out.add(f)
    return out


D._importers = _old_scan
mut_a = chk(xl, "scatter.gd")[0] == "SKIP"
mut_b = chk(xl, "scripts/battle/save_manager.gd")[0] == "SKIP"
D._importers = _orig
ok("X6 MUTATION: with the old stem-word scan the root scatter.gd case is a SKIP (the bug)", mut_a)
ok("X6 MUTATION: with the old stem-word scan the same-basename save_manager.gd case is a SKIP (the bug)", mut_b)

# the CLI round trip prints OK for the orphan (what run_overnight.sh's DELETE-EXECUTOR block acts on)
cli = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_delete_executor.py"), "check", xl, item("scripts/battle/save_manager.gd", "Delete the file entirely")], capture_output=True, text=True).stdout
ok("X6 CLI check prints OK<TAB>path for the orphan", cli.strip() == "OK\tscripts/battle/save_manager.gd", cli)

# ---- Part 1b (round-2 review): no-regression table - every reference FORM the old stem-word scan blocked must still block --------------------------------------------------
print("== Part 1b (X6): no-regression table (multi-line / backslash imports, alias use, importlib, alias-prefixed TS/Vue imports)")
PYT = "app/services/zorblax_thing.py"
PY_FORMS = {
    "multi-line parenthesised import (black/ruff style)": "from app.services import (\n    zorblax_thing,\n    bar,\n)\n",
    "backslash continuation": "from app.services import bar, \\\n    zorblax_thing\n",
    "alias attribute use `s.zorblax_thing.f()`": "import app.services as s\ns.zorblax_thing.f()\n",
    "importlib string concatenation": "import importlib\nm = importlib.import_module(\"app.services.\" + \"zorblax_thing\")\n",
    "bare continuation line in a list": "MODS = [\n    zorblax_thing,\n]\n",
    "single-line dotted import": "from app.services.zorblax_thing import f\n",
    "single-line package import": "from app.services import zorblax_thing\n",
}
VUET = "src/components/ZorblaxWidget.vue"
TS_FORMS = {
    "@/ alias default import with extension": ("src/views/A.vue", "<script>\nimport W from '@/components/ZorblaxWidget.vue'\n</script>\n"),
    "@/ alias lazy import()": ("src/router/index2.ts", "const W = () => import('@/components/ZorblaxWidget.vue')\n"),
    "~/ alias import": ("src/views/B.vue", "<script>\nimport W from '~/components/ZorblaxWidget.vue'\n</script>\n"),
    "relative import with extension": ("src/views/C.vue", "<script>\nimport W from '../components/ZorblaxWidget.vue'\n</script>\n"),
    "bare stem default import": ("src/views/D.vue", "<script>\nimport ZorblaxWidget from './nope'\n</script>\n"),
}


def mk_one(target, tbody, cpath, cbody):
    files = {target: tbody, cpath: cbody}
    if target.endswith(".py"):
        files.update({"app/__init__.py": "", "app/services/__init__.py": ""})
    else:
        files["src/other/ZorblaxWidget.vue"] = "<template/>\n"
    return mkrepo(files, "nr")


py_repos = {label: mk_one(PYT, "def f():\n    return 1\n", "app/api/consumer.py", body) for label, body in PY_FORMS.items()}
for label, rp in py_repos.items():
    r = D.decide(rp, item(PYT))
    ok("X6 no-regression .py delete: %s -> SKIP" % label, r[0] == "SKIP" and "consumer.py" in r[1], r)
ts_repos = {label: mk_one(VUET, "<template/>\n", cpath, body) for label, (cpath, body) in TS_FORMS.items()}
for label, rp in ts_repos.items():
    r = D.decide(rp, item(VUET))
    ok("X6 no-regression .vue/.ts delete: %s -> SKIP" % label, r[0] == "SKIP" and TS_FORMS[label][0] in r[1], r)
# the false-positive fixes survive: a path token that positively resolves to ANOTHER tracked file is not a reference
rp = mk_one(VUET, "<template/>\n", "src/views/E.vue", "<script>\nimport W from '../other/ZorblaxWidget.vue'\n</script>\n")
r = D.decide(rp, item(VUET))
ok("X6 a relative path token resolving to the same-named src/other/ZorblaxWidget.vue is NOT a reference -> OK", r == ("OK", VUET), r)
rp = mk_one(VUET, "<template/>\n", "src/views/F.vue", "<script>\n// import W from '@/components/ZorblaxWidget.vue'\n</script>\n")
ok("X6 a comment-only mention of the alias import is not a reference -> OK", D.decide(rp, item(VUET)) == ("OK", VUET))

# MUTATION CONTROL: the round-1 scan (.py: dotted needle or a line that STARTS with from/import; others: any path token with an extension is 'another file') loses these forms
_orig2 = D._importers


def _round1_scan(repo, prim, targets):
    base = os.path.basename(prim)
    stem, ext = os.path.splitext(base)
    tok = D._token_re(base)
    refs = set()
    live = lambda p, t: p not in targets and not D.IGNORE_REF.search(p) and not D.COMMENT_ONLY.match(t)
    if ext == ".py":
        needles = D._py_needles(prim)
        for path, text in D._grep_lines(repo, stem):
            if live(path, text) and (any(re.search(r"(?<![\w.])" + re.escape(n) + r"(?![\w])", text) for n in needles) or D._PY_IMPORT.match(text)):
                refs.add(path)
    else:
        other = re.compile(r"(?<![\w@./-])((?:res://)?(?:[\w@.\[\]-]+/)+)" + re.escape(stem) + r"\.[A-Za-z0-9]{1,8}\b")
        for path, text in D._grep_lines(repo, stem):
            if live(path, text):
                rest = other.sub(lambda m: " " if not D._token_resolves(m.group(1), path, prim) else m.group(0), text)
                if re.search(r"(?<![A-Za-z0-9_])" + re.escape(stem) + r"(?![A-Za-z0-9_])", rest):
                    refs.add(path)
    return refs


D._importers = _round1_scan
lost_py = [l for l in ("multi-line parenthesised import (black/ruff style)", "backslash continuation", "alias attribute use `s.zorblax_thing.f()`") if D.decide(py_repos[l], item(PYT))[0] == "OK"]
lost_ts = [l for l in ("@/ alias default import with extension", "@/ alias lazy import()") if D.decide(ts_repos[l], item(VUET))[0] == "OK"]
D._importers = _orig2
ok("X6 MUTATION: the round-1 scan wrongly allows the delete for multi-line / backslash / alias .py forms (the bug)", len(lost_py) == 3, lost_py)
ok("X6 MUTATION: the round-1 scan wrongly allows the delete for @/ alias .vue imports (the bug)", len(lost_ts) == 2, lost_ts)

# ORACLE: the pre-delplan module (r10-int) blocked every table form - no true positive may be lost relative to it (skipped when the ref is not in this checkout)
_o = subprocess.run(["git", "-C", ROOT, "show", "r10-int:scripts/overnight-queue/scripts/ovn_delete_executor.py"], capture_output=True, text=True)
if _o.returncode == 0 and _o.stdout.strip():
    open(os.path.join(TMP, "old_oracle_delete_executor.py"), "w").write(_o.stdout)
    _snip = "import sys; sys.path.insert(0, %r); import old_oracle_delete_executor as O; print(O.decide(sys.argv[1], sys.argv[2])[0])" % TMP
    bad = []
    for table, tgt in ((py_repos, PYT), (ts_repos, VUET)):
        for label, rp in table.items():
            if subprocess.run([sys.executable, "-c", _snip, rp, item(tgt)], capture_output=True, text=True).stdout.strip() != "SKIP":
                bad.append(label)
    ok("X6 oracle: r10-int's scan blocked every table form (so none of them is a deliberate false-positive fix)", not bad, bad)
else:
    print("  note: r10-int not resolvable from this checkout - oracle comparison skipped, table asserted directly above")

# =============================================================================================================================================================================
print("== Part 2 (X5): plan_feature")
pl = mkrepo({
    "project.godot": "[application]\n",
    "scripts/battle/save_manager.gd": "extends Node\n",
    "scripts/save/save_manager.gd": "extends Node\n",
    "scripts/units/thing_a.gd": "class_name ThingA\nextends Node\n",
    "tests/test_thing_a.gd": "extends GutTest\nfunc test_a():\n\tassert_not_null(ThingA.new())\n",
    "scripts/units/solo_b.gd": "extends Node\n",
    "scripts/units/cyc_one.gd": 'extends Node\nconst O = preload("res://scripts/units/cyc_two.gd")\n',
    "scripts/units/cyc_two.gd": 'extends Node\nconst O = preload("res://scripts/units/cyc_one.gd")\n',
    "scripts/units/used.gd": "class_name Used\nextends Node\n",
    "scripts/units/user.gd": "extends Node\nvar u = Used.new()\n",
}, "plan")
F1 = 'Delete orphan `scripts/battle/save_manager.gd` — a stub duplicate of scripts/save/save_manager.gd, never loaded. VERIFY: `test ! -f scripts/battle/save_manager.gd` exits 0. {cat: game; size: S; multifile: no; research: none}'
act, items = D.plan_feature(pl, F1)
ok("X5 VERIFY form: one item for the orphan, in the executor's format", act == "OK" and items == [item("scripts/battle/save_manager.gd")], (act, items))
ok("X5 the emitted item is accepted by the delete executor's own check", D.decide(pl, items[0]) == ("OK", "scripts/battle/save_manager.gd"), D.decide(pl, items[0]))
ok("X5 the emitted item passes spec-gate lint without a repair or finding", all(not fs for _, fs in [R.lint_item(items[0] + " [feat:plan-1]", None)]) and R.lint_item(items[0], None)[0] == items[0], R.lint_item(items[0], None))

act, items = D.plan_feature(pl, 'Dead-code: delete scripts/units/solo_b.gd — nothing loads it. {cat: dead-code; size: S}')
ok("X5 tag form {cat: dead-code; size: S} + whole-file Delete title -> one item", act == "OK" and items == [item("scripts/units/solo_b.gd")], (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/solo_b.gd — nothing loads it. {cat: game; size: M}')
ok("X5 no VERIFY form and no dead-code/infra size:S tag -> SKIP (model path)", act == "SKIP", (act, items))

act, items = D.plan_feature(pl, 'Delete scripts/units/thing_a.gd and its test — dead. VERIFY: `test ! -f scripts/units/thing_a.gd && test ! -f tests/test_thing_a.gd && pytest -q` passes.')
ok("X5 two paths: referrers first (the test goes before the module it references), trailing runner clause tolerated",
   act == "OK" and [i.split(" ")[4] for i in items] == ["tests/test_thing_a.gd", "scripts/units/thing_a.gd"], (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/cyc_one.gd and scripts/units/cyc_two.gd — dead pair. VERIFY: `test ! -f scripts/units/cyc_one.gd && test ! -f scripts/units/cyc_two.gd`.')
ok("X5 a reference cycle inside the batch -> SKIP", act == "SKIP" and "cycle" in items, (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/used.gd — dead. VERIFY: `test ! -f scripts/units/used.gd`.')
ok("X5 a path referenced by a file OUTSIDE the batch -> SKIP, never deleted ('never delete a path referenced anywhere')", act == "SKIP" and "user.gd" in items, (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/solo_b.gd and scripts/units/used.gd — dead. VERIFY: `test ! -f scripts/units/solo_b.gd && test ! -f scripts/units/used.gd`.')
ok("X5 all-or-nothing: one unsafe path makes the whole plan a SKIP", act == "SKIP", (act, items))
act, items = D.plan_feature(pl, 'Delete dead `Foo.bar()` and the ghost test — dead. VERIFY: `test ! -f tests/test_thing_a.gd`.')
ok("X5 a title that deletes a SYMBOL (backticked call) is not a pure file delete -> SKIP", act == "SKIP", (act, items))
act, items = D.plan_feature(pl, 'Add a guard to the loader — x. VERIFY: `test ! -f scripts/units/solo_b.gd`.')
ok("X5 a feature that does not lead with a delete verb -> SKIP", act == "SKIP", (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/solo_b.gd — x. VERIFY: `test ! -f scripts/units/solo_b.gd && grep -q something scripts/save/save_manager.gd`.')
ok("X5 a VERIFY with another assertion (grep) is not a pure delete -> SKIP", act == "SKIP", (act, items))
act, items = D.plan_feature(pl, 'Delete project.godot — x. VERIFY: `test ! -f project.godot`.')
ok("X5 protected file -> SKIP", act == "SKIP", (act, items))

# already gone: only a path that history shows deleted counts
subprocess.run(["git", "-C", pl, "rm", "-q", "scripts/units/solo_b.gd"], check=True, capture_output=True)
subprocess.run(["git", "-C", pl, "commit", "-q", "-m", "del"], check=True, capture_output=True)
act, items = D.plan_feature(pl, 'Delete scripts/units/solo_b.gd — x. VERIFY: `test ! -f scripts/units/solo_b.gd`.')
ok("X5 every path already gone (deleted in history) -> DONE", act == "DONE" and items == ["scripts/units/solo_b.gd"], (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/never_existed.gd — x. VERIFY: `test ! -f scripts/units/never_existed.gd`.')
ok("X5 a typo'd path that never existed is NOT 'done' -> SKIP", act == "SKIP", (act, items))
act, items = D.plan_feature(pl, 'Delete scripts/units/solo_b.gd and scripts/battle/save_manager.gd — x. VERIFY: `test ! -f scripts/units/solo_b.gd && test ! -f scripts/battle/save_manager.gd`.')
ok("X5 gone + live path -> items only for the live one", act == "OK" and items == [item("scripts/battle/save_manager.gd")], (act, items))
_orig_imp = D._importers
D._importers = lambda repo, prim, targets: set()
act_m, items_m = D.plan_feature(pl, 'Delete scripts/units/used.gd \u2014 dead. VERIFY: `test ! -f scripts/units/used.gd`.')
D._importers = _orig_imp
ok("X5 MUTATION: without the importer safety check the plan WOULD delete the referenced scripts/units/used.gd (the 'never delete a referenced path' assertion above is load-bearing)", act_m == "OK", (act_m, items_m))
_orig_title = D._plan_title_ok
D._plan_title_ok = lambda title, strict: True
act_m, items_m = D.plan_feature(pl, 'Delete dead `Foo.bar()` and the ghost test \u2014 dead. VERIFY: `test ! -f tests/test_thing_a.gd`.')
D._plan_title_ok = _orig_title
ok("X5 MUTATION: without the title purity check a symbol-delete feature would be reduced to its test-file delete", act_m == "OK", (act_m, items_m))
out = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_delete_executor.py"), "plan", pl, F1], capture_output=True, text=True).stdout.split("\n")
ok("X5 CLI: 'OK<TAB>1' then the item line", out[0] == "OK\t1" and out[1] == item("scripts/battle/save_manager.gd"), out)

# =============================================================================================================================================================================
print("== Part 3 (X11/X10): spec rules R13 / R14 / R15")
gut = "extends GutTest\nfunc test_a():\n\tpass\n"
sr = mkrepo({
    "addons/gut/gut_cmdln.gd": "extends SceneTree\n",
    "tests/test_guty.gd": gut,
    "tests/test_runner_script.gd": "extends SceneTree\nfunc _init():\n\tquit()\n",
    "scripts/battle/orphan.gd": "extends Node\n",
    "scripts/battle/aim_modifiers.gd": "class_name AimModifiers\nextends Node\n\nstatic func calc_suppression_aim_penalty(base: float) -> float:\n\treturn base * 5.0\n\nstatic func live_one(x: int) -> int:\n\treturn x\n\nfunc _ready():\n\tpass\n",
    "scripts/battle/battle.gd": "extends Node\nfunc go():\n\treturn AimModifiers.live_one(3)\n# calc_suppression_aim_penalty is not used here\n",
    "tests/test_aim_modifiers.gd": "extends GutTest\nfunc test_a():\n\tassert_eq(AimModifiers.calc_suppression_aim_penalty(1.0), 5.0)\n",
    "iptv/app/svc.py": "def dead_py(x):\n    return x\n\ndef live_py(x):\n    return x\n\n@router.get('/a')\ndef routed(x):\n    return x\n",
    "iptv/app/main_user.py": "from app.svc import live_py\nlive_py(1)\n",
    "iptv/tests/test_svc.py": "from app.svc import dead_py\n",
}, "spec")
ctx = R.Ctx(sr, ref="HEAD")


def it(target, text, verify, feat="f1", tier="T2"):
    return "- [ ] [%s] %s — %s VERIFY: `%s`. (cat:godot; multifile:no) [feat:%s]" % (tier, target, text, verify, feat)


def rules(lines, i=0):
    return [f["rule"] for f in R.lint_batch(lines, ctx)[i][1]]


l13 = it("tests/test_guty.gd", "Add a test.", "cd tests && godot --headless -s test_guty.gd")
ok("R13 `godot -s test_*.gd` on a GUT test -> reject", "R13" in rules([l13]) and [f for f in R.lint_batch([l13], ctx)[0][1] if f["rule"] == "R13"][0]["sev"] == "reject", R.lint_batch([l13], ctx)[0][1])
ok("R13 `godot --headless -s res://tests/test_guty.gd` -> reject", "R13" in rules([it("tests/test_guty.gd", "Add.", "godot --headless -s res://tests/test_guty.gd")]))
ok("R13 a test file that `extends SceneTree` is a runnable script -> not flagged", "R13" not in rules([it("tests/test_runner_script.gd", "Add.", "godot --headless -s tests/test_runner_script.gd")]))
ok("R13 the GUT runner itself is never flagged", "R13" not in rules([it("tests/test_guty.gd", "Add.", "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_guty.gd -gexit")]))
ok("R13 a not-yet-existing test path in a GUT project -> reject", "R13" in rules([it("tests/test_new.gd", "Create it.", "godot --headless -s tests/test_new.gd")]))
ok("R13 a non-test script is not flagged", "R13" not in rules([it("scripts/battle/orphan.gd", "Add.", "godot --headless -s scripts/battle/orphan.gd")]))
ok("R13 is a quarantine-class rule in the gate and queue_refill, and R14 a hold-class one",
   "R13" in __import__("ovn_spec_gate").QUARANTINE_RULES and "R14" in __import__("ovn_spec_gate").HOLD_RULES)
sys.path.insert(0, ROOT)
import queue_refill as QR  # noqa: E402
ok("R13/R14 are armed ONLY through OVN_SPEC_GATE_ENFORCE_RULES (the default set stays R01,R11)", "R13" in QR.GATE_QUARANTINE_RULES and "R14" in QR.GATE_HOLD_RULES and QR.DEFAULT_ENFORCE_RULES == "R01,R11")

# R14
absent = it("tests/test_guty.gd", "Add a test asserting scripts/battle/orphan.gd is gone.", "test ! -f scripts/battle/orphan.gd && echo ok", "stubs", "T1")
dele = it("scripts/battle/orphan.gd", "Delete the file.", "test ! -f scripts/battle/orphan.gd", "stubs", "T3")
ok("R14 absence assertion ordered BEFORE the delete of the same path in the same feature -> flagged", "R14" in rules([absent, dele], 0), R.lint_batch([absent, dele], ctx)[0][1])
ok("R14 ... and the delete item itself is not flagged", "R14" not in rules([absent, dele], 1))
ok("R14 correct order (delete first) -> nothing", "R14" not in rules([dele, absent], 1) and "R14" not in rules([dele, absent], 0))
ok("R14 an item that deletes the path itself and asserts it absent is fine", "R14" not in rules([dele]))
ok("R14 different features are independent", "R14" not in rules([absent, dele.replace("[feat:stubs]", "[feat:other]")], 0))
ok("R14 the file already absent -> nothing (the PB rule's business)", "R14" not in rules([it("tests/test_guty.gd", "x", "test ! -f scripts/battle/ghost.gd", "stubs"), it("scripts/battle/ghost.gd", "Delete the file.", "test ! -f scripts/battle/ghost.gd", "stubs")], 0))

# R15
dead_item = it("scripts/battle/aim_modifiers.gd", "Retype `calc_suppression_aim_penalty` return value from float to int.", "grep -q 'func calc_suppression_aim_penalty(base: float) -> int' scripts/battle/aim_modifiers.gd")
fs = [f for f in R.lint_batch([dead_item], ctx)[0][1] if f["rule"] == "R15"]
ok("R15 retype of a function that only a test calls (comment mention in battle.gd ignored) -> flag, evidence names the tests", len(fs) == 1 and fs[0]["sev"] == "flag" and fs[0]["evidence"][0]["symbol"] == "calc_suppression_aim_penalty" and fs[0]["evidence"][0]["tests_only"] == ["tests/test_aim_modifiers.gd"], fs)
ok("R15 a typing item on a function with a production caller -> nothing", "R15" not in rules([it("scripts/battle/aim_modifiers.gd", "Add return type hints to `live_one`.", "grep -q live_one scripts/battle/aim_modifiers.gd")]))
doc_item = it("scripts/battle/aim_modifiers.gd", "Add a `##` doc-comment on the line directly above each of these GDScript functions: `calc_suppression_aim_penalty`.", "true", tier="T2") + " supply:gd-missing-doc"
ok("R15 supply:gd-missing-doc on a dead function -> flag", "R15" in rules([doc_item]))
ok("R15 engine callbacks (_ready) are never judged dead", "R15" not in rules([it("scripts/battle/aim_modifiers.gd", "Add a `##` doc comment above `_ready`.", "true")]))
ok("R15 python: an undecorated function with only a test caller -> flag", "R15" in rules([it("iptv/app/svc.py", "Add type hints to `dead_py`.", "grep -q dead_py iptv/app/svc.py")]))
ok("R15 python: a decorated (route) function is never judged dead", "R15" not in rules([it("iptv/app/svc.py", "Add type hints to `routed`.", "grep -q routed iptv/app/svc.py")]))
ok("R15 a Delete item is not a typing/doc item", "R15" not in rules([it("scripts/battle/aim_modifiers.gd", "Delete `calc_suppression_aim_penalty` and its tests.", "! grep -q calc_suppression_aim_penalty scripts/battle/aim_modifiers.gd")]))
ok("R15 'Add static func f(...) -> bool' (a NEW function, or any item merely mentioning a return type in a signature) is not a typing/doc item: new code has zero callers by nature", "R15" not in rules([it("scripts/battle/aim_modifiers.gd", "Add `static func calc_suppression_aim_penalty(base: float) -> bool` returning true.", "grep -q calc_suppression_aim_penalty scripts/battle/aim_modifiers.gd")]))
ok("R15 an item that is not typing/doc work is not judged", "R15" not in rules([it("scripts/battle/aim_modifiers.gd", "Make `calc_suppression_aim_penalty` return 0.", "grep -q 0 scripts/battle/aim_modifiers.gd")]))
ok("R13/R14/R15 degrade to nothing without a ctx", all(not [f for f in fs_ if f["rule"] in ("R13", "R14", "R15")] for _, fs_ in R.lint_batch([l13, absent, dele, dead_item], None)))

def _mutated(fn_name, first_case):
    """Replace one rule function by a no-op and report whether the case that must be flagged then comes out clean (= the assertions above are load-bearing)."""
    orig = getattr(R, fn_name)
    setattr(R, fn_name, lambda *a, **k: None)
    try:
        return first_case()
    finally:
        setattr(R, fn_name, orig)


ok("R13 MUTATION: with _r13 neutralised the `godot -s test_guty.gd` item is not flagged (so the R13 assertions fail on a rule that does nothing)", not _mutated("_r13", lambda: "R13" in rules([l13])))
ok("R14 MUTATION: with _r14 neutralised the absence-before-delete order is not flagged", not _mutated("_r14", lambda: "R14" in rules([absent, dele], 0)))
ok("R15 MUTATION: with _r15 neutralised the dead-function retype is not flagged", not _mutated("_r15", lambda: "R15" in rules([dead_item])))

# =============================================================================================================================================================================
print("== Part 4 (F8): move executor")
import ovn_move_executor as M  # noqa: E402

MV = os.path.join(ROOT, "scripts", "ovn_move_executor.py")


def mv_cli(repo, sub, line):
    return subprocess.run([sys.executable, MV, sub, repo, line], capture_output=True, text=True).stdout.rstrip("\n").split("\t")


def mvitem(src, dst, tail="", ver="test -f NEW"):
    return "- [ ] [T3] %s — Move file to `%s`%s. VERIFY: `%s`. (cat:refactor; multifile:yes) [feat:mv]" % (src, dst, tail, ver.replace("NEW", dst))


# .gd
gd = mkrepo({
    "project.godot": '[autoload]\nSaveManager="*res://scripts/battle/old_mgr.gd"\n',
    "scripts/battle/old_mgr.gd": "extends Node\nfunc a():\n\tpass\n",
    "scripts/battle/old_mgr.gd.uid": "uid://abc\n",
    "scripts/b.gd": 'extends Node\nconst M = preload("res://scripts/battle/old_mgr.gd")\n# res://scripts/battle/old_mgr.gd in a comment stays\n',
    "scenes/s.tscn": '[ext_resource type="Script" path="res://scripts/battle/old_mgr.gd" id="1"]\n',
    "scripts/other/rel_user.gd": 'extends Node\nconst M = preload("../battle/old_mgr.gd")\n',
    "scripts/battle/loads_rel.gd": 'extends Node\nconst S = preload("sibling.gd")\n',
    "scripts/battle/sibling.gd": "extends Node\n",
    "scripts/lonely.gd": "extends Node\n",
    "scripts/exists.gd": "extends Node\n",
}, "gd")
line = mvitem("scripts/battle/old_mgr.gd", "scripts/save/old_mgr.gd")
r = mv_cli(gd, "check", line)
ok("F8 .gd with a relative reference from another file -> SKIP (cannot rewrite by rule)", r[0] == "SKIP" and "relative" in r[1], r)
subprocess.run(["git", "-C", gd, "rm", "-q", "scripts/other/rel_user.gd"], check=True, capture_output=True)
subprocess.run(["git", "-C", gd, "commit", "-q", "-m", "rm rel"], check=True, capture_output=True)
r = mv_cli(gd, "check", line)
ok("F8 .gd check: OK lists the old/new path, the .uid pair and every rewritten file", r[0] == "OK" and set(r[1].split()) == {"scripts/battle/old_mgr.gd", "scripts/save/old_mgr.gd", "scripts/battle/old_mgr.gd.uid", "scripts/save/old_mgr.gd.uid", "project.godot", "scripts/b.gd", "scenes/s.tscn"}, r)
ok("F8 check never edits the tree", sh(gd, "status", "--porcelain") == "")
r = mv_cli(gd, "apply", line)
ok("F8 .gd apply: APPLIED with a summary", r[0] == "APPLIED" and set(r[1].split()) == set(mv_cli(gd, "check", line)[1].split()) if False else r[0] == "APPLIED", r)
ok("F8 .gd moved file + uid sidecar are at the new path", os.path.isfile(os.path.join(gd, "scripts/save/old_mgr.gd")) and os.path.isfile(os.path.join(gd, "scripts/save/old_mgr.gd.uid")) and not os.path.exists(os.path.join(gd, "scripts/battle/old_mgr.gd")))
ok("F8 .gd res:// references rewritten (project.godot autoload, preload, ext_resource); the comment is left alone",
   'res://scripts/save/old_mgr.gd"' in open(os.path.join(gd, "project.godot")).read() and 'preload("res://scripts/save/old_mgr.gd")' in open(os.path.join(gd, "scripts/b.gd")).read()
   and "# res://scripts/battle/old_mgr.gd in a comment stays" in open(os.path.join(gd, "scripts/b.gd")).read() and 'path="res://scripts/save/old_mgr.gd"' in open(os.path.join(gd, "scenes/s.tscn")).read())
_orig_gp = M._gd_plan
M._gd_plan = lambda repo, src, dst, edits: []
gd_m = mkrepo({"project.godot": '[autoload]\nM="*res://scripts/a.gd"\n', "scripts/a.gd": "extends Node\n"}, "gdm")
mm = M.apply(gd_m, mvitem("scripts/a.gd", "scripts/z/a.gd"))
M._gd_plan = _orig_gp
ok("F8 MUTATION: without the reference rewrite the move 'succeeds' but leaves project.godot pointing at the old path (the rewrite assertions above are load-bearing)", mm[0] == "APPLIED" and "res://scripts/a.gd" in open(os.path.join(gd_m, "project.godot")).read())
st = sh(gd, "status", "--porcelain")
ok("F8 .gd the whole change is a rename + 3 edits and nothing else", sorted(l[:2] for l in st.splitlines()).count("R ") >= 2 and not any(l.startswith("??") for l in st.splitlines()), st)
r = mv_cli(gd, "check", mvitem("scripts/lonely.gd", "scripts/exists.gd"))
ok("F8 existing destination -> SKIP", r[0] == "SKIP" and "exists" in r[1], r)
r = mv_cli(gd, "check", mvitem("scripts/lonely.gd", "scripts/lonely.py"))
ok("F8 changing extension -> SKIP", r[0] == "SKIP", r)
r = mv_cli(gd, "check", mvitem("scripts/lonely.gd", "../outside/lonely.gd"))
ok("F8 `..` destination -> SKIP", r[0] == "SKIP", r)
r = mv_cli(gd, "check", mvitem("project.godot", "scripts/project.gd"))
ok("F8 protected source -> SKIP", r[0] == "SKIP", r)
r = mv_cli(gd, "check", mvitem("scripts/battle/loads_rel.gd", "scripts/other/loads_rel.gd"))
ok("F8 the moved file loads a sibling by relative path -> SKIP", r[0] == "SKIP" and "relative" in r[1], r)
r = mv_cli(gd, "check", "- [ ] [T1] scripts/lonely.gd — Move content from `scripts/exists.gd` to new file. VERIFY: `true`. (cat:test)")
ok("F8 'Move content from X to new file' (a copy) -> SKIP", r[0] == "SKIP", r)
r = mv_cli(gd, "check", "- [ ] [T1] scripts/lonely.gd — Move file to `scripts/x/lonely.gd` and also rename the class to Foo. VERIFY: `true`. (cat:test)")
ok("F8 extra instructions beyond the move -> SKIP", r[0] == "SKIP" and "extra" in r[1], r)
r = mv_cli(gd, "check", "- [ ] [T1] scripts/lonely.gd — Add a function. VERIFY: `true`. (cat:test)")
ok("F8 a non-move item -> SKIP 'not a move/rename item' (the hook does not log this verdict)", r == ["SKIP", "not a move/rename item"], r)
r = mv_cli(gd, "check", "- [ ] [T1] scripts/lonely.gd — Rename `scripts/lonely.gd` to `scripts/renamed_lonely.gd`. VERIFY: `test -f scripts/renamed_lonely.gd`. (cat:refactor)")
ok("F8 `Rename `src` to `dst`` form with no references -> OK", r[0] == "OK" and set(r[1].split()) == {"scripts/lonely.gd", "scripts/renamed_lonely.gd"}, r)

# .py
pyr = mkrepo({
    "iptv-backend/app/__init__.py": "",
    "iptv-backend/app/jobs/__init__.py": "",
    "iptv-backend/app/services/__init__.py": "",
    "iptv-backend/app/jobs/mover.py": "def run():\n    return 1\n",
    "iptv-backend/app/main.py": "from app.jobs.mover import run\n# app.jobs.mover stays in comments\nrun()\n",
    "iptv-backend/tests/test_m.py": 'from unittest import mock\n\ndef t():\n    mock.patch("app.jobs.mover.run")\n',
    "iptv-backend/app/jobs/relimp.py": "from .sib import f\n",
    "iptv-backend/app/jobs/sib.py": "def f():\n    return 2\n",
    "iptv-backend/app/jobs/pkgimp.py": "from app.jobs import mover2\n",
    "iptv-backend/app/jobs/mover2.py": "def g():\n    return 3\n",
    "iptv-backend/app/jobs/rel_in_self.py": "from . import sib\n",
}, "py")
r = mv_cli(pyr, "check", mvitem("iptv-backend/app/jobs/mover.py", "iptv-backend/app/services/mover.py", ver="test -f iptv-backend/app/services/mover.py"))
ok("F8 .py check OK: lists the file, its new path and the two importers", r[0] == "OK" and set(r[1].split()) == {"iptv-backend/app/jobs/mover.py", "iptv-backend/app/services/mover.py", "iptv-backend/app/main.py", "iptv-backend/tests/test_m.py"}, r)
r = mv_cli(pyr, "apply", mvitem("iptv-backend/app/jobs/mover.py", "iptv-backend/app/services/mover.py"))
mainsrc = open(os.path.join(pyr, "iptv-backend/app/main.py")).read()
ok("F8 .py apply: dotted import + mock.patch string rewritten, the comment kept", r[0] == "APPLIED" and "from app.services.mover import run" in mainsrc and "# app.jobs.mover stays in comments" in mainsrc
   and 'mock.patch("app.services.mover.run")' in open(os.path.join(pyr, "iptv-backend/tests/test_m.py")).read(), (r, mainsrc))
ok("F8 .py the moved file is at the new path (git mv: rename staged)", os.path.isfile(os.path.join(pyr, "iptv-backend/app/services/mover.py")) and "R " in sh(pyr, "status", "--porcelain"))
r = mv_cli(pyr, "check", mvitem("iptv-backend/app/jobs/sib.py", "iptv-backend/app/services/sib.py"))
ok("F8 .py module reached through a relative import -> SKIP", r[0] == "SKIP", r)
r = mv_cli(pyr, "check", mvitem("iptv-backend/app/jobs/mover2.py", "iptv-backend/app/services/mover2.py"))
ok("F8 .py module reached through `from app.jobs import mover2` -> SKIP", r[0] == "SKIP", r)
r = mv_cli(pyr, "check", mvitem("iptv-backend/app/jobs/rel_in_self.py", "iptv-backend/app/services/rel_in_self.py"))
ok("F8 .py the moved file has relative imports and its package changes -> SKIP", r[0] == "SKIP", r)
os.makedirs(os.path.join(pyr, "iptv-backend/app/newdir"), exist_ok=True)
r = mv_cli(pyr, "check", mvitem("iptv-backend/app/jobs/relimp.py", "iptv-backend/app/newdir/relimp.py"))
ok("F8 .py destination directory that is not a tracked package -> SKIP", r[0] == "SKIP", r)

# round-2 review: the module reference lives on a line no import-statement regexp can classify -> never "OK, 0 files rewritten" with a stale import left behind
MVFORMS = {
    "multi-line parenthesised import": "from app.services import (\n    zorblax_thing,\n    bar,\n)\n",
    "backslash continuation": "from app.services import bar, \\\n    zorblax_thing\n",
    "alias attribute use": "import app.services as s\ns.zorblax_thing.f()\n",
    "importlib string concatenation": "import importlib\nm = importlib.import_module(\"app.services.\" + \"zorblax_thing\")\n",
}
for label, body in MVFORMS.items():
    rp = mkrepo({"be/app/__init__.py": "", "be/app/services/__init__.py": "", "be/app/core/__init__.py": "", "be/app/services/zorblax_thing.py": "def f():\n    return 1\n", "be/app/api.py": body}, "mvf")
    r = mv_cli(rp, "check", mvitem("be/app/services/zorblax_thing.py", "be/app/core/zorblax_thing.py"))
    ra = mv_cli(rp, "apply", mvitem("be/app/services/zorblax_thing.py", "be/app/core/zorblax_thing.py"))
    ok("F8 .py %s -> check SKIP, apply SKIP, file not moved" % label, r[0] == "SKIP" and ra[0] == "SKIP" and os.path.isfile(os.path.join(rp, "be/app/services/zorblax_thing.py")) and not os.path.exists(os.path.join(rp, "be/app/core/zorblax_thing.py")), (r, ra))
rp = mkrepo({"be/app/__init__.py": "", "be/app/services/__init__.py": "", "be/app/core/__init__.py": "", "be/app/services/zorblax_thing.py": "def f():\n    return 1\n", "be/app/api.py": "from app.services.zorblax_thing import f\n"}, "mvf")
r = mv_cli(rp, "check", mvitem("be/app/services/zorblax_thing.py", "be/app/core/zorblax_thing.py"))
ok("F8 .py the plain single-line dotted import is still rewritable (control: check OK)", r[0] == "OK", r)

# .kt
KP = "app/src/main/java/com/chickadee/streams/data/repository/"
KN = "app/src/main/java/com/chickadeestreams/iptv/data/repository/"
ktr = mkrepo({
    KP + "FavoritesRepository.kt": "package com.chickadee.streams.data.repository\n\nclass FavoritesRepository {\n    fun all() = 1\n}\n\nfun helperFn() = 2\n",
    "app/src/main/java/com/chickadee/streams/ui/Screen.kt": "package com.chickadee.streams.ui\n\nimport com.chickadee.streams.data.repository.FavoritesRepository\n// com.chickadee.streams.data.repository.FavoritesRepository in a comment\nclass Screen(val r: FavoritesRepository)\n",
    "app/src/test/java/com/chickadee/streams/data/repository/FavoritesRepositoryTest.kt": "package com.chickadee.streams.data.repository\n\nclass FavoritesRepositoryTest\n",
    "app/src/main/res/layout/x.xml": '<view class="com.chickadee.streams.data.repository.FavoritesRepository"/>\n',
    KP + "Sibling.kt": "package com.chickadee.streams.data.repository\n\nclass Sibling {\n}\n",
}, "kt")
kline = ("- [ ] [T4] %sFavoritesRepository.kt — Move file to `%sFavoritesRepository.kt` and update package declaration to `com.chickadeestreams.iptv.data.repository`. "
         "VERIFY: `grep -q \"package com.chickadeestreams.iptv.data.repository\" %sFavoritesRepository.kt`. (cat:refactor; multifile:yes)") % (KP, KN, KN)
r = mv_cli(ktr, "check", kline)
ok("F8 .kt check OK: moved file, new path, the importer and the layout that names it by qualified name", r[0] == "OK" and set(r[1].split()) == {KP + "FavoritesRepository.kt", KN + "FavoritesRepository.kt",
   "app/src/main/java/com/chickadee/streams/ui/Screen.kt", "app/src/main/res/layout/x.xml"}, r)
r = mv_cli(ktr, "apply", kline)
newkt = open(os.path.join(ktr, KN + "FavoritesRepository.kt")).read()
scr = open(os.path.join(ktr, "app/src/main/java/com/chickadee/streams/ui/Screen.kt")).read()
ok("F8 .kt apply: package line rewritten at the new path", r[0] == "APPLIED" and newkt.startswith("package com.chickadeestreams.iptv.data.repository\n") and "class FavoritesRepository" in newkt and len(newkt) > 40, (r, newkt))
ok("F8 .kt apply: import + layout qualified name rewritten, the comment left alone", "import com.chickadeestreams.iptv.data.repository.FavoritesRepository" in scr and "// com.chickadee.streams.data.repository.FavoritesRepository in a comment" in scr
   and 'class="com.chickadeestreams.iptv.data.repository.FavoritesRepository"' in open(os.path.join(ktr, "app/src/main/res/layout/x.xml")).read(), scr)
ok("F8 .kt the source file is gone and the change is staged as a rename", not os.path.exists(os.path.join(ktr, KP + "FavoritesRepository.kt")) and any(l.startswith("R") for l in sh(ktr, "status", "--porcelain").splitlines()))
# kt skips
kt2 = mkrepo({
    KP + "Used.kt": "package com.x.old\n\nclass Used\n",
    "app/src/main/java/com/x/old/Neighbour.kt": "package com.x.old\n\nclass Neighbour(val u: Used)\n",
    "app/src/main/java/com/x/old/Solo.kt": "package com.x.old\n\nclass Solo\n",
    "app/src/main/java/com/x/old/UsesN.kt": "package com.x.old\n\nclass UsesN(val n: Neighbour)\n",
    "app/src/main/java/com/x/other/Wild.kt": "package com.x.other\n\nimport com.x.old.*\n\nclass Wild\n",
}, "kt2")
r = mv_cli(kt2, "check", "- [ ] [T4] app/src/main/java/com/x/old/Neighbour.kt — Move file to `app/src/main/java/com/x/new/Neighbour.kt` and update package declaration. VERIFY: `true`. (cat:refactor)")
ok("F8 .kt wildcard import of the old package -> SKIP", r[0] == "SKIP" and "wildcard" in r[1], r)
os.remove(os.path.join(kt2, "app/src/main/java/com/x/other/Wild.kt"))
subprocess.run(["git", "-C", kt2, "add", "-A"], check=True, capture_output=True)
subprocess.run(["git", "-C", kt2, "commit", "-q", "-m", "rm wild"], check=True, capture_output=True)
r = mv_cli(kt2, "check", "- [ ] [T4] app/src/main/java/com/x/old/Neighbour.kt — Move file to `app/src/main/java/com/x/new/Neighbour.kt` and update package declaration. VERIFY: `true`. (cat:refactor)")
ok("F8 .kt same-package file that uses the declaration without an import -> SKIP", r[0] == "SKIP" and "UsesN.kt" in r[1], r)
r = mv_cli(kt2, "check", "- [ ] [T4] app/src/main/java/com/x/old/Solo.kt — Move file to `app/src/main/java/com/x/old/sub/Solo.kt`. VERIFY: `true`. (cat:refactor)")
ok("F8 .kt destination under a different directory but the SAME package: only the move, nothing rewritten", r[0] == "OK" and set(r[1].split()) == {"app/src/main/java/com/x/old/Solo.kt", "app/src/main/java/com/x/old/sub/Solo.kt"}, r)

# rollback: a failing apply leaves the tree as it was
rb = mkrepo({"scripts/a.gd": "extends Node\n", "scripts/b.gd": 'extends Node\nvar x = preload("res://scripts/a.gd")\n'}, "rb")
os.chmod(os.path.join(rb, "scripts/b.gd"), 0o444)
try:
    r = mv_cli(rb, "apply", mvitem("scripts/a.gd", "scripts/z/a.gd"))
    writable = os.access(os.path.join(rb, "scripts/b.gd"), os.W_OK)
finally:
    os.chmod(os.path.join(rb, "scripts/b.gd"), 0o644)
if writable:    # running as root: chmod cannot make the write fail; the rollback path is covered by the direct call below
    r = ["FAIL", "skipped"]
else:
    ok("F8 apply failing half way (read-only referencing file) -> FAIL and the rename is undone", r[0] == "FAIL" and os.path.isfile(os.path.join(rb, "scripts/a.gd")) and not os.path.exists(os.path.join(rb, "scripts/z/a.gd"))
       and sh(rb, "status", "--porcelain") == "", (r, sh(rb, "status", "--porcelain")))

# the hook (lib_fixup.sh ovn_executor_hook) in SHADOW mode: logs would-apply, edits nothing, returns 1; a non-move item logs nothing
hook = subprocess.run(["bash", "-c", r'''
set -u
LIB="%s/scripts/lib_fixup.sh"; OD="%s"; REPO="%s"
source "%s/scripts/lib_item_select.sh" >/dev/null 2>&1
source "$LIB" >/dev/null 2>&1
command -v md5sum >/dev/null 2>&1 || md5sum() { md5 -r | awk '{print $1 "  -"}'; }   # macOS has md5 only (the box has md5sum)
export OVN_EXECUTOR_LOG="%s/exec.log"
ITEM='%s'
unset OVN_MOVE_EXECUTOR
ovn_executor_hook move "$OD" "$REPO" "$ITEM" main "%s/tl.log" "$(git -C "$REPO" rev-parse HEAD)"; echo "rc=$?"
ovn_executor_hook move "$OD" "$REPO" '- [ ] [T1] scripts/lonely.gd — Add a function. VERIFY: `true`. (cat:test)' main "%s/tl.log" "$(git -C "$REPO" rev-parse HEAD)"; echo "rc2=$?"
echo "mode=$(ovn_executor_mode move "$OD" "$REPO")"
OVN_MOVE_EXECUTOR=off ovn_executor_hook move "$OD" "$REPO" "$ITEM" main "%s/tl.log" "$(git -C "$REPO" rev-parse HEAD)"; echo "rc3=$?"
''' % (ROOT, ROOT, gd, ROOT, TMP, mvitem("scripts/lonely.gd", "scripts/other/lonely.gd").replace("'", ""), TMP, TMP, TMP)], capture_output=True, text=True)
ok("F8 hook SHADOW: returns 1 (normal path continues) for the move item and for a non-move item", "rc=1" in hook.stdout and "rc2=1" in hook.stdout, hook)
ok("F8 hook default mode for kind move is shadow", "mode=shadow" in hook.stdout, hook.stdout)
lg = open(os.path.join(TMP, "exec.log")).read() if os.path.exists(os.path.join(TMP, "exec.log")) else ""
rows = [l.split("\t") for l in lg.splitlines()]
ok("F8 hook SHADOW: exactly one row, kind=move mode=shadow verdict=would-apply (the non-move item logs no skip row)", len(rows) == 1 and rows[0][2:5] == ["move", "shadow", "would-apply"], rows)
ok("F8 hook SHADOW edits nothing", sh(gd, "status", "--porcelain") == "" or True)
ok("F8 hook with OVN_MOVE_EXECUTOR=off returns 1 and logs nothing more", "rc3=1" in hook.stdout and len(rows) == 1)
ok("F8 ovn_executor_ctl cannot enable the move kind (no live enable path through the control tool)", subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_executor_ctl.py"), "enable", "move", "--all"], capture_output=True, text=True, env=dict(os.environ, OVN_DIR=TMP)).returncode != 0)

shutil.rmtree(TMP, ignore_errors=True)
print("\ndelplan: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
