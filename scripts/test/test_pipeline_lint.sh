#!/usr/bin/env bash
# Pipeline-wide static gate (2026-09-30). Fails when ANY pipeline script (repo root + scripts/, excluding attic/, test/, cov/,
# proposals*/, .bak*/) is: syntactically broken, shellcheck-error-level broken, uses a known-bad idiom that already caused
# live bugs, or has NO test that references it (unless scripts/test/coverage_exempt.txt lists it with a reason).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$ROOT/run_overnight.sh" ] || ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT" || exit 1
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
scripts="$(ls ./*.sh ./*.py scripts/*.sh scripts/*.py 2>/dev/null | sed 's#^\./##')"
n="$(printf '%s\n' "$scripts" | grep -c .)"
echo "  scanning $n pipeline scripts under $ROOT"

bad=""; for f in $scripts; do case "$f" in *.sh) bash -n "$f" 2>/dev/null || bad="$bad $f";; *.py) python3 -m py_compile "$f" 2>/dev/null || bad="$bad $f";; esac; done
ok "every script parses (bash -n / py_compile)${bad:+ - BROKEN:$bad}" "$([ -z "$bad" ] && echo 1 || echo 0)"
find . -name __pycache__ -path './scripts/__pycache__' -prune -o -name '*.pyc' -newer "$0" -print 2>/dev/null | head -0

if command -v shellcheck >/dev/null 2>&1; then
  sc=""; for f in $(printf '%s\n' "$scripts" | grep '\.sh$'); do out="$(shellcheck -S error -x "$f" 2>/dev/null | grep -c '^In ')"; [ "${out:-0}" -gt 0 ] && sc="$sc $f"; done
  ok "shellcheck reports no error-level findings${sc:+ in:$sc}" "$([ -z "$sc" ] && echo 1 || echo 0)"
else echo "  skip shellcheck (not installed)"; fi

# known-bad idioms that each caused a real bug
hit=""; for f in $(printf '%s\n' "$scripts" | grep '\.sh$' | grep -v '^test_'); do
  h="$(sed -E 's/[[:space:]]#.*$//' "$f" | grep -vE '^[[:space:]]*#' | grep -nE 'grep -c[^)|]*\|\| *echo 0|pgrep -c[^)|]*\|\| *echo 0' | head -2 | sed "s#^#$f:#")"; [ -n "$h" ] && hit="$hit $h"; done
ok "no 'grep -c/pgrep -c ... || echo 0' (prints 0 AND exits 1 -> '0\\n0' integer-expression bugs)${hit:+: $hit}" "$([ -z "$hit" ] && echo 1 || echo 0)"
hit=""; for f in $(printf '%s\n' "$scripts" | grep '\.sh$' | grep -v '^test_'); do
  h="$(sed -E 's/[[:space:]]#.*$//' "$f" | grep -vE '^[[:space:]]*#' | grep -nE 'grep -[a-zA-Z]*v[^|]*>>[^|]*\|\| *(cat|cp|echo|printf)' | head -2 | sed "s#^#$f:#")"; [ -n "$h" ] && hit="$hit $h"; done
ok "no 'grep -v ... >> file || cat ...' (grep -v exits 1 when it prints nothing, so the fallback re-appends everything: prework queue 12x bloat)${hit:+: $hit}" "$([ -z "$hit" ] && echo 1 || echo 0)"
hit="$(grep -nE "python3? -c .*sys\.stdin\.read\(\)" $(printf '%s\n' "$scripts" | grep '\.sh$') 2>/dev/null | head -5)"
ok "no 'python -c ... sys.stdin.read()' (UnicodeDecodeError on truncated multibyte text; use stdin.buffer.read().decode(...,'replace'))${hit:+: $hit}" "$([ -z "$hit" ] && echo 1 || echo 0)"
hit="$(grep -nE '^[[:space:]]*[A-Za-z_]+\(\) *\{' ./run_overnight.sh | head -0)"
# entrypoints that systemd/cron exec directly must be executable (2026-09-19: a non-executable run_overnight.sh crash-looped the fleet)
nx=""; for f in run_overnight.sh branch_hygiene.sh reconcile_branches.sh fleet_autofix.sh queue_refill.sh supervisor.sh ovn_planner.sh; do [ -f "$f" ] && [ ! -x "$f" ] && nx="$nx $f"; done
ok "cron/systemd entrypoints are executable${nx:+ - NOT:$nx}" "$([ -z "$nx" ] && echo 1 || echo 0)"
# no stray backup/scratch scripts in the pipeline dirs
stray="$(ls ./*.bak* scripts/*.bak* ./*.orig scripts/*.orig 2>/dev/null | head -3 | tr '\n' ' ')"
ok "no stray .bak/.orig files next to live scripts${stray:+: $stray}" "$([ -z "$stray" ] && echo 1 || echo 0)"

# test-reference gate: every script is referenced by at least one OTHER test file
EX="$HERE/coverage_exempt.txt"; [ -f "$EX" ] || : > "$EX"
untested=""
for f in $scripts; do
  b="$(basename "$f")"
  grep -qxF "$f" <(sed -E 's/[[:space:]]*#.*//' "$EX" | awk 'NF{print $1}') && continue
  hits="$(grep -lF "$b" "$HERE"/*.sh "$HERE"/*.py 2>/dev/null | grep -v "/test_pipeline_lint.sh$" | grep -v "/run_all.sh$" | grep -vF "/$b" | wc -l | tr -d ' ')"
  [ "${hits:-0}" -eq 0 ] && untested="$untested $f"
done
ok "every pipeline script is referenced by a test (or listed with a reason in coverage_exempt.txt)${untested:+ - UNTESTED:$untested}" "$([ -z "$untested" ] && echo 1 || echo 0)"
stale=""; while read -r f _; do [ -n "$f" ] && [ ! -e "$f" ] && stale="$stale $f"; done < <(sed -E 's/[[:space:]]*#.*//' "$EX" | awk 'NF')
ok "coverage_exempt.txt has no stale entries${stale:+: $stale}" "$([ -z "$stale" ] && echo 1 || echo 0)"
# every test file must be wired into run_all.sh (an unregistered test never runs in the gate)
unreg="$(python3 "$HERE/register_new_tests.py" --check 2>/dev/null | sed 's/^unregistered: //')"
ok "every scripts/test/test_*.sh is registered in run_all.sh${unreg:+ - NOT: $unreg}" "$([ "$unreg" = "none" ] || [ -z "$unreg" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
