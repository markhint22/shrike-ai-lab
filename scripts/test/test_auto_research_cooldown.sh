#!/usr/bin/env bash
# ovn_auto_research.sh cooldown policy: long after an EMPTY pass (repo may be complete), short after a PRODUCTIVE pass (fleet burns the items, repo starves again).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SRC="$HERE/../../ovn_auto_research.sh"
[ -f "$SRC" ] || SRC="$HERE/../ovn_auto_research.sh"
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed -n '/^COOLDOWN_EMPTY_H=/,/^}/p' "$SRC" > "$T/fn.sh"
[ -s "$T/fn.sh" ] || { echo "  FAIL: could not extract ar_cooldown_s"; echo "auto research cooldown: 0 passed, 1 failed"; exit 1; }
source "$T/fn.sh"
ok "NEGATIVE: last pass accepted 0 items -> 18h (do not re-research a complete repo every run)" "$([ "$(ar_cooldown_s 0)" = 64800 ] && echo 1 || echo 0)"
ok "no marker / empty count -> 18h (safe default)" "$([ "$(ar_cooldown_s '')" = 64800 ] && echo 1 || echo 0)"
ok "garbage count -> 18h (safe default)" "$([ "$(ar_cooldown_s 'x')" = 64800 ] && echo 1 || echo 0)"
ok "BENIGN: last pass accepted 5 items -> 2h (starved lane gets refueled again)" "$([ "$(ar_cooldown_s 5)" = 7200 ] && echo 1 || echo 0)"
ok "env override works (productive cooldown 1h)" "$([ "$(OVN_AR_COOLDOWN_PRODUCTIVE_H=1; COOLDOWN_PRODUCTIVE_H=1; ar_cooldown_s 3)" = 3600 ] && echo 1 || echo 0)"
ok "the script writes the accepted count marker next to the time marker" "$(grep -q 'researched_n_\$repo' "$SRC" && echo 1 || echo 0)"
ok "reads a FRESH detached checkout of origin/overnight/feature, not the clone's working tree" "$(grep -q 'worktree add -q --detach "$src" origin/overnight/feature' "$SRC" && grep -q -- '--add-dir "$src"' "$SRC" && echo 1 || echo 0)"
ok "NEGATIVE: the prompt no longer points the agent at the stale clone path" "$(grep -q 'Its local clone is' "$SRC" && echo 0 || echo 1)"
ok "the fresh checkout is removed after the pass" "$(grep -q 'worktree remove --force "$src"' "$SRC" && echo 1 || echo 0)"
ok "prompt carries the quality rules (no uncalled helpers, verify deletions, tests only where collected, <=2 test-only items)" "$(grep -q 'NEVER propose adding a new standalone helper' "$SRC" && grep -q 'iptv-backend/tests/ ONLY' "$SRC" && grep -q 'at most 2 test-only items' "$SRC" && echo 1 || echo 0)"
echo "auto research cooldown: $P passed, $F failed"; [ "$F" = 0 ]
