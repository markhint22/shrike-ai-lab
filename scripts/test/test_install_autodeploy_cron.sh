#!/usr/bin/env bash
# test_install_autodeploy_cron.sh - ops/install_autodeploy_cron.sh (package L4): dry-run default, one marker-guarded block, backup before write, verified install + rollback,
# byte-exact --remove, refusals. A stub `crontab` (file backed) first on PATH; HOME is a sandbox. Then mutants (each must be caught).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
OPSD="${L4_OPS_DIR:-$(cd "$HERE/../.." && pwd)/ops}"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir iadc)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
safe_set_sandbox_home "$T" || exit 1
mkdir -p "$T/bin" "$T/ops"; cp -p "$OPSD/install_autodeploy_cron.sh" "$T/ops/"; : > "$T/ops/box_autodeploy.sh"
CT="$T/ctab"; BK="$HOME/crontab-backups"
cat > "$T/bin/crontab" <<STUB
#!/usr/bin/env bash
CT="$CT"
if [ "\${1:-}" = "-l" ]; then [ "\${STUB_LIST_FAIL:-}" = 1 ] && { echo "crontab: permission denied" >&2; exit 1; }; if [ -f "\$CT" ]; then cat "\$CT"; exit 0; else echo "no crontab for \$USER" >&2; exit 1; fi; fi
[ "\${STUB_WRITE_FAIL:-}" = 1 ] && [ "\${STUB_WRITE_FAIL_N:-1}" = 1 ] && { echo "crontab: cannot write" >&2; export STUB_WRITE_FAIL_N=0; exit 1; }
cp "\$1" "\$CT"
STUB
chmod +x "$T/bin/crontab"; export PATH="$T/bin:$PATH"
run(){ bash "$T/ops/install_autodeploy_cron.sh" "$@" > "$T/out" 2>&1; RC=$?; }
ORIG=$'MAILTO=""\n20 * * * * cd $HOME/overnight-queue && python3 scripts/ovn_notify.py update\n# >>> SUPPLY-LINES BEGIN >>>\n3,33 * * * * supply\n# <<< SUPPLY-LINES END <<<\n'
printf '%s' "$ORIG" > "$CT"
run
ok "I1 dry run is the default: rc 0, crontab untouched, no backup dir, the block and a diff are printed" "$([ $RC = 0 ] && [ "$(cat "$CT")" = "${ORIG%$'\n'}" ] && [ ! -d "$BK" ] && grep -q 'AUTODEPLOY-LINE BEGIN' "$T/out" && grep -q 'DRY RUN' "$T/out" && echo 1 || echo 0)"
run --apply
ok "I2 --apply installs ONE block (shadow, minute 7), keeps every other line, saved a byte-identical backup" "$([ $RC = 0 ] && [ "$(grep -c 'AUTODEPLOY-LINE BEGIN' "$CT")" = 1 ] && grep -q '^7 \* \* \* \* .*OVN_AUTODEPLOY=shadow bash ops/box_autodeploy.sh run' "$CT" && grep -q 'SUPPLY-LINES END' "$CT" && [ "$(cat "$(ls "$BK"/crontab.*.txt | head -1)")" = "${ORIG%$'\n'}" ] && echo 1 || echo 0)"
nb="$(ls "$BK" | wc -l | tr -d ' ')"; run --apply
ok "I3 re-apply is idempotent: 'no change', no second backup" "$([ $RC = 0 ] && grep -q 'no change' "$T/out" && [ "$(ls "$BK" | wc -l | tr -d ' ')" = "$nb" ] && echo 1 || echo 0)"
sleep 1; run --apply --mode enforce
ok "I4 --mode enforce replaces the block in place (still ONE block, enforce)" "$([ $RC = 0 ] && [ "$(grep -c 'AUTODEPLOY-LINE BEGIN' "$CT")" = 1 ] && grep -q 'OVN_AUTODEPLOY=enforce' "$CT" && ! grep -q 'OVN_AUTODEPLOY=shadow' "$CT" && echo 1 || echo 0)"
run --apply --remove
ok "I5 --remove restores the crontab BYTE-EXACTLY to its pre-install state" "$([ $RC = 0 ] && cmp -s "$CT" <(printf '%s' "$ORIG") && echo 1 || echo 0)"
printf '%s' "$ORIG" > "$CT"; before="$(cat "$CT")"
STUB_LIST_FAIL=1 run --apply
ok "I6 crontab -l failing: REFUSED (rc 2), nothing written" "$([ $RC = 2 ] && [ "$(cat "$CT")" = "$before" ] && echo 1 || echo 0)"
rm -f "$CT"; run --apply
ok "I6b 'no crontab' is refused without --allow-empty" "$([ $RC = 2 ] && [ ! -f "$CT" ] && echo 1 || echo 0)"
run --apply --allow-empty
ok "I6c ... and installs with --allow-empty" "$([ $RC = 0 ] && grep -q 'AUTODEPLOY-LINE BEGIN' "$CT" && echo 1 || echo 0)"
printf '%s' "$ORIG" > "$CT"; STUB_WRITE_FAIL=1 run --apply
ok "I7 a failing crontab write: rc 1 and the saved crontab is restored" "$([ $RC = 1 ] && [ "$(cat "$CT")" = "${ORIG%$'\n'}" ] && echo 1 || echo 0)"
run --apply --mode bogus
ok "I8 a bad --mode is refused (rc 2)" "$([ $RC = 2 ] && echo 1 || echo 0)"
printf '%s' "$ORIG" > "$CT"; run --apply --run-suite
ok "I9 --run-suite puts OVN_AUTODEPLOY_RUN_SUITE=1 on the line (shadow keeps shadow)" "$([ $RC = 0 ] && grep -q 'OVN_AUTODEPLOY=shadow OVN_AUTODEPLOY_RUN_SUITE=1 bash ops/box_autodeploy.sh run' "$CT" && echo 1 || echo 0)"
printf '# >>> AUTODEPLOY-LINE BEGIN >>>\n# >>> AUTODEPLOY-LINE BEGIN >>>\n# <<< AUTODEPLOY-LINE END <<<\n' > "$CT"; run --apply
ok "I8b duplicated markers are refused (rc 2), nothing written" "$([ $RC = 2 ] && echo 1 || echo 0)"
SDX="$T/state"; mkdir -p "$SDX"; export AUTODEPLOY_STATE_DIR="$SDX"
printf '%s' "$ORIG" > "$CT"; run --apply
echo '{"ts": 1, "mode": "shadow"}' > "$SDX/autodeploy_report.json"; echo "Box code [shadow]: x" > "$SDX/autodeploy_status.txt"; echo keep > "$SDX/deployed_sha"
run --apply --mode enforce
ok "I10 a mode change leaves the report alone (the next cron pass rewrites it)" "$([ -f "$SDX/autodeploy_report.json" ] && echo 1 || echo 0)"
run --apply --remove
ok "I10b --remove --apply deletes the last autodeploy report + status (no permanent 'report stale' bullet in the hourly update) and nothing else in state/" "$([ $RC = 0 ] && [ ! -e "$SDX/autodeploy_report.json" ] && [ ! -e "$SDX/autodeploy_status.txt" ] && [ -f "$SDX/deployed_sha" ] && echo 1 || echo 0)"
printf '%s' "$ORIG" > "$CT"; run --apply; echo '{"ts": 1}' > "$SDX/autodeploy_report.json"; run --remove
ok "I10c a DRY-RUN --remove deletes nothing" "$([ -f "$SDX/autodeploy_report.json" ] && echo 1 || echo 0)"
unset AUTODEPLOY_STATE_DIR
if [ -z "${L4_NO_MUTANTS:-}" ]; then
  d10="$T/m10"; mkdir -p "$d10/ops"; : > "$d10/ops/box_autodeploy.sh"
  OLD='    rm -f "$SD/autodeploy_report.json" "$SD/autodeploy_status.txt"' NEW=':' python3 - "$OPSD/install_autodeploy_cron.sh" "$d10/ops/install_autodeploy_cron.sh" <<'PYI'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("anchor not found exactly once")
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PYI
  printf '%s' "$ORIG" > "$CT"; bash "$d10/ops/install_autodeploy_cron.sh" --apply >/dev/null 2>&1; echo '{"ts": 1}' > "$SDX/autodeploy_report.json"
  AUTODEPLOY_STATE_DIR="$SDX" bash "$d10/ops/install_autodeploy_cron.sh" --apply --remove >/dev/null 2>&1
  ok "mutant caught: --remove keeps the stale report" "$([ -f "$SDX/autodeploy_report.json" ] && echo 1 || echo 0)"
fi
if [ -z "${L4_NO_MUTANTS:-}" ]; then
  mutant(){ # label old new
    local d="$T/m$RANDOM"; mkdir -p "$d/ops"; : > "$d/ops/box_autodeploy.sh"
    OLD="$2" NEW="$3" python3 - "$OPSD/install_autodeploy_cron.sh" "$d/ops/install_autodeploy_cron.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("anchor not found exactly once: " + os.environ["OLD"][:60])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
    [ $? -eq 0 ] || { ok "mutant '$1' could not be applied" 0; return; }
    cp -p "$T/bin/crontab" "$d/crontab.stub"; printf '%s' "$ORIG" > "$CT"
    local tgt="$d/ops/install_autodeploy_cron.sh" bad=0
    bash "$tgt" --apply > /dev/null 2>&1; bash "$tgt" --apply --remove > /dev/null 2>&1
    cmp -s "$CT" <(printf '%s' "$ORIG") || bad=1
    printf '%s' "$ORIG" > "$CT"
    if [ "$4" = dry ]; then bash "$tgt" > /dev/null 2>&1; [ "$(cat "$CT")" = "${ORIG%$'\n'}" ] || bad=1; fi
    if [ "$4" = backup ]; then rm -rf "${BK:?}"; bash "$tgt" --apply >/dev/null 2>&1; [ -d "$BK" ] || bad=1; fi
    ok "mutant caught: $1" "$bad"
  }
  mutant "--remove leaves the separator line (not byte-exact)" '        head = head[:-1]            # the one blank separator --apply added' '        pass' x
  mutant "the backup is skipped" 'mkdir -p "$BKDIR" && chmod 700 "$BKDIR" || refuse "cannot create the backup dir"' ':' backup
  mutant "dry run writes" 'if [ "$APPLY" != 1 ]; then' 'if false; then' dry
fi
echo "  install_autodeploy_cron: $P passed, $F failed"
[ "$F" -eq 0 ]
