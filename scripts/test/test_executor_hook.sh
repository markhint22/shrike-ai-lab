#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 12): ovn_executor_hook - the contract-only DOC-EXECUTOR / RUFF-EXECUTOR hooks beside the DELETE-EXECUTOR block.
# Executors are STUBS here (fake ovn_doc_executor.py / ovn_ruff_fix_executor.py in a temp OVN dir; behaviour switched by STUB_* env) - the real ones are built by other packages.
# Covered: shadow default (check only, 'would apply'), off, absent script (silent), on: success (commit message, credit, push, status), apply FAIL, red verification,
# 'skip' verification (not remembered), failing item VERIFY, undeclared extra file, undeclared dirty tree, push failure, remembered failures skipped, SKIP verdicts, ruff kind,
# run_overnight.sh wiring, mutation controls. Real git repos (bare origin), no network, no model.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
emit_alert(){ :; }
run_repo_verification(){ echo "${STUB_VERIFY:-pass}"; }
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_verify_clause.sh"; . "$S/lib_fixup.sh"
unset OVN_DOC_EXECUTOR OVN_RUFF_EXECUTOR

OD="$W/ovn"; mkdir -p "$OD/scripts" "$OD/state"
cat > "$OD/stub_executor.py" <<'EOP'
# stub executor: python3 <this> check|apply <repo> "<item>" ; behaviour via STUB_* env; every call is appended to $STUB_CALLS
import os, sys
mode, repo, item = sys.argv[1], sys.argv[2], sys.argv[3]
kind = os.environ.get("STUB_KIND", "doc")
with open(os.environ["STUB_CALLS"], "a") as f:
    f.write(mode + "\n")
want = "DOCITEM" if kind == "doc" else "RUFFITEM"
if mode == "check":
    print("OK\tdocs/a.md" if want in item and os.environ.get("STUB_CHECK") != "skip" else "SKIP\tnot my item")
    sys.exit(0)
beh = os.environ.get("STUB_APPLY", "ok")
target = os.path.join(repo, "docs/a.md")
if beh == "fail":
    with open(target, "a") as f:
        f.write("half-written\n")
    print("FAIL\tcould not apply")      # (a misbehaving stub: leaves dirt behind - the hook must still clean up)
elif beh == "nothing":
    print("APPLIED\tdocs/a.md\tno-op")
elif beh == "extra":
    with open(target, "a") as f:
        f.write("executor-applied line\n")
    with open(os.path.join(repo, "other.txt"), "w") as f:
        f.write("undeclared\n")
    os.system("cd %s && git add other.txt" % repo)
    print("APPLIED\tdocs/a.md\tedited a.md and secretly other.txt")
elif beh == "dirty":
    with open(target, "a") as f:
        f.write("executor-applied line\n")
    with open(os.path.join(repo, "README.md"), "a") as f:
        f.write("undeclared unstaged edit\n")
    print("APPLIED\tdocs/a.md\tedited a.md and README.md (undeclared, unstaged)")
elif beh == "badverify":
    with open(target, "a") as f:
        f.write("no marker here\n")
    print("APPLIED\tdocs/a.md\tedit that does not satisfy the item's VERIFY")
else:
    with open(target, "a") as f:
        f.write("executor-applied line\n")
    print("APPLIED\tdocs/a.md\tadded a doc line")
EOP
cp "$OD/stub_executor.py" "$OD/scripts/ovn_doc_executor.py"; cp "$OD/stub_executor.py" "$OD/scripts/ovn_ruff_fix_executor.py"
export STUB_CALLS="$W/calls.txt"
calls(){ [ -f "$STUB_CALLS" ] && wc -l < "$STUB_CALLS" | tr -d ' ' || echo 0; }

ITEM_DOC='- [ ] [T2] docs/a.md — DOCITEM add the executor line. VERIFY: `grep -q executor-applied docs/a.md`'
ITEM_RUFF='- [ ] [T1] docs/a.md — RUFFITEM add the executor line. VERIFY: `grep -q executor-applied docs/a.md`'
mkrepo(){  # $1 name  $2 item line -> $R, $BEFORE, $TL ; with a bare origin
  R="$W/$1"; local b="$W/$1.git"; rm -rf "$R" "$b"
  git init -q --bare "$b"; git clone -q "$b" "$R" 2>/dev/null; cd "$R" || exit 1
  git checkout -q -b main; git config user.email t@t; git config user.name t
  mkdir -p docs; printf 'base\n' > docs/a.md; printf 'readme\n' > README.md
  printf '## Next Steps\n%s\n' "$2" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m init; git push -q origin main 2>/dev/null
  BEFORE="$(git rev-parse HEAD)"; TL="$W/$1.log"; : > "$TL"; : > "$STUB_CALLS"; rm -rf "$OD/state/exec_failed"
}
hook(){ ovn_executor_hook "$1" "$OD" "$R" "$2" main "$TL" "$BEFORE"; }

# ---- shadow (the default) ----
mkrepo s1 "$ITEM_DOC"; OUT="$(hook doc "$ITEM_DOC")"; RC=$?
ok "default mode is SHADOW: rc 1, nothing printed, repo untouched" "[ $RC = 1 ] && [ -z '$OUT' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -z \"\$(git status --porcelain)\" ]"
ok "shadow ran only 'check' (1 call) and logged 'would apply: docs/a.md'" "[ \"\$(calls)\" = 1 ] && [ \"\$(grep -c 'DOC-EXECUTOR (shadow): would apply: docs/a.md' '$TL')\" = 1 ]"
OUT="$(OVN_DOC_EXECUTOR=shadow hook doc "$ITEM_DOC")"
ok "explicit shadow behaves the same" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
OVN_DOC_EXECUTOR=bogus hook doc "$ITEM_DOC" >/dev/null
ok "an unknown mode value falls back to shadow (never applies)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
# ---- off / absent / skip ----
: > "$STUB_CALLS"; OVN_DOC_EXECUTOR=off hook doc "$ITEM_DOC" >/dev/null; RC=$?
ok "off: rc 1 and the executor is not even called" "[ $RC = 1 ] && [ \"\$(calls)\" = 0 ]"
mv "$OD/scripts/ovn_doc_executor.py" "$OD/scripts/ovn_doc_executor.py.bak"; : > "$TL"
OVN_DOC_EXECUTOR=on hook doc "$ITEM_DOC" >/dev/null; RC=$?
ok "absent executor script: skipped SILENTLY (rc 1, nothing logged, repo untouched)" "[ $RC = 1 ] && [ ! -s '$TL' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"
mv "$OD/scripts/ovn_doc_executor.py.bak" "$OD/scripts/ovn_doc_executor.py"
: > "$STUB_CALLS"; OVN_DOC_EXECUTOR=on hook doc '- [ ] [T2] app/x.py — some model item. VERIFY: `true`' >/dev/null; RC=$?
ok "check says SKIP (not this executor's item) => rc 1, only 'check' ran, nothing remembered" "[ $RC = 1 ] && [ \"\$(calls)\" = 1 ] && [ ! -d '$OD/state/exec_failed' ]"

# ---- on: success ----
mkrepo o1 "$ITEM_DOC"; OUT="$(OVN_DOC_EXECUTOR=on hook doc "$ITEM_DOC")"; RC=$?
ok "on: success => rc 0 and the status 'pushed(tests:pass) doc-executor' on stdout" "[ $RC = 0 ] && [ '$OUT' = 'pushed(tests:pass) doc-executor' ]"
ok "on: commit message is 'chore(supply): doc via deterministic executor' and it touches only docs/a.md" "git log --format=%s -3 | grep -qx 'chore(supply): doc via deterministic executor' && [ \"\$(git show --name-only --format= HEAD~1)\" = docs/a.md ]"
ok "on: the item is credited '- [x] (doc via deterministic executor, verified)' in a pathspec commit of OVERNIGHT_PROGRESS.md only" "grep -q '^- \\[x\\] (doc via deterministic executor, verified) \\[T2\\]' OVERNIGHT_PROGRESS.md && [ \"\$(git show --name-only --format= HEAD)\" = OVERNIGHT_PROGRESS.md ]"
ok "on: pushed to origin (origin/main == local HEAD) and the tree is clean" "[ \"\$(git rev-parse HEAD)\" = \"\$(git -C '$W/o1.git' rev-parse main)\" ] && [ -z \"\$(git status --porcelain)\" ]"
ok "on: both the repo verification and the item VERIFY ran (PASS row in the shadow log)" "grep -q 'result=PASS' '$OVN_VERIFY_SHADOW_LOG'"
# ---- on: ruff kind ----
mkrepo o2 "$ITEM_RUFF"; OUT="$(STUB_KIND=ruff OVN_RUFF_EXECUTOR=on hook ruff "$ITEM_RUFF")"; RC=$?
ok "ruff kind: status 'pushed(tests:pass) ruff-executor' and commit 'chore(supply): ruff via deterministic executor'" "[ $RC = 0 ] && [ '$OUT' = 'pushed(tests:pass) ruff-executor' ] && git log --format=%s -3 | grep -qx 'chore(supply): ruff via deterministic executor'"
mkrepo o3 "$ITEM_RUFF"; OUT="$(STUB_KIND=ruff hook ruff "$ITEM_RUFF")"
ok "ruff kind default is shadow too (flag OVN_RUFF_EXECUTOR is separate from OVN_DOC_EXECUTOR)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && grep -q 'RUFF-EXECUTOR (shadow): would apply' '$TL'"
mkrepo o4 "$ITEM_RUFF"; OUT="$(STUB_KIND=ruff OVN_DOC_EXECUTOR=on hook ruff "$ITEM_RUFF")"
ok "OVN_DOC_EXECUTOR=on does NOT enable the ruff executor" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"

# ---- on: failures => reset, remembered, fall through ----
failcase(){ # name behaviour [extra env as VAR=val ...]
  local n="$1" beh="$2"; shift 2
  mkrepo "$n" "$ITEM_DOC"; OUT="$(env STUB_APPLY="$beh" "$@" OVN_DOC_EXECUTOR=on bash -c ". '$S/lib_item_select.sh'; . '$S/lib_verify_clause.sh'; . '$S/lib_fixup.sh'; emit_alert(){ :; }; run_repo_verification(){ echo \"\${STUB_VERIFY:-pass}\"; }; ovn_executor_hook doc '$OD' '$R' '$ITEM_DOC' main '$TL' '$BEFORE'")"; RC=$?
}
HASH="$(ovn_item_hash "$ITEM_DOC")"
failcase f1 fail
ok "apply FAIL (stub leaves dirt behind): rc 1, tree reset clean at BEFORE_SHA, failure remembered" "[ $RC = 1 ] && [ -z '$OUT' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -z \"\$(git status --porcelain)\" ] && [ -e '$OD/state/exec_failed/$HASH' ]"
: > "$STUB_CALLS"; OVN_DOC_EXECUTOR=on hook doc "$ITEM_DOC" >/dev/null; RC=$?
ok "a remembered failure is skipped: rc 1 without calling the executor at all" "[ $RC = 1 ] && [ \"\$(calls)\" = 0 ]"
failcase f2 ok STUB_VERIFY=fail
ok "repo verification red => reset, remembered, no push (origin untouched)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH' ] && [ \"\$(git -C '$W/f2.git' rev-parse main)\" = '$BEFORE' ]"
failcase f3 ok STUB_VERIFY=skip
ok "verification could not run ('skip') => reset but NOT remembered (retried next cycle)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ ! -e '$OD/state/exec_failed/$HASH' ]"
failcase f4 badverify
ok "the item's own VERIFY fails => reset, remembered (the repo verification alone is not enough)" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH' ] && grep -q 'result=FAIL' '$OVN_VERIFY_SHADOW_LOG'"
failcase f5 extra
ok "a commit that stages a file beyond the declared set (other.txt) => reset, remembered, other.txt gone" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH' ] && [ ! -e other.txt ] && grep -q 'beyond the declared' '$TL'"
failcase f6 dirty
ok "undeclared UNSTAGED edits (README.md) => reset, remembered, README.md restored" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH' ] && [ \"\$(cat README.md)\" = readme ]"
failcase f7 nothing
ok "APPLIED but nothing changed => reset, remembered" "[ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH' ]"
mkrepo f8 "$ITEM_DOC"; git -C "$W/f8.git" config receive.denyCurrentBranch ignore; rm -rf "$W/f8.git"; HASH2="$(ovn_item_hash "$ITEM_DOC")"
OUT="$(OVN_DOC_EXECUTOR=on hook doc "$ITEM_DOC")"; RC=$?
ok "push failure (origin gone) => rc 1, reset to BEFORE_SHA, remembered, no status" "[ $RC = 1 ] && [ -z '$OUT' ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ] && [ -e '$OD/state/exec_failed/$HASH2' ]"

# ---- wiring ----
ok "run_overnight.sh has the DOC-EXECUTOR and RUFF-EXECUTOR blocks right after the DELETE-EXECUTOR block" "[ \"\$(grep -c '^    # >>> DOC-EXECUTOR-BEGIN' '$RUN')\" = 1 ] && [ \"\$(grep -c '^    # <<< RUFF-EXECUTOR-END' '$RUN')\" = 1 ] && [ \"\$(grep -n '# <<< DELETE-EXECUTOR-END' '$RUN' | cut -d: -f1)\" -lt \"\$(grep -n '# >>> DOC-EXECUTOR-BEGIN' '$RUN' | cut -d: -f1)\" ]"
ok "each block calls ovn_executor_hook with its kind, only for ongoing-* lanes, and echoes the status then returns" "[ \"\$(grep -c 'ovn_executor_hook doc \"\$SCRIPT_DIR\" \"\$PWD\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'ovn_executor_hook ruff \"\$SCRIPT_DIR\" \"\$PWD\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'echo \"\$_dx_status\"; return' '$RUN')\" = 1 ] && [ \"\$(grep -c 'echo \"\$_rx_status\"; return' '$RUN')\" = 1 ]"
ok "defaults in the runner are shadow (OVN_DOC_EXECUTOR:-shadow / OVN_RUFF_EXECUTOR:-shadow) and the script-absent test is in the condition" "[ \"\$(grep -c 'OVN_DOC_EXECUTOR:-shadow}\" != \"off\" \\] && \\[ -f \"\$SCRIPT_DIR/scripts/ovn_doc_executor.py\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'OVN_RUFF_EXECUTOR:-shadow}\" != \"off\" \\] && \\[ -f \"\$SCRIPT_DIR/scripts/ovn_ruff_fix_executor.py\"' '$RUN')\" = 1 ]"

# ---- MUTATION controls ----
python3 - "$S/lib_fixup.sh" "$W" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, out):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + out, "w").write(s.replace(a, b))
mut('  [ "$okc" = PASS ] || { _ex_fail', '  true || { _ex_fail', "m_verify.sh")
mut('  [ -z "$extra" ] || { _ex_fail', '  true || { _ex_fail', "m_extra.sh")
mut('  mode="${!modevar:-shadow}"', '  mode="${!modevar:-on}"', "m_default.sh")
mut('  if [ "$mode" = shadow ]; then\n    echo "--- ${kind^^}-EXECUTOR (shadow): would apply: ${files} ---" >> "$tl"\n    return 1\n  fi', '  :', "m_shadow.sh")
PY
mut_check(){ # $1=repo name $2=lib $3=stub behaviour $4=expect HEAD moved (1) or not (0) [$5.. env VAR=val]
  local n="$1" lib="$2" beh="$3" want="$4" moved=0; shift 4
  mkrepo "$n" "$ITEM_DOC"
  ( . "$lib"; export STUB_APPLY="$beh"; for kv in "$@"; do export "$kv"; done; ovn_executor_hook doc "$OD" "$R" "$ITEM_DOC" main "$TL" "$BEFORE" >/dev/null )
  [ "$(git rev-parse HEAD)" != "$BEFORE" ] && moved=1
  [ -n "${HCI_DEBUG:-}" ] && cp "$TL" "$HCI_DEBUG.$n"
  [ "$moved" = "$want" ]
}
ok "MUTATION: without the item-VERIFY requirement the 'badverify' edit is (wrongly) landed (HEAD moves)" "mut_check mu1 '$W/m_verify.sh' badverify 1 OVN_DOC_EXECUTOR=on"
ok "MUTATION: without the declared-files check the secret other.txt edit is (wrongly) landed" "mut_check mu2 '$W/m_extra.sh' extra 1 OVN_DOC_EXECUTOR=on"
ok "MUTATION: a default of 'on' applies without any flag (the shadow-by-default test would fail)" "mut_check mu3 '$W/m_default.sh' ok 1"
ok "MUTATION: with the shadow branch removed, explicit shadow mode applies for real" "mut_check mu4 '$W/m_shadow.sh' ok 1 OVN_DOC_EXECUTOR=shadow"
ok "MUTATION sanity: the UNMUTATED hook leaves HEAD at BEFORE for badverify, extra, default-mode and explicit shadow" "mut_check s1 '$S/lib_fixup.sh' badverify 0 OVN_DOC_EXECUTOR=on && mut_check s2 '$S/lib_fixup.sh' extra 0 OVN_DOC_EXECUTOR=on && mut_check s3 '$S/lib_fixup.sh' ok 0 && mut_check s4 '$S/lib_fixup.sh' ok 0 OVN_DOC_EXECUTOR=shadow"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
