# BASH_ENV hook for line-coverage of the pipeline's bash scripts (2026-09-30). Sourced by EVERY non-interactive bash
# (scripts, subshell `bash x.sh` calls, shebang runs) when OVN_COV_DIR is set: turns on xtrace into a per-process file with a
# compact, parseable PS4. Aggregated by scripts/cov/ovn_cov_report.py. No effect when OVN_COV_DIR is unset.
if [ -n "${OVN_COV_DIR:-}" ]; then
  { exec 97>>"$OVN_COV_DIR/bash.$$.x"; } 2>/dev/null && {
    BASH_XTRACEFD=97
    PS4='@@${BASH_SOURCE[0]:-?}:${LINENO}@@ '
    set -x
  }
fi
