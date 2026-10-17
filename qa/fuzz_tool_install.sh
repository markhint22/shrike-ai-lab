#!/usr/bin/env bash
# fuzz_tool_install.sh - make sure the ONE tool contract_fuzz needs (schemathesis) is installed, by REUSING the P1 tool-health installer (ops/qa_tools_install.sh).
#   bash qa/fuzz_tool_install.sh            # DRY RUN (default): what the P1 installer would do for schemathesis only; changes nothing
#   bash qa/fuzz_tool_install.sh --check    # exit 0 when schemathesis is present in the install venv, 1 when missing (read-only, health-check safe)
#   bash qa/fuzz_tool_install.sh --apply    # install schemathesis (and nothing else) into $OVN_DIR/qa-tools/.venv
# Why: the 2026-10-16 home wipe removed schemathesis; contract_fuzz then reports UNVERIFIED "schemathesis missing" every night. P1 (qa_tool_health.py) DETECTS that and
# ops/qa_tools_install.sh restores all QA tools in one dedicated venv (contract_fuzz.find_schemathesis looks there last). This wrapper only narrows that installer to
# schemathesis (QA_TOOLS_SKIP = every other tool) so installing the fuzz does not also pull semgrep/bandit/mutmut/gitleaks. There is deliberately no second installer
# here: same venv, same safety checks (path strictly under OVN_DIR, never a repo venv, never HOME), same version policy (schemathesis>=4,<5; the fuzz README was validated on 4.28.0).
# Never deletes anything itself. Exit codes are the P1 installer's; 2 = bad usage / the P1 installer is missing.
set -u
SELF="${BASH_SOURCE[0]:-$0}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" && pwd)" || exit 2
OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"; export OVN_DIR
INSTALLER="${OVN_FUZZ_TOOLS_INSTALLER:-$OVN_DIR/ops/qa_tools_install.sh}"
case "${1:-}" in --apply) ARGS="" ;; --check) ARGS="--check" ;; ""|--dry-run) ARGS="--dry-run" ;; *) echo "usage: $0 [--dry-run|--check|--apply]" >&2; exit 2 ;; esac
[ -f "$INSTALLER" ] || { echo "P1 installer not found: $INSTALLER (expected ops/qa_tools_install.sh next to qa/)" >&2; exit 2; }
export QA_TOOLS_SKIP="bandit semgrep pip-audit mutmut mypy ruff gitleaks"
echo "schemathesis only (QA_TOOLS_SKIP=$QA_TOOLS_SKIP) via $INSTALLER ${ARGS:-(apply)}"
if [ -n "$ARGS" ]; then exec bash "$INSTALLER" $ARGS; else exec bash "$INSTALLER"; fi
