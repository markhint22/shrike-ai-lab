#!/usr/bin/env bash
# Package verify-credit-runner (night review N4, 2026-10-13), finding B in lib_auto_credit.sh: three landed, green cycles were refused only because the tree changed AFTER the cycle's verify.
#   billwatch 122817 / iptv 042516  'working tree/index differ from AFTER (billwatch-web/package-lock.json)'   (npm rewrote the lockfile)
#   gitlark 144311 (code commit d2c2fdab green)   'working tree/index differ from AFTER (OVERNIGHT_PROGRESS.md)'  - a RULE 1 refusal BEFORE any VERIFY ran: the progress file was already dirty
#      when auto-credit started (the writer is unidentified: .ovn-verify.sh of gitlark does not write it; a concurrent writer of the live checkout is the likely cause)
#   billwatch 104937-style: a VERIFY/concurrent writer changes the progress file between the checks (post-VERIFY RULE 1)
# Now: a package-lock.json / yarn.lock / pnpm-lock.yaml delta is restored to AFTER and the credit proceeds; a progress-file-only delta (at RULE 1 AND post-VERIFY) is kept - provided every
# removed/changed line is an item line (`- [ ]`/`- [x]`), a heading/record edit refuses - and the ticked lines are re-located by text; ANY other differing path (source file, or a lockfile mixed with source) keeps the refusal and nothing is restored/credited. OVN_AC_LOCKFILE_RESTORE=off restores the old refusal.
# Every "credits" assertion fails on the old code (the refusal), every "still refuses" assertion is the guard that must NOT regress (benign twins are labelled).
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_auto_credit.sh" ] || { echo "  NOT RUN: lib_auto_credit.sh not found"; exit 77; }   # 77 = cannot run here; run_all.sh reports it (never a silent green)
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
ALERTS="$W/alerts.log"; : > "$ALERTS"
emit_alert(){ echo "$1 | $2 | $3" >> "$ALERTS"; }
unset OVN_AC_LOCKFILE_RESTORE
. "$S/lib_item_select.sh"
. "$S/lib_verify_clause.sh"
. "$S/lib_auto_credit.sh"

ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py`
- [ ] [T2] src/b.py — Add new_b, never touched by the cycle. VERIFY: `grep -q "def new_b" src/b.py`'
mk() {  # mk <name> [verify-clause-override-for-item-1]
  R="$W/r/$1"; rm -rf "$R"; mkdir -p "$R/src" "$R/web"; cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py
  printf 'def old_b():\n    return 1\n' > src/b.py
  printf 'other\n' > src/other.py
  printf '{"lockfileVersion":3}\n' > web/package-lock.json
  printf '# yarn lockfile v1\n' > web/yarn.lock
  printf 'lockfileVersion: 9\n' > web/pnpm-lock.yaml
  local items="$ITEMS"
  if [ -n "${2:-}" ]; then items="- [ ] [T2] src/a.py — Add new_a. VERIFY: \`$2\`"$'\n'"$(printf '%s\n' "$ITEMS" | sed -n 2p)"; fi
  printf '%s\n' "## Next Steps" "$items" "" "## Completed" > OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m base; B="$(git rev-parse HEAD)"
  printf 'def new_a():\n    return 2\n' >> src/a.py
  git add -A && git commit -q -m "feat: a"; A="$(git rev-parse HEAD)"
}
call() { : > "$R/task.log"; : > "$ALERTS"; ovn_auto_credit "$B" "$A" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null; CRC=$?; CLOG="$(cat "$R/task.log")"; }
item_state() { grep -E "$1" OVERNIGHT_PROGRESS.md | head -1 | cut -c1-5; }   # '- [x]' or '- [ ]'
clean() { [ -z "$(git status --porcelain --untracked-files=no)" ]; }
dirty_paths() { git status --porcelain --untracked-files=no | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//'; }

# ---------------- RULE 1: lockfile-only delta before anything runs ----------------
mk l1; printf '{"lockfileVersion":3,"npm":"rewrote"}\n' > web/package-lock.json
call
eq "L1 package-lock.json rewritten after the cycle commit: rc 0 (credit proceeds)" "$CRC" 0
eq "L1 the item is credited" "$(item_state 'src/a.py')" "- [x]"
eq "L1 the untouched sibling item stays open" "$(item_state 'src/b.py')" "- [ ]"
eq "L1 the lockfile was restored to the cycle's content" "$(cat web/package-lock.json)" '{"lockfileVersion":3}'
ok "L1 the worktree is clean afterwards" clean
ok "L1 the restore is logged with the file name" 'printf "%s" "$CLOG" | grep -q "restored lockfile web/package-lock.json"'
ok "L1 no REFUSED line, no alert" '! printf "%s" "$CLOG" | grep -q REFUSED && [ ! -s "$ALERTS" ]'
eq "L1 the tick commit holds ONLY the progress file" "$(git show --name-only --format= HEAD | tr '\n' ' ')" "OVERNIGHT_PROGRESS.md "

for lf in web/yarn.lock web/pnpm-lock.yaml; do
  mk "l1_$(basename "$lf")"; printf 'rewritten\n' > "$lf"
  call
  eq "L1 $lf delta: credited and restored" "$(item_state 'src/a.py'):$(git diff --name-only | wc -l | tr -d ' ')" "- [x]:0"
done

mk l1i; printf '{"staged":1}\n' > web/package-lock.json; git add web/package-lock.json
call
eq "L1i a STAGED lockfile delta is settled too (index and worktree)" "$(item_state 'src/a.py'):$(git diff --cached --name-only | wc -l | tr -d ' '):$(git diff --name-only | wc -l | tr -d ' ')" "- [x]:0:0"

mk l1d; rm -f web/package-lock.json
call
eq "L1d a DELETED lockfile is restored and the credit proceeds" "$(item_state 'src/a.py'):$(test -f web/package-lock.json && echo present)" "- [x]:present"

# ---------------- RULE 1: anything that is not a lockfile keeps the refusal ----------------
mk s1; printf 'tampered\n' >> src/other.py
call
eq "S1 a SOURCE file differing from AFTER: rc 1 (refused)" "$CRC" 1
eq "S1 nothing credited" "$(item_state 'src/a.py'):$OVN_AC_CREDITED" "- [ ]:0"
ok "S1 the log names the path and says REFUSED" 'printf "%s" "$CLOG" | grep -q "REFUSED - working tree/index differ from AFTER.*src/other.py"'
eq "S1 the source file was NOT touched by us (still dirty)" "$(dirty_paths)" "src/other.py"
eq "S1 HEAD unchanged (no commit)" "$(git rev-parse HEAD)" "$A"

mk s2; printf 'tampered\n' >> src/other.py; printf '{"mixed":1}\n' > web/package-lock.json
call
eq "S2 lockfile MIXED with a source delta: rc 1 (refused)" "$CRC" 1
eq "S2 ... and the lockfile is NOT restored either (nothing is touched on a refusal)" "$(dirty_paths)" "src/other.py web/package-lock.json"
eq "S2 nothing credited" "$(item_state 'src/a.py')" "- [ ]"

mk s3; printf '{"x":1}\n' > web/package-lock.json
OVN_AC_LOCKFILE_RESTORE=off call
eq "S3 kill switch OVN_AC_LOCKFILE_RESTORE=off: the old refusal comes back (rc 1, nothing credited)" "$CRC:$(item_state 'src/a.py')" "1:- [ ]"
ok "S3 off: the lockfile is left as it was found" '[ "$(dirty_paths)" = "web/package-lock.json" ]'

mk s4; printf 'x\n' > web/package.json.bak; git add -A; git commit -q -m "feat: a (+bak)"; A="$(git rev-parse HEAD)"
printf 'z\n' >> web/package.json.bak
call
eq "S4 a look-alike name (package.json.bak, not a lockfile) still refuses" "$CRC:$(item_state 'src/a.py')" "1:- [ ]"

# the cycle's OWN diff touched the lockfile (npm install was part of the work) and the tree then moved off AFTER: settled to AFTER, the committed state
mk l5; printf '{"lockfileVersion":3,"deps":1}\n' > web/package-lock.json; git add -A; git commit -q -m "feat: a + lock"; A="$(git rev-parse HEAD)"
printf '{"lockfileVersion":3,"deps":2}\n' > web/package-lock.json
call
eq "L5 a lockfile the cycle itself committed, then rewritten: restored to AFTER's copy, credited" "$(item_state 'src/a.py'):$(cat web/package-lock.json)" '- [x]:{"lockfileVersion":3,"deps":1}'

# ---------------- post-VERIFY check ----------------
# the VERIFY clause itself rewrites a file after proving the item (python3 -c: no shell redirect, which the runner refuses to run)
V_LOCK='grep -q "def new_a" src/a.py && python3 -c "open(\"web/package-lock.json\",\"a\").write(\"x\")"'
mk v1 "$V_LOCK"
call
eq "V1 a VERIFY that rewrites package-lock.json: credited, lockfile restored" "$CRC:$(item_state 'src/a.py'):$(cat web/package-lock.json)" '0:- [x]:{"lockfileVersion":3}'
ok "V1 worktree clean after the credit commit" clean

mk v1o "$V_LOCK"
OVN_AC_LOCKFILE_RESTORE=off call
eq "V1 kill switch off: refused as before (rc 1, nothing credited, reset to AFTER)" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py'):$(git rev-parse HEAD)" "1:0:- [ ]:$A"

V_SRC='grep -q "def new_a" src/a.py && python3 -c "open(\"src/other.py\",\"a\").write(\"x\")"'
mk v2 "$V_SRC"
call
eq "V2 benign twin: a VERIFY that modifies SOURCE still refuses (rc 1), nothing credited" "$CRC:$(item_state 'src/a.py')" "1:- [ ]"
ok "V2 and the tree is hard-reset to AFTER" 'clean && [ "$(git rev-parse HEAD)" = "$A" ]'
ok "V2 the log says a VERIFY command modified the tree" 'printf "%s" "$CLOG" | grep -q "REFUSED - a VERIFY command modified the tree (src/other.py)"'

# a VERIFY that touches the progress file: a line is PREPENDED, so every line number moves down by one
V_PROG='grep -q "def new_a" src/a.py && python3 -c "p=\"OVERNIGHT_PROGRESS.md\"; s=open(p).read(); open(p,\"w\").write(\"# written during verify\\n\"+s)"'
mk p1 "$V_PROG"
call
eq "P1 progress file changed during VERIFY (only differing path): rc 0, the ticked item is credited" "$CRC:$OVN_AC_CREDITED" "0:1"
eq "P1 the RIGHT item was ticked after the line numbers moved (a stale line number would tick the wrong line)" "$(item_state 'src/a.py'):$(item_state 'src/b.py')" "- [x]:- [ ]"
ok "P1 the line written during verify is preserved" 'head -1 OVERNIGHT_PROGRESS.md | grep -q "written during verify"'
ok "P1 the log says it kept the progress file and re-located by text" 'printf "%s" "$CLOG" | grep -q "progress file OVERNIGHT_PROGRESS.md changed since the cycle.s verify"'
ok "P1 clean worktree, the tick commit holds only the progress file" 'clean && [ "$(git show --name-only --format= HEAD | tr "\n" " ")" = "OVERNIGHT_PROGRESS.md " ]'

mk p1o "$V_PROG"
OVN_AC_LOCKFILE_RESTORE=off call
eq "P1 kill switch off: refused as before" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py')" "1:0:- [ ]"

V_BOTH='grep -q "def new_a" src/a.py && python3 -c "p=\"OVERNIGHT_PROGRESS.md\"; s=open(p).read(); open(p,\"w\").write(\"# v\\n\"+s); open(\"web/yarn.lock\",\"a\").write(\"x\")"'
mk p2 "$V_BOTH"
call
eq "P2 progress file + lockfile both changed by VERIFY: credited, lockfile restored, right item ticked" "$CRC:$(item_state 'src/a.py'):$(item_state 'src/b.py'):$(cat web/yarn.lock)" "0:- [x]:- [ ]:# yarn lockfile v1"

V_PS='grep -q "def new_a" src/a.py && python3 -c "p=\"OVERNIGHT_PROGRESS.md\"; s=open(p).read(); open(p,\"w\").write(\"# v\\n\"+s); open(\"src/other.py\",\"a\").write(\"x\")"'
mk p3 "$V_PS"
call
eq "P3 benign twin: progress file + SOURCE changed by VERIFY still refuses and resets" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py')" "1:0:- [ ]"
ok "P3 the progress file edit is dropped with the reset (HEAD is AFTER, tree clean)" 'clean && [ "$(git rev-parse HEAD)" = "$A" ] && ! head -1 OVERNIGHT_PROGRESS.md | grep -q "# v"'

# the item that moved is gone from the changed progress file (someone ticked/removed it): skipped, nothing wrong ticked
V_GONE='grep -q "def new_a" src/a.py && python3 -c "p=\"OVERNIGHT_PROGRESS.md\"; s=open(p).read().replace(\"Add new_a\",\"Add new_a (reworded)\"); open(p,\"w\").write(s)"'
mk p4 "$V_GONE"
call
eq "P4 the item text was edited during VERIFY: the tick is skipped (no wrong line ticked), rc 0" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py'):$(item_state 'src/b.py')" "0:0:- [ ]:- [ ]"
ok "P4 the skip is logged" 'printf "%s" "$CLOG" | grep -q "SKIPPED tick of line"'

# ---------------- RULE 1: progress-file-only delta BEFORE any VERIFY (gitlark 144311) ----------------
mk g1; printf -- '- [ ] [T3] src/zzz.py — appended by a concurrent writer. VERIFY: `true`\n' >> OVERNIGHT_PROGRESS.md
call
eq "G1 progress file APPENDED to before auto-credit starts (the only delta): rc 0, item credited" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py'):$(item_state 'src/b.py')" "0:1:- [x]:- [ ]"
ok "G1 the appended line survives in the credit commit" 'git show HEAD:OVERNIGHT_PROGRESS.md | grep -q "appended by a concurrent writer"'
ok "G1 the diffstat is logged (+1 -N)" 'printf "%s" "$CLOG" | grep -q "progress file OVERNIGHT_PROGRESS.md diffstat vs AFTER: +1 -"'
ok "G1 no REFUSED line, no alert, clean tree, one tick commit holding only the progress file" '! printf "%s" "$CLOG" | grep -q REFUSED && [ ! -s "$ALERTS" ] && clean && [ "$(git show --name-only --format= HEAD | tr "\n" " ")" = "OVERNIGHT_PROGRESS.md " ]'

mk g2; { printf '# prepended\n'; cat OVERNIGHT_PROGRESS.md; } > "$W/p.tmp" && cp "$W/p.tmp" OVERNIGHT_PROGRESS.md
call
eq "G2 progress file PREPENDED before auto-credit (line numbers shift): the RIGHT item is ticked" "$CRC:$(item_state 'src/a.py'):$(item_state 'src/b.py')" "0:- [x]:- [ ]"

mk g3; printf -- '- [ ] [T3] src/zzz.py — concurrent. VERIFY: `true`\n' >> OVERNIGHT_PROGRESS.md; printf 'tampered\n' >> src/other.py
call
eq "G3 benign twin: progress file + SOURCE differ before auto-credit: still refuses, nothing credited" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py')" "1:0:- [ ]"
ok "G3 source and progress file left exactly as found (nothing restored on a refusal)" '[ "$(dirty_paths)" = "OVERNIGHT_PROGRESS.md src/other.py" ]'

mk g4; printf -- '- [ ] [T3] src/zzz.py — c. VERIFY: `true`\n' >> OVERNIGHT_PROGRESS.md; printf '{"x":2}\n' > web/package-lock.json
call
eq "G4 progress file + lockfile before auto-credit: credited, lockfile restored" "$CRC:$(item_state 'src/a.py'):$(cat web/package-lock.json)" '0:- [x]:{"lockfileVersion":3}'

mk g5; sed -i.bak 's/^## Completed$/## Done/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
call
eq "G5 a HEADING of the progress file changed (not bookkeeping): refuses, nothing credited" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py')" "1:0:- [ ]"
ok "G5 the refusal is logged" 'printf "%s" "$CLOG" | grep -q "differs from AFTER in a non-item line"'

mk g6; sed -i.bak 's/Add new_b, never touched by the cycle\./Add new_b (parked by a concurrent writer)./' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
call
eq "G6 an ITEM line edited by a concurrent writer (a park annotation): still bookkeeping, credited" "$CRC:$(item_state 'src/a.py')" "0:- [x]"
ok "G6 the concurrent edit is kept" 'grep -q "parked by a concurrent writer" OVERNIGHT_PROGRESS.md'

mk g7; printf -- '- [ ] [T3] src/zzz.py — c. VERIFY: `true`\n' >> OVERNIGHT_PROGRESS.md
OVN_AC_LOCKFILE_RESTORE=off call
eq "G7 kill switch off: the old RULE 1 refusal on a progress-only delta comes back" "$CRC:$OVN_AC_CREDITED:$(item_state 'src/a.py')" "1:0:- [ ]"

echo "test_auto_credit_lockfile: $P passed, $F failed"
[ "$F" = 0 ]
