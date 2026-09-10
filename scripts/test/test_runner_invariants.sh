#!/usr/bin/env bash
# Structural regression guards: FAIL if a critical run_overnight.sh fix is removed/reordered.
set -uo pipefail
R="${OVN_RUNNER:-$HOME/overnight-queue/run_overnight.sh}"
G="${OVN_SCRIPTS:-$HOME/overnight-queue/scripts}/ovn_item_guard.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
lno(){ grep -nE "$1" "$R" | head -1 | cut -d: -f1; }

# 1) BEFORE_SHA re-captured AFTER self-gen (else self-gen items discarded every cycle)
ok "BEFORE_SHA re-capture present" "grep -q 'Re-capture BEFORE_SHA AFTER' $R"
sg=$(lno 'auto-generate safe mechanical items'); bs=$(lno 'Re-capture BEFORE_SHA AFTER')
ok "BEFORE_SHA re-capture is AFTER self-gen commit" "[ -n '$sg' ] && [ -n '$bs' ] && [ $bs -gt $sg ]"

# 2) scout-commit continues (does NOT abort the cycle)
ok "scout-commit no longer aborts" "! grep -q 'error(scout committed unexpectedly)' $R"
ok "scout-commit reset+continue present" "grep -q 'CONTINUING to implement' $R"

# 3) valve counts ONLY reverted (not error), threshold raised
ok "valve: only reverted counts" "grep -qE '^[[:space:]]*reverted\*\)' $R && ! grep -qE 'error\*\|reverted\*\)' $R"
ok "valve: threshold raised to 8" "grep -q 'MAX_CONSECUTIVE_FAILURES=8' $R"

# 4) double-jeopardy: item-guard runs BEFORE task-valve, and resets it on park
ig=$(lno 'ovn_item_guard.sh'); cr=$(lno 'check_and_record_failure "\$ID"')
ok "item-guard runs before task-valve" "[ -n '$ig' ] && [ -n '$cr' ] && [ $ig -lt $cr ]"
ok "item-guard resets task-valve on park" "grep -q 'give the REPO a fresh start' $G"

# 5) push-heal
ok "push rejection self-heals (rebase-retry)" "grep -q 'rebasing onto origin' $R"

# 6) all the pieces are wired
ok "self-gen wired" "grep -q 'ovn_generate_items.py' $R"
ok "classification logging wired" "grep -q 'ovn_classify.py' $R"
ok "credit helper wired" "grep -q 'ovn_credit_already_satisfied.sh' $R"
ok "sanitizer wired (scripts/ path)" "grep -q 'scripts/ovn_retire_vague.py' $R"

# 7) exhausted-repo skip (2026-08-31): a 0-doable repo is skipped, not no-op'd
ok "exhausted-repo skip present" "grep -q 'skip(exhausted)' $R"
ok "exhausted skip is AFTER self-gen" "es=\$(lno 'skip\(exhausted\)'); sg2=\$(lno 'auto-generate safe mechanical items'); [ -n \"\$es\" ] && [ -n \"\$sg2\" ] && [ \$es -gt \$sg2 ]"

# 8) no-op guard (2026-08-31): the item-guard now parks repeat-no-op items
ok "guard counts no-op streaks" "grep -q 'No-op streak' $G"
ok "guard parks no-op items AUTO-SKIP" "grep -q 'AUTO-SKIP after' $G"

echo "Runner invariants: $P passed, $F failed"
[ "$F" -eq 0 ]
