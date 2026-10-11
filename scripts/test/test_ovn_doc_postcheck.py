#!/usr/bin/env python3
"""scripts/ovn_doc_postcheck.py: the net-diff post-check for model-written supply:gd-missing-doc commits (2026-10-10, package docexec, analysis[6] BX-01).

Real git repos in a temp dir, no network, no model. The fixtures are the failure shapes measured on xlite 10-09/10-10: the `##` block that landed at the END of the file
(damage_preview.gd d54ffc7), the 'move doc comment above' cycle that only deleted the lines (0862c1b), a re-added whole `static func` line (loot_table.gd), the same comment
twice with an orphan between (mission_summary.gd) and a doc above @annotations (valid). Each verdict is relative to BASE (damage that already existed is never charged), and
the battery is then run against MUTATED copies of the tool: every mutant must make it fail."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(ROOT, "scripts")
TOOL = os.path.join(SCRIPTS, "ovn_doc_postcheck.py")
P = F = 0
QUIET = False


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        if not QUIET:
            print("  ok   " + name)
    else:
        F += 1
        if not QUIET:
            print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def git(d, *a):
    return subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t"] + list(a), capture_output=True, text=True, check=True).stdout.strip()


def item(names, path="scripts/battle/dp.gd", supply=True):
    tag = "; supply:gd-missing-doc" if supply else ""
    return ("- [ ] [T2] %s — Add a `##` doc-comment on each of these GDScript functions: %s. Comments only. VERIFY: `true`. (cat:godot; multifile:no%s) [feat:xlite-1-x]"
            % (path, ", ".join("`%s`" % n for n in names), tag))


BASE = ("extends RefCounted\n\nstatic func predicted_damage(base: int, cover: int, flanked: bool) -> int:\n\tvar d := base - cover\n\treturn d\n\n"
        "static func second(x):\n\tvar a = x\n\treturn a\n")
GOOD = BASE.replace("static func predicted_damage", "## Predicts damage.\nstatic func predicted_damage")


def run(tool, repo, base, head, it):
    r = subprocess.run([sys.executable, tool, "check", repo, base, head, it], capture_output=True, text=True, timeout=60, cwd=repo)
    return r.stdout.strip().split("\t")


def mkrepo(base_text, path="scripts/battle/dp.gd"):
    d = tempfile.mkdtemp(prefix="pc-")
    git(d, "init", "-q", ".")
    os.makedirs(os.path.join(d, os.path.dirname(path)), exist_ok=True)
    open(os.path.join(d, path), "w").write(base_text)
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "base")
    return d, git(d, "rev-parse", "HEAD")


def commit(d, text, path="scripts/battle/dp.gd"):
    open(os.path.join(d, path), "w").write(text)
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "c", "--allow-empty")
    return git(d, "rev-parse", "HEAD")


FIX = {}


def build():
    """Fixture repos are tool-independent: build each once, the battery (and every mutant run) only re-runs the tool against them."""
    names = ["predicted_damage"]
    def case(key, base_text, head_text, it, path="scripts/battle/dp.gd"):
        d, b = mkrepo(base_text, path)
        h = commit(d, head_text, path)
        FIX[key] = (d, b, h, it)
    case("good", BASE, GOOD, item(names))
    case("eof", BASE, BASE + "## Predicts damage.\n## Args: base.\n", item(names))
    case("deleted", BASE + "## Predicts damage.\n## Args: base.\n", BASE, item(names))
    case("dupfunc", BASE, GOOD + "\nstatic func predicted_damage(base: int, cover: int, flanked: bool) -> int:\n\treturn 0\n", item(names))
    twice = ("extends RefCounted\n\nvar x = 1\n\n## Builds a summary dictionary of the mission.\n\nvar y = 2\n## Builds a summary dictionary of the mission.\n"
             "static func predicted_damage(base: int, cover: int, flanked: bool) -> int:\n\tvar d := base - cover\n\treturn d\n\nstatic func second(x):\n\tvar a = x\n\treturn a\n")
    case("twice", BASE, twice, item(names))
    case("already", GOOD, GOOD + "\n# unrelated comment\n", item(names))
    base_a = "extends Node\n\nvar z = 1\n\n@rpc(\"any_peer\")\n@warning_ignore(\"unused_parameter\")\nfunc predicted_damage(a):\n\treturn a\n"
    case("annot", base_a, base_a.replace("@rpc", "## Doc above the annotations.\n@rpc", 1), item(names))
    pre = "extends RefCounted\n\nvar v = 1\n\n## old orphan\n\nvar w = 2\n"
    case("preexisting", pre + BASE.split("\n", 1)[1], pre + GOOD.split("\n", 1)[1], item(names))
    case("empty", BASE, BASE, item(names))
    case("two", BASE, GOOD, item(["predicted_damage", "second"]))
    case("gone", BASE, GOOD.replace("static func second(x):\n\tvar a = x\n\treturn a\n", ""), item(["predicted_damage", "second"]))
    d, b = mkrepo(BASE); git(d, "rm", "-q", "scripts/battle/dp.gd"); git(d, "commit", "-q", "-m", "rm")
    FIX["nofile"] = (d, b, git(d, "rev-parse", "HEAD"), item(names))
    base_v = BASE.replace("static func predicted_damage", "var v = 1\n\nstatic func predicted_damage")
    case("blank", base_v, base_v.replace("static func predicted_damage", "## Predicts damage.\n\nstatic func predicted_damage"), item(names))
    case("body", BASE, GOOD.replace("\tvar d := base - cover\n", "\tvar d := base - cover\n\t## sneaky doc in the body\n"), item(names))
    case("sameline", BASE, BASE.replace("static func predicted_damage", "## Predicts the damage.\n## Predicts the damage.\nstatic func predicted_damage"), item(names))
    case("nonsupply", BASE, GOOD, item(names, supply=False))
    case("partial", GOOD, GOOD.replace("static func second", "## Second one.\nstatic func second"), item(["predicted_damage", "second"]))
    det_base = BASE.replace("static func predicted_damage", "var v = 1\n\n## Predicts damage.\n\nstatic func predicted_damage")
    case("detached", det_base, det_base.replace("## Predicts damage.\n\n", "## Predicts damage.\n"), item(names))
    case("header", BASE, GOOD.replace("extends RefCounted\n", "extends RefCounted\n## Script-level doc, valid after extends.\n", 1), item(names))
    d, b = mkrepo(BASE + "## orphan one\n## orphan one\n")
    os.makedirs(os.path.join(d, "addons"), exist_ok=True)
    open(os.path.join(d, "addons", "x.gd"), "w").write("## junk\n")
    git(d, "add", "-A"); git(d, "commit", "-q", "-m", "addons")
    FIX["scan"] = (d, b, "", "")


def R(tool, key):
    d, b, h, it = FIX[key]
    return run(tool, d, b, h, it)


def battery(tool, tag):
    """returns the number of failed assertions (so a mutant run can count how many bite)"""
    global P, F
    f0 = F
    if not FIX:
        build()
    r = R(tool, "good"); ok("%s: a ## line added directly above the named func => OK" % tag, r[0] == "OK", r)
    r = R(tool, "eof"); ok("%s: block appended at EOF (damage_preview.gd d54ffc7) => FLAG no-net-doc,orphan" % tag, r[0] == "FLAG" and "no-net-doc" in r[1] and "orphan" in r[1], r)
    r = R(tool, "deleted"); ok("%s: the follow-up cycle only deleted the doc lines => FLAG no-net-doc (the removed orphan is not charged as new)" % tag, r[0] == "FLAG" and r[1] == "no-net-doc", r)
    r = R(tool, "dupfunc"); ok("%s: the func defined twice (loot_table.gd Parse Error) => FLAG dup-func" % tag, r[0] == "FLAG" and "dup-func" in r[1], r)
    r = R(tool, "twice"); ok("%s: the same ## text twice, one block detached (mission_summary.gd) => FLAG duplicate and orphan, not no-net-doc" % tag,
                             r[0] == "FLAG" and "duplicate" in r[1] and "orphan" in r[1] and "no-net-doc" not in r[1], r)
    r = R(tool, "already"); ok("%s: the ## above the func was already in BASE => FLAG no-net-doc (already there)" % tag, r[0] == "FLAG" and "no-net-doc" in r[1] and "already" in r[2], r)
    r = R(tool, "annot"); ok("%s: a ## added above the func's own-line annotations => OK (not an orphan)" % tag, r[0] == "OK", r)
    r = R(tool, "preexisting"); ok("%s: a pre-existing orphan block in BASE is not charged => OK" % tag, r[0] == "OK", r)
    r = R(tool, "empty"); ok("%s: no net diff at all => FLAG no-net-doc ('no net diff')" % tag, r[0] == "FLAG" and "no-net-doc" in r[1] and "no net diff" in r[2], r)
    r = R(tool, "two"); ok("%s: two named funcs, only one documented => FLAG no-net-doc naming `second` only" % tag,
                           r[0] == "FLAG" and "no-net-doc" in r[1] and "`second`" in r[2] and "`predicted_damage`" not in r[2], r)
    r = R(tool, "gone"); ok("%s: a named func deleted => FLAG func-missing" % tag, r[0] == "FLAG" and "func-missing" in r[1], r)
    r = R(tool, "nofile"); ok("%s: file deleted => FLAG file-missing" % tag, r[0] == "FLAG" and "file-missing" in r[1], r)
    r = R(tool, "blank"); ok("%s: a blank line between the ## block and the func => FLAG no-net-doc,orphan" % tag, r[0] == "FLAG" and "no-net-doc" in r[1] and "orphan" in r[1], r)
    r = R(tool, "body"); ok("%s: a ## block inside a function body => FLAG orphan (the func itself is documented)" % tag, r[0] == "FLAG" and r[1] == "orphan", r)
    r = R(tool, "sameline"); ok("%s: the same line twice inside one block => FLAG duplicate" % tag, r[0] == "FLAG" and r[1] == "duplicate", r)
    r = R(tool, "header"); ok("%s: a script-level ## block right after `extends` (blank line before the first func) is valid, not an orphan => OK (190 of xlite's 223 naive 'orphans' were this shape)" % tag, r[0] == "OK", r)
    r = R(tool, "detached"); ok("%s: a ## block BASE had detached by a blank line, attached by deleting the blank (the executor's own repair; found by `ovn_executor_ctl.py rehearse` on real xlite items) => OK, no orphan left" % tag, r[0] == "OK", r)
    r = R(tool, "partial"); ok("%s: two named funcs, one documented in BASE already and the other documented by this change => OK (found by rehearse on real xlite item height_damage.gd)" % tag, r[0] == "OK", r)
    r = R(tool, "nonsupply"); ok("%s: not a supply:gd-missing-doc item => SKIP" % tag, r[0] == "SKIP", r)
    d = FIX["scan"][0]
    s = subprocess.run([sys.executable, tool, "scan", d], capture_output=True, text=True, cwd=d).stdout.strip().split("\n")
    ok("%s: scan reports the orphan + duplicated line in dp.gd, TOTAL files=1 orphans=1 dups=1, addons/ ignored" % tag,
       s[-1] == "TOTAL\tfiles=1\torphans=1\tdups=1" and s[0].startswith("scripts/battle/dp.gd\torphans=1\tdups=1\tfirst-orphan-line="), s)
    r = subprocess.run([sys.executable, tool, "check", "/nonexistent-dir", "x", "y", item(["predicted_damage"])], capture_output=True, text=True)
    ok("%s: a missing repo does not crash (exit 0, FLAG or SKIP line)" % tag, r.returncode == 0 and r.stdout.split("\t")[0] in ("FLAG", "SKIP"), (r.returncode, r.stdout, r.stderr[-200:]))
    return F - f0


real_fail = battery(TOOL, "real")
ok("real tool passes the whole battery", real_fail == 0, "failed=%d" % real_fail)

src = open(TOOL).read()
MUTANTS = [
    ("net-added check removed (a pre-existing doc counts)", "if any((k + 1) in added for k in range(blk[0], blk[1])) or", "if True or"),
    ("detached-in-BASE repair not credited", " or (oidx and doc_block_above(old, oidx[0]) is None):", ":"),
    ("any already-documented name flags the change", 'if not gained and already and "no-net-doc" not in flags and "func-missing" not in flags:', 'if already and "no-net-doc" not in flags and "func-missing" not in flags:'),
    ("orphan detection removed", "if d_orph > 0:", "if False:"),
    ("duplicate detection removed", "if d_dup > 0:", "if False:"),
    ("dup-func detection removed", "if n_funcs(new, name) > n_funcs(old, name):", "if False:"),
    ("empty-diff shortcut removed", "if not added and old == new:", "if False:"),
    ("blank line allowed between block and func", "    while j > 0 and lines[j - 1].lstrip().startswith(\"##\"):",
     "    while j > 0 and (lines[j - 1].lstrip().startswith(\"##\") or not lines[j - 1].strip()):"),
    ("orphan compared absolutely (not relative to BASE)", "d_orph = orphan_count(new) - orphan_count(old)", "d_orph = orphan_count(new)"),
    ("annotation walk dropped from the doc lookup", "a = dx.anchor(lines, i)\n    j = a", "a = i\n    j = a"),
    ("func-missing not flagged", 'flags.append("func-missing")', 'pass'),
    ("file-missing not flagged", 'return ("FLAG", "file-missing"', 'return ("SKIP", "file-missing"'),
    ("non-supply item judged", 'if "supply:gd-missing-doc" not in item:', "if False:"),
    ("script-level header doc counted as orphan", "(j < n and bool(DECL_RE.match(lines[j]))) or header_only", "(j < n and bool(DECL_RE.match(lines[j])))"),
    ("annotations not declarations", '|class_name\\b|extends\\b|@\\w+)")', '|class_name\\b|extends\\b)")'),
    ("scan counts addons/", 'and not p.startswith("addons/") and "/addons/" not in p]', "]"),
]
tmpd = tempfile.mkdtemp(prefix="pc-mut-")
for name, old, new in MUTANTS:
    if src.count(old) != 1:
        ok("mutation '%s' applies (source drifted)" % name, False, "count=%d" % src.count(old))
        continue
    mdir = os.path.join(tmpd, "m")
    shutil.rmtree(mdir, ignore_errors=True)
    os.makedirs(mdir)
    shutil.copy(os.path.join(SCRIPTS, "ovn_doc_executor.py"), mdir)
    mp = os.path.join(mdir, "ovn_doc_postcheck.py")
    open(mp, "w").write(src.replace(old, new))
    p_, f_ = P, F
    QUIET = True
    bad = battery(mp, "mutant")
    QUIET = False
    # a mutant run's own FAIL lines are the point: take them back out of the totals, then assert that it bit
    F = f_
    P = p_
    ok("mutation '%s' is caught (%d assertion(s) bite)" % (name, bad), bad > 0)
shutil.rmtree(tmpd, ignore_errors=True)
for d_, *_ in FIX.values():
    shutil.rmtree(d_, ignore_errors=True)

print("ovn_doc_postcheck: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
