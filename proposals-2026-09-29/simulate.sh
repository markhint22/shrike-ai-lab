#!/usr/bin/env bash
# usage: simulate.sh <clone> <projdir> <venv-python> <first> <last>   -- emulates the proposed hook on a real failed commit
clone=$1; proj=$2; PY=$3; first=$4; last=$5
cd "$clone" && git checkout -qf "$last" && git clean -fdq -e .venv || exit 1
base=$(git rev-parse "$first^")
chain=ok; python3 ~/overnight-queue/scripts/check_migrations.py "$clone" >/dev/null 2>&1 || chain=BROKEN
added=$(git diff --name-only --diff-filter=A "$base" "$last" -- "$proj/alembic/versions/" | grep '\.py$' || true)
if [ "$chain" = BROKEN ]; then
  [ -n "$added" ] && git rm -q $added
  # restore any PRE-EXISTING migration the cycle edited/renamed/deleted (never leave history rewritten)
  git diff --name-only --diff-filter=MDT "$base" "$last" -- "$proj/alembic/versions/" | grep '\.py$' | while read -r f; do git checkout -q "$base" -- "$f"; done
  git diff --name-status --diff-filter=R "$base" "$last" -- "$proj/alembic/versions/" >/dev/null
fi
cd "$clone/$proj"
out=$($PY /tmp/proposals/ovn_alembic_autogen.py --message "sync models" 2>&1 | grep -E "^(GENERATED|NODRIFT|REFUSE|ERROR)" | head -1); rc=$?
new=$(echo "$out" | sed -n 's/^GENERATED //p')
if [ -n "$new" ]; then
  if [ "$proj" = iptv-backend ]; then export DATABASE_URL=sqlite:////tmp/x-$$.db; else unset DATABASE_URL; fi
  suite=$(timeout 300 $PY -m pytest tests -q -o addopts="" -p no:cacheprovider 2>&1 | tail -1 | cut -c1-120)
else suite="(skipped)"; fi
echo "$last chain=$chain removed=$(echo $added|wc -w) driver=[$out] suite=[$suite]"
