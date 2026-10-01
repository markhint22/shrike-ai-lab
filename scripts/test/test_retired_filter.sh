#!/usr/bin/env bash
# Regression: the doable-item filter must exclude only the real "(retired-...)" markers, never a
# feature tag that merely contains "retired-" (e.g. [feat:...-replace-retired-claude-model-ids]).
cd "$(dirname "$0")/../.." || exit 1
fail=0
ok(){ echo "ok - $1"; }; bad(){ echo "FAIL - $1"; fail=1; }
# 1. no bare retired- exclusion left in any filter
if grep -rnE "(\||\")retired-(\||'|\")" --include='*.sh' --include='*.py' . | grep -v '/test/' | grep -v 'tests/' | grep -q .; then bad "bare retired- exclusion present"; else ok "no bare retired- exclusion"; fi
# 2. queue_health's filter keeps the feature-tag item, drops real markers
f=$(mktemp); cat > "$f" <<'Q'
- [ ] [feat:x-replace-retired-claude-model-ids] do the thing
- [ ] (retired-dead-path) gone
- [ ] (retired-vague) vague
Q
n=$(grep -E '^- \[ \]' "$f" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|\(retired-' | wc -l | tr -d ' ')
[ "$n" = 1 ] && ok "filter counts 1 doable" || bad "filter counted $n"
rm -f "$f"
exit $fail
