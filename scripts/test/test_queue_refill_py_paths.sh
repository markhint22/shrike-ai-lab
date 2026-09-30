#!/usr/bin/env bash
# Runs the REAL queue_refill.py (by its real path) against throwaway progress/backlog files to cover every branch: usage error,
# missing backlog, nothing-eligible early return, dedup-prune-only path, pulls up to the quota, parked/CLAUDE exclusion, feat-date
# normalisation, pre-check crediting (backtick + "(cat:" VERIFY forms), always-true rejection, unsupported VERIFY shapes, failing
# and timing-out verifies, SCAN_CAP bound, done-archive writing and the REFILL/CREDITED/PRUNED summary line.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QR=""
for c in "$HERE/../../queue_refill.py" "$HERE/../queue_refill.py" "$HERE/queue_refill.py"; do [ -f "$c" ] && { QR="$c"; break; }; done
[ -n "$QR" ] || { echo "  SKIP: queue_refill.py not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
new(){ rm -rf "$T/r"; mkdir -p "$T/r"; PF="$T/r/OVERNIGHT_PROGRESS.md"; BL="$T/r/backlog.md"; DONE="$T/r/OVERNIGHT_DONE.md"; : > "$PF"; : > "$BL"; }
run(){ OUT="$(python3 "$QR" "$@" 2>"$T/err")"; RC=$?; }
cnt(){ local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)"; echo "${c:-0}"; }

# ---- usage ----
run; ok "no args -> usage on stderr, exit 2" "$([ "$RC" = 2 ] && grep -q usage "$T/err" && echo 1 || echo 0)"
run a b; ok "two args -> usage, exit 2" "$([ "$RC" = 2 ] && echo 1 || echo 0)"

# ---- missing backlog ----
new; run "$PF" "$T/r/nope.md" 5
ok "missing backlog file -> zeroed summary (no PRUNED field on this path)" "$([ "$OUT" = "REFILL=0  BACKLOG_REMAINING=0  CREDITED=0" ] && echo 1 || echo 0)"

# ---- nothing eligible ----
new; printf -- '- [ ] [CLAUDE] escalation\n- [ ] [T2] HUMAN-ONLY decision\n- [ ] [T2] [HUMAN/design] needs design\n- [ ] [T1] blocked thing BLOCKED\n- [ ] [T1] auto-skip AUTO-SKIP\nprose line\n- [x] [T1] already checked\n' > "$BL"
run "$PF" "$BL" 5
ok "CLAUDE/parked/checked/prose lines are never eligible -> early return" "$([ "$OUT" = "REFILL=0  BACKLOG_REMAINING=0  CREDITED=0  PRUNED=0" ] && echo 1 || echo 0)"
ok "early return leaves the backlog untouched" "$([ "$(wc -l < "$BL" | tr -d ' ')" = 7 ] && echo 1 || echo 0)"

# ---- simple pull up to the quota, appended under a dated marker, removed from backlog ----
new; printf -- '- [ ] [T1] item one (cat:py)\n- [ ] [T2] item two (cat:py)\n- [ ] [T3] item three (cat:py)\n- [ ] [CLAUDE] keep me\n' > "$BL"; echo "- [ ] [T1] existing live" > "$PF"
run "$PF" "$BL" 2
ok "pulls exactly the quota" "$([ "$OUT" = "REFILL=2  CREDITED=0  BACKLOG_REMAINING=1  PRUNED=0" ] && echo 1 || echo 0)"
ok "pulled items appended to progress under an auto-refill marker" "$(grep -q '<!-- auto-refill .*: 2 items pulled from backlog -->' "$PF" && grep -q 'item one' "$PF" && grep -q 'item two' "$PF" && ! grep -q 'item three' "$PF" && echo 1 || echo 0)"
ok "pulled items removed from backlog; the rest (incl. CLAUDE) kept" "$(grep -q 'item three' "$BL" && grep -q 'keep me' "$BL" && ! grep -q 'item one' "$BL" && echo 1 || echo 0)"
ok "no done archive created when nothing credited" "$([ ! -f "$DONE" ] && echo 1 || echo 0)"

# ---- dedup vs live queue AND done archive; prune-only path (nothing to pull) ----
new; printf -- '- [ ] [T1] already live (cat:py)\n- [ ] [T3] archived earlier (cat:py)\n' > "$BL"
echo "- [ ] [T1] already live (cat:py)" > "$PF"; echo "- [x] [T3] archived earlier (cat:py)" > "$DONE"
run "$PF" "$BL" 5
ok "dup-only run: REFILL=0 but the stale duplicates are PRUNED (2)" "$([ "$OUT" = "REFILL=0  CREDITED=0  BACKLOG_REMAINING=0  PRUNED=2" ] && echo 1 || echo 0)"
ok "pruned lines are gone from the backlog file" "$([ "$(grep -c '^- \[ \]' "$BL")" = 0 ] && echo 1 || echo 0)"
ok "no auto-refill marker when nothing was pulled" "$(grep -q 'auto-refill' "$PF" && echo 0 || echo 1)"

# ---- feat-date normalisation: same feat slug, regenerated date stamp == duplicate ----
new; echo "- [ ] [T2] [feat:login-20260901-a] wire the form (cat:py)" > "$PF"
printf -- '- [ ] [T2] [feat:login-20260929-a] wire the form (cat:py)\n- [ ] [T2] [feat:login-290926-a] wire the form (cat:py)\n- [ ] [T2] [feat:login-20260929-a] wire the OTHER sibling (cat:py)\n' > "$BL"
run "$PF" "$BL" 5
ok "8-digit and 6-digit re-stamped feat tags dedup against the live item; a different sibling is pulled" "$([ "$OUT" = "REFILL=1  CREDITED=0  BACKLOG_REMAINING=0  PRUNED=2" ] && echo 1 || echo 0)"

# ---- pre-check crediting ----
new; mkdir -p "$T/r"; echo "def hello(): pass" > "$T/r/mod.py"
{
  echo '- [ ] [T1] grep form VERIFY: `grep -q "def hello" mod.py` (cat:py)'
  echo '- [ ] [T1] cat-form VERIFY: grep -q "def hello" mod.py (cat:py)'
  echo '- [ ] [T1] python form VERIFY: `python3 -c "import os"` (cat:py)'
  echo '- [ ] [T1] failing verify VERIFY: `grep -q "nothing_here_xyz" mod.py` (cat:py)'
  echo '- [ ] [T1] always-true shape VERIFY: `grep -q foo mod.py || echo ok` (cat:py)'
  echo '- [ ] [T1] always-true printf VERIFY: `grep -q foo mod.py || printf ok` (cat:py)'
  echo '- [ ] [T1] always-true true VERIFY: `grep -q foo mod.py || true` (cat:py)'
  echo '- [ ] [T1] unsupported shape VERIFY: `pytest -q tests` (cat:py)'
  echo '- [ ] [T1] no verify at all (cat:py)'
} > "$BL"
run "$PF" "$BL" 20
ok "3 pass-verify items credited, 6 others pulled (never blocked)" "$([ "$OUT" = "REFILL=6  CREDITED=3  BACKLOG_REMAINING=0  PRUNED=0" ] && echo 1 || echo 0)"
ok "credited items go straight to OVERNIGHT_DONE.md as pre-verified [x]" "$([ "$(cnt '^- \[x\] (pre-verified: VERIFY already passed against current code) \[T1\]' "$DONE")" = 3 ] && grep -q 'pre-verified already-satisfied .*: 3 item(s)' "$DONE" && echo 1 || echo 0)"
ok "credited items never enter the live queue" "$(grep -q 'grep form VERIFY' "$PF" && echo 0 || echo 1)"
ok "failing / always-true / unsupported / verify-less items ARE pulled" "$(grep -q 'failing verify' "$PF" && grep -q 'always-true shape' "$PF" && grep -q 'unsupported shape' "$PF" && grep -q 'no verify at all' "$PF" && echo 1 || echo 0)"
ok "always-true shapes were rejected without executing (printf/true variants pulled too)" "$(grep -q 'always-true printf' "$PF" && grep -q 'always-true true' "$PF" && echo 1 || echo 0)"

# ---- timeout -> treated as not satisfied (pulled) ----
new; echo '- [ ] [T1] slow verify VERIFY: `python3 -c "import time; time.sleep(30)"` (cat:py)' > "$BL"
run "$PF" "$BL" 5
ok "verify that exceeds the 8s timeout is not credited (item pulled)" "$([ "$OUT" = "REFILL=1  CREDITED=0  BACKLOG_REMAINING=0  PRUNED=0" ] && echo 1 || echo 0)"

# ---- SCAN_CAP bound: only the first 30 eligible items are examined/pulled when n is large ----
new; : > "$BL"; i=0; while [ "$i" -lt 40 ]; do echo "- [ ] [T2] bulk item $i (cat:py)" >> "$BL"; i=$((i+1)); done
run "$PF" "$BL" 100
ok "SCAN_CAP=30 bounds a run even when quota is larger" "$([ "$OUT" = "REFILL=30  CREDITED=0  BACKLOG_REMAINING=10  PRUNED=0" ] && echo 1 || echo 0)"

# ---- progress file does not exist yet (dedup tolerates it, pull creates it) ----
new; rm -f "$PF"; echo "- [ ] [T1] fresh item (cat:py)" > "$BL"
run "$PF" "$BL" 3
ok "missing progress file: created with the pulled item" "$([ "$OUT" = "REFILL=1  CREDITED=0  BACKLOG_REMAINING=0  PRUNED=0" ] && grep -q 'fresh item' "$PF" && echo 1 || echo 0)"
# relative progress path without a directory component -> repo_root falls back to "."
new; ( cd "$T/r" && echo "- [ ] [T1] rel item (cat:py)" > backlog.md && python3 "$QR" OVERNIGHT_PROGRESS.md backlog.md 1 > "$T/rel.out" 2>&1 )
ok "bare relative progress path works (repo_root='.')" "$(grep -q 'REFILL=1' "$T/rel.out" && echo 1 || echo 0)"

echo "queue_refill_py_paths: $P passed, $F failed"
[ "$F" = 0 ]
