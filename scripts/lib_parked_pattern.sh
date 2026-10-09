#!/usr/bin/env bash
# scripts/lib_parked_pattern.sh - the bash twin of scripts/ovn_backlog_eligibility.py's PARKED_CI / PARKED_CS (spec-compiler-v2, 2026-10-09).
#
# A progress/backlog line is "parked" (not for the 27B) when it carries one of the case-insensitive tags OR the case-sensitive tag BLOCKED. `BLOCKED` used to be
# matched case-insensitively (`grep -viE '...|BLOCKED|...'`), which parked every line that merely contained the word blocked / unblocked / test_x_blocked /
# blocked_reason (all 10 open iptv_apps items and both open xlite items on 2026-10-09). The harness writes the TAG in capitals (`BLOCKED ITEM`), so only that matches.
#
# Usage (two greps, one per variable - never put BLOCKED into the -i alternation again; a site that needs extra case-insensitive alternatives appends them):
#   grep -viE "$OVN_PARKED_CI_ERE" | grep -vE "$OVN_PARKED_CS_ERE"
#
# DEPLOY ORDER (reviewer audit 2026-10-09, resolved in round 3): other sites used to match BLOCKED case-insensitively and would treat a lowercase-"blocked" item as parked once
# queue_refill pulled it. Now: (1) every such site that no other package owns was converted in this package (lib_bug_escalate.sh, ovn_credit_items.py, ovn_alembic_credit.py,
# ovn_fold_migration_items.py, ovn_park_unworkable.py, ovn_batch_stragglers.py, qa/bug_brief.py); run_overnight.sh is converted by harness-credit-integrity; the rest
# (ovn_churn_guard.py, ovn_item_guard.sh, ovn_stale_top_item_check.py) convert with `python3 scripts/ovn_convert_blocked_sites.py <file>...` or the patches in docs/patches/.
# (2) ovn_backlog_eligibility.py audits the tree (`python3 scripts/ovn_backlog_eligibility.py sites`) and, while any site is left, KEEPS lowercase-"blocked" items parked
# in queue_refill (default OVN_PARKED_BLOCKED_CI=auto), so the unlock cannot happen before the pickers agree. OVN_PARKED_BLOCKED_CI=off forces the unlock, =on restores the
# legacy case-insensitive park everywhere (this library included).
# Converted forms (the audit and the converter know them): python `(?-i:BLOCKED)` inside a re.I pattern; shell `grep -viE 'A|B' | grep -vE 'BLOCKED'`.
# Sourcing is idempotent (plain assignment: every site sees the SAME patterns, an env leftover cannot weaken one). Callers keep an identical inline fallback
# for a missing library.
OVN_PARKED_CI_ERE='AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|\[CLAUDE\]'
OVN_PARKED_CS_ERE='BLOCKED'
# kill switch (same name as the python side): OVN_PARKED_BLOCKED_CI=on restores the legacy case-insensitive BLOCKED
[ "${OVN_PARKED_BLOCKED_CI:-off}" = on ] && OVN_PARKED_CI_ERE="$OVN_PARKED_CI_ERE|BLOCKED"
:   # never leave the sourcing shell with a non-zero status (set -e callers)
