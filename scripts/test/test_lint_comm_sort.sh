#!/usr/bin/env bash
# run_overnight.sh run_lint_check: the BEFORE/AFTER finding lists are compared with comm on the same collation (2026-10-10, review B14).
#
# Defect: `comm: file 2 is not in sorted order` + `comm: input is not in sorted order` appeared in the journal on EVERY pass (14 hits in 3 h) and was assumed harmless. It is not: BEFORE (b)
# is the CONCATENATION of per-file sorted lists in git's bytewise path order, AFTER (a) is one sort in the host locale (en_US.UTF-8 on the box, where punctuation is ignored), so for paths such as
# t/test_streams.py and t/test_streams_health.py the two lists are in different orders and comm miscounts: a commit that changes NO finding is reported as "+1 added / -1 fixed" (detail '1 1').
# The fix re-sorts both sides and runs comm under LC_ALL=C.
#
# The host sort may be bytewise (macOS) - then the defect cannot show - so a `sort` shim on PATH emulates the box's punctuation-ignoring collation unless LC_ALL=C is set (exactly what a UTF-8
# locale sort does for these names). The REAL run_lint_check is extracted from run_overnight.sh; ruff is a content-aware stub (a finding = a line containing BAD).
# Mutation section: the pre-fix line is restored in a temp copy of run_overnight.sh and the same checks must FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; RUN="${OVN_RUN_SH:-$Q/run_overnight.sh}"
[ -f "$RUN" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
grep -q '^run_lint_check() {' "$RUN" || { echo "  SKIP: run_overnight.sh has no run_lint_check"; exit 0; }
REAL_SORT="$(command -v sort)"
P=0; F=0; QUIET=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); [ "$QUIET" = 1 ] || echo "  FAIL: $1"; fi; }
W="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
BIN="$W/bin"; mkdir -p "$BIN"
cat > "$BIN/ruff" <<'EOS'
#!/bin/bash
name="stdin"; use_stdin=0; files=(); nxt=0
for a in "$@"; do
  if [ "$nxt" = 1 ]; then name="$a"; nxt=0; continue; fi
  case "$a" in --stdin-filename) nxt=1;; -) use_stdin=1;; --*) ;; *) files+=("$a");; esac
done
emit(){ awk -v n="$1" '/BAD/{printf "%s:%d:1: E100 bad thing: %s\n", n, NR, $0}'; }
if [ "$use_stdin" = 1 ]; then emit "$name"; else for f in "${files[@]}"; do emit "$f" < "$f"; done; fi
EOS
# punctuation-ignoring, case-folding collation (what sort does under en_US.UTF-8 on the box) unless LC_ALL=C
cat > "$BIN/sort" <<EOS
#!/bin/bash
if [ "\${LC_ALL:-}" = C ]; then exec "$REAL_SORT" "\$@"; fi
awk '{k=tolower(\$0); gsub(/[^a-z0-9 ]/,"",k); print k "\\t" \$0}' | "$REAL_SORT" -t "\$(printf '\\t')" -k1,1 | cut -f2-
EOS
chmod +x "$BIN/ruff" "$BIN/sort"
export PATH="$BIN:$PATH"
unset LC_ALL

# sanity of the shim itself: it really orders these two names differently from the bytewise order
ok "shim: locale-like sort puts test_streams_health BEFORE test_streams.py (bytewise puts it after) - the precondition of the defect" "[ \"\$(printf 't/test_streams.py E\\nt/test_streams_health.py E\\n' | sort | head -1)\" = 't/test_streams_health.py E' ] && [ \"\$(printf 't/test_streams.py E\\nt/test_streams_health.py E\\n' | LC_ALL=C sort | head -1)\" = 't/test_streams.py E' ]"

checks(){   # $1 = run_overnight.sh to extract from, $2 = label prefix
  local run="$1" l="${2:-}" FN R="$W/repo" B A
  FN="$(sed -n '/^run_lint_check() {/,/^}/p' "$run")"
  [ -n "$FN" ] || { F=$((F+1)); echo "  FAIL: cannot extract run_lint_check"; return; }
  rm -f "$W"/out_* "$W"/det_*
  ( eval "$FN"
    rm -rf "$R"; mkdir -p "$R/t"; cd "$R" || exit 1; git init -q; echo base > README
    printf 'BAD a\nok\n' > t/test_streams.py; printf 'BAD b\nok\n' > t/test_streams_health.py; git add -A; git commit -q -m base; B="$(git rev-parse HEAD)"
    # 1. both files change but their findings only MOVE
    printf 'ok\nBAD a\nok\n' > t/test_streams.py; printf 'ok\nBAD b\nok\n' > t/test_streams_health.py; git add -A; git commit -q -m moved; A="$(git rev-parse HEAD)"
    run_lint_check "$B" "$A" "$W/det_nochange" > "$W/out_nochange" 2>&1
    # 2. one finding added in one of them
    printf 'ok\nBAD a\nBAD a2\nok\n' > t/test_streams.py; git add -A; git commit -q -m add1; B="$A"; A="$(git rev-parse HEAD)"
    run_lint_check "$B" "$A" "$W/det_add1" > "$W/out_add1" 2>&1
    # 3. one finding fixed in the other
    printf 'ok\nok\nok\n' > t/test_streams_health.py; git add -A; git commit -q -m fix1; B="$A"; A="$(git rev-parse HEAD)"
    run_lint_check "$B" "$A" "$W/det_fix" > "$W/out_fix" 2>&1
  ) >/dev/null 2>&1
  ok "${l}findings that only MOVED across two locale-hostile paths: echoes 0" "[ \"\$(cat '$W/out_nochange')\" = 0 ]"
  ok "${l}...and the detail file is exactly '0 0' (the defect reported '1 1': a finding present on both sides counted as added AND fixed)" "[ \"\$(cat '$W/det_nochange')\" = '0 0' ]"
  ok "${l}one new finding: detail '1 0', echoes 1" "[ \"\$(cat '$W/det_add1')\" = '1 0' ] && [ \"\$(cat '$W/out_add1')\" = 1 ]"
  ok "${l}one finding fixed: detail '0 1', echoes 0" "[ \"\$(cat '$W/det_fix')\" = '0 1' ] && [ \"\$(cat '$W/out_fix')\" = 0 ]"
  ok "${l}no 'not in sorted order' complaint in any output" "! grep -q 'sorted order' '$W/out_nochange' '$W/out_add1' '$W/out_fix'"
}
checks "$RUN"

# ---- mutation: restore the pre-fix comm line in a temp copy; the checks must fail
if [ -z "${LINTCOMM_SKIP_MUTATION:-}" ]; then
  M="$W/run_overnight_prefix.sh"
  python3 - "$RUN" "$M" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
new = s
old_line = [l for l in s.split("\n") if l.strip().startswith("_ovn_lint_cnt() {")]
assert len(old_line) == 1, "anchor: _ovn_lint_cnt line not found exactly once"
pre = '''  _ovn_lint_cnt() { local n; n="$(comm "$1" <(printf '%s\\n' "$b" | grep -v '^$') <(printf '%s\\n' "$a" | grep -v '^$') | grep -c . || true)"; echo "${n:-0}"; }'''
new = s.replace(old_line[0], pre, 1)
open(sys.argv[2], "w").write(new)
EOF
  p0=$P; f0=$F; QUIET=1; checks "$M" "[pre-fix] "; QUIET=0
  caught=$(( F > f0 )); P=$p0; F=$f0
  ok "mutation CAUGHT: with the pre-fix comm line the checks fail (miscount under a locale-ordered sort)" "[ '$caught' = 1 ]"
  M2="$W/run_overnight_nocomm_c.sh"
  sed -e "s#LC_ALL=C comm#comm#" "$RUN" > "$M2"
  p0=$P; f0=$F; QUIET=1; checks "$M2" "[no-C-comm] "; QUIET=0
  caught2=$(( F > f0 )); P=$p0; F=$f0
  # comm without LC_ALL=C is still correct on a bytewise-comm host when both inputs are C-sorted: report, do not require
  echo "  info: comm without LC_ALL=C (inputs still C-sorted) is $([ "$caught2" = 1 ] && echo 'also caught' || echo 'equivalent on this host - fine, the C-sort of both inputs is the load-bearing part')"
  M3="$W/run_overnight_nosort.sh"
  sed -e "s#| grep -v '^\$' | LC_ALL=C sort)#| grep -v '^\$')#g" "$RUN" > "$M3"
  p0=$P; f0=$F; QUIET=1; checks "$M3" "[no-resort] "; QUIET=0
  caught3=$(( F > f0 )); P=$p0; F=$f0
  ok "mutation CAUGHT: dropping the C-locale re-sort of both inputs" "[ '$caught3' = 1 ]"
fi
echo "test_lint_comm_sort: $P passed, $F failed"
[ "$F" -eq 0 ]
