#!/usr/bin/env bash
# QA enforcement plumbing (2026-10-02): the REAL branch_hygiene.sh against throwaway bare origins with STUB gates (QA_GATES_DIR).
# Covers: shadow default unchanged, enforce+FAIL blocks and lands only the clean prefix, enforce+UNVERIFIED/FLAG/PASS merges, nothing-landable =
# 'QA-blocked' clean exit, alert written ONCE, per-gate flip file, rollback (shadow/off/kill switch/env), mode() hardening, cron-style invocation.
# Nothing real is touched or pushed; curl is a stub; OVN_QA_SHADOW=off so the real shadow gates never launch.
export OVN_QA_SHADOW=off
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
BH="${BH_UNDER_TEST:-$Q/branch_hygiene.sh}"; [ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
[ -f "$Q/qa/qa_enforce_run.py" ] && [ -f "$Q/qa/qa_enforce.sh" ] || { echo "  SKIP: qa enforcement files not installed"; exit 0; }
for t in flock timeout jq python3; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(mktemp -d)"; export T; trap 'rm -rf "$T"' EXIT
REALGIT="$(command -v git)"; export REALGIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
export HOME="$T/home"; export STATE_DIR="$T/state"; export REPORT_FILE="$T/report.md"; OUT="$T/out.log"
export QA_GATES_DIR="$T/gates" OVN_XDIST_REPOS=none NTFY_SERVER=http://127.0.0.1:9 QA_STATE_DIR="$STATE_DIR"
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
PYTEST_BODY='echo "pytest $*" >> "$T/pytest.log"; echo "cwd=$PWD" >> "$T/pytest.log"; [ -f red.flag ] && { echo "1 failed"; exit 1; }; echo ". passed"; exit 0'

# stub gate factory: mkgate <name> <fail-prefix> [body-override]. FAIL on files named <fail-prefix>*, UNVERIFIED on unv*, FLAG on flag*, else PASS.
mkgate(){
  mkdir -p "$T/gates"
  cat > "$T/gates/gate_$1.py" <<PY
import os, sys, time
sys.path.insert(0, "$Q/qa")
import qa_common as qc
GATE = "$1"
def check(argv):
    a = {}
    for i, x in enumerate(argv):
        if x in ("--repo", "--base", "--head") and i + 1 < len(argv):
            a[x[2:]] = argv[i + 1]
    open(os.path.join("$T", "gate_runs.log"), "a").write("%s %s..%s\n" % (GATE, a["base"][:8], a["head"][:8]))
    $3
    names = [os.path.basename(f) for f in qc.changed_files(a["repo"], a["base"], a["head"])]
    for n in names:
        if n.startswith("$2"):
            return qc.verdict("FAIL", GATE, "r", "x", "seeded bad change in " + n)
    for n in names:
        if n.startswith("unv"):
            return qc.verdict("UNVERIFIED", GATE, "r", "x", "could not run")
    for n in names:
        if n.startswith("flag"):
            return qc.verdict("FLAG", GATE, "r", "x", "flagged " + n)
    return qc.verdict("PASS", GATE, "r", "x", "clean")
sys.exit(qc.main_guard(GATE, check))
PY
}
setup(){
  rm -rf "$T/home" "$T/origin" "$T/seed" "$T/repos" "$T/state" "$T/report.md" "$T"/*.log "$T/gates"
  mkdir -p "$HOME/overnight-queue/scripts" "$T/origin" "$T/seed" "$T/repos" "$STATE_DIR"
  printf 'import sys\n' > "$HOME/overnight-queue/scripts/check_migrations.py"
  unset OVN_QA_ENFORCE OVN_QA_STUB OVN_QA_OTHER QA_ENFORCE_SEARCH_BUDGET QA_ENFORCE_TIMEOUT QA_ENFORCE_MAX_COMMITS HYGIENE_MERGE_TARGET
  mkgate stub bad ""
}
mk(){ # mk <name> [nfeat]
  local n="$1" nf="${2:-2}" o="$T/origin/$1.git" s="$T/seed/$1" i
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature
    for i in $(seq 1 "$nf"); do echo "feat$i" > "feat$i.txt"; git add -A; git commit -q -m "feat: $i"; done
    git push -q origin overnight/feature
    git checkout -q develop; git branch claude/feature; git push -q origin claude/feature )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  git -C "$T/repos/$n" config user.email t@t; git -C "$T/repos/$n" config user.name t
  mkdir -p "$T/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$T/repos/$n/.venv/bin/pytest"; chmod +x "$T/repos/$n/.venv/bin/pytest"
  return 0
}
addc(){ local n="$1" f="$2" s="$T/seed/$1"; ( cd "$s"; git checkout -q overnight/feature; echo "$f" > "$f"; git add -A; git commit -q -m "add $f"; git push -q origin overnight/feature; git checkout -q develop ); git -C "$T/repos/$n" fetch -q origin; }
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
subj(){ git -C "$T/origin/$1.git" log --format='%H %s' overnight/feature | grep -F "$2" | head -1 | cut -d' ' -f1; }
anc(){ git -C "$T/origin/$1.git" merge-base --is-ancestor "$2" develop && echo 1 || echo 0; }
run(){ ( cd "$T" && PATH="$BIN:$PATH" bash "$BH" "$@" > "$OUT" 2>&1 ); echo $? > "$T/rc"; }
QE(){ ( QA_STATE_DIR="$STATE_DIR" bash "$Q/qa/qa_enforce.sh" "$@" ); }
nalerts(){ grep -c "qa-enforce:" "$STATE_DIR/alerts.log" 2>/dev/null || echo 0; }

# ===== shadow default: nothing changes, gates never run synchronously =====
setup; mk app 2; addc app bad1.txt; addc app good3.txt; run "$T/repos/app"
ok "shadow default: the whole branch merges even though a gate WOULD fail it" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"
ok "shadow default: no gate was run synchronously" "$([ ! -s "$T/gate_runs.log" ] && echo 1 || echo 0)"
ok "shadow default: no alert, no qa_blocked record" "$([ "$(nalerts)" = 0 ] && [ ! -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"

# ===== enforce + FAIL: clean prefix lands, offender and everything after stay =====
setup; mk app 2; addc app bad1.txt; addc app good3.txt
QE stub enforce >/dev/null; f1="$(subj app 'feat: 1')"; f2="$(subj app 'feat: 2')"; bad="$(subj app 'add bad1.txt')"; g3="$(subj app 'add good3.txt')"
run "$T/repos/app"
ok "enforce+FAIL: hygiene exits 0" "$([ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"
ok "enforce+FAIL: the clean prefix (feat 1 and 2) landed on develop" "$([ "$(anc app "$f1")" = 1 ] && [ "$(anc app "$f2")" = 1 ] && echo 1 || echo 0)"
ok "enforce+FAIL: the offender is NOT on develop" "$([ "$(anc app "$bad")" = 0 ] && echo 1 || echo 0)"
ok "enforce+FAIL: the good commit AFTER the offender is held too" "$([ "$(anc app "$g3")" = 0 ] && echo 1 || echo 0)"
ok "enforce+FAIL: the offender is still on overnight/feature (not dropped, not reverted)" "$([ "$(git -C "$T/origin/app.git" merge-base --is-ancestor "$bad" overnight/feature && echo 1 || echo 0)" = 1 ] && echo 1 || echo 0)"
ok "enforce+FAIL: develop has no bad1.txt" "$([ -z "$(git -C "$T/origin/app.git" ls-tree develop --name-only | grep bad1)" ] && echo 1 || echo 0)"
ok "enforce+FAIL: exactly ONE alert line naming repo, gate and commit" "$([ "$(nalerts)" = 1 ] && grep -q "warn | qa-enforce:app | gate=stub blocked commit ${bad:0:12}" "$STATE_DIR/alerts.log" && echo 1 || echo 0)"
ok "enforce+FAIL: alert carries the finding" "$(has "$STATE_DIR/alerts.log" 'seeded bad change in bad1.txt')"
ok "enforce+FAIL: state/qa_blocked/app__overnight_feature.json records gate+commit+finding" "$(jq -e --arg c "$bad" '.gate=="stub" and .commit==$c and (.finding|test("bad1")) and .held_commits==2' "$STATE_DIR/qa_blocked/app__overnight_feature.json" >/dev/null 2>&1 && echo 1 || echo 0)"
ok "enforce+FAIL: report says merged partial / QA-held" "$(has "$REPORT_FILE" 'QA-held')"
ok "enforce+FAIL: the clean prefix was re-gated by the build/test gate (pytest in a qaprefix worktree)" "$(has "$T/pytest.log" 'cwd=/tmp/hygiene-app-qaprefix.')"
ok "enforce+FAIL: shadow-style gate runs happened only for the enforce gate (range + prefixes)" "$([ "$(grep -vc '^stub ' "$T/gate_runs.log")" = 0 ] && [ "$(wc -l < "$T/gate_runs.log")" -ge 2 ] && echo 1 || echo 0)"
ok "enforce+FAIL: no leaked worktrees" "$([ "$(git -C $T/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
ok "enforce+FAIL: hygiene lock not left held" "$(flock -n "$STATE_DIR/hygiene.lock" true && echo 1 || echo 0)"
ok "enforce+FAIL: no review flag (the single alert channel is alerts.log)" "$([ ! -e "$STATE_DIR/branch_hygiene_review_app" ] && echo 1 || echo 0)"
d1="$(sha app develop)"
run "$T/repos/app"
ok "second hourly run: still blocked, develop unchanged" "$([ "$(sha app develop)" = "$d1" ] && [ "$(has "$OUT" 'QA-blocked')" = 1 ] && echo 1 || echo 0)"
ok "second hourly run: NO new alert (same offender)" "$([ "$(nalerts)" = 1 ] && echo 1 || echo 0)"
ok "second hourly run: report says QA-blocked, exit 0" "$([ "$(has "$REPORT_FILE" 'QA-blocked')" = 1 ] && [ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"
run "$T/repos/app"; ok "third run: still exactly one alert" "$([ "$(nalerts)" = 1 ] && echo 1 || echo 0)"
# rollback: same command, next pass merges everything and the block record is cleared
QE stub shadow >/dev/null; run "$T/repos/app"
ok "rollback (qa_enforce.sh stub shadow): next pass lands the held commits" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"
ok "rollback: qa_blocked record cleared once a pass proceeds" "$([ ! -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"

# ===== nothing landable before the offender: QA-blocked, clean exit =====
setup; mk app 0; addc app bad1.txt; addc app good2.txt; QE stub enforce >/dev/null; d0="$(sha app develop)"; run "$T/repos/app"
ok "offender first: develop untouched" "$([ "$(sha app develop)" = "$d0" ] && echo 1 || echo 0)"
ok "offender first: 'QA-blocked' logged and reported, exit 0, not a failure flag" "$([ "$(has "$OUT" 'QA-blocked')" = 1 ] && [ "$(has "$REPORT_FILE" 'QA-blocked')" = 1 ] && [ "$(cat "$T/rc")" = 0 ] && [ ! -e "$STATE_DIR/branch_hygiene_review_app" ] && echo 1 || echo 0)"
ok "offender first: one alert; lock free; no worktrees left" "$([ "$(nalerts)" = 1 ] && flock -n "$STATE_DIR/hygiene.lock" true && [ "$(git -C $T/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
run "$T/repos/app"; ok "offender first, rerun: still one alert" "$([ "$(nalerts)" = 1 ] && echo 1 || echo 0)"

# ===== two feature-branch passes per repo share one state dir (the real cron layout): one alert, not one per hour =====
cseed(){ local n="$1" f="$2" s="$T/seed/$1"; ( cd "$s"; git checkout -q claude/feature; echo "$f" > "$f"; git add -A; git commit -q -m "add $f"; git push -q origin claude/feature; git checkout -q develop ); git -C "$T/repos/$n" fetch -q origin; }
setup; mk app 0; addc app bad1.txt; QE stub enforce >/dev/null
run "$T/repos/app"; ok "two-branch: overnight/feature pass blocks and alerts once" "$([ "$(nalerts)" = 1 ] && [ -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"
cseed app clean1.txt; HYGIENE_FEATURE_BRANCH=claude/feature run "$T/repos/app"
ok "two-branch: the clean claude/feature pass lands its commit (proceed path)" "$([ "$(anc app claude/feature)" = 1 ] && echo 1 || echo 0)"
ok "two-branch: the clean claude/feature pass does NOT delete overnight/feature's record" "$([ -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"
HYGIENE_FEATURE_BRANCH=claude/feature run "$T/repos/app"
ok "two-branch: the claude/feature 'already in develop' pass does NOT delete it either" "$([ "$(has "$OUT" 'already in')" = 1 ] && [ -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"
run "$T/repos/app"; HYGIENE_FEATURE_BRANCH=claude/feature run "$T/repos/app"; run "$T/repos/app"
ok "two-branch: after alternating passes the blocked branch has still produced exactly ONE alert" "$([ "$(nalerts)" = 1 ] && echo 1 || echo 0)"
# a record for one branch is cleared only by that branch's own clean/in-sync pass
mkdir -p "$STATE_DIR/qa_blocked"; echo '{"gate":"stub","commit":"old"}' > "$STATE_DIR/qa_blocked/app__claude_feature.json"; HYGIENE_FEATURE_BRANCH=claude/feature run "$T/repos/app"
ok "two-branch: a branch's own in-sync pass clears its own record" "$([ ! -e "$STATE_DIR/qa_blocked/app__claude_feature.json" ] && [ -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && echo 1 || echo 0)"

# ===== candidate cap: commits past the cap are held UNVERIFIED, the alert must not blame an examined commit =====
setup; mk app 4; addc app bad1.txt; QE stub enforce >/dev/null; f2="$(subj app 'feat: 2')"; f3="$(subj app 'feat: 3')"; f4="$(subj app 'feat: 4')"
export QA_ENFORCE_MAX_COMMITS=2; run "$T/repos/app"; unset QA_ENFORCE_MAX_COMMITS
ok "cap: the two examined commits land, the first unexamined one (feat 3) and everything after are held" "$([ "$(anc app "$f2")" = 1 ] && [ "$(anc app "$f3")" = 0 ] && [ "$(anc app "$f4")" = 0 ] && echo 1 || echo 0)"
ok "cap: alert is labelled 'held unverified (candidate cap' and names the first unexamined commit" "$(grep -q "blocked commit ${f3:0:12}.*held unverified (candidate cap 2" "$STATE_DIR/alerts.log" && echo 1 || echo 0)"
ok "cap: alert does NOT claim the failure was 'not reproduced by any single prefix'" "$([ "$(has "$STATE_DIR/alerts.log" 'not reproduced')" = 0 ] && [ "$(nalerts)" = 1 ] && echo 1 || echo 0)"
# benign control: the whole branch fits under the cap, offender found normally (no cap wording)
setup; mk app 1; addc app bad1.txt; QE stub enforce >/dev/null; export QA_ENFORCE_MAX_COMMITS=5; run "$T/repos/app"; unset QA_ENFORCE_MAX_COMMITS
ok "cap benign: under the cap the real offender is named, no cap wording" "$(grep -q "seeded bad change in bad1.txt" "$STATE_DIR/alerts.log" && [ "$(has "$STATE_DIR/alerts.log" 'candidate cap')" = 0 ] && echo 1 || echo 0)"

# ===== prefix re-gate: one infra flake is retried once, a persistent failure still holds =====
flakybody(){ printf '#!/usr/bin/env bash\n%s\n' "$1; $PYTEST_BODY" > "$T/repos/app/.venv/bin/pytest"; chmod +x "$T/repos/app/.venv/bin/pytest"; }
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; f2="$(subj app 'feat: 2')"
flakybody 'case "$PWD" in *qaprefix*) if [ ! -f "$T/flaked" ]; then touch "$T/flaked"; exit 124; fi;; esac'
run "$T/repos/app"
ok "prefix flake once (timeout 124): retried, the clean prefix still lands" "$([ "$(anc app "$f2")" = 1 ] && [ ! -e "$STATE_DIR/branch_hygiene_review_app" ] && [ "$(has "$OUT" 'retrying once')" = 1 ] && echo 1 || echo 0)"
ok "prefix flake once: no leaked worktrees" "$([ "$(git -C $T/repos/app worktree list | wc -l)" = 1 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; f2="$(subj app 'feat: 2')"; d0="$(sha app develop)"
flakybody 'case "$PWD" in *qaprefix*) echo "cwd=$PWD" >> "$T/pytest.log"; exit 124;; esac'
run "$T/repos/app"
ok "prefix fails persistently (124 twice): still held + flagged, develop untouched (retry is bounded to one)" "$([ "$(sha app develop)" = "$d0" ] && [ -e "$STATE_DIR/branch_hygiene_review_app" ] && [ "$(grep -c 'cwd=.*qaprefix' "$T/pytest.log")" = 2 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; d0="$(sha app develop)"
flakybody 'case "$PWD" in *qaprefix*) echo "1 failed"; exit 1;; esac'
run "$T/repos/app"
ok "prefix genuinely red (rc 1, not a timeout): NOT retried as a flake, held + flagged" "$([ "$(sha app develop)" = "$d0" ] && [ -e "$STATE_DIR/branch_hygiene_review_app" ] && [ "$(has "$OUT" 'prefix gate hit a known infra flake')" = 0 ] && echo 1 || echo 0)"

# ===== infra problems never block =====
setup; mk app 2; addc app unv1.txt; QE stub enforce >/dev/null; run "$T/repos/app"
ok "enforce+UNVERIFIED: merges everything, no alert" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(nalerts)" = 0 ] && echo 1 || echo 0)"
setup; mk app 2; addc app flag1.txt; QE stub enforce >/dev/null; run "$T/repos/app"
ok "enforce+FLAG: merges everything, no alert" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(nalerts)" = 0 ] && echo 1 || echo 0)"
setup; mk app 2; QE stub enforce >/dev/null; mkdir -p "$STATE_DIR/qa_blocked"; echo '{"gate":"stub","commit":"old"}' > "$STATE_DIR/qa_blocked/app__overnight_feature.json"; run "$T/repos/app"
ok "enforce+PASS: merges everything and clears a stale qa_blocked record" "$([ "$(anc app overnight/feature)" = 1 ] && [ ! -e "$STATE_DIR/qa_blocked/app__overnight_feature.json" ] && [ "$(has "$T/gate_runs.log" 'stub ')" = 1 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; mkgate crash zzz 'sys.exit(1)'; QE crash enforce >/dev/null; run "$T/repos/app"
ok "enforce gate that crashes (rc 1, no JSON): UNVERIFIED, merge proceeds" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(nalerts)" = 0 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; mkgate slow bad 'time.sleep(60)'; QE slow enforce >/dev/null; export QA_ENFORCE_TIMEOUT=5; run "$T/repos/app"; unset QA_ENFORCE_TIMEOUT
ok "enforce gate that times out: UNVERIFIED, merge proceeds, bounded (hung gate killed)" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(nalerts)" = 0 ] && ! pgrep -f "$T/gates/gate_slow.py" >/dev/null && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; mv "$T/gates/gate_stub.py" "$T/gates/gate_stub.py.gone"; run "$T/repos/app"
ok "enforce-mode gate whose script vanished: merge proceeds (never blocks on infra)" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; export QA_ENFORCE_HELPER="$T/nonexistent.py"; run "$T/repos/app"; unset QA_ENFORCE_HELPER
ok "missing enforce helper: merge proceeds exactly as before" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; printf 'print("garbage")\n' > "$T/helper_garbage.py"; QE stub enforce >/dev/null; export QA_ENFORCE_HELPER="$T/helper_garbage.py"; run "$T/repos/app"; unset QA_ENFORCE_HELPER
ok "helper emitting garbage: merge proceeds, 'UNVERIFIED' logged (never fails open silently)" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(has "$OUT" 'UNVERIFIED, proceeding')" = 1 ] && echo 1 || echo 0)"

# ===== bounded search: budget exhausted holds unchecked commits UNVERIFIED, never merges them unchecked =====
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; d0="$(sha app develop)"; export QA_ENFORCE_SEARCH_BUDGET=0; run "$T/repos/app"; unset QA_ENFORCE_SEARCH_BUDGET
ok "search budget exhausted before any commit checked: nothing merged, QA-blocked, one alert, exit 0" "$([ "$(sha app develop)" = "$d0" ] && [ "$(has "$OUT" 'QA-blocked')" = 1 ] && [ "$(nalerts)" = 1 ] && [ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"

# ===== per-gate flip file + env override + kill switch =====
setup; mk app 2; addc app bad1.txt; mkgate other worse ""; QE other enforce >/dev/null; run "$T/repos/app"
ok "per-gate: 'other' enforces, 'stub' (shadow) would fail bad1 but is NOT run synchronously: everything merges" "$([ "$(anc app overnight/feature)" = 1 ] && [ "$(has "$T/gate_runs.log" 'other ')" = 1 ] && [ "$(has "$T/gate_runs.log" 'stub ')" = 0 ] && echo 1 || echo 0)"
ok "per-gate: flip file holds exactly {other: enforce}" "$([ "$(jq -c . "$STATE_DIR/qa_gate_modes.json")" = '{"other":"enforce"}' ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; OVN_QA_STUB=shadow run "$T/repos/app"
ok "env OVN_QA_STUB=shadow outranks the flip file: no block" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; OVN_QA_ENFORCE=off run "$T/repos/app"
ok "OVN_QA_ENFORCE=off kill switch: no block" "$([ "$(anc app overnight/feature)" = 1 ] && [ ! -s "$T/gate_runs.log" ] && echo 1 || echo 0)"
setup; mk app 2; addc app bad1.txt; QE stub enforce >/dev/null; QE stub off >/dev/null; run "$T/repos/app"
ok "rollback to off: no block" "$([ "$(anc app overnight/feature)" = 1 ] && echo 1 || echo 0)"

# ===== qa_enforce.sh CLI =====
setup; mkgate stub bad ""
ok "CLI: bad mode rejected" "$(QE stub bogus >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"
ok "CLI: enforcing an uninstalled gate is refused (typo != flip)" "$(QE nosuch enforce >/dev/null 2>&1; [ $? -ne 0 ] && [ ! -e "$STATE_DIR/qa_gate_modes.json" ] && echo 1 || echo 0)"
ok "CLI: bad gate name rejected" "$(QE '../x' shadow >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"
QA_ENFORCE_WHO=mark@box QE stub enforce >/dev/null
ok "CLI: flip is recorded with who/when" "$(jq -e '.gate=="stub" and .to=="enforce" and .who=="mark@box" and (.ts|length>10)' < "$STATE_DIR/qa_gate_modes.history.jsonl" >/dev/null 2>&1 && echo 1 || echo 0)"
ok "CLI: status shows enforce, source=file, who" "$(QE status | grep -q 'stub .*enforce .*source=file.*mark@box' && echo 1 || echo 0)"
ok "CLI: no temp files left behind by the atomic write" "$([ -z "$(ls -A "$STATE_DIR" | grep '^\.qa_gate_modes')" ] && echo 1 || echo 0)"
QE stub shadow >/dev/null; ok "CLI: rollback flips back, status shows shadow" "$(QE status | grep -q 'stub .*shadow .*source=file' && echo 1 || echo 0)"
mkdir -p "$STATE_DIR/qa_blocked"; echo '{"repo":"app","gate":"stub","commit":"abc","since":"x"}' > "$STATE_DIR/qa_blocked/app__overnight_feature.json"
ok "CLI: status lists blocked repos" "$(QE status | grep -q 'BLOCKED app: gate=stub' && echo 1 || echo 0)"
QE unblock app >/dev/null; ok "CLI: unblock removes the legacy repo-only record" "$([ ! -e "$STATE_DIR/qa_blocked/app.json" ] && echo 1 || echo 0)"
B="$STATE_DIR/qa_blocked"; mkdir -p "$B"
for k in app__overnight_feature app__claude_feature other__overnight_feature; do echo '{"repo":"'"${k%%__*}"'","branch":"x/y","gate":"stub","commit":"abc","since":"x"}' > "$B/$k.json"; done
ok "CLI: status shows the branch of each record" "$(QE status | grep -q 'BLOCKED app \[x/y\]: gate=stub' && echo 1 || echo 0)"
QE unblock app claude/feature >/dev/null
ok "CLI: unblock <repo> <branch> removes only that branch's record" "$([ ! -e "$B/app__claude_feature.json" ] && [ -e "$B/app__overnight_feature.json" ] && [ -e "$B/other__overnight_feature.json" ] && echo 1 || echo 0)"
QE unblock app >/dev/null
ok "CLI: unblock <repo> removes every branch of that repo, not other repos" "$([ ! -e "$B/app__overnight_feature.json" ] && [ -e "$B/other__overnight_feature.json" ] && echo 1 || echo 0)"
rm -f "$B"/*.json
ok "CLI: unblock refuses path tricks" "$(QE unblock ../x >/dev/null 2>&1; [ $? -ne 0 ] && echo 1 || echo 0)"
# cron-style: relative path, env -i minimal PATH
ok "CLI under env -i minimal PATH + relative path" "$(cd "$Q" && env -i HOME="$HOME" PATH=/usr/bin:/bin QA_STATE_DIR="$STATE_DIR" QA_GATES_DIR="$T/gates" bash ./qa/qa_enforce.sh status >/dev/null 2>&1 && echo 1 || echo 0)"
ok "helper 'gates' under env -i minimal PATH lists only enforce gates" "$(QE stub enforce >/dev/null; cd "$Q" && [ "$(env -i HOME="$HOME" PATH=/usr/bin:/bin QA_STATE_DIR="$STATE_DIR" QA_GATES_DIR="$T/gates" python3 ./qa/qa_enforce_run.py gates)" = stub ] && echo 1 || echo 0)"

# ===== qa_common.mode() hardening =====
M(){ QA_STATE_DIR="$STATE_DIR" python3 -c "import sys;sys.path.insert(0,'$Q/qa');import qa_common as q;print(q.mode('$1'))"; }
setup; ok "mode(): default is shadow" "$([ "$(M stub)" = shadow ] && echo 1 || echo 0)"
echo '{not json' > "$STATE_DIR/qa_gate_modes.json"; ok "mode(): corrupt flip file => shadow, no crash" "$([ "$(M stub)" = shadow ] && echo 1 || echo 0)"
echo '{"stub":"ENFORCE!"}' > "$STATE_DIR/qa_gate_modes.json"; ok "mode(): unknown value => shadow (never enforce by accident)" "$([ "$(M stub)" = shadow ] && echo 1 || echo 0)"
echo '{"stub":"enforce"}' > "$STATE_DIR/qa_gate_modes.json"; echo '{"stub":"off"}' > "$STATE_DIR/qa_modes.json"
ok "mode(): flip file outranks legacy qa_modes.json" "$([ "$(M stub)" = enforce ] && echo 1 || echo 0)"
rm -f "$STATE_DIR/qa_gate_modes.json"; ok "mode(): legacy qa_modes.json still honoured when no flip file" "$([ "$(M stub)" = off ] && echo 1 || echo 0)"

echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
