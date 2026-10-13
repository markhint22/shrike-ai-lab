#!/usr/bin/env bash
# 2026-10-12 (package uidcredit, part 2): ONE canonical item identity (ovn_credit_items.py canon_item) for refill dedupe, planner dedupe and twin crediting, plus the
# scout ALREADY-DONE refusal counter. What the real xlite logs showed (state/outcomes.jsonl, logs/20261012-0055xx..0057xx, verify_gate_shadow.log) for hash 47184e0e...
# (= the [feat:] tag of FIVE sibling items, not one duplicated item): the code already had `faction_for`, the scout said ALREADY-DONE 4x, and every credit was REFUSED because
# the item's VERIFY `godot ... -gdir=tests/test_enemy_faction_map.gd` can never pass (GUT -gdir takes a directory). That refusal was not counted toward the credit-refusal park.
# The multi-section-twin hazard the brief named is real in the code (a done copy with an `(annotation)` prefix never matched its plain re-shipped copy in queue_refill, so the
# 2026-10-07 churn-loop shape could re-pull it) and is covered here; no open twin existed in the live files on 2026-10-12.
# Every behaviour has a kill switch / legacy mode (OVN_REFILL_CANON=legacy, OVN_TWIN_CREDIT=off, OVN_PLANNER_DEDUPE=off, OVN_SCOUT_REFUSAL_PARK=off) that reproduces the old behaviour.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; [ -f "$S/ovn_credit_items.py" ] || S="$HERE"
RF="$S/../queue_refill.py"; [ -f "$RF" ] || RF="$HERE/../queue_refill.py"
PL="$S/../ovn_planner.sh"; [ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
RUN="$S/../run_overnight.sh"
CI="$S/ovn_credit_items.py"
. "$HERE/ntfy_guard.sh" 2>/dev/null || true
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
W="$(mktemp -d)"; trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
canon(){ printf '%s\n' "$1" > "$W/c.md"; python3 "$CI" canon "$W/c.md" 1; }

# the REAL line shapes (xlite OVERNIGHT_PROGRESS.md, 2026-10-12)
DONE_ANN='- [x] (pre-verified done 2026-10-11: get_faction never in current enemy_faction_map.gd; file only has _FACTION_MAP const) [AUTO-SKIP churn-loop] [T1] scripts/battle/enemy_faction_map.gd — Remove the `get_faction()` function definition and its associated doc comments. (cat:godot; multifile:no) [feat:xlite-20261009-delete-enemyfactionmap-get-faction-and-g]'
PLAIN_OPEN='- [ ] [T1] scripts/battle/enemy_faction_map.gd — Remove the `get_faction()` function definition and its associated doc comments. (cat:godot; multifile:no) [feat:xlite-20261012-delete-enemyfactionmap-get-faction-and-g]'
SIB='- [ ] [T2] tests/test_enemy_faction_map.gd — Remove any test functions that exclusively call `get_faction()`. (cat:test; multifile:no) [feat:xlite-20261012-delete-enemyfactionmap-get-faction-and-g]'

# ============================== P. canonical identity ==============================
ok "P1 a done line with a '(pre-verified ...)' annotation + [AUTO-SKIP] tag has the SAME identity as its plain re-shipped copy (real lines)" "[ \"\$(canon '$DONE_ANN')\" = \"\$(canon '$PLAIN_OPEN')\" ]"
ok "P2 a retiered copy ([T3] vs [T1]) is the same item" "[ \"\$(canon '${PLAIN_OPEN/\[T1\]/[T3]}')\" = \"\$(canon '$PLAIN_OPEN')\" ]"
ok "P3 only the feat date differs (regeneration) -> same item" "[ \"\$(canon '${PLAIN_OPEN/20261012/20261001}')\" = \"\$(canon '$PLAIN_OPEN')\" ]"
ok "P4 leading state tags ([CLAUDE] [unworkable: ...] [AUTO-SKIP ...]) and nested-paren annotations never change identity" "[ \"\$(canon '- [ ] [CLAUDE] [unworkable: hard-banned file addons/gut/gut.gd] (retired (nested (deep)) note) [T1] scripts/battle/enemy_faction_map.gd — Remove the \`get_faction()\` function definition and its associated doc comments. (cat:godot; multifile:no) [feat:xlite-20261012-delete-enemyfactionmap-get-faction-and-g]')\" = \"\$(canon '$PLAIN_OPEN')\" ]"
ok "P5 a SIBLING sharing the feat tag but with different text is a DIFFERENT item (siblings are different work: the item HASH alone would conflate them)" "[ \"\$(canon '$SIB')\" != \"\$(canon '$PLAIN_OPEN')\" ]"
ok "P6 same text, different VERIFY -> different item" "[ \"\$(canon '- [ ] [T1] a.gd — Do it. VERIFY: \`test -f a.gd\`. (cat:x) [feat:r-20261012-z]')\" != \"\$(canon '- [ ] [T1] a.gd — Do it. VERIFY: \`test -f b.gd\`. (cat:x) [feat:r-20261012-z]')\" ]"
ok "P7 an unbalanced '(' annotation does not loop or crash (identity = the rest of the line)" "[ -n \"\$(canon '- [ ] (never closed [T1] a.gd — Do it.')\" ]"
ok "P8 the R11 GUT path rewrite is part of the identity (rewritten copy == old copy)" "[ \"\$(canon '- [ ] [T1] a.gd — x. VERIFY: \`godot -s addons/gut/cli/gut_cli.gd -gtest=res://t.gd\`')\" = \"\$(canon '- [ ] [T1] a.gd — x. VERIFY: \`godot -s addons/gut/gut_cmdln.gd -gtest=res://t.gd\`')\" ]"

# ============================== R. queue_refill ==============================
refill(){  # $1 = n ; env passes through ; prints the stdout line
  python3 "$RF" "$W/prog.md" "$W/bl.md" "$1" 2>/dev/null
}
mk_refill(){  # $1 = progress extra lines  $2 = backlog lines  $3 = done lines
  printf '# progress\n## Next Steps\n%s\n' "$1" > "$W/prog.md"; printf '# backlog\n%s\n' "$2" > "$W/bl.md"; printf '# done\n%s\n' "${3:-}" > "$W/OVERNIGHT_DONE.md"
}
# the backlog copy of the item is the plain re-shipped one (a roadmap re-decomposition); the progress copy is the annotated DONE line
mk_refill "$DONE_ANN" "$PLAIN_OPEN"
out="$(refill 5)"
ok "R1 real shape: a plain copy of an annotated DONE item is NOT re-pulled (REFILL=0) and is pruned from the backlog" "printf '%s' '$out' | grep -q 'REFILL=0' && printf '%s' '$out' | grep -q 'PRUNED=1' && ! grep -q 'enemy_faction_map.gd' '$W/bl.md' && [ \"\$(grep -c 'enemy_faction_map.gd' '$W/prog.md')\" = 1 ]"
mk_refill "$DONE_ANN" "$PLAIN_OPEN"
out="$(OVN_REFILL_CANON=legacy refill 5)"
ok "R1' (mutation: OVN_REFILL_CANON=legacy = the old comparison) the same item IS re-pulled (REFILL=1) - the churn-loop shape" "printf '%s' '$out' | grep -q 'REFILL=1' && [ \"\$(grep -c 'enemy_faction_map.gd' '$W/prog.md')\" = 2 ]"
mk_refill "" "$PLAIN_OPEN" "$(printf '%s' "$DONE_ANN" | sed 's/^- \[x\] (pre-verified done[^)]*) \[AUTO-SKIP churn-loop\]/- [x] (pre-verified: VERIFY already passed against current code)/')"
out="$(refill 5)"
ok "R2 the OVERNIGHT_DONE.md archive form '(pre-verified: VERIFY already passed ...)' also dedupes" "printf '%s' '$out' | grep -q 'REFILL=0'"
mk_refill "" "$PLAIN_OPEN
$PLAIN_OPEN"
out="$(refill 5)"
ok "R3 two IDENTICAL backlog lines: only ONE is pulled (REFILL=1), both leave the backlog" "printf '%s' '$out' | grep -q 'REFILL=1' && [ \"\$(grep -c 'enemy_faction_map.gd' '$W/prog.md')\" = 1 ] && ! grep -q 'enemy_faction_map.gd' '$W/bl.md'"
mk_refill "" "$PLAIN_OPEN
$PLAIN_OPEN"
out="$(OVN_REFILL_CANON=legacy refill 5)"
ok "R3' (mutation: legacy) both identical lines are pulled (REFILL=2)" "printf '%s' '$out' | grep -q 'REFILL=2'"
mk_refill "- [ ] [T3] scripts/battle/enemy_faction_map.gd — Remove the \`get_faction()\` function definition and its associated doc comments. (cat:godot; multifile:no) [feat:xlite-20261012-delete-enemyfactionmap-get-faction-and-g]" "$PLAIN_OPEN"
out="$(refill 5)"
ok "R4 a retiered ([T3] open vs [T1] backlog) copy is the same item: not pulled" "printf '%s' '$out' | grep -q 'REFILL=0'"
mk_refill "$DONE_ANN" "$SIB"
out="$(refill 5)"
ok "R5 a SIBLING (same feat tag, different text) is still pulled" "printf '%s' '$out' | grep -q 'REFILL=1' && grep -q 'test_enemy_faction_map.gd' '$W/prog.md'"
mk_refill "- [ ] [T1] app/a.py — spec A. VERIFY: x. (polish)" "- [ ] [T1] app/a.py — spec A. VERIFY: x. (polish)
- [ ] [T1] app/b.py — spec B. VERIFY: y. (polish)"
out="$(refill 5)"
ok "R6 the exact-twin dedupe that always existed still works (only b.py pulled)" "printf '%s' '$out' | grep -q 'REFILL=1' && [ \"\$(grep -c 'app/a.py' '$W/prog.md')\" = 1 ] && grep -q 'app/b.py' '$W/prog.md'"
# the canonical form must never WIDEN to different work
mk_refill "- [ ] [T1] app/a.py — spec A. VERIFY: x. (polish)" "- [ ] [T1] app/a.py — spec A2. VERIFY: x. (polish)"
out="$(refill 5)"
ok "R7 different text is never deduped (spec A2 vs spec A)" "printf '%s' '$out' | grep -q 'REFILL=1'"

# ============================== T. twin credit ==============================
mk_twin(){
  cat > "$W/tw.md" <<EOP
## Next Steps
- [ ] [T2] src/a.py — Add new_a. VERIFY: \`grep -q "def new_a" src/a.py\` (cat:x) [feat:r-20261012-aa]
- [ ] [T3] src/a.py — Add new_a. VERIFY: \`grep -q "def new_a" src/a.py\` (cat:x) [feat:r-20261009-aa]
- [ ] [AUTO-SKIP after 5 no-op cycles] [T2] src/a.py — Add new_a. VERIFY: \`grep -q "def new_a" src/a.py\` (cat:x) [feat:r-20261012-aa]
- [ ] [T2] src/a.py — Add new_a_sibling. VERIFY: \`grep -q "def new_a" src/a.py\` (cat:x) [feat:r-20261012-aa]
- [x] (already-done, scout-verified) [T2] src/a.py — Add new_a. VERIFY: \`grep -q "def new_a" src/a.py\` (cat:x) [feat:r-20261012-aa]
EOP
}
mk_twin
ok "T1 twins of line 2: only the open, non-parked identical copy (line 3); not the parked copy, the sibling or the done line" "[ \"\$(python3 '$CI' twins '$W/tw.md' 2 | tr '\n' ' ')\" = '3 ' ]"
cp "$W/tw.md" "$W/tw.before"
ok "T2 tick-twins shadow: reports 'SHADOW 1 3' and edits NOTHING" "[ \"\$(python3 '$CI' tick-twins '$W/tw.md' 2 shadow)\" = 'SHADOW 1 3' ] && cmp -s '$W/tw.md' '$W/tw.before'"
ok "T3 tick-twins off: 'OFF 0', edits nothing" "[ \"\$(python3 '$CI' tick-twins '$W/tw.md' 2 off)\" = 'OFF 0' ] && cmp -s '$W/tw.md' '$W/tw.before'"
ok "T4 tick-twins on: TICKED 1; line 3 annotated with the source line; parked copy / sibling untouched; every other byte identical" "[ \"\$(python3 '$CI' tick-twins '$W/tw.md' 2 on)\" = 'TICKED 1' ] && sed -n 3p '$W/tw.md' | grep -q '^- \[x\] (identical twin of the item credited at line 2) \[T3\] src/a.py' && [ \"\$(diff '$W/tw.before' '$W/tw.md' | grep -c '^[<>]')\" = 2 ] && [ \"\$(tail -c1 '$W/tw.md' | od -An -tx1 | tr -d ' ')\" = 0a ]"
ok "T5 the credited line's own checkbox state does not matter (twins of a ticked line are found too)" "[ \"\$(python3 '$CI' twins '$W/tw.before' 6 | tr '\n' ' ')\" = '2 3 ' ]"

# wiring in ovn_auto_credit (the real function, a throwaway repo)
export HOME="$W/home"; mkdir -p "$HOME"
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
export OVN_STATE_DIR="$W/state"; mkdir -p "$OVN_STATE_DIR"
emit_alert(){ :; }
. "$S/lib_item_select.sh"; . "$S/lib_path_normalize.sh"; . "$S/lib_verify_clause.sh"; . "$S/lib_auto_credit.sh"
mk_ac(){
  R="$W/acrepo"; rm -rf "$R"; mkdir -p "$R/src"; cd "$R" || exit 1
  git init -q -b main; git config user.email t@t; git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py
  cat > OVERNIGHT_PROGRESS.md <<'EOP'
## Next Steps
- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py` (cat:x) [feat:r-20261012-aa]
- [ ] [T3] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py` (cat:x) [feat:r-20261009-aa]
- [ ] [T2] src/a.py — Add new_a_other. VERIFY: `grep -q "def new_a_other" src/a.py` (cat:x) [feat:r-20261012-aa]
EOP
  git add -A; git commit -q -m base; B1="$(git rev-parse HEAD)"
  printf 'def new_a():\n    return 2\n' >> src/a.py; git add -A; git commit -q -m "feat: new_a"; A1="$(git rev-parse HEAD)"
  : > "$R/task.log"
}
mk_ac; OVN_TWIN_CREDIT=on ovn_auto_credit "$B1" "$A1" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null
ok "T6 ovn_auto_credit with OVN_TWIN_CREDIT=on: the credited item AND its identical twin are ticked in ONE commit; the different item stays open" "[ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 2 ] && sed -n 2p OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] \[T2\] src/a.py — Add new_a\\. VERIFY' && sed -n 3p OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] (identical twin of the item credited at line 2)' && sed -n 4p OVERNIGHT_PROGRESS.md | grep -q '^- \[ \]' && [ \"\$(git log --format=%s -n1)\" = 'chore(queue): auto-credit item(s) whose file this green change touched' ] && [ \"\$(git show --name-only --format= HEAD)\" = OVERNIGHT_PROGRESS.md ]"
ok "T6b the task log records the twin credit" "grep -q 'twin credit: also ticked 1 identical open copy' '$R/task.log'"
mk_ac; ovn_auto_credit "$B1" "$A1" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null
ok "T7 DEFAULT (on): the credited item AND its identical twin are ticked, the different item stays open" "[ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 2 ] && sed -n 4p OVERNIGHT_PROGRESS.md | grep -q '^- \[ \]' && grep -q 'twin credit: also ticked 1 identical open copy' '$R/task.log'"
mk_ac; OVN_TWIN_CREDIT=shadow ovn_auto_credit "$B1" "$A1" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null
ok "T7b OVN_TWIN_CREDIT=shadow: only the first copy is ticked, the log says what 'on' would do" "[ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 1 ] && grep -q 'twin credit SHADOW: would also tick 1 identical open copy' '$R/task.log'"
mk_ac; OVN_TWIN_CREDIT=off ovn_auto_credit "$B1" "$A1" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null
ok "T8 OVN_TWIN_CREDIT=off (= the old behaviour): one tick, no twin log line" "[ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 1 ] && ! grep -q 'twin credit' '$R/task.log'"
# the implement-pass credit script (ovn_credit_already_satisfied.sh): standalone, run in the repo
mk_ac
printf 'src/a.py\nThe task is already done - src/a.py already contains new_a.\n' > "$R/scout.log"
sedi -e 's/ VERIFY: `grep -q "def new_a" src\/a.py`//' OVERNIGHT_PROGRESS.md
if sed --version >/dev/null 2>&1; then   # that script's own `sed -i` is GNU-only (it runs on the box)
  OVN_TWIN_CREDIT=on OVN_IMPL_CREDIT_REQUIRE_VERIFY=off bash "$S/ovn_credit_already_satisfied.sh" "$R/scout.log" OVERNIGHT_PROGRESS.md > "$R/ac.out" 2>&1
  ok "T9 ovn_credit_already_satisfied.sh with OVN_TWIN_CREDIT=on credits the item and its identical twin" "grep -q 'CREDITED=1' '$R/ac.out' && grep -q 'twin credit (on) for line 2: TICKED 1' '$R/ac.out' && [ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 2 ]"
  mk_ac; printf 'src/a.py\nThe task is already done - src/a.py already contains new_a.\n' > "$R/scout.log"; sedi -e 's/ VERIFY: `grep -q "def new_a" src\/a.py`//' OVERNIGHT_PROGRESS.md
  OVN_TWIN_CREDIT=off OVN_IMPL_CREDIT_REQUIRE_VERIFY=off bash "$S/ovn_credit_already_satisfied.sh" "$R/scout.log" OVERNIGHT_PROGRESS.md > "$R/ac.out" 2>&1
  ok "T9b (off = old behaviour) the twin stays open" "grep -q 'CREDITED=1' '$R/ac.out' && [ \"\$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)\" = 1 ]"
else
  echo "  SKIP T9: ovn_credit_already_satisfied.sh needs GNU sed (run on the box)"
fi
# wiring present at the three runner credit sites
ok "T10 run_overnight.sh calls ovn_credit_twins at the delete-executor credit, the ALREADY-GONE credit, the CREATE-EXISTS credit and the scout ALREADY-DONE credit" "[ \"\$(grep -c 'ovn_credit_twins OVERNIGHT_PROGRESS.md' '$RUN')\" = 4 ]"

# ============================== F. filter-new (planner/refill dedupe CLI) ==============================
printf '%s\n%s\n' "$DONE_ANN" "$SIB" > "$W/exist.md"
printf '# header\n%s\n%s\n- [ ] [T1] app/new.py — brand new. VERIFY: x. (c) [feat:r-20261012-q]\n- [ ] [T2] app/new.py — brand new. VERIFY: x. (c) [feat:r-20261012-q]\n' "$PLAIN_OPEN" "$SIB" > "$W/cand.md"
out="$(python3 "$CI" filter-new "$W/exist.md" < "$W/cand.md" 2>"$W/fn.err")"
ok "F1 filter-new drops the candidate that exists annotated in a file, the one that exists as a sibling line, and the in-batch twin; keeps the new item and non-item lines" "[ \"\$(printf '%s\n' \"\$out\" | grep -c '^- \[')\" = 1 ] && printf '%s' \"\$out\" | grep -q 'app/new.py' && printf '%s' \"\$out\" | grep -q '^# header' && grep -q 'kept 1 of 4' '$W/fn.err'"

# ============================== S. scout ALREADY-DONE refusal counter ==============================
D="$W/gate"; rm -rf "$D"; mkdir -p "$D/app"; cd "$D" || exit 1; git init -q -b main
printf 'x=1\n' > app/x.gd
cat > prog.md <<'EOP'
## Next Steps
- [ ] [T1] app/x.gd — Add f. VERIFY: `grep -q NEVER_THERE app/x.gd` (cat:godot) [feat:xlite-20261012-ff]
EOP
GL="$W/gate.log"
gate(){ : > "$GL"; ( cd "$D" && ovn_credit_verify_gate "$D/prog.md" 2 "$GL" "${1:-scout ALREADY-DONE credit}" ); echo $?; }
crf="$OVN_STATE_DIR/credit_refused"
rm -rf "$crf"; r="$(gate)"; r2="$(gate)"; f0="$(ls "$crf"/* 2>/dev/null | head -1)"
ok "S1 DEFAULT (on since 2026-10-13, night review iptv F5): the refusal is rc 1 and each one bumps the credit_refused counter (2 after 2 refusals), no SHADOW line" "[ \"\$r\" = 1 ] && [ -n '$f0' ] && [ \"\$(sed -n 1p '$f0')\" = 2 ] && ! grep -q 'SHADOW' '$GL' && grep -q 'counted toward the credit-refusal park' '$GL'"
rm -rf "$crf"; r="$(OVN_SCOUT_REFUSAL_PARK=shadow gate)"
ok "S1b OVN_SCOUT_REFUSAL_PARK=shadow (the previous default): rc 1, logs 'SHADOW ... would count as refusal 1 of 2' and writes NO counter" "[ \"\$r\" = 1 ] && grep -q 'SHADOW scout ALREADY-DONE refusal at line 2 would count as refusal 1 of 2' '$GL' && [ -z \"\$(ls '$crf' 2>/dev/null)\" ]"
rm -rf "$crf"; r="$(OVN_SCOUT_REFUSAL_PARK=on gate)"; r2="$(OVN_SCOUT_REFUSAL_PARK=on gate)"
f="$(ls "$crf"/* 2>/dev/null | head -1)"
ok "S2 OVN_SCOUT_REFUSAL_PARK=on: each refusal bumps the credit_refused counter (2 after 2 refusals) with the VERIFY-failed reason and the item line" "[ -n '$f' ] && [ \"\$(sed -n 1p '$f')\" = 2 ] && sed -n 2p '$f' | grep -q '^VERIFY failed' && sed -n 3p '$f' | grep -q 'app/x.gd — Add f'"
ok "S3 the counter's key is the one ovn_item_guard.sh reads: '<repo>.<item hash>'" "[ \"\$(basename '$f')\" = \"\$(basename '$D' | sed 's/[^A-Za-z0-9_-]/_/g').\$(ovn_item_hash \"\$(sed -n 2p '$D/prog.md')\")\" ]"
rm -rf "$crf"; r="$(OVN_SCOUT_REFUSAL_PARK=off gate)"
ok "S4 OVN_SCOUT_REFUSAL_PARK=off (= the old behaviour): rc 1, no counter, no SHADOW line" "[ \"\$r\" = 1 ] && [ -z \"\$(ls '$crf' 2>/dev/null)\" ] && ! grep -q 'SHADOW' '$GL'"
rm -rf "$crf"; r="$(OVN_SCOUT_REFUSAL_PARK=on gate 'DONE-trailer credit')"
ok "S5 the DONE-trailer gate label is NOT counted (only the scout ALREADY-DONE credit is)" "[ \"\$r\" = 1 ] && [ -z \"\$(ls '$crf' 2>/dev/null)\" ]"
sedi 's/NEVER_THERE/x=1/' prog.md
rm -rf "$crf"; r="$(OVN_SCOUT_REFUSAL_PARK=on gate)"
ok "S6 a PASSING VERIFY is credited (rc 0) and counts nothing" "[ \"\$r\" = 0 ] && [ -z \"\$(ls '$crf' 2>/dev/null)\" ]"

# ============================== Q. planner dedupe (needs GNU sed + flock + the mock model) ==============================
if sed --version >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 && [ -f "$PL" ]; then
  PORT=18947
  cat > "$W/mock.py" <<'PYEOF2'
import http.server, json, sys
PORT = int(sys.argv[1]); RESP = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0) or 0))
        payload = json.dumps({"choices": [{"message": {"content": open(RESP).read()}}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PYEOF2
  cat > "$W/resp.txt" <<'RESP'
- [ ] [T1] scripts/model_one.gd — Add one. VERIFY: `grep -q one scripts/model_one.gd`. (cat:godot; multifile:no)
- [ ] [T1] scripts/model_two.gd — Add two. VERIFY: `grep -q two scripts/model_two.gd`. (cat:godot; multifile:no)
- [ ] [T2] scripts/model_three.gd — Add three. VERIFY: `grep -q three scripts/model_three.gd`. (cat:godot; multifile:no)
RESP
  python3 "$W/mock.py" "$PORT" "$W/resp.txt" >/dev/null 2>&1 & MOCKPID=$!
  for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
  WD="$W/phome/overnight-queue"; mkdir -p "$WD"/{backlog,roadmap,repos,logs,scripts}
  cp "$S/ovn_credit_items.py" "$S/ovn_path_gate.py" "$S/ovn_delete_executor.py" "$WD/scripts/" 2>/dev/null
  FEAT='Add the model feature to the game'
  SLUG="$(printf '%s' "$FEAT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)"
  setup_pl(){
    rm -rf "$WD/repos/xl" "$WD/state"; mkdir -p "$WD/repos/xl/scripts"; (cd "$WD/repos/xl" && git init -q . && git config user.email t@t && git config user.name t && echo 'extends Node' > scripts/a.gd && git add -A && git commit -q -m base)
    : > "$WD/logs/ovn_planner.log"
    printf '# backlog\n' > "$WD/backlog/xl.md"; printf '# roadmap\n- [ ] [P2] [ready] %s\n' "$FEAT" > "$WD/roadmap/xl.md"
    printf '## Next Steps\n- [x] (already-done, scout-verified) [T1] scripts/model_one.gd — Add one. VERIFY: `grep -q one scripts/model_one.gd`. (cat:godot; multifile:no) [feat:xl-20200101-%s]\n' "$SLUG" > "$WD/repos/xl/OVERNIGHT_PROGRESS.md"
    printf '%s\n' "$1" > "$WD/repos/xl/OVERNIGHT_DONE.md"
  }
  runpl(){ ( cd "$W" && HOME="$W/phome" OVN_MODEL=m LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 OVN_PLAN_MAX_PER_RUN=4 env "$@" bash "$PL" xl >/dev/null 2>>"$W/pl.err" ); }
  setup_pl ""; runpl OVN_PLANNER_DEDUPE=on
  ok "Q1 planner: the model's item that already exists (annotated DONE line, other feat date) is NOT appended; the other two are" "[ \"\$(grep -c '^- \[ \]' '$WD/backlog/xl.md')\" = 2 ] && ! grep -q 'model_one.gd' '$WD/backlog/xl.md' && grep -q 'model_two.gd' '$WD/backlog/xl.md' && grep -q 'model_three.gd' '$WD/backlog/xl.md' && grep -q 'dedupe dropped 1 of 3' '$WD/logs/ovn_planner.log'"
  setup_pl ""; runpl OVN_PLANNER_DEDUPE=off
  ok "Q2 (mutation: OVN_PLANNER_DEDUPE=off = the old behaviour) all three are appended" "[ \"\$(grep -c '^- \[ \]' '$WD/backlog/xl.md')\" = 3 ]"
  setup_pl "- [x] [T1] scripts/model_two.gd — Add two. VERIFY: \`grep -q two scripts/model_two.gd\`. (cat:godot; multifile:no) [feat:xl-20200202-$SLUG]
- [x] [T2] scripts/model_three.gd — Add three. VERIFY: \`grep -q three scripts/model_three.gd\`. (cat:godot; multifile:no) [feat:xl-20200202-$SLUG]"
  runpl OVN_PLANNER_DEDUPE=on
  ok "Q3 every decomposed item already exists: nothing appended, feature marked [decomposed], logged" "[ \"\$(grep -c '^- \[ \]' '$WD/backlog/xl.md')\" = 0 ] && grep -q '\[decomposed\]' '$WD/roadmap/xl.md' && grep -q 'every decomposed item already exists' '$WD/logs/ovn_planner.log'"
  unset OVN_PLANNER_DEDUPE; setup_pl ""; runpl OVN_PLANNER_UNUSED=1
  ok "Q4 (default pin, review r15) with OVN_PLANNER_DEDUPE UNSET the planner dedupes (2 appended, not 3)" "[ \"\$(grep -c '^- \[ \]' '$WD/backlog/xl.md')\" = 2 ]"
else
  echo "  SKIP Q1-Q4: planner integration needs GNU sed + flock (run on the box)"
fi
ok "Q5 (default pin, review r15) the planner reads OVN_PLANNER_DEDUPE with default on" "grep -q 'OVN_PLANNER_DEDUPE:-on}' '$PL'"
ok "Q6 (default pin, review r15) canon keeps backticked identifiers + the VERIFY clause case-sensitive; prose case is ignored" "[ \"\$(canon '- [ ] [T1] a.gd - Rename \`Foo\` now. VERIFY: \`grep -q Foo a.gd\`.')\" != \"\$(canon '- [ ] [T1] a.gd - Rename \`foo\` now. VERIFY: \`grep -q Foo a.gd\`.')\" ] && [ \"\$(canon '- [ ] [T1] a.gd - Rename \`Foo\` now. VERIFY: \`grep -q Foo a.gd\`.')\" != \"\$(canon '- [ ] [T1] a.gd - Rename \`Foo\` now. VERIFY: \`grep -q foo a.gd\`.')\" ] && [ \"\$(canon '- [ ] [T1] a.gd - Rename \`Foo\` NOW. VERIFY: \`grep -q Foo a.gd\`.')\" = \"\$(canon '- [ ] [T1] a.gd - rename \`Foo\` now. VERIFY: \`grep -q Foo a.gd\`.')\" ]"
ok "Q7 (review r15) twin crediting still sees two lines differing only by identifier case as DISTINCT (open_twins)" "printf '%s\n' '- [ ] [T1] a.gd - Rename \`Foo\` now. VERIFY: \`grep -q Foo a.gd\`.' '- [ ] [T1] a.gd - Rename \`foo\` now. VERIFY: \`grep -q Foo a.gd\`.' > '$W/ot.md'; [ -z \"\$(python3 '$CI' tick-twins '$W/ot.md' 1 shadow | grep -E '^SHADOW [1-9]')\" ]"

echo "  $P passed, $F failed"; [ "$F" -eq 0 ]
