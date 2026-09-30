#!/usr/bin/env bash
# Wave-3c coverage tests: executes the REAL python scripts in place (no copies) for
#   ovn_batch_park_tagger.py, ovn_classify.py, ovn_enqueue_emergency.py, ovn_tag_items.py,
#   ovn_hourly_notable.py, ovn_retire_vague.py
# Hermetic: every fixture lives in a mktemp dir; HOME/TASK_STATS point at temp data.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/.."; [ -f "$D/ovn_classify.py" ] || D="$HERE"
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
eq(){ [ "$2" = "$3" ] && ok "$1" 1 || { ok "$1 (got: $2 | want: $3)" 0; }; }

# ---------------------------------------------------------------- park tagger
PT="$D/ovn_batch_park_tagger.py"
cat > "$T/batch.json" <<'J'
{"repo":"r","tag":"feat-x","landed":1,"n":8,"pct":12,"stragglers":["fix foo.py thing","already done bar.py","other baz.py"]}
J
printf '%s\n' '# Progress' '- [ ] fix foo.py thing' '- [ ] [AUTO-SKIP old] already done bar.py' '- [x] fix foo.py thing' 'plain line' '- [ ] unrelated qux.py' '- [ ] other baz.py' > "$T/p1.md"
out="$(python3 "$PT" "$T/p1.md" "$T/batch.json")"
eq "park tagger prints tagged count 2" "$out" "2"
ok "tagged line carries marker with tag/landed/n/pct" "$(grep -qF -- '- [ ] [AUTO-SKIP batch-graded-F — feat-x landed 1/8 (12%); review] fix foo.py thing' "$T/p1.md" && echo 1 || echo 0)"
ok "second straggler tagged" "$(grep -qF -- 'review] other baz.py' "$T/p1.md" && echo 1 || echo 0)"
ok "already AUTO-SKIP line not double-tagged" "$(grep -c 'AUTO-SKIP' "$T/p1.md" | grep -qx 3 && echo 1 || echo 0)"
ok "checked/unrelated/plain lines untouched" "$(grep -qxF -- '- [x] fix foo.py thing' "$T/p1.md" && grep -qxF -- '- [ ] unrelated qux.py' "$T/p1.md" && grep -qxF 'plain line' "$T/p1.md" && echo 1 || echo 0)"
cp "$T/p1.md" "$T/p1.before"
out="$(python3 "$PT" "$T/p1.md" "$T/batch.json")"
eq "park tagger idempotent: second run prints 0" "$out" "0"
ok "second run leaves the file byte-identical" "$(cmp -s "$T/p1.md" "$T/p1.before" && echo 1 || echo 0)"

# ------------------------------------------------------------------- classify
CL="$D/ovn_classify.py"
eq "CLI plain output" "$(python3 "$CL" 'app/foo.py — replace the bare except with except Exception. One line.')" "py syntax T1 test-covered app/foo.py"
eq "CLI --tag output" "$(python3 "$CL" --tag 'web/src/A.vue — add type="button" to the close button')" '{vue·a11y·T1·test-covered}'
eq "CLI no-file text" "$(python3 "$CL" 'just some vague words')" "other other T2 build-verified "
cat > "$T/cl.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ovn_classify_under_test", sys.argv[1])
C = importlib.util.module_from_spec(spec); spec.loader.exec_module(C)
P = F = 0
def chk(name, got, want):
    global P, F
    if got == want: P += 1
    else:
        F += 1; print("  FAIL %s: got %r want %r" % (name, got, want))
# every type rule fires
for text, want in [
    ('add aria-label to x', 'a11y'), ('rel="noopener" link', 'security'), ('add Field(ge=1)', 'validation'),
    ('add return type hint', 'typing'), ('add a cache layer', 'perf'), ('add test_foo coverage', 'test'),
    ('fix the docstring', 'docs'), ('bump requirements pin', 'config'), ('edit the .tres resource', 'data'),
    ('it will crash on None', 'bugfix'), ('implement the thing', 'feature'), ('rename the helper', 'refactor'),
    ('fix indentation here', 'syntax'), ('nothing relevant whatsoever', 'other')]:
    chk("type_of " + text, C.type_of(text), want)
# complexity heuristics
for text, want in [
    ('change it. One line.', 'T1'), ('add `type="button"` now', 'T1'), ('swap bare except here', 'T1'),
    ('implement real logic', 'T4'), ('touch multi-file things', 'T4'), ('parse the thing', 'T3'), ('tidy a label', 'T2')]:
    chk("complexity " + text, C.complexity_of(text), want)
chk("explicit complexity wins", C.complexity_of('implement real', 'T5'), 'T5')
# verifiability
for lang, path, want in [('swift', 'a.swift', 'unverifiable'), ('py', 'tests/x.py', 'test-covered'),
                         ('md', 'README.md', 'unverifiable'), ('py', 'a.py', 'test-covered'),
                         ('godot', 'a.tscn', 'build-verified'), ('other', '', 'build-verified')]:
    chk("verif %s %s" % (lang, path), C.verif_of(lang, path), want)
# path discovery: backticked, bare fallback, none
chk("backtick path", C.classify('fix `src/a.ts` now')['file'], 'src/a.ts')
chk("bare path fallback", C.classify('fix src/b.kt now')['lang'], 'kotlin')
chk("no path", C.classify('nothing here')['file'], '')
chk("lang of unknown ext", C.lang_of('x.zzz'), 'other')
chk("tag format", C.tag({'lang': 'a', 'type': 'b', 'complexity': 'T1', 'verif': 'c'}), '{a·b·T1·c}')
print("PASS=%d FAIL=%d" % (P, F)); sys.exit(1 if F else 0)
PY
pyout="$(python3 "$T/cl.py" "$CL" 2>&1)"; rc=$?
echo "$pyout" | grep -v '^PASS='
n="$(echo "$pyout" | sed -n 's/^PASS=\([0-9]*\).*/\1/p')"
ok "classify in-process matrix (${n:-0} checks) rc=0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"

# ------------------------------------------------------------ enqueue emergency
EM="$D/ovn_enqueue_emergency.py"
python3 "$EM" >/dev/null 2>"$T/err"; rc=$?
ok "no args -> rc 2" "$([ $rc -eq 2 ] && echo 1 || echo 0)"
ok "usage on stderr" "$(grep -q usage "$T/err" && echo 1 || echo 0)"
python3 "$EM" a b >/dev/null 2>&1; ok "two args -> rc 2" "$([ $? -eq 2 ] && echo 1 || echo 0)"
ITEM='- [ ] 🚨 EMERGENCY DEPLOY FIX billwatch: prod deploy failed'
out="$(python3 "$EM" "$T/new.md" billwatch "$ITEM")"; rc=$?
ok "missing file: created, rc 0" "$([ $rc -eq 0 ] && [ -f "$T/new.md" ] && echo 1 || echo 0)"
eq "enqueue message" "$out" "enqueued emergency item for billwatch"
ok "no H1: section first, item inside" "$(sed -n 2p "$T/new.md" | grep -q '^## 🚨 Emergency' && grep -qF -- "$ITEM" "$T/new.md" && echo 1 || echo 0)"
out="$(python3 "$EM" "$T/new.md" billwatch "$ITEM")"
eq "dedup message" "$out" "emergency item for billwatch already present — no-op"
ok "dedup: item appears once" "$([ "$(grep -cF -- 'EMERGENCY DEPLOY FIX' "$T/new.md")" = 1 ] && echo 1 || echo 0)"
printf '%s\n' '# Overnight Progress' '' '## Next Steps' '- [ ] real work' > "$T/h1.md"
python3 "$EM" "$T/h1.md" gitlark '- [ ] 🚨 EMERGENCY DEPLOY FIX gitlark: broke' >/dev/null
ok "H1 kept on line 1, emergency section right after it" "$([ "$(sed -n 1p "$T/h1.md")" = '# Overnight Progress' ] && sed -n 3p "$T/h1.md" | grep -q '^## 🚨 Emergency' && echo 1 || echo 0)"
ok "existing items preserved; file ends with single newline" "$(grep -qxF -- '- [ ] real work' "$T/h1.md" && [ -z "$(tail -c1 "$T/h1.md" | tr -d '\n')" ] && echo 1 || echo 0)"
out="$(python3 "$EM" "$T/h1.md" billwatch '- [ ] 🚨 EMERGENCY DEPLOY FIX billwatch: x')"
eq "other service's open item does not dedup" "$out" "enqueued emergency item for billwatch"
printf '%s\n' '- [x] 🚨 EMERGENCY DEPLOY FIX iptv: was fixed' > "$T/closed.md"
out="$(python3 "$EM" "$T/closed.md" iptv '- [ ] 🚨 EMERGENCY DEPLOY FIX iptv: again')"
eq "a CLOSED emergency item does not block a new one" "$out" "enqueued emergency item for iptv"

# ------------------------------------------------------------------ tag items
TG="$D/ovn_tag_items.py"
printf '%s\n' '- [ ] app/foo.py — bare except. One line.' '- [ ] [T2] web/A.vue add aria-label' '- [x] done.py' '- [ ] HUMAN-ONLY x.py' '- [ ] {py·a·T1·b} tagged.py' '- [ ]' > "$T/ti.md"
out="$(python3 "$TG" "$T/ti.md" "$T/does-not-exist.md")"
eq "tag_items skips missing paths, counts 2" "$out" "GENERATED_TAGS=2"
ok "label kept before tag" "$(grep -q '^- \[ \] \[T2\] {vue·a11y·T1·test-covered} web/A.vue' "$T/ti.md" && echo 1 || echo 0)"
eq "tag_items rerun is idempotent" "$(python3 "$TG" "$T/ti.md")" "GENERATED_TAGS=0"
eq "tag_items no args prints 0" "$(python3 "$TG")" "GENERATED_TAGS=0"

# -------------------------------------------------------------- hourly notable
HN="$D/ovn_hourly_notable.py"
now="$(date +%s)"
mkrow(){ printf '%s\t%s\t%s\t{py·x·T1·y}\tf.py\n' "$1" r "$2"; }
hn(){ ( cd "$T" && TASK_STATS="$1" python3 "$HN" "${@:2}" ); }
: > "$T/empty.log"
eq "empty stats -> silent" "$(hn "$T/empty.log")" ""
eq "missing stats file (and no cwd fallback) -> silent" "$(hn "$T/nope.log")" ""
{ mkrow $((now-60)) pass; mkrow $((now-90)) pass; } > "$T/good.log"
eq "clean landings -> not notable" "$(hn "$T/good.log")" ""
{ mkrow $((now-60)) revert; mkrow $((now-70)) noop:gate; } > "$T/wash.log"
ok "0 landed + bad -> washout" "$(hn "$T/wash.log" | grep -q '^NOTABLE: a fully-wasted window — 0 landed, 2 wasted' && echo 1 || echo 0)"
{ printf 'garbage\n'; printf 'x\ty\n'; printf 'notanumber\tr\trevert\tt\tf\n'; mkrow $((now-60)) revert; } > "$T/junk.log"
ok "malformed rows skipped; valid row counted" "$(hn "$T/junk.log" | grep -q 'fully-wasted window — 0 landed, 1 wasted' && echo 1 || echo 0)"
{ for i in 1 2 3; do mkrow $((now-100-i)) pass; done; mkrow $((now-200)) revert; mkrow $((now-210)) revert; } > "$T/spike.log"
# baseline: 24h window before the last hour holds lots of good rows
{ cat "$T/spike.log"; for i in $(seq 1 30); do mkrow $((now-7200-i)) pass; done; } > "$T/spike2.log"
ok "bad-rate spike vs baseline -> notable" "$(hn "$T/spike2.log" | grep -q 'rate spiking — 40% this window vs 0% baseline (2 wasted of 5)' && echo 1 || echo 0)"
{ cat "$T/spike.log"; for i in $(seq 1 6); do mkrow $((now-7200-i)) revert; done; for i in $(seq 1 4); do mkrow $((now-8000-i)) pass; done; } > "$T/nospike.log"
eq "spike absorbed by already-bad baseline -> silent" "$(hn "$T/nospike.log")" ""
eq "args: too few bad events for spike (min_bad=3)" "$(hn "$T/spike2.log" 1 24 0.35 3)" ""
{ mkrow $((now-100)) pass; mkrow $((now-110)) revert; mkrow $((now-7300)) pass; } > "$T/nobase.log"
ok "no baseline rows -> baseline 0%, 50% rate hits margin 0.35" "$(hn "$T/nobase.log" 1 24 0.35 1 | grep -q 'vs 0% baseline' && echo 1 || echo 0)"
{ mkrow $((now-100)) pass; mkrow $((now-110)) revert; } > "$T/nobase2.log"
ok "empty baseline window handled (rate_b=0)" "$(hn "$T/nobase2.log" 1 24 0.35 1 | grep -q 'NOTABLE' && echo 1 || echo 0)"
mkdir -p "$T/cwd/state"; mkrow $((now-60)) revert > "$T/cwd/state/task_stats.log"
out="$(cd "$T/cwd" && TASK_STATS="$T/absent" python3 "$HN")"
ok "cwd-relative state/task_stats.log fallback used" "$(echo "$out" | grep -q NOTABLE && echo 1 || echo 0)"

# --------------------------------------------------------------- retire vague
RV="$D/ovn_retire_vague.py"
W="$T/repo"; mkdir -p "$W/src" "$W/backend/tests"; echo x > "$W/src/real.py"; echo x > "$W/backend/tests/t.py"; echo x > "$W/top.py"
cat > "$W/P.md" <<'MD'
# Progress
- [ ] keeps src/real.py fix one thing
- [ ] vague item with no file at all
- [ ] dead ghost/none.py is gone
- [ ] [T2] myrepo/src/real.py prefixed still exists
- [ ] tests/t.py::test_x under backend prefix
- [ ] Create a new ghost/newfile.py module
- [ ] Add a new component at ghost/Comp.vue
- [ ] Fix NEW ghost/marker.py
- [ ] human decision needed on ghost/x.py
- [ ] AUTO-SKIP ghost/y.py
- [ ] retired-something ghost/z.py
- [ ] top.py alone (no slash) kept
- [x] checked ghost/w.py untouched
MD
cp "$W/P.md" "$W/P.orig"
out="$(cd "$W" && python3 "$RV" P.md nonexistent.md)"
ok "summary: vague=1 dead-path=1" "$(echo "$out" | grep -qF 'total retired: 2 (vague=1 dead-path=1)' && echo 1 || echo 0)"
ok "per-class lines printed" "$(echo "$out" | grep -q 'retired 1 vague from P.md' && echo "$out" | grep -q 'retired 1 dead-path from P.md' && echo 1 || echo 0)"
ok "vague item moved to retired section" "$(grep -qxF -- '- [x] (retired-vague) vague item with no file at all' "$W/P.md" && echo 1 || echo 0)"
ok "dead item moved to retired section" "$(grep -qxF -- '- [x] (retired-dead-path) dead ghost/none.py is gone' "$W/P.md" && echo 1 || echo 0)"
ok "both retired headers written" "$(grep -q '^### Retired (vague' "$W/P.md" && grep -q '^### Retired (dead-path' "$W/P.md" && echo 1 || echo 0)"
kept=1; for s in 'keeps src/real.py' 'myrepo/src/real.py' 'tests/t.py::test_x' 'Create a new ghost/newfile.py' 'Add a new component' 'Fix NEW ghost/marker.py' 'human decision' 'AUTO-SKIP ghost/y.py' 'retired-something' 'top.py alone' '- [x] checked ghost/w.py'; do grep -qF -- "$s" "$W/P.md" || { kept=0; echo "    lost: $s"; }; done
ok "all keep-cases survive (existing, prefixed, app-root, create-intent, NEW, skip words, no-slash, checked)" "$kept"
ok "retired items no longer unchecked" "$(! grep -qE '^- \[ \] (vague item|dead ghost)' "$W/P.md" && echo 1 || echo 0)"
out="$(cd "$W" && python3 "$RV" P.md)"
ok "second run retires nothing" "$(echo "$out" | grep -qF 'total retired: 0 (vague=0 dead-path=0)' && echo 1 || echo 0)"
out="$(cd "$W" && python3 "$RV")"
ok "no args: only total line" "$([ "$out" = '  total retired: 0 (vague=0 dead-path=0)' ] && echo 1 || echo 0)"
printf '%s\n' '- [ ] only vague words here' > "$W/V.md"
out="$(cd "$W" && python3 "$RV" V.md)"
ok "only-vague file: no dead-path line" "$(echo "$out" | grep -q 'retired 1 vague' && ! echo "$out" | grep -q dead-path.from && echo 1 || echo 0)"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
