#!/usr/bin/env bash
# Regression test (package reconcile-llm-resolve-gate, part B, 2026-10-13): a hygiene gate that failed on HOST STORAGE EXHAUSTION is not a red gate.
# 10-13 15:00: two concurrent full run_all.sh runs exhausted the box's 1M-inode /tmp tmpfs; gitlark's `npm build` died in 1 s, shrike-notify's pytest gate printed 38x
# "OSError: could not create numbered dir with prefix ... in /tmp/pytest-of-<user>/pytest-523 after 10 tries" (pytest's tmp_path - the literal ENOSPC text never reaches the
# output) and test-automation-agent/xlite logged "could not create worktree" - all scored as RED gates / stuck flags / repo blame although no code was at fault.
# Runs the REAL branch_hygiene.sh against a fixture repo with a stub pytest as the gate. Asserts: infra output -> 'gate-infra-skip', no streak step, no review flag, neutral report
# line, nothing merged; a genuine red is STILL red (streak 1, flag, 'gate FAILED'); the consecutive-skip budget stops a real red from hiding for good; the kill switch
# (OVN_HYG_INFRA_SKIP=off) restores the old scoring; a /tmp that cannot create a dir (npm/docker gates whose output is discarded) is detected by the probe; worktree-add failures
# carrying the signature skip too while other worktree failures still flag. bash 5 / GNU (flock, timeout) suite: run on the box or with Homebrew bash.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ_SRC="$HERE/../.."; [ -f "$OQ_SRC/branch_hygiene.sh" ] || OQ_SRC="$HERE/.."
# cannot run on this host -> exit 77 (NOT RUN): run_all.sh counts it and reports it, never a silent green (2026-10-14)
[ -f "$OQ_SRC/branch_hygiene.sh" ] || { echo "  NOT RUN: branch_hygiene.sh not found"; exit 77; }
for t in flock timeout git; do type -P $t >/dev/null || { echo "  NOT RUN: no $t (suite needs it)"; exit 77; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  NOT RUN: needs bash >= 4"; exit 77; }
# shellcheck source=./ntfy_guard.sh
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T
cleanup(){ rm -rf "$T" /tmp/hygiene-app.* /tmp/hygiene-main-app.* /tmp/hygiene-app-retry.* 2>/dev/null; }
trap cleanup EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset OVN_HYG_INFRA_SKIP OVN_HYG_INFRA_SKIP_MAX OVN_HYG_STREAK_ALERT HYGIENE_GATE_ONLY DRY_RUN HYGIENE_FEATURE_BRANCH
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"; BIN="$T/bin"
mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs" "$BIN" "$HOME/qa-venv/bin"
cp "$OQ_SRC/branch_hygiene.sh" "$Q/"
for f in lib_lock.sh lib_pytest_parallel.sh lib_gut_xml.sh lib_tree_guard.sh; do [ -f "$OQ_SRC/scripts/$f" ] && cp "$OQ_SRC/scripts/$f" "$Q/scripts/"; done
REAL_MKTEMP="$(type -P mktemp)"; REAL_GIT="$(type -P git)"; export REAL_MKTEMP REAL_GIT
# mktemp shim: INFRA_PROBE_FAIL=1 makes ONLY the hygiene infra probe's mktemp fail (what a full /tmp does), everything else is the real mktemp
printf '#!/usr/bin/env bash\ncase "$*" in *hyg-infra-probe*) [ "${INFRA_PROBE_FAIL:-0}" = 1 ] && { echo "mktemp: failed to create directory: No space left on device" >&2; exit 1; };; esac\nexec "$REAL_MKTEMP" "$@"\n' > "$BIN/mktemp"
# git shim: WT_FAIL=enospc|plain makes `worktree add` fail (with / without the storage signature); WT_FAIL=main / retry fail ONLY the main-branch / timeout-retry worktree add
printf '#!/usr/bin/env bash\ncase "$*" in *"worktree add"*) case "${WT_FAIL:-}" in main) case "$*" in *hygiene-main-*) echo "fatal: simulated main worktree failure" >&2; exit 128;; esac;; retry) case "$*" in *-retry.*) echo "fatal: simulated retry worktree failure" >&2; exit 128;; esac;; enospc) echo "fatal: could not create leading directories of /tmp/x: No space left on device" >&2; exit 128;; plain) echo "fatal: simulated unrelated failure" >&2; exit 128;; esac;; esac\nexec "$REAL_GIT" "$@"\n' > "$BIN/git"
chmod +x "$BIN/mktemp" "$BIN/git"
# stub pytest = the repo's gate; its behaviour is whatever $T/mode says
PYTEST_BODY='case "$(cat "$T/mode" 2>/dev/null)" in
  numdir) echo "E   OSError: could not create numbered dir with prefix test_x in /tmp/pytest-of-u/pytest-523 after 10 tries"; echo "38 errors"; exit 1;;
  enospc) echo "OSError: [Errno 28] No space left on device: /tmp/x"; echo "1 error"; exit 1;;
  plain)  echo "boom: something unrelated broke"; exit 1;;
  red)    echo "FAILED tests/test_x.py::test_y - assert 1 == 2"; echo "1 failed"; exit 1;;
  enospcword) echo "tests/test_fs.py::test_handles_ENOSPC_gracefully FAILED - assert 1 == 2"; echo "1 failed"; exit 1;;
  timeout) echo "killed by the timeout wrapper"; exit 124;;
  *)      echo ". passed"; exit 0;;
esac'

mk(){   # fresh fixture: main == develop, overnight/feature = develop + 1 commit; clone on overnight/feature with the stub pytest
  local o="$T/origin/app.git" s="$T/seed/app"
  rm -rf "$o" "$s" "${Q:?}/repos/app" "${Q:?}/state" "${T:?}/report.md"; mkdir -p "$T/origin" "$T/seed" "$Q/state"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main; git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature; echo feat > feat.txt; git add -A; git commit -q -m "feat: work"; git push -q origin overnight/feature )
  git clone -q "$o" "$Q/repos/app" 2>/dev/null; git -C "$Q/repos/app" checkout -q overnight/feature
  mkdir -p "$Q/repos/app/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$Q/repos/app/.venv/bin/pytest"; chmod +x "$Q/repos/app/.venv/bin/pytest"
}
sha(){ git -C "$T/origin/app.git" rev-parse --verify -q "$1" 2>/dev/null; true; }
run(){ ( cd "$Q" && HYGIENE_MERGE_TARGET=develop REPORT_FILE="$T/report.md" PATH="$BIN:$PATH" bash ./branch_hygiene.sh repos/app > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
OUT="$T/out.log"; REP="$T/report.md"; ST="$Q/state"
STREAK="$ST/hygiene_gate_streak/app__overnight_feature"; FLAG="$ST/branch_hygiene_review_app"; CNT="$ST/hygiene_infra_skip/app__overnight_feature"
streak_n(){ [ -f "$STREAK" ] && cut -d' ' -f1 "$STREAK" || echo 0; }

# ===== A: infra output is SKIPPED, unscored =====
for m in numdir enospc; do
  mk; d0="$(sha develop)"; echo "$m" > "$T/mode"; run
  ok "A($m)1: logged as gate-infra-skip" "$([ "$(has $OUT 'gate-infra-skip')" = 1 ] && echo 1 || echo 0)"
  ok "A($m)2: NOT logged as 'gate FAILED' / flagged for review" "$([ "$(has $OUT 'gate FAILED')" = 0 ] && [ "$(has $OUT 'flagged for review')" = 0 ] && echo 1 || echo 0)"
  ok "A($m)3: no red-streak state written (no increment)" "$([ ! -e "$STREAK" ] && echo 1 || echo 0)"
  ok "A($m)4: no stuck/review flag written" "$([ ! -e "$FLAG" ] && echo 1 || echo 0)"
  ok "A($m)5: neutral report line, no 'needs review' repo blame" "$([ "$(has $REP 'gate skipped (host infra')" = 1 ] && [ "$(has $REP 'needs review')" = 0 ] && echo 1 || echo 0)"
  ok "A($m)6: nothing merged, develop untouched" "$([ "$(sha develop)" = "$d0" ] && echo 1 || echo 0)"
  ok "A($m)7: the skip is counted (1)" "$([ "$(cat $CNT 2>/dev/null)" = 1 ] && echo 1 || echo 0)"
  ok "A($m)8: the pass completes normally (no crash on the skip path)" "$([ "$(has $OUT 'branch hygiene complete')" = 1 ] && echo 1 || echo 0)"
done

# ===== B: a GENUINE red is still red =====
mk; echo red > "$T/mode"; run
ok "B1: 'gate FAILED' logged and the repo flagged" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ -s "$FLAG" ] && [ "$(has $OUT 'gate-infra-skip')" = 0 ] && echo 1 || echo 0)"
ok "B2: the red streak advanced to 1" "$([ "$(streak_n)" = 1 ] && echo 1 || echo 0)"
ok "B3: red report line blames the repo as before" "$([ "$(has $REP 'needs review')" = 1 ] && echo 1 || echo 0)"
ok "B4: no infra-skip counter for a real red" "$([ ! -e "$CNT" ] && echo 1 || echo 0)"
run
ok "B5: the second consecutive red advances the streak to 2" "$([ "$(streak_n)" = 2 ] && echo 1 || echo 0)"

# ===== C: infra passes in BETWEEN real reds neither add to nor reset the streak; a real result resets the skip counter =====
echo numdir > "$T/mode"; run
ok "C1: an infra pass leaves the red streak at 2 (no increment, no reset)" "$([ "$(streak_n)" = 2 ] && [ -f "$FLAG" ] && echo 1 || echo 0)"
ok "C2: ...and keeps the existing review flag untouched" "$([ "$(has $FLAG 'gate FAILED')" = 1 ] && echo 1 || echo 0)"
echo red > "$T/mode"; run
ok "C3: the next real red resets the infra-skip counter and advances the streak to 3" "$([ ! -e "$CNT" ] && [ "$(streak_n)" = 3 ] && echo 1 || echo 0)"

# ===== D: the skip BUDGET (OVN_HYG_INFRA_SKIP_MAX=3 consecutive) - a real red that merely prints the phrase cannot hide forever =====
mk; echo numdir > "$T/mode"; run; run; run
ok "D1: three consecutive infra passes are all skipped (counter 3, no streak)" "$([ "$(cat $CNT 2>/dev/null)" = 3 ] && [ ! -e "$STREAK" ] && [ ! -e "$FLAG" ] && echo 1 || echo 0)"
run
ok "D2: the 4th consecutive one is scored RED (budget exhausted, logged)" "$([ "$(has $OUT 'gate-infra-skip budget exhausted')" = 1 ] && [ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(streak_n)" = 1 ] && [ -s "$FLAG" ] && echo 1 || echo 0)"
mk; echo numdir > "$T/mode"; OVN_HYG_INFRA_SKIP_MAX=1 run; OVN_HYG_INFRA_SKIP_MAX=1 run
ok "D3: OVN_HYG_INFRA_SKIP_MAX=1 -> the 2nd consecutive is already scored" "$([ "$(streak_n)" = 1 ] && echo 1 || echo 0)"

# ===== E: infra skip then GREEN: the counter resets and the merge goes through =====
mk; echo numdir > "$T/mode"; run; echo green > "$T/mode"; run
ok "E1: green after an infra skip merges to develop" "$([ "$(has $OUT 'MERGED app')" = 1 ] && git -C $T/origin/app.git merge-base --is-ancestor overnight/feature develop && echo 1 || echo 0)"
ok "E2: the skip counter was reset by the real (green) result" "$([ ! -e "$CNT" ] && echo 1 || echo 0)"

# ===== F: kill switch OVN_HYG_INFRA_SKIP=off restores the old scoring =====
mk; echo numdir > "$T/mode"; OVN_HYG_INFRA_SKIP=off run
ok "F1: with the switch off the same output is a red gate again (old behaviour)" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(has $OUT 'gate-infra-skip')" = 0 ] && [ "$(streak_n)" = 1 ] && [ -s "$FLAG" ] && echo 1 || echo 0)"

# ===== G: /tmp cannot create a dir (npm/docker gates discard their output): the PROBE classifies a plain failure as infra =====
mk; echo plain > "$T/mode"; INFRA_PROBE_FAIL=1 run
ok "G1: plain failure + failing /tmp probe -> gate-infra-skip, unscored, unflagged" "$([ "$(has $OUT 'gate-infra-skip')" = 1 ] && [ ! -e "$STREAK" ] && [ ! -e "$FLAG" ] && echo 1 || echo 0)"
mk; echo plain > "$T/mode"; run
ok "G2: the same plain failure with a healthy /tmp is red (probe only fires on real exhaustion)" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(streak_n)" = 1 ] && echo 1 || echo 0)"

# ===== H: worktree creation failures =====
mk; echo green > "$T/mode"; WT_FAIL=enospc run
ok "H1: 'could not create worktree' with the storage signature -> gate-infra-skip, NO review flag" "$([ "$(has $OUT 'gate-infra-skip: could not create worktree')" = 1 ] && [ ! -e "$FLAG" ] && [ "$(has $REP 'could not create worktree')" = 1 ] && [ "$(has $REP 'worktree failed')" = 0 ] && echo 1 || echo 0)"
ok "H2: no leaked /tmp/hygiene-app.* dir" "$([ -z "$(ls -d /tmp/hygiene-app.* 2>/dev/null)" ] && echo 1 || echo 0)"
mk; echo green > "$T/mode"; WT_FAIL=plain run
ok "H3: an unrelated worktree failure is still flagged exactly as before" "$([ "$(has $OUT 'could not create worktree — flagging')" = 1 ] && [ -s "$FLAG" ] && [ "$(has $REP 'worktree failed')" = 1 ] && echo 1 || echo 0)"
mk; echo green > "$T/mode"; WT_FAIL=plain INFRA_PROBE_FAIL=1 run
ok "H4: ...unless /tmp itself cannot create a dir (probe) - then it is infra" "$([ "$(has $OUT 'gate-infra-skip: could not create worktree')" = 1 ] && [ ! -e "$FLAG" ] && echo 1 || echo 0)"

# ===== I: a REAL red that merely mentions the bare token ENOSPC (a repo test about it) is NOT infra - the bare token was dropped from the signature list =====
mk; echo enospcword > "$T/mode"; run
ok "I1: output containing only 'ENOSPC' (test name) is scored red: 'gate FAILED', flagged, streak 1, no infra skip" "$([ "$(has $OUT 'gate FAILED')" = 1 ] && [ "$(has $OUT 'gate-infra-skip')" = 0 ] && [ -s "$FLAG" ] && [ "$(streak_n)" = 1 ] && [ ! -e "$CNT" ] && echo 1 || echo 0)"
# ...while the real phrases of the same class (node: 'ENOSPC: no space left on device') are still caught via the phrase
mk; echo plain > "$T/mode"; printf '#!/usr/bin/env bash\necho "Error: ENOSPC: no space left on device, write"; exit 1\n' > "$Q/repos/app/.venv/bin/pytest"; run
ok "I2: node-style 'ENOSPC: no space left on device' is still an infra skip (matched by the phrase)" "$([ "$(has $OUT 'gate-infra-skip')" = 1 ] && [ ! -e "$STREAK" ] && echo 1 || echo 0)"

# ===== J: failed worktree adds never leak their mktemp dir =====
mk; echo green > "$T/mode"; rm -rf /tmp/hygiene-main-app.* 2>/dev/null; WT_FAIL=main run
ok "J1: the main worktree add fails -> flagged as before ('main worktree failed')" "$([ "$(has $OUT 'could not create main worktree')" = 1 ] && [ "$(has $FLAG 'main worktree failed')" = 1 ] && echo 1 || echo 0)"
ok "J2: ...and NO /tmp/hygiene-main-app.* mktemp dir is left behind" "$([ -z "$(ls -d /tmp/hygiene-main-app.* 2>/dev/null)" ] && echo 1 || echo 0)"
mk; echo timeout > "$T/mode"; rm -rf /tmp/hygiene-app-retry.* 2>/dev/null; WT_FAIL=retry run
ok "J3: the timeout-retry worktree add fails -> the pass completes" "$([ "$(has $OUT 'retrying once with a fresh worktree')" = 1 ] && [ "$(has $OUT 'branch hygiene complete')" = 1 ] && echo 1 || echo 0)"
ok "J4: ...and NO /tmp/hygiene-app-retry.* mktemp dir is left behind (pre-existing leak: 60 empty dirs on the box)" "$([ -z "$(ls -d /tmp/hygiene-app-retry.* 2>/dev/null)" ] && echo 1 || echo 0)"

echo "$P passed, $F failed"
[ "$F" -eq 0 ] && echo "  test_hygiene_infra_skip: PASS" || echo "  test_hygiene_infra_skip: FAIL"
[ "$F" -eq 0 ]
