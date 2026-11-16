#!/usr/bin/env bash
# scripts/lib_tools_runner.sh - pipeline-owned python test runner (2026-11-15, q-weekend-fixes). SOURCED by run_overnight.sh and ovn_stage_runner.sh.
#
# Gap: a repo whose python tests are PYTEST-style files but that has no .venv/bin/pytest (xlite: tools/tests/*.py, no venv) failed the verify fail-closed rule on EVERY staged run
# ("python tests exist but no venv pytest found: CANNOT verify"): 40 of 126 xlite rows in 53 h were no-op(stage-unverified). The repos themselves are never edited, so the pipeline owns a
# tools venv instead (ops/make_tools_venv.sh creates it: `python3 -m venv` + `pip install pytest`).
#
#   ovn_tools_pytest_py   prints the python interpreter that can `-m pytest`, or nothing.
#       order: $OVN_TOOLS_VENV/bin/python (default $HOME/overnight-queue/state/tools_venv), then the system python3 when it already has pytest.
#       OVN_TOOLS_RUNNER=off disables both (old behaviour: fail-closed). OVN_TOOLS_SYSTEM_PYTEST=off disables only the system python3 link.
#   ovn_tools_test_pkgs <repo_dir>   prints one package dir per line (relative to the repo, '.' for root): the parent of every */tests/test_*.py dir (no cap).
#   ovn_tools_pytest_run <python> <pkg_dir> <timeout_s> <pytest args...>   runs pytest ISOLATED (review advisory a, 2026-11-15): `python -I -c 'import pytest; sys.path.append(pkg); pytest.main(args)'` from the package dir. -I (isolated mode) keeps the
#       cwd AND PYTHONPATH off sys.path and skips user site, so a repo-controlled pytest.py stub or sitecustomize.py can neither replace pytest nor fake a green (rc 0 on a failing test). The package is
#       made importable by APPENDING it to sys.path only AFTER pytest is imported (it can neither shadow pytest nor stdlib), not via PYTHONPATH. (pytest's `-o pythonpath=` was rejected: it asserts when the repo has no ini file.) -p no:cacheprovider writes nothing into the repo.
ovn_tools_pytest_py() {
  [ "${OVN_TOOLS_RUNNER:-on}" = off ] && return 0
  local v="${OVN_TOOLS_VENV:-$HOME/overnight-queue/state/tools_venv}" p
  for p in "$v/bin/python" "$( [ "${OVN_TOOLS_SYSTEM_PYTEST:-on}" = off ] || command -v python3 2>/dev/null)"; do
    # probe from a NEUTRAL cwd (/) and isolated: a pytest.py / sitecustomize.py in the caller's cwd (the repo) must not satisfy the probe
    [ -n "$p" ] && [ -x "$p" ] && ( cd / && "$p" -I -c 'import pytest' ) >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  return 0
}
ovn_tools_pytest_run() {
  local py="$1" pkg="$2" to="$3"; shift 3
  ( cd "$pkg" && timeout "$to" "$py" -I -c 'import sys, pytest; sys.path.append(sys.argv[1]); sys.exit(pytest.main(sys.argv[2:]))' "$pkg" -q -o addopts="" -p no:cacheprovider "$@" )
}
# every package is returned (no cap: a 7th package must never be silently skipped); maxdepth 4 bounds the search
ovn_tools_test_pkgs() {
  local rd="${1:-.}" f d
  find "$rd" -maxdepth 4 -path '*/tests/test_*.py' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sort | while IFS= read -r f; do
    d="$(dirname "$(dirname "$f")")"; d="${d#"$rd"}"; d="${d#/}"; printf '%s\n' "${d:-.}"
  done | awk '!s[$0]++'
}
