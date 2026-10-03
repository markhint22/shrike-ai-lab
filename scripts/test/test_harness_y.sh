#!/usr/bin/env bash
# Harness Y (2026-10-02): schema-budget / best-of-N circuit breakers (Y1), scout grounding (Y2), the "model/API error" classifier (Y3).
# Every behaviour change has a NEGATIVE case (the new rule fires) and a BENIGN case (the old behaviour is untouched). Each NEW assertion was also run
# against the pre-change tree (see the commit message) to prove it fails there. The real functions/scripts are exercised with stubs:
#   Y1  lib_item_select.sh helpers, ovn_fold_migration_items.py, the REAL ovn_item_guard.sh, and the REAL run_overnight.sh main loop (stub aider)
#   Y2  ovn_scout_ground.py (pure, on throwaway git repos) and the REAL run_aider_fix_task via lib_ro_harness_y_driver.sh
#   Y3  ovn_log_has_api_error on the real iptv lint-traceback shape, and the real main loop's status
# (Y4, the unverified staged-run outcome row, is in test_harness_y_stage.sh.)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_ro_core.sh"
. "$Q/scripts/lib_item_select.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${T:-}" ] && rm -rf "$T"' EXIT
gitq(){ git -c user.email=t@t -c user.name=t "$@"; }
# the lib_ro_core ok() takes 1/0; wrap a command
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }

echo "== Y1 pure helpers =="
L="$TMP/l"; mkdir -p "$L"
printf 'blah\nFAILED tests/test_migration_drift.py::test_alembic_head_matches_models - AssertionError: Migration drift detected\n' > "$L/drift.log"
printf 'blah\nFAILED tests/test_other.py::test_b - assert 1 == 2\nERROR tests/test_c.py::test_c - boom\n' > "$L/other.log"
printf 'MULTIPLE HEADS [0010_content_group, 0012]\n' > "$L/heads.log"
printf -- '--- MIGRATION-SAFETY GATE: commit forked/broke the Alembic migration chain ---\n' > "$L/gate.log"
eq "signature: status reverted(migration-fork) alone" migration-drift "$(ovn_attempt_signature 'reverted(migration-fork)' /nonexistent)"
eq "signature: drift test in the log" migration-drift "$(ovn_attempt_signature 'no-op(reverted-red)' "$L/drift.log")"
eq "signature: MULTIPLE HEADS in the log" migration-drift "$(ovn_attempt_signature 'no-op' "$L/heads.log")"
eq "signature: MIGRATION-SAFETY GATE in the log" migration-drift "$(ovn_attempt_signature 'no-op' "$L/gate.log")"
eq "BENIGN signature: an unrelated failing test is no signature" "" "$(ovn_attempt_signature 'no-op(reverted-red)' "$L/other.log")"
eq "BENIGN signature: missing log + plain status is no signature" "" "$(ovn_attempt_signature 'no-op' /nonexistent)"
eq "failing ids: sorted FAILED+ERROR node ids" "tests/test_c.py::test_c
tests/test_other.py::test_b" "$(ovn_failing_ids "$L/other.log" | sort)"
eq "failing ids: empty for a log without a pytest summary" "" "$(ovn_failing_ids "$L/heads.log")"
eq "drift cap: 5 -> 2 after a drift failure" 2 "$(ovn_bestn_after_failure 5 migration-drift)"
eq "drift cap: 3 -> 2" 2 "$(ovn_bestn_after_failure 3 migration-drift)"
eq "BENIGN drift cap: budget 2 or 1 is not raised" "2 1" "$(ovn_bestn_after_failure 2 migration-drift) $(ovn_bestn_after_failure 1 migration-drift)"
eq "BENIGN drift cap: an unrelated failure keeps the full budget" 5 "$(ovn_bestn_after_failure 5 '')"
eq "drift cap kill switch OVN_BESTOF_N_DRIFT_CAP=0" 5 "$(OVN_BESTOF_N_DRIFT_CAP=0 ovn_bestn_after_failure 5 migration-drift)"
eq "drift cap tunable OVN_BESTOF_N_DRIFT_CAP=3" 3 "$(OVN_BESTOF_N_DRIFT_CAP=3 ovn_bestn_after_failure 5 migration-drift)"
k1="$(ovn_repeat_key h1 "$L/drift.log")"; k2="$(ovn_repeat_key h1 "$L/drift.log")"; k3="$(ovn_repeat_key h1 "$L/other.log")"; k4="$(ovn_repeat_key h2 "$L/drift.log")"
eq "repeat key is stable for the same id set" "$k1" "$k2"
ok "repeat key differs for a different id set" "$([ -n "$k3" ] && [ "$k1" != "$k3" ] && echo 1 || echo 0)"
ok "repeat key differs for a different ITEM with the same ids" "$([ "$k1" != "$k4" ] && echo 1 || echo 0)"
eq "streak: identical key -> 2" 2 "$(ovn_repeat_streak "$k1" "$k2" 1)"
eq "streak: identical key again -> 3" 3 "$(ovn_repeat_streak "$k1" "$k2" 2)"
eq "BENIGN streak: a different set restarts at 1" 1 "$(ovn_repeat_streak "$k1" "$k3" 2)"
eq "BENIGN streak: an empty current key (no ids) restarts at 1" 1 "$(ovn_repeat_streak "$k1" "" 2)"
eq "BENIGN: no failing ids -> empty key" "" "$(ovn_repeat_key h1 "$L/heads.log")"
for i in $(seq 1 25); do echo "FAILED tests/test_many.py::test_$i - x"; done > "$L/many.log"
eq "BENIGN: > 20 failing ids (baseline/env break) is never a repeat signal" "" "$(ovn_repeat_key h1 "$L/many.log")"
eq "repeat breaker kill switch" "" "$(OVN_REPEAT_BREAKER=off ovn_repeat_key h1 "$L/drift.log")"

echo "== Y1 fold: a model-column item and its migration sibling stay ONE unit =="
fold_repo(){  # <name> [no-drift-test]
  local r="$TMP/$1"; mkdir -p "$r/backend/tests" "$r/backend/alembic/versions"
  [ "${2:-}" = nodrift ] || echo 'def test_alembic_head_matches_models(): pass' > "$r/backend/tests/test_migration_drift.py"
  echo "$r"
}
MODEL='- [ ] [T1] iptv-backend/app/models/subscription.py — Add `last_event_ms` column (BigInteger, nullable) to Subscription model. VERIFY: python -c "pass" (cat:schema; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook]'
MIG='- [ ] [T2] iptv-backend/alembic/versions/0011_subscription_last_event_ms.py — Create migration to add `last_event_ms` column to subscriptions table. VERIFY: alembic upgrade head (cat:schema; multifile:no) [feat:iptv_apps-20260930-revenuecat-webhook]'
FOLD="$Q/scripts/ovn_fold_migration_items.py"
r="$(fold_repo iptv_apps)"; printf '# P\n\n## Next Steps\n%s\n%s\n' "$MODEL" "$MIG" > "$r/P.md"
eq "iptv incident: migration sibling folded" "folded 1" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
ok "migration line retired in place with the folded tag" "$(grep -q '^- \[x\] (retired-folded-migration' "$r/P.md" && grep -q 'alembic/versions/0011' "$r/P.md" && echo 1 || echo 0)"
ok "the MODEL item is untouched and still open" "$(grep -qxF -- "$MODEL" "$r/P.md" && echo 1 || echo 0)"
eq "idempotent: second run folds nothing" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo iptv_apps2)"; printf '# P\n%s\n%s\n' "${MODEL/- \[ \]/- [x]}" "$MIG" > "$r/P.md"
eq "BENIGN: model sibling already landed -> the open migration item is genuine work, kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo iptv_apps3)"; printf '# P\n%s\n%s\n' "$MODEL" "${MIG//revenuecat-webhook/other-feature}" > "$r/P.md"
eq "BENIGN: different [feat:] tag is a different unit, kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo iptv_apps4)"; printf '# P\n%s\n%s\n' "${MODEL% \[feat:*}" "${MIG% \[feat:*}" > "$r/P.md"
eq "BENIGN: no feat tag -> cannot tell they belong together, kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo billwatch)"; printf '# P\n%s\n%s\n' "$MODEL" "$MIG" > "$r/P.md"
eq "BENIGN: repo off the autogen allowlist (no hook there) -> kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" billwatch)"
r="$(fold_repo iptv_apps5 nodrift)"; printf '# P\n%s\n%s\n' "$MODEL" "$MIG" > "$r/P.md"
eq "BENIGN: repo has no drift test -> the hook would not run, kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo iptv_apps6)"; printf '# P\n%s\n%s\n' "${MODEL/- \[ \]/- [ ] [AUTO-SKIP x]}" "$MIG" > "$r/P.md"
eq "BENIGN: a PARKED model sibling is not a pending unit, migration kept" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
r="$(fold_repo iptv_apps7)"; printf '# P\n%s\n%s\n' "${MODEL/20260930/20260915}" "$MIG" > "$r/P.md"
eq "regenerated feat tag (different date stamp) still folds" "folded 1" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
for w in "and backfills existing rows from updated_at (data migration, UPDATE statement)" "and drops the legacy last_seen column" "and alters the column type to BigInteger" "and renames last_event to last_event_ms"; do
  r="$(fold_repo iptv_apps8)"; printf '# P\n%s\n%s\n' "$MODEL" "${MIG/to subscriptions table/to subscriptions table $w}" > "$r/P.md"
  eq "NEGATIVE: migration item with data/drop/alter work is NOT folded ($w)" "folded 0" "$(python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"
  ok "data-work migration item stays open" "$(grep -q '^- \[ \] \[T2\].*alembic/versions/0011' "$r/P.md" && echo 1 || echo 0)"
done
eq "kill switch OVN_FOLD_MIGRATION=off" "folded 0" "$(printf '# P\n%s\n%s\n' "$MODEL" "$MIG" > "$r/P.md"; OVN_FOLD_MIGRATION=off python3 "$FOLD" "$r/P.md" "$r" iptv_apps)"

echo "== Y1 guard: repeat circuit-breaker (real ovn_item_guard.sh) =="
G="$Q/scripts/ovn_item_guard.sh"
new_repo(){ local r="$TMP/g_$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && printf '%s\n' "- [ ] [T2] app/foo.py — do the thing" "- [ ] [T2] app/bar.py — other thing" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i ); echo "$r"; }
mklog(){ printf '%s\n' "$@" > "$TMP/log.$$"; echo "$TMP/log.$$"; }
CAPS="OVN_ITEM_FAIL_CAP=9 OVN_ITEM_NOOP_CAP=9 OVN_ITEM_TOKEN_CAP=99999999"
parked(){ grep -q 'AUTO-SKIP needs-human' "$1/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0; }
r="$(new_repo m1)"; st="$TMP/st_m1"; mkdir -p "$st"
lg="$(mklog 'scout' '--- repeat-breaker: same failing tests on 2 consecutive attempts of the same item: tests/test_migration_drift.py::test_alembic_head_matches_models ---' 'FAILED tests/test_migration_drift.py::test_alembic_head_matches_models - x')"
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$lg" >/dev/null 2>&1
eq "marker from the best-of-N loop parks the item on the FIRST cycle (fail cap was 9)" 1 "$(parked "$r")"
ok "park note names needs-human and the repeated test id" "$(grep -q 'needs-human: the same failing tests repeated.*test_migration_drift.py::test_alembic_head_matches_models' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "the NEXT item is untouched" "$(grep -q '^- \[ \] \[T2\] app/bar.py' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "park committed" "$(git -C "$r" log --format=%s -1 | grep -q 'park item - same failing tests' && echo 1 || echo 0)"
r="$(new_repo m2)"; st="$TMP/st_m2"; mkdir -p "$st"
lg="$(mklog 'FAILED tests/test_a.py::test_x - assert 1 == 2')"
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$lg" >/dev/null 2>&1
eq "BENIGN: first failure with ids is not parked" 0 "$(parked "$r")"
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$lg" >/dev/null 2>&1
eq "cross-cycle: the SAME failing id set on the 2nd consecutive cycle parks it" 1 "$(parked "$r")"
r="$(new_repo m3)"; st="$TMP/st_m3"; mkdir -p "$st"
printf 'FAILED tests/test_a.py::test_x - assert 1 == 2\n' > "$TMP/lgA"; printf 'FAILED tests/test_b.py::test_y - assert 3 == 4\n' > "$TMP/lgB"
for f in lgA lgB lgA lgB; do env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/$f" >/dev/null 2>&1; done
eq "BENIGN: DIFFERENT failing sets on consecutive cycles never trip it" 0 "$(parked "$r")"
r="$(new_repo m4)"; st="$TMP/st_m4"; mkdir -p "$st"
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$L/heads.log" >/dev/null 2>&1
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1
eq "BENIGN: a no-ids cycle in between resets the streak" 0 "$(parked "$r")"
r="$(new_repo m5)"; st="$TMP/st_m5"; mkdir -p "$st"; cp "$L/many.log" "$TMP/many.log"
for i in 1 2; do env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/many.log" >/dev/null 2>&1; done
eq "BENIGN: 25 failing ids twice (baseline/env break) is not an item signal" 0 "$(parked "$r")"
r="$(new_repo m6)"; st="$TMP/st_m6"; mkdir -p "$st"
for i in 1 2 3; do env $CAPS OVN_REPEAT_BREAKER=off bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1; done
eq "kill switch OVN_REPEAT_BREAKER=off: identical sets never park (the old cap-9 behaviour)" 0 "$(parked "$r")"
r="$(new_repo m7)"; st="$TMP/st_m7"; mkdir -p "$st"
env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1
h="$(ovn_item_hash '- [ ] [T2] app/foo.py — do the thing')"
ok "streak state file written for the item" "$([ -s "$st/item_fails/id1.$h.lastids" ] && echo 1 || echo 0)"
printf 'item-hash %s\n' "$h" > "$TMP/landlog"
env $CAPS bash "$G" "$r" 'pushed tests:pass' "$st" id1 "$TMP/landlog" >/dev/null 2>&1
ok "a landing clears the item's repeat-streak state" "$([ ! -e "$st/item_fails/id1.$h.lastids" ] && echo 1 || echo 0)"
for i in 1; do env $CAPS bash "$G" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1; done
eq "after a landing the same ids start a fresh streak (not parked at once)" 0 "$(parked "$r")"

echo "== review notes Y-b / Y-c / Y-d / Y-e (2026-10-02): pure helpers =="
# ---- Y-b: the drift signature needs the ACTUAL failure, not a mention of the drift test file
printf 'Added tests/test_migration_drift.py to the chat\nFAILED tests/test_other.py::test_b - assert 1 == 2\n' > "$L/mention.log"
printf 'Please also keep test_migration_drift green.\nAider: Added tests/test_migration_drift.py to the chat.\n' > "$L/mention2.log"
printf 'tests/test_migration_drift.py::test_alembic_head_matches_models FAILED [100%%]\n' > "$L/drift_v.log"
printf 'ERROR tests/test_migration_drift.py::test_alembic_head_matches_models - sqlalchemy.exc.OperationalError\n' > "$L/drift_e.log"
printf 'x\nAssertionError: Migration drift detected: columns differ\n' > "$L/drift_txt.log"
eq "Y-b NEGATIVE: a log that merely MENTIONS the drift test file is no drift signature" "" "$(ovn_attempt_signature 'no-op(reverted-red)' "$L/mention.log")"
eq "Y-b NEGATIVE: prompt-echo / chat-add mentions only" "" "$(ovn_attempt_signature 'no-op' "$L/mention2.log")"
eq "Y-b NEGATIVE: ...so best-of-N keeps its full budget for it" 5 "$(ovn_bestn_after_failure 5 "$(ovn_attempt_signature 'no-op' "$L/mention.log")")"
eq "Y-b BENIGN: verbose-form FAILED line for the drift test" migration-drift "$(ovn_attempt_signature 'no-op' "$L/drift_v.log")"
eq "Y-b BENIGN: ERROR line for the drift test" migration-drift "$(ovn_attempt_signature 'no-op' "$L/drift_e.log")"
eq "Y-b BENIGN: the drift AssertionError text alone" migration-drift "$(ovn_attempt_signature 'no-op' "$L/drift_txt.log")"

# ---- Y-d: scout grounding - combined byte budget + code-context symbols only
GR="$Q/ovn_scout_ground.py"
mkg(){ # <name> -> repo with a realistic layout
  local g="$TMP/gr_$1"; mkdir -p "$g/app/routers" "$g/app/services" "$g/tests" "$g/a" "$g/b" "$g/iptv-backend/app/models"
  ( cd "$g" && gitq init -q
    printf 'def is_safe_url(u):\n    return True\n' > app/url_safety.py
    printf 'def get_current_user():\n    return 1\n' > app/routers/auth.py
    printf 'def test_auth(): pass\n' > tests/test_auth.py
    gitq add -A && gitq commit -q -m i ) >/dev/null
  echo "$g"
}
runground(){ # <repo> <item text> <files...> -> stdout rows
  local g="$1" item="$2"; shift 2
  printf 'VERDICT: PROCEED\nPLAN: do it\nFILES:\n%s\nTokens: 100 sent, 50 received\n' "$(printf '%s\n' "$@")" > "$TMP/sl2.log"; printf '%s\n' "$item" > "$TMP/item2.txt"
  python3 "$GR" "$g" "$TMP/sl2.log" "$TMP/item2.txt" 120000
}
bigfile(){ python3 -c "import sys; open(sys.argv[1],'w').write(sys.argv[2].replace('\\\\n','\n') + '#'*int(sys.argv[3]))" "$1" "$2" "$3"; }
g="$(mkg budget)"; mkdir -p "$g/app/big"
bigfile "$g/app/big/planned_big.py" 'def planned_thing():\n    return 1\n' 100000
for i in 1 2 3; do bigfile "$g/app/big/extra_$i.py" "def helper_func_$i():\n    return 1\n" 45000; done
( cd "$g" && gitq add -A && gitq commit -q -m big ) >/dev/null
ITEM_B='- [ ] [T2] wire helper_func_1 helper_func_2 helper_func_3 (cat:python)'
out="$(runground "$g" "$ITEM_B" app/big/planned_big.py)"
eq "Y-d NEGATIVE: planned 100KB + 3x45KB extras: only what fits under 160KB total is added (1 extra; old: 2)" 1 "$(grep -c '^ADD' <<<"$out")"
out="$(OVN_SCOUT_TOTAL_BYTES=400000 runground "$g" "$ITEM_B" app/big/planned_big.py)"
eq "Y-d BENIGN: a bigger OVN_SCOUT_TOTAL_BYTES admits them (extras cap 120KB -> 2)" 2 "$(grep -c '^ADD' <<<"$out")"
out="$(OVN_SCOUT_TOTAL_BYTES=100000 runground "$g" "$ITEM_B" app/big/planned_big.py)"
eq "Y-d NEGATIVE: planned file alone at the budget -> NO extras, planned file still KEPT" "0 1" "$(grep -c '^ADD' <<<"$out") $(grep -c '^KEEP' <<<"$out")"
out="$(runground "$g" "$ITEM_B" app/url_safety.py)"
eq "Y-d BENIGN: a small planned file leaves room for the extras (up to the 120KB extras cap: 2 of 45KB)" 2 "$(grep -c '^ADD' <<<"$out")"
g="$(mkg prio)"; mkdir -p "$g/app/p"
bigfile "$g/app/p/widget.py" 'def build_widget_now():\n    return 1\n' 30000
bigfile "$g/tests/test_widget.py" 'def test_widget(): pass\n' 30000
bigfile "$g/app/planned.py" 'x = 1\n' 100000
( cd "$g" && gitq add -A && gitq commit -q -m p ) >/dev/null
out="$(runground "$g" '- [ ] [T2] fix `build_widget_now` (cat:python)' app/planned.py)"
eq "Y-d NEGATIVE: 100KB planned + 30KB def + 30KB test, 160KB total: the TEST is dropped first, the definition stays" "app/p/widget.py" "$(grep '^ADD' <<<"$out" | cut -f2)"
g="$(mkg sym)"; mkdir -p "$g/app/core"
printf 'def rate_limit(x):\n    return x\n' > "$g/app/core/limiter.py"
printf 'def get_user_name(x):\n    return x\n' > "$g/app/core/names_a.py"
printf 'def get_user_name(x):\n    return 2\n' > "$g/app/core/names_b.py"
printf 'def build_sales_report(x):\n    return x\n' > "$g/app/core/reports.py"
( cd "$g" && gitq add -A && gitq commit -q -m s ) >/dev/null
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — tidy the rate_limit wording in the docs (cat:python)' app/url_safety.py)"
eq "Y-d NEGATIVE: a two-part prose word (rate_limit) in plain text pulls nothing in (old: added limiter.py)" $'KEEP\tapp/url_safety.py' "$out"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — respect the `rate_limit` helper (cat:python)' app/url_safety.py)"
ok "Y-d BENIGN: the same name in BACKTICKS resolves to its definition" "$(grep -q $'^ADD\tapp/core/limiter.py' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — call rate_limit() before returning (cat:python)' app/url_safety.py)"
ok "Y-d BENIGN: the same name as a CALL rate_limit() resolves" "$(grep -q $'^ADD\tapp/core/limiter.py' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — also look at get_user_name please (cat:python)' app/url_safety.py)"
eq "Y-d NEGATIVE: a bare 3-part name defined in TWO files is ambiguous - nothing guessed (old: both added)" $'KEEP\tapp/url_safety.py' "$out"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — reuse build_sales_report for the summary (cat:python)' app/url_safety.py)"
ok "Y-d BENIGN: a bare 3-part name defined in exactly one file still resolves" "$(grep -q $'^ADD\tapp/core/reports.py' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — def get_user_name needs a docstring (cat:python)' app/url_safety.py)"
ok "Y-d BENIGN: a name after the word def is code context even when defined in 2 files" "$(grep -c $'^ADD' <<<"$out" | grep -qx 2 && echo 1 || echo 0)"

# ---- Y-e: the repeat breaker discounts baseline-red / shared-red ids
ST_E="$TMP/st_e"; mkdir -p "$ST_E/qa_baselines/verify" "$ST_E/item_fails"
RP="$TMP/repos_e/iptv_apps"; mkdir -p "$RP"
printf 'FAILED tests/test_a.py::test_x - assert 1 == 2\n' > "$L/ya.log"
printf 'FAILED tests/test_a.py::test_x - assert 1 == 2\nFAILED tests/test_n.py::test_new - assert 3 == 4\n' > "$L/ya_new.log"
printf 'FAILED backend/tests/test_a.py::test_x - assert 1 == 2\n' > "$L/ya_prefix.log"
mkbl(){ printf '{"version":1,"repo":"iptv_apps","ts":%s,"failing":%s,"count":1,"ttl_s":86400}\n' "$1" "$2" > "$ST_E/qa_baselines/verify/iptv_apps.json"; }
mkbl "$(date +%s)" '["tests/test_a.py::test_x"]'
eq "Y-e NEGATIVE: the only failing id is red at the repo baseline -> no repeat key (old: a key)" "" "$(ovn_repeat_key h1 "$L/ya.log" "$RP" "$ST_E")"
ok "Y-e: the legacy call shape (no repo/state) still keys it (unfiltered, as before)" "$([ -n "$(ovn_repeat_key h1 "$L/ya.log")" ] && echo 1 || echo 0)"
eq "Y-e NEGATIVE: package-prefixed id (backend/tests/..) matches the baseline id" "" "$(ovn_repeat_key h1 "$L/ya_prefix.log" "$RP" "$ST_E")"
k_new="$(ovn_repeat_key h1 "$L/ya_new.log" "$RP" "$ST_E")"; k_new2="$(ovn_repeat_key h1 "$L/ya_new.log" "$RP" "$ST_E")"
ok "Y-e BENIGN: baseline-red id + a NEW failing id -> keyed, on the NEW id only (stable)" "$([ -n "$k_new" ] && [ "$k_new" = "$k_new2" ] && [ "$k_new" != "$(ovn_repeat_key h1 "$L/ya.log")" ] && echo 1 || echo 0)"
eq "Y-e basis: reported as baseline" baseline "$(ovn_repeat_basis "$RP" "$ST_E")"
mkbl "$(( $(date +%s) - 200000 ))" '["tests/test_a.py::test_x"]'
ok "Y-e BENIGN: an EXPIRED baseline is not trusted (fallback; no previous item -> keyed)" "$([ -n "$(ovn_repeat_key h1 "$L/ya.log" "$RP" "$ST_E")" ] && echo 1 || echo 0)"
eq "Y-e basis: expired baseline -> previous-item rule" previous-item "$(ovn_repeat_basis "$RP" "$ST_E")"
rm -f "$ST_E/qa_baselines/verify/iptv_apps.json"
ok "Y-e BENIGN: no baseline and no previous item recorded -> keyed (same ids still trip it)" "$([ -n "$(ovn_repeat_key h1 "$L/ya.log" "$RP" "$ST_E")" ] && echo 1 || echo 0)"
ovn_repeat_record "$RP" "$ST_E" hprev "$L/ya.log"        # the previous ITEM failed on the same id
eq "Y-e NEGATIVE: no baseline; the previous item failed on the same ids -> shared/flaky red, no key" "" "$(ovn_repeat_key hcur "$L/ya.log" "$RP" "$ST_E")"
ok "Y-e BENIGN: no baseline; at least one id is new relative to the previous item -> keyed" "$([ -n "$(ovn_repeat_key hcur "$L/ya_new.log" "$RP" "$ST_E")" ] && echo 1 || echo 0)"
ovn_repeat_record "$RP" "$ST_E" hcur "$L/ya.log"         # hcur's own attempt is recorded; hprev moves to the 'other' slot
eq "Y-e NEGATIVE: a 2nd attempt of the SAME item still compares against the last DIFFERENT item" "" "$(ovn_repeat_key hcur "$L/ya.log" "$RP" "$ST_E")"

echo "== review note Y-e: the REAL guard does not park on a baseline-red / shared-red id =="
G2="$Q/scripts/ovn_item_guard.sh"
mkbl2(){ printf '{"version":1,"repo":"%s","ts":%s,"failing":["tests/test_a.py::test_x"],"count":1,"ttl_s":86400}\n' "$(basename "$1")" "$(date +%s)" > "$2/qa_baselines/verify/$(basename "$1").json"; }
r="$(new_repo ye1)"; st="$TMP/st_ye1"; mkdir -p "$st/qa_baselines/verify"
mkbl2 "$r" "$st"
printf 'FAILED tests/test_a.py::test_x - assert 1 == 2\n' > "$TMP/lgA"
for i in 1 2 3; do env $CAPS bash "$G2" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1; done
eq "Y-e NEGATIVE: the ONLY failing id is red at the baseline, 3 identical cycles -> NOT parked (old: parked at cycle 2)" 0 "$(parked "$r")"
printf 'FAILED tests/test_a.py::test_x - e\nFAILED tests/test_n.py::test_new - e2\n' > "$TMP/lgN"
r="$(new_repo ye2)"; st="$TMP/st_ye2"; mkdir -p "$st/qa_baselines/verify"; mkbl2 "$r" "$st"
for i in 1 2; do env $CAPS bash "$G2" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgN" >/dev/null 2>&1; done
eq "Y-e BENIGN: baseline-red id PLUS a new id repeating -> parked" 1 "$(parked "$r")"
ok "Y-e: the park note says it is a repeat of the same failing ids, names only the NEW id, and why it counts" "$(grep -q 'needs-human: the same failing tests repeated on 2 consecutive attempts (tests/test_n.py::test_new) - a repeat of the same failing ids (not red at the repo baseline)' "$r/OVERNIGHT_PROGRESS.md" && ! grep -q 'test_a.py::test_x' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
r="$(new_repo ye3)"; st="$TMP/st_ye3"; mkdir -p "$st"
printf '%s\n' "- [ ] [T2] app/first.py — first item" "- [ ] [T2] app/second.py — second item" > "$r/OVERNIGHT_PROGRESS.md"; ( cd "$r" && git add -A && git commit -q -m two )
env $CAPS bash "$G2" "$r" 'reverted(reverted-red)' "$st" id1 "$TMP/lgA" >/dev/null 2>&1      # item 1 fails on test_x
sed -i.bak 's/^- \[ \] \[T2\] app\/first.py/- [x] [T2] app\/first.py/' "$r/OVERNIGHT_PROGRESS.md"; rm -f "$r/OVERNIGHT_PROGRESS.md.bak"; ( cd "$r" && git add -A && git commit -q -m done1 )
for i in 1 2 3; do env $CAPS bash "$G2" "$r" 'reverted(reverted-red)' "$st" id2 "$TMP/lgA" >/dev/null 2>&1; done   # item 2 fails on the SAME id x3
eq "Y-e NEGATIVE (no baseline): item 2 fails only on the id the PREVIOUS item also failed on -> shared red, NOT parked" 0 "$(parked "$r")"
for i in 1 2; do env $CAPS bash "$G2" "$r" 'reverted(reverted-red)' "$st" id2 "$TMP/lgN" >/dev/null 2>&1; done
eq "Y-e BENIGN (no baseline): ...but once a NEW id repeats on 2 attempts it parks" 1 "$(parked "$r")"
ok "Y-e: no-baseline park note says the ids are not a repeat of the previous item's failures" "$(grep -q "not a repeat of the previous item's failures" "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"

echo "== Y1 best-of-N through the real main loop (stub aider) =="
ro_init
trap 'rm -rf "$TMP" "$T"' EXIT
ro_hook_stubs
ro_link scripts/ovn_fold_migration_items.py scripts/ovn_repeat_ids.py
ST="$T/tree/state"; R="$T/repos"; mkdir -p "$ST"
oc(){ jq -r --arg id "$1" --arg f "$2" 'select(.id==$id) | .[$f]' "$ST/outcomes.jsonl" | tail -1; }
SCHEMA_PROG='# Overnight Progress

## Next Steps
- [ ] [T1] `backend/app/models/user.py` — add a nullable column to the User model (cat:python)'
PLAIN_PROG='# Overnight Progress

## Next Steps
- [ ] [T1] `app/foo.py` — add a bar function (cat:python)'
# y_run <name> <progress> <bestn> <scn body file> [ENV...]
y_run(){
  local name="$1" prog="$2" n="$3" scn="$4"; shift 4
  ro_mkrepo "r-$name" "$prog" >/dev/null
  echo "OVN_BESTOF_N=$n" > "$ST/pilot_flags.env"
  cp "$scn" "$RO_STUB/scn"
  : > "$RO_STUB/aider_n"; rm -f "$RO_STUB/impl_n" "$RO_STUB/aider_kinds" "$ST/outcomes.jsonl" "$T/tree/reports"/* 2>/dev/null; rm -rf "$T/tree/logs"/* 2>/dev/null
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("t-"+$n),repo:($R+"/r-"+$n),prompt:"x"}]')"
  ro_run_main "$@"
}
mkscn(){ cat > "$1"; }
mkscn "$TMP/scn_heads" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA='a multi-file change
MULTIPLE HEADS [0010_content_group, 0012]'
EOF
mkscn "$TMP/scn_plain" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA='a multi-file change'
EOF
mkscn "$TMP/scn_sameids" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA='a multi-file change
FAILED tests/test_foo.py::test_bar - AssertionError'
EOF
mkscn "$TMP/scn_diffids" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA="a multi-file change
FAILED tests/test_foo.py::test_bar_$n - AssertionError"
EOF
mkscn "$TMP/scn_drift_sameids" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA='a multi-file change
FAILED tests/test_migration_drift.py::test_alembic_head_matches_models - AssertionError: Migration drift detected'
EOF
y_run drift "$SCHEMA_PROG" 3 "$TMP/scn_heads"
eq "schema item + migration-chain failure: budget 5 capped to 2 attempts" 2 "$(oc t-drift attempts)"
eq "outcome row carries attempts == attempt" "$(oc t-drift attempt)" "$(oc t-drift attempts)"
eq "outcome row records WHY the loop stopped" drift-cap "$(oc t-drift bestn_stop)"
has "log names the cap" "$RO_OUT" "stopped after attempt 2/2: migration-chain failure is deterministic"
y_run drift2 "$SCHEMA_PROG" 3 "$TMP/scn_plain"
eq "BENIGN: schema item, UNRELATED failure keeps the normal schema budget (5)" 5 "$(oc t-drift2 attempts)"
eq "BENIGN: no stop reason when the budget ran out normally" "" "$(oc t-drift2 bestn_stop)"
y_run drift3 "$SCHEMA_PROG" 3 "$TMP/scn_heads" OVN_BESTOF_N_DRIFT_CAP=0
eq "kill switch OVN_BESTOF_N_DRIFT_CAP=0: back to the schema budget (5)" 5 "$(oc t-drift3 attempts)"
y_run rep "$PLAIN_PROG" 4 "$TMP/scn_sameids"
eq "REPEAT BREAKER: the same failing test set on 2 consecutive attempts stops best-of-4 at 2" 2 "$(oc t-rep attempts)"
eq "REPEAT BREAKER: stop reason recorded" repeat-breaker "$(oc t-rep bestn_stop)"
has "REPEAT BREAKER: log line" "$RO_OUT" "the same failing test set repeated 2x"
ok "REPEAT BREAKER: marker left in the task log for the guard" "$(grep -rqE 'repeat-breaker: same failing tests on 2 consecutive attempts.*test_foo.py::test_bar' "$T"/tree/logs/ && echo 1 || echo 0)"
y_run rep2 "$PLAIN_PROG" 4 "$TMP/scn_diffids"
eq "BENIGN: DIFFERENT failing sets each attempt -> all 4 attempts run" 4 "$(oc t-rep2 attempts)"
y_run rep3 "$PLAIN_PROG" 4 "$TMP/scn_sameids" OVN_REPEAT_BREAKER=off
eq "kill switch OVN_REPEAT_BREAKER=off: all 4 attempts run" 4 "$(oc t-rep3 attempts)"
y_run rep4 "$PLAIN_PROG" 4 "$TMP/scn_sameids" OVN_REPEAT_BREAKER_N=3
eq "OVN_REPEAT_BREAKER_N=3 needs 3 identical attempts" 3 "$(oc t-rep4 attempts)"
mkdir -p "$ST/qa_baselines/verify"
printf '{"version":1,"repo":"r-rep6","ts":%s,"failing":["tests/test_foo.py::test_bar"],"count":1,"ttl_s":86400}\n' "$(date +%s)" > "$ST/qa_baselines/verify/r-rep6.json"
y_run rep6 "$PLAIN_PROG" 4 "$TMP/scn_sameids"
eq "Y-e NEGATIVE (main loop): the identical failing id is RED AT THE BASELINE -> not a repeat, all 4 attempts run (old: stops at 2)" 4 "$(oc t-rep6 attempts)"
eq "Y-e: no repeat-breaker stop recorded" "" "$(oc t-rep6 bestn_stop)"
rm -f "$ST/qa_baselines/verify/r-rep6.json"
mkscn "$TMP/scn_mention" <<'EOF'
IMPL_SEQ=none
SCOUT_EXTRA='a multi-file change
Added tests/test_migration_drift.py to the chat'
EOF
y_run mention "$SCHEMA_PROG" 3 "$TMP/scn_mention"
eq "Y-b NEGATIVE (main loop): a log that only MENTIONS the drift test does not cap best-of-N (schema budget 5 runs)" 5 "$(oc t-mention attempts)"
y_run rep5 "$SCHEMA_PROG" 3 "$TMP/scn_drift_sameids"
eq "drift test failing identically: capped at 2 (both rules agree on the stop)" 2 "$(oc t-rep5 attempts)"
y_run single "$PLAIN_PROG" 1 "$TMP/scn_plain"
eq "BENIGN: best-of-N off -> 1 attempt, attempts field is 1" 1 "$(oc t-single attempts)"

echo "== Y1 e2e: fold runs in the per-cycle sanitizer =="
FOLD_PROG="# Overnight Progress

## Next Steps
$MODEL
$MIG"
ro_mkrepo iptv_apps "$FOLD_PROG" >/dev/null
( cd "$R/iptv_apps" && mkdir -p backend/tests backend/alembic/versions iptv-backend/app/models && echo x > backend/tests/test_migration_drift.py && echo 'class Subscription: pass' > iptv-backend/app/models/subscription.py && gitq add -A && gitq commit -q -m drift && gitq push -q origin main 2>/dev/null )
echo 'OVN_BESTOF_N=1' > "$ST/pilot_flags.env"; cp "$TMP/scn_plain" "$RO_STUB/scn"; : > "$RO_STUB/aider_n"; rm -f "$ST/outcomes.jsonl"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-fold",repo:($R+"/iptv_apps"),prompt:"x"}]')"
ro_run_main
ok "sanitizer folded the migration item before the scout ran" "$(git -C "$R/iptv_apps" log --all --format=%s | grep -q 'fold migration item' && echo 1 || echo 0)"

echo "== Y2 scout grounding: pure (ovn_scout_ground.py) =="
GR="$Q/ovn_scout_ground.py"
mkg(){ # <name> -> repo with a realistic layout
  local g="$TMP/gr_$1"; mkdir -p "$g/app/routers" "$g/app/services" "$g/tests" "$g/a" "$g/b" "$g/iptv-backend/app/models"
  ( cd "$g" && gitq init -q
    printf 'def is_safe_url(u):\n    return True\n' > app/url_safety.py
    printf 'def get_current_user():\n    return 1\n' > app/routers/auth.py
    printf 'def refresh():\n    return 1\n' > app/routers/finance.py
    printf 'def test_auth(): pass\n' > tests/test_auth.py
    printf 'x = 1\n' > a/utils.py; printf 'y = 2\n' > b/utils.py
    printf 'class ActiveStreamSession:\n    pass\n' > iptv-backend/app/models/stream_session.py
    gitq add -A && gitq commit -q -m i ) >/dev/null
  echo "$g"
}
scout_log(){ printf 'VERDICT: PROCEED\nPLAN: do it\nFILES:\n%s\nTokens: 100 sent, 50 received\n' "$(printf '%s\n' "$@")"; }
runground(){ # <repo> <item text> <files...> -> stdout rows
  local g="$1" item="$2"; shift 2
  scout_log "$@" > "$TMP/sl.log"; printf '%s\n' "$item" > "$TMP/item.txt"
  python3 "$GR" "$g" "$TMP/sl.log" "$TMP/item.txt" 120000
}
g="$(mkg a)"
out="$(runground "$g" '- [ ] [T2] harden the SSRF check (cat:python)' app/services/ssrf.py)"
ok "fictional path (ssrf.py) is DROPPED with a reason" "$(grep -q $'^DROP\tapp/services/ssrf.py\tno such file' <<<"$out" && echo 1 || echo 0)"
ok "...and nothing workable left -> UNGROUNDED" "$(grep -q '^UNGROUNDED' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] harden the SSRF check (cat:python)' app/core/url_safety.py)"
ok "unique basename match is SUBSTITUTED (real url_safety.py)" "$(grep -q $'^SUBST\tapp/core/url_safety.py\tapp/url_safety.py' <<<"$out" && echo 1 || echo 0)"
ok "...and is not UNGROUNDED" "$(grep -q '^UNGROUNDED' <<<"$out" && echo 0 || echo 1)"
out="$(runground "$g" '- [ ] [T2] move ActiveStreamSession handling (cat:python)' app/models/stream_session.py)"
ok "path-suffix match (dropped leading dir) is substituted" "$(grep -q $'^SUBST\tapp/models/stream_session.py\tiptv-backend/app/models/stream_session.py' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] tidy utils (cat:python)' lib/utils.py app/url_safety.py)"
ok "AMBIGUOUS basename (a/utils.py, b/utils.py) is dropped, not guessed" "$(grep -q $'^DROP\tlib/utils.py\tambiguous' <<<"$out" && echo 1 || echo 0)"
ok "...the other planned file survives so the item is NOT ungrounded" "$(grep -q $'^KEEP\tapp/url_safety.py' <<<"$out" && ! grep -q UNGROUNDED <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] tidy url_safety (cat:python)' app/url_safety.py)"
eq "BENIGN: an existing planned file is just KEEP" $'KEEP\tapp/url_safety.py' "$out"
out="$(runground "$g" '- [ ] [T2] add a test for url safety (cat:test)' tests/test_url_safety.py)"
eq "BENIGN: a new test file in an existing tests/ dir is kept as NEW (not a fiction)" $'NEW\ttests/test_url_safety.py' "$out"
out="$(runground "$g" '- [ ] [T2] app/services/newthing.py — create a helper (cat:python)' app/services/newthing.py)"
eq "BENIGN: a file the ITEM TEXT names is an author-sanctioned new file" $'NEW\tapp/services/newthing.py' "$out"
out="$(runground "$g" '- [ ] [T2] create a new service that does the thing (cat:python)' app/services/thing.py)"
eq "BENIGN: item asks for a NEW file and its dir exists -> NEW" $'NEW\tapp/services/thing.py' "$out"
scout_log NONE > "$TMP/sl.log"; printf 'x\n' > "$TMP/item.txt"
eq "BENIGN: FILES: NONE -> no decisions at all (the old ungrounded-plan guard owns that case)" "" "$(python3 "$GR" "$g" "$TMP/sl.log" "$TMP/item.txt")"

echo "== Y2 symbol resolution =="
g="$(mkg b)"
out="$(runground "$g" '- [ ] [T2] app/routers/finance.py — require get_current_user on the refresh endpoint (cat:python)' app/routers/finance.py)"
ok "billwatch auth shape: get_current_user's defining file is ADDED" "$(grep -q $'^ADD\tapp/routers/auth.py\tdefines `get_current_user`' <<<"$out" && echo 1 || echo 0)"
ok "...with the nearest existing test file (tests/test_auth.py)" "$(grep -q $'^ADD\ttests/test_auth.py\tnearest existing test file of app/routers/auth.py' <<<"$out" && echo 1 || echo 0)"
ok "...and the scout's own file is KEPT" "$(grep -q $'^KEEP\tapp/routers/finance.py' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] app/routers/finance.py — require get_current_user on the refresh endpoint (cat:python)' app/routers/finance.py app/routers/auth.py)"
ok "BENIGN: the scout already planned the definition -> no ADD for it" "$(grep -q '^ADD.app/routers/auth.py' <<<"$out" && echo 0 || echo 1)"
out="$(runground "$g" '- [ ] [T2] fix the ActiveStreamSession import (cat:python)' app/url_safety.py)"
ok "CamelCase class named in the item resolves to its module" "$(grep -q $'^ADD\tiptv-backend/app/models/stream_session.py\tdefines `ActiveStreamSession`' <<<"$out" && echo 1 || echo 0)"
out="$(runground "$g" '- [ ] [T2] tidy things up in app/url_safety.py without touching anything_else (cat:python)' app/url_safety.py)"
eq "BENIGN: a name the repo does not define adds nothing" $'KEEP\tapp/url_safety.py' "$out"
out="$(runground "$g" '- [ ] [T2] app/url_safety.py — url_safety.py handles is_safe_url (cat:python)' app/url_safety.py)"
eq "BENIGN: a symbol whose definition IS the planned file adds nothing" $'KEEP\tapp/url_safety.py' "$out"
scout_log NONE > "$TMP/sl.log"; printf '%s\n' '- [ ] [T2] require get_current_user on refresh (cat:python)' > "$TMP/item.txt"
eq "BENIGN: FILES: NONE + an item naming a real symbol -> nothing added (the ungrounded-plan guard owns a plan with no files)" "" "$(python3 "$GR" "$g" "$TMP/sl.log" "$TMP/item.txt")"
out="$(runground "$g" '- [ ] [T2] require get_current_user on refresh (cat:python)' app/services/ghost_service.py)"
ok "BENIGN: an all-fictional plan is not rescued by symbol resolution (it no-ops as scout-ungrounded)" "$(grep -q '^ADD' <<<"$out" && echo 0 || (grep -q '^UNGROUNDED' <<<"$out" && echo 1 || echo 0))"
g2="$(mkg c)"; for i in 1 2 3 4 5 6 7 8; do printf 'def helper_func_%s():\n    return 1\n' "$i" > "$g2/app/helper_mod_$i.py"; done; ( cd "$g2" && gitq add -A && gitq commit -q -m h ) >/dev/null
out="$(runground "$g2" '- [ ] [T2] wire helper_func_1 helper_func_2 helper_func_3 helper_func_4 helper_func_5 helper_func_6 helper_func_7 helper_func_8 (cat:python)' app/url_safety.py)"
eq "bounded: at most 6 extra files" 6 "$(grep -c '^ADD' <<<"$out")"
out="$(OVN_SCOUT_MAX_EXTRA=2 runground "$g2" '- [ ] [T2] wire helper_func_1 helper_func_2 helper_func_3 (cat:python)' app/url_safety.py)"
eq "bound is tunable (OVN_SCOUT_MAX_EXTRA=2)" 2 "$(grep -c '^ADD' <<<"$out")"
python3 -c "open('$g2/app/helper_mod_1.py','w').write('def helper_func_1():\n    return 1\n' + '#'*130000)"
out="$(runground "$g2" '- [ ] [T2] wire helper_func_1 (cat:python)' app/url_safety.py)"
ok "an oversize (>120KB) defining file is NOT added" "$(grep -q '^ADD' <<<"$out" && echo 0 || echo 1)"
g3="$(mkg d)"; mkdir -p "$g3/app/core"; printf 'def secret_helper():\n    return 1\n' > "$g3/app/core/banned_mod.py"; printf 'app/core/banned_mod.py\n' > "$g3/.queue-hard-banned-files"; ( cd "$g3" && gitq add -A && gitq commit -q -m b ) >/dev/null
out="$(runground "$g3" '- [ ] [T2] call secret_helper from app/url_safety.py (cat:python)' app/url_safety.py)"
ok "a hard-banned defining file is NEVER added" "$(grep -q '^ADD' <<<"$out" && echo 0 || echo 1)"
g4="$(mkg e)"; printf 'def get_current_user():\n    return 2\n' > "$g4/app/routers/other_auth.py"; printf 'def get_current_user():\n    return 3\n' > "$g4/app/routers/third_auth.py"; printf 'def get_current_user():\n    return 4\n' > "$g4/app/routers/fourth_auth.py"; ( cd "$g4" && gitq add -A && gitq commit -q -m d ) >/dev/null
out="$(runground "$g4" '- [ ] [T2] require get_current_user on refresh (cat:python)' app/routers/finance.py)"
ok "BENIGN: a name defined in 4 files is generic - nothing guessed" "$(grep -q '^ADD' <<<"$out" && echo 0 || echo 1)"

echo "== Y2 e2e: the real run_aider_fix_task =="
DRV="$HERE/lib_ro_harness_y_driver.sh"
yd="$TMP/yd"; mkdir -p "$yd"
cat > "$yd/setup.sh" <<'EOF'
mkdir -p app/routers app/services tests
printf 'def is_safe_url(u):\n    return True\n' > app/url_safety.py
printf 'def get_current_user():\n    return 1\n' > app/routers/auth.py
printf 'def refresh():\n    return 1\n' > app/routers/finance.py
printf 'def test_auth(): pass\n' > tests/test_auth.py
printf 'x = 1\n' > a_utils.py
EOF
yprog(){ printf '# Overnight Progress\n\n## Next Steps\n%s\n- [ ] [T1] app/other.py — other (cat:python)\n' "$1" > "$yd/prog.md"; }
yscout(){ printf 'VERDICT: PROCEED\nPLAN: %s\nFILES:\n%s\nTokens: 100 sent, 50 received\n' "$1" "$2" > "$yd/scout.txt"; }
yrun(){ local n="$1"; shift; env Y_SETUP="$yd/setup.sh" Y_PROGRESS="$yd/prog.md" Y_SCOUT="$yd/scout.txt" "$@" timeout 150 bash "$DRV" "$TMP/$n" > "$TMP/$n.out" 2>&1; }
yres(){ cat "$TMP/$1/result" 2>/dev/null; }
ylog(){ cat "$TMP/$1/task.log" 2>/dev/null; }
yimpl(){ cat "$TMP/$1"/scn/calls/*.impl 2>/dev/null; }
yprog '- [ ] [T2] app/url_safety.py — harden the SSRF check (cat:python)'
yscout 'harden the ssrf check in app/services/ssrf.py' 'app/services/ssrf.py'
yrun e2e_fiction
eq "fictional-only plan -> no-op(scout-ungrounded), implement NEVER called" "no-op(scout-ungrounded)" "$(yres e2e_fiction)"
ok "aider implement not invoked" "$([ -z "$(yimpl e2e_fiction)" ] && echo 1 || echo 0)"
has "drop logged with its reason" "$(ylog e2e_fiction)" "scout-grounding: dropped planned file app/services/ssrf.py (no such file in the repo (fictional path))"
yrun e2e_fiction_off OVN_SCOUT_GROUND=off
ok "kill switch OVN_SCOUT_GROUND=off: the old behaviour (implement is called)" "$([ -n "$(yimpl e2e_fiction_off)" ] && echo 1 || echo 0)"
yscout 'harden the ssrf check in app/core/url_safety.py' 'app/core/url_safety.py'
yrun e2e_subst
ok "unique basename: the REAL file is force-loaded for implement" "$(yimpl e2e_subst | grep -qx 'app/url_safety.py' && echo 1 || echo 0)"
has "substitution logged" "$(ylog e2e_subst)" "substituted the one real match app/url_safety.py"
ok "the plan text handed to implement names the real file" "$(yimpl e2e_subst | grep -q 'app/url_safety.py' && ! yimpl e2e_subst | grep -q 'app/core/url_safety.py' && echo 1 || echo 0)"
yscout 'harden both' 'lib/ghost_utils.py
app/url_safety.py'
yrun e2e_mixed
ok "a fiction + a real file: the real one proceeds to implement, the fiction is dropped" "$(yimpl e2e_mixed | grep -qx 'app/url_safety.py' && grep -q 'dropped planned file lib/ghost_utils.py' "$TMP/e2e_mixed/task.log" && echo 1 || echo 0)"
yprog '- [ ] [T2] app/routers/finance.py — require get_current_user on the finance refresh endpoint (cat:python)'
yscout 'add the auth dependency to refresh' 'app/routers/finance.py'
yrun e2e_symbol
ok "symbol resolution: auth.py (defines get_current_user) is loaded although the scout omitted it" "$(yimpl e2e_symbol | grep -qx 'app/routers/auth.py' && echo 1 || echo 0)"
ok "...plus its nearest test file" "$(yimpl e2e_symbol | grep -qx 'tests/test_auth.py' && echo 1 || echo 0)"
ok "...and the scout's own file stays loaded" "$(yimpl e2e_symbol | grep -qx 'app/routers/finance.py' && echo 1 || echo 0)"
yrun e2e_symbol_off OVN_SCOUT_GROUND=off
ok "kill switch: no symbol resolution, auth.py not loaded" "$(yimpl e2e_symbol_off | grep -qx 'app/routers/auth.py' && echo 0 || echo 1)"
yprog '- [ ] [T2] app/url_safety.py — tidy the url helper (cat:python)'
yscout 'tidy' 'app/url_safety.py'
yrun e2e_benign
ok "BENIGN: a clean plan runs exactly as before (file loaded, no grounding lines)" "$(yimpl e2e_benign | grep -qx 'app/url_safety.py' && ! ylog e2e_benign | grep -q 'scout-grounding' && echo 1 || echo 0)"
eq "BENIGN: the status is not a grounding no-op" "0" "$(yres e2e_benign | grep -c scout-ungrounded)"

echo "== Y2 fail-reason tag =="
printf 'x\n' > "$TMP/cf.log"
eq "ovn_classify_fail names no-op(scout-ungrounded) precisely" scout-ungrounded "$(bash "$Q/ovn_classify_fail.sh" "$TMP/cf.log" 'no-op(scout-ungrounded)')"
eq "BENIGN: a plain no-op is not mislabelled scout-ungrounded" unknown "$(bash "$Q/ovn_classify_fail.sh" "$TMP/cf.log" 'no-op')"
eq "outcome helper: row_attempts reads the new attempts field, falls back to attempt, then 1" "5 3 1" "$(python3 -c "
import sys; sys.path.insert(0, '$Q/scripts'); import ovn_outcome_buckets as o
print(o.row_attempts({'attempts': 5, 'attempt': 1}), o.row_attempts({'attempt': '3'}), o.row_attempts({}))")"
eq "outcome helper: total_attempts counts inner best-of-N attempts, not rows" 7 "$(python3 -c "
import sys; sys.path.insert(0, '$Q/scripts'); import ovn_outcome_buckets as o
print(o.total_attempts([{'attempts': 5}, {'attempt': 1}, {}]))")"

echo "== Y3 classifier =="
cat > "$L/lint.log" <<'EOF'
Tokens: 18k sent, 132 received.
Applied edit to iptv-backend/app/services/account.py

# Fix any errors below, if possible.

Traceback (most recent call last):
  File
"/home/x/overnight-queue/repos/iptv_apps/iptv-backend/app/services/
account.py", line 332
    db.query(EPGSource).filter(EPGSource.user_id ==
user_id).delete(synchronize_session=False)
IndentationError: unexpected indent

## Running: /home/x/aider-venv/bin/python3.12 -m flake8
--select=E9,F821 --show-source --isolated iptv-backend/app/services/account.py

iptv-backend/app/services/account.py:332:5: E999 IndentationError: unexpected
indent
    except APIError:
    ^

## See relevant line below marked with █.

iptv-backend/app/services/account.py:
...⋮...
 332█    db.query(EPGSource).filter(EPGSource.user_id ==
user_id).delete(synchronize_session=False)
Tokens: 18k sent, 90 received.
EOF
t "NEGATIVE: aider's own lint traceback (the iptv 17Z row) is NOT an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error '$L/lint.log'"
t "...even though the lint block quotes the word APIError in a source line" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error '$L/lint.log'"
{ cat "$L/lint.log"; printf 'litellm.APIConnectionError: connection refused to 127.0.0.1:4000\n'; } > "$L/lint_then_api.log"
t "BENIGN: a REAL litellm error after the lint block still matches" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/lint_then_api.log'"
printf 'blah\nlitellm.ContextWindowExceededError: too big\n' > "$L/ctx.log"
printf 'blah\nlitellm.BadRequestError: bad\n' > "$L/bad.log"
printf 'blah\nopenai.RateLimitError: 429\n' > "$L/rl.log"
printf 'blah\nTraceback (most recent call last):\n  File "x.py", line 1, in <module>\nhttpx.ConnectError: [Errno 111] Connection refused\n' > "$L/tb_api.log"
printf 'blah\nTraceback (most recent call last):\n  File "x.py", line 1, in <module>\nKeyError: foo\n' > "$L/tb_key.log"
for f in ctx bad rl tb_api; do t "BENIGN: real API marker still an API error ($f)" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/$f.log'"; done
t "NEGATIVE: a bare non-API traceback (KeyError) is no longer labelled an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error '$L/tb_key.log'"
t "missing log -> not an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error /nonexistent"
printf 'IMPL_SEQ=none\nSCOUT_EXTRA=%q\n' "$(sed -n 1,16p "$L/lint.log")" > "$TMP/scn_lint"
y_run lint "$PLAIN_PROG" 1 "$TMP/scn_lint"
st="$(oc t-lint status)"
ok "e2e: a cycle whose log holds a lint traceback is NOT error(model/API error): got [$st]" "$([[ "$st" != *"model/API error"* ]] && echo 1 || echo 0)"
y_run apierr "$PLAIN_PROG" 1 <(printf 'IMPL_SEQ=ctx\n')
st="$(oc t-apierr status)"
ok "e2e BENIGN: a real ContextWindowExceededError is still error(model/API error): got [$st]" "$([[ "$st" == error* ]] && echo 1 || echo 0)"
eq "e2e BENIGN: ...and it is still class=error/neutral (valve behaviour unchanged)" "error neutral" "$(oc t-apierr class) $(oc t-apierr severity)"

echo "== review note Y-c: a real API error right after an UNTERMINATED aider lint block is not swallowed =="
head -n -1 "$L/lint.log" > "$L/lint_open.log"        # drop the closing "Tokens:" terminator
{ cat "$L/lint_open.log"; printf 'litellm.APIConnectionError: connection refused to 127.0.0.1:4000\n'; } > "$L/lint_open_api.log"
{ cat "$L/lint_open.log"; printf 'httpx.ConnectError: [Errno 111] Connection refused\n'; } > "$L/lint_open_httpx.log"
{ cat "$L/lint_open.log"; printf 'litellm.ContextWindowExceededError: too big\n'; } > "$L/lint_open_ctx.log"
t "Y-c NEGATIVE: API error directly after an UNTERMINATED lint block is still an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/lint_open_api.log'"
t "Y-c NEGATIVE: ...a bare httpx exception line after it" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/lint_open_httpx.log'"
t "Y-c NEGATIVE: ...ContextWindowExceeded after it" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/lint_open_ctx.log'"
ok "Y-c: the stripped output KEEPS the marker line and still drops the lint traceback" "$(ovn_strip_lint_blocks "$L/lint_open_api.log" | grep -q 'litellm.APIConnectionError' && ! ovn_strip_lint_blocks "$L/lint_open_api.log" | grep -q 'IndentationError' && echo 1 || echo 0)"
t "Y-c BENIGN: the unterminated lint block ALONE (no marker) is still not an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error '$L/lint_open.log'"
{ cat "$L/lint_open.log"; printf "iptv-backend/app/x.py:9:5: F821 undefined name 'APIError'\n    except APIError:\n"; } > "$L/lint_f821.log"
t "Y-c BENIGN: a flake8 F821 line / quoted source naming APIError inside the block is lint, not an API error" bash -c ". '$Q/scripts/lib_item_select.sh'; ! ovn_log_has_api_error '$L/lint_f821.log'"
printf 'Tokens: 1k sent\n# Fix any errors below, if possible.\n\nx.py:3:1: E999 oops\nlitellm.RateLimitError: 429\n' > "$L/lint_rl.log"
t "Y-c NEGATIVE: marker on the line right after the lint heading (block shorter than any cap)" bash -c ". '$Q/scripts/lib_item_select.sh'; ovn_log_has_api_error '$L/lint_rl.log'"

ro_summary
