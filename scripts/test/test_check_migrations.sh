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
CM="${OVN_CHECK_MIGRATIONS:-$HOME/overnight-queue/scripts/check_migrations.py}"
[ -f "$CM" ] || { echo "  SKIP: $CM not found on this host"; exit 0; }
P=0; F=0
ok(){  if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }

mkvdir(){ mkdir -p "$1/alembic/versions"; }

# ---- 1. clean, single linear chain -> OK ----
d=$(mktemp -d); mkvdir "$d"
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
rm -rf "$d"

# ---- 2. duplicate revision id in two files (the exact gitlark shape) -> FAIL ----
d=$(mktemp -d); mkvdir "$d"
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
rm -rf "$d"

# ---- 3. multiple heads (a disconnected side-chain) -> FAIL ----
d=$(mktemp -d); mkvdir "$d"
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
rm -rf "$d"

# ---- 4. String FK pointing at a UUID target (the billwatch shape) -> FAIL ----
d=$(mktemp -d); mkvdir "$d"
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
rm -rf "$d"

# ---- 5. no alembic dirs at all -> safe no-op OK (nothing to check) ----
d=$(mktemp -d)
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
ok  "no alembic dirs -> exit 0 (nothing to check)"  "[ $rc -eq 0 ]"
rm -rf "$d"

echo "check_migrations.py: $P passed, $F failed"
[ "$F" -eq 0 ]
