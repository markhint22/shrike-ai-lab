#!/usr/bin/env bash
# Regression test for ovn_recover_parked.sh's already-satisfied filter (2026-09-28).
#
# A decomposed sub-item can resurface work that's ALREADY checked off elsewhere in
# OVERNIGHT_PROGRESS.md - the LLM decomposing a stuck item only sees the target file's
# current content and the stuck item's own text, never the rest of the file, so it can
# genuinely re-propose something a DIFFERENT already-landed item already covers.
# Confirmed live on shrike-monitor: an already-[x]-checked "already-satisfied" item's
# near-duplicate re-appeared as a fresh unchecked item in the same file, forcing a
# pointless re-attempt - the repo's own backlog notes independently flagged this same
# pattern twice.
#
# Extracts the real filter block out of ovn_recover_parked.sh (not a reimplementation) so
# this can't silently drift from what's deployed.
set -uo pipefail
RP="${OVN_RECOVER_PARKED:-$HOME/overnight-queue/ovn_recover_parked.sh}"
[ -f "$RP" ] || { echo "  SKIP: $RP not found on this host"; exit 0; }
LIB="${OVN_LIB_PATH_NORMALIZE:-$HOME/overnight-queue/scripts/lib_path_normalize.sh}"
[ -f "$LIB" ] || { echo "  SKIP: lib_path_normalize.sh not found"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

BLOCK="$(sed -n '/^  # ALREADY-SATISFIED FILTER/,/^  cnt=\$(printf/p' "$RP")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the already-satisfied filter block from $RP"; exit 1; }
case "$BLOCK" in
  *'ALREADY-SATISFIED FILTER'*'ovn_normalize_path'*) : ;;
  *) echo "  FAIL: extracted block doesn't look like the expected filter:"; printf '%s\n' "$BLOCK"; exit 1 ;;
esac

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
say(){ :; }  # the real script's logger - a no-op here, we only assert on $items/$cnt

run_filter(){ # $1=rd $2=f $3=items(newline-separated) -> sets $items and $cnt, prints nothing
  local rd="$1" f="$2" items="$3" cnt _checked_files _kept _it _itf _itf_norm r=test
  eval "$BLOCK" >/dev/null 2>&1
  printf '%s' "$items"
}

# --- A: a real repo where the target file was already checked off under DIFFERENT wording
#     than this decomposition uses (short path vs full tracked path) - must be dropped ---
rd="$tmp/repoA"; mkdir -p "$rd/backend/tests"
( cd "$rd" && git init -q && git config user.email t@t.com && git config user.name t \
  && echo x > backend/tests/test_x.py && git add -A && git commit -q -m init )
f="$tmp/repoA_prog.md"
cat > "$f" << 'EOF'
- [x] [T2] `backend/tests/test_x.py` — already fixed earlier this week
EOF
items_in="- [ ] [T2] \`tests/test_x.py\` — add a missing edge case. VERIFY: \`pytest tests/test_x.py\`. (cat:test)
- [ ] [T2] \`backend/app/other.py\` — genuinely new work. VERIFY: \`pytest backend/tests/test_other.py\`. (cat:python)"
result="$(run_filter "$rd" "$f" "$items_in")"
ok "duplicate sub-item (already checked off under different wording) is dropped" \
   "! printf '%s' \"\$result\" | grep -q 'test_x.py.*add a missing edge case'"
ok "the genuinely new sub-item is kept" \
   "printf '%s' \"\$result\" | grep -q 'other.py'"
ok "exactly one sub-item survives" \
   "[ \$(printf '%s' \"\$result\" | grep -c '^- \[ \]') -eq 1 ]"

# --- B: nothing checked off yet in the file -> no filtering happens, all items survive ---
f2="$tmp/repoB_prog.md"
cat > "$f2" << 'EOF'
- [ ] [T2] `backend/app/unrelated.py` — some other open item
EOF
items_in2="- [ ] [T2] \`backend/tests/test_x.py\` — brand new work. VERIFY: \`pytest\`. (cat:test)"
result2="$(run_filter "$rd" "$f2" "$items_in2")"
ok "no checked-off lines at all: item survives untouched" \
   "printf '%s' \"\$result2\" | grep -q 'test_x.py'"

# --- C: a [CLAUDE] escalation note is NEVER filtered, even if its mentioned file happens
#     to already be checked off - it's a meta hand-off, not decomposed work to de-dup ---
items_in3="- [ ] [CLAUDE] backend/tests/test_x.py has been recovered too many times (recovery:escalated)"
result3="$(run_filter "$rd" "$f" "$items_in3")"
ok "[CLAUDE] escalation note survives the filter unconditionally" \
   "printf '%s' \"\$result3\" | grep -q '\[CLAUDE\]'"

echo "recover-parked already-satisfied filter: $P passed, $F failed"
[ "$F" -eq 0 ]
