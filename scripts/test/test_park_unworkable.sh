#!/usr/bin/env bash
# ovn_park_unworkable.py: hard-banned and context-overflowing targets are parked; normal/delete items untouched.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "ok - $1"; }; bad(){ echo "FAIL - $1"; fail=1; }
mkdir -p "$T/repo/scripts"; printf 'scripts/banned.gd\n' > "$T/repo/.queue-hard-banned-files"
echo x > "$T/repo/scripts/banned.gd"; echo x > "$T/repo/scripts/small.gd"
python3 -c "open('$T/repo/scripts/huge.gd','w').write('a'*200000)"; echo x > "$T/repo/scripts/old.py"
cat > "$T/P.md" <<'Q'
- [ ] [T2] scripts/banned.gd — add a thing. VERIFY: `true`
- [ ] [T2] scripts/huge.gd — add a helper. VERIFY: `true`
- [ ] [T2] scripts/small.gd — add a helper. VERIFY: `true`
- [ ] [T1] scripts/huge.gd — Delete the file entirely. VERIFY: `true`
- [ ] [AUTO-SKIP] [T2] scripts/huge.gd — already parked
Q
out=$(python3 ovn_park_unworkable.py "$T/P.md" "$T/repo")
[ "$out" = "PARKED=2" ] && ok "parks banned + huge" || bad "got $out"
grep -q '^- \[ \] \[CLAUDE\] \[unworkable: hard-banned' "$T/P.md" && ok "banned tagged" || bad "banned tag"
grep -q '^- \[ \] \[CLAUDE\] \[unworkable: scripts/huge.gd is' "$T/P.md" && ok "huge tagged" || bad "huge tag"
grep -q '^- \[ \] \[T2\] scripts/small.gd' "$T/P.md" && ok "small untouched" || bad "small touched"
grep -q '^- \[ \] \[T1\] scripts/huge.gd — Delete' "$T/P.md" && ok "delete item untouched" || bad "delete touched"
[ "$(python3 ovn_park_unworkable.py "$T/P.md" "$T/repo")" = "PARKED=0" ] && ok "idempotent" || bad "not idempotent"
# 2026-10-02: FILES: clause - every listed file is added to the aider chat, so a huge/banned file there parks the item even when the first path is small
cat > "$T/P2.md" <<'Q'
- [ ] [T3] scripts/small.gd — add a test that checks X. FILES: scripts/huge.gd, scripts/small.gd
- [ ] [T3] scripts/small.gd — another. FILES: scripts/banned.gd
- [ ] [T3] scripts/small.gd — fine. FILES: scripts/small.gd, scripts/old.py
- [ ] [T3] scripts/small.gd — no FILES clause, small first path
Q
out=$(python3 ovn_park_unworkable.py "$T/P2.md" "$T/repo")
[ "$out" = "PARKED=2" ] && ok "FILES: clause parks huge + banned" || bad "FILES clause got $out"
grep -q '^- \[ \] \[CLAUDE\] \[unworkable: scripts/huge.gd is.*FILES: scripts/huge.gd' "$T/P2.md" && ok "FILES huge tagged" || bad "FILES huge tag"
grep -q '^- \[ \] \[T3\] scripts/small.gd — fine' "$T/P2.md" && ok "FILES small untouched" || bad "FILES small touched"
grep -q '^- \[ \] \[T3\] scripts/small.gd — no FILES' "$T/P2.md" && ok "no-FILES item untouched" || bad "no-FILES touched"
exit $fail
