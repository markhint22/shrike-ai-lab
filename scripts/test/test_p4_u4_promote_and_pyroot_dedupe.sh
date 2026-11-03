#!/usr/bin/env bash
# 2026-11-02 (P4 / outcomes F7), two fixes:
#  1. verify-shape lint U4 (`python -c 'from backend.app... import x'` where backend/ is the package root, the real gitlark clause on item 1:3682350596) is promotable at item
#     creation with OVN_VERIFY_U4=enforce (rewritten to `cd backend && from app...`); DEFAULT stays shadow (item untouched) but the log row now carries `u4_would` = the report.
#  2. the py-root-retry audit row (alerts.log) is written once per (repo, run, item) instead of once per re-verify pass (gitlark: two rows 3.5 min apart). The retry stays ON.
# Mutation controls: OVN_VERIFY_U4 unset => no rewrite (old behaviour); OVN_PYROOT_AUDIT_DEDUPE=off => a row per adoption (old behaviour).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; S="$HERE/.."
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 PYTHONDONTWRITEBYTECODE=1
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
PY="$(command -v python3.12 || command -v python3)"
LINT="$S/ovn_verify_shape_lint.py"
T="$tmp/tree"; mkdir -p "$T/backend/app/core"
printf 'from app.database import Base\n_enabled = True\n' > "$T/backend/app/core/error_reporting.py"
printf 'Base = object\n' > "$T/backend/app/database.py"
LINE='- [ ] [T2] backend/app/core/error_reporting.py — drop the module flag. VERIFY: `python -c "from backend.app.core import error_reporting; print(error_reporting._enabled)"`'
run_filter(){ # env... ; stdout = kept line
  printf '%s\n' "$LINE" | env OVN_VERIFY_SHAPE_LOG="$tmp/shape.log" OVN_VERIFY_ALERTS_LOG="$tmp/al.log" "$@" "$PY" "$LINT" filter --tree "$T" --repo gitlark --dropped "$tmp/dropped.md"
}
: > "$tmp/shape.log"
out="$(run_filter OVN_VERIFY_LINT=shadow)"
ok "U1 default (shadow): the item line is untouched" "[ \"\$out\" = '$LINE' ]"
ok "U1 the log row has the u4_would report (rewritten:cd backend && ...)" "grep -q '\"u4_would\": \"rewritten:cd backend && ' '$tmp/shape.log' || grep -q 'u4_would.*rewritten:cd backend' '$tmp/shape.log'"
ok "U1 the report says what the clause becomes (no backend.app prefix)" "grep -o 'u4_would[^}]*' '$tmp/shape.log' | grep -q 'from app.core import'"
: > "$tmp/shape.log"
out="$(run_filter OVN_VERIFY_LINT=shadow OVN_VERIFY_U4=enforce)"
ok "U2 OVN_VERIFY_U4=enforce: rewritten at creation to cd backend && from app..." "case \"\$out\" in *'cd backend && python -c \"from app.core import error_reporting'*) true;; *) false;; esac"
ok "U2 the rewritten clause no longer carries backend.app" "! printf '%s' \"\$out\" | grep -q 'backend\\.app'"
ok "U2 the rewritten clause really imports from backend/ (runs green)" "( cd '$T/backend' && '$PY' -c 'import sys; sys.path.insert(0, \".\"); from app.core import error_reporting' ) "
# a mixed-finding line stays flagged only (U4 enforce must not enforce OTHER shadow-gated findings)
LINE2='- [ ] [T2] backend/app/core/error_reporting.py — x. VERIFY: `python -c "from backend.app.core import error_reporting" | wc -l`'
out2="$(printf '%s\n' "$LINE2" | env OVN_VERIFY_SHAPE_LOG="$tmp/shape2.log" OVN_VERIFY_ALERTS_LOG="$tmp/al2.log" OVN_VERIFY_U4=enforce OVN_VERIFY_LINT=shadow "$PY" "$LINT" filter --tree "$T" --repo gitlark)"
ok "U3 U4 enforce does not rewrite an item that has other (non-U4) findings while OVN_VERIFY_LINT=shadow" "[ \"\$out2\" = '$LINE2' ]"
# control: a clean clause is never touched
LINE3='- [ ] [T2] backend/app/core/error_reporting.py — x. VERIFY: `cd backend && python -c "from app.core import error_reporting"`'
out3="$(printf '%s\n' "$LINE3" | env OVN_VERIFY_SHAPE_LOG="$tmp/s3.log" OVN_VERIFY_ALERTS_LOG="$tmp/a3.log" OVN_VERIFY_U4=enforce "$PY" "$LINT" filter --tree "$T" --repo gitlark)"
ok "U4 control: an already-correct clause is untouched under U4 enforce" "[ \"\$out3\" = '$LINE3' ]"
# full enforce mode: with OVN_VERIFY_U4 unset the P5 gate still keeps U4 flag-only (the old behaviour, mutation proof for U2)
out4="$(run_filter OVN_VERIFY_LINT=enforce)"
ok "U5 MUTANT/old: OVN_VERIFY_LINT=enforce without OVN_VERIFY_U4 leaves U4 un-rewritten" "[ \"\$out4\" = '$LINE' ]"

# ---------------- py-root-retry audit dedupe ----------------
export OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log" OVN_VERIFY_ALERTS_LOG="$tmp/alerts.log"
SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"
# shellcheck disable=SC1090
. "$S/lib_verify_clause.sh"
PROG="$tmp/prog.md"; printf '%s\n%s\n' "- [ ] item one" "- [ ] item two" > "$PROG"
_REPO_LABEL=gitlark; unset RUNID OVN_PYROOT_AUDIT_DEDUPE
: > "$OVN_VERIFY_ALERTS_LOG"; rm -f "$tmp/py_root_retry_seen.log"
for _ in 1 2 3; do _verify_py_root_audit 1 /r/backend 'python -c "x"' "$PROG" 1; done
ok "D1 three adoptions of the same item in one run => ONE audit row" "[ \"\$(grep -c 'py-root-retry' '$OVN_VERIFY_ALERTS_LOG')\" = 1 ]"
_verify_py_root_audit 2 /r/backend 'python -c "y"' "$PROG" 1
ok "D2 a different item still gets its own row" "[ \"\$(grep -c 'py-root-retry' '$OVN_VERIFY_ALERTS_LOG')\" = 2 ]"
RUNID=20261102-run2 _verify_py_root_audit 1 /r/backend 'python -c "x"' "$PROG" 1
ok "D3 the same item in a NEW run is audited again" "[ \"\$(grep -c 'py-root-retry' '$OVN_VERIFY_ALERTS_LOG')\" = 3 ]"
: > "$OVN_VERIFY_ALERTS_LOG"
for _ in 1 2 3; do OVN_PYROOT_AUDIT_DEDUPE=off _verify_py_root_audit 1 /r/backend 'python -c "x"' "$PROG" 1; done
ok "D4 MUTANT (OVN_PYROOT_AUDIT_DEDUPE=off): the old row-per-adoption returns (3 rows)" "[ \"\$(grep -c 'py-root-retry' '$OVN_VERIFY_ALERTS_LOG')\" = 3 ]"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
