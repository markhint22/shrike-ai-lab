#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 6b): ovn_churn_guard.py - REMOVE/RESTORE ping-pong rule + the 1h/4-commit fast window.
# Live: xlite remove/restore ping-pong (get_faction, machine_completionist: 12 and 9 landed cycles, 21 pairs) was only parked after ~2.7h by the 3h/8-commit rule.
#  - two commits touching the SAME file within OVN_CHURN_PINGPONG_GAP_MIN (30) whose subjects read '(remove|delete|drop) ... X' and '(restore|re-add|revert) ... X'
#    for the same identifier X park the file's open items immediately (either order); 'remove X' then 'add unrelated Y' never matches;
#  - the existing oscillation test over a 1h window with OVN_CHURN_PER_HOUR (default 4) commits;
#  - kill switches OVN_CHURN_PINGPONG=off / OVN_CHURN_PER_HOUR=0.
# Pure functions over commit fixtures, one real-git end-to-end park through the wrapper, and mutation controls.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; ROOT="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W" /tmp/wt-churnguard-* 2>/dev/null' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export OVN_STATE_DIR="$W/state"; mkdir -p "$OVN_STATE_DIR"

# ------------------------------------------------------------------ C. churn guard ------------------------------------------------------------------
cat > "$W/pp.py" <<'EOPY'
import os, sys, json
sys.path.insert(0, os.path.join(os.environ["S"]))
os.environ.setdefault("OVN_STATE_DIR", os.environ["W"] + "/pstate")
import ovn_churn_guard as g

NOW = 1_800_000_000
def C(sha, mins_ago, subj, f="scripts/battle/enemy_faction_map.gd", old="a", new="b"):
    return {"sha": sha, "t": NOW - mins_ago * 60, "s": subj, "f": {f: (old, new, "M")}}
def kinds(cs):
    return {c["file"]: c["kind"] for c in cs}
out = {}
# get_faction ping-pong (the live 2026-10-07 shape)
out["gf"] = kinds(g.detect_pingpong([C("1", 50, "fix: remove get_faction function from enemy_faction_map"), C("2", 40, "fix: restore get_faction in enemy_faction_map")], NOW))
# machine_completionist: delete -> re-add
out["mc"] = kinds(g.detect_pingpong([C("1", 30, "test: delete machine_completionist assertion"), C("2", 12, "fix: re-add machine_completionist assertion")], NOW))
# restore first, then remove (either order)
out["rev_order"] = kinds(g.detect_pingpong([C("1", 30, "fix: restore get_faction default"), C("2", 12, "fix: drop get_faction default again")], NOW))
# 'revert removal of X'
out["revert"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove get_faction"), C("2", 12, "revert: undo removal of get_faction")], NOW))
# NEGATIVES
out["neg_unrelated_add"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove get_faction function"), C("2", 12, "feat: add shield_bonus handler")], NOW))
out["neg_other_ident"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove get_faction function"), C("2", 12, "fix: restore machine_completionist check")], NOW))
out["neg_gap"] = kinds(g.detect_pingpong([C("1", 90, "fix: remove get_faction function"), C("2", 12, "fix: restore get_faction function")], NOW))
out["neg_two_files"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove get_faction function", f="a.gd"), C("2", 12, "fix: restore get_faction function", f="b.gd")], NOW))
out["neg_same_verb"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove get_faction function"), C("2", 12, "fix: delete get_faction helper")], NOW))
out["neg_bookkeeping"] = kinds(g.detect_pingpong([C("1", 30, "chore(queue): remove get_faction item"), C("2", 12, "chore(queue): restore get_faction item")], NOW))
out["neg_generic_words"] = kinds(g.detect_pingpong([C("1", 30, "fix: remove unused import"), C("2", 12, "fix: restore unused import")], NOW))
# the fast window: 4 oscillating commits in < 1h, same blobs A->B->A->B->A (needs R>=3 and repeated subjects)
osc = [C(str(i), 50 - i * 10, "fix: tweak faction default", f="scripts/battle/x.gd", old=("a" if i % 2 else "b"), new=("b" if i % 2 else "a")) for i in range(1, 5)]
out["fast_default_3h"] = [c["file"] for c in g.detect(osc, NOW)]
out["fast_1h"] = [c["file"] for c in g.detect(osc, NOW, window_h=1, min_n=4, pair_min=4)]
fwd = [C(str(i), 50 - i * 10, "feat: add capability number %d to the module" % i, f="scripts/battle/x.gd", old="v%d" % (i - 1), new="v%d" % i) for i in range(1, 5)]
out["fast_legit_forward"] = [c["file"] for c in g.detect(fwd, NOW, window_h=1, min_n=4, pair_min=4)]
# merge keeps the established detector's numbers, orders by n desc
m = g.merge_churners([{"file": "a", "n": 9, "kind": "file"}], [{"file": "a", "n": 2, "kind": "x"}, {"file": "b", "n": 3, "kind": "y"}])
out["merge"] = [(c["file"], c["n"]) for c in m]
# tag text carries the churner's own window
txt = "## Next\n- [ ] [T2] scripts/battle/x.gd — thing\n"
new, parked, _ = g.plan_parking(txt, [{"file": "scripts/battle/x.gd", "n": 4, "kind": "file", "win": 1, "aliases": []}], 3, 10)
out["tag_win"] = "touched by 4 fleet commits in 1h" in new
out["consts"] = [g.PER_HOUR, g.PINGPONG, g.PINGPONG_GAP_S]
print(json.dumps(out, sort_keys=True))
EOPY
PPOUT="$(S="$S" W="$W" python3 "$W/pp.py" 2>&1)"
pj(){ printf '%s' "$PPOUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d$1))" 2>/dev/null; }
ok "C: the fixture module imports and prints JSON" "case \"\$PPOUT\" in '{'*) true;; *) echo \"\$PPOUT\" >&2; false;; esac"
ok "C: get_faction remove -> restore within 30 min is flagged (kind remove/restore(get_faction))" "[ \"\$(pj \"['gf']\")\" = '{\"scripts/battle/enemy_faction_map.gd\": \"remove/restore(get_faction)\"}' ]"
ok "C: machine_completionist delete -> re-add is flagged" "case \"\$(pj \"['mc']\")\" in *'remove/restore(machine_completionist)'*) true;; *) false;; esac"
ok "C: restore -> remove (reverse order) is flagged too" "case \"\$(pj \"['rev_order']\")\" in *'remove/restore(get_faction)'*) true;; *) false;; esac"
ok "C: 'revert: undo removal of get_faction' counts as the restore side" "case \"\$(pj \"['revert']\")\" in *'remove/restore(get_faction)'*) true;; *) false;; esac"
ok "C NEGATIVE: remove get_faction then add unrelated shield_bonus => nothing" "[ \"\$(pj \"['neg_unrelated_add']\")\" = '{}' ]"
ok "C NEGATIVE: remove get_faction then restore a DIFFERENT identifier => nothing" "[ \"\$(pj \"['neg_other_ident']\")\" = '{}' ]"
ok "C NEGATIVE: the two commits are 78 minutes apart (> 30) => nothing" "[ \"\$(pj \"['neg_gap']\")\" = '{}' ]"
ok "C NEGATIVE: same identifier but different files => nothing" "[ \"\$(pj \"['neg_two_files']\")\" = '{}' ]"
ok "C NEGATIVE: remove + remove (no restore side) => nothing" "[ \"\$(pj \"['neg_same_verb']\")\" = '{}' ]"
ok "C NEGATIVE: chore(queue) bookkeeping subjects are ignored" "[ \"\$(pj \"['neg_bookkeeping']\")\" = '{}' ]"
ok "C NEGATIVE: boilerplate words only ('remove unused import' / 'restore unused import') are not an identifier" "[ \"\$(pj \"['neg_generic_words']\")\" = '{}' ]"
ok "C: 4 oscillating commits in 1h are NOT seen by the old 3h/8-commit rule" "[ \"\$(pj \"['fast_default_3h']\")\" = '[]' ]"
ok "C: ... but ARE seen by the new 1h window with OVN_CHURN_PER_HOUR=4" "[ \"\$(pj \"['fast_1h']\")\" = '[\"scripts/battle/x.gd\"]' ]"
ok "C NEGATIVE: a legit staged feature (4 forward-only commits in 1h) is not flagged" "[ \"\$(pj \"['fast_legit_forward']\")\" = '[]' ]"
ok "C: merge_churners keeps the first detector's entry and orders by n desc" "[ \"\$(pj \"['merge']\")\" = '[[\"a\", 9], [\"b\", 3]]' ]"
ok "C: the park tag uses the churner's own window ('in 1h')" "[ \"\$(pj \"['tag_win']\")\" = true ]"
ok "C: defaults are PER_HOUR=4, ping-pong on, gap 1800s" "[ \"\$(pj \"['consts']\")\" = '[4, true, 1800]' ]"
KS="$(S="$S" W="$W" OVN_CHURN_PER_HOUR=0 OVN_CHURN_PINGPONG=off OVN_CHURN_PINGPONG_GAP_MIN=10 python3 -c "
import os,sys; sys.path.insert(0, os.environ['S']); import ovn_churn_guard as g; print(g.PER_HOUR, g.PINGPONG, g.PINGPONG_GAP_S)")"
ok "C: kill switches: OVN_CHURN_PER_HOUR=0, OVN_CHURN_PINGPONG=off, OVN_CHURN_PINGPONG_GAP_MIN=10 are honoured" "[ \"\$KS\" = '0 False 600' ]"

# ---- C. end-to-end through the real wrapper: a ping-pong of just TWO commits parks the open item, a control repo with an unrelated pair does not ----
T="$W/e2e"; mkdir -p "$T/repos" "$T/state" "$T/logs"; NOW="$(date +%s)"
mkrepo(){ # name
  local n="$1" b="$T/origin_$1.git" w="$T/work_$1"
  git init -q --bare "$b"; git -C "$b" symbolic-ref HEAD refs/heads/overnight/feature
  git clone -q "$b" "$w" 2>/dev/null; git -C "$w" checkout -q -b overnight/feature
  printf '%s\n' '# Progress' '- [ ] [T2] scripts/battle/enemy_faction_map.gd — Make get_faction tolerant. VERIFY: `true`' '- [ ] [T2] scripts/battle/y.gd — Unrelated.' > "$w/OVERNIGHT_PROGRESS.md"
  mkdir -p "$w/scripts/battle"; printf 'v=0\n' > "$w/scripts/battle/enemy_faction_map.gd"
  git -C "$w" add -A; GIT_COMMITTER_DATE="$((NOW-20000)) +0000" GIT_AUTHOR_DATE="$((NOW-20000)) +0000" git -C "$w" commit -q -m "chore: init"
  git -C "$w" push -q origin overnight/feature 2>/dev/null
  git clone -q "$b" "$T/repos/$n" 2>/dev/null; git -C "$T/repos/$n" checkout -q overnight/feature
}
cmt(){ # repo mins_ago subject content
  local w="$T/work_$1"
  printf '%s\n' "$4" > "$w/scripts/battle/enemy_faction_map.gd"; git -C "$w" add -A
  GIT_COMMITTER_DATE="$((NOW-$2*60)) +0000" GIT_AUTHOR_DATE="$((NOW-$2*60)) +0000" git -C "$w" commit -q -m "$3"; git -C "$w" push -q origin overnight/feature 2>/dev/null
}
mkrepo pp; cmt pp 40 "fix: remove get_faction function from enemy_faction_map" "v=1"; cmt pp 25 "fix: restore get_faction in enemy_faction_map" "v=2"
mkrepo ctl; cmt ctl 40 "fix: remove get_faction function from enemy_faction_map" "v=1"; cmt ctl 25 "feat: add shield_bonus handler" "v=2"
runguard(){ env OVN_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_STATE_DIR="$T/state" OVN_CHURN_LOG="$T/logs/cg.log" OVN_CHURN_LOCK_WAIT=2 NTFY_SERVER=http://127.0.0.1:9/x "$@" bash "$S/ovn_churn_guard.sh" </dev/null >/dev/null 2>&1; echo $?; }
progof(){ git -C "$T/origin_$1.git" show overnight/feature:OVERNIGHT_PROGRESS.md; }
rc="$(runguard OVN_CHURN_REPOS="pp ctl")"
ok "C e2e: wrapper exits 0" "[ '$rc' = 0 ]"
ok "C e2e: the 2-commit ping-pong parks the open item naming the file (AUTO-SKIP churn-loop, recovery:none)" "[ \"\$(progof pp | grep -c 'AUTO-SKIP churn-loop: scripts/battle/enemy_faction_map.gd touched by 2 fleet commits in 3h - needs Claude; recovery:none')\" = 1 ]"
ok "C e2e: the unrelated item in the same repo is untouched" "progof pp | grep -qF -- '- [ ] [T2] scripts/battle/y.gd — Unrelated.'"
ok "C e2e NEGATIVE: 'remove X' then 'add unrelated Y' parks nothing" "[ \"\$(progof ctl | grep -c AUTO-SKIP)\" = 0 ]"
ok "C e2e: with OVN_CHURN_PINGPONG=off the same ping-pong is not parked (control)" "mkrepo pp2; cmt pp2 40 'fix: remove get_faction function from enemy_faction_map' v=1; cmt pp2 25 'fix: restore get_faction in enemy_faction_map' v=2; [ \"\$(runguard OVN_CHURN_REPOS=pp2 OVN_CHURN_PINGPONG=off)\" = 0 ] && [ \"\$(progof pp2 | grep -c AUTO-SKIP)\" = 0 ]"


# ------------------------------------------------------------------ MUTATION controls ------------------------------------------------------------------
cd "$W" || exit 1
python3 - "$S" "$W" <<'PY'
import sys, os
S, W = sys.argv[1], sys.argv[2]
def mut(a, b, name):
    s = open(S + "/ovn_churn_guard.py").read()
    assert s.count(a) == 1, a
    os.makedirs(W + "/" + name, exist_ok=True)
    open(W + "/" + name + "/ovn_churn_guard.py", "w").write(s.replace(a, b))
mut('                shared = ids1 & ids2', '                shared = set()', "mc_shared")
mut('                if k2 is None or k2 == k1 or not ids2:', '                if k2 is None or not ids2:', "mc_samekind")
mut('                if c2["t"] - c1["t"] > gap_s:\n                    break', '                pass', "mc_gap")
mut('sides = [(c, k, ids - own) for', 'sides = [(c, k, ids) for', "mc_own")
PY
mutpp(){ ( cd "$W" && python3 -c "
import sys, os; sys.path.insert(0, '$1'); os.environ.setdefault('OVN_STATE_DIR', '$W/pstate'); import ovn_churn_guard as g
N=1_800_000_000
def C(sha, m, s, f='a.gd'): return {'sha': sha, 't': N-m*60, 's': s, 'f': {f: ('a','b','M')}}
print(len(g.detect_pingpong($2, N)))" ); }
PAIR="[C('1',30,'fix: remove get_faction function'), C('2',12,'fix: restore get_faction function')]"
SAMEKIND="[C('1',30,'fix: remove get_faction function'), C('2',12,'fix: delete get_faction helper')]"
FARGAP="[C('1',170,'fix: remove get_faction function'), C('2',12,'fix: restore get_faction function')]"
FILENAME="[C('1',30,'fix: remove helper from enemy_faction_map', 'scripts/enemy_faction_map.gd'), C('2',12,'fix: restore tracing in enemy_faction_map', 'scripts/enemy_faction_map.gd')]"
ok "MUTATION sanity: the real module flags the pair (1), ignores same-kind (0), ignores a 158-minute gap (0), ignores a shared FILE-NAME token (0)" "[ \"\$(mutpp '$S' \"$PAIR\")\" = 1 ] && [ \"\$(mutpp '$S' \"$SAMEKIND\")\" = 0 ] && [ \"\$(mutpp '$S' \"$FARGAP\")\" = 0 ] && [ \"\$(mutpp '$S' \"$FILENAME\")\" = 0 ]"
ok "MUTATION: without the shared-identifier test the get_faction pair is no longer found (the positive tests would fail)" "[ \"\$(mutpp '$W/mc_shared' \"$PAIR\")\" = 0 ]"
ok "MUTATION: without the opposite-kind test 'remove X' + 'delete X' is wrongly flagged" "[ \"\$(mutpp '$W/mc_samekind' \"$SAMEKIND\")\" = 1 ]"
ok "MUTATION: without the 30-minute gap test a 158-minute-apart pair is wrongly flagged" "[ \"\$(mutpp '$W/mc_gap' \"$FARGAP\")\" = 1 ]"
ok "MUTATION: without the file-name exclusion two subjects that merely share the file name are wrongly flagged" "[ \"\$(mutpp '$W/mc_own' \"$FILENAME\")\" = 1 ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
