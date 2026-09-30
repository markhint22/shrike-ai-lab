#!/usr/bin/env bash
# Runs the REAL promote_to_prod.sh and staging_smoke.sh against throwaway bare origins + clones under a fake HOME
# (curl is an exported stub function; the smoke script runs as a real child bash and inherits it).
# Covers: usage, skip paths, nothing-to-promote, dry-run, smoke pass/fail/--force, migration gate, typed confirmation vs --yes,
# merge + push + prod tag + rollback tag, merge conflict, push failure, origin/HEAD fallback; plus every staging_smoke branch.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P2P="$HERE/../../promote_to_prod.sh"; [ -f "$P2P" ] || P2P="$HERE/../promote_to_prod.sh"
SMK="$HERE/../../staging_smoke.sh";   [ -f "$SMK" ] || SMK="$HERE/../staging_smoke.sh"
[ -f "$P2P" ] && [ -f "$SMK" ] || { echo "  SKIP: scripts not found"; exit 0; }
command -v timeout >/dev/null || { echo "  SKIP: no timeout(1)"; exit 0; }
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(mktemp -d)"; export T; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; Q="$HOME/overnight-queue"; OUT="$T/out.log"
curl(){ echo "curl $*" >> "$T/curl.log"
  case "$*" in
    *http_code*) printf '%s' "${SM_CODE:-200}";;
    *content_type*) printf '%s' "${SM_CT:-application/json}";;
    *" -D "*) [ "${SM_CORS:-1}" = 1 ] && printf 'HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: https://front.example\r\n\r\n' || printf 'HTTP/1.1 200 OK\r\n\r\n';;
  esac; return 0; }
export -f curl

setup(){  # fresh fake tree
  rm -rf "$T/home" "$T/origin" "$T/seed" "$T/curl.log"; mkdir -p "$Q/state" "$Q/scripts" "$T/origin" "$T/seed"
  cp "$SMK" "$Q/staging_smoke.sh"
  cat > "$Q/scripts/check_migrations.py" <<'PY'
import os, sys
if os.path.exists(os.path.expanduser("~/mig_fail")):
    print("  ✗ multiple heads"); sys.exit(1)
PY
  unset SM_CODE SM_CT SM_CORS
}
mkrepo(){  # $1=name  $2=mode: ahead | same | nodevelop | conflict
  local n="$1" mode="${2:-ahead}" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s" && echo base > f.txt && git add -A && git commit -q -m base && git branch -M main && git push -q origin main
    if [ "$mode" != nodevelop ]; then git checkout -q -b develop && echo dev > d.txt && git add -A && git commit -q -m "feat: dev work" && git push -q origin develop
      [ "$mode" = same ] && git push -q origin develop:main -f
      if [ "$mode" = conflict ]; then git checkout -q main && echo mainchange > d.txt && git add -A && git commit -q -m "hotfix on main" && git push -q origin main; fi
    fi )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
  [ -d "$Q/repos/$n/.git" ] || { mkdir -p "$Q/repos"; git clone -q "$o" "$Q/repos/$n" 2>/dev/null; }
}
mainsha(){ git -C "$T/origin/$1.git" rev-parse main; }
run(){ bash "$P2P" "$@" > "$OUT" 2>&1 < "${STDIN_FILE:-/dev/null}"; echo $? > "$T/rc"; }

# ---- usage / skip paths ----
setup; run
ok "no args -> usage exit 2" "$([ "$(cat $T/rc)" = 2 ] && has $OUT 'usage: promote_to_prod.sh' | grep -q 1 && echo 1 || echo 0)"
run "$Q/repos/ghost"
ok "no checkout -> SKIP" "$(has $OUT 'SKIP ghost (no checkout)')"
setup; mkrepo nodev nodevelop; run "$Q/repos/nodev"
ok "no develop -> SKIP" "$(has $OUT 'SKIP nodev (no develop)')"
setup; mkrepo same same; run "$Q/repos/same"
ok "develop == main -> nothing to promote" "$(has $OUT 'nothing to promote.')"

# ---- dry-run, no staging url ----
setup; mkrepo app ahead; m0="$(mainsha app)"; run --dry-run "$Q/repos/app"
ok "dry-run reports ahead count" "$(has $OUT 'develop is +1 ahead of main')"
ok "dry-run lists commit + files" "$([ "$(has $OUT 'feat: dev work')" = 1 ] && [ "$(has $OUT 'd.txt')" = 1 ] && echo 1 || echo 0)"
ok "dry-run warns smoke skipped (no staging url)" "$(has $OUT 'no staging URL configured')"
ok "dry-run: would merge line, main untouched" "$([ "$(has $OUT '[dry-run] would merge develop -> main')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"

# ---- typed confirmation ----
setup; mkrepo app ahead; m0="$(mainsha app)"; echo "wrong" > "$T/in"; STDIN_FILE="$T/in" run "$Q/repos/app"
ok "wrong confirmation -> aborted, main untouched" "$([ "$(has $OUT 'aborted.')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"
ok "no-staging interactive prints promoting-without-check hint" "$(has $OUT 'promoting without a staging check')"
echo "ship app" > "$T/in"; STDIN_FILE="$T/in" run "$Q/repos/app"
ok "typed 'ship app' -> PROMOTED" "$(has $OUT 'PROMOTED app develop -> main (+1)')"
ok "main advanced to a merge commit incl. develop" "$([ "$(mainsha app)" != "$m0" ] && git -C $T/origin/app.git merge-base --is-ancestor develop main && echo 1 || echo 0)"
tag="$(git -C $T/origin/app.git tag -l 'prod-*-app' | head -1)"
ok "prod rollback tag pushed to origin" "$([ -n "$tag" ] && echo 1 || echo 0)"
ok "tag points at new main tip" "$([ -n "$tag" ] && [ "$(git -C $T/origin/app.git rev-parse "$tag^{commit}")" = "$(mainsha app)" ] && echo 1 || echo 0)"
ok "rollback hint printed" "$(has $OUT "Rollback: git checkout $tag")"
ok "temp worktree cleaned up" "$([ "$(git -C $Q/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
STDIN_FILE=/dev/null run "$Q/repos/app"
ok "second run: nothing to promote (idempotent)" "$(has $OUT 'nothing to promote.')"

# ---- --yes with no staging url, origin/HEAD fallback to main ----
setup; mkrepo app ahead; git -C "$Q/repos/app" remote set-head origin -d >/dev/null 2>&1; run --yes "$Q/repos/app"
ok "--yes promotes; unresolved origin/HEAD falls back to main" "$(has $OUT 'PROMOTED app develop -> main')"
ok "--yes suppresses the interactive hint" "$([ "$(has $OUT 'promoting without a staging check')" = 0 ] && echo 1 || echo 0)"

# ---- smoke gate ----
setup; mkrepo app ahead; m0="$(mainsha app)"; echo "https://back.example https://front.example" > "$Q/state/staging_url_app"
export SM_CODE=502; run --yes "$Q/repos/app"
ok "smoke red blocks promote" "$([ "$(has $OUT 'smoke failed')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"
ok "smoke output shows health failure" "$(has $OUT 'health 502')"
run --yes --force "$Q/repos/app"
ok "--force overrides red smoke" "$(has $OUT 'PROMOTED app')"
setup; mkrepo app ahead; m0="$(mainsha app)"; echo "https://back.example https://front.example" > "$Q/state/staging_url_app"
export SM_CT="text/html"; run --yes "$Q/repos/app"
ok "HTML content-type blocks promote" "$([ "$(has $OUT 'API is serving HTML')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"
unset SM_CT; export SM_CORS=0; run --yes "$Q/repos/app"
ok "missing CORS header blocks promote" "$([ "$(has $OUT 'no access-control-allow-origin')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"
unset SM_CORS SM_CODE; run --yes "$Q/repos/app"
ok "green smoke (incl. CORS) promotes" "$([ "$(has $OUT 'SMOKE PASS')" = 1 ] && [ "$(has $OUT 'PROMOTED app')" = 1 ] && echo 1 || echo 0)"

# ---- migration safety gate ----
setup; mkrepo app ahead; m0="$(mainsha app)"; touch "$HOME/mig_fail"; run --yes "$Q/repos/app"
ok "migration gate red blocks promote + shows reason" "$([ "$(has $OUT 'migration safety FAILED')" = 1 ] && [ "$(has $OUT 'multiple heads')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"

# ---- merge conflict ----
setup; mkrepo app conflict; m0="$(mainsha app)"; run --yes "$Q/repos/app"
ok "merge conflict reported, main untouched" "$([ "$(has $OUT 'merge conflict develop vs main')" = 1 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"
ok "conflict leaves no stray worktree" "$([ "$(git -C $Q/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"

# ---- push failure (origin hook rejects) ----
setup; mkrepo app ahead; m0="$(mainsha app)"
printf '#!/bin/sh\nexit 1\n' > "$T/origin/app.git/hooks/pre-receive"; chmod +x "$T/origin/app.git/hooks/pre-receive"
run --yes "$Q/repos/app"
ok "push rejected -> 'push failed', not PROMOTED" "$([ "$(has $OUT 'push failed')" = 1 ] && [ "$(has $OUT 'PROMOTED')" = 0 ] && [ "$(mainsha app)" = "$m0" ] && echo 1 || echo 0)"

# ---- two repos in one invocation are independent ----
setup; mkrepo a ahead; mkrepo b same; run --yes "$Q/repos/a" "$Q/repos/b"
ok "multi-repo: a promoted, b nothing" "$([ "$(has $OUT 'PROMOTED a develop')" = 1 ] && [ "$(has $OUT 'b: develop is +0')" = 1 ] && echo 1 || echo 0)"

# ---- staging_smoke.sh directly ----
sm(){ bash "$SMK" "$@" > "$OUT" 2>&1; echo $? > "$T/rc"; }
unset SM_CODE SM_CT SM_CORS
sm https://b.example; ok "smoke: green no-origin exits 0" "$([ "$(cat $T/rc)" = 0 ] && has $OUT 'SMOKE PASS' | grep -q 1 && echo 1 || echo 0)"
SM_CODE=307 sm https://b.example; ok "smoke: 307 accepted" "$([ "$(cat $T/rc)" = 0 ] && echo 1 || echo 0)"
SM_CODE=204 sm https://b.example; ok "smoke: 204 accepted" "$([ "$(cat $T/rc)" = 0 ] && echo 1 || echo 0)"
SM_CODE=404 sm https://b.example; ok "smoke: 404 fails" "$([ "$(cat $T/rc)" = 1 ] && has $OUT 'SMOKE FAIL' | grep -q 1 && echo 1 || echo 0)"
SM_CT=text/html sm https://b.example; ok "smoke: html fails" "$([ "$(cat $T/rc)" = 1 ] && echo 1 || echo 0)"
sm https://b.example https://front.example; ok "smoke: CORS ok prints allow-origin" "$(has $OUT 'CORS allow-origin: https://front.example')"
SM_CORS=0 sm https://b.example https://front.example; ok "smoke: CORS missing fails" "$([ "$(cat $T/rc)" = 1 ] && echo 1 || echo 0)"
HEALTH_PATH=/api/health sm https://b.example; ok "smoke: HEALTH_PATH override used" "$(has $T/curl.log '/api/health')"
bash "$SMK" > "$OUT" 2>&1; rc=$?; ok "smoke: missing arg -> usage error" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
