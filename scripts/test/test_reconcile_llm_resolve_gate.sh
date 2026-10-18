#!/usr/bin/env bash
# Regression test (package reconcile-llm-resolve-gate, 2026-10-13): reconcile_branches.sh's LLM-assisted conflict resolve must be able to RUN ITS GATE.
# The old code text-extracted run_gate out of branch_hygiene.sh, sourced it under `set -uo pipefail` and called it; run_gate had grown dependencies reconcile never defines
# ($SCRIPT_DIR, $STATE_DIR, acquire_lock, hyg_gate_run, ...), so the shell died ("SCRIPT_DIR: unbound variable"), merge_into returned an EMPTY result, nothing alerted and the
# worktree leaked (142 aider attempts since 09-21, 0 resolved). This runs the REAL reconcile_branches.sh + the REAL branch_hygiene.sh gate-only entry against fixture repos
# (stub aider that strips the markers, stub pytest as the gate) and asserts the conflict is actually resolved, gated, pushed and cleaned up.
# bash 5 / GNU (flock, timeout) suite: run on the box or with Homebrew bash; SKIPs without them.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ_SRC="$HERE/../.."; [ -f "$OQ_SRC/reconcile_branches.sh" ] || OQ_SRC="$HERE/.."
[ -f "$OQ_SRC/reconcile_branches.sh" ] && [ -f "$OQ_SRC/branch_hygiene.sh" ] || { echo "  SKIP: reconcile_branches.sh / branch_hygiene.sh not found"; exit 0; }
for t in flock timeout git python3; do type -P $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  SKIP: needs bash >= 4"; exit 0; }
# shellcheck source=./ntfy_guard.sh
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T
cleanup(){ rm -rf "$T" /tmp/reconcile-*llmgate* 2>/dev/null; }
trap cleanup EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export NTFY_TOPIC="reconcile_llmgate_selftest_ignore"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER OVN_MERGE_SANITY OVN_LLM_RESOLVE_PREFLIGHT HYGIENE_GATE_ONLY DRY_RUN
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"; BIN="$T/bin"
mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs" "$HOME/aider-venv/bin" "$BIN"
cp "$OQ_SRC/reconcile_branches.sh" "$OQ_SRC/branch_hygiene.sh" "$Q/"
for f in lib_lock.sh lib_pytest_parallel.sh lib_gut_xml.sh lib_tree_guard.sh ovn_stub_guard.py; do [ -f "$OQ_SRC/scripts/$f" ] && cp "$OQ_SRC/scripts/$f" "$Q/scripts/"; done
printf '#!/usr/bin/env bash\necho "$*" >> "%s/tok.log"\n' "$T" > "$Q/scripts/ovn_log_tokens.sh"; chmod +x "$Q/scripts/ovn_log_tokens.sh"
# the exported function beats every PATH lookup (reconcile resets PATH): no test may reach the real ntfy.sh; it logs the title + body for assertions
curl(){ printf '%s\n' "curl $*" >> "$T/curl.log"; return 0; }; export -f curl
# stub aider: resolves the conflict by deleting the marker lines (keeps both sides), records the call
cat > "$HOME/aider-venv/bin/aider" <<'EOF2'
#!/usr/bin/env bash
echo "aider $*" >> "$T/aider.log"
files=(); while [ $# -gt 0 ]; do [ "$1" = --file ] && files+=("$2"); shift; done
for f in "${files[@]}"; do sed -i '/^<<<<<<< /d;/^=======$/d;/^>>>>>>> /d' "$f"; done
echo "Tokens: 1.5k sent, 2k received."
exit 0
EOF2
chmod +x "$HOME/aider-venv/bin/aider"
# stub pytest = the repo's gate (run_gate reuses the main clone's .venv/bin/pytest against the worktree): red when STUB_PYTEST_RC=1, red when a conflict marker is in the tree
PYTEST_BODY='echo "pytest cwd=$PWD" >> "$T/pytest.log"
if grep -rqE "^(<<<<<<<|>>>>>>>)" --include=*.txt . 2>/dev/null; then echo "1 failed (markers)"; exit 1; fi
[ "${STUB_PYTEST_RC:-0}" = 0 ] || { echo "1 failed"; exit 1; }
echo ". passed"; exit 0'

mk(){   # <name>: a repo whose develop and overnight/feature conflict in TWO files (a.txt b.txt, both within the <=3 limit); clone checked out on overnight/feature like production
  local n="$1" o="$T/origin/$1.git" s="$T/seed/$1" i
  rm -rf "$o" "$s" "${Q:?}/repos/$n"; mkdir -p "$T/origin" "$T/seed"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; for i in a b; do printf 'one\ntwo\nthree\nfour\nfive\n' > "$i.txt"; done
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git branch overnight/feature; git push -q origin develop overnight/feature
    git checkout -q develop; for i in a b; do sed -i '2s/.*/dev-side/' "$i.txt"; done; git commit -qam "dev edits"; git push -q origin develop
    git checkout -q overnight/feature; for i in a b; do sed -i '2s/.*/feat-side/' "$i.txt"; done; git commit -qam "feat edits"; git push -q origin overnight/feature )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
  git -C "$Q/repos/$n" checkout -q overnight/feature
  mkdir -p "$Q/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$Q/repos/$n/.venv/bin/pytest"; chmod +x "$Q/repos/$n/.venv/bin/pytest"
}
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$Q" && PATH="$BIN:$PATH" bash ./reconcile_branches.sh "$@" > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
reset(){ : > "$T/curl.log"; : > "$T/aider.log"; : > "$T/pytest.log"; rm -f "$T/tok.log" "$Q/state/alerts.log" "$Q/state/reconcile_llm_gate_alerted" "$Q/logs/reconcile_gate_last.log" "$Q/logs/reconcile_gate_preflight.log"; unset STUB_PYTEST_RC; }
leaks(){ ls -d /tmp/reconcile-*llmgate* 2>/dev/null | wc -l | tr -d ' '; }
OUT="$T/out.log"

# ===== A: the reproduction - a resolvable 2-file conflict is auto-resolved, GATED (really), pushed, and nothing leaks =====
reset; mk llmgate; f0="$(sha llmgate overnight/feature)"; run repos/llmgate
ok "A1: reconcile logs the LLM-assisted auto-resolve (was: an empty result / blank log line)" "$(has $OUT 'auto-resolved a develop->overnight/feature CONFLICT')"
ok "A2: aider was called exactly once, with both conflicted files" "$([ "$(grep -c '^aider ' $T/aider.log)" = 1 ] && [ "$(has $T/aider.log '--file a.txt')" = 1 ] && [ "$(has $T/aider.log '--file b.txt')" = 1 ] && echo 1 || echo 0)"
ok "A3: origin/overnight/feature MOVED and contains develop (the merge really landed)" "$([ "$(sha llmgate overnight/feature)" != "$f0" ] && git -C $T/origin/llmgate.git merge-base --is-ancestor develop overnight/feature && echo 1 || echo 0)"
ok "A4: the pushed files carry no conflict markers" "$([ "$(git -C $T/origin/llmgate.git show overnight/feature:a.txt | grep -cE '^(<<<<<<<|=======|>>>>>>>)')" = 0 ] && echo 1 || echo 0)"
ok "A5: reconcile_gate_last.log exists, has the REAL gate's output and NO 'unbound' (the old crash text)" "$([ -s $Q/logs/reconcile_gate_last.log ] && [ "$(has $Q/logs/reconcile_gate_last.log 'gate: pytest')" = 1 ] && [ "$(has $Q/logs/reconcile_gate_last.log 'unbound')" = 0 ] && echo 1 || echo 0)"
ok "A6: the gate really ran the repo's pytest inside the merge worktree" "$([ "$(has $T/pytest.log 'cwd=/tmp/reconcile-llmgate.')" = 1 ] && echo 1 || echo 0)"
ok "A7: no /tmp/reconcile-*llmgate* worktree or preflight dir left behind" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"
ok "A8: the git worktree registry is clean too" "$([ -z "$(git -C $Q/repos/llmgate worktree list --porcelain | grep -F reconcile-)" ] && echo 1 || echo 0)"
ok "A9: the token ledger recorded the attempt" "$([ "$(has $T/tok.log 'reconcile-selfheal llmgate 1500 2000')" = 1 ] && echo 1 || echo 0)"
ok "A10: a resolved conflict sends the info alert, not the CONFLICT alert" "$([ "$(has $T/curl.log 'auto-resolved a conflict')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 0 ] && echo 1 || echo 0)"
ok "A11: no alerts.log warn for a healthy harness" "$([ ! -s $Q/state/alerts.log ] && echo 1 || echo 0)"
ok "A12: the empty-dir preflight ran and answered rc 2 (nothing to check)" "$([ -f $Q/logs/reconcile_gate_preflight.log ] && echo 1 || echo 0)"

# ===== B: a RED gate still rejects the LLM resolution (safety bar unchanged) =====
reset; mk llmgate; f0="$(sha llmgate overnight/feature)"; export STUB_PYTEST_RC=1; run repos/llmgate; unset STUB_PYTEST_RC
ok "B1: red gate -> CONFLICT reported, not auto-resolved" "$([ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && [ "$(has $OUT 'auto-resolved')" = 0 ] && echo 1 || echo 0)"
ok "B2: origin feature untouched" "$([ "$(sha llmgate overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
ok "B3: the CONFLICT alert fired" "$([ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "B4: no leaked worktree after a rejected resolution" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"

# ===== C: BROKEN harness (branch_hygiene.sh missing/unrunnable) -> preflight skips the attempt: no aider tokens, ONE alerts.log warn per day, abort+alert as before =====
reset; mk llmgate; f0="$(sha llmgate overnight/feature)"; mv "$Q/branch_hygiene.sh" "$Q/branch_hygiene.sh.off"; run repos/llmgate
ok "C1: preflight failure is logged ('llm-resolve disabled: gate harness broken')" "$([ "$(has $OUT 'llm-resolve disabled: gate harness broken')" = 1 ] && echo 1 || echo 0)"
ok "C2: NO aider call (no tokens spent on a resolution that can never be verified)" "$([ ! -s $T/aider.log ] && [ ! -s $T/tok.log ] && echo 1 || echo 0)"
ok "C3: falls back to the original conflict report + alert" "$([ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "C4: exactly ONE alerts.log warn names reconcile-llm-gate" "$([ "$(grep -c 'warn | reconcile-llm-gate' $Q/state/alerts.log 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
run repos/llmgate
ok "C5: a second pass the same day does NOT add another alerts.log line (daily dedupe)" "$([ "$(grep -c 'warn | reconcile-llm-gate' $Q/state/alerts.log 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
ok "C6: origin feature untouched, nothing leaked" "$([ "$(sha llmgate overnight/feature)" = "$f0" ] && [ "$(leaks)" = 0 ] && echo 1 || echo 0)"
# kill switch: OVN_LLM_RESOLVE_PREFLIGHT=off skips the check (the attempt then runs and the gate-less result is rejected as before)
reset; mk llmgate; OVN_LLM_RESOLVE_PREFLIGHT=off run repos/llmgate
ok "C7: OVN_LLM_RESOLVE_PREFLIGHT=off skips the preflight (aider is attempted)" "$([ -s $T/aider.log ] && [ "$(has $OUT 'llm-resolve disabled')" = 0 ] && echo 1 || echo 0)"
mv "$Q/branch_hygiene.sh.off" "$Q/branch_hygiene.sh"

# ===== D: a subshell that DIES inside merge_into (the old failure mode) still removes its worktree (EXIT trap) and is reported as a conflict =====
# an exported git FUNCTION runs inside merge_into's own subshell: `exit 99` on the post-resolve `git add a.txt` kills that subshell exactly like set -u did.
reset; mk llmgate; f0="$(sha llmgate overnight/feature)"
git(){ case "$*" in *" add a.txt") exit 99;; esac; command git "$@"; }; export -f git
run repos/llmgate
unset -f git
ok "D1: the dying subshell leaves NO /tmp/reconcile-*llmgate* worktree (EXIT trap)" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"
ok "D2: the worktree is also unregistered from the clone" "$([ -z "$(git -C $Q/repos/llmgate worktree list --porcelain | grep -F reconcile-)" ] && echo 1 || echo 0)"
ok "D3: the empty result is reported as rc=<empty> and alerts as a conflict" "$([ "$(has $OUT 'rc=<empty>')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "D4: origin feature untouched" "$([ "$(sha llmgate overnight/feature)" = "$f0" ] && echo 1 || echo 0)"

# ===== E: the gate-only entry itself =====
mkdir -p "$T/emptydir"
( cd "$Q" && HYGIENE_GATE_ONLY=1 HYGIENE_GATE_REPO="$T/emptydir" HYGIENE_GATE_WT="$T/emptydir" bash ./branch_hygiene.sh > "$T/e1.out" 2>&1 ); e1=$?
ok "E1: empty dir -> rc 2 (nothing to check), not a crash" "$([ "$e1" = 2 ] && [ "$(has $T/e1.out 'unbound')" = 0 ] && echo 1 || echo 0)"
( cd "$Q" && HYGIENE_GATE_ONLY=1 bash ./branch_hygiene.sh > "$T/e2.out" 2>&1 ); e2=$?
ok "E2: missing HYGIENE_GATE_REPO/_WT -> rc 3 + usage message (never a silent 0)" "$([ "$e2" = 3 ] && [ "$(has $T/e2.out 'needs HYGIENE_GATE_REPO')" = 1 ] && echo 1 || echo 0)"
mkdir -p "$T/gdir/repo"; mkdir -p "$T/gdir/repo/.venv/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/gdir/repo/.venv/bin/pytest"; chmod +x "$T/gdir/repo/.venv/bin/pytest"; : > "$T/gdir/repo/x.txt"
( cd "$Q" && HYGIENE_GATE_ONLY=1 HYGIENE_GATE_REPO="$T/gdir/repo" HYGIENE_GATE_WT="$T/gdir/repo" bash ./branch_hygiene.sh > "$T/e3.out" 2>&1 ); e3=$?
ok "E3: a worktree with a green pytest -> rc 0" "$([ "$e3" = 0 ] && echo 1 || echo 0)"
ok "E3b: ...and the gate-only entry ends stdout with its completion marker 'HYGIENE_GATE_ONLY done rc=0'" "$([ "$(tail -n 1 $T/e3.out)" = 'HYGIENE_GATE_ONLY done rc=0' ] && echo 1 || echo 0)"
ok "E1b: the empty-dir answer carries the marker with rc=2" "$([ "$(tail -n 1 $T/e1.out)" = 'HYGIENE_GATE_ONLY done rc=2' ] && echo 1 || echo 0)"
# the gate-only entry must NOT take the hygiene pass lock: hold it, run gate-only, still get the gate's own answer
( exec 9>"$Q/state/hygiene.lock"; flock -n 9 && { cd "$Q" && HYGIENE_GATE_ONLY=1 HYGIENE_GATE_REPO="$T/emptydir" HYGIENE_GATE_WT="$T/emptydir" bash ./branch_hygiene.sh > "$T/e4.out" 2>&1; echo $? > "$T/e4.rc"; } )
ok "E4: with the hygiene lock held elsewhere, gate-only still answers (rc 2), it never waits on / skips for the pass lock" "$([ "$(cat $T/e4.rc 2>/dev/null)" = 2 ] && echo 1 || echo 0)"
# default mode (flag unset) with no repos is unchanged: 'no repos to process', rc 0
( cd "$Q" && bash ./branch_hygiene.sh > "$T/e5.out" 2>&1 ); e5=$?
ok "E5: flag unset + no repos = the old 'no repos to process' exit 0" "$([ "$e5" = 0 ] && [ "$(has $T/e5.out 'no repos to process')" = 1 ] && echo 1 || echo 0)"
ok "E6: gate-only left no stub-leak streak state behind (OVN_STUB_LEAK_ALERT=off in this mode)" "$([ ! -d $Q/state/stub_leak_streak ] && echo 1 || echo 0)"

# ===== F: partial deploy - an OLD branch_hygiene.sh that ignores HYGIENE_GATE_ONLY (no repos -> exit 0) must NEVER read as a green gate, even with the preflight switched off =====
reset; mk llmgate; f0="$(sha llmgate overnight/feature)"
printf '#!/usr/bin/env bash\necho "branch-hygiene: no repos to process"\nexit 0\n' > "$Q/branch_hygiene.sh"
OVN_LLM_RESOLVE_PREFLIGHT=off run repos/llmgate
ok "F1: the attempt ran (preflight off), but the unverified resolution was NOT pushed (origin feature untouched)" "$([ -s $T/aider.log ] && [ "$(sha llmgate overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
ok "F2: reported as a CONFLICT (alert), never 'auto-resolved'" "$([ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && [ "$(has $OUT 'auto-resolved')" = 0 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "F3: the reason is logged (rc 0 without the completion marker)" "$([ "$(has $OUT 'without the HYGIENE_GATE_ONLY completion marker')" = 1 ] && echo 1 || echo 0)"
ok "F4: nothing leaked" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"
# ...and with the preflight ON the same old script is caught BEFORE any token is spent (rc 0, not the expected 2)
reset; mk llmgate; run repos/llmgate
ok "F5: preflight on + old script -> disabled before aider (no tokens)" "$([ ! -s $T/aider.log ] && [ "$(has $OUT 'llm-resolve disabled: gate harness broken')" = 1 ] && echo 1 || echo 0)"
cp "$OQ_SRC/branch_hygiene.sh" "$Q/branch_hygiene.sh"

# ===== G: the gate-only probe is READ-ONLY w.r.t. the hygiene lane's shadow stub-leak state (clean tree used to rm the streak counter + state file) =====
SGR="$T/sg/repo"; mkdir -p "$SGR/app" "$SGR/.venv/bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$SGR/.venv/bin/pytest"; chmod +x "$SGR/.venv/bin/pytest"
( cd "$SGR" && git init -q -b main . && printf 'x=1\n' > app/real.py && printf '.venv/\n' > .gitignore && git add -A && git commit -q -m init )
seed_stub(){ mkdir -p "$Q/state/stub_leak_streak"; echo "123 2 0" > "$Q/state/stub_leak_streak/repo__overnight_feature"; echo "SOURCE	app/Old.kt" > "$Q/state/stub_leak_repo.txt"; }
gate_only(){ ( cd "$Q" && HYGIENE_GATE_ONLY=1 HYGIENE_GATE_REPO="$SGR" HYGIENE_GATE_WT="$SGR" bash ./branch_hygiene.sh > "$T/g.out" 2>&1 ); echo $?; }
seed_stub; g1="$(gate_only)"
ok "G1: clean tree -> rc 0" "$([ "$g1" = 0 ] && echo 1 || echo 0)"
ok "G2: ...the lane's stub_leak_streak counter is NOT removed" "$([ "$(cat $Q/state/stub_leak_streak/repo__overnight_feature 2>/dev/null)" = '123 2 0' ] && echo 1 || echo 0)"
ok "G3: ...and state/stub_leak_<repo>.txt is NOT removed/overwritten" "$([ "$(cat $Q/state/stub_leak_repo.txt 2>/dev/null)" = 'SOURCE	app/Old.kt' ] && echo 1 || echo 0)"
printf '// Placeholder - the implement step fills this in.\n' > "$SGR/app/Leaked.kt"; ( cd "$SGR" && git add -A && git commit -q -m leak )
seed_stub; g2="$(gate_only)"
ok "G4: a leaked stub in SHADOW still passes the probe (rc 0) and is flagged in its output, but the lane state is untouched" "$([ "$g2" = 0 ] && [ "$(has $T/g.out 'STUB-LEAK FLAG (shadow)')" = 1 ] && [ "$(cat $Q/state/stub_leak_repo.txt)" = 'SOURCE	app/Old.kt' ] && [ "$(cat $Q/state/stub_leak_streak/repo__overnight_feature)" = '123 2 0' ] && echo 1 || echo 0)"
seed_stub; g3="$(OVN_STUB_LEAK=enforce gate_only)"
ok "G5: OVN_STUB_LEAK=enforce still BLOCKS in gate-only mode (rc 1): the read-only change must not weaken enforcement" "$([ "$g3" = 1 ] && [ "$(cat $Q/state/stub_leak_repo.txt)" = 'SOURCE	app/Old.kt' ] && echo 1 || echo 0)"

echo "$P passed, $F failed"
[ "$F" -eq 0 ] && echo "  test_reconcile_llm_resolve_gate: PASS" || echo "  test_reconcile_llm_resolve_gate: FAIL"
[ "$F" -eq 0 ]
