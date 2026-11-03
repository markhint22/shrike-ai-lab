#!/usr/bin/env bash
# N4 (2026-11-02): lint_ntfy_tests.py keeps the suite from posting to the LIVE notification channel (a test calling push_emergency('t','m') against the real relay paged Mark's phone
# every suite run). This wrapper proves (a) the real scripts/test dir is clean, (b) the guard exports the closed-port NTFY_SERVER + OVN_NOTIFY_DISABLE, (c) each rule has teeth: a mutant dir
# containing exactly one violation must be reported (mutation proof), and the allow marker / safe variants must NOT be.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
L="$HERE/lint_ntfy_tests.py"
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
out="$(python3 "$L" "$HERE" 2>&1)"; rc=$?
ok "the real scripts/test dir has no test that can post to the live relay / ntfy.sh${out:+: $out}" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
env_after="$(bash -c ". '$HERE/ntfy_guard.sh'; echo \"\$NTFY_SERVER|\${OVN_NOTIFY_DISABLE:-}\"")"
ok "sourcing ntfy_guard.sh exports NTFY_SERVER=http://127.0.0.1:9 and OVN_NOTIFY_DISABLE=1" "$([ "$env_after" = "http://127.0.0.1:9|1" ] && echo 1 || echo 0)"

mk(){ # fresh minimal test dir with a clean guard + runner; echo its path
  local d; d="$(safe_mktemp_dir_in "$T" case)" || exit 1
  cp "$HERE/ntfy_guard.sh" "$d/"; printf '. "$HERE/ntfy_guard.sh"\n' > "$d/run_all.sh"; echo "$d"; }
expect_bad(){ # $1 label $2 dir $3 grep-pattern
  local o; o="$(python3 "$L" "$2" 2>&1)"; local r=$?
  ok "mutant: $1 is reported" "$([ "$r" = 1 ] && printf '%s' "$o" | grep -q "$3" && echo 1 || echo 0)"; }
expect_clean(){ local o; o="$(python3 "$L" "$2" 2>&1)"; ok "safe variant: $1 is NOT reported${o:+: $o}" "$([ $? = 0 ] && [ -z "$o" ] && echo 1 || echo 0)"; }

d="$(mk)"; expect_clean "baseline dir (guard + runner only)" "$d"
d="$(mk)"; printf 'export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"\n' > "$d/test_a.sh"; expect_bad "a live-relay NTFY_SERVER default (R1)" "$d" 'test_a.sh:1'
d="$(mk)"; printf 'x=1\nenv -i NTFY_SERVER=http://localhost:8099 bash run.sh\n' > "$d/test_b.sh"; expect_bad "NTFY_SERVER=localhost:8099 on an executed line (R1)" "$d" 'test_b.sh:2'
d="$(mk)"; printf 'NTFY_SERVER=https://ntfy.sh bash x.sh\n' > "$d/test_c.sh"; expect_bad "NTFY_SERVER=https://ntfy.sh (R1)" "$d" 'test_c.sh:1'
d="$(mk)"; printf 'import qa.evidence_freshness_check as FM\nFM.push_emergency("t", "m")\n' > "$d/test_d.py"; expect_bad "an unmocked push_emergency('t','m') call (R2: the real N4 leak)" "$d" 'test_d.py:1'
d="$(mk)"; printf 'export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"   # ntfy-lint: allow\n# NTFY_SERVER=http://127.0.0.1:8099 in a comment\n' > "$d/test_e.sh"; expect_clean "allow marker and comment-only lines" "$d"
d="$(mk)"; printf 'import os\nos.environ["NTFY_SERVER"]="http://127.0.0.1:9"\nFM.push_emergency("t","m")\n' > "$d/test_f.py"; expect_clean "push_emergency with NTFY_SERVER set in the file" "$d"
d="$(mk)"; printf 'export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:9}"\n' > "$d/test_g.sh"; expect_clean "closed-port default" "$d"
d="$(mk)"; sed -i.bak 's#^export NTFY_SERVER=.*#unset NTFY_SERVER#' "$d/ntfy_guard.sh"; rm -f "$d/ntfy_guard.sh.bak"; expect_bad "a guard that only unsets NTFY_SERVER again (R3)" "$d" 'ntfy_guard.sh:1: does not export NTFY_SERVER'
d="$(mk)"; sed -i.bak 's#^export OVN_NOTIFY_DISABLE=1#:#' "$d/ntfy_guard.sh"; rm -f "$d/ntfy_guard.sh.bak"; expect_bad "a guard without OVN_NOTIFY_DISABLE (R3)" "$d" 'does not export OVN_NOTIFY_DISABLE'
d="$(mk)"; sed -i.bak 's#|\*127.0.0.1:8099\*|\*localhost:8099\*##' "$d/ntfy_guard.sh"; rm -f "$d/ntfy_guard.sh.bak"; expect_bad "a guard whose curl wrapper no longer swallows the live relay (R3)" "$d" 'does not swallow the LIVE relay'
d="$(mk)"; : > "$d/run_all.sh"; expect_bad "a runner that no longer sources the guard (R3)" "$d" 'runner does not source ntfy_guard.sh'
# N5 audit: no pipeline script defaults NTFY_SERVER to ntfy.sh
QROOT="$(cd "$HERE/../.." && pwd)"
out="$(python3 "$L" --scripts "$QROOT" 2>&1)"; rc=$?
ok "no pipeline script defaults NTFY_SERVER to https://ntfy.sh (relay bypass)${out:+: $out}" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
d="$(safe_mktemp_dir_in "$T" scr)"; printf 'curl -d x "${NTFY_SERVER:-https://ntfy.sh}/t"\n' > "$d/a.sh"
o="$(python3 "$L" --scripts "$d" 2>&1)"; r=$?; ok "mutant: a shell script with the \${NTFY_SERVER:-https://ntfy.sh} fallback is reported" "$([ "$r" = 1 ] && printf '%s' "$o" | grep -q 'a.sh:1' && echo 1 || echo 0)"
printf 'import os\nu = os.environ.get("NTFY_SERVER", "https://ntfy.sh")\n' > "$d/b.py"
o="$(python3 "$L" --scripts "$d" 2>&1)"; ok "mutant: a python os.environ.get('NTFY_SERVER', 'https://ntfy.sh') default is reported" "$(printf '%s' "$o" | grep -q 'b.py:2' && echo 1 || echo 0)"
d2="$(safe_mktemp_dir_in "$T" scr2)"; printf 'curl -d x "${NTFY_SERVER:-http://127.0.0.1:8099}/t"\n# NTFY_SERVER:-https://ntfy.sh in a comment\ncurl "${NTFY_SERVER:-https://ntfy.sh}/t"   # ntfy-lint: allow\n' > "$d2/c.sh"
python3 "$L" --scripts "$d2" >/dev/null 2>&1; ok "safe variants: relay default, comment, allow marker are NOT reported" "$([ $? = 0 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
