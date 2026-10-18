#!/usr/bin/env bash
# 2026-10-11 (r11 acct, platform P9a): cycle_walltime.jsonl verify_s was 0 for EVERY row in 24h (the ledger only counted logged "VERIFY timed out" lines, so a verification that finished
# under its cap was invisible and a 450s xlite cycle showing 62s gen / 612s other could not be split). The runner now writes '--- verify done in Ns ---' (one per run_repo_verification
# run, both its exits) and '--- fixup done in Ns ---' (after each bounded fix-up aider call) into the cycle log; ovn_cycle_walltime.py sums them (verify_s += markers; fixup_s informational).
# Sections: A the REAL run_repo_verification writes the verify marker on each exit path, B ovn_cycle_walltime.py parses the markers (real script, throwaway state/logs), C wiring greps
# (3 fix-up aider calls), D MUTATION controls.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
unset OVN_WT_BACKFILL_H OVN_WT_MAX_ROWS OVN_WT_PREFILL_TPS OVN_WT_DECODE_TPS   # hermetic
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; R="$Q/run_overnight.sh"; W="$Q/scripts/ovn_cycle_walltime.py"
[ -f "$R" ] && [ -f "$W" ] || { echo "  SKIP: run_overnight.sh / ovn_cycle_walltime.py not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
# 2026-10-16: the embedded python heredocs call tempfile.mkdtemp(); point TMPDIR inside $tmp so the EXIT trap removes those dirs too (they were left in the private TMPDIR)
mkdir -p "$tmp/pytmp" && export TMPDIR="$tmp/pytmp"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

echo "== A: run_repo_verification writes the verify marker (REAL function)"
FN="$(sed -n '/^run_repo_verification() {/,/^}/p' "$R")"
[ -n "$FN" ] || { echo "  FAIL: could not extract run_repo_verification()"; exit 1; }
eval "$FN"
# 1) the repo-owned .ovn-verify.sh override path (one of the two exits)
G1="$tmp/g1"; mkdir -p "$G1"; cd "$G1" || exit 1; git init -q -b main . 2>/dev/null || git init -q .
printf '#!/usr/bin/env bash\nsleep 2\nexit 0\n' > .ovn-verify.sh; chmod +x .ovn-verify.sh; git add -A; git commit -q -m seed
BEFORE_SHA="$(git rev-parse HEAD)"; task_log="$tmp/t1.log"; : > "$task_log"
v="$(run_repo_verification)"
ok "A1 the override path returns pass and logs '--- verify done in Ns ---' with N >= 2" "[ '$v' = pass ] && grep -qE '^--- verify done in [2-9]s ---\$' '$task_log'"
ok "A2 exactly ONE verify marker for the one run, written AFTER the script output (never before the verify line)" "[ \"\$(grep -c '^--- verify done in ' '$task_log')\" = 1 ] && [ \"\$(grep -n '^--- verify: ' '$task_log' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n '^--- verify done in ' '$task_log' | head -1 | cut -d: -f1)\" ]"
# the failing override still logs the marker (a red verify costs time too)
printf '#!/usr/bin/env bash\nexit 3\n' > .ovn-verify.sh; task_log="$tmp/t1b.log"; : > "$task_log"
v="$(run_repo_verification)"
ok "A3 a failing override returns fail and still logs the marker" "[ '$v' = fail ] && grep -qE '^--- verify done in [0-9]+s ---\$' '$task_log'"
# 2) nothing provisioned: the final exit
G2="$tmp/g2"; mkdir -p "$G2"; cd "$G2" || exit 1; git init -q -b main . 2>/dev/null || git init -q .
printf 'x\n' > a.txt; git add -A; git commit -q -m seed; BEFORE_SHA="$(git rev-parse HEAD)"; task_log="$tmp/t2.log"; : > "$task_log"
v="$(run_repo_verification)"
ok "A4 the no-suite path returns none and logs '--- verify done in 0s ---'" "[ '$v' = none ] && grep -qE '^--- verify done in [0-9]+s ---\$' '$task_log'"
ok "A5 stdout is ONLY the verdict (the marker goes to the log): the verdict capture stays exactly 'none'" "[ '$v' = none ]"
cd "$HERE" || exit 1

echo "== B: ovn_cycle_walltime.py parses the markers (real script)"
cat > "$tmp/wall_check.py" <<'PYEOF'
import json, os, subprocess, sys, tempfile, time
W = sys.argv[1]
def iso(e): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))
def local_dir(e): return time.strftime("%Y%m%d-%H%M%S", time.localtime(e))
def case(log_text, dur=450, ts_=0, tr_=0):
    d = tempfile.mkdtemp(prefix="wt-")
    os.makedirs(os.path.join(d, "state")); os.makedirs(os.path.join(d, "logs"))
    e = time.time() - 3600
    p = os.path.join(d, "logs", local_dir(e - 60)); os.makedirs(p)
    open(os.path.join(p, "ongoing-xlite.log"), "w").write(log_text)
    open(os.path.join(d, "state", "outcomes.jsonl"), "w").write(json.dumps({"ts": iso(e), "repo": "xlite", "id": "ongoing-xlite", "type": "aider_fix", "tier": "2", "category": "godot", "class": "landed", "severity": "good", "attempt": 1, "attempts": 1, "status": "pushed(tests:pass)", "tokens_sent": ts_, "tokens_recv": tr_, "duration_s": dur, "item_hash": "", "feat_tag": ""}) + "\n")
    r = subprocess.run([sys.executable, W, os.path.join(d, "state"), os.path.join(d, "logs")], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=60)
    rows = [json.loads(l) for l in open(os.path.join(d, "state", "cycle_walltime.jsonl"))]
    return rows[0]
out = {}
# the 10-11 xlite shape: a 450s cycle, one 62s verify, a 45s fix-up and its 20s re-verify; 14k sent / 342 recv (est gen ~ 22s)
r = case("Tokens: 14k sent, 342 received.\n--- verify: GUT tests in . (90s cap) ---\n--- verify done in 62s ---\n--- Tier-2 fix-up: one bounded attempt ---\n--- fixup done in 45s ---\n--- verify done in 20s ---\n", ts_=14000, tr_=342)
out["sum_marks"] = r["verify_s"] == 82
out["fixup"] = r["fixup_s"] == 45
out["basis"] = r["verify_basis"] == "markers"
out["invariant"] = abs(r["gen_s"] + r["verify_s"] + r["other_s"] - r["duration_s"]) <= 1
out["other_split"] = r["other_s"] > 0 and r["verify_s"] > 0
# timeouts and markers add up (distinct things: clause timeouts vs suite runs)
r = case("--- verify done in 30s ---\n--- auto-credit: INDETERMINATE line 3 (a.gd) - VERIFY timed out (rc=124) after 100s; item left open ---\n")
out["timeouts_plus_marks"] = r["verify_s"] == 130
# a log written before the markers existed: unchanged behaviour (verify_s 0, basis none)
r = case("Tokens: 14k sent, 342 received.\n--- verify: GUT tests in . (90s cap) ---\n")
out["old_log"] = r["verify_s"] == 0 and r["verify_basis"] == "none" and r["fixup_s"] == 0
# only timeouts => basis timeouts
r = case("--- auto-credit: INDETERMINATE line 3 (a.gd) - VERIFY timed out (rc=124) after 100s; item left open ---\n")
out["timeouts_only"] = r["verify_s"] == 100 and r["verify_basis"] == "timeouts"
# a marker can never exceed the row's duration (clamped) and a garbled marker is ignored
r = case("--- verify done in 99999s ---\n--- verify done in xs ---\n", dur=300)
out["clamped"] = r["verify_s"] == 300 and r["other_s"] == 0
# a quoted marker inside model chatter (not at line start) is not counted
r = case("the model wrote: --- verify done in 500s --- as text\n")
out["quoted_ignored"] = r["verify_s"] == 0
print(json.dumps(out))
PYEOF
WR="$("$PY" "$tmp/wall_check.py" "$W" 2>/dev/null | tail -1)"
for k in sum_marks:"B1 two verify markers (62s + 20s) => verify_s 82 (was 0)" fixup:"B2 fixup marker => fixup_s 45 (informational)" basis:"B3 verify_basis is 'markers'" invariant:"B4 gen_s + verify_s + other_s == duration_s still holds" other_split:"B5 the 450s cycle is now splittable: other_s > 0 AND verify_s > 0" timeouts_plus_marks:"B6 logged VERIFY timeouts (100s) and suite markers (30s) add up to 130s" old_log:"B7 a pre-marker log keeps verify_s 0 / basis none / fixup_s 0" timeouts_only:"B8 timeouts only => verify_s 100, basis timeouts" clamped:"B9 an absurd marker is clamped to the row duration; a garbled one is ignored" quoted_ignored:"B10 a marker quoted mid-line in model chatter is not counted"; do
  ok "${k#*:}" "printf '%s' '$WR' | jq -e '.${k%%:*}'"
done

echo "== C: wiring in run_overnight.sh"
ok "C1 run_repo_verification has both marker call sites (override path + final exit) and the helper" "[ \"\$(grep -c '^ *_ovn_verify_done_mark\$' '$R')\" = 2 ] && grep -q '^  _ovn_verify_done_mark() { { echo \"--- verify done in' '$R'"
ok "C2 every fix-up aider call (BUILD-GATE, MIGRATION-SAFETY, Tier-2) is followed by a '--- fixup done in' marker (3)" "[ \"\$(grep -c 'echo \"--- fixup done in \$(( \$(date +%s) - _ovn_fx0 ))s ---\" >> \"\$task_log\"' '$R')\" = 3 ] && [ \"\$(grep -c '_ovn_fx0=\"\$(date +%s)\"' '$R')\" = 3 ]"

echo "== D: MUTATION controls"
mkdir -p "$tmp/mut"; cp "$Q"/scripts/*.py "$tmp/mut/" 2>/dev/null   # the mutated walltime copies need their sibling modules (ovn_failure_triage.py ...)
"$PY" - "$R" "$W" "$tmp" <<'PYEOF'
import sys
r = open(sys.argv[1]).read(); w = open(sys.argv[2]).read()
def mut(s, a, b, name):
    assert s.count(a) == 1, a
    open(sys.argv[3] + ("/mut/" if name.endswith(".py") else "/") + name, "w").write(s.replace(a, b))
mut(r, '  _ovn_verify_done_mark\n  if [ "$py_ran" -eq 0 ]', '  if [ "$py_ran" -eq 0 ]', "m_nofinal.sh")
mut(w, '    verify = min(dur, ph["timeouts"] + ph["verify_marks"])', '    verify = min(dur, ph["timeouts"])', "m_nomarks.py")
mut(w, '        m = _MARK_RE.match(line)', '        m = re.search(r"--- (verify|fixup) done in (\\d+)s ---", line)', "m_unanchored.py")
PYEOF
ok "D1 MUTATION: without the final-exit marker the no-suite path logs no marker (A4 would fail)" "( eval \"\$(sed -n '/^run_repo_verification() {/,/^}/p' '$tmp/m_nofinal.sh')\"; cd '$G2' && BEFORE_SHA=\$(git rev-parse HEAD) && task_log='$tmp/t_m1.log' && : > \"\$task_log\" && run_repo_verification >/dev/null; ! grep -q '^--- verify done in ' \"\$task_log\" )"
ok "D2 MUTATION: without summing the markers verify_s is 0 again (B1 would fail)" "[ \"\$(\"$PY\" \"$tmp/wall_check.py\" '$tmp/mut/m_nomarks.py' 2>/dev/null | tail -1 | jq -r '.sum_marks')\" = false ]"
ok "D3 MUTATION: an unanchored marker regex counts a quoted marker (B10 would fail)" "[ \"\$(\"$PY\" \"$tmp/wall_check.py\" '$tmp/mut/m_unanchored.py' 2>/dev/null | tail -1 | jq -r '.quoted_ignored')\" = false ]"
ok "D4 MUTATION sanity: the unmutated script passes every B check" "printf '%s' '$WR' | jq -e 'all(.[]; . == true)'"

echo "walltime markers: $P passed, $F failed"; [ "$F" -eq 0 ]
