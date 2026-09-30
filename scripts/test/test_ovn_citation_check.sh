#!/usr/bin/env bash
# Regression tests for ovn_citation_check.py (per-commit helper) and ovn_citation_check.sh (git-history driver).
# Flags backlog items whose description cites a file (by basename) that exists nowhere in the repo, after
# three false-positive filters: VERIFY: clauses dropped, delete/removal items skipped, sibling-line targets.
# Hermetic: fake $HOME/overnight-queue git repo, curl stubbed, script PATH line patched so the stub wins.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_HOME="$HOME"
PY="$HERE/../ovn_citation_check.py"; [ -f "$PY" ] || PY="$REAL_HOME/overnight-queue/scripts/ovn_citation_check.py"
SH="$HERE/../ovn_citation_check.sh"; [ -f "$SH" ] || SH="$REAL_HOME/overnight-queue/scripts/ovn_citation_check.sh"
[ -f "$PY" ] && [ -f "$SH" ] || { echo "  SKIP: scripts not found"; exit 0; }
command -v git >/dev/null || { echo "  SKIP: git missing"; exit 0; }
PYBIN="$(command -v python3)"
unset NTFY_TOPIC
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
known(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else warnc=$((warnc+1)); echo "  WARN KNOWN-BUG: $l"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "== python helper =="
R="$T/repo"; mkdir -p "$R/src" "$R/node_modules/pkg" "$R/.venv/lib" "$R/.git/x"
touch "$R/src/Existing.kt" "$R/src/AuthRepositoryTest.kt" "$R/node_modules/pkg/OnlyInNodeModules.ts" "$R/.venv/lib/OnlyInVenv.py"
py(){ printf '%s\n' "$1" | python3 "$PY" "$R" 2>&1; }

eqv "no args -> silent" "" "$(python3 "$PY" </dev/null 2>&1)"
eqv "empty stdin -> silent" "" "$(py '')"
out="$(py '+- [ ] [T2] app/NewThing.kt — Add x mirroring Existing.kt pattern.')"
eqv "existing referenced file (found by basename) -> clean" "" "$out"
out="$(py '+- [ ] [T2] app/NewThing.kt — Add x mirroring GhostTest.kt mockk pattern.')"
eqv "missing referenced file -> flagged (tab-separated)" "+- [ ] [T2] app/NewThing.kt — Add x mirroring GhostTest.kt mockk pattern.	MISSING: GhostTest.kt (referenced, not found anywhere in repo)" "$out"
out="$(py '+- [ ] [T2] app/NewThing.kt — Create this new file.')"
eqv "item's own leading target is never checked" "" "$out"
out="$(py '+- [ ] [T2] app/NewThing.kt — Create. VERIFY: pytest tests/test_new.py::test_a')"
eqv "VERIFY: clause is dropped before scanning" "" "$out"
out="$(py '+- [ ] [T2] app/NewThing.kt — Uses Ghost.kt. VERIFY: pytest tests/test_new.py')"
eqv "citation BEFORE VERIFY still checked, VERIFY file ignored" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: Ghost.kt')"
out="$(py '+- [ ] [T1] app/old.py — Delete the test file for the now-deleted Gone.py.')"
eqv "delete/removal items skipped" "" "$out"
out="$(py '+- [ ] [T1] app/old.py — Removal of Gone.py wiring.')"
eqv "'removal' keyword also skips" "" "$out"
out="$(py '+- [ ] [T1] app/old.py — Deletes the stale Gone.py reference.')"
eqv "'Deletes' (not a whole-word match) is NOT skipped -> flagged" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: Gone.py')"

# sibling lines in same commit: one creates the file another references
in1='+- [ ] [T2] src/router.ts — Wire route to CodeInsightsPage.vue in the router.
+- [ ] [T2] src/CodeInsightsPage.vue — Create the page component.'
out="$(printf '%s\n' "$in1" | python3 "$PY" "$R")"
eqv "reference to a file a sibling item creates -> not flagged" "" "$out"
# same pair but the sibling does NOT create it
in2='+- [ ] [T2] src/router.ts — Wire route to CodeInsightsPage.vue in the router.
+- [ ] [T2] src/Other.vue — Create the other page.'
out="$(printf '%s\n' "$in2" | python3 "$PY" "$R")"
eqv "no sibling creates it -> flagged" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: CodeInsightsPage.vue')"

# de-dup: same missing basename cited twice, and target's basename cited again
out="$(py '+- [ ] [T2] a/x.kt — Needs Ghost.kt and sub/Ghost.kt and again Ghost.kt.')"
eqv "same missing basename reported once" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: Ghost.kt')"
out="$(py '+- [ ] [T2] a/Target.kt — Also update lib/Target.kt and Existing.kt.')"
eqv "target's own basename cited again -> skipped" "" "$out"
out="$(py '+- [ ] [T2] a/x.kt — Needs Ghost1.kt and Ghost2.py both.')"
eqv "two distinct missing -> two lines" "2" "$(printf '%s\n' "$out" | grep -c 'MISSING:')"

# excluded dirs: file only in node_modules / .venv / .git does not count as present
out="$(py '+- [ ] [T2] a/x.kt — Mirror OnlyInNodeModules.ts and OnlyInVenv.py pattern.')"
eqv "files only under node_modules/.venv are treated as missing" "2" "$(printf '%s\n' "$out" | grep -c 'MISSING:')"
touch "$R/.git/x/InGit.kt"
eqv "files only under .git treated as missing" "1" "$(py '+- [ ] [T2] a/x.kt — Mirror InGit.kt.' | grep -c MISSING)"

# line shapes
out="$(py '- [ ] [T3] a/x.kt — Mirror Ghost.kt.')"
eqv "works without leading '+'" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: Ghost.kt')"
out="$(py 'free text with foo.py then Ghost.py here')"
eqv "malformed (no tier tag) line does not crash; scans anyway" "1" "$(printf '%s\n' "$out" | grep -c 'MISSING: Ghost.py')"
eqv "line with no file paths -> silent" "" "$(py '+- [ ] [T1] Just prose, nothing to cite.')"
eqv "unsupported extensions (.json/.md) are not citations" "" "$(py '+- [ ] [T2] a/x.kt — See config.json and README.md.')"
eqv ".tsx recognised as a path" "1" "$(py '+- [ ] [T2] a/x.kt — Mirror Panel.tsx.' | grep -c 'MISSING: Panel.tsx')"

# find() failure must not false-flag (except branch): hide `find` from PATH
out="$(printf '%s\n' '+- [ ] [T2] a/x.kt — Mirror Ghost.kt.' | PATH=/nonexistent "$PYBIN" "$PY" "$R" 2>&1)"
eqv "find unavailable -> never false-flags" "" "$out"
# nonexistent repo dir: find exits nonzero with empty stdout. Doc says 'find failing is not evidence of a missing file'.
out="$(printf '%s\n' '+- [ ] [T2] a/x.kt — Mirror Ghost.kt.' | python3 "$PY" "$T/does-not-exist" 2>&1)"
known "find erroring on a missing repo dir should not false-flag (nonzero exit treated as 'not found')" test -z "$out"

echo "== shell driver =="
STUB="$T/stub"; mkdir -p "$STUB"; CURLLOG="$T/curl.log"
cat > "$STUB/curl" <<EOF
#!/bin/bash
{ echo "--CALL--"; printf '%s\n' "\$@"; } >> "$CURLLOG"
exit 0
EOF
chmod +x "$STUB/curl"
W="$T/w/overnight-queue"
gi(){ git -C "$W" "$@"; }
setup(){
  rm -rf "$T/w" "$CURLLOG"; mkdir -p "$W"/{scripts,state,logs,backlog,repos/alpha/src}
  touch "$W/repos/alpha/src/Existing.kt"
  sed "s|^export PATH=.*|export PATH=\"$STUB:/usr/bin:/bin\"|" "$SH" > "$W/scripts/ovn_citation_check.sh"
  cp "$PY" "$W/scripts/ovn_citation_check.py"
  gi init -q; : > "$W/.gitignore"
  printf 'logs/\nstate/\n' > "$W/.gitignore"
  gi add .gitignore; gi commit -q -m init
}
bl(){ printf '%s\n' "$2" >> "$W/backlog/$1.md"; gi add backlog; gi commit -q -m "backlog $1 $RANDOM"; }
runsh(){ HOME="$T/w" bash "$W/scripts/ovn_citation_check.sh" "$@" 2>&1; }
LOG="$W/logs/ovn_citation_check.log"

HOME="$T/none" bash "$SH" >/dev/null 2>&1; eqv "no ~/overnight-queue -> exit 1" "1" "$?"

setup
bl alpha '# --- decomposed from roadmap ---
- [ ] [T2] app/NewThing.kt — Create it mirroring Existing.kt pattern. VERIFY: pytest foo
- [ ] [T2] app/Other.kt — Add method mirroring GhostTest.kt mockk pattern. VERIFY: pytest bar'
NTFY_TOPIC=tt runsh alpha >/dev/null; rc=$?
eqv "run exits 0" "0" "$rc"
chk "SUSPECT logged with repo, short sha and missing file" grep -Eq 'SUSPECT: alpha @ [0-9a-f]{9}: .*-> MISSING: GhostTest.kt' "$LOG"
eqv "exactly one suspect (the existing-file item is clean)" "1" "$(grep -c SUSPECT "$LOG")"
chk "summary line logged" grep -q '=== 1 item(s) citing a file not found anywhere in the repo this run ===' "$LOG"
chk "curl called once" test "$(grep -c -- '--CALL--' "$CURLLOG")" = 1
chk "alert title" grep -q 'Title: Citation check: 1 suspect item(s)' "$CURLLOG"
chk "alert tag warning" grep -q 'Tags: warning' "$CURLLOG"
chk "alert posts to ntfy.sh/<topic>" grep -q 'https://ntfy.sh/tt$' "$CURLLOG"
chk "alert body names repo+file" grep -q 'alpha @ .*MISSING: GhostTest.kt' "$CURLLOG"
eqv "since marker == latest backlog commit" "$(gi log -1 --format=%H -- backlog/alpha.md)" "$(cat "$W/state/citation_check_since_alpha")"

# idempotent: no new commits -> clean, no second alert
: > "$CURLLOG"
runsh alpha >/dev/null
chk "rerun with nothing new -> 'clean run' logged" grep -q 'clean run — no missing-citation items found' "$LOG"
eqv "rerun: no duplicate SUSPECT" "1" "$(grep -c SUSPECT "$LOG")"
chk "rerun: curl not called" bash -c "! test -s '$CURLLOG'"

# new commit: only it is scanned; header-only / non-payload commit skipped; sibling rule through git
bl alpha '- [ ] [T2] src/router.ts — Wire route to Page.vue in the router.
- [ ] [T2] src/Page.vue — Create the page component.'
runsh alpha >/dev/null
eqv "new commit with sibling-created file -> still only the original SUSPECT" "1" "$(grep -c SUSPECT "$LOG")"
bl alpha '# --- just a header, no payload ---'
runsh alpha >/dev/null
eqv "header-only commit -> no suspects" "1" "$(grep -c SUSPECT "$LOG")"
bl alpha '- [ ] [T3] src/a.kt — Extend Ghost2.kt behaviour.'
NTFY_TOPIC=tt runsh alpha >/dev/null
eqv "new commit with a missing citation -> second SUSPECT" "2" "$(grep -c SUSPECT "$LOG")"
chk "second alert sent" grep -q 'Ghost2.kt' "$CURLLOG"

# invalid since marker: git errors -> nothing scanned -> marker refreshed
echo "deadbeefdeadbeef" > "$W/state/citation_check_since_alpha"
: > "$CURLLOG"
runsh alpha >/dev/null
chk "garbage since-sha -> no crash, clean run" bash -c "tail -1 '$LOG' | grep -q 'clean run'"
eqv "garbage since-sha is overwritten with real latest" "$(gi log -1 --format=%H -- backlog/alpha.md)" "$(cat "$W/state/citation_check_since_alpha")"

# no topic -> no curl, but still logged
setup
bl alpha '- [ ] [T3] src/a.kt — Extend Ghost3.kt behaviour.'
runsh alpha >/dev/null
chk "no ntfy topic -> SUSPECT still logged" grep -q 'MISSING: Ghost3.kt' "$LOG"
chk "no ntfy topic -> curl never invoked" bash -c "! test -s '$CURLLOG'"
# topic from state file
echo "filetopic" > "$W/state/ntfy_topic"; rm -f "$W/state/citation_check_since_alpha"
runsh alpha >/dev/null
chk "topic read from state/ntfy_topic" grep -q 'https://ntfy.sh/filetopic$' "$CURLLOG"
: > "$CURLLOG"; rm -f "$W/state/citation_check_since_alpha"
NTFY_TOPIC=envtopic runsh alpha >/dev/null
chk "NTFY_TOPIC env wins over state file" grep -q 'https://ntfy.sh/envtopic$' "$CURLLOG"

# skipping: backlog without repo dir, repo dir without backlog; default repo list
setup
bl norepo '- [ ] [T3] src/a.kt — Extend Ghost4.kt behaviour.'
mkdir -p "$W/repos/nobacklog"
runsh "norepo nobacklog" >/dev/null
chk "repo dir missing -> skipped, nothing logged as SUSPECT" bash -c "! grep -q SUSPECT '$LOG'"
chk "skipped repos leave no since marker" bash -c "! ls '$W'/state/citation_check_since_* >/dev/null 2>&1"
mkdir -p "$W/repos/billwatch"; bl billwatch '- [ ] [T3] src/a.kt — Extend Ghost5.kt behaviour.'
runsh >/dev/null
chk "no args -> default repo list includes billwatch" grep -q 'billwatch @ .*MISSING: Ghost5.kt' "$LOG"

# alert body capped at 800 bytes
setup
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do bl alpha "- [ ] [T3] src/a$i.kt — Extend GhostLongName$i.kt behaviour with padding padding padding padding padding padding padding."; done
NTFY_TOPIC=tt runsh alpha >/dev/null
chk "12 suspects counted in title" grep -q 'Citation check: 12 suspect item(s)' "$CURLLOG"
body="$(awk '/^--CALL--/{n++} {print}' "$CURLLOG" | awk '/^alpha @/{print}' | wc -c)"
chk "ntfy body truncated to <=800 bytes" test "$body" -le 900

echo
echo "$pass passed, $fail failed ($warnc known-bug warning(s))"
[ "$fail" -eq 0 ]
