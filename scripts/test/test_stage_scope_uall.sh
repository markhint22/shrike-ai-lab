#!/usr/bin/env bash
# Staged scope guard: `git status --porcelain` collapses a NEW directory to "dir/", so a step that legitimately created
# tests/new_pkg/test_x.py looked like it touched an undeclared path "tests/new_pkg/" and the whole attempt was discarded
# (76 of 256 scope-violation rejections in 14d). The guard must list individual files (-uall).
Q="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
( cd "$T" && git init -q -b main && echo x > a.txt && git add -A && git commit -q -m base && mkdir -p tests/new_pkg && echo t > tests/new_pkg/test_x.py && echo u > tests/new_pkg/helper.py )
old="$(git -C "$T" status --porcelain 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ')"
new="$(git -C "$T" status --porcelain -uall 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ')"
ok "CHARACTERISATION: plain porcelain collapses the new directory ('$old')" "$([ "$old" = "tests/ " ] && echo 1 || echo 0)"
ok "-uall lists the individual new files ('$new')" "$([ "$new" = "tests/new_pkg/helper.py tests/new_pkg/test_x.py " ] && echo 1 || echo 0)"
RUN="$Q/ovn_stage_runner.sh"
ok "stage runner scope guard uses status --porcelain -uall (the _touched list)" "$(grep -q "_touched=.*status --porcelain -uall" "$RUN" && echo 1 || echo 0)"
ok "stage runner empty-tree check uses -uall too" "$(grep -q 'git -C "\$wt" status --porcelain -uall 2>/dev/null)" ]; then' "$RUN" || grep -q 'status --porcelain -uall 2>/dev/null)" \]; then' "$RUN" && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
