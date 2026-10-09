#!/usr/bin/env bash
# ovn_auto_research.sh (Mac launchd job) + ovn_auto_research_validate.py, 2026-10-09:
#   1. candidates are ordered round-robin: fewest passes that ACCEPTED items in the last 48h first, then longest starving (run.log is the source)
#      - before: longest-starving first gave both daily slots to xlite (10-08 01:33+03:47, 10-09 02:05+04:20) while iptv_apps' last pass was 10-07
#   2. the research prompt is design-level / bug-hunting only and lists the OPEN roadmap/backlog features as 'do not repeat'
#   3. the validator rejects mechanical-gap proposals (docstrings, comments, unused imports, return annotations, dead-stub deletes w/o callers analysis)
# Hermetic (lib_ar_fixture.sh): temp HOME/state, stub ssh/scp/claude, the "box" is a temp dir. The real claude CLI and ~/.ovn_auto_research are never touched.
# Assertions about the prompt read the file the stub `claude` captured, never the script source. Mutation checks at the bottom.
# No `x | grep -q` (pipefail-safe: no pipefail anyway), no kill -0, no greps that can match comments (all greps run on captured output/prompt files).
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../ovn_auto_research.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../ovn_auto_research.sh"
VALIDATOR="$HERE/../../ovn_auto_research_validate.py"; [ -f "$VALIDATOR" ] || VALIDATOR="$HERE/../ovn_auto_research_validate.py"
. "$HERE/lib_ar_fixture.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
MT="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$MT"; [ -n "${T:-}" ] && rm -rf "$T"' EXIT
META='{cat: backend; size: S; multifile: no; research: repo}'

mutate(){   # <src> <dest> <anchor> <replacement>  (the anchor must exist, else the test itself is stale)
  python3 - "$1" "$2" "$3" "$4" 2>/dev/null <<'PY' || { F=$((F+1)); echo "  FAIL mutation anchor missing - the test is stale: $3"; }
import sys
src, dest, a, b = sys.argv[1:5]
s = open(src).read()
assert a in s, "mutation anchor missing: %r" % a
open(dest, "w").write(s.replace(a, b, 1))
PY
}
order_of(){ grep -a "starting research pass" "$T/out.txt" | sed 's/^[^ ]* [^ ]* \([^:]*\):.*/\1/' | tr '\n' ' '; }
fresh_state(){ rm -rf "$STATE" "$CAP"; mkdir -p "$STATE" "$CAP"; : > "$BOX/ssh.log"; }
seed_roadmaps(){ for r in iptv_apps xlite billwatch shrike-notify shrike-monitor; do ar_roadmap "$r" "- [x] [P1] [done] Old feature of $r — app/old.py $META"; done; }

# ---- round-robin scenarios; prints "1|name" / "0|name" lines. All 1 for the real script; every mutant must produce at least one 0.
rr_checks(){
  ar_setup "$1" "$VALIDATOR"
  seed_roadmaps
  local o

  # 1. xlite is the LONGEST starving (9h) and took 2 accepted passes in the last 24h; iptv_apps (5h) has none in 48h (its last pass was 60h ago)
  fresh_state; ar_starving xlite:9 iptv_apps:5
  ar_runlog $((60*3600)) iptv_apps "accepted 4/6"
  ar_runlog $((20*3600)) xlite "accepted 3/5"; ar_runlog $((18*3600)) xlite "accepted 2/3"
  ar_runlog $((10*3600)) xlite "reject: near-duplicate of an existing roadmap item (same file, same words): Something"
  echo "$(date '+%F %T') daily cap reached (2/2) - skip" >> "$STATE/run.log"; echo "$(date '+%F %T') another run active - skip" >> "$STATE/run.log"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3; o="$(order_of)"
  [ "$o" = "iptv_apps xlite " ] && echo "1|iptv_apps (no accepted pass in 48h) goes before the longest-starving xlite (2 accepted)" || echo "0|iptv_apps (no accepted pass in 48h) goes before the longest-starving xlite (2 accepted) [got: $o]"
  grep -aq "candidate order (roundrobin): iptv_apps\[accepted48h=0 starving=5.0h\] xlite\[accepted48h=2 starving=9.0h\]" "$T/out.txt" && echo "1|the chosen order is logged" || echo "0|the chosen order is logged"

  # 2. a tie on accepted passes falls back to starvation age (xlite 9h before iptv_apps 5h)
  fresh_state; ar_starving iptv_apps:5 xlite:9
  ar_runlog $((20*3600)) xlite "accepted 3/5"; ar_runlog $((19*3600)) iptv_apps "accepted 2/3"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3; o="$(order_of)"
  [ "$o" = "xlite iptv_apps " ] && echo "1|tie on accepted passes -> longest starving first" || echo "0|tie on accepted passes -> longest starving first [got: $o]"

  # 3. legacy order = longest starving first, whatever the history
  fresh_state; ar_starving iptv_apps:5 xlite:9
  ar_runlog $((20*3600)) xlite "accepted 3/5"; ar_runlog $((18*3600)) xlite "accepted 2/3"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_ORDER=legacy; o="$(order_of)"
  [ "$o" = "xlite iptv_apps " ] && echo "1|OVN_AR_ORDER=legacy keeps the old longest-starving-first order" || echo "0|OVN_AR_ORDER=legacy keeps the old longest-starving-first order [got: $o]"

  # 4. a pass that accepted ZERO items does not count as an accepted pass (billwatch 6h > iptv_apps 5h, both 0 accepted -> billwatch first)
  fresh_state; ar_starving iptv_apps:5 billwatch:6
  ar_runlog $((5*3600)) billwatch "accepted 0/3"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_REPOS=all; o="$(order_of)"
  [ "$o" = "billwatch iptv_apps " ] && echo "1|a 0-accepted pass does not count against a repo" || echo "0|a 0-accepted pass does not count against a repo [got: $o]"

  # 5. only the FIRST candidate is researched when MAX_PER_RUN=1 (the slot really goes to iptv_apps)
  fresh_state; ar_starving xlite:9 iptv_apps:5
  ar_runlog $((20*3600)) xlite "accepted 3/5"
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=1; o="$(order_of)"
  [ "$o" = "iptv_apps " ] && echo "1|MAX_PER_RUN=1 gives the slot to iptv_apps" || echo "0|MAX_PER_RUN=1 gives the slot to iptv_apps [got: $o]"

  # 6. (review fix) the inactive lanes must not take a Claude slot. Real snapshot: shrike-notify/shrike-monitor "starve" 0.5h but have pullable 42/35;
  #    iptv_apps 31h (pullable 3), xlite 6h. Before the fix the order was iptv_apps, shrike-notify, shrike-monitor, xlite and MAX_PER_DAY=2 starved xlite.
  fresh_state; ar_starving shrike-notify:0.5:42 shrike-monitor:0.5:35 iptv_apps:31.4:3 xlite:6.2:2
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_REPOS=all; o="$(order_of)"
  [ "$o" = "iptv_apps xlite " ] && echo "1|repos with pullable above the threshold (42, 35) are not candidates, so xlite still gets its slot" || echo "0|repos with pullable above the threshold (42, 35) are not candidates, so xlite still gets its slot [got: $o]"
  grep -aq "excluded shrike-notify: pullable=42 > 10" "$T/out.txt" && echo "1|the exclusion and its reason are logged" || echo "0|the exclusion and its reason are logged"
  fresh_state; ar_starving iptv_apps:31:10 xlite:6:11 billwatch:5:9
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_REPOS=all; o="$(order_of)"
  [ "$o" = "iptv_apps billwatch " ] && echo "1|pullable == threshold stays a candidate, threshold+1 is dropped (boundary)" || echo "0|pullable == threshold stays a candidate, threshold+1 is dropped (boundary) [got: $o]"
  fresh_state; ar_starving shrike-notify:5:42 iptv_apps:4:3
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_REPOS=all OVN_AR_PULLABLE_MAX=100; o="$(order_of)"
  [ "$o" = "shrike-notify iptv_apps " ] && echo "1|OVN_AR_PULLABLE_MAX raises the limit" || echo "0|OVN_AR_PULLABLE_MAX raises the limit [got: $o]"
  fresh_state; ar_starving shrike-notify:5 iptv_apps:4:3
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3 OVN_AR_REPOS=all; o="$(order_of)"
  [ "$o" = "shrike-notify iptv_apps " ] && echo "1|a record without a pullable field (older checker) is not filtered" || echo "0|a record without a pullable field (older checker) is not filtered [got: $o]"

  # 7. (review fix) lane allowlist: default = iptv_apps + xlite only, even when an inactive lane has no pullable info; OVN_AR_REPOS=all lifts it
  fresh_state; ar_starving shrike-notify:40 billwatch:30 xlite:6 iptv_apps:5
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=4; o="$(order_of)"
  [ "$o" = "xlite iptv_apps " ] && echo "1|default allowlist keeps only the active dev lanes (iptv_apps, xlite)" || echo "0|default allowlist keeps only the active dev lanes (iptv_apps, xlite) [got: $o]"
  grep -aq "excluded shrike-notify: not in the research lane allowlist" "$T/out.txt" && echo "1|allowlist exclusion is logged" || echo "0|allowlist exclusion is logged"
  fresh_state; ar_starving shrike-notify:40 billwatch:30 xlite:6
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=4 OVN_AR_REPOS=all; o="$(order_of)"
  [ "$o" = "shrike-notify billwatch xlite " ] && echo "1|OVN_AR_REPOS=all lifts the allowlist" || echo "0|OVN_AR_REPOS=all lifts the allowlist [got: $o]"
  fresh_state; ar_starving shrike-notify:40 xlite:6
  ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=4 OVN_AR_REPOS="xlite shrike-notify"; o="$(order_of)"
  [ "$o" = "shrike-notify xlite " ] && echo "1|OVN_AR_REPOS accepts a custom list" || echo "0|OVN_AR_REPOS accepts a custom list [got: $o]"
  # 8. (round-3 review) an empty / truncated / non-JSON starving.json must not dump a python traceback into run.log line by line
  for bad in '' '{"checked_at": 1' 'not json' '[]'; do
    fresh_state; printf '%s' "$bad" > "$BOX/starving.json"
    ar_run DRY_RUN=1 OVN_AR_MAX_PER_RUN=3
    [ "$AR_RC" = 0 ] && [ "$(grep -a -c 'Traceback\|JSONDecodeError\|File "<stdin>"' "$T/out.txt")" = 0 ] && [ "$(grep -a -c 'starving snapshot unreadable' "$T/out.txt")" = 1 ] && echo "1|bad starving.json ('$bad') -> one clear 'unreadable' line, no traceback, rc 0" || echo "0|bad starving.json ('$bad') -> one clear 'unreadable' line, no traceback, rc 0 [rc=$AR_RC $(tail -3 "$T/out.txt" | tr '\n' '~')]"
  done
  ar_cleanup; T=""
}

echo "== candidate order (real script) =="
res="$(rr_checks "$SCRIPT")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOF
$res
EOF

echo "== prompt: design-level only + do-not-repeat list (read from the file the stub claude captured) =="
ar_setup "$SCRIPT" "$VALIDATOR"
fresh_state; ar_starving iptv_apps:5
ar_roadmap iptv_apps "- [ ] [P1] [ready] Alpha feature title — body in app/a.py $META
- [x] [P1] [done] Closed old feature — body app/c.py $META
- [ ] [P2] [decomposed] Decomposed feature gamma — body app/g.py $META
- [ ] [P2] [decomposed] Decomposed feature delta — body app/d.py $META
- [ ] [P2] [needs-research] Needs research epsilon — body $META"
ar_backlog iptv_apps "# --- 27B-decomposed from roadmap [2026-10-01]: Decomposed feature gamma — body app/g.py (review + tweak) [feat:iptv_apps-20261001-decomposed-feature-gamma-body] ---
- [ ] [T2] app/g.py — do the gamma thing VERIFY: true. [feat:iptv_apps-20261001-decomposed-feature-gamma-body]
# --- 27B-decomposed from roadmap [2026-10-01]: Decomposed feature delta — body app/d.py (review + tweak) [feat:iptv_apps-20261001-decomposed-feature-delta-body] ---
- [x] [T2] app/d.py — the delta thing is done VERIFY: true. [feat:iptv_apps-20261001-decomposed-feature-delta-body]"
ar_run DRY_RUN=1
PF="$CAP/prompt_iptv_apps.txt"
ok "stub claude was invoked once for iptv_apps and captured a prompt" "[ -s '$PF' ] && [ \"\$(grep -c . '$CAP/calls.log')\" = 1 ]"
ok "prompt carries the design-level/bug-hunting-only instruction" "[ \"\$(grep -c 'DESIGN-LEVEL and BUG-HUNTING research ONLY' '$PF')\" = 1 ]"
ok "prompt forbids each mechanical gap kind" "[ \"\$(grep -c 'docstrings, comments, unused imports, missing return/type annotations, or deleting dead stubs/helpers without a callers analysis' '$PF')\" = 1 ]"
ok "prompt has the do-not-repeat header" "[ \"\$(grep -c 'DO NOT REPEAT' '$PF')\" = 1 ]"
ok "open [ready] roadmap feature is listed" "[ \"\$(grep -c '^- Alpha feature title\$' '$PF')\" = 1 ]"
ok "open [needs-research] roadmap feature is listed" "[ \"\$(grep -c '^- Needs research epsilon\$' '$PF')\" = 1 ]"
ok "decomposed feature with an OPEN backlog item is listed (from the backlog group header)" "[ \"\$(grep -c '^- Decomposed feature gamma\$' '$PF')\" = 1 ]"
ok "NEGATIVE: a done roadmap feature is not listed" "[ \"\$(grep -c 'Closed old feature' '$PF')\" = 0 ]"
ok "NEGATIVE: a decomposed feature whose sub-items are all done is not listed" "[ \"\$(grep -c 'Decomposed feature delta' '$PF')\" = 0 ]"
ok "the original quality rules are still in the prompt" "[ \"\$(grep -c 'NEVER propose adding a new standalone helper' '$PF')\" = 1 ]"
ok "the stubs, not the network, served the run (ssh/scp stub log has entries)" "[ \"\$(grep -c 'roadmap/iptv_apps.md' '$BOX/ssh.log')\" -ge 1 ]"
fresh_state; ar_run DRY_RUN=1 OVN_AR_DESIGN_ONLY=off
ok "kill switch OVN_AR_DESIGN_ONLY=off: no design-only paragraph, no do-not-repeat list (old prompt)" "[ \"\$(grep -c -E 'DESIGN-LEVEL|DO NOT REPEAT' '$PF')\" = 0 ] && [ \"\$(grep -c 'NEVER propose adding a new standalone helper' '$PF')\" = 1 ]"
fresh_state; ar_roadmap iptv_apps "- [x] [P1] [done] Only a done feature — app/x.py $META"; rm -f "$BOX/backlog/iptv_apps.md"; ar_run DRY_RUN=1
ok "no open features anywhere: the list says (none) and the pass still runs" "[ \"\$(grep -c '^(none)\$' '$PF')\" = 1 ]"
ar_cleanup; T=""

echo "== validator: mechanical-gap proposals rejected, design proposals accepted =="
vsuite(){   # <validator path> [env...] -> "1|name" / "0|name" lines
  local v="$1"; shift
  local d; d="$(cd "$(mktemp -d)" && pwd -P)"
  : > "$d/existing.md"
  cat > "$d/p.md" <<EOP
- [ ] [P3] [ready] Add docstrings to the public functions in app/services/foo.py — app/services/foo.py has none $META
- [ ] [P3] [ready] Remove unused imports from app/routers/bar.py — app/routers/bar.py imports os and sys and uses neither $META
- [ ] [P3] [ready] Add missing return type annotations in app/core/baz.py — app/core/baz.py helpers return values with no hint $META
- [ ] [P3] [ready] Add comments explaining the retry loop in app/jobs/q.py — app/jobs/q.py is hard to follow $META
- [ ] [P4] [ready] Delete dead stub helpers in app/utils/dead.py — app/utils/dead.py holds a few empty functions $META
- [ ] [P1] [ready] Search endpoint bypasses the parental rating ceiling — app/routers/search.py search() never applies the profile rating filter that browse enforces $META
- [ ] [P4] [ready] Delete dead calculate_backoff_delay helper — app/utils/playback.py has zero callers anywhere in app/ (confirmed via grep -rn) and no test uses it $META
- [ ] [P2] [ready] Handle the IntegrityError race on concurrent favorite adds — app/services/favorites.py add_favorite() should add a savepoint retry because its docstring promises idempotence but a race leaves the second request without a result $META
EOP
  env "$@" python3 "$v" "$d/p.md" "$d/existing.md" 12 > "$d/out.txt" 2> "$d/err.txt"
  local nm; nm="$(grep -c 'mechanical-gap: handled by supply' "$d/err.txt")"
  [ "$nm" = 5 ] && echo "1|5 mechanical-gap proposals rejected with the reason 'mechanical-gap: handled by supply'" || echo "0|5 mechanical-gap proposals rejected with the reason 'mechanical-gap: handled by supply' [got $nm]"
  for t in 'Add docstrings to the public functions' 'Remove unused imports' 'Add missing return type annotations' 'Add comments explaining the retry loop' 'Delete dead stub helpers'; do
    grep -q "mechanical-gap: handled by supply: $t" "$d/err.txt" && echo "1|rejected: $t" || echo "0|rejected: $t"
  done
  [ "$(grep -c '^- \[ \] \[P1\] \[ready\] Search endpoint bypasses' "$d/out.txt")" = 1 ] && echo "1|a real design/bug proposal is accepted" || echo "0|a real design/bug proposal is accepted"
  [ "$(grep -c 'Delete dead calculate_backoff_delay helper' "$d/out.txt")" = 1 ] && echo "1|a dead-code delete WITH a callers analysis (grep, zero callers) is accepted" || echo "0|a dead-code delete WITH a callers analysis (grep, zero callers) is accepted"
  [ "$(grep -c 'Handle the IntegrityError race' "$d/out.txt")" = 1 ] && echo "1|the word 'docstring' in the BODY of a real bug is not a mechanical gap" || echo "0|the word 'docstring' in the BODY of a real bug is not a mechanical gap"
  [ "$(grep -c '^accepted 3/8$' "$d/err.txt")" = 1 ] && echo "1|exactly 3 of 8 accepted" || echo "0|exactly 3 of 8 accepted [$(tail -1 "$d/err.txt")]"
  rm -rf "$d"
}
res="$(vsuite "$VALIDATOR")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOF
$res
EOF
# (review fix) real behaviour/bug titles that the first version of the gate rejected. Each must be ACCEPTED; the pure mechanical ones must still be rejected.
vsuite2(){   # <validator path> -> "1|name" / "0|name" lines
  local v="$1" d t; shift; d="$(cd "$(mktemp -d)" && pwd -P)"
  : > "$d/existing.md"
  : > "$d/p.md"
  while IFS='|' read -r title body; do
    [ -n "$title" ] || continue
    printf -- '- [ ] [P2] [ready] %s — %s %s\n' "$title" "$body" "$META" >> "$d/p.md"
  done <<EOT
Add comments and ratings to channel pages|app/routers/channels.py has no review endpoint and the web channel page has no comment box
Add per-episode comments endpoint|app/routers/episodes.py exposes episodes read-only
Delete empty playlists automatically when last channel removed|app/routers/playlists.py leaves a zero-channel playlist behind
Remove unused refresh tokens on password change|app/services/auth.py keeps old refresh tokens valid after a password reset
Drop unused column from watch_history migration|alembic/versions/0007_watch.py creates a column nothing reads
Remove duplicate import of router causing startup crash|app/main.py imports the router twice
Import cleanup in main.py causes circular import crash|app/main.py imports profiles at module top
Missing type hints in public API cause 500 on /watch|app/routers/watch.py coerces the id wrongly
Remove unused import in app/routers/x.py|the import of os in app/routers/x.py raises ImportError at startup on the Linux image
EOT
  env "$@" python3 "$v" "$d/p.md" "$d/existing.md" 12 > "$d/out.txt" 2> "$d/err.txt"
  for t in 'Add comments and ratings to channel pages' 'Add per-episode comments endpoint' 'Delete empty playlists automatically' 'Remove unused refresh tokens on password change' 'Drop unused column from watch_history migration' 'Remove duplicate import of router causing startup crash' 'Import cleanup in main.py causes circular import crash' 'Missing type hints in public API cause 500 on /watch' 'Remove unused import in app/routers/x.py'; do
    [ "$(grep -c "$t" "$d/out.txt")" = 1 ] && echo "1|real item accepted: $t" || echo "0|real item accepted: $t [$(grep -a 'mechanical' "$d/err.txt" | head -2 | tr '\n' '~')]"
  done
  : > "$d/p2.md"
  while IFS= read -r title; do printf -- '- [ ] [P3] [ready] %s — app/services/foo.py has none %s\n' "$title" "$META" >> "$d/p2.md"; done <<EOT
Add inline comments to the parser in app/services/foo.py
Add docstrings for the helpers in app/services/foo.py
Remove unused imports from app/services/foo.py
Add return type annotations to app/services/foo.py
Remove dead code from app/services/foo.py
Delete unused helper functions in app/services/foo.py
EOT
  env "$@" python3 "$v" "$d/p2.md" "$d/existing.md" 12 > "$d/out2.txt" 2> "$d/err2.txt"
  [ "$(grep -c 'mechanical-gap: handled by supply' "$d/err2.txt")" = 6 ] && echo "1|all 6 pure mechanical titles are still rejected" || echo "0|all 6 pure mechanical titles are still rejected [$(tail -1 "$d/err2.txt")]"
  rm -rf "$d"
}
res="$(vsuite2 "$VALIDATOR")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOF
$res
EOF

# (round-3 review fix) the bug-evidence escape must not be a bypass: a bare 500-599 number (a line number / LOC count), the bare words 'raises', 'fail*', 'startup',
# and 'Cleanup imports' / 'Add comments to the X module' phrasings used to let pure mechanical items through. Each must be REJECTED; concrete symptoms still escape.
vsuite3(){   # <validator path> -> "1|name" / "0|name" lines
  local v="$1" d n; shift; d="$(cd "$(mktemp -d)" && pwd -P)"
  : > "$d/existing.md"; : > "$d/p.md"
  while IFS='|' read -r title body; do
    [ -n "$title" ] || continue
    printf -- '- [ ] [P2] [ready] %s — %s %s\n' "$title" "$body" "$META" >> "$d/p.md"
  done <<EOT
Add missing docstrings to watch router|app/watch.py has 540 lines, get_watch returns 540 items and 12 public functions have no docstring
Remove unused imports from watch router|see app/watch.py:512
Add docstrings to public helpers|app/routers/h.py: each helper documents what it raises
Add docstring to failure handler|app/routers/h.py has no docstring
Cleanup imports in app.py|app/main.py has 3 unused names
Add comments to the watch module|app/watch.py has none
Add docstring to the startup module|app/startup.py has none
EOT
  env "$@" python3 "$v" "$d/p.md" "$d/existing.md" 12 > "$d/out.txt" 2> "$d/err.txt"
  n="$(grep -c 'mechanical-gap: handled by supply' "$d/err.txt")"
  [ "$n" = 7 ] && echo "1|all 7 bypass attempts (line number 512 / 540 lines / 'raises' / 'failure' / 'startup' / Cleanup imports / comments-to-module) are rejected" || echo "0|all 7 bypass attempts (line number 512 / 540 lines / 'raises' / 'failure' / 'startup' / Cleanup imports / comments-to-module) are rejected [rejected $n: $(grep -a accepted "$d/err.txt")]"
  : > "$d/p2.md"
  while IFS='|' read -r title body; do
    printf -- '- [ ] [P2] [ready] %s — %s %s\n' "$title" "$body" "$META" >> "$d/p2.md"
  done <<EOT
Remove unused import in watch router|app/watch.py returns HTTP 503 on /watch
Add type hints to the router|app/watch.py crashes with a traceback on import
Remove unused imports in main|app/main.py fails to start because of a circular import
Add docstrings to the helpers|app/h.py raises an uncaught exception on every request
EOT
  env "$@" python3 "$v" "$d/p2.md" "$d/existing.md" 12 > "$d/out2.txt" 2> "$d/err2.txt"
  [ "$(grep -c . "$d/out2.txt")" = 4 ] && echo "1|concrete failing symptoms (HTTP 503, traceback, circular import, uncaught exception) still escape the gate" || echo "0|concrete failing symptoms (HTTP 503, traceback, circular import, uncaught exception) still escape the gate [$(grep -a 'reject\|accepted' "$d/err2.txt" | tr '\n' '~')]"
  rm -rf "$d"
}
res="$(vsuite3 "$VALIDATOR")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOF
$res
EOF

d="$(cd "$(mktemp -d)" && pwd -P)"; : > "$d/e.md"
printf '%s\n' "- [ ] [P3] [ready] Add docstrings to the public functions in app/services/foo.py — app/services/foo.py has none $META" > "$d/p.md"
OVN_AR_MECHANICAL_REJECT=off python3 "$VALIDATOR" "$d/p.md" "$d/e.md" 12 > "$d/out.txt" 2> "$d/err.txt"
ok "kill switch OVN_AR_MECHANICAL_REJECT=off accepts it" "[ \"\$(grep -c 'Add docstrings' '$d/out.txt')\" = 1 ]"
python3 "$VALIDATOR" "$d/p.md" "$d/e.md" 12 > "$d/out.txt" 2> "$d/err.txt"
ok "NEGATIVE control: with the default setting the same line is rejected" "[ \"\$(grep -c 'Add docstrings' '$d/out.txt')\" = 0 ]"
rm -rf "$d"

echo "== mutation checks: break each rule, the suites above must notice =="
nfail(){ printf '%s\n' "$1" | grep -c '^0|'; }
mv_val(){   # <name> <anchor> <replacement>
  mutate "$VALIDATOR" "$MT/v.py" "$2" "$3"
  local r; r="$(vsuite "$MT/v.py")"
  ok "validator mutant '$1' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
}
mv_val "mechanical title patterns disabled" 'if any(p.search(title) for p in MECH_PATTERNS):' 'if False:'
mv_val "dead-stub delete rule disabled" 'return bool(DEAD_DELETE_RE.search(title) and not CALLER_ANALYSIS_RE.search(title + " " + body))' 'return False'
mv_val "callers-analysis exemption ignored" 'and not CALLER_ANALYSIS_RE.search(title + " " + body))' ')'
mv_val "patterns matched against the BODY too" 'if any(p.search(title) for p in MECH_PATTERNS):' 'if any(p.search(title + " " + body) for p in MECH_PATTERNS):'
mv_val "wrong rejection reason" 'mechanical-gap: handled by supply' 'mechanical'
mutate "$VALIDATOR" "$MT/v.py" 'if os.environ.get("OVN_AR_MECHANICAL_REJECT", "on") == "off":' 'if False:'
d="$(cd "$(mktemp -d)" && pwd -P)"; : > "$d/e.md"
printf '%s\n' "- [ ] [P3] [ready] Add docstrings to the public functions in app/services/foo.py — app/services/foo.py has none $META" > "$d/p.md"
OVN_AR_MECHANICAL_REJECT=off python3 "$MT/v.py" "$d/p.md" "$d/e.md" 12 > "$d/out.txt" 2>/dev/null
ok "validator mutant 'kill switch ignored' is caught" "[ \"\$(grep -c 'Add docstrings' '$d/out.txt')\" = 0 ]"
rm -rf "$d"

mv_val2(){   # <name> <anchor> <replacement>  (review-fix regressions: the OLD over-broad rules must be caught)
  mutate "$VALIDATOR" "$MT/v.py" "$2" "$3"
  local r; r="$(vsuite2 "$MT/v.py")"
  ok "validator mutant '$1' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
}
mv_val2 "bug-evidence escape removed" 'if BUG_TITLE_RE.search(title) or BUG_BODY_RE.search(body):' 'if False:'
mv_val2 "title-only escape (body evidence ignored)" 'if BUG_TITLE_RE.search(title) or BUG_BODY_RE.search(body):' 'if BUG_TITLE_RE.search(title):'
mv_val2 "body-only escape (title consequence words ignored)" 'if BUG_TITLE_RE.search(title) or BUG_BODY_RE.search(body):' 'if BUG_BODY_RE.search(body):'
mv_val2 "bare 'add ... comments' rule is back" 'comments?\s+(explaining|describing|documenting|clarifying)\b", _I),' 'comments?\s+(explaining|describing|documenting|clarifying)\b|\b(add|write)\b[^—]{0,30}\bcomments\b", _I),'
mv_val2 "dead-delete matches any noun after unused/empty" '(?:[\w./-]+\s+){0,3}?(code|stubs?' '(?:[\w./-]+\s+){0,3}?(\w+|code|stubs?'
mv_val2 "mechanical patterns no longer match" 'if any(p.search(title) for p in MECH_PATTERNS):' 'if False:'

mv_val3(){   # <name> <anchor> <replacement>  (round-3: the loose escape words must be caught)
  mutate "$VALIDATOR" "$MT/v.py" "$2" "$3"
  local r; r="$(vsuite3 "$MT/v.py")"
  ok "validator mutant '$1' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
}
mv_val3 "old BUG_BODY_RE (bare 5xx number, bare 'raises')" 'BUG_BODY_RE = re.compile(' 'BUG_BODY_RE = re.compile(r"\b(crash|5\d\d|raises)\b", _I)
_UNUSED = re.compile('
mv_val3 "old BUG_TITLE_RE (bare fail*, 5xx, startup)" 'BUG_TITLE_RE = re.compile(' 'BUG_TITLE_RE = re.compile(r"\b(crash|5\d\d|fail(s|ed|ing|ure)?|startup)\b", _I)
_UNUSED2 = re.compile('
mv_val3 "bare 5xx number accepted in a body" '_HTTP5 = r"(?:50[0-4])"' '_HTTP5 = r"(?:5\d\d)"; BUG_BODY_RE_X = None'
mv_val3 "'Cleanup imports' pattern removed" '|\b(clean\s?up|tidy( up)?)\b[^—]{0,30}\bimports\b' ''
mv_val3 "'comments to the X module' pattern removed" '(to|in|for|on)\s+(the\s+)?[\w./-]*\s*(modules?|files?|functions?|classes|class|helpers?|methods?)\b", _I),' '(to|in|for|on)\s+(the\s+)?[\w./-]*\s*(zzzzzz)\b", _I),'

mv_rr(){   # <name> <anchor> <replacement>
  mutate "$SCRIPT" "$MT/s.sh" "$2" "$3"
  local r; r="$(rr_checks "$MT/s.sh")"; T=""
  ok "round-robin mutant '$1' is caught ($(nfail "$r") check(s) fail)" "[ $(nfail "$r") -ge 1 ]"
}
mv_rr "no sorting" 'rows.sort(key=lambda r: (acc.get(r[0], 0), -float(r[1])))' 'pass'
mv_rr "tie-break prefers the LEAST starving" 'rows.sort(key=lambda r: (acc.get(r[0], 0), -float(r[1])))' 'rows.sort(key=lambda r: (acc.get(r[0], 0), float(r[1])))'
mv_rr "48h window is 4800h" 'time.time() - t <= 48 * 3600' 'time.time() - t <= 4800 * 3600'
mv_rr "zero-accepted passes counted" 'if m and int(m.group(3)) > 0:' 'if m and int(m.group(3)) >= 0:'
mv_rr "legacy is the default order" '"${OVN_AR_ORDER:-roundrobin}"' '"${OVN_AR_ORDER:-legacy}"'
mv_rr "order line not logged" '[ -s "$WORK/order.err" ] && log "$(cat "$WORK/order.err")"' 'true'
mv_rr "pullable filter disabled (the review's major defect)" 'if isinstance(pull, (int, float)) and not isinstance(pull, bool) and pull > pmax:' 'if False:'
mv_rr "lane allowlist disabled" 'if allow and "all" not in allow and r["repo"] not in allow:' 'if False:'
mv_rr "allowlist default empty" '"${OVN_AR_REPOS-iptv_apps xlite}"' '"${OVN_AR_REPOS-}"'
mv_rr "pullable limit ignores OVN_AR_PULLABLE_MAX" '"${OVN_AR_PULLABLE_MAX:-10}"' '10'
mv_rr "bad starving.json crashes with a traceback" 'except (OSError, ValueError):' 'except KeyError:'
mv_rr "exclusions not logged" '[ -s "$WORK/cand.err" ] && while IFS= read -r l; do log "$l"; done < "$WORK/cand.err"' 'true'
mutate "$SCRIPT" "$MT/s.sh" '[ "${OVN_AR_DESIGN_ONLY:-on}" != "off" ]' '[ "${OVN_AR_DESIGN_ONLY:-on}" = "never" ]'
ar_setup "$MT/s.sh" "$VALIDATOR"; seed_roadmaps; fresh_state; ar_starving iptv_apps:5; ar_run DRY_RUN=1
ok "prompt mutant 'design-only paragraph never added' is caught" "[ \"\$(grep -c 'DESIGN-LEVEL' '$CAP/prompt_iptv_apps.txt')\" = 0 ]"
ar_cleanup; T=""
mutate "$SCRIPT" "$MT/s.sh" 'DO NOT REPEAT - these features are already OPEN' 'ALREADY OPEN'
ar_setup "$MT/s.sh" "$VALIDATOR"; seed_roadmaps; fresh_state; ar_starving iptv_apps:5; ar_run DRY_RUN=1
ok "prompt mutant 'do-not-repeat header renamed' is caught" "[ \"\$(grep -c 'DO NOT REPEAT' '$CAP/prompt_iptv_apps.txt')\" = 0 ]"
ar_cleanup; T=""

echo
echo "auto research round-robin: $P passed, $F failed"
[ "$F" = 0 ]
