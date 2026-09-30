#!/usr/bin/env bash
# Wave-3: ovn_alembic_autogen.sh branch where a migration IS generated but the repo's static check_migrations.py then
# rejects it -> the hook discards everything (reset --hard + clean) and leaves HEAD alone. Uses a private scripts dir
# holding the REAL hook + driver and a stub check_migrations.py that fails. Fixture builder reused from
# test_alembic_autogen.sh (mkrepo only). SKIPs when no python with alembic+sqlalchemy exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$(cd "$HERE/.." && pwd)"
PYX="${OVN_TEST_PY:-$HOME/overnight-queue/repos/test-automation-agent/backend/.venv/bin/python}"
"$PYX" -c 'import alembic, sqlalchemy' 2>/dev/null || { echo "SKIP: no python with alembic+sqlalchemy ($PYX)"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
EXT="$HERE/test_alembic_autogen.sh"
eval "$(sed -n '/^mkrepo() {/,/^}/p; /^commit_models() /p; /^nfiles() /p' "$EXT")"
mkdir -p "$T/priv"
cp "$SCRIPTS/ovn_alembic_autogen.sh" "$SCRIPTS/ovn_alembic_autogen.py" "$T/priv/"
printf 'import sys\nsys.exit(1)\n' > "$T/priv/check_migrations.py"

R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat(models): add item note"; H=$(git rev-parse HEAD)
out="$(OVN_ALEMBIC_AUTOGEN_REPOS=fixture-app bash "$T/priv/ovn_alembic_autogen.sh" "$PWD" "$B" "$H" 2>&1)"
ok "post-generate static check failure is reported" "echo \"$out\" | grep -q 'post-generate check_migrations.py failed - discarding'"
ok "HEAD is unchanged (nothing committed)" "[ \"\$(git rev-parse HEAD)\" = '$H' ]"
ok "no migration file left behind" "[ \"\$(nfiles)\" = 1 ]"
ok "working tree clean after the discard" "git diff --quiet HEAD -- && [ -z \"\$(git status --porcelain)\" ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
