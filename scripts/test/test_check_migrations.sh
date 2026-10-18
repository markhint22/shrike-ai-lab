#!/usr/bin/env bash
# Tests for scripts/check_migrations.py — the static alembic safety gate used by
# branch_hygiene.sh AND promote_to_prod.sh (the only thing standing between a broken
# migration chain and a crash-looping prod deploy). Had ZERO test coverage despite being
# exactly what caught the real gitlark incident this session: 4 fleet-authored migrations
# formed an orphaned side-chain (bare numeric revision ids that never linked to the real
# slug-id history), producing a duplicate revision id AND 3 heads. The gate correctly
# rejected it — this backfills coverage for that gate itself, not just documents the
# incident after the fact.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # fail-closed sandbox helpers (lint_unsafe_rm.py)
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
CM="${OVN_CHECK_MIGRATIONS:-$HOME/overnight-queue/scripts/check_migrations.py}"
[ -f "$CM" ] || { echo "  SKIP: $CM not found on this host"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){  if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }

mkvdir(){ mkdir -p "$1/alembic/versions"; }

# ---- 1. clean, single linear chain -> OK ----
d=$(safe_mktemp_dir) || exit 1; mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
cat > "$d/alembic/versions/002_add_users.py" <<'EOF'
revision = "002_add_users"
down_revision = "001_initial"
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "clean linear chain -> exit 0"                 "[ $rc -eq 0 ]"
ok  "clean linear chain -> reports OK"              "printf '%s' \"\$out\" | grep -q 'MIGRATION SAFETY: OK'"
safe_rm_rf "$d"

# ---- 2. duplicate revision id in two files (the exact gitlark shape) -> FAIL ----
d=$(safe_mktemp_dir) || exit 1; mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
cat > "$d/alembic/versions/013_add_plans.py" <<'EOF'
revision = "013"
down_revision = "001_initial"
EOF
cat > "$d/alembic/versions/013_create_plans_table.py" <<'EOF'
revision = "013"
down_revision = "001_initial"
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "duplicate revision id -> does NOT exit 0"      "[ $rc -eq 0 ]"
ok  "duplicate revision id -> flagged by name"      "printf '%s' \"\$out\" | grep -q \"revision '013' declared in 2 files\""
safe_rm_rf "$d"

# ---- 3. multiple heads (a disconnected side-chain) -> FAIL ----
d=$(safe_mktemp_dir) || exit 1; mkvdir "$d"
cat > "$d/alembic/versions/001_initial.py" <<'EOF'
revision = "001_initial"
down_revision = None
EOF
cat > "$d/alembic/versions/002_main_head.py" <<'EOF'
revision = "002_main_head"
down_revision = "001_initial"
EOF
cat > "$d/alembic/versions/orphan_head.py" <<'EOF'
revision = "orphan_head"
down_revision = None
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "multiple heads -> does NOT exit 0"             "[ $rc -eq 0 ]"
ok  "multiple heads -> flagged"                     "printf '%s' \"\$out\" | grep -q 'MULTIPLE HEADS'"
safe_rm_rf "$d"

# ---- 4. String FK pointing at a UUID target (the billwatch shape) -> FAIL ----
d=$(safe_mktemp_dir) || exit 1; mkvdir "$d"
cat > "$d/alembic/versions/001_users.py" <<'EOF'
from alembic import op
from sqlalchemy.dialects import postgresql
revision = "001_users"
down_revision = None
def upgrade():
    op.create_table(
        "users",
        op.Column("id", postgresql.UUID(as_uuid=True)),
    )
EOF
cat > "$d/alembic/versions/002_api_usage.py" <<'EOF'
from alembic import op
import sqlalchemy as sa
revision = "002_api_usage"
down_revision = "001_users"
def upgrade():
    op.create_table(
        "api_usage",
        op.Column("user_id", sa.String(36)),
        op.ForeignKeyConstraint(["user_id"], ["users.id"]),
    )
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "String FK to UUID target -> does NOT exit 0"   "[ $rc -eq 0 ]"
ok  "String FK to UUID target -> flagged"           "printf '%s' \"\$out\" | grep -q 'is String but target'"
safe_rm_rf "$d"

# ---- 4b. tuple down_revision (an Alembic MERGE migration) -> parents are NOT heads (2026-10-18 TAA) ----
# Regression: the regex read `down_revision = ('0007', '0379c2620417')` as '(' so a CORRECT merge
# showed its own parents as extra heads -> 'MULTIPLE HEADS' -> claude/feature -> develop blocked 10h.
d="$(safe_mktemp_dir)" || exit 1; mkvdir "$d"
cat > "$d/alembic/versions/0001_base.py" <<'EOF'
revision = "0001_base"
down_revision = None
EOF
cat > "$d/alembic/versions/0002_a.py" <<'EOF'
revision: str = "0002_a"
down_revision: Union[str, None] = "0001_base"
EOF
cat > "$d/alembic/versions/0003_b.py" <<'EOF'
revision = "0003_b"
down_revision = "0001_base"
EOF
cat > "$d/alembic/versions/0004_merge.py" <<'EOF'
revision = '0004'
down_revision = ('0002_a', '0003_b')
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "tuple-parent merge of two branches -> single head, exit 0"   "[ $rc -eq 0 ]"
# mutant: same tree minus the merge file -> the two real heads MUST still be flagged
rm "$d/alembic/versions/0004_merge.py"
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "two branches with NO merge -> still flagged (gate not weakened)" "[ $rc -eq 0 ]"
ok  "two branches with NO merge -> MULTIPLE HEADS names both"      "printf '%s' \"\$out\" | grep -q \"MULTIPLE HEADS \\['0002_a', '0003_b'\\]\""
# a merge that lists only ONE of the two heads leaves the other as a head
cat > "$d/alembic/versions/0004_merge.py" <<'EOF'
revision = '0004'
down_revision = ('0002_a',)
EOF
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "merge listing only one parent -> still flagged"              "[ $rc -eq 0 ]"
ok  "merge listing only one parent -> 0003_b reported as head"    "printf '%s' \"\$out\" | grep -q '0003_b'"
safe_rm_rf "$d"

# ---- 4c. applied-migration immutability (2026-10-18 TAA 3114b2a: baseline edited after it was applied) ----
d="$(safe_mktemp_dir)" || exit 1; mkvdir "$d"
( cd "$d" && git init -q && git config user.email t@t && git config user.name t
  printf 'revision = "0001_base"\ndown_revision = None\n' > alembic/versions/0001_base.py
  git add -A && git commit -q -m base ) >/dev/null 2>&1
B="$(git -C "$d" rev-parse HEAD)"
printf 'revision = "0001_base"\ndown_revision = None\n# edited after being applied\n' > "$d/alembic/versions/0001_base.py"
git -C "$d" commit -qam "edit applied baseline" >/dev/null 2>&1
out="$(OVN_MIG_BEFORE_SHA=$B python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "immutability shadow (default): edit of an existing migration is reported"        "printf '%s' \"\$out\" | grep -q 'IMMUTABILITY (shadow).*0001_base.py'"
ok  "immutability shadow (default): never fails the check (exit 0)"                   "[ $rc -eq 0 ]"
out="$(OVN_MIG_IMMUTABLE=enforce OVN_MIG_BEFORE_SHA=$B python3 "$CM" "$d" 2>&1)"; rc=$?
nok "immutability enforce: edit of an existing migration fails"                       "[ $rc -eq 0 ]"
out="$(OVN_MIG_IMMUTABLE=off OVN_MIG_BEFORE_SHA=$B python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "immutability off: silent and exit 0"                                             "[ $rc -eq 0 ] && ! printf '%s' \"\$out\" | grep -q IMMUTABILITY"
printf 'revision = "0002_new"\ndown_revision = "0001_base"\n' > "$d/alembic/versions/0002_new.py"
git -C "$d" checkout -q "$B" -- alembic/versions/0001_base.py; git -C "$d" add -A; git -C "$d" commit -qm "add new migration, restore baseline" >/dev/null 2>&1
out="$(OVN_MIG_IMMUTABLE=enforce OVN_MIG_BEFORE_SHA=$B python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "immutability enforce: ADDING a new migration (baseline unchanged vs BEFORE) passes"  "[ $rc -eq 0 ]"
safe_rm_rf "$d/.git"; safe_rm_rf "$d"   # safe_rm_rf refuses a git checkout root: drop the throwaway .git first

# ---- 5. no alembic dirs at all -> safe no-op OK (nothing to check) ----
d=$(safe_mktemp_dir) || exit 1
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "no alembic dirs -> exit 0 (nothing to check)"  "[ $rc -eq 0 ]"
safe_rm_rf "$d"

echo "check_migrations.py: $P passed, $F failed"
[ "$F" -eq 0 ]
