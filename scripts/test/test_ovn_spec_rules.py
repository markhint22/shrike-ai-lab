#!/usr/bin/env python3
"""scripts/ovn_spec_rules.py (spec-compiler-v2 C2): rules R01-R08, R10.
R02/R03 repairs are BEHAVIOURAL: the repaired VERIFY is executed in a temp tree where the target is present and absent and the red-before / green-after polarity is
asserted. Mutations: PASS/FAIL swapped in the R02 regex, the R03 phrase matcher disabled, the R06 replay with the reorder removed. All repository reads happen at a ref
(a committed branch) - the working tree of the fixture is deliberately left dirty to prove it is never read."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def it(target, text, verify="`true`", feat=None, tier="T2"):
    s = "- [ ] [%s] %s — %s VERIFY: %s. (cat:python; multifile:no)" % (tier, target, text, verify)
    return s + (" [feat:%s]" % feat if feat else "")


def rules_of(fs):
    return sorted(f["rule"] for f in fs)


def run(cmd, cwd):
    return subprocess.run(["bash", "-c", cmd], cwd=cwd, capture_output=True).returncode


# ------------------------------------------------------------------ fixture repo at a ref
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
WORK = os.path.realpath(tempfile.mkdtemp(prefix="rules-"))
REPO = os.path.join(WORK, "repo")
os.makedirs(REPO)


def g(*a):
    return subprocess.run(["git", "-C", REPO] + list(a), capture_output=True, text=True)


FILES = {
    "scripts/enemy/enemy_faction_map.gd": "func get_faction(id):\n\treturn 1\nfunc get_all_factions():\n\treturn []\nfunc never_called():\n\treturn 0\nfunc self_ref():\n\treturn self_ref()\n",
    "tests/test_enemy_faction_map.gd": "func test_a():\n\tvar f = get_faction(1)\nfunc test_b():\n\tvar all = get_all_factions()\n",
    "scripts/other.gd": "func get_faction_x():\n\treturn 2\nfunc use():\n\tget_faction_x()\n",
    "scripts/ai/ai.gd": "func decide():\n\tvar f = get_prod_only()\n\treturn f\n",
    "scripts/ai/prod_def.gd": "func get_prod_only():\n\treturn 1\n",
    "scenes/ui.tscn": "[connection signal=\"pressed\" method=\"get_scene_only\"]\n",
    "scripts/ui/scene_def.gd": "func get_scene_only():\n\treturn 3\n",
    "OVERNIGHT_PROGRESS.md": "- [x] mention get_doc_only in progress\n",
    "docs/NOTES.md": "get_doc_only is described here\n",
    "scripts/doc_def.gd": "func get_doc_only():\n\treturn 4\n",
    "addons/gut/gut.gd": "func get_vendored():\n\treturn 5\n",
    "iptv/rep.py": "def recompute_representative(items, weights=None):\n    out = []\n    for it in items:\n        out.append(it)\n    return out\n\ndef helper_a():\n    return 1\n",
    "scripts/battle/thing.gd": "func do_it(a, b):\n\tprint(a)\nfunc other_fn():\n\tpass\n",
    "iptv/bad.py": "def broken(:\n",
    "iptv/url_safety.py": "def safe_get(url):\n    return url\n",
    "ROADMAP.md": "remember to delete get_roadmap_only someday\n",
    "scripts/road_def.gd": "func get_roadmap_only():\n\treturn 6\n",
    ".queue-hard-banned-files": "# banned\nscripts/battle/battle.gd\ntests/test_mission_select\n",
    "docs/ARCH.md": "architecture\n",
    "scripts/battle/battle.gd": "func x():\n\tpass\n",
}
g("init", "-q")
g("checkout", "-q", "-b", "main")
for rp, body in FILES.items():
    fp = os.path.join(REPO, rp)
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    open(fp, "w").write(body)
g("add", "-A")
subprocess.run(["git", "-C", REPO] + GIT[1:] + ["commit", "-q", "-m", "init"], capture_output=True)
# dirty the working tree: a reference that only exists there must NEVER be seen (reads are at the ref)
open(os.path.join(REPO, "scripts/enemy/worktree_only.gd"), "w").write("func get_faction():\n\tpass\n")
open(os.path.join(REPO, "never_called_ref.gd"), "w").write("never_called()\n")
ctx = R.Ctx(REPO, "main")
FEAT = "xlite-20261009-enemy-faction-map"

# ------------------------------------------------------------------ R01
print("== R01 bare VERIFY -> backticked")
for cmd in ("grep -q alpha f.txt", "test -f f.txt", "ls f.txt", "python3 -c \"assert 1\"", "python -c \"assert 1\"", "pytest tests/test_a.py -q", "cd sub && ls",
            "godot --headless -s x.gd", "npm test", "npx vitest run", "./gradlew test"):
    line = "- [ ] [T2] a.py — do it. VERIFY: %s (cat:python; multifile:no)" % cmd
    l2, fs = R.lint_static(line)
    ok("R01 repairs bare `%s`" % cmd, rules_of(fs) == ["R01"] and ("VERIFY: `%s` (cat:" % cmd) in l2, (l2, fs))
line = "- [ ] [T2] a.py — do it. VERIFY: pytest tests/test_a.py -q. (cat:python; multifile:no)"
l2, fs = R.lint_static(line)
ok("R01 drops the sentence period glued to the last token", "VERIFY: `pytest tests/test_a.py -q` (cat:" in l2, l2)
ok("R01 finding shape: rule/sev/msg/evidence", fs and set(fs[0]) == {"rule", "sev", "msg", "evidence"} and fs[0]["sev"] == "repair")
ok("R01 is idempotent", R.lint_static(l2) == (l2, []))
for name, bad in (("prose", "the tests pass"), ("prose with a command word", "pytest tests/test_a.py passes"), ("unbalanced quotes", 'grep -q "unbalanced tests/x.py'),
                  ("unknown command", "curl localhost"), ("empty-ish", "see above")):
    line = "- [ ] [T2] a.py — do it. VERIFY: %s (cat:python)" % bad
    ok("R01 NEGATIVE leaves %s alone" % name, R.lint_static(line) == (line, []), R.lint_static(line))
backt = "- [ ] [T2] a.py — do it. VERIFY: `grep -q a f` . (cat:python)"
ok("R01 NEGATIVE: an already backticked clause is untouched", R.lint_static(backt) == (backt, []))
ok("R01 only= filter: not applied when R01 is not in the set", R.lint_static("- [ ] [T2] a — x. VERIFY: ls f (cat:p)", only={"R02", "R03"})[1] == [])
# behavioural: the repaired command runs exactly as authored
td = os.path.join(WORK, "r01")
os.makedirs(td)
open(os.path.join(td, "f.txt"), "w").write("alpha\n")
l2, _ = R.lint_static("- [ ] [T2] a — x. VERIFY: grep -q alpha f.txt. (cat:p)")
ok("R01 BEHAVIOUR: the backticked command passes where alpha exists and fails where it does not", run(E.extract_verify(l2), td) == 0 and run(E.extract_verify(l2).replace("alpha", "beta"), td) != 0)

# ------------------------------------------------------------------ R02
print("== R02 vacuous echo idiom (behavioural)")
present, absent = os.path.join(WORK, "present"), os.path.join(WORK, "absent")
for d in (present, absent):
    os.makedirs(d)
open(os.path.join(present, "f.txt"), "w").write("old_name here\n")
open(os.path.join(absent, "f.txt"), "w").write("new_name here\n")
fp = it("f.txt", "Rename it.", "`grep -q old_name f.txt && echo \"FAIL\" || echo \"PASS\"`")
pf = it("f.txt", "Add it.", "`grep -q old_name f.txt && echo \"PASS\" || echo \"FAIL\"`")
fp2, f1 = R.lint_static(fp)
pf2, f2 = R.lint_static(pf)
ok("R02 reports a repair finding for both shapes", rules_of(f1) == ["R02"] and rules_of(f2) == ["R02"], (f1, f2))
c_fp, c_pf = E.extract_verify(fp2), E.extract_verify(pf2)
ok("R02 BEHAVIOUR (before): the idiom as authored exits 0 whether or not the target is there", run(E.extract_verify(fp), present) == 0 and run(E.extract_verify(fp), absent) == 0)
ok("R02 BEHAVIOUR: FAIL/PASS repaired = red-before (old_name present) / green-after (gone)", run(c_fp, present) != 0 and run(c_fp, absent) == 0, c_fp)
ok("R02 BEHAVIOUR: PASS/FAIL repaired = green while present, red when absent", run(c_pf, present) == 0 and run(c_pf, absent) != 0, c_pf)
ok("R02 is idempotent", R.lint_static(fp2) == (fp2, []) and R.lint_static(pf2) == (pf2, []))
awk = it("f.txt", "x.", "`grep old f.txt | awk 'NR>1' && echo \"FAIL\" || echo \"PASS\"`")
ok("R02 NEGATIVE: awk/pipe shapes are left alone", [f["rule"] for f in R.lint_static(awk)[1]] == [])
ok("R02 queue_refill's _ALWAYS_TRUE_RE no longer sees the repaired VERIFY", not re.search(r"\|\|\s*(echo|printf|true)\b", c_fp + c_pf))
_s = E._VAC_FAILPASS
E._VAC_FAILPASS = re.compile(_s.pattern.replace("FAIL", "@@").replace("PASS", "FAIL").replace("@@", "PASS"))
m_l, _ = R.lint_static(fp)
E._VAC_FAILPASS = _s
mc = E.extract_verify(m_l)
ok("MUTATION (PASS/FAIL swapped in the regex): the polarity assertion fails", not (run(mc, present) != 0 and run(mc, absent) == 0), mc)

# ------------------------------------------------------------------ R03
print("== R03 narrated failure -> `! cmd` (behavioural)")
r3 = it("f.txt", "Remove old_name.", "`grep -q old_name f.txt` returns non-zero after the change")
r3b, f3 = R.lint_static(r3)
ok("R03 repair finding", rules_of(f3) == ["R03"], f3)
c3 = E.extract_verify(r3b)
ok("R03 rewrites to `! cmd` and drops the narration", c3 == "! grep -q old_name f.txt" and "returns non-zero" not in r3b and "after the change" not in r3b, r3b)
ok("R03 BEHAVIOUR: red while old_name is present, green once gone", run(c3, present) != 0 and run(c3, absent) == 0)
for phrase in ("fails", "returns non-zero", "no matches", "No such file"):
    l, fs = R.lint_static(it("f.txt", "x.", "`grep -q a f.txt` %s" % phrase))
    ok("R03 phrase '%s' triggers" % phrase, rules_of(fs) == ["R03"], (l, fs))
l, fs = R.lint_static(it("f.txt", "x.", "`cd d && grep -q a f.txt` fails"))
ok("R03 compound commands are wrapped: `! ( cd d && grep ... )`", E.extract_verify(l) == "! ( cd d && grep -q a f.txt )", l)
ok("R03 is idempotent", R.lint_static(r3b) == (r3b, []))
ok("R03 NEGATIVE: already negated command untouched", R.lint_static(it("f.txt", "x.", "`! grep -q a f.txt` fails"))[1] == [])
_lg = it("f.txt", "x.", "`grep -q a f.txt` " + "and some very long unrelated explanation " * 2 + "fails")
ok("R03 NEGATIVE: a long unrelated sentence that merely contains 'fails' is never rewritten (flagged only)", R.lint_static(_lg)[0] == _lg and [f["sev"] for f in R.lint_static(_lg)[1]] == ["flag"])
ok("R03 NEGATIVE: the word 'fails' only inside the command text is not narration", R.lint_static(it("f.txt", "x.", "`grep -q fails f.txt`"))[1] == [])
ok("R03 NEGATIVE: narration after '(cat:' does not count", R.lint_static("- [ ] [T2] f — x. VERIFY: `grep -q a f` (cat:python; fails soon)")[1] == [])
# review defects (spec-compiler-v2 fixer): R03 must never invert the polarity of a test runner or mangle prose
print("== R03 safety: runners, passes/before/else narration, compound statements, pipes")
_neg = [
    ("(a) pytest ... passes (the old code fails this)", "`pytest tests/test_a.py -q` passes (the old code fails this)"),
    ("(b) which fails before and passes after", "`pytest tests/test_a.py::test_x -q` which fails before and passes after"),
    ("(c) suite no longer fails", "`pytest -q` \u2014 suite no longer fails"),
    ("(d) test -f (else No such file)", "`test -f a.py` (else No such file)"),
    ("npm test narrating a failure", "`npm test` fails before the change"),
    ("godot narrating a failure", "`godot --headless -s t.gd` fails"),
    ("second backticked command in the window", "`test -f a.py` fails and `cd d && pytest -q` passes"),
    ("single pipe (negation would apply to the last stage)", "`grep -q a f.txt | wc -l` fails after the change"),
    ("veto word 'passes' inside the sentence", "`grep -q a f.txt` fails and the other check passes"),
]
for nm, v in _neg:
    l, fs = R.lint_static(it("f.txt", "x.", v))
    ok("R03 NEGATIVE %s: line untouched, no repair" % nm, l == it("f.txt", "x.", v) and not [f for f in fs if f["sev"] == "repair"], (l, fs))
l, fs = R.lint_static(it("f.txt", "x.", "`cd d && pytest -q` fails"))
ok("R03 NEGATIVE: compound with a test runner clause untouched", fs == [] and "! (" not in l, l)
l, fs = R.lint_static(it("f.txt", "x.", "`grep -q a f.txt` which fails after the change"))
ok("R03 POSITIVE: 'which fails' lead-in on a grep still repairs cleanly", rules_of(fs) == ["R03"] and E.extract_verify(l) == "! grep -q a f.txt" and "after the change" not in l, l)
ok("R03 NEGATIVE: no stray prose fragments are ever left behind by a repair", all(not x.endswith("this)") for x in [R.lint_static(it("f.txt", "x.", v))[0] for _, v in _neg]))
_cok = R._r03_cmd_ok
R._r03_cmd_ok = lambda cmd: True
mut_l, mut_f = R.lint_static(it("f.txt", "x.", "`pytest -q` fails"))
R._r03_cmd_ok = _cok
ok("MUTATION (command allowlist disabled): pytest narration would be negated", rules_of(mut_f) == ["R03"] and "! pytest" in mut_l, mut_l)
_p = R._R03_NARR
R._R03_NARR = re.compile("NEVERMATCHES")
mut_l, mut_f = R.lint_static(r3)
R._R03_NARR = _p
ok("MUTATION (narration whitelist matches nothing): the R03 repair assertions fail", [f["sev"] for f in mut_f] != ["repair"] and mut_l == r3)

# review round 2 (spec-compiler-v2 fixer 3): R03 is a WHITELIST - a temporal / conditional narration is never inverted, it is flagged for a human
print("== R03 whitelist: temporal / conditional narrations are never rewritten")
_TEMPORAL = ["in the old code", "on the current code", "today", "at present", "pre-change", "prior to the change", "initially", "at first", "right now", "until the fix lands",
             "when the symbol is present", "because the file is missing", "(expected: red)", "with RuntimeError when the env var is unset", "currently", "on main",
             "before the change", "if the file exists", "unless it is deleted", "but passes after", "and then passes", "no longer"]
for t in _TEMPORAL:
    v = "`grep -q foo a.py` fails %s" % t
    l, fs = R.lint_static(it("a.py", "x.", v))
    ok("R03 WHITELIST NEGATIVE 'fails %s': untouched, flagged, never repaired" % t, l == it("a.py", "x.", v) and [f["sev"] for f in fs] == ["flag"] and fs[0]["rule"] == "R03", (l, fs))
    v2 = "`test -f a.py` returns non-zero %s" % t
    l2, fs2 = R.lint_static(it("a.py", "x.", v2))
    ok("R03 WHITELIST NEGATIVE 'returns non-zero %s': no repair, line untouched" % t, l2 == it("a.py", "x.", v2) and not [f for f in fs2 if f["sev"] == "repair"], (l2, fs2))
_py = it("iptv/a.py", "Guard the import.", "`python -c \"import iptv_backend.app.main\"` fails with RuntimeError when env var is unset")
l, fs = R.lint_static(_py)
ok("R03 WHITELIST NEGATIVE (the real-data wrong repair): python -c 'fails with RuntimeError when env var is unset' stays untouched", l == _py and fs == [], (l, fs))
l, fs = R.lint_static(it("a.py", "x.", "`python3 -c \"import os; os.stat('nope')\"` returns non-zero"))
ok("R03 NEGATIVE: python -c is no longer an R03 command (its narration is conditional)", fs == [] and "!" not in l.split("VERIFY:")[1][:3], (l, fs))
# the shapes the whitelist DOES accept (all seen in the live queue / backlog on 2026-10-09)
for nm, v, want in [
    ("returns non-zero exit code.", "`test -f tests/test_scatter.gd.uid` returns non-zero exit code", "! test -f tests/test_scatter.gd.uid"),
    ("returns non-zero.", "`test -f tests/a.gd.uid` returns non-zero", "! test -f tests/a.gd.uid"),
    ("fails with No such file", "`ls tests/a.gd.uid` fails with \"No such file or directory\"", "! ls tests/a.gd.uid"),
    ("returns non-zero exit code on a recursive grep", "`grep -rn \"flakes_quarantine\" backend/app --include=\"*.py\"` returns non-zero exit code", "! grep -rn \"flakes_quarantine\" backend/app --include=\"*.py\""),
    ("fails after the change", "`grep -q a f.txt` fails after the change", "! grep -q a f.txt"),
    ("must fail once the fix is applied", "`grep -q a f.txt` must fail after the fix is applied and then some", None),
]:
    l, fs = R.lint_static(it("f.txt", "x.", v))
    if want is None:
        ok("R03 WHITELIST: %s is NOT accepted (unknown tail) - untouched" % nm, [f["sev"] for f in fs] == ["flag"], (l, fs))
        continue
    ok("R03 WHITELIST POSITIVE %s" % nm, rules_of(fs) == ["R03"] and E.extract_verify(l) == want and l.endswith(". (cat:python; multifile:no)") and ".." not in l, (l, fs))
l, fs = R.lint_static(it("f.txt", "x.", "`grep -rn x f.txt` returns no matches"))
ok("R03 whitelist: 'returns no matches' (not in the pre-review accepted set) is flagged for a human, not rewritten", [f["sev"] for f in fs] == ["flag"] and "! grep" not in l, (l, fs))
l, fs = R.lint_static(it("f.txt", "x.", "`grep -q a f.txt` fails after the change"))
ok("R03 whitelist: the narration is dropped, the sentence's period and the rest of the line survive", ".." not in l and "after the change" not in l and l.count("VERIFY:") == 1, l)
# MUTATION: the old blacklist behaviour (any sentence containing a phrase and no veto word is accepted) would invert the temporal narrations
_n = R._R03_NARR
R._R03_NARR = re.compile(r"^.*(?:fails?|returns? non-?zero).*$", re.I)
_bad = 0
for t in _TEMPORAL:
    l, fs = R.lint_static(it("a.py", "x.", "`grep -q foo a.py` fails %s" % t))
    _bad += 1 if [f for f in fs if f["sev"] == "repair"] else 0
R._R03_NARR = _n
ok("MUTATION (whitelist replaced by 'phrase anywhere'): temporal narrations WOULD be inverted (%d of %d)" % (_bad, len(_TEMPORAL)), _bad == len(_TEMPORAL))
# replay the real VERIFY corpus (if the fixture file is given): every R03 repair must be a plain grep/test/ls negation with a whitelisted tail
_corp = os.environ.get("OVN_R03_CORPUS", "")
if _corp and os.path.exists(_corp):
    _n_rep = _n_bad = 0
    for raw in open(_corp, errors="replace"):
        raw = raw.rstrip("\n")
        l2, f2 = R.lint_static(raw, only={"R03"})
        if [f for f in f2 if f["sev"] == "repair"]:
            _n_rep += 1
            c = E.extract_verify(l2) or ""
            _n_bad += 0 if re.match(r"^! (?:\( )?(?:grep|egrep|fgrep|rg|test|\[|ls|cat|stat) ", c) else 1
    print("  info  corpus replay: %d R03 repairs, %d outside the plain negation shape" % (_n_rep, _n_bad))
    ok("R03 corpus replay: no repair outside the plain grep/test/ls negation shape", _n_bad == 0)

# ------------------------------------------------------------------ R04
print("== R04 banned / vendored target")
ok("R04 addons/gut/gut.gd -> reject", rules_of(R.lint_item(it("addons/gut/gut.gd", "Change it."), ctx)[1]) == ["R04"])
ok("R04 reject severity and evidence", R.lint_item(it("addons/gut/gut.gd", "Change it."), ctx)[1][0]["sev"] == "reject")
ok("R04 hard-banned file from .queue-hard-banned-files AT THE REF -> reject", "R04" in rules_of(R.lint_item(it("scripts/battle/battle.gd", "Change it."), ctx)[1]))
ok("R04 banned test prefix (unanchored ERE) -> reject", "R04" in rules_of(R.lint_item(it("tests/test_mission_select_x.gd", "Change it."), ctx)[1]))
ok("R04 NEGATIVE: docs/ path is not a banned target", "R04" not in rules_of(R.lint_item(it("docs/ARCH.md", "Update it."), ctx)[1]))
ok("R04 NEGATIVE: unlisted file", "R04" not in rules_of(R.lint_item(it("scripts/battle/thing.gd", "Change it."), ctx)[1]))
ok("R04 NEGATIVE: banned path only inside the VERIFY clause", "R04" not in rules_of(R.lint_item(it("scripts/battle/thing.gd", "Change it.", "`grep -q x addons/gut/gut.gd`"), ctx)[1]))
ok("R04 without a ctx still catches addons/", "R04" in rules_of(R.lint_item(it("addons/x.gd", "Change it."), None)[1]))

# ------------------------------------------------------------------ R05
print("== R05 non-actionable text")
for name, text in (("Verify only", "Verify that the faction map works as expected."), ("Ensure only", "Ensure the config is sane."), ("Check only", "Check the logs."),
                   ("Confirm only", "Confirm nothing else breaks."), ("Run only", "Run the full test suite."), ("Review only", "Review the module."),
                   ("conditional", "If the helper is unused, delete it."), ("manual inspection", "Rename the field after manual inspection of the callers.")):
    ok("R05 flags: " + name, "R05" in rules_of(R.lint_item(it("a.py", text), ctx)[1]), text)
prose = "- [ ] [T2] a.py — Add the guard. VERIFY: all the tests pass and nothing regresses (cat:python)"
ok("R05 flags a prose VERIFY that cannot be run", "R05" in rules_of(R.lint_item(prose, ctx)[1]))
ok("R05 NEGATIVE: 'Check ... and add' has a change verb", "R05" not in rules_of(R.lint_item(it("a.py", "Check the cache key and add a guard for None."), ctx)[1]))
ok("R05 NEGATIVE: ordinary change item", "R05" not in rules_of(R.lint_item(it("a.py", "Add a pure function `f()`."), ctx)[1]))
ok("R05 NEGATIVE: a bare but runnable VERIFY is not 'prose' (R01 repairs it instead)", "R05" not in rules_of(R.lint_item("- [ ] [T2] a.py — Add it. VERIFY: grep -q a a.py (cat:python)", ctx)[1]))
ok("R05 NEGATIVE: 'verification' inside a later sentence is not a leading verb", "R05" not in rules_of(R.lint_item(it("a.py", "Add a guard; verification is by VERIFY."), ctx)[1]))

# ------------------------------------------------------------------ R06
print("== R06 delete-with-live-refs (replay of the 10-09 enemy_faction_map batch)")
D1 = it("scripts/enemy/enemy_faction_map.gd", "Delete func get_faction() from the faction map.", "`! grep -q 'func get_faction' scripts/enemy/enemy_faction_map.gd`", FEAT, "T3")
D2 = it("scripts/enemy/enemy_faction_map.gd", "Delete func get_all_factions() from the faction map.", "`! grep -q 'func get_all_factions' scripts/enemy/enemy_faction_map.gd`", FEAT, "T3")
T3 = it("tests/test_enemy_faction_map.gd", "Remove the tests that call get_faction and get_all_factions.", "`! grep -q get_faction tests/test_enemy_faction_map.gd`", FEAT)
out = R.lint_batch([D1, D2, T3], ctx)
ok("replay: item 1 (delete get_faction) is flagged R06", "R06" in rules_of(out[0][1]), out[0][1])
ok("replay: item 2 (delete get_all_factions) is flagged R06", "R06" in rules_of(out[1][1]), out[1][1])
ok("replay: item 3 (remove the tests) is NOT flagged", "R06" not in rules_of(out[2][1]), out[2][1])
ev = [f for f in out[0][1] if f["rule"] == "R06"][0]
ok("replay: the finding names the reorder (item 3) and the hit file, not the dirty working tree", ev["evidence"]["reorder_after_items"] == [3] and ev["evidence"]["files"] == ["tests/test_enemy_faction_map.gd"], ev)
ok("replay: finding severity is flag", ev["sev"] == "flag")
out = R.lint_batch([T3, D1, D2], ctx)
ok("swapping the order (tests first) clears R06 on both deletes", all("R06" not in rules_of(o[1]) for o in out), [o[1] for o in out])
out = R.lint_batch([D1, T3, D2], ctx)
ok("partial order: delete get_faction before the tests still flagged, delete get_all_factions after the tests is clear", "R06" in rules_of(out[0][1]) and "R06" not in rules_of(out[2][1]))
T3_other_feat = it("tests/test_enemy_faction_map.gd", "Remove the tests that call get_faction.", "`true`", "xlite-20261001-other-batch")
out = R.lint_batch([T3_other_feat, D1], ctx)
ok("an earlier Remove item in a DIFFERENT [feat] batch does not clear it", "R06" in rules_of(out[1][1]))
ok("R06 single-item (lint_item) also reports", "R06" in rules_of(R.lint_item(D1, ctx)[1]))
ok("NEGATIVE: no references anywhere (never_called) -> clear (the dirty-worktree reference is never read)", "R06" not in rules_of(R.lint_item(it("scripts/enemy/enemy_faction_map.gd", "Delete func never_called() from the map."), ctx)[1]))
ok("NEGATIVE: references only in the same file (self_ref) -> clear", "R06" not in rules_of(R.lint_item(it("scripts/enemy/enemy_faction_map.gd", "Remove `self_ref()` from the map."), ctx)[1]))
ok("NEGATIVE: references only in OVERNIGHT_PROGRESS.md / docs/ -> clear", "R06" not in rules_of(R.lint_item(it("scripts/doc_def.gd", "Delete func get_doc_only() entirely."), ctx)[1]))
ok("NEGATIVE: references only in addons/ are ignored", "R06" not in rules_of(R.lint_item(it("scripts/vendor.gd", "Delete func get_vendored() entirely."), ctx)[1]))
ok("NEGATIVE (-w semantics): get_faction_x elsewhere does not count as a get_faction reference", [f for f in R.lint_item(D1, ctx)[1] if f["rule"] == "R06"][0]["evidence"]["files"] == ["tests/test_enemy_faction_map.gd"])
pc = R.lint_item(it("scripts/ai/prod_def.gd", "Delete func get_prod_only() as dead code."), ctx)[1]
r6 = [f for f in pc if f["rule"] == "R06"]
ok("production-code reference -> R06 (queue time: hold) with the production file in the evidence", r6 and r6[0]["evidence"]["production_refs"] == ["scripts/ai/ai.gd"] and "production" in r6[0]["msg"], pc)
sc = R.lint_item(it("scripts/ui/scene_def.gd", "Delete func get_scene_only() as dead code."), ctx)[1]
ok("a .tscn connection counts as a reference", any(f["rule"] == "R06" and "scenes/ui.tscn" in f["evidence"]["files"] for f in sc), sc)
ok("NEGATIVE: a 'remove the tests that call ...' item is not itself a symbol deletion", all("R06" not in rules_of(o[1]) for o in R.lint_batch([T3], ctx)))
ok("NEGATIVE: Add items are never R06", "R06" not in rules_of(R.lint_item(it("scripts/enemy/enemy_faction_map.gd", "Add func get_faction() to the map."), ctx)[1]))
# real-backlog false positives found by linting 155 landed items at the live ref (2026-10-09): noise words, parameter/file removals, *.md references
def r6(text, target="scripts/enemy/enemy_faction_map.gd"):
    return [f for f in R.lint_item(it(target, text), ctx)[1] if f["rule"] == "R06"]


ok("R06 'Remove the `get_faction` method definition' names get_faction, not the noise word 'definition'", r6("Remove the `get_faction` method definition.") and r6("Remove the `get_faction` method definition.")[0]["evidence"]["symbol"] == "get_faction")
ok("R06 with a constant first: 'Remove the `LIMIT` constant and the `get_faction` method definition' still finds get_faction", r6("Remove the `LIMIT` constant and the `get_faction` method definition.") and r6("Remove the `LIMIT` constant and the `get_faction` method definition.")[0]["evidence"]["symbol"] == "get_faction")
ok("NEGATIVE: removing a PARAMETER from a function is not deleting the function", not r6("Remove the `intent_data: Dictionary` parameter from the `get_faction` function signature."))
ok("NEGATIVE: 'Remove the unused argument `flag` from `get_faction()`'", not r6("Remove the unused argument `flag` from `get_faction()`."))
ok("NEGATIVE: 'Delete the entire file containing ghost tests for `get_faction`' is a file deletion", not r6("Delete the entire file containing ghost tests for `get_faction`."))
ok("NEGATIVE: 'Remove the import of `get_faction`'", not r6("Remove the import of `get_faction` from the map."))
ok("NEGATIVE: 'Remove redundant direct calls to `get_faction` in the old locations' removes calls, not the definition", not r6("Remove redundant direct calls to `get_faction` and `get_all_factions` in original locations."))
ok("NEGATIVE: 'Remove the redundant `def get_faction()`' (a duplicate definition remains)", not r6("Remove the redundant `def get_faction() -> int:` and keep the other."))
ok("NEGATIVE: 'Remove the first `def get_faction()` block' (a duplicate definition remains)", not r6("Remove the first `def get_faction() -> int:` block and keep the second."))
ok("NEGATIVE: references only in a top-level *.md (ROADMAP.md) are not live references", not R.lint_item(it("scripts/road_def.gd", "Delete func get_roadmap_only() entirely."), ctx)[1])
n0 = ctx.git_calls
R.lint_batch([D1, D2, T3], ctx)
R.lint_batch([D1, D2, T3], ctx)
ok("every git read is cached on the Ctx (a second pass costs no git call)", ctx.git_calls == n0, (n0, ctx.git_calls))
bad = R.Ctx(REPO, "no-such-ref")
ok("fail-safe: an unreadable ref yields no R06/R08 finding and no crash", "R06" not in rules_of(R.lint_item(D1, bad)[1]) and bad.tree() == set())
# mutation: drop the 'earlier Remove covers it' clause by lying about order - the replay's swap assertion must then fail
_orig = R._lead_verb
R._lead_verb = lambda text: "add" if text.startswith("Remove the tests") else _orig(text)
mut = R.lint_batch([T3, D1, D2], ctx)
R._lead_verb = _orig
ok("MUTATION (earlier Remove item no longer recognised): the swapped order is flagged again, so the swap assertion is load-bearing", any("R06" in rules_of(o[1]) for o in mut[1:]))

# ------------------------------------------------------------------ R07
print("== R07 add/delete contradiction")
A = it("scripts/enemy/enemy_faction_map.gd", "Add func new_thing() to the map.", feat=FEAT)
Dd = it("scripts/enemy/enemy_faction_map.gd", "Delete func new_thing() from the map.", feat=FEAT)
out = R.lint_batch([A, Dd], None)
ok("R07 flags BOTH items", all("R07" in rules_of(o[1]) for o in out), out)
ok("R07 NEGATIVE: add in one file, delete in another", all("R07" not in rules_of(o[1]) for o in R.lint_batch([A, it("scripts/other.gd", "Delete func new_thing() from it.")], None)))
ok("R07 NEGATIVE: add foo and delete bar in the same file", all("R07" not in rules_of(o[1]) for o in R.lint_batch([A, it("scripts/enemy/enemy_faction_map.gd", "Delete func other_thing() from the map.")], None)))
ok("R07 NEGATIVE: two adds of the same symbol are a duplicate, not a contradiction", all("R07" not in rules_of(o[1]) for o in R.lint_batch([A, A], None)))

# ------------------------------------------------------------------ R08
print("== R08 ungrounded symbol")
m1 = it("iptv/rep.py", "Modify `recompute_representative()` to weight each row by `scores`.")
fs = R.lint_item(m1, ctx)[1]
ok("R08 flags the symbol the file does not define ('scores' in recompute_representative)", [f for f in fs if f["rule"] == "R08"] and [f for f in fs if f["rule"] == "R08"][0]["evidence"] == ["scores"], fs)
ok("R08 NEGATIVE: `weights` IS in the file (an argument)", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Modify `recompute_representative()` to weight each row by `weights`."), ctx)[1]))
ok("R08 NEGATIVE: a Create/Add verb in the item introduces the symbol", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Modify `recompute_representative()` to add a `scores` parameter."), ctx)[1]))
ok("R08 NEGATIVE: Add-led item", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Add `scores()` helper."), ctx)[1]))
ok("R08 NEGATIVE: all named symbols exist", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Modify `recompute_representative()` and `helper_a()` to agree."), ctx)[1]))
ok("R08 flags an undefined function call in a .py target", "R08" in rules_of(R.lint_item(it("iptv/rep.py", "Modify `helper_a()` to call `missing_fn()`."), ctx)[1]))
ok("R08 .gd target uses a regex over the file at the ref", "R08" in rules_of(R.lint_item(it("scripts/battle/thing.gd", "Modify `do_it()` to call `missing_fn()`."), ctx)[1]))
ok("R08 NEGATIVE .gd: symbol present", "R08" not in rules_of(R.lint_item(it("scripts/battle/thing.gd", "Modify `do_it()` to call `other_fn()`."), ctx)[1]))
ok("R08 NEGATIVE: a Python builtin (`print(...)`) is never 'ungrounded'", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Replace every bare `print(...)` call with logging."), ctx)[1]))
ok("R08 NEGATIVE: the repo's own module name (`url_safety`) is something the item imports, not an ungrounded symbol", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Modify `helper_a()` to use the safe client from `url_safety`."), ctx)[1]))
ok("R08 NEGATIVE: a TEST target names code under test that lives in other files", "R08" not in rules_of(R.lint_item(it("tests/test_enemy_faction_map.gd", "Refactor the test block to call `get_scores()` and `scores_total`."), ctx)[1]))
ok("R08 NEGATIVE: an item that imports the name (`timezone`) brings it in itself", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Replace the old call with one using `timezone` and ensure `timezone` is imported."), ctx)[1]))
ok("R08 NEGATIVE: target file missing at the ref", "R08" not in rules_of(R.lint_item(it("iptv/not_there.py", "Modify `x()`."), ctx)[1]))
ok("R08 NEGATIVE: unparseable python target is skipped, no crash", "R08" not in rules_of(R.lint_item(it("iptv/bad.py", "Modify `x()`."), ctx)[1]))
ok("R08 NEGATIVE: no ctx -> silent", "R08" not in rules_of(R.lint_item(m1, None)[1]))
ok("R08 NEGATIVE: symbols only inside the VERIFY clause are not read", "R08" not in rules_of(R.lint_item(it("iptv/rep.py", "Modify `helper_a()` quietly.", "`grep -q \\`ghost_sym()\\` iptv/rep.py`"), ctx)[1]))

# ------------------------------------------------------------------ R10
print("== R10 model-written 'send N requests, assert 429'")
r10 = it("iptv-backend/tests/test_rate_limit.py", "Create a test that sends 11 requests to /login and asserts the 11th returns 429.")
ok("R10 rejects the pattern", [f["sev"] for f in R.lint_item(r10, ctx)[1] if f["rule"] == "R10"] == ["reject"])
ok("R10 variants: 'make 20 rapid requests ... Too Many Requests'", "R10" in rules_of(R.lint_item(it("tests/test_x.py", "Write a test that makes 20 rapid requests and expects Too Many Requests."), ctx)[1]))
ok("R10 NEGATIVE: the sanctioned deterministic collector's item (supply:rate-limit) is never flagged", "R10" not in rules_of(R.lint_item(r10 + " (supply:rate-limit)", ctx)[1]))
ok("R10 NEGATIVE: mentions 429 but sends no N requests", "R10" not in rules_of(R.lint_item(it("app/r.py", "Return 429 from the lockout handler when the PIN is wrong."), ctx)[1]))
ok("R10 NEGATIVE: sends requests but asserts no rate limit", "R10" not in rules_of(R.lint_item(it("tests/test_x.py", "Write a test that sends 5 requests and asserts they all return 200."), ctx)[1]))

# ------------------------------------------------------------------ plumbing
print("== plumbing")
lines = ["# header", "", D1, "  indented", "- [x] [T2] done.py — Delete func get_faction() VERIFY: `true`.", fp, "- [ ] [CLAUDE] route me"]
out = R.lint_batch(lines, ctx)
ok("lint_batch returns one (line, findings) per input line, in order", len(out) == len(lines) and [o[0] for o in out][:5] == lines[:5])
ok("non-item lines get no findings", out[0][1] == [] and out[1][1] == [] and out[3][1] == [] and out[4][1] == [] and out[6][1] == [])
ok("the vacuous-echo line was repaired in the batch result", out[5][0] != fp and "! ( grep -q old_name f.txt )" in out[5][0])
ok("lint_item == lint_batch([line])[0]", R.lint_item(D1, ctx) == R.lint_batch([D1], ctx)[0])
ok("findings carry only the documented severities", all(f["sev"] in ("repair", "reject", "flag") for o in out for f in o[1]))
ok("lint_static(only=) applies just the named rules", R.lint_static(fp, only={"R01"})[0] == fp and R.lint_static(fp, only={"R02"})[0] != fp)

shutil.rmtree(WORK, ignore_errors=True)
print("\nspec rules: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
