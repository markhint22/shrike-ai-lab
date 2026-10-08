#!/usr/bin/env bash
# Regression test for scripts/lib_pytest_parallel.sh (2026-09-29).
#
# The helper decides whether a full pytest run may add `-n <workers>` (pytest-xdist). The
# dangerous failure mode is emitting `-n` in a venv WITHOUT pytest-xdist: pytest rejects the
# unknown flag, every verify in that venv fails, and every commit is reverted. So the important
# assertions are the fall-back-to-serial ones, not the happy path.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_pytest_parallel.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_pytest_parallel.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib_pytest_parallel.sh not found"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkbin(){ # $1=dir $2=exit code of `python -c "import xdist"` (0 = xdist installed)
  mkdir -p "$1"
  printf '#!/bin/sh\nif [ "$1" = "-c" ] && [ "$2" = "import xdist" ]; then exit %s; fi\nexit 0\n' "$2" > "$1/python"
  chmod +x "$1/python"
}
mkbin "$tmp/with_xdist" 0
mkbin "$tmp/no_xdist" 1
mkdir -p "$tmp/no_python"

unset OVN_PYTEST_WORKERS OVN_XDIST_REPOS

ok "allowlisted repo with xdist installed -> -n 8" \
   "[ \"\$(ovn_pytest_par_args iptv_apps '$tmp/with_xdist')\" = '-n 8' ]"
ok "billwatch is NOT allowlisted by default (its parallel runs were never seen to complete cleanly)" \
   "[ -z \"\$(ovn_pytest_par_args billwatch '$tmp/with_xdist')\" ]"

# --- the critical fall-back cases: never emit -n when it would break pytest ---
ok "allowlisted repo but xdist NOT installed in that venv -> empty (serial)" \
   "[ -z \"\$(ovn_pytest_par_args iptv_apps '$tmp/no_xdist')\" ]"
ok "venv dir with no python at all -> empty (serial)" \
   "[ -z \"\$(ovn_pytest_par_args iptv_apps '$tmp/no_python')\" ]"
ok "missing venv path -> empty (serial)" \
   "[ -z \"\$(ovn_pytest_par_args iptv_apps '$tmp/does_not_exist')\" ]"

# --- allowlist: gitlark fails 11 tests under xdist, so it must stay serial even with xdist present ---
ok "gitlark (not allowlisted) stays serial even though xdist is installed" \
   "[ -z \"\$(ovn_pytest_par_args gitlark '$tmp/with_xdist')\" ]"
ok "unknown repo stays serial" \
   "[ -z \"\$(ovn_pytest_par_args some-new-repo '$tmp/with_xdist')\" ]"
ok "an empty repo name stays serial" \
   "[ -z \"\$(ovn_pytest_par_args '' '$tmp/with_xdist')\" ]"

# --- overrides ---
ok "OVN_PYTEST_WORKERS=4 changes the worker count" \
   "[ \"\$(OVN_PYTEST_WORKERS=4 ovn_pytest_par_args iptv_apps '$tmp/with_xdist')\" = '-n 4' ]"
ok "OVN_PYTEST_WORKERS=0 is a fleet-wide kill switch" \
   "[ -z \"\$(OVN_PYTEST_WORKERS=0 ovn_pytest_par_args iptv_apps '$tmp/with_xdist')\" ]"
ok "OVN_XDIST_REPOS overrides the allowlist (opt a repo in)" \
   "[ \"\$(OVN_XDIST_REPOS='gitlark' ovn_pytest_par_args gitlark '$tmp/with_xdist')\" = '-n 8' ]"
ok "OVN_XDIST_REPOS overrides the allowlist (opt a repo out)" \
   "[ -z \"\$(OVN_XDIST_REPOS='billwatch' ovn_pytest_par_args iptv_apps '$tmp/with_xdist')\" ]"

# --- output shape: safe to leave UNQUOTED on a command line ---
out="$(ovn_pytest_par_args iptv_apps "$tmp/with_xdist")"
ok "output is exactly two shell words (so unquoted expansion yields '-n' '8')" \
   "[ \$(printf '%s\n' $out | wc -l | tr -d ' ') -eq 2 ]"


# --- wiring: the call sites must go THROUGH the guard, never hardcode -n (the unguarded form fails
#     every verify in a venv without pytest-xdist). Static checks on the real scripts. ---
ROOT="$HERE/../.."; [ -f "$ROOT/branch_hygiene.sh" ] || ROOT="$HERE/.."
for f in branch_hygiene.sh ovn_stage_runner.sh; do
  if [ -f "$ROOT/$f" ]; then
    ok "$f sources the guard library" "grep -q 'lib_pytest_parallel.sh' '$ROOT/$f'"
    ok "$f builds its pytest flags via ovn_pytest_par_args" "grep -q 'ovn_pytest_par_args' '$ROOT/$f'"
    ok "$f never hardcodes an unguarded '-n <N>' pytest flag" "! grep -nE 'pytest[^#]*[[:space:]]-n[[:space:]]+[0-9]' '$ROOT/$f'"
  fi
done
echo "pytest-parallel guard: $P passed, $F failed"
[ "$F" -eq 0 ]
