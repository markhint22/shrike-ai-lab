#!/usr/bin/env bash
# Extra coverage for ovn_verify_direction_check.sh: check 1 (always-true), check 2 (delete direction),
# check 3 variants (assert-is-None, bare import), lib_item_select hash path, dedup, skip filters.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ -d "$ROOT/scripts" ] && [ -f "$ROOT/scripts/lib_item_select.sh" ] || ROOT="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
SCRIPT=""
for c in "$ROOT/scripts/ovn_verify_direction_check.sh" "$ROOT/ovn_verify_direction_check.sh"; do [ -f "$c" ] && { SCRIPT="$c"; break; }; done
LIB="$ROOT/scripts/lib_item_select.sh"
[ -n "$SCRIPT" ] && [ -f "$LIB" ] || { echo "SKIP: script/lib not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q="$tmp/overnight-queue"
mkdir -p "$Q/backlog" "$Q/state" "$Q/logs" "$Q/scripts" "$Q/repos/r2"
cp "$SCRIPT" "$Q/ovn_verify_direction_check.sh"
cp "$LIB" "$Q/scripts/lib_item_select.sh"
run(){ ( HOME="$tmp" NTFY_TOPIC="" bash "$Q/ovn_verify_direction_check.sh" "$@" >/dev/null 2>&1 ); }
LOGF="$Q/logs/ovn_verify_direction_check.log"
SEEN="$Q/state/verify_direction_seen.txt"

cat > "$Q/backlog/r1.md" <<'B'
# Backlog
- [ ] [T2] a.py - add thing. VERIFY: `grep -q foo a.py && echo OK || echo NO`. (cat:misc)
- [ ] [T2] b.py - delete the legacy helper. VERIFY: `grep -q legacy b.py`. (cat:misc)
- [ ] [T2] c.py - remove old module. VERIFY: `! grep -q legacy c.py`. (cat:misc)
- [ ] [T2] d.py - remove orphaned file. VERIFY: `pytest tests/test_d.py`. (cat:misc)
- [ ] [T2] e.py - add model. VERIFY: `python -c "from app.e import E; assert E is not None"`. (cat:schema)
- [ ] [T2] f.py - add model. VERIFY: `python -c "import app.f"`. (cat:schema)
- [ ] [T2] g.py - add model. VERIFY: `python -c "import app.g; assert app.g.X == 1"`. (cat:schema)
- [ ] [T2] h.py - delete dead code. VERIFY: `test -f h.py || echo gone` HUMAN-ONLY
- [x] [T2] i.py - delete thing. VERIFY: `grep -q x i.py || echo NO`
- [ ] [T2] j.py - no verify here at all
- [ ] [T2] l.py - add model. VERIFY: `python -c "from app.l import L; assert hasattr(L, 'x')"`. (cat:schema)
B
cat > "$Q/repos/r2/OVERNIGHT_PROGRESS.md" <<'B'
- [ ] [T2] k.py - add x. VERIFY: `ls k.py || true`. (cat:misc)
B

run "r1 r2"
L="$(cat "$LOGF")"
ok "always-true flagged (a.py)" "printf '%s' \"\$L\" | grep -q 'always-true.*r1.md: - \[ \] \[T2\] a.py'"
ok "always-true from repos/<r>/OVERNIGHT_PROGRESS.md (k.py)" "printf '%s' \"\$L\" | grep -q 'always-true.*k.py'"
ok "direction-review flagged for b.py" "printf '%s' \"\$L\" | grep -q 'direction-review.*b.py'"
ok "negated delete c.py not flagged" "! printf '%s' \"\$L\" | grep -q 'direction-review.*c.py'"
ok "pytest-delegated delete d.py not flagged" "! printf '%s' \"\$L\" | grep -q 'direction-review.*d.py'"
ok "HUMAN-ONLY h.py skipped" "! printf '%s' \"\$L\" | grep -q 'h.py'"
ok "checked line i.py skipped" "! printf '%s' \"\$L\" | grep -q 'i.py'"
ok "assert-is-None e.py existence-only" "printf '%s' \"\$L\" | grep -q 'existence-only.*e.py'"
ok "bare import f.py existence-only" "printf '%s' \"\$L\" | grep -q 'existence-only.*f.py'"
ok "import+assert g.py not flagged" "! printf '%s' \"\$L\" | grep -q 'existence-only.*g.py'"
ok "hasattr l.py existence-only" "printf '%s' \"\$L\" | grep -q 'existence-only.*l.py'"
ok "summary line counts 2 always-true, 1 direction, 3 existence" "printf '%s' \"\$L\" | grep -q '=== 2 new always-true + 1 new direction-review + 3 new existence-only'"
n1="$(wc -l < "$SEEN")"
ok "seen file has 6 entries" "[ '$n1' -eq 6 ]"

run "r1 r2"
L2="$(cat "$LOGF")"
ok "second run is clean (dedup)" "printf '%s' \"\$L2\" | tail -1 | grep -q 'clean run'"
ok "seen file unchanged" "[ \"\$(wc -l < '$SEEN')\" -eq 6 ]"

# no-lib fallback + default REPOS list + missing backlog files
rm -f "$Q/scripts/lib_item_select.sh" "$SEEN"
( cd "$tmp" && HOME="$tmp" NTFY_TOPIC="" bash "$Q/ovn_verify_direction_check.sh" >/dev/null 2>&1 )
ok "default repo list with no files = clean" "tail -1 '$LOGF' | grep -q 'clean run'"
run r1
ok "md5 fallback path still hashes and flags" "tail -3 '$LOGF' | grep -q 'new always-true'"

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
