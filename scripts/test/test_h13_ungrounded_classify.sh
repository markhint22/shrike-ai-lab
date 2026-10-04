#!/usr/bin/env bash
# test_h13_ungrounded_classify.sh - 2026-10-04 (h13 tasks 4 + 5).
#  4. no-op(ungrounded-plan) (scout PROCEED, FILES: NONE, for items whose path is '.'/'tests') is benign, not a scored flail (record_outcome +
#     ovn_outcome_buckets.py); ovn_item_guard.sh parks the whole [feat:] sibling group after N (default 3) CONSECUTIVE hits; the vague sanitizer
#     retires '.'/'tests' items with no concrete file (covered with the sanitizer in test_h13_delete_already_gone.sh).
#  5. ovn_classify.py lang_of() answers 'unknown' (not 'other'/build-verified) for non-path tokens; ovn_stats.py leaves 'unknown' out of the
#     per-language pass-rate rows.
# Each behaviour has a NEGATIVE control (a real flail stays bad / a real path is classified / streak reset keeps siblings) and a BENIGN control.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
b(){ [ "$1" = "$2" ] && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# ------------------------------------------------------------ outcome buckets (python)
B="$T/b.py"; cat > "$B" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = lambda **k: m.bucket_from_outcome_row(k)
print(r(**{"class": "noop", "status": "no-op(ungrounded-plan)"}))                      # legacy row w/o severity
print(r(**{"class": "noop", "status": "no-op"}))                                       # real flail
print(r(**{"class": "noop", "status": "no-op(ALREADY-DONE)"}))
print(r(**{"class": "noop", "status": "no-op(ungrounded-plan)", "severity": "neutral"}))
print(r(**{"class": "noop", "status": "no-op", "severity": "bad"}))
PY
OB="$(python3 "$B" "$Q/scripts/ovn_outcome_buckets.py" | tr '\n' ' ')"
ok "buckets: ungrounded-plan (no severity) => benign, bare no-op still bad, already-done benign, severity rows unchanged" "$(b "$OB" 'benign bad benign benign bad ')"

# ------------------------------------------------------------ record_outcome severity
R="$Q/run_overnight.sh"
eval "$(sed -n '/^record_outcome(/,/^}/p' "$R")"
SCRIPT_DIR="$Q"; STATE_DIR="$T/st"; mkdir -p "$STATE_DIR"
sev_of(){ : > "$STATE_DIR/outcomes.jsonl"; record_outcome "$2" repo "$1" "" aider_fix 1 /dev/null; grep -o '"severity":"[a-z]*"' "$STATE_DIR/outcomes.jsonl" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/'; }
cls_of(){ : > "$STATE_DIR/outcomes.jsonl"; record_outcome "$2" repo "$1" "" aider_fix 1 /dev/null; grep -o '"class":"[a-z]*"' "$STATE_DIR/outcomes.jsonl" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/'; }
ok "record_outcome: no-op(ungrounded-plan) => severity neutral" "$(b "$(sev_of 'no-op(ungrounded-plan)' u1)" neutral)"
ok "record_outcome: ... class stays noop" "$(b "$(cls_of 'no-op(ungrounded-plan)' u2)" noop)"
ok "record_outcome NEG: a bare no-op (real flail) is still severity bad" "$(b "$(sev_of 'no-op' u3)" bad)"
ok "record_outcome NEG: no-op(reverted-red) is still bad-class" "$(b "$(sev_of 'no-op(reverted-red)' u4)" bad)"

# ------------------------------------------------------------ item guard: sibling-group park
G="$Q/scripts/ovn_item_guard.sh"
mk(){  # name content -> repo dir
  local r="$T/$1"; mkdir -p "$r"; ( cd "$r" && git init -q -b main && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); echo "$r"; }
guard(){ OVN_SCHEMA_BUDGET=off bash "$G" "$1" "$2" "$3" ugid >/dev/null 2>&1; }
GROUP='- [ ] [T4] . — Execute full test suite. VERIFY: `godot -s x.gd` exits 0. [feat:xlite-20261003-dead-code-a]
- [ ] [T4] tests — Run all again. VERIFY: `godot -s y.gd` exits 0. [feat:xlite-20261003-dead-code-a]
- [ ] [T3] scripts/z.gd — a sibling with a file. [feat:xlite-20261003-dead-code-a]
- [ ] [T3] scripts/other.gd — an unrelated feature. [feat:xlite-20261003-other]'
r="$(mk g1 "$GROUP")"; st="$T/s1"; mkdir -p "$st"
guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"
ok "guard: after 2 consecutive hits nothing is parked yet (below the group cap of 3)" "$(b "$(grep -c AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md")" 0)"
guard "$r" 'no-op(ungrounded-plan)' "$st"
ok "guard: the 3rd consecutive hit parks the open ungrounded-shaped siblings of the feature group (2: '.' and 'tests')" "$(b "$(grep -c 'AUTO-SKIP ungrounded-plan x3' "$r/OVERNIGHT_PROGRESS.md")" 2)"
ok "guard NEG: a sibling that names a REAL file is NOT parked (3 unlucky scouts do not make it ungrounded)" "$(grep -q '^- \[ \] \[T3\] scripts/z.gd' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "guard NEG: the unrelated feature's item is NOT parked" "$(grep -q '^- \[ \] \[T3\] scripts/other.gd' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "guard: parked items stay UNCHECKED (reversible) and the park is committed" "$(grep -c '^- \[ \] \[AUTO-SKIP ungrounded-plan' "$r/OVERNIGHT_PROGRESS.md" | grep -qx 2 && git -C "$r" log --format=%s -1 | grep -q 'park 2 sibling' && echo 1 || echo 0)"

r="$(mk g2 "$GROUP")"; st="$T/s2"; mkdir -p "$st"
guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"
ok "guard NEG: a non-consecutive hit (another outcome in between) resets the streak - no group park" "$(b "$(grep -c 'AUTO-SKIP ungrounded-plan' "$r/OVERNIGHT_PROGRESS.md")" 0)"

r="$(mk g3 '- [ ] [T4] . — Execute full test suite. VERIFY: `x`
- [ ] [T3] scripts/z.gd — another thing.')"; st="$T/s3"; mkdir -p "$st"
guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"
ok "guard BENIGN: an item with no [feat:] group is not group-parked (ordinary no-op streak applies)" "$(b "$(grep -c 'AUTO-SKIP ungrounded-plan' "$r/OVERNIGHT_PROGRESS.md")" 0)"

r="$(mk g4 "$GROUP")"; st="$T/s4"; mkdir -p "$st"
for i in 1 2 3; do guard "$r" 'no-op' "$st"; done
ok "guard BENIGN: ordinary bare no-ops never trigger the group park (cap 4 unchanged, 3 hits parks nothing)" "$(b "$(grep -c 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md")" 0)"

# review hardening: a LANDING of the feature breaks the streak (consecutive), and a delete-executor credit is not billed to the next item
r="$(mk g5 "$GROUP")"; st="$T/s5"; mkdir -p "$st"
LOGL="$T/landlog"; : > "$LOGL"
guard "$r" 'no-op(ungrounded-plan)' "$st"; guard "$r" 'no-op(ungrounded-plan)' "$st"
ls "$st/item_fails" | grep -q ungrounded && printf 'item-hash %s\n' "$(ls "$st/item_fails" | grep ungrounded | sed -E 's/^ugid\.([0-9a-f]{32})\..*/\1/')" > "$LOGL"
OVN_SCHEMA_BUDGET=off bash "$G" "$r" 'pushed(tests:pass)' "$st" ugid "$LOGL" >/dev/null 2>&1
guard "$r" 'no-op(ungrounded-plan)' "$st"
ok "guard NEG: ungrounded, ungrounded, LANDING, ungrounded => no group park (landing resets the streak)" "$(b "$(grep -c 'AUTO-SKIP ungrounded-plan' "$r/OVERNIGHT_PROGRESS.md")" 0)"
r="$(mk g6 "$GROUP")"; st="$T/s6"; mkdir -p "$st"; GL="$T/gonelog"; echo '--- DELETE-EXECUTOR: scripts/x.gd is already gone (deleted earlier) - crediting the item ---' > "$GL"
for i in 1 2 3 4 5; do OVN_SCHEMA_BUDGET=off bash "$G" "$r" 'no-op(ALREADY-DONE)' "$st" ugid "$GL" >/dev/null 2>&1; done
ok "guard: executor-credited ALREADY-GONE no-ops are not billed to the next open item (5 in a row park nothing)" "$(b "$(grep -c 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md")" 0)"
r="$(mk g7 "$GROUP")"; st="$T/s7"; mkdir -p "$st"; : > "$T/plainlog"
for i in 1 2 3 4 5; do OVN_SCHEMA_BUDGET=off bash "$G" "$r" 'no-op(ALREADY-DONE)' "$st" ugid "$T/plainlog" >/dev/null 2>&1; done
ok "guard BENIGN: ordinary repeated ALREADY-DONE no-ops (no executor credit marker) still walk the no-op cap" "$(grep -q 'AUTO-SKIP after' "$r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"

# ------------------------------------------------------------ classifier
C="$Q/scripts/ovn_classify.py"
cl(){ python3 "$C" "$1"; }
ok "classify: 'none' => lang unknown, verif unknown (no longer other/build-verified)" "$(b "$(cl 'none')" 'unknown other T2 unknown ')"
ok "classify: dotted symbol sympy.isprime => unknown" "$(cl 'use sympy.isprime here' | grep -q '^unknown ' && echo 1 || echo 0)"
ok "classify: dotted module app.services.cache => unknown" "$(cl 'cache in app.services.cache' | grep -q '^unknown ' && echo 1 || echo 0)"
ok "classify BENIGN: a real python path is unchanged" "$(b "$(cl 'fix app/services/cache.py now' | cut -d' ' -f1,4,5)" 'py test-covered app/services/cache.py')"
ok "classify BENIGN: a real gdscript path is unchanged" "$(cl 'fix scripts/battle/x.gd' | grep -q '^gdscript ' && echo 1 || echo 0)"

# ------------------------------------------------------------ ovn_stats: unknown excluded from the per-language rows
H="$T/home"; mkdir -p "$H/overnight-queue/state"; LOG="$H/overnight-queue/state/task_stats.log"; NOW="$(date +%s)"
row(){ printf '%s\t%s\t%s\t%s\t%s\n' "$((NOW-$1))" "$2" "$3" "$4" "$5"; }
{ row 100 r pass '{py·fix·T2·test-covered}' a.py; row 110 r pass '{py·fix·T2·test-covered}' b.py; row 120 r revert '{py·fix·T2·test-covered}' c.py
  for i in 1 2 3 4 5 6; do row $((130+i)) r noop:flail '{unknown·other·T2·unknown}' none; done; } > "$LOG"
SO="$(HOME="$H" python3 "$Q/scripts/ovn_stats.py" 2>&1)"
LANGSEC="$(printf '%s\n' "$SO" | sed -n '/^BY LANGUAGE:/,/^$/p')"
ok "stats: LANGUAGE table has the py row" "$(printf '%s' "$LANGSEC" | grep -q '^  py ' && echo 1 || echo 0)"
ok "stats NEG: no 'unknown' (formerly 'other') pass-rate row in the LANGUAGE table" "$(! printf '%s' "$LANGSEC" | grep -qE '^  (unknown|other) ' && echo 1 || echo 0)"
ok "stats: the exclusion is labelled (6 attempts with no identifiable file)" "$(printf '%s' "$LANGSEC" | grep -q '(6 attempt(s) with no identifiable file are not in this table)' && echo 1 || echo 0)"
ok "stats BENIGN: the other axes still count those attempts (headline wasted = revert 1 + flail 6)" "$(printf '%s' "$SO" | grep -q 'wasted attempts: 7 (1 revert, 0 gate-reverted, 6 flailed)' && echo 1 || echo 0)"
{ row 100 r pass '{py·fix·T2·test-covered}' a.py; row 110 r revert '{py·fix·T2·test-covered}' c.py; } > "$LOG"
SO2="$(HOME="$H" python3 "$Q/scripts/ovn_stats.py" 2>&1)"
ok "stats BENIGN: no unknown rows => no footnote and the py row is unchanged" "$(printf '%s' "$SO2" | grep -q '^  py ' && ! printf '%s' "$SO2" | grep -q 'no identifiable file' && echo 1 || echo 0)"

echo "test_h13_ungrounded_classify: $P passed, $F failed"
[ "$F" -eq 0 ]
