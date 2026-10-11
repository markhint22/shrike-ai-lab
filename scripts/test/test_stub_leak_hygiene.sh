#!/usr/bin/env bash
# test_stub_leak_hygiene.sh - r11 package stub (5): the branch_hygiene run_gate STUB-LEAK FLAG (shadow). A merge candidate holding a non-test source file
# whose WHOLE content is the generated 'Placeholder - the implement step fills this in.' marker is flagged in the hygiene log + state/stub_leak_<repo>.txt
# (blocks only with OVN_STUB_LEAK=enforce; off disables; test-file placeholders are informational). The deployed block is extracted from
# branch_hygiene.sh and run for real (not mirrored), so the test cannot drift from the script.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="${OVN_BRANCH_HYGIENE:-$HERE/../../branch_hygiene.sh}"
[ -f "$BH" ] || { echo "  SKIP: $BH not found"; exit 0; }
SD="$(cd "$(dirname "$BH")" && pwd)"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }

BLOCK="$(sed -n '/# stub-leak FLAG (r11, package stub; SHADOW)/,/^  # web build+test/p' "$BH" | sed '$d')"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the stub-leak block from $BH"; exit 1; }
[ "$(printf '%s\n' "$BLOCK" | grep -c 'ovn_stub_guard.py" scan')" = 1 ] || { echo "  FAIL: expected exactly one scan call in the extracted block"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
LOGF="$W/hygiene.log"; : > "$LOGF"
log(){ echo "[branch-hygiene] $*" >> "$LOGF"; }
mkdir -p "$W/state"
gate_fn(){   # the extracted block, wrapped as the function it lives in; rc 0 = continues to the next gate
  local repo="$1" dir="$2"
  eval "$BLOCK"
  return 0
}
run(){ : > "$LOGF"; SCRIPT_DIR="$SD" STATE_DIR="$W/state" gate_fn "$1" "$2"; echo $?; }

M='Placeholder - the implement step fills this in.'
mkdir -p "$W/clone/app" "$W/clone/tests"
( cd "$W/clone" && git init -q -b main . && printf 'x=1\n' > app/real.py && git add -A && git commit -q -m init )
eq "clean tree: gate continues (rc 0)" "$(run "$W/clone" "$W/clone")" "0"
ok "clean tree: nothing logged, no state file" '[ ! -s "$LOGF" ] && [ ! -e "$W/state/stub_leak_clone.txt" ]'

printf '// %s\n' "$M" > "$W/clone/app/Leaked.kt"; printf '"""%s"""\n' "$M" > "$W/clone/tests/test_leaked.py"
( cd "$W/clone" && git add -A && git commit -q -m leak )
eq "SHADOW (default): a leaked source stub does NOT block (rc 0)" "$(run "$W/clone" "$W/clone")" "0"
ok "SHADOW: the leak is flagged in the hygiene log, naming the file" 'grep -q "STUB-LEAK FLAG (shadow).*app/Leaked.kt" "$LOGF"'
ok "SHADOW: the test placeholder is NOT in the flag line" '! grep -q "test_leaked" "$LOGF"'
ok "SHADOW: state/stub_leak_<repo>.txt lists SOURCE and TEST rows" 'grep -qxF "SOURCE	app/Leaked.kt" "$W/state/stub_leak_clone.txt" && grep -qxF "TEST	tests/test_leaked.py" "$W/state/stub_leak_clone.txt"'
eq "ENFORCE: the same candidate blocks the merge (rc 1)" "$(OVN_STUB_LEAK=enforce run "$W/clone" "$W/clone")" "1"
ok "ENFORCE: logged as enforce" 'grep -q "STUB-LEAK FLAG (enforce)" "$LOGF"'
eq "OFF: nothing flagged, never blocks" "$(OVN_STUB_LEAK=off run "$W/clone" "$W/clone")" "0"
ok "OFF: no log line" '! grep -q STUB-LEAK "$LOGF"'

# the worktree ($dir) is what is scanned, not the clone ($repo)
mkdir -p "$W/wt/app"; printf 'x=2\n' > "$W/wt/app/real.py"; ( cd "$W/wt" && git init -q -b main . && git add -A && git commit -q -m init )
eq "the merge-candidate WORKTREE is scanned (clean worktree + leaky clone = no flag)" "$(OVN_STUB_LEAK=enforce run "$W/clone" "$W/wt")" "0"
ok "clean worktree: stale state file is removed" '[ ! -e "$W/state/stub_leak_clone.txt" ]'

# test-only placeholders never flag
mkdir -p "$W/t2/tests"; printf '# %s\n' "$M" > "$W/t2/tests/test_x.gd"; ( cd "$W/t2" && git init -q -b main . && git add -A && git commit -q -m x )
eq "test-only placeholder: no flag even in enforce" "$(OVN_STUB_LEAK=enforce run "$W/t2" "$W/t2")" "0"
ok "test-only placeholder: listed (informational) in the state file" 'grep -qxF "TEST	tests/test_x.gd" "$W/state/stub_leak_t2.txt"'

# fail-safe: guard script missing = no-op
SD_SAVE="$SD"; SD="$W/empty"; mkdir -p "$SD"
eq "guard script absent: no-op, never blocks (fail-safe)" "$(OVN_STUB_LEAK=enforce run "$W/clone" "$W/clone")" "0"
SD="$SD_SAVE"

echo "stub-leak-hygiene: $P passed, $F failed"
[ "$F" -eq 0 ]
