#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 1): ovn_normalize_path must not depend on a pipe when it tests exact tracked-path membership.
# The old `printf '%s\n' "$tracked" | grep -qxF "$extracted"` returned rc 141 (SIGPIPE on the writer) under `set -o pipefail` as soon as the
# `git ls-files` list exceeded the pipe buffer: iptv's list (69,812 B) made 841 of 1371 tracked paths resolve to NOMATCH, 29 'path mismatch'
# credit refusals in 24h, 7 churn landings on routers/subscription.py. The fixture here is built in a temp repo's INDEX only (no files), sorted so that
# the paths under test come FIRST (grep -q exits at its first hit, so the writer is guaranteed to still be writing) and padded to ~200 KB so the pipe buffer
# (16-64 KB depending on the OS) can never swallow the whole list - that makes the OLD-function control deterministic instead of a race.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_path_normalize.sh"
[ -f "$LIB" ] || { echo "  FAIL: lib not found"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC1090
source "$LIB"
# the OLD implementation, verbatim (pre-2026-10-09), kept as a mutation control
old_normalize_path() {
  local repo_dir="$1" extracted="$2" tracked real base cand
  if [ -z "$extracted" ]; then printf '%s\n' "$extracted"; return; fi
  tracked="$(git -C "$repo_dir" ls-files 2>/dev/null)"
  if [ -z "$tracked" ] || printf '%s\n' "$tracked" | grep -qxF "$extracted"; then printf '%s\n' "$extracted"; return; fi
  real=""
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    case "$cand" in */"$extracted") real="$cand"; break ;; esac
  done <<< "$tracked"
  if [ -z "$real" ]; then
    base="$(basename "$extracted")"
    while IFS= read -r cand; do
      [ -z "$cand" ] && continue
      case "$cand" in "$base"|*"/$base") real="$cand"; break ;; esac
    done <<< "$tracked"
  fi
  printf '%s\n' "${real:-$extracted}"
}
R="$tmp/repo"; mkdir -p "$R"
git -C "$R" init -q
blob="$(git -C "$R" hash-object -w --stdin </dev/null)"
IDX="$tmp/index-info.txt"
: > "$IDX"
for p in iptv-backend/app/models/subscription.py iptv-backend/app/routers/subscription.py \
         iptv-backend/app/routers/test_content_groups_rate_limit.py iptv-backend/tests/test_content_groups_rate_limit.py; do
  printf '100644 %s\t%s\n' "$blob" "$p" >> "$IDX"
done
i=0
while [ "$i" -lt 3000 ]; do
  printf '100644 %s\tiptv-backend/zz_filler/module_%04d/generated_component_with_a_long_name_%04d.py\n' "$blob" "$i" "$i" >> "$IDX"
  i=$((i+1))
done
git -C "$R" update-index --add --index-info < "$IDX"
LIST="$(git -C "$R" ls-files)"
SZ=${#LIST}; N="$(git -C "$R" ls-files | wc -l | tr -d ' ')"
FIRST_SUB="$(git -C "$R" ls-files | grep -m1 'subscription.py')"
ok "fixture is big enough: >= 70000 bytes and > 1400 tracked paths (got $SZ bytes, $N paths)" "[ $SZ -ge 70000 ] && [ $N -gt 1400 ]"
ok "fixture: models/subscription.py sorts before routers/subscription.py" "[ '$FIRST_SUB' = iptv-backend/app/models/subscription.py ]"

# under pipefail (the runner's mode)
set -o pipefail
NEW1="$(ovn_normalize_path "$R" iptv-backend/app/routers/subscription.py)"
NEW2="$(ovn_normalize_path "$R" iptv-backend/tests/test_content_groups_rate_limit.py)"
NEW3="$(ovn_normalize_path "$R" tests/test_content_groups_rate_limit.py)"
NEW4="$(ovn_normalize_path "$R" iptv-backend/app/models/subscription.py)"
OLD1="$(old_normalize_path "$R" iptv-backend/app/routers/subscription.py)"
OLD2="$(old_normalize_path "$R" iptv-backend/tests/test_content_groups_rate_limit.py)"
# 20 repeated calls: the result must be stable, not a race
STABLE=1
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ "$(ovn_normalize_path "$R" iptv-backend/app/routers/subscription.py)" = iptv-backend/app/routers/subscription.py ] || STABLE=0
done
set +o pipefail

ok "NEW: routers/subscription.py maps to itself under pipefail on the big list" "[ '$NEW1' = iptv-backend/app/routers/subscription.py ]"
ok "NEW: result is stable across 20 consecutive calls (no SIGPIPE race)" "[ $STABLE = 1 ]"
ok "NEW: the real test file maps to itself, NOT to the ghost app/routers/test_*.py decoy" "[ '$NEW2' = iptv-backend/tests/test_content_groups_rate_limit.py ]"
ok "NEW: the short form tests/test_*.py resolves to the real tests/ file by suffix (not the decoy)" "[ '$NEW3' = iptv-backend/tests/test_content_groups_rate_limit.py ]"
ok "NEW: models/subscription.py (first in the list) maps to itself" "[ '$NEW4' = iptv-backend/app/models/subscription.py ]"
# MUTATION CONTROL: the old implementation, same fixture, same mode => false NOMATCH. Proves the fixture exceeds the pipe buffer.
ok "CONTROL: the OLD copy gets routers/subscription.py wrong (fixture really exceeds the pipe buffer)" "[ '$OLD1' != iptv-backend/app/routers/subscription.py ]"
ok "CONTROL: the OLD copy maps the real test file to the ghost decoy" "[ '$OLD2' = iptv-backend/app/routers/test_content_groups_rate_limit.py ]"
# negative controls: untracked / glob / partial path
ok "untracked path passes through unchanged on the big list" "[ \"\$(ovn_normalize_path '$R' ghost/none.py)\" = ghost/none.py ]"
ok "glob characters in the extracted path are matched literally (no accidental membership)" "[ \"\$(ovn_normalize_path '$R' 'iptv-backend/app/routers/*.py')\" = 'iptv-backend/app/routers/*.py' ]"
ok "a partial path resolves by suffix to the real tracked file" "[ \"\$(ovn_normalize_path '$R' 'routers/subscription.py')\" = iptv-backend/app/routers/subscription.py ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
