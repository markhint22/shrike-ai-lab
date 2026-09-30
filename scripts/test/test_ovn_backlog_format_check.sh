#!/usr/bin/env bash
# Regression tests for ovn_backlog_format_check.sh: shadow-mode detector for "header-only backlog" commits
# (a commit adds "# --- decomposed ... ---" header(s) to backlog/<repo>.md but zero "- [ ] [T1..5]" payload lines).
# Hermetic: fake $HOME/overnight-queue git repo, curl stubbed, script PATH line patched so the stub wins.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_HOME="$HOME"
SH="$HERE/../ovn_backlog_format_check.sh"; [ -f "$SH" ] || SH="$REAL_HOME/overnight-queue/scripts/ovn_backlog_format_check.sh"
[ -f "$SH" ] || { echo "  SKIP: ovn_backlog_format_check.sh not found on this host"; exit 0; }
command -v git >/dev/null || { echo "  SKIP: git missing"; exit 0; }
unset NTFY_TOPIC
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
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
  rm -rf "$T/w" "$CURLLOG"; mkdir -p "$W"/{scripts,state,logs,backlog}
  sed "s|^export PATH=.*|export PATH=\"$STUB:/usr/bin:/bin\"|" "$SH" > "$W/scripts/ovn_backlog_format_check.sh"
  gi init -q; printf 'logs/\nstate/\n' > "$W/.gitignore"; gi add .gitignore; gi commit -q -m init
}
bl(){ printf '%s\n' "$2" >> "$W/backlog/$1.md"; gi add backlog; gi commit -q -m "backlog $1 $RANDOM"; }
runsh(){ HOME="$T/w" bash "$W/scripts/ovn_backlog_format_check.sh" "$@" 2>&1; }
LOG="$W/logs/ovn_backlog_format_check.log"
sha9(){ gi log -1 --format=%h --abbrev=9 -- "backlog/$1.md"; }

HOME="$T/none" bash "$SH" >/dev/null 2>&1; eqv "no ~/overnight-queue -> exit 1" "1" "$?"

echo "== detection =="
setup
bl alpha '# --- decomposed from roadmap: feature X ---'
NTFY_TOPIC=tt runsh alpha >/dev/null; rc=$?
eqv "exit 0" "0" "$rc"
chk "header-only commit flagged with sha + count" grep -q "SUSPECT: alpha backlog commit $(sha9 alpha) added 1 header(s) with ZERO real \[T#\] payload lines" "$LOG"
chk "summary line" grep -q '=== 1 header-only-backlog commit(s) found this run ===' "$LOG"
chk "alert sent once" test "$(grep -c -- '--CALL--' "$CURLLOG")" = 1
chk "alert title" grep -q 'Title: Backlog format check: 1 suspect commit(s)' "$CURLLOG"
chk "alert tags" grep -q 'Tags: warning' "$CURLLOG"
chk "alert url uses topic" grep -q 'https://ntfy.sh/tt$' "$CURLLOG"
chk "alert body is the report" grep -q 'alpha backlog commit .* added 1 header(s)' "$CURLLOG"
eqv "since marker == latest commit" "$(gi log -1 --format=%H -- backlog/alpha.md)" "$(cat "$W/state/backlog_check_since_alpha")"

# idempotent rerun
: > "$CURLLOG"
runsh alpha >/dev/null
chk "rerun -> clean run logged" grep -q 'clean run — no header-only-backlog commits found' "$LOG"
eqv "rerun: suspect not re-reported" "1" "$(grep -c SUSPECT "$LOG")"
chk "rerun: no curl" bash -c "! test -s '$CURLLOG'"

echo "== non-suspect shapes =="
bl alpha '# --- decomposed again ---
- [ ] [T1] a.py — do a thing. VERIFY: pytest x'
runsh alpha >/dev/null
eqv "header + real payload is fine" "1" "$(grep -c SUSPECT "$LOG")"
bl alpha '- [ ] [T3] b.py — payload only, no header'
runsh alpha >/dev/null
eqv "payload-only commit fine" "1" "$(grep -c SUSPECT "$LOG")"
bl alpha 'plain prose line, no header no payload'
runsh alpha >/dev/null
eqv "commit with neither fine" "1" "$(grep -c SUSPECT "$LOG")"
bl alpha '#--- not a header (no space) ---'
runsh alpha >/dev/null
eqv "'#---' without the space does not count as a header" "1" "$(grep -c SUSPECT "$LOG")"

echo "== shapes that ARE suspect =="
bl alpha '# --- h1 ---
# --- h2 ---'
runsh alpha >/dev/null
chk "two headers, zero payload -> 'added 2 header(s)'" grep -q 'added 2 header(s) with ZERO' "$LOG"
bl alpha '# --- h3 ---
- [x] [T1] done.py — already done line is not a payload line'
runsh alpha >/dev/null
chk "header + only a checked-off [x] line -> suspect" grep -q "alpha backlog commit $(sha9 alpha) added 1 header" "$LOG"
bl alpha '# --- h4 ---
- [ ] [T6] zz.py — tier 6 does not exist'
runsh alpha >/dev/null
eqv "header + [T6] (invalid tier) -> suspect (4 SUSPECT lines total)" "4" "$(grep -c 'SUSPECT' "$LOG")"

echo "== multi-repo, markers, topics =="
setup
bl alpha '# --- a ---'
bl bravo '# --- b ---'
bl bravo '# --- b2 ---'
NTFY_TOPIC=tt runsh "alpha bravo" >/dev/null
chk "3 suspects across repos counted (alpha 1 + bravo 2 commits)" grep -q '=== 3 header-only-backlog commit(s)' "$LOG"
chk "title aggregates count" grep -q 'Backlog format check: 3 suspect commit(s)' "$CURLLOG"
chk "markers written for both repos" test -f "$W/state/backlog_check_since_alpha" -a -f "$W/state/backlog_check_since_bravo"

setup
bl alpha '# --- a ---'
runsh alpha >/dev/null
chk "no topic: still logged" grep -q SUSPECT "$LOG"
chk "no topic: curl never called" bash -c "! test -s '$CURLLOG'"
echo ftopic > "$W/state/ntfy_topic"; rm -f "$W/state/backlog_check_since_alpha"
runsh alpha >/dev/null
chk "topic from state/ntfy_topic" grep -q 'https://ntfy.sh/ftopic$' "$CURLLOG"
rm -f "$W/state/backlog_check_since_alpha"; : > "$CURLLOG"
NTFY_TOPIC=etopic runsh alpha >/dev/null
chk "env topic wins" grep -q 'https://ntfy.sh/etopic$' "$CURLLOG"

# missing backlog file skipped; default repo list; garbage since-sha
setup
runsh ghost >/dev/null
chk "missing backlog file -> skipped, clean" grep -q 'clean run' "$LOG"
chk "missing backlog file -> no marker" bash -c "! ls '$W'/state/backlog_check_since_* >/dev/null 2>&1"
bl billwatch '# --- dflt ---'
runsh >/dev/null
chk "default repo list includes billwatch" grep -q 'SUSPECT: billwatch backlog commit' "$LOG"
echo notasha > "$W/state/backlog_check_since_billwatch"
runsh billwatch >/dev/null
chk "garbage since-sha: no crash, no new suspect" test "$(grep -c SUSPECT "$LOG")" = 1
eqv "garbage since-sha overwritten" "$(gi log -1 --format=%H -- backlog/billwatch.md)" "$(cat "$W/state/backlog_check_since_billwatch")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
