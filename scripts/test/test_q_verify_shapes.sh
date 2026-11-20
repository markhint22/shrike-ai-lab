#!/usr/bin/env bash
# Regression test: package q-verify-shapes (2026-11-18). PART 1 = test_q_verify_shapes.py (new SHADOW VERIFY-shape rules, park_cycle, ovn_item_hazards; every source mutant must be killed, count printed by the python suite).
# PART 2 = the item-guard hook OVN_VERIFY_LINT_PARK (default OFF): an item whose last 2 picks were ALREADY-DONE/landed-uncredited and whose VERIFY carries a PARK_RULES verdict is parked
# '[AUTO-SKIP needs-human: VERIFY can never pass ...]' only when the switch is on; plus static checks of the run_overnight.sh hazard hook. Sandboxed (lib_safe_tmp.sh + lib_mac_test_sandbox.sh).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$SC/.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
for f in "$Q/ovn_verify_lint.py" "$Q/ovn_item_hazards.py" "$Q/ovn_pick_cap.py" "$SC/ovn_item_guard.sh"; do [ -f "$f" ] || { echo "  SKIP: $f not found"; exit 77; }; done
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: mac test sandbox"; exit 1; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TMPDIR="$T"
PY="$(command -v python3.12 || command -v python3)"
# Load determinism (the 2026-11-18 G_on_keeps_item_text flake under concurrent suites): the guard's per-helper ovn_hto 30 caps are disabled for the guard runs below (OVN_HTO=off) and replaced by one generous outer cap, so CPU contention can never make the park hook time out and fall through
OVN_TEST_TO="$(command -v timeout || command -v gtimeout || true)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
mut(){ local lbl="$1" rel="$2" expr="$3"; shift 3; local d="$T/mut_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)"; safe_rm_rf "$d"; mkdir -p "$d"; cp -R "$Q/." "$d/" 2>/dev/null
  sed -E "$expr" "$Q/$rel" > "$d/$rel.new" && mv "$d/$rel.new" "$d/$rel"; if cmp -s "$Q/$rel" "$d/$rel"; then F=$((F+1)); echo "  FAIL: mutant '$lbl' did not change $rel"; return; fi
  if ( MUT="$d" eval "$*" ) >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL: mutant '$lbl' SURVIVED (check still passes)"; else P=$((P+1)); fi; }

# ---- PART 1
PYOUT="$("$PY" "$HERE/test_q_verify_shapes.py" 2>&1)"; PYRC=$?
printf '%s\n' "$PYOUT" | tail -5
ok "python suite (rules + park_cycle + hazards, 0 mutants survive)" "[ '$PYRC' = 0 ]"

# ---- PART 2: the guard hook
ITEM='[T1] backend/app/x.py - add the helper. VERIFY: `cd backend && python3 -m pytest tests/test_nope.py -q`'
ITEM_OK='[T1] backend/app/x.py - add the helper. VERIFY: `true`'
md5s(){ printf '%s' "$1" | md5sum 2>/dev/null | cut -d' ' -f1 || true; }
ITEM_HASH="$(md5s "$ITEM")"; [ -n "$ITEM_HASH" ] || ITEM_HASH="$(printf '%s' "$ITEM" | md5 -q)"
ITEM_OK_HASH="$(md5s "$ITEM_OK")"; [ -n "$ITEM_OK_HASH" ] || ITEM_OK_HASH="$(printf '%s' "$ITEM_OK" | md5 -q)"
mkg(){ # $1=dir [$2=sed -E expr applied to the guard copy] -> guard path (scripts + ovn_pick_cap.py + ovn_verify_lint.py one level up)
  mkdir -p "$1/scripts"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py lib_helper_timeout.sh lib_push_bound.sh; do [ -f "$SC/$f" ] && cp "$SC/$f" "$1/scripts/$f"; done
  cp "$Q/ovn_pick_cap.py" "$Q/ovn_verify_lint.py" "$1/"
  [ -n "${2:-}" ] && { sed -E "$2" "$1/scripts/ovn_item_guard.sh" > "$1/scripts/g.new" && mv "$1/scripts/g.new" "$1/scripts/ovn_item_guard.sh"; }
  echo "$1/scripts/ovn_item_guard.sh"; }
new_repo(){ local r="$T/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf -- '- [ ] [T0] other/a.py - first open line. VERIFY: `true`\n- [ ] %s\n' "${2:-$ITEM}" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); echo "$r"; }
jrow(){ local ts; ts="$("$PY" -c "import time,sys;print(time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()-float(sys.argv[1])*60)))" "$3")"
  printf '{"ts":"%s","repo":"%s","id":"ongoing-%s","class":"%s","severity":"neutral","status":"%s","item_hash":"%s","item_line_hash":"%s","duration_s":60}\n' "$ts" "$2" "$2" "$4" "$5" "$6" "$7" >> "$1/outcomes.jsonl"; }
runguard(){ local g="$1" r="$2" st="$3" status="$4"; shift 4; printf 'Tokens: 1k sent, 1 received.\n' > "$T/l.log"; env OVN_HTO=off OVN_PICK_CAP=off OVN_ITEM_DAY_CAP_MODE=off OVN_REVERT_REPEAT_MODE=off OVN_REPEAT_BREAKER=off OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 "$@" ${OVN_TEST_TO:+"$OVN_TEST_TO" 600} bash "$g" "$r" "$status" "$st" ongoing-r "$T/l.log" 2>&1; }
two(){ local st="$1" rn="$2" h="$3"; jrow "$st" "$rn" 100 noop 'no-op(ALREADY-DONE)' "$h" "$h"; jrow "$st" "$rn" 1 "${4:-noop}" "${5:-no-op(ALREADY-DONE)}" "$h" "$h"; }
guard_suite(){ # $1=label $2=guard
  local lb="$1" g="$2" r st rn out
  r="$(new_repo "${lb}_off")"; st="$T/${lb}_stoff"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' >/dev/null
  ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && [ ! -e "$st/verify_lint_park.log" ] && echo "G_default_off=1" || echo "G_default_off=0"
  r="$(new_repo "${lb}_on")"; st="$T/${lb}_ston"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH"
  out="$(runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=on)"
  [ "$(sed -n 2p "$r/OVERNIGHT_PROGRESS.md" | grep -c '^- \[ \] \[AUTO-SKIP needs-human: VERIFY can never pass (NODEID_WRONG_FILE) and the item came back 2x')" = 1 ] && [ "$(grep -c AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md")" = 1 ] && [ "$(sed -n 1p "$r/OVERNIGHT_PROGRESS.md")" = '- [ ] [T0] other/a.py - first open line. VERIFY: `true`' ] && echo "G_on_parks_exact_line=1" || echo "G_on_parks_exact_line=0"
  grep -qF -- "$ITEM" "$r/OVERNIGHT_PROGRESS.md" && [ "$(wc -l < "$r/OVERNIGHT_PROGRESS.md" | tr -d ' ')" = 2 ] && echo "G_on_keeps_item_text=1" || echo "G_on_keeps_item_text=0"
  [ "$(git -C "$r" log --oneline | wc -l | tr -d ' ')" = 2 ] && git -C "$r" log -1 --format=%s | grep -q 'verify-lint park' && echo "G_on_commits=1" || echo "G_on_commits=0"
  grep -q 'rule=NODEID_WRONG_FILE' "$st/verify_lint_park.log" 2>/dev/null && printf '%s' "$out" | grep -q 'AUTO-SKIPPED item (VERIFY can never pass' && grep -q 'verify-lint-park: item at line 2 parked' "$T/l.log" && echo "G_on_logs=1" || echo "G_on_logs=0"
  r="$(new_repo "${lb}_bad")"; st="$T/${lb}_stbad"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=yes >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_only_on_means_on=1" || echo "G_only_on_means_on=0"
  r="$(new_repo "${lb}_lo")"; st="$T/${lb}_stlo"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=on OVN_VERIFY_LINT=off >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_lint_off_disables_park=1" || echo "G_lint_off_disables_park=0"
  r="$(new_repo "${lb}_one")"; st="$T/${lb}_stone"; mkdir -p "$st"; rn="$(basename "$r")"; jrow "$st" "$rn" 1 noop 'no-op(ALREADY-DONE)' "$ITEM_HASH" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=on >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_one_pick_no_park=1" || echo "G_one_pick_no_park=0"
  r="$(new_repo "${lb}_ok" "$ITEM_OK")"; st="$T/${lb}_stok"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_OK_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=on >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_no_verdict_no_park=1" || echo "G_no_verdict_no_park=0"
  r="$(new_repo "${lb}_rr")"; st="$T/${lb}_strr"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH" noop 'no-op(reverted-red)'
  runguard "$g" "$r" "$st" 'no-op(reverted-red)' OVN_VERIFY_LINT_PARK=on >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_reverted_red_not_a_verify_failure=1" || echo "G_reverted_red_not_a_verify_failure=0"
  r="$(new_repo "${lb}_ex")"; st="$T/${lb}_stex"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH" landed-uncredited 'pushed(tests:pass)'
  runguard "$g" "$r" "$st" 'pushed(tests:pass)' OVN_VERIFY_LINT_PARK=on >/dev/null; rc=$?
  grep -q 'AUTO-SKIP needs-human: VERIFY can never pass' "$r/OVERNIGHT_PROGRESS.md" && [ "$rc" = 0 ] && echo "G_landed_uncredited_parks_rc0=1" || echo "G_landed_uncredited_parks_rc0=0"
  r="$(new_repo "${lb}_rules")"; st="$T/${lb}_strules"; mkdir -p "$st"; rn="$(basename "$r")"; two "$st" "$rn" "$ITEM_HASH"
  runguard "$g" "$r" "$st" 'no-op(ALREADY-DONE)' OVN_VERIFY_LINT_PARK=on OVN_VERIFY_LINT_PARK_RULES=DIRTY_PATH >/dev/null; ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && echo "G_park_rules_env_respected=1" || echo "G_park_rules_env_respected=0"
}
GS="$(guard_suite real "$(mkg "$T/g_real")")"
for k in G_default_off G_on_parks_exact_line G_on_keeps_item_text G_on_commits G_on_logs G_only_on_means_on G_lint_off_disables_park G_one_pick_no_park G_no_verdict_no_park G_reverted_red_not_a_verify_failure G_landed_uncredited_parks_rc0 G_park_rules_env_respected; do
  ok "guard park: $k" "grep -qx '$k=1' <<< \"\$GS\""; done
chkg(){ [ "$(guard_suite "m$$" "$(mkg "$T/g_m_$$" "$1")" 2>/dev/null | grep -c '=1$')" = "$(printf '%s\n' "$GS" | grep -c '=1$')" ]; }
gmut(){ local lbl="$1" expr="$2"; local gg; gg="$(mkg "$T/gm_$(echo "$lbl" | tr -c 'A-Za-z0-9' _)" "$expr")"; if cmp -s "$gg" "$SC/ovn_item_guard.sh"; then F=$((F+1)); echo "  FAIL: guard mutant '$lbl' did not change the guard"; return; fi
  local gs; gs="$(guard_suite "x$(echo "$lbl" | tr -c 'A-Za-z0-9' _)" "$gg" 2>/dev/null)"; if [ "$(printf '%s\n' "$gs" | grep -c '=1$')" = "$(printf '%s\n' "$GS" | grep -c '=1$')" ]; then F=$((F+1)); echo "  FAIL: guard mutant '$lbl' SURVIVED"; else P=$((P+1)); fi; }
gmut "default on" 's/OVN_VERIFY_LINT_PARK:-off\}" = on/OVN_VERIFY_LINT_PARK:-on}" = on/'
gmut "any value is on" 's/OVN_VERIFY_LINT_PARK:-off\}" = on \]/OVN_VERIFY_LINT_PARK:-off}" != off ]/'
gmut "lint off ignored" 's/ \&\& \[ "\$\{OVN_VERIFY_LINT:-shadow\}" != off \] \&\& \[ -f "\$state\/outcomes.jsonl" \] \&\& \[ -f "\$\(dirname "\$0"\)\/\.\.\/ovn_verify_lint.py" \]/ \&\& [ -f "$state\/outcomes.jsonl" ]/'
gmut "threshold 1 pick" 's/OVN_VERIFY_LINT_PARK_N:-2/OVN_VERIFY_LINT_PARK_N:-1/'
gmut "commit subject changed" 's/\$\{_vp_tag\}; verify-lint park\)/${_vp_tag}; other)/'
# ---- static: the hazard hook + wiring
RUN="$Q/run_overnight.sh"
ok "run_overnight: hazard hook runs ovn_item_hazards.py scan under ovn_hto, default shadow, off honoured, commits only a retirement" "grep -q 'OVN_ITEM_HAZARD:-shadow' '$RUN' && grep -q 'ovn_hto 60 item_hazard python3 \"\$SCRIPT_DIR/ovn_item_hazards.py\" scan OVERNIGHT_PROGRESS.md' '$RUN' && grep -q 'retire items that would delete all existing tests' '$RUN'"
ok "run_overnight: hazard hook sits right after the Q2 verify-lint hook (same site)" "[ \"\$(grep -n 'ovn_verify_lint.py\" shadow OVERNIGHT_PROGRESS.md' '$RUN' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'ovn_item_hazards.py\" scan OVERNIGHT_PROGRESS.md' '$RUN' | head -1 | cut -d: -f1)\" ]"
ok "run_overnight.sh parses" "bash -n '$RUN'"
ok "guard parses" "bash -n '$SC/ovn_item_guard.sh'"
ok "hazard module default mode is shadow in the source" "grep -q 'os.environ.get(\"OVN_ITEM_HAZARD\", \"shadow\")' '$Q/ovn_item_hazards.py'"
ok "park default is off in the source" "grep -q 'OVN_VERIFY_LINT_PARK:-off' '$SC/ovn_item_guard.sh'"
echo "q-verify-shapes: $P passed, $F failed"
[ "$F" = 0 ]
