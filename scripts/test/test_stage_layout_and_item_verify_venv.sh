#!/usr/bin/env bash
# 2026-10-18 (gitlark landing audit), two staged-runner defects found in the gitlark stage runs of 2026-10-17:
#   L  the decomposer's "Real source paths" block was `find | sort | head -100`: for gitlark it was backend/alembic x26 + backend/app x71, so backend/tests never reached the planner, which then
#      invented repo-root `tests/...` paths ("declared file is empty" x6, ghost tests/test_memory_migration.py that pytest never collects). stage_layout_listing keeps tests visible.
#   V  stage_item_verify_run ran the item's own VERIFY inside the stage worktree, which has no .venv: a bare `python` resolved to the box's aider-venv python (No module named pytest / jose), so every
#      python item VERIFY was FAIL before AND after the change and the item_verify verdict was noise. The repo clone's venv bin must lead PATH for the probe.
# Pure shell, no network: stub venv python, synthetic tree. Every block also runs the old behaviour (mutation proof the assertion can fail).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
SCRIPTS="$(cd "$HERE/.." && pwd)"
T="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_tree "$T" 2>/dev/null || true' EXIT
. "$SCRIPTS/lib_stage_guards.sh"

echo "== L: layout listing keeps test directories visible"
W="$T/wt"; mkdir -p "$W/backend/alembic/versions" "$W/backend/alembic.backup" "$W/backend/app/services" "$W/backend/tests" "$W/web/src" "$W/web/tests/api"
for i in $(seq 1 40); do : > "$W/backend/alembic/versions/m$i.py"; done
: > "$W/backend/alembic.backup/old.py"
for i in $(seq 1 90); do : > "$W/backend/app/services/svc$i.py"; done
for i in 1 2 3; do : > "$W/backend/tests/test_a$i.py"; done
: > "$W/web/tests/api/feed.spec.ts"; : > "$W/web/src/app.ts"
OLD="$(cd "$W" && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' \) -not -path '*/node_modules/*' | sed 's#^\./##' | sort | head -100)"
NEW="$(stage_layout_listing "$W")"
ok "L0 (old behaviour) the first-100 listing never mentions backend/tests" "$(printf '%s' "$OLD" | grep -q 'backend/tests' && echo 0 || echo 1)"
ok "L1 the new listing names backend/tests as a test directory with its count" "$(printf '%s' "$NEW" | grep -qF 'backend/tests/  (3 test files)' && echo 1 || echo 0)"
ok "L2 ... and web/tests/api" "$(printf '%s' "$NEW" | grep -qF 'web/tests/api/  (1 test files)' && echo 1 || echo 0)"
ok "L3 alembic / backup trees are not listed" "$(printf '%s' "$NEW" | grep -q 'alembic' && echo 0 || echo 1)"
ok "L4 source files still listed, bounded (<= 90 lines)" "$([ "$(printf '%s\n' "$NEW" | wc -l)" -le 90 ] && printf '%s' "$NEW" | grep -q 'web/src/app.ts' && echo 1 || echo 0)"
ok "L5 test files themselves are not mixed into the source block" "$(printf '%s' "$NEW" | grep -q 'test_a1.py' && echo 0 || echo 1)"

echo "== V: item VERIFY probe runs under the repo clone's venv python"
Q="$T/q"; mkdir -p "$Q/repos/r/backend/.venv/bin" "$T/bin" "$T/wtv/backend"
printf '#!/bin/sh\necho REPO-VENV-PYTHON\nexit 0\n' > "$Q/repos/r/backend/.venv/bin/python"; chmod +x "$Q/repos/r/backend/.venv/bin/python"
printf '#!/bin/sh\necho "No module named pytest" >&2\nexit 1\n' > "$T/bin/python"; chmod +x "$T/bin/python"   # the box's aider-venv python
ITEM='[T3] backend/app/x.py — do x. VERIFY: `python -c "import pytest"`. (cat:python; multifile:no)'
export OVN_STAGE_IV_SHADOW_LOG="$T/iv.log"
r_new="$(cd "$Q" && PATH="$T/bin:$PATH" OVN_STAGE_REPO=r stage_item_verify_run "$T/wtv" "$ITEM")"
r_old="$(cd "$Q" && PATH="$T/bin:$PATH" OVN_STAGE_REPO=r OVN_STAGE_REPO_DIR=/nonexistent stage_item_verify_run "$T/wtv" "$ITEM")"
ok "V0 (old behaviour: no repo venv) the bare python is the box's and the verdict is FAIL: $r_old" "$([ "${r_old%%|*}" = FAIL ] && echo 1 || echo 0)"
ok "V1 with the repo clone venv leading PATH the same clause is PASS: $r_new" "$([ "${r_new%%|*}" = PASS ] && echo 1 || echo 0)"
ok "V2 the probe left no file in the worktree" "$([ -z "$(ls -A "$T/wtv/backend")" ] && echo 1 || echo 0)"
echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
