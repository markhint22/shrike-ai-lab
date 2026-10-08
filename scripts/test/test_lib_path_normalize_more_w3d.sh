#!/usr/bin/env bash
# Wave-3: direct tests of scripts/lib_path_normalize.sh ovn_normalize_path (empty input, exact tracked path, suffix match,
# basename fallback, untracked passthrough, loop+sort -u newline contract).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_path_normalize.sh"; [ -f "$LIB" ] || LIB="$HERE/../scripts/lib_path_normalize.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC1090
source "$LIB"
R="$tmp/repo"; mkdir -p "$R/app/deep" "$R/web"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t
  echo 1 > top.py; echo 1 > app/deep/mod.py; echo 1 > web/page.vue; git add -A; git commit -q -m i )
ok "empty extracted path -> empty line" "[ \"\$(ovn_normalize_path '$R' '')\" = '' ] && [ \"\$(ovn_normalize_path '$R' '' | wc -l | tr -d ' ')\" = 1 ]"
ok "exact tracked path is returned as is" "[ \"\$(ovn_normalize_path '$R' 'top.py')\" = top.py ]"
ok "suffix match resolves a partial path to the real tracked path" "[ \"\$(ovn_normalize_path '$R' 'deep/mod.py')\" = app/deep/mod.py ]"
ok "basename fallback resolves a wrong-directory path" "[ \"\$(ovn_normalize_path '$R' 'nowhere/page.vue')\" = web/page.vue ]"
ok "an untracked path passes through unchanged" "[ \"\$(ovn_normalize_path '$R' 'ghost/none.py')\" = ghost/none.py ]"
ok "a non-git dir (nothing tracked) passes the input through" "[ \"\$(ovn_normalize_path '$tmp' 'x/y.py')\" = x/y.py ]"
ok "loop+sort -u keeps one path per line (trailing-newline contract)" "[ \"\$(for f in top.py deep/mod.py; do ovn_normalize_path '$R' \"\$f\"; done | sort -u | wc -l | tr -d ' ')\" = 2 ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
