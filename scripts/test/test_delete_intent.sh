#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 2): `ovn_delete_executor.py intent` - is the item's LEADING instruction a whole-FILE delete?
# Live bug: run_overnight.sh injected "this task deletes a file: end your commit message with DELETE: <path>" for "Remove the unused import(s) in this
# file: ..." supply items (the model then could not edit the file), and ovn_path_gate.py called the already-edited file STILL_EXISTS.
# Covers: the python subcommand (positives, near-miss negatives), the bash wrapper + kill switch, the path-gate wiring, the run_overnight.sh call site,
# and a MUTATION control (the same negatives against a copy whose partial-noun rule is disabled must flip to "delete").
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
EX="$S/ovn_delete_executor.py"; GATE="$S/ovn_path_gate.py"; FIX="$S/lib_fixup.sh"; RUN="$S/../run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
intent(){ python3 "$1" intent "$2"; }

# --- positives: whole-file delete intent -> exit 0
POS=(
  'Delete the orphaned file scripts/x.gd.uid'
  'Delete the dead file app/a.py'
  'Remove the stale test file tests/test_old.py'
  'Delete scripts/x.gd.uid'
  '- [ ] [T3] app/a.py — Delete this dead module.'
  '- [ ] [T3] app/a.py — Delete the dead file; nothing imports it.'
  '- [ ] [T3] src/stale.py — Delete.'
  '- [ ] [T3] src/stale.py — Remove the dead route file'
  'Delete the unused file app/function.py'
  'Delete the dead file app/import_helpers.py'
  '- [ ] [T2] scripts/x.gd.uid — Delete the orphaned file scripts/x.gd.uid'
  # REAL fleet lines from the OVERNIGHT_PROGRESS.md files (round-3 review: the old path-gate rule called all of these deletes; the first delete_intent missed them)
  '- [x] [T3] iptv-backend/app/jobs/test_main_import.py — Delete duplicate stub covered by `tests/test_main.py`. VERIFY: `test ! -f iptv-backend/app/jobs/test_main_import.py`. (cat:refactor; multifile:no)'
  '- [x] [T3] iptv-backend/app/jobs/test_safe_send_email.py — Delete duplicate stub covered by `tests/test_auth_safe_send_email.py`. VERIFY: `test ! -f iptv-backend/app/jobs/test_safe_send_email.py`.'
  '- [ ] [T3] iptv-backend/app/jobs/test_auth_registration_resilience.py — Delete dead stub containing broken `patch()` call. VERIFY: `test ! -f iptv-backend/app/jobs/test_auth_registration_resilience.py`.'
  '- [x] [T1] billwatch-backend/app/services/caching.py — Delete this orphaned 58-line CacheService module. VERIFY: `test ! -f billwatch-backend/app/services/caching.py`. (cat:backend; multifile:no)'
  '- [x] (retired-dead-path) [T1] billwatch-backend/app/services/export.py — Delete this orphaned 37-line ExportService stub (export_bills_pdf/export_legislator_voting_record always return empty; the real, wired-in export path is elsewhere). VERIFY: `test ! -f billwatch-backend/app/services/export.py`.'
  '- [x] (retired-dead-path) [T1] billwatch-backend/app/services/webhook_service.py — Delete this orphaned 68-line WebhookService (register_webhook/get_webhooks/trigger_webhook/delete_webhook, no consumer anywhere). VERIFY: `test ! -f billwatch-backend/app/services/webhook_service.py`.'
  '- [x] (retired-dead-path) [T1] billwatch-web/src/components/BillCommentsSection.vue — Delete this 97-line orphaned component (calls the double-prefixed, backend-less `/api/bills/${billId}/comments`, reads `route.params.id` without a guard). VERIFY: `test ! -f billwatch-web/src/components/BillCommentsSection.vue`.'
  '- [x] (retired-dead-path) [T1] billwatch-web/src/components/BillSummaryCard.vue — Delete this orphaned 124-line component (no test file exists for it, so nothing else to remove). VERIFY: `test ! -f billwatch-web/src/components/BillSummaryCard.vue`.'
  '- [x] [T1] billwatch-web/src/stores/billChat.ts — Delete this orphaned 179-line Pinia store (fetchSummary/fetchMessages/postMessage/clearBillCache/clearAllCache, uses raw axios instead of the shared api client). VERIFY: `test ! -f billwatch-web/src/stores/billChat.ts`.'
  '- [x] [T1] billwatch-web/src/components/__tests__/DeleteAccountButton.spec.js — Delete the stale duplicate test file that is not matched by vitest include globs and contains a latent scoping bug. VERIFY: `test ! -f billwatch-web/src/components/__tests__/DeleteAccountButton.spec.js`.'
  'Delete tests/test_x.py as it duplicates tests/test_y.py'"'"'s coverage'
  'Remove the duplicate test file a/b.py (covered by c)'
  'Delete this orphaned 58-line module app/cache.py'
  '- [ ] [T3] app/a.py — Delete.'
  '- [ ] [T3] app/a.py — Delete'
)
i=0
for t in "${POS[@]}"; do
  i=$((i+1)); intent "$EX" "$t" >/dev/null 2>&1; rc=$?
  ok "positive $i exits 0: ${t:0:70}" "[ $rc = 0 ]"
done

# --- near-miss negatives: partial removals -> exit 1 (the test FAILS if any returns 0)
NEG=(
  'Remove the unused import(s) in this file: `a`, `b` (ruff F401).'
  '- [ ] [T2] app/x.py — Remove the unused import(s) in this file: `a`, `b` (ruff F401). VERIFY: ruff check app/x.py --select F401'
  'Delete the unused import(s) from the import statement(s) in app/x.py'
  'Remove the get_faction function from enemy_faction_map.gd'
  'Delete the unused import line'
  '- [ ] [T3] app/x.py — Delete `foo_helper`'
  '- [ ] [T2] app/x.py — Remove the unused import'
  '- [ ] [T2] app/x.py — Remove the dead function'
  '- [ ] [T3] app/x.py — Remove the duplicated helper from the end of the module'
  'Remove the @deprecated decorator from app/x.py'
  'Delete the stale entry in config/keys.yaml'
  'Remove the stub body of run() in app/x.py'
  'Delete the unused symbol Foo from app/x.py'
  'Remove dead code in app/x.py'
  'This task will delete the file foo.py later'
  'Add a test for app/x.py'
  '- [ ] [T1] a/b.py — Remove this file'"'"'s unused helper functions'
  'Remove the file `a/b.py`'"'"'s unused import'
  'Remove the unused scripts directory reference'
  'Remove unused file references from this module'
  'Delete the module'"'"'s dead helper methods'
  # real partial-removal lines (stay NOT deletes after the round-3 loosening)
  '- [x] [T2] backend/app/services/dispatcher.py — Remove the `dispatch_flow()` function definition and its docstring. VERIFY: `grep -q "def dispatch_flow" backend/app/services/dispatcher.py`.'
  '- [x] [T1] iptv-backend/app/services/content.py — Delete the dead `get_vod_catalog(db, page=1, limit=10)` stub function (always returns `[]`, zero callers). VERIFY: `! grep -q "def get_vod_catalog" iptv-backend/app/services/content.py`.'
  '- [x] [T2] billwatch-backend/app/services/summary_scheduler.py — Remove the dead `cleanup_old_summaries` method (lines 158-186) as it is never called in the codebase.'
  '- [x] [T1] gitlark/backend/app/routers/repo_analysis.py — Remove the unused `from app.services.diff_stats_format import format_diff_stats` import (line ~26); confirmed via grep it is never called anywhere in this file.'
  '- [x] [T1] billwatch-web/src/pages/SearchPage.vue — Remove the leading `/api` from the `api.get('"'"'/api/search/advanced'"'"', ...)` call to use `api.get('"'"'/search/advanced'"'"', ...)`.'
  '- [ ] [T2] app/x.py — Remove the 58-line block at the end'
  '- [ ] [T2] app/x.py — Remove the duplicate function'
  '- [ ] [T2] app/x.py — Remove the duplicate imports'
  '- [ ] [T2] app/x.py — Delete the 12-line helper from this module'
  '- [ ] [T2] app/x.py — Delete the dead `foo_helper` stub containing a TODO'
  ''
)
i=0; NEGBAD=0
for t in "${NEG[@]}"; do
  i=$((i+1)); intent "$EX" "$t" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && NEGBAD=$((NEGBAD+1))
  ok "negative $i exits 1: ${t:0:70}" "[ $rc = 1 ]"
done
ok "no negative returned 0" "[ $NEGBAD = 0 ]"
ok "no argument -> exit 1 (never crashes into 'delete')" "python3 '$EX' intent; [ \$? = 1 ]"
# multi-line text (runner passes prompt + top item): a delete line anywhere counts, partial-only text does not
ok "multi-line: generic prompt + a delete item line -> 0" "python3 '$EX' intent \"\$(printf 'Work the top item.\n- [ ] [T3] app/a.py — Delete the dead file')\""
ok "multi-line: generic prompt + an import-removal item line -> 1" "python3 '$EX' intent \"\$(printf 'Remove nothing else.\n- [ ] [T2] app/a.py — Remove the unused import(s) in this file: \`os\`')\"; [ \$? = 1 ]"

# --- MUTATION CONTROL: disable the partial-noun rule in a copy; the import/function negatives must now be (wrongly) classified as deletes
python3 - "$EX" "$tmp/mutant.py" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
n = s.count("pm = INTENT_PARTIAL.search(phrase_n)")
assert n == 1, n
assert s.count("INTENT_PARTIAL.search(head_n) is None") == 1
open(sys.argv[2], "w").write(s.replace("pm = INTENT_PARTIAL.search(phrase_n)", "pm = None").replace("INTENT_PARTIAL.search(head_n) is None", "True"))
PY
MUT=0
for t in '- [ ] [T2] app/x.py — Remove the unused import' '- [ ] [T2] app/x.py — Remove the dead function'; do intent "$tmp/mutant.py" "$t" >/dev/null 2>&1 && MUT=$((MUT+1)); done
ok "MUTATION: with the partial-noun rule disabled the two implicit-object partial items flip to delete (flipped $MUT of 2)" "[ $MUT -eq 2 ]"
# second mutant: drop the container-preposition rule -> 'Delete the stale entry in config/keys.yaml'-style container paths must flip for a non-partial noun
python3 - "$EX" "$tmp/mutant2.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "    if INTENT_CONTAINER_PREP.search(phrase[:obj]):\n        return False\n"
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, ""))
PY
ok "MUTATION: without the container-preposition rule 'Remove the leftover tracing from app/x.py' (a path container) flips to delete, with it it does not" \
   "intent '$EX' 'Remove the leftover tracing from app/x.py'; [ \$? = 1 ] && intent '$tmp/mutant2.py' 'Remove the leftover tracing from app/x.py'"

# third mutant: drop the possessor / partial-modifier rule (_file_object_ok always true) -> the file-noun false positives flip back to 'delete'
python3 - "$EX" "$tmp/mutant3.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "    if not _file_object_ok(phrase, end):\n        return False\n"
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, ""))
PY
MUT3=0
for t in 'Remove this file'"'"'s unused helper functions' 'Remove unused file references from this module' 'Remove the unused scripts directory reference'; do intent "$tmp/mutant3.py" "$t" >/dev/null 2>&1 && MUT3=$((MUT3+1)); done
ok "MUTATION: without the possessor/modifier rule the 3 file-noun false positives flip to delete (flipped $MUT3 of 3)" "[ $MUT3 -eq 3 ]"

# --- BACK-STOP (round-3 fix): a leading delete verb + the item's own VERIFY `test ! -f <its own path>` is a whole-file delete whatever the noun phrase looks like
ok "back-stop: odd phrasing + VERIFY test ! -f <own path> -> delete (0)" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Delete the old thing nobody uses anymore for anything real. VERIFY: \`test ! -f app/jobs/t.py\`.'"
ok "back-stop: the same odd phrasing WITHOUT the VERIFY -> not a delete (the back-stop is not a blanket verb rule)" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Delete the old thing nobody uses anymore for anything real. VERIFY: \`pytest\`.'; [ \$? = 1 ]"
ok "back-stop: VERIFY test ! -f of a DIFFERENT path does not count" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Delete the old thing nobody uses anymore for anything real. VERIFY: \`test ! -f app/jobs/other.py\`.'; [ \$? = 1 ]"
ok "back-stop: a path that merely extends the item path (t.py vs t.pyc) does not count" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Delete the old thing nobody uses anymore for anything real. VERIFY: \`test ! -f app/jobs/t.pyc\`.'; [ \$? = 1 ]"
ok "back-stop: a non-delete verb with a test ! -f VERIFY is not a delete (verb rule first)" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Rewrite the thing. VERIFY: \`test ! -f app/jobs/t.py\`.'; [ \$? = 1 ]"
ok "back-stop: a partial removal whose VERIFY happens to test ! -f its own path is still a delete (the VERIFY says the file must go)" "intent '$EX' '- [ ] [T3] app/jobs/t.py — Remove the thing and the import. VERIFY: \`test ! -f app/jobs/t.py\`.'"
# the path gate takes the new rule: STILL_EXISTS for the REAL iptv/billwatch shapes (the old rule said STILL_EXISTS, the first delete_intent said OK)
RG="$tmp/rg"; mkdir -p "$RG/iptv-backend/app/jobs" "$RG/billwatch-backend/app/services"; touch "$RG/iptv-backend/app/jobs/test_main_import.py" "$RG/billwatch-backend/app/services/caching.py"
printf '%s\n' '## Next Steps' \
  '- [ ] [T3] iptv-backend/app/jobs/test_main_import.py — Delete duplicate stub covered by `tests/test_main.py`. VERIFY: `test ! -f iptv-backend/app/jobs/test_main_import.py`.' \
  '- [ ] [T1] billwatch-backend/app/services/caching.py — Delete this orphaned 58-line CacheService module. VERIFY: `test ! -f billwatch-backend/app/services/caching.py`.' > "$RG/P.md"
rg(){ python3 "$GATE" "$RG/P.md" "$1" "$RG"; }
ok "path gate (real iptv line): duplicate stub delete, file still there -> STILL_EXISTS (the 'delete item whose file still exists' guard protects it)" "[ \"\$(rg 2)\" = 'STILL_EXISTS iptv-backend/app/jobs/test_main_import.py' ]"
ok "path gate (real billwatch line): '58-line module' delete, file still there -> STILL_EXISTS" "[ \"\$(rg 3)\" = 'STILL_EXISTS billwatch-backend/app/services/caching.py' ]"
rm -f "$RG/iptv-backend/app/jobs/test_main_import.py"
ok "path gate (real iptv line): the file already gone -> OK (not MISSING, which would refuse the already-done credit)" "[ \"\$(rg 2)\" = 'OK iptv-backend/app/jobs/test_main_import.py' ]"
# the runner-side injection wrapper agrees (hint injected for these)
ok "ovn_is_delete_intent: real 'Delete duplicate stub covered by' line -> delete (rc 0)" "( source '$FIX'; ovn_is_delete_intent '- [x] [T3] iptv-backend/app/jobs/test_main_import.py — Delete duplicate stub covered by \`tests/test_main.py\`. VERIFY: \`test ! -f iptv-backend/app/jobs/test_main_import.py\`.' )"

# --- MUTATIONS for the round-3 additions: each restores one piece of the first delete_intent; the real lines it was written for must flip back to 'not a delete'
python3 - "$EX" "$tmp" <<'PY'
import sys
S, T = sys.argv[1], sys.argv[2]
src = open(S).read()
def mut(name, a, b):
    assert src.count(a) == 1, (name, a)
    open(T + "/mut_" + name + ".py", "w").write(src.replace(a, b))
mut("count", 'INTENT_COUNT_MOD.sub(lambda mm: "X" * len(mm.group(0)), INTENT_PARTIAL_MODIFIER.sub(', '(lambda x: x)(INTENT_PARTIAL_MODIFIER.sub(')
mut("clause", "    cm = INTENT_CLAUSE_CUT.search(raw_phrase)\n", "    cm = None\n")
mut("dup", 'r"stub\\s+bod(?:y|ies)|bod(?:y|ies)', 'r"duplicate|stub\\s+bod(?:y|ies)|bod(?:y|ies)')
mut("backstop", "            if INTENT_VERB.match(desc) and re.search(", "            if False and re.search(")
PY
CNT='- [x] [T1] billwatch-backend/app/services/caching.py — Delete this orphaned 58-line CacheService module. (cat:backend)'
STUB='- [x] [T3] app/jobs/t.py — Delete dead stub containing broken `patch()` call.'
DUP='Remove the duplicate test file a/b.py (covered by c)'
ODD='- [ ] [T3] app/jobs/t.py — Delete the old thing nobody uses anymore for anything real. VERIFY: `test ! -f app/jobs/t.py`.'
ok "MUTATION (count modifier not neutralised): the '58-line CacheService module' line flips to NOT a delete" "intent '$EX' '$CNT'; intent '$tmp/mut_count.py' '$CNT'; [ \$? = 1 ]"
ok "MUTATION (clause cut removed): 'Delete dead stub containing broken patch() call' (the backticked clause) flips to NOT a delete" "intent '$EX' '$STUB'; intent '$tmp/mut_clause.py' '$STUB'; [ \$? = 1 ]"
ok "MUTATION ('duplicate' a partial noun again): 'Remove the duplicate test file a/b.py (covered by c)' flips to NOT a delete" "intent '$EX' '$DUP'; intent '$tmp/mut_dup.py' '$DUP'; [ \$? = 1 ]"
ok "MUTATION (back-stop removed): the odd-phrasing + VERIFY test ! -f line flips to NOT a delete" "intent '$EX' '$ODD'; intent '$tmp/mut_backstop.py' '$ODD'; [ \$? = 1 ]"

# --- bash wrapper (lib_fixup.sh) and its kill switch
# shellcheck disable=SC1090
source "$FIX"
IMP='- [ ] [T2] app/x.py — Remove the unused import(s) in this file: `a`, `b` (ruff F401).'
ok "ovn_is_delete_intent: import-removal item -> not a delete (rc 1)" "ovn_is_delete_intent '$IMP'; [ \$? = 1 ]"
ok "ovn_is_delete_intent: whole-file item -> delete (rc 0)" "ovn_is_delete_intent 'Delete the dead file app/a.py'"
ok "OVN_DELETE_INTENT=legacy restores the old regex (import item matches again, proving the switch works)" "OVN_DELETE_INTENT=legacy ovn_is_delete_intent '$IMP'"

# python helper NOT deployed next to the lib: fall back to the legacy regex (consistent with run_overnight.sh's lib-missing fallback), NOT 'never a delete'
mkdir -p "$tmp/nolibpy"; cp "$FIX" "$tmp/nolibpy/lib_fixup.sh"
ok "no ovn_delete_executor.py beside lib_fixup.sh: a real delete item still gets the delete hint (legacy regex, rc 0)" "( source '$tmp/nolibpy/lib_fixup.sh'; ovn_is_delete_intent '- [ ] [T1] Remove the dead file app/old.py - nothing imports it.' )"
ok "no ovn_delete_executor.py beside lib_fixup.sh: a non-delete text is still rc 1" "( source '$tmp/nolibpy/lib_fixup.sh'; ovn_is_delete_intent 'Add a test for app/x.py'; [ \$? = 1 ] )"
# mutation: the old fail-closed behaviour ('[ -f $_py ] || return 1') would make the first assertion fail
sed 's#|| \[ ! -f "\$_py" \]##' "$FIX" > "$tmp/nolibpy/mut_lib_fixup.sh"
ok "MUTATION: with the fallback removed (python missing => not a delete) the delete item is not recognised" "( source '$tmp/nolibpy/mut_lib_fixup.sh'; ovn_is_delete_intent '- [ ] [T1] Remove the dead file app/old.py - nothing imports it.'; [ \$? != 0 ] )"

# --- ovn_path_gate.py wiring: a delete verb in front of an import list must not make the (existing) target STILL_EXISTS
W="$tmp/w"; mkdir -p "$W/app"; touch "$W/app/x.py" "$W/app/dead.py"
printf '%s\n' '## Next Steps' \
  '- [ ] [T2] app/x.py — Remove the unused import(s) in this file: `os` (ruff F401).' \
  '- [ ] [T2] app/dead.py — Delete this dead module.' \
  '- [ ] [T2] app/gone.py — Delete this dead module.' > "$W/P.md"
g(){ python3 "$GATE" "$W/P.md" "$1" "$W"; }
ok "path gate: import-removal item with an existing file -> OK (was STILL_EXISTS)" "[ \"\$(g 2)\" = 'OK app/x.py' ]"
ok "path gate: whole-file delete, file still there -> STILL_EXISTS (unchanged)" "[ \"\$(g 3)\" = 'STILL_EXISTS app/dead.py' ]"
ok "path gate: whole-file delete, file gone -> OK (unchanged)" "[ \"\$(g 4)\" = 'OK app/gone.py' ]"
ok "path gate: OVN_DELETE_INTENT=legacy brings the old STILL_EXISTS back for the import item (control)" "[ \"\$(OVN_DELETE_INTENT=legacy g 2)\" = 'STILL_EXISTS app/x.py' ]"

# --- run_overnight.sh call site: executed code uses the helper, the inline delete regex is gone from the injection test
ok "run_overnight.sh calls ovn_is_delete_intent at the DELETE-trailer injection (code line, not a comment)" "[ \"\$(grep -c '^  if ovn_is_delete_intent ' '$RUN')\" = 1 ]"
ok "run_overnight.sh no longer pipes the prompt into the inline delete/remove regex" "[ \"\$(grep -c 'top_progress_item\" | grep -qiE' '$RUN')\" = 0 ]"
# --- picker patterns (spec 'Picker patterns'): BLOCKED parks an item only as the UPPER-CASE tag; the same top-item picker feeds the delete-intent injection above
LEGACY="$(grep -c "grep -viE '[^']*HARD FILE BAN|BLOCKED|" "$RUN")"
NEWSHAPE="$(grep -c 'grep -viE "\${OVN_PARKED_CI_ERE:-' "$RUN")"
ok "run_overnight.sh: no picker still uses the case-insensitive '...|BLOCKED|...' alternation" "[ '$LEGACY' = 0 ]"
ok "run_overnight.sh: the 7 open-item pickers use the CI/CS pattern pair (found $NEWSHAPE)" "[ '$NEWSHAPE' -ge 7 ]"
PL="$(grep -m1 '^    _ovn_top_progress_item="\$(grep -E' "$RUN")"
PR="$tmp/pr"; mkdir -p "$PR"
printf '%s\n' '## Next Steps' \
  '- [ ] [BLOCKED: waiting on a human] [T2] app/a.py — parked by its upper-case tag.' \
  '- [ ] [AUTO-SKIP after 3 failed-to-land cycles] [T2] app/b.py — auto-skipped.' \
  '- [ ] [T2] app/c.py — Fix the helper that was blocked by a stale import last week. VERIFY: `true`' \
  '- [ ] [T2] app/d.py — a later item.' > "$PR/OVERNIGHT_PROGRESS.md"
pick(){ ( repo="$PR"; ovn_bug_first_order(){ cat; }; prompt=""; eval "$PL"; printf '%s' "$_ovn_top_progress_item" ); }
ok "picker: UPPER-CASE BLOCKED and AUTO-SKIP lines are skipped, a lower-case 'blocked' in prose is NOT (app/c.py is the top item)" "case \"\$(pick)\" in *app/c.py*'stale import'*) true;; *) false;; esac"
ok "picker control: with only the legacy case-insensitive rule the same line would be hidden (grep -i blocked drops app/c.py)" "[ -z \"\$(grep -E '^- \\[ \\]' '$PR/OVERNIGHT_PROGRESS.md' | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\\[CLAUDE\\]' | grep 'app/c.py')\" ]"
# sourcing + inline defaults: extract the 3 lines the runner executes and run them with / without a lib_parked_pattern.sh
SRCL="$(grep -n 'lib_parked_pattern.sh" \]' "$RUN" | head -1 | cut -d: -f1)"
DEFL="$(sed -n "$((SRCL+1)),$((SRCL+2))p" "$RUN")"
SRCLINE="$(sed -n "${SRCL}p" "$RUN")"
ok "defaults: no lib => CI default has the 5 tags, CS default is BLOCKED" "( SCRIPT_DIR='$tmp/nolib'; eval \"\$SRCLINE\"; eval \"\$DEFL\"; [ \"\$OVN_PARKED_CS_ERE\" = BLOCKED ] && case \"\$OVN_PARKED_CI_ERE\" in *AUTO-SKIP*HUMAN-ONLY*'human/'*'HARD FILE BAN'*CLAUDE*) true;; *) false;; esac )"
mkdir -p "$tmp/withlib/scripts"; printf 'OVN_PARKED_CI_ERE="LIBTAG"\nOVN_PARKED_CS_ERE="LIBCS"\n' > "$tmp/withlib/scripts/lib_parked_pattern.sh"
ok "defaults: a lib_parked_pattern.sh (spec-compiler-v2) wins over the inline defaults" "( SCRIPT_DIR='$tmp/withlib'; eval \"\$SRCLINE\"; eval \"\$DEFL\"; [ \"\$OVN_PARKED_CI_ERE\" = LIBTAG ] && [ \"\$OVN_PARKED_CS_ERE\" = LIBCS ] )"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
