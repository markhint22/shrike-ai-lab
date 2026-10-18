#!/usr/bin/env python3
"""iptv-night F3 (2026-10-13): the R14 VERIFY polarity fix still false-credited COMPOUND narration.

Live: queue_refill's pre-verify path credited two iptv_apps items ("Remove class ParentalControlsService", "Remove PinLockoutTracker") whose VERIFY reads
    `grep -rn "ParentalControlsService" iptv-backend/app/` returns nothing and `python -c "..."` succeeds.
_polarity_of_text returned 'unknown' for ANY narration containing a second backtick, so already_satisfied fell back to "grep exit 0 = satisfied" - exit 0 meant the class was STILL there.
Fix: classify the narration HEAD (up to the first backtick, trailing ' and' dropped); a qualifier anywhere still makes the whole narration unknown; an absence narration that stays
unresolved is never pre-credited from a bare exit status (absence_narration_unresolved + queue_refill.already_satisfied).
Mutations proved in a scratch copy: narration_head disabled (OVN_VERIFY_NARRATION_HEAD=off behaviour) -> the first block fails; the refusal in already_satisfied removed -> the
'unresolved absence' block fails.
"""
import os
import sys
import tempfile
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__))); import tmp_track; tmp_track.install()   # 2026-10-17: every mkdtemp() below is removed at exit (the suite leaked these dirs)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import ovn_backlog_eligibility as E  # noqa: E402
import queue_refill as Q  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


ITEM_PCS = ('- [ ] [T4] iptv-backend/app/services/parental_controls.py — Remove the `class ParentalControlsService` definition and its associated in-memory `PinLockoutTracker` usage, '
            'ensuring module-level functions `profile_rating_ceiling`, `infer_stream_rating`, and `MATURE_CATEGORY_KEYWORDS` remain intact. '
            'VERIFY: `grep -rn "ParentalControlsService" iptv-backend/app/` returns nothing and `python -c "from iptv_backend.app.services.parental_controls import profile_rating_ceiling, '
            'infer_stream_rating, MATURE_CATEGORY_KEYWORDS"` succeeds. (cat:refactor; multifile:yes) [feat:iptv_apps-20261013-delete-the-dead-parentalcontrolsservice-]')
ITEM_PLT = ('- [ ] [T4] iptv-backend/app/services/pin_lockout.py — Remove the `PinLockoutTracker` class definition if it is exclusively used by the deleted `ParentalControlsService`, ensuring no other imports break. '
            'VERIFY: `grep -rn "PinLockoutTracker" iptv-backend/app/` returns nothing and `python -c "import iptv_backend.app.services.pin_lockout"` succeeds. '
            '(cat:refactor; multifile:yes) [feat:iptv_apps-20261013-delete-the-dead-parentalcontrolsservice-]')


def it(v, tail=""):
    return "- [ ] [T2] a.py — x. VERIFY: %s%s (cat:python; multifile:no)" % (v, tail)


print("== the two live items: compound narration 'returns nothing and `python -c ...` succeeds' is an ABSENCE of the first command")
for name, line, needle in (("ParentalControlsService", ITEM_PCS, "ParentalControlsService"), ("PinLockoutTracker", ITEM_PLT, "PinLockoutTracker")):
    cmd, pol = E.verify_clause_and_polarity(line)
    ok("%s: polarity neg" % name, pol == "neg", (cmd, pol))
    ok("%s: the command run is the grep (the first backtick)" % name, cmd.startswith("grep -rn") and needle in cmd, cmd)
    ok("%s: tool class grep" % name, E.verify_tool_class(cmd) == "grep")

print("== narration_head")
ok("head stops at the first backtick and drops the trailing ' and'", E.narration_head(' returns nothing and `python -c "x"` succeeds') == "returns nothing", E.narration_head(' returns nothing and `python -c "x"` succeeds'))
ok("a narration with no backtick is returned whole", E.narration_head(" returns no matches") == "returns no matches")
ok("trailing comma / semicolon dropped too", E.narration_head("returns no output; `ls x` fails") == "returns no output")
ok("a backtick that CONTINUES the sentence ('containing `X`') quotes an operand: the whole text is kept (=> unknown)", "`" in E.narration_head("returns no lines containing `X = {}`"), E.narration_head("returns no lines containing `X = {}`"))

print("== polarity of other compound shapes")
for v, tail, want in (
    ('`grep -n x f`', ' returns no matches and `ls g` fails.', "neg"),
    ('`grep -n x f`', ' returns matches and `ls g` succeeds.', "pos"),
    ('`grep -n x f`', ' returns no matches for `foo` but returns matches for `bar`.', "unknown"),   # qualifier in the tail: still unknown
    ('`grep -n x f`', ' returns no matches before the change and `pytest y` passes.', "unknown"),   # red-state qualifier
    ('`grep -n x f`', ' returns no lines containing `foo = {}`.', "unknown"),                      # the quoted operand NARROWS the claim below what the command checks (audit: discover.py _cache)
    ('`grep -n x f`', ' returns no matches for `foo`.', "unknown"),
    ('`grep -n x f`', ' and `ls g`', "unknown"),                                                   # no verdict words at all
    ('`pytest tests/test_a.py`', ' fails and `ls g` succeeds.', "unknown"),                         # a runner narrating fails is still unknown
    ('`! grep -n x f`', ' returns no matches and `ls g` fails.', "unknown"),                        # already negated
):
    got = E.verify_polarity(it(v, tail))
    ok("%s%s -> %s" % (v, tail[:48], want), got == want, got)

print("== kill switch OVN_VERIFY_NARRATION_HEAD=off restores 'any backtick = unknown'")
os.environ["OVN_VERIFY_NARRATION_HEAD"] = "off"
ok("off: the live item is unknown again", E.verify_polarity(ITEM_PCS) == "unknown")
del os.environ["OVN_VERIFY_NARRATION_HEAD"]
ok("on again: neg", E.verify_polarity(ITEM_PCS) == "neg")

print("== queue_refill.already_satisfied on the exact live shapes (the false credit)")
d = tempfile.mkdtemp(prefix="polc-")
os.makedirs(os.path.join(d, "iptv-backend", "app", "services"))
with open(os.path.join(d, "iptv-backend", "app", "services", "parental_controls.py"), "w") as f:
    f.write("class ParentalControlsService:\n    pass\n\n\ndef profile_rating_ceiling():\n    return 1\n")
ok("class STILL in the tree + 'returns nothing and `python -c` succeeds' -> NOT credited (was credited: 'unknown' -> grep rc 0)", Q.already_satisfied(ITEM_PCS, d) is False)
with open(os.path.join(d, "iptv-backend", "app", "services", "parental_controls.py"), "w") as f:
    f.write("def profile_rating_ceiling():\n    return 1\n")
ok("class gone -> credited (grep rc 1 = absent)", Q.already_satisfied(ITEM_PCS, d) is True)
ok("class gone, grep error (missing dir) is not an absence", Q.already_satisfied(ITEM_PCS.replace("iptv-backend/app/", "nodir/app/"), d) is False)

print("== absence_narration_unresolved: an absence narration the reader could not resolve is never pre-credited")
RED = it('`grep -n "Gone" a.py`', " returns no matches before the change.")
ok("red-state absence narration (polarity unknown) is flagged", E.absence_narration_unresolved(RED) is True)
ok("a resolved neg item is not flagged", E.absence_narration_unresolved(ITEM_PCS) is False)
ok("no narration is not flagged", E.absence_narration_unresolved(it('`grep -n x a.py`')) is False)
ok("a pos narration is not flagged", E.absence_narration_unresolved(it('`grep -n x a.py`', " returns matches.")) is False)
ok("already-negated command is not flagged", E.absence_narration_unresolved(it('`! grep -n x a.py`', " returns no matches.")) is False)
ok("a runner is not flagged", E.absence_narration_unresolved(it('`pytest x`', " fails.")) is False)
ok("no VERIFY at all is not flagged", E.absence_narration_unresolved("- [ ] [T2] a — b (cat:x)") is False)
with open(os.path.join(d, "a.py"), "w") as f:
    f.write("Gone = 1\n")
ok("already_satisfied refuses the unresolved absence item although grep exits 0", Q.already_satisfied(RED, d) is False)
ok("CONTROL: the same grep without narration still credits (unchanged behaviour)", Q.already_satisfied(it('`grep -n "Gone" a.py`'), d) is True)
os.environ["OVN_VERIFY_AMBIGUOUS_NEG"] = "off"
ok("kill switch OVN_VERIFY_AMBIGUOUS_NEG=off: not flagged, old reading (credited on rc 0)", E.absence_narration_unresolved(RED) is False and Q.already_satisfied(RED, d) is True)
del os.environ["OVN_VERIFY_AMBIGUOUS_NEG"]

print("== MUTATION: refusal removed -> the unresolved-absence credit comes back")
_f = E.absence_narration_unresolved
E.absence_narration_unresolved = lambda line: False
try:
    ok("mutant credits the unresolved absence item (proves the test above can fail)", Q.already_satisfied(RED, d) is True)
finally:
    E.absence_narration_unresolved = _f

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
