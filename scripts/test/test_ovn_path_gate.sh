#!/usr/bin/env bash
# ovn_path_gate.py: the shared "does this item's own target path make sense for an already-done credit" check.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../ovn_path_gate.py"; [ -f "$G" ] || G="$HERE/ovn_path_gate.py"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; cd "$T"; mkdir -p src; touch src/here.py src/stale.py
cat > P.md <<'P'
## Next Steps
- [ ] [T2] src/here.py — Add a thing.
- [ ] [T2] src/gone.py — Add a thing.
- [ ] [T2] src/stale.py — Delete this dead module.
- [ ] [T2] src/already_deleted.py — Remove this dead module.
- [x] (already-satisfied in code, implement-verified) [T1] `src/here.py`: — Add a thing.
- [ ] [T2] Tighten some wording with no path at all.
- [ ] [T2] docs/README.md — Add a note.
- [ ] [T2] src/*.py — bulk edit with a glob.
- [ ] [T2] https://example.com/x.py — not a repo path.
P
g(){ python3 "$G" P.md "$1" "$T"; }
ok "create item, target exists -> OK" "$([ "$(g 2)" = "OK src/here.py" ] && echo 1 || echo 0)"
ok "create item, target missing -> MISSING" "$([ "$(g 3)" = "MISSING src/gone.py" ] && echo 1 || echo 0)"
ok "delete item, target still exists -> STILL_EXISTS" "$([ "$(g 4)" = "STILL_EXISTS src/stale.py" ] && echo 1 || echo 0)"
ok "delete item, target gone -> OK" "$([ "$(g 5)" = "OK src/already_deleted.py" ] && echo 1 || echo 0)"
ok "already-credited line with a credit label and backticked path:line is parsed" "$([ "$(g 6)" = "OK src/here.py" ] && echo 1 || echo 0)"
ok "no path token -> NA" "$([ "$(g 7)" = "NA" ] && echo 1 || echo 0)"
ok "non-code file (.md) -> NA" "$([ "$(g 8)" = "NA" ] && echo 1 || echo 0)"
ok "glob target -> NA" "$([ "$(g 9)" = "NA" ] && echo 1 || echo 0)"
ok "url target -> NA" "$([ "$(g 10)" = "NA" ] && echo 1 || echo 0)"
ok "line number out of range -> NA (never crashes)" "$([ "$(g 99)" = "NA" ] && echo 1 || echo 0)"
ok "missing progress file -> NA" "$([ "$(python3 "$G" /nonexistent 1 "$T")" = "NA" ] && echo 1 || echo 0)"
ok "no args -> NA" "$([ "$(python3 "$G")" = "NA" ] && echo 1 || echo 0)"
ok "repo dir defaults to the progress file's directory" "$([ "$(python3 "$G" "$T/P.md" 2)" = "OK src/here.py" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
