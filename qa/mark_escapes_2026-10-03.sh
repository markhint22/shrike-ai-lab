#!/usr/bin/env bash
# mark_escapes_2026-10-03.sh - record this week's three real escapes in the QA ledger (qa_ledger.py mark-escape), from qa/gold_set.json.
# 2026-10-03 diagnosis F9: the week-defining escapes exist in the ledger only as weak 'hotfix' events (or not at all), so the escape-rate headline
# (3 strong in ~1028 landed) understates them. The three incidents:
#   billwatch  06435083  staged step 1 added POST /api/auth/reset-password with no token/auth (open account takeover)      gold G7
#   billwatch  ae047db6  DeleteAccountButton.vue created without its try/catch + test, bound to logout in ProfileView       gold G1
#   iptv_apps  1f92e120  fleet restored a docstring-only alembic 0011 (no revision): staging + prod deploys failed         gold G8
#
# SAFE BY DEFAULT: with no argument it only PRINTS the three commands (dry run) and touches nothing. To write:
#     MARK_ESCAPE_CONFIRM=yes OVN_DIR=<ovn dir> qa/mark_escapes_2026-10-03.sh --apply
# --apply refuses without MARK_ESCAPE_CONFIRM=yes. mark-escape is idempotent (an escape key already in the ledger is skipped), so a second run
# adds nothing. NOT run by the author against live state: the integrator runs it once on the box after deploy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
ROWS=(
  "billwatch|06435083508d955023563f36540d78ff318c6d89|G7: POST /api/auth/reset-password shipped with no token or auth (account takeover); removed by d52bdaf9 2026-10-03"
  "billwatch|ae047db63f344f4ed6603dda1f65cc9dc9041da4|G1: DeleteAccountButton gutted (try/catch + test removed), bound to logout in ProfileView; repaired on develop 2026-10-02"
  "iptv_apps|1f92e12053d01a2793bdef9edcee782c4c9666f4|G8: docstring-only alembic 0011_subscription_last_event_ms.py (no revision) failed staging + prod deploys 2026-10-03; removed by 7a986d1b"
)
if [ "$APPLY" = 1 ] && [ "${MARK_ESCAPE_CONFIRM:-}" != "yes" ]; then
  echo "refusing: --apply writes to the QA ledger; set MARK_ESCAPE_CONFIRM=yes (and OVN_DIR) to proceed" >&2
  exit 3
fi
rc=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r repo ref note <<<"$row"
  if [ "$APPLY" = 1 ]; then
    echo "== mark-escape $repo ${ref:0:8}"
    "$PY" "$HERE/qa_ledger.py" mark-escape --repo "$repo" --ref "$ref" --note "$note" || rc=1
  else
    printf 'DRY RUN: %s %s/qa_ledger.py mark-escape --repo %s --ref %s --note "%s"\n' "$PY" "$HERE" "$repo" "$ref" "$note"
  fi
done
exit $rc
