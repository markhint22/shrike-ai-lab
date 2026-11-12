#!/usr/bin/env bash
# lib_gradle_scope.sh - scope the staged-landing gradle FULL verify to cycles that can actually affect the Android build (2026-11-12, q-verify-speed).
#
# Measured 2026-11-12: ovn_stage_runner.sh full_verify ran `gradlew test` (~209 s) on EVERY staged landing, even a one-file backend test change
# (iptv cycle: 79 s generation, 188 s pytest, 209 s gradle). The hygiene gate (branch_hygiene.sh) still runs gradle on every develop merge, so a
# backend/web/docs-only diff that skips it here cannot reach develop unverified.
#
# ovn_gradle_scope_needed <gdir_rel> <changed_files_newline_list> [item_text]
#   rc 0 = run the gradle full verify, rc 1 = skip it (diff proven non-native). FAIL SAFE: anything unknown runs.
#   run when: OVN_STAGE_GRADLE_SCOPE=off | changed list empty/unknown | any changed path is native/Android | the item text names gradle.
#   native = under <gdir_rel>/ , android/ , app/src/ , res/ ; *.kt *.kts *.gradle *.java *.pro ; gradle.properties gradlew(.bat) libs.versions.toml AndroidManifest.xml; gradle/ dir.
ovn_gradle_path_is_native() {
  local p="${1#./}"
  case "$p" in
    android/*|*/android/*|app/src/*|*/app/src/*|res/*|*/res/*|gradle/*|*/gradle/*) return 0 ;;
    *.kt|*.kts|*.gradle|*.java|*.pro|*/gradle.properties|gradle.properties|*/gradlew|gradlew|*/gradlew.bat|gradlew.bat|*/libs.versions.toml|libs.versions.toml|*/AndroidManifest.xml|AndroidManifest.xml) return 0 ;;
  esac
  return 1
}
ovn_gradle_scope_needed() {
  local gdir="${1#./}" changed="$2" item="${3:-}" p
  [ "${OVN_STAGE_GRADLE_SCOPE:-on}" = off ] && return 0
  [ -z "$changed" ] && return 0                                   # diff could not be computed (or is empty) -> run, as before
  case "$item" in *[Gg][Rr][Aa][Dd][Ll][Ee]*) return 0 ;; esac    # the item's own VERIFY names gradle
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in "$gdir"/*) return 0 ;; esac
    ovn_gradle_path_is_native "$p" && return 0
  done <<< "$changed"
  return 1
}
# ovn_gradle_changed_files <worktree> <base_ref_or_sha> : newline list of paths changed vs base (committed + working tree + untracked); prints nothing and returns 1 if it cannot be computed.
ovn_gradle_changed_files() {
  local wt="$1" base="$2" out un
  [ -n "$base" ] || return 1
  out="$(git -C "$wt" diff --name-only --no-renames "$base" -- 2>/dev/null)" || return 1
  un="$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" || return 1
  printf '%s\n' "$out" "$un" | sed '/^$/d'
}
