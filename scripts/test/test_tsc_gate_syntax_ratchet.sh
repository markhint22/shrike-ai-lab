#!/usr/bin/env bash
# P5 (2026-10-27): ovn_tsc_gate.sh must hard-fail TS1xxx syntax errors and never ratchet down while
# syntax errors exist (tsc drops all semantic errors on a syntax error: billwatch 67 -> 3). Also the
# shadow collected-test check. Uses a FAKE vue-tsc/vitest; no TypeScript toolchain needed.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../ovn_tsc_gate.sh"; [ -f "$GATE" ] || GATE="$HERE/ovn_tsc_gate.sh"
[ -f "$GATE" ] || { echo "  ❌ ovn_tsc_gate.sh not found"; exit 1; }
command -v git >/dev/null || { echo "  SKIP (loud): git absent"; exit 0; }
rc=0; fail(){ echo "  ❌ $1"; rc=1; }; ok(){ echo "  ✅ $1"; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export FAKE_OUT_FILE="$tmp/fakeout"
bl="$tmp/baselines"; mkdir -p "$bl"
repo="$tmp/repo"; wd="$repo/web"; mkdir -p "$wd/src" "$wd/node_modules/.bin"
cat > "$wd/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
cat "$FAKE_OUT_FILE" 2>/dev/null; [ -s "$FAKE_OUT_FILE" ] && exit 1 || exit 0
FAKE
cat > "$wd/node_modules/.bin/vitest" <<'FAKE'
#!/usr/bin/env bash
cat "$FAKE_VITEST_LIST" 2>/dev/null; exit 0
FAKE
chmod +x "$wd/node_modules/.bin/vue-tsc" "$wd/node_modules/.bin/vitest"
export FAKE_VITEST_LIST="$tmp/vlist"; : > "$FAKE_VITEST_LIST"
echo '{"compilerOptions":{"noEmit":true},"include":["src"]}' > "$wd/tsconfig.json"
sem(){ local i=1; while [ "$i" -le "$1" ]; do echo "src/a.ts($i,1): error TS2322: semantic $i"; i=$((i+1)); done; }
cd "$repo" && git init -q && git config user.email t@t && git config user.name t
echo "export const a = 1;" > "$wd/src/app.ts"; git add -A; git commit -q -m init
tsc_commit(){ echo "export const a = $RANDOM;" > "$wd/src/app.ts"; git add -A >/dev/null; git commit -q -m c; git rev-parse HEAD; }
run(){ bash "$GATE" "$repo" "$bl" r "$1" "$2" 2>&1; }
P=$(git rev-parse HEAD)

sem 67 > "$FAKE_OUT_FILE"; C1=$(tsc_commit); run "$P" "$C1" | grep -c SEED >/dev/null
[ "$(cat "$bl/r__web.count")" = 67 ] && ok "seeded baseline 67" || fail "seed"

# syntax error drops semantic errors: 67 -> 1 (TS1109). Must be REGRESSION, baseline byte-identical.
cp "$bl/r__web.count" "$tmp/before"
echo "src/a.ts(3,1): error TS1109: Expression expected." > "$FAKE_OUT_FILE"; C2=$(tsc_commit)
OUT="$(run "$C1" "$C2")"
grep -q "TSC-RATCHET-REGRESSION" <<<"$OUT" && ok "TS1109 -> REGRESSION" || fail "expected REGRESSION: $OUT"
cmp -s "$bl/r__web.count" "$tmp/before" && ok "baseline byte-identical after syntax regression" || fail "baseline changed"
ls "$bl"/r__web.count.syn >/dev/null 2>&1 && fail "syn sidecar must not be written on regression" || ok "no sidecar written"

# kill switch restores old behaviour (IMPROVED, ratchet down)
OUT="$(OVN_TSC_SYNTAX_HARDFAIL=0 run "$C1" "$C2")"
grep -q "TSC-RATCHET-IMPROVED" <<<"$OUT" && ok "HARDFAIL=0 -> old IMPROVED behaviour" || fail "switch: $OUT"
echo 67 > "$bl/r__web.count"

# clean improvement still ratchets down
sem 60 > "$FAKE_OUT_FILE"; C3=$(tsc_commit); OUT="$(run "$C1" "$C3")"
grep -q "TSC-RATCHET-IMPROVED" <<<"$OUT" && [ "$(cat "$bl/r__web.count")" = 60 ] && ok "clean improvement ratchets 67 -> 60" || fail "improve: $OUT"

# pre-existing syntax error (sidecar=1): same syn count is not a regression, and count drop does NOT ratchet
echo 1 > "$bl/r__web.count.syn"
{ sem 5; echo "src/a.ts(3,1): error TS1005: ';' expected."; } > "$FAKE_OUT_FILE"; C4=$(tsc_commit)
OUT="$(run "$C3" "$C4")"
! grep -q REGRESSION <<<"$OUT" && [ "$(cat "$bl/r__web.count")" = 60 ] && ok "pre-existing syntax: no regression, no ratchet-down (60 kept)" || fail "preexisting: $OUT"

# a second syntax error beyond the sidecar -> REGRESSION
{ echo "src/a.ts(3,1): error TS1005: x"; echo "src/a.ts(4,1): error TS1128: y"; } > "$FAKE_OUT_FILE"; C5=$(tsc_commit)
OUT="$(run "$C4" "$C5")"; grep -q "SYNTAX errors 1 -> 2" <<<"$OUT" && ok "extra syntax error beyond baseline -> REGRESSION" || fail "extra syn: $OUT"

# checker (semantic) TS1xxx codes with NO sidecar must not count as syntax errors (billwatch TS1117 case)
rm -f "$bl/r__web.count.syn"; echo 60 > "$bl/r__web.count"
{ sem 57; echo "src/a.test.ts(32,5): error TS1117: An object literal cannot have multiple properties with the same name."; echo "src/b.ts(1,1): error TS1259: x"; echo "src/c.ts(1,1): error TS1484: y"; } > "$FAKE_OUT_FILE"; C7=$(tsc_commit)
OUT="$(run "$C5" "$C7")"
! grep -q "REGRESSION" <<<"$OUT" && ok "pre-existing TS1117/1259/1484, no sidecar: no SYNTAX regression" || fail "checker TS1xxx misfire: $OUT"

# shadow collected check
: > "$FAKE_OUT_FILE"; echo 60 > "$bl/r__web.count"; rm -f "$bl/r__web.count.syn"
echo "export {}" > "$wd/src/new.test.ts"; git add -A >/dev/null; git commit -q -m t; C6=$(git rev-parse HEAD)
echo 60 > "$FAKE_OUT_FILE"; sem 60 > "$FAKE_OUT_FILE"
OUT="$(run "$C5" "$C6")"; ! grep -q "TEST-COLLECTED" <<<"$OUT" && ok "collected check off by default" || fail "should be off: $OUT"
OUT="$(OVN_TEST_COLLECTED_CHECK=shadow run "$C5" "$C6")"
grep -q "TEST-COLLECTED-SHADOW would-flag.*new.test.ts" <<<"$OUT" && ok "shadow: unlisted new test -> would-flag" || fail "shadow flag: $OUT"
grep -q "TSC-RATCHET-REGRESSION" <<<"$OUT" && fail "shadow must not alter verdict" || ok "shadow does not change verdict"
echo "src/new.test.ts" > "$FAKE_VITEST_LIST"
OUT="$(OVN_TEST_COLLECTED_CHECK=shadow run "$C5" "$C6")"; ! grep -q "would-flag" <<<"$OUT" && ok "listed test -> no flag" || fail "listed: $OUT"
exit "$rc"
