#!/usr/bin/env bash
# test_q_landing_quality.sh - q-landing-quality (2026-11-12) package. All new rules are SHADOW (journal only, never a veto):
#  A. tone-lint-wide  (OVN_Z3_TONE_WIDE): Check out / Grab / Awesome ... on PRODUCT strings (corpus: billwatch 3940f9f4 + fb49f333/c545a8f7, iptv 72c7d787); comments, mechanics
#     ("Check out the branch", "Grab the lock"), docs, tests, locale files, item-asked-for and moved lines stay clean. The ORIGINAL tone-lint is untouched and the direct-cycle audit stays audit-only.
#  B. assert-flip     (assert-weaken kind, fix-up/repair rounds): xlite fa9ffe59 `== 5` -> `== 11` in test_..._never_repairs.
#  C. dup-test        : monitor d2e8944 six copies of one test def in one commit.
#  D. NEGGREP1        (ovn_verify_lint.py): file-wide `! grep -q` / `grep -c ... -eq 0` on a token that matches >= 2 lines (gitlark c3b579b7 cursor-pointer).
#  E. test-first-pair (ovn_item_deps.py item-filter, shadow row): test item listed before the open source item it asserts (xlite cover_degradation).
# Mutants of every module/lib must each be caught by this body.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$SC/.." && pwd)"
MOD="${QLQ_MODULE_DIR:-$SC}"; QMOD="${QLQ_Q_DIR:-$Q}"
PY="${PYTHON:-python3}"
pass=0; fail=0
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
ok(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'rm -rf "${tmp:?}"' EXIT
unset OVN_Z3_TONE OVN_Z3_TONE_LINT OVN_Z3_TONE_TEST OVN_Z8_TONE OVN_Z3_TONE_TOKENS OVN_Z3_TONE_WIDE OVN_Z3_DUP_TEST OVN_Z3_ASSERT_FLIP OVN_VERIFY_LINT_NEGGREP OVN_ITEM_DEPS_TFP OVN_ITEM_DEPS

# ------------------------------------------------------------------ A/B/C: landing gates driver
cat > "$tmp/drv.py" <<'PYEOF'
import sys, os, importlib.util, json
spec = importlib.util.spec_from_file_location("ovn_landing_gates", os.path.join(sys.argv[1], "ovn_landing_gates.py"))
G = importlib.util.module_from_spec(spec); spec.loader.exec_module(G)
def diff(path, added, removed=()):
    h = "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -10,%d +10,%d @@\n" % (path, path, path, path, len(removed)+1, len(added)+1)
    return h + " ctx\n" + "".join("-"+r+"\n" for r in removed) + "".join("+"+a+"\n" for a in added)
def rules(path, added, removed=(), text="", kind="step"):
    r = G.analyse(diff(path, added, removed), text, "", kind, "")
    return sorted(k for k, v in r.items() if v and k in ("tone-lint", "tone-lint-wide", "tone-test-greeting", "dup-test"))
WIDE = [
 # name, path, added, removed, text, expected
 ("billwatch_docstring_check_out", "billwatch-backend/app/routers/bills.py", ['    """Check out the hottest bills with recent activity.'], ['    """Grab the hottest bills with recent activity.'], "", ["tone-lint-wide"]),
 ("billwatch_docstring_grab",      "billwatch-backend/app/routers/bills.py", ['    """Grab a bill by its Congress.gov ID (e.g., \'hr1234-118\')."""'], [], "", ["tone-lint-wide"]),
 ("iptv_notification_body",        "iptv-backend/app/services/notifications.py", ['        body="Grab a sub to keep all your channels, guide, and history.",'], [], "", ["tone-lint-wide"]),
 ("vue_copy_check_out",            "web/src/components/Banner.vue", ["      Check out our new guide"], [], "", ["tone-lint-wide"]),
 ("awesome_copy",                  "web/src/components/Banner.vue", ["      Awesome, you are all set!"], [], "", ["tone-lint-wide"]),
 ("original_hey_not_wide",         "web/src/components/Banner.vue", ["      Hey, no usage data yet."], [], "", ["tone-lint"]),
 # legitimate uses stay clean
 ("comment_grab_lock",             "backend/app/lock.py", ["    # Grab the lock before touching the cache"], [], "", []),
 ("comment_casual_ignored",        "backend/app/x.py", ["    # Check out the hottest bills here, Grab them all"], [], "", []),
 ("comment_check_out_branch",      "backend/app/x.py", ["    # Check out the branch first"], [], "", []),
 ("code_grab_the_lock_string",     "backend/app/lock.py", ['    log.debug("Grab the lock before writing")'], [], "", []),
 ("check_out_the_branch_string",   "backend/app/git.py", ['    raise RuntimeError("Check out the branch you want to release first")'], [], "", []),
 ("docs_readme_exempt",            "docs/guide.md", ["Check out the guide and Grab a coffee"], [], "", []),
 ("test_file_exempt",              "backend/tests/test_x.py", ['    assert msg == "Check out the bills"'], [], "", []),
 ("locale_exempt",                 "web/src/locales/en.ts", ["  cta: 'Check out the plans'"], [], "", []),
 ("item_asks_for_it",              "web/src/components/Banner.vue", ["      Check out our new guide"], [], "change the banner copy to say Check out our new guide", []),
 ("moved_line_not_new",            "web/src/components/Banner.vue", ["      Check out our new guide"], ["      Check out our new guide"], "", []),
 ("identifier_not_token",          "backend/app/x.py", ["    GrabCount = 3", "    checkout = 1", "    check_out = 2"], [], "", []),
 ("lowercase_not_token",           "web/src/components/Banner.vue", ["      you can check out any time"], [], "", []),
 ("mechanic_grab_focus",           "web/src/components/Modal.vue", ['  aria-label="Grab focus handle"'], [], "", []),
 # advisory (a): the 'Check out the latest ...' exemption must not swallow marketing copy; identifiers are not prose
 ("check_out_latest_deals",        "web/src/components/Banner.vue", ["      Check out the latest deals"], [], "", ["tone-lint-wide"]),
 ("check_out_the_latest_features", "backend/app/promo.py", ['    msg = "Check out the latest features in your plan"'], [], "", ["tone-lint-wide"]),
 ("check_out_the_new",             "backend/app/promo.py", ['    msg = "Check out the new dashboard"'], [], "", ["tone-lint-wide"]),
 ("check_out_the_main_features",   "backend/app/promo.py", ['    msg = "Check out the main features"'], [], "", ["tone-lint-wide"]),
 ("check_out_our_latest_deals",    "backend/app/promo.py", ['    msg = "Check out our latest deals"'], [], "", ["tone-lint-wide"]),
 ("check_out_latest_commit_mech",  "backend/app/git.py", ['    raise RuntimeError("Check out the latest commit first")'], [], "", []),
 ("check_out_main_branch_mech",    "backend/app/git.py", ['    raise RuntimeError("Check out the main branch before releasing")'], [], "", []),
 ("check_out_bare_main_mech",      "backend/app/git.py", ['    hint = "Then Check out main."'], [], "", []),
 ("check_out_docs_mech",           "backend/app/git.py", ['    hint = "Check out the docs for details"'], [], "", []),
 ("grab_call_not_prose",           "backend/app/ui.py", ["    focus = Grab(1)"], [], "", []),
 ("grab_gd_method_not_prose",      "scripts/ui/panel.gd", ["\tinput.Grab(1)"], [], "", []),
 ("grab_attr_not_prose",           "backend/app/ui.py", ["    widget = Grab.focus"], [], "", []),
 ("grab_prev_dot_not_prose",       "backend/app/ui.py", ["    ok = panel.Grab and True"], [], "", []),
 ("grab_focus_identifier",         "scripts/ui/panel.gd", ["\tGrabFocus()"], [], "", []),
 ("grab_sentence_punct_still_flags", "backend/app/promo.py", ['    msg = "Grab it now."'], [], "", ["tone-lint-wide"]),
 # C: dup-test
 ("dup_six_copies",                "backend/tests/test_notifier.py", ["def test_notify_transition_403_no_retry():", "    assert 1", "", "def test_notify_transition_403_no_retry():", "    assert 1", "", "def test_notify_transition_403_no_retry():", "    assert 1"], [], "", ["dup-test"]),
 ("dup_gd_func",                   "tests/test_cover.gd", ["func test_a():", "\tassert_eq(1, 1)", "func test_a():", "\tassert_eq(1, 1)"], [], "", ["dup-test"]),
 ("dup_single_def_clean",          "backend/tests/test_notifier.py", ["def test_a():", "    assert 1", "", "def test_b():", "    assert 1"], [], "", []),
 ("dup_method_indent_two_names",   "backend/tests/test_notifier.py", ["    def test_a(self):", "        assert 1", "    def test_b(self):", "        assert 1"], [], "", []),
 ("dup_nested_classes_diffonly",   "backend/tests/test_k.py", ["class A:", "    def test_x(self):", "        pass", "class B:", "    def test_x(self):", "        pass"], [], "", []),
 ("dup_js_titles_not_checked",     "web/src/a.test.ts", ["  it('works', () => {})", "  it('works', () => {})"], [], "", []),
 ("dup_non_test_file_clean",       "backend/app/x.py", ["def test_a():", "    pass", "def test_a():", "    pass"], [], "", []),
]
bad = 0
for n, p, a, r, t, exp in WIDE:
    got = rules(p, a, r, t)
    if got != exp:
        bad += 1; print("MISMATCH %s: got %s expected %s" % (n, got, exp))
print("cases=%d bad=%d" % (len(WIDE), bad))
# env switches
os.environ["OVN_Z3_TONE_WIDE"] = "off"
if rules("web/src/components/Banner.vue", ["      Check out our new guide"]) != []:
    bad += 1; print("MISMATCH OVN_Z3_TONE_WIDE=off still flags")
del os.environ["OVN_Z3_TONE_WIDE"]
os.environ["OVN_Z3_DUP_TEST"] = "off"
if rules("backend/tests/test_n.py", ["def test_a():", "    pass", "def test_a():", "    pass"]) != []:
    bad += 1; print("MISMATCH OVN_Z3_DUP_TEST=off still flags")
del os.environ["OVN_Z3_DUP_TEST"]
# dup-test: same name in two classes of the post-image is NOT a duplicate (post-image supplied)
post = "class A:\n    def test_x(self):\n        pass\n\nclass B:\n    def test_x(self):\n        pass\n"
fds = G.parse_diff(diff("backend/tests/test_k.py", ["    def test_x(self):", "        pass", "    def test_x(self):", "        pass"]))
if G.check_dup_tests(fds, lambda p: post): bad += 1; print("MISMATCH dup-test across two classes flagged")
post2 = "class A:\n    def test_x(self):\n        pass\n    def test_x(self):\n        pass\n"
if not G.check_dup_tests(fds, lambda p: post2): bad += 1; print("MISMATCH dup-test inside one class missed")
# dup-test advisory (c): class scope resets on NESTED classes; unavailable post-image fails OPEN
post3 = "class A:\n    def test_x(self):\n        pass\n    class Inner:\n        def test_x(self):\n            pass\n"
fds3 = G.parse_diff(diff("backend/tests/test_n.py", ["    def test_x(self):", "        pass", "        def test_x(self):", "            pass"]))
fds3b = G.parse_diff(diff("backend/tests/test_n.py", ["        def test_x(self):", "            pass", "        def test_x(self):", "            pass"]))
if G.check_dup_tests(fds3b, lambda p: "class A:\n    class B:\n        def test_x(self):\n            pass\n    class C:\n        def test_x(self):\n            pass\n"): bad += 1; print("MISMATCH dup-test across two nested sibling classes flagged")
if not G.check_dup_tests(fds3b, lambda p: "class A:\n    class B:\n        def test_x(self):\n            pass\n        def test_x(self):\n            pass\n"): bad += 1; print("MISMATCH dup-test inside one nested class missed")
post4 = "class A:\n    def test_x(self):\n        pass\n    class Inner:\n        def test_y(self):\n            pass\n    def test_x(self):\n        pass\n"
if not G.check_dup_tests(fds, lambda p: post4): bad += 1; print("MISMATCH dup-test: a dup in the OUTER class after a nested class closes was missed")
if G.check_dup_tests(fds, lambda p: ""): bad += 1; print("MISMATCH dup-test must fail OPEN on an empty post-image")
def _boom(p): raise RuntimeError("git show failed")
if G.check_dup_tests(fds, _boom): bad += 1; print("MISMATCH dup-test must fail OPEN when the post-image lookup raises")
if G.check_dup_tests(fds, lambda p: None): bad += 1; print("MISMATCH dup-test must fail OPEN on a None post-image")
# B: assert-flip
def flips(path, added, removed, kind, src=None, post=""):
    d = diff(path, added, removed)
    if src:
        d += diff(src[0], src[1], src[2])
    fds = G.parse_diff(d)
    ws = G.check_assert_weaken(fds, None, (lambda p: post), repair=(kind == "repair"), fixup=(kind == "fixup"))
    return [(w["kind"], w.get("neg_name"), w.get("tier")) for w in ws]
T = "tests/test_cover_degradation_hits.gd"
POST = "extends GutTest\nfunc test_negative_hits_or_damage_never_repairs():\n\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 11)\n"
OLD = ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 5)"]
f = flips(T, ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 11)"], OLD, "fixup", post=POST)
if f != [("assert-flip", True, "strong")]: bad += 1; print("MISMATCH assert-flip fixup test-only: %r" % (f,))
f = flips(T, ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 11)"], OLD, "repair", post=POST)
if [x[0] for x in f] != ["assert-flip"]: bad += 1; print("MISMATCH assert-flip repair: %r" % (f,))
f = flips(T, ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 11)"], OLD, "step", post=POST)
if f: bad += 1; print("MISMATCH assert-flip must not fire on a plain step: %r" % (f,))
f = flips(T, ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, 3), 11)"], OLD, "fixup", post=POST)
if [x[0] for x in f] != ["assert-flip"]: bad += 1; print("MISMATCH assert-flip on changed args too (same shape): %r" % (f,))
f = flips(T, ["\tassert_eq(other.thing(1), 11)"], OLD, "fixup", post=POST)
if f: bad += 1; print("MISMATCH assert-flip different subject must not fire: %r" % (f,))
f = flips("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"], "fixup", post="def test_compute_total():\n    assert compute(2) == 7\n")
if [(x[0], x[1]) for x in f] != [("assert-flip", False)]: bad += 1; print("MISMATCH assert-flip plain-name test neg_name False: %r" % (f,))
f = flips("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"], "fixup", src=("app/calc.py", ["    return x * 3 + 1"], ["    return x * 3"]), post="def test_compute_total():\n    assert compute(2) == 7\n")
if [x[0] for x in f].count("assert-flip") + [x[0] for x in f].count("literal-swap") != 1: bad += 1; print("MISMATCH exactly one of literal-swap/assert-flip when src also changed: %r" % (f,))
# advisory (b): kind=fixup adds assert-flip ONLY; literal-swap / assertion-deleted tiers for those commits stay exactly as under a plain step (weak), while repair keeps them strong
SRC = ("app/calc.py", ["    return x * 3 + 1"], ["    return x * 3"])
ls_step = flips("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"], "step", src=SRC, post="def test_compute_total():\n    assert compute(2) == 7\n")
ls_fix = flips("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"], "fixup", src=SRC, post="def test_compute_total():\n    assert compute(2) == 7\n")
ls_rep = flips("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"], "repair", src=SRC, post="def test_compute_total():\n    assert compute(2) == 7\n")
if ls_step != [("literal-swap", None, "weak")]: bad += 1; print("MISMATCH plain step literal-swap baseline: %r" % (ls_step,))
if ls_fix != ls_step: bad += 1; print("MISMATCH fixup must not change the literal-swap tier: step=%r fixup=%r" % (ls_step, ls_fix))
if [(x[0], x[2]) for x in ls_rep] != [("literal-swap", "strong")]: bad += 1; print("MISMATCH repair literal-swap tier must stay strong: %r" % (ls_rep,))
dl_step = flips("tests/test_ok.py", [], ["    assert compute(2) == 6"], "step", post="def test_compute_total():\n    pass\n")
dl_fix = flips("tests/test_ok.py", [], ["    assert compute(2) == 6"], "fixup", post="def test_compute_total():\n    pass\n")
if dl_fix != dl_step: bad += 1; print("MISMATCH fixup must not change assertion-deleted handling: step=%r fixup=%r" % (dl_step, dl_fix))
# same through analyse(): the kind plumbing (analyse -> check_assert_weaken) must keep fixup out of the repair tiers
_dd = diff("tests/test_ok.py", ["    assert compute(2) == 7"], ["    assert compute(2) == 6"]) + diff("app/calc.py", ["    return x * 3 + 1"], ["    return x * 3"])
_tiers = {k: [(w.get("kind"), w.get("tier")) for w in G.analyse(_dd, "", "", k, "")["assert-weaken"]] for k in ("step", "fixup", "repair")}
if _tiers["fixup"] != _tiers["step"] or _tiers["step"] != [("literal-swap", "weak")] or _tiers["repair"] != [("literal-swap", "strong")]: bad += 1; print("MISMATCH analyse() kind->tier plumbing: %r" % (_tiers,))
os.environ["OVN_Z3_ASSERT_FLIP"] = "off"
f = flips(T, ["\tassert_eq(CoverDegradation.durability_after_hits(5, 2, -3), 11)"], OLD, "fixup", post=POST)
if any(x[0] == "assert-flip" for x in f): bad += 1; print("MISMATCH OVN_Z3_ASSERT_FLIP=off still flags")
print("extra bad=%d" % bad)
sys.exit(1 if bad else 0)
PYEOF
ok "A/B/C driver: wide-tone corpus, dup-test, assert-flip (fix-up/repair only, neg_name, tier strong) and the env switches" '"$PY" "$tmp/drv.py" "$MOD"'

# lib: never a veto, rows journaled, commit-audit fix-up detection
mkwt(){ rm -rf "${tmp:?}/wt"; mkdir -p "$tmp/wt/tests" "$tmp/wt/app"; git -C "$tmp/wt" init -q -b main; git -C "$tmp/wt" config user.email t@t; git -C "$tmp/wt" config user.name t
  printf 'def test_never_repairs():\n    assert f(5, -3) == 5\n' > "$tmp/wt/tests/test_c.py"; printf 'def f(a, b):\n    return a - b\n' > "$tmp/wt/app/c.py"; git -C "$tmp/wt" add -A; git -C "$tmp/wt" commit -qm base; }
mkwt; printf '    """Check out the thing."""\n' > "$tmp/wt/app/c2.py"
ok "lib: a wide-tone finding is journaled in shadow and NEVER refuses, even with OVN_Z3_TONE_WIDE=enforce" '( . "$MOD/lib_landing_gates.sh"; for m in "" enforce; do rm -rf "$tmp/st"; OVN_Z3_TONE_WIDE="$m" z3_step_gate "$tmp/wt" step "add c2" "" "app/c2.py" "" "$tmp/st" lbl; [ $? -eq 0 ] && [ -z "${Z3_REFUSE:-}" ] && grep -q "\"rule\": \"tone-lint-wide\"" "$tmp/st/landing_gates_shadow.log" && grep -q "\"mode\": \"shadow\"" "$tmp/st/landing_gates_shadow.log" || exit 1; done )'
ok "lib: OVN_Z3_TONE_WIDE=off journals nothing" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; OVN_Z3_TONE_WIDE=off z3_step_gate "$tmp/wt" step "add c2" "" "app/c2.py" "" "$tmp/st" lbl; ! grep -q tone-lint-wide "$tmp/st/landing_gates_shadow.log" 2>/dev/null )'
ok "lib: the ORIGINAL tone-lint still ENFORCES (Hey in product copy refuses) - the wide set did not weaken it" '( . "$MOD/lib_landing_gates.sh"; printf "    \"\"\"Hey, do the thing.\"\"\"\n" > "$tmp/wt/app/c3.py"; rm -rf "$tmp/st"; z3_step_gate "$tmp/wt" step "add c3" "" "app/c3.py" "" "$tmp/st" lbl; rc=$?; rm -f "$tmp/wt/app/c3.py"; [ $rc -eq 1 ] && case "${Z3_REFUSE:-}" in tone-lint:*) true;; *) false;; esac )'
ok "lib: dup-test is journaled in shadow, never refuses (enforce behaves as shadow)" '( . "$MOD/lib_landing_gates.sh"; printf "def test_a():\n    assert 1\ndef test_a():\n    assert 1\n" > "$tmp/wt/tests/test_dup.py"; rm -rf "$tmp/st"; OVN_Z3_DUP_TEST=enforce z3_step_gate "$tmp/wt" step "add tests" "" "tests/test_dup.py" "" "$tmp/st" lbl; rc=$?; rm -f "$tmp/wt/tests/test_dup.py"; [ $rc -eq 0 ] && grep -q "\"rule\": \"dup-test\"" "$tmp/st/landing_gates_shadow.log" )'
# commit audit: fix-up subject -> kind fixup -> assert-flip row; plain subject -> none; the direct-cycle audit never refuses (audit-only is kept: no precision evidence for enforce)
mkwt; BASE="$(git -C "$tmp/wt" rev-parse HEAD)"
printf 'def test_never_repairs():\n    assert f(5, -3) == 11\n' > "$tmp/wt/tests/test_c.py"; git -C "$tmp/wt" commit -qam "fix(xlite): repair staged item to pass verification (round 1)"; HEAD1="$(git -C "$tmp/wt" rev-parse HEAD)"
ok "commit audit: a stage-runner repair-round commit journals assert-weaken/assert-flip (audit mode, never refuses)" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; z3_commit_audit "$tmp/wt" "$BASE" "$HEAD1" "item" "$tmp/st" lbl; rc=$?; [ $rc -eq 0 ] && grep "assert-flip" "$tmp/st/landing_gates_shadow.log" | grep -q "\"mode\": \"audit\"" && grep "assert-flip" "$tmp/st/landing_gates_shadow.log" | grep -q "\"neg_name\": true" )'
mkwt; BASE="$(git -C "$tmp/wt" rev-parse HEAD)"; printf 'def test_never_repairs():\n    assert f(5, -3) == 11\n' > "$tmp/wt/tests/test_c.py"; git -C "$tmp/wt" commit -qam "feat: rework the cover maths"; HEAD2="$(git -C "$tmp/wt" rev-parse HEAD)"
ok "commit audit: the same diff under a non-fix-up subject journals no assert-flip" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; z3_commit_audit "$tmp/wt" "$BASE" "$HEAD2" "item" "$tmp/st" lbl; ! grep -q "assert-flip" "$tmp/st/landing_gates_shadow.log" 2>/dev/null )'
for subj in "fix: update test expectations to match actual arithmetic behavior" "fix(billing): correct test fixture for proration" "feat: add test helper and fix test names"; do
  mkwt; BASE="$(git -C "$tmp/wt" rev-parse HEAD)"; printf 'def test_never_repairs():\n    assert f(5, -3) == 11\n' > "$tmp/wt/tests/test_c.py"; git -C "$tmp/wt" commit -qam "$subj"; HX="$(git -C "$tmp/wt" rev-parse HEAD)"
  ok "commit audit: ordinary subject '$subj' is NOT a fix-up (no assert-flip)" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; z3_commit_audit "$tmp/wt" "$BASE" "'"$HX"'" "item" "$tmp/st" lbl; ! grep -q "assert-flip" "$tmp/st/landing_gates_shadow.log" 2>/dev/null )'
done
for subj in "fixup: test expectation" "fix-up: align assertion" "repair: flaky test" "fix(xlite): fixup round 2"; do
  mkwt; BASE="$(git -C "$tmp/wt" rev-parse HEAD)"; printf 'def test_never_repairs():\n    assert f(5, -3) == 11\n' > "$tmp/wt/tests/test_c.py"; git -C "$tmp/wt" commit -qam "$subj"; HX="$(git -C "$tmp/wt" rev-parse HEAD)"
  ok "commit audit: fix-up subject '$subj' marks the range (assert-flip journaled)" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; z3_commit_audit "$tmp/wt" "$BASE" "'"$HX"'" "item" "$tmp/st" lbl; grep -q "assert-flip" "$tmp/st/landing_gates_shadow.log" )'
done
mkwt; BASE="$(git -C "$tmp/wt" rev-parse HEAD)"; printf '    """Hey, new helper."""\n' > "$tmp/wt/app/c4.py"; git -C "$tmp/wt" add -A; git -C "$tmp/wt" commit -qm "feat: add c4"; HEAD3="$(git -C "$tmp/wt" rev-parse HEAD)"
ok "commit audit: a direct-cycle Hey landing is journaled mode=audit and the audit returns 0 (no refusal on the direct path)" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; z3_commit_audit "$tmp/wt" "$BASE" "$HEAD3" "item" "$tmp/st" lbl; rc=$?; [ $rc -eq 0 ] && grep "tone-lint" "$tmp/st/landing_gates_shadow.log" | grep -q "\"mode\": \"audit\"" )'

# ------------------------------------------------------------------ D: NEGGREP1
VL="$QMOD/ovn_verify_lint.py"
cat > "$tmp/vl.py" <<'PYEOF'
import sys, os, importlib.util, tempfile, shutil
spec = importlib.util.spec_from_file_location("ovn_verify_lint", sys.argv[1]); V = importlib.util.module_from_spec(spec); spec.loader.exec_module(V)
d = tempfile.mkdtemp(prefix="nglint")
bad = 0
try:
    os.makedirs(d + "/web/src/pages")
    open(d + "/web/src/pages/D.vue", "w").write('<h1 class="cursor-pointer">x</h1>\n<div class="cursor-pointer" @click="a">\n<div class="cursor-pointer">\n<p>CURSOR-POINTER note</p>\n')
    open(d + "/web/src/pages/One.vue", "w").write('<h1 class="cursor-pointer">x</h1>\n')
    F = "web/src/pages/D.vue"
    def it(text, verify): return "- [ ] [T2] %s - %s VERIFY: `%s` (cat:vue; multifile:no)" % (F, text, verify)
    def chk(name, line, want, frag=""):
        global bad
        r = V.lint_verify(line, d)
        got = r["rule"] if r["verdict"] == "SUSPECT" else ""
        if got != want or (frag and frag not in r["reason"]):
            bad += 1; print("MISMATCH %s: got %r (%s) want %r" % (name, got, r["reason"][:120], want))
    chk("c3b579b7_bang_grep_q", it("Remove cursor-pointer from the <h1>.", "cd web && ! grep -q 'cursor-pointer' src/pages/D.vue"), "NEGGREP1", "currently matches 3 lines")
    chk("grep_c_eq0", it("Remove cursor-pointer from the h1.", 'cd web && [ "$(grep -c cursor-pointer src/pages/D.vue)" -eq 0 ]'), "NEGGREP1", "matches 3")
    chk("grep_c_pipe_0", it("Remove cursor-pointer from the h1.", "cd web && grep -c cursor-pointer src/pages/D.vue | grep -q '^0$'"), "NEGGREP1")
    chk("bang_grep_with_i_flag", it("Remove cursor-pointer from the h1.", "cd web && ! grep -qi 'cursor-pointer' src/pages/D.vue"), "NEGGREP1", "matches 4")
    chk("item_says_every", it("Remove cursor-pointer from every element.", "cd web && ! grep -q 'cursor-pointer' src/pages/D.vue"), "")
    chk("item_says_all", it("Remove all cursor-pointer classes.", "cd web && ! grep -q 'cursor-pointer' src/pages/D.vue"), "")
    chk("single_match_ok", it("Remove cursor-pointer from the h1.", "cd web && ! grep -q 'cursor-pointer' src/pages/One.vue"), "")
    chk("zero_matches_ok", it("Remove nothing.", "cd web && ! grep -q 'nothere' src/pages/D.vue"), "")
    chk("positive_grep_ok", it("Add cursor-pointer to the h1.", "cd web && grep -q 'cursor-pointer' src/pages/D.vue"), "")
    chk("scoped_line_grep_ok", it("Remove cursor-pointer from the h1.", "cd web && ! grep -q '<h1 class=.cursor-pointer' src/pages/D.vue"), "")
    chk("recursive_dir_ban_skipped", it("Remove debug logging.", "cd web && ! grep -rq 'cursor-pointer' src"), "")
    chk("grep_v_skipped", it("Remove cursor-pointer from the h1.", "cd web && ! grep -qv 'cursor-pointer' src/pages/D.vue"), "")
    os.environ["OVN_VERIFY_LINT_NEGGREP"] = "off"
    chk("switch_off", it("Remove cursor-pointer from the <h1>.", "cd web && ! grep -q 'cursor-pointer' src/pages/D.vue"), "")
    del os.environ["OVN_VERIFY_LINT_NEGGREP"]
    # shadow_log writes a row with the match count; the item is never changed
    sd = os.path.join(d, "st"); os.makedirs(sd)
    r = V.shadow_log(it("Remove cursor-pointer from the <h1>.", "cd web && ! grep -q 'cursor-pointer' src/pages/D.vue"), d, "gitlark", sd)
    lp = os.path.join(sd, "verify_lint.jsonl")
    rows = list(open(lp)) if os.path.exists(lp) else []
    if r["rule"] != "NEGGREP1" or len(rows) != 1 or "NEGGREP1" not in rows[0] or "matches 3" not in rows[0]:
        bad += 1; print("MISMATCH shadow row: %r" % (rows,))
    print("cases bad=%d" % bad)
finally:
    shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if bad else 0)
PYEOF
ok "D driver: NEGGREP1 flags file-wide negative greps with >= 2 current matches, with the count; every other shape stays OK" '"$PY" "$tmp/vl.py" "$VL"'

# ------------------------------------------------------------------ E: test-first-pair
cat > "$tmp/prog.md" <<'PROGEOF'
# Progress
## Next Steps
- [ ] [T2] tests/test_cover_degradation_hits.gd — Add `test_negative_hits_or_damage_never_repairs` asserting `durability_after_hits(5, 2, -3) == 5`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation_hits.gd -gexit` (cat:test; multifile:no) [feat:xlite-cover]
- [ ] [T1] scripts/battle/cover_degradation.gd — In `durability_after_hits` replace `current - (dmg_per_hit * hits)` with `current - (maxi(dmg_per_hit, 0) * maxi(hits, 0))`. VERIFY: `grep -q "maxi(hits, 0)" scripts/battle/cover_degradation.gd` (cat:godot; multifile:no) [feat:xlite-cover]
- [ ] [T2] tests/test_other_thing.gd — Add a test asserting `unrelated_widget(1) == 2`. VERIFY: `grep -q unrelated_widget tests/test_other_thing.gd` (cat:test; multifile:no) [feat:xlite-other]
- [ ] [T1] scripts/battle/other_module.gd — Add `static func something_else()` returning 3. VERIFY: `grep -q something_else scripts/battle/other_module.gd` (cat:godot; multifile:no) [feat:xlite-other]
PROGEOF
cat > "$tmp/prog_ok.md" <<'PROGEOF'
# Progress
## Next Steps
- [ ] [T1] scripts/battle/cover_degradation.gd — In `durability_after_hits` replace `current - (dmg_per_hit * hits)` with `current - (maxi(dmg_per_hit, 0) * maxi(hits, 0))`. VERIFY: `grep -q "maxi(hits, 0)" scripts/battle/cover_degradation.gd` (cat:godot; multifile:no) [feat:xlite-cover]
- [ ] [T2] tests/test_cover_degradation_hits.gd — Add `test_negative_hits_or_damage_never_repairs` asserting `durability_after_hits(5, 2, -3) == 5`. VERIFY: `~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_cover_degradation_hits.gd -gexit` (cat:test; multifile:no) [feat:xlite-cover]
PROGEOF
IDP="$MOD/ovn_item_deps.py"
TFIRST="$(grep -m1 'test_negative_hits' "$tmp/prog.md" | sed 's/^- \[ \] //')"
TOK="$(grep -m1 'test_negative_hits' "$tmp/prog_ok.md" | sed 's/^- \[ \] //')"
TUNREL="$(grep -m1 'unrelated_widget' "$tmp/prog.md" | sed 's/^- \[ \] //')"
tfp_run(){ # $1 progress, $2 candidate text (no "- [ ] "), $3 mode; env passes through; stdout = filter output, rows in $tmp/tfp.log
  rm -f "$tmp/tfp.log" "$tmp/tfp.log.lock"; printf -- '- [ ] %s\n' "$2" | "$PY" "$IDP" item-filter --mode "${3:-shadow}" --progress "$1" --repo xlite --log "$tmp/tfp.log" --tree "$tmp" 2>/dev/null; }
OUT="$(tfp_run "$tmp/prog.md" "$TFIRST")"
ok "E: item-filter output is unchanged (shadow, the picker never changes)" '[ "$OUT" = "- [ ] $TFIRST" ]'
ok "E: a test-first-pair row is journaled for the test item listed before its source item (why names the symbol)" 'grep -q "\"event\": \"test-first-pair\"" "$tmp/tfp.log" && grep -q "durability_after_hits" "$tmp/tfp.log" && grep -q "\"mode\": \"shadow\"" "$tmp/tfp.log"'
tfp_run "$tmp/prog_ok.md" "$TOK" >/dev/null
ok "E: source-first order journals NO test-first-pair row" '! grep -q "test-first-pair" "$tmp/tfp.log" 2>/dev/null'
tfp_run "$tmp/prog.md" "$TUNREL" >/dev/null
ok "E: a test item whose symbol the later source item does not name journals no pair" '! grep -q "test-first-pair" "$tmp/tfp.log" 2>/dev/null'
OVN_ITEM_DEPS_TFP=off tfp_run "$tmp/prog.md" "$TFIRST" >/dev/null
ok "E: OVN_ITEM_DEPS_TFP=off journals nothing" '! grep -q "test-first-pair" "$tmp/tfp.log" 2>/dev/null'
tfp_run "$tmp/prog.md" "$TFIRST" enforce >/dev/null
ok "E: pair rows are shadow even when the item filter runs in enforce mode (the detector itself never drops the item)" 'grep -q "\"event\": \"test-first-pair\"" "$tmp/tfp.log" && grep -q "\"mode\": \"shadow\"" "$tmp/tfp.log"'

# ------------------------------------------------------------------ mutants
mutant(){ local f="$1" name="$2" a="$3" b="$4" dir; dir="$tmp/m_$name"; mkdir -p "$dir"; cp "$SC/ovn_landing_gates.py" "$SC/lib_landing_gates.sh" "$SC/ovn_item_deps.py" "$SC/ovn_stage_order.py" "$dir/" 2>/dev/null; for x in "$SC"/lib_*.sh; do cp -n "$x" "$dir/" 2>/dev/null; done
  cp "$Q/ovn_verify_lint.py" "$dir/ovn_verify_lint.py"
  "$PY" - "$dir/$f" "$a" "$b" <<'PYEOF' || { fail=$((fail+1)); echo "  FAIL: mutant $name did not apply"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p).read(); assert s.count(a) >= 1, a; open(p, "w").write(s.replace(a, b, 1))
PYEOF
  ok "MUTANT $name is caught" '! QLQ_MODULE_DIR="$tmp/m_'"$name"'" QLQ_Q_DIR="$tmp/m_'"$name"'" bash "$0" --body-only >/dev/null 2>&1'; }
if [ "${1:-}" != "--body-only" ]; then
  mutant ovn_landing_gates.py wide_not_wired 'res["tone-lint-wide"] = check_tone_wide(fds, (desc or "") + "\n" + (item or ""))' 'res["tone-lint-wide"] = []'
  mutant ovn_landing_gates.py wide_flags_comments '            if _is_comment(t) or re.match(r"\s*(?:<!--)", t):
                continue
            for m in rx.finditer(t):
                w = m.group(0)
                if not _wide_is_prose(t, m) or _WIDE_MECHANIC_RE' '            for m in rx.finditer(t):
                w = m.group(0)
                if not _wide_is_prose(t, m) or _WIDE_MECHANIC_RE'
  mutant ovn_landing_gates.py wide_flags_mechanics 'if not _wide_is_prose(t, m) or _WIDE_MECHANIC_RE.match(t[m.start():]):
                    continue' 'if not _wide_is_prose(t, m):
                    continue'
  mutant ovn_landing_gates.py wide_token_dropped 'TONE_WIDE = ("Check out", "Grab",' 'TONE_WIDE = ("Check out",'
  mutant ovn_landing_gates.py wide_ignores_item 'if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(w), ctxt):
                    continue
                if prior.get(w, 0) > 0:
                    prior[w] -= 1
                    continue
                findings.append({"rule": "tone-lint-wide"' 'if prior.get(w, 0) > 0:
                    prior[w] -= 1
                    continue
                findings.append({"rule": "tone-lint-wide"'
  mutant ovn_landing_gates.py wide_switch_ignored 'if _tone_wide_mode() == "off":
        return []' 'if False:
        return []'
  mutant ovn_landing_gates.py flip_on_plain_step 'if (repair or fixup) and not retired and os.environ.get("OVN_Z3_ASSERT_FLIP"' 'if not retired and os.environ.get("OVN_Z3_ASSERT_FLIP"'
  mutant ovn_landing_gates.py flip_not_strong '"stream-assert-deleted", "assert-flip") or' '"stream-assert-deleted") or'
  mutant ovn_landing_gates.py flip_any_subject 'and _lit_shape(a) == sh and _lits(a) != lt and _norm_line(a) != _norm_line(t):
                            hit("assert-flip"' 'and _lits(a) != lt and _norm_line(a) != _norm_line(t):
                            hit("assert-flip"'
  mutant ovn_landing_gates.py flip_no_neg_name 'f["neg_name"] = bool(' 'f["neg_name"] = False and bool('
  mutant ovn_landing_gates.py fixup_kind_not_wired 'repair=(kind == "repair"), fixup=(kind == "fixup"))' 'repair=(kind == "repair"), fixup=False)'
  mutant ovn_landing_gates.py fixup_widens_all_tiers 'repair=(kind == "repair"), fixup=(kind == "fixup"))' 'repair=(kind in ("repair", "fixup")), fixup=(kind == "fixup"))'
  mutant ovn_landing_gates.py wide_check_out_latest_exempt '|latest\s+(?:commit|tag|release|revision|sha|branch)\b"' '|latest\b"'
  mutant ovn_landing_gates.py wide_ident_not_guarded 'if not _wide_is_prose(t, m) or _WIDE_MECHANIC_RE' 'if _WIDE_MECHANIC_RE'
  mutant ovn_landing_gates.py wide_prev_dot_not_guarded 'if m.start() > 0 and t[m.start() - 1] in ".:":
        return False' 'if False:
        return False'
  mutant ovn_landing_gates.py dup_not_wired 'res["dup-test"] = check_dup_tests(' 'res["dup-test"] = [] and check_dup_tests('
  mutant ovn_landing_gates.py dup_threshold 'if counts[key] >= 2:' 'if counts[key] >= 1:'
  mutant ovn_landing_gates.py dup_class_scope_ignored 'if not _dup_in_post(post, name, indent):
                continue' 'if False:
                continue'
  mutant ovn_landing_gates.py dup_nested_scope_not_reset 'while stack and stack[-1][0] >= n:
            stack.pop()' 'while False:
            stack.pop()'
  mutant ovn_landing_gates.py dup_fails_closed 'if not post:
                    continue    # post-image unavailable' 'post = "\n".join(t for _, t in fd.added)    # post-image unavailable'
  mutant ovn_landing_gates.py dup_non_test_checked 'if fd.is_deleted or not fd.path.endswith((".py", ".gd")) or not is_test_path(fd.path):' 'if fd.is_deleted or not fd.path.endswith((".py", ".gd")):'
  mutant lib_landing_gates.sh wide_enforces 'tone-lint-wide) mode="$(_z3_mode OVN_Z3_TONE_WIDE)"; [ "$mode" = enforce ] && mode=shadow;;' 'tone-lint-wide) mode="$(_z3_mode OVN_Z3_TONE_WIDE)";;'
  mutant lib_landing_gates.sh dup_enforces 'dup-test) mode="$(_z3_mode OVN_Z3_DUP_TEST)"; [ "$mode" = enforce ] && mode=shadow;;' 'dup-test) mode="$(_z3_mode OVN_Z3_DUP_TEST)";;'
  mutant lib_landing_gates.sh audit_no_fixup 'grep -qiE' 'grep -qiEv'
  mutant lib_landing_gates.sh audit_plain_fix_test_subject '(^([a-z]+(\([^)]*\))?:[[:space:]]*)?(fix-?up|repair)([^a-z]|$))|repair staged' '^[a-z]+(\([^)]*\))?: (fix|update|adjust|correct|align)[a-z -]* (test|expectation|assertion)|repair staged'
  mutant lib_landing_gates.sh audit_never_fixup 'ck=fixup' 'ck=step'
  mutant ovn_verify_lint.py neg_not_wired ', rule_neggrep1(item_line, clause, repo_root)):' '):'
  mutant ovn_verify_lint.py neg_threshold 'if n >= 2:
            return _res(SUSPECT, "NEGGREP1' 'if n >= 0:
            return _res(SUSPECT, "NEGGREP1'
  mutant ovn_verify_lint.py neg_ignores_all_words 'if _ALL_WORDS.search(re.sub(r"VERIFY:.*$", "", item or "", flags=re.S)):
        return None' 'if False:
        return None'
  mutant ovn_verify_lint.py neg_no_count 'currently matches %d lines of %s' 'currently matches lines of %s%.0d'
  mutant ovn_verify_lint.py neg_switch_ignored 'if os.environ.get("OVN_VERIFY_LINT_NEGGREP", "shadow").strip().lower() == "off":
        return None' 'if False:
        return None'
  mutant ovn_verify_lint.py neg_misses_grep_c_pipe 'for m in re.finditer(r"grep\s+(-[A-Za-z]*c' 'for m in re.finditer(r"grepNEVER\s+(-[A-Za-z]*c'
  mutant ovn_item_deps.py tfp_not_journaled 'if a.log and (os.environ.get("OVN_ITEM_DEPS_TFP", "on") or "on").strip().lower() != "off":' 'if False:'
  mutant ovn_item_deps.py tfp_wrong_order 'a["it"]["line"] <= b["it"]["line"]:' 'a["it"]["line"] >= b["it"]["line"]:'
  mutant ovn_item_deps.py tfp_switch_ignored '"OVN_ITEM_DEPS_TFP", "on") or "on").strip().lower() != "off":' '"OVN_ITEM_DEPS_TFP", "on") or "on").strip().lower() != "xoff":'
  mutant ovn_item_deps.py tfp_any_pair 'if why:
                out.append((b["id"], a["id"], why))' 'if True:
                out.append((b["id"], a["id"], why or "x"))'
fi
echo "q landing quality: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
