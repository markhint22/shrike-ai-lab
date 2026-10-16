#!/usr/bin/env bash
# docs/patches/cron-r11.txt (package acct, platform P7, 2026-10-11): the DOC PATCH that lists the supply / qa / spec-gate / mutation-scan / log-cap cron lines. Nothing here is installed by the test or by the doc.
# The check is against fixtures/live_crontab_2026-10-11.txt = the box's `crontab -l` at 2026-10-11 ~12:28 CDT (read-only snapshot, the ntfy topic redacted; refreshed in fixer round 2 - the 11:25 snapshot
# predated the install of the spec-gate, mutation-scan and log-cap lines, which made the doc call them NOT installed):
#   - every SECTION A and SECTION B line is VERBATIM in the live snapshot (the doc does not invent lines, and does not call an installed line NOT installed) and is not yet in scripts/cron.txt (finding F2), unless the lead has merged it since
#   - SECTION B (spec gate, mutation scan, log cap; finding F3 RESOLVED) is shadow/observer only: the spec-gate line is flock-guarded and arms no enforcement
#   - the three lines scripts/cron.txt carries today are live verbatim (finding F1: its 'NOT INSTALLED' header is stale and its install idiom would duplicate them)
#   - every active line is 5-field cron syntax, runs a script that exists in this tree, and nothing is listed twice
# MUTATION controls: a line with a typo in the doc, an enforcement flag, a missing script, a duplicate - each must fail the matching assertion.
# SKIPs on a live-dir copy without docs/ (OVN_TEST_REQUIRE_DOCS=1 turns that into a failure, as scripts/test/premerge_docs_tests.sh does). bash 3.2 ok.
set -uo pipefail
main() {
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"                     # the queue tree (scripts/overnight-queue or ~/overnight-queue)
DOC="$HERE/../../../../docs/patches/cron-r11.txt"; [ -f "$DOC" ] || DOC="$HERE/../../docs/patches/cron-r11.txt"
SNAP="$HERE/fixtures/live_crontab_2026-10-11.txt"
CRONTXT="$SRC/scripts/cron.txt"
[ -f "$DOC" ] || { if [ "${OVN_TEST_REQUIRE_DOCS:-0}" = 1 ]; then echo "  FAIL: docs/patches/cron-r11.txt not present and OVN_TEST_REQUIRE_DOCS=1"; exit 1; fi
                   echo "  SKIP: docs/patches/cron-r11.txt not present next to this tree (live-dir copy without docs/) - NOTHING WAS TESTED; run it from a checkout"; exit 0; }
[ -f "$SNAP" ] || { echo "  FAIL: fixture $SNAP missing"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT

# active (non-comment, non-blank) lines of the doc, split by section: A = before the 'SECTION B' header, B = between B and C
awk '/^# SECTION B /{s="B"} /^# SECTION C /{s="C"} /^#/ || NF == 0 {next} {print (s==""?"A":s) "\t" $0}' "$DOC" > "$T/active.tsv"
awk -F'\t' '$1=="A"{sub(/^A\t/,""); print}' "$T/active.tsv" > "$T/secA.txt"
awk -F'\t' '$1=="B"{sub(/^B\t/,""); print}' "$T/active.tsv" > "$T/secB.txt"
cut -f2- "$T/active.tsv" > "$T/all.txt"
nA="$(grep -c . "$T/secA.txt" | tr -d ' ')"; nB="$(grep -c . "$T/secB.txt" | tr -d ' ')"
scripts_of(){ grep -oE '(scripts|qa)/[A-Za-z0-9_]+\.(py|sh)' "$1" | sort -u; }          # the repo-relative scripts a set of cron lines runs
all_exist(){ local s; for s in $(scripts_of "$1"); do [ -f "$SRC/$s" ] || { echo "missing $s"; return 1; }; done; }
# merged state of SECTION A in a cron.txt: 0 = none of the lines, or all of them (consistent); 1 = a HALF merge
merged_ok(){ local c=0 l; while IFS= read -r l; do grep -qxF -- "$l" "$1" && c=$((c+1)); done < "$T/all.txt"; [ "$c" = 0 ] || [ "$c" = "$((nA+nB))" ]; }

echo "== A: the doc against the live snapshot"
ok "A1 SECTION A carries the 6 supply/qa lines and SECTION B the 3 installed shadow/observer lines (spec-gate scan, mutation scan, log cap)" "[ '$nA' = 6 ] && [ '$nB' = 3 ]"
ok "A2 every SECTION A and SECTION B line is VERBATIM in the live crontab snapshot (nothing invented, nothing stale)" "while IFS= read -r l; do grep -qxF -- \"\$l\" '$SNAP' || { echo MISSING: \$l; exit 1; }; done < '$T/all.txt'"
ok "A3 the six lines are exactly: supply, qa_block_watch, qa_daily_shadow --staging-only, staging_e2e_run, staging_e2e_ingest, evidence_freshness_check" "for k in ovn_work_supply.py qa_block_watch.py 'qa_daily_shadow.sh --staging-only' staging_e2e_run.sh staging_e2e_ingest.py evidence_freshness_check.py; do [ \"\$(grep -cF -- \"\$k\" '$T/secA.txt')\" = 1 ] || { echo \"\$k\"; exit 1; }; done"
ok "A4 F3 RESOLVED: the spec-gate scan, the mutation scan and the log cap ARE in the live snapshot (12:28 CDT), and the doc no longer tags any line '[NOT installed]' or lists a NOT-installed section" "grep -q 'ovn_spec_gate.py scan' '$SNAP' && grep -q 'ovn_mutation_supply.py scan' '$SNAP' && grep -q 'ovn_log_cap.sh' '$SNAP' && ! grep -q '\[NOT installed\]' '$DOC' && ! grep -q '^# SECTION B - NOT INSTALLED' '$DOC' && grep -q 'F3. RESOLVED' '$DOC'"
ok "A5 F1: the three active lines scripts/cron.txt carries today are live verbatim (its 'NOT INSTALLED' header is stale)" "[ -f '$CRONTXT' ] && n=0 && while IFS= read -r l; do grep -qxF -- \"\$l\" '$SNAP' || exit 1; n=\$((n+1)); done < <(grep -v '^#' '$CRONTXT' | grep -v '^\$') && [ \"\$n\" -ge 3 ]"
ok "A6 F2: no SECTION A/B line is in scripts/cron.txt yet - or ALL of them are (the lead merged the patch); never half" "[ -f '$CRONTXT' ] && merged_ok '$CRONTXT'"
ok "A7 the doc warns against the duplicating install idiom and gives the idempotent form" "grep -q 'DUPLICATES them' '$DOC' && grep -q 'grep -vF -e \"scripts/ovn_spec_gate.py scan\"' '$DOC'"

echo "== B: syntax, script existence, shadow-only"
ok "B1 every active line is a 5-field cron schedule" "[ \"\$(grep -cE '^[0-9*/,]+ [0-9*/,]+ [0-9*/,]+ [0-9*/,]+ [0-9*/,]+ [^ ]' '$T/all.txt')\" = 9 ]"
ok "B2 every script an active line runs exists in this tree (9 distinct scripts)" "all_exist '$T/all.txt' && [ \"\$(scripts_of '$T/all.txt' | wc -l | tr -d ' ')\" = 9 ]"
ok "B3 nothing is listed twice" "[ \"\$(sort '$T/all.txt' | uniq -d | wc -l | tr -d ' ')\" = 0 ]"
ok "B4 SHADOW: the spec-gate line pins OVN_SPEC_GATE=shadow, takes the flock, and sets no ENFORCE variable" "l=\"\$(grep -F 'ovn_spec_gate.py scan' '$T/secB.txt')\"; [ -n \"\$l\" ] && echo \"\$l\" | grep -q 'OVN_SPEC_GATE=shadow' && echo \"\$l\" | grep -q 'flock -n state/spec_gate.lock' && ! echo \"\$l\" | grep -qE 'ENFORCE|OVN_SPEC_GATE=enforce'"
ok "B5 no active line anywhere enables enforcement, executors beyond shadow, or the mutation feed" "! grep -qE 'OVN_SPEC_GATE=enforce|ENFORCE_RULES|OVN_DOC_EXECUTOR=(on|enforce)|OVN_SUPPLY_MUTATION=1' '$T/all.txt'"
ok "B6 the three SECTION B lines match docs/patches/cron-r10.txt (qacov) verbatim - one source, no drift" "r10=\"\$(dirname '$DOC')/cron-r10.txt\"; [ ! -f \"\$r10\" ] || while IFS= read -r l; do grep -qxF -- \"\$l\" \"\$r10\" || exit 1; done < '$T/secB.txt'"

echo "== C: MUTATION controls (a broken doc must fail the same assertions)"
sed 's#python3 qa/qa_block_watch.py#python3 qa/qa_block_wach.py#' "$T/secA.txt" > "$T/mA_typo.txt"
ok "C1 MUTATION: a typo in a SECTION A line is no longer verbatim in the snapshot (A2 would fail)" "! ( while IFS= read -r l; do grep -qxF -- \"\$l\" '$SNAP' || exit 1; done < '$T/mA_typo.txt' )"
sed 's/OVN_SPEC_GATE=shadow/OVN_SPEC_GATE=enforce/' "$T/secB.txt" > "$T/mB_enf.txt"
ok "C2 MUTATION: OVN_SPEC_GATE=enforce in the spec line fails the shadow check (B4 would fail)" "! ( l=\"\$(cat '$T/mB_enf.txt')\"; echo \"\$l\" | grep -q 'OVN_SPEC_GATE=shadow' )"
ok "C3 MUTATION: a line naming a script that does not exist fails the existence check (B2 would fail)" "! all_exist '$T/mA_typo.txt'"
{ cat "$T/all.txt"; head -1 "$T/secA.txt"; } > "$T/mDup.txt"
ok "C4 MUTATION: a duplicated line is detected (B3 would fail)" "[ \"\$(sort '$T/mDup.txt' | uniq -d | wc -l | tr -d ' ')\" -ge 1 ]"
{ cat "$CRONTXT"; head -1 "$T/secA.txt"; } > "$T/mHalf_cron.txt"
ok "C5 MUTATION: a cron.txt that carries only SOME of SECTION A is flagged (A6 would fail)" "! merged_ok '$T/mHalf_cron.txt'"
{ cat "$CRONTXT"; cat "$T/all.txt"; } > "$T/mFull_cron.txt"
ok "C6 control: a cron.txt that carries ALL of SECTIONS A+B is accepted" "merged_ok '$T/mFull_cron.txt'"

sed 's/^# \[installed\] SPEC GATE SCAN/# [NOT installed] SPEC GATE SCAN/' "$DOC" > "$T/mStale_doc.txt"
ok "C7 MUTATION: the stale shape (a live line tagged '[NOT installed]', the 11:25 doc) fails the A4 check" "! ( ! grep -q '\[NOT installed\]' '$T/mStale_doc.txt' )"
sed 's/ scripts\/ovn_log_cap.sh / scripts\/ovn_log_cap2.sh /' "$T/secB.txt" > "$T/mB_notlive.txt"
ok "C8 MUTATION: a SECTION B line that is not live-verbatim (a line the box does not have) is detected (A2 would fail)" "! ( while IFS= read -r l; do grep -qxF -- \"\$l\" '$SNAP' || exit 1; done < '$T/mB_notlive.txt' )"

echo "cron r11 doc patch: $P passed, $F failed"; [ "$F" -eq 0 ]
}
main "$@"
