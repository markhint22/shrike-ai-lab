#!/usr/bin/env bash
# test_stub_guard_newdir_n2.sh - package qa (2026-10-13, finding iptv-night F4). The pre-scout "stub new source file" step wrote whatever path the item named; three items
# named `iptv-backend/iptv-backend/tests/...` (made so by queue_refill.relocate_new_tests before dce6b5d9) and the step created 3 stray test files nothing collected, and
# `app/routers/outers/` (a typo of routers/) got a junk file. ovn_stub_guard.py pick now judges the first NEW directory of the path: a name that repeats its parent's (exactly
# or within edit distance 2) while the collapsed path exists, or that is within distance 2 of an existing sibling directory. SHADOW by default (stub anyway + one line in
# logs/stub_guard.log); OVN_STUB_NEWDIR_GUARD=enforce refuses (SKIP|new-dir-...); =off skips. The stub step itself resolves paths against the repo root correctly (verified).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${OVN_STUB_GUARD:-$HERE/../ovn_stub_guard.py}"
[ -f "$G" ] || { echo "  FAIL: $G not found"; exit 1; }
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1 (got [$2] want [$3])"; fi; }
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
LOG="$W/stub_guard.log"; export OVN_STUB_GUARD_LOG="$LOG"
unset OVN_STUB_NEWDIR_GUARD
pick(){ printf '%s' "$2" | timeout 60 python3 "$G" pick "$1" | tr '\t' '|'; }
R="$W/repo"; mkdir -p "$R" && cd "$R" || exit 1
git init -q -b main .
mkdir -p iptv-backend/app/routers iptv-backend/app/services iptv-backend/app/v1 iptv-backend/tests scripts/battle web/src/api
for f in iptv-backend/app/routers/billing.py iptv-backend/app/services/parental.py iptv-backend/app/v1/a.py iptv-backend/tests/test_a.py scripts/battle/damage.gd web/src/api/client.ts; do echo x > "$f"; done
git add -A && git commit -q -m base

DOUBLE='[T2] iptv-backend/iptv-backend/tests/test_parental_pure.py - NEW test file'
OUTERS='[T1] iptv-backend/app/routers/outers/subscription.py - Create'
TYPO='[T1] iptv-backend/app/servces/x.py - Create'
# ---- default = SHADOW: the stub is still picked, the would-be refusal is only logged
eq "SHADOW default: the doubled iptv-backend/iptv-backend/tests path is still PICKed (no behaviour change)" "$(pick "$R" "$DOUBLE")" "PICK|iptv-backend/iptv-backend/tests/test_parental_pure.py"
eq "SHADOW default: the outers/ typo path is still PICKed" "$(pick "$R" "$OUTERS")" "PICK|iptv-backend/app/routers/outers/subscription.py"
eq "SHADOW: one log line per would-be refusal (2 so far)" "$(grep -c 'SHADOW new-dir-lookalike' "$LOG" 2>/dev/null || true)" "2"
eq "SHADOW log names the existing directory" "$(grep -c 'doubled:iptv-backend/tests' "$LOG" 2>/dev/null || true)" "1"
# ---- enforce
export OVN_STUB_NEWDIR_GUARD=enforce
eq "ENFORCE REPRO (iptv 6cdf9c68): doubled iptv-backend/iptv-backend/tests refused" "$(pick "$R" "$DOUBLE")" "SKIP|new-dir-doubled:iptv-backend/tests|iptv-backend/iptv-backend/tests/test_parental_pure.py"
eq "ENFORCE REPRO (iptv 64a01ac4): routers/outers refused" "$(pick "$R" "$OUTERS")" "SKIP|new-dir-doubled:iptv-backend/app/routers|iptv-backend/app/routers/outers/subscription.py"
eq "ENFORCE: sibling typo servces/ ~ services/ refused" "$(pick "$R" "$TYPO")" "SKIP|new-dir-lookalike:iptv-backend/app/services|iptv-backend/app/servces/x.py"
eq "ENFORCE: exact repeat (scripts/scripts/x.gd, scripts/ exists at the root) is refused" "$(pick "$R" '[T1] scripts/scripts/x.gd - Create')" "SKIP|new-dir-doubled:scripts|scripts/scripts/x.gd"
# BENIGN
eq "BENIGN: an existing directory is stubbed" "$(pick "$R" '[T1] iptv-backend/tests/test_new.py - Create')" "PICK|iptv-backend/tests/test_new.py"
eq "BENIGN: a genuinely new feature directory is stubbed" "$(pick "$R" '[T1] iptv-backend/app/routers/payments/x.py - Create')" "PICK|iptv-backend/app/routers/payments/x.py"
eq "BENIGN: a new top-level directory is stubbed" "$(pick "$R" '[T1] scripts/mission/mission_directive.gd - Create')" "PICK|scripts/mission/mission_directive.gd"
eq "BENIGN: v2/ next to v1/ (digits only) is stubbed" "$(pick "$R" '[T1] iptv-backend/app/v2/a.py - Create')" "PICK|iptv-backend/app/v2/a.py"
eq "BENIGN: a short name (api/) is never judged" "$(pick "$R" '[T1] iptv-backend/app/api/a.py - Create')" "PICK|iptv-backend/app/api/a.py"
eq "BENIGN: ./-prefixed existing path" "$(pick "$R" '[T1] ./scripts/battle/new_one.gd - Create')" "PICK|./scripts/battle/new_one.gd"
# ---- kill switch + partial deploy
export OVN_STUB_NEWDIR_GUARD=off; : > "$LOG"
eq "OFF: the doubled path is PICKed and nothing is logged" "$(pick "$R" "$DOUBLE")|$(wc -c < "$LOG" | tr -d ' ')" "PICK|iptv-backend/iptv-backend/tests/test_parental_pure.py|0"
export OVN_STUB_NEWDIR_GUARD=enforce
mkdir -p "$W/tree/scripts"; cp "$G" "$W/tree/scripts/ovn_stub_guard.py"     # no qa/ag_n2.py next to it (partial deploy)
eq "PARTIAL DEPLOY: without qa/ag_n2.py the guard is skipped even in enforce (fail-open)" "$(printf '%s' "$DOUBLE" | python3 "$W/tree/scripts/ovn_stub_guard.py" pick "$R" | tr '\t' '|')" "PICK|iptv-backend/iptv-backend/tests/test_parental_pure.py"
echo "stub guard newdir n2: $P passed, $F failed"; [ "$F" = 0 ]
