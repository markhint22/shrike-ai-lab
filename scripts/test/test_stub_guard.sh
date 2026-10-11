#!/usr/bin/env bash
# test_stub_guard.sh - r11 package stub. Unit tests of scripts/ovn_stub_guard.py (the guards of run_overnight.sh's pre-scout "stub new source file"
# step + the leaked-placeholder scan). Pure python + git (no run_overnight.sh sourcing), so it runs on the Mac and on the box.
# End-to-end behaviour of the real cycle (stub step + EXIT-trap undo) is in test_stub_guard_e2e.sh.
#   X4/P1  a path whose last git change is a deletion is never stubbed; "asserts X does not exist" items never stub X
#   P5/F2  the extraction has a right boundary ('.kts' is not '.kt'); a longer-extension sibling refuses the stub
#   F3     a directory AGENTS.md declares out of scope is never stubbed under (unparsable/missing AGENTS.md declares nothing)
#   (3)    undo: an unfilled stub is removed on the way out (reset when unpushed tip, follow-up commit otherwise); a filled stub is kept
#   (5)    scan: placeholder-only SOURCE files are flagged, TEST ones informational, real files never
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${OVN_STUB_GUARD:-$HERE/../ovn_stub_guard.py}"
[ -f "$G" ] || { echo "  FAIL: $G not found"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
pick(){ printf '%s' "$2" | timeout 60 python3 "$G" pick "$1" | tr '\t' '|'; }

R="$W/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q -b main .
mkdir -p iptv-android/app scripts/battle scripts/mission iptv-web/src
echo 'plugins {}' > iptv-android/app/build.gradle.kts
echo 'extends Node' > scripts/battle/save_manager.gd
echo 'extends Node' > scripts/battle/readded.gd
echo 'x' > iptv-web/src/app.ts; echo 'x' > iptv-web/src/app.tsx
cat > AGENTS.md <<'EOF'
# AGENTS.md - Chickadee
Multi-platform. **Fleet scope = `iptv-backend` + `iptv-web` only.**
`iptv-ios/` (SwiftUI+tvOS) and `iptv-android/` (Compose+Hilt) are **out of scope** — never edit them.
- Never edit `addons/` (vendored GUT).
- Never edit `requirements.txt` to remove a package.
EOF
git add -A && git commit -q -m base
git rm -q scripts/battle/save_manager.gd scripts/battle/readded.gd && git commit -q -m "delete both"
mkdir -p scripts/battle; echo 'extends Node' > scripts/battle/readded.gd && git add -A && git commit -q -m "re-add one"

# ---- (2) right boundary: the legacy regex truncates .kts to .kt (reproduces the prod-main junk file); the picker does not ----
legacy(){ printf '%s' "$1" | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue|kt|swift)' | head -1; }
eq "REPRO legacy regex: .kts truncates to .kt (the defect)" "$(legacy '[T2] iptv-android/app/build.gradle.kts - x')" "iptv-android/app/build.gradle.kt"
eq "REPRO legacy regex: .pyi -> .py" "$(legacy 'see foo/bar.pyi here')" "foo/bar.py"
eq "REPRO legacy regex: .gdshader -> .gd" "$(legacy 'see foo/bar.gdshader here')" "foo/bar.gd"
eq "picker: .kts never yields a .kt path" "$(pick "$R" '[T2] iptv-android/app/build.gradle.kts - x')" "NONE"
eq "picker: .pyi yields nothing" "$(pick "$R" 'see foo/bar.pyi here')" "NONE"
eq "picker: .gdshader yields nothing" "$(pick "$R" 'see foo/bar.gdshader here')" "NONE"
eq "picker: .tsx is a whole token, not .ts" "$(pick "$R" '[T2] web/New.tsx - Create')" "PICK|web/New.tsx"
eq "picker: foo.py.bak is not a .py path" "$(pick "$R" 'x scripts/foo.py.bak y')" "NONE"
eq "picker: trailing sentence period is not part of the path" "$(pick "$R" 'Create scripts/mission/new_one.gd.')" "PICK|scripts/mission/new_one.gd"
eq "picker: a longer-extension sibling on disk (build.gradle.kts vs a .kt request) refuses" "$(pick "$R" '[T2] iptv-web/src/app.t - x iptv-web/src/app.ts')" "NONE"
mkdir -p lib && echo 'x' > lib/helper.pyi
eq "picker: sibling differing only by trailing letters refuses (helper.py vs helper.pyi)" "$(pick "$R" '[T1] lib/helper.py - Create')" "SKIP|sibling-longer-ext:helper.pyi|lib/helper.py"
rm -rf lib
eq "BENIGN picker: a plain new file is picked" "$(pick "$R" '[T1] scripts/mission/mission_directive.gd - Create with class_name X.')" "PICK|scripts/mission/mission_directive.gd"
eq "BENIGN picker: first path only (item with two paths picks the first)" "$(pick "$R" '[T1] scripts/mission/a.gd - Create; wire into scripts/mission/b.gd')" "PICK|scripts/mission/a.gd"
eq "picker: an existing file is not a stub target" "$(pick "$R" '[T1] iptv-web/src/app.ts - Add a helper')" "NONE"
eq "picker: no source path in the text" "$(pick "$R" 'Fix a typo in the README')" "NONE"

# ---- (1) deleted in history ----
eq "REPRO history: the delete is visible to git log --diff-filter=D" "$(git log --diff-filter=D --format=%h -1 -- scripts/battle/save_manager.gd | wc -l | tr -d ' ')" "1"
eq "picker: a path deleted in history is refused" "$(pick "$R" '[T1] scripts/battle/save_manager.gd - Remove the file content to prepare for deletion')" "SKIP|deleted-in-history|scripts/battle/save_manager.gd"
eq "picker: the xlite X4 item text (test asserting the deleted file does not exist) stubs nothing" "$(pick "$R" '- [ ] [T2] tests/ - Create a test that asserts `scripts/battle/save_manager.gd` does not exist')" "SKIP|deleted-in-history|scripts/battle/save_manager.gd"
eq "NEG picker: deleted then RE-ADDED (present again) is a normal existing file" "$(pick "$R" '[T1] scripts/battle/readded.gd - Add a helper')" "NONE"
eq "NEG picker: a path with glob characters does not match a different deleted file" "$(pick "$R" '[T1] scripts/battle/save_*.gd - x')" "NONE"
eq "picker: a never-existed path is stubbed as before" "$(pick "$R" '[T1] scripts/battle/never_was.gd - Create')" "PICK|scripts/battle/never_was.gd"

# ---- asserts-absent wording (a path that never existed in history) ----
eq "picker: 'asserts X does not exist' for a never-existed path stubs nothing" "$(pick "$R" '[T2] tests/ - Create a test that asserts `scripts/mission/ghost.gd` does not exist')" "SKIP|asserts-absent|scripts/mission/ghost.gd"
eq "picker: \"doesn't exist\" wording" "$(pick "$R" '[T2] tests/ - assert scripts/mission/ghost.gd doesn'"'"'t exist')" "SKIP|asserts-absent|scripts/mission/ghost.gd"
eq "BENIGN picker: '(does not exist yet)' on a create item is still stubbed" "$(pick "$R" '[T2] scripts/mission/fresh.gd (does not exist yet) - Create it')" "PICK|scripts/mission/fresh.gd"
eq "BENIGN picker: the wording on ANOTHER line does not block" "$(printf '[T2] scripts/mission/fresh.gd - Create it\nnote: old.gd does not exist' | python3 "$G" pick "$R" | tr '\t' '|')" "PICK|scripts/mission/fresh.gd"

# r11 round 2 (reviewer minor 1): the phrase must be about the PATH, not a later description of the new file
eq "REPRO asserts-absent: a create item that only mentions a missing entry later is still stubbed (test file)" "$(pick "$R" '[T1] iptv-backend/tests/test_watch_history_progress.py - Add test verifying update_watch_progress handles 404 error when watch history entry does not exist.')" "PICK|iptv-backend/tests/test_watch_history_progress.py"
eq "REPRO asserts-absent: 'returns error if the save file does not exist' in the description is still stubbed" "$(pick "$R" '[T1] scripts/new_mod.gd - Create module that returns error if the save file does not exist')" "PICK|scripts/new_mod.gd"
eq "asserts-absent: dash/colon separator before the phrase still refuses" "$(pick "$R" '[T2] tests/ - assert scripts/mission/ghost.gd - must not exist after the refactor')" "SKIP|asserts-absent|scripts/mission/ghost.gd"
eq "asserts-absent: adverb (now does not exist) still refuses" "$(pick "$R" '[T2] tests/ - check `scripts/mission/ghost.gd` now does not exist')" "SKIP|asserts-absent|scripts/mission/ghost.gd"
eq "asserts-absent: 'is deleted' right after the path still refuses" "$(pick "$R" '[T2] tests/ - verify scripts/mission/ghost.gd is deleted')" "SKIP|asserts-absent|scripts/mission/ghost.gd"

# r11 round 2 (reviewer minor 3): a bare basename that already exists in a subdirectory is a reference, not a new repo-root file
mkdir -p scripts/util && echo 'extends Node' > scripts/util/in_range.gd
eq "REPRO bare-basename: prose 'in_range.gd' (tracked under scripts/util) must not stub the repo root" "$( (git add -A; git commit -q -m util) >/dev/null 2>&1; pick "$R" 'Fix the off-by-one in in_range.gd when the range is empty')" "SKIP|bare-basename:scripts/util/in_range.gd|in_range.gd"
eq "bare-basename NEG: a bare name that exists NOWHERE is stubbed as before" "$(pick "$R" 'Create brand_new_root.gd with helpers')" "PICK|brand_new_root.gd"
eq "bare-basename NEG: a path WITH a directory is never treated as bare (same basename elsewhere is fine)" "$(pick "$R" '[T1] scripts/other/in_range.gd - Create')" "PICK|scripts/other/in_range.gd"
eq "bare-basename NEG: ./name that exists in a subdir also refuses" "$(pick "$R" 'see ./in_range.gd')" "SKIP|bare-basename:scripts/util/in_range.gd|./in_range.gd"

# ---- unsafe paths ----
eq "picker: absolute path refused" "$(pick "$R" '[T1] /etc/evil.py - Create')" "SKIP|unsafe-path|/etc/evil.py"
eq "picker: .. traversal refused" "$(pick "$R" '[T1] ../outside/evil.py - Create')" "SKIP|unsafe-path|../outside/evil.py"

# ---- (4) AGENTS.md out of scope ----
eq "picker: a new file under an AGENTS.md out-of-scope dir is refused (iptv-android)" "$(pick "$R" '[T1] iptv-android/app/src/main/Foo.kt - Create')" "SKIP|out-of-scope:iptv-android|iptv-android/app/src/main/Foo.kt"
eq "picker: iptv-ios too" "$(pick "$R" '[T1] iptv-ios/App/Foo.swift - Create')" "SKIP|out-of-scope:iptv-ios|iptv-ios/App/Foo.swift"
eq "picker: 'Never edit \`addons/\`' declares addons out of scope" "$(pick "$R" '[T1] addons/gut/x.gd - Create')" "SKIP|out-of-scope:addons|addons/gut/x.gd"
eq "BENIGN picker: an in-scope dir (iptv-backend) is stubbed" "$(pick "$R" '[T1] iptv-backend/app/new_mod.py - Create')" "PICK|iptv-backend/app/new_mod.py"
eq "BENIGN picker: a dir that merely shares the prefix (iptv-android-docs) is not out of scope" "$(pick "$R" '[T1] iptv-android-docs/x.py - Create')" "PICK|iptv-android-docs/x.py"
OOS="$(python3 - "$G" "$R" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(",".join(m.out_of_scope_dirs(sys.argv[2])))
PY
)"
eq "parser: exactly iptv-ios, iptv-android and addons are declared (not iptv-backend/iptv-web, not requirements.txt)" "$OOS" "iptv-ios,iptv-android,addons"
R2="$W/noagents"; mkdir -p "$R2"; git -C "$R2" init -q -b main
eq "no AGENTS.md: nothing is out of scope (stubs as before)" "$(pick "$R2" '[T1] iptv-android/app/Foo.kt - Create')" "PICK|iptv-android/app/Foo.kt"
printf '%s\n' '# x' 'Some text. Out of scope: lots of things, no backticked dirs here.' 'Fleet scope = `a/` only; `b/` is out of scope.' > "$R2/AGENTS.md"
eq "unparsable/ambiguous AGENTS.md declares nothing (the 'scope = ... only ... out of scope' line is ignored)" "$(pick "$R2" '[T1] b/x.py - Create')" "PICK|b/x.py"
printf '\xff\xfe garbage `x/` out of scope\n' > "$R2/AGENTS.md"
eq "binary-garbage AGENTS.md does not crash the picker" "$(pick "$R2" '[T1] y/x.py - Create' | cut -c1-4)" "PICK"

# ---- (3) undo ----
mkrepo(){   # $1=dir : repo with a bare origin, main pushed; prints nothing
  rm -rf "$1" "$1.git"; git init -q --bare -b main "$1.git"; git init -q -b main "$1"
  ( cd "$1" && echo a > a.txt && git add -A && git commit -q -m init && git remote add origin "$1.git" && git push -q origin main ) >/dev/null 2>&1
}
stub_commit(){   # $1=repo $2=path : writes the real stub and commits it; sets PRE/STUB
  ( cd "$1" && mkdir -p "$(dirname "$2")" && printf '%s\n' '# Placeholder - the implement step fills this in.' > "$2" )
  PRE="$(git -C "$1" rev-parse HEAD)"; git -C "$1" add "$2"; git -C "$1" commit -q -m "chore: stub new source file before implement (new-file udiff is unreliable)"; STUB="$(git -C "$1" rev-parse HEAD)"
}
undo(){ ( cd "$1" && python3 "$G" undo "$1" "$PRE" "$STUB" "$2" main "$W/undo.log" ); }

U="$W/u1"; mkrepo "$U"; stub_commit "$U" scripts/x.gd
eq "undo (unpushed tip stub): reset back to the pre-stub sha" "$(undo "$U" scripts/x.gd)" "reset"
ok "undo reset: HEAD is the pre-stub commit and the file + empty dir are gone" '[ "$(git -C "$U" rev-parse HEAD)" = "$PRE" ] && [ ! -e "$U/scripts/x.gd" ] && [ -z "$(git -C "$U" status --porcelain)" ]'
ok "undo logs to the task log" 'grep -q "stub-guard: unfilled stub scripts/x.gd dropped" "$W/undo.log"'

U="$W/u2"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; echo 'real' > "$U/scripts/x.gd"; git -C "$U" add -A; git -C "$U" commit -q -m "feat: filled"
eq "undo NEG: a stub the implement step FILLED is never touched" "$(undo "$U" scripts/x.gd)" "filled-or-gone"
ok "undo NEG: the real content is intact" '[ "$(cat "$U/scripts/x.gd")" = real ]'

U="$W/u3"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; echo 2 >> "$U/a.txt"; git -C "$U" add -A; git -C "$U" commit -q -m "feat: other work on top"
eq "undo: unfilled stub UNDER later work is removed by a follow-up commit (work kept)" "$(undo "$U" scripts/x.gd)" "removed"
ok "undo removed: file gone, other work kept, tree clean, stub history intact" '[ ! -e "$U/scripts/x.gd" ] && grep -q 2 "$U/a.txt" && [ -z "$(git -C "$U" status --porcelain)" ] && git -C "$U" log --format=%s | grep -q "drop unfilled stub scripts/x.gd" && git -C "$U" log --format=%s | grep -q "stub new source file"'

U="$W/u4"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; git -C "$U" push -q origin main
eq "undo: a stub that already reached origin is removed by a commit that is PUSHED (fast-forward)" "$(undo "$U" scripts/x.gd)" "removed"
ok "undo pushed: origin/main no longer has the stub file" '! git -C "$U.git" cat-file -e main:scripts/x.gd'

U="$W/u5"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; printf 'wip\n' >> "$U/scripts/x.gd"
eq "undo NEG: uncommitted edits to the stub path leave it alone" "$(undo "$U" scripts/x.gd)" "dirty"
U="$W/u6"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; echo dirty >> "$U/a.txt"
eq "undo: dirty tree elsewhere -> no hard reset, the stub is removed by commit and the dirty edit survives" "$(undo "$U" scripts/x.gd)" "removed"
ok "undo dirty: the unrelated uncommitted edit is untouched" 'grep -q dirty "$U/a.txt"'
U="$W/u7"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; git -C "$U" reset -q --hard "$PRE"
eq "undo: stub no longer in HEAD (already reverted) -> no-op" "$(undo "$U" scripts/x.gd)" "stub-not-in-head"
U="$W/u8"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; ( cd "$U" && git commit -q --amend -m "chore: stub new source file before implement (new-file udiff is unreliable)" --date="2001-01-01T00:00:00" ); echo b >> "$U/a.txt"; git -C "$U" add -A; git -C "$U" commit -q -m top
eq "undo: stub sha rewritten by an in-cycle rebase is found again by subject+path" "$(undo "$U" scripts/x.gd)" "removed"
ok "undo rebased: file gone" '[ ! -e "$U/scripts/x.gd" ]'
U="$W/u9"; mkrepo "$U"; stub_commit "$U" scripts/x.gd
eq "undo: OVN_STUB_UNDO=off disables it" "$(OVN_STUB_UNDO=off undo "$U" scripts/x.gd)" "off"
ok "undo off: stub still there" '[ -f "$U/scripts/x.gd" ]'

# r11 round 2 (reviewer minor 2): never undo a stub that a source file added THIS CYCLE references; remove the .uid sidecar with the stub
U="$W/u10"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; mkdir -p "$U/tests"; printf 'const X = preload("res://scripts/x.gd")\n' > "$U/tests/test_x.gd"; git -C "$U" add -A; git -C "$U" commit -q -m "feat: test preloads the stub"
eq "REPRO undo-references: a .gd that preloads the unfilled stub keeps it (removal would make the preload fail = red HEAD)" "$(undo "$U" scripts/x.gd)" "referenced"
ok "undo-references: the placeholder file is still there and no drop commit was made" '[ -f "$U/scripts/x.gd" ] && ! git -C "$U" log --format=%s | grep -q "drop unfilled stub"'
ok "undo-references: logged to the task log" 'grep -q "stub-guard: unfilled stub scripts/x.gd KEPT" "$W/undo.log"'
U="$W/u11"; mkrepo "$U"; stub_commit "$U" app/new_mod.py; printf 'from app import new_mod\n' > "$U/use.py"; git -C "$U" add -A; git -C "$U" commit -q -m "feat: imports the stub"
eq "undo-references: a python 'from app import new_mod' keeps the stub" "$(undo "$U" app/new_mod.py)" "referenced"
U="$W/u12"; mkrepo "$U"; stub_commit "$U" web/Thing.ts; printf "import { x } from './Thing'\n" > "$U/web/use.ts"; git -C "$U" add -A; git -C "$U" commit -q -m "feat: imports the ts stub"
eq "undo-references: a ts relative import keeps the stub" "$(undo "$U" web/Thing.ts)" "referenced"
U="$W/u13"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; printf -- '- [x] [T1] scripts/x.gd - Create (credited)\n' > "$U/OVERNIGHT_PROGRESS.md"; git -C "$U" add -A; git -C "$U" commit -q -m "chore: credit item"
eq "undo-references NEG: the progress file naming the path (docs) does not keep an unfilled stub" "$(undo "$U" scripts/x.gd)" "removed"
U="$W/u14"; mkrepo "$U"; mkdir -p "$U/tests"; printf 'const X = preload("res://scripts/x.gd")\n' > "$U/tests/test_old.gd"; git -C "$U" add -A; git -C "$U" commit -q -m "old dangling ref" ; git -C "$U" push -q origin main; stub_commit "$U" scripts/x.gd; echo b >> "$U/a.txt"; git -C "$U" add -A; git -C "$U" commit -q -m top
eq "undo-references NEG: a reference that already existed BEFORE the stub (baseline) does not keep it" "$(undo "$U" scripts/x.gd)" "removed"
U="$W/u15"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; printf 'uid://abc\n' > "$U/scripts/x.gd.uid"; git -C "$U" add -A; git -C "$U" commit -q -m "godot uid sidecar"; echo c >> "$U/a.txt"; git -C "$U" add -A; git -C "$U" commit -q -m top
eq "REPRO uid: tracked <path>.uid sidecar is removed WITH the stub" "$(undo "$U" scripts/x.gd)" "removed"
ok "uid: neither the stub nor its tracked sidecar remain; tree clean" '[ ! -e "$U/scripts/x.gd" ] && [ ! -e "$U/scripts/x.gd.uid" ] && [ -z "$(git -C "$U" status --porcelain)" ]'
U="$W/u16"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; echo c >> "$U/a.txt"; git -C "$U" add -A; git -C "$U" commit -q -m top; printf 'uid://abc\n' > "$U/scripts/x.gd.uid"
eq "uid: untracked sidecar (Godot wrote it during the cycle) is deleted with the stub" "$(undo "$U" scripts/x.gd)" "removed"
ok "uid untracked: sidecar gone" '[ ! -e "$U/scripts/x.gd.uid" ]'
U="$W/u17"; mkrepo "$U"; stub_commit "$U" scripts/x.gd; printf 'uid://abc\n' > "$U/scripts/x.gd.uid"
eq "uid: reset path also deletes an untracked sidecar" "$(undo "$U" scripts/x.gd)" "reset"
ok "uid reset: sidecar gone" '[ ! -e "$U/scripts/x.gd.uid" ]'

# ---- (5) scan ----
S="$W/scan"; mkdir -p "$S/app" "$S/tests" "$S/iptv-android/app" "$S/src" && cd "$S" && git init -q -b main .
M='Placeholder - the implement step fills this in.'
printf '// %s\n' "$M" > iptv-android/app/build.gradle.kt            # the P5 junk file
printf '// %s\n' "$M" > app/RatingPromptManager.kt
printf '# %s\n' "$M" > in_range.gd
printf '"""%s"""\n' "$M" > app/mod.py
printf '// %s\nexport {}\n' "$M" > src/helper.ts
printf '<template><div /></template>\n<!-- %s -->\n' "$M" > src/Foo.vue
printf '"""%s"""\n' "$M" > tests/test_removed_stubs.py
printf '# %s\n' "$M" > tests/test_foo.gd
printf '// %s\nimport { describe, it } from '"'"'vitest'"'"'\n\ndescribe.skip('"'"'placeholder until the implement step fills it in'"'"', () => {\n  it('"'"'placeholder'"'"', () => {})\n})\n' "$M" > src/Thing.test.ts
printf '"""%s"""\ndef real():\n    return 1\n' "$M" > app/filled.py                                  # marker + real code: NOT a leak
printf '# %s\nvar x = 1\n' "$M" > filled.gd
printf '# mentions %s in prose only\n' "$M" > prose.gd
: > empty.py
printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\n' > app/0099_x.py
printf '%s\n' "$M" > notes.md                                                                      # not a source extension
git add -A && git commit -q -m x
SC="$(python3 "$G" scan "$S" | sort)"
for f in iptv-android/app/build.gradle.kt app/RatingPromptManager.kt in_range.gd app/mod.py src/helper.ts src/Foo.vue app/0099_x.py; do
  ok "scan flags leaked placeholder source: $f" "printf '%s\n' \"\$SC\" | grep -qxF \"SOURCE	$f\""
done
for f in tests/test_removed_stubs.py tests/test_foo.gd src/Thing.test.ts; do
  ok "scan lists test placeholder as TEST (informational): $f" "printf '%s\n' \"\$SC\" | grep -qxF \"TEST	$f\""
done
for f in app/filled.py filled.gd prose.gd empty.py notes.md; do
  ok "scan NEG: never flags $f" "! printf '%s\n' \"\$SC\" | grep -qF \"$f\""
done
eq "scan exit code is 0 even with leaks (a flag, not a failure)" "$(python3 "$G" scan "$S" >/dev/null; echo $?)" "0"
eq "scan --rev reads the committed tree (same set)" "$(python3 "$G" scan "$S" --rev HEAD | sort | md5sum | cut -c1-32)" "$(python3 "$G" scan "$S" | sort | md5sum | cut -c1-32)"
git rm -q -f in_range.gd && git commit -q -m rm
ok "scan --rev HEAD~1 still sees the file removed in HEAD" "python3 \"$G\" scan \"$S\" --rev HEAD~1 | grep -qxF 'SOURCE	in_range.gd'"
ok "scan on the new tree no longer lists it" "! python3 \"$G\" scan \"$S\" | grep -qF in_range.gd"
eq "scan of a non-repo prints nothing, exit 0" "$(python3 "$G" scan "$W/nonexistent" | wc -l | tr -d ' ')" "0"

echo "stub-guard: $P passed, $F failed"
[ "$F" -eq 0 ]
