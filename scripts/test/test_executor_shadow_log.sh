#!/usr/bin/env bash
# 2026-10-10 (package docexec; analysis[6] BX-01 + analysis[0] F4): the deterministic doc/ruff executors become OBSERVABLE and switchable.
# Root cause reproduced first (scratch clone, real hook): the hook DID write '--- DOC-EXECUTOR (shadow): would apply ---' into the cycle's task log, and the scout's
# `> "$task_log"` (truncate) erased it later in the same cycle; lanes with no doable item (every doc gap parked after credit refusals) returned skip(exhausted) before the block.
# Covered here (lib level; the runner wiring end to end is test_docexec_wiring.sh):
#   persistent executor_shadow.log rows for every verdict (would-apply / skip / applied / fail), surviving a task-log truncation, bounded size, kill switches;
#   mode resolution env > state/executor_mode (kind:repo beats kind) > shadow, bash == python ctl == supply collector;
#   a model/endpoint outage is NOT remembered as an exec_failed marker;
#   ovn_doc_reroute_item (parked credit-refusal doc gaps are offered only in ON mode); ovn_doc_postcheck_gate shadow / enforce / off;
#   mutation controls. Real git repos, stub executor, no network, no model.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)" || exit 1; trap 'rm -rf "$W"' EXIT
W="$(cd "$W" && pwd -P)"
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
emit_alert(){ :; }
run_repo_verification(){ echo "${STUB_VERIFY:-pass}"; }
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_verify_clause.sh"; . "$S/lib_fixup.sh"
SCRIPT_DIR=; unset SCRIPT_DIR   # the postcheck gate locates the ovn dir (its executor_shadow.log) from SCRIPT_DIR: pinned to the temp dir below
unset OVN_DOC_EXECUTOR OVN_RUFF_EXECUTOR OVN_EXECUTOR_LOG OVN_EXECUTOR_LOG_OFF OVN_DOC_POSTCHECK OVN_DOC_REROUTE OVN_DOC_REROUTE_ERE

OD="$W/ovn"; mkdir -p "$OD/scripts" "$OD/state"
SCRIPT_DIR="$OD"
LOG="$OD/state/executor_shadow.log"
cat > "$OD/scripts/ovn_doc_executor.py" <<'EOP'
# stub doc executor: check OK for 'DOCITEM' items (SKIP 'not my item' otherwise; 'SKIPME' items SKIP 'annotated'); apply per STUB_APPLY; every call is appended to $STUB_CALLS
import os, sys
mode, repo, item = sys.argv[1], sys.argv[2], sys.argv[3]
with open(os.environ["STUB_CALLS"], "a") as f:
    f.write(mode + "\n")
if mode == "check":
    chk = os.environ.get("STUB_CHECK", "")
    if chk == "empty":      # a 60s timeout / crash: `check` prints nothing
        sys.exit(0)
    if chk == "notdoc":     # what the real executor answers for any non-doc top item
        print("SKIP\tnot a gd-missing-doc supply item"); sys.exit(0)
    if "SKIPME" in item:
        print("SKIP\tcarries annotations")
    else:
        print("OK\tdocs/a.md" if "DOCITEM" in item else "SKIP\tnot my item")
    sys.exit(0)
beh = os.environ.get("STUB_APPLY", "ok")
target = os.path.join(repo, "docs/a.md")
if beh == "modelfail":
    print("FAIL\tmodel call failed: <urlopen error [Errno 111] Connection refused> for `x`")
elif beh == "fail":
    print("FAIL\tcould not apply")
else:
    with open(target, "a") as f:
        f.write("executor-applied line\n")
    print("APPLIED\tdocs/a.md\tadded a doc line")
EOP
cp "$OD/scripts/ovn_doc_executor.py" "$OD/scripts/ovn_ruff_fix_executor.py"
export STUB_CALLS="$W/calls.txt"
calls(){ [ -f "$STUB_CALLS" ] && wc -l < "$STUB_CALLS" | tr -d ' ' || echo 0; }
ITEM_DOC='- [ ] [T2] docs/a.md — DOCITEM add the executor line. VERIFY: `grep -q executor-applied docs/a.md`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-docs-a]'
mkrepo(){  # $1 name  $2 progress text -> $R, $BEFORE, $TL
  R="$W/$1"; local b="$W/$1.git"; rm -rf "$R" "$b"
  git init -q --bare "$b"; git clone -q "$b" "$R" 2>/dev/null; cd "$R" || exit 1
  git checkout -q -b main; git config user.email t@t; git config user.name t
  mkdir -p docs; printf 'base\n' > docs/a.md
  printf '## Next Steps\n%s\n' "$2" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m init; git push -q origin main 2>/dev/null
  BEFORE="$(git rev-parse HEAD)"; TL="$W/cyc-$1/ongoing-$1.log"; mkdir -p "$(dirname "$TL")"; : > "$TL"; : > "$STUB_CALLS"; rm -rf "${OD:?}/state/exec_failed" "$LOG" "${OD:?}/state/executor_mode"
}
hook(){ ovn_executor_hook doc "$OD" "$R" "$1" main "$TL" "$BEFORE"; }
rows(){ [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
col(){ awk -F'\t' -v n="$1" -v r="${2:-1}" 'NR==r{print $n}' "$LOG"; }

echo "== persistent shadow log (F4 root cause: the scout's > task_log erased the line) =="
mkrepo s1 "$ITEM_DOC"; hook "$ITEM_DOC" >/dev/null; RC=$?
HASH="$(ovn_item_hash "$ITEM_DOC")"
ok "shadow: rc 1, repo untouched, task log has the 'would apply' line (as before)" "[ $RC = 1 ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && grep -q 'DOC-EXECUTOR (shadow): would apply: docs/a.md' '$TL'"
ok "shadow: ONE row in state/executor_shadow.log with 8 tab fields: ts repo kind mode verdict hash detail cycle" "[ \"\$(rows)\" = 1 ] && [ \"\$(awk -F'\t' '{print NF}' '$LOG')\" = 8 ]"
ok "row content: ISO ts, repo s1, kind doc, mode shadow, verdict would-apply, item hash, detail docs/a.md, cycle dir cyc-s1" "[ \"\$(col 2)\" = s1 ] && [ \"\$(col 3)\" = doc ] && [ \"\$(col 4)\" = shadow ] && [ \"\$(col 5)\" = would-apply ] && [ \"\$(col 6)\" = '$HASH' ] && [ \"\$(col 7)\" = docs/a.md ] && [ \"\$(col 8)\" = cyc-s1 ] && col 1 | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'"
: > "$TL"   # exactly what run_overnight.sh's scout redirect does: aider ... > "$task_log"
ok "THE F4 REGRESSION: after the scout truncates the task log the evidence is still in executor_shadow.log" "[ ! -s '$TL' ] && [ \"\$(col 5)\" = would-apply ]"
hook "$ITEM_DOC" >/dev/null
ok "a second cycle APPENDS (2 rows), never truncates" "[ \"\$(rows)\" = 2 ]"
mkrepo s2 "$ITEM_DOC"; hook '- [ ] [T2] app/x.py — a model item. VERIFY: `true`' >/dev/null
ok "check SKIP: a 'skip' row carries the executor's reason (not my item); nothing remembered" "[ \"\$(col 5)\" = skip ] && [ \"\$(col 7)\" = 'not my item' ] && [ ! -d '$OD/state/exec_failed' ]"
mkrepo s2b "$ITEM_DOC"; STUB_CHECK=notdoc hook '- [ ] [T2] app/x.py — a model item. VERIFY: `true`' >/dev/null; RC=$?
ok "round 3: the executor declining a NON-doc top item ('not a gd-missing-doc supply item') writes NO row (it is not evidence about a doc gap and would dilute the would-apply share), rc 1, the task-log line stays" "[ $RC = 1 ] && [ ! -e '$LOG' ] && grep -q 'not a gd-missing-doc supply item' '$TL'"
mkrepo s2c "$ITEM_DOC"; STUB_CHECK=empty hook "$ITEM_DOC" >/dev/null; RC=$?
ok "round 3: a check that prints nothing (timeout/crash) is logged as 'check-empty', never as a 'skip' (a skip row would stand as the item's permanent verdict); rc 1, nothing remembered" "[ $RC = 1 ] && [ \"\$(col 5)\" = check-empty ] && [ \"\$(rows)\" = 1 ] && [ ! -d '$OD/state/exec_failed' ]"
mkrepo s3 "$ITEM_DOC"; mkdir -p "$OD/state/exec_failed"; : > "$OD/state/exec_failed/$HASH"; hook "$ITEM_DOC" >/dev/null
ok "an exec_failed marker: skip row 'previously failed', executor not called" "[ \"\$(col 5)\" = skip ] && col 7 | grep -q 'previously failed' && [ \"\$(calls)\" = 0 ]"
mkrepo s4 "$ITEM_DOC"; OVN_DOC_EXECUTOR=off hook "$ITEM_DOC" >/dev/null
ok "mode off: no row, no log file at all, executor not called" "[ ! -e '$LOG' ] && [ \"\$(calls)\" = 0 ]"
mkrepo s5 "$ITEM_DOC"; mv "$OD/scripts/ovn_doc_executor.py" "$OD/scripts/ovn_doc_executor.py.bak"; hook "$ITEM_DOC" >/dev/null; mv "$OD/scripts/ovn_doc_executor.py.bak" "$OD/scripts/ovn_doc_executor.py"
ok "absent executor script: silent (no row, no task-log line)" "[ ! -e '$LOG' ] && [ ! -s '$TL' ]"
mkrepo s6 "$ITEM_DOC"; OVN_EXECUTOR_LOG="$W/custom.log" hook "$ITEM_DOC" >/dev/null
ok "OVN_EXECUTOR_LOG relocates the log" "[ -s '$W/custom.log' ] && [ ! -e '$LOG' ]"
mkrepo s7 "$ITEM_DOC"; OVN_EXECUTOR_LOG_OFF=1 hook "$ITEM_DOC" >/dev/null
ok "OVN_EXECUTOR_LOG_OFF=1 writes no row (task-log line unchanged)" "[ ! -e '$LOG' ] && grep -q 'would apply' '$TL'"
mkrepo s8 "$ITEM_DOC"; mkdir -p "$OD/state"; yes 'x' | head -c 4300000 > "$LOG"; hook "$ITEM_DOC" >/dev/null
ok "the log is bounded: past 4 MB it is trimmed to the newest 20000 rows (the new row is the last one)" "[ \"\$(rows)\" -le 20001 ] && [ \"\$(tail -1 '$LOG' | cut -f5)\" = would-apply ]"

echo "== on mode logs applied / fail; a model outage is not remembered =="
mkrepo o1 "$ITEM_DOC"; OUT="$(OVN_DOC_EXECUTOR=on hook "$ITEM_DOC")"; RC=$?
ok "on: success => status line and an 'applied' row (detail names the file)" "[ $RC = 0 ] && [ '$OUT' = 'pushed(tests:pass) doc-executor' ] && [ \"\$(col 5)\" = applied ] && [ \"\$(col 4)\" = on ] && col 7 | grep -q 'docs/a.md'"
mkrepo o2 "$ITEM_DOC"; STUB_APPLY=fail OVN_DOC_EXECUTOR=on hook "$ITEM_DOC" >/dev/null; RC=$?
ok "on: apply FAIL => a 'fail' row with the reason, the item IS remembered" "[ $RC = 1 ] && [ \"\$(col 5)\" = fail ] && col 7 | grep -q 'could not apply' && [ -e '$OD/state/exec_failed/$HASH' ]"
mkrepo o3 "$ITEM_DOC"; STUB_APPLY=modelfail OVN_DOC_EXECUTOR=on hook "$ITEM_DOC" >/dev/null; RC=$?
ok "on: apply FAIL 'model call failed' (LiteLLM down) => fail row, tree clean, item NOT remembered" "[ $RC = 1 ] && [ \"\$(col 5)\" = fail ] && col 7 | grep -q 'model call failed' && [ ! -e '$OD/state/exec_failed/$HASH' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
: > "$STUB_CALLS"; STUB_APPLY=ok OVN_DOC_EXECUTOR=on hook "$ITEM_DOC" >/dev/null; RC=$?
ok "... and the next cycle retries it (executor called again) and lands it once the model is back" "[ $RC = 0 ] && [ \"\$(calls)\" = 2 ]"

echo "== mode resolution: env > state/executor_mode (kind:repo beats kind) > shadow =="
mm(){ # <doc|ruff> <repo-dir-name> [env]   (file content on stdin)
  local k="$1" r="$2"; shift 2; mkdir -p "$W/mm/$r" "$OD/state"; cat > "$OD/state/executor_mode"
  ( [ "$#" -gt 0 ] && export "$@"; ovn_executor_mode "$k" "$OD" "$W/mm/$r" )
}
ok "no file, no env => shadow" "[ \"\$(rm -f '$OD/state/executor_mode'; ovn_executor_mode doc '$OD' '$W/mm/xlite')\" = shadow ]"
ok "doc=on applies to every repo" "[ \"\$(printf 'doc=on\n' | mm doc xlite)\" = on ] && [ \"\$(printf 'doc=on\n' | mm doc billwatch)\" = on ]"
ok "doc:xlite=on applies to xlite only" "[ \"\$(printf 'doc:xlite=on\n' | mm doc xlite)\" = on ] && [ \"\$(printf 'doc:xlite=on\n' | mm doc billwatch)\" = shadow ]"
ok "kind:repo beats kind (doc=on, doc:xlite=off) in either order" "[ \"\$(printf 'doc=on\ndoc:xlite=off\n' | mm doc xlite)\" = off ] && [ \"\$(printf 'doc:xlite=off\ndoc=on\n' | mm doc xlite)\" = off ] && [ \"\$(printf 'doc=on\ndoc:xlite=off\n' | mm doc billwatch)\" = on ]"
ok "the doc line does not enable ruff (separate kinds)" "[ \"\$(printf 'doc=on\n' | mm ruff xlite)\" = shadow ]"
ok "env beats the file: OVN_DOC_EXECUTOR=off is a kill switch over doc=on; =on beats doc=shadow" "[ \"\$(printf 'doc=on\n' | mm doc xlite OVN_DOC_EXECUTOR=off)\" = off ] && [ \"\$(printf 'doc=shadow\n' | mm doc xlite OVN_DOC_EXECUTOR=on)\" = on ]"
ok "garbage values, comments, blank lines, spaces and CRLF are tolerated (garbage => shadow, also a garbage ENV value: never enables)" "[ \"\$(printf '# c\n\n doc : xlite = on \r\n' | mm doc xlite)\" = on ] && [ \"\$(printf 'doc=yes\n' | mm doc xlite)\" = shadow ] && [ \"\$(printf 'doc=on\n' | mm doc xlite OVN_DOC_EXECUTOR=bogus)\" = shadow ]"
# bash == python ctl == supply collector, over a table
cat > "$W/parity.py" <<'EOP'
import os, subprocess, sys, tempfile
S = sys.argv[1]; od = sys.argv[2]
sys.path.insert(0, S)
os.environ["OVN_DIR"] = od
import ovn_executor_ctl as C
import ovn_work_supply as W
bad = 0
cases = [("", None, "xlite"), ("doc=on\n", None, "xlite"), ("doc:xlite=on\n", None, "xlite"), ("doc:xlite=on\n", None, "billwatch"), ("doc=on\ndoc:xlite=off\n", None, "xlite"),
         ("doc=on\n", "off", "xlite"), ("doc=shadow\n", "on", "xlite"), ("doc=yes\n", None, "xlite"), ("doc=on\n", "bogus", "xlite"), ("# x\n doc : xlite = on \n", None, "xlite")]
for content, env, repo in cases:
    p = os.path.join(od, "state", "executor_mode")
    if content:
        open(p, "w").write(content)
    elif os.path.exists(p):
        os.remove(p)
    rd = os.path.join(od, "..", "pr", repo); os.makedirs(rd, exist_ok=True)
    e = dict(os.environ); e.pop("OVN_DOC_EXECUTOR", None)
    if env:
        e["OVN_DOC_EXECUTOR"] = env
    sh = subprocess.run(["bash", "-c", '. "$1/lib_item_select.sh"; . "$1/lib_fixup.sh"; ovn_executor_mode doc "$2" "$3"', "x", S, od, rd], capture_output=True, text=True, env=e).stdout
    os.environ.pop("OVN_DOC_EXECUTOR", None)
    if env:
        os.environ["OVN_DOC_EXECUTOR"] = env
    py = C.resolve_mode("doc", repo)
    sup = W.doc_executor_mode(rd)
    os.environ.pop("OVN_DOC_EXECUTOR", None)
    if not (sh == py == sup):
        bad += 1
        print("MISMATCH", repr(content), env, repo, "bash=%r ctl=%r supply=%r" % (sh, py, sup))
sys.exit(1 if bad else 0)
EOP
ok "the same 10-row table resolves identically in bash (lib_fixup), python (ovn_executor_ctl) and the supply collector (ovn_work_supply)" "python3 '$W/parity.py' '$S' '$OD'"
rm -f "$OD/state/executor_mode"
# the hook honours the file
mkrepo f1 "$ITEM_DOC"; printf 'doc:f1=on\n' > "$OD/state/executor_mode"; OUT="$(hook "$ITEM_DOC")"; RC=$?
ok "hook + state file: 'doc:f1=on' makes the hook apply for repo f1 without any env flag" "[ $RC = 0 ] && [ '$OUT' = 'pushed(tests:pass) doc-executor' ]"
mkrepo f2 "$ITEM_DOC"; printf 'doc:xlite=on\n' > "$OD/state/executor_mode"; hook "$ITEM_DOC" >/dev/null
ok "hook + state file for ANOTHER repo: stays shadow (HEAD unchanged, would-apply row)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ \"\$(col 5)\" = would-apply ]"

echo "== ovn_doc_reroute_item: parked credit-refusal doc gaps are re-routable only in ON mode =="
PK1='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM first parked gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-aa]'
PK2='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM second parked gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-bb]'
PKS='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — SKIPME DOCITEM annotated gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-ss]'
PKX='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM but NOT a doc supply item. VERIFY: `true`. [feat:xlite-20261009-other-cc]'
PKH='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [CLAUDE] [T2] docs/a.md — DOCITEM escalated gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-hh]'
PKA='- [ ] [AUTO-SKIP recovery:none after 5 no-op cycles] [T2] docs/a.md — DOCITEM parked for another reason. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-dd]'
PKD='- [x] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM done already. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-ee]'
rr(){ ovn_doc_reroute_item "$OD" "$R" "${1:-ongoing-xlite}"; }
PROG="$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s' "$PKX" "$PKH" "$PKA" "$PKD" "$PKS" "$PK1" "$PK2")"
mkrepo r1 "$PROG"
ok "shadow (default): nothing is re-routed (behaviour unchanged) and a parked-idle breadcrumb is logged" "[ -z \"\$(rr)\" ] && [ \"\$(col 5)\" = parked-idle ] && col 7 | grep -q '^3 parked gd-missing-doc gap'"
ok "off: nothing re-routed and nothing logged" "[ -z \"\$(rm -f '$LOG'; OVN_DOC_EXECUTOR=off rr)\" ] && [ ! -e '$LOG' ]"
ok "on: the first parked doc gap the executor's check accepts - skips the non-doc line, the [CLAUDE] escalation, the other-reason park, the done line and the SKIP-ing (annotated) gap" "[ \"\$(OVN_DOC_EXECUTOR=on rr)\" = '$PK1' ]"
mkdir -p "$OD/state/exec_failed"; : > "$OD/state/exec_failed/$(ovn_item_hash "$PK1")"
ok "on: a gap with an exec_failed marker is skipped - the next parked gap is offered" "[ \"\$(OVN_DOC_EXECUTOR=on rr)\" = '$PK2' ]"
: > "$OD/state/exec_failed/$(ovn_item_hash "$PK2")"
ok "on: every gap failed once => nothing offered" "[ -z \"\$(OVN_DOC_EXECUTOR=on rr)\" ]"
rm -rf "${OD:?}/state/exec_failed"
ok "on via state file doc:r1=on (no env): offered" "printf 'doc:r1=on\n' > '$OD/state/executor_mode'; [ \"\$(rr)\" = '$PK1' ]; rc=\$?; rm -f '$OD/state/executor_mode'; [ \$rc = 0 ]"
ok "only ongoing-* lanes: a queued task id gets nothing" "[ -z \"\$(OVN_DOC_EXECUTOR=on rr t-123)\" ]"
ok "OVN_DOC_REROUTE=off is a kill switch" "[ -z \"\$(OVN_DOC_EXECUTOR=on OVN_DOC_REROUTE=off rr)\" ]"
ok "a progress file with no parked doc gap: nothing" "mkrepo r2 \"\$(printf '%s' \"\$PKX\")\"; [ -z \"\$(OVN_DOC_EXECUTOR=on rr)\" ]"

echo "== SHADOW evidence for parked gaps: read-only check rows, bounded per call, no repeats (docexec round 2) =="
evc(){ awk -F'\t' -v v="$1" '$4=="shadow" && $5==v' "$LOG" | wc -l | tr -d ' '; }
mkrepo r3 "$PROG"; rr >/dev/null; B3="$(git rev-parse HEAD)"
ok "shadow: parked gaps leave 'would-apply' rows (PK1, PK2) and a 'skip' row (the annotated one) with mode=shadow" "[ \"\$(evc would-apply)\" = 2 ] && [ \"\$(evc skip)\" = 1 ] && awk -F'\t' '\$5==\"would-apply\"{print \$6}' '$LOG' | grep -qx '$(ovn_item_hash "$PK1")' && awk -F'\t' '\$5==\"skip\"' '$LOG' | grep -q 'annotations'"
ok "... via the read-only 'check' verb only (3 executor calls, none of them apply), repo untouched" "[ \"\$(calls)\" = 3 ] && ! grep -qv '^check\$' '$STUB_CALLS' && [ \"\$(git rev-parse HEAD)\" = '$B3' ] && [ -z \"\$(git status --porcelain)\" ]"
rr >/dev/null
ok "a second idle cycle repeats nothing: no new evidence rows, no executor call (only the parked-idle breadcrumb)" "[ \"\$(evc would-apply)\" = 2 ] && [ \"\$(evc skip)\" = 1 ] && [ \"\$(calls)\" = 3 ]"
mkrepo r4 "$PROG"; OVN_DOC_SHADOW_PARKED_MAX=1 rr >/dev/null
ok "OVN_DOC_SHADOW_PARKED_MAX=1: one gap checked per idle cycle ..." "[ \"\$(( \$(evc would-apply) + \$(evc skip) ))\" = 1 ] && [ \"\$(calls)\" = 1 ]"
OVN_DOC_SHADOW_PARKED_MAX=1 rr >/dev/null; OVN_DOC_SHADOW_PARKED_MAX=1 rr >/dev/null; OVN_DOC_SHADOW_PARKED_MAX=1 rr >/dev/null
ok "... and successive cycles walk the whole list (3 gaps -> 3 rows, then no more calls)" "[ \"\$(( \$(evc would-apply) + \$(evc skip) ))\" = 3 ] && [ \"\$(calls)\" = 3 ]"
mkrepo r5 "$PROG"; OVN_DOC_SHADOW_PARKED_MAX=0 rr >/dev/null
ok "OVN_DOC_SHADOW_PARKED_MAX=0 disables the evidence rows (parked-idle breadcrumb stays, executor not called)" "[ \"\$(evc would-apply)\" = 0 ] && [ \"\$(calls)\" = 0 ] && [ \"\$(col 5)\" = parked-idle ]"
mkrepo r6 "$PROG"; OVN_DOC_EXECUTOR=on rr >/dev/null
ok "on: the offer path writes no shadow evidence rows (those belong to the hook)" "[ \"\$(evc would-apply)\" = 0 ] && [ \"\$(evc skip)\" = 0 ]"
mkrepo r7 "$PROG"; mkdir -p "$OD/state/exec_failed"; : > "$OD/state/exec_failed/$(ovn_item_hash "$PK1")"; rr >/dev/null
ok "an exec_failed gap is not re-checked for shadow evidence (PK2 + annotated only: 2 calls)" "[ \"\$(calls)\" = 2 ]"
rm -rf "${OD:?}/state/exec_failed"
mkrepo r8 "$PK1"; STUB_CHECK=empty rr >/dev/null
ok "round 3: a parked-gap check that prints nothing (timeout/crash) logs 'check-empty', NOT a permanent shadow 'skip' (and no would-apply)" "[ \"\$(evc check-empty)\" = 1 ] && [ \"\$(evc skip)\" = 0 ] && [ \"\$(evc would-apply)\" = 0 ]"
STUB_CHECK=empty rr >/dev/null; STUB_CHECK=empty rr >/dev/null; STUB_CHECK=empty rr >/dev/null
ok "... the inconclusive item is re-checked on later idle cycles (the dedupe ignores check-empty) but at most 3 times, so a crashing item cannot eat 60s of every idle cycle" "[ \"\$(evc check-empty)\" = 3 ] && [ \"\$(calls)\" = 3 ]"

echo "== ovn_doc_postcheck_gate (real ovn_doc_postcheck.py) =="
DOCGD='- [ ] [T2] scripts/dp.gd — Add a `##` doc-comment on each of these GDScript functions: `predicted`. Comments only. VERIFY: `true`. (cat:godot; multifile:no; supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-dp]'
GDBASE=$'extends RefCounted\n\nstatic func predicted(a):\n\tvar b = a\n\treturn b\n'
mkgd(){ # $1 name $2 head text -> repo with BEFORE = base, HEAD = head commit
  mkrepo "$1" "$DOCGD"; mkdir -p scripts; printf '%s' "$GDBASE" > scripts/dp.gd; git add -A; git commit -q -m base; BEFORE="$(git rev-parse HEAD)"
  printf '%s' "$2" > scripts/dp.gd; git add -A; git commit -q -m "model edit"
}
gate(){ ovn_doc_postcheck_gate "$BEFORE" "$TL" "ongoing-$1"; }
mkgd g1 "$GDBASE"$'## Predicts.\n## Args.\n'
gate g1 >/dev/null; RC=$?
ok "shadow (default), orphan block at EOF: rc 0 (kept), OVN_DPC_TAG='[doc-postcheck]', a 'flag' row, tree untouched" "[ $RC = 0 ] && [ \"\$OVN_DPC_TAG\" = '[doc-postcheck]' ] && [ \"\$(col 3)\" = doc-postcheck ] && [ \"\$(col 5)\" = flag ] && col 7 | grep -q 'no-net-doc' && [ \"\$(git log --format=%s -1)\" = 'model edit' ]"
ok "the shadow flag is in the task log too" "grep -q '\[doc-postcheck\] (mode=shadow)' '$TL'"
mkgd g2 "$GDBASE"$'## Predicts.\n## Args.\n'
OVN_DOC_POSTCHECK=enforce gate g2 >/dev/null; RC=$?
ok "enforce: rc 1, OVN_FXI_STATUS='no-op(doc-postcheck)', tree reset to BEFORE" "[ $RC = 1 ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(doc-postcheck)' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ \"\$(cat scripts/dp.gd)\" = \"\$(printf '%s' \"\$GDBASE\")\" ]"
mkgd g3 "${GDBASE/static func/## Predicts the thing.
static func}"
gate g3 >/dev/null; RC=$?
ok "a correct doc above the func: rc 0, no tag, an 'ok' row" "[ $RC = 0 ] && [ -z \"\$OVN_DPC_TAG\" ] && [ \"\$(col 5)\" = ok ]"
mkgd g4 "$GDBASE"$'## Predicts.\n'
OVN_DOC_POSTCHECK=off gate g4 >/dev/null; RC=$?
ok "off: rc 0, no tag, no row" "[ $RC = 0 ] && [ -z \"\$OVN_DPC_TAG\" ] && [ ! -e '$LOG' ]"
mkgd g5 "$GDBASE"$'## Predicts.\n'
OVN_DOC_POSTCHECK=bogus OVN_DOC_POSTCHECK_BIN="$W/none.py" gate g5 >/dev/null; RC=$?
ok "a missing post-check script: silent pass (rc 0, no tag)" "[ $RC = 0 ] && [ -z \"\$OVN_DPC_TAG\" ]"
mkgd g6 "$GDBASE"$'## Predicts.\n'
OVN_DOC_POSTCHECK=bogus gate g6 >/dev/null; RC=$?
ok "an unknown mode value behaves as shadow (never resets)" "[ $RC = 0 ] && [ \"\$OVN_DPC_TAG\" = '[doc-postcheck]' ] && [ \"\$(git log --format=%s -1)\" = 'model edit' ]"
mkrepo g7 '- [ ] [T1] `app/foo.py` — a roadmap item. VERIFY: `true`'; mkdir -p scripts; printf '%s' "$GDBASE" > scripts/dp.gd; git add -A; git commit -q -m base; BEFORE="$(git rev-parse HEAD)"; printf '%s' "$GDBASE"$'## x\n' > scripts/dp.gd; git add -A; git commit -q -m edit
OVN_DOC_POSTCHECK=enforce gate g7 >/dev/null; RC=$?
ok "a cycle whose item is not a gd-missing-doc item is never judged (even in enforce)" "[ $RC = 0 ] && [ -z \"\$OVN_DPC_TAG\" ] && [ \"\$(git log --format=%s -1)\" = edit ]"

mkrepo g8 "$DOCGD"; printf 'hello\n' > README.md; git add -A; git commit -q -m base; BEFORE="$(git rev-parse HEAD)"; printf 'more\n' >> README.md; git add -A; git commit -q -m "wrong file"
OVN_DOC_POSTCHECK=enforce gate g8 >/dev/null; RC=$?
ok "a repo with NO tracked .gd cannot have a gd-missing-doc landing: the gate exits early (rc 0, no tag, no row, tree untouched) without resolving the item" "[ $RC = 0 ] && [ -z \"\$OVN_DPC_TAG\" ] && [ ! -e '$LOG' ] && [ \"\$(git log --format=%s -1)\" = 'wrong file' ]"
mkrepo g9 "$DOCGD"; mkdir -p scripts; printf '%s' "$GDBASE" > scripts/dp.gd; printf 'hello\n' > README.md; git add -A; git commit -q -m base; BEFORE="$(git rev-parse HEAD)"; printf 'more\n' >> README.md; git add -A; git commit -q -m "wrong file"
OVN_DOC_POSTCHECK=enforce gate g9 >/dev/null; RC=$?
ok "but in a repo that tracks .gd a commit that never touched a .gd for a gd-missing-doc item is STILL caught (enforce resets it) - the early exit is not 'diff has no .gd'" "[ $RC = 1 ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(doc-postcheck)' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"

echo "== runner wiring =="
ok "the scout redirect is still '>' (intentionally untouched: the dedicated log is the fix), and the DOC-EXECUTOR block logs a no-candidate row" "[ \"\$(grep -c 'ovn_executor_log \"\$SCRIPT_DIR\" \"\$PWD\" doc ' '$RUN')\" = 1 ] && grep -q 'no-candidate' '$RUN'"
ok "the exhausted-repo skip consults ovn_doc_reroute_item before returning skip(exhausted)" "awk '/Exhausted-repo skip/{f=1} f&&/ovn_doc_reroute_item/{a=NR} f&&/echo \"skip\\(exhausted\\)\"/{b=NR; exit} END{exit !(a && b && a<b)}' '$RUN'"
ok "the DOC-EXECUTOR block falls back to the re-routable parked gap and ends the cycle with skip(exhausted) when it does not land" "grep -q '_DX_REROUTE=1' '$RUN' && grep -q 'if \[ \"\$_DX_REROUTE\" = 1 \]; then' '$RUN'"
ok "the parked-gap re-route in the DOC-EXECUTOR block is idle-only: guarded by _DOABLE_NOW being 0 (never forces skip(exhausted) while the lane has doable items)" "grep -qE '\[ -z \"\\\$_dx_item\" \] && \[ \"\\\${_DOABLE_NOW:-1}\" -eq 0 \] && declare -F ovn_doc_reroute_item' '$RUN'"
ok "round 3: the exhausted check keeps the re-route lookup (_DX_RR, keyed by this cycle's task log) and the DOC-EXECUTOR block reuses it instead of running check over the parked lines twice" "grep -q '_DX_RR=\"\$(ovn_doc_reroute_item' '$RUN' && grep -q '_DX_RR_DONE=\"\$task_log\"' '$RUN' && grep -q '_dx_item=\"\$_DX_RR\"' '$RUN'"
ok "lib_fixup.sh: the executor-hook header comment sits directly above ovn_executor_hook() (the docexec helpers are above the header, not between it and the function)" "awk '/^# DETERMINISTIC EXECUTOR HOOKS/{h=NR} h&&/^# ====/&&NR>h{e=NR} /^ovn_executor_hook\\(\\) \\{/{f=NR} END{exit !(h&&e&&f&&f==e+1)}' '$S/lib_fixup.sh'"
ok "the post-check gate is wired before the push and its tag joins PUSH_STATUS" "grep -q 'ovn_doc_postcheck_gate \"\$BEFORE_SHA\"' '$RUN' && grep -q 'PUSH_STATUS=\"\${PUSH_STATUS} \${_ovn_doc_tag}\"' '$RUN'"

echo "== MUTATION controls =="
python3 - "$S/lib_fixup.sh" "$W" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, out):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + out, "w").write(s.replace(a, b))
mut('    ovn_executor_log "$od" "$rd" "$kind" "$mode" would-apply "$hash" "$files" "$tl"', '    :', "m_nolog.sh")
mut('*"model call failed"*) _ex_fail "apply failed (${act#FAIL	})" noremember ;;', '*"model call failed"*) _ex_fail "apply failed (${act#FAIL	})" ;;', "m_remember.sh")
mut('  if [ "$m" != on ]; then   # shadow:', '  if false; then   # shadow:', "m_reroute_mode.sh")
mut('    _ovn_fxi_reset "$before"; OVN_FXI_STATUS="no-op(doc-postcheck)"; return 1', '    :', "m_noenforce.sh")
mut('       else ovn_executor_log "$od" "$rd" "$kind" "$mode" skip "$hash" "${out#SKIP	}" "$tl"; fi', '       else :; fi', "m_noskiplog.sh")
mut('elif [ "$kind" = doc ] && case "$out" in *"not a gd-missing-doc supply item"*) true ;; *) false ;; esac; then :', 'elif false; then :', "m_notdoclog.sh")
mut('if [ -z "$out" ]; then ovn_executor_log "$od" "$rd" "$kind" "$mode" check-empty "$hash"', 'if [ -z "$out" ]; then ovn_executor_log "$od" "$rd" "$kind" "$mode" skip "$hash"', "m_hookempty.sh")
mut('      \'\') ovn_executor_log "$od" "$rd" doc shadow check-empty "$h"', '      \'\') ovn_executor_log "$od" "$rd" doc shadow skip "$h"', "m_parkedempty.sh")
mut(' -ge 3 ] 2>/dev/null; then continue; fi', ' -ge 99999 ] 2>/dev/null; then continue; fi', "m_nocap.sh")
mut('  [ -n "$var" ] && m="${!var:-}"', '  m=""', "m_envignored.sh")
mut('        _ovn_doc_shadow_check_parked "$od" "$rd" "$script" "$prog" "$ere"\n', '        :\n', "m_noparkedcheck.sh")
mut('  [ -n "$(git ls-files -- \'*.gd\' 2>/dev/null | head -n 1)" ] || return 0\n', '', "m_noearlyexit.sh")
PY
mutrun(){ # <lib> <script body run in a fresh shell sourcing the mutated lib> -> prints its output
  bash -c ". '$S/lib_item_select.sh'; . '$S/lib_verify_clause.sh'; . '$1'; emit_alert(){ :; }; run_repo_verification(){ echo pass; }; export STUB_CALLS='$STUB_CALLS' OVN_VERIFY_SHADOW_LOG='$W/shadow.log'; $2" 2>/dev/null
}
mkrepo mu1 "$ITEM_DOC"; mutrun "$W/m_nolog.sh" "ovn_executor_hook doc '$OD' '$R' '$ITEM_DOC' main '$TL' '$BEFORE'" >/dev/null
ok "MUTATION: without the persistent log call in the shadow branch no row is written (the F4 regression test would fail)" "[ ! -e '$LOG' ]"
mkrepo mu2 "$ITEM_DOC"; mutrun "$W/m_remember.sh" "STUB_APPLY=modelfail OVN_DOC_EXECUTOR=on ovn_executor_hook doc '$OD' '$R' '$ITEM_DOC' main '$TL' '$BEFORE'" >/dev/null
ok "MUTATION: remembering a model outage poisons the item (marker exists; the not-remembered test would fail)" "[ -e '$OD/state/exec_failed/$HASH' ]"
mkrepo mu3 "$PROG"; OUTM="$(mutrun "$W/m_reroute_mode.sh" "ovn_doc_reroute_item '$OD' '$R' ongoing-xlite")"
ok "MUTATION: a reroute helper that ignores the mode offers the parked gap in SHADOW (the on-only test would fail)" "[ -n '$OUTM' ]"
mkgd mu4 "$GDBASE"$'## Predicts.\n## Args.\n'; mutrun "$W/m_noenforce.sh" "OVN_DOC_POSTCHECK_BIN='$S/ovn_doc_postcheck.py' SCRIPT_DIR='$OD' OVN_DOC_POSTCHECK=enforce ovn_doc_postcheck_gate '$BEFORE' '$TL' ongoing-x" >/dev/null; RCM=$?
ok "MUTATION: enforce without the reset leaves the model's commit in place" "[ \"\$(git rev-parse HEAD)\" != '$BEFORE' ]"
mkrepo mu5 "$ITEM_DOC"; mutrun "$W/m_noskiplog.sh" "ovn_executor_hook doc '$OD' '$R' '- [ ] [T2] app/x.py — a model item' main '$TL' '$BEFORE'" >/dev/null
ok "MUTATION: without the skip row the skip test would fail (no row written)" "[ ! -e '$LOG' ]"
mkrepo mu5b "$ITEM_DOC"; STUB_CHECK=notdoc mutrun "$W/m_notdoclog.sh" "STUB_CHECK=notdoc ovn_executor_hook doc '$OD' '$R' '- [ ] [T2] app/x.py — a model item' main '$TL' '$BEFORE'" >/dev/null
ok "MUTATION: without the non-doc exclusion the 'not a gd-missing-doc supply item' skip row is written again (the round-3 no-row test would fail)" "[ -e '$LOG' ] && [ \"\$(col 5)\" = skip ]"
mkrepo mu5c "$ITEM_DOC"; mutrun "$W/m_hookempty.sh" "STUB_CHECK=empty ovn_executor_hook doc '$OD' '$R' '$ITEM_DOC' main '$TL' '$BEFORE'" >/dev/null
ok "MUTATION: the hook logging empty output as 'skip' is caught (the check-empty test would fail)" "[ \"\$(col 5)\" = skip ]"
mkrepo mu5d "$PK1"; mutrun "$W/m_parkedempty.sh" "STUB_CHECK=empty ovn_doc_reroute_item '$OD' '$R' ongoing-xlite" >/dev/null
ok "MUTATION: logging an empty parked-gap check as a skip makes it a permanent verdict (the round-3 check-empty test would fail)" "[ \"\$(evc skip)\" = 1 ] && [ \"\$(evc check-empty)\" = 0 ]"
mkrepo mu5e "$PK1"; for _i in 1 2 3 4 5; do mutrun "$W/m_nocap.sh" "STUB_CHECK=empty ovn_doc_reroute_item '$OD' '$R' ongoing-xlite" >/dev/null; done
ok "MUTATION: without the 3-retry cap an always-empty check is re-run on every idle cycle (5 rows, the cap test would fail)" "[ \"\$(evc check-empty)\" = 5 ]"
mkrepo mu6 "$ITEM_DOC"; printf 'doc=on\n' > "$OD/state/executor_mode"; OUTM="$(mutrun "$W/m_envignored.sh" "OVN_DOC_EXECUTOR=off ovn_executor_mode doc '$OD' '$R'")"; rm -f "$OD/state/executor_mode"
ok "MUTATION: ignoring the env kill switch lets the file enable the executor over OVN_DOC_EXECUTOR=off" "[ '$OUTM' = on ]"
mkrepo mu7 "$PROG"; mutrun "$W/m_noparkedcheck.sh" "ovn_doc_reroute_item '$OD' '$R' ongoing-xlite" >/dev/null
ok "MUTATION: without the shadow check call no would-apply rows are written for parked gaps (the evidence test would fail)" "[ \"\$(evc would-apply)\" = 0 ]"
mkrepo mu8 "$DOCGD"; printf 'hello\n' > README.md; git add -A; git commit -q -m base; BEFORE="$(git rev-parse HEAD)"; printf 'more\n' >> README.md; git add -A; git commit -q -m "wrong file"
mutrun "$W/m_noearlyexit.sh" "cd '$R'; OVN_DOC_POSTCHECK_BIN='$S/ovn_doc_postcheck.py' OVN_DOC_POSTCHECK=enforce SCRIPT_DIR='$OD' ovn_doc_postcheck_gate '$BEFORE' '$TL' ongoing-x" >/dev/null
ok "MUTATION: without the no-.gd early exit the gate does the full per-cycle work in a repo without GDScript (a row is written / the commit is reset)" "[ -e '$LOG' ] || [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
mkrepo sane "$ITEM_DOC"; OUTS="$(mutrun "$S/lib_fixup.sh" "OVN_DOC_EXECUTOR=off ovn_executor_mode doc '$OD' '$R'")"
ok "MUTATION sanity: the UNMUTATED lib answers off for that case" "[ '$OUTS' = off ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
