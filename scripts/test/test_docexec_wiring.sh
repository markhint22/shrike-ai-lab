#!/usr/bin/env bash
# 2026-10-10 (package docexec; analysis[6] BX-01 / analysis[0] F4 / analysis[5] B3): the doc-executor wiring in run_overnight.sh, END TO END through the REAL script in the
# hermetic fake tree (lib_ro_core.sh). Proves what the lib-level tests (test_executor_shadow_log.sh) cannot:
#   A. F4: with a doable gd-missing-doc item on top the shadow verdict reaches state/executor_shadow.log even though the cycle's task log is truncated by the scout;
#   B. exhausted lane, only parked credit-refusal doc gaps: SHADOW => skip(exhausted) unchanged + a parked-idle breadcrumb; ON (state file) => the executor is offered the gap, lands
#      it (pushed(tests:pass) doc-executor, item credited) and a failed attempt ends the cycle as skip(exhausted) instead of feeding the model an empty backlog;
#   C. the BX-01 post-check on a model-written doc cycle: shadow tags the push status '[doc-postcheck]' and keeps the commit; enforce resets it (no-op(doc-postcheck)); a good doc is untouched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
# the real run_overnight.sh needs util-linux flock (-w 0): the macOS flock port rejects it, so every end-to-end test of the real script fails on the Mac at baseline
# (test_run_overnight_core_main.sh: 14 passed / 57 failed there). Run this one on the box.
if ! ( _p="$(mktemp)"; exec 9>"$_p"; flock -w 0 9 ) 2>/dev/null; then echo "  SKIP: needs util-linux flock (-w 0); run on the box"; exit 0; fi
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed (the runner uses sed -i); run on the box"; exit 0; fi
unset OVN_DOC_EXECUTOR OVN_RUFF_EXECUTOR OVN_DOC_POSTCHECK OVN_DOC_REROUTE OVN_EXECUTOR_LOG OVN_EXECUTOR_LOG_OFF NTFY_SERVER NTFY_TOPIC
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh \
        scripts/lib_verify_clause.sh scripts/lib_auto_credit.sh scripts/lib_parked_pattern.sh scripts/lib_path_normalize.sh scripts/lib_run_integrity.sh scripts/lib_worktree.sh \
        scripts/ovn_doc_postcheck.py scripts/ovn_doc_executor.py scripts/ovn_executor_ctl.py
ST="$T/tree/state"; R="$T/repos"; LOG="$ST/executor_shadow.log"; mkdir -p "$ST"
S="$RO_Q/scripts"
GDBASE=$'extends RefCounted\n\nstatic func predicted(a):\n\tvar b = a\n\tvar c = b\n\tvar d = c\n\tvar e = d\n\treturn e\n'
VER="python3 -c \"import re,sys;s=open('scripts/dp.gd').read();sys.exit(0 if re.search(r'^##[^\\\\n]*\\\\n(?:static )?func predicted[(]',s,re.M) else 1)\""
doc_item(){ # $1 = prefix tags
  printf -- '- [ ] %s[T2] scripts/dp.gd — Add a `##` doc-comment on the line directly above each of these GDScript functions: `predicted`. Comments only. VERIFY: `%s`. (cat:godot; multifile:no; supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-dp]' "$1" "$VER"
}
PARKED='[AUTO-SKIP after 2 credit refusals: VERIFY failed] '
mkp(){ printf '# Overnight Progress\n\n## Next Steps\n'; printf '%s\n' "$@"; }
mkrepo2(){ # <name> <progress text>   -> repo with scripts/dp.gd tracked
  ro_mkrepo "$1" "$2" >/dev/null
  ( cd "$R/$1" && mkdir -p scripts && printf '%s' "$GDBASE" > scripts/dp.gd && git add -A && git commit -q -m "add dp.gd" && git push -q origin main 2>/dev/null )
}
cycle(){ # <name> [ENV=...]  one ongoing-<name> cycle
  local name="$1"; shift
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("ongoing-"+$n),repo:($R+"/"+$n),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
  rm -rf "${T:?}/tree/reports"/* "${ST:?}/outcomes.jsonl" "${RO_STUB:?}/aider_n" "${RO_STUB:?}/aider_kinds" "$LOG" "${ST:?}/executor_mode"
  printf 'IMPL_SEQ=none\nSCOUT_FILES=scripts/dp.gd\nSCOUT_PLAN="add a doc comment above predicted"\n' > "$RO_STUB/scn"
  ro_run_main "$@"; REP="$(ro_report)"
  STATUS="$(jq -r --arg id "ongoing-$name" 'select(.id==$id) | .status' "$ST/outcomes.jsonl" 2>/dev/null | tail -1)"
}
col(){ awk -F'\t' -v n="$1" -v r="${2:-1}" 'NR==r{print $n}' "$LOG" 2>/dev/null; }
aiders(){ [ -f "$RO_STUB/aider_n" ] && cat "$RO_STUB/aider_n" || echo 0; }

echo "=== A: F4 - the shadow verdict survives the scout's truncating redirect ==="
mkrepo2 a1 "$(mkp "$(doc_item '')")"
cycle a1
ok "shadow: the cycle ran the normal scout+implement path (aider was called)" "$([ "$(aiders)" -ge 1 ] && echo 1 || echo 0)"
eq "state/executor_shadow.log has the would-apply row for the cycle (verdict column)" "would-apply" "$(col 5)"
eq "... for repo a1, kind doc, mode shadow" "a1 doc shadow" "$(col 2) $(col 3) $(col 4)"
has "... naming the file" "$(col 7)" "scripts/dp.gd"
LATEST_LOG="$(ls -t "$T"/tree/logs/*/ongoing-a1.log 2>/dev/null | head -1)"
hasnt "the cycle's own task log no longer carries the line (it was truncated by the scout's > redirect - the reason the log exists)" "$(cat "$LATEST_LOG" 2>/dev/null)" "would apply"
eq "the executor did not touch the repo in shadow (HEAD has no executor commit)" "0" "$(git -C "$R/a1" log --format=%s | grep -c 'deterministic executor')"

echo "=== B: exhausted lane with only parked doc gaps ==="
mkrepo2 b1 "$(mkp "$(doc_item "$PARKED")")"
cycle b1
eq "shadow: the lane still reports skip(exhausted) (behaviour unchanged)" "skip(exhausted)" "$STATUS"
eq "shadow: aider was NOT called" 0 "$(aiders)"
eq "shadow: a parked-idle breadcrumb row says how many gaps idle" "parked-idle" "$(col 5)"
has "shadow: ... with the count" "$(col 7)" "1 parked gd-missing-doc gap"
# a deterministic stand-in for the model-writing executor: same contract (check/apply), no LiteLLM; the REAL hook still commits, verifies repo + the item's own VERIFY, credits and pushes
rm -f "$T/tree/scripts/ovn_doc_executor.py"
cat > "$T/tree/scripts/ovn_doc_executor.py" <<'EOP'
import os, sys
mode, repo, item = sys.argv[1], sys.argv[2], sys.argv[3]
if mode == "check" and os.environ.get("CHK_LOG"):
    open(os.environ["CHK_LOG"], "a").write("c\n")   # one line per `check` call (test E counts them)
if "supply:gd-missing-doc" not in item:
    print("SKIP\tnot a gd-missing-doc supply item"); sys.exit(0)
if mode == "check":
    print("OK\tscripts/dp.gd"); sys.exit(0)
if os.environ.get("STUB_APPLY") == "fail":
    print("FAIL\tstub could not apply"); sys.exit(0)
p = os.path.join(repo, "scripts/dp.gd")
t = open(p).read().replace("static func predicted", "## Predicts the thing.\nstatic func predicted")
open(p, "w").write(t)
print("APPLIED\tscripts/dp.gd\t1 docs")
EOP
bmode(){ # <name> <mode line or ''> [ENV=...]  one cycle with the state file preset
  local name="$1" line="$2"; shift 2
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("ongoing-"+$n),repo:($R+"/"+$n),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
  rm -rf "${T:?}/tree/reports"/* "${ST:?}/outcomes.jsonl" "${RO_STUB:?}/aider_n" "${RO_STUB:?}/aider_kinds" "$LOG" "${ST:?}/executor_mode"
  [ -n "$line" ] && printf '%s\n' "$line" > "$ST/executor_mode"
  printf 'IMPL_SEQ=none\nSCOUT_FILES=scripts/dp.gd\n' > "$RO_STUB/scn"
  ro_run_main "$@"
  STATUS="$(jq -r --arg id "ongoing-$name" 'select(.id==$id) | .status' "$ST/outcomes.jsonl" 2>/dev/null | tail -1)"
}
mkrepo2 b2 "$(mkp "$(doc_item "$PARKED")")"
bmode b2 ''
eq "executor still SHADOW without the state line: skip(exhausted), no commit" "skip(exhausted)" "$STATUS"
bmode b2 'doc:b2=on'
eq "ON via state/executor_mode (no env var): the parked gap is re-routed - status 'pushed(tests:pass) doc-executor'" "pushed(tests:pass) doc-executor" "$STATUS"
eq "... no model call at all (aider not called)" 0 "$(aiders)"
ok "... the file now carries the ## above the func" "$(grep -q '^## Predicts the thing\.$' "$R/b2/scripts/dp.gd" && echo 1 || echo 0)"
ok "... the item is credited '- [x] (doc via deterministic executor, verified)'" "$(grep -q '^- \[x\] (doc via deterministic executor, verified)' "$R/b2/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "... and the credit commit is on origin (the cycle's own overnight/<run>/<id> branch tip == local HEAD)" "$(git -C "$T/origin/b2.git" for-each-ref --format='%(objectname)' refs/heads | grep -qx "$(git -C "$R/b2" rev-parse HEAD)" && echo 1 || echo 0)"
eq "... an 'applied' row is logged" "applied" "$(awk -F'\t' '$5=="applied"{print $5}' "$LOG" | head -1)"
mkrepo2 b3 "$(mkp "$(doc_item "$PARKED")")"
bmode b3 'doc:b3=on' STUB_APPLY=fail
eq "ON, executor FAILS: the cycle ends as skip(exhausted) (the model is not fed an empty backlog)" "skip(exhausted)" "$STATUS"
eq "... aider not called" 0 "$(aiders)"
eq "... a 'fail' row is logged" "fail" "$(awk -F'\t' '$5=="fail"{print $5}' "$LOG" | head -1)"
eq "... and the repo is back at its starting commit (origin == local, no executor commit)" "$(git -C "$T/origin/b3.git" rev-parse main)" "$(git -C "$R/b3" rev-parse HEAD)"
ok "... the failure is remembered (exec_failed marker) so the next cycle does not retry the same gap" "$(ls "$ST/exec_failed"/* >/dev/null 2>&1 && echo 1 || echo 0)"
mv "$ST/exec_failed" "$T/exec_failed.keep"
bmode b3 'doc:b3=on' STUB_APPLY=ok
eq "... (control) without the marker the same gap IS offered again and lands" "pushed(tests:pass) doc-executor" "$STATUS"
mkrepo2 b3 "$(mkp "$(doc_item "$PARKED")")"; mkdir -p "$ST/exec_failed"; cp "$T/exec_failed.keep"/* "$ST/exec_failed/" 2>/dev/null
ro_tasks "$(jq -nc --arg R "$R" '[{id:"ongoing-b3",repo:($R+"/b3"),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
rm -rf "${T:?}/tree/reports"/* "${ST:?}/outcomes.jsonl" "${RO_STUB:?}/aider_n" "$LOG"; printf 'doc:b3=on\n' > "$ST/executor_mode"
ro_run_main STUB_APPLY=ok
STATUS="$(jq -r 'select(.id=="ongoing-b3") | .status' "$ST/outcomes.jsonl" 2>/dev/null | tail -1)"
eq "with the exec_failed marker in place the next cycle does not retry the gap: skip(exhausted)" "skip(exhausted)" "$STATUS"
rm -rf "${ST:?}/exec_failed" "${T:?}/exec_failed.keep"
mkrepo2 b4 "$(mkp "$(doc_item "$PARKED")")"
bmode b4 'doc:b4=on' OVN_DOC_REROUTE=off
eq "OVN_DOC_REROUTE=off is a kill switch even in ON mode (skip(exhausted), no commit)" "skip(exhausted)" "$STATUS"
rm -f "$ST/executor_mode"

echo "=== D: parked-gap re-route is IDLE-ONLY (round 2): never forces skip(exhausted) while the lane has a doable item ==="
# a doable item the executor-candidate filter drops (HARD FILE BAN: the exhausted count keeps it, the DOC-EXECUTOR block does not) next to an ON-mode re-routable parked gap whose apply FAILS.
# Old behaviour: no candidate -> re-route the parked gap -> it fails -> the cycle was forced to skip(exhausted) although the lane had doable work. New: no re-route, the normal path runs.
HFB="$(doc_item '[HARD FILE BAN] ' | sed 's/gd-missing-doc-dp\]/gd-missing-doc-hb]/')"
PK_D="$(doc_item "$PARKED" | sed 's/gd-missing-doc-dp\]/gd-missing-doc-pp]/')"
mkrepo2 d1 "$(mkp "$HFB" "$PK_D")"
bmode d1 'doc:d1=on' STUB_APPLY=fail
hasnt "ON, doable (HARD FILE BAN) item present: the cycle is NOT forced to skip(exhausted)" "$STATUS" "skip(exhausted)"
ok "... the normal path ran (aider called)" "$([ "$(aiders)" -ge 1 ] && echo 1 || echo 0)"
eq "... the parked gap was not offered to the executor (no 'fail' row, no exec_failed marker)" "00" "$(awk -F'\t' '$5=="fail"' "$LOG" 2>/dev/null | wc -l | tr -d ' ')$(ls "$ST/exec_failed" 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$ST/executor_mode"

echo "=== E: round 3 - ON mode looks the parked gaps up ONCE per cycle (the exhausted check's lookup is reused by the DOC-EXECUTOR block) ==="
mkrepo2 e1 "$(mkp "$(doc_item "$PARKED")")"
rm -f "$T/chk"
bmode e1 'doc:e1=on' CHK_LOG="$T/chk"
eq "ON, idle lane, parked gap: lands via the executor" "pushed(tests:pass) doc-executor" "$STATUS"
eq "... executor 'check' ran 2x in the cycle (one lookup of the parked gap + the hook's own check); the old double lookup made it 3" "2" "$(wc -l < "$T/chk" 2>/dev/null | tr -d ' ')"
mkrepo2 e2 "$(mkp "$(doc_item "$PARKED")")"
rm -f "$T/chk"
bmode e2 'doc:e2=on' CHK_LOG="$T/chk" STUB_APPLY=fail
eq "ON, apply fails: still skip(exhausted) (the reused lookup does not change the outcome)" "skip(exhausted)" "$STATUS"
eq "... and still only 2 checks" "2" "$(wc -l < "$T/chk" 2>/dev/null | tr -d ' ')"
rm -rf "${ST:?}/exec_failed"; rm -f "$ST/executor_mode"

echo "=== C: BX-01 post-check on a model-written doc cycle ==="
rm -f "$T/tree/scripts/ovn_doc_executor.py"; ro_link scripts/ovn_doc_executor.py   # the post-check imports the REAL executor module (parse_item/anchor): drop the stand-in
# a stand-in aider whose implement step writes the doc where the real 27B did: variant orphan = appended at EOF, variant good = above the func
ro_stub aider <<'EOF'
S="${RO_STUB:?}"
n=$(( $(cat "$S/aider_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/aider_n"
case " $* " in
  *" --no-auto-commits "*) printf 'VERDICT: PROCEED\nPLAN: doc above predicted\nFILES: scripts/dp.gd\nTokens: 1k sent, 100 received.\n'; exit 0;;
esac
case "$(cat "$S/doc_variant" 2>/dev/null)" in
  good) python3 - <<'PY'
p = "scripts/dp.gd"; t = open(p).read().replace("static func predicted", "## Predicts the thing.\nstatic func predicted"); open(p, "w").write(t)
PY
  ;;
  *) printf '## Predicts the thing.\n## Args: a.\n' >> scripts/dp.gd;;
esac
git add -A; git commit -q -m "docs: add docstrings for predicted"
echo "Tokens: 2k sent, 500 received. Applied edit to scripts/dp.gd"
EOF
cyc2(){ # <name> <variant> [ENV=...]
  local name="$1" variant="$2"; shift 2
  mkrepo2 "$name" "$(mkp "$(doc_item '')")"
  echo "$variant" > "$RO_STUB/doc_variant"
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("ongoing-"+$n),repo:($R+"/"+$n),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
  rm -rf "${T:?}/tree/reports"/* "${ST:?}/outcomes.jsonl" "${RO_STUB:?}/aider_n" "$LOG" "${ST:?}/executor_mode"
  ro_run_main "$@"
  STATUS="$(jq -r --arg id "ongoing-$name" 'select(.id==$id) | .status' "$ST/outcomes.jsonl" 2>/dev/null | tail -1)"
  [ -n "${DBGLOG:-}" ] && { echo "=== task log $name ==="; cat "$(ls -t "$T"/tree/logs/*/ongoing-$name.log | head -1)"; }
}
cyc2 c1 orphan
has "shadow: an orphan-at-EOF doc commit still lands (pushed) ..." "$STATUS" "pushed"
has "... but the push status carries the '[doc-postcheck]' tag so the landing is countable" "$STATUS" "[doc-postcheck]"
eq "... and a doc-postcheck 'flag' row is logged" "flag" "$(awk -F'\t' '$3=="doc-postcheck"{print $5}' "$LOG" | head -1)"
has "... the flag names no-net-doc and orphan" "$(awk -F'\t' '$3=="doc-postcheck"{print $7}' "$LOG" | head -1)" "no-net-doc,orphan"
cyc2 c2 orphan OVN_DOC_POSTCHECK=enforce
eq "enforce: the cycle is a no-op(doc-postcheck)" "no-op(doc-postcheck)" "$STATUS"
eq "enforce: the model's commit is gone (repo back at its starting commit, origin untouched)" "$(git -C "$T/origin/c2.git" rev-parse main)" "$(git -C "$R/c2" rev-parse HEAD)"
cyc2 c3 good
hasnt "a correct doc above the func: no tag" "$STATUS" "doc-postcheck"
has "... lands normally" "$STATUS" "pushed"
eq "... and an 'ok' post-check row" "ok" "$(awk -F'\t' '$3=="doc-postcheck"{print $5}' "$LOG" | head -1)"
cyc2 c4 orphan OVN_DOC_POSTCHECK=off
hasnt "OVN_DOC_POSTCHECK=off: no tag, no row" "$STATUS$(cat "$LOG" 2>/dev/null | grep -c doc-postcheck)" "doc-postcheck"
[ -n "${DBG:-}" ] && { echo "--- RUN OUT ---"; echo "$RO_OUT" | tail -40; }
ro_summary
