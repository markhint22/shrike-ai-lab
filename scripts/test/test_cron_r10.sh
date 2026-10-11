#!/usr/bin/env bash
# docs/patches/cron-r10.txt (qacov R10): the three active cron lines are run VERBATIM, with HOME redirected to a fixture "live dir", so a typo in the documented lines fails here.
#   spec gate scan (shadow): rows land in state/spec_gate.jsonl, the backlog is byte-identical afterwards, the flock keeps a second scan out, OVN_SPEC_GATE=off writes nothing
#   mutation scan: survivors file produced from a scratch archive of the fixture repo (shim godot at $HOME/godot/godot4), the live clone is untouched, no mutscan-* is left behind,
#                  state/PAUSED skips it
#   log cap: dry run - reports WOULD cap and changes nothing
# Mutants of the doc (a line broken) must fail the same assertions. SKIPs where flock/timeout/git are missing. bash 3.2 ok.
set -uo pipefail
# The whole body is ONE function, called on the last line: bash reads a script incrementally, so a file that is replaced in place while it runs (a deploy rsync over the live
# dir, an editor save during a 20 s run) used to make the RUNNING copy die with a syntax error at a stale byte offset (seen in the 10-10/10-11 review: "line 55: syntax error near
# unexpected token" in 2 of 48 looped runs that overlapped an edit). Bash parses a function definition completely before executing anything, so the run is immune.
main() {
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"                       # scripts/
DOC="$HERE/../../../../docs/patches/cron-r10.txt"; [ -f "$DOC" ] || DOC="$HERE/../../docs/patches/cron-r10.txt"
# The live dir on the box carries no docs/, so there this test is a no-op: it only runs on a checkout. OVN_TEST_REQUIRE_DOCS=1 turns that SKIP into a FAILURE (scripts/test/premerge_docs_tests.sh sets it).
[ -f "$DOC" ] || { if [ "${OVN_TEST_REQUIRE_DOCS:-0}" = 1 ]; then echo "  FAIL: docs/patches/cron-r10.txt not present next to this tree and OVN_TEST_REQUIRE_DOCS=1"; exit 1; fi
                   echo "  SKIP: docs/patches/cron-r10.txt not present next to this tree (live-dir copy without docs/) - NOTHING WAS TESTED; run it from a checkout (premerge_docs_tests.sh)"; exit 0; }
for t in flock timeout git python3 nice; do command -v $t >/dev/null 2>&1 || { echo "  SKIP: no $t"; exit 0; }; done
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
GITQ=(git -c user.name=t -c user.email=t@t)
cron_line(){ grep -v '^#' "$1" | grep -F -e "$2" | head -1; }    # active line of doc $1 containing $2
L_SPEC="$(cron_line "$DOC" 'scripts/ovn_spec_gate.py scan')"; L_MUT="$(cron_line "$DOC" 'scripts/ovn_mutation_supply.py scan')"; L_CAP="$(cron_line "$DOC" 'scripts/ovn_log_cap.sh')"
ok "the doc carries exactly three active cron lines (spec scan, mutation scan, log cap)" "[ \"\$(grep -vc '^#' '$DOC' | tr -d ' ')\" = 3 ] && [ -n \"\$L_SPEC\" ] && [ -n \"\$L_MUT\" ] && [ -n \"\$L_CAP\" ]"
ok "every active line is a 5-field cron schedule followed by 'cd ~/overnight-queue'" "[ \"\$(grep -v '^#' '$DOC' | grep -cE '^[0-9*/,]+ [0-9*/,]+ \\* \\* \\* cd ~/overnight-queue && ')\" = 3 ]"
ok "SHADOW: the spec scan line sets OVN_SPEC_GATE=shadow, takes a flock, and arms no enforcement" "echo \"\$L_SPEC\" | grep -q 'OVN_SPEC_GATE=shadow' && echo \"\$L_SPEC\" | grep -q 'flock -n state/spec_gate.lock' && ! echo \"\$L_SPEC\" | grep -q ENFORCE"
ok "the mutation line is nice 19 + timeout + flock + OVN_MUT_MAX, scans repos/xlite (ONE repo_dir argument), and does not enable OVN_SUPPLY_MUTATION" "echo \"\$L_MUT\" | grep -q 'nice -n 19 timeout 5400 env OVN_MUT_MAX=60 python3 scripts/ovn_mutation_supply.py scan repos/xlite ' && echo \"\$L_MUT\" | grep -q 'flock -n state/mutation_scan.lock' && ! echo \"\$L_MUT\" | grep -q OVN_SUPPLY_MUTATION"
ok "the log cap line is the DRY RUN (no --apply, no OVN_LOG_CAP=on)" "! echo \"\$L_CAP\" | grep -qE -e '--apply|OVN_LOG_CAP=on'"

# ---- fixture live dir
mkq(){  # <name> -> $T/<name>/home/overnight-queue (HOME=$T/<name>/home)
  local h="$T/$1/home" q="$T/$1/home/overnight-queue" r
  mkdir -p "$q/scripts" "$q/state" "$q/backlog" "$q/repos" "$q/logs" "$h/godot"
  for f in lib_verify_clause.sh lib_gut_xml.sh lib_worktree.sh ovn_spec_check.sh ovn_spec_gate.py ovn_spec_rules.py ovn_spec_classify.py ovn_backlog_eligibility.py ovn_mutation_supply.py ovn_log_cap.sh; do cp "$SRC/$f" "$q/scripts/" 2>/dev/null; done
  chmod +x "$q/scripts/ovn_log_cap.sh"
  printf '#!/bin/sh\ncase "$*" in *--import*) exit 0;; esac\necho "Tests 1"; echo "  Passing 1"; echo "---- All tests passed! ----"; exit 0\n' > "$h/godot/godot4"; chmod +x "$h/godot/godot4"
  for r in iptv_apps xlite; do
    git init -q --bare -b main "$T/$1/origin_$r.git"; git clone -q "$T/$1/origin_$r.git" "$q/repos/$r" 2>/dev/null
    ( cd "$q/repos/$r" || exit 1
      "${GITQ[@]}" checkout -q -b overnight/feature
      mkdir -p app scripts/units tests; : > app/__init__.py; printf 'old here\n' > f.txt
      echo 'config/name="XLite"' > project.godot
      printf 'class_name A\nstatic func f(x, y):\n\tif x < y:\n\t\treturn 1\n\treturn 0\n' > scripts/units/a.gd
      printf 'extends GutTest\nfunc test_f():\n\tassert_eq(A.f(1, 2), 1)\n' > tests/test_a.gd
      printf '# progress\n' > OVERNIGHT_PROGRESS.md
      git add -A && "${GITQ[@]}" commit -q -m init && git push -q origin overnight/feature ) >/dev/null 2>&1
    printf '# backlog\n- [ ] [T2] app/a.py — Change a. VERIFY: `true`. (cat:python; multifile:no)\n- [ ] [T2] f.txt — Rename old. VERIFY: `grep -q old f.txt && echo FAIL || echo PASS`. (cat:python; multifile:no)\n' > "$q/backlog/$r.md"
  done
  printf '%s' "$q"
}
runline(){ # <name> <cron line>: run the line's command part (after the 5 schedule fields) under sh with HOME redirected, as cron would
  local cmd; cmd="$(printf '%s' "$2" | cut -d' ' -f6-)"
  ( HOME="$T/$1/home"; export HOME; unset OVN_DIR OVN_Q OVN_SPEC_GATE OVN_SPEC_BASE OVN_MUT_REF OVN_GODOT_BIN OVN_MUT_SEED OVN_LOG_CAP OVN_LOG_CAP_MB OVN_MUTATION_SCAN OVN_MUT_MAX; cd / && sh -c "$cmd" ); echo $? > "$T/$1/rc"
}
rows(){ [ -f "$1/state/spec_gate.jsonl" ] && wc -l < "$1/state/spec_gate.jsonl" | tr -d ' ' || echo 0; }

echo "== spec gate scan line (shadow)"
Q="$(mkq spec)"; cp "$Q/backlog/iptv_apps.md" "$T/ba.before"; cp "$Q/backlog/xlite.md" "$T/bx.before"
runline spec "$L_SPEC"
ok "the cron line exits 0 and logs one 'spec_gate scan' line per repo" "[ \"\$(cat '$T/spec/rc')\" = 0 ] && [ \"\$(grep -c '^spec_gate scan' '$Q/logs/spec_gate.log')\" -ge 2 ] && grep -q 'spec_gate scan iptv_apps' '$Q/logs/spec_gate.log' && grep -q 'spec_gate scan xlite' '$Q/logs/spec_gate.log'"
ok "state/spec_gate.jsonl gets rows for BOTH repos (2 open lines each)" "[ \"\$(rows '$Q')\" = 4 ] && grep -q '\"repo\": \"iptv_apps\"' '$Q/state/spec_gate.jsonl' && grep -q '\"repo\": \"xlite\"' '$Q/state/spec_gate.jsonl'"
ok "SHADOW: both backlogs are byte-identical after the scan (cmp)" "cmp -s '$Q/backlog/iptv_apps.md' '$T/ba.before' && cmp -s '$Q/backlog/xlite.md' '$T/bx.before'"
ok "every row records mode=shadow" "! grep -v '\"mode\": \"shadow\"' '$Q/state/spec_gate.jsonl' | grep -q ."
( cd "$Q" && OVN_DIR="$Q" python3 scripts/ovn_spec_gate.py report > "$T/report.txt" 2>&1 )
ok "'ovn_spec_gate.py report' shows a verdict mix (the acceptance command)" "grep -qiE 'verdict|red|pass' '$T/report.txt'"
runline spec "$L_SPEC"
ok "second tick: memo hit, no new rows (idempotent within the TTL)" "[ \"\$(rows '$Q')\" = 4 ]"
# the flock: hold the lock, run the line, nothing happens (and it exits non-zero, which cron ignores)
Q2="$(mkq lock)"
( exec 9>"$Q2/state/spec_gate.lock"; flock -n 9 || exit 3; runline lock "$L_SPEC"; echo held > "$T/lock/held" )
ok "flock -n: while another scan holds state/spec_gate.lock the line does nothing (no rows, no log lines)" "[ \"\$(rows '$Q2')\" = 0 ] && [ ! -s '$Q2/logs/spec_gate.log' ] && [ \"\$(cat '$T/lock/rc')\" != 0 ]"
Q3="$(mkq off)"; sed 's/OVN_SPEC_GATE=shadow/OVN_SPEC_GATE=off/' <<< "$L_SPEC" > "$T/line_off"; runline off "$(cat "$T/line_off")"
ok "kill switch OVN_SPEC_GATE=off: scan writes nothing" "[ \"\$(rows '$Q3')\" = 0 ] && grep -q 'OVN_SPEC_GATE=off' '$Q3/logs/spec_gate.log'"
Q4="$(mkq paused)"; : > "$Q4/state/PAUSED"; runline paused "$L_SPEC"
ok "state/PAUSED: scan is skipped" "[ \"\$(rows '$Q4')\" = 0 ] && grep -q 'queue is paused' '$Q4/logs/spec_gate.log'"
# mutant: the scan line without the repo loop variable -> scans nothing useful
sed 's/scan \$r/scan nosuchrepo/' <<< "$L_SPEC" > "$T/line_mut1"; Q5="$(mkq mut1)"; runline mut1 "$(cat "$T/line_mut1")"
ok "MUTANT (wrong repo name in the line): no rows - proves the rows assertions bite" "[ \"\$(rows '$Q5')\" = 0 ]"

echo "== mutation scan line"
M="$(mkq mut)"; ( cd "$M/repos/xlite" && git status --porcelain > "$T/live.before"; git rev-parse HEAD > "$T/live.head" )
mkdir -p "$T/tmpdir"; export TMPDIR="$T/tmpdir"
runline mut "$L_MUT"
ok "the cron line exits 0, appends the scan summary to logs/mutation_scan.log" "[ \"\$(cat '$T/mut/rc')\" = 0 ] && grep -q 'mutation scan xlite: ran' '$M/logs/mutation_scan.log'"
ok "state/mutation_survivors_xlite.json exists and lists the weakly-tested site (shim godot never fails => every mutant survives)" "python3 -c \"import json,sys; d=json.load(open('$M/state/mutation_survivors_xlite.json')); sys.exit(0 if d['survivors'] and d['survivors'][0]['file']=='scripts/units/a.gd' else 1)\""
ok "the live clone is untouched (same porcelain, same HEAD) and no scratch archive (mutscan-*) is left in TMPDIR" "( cd '$M/repos/xlite' && [ \"\$(git status --porcelain)\" = \"\$(cat '$T/live.before')\" ] && [ \"\$(git rev-parse HEAD)\" = \"\$(cat '$T/live.head')\" ] ) && [ \"\$(ls '$T/tmpdir' | grep -c mutscan)\" = 0 ]"
ok "OVN_SUPPLY_MUTATION stays off: collect() yields nothing from the survivors file" "( cd '$M/scripts' && OVN_DIR='$M' python3 -c \"import ovn_mutation_supply as m; print(len(list(m.collect('$M/repos/xlite'))))\" | grep -qx 0 )"
M2="$(mkq mutp)"; : > "$M2/state/PAUSED"; runline mutp "$L_MUT"
ok "state/PAUSED: the mutation scan does not run (no survivors file, rc != 0 from the guard)" "[ ! -e '$M2/state/mutation_survivors_xlite.json' ] && [ \"\$(cat '$T/mutp/rc')\" != 0 ]"
M3="$(mkq muto)"; ( HOME="$T/muto/home"; export HOME OVN_MUTATION_SCAN=off; cd / && sh -c "$(printf '%s' "$L_MUT" | cut -d' ' -f6-)" ) > "$T/muto/out" 2>&1
ok "kill switch OVN_MUTATION_SCAN=off: no survivors file" "[ ! -e '$M3/state/mutation_survivors_xlite.json' ] && grep -q 'OVN_MUTATION_SCAN=off' '$M3/logs/mutation_scan.log'"
sed 's/scan repos\/xlite/scan scratch-archive repos\/xlite/' <<< "$L_MUT" > "$T/line_mut2"; M4="$(mkq mut2)"; runline mut2 "$(cat "$T/line_mut2")"
ok "MUTANT (the analysis' draft: an extra scratch-archive argument before repos/xlite): no survivors file for xlite - proves the contract assertion bites" "[ ! -e '$M4/state/mutation_survivors_xlite.json' ]"

echo "== log cap line (dry run)"
C="$(mkq cap)"; dd if=/dev/zero bs=1048576 count=22 2>/dev/null | tr '\0' 'x' | fold -w 100 > "$C/logs/big.log"; cp "$C/logs/big.log" "$T/big.before"
runline cap "$L_CAP"
ok "the cron line exits 0, reports WOULD cap big.log, and leaves every byte in place" "[ \"\$(cat '$T/cap/rc')\" = 0 ] && grep -q 'WOULD cap big.log' '$C/logs/log_cap.log' && cmp -s '$C/logs/big.log' '$T/big.before' && [ ! -d '$C/logs/archive' ]"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
}
main "$@"; exit $?
