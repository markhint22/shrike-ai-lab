#!/usr/bin/env bash
# scripts/lib_pytest_parallel.sh — decide whether a repo's full pytest run may use pytest-xdist.
#
# WHY (2026-09-29): iptv_apps' full pytest suite takes ~456s and runs ~32x/day on the fleet's
# critical path (236 min/day) plus twice an hour in branch_hygiene.sh, which holds the shared
# per-repo verify lock for the whole run (that lock hold is what turned into the 300s-wait
# "verify skipped - lock contended" errors, 58 min/day). Measured on the loaded box, same
# suite, same tests: iptv_apps 467s -> 64s with `-n 8`; billwatch 105s -> 18s. The fleet is
# serial and the GPU sits idle during verification, so this is the cheapest throughput win.
#
# SAFETY - this is a guard, not a flag: pytest REJECTS `-n` outright when pytest-xdist is not
# installed ("unrecognized arguments: -n"), which would fail EVERY verify in that venv and revert
# every commit. So the flag is only ever emitted when ALL of these hold:
#   1. the repo is on the allowlist (default: iptv_apps only - 5 consecutive clean parallel runs.
#      NOT on it: gitlark, where 11 tests fail under parallelism and need isolation work first, and
#      billwatch, whose parallel runs were never seen to complete cleanly - its suite was observed
#      HANGING (also serially, in branch_hygiene) at ~24% on 2026-09-29, unexplained; investigate
#      that before enabling);
#   2. the kill switch is off (OVN_PYTEST_WORKERS=0 disables it fleet-wide instantly);
#   3. `import xdist` actually succeeds in THAT venv's python (a rebuilt/self-healed venv, a staged
#      worktree, or a fresh provision without the dependency silently falls back to serial).
#
# Usage:  XD="$(ovn_pytest_par_args <repo-basename> <dir-containing-the-venv's-python>)"
#         "$py" -m pytest ... $XD ...            # $XD is empty or "-n <workers>"; leave UNQUOTED
# Override the allowlist with OVN_XDIST_REPOS="a b c"; worker count with OVN_PYTEST_WORKERS=N.
ovn_pytest_par_args() {
  local repo="${1:-}" venvbin="${2:-}" workers="${OVN_PYTEST_WORKERS:-8}"
  [ "$workers" = "0" ] && return 0
  case " ${OVN_XDIST_REPOS:-iptv_apps} " in *" $repo "*) ;; *) return 0 ;; esac
  local py="$venvbin/python"
  [ -x "$py" ] || py="$venvbin/python3"
  [ -x "$py" ] || return 0
  "$py" -c 'import xdist' >/dev/null 2>&1 || return 0
  printf -- '-n %s' "$workers"
}
