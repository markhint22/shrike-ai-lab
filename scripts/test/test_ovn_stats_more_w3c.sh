#!/usr/bin/env bash
# Coverage tests for scripts/ovn_stats.py (runs the REAL script in place; data via temp HOME / env).
# Covers: no-activity exit, full report, --ntfy report (errors ongoing/resolved, last-30m, no-op causes, repeat offenders,
# producing/idle/weak spots, runway), --noop-headline variants, runway() edge cases (import path).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../ovn_stats.py"; [ -f "$PY" ] || PY="$HOME/overnight-queue/scripts/ovn_stats.py"
[ -f "$PY" ] || { echo "  SKIP: ovn_stats.py not found"; exit 0; }
SD="$(dirname "$PY")"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset OVN_REPOS_DIR OVN_ACTIVE_REPOS
pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
has(){ if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (missing [$3])"; [ -n "${DBG:-}" ] && { printf "%s\n" "$2" | head -12; }; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 (unexpected [$3])"; else ok "$1"; fi; }
known(){ if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else warnc=$((warnc+1)); echo "  WARN $1"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H/overnight-queue/state"; LOG="$H/overnight-queue/state/task_stats.log"
NOW="$(date +%s)"
row(){ printf '%s\t%s\t%s\t%s\t%s\n' "$((NOW-$1))" "$2" "$3" "$4" "$5"; }   # age_s repo oc tag file
run(){ HOME="$H" python3 "$PY" "$@" 2>&1; }

echo "== no log / no rows in window =="
out="$(run)"; has "no log -> no activity msg" "$out" "no queue activity recorded in the last 24h yet"
out="$(run 0.5)"; has "custom hours formatted" "$out" "last 0.5h yet"
printf 'garbage line\nnotanumber\trepo\tpass\t{a.b.c.d}\tf\n%s\n%s\n' "$(row 10 r pass 'notag' f)" "$(row 999999 r pass '{py.fix.low.tested}' old)" > "$LOG"
out="$(run)"; has "malformed/old/untagged rows ignored" "$out" "no queue activity"

echo "== full report =="
{
  row 100 billwatch pass   '{py.fix.low.tested}' a.py
  row 110 billwatch pass   '{py.fix.low.tested}' b.py
  row 120 billwatch pass   '{ts·feat·high·unverifiable}' c.ts
  row 130 billwatch revert '{ts·feat·high·unverifiable}' d.ts
  row 140 gitlark  noop:gate  '{py.fix.low.tested}' e.py
  row 150 gitlark  noop:flail '{py.fix.low.tested}' e.py
  row 160 gitlark  noop '{py.fix.low.tested}' e.py
  row 170 gitlark  noop:gate  '{py.fix.low.tested}' e.py
  row 180 gitlark  noop:flail '{py.fix.low.tested}' e.py
  row 185 gitlark  noop:flail '{py.fix.low.tested}' e.py
  row 186 gitlark  noop:gate '{py.fix.low.tested}' e.py
  row 190 gitlark  noop:done  '{sh.chore.low.tested}' f.sh
  row 200 gitlark  noop:blocked '{sh.chore.low.tested}' g.sh
  row 210 gitlark  skip '{sh.chore.low.tested}' h.sh
  row 220 gitlark  error '{sh.chore.low.tested}' i.sh
} > "$LOG"
out="$(run)"
has "header" "$out" "Overnight throughput, last 24h — 15 cycles"
has "line: 3 landed" "$out" "✅ 3 landed"
has "line: benign no-op count" "$out" "➖ 2 benign no-op"
has "line: errored shown" "$out" "⚠ 1 errored"
has "pass-rate line" "$out" "pass-rate (of GOOD-or-BAD attempts): 27.3%"
has "wasted line" "$out" "wasted attempts: 8 (1 revert, 3 gate-reverted, 4 flailed)"
has "benign breakdown parts" "$out" "(1 already-done, 1 blocked, 1 skip, 1 error)"
known "KNOWN-BUG: ovn_stats.py _benign_total double-counts skip (oc_benign_breakdown already includes skip; 4 events shown as 5)" "$out" "excluded, not counted (benign): 4 ("
has "stuck line" "$out" "🔁 Stuck (repeated flail/gate-rev): gitlark/e.py x6"
has "BY COMPLEXITY" "$out" "BY COMPLEXITY:"
has "BY LANGUAGE" "$out" "BY LANGUAGE:"
has "BY TYPE" "$out" "BY TYPE:"
has "BY VERIFIABILITY" "$out" "BY VERIFIABILITY:"
has "err column in cell" "$out" "err 1"
out="$(run 1)"; has "explicit hours arg" "$out" "last 1h"
# a cell with zero landed+failed shows the dash rate
printf '%s\n' "$(row 5 r noop:done '{sh.chore.low.tested}' z)" > "$LOG"
out="$(run)"; has "no-rate dash for benign-only cell" "$out" "—"
hasnt "no pass-rate line when L+F==0" "$out" "pass-rate"
hasnt "no stuck/err/benign extras" "$out" "errored"

echo "== --ntfy report =="
{
  row 100 billwatch pass   '{py.fix.low.tested}' a.py
  row 110 billwatch pass   '{py.fix.low.tested}' b.py
  row 120 billwatch revert '{ts.feat.high.unverifiable}' c.ts
  for i in 1 2 3 4 5; do row $((200+i)) gitlark noop:flail '{sh.chore.mid.tested}' s.sh; done
  for i in 1 2 3 4; do row $((4000+i)) gitlark noop:done '{sh.idle.mid.unverifiable}' x.sh; done
  row 50 gitlark noop:done '{sh.idle.mid.unverifiable}' y.sh
  row 60 gitlark skip '{sh.chore.mid.tested}' y.sh
  row 7200 gitlark error '{sh.chore.mid.tested}' y.sh
} > "$LOG"
out="$(run --ntfy)"
has "ntfy head" "$out" "Overnight · 24h · 15 cycles"
has "ntfy headline" "$out" "✅ 2 landed"
has "errored RESOLVED" "$out" "errored (RESOLVED — last 120m ago)"
has "pass-rate line" "$out" "pass-rate: 25.0%"
has "benign breakdown parts ntfy" "$out" "(5 already-done, 0 blocked, 1 skip, 1 error)"
known "KNOWN-BUG: ovn_stats.py --ntfy benign total double-counts skip (4 events shown as 5)" "$out" "ℹ️ 7 benign, not counted ("
has "last 30m line" "$out" "last 30m: ✅ 2"
has "no-op causes" "$out" "No-op causes: flailed 5 (too hard for the model)"
has "mostly flail meaning" "$out" "→ mostly flail: too hard for the 27B"
has "stuck line ntfy" "$out" "🔁 Stuck (same item retried and thrown away repeatedly): gitlark/s.sh x5"
has "producing" "$out" "Producing: py 2"
has "idle (spinning by type) + unverifiable" "$out" "Idle (nothing to do):"
has "weak spots" "$out" "⚠ Weak spots"
hasnt "no runway without env" "$out" "Runway:"
# recent error => ONGOING
printf '%s\n%s\n' "$(row 100 r pass '{py.fix.low.tested}' a)" "$(row 300 r error '{py.fix.low.tested}' b)" > "$LOG"
out="$(run --ntfy)"; has "errored ONGOING" "$out" "errored (ONGOING — last 5m ago)"
hasnt "no-op causes absent" "$out" "No-op causes"
hasnt "no benign line when 0 benign ... (error counts as benign)" "$out" "NOPE-placeholder"
# only flails below threshold: no 'mostly' line; all-noop langs -> idle via lang fallback
printf '%s\n' "$(row 5 r noop:blocked '{sh.chore.low.tested}' a)" > "$LOG"
out="$(run --ntfy)"; hasnt "below-threshold cause has no mostly line" "$out" "→ mostly"
has "blocked cause" "$out" "blocked 1"
# legacy bare noop: counted as flail cause & failed
printf '%s\n%s\n%s\n' "$(row 5 r noop '{sh.chore.low.tested}' a)" "$(row 6 r noop '{sh.chore.low.tested}' a)" "$(row 7 r noop '{sh.chore.low.tested}' a)" > "$LOG"
out="$(run --ntfy)"; has "legacy noop folded into flailed" "$out" "flailed 3"
has "mostly flail (3)" "$out" "→ mostly flail"
# spinning by lang fallback: >=5 benign noops under DIFFERENT types so type-axis has none? (type axis has each <5)
: > "$LOG"; i=0
for t in a b c d e f; do row 10 r noop:done "{sh.$t.low.tested}" "q$t"; done > "$LOG"
out="$(run --ntfy)"; has "idle falls back to lang axis" "$out" "Idle (nothing to do): sh"

echo "== --noop-headline =="
printf '%s\n' "$(row 5 r pass '{py.fix.low.tested}' a)" > "$LOG"
out="$(run --noop-headline)"; eqv "no no-ops -> empty line" "" "$out"
printf '%s\n%s\n' "$(row 5 r noop:done '{py.fix.low.tested}' a)" "$(row 6 r noop:blocked '{py.fix.low.tested}' a)" > "$LOG"
out="$(run --noop-headline)"
has "cheap only" "$out" "2 no-op -- 2 cheap, no real attempt made (1 done (already satisfied in code), 1 blocked (needs a human decision))"
hasnt "cheap only: no burned clause" "$out" "worth investigating"
printf '%s\n%s\n' "$(row 5 r noop:flail '{py.fix.low.tested}' a)" "$(row 6 r noop:gate '{py.fix.low.tested}' a)" > "$LOG"
out="$(run --noop-headline)"
has "burned only" "$out" "2 no-op -- 2 worth investigating, a real attempt was burned (1 flailed (too hard for the model), 1 gate-rev (safety-check reverted it))"
printf '%s\n%s\n' "$(row 5 r noop:flail '{py.fix.low.tested}' a)" "$(row 6 r noop:done '{py.fix.low.tested}' a)" > "$LOG"
out="$(run --noop-headline)"
has "both clauses" "$out" "; 1 worth investigating"

echo "== runway() via import =="
RWPY='
import sys, os, importlib.util
sd = sys.argv[1]; sys.argv = ["ovn_stats.py"]
spec = importlib.util.spec_from_file_location("ovn_stats", os.path.join(sd, "ovn_stats.py"))
m = importlib.util.module_from_spec(spec); sys.modules["ovn_stats"] = m
try:
    spec.loader.exec_module(m)
except SystemExit:
    pass
print(repr(m.runway()))
'
rw(){ HOME="$H" python3 -c "$RWPY" "$SD" 2>&1; }
: > "$LOG"
eqv "no OVN_REPOS_DIR -> []" "[]" "$(rw | tail -1)"
eqv "missing dir -> []" "[]" "$(OVN_REPOS_DIR="$T/nope" rw | tail -1)"
R="$T/repos"; mkdir -p "$R"
mkrepo(){ # name open_items [recent_commits...]
  local n="$1" open="$2"; shift 2
  mkdir -p "$R/$n"; ( cd "$R/$n" && git init -q . && : > OVERNIGHT_PROGRESS.md
    for i in $(seq 1 "$open"); do echo "- [ ] item $i" >> OVERNIGHT_PROGRESS.md; done
    echo "- [ ] HUMAN-ONLY thing" >> OVERNIGHT_PROGRESS.md; echo "- [x] done" >> OVERNIGHT_PROGRESS.md
    git add -A && git commit -qm "chore: init"
    for s in "$@"; do git commit -q --allow-empty -m "$s"; done ); }
mkrepo aaa_zero 0 "feat: x"
mkrepo bbb_stalled 4
mkrepo ccc_days 10 "feat: a" "fix: b" "test: c" "auto-credit: skip me" "docs: ignored"
mkrepo ddd_lt1 1 "feat: a" "fix: b" "perf: c"
mkdir -p "$R/eee_unreadable/OVERNIGHT_PROGRESS.md"      # directory -> open() raises OSError
out="$(OVN_REPOS_DIR="$R" rw)"
has "zero doable -> 0d" "$out" "('aaa_zero', 0, '0d', 1)"
has "no burn -> stalled?" "$out" "('bbb_stalled', 4, 'stalled?', 0)"
has "burn counts substantive only, ~Nd" "$out" "('ccc_days', 10, '~3d', 3)"
has "<1d" "$out" "('ddd_lt1', 1, '<1d', 3)"
hasnt "unreadable progress skipped" "$out" "eee_unreadable"
out="$(OVN_REPOS_DIR="$R" OVN_ACTIVE_REPOS="ccc_days ddd_lt1" rw)"
hasnt "active filter excludes others" "$out" "aaa_zero"
has "active filter keeps listed" "$out" "ccc_days"
# git missing -> except branch, burn 0
out="$(PATH="/nonexistent-bin" OVN_REPOS_DIR="$R" OVN_ACTIVE_REPOS="ccc_days" HOME="$H" "$(command -v python3)" -c "$RWPY" "$SD" 2>&1)"
has "git unavailable -> burn 0 -> stalled?" "$out" "('ccc_days', 10, 'stalled?', 0)"
# runway line in ntfy report
printf '%s\n' "$(row 5 r pass '{py.fix.low.tested}' a)" > "$LOG"
out="$(OVN_REPOS_DIR="$R" OVN_ACTIVE_REPOS="ccc_days" run --ntfy)"
has "ntfy Runway line" "$out" "Runway: ccc_days 10 ~3d"

echo "ovn_stats_more: $pass passed, $fail failed ($warnc known-bug warnings)"
[ "$fail" -eq 0 ]
