#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 13, lowest priority): run_lint_check / run_coverage_check report CHANGES, not absolutes.
#  - run_lint_check ran ruff on the changed files and echoed the ABSOLUTE count ("[lint:309]" on every commit that touched a noisy file, even a commit that LOWERED it).
#    It now compares the BEFORE blob with the AFTER blob (multiset of findings with line/column stripped): N added / M removed; echoes N-M when > 0 (else 0), writes
#    "N M" to an optional detail file, and the caller prints [lint:+N/-M]. OVN_LINT_DELTA=off restores the absolute count.
#  - run_coverage_check flagged [untested-change] for any added def/class line, including a mere signature edit (-def f(a) / +def f(a, b)). Now only NET-NEW names count
#    (set(added) - set(removed)). OVN_COVERAGE_NETNEW=off restores the old count.
# The REAL functions are extracted from run_overnight.sh; ruff/eslint are content-aware stubs (a finding = a line containing BAD). Mutation controls at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME/aider-venv/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
BIN="$W/bin"; mkdir -p "$BIN"
cat > "$BIN/ruff" <<'EOS'
#!/bin/bash
# content-aware stub: one finding "<name>:<line>:1: E100 bad thing" per line containing BAD; stdin mode when '-' is among the args, else the named files
name="stdin"; use_stdin=0; files=(); nxt=0
for a in "$@"; do
  if [ "$nxt" = 1 ]; then name="$a"; nxt=0; continue; fi
  case "$a" in --stdin-filename) nxt=1;; -) use_stdin=1;; --*) ;; *) files+=("$a");; esac
done
emit(){ awk -v n="$1" '/BAD/{printf "%s:%d:1: E100 bad thing: %s\n", n, NR, $0}'; }
if [ "$use_stdin" = 1 ]; then emit "$name"; else for f in "${files[@]}"; do emit "$f" < "$f"; done; fi
EOS
chmod +x "$BIN/ruff"
mkdir -p "$W/node_stub"
export PATH="$BIN:$PATH"
FN="$(sed -n '/^run_lint_check() {/,/^}/p;/^run_coverage_check() {/,/^}/p' "$RUN")"
[ -n "$FN" ] || { echo "  FAIL: could not extract run_lint_check/run_coverage_check from $RUN"; exit 1; }
eval "$FN"

R="$W/repo"
mkrepo(){ rm -rf "$R"; mkdir -p "$R"; cd "$R" || exit 1; git init -q; git config user.email t@t; git config user.name t; echo base > README; git add -A; git commit -q -m base; }
sha(){ git rev-parse HEAD; }
DET="$W/detail"
lint(){ run_lint_check "$1" "$2" "$DET"; }

# ---------------------------------------------------------------- lint
mkrepo; printf 'BAD one\nBAD two\nBAD three\nok\n' > a.py; git add -A; git commit -q -m a; B="$(sha)"
printf 'BAD one\nok\nok\nok\n' > a.py; git add -A; git commit -q -m lower; A="$(sha)"
ok "commit that LOWERS the findings (3 -> 1): echoes 0 (the old absolute logic echoed 1), detail '0 2'" "[ \"\$(lint '$B' '$A')\" = 0 ] && [ \"\$(cat '$DET')\" = '0 2' ]"
ok "same commit under OVN_LINT_DELTA=off echoes the absolute count (1) = the old behaviour" "[ \"\$(OVN_LINT_DELTA=off lint '$B' '$A')\" = 1 ]"
printf 'BAD one\nBAD two\nBAD three\nok\n' > a.py; git add -A; git commit -q -m c3; B="$(sha)"
printf 'BAD one\nBAD two\nBAD three\nBAD four\nBAD five\n' > a.py; git add -A; git commit -q -m add2; A="$(sha)"
ok "commit that ADDS 2 findings: echoes 2, detail '2 0'" "[ \"\$(lint '$B' '$A')\" = 2 ] && [ \"\$(cat '$DET')\" = '2 0' ]"
printf 'ok\nok\nBAD one\nBAD two\n' > a.py; git add -A; git commit -q -m c4; B="$(sha)"
printf 'ok\nok\nnew line\nnew line\nBAD one\nBAD two\n' > a.py; git add -A; git commit -q -m move; A="$(sha)"
ok "findings that merely MOVED (lines shifted by an insertion) are not new: 0, detail '0 0'" "[ \"\$(lint '$B' '$A')\" = 0 ] && [ \"\$(cat '$DET')\" = '0 0' ]"
printf 'BAD one\nBAD two\nok\n' > a.py; git add -A; git commit -q -m c5; B="$(sha)"
printf 'BAD two\nBAD x\nBAD y\nBAD z\n' > a.py; git add -A; git commit -q -m mix; A="$(sha)"
ok "mixed: 1 removed + 3 added => net +2, detail '3 1'" "[ \"\$(lint '$B' '$A')\" = 2 ] && [ \"\$(cat '$DET')\" = '3 1' ]"
printf 'ok\n' > b.py; git add -A; git commit -q -m c6; B="$(sha)"
printf 'BAD one\nBAD two\n' > newfile.py; git add -A; git commit -q -m new; A="$(sha)"
ok "a NEW file (no BEFORE blob) counts all its findings as added (2)" "[ \"\$(lint '$B' '$A')\" = 2 ] && [ \"\$(cat '$DET')\" = '2 0' ]"
git rm -q newfile.py; git commit -q -m del; B="$A"; A="$(sha)"
ok "a DELETED file is not linted on the AFTER side: nothing added (0)" "[ \"\$(lint '$B' '$A')\" = 0 ]"
mkdir -p migrations; printf 'BAD m\n' > migrations/0001.py; git add -A; git commit -q -m mig; B="$A"; A="$(sha)"
ok "root migrations/ files stay excluded (0)" "[ \"\$(lint '$B' '$A')\" = 0 ]"
echo hi > notes.txt; git add -A; git commit -q -m txt; B="$A"; A="$(sha)"
ok "no py/js file changed => 0 and the detail file says '0 0'" "[ \"\$(lint '$B' '$A')\" = 0 ] && [ \"\$(cat '$DET')\" = '0 0' ]"
ok "the 3rd argument is optional (the old 2-arg call still echoes an integer)" "[ \"\$(run_lint_check '$B' '$A')\" = 0 ]"
# eslint (js) with a stdin-aware stub
mkrepo; mkdir -p node_modules/.bin
cat > node_modules/.bin/eslint <<'EOS'
#!/bin/bash
# content-aware stub: stdin mode (--stdin --stdin-filename NAME) or real files as arguments
name="stdin"; nxt=0; use_stdin=0; files=()
for a in "$@"; do
  if [ "$nxt" = 1 ]; then name="$a"; nxt=0; continue; fi
  case "$a" in --stdin-filename) nxt=1;; --stdin) use_stdin=1;; --format) ;; unix) ;; --*) ;; *) files+=("$a");; esac
done
emit(){ awk -v n="$1" '/BAD/{printf "%s:%d:1: error bad %s (no-undef)\n", n, NR, $0}'; }
if [ "$use_stdin" = 1 ]; then emit "$name"; else for f in "${files[@]}"; do emit "$f" < "$f"; done; fi
EOS
chmod +x node_modules/.bin/eslint; printf 'BAD a\nBAD b\n' > a.js; git add -A; git commit -q -m js1; B="$(sha)"
printf 'BAD a\n' > a.js; git add -A; git commit -q -m js2; A="$(sha)"
ok "eslint: a commit that removes a finding => 0 (detail '0 1')" "[ \"\$(lint '$B' '$A')\" = 0 ] && [ \"\$(cat '$DET')\" = '0 1' ]"
printf 'BAD a\nBAD q\nBAD r\n' > a.js; git add -A; git commit -q -m js3; A2="$(sha)"
ok "eslint: a commit that adds 2 => 2 (detail '2 0')" "[ \"\$(lint '$A' '$A2')\" = 2 ] && [ \"\$(cat '$DET')\" = '2 0' ]"

# ---------------------------------------------------------------- coverage
mkrepo; printf 'def f(a):\n    return a\n' > m.py; git add -A; git commit -q -m m; B="$(sha)"
printf 'def f(a, b):\n    return a + b\n' > m.py; git add -A; git commit -q -m sig; A="$(sha)"
ok "a signature edit (-def f(a) / +def f(a, b)) is NOT an untested new definition => ok" "[ \"\$(run_coverage_check '$B' '$A')\" = ok ]"
ok "same commit under OVN_COVERAGE_NETNEW=off is flagged (the old behaviour) => untested" "[ \"\$(OVN_COVERAGE_NETNEW=off run_coverage_check '$B' '$A')\" = untested ]"
printf 'def f(a, b):\n    return a + b\n\ndef g(x):\n    return x\n' > m.py; git add -A; git commit -q -m newdef; A2="$(sha)"
ok "a genuinely new function g => untested" "[ \"\$(run_coverage_check '$A' '$A2')\" = untested ]"
printf 'def f(a, b):\n    return a + b\n\ndef h(x):\n    return x\n' > m.py; git add -A; git commit -q -m rename; A3="$(sha)"
ok "renaming g -> h (one name removed, a different one added) => untested (h is net-new)" "[ \"\$(run_coverage_check '$A2' '$A3')\" = untested ]"
printf 'def h(x):\n    return x\n\ndef f(a, b):\n    return a + b\n' > m.py; git add -A; git commit -q -m reorder; A4="$(sha)"
ok "reordering functions (same names removed and added) => ok" "[ \"\$(run_coverage_check '$A3' '$A4')\" = ok ]"
printf 'class K:\n    pass\n' > k.py; git add -A; git commit -q -m cls; A5="$(sha)"
ok "a new class => untested" "[ \"\$(run_coverage_check '$A4' '$A5')\" = untested ]"
printf 'class K:\n    pass\n' > k.py; printf 'def test_k():\n    assert True\n' > test_k.py; printf 'def n1():\n    pass\n' > n.py; git add -A; git commit -q -m withtest; A6="$(sha)"
ok "a new def WITH a test file in the same commit => ok (unchanged)" "[ \"\$(run_coverage_check '$A5' '$A6')\" = ok ]"
printf 'func a(x):\n\tpass\n' > g.gd; git add -A; git commit -q -m gd1; B7="$(sha)"
printf 'func a(x, y):\n\tpass\n' > g.gd; git add -A; git commit -q -m gd2; A7="$(sha)"
ok "gdscript signature edit => ok; new gd func => untested" "[ \"\$(run_coverage_check '$B7' '$A7')\" = ok ]"
printf 'export async function fx() {}\n' > t.ts; git add -A; git commit -q -m ts; A8="$(sha)"
ok "a new exported async ts function => untested" "[ \"\$(run_coverage_check '$A7' '$A8')\" = untested ]"

# ---------------------------------------------------------------- caller wiring + mutants
ok "the push-status caller prints [lint:+N/-M] (and the old [lint:N] under OVN_LINT_DELTA=off)" "[ \"\$(grep -c 'PUSH_STATUS=\"\${PUSH_STATUS} \\[lint:+\${_ovn_lint_n:-\$LINT_ISSUES}/-\${_ovn_lint_m:-0}\\]\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'PUSH_STATUS=\"\${PUSH_STATUS} \\[lint:\${LINT_ISSUES}\\]\"' '$RUN')\" = 1 ]"
python3 - "$RUN" "$W" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
def fn(name):
    m = re.search(r"^%s\(\) \{.*?^\}" % name, s, re.S | re.M)
    return m.group(0)
lint, cov = fn("run_lint_check"), fn("run_coverage_check")
def mut(src, a, b, out):
    assert src.count(a) == 1, a
    open(sys.argv[2] + "/" + out, "w").write(src.replace(a, b))
mut(lint, 'if [ $((added - fixed)) -gt 0 ]; then echo $((added - fixed)); else echo 0; fi', 'echo "$added"', "m_lint_delta.sh")
mut(lint, "comm -23 <(printf '%s\\n' \"$b\" | grep -v '^$') <(printf '%s\\n' \"$a\" | grep -v '^$')", "echo", "m_lint_fixed.sh") if False else None
mut(lint, "sed -E 's/^[^:]*:[0-9]+:[0-9]+:? *//' | sort", "sort", "m_lint_pos.sh") if False else None
mut(cov, "newdefs=\"$(comm -23 <(printf '%s\\n' \"$addn\" | grep -v '^$') <(printf '%s\\n' \"$remn\" | grep -v '^$') | grep -c . || true)\"", "newdefs=\"$(printf '%s\\n' \"$addn\" | grep -vc '^$' || true)\"", "m_cov_net.sh")
PY
# mutation scenarios live in their own repos so they do not depend on the shas above
mixed_repo(){ mkrepo; printf 'BAD one\nBAD two\nok\n' > a.py; git add -A; git commit -q -m a; MB="$(sha)"; printf 'BAD two\nBAD x\nBAD y\nBAD z\n' > a.py; git add -A; git commit -q -m m; MA="$(sha)"; }
sig_repo(){ mkrepo; printf 'def f(a):\n    return a\n' > m.py; git add -A; git commit -q -m m; SB="$(sha)"; printf 'def f(a, b):\n    return a + b\n' > m.py; git add -A; git commit -q -m s; SA="$(sha)"; }
mixed_repo
ok "MUTATION sanity: the real run_lint_check says net 2 for the mixed commit (3 added, 1 removed)" "[ \"\$(run_lint_check '$MB' '$MA')\" = 2 ]"
ok "MUTATION: a run_lint_check that echoed the ADDED count would say 3 for the same commit (so the net-delta assertions would fail)" "[ \"\$( ( eval \"\$(cat '$W/m_lint_delta.sh')\"; run_lint_check '$MB' '$MA' ) )\" = 3 ]"
sig_repo
ok "MUTATION sanity: the real run_coverage_check says ok for the signature edit" "[ \"\$(run_coverage_check '$SB' '$SA')\" = ok ]"
ok "MUTATION: counting every added name (no removed-name subtraction) flags the signature edit again => untested" "[ \"\$( ( eval \"\$(cat '$W/m_cov_net.sh')\"; run_coverage_check '$SB' '$SA' ) )\" = untested ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
