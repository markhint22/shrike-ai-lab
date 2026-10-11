#!/usr/bin/env bash
# 2026-10-10 (package qagate, analysis[6] BX-05): the stage runner's decompose prompt tells the model to put any new helper in the file that calls it and never in
# an unrelated module (xlite damage.gd carried two caller-less helpers). OVN_STAGE_HELPER_HINT=off drops the paragraph (prompt unchanged). Uses the hermetic
# fixture (stub LLM records the request body); the verdict is on the prompt text only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
GD_ITEM='[T3] game/x.gd — Add static function foo to x.gd. VERIFY: `gdparse game/x.gd` (cat:godot)'

osr_new; osr_godot ok; osr_plan default '[]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$GD_ITEM"
t "godot item: the decompose prompt carries the HELPERS rule" bash -c "grep -q 'HELPERS: put any new helper function in the SAME file that calls it' '$T/llm/body.1'"
t "godot item: the rule forbids helpers in unrelated modules with no caller" bash -c "grep -q 'NEVER add a helper to a different or unrelated module' '$T/llm/body.1'"
t "godot item: the existing SOURCE-ONLY rules are still there (the hint is appended, nothing replaced)" bash -c "grep -q 'GODOT 4 MODE' '$T/llm/body.1'"
osr_cleanup

osr_new; osr_plan default '[]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "non-godot item: the HELPERS rule is there too, next to the self-verifying rules" bash -c "grep -q 'HELPERS: put any new helper function' '$T/llm/body.1' && grep -q 'SELF-VERIFYING' '$T/llm/body.1'"
osr_cleanup

osr_new; osr_godot ok; osr_plan default '[]'
OVN_STAGE_HELPER_HINT=off OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO" "$GD_ITEM"
t "KILL SWITCH OVN_STAGE_HELPER_HINT=off: no HELPERS paragraph (prompt as before)" bash -c "[ -s '$T/llm/body.1' ] && ! grep -q 'HELPERS:' '$T/llm/body.1' && grep -q 'GODOT 4 MODE' '$T/llm/body.1'"
osr_cleanup
osr_summary
