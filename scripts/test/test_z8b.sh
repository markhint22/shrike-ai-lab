#!/usr/bin/env bash
# Z8b (2026-11-10): gate recall + waste cuts. Runs test_z8b_gates.py (python units: tone tokens, assert-weaken recall kinds, unused-import fixer, plan-path check), then re-runs it against
# MUTANTS (every mutant must be KILLED), then shell-level checks: ovn_tsc_gate.sh autofix of unused imports with a fake vue-tsc (fixed / shadow / off / untouched file / mutants),
# z3_commit_audit on a real commit range (shadow journal, kill switch, flags), wiring greps (run_overnight.sh, ovn_credit_already_satisfied.sh), pinned defaults of the shadow-vs-enforce
# decisions (timeout park / build-break park stay SHADOW with the measured precision; empty-file whole retry is ON; dependency no-edit rule is ON).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
SRC="$HERE/.."; ROOT="$HERE/../.."
rc=0
"$PY" "$HERE/test_z8b_gates.py" || rc=1
echo "test_z8b_gates.py rc=$rc"
[ "$rc" -eq 0 ] || exit 1
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
MD="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$MD"' EXIT
echo "== Z8b mutation proofs (each mutant must make the python suite FAIL)"
survived=0; n=0
mut() {  # mut <file> <label> <old> <new>
  local f="$1" label="$2" old="$3" new="$4" d="$MD/$((n+1))"
  n=$((n+1)); mkdir -p "$d"; cp "$SRC/ovn_landing_gates.py" "$SRC/ovn_ts_unused_imports.py" "$SRC/ovn_plan_path_ok.py" "$d/"
  if ! OLD="$old" NEW="$new" "$PY" - "$d/$f" <<'PYEOF'
import os, sys
p = sys.argv[1]; s = open(p).read(); old = os.environ["OLD"]; new = os.environ["NEW"]
if old not in s:
    sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then echo "  FAIL mutant '$label' could not be applied (source changed?)"; survived=$((survived+1)); return; fi
  if Z8B_MODULE_DIR="$d" "$PY" "$HERE/test_z8b_gates.py" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); else echo "  ok   mutant killed: $label"; fi
}
G=ovn_landing_gates.py; U=ovn_ts_unused_imports.py; PP=ovn_plan_path_ok.py
mut $G "A: Heads up not in the token list"        'Z8_TONE_EXTRA = ("Heads up", ' 'Z8_TONE_EXTRA = ('
mut $G "A: comment lines judged for new tokens"   'if w in Z8_TONE_EXTRA and _z8_tone_on() and (_is_comment(t)' 'if w in Z8_TONE_EXTRA and _z8_tone_on() and (False'
mut $G "A: kill switch OVN_Z8_TONE ignored"       'return os.environ.get("OVN_Z8_TONE", "on").strip().lower() != "off"' 'return True'
mut $G "B: expectation-trivial never reported"    'hit("expectation-trivial"' '(lambda *a: None)("expectation-trivial"'
mut $G "B: expectation-trivial without a source edit" 'if src_touched and not retired:
                    for ln, t in rem:
                        if not _ASSERTISH_RE.search(t) or _is_comment(t) or _TRIVIAL_EXP_RE.search(t):' 'if not retired:
                    for ln, t in rem:
                        if not _ASSERTISH_RE.search(t) or _is_comment(t) or _TRIVIAL_EXP_RE.search(t):'
mut $G "B: trivial zero matches 0.5"              '|==\s*0(?![\w.])|' '|==\s*0\b|'
mut $G "B: stream-assert-deleted never reported"  'hit("stream-assert-deleted"' '(lambda *a: None)("stream-assert-deleted"'
mut $G "B: stream assertion kept in new file still flagged" 'and (new_norm_s is None or _norm_line(t) not in new_norm_s):' ':'
mut $G "B: reworded stream assertion still flagged" 'for ln, t in ([] if stream_added else rem):' 'for ln, t in rem:'
mut $G "B: bulk-assert-deleted never reported"    'found.setdefault("bulk-assert-deleted"' '(lambda *a, **k: None)("bulk-assert-deleted"'
mut $G "B: post-image lines still counted as lost"  'all_added_norm |= set(_norm_line(x) for x in new_text.split("\n"))' 'pass'
mut $G "B: expectation subject not compared"      'return n[:m.start()] + "|" + _VALUE_TOK_RE.sub("E", n[m.start():])' 'return _VALUE_TOK_RE.sub("E", n)'
mut $G "B: duplicate test name still in file counted as removed" 'and not (new_text and re.search(r"(?:def|func)' 'and not (False and re.search(r"(?:def|func)'
mut $G "B: bulk moved lines still counted"        'and _norm_line(t) not in all_added_norm:
                        gone.append' ':
                        gone.append'
mut $G "B: bulk-test-deleted never reported"      'found.setdefault("bulk-test-deleted"' '(lambda *a, **k: None)("bulk-test-deleted"'
mut $G "B: bulk-test-deleted bar removed"         'or net_lines >= _envint("OVN_Z8_BULK_LINES_N", 100)):' 'or net_lines >= 0):'
mut $G "B: 429 not a status-flip-src code"        '(c == 429 and _z8_on())' '(c == 0)'
mut $G "B: Z8 kill switch ignored"                'return _z7_on() and os.environ.get("OVN_Z8_ASSERT_RECALL", "on").strip().lower() != "off"' 'return _z7_on()'
mut $G "B: Z8 not subordinate to Z7 kill switch"  'return _z7_on() and os.environ.get("OVN_Z8_ASSERT_RECALL"' 'return os.environ.get("OVN_Z8_ASSERT_RECALL"'
mut $U "D: side-effect / non-binding names removed" 'if default == name:' 'if True:'
mut $U "D: declaration kept when no binding left"  'last = m.end()
            if text[last:last + 2] == "\r\n":' 'last = m.start()
            if text[last:last + 2] == "\r\n":'
mut $U "D: added-lines filter ignored"            'if added is not None and not (set(range(l0, l1 + 1)) & added):' 'if False:'
mut $U "D: semicolon always added"                '";" if m.group(0).rstrip().endswith(";") else ""' '";"'
mut $U "D: dry-run writes anyway"                 'if not a.dry_run:
                with open' 'if True:
                with open'
mut $PP "F: extension check removed"              'if ext not in KNOWN_EXT:
        return False' 'if False:
        return False'
mut $PP "F: existence check removed"              '    return False


def main' '    return True


def main'
mut $PP "F: kill switch ignored"                  'if os.environ.get("OVN_PLAN_PATH_STRICT", "on").strip().lower() == "off" or len(argv) < 3:' 'if len(argv) < 3:'
echo "mutants: $n, survived/unapplied: $survived"
[ "$survived" -eq 0 ] || exit 1

echo "== D: ovn_tsc_gate.sh autofix with a fake vue-tsc (TS6133 on an import the commit added)"
fail=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL $1"; fail=1; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$MD"; safe_rm_rf "$tmp"' EXIT
GATE="$SRC/ovn_tsc_gate.sh"
mk_repo() {  # mk_repo <name> -> repo with web/ and a fake vue-tsc that reports TS6133 for any `vi` import still present in src/*.ts and 2 baseline errors
  local r="$tmp/$1"; mkdir -p "$r/web/src" "$r/web/node_modules/.bin" "$tmp/bl-$1"
  cat > "$r/web/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
for f in src/*.ts; do
  n=$(grep -n "import {[^}]*\bvi\b[^}]*} from" "$f" | head -1 | cut -d: -f1)
  [ -n "$n" ] && echo "$f($n,1): error TS6133: 'vi' is declared but its value is never read."
done
echo "src/base.ts(1,1): error TS2322: baseline one"
echo "src/base.ts(2,1): error TS2322: baseline two"
exit 1
FAKE
  chmod +x "$r/web/node_modules/.bin/vue-tsc"
  echo '{"compilerOptions":{"noEmit":true},"include":["src"]}' > "$r/web/tsconfig.json"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && echo "export const b = 1;" > web/src/base.ts && printf "import { describe } from 'vitest'\ndescribe('a', () => {})\n" > web/src/a.test.ts && git add -A && git commit -qm base )
  echo 2 > "$tmp/bl-$1/testrepo__web.count"
  printf '%s' "$r"
}
add_commit() {  # add_commit <repo> -> echoes the new sha (adds the unused vi import to a.test.ts)
  ( cd "$1" && printf "import { describe, vi } from 'vitest'\ndescribe('a', () => {})\n" > web/src/a.test.ts && git add -A && git commit -qm item && git rev-parse HEAD )
}
run_gate() { # run_gate <name> <repo> <before> <after> [env...]
  local nm="$1" r="$2" b="$3" a="$4"; shift 4
  env OVN_TSC_PREMEASURE=0 OVN_SAFE_TMP_LIB="$HERE/lib_safe_tmp.sh" "$@" bash "$GATE" "$r" "$tmp/bl-$nm" testrepo "$b" "$a" 2>&1
}
r="$(mk_repo on)"; b0="$(git -C "$r" rev-parse HEAD)"; a0="$(add_commit "$r")"
out="$(run_gate on "$r" "$b0" "$a0")"
echo "$out" | grep -q "TSC-UNUSED-IMPORTS-FIXED" && ok "D20 default ON: the unused import is removed (TSC-UNUSED-IMPORTS-FIXED logged)" || bad "D20: $out"
echo "$out" | grep -q "TSC-RATCHET-REGRESSION" && bad "D21 no regression expected after the fix: $out" || ok "D21 the ratchet no longer sees a regression after the autofix"
echo "$out" | grep -q "TSC-RATCHET-OK" && ok "D21b ratchet verdict OK (errors held at the baseline)" || bad "D21b: $out"
[ "$(git -C "$r" rev-list --count "$a0..HEAD")" = 1 ] && [ "$(git -C "$r" log -1 --format=%s)" = "fix(ts): remove unused imports flagged by tsc (TS6133/TS6192/TS6196)" ] && ok "D22 the fix is ONE small commit on top of the item commit" || bad "D22: $(git -C "$r" log --oneline | head -3)"
grep -q "^import { describe } from 'vitest'" "$r/web/src/a.test.ts" && ok "D23 only the unused binding is gone" || bad "D23: $(cat "$r/web/src/a.test.ts")"
git -C "$r" diff --quiet HEAD && ok "D24 tree clean after the fix commit" || bad "D24 dirty"
grep -q " fixed 1 " "$tmp/bl-on/unused_import_fix.log" 2>/dev/null && ok "D25 journal row state/tsc_baseline/unused_import_fix.log written" || bad "D25"
# off: the regression is reported exactly like before
r="$(mk_repo off)"; b0="$(git -C "$r" rev-parse HEAD)"; a0="$(add_commit "$r")"
out="$(run_gate off "$r" "$b0" "$a0" OVN_TSC_UNUSED_FIX=off)"
echo "$out" | grep -q "TSC-RATCHET-REGRESSION" && ! echo "$out" | grep -q "UNUSED-IMPORTS" && [ "$(git -C "$r" rev-parse HEAD)" = "$a0" ] && ok "D26 OVN_TSC_UNUSED_FIX=off: old behaviour (regression, no edit, no commit)" || bad "D26: $out"
# shadow
r="$(mk_repo shadow)"; b0="$(git -C "$r" rev-parse HEAD)"; a0="$(add_commit "$r")"
out="$(run_gate shadow "$r" "$b0" "$a0" OVN_TSC_UNUSED_FIX=shadow)"
echo "$out" | grep -q "TSC-UNUSED-IMPORTS-WOULD-FIX" && echo "$out" | grep -q "TSC-RATCHET-REGRESSION" && [ "$(git -C "$r" rev-parse HEAD)" = "$a0" ] && git -C "$r" diff --quiet HEAD && ok "D27 shadow: would-fix logged, nothing edited, regression still reported" || bad "D27: $out"
# an unused import the commit did NOT add (pre-existing in another file) is not touched
r="$(mk_repo pre)"; ( cd "$r" && printf "import { vi } from 'vitest'\n" > web/src/old.ts && git add -A && git commit -qm old ); b0="$(git -C "$r" rev-parse HEAD)"
a0="$(cd "$r" && echo "export const c = 2;" >> web/src/base.ts && git add -A && git commit -qm item >/dev/null && git rev-parse HEAD)"
echo 1 > "$tmp/bl-pre/testrepo__web.count"
out="$(run_gate pre "$r" "$b0" "$a0")"
grep -q "import { vi }" "$r/web/src/old.ts" && [ "$(git -C "$r" rev-parse HEAD)" = "$a0" ] && ok "D28 an unused import in a file the commit did not touch is left alone" || bad "D28: $out"
# mutants of the gate script
for mm in "default off|OVN_TSC_UNUSED_FIX:-on|OVN_TSC_UNUSED_FIX:-off" "fix never committed|git -C \"\$top\" commit -q -m \"fix(ts)|true -q -m \"fix(ts)" "ratchet not re-run|out=\"\$( timeout 180 \$cmd 2>&1 )\"
            else|out=\"\$out\"
            else"; do
  lab="${mm%%|*}"; rest="${mm#*|}"; old="${rest%%|*}"; new="${rest#*|}"
  cp "$GATE" "$tmp/gate_mut.sh"
  OLD="$old" NEW="$new" "$PY" - "$tmp/gate_mut.sh" <<'PYEOF' || { bad "D29 mutant '$lab' not applicable"; continue; }
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if o not in s: sys.exit(3)
open(p, "w").write(s.replace(o, os.environ["NEW"], 1))
PYEOF
  cp "$SRC/ovn_ts_unused_imports.py" "$tmp/"
  mi=$((${mi:-0}+1)); r="$(mk_repo mut$mi)"; b0="$(git -C "$r" rev-parse HEAD)"; a0="$(add_commit "$r")"   # unique repo per mutant; $tmp is removed by the EXIT trap
  out="$(env OVN_TSC_PREMEASURE=0 OVN_SAFE_TMP_LIB="$HERE/lib_safe_tmp.sh" bash "$tmp/gate_mut.sh" "$r" "$tmp/bl-mut$mi" testrepo "$b0" "$a0" 2>&1)"
  if echo "$out" | grep -q "TSC-RATCHET-OK" && [ "$(git -C "$r" log -1 --format=%s)" = "fix(ts): remove unused imports flagged by tsc (TS6133/TS6192/TS6196)" ]; then bad "D29 mutant SURVIVED: $lab"; else ok "D29 mutant killed: $lab"; fi
done

# ---- review fixes (2026-11-10): CRLF preserved when removing imports; failed commit restores from HEAD (not the index)
crlf_case() {  # crlf_case <gate script> <name> -> rc 0 when CRLF is intact after the autofix (multi-spec edit AND whole-declaration drop)
  local g="$1" nm="$2" rr b a
  rr="$(mk_repo "$nm")"; b="$(git -C "$rr" rev-parse HEAD)"
  ( cd "$rr" && printf "import { describe, vi } from 'vitest'\r\ndescribe('a', () => {})\r\n" > web/src/a.test.ts && git add -A && git commit -qm item )
  a="$(git -C "$rr" rev-parse HEAD)"
  env OVN_TSC_PREMEASURE=0 OVN_SAFE_TMP_LIB="$HERE/lib_safe_tmp.sh" bash "$g" "$rr" "$tmp/bl-$nm" testrepo "$b" "$a" >/dev/null 2>&1
  printf "import { describe } from 'vitest'\r\ndescribe('a', () => {})\r\n" > "$tmp/crlf.expect"
  cmp -s "$tmp/crlf.expect" "$rr/web/src/a.test.ts" || return 1
  # whole declaration dropped (sole specifier) in a CRLF file: the CRLF after it goes too and every other line keeps CRLF
  b="$(git -C "$rr" rev-parse HEAD)"
  ( cd "$rr" && printf "import { vi } from 'vitest'\r\nexport const z = 1;\r\n" > web/src/z.ts && git add -A && git commit -qm item2 )
  a="$(git -C "$rr" rev-parse HEAD)"
  env OVN_TSC_PREMEASURE=0 OVN_SAFE_TMP_LIB="$HERE/lib_safe_tmp.sh" bash "$g" "$rr" "$tmp/bl-$nm" testrepo "$b" "$a" >/dev/null 2>&1
  printf "export const z = 1;\r\n" > "$tmp/crlf.expect"
  cmp -s "$tmp/crlf.expect" "$rr/web/src/z.ts"; local rc=$?
  return $rc
}
mkdir -p "$tmp/gm"; cp "$GATE" "$SRC/ovn_ts_unused_imports.py" "$tmp/gm/"
crlf_case "$tmp/gm/ovn_tsc_gate.sh" crlf && ok "D30 CRLF file: removing an import keeps CRLF (byte-identical to the expected CRLF text), incl. whole-declaration drop" || bad "D30 CRLF not preserved"
# mutant: the old read/write (default newline translation) must FAIL D30
sed -i.bak 's/encoding="utf-8", newline="") as fh:/encoding="utf-8") as fh:/' "$tmp/gm/ovn_ts_unused_imports.py"
cmp -s "$tmp/gm/ovn_ts_unused_imports.py" "$SRC/ovn_ts_unused_imports.py" && bad "D31 mutant not applicable"
if crlf_case "$tmp/gm/ovn_tsc_gate.sh" crlfm; then bad "D31 mutant SURVIVED: translating newlines"; else ok "D31 mutant killed: default newline translation breaks CRLF"; fi
cp "$SRC/ovn_ts_unused_imports.py" "$tmp/gm/"
OLD=$'text[last:last + 2] == "\\r\\n"' NEW='False' "$PY" - "$tmp/gm/ovn_ts_unused_imports.py" <<'PYEOF'
import os, sys
p = sys.argv[1]; s = open(p).read()
assert os.environ["OLD"] in s
open(p, "w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))
PYEOF
if crlf_case "$tmp/gm/ovn_tsc_gate.sh" crlfm2; then bad "D32 mutant SURVIVED: CRLF not swallowed on a dropped declaration"; else ok "D32 mutant killed: a dropped declaration must swallow its CRLF"; fi
cp "$SRC/ovn_ts_unused_imports.py" "$tmp/gm/"
# commit failure (pre-commit hook rejects): files restored from HEAD, index clean
fail_commit_case() {  # fail_commit_case <gate script> <name> -> 0 when the worktree AND index equal HEAD afterwards
  local g="$1" nm="$2" rr b a out
  rr="$(mk_repo "$nm")"; b="$(git -C "$rr" rev-parse HEAD)"; a="$(add_commit "$rr")"
  printf '#!/bin/sh\nexit 1\n' > "$rr/.git/hooks/pre-commit"; chmod +x "$rr/.git/hooks/pre-commit"
  out="$(env OVN_TSC_PREMEASURE=0 OVN_SAFE_TMP_LIB="$HERE/lib_safe_tmp.sh" bash "$g" "$rr" "$tmp/bl-$nm" testrepo "$b" "$a" 2>&1)"
  local rc=1
  if echo "$out" | grep -q "TSC-UNUSED-IMPORTS-SKIP" && git -C "$rr" diff --quiet HEAD && git -C "$rr" diff --cached --quiet && [ "$(git -C "$rr" rev-parse HEAD)" = "$a" ] && grep -q "vi } from" "$rr/web/src/a.test.ts"; then rc=0; fi
  return $rc
}
fail_commit_case "$tmp/gm/ovn_tsc_gate.sh" failc && ok "D33 failed commit after git add: worktree AND index are restored to HEAD (nothing left staged/modified)" || bad "D33 failed commit left the fix staged/modified"
sed -i.bak 's|checkout -q HEAD -- \$fxfiles|checkout -q -- $fxfiles|' "$tmp/gm/ovn_tsc_gate.sh"
grep -q 'checkout -q -- \$fxfiles' "$tmp/gm/ovn_tsc_gate.sh" || bad "D34 mutant not applicable"
if fail_commit_case "$tmp/gm/ovn_tsc_gate.sh" failcm; then bad "D34 mutant SURVIVED: restoring from the index"; else ok "D34 mutant killed: restoring from the index leaves the fix staged"; fi
safe_rm_rf "${tmp:?}/gm"

echo "== B: z3_commit_audit on a real commit range (non-staged commits, shadow only)"
. "$SRC/lib_landing_gates.sh"
ca="$tmp/audit"; mkdir -p "$ca/backend/tests" "$ca/backend/app" "$tmp/st"
( cd "$ca" && git init -q && git config user.email t@t && git config user.name t
  printf 'def sla_met(r, t):\n    return False\n' > backend/app/sla_met.py
  printf 'from app.sla_met import sla_met\n\ndef test_a():\n    assert sla_met([], 0.9) is False\n' > backend/tests/test_sla_met.py
  git add -A && git commit -qm base )
b0="$(git -C "$ca" rev-parse HEAD)"
( cd "$ca" && printf 'def sla_met(r, t):\n    return None\n' > backend/app/sla_met.py && printf 'from app.sla_met import sla_met\n\ndef test_a():\n    assert sla_met([], 0.9) is None\n' > backend/tests/test_sla_met.py && printf 'TITLE = "Heads up: down"\n' > backend/app/notifier.py && git add -A && git commit -qm "fix: x" )
a0="$(git -C "$ca" rev-parse HEAD)"
z3_commit_audit "$ca" "$b0" "$a0" "Update sla_met" "$tmp/st" "audit:commit"; arc=$?
[ "$arc" = 0 ] && ok "B30 returns 0" || bad "B30 rc=$arc"
grep -q '"rule_kind": "expectation-trivial"' "$tmp/st/landing_gates_shadow.log" && grep -q '"token": "Heads up"' "$tmp/st/landing_gates_shadow.log" && ok "B31 the expectation rewrite AND the tone finding are journaled (the two shapes the gate was silent on)" || bad "B31: $(cat "$tmp/st/landing_gates_shadow.log" 2>/dev/null | cut -c1-200)"
grep -q '"mode": "shadow"' "$tmp/st/landing_gates_shadow.log" && grep -q '"kind": "commit"' "$tmp/st/landing_gates_shadow.log" && ok "B32 rows carry mode=shadow, kind=commit" || bad "B32"
rm -f "$tmp/st/landing_gates_shadow.log"; OVN_Z8_COMMIT_AUDIT=off z3_commit_audit "$ca" "$b0" "$a0" "x" "$tmp/st" "l"
[ ! -s "$tmp/st/landing_gates_shadow.log" ] && ok "B33 OVN_Z8_COMMIT_AUDIT=off writes nothing" || bad "B33"
rm -f "$tmp/st/landing_gates_shadow.log"; OVN_Z3_TONE=off OVN_Z3_ASSERT_WEAKEN=off z3_commit_audit "$ca" "$b0" "$a0" "x" "$tmp/st" "l"
! grep -q 'tone-lint\|assert-weaken' "$tmp/st/landing_gates_shadow.log" 2>/dev/null && ok "B34 per-rule off flags are honoured" || bad "B34"
rm -f "$tmp/st/landing_gates_shadow.log"; z3_commit_audit "$ca" "$a0" "$a0" "x" "$tmp/st" "l"; z3_commit_audit "/nonexistent" "$b0" "$a0" "x" "$tmp/st" "l"; z3_commit_audit "$ca" "" "" "x" "$tmp/st" "l"
[ ! -s "$tmp/st/landing_gates_shadow.log" ] && ok "B35 empty range / bad repo / missing shas: no row, no error" || bad "B35"
OVN_Z3_TONE=enforce OVN_Z3_ASSERT_WEAKEN=enforce z3_commit_audit "$ca" "$b0" "$a0" "x" "$tmp/st" "l"; [ -z "${Z3_REFUSE:-}" ] && ok "B36 an enforce flag never makes the commit audit refuse (shadow only)" || bad "B36"
# mutants of the shell glue
for mm in "audit disabled|OVN_Z8_COMMIT_AUDIT:-on|OVN_Z8_COMMIT_AUDIT:-off" "kind label wrong|kind=\"commit\"|kind=\"step\"" "assert flag ignored|\"assert-weaken\":\"OVN_Z3_ENV_ASSERT\"|\"assert-weaken\":\"OVN_X\""; do
  lab="${mm%%|*}"; rest="${mm#*|}"; old="${rest%%|*}"; new="${rest#*|}"
  cp "$SRC/lib_landing_gates.sh" "$tmp/lg_mut.sh"
  OLD="$old" NEW="$new" "$PY" - "$tmp/lg_mut.sh" <<'PYEOF' || { bad "B37 mutant '$lab' not applicable"; continue; }
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if o not in s: sys.exit(3)
open(p, "w").write(s.replace(o, os.environ["NEW"], 1))
PYEOF
  cp "$SRC/lib_landing_gates.sh" "$tmp/lg_orig.sh"; cp "$tmp/lg_mut.sh" "$SRC/lib_landing_gates.sh.mut" 2>/dev/null; rm -f "$SRC/lib_landing_gates.sh.mut"
  mutdir="$tmp/lgm"; mkdir -p "$mutdir"; cp "$SRC/ovn_landing_gates.py" "$SRC/lib_push_bound.sh" "$SRC/lib_helper_timeout.sh" "$mutdir/" 2>/dev/null; cp "$tmp/lg_mut.sh" "$mutdir/lib_landing_gates.sh"
  rm -f "$tmp/st/landing_gates_shadow.log"
  res="$( ( . "$mutdir/lib_landing_gates.sh"; if [ "$lab" = "assert flag ignored" ]; then OVN_Z3_ASSERT_WEAKEN=off z3_commit_audit "$ca" "$b0" "$a0" "x" "$tmp/st" "l"; else z3_commit_audit "$ca" "$b0" "$a0" "x" "$tmp/st" "l"; fi; cat "$tmp/st/landing_gates_shadow.log" 2>/dev/null ) )"
  case "$lab" in
    "audit disabled") [ -z "$res" ] && echo "  ok   B37 mutant killed: $lab" || { echo "  FAIL B37 mutant SURVIVED: $lab"; fail=1; } ;;
    "kind label wrong") echo "$res" | grep -q '"kind": "commit"' && { echo "  FAIL B37 mutant SURVIVED: $lab"; fail=1; } || echo "  ok   B37 mutant killed: $lab" ;;
    *) echo "$res" | grep -q assert-weaken && echo "  ok   B37 mutant killed: $lab" || { echo "  FAIL B37 mutant SURVIVED: $lab"; fail=1; } ;;
  esac
done

echo "== F: ovn_credit_already_satisfied.sh must not credit on a garbage plan token (7199.96, db.example)"
CR="$SRC/ovn_credit_already_satisfied.sh"
cr_run() {  # cr_run <script> [env...] -> prints CREDITED=n ; fixture: a real git repo with the item's file
  local scr="$1"; shift; local d="$tmp/cr"; rm -rf "$d"; mkdir -p "$d/backend/tests"; cd "$d" || return 1
  git init -q; git config user.email t@t; git config user.name t; echo "x = 1" > backend/tests/test_duration_hour_rollover.py
  cat > OVERNIGHT_PROGRESS.md <<'PROG'
## Next Steps
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — assert the duration 7199.96 rolls over into hours; db.example holds the url. VERIFY: `true`. (cat:python; multifile:no)
PROG
  git add -A; git commit -qm base
  printf 'The scout looked at 7199.96 and db.example\nThe code already contains the rollover, no change needed.\n' > aider.log
  env OVN_VERIFY_SHADOW_LOG="$d/shadow.log" "$@" bash "$scr" aider.log OVERNIGHT_PROGRESS.md 2>&1 | tail -1
  cd "$HERE" || true
}
[ "$(cr_run "$CR")" = "CREDITED=0" ] && ok "F10 garbage tokens (7199.96 / db.example) credit nothing" || bad "F10: $(cr_run "$CR")"
[ "$(cr_run "$CR" OVN_PLAN_PATH_STRICT=off)" = "CREDITED=1" ] && ok "F11 with OVN_PLAN_PATH_STRICT=off the OLD behaviour is restored (the garbage token credits the item): the test fails on the old code" || bad "F11: $(cr_run "$CR" OVN_PLAN_PATH_STRICT=off)"
cp "$CR" "$tmp/cr_mut.sh"; cp "$SRC/ovn_plan_path_ok.py" "$tmp/"; cp "$SRC/ovn_path_gate.py" "$tmp/" 2>/dev/null
sed -i.bak 's|if \[ -f "\$_ppo" \] \&\& ! python3 "\$_ppo" "\$PWD" "\$f" 2>/dev/null; then continue; fi|:|' "$tmp/cr_mut.sh"
for x in lib_verify_clause.sh ovn_verify_safe.py ovn_path_gate.py; do [ -f "$SRC/$x" ] && cp "$SRC/$x" "$tmp/"; done
[ "$(cr_run "$tmp/cr_mut.sh")" = "CREDITED=1" ] && ok "F12 mutant (plan-path check removed from the credit script) credits the garbage item: caught" || bad "F12 mutant survived: $(cr_run "$tmp/cr_mut.sh")"
cd "$HERE" || true

echo "== wiring + pinned defaults"
RO="$ROOT/run_overnight.sh"; SR="$ROOT/ovn_stage_runner.sh"
grep -q 'z3_commit_audit "\$PWD" "\$BEFORE_SHA" "\$AFTER_SHA"' "$RO" && ok "W1 run_overnight.sh calls z3_commit_audit on BEFORE_SHA..AFTER_SHA" || bad "W1"
grep -q 'source "\$SCRIPT_DIR/scripts/lib_landing_gates.sh"' "$RO" && ok "W2 run_overnight.sh sources lib_landing_gates.sh" || bad "W2"
grep -q 'AFTER_SHA="\$(git rev-parse HEAD)"   # 2026-11-10 (Z8b-D)' "$RO" && ok "W3 run_overnight.sh refreshes AFTER_SHA after the tsc gate (the autofix commit)" || bad "W3"
grep -q 'ovn_plan_path_ok.py" "\$PWD" "\$_df"' "$RO" && ok "W4 the scout ALREADY-DONE credit loop filters garbage plan tokens" || bad "W4"
grep -q 'ovn_plan_path_ok.py' "$SRC/ovn_credit_already_satisfied.sh" && ok "W5 the any-verdict already-satisfied credit filters garbage plan tokens" || bad "W5"
grep -q 'OVN_STAGE_TIMEOUT_PARK:-shadow' "$SR" && ok "W6 OVN_STAGE_TIMEOUT_PARK stays SHADOW (item-level precision 57-64% < 80%)" || bad "W6"
grep -q 'OVN_BUILD_BREAK_PARK:-shadow' "$SRC/lib_build_break_park.sh" && ok "W7 OVN_BUILD_BREAK_PARK stays SHADOW (precision 50-75% < 80%)" || bad "W7"
grep -q 'OVN_STAGE_EMPTY_WHOLE:-shadow' "$SR" && ! grep -q '82 of 82' "$SR" && grep -q '15 of 45' "$SR" && ok "W8 OVN_STAGE_EMPTY_WHOLE defaults SHADOW (review: measured 33% = 15/45, whole has no outcome data; the false 82-of-82 claim is gone)" || bad "W8"
grep -q 'OVN_STAGE_DEP_NOEDIT:-off' "$SR" && grep -q 'stage_step_noedit_only "\$i"' "$SR" && grep -q '0.0 == 0 in jq' "$SR" && ok "W9 the dependency no-edit rule is wired but defaults OFF (documents the jq 0.0 aliasing)" || bad "W9"
# stage_step_noedit_only behaves: no-edit-only => 0; a scope-violation / pass / no rows => 1
eval "$(sed -n '/^stage_step_noedit_only(){/,/^}/p' "$SR")"
if command -v jq >/dev/null 2>&1; then
  SLOG="$tmp/slog.jsonl"
  printf '%s\n' '{"step":0,"attempt":1,"verdict":"fail","fail_reason":"no-edit"}' '{"step":0,"attempt":2,"verdict":"fail","fail_reason":"no-edit"}' '{"step":1,"attempt":1,"verdict":"fail","fail_reason":"scope-violation"}' '{"step":2,"attempt":1,"verdict":"fail","fail_reason":"no-edit"}' '{"step":2,"attempt":2,"verdict":"pass"}' '{"step":3,"attempt":1,"verdict":"fail","fail_reason":"no-edit"}' '{"step":3,"attempt":2,"verdict":"fail","fail_reason":"empty-file"}' > "$SLOG"
  OVN_STAGE_DEP_NOEDIT=on
  stage_step_noedit_only 0 && ok "W10 all attempts no-edit -> satisfied" || bad "W10"
  ! stage_step_noedit_only 1 && ! stage_step_noedit_only 2 && ! stage_step_noedit_only 3 && ! stage_step_noedit_only 9 && ok "W11 scope-violation / a pass / a mix with empty-file / no rows -> not satisfied" || bad "W11"
  OVN_STAGE_DEP_NOEDIT=off; ! stage_step_noedit_only 0 && ok "W12 OVN_STAGE_DEP_NOEDIT=off -> never satisfied" || bad "W12"
  unset OVN_STAGE_DEP_NOEDIT; ! stage_step_noedit_only 0 && ok "W12b UNSET (default) -> never satisfied (even all-no-edit)" || bad "W12b"
else echo "  (W10-W12 skipped: no jq)"; fi
[ "$fail" = 0 ] || rc=1
exit $rc
