#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 11): idle behaviour.
#  (b) record_outcome writes at most ONE skip(exhausted) row per repo per hour (first skip after any non-skip row is written);
#  (a) after an all-exhausted pass the runner waits OVN_IDLE_SLEEP_S in 5 s steps (early exit on state/supply_kick) instead of exiting into an immediate systemd restart;
#  (c) the FIRST exhausted pass per repo (state/exhausted_since_<repo> absent) starts `ovn_work_supply.py <repo> --on-exhausted` in the background, without run.lock's fd 200.
# Helpers live in lib_fixup.sh (ovn_skip_row_should_write / ovn_skip_row_reset / ovn_idle_wait / ovn_exhausted_supply_kick / ovn_exhausted_clear); record_outcome is the REAL
# function extracted from run_overnight.sh. Mutation controls at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_fixup.sh"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$RUN")"; eval "$FN_SRC"
SCRIPT_DIR="$Q"; STATE_DIR="$W/state"; mkdir -p "$STATE_DIR"
rows(){ [ -f "$STATE_DIR/outcomes.jsonl" ] && wc -l < "$STATE_DIR/outcomes.jsonl" | tr -d ' ' || echo 0; }
rec(){ record_outcome id1 "$1" "$2" "" aider_fix 1 /dev/null 1 "" "" 2>/dev/null; }

# ---------------------------------------------------------------- (b) one skip(exhausted) row per repo per hour
: > "$STATE_DIR/outcomes.jsonl"
rec iptv_apps 'skip(exhausted)'; rec iptv_apps 'skip(exhausted)'; rec iptv_apps 'skip(exhausted)'
ok "(b) 3 consecutive skip(exhausted) in one hour => exactly 1 row" "[ \"\$(rows)\" = 1 ]"
ok "(b) the written row is the skip(exhausted) row (class skipped, severity expected)" "[ \"\$(jq -r '.class + \"|\" + .severity + \"|\" + .status' '$STATE_DIR/outcomes.jsonl' | head -1)\" = 'skipped|expected|skip(exhausted)' ]"
rec xlite 'skip(exhausted)'
ok "(b) a different repo has its own hour: its first skip is written (2 rows)" "[ \"\$(rows)\" = 2 ]"
rec iptv_apps 'pushed(tests:pass)'
ok "(b) a non-skip row is always written (3 rows)" "[ \"\$(rows)\" = 3 ]"
rec iptv_apps 'skip(exhausted)'
ok "(b) the first skip AFTER a non-skip row is written again (4 rows)" "[ \"\$(rows)\" = 4 ]"
rec iptv_apps 'skip(exhausted)'; rec iptv_apps 'skip(exhausted)'
ok "(b) ... and the following ones are suppressed again (still 4 rows)" "[ \"\$(rows)\" = 4 ]"
printf '%s' "$(( $(date +%s) - 3601 ))" > "$STATE_DIR/skip_row_ts_iptv_apps"
rec iptv_apps 'skip(exhausted)'
ok "(b) once the hour is over (marker 3601 s old) the next skip is written (5 rows)" "[ \"\$(rows)\" = 5 ]"
printf '%s' "$(( $(date +%s) - 3500 ))" > "$STATE_DIR/skip_row_ts_iptv_apps"
rec iptv_apps 'skip(exhausted)'
ok "(b) control: a marker 3500 s old is still inside the hour => suppressed (5 rows)" "[ \"\$(rows)\" = 5 ]"
rec iptv_apps 'skip(oversized-context)'
ok "(b) a skip of ANOTHER kind (oversized-context) is neither deduped nor does it reset the hour (6 rows, marker kept)" "[ \"\$(rows)\" = 6 ] && [ -f '$STATE_DIR/skip_row_ts_iptv_apps' ]"
rec iptv_apps 'no-op(ALREADY-DONE)'; rec iptv_apps 'no-op(ALREADY-DONE)'
ok "(b) non-skip rows are never deduped (8 rows)" "[ \"\$(rows)\" = 8 ]"
OVN_SKIP_ROW_DEDUPE=off rec iptv_apps 'skip(exhausted)'; OVN_SKIP_ROW_DEDUPE=off rec iptv_apps 'skip(exhausted)'
ok "(b) kill switch OVN_SKIP_ROW_DEDUPE=off writes every row (10 rows)" "[ \"\$(rows)\" = 10 ]"
# direct unit
rm -f "$STATE_DIR"/skip_row_ts_*
ok "(b) unit: first call writes, the second inside the hour does not, after a reset it does again" "ovn_skip_row_should_write r1 '$STATE_DIR' && ! ovn_skip_row_should_write r1 '$STATE_DIR' && { ovn_skip_row_reset r1 '$STATE_DIR'; ovn_skip_row_should_write r1 '$STATE_DIR'; }"

# ---------------------------------------------------------------- (a) idle wait
D="$W/idle"; mkdir -p "$D"
t0="$(date +%s)"; R1="$(ovn_idle_wait "$D" 2 1)"; t1="$(date +%s)"
ok "(a) no kick: waits the full (short) sleep in steps and answers 'timeout'" "[ '$R1' = timeout ] && [ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 6 ]"
: > "$D/supply_kick"; t0="$(date +%s)"; R2="$(ovn_idle_wait "$D" 30 5)"; t1="$(date +%s)"
ok "(a) a supply_kick that already exists wakes it at once ('kick', file deleted, no 30 s wait)" "[ '$R2' = kick ] && [ ! -e '$D/supply_kick' ] && [ $((t1 - t0)) -le 3 ]"
( sleep 1; : > "$D/supply_kick" ) & KP=$!
t0="$(date +%s)"; R3="$(ovn_idle_wait "$D" 30 1)"; t1="$(date +%s)"; wait "$KP"
ok "(a) a supply_kick written DURING the wait wakes it within a step ('kick', deleted, well under the 30 s cap)" "[ '$R3' = kick ] && [ ! -e '$D/supply_kick' ] && [ $((t1 - t0)) -le 6 ]"
ok "(a) default sleep comes from OVN_IDLE_SLEEP_S (set to 1 here => 'timeout' after ~1 s)" "[ \"\$(OVN_IDLE_SLEEP_S=1 OVN_IDLE_STEP_S=1 ovn_idle_wait '$D')\" = timeout ]"
ok "(a) garbage arguments fall back to sane defaults and never loop forever (step 0 => 5)" "[ \"\$(ovn_idle_wait '$D' 1 0)\" = timeout ]"

# ---------------------------------------------------------------- (c) exhausted supply kick
OD="$W/ovn"; mkdir -p "$OD/scripts" "$OD/logs"; SD="$W/kstate"; mkdir -p "$SD"
cat > "$OD/scripts/ovn_work_supply.py" <<'EOP'
# a supply-v2 style script: implements --on-exhausted (the default 'auto' mode launches only such a script)
import os, sys
fd200 = "open" if os.path.exists("/dev/fd/200") else "closed"
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supply_calls.txt"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + " fd200=" + fd200 + "\n")
EOP
calls(){ [ -f "$OD/supply_calls.txt" ] && wc -l < "$OD/supply_calls.txt" | tr -d ' ' || echo 0; }
waitcalls(){ local i=0; while [ "$i" -lt 50 ]; do [ "$(calls)" -ge "$1" ] && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
exec 200> "$W/lockfile"    # simulate run.lock's fd 200 being open in the runner
ovn_exhausted_supply_kick iptv_apps "$SD" "$OD"; waitcalls 1
ok "(c) first exhausted pass: the supply is launched once with '<repo> --on-exhausted'" "[ \"\$(calls)\" = 1 ] && grep -q '^iptv_apps --on-exhausted ' '$OD/supply_calls.txt'"
ok "(c) run.lock's fd 200 is closed for the supply child (it can never hold the runner's lock)" "grep -q 'fd200=closed' '$OD/supply_calls.txt'"
ok "(c) the exhausted_since marker exists (epoch)" "[ -s '$SD/exhausted_since_iptv_apps' ]"
ovn_exhausted_supply_kick iptv_apps "$SD" "$OD"; sleep 0.5
ok "(c) a second exhausted pass for the same repo does NOT relaunch (still 1 call)" "[ \"\$(calls)\" = 1 ]"
ovn_exhausted_supply_kick xlite "$SD" "$OD"; waitcalls 2
ok "(c) another repo has its own marker: launched (2 calls)" "[ \"\$(calls)\" = 2 ] && grep -q '^xlite --on-exhausted ' '$OD/supply_calls.txt'"
ovn_exhausted_clear iptv_apps "$SD"; ovn_exhausted_supply_kick iptv_apps "$SD" "$OD"; waitcalls 3
ok "(c) after ovn_exhausted_clear (work came back) the next exhaustion launches again (3 calls)" "[ \"\$(calls)\" = 3 ]"
ovn_exhausted_clear xlite "$SD"; OVN_EXHAUSTED_SUPPLY=off ovn_exhausted_supply_kick xlite "$SD" "$OD"; sleep 0.5
ok "(c) kill switch OVN_EXHAUSTED_SUPPLY=off: no launch (still 3 calls) but the marker is written" "[ \"\$(calls)\" = 3 ] && [ -s '$SD/exhausted_since_xlite' ]"
rm -rf "$W/ovn2"; mkdir -p "$W/ovn2"; ovn_exhausted_supply_kick gitlark "$SD" "$W/ovn2"; sleep 0.3
ok "(c) a missing ovn_work_supply.py is skipped silently (marker only, rc 0)" "[ -s '$SD/exhausted_since_gitlark' ] && [ ! -e '$W/ovn2/logs/work_supply.log' ]"
exec 200>&-

# (c2) harness-credit-integrity fix: the kick is OFF unless the deployed supply script implements --on-exhausted (a script that ignores the flag would run a
# normal supply pass with no lock of its own and could overlap the :07/:37 cron run). 'auto' is the default; 'on' forces; 'off' disables.
rm -f "$OD/supply_calls.txt"; rm -f "$SD"/exhausted_since_*
OD2="$W/ovn_old"; mkdir -p "$OD2/scripts" "$OD2/logs"
cat > "$OD2/scripts/ovn_work_supply.py" <<'EOP'
# today's supply script: takes a repo and some flags but knows nothing about the exhausted trigger
import os, sys
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supply_calls.txt"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
EOP
calls2(){ [ -f "$OD2/supply_calls.txt" ] && wc -l < "$OD2/supply_calls.txt" | tr -d ' ' || echo 0; }
ovn_exhausted_supply_kick iptv_apps "$SD" "$OD2"; sleep 0.8
ok "(c2) default (auto): a supply script that does NOT implement --on-exhausted is never launched (0 calls)" "[ \"\$(calls2)\" = 0 ]"
ok "(c2) ... but the exhausted_since marker is still written" "[ -s '$SD/exhausted_since_iptv_apps' ]"
ovn_exhausted_clear iptv_apps "$SD"; OVN_EXHAUSTED_SUPPLY=on ovn_exhausted_supply_kick iptv_apps "$SD" "$OD2"
i=0; while [ "$i" -lt 50 ] && [ "$(calls2)" -lt 1 ]; do sleep 0.1; i=$((i+1)); done
ok "(c2) OVN_EXHAUSTED_SUPPLY=on forces the launch even for such a script (1 call)" "[ \"\$(calls2)\" = 1 ]"
ovn_exhausted_clear iptv_apps "$SD"; ovn_exhausted_supply_kick iptv_apps "$SD" "$OD"; i=0; while [ "$i" -lt 50 ] && [ "$(calls)" -lt 1 ]; do sleep 0.1; i=$((i+1)); done
ok "(c2) default (auto) launches a script that implements --on-exhausted (supply-v2) (1 call)" "[ \"\$(calls)\" = 1 ]"
# the real tree's file is never launched by default unless it advertises the flag: assert the production gate string is what the check keys on
ok "(c2) the gate keys on the literal '--on-exhausted' inside the deployed script" "[ \"\$(grep -c \"grep -qF -- '--on-exhausted' \\\"\\\$od/scripts/ovn_work_supply.py\\\"\" '$S/lib_fixup.sh')\" = 1 ]"

# (a2) harness-credit-integrity fix: the idle-wait block must not leave stderr redirected to /dev/null for the rest of the run ('exec 200>&- 2>/dev/null' on a
# bare exec applies the redirection to the shell itself - journald/EXIT-trap output after the idle wait was lost). Run the EXACT executed line.
IDLE_LINE="$(grep -m1 '^  exec 200>&- ' "$RUN")"
stderr_after(){ printf 'exec 200>"%s"\n%s\necho STDERR_AFTER >&2\n' "$W/idle_lock" "$1" > "$W/idle_stub.sh"; bash "$W/idle_stub.sh" 2>"$W/idle_err" >/dev/null; cat "$W/idle_err"; }
ok "(a2) after the idle block's fd-200 close, stderr still reaches the caller" "case \"\$(stderr_after \"\$IDLE_LINE\")\" in *STDERR_AFTER*) true;; *) false;; esac"
ok "(a2) MUTATION: the old line ('exec 200>&- 2>/dev/null || true') swallows later stderr (the test would fail on it)" "case \"\$(stderr_after '  exec 200>&- 2>/dev/null || true')\" in *STDERR_AFTER*) false;; *) true;; esac"

# ---------------------------------------------------------------- wiring (code lines)
ok "record_outcome gates skip(exhausted) rows through ovn_skip_row_should_write before the token scan / jq" "[ \"\$(grep -c 'skip\\*exhausted\\*) ovn_skip_row_should_write \"\${2:-none}\" \"\$STATE_DIR\" || return 0 ;;' '$RUN')\" = 1 ]"
ok "the main loop kicks the supply on skip(exhausted) and clears the marker otherwise" "[ \"\$(grep -c 'ovn_exhausted_supply_kick \"\${REPO_BASENAME:-}\" \"\$STATE_DIR\" \"\$SCRIPT_DIR\" ;;' '$RUN')\" = 1 ] && [ \"\$(grep -c 'ovn_exhausted_clear \"\${REPO_BASENAME:-}\" \"\$STATE_DIR\" ;;' '$RUN')\" = 1 ]"
ok "the idle wait runs after cycle_notify.sh and releases run.lock (exec 200>&-) first" "[ \"\$(grep -c '^  exec 200>&- ' '$RUN')\" = 1 ] && [ \"\$(grep -n 'ovn_idle_wait \"\$STATE_DIR\"' '$RUN' | head -1 | cut -d: -f1)\" -gt \"\$(grep -n '^\\[ -x \"\$SCRIPT_DIR/cycle_notify.sh\" \\]' '$RUN' | tail -1 | cut -d: -f1)\" ]"
ok "the idle wait only fires when every lane this pass was idle (seen > 0 and idle == seen)" "[ \"\$(grep -c '_ovn_lanes_seen:-0}\" -gt 0 \\] && \\[ \"\${_ovn_lanes_idle:-0}\" -eq \"\${_ovn_lanes_seen:-0}\"' '$RUN')\" = 1 ]"
ok "OVN_IDLE_SLEEP_S=0 disables the wait (guard in the condition)" "[ \"\$(grep -c 'OVN_IDLE_SLEEP_S:-60}\" != 0' '$RUN')\" = 1 ]"

# ---------------------------------------------------------------- MUTATION controls
python3 - "$S/lib_fixup.sh" "$W" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, out):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + out, "w").write(s.replace(a, b))
mut('  if [ $((now - last)) -ge 3600 ]; then printf', '  if true; then printf', "m_dedupe.sh")
src = open(sys.argv[1]).read()
k = 'if [ -e "$sd/supply_kick" ]; then rm -f "$sd/supply_kick"; echo kick; return 0; fi'
assert src.count(k) == 2
open(sys.argv[2] + "/m_kick.sh", "w").write(src.replace(k, ':'))
mut('  [ -e "$sd/exhausted_since_${repo}" ] && return 0       # not the first exhausted pass for this repo\n', '', "m_first.sh")
mut('2>&1 < /dev/null 200>&- & ) 2>/dev/null', '2>&1 < /dev/null & ) 2>/dev/null', "m_fd.sh")
PY
ok "MUTATION: without the hour test every skip is written (second call inside the hour returns 0)" "( . '$W/m_dedupe.sh'; rm -f '$STATE_DIR'/skip_row_ts_mut; ovn_skip_row_should_write mut '$STATE_DIR'; ovn_skip_row_should_write mut '$STATE_DIR' )"
ok "MUTATION: a wait loop that ignores supply_kick answers 'timeout' and sleeps the full time (>= 3 s) even though a kick is present" "set -- \$( ( . '$W/m_kick.sh'; : > '$D/supply_kick'; t0=\$(date +%s); r=\$(ovn_idle_wait '$D' 3 1); t1=\$(date +%s); echo \"\$r \$((t1 - t0))\" ) ); [ \"\$1\" = timeout ] && [ \"\$2\" -ge 3 ]"
rm -f "$D/supply_kick"; rm -f "$OD/supply_calls.txt"; rm -f "$SD"/exhausted_since_*
ok "MUTATION: without the first-pass marker test the supply is relaunched on every exhausted pass (2 calls from 2 passes)" "( . '$W/m_first.sh'; ovn_exhausted_supply_kick mrepo '$SD' '$OD'; ovn_exhausted_supply_kick mrepo '$SD' '$OD'; sleep 1 ); [ \"\$(calls)\" = 2 ]"
rm -f "$OD/supply_calls.txt"; rm -f "$SD"/exhausted_since_*
exec 200> "$W/lockfile2"
ok "MUTATION: without 200>&- the supply child inherits run.lock's fd (fd200=open recorded)" "( . '$W/m_fd.sh'; ovn_exhausted_supply_kick mrepo2 '$SD' '$OD'; sleep 1 ); grep -q 'fd200=open' '$OD/supply_calls.txt'"
exec 200>&-
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
