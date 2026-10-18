#!/usr/bin/env bash
# 2026-10-10 (harness R10, IPTV-2 + BX-02/BX-06): the credit gate READS the unbackticked `VERIFY: <cmd>[.] (cat:...)` form, a GUT VERIFY that calls addons/gut/cli/gut_cli.gd is rewritten to
# gut_cmdln.gd, and the implement-pass name-match credit has a strict (shadow-by-default) mode.
#
# Live defect replayed: lib_verify_clause.sh shadow_check only parsed a BACKTICKED VERIFY, so 56 of 99 live iptv items (and the xlite pair `get_max_directive_value` T1/T2, 02:36 CDT) read as
# NO_VERIFY_CLAUSE and were credited on a file-name match alone ("credited line 2667 (matched MissionDirective.Directive.values)": the function was never written).
# Sections: A bare_verify (the one safety test), B the ovn_credit_items.py CLI, C shadow_check (PASS/FAIL/prose/kill switch/mutation), D gut_cli rewrite, E the credit script end to end
# (xlite replay: refused; mutation = fallback off credits it again; strict modes). E needs GNU sed (the credit script edits with `sed -i`): skipped on the Mac, run on the box.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
safe_use_short_tmp || exit 1     # 2026-10-17: the shadow log truncates cmd= / clause= at 200 chars; a deep TMPDIR (scratchpad, CI workspace) must not push the asserted token out of it
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; [ -f "$S/lib_verify_clause.sh" ] || S="$HERE"
[ -f "$S/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (grep -q + pipefail is flaky: SIGPIPE rc 141)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT

L_GREP='- [ ] [T1] scripts/battle/damage.gd — Add static method `get_max_directive_value()` returning `MissionDirective.Directive.values().max()` VERIFY: grep -q "static func get_max_directive_value" scripts/battle/damage.gd && grep -q "MissionDirective.Directive.values().max()" scripts/battle/damage.gd. (cat:godot; multifile:no) [feat:xlite-20261010-x]'
L_GUT='- [ ] [T2] tests/test_damage.gd — Add test case VERIFY: godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_damage.gd -gexit. (cat:test; multifile:no) [feat:xlite-20261010-x]'
L_PROSE='- [ ] [T2] a.py — Do a thing VERIFY: the function exists and works (cat:python; multifile:no)'
L_TICK='- [ ] [T2] a.py — Do a thing VERIFY: `test -f a.py`. (cat:python; multifile:no)'

echo "== A: ovn_spec_rules.bare_verify"
BV(){ python3 - "$S" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ovn_spec_rules as R
b = R.bare_verify(sys.argv[2])
print(b[1] if b else "")
PY
}
ok "A1 a bare grep clause is accepted, the sentence period dropped" "[ \"\$(BV '$L_GREP')\" = 'grep -q \"static func get_max_directive_value\" scripts/battle/damage.gd && grep -q \"MissionDirective.Directive.values().max()\" scripts/battle/damage.gd' ]"
ok "A2 a bare godot GUT clause is accepted ('-gexit.' -> '-gexit')" "[ \"\$(BV '$L_GUT')\" = 'godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_damage.gd -gexit' ]"
ok "A3 prose is NOT a command (no fallback)" "[ -z \"\$(BV '$L_PROSE')\" ]"
ok "A4 a backticked clause is not the fallback's business" "[ -z \"\$(BV '$L_TICK')\" ]"

echo "== A2: golden lines from the live progress files (2026-10-10 reviewer replay): trailing prose / vacuous pipelines are NOT a command"
cat > "$tmp/golden.tsv" <<'GOLD'
reject	- [ ] [T1] scripts/battle/aoe_targeting.gd — Check x VERIFY: grep -n "GridDistance.chebyshev" scripts/battle/aoe_targeting.gd shows a match near line 41. (cat:godot; multifile:no)
reject	- [ ] [T1] a.gd — Check x VERIFY: grep -c "SaveManager.file_exists_for" scripts/tech/tech_manager.gd returns 1. (cat:godot; multifile:no)
reject	- [ ] [T1] a.gd — Check x VERIFY: grep -c "func " scripts/battle/enemy_faction_map.gd | awk '{if ($1 > 0) print "HAS_FUNCS"; else print "EMPTY"}'. (cat:godot; multifile:no)
reject	- [ ] [T4] r.py — Refactor VERIFY: grep -r "filter_streams_for_profile" iptv-backend/app/routers/ | wc -l >= 2 && pytest iptv-backend/tests/test_streams_router.py -q. (cat:refactor; multifile:yes)
reject	- [ ] [T5] auth.py — Bump VERIFY: grep -n "token_version" iptv-backend/app/routers/auth.py | wc -l. (cat:endpoint; multifile:no)
reject	- [ ] [T1] s.py — Replace VERIFY: grep -n "Hey!" iptv-backend/app/services/stream_limit.py | wc -l returns 0. (cat:python; multifile:no)
reject	- [ ] [T1] s.py — Replace VERIFY: grep -q foo a.txt || echo MISSING (cat:python; multifile:no)
reject	- [ ] [T1] s.py — Replace VERIFY: grep -c foo a.txt | cat (cat:python; multifile:no)
reject	- [ ] [T1] m.py — Check x VERIFY: grep -n "def get_max" f.py and grep -n "return" f.py. (cat:python; multifile:no)
reject	- [ ] [T1] m.py — Check x VERIFY: test -f a.py or test -f b.py (cat:python; multifile:no)
accept	- [ ] [T1] m.py — Check x VERIFY: grep -q "this and that" f.py (cat:python; multifile:no)
accept	- [ ] [T1] m.py — Check x VERIFY: grep -q "def get_max" f.py && grep -q "return" f.py (cat:python; multifile:no)
accept	- [ ] [T4] g.py — Refactor VERIFY: grep -c "execute_with_httpx" backend/app/services/github.py | awk '{exit $1 < 5}' && pytest backend/tests/test_github_client.py -v. (cat:refactor; multifile:no)
accept	- [ ] [T3] v.vue — Add VERIFY: grep -n 'type="button"' iptv-web/src/components/DuplicateSourcePicker.vue | wc -l | grep -q "1". (cat:vue; multifile:no)
accept	- [ ] [T1] s.py — Add VERIFY: grep -q foo a.txt && echo OK (cat:python; multifile:no)
accept	- [ ] [T1] s.py — Add VERIFY: grep -q "anthropic==0.4" backend/requirements.txt || grep -q "anthropic>=0.4" backend/requirements.txt (cat:python; multifile:no)
accept	- [ ] [T1] s.py — Add VERIFY: python -c "from a import f; assert len(f('x')) >= 4" (cat:python; multifile:no)
accept	- [ ] [T1] m.gd — Add VERIFY: grep -A 5 "func research_tech" scripts/tech/tech_manager.gd | grep -q "can_research" (cat:godot; multifile:no)
accept	- [ ] [T1] m.gd — Add VERIFY: python3 -m pytest tests/test_a.py::test_one -q -x. (cat:python; multifile:no)
GOLD
cat > "$tmp/golden.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ovn_spec_rules as R
for i, raw in enumerate(open(sys.argv[2], encoding="utf-8").read().split("\n")):
    if not raw.strip():
        continue
    want, line = raw.split("\t", 1)
    got = "accept" if R.bare_verify(line) else "reject"
    print(("OK   " if got == want else "FAIL ") + "golden-%02d-%s" % (i + 1, want))
PY
python3 "$tmp/golden.py" "$S" "$tmp/golden.tsv" > "$tmp/golden.out" 2>&1
ok "A2 every golden line has the expected verdict ($(grep -c . "$tmp/golden.tsv") lines)" "[ \"\$(grep -c '^OK' '$tmp/golden.out')\" = \"\$(grep -c . '$tmp/golden.tsv')\" ] && ! grep -q '^FAIL' '$tmp/golden.out'"
grep '^FAIL' "$tmp/golden.out" | sed 's/^/  /'

echo "== B: ovn_credit_items.py bare-verify"
printf '%s\n%s\n%s\n%s\n' "$L_GREP" "$L_GUT" "$L_PROSE" "$L_TICK" > "$tmp/prog.md"
ok "B1 line 1 -> its command" "python3 '$S/ovn_credit_items.py' bare-verify '$tmp/prog.md' 1 | grep -q '^grep -q \"static func get_max_directive_value\"'"
ok "B2 prose (line 3) and backticked (line 4) -> nothing" "[ -z \"\$(python3 '$S/ovn_credit_items.py' bare-verify '$tmp/prog.md' 3)\" ] && [ -z \"\$(python3 '$S/ovn_credit_items.py' bare-verify '$tmp/prog.md' 4)\" ]"
ok "B3 out-of-range / non-numeric line -> nothing, rc 0" "[ -z \"\$(python3 '$S/ovn_credit_items.py' bare-verify '$tmp/prog.md' 99)\" ] && python3 '$S/ovn_credit_items.py' bare-verify '$tmp/prog.md' x >/dev/null"

echo "== C: shadow_check reads the bare form"
mkdir -p "$tmp/c/scripts/battle"; cd "$tmp/c" || exit 1
printf 'extends RefCounted\nstatic func other() -> int:\n\treturn 1\n' > scripts/battle/damage.gd
printf '%s\n' "$L_GREP" > prog.md
printf '%s\n' '- [ ] [T1] a.txt — x VERIFY: test -f a.txt. (cat:python)' >> prog.md       # line 2: bare, passes once a.txt exists
printf '%s\n' "$L_PROSE" >> prog.md                                                       # line 3: prose
export PROG="$tmp/c/prog.md" SHADOW_LOG="$tmp/c/shadow.log" _REPO_LABEL=t
# shellcheck disable=SC1090
. "$S/lib_verify_clause.sh"
shadow_check 1
ok "C1 bare grep VERIFY on a tree WITHOUT the function -> FAIL (was NO_VERIFY_CLAUSE: the false-credit door)" "[ '$_LAST_VERIFY_RESULT' = FAIL ]"
ok "C1b ... and the verdict is marked as reached through the fallback" "[ '$_LAST_VERIFY_BARE' = 1 ]"
shadow_check 2
ok "C2 bare 'test -f a.txt.' with no a.txt -> FAIL" "[ '$_LAST_VERIFY_RESULT' = FAIL ]"
touch a.txt; shadow_check 2
ok "C3 ... and PASS once the file exists" "[ '$_LAST_VERIFY_RESULT' = PASS ] && [ '$_LAST_VERIFY_BARE' = 1 ]"
L_SHOWS='- [ ] [T1] scripts/battle/damage.gd — Check x VERIFY: grep -n "static func other" scripts/battle/damage.gd shows a match near line 2. (cat:godot; multifile:no)'
printf '%s\n' "$L_SHOWS" > prog2.md; PROG="$tmp/c/prog2.md" shadow_check 1
ok "C4b a command followed by narration is NO_VERIFY_CLAUSE, not a bash -c FAIL that would refuse a legitimate credit" "[ '$_LAST_VERIFY_RESULT' = NO_VERIFY_CLAUSE ] && [ -z '$_LAST_VERIFY_BARE' ]"
shadow_check 3
ok "C4 prose VERIFY stays NO_VERIFY_CLAUSE (never run as a command)" "[ '$_LAST_VERIFY_RESULT' = NO_VERIFY_CLAUSE ] && [ -z '$_LAST_VERIFY_BARE' ]"
OVN_VERIFY_BARE_FALLBACK=off shadow_check 1
ok "C5 MUTATION / kill switch OVN_VERIFY_BARE_FALLBACK=off: the old NO_VERIFY_CLAUSE answer comes back" "[ '$_LAST_VERIFY_RESULT' = NO_VERIFY_CLAUSE ]"
touch a.py; printf '%s\n' "$L_TICK" > prog1.md; PROG="$tmp/c/prog1.md" shadow_check 1
ok "C6 a backticked VERIFY is read exactly as before and is not marked bare" "[ '$_LAST_VERIFY_RESULT' = PASS ] && [ -z '$_LAST_VERIFY_BARE' ]"
cat "$tmp/c/prog.md" > /dev/null

echo "== D: gut_cli.gd -> gut_cmdln.gd at run time"
mkdir -p "$tmp/d/addons/gut/cli" "$tmp/d/bin"; cd "$tmp/d" || exit 1
safe_set_sandbox_home "$tmp/d" || exit 1; mkdir -p "$HOME/godot"
printf '%s\n' '#!/usr/bin/env bash' 'echo "STUB-GODOT $*"' 'exit 0' > "$HOME/godot/godot4"; chmod +x "$HOME/godot/godot4"
printf '%s\n' '- [ ] [T2] tests/t.gd — x VERIFY: `godot --headless -s addons/gut/cli/gut_cli.gd -gdir=tests -gexit`. (cat:test)' > prog.md
export PROG="$tmp/d/prog.md" SHADOW_LOG="$tmp/d/shadow.log"
shadow_check 1
ok "D1 the command that runs names gut_cmdln.gd, not gut_cli.gd" "grep -q 'gut_cmdln.gd' '$tmp/d/shadow.log' && ! grep -q 'gut_cli.gd' '$tmp/d/shadow.log'"
OVN_VERIFY_GUT_CLI_REWRITE=off shadow_check 1
ok "D2 MUTATION / kill switch OVN_VERIFY_GUT_CLI_REWRITE=off: gut_cli.gd is run as written" "tail -1 '$tmp/d/shadow.log' | grep -q 'gut_cli.gd'"

echo "== E: ovn_credit_already_satisfied.sh end to end (the xlite 02:36 replay)"
if ! sed --version >/dev/null 2>&1; then
  echo "  SKIP: needs GNU sed (the credit script edits with sed -i); run on the box"
else
  CR="$S/ovn_credit_already_satisfied.sh"
  mk(){ rm -rf "${tmp:?}/e"; mkdir -p "$tmp/e/scripts/battle" "$tmp/e/tests"; cd "$tmp/e" || exit 1
    printf 'extends RefCounted\nstatic func other() -> int:\n\treturn 1\n' > scripts/battle/damage.gd
    printf '%s\n' "$1" > OVERNIGHT_PROGRESS.md
    printf 'scripts/battle/damage.gd\nThis item is already done, no changes needed.\n' > aider.log
    : > shadow.log; }
  run(){ OVN_VERIFY_SHADOW_LOG="$tmp/e/shadow.log" env "$@" bash "$CR" aider.log OVERNIGHT_PROGRESS.md 2>&1; }
  mk "$L_GREP"
  out="$(run)"
  ok "E1 REPLAY: the bare VERIFY (function never written) FAILS, so the name-match credit is REFUSED" "printf '%s' '$out' | grep -q 'REFUSED credit' && printf '%s' '$out' | grep -q 'CREDITED=0' && grep -q '^- \[ \] ' OVERNIGHT_PROGRESS.md"
  mk "$L_GREP"
  out="$(run OVN_VERIFY_BARE_FALLBACK=off)"
  ok "E2 MUTATION (fallback off = the old reader): the same item IS credited on the path match alone" "printf '%s' '$out' | grep -q 'credited line 1' && grep -q '^- \[x\] (already-satisfied' OVERNIGHT_PROGRESS.md"
  # strict mode: an item whose VERIFY cannot be run at all (prose) is credited on a name match only
  P2='- [ ] [T1] scripts/battle/damage.gd — Do a thing VERIFY: the function exists and works (cat:godot; multifile:no)'
  mk "$P2"; out="$(run)"
  ok "E3 default strict mode is SHADOW: credited, with a STRICT-SHADOW line saying enforce would refuse" "printf '%s' '$out' | grep -q 'CREDITED=1' && printf '%s' '$out' | grep -q 'STRICT-SHADOW'"
  mk "$P2"; out="$(run OVN_IMPL_CREDIT_REQUIRE_VERIFY=enforce)"
  ok "E4 OVN_IMPL_CREDIT_REQUIRE_VERIFY=enforce: refused, left open" "printf '%s' '$out' | grep -q 'strict mode' && printf '%s' '$out' | grep -q 'CREDITED=0' && grep -q '^- \[ \] ' OVERNIGHT_PROGRESS.md"
  mk "$P2"; out="$(run OVN_IMPL_CREDIT_REQUIRE_VERIFY=off)"
  ok "E5 OVN_IMPL_CREDIT_REQUIRE_VERIFY=off: credited, silent" "printf '%s' '$out' | grep -q 'CREDITED=1' && ! printf '%s' '$out' | grep -q 'STRICT-SHADOW'"
  G='- [ ] [T1] scripts/battle/damage.gd — Add x VERIFY: grep -q "static func other" scripts/battle/damage.gd. (cat:godot; multifile:no)'
  mk "$G"; out="$(run OVN_IMPL_CREDIT_REQUIRE_VERIFY=enforce)"
  ok "E6 strict enforce still credits an item whose bare VERIFY PASSES" "printf '%s' '$out' | grep -q 'CREDITED=1'"
fi

echo "bare-verify fallback: $P passed, $F failed"
[ "$F" -eq 0 ]
