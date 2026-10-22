#!/usr/bin/env bash
# Regression test (package P2a, 2026-10-21): the reconcile CONFLICT alert must be deduped (it fired on every pass: 8 high notes in 105 min for one conflict).
# On 10-13 test-automation-agent's develop->overnight/feature sync produced 7 reconcile.log lines with an EMPTY outcome (the subshell behind rc=$(sync_feature) had died on an unbound
# variable); the `*) log "$name: develop->$feat $rc"` branch only logged them, so $conflicts stayed empty, no ntfy fired, and a 2-file conflict sat 14:04 -> 16:40 until a manual merge.
# The dying subshell is simulated with an exported git FUNCTION (it runs inside merge_into's own subshell; `exit 99` kills that subshell exactly like set -u did).
# bash 5 suite (run on the box / Homebrew bash); fixtures only, curl is a stub function.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ_SRC="$HERE/../.."; [ -f "$OQ_SRC/reconcile_branches.sh" ] || OQ_SRC="$HERE/.."
[ -f "$OQ_SRC/reconcile_branches.sh" ] || { echo "  SKIP: reconcile_branches.sh not found"; exit 0; }
for t in timeout git; do type -P $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  SKIP: needs bash >= 4"; exit 0; }
# shellcheck source=./ntfy_guard.sh
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T
cleanup(){ safe_rm_rf "$T" 2>/dev/null; }
trap cleanup EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export NTFY_TOPIC="reconcile_dedupe_selftest_ignore"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER OVN_MERGE_SANITY DRY_RUN
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"
mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs"
cp "$OQ_SRC/reconcile_branches.sh" "$Q/"; [ -f "$OQ_SRC/scripts/lib_tree_guard.sh" ] && cp "$OQ_SRC/scripts/lib_tree_guard.sh" "$Q/scripts/"
touch "$Q/state/PAUSED"   # the GPU-using LLM path stays out of this test; the die is injected at the plain merge
curl(){ printf '%s\n' "curl $*" >> "$T/curl.log"; [ -e "$T/curl.fail" ] && return 7; return 0; }; export -f curl


mk(){   # <name> <conflict|clean>: develop and overnight/feature both edit f.txt differently (real merge conflict) | clean = feature just behind develop (fast-forward)
  local n="$1" k="$2" o="$T/origin/$1.git" s="$T/seed/$1"
  safe_rm_rf "$o" "$s" "$Q/repos/$n"; mkdir -p "$T/origin" "$T/seed"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop; git branch overnight/feature; git push -q origin overnight/feature
    git checkout -q develop; echo dev > f.txt; git add -A; git commit -q -m "dev edit"; git push -q origin develop
    if [ "$k" = conflict ]; then git checkout -q overnight/feature; echo feat > f.txt; git add -A; git commit -q -m "feat edit"; git push -q origin overnight/feature; fi )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$Q" && bash ./reconcile_branches.sh "$@" > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
cnt(){ grep -c -- "$1" "$T/curl.log" 2>/dev/null || true; }
CA="$Q/state/reconcile_conflict_alert"

mk billwatch conflict
: > "$T/curl.log"; export OVN_RECONCILE_NOW=1000000
run
ok "A0: the fixture really conflicts (alert fired on pass 1)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
run
ok "A1: SECOND consecutive pass with the same conflict -> still ONE alert (old code: 2)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "A1b: the suppressed pass is logged" "$([ "$(has $T/out.log 'conflict alert suppressed')" = 1 ] && echo 1 || echo 0)"
ok "A1c: the conflict itself is still logged every pass" "$([ "$(has $T/out.log 'CONFLICT develop->overnight/feature')" = 1 ] && echo 1 || echo 0)"
export OVN_RECONCILE_NOW=$((1000000 + 5*3600)); run
ok "A2: 5 h later, same set -> still suppressed" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
export OVN_RECONCILE_NOW=$((1000000 + 6*3600 + 1)); run
ok "A3: after the 6 h ceiling, same set -> re-alert (2nd)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 2 ] && echo 1 || echo 0)"
mk gitlark conflict   # a SECOND conflicting repo: the set changes
run
ok "A4: a changed conflict set -> new alert at once (3rd), naming the new repo" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 3 ] && [ "$(has $T/curl.log 'gitlark')" = 1 ] && echo 1 || echo 0)"
run
ok "A5: unchanged again -> no 4th alert" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 3 ] && echo 1 || echo 0)"
ok "A5b: no 'cleared' note while conflicts remain" "$([ "$(cnt 'conflict cleared')" = 0 ] && echo 1 || echo 0)"
# clear both: make the feature branches equal to develop (hygiene landed them)
for n in billwatch gitlark; do
  ( cd "$T/seed/$n" && git fetch -q origin && git checkout -q -B overnight/feature origin/develop && git push -q -f origin overnight/feature )
done
run repos/billwatch
ok "A6: a single-repo pass does NOT judge recovery (no cleared note, state kept)" "$([ "$(cnt 'conflict cleared')" = 0 ] && [ -f "$CA" ] && echo 1 || echo 0)"
run
ok "A7: full pass with the set empty -> ONE 'cleared' note" "$([ "$(cnt 'conflict cleared')" = 1 ] && echo 1 || echo 0)"
ok "A7b: state file removed" "$([ ! -f "$CA" ] && echo 1 || echo 0)"
run
ok "A8: later clean pass -> no second cleared note, no conflict alert" "$([ "$(cnt 'conflict cleared')" = 1 ] && [ "$(cnt 'Branch reconcile CONFLICT')" = 3 ] && echo 1 || echo 0)"
# kill switch restores legacy behaviour
mk iptv_apps conflict; : > "$T/curl.log"; export OVN_RECONCILE_ALERT_DEDUPE=0
run; run
ok "A9: OVN_RECONCILE_ALERT_DEDUPE=0 -> legacy alert every pass (2)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 2 ] && echo 1 || echo 0)"
# A10 (P2 review fix): a transient fetch failure on the only conflicted repo must NOT read as recovery (old code: false 'cleared' + state deleted -> flap)
mk shrike-notify conflict; : > "$T/curl.log"; unset OVN_RECONCILE_ALERT_DEDUPE; export OVN_RECONCILE_NOW=2000000
( cd "$T/seed/iptv_apps" && git fetch -q origin && git checkout -q -B overnight/feature origin/develop && git push -q -f origin overnight/feature )   # clear the leftover A9 conflict so shrike-notify is the only one
run
ok "A10a: fixture conflict alerted" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && [ -f "$CA" ] && echo 1 || echo 0)"
git -C "$Q/repos/shrike-notify" remote set-url origin "$T/origin/does-not-exist.git"
run
ok "A10b: fetch failure on the conflicted repo -> NO cleared note" "$([ "$(cnt 'conflict cleared')" = 0 ] && echo 1 || echo 0)"
ok "A10c: alert state kept (no flap)" "$([ -f "$CA" ] && echo 1 || echo 0)"
ok "A10d: skip is logged" "$([ "$(has $T/out.log 'recovery NOT judged')" = 1 ] && echo 1 || echo 0)"
git -C "$Q/repos/shrike-notify" remote set-url origin "$T/origin/shrike-notify.git"
( cd "$T/seed/shrike-notify" && git fetch -q origin && git checkout -q -B overnight/feature origin/develop && git push -q -f origin overnight/feature )
run
ok "A10e: after a real clean pass -> cleared note" "$([ "$(cnt 'conflict cleared')" = 1 ] && [ ! -f "$CA" ] && echo 1 || echo 0)"
# A11 (review fix): a FAILED first alert (ntfy down) must not persist dedupe state -> next pass retries
reconf(){ ( cd "$T/seed/$1" && git fetch -q origin && git checkout -q -B develop origin/develop && echo "dev$2" > f.txt && git add -A && git commit -q -m "dev$2" && git push -q origin develop \
  && git checkout -q -B overnight/feature origin/overnight/feature && echo "feat$2" > f.txt && git add -A && git commit -q -m "feat$2" && git push -q origin overnight/feature ); }   # fresh real conflict on an existing fixture repo
reconf billwatch 11; : > "$T/curl.log"; export OVN_RECONCILE_NOW=3000000; safe_rm_rf "$CA" "$CA.set"
: > "$T/curl.fail"; run
ok "A11a: alert attempted while ntfy down" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "A11b: no state persisted after failed send" "$([ ! -f "$CA" ] && echo 1 || echo 0)"
run
ok "A11c: next pass retries (2 attempts)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 2 ] && echo 1 || echo 0)"
safe_rm_rf "$T/curl.fail"; run
ok "A11d: send succeeds -> state persisted" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 3 ] && [ -f "$CA" ] && echo 1 || echo 0)"
run
ok "A11e: then suppressed" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 3 ] && echo 1 || echo 0)"
# A12 (review fix): flapping skipped repo must not re-alert. Two conflicts alerted; one repo then fails fetch (subset), then returns.
reconf gitlark 12; safe_rm_rf "$CA" "$CA.set"; : > "$T/curl.log"; export OVN_RECONCILE_NOW=4000000
run
ok "A12a: two-repo set alerted once" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
git -C "$Q/repos/gitlark" remote set-url origin "$T/origin/does-not-exist.git"; run
ok "A12b: gitlark skipped (subset set) -> no new alert" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
git -C "$Q/repos/gitlark" remote set-url origin "$T/origin/gitlark.git"; run
ok "A12c: gitlark back (same set) -> still no new alert (old code: 3)" "$([ "$(cnt 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
echo "test_reconcile_conflict_dedupe: $P passed, $F failed"; [ "$F" = 0 ]
