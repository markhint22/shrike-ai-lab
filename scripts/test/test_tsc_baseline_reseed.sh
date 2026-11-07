#!/usr/bin/env bash
# Y3 (2026-11-04): ops/tsc_baseline_reseed.sh - dry-run by default, --apply writes <repo>__<dir>.count with a backup, never touches the live clone,
# refuses to seed from a tree with syntax errors. Hermetic: fake clones + tree-aware fake vue-tsc (one error per line of src/errs.txt).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${RESEED_UNDER_TEST:-$HERE/../../ops/tsc_baseline_reseed.sh}"; [ -f "$S" ] || { echo "  FAIL: script not found"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0; fail(){ echo "  FAIL $1"; rc=1; }; ok(){ echo "  ok   $1"; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp/tmpdir"; mkdir -p "$TMPDIR"
qd="$tmp/q"; bd="$qd/state/tsc_baseline"; mkdir -p "$bd"
mk(){ # repo dir nerrs nsyn
  local R="$qd/repos/$1" d="$2" i
  mkdir -p "$R/$d/src" "$R/$d/node_modules/.bin"
  cat > "$R/$d/node_modules/.bin/vue-tsc" <<'FAKE'
#!/usr/bin/env bash
[ -f src/errs.txt ] || exit 0
while IFS= read -r l; do [ -n "$l" ] && echo "src/a.ts(1,1): error $l: fake"; done < src/errs.txt
exit 1
FAKE
  chmod +x "$R/$d/node_modules/.bin/vue-tsc"
  : > "$R/$d/src/errs.txt"; i=0; while [ $i -lt "$3" ]; do echo TS2322 >> "$R/$d/src/errs.txt"; i=$((i+1)); done
  i=0; while [ $i -lt "$4" ]; do echo TS1005 >> "$R/$d/src/errs.txt"; i=$((i+1)); done
  echo "node_modules" > "$R/.gitignore"
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -q -m i )
}
mk gitlark web 13 0; mk billwatch billwatch-web 83 0; mk iptv_apps iptv-web 0 0
echo 2 > "$bd/gitlark__web.count"; echo 2 > "$bd/gitlark__web.count.syn"; echo 83 > "$bd/billwatch__billwatch-web.count"; echo 0 > "$bd/iptv_apps__iptv-web.count"
snap(){ ( cd "$bd" && for f in *; do echo "$f=$(cat "$f")"; done ) | sort; }
before="$(snap)"; livebefore="$(cd "$qd/repos/gitlark" && git status --porcelain)"
OUT="$(bash "$S" --queue-dir "$qd" --ref HEAD 2>&1)"; r=$?
[ "$r" = 0 ] && ok "dry-run exit 0" || fail "dry-run rc=$r: $OUT"
[ "$(snap)" = "$before" ] && ok "dry-run writes nothing" || fail "dry-run modified baselines"
echo "$OUT" | grep -q "gitlark/web.*stored=2 .*measured=13.*would write" && ok "dry-run reports gitlark 2 -> 13" || fail "gitlark line: $OUT"
echo "$OUT" | grep -q "billwatch/billwatch-web.*unchanged" && echo "$OUT" | grep -q "iptv_apps/iptv-web.*unchanged" && ok "billwatch/iptv unchanged lines" || fail "unchanged lines: $OUT"
echo "$OUT" | grep -q "dry-run only" && ok "dry-run says how to apply" || fail "no apply hint"
OUT="$(bash "$S" --queue-dir "$qd" --ref HEAD --apply 2>&1)"; r=$?
[ "$r" = 0 ] && ok "apply exit 0" || fail "apply rc=$r: $OUT"
[ "$(cat "$bd/gitlark__web.count")" = 13 ] && ok "apply wrote gitlark__web.count = 13" || fail "count not 13"
ls "$bd" | grep -q '^gitlark__web.count.bak.' && [ "$(cat "$bd"/gitlark__web.count.bak.* | head -1)" = 2 ] && ok "backup of old count (2) kept" || fail "no count backup"
[ ! -f "$bd/gitlark__web.count.syn" ] && ls "$bd" | grep -q 'count.syn.bak.' && ok "stale .syn moved to backup" || fail ".syn handling"
[ "$(cat "$bd/billwatch__billwatch-web.count")" = 83 ] && ! ls "$bd" | grep -q 'billwatch.*bak' && ok "unchanged repos not rewritten, no backup" || fail "billwatch touched"
[ "$(cd "$qd/repos/gitlark" && git status --porcelain)" = "$livebefore" ] && ok "live clone untouched" || fail "live clone modified"
ls "$TMPDIR" | grep -q tsc_reseed && fail "temp dir leaked" || ok "no leaked temp dirs"
# syntax errors present -> refuse to seed
mk gitlark web 5 2; echo 2 > "$bd/gitlark__web.count"; rm -f "$bd"/gitlark__web.count.bak.*
OUT="$(bash "$S" --queue-dir "$qd" --ref HEAD --apply --repos "gitlark:web" 2>&1)"; r=$?
echo "$OUT" | grep -q "NOT RE-SEEDED" && [ "$(cat "$bd/gitlark__web.count")" = 2 ] && [ "$r" != 0 ] && ok "syntax errors -> refused, count untouched, rc!=0" || fail "syntax refusal: rc=$r $OUT"
# missing clone / bad arg
OUT="$(bash "$S" --queue-dir "$qd" --repos "nope:web" 2>&1)"; echo "$OUT" | grep -q "SKIP (no clone" && ok "missing clone -> SKIP" || fail "missing clone: $OUT"
bash "$S" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "unknown arg -> rc 2" || fail "unknown arg rc"
[ "$rc" = 0 ] && echo "test_tsc_baseline_reseed: PASS" || echo "test_tsc_baseline_reseed: FAIL"
exit $rc
