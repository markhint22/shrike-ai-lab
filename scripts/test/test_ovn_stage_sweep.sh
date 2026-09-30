#!/usr/bin/env bash
# test_ovn_stage_sweep.sh — runs the REAL ovn_stage_sweep.sh in a hermetic fake tree: dedicated-pause handling, the
# GPU-idle drain wait (stub pgrep), Pass 1 (godot items routed to Claude: commit + push incl. the pull-rebase retry),
# Pass 2 (MAX-bounded runner invocation per repo with a doable NON-godot T3+ item; the runner is a stub that records
# its args) and the exit-trap unpause.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT

sw_new(){   # fresh fake tree with stub runner/pgrep/sleep ahead of PATH
  T="$(mktemp -d)"; H="$T/home"; Q="$H/overnight-queue"; mkdir -p "$Q/state" "$Q/logs" "$Q/repos" "$T/bin"
  printf '#!/usr/bin/env bash\necho "$*" >> "$HOME/overnight-queue/state/runner.calls"\nr="$1"\nif grep -qx "$r" "$HOME/overnight-queue/state/runner.fail" 2>/dev/null; then exit 1; fi\nexit 0\n' > "$Q/ovn_stage_runner.sh"
  printf '#!/usr/bin/env bash\nn=$(( $(cat "%s/pg.n" 2>/dev/null || echo 0) + 1 )); echo $n > "%s/pg.n"\n[ "$n" -le "${OSR_PGREP_BUSY:-0}" ] && exit 0; exit 1\n' "$T" "$T" > "$T/bin/pgrep"
  printf '#!/usr/bin/env bash\necho "sleep $*" >> "%s/sleeps"\nexit 0\n' "$T" > "$T/bin/sleep"
  chmod +x "$T/bin/pgrep" "$T/bin/sleep"
}
sw_repo(){  # $1=name, rest=progress lines ; repo with a bare origin on overnight/feature
  local r="$1"; shift; local d="$Q/repos/$r" o="$T/origin-$r.git"
  git init -q --bare "$o"; git init -q "$d"; git -C "$d" checkout -q -b overnight/feature
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  { echo "# Progress"; echo "## Next"; local l; for l in "$@"; do echo "$l"; done; } > "$d/OVERNIGHT_PROGRESS.md"
  git -C "$d" add -A; git -C "$d" commit -q -m seed; git -C "$d" remote add origin "$o"; git -C "$d" push -q origin overnight/feature 2>/dev/null
  cat > "$o/hooks/pre-receive" <<HOOK
#!/bin/sh
if [ -f "$T/reject_once_$r" ]; then rm -f "$T/reject_once_$r"; exit 1; fi
exit 0
HOOK
  chmod +x "$o/hooks/pre-receive"
}
sw_run(){ ( cd "$T" && HOME="$H" PATH="$T/bin:$PATH" bash "$SWEEP" ) > "$T/out.txt" 2>&1 < /dev/null; RC=$?; }
LOGF(){ grep -qF -- "$1" "$Q/logs/ovn_stage_runner.log"; }
ofile(){ git -C "$T/origin-$1.git" show overnight/feature:OVERNIGHT_PROGRESS.md; }

echo "== S1: dedicated sweep, MAX=1"
sw_new
sw_repo gitlark '- [ ] [T3] backend/app/a.py — python thing' '- [ ] [T4] game/x.gd — godot thing' '- [ ] [T3] [AUTO-SKIP old] game/y.gd — already skipped'
sw_repo billwatch '- [ ] [T3] game/z.gd — only godot here' '- [ ] untiered w.gd item' '- [ ] [T3] [BLOCKED] v.gd'
sw_repo test-automation-agent '- [ ] [T3] backend/b.py — python only'
sw_repo shrike-notify '- [x] [T3] backend/done.py'
touch "$T/reject_once_gitlark"       # first escalate push rejected -> pull --rebase + push retry
OSR_PGREP_BUSY=2 sw_run
t "sweep exits 0" test "$RC" = 0
t "drain wait polled pgrep while an aider was busy (2 sleeps)" bash -c "[ \$(grep -c 'sleep 10' '$T/sleeps') = 2 ]"
t "logs: paused for dedicated 27B, then GPU idle" bash -c "grep -qF 'paused fleet for dedicated 27B' '$Q/logs/ovn_stage_runner.log' && grep -qF 'GPU idle (0 aiders), starting dedicated' '$Q/logs/ovn_stage_runner.log'"
t "godot T4 item tagged AUTO-SKIP on origin (push retried after rejection)" bash -c "git -C '$T/origin-gitlark.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[AUTO-SKIP godot(.gd) — 27B measured 0%, route to CLAUDE\] \[T4\] game/x.gd'"
t "python item and already-skipped godot item untouched" bash -c "git -C '$T/origin-gitlark.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[T3\] backend/app/a.py' && git -C '$T/origin-gitlark.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -c 'AUTO-SKIP' | grep -qx 2"
t "commit message counts the routed items" bash -c "git -C '$T/origin-gitlark.git' log --format=%s overnight/feature | grep -q 'route 1 godot(.gd) items to Claude'"
t "routed-count log line written" LOGF "routed 1 godot gitlark items to Claude"
t "billwatch godot item routed too" bash -c "git -C '$T/origin-billwatch.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP godot(.gd).*\[T3\] game/z.gd'"
t "untiered / BLOCKED .gd lines are NOT routed" bash -c "! git -C '$T/origin-billwatch.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep 'untiered w.gd' | grep -q AUTO-SKIP && ! git -C '$T/origin-billwatch.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep 'BLOCKED' | grep -q 'AUTO-SKIP godot'"
t "repo with no .gd item left alone (no commit beyond seed)" bash -c "[ \$(git -C '$T/origin-test-automation-agent.git' log --oneline overnight/feature | wc -l) = 1 ]"
t "Pass 2 (MAX=1): runner invoked once, for the first repo with a doable non-godot T3+ item" bash -c "[ \"\$(cat '$Q/state/runner.calls')\" = gitlark ]"
t "summary line says ran 1 repo (dedicated)" LOGF "stage-sweep ran 1 repo(s) (dedicated)"
t "exit trap cleared the pause it set" bash -c "[ ! -f '$Q/state/PAUSED' ] && [ ! -f '$Q/state/stage_pause_since' ]"
osr_cleanup

echo "== S2: MAX=3, failing runner is not counted; repos without a progress file / doable item skipped"
sw_new
sw_repo gitlark '- [ ] [T3] backend/app/a.py — python thing'
sw_repo billwatch '- [ ] [T3] game/z.gd — only godot'
sw_repo test-automation-agent '- [ ] [T3] backend/b.py — python only'
sw_repo iptv_apps '- [ ] [T5] web/c.vue — frontend'
echo gitlark > "$Q/state/runner.fail"
( cd "$T" && OVN_STAGE_SWEEP_MAX=3 HOME="$H" PATH="$T/bin:$PATH" bash "$SWEEP" ) > "$T/out.txt" 2>&1 < /dev/null; RC=$?
t "runner tried on every repo with a doable non-godot item, in ALL_REPOS order" bash -c "[ \"\$(tr '\n' ' ' < '$Q/state/runner.calls')\" = 'gitlark test-automation-agent iptv_apps ' ]"
t "failed run (gitlark) not counted: done=2" LOGF "stage-sweep ran 2 repo(s)"
t "billwatch (godot only) never run" bash -c "! grep -qx billwatch '$Q/state/runner.calls'"
osr_cleanup

echo "== S3: someone else already paused the fleet / dedicate off"
sw_new
sw_repo gitlark '- [ ] [T3] backend/app/a.py — python thing'
touch "$Q/state/PAUSED"
sw_run
t "pre-existing pause is NOT ours: no 'paused fleet' line" bash -c "! grep -qF 'paused fleet for dedicated' '$Q/logs/ovn_stage_runner.log'"
t "pre-existing pause left in place (not removed by our trap)" test -f "$Q/state/PAUSED"
t "summary has no (dedicated) suffix" bash -c "grep -qF 'stage-sweep ran 1 repo(s)' '$Q/logs/ovn_stage_runner.log' && ! grep -qF '(dedicated)' '$Q/logs/ovn_stage_runner.log'"
osr_cleanup
sw_new
sw_repo gitlark '- [ ] [T3] backend/app/a.py — python thing'
( cd "$T" && OVN_STAGE_DEDICATE=0 HOME="$H" PATH="$T/bin:$PATH" bash "$SWEEP" ) > "$T/out.txt" 2>&1 < /dev/null; RC=$?
t "OVN_STAGE_DEDICATE=0: sweep still runs the repo and exits 0" bash -c "[ $RC = 0 ] && [ \"\$(cat '$Q/state/runner.calls')\" = gitlark ]"
osr_cleanup

echo "== S4: nothing to do"
sw_new
sw_repo gitlark '- [x] [T3] backend/app/a.py — done' '- [ ] [T1] backend/app/easy.py — tier 1'
OSR_PGREP_BUSY=0 sw_run
t "no doable T3+ item anywhere -> runner never invoked, ran 0 repo(s)" bash -c "[ ! -f '$Q/state/runner.calls' ] && grep -qF 'stage-sweep ran 0 repo(s)' '$Q/logs/ovn_stage_runner.log'"
osr_cleanup

osr_summary
