#!/usr/bin/env bash
# test_gradle_scope.sh - q-verify-speed (2026-11-12): the stage runner's full_verify runs `gradlew test` only for diffs that can affect the native build.
# Covers: pure decision (backend-only skips, android runs, unknown runs, item-names-gradle runs, kill switch), a real git worktree diff, the wiring in
# ovn_stage_runner.sh, and MUTANTS of the lib (each must be caught by this very test body).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
LIB="$Q/scripts/lib_gradle_scope.sh"; SR="$Q/ovn_stage_runner.sh"
pass=0; fail=0
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
ok(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'rm -rf "${tmp:?}"' EXIT
unset OVN_STAGE_GRADLE_SCOPE

# battery: prints one line per case "name rc"; used for the real lib and for every mutant
battery(){ ( . "$1"
  c(){ ovn_gradle_scope_needed "$2" "$3" "${4:-}"; echo "$1 $?"; }
  c backend_only   iptv-android $'backend/app/x.py\nbackend/tests/test_x.py'
  c web_docs       iptv-android $'web/src/a.vue\nREADME.md\nscripts/foo.sh'
  c test_only      iptv-android $'backend/tests/test_y.py'
  c gdir_file      iptv-android $'backend/a.py\niptv-android/README.md'
  c kt             iptv-android $'backend/a.py\nfoo/Bar.kt'
  c kts            iptv-android $'build.gradle.kts'
  c gradle_props   iptv-android $'gradle.properties'
  c android_dir    iptv-android $'android/app/x.txt'
  c app_src        iptv-android $'app/src/main/y.txt'
  c res            iptv-android $'x/res/values/s.xml'
  c manifest       iptv-android $'x/AndroidManifest.xml'
  c unknown_empty  iptv-android ""
  c item_gradle    iptv-android $'backend/a.py' "tests: run ./gradlew test and check"
  c item_plain     iptv-android $'backend/a.py' "tests: pytest backend/tests/test_a.py"
  OVN_STAGE_GRADLE_SCOPE=off c kill_switch iptv-android $'backend/a.py'
  # near-miss names must NOT count as native
  c lookalike      iptv-android $'docs/android_notes.md\nbackend/kotlin_notes.txt\nbackend/ktx.py'
); }
exp_real="backend_only 1
web_docs 1
test_only 1
gdir_file 0
kt 0
kts 0
gradle_props 0
android_dir 0
app_src 0
res 0
manifest 0
unknown_empty 0
item_gradle 0
item_plain 1
kill_switch 0
lookalike 1"
ok "lib exists and parses" 'bash -n "$LIB"'
ok "decision table: backend/web/docs/test-only skip (1); android/kt/gradle/res/unknown/item-gradle/kill-switch run (0)" '[ "$(battery "$LIB")" = "$exp_real" ]'

# real git worktree diff
G="$tmp/g"; mkdir -p "$G"; git -C "$G" init -q -b main; git -C "$G" config user.email t@t; git -C "$G" config user.name t
mkdir -p "$G/backend" "$G/iptv-android"; echo a > "$G/backend/a.py"; echo b > "$G/iptv-android/settings.gradle.kts"; git -C "$G" add -A; git -C "$G" commit -qm base
BASE="$(git -C "$G" rev-parse HEAD)"
echo a2 > "$G/backend/a.py"; echo t > "$G/backend/test_new.py"                      # modified + untracked
ok "changed_files lists modified + untracked vs base" '[ "$(. "$LIB"; ovn_gradle_changed_files "$G" "$BASE" | sort | tr "\n" ,)" = "backend/a.py,backend/test_new.py," ]'
ok "backend-only worktree diff -> skip" '( . "$LIB"; ch="$(ovn_gradle_changed_files "$G" "$BASE")"; ! ovn_gradle_scope_needed iptv-android "$ch" "pytest" )'
git -C "$G" commit -qam c1 2>/dev/null; echo k > "$G/iptv-android/Z.kt"
ok "android file in the worktree diff -> run" '( . "$LIB"; ch="$(ovn_gradle_changed_files "$G" "$BASE")"; ovn_gradle_scope_needed iptv-android "$ch" "pytest" )'
# rename OUT of a native dir must list the OLD path (rename detection would show only the new, non-native name)
R="$tmp/r"; mkdir -p "$R"; git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
mkdir -p "$R/iptv-android"; printf 'package x\nclass X { fun a() = 1 }\n' > "$R/iptv-android/x.kt"; git -C "$R" add -A; git -C "$R" commit -qm base; RBASE="$(git -C "$R" rev-parse HEAD)"
git -C "$R" mv iptv-android/x.kt notes.txt
ok "rename iptv-android/x.kt -> notes.txt lists the old native path" '. "$LIB"; ovn_gradle_changed_files "$R" "$RBASE" | grep -qx "iptv-android/x.kt"'
ok "rename out of a native dir -> gradle NOT skipped" '( . "$LIB"; ch="$(ovn_gradle_changed_files "$R" "$RBASE")"; ovn_gradle_scope_needed iptv-android "$ch" "pytest" )'
ok "unknown base (unresolvable ref) -> changed_files fails -> run" '( . "$LIB"; ch="$(ovn_gradle_changed_files "$G" "no-such-ref-xyz" 2>/dev/null)"; [ -z "$ch" ] && ovn_gradle_scope_needed iptv-android "$ch" "pytest" )'
ok "empty base -> changed_files fails" '( . "$LIB"; ! ovn_gradle_changed_files "$G" "" )'
ok "not a git dir -> changed_files fails (safe: run)" '( . "$LIB"; ! ovn_gradle_changed_files "$tmp" "$BASE" 2>/dev/null )'

# wiring in the stage runner
ok "stage runner sources lib_gradle_scope.sh with a run-always fallback" 'grep -q "source scripts/lib_gradle_scope.sh" "$SR" && grep -q "ovn_gradle_scope_needed(){ return 0; }" "$SR"'
ok "the scope check sits before the gradle run inside full_verify" 'a=$(grep -n "ovn_gradle_scope_needed \"" "$SR" | head -1 | cut -d: -f1); b=$(grep -n "ovn_gradle_run \"\$gdir\"" "$SR" | head -1 | cut -d: -f1); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]'
ok "a skip is logged (visible in verify.log) and names the kill switch" 'grep -q "gradlew test FULL SKIPPED in" "$SR" && grep -q "OVN_STAGE_GRADLE_SCOPE=off restores" "$SR"'
ok "diff base is origin/overnight/feature (same base as the new-tests helper)" 'grep -q "ovn_gradle_changed_files \"\$wt\" \"\$(git -C \"\$wt\" rev-parse origin/overnight/feature" "$SR"'
ok "stage runner parses" 'bash -n "$SR"'

# MUTANTS: every one must change the battery result
mutant(){ # name sed-expr
  sed "$2" "$LIB" > "$tmp/m_$1.sh"; cmp -s "$LIB" "$tmp/m_$1.sh" && { fail=$((fail+1)); echo "  FAIL: mutant $1 did not change the lib"; return; }
  ok "MUTANT $1 is caught" '[ "$(battery "$tmp/m_'"$1"'.sh")" != "$exp_real" ]'; }
mutant unknown_skips      's/\[ -z "\$changed" \] \&\& return 0/[ -z "$changed" ] \&\& return 1/'
mutant no_kill_switch     's/\[ "\${OVN_STAGE_GRADLE_SCOPE:-on}" = off \] \&\& return 0/:/'
mutant no_kt              's/\*\.kt|//'
mutant no_res             's/|res\/\*|\*\/res\/\*//'
mutant no_android_dir     's/android\/\*|\*\/android\/\*|//'
mutant ignore_item        's/\*\[Gg\]\[Rr\]\[Aa\]\[Dd\]\[Ll\]\[Ee\]\*) return 0/*NEVERMATCH*) return 0/'
mutant no_gdir            's/"\$gdir"\/\*) return 0/"$gdir"\/NOPE) return 0/'
mutant always_run         's/^  return 1$/  return 0/'
sed 's/ --no-renames//' "$LIB" > "$tmp/m_rn.sh"; cmp -s "$LIB" "$tmp/m_rn.sh" && { fail=$((fail+1)); echo "  FAIL: mutant renames unchanged"; }
ok "MUTANT dropping --no-renames is caught (rename out of native dir would skip gradle)" '( . "$tmp/m_rn.sh"; ch="$(ovn_gradle_changed_files "$R" "$RBASE")"; ! ovn_gradle_scope_needed iptv-android "$ch" "pytest" )'
echo "gradle scope: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
