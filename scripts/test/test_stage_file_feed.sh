#!/usr/bin/env bash
# N4 stage-runner-waste, Part 4 (2026-10-13): OVN_STAGE_FILE_FEED in ovn_stage_runner.sh. 26 of 130 staged step attempts in 48h ended with NO edit because the architect replied 'Please add the following
# files to the chat' (iptv_apps-20261013-082239-1305878-s0.log needs routers/subscription.py + conftest.py while the step FILES lists only tests/test_subscription.py); aider's single-shot --message mode never
# loops back for them, and the staged path (unlike run_overnight.sh's iterative file-feeding) had no feeding. The paths the architect named are validated and added (max 3) to the RETRY.
# Drives the REAL ovn_stage_runner.sh in the hermetic fixture (lib_osr_fixture.sh); the stub aider prints the architect's request on attempt 1 and records its argv. Needs GNU sed + bash 5.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
# --- Part U (unit, runs anywhere incl. the Mac): stage_feed_files extracted from the real runner, run under `set -o pipefail` against a repo whose `git ls-files` listing exceeds the 64 KB pipe buffer.
# Regression for the pipefail trap: `printf "$lst" | grep -qxF "$tok"` returned 141 (SIGPIPE) once the listing was bigger than the pipe buffer and the match was early in it, so an architect-named EXACT path
# was silently dropped in the big repos (iptv_apps ~70 KB, xlite ~75 KB). Small fixture repos can never show it.
UW="$(mktemp -d)" || exit 1; trap 'rm -rf "$UW"; osr_cleanup' EXIT
{ sed -n '/^# >>> n4-stage-waste helpers: scope-learn/,/^# <<< n4-stage-waste helpers: scope-learn/p' "$RUNNER"; sed -n '/^# >>> n4-stage-waste helpers: file-feed/,/^# <<< n4-stage-waste helpers: file-feed/p' "$RUNNER"; } > "$UW/h.sh"
[ -s "$UW/h.sh" ] && grep -q '^stage_feed_files()' "$UW/h.sh" || { echo "  FAIL: file-feed helper block not found in $RUNNER"; exit 1; }
# shellcheck disable=SC1091
. "$UW/h.sh"
BIG="$UW/big"; mkdir -p "$BIG/aaa" "$BIG/zzz"; git -C "$BIG" init -q; git -C "$BIG" config user.email t@t; git -C "$BIG" config user.name t
printf 'x = 1\n' > "$BIG/aaa/early.py"; printf 'y = 2\n' > "$BIG/zzz/late.py"; printf 'z = 3\n' > "$BIG/aaa/zz_uniq_basename.py"
git -C "$BIG" add aaa/early.py zzz/late.py aaa/zz_uniq_basename.py
# ~1700 index-only entries (empty blob, no working file) with 60+ char paths -> the listing is well over 64 KB
EB="$(git -C "$BIG" hash-object -w --stdin </dev/null)"
for i in $(seq 1 1700); do printf '100644 %s\t%s\n' "$EB" "mmm/padding_directory_with_a_long_name_for_the_listing/file_number_$i.py"; done | git -C "$BIG" update-index --index-info
LSZ="$(git -C "$BIG" ls-files | wc -c | tr -d ' ')"
t "U0 fixture listing is over the 64 KB pipe buffer ($LSZ bytes)" test "$LSZ" -gt 70000
printf 'Please add the following files to the chat:\n\n 1 aaa/early.py\n 2 zzz/late.py\n 3 zz_uniq_basename.py\nTokens: 1 sent\n' > "$UW/arch.log"
FED="$(set -uo pipefail; stage_feed_files "$UW/arch.log" "$BIG" "" 3)"
t "U1 an EXACT repo path early in a >64 KB listing is fed under pipefail (the old pipeline dropped it)" bash -c "printf '%s\n' \"\$1\" | grep -qx 'aaa/early.py'" _ "$FED"
t "U2 an exact path late in the listing is still fed" bash -c "printf '%s\n' \"\$1\" | grep -qx 'zzz/late.py'" _ "$FED"
t "U3 a bare basename that is unique in the listing still resolves" bash -c "printf '%s\n' \"\$1\" | grep -qx 'aaa/zz_uniq_basename.py'" _ "$FED"
t "U4 exactly those three are returned" test "$(printf '%s\n' "$FED" | grep -c .)" = 3
echo "== U (unit) done"
if ! sed --version >/dev/null 2>&1; then echo "  (Part A-F skipped: needs GNU sed; run on the box)"; osr_summary; _s=$?; [ "$_s" -ne 0 ] && exit "$_s"; echo "  NOT RUN: Parts A-F need GNU sed (run on the box)"; exit 77; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_FILE_FEED OVN_STAGE_FILE_FEED_MAX_BYTES OVN_STAGE_SCOPE_LEARN NTFY_SERVER NTFY_TOPIC
trap 'rm -rf "$UW"; osr_cleanup' EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
ITEM_MF='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python; multifile:no)'
# attempt 1: the architect only asks for files (aider.log shape from the box: numbered, wrapped, then Tokens:) and edits nothing
ask(){ printf '%s\n' 'echo "I will request these files."' 'echo' 'echo "Please add the following files to the chat:"' 'echo' "$@" 'echo' 'echo "Tokens: 7.8k sent, 448 received."'; }
ASK_BASIC="$(ask 'echo " 1 backend/app/svc.py"' 'echo " 2 backend/tests/test_svc.py"' 'echo " 3 backend/app/nonexistent.py (or wherever it is defined, e.g., app/core/other.py)"')"
has_arg(){ # $1=flag $2=path $3=aider call number -> argv has "$1" immediately followed by "$2"
  awk -v f="$1" -v p="$2" 'prev==f && $0==p {found=1} {prev=$0} END{exit !found}' "$T/scn/aider.args.$3"; }
setup(){ osr_new; osr_venv backend; osr_tracked backend/tests/test_svc.py 'from app.svc import run_job\n\ndef test_x():\n    assert run_job() == 1\n'
  osr_progress "- [ ] ${1:-$ITEM_PY}"; osr_plan default "$PLAN"; osr_aider 1 "$ASK_BASIC"; osr_aider 2 "$SNIP_FOO"; }
run(){ OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"; }

echo "== A: the files the architect named are added to the retry (--file for a normal item)"
setup; run
t "A1 attempt 1 is a no-edit" G "step 0 att 1 FAIL (no-edit"
t "A2 file-feed is logged with the two files that exist (and not the missing one)" bash -c "grep -q 'file-feed: the architect asked for files - adding backend/app/svc.py backend/tests/test_svc.py to the retry' '$T/out.txt'"
t "A3 attempt 2's aider argv has --file backend/app/svc.py and --file backend/tests/test_svc.py" bash -c "$(declare -f has_arg); T='$T'; has_arg --file backend/app/svc.py 2 && has_arg --file backend/tests/test_svc.py 2"
t "A4 the nonexistent path and the 'e.g.' alternative are NOT added" bash -c "! grep -q 'nonexistent' '$T/scn/aider.args.2' && ! grep -q 'other.py' '$T/scn/aider.args.2'"
t "A5 attempt 1 did NOT have them (they were only the architect's request)" bash -c "$(declare -f has_arg); T='$T'; ! has_arg --file backend/app/svc.py 1"
t "A6 the retry prompt says the files are in the chat and not to ask again" bash -c "grep -q 'THE FILES YOU ASKED FOR ARE NOW IN THE CHAT' '$T/scn/aider.args.2'"
t "A7 a file_feed event is journaled and the step then PASSes on attempt 2" bash -c "grep -q '\"event\":\"file_feed\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'step 0 PASS (att 2' '$T/out.txt'"
osr_cleanup

echo "== B: a multifile:no item gets them READ-ONLY (cannot trip the scope guard)"
setup "$ITEM_MF"; run
t "B1 attempt 2's argv has --read backend/app/svc.py and NOT --file" bash -c "$(declare -f has_arg); T='$T'; has_arg --read backend/app/svc.py 2 && ! has_arg --file backend/app/svc.py 2"
osr_cleanup

echo "== C: at most 3 files per step"
setup
for i in 1 2 3 4 5; do osr_tracked backend/app/mod$i.py "# m$i\n"; done
osr_aider 1 "$(ask 'echo " 1 backend/app/mod1.py"' 'echo " 2 backend/app/mod2.py"' 'echo " 3 backend/app/mod3.py"' 'echo " 4 backend/app/mod4.py"' 'echo " 5 backend/app/mod5.py"')"
run
t "C1 exactly 3 files are fed (mod1..mod3), mod4/mod5 are not" bash -c "$(declare -f has_arg); T='$T'; has_arg --file backend/app/mod1.py 2 && has_arg --file backend/app/mod2.py 2 && has_arg --file backend/app/mod3.py 2 && ! grep -q 'mod4\|mod5' '$T/scn/aider.args.2'"
osr_cleanup

echo "== D: validation - denylisted, hard-banned, vendored, .md, oversize and already-loaded paths are never fed"
setup
osr_tracked vendor/lib.py "# v\n"; osr_tracked .queue-hard-banned-files "backend/app/banned.py\n"; osr_tracked backend/app/banned.py "# b\n"
osr_tracked backend/app/big.py "$(printf '# %0200d\n' 0)"; osr_tracked notes.md "# n\n"
osr_aider 1 "$(ask 'echo " 1 vendor/lib.py"' 'echo " 2 backend/app/banned.py"' 'echo " 3 notes.md"' 'echo " 4 backend/app/big.py"' 'echo " 5 AGENTS.md"' 'echo " 6 backend/app/foo.py"' 'echo " 7 backend/app/svc.py"')"
OVN_STAGE_FILE_FEED_MAX_BYTES=100 run
t "D1 only svc.py is fed (vendor, banned, .md, oversize, AGENTS.md denied; foo.py is the step's own declared file)" bash -c "$(declare -f has_arg); T='$T'; has_arg --file backend/app/svc.py 2 && ! grep -qE 'vendor/lib.py|banned.py|notes.md|big.py' '$T/scn/aider.args.2' && [ \"\$(grep -c '^backend/app/foo.py\$' '$T/scn/aider.args.2')\" = 1 ]"
osr_cleanup

echo "== E: suffix resolution - a path relative to a sub-package resolves to the unique tracked file"
setup
osr_aider 1 "$(ask 'echo " 1 app/svc.py"')"
run
t "E1 'app/svc.py' resolves to backend/app/svc.py" bash -c "$(declare -f has_arg); T='$T'; has_arg --file backend/app/svc.py 2"
osr_cleanup

echo "== F: control and kill switch"
setup; osr_aider 1 'echo "I looked at it, nothing to change"'
run
t "F1 a no-edit WITHOUT a file request feeds nothing" bash -c "! grep -q 'file-feed' '$T/out.txt' && ! grep -q 'THE FILES YOU ASKED' '$T/scn/aider.args.2'"
osr_cleanup
setup; OVN_STAGE_FILE_FEED=off run
t "F2 OVN_STAGE_FILE_FEED=off: the request is ignored exactly as before" bash -c "! grep -q 'file-feed' '$T/out.txt' && ! grep -q 'svc.py' '$T/scn/aider.args.2'"
osr_cleanup
osr_summary
