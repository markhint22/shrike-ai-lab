#!/usr/bin/env bash
# 2026-10-11 (r11 acct, iptv F7): a push whose commits touch ONLY OVERNIGHT_PROGRESS.md / OVERNIGHT_DONE.md is class `credit-only` (neutral), not `landed`.
# Live defect replayed (iptv_apps 10-11 01:29Z, cycle 20261010-202620): two 'aider attempt verdict: no-edit-unfenced', then the implement-pass already-satisfied credit committed ONLY
# OVERNIGHT_PROGRESS.md; the push was recorded class=landed severity=good status=pushed(tests:pass) - a TRUE credit, zero code, counted as a landing (and as a phantom 'landed with no commit' in the QA ledger).
# Sections: A ovn_cycle_credit_only (the REAL function extracted from run_overnight.sh, real git repo), B record_outcome (REAL function) class/severity, C the readers (buckets, work_summary,
# ovn_notify hourly line + stall activity, qa_ledger, cycle_notify oc), D wiring greps, E MUTATION controls (each fix reverted -> the matching assertion must fail).
set -uo pipefail
unset OVN_CREDIT_ONLY OVN_LANDED_UNCREDITED OVN_NOTIFY_LANDED_CLASSES OVN_OUTCOME_ATTRIB OVN_SKIP_ROW_DEDUPE   # hermetic: kill switches set by a caller must not change what this asserts
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; R="$Q/run_overnight.sh"
[ -f "$R" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

echo "== A: ovn_cycle_credit_only (unit)"
FN="$(sed -n '/^ovn_cycle_credit_only() {/,/^}/p' "$R")"
[ -n "$FN" ] || { echo "  FAIL: ovn_cycle_credit_only() is not defined in run_overnight.sh (the defect: no such classification existed)"; exit 1; }
eval "$FN"
G="$tmp/g"; mkdir -p "$G"; cd "$G" || exit 1; git init -q -b main . 2>/dev/null || git init -q .
printf 'import os\nx = os.getenv("A")\n' > svc.py; printf '# prog\n- [ ] [T1] svc.py - do it\n' > OVERNIGHT_PROGRESS.md; printf '# done\n' > OVERNIGHT_DONE.md; mkdir -p sub
git add -A; git commit -q -m seed; B0="$(git rev-parse HEAD)"
br(){ git checkout -q main; git checkout -q -b "$1"; }
tick(){ sed -i.bak 's/\[ \] \[T1\]/[x] [T1]/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak; }
br c1; tick; git commit -q -am "chore(queue): credit item(s) the implement pass found already satisfied in code"
ok "A1 the 10-11 shape: one progress-file-only credit commit => credit-only" "ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c2; tick; printf '# done\n- x\n' > OVERNIGHT_DONE.md; git commit -q -am "credit + done"
ok "A2 progress + done file only => credit-only" "ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c3; tick; git commit -q -am credit; printf 'x = 2\n' > svc.py; git commit -q -am "real code"
ok "A3 a credit AND a real code change => NOT credit-only (a landing)" "! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c4; printf 'x = 2\n' > svc.py; git commit -q -am "real code only"
ok "A4 code only => NOT credit-only" "! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c5; printf 'x = 1\n' > svc.py; git commit -q -am rm; printf 'import os\nx = os.getenv("A")\n' > svc.py; git commit -q -am readd; tick; git commit -q -am credit
ok "A5 code churn that cancels out + a credit => credit-only (net diff is bookkeeping only)" "ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c6; git commit -q --allow-empty -m e1; git commit -q --allow-empty -m e2
ok "A6 empty commits only (empty net diff) => NOT credit-only (nothing credited; lands as before)" "! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
ok "A7 same sha / empty args => NOT credit-only" "! ovn_cycle_credit_only $B0 $B0 && ! ovn_cycle_credit_only '' '' && ! ovn_cycle_credit_only $B0 ''"
br c8; printf '# p\n' > sub/OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m "nested progress file"
ok "A8 a progress file in a SUBDIRECTORY is a real file change => NOT credit-only" "! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
ok "A9 unknown sha (git error) => NOT credit-only" "! ovn_cycle_credit_only $B0 0123456789abcdef0123456789abcdef01234567"
br c10; tick; git commit -q -am credit
ok "A10 kill switch OVN_CREDIT_ONLY=off => NOT credit-only (old behaviour: lands)" "! OVN_CREDIT_ONLY=off ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
br c11; git mv svc.py svc2.py; git commit -q -m "rename"
ok "A11 a rename is a code change => NOT credit-only" "! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"
cd "$HERE" || exit 1

echo "== B: record_outcome (REAL function) class / severity"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$R")"; [ -n "$FN_SRC" ] || { echo "  FAIL: could not extract record_outcome()"; exit 1; }
eval "$FN_SRC"
# shellcheck disable=SC1091
source "$Q/scripts/lib_auto_credit.sh" 2>/dev/null
SCRIPT_DIR="$Q"; STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"
row(){  # $1=status $2=log -> "class|severity"
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "id1" repo "$1" "" aider_fix 1 "${2:-/nonexistent}" 5 "" "" 2>/dev/null
  jq -r '.class + "|" + .severity' "$STATE_DIR/outcomes.jsonl" 2>/dev/null | head -1
}
printf '%s\n' 'aider noise' '--- landing: bookkeeping + auto-credit + push phase ---' '--- auto-credit: REFUSED line 12 (a.py) - item has no VERIFY: clause, so there is nothing to prove it is done ---' > "$tmp/refused.log"
ok "B1 'pushed(tests:pass) [credit-only]' => credit-only|neutral (was landed|good)" "[ \"\$(row 'pushed(tests:pass) [credit-only]')\" = 'credit-only|neutral' ]"
ok "B2 plain 'pushed(tests:pass)' stays landed|good (control)" "[ \"\$(row 'pushed(tests:pass)')\" = 'landed|good' ]"
ok "B3 'pushed(after-rebase) [credit-only]' => credit-only|neutral" "[ \"\$(row 'pushed(after-rebase) [credit-only]')\" = 'credit-only|neutral' ]"
ok "B4 'pushed(tests:FAIL - see log) [credit-only]' => credit-only|neutral (no code was pushed either way)" "[ \"\$(row 'pushed(tests:FAIL - see log) [credit-only]')\" = 'credit-only|neutral' ]"
ok "B5 credit-only wins over landed-uncredited (a refusal line in the log, but no code at all)" "[ \"\$(row 'pushed(tests:pass) [credit-only]' '$tmp/refused.log')\" = 'credit-only|neutral' ] && [ \"\$(row 'pushed(tests:pass)' '$tmp/refused.log')\" = 'landed-uncredited|neutral' ]"
ok "B6 kill switch OVN_CREDIT_ONLY=off => landed|good (old behaviour)" "[ \"\$(OVN_CREDIT_ONLY=off row 'pushed(tests:pass) [credit-only]')\" = 'landed|good' ]"
ok "B7 the tag never rescues a failure: reverted(...) [credit-only] is still reverted|bad" "[ \"\$(row 'reverted(tests-failed) [credit-only]')\" = 'reverted|bad' ]"
ok "B8 the status field keeps the tag (<= 80 chars cut) so the row is auditable" "row 'pushed(tests:pass) [credit-only]' >/dev/null; jq -e '.status==\"pushed(tests:pass) [credit-only]\"' '$STATE_DIR/outcomes.jsonl'"

echo "== C: readers"
B="$Q/scripts"
bk(){ "$PY" -c "
import sys
sys.path.insert(0, '$B')
import ovn_outcome_buckets as b
$1"; }
ok "C1 bucket_from_outcome_row: credit-only (neutral) => benign" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'credit-only','severity':'neutral'}))\")\" = benign ]"
ok "C2 ... stays benign even with a stale severity=good, and with no severity at all" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'credit-only','severity':'good'}), b.bucket_from_outcome_row({'class':'credit-only'}))\")\" = 'benign benign' ]"
ok "C3 pass rate excludes credit-only: 1 good + 1 bad + 5 credit-only => 50.0 (before: 6 good/1 bad)" "[ \"\$(bk \"rows=[{'class':'landed','severity':'good'},{'class':'reverted','severity':'bad'}]+[{'class':'credit-only','severity':'neutral'}]*5; print(b.pass_rate([b.bucket_from_outcome_row(r) for r in rows]))\")\" = 50.0 ]"
ok "C4 bucket('credit-only') (task_stats oc column) => benign, and it is in BENIGN / oc_benign_breakdown" "[ \"\$(bk \"print(b.bucket('credit-only'), 'credit-only' in b.BENIGN, b.oc_benign_breakdown(['pass','credit-only','credit-only']))\")\" = \"benign True {'credit-only': 2}\" ]"
ok "C5 oc_pass_rate ignores credit-only: pass,pass,revert,credit-only x4 => 66.7" "[ \"\$(bk \"print(b.oc_pass_rate(['pass','pass','revert']+['credit-only']*4))\")\" = 66.7 ]"
ok "C6 is_credit_only / count_credit_only / credit_only_label" "[ \"\$(bk \"r=[{'class':'credit-only'}]*3+[{'class':'landed'}]; print(b.count_credit_only(r), repr(b.credit_only_label(0)), b.credit_only_label(3), b.is_credit_only({'class':'landed'}))\")\" = \"3 '' 3 credit-only False\" ]"
ok "C7 the net-zero class is unchanged and still BAD (consistency): noop|bad net-zero row" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'noop','status':'no-op(net-zero)','severity':'bad'}))\")\" = bad ]"

NOW="$(date -u +%FT%TZ)"
{ for c in landed landed credit-only credit-only credit-only reverted; do printf '{"ts":"%s","repo":"iptv_apps","class":"%s","tier":"2"}\n' "$NOW" "$c"; done; } > "$tmp/outcomes_ws.jsonl"
WS="$(cd "$tmp" && OUTCOMES="$tmp/outcomes_ws.jsonl" OVN_LANDED_DETAIL_SCRIPT=/nonexistent "$PY" "$Q/work_summary.py" 24)"
ok "C8 work_summary: headline counts only the 2 real landings and appends '3 credit-only'" "case \"\$WS\" in *'2 landed · 1 reverted'*'3 credit-only'*) true;; *) false;; esac"
printf '{"ts":"%s","repo":"iptv_apps","class":"landed","tier":"2"}\n' "$NOW" > "$tmp/outcomes_ws0.jsonl"
WS0="$(cd "$tmp" && OUTCOMES="$tmp/outcomes_ws0.jsonl" OVN_LANDED_DETAIL_SCRIPT=/nonexistent "$PY" "$Q/work_summary.py" 24)"
ok "C9 work_summary: no credit-only rows => no 'credit-only' text (control)" "case \"\$WS0\" in *credit-only*) false;; *) true;; esac"

# ovn_notify: hourly line + stall activity
cat > "$tmp/notify_check.py" <<'PYEOF'
import importlib.util, json, os, sys, tempfile, time
root = sys.argv[1]
T = tempfile.mkdtemp()
os.environ.update(OVN_NOTIFY_STATE=os.path.join(T, "state"), NTFY_TOPIC="t_test", OVN_NOTIFY_UPSTREAM="http://127.0.0.1:9")
os.makedirs(os.environ["OVN_NOTIFY_STATE"])
spec = importlib.util.spec_from_file_location("ovn_notify", os.path.join(root, "scripts", "ovn_notify.py")); N = importlib.util.module_from_spec(spec); spec.loader.exec_module(N)
ST = os.environ["OVN_NOTIFY_STATE"]
now = time.time()
iso = lambda e: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))
def put(rows):
    open(os.path.join(ST, "outcomes.jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
co = lambda repo, age=300: {"ts": iso(now - age), "repo": repo, "class": "credit-only", "severity": "neutral"}
ld = lambda repo, age=300: {"ts": iso(now - age), "repo": repo, "class": "landed", "severity": "good"}
res = {}
put([ld("gitlark"), ld("gitlark", 200), co("iptv_apps"), co("iptv_apps", 100)])
_, b, _ = N.compose_update(at=now)
res["head"] = "Landed 2: gitlark 2 (+2 credit-only)" in b
put([co("iptv_apps"), co("iptv_apps", 100), co("iptv_apps", 50)])
_, b, _ = N.compose_update(at=now)
res["only"] = "Nothing credited this hour (+3 credit-only)" in b and "Nothing landed this hour" not in b
res["rate"] = "last hour 0/0 (-)" in b
put([])
_, b, _ = N.compose_update(at=now)
res["empty"] = "Nothing landed this hour" in b and "credit-only" not in b
res["activity"] = "credit-only" not in N.LANDED and "landed" in N.LANDED and "landed-uncredited" in N.LANDED
print(json.dumps(res))
PYEOF
NR="$("$PY" "$tmp/notify_check.py" "$Q" 2>/dev/null | tail -1)"
ok "C10 ovn_notify hourly: '(+2 credit-only)' next to the credited count, never inside it" "printf '%s' '$NR' | jq -e '.head'"
ok "C11 ovn_notify hourly: a credit-only-only window says 'Nothing credited' and leaves the pass rate empty" "printf '%s' '$NR' | jq -e '.only and .rate'"
ok "C12 ovn_notify hourly: an empty window is still 'Nothing landed this hour' (control)" "printf '%s' '$NR' | jq -e '.empty'"
ok "C13 ovn_notify stall activity: credit-only is NOT activity by default (no code pushed must not mask 'Fleet stalled'); env opt-in documented" "printf '%s' '$NR' | jq -e '.activity' && grep -q 'is NOT activity for the stall emergency' '$B/ovn_notify.py' && grep -q 'OVN_NOTIFY_LANDED_CLASSES=landed,landed-uncredited,credit-only' '$B/ovn_notify.py'"

# qa_ledger: the ledger ignores credit-only rows but counts them
cat > "$tmp/ledger_check.py" <<'PYEOF'
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "qa"))
import qa_ledger as q
assert not q.is_landed({"class": "credit-only", "repo": "r", "status": "pushed(tests:pass) [credit-only]"}), "credit-only must not be a ledger landing"
assert q.is_landed({"class": "landed", "repo": "r", "status": "pushed(tests:pass)"})
st = {}
rows = [{"class": "credit-only", "repo": "r", "ts": "2026-10-11T01:29:19Z", "status": "pushed(tests:pass) [credit-only]", "id": "a"},
        {"class": "credit-only", "repo": "r", "ts": "2026-10-11T01:39:19Z", "status": "pushed(tests:pass) [credit-only]", "id": "b"}]
recs, _prev = q.derive_records(rows, set(), set(), st)
print(json.dumps({"recs": len(recs), "credit_only": st.get("credit_only", 0)}))
PYEOF
LR="$(OVN_DIR="$tmp/ovnled" "$PY" "$tmp/ledger_check.py" "$Q" 2>/dev/null | tail -1)"
ok "C14 qa_ledger: credit-only rows are not ledger landings (0 records) and are counted (stats credit_only=2)" "printf '%s' '$LR' | jq -e '.recs==0 and .credit_only==2'"

# cycle_notify: the report status maps to oc credit-only (task_stats.log), not pass
CN="$tmp/cn"; mkdir -p "$CN/state" "$CN/logs"; cp "$Q/cycle_notify.sh" "$CN/cycle_notify.sh"
printf 'ts\n' > /dev/null
printf '%s\n' '| ongoing-iptv-apps | aider_fix | pushed(tests:pass) [credit-only] | overnight/feature | /tmp/x.log | 90s |' > "$CN/report.md"
printf '%s\n' 'x ongoing-iptv-apps class={python.endpoint.T2.verified} top_item=app/x.py' > "$CN/state/cycle_summary.log"
bash "$CN/cycle_notify.sh" "$CN/report.md" >/dev/null 2>&1
ok "C15 cycle_notify: task_stats.log oc column is 'credit-only' (benign), not 'pass'" "[ \"\$(cut -f3 '$CN/state/task_stats.log' | tail -1)\" = credit-only ]"
printf '%s\n' '| ongoing-iptv-apps | aider_fix | pushed(tests:pass) | overnight/feature | /tmp/x.log | 90s |' > "$CN/report2.md"
printf '%s\n' 'x ongoing-iptv-apps class={python.endpoint.T2.verified} top_item=app/y.py' >> "$CN/state/cycle_summary.log"
bash "$CN/cycle_notify.sh" "$CN/report2.md" >/dev/null 2>&1
ok "C16 cycle_notify: a normal green push is still oc 'pass' (control)" "[ \"\$(cut -f3 '$CN/state/task_stats.log' | tail -1)\" = pass ]"

echo "== D: wiring in run_overnight.sh"
ok "D1 the push status is tagged right after the base status via ovn_cycle_credit_only (exactly once in the main path)" "[ \"\$(grep -c '^        ovn_cycle_credit_only \"\$BEFORE_SHA\" \"\$AFTER_SHA\" && PUSH_STATUS=\"\${PUSH_STATUS} \[credit-only\]\"' '$R')\" = 1 ]"
ok "D2 the after-rebase push path tags too" "grep -q 'ovn_cycle_credit_only \"\$BEFORE_SHA\" \"\$AFTER_SHA\" && { echo \"pushed(after-rebase) \[credit-only\]\"; return; }' '$R'"
ok "D3 record_outcome maps the tag before the landed-uncredited check" "[ \"\$(grep -n 'cls=\"credit-only\"; sev=neutral' '$R' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'cls=\"landed-uncredited\"; sev=neutral' '$R' | head -1 | cut -d: -f1)\" ]"

echo "== E: MUTATION controls"
"$PY" - "$R" "$tmp" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, name):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + name, "w").write(s.replace(a, b))
mut('    case "$f" in OVERNIGHT_PROGRESS.md|OVERNIGHT_DONE.md) ;; *) return 1 ;; esac', '    case "$f" in *) ;; esac', "m_anyfile.sh")
mut('  [ -n "$files" ] || return 1\n', '', "m_empty.sh")
mut('case "$3" in *"[credit-only]"*) cls="credit-only"; sev=neutral;; esac', 'case "$3" in *"[credit-only]"*) :;; esac', "m_nomap.sh")
PYEOF
getfn(){ sed -n "/^$2() {/,/^}/p" "$1"; }
ok "E1 MUTATION: without the file check a code push is misclassified credit-only" "( eval \"\$(getfn '$tmp/m_anyfile.sh' ovn_cycle_credit_only)\"; cd '$G' && git checkout -q c4 && ovn_cycle_credit_only $B0 \$(git rev-parse HEAD) )"
ok "E2 MUTATION: without the empty-diff check empty commits are misclassified credit-only" "( eval \"\$(getfn '$tmp/m_empty.sh' ovn_cycle_credit_only)\"; cd '$G' && git checkout -q c6 && ovn_cycle_credit_only $B0 \$(git rev-parse HEAD) )"
ok "E3 MUTATION: without the record_outcome mapping the tagged push is still landed|good (the old behaviour)" "( eval \"\$(sed -n '/^record_outcome(/,/^}/p' '$tmp/m_nomap.sh')\"; : > '$STATE_DIR/outcomes.jsonl'; record_outcome id1 repo 'pushed(tests:pass) [credit-only]' '' aider_fix 1 /nonexistent 5 '' '' 2>/dev/null; [ \"\$(jq -r '.class' '$STATE_DIR/outcomes.jsonl')\" = landed ] )"
ok "E4 MUTATION sanity: the unmutated function gets c4 (code) and c6 (empty) right" "cd '$G' && git checkout -q c4 && ! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD) && git checkout -q c6 && ! ovn_cycle_credit_only $B0 \$(git rev-parse HEAD)"

echo "credit-only class: $P passed, $F failed"; [ "$F" -eq 0 ]
