#!/usr/bin/env bash
# Regression test: queue_refill.py as the single writer between the spec gate and the queue (spec-compiler-v2 A2/A3/C4, 2026-10-09).
# Verdict rows are hand-made (state/spec_gate.jsonl) so every rule/policy is exercised without a scan:
#   repairs R01-R03 apply ONLY for rules in OVN_SPEC_GATE_ENFORCE_RULES; R04/R05/R07/R10/PB quarantine, R06 holds, R08 is never enforced; unjudged policy;
#   6h TTL; quarantine file format; restore round-trip (sticky); the ingest ban filter (A2); the vacuous-echo count (A3); kill switches.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
QR="${OVN_QUEUE_REFILL_PY:-$HERE/../../queue_refill.py}"
[ -f "$QR" ] || { echo "  SKIP: queue_refill.py not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (under pipefail `A | grep -q X` is flaky: grep -q exits at its first hit and A may take SIGPIPE)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
NOW=2026-10-09T12:00:00Z
STALE=2026-10-09T05:00:00Z   # 7h before NOW: past the 6h TTL

# fresh <name> -> a live dir with queue_refill.py + the module scripts, an empty progress file, no backlog yet
fresh(){
  local d="$tmp/$1"
  mkdir -p "$d/scripts" "$d/state" "$d/backlog" "$d/repos/demo"
  cp "$QR" "$d/queue_refill.py"
  cp "$SRC/ovn_backlog_eligibility.py" "$SRC/ovn_spec_rules.py" "$SRC/ovn_spec_classify.py" "$SRC/ovn_spec_gate.py" "$d/scripts/"
  : > "$d/repos/demo/OVERNIGHT_PROGRESS.md"; : > "$d/repos/demo/OVERNIGHT_DONE.md"
  printf '%s' "$d"
}
# vrow <dir> <line> <findings-json> <exec-json|null> [ts] -> appends one verdict row for that backlog line; prints its item_key
vrow(){
  python3 - "$1" "$2" "$3" "$4" "${5:-$NOW}" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1] + "/scripts")
import ovn_backlog_eligibility as E
d, line, findings, ex, ts = sys.argv[1:6]
key = E.line_hash(line) + "-abc1234"
row = {"ts": ts, "repo": "demo", "item_key": key, "feat": None, "tier": "T2", "path": "x", "base": "abc1234", "mode": "shadow",
       "exec": json.loads(ex), "findings": json.loads(findings), "repairs": [], "action": "x"}
open(d + "/state/spec_gate.jsonl", "a").write(json.dumps(row) + "\n")
print(key)
PYEOF
}
refill(){  # <dir> <n> [env assignments...]
  local d="$1" n="$2"; shift 2
  ( cd "$d" && env OVN_SPEC_GATE_NOW="$NOW" "$@" python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md "$n" )
}
paths(){ grep '^- \[ \] \[T' "$1" | awk '{print $5}' | tr '\n' ','; }
FIND(){ printf '[{"rule":"%s","sev":"flag","msg":"m","evidence":""}]' "$1"; }

L_BARE='- [ ] [T2] f.txt — rename old. VERIFY: grep -q old f.txt (cat:python; multifile:no)'
L_VAC='- [ ] [T2] g.txt — rename old. VERIFY: `grep -q old g.txt && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)'
L_NARR='- [ ] [T2] h.txt — remove old. VERIFY: `grep -q old h.txt` returns non-zero after the change. (cat:python; multifile:no)'
L_PLAIN='- [ ] [T2] p.txt — a plain item. VERIFY: `grep -q zzz p.txt`. (cat:python; multifile:no)'

echo "== repairs apply only for the rules in OVN_SPEC_GATE_ENFORCE_RULES"
D="$(fresh repair)"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_VAC" "$L_NARR" "$L_PLAIN" > "$D/backlog/demo.md"
out="$(refill "$D" 10)"
prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
ok "nothing enforced (default): all four lines pulled byte-for-byte unchanged" "[ \"\$(grep -c '^- \\[ \\] \\[T' '$prog')\" = 4 ] && grep -qF -- '$L_BARE' '$prog' && grep -qF -- '$L_VAC' '$prog' && grep -qF -- '$L_NARR' '$prog'"
ok "... and the vacuous-echo line is only COUNTED (VACUOUS_ECHO=1, no REPAIRED)" "printf '%s' '$out' | grep -c 'VACUOUS_ECHO=1' | grep -qx 1 && [ \"\$(printf '%s' '$out' | grep -c 'REPAIRED')\" = 0 ]"
rm -rf "$D"; D="$(fresh repair1)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_VAC" "$L_NARR" "$L_PLAIN" > "$D/backlog/demo.md"
out="$(refill "$D" 10 OVN_SPEC_GATE_ENFORCE_RULES=R01)"
ok "R01 only: the bare VERIFY is backticked; the vacuous and narrated lines are untouched" "grep -qF 'VERIFY: \`grep -q old f.txt\` (cat:' '$prog' && grep -qF -- '$L_VAC' '$prog' && grep -qF -- '$L_NARR' '$prog'"
ok "R01 only: REPAIRED is not reported (that field counts R02 repairs)" "[ \"\$(printf '%s' '$out' | grep -c 'REPAIRED=')\" = 0 ]"
rm -rf "$D"; D="$(fresh repair2)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_VAC" "$L_NARR" "$L_PLAIN" > "$D/backlog/demo.md"
out="$(refill "$D" 10 OVN_SPEC_GATE_ENFORCE_RULES=R02)"
ok "R02 only: the vacuous idiom is repaired to ! ( cmd ); bare and narrated lines untouched" "grep -qF 'VERIFY: \`! ( grep -q old g.txt )\`' '$prog' && grep -qF -- '$L_BARE' '$prog' && grep -qF -- '$L_NARR' '$prog'"
ok "R02: REPAIRED=1 and VACUOUS_ECHO=1 reported" "printf '%s' '$out' | grep -c 'REPAIRED=1' | grep -qx 1 && printf '%s' '$out' | grep -c 'VACUOUS_ECHO=1' | grep -qx 1"
ok "the backlog copies were removed by their ORIGINAL text (nothing left to re-pull)" "[ \"\$(grep -c '^- \\[ \\]' '$D/backlog/demo.md')\" = 0 ]"
rm -rf "$D"; D="$(fresh repair3)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_VAC" "$L_NARR" "$L_PLAIN" > "$D/backlog/demo.md"
refill "$D" 10 OVN_SPEC_GATE_ENFORCE_RULES=R03 >/dev/null
ok "R03 only: the narrated failure becomes ! cmd" "grep -qF 'VERIFY: \`! grep -q old h.txt\`' '$prog' && grep -qF -- '$L_BARE' '$prog' && grep -qF -- '$L_VAC' '$prog'"
ok "the plain line is never touched by any repair" "grep -qF -- '$L_PLAIN' '$prog'"
rm -rf "$D"; D="$(fresh repair4)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_VAC" "$L_NARR" "$L_PLAIN" > "$D/backlog/demo.md"
refill "$D" 10 OVN_SPEC_GATE_ENFORCE_RULES=R01,R02,R03 >/dev/null
ok "R01,R02,R03: all three repaired" "grep -qF 'VERIFY: \`grep -q old f.txt\` (cat:' '$prog' && grep -qF '! ( grep -q old g.txt )' '$prog' && grep -qF '\`! grep -q old h.txt\`' '$prog'"
rm -rf "$D"; D="$(fresh repair5)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n' "$L_VAC" "$L_BARE" > "$D/backlog/demo.md"
refill "$D" 10 OVN_SPEC_GATE=off OVN_SPEC_GATE_ENFORCE_RULES=R01,R02,R03 >/dev/null
ok "KILL SWITCH OVN_SPEC_GATE=off: nothing repaired even with rules enforced" "grep -qF -- '$L_VAC' '$prog' && grep -qF -- '$L_BARE' '$prog'"
# mutation: a queue_refill whose gate ignores the (empty) enforce list repairs by default - the 'nothing enforced' assertion above would catch it
MUT="$tmp/mutqr"; mkdir -p "$MUT"; cp -R "$D/scripts" "$MUT/"
python3 - "$QR" "$MUT/queue_refill.py" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
needle = 'if os.environ.get("OVN_SPEC_GATE", "shadow") == "off" or not rules:'
assert needle in s
s = s.replace(needle, 'rules = {"R01", "R02", "R03"}\n    if False:', 1)
s = s.replace('if "R02" in enforce_rules() and', 'if True and', 1)
open(sys.argv[2], "w").write(s)
PYEOF
mkdir -p "$MUT/backlog" "$MUT/state" "$MUT/repos/demo"; : > "$MUT/repos/demo/OVERNIGHT_PROGRESS.md"; : > "$MUT/repos/demo/OVERNIGHT_DONE.md"; printf '%s\n%s\n' "$L_VAC" "$L_BARE" > "$MUT/backlog/demo.md"
( cd "$MUT" && python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md 10 ) >/dev/null 2>&1
ok "MUTATION (gate ignores the enforce list): the lines get repaired by default, so the 'nothing enforced' assertion is load-bearing" "! grep -qF -- '$L_VAC' '$MUT/repos/demo/OVERNIGHT_PROGRESS.md'"

echo "== verdict-based rules: quarantine / hold / unjudged / TTL"
Q_R05='- [ ] [T2] a.py — Verify the thing works. VERIFY: `true`. (cat:python; multifile:no)'
Q_R07='- [ ] [T2] b.py — Add and delete. VERIFY: `grep -q b b.py`. (cat:python; multifile:no)'
Q_R10='- [ ] [T2] c.py — Send 11 requests, assert 429. VERIFY: `pytest tests/test_c.py`. (cat:python; multifile:no)'
H_R06='- [ ] [T3] d.py — Delete func old(). VERIFY: `! grep -q old d.py`. (cat:python; multifile:no) [feat:demo-20261009-x]'
N_R08='- [ ] [T2] e.py — Modify `ghost()`. VERIFY: `grep -q ghost e.py`. (cat:python; multifile:no)'
P_PB='- [ ] [T2] k.py — Already done. VERIFY: `grep -q done k.py`. (cat:python; multifile:no)'
U_NOV='- [ ] [T2] u.py — Never judged. VERIFY: `grep -q u u.py`. (cat:python; multifile:no)'
S_STALE='- [ ] [T2] s.py — Verdict too old. VERIFY: `grep -q s s.py`. (cat:python; multifile:no)'
D="$(fresh verdict)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '%s\n' "$Q_R05" "$Q_R07" "$Q_R10" "$H_R06" "$N_R08" "$P_PB" "$U_NOV" "$S_STALE" > "$D/backlog/demo.md"
K05="$(vrow "$D" "$Q_R05" "$(FIND R05)" null)"; vrow "$D" "$Q_R07" "$(FIND R07)" null >/dev/null; vrow "$D" "$Q_R10" "$(FIND R10)" null >/dev/null
vrow "$D" "$H_R06" "$(FIND R06)" null >/dev/null; vrow "$D" "$N_R08" "$(FIND R08)" null >/dev/null
vrow "$D" "$P_PB" '[]' '{"verdict":"passes-before","sub":"","rc":0,"ms":5}' >/dev/null
vrow "$D" "$S_STALE" "$(FIND R05)" null "$STALE" >/dev/null
cp "$D/backlog/demo.md" "$tmp/verdict.before"
out="$(refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R05,R06,R07,R10,PB)"
q="$D/backlog/quarantine/demo.md"
ok "R05, R07, R10 and PB lines are quarantined (4); output says QUARANTINED=4 HELD=1" "[ \"\$(grep -c . '$q')\" = 4 ] && printf '%s' '$out' | grep -c 'QUARANTINED=4' | grep -qx 1 && printf '%s' '$out' | grep -c 'HELD=1' | grep -qx 1"
ok "quarantine entry format: <original line>  <!-- spec-gate:RNN <ts> -->" "grep -qF -- '$Q_R05  <!-- spec-gate:R05 $NOW -->' '$q' && grep -qF -- '$Q_R07  <!-- spec-gate:R07 $NOW -->' '$q' && grep -qF -- '$Q_R10  <!-- spec-gate:R10 $NOW -->' '$q'"
ok "PB entry carries the 'already-satisfied?' note" "grep -qF -- '$P_PB  <!-- spec-gate:PB $NOW already-satisfied? -->' '$q'"
ok "a passes-before line is NEVER credited (done archive untouched)" "[ ! -s '$D/repos/demo/OVERNIGHT_DONE.md' ]"
ok "R06 is a HOLD: the line stays in the backlog, not quarantined, not queued" "grep -qF -- '$H_R06' '$D/backlog/demo.md' && [ \"\$(grep -c 'Delete func old' '$q')\" = 0 ] && [ \"\$(grep -c 'Delete func old' '$prog')\" = 0 ]"
ok "R08 is flag-only: even a finding R08 is pulled" "grep -qF -- '$N_R08' '$prog'"
ok "an UNJUDGED line is pulled (OVN_SPEC_GATE_UNJUDGED=pull default)" "grep -qF -- '$U_NOV' '$prog'"
ok "a verdict older than the 6h TTL is ignored: the line is pulled" "grep -qF -- '$S_STALE' '$prog'"
ok "the spec-gate marker never uses an AUTO-SKIP tag (the Claude-queue bridge harvests those)" "[ \"\$(grep -c 'AUTO-SKIP' '$q')\" = 0 ]"
ok "pulled lines kept their original relative order (e, u, s)" "[ \"\$(paths '$prog')\" = 'e.py,u.py,s.py,' ]"
ok "the backlog now holds only the held line" "[ \"\$(grep -c '^- \\[ \\]' '$D/backlog/demo.md')\" = 1 ]"

echo "== only the enforced rules act"
D="$(fresh partial)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '%s\n' "$Q_R05" "$Q_R07" "$H_R06" "$P_PB" > "$D/backlog/demo.md"
vrow "$D" "$Q_R05" "$(FIND R05)" null >/dev/null; vrow "$D" "$Q_R07" "$(FIND R07)" null >/dev/null; vrow "$D" "$H_R06" "$(FIND R06)" null >/dev/null
vrow "$D" "$P_PB" '[]' '{"verdict":"passes-before","sub":"","rc":0,"ms":5}' >/dev/null
refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R07 >/dev/null
ok "R07 enforced alone: only the R07 line is quarantined; R05, R06 (not held) and passes-before lines are pulled" "[ \"\$(grep -c . '$D/backlog/quarantine/demo.md')\" = 1 ] && grep -c 'spec-gate:R07' '$D/backlog/quarantine/demo.md' | grep -qx 1 && [ \"\$(paths '$prog')\" = 'a.py,d.py,k.py,' ]"
rm -rf "$D"; D="$(fresh partial2)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '%s\n' "$Q_R05" "$P_PB" > "$D/backlog/demo.md"; vrow "$D" "$Q_R05" "$(FIND R05)" null >/dev/null; vrow "$D" "$P_PB" '[]' '{"verdict":"passes-before","sub":"","rc":0,"ms":5}' >/dev/null
refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=PB >/dev/null
ok "PB enforced alone: only the passes-before line is quarantined" "[ \"\$(grep -c . '$D/backlog/quarantine/demo.md')\" = 1 ] && grep -c 'spec-gate:PB' '$D/backlog/quarantine/demo.md' | grep -qx 1 && [ \"\$(paths '$prog')\" = 'a.py,' ]"

echo "== held lines do not starve the queue (they are not counted against SCAN_CAP)"
D="$(fresh starve)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
for i in $(seq 1 40); do l="- [ ] [T3] d$i.py — Delete func old$i(). VERIFY: \`true\`. (cat:python; multifile:no) [feat:demo-20261009-s]"; printf '%s\n' "$l" >> "$D/backlog/demo.md"; vrow "$D" "$l" "$(FIND R06)" null >/dev/null; done
printf '%s\n' "$U_NOV" >> "$D/backlog/demo.md"
out="$(refill "$D" 5 OVN_SPEC_GATE_ENFORCE_RULES=R06)"
ok "40 held lines ahead of one good line: the good line is still pulled (HELD=40)" "[ \"\$(paths '$prog')\" = 'u.py,' ] && printf '%s' '$out' | grep -c 'HELD=40' | grep -qx 1"

# mutation: count held lines against SCAN_CAP again (the old order) and the starvation returns
python3 - "$QR" "$D/queue_refill.py" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
a = "        scanned += 1\n"
b = "        action, l2, rule, note = consult_gate(l, repo_label, verdicts)\n"
assert a in s and b in s
s = s.replace(a, "", 1).replace(b, "        scanned += 1\n" + b, 1)
open(sys.argv[2], "w").write(s)
PYEOF
rm -f "$prog"; : > "$prog"
for i in $(seq 1 40); do l="- [ ] [T3] d$i.py — Delete func old$i(). VERIFY: \`true\`. (cat:python; multifile:no) [feat:demo-20261009-s]"; printf '%s\n' "$l"; done > "$D/backlog/demo.md"; printf '%s\n' "$U_NOV" >> "$D/backlog/demo.md"
refill "$D" 5 OVN_SPEC_GATE_ENFORCE_RULES=R06 >/dev/null
ok "MUTATION (held lines counted against SCAN_CAP): the good line is starved, so the assertion above is load-bearing" "[ \"\$(paths '$prog')\" = '' ]"

echo "== unjudged policy"
D="$(fresh unjudged)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n' "$U_NOV" "$Q_R05" > "$D/backlog/demo.md"; vrow "$D" "$Q_R05" '[]' null >/dev/null
out="$(refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R05 OVN_SPEC_GATE_UNJUDGED=hold)"
ok "OVN_SPEC_GATE_UNJUDGED=hold: the line with no verdict stays in the backlog, the judged clean line is pulled" "grep -qF -- '$U_NOV' '$D/backlog/demo.md' && [ \"\$(paths '$prog')\" = 'a.py,' ] && printf '%s' '$out' | grep -c 'HELD=1' | grep -qx 1"
rm -rf "$D"; D="$(fresh unjudged2)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n' "$U_NOV" > "$D/backlog/demo.md"
refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R01 OVN_SPEC_GATE_UNJUDGED=hold >/dev/null
ok "'hold' only matters when a verdict-based rule is enforced (R01 alone: pulled)" "[ \"\$(paths '$prog')\" = 'u.py,' ]"

echo "== A2 ingest ban filter (no verdict needed)"
D="$(fresh ban)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '# banned\nscripts/battle/battle.gd\ntests/test_mission_select\n' > "$D/repos/demo/.queue-hard-banned-files"
{ for i in $(seq 1 35); do printf -- '- [ ] [T2] addons/gut/v%s.gd — vendored %s. VERIFY: `true`. (cat:python)\n' "$i" "$i"; done
  printf -- '- [ ] [T2] scripts/battle/battle.gd — hard banned. VERIFY: `grep -q x scripts/battle/battle.gd`. (cat:python)\n'
  printf -- '- [ ] [T2] scripts/ok.gd — fine, mentions addons/gut/gut.gd in the text. VERIFY: `grep -q addons/gut/gut.gd scripts/ok.gd`. (cat:python)\n'; } > "$D/backlog/demo.md"
out="$(refill "$D" 5)"
ok "37 banned lines are quarantined with R04 markers (35 addons/ + 1 listed); the good line is pulled despite 36 lines ahead of it (not counted against SCAN_CAP)" "printf '%s' '$out' | grep -c 'QUARANTINED=36' | grep -qx 1 && [ \"\$(grep -c 'spec-gate:R04' '$D/backlog/quarantine/demo.md')\" = 36 ] && [ \"\$(paths '$prog')\" = 'scripts/ok.gd,' ]"
ok "a banned PATH appearing only in the body/VERIFY does not quarantine (scripts/ok.gd pulled)" "grep -c 'scripts/ok.gd' '$prog' | grep -qx 1"
rm -rf "$D"; D="$(fresh ban2)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '# banned\naddons/\n' > "$D/repos/demo/.queue-hard-banned-files"
printf -- '- [ ] [T2] addons/gut/x.gd — vendored. VERIFY: `true`. (cat:python)\n' > "$D/backlog/demo.md"
refill "$D" 5 OVN_INGEST_BAN_FILTER=off >/dev/null
ok "OVN_INGEST_BAN_FILTER=off: the vendored line is pulled as before" "[ \"\$(paths '$prog')\" = 'addons/gut/x.gd,' ] && [ ! -e '$D/backlog/quarantine' ]"
rm -rf "$D"; D="$(fresh ban3)"
printf -- '- [ ] [T2] addons/gut/x.gd — vendored. VERIFY: `true`. (cat:python)\n' > "$D/backlog/demo.md"
refill "$D" 5 >/dev/null
printf -- '- [ ] [T2] addons/gut/x.gd — vendored. VERIFY: `true`. (cat:python)\n' > "$D/backlog/demo.md"
refill "$D" 5 >/dev/null
ok "the same banned line re-added later is quarantined again WITHOUT a duplicate quarantine entry" "[ \"\$(grep -c 'addons/gut/x.gd' '$D/backlog/quarantine/demo.md')\" = 1 ]"

echo "== restore round-trip"
D="$(fresh restore)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"; printf '%s\n%s\n' "$Q_R05" "$P_PB" > "$D/backlog/demo.md"
K05="$(vrow "$D" "$Q_R05" "$(FIND R05)" null)"; vrow "$D" "$P_PB" '[]' '{"verdict":"passes-before","sub":"","rc":0,"ms":5}' >/dev/null
refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R05,PB >/dev/null
q="$D/backlog/quarantine/demo.md"
ok "setup: both lines quarantined, backlog and queue empty" "[ \"\$(grep -c . '$q')\" = 2 ] && [ \"\$(grep -c '^- \\[ \\]' '$D/backlog/demo.md')\" = 0 ] && [ \"\$(paths '$prog')\" = '' ]"
rout="$( cd "$D" && OVN_DIR="$D" OVN_SPEC_GATE_NOW="$NOW" python3 scripts/ovn_spec_gate.py restore demo "$K05" )"
ok "restore by the full item_key puts the original line (marker stripped) back in the backlog" "printf '%s' '$rout' | grep -c 'restored 1' | grep -qx 1 && grep -qxF -- '$Q_R05' '$D/backlog/demo.md' && [ \"\$(grep -c 'spec-gate' '$D/backlog/demo.md')\" = 0 ]"
ok "... and out of the quarantine file (the other entry stays)" "[ \"\$(grep -c . '$q')\" = 1 ] && grep -c 'spec-gate:PB' '$q' | grep -qx 1"
refill "$D" 20 OVN_SPEC_GATE_ENFORCE_RULES=R05,PB >/dev/null
ok "STICKY: the restored line is now pulled even though its R05 verdict row is still fresh" "[ \"\$(paths '$prog')\" = 'a.py,' ]"
ok "restore by a 12-hex prefix works for a note-carrying (PB) marker too" "( cd '$D' && OVN_DIR='$D' python3 scripts/ovn_spec_gate.py restore demo \"\$(python3 -c \"import sys;sys.path.insert(0,'$D/scripts');import ovn_backlog_eligibility as E;print(E.line_hash(sys.argv[1]))\" '$P_PB')\" ) | grep -c 'restored 1' | grep -qx 1 && [ \"\$(grep -c . '$q')\" = 0 ]"
rc_unknown="$( cd "$D" && OVN_DIR="$D" python3 scripts/ovn_spec_gate.py restore demo 0123456789ab >/dev/null 2>&1; echo $? )"
rc_short="$( cd "$D" && OVN_DIR="$D" python3 scripts/ovn_spec_gate.py restore demo abc >/dev/null 2>&1; echo $? )"
ok "NEGATIVE: unknown key -> exit 1, key too short -> exit 2" "[ '$rc_unknown' = 1 ] && [ '$rc_short' = 2 ]"
ok "restore appended sticky 'restored' rows to the append-only marker file (never to the store the scan rewrites)" "[ \"\$(grep -c '\"restored\": true' '$D/state/spec_gate_restored.jsonl')\" = 2 ] && [ \"\$(grep -c '\"restored\": true' '$D/state/spec_gate.jsonl')\" = 0 ]"

echo "== regression: pre-existing behaviour is unchanged with no gate state at all"
D="$(fresh plain)"; prog="$D/repos/demo/OVERNIGHT_PROGRESS.md"
printf '%s\n%s\n' "$L_PLAIN" '- [ ] [T2] [AUTO-SKIP after 4] x.py — parked. VERIFY: `true`. (cat:python)' > "$D/backlog/demo.md"
out="$(refill "$D" 5)"
ok "plain pull works, the parked line stays, output fields unchanged (no extra fields)" "[ \"\$(paths '$prog')\" = 'p.txt,' ] && printf '%s' '$out' | grep -c 'REFILL=1  CREDITED=0  BACKLOG_REMAINING=0  PRUNED=0\$' | grep -qx 1 && [ ! -e '$D/backlog/quarantine' ]"

echo; echo "queue_refill gate: $P passed, $F failed"
[ "$F" = 0 ]
