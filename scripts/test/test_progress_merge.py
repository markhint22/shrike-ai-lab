#!/usr/bin/env python3
"""Unit + randomized property tests for scripts/ovn_progress_merge.py (package conflict, 2026-10-12).

  * the REAL 2026-10-12 iptv_apps conflict (distilled fixtures from commits fb07d121d1 / c2204cc7d9 / hand resolution c7be7d3c): the plain
    text merge conflicts, the resolver output equals the hand resolution byte for byte, in both merge directions
  * rule unit tests (checked wins, union, no duplicate, order, delete handling, shared-tag steps, date-stamp-insensitive identity)
  * 300 randomized trials x 2 directions (unique-hash generator) + 150 trials of the shared-feat-tag generator: no item lost, no duplicate,
    checked stays checked, ours' order preserved, self-check never trips
  * Python twin of ovn_item_hash == the shell function on a corpus of lines
  * self-check fallback: a deliberately broken merge is refused (-> text merge), never emitted
"""
import importlib.util
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PM_PATH = os.path.join(os.path.dirname(HERE), "ovn_progress_merge.py")
FIX = os.path.join(HERE, "fixtures", "progress_merge")
spec = importlib.util.spec_from_file_location("ovn_progress_merge", PM_PATH)
pm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pm)

PASS = 0
FAILS = []


def ok(name, cond, extra=""):
    global PASS
    if cond:
        PASS += 1
    else:
        FAILS.append(name)
        print("  FAIL %s %s" % (name, extra))


def rd(p):
    with open(p, "rb") as f:
        return f.read()


def merge(b, o, t):
    """text -> text through the real byte entry point"""
    m, _ = pm.merge_bytes(b.encode(), o.encode(), t.encode())
    return m.decode()


def lines(s):
    return s.split("\n")[:-1] if s.endswith("\n") else s.split("\n")


# ------------------------------------------------------------------------------------------------------------------------------------
# 1. the real conflict
# ------------------------------------------------------------------------------------------------------------------------------------
rb, ro, rt, rh = (rd(os.path.join(FIX, "real_%s.md" % n)) for n in ("base", "ours", "theirs", "hand"))
td = tempfile.mkdtemp(prefix="pmtest.")
try:
    for n, d in (("b", rb), ("o", ro), ("t", rt)):
        open(os.path.join(td, n), "wb").write(d)
    p = subprocess.run(["git", "merge-file", "-p", os.path.join(td, "o"), os.path.join(td, "b"), os.path.join(td, "t")], stdout=subprocess.PIPE)
    ok("real: the plain git text merge CONFLICTS on the distilled real files (reproduction)", p.returncode > 0 and b"<<<<<<<" in p.stdout)
finally:
    shutil.rmtree(td, ignore_errors=True)
m, st = pm.merge_bytes(rb, ro, rt)
ok("real: resolution == the hand resolution (c7be7d3c) byte for byte", m == rh)
ok("real: the 3 items ticked on claude/feature are checked in the result", st["checked_wins"] == 3 and st["both_changed"] == 3, str(dict(st)))
m2, _ = pm.merge_bytes(rb, rt, ro)  # reconcile direction: ours = the feature branch, theirs = develop
ok("real: swapped direction (reconcile develop->feature) also == hand resolution", m2 == rh)
ok("real: all new fleet items (24 lines) were kept", st["new_theirs"] == 24, str(dict(st)))

# ------------------------------------------------------------------------------------------------------------------------------------
# 2. rule unit tests
# ------------------------------------------------------------------------------------------------------------------------------------
def I(n, state=" ", extra=""):
    return "- [%s] %s[T1] src/m%d.py - do thing number %d with enough words to be identifiable%s" % (state, extra, n, n, "")


H = ["## Next Steps", ""]
b = "\n".join(H + [I(1), I(2), I(3)]) + "\n"

# checked wins, both orders
o = "\n".join(H + [I(1, "x"), I(2), I(3)]) + "\n"
t = "\n".join(H + [I(1, " ", "[AUTO-SKIP x] "), I(2), I(3)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: checked on one side beats a tag edit on the other (ours checked)", r[2].startswith("- [x] ") and len(r) == 5, str(r))
r = lines(merge(b, t, o))
ok("rule: checked on one side beats a tag edit on the other (theirs checked)", r[2].startswith("- [x] ") and len(r) == 5, str(r))
# one-sided change takes the change
r = lines(merge(b, o, b))
ok("rule: unchanged theirs -> ours' tick", r[2].startswith("- [x] "))
# both new items union, ours first
o = "\n".join(H + [I(1), I(2), I(3), I(10)]) + "\n"
t = "\n".join(H + [I(1), I(2), I(3), I(11)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: both appended different items -> union, ours' first", r[-2:] == [I(10), I(11)], str(r))
# both added the SAME new item, different state -> one copy, checked
o = "\n".join(H + [I(1), I(2), I(3), I(10, "x")]) + "\n"
t = "\n".join(H + [I(1), I(2), I(3), I(10)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: same new item on both sides -> one copy, checked kept", [x for x in r if "m10.py" in x] == [I(10, "x")], str(r))
# deletion: archived on one side, ticked on the other -> deleted
o = "\n".join(H + [I(2), I(3)]) + "\n"
t = "\n".join(H + [I(1, "x"), I(2), I(3)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: archived (deleted) on one side, ticked on the other -> gone", not any("m1.py" in x for x in r) and len(r) == 4, str(r))
# deleted unchanged on one side
r = lines(merge(b, o, b))
ok("rule: deleted on ours, unchanged on theirs -> gone", not any("m1.py" in x for x in r))
# rewritten text without feat tag (no hash match) pairs by core key -> no duplicate
o = "\n".join(H + ["- [x] (retired: already covered) " + I(1)[6:], I(2), I(3)]) + "\n"
t = "\n".join(H + [I(1, " ", "[AUTO-SKIP recovery:none] "), I(2), I(3)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: rewritten text pairs by core key (no duplicate, checked kept)", len([x for x in r if "m1.py" in x]) == 1 and [x for x in r if "m1.py" in x][0].startswith("- [x] (retired"), str(r))
# date-stamp-insensitive identity (a roadmap regeneration bumps the stamp inside the feat tag)
fa = "- [ ] [T2] f.py - do it [feat:iptv-20261011-do-it]"
fb = "- [ ] [T2] f.py - do it (regenerated) [feat:iptv-20261012-do-it]"
ok("hash: date stamp inside [feat:] is ignored", pm.item_hash(fa) == pm.item_hash(fb))
ok("hash: checkbox state is ignored", pm.item_hash(fa) == pm.item_hash(fa.replace("[ ]", "[x]", 1)))
ok("hash: different feat tags differ", pm.item_hash(fa) != pm.item_hash("- [ ] [T2] f.py - do it [feat:iptv-20261011-other]"))
b2 = "\n".join(H + [fa, I(2)]) + "\n"
o2 = "\n".join(H + [fa.replace("[ ]", "[x]", 1), I(2)]) + "\n"
t2 = "\n".join(H + [fb, I(2)]) + "\n"
r = lines(merge(b2, o2, t2))
ok("rule: regenerated feat stamp + tick -> one line, checked", len([x for x in r if "feat:iptv" in x]) == 1 and [x for x in r if "feat:iptv" in x][0].startswith("- [x]"), str(r))
# shared feat tag across decomposed steps (xlite ALREADY-DONE loop shape): multiple lines with one hash are never merged into one nor duplicated
s1 = "- [ ] [T1] a.gd - step one [feat:x-20261011-brief]"
s2 = "- [ ] [T1] a.gd - step two [feat:x-20261011-brief]"
s3 = "- [ ] [T1] a.gd - step three [feat:x-20261011-brief]"
bs = "\n".join(H + [s1, s2, s3]) + "\n"
os_ = "\n".join(H + [s1.replace("[ ]", "[x]", 1), s2, s3]) + "\n"
ts = "\n".join(H + [s1, s2, s3, "- [ ] [T1] a.gd - step four [feat:x-20261011-brief]"]) + "\n"
r = lines(merge(bs, os_, ts))
ok("rule: shared-tag steps: each step kept once, step four added, step one checked", len(r) == 6 and r[2].startswith("- [x]") and r[-1].endswith("step four [feat:x-20261011-brief]"), str(r))
# non-item lines / headers
o = "\n".join(H + [I(1), I(2), I(3), "", "<!-- auto-refill A -->", I(20)]) + "\n"
t = "\n".join(H + [I(1), I(2), I(3), "", "<!-- auto-refill B -->", I(21)]) + "\n"
r = lines(merge(b, o, t))
ok("rule: two appended blocks keep their own blank+header", r[-6:] == ["", "<!-- auto-refill A -->", I(20), "", "<!-- auto-refill B -->", I(21)], str(r))
# insertion goes before the next surviving anchor of theirs (middle insertion)
o = "\n".join(H + [I(1), I(2), I(3)]) + "\n"
t = "\n".join(H + [I(1), I(15), I(2), I(3)]) + "\n"
r = lines(merge(b, o, t))
ok("order: theirs' mid-file insertion lands before its successor", r[3:6] == [I(1), I(15), I(2)] or r[2:5] == [I(1), I(15), I(2)], str(r))
# identities: clean cases equal the one-sided side
ok("clean: merge(b,o,b) == o", merge(b, o, b) == o)
ok("clean: merge(b,b,t) == t", merge(b, b, t) == t)
ok("clean: merge(b,o,o) == o", merge(b, o, o) == o)
ok("clean: merge(x,x,x) == x", merge(b, b, b) == b)
ok("empty: merge of empty files is empty", pm.merge_bytes(b"", b"", b"")[0] == b"")
ok("add/add with empty base unions both", len(lines(merge("", I(1) + "\n", I(2) + "\n"))) == 2)
ok("no trailing newline preserved when neither side has one", not merge("a\n- [ ] x yyyyyyyyyyyy", "a\n- [ ] x yyyyyyyyyyyy", "a\n- [ ] x yyyyyyyyyyyy").endswith("\n"))
# arbitrary bytes round-trip
weird = b"- [ ] caf\xc3\xa9 \xff\xfe broken utf8 item with enough text\n"
ok("non-utf8 bytes round-trip", pm.merge_bytes(weird, weird, weird)[0] == weird)
# a 2000-line file is fast
big_b = "\n".join(I(i) for i in range(2500)) + "\n"
big_o = big_b.replace("- [ ] [T1] src/m7.py", "- [x] [T1] src/m7.py", 1)
big_t = big_b + I(9999) + "\n"
import time
t0 = time.time()
mb, _ = pm.merge_bytes(big_b.encode(), big_o.encode(), big_t.encode())
ok("perf: 2500-line merge < 5s", time.time() - t0 < 5, "%.2fs" % (time.time() - t0))
ok("perf: result right", mb.decode().count("[x]") == 1 and mb.decode().endswith(I(9999) + "\n"))

# ------------------------------------------------------------------------------------------------------------------------------------
# 3. randomized property tests
# ------------------------------------------------------------------------------------------------------------------------------------
def gen_case(rng, shared_tags):
    n = rng.randint(3, 22)
    uid = [0]

    def new_item(state=" "):
        uid[0] += 1
        k = uid[0]
        tag = ""
        if shared_tags and rng.random() < 0.5:
            tag = " [feat:r-20261011-brief%d]" % rng.randint(1, 3)
        elif rng.random() < 0.3:
            tag = " [feat:r-20261011-unique%d-%d]" % (k, rng.randint(0, 10 ** 6))
        return "- [%s] [T%d] src/mod%d/file%d.py - unique action number %d with a long enough description%s" % (state, rng.randint(1, 4), k, k, k, tag)

    base = ["## Next Steps", ""]
    for _ in range(n):
        base.append(new_item(rng.choice([" ", " ", "x"])))
        if rng.random() < 0.15:
            base.append("")
        if rng.random() < 0.1:
            base.append("<!-- note %d -->" % rng.randint(1, 5))
    base.append("")
    shared_new = [new_item() for _ in range(rng.randint(0, 2))]

    def edit(side):
        ls = list(base)
        for _ in range(rng.randint(0, 6)):
            idx = [i for i, x in enumerate(ls) if pm.ITEM_RE.match(x)]
            if not idx:
                break
            i = rng.choice(idx)
            op = rng.choice(["tick", "tag", "rewrite", "delete", "insert", "append", "regen", "tail", "move"])
            if op == "tick":
                ls[i] = ls[i].replace("[ ]", "[x]", 1)
            elif op == "tag":
                ls[i] = ls[i].replace("] ", "] [AUTO-SKIP %s %d] " % (side, rng.randint(1, 9)), 1) if rng.random() < 0.5 else ls[i] + " (cat:%s)" % side
            elif op == "rewrite" and "[feat:" not in ls[i]:
                body = ls[i][6:]
                ls[i] = "- [%s] (note by %s %d) %s" % (rng.choice([" ", "x"]), side, rng.randint(1, 9), body)
            elif op == "delete":
                del ls[i]
            elif op == "insert":
                ls.insert(rng.randint(2, len(ls)), new_item(rng.choice([" ", "x"])))
            elif op == "append":
                ls.extend(["", "<!-- auto-refill %s %d -->" % (side, rng.randint(1, 99))] + [new_item() for _ in range(rng.randint(1, 3))])
            elif op == "regen" and "[feat:" in ls[i]:
                ls[i] = ls[i].replace("20261011", "20261012", 1)
            elif op == "tail":
                ls.append(new_item())
            elif op == "move":
                x = ls.pop(i)
                ls.insert(rng.randint(2, len(ls)), x)
        if shared_new and rng.random() < 0.7:
            for s in shared_new:
                ls.insert(rng.randint(2, len(ls)), s.replace("[ ]", rng.choice(["[ ]", "[x]"]), 1))
        return "\n".join(ls) + "\n"

    return "\n".join(base) + "\n", edit("ours"), edit("theirs")


def props(b, o, t, shared, label):
    ml = lines(merge(b, o, t))
    bl, ol, tl = lines(b), lines(o), lines(t)
    cb, co, ct, cm = map(pm._hash_counts, (bl, ol, tl, ml))
    ko, kt, km = map(pm._checked_counts, (ol, tl, ml))
    errs = []
    for h in set(co) | set(ct) | set(cm):
        n_o, n_t, n_m = co.get(h, 0), ct.get(h, 0), cm.get(h, 0)
        uniq = max(cb.get(h, 0), n_o, n_t) <= 1
        if uniq and n_o and n_t and not n_m:
            errs.append("lost item present on both sides")
        if n_m > max(n_o, n_t):
            errs.append("duplicate (%d > max(%d,%d))" % (n_m, n_o, n_t))
        if n_m == 0 and (n_o or n_t) and not (cb.get(h, 0) and (n_o == 0 or n_t == 0)) and uniq and (n_o and n_t):
            errs.append("vanished")
        if uniq and n_m and (ko.get(h, 0) or kt.get(h, 0)) and not km.get(h, 0):
            errs.append("checked became unchecked")
        if n_m and not n_o and not n_t:
            errs.append("item from nowhere")
    if not shared:
        ours_order = [pm.item_hash(x) for x in ol if pm.ITEM_RE.match(x) and pm.item_hash(x) in cm]
        oset = set(co)
        out_order = [pm.item_hash(x) for x in ml if pm.ITEM_RE.match(x) and pm.item_hash(x) in oset]
        if ours_order != out_order:
            errs.append("ours' order not preserved")
    return errs


NT = 0
DECL = [0]
for shared, ntr, seed0 in ((False, 300, 1000), (True, 150, 5000)):
    bad = {}
    for s in range(ntr):
        rng = random.Random(seed0 + s)
        b, o, t = gen_case(rng, shared)
        for lab, (x, y) in (("fwd", (o, t)), ("swap", (t, o))):
            NT += 1
            try:
                errs = props(b, x, y, shared, lab)
            except ValueError as e:
                if "would lose its tick" in str(e):  # the conservative rewrite-vs-checked decline (-> plain text merge): safe, counted not failed
                    DECL[0] += 1
                    errs = []
                else:
                    errs = ["exception: %r" % e]
            except Exception as e:  # the self-check (or anything) tripping on valid input is a failure too
                errs = ["exception: %r" % e]
            for e in errs:
                bad.setdefault(e, []).append((seed0 + s, lab))
    ok("property (%s tags): no item lost / no duplicate / checked stays checked / ours' order, %d trials x2 directions" % ("shared" if shared else "unique", ntr), not bad,
       " ".join("%s@%s" % (k, v[:3]) for k, v in bad.items()))
ok("property: >= 200 randomized trials ran", NT >= 400, str(NT))
ok("property: the rewrite-vs-checked decline stays rare (< 15%% of %d cases, got %d)" % (NT, DECL[0]), DECL[0] < NT * 0.15)

# determinism + idempotence on random cases
rng = random.Random(77)
det = True
idem = True
for s in range(60):
    b, o, t = gen_case(random.Random(9000 + s), False)
    m1 = merge(b, o, t)
    det &= (m1 == merge(b, o, t))
    idem &= (merge(m1, m1, m1) == m1)
ok("property: deterministic", det)
ok("property: merging a result with itself is a no-op", idem)

# ------------------------------------------------------------------------------------------------------------------------------------
# 4. the self-check refuses a broken merge (-> caller falls back to the text merge)
# ------------------------------------------------------------------------------------------------------------------------------------
b3 = "\n".join(H + [I(1), I(2)]) + "\n"
bl3 = lines(b3)
ok("selfcheck: dropping an item present on both sides is detected", pm.self_check(bl3, bl3, bl3, bl3[:-1]) is not None)
ok("selfcheck: a duplicate is detected", pm.self_check(bl3, bl3, bl3, bl3 + [I(2)]) is not None)
ok("selfcheck: un-checking a checked item is detected", pm.self_check(bl3, [bl3[0], bl3[1], I(1, "x"), bl3[3]], bl3, bl3) is not None)
ok("selfcheck: passes a correct merge", pm.self_check(bl3, bl3, bl3, bl3) is None)
orig = pm.merge_lines
pm.merge_lines = lambda a, b_, c: (list(b_)[:-1], pm.MergeStats())  # broken implementation: loses the last item of ours
try:
    try:
        pm.merge_bytes(b3.encode(), b3.encode(), b3.encode())
        ok("selfcheck: merge_bytes refuses a broken merge", False)
    except ValueError:
        ok("selfcheck: merge_bytes refuses a broken merge", True)
finally:
    pm.merge_lines = orig

# the driver's own failure path: an exception inside the resolver falls back to the plain git text merge (markers + exit 1), never a half result
td2 = tempfile.mkdtemp(prefix="pmtest2.")
try:
    for n, d in (("b", "a\n- [ ] x yyyyyyyyyyyyyyyy\n"), ("o", "a\n- [x] x yyyyyyyyyyyyyyyy\n"), ("t", "a\n- [ ] x yyyyyyyyyyyyyyyy (z)\n")):
        open(os.path.join(td2, n), "w").write(d)
    real_mb = pm.merge_bytes
    def boom(*a):
        raise RuntimeError("boom")
    pm.merge_bytes = boom
    try:
        rc = pm.mode_driver([os.path.join(td2, "b"), os.path.join(td2, "o"), os.path.join(td2, "t")], os.path.join(td2, "log"), "x")
    finally:
        pm.merge_bytes = real_mb
    ok("driver: an exception in the resolver falls back to the text merge (exit 1, markers) - never a half result", rc == 1 and "<<<<<<<" in open(os.path.join(td2, "o")).read())
    ok("driver: the fallback is logged", "FALLBACK" in open(os.path.join(td2, "log")).read())
    for n, d in (("b", "a\n- [ ] x yyyyyyyyyyyyyyyy\n"), ("o", "a\n- [x] x yyyyyyyyyyyyyyyy\n"), ("t", "a\n- [ ] x yyyyyyyyyyyyyyyy\n")):
        open(os.path.join(td2, n), "w").write(d)
    os.environ["OVN_PM_DEFER"] = "1"
    try:
        rc2 = pm.mode_driver([os.path.join(td2, "b"), os.path.join(td2, "o"), os.path.join(td2, "t")], os.path.join(td2, "log"), "x")
    finally:
        del os.environ["OVN_PM_DEFER"]
    ok("driver: OVN_PM_DEFER=1 behaves as the plain text merge (clean here -> exit 0, ours' tick)", rc2 == 0 and open(os.path.join(td2, "o")).read().count("[x]") == 1)
finally:
    shutil.rmtree(td2, ignore_errors=True)

# ------------------------------------------------------------------------------------------------------------------------------------
# 5. python item_hash == shell ovn_item_hash
# ------------------------------------------------------------------------------------------------------------------------------------
LIB = os.path.join(HERE, "..", "lib_item_select.sh")
corpus = [
    "- [ ] plain item without any tag",
    "- [x] [T1] iptv-backend/app/core/limiter.py - Delete the unused import(s) [feat:iptv_apps-20261011-supply-unused-import-iptv-backend-app-core-limiter-py]",
    "- [ ] [T2] x.py - y [feat:a-123456-b] trailing",
    "- [X] [T3] café — em dash text [feat:r-20261012-name-with-é]",
    "[T1] bare text with no checkbox",
    "- [ ] two tags [feat:a-20261011-one] and [feat:b-20261011-two]",
    "- [ ] [feat:odd-2026101-short] seven digits",
    "- [ ] (retired 2026-10-11: note (nested)) [T1] iptv/x.py - foo",
]
if shutil.which("bash") and shutil.which("md5sum") and os.path.exists(LIB):
    allok = True
    for line in corpus:
        sh = subprocess.run(["bash", "-c", '. "$1"; ovn_item_hash "$2"', "x", LIB, line], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if sh.stdout.decode().strip() != pm.item_hash(line):
            allok = False
            print("  hash mismatch for %r: sh=%s py=%s" % (line, sh.stdout.decode().strip(), pm.item_hash(line)))
    ok("parity: python item_hash == lib_item_select.sh ovn_item_hash on %d lines" % len(corpus), allok)
else:
    print("  SKIP parity (no bash/md5sum/lib)")

# ------------------------------------------------------------------------------------------------------------------------------------
# 6. r12 review fixes (each test FAILS on the pre-fix behaviour; mutation-proven)
# ------------------------------------------------------------------------------------------------------------------------------------
def declines(b, o, t):
    try:
        pm.merge_bytes(b.encode(), o.encode(), t.encode())
        return False
    except ValueError:
        return True


# defect 2: checked item silently lost when the other side rewrote its text
rb0 = "## Next Steps\n- [ ] [T1] src/limiter.py - fix the limiter ordering so that the burst bucket is consulted first please\n- [ ] [T1] src/other.py - something else entirely different\n"
ro0 = rb0.replace("- [ ] [T1] src/limiter", "- [x] [T1] src/limiter", 1)
rt0 = rb0.replace("fix the limiter", "repair the limiter", 1)
ok("r12-2: ours ticks, theirs rewrites the text -> declined (tick never silently dropped)", declines(rb0, ro0, rt0))
ok("r12-2: same, swapped sides", declines(rb0, rt0, ro0))
res = None
try:
    res = pm.merge_bytes(rb0.encode(), ro0.encode(), rt0.encode())[0].decode()
except ValueError:
    pass
ok("r12-2: whatever happens, a result never lacks the [x]", res is None or "[x]" in res)
ok("r12-2: a plain archive (delete) vs tick of an unrelated-text item is still 'gone' (no over-decline)", not declines(rb0, "## Next Steps\n- [ ] [T1] src/other.py - something else entirely different\n", ro0))

# defect 3: non-item lines edited on both sides
sb = "# Title\nStatus: 5 done\n\n## Sec A (1)\n" + I(1) + "\n"
so = "# Title\nStatus: 6 done\n\n## Sec A (2)\n" + I(1) + "\n"
st_ = "# Title\nStatus: 7 done\n\n## Sec A (3)\n" + I(1) + "\n"
r = lines(merge(sb, so, st_))
ok("r12-3: 'Status:' line edited on both sides -> ONE line, ours' version", [x for x in r if x.startswith("Status:")] == ["Status: 6 done"], str(r))
ok("r12-3: '## Sec A (n)' header edited on both sides -> ONE header, ours'", [x for x in r if x.startswith("## Sec A")] == ["## Sec A (2)"], str(r))
r = lines(merge(sb, st_, so))
ok("r12-3: swapped -> theirs becomes ours' (the other version)", [x for x in r if x.startswith("Status:")] == ["Status: 7 done"], str(r))
ok("r12-3: appended-block headers (no common base line) are still both kept", True)  # asserted by 'two appended blocks keep their own blank+header' above

# defect 6: size cap + driver alarm
big = "\n".join("- [ ] identical line x" for _ in range(pm.MAX_LINES + 1)) + "\n"
t0 = time.process_time()
ok("r12-6: more than MAX_LINES lines -> declined", declines(big, big, big))
ok("r12-6: ... and fast (<2s CPU, no quadratic work)", time.process_time() - t0 < 2, "%.1fs cpu" % (time.process_time() - t0))
mid = "\n".join("- [ ] identical line x" for _ in range(2000)) + "\n"
t0 = time.process_time()   # CPU time, not wall: the Mac runs at load >100 and wall-clock made this flaky (17s wall vs ~3s CPU)
pm.merge_bytes(mid.encode(), mid.encode(), (mid + "- [ ] new item at the end\n").encode())
ok("r12-6: 2000 identical lines still merge in < 10s CPU", time.process_time() - t0 < 10, "%.1fs cpu" % (time.process_time() - t0))
td3 = tempfile.mkdtemp(prefix="pmtest3.")
try:
    for n, d in (("b", "a\n- [ ] x yyyyyyyyyyyyyyyy\n"), ("o", "a\n- [x] x yyyyyyyyyyyyyyyy\n"), ("t", "a\n- [ ] x yyyyyyyyyyyyyyyy (z)\n")):
        open(os.path.join(td3, n), "w").write(d)
    real_mb = pm.merge_bytes
    def slow(*a):
        time.sleep(8)
        return real_mb(*a)
    pm.merge_bytes = slow
    os.environ["OVN_PM_ALARM_S"] = "1"
    t0 = time.time()
    try:
        rc = pm.mode_driver([os.path.join(td3, "b"), os.path.join(td3, "o"), os.path.join(td3, "t")], os.path.join(td3, "log"), "x")
    finally:
        pm.merge_bytes = real_mb
        del os.environ["OVN_PM_ALARM_S"]
    ok("r12-6: a hung merge is cut by the driver alarm -> plain text merge (exit 1, markers), < 5s", rc == 1 and "<<<<<<<" in open(os.path.join(td3, "o")).read() and time.time() - t0 < 5, "rc=%s %.1fs" % (rc, time.time() - t0))
    ok("r12-6: the alarm fallback is logged", "exceeded" in open(os.path.join(td3, "log")).read())
    # defect 5: every ungated driver resolution is logged with the marker
    for n, d in (("b", "a\n- [ ] x yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\n"), ("o", "a\n- [x] x yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\n"), ("t", "a\n- [ ] x yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy (z)\n")):
        open(os.path.join(td3, n), "w").write(d)
    os.remove(os.path.join(td3, "log"))
    rc = pm.mode_driver([os.path.join(td3, "b"), os.path.join(td3, "o"), os.path.join(td3, "t")], os.path.join(td3, "log"), "x")
    lg = open(os.path.join(td3, "log")).read()
    ok("r12-5: a driver resolution without OVN_PM_DEFER is logged with the 'ungated' marker", rc == 0 and "ungated" in lg, lg)
finally:
    shutil.rmtree(td3, ignore_errors=True)

# defect 7: committed conflict markers
mk_b = "## Next Steps\n" + I(1) + "\n" + I(2) + "\n"
for nm, marker in (("<<<<<<<", "<<<<<<< HEAD"), ("=======", "======="), (">>>>>>>", ">>>>>>> origin/x")):
    bad = mk_b + marker + "\n"
    ok("r12-7: marker line %r in ours -> declined" % nm, declines(mk_b, bad, mk_b + I(3) + "\n"))
    ok("r12-7: marker line %r in theirs -> declined" % nm, declines(mk_b, mk_b + I(3) + "\n", bad))
    ok("r12-7: marker line %r in base -> declined" % nm, declines(bad, mk_b, mk_b + I(3) + "\n"))
ok("r12-7: a setext underline '=====' (5) or '<<<<' (4) is not a marker", not declines(mk_b, mk_b + "Title\n=====\n<<<< ok\n", mk_b + I(3) + "\n"))

# defect 8: CLAUDE_QUEUE.md
ok("r12-8: CLAUDE_QUEUE.md is a progress file", "CLAUDE_QUEUE.md" in pm.PROGRESS_FILES)
cq = rd(os.path.join(FIX, "claude_queue.md")).decode()
cql = cq.split("\n")
first = next(i for i, x in enumerate(cql) if x.startswith("- [ ] "))
oq = list(cql); oq[first] = oq[first].replace("[ ]", "[x]", 1)
tq = list(cql); tq[first] = tq[first] + " (cat:godot-edit)"
tq.insert(len(tq) - 1, "- [ ] [T1] scripts/new/thing.gd - Add a brand new helper with a real description. VERIFY: `grep -q thing scripts/new/thing.gd`. (cat:godot; multifile:no) [feat:xlite-20261012-queue-new-thing]")
mq, stq = pm.merge_bytes(cq.encode(), "\n".join(oq).encode(), "\n".join(tq).encode())
mql = mq.decode().split("\n")
ok("r12-8: real xlite CLAUDE_QUEUE.md: tick on one side + tag edit + new item on the other -> tick kept, new item added once, nothing else lost",
   mql[first].startswith("- [x] ") and sum(1 for x in mql if "queue-new-thing" in x) == 1 and len([x for x in mql if x.startswith("- [")]) == len([x for x in cql if x.startswith("- [")]) + 1, str(dict(stq)))
ok("r12-8: CLAUDE_QUEUE.md identity: every real item hashes distinctly (item-hash copes with the VERIFY/backtick line shape)", len({pm.item_hash(x) for x in cql if pm.ITEM_RE.match(x)}) == len([x for x in cql if pm.ITEM_RE.match(x)]))

# ------------------------------------------------------------------------------------------------------------------------------------
# review round 2 (M1-M5)
# ------------------------------------------------------------------------------------------------------------------------------------
# M2: a MODERATE reword (below REWRITE_SIM) of an item the other side ticked must not lose the tick
RB = "## Next Steps\n- [ ] [T1] src/net.py - Add retry handling for X\n- [ ] [T1] src/other.py - Unrelated item number two goes here\n"
RO = RB.replace("- [ ] [T1] src/net.py", "- [x] [T1] src/net.py")
RT = RB.replace("Add retry handling for X", "Implement exponential backoff for X")
for nm, (b_, o_, t_) in (("ours ticked / theirs reworded", (RB, RO, RT)), ("theirs ticked / ours reworded", (RB, RT, RO))):
    try:
        mm = merge(b_, o_, t_)
        ml = lines(mm)
        ok("m2: %s -> the tick is kept" % nm, any(x.startswith("- [x] ") and "Add retry handling for X" in x for x in ml), mm)
        ok("m2: %s -> the rewritten item is kept too (duplicate beats a lost tick)" % nm, any("Implement exponential backoff for X" in x for x in ml), mm)
        ok("m2: %s -> unrelated item untouched, nothing else duplicated" % nm, sum("Unrelated item number two" in x for x in ml) == 1 and len(ml) == 4, mm)
    except ValueError:
        ok("m2: %s -> declined is also acceptable but it must not silently drop" % nm, True)
# no regression: a plain archive (delete) of an item the other side ticked, with no new item in its gap, still deletes
ok("m2: delete with no new item in the gap still deletes (archive flow unchanged)",
   not any("net.py" in x for x in lines(merge(RB, RO, RB.replace("- [ ] [T1] src/net.py - Add retry handling for X\n", "")))))


def _words(rng, n=4):
    pool = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu".split()
    return " ".join(rng.sample(pool, n))


def gen_reword_case(rng):
    """unchecked base items (some feat-tagged); each side: keep / tick / reword in place (maybe + tick) / tag edit, plus new items. NEVER a pure deletion."""
    n = rng.randint(2, 9)
    base = []
    for i in range(n):
        if rng.random() < 0.3:
            base.append("- [ ] [T2] area%d.py - %s (cat:x) [feat:app-20261012-item%d]" % (i, _words(rng), i))
        else:
            base.append("- [ ] [T1] file%d.py - %s" % (i, _words(rng, rng.randint(3, 7))))
    sides = []
    for sd in range(2):
        out = []
        for i, ln in enumerate(base):
            r = rng.random()
            if r < 0.25:
                out.append(ln.replace("- [ ]", "- [x]", 1))
            elif r < 0.5:
                t = "- [ ] [T1] file%d.py - %s" % (i, _words(rng, rng.randint(3, 7))) if "[feat:" not in ln else ln.replace("(cat:x)", "(cat:y%d)" % sd)
                out.append(t.replace("- [ ]", "- [x]", 1) if rng.random() < 0.3 else t)
            else:
                out.append(ln)
            if rng.random() < 0.2:
                out.append("- [ ] [T1] new%d_%d.py - %s" % (sd, i, _words(rng)))
        sides.append(out)
    return base, sides[0], sides[1]


def _checked_hashes(ls):
    return {pm.item_hash(x) for x in ls if pm.ITEM_RE.match(x) and x[3] in "xX"}


rng = random.Random(20261012)
lost, declined, total = [], 0, 3000
for trial in range(total):
    base, ours, theirs = gen_reword_case(rng)
    for (oo, tt) in ((ours, theirs), (theirs, ours)):
        try:
            res, _ = pm.merge_lines(base, oo, tt)
        except ValueError:
            declined += 1
            continue
        want = _checked_hashes(oo) | _checked_hashes(tt)
        got = _checked_hashes(res)
        if not want <= got:
            lost.append((trial, base, oo, tt, res))
    if len(lost) > 3:
        break
ok("m2-prop: %d random cases x 2 directions (incl. rewords): no checked item present on either side ever disappears (%d declined)" % (total, declined), not lost,
   "first loss: " + repr(lost[0] if lost else None))

# M3: short headers
sb = "## Status\n- [ ] [T1] a.py - aaaa bbbb cccc dddd\n"
so = sb.replace("## Status", "## Status (ours)")
st_ = sb.replace("## Status", "## Status (theirs)")
mm = lines(merge(sb, so, st_))
ok("m3: short header edited on both sides is paired (only ours' version kept)", sum(x.startswith("## Status") for x in mm) == 1 and "## Status (ours)" in mm, str(mm))
mm = lines(merge("## S\n- [ ] [T1] a.py - aaaa bbbb cccc dddd\n", "## S (edit1)\n- [ ] [T1] a.py - aaaa bbbb cccc dddd\n", "## S (edit2)\n- [ ] [T1] a.py - aaaa bbbb cccc dddd\n"))
ok("m3: '## S' vs '## S (edit1)' are paired, not both kept", sum(x.startswith("## S") for x in mm) == 1, str(mm))

# M4: a tie is ambiguous -> no pairing, nothing dropped
b4 = "Status: 5 done\n" + I(1) + "\n"
mm = lines(merge(b4, "Status: 6 done\n" + I(1) + "\n", "Status: 7 done\nStatus: 4 done\n" + I(1) + "\n"))
ok("m4: an ambiguous (tied) both-edited match drops nothing", all(x in mm for x in ("Status: 6 done", "Status: 7 done", "Status: 4 done")), str(mm))

# M5: pathological both-edited file is bounded
import time as _t


def _run_to(cmd, env=None, timeout=25):
    """subprocess.run that reports a hang as returncode -9 instead of raising (so a regression is a clean FAIL, not a crash)"""
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(cmd, -9, b"", b"HUNG")


n5 = 5900
b5 = ["## Section %d heading text here" % i for i in range(n5)]
td5 = tempfile.mkdtemp(prefix="pmtest5.")
try:
    for nm_, ls_ in (("b", b5), ("o", [x + " ours" for x in b5]), ("t", [x + " theirs" for x in b5])):
        open(os.path.join(td5, nm_), "w").write("\n".join(ls_) + "\n")
    t0 = _t.time()
    p5 = _run_to([sys.executable, PM_PATH, "--merge", os.path.join(td5, "b"), os.path.join(td5, "o"), os.path.join(td5, "t"), "--out", os.path.join(td5, "m"), "--log", os.path.join(td5, "log")])
    dt = _t.time() - t0
    ok("m5: 5900-line fully both-edited file -> --merge declines cleanly in < 30s (%.1fs)" % dt, p5.returncode == 1 and dt < 30 and not os.path.exists(os.path.join(td5, "m")), "rc=%s %.1fs" % (p5.returncode, dt))
    # the wall-clock alarm covers the non-driver modes too (pairing cap lifted so the quadratic loop really runs)
    env = dict(os.environ, OVN_PM_PAIR_CAP="1000000000", OVN_PM_ALARM_S="2")
    t0 = _t.time()
    p5 = _run_to([sys.executable, PM_PATH, "--merge", os.path.join(td5, "b"), os.path.join(td5, "o"), os.path.join(td5, "t"), "--out", os.path.join(td5, "m"), "--log", os.path.join(td5, "log")], env=env)
    dt = _t.time() - t0
    ok("m5: --merge alarm (OVN_PM_ALARM_S=2) cuts the quadratic pairing and declines (%.1fs)" % dt, p5.returncode == 1 and dt < 15 and b"exceeded" in p5.stderr, "rc=%s %.1fs %r" % (p5.returncode, dt, p5.stderr[:80]))
    # --check-index / --resolve-index: alarm + decline, index untouched
    rp = os.path.join(td5, "repo")
    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=rp, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_GLOBAL="/dev/null"))
    os.makedirs(rp)
    g("init", "-q", "-b", "main")
    small = ["## Section %d heading text here" % i for i in range(1200)]
    for br, suf in (("main", ""), ("a", " ours"), ("b", " theirs")):
        if br != "main":
            g("checkout", "-q", "-b", br, "main")
        open(os.path.join(rp, "OVERNIGHT_PROGRESS.md"), "w").write("\n".join(x + suf for x in small) + "\n")
        g("add", "-A"); g("commit", "-q", "-m", br)
    g("checkout", "-q", "a"); g("merge", "-q", "b")
    for flag in ("--check-index", "--resolve-index"):
        t0 = _t.time()
        env = dict(os.environ, OVN_PM_PAIR_CAP="1000000000", OVN_PM_ALARM_S="2")
        pr = _run_to([sys.executable, PM_PATH, flag, rp, "--log", os.path.join(td5, "log")], env=env)
        dt = _t.time() - t0
        still = g("ls-files", "-u").stdout.strip() != b""
        ok("m5: %s on a pathological index -> exit 1 in < 15s, index still conflicted (never half-merged) (%.1fs)" % (flag, dt), pr.returncode == 1 and dt < 15 and still, "rc=%s %.1fs still=%s" % (pr.returncode, dt, still))
finally:
    shutil.rmtree(td5, ignore_errors=True)

print("  test_progress_merge.py: %d passed, %d failed" % (PASS, len(FAILS)))
sys.exit(1 if FAILS else 0)
