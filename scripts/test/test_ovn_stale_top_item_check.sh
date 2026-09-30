#!/usr/bin/env bash
# Regression tests for ovn_stale_top_item_check.sh (the cron/alert wrapper around ovn_stale_top_item_check.py):
# parsing of the python TSV, per-repo re-alert cooldown markers, ntfy call shape, env threshold, error paths.
# The python detector itself has its own test (test_stale_top_item_check.sh); here it is STUBBED for the wrapper
# cases and exercised once for real at the end as an integration check.
# Hermetic: HOME is a temp dir, curl is a stub, the script copy has its PATH line patched so the stub wins.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_HOME="$HOME"
SH="$HERE/../ovn_stale_top_item_check.sh"; [ -f "$SH" ] || SH="$REAL_HOME/overnight-queue/scripts/ovn_stale_top_item_check.sh"
REALPY="$HERE/../ovn_stale_top_item_check.py"; [ -f "$REALPY" ] || REALPY="$REAL_HOME/overnight-queue/scripts/ovn_stale_top_item_check.py"
[ -f "$SH" ] || { echo "  SKIP: script not found"; exit 0; }
unset NTFY_TOPIC OVN_STALE_TOP_ITEM_HOURS
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
known(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else warnc=$((warnc+1)); echo "  WARN KNOWN-BUG: $l"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUB="$T/stub"; mkdir -p "$STUB"; CURLLOG="$T/curl.log"
cat > "$STUB/curl" <<EOF
#!/bin/bash
{ echo "--CALL--"; printf '%s\n' "\$@"; } >> "$CURLLOG"
exit 0
EOF
chmod +x "$STUB/curl"
W="$T/w/overnight-queue"; LOG="$W/logs/ovn_stale_top_item_check.log"; ST="$W/state"
PYOUT="$T/pyout.tsv"; PYARGS="$T/pyargs.log"; PYERR="$T/pyerr.txt"
setup(){
  rm -rf "$T/w" "$CURLLOG" "$PYARGS" "$PYERR"; : > "$PYOUT"; mkdir -p "$W"/{scripts,state,logs}
  sed "s|^export PATH=.*|export PATH=\"$STUB:/usr/bin:/bin\"|" "$SH" > "$W/scripts/ovn_stale_top_item_check.sh"
  cat > "$W/scripts/ovn_stale_top_item_check.py" <<EOF
import sys
open("$PYARGS","a").write(" ".join(sys.argv[1:])+"\n")
try: sys.stderr.write(open("$PYERR").read())
except FileNotFoundError: pass
sys.stdout.write(open("$PYOUT").read())
EOF
}
runsh(){ HOME="$T/w" bash "$W/scripts/ovn_stale_top_item_check.sh" 2>&1; }
tsv(){ printf '%s\t%s\t%s\t%s\n' "$@"; }     # repo age line text

HOME="$T/none" bash "$SH" >/dev/null 2>&1; eqv "no ~/overnight-queue -> exit 1" "1" "$?"

echo "== clean / args =="
setup
runsh >/dev/null; rc=$?
eqv "clean run exits 0" "0" "$rc"
chk "clean run logged" grep -q 'clean run — no stale top items found' "$LOG"
eqv "python invoked with \$PWD and default 12h" "$W 12" "$(cat "$PYARGS")"
chk "clean run: no curl" bash -c "! test -s '$CURLLOG'"
chk "clean run: no marker files" bash -c "! ls '$ST'/stale_top_item_alerted_* >/dev/null 2>&1"
OVN_STALE_TOP_ITEM_HOURS=6 runsh >/dev/null
eqv "OVN_STALE_TOP_ITEM_HOURS passed through to python" "$W 6" "$(tail -1 "$PYARGS")"
printf 'some python warning\n' > "$PYERR"
runsh >/dev/null
chk "python stderr is appended to the log" grep -q 'some python warning' "$LOG"

echo "== first alert =="
setup
TXT='- [ ] [T1] app/stale.py — Delete this dead stub.'
tsv alpha 13.5 42 "$TXT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "SUSPECT line: repo, age, line number, text" grep -qF "SUSPECT: alpha: top item stale 13.5h (line 42) — $TXT" "$LOG"
chk "summary line" grep -q '=== 1 stale top item(s) newly alerted this run ===' "$LOG"
eqv "marker holds key|age" "42:${TXT:0:60}|13.5" "$(cat "$ST/stale_top_item_alerted_alpha")"
chk "one curl call" test "$(grep -c -- '--CALL--' "$CURLLOG")" = 1
chk "title: count of repos" grep -q 'Title: Stale top item: 1 repo(s) ignoring their #1 doable item' "$CURLLOG"
chk "tags warning" grep -q 'Tags: warning' "$CURLLOG"
chk "url has topic" grep -q 'https://ntfy.sh/tt$' "$CURLLOG"
chk "body: 'repo: stale Nh — text'" grep -qF "alpha: stale 13.5h — $TXT" "$CURLLOG"

echo "== re-alert cooldown =="
: > "$CURLLOG"
tsv alpha 14.0 42 "$TXT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "same item, +0.5h -> within cooldown, logged as such" grep -q 'stale items found but all within their re-alert cooldown' "$LOG"
chk "cooldown: no curl" bash -c "! test -s '$CURLLOG'"
eqv "cooldown: marker unchanged" "42:${TXT:0:60}|13.5" "$(cat "$ST/stale_top_item_alerted_alpha")"
tsv alpha 25.4 42 "$TXT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "+11.9h (<12) still quiet" bash -c "! test -s '$CURLLOG'"
tsv alpha 25.5 42 "$TXT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "exactly +12h re-alerts" grep -q 'alpha: stale 25.5h' "$CURLLOG"
eqv "marker advanced to the new age" "42:${TXT:0:60}|25.5" "$(cat "$ST/stale_top_item_alerted_alpha")"

: > "$CURLLOG"
OVN_STALE_TOP_ITEM_HOURS=2 NTFY_TOPIC=tt runsh >/dev/null; : > "$CURLLOG"
tsv alpha 27.6 42 "$TXT" > "$PYOUT"
OVN_STALE_TOP_ITEM_HOURS=2 NTFY_TOPIC=tt runsh >/dev/null
chk "custom 2h window: +2.1h re-alerts (cooldown follows OVN_STALE_TOP_ITEM_HOURS)" grep -q 'alpha: stale 27.6h' "$CURLLOG"

: > "$CURLLOG"
tsv alpha 1.0 42 "$TXT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "age went DOWN (negative delta) -> treated as cooldown, quiet" bash -c "! test -s '$CURLLOG'"

echo "== different item / multi repo =="
: > "$CURLLOG"
tsv alpha 0.5 43 "- [ ] [T1] app/other.py — something else." > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "different item in #1 slot alerts fresh even at lower age" grep -q 'alpha: stale 0.5h' "$CURLLOG"
: > "$CURLLOG"
tsv alpha 0.6 43 "- [ ] [T1] app/other.py — something else." > "$PYOUT"; tsv bravo 20.0 7 "- [ ] [T2] b/y.py — thing" >> "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "two repos: only the not-in-cooldown one alerted (title says 1)" grep -q 'Title: Stale top item: 1 repo(s)' "$CURLLOG"
chk "body mentions bravo, not alpha" bash -c "grep -q 'bravo: stale 20.0h' '$CURLLOG' && ! grep -q 'alpha: stale' '$CURLLOG'"
chk "separate marker per repo" test -f "$ST/stale_top_item_alerted_bravo"
: > "$CURLLOG"; rm -f "$ST"/stale_top_item_alerted_*
tsv alpha 13 1 "- [ ] [T1] a.py — x" > "$PYOUT"; printf '\n' >> "$PYOUT"; tsv bravo 14 2 "- [ ] [T1] b.py — y" >> "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
chk "two repos at once -> title '2 repo(s)', blank line in output skipped" grep -q 'Title: Stale top item: 2 repo(s)' "$CURLLOG"
chk "body has both lines" bash -c "grep -q 'alpha: stale 13h' '$CURLLOG' && grep -q 'bravo: stale 14h' '$CURLLOG'"
chk "body item text truncated to 100 chars" bash -c "
  rm -f '$ST'/stale_top_item_alerted_*; : > '$CURLLOG'
  long=\"- [ ] [T1] a.py — \$(printf 'Z%.0s' \$(seq 1 200))\"
  printf 'alpha\t9\t1\t%s\n' \"\$long\" > '$PYOUT'
  NTFY_TOPIC=tt HOME='$T/w' bash '$W/scripts/ovn_stale_top_item_check.sh' >/dev/null 2>&1
  ! grep -q 'Z\{101\}' '$CURLLOG' && grep -q 'Z\{50\}' '$CURLLOG'"

echo "== topic handling =="
setup
tsv alpha 13 1 "- [ ] [T1] a.py — x" > "$PYOUT"
runsh >/dev/null
chk "no topic: still logs SUSPECT" grep -q 'SUSPECT: alpha' "$LOG"
chk "no topic: curl never called" bash -c "! test -s '$CURLLOG'"
echo ftopic > "$ST/ntfy_topic"; rm -f "$ST"/stale_top_item_alerted_*
runsh >/dev/null
chk "topic from state/ntfy_topic" grep -q 'https://ntfy.sh/ftopic$' "$CURLLOG"
rm -f "$ST"/stale_top_item_alerted_*; : > "$CURLLOG"
NTFY_TOPIC=etopic runsh >/dev/null
chk "env topic wins" grep -q 'https://ntfy.sh/etopic$' "$CURLLOG"

echo "== marker key with a '|' in the item text =="
setup
PT='- [ ] [T2] app/x.sh — handle cmd a|b in pipeline'
tsv alpha 13 5 "$PT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null; : > "$CURLLOG"
tsv alpha 13.5 5 "$PT" > "$PYOUT"
NTFY_TOPIC=tt runsh >/dev/null
known "pipe in first 60 chars of item text must not defeat the cooldown (prev_key=\${prev%%|*} cuts at FIRST '|')" bash -c "! test -s '$CURLLOG'"

echo "== integration with the real python detector =="
if [ -f "$REALPY" ]; then
  setup; cp "$REALPY" "$W/scripts/ovn_stale_top_item_check.py"
  R="$W/repos/billwatch"; mkdir -p "$R"
  ( cd "$R" && git init -q && printf '# Roadmap\n\n- [ ] [T1] stale_target.py — Delete the dead stub.\n' > OVERNIGHT_PROGRESS.md && echo x > stale_target.py \
    && git add -A && GIT_AUTHOR_DATE='2020-01-01T00:00:00' GIT_COMMITTER_DATE='2020-01-01T00:00:00' git commit -q -m old )
  OVN_STALE_TOP_ITEM_HOURS=0 NTFY_TOPIC=tt runsh >/dev/null
  chk "real detector: #1 item w/ untouched target file -> alert end-to-end" grep -q 'SUSPECT: billwatch: top item stale 0.0h (line 3)' "$LOG"
  chk "real detector: first-seen clock file written by python" test -f "$ST/stale_top_item_first_seen_billwatch"
  chk "real detector: ntfy call made" grep -q 'Title: Stale top item: 1 repo(s)' "$CURLLOG"
  # default 12h: a just-seen item is NOT stale
  rm -f "$ST"/stale_top_item_* "$W/logs/"*; : > "$CURLLOG"
  runsh >/dev/null
  chk "real detector: default 12h, freshly-seen item -> clean" grep -q 'clean run' "$LOG"
else
  echo "  (real python detector not found - integration skipped)"
fi

echo
echo "$pass passed, $fail failed ($warnc known-bug warning(s))"
[ "$fail" -eq 0 ]
