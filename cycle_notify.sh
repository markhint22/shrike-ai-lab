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
np=0; nf=0; nr=0; nn=0; ne=0; ni=0
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
    # 2026-09-20 FIX: run_overnight.sh's own "pushed" status has THREE forms -
    # "pushed(tests:pass)" (caught above), "pushed(tests:FAIL - see log)" (caught by
    # the tests:FAIL arm above), and a bare "pushed" / "pushed(after-rebase)" when
    # VERIFY_RESULT was neither pass nor fail (verification skipped/unknown, or a
    # push-rejected-then-rebased retry). That last form has NO "tests:pass" substring,
    # so it fell through every arm to the no-op catch-all below - a real landed commit
    # was being counted (and displayed) as a no-op. Confirmed live in reports/*.md
    # ("ongoing-billwatch | pushed"). Any remaining "pushed*" status at this point in
    # the case (tests:pass/tests:FAIL already sliced off above) is still a real push.
    pushed*)               pass="$pass $id"; np=$((np+1));;
    reverted*|*build-gate*) rev="$rev $id"; nr=$((nr+1));;
    error*)                err="$err $id"; ne=$((ne+1));;
    no-op*)                nn=$((nn+1));;
    # 2026-09-20 FIX: "disabled" (task never ran this cycle), "skip(exhausted)" (repo
    # genuinely has nothing doable - the SAME condition ovn_stats.py's own no-op
    # counter deliberately excludes, see its "'skip' ... is deliberately NOT counted
    # as a no-op" comment), "skipped(paused)" (mid-run pause), and "held(<repo>)" (a
    # human hold) all mean NO attempt happened this cycle - not a no-op attempt that
    # burned a real cycle. These used to fall into the same catch-all as a genuine
    # no-op below, inflating $nn with idle/never-ran rows. Confirmed live: a 3h
    # window's real $nn of 100 was ~76 of these idle rows (40 skip(exhausted) across
    # 4 dry repos + 36 disabled entries for wound-down repos) plus only 23 genuine
    # no-op attempts (state/task_stats.log's own independent classification agreed:
    # exactly 23) plus 1 misclassified bare "pushed" - see digest_notify.sh's no-op
    # line for the other half of this fix. Track them separately (ni) so a reader
    # can no longer see "$NN no-op" claim more no-ops happened than genuinely did.
    disabled|skip\(exhausted\)*|skipped\(paused\)|held\(*\))
      ni=$((ni+1));;
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
  # 2026-09-17 fix: this used to be a naive `grep ... | tail -1` with NO staleness
  # check, so once a repo's cycle_summary.log went quiet for this id (paused,
  # stuck behind a lock-orphan crash-loop, or simply moved to the T3+ staged
  # pipeline -- ovn_stage_runner.sh's higher-tier sub-flow never writes
  # cycle_summary.log at all), EVERY subsequent report line for that id -- even
  # hours later, even a genuine "skip" outcome with nothing to do with the old
  # target -- got silently mislabeled with whatever class=/top_item= was logged
  # last. Diagnosed live 2026-09-17 on test-automation-agent: "update_flake_stats"
  # kept showing up as top_item in task_stats.log for 4+ hours (13:46-21:43) after
  # that item was already AUTO-SKIPped and retired via Claude at 19:08, and while
  # the repo was actually succeeding on unrelated fresh backlog items via the
  # staged pipeline (which produces no cycle_summary.log line to update against) --
  # fabricating the appearance of the 27B endlessly retrying one stuck target.
  # Fix: only reuse a cycle_summary.log line's classification if it's NEWER (by
  # line number) than the last one already consumed for this id; otherwise treat
  # this cycle as unclassified (matches the pre-existing intentional "nothing to
  # classify" skip below) rather than reattributing stale data.
  _cs_match="$(grep -n "ongoing-${id} " "$STATE_DIR/cycle_summary.log" 2>/dev/null | tail -1)"
  _cs_lineno="${_cs_match%%:*}"
  _cs_line="${_cs_match#*:}"
  _cursor_file="$STATE_DIR/.cycle_notify_cursor__${id}"
  _last_lineno="$(cat "$_cursor_file" 2>/dev/null)"
  _last_lineno="${_last_lineno:-0}"
  if [ -n "$_cs_lineno" ] && [ "$_cs_lineno" -gt "$_last_lineno" ] 2>/dev/null; then
    _cls="$(echo "$_cs_line" | grep -oE 'class=\{[^}]*\}' | sed 's/class=//')"
    _cfl="$(echo "$_cs_line" | grep -oE 'top_item=[^ ]+' | sed 's/top_item=//')"
    echo "$_cs_lineno" > "$_cursor_file"
  else
    _cls=""
    _cfl=""
  fi
  [ -n "$_cls" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$id" "$_oc" "$_cls" "${_cfl:-?}" >> "$STATE_DIR/task_stats.log"
done < <(grep -E "^\| ongoing" "$REPORT")

# nothing ran (paused / abort) -> record nothing. ni counts toward this check (not toward
# the digest's "items done" math) so an all-idle cycle (e.g. every repo dry) still writes a
# row instead of being silently dropped - same intent as the original 2026-09-10 fix, just
# with idle rows no longer misrepresented as no-op work below.
[ $((np+nf+nr+nn+ne+ni)) -eq 0 ] && exit 0

j() { echo $* | tr ' ' ',' | sed 's/^,//;s/,$//'; }   # space-list -> comma-list
printf '%s\t%d\t%d\t%d\t%d\t%d\tPASS=%s\tFAIL=%s\tREV=%s\tERR=%s\tIDLE=%d\n' \
  "$(date '+%s')" "$np" "$nf" "$nr" "$nn" "$ne" \
  "$(j $pass)" "$(j $fail)" "$(j $rev)" "$(j $err)" "$ni" \
  >> "$STATE_DIR/digest_buffer.log"
