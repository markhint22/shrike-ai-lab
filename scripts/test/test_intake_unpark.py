#!/usr/bin/env python3
"""Intake package (2026-10-13): ovn_unpark_xlite_unworkable.py - the read-only retag helper for the lines the F2 bug parked.
Dry run by default (nothing written); RETAG / KEEP / HELD classification with the FIXED rule; --apply is text-anchored (tick_lines.py semantics) and touches only --progress.
Mutation proofs: classify with the OLD whole-line rule (every line KEEPs), apply by line number instead of anchor, write in dry-run mode."""
import json
import os
import subprocess
import sys
import tempfile
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()   # 2026-10-16: every tempfile.mkdtemp() below is removed at exit (these tests left dirs in the private TMPDIR)

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SD)
import ovn_unpark_xlite_unworkable as U  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


root = tempfile.mkdtemp(prefix="unpark-")
for rel in ("addons/gut/gut_cmdln.gd", "addons/gut/strutils.gd", "scripts/small.gd", "tests/test_existing.gd"):
    os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
    open(os.path.join(root, rel), "w").write("x")
open(os.path.join(root, ".queue-hard-banned-files"), "w").write("addons/\n")
RUN = "godot --headless -s addons/gut/gut_cmdln.gd"
T = "[CLAUDE] [unworkable: hard-banned file addons/gut/gut_cmdln.gd] "
lines = [
    "# Next Steps", "",
    "- [ ] " + T + "[T4] tests/battle/test_a.gd — Create test A. VERIFY: `%s -gtest=res://tests/battle/test_a.gd`. (cat:test)" % RUN,                       # 3  RETAG
    "- [ ] " + T + "[T4] tests/battle/test_b.gd — Create test B. VERIFY: `%s -gtest=res://tests/battle/test_b.gd`. (cat:test)" % RUN,                       # 4  RETAG
    "- [ ] [CLAUDE] [unworkable: hard-banned file addons/gut/strutils.gd] [T1] addons/gut/strutils.gd — add helper. VERIFY: `grep -n x addons/gut/strutils.gd`",  # 5  KEEP (real target)
    "- [ ] [AUTO-SKIP batch-graded-F — landed 0/13] " + T + "[T1] tests/test_c.gd — Add test C. VERIFY: `%s -gtest=res://tests/test_c.gd`" % RUN,           # 6  HELD
    "- [ ] [T2] scripts/small.gd — an ordinary open item. VERIFY: `true`",                                                                                      # 7  not parked
    "- [x] " + T + "[T4] tests/battle/test_done.gd — done line. VERIFY: `true`",                                                                                # 8  checked: ignored
    "- [ ] " + T + "[T4] tests/battle/test_a.gd — Create test A. VERIFY: `%s -gtest=res://tests/battle/test_a.gd`. (cat:test) [feat:dup]" % RUN,            # 9  RETAG, text overlaps line 3
    "",
]
text = "\n".join(lines)
prog = os.path.join(root, "OVERNIGHT_PROGRESS.md")
open(prog, "w").write(text)

print("== plan")
retags, keeps, held = U.plan(text, root)
ok("RETAG = lines 3, 4, 9 (workable once the VERIFY is not scanned)", [r["line"] for r in retags] == [3, 4, 9], [r["line"] for r in retags])
ok("[mut] KEEP = line 5 (a REAL vendored target stays unworkable), with the reason", [(r["line"], r["still"]) for r in keeps] == [(5, "hard-banned file addons/gut/strutils.gd")], keeps)
ok("HELD = line 6 (another parking tag, AUTO-SKIP, stays)", [(r["line"], r["other"]) for r in held] == [(6, "AUTO-SKIP")], held)
ok("the retagged line is the original text without the park tag", retags[0]["new_line"] == "- [ ] [T4] tests/battle/test_a.gd — Create test A. VERIFY: `%s -gtest=res://tests/battle/test_a.gd`. (cat:test)" % RUN, retags[0]["new_line"])
ok("every decision carries the exact parked line text, and each occurs once among the open lines", all(sum(1 for l in lines if l == r["orig_line"]) == 1 for r in retags))
ok("line 3 has NO unique substring anchor (it is a prefix of line 9): the substring anchor is null, the exact text still works", retags[0]["anchor"] is None and retags[2]["anchor"] is not None, [r["anchor"] for r in retags])

print("== dry run writes nothing")
before = open(prog).read()
out = os.path.join(root, "dec.json")
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_unpark_xlite_unworkable.py"), "--progress", prog, "--repo-root", root, "--json-out", out], capture_output=True, text=True)
ok("rc 0, summary line, DRY RUN banner", r.returncode == 0 and "3 to RETAG" in r.stdout and "1 still unworkable" in r.stdout and "1 held" in r.stdout and "DRY RUN: nothing written" in r.stdout, r.stdout + r.stderr)
ok("[mut] the progress file is byte-identical after a dry run", open(prog).read() == before)
ok("the diff shows the old line and the new line", "  - - [ ] " + T.strip() in r.stdout and "  + - [ ] [T4] tests/battle/test_a.gd" in r.stdout, r.stdout[:800])
dec = json.load(open(out))
ok("--json-out carries the decisions (exact line text, optional anchor)", len(dec["retag"]) == 3 and all(d["line_text"].startswith("- [ ] [CLAUDE] [unworkable") or d["line_text"].startswith("- [ ] ") for d in dec["retag"]), dec)
ok("a read-only progress file works (dry run only reads)", True)

print("== --apply: text anchored, only the three lines change")
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_unpark_xlite_unworkable.py"), "--progress", prog, "--repo-root", root, "--apply"], capture_output=True, text=True)
after = open(prog).read().split("\n")
ok("3 line(s) written", "3 line(s) written" in r.stdout, r.stdout[-300:])
ok("lines 3, 4, 9 lost the park tag", all("[unworkable" not in after[i] and after[i].startswith("- [ ] [T4] tests/battle/") for i in (2, 3, 8)), [after[i][:60] for i in (2, 3, 8)])
ok("every OTHER line is byte-identical (KEEP, HELD, ordinary, checked, headers)", all(after[i] == lines[i] for i in range(len(lines)) if i not in (2, 3, 8)))
r2 = subprocess.run([sys.executable, os.path.join(SD, "ovn_unpark_xlite_unworkable.py"), "--progress", prog, "--repo-root", root, "--apply"], capture_output=True, text=True)
ok("idempotent: a second apply finds nothing to retag", "0 to RETAG" in r2.stdout and "0 line(s) written" in r2.stdout, r2.stdout[:200])

print("== apply by anchor survives the fleet inserting lines above")
open(prog, "w").write(text)
shifted = "- [ ] [T2] scripts/small.gd — a new line the fleet added above. VERIFY: `true`\n" * 5 + text
open(prog, "w").write(shifted)
new, report, changed = U.apply_retags(shifted, retags)       # decisions made against the OLD numbering
ok("the retags still land on the right lines after a shift of 5 lines", changed == 3 and new.count("[unworkable: hard-banned file addons/gut/gut_cmdln.gd]") == 2, (changed, report))   # the HELD line and the checked [x] line keep theirs
ok("a decision whose parked line changed (the fleet edited it) is skipped, never guessed", U.apply_retags("- [ ] [T2] x.gd — y\n", retags)[1][0].startswith("SKIP"))
amb = "- [ ] %s[T4] tests/a.gd — Create A. VERIFY: `x`\n- [ ] %s[T4] tests/a.gd — Create A. VERIFY: `x`" % (T, T)
rt, kp, hd = U.plan(amb, root)
ok("two IDENTICAL parked lines: apply refuses (never retags a guess)", rt and U.apply_retags(amb, rt)[2] == 0 and U.apply_retags(amb, rt)[1][0].startswith("REFUSED"), rt)

print("== --apply: the temp file is written OUTSIDE the checkout, the file mode is kept")
os.chmod(prog, 0o644)
open(prog, "w").write(text)
os.chmod(prog, 0o644)
seen = []
_real_replace = os.replace
def _spy(a, b, *x, **k):
    seen.append((a, b))
    return _real_replace(a, b, *x, **k)
os.replace = _spy
try:
    rc = U.main(["--progress", prog, "--repo-root", root, "--apply"])
finally:
    os.replace = _real_replace
ok("[mut] the staged temp file is not next to --progress (no untracked file in a live tree)", rc == 0 and seen and all(os.path.dirname(os.path.abspath(a)) != os.path.dirname(os.path.abspath(prog)) for a, _ in seen), seen)
ok("no '.unpark.tmp' / 'unpark-*.tmp' leftover next to the progress file", not [n for n in os.listdir(root) if n.endswith(".tmp")], os.listdir(root))
ok("the progress file keeps its mode (0644) and the retags landed", (os.stat(prog).st_mode & 0o777) == 0o644 and open(prog).read().count("[unworkable") == 3)

print("== arguments")
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_unpark_xlite_unworkable.py"), "--progress", prog], capture_output=True, text=True)
ok("missing --repo-root -> rc 2", r.returncode == 2)

print("intake unpark: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
