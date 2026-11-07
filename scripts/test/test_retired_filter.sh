#!/usr/bin/env bash
# Regression: the doable-item filter must exclude only the real "(retired-...)" markers, never a
# feature tag that merely contains "retired-" (e.g. [feat:...-replace-retired-claude-model-ids]).
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../.." || exit 1
fail=0
ok(){ echo "ok - $1"; }; bad(){ echo "FAIL - $1"; fail=1; }
# 1. no bare retired- exclusion left in any filter
if grep -rnE "(\||\")retired-(\||'|\")" --include='*.sh' --include='*.py' . | grep -v '/test/' | grep -v 'tests/' | grep -q .; then bad "bare retired- exclusion present"; else ok "no bare retired- exclusion"; fi
# 2. queue_health's filter keeps the feature-tag item, drops real markers
f=$(mktemp); trap 'rm -f "$f"' EXIT; cat > "$f" <<'Q'
- [ ] [feat:x-replace-retired-claude-model-ids] do the thing
- [ ] (retired-dead-path) gone
- [ ] (retired-vague) vague
Q
n=$(grep -E '^- \[ \]' "$f" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|\(retired-' | wc -l | tr -d ' ')
[ "$n" = 1 ] && ok "filter counts 1 doable" || bad "filter counted $n"
rm -f "$f"

# 3. Z1 (2026-11-07): the dead-path sanitizer must keep TEST-creation items ("`tests/x.py` - Add test ..."), whose target file does not exist yet by definition, and items whose sibling
#    (same [feat:] tag) creates the path; it must still retire a genuinely dead non-test path. Runs the REAL sanitizer (scripts/ovn_retire_vague.py) in a throwaway sandbox repo.
. "$HERE/lib_safe_tmp.sh" || { bad "lib_safe_tmp.sh missing"; exit 1; }
SB="$(safe_mktemp_dir z1rf)" || { bad "no safe temp dir"; exit 1; }
RV="${RETIRE_VAGUE_PY:-$HERE/../ovn_retire_vague.py}"
mkdir -p "$SB/repo/backend/app" "$SB/repo/backend/tests"; : > "$SB/repo/backend/app/real.py"; : > "$SB/repo/backend/tests/test_exists.py"
cat > "$SB/repo/OVERNIGHT_PROGRESS.md" <<'Q'
## Next Steps
- [ ] [T1] backend/tests/test_new_mw.py — Add test verifying that oversized bodies are rejected with 413. VERIFY: `pytest backend/tests/test_new_mw.py::test_rejects_oversized_413` (cat:test) [feat:mw-1]
- [ ] [T2] `backend/tests/test_new_two.py` — Write a regression test for the retry cap. VERIFY: `pytest backend/tests/test_new_two.py` (cat:test) [feat:mw-2]
- [ ] [T3] backend/old/gone.py — Refactor the legacy helper. VERIFY: `grep -q helper backend/old/gone.py` (cat:test) [feat:gone-1]
- [ ] [T4] backend/app/newmod.py — Wire the limiter into the request path. VERIFY: `grep -q limiter backend/app/newmod.py` (cat:test) [feat:sib-1]
- [ ] [T4] backend/app/newmod.py — Create the limiter helper module here. VERIFY: `grep -q limiter backend/app/newmod.py` (cat:test) [feat:sib-1]
- [ ] [T5] backend/app/newmod2.py — Wire the limiter into the request path. VERIFY: `grep -q limiter backend/app/newmod2.py` (cat:test) [feat:sib-2]
- [ ] [T6] backend/app/thing.py — Wire it (no creation words). VERIFY: `grep -q x backend/app/other_missing.py` (cat:test) [feat:sib-3]
- [ ] [T7] backend/old/gone2.py — Remove the dead shim, the add test for it is elsewhere. VERIFY: `grep -q x backend/old/gone2.py` (cat:test) [feat:gone-2]
Q
( cd "$SB/repo" && python3 "$RV" OVERNIGHT_PROGRESS.md >"$SB/out.txt" 2>&1 )
P="$SB/repo/OVERNIGHT_PROGRESS.md"
kept(){ grep -F -- "$1" "$P" | grep -q '^- \[ \]'; }
retired(){ grep -F -- "$1" "$P" | grep -q '^- \[x\] (retired-dead-path)'; }
kept 'test_new_mw.py — Add test verifying' && ok "Z1 'tests/x.py — Add test ...' (missing test file) is KEPT" || bad "Z1 add-test item was retired as dead-path"
kept 'Write a regression test for the retry cap' && ok "Z1 'Write a regression test' with a missing backticked test path is KEPT" || bad "Z1 write-test item retired"
retired 'backend/old/gone.py — Refactor' && ok "Z1 a genuinely dead NON-test path is still retired" || bad "Z1 dead non-test path was kept"
kept 'Wire the limiter into the request path. VERIFY: `grep -q limiter backend/app/newmod.py` (cat:test) [feat:sib-1]' && ok "Z1 item whose SIBLING (same feat) creates the missing path is KEPT" || bad "Z1 sibling-created path item retired"
retired 'newmod2.py — Wire the limiter' && ok "Z1 same shape WITHOUT a creating sibling is still retired" || bad "Z1 no-sibling item kept"
retired 'Wire it (no creation words)' && ok "Z1 a missing path only in VERIFY with no creation intent is still retired" || bad "Z1 verify-only missing path kept"
retired 'Remove the dead shim, the add test for it is elsewhere' && ok "Z1 'add test' prose on a dead NON-test path does not rescue it" || bad "Z1 add-test prose rescued a dead non-test path"
grep -q "retired 4 dead-path" "$SB/out.txt" && ok "Z1 sanitizer reports the retired count (visible log line)" || bad "Z1 retired count line: $(cat "$SB/out.txt")"
safe_rm_rf "$SB"

# 4. Z1 review-fix (defect 2): the test-creation exemption must be NARROW. Modify-existing-test items and unrelated prose that merely mention tests are still dead when the path is missing;
#    a dead non-test path beside a test path is still dead; docs/spec/*.md is not a test path; a sibling only "creates" the path its own create-intent head names.
SB2="$(safe_mktemp_dir z1rf2)" || { bad "no safe temp dir"; exit 1; }
mkdir -p "$SB2/repo/backend/app"; : > "$SB2/repo/backend/app/real.py"
cat > "$SB2/repo/OVERNIGHT_PROGRESS.md" <<'Q'
## Next Steps
- [ ] [T1] backend/tests/test_renamed_away.py — Add a missing assertion to the existing test for the 404 branch. VERIFY: `pytest backend/tests/test_renamed_away.py` (cat:test) [feat:r1]
- [ ] [T2] backend/tests/test_renamed_away2.py — Add a docstring to the test module. VERIFY: `pytest backend/tests/test_renamed_away2.py` (cat:test) [feat:r2]
- [ ] [T3] backend/tests/test_renamed_away3.py — Adding retries makes the tests stable. VERIFY: `pytest backend/tests/test_renamed_away3.py` (cat:test) [feat:r3]
- [ ] [T4] backend/tests/test_renamed_away4.py — Implement caching so tests run faster. VERIFY: `pytest backend/tests/test_renamed_away4.py` (cat:test) [feat:r4]
- [ ] [T5] backend/old/gone_old.py and backend/tests/test_new5.py — Add test for the shim. VERIFY: `pytest backend/tests/test_new5.py` (cat:test) [feat:r5]
- [ ] [T6] docs/spec/old.md — Add test plan section. VERIFY: `grep -q plan docs/spec/old.md` (cat:test) [feat:r6]
- [ ] [T7] backend/app/helper_new.py — Create new retry helper that calls backend/app/dead_ref.py. VERIFY: `grep -q retry backend/app/helper_new.py` (cat:test) [feat:r7]
- [ ] [T7] backend/app/dead_ref.py — Tune the retry delay. VERIFY: `grep -q delay backend/app/dead_ref.py` (cat:test) [feat:r7]
- [ ] [T8] backend/tests/test_vo8.py — Refactor the fixture setup. VERIFY: `pytest backend/tests/test_vo8.py` then write a test for it (cat:test) [feat:r8]
- [ ] [T9] backend/tests/test_new9.py — Add a new test file covering the limiter. VERIFY: `pytest backend/tests/test_new9.py` (cat:test) [feat:r9]
- [ ] [T10] backend/tests/test_new10.py — Write unit tests for the cap. VERIFY: `pytest backend/tests/test_new10.py` (cat:test) [feat:r10]
- [ ] [T11] backend/app/mod11.py — Create backend/app/other11.py with the helper. VERIFY: `grep -q x backend/app/other11.py` (cat:test) [feat:r11]
Q
P2="$SB2/repo/OVERNIGHT_PROGRESS.md"
runrv(){ ( cd "$SB2/repo" && cp OVERNIGHT_PROGRESS.md OVERNIGHT_PROGRESS.md.orig && python3 "$1" OVERNIGHT_PROGRESS.md >/dev/null 2>&1; mv OVERNIGHT_PROGRESS.md "$2"; mv OVERNIGHT_PROGRESS.md.orig OVERNIGHT_PROGRESS.md ); }
runrv "$RV" "$SB2/new.md"
r2(){ grep -F -- "$2" "$1" | grep -q '^- \[x\] (retired-dead-path)'; }
k2(){ grep -F -- "$2" "$1" | grep -q '^- \[ \]'; }
for pair in "T1:add a missing assertion to the existing test" "T2:docstring to the test module" "T3:Adding retries makes the tests stable" "T4:Implement caching so tests run faster" ; do
  needle="${pair#*:}"; needle="$(grep -o "\[T${pair%%:*}\].*" "$P2" | head -1 | cut -c1-40)"
done
chk_ret(){ r2 "$SB2/new.md" "$1" && ok "Z1r $2 is retired (dead path)" || bad "Z1r $2 was KEPT"; }
chk_keep(){ k2 "$SB2/new.md" "$1" && ok "Z1r $2 is KEPT" || bad "Z1r $2 was retired"; }
chk_ret '[T1] backend/tests/test_renamed_away.py' "modify-existing-test item (add assertion to existing test)"
chk_ret '[T2] backend/tests/test_renamed_away2.py' "docstring-to-the-test-module item"
chk_ret '[T3] backend/tests/test_renamed_away3.py' "'Adding retries makes the tests stable' prose"
chk_ret '[T4] backend/tests/test_renamed_away4.py' "'Implement caching so tests run faster' prose"
chk_ret '[T5] backend/old/gone_old.py and' "dead non-test path listed beside a created test path"
chk_ret '[T6] docs/spec/old.md' "docs/spec/old.md + 'Add test plan' (not a test path)"
chk_ret '[T7] backend/app/dead_ref.py' "dead path merely NAMED by a 'create new helper' sibling"
chk_ret '[T8] backend/tests/test_vo8.py' "test-creation words only AFTER the VERIFY clause -- not an exemption"
chk_keep '[T9] backend/tests/test_new9.py' "'Add a new test file' creating a missing test path"
chk_keep '[T10] backend/tests/test_new10.py' "'Write unit tests' creating a missing test path"
chk_keep '[T11] backend/app/mod11.py' "item with a global create-intent (Create <path>) naming a missing path"
# MUTATIONS: each must flip a Z1r expectation
python3 - "$RV" "$SB2/mut_head.py" "$SB2/mut_broad.py" "$SB2/mut_sib.py" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
h='return re.split(r"VERIFY:", body, maxsplit=1)[0]'
assert h in s
open(sys.argv[2],"w").write(s.replace(h,"return body"))
i=s.index("TEST_CREATE_INTENT = re.compile("); j=s.index("\n", i)
old='TEST_CREATE_INTENT = re.compile(r"\\b(?:add|adds|adding|write|writes|create|creates|author|introduce|implement)\\b[^.;\\n`]{0,60}?\\b(?:tests?|test[ -]cases?|specs?|unit[ -]tests?|regression[ -]tests?)\\b", re.I)'
open(sys.argv[3],"w").write(s[:i]+old+s[j:])
t=s.replace("        out.add(paths[0])","        out.update(paths)").replace("    for m in _CREATE_VERB_PATH.finditer(head):\n        out.add(m.group(1))","    pass")
assert t!=s
t=t.replace("    if paths and _has_create_intent(head) and not out:","    if paths and _has_create_intent(head):")
open(sys.argv[4],"w").write(t)
PY
for f in mut_head mut_broad mut_sib; do [ -s "$SB2/$f.py" ] || bad "mutant file $f not generated"; done
runrv "$SB2/mut_head.py" "$SB2/m_head.md"; runrv "$SB2/mut_broad.py" "$SB2/m_broad.md"; runrv "$SB2/mut_sib.py" "$SB2/m_sib.md"
grep -F '[T8]' "$SB2/m_head.md" | grep -q '^- \[ \]' && ok "Z1r MUTANT _head(body)->body keeps the VERIFY-trailing 'write a test' item (our T8 assertion would go red)" || bad "Z1r head mutant survived (T8 still retired)"
for n in T1 T2 T3 T4; do grep -F "[$n]" "$SB2/m_broad.md" | grep -q '^- \[ \]' && ok "Z1r MUTANT broad regex keeps $n (assertion would go red)" || bad "Z1r broad-regex mutant survived on $n"; done
grep -F '[T7] backend/app/dead_ref.py' "$SB2/m_sib.md" | grep -q '^- \[ \]' && ok "Z1r MUTANT sibling-takes-all-paths keeps the dead_ref item (assertion would go red)" || bad "Z1r sibling mutant survived"
safe_rm_rf "$SB2"
exit $fail
