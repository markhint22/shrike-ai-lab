#!/usr/bin/env bash
# Regression: ovn_filesize_retag.sh wraps ovn_filesize_retag.py per repo (repo discovery from tasks.json, hold, hard-sync to
# origin/overnight/feature, retag large-file T1/T2 -> T3, commit+push with one retry, release). Hermetic fake $HOME tree,
# local bare origins, stub queue.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../../ovn_filesize_retag.py"; [ -f "$PY" ] || PY="$HERE/../ovn_filesize_retag.py"; [ -f "$PY" ] || PY="$HERE/ovn_filesize_retag.py"
SH="$HERE/../../ovn_filesize_retag.sh"; [ -f "$SH" ] || SH="$HERE/../ovn_filesize_retag.sh"; [ -f "$SH" ] || SH="$HERE/ovn_filesize_retag.sh"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
both(){ [ "$1" = 1 ] && [ "$2" = 1 ] && echo 1 || echo 0; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; W="$H/overnight-queue"; O="$T/origins"; mkdir -p "$W/repos" "$W/logs" "$O"
cp "$SH" "$W/ovn_filesize_retag.sh"; cp "$PY" "$W/ovn_filesize_retag.py"
cat > "$W/queue.sh" <<Q
#!/usr/bin/env bash
echo "\$*" >> "$W/queue.calls"
Q
chmod +x "$W/queue.sh"
G(){ git -c user.email=t@t -c user.name=t "$@"; }
# mkrepo name progress-content big-file-lines
mkrepo(){ local n="$1"; rm -rf "$O/$n.git" "$T/seed" "$W/repos/$n"
  git init -q --bare "$O/$n.git"; git clone -q "$O/$n.git" "$T/seed" 2>/dev/null
  ( cd "$T/seed" && G checkout -q -b overnight/feature && mkdir -p app && seq 1 "${3:-600}" | sed 's/^/x = /' > app/big.py && seq 1 20 > app/small.py \
    && printf '%b' "$2" > OVERNIGHT_PROGRESS.md && G add -A && G commit -q -m seed && G push -q origin overnight/feature )
  git clone -q -b overnight/feature "$O/$n.git" "$W/repos/$n" 2>/dev/null; rm -rf "$T/seed"; }
run(){ : > "$W/queue.calls"; ( cd "$W" && HOME="$H" bash ./ovn_filesize_retag.sh "$@" ) > "$T/out" 2>&1; echo $?; }
BIG='- [ ] [T2] app/big.py — rework\n- [ ] [T1] app/small.py — tiny\n- [ ] [T1] app/big.py — another\n'
cat > "$W/tasks.json" <<J
[{"repo":"/srv/repos/alpha","type":"aider_fix"},
 {"repo":"/srv/repos/beta","type":"aider_fix","enabled":false},
 {"repo":"/srv/repos/gamma","type":"train"},
 {"repo":"/srv/repos/delta","type":"aider_fix"},
 {"repo":"/srv/repos/alpha","type":"aider_fix"}]
J
mkrepo alpha "$BIG"; mkrepo beta "$BIG"; mkrepo gamma "$BIG"; mkrepo delta '- [ ] [T2] app/small.py — only small\n'
rc="$(run)"; out="$(cat "$T/out")"
ok "discovery run exits 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "alpha: 2 large-file items retagged and logged" "$(has "$out" 'alpha: retagged 2 large-file item(s)')"
ok "commit message on origin" "$(git -C "$O/alpha.git" log overnight/feature --format=%s -1 | grep -qF 'chore(queue): retag 2 large-file item(s) T1/T2->T3 (routes to staged pipeline)' && echo 1 || echo 0)"
ok "commit authored by shrike-fleet" "$([ "$(git -C "$O/alpha.git" log overnight/feature --format=%an -1)" = shrike-fleet ] && echo 1 || echo 0)"
pf="$(git -C "$O/alpha.git" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "origin progress: big-file T2 and T1 items became [T3] w/ annotation" "$(both "$(printf '%s\n' "$pf" | grep -q '^- \[ \] \[T3\] app/big.py — rework  <!-- retagged T2->T3: target file is 600 lines' && echo 1 || echo 0)" "$(printf '%s\n' "$pf" | grep -q '^- \[ \] \[T3\] app/big.py — another  <!-- retagged T1->T3' && echo 1 || echo 0)")"
ok "small-file item untouched" "$(printf '%s\n' "$pf" | grep -qxF -- '- [ ] [T1] app/small.py — tiny' && echo 1 || echo 0)"
ok "delta (only small-file item): 'nothing to retag', no commit" "$(both "$(has "$out" 'delta: nothing to retag')" "$([ "$(git -C "$O/delta.git" rev-list --count overnight/feature)" = 1 ] && echo 1 || echo 0)")"
ok "disabled repo beta skipped, untouched" "$(both "$(! grep -q 'beta:' "$T/out" && echo 1 || echo 0)" "$([ "$(git -C "$O/beta.git" rev-list --count overnight/feature)" = 1 ] && echo 1 || echo 0)")"
ok "non-aider_fix repo gamma skipped" "$(! grep -q 'gamma:' "$T/out" && echo 1 || echo 0)"
ok "duplicate tasks.json entry processed once" "$([ "$(grep -c 'alpha:' "$T/out")" = 1 ] && echo 1 || echo 0)"
ok "hold before / release after for each processed repo" "$(grep -qx 'hold alpha' "$W/queue.calls" && grep -qx 'release alpha' "$W/queue.calls" && [ "$(head -1 "$W/queue.calls")" = 'hold alpha' ] && [ "$(tail -1 "$W/queue.calls")" = 'release delta' ] && echo 1 || echo 0)"
ok "pass-complete line logged with timestamp" "$(printf '%s\n' "$out" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ovn_filesize_retag pass complete$' && echo 1 || echo 0)"

rc="$(run alpha)"; out="$(cat "$T/out")"
ok "explicit repo arg + idempotent rerun: nothing to retag" "$(has "$out" 'alpha: nothing to retag')"
ok "rerun adds no commit" "$([ "$(git -C "$O/alpha.git" rev-list --count overnight/feature)" = 2 ] && echo 1 || echo 0)"
ok "explicit arg bypasses tasks.json (only alpha logged)" "$(! grep -q 'delta:' "$T/out" && echo 1 || echo 0)"

# drift discarded by reset --hard
echo junk > "$W/repos/alpha/OVERNIGHT_PROGRESS.md"; run alpha >/dev/null
ok "local edits are hard-reset to origin (not pushed)" "$(git -C "$O/alpha.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q junk && echo 0 || echo 1)"

# no progress file
rm -f "$W/repos/alpha/OVERNIGHT_PROGRESS.md"; run alpha >/dev/null
ok "no progress file: skipped, no hold taken" "$(both "$(has "$(cat "$T/out")" 'alpha: no progress file, skipping')" "$([ ! -s "$W/queue.calls" ] && echo 1 || echo 0)")"

# sync failure
mkrepo eps "$BIG"; git -C "$O/eps.git" update-ref -d refs/heads/overnight/feature; run eps >/dev/null
ok "origin branch missing: 'git sync failed' and hold released" "$(both "$(has "$(cat "$T/out")" 'eps: git sync failed')" "$(grep -qx 'release eps' "$W/queue.calls" && echo 1 || echo 0)")"

# first push rejected, retry works
mkrepo zeta "$BIG"
printf '#!/bin/sh\n[ -f "%s/m" ] && exit 0\ntouch "%s/m"\nexit 1\n' "$T" "$T" > "$O/zeta.git/hooks/pre-receive"; chmod +x "$O/zeta.git/hooks/pre-receive"
run zeta >/dev/null
ok "first push rejected -> pull --rebase + retry succeeds" "$(both "$(has "$(cat "$T/out")" 'zeta: retagged 2 large-file item(s)')" "$(git -C "$O/zeta.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'retagged T2->T3' && echo 1 || echo 0)")"

# permanent push failure
mkrepo eta "$BIG"; printf '#!/bin/sh\nexit 1\n' > "$O/eta.git/hooks/pre-receive"; chmod +x "$O/eta.git/hooks/pre-receive"
run eta >/dev/null
ok "permanent push failure logged as FAILED" "$(has "$(cat "$T/out")" 'eta: retag push FAILED')"
ok "push failure still releases hold and finishes the pass" "$(both "$(grep -qx 'release eta' "$W/queue.calls" && echo 1 || echo 0)" "$(has "$(cat "$T/out")" 'pass complete')")"

# threshold boundary: exactly 500 lines is NOT large (default threshold 500), 501 is
mkrepo edge500 '- [ ] [T2] app/big.py — edge\n' 500; run edge500 >/dev/null
ok "500-line file not retagged (threshold is strictly greater)" "$(has "$(cat "$T/out")" 'edge500: nothing to retag')"
mkrepo edge501 '- [ ] [T2] app/big.py — edge\n' 501; run edge501 >/dev/null
ok "501-line file retagged" "$(has "$(cat "$T/out")" 'edge501: retagged 1 large-file item(s)')"

# empty / missing task list
echo '[]' > "$W/tasks.json"; rc="$(run)"
ok "empty task list: exit 0, only the completion line" "$(both "$([ "$rc" = 0 ] && echo 1 || echo 0)" "$([ "$(grep -c '' "$T/out")" = 1 ] && has "$(cat "$T/out")" 'pass complete')")"
rm -f "$W/tasks.json"; rc="$(run)"
ok "missing tasks.json tolerated" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
rc="$( cd "$T" && HOME="$T/nohome" bash "$SH" >/dev/null 2>&1; echo $? )"
ok "missing \$HOME/overnight-queue -> exit 1" "$([ "$rc" = 1 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
