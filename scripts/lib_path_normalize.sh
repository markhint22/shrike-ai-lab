#!/usr/bin/env bash
# scripts/lib_path_normalize.sh — normalize an extracted file-path-shaped token against a
# repo's real git-tracked file list (2026-09-28).
#
# Extracted from ovn_recover_parked.sh's RECOVERY_LINEAGE_CAP fix (2026-09-28): the same
# real file phrased two different ways across two mentions (e.g. a re-decomposed item
# wording it "backend/tests/test_x.py" one time and "tests/test_x.py" the next - both
# legitimate references to one file) used to hash to two different keys, silently
# bypassing whatever cap/counter the caller keys off wording alone. Shared here so every
# caller with this exact problem (ovn_recover_parked.sh's RECOVERY_LINEAGE_CAP,
# ovn_item_guard.sh's untagged-item streak key) uses the identical, tested normalization
# instead of each re-deriving (and potentially re-breaking) their own copy.
#
# Resolution order: an exact tracked-path match wins outright; otherwise prefer a tracked
# path ENDING in the extracted text (keeps directory context when it's present and
# correct - e.g. "tests/test_x.py" correctly resolves to "backend/tests/test_x.py" if
# that's the one real file ending in that suffix); otherwise fall back to a basename-only
# match (handles a directory-prefix mismatch). Returns the extracted text UNCHANGED when
# nothing in the tree matches at all (e.g. a not-yet-created target) - never errors, never
# returns empty for a non-empty input.
#
# Usage: source this file, then:
#   real="$(ovn_normalize_path "$repo_dir" "$extracted_path")"
#
# 2026-09-29 FIX: every return path used `printf '%s'` with NO trailing newline. A direct
# command-substitution caller ($(ovn_normalize_path ...)) is unaffected (bash strips
# trailing newlines from $() regardless), but the OTHER documented call shape - collecting
# results from a loop before deduplicating, e.g.
#   while IFS= read -r f; do ovn_normalize_path "$rd" "$f"; done | sort -u
# (exactly what ovn_recover_parked.sh's 2026-09-28 ALREADY-SATISFIED FILTER does to build
# its _checked_files list) - concatenates every call's output into ONE unbroken string with
# no separators, since nothing ever emits a newline between them. `sort -u` then sees a
# single "line", and the later `grep -qxF "$_itf_norm"` exact-line match against that one
# giant blob can never succeed for a repo with more than one checked-off file. Confirmed
# live: a gitlark recovery-decomposed duplicate of an already-[x]-checked TemporalNavigation
# item was NOT dropped despite the checked-off duplicate being present in the same file at
# generation time - this is why. Every return path now terminates with \n; safe for the
# direct-substitution callers (still stripped by $()) and now correct for the loop+sort
# caller too.
ovn_normalize_path() {
  local repo_dir="$1" extracted="$2" tracked real base cand
  if [ -z "$extracted" ]; then
    printf '%s\n' "$extracted"
    return
  fi
  tracked="$(git -C "$repo_dir" ls-files 2>/dev/null)"
  if [ -z "$tracked" ] || printf '%s\n' "$tracked" | grep -qxF "$extracted"; then
    printf '%s\n' "$extracted"
    return
  fi
  real=""
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    case "$cand" in
      */"$extracted") real="$cand"; break ;;
    esac
  done <<< "$tracked"
  if [ -z "$real" ]; then
    base="$(basename "$extracted")"
    while IFS= read -r cand; do
      [ -z "$cand" ] && continue
      case "$cand" in
        "$base"|*"/$base") real="$cand"; break ;;
      esac
    done <<< "$tracked"
  fi
  printf '%s\n' "${real:-$extracted}"
}
