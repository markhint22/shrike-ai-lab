#!/usr/bin/env bash
# Tests for scripts/check_applied_migration_immutable.py (2026-10-18). Includes the mutant: a checker that ignores edits must FAIL these assertions.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
CK="${OVN_CHECK_IMMUTABLE:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/check_applied_migration_immutable.py}"
[ -f "$CK" ] || { echo "  SKIP: $CK not found"; exit 0; }
P=0; F=0
chk(){ local want="$1" name="$2"; shift 2; python3 -I "$CK" "$@" >"$T/out" 2>&1; local rc=$?; if [ "$rc" = "$want" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $name (rc=$rc want=$want)"; cat "$T/out"; fi; }
T="$(safe_mktemp_dir immut)" || exit 1
R="$T/repo"; mkdir -p "$R/backend/alembic/versions"
g(){ git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
g init -q -b prod
printf 'revision = "0001"\ndown_revision = None\n' > "$R/backend/alembic/versions/0001_base.py"
g add -A; g commit -qm base
BASE="$(g rev-parse HEAD)"; g tag prod "$BASE"
# 1. new migration file only -> clean
printf 'revision = "0002"\ndown_revision = "0001"\n' > "$R/backend/alembic/versions/0002_new.py"
g add -A; g commit -qm new; A1="$(g rev-parse HEAD)"
chk 0 "adding a new migration is clean" "$R" "$BASE" "$A1" prod
# 2. editing the applied baseline -> flagged
printf 'revision = "0001"\ndown_revision = None\n# col added\n' > "$R/backend/alembic/versions/0001_base.py"
g add -A; g commit -qm edit; A2="$(g rev-parse HEAD)"
chk 1 "editing a migration present on main is flagged" "$R" "$A1" "$A2" prod
grep -q "0001_base.py" "$T/out" && P=$((P+1)) || { F=$((F+1)); echo "  FAIL: message names the file"; }
# 3. editing a migration NOT on main (still unapplied) -> clean
printf 'revision = "0002"\ndown_revision = "0001"\n# fixed down_revision\n' > "$R/backend/alembic/versions/0002_new.py"
g add -A; g commit -qm fix2; A3="$(g rev-parse HEAD)"
chk 0 "editing an unapplied migration is clean" "$R" "$A2" "$A3" prod
# 4. deleting an applied migration -> flagged
g rm -q "backend/alembic/versions/0001_base.py"; g commit -qm del; A4="$(g rev-parse HEAD)"
chk 1 "deleting a migration present on main is flagged" "$R" "$A3" "$A4" prod
# 5. no prod ref -> silent
chk 0 "missing prod ref is silent" "$R" "$A3" "$A4" nosuchref
safe_rm_rf "$T"
echo "  passed=$P failed=$F"; [ "$F" = 0 ]
