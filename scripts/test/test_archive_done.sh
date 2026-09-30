#!/usr/bin/env bash
# Regression: archive_done.py (move "- [x]" items out of OVERNIGHT_PROGRESS.md into OVERNIGHT_DONE.md) and its wrapper
# archive_done.sh (hold -> sync -> archive -> commit+push -> release, per repo). Hermetic: python half runs on temp files;
# wrapper half runs against a fake ~/overnight-queue under a temp HOME with local bare-repo origins and a stub queue.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
find_sut(){ local c; for c in "$HERE/../../$1" "$HERE/../$1" "$HERE/$1"; do [ -f "$c" ] && { echo "$c"; return; }; done; }
PY="$(find_sut archive_done.py)"; SH="$(find_sut archive_done.sh)"
[ -n "$PY" ] && [ -n "$SH" ] || { echo "archive_done.{py,sh} not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TODAY="$(python3 -c 'import datetime;print(datetime.date.today().isoformat())')"

# ================= archive_done.py =================
P="$T/prog.md"; A="$T/arch.md"
printf '%s\n' '# Progress' '## Next Steps' '- [ ] open one' '  - [x] indented done' '- [X] UPPER done' '- [x] plain done' '-[x] no-space is not an item' '- [ ] text mentioning [x] mid-line' 'trailing notes' > "$P"
out="$(python3 "$PY" "$P" "$A")"; rc=$?
ok "py: rc 0 and prints MOVED/KEPT_OPEN counts" "$([ $rc = 0 ] && [ "$out" = "MOVED=3 KEPT_OPEN=2" ] && echo 1 || echo 0)"
ok "py: [x]/[X]/indented done items leave the progress file" "$(! grep -qE '^\s*- \[[xX]\]' "$P" && echo 1 || echo 0)"
ok "py: headers, open items, notes and look-alikes are kept in order" "$([ "$(cat "$P")" = "$(printf '%s\n' '# Progress' '## Next Steps' '- [ ] open one' '-[x] no-space is not an item' '- [ ] text mentioning [x] mid-line' 'trailing notes')" ] && echo 1 || echo 0)"
ok "py: progress file ends with exactly one trailing newline" "$(python3 -c 'import sys;b=open(sys.argv[1],"rb").read();sys.exit(0 if b.endswith(b"\n") and not b.endswith(b"\n\n") else 1)' "$P" && echo 1 || echo 0)"
ok "py: archive gets dated header with the count" "$(grep -qx "<!-- archived $TODAY: 3 completed items moved out of OVERNIGHT_PROGRESS.md -->" "$A" && echo 1 || echo 0)"
ok "py: archive holds the moved lines verbatim (incl. indentation)" "$(grep -qxF '  - [x] indented done' "$A" && grep -qxF -- '- [X] UPPER done' "$A" && grep -qxF -- '- [x] plain done' "$A" && echo 1 || echo 0)"
# second run: idempotent / nothing to do
cp "$P" "$T/prog.before"; cp "$A" "$T/arch.before"
out="$(python3 "$PY" "$P" "$A")"
ok "py: re-run -> 'MOVED=0 KEPT=<open+checked-lookalike lines starting with - [>'" "$([ "$out" = "MOVED=0 KEPT=2" ] && echo 1 || echo 0)"
ok "py: re-run leaves both files byte-identical" "$(cmp -s "$P" "$T/prog.before" && cmp -s "$A" "$T/arch.before" && echo 1 || echo 0)"
# append to an existing archive
printf '%s\n' '- [ ] new open' '- [x] later done' >> "$P"
out="$(python3 "$PY" "$P" "$A")"
ok "py: later batch is appended (not overwritten) with its own header" "$([ "$out" = "MOVED=1 KEPT_OPEN=3" ] && [ "$(grep -c '<!-- archived' "$A")" = 2 ] && grep -qxF -- '- [x] later done' "$A" && grep -qxF -- '- [x] plain done' "$A" && echo 1 || echo 0)"
# no done items -> archive never created
P2="$T/p2.md"; printf '%s\n' '- [ ] a' '- [ ] b' 'note' > "$P2"; cp "$P2" "$T/p2.before"
out="$(python3 "$PY" "$P2" "$T/never.md")"
ok "py: nothing done -> MOVED=0, archive file not created, progress untouched" "$([ "$out" = "MOVED=0 KEPT=2" ] && [ ! -e "$T/never.md" ] && cmp -s "$P2" "$T/p2.before" && echo 1 || echo 0)"
# everything done
P3="$T/p3.md"; printf '%s\n' '- [x] only' '- [x] done' > "$P3"
out="$(python3 "$PY" "$P3" "$T/a3.md")"
ok "py: all-done file -> progress reduced to a single newline, KEPT_OPEN=0" "$([ "$out" = "MOVED=2 KEPT_OPEN=0" ] && [ "$(cat "$P3" | wc -c | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
# empty progress file
: > "$T/p4.md"; out="$(python3 "$PY" "$T/p4.md" "$T/a4.md")"
ok "py: empty progress file -> MOVED=0 KEPT=0" "$([ "$out" = "MOVED=0 KEPT=0" ] && echo 1 || echo 0)"
# CRLF / unicode safety
printf -- '- [x] done — with em-dash é\r\n- [ ] open\r\n' > "$T/p5.md"; python3 "$PY" "$T/p5.md" "$T/a5.md" >/dev/null
ok "py: utf-8 content round-trips into the archive" "$(grep -q 'done — with em-dash é' "$T/a5.md" && echo 1 || echo 0)"
# error paths
python3 "$PY" >/dev/null 2>&1; ok "py: no args -> nonzero (usage error)" "$([ $? != 0 ] && echo 1 || echo 0)"
python3 "$PY" "$T/does-not-exist.md" "$T/x.md" >/dev/null 2>&1; ok "py: missing progress file -> nonzero" "$([ $? != 0 ] && echo 1 || echo 0)"

# ================= archive_done.sh =================
export HOME="$T/home"; Q="$HOME/overnight-queue"; mkdir -p "$Q/repos"; cp "$PY" "$Q/archive_done.py"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
QLOG="$T/queue.log"; : > "$QLOG"
printf '#!/usr/bin/env bash\necho "queue.sh $*" >> "%s"\n' "$QLOG" > "$Q/queue.sh"; chmod +x "$Q/queue.sh"
g(){ git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
mkrepo(){  # $1=repo $2=progress content (printf-able) ; "" = no progress file
  local r="$1" o="$T/origin_$1.git" s="$T/seed_$1"
  g init -q --bare "$o"; g init -q "$s"; echo readme > "$s/README.md"
  [ -n "$2" ] && printf "$2" > "$s/OVERNIGHT_PROGRESS.md"
  ( cd "$s" && g add -A && g commit -q -m seed && g push -q "$o" HEAD:refs/heads/overnight/feature )
  g clone -q -b overnight/feature "$o" "$Q/repos/$r" 2>/dev/null
  cat > "$o/hooks/pre-receive" <<H
#!/bin/sh
m="$T/mode_$r"
if [ -f "\$m" ]; then mode="\$(cat "\$m")"; [ "\$mode" = always ] && exit 1; [ "\$mode" = once ] && { rm -f "\$m"; exit 1; }; fi
exit 0
H
  chmod +x "$o/hooks/pre-receive"
}
rfile(){ g --git-dir="$T/origin_$1.git" show "overnight/feature:$2" 2>/dev/null; }
rlog(){ g --git-dir="$T/origin_$1.git" log --format='%an|%ae|%s' overnight/feature; }
BODY='# P\n- [ ] open1\n- [x] done1\n- [x] done2\n- [ ] open2\n'
mkrepo alpha "$BODY"
mkrepo beta '# P\n- [ ] only open\n'
mkrepo gamma ""                                   # no progress file
mkrepo delta "$BODY"; g -C "$Q/repos/delta" remote set-url origin "$T/nonexistent.git"     # fetch fails -> sync failed
mkrepo eps "$BODY"; echo always > "$T/mode_eps"   # push always rejected
mkrepo zeta "$BODY"; echo once > "$T/mode_zeta"   # first push rejected, rebase retry works
mkrepo eta "$BODY"; printf -- '- [x] old archived\n' > "$T/eta_done"
run(){ ( cd "$T"; bash "$SH" "$@" > "$T/out" 2> "$T/err" ); rc=$?; }

run; ok "sh: no repo args -> exit 0, no output" "$([ $rc = 0 ] && [ ! -s "$T/out" ] && [ ! -s "$QLOG" ] && echo 1 || echo 0)"
mv "$Q" "$T/q.away"; ( cd "$T"; bash "$SH" alpha >/dev/null 2>&1 ); rc=$?; mv "$T/q.away" "$Q"
ok "sh: missing ~/overnight-queue -> exit 1" "$([ $rc = 1 ] && echo 1 || echo 0)"

run alpha beta gamma delta eps zeta
ok "sh: exit 0 overall" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "alpha: reports 'archived 2 done items (6 -> 4 lines)'" "$(grep -qx 'alpha: archived 2 done items (5 -> 3 lines)' "$T/out" && echo 1 || echo 0)"
ok "alpha: origin progress file no longer has [x] items" "$(! rfile alpha OVERNIGHT_PROGRESS.md | grep -q '\[x\]' && rfile alpha OVERNIGHT_PROGRESS.md | grep -q 'open2' && echo 1 || echo 0)"
ok "alpha: origin archive file holds both done items" "$(rfile alpha OVERNIGHT_DONE.md | grep -q -- '- \[x\] done1' && rfile alpha OVERNIGHT_DONE.md | grep -q -- '- \[x\] done2' && echo 1 || echo 0)"
ok "alpha: commit by shrike-fleet, message carries the count" "$(rlog alpha | head -1 | grep -q '^shrike-fleet|fleet@shrike.local|chore(queue): archive 2 completed items' && echo 1 || echo 0)"
ok "alpha: commit touches exactly progress + done files" "$([ "$(g --git-dir="$T/origin_alpha.git" show --name-only --format= overnight/feature | sort | tr '\n' ' ')" = 'OVERNIGHT_DONE.md OVERNIGHT_PROGRESS.md ' ] && echo 1 || echo 0)"
ok "beta: nothing to archive, reports line count, no commit" "$(grep -qx 'beta: nothing to archive (2 lines)' "$T/out" && [ "$(rlog beta | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "gamma: no progress file -> reported, never held" "$(grep -qx 'gamma: no progress file' "$T/out" && ! grep -q 'gamma' "$QLOG" && echo 1 || echo 0)"
ok "delta: fetch failure -> 'sync failed' and hold released" "$(grep -qx 'delta: sync failed' "$T/out" && grep -qx 'queue.sh release delta' "$QLOG" && echo 1 || echo 0)"
ok "eps: persistent push rejection -> 'push failed'" "$(grep -qx 'eps: push failed' "$T/out" && ! rfile eps OVERNIGHT_DONE.md | grep -q done1 && echo 1 || echo 0)"
ok "zeta: first push rejected, pull --rebase + retry lands the archive" "$(grep -qx 'zeta: archived 2 done items (5 -> 3 lines)' "$T/out" && rfile zeta OVERNIGHT_DONE.md | grep -q done2 && echo 1 || echo 0)"
ok "each processed repo is held then released (incl. failures)" "$(for r in alpha beta delta eps zeta; do h=$(grep -n "^queue.sh hold $r\$" "$QLOG" | head -1 | cut -d: -f1); l=$(grep -n "^queue.sh release $r\$" "$QLOG" | tail -1 | cut -d: -f1); [ -n "$h" ] && [ -n "$l" ] && [ "$h" -lt "$l" ] || { echo 0; exit; }; done; echo 1)"
# idempotent re-run on alpha
run alpha
ok "alpha re-run: nothing left to archive (idempotent, no extra commit)" "$(grep -qx 'alpha: nothing to archive (3 lines)' "$T/out" && [ "$(rlog alpha | wc -l | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
# hard reset discards stale local progress before archiving
printf '# local stale\n- [x] stale local\n' > "$Q/repos/beta/OVERNIGHT_PROGRESS.md"
run beta
ok "beta: local stale edits are reset to origin before archiving" "$(grep -qx 'beta: nothing to archive (2 lines)' "$T/out" && ! grep -q stale "$Q/repos/beta/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
# appends to an archive already present on origin
( cd "$Q/repos/eta" && cp "$T/eta_done" OVERNIGHT_DONE.md && g add -A && g commit -q -m "pre-existing archive" && g push -q origin overnight/feature )
run eta
ok "eta: pre-existing OVERNIGHT_DONE.md is appended to, not clobbered" "$(rfile eta OVERNIGHT_DONE.md | grep -q 'old archived' && rfile eta OVERNIGHT_DONE.md | grep -q done2 && echo 1 || echo 0)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
