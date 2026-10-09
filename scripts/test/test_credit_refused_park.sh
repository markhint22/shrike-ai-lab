#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity items 6a + 7): credit-refusal cap and the VERIFY gate on the credit paths that ran none.
#  A. lib_auto_credit.sh counts refusals that happen AFTER the path matched (no VERIFY / placeholder / failing VERIFY) in state/credit_refused/<repo>.<item hash>;
#     path-mismatch refusals (basename-sharing innocents) are NOT counted; a credit deletes the counter.
#  B. ovn_item_guard.sh parks the item at OVN_REFUSED_PARK_AT (default 2) with '[AUTO-SKIP after N credit refusals: <reason>]'; kill switch, threshold, stale counters.
#  D. (item 7) ovn_credit_verify_gate / ovn_bookkeeping_verify_gate: the scout ALREADY-DONE credit and the DONE:-trailer bookkeeping credit run the item's own VERIFY
#     and are refused on FAIL under OVN_VERIFY_GATE_MODE=enforce (default), only logged under shadow; NO_VERIFY keeps today's behaviour.
# (the churn-guard half of item 6 lives in test_churn_remove_restore.sh). Mutation controls at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; ROOT="$(cd "$HERE/../.." && pwd)"; RUN="$S/../run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # portable in-place sed (BSD on the Mac, GNU on the box)
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
export OVN_STATE_DIR="$W/state"; STATE="$OVN_STATE_DIR"; mkdir -p "$STATE"
emit_alert(){ :; }
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_path_normalize.sh"; . "$S/lib_verify_clause.sh"; . "$S/lib_auto_credit.sh"
GUARD="$S/ovn_item_guard.sh"

# ------------------------------------------------------------------ A. the counter ------------------------------------------------------------------
R="$W/repo"; mkdir -p "$R/app" "$R/models" "$R/routers"; cd "$R" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
for f in a b c p; do printf 'v=0\n' > "app/$f.py"; done
printf 'v=0\n' > models/sub.py; printf 'v=0\n' > routers/sub.py
cat > OVERNIGHT_PROGRESS.md <<'EOP'
## Next Steps
- [ ] [T2] app/a.py — item without any VERIFY clause.
- [ ] [T2] app/b.py — item with a passing VERIFY. VERIFY: `true`
- [ ] [T2] app/c.py — item whose VERIFY fails. VERIFY: `false`
- [ ] [T2] app/p.py — item whose file is only a placeholder stub. VERIFY: `true`
- [ ] [T2] models/sub.py — a different file that merely shares the basename sub.py. VERIFY: `true`
EOP
git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"
cycle(){  # touch every file (one commit) and run the REAL auto-credit. $1 = content tag; $2 = the file the cycle WORKED (the scout verdict names it in the task log, which
          # is how ovn_resolve_top_item - the harness's "worked item" resolver - finds the item; only that item's refusals are counted toward a park)
  BEFORE="$(git rev-parse HEAD)"
  for f in a b c; do printf 'v=%s\n' "$1" > "app/$f.py"; done
  printf '"""Placeholder - the implement step fills this in."""\n# cycle %s\n' "$1" > app/p.py
  printf 'v=%s\n' "$1" > routers/sub.py
  git add -A; git commit -q -m "cycle $1"; AFTER="$(git rev-parse HEAD)"
  printf 'VERDICT: PROCEED\nFILES: %s\n' "${2:-app/a.py}" > "$W/task.log"; ovn_auto_credit "$BEFORE" "$AFTER" OVERNIGHT_PROGRESS.md "$W/task.log" || true
}
hash_of(){ printf 'repo.%s' "$(ovn_item_hash "$(grep -F -- "$1" OVERNIGHT_PROGRESS.md | head -1)")"; }   # counter files are keyed "<repo>.<item hash>" (repo = basename of the repo dir: $R is .../repo)
cnt(){ local f="$STATE/credit_refused/$(hash_of "$1")"; [ -f "$f" ] && sed -n 1p "$f" || echo none; }
rsn(){ local f="$STATE/credit_refused/$(hash_of "$1")"; [ -f "$f" ] && sed -n 2p "$f" || echo none; }
HA="$(hash_of 'app/a.py —')"; HB="$(hash_of 'app/b.py —')"; HC="$(hash_of 'app/c.py —')"; HP="$(hash_of 'app/p.py —')"; HS="$(hash_of 'models/sub.py —')"
cycle 1 app/a.py
ok "A: no-VERIFY refusal is counted (1) with the reason 'no VERIFY clause' (a.py is the item this cycle worked)" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HA')\" = 1 ] && [ \"\$(sed -n 2p '$STATE/credit_refused/$HA')\" = 'no VERIFY clause' ]"
ok "A: the counter file stores the item line (3rd line) for the guard to find it again" "[ \"\$(sed -n 3p '$STATE/credit_refused/$HA')\" = '- [ ] [T2] app/a.py — item without any VERIFY clause.' ]"
ok "A NEGATIVE: the credited item (b.py, VERIFY passes) has NO counter" "[ ! -e '$STATE/credit_refused/$HB' ]"
ok "A NEGATIVE: path-mismatch refusal (models/sub.py vs the touched routers/sub.py) is logged but NOT counted" "[ ! -e '$STATE/credit_refused/$HS' ] && [ \"\$(grep -c 'path mismatch' '$W/task.log')\" -ge 1 ]"
ok "A: b.py really was credited by the same call (the counter logic did not disturb crediting)" "grep -q '^- \\[x\\] \\[T2\\] app/b.py' OVERNIGHT_PROGRESS.md"
ok "A NEGATIVE (unworked siblings): c.py (VERIFY red) and p.py (placeholder) were refused in the same call but the cycle worked only a.py => NO counter for them" "[ ! -e '$STATE/credit_refused/$HC' ] && [ ! -e '$STATE/credit_refused/$HP' ] && [ \"\$(grep -c 'did not work that item' '$W/task.log')\" -ge 2 ]"
OVN_REFUSED_WORKED_ONLY=off cycle 1x app/a.py
ok "A CONTROL (OVN_REFUSED_WORKED_ONLY=off = the old behaviour): the same refusals DO count for the unworked siblings" "[ -e '$STATE/credit_refused/$HC' ] && [ -e '$STATE/credit_refused/$HP' ]"
rm -f "$STATE/credit_refused/$HC" "$STATE/credit_refused/$HP"; rm -f "$STATE/credit_refused/$HA"
# a clean slate for the counting rounds: every item is worked in turn (same commits, a different scout verdict each round)
cycle 1a app/a.py; cycle 1c app/c.py; cycle 1p app/p.py
ok "A: failing-VERIFY refusal is counted with reason 'VERIFY failed' when c.py is the worked item" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HC')\" = 1 ] && [ \"\$(sed -n 2p '$STATE/credit_refused/$HC')\" = 'VERIFY failed' ]"
ok "A: placeholder-stub refusal is counted with reason 'placeholder stub' when p.py is the worked item" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HP')\" = 1 ] && [ \"\$(sed -n 2p '$STATE/credit_refused/$HP')\" = 'placeholder stub' ]"
ok "A: a.py's counter is 1 again after its own round (the siblings' rounds did not touch it)" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HA')\" = 1 ]"
cycle 2a app/a.py; cycle 2c app/c.py; cycle 2p app/p.py
ok "A: a second refusal of the same item increments the counter to 2" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HA')\" = 2 ] && [ \"\$(sed -n 1p '$STATE/credit_refused/$HC')\" = 2 ]"
ok "A: the placeholder item's counter is 2 as well" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HP')\" = 2 ]"

# ------------------------------------------------------------------ B. the guard parks ------------------------------------------------------------------
# kill switch and threshold first (nothing parked), then the real park
OVN_REFUSED_PARK_AT=0 bash "$GUARD" "$R" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "B: OVN_REFUSED_PARK_AT=0 disables the park (nothing tagged, counters kept)" "[ \"\$(grep -c 'credit refusals' OVERNIGHT_PROGRESS.md)\" = 0 ] && [ -e '$STATE/credit_refused/$HA' ]"
OVN_REFUSED_PARK_AT=3 bash "$GUARD" "$R" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "B: threshold 3 with counters at 2 parks nothing" "[ \"\$(grep -c 'credit refusals' OVERNIGHT_PROGRESS.md)\" = 0 ]"
bash "$GUARD" "$R" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "B: default threshold 2 parks the no-VERIFY item with '[AUTO-SKIP after 2 credit refusals: no VERIFY clause]'" "grep -qF -- '- [ ] [AUTO-SKIP after 2 credit refusals: no VERIFY clause] [T2] app/a.py' OVERNIGHT_PROGRESS.md"
ok "B: ... the failing-VERIFY item with 'VERIFY failed' and the placeholder item with 'placeholder stub'" "grep -qF -- '[AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] app/c.py' OVERNIGHT_PROGRESS.md && grep -qF -- '[AUTO-SKIP after 2 credit refusals: placeholder stub] [T2] app/p.py' OVERNIGHT_PROGRESS.md"
ok "B NEGATIVE: the credited item and the basename-sharing innocent are untouched" "grep -q '^- \\[x\\] \\[T2\\] app/b.py' OVERNIGHT_PROGRESS.md && grep -qF -- '- [ ] [T2] models/sub.py —' OVERNIGHT_PROGRESS.md"
ok "B: the counters are consumed by the park" "[ ! -e '$STATE/credit_refused/$HA' ] && [ ! -e '$STATE/credit_refused/$HC' ]"
ok "B: the park is committed with a chore(queue) pathspec commit touching only OVERNIGHT_PROGRESS.md" "[ \"\$(git log -1 --format=%s)\" = 'chore(queue): park 3 item(s) after 2+ credit refusals (green commits the auto-credit could not tick)' ] && [ \"\$(git show --name-only --format= HEAD)\" = OVERNIGHT_PROGRESS.md ]"
ok "B: the park tag is in the pickers' exclusion set (AUTO-SKIP)" "[ -z \"\$(grep -E '^- \\[ \\]' OVERNIGHT_PROGRESS.md | grep -vE 'AUTO-SKIP' | grep -F 'app/a.py')\" ]"
# stale counter (item already credited/edited/gone) is dropped, not parked
mkdir -p "$STATE/credit_refused"; printf '5\nno VERIFY clause\n- [ ] [T2] app/gone.py — an item that no longer exists\n' > "$STATE/credit_refused/repo.deadbeefdeadbeefdeadbeefdeadbeef"
bash "$GUARD" "$R" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "B: a stale counter whose item no longer exists is deleted and nothing is tagged" "[ ! -e '$STATE/credit_refused/repo.deadbeefdeadbeefdeadbeefdeadbeef' ] && [ \"\$(grep -c 'app/gone.py' OVERNIGHT_PROGRESS.md)\" = 0 ]"
# credit deletes the counter (lib) and the item-hash marker deletes it too (guard)
printf -- '- [ ] [T2] app/z.py — will fail once then be credited. VERIFY: `true`\n' >> OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m z
HZ="repo.$(ovn_item_hash '- [ ] [T2] app/z.py — will fail once then be credited. VERIFY: `true`')"
ovn_credit_refused_note '- [ ] [T2] app/z.py — will fail once then be credited. VERIFY: `true`' 'VERIFY failed'
ok "A: ovn_credit_refused_note writes the counter for z (1)" "[ \"\$(sed -n 1p '$STATE/credit_refused/$HZ')\" = 1 ]"
printf 'v=1\n' > app/z.py; git add -A; git commit -q -m "touch z"; Z_AFTER="$(git rev-parse HEAD)"; Z_BEFORE="$(git rev-parse HEAD~1)"
: > "$W/task.log"; ovn_auto_credit "$Z_BEFORE" "$Z_AFTER" OVERNIGHT_PROGRESS.md "$W/task.log" || true
ok "A: when the item is finally credited its counter is deleted" "grep -q '^- \\[x\\] \\[T2\\] app/z.py' OVERNIGHT_PROGRESS.md && [ ! -e '$STATE/credit_refused/$HZ' ]"
printf '1\nVERIFY failed\n- [ ] [T2] app/q.py — credited by DONE trailer\n' > "$STATE/credit_refused/repo.0123456789abcdef0123456789abcdef"
printf -- '--- auto-credit: item-hash 0123456789abcdef0123456789abcdef ---\n' > "$W/landed.log"
bash "$GUARD" "$R" 'pushed(tests:pass)' "$STATE" itemG "$W/landed.log" >/dev/null 2>&1
ok "B: an item-hash (credited) marker in the log deletes that hash's counter" "[ ! -e '$STATE/credit_refused/repo.0123456789abcdef0123456789abcdef' ]"


# ------------------------------------------------------------------ MUTATION controls (A/B) ------------------------------------------------------------------
cd "$W" || exit 1
python3 - "$S" "$W" <<'PY'
import sys
S, W = sys.argv[1], sys.argv[2]
def mut(src, a, b, out):
    s = open(src).read()
    assert s.count(a) == 1, (src, a)
    open(out, "w").write(s.replace(a, b))
mut(S + "/lib_auto_credit.sh", '                          _ovn_cr_bump "$prog" "$ln" "no VERIFY clause" ;;', '                          : ;;', W + "/m_lib.sh")
mut(S + "/ovn_item_guard.sh", '    [ "$_rn" -ge "$_rp_at" ] || continue', '    :', W + "/m_guard.sh")
mut(S + "/lib_auto_credit.sh", '      if [ "$mode" = enforce ]; then\n        [ -n "$tl" ] && echo "--- verify-gate: ${label} REFUSED', '      if false; then\n        [ -n "$tl" ] && echo "--- verify-gate: ${label} REFUSED', W + "/m_gate.sh")
PY
# lib mutant: refusal counting removed => no counter after a refusal
( . "$W/m_lib.sh"; rm -rf "$STATE/credit_refused"; R2="$W/repo2"; mkdir -p "$R2/app"; cd "$R2"; git init -q -b main; git config user.email t@t; git config user.name t
  printf 'v=0\n' > app/a.py; printf -- '- [ ] [T2] app/a.py — no verify here.\n' > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m b; B2="$(git rev-parse HEAD)"
  printf 'v=1\n' > app/a.py; git add -A; git commit -q -m c; A2="$(git rev-parse HEAD)"; : > "$W/t2.log"; ovn_auto_credit "$B2" "$A2" OVERNIGHT_PROGRESS.md "$W/t2.log" || true
  [ ! -d "$STATE/credit_refused" ] || [ -z "$(ls -A "$STATE/credit_refused" 2>/dev/null)" ] )
ok "MUTATION: with the refusal bump removed from lib_auto_credit.sh no counter is written (so test A would fail)" "[ \$? = 0 ]"
# guard mutant: threshold ignored => parks at count 1
rm -rf "$STATE/credit_refused"; mkdir -p "$STATE/credit_refused"; R3="$W/repo3"; mkdir -p "$R3"; ( cd "$R3" && git init -q -b main && git config user.email t@t && git config user.name t && printf -- '- [ ] [T2] app/m.py — mutated guard item.\n' > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i )
printf '1\nno VERIFY clause\n- [ ] [T2] app/m.py — mutated guard item.\n' > "$STATE/credit_refused/repo3.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
bash "$W/m_guard.sh" "$R3" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "MUTATION: a guard without the threshold test parks at count 1 (the real guard needs 2: sanity via the count-1 control)" "grep -q 'credit refusals' '$R3/OVERNIGHT_PROGRESS.md'"
( cd "$R3" && printf -- '- [ ] [T2] app/m.py — mutated guard item.\n' > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m reset-item ); printf '1\nno VERIFY clause\n- [ ] [T2] app/m.py — mutated guard item.\n' > "$STATE/credit_refused/repo3.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
bash "$GUARD" "$R3" 'pushed(tests:pass)' "$STATE" itemG "$W/task.log" >/dev/null 2>&1
ok "CONTROL: the real guard leaves a count-1 item alone" "[ \"\$(grep -c 'credit refusals' '$R3/OVERNIGHT_PROGRESS.md')\" = 0 ]"


# ------------------------------------------------------------------ D. item 7: VERIFY gate on the unverified credit paths ------------------------------------------------------------------
D="$W/gate"; mkdir -p "$D"; cd "$D" || exit 1
cat > prog.md <<'EOP'
- [ ] [T2] app/fail.py — VERIFY exits 1. VERIFY: `exit 1`
- [ ] [T2] app/pass.py — VERIFY exits 0. VERIFY: `exit 0`
- [ ] [T2] app/none.py — no VERIFY clause at all.
- [ ] [T2] app/unsafe.py — unsafe clause. VERIFY: `rm -rf /tmp/never-run-this`
- [ ] [T2] app/slow.py — a clause that outruns the cap. VERIFY: `sleep 5`
EOP
GL="$W/gate.log"
gate(){ : > "$GL"; ovn_credit_verify_gate "$D/prog.md" "$1" "$GL" "scout ALREADY-DONE credit"; echo $?; }
ok "D: VERIFY exits 1, enforce (default) => REFUSED (rc 1) and the task log says so" "[ \"\$(gate 1)\" = 1 ] && [ \"\$(grep -c 'verify-gate: scout ALREADY-DONE credit REFUSED at line 1' '$GL')\" = 1 ]"
ok "D: VERIFY exits 0 => credited (rc 0), nothing logged" "[ \"\$(gate 2)\" = 0 ] && [ ! -s '$GL' ]"
ok "D: NO_VERIFY keeps today's behaviour => credited (rc 0)" "[ \"\$(gate 3)\" = 0 ]"
ok "D: an unsafe clause (denylist) is not run and the credit proceeds as before (rc 0)" "[ \"\$(gate 4)\" = 0 ] && [ ! -e /tmp/never-run-this ]"
ok "D: an INDETERMINATE clause (timeout) is not a failure => credited (rc 0), logged as indeterminate" "[ \"\$(OVN_CREDIT_VERIFY_TIMEOUT=1 gate 5)\" = 0 ] && grep -q 'VERIFY indeterminate' '$GL'"
ok "D: OVN_VERIFY_GATE_MODE=shadow: the failing clause is only LOGGED ('would be REFUSED'), credit proceeds (rc 0)" "[ \"\$(OVN_VERIFY_GATE_MODE=shadow gate 1)\" = 0 ] && [ \"\$(grep -c 'would be REFUSED' '$GL')\" = 1 ]"
ok "D: the failing run is recorded in the shared shadow log by shadow_check (result=FAIL)" "grep -q 'result=FAIL' '$OVN_VERIFY_SHADOW_LOG'"
# the DONE:-trailer bookkeeping path
BK="$W/bk"; mkdir -p "$BK"; cd "$BK" || exit 1; git init -q -b main; git config user.email t@t; git config user.name t
cp "$D/prog.md" OVERNIGHT_PROGRESS.md; sedi '/never-run-this/d; /sleep 5/d' OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m init
sedi 's/^- \[ \] /- [x] /' OVERNIGHT_PROGRESS.md      # update_progress.py ticked all three on DONE: trailers
: > "$W/bk.log"; N="$(ovn_bookkeeping_verify_gate OVERNIGHT_PROGRESS.md "$W/bk.log")"
ok "D: bookkeeping gate un-ticks only the item whose VERIFY fails (reports 1 refused)" "[ '$N' = 1 ] && grep -q '^- \\[ \\] \\[T2\\] app/fail.py' OVERNIGHT_PROGRESS.md && grep -q '^- \\[x\\] \\[T2\\] app/pass.py' OVERNIGHT_PROGRESS.md && grep -q '^- \\[x\\] \\[T2\\] app/none.py' OVERNIGHT_PROGRESS.md"
ok "D: ... and logs the refusal under 'DONE-trailer credit'" "[ \"\$(grep -c 'verify-gate: DONE-trailer credit REFUSED' '$W/bk.log')\" = 1 ]"
sedi 's/^- \[ \] /- [x] /' OVERNIGHT_PROGRESS.md; : > "$W/bk.log"; N="$(OVN_VERIFY_GATE_MODE=shadow ovn_bookkeeping_verify_gate OVERNIGHT_PROGRESS.md "$W/bk.log")"
ok "D: shadow mode: nothing un-ticked (0 refused), the would-refuse line is logged" "[ '$N' = 0 ] && [ \"\$(grep -c '^- \\[x\\]' OVERNIGHT_PROGRESS.md)\" = 3 ] && [ \"\$(grep -c 'would be REFUSED' '$W/bk.log')\" = 1 ]"
git checkout -q -- OVERNIGHT_PROGRESS.md; N="$(ovn_bookkeeping_verify_gate OVERNIGHT_PROGRESS.md "$W/bk.log")"
ok "D: control: a working tree with nothing newly ticked refuses nothing" "[ '$N' = 0 ]"
# run_overnight.sh wiring: the gate runs BEFORE the credit sed / commit
LG="$(grep -n 'ovn_credit_verify_gate OVERNIGHT_PROGRESS.md "\$_ad_ln"' "$RUN" | head -1 | cut -d: -f1)"; LS="$(grep -n 'already-done, scout-verified) /' "$RUN" | head -1 | cut -d: -f1)"
ok "D wiring: the scout ALREADY-DONE credit calls ovn_credit_verify_gate before it ticks the item" "[ -n '$LG' ] && [ -n '$LS' ] && [ '$LG' -lt '$LS' ]"
ok "D wiring: the DONE-trailer bookkeeping runs ovn_bookkeeping_verify_gate before its commit" "[ \"\$(grep -c '_bk_refused=\"\$(ovn_bookkeeping_verify_gate OVERNIGHT_PROGRESS.md \"\$task_log\")\"' '$RUN')\" = 1 ]"
# MUTATION: with the enforce branch disabled the failing item is credited
cd "$D" || exit 1
ok "MUTATION: with the enforce branch removed from ovn_credit_verify_gate the failing item is (wrongly) credited, rc 0" "[ \"\$( ( . '$W/m_gate.sh'; : > '$GL'; ovn_credit_verify_gate '$D/prog.md' 1 '$GL' x; echo \$? ) )\" = 0 ]"
ok "MUTATION sanity: the real gate refuses the same item (rc 1)" "[ \"\$(gate 1)\" = 1 ]"

# ------------------------------------------------------------------ E. per-repo keying (round-3 fix): state/credit_refused is SHARED by every repo ------------------------------------------------------------------
# Live shape: repo B's item hit its 2nd credit refusal; BEFORE B's own guard ran, the guard ran for repo A. A's progress file does not contain B's item line, so the old
# stale-counter rule (`[ -z "$_rl" ] && rm -f`) deleted B's counter and B's item was never parked.
E="$W/shared_state"; mkdir -p "$E/state" "$E/repoA" "$E/repoB"; ES="$E/state"
for r in repoA repoB; do ( cd "$E/$r" && git init -q -b main && git config user.email t@t && git config user.name t ); done
printf -- '- [ ] [T2] app/a1.py — item of repo A, no verify.\n' > "$E/repoA/OVERNIGHT_PROGRESS.md"
printf -- '- [ ] [T2] app/b1.py — item of repo B, no verify.\n- [ ] [T2] app/shared.py — an item whose text is identical in both repos.\n' > "$E/repoB/OVERNIGHT_PROGRESS.md"
printf -- '- [ ] [T2] app/shared.py — an item whose text is identical in both repos.\n' >> "$E/repoA/OVERNIGHT_PROGRESS.md"
for r in repoA repoB; do ( cd "$E/$r" && git add -A && git commit -q -m i ); done
BLINE="$(sed -n 1p "$E/repoB/OVERNIGHT_PROGRESS.md")"; SLINE="$(sed -n 2p "$E/repoB/OVERNIGHT_PROGRESS.md")"
( cd "$E/repoB" && OVN_STATE_DIR="$ES" ovn_credit_refused_note "$BLINE" 'no VERIFY clause' "$E/repoB/OVERNIGHT_PROGRESS.md" && OVN_STATE_DIR="$ES" ovn_credit_refused_note "$BLINE" 'no VERIFY clause' "$E/repoB/OVERNIGHT_PROGRESS.md" )
KB="$ES/credit_refused/repoB.$(ovn_item_hash "$BLINE")"
ok "E: the counter is keyed by repo ('repoB.<hash>') and holds the count 2" "[ -f '$KB' ] && [ \"\$(sed -n 1p '$KB')\" = 2 ]"
: > "$W/e.log"; bash "$GUARD" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "E REGRESSION: a guard call for repo A neither deletes nor parks repo B's at-threshold counter" "[ -f '$KB' ] && [ \"\$(sed -n 1p '$KB')\" = 2 ] && [ \"\$(grep -c 'credit refusals' '$E/repoB/OVERNIGHT_PROGRESS.md')\" = 0 ] && [ \"\$(grep -c 'credit refusals' '$E/repoA/OVERNIGHT_PROGRESS.md')\" = 0 ]"
bash "$GUARD" "$E/repoB" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "E: the owning repo's guard then parks B's item and consumes the counter" "grep -qF -- '[AUTO-SKIP after 2 credit refusals: no VERIFY clause] [T2] app/b1.py' '$E/repoB/OVERNIGHT_PROGRESS.md' && [ ! -e '$KB' ]"
# identical item text in two repos => two independent counters (a bare-hash key would merge them)
( OVN_STATE_DIR="$ES" ovn_credit_refused_note "$SLINE" 'VERIFY failed' "$E/repoA/OVERNIGHT_PROGRESS.md"; OVN_STATE_DIR="$ES" ovn_credit_refused_note "$SLINE" 'VERIFY failed' "$E/repoB/OVERNIGHT_PROGRESS.md"; OVN_STATE_DIR="$ES" ovn_credit_refused_note "$SLINE" 'VERIFY failed' "$E/repoB/OVERNIGHT_PROGRESS.md" )
HS2="$(ovn_item_hash "$SLINE")"
ok "E: identical item text in two repos keeps two separate counters (A=1, B=2)" "[ \"\$(sed -n 1p '$ES/credit_refused/repoA.$HS2')\" = 1 ] && [ \"\$(sed -n 1p '$ES/credit_refused/repoB.$HS2')\" = 2 ]"
OVN_STATE_DIR="$ES" ovn_credit_refused_clear "$SLINE" "$E/repoA/OVERNIGHT_PROGRESS.md"
ok "E: crediting the item in repo A clears only A's counter" "[ ! -e '$ES/credit_refused/repoA.$HS2' ] && [ -f '$ES/credit_refused/repoB.$HS2' ]"
printf -- '--- auto-credit: item-hash %s ---\n' "$HS2" > "$W/e_landed.log"
bash "$GUARD" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e_landed.log" >/dev/null 2>&1
ok "E: an item-hash landing marker seen by repo A's guard does not clear repo B's counter for the same hash" "[ -f '$ES/credit_refused/repoB.$HS2' ]"
bash "$GUARD" "$E/repoB" 'pushed(tests:pass)' "$ES" itemE "$W/e_landed.log" >/dev/null 2>&1
ok "E: ... and the same marker seen by repo B's guard clears B's counter" "[ ! -e '$ES/credit_refused/repoB.$HS2' ]"
# a relative progress path resolves to the repo dir name (the lib is called with a relative OVERNIGHT_PROGRESS.md in some paths)
( cd "$E/repoA" && OVN_STATE_DIR="$ES" ovn_credit_refused_note "$SLINE" 'VERIFY failed' OVERNIGHT_PROGRESS.md )
ok "E: a relative progress path is keyed by the repo directory name, not '.'" "[ -f '$ES/credit_refused/repoA.$HS2' ] && [ -z \"\$(ls '$ES/credit_refused' | grep -E '^[._]\\.')\" ]"
# bare-hash (pre-per-repo) counters are ownerless: never parked, aged out after a day
printf '9\nno VERIFY clause\n%s\n' "$BLINE" > "$ES/credit_refused/cafebabecafebabecafebabecafebabe"
bash "$GUARD" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "E: a fresh bare-hash counter is left alone by every guard" "[ -f '$ES/credit_refused/cafebabecafebabecafebabecafebabe' ]"
touch -t 202001010000 "$ES/credit_refused/cafebabecafebabecafebabecafebabe"
bash "$GUARD" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "E: ... and an old one is deleted without parking anything" "[ ! -e '$ES/credit_refused/cafebabecafebabecafebabecafebabe' ] && [ \"\$(grep -c 'credit refusals' '$E/repoA/OVERNIGHT_PROGRESS.md')\" = 0 ]"
# MUTATION: the old guard (every counter in the shared dir, stale => delete) loses repo B's park
python3 - "$S" "$W" <<'PY'
import sys
S, W = sys.argv[1], sys.argv[2]
s = open(S + "/ovn_item_guard.sh").read()
a = 'for _rf in "$state/credit_refused/${_rp_repo}."*; do'
assert s.count(a) == 1
open(W + "/m_guard_old.sh", "w").write(s.replace(a, 'for _rf in "$state/credit_refused"/*; do'))
PY
printf '2\nno VERIFY clause\n%s\n' "$SLINE" > "$ES/credit_refused/repoZ.00000000000000000000000000000001"
printf -- '- [ ] [T2] app/other.py — nothing to do with repo Z.\n' > "$E/repoA/OVERNIGHT_PROGRESS.md"; ( cd "$E/repoA" && git add -A && git commit -q -m other )
bash "$W/m_guard_old.sh" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "MUTATION: the old all-counters loop deletes another repo's at-threshold counter (the E REGRESSION assertion would fail)" "[ ! -e '$ES/credit_refused/repoZ.00000000000000000000000000000001' ]"
printf '2\nno VERIFY clause\n%s\n' "$SLINE" > "$ES/credit_refused/repoZ.00000000000000000000000000000001"
bash "$GUARD" "$E/repoA" 'pushed(tests:pass)' "$ES" itemE "$W/e.log" >/dev/null 2>&1
ok "MUTATION sanity: the real guard leaves the same repoZ counter alone" "[ -f '$ES/credit_refused/repoZ.00000000000000000000000000000001' ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
