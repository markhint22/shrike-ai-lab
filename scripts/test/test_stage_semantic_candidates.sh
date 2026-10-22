#!/usr/bin/env bash
# 2026-10-22 (PKG-C). The stage runner's SEMANTIC wire check took ONE symbol (the first bare backtick token) and demanded the target file reference it. For the item text
# 'Refactor `get_webhook_deliveries` to call `_filter_deliveries` and `_paginate_deliveries`' the first token is the function being EDITED (one def, nothing else), so test-automation-agent
# 6cf21597b8 burned 2 cycles / 27.6 min / 179k tokens with 2733 tests green and then failed 'only defines (or never uses) get_webhook_deliveries' (and escalated to Claude); same shape on billwatch upvote_bill.
# Part U (unit, runs anywhere): the REAL helper block extracted from ovn_stage_runner.sh. Part F (fixture, needs GNU sed + bash 5): the real runner end to end.
# Mutants: OVN_STAGE_SEMANTIC_CANDIDATES=old (the pre-fix behaviour) and source mutants of the drop/ordering logic must each break the matching assertion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
ROOT="$(cd "$HERE/../.." && pwd)"; RUNNER="${OVN_RUNNER_SRC:-$ROOT/ovn_stage_runner.sh}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
tmp="$(safe_mktemp_dir pkgc-sem)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
PY="$(command -v python3)"
sed -n '/^# >>> pkgC helpers: semantic candidates/,/^# <<< pkgC helpers: semantic candidates/p' "$RUNNER" > "$tmp/h.sh"
[ -s "$tmp/h.sh" ] && grep -q '^stage_semantic_check()' "$tmp/h.sh" || { echo "  FAIL: semantic helper block not found in $RUNNER"; exit 1; }
mutate(){ "$PY" - "$tmp/h.sh" "$1" "$2" "$3" <<'PYEOF' || { F=$((F+1)); echo "  FAIL: mutant anchor not found: $1"; return 1; }
import sys
src, old, new, out = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1: sys.exit(1)
open(out, "w").write(s.replace(old, new))
PYEOF
}
WEB='[T3] backend/app/routers/webhooks.py — Refactor `get_webhook_deliveries` to call `_filter_deliveries` and `_paginate_deliveries`. VERIFY: `pytest backend/tests/test_webhooks.py -q` (cat:python)'
mkwt(){ # <name> <file content> -> worktree dir with backend/app/routers/webhooks.py
  local d="$tmp/$1"; mkdir -p "$d/backend/app/routers"; printf '%b' "$2" > "$d/backend/app/routers/webhooks.py"; printf '%s' "$d"; }
chk(){ # <helper file> <wt> <item> -> evidence on stdout, rc of the check ; mode from env
  ( . "$1"; stage_semantic_check "$2" backend/app/routers/webhooks.py "$3" ); }
GOOD="$(mkwt good 'def _filter_deliveries(rows):\n    return rows\n\ndef _paginate_deliveries(rows, n):\n    return rows[:n]\n\ndef get_webhook_deliveries(rows, n):\n    return _paginate_deliveries(_filter_deliveries(rows), n)\n')"
NONE="$(mkwt none 'def get_webhook_deliveries(rows, n):\n    return rows[:n]\n')"
DEFONLY="$(mkwt defonly 'def _filter_deliveries(rows):\n    return rows\n\ndef _paginate_deliveries(rows, n):\n    return rows[:n]\n\ndef get_webhook_deliveries(rows, n):\n    return rows[:n]\n')"
SELFREF="$(mkwt selfref 'def get_webhook_deliveries(rows, n):\n    return rows[:n]\n\ndef other(rows):\n    return get_webhook_deliveries(rows, 5)\n')"

echo "== U: candidates"
CANDS="$( . "$tmp/h.sh"; stage_semantic_candidates "$WEB" )"
ok "U1 the leading edited symbol is dropped, the callees remain" "[ \"\$(printf '%s' '$CANDS' | tr '\n' ' ')\" = '_filter_deliveries _paginate_deliveries' ]"
OLDC="$( . "$tmp/h.sh"; OVN_STAGE_SEMANTIC_CANDIDATES=old stage_semantic_candidates "$WEB" )"
ok "U2 OVN_STAGE_SEMANTIC_CANDIDATES=old restores the single edited-symbol candidate" "[ '$OLDC' = get_webhook_deliveries ]"
ok "U3 a single-token item keeps its only candidate (drop only when others exist)" "[ \"\$( . '$tmp/h.sh'; stage_semantic_candidates '[T3] a.py — Refactor \`only_one\` for speed. VERIFY: \`pytest\`')\" = only_one ]"
ok "U4 tokens after call/register/wire/hook are tried first" "[ \"\$( . '$tmp/h.sh'; stage_semantic_candidates 'Add \`plain_helper\` then register \`reg_target\` into x.py' | head -1)\" = reg_target ]"
ok "U5 VERIFY-clause tokens, file names and stoplist words are not candidates" "! ( . '$tmp/h.sh'; stage_semantic_candidates 'Wire \`real_fn\` into x.py \`x.py\` \`None\` \`db.commit()\` VERIFY: \`verify_only_name\`' ) | grep -qE 'verify_only_name|x.py|None|commit'"
ok "U6 a dotted call keeps the last segment (old behaviour for real callees)" "[ \"\$( . '$tmp/h.sh'; stage_semantic_candidates 'Wire the \`svc.helper_fn\` call into x.py')\" = helper_fn ]"

echo "== U: the check"
chk "$tmp/h.sh" "$GOOD" "$WEB" > "$tmp/o1" ; R1=$?
ok "U7 the exact webhooks item text with the helpers defined AND called PASSES" "[ $R1 = 0 ] && grep -q 'semantic OK: backend/app/routers/webhooks.py uses _filter_deliveries (2 refs)' '$tmp/o1'"
OVN_STAGE_SEMANTIC_CANDIDATES=old chk "$tmp/h.sh" "$GOOD" "$WEB" > "$tmp/o2"; R2=$?
ok "U8 MUTANT (=old, the pre-fix code) FAILS the same worktree with the exact production message" "[ $R2 = 1 ] && grep -q 'only defines (or never uses) get_webhook_deliveries' '$tmp/o2'"
chk "$tmp/h.sh" "$NONE" "$WEB" > "$tmp/o3"; R3=$?
ok "U9 nothing integrated (helpers absent) still FAILS" "[ $R3 = 1 ] && grep -q 'SEMANTIC FAIL' '$tmp/o3'"
chk "$tmp/h.sh" "$DEFONLY" "$WEB" > "$tmp/o4"; R4=$?
ok "U10 helpers defined but never called still FAILS (def-only = refs 1 with a def)" "[ $R4 = 1 ] && grep -q 'SEMANTIC FAIL' '$tmp/o4'"
chk "$tmp/h.sh" "$SELFREF" "$WEB" > "$tmp/o5"; R5=$?
ok "U11 the edited symbol referenced elsewhere in the file does not rescue a missing integration" "[ $R5 = 1 ]"
SING='[T3] backend/app/routers/webhooks.py — Wire `helper_x` into webhooks.run. VERIFY: `pytest` (cat:python)'
SW="$(mkwt single 'def helper_x():\n    return 2\n\ndef run():\n    return 1\n')"
chk "$tmp/h.sh" "$SW" "$SING" > "$tmp/o6"; R6=$?
ok "U12 single-symbol def-only item still FAILS with the legacy message text" "[ $R6 = 1 ] && grep -q 'only defines (or never uses) helper_x' '$tmp/o6'"
EXT="$(mkwt ext 'def run():\n    return ext_fn()\n')"
chk "$tmp/h.sh" "$EXT" '[T3] backend/app/routers/webhooks.py — Wire `ext_fn` into webhooks.run. VERIFY: `pytest` (cat:python)' > "$tmp/o7"
ok "U13 one reference and no local def (imported symbol) counts as used" "grep -q 'ext_fn (1 refs)' '$tmp/o7'"
ok "U14 no candidates at all -> nothing checkable, rc 0" "( . '$tmp/h.sh'; stage_semantic_check '$GOOD' backend/app/routers/webhooks.py 'Wire things into webhooks.py' >/dev/null )"
# review fix: the CONTAINER (token after into/in/inside/within) must not rescue a missing integration
CONT="$(mkwt cont 'def handler(x):\n    return x\n\ndef other():\n    return handler(1)\n')"
for shape in 'Wire `compute_total` into `handler`' 'Integrate `compute_total` into `handler`' 'Add a call to `compute_total` in `handler`'; do
  CI="[T3] backend/app/routers/webhooks.py — $shape. VERIFY: \`pytest\` (cat:python)"
  chk "$tmp/h.sh" "$CONT" "$CI" > "$tmp/oc"; RC=$?
  ok "U16 container-only reference FAILS for: $shape" "[ $RC = 1 ] && grep -q 'only defines (or never uses) compute_total' '$tmp/oc'"
  ( . "$tmp/h.sh"; stage_semantic_candidates "$CI" ) > "$tmp/ocand"
  ok "U17 container is not a candidate for: $shape" "[ \"\$(cat '$tmp/ocand')\" = compute_total ]"
done
CONTOK="$(mkwt contok 'def compute_total(x):\n    return x\n\ndef handler(x):\n    return compute_total(x)\n')"
chk "$tmp/h.sh" "$CONTOK" '[T3] backend/app/routers/webhooks.py — Wire `compute_total` into `handler`. VERIFY: `pytest`' > "$tmp/od"
ok "U18 a real wire (X defined and called in Y) still PASSES" "grep -q 'semantic OK: backend/app/routers/webhooks.py uses compute_total' '$tmp/od'"
ok "U19 container kept when it is the only token" "[ \"\$( . '$tmp/h.sh'; stage_semantic_candidates 'Add the call into \`only_c\`. VERIFY: \`pytest\`')\" = only_c ]"
mutate 'if any(not c for c in cont.values()):' 'if False:' "$tmp/m_cont.sh" \
  && ok "U-MUTANT no container drop is caught by U16 (false pass rc 0)" "chk '$tmp/m_cont.sh' '$CONT' '[T3] backend/app/routers/webhooks.py — Wire \`compute_total\` into \`handler\`. VERIFY: \`pytest\`' >/dev/null"
mutate 'lead = first[0]' 'lead = None' "$tmp/m_nodrop.sh" \
  && ok "U-MUTANT no leading-symbol drop (edited symbol rescues the item, rc 0) is caught by U11" "chk '$tmp/m_nodrop.sh' '$SELFREF' '$WEB' >/dev/null"
mutate 'if [ "$refs" -ge 2 ] ||' 'if [ "$refs" -ge 99 ] ||' "$tmp/m_refs.sh" \
  && nok "U-MUTANT refs threshold broken is caught by U7" "chk '$tmp/m_refs.sh' '$GOOD' '$WEB' >/dev/null"
ok "U15 the runner gate delegates to stage_semantic_check" "grep -q '_sem_out=\"\$(stage_semantic_check \"\$wt\" \"\$tgt\" \"\$item\")\"' '$RUNNER'"

echo "== F: the real runner (fixture; GNU sed + bash 5 only)"
if sed --version >/dev/null 2>&1 && [ -f "$HERE/lib_osr_fixture.sh" ]; then
  . "$HERE/lib_osr_fixture.sh"
  ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }   # the fixture defines its own ok(label,1|0): restore this file's eval-style helpers
  nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
  trap 'osr_cleanup; safe_rm_rf "$tmp"' EXIT
  export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
  vl(){ VL="$(osr_vlog)"; }
  ITEM='[T3] backend/app/svc.py — Refactor `get_webhook_deliveries` to call `_filter_deliveries` and `_paginate_deliveries`. VERIFY: `pytest backend/tests` (cat:python)'
  SNIP='printf "def _filter_deliveries(r):\n    return r\n\ndef _paginate_deliveries(r, n):\n    return r[:n]\n\ndef get_webhook_deliveries(r, n):\n    return _paginate_deliveries(_filter_deliveries(r), n)\n" > backend/app/svc.py'
  runit(){ osr_new; osr_venv backend; osr_plan default '[{"desc":"refactor get_webhook_deliveries","files":["backend/app/svc.py"],"verify":"t"}]'; osr_aider 1 "$SNIP"; osr_run "$OSR_REPO" "$ITEM"; vl; }
  runit
  ok "F1 new code: the exact webhooks item verifies" "grep -q 'independent full-verify: PASSED' '$T/out.txt' && grep -qF 'semantic OK: backend/app/svc.py uses _filter_deliveries' <<<\"\$VL\""
  osr_cleanup
  OVN_STAGE_SEMANTIC_CANDIDATES=old runit
  ok "F2 MUTANT old mode: the same run FAILS the semantic gate (the production false positive)" "grep -qF 'SEMANTIC FAIL: backend/app/svc.py only defines (or never uses) get_webhook_deliveries' <<<\"\$VL\""
  osr_cleanup
else
  echo "  (Part F skipped: needs GNU sed; run on the box)"; NOTRUN=1
fi
echo "pkgC semantic: pass=$P fail=$F"; [ "$F" = 0 ] || exit 1
[ "${NOTRUN:-0}" = 1 ] && { echo "  NOT RUN: Part F needs GNU sed (run on the box)"; exit 77; }
exit 0
