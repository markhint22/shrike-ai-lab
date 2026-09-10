#!/usr/bin/env bash
# Per-cycle RECORDER (no phone push).
# Old behaviour pushed an ntfy message after every single cycle, which spammed the
# phone the moment the queue started doing real work again (each cycle differs, so
# the dedup no longer suppressed anything). Now this script only:
#   (a) records failing-test NAMES to state/failing_tests.log (trend analysis), and
#   (b) appends one compact, quote-safe record to state/digest_buffer.log.
# digest_notify.sh (cron, ~every 3h) rolls the buffer up into ONE human-readable
# message and clears it. Called at the end of run_overnight.sh:
#     "$SCRIPT_DIR/cycle_notify.sh" "$REPORT_FILE"
set -uo pipefail
REPORT="${1:-}"
[ -f "$REPORT" ] || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
mkdir -p "$STATE_DIR"

# clean, space-free repo-id lists (safe to store tab-separated)
pass=""; fail=""; rev=""; err=""
np=0; nf=0; nr=0; nn=0; ne=0
while IFS='|' read -r _ c_id c_type c_out c_branch c_log _; do
  id="$(echo "$c_id" | xargs | sed 's/^ongoing-//')"
  out="$(echo "$c_out" | xargs)"
  logp="$(echo "$c_log" | xargs)"
  case "$out" in
    *"tests:pass"*)        pass="$pass $id"; np=$((np+1));;
    *"tests:FAIL"*)
      fail="$fail $id"; nf=$((nf+1))
      fc="$(grep -hoE '[0-9]+ failed' "$logp" 2>/dev/null | tail -1)"
      ft="$(grep -hoE 'FAILED [A-Za-z0-9_./:]+|[A-Za-z0-9_./]+\.py::[A-Za-z0-9_:]+ FAILED|(×|✕) [^[:space:]]+' "$logp" 2>/dev/null | sed -E 's/^FAILED //; s/ FAILED$//; s/^(×|✕) //' | sort -u | head -6 | tr '\n' ',' | sed 's/,$//')"
      echo "$(date '+%F %H:%M') | ${id} | ${fc:-?} | ${ft:-<names not in log>}" >> "$STATE_DIR/failing_tests.log"
      ;;
    reverted*|*build-gate*) rev="$rev $id"; nr=$((nr+1));;
    error*)                err="$err $id"; ne=$((ne+1));;
    no-op*)                nn=$((nn+1));;
    # 2026-09-10 fix: qualified no-op forms (no-op(BLOCKED), no-op(stage-unverified),
    # no-op(reverted-red)) and unrelated real outcome strings (disabled, skip(exhausted))
    # used to match none of the above and fall through uncounted - if a WHOLE cycle
    # consisted only of these, the sum stayed 0 and the entire cycle silently never
    # reached digest_buffer.log (line 55 below), even though real activity happened.
    *)                     nn=$((nn+1));;
  esac
  # classification stats (2026-08-31): attribute each repo-cycle outcome to the
  # item's classification (lang/type/complexity/verifiability) for pass-rate slicing.
  case "$out" in
    *tests:pass*) _oc=pass;; *tests:FAIL*) _oc=fail;;
    reverted*|*build-gate*) _oc=revert;; error*) _oc=error;;
    *ALREADY-DONE*) _oc=noop:done;;             # item already satisfied in code (mis-targeted / credit-gap)
    *BLOCKED*|*NEEDS-DECISION*) _oc=noop:blocked;; # model needs a human decision to proceed
    no-op*revert*) _oc=noop:gate;;              # model changed code, a gate reverted it (too-hard attempt)
    no-op*) _oc=noop:flail;;                    # PROCEED but produced no usable diff (too hard for the 27B)
    *) _oc=skip;;
  esac
  _cs_line="$(grep "ongoing-${id} " "$STATE_DIR/cycle_summary.log" 2>/dev/null | tail -1)"
  _cls="$(echo "$_cs_line" | grep -oE 'class=\{[^}]*\}' | sed 's/class=//')"
  _cfl="$(echo "$_cs_line" | grep -oE 'top_item=[^ ]+' | sed 's/top_item=//')"
  [ -n "$_cls" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$id" "$_oc" "$_cls" "${_cfl:-?}" >> "$STATE_DIR/task_stats.log"
done < <(grep -E "^\| ongoing" "$REPORT")

# nothing ran (paused / abort) -> record nothing
[ $((np+nf+nr+nn+ne)) -eq 0 ] && exit 0

j() { echo $* | tr ' ' ',' | sed 's/^,//;s/,$//'; }   # space-list -> comma-list
printf '%s\t%d\t%d\t%d\t%d\t%d\tPASS=%s\tFAIL=%s\tREV=%s\tERR=%s\n' \
  "$(date '+%s')" "$np" "$nf" "$nr" "$nn" "$ne" \
  "$(j $pass)" "$(j $fail)" "$(j $rev)" "$(j $err)" \
  >> "$STATE_DIR/digest_buffer.log"
