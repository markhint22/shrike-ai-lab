#!/usr/bin/env python3
"""R15 verify package (2026-10-12): ovn_verify_safe.py - allow-list execution of untrusted VERIFY text, stage-aware status, delete-item shape."""
import os
import sys
import tempfile
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__))); import tmp_track; tmp_track.install()   # 2026-10-17: every mkdtemp() below is removed at exit (the suite leaked these dirs)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import ovn_verify_safe as S  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


tree = tempfile.mkdtemp(prefix="safe-tree-")
probe = tempfile.mkdtemp(prefix="safe-probe-")   # outside the tree: must stay empty
open(os.path.join(tree, "a.txt"), "w").write("hi\nfoo\n")
os.makedirs(os.path.join(tree, "sub"))
open(os.path.join(tree, "sub", "b.txt"), "w").write("bar\n")

print("== allow-list: every escape probe is UNSAFE and never executed")
escapes = ["echo hi | tee %s/w1 | grep -q hi" % probe, "touch %s/w2; ls a.txt" % probe, "sed -i s/hi/x/ a.txt", "find . -name a.txt -delete", "find . -exec touch %s/w3 ;" % probe,
           "find . -fprint %s/w4" % probe, "python3 -c 'open(\"%s/w5\",\"w\")'" % probe, "nc -l 1", "ssh localhost true", "git checkout -- a.txt", "pytest --collect-only",
           "ls $(touch %s/w6)" % probe, "ls `touch %s/w7`" % probe, "ls a.txt > %s/w8" % probe, "grep hi a.txt >> %s/w9" % probe, "sort -o %s/w10 a.txt" % probe, "uniq a.txt %s/w11" % probe,
           "grep hi a.txt & touch %s/w12" % probe, "ls <(touch %s/w13)" % probe, "(touch %s/w14)" % probe, "/bin/ls a.txt", "FOO=1 ls a.txt", "ls a.txt\ntouch %s/w15" % probe,
           "cd .. && ls", "cd /tmp && ls", "awk 'BEGIN{system(\"touch %s/w16\")}'" % probe, "grep hi a.txt | xargs touch", "cat a.txt | sh"]
for c in escapes:
    r = S.run(c, tree, 10)
    ok("UNSAFE: %s" % c.replace("\n", "\\n")[:70], r["status"] == "UNSAFE", r)
ok("nothing was created outside the tree", os.listdir(probe) == [], os.listdir(probe))
ok("nothing was created in the tree", sorted(os.listdir(tree)) == ["a.txt", "sub"], os.listdir(tree))
ok("a hung allow-listed command is killed (tail -f) and reported as TIMEOUT", S.run("tail -f a.txt", tree, 2)["status"] == "TIMEOUT")

print("== allow-listed shapes run")
for c, rc in (("grep -q hi a.txt", 0), ("grep -q nothere a.txt", 1), ("! grep -q nothere a.txt", 0), ("ls a.txt", 0), ("test -f a.txt", 0), ("[ -d sub ]", 0),
              ("grep foo a.txt 2>/dev/null", 0), ("grep -c o a.txt 2>&1 | wc -l", 0), ("cat a.txt | grep -q foo && ls sub", 0), ("grep 'a>b' a.txt", 1), ("cd sub && grep -q bar b.txt", 0),
              ("find . -name b.txt | grep -q b", 0), ("grep -q nothere a.txt || test -f a.txt", 0)):
    r = S.run(c, tree, 10)
    ok("%s -> rc %d" % (c, rc), r["status"] == "OK" and r["rc"] == rc, r)

ok("ls on a missing file exits non-zero (not an err flag: ls is an exit-code tool)", S.run("ls nope.txt", tree, 10)["rc"] not in (0, None) and not S.run("ls nope.txt", tree, 10)["err"])
print("== stage-aware status (the unsafe direction: errors read as absence)")
for c, why in (("grep x missing_dir | grep -v y", "earlier-stage grep error"), ("cd missing && grep x a.txt", "cd into a missing dir"), ("cd missing || grep x a.txt", "cd failure under ||"), ("grep x missing_file", "grep rc 2")):
    r = S.run(c, tree, 10)
    ok("%s: err flagged (%s)" % (c, why), r["status"] == "OK" and r["err"], r)
for c in ("grep x a.txt | grep -v y", "cd sub && grep nothere b.txt", "ls a.txt | grep -q a"):
    r = S.run(c, tree, 10)
    ok("%s: no err flag (healthy stages)" % c, r["status"] == "OK" and not r["err"], r)

print("== delete-item shape (livelock fix) is conservative")
d = "- [ ] [T2] gone.gd — Delete gone.gd entirely. VERIFY: `grep -n x gone.gd` returns no matches. (cat:gd)"
ok("delete item + lone grep on the missing file", S.delete_shape_ok(d, "grep -n x gone.gd", tree))
ok("... not when the description merely mentions 'the removed function' (xlite addons/gut/test_aoe*.gd)", not S.delete_shape_ok("- [x] [T2] gone.gd \u2014 Verify that no test case calls `A.b` or references the removed function. VERIFY: `grep -n x gone.gd` returns no output. (cat:test)", "grep -n x gone.gd", tree))
ok("... not for 'Remove the unused import' on a missing file", not S.delete_shape_ok("- [ ] [T2] gone.gd \u2014 Remove the unused import in gone.gd. VERIFY: `grep -n x gone.gd` returns no matches.", "grep -n x gone.gd", tree))
ok("... yes for 'Delete the test file for the removed X class'", S.delete_shape_ok("- [x] [T2] gone.gd \u2014 Delete the test file for the removed Scatter class. VERIFY: `grep -n x gone.gd` returns no matches.", "grep -n x gone.gd", tree))
ok("... not when the file exists", not S.delete_shape_ok(d.replace("gone.gd", "a.txt"), "grep -n x a.txt", tree))
ok("... not for a non-delete item", not S.delete_shape_ok(d.replace("Delete", "Add a header to"), "grep -n x gone.gd", tree))
ok("... not when the operand is not named by the item", not S.delete_shape_ok(d, "grep -n x gone.gd other_missing.gd", tree))
ok("... not for a pipeline", not S.delete_shape_ok(d, "grep -n x gone.gd | grep -v y", tree))
ok("... not for a glob operand", not S.delete_shape_ok(d, "grep -n x gon*.gd", tree))
ok("... not without a file operand (stdin)", not S.delete_shape_ok(d, "grep -n x", tree))
ok("... not for a non-grep tool", not S.delete_shape_ok(d, "ls gone.gd", tree))
ok("-e PATTERN form: operand is the file", S.delete_shape_ok(d, "grep -n -e x gone.gd", tree))

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
