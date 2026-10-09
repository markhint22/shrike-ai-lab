#!/usr/bin/env bash
# Regression test: scripts/ovn_spec_gate.py scan / lint / report (spec-compiler-v2 C3, 2026-10-09).
# A temp "live dir" (state/ backlog/ repos/<repo> with an origin/overnight/feature ref, scripts/ copied from this tree) so the gate runs exactly as it does on the box:
# ONE detached worktree of the ref through lib_worktree.sh, VERIFYs through ovn_spec_check.sh, rows in state/spec_gate.jsonl.
#   shadow (default) never touches the backlog (cmp) - mutation: a gate that writes the backlog makes the cmp assertion fail
#   second scan = memo hit (the VERIFY side effect fires once), OVN_SPEC_GATE=off writes nothing, state/PAUSED skips, a line appended while a scan runs is not lost,
#   the per-scan execution cap, and the enforcement hand-off to queue_refill (quarantine exactly the flagged line, hold R06, keep the original order of the rest).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"                 # scripts/
QR="${OVN_QUEUE_REFILL_PY:-$HERE/../../queue_refill.py}"
[ -f "$SRC/ovn_spec_gate.py" ] || { echo "  SKIP: ovn_spec_gate.py not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (under pipefail `A | grep -q X` is flaky: grep -q exits at its first hit and A may take SIGPIPE)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
GITQ=(git -c user.name=t -c user.email=t@t)

# mk <name> -> a live dir at $tmp/<name> (echoes the path)
mk(){
  local d="$tmp/$1"
  mkdir -p "$d/scripts" "$d/state" "$d/backlog" "$d/repos"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/repos/demo" 2>/dev/null
  (
    cd "$d/repos/demo" || exit 1
    "${GITQ[@]}" checkout -q -b overnight/feature
    mkdir -p app scripts/enemy tests
    : > app/__init__.py
    printf 'old here\n' > f.txt
    printf 'func get_faction(id):\n\treturn 1\nfunc get_all_factions():\n\treturn []\n' > scripts/enemy/map.gd
    printf 'func test_a():\n\tvar f = get_faction(1)\n' > tests/test_map.gd
    printf '# progress\n' > OVERNIGHT_PROGRESS.md
    git add -A && "${GITQ[@]}" commit -q -m init && git push -q origin overnight/feature
  ) >/dev/null 2>&1
  for f in lib_verify_clause.sh lib_gut_xml.sh lib_worktree.sh ovn_spec_check.sh ovn_spec_gate.py ovn_spec_rules.py ovn_spec_classify.py ovn_backlog_eligibility.py; do cp "$SRC/$f" "$d/scripts/" 2>/dev/null; done
  [ -f "$QR" ] && cp "$QR" "$d/queue_refill.py"
  printf '%s' "$d"
}
rows_n(){ [ -f "$1/state/spec_gate.jsonl" ] && wc -l < "$1/state/spec_gate.jsonl" | tr -d ' ' || echo 0; }
# pj <live dir> '<python expr over `rows`>' -> prints the value
pj(){ python3 -c "import json,sys
rows=[json.loads(l) for l in open('$1/state/spec_gate.jsonl')]
print($2)"; }
scan(){ ( cd "$1" && OVN_DIR="$1" python3 scripts/ovn_spec_gate.py scan demo ); }

MARKCMD="python3 -c \"import os;open(os.environ['MARK'],'a').write('x');assert 0\""
BL=$(cat <<EOT
# backlog
- [ ] [T2] app/a.py — Change a. VERIFY: \`$MARKCMD\`. (cat:python; multifile:no)
- [ ] [T2] app/b.py — Change b. VERIFY: \`true\`. (cat:python; multifile:no)
- [ ] [T2] addons/gut/gut.gd — Change gut. VERIFY: \`false\`. (cat:python; multifile:no)
- [ ] [T2] f.txt — Rename old. VERIFY: \`grep -q old f.txt && echo "FAIL" || echo "PASS"\`. (cat:python; multifile:no)
- [ ] [T3] scripts/enemy/map.gd — Delete func get_faction() from the map. VERIFY: \`! grep -q "func get_faction" scripts/enemy/map.gd\`. (cat:python; multifile:no) [feat:demo-20261009-map]
- [ ] [T2] tests/test_map.gd — Remove the tests that call get_faction. VERIFY: \`! grep -q get_faction tests/test_map.gd\`. (cat:python; multifile:no) [feat:demo-20261009-map]
- [ ] [T2] app/a.py — Change a again. VERIFY: \`$MARKCMD\`. (cat:python; multifile:no)
EOT
)

echo "== shadow (default): judges, never writes the backlog"
D="$(mk shadow)"
printf '%s\n' "$BL" > "$D/backlog/demo.md"; cp "$D/backlog/demo.md" "$tmp/shadow.before"
export MARK="$tmp/mark.shadow"; : > "$MARK"
out="$(scan "$D" 2>&1)"
ok "scan exits and reports (7 open, 7 judged)" "printf '%s' '$out' | grep -c '7 open, 0 fresh, 7 judged' | grep -qx 1"
ok "SHADOW: the backlog is byte-identical after a scan (cmp)" "cmp -s '$D/backlog/demo.md' '$tmp/shadow.before'"
ok "7 rows written to state/spec_gate.jsonl" "[ \"\$(rows_n '$D')\" = 7 ]"
ok "rows carry the documented fields" "[ \"\$(pj '$D' 'all(set(r)>={\"ts\",\"repo\",\"item_key\",\"feat\",\"tier\",\"path\",\"base\",\"mode\",\"exec\",\"findings\",\"repairs\",\"action\"} for r in rows)')\" = True ]"
ok "mode is recorded as shadow" "[ \"\$(pj '$D' 'set(r[\"mode\"] for r in rows)')\" = \"{'shadow'}\" ]"
ok "item_key = <12 hex>-<base7>, base7 is the ref's short sha" "[ \"\$(pj '$D' 'all(len(r[\"item_key\"].split(\"-\")[0])==12 and r[\"item_key\"].endswith(\"-\"+r[\"base\"]) and len(r[\"base\"])==7 for r in rows)')\" = True ]"
ok "L1 (red spec) exec = red/assert with an rc and ms" "[ \"\$(pj '$D' 'rows[0][\"exec\"][\"verdict\"]+\"/\"+rows[0][\"exec\"][\"sub\"]+\"/\"+str(rows[0][\"exec\"][\"rc\"])+\"/\"+str(\"ms\" in rows[0][\"exec\"])')\" = red/assert/1/True ]"
ok "L2 (VERIFY true) exec = passes-before, would-do quarantine:PB" "[ \"\$(pj '$D' 'rows[1][\"exec\"][\"verdict\"]+\"/\"+rows[1][\"action\"]')\" = passes-before/quarantine:PB ]"
ok "L3 (addons/ target) finding R04, would-do quarantine:R04" "[ \"\$(pj '$D' '[f[\"rule\"] for f in rows[2][\"findings\"]]+[rows[2][\"action\"]]')\" = \"['R04', 'quarantine:R04']\" ]"
ok "L4 (vacuous echo): R02 repair recorded, and the REPAIRED VERIFY was executed (red-before)" "[ \"\$(pj '$D' 'rows[3][\"repairs\"]+[rows[3][\"exec\"][\"verdict\"],rows[3][\"action\"]]')\" = \"['R02', 'red', 'repair:R02']\" ]"
ok "L5 (delete func with live test refs) finding R06, would-do hold:R06" "[ \"\$(pj '$D' '[f[\"rule\"] for f in rows[4][\"findings\"]]+[rows[4][\"action\"], rows[4][\"feat\"]]')\" = \"['R06', 'hold:R06', 'demo-20261009-map']\" ]"
ok "L6 (remove the tests) is clean" "[ \"\$(pj '$D' 'rows[5][\"action\"]')\" = pass ]"
ok "identical command + declared paths (L1, L7) executed ONCE: the marker file has 1 byte" "[ \"\$(wc -c < '$MARK' | tr -d ' ')\" = 1 ]"
ok "L7 shares L1's verdict" "[ \"\$(pj '$D' 'rows[6][\"exec\"][\"verdict\"]')\" = red ]"
ok "no worktree is left behind and the live clone is clean" "[ \"\$(git -C '$D/repos/demo' worktree list | wc -l | tr -d ' ')\" = 1 ] && [ -z \"\$(git -C '$D/repos/demo' status --porcelain)\" ]"

echo "== second scan is a memo hit"
before="$(rows_n "$D")"
out2="$(scan "$D" 2>&1)"
ok "memo hit reported" "printf '%s' '$out2' | grep -c 'memo hit' | grep -qx 1"
ok "no new rows" "[ \"\$(rows_n '$D')\" = '$before' ]"
ok "no re-execution (marker still 1 byte)" "[ \"\$(wc -c < '$MARK' | tr -d ' ')\" = 1 ]"
ok "backlog still byte-identical" "cmp -s '$D/backlog/demo.md' '$tmp/shadow.before'"

echo "== a new commit on the ref changes base7: verdicts are re-judged"
( cd "$D/repos/demo" && printf 'x\n' > newfile.txt && git add -A && "${GITQ[@]}" commit -q -m two && git push -q origin overnight/feature ) >/dev/null 2>&1
out3="$(scan "$D" 2>&1)"
ok "new base -> judged again (7 judged)" "printf '%s' '$out3' | grep -c '7 judged' | grep -qx 1"
ok "rows doubled and carry two distinct bases" "[ \"\$(rows_n '$D')\" = 14 ] && [ \"\$(pj '$D' 'len(set(r[\"base\"] for r in rows))')\" = 2 ]"

echo "== kill switches"
D2="$(mk off)"; printf '%s\n' "$BL" > "$D2/backlog/demo.md"
( cd "$D2" && OVN_SPEC_GATE=off OVN_DIR="$D2" python3 scripts/ovn_spec_gate.py scan demo ) > "$tmp/off.out" 2>&1
ok "OVN_SPEC_GATE=off writes nothing (no jsonl at all)" "[ ! -e '$D2/state/spec_gate.jsonl' ]"
ok "... and says so" "grep -c 'OVN_SPEC_GATE=off' '$tmp/off.out' | grep -qx 1"
touch "$D2/state/PAUSED"
out="$(scan "$D2" 2>&1)"
ok "state/PAUSED skips the scan" "[ ! -e '$D2/state/spec_gate.jsonl' ] && printf '%s' '$out' | grep -c 'paused' | grep -qx 1"
rm -f "$D2/state/PAUSED"
OVN_SPEC_GATE=enforce scan "$D2" >/dev/null 2>&1
ok "default and enforce modes judge identically; the row records the mode" "[ \"\$(rows_n '$D2')\" = 7 ] && [ \"\$(pj '$D2' 'set(r[\"mode\"] for r in rows)')\" = \"{'enforce'}\" ]"
ok "ENFORCE mode still never writes the backlog (queue_refill is the single writer)" "cmp -s '$D2/backlog/demo.md' <(printf '%s\n' \"\$BL\")"

echo "== MUTATION: a gate that writes the backlog would fail the cmp assertion"
D3="$(mk mut)"; printf '%s\n' "$BL" > "$D3/backlog/demo.md"; cp "$D3/backlog/demo.md" "$tmp/mut.before"
python3 - "$D3/scripts/ovn_spec_gate.py" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
needle = '    log("%d open, %d fresh'
assert needle in s
open(p, "w").write(s.replace(needle, '    open(backlog, "a").write("# gate wrote this\\n")\n' + needle, 1))
PYEOF
scan "$D3" >/dev/null 2>&1
ok "MUTATION caught: with the writing gate the backlog differs from the original" "! cmp -s '$D3/backlog/demo.md' '$tmp/mut.before'"

echo "== a line appended while a scan runs is not lost"
D4="$(mk append)"
SLOW="python3 -c \"import time;time.sleep(2);assert 0\""
printf '# backlog\n- [ ] [T2] app/s.py — Slow. VERIFY: `%s`. (cat:python; multifile:no)\n' "$SLOW" > "$D4/backlog/demo.md"
( scan "$D4" >/dev/null 2>&1 ) &
bgpid=$!
sleep 1
printf -- '- [ ] [T2] app/late.py — Appended mid-scan. VERIFY: `true`. (cat:python; multifile:no)\n' >> "$D4/backlog/demo.md"
wait "$bgpid"
ok "the appended line is still there after the scan finished" "grep -c 'Appended mid-scan' '$D4/backlog/demo.md' | grep -qx 1"
ok "the original line is intact and first" "[ \"\$(sed -n 2p '$D4/backlog/demo.md' | awk '{print \$5}')\" = 'app/s.py' ] && sed -n 2p '$D4/backlog/demo.md' | grep -c 'time.sleep(2)' | grep -qx 1"
ok "the first scan judged only the line it had read (1 row)" "[ \"\$(rows_n '$D4')\" = 1 ]"
scan "$D4" >/dev/null 2>&1
ok "the next scan judges the late line (2 rows)" "[ \"\$(rows_n '$D4')\" = 2 ]"

echo "== execution cap per scan"
D5="$(mk cap)"
{ echo "# backlog"; for i in 1 2 3 4 5; do printf -- '- [ ] [T2] app/m%s.py — Change m%s. VERIFY: `true`. (cat:python; multifile:no)\n' "$i" "$i"; done; } > "$D5/backlog/demo.md"
( cd "$D5" && OVN_SPEC_GATE_MAX_EXEC=2 OVN_DIR="$D5" python3 scripts/ovn_spec_gate.py scan demo ) > "$tmp/cap1.out" 2>&1
ok "OVN_SPEC_GATE_MAX_EXEC=2: first scan judges exactly 2 rows" "[ \"\$(rows_n '$D5')\" = 2 ] && grep -c '3 left' '$tmp/cap1.out' | grep -qx 1"
( cd "$D5" && OVN_SPEC_GATE_MAX_EXEC=2 OVN_DIR="$D5" python3 scripts/ovn_spec_gate.py scan demo ) >/dev/null 2>&1
( cd "$D5" && OVN_SPEC_GATE_MAX_EXEC=2 OVN_DIR="$D5" python3 scripts/ovn_spec_gate.py scan demo ) >/dev/null 2>&1
ok "the next scans take the next lines in file order until all 5 are judged, none twice" "[ \"\$(rows_n '$D5')\" = 5 ] && [ \"\$(pj '$D5' 'len(set(r[\"item_key\"] for r in rows))')\" = 5 ] && [ \"\$(pj '$D5' '[r[\"path\"] for r in rows]')\" = \"['app/m1.py', 'app/m2.py', 'app/m3.py', 'app/m4.py', 'app/m5.py']\" ]"

echo "== enforcement hand-off: queue_refill quarantines exactly the flagged line, holds R06, keeps order"
if [ -f "$D/queue_refill.py" ]; then
  : > "$MARK"
  # fresh live dir so the clock/base match the rows just written
  E1="$(mk enforce)"; printf '%s\n' "$BL" > "$E1/backlog/demo.md"
  scan "$E1" >/dev/null 2>&1
  cp "$E1/backlog/demo.md" "$tmp/enf.before"
  outq="$( cd "$E1" && OVN_INGEST_BAN_FILTER=off OVN_SPEC_GATE_ENFORCE_RULES=R04,R06 python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md 20 )"
  ok "refill output counts the quarantined and held lines" "printf '%s' '$outq' | grep -c 'QUARANTINED=1' | grep -qx 1 && printf '%s' '$outq' | grep -c 'HELD=1' | grep -qx 1"
  ok "quarantine file holds exactly the R04 line with a spec-gate marker (never an AUTO-SKIP tag)" "[ \"\$(grep -c . '$E1/backlog/quarantine/demo.md')\" = 1 ] && grep -c 'addons/gut/gut.gd' '$E1/backlog/quarantine/demo.md' | grep -qx 1 && grep -c '<!-- spec-gate:R04 ' '$E1/backlog/quarantine/demo.md' | grep -qx 1 && [ \"\$(grep -c 'AUTO-SKIP' '$E1/backlog/quarantine/demo.md')\" = 0 ]"
  ok "the held R06 line stays in the backlog (and only it)" "[ \"\$(grep -c '^- \\[ \\]' '$E1/backlog/demo.md')\" = 1 ] && grep -c 'Delete func get_faction' '$E1/backlog/demo.md' | grep -qx 1"
  pulled="$(grep '^- \[ \] \[T' "$E1/repos/demo/OVERNIGHT_PROGRESS.md" | awk '{print $5}' | tr '\n' ',')"
  ok "the other 5 lines were pulled in their ORIGINAL order (a.py, b.py, f.txt, test_map.gd, a.py)" "[ '$pulled' = 'app/a.py,app/b.py,f.txt,tests/test_map.gd,app/a.py,' ]"
  ok "the R04 line is not in the queue" "[ \"\$(grep -c 'addons/gut' '$E1/repos/demo/OVERNIGHT_PROGRESS.md')\" = 0 ]"
  # a rule that is NOT in the list is not enforced: with an empty list nothing is quarantined or held
  E2="$(mk noenforce)"; printf '%s\n' "$BL" > "$E2/backlog/demo.md"; scan "$E2" >/dev/null 2>&1
  ( cd "$E2" && OVN_INGEST_BAN_FILTER=off python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md 20 ) >/dev/null
  ok "empty OVN_SPEC_GATE_ENFORCE_RULES: all 7 lines pulled, no quarantine dir" "[ \"\$(grep -c '^- \\[ \\] \\[T' '$E2/repos/demo/OVERNIGHT_PROGRESS.md')\" = 7 ] && [ ! -e '$E2/backlog/quarantine' ]"
else
  echo "  SKIP: queue_refill.py not found"
fi

echo "== lint (stdin -> stdout)"
FIXME_IN="$(printf -- '- [ ] [T2] a.py — x. VERIFY: pytest tests/test_a.py -q. (cat:python)\n- [ ] [T2] f.txt — y. VERIFY: `grep -q old f.txt && echo "FAIL" || echo "PASS"`. (cat:python)\nnot an item line\n')"
lint(){ printf '%s\n' "$FIXME_IN" | ( cd "$tmp" && OVN_DIR="$D" python3 "$D/scripts/ovn_spec_gate.py" lint repos/demo ) 2>"$tmp/lint.err"; }
out_default="$(lint)"
ok "default (nothing enforced): stdin echoed unchanged, the would-repair counts go to stderr" "[ \"\$out_default\" = \"\$FIXME_IN\" ] && grep -c 'shadow, nothing rewritten' '$tmp/lint.err' | grep -qx 1 && grep -c 'R01=1' '$tmp/lint.err' | grep -qx 1"
out_r1="$(OVN_SPEC_GATE_ENFORCE_RULES=R01 lint)"
ok "R01 enforced: the bare VERIFY is backticked, the vacuous line and the prose line untouched" "printf '%s' '$out_r1' | grep -c 'VERIFY: .pytest tests/test_a.py -q. (cat' | grep -qx 1 && printf '%s' '$out_r1' | grep -c 'echo \"FAIL\" || echo \"PASS\"' | grep -qx 1 && printf '%s' '$out_r1' | grep -c '^not an item line' | grep -qx 1"
out_r12="$(OVN_SPEC_GATE_ENFORCE_RULES=R01,R02 lint)"
ok "R01+R02 enforced: both repaired" "printf '%s' '$out_r12' | grep -c '! ( grep -q old f.txt )' | grep -qx 1 && printf '%s' '$out_r12' | grep -c 'VERIFY: .pytest' | grep -qx 1"
out_off="$(OVN_SPEC_GATE=off OVN_SPEC_GATE_ENFORCE_RULES=R01,R02 lint)"
ok "OVN_SPEC_GATE=off: echoed unchanged even with rules enforced" "[ \"\$out_off\" = \"\$FIXME_IN\" ]"
# crash safety: a rules module that raises must echo the input
CR="$tmp/crash"; mkdir -p "$CR"; cp "$D"/scripts/ovn_spec_gate.py "$D"/scripts/ovn_backlog_eligibility.py "$D"/scripts/ovn_spec_classify.py "$CR/"
printf 'def lint_static(*a, **k):\n    raise RuntimeError("boom")\nclass Ctx: pass\ndef lint_batch(*a, **k):\n    raise RuntimeError("boom")\ndef parse(*a): return None\n' > "$CR/ovn_spec_rules.py"
out_crash="$(printf '%s\n' "$FIXME_IN" | OVN_SPEC_GATE_ENFORCE_RULES=R01,R02 python3 "$CR/ovn_spec_gate.py" lint repos/demo 2>/dev/null)"
ok "a crash inside lint echoes stdin unchanged" "[ \"\$out_crash\" = \"\$FIXME_IN\" ]"
rm -f "$CR/ovn_spec_rules.py"
out_imp="$(printf '%s\n' "$FIXME_IN" | OVN_SPEC_GATE_ENFORCE_RULES=R01,R02 python3 "$CR/ovn_spec_gate.py" lint repos/demo 2>/dev/null)"
ok "a missing sibling module (import failure) also echoes stdin unchanged" "[ \"\$out_imp\" = \"\$FIXME_IN\" ]"

echo "== report"
rep="$( cd "$D" && OVN_DIR="$D" python3 scripts/ovn_spec_gate.py report )"
ok "report summarises rows, verdicts and per-rule findings" "printf '%s' '$rep' | grep -c 'judged rows' | grep -qx 1 && printf '%s' '$rep' | grep -c 'rule R04' | grep -qx 1 && printf '%s' '$rep' | grep -c 'repair R02' | grep -qx 1"

echo "== spec_gate.jsonl rotation and the enforce-without-rules warning (review defect)"
# cnt <live dir> <python predicate over r> -> number of rows matching
cnt(){ python3 -c "import json
rows=[json.loads(l) for l in open('$1/state/spec_gate.jsonl')]
print(sum(1 for r in rows if $2))"; }
D6="$(mk rot)"
{ echo "# backlog"; printf -- '- [ ] [T2] app/r1.py — Change r1. VERIFY: `true`. (cat:python; multifile:no)\n'; } > "$D6/backlog/demo.md"
python3 - "$D6/state/spec_gate.jsonl" <<'PYEOF'
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
def ts(d): return (now - datetime.timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")
rows = [{"ts": ts(30), "repo": "demo", "item_key": "old%09d-aaaaaaa" % i, "action": "pass", "findings": [], "exec": None} for i in range(40)]
rows += [{"ts": ts(30), "repo": "demo", "item_key": "abcdef123456", "restored": True, "action": "restored", "findings": [], "exec": None}]
rows += [{"ts": ts(1), "repo": "demo", "item_key": "new%09d-bbbbbbb" % i, "action": "pass", "findings": [], "exec": None} for i in range(6)]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows) + "garbage not json\n")
PYEOF
out="$(scan "$D6" 2>&1)"
ok "scan rotates: the 40 rows older than 7 days and the unparseable line are dropped" "printf '%s' '$out' | grep -c 'dropped 41 old row' | grep -qx 1"
ok "recent rows (6) + the sticky restored marker + this scan's 1 new row = 8 remain" "[ \"\$(rows_n '$D6')\" = 8 ]"
ok "the restored marker survived (older than the retention, still kept)" "[ \"\$(cnt '$D6' 'r.get(\"restored\")')\" = 1 ]"
ok "no old row remains" "[ \"\$(cnt '$D6' 'str(r[\"item_key\"]).startswith(\"old\")')\" = 0 ]"
printf -- '- [ ] [T2] app/r2.py — Change r2. VERIFY: `true`. (cat:python; multifile:no)\n' >> "$D6/backlog/demo.md"
( cd "$D6" && OVN_SPEC_GATE_MAX_ROWS=3 OVN_DIR="$D6" python3 scripts/ovn_spec_gate.py scan demo ) >/dev/null 2>&1
ok "OVN_SPEC_GATE_MAX_ROWS=3: rotation keeps the 3 newest non-restored rows, then this scan's 1 new row is added" "[ \"\$(cnt '$D6' 'not r.get(\"restored\")')\" = 4 ] && [ \"\$(cnt '$D6' 'r.get(\"restored\")')\" = 1 ]"
D7="$(mk norot)"; printf '%s\n' "$BL" > "$D7/backlog/demo.md"; scan "$D7" >/dev/null 2>&1
ok "no rotation when nothing is old (7 fresh rows kept)" "[ \"\$(rows_n '$D7')\" = 7 ]"
D8="$(mk warn)"; printf '%s\n' "$BL" > "$D8/backlog/demo.md"
( cd "$D8" && OVN_SPEC_GATE=enforce OVN_DIR="$D8" python3 scripts/ovn_spec_gate.py scan demo ) > "$tmp/warn.out" 2>&1
ok "OVN_SPEC_GATE=enforce with an empty rule list warns on stderr that nothing is enforced" "grep -c 'enforces NOTHING' '$tmp/warn.out' | grep -qx 1"
( cd "$D8" && OVN_SPEC_GATE=enforce OVN_SPEC_GATE_ENFORCE_RULES=R04 OVN_DIR="$D8" python3 scripts/ovn_spec_gate.py report ) > "$tmp/warn2.out" 2>&1
ok "NEGATIVE: no warning once a rule is armed" "[ \"\$(grep -c 'enforces NOTHING' '$tmp/warn2.out')\" = 0 ]"
( cd "$D8" && OVN_DIR="$D8" python3 scripts/ovn_spec_gate.py report ) > "$tmp/warn3.out" 2>&1
ok "NEGATIVE: no warning in the default shadow mode" "[ \"\$(grep -c 'enforces NOTHING' '$tmp/warn3.out')\" = 0 ]"

echo "== restore vs the scan's rotation: a restored marker can never be lost (review defect: restore appended to the store without the scan's lock)"
D9="$(mk race)"; printf -- '- [ ] [T2] app/r1.py — Change r1. VERIFY: `true`. (cat:python; multifile:no)\n' > "$D9/backlog/demo.md"
RACE_LINE='- [ ] [T2] app/q1.py — Quarantined q1. VERIFY: `true`. (cat:python; multifile:no)'
mkdir -p "$D9/backlog/quarantine"; printf '%s <!-- spec-gate:R05 -->\n' "$RACE_LINE" > "$D9/backlog/quarantine/demo.md"
cat > "$tmp/race.py" <<'PYEOF'
import datetime, json, os, sys
d, src, line = sys.argv[1:4]
sys.path.insert(0, src)
os.environ["OVN_DIR"] = d
import ovn_backlog_eligibility as E
import ovn_spec_gate as G
store = os.path.join(d, "state", "spec_gate.jsonl")
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
old = (now - datetime.timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
open(store, "w").write("".join(json.dumps({"ts": old, "repo": "demo", "item_key": "old%09d-aaaaaaa" % i, "findings": [], "exec": None}) + "\n" for i in range(5)))
real, fired = os.replace, []
def hook(a, b, *k, **kw):                      # the exact interleaving: the operator's restore lands AFTER rotate_store read the file and BEFORE it replaces it
    if b == store and not fired:
        fired.append(1)
        G.restore("demo", E.line_hash(line))
    return real(a, b, *k, **kw)
os.replace = hook
n = G.rotate_store(store, now)
os.replace = real
print("ROTATED=%d FIRED=%d" % (n, len(fired)))
print("MARKER_KEPT=%s" % (E.line_hash(line) in G.restored_prefixes(d)))
PYEOF
RACE_OUT="$(python3 "$tmp/race.py" "$D9" "$SRC" "$RACE_LINE" 2>&1)"     # (heredoc kept OUT of the $( ): bash 3.2 cannot parse a quote inside a heredoc inside a command substitution)
ok "setup: the rotation really rewrote the store and the restore ran inside its read-to-replace window" "printf '%s' '$RACE_OUT' | grep -c 'ROTATED=5 FIRED=1' | grep -qx 1"
ok "the restored marker survives the rotation that raced with it" "printf '%s' '$RACE_OUT' | grep -c 'MARKER_KEPT=True' | grep -qx 1"
printf '%s\n' "$RACE_LINE" >> "$D9/backlog/demo.md"
scan "$D9" >/dev/null 2>&1
ok "the next scan does not re-judge the line the operator restored (no verdict row for it) but still judges the other line" "[ \"\$(python3 -c \"import sys,json;sys.path.insert(0,'$SRC');import ovn_backlog_eligibility as E;h=E.line_hash(sys.argv[1]);print(sum(1 for l in open('$D9/state/spec_gate.jsonl') if json.loads(l).get('item_key','').startswith(h)))\" '$RACE_LINE')\" = 0 ] && [ \"\$(cnt '$D9' 'r.get(\"path\") == \"app/r1.py\"')\" = 1 ]"
ok "restore wrote the marker to its own append-only file; the store holds none" "[ \"\$(grep -c '\"restored\": true' '$D9/state/spec_gate_restored.jsonl')\" = 1 ] && [ \"\$(cnt '$D9' 'r.get(\"restored\")')\" = 0 ]"
# legacy: a marker an earlier version wrote INTO the store is still honoured and still kept by rotation
D10="$(mk legacy)"; printf '%s\n' "$RACE_LINE" > "$D10/backlog/demo.md"
python3 -c "import sys,json;sys.path.insert(0,'$SRC');import ovn_backlog_eligibility as E;print(json.dumps({'ts':'2020-01-01T00:00:00Z','repo':'demo','item_key':E.line_hash(sys.argv[1]),'restored':True,'findings':[],'exec':None,'action':'restored'}))" "$RACE_LINE" > "$D10/state/spec_gate.jsonl"
scan "$D10" >/dev/null 2>&1
ok "legacy 'restored' row in the store: honoured by the scan (line not judged) and kept" "[ \"\$(cnt '$D10' 'not r.get(\"restored\")')\" = 0 ] && [ \"\$(cnt '$D10' 'r.get(\"restored\")')\" = 1 ]"

echo; echo "spec gate scan: $P passed, $F failed"
[ "$F" = 0 ]
