#!/usr/bin/env bash
# Z1 (2026-11-07): ovn_ac_is_placeholder used to refuse any file whose first 4000 bytes contain the placeholder text, so a file with REAL tests plus a leftover placeholder docstring
# (3 iptv landed-uncredited rows) could never be credited. Now: placeholder only when no real content remains once the placeholder line is removed.
# Real fixtures: the three iptv files from the 2026-11-07 outcomes (bulk_action_limits, favorites_rate_limit, parental_check_scope). Includes a mutation proof (old substring check).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/ntfy_guard.sh" 2>/dev/null
LIB="$HERE/../lib_auto_credit.sh"
W="$(safe_mktemp_dir z1ph)" || exit 1
fail=0; ok(){ if eval "$2"; then echo "ok - $1"; else echo "FAIL - $1"; fail=1; fi; }
mkdir "$W/r" && cd "$W/r" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
PH='"""Placeholder - the implement step fills this in."""'
for n in bulk_action_limits favorites_rate_limit parental_check_scope; do cp "$HERE/fixtures_z1/$n.py.txt" "test_real_$n.py"; done
printf '%s\n' "$PH" > test_stub_only.py
printf '%s\nimport pytest\nfrom app import x\n\npass\n# todo\n' "$PH" > test_stub_imports.py
: > test_empty.py
printf '%s\nx = 1\ny = 2\nz = 3\n' "$PH" > src_statements.py
printf 'extends GutTest\n# Placeholder - the implement step fills this in\nfunc test_a():\n\tassert_eq(f(), 1)\n' > test_real.gd
printf 'def test_a():\n    assert True\n' > test_no_placeholder.py
# --- review-fix fixtures (all carry the placeholder marker) ---
printf '// Placeholder - the implement step fills this in.\nimport { describe, it } from '"'"'vitest'"'"'\ndescribe.skip('"'"'placeholder x'"'"', () => {\n  it('"'"'placeholder'"'"', () => {})\n})\n' > stub.test.ts
printf '// Placeholder - the implement step fills this in.\nimport { describe, it, expect } from '"'"'vitest'"'"'\ndescribe('"'"'a'"'"', () => {\n  it('"'"'works'"'"', () => {\n    expect(f()).toBe(3)\n  })\n})\n' > real.spec.ts
printf '// Placeholder\n// Placeholder - the implement step fills this in.\ndescribe('"'"'a'"'"', () => {\n  it.skip('"'"'works'"'"', () => {\n    expect(f()).toBe(3)\n  })\n})\n' > skipped.spec.ts
printf '%s\ndef test_x():\n    pass\n' "$PH" > test_passonly.py
printf '%s\nimport pytest\n@pytest.mark.skip\ndef test_a():\n    assert foo() == 1\n' "$PH" > test_skipped.py
printf '%s\nx = 1\ny = 2\nz = 3\n' "$PH" > test_junk.py
printf '%s\ndef test_a():\n    assert True\n' "$PH" > test_asserttrue.py
printf '%s\ndef test_a():\n    assert foo() == 3\n' "$PH" > test_realassert.py
printf '%s\nimport XCTest\nclass A: XCTestCase {\n  func testA() {\n    XCTAssertEqual(f(), 1)\n  }\n}\n' "$PH" > AFooTests.swift
printf '%s\nclass A {\n  @Test\n  fun a() {\n    assertEquals(1, f())\n  }\n}\n' "$PH" > AFooTest.kt
git add -A && git commit -q -m c
chk(){ ( . "$LIB" 2>/dev/null; ovn_ac_is_placeholder HEAD "$1" ) && echo P || echo R; }   # P = treated as placeholder (refused), R = real
run_cases(){  # $1 = label
  ok "$1 real iptv bulk_action_limits (real tests + leftover docstring) is NOT a placeholder" '[ "$(chk test_real_bulk_action_limits.py)" = R ]'
  ok "$1 real iptv favorites_rate_limit is NOT a placeholder" '[ "$(chk test_real_favorites_rate_limit.py)" = R ]'
  ok "$1 real iptv parental_check_scope is NOT a placeholder" '[ "$(chk test_real_parental_check_scope.py)" = R ]'
  ok "$1 >=3 substantive statements + docstring is real" '[ "$(chk src_statements.py)" = R ]'
  ok "$1 gdscript test with a leftover placeholder comment is real" '[ "$(chk test_real.gd)" = R ]'
  ok "$1 file without the placeholder text is not a placeholder" '[ "$(chk test_no_placeholder.py)" = R ]'
  ok "$1 docstring-only stub IS still a placeholder" '[ "$(chk test_stub_only.py)" = P ]'
  ok "$1 docstring + imports/pass/comments IS still a placeholder" '[ "$(chk test_stub_imports.py)" = P ]'
  ok "$1 harness vitest stub (describe.skip + it('placeholder')) IS a placeholder" '[ "$(chk stub.test.ts)" = P ]'
  ok "$1 ts spec with a real expect IS real" '[ "$(chk real.spec.ts)" = R ]'
  ok "$1 ts spec with it.skip only IS a placeholder" '[ "$(chk skipped.spec.ts)" = P ]'
  ok "$1 placeholder + def test_x(): pass IS a placeholder" '[ "$(chk test_passonly.py)" = P ]'
  ok "$1 placeholder + skip-marked test IS a placeholder" '[ "$(chk test_skipped.py)" = P ]'
  ok "$1 placeholder + 3 junk assignments in a test file IS a placeholder" '[ "$(chk test_junk.py)" = P ]'
  ok "$1 placeholder + assert True IS a placeholder" '[ "$(chk test_asserttrue.py)" = P ]'
  ok "$1 placeholder + real assert in a test fn is real" '[ "$(chk test_realassert.py)" = R ]'
  ok "$1 swift XCTAssert test is real / kotlin @Test assertEquals is real" '[ "$(chk AFooTests.swift)" = R ] && [ "$(chk AFooTest.kt)" = R ]'
  ok "$1 empty file is not (placeholder text absent)" '[ "$(chk test_empty.py)" = R ]'
}
run_cases NEW
# MUTATION: restore the old substring check -> the three real cases must flip to P (fail the NEW expectations)
python3 - "$LIB" "$W/mut_lib.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
i = s.index("ovn_ac_is_placeholder() {")
j = s.index("\n}\n", i) + 3
old = 'ovn_ac_is_placeholder() {\n  local _head; _head="$(git show "$1:$2" 2>/dev/null | head -c 4000)"\n  case "$_head" in *"$OVN_AC_PLACEHOLDER_TEXT"*) return 0 ;; esac\n  return 1\n}\n'
open(sys.argv[2], "w").write(s[:i] + old + s[j:])
PY
chkm(){ ( . "$W/mut_lib.sh" 2>/dev/null; ovn_ac_is_placeholder HEAD "$1" ) && echo P || echo R; }
ok "M1 MUTANT (old substring check): real bulk_action_limits is wrongly a placeholder" '[ "$(chkm test_real_bulk_action_limits.py)" = P ]'
ok "M2 MUTANT (old substring check): real favorites_rate_limit is wrongly a placeholder" '[ "$(chkm test_real_favorites_rate_limit.py)" = P ]'
ok "M3 MUTANT (old substring check): real parental_check_scope is wrongly a placeholder" '[ "$(chkm test_real_parental_check_scope.py)" = P ]'
# MUTATION 2: scanner that treats any `def test`/`it(`/junk lines as real (pre-review-fix awk) -> the stub cases wrongly pass as real
mkdir -p "$W/mutscripts" && cp "$HERE/../lib_auto_credit.sh" "$W/mutscripts/" && cat > "$W/mutscripts/ovn_placeholder_scan.py" <<'PYEOF'
import sys,re
t=sys.stdin.read(); print("real" if re.search(r"(def test|\bit\(|test\(|assert |expect)", t.replace(sys.argv[2],"")) else "stub")
PYEOF
chkm2(){ ( . "$W/mutscripts/lib_auto_credit.sh" 2>/dev/null; ovn_ac_is_placeholder HEAD "$1" ) && echo P || echo R; }
ok "M4 MUTANT (loose scanner): vitest stub wrongly REAL" '[ "$(chkm2 stub.test.ts)" = R ]'
ok "M5 MUTANT (loose scanner): pass-only / assert True wrongly REAL" '[ "$(chkm2 test_passonly.py)" = R ] && [ "$(chkm2 test_asserttrue.py)" = R ]'
cd "$HERE" && safe_rm_rf "$W"
echo "test_z1_placeholder rc=$fail"
exit $fail
