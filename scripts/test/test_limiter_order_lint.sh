#!/usr/bin/env bash
# test_limiter_order_lint.sh - P6a: scripts/ovn_limiter_order_lint.py (limiter decorator ABOVE a route decorator = limit never enforced) and its per-cycle hook lib_limiter_lint.sh
# (OVN_LIMITER_LINT=off|shadow|enforce, default shadow = alert + log only, never a revert; only files the commit touched). Temp dirs from lib_safe_tmp.sh (fail closed); no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
L="$HERE/../ovn_limiter_order_lint.py"; H="$HERE/../lib_limiter_lint.sh"
[ -f "$L" ] || { echo "  FAIL: $L missing"; exit 1; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1 ${3:+:: $3}"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
safe_set_sandbox_home "$tmp" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
mkdir -p "$tmp/fx"
cat > "$tmp/fx/bad.py" <<'T'
from fastapi import APIRouter
from slowapi import Limiter
router = APIRouter()
limiter = Limiter(key_func=lambda r: "k")

@limiter.limit("5/minute")
@router.post("/login")
async def login(request): ...

@limiter.shared_limit("10/minute", scope="auth")
@router.get("/me")
def me(request): ...
T
cat > "$tmp/fx/clean.py" <<'T'
from fastapi import APIRouter
from slowapi import Limiter
router = APIRouter()
limiter = Limiter(key_func=lambda r: "k")

@router.post("/login")
@limiter.limit("5/minute")
async def login(request): ...

@router.get("/ping")
async def ping(): ...
T
cat > "$tmp/fx/nonroute.py" <<'T'
import functools
from slowapi import Limiter
limiter = Limiter(key_func=lambda r: "k")
cache = {}

@limiter.limit("5/minute")
@functools.lru_cache(maxsize=4)
def helper(x): return x

@functools.wraps(helper)
@cache.get("k")
def other(x): return x

@limit
@property
def p(self): ...
T
cat > "$tmp/fx/alias.py" <<'T'
from slowapi import Limiter
from app.core.limiter import limiter as lm
limiter = Limiter(key_func=lambda r: "k")
five = limiter.limit("5/minute")
post = router.post

@five
@router.put("/a")
def a(request): ...

@lm.limit("1/second")
@app.delete("/b")
def b(request): ...

@limiter.limit("2/second")
@post("/c")
def c(request): ...

class K:
    @limiter.limit("3/second")
    @router.patch("/d")
    async def d(self, request): ...
T
cat > "$tmp/fx/syn.py" <<'T'
def broken(:
T
cnt(){ "$PY" "$L" check "$1" 2>/dev/null | grep -c ': L1 ' ; }
out="$("$PY" "$L" check "$tmp/fx/bad.py")"; rc=$?
ok "offender: exit 1" "$([ "$rc" = 1 ] && echo 0 || echo 1)" "rc=$rc"
ok "offender: 2 findings (limit + shared_limit), login and me named" "$([ "$(printf '%s\n' "$out" | grep -c ': L1 ')" = 2 ] && printf '%s' "$out" | grep -q 'login()' && printf '%s' "$out" | grep -q 'me()'; echo $?)" "$out"
out="$("$PY" "$L" check "$tmp/fx/clean.py")"; rc=$?
ok "clean file (limiter below route): exit 0, no output" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
out="$("$PY" "$L" check "$tmp/fx/nonroute.py")"; rc=$?
ok "non-route decorators (lru_cache, wraps, cache.get(key), bare @limit): no finding" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
out="$("$PY" "$L" check "$tmp/fx/alias.py")"
ok "aliases: bare alias, imported-as limiter, route alias, method in class, delete/patch/put all caught (4 findings)" "$([ "$(printf '%s\n' "$out" | grep -c ': L1 ')" = 4 ]; echo $?)" "$out"
out="$("$PY" "$L" check "$tmp/fx/syn.py")"; rc=$?
ok "syntax error file is skipped, never a finding (exit 0)" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
j="$("$PY" "$L" check --json "$tmp/fx/bad.py" "$tmp/fx/syn.py")"
ok "--json: 2 findings, 1 skipped" "$("$PY" -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if len(d["findings"])==2 and len(d["skipped"])==1 else 1)' "$j"; echo $?)" "$j"

# mutant: flip the order check (limiter BELOW route is flagged instead of ABOVE)
mkdir -p "$tmp/mut"
"$PY" - "$L" "$tmp/mut/ovn_limiter_order_lint.py" <<'T'
import sys
s = open(sys.argv[1]).read()
old = "below = [l2 for k2, l2 in kinds[i + 1:] if k2 == \"route\"]"
assert s.count(old) == 1
open(sys.argv[2], "w").write(s.replace(old, "below = [l2 for k2, l2 in kinds[:i] if k2 == \"route\"]"))
T
mo="$("$PY" "$tmp/mut/ovn_limiter_order_lint.py" check "$tmp/fx/bad.py" | grep -c ': L1 ')"; mc="$("$PY" "$tmp/mut/ovn_limiter_order_lint.py" check "$tmp/fx/clean.py" | grep -c ': L1 ')"
ok "MUTANT (order check flipped) is caught by these fixtures: offender gives 0, clean gives >0" "$([ "$mo" = 0 ] && [ "$mc" -gt 0 ]; echo $?)" "offender=$mo clean=$mc"

# diff mode: only files the commit touched
R="$tmp/repo"; mkdir -p "$R/app"; git -C "$R" init -q . && git -C "$R" checkout -q -b main 2>/dev/null
cp "$tmp/fx/bad.py" "$R/app/old_bad.py"; printf 'x = 1\n' > "$R/app/other.py"
git -C "$R" add -A && git -C "$R" commit -q -m base; B="$(git -C "$R" rev-parse HEAD)"
cp "$tmp/fx/clean.py" "$R/app/new_clean.py"; printf 'x = 2\n' > "$R/app/other.py"
git -C "$R" add -A && git -C "$R" commit -q -m touch-clean; A1="$(git -C "$R" rev-parse HEAD)"
out="$("$PY" "$L" diff --repo "$R" --before "$B" --after "$A1")"; rc=$?
ok "diff: a pre-existing offender the commit did not touch is NOT reported (exit 0)" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
cp "$tmp/fx/bad.py" "$R/app/new_bad.py"; git -C "$R" add -A && git -C "$R" commit -q -m touch-bad; A2="$(git -C "$R" rev-parse HEAD)"
out="$("$PY" "$L" diff --repo "$R" --before "$A1" --after "$A2")"; rc=$?
ok "diff: the touched offender is reported with a repo-relative path (exit 1)" "$([ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^app/new_bad.py:6: L1 '; echo $?)" "rc=$rc $out"

# P6 review fixes (2026-10-27): (1) diff mode reports only findings the commit INTRODUCED, (2) non-literal route paths, (3) lint_unsafe_rm exempts the helper from a sub-root
cat > "$tmp/fx/dyn.py" <<'T'
from fastapi import APIRouter
from slowapi import Limiter
router = APIRouter()
limiter = Limiter(key_func=lambda r: "k")
PATH = "/p"
base = "/api"

@limiter.limit("1/second")
@router.post(PATH)
def a(request): ...

@limiter.limit("1/second")
@router.post(f"{base}/b")
def b(request): ...

@limiter.limit("1/second")
@router.post(base + "/c")
def c(request): ...

@limiter.limit("1/second")
@router.get(IMPORTED_PATH)
def d(request): ...

@limiter.limit("1/second")
@cache.get(key)
def not_a_route(request): ...
T
out="$("$PY" "$L" check "$tmp/fx/dyn.py")"
ok "non-literal route paths (constant name, f-string, concat, ALL_CAPS import) caught (4); cache.get(key) not" "$([ "$(printf '%s\n' "$out" | grep -c ': L1 ')" = 4 ] && ! printf '%s' "$out" | grep -q not_a_route; echo $?)" "$out"
R2="$tmp/repo2"; mkdir -p "$R2/app"; git -C "$R2" init -q . && git -C "$R2" checkout -q -b main 2>/dev/null
cp "$tmp/fx/bad.py" "$R2/app/auth.py"; git -C "$R2" add -A && git -C "$R2" commit -q -m base; B2="$(git -C "$R2" rev-parse HEAD)"
printf '\n# unrelated edit\nx = 1\n' >> "$R2/app/auth.py"; git -C "$R2" add -A && git -C "$R2" commit -q -m unrelated; U2="$(git -C "$R2" rev-parse HEAD)"
out="$("$PY" "$L" diff --repo "$R2" --before "$B2" --after "$U2")"; rc=$?
ok "diff: pre-existing offender in a file the commit merely touched is NOT reported (exit 0)" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
printf '\n@limiter.limit("2/second")\n@router.put("/new")\ndef newone(request): ...\n' >> "$R2/app/auth.py"; git -C "$R2" add -A && git -C "$R2" commit -q -m intro; N2="$(git -C "$R2" rev-parse HEAD)"
out="$("$PY" "$L" diff --repo "$R2" --before "$U2" --after "$N2")"; rc=$?
ok "diff: a NEW offender added to the same file IS reported, the old two are not (exactly 1, newone)" "$([ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c ': L1 ')" = 1 ] && printf '%s' "$out" | grep -q 'newone()'; echo $?)" "rc=$rc $out"
git -C "$R2" mv app/auth.py app/auth2.py && git -C "$R2" commit -q -m rename; M2="$(git -C "$R2" rev-parse HEAD)"
out="$("$PY" "$L" diff --repo "$R2" --before "$N2" --after "$M2")"; rc=$?
ok "diff: a pure rename of an offender file reports nothing" "$([ "$rc" = 0 ] && [ -z "$out" ]; echo $?)" "rc=$rc $out"
LU="$HERE/lint_unsafe_rm.py"
if [ -f "$LU" ] && [ -f "$HERE/lib_safe_tmp.sh" ]; then
  out="$(cd "$HERE" && "$PY" "$LU" . 2>&1 | grep -c 'lib_safe_tmp.sh')"
  ok "lint_unsafe_rm: linting from the test dir as root does not flag the sandbox helper itself (R6)" "$([ "$out" = 0 ]; echo $?)" "findings=$out"
fi

# hook (lib_limiter_lint.sh)
if [ -f "$H" ]; then
  # shellcheck disable=SC1090
  . "$H"
  AL="$tmp/alerts.log"; SL="$tmp/limiter_lint.log"; export OVN_LIMITER_LINT_ALERTS="$AL" OVN_LIMITER_LINT_LOG="$SL"
  hook(){ OVN_LIMITER_LINT="$1" limiter_lint_gate "$R" "$A1" "$A2" >/dev/null; }
  hook shadow; rc=$?
  ok "hook shadow: returns 0 (never reverts), writes one log line and one alert naming the file" "$([ "$rc" = 0 ] && [ "$(grep -c new_bad.py "$SL")" -ge 1 ] && [ "$(wc -l < "$AL" | tr -d " ")" = 1 ] && grep -q 'limiter-order' "$AL"; echo $?)" "rc=$rc log=$(cat "$SL" 2>/dev/null) alerts=$(cat "$AL" 2>/dev/null)"
  : > "$AL"; : > "$SL"
  hook off; rc=$?
  ok "hook off: returns 0, no log, no alert" "$([ "$rc" = 0 ] && [ ! -s "$AL" ] && [ ! -s "$SL" ]; echo $?)"
  hook enforce; rc=$?
  ok "hook enforce: returns 1 for the touched offender" "$([ "$rc" = 1 ]; echo $?)" "rc=$rc"
  : > "$AL"; : > "$SL"
  OVN_LIMITER_LINT=shadow limiter_lint_gate "$R" "$B" "$A1" >/dev/null; rc=$?
  ok "hook shadow on a clean commit: 0, no alert" "$([ "$rc" = 0 ] && [ ! -s "$AL" ]; echo $?)"
  unset OVN_LIMITER_LINT
  limiter_lint_gate "$R" "$A1" "$A2" >/dev/null; rc=$?
  ok "hook default mode is shadow (no OVN_LIMITER_LINT set -> returns 0 even for an offender)" "$([ "$rc" = 0 ]; echo $?)"
  OVN_LIMITER_LINT_PY="$tmp/does-not-exist.py" OVN_LIMITER_LINT=enforce limiter_lint_gate "$R" "$A1" "$A2" >/dev/null; rc=$?
  ok "hook fail-open: lint script missing -> 0 even in enforce" "$([ "$rc" = 0 ]; echo $?)"
else
  ok "lib_limiter_lint.sh exists" 1 "missing $H"
fi
RO="$HERE/../../run_overnight.sh"
if [ -f "$RO" ]; then
  ok "run_overnight.sh sources lib_limiter_lint.sh" "$(grep -q 'source "\$SCRIPT_DIR/scripts/lib_limiter_lint.sh"' "$RO"; echo $?)"
  ok "run_overnight.sh calls limiter_lint_gate with BEFORE_SHA AFTER_SHA, default shadow, after the ghost-test gate" "$(grep -q 'limiter_lint_gate "\$(pwd)" "\$BEFORE_SHA" "\$AFTER_SHA"' "$RO" && grep -q 'OVN_LIMITER_LINT:-shadow' "$RO" && [ "$(grep -n 'GHOST-TEST GATE (2026' "$RO" | head -1 | cut -d: -f1)" -lt "$(grep -n 'LIMITER-ORDER LINT (P6a' "$RO" | head -1 | cut -d: -f1)" ]; echo $?)"
  ok "run_overnight.sh parses (bash -n)" "$(bash -n "$RO"; echo $?)"
fi
echo; echo "test_limiter_order_lint: $P passed, $F failed"; [ "$F" = 0 ]
