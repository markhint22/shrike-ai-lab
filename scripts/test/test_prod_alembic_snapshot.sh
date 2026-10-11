#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_prod_alembic_snapshot.py (qa/prod_alembic_snapshot.py: prod /health db_revision -> state/prod_alembic/<repo>.json).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_prod_alembic_snapshot.py"
rc=$?
echo "test_prod_alembic_snapshot.py rc=$rc"
exit $rc
