#!/usr/bin/env python3
"""scripts/ovn_retire_vague.py: Godot `.gd.uid` sidecar items (2026-10-09).

Real incident: `- [ ] [T1] scripts/roster/loadout_preset.gd.uid - Delete the orphaned file. VERIFY: test ! -f scripts/roster/loadout_preset.gd.uid`
matched SLASH_FILE/HAS_FILE as `scripts/roster/loadout_preset.gd` (EXT had no `uid`, the regex stopped at `.gd`). That .gd does not exist (the .uid is the
orphan by definition), so classify() returned 'dead-path' and five VALID delete items were retired. Now the .uid itself is the path that is checked.
Includes negative controls (the OLD extension list, and a wrong alternation order, reproduce the bug through the same assertions) and runs the
pre-existing retire suites."""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SCRIPTS)
import ovn_retire_vague as RV  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


ITEM = "- [ ] [T1] scripts/roster/loadout_preset.gd.uid — Delete the orphaned file. VERIFY: test ! -f scripts/roster/loadout_preset.gd.uid"
ITEM_NOVERIFY = "- [ ] [T1] scripts/roster/loadout_preset.gd.uid — Delete the orphaned file."
ITEM_TSCN_UID = "- [ ] [T1] scenes/menu/main.tscn.uid — Delete the orphaned file. VERIFY: test ! -f scenes/menu/main.tscn.uid"
ITEM_GD = "- [ ] [T2] scripts/roster/loadout_preset.gd — add a docstring. One file."


def in_tree(files, fn):
    old = os.getcwd()
    d = tempfile.mkdtemp(prefix="rv-")
    try:
        os.chdir(d)
        for rp, body in files.items():
            os.makedirs(os.path.dirname(rp) or ".", exist_ok=True)
            open(rp, "w").write(body)
        return fn()
    finally:
        os.chdir(old)


def battery(mod, tag):
    """The behaviour assertions, run against a module-like object (real, or a mutant). Returns the number of failed assertions."""
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)

    c = in_tree({"scripts/roster/loadout_preset.gd.uid": "uid://abc\n"}, lambda: mod.classify(ITEM))
    chk("uid exists -> kept (not dead-path, not gone)", c is None, c)
    c = in_tree({"scripts/roster/loadout_preset.gd.uid": "uid://abc\n"}, lambda: mod.classify(ITEM_NOVERIFY))
    chk("uid exists, no VERIFY clause -> kept", c is None, c)
    c = in_tree({"scripts/other.gd": "x\n"}, lambda: mod.classify(ITEM))
    chk("uid absent + own `test ! -f` VERIFY -> 'gone' (credited as already-done)", c == "gone", c)
    c = in_tree({"scripts/other.gd": "x\n"}, lambda: mod.classify(ITEM_NOVERIFY))
    chk("uid absent, no VERIFY -> dead-path (still retired)", c == "dead-path", c)
    c = in_tree({"scenes/menu/main.tscn.uid": "uid://x\n"}, lambda: mod.classify(ITEM_TSCN_UID))
    chk("tscn.uid exists -> kept", c is None, c)
    c = in_tree({"scenes/menu/other.tscn": "x\n"}, lambda: mod.classify(ITEM_TSCN_UID))
    chk("tscn.uid absent + VERIFY -> gone", c == "gone", c)
    c = in_tree({"scripts/roster/loadout_preset.gd": "extends Node\n", "scripts/roster/loadout_preset.gd.uid": "u\n"}, lambda: mod.classify(ITEM_GD))
    chk("existing .gd item still kept", c is None, c)
    return bad


# ---- real module ----
bad = battery(RV, "real")
ok("real module passes every .uid assertion", bad == 0, "failed=%d" % bad)


# ---- end-to-end through process(): the file on disk, kept vs credited ----
def e2e():
    open("Q.md", "w").write("# q\n" + ITEM + "\n")
    RV.process("Q.md")
    return open("Q.md").read()


out = in_tree({"scripts/roster/loadout_preset.gd.uid": "u\n"}, e2e)
ok("process(): item with an existing .uid stays an open `- [ ]` line", ITEM in out.splitlines() and "retired" not in out, out)
out = in_tree({"scripts/x.gd": "x\n"}, e2e)
ok("process(): item with an absent .uid is credited as already-done, not retired dead-path",
   "(already-done, target already absent)" in out and "(retired-dead-path)" not in out and "- [ ] [T1] scripts/roster/loadout_preset.gd.uid" not in out, out)

# ---- unchanged behaviour of the pre-existing classes ----
ok("vague item (no file) still vague", in_tree({}, lambda: RV.classify("- [ ] [T2] make the code cleaner and nicer")) == "vague")
ok("missing .py with a slash still dead-path", in_tree({}, lambda: RV.classify("- [ ] [T2] app/ghost.py — fix. One file.")) == "dead-path")
ok("create-intent item with a missing path still kept", in_tree({}, lambda: RV.classify("- [ ] [T2] Create a new app/fresh.py helper")) is None)
ok("prose `user.uid` is NOT treated as a file (no bare 'uid' extension)",
   in_tree({}, lambda: RV.classify("- [ ] [T2] rename the user.uid field everywhere")) == "vague")
ok("existing scene item .tscn present -> kept",
   in_tree({"scenes/a.tscn": "x"}, lambda: RV.classify("- [ ] [T2] scenes/a.tscn — tweak the root node. One file.")) is None)
ok("missing scene item .tscn (no create intent) -> dead-path",
   in_tree({}, lambda: RV.classify("- [ ] [T2] scenes/a.tscn — tweak the root node. One file.")) == "dead-path")

# ---- mutation / negative controls: the OLD extension list, and a wrong alternation order, must fail the same battery ----
src = open(os.path.join(SCRIPTS, "ovn_retire_vague.py")).read()
m = re.search(r'^EXT = r".*"$', src, re.M)
ok("found the EXT line to mutate", m is not None)
if m:
    old_ext = 'EXT = r"(py|vue|ts|tsx|js|jsx|kts|kt|gd|swift|gradle|toml|ya?ml|json|cfg|ini|sh|html|css|md|txt|env)"'
    ns = {"__name__": "mutant_old_ext"}
    exec(compile(src.replace(m.group(0), old_ext), "mutant_old_ext.py", "exec"), ns)

    class M:
        classify = staticmethod(ns["classify"])

    mb = battery(M, "mutant")
    ok("mutation: the OLD EXT (no .uid forms) fails the battery (%d assertion(s) bite)" % mb, mb > 0)

    swapped = 'EXT = r"(py|vue|ts|tsx|js|jsx|kts|kt|gd|gd\\.uid|tscn\\.uid|tres\\.uid|gdshader\\.uid|tscn|tres|swift|gradle|toml|ya?ml|json|cfg|ini|sh|html|css|md|txt|env)"'
    ns2 = {"__name__": "mutant_order"}
    exec(compile(src.replace(m.group(0), swapped), "mutant_order.py", "exec"), ns2)

    class M2:
        classify = staticmethod(ns2["classify"])

    mb2 = battery(M2, "mutant")
    ok("mutation: bare `gd` BEFORE `gd\\.uid` in the alternation fails the battery (%d bite)" % mb2, mb2 > 0)

# ---- the pre-existing retire suites stay green ----
for t in ("test_retire_prefix.sh", "test_h13_delete_already_gone.sh", "test_retired_filter.sh"):
    tp = os.path.join(HERE, t)
    if not os.path.exists(tp):
        continue
    r = subprocess.run(["bash", tp], capture_output=True, text=True, timeout=600)
    ok("existing suite %s exits 0" % t, r.returncode == 0, (r.stdout + r.stderr)[-300:])

print("retire_vague uid: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
