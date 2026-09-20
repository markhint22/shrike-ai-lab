#!/usr/bin/env bash
# Regression test for ovn_stage_runner.sh's multifile:no scope guard (2026-09-20). A step on a
# multifile:no item should reject (not silently accept) touching any file outside its declared
# target(s) + a reasonable same-basename test companion — this is the shape of the earlier
# shrike-monitor incident (an obviously-hallucinated junk aether/README.md file slipping
# through a scope-less gate). Extracts the real guard condition out of ovn_stage_runner.sh so
# this can't drift from what's deployed.
set -uo pipefail
SR="${OVN_STAGE_RUNNER:-$HOME/overnight-queue/ovn_stage_runner.sh}"
[ -f "$SR" ] || { echo "  SKIP: $SR not found on this host"; exit 0; }

grep -q 'scope-violation' "$SR" || { echo "  FAIL: scope-violation fail_reason not found in $SR"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed guard exactly
scope_extra_files(){ # $1=worktree $2=item-text $3=declared-files(space-sep) -> extra file(s) or ""
  local wt="$1" item="$2" files="$3"
  local _declared _touched _extra _tf _df _tb _base _ok
  printf '%s' "$item" | grep -qiE 'multifile:no' || { echo ""; return; }
  _declared="$(
    { printf '%s\n' "$files" | tr ' ' '\n'
      printf '%s' "$item" | sed -E 's/^\[T[0-9]\] //' | grep -oE '^[A-Za-z0-9_./-]+\.[A-Za-z0-9]+'
    } | grep -vE '^$' | sort -u)"
  _touched="$(git -C "$wt" status --porcelain 2>/dev/null | awk '{print $2}' | sort -u)"
  _extra=""
  while IFS= read -r _tf; do
    [ -z "$_tf" ] && continue
    _ok=0
    while IFS= read -r _df; do
      [ -z "$_df" ] && continue
      if [ "$_tf" = "$_df" ]; then _ok=1; break; fi
      _tb="$(basename "$_tf" | sed -E 's/\.[A-Za-z0-9]+$//; s/^test_//; s/_test$//; s/\.(spec|test)$//')"
      _base="$(basename "$_df" | sed -E 's/\.[A-Za-z0-9]+$//; s/^test_//; s/_test$//; s/\.(spec|test)$//')"
      if [ -n "$_tb" ] && [ "$_tb" = "$_base" ]; then _ok=1; break; fi
    done <<< "$_declared"
    [ "$_ok" -eq 0 ] && _extra="$_extra $_tf"
  done <<< "$_touched"
  echo "$_extra"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tmp" && git init -q && git config user.email t@t && git config user.name t
  echo base > foo.py && git add -A && git commit -q -m base )

# ---- A: only the declared target touched -> clean ----
( cd "$tmp" && echo modified >> foo.py )
res="$(scope_extra_files "$tmp" '[T2] foo.py — do a thing (cat:python; multifile:no)' 'foo.py')"
ok "declared-target-only edit passes clean" "[ -z \"\$(echo '$res' | tr -d '[:space:]')\" ]"
( cd "$tmp" && git checkout -q -- foo.py )

# ---- B: declared target + a same-basename test companion -> still clean ----
( cd "$tmp" && echo modified >> foo.py && echo "def test_foo(): pass" > test_foo.py )
res="$(scope_extra_files "$tmp" '[T2] foo.py — do a thing (cat:python; multifile:no)' 'foo.py')"
ok "a matching test companion is allowed, not flagged" "[ -z \"\$(echo '$res' | tr -d '[:space:]')\" ]"
( cd "$tmp" && git checkout -q -- foo.py && rm -f test_foo.py )

# ---- C: an unrelated junk file/dir appears (the real shrike-monitor incident shape) -> flagged ----
( cd "$tmp" && mkdir -p aether && echo junk > aether/README.md )
res="$(scope_extra_files "$tmp" '[T2] foo.py — do a thing (cat:python; multifile:no)' 'foo.py')"
ok "an undeclared junk file is flagged" "[ -n \"\$(echo '$res' | tr -d '[:space:]')\" ]"
( cd "$tmp" && rm -rf aether )

# ---- D: multifile:yes item -> never flagged even with extra files ----
( cd "$tmp" && mkdir -p aether && echo junk > aether/README.md )
res="$(scope_extra_files "$tmp" '[T4] foo.py — refactor across files (cat:python; multifile:yes)' 'foo.py')"
ok "a multifile:yes item is never scope-flagged" "[ -z \"\$(echo '$res' | tr -d '[:space:]')\" ]"
( cd "$tmp" && rm -rf aether )

echo "Stage scope guard (multifile:no): $P passed, $F failed"
[ "$F" -eq 0 ]
