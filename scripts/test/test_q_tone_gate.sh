#!/usr/bin/env bash
# test_q_tone_gate.sh - q-verify-speed (2026-11-12) tone gate package.
#  A. tone-test-greeting (SHADOW): a TEST file asserting/opening with a leaked greeting is flagged; benign fixture text never is. Real 2026-11-09..12 landings (62a7319e, d1e6d5ce, 9da06b66,
#     a4eef354, 4e68cd52) are the positives; `Hello World`, `Hi there` chat fixtures are the negatives. Never a veto: OVN_Z3_TONE_TEST=enforce behaves as shadow.
#  B. tone-lint precision corpus: the 2026-11-07..12 product-copy landings (31 lines / 23 commit-file events) must all still be flagged, and legitimate additions must not.
# Mutants of the module/lib must each be caught by this body.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"
MOD="${QTG_MODULE_DIR:-$SC}"
PY="${PYTHON:-python3}"
pass=0; fail=0
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
ok(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'rm -rf "${tmp:?}"' EXIT
unset OVN_Z3_TONE OVN_Z3_TONE_LINT OVN_Z3_TONE_TEST OVN_Z8_TONE OVN_Z3_TONE_TOKENS

cat > "$tmp/drv.py" <<'PYEOF'
import sys, os, importlib.util, json
spec = importlib.util.spec_from_file_location("ovn_landing_gates", os.path.join(sys.argv[1], "ovn_landing_gates.py"))
G = importlib.util.module_from_spec(spec); spec.loader.exec_module(G)
def diff(path, added, removed=()):
    h = "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -10,%d +10,%d @@\n" % (path, path, path, path, len(removed)+1, len(added)+1)
    return h + " ctx\n" + "".join("-"+r+"\n" for r in removed) + "".join("+"+a+"\n" for a in added)
def run(path, added, removed=(), text="", kind="step"):
    r = G.analyse(diff(path, added, removed), text, "", kind, "")
    return sorted(k for k, v in r.items() if v and k in ("tone-lint", "tone-test-greeting"))
CASES = [
 # name, path, added, removed, text, expected rules
 ("monitor_inverted_assert", "backend/tests/test_notifier.py", ['    assert body["title"] == "Hey, api went from up to down"'], ['    assert body["title"] == "api went from up to down"'], "", ["tone-test-greeting"]),
 ("notify_in_assert",        "backend/tests/test_broker_flush_due_held.py", ['    assert "Hey!" in result[0].body'], [], "", ["tone-test-greeting"]),
 ("billwatch_toContain",     "billwatch-web/src/views/__tests__/LegislatorDetailView.test.ts", ["    expect(wrapper.text()).toContain('Hey there, loading up your legislator...')"], [], "", ["tone-test-greeting"]),
 ("docstring_opener",        "billwatch-backend/tests/test_finance_math.py", ['"""Hey! Tests for finance_math pure helpers."""'], [], "", ["tone-test-greeting"]),
 ("hello_world_fixture",     "billwatch-backend/tests/test_digest_html_escape.py", ['    assert escape_html("Hello World") == "Hello World"'], [], "", []),
 ("hi_there_chat_fixture",   "web/src/__tests__/api.test.ts", ["  { id: '2', role: 'assistant', content: 'Hi there' },"], [], "", []),
 ("item_asks_for_it",        "backend/tests/test_notifier.py", ['    assert "Hey!" in body'], [], "assert the body contains Hey!", []),
 ("already_in_file",         "backend/tests/test_notifier.py", ['    assert "Hey!" in body2'], ['    assert "Hey!" in body'], "", []),
 ("identifier_not_token",    "backend/tests/test_x.py", ['    assert "HeyCorp" in body'], [], "", []),
 ("lowercase_hey_not_token", "backend/tests/test_x.py", ['    assert "hey" in body'], [], "", []),
 ("non_test_file_is_tone_lint_not_b2b", "backend/app/x.py", ['    assert "Hey!" in body'], [], "", ["tone-lint"]),
 # B: tone-lint corpus (product copy that really landed): every one must stay flagged
 ("vue_UsageInsights",       "web/src/components/UsageInsights.vue", ["      Hey, no usage data yet."], [], "", ["tone-lint"]),
 ("py_notifier_fstring",     "backend/app/services/notifier.py", ['        title = f"Hey, {monitor_name} went from {old_status} to {new_status}"'], [], "", ["tone-lint"]),
 ("ts_console_error",        "web/src/stores/workspace.ts", ["      console.error('Hey, failed to fetch workspaces:', errorMsg)"], [], "", ["tone-lint"]),
 ("html_h1",                 "backend/app/static/console.html", ["<h1>Yo, shrike-monitor</h1>"], [], "", ["tone-lint"]),
 ("vue_aria_template",       "billwatch-web/src/components/UnifiedBillCard.vue", [':aria-label="`Hey, check out ${bill.congress_id.toUpperCase()}`"'], [], "", ["tone-lint"]),
 ("vue_buzz_label",          "billwatch-web/src/components/UnifiedBillCard.vue", ['        <div class="text-xs text-slate-500 mb-1">Buzz</div>'], [], "", ["tone-lint"]),
 ("vue_whoa",                "billwatch-web/src/components/DeleteAccountButton.vue", ['  title="Whoa, hold up!"'], [], "", ["tone-lint"]),
 ("py_headsup_title",        "backend/app/services/notifier.py", ['        title = f"Heads up: {monitor_name} went from {old_status} to {new_status}"'], [], "", ["tone-lint"]),
 ("py_docstring_hey",        "backend/app/utils/retry_decision.py", ['"""Hey! This utility determines retry decisions based on error type."""'], [], "", ["tone-lint"]),
 ("py_logger_yo",            "backend/app/routers/github_app.py", ['    logger.info("Yo! GitHub App callback event: %s", audit_context)'], [], "", ["tone-lint"]),
 # legitimate additions must stay clean
 ("clean_product_copy",      "web/src/components/UsageInsights.vue", ["      No usage data yet."], [], "", []),
 ("welcome_is_fine",         "web/src/components/Banner.vue", ["      Welcome back, {{ user.name }}"], [], "", []),
 ("hey_asked_for",           "web/src/components/UsageInsights.vue", ["      Hey, no usage data yet."], [], "change the empty-state copy to say Hey, no usage data yet.", []),
 ("hey_moved_line",          "web/src/components/UsageInsights.vue", ["      Hey, no usage data yet."], ["      Hey, no usage data yet."], "", []),
 ("hey_in_docs_exempt",      "docs/guide.md", ["Hey, welcome to the guide"], [], "", []),
 ("hey_in_locale_exempt",    "web/src/locales/en.ts", ["  greet: 'Hey!'"], [], "", []),
]
bad = 0
for n, p, a, r, t, exp in CASES:
    got = run(p, a, r, t)
    if got != exp:
        bad += 1; print("MISMATCH %s: got %s expected %s" % (n, got, exp))
print("cases=%d bad=%d" % (len(CASES), bad))
sys.exit(1 if bad else 0)
PYEOF
ok "A/B driver: every corpus case matches (positives flagged, benign/exempt/asked-for clean)" '"$PY" "$tmp/drv.py" "$MOD"'
ok "OVN_Z8_TONE=off keeps tone-lint on the pre-Z8b list; the new test rule is unaffected (Heads up not flagged, Hey in tests still)" 'OVN_Z8_TONE=off "$PY" - "$MOD" <<PYEOF
import sys, os, importlib.util
exec(open(os.environ.get("DRV", "'"$tmp"'/drv.py")).read().split("CASES = [")[0])
assert run("backend/app/services/notifier.py", ["        title = f\"Heads up: x\""]) == []
assert run("backend/tests/test_n.py", ["    assert \"Hey!\" in b"]) == ["tone-test-greeting"]
PYEOF'
# lib: shadow only (never a veto)
mkwt(){ rm -rf "${tmp:?}/wt"; mkdir -p "$tmp/wt/backend/tests"; git -C "$tmp/wt" init -q -b main; git -C "$tmp/wt" config user.email t@t; git -C "$tmp/wt" config user.name t
  printf 'def test_a():\n    assert True\n' > "$tmp/wt/backend/tests/test_n.py"; git -C "$tmp/wt" add -A; git -C "$tmp/wt" commit -qm base; }
mkwt; printf 'def test_a():\n    assert "Hey!" in "Hey! x"\n' > "$tmp/wt/backend/tests/test_n.py"
ok "lib: a test-greeting finding is journaled in shadow and NEVER refuses, even with OVN_Z3_TONE_TEST=enforce" '( . "$MOD/lib_landing_gates.sh"; for m in "" enforce; do rm -f "$tmp/st/landing_gates_shadow.log"; OVN_Z3_TONE_TEST="$m" z3_step_gate "$tmp/wt" step "update the test" "" "backend/tests/test_n.py" "" "$tmp/st" lbl || exit 1; [ -z "$Z3_REFUSE" ] && grep -q "\"rule\": \"tone-test-greeting\".*\"mode\": \"shadow\"" "$tmp/st/landing_gates_shadow.log" || exit 1; done )'
ok "lib: OVN_Z3_TONE_TEST=off journals nothing" '( . "$MOD/lib_landing_gates.sh"; rm -rf "$tmp/st"; OVN_Z3_TONE_TEST=off z3_step_gate "$tmp/wt" step "update the test" "" "backend/tests/test_n.py" "" "$tmp/st" lbl; ! grep -q tone-test-greeting "$tmp/st/landing_gates_shadow.log" 2>/dev/null )'

# MUTANTS
mutant(){ local f="$1" name="$2" a="$3" b="$4"; mkdir -p "$tmp/m_$name"; cp "$SC/ovn_landing_gates.py" "$SC/lib_landing_gates.sh" "$tmp/m_$name/"; for x in "$SC"/lib_*.sh; do cp -n "$x" "$tmp/m_$name/" 2>/dev/null; done
  "$PY" - "$tmp/m_$name/$f" "$a" "$b" <<'PYEOF' || { fail=$((fail+1)); echo "  FAIL: mutant $name did not apply"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p).read(); assert s.count(a) >= 1, a; open(p, "w").write(s.replace(a, b, 1))
PYEOF
  ok "MUTANT $name is caught" '! QTG_MODULE_DIR="$tmp/m_'"$name"'" bash "$0" --body-only >/dev/null 2>&1'; }
if [ "${1:-}" != "--body-only" ]; then
  mutant ovn_landing_gates.py no_assert_gate '_TONE_TEST_ASSERT_RE.search(t) or _TONE_TEST_LEAD_RE.match(t)' 'True'
  mutant ovn_landing_gates.py no_lead '_TONE_TEST_ASSERT_RE.search(t) or _TONE_TEST_LEAD_RE.match(t)' '_TONE_TEST_ASSERT_RE.search(t)'
  mutant ovn_landing_gates.py no_item_escape 'if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(w), ctxt):
                continue
            if prior.get(w, 0) > 0:
                prior[w] -= 1
                continue
            findings.append({"rule": "tone-test-greeting"' 'if prior.get(w, 0) > 0:
                prior[w] -= 1
                continue
            findings.append({"rule": "tone-test-greeting"'
  mutant ovn_landing_gates.py tests_not_required 'or not is_test_path(fd.path):
            continue
        prior = {}
        for _, t in fd.removed:
            for m in rx.finditer(t):
                prior[m.group(0)] = prior.get(m.group(0), 0) + 1
        for ln, t in fd.added:
            m = rx.search(t)' 'or False:
            continue
        prior = {}
        for _, t in fd.removed:
            for m in rx.finditer(t):
                prior[m.group(0)] = prior.get(m.group(0), 0) + 1
        for ln, t in fd.added:
            m = rx.search(t)'
  mutant ovn_landing_gates.py not_wired 'res["tone-test-greeting"] = check_tone_tests(fds, (desc or "") + "\n" + (item or ""))' 'res["tone-test-greeting"] = []'
  mutant ovn_landing_gates.py tone_lint_skips_vue 'SRC_EXT = (".py", ".gd", ".ts", ".tsx", ".js", ".jsx", ".vue",' 'SRC_EXT = (".py", ".gd", ".ts", ".tsx", ".js", ".jsx",'
  mutant lib_landing_gates.sh test_rule_enforces 'tone-test-greeting) mode="$(_z3_mode OVN_Z3_TONE_TEST)"; [ "$mode" = enforce ] && mode=shadow;;' 'tone-test-greeting) mode="$(_z3_mode OVN_Z3_TONE_TEST)";;'
fi
echo "q tone gate: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
