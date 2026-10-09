#!/usr/bin/env bash
# Regression test: scripts/lib_parked_pattern.sh + its use in lib_item_select.sh (spec-compiler-v2 A1, 2026-10-09).
# Defect: `grep -viE '...|BLOCKED|...'` parked every progress line that merely contained the lowercase word blocked/unblocked/blocked_reason (all 10 open iptv_apps
# items and both open xlite items). BLOCKED is a TAG: matched case-sensitively; the other tags stay case-insensitive.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_parked_pattern.sh" ] || { echo "  SKIP: lib_parked_pattern.sh not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (under pipefail `A | grep -q X` is flaky: grep -q exits at its first hit and A may take SIGPIPE)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# shellcheck disable=SC1091
. "$LIBDIR/lib_parked_pattern.sh"
ok "CI pattern is the documented one" "[ \"\$OVN_PARKED_CI_ERE\" = 'AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|\\[CLAUDE\\]' ]"
ok "CS pattern is BLOCKED" "[ \"\$OVN_PARKED_CS_ERE\" = 'BLOCKED' ]"

cat > "$tmp/lines.md" <<'EOT'
- [ ] [T2] a.py — plain item one
- [ ] [T2] b.py — test_x_blocked and unblocked flows, blocked_reason field
- [ ] [T2] c.py — BLOCKED ITEM: file is read-only
- [ ] [T2] [AUTO-SKIP after 4 cycles] d.py — x
- [ ] [T2] [auto-skip lowercase] d2.py — x
- [ ] [T2] [HUMAN-ONLY] e.py — x
- [ ] [T3] [human/design] f.py — x
- [ ] [T2] g.py — route to [CLAUDE] queue
- [ ] [T2] h.py — HARD FILE BAN applies
- [ ] [T2] i.py — plain item two
EOT
# eligible = lines surviving both greps
elig(){ grep -viE "$OVN_PARKED_CI_ERE" "$1" | grep -vE "$OVN_PARKED_CS_ERE"; }
n_elig="$(elig "$tmp/lines.md" | grep -c . || true)"
ok "survivors: a.py, b.py (lowercase blocked), i.py = 3" "[ \"$n_elig\" = 3 ]"
ok "the lowercase-'blocked' line survives" "elig '$tmp/lines.md' | grep -c 'b.py' | grep -qx 1"
ok "BLOCKED ITEM is still parked" "[ \"\$(elig '$tmp/lines.md' | grep -c 'c.py')\" = 0 ]"
ok "AUTO-SKIP (either case), HUMAN-ONLY, human/, [CLAUDE], HARD FILE BAN all parked" "[ \"\$(elig '$tmp/lines.md' | grep -cE 'd.py|d2.py|e.py|f.py|g.py|h.py')\" = 0 ]"
# the OLD pipeline on the same file, to prove the fixture really exercises the defect
old_elig="$(grep -viE 'AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|BLOCKED|\[CLAUDE\]' "$tmp/lines.md" | grep -c . || true)"
ok "control: the old case-insensitive pipeline kept only 2 (it parked b.py)" "[ '$old_elig' = 2 ]"
# mutation: a case-insensitive CS pattern must change the answer, i.e. this test would catch a regression to the old behaviour
mut_n="$( OVN_PARKED_CS_ERE='[Bb][Ll][Oo][Cc][Kk][Ee][Dd]'; grep -viE "$OVN_PARKED_CI_ERE" "$tmp/lines.md" | grep -vE "$OVN_PARKED_CS_ERE" | grep -c . || true)"
ok "MUTATION (case-insensitive CS pattern): survivors drop to 2, the assertion above would fail" "[ '$mut_n' = 2 ]"

# ---- lib_item_select.sh really uses it: ovn_resolve_top_item / ovn_open_bug_count
mkdir -p "$tmp/repo"
resolve_top(){  # $1=lib dir  $2=repo dir
  ( set +u; . "$1/lib_item_select.sh"; ovn_resolve_top_item "$2" "" )
}
cat > "$tmp/repo/OVERNIGHT_PROGRESS.md" <<'EOT'
# progress
- [ ] [T2] c.py — BLOCKED ITEM: the file is read-only
- [ ] [T2] [AUTO-SKIP after 4 cycles] d.py — parked
- [ ] [T3] [human/design] f.py — parked
- [ ] [T2] b.py — enforce test_unlicensed_import_blocked for blocked_categories
- [ ] [T2] i.py — later item
EOT
top="$(resolve_top "$LIBDIR" "$tmp/repo")"
ok "top item skips the parked tags and returns the lowercase-'blocked' item (line 5)" "[ \"\${top%%:*}\" = 5 ] && printf '%s' '$top' | grep -c 'b.py' | grep -qx 1"
# the same through a copy of lib_item_select.sh with NO lib_parked_pattern.sh beside it: the inline fallback has identical values
mkdir -p "$tmp/solo"; cp "$LIBDIR/lib_item_select.sh" "$tmp/solo/"
top2="$(resolve_top "$tmp/solo" "$tmp/repo")"
ok "inline fallback (library missing): same answer" "[ \"\$top2\" = \"\$top\" ]"
# mutation on the library copy: a case-insensitive CS pattern makes the top item i.py (b.py is parked again)
mkdir -p "$tmp/mut"; cp "$LIBDIR/lib_item_select.sh" "$tmp/mut/"
printf "OVN_PARKED_CI_ERE='AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|\\\\[CLAUDE\\\\]'\nOVN_PARKED_CS_ERE='[Bb][Ll][Oo][Cc][Kk][Ee][Dd]'\n" > "$tmp/mut/lib_parked_pattern.sh"
top3="$(resolve_top "$tmp/mut" "$tmp/repo")"
ok "MUTATION (case-insensitive CS in the library): top item becomes i.py (line 6)" "[ \"\${top3%%:*}\" = 6 ]"

# kill switch OVN_PARKED_BLOCKED_CI=on restores the legacy case-insensitive BLOCKED (library and fallback both), and a failing `[ cond ] && x` must not leak a non-zero status to a `set -e` caller
cat > "$tmp/repo/OVERNIGHT_PROGRESS.md" <<'EOT'
# progress
- [ ] [T2] b.py — enforce test_unlicensed_import_blocked for blocked_categories
- [ ] [T2] i.py — later item
EOT
topk="$(OVN_PARKED_BLOCKED_CI=on resolve_top "$LIBDIR" "$tmp/repo")"
ok "kill switch (library): the lowercase-'blocked' line is parked again, top item is i.py (line 3)" "[ \"\${topk%%:*}\" = 3 ]"
topk2="$(OVN_PARKED_BLOCKED_CI=on resolve_top "$tmp/solo" "$tmp/repo")"
ok "kill switch (inline fallback): same" "[ \"\${topk2%%:*}\" = 3 ]"
ok "switch off (default): the lowercase-'blocked' line is the top item (line 2)" "[ \"\$(resolve_top '$LIBDIR' '$tmp/repo' | cut -d: -f1)\" = 2 ]"
ok "sourcing lib_parked_pattern.sh returns 0 under 'set -e' with the switch off" "( set -e; . '$LIBDIR/lib_parked_pattern.sh'; echo reached ) | grep -c reached | grep -qx 1"

cat > "$tmp/repo/OVERNIGHT_PROGRESS.md" <<'EOT'
- [ ] [T2] bug one blocked by nothing. Manual-test bug (reported by Mark) src:manual [feat:iptv_apps-20261009-manual-0123abcd]
- [ ] [T2] bug two. BLOCKED ITEM Manual-test bug (reported by Mark) src:manual [feat:iptv_apps-20261009-manual-0123abce]
- [ ] [T2] bug three. [AUTO-SKIP x] Manual-test bug (reported by Mark) src:manual [feat:iptv_apps-20261009-manual-0123abcf]
EOT
cnt="$( set +u; . "$LIBDIR/lib_item_select.sh"; ovn_open_bug_count "$tmp/repo" )"
ok "open-bug count: the lowercase-'blocked' bug counts, BLOCKED ITEM and AUTO-SKIP bugs do not (1)" "[ '$cnt' = 1 ]"

# ---- the two `$body | grep -q` sites in ovn_log_has_api_error are pipe-free (a big log + early match under pipefail used to risk SIGPIPE -> false 'no match')
ok "static: no '\"\$body\" | grep -q' (printf-into-grep -q on a log) left in lib_item_select.sh" "[ \"\$(grep -cF '\"\$body\" | grep -q' '$LIBDIR/lib_item_select.sh')\" = 0 ]"
{ echo "litellm.RateLimitError: boom"; yes 'filler line that is long enough to fill pipe buffers quickly and make an early exit matter' | head -c 3000000; } > "$tmp/big.log"
fails=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  ( set -o pipefail; set +u; . "$LIBDIR/lib_item_select.sh"; ovn_log_has_api_error "$tmp/big.log" ) || fails=$((fails+1))
done
ok "ovn_log_has_api_error on a 3MB log with an early match: true 10/10 under pipefail" "[ '$fails' = 0 ]"
printf 'all fine\n' > "$tmp/clean.log"
ok "NEGATIVE: a clean log is not an API error" "! ( set +u; . '$LIBDIR/lib_item_select.sh'; ovn_log_has_api_error '$tmp/clean.log' )"

echo; echo "parked pattern: $P passed, $F failed"
[ "$F" = 0 ]
