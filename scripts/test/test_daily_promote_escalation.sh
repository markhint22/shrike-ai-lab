#!/usr/bin/env bash
# N7 (2026-11-02): daily_promote.sh escalates a final HELD / BLOCKED promote of billwatch / iptv_apps (OVN_ESC_PROMOTE_REPOS) once per repo through `ovn_notify.py escalate`
# (flag OVN_ESC_PROMOTE_RED, shadow by default). Sandboxed like test_daily_promote.sh (fake HOME, fake promote_to_prod.sh, fake curl, stub escalate command). Mutants must fail.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
G="${OVN_DAILY_PROMOTE:-$HERE/../../daily_promote.sh}"; [ -f "$G" ] || G="$HERE/../daily_promote.sh"
[ -f "$G" ] || { echo "  SKIP: daily_promote.sh not found"; exit 0; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
P=0; F=0
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\necho "CURL $*" >> "$FAKE_CURL_LOG"\nexit 0\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
printf '#!/usr/bin/env bash\necho "ESC $*" >> "$FAKE_ESC_LOG"\nexit 0\n' > "$T/esc_stub.sh"; chmod +x "$T/esc_stub.sh"

scenario(){  # $1 = script, $2 = case name -> number of failed checks
  local script="$1" c="$T/case_${RANDOM}_$$" f=0
  mkdir -p "$c/home/overnight-queue/repos"; cp "$script" "$c/home/overnight-queue/daily_promote.sh"
  for r in billwatch iptv_apps gitlark xlite; do mkdir -p "$c/home/overnight-queue/repos/$r"; done
  cat > "$c/home/overnight-queue/promote_to_prod.sh" <<'EOS'
#!/usr/bin/env bash
case "$(basename "$2")" in
  billwatch) echo "  STAGING-GATE BLOCK: staging is not serving the candidate" ;;
  iptv_apps) echo "  migration safety FAILED - NOT promoting" ;;
  gitlark)   echo "  STAGING-GATE BLOCK: staging is not serving the candidate" ;;
  xlite)     echo "  PROMOTED xlite develop -> main (+3). Prod deploy triggered." ;;
esac
EOS
  chmod +x "$c/home/overnight-queue/promote_to_prod.sh"
  export FAKE_CURL_LOG="$c/curl.log" FAKE_ESC_LOG="$c/esc.log"; : > "$FAKE_CURL_LOG"; : > "$FAKE_ESC_LOG"
  ( HOME="$c/home" PATH="$T/bin:$PATH" OVN_PROMOTE_REPOS="billwatch iptv_apps gitlark xlite" OVN_PROMOTE_RETRY_S=0 OVN_ESCALATE_CMD="$T/esc_stub.sh" bash "$c/home/overnight-queue/daily_promote.sh" >"$c/out.log" 2>&1 )
  chk(){ if ! ( set +o pipefail; eval "$2" ) >/dev/null 2>&1; then f=$((f+1)); echo "    check failed: $1"; fi; }
  chk "N7: a HELD billwatch is escalated once (sig promote_red:billwatch, flag OVN_ESC_PROMOTE_RED)" "[ \$(grep -c -- '--sig promote_red:billwatch' '$c/esc.log') -eq 1 ] && grep -q -- '--flag OVN_ESC_PROMOTE_RED' '$c/esc.log' && grep -q 'Prod promote HELD: billwatch' '$c/esc.log'"
  chk "N7: a BLOCKED iptv_apps is escalated once and named BLOCKED" "[ \$(grep -c -- '--sig promote_red:iptv_apps' '$c/esc.log') -eq 1 ] && grep -q 'Prod promote BLOCKED: iptv_apps' '$c/esc.log'"
  chk "N7: a HELD repo that is not in OVN_ESC_PROMOTE_REPOS (gitlark) is NOT escalated" "! grep -q 'gitlark' '$c/esc.log'"
  chk "N7: a promoted repo (xlite) is not escalated" "! grep -q 'xlite' '$c/esc.log'"
  chk "the normal summary push is unchanged (HELD and BLOCKED lines present)" "grep -q 'HELD' '$c/curl.log' && grep -q 'BLOCKED' '$c/curl.log'"
  return $f
}
runcase(){ local rc; scenario "$2" "$1"; rc=$?
  if [ "$3" = pass ]; then if [ "$rc" = 0 ]; then P=$((P+1)); echo "  ok   $1: scenario passes"; else F=$((F+1)); echo "  FAIL $1: $rc check(s) failed"; fi
  else if [ "$rc" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1 ($rc check(s) fail)"; else F=$((F+1)); echo "  FAIL mutation NOT caught: $1"; fi; fi; }
runcase real "$G" pass
mutate(){ local m="$T/mut_$RANDOM.sh"
  OLD="$2" NEW="$3" python3 - "$G" "$m" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL mutation '$1' could not be applied"; return; }
  runcase "$1" "$m" fail; }
mutate "no escalation at all" 'for _er in $held $blocked; do' 'for _er in; do'
mutate "every repo escalates (repo filter dropped)" '  case " ${OVN_ESC_PROMOTE_REPOS:-billwatch iptv_apps} " in
    *" $_er "*)' '  case " $_er " in
    *" $_er "*)'
mutate "BLOCKED not distinguished from HELD" '_ek="HELD"; case " $blocked " in *" $_er "*) _ek="BLOCKED";; esac' '_ek="HELD"'
mutate "held ignored" 'for _er in $held $blocked; do' 'for _er in $blocked; do'
mutate "wrong flag" '--flag OVN_ESC_PROMOTE_RED >>' '--flag OVN_ESC_NOPE >>'
echo "  daily promote escalation: $P passed, $F failed"
[ "$F" = 0 ]
