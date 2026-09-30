#!/usr/bin/env bash
# ovn_credit_already_satisfied.sh TARGET-PATH GATE (2026-09-30). Items with no runnable VERIFY clause used to credit on
# the model's say-so alone (5-21% wrong in the 2026-09-24 audit). The item's own leading path must make sense:
# create/modify target must EXIST, delete target must be GONE. Needs GNU sed (-i) - run on the box.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_credit_already_satisfied.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/ovn_credit_already_satisfied.sh"
[ -n "${OVN_CREDIT_SCRIPT:-}" ] && SCRIPT="$OVN_CREDIT_SCRIPT"
[ -f "$SCRIPT" ] || { echo "  SKIP: script not found"; exit 0; }
sed --version >/dev/null 2>&1 || { echo "  SKIP: needs GNU sed"; exit 0; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; cd "$tmp"
mkdir -p src; touch src/exists.py src/stale_to_delete.py
mk(){ cat > OVERNIGHT_PROGRESS.md <<'P'
## Next Steps
- [ ] [T2] src/exists.py — Add a thing with no verify clause. (cat:python)
- [ ] [T2] src/missing.py — Add a thing with no verify clause. (cat:python)
- [ ] [T2] src/stale_to_delete.py — Delete this dead module, it has no callers. (cat:python)
- [ ] [T2] src/already_gone.py — Remove this dead module, it has no callers. (cat:python)
- [ ] [T2] Tighten the retry docs in README wording with no path token at all. (cat:docs)
- [ ] [T2] src/verified_missing.py — Add a thing WITH a passing verify clause. VERIFY: `true`. (cat:python)
P
cat > aider.log <<'L'
exists.py
Already done, no changes needed.
missing.py
Already done, no changes needed.
stale_to_delete.py
Already done, no changes needed.
already_gone.py
Already done, no changes needed.
verified_missing.py
Already done, no changes needed.
L
}
run(){ OVN_VERIFY_SHADOW_LOG="$tmp/sh.log" "$@" bash "$SCRIPT" aider.log OVERNIGHT_PROGRESS.md 2>&1; }
mk; out="$(run env)"
chk(){ grep -q "$1" OVERNIGHT_PROGRESS.md && ok "$2" || fail "$2"; }
chk '^- \[x\].*src/exists.py' "create item whose target EXISTS credits"
chk '^- \[ \] .*src/missing.py' "create item whose target is MISSING is refused (left open)"
chk '^- \[ \] .*src/stale_to_delete.py' "delete item whose target STILL EXISTS is refused"
chk '^- \[x\].*src/already_gone.py' "delete item whose target is gone credits"
chk '^- \[x\].*src/verified_missing.py' "item WITH a passing VERIFY clause is not subject to the path gate"
echo "$out" | grep -q 'REFUSED.*missing.py.*MISSING' && ok "refusal names the reason (MISSING)" || fail "no MISSING refusal line: $out"
echo "$out" | grep -q 'REFUSED.*stale_to_delete.py.*STILL_EXISTS' && ok "refusal names the reason (STILL_EXISTS)" || fail "no STILL_EXISTS refusal line"
grep -q 'path_gate=MISSING' sh.log && ok "path gate result is logged to the shadow log" || fail "shadow log missing path_gate record"
mk; out="$(run env OVN_PATH_GATE=shadow)"
chk '^- \[x\].*src/missing.py' "OVN_PATH_GATE=shadow: nothing is refused (rollback path)"
mk; out="$(run env OVN_PATH_GATE=off)"
chk '^- \[x\].*src/stale_to_delete.py' "OVN_PATH_GATE=off: pre-gate behavior"
[ "$rc" = 0 ] && echo "  credit path gate: ALL PASS" || echo "  credit path gate: FAILURES"; exit $rc
