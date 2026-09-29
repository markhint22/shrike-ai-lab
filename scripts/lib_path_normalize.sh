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
ovn_normalize_path() {
  local repo_dir="$1" extracted="$2" tracked real base cand
  if [ -z "$extracted" ]; then
    printf '%s' "$extracted"
    return
  fi
  tracked="$(git -C "$repo_dir" ls-files 2>/dev/null)"
  if [ -z "$tracked" ] || printf '%s\n' "$tracked" | grep -qxF "$extracted"; then
    printf '%s' "$extracted"
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
  printf '%s' "${real:-$extracted}"
}
