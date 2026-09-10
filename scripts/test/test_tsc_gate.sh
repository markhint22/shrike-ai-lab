#!/usr/bin/env bash
# Regression test for ovn_tsc_gate.sh (the TypeScript type-error ratchet).
# Drives the gate with a FAKE vue-tsc whose error count is controllable, so the ratchet
# logic (seed / ok / improved / regression / skip) is verified deterministically without a
# real TypeScript toolchain.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../ovn_tsc_gate.sh"; [ -f "$GATE" ] || GATE="$HERE/ovn_tsc_gate.sh"
[ -f "$GATE" ] || { echo "  ❌ ovn_tsc_gate.sh not found"; exit 1; }
rc=0; fail(){ echo "  ❌ $1"; rc=1; }; ok(){ echo "  ✅ $1"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export FAKE_ERR_COUNT_FILE="$tmp/errcount"
bl="$tmp/baselines"; mkdir -p "$bl"
repo="$tmp/repo"; wd="$repo/web"; mkdir -p "$wd/src" "$wd/node_modules/.bin"

# fake vue-tsc: prints N "error TS" lines from $FAKE_ERR_COUNT_FILE
cat > "$wd/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
n=$(cat "$FAKE_ERR_COUNT_FILE" 2>/dev/null || echo 0)
i=1; while [ "$i" -le "$n" ]; do echo "src/app.ts($i,1): error TS2322: fake type error $i"; i=$((i+1)); done
[ "$n" -gt 0 ] && exit 1 || exit 0
FAKE
chmod +x "$wd/node_modules/.bin/vue-tsc"
echo '{"compilerOptions":{"noEmit":true},"include":["src"]}' > "$wd/tsconfig.json"

cd "$repo"
git init -q; git config user.email t@t; git config user.name t
echo "export const a = 1;" > "$wd/src/app.ts"
git add -A; git commit -q -m init
BASE_SHA=$(git rev-parse HEAD)

# make a TS-touching commit; echoes new SHA
ts_commit(){ echo "export const a = $RANDOM;" > "$wd/src/app.ts"; git add -A >/dev/null; git commit -q -m "ts change"; git rev-parse HEAD; }
# make a non-TS commit
nonts_commit(){ echo "note $RANDOM" >> "$repo/README.md"; git add -A >/dev/null; git commit -q -m "doc"; git rev-parse HEAD; }

run(){ bash "$GATE" "$repo" "$bl" testrepo "$1" "$2" 2>&1; }

# --- Case SKIP: commit touches no TS files ---
A=$(nonts_commit); OUT="$(run "$BASE_SHA" "$A")"
echo "$OUT" | grep -q "TSC-RATCHET-SKIP" && ok "non-TS commit -> SKIP" || fail "non-TS commit should SKIP: $OUT"

# --- Case SEED: no baseline yet, fake=3 -> seeds baseline=3, no regression ---
echo 3 > "$FAKE_ERR_COUNT_FILE"; B=$(ts_commit); OUT="$(run "$A" "$B")"
echo "$OUT" | grep -q "TSC-RATCHET-SEED" && ok "first TS commit -> SEED" || fail "expected SEED: $OUT"
[ "$(cat "$bl/testrepo__web.count" 2>/dev/null)" = 3 ] && ok "baseline seeded = 3" || fail "baseline not 3"

# --- Case OK: baseline=3, fake=3 -> held ---
echo 3 > "$FAKE_ERR_COUNT_FILE"; C=$(ts_commit); OUT="$(run "$B" "$C")"
echo "$OUT" | grep -q "TSC-RATCHET-OK" && ok "same count -> OK (held)" || fail "expected OK: $OUT"

# --- Case REGRESSION: baseline=3, fake=5 -> regression, baseline unchanged ---
echo 5 > "$FAKE_ERR_COUNT_FILE"; D=$(ts_commit); OUT="$(run "$C" "$D")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "count up -> REGRESSION" || fail "expected REGRESSION: $OUT"
[ "$(cat "$bl/testrepo__web.count")" = 3 ] && ok "baseline NOT raised on regression (still 3)" || fail "baseline should stay 3"

# --- Case IMPROVED: baseline=3, fake=1 -> improved, baseline ratchets to 1 ---
echo 1 > "$FAKE_ERR_COUNT_FILE"; E=$(ts_commit); OUT="$(run "$D" "$E")"
echo "$OUT" | grep -q "TSC-RATCHET-IMPROVED" && ok "count down -> IMPROVED" || fail "expected IMPROVED: $OUT"
[ "$(cat "$bl/testrepo__web.count")" = 1 ] && ok "baseline ratcheted down to 1" || fail "baseline should be 1"

# --- Case REGRESSION vs ratcheted baseline: baseline=1, fake=2 -> regression ---
echo 2 > "$FAKE_ERR_COUNT_FILE"; F=$(ts_commit); OUT="$(run "$E" "$F")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "above ratcheted baseline -> REGRESSION" || fail "expected REGRESSION vs ratchet: $OUT"

[ $rc -eq 0 ] && echo "  test_tsc_gate: PASS" || echo "  test_tsc_gate: FAIL"
exit $rc
