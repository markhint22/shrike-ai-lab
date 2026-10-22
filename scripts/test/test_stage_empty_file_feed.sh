#!/usr/bin/env bash
# 2026-10-22 (PKG-C). Empty-file steps stalled: 14 attempts / 1530s / 4 blocked steps. billwatch-082054: the decomposer declared bills.py but the function lives in bill_service.py; the architect asked 'Please add
# these files to the chat' (the feed regex only knew 'add the following files') and the feed only fired on fa=no-edit, never on fa=empty-file.
# Changes under test (ovn_stage_runner.sh): (1) the ask regex also matches '(add|provide|share) (these|the following) files'; (2) the feed also runs for fa=empty-file; (3) OVN_STAGE_SYMBOL_CONTEXT=off|shadow|on
# (default shadow): the defining file of a backticked snake_case symbol and the source of a declared test_<stem>.py are added (on) or only LOGGED (shadow).
# Part U (unit, anywhere): helper block from the real runner. Part F (fixture, GNU sed + bash 5): the real runner. Mutants break the matching assertion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
ROOT="$(cd "$HERE/../.." && pwd)"; RUNNER="${OVN_RUNNER_SRC:-$ROOT/ovn_stage_runner.sh}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
tmp="$(safe_mktemp_dir pkgc-feed)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
PY="$(command -v python3)"
{ sed -n '/^# >>> n4-stage-waste helpers: scope-learn/,/^# <<< n4-stage-waste helpers: scope-learn/p' "$RUNNER"; sed -n '/^# >>> n4-stage-waste helpers: file-feed/,/^# <<< n4-stage-waste helpers: file-feed/p' "$RUNNER"; } > "$tmp/h.sh"
grep -q '^stage_symbol_files()' "$tmp/h.sh" && grep -q '^stage_feed_filter()' "$tmp/h.sh" || { echo "  FAIL: feed helper block not found in $RUNNER"; exit 1; }
mutate(){ "$PY" - "$tmp/h.sh" "$1" "$2" "$3" <<'PYEOF' || { F=$((F+1)); echo "  FAIL: mutant anchor not found: $1"; return 1; }
import sys
src, old, new, out = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1: sys.exit(1)
open(out, "w").write(s.replace(old, new))
PYEOF
}
W="$tmp/repo"; mkdir -p "$W/backend/app/routers" "$W/backend/app/services" "$W/backend/tests"; git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
printf 'def list_bills():\n    return []\n' > "$W/backend/app/routers/bills.py"
printf 'def upvote_bill(bill_id):\n    return bill_id\n' > "$W/backend/app/services/bill_service.py"
printf 'from app.services.bill_service import upvote_bill\n\ndef test_x():\n    assert upvote_bill(1) == 1\n' > "$W/backend/tests/test_bill_service.py"
printf 'def dup_fn():\n    return 1\n' > "$W/backend/app/a1.py"; printf 'def dup_fn():\n    return 2\n' > "$W/backend/app/a2.py"
git -C "$W" add -A; git -C "$W" commit -qm init
. "$tmp/h.sh"
echo "== U: ask regex"
for phr in 'Please add these files to the chat:' 'Please add the following files to the chat:' 'Please provide the following files:' 'Please share these files with me:' 'ADD THESE FILES'; do
  printf '%s\n\n 1 backend/app/services/bill_service.py\nTokens: 1 sent\n' "$phr" > "$tmp/arch.log"
  ok "U1 '$phr' -> the named file is fed" "[ \"\$(stage_feed_files '$tmp/arch.log' '$W' '' 3)\" = backend/app/services/bill_service.py ]"
  ok "U1b '$phr' -> stage_feed_asked" "stage_feed_asked '$tmp/arch.log'"
done
printf 'I looked at bill_service.py and it is fine.\n' > "$tmp/noask.log"
nok "U2 no request -> nothing fed, not asked" "[ -n \"\$(stage_feed_files '$tmp/noask.log' '$W' '' 3)\" ] || stage_feed_asked '$tmp/noask.log'"
printf 'Please add these files to the chat:\n\n 1 backend/app/services/bill_service.py\nTokens: 1 sent\n' > "$tmp/arch.log"
mutate "STAGE_FEED_ASK_RE='(add|provide|share) (these|the following) files?'" "STAGE_FEED_ASK_RE='add the following files?'" "$tmp/m_re.sh" \
  && nok "U-MUTANT the OLD ask regex ('add the following files') misses 'Please add these files' (caught by U1)" "( . '$tmp/m_re.sh'; [ \"\$(stage_feed_files '$tmp/arch.log' '$W' '' 3)\" = backend/app/services/bill_service.py ] )"
echo "== U: symbol context"
ITEM='[T3] backend/app/routers/bills.py — Make `upvote_bill` idempotent. VERIFY: `pytest backend/tests/test_bill_service.py`'
SYM="$(stage_symbol_files "$W" "$ITEM" "backend/app/routers/bills.py backend/tests/test_bill_service.py" "backend/app/routers/bills.py backend/tests/test_bill_service.py" 3)"
ok "U3 the DEFINING file of a snake_case symbol is found (bill_service.py, not the declared bills.py)" "[ \"\$(printf '%s\n' '$SYM' | grep -c .)\" = 1 ] && printf '%s\n' '$SYM' | grep -qx backend/app/services/bill_service.py"
SYM2="$(stage_symbol_files "$W" "no symbols here" "backend/tests/test_bill_service.py" "backend/tests/test_bill_service.py" 3)"
ok "U4 a declared test_<stem>.py adds the unique <stem>.py source" "[ '$SYM2' = backend/app/services/bill_service.py ]"
BT='`'
SYM3="$(stage_symbol_files "$W" "Fix ${BT}dup_fn${BT} now" "" "" 3)"
ok "U5 a symbol defined in two files is ambiguous -> nothing fed" "[ -z '$SYM3' ]"
SYM4="$(stage_symbol_files "$W" "$ITEM" "backend/app/services/bill_service.py" "backend/app/services/bill_service.py" 3)"
ok "U6 an already-loaded defining file is not fed again" "[ -z '$SYM4' ]"
SYM5="$(stage_symbol_files "$W" "Run ${BT}pytest${BT} and fix ${BT}list_bills${BT} and tests" "" "" 3)"
ok "U7 only snake_case (with underscore) symbols are looked up (list_bills in bills.py is found, 'pytest' is not)" "[ '$SYM5' = backend/app/routers/bills.py ]"
SYM6="$(stage_symbol_files "$W" "Fix ${BT}dup_fn${BT}" "" "" 3)"
ok "U5b sanity: with the ambiguous symbol the real input shape is exercised (control: unique symbol IS found)" "[ -n \"\$(stage_symbol_files '$W' 'Fix ${BT}upvote_bill${BT}' '' '' 3)\" ]"
echo "== U: call-site wiring"
ok "U8 the feed also runs for empty-file" "grep -qE '\\[ \"\\\$fa\" = \"no-edit\" \\] \\|\\| \\[ \"\\\$fa\" = \"empty-file\" \\]' '$RUNNER'"
ok "U9 symbol context defaults to shadow" "grep -q 'OVN_STAGE_SYMBOL_CONTEXT:-shadow' '$RUNNER'"

echo "== F: the real runner (fixture; GNU sed + bash 5 only)"
NOTRUN=0
if sed --version >/dev/null 2>&1 && [ -f "$HERE/lib_osr_fixture.sh" ]; then
  . "$HERE/lib_osr_fixture.sh"
  ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }   # the fixture defines its own ok(label,1|0): restore this file's eval-style helpers
  nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
  trap 'osr_cleanup; safe_rm_rf "$tmp"' EXIT
  unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_FILE_FEED OVN_STAGE_SYMBOL_CONTEXT NTFY_SERVER NTFY_TOPIC
  has_arg(){ awk -v f="$1" -v p="$2" 'prev==f && $0==p {found=1} {prev=$0} END{exit !found}' "$T/scn/aider.args.$3"; }
  PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
  # attempt 1: the architect asks for files ('Please add these files') AND the declared test file is left EMPTY (fa=empty-file)
  ASK='mkdir -p backend/app backend/tests
printf "def foo():\n    return 1\n" > backend/app/foo.py
: > backend/tests/test_foo.py
echo "Please add these files to the chat:"
echo
echo " 1 backend/app/svc.py"
echo
echo "Tokens: 7.8k sent, 448 received."'
  setup(){ osr_new; osr_venv backend; osr_tracked backend/tests/test_svc.py 'from app.svc import run_job\n\ndef test_x():\n    assert run_job() == 1\n'
    osr_progress "${1:-$ITEM_PY}"; osr_plan default "$PLAN"; osr_aider 1 "$ASK"; osr_aider 2 "$SNIP_FOO"; }
  run(){ OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"; }
  setup "- [ ] $ITEM_PY"; run
  ok "F1 attempt 1 is an empty-file failure" "grep -qF 'step 0 att 1 FAIL (empty-file' '$T/out.txt'"
  ok "F2 the architect-named file is fed on the empty-file retry (--file backend/app/svc.py)" "has_arg --file backend/app/svc.py 2"
  ok "F3 the retry still carries the empty-file feedback" "grep -q 'EMPTY (0 bytes)' '$T/scn/aider.args.2'"
  osr_cleanup
  # symbol context. NOTE run_step already auto-adds the file that DEFINES a backticked symbol before attempt 1 (AUTO-ADD SOURCE FILES), so the live gap is the TEST-FILE STEM: a declared
  # test_jobs_mod.py whose source jobs_mod.py is not declared. shadow = logged only; on = fed.
  STEMPLAN='[{"desc":"add jobs mod test","files":["backend/tests/test_jobs_mod.py"],"verify":"pytest backend/tests/test_jobs_mod.py"}]'
  STEMITEM='- [ ] [T3] backend/tests/test_jobs_mod.py — Add a test for the jobs module. VERIFY: `pytest backend/tests/test_jobs_mod.py` (cat:python)'
  ASK2='mkdir -p backend/tests
: > backend/tests/test_jobs_mod.py
echo "ok"'
  SNIP2='mkdir -p backend/tests
printf "def test_x():\n    assert True\n" > backend/tests/test_jobs_mod.py'
  stemsetup(){ osr_new; osr_venv backend; osr_tracked backend/app/jobs_mod.py 'def helper():\n    return 1\n'; osr_progress "$STEMITEM"; osr_plan default "$STEMPLAN"; osr_aider 1 "$ASK2"; osr_aider 2 "$SNIP2"; }
  stemsetup; run
  ok "F4 shadow (default): the would-be symbol-context file is logged" "grep -q 'symbol-context (shadow): would also feed backend/app/jobs_mod.py' '$T/out.txt'"
  nok "F5 shadow: it is NOT fed to the retry" "has_arg --file backend/app/jobs_mod.py 2"
  ok "F5b shadow: the event is journaled" "cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | grep -q '\"event\":\"symbol_context\"'"
  osr_cleanup
  stemsetup; OVN_STAGE_SYMBOL_CONTEXT=on run
  ok "F6 on: the stem source IS fed (--file backend/app/jobs_mod.py)" "has_arg --file backend/app/jobs_mod.py 2"
  osr_cleanup
  stemsetup; OVN_STAGE_SYMBOL_CONTEXT=off run
  ok "F7 off: nothing logged, nothing fed" "! grep -q 'symbol-context' '$T/out.txt' && ! has_arg --file backend/app/jobs_mod.py 2"
  osr_cleanup
else
  echo "  (Part F skipped: needs GNU sed; run on the box)"; NOTRUN=1
fi
echo "pkgC empty-file feed: pass=$P fail=$F"; [ "$F" = 0 ] || exit 1
[ "$NOTRUN" = 1 ] && { echo "  NOT RUN: Part F needs GNU sed (run on the box)"; exit 77; }
exit 0
