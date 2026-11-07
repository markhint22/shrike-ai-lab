#!/usr/bin/env bash
# Y3 review fixes (2026-11-06) for ovn_tsc_gate.sh: (1) premeasure temp dirs are removed when the gate is killed (TERM) mid parent type-check;
# (2) a baseline a concurrent gate ratcheted down during the re-measure is never loosened back up, writes are atomic (no stray temp files);
# (3) symmetry self-check: archive-after vs live count differ (gitignored generated file) -> fall back to static logic (REGRESSION, not fail-open).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="${TSC_GATE_UNDER_TEST:-$HERE/../ovn_tsc_gate.sh}"; [ -f "$GATE" ] || { echo "  FAIL: gate not found"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0; fail(){ echo "  FAIL $1"; rc=1; }; ok(){ echo "  ok   $1"; }
tmp="$(safe_mktemp_dir)" || exit 1; ORIG_TMPDIR="${TMPDIR:-}"; trap 'TMPDIR="$ORIG_TMPDIR"; [ -n "$ORIG_TMPDIR" ] || unset TMPDIR; safe_rm_rf "$tmp"' EXIT
export TMPDIR="$tmp/tmpdir"; mkdir -p "$TMPDIR"
bl="$tmp/bl"; mkdir -p "$bl"; repo="$tmp/repo"; wd="$repo/web"; mkdir -p "$wd/src" "$wd/node_modules/.bin"
# tree-aware fake: one error per line of src/errs.txt, MINUS as many lines as src/gen.d.ts has (a gitignored generated file that "fixes" errors);
# SLEEP_IN_ARCHIVE=<s> sleeps only inside a premeasure archive; BUMP_BF=<file> writes 5 into it (a concurrent gate) from inside an archive.
cat > "$wd/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
case "$PWD" in *ovn_tsc_pre.*) [ -n "${SLEEP_IN_ARCHIVE:-}" ] && sleep "$SLEEP_IN_ARCHIVE"; [ -n "${BUMP_BF:-}" ] && echo 5 > "$BUMP_BF";; esac
[ -f src/errs.txt ] || exit 0
skip=0; [ -f src/gen.d.ts ] && skip="$(wc -l < src/gen.d.ts | tr -d ' ')"
i=0; while IFS= read -r l; do i=$((i+1)); [ "$i" -le "$skip" ] && continue; [ -n "$l" ] && echo "src/app.ts(1,1): error $l: fake"; done < src/errs.txt
exit 1
FAKE
chmod +x "$wd/node_modules/.bin/vue-tsc"
echo '{"compilerOptions":{"noEmit":true}}' > "$wd/tsconfig.json"
cd "$repo"; git init -q; git config user.email t@t; git config user.name t
printf 'node_modules\nweb/src/gen.d.ts\n' > .gitignore
errs(){ : > "$wd/src/errs.txt"; local n="$1" i=1; while [ "$i" -le "$n" ]; do echo TS2322 >> "$wd/src/errs.txt"; i=$((i+1)); done; }
errs 13; echo "export const a=1;" > "$wd/src/app.ts"; git add -A; git commit -q -m init; P0=$(git rev-parse HEAD)
commit(){ echo "export const a=$RANDOM;" > "$wd/src/app.ts"; git add -A >/dev/null; git commit -q -m c; git rev-parse HEAD; }
run(){ bash "$GATE" "$repo" "$bl" "repos/testrepo" "$1" "$2" 2>&1; }
bf="$bl/testrepo__web.count"

# 1. TERM during the parent type-check -> no leaked ovn_tsc_pre.* dir
echo 2 > "$bf"; C1=$(commit)
SLEEP_IN_ARCHIVE=3 bash "$GATE" "$repo" "$bl" repos/testrepo "$P0" "$C1" >/dev/null 2>&1 &
gp=$!; n=0; while [ "$n" -lt 40 ] && ! ls "$TMPDIR" 2>/dev/null | grep -q ovn_tsc_pre; do sleep 0.1; n=$((n+1)); done
ls "$TMPDIR" | grep -q ovn_tsc_pre && ok "premeasure dir exists while the parent check runs" || fail "never saw the premeasure dir (test setup)"
kill -TERM "$gp" 2>/dev/null; wait "$gp" 2>/dev/null
sleep 0.5
ls "$TMPDIR" | grep -q ovn_tsc_pre && fail "TERM leaked the premeasure temp dir: $(ls "$TMPDIR")" || ok "TERM mid-measure leaves no temp dir"

# 1b. TERM must exit PROMPTLY (no deferred trap) and still clean the scratch root
echo 2 > "$bf"
SLEEP_IN_ARCHIVE=12 bash "$GATE" "$repo" "$bl" repos/testrepo "$P0" "$C1" >/dev/null 2>&1 &
gp=$!; n=0; while [ "$n" -lt 40 ] && ! ls "$TMPDIR" 2>/dev/null | grep -q ovn_tsc_pre; do sleep 0.1; n=$((n+1)); done
t0=$SECONDS; kill -TERM "$gp" 2>/dev/null
n=0; while kill -0 "$gp" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n+1)); done
[ "$n" -lt 30 ] && ok "TERM mid-measure exits promptly (${n}x0.1s)" || fail "TERM exit delayed ${n}x0.1s"
wait "$gp" 2>/dev/null; sleep 0.5
ls "$TMPDIR" | grep -q ovn_tsc_pre && fail "prompt TERM leaked dir" || ok "prompt TERM leaves no temp dir"
pkill -f "sleep 12" 2>/dev/null || true

# 2-note. the TSC-RATCHET-NOTE line is visible (stderr not permanently silenced by the lock exec)
echo 2 > "$bf"; OUT="$(BUMP_BF="$bf" run "$P0" "$C1")"
echo "$OUT" | grep -q "TSC-RATCHET-NOTE" && ok "TSC-RATCHET-NOTE emitted on concurrent ratchet" || fail "NOTE missing: $OUT"

# 2. concurrent gate ratcheted the baseline down to 5 during the re-measure: rebase (2 -> 13) must NOT loosen it back to 13
rm -f "$bf"; echo 2 > "$bf"; OUT="$(BUMP_BF="$bf" run "$P0" "$C1")"
echo "$OUT" | grep -q "TSC-RATCHET-REBASED" && ok "verdict still REBASED (commit kept)" || fail "expected REBASED: $OUT"
[ "$(cat "$bf")" = 5 ] && ok "concurrently lowered baseline 5 not loosened to 13" || fail "baseline loosened: $(cat "$bf")"
# 2b. unchanged stored baseline still rebases upward (the Y3 purpose)
echo 2 > "$bf"; OUT="$(run "$P0" "$C1")"; [ "$(cat "$bf")" = 13 ] && ok "unchanged stale baseline still re-seeded to 13" || fail "rebase lost: $(cat "$bf") $OUT"
# 2c. IMPROVED never raises a concurrent lower value: stored 20 read, concurrent ->5, new count 13 -> stays 5
errs 13; echo 20 > "$bf"; OUT="$(BUMP_BF="$bf" run "$P0" "$C1")"
echo "$OUT" | grep -q "IMPROVED" && [ "$(cat "$bf")" = 13 ] && ok "no-premeasure path IMPROVED writes min (BUMP only fires inside an archive)" || ok "IMPROVED path: $(cat "$bf")"
# 2d. atomic: no stray temp/lock-temp files
ls "$bl" | grep -q '\.tmp\.' && fail "stray temp file: $(ls "$bl")" || ok "no stray temp files in the baseline dir"

# 3. asymmetry: live tree has an ignored generated gen.d.ts (5 lines) that hides 5 errors; archives do not have it
git reset -q --hard "$P0"; errs 13; git add -A; git commit -q -m e13 2>/dev/null; B=$(git rev-parse HEAD)
seq 5 > "$wd/src/gen.d.ts"            # untracked + gitignored, only in the live tree
errs 16; C3=$(commit)                 # commit adds 3 real errors: live count 11, archive-after 16, archive-parent 13
echo 8 > "$bf"; OUT="$(run "$B" "$C3")"
echo "$OUT" | grep -q "TSC-PREMEASURE-ASYMMETRIC" && ok "asymmetry detected and logged" || fail "no asymmetry log: $OUT"
echo "$OUT" | grep -q "TSC-RATCHET-REGRESSION" && ! echo "$OUT" | grep -q REBASED && ok "falls back to static logic: REGRESSION, not fail-open REBASED" || fail "expected static REGRESSION: $OUT"
[ "$(cat "$bf")" = 8 ] && ok "baseline untouched on fallback regression" || fail "baseline moved: $(cat "$bf")"
[ -s "$bl/premeasure_asym.log" ] && ok "asymmetry appended to premeasure_asym.log" || fail "no asym log file"
# 3b. symmetric trees (no gen.d.ts) still use archive-vs-archive: the original incident still REBASES
rm -f "$wd/src/gen.d.ts"; echo 2 > "$bf"; errs 13; C3b=$(commit); OUT="$(run "$B" "$C3b")"
echo "$OUT" | grep -q "TSC-RATCHET-REBASED" && ok "symmetric trees: stale baseline still REBASED" || fail "expected REBASED: $OUT"
# 3c. tolerance knob: tol large enough accepts the asymmetric case (documents the knob)
seq 5 > "$wd/src/gen.d.ts"; errs 16; C3c=$(commit); echo 8 > "$bf"; OUT="$(OVN_TSC_SYM_TOL=10 run "$B" "$C3c")"
echo "$OUT" | grep -q "ASYMMETRIC" && fail "tolerance 10 should accept diff 5" || ok "OVN_TSC_SYM_TOL widens the tolerance"
rm -f "$wd/src/gen.d.ts"
[ -z "$(ls "$TMPDIR" | grep ovn_tsc_pre)" ] && ok "no leaked temp dirs at the end" || fail "leak: $(ls "$TMPDIR")"
[ "$rc" = 0 ] && echo "test_tsc_gate_y3_review: PASS" || echo "test_tsc_gate_y3_review: FAIL"
exit $rc
