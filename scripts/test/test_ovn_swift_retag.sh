#!/usr/bin/env bash
# Regression: ovn_swift_retag.py tags open, unparked items whose text names a .swift file as AUTO-SKIP (max-retags cap,
# RETAGGED=<n> contract); ovn_swift_retag.sh wraps it per repo (hold -> sync -> retag -> commit+push -> release).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../../ovn_swift_retag.py"; [ -f "$PY" ] || PY="$HERE/../ovn_swift_retag.py"; [ -f "$PY" ] || PY="$HERE/ovn_swift_retag.py"
SH="$HERE/../../ovn_swift_retag.sh"; [ -f "$SH" ] || SH="$HERE/../ovn_swift_retag.sh"; [ -f "$SH" ] || SH="$HERE/ovn_swift_retag.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
both(){ [ "$1" = 1 ] && [ "$2" = 1 ] && echo 1 || echo 0; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TAG='[AUTO-SKIP swift(no-fleet-verify)'

############ python script ############
P="$T/p.md"
printf '%s\n' '## Next Steps' \
  '- [ ] [T2] ios/Views/TVHistoryView.swift — refactor the row' \
  '- [ ] [T1] app/foo.py — python item' \
  '- [x] [T2] ios/Done.swift — already checked' \
  '- [ ] [T3] ios/Parked.swift — AUTO-SKIP already parked' \
  '- [ ] [T3] ios/H.swift — HUMAN-ONLY' \
  '- [ ] [T3] ios/B.swift — BLOCKED on x' \
  '- [ ] [T3] ios/R.swift — (retired-vague)' \
  '- [ ] [T2] Package.swiftpm notes — not a swift source' \
  '- [ ] [T4] ios/Other.swift and ios/Two.swift — two mentions' \
  '  - [ ] indented sub-item ios/Sub.swift' \
  'plain prose mentioning x.swift' > "$P"
out="$(python3 "$PY" "$P")"
ok "prints RETAGGED=2" "$([ "$out" = "RETAGGED=2" ] && echo 1 || echo 0)"
ok "swift item gets the AUTO-SKIP prefix right after the checkbox" "$(grep -qF -- "- [ ] $TAG" "$P" && grep -F 'TVHistoryView.swift' "$P" | grep -q "^- \[ \] \[AUTO-SKIP swift" && echo 1 || echo 0)"
ok "original tier tag and text kept after the prefix" "$(grep -q '^- \[ \] \[AUTO-SKIP[^]]*\] \[T2\] ios/Views/TVHistoryView.swift — refactor the row$' "$P" && echo 1 || echo 0)"
ok "second swift item also retagged (only first checkbox occurrence replaced)" "$([ "$(grep -c '\[AUTO-SKIP swift' "$P")" = 2 ] && grep 'Other.swift' "$P" | grep -q '^- \[ \] \[AUTO-SKIP' && echo 1 || echo 0)"
ok "python item untouched" "$(grep -qxF -- '- [ ] [T1] app/foo.py — python item' "$P" && echo 1 || echo 0)"
ok "checked swift item untouched" "$(grep -qxF -- '- [x] [T2] ios/Done.swift — already checked' "$P" && echo 1 || echo 0)"
ok "AUTO-SKIP/HUMAN-ONLY/BLOCKED/retired- items are skipped (not double-tagged)" "$([ "$(grep -c 'AUTO-SKIP' "$P")" = 3 ] && grep -qxF -- '- [ ] [T3] ios/H.swift — HUMAN-ONLY' "$P" && grep -qxF -- '- [ ] [T3] ios/B.swift — BLOCKED on x' "$P" && grep -qxF -- '- [ ] [T3] ios/R.swift — (retired-vague)' "$P" && echo 1 || echo 0)"
ok ".swiftpm is not treated as a .swift target" "$(grep -qxF -- '- [ ] [T2] Package.swiftpm notes — not a swift source' "$P" && echo 1 || echo 0)"
ok "indented sub-item and prose lines ignored (must start with '- [ ] ')" "$(grep -qxF -- '  - [ ] indented sub-item ios/Sub.swift' "$P" && grep -qxF 'plain prose mentioning x.swift' "$P" && echo 1 || echo 0)"
ok "file line count preserved" "$([ "$(grep -c '' "$P")" = 12 ] && echo 1 || echo 0)"
cp "$P" "$T/b"; out="$(python3 "$PY" "$P")"
ok "idempotent: second run RETAGGED=0" "$([ "$out" = "RETAGGED=0" ] && echo 1 || echo 0)"
ok "idempotent: file unchanged" "$(cmp -s "$P" "$T/b" && echo 1 || echo 0)"

# max-retags cap
printf '%s\n' '- [ ] a.swift' '- [ ] b.swift' '- [ ] c.swift' '' > "$P"
out="$(python3 "$PY" "$P" 2)"
ok "cap arg: RETAGGED=2 of 3" "$([ "$out" = "RETAGGED=2" ] && echo 1 || echo 0)"
ok "cap arg: the third item left open for the next pass" "$(grep -qxF -- '- [ ] c.swift' "$P" && echo 1 || echo 0)"
printf '%s\n' '- [ ] a.swift' '- [ ] b.swift' > "$P"; cp "$P" "$T/b"
out="$(python3 "$PY" "$P" 0)"
ok "cap 0: nothing retagged, file untouched" "$([ "$out" = "RETAGGED=0" ] && cmp -s "$P" "$T/b" && echo 1 || echo 0)"
for i in $(seq 1 12); do echo "- [ ] f$i.swift"; done > "$P"
ok "default cap is 10" "$([ "$(python3 "$PY" "$P")" = "RETAGGED=10" ] && [ "$(grep -c '^- \[ \] f1[12].swift$' "$P")" = 2 ] && echo 1 || echo 0)"
: > "$P"; ok "empty file: RETAGGED=0" "$([ "$(python3 "$PY" "$P")" = "RETAGGED=0" ] && echo 1 || echo 0)"
printf -- '- [ ] x.swift' > "$P"; python3 "$PY" "$P" >/dev/null
ok "no trailing newline preserved exactly (no newline added)" "$([ "$(tail -c1 "$P" | xxd -p)" != "0a" ] && echo 1 || echo 0)"
python3 "$PY" "$T/nope.md" >/dev/null 2>&1; ok "missing file: nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"
python3 "$PY" >/dev/null 2>&1; ok "no args: nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"
python3 "$PY" "$P" notanumber >/dev/null 2>&1; ok "non-integer cap: nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"

############ shell wrapper ############
H="$T/home"; W="$H/overnight-queue"; O="$T/origins"; mkdir -p "$W/repos" "$W/logs" "$O"
cp "$SH" "$W/ovn_swift_retag.sh"; cp "$PY" "$W/ovn_swift_retag.py"
cat > "$W/queue.sh" <<Q
#!/usr/bin/env bash
echo "\$*" >> "$W/queue.calls"
Q
chmod +x "$W/queue.sh"
G(){ git -c user.email=t@t -c user.name=t "$@"; }
mkrepo(){ # name, progress-content
  local n="$1"; rm -rf "$O/$n.git" "$T/seed" "$W/repos/$n"
  git init -q --bare "$O/$n.git"; git clone -q "$O/$n.git" "$T/seed" 2>/dev/null
  ( cd "$T/seed" && G checkout -q -b overnight/feature && printf '%b' "$2" > OVERNIGHT_PROGRESS.md && G add -A && G commit -q -m seed && G push -q origin overnight/feature )
  git clone -q -b overnight/feature "$O/$n.git" "$W/repos/$n" 2>/dev/null; rm -rf "$T/seed"; }
run(){ : > "$W/queue.calls"; ( cd "$W" && HOME="$H" bash ./ovn_swift_retag.sh "$@" ) > "$T/out" 2>&1; echo $?; }
SW='- [ ] [T2] ios/A.swift — fix\n- [ ] [T1] app/a.py — py\n'
cat > "$W/tasks.json" <<J
[{"repo":"/srv/x/repos/alpha","type":"aider_fix"},
 {"repo":"/srv/x/repos/beta","type":"aider_fix","enabled":false},
 {"repo":"/srv/x/repos/gamma","type":"other"},
 {"repo":"/srv/x/repos/delta","type":"aider_fix","enabled":true},
 {"repo":"/srv/x/repos/alpha","type":"aider_fix"}]
J
mkrepo alpha "$SW"; mkrepo beta "$SW"; mkrepo gamma "$SW"; mkrepo delta '- [ ] [T1] app/a.py — py only\n'
rc="$(run)"
ok "tasks.json discovery run exits 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "enabled aider_fix repo alpha retagged + logged" "$(has "$(cat "$T/out")" 'alpha: AUTO-SKIPped 1 swift item(s)')"
ok "retag commit reached origin/overnight/feature" "$(git -C "$O/alpha.git" log overnight/feature --format=%s -1 | grep -q 'chore(queue): AUTO-SKIP 1 swift item(s)' && echo 1 || echo 0)"
ok "commit authored by shrike-fleet" "$([ "$(git -C "$O/alpha.git" log overnight/feature --format=%an -1)" = shrike-fleet ] && echo 1 || echo 0)"
ok "origin file carries the tag" "$(git -C "$O/alpha.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[AUTO-SKIP swift' && echo 1 || echo 0)"
ok "repo with nothing to retag logs 'nothing to retag' and makes no commit" "$(both "$(has "$(cat "$T/out")" 'delta: nothing to retag')" "$([ "$(git -C "$O/delta.git" rev-list --count overnight/feature)" = 1 ] && echo 1 || echo 0)")"
ok "disabled repo (beta) skipped" "$(! grep -q 'beta:' "$T/out" && [ "$(git -C "$O/beta.git" rev-list --count overnight/feature)" = 1 ] && echo 1 || echo 0)"
ok "non-aider_fix repo (gamma) skipped" "$(! grep -q 'gamma:' "$T/out" && echo 1 || echo 0)"
ok "duplicate tasks.json repo de-duplicated (alpha processed once)" "$([ "$(grep -c 'alpha:' "$T/out")" = 1 ] && echo 1 || echo 0)"
ok "queue hold+release called for each processed repo, release last" "$(grep -qx 'hold alpha' "$W/queue.calls" && grep -qx 'release alpha' "$W/queue.calls" && grep -qx 'hold delta' "$W/queue.calls" && [ "$(tail -1 "$W/queue.calls")" = 'release delta' ] && echo 1 || echo 0)"
ok "completion line logged" "$(has "$(cat "$T/out")" 'ovn_swift_retag pass complete')"
ok "log lines carry a timestamp prefix" "$(grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ' "$T/out" && echo 1 || echo 0)"

# second pass: idempotent
rc="$(run alpha)"
ok "explicit repo arg overrides tasks.json; rerun says nothing to retag" "$(has "$(cat "$T/out")" 'alpha: nothing to retag')"
ok "rerun adds no commit" "$([ "$(git -C "$O/alpha.git" rev-list --count overnight/feature)" = 2 ] && echo 1 || echo 0)"

# local drift is discarded by the hard reset
echo junk > "$W/repos/alpha/OVERNIGHT_PROGRESS.md"; run alpha >/dev/null
ok "local edits reset to origin before retag (no junk pushed)" "$(git -C "$O/alpha.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q junk && echo 0 || echo 1)"

# missing progress file / missing repo dir
rm -f "$W/repos/alpha/OVERNIGHT_PROGRESS.md"; : > "$W/queue.calls"; run alpha >/dev/null
ok "no progress file: logged + skipped without hold" "$(both "$(has "$(cat "$T/out")" 'alpha: no progress file, skipping')" "$([ ! -s "$W/queue.calls" ] && echo 1 || echo 0)")"

# git sync failure: origin branch gone -> skipped, hold released
mkrepo eps "$SW"; git -C "$O/eps.git" update-ref -d refs/heads/overnight/feature
run eps >/dev/null
ok "git sync failure logged and skipped" "$(has "$(cat "$T/out")" 'eps: git sync failed')"
ok "sync failure still releases the hold" "$(grep -qx 'release eps' "$W/queue.calls" && echo 1 || echo 0)"

# push rejected once -> pull --rebase + retry succeeds
mkrepo zeta "$SW"
printf '#!/bin/sh\n[ -f "%s/m" ] && exit 0\ntouch "%s/m"\nexit 1\n' "$T" "$T" > "$O/zeta.git/hooks/pre-receive"; chmod +x "$O/zeta.git/hooks/pre-receive"
run zeta >/dev/null
ok "first push rejected, retry path pushes and logs success" "$(has "$(cat "$T/out")" 'zeta: AUTO-SKIPped 1 swift item(s)')"
ok "retry landed on origin" "$(git -C "$O/zeta.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q AUTO-SKIP && echo 1 || echo 0)"

# push always rejected -> FAILED logged, hold released
mkrepo eta "$SW"
printf '#!/bin/sh\nexit 1\n' > "$O/eta.git/hooks/pre-receive"; chmod +x "$O/eta.git/hooks/pre-receive"
run eta >/dev/null
ok "permanent push failure logs 'retag push FAILED'" "$(has "$(cat "$T/out")" 'eta: retag push FAILED')"
ok "push failure still releases hold and completes pass" "$(both "$(grep -qx 'release eta' "$W/queue.calls" && echo 1 || echo 0)" "$(has "$(cat "$T/out")" 'pass complete')")"

# no tasks.json match and no args
echo '[]' > "$W/tasks.json"; rc="$(run)"
ok "empty task list: exits 0, only the completion line" "$(both "$([ "$rc" = 0 ] && echo 1 || echo 0)" "$([ "$(grep -c '' "$T/out")" = 1 ] && has "$(cat "$T/out")" 'pass complete')")"
rm -f "$W/tasks.json"; rc="$(run)"
ok "missing tasks.json tolerated (exit 0)" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
rc="$( cd "$T" && HOME="$T/nohome" bash "$SH" >/dev/null 2>&1; echo $? )"
ok "missing \$HOME/overnight-queue: exit 1" "$([ "$rc" = 1 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
