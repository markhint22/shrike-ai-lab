#!/usr/bin/env bash
# Gate S6 (qa/gate_migrations.py + qa/prodshape.py): unit tests everywhere; real-postgres integration scenarios where docker works.
# Runs test_qa_migrations.py under python3.12 when present (the box's gate interpreter; its default python3 is 3.14) and ALSO under
# the default python3 when QA_TEST_BOTH=1 (the Mac interpreter). The integration part SKIPs loudly (exit 0) if the docker daemon or a
# venv with fastapi/sqlalchemy/psycopg2/alembic is missing - on a machine without docker the python tests still assert the
# UNVERIFIED verdict path. Never touches the network (docker images are local), never reaches ntfy.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
rc=0
PYS=()
if [ -x /usr/bin/python3.12 ]; then PYS+=(/usr/bin/python3.12); fi
if [ "${#PYS[@]}" -eq 0 ] || [ "${QA_TEST_BOTH:-0}" = "1" ]; then PYS+=("$(command -v python3)"); fi
for py in "${PYS[@]}"; do
  echo "--- test_qa_migrations.py under $py ($("$py" -V 2>&1))"
  "$py" "$HERE/test_qa_migrations.py" || rc=1
done
exit $rc
