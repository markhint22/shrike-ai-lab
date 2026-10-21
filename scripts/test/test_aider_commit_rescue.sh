#!/usr/bin/env bash
# 2026-10-20: aider crashes while committing an already-applied edit ("Unable to commit: ... NoneType"); the BUILD-GATE fix-up then read 'HEAD unchanged' as 'made no change' and the
# correct repair was lost (xlite 20261020-181928, 6 task logs / 4 days). ovn_aider_commit_rescue commits the TRACKED edit only when the crash signature is in the fresh log segment.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
pass=0; fail=0
ok(){ if [ "$2" = 1 ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }
TMPS=()
cleanup(){ local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && safe_rm_rf "$d" >/dev/null 2>&1; done; }
trap cleanup EXIT
LIB="$HERE/../lib_fixup.sh"
mk(){ local d; d="$(safe_mktemp_dir)" || exit 1; TMPS+=("$d"); git -C "$d" init -q; echo "a=1" > "$d/f.py"; git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -qm base; printf '%s' "$d"; }
G(){ git -c user.email=t@t -c user.name=t "$@"; }
run(){ # $1=repo $2=log-text-after-offset $3=mutant lib(optional) ; edit file, then call rescue
  local d="$1" lib="${3:-$LIB}"
  ( cd "$d" && . "$lib" && git() { command git -c user.email=t@t -c user.name=t "$@"; } && B="$(command git rev-parse HEAD)" && : > "$d/task.log" && echo "pre-existing log line" > "$d/task.log" && off=$(wc -c < "$d/task.log" | tr -d ' ') && printf '%s\n' "$2" >> "$d/task.log" && echo "a=2" > "$d/f.py" && ovn_aider_commit_rescue "$B" "$d/task.log" "$off" "rescued" )
}
echo "== rescue"
D1="$(mk)"; run "$D1" "unsupported operand type(s) for +: 'NoneType' and 'str'
Unable to commit: unsupported operand type(s) for /: 'PosixPath' and 'NoneType'"
t "1 crash signature + dirty tracked file -> committed (HEAD moved)" bash -c "[ \"\$(git -C '$D1' log --oneline | wc -l | tr -d ' ')\" = 2 ] && git -C '$D1' show HEAD:f.py | grep -q 'a=2'"
t "2 a marker line is written for the alert/audit trail" grep -q "aider-crash" "$D1/task.log"
D2="$(mk)"; run "$D2" "Applied edit to f.py"; rc=$?
t "3 NO crash signature -> not rescued (an honest no-op stays a no-op)" bash -c "[ $rc -ne 0 ] && [ \"\$(git -C '$D2' log --oneline | wc -l | tr -d ' ')\" = 1 ]"
D3="$(mk)"; ( cd "$D3" && . "$LIB" && B="$(git rev-parse HEAD)" && echo "x" > "$D3/task.log" && echo "Unable to commit: boom" >> "$D3/task.log" && ovn_aider_commit_rescue "$B" "$D3/task.log" 0 m ); rc3=$?
t "4 crash signature but NOTHING modified -> rc 1, no empty commit" bash -c "[ $rc3 -ne 0 ] && [ \"\$(git -C '$D3' log --oneline | wc -l | tr -d ' ')\" = 1 ]"
D4="$(mk)"; echo "junk" > "$D4/untracked.txt"; ( cd "$D4" && . "$LIB" && B="$(git rev-parse HEAD)" && echo "Unable to commit: boom" > "$D4/task.log" && ovn_aider_commit_rescue "$B" "$D4/task.log" 0 m ); rc4=$?
t "5 untracked files alone are never committed" bash -c "[ $rc4 -ne 0 ] && ! git -C '$D4' ls-files | grep -q untracked"
D5="$(mk)"; ( cd "$D5" && export OVN_AIDER_COMMIT_RESCUE=off && echo "a=3" > f.py && echo "Unable to commit: boom" > task.log && . "$LIB" && ovn_aider_commit_rescue "$(git rev-parse HEAD)" "$D5/task.log" 0 m ); rc5=$?
t "6 OVN_AIDER_COMMIT_RESCUE=off disables it" [ $rc5 -ne 0 ]
D6="$(mk)"; ( cd "$D6" && . "$LIB" && echo "a=4" > f.py && echo "old: Unable to commit: boom" > task.log && off=$(wc -c < task.log | tr -d ' ') && echo "clean run" >> task.log && ovn_aider_commit_rescue "$(git rev-parse HEAD)" "$D6/task.log" "$off" m ); rc6=$?
t "7 a crash signature from BEFORE the offset (an earlier step) is ignored" [ $rc6 -ne 0 ]
MUT="$(safe_mktemp_dir)"; TMPS+=("$MUT")
python3 - "$LIB" "$MUT/lib_mut.sh" <<'PY'
import sys; s=open(sys.argv[1]).read()
a="  tail -c +\"$((off + 1))\" \"$log\" 2>/dev/null | grep -qE"
assert a in s
s=s.replace(a,"  true || tail -c +\"$((off + 1))\" \"$log\" 2>/dev/null | grep -qE"); open(sys.argv[2],'w').write(s)
PY
D7="$(mk)"; run "$D7" "Applied edit to f.py" "$MUT/lib_mut.sh"; rcm=$?
t "8 MUTANT (signature check removed) is caught: test 3 shape now commits" bash -c "[ $rcm -eq 0 ]"
t "9 run_overnight.sh wires the rescue into the BUILD-GATE fix-up and parses" bash -c "grep -q 'ovn_aider_commit_rescue \"\$AFTER_SHA\"' '$HERE/../../run_overnight.sh' && bash -n '$HERE/../../run_overnight.sh'"
echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
