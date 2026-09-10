#!/usr/bin/env bash
# Tests for the higher-tier pipeline added 2026-09-08:
#   - ovn_autotest.sh GODOT gate (gdparse syntax + godot --check-only semantic)
#   - queue_refill.py GODOT routing (godot -> Claude, never into the 27B queue)
#   - the INLINE higher-tier branch selection grep (run_overnight.sh)
#   - the stage runner AUTO-PICK grep (python-prefer, godot-exclude)
#   - the decompose GODOT-vs-python rules selection
# Pure-logic where possible so it runs anywhere; gate tests self-skip if gdparse/godot are absent.
set -uo pipefail
OVN="${OVN_ROOT:-$HOME/overnight-queue}"
P=0; F=0; S=0
ok(){   if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){  if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
skip(){ S=$((S+1)); echo "  SKIP: $1"; }

# ============ 1. INLINE higher-tier branch: "repo has a doable NON-GODOT T3+ item?" ============
# This is the exact predicate run_overnight uses to decide whether to run the sub-flow.
has_t3(){ grep -E '^- \[ \] ' "$1" 2>/dev/null | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED' \
            | grep -E '\[T[345]\]|·T[345]·' | grep -qviE '\.gd\b'; }
d=$(mktemp -d)
printf -- '- [ ] [T3] app/foo.py — add a fn\n' > "$d/py.md"
ok   "inline fires on a python T3 item"        "has_t3 $d/py.md"
printf -- '- [ ] [T4] app/svc.py — wire it\n'  > "$d/t4.md"
ok   "inline fires on a T4 item"               "has_t3 $d/t4.md"
printf -- '- [ ] [T3] scripts/battle/x.gd — add fn\n' > "$d/gd.md"
nok  "inline does NOT fire on a godot-only T3"  "has_t3 $d/gd.md"
printf -- '- [ ] [T1] app/foo.py — trivial\n- [ ] [T2] app/bar.py — small\n' > "$d/low.md"
nok  "inline does NOT fire when only T1/T2"     "has_t3 $d/low.md"
printf -- '- [ ] [AUTO-SKIP godot] [T3] x.gd — x\n- [ ] [T5] app/z.py — big\n' > "$d/mix.md"
ok   "inline fires on the python T5, ignores AUTO-SKIP godot" "has_t3 $d/mix.md"
printf -- '- [x] [T3] app/done.py — already done\n' > "$d/done.md"
nok  "inline does NOT fire on a checked-off item" "has_t3 $d/done.md"
rm -rf "$d"

# ============ 2. STAGE RUNNER auto-pick: prefer python, NEVER pick godot ============
pick(){  # mirrors ovn_stage_runner.sh lines 78-79
  local f="$1" _doable item
  _doable="$(grep -E '^- \[ \] ' "$f" | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED' | grep -E '\[T[345]\]|·T[345]·' | grep -viE '\.gd\b')"
  item="$(printf '%s\n' "$_doable" | grep -iE '\.py\b' | grep -viE 'wire|integrate|\.vue\b|\.tsx?\b' | head -1 | sed -E 's/^- \[ \] //')"
  [ -z "$item" ] && item="$(printf '%s\n' "$_doable" | head -1 | sed -E 's/^- \[ \] //')"
  printf '%s' "$item"
}
d=$(mktemp -d)
printf -- '- [ ] [T3] web/x.vue — ui\n- [ ] [T3] app/svc.py — logic\n' > "$d/q.md"
ok  "auto-pick PREFERS the python item over the vue" "[ \"\$(pick $d/q.md)\" = '[T3] app/svc.py — logic' ]"
printf -- '- [ ] [T3] scripts/a.gd — godot\n- [ ] [T3] web/x.vue — ui\n' > "$d/q2.md"
p2="$(pick "$d/q2.md")"
ok  "auto-pick NEVER returns a .gd item (falls to vue)" "printf '%s' \"\$p2\" | grep -qv '\\.gd'"
ok  "auto-pick fallback returns the non-godot hard item" "printf '%s' \"\$p2\" | grep -q '\\.vue'"
printf -- '- [ ] [T3] scripts/a.gd — godot only\n' > "$d/q3.md"
ok  "auto-pick returns EMPTY when only godot remains" "[ -z \"\$(pick $d/q3.md)\" ]"
rm -rf "$d"

# ============ 3. decompose GODOT-vs-python rules selection ============
rules_kind(){ case "$1" in *.gd*|*[Gg][Dd][Ss]cript*|*[Gg]odot*) echo godot;; *) echo python;; esac; }
ok  "decompose picks SOURCE-ONLY rules for a .gd item"   "[ \"\$(rules_kind '[T3] scripts/x.gd — add fn')\" = godot ]"
ok  "decompose picks SOURCE-ONLY rules for a 'Godot' item" "[ \"\$(rules_kind '[T3] add a Godot scene loader')\" = godot ]"
ok  "decompose picks self-verifying rules for a .py item" "[ \"\$(rules_kind '[T3] app/foo.py — add fn')\" = python ]"

# ============ 4. queue_refill.py GODOT routing ============
if [ -f "$OVN/queue_refill.py" ]; then
  d=$(mktemp -d)
  printf -- '- [ ] [T3] app/a.py — real python work\n- [ ] [T3] scripts/b.gd — godot work\n- [ ] [T2] app/c.py — more python\n' > "$d/backlog.md"
  printf '# progress\n' > "$d/prog.md"
  out="$(python3 "$OVN/queue_refill.py" "$d/prog.md" "$d/backlog.md" 5 2>/dev/null)"
  ok  "refill pulls the python items"                 "grep -q 'app/a.py' $d/prog.md && grep -q 'app/c.py' $d/prog.md"
  ok  "refill routes the .gd item to Claude (AUTO-SKIP in progress)" "grep -E 'AUTO-SKIP.*godot' $d/prog.md | grep -q 'scripts/b.gd'"
  ok  "refill reports GODOT_TO_CLAUDE>=1"              "printf '%s' \"\$out\" | grep -qE 'GODOT_TO_CLAUDE=[1-9]'"
  ok  "refill removes godot from the backlog"          "! grep -q 'scripts/b.gd' $d/backlog.md"
  ok  "the routed godot line is NOT a plain 27B item"  "! grep -E '^- \\[ \\] \\[T[0-9]\\] scripts/b.gd' $d/prog.md"
  rm -rf "$d"
else
  skip "queue_refill.py not found at $OVN"
fi

# ============ 5. ovn_autotest.sh GODOT gate (needs gdparse + godot) ============
GDP="$HOME/aider-venv/bin/gdparse"; GODOT="$HOME/godot/godot4"; AT="$OVN/scripts/ovn_autotest.sh"
if [ -x "$GDP" ] && [ -f "$AT" ]; then
  d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
    printf 'config_version=5\n' > project.godot; git add -A; git commit -qm init )
  # bad Godot-3 syntax -> gate FAILS
  printf 'extends KinematicBody2D\nexport var s = 1\nfunc _ready():\n\tyield(get_tree(),"x")\n' > "$d/bad.gd"
  ( cd "$d" && bash "$AT" "$d" >/dev/null 2>&1 ); ec_bad=$?
  ok  "godot gate FAILS on Godot-3 syntax"  "[ $ec_bad -ne 0 ]"
  # clean Godot-4 -> gate PASSES
  printf 'extends Node\n@export var s: int = 1\nfunc _ready() -> void:\n\tpass\n' > "$d/bad.gd"
  ( cd "$d" && bash "$AT" "$d" >/dev/null 2>&1 ); ec_ok=$?
  ok  "godot gate PASSES on clean Godot-4"   "[ $ec_ok -eq 0 ]"
  rm -rf "$d"
else
  skip "godot gate (gdparse/godot not installed — server-only test)"
fi

# ============ 6. gate FIX 2: "test exercises the changed source" detection (unit) ============
exercises(){ local tf="$1" m="$2" e=0; grep -qE "\\b${m}\\b" "$tf" 2>/dev/null && e=1; grep -qE '\.(get|post|put|delete|patch)\(' "$tf" 2>/dev/null && e=1; [ "$e" = 1 ]; }
d=$(mktemp -d)
printf 'from app.saved_search_service import SavedSearchService\ndef test_x(): assert SavedSearchService()\n' > "$d/good.py"
ok  "gate: a test importing the module EXERCISES it"       "exercises $d/good.py saved_search_service"
printf 'def test_x(): assert 1==1\n' > "$d/vac.py"
nok "gate: a vacuous test does NOT exercise the change"     "exercises $d/vac.py saved_search_service"
printf 'def test_ep(client): assert client.get(\"/topics\").status_code==200\n' > "$d/ep.py"
ok  "gate: an endpoint TestClient test counts as exercising" "exercises $d/ep.py some_router"
rm -rf "$d"

# ============ 7. gate END-TO-END: real ovn_autotest.sh rejects a vacuous test, accepts a real one ============
AT="$OVN/scripts/ovn_autotest.sh"
if [ -f "$AT" ]; then
  d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
    mkdir -p svc/.venv/bin svc/app svc/tests
    printf '#!/bin/sh\nexit 0\n' > svc/.venv/bin/pytest; chmod +x svc/.venv/bin/pytest
    printf 'class Foo:\n    pass\n' > svc/app/foo.py
    printf 'import pytest\n' > svc/tests/test_foo.py
    git add -A; git commit -qm init
    # uncommitted change: modify source + write a VACUOUS test (never names foo)
    printf 'class Foo:\n    def go(self): return 1\n' > svc/app/foo.py
    printf 'def test_x(): assert 1==1\n' > svc/tests/test_foo.py )
  ( cd "$d" && OVN_GATE_STRICT=1 bash "$AT" "$d" >/dev/null 2>&1 ); ec_vac=$?
  ok "gate e2e: REJECTS a source change whose test doesn't exercise it" "[ $ec_vac -ne 0 ]"
  printf 'from app.foo import Foo\ndef test_x(): assert Foo().go()==1\n' > "$d/svc/tests/test_foo.py"
  ( cd "$d" && OVN_GATE_STRICT=1 bash "$AT" "$d" >/dev/null 2>&1 ); ec_ok=$?
  ok "gate e2e: ACCEPTS when the test actually exercises the change"     "[ $ec_ok -eq 0 ]"
  # and the escape hatch works
  ( cd "$d"; printf 'def test_x(): assert 1==1\n' > svc/tests/test_foo.py )
  ( cd "$d" && OVN_GATE_STRICT=0 bash "$AT" "$d" >/dev/null 2>&1 ); ec_off=$?
  ok "gate e2e: OVN_GATE_STRICT=0 disables the exercise check (revert path)" "[ $ec_off -eq 0 ]"
  rm -rf "$d"
else
  skip "gate e2e (ovn_autotest.sh not found)"
fi

# ============ 8. verify-repair loop: failure-reason extraction + present & flag-guarded ============
extract_reason(){ grep -iE 'QUALITY FAIL|FAILED |assert|Error|Parse Error|Import|not declared|tzinfo|does not exercise' "$1" 2>/dev/null | grep -viE 'passed|0 error' | tail -12; }
d=$(mktemp -d)
printf '10 passed\nFAILED tests/test_x.py::test_foo - assert 3 == 4\n' > "$d/vlog"
ok  "repair: extracts the failed-test assertion for feedback" "extract_reason $d/vlog | grep -q 'assert 3 == 4'"
printf -- '-- QUALITY FAIL: no changed test exercises the changed source --\n' > "$d/vlog2"
ok  "repair: extracts a quality-guard verdict"                "extract_reason $d/vlog2 | grep -q 'QUALITY FAIL'"
printf 'All 20 tests passed\n' > "$d/vlog3"
ok  "repair: extracts NOTHING from an all-pass log"           "[ -z \"\$(extract_reason $d/vlog3)\" ]"
rm -rf "$d"
if [ -f "$OVN/ovn_stage_runner.sh" ]; then
  ok "runner HAS the general verify-repair loop"             "grep -q 'VERIFY-REPAIR LOOP' $OVN/ovn_stage_runner.sh"
  ok "verify-repair is flag-guarded (OVN_VERIFY_REPAIR_ROUNDS)" "grep -q 'OVN_VERIFY_REPAIR_ROUNDS' $OVN/ovn_stage_runner.sh"
  ok "verify-repair loads ALL changed files (source+test)"    "grep -q 'repair_fargs' $OVN/ovn_stage_runner.sh"
else
  skip "runner not found for repair-loop structural check"
fi

# ============ 9. try_regen: extract the "re-run `CMD`" instruction + safety-gate it ============
extract_cmd(){ sed -nE 's/.*re-?run `([^`]+)`.*/\1/p' "$1" 2>/dev/null | head -1; }
d=$(mktemp -d)
printf 'docs/openapi.json is stale - re-run `python scripts/export_openapi.py` from backend/ and commit\n' > "$d/v"
ok  "regen: extracts the regenerate command from the failure"    "[ \"\$(extract_cmd $d/v)\" = 'python scripts/export_openapi.py' ]"
printf 'a normal assertion failure, no regen instruction\n' > "$d/v2"
ok  "regen: extracts nothing when there is no re-run instruction" "[ -z \"\$(extract_cmd $d/v2)\" ]"
rm -rf "$d"
# safety: a command with shell metacharacters must be rejected by the allowlist gate
reject_meta(){ case "$1" in *';'*|*'|'*|*'&'*|*'>'*|*'<'*) return 0 ;; *) return 1 ;; esac; }
ok  "regen: rejects a shell-injection command"   "reject_meta 'python x.py; rm -rf /'"
nok "regen: accepts a plain python command"       "reject_meta 'python scripts/export_openapi.py'"
if [ -f "$OVN/ovn_stage_runner.sh" ]; then
  ok "runner HAS try_regen"                        "grep -q 'try_regen()' $OVN/ovn_stage_runner.sh"
  ok "regen is flag-guarded (OVN_VERIFY_REGEN)"    "grep -q 'OVN_VERIFY_REGEN' $OVN/ovn_stage_runner.sh"
  ok "repair diff-scope is capped (head -12)"      "grep -q 'head -12' $OVN/ovn_stage_runner.sh"
fi

echo "  higher-tier pipeline: $P passed, $F failed, $S skipped"
[ "$F" -eq 0 ]
