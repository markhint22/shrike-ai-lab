#!/usr/bin/env bash
# Y3 (2026-11-04): ovn_tsc_gate.sh re-measures the PARENT tree before reverting. Fake vue-tsc is TREE-AWARE: it prints one
# "error TS2322" per line of src/errs.txt of the tree it runs in, so the parent (git archive copy) and the commit differ for real.
# Cases: stale low baseline + commit adds none -> REBASED (not reverted); commit adds errors vs parent -> REGRESSION;
# premeasure off -> old static revert; unmeasurable parent -> still REGRESSION; syntax baseline stale -> rebased; real syntax add -> REGRESSION.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${TSC_GATE_UNDER_TEST:-$HERE/../ovn_tsc_gate.sh}"; [ -f "$GATE" ] || { echo "  FAIL: gate not found"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0; fail(){ echo "  FAIL $1"; rc=1; }; ok(){ echo "  ok   $1"; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/tmpdir"; mkdir -p "$TMPDIR"
bl="$tmp/bl"; mkdir -p "$bl"; repo="$tmp/repo"; wd="$repo/web"; mkdir -p "$wd/src" "$wd/node_modules/.bin"
cat > "$wd/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
[ -f src/errs.txt ] || exit 0
cat src/errs.txt | while IFS= read -r l; do [ -n "$l" ] && echo "src/app.ts(1,1): error $l: fake"; done
exit 1
FAKE
chmod +x "$wd/node_modules/.bin/vue-tsc"
echo '{"compilerOptions":{"noEmit":true}}' > "$wd/tsconfig.json"
cd "$repo"; git init -q; git config user.email t@t; git config user.name t
printf 'node_modules\n' > .gitignore
errs(){ : > "$wd/src/errs.txt"; local n="$1" i=1 k="${2:-TS2322}"; while [ "$i" -le "$n" ]; do echo "$k" >> "$wd/src/errs.txt"; i=$((i+1)); done; }
errs 13; echo "export const a=1;" > "$wd/src/app.ts"; git add -A; git commit -q -m init; P0=$(git rev-parse HEAD)
commit(){ echo "export const a=$RANDOM;" > "$wd/src/app.ts"; git add -A >/dev/null; git commit -q -m c; git rev-parse HEAD; }
run(){ bash "$GATE" "$repo" "$bl" "repos/testrepo" "$1" "$2" 2>&1; }
bf="$bl/testrepo__web.count"

# 1. the gitlark incident: stored baseline 2, parent has 13, commit does not add any (13) -> REBASED, not REGRESSION, baseline = 13
echo 2 > "$bf"; C1=$(commit); OUT="$(run "$P0" "$C1")"
echo "$OUT" | grep -q "TSC-RATCHET-REBASED" && ! echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "stale baseline 2, parent 13, commit adds none -> REBASED (kept)" || fail "expected REBASED: $OUT"
[ "$(cat "$bf")" = 13 ] && ok "baseline re-seeded to 13" || fail "baseline should be 13, got $(cat "$bf")"
echo "$OUT" | grep -q "TSC-RATCHET-OK\|REBASED" && ok "verdict printed" || fail "no verdict"
# 2. next commit, baseline now fresh, adds 2 errors vs parent -> REGRESSION, baseline untouched
errs 15; C2=$(commit); OUT="$(run "$C1" "$C2")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "commit adding 2 errors -> REGRESSION" || fail "expected REGRESSION: $OUT"
[ "$(cat "$bf")" = 13 ] && ok "baseline unchanged on regression" || fail "baseline moved"
# 3. stale baseline 2, parent 13, commit adds one (14) -> still REGRESSION (adds vs own parent), baseline untouched
git reset -q --hard "$C1"; echo 2 > "$bf"; errs 14; C3=$(commit); OUT="$(run "$C1" "$C3")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "stale baseline but commit adds one vs parent -> REGRESSION" || fail "expected REGRESSION: $OUT"
echo "$OUT" | grep -q "parent tree measured 13" && ok "regression message names the parent measurement" || fail "no parent measurement in message"
[ "$(cat "$bf")" = 2 ] && ok "stale baseline not rewritten on real regression" || fail "baseline rewritten"
# 4. rollback switch: OVN_TSC_PREMEASURE=0 restores the static behaviour (stale baseline -> revert)
git reset -q --hard "$C1"; echo 2 > "$bf"; errs 13; C4=$(commit); OUT="$(OVN_TSC_PREMEASURE=0 run "$C1" "$C4")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "OVN_TSC_PREMEASURE=0 -> old static REGRESSION" || fail "expected static REGRESSION: $OUT"
# 5. parent sha unresolvable -> fail-safe: static behaviour, REGRESSION
echo 2 > "$bf"; OUT="$(run deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$C4" 2>&1)"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION\|SKIP" && ! echo "$OUT" | grep -q REBASED && ok "unmeasurable parent -> no rebase (fail-safe)" || fail "expected fail-safe: $OUT"
# 6. clean parent (0 errors), baseline 0, commit adds 1 -> REGRESSION (empty parent output must count as 0, not as unmeasurable)
git reset -q --hard "$C1"; errs 0; git add -A; git commit -q -m clean; C6a=$(git rev-parse HEAD); echo 0 > "$bf"; rm -f "$bf.syn"
errs 1; C6=$(commit); OUT="$(run "$C6a" "$C6")"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "0 -> 1 on a clean parent -> REGRESSION" || fail "expected REGRESSION: $OUT"
# 7. stale syntax baseline: syn sidecar 0, parent already has 1 syntax error, commit keeps 1 -> REBASED syntax, no revert
git reset -q --hard "$C6a"; printf 'TS2322\nTS2322\nTS1005\n' > "$wd/src/errs.txt"; git add -A; git commit -q -m syn; S0=$(git rev-parse HEAD)
echo 3 > "$bf"; rm -f "$bf.syn"; echo "export const b=1;" >> "$wd/src/app.ts"; git add -A; git commit -q -m s1; S1=$(git rev-parse HEAD)
OUT="$(run "$S0" "$S1")"
echo "$OUT" | grep -q "syntax baseline 0 is stale" && ! echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ok "stale syntax baseline re-seeded, commit kept" || fail "expected syntax rebase: $OUT"
[ "$(cat "$bf.syn")" = 1 ] && ok "syntax sidecar = 1" || fail "syn sidecar wrong"
# 8. commit adds a NEW syntax error vs parent -> hard REGRESSION
printf 'TS2322\nTS2322\nTS1005\nTS1109\n' > "$wd/src/errs.txt"; echo "export const c=1;" >> "$wd/src/app.ts"; git add -A; git commit -q -m s2; S2=$(git rev-parse HEAD)
OUT="$(run "$S1" "$S2")"
echo "$OUT" | grep -q "SYNTAX errors 1 -> 2" && ok "new syntax error vs parent -> SYNTAX REGRESSION" || fail "expected SYNTAX REGRESSION: $OUT"
# 9. the private archive dir is cleaned up
ls "$TMPDIR" | grep -q ovn_tsc_pre && fail "premeasure temp dir leaked" || ok "no leaked temp dirs"
# 10. the live checkout was not touched by the premeasure
[ -z "$(git status --porcelain)" ] && ok "live tree clean after gate" || fail "live tree dirtied: $(git status --porcelain)"
[ "$rc" = 0 ] && echo "test_tsc_gate_premeasure: PASS" || echo "test_tsc_gate_premeasure: FAIL"
exit $rc
