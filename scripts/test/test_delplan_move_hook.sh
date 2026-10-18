#!/usr/bin/env bash
# 2026-10-11 (delplan F8): the REAL scripts/ovn_move_executor.py driven through ovn_executor_hook (lib_fixup.sh) - SHADOW by default (check only, 'would-apply' row, nothing edited),
# on: git mv + reference rewrite + repo verification + the item's own VERIFY + credit + push, every failure resets and is remembered, run_overnight.sh wiring, mutation control.
# Real git repos (bare origin), no network, no model. The repo verification is a stub (STUB_VERIFY).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log" OVN_EXECUTOR_LOG="$W/exec.log"
emit_alert(){ :; }
run_repo_verification(){ echo "${STUB_VERIFY:-pass}"; }
command -v md5sum >/dev/null 2>&1 || md5sum() { md5 -r | awk '{print $1 "  -"}'; }
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_verify_clause.sh"; . "$S/lib_fixup.sh"
unset OVN_MOVE_EXECUTOR OVN_DOC_EXECUTOR OVN_RUFF_EXECUTOR
OD="$W/ovn"; mkdir -p "$OD/scripts" "$OD/state"; cp "$S/ovn_move_executor.py" "$S/ovn_delete_executor.py" "$OD/scripts/"
ITEM='- [ ] [T3] scripts/battle/old_mgr.gd — Move file to `scripts/save/old_mgr.gd`. VERIFY: `test -f scripts/save/old_mgr.gd && ! test -f scripts/battle/old_mgr.gd`. (cat:refactor; multifile:yes) [feat:mv]'
mkrepo(){  # $1 name -> $R $BEFORE $TL (bare origin)
  R="$W/$1"; local b="$W/$1.git"; rm -rf "$R" "$b"
  git init -q --bare "$b"; git clone -q "$b" "$R" 2>/dev/null; cd "$R" || exit 1
  git checkout -q -b main; git config user.email t@t; git config user.name t
  mkdir -p scripts/battle; printf 'extends Node\n' > scripts/battle/old_mgr.gd
  printf '[autoload]\nMgr="*res://scripts/battle/old_mgr.gd"\n' > project.godot
  printf '## Next Steps\n%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m init; git push -q origin main 2>/dev/null
  BEFORE="$(git rev-parse HEAD)"; TL="$W/$1.log"; : > "$TL"; rm -rf "${OD:?}/state/exec_failed"; : > "$OVN_EXECUTOR_LOG"
}
hook(){ ovn_executor_hook move "$OD" "$R" "$1" main "$TL" "$BEFORE"; }
HASH="$(ovn_item_hash "$ITEM")"

# ---- shadow (default) ----
mkrepo s1; OUT="$(hook "$ITEM")"; RC=$?
ok "default mode is SHADOW: rc 1, nothing printed, repo untouched" "[ $RC = 1 ] && [ -z '$OUT' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -z \"\$(git status --porcelain)\" ] && [ -f scripts/battle/old_mgr.gd ]"
ok "shadow logs one move/shadow/would-apply row naming the files, and 'would apply' in the cycle log" "[ \"\$(grep -c \$'\\tmove\\tshadow\\twould-apply\\t$HASH\\t' '$OVN_EXECUTOR_LOG')\" = 1 ] && grep -q 'MOVE-EXECUTOR (shadow): would apply: scripts/battle/old_mgr.gd scripts/save/old_mgr.gd project.godot' '$TL'"
mkrepo s2; hook '- [ ] [T1] scripts/battle/old_mgr.gd — Add a function. VERIFY: `true`. (cat:test)' >/dev/null; RC=$?
ok "a non-move top item: rc 1 and NO log row (it is the normal case on every lane)" "[ $RC = 1 ] && [ ! -s '$OVN_EXECUTOR_LOG' ]"
mkrepo s3; OVN_MOVE_EXECUTOR=off hook "$ITEM" >/dev/null; RC=$?
ok "off: rc 1, nothing logged, repo untouched" "[ $RC = 1 ] && [ ! -s '$OVN_EXECUTOR_LOG' ] && [ -f scripts/battle/old_mgr.gd ]"
mkrepo s4; OVN_DOC_EXECUTOR=on OVN_RUFF_EXECUTOR=on hook "$ITEM" >/dev/null
ok "the doc / ruff switches do NOT enable the move executor" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"

# ---- on: success ----
mkrepo o1; OUT="$(OVN_MOVE_EXECUTOR=on hook "$ITEM")"; RC=$?
ok "on: rc 0 and status 'pushed(tests:pass) move-executor'" "[ $RC = 0 ] && [ '$OUT' = 'pushed(tests:pass) move-executor' ]"
ok "on: the file moved, the autoload path was rewritten, the old path is gone" "[ -f scripts/save/old_mgr.gd ] && [ ! -e scripts/battle/old_mgr.gd ] && grep -q 'res://scripts/save/old_mgr.gd' project.godot && ! grep -q 'scripts/battle/old_mgr' project.godot"
ok "on: commit 'chore(supply): move via deterministic executor' touching exactly the declared files" "git log --format=%s -3 | grep -qx 'chore(supply): move via deterministic executor' && [ \"\$(git show --name-only --format= HEAD~1 | sort | tr '\\n' ' ')\" = 'project.godot scripts/save/old_mgr.gd ' ]"
ok "on: the item is credited '(move via deterministic executor, verified)' and pushed to origin, tree clean" "grep -q '^- \\[x\\] (move via deterministic executor, verified) \\[T3\\]' OVERNIGHT_PROGRESS.md && [ \"\$(git rev-parse HEAD)\" = \"\$(git -C '$W/o1.git' rev-parse main)\" ] && [ -z \"\$(git status --porcelain)\" ]"
ok "on: an 'applied' row is logged with mode=on" "grep -q \$'\\tmove\\ton\\tapplied\\t$HASH\\t' '$OVN_EXECUTOR_LOG'"

# ---- on: failures ----
mkrepo f1; OUT="$(STUB_VERIFY=fail OVN_MOVE_EXECUTOR=on hook "$ITEM")"; RC=$?
ok "repo verification red => rc 1, reset to BEFORE_SHA (file back at the old path, project.godot restored), remembered, origin untouched" "[ $RC = 1 ] && [ -z '$OUT' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -f scripts/battle/old_mgr.gd ] && [ ! -e scripts/save/old_mgr.gd ] && grep -q 'scripts/battle/old_mgr' project.godot && [ -z \"\$(git status --porcelain)\" ] && [ -e '$OD/state/exec_failed/$HASH' ] && [ \"\$(git -C '$W/f1.git' rev-parse main)\" = '$BEFORE' ]"
OUT="$(OVN_MOVE_EXECUTOR=on hook "$ITEM")"; RC=$?
ok "a remembered failure is skipped (rc 1, nothing applied)" "[ $RC = 1 ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
BADITEM='- [ ] [T3] scripts/battle/old_mgr.gd — Move file to `scripts/save/old_mgr.gd`. VERIFY: `test -f scripts/nowhere/never.gd`. (cat:refactor; multifile:yes) [feat:mv2]'
mkrepo f2; printf '## Next Steps\n%s\n' "$BADITEM" > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m prog; git push -q origin main; BEFORE="$(git rev-parse HEAD)"
OUT="$(OVN_MOVE_EXECUTOR=on hook "$BADITEM")"; RC=$?
ok "the item's own VERIFY failing => reset, remembered, no push (the repo verification alone is not enough)" "[ $RC = 1 ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -f scripts/battle/old_mgr.gd ] && [ -e '$OD/state/exec_failed/$(ovn_item_hash "$BADITEM")' ]"

# ---- wiring ----
ok "run_overnight.sh has the MOVE-EXECUTOR block right after the RUFF-EXECUTOR block, before SUPPLY-RECHECK" "[ \"\$(grep -c '^    # >>> MOVE-EXECUTOR-BEGIN' '$RUN')\" = 1 ] && [ \"\$(grep -n '# <<< RUFF-EXECUTOR-END' '$RUN' | cut -d: -f1)\" -lt \"\$(grep -n '# >>> MOVE-EXECUTOR-BEGIN' '$RUN' | cut -d: -f1)\" ] && [ \"\$(grep -n '# <<< MOVE-EXECUTOR-END' '$RUN' | cut -d: -f1)\" -lt \"\$(grep -n '# >>> SUPPLY-RECHECK-BEGIN' '$RUN' | cut -d: -f1)\" ]"
ok "the block is ongoing-* only, defaults to shadow, needs the script, and calls the hook with kind move" "[ \"\$(grep -c 'OVN_MOVE_EXECUTOR:-shadow}\" != \"off\" \\] && \\[ -f \"\$SCRIPT_DIR/scripts/ovn_move_executor.py\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'ovn_executor_hook move \"\$SCRIPT_DIR\" \"\$PWD\"' '$RUN')\" = 1 ]"
ok "the block is a pass-through for the real run_overnight.sh syntax" "bash -n '$RUN'"

# ---- MUTATION: without the shadow branch an explicit/default shadow run applies for real ----
python3 - "$S/lib_fixup.sh" "$W/m_shadow.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = '  if [ "$mode" = shadow ]; then\n    echo "--- ${kind^^}-EXECUTOR (shadow): would apply: ${files} ---" >> "$tl"\n'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, '  if false; then\n    echo "--- ${kind^^}-EXECUTOR (shadow): would apply: ${files} ---" >> "$tl"\n'))
PY
mkrepo mu1; ( . "$W/m_shadow.sh"; ovn_executor_hook move "$OD" "$R" "$ITEM" main "$TL" "$BEFORE" >/dev/null )
ok "MUTATION: with the shadow branch removed the default (shadow) mode moves the file (HEAD changes) - the shadow tests above would fail" "[ \"\$(git rev-parse HEAD)\" != '$BEFORE' ]"
# ---- MUTATION: the old single `git add -- $files` aborts on the path the move removed, so the on-mode move can never land ----
python3 - "$S/lib_fixup.sh" "$W/m_add.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
i = s.index("  for f in $files; do\n    if [ -e \"$rd/$f\" ]")
j = s.index("  staged=\"$(git -C \"$rd\" diff --cached --name-only")
open(sys.argv[2], "w").write(s[:i] + '  git -C "$rd" add -- $files >>"$tl" 2>&1\n' + s[j:])
PY
mkrepo mu2; ( . "$W/m_add.sh"; OVN_MOVE_EXECUTOR=on ovn_executor_hook move "$OD" "$R" "$ITEM" main "$TL" "$BEFORE" >/dev/null )
ok "MUTATION: with the old single 'git add -- \$files' the on-mode move does NOT land (HEAD stays at BEFORE) - the success test above would fail" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
