#!/usr/bin/env bash
# Tests for scripts/ovn_landed_detail.py (2026-09-20) — per-landed-item "what actually
# landed" lines added to the ntfy digests (digest_notify.sh 3h + work_summary.py 24h).
# Reads state/task_stats.log (the same file ovn_stats.py already reads) against a
# fixture $HOME so it never touches production data.
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
SCRIPT="$SCRIPTS/ovn_landed_detail.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP: $SCRIPT not found on this host"
  echo "ovn_landed_detail.py: 0 passed, 0 failed"
  exit 0
fi

tmp="$(mktemp -d)"; export HOME="$tmp"; mkdir -p "$HOME/overnight-queue/state"
TSF="$HOME/overnight-queue/state/task_stats.log"
now="$(date +%s)"

# --- 1: empty/missing file prints nothing ---
out0="$(python3 "$SCRIPT" 3 2>&1)"
ok "missing task_stats.log: prints nothing" "[ -z \"\$out0\" ]"

# --- 2: a real landed row is shown, tier prefix is NOT doubled (no 'TT2') ---
cat > "$TSF" <<TSEOF
$now	billwatch	pass	{py·other·T2·test-covered}	billwatch-backend/app/services/trending_service.py
TSEOF
out1="$(python3 "$SCRIPT" 3 2>&1)"
ok "shows the header"                          "printf '%s' \"\$out1\" | grep -q 'Landed detail'"
ok "shows repo + tier + category + file"        "printf '%s' \"\$out1\" | grep -q 'billwatch (T2·other): billwatch-backend/app/services/trending_service.py'"
ok "tier is NOT double-prefixed (no TT2)"        "! printf '%s' \"\$out1\" | grep -q 'TT2'"

# --- 3: non-'pass' outcomes (noop/revert/fail/skip) are excluded ---
cat > "$TSF" <<TSEOF
$now	billwatch	noop:done	{py·other·T2·test-covered}	should-not-appear-noop.py
$now	billwatch	revert	{py·other·T2·test-covered}	should-not-appear-revert.py
$now	billwatch	fail	{py·other·T2·test-covered}	should-not-appear-fail.py
$now	billwatch	skip	{py·other·T2·test-covered}	should-not-appear-skip.py
TSEOF
out2="$(python3 "$SCRIPT" 3 2>&1)"
ok "non-'pass' outcomes are excluded entirely (prints nothing)" "[ -z \"\$out2\" ]"

# --- 4: rows outside the window are excluded ---
old_ts=$(( now - 30 * 3600 ))   # 30h ago, outside a 3h window
cat > "$TSF" <<TSEOF
$old_ts	billwatch	pass	{py·other·T2·test-covered}	old-file-outside-window.py
TSEOF
out3="$(python3 "$SCRIPT" 3 2>&1)"
ok "a row older than the window is excluded" "[ -z \"\$out3\" ]"
out3b="$(python3 "$SCRIPT" 48 2>&1)"
ok "the SAME row appears once the window is widened past it" "printf '%s' \"\$out3b\" | grep -q 'old-file-outside-window.py'"

# --- 5: --max-per-repo caps per-repo lines, keeping the MOST RECENT ones ---
: > "$TSF"
for i in 1 2 3 4 5; do
  ts=$(( now - i ))
  echo -e "$ts\tgitlark\tpass\t{py·other·T2·test-covered}\tfile-$i.py" >> "$TSF"
done
out4="$(python3 "$SCRIPT" 3 --max-per-repo 2 --max-total 20 2>&1)"
n4="$(printf '%s' "$out4" | grep -c 'gitlark')"
ok "max-per-repo caps a single repo's lines to 2" "[ \"$n4\" -eq 2 ]"
ok "keeps the most recent (file-1.py, smallest ts-delta), not the oldest" "printf '%s' \"\$out4\" | grep -q 'file-1.py'"
ok "does not keep the oldest of the 5 (file-5.py)" "! printf '%s' \"\$out4\" | grep -q 'file-5.py'"

# --- 6: --max-total caps the OVERALL line count across repos ---
: > "$TSF"
for r in repo-a repo-b repo-c; do
  echo -e "$now\t$r\tpass\t{py·other·T2·test-covered}\tf.py" >> "$TSF"
done
out5="$(python3 "$SCRIPT" 3 --max-per-repo 5 --max-total 2 2>&1)"
n5="$(printf '%s' "$out5" | grep -c '(T2')"
ok "max-total caps the overall item count to 2 even with 3 repos active" "[ \"$n5\" -eq 2 ]"

# --- 7: a malformed/missing tag falls back to '?' instead of crashing ---
: > "$TSF"
echo -e "$now\tbillwatch\tpass\tnotatag\tfile.py" >> "$TSF"
out6="$(python3 "$SCRIPT" 3 2>&1)"
ok "malformed tag doesn't crash, falls back to '?'" "printf '%s' \"\$out6\" | grep -q 'billwatch (?·?): file.py'"

# --- 8: a long file path is truncated from the LEFT (keeps the meaningful tail) ---
: > "$TSF"
longpath="a/very/deeply/nested/directory/structure/that/is/way/too/long/to/show/in/full/on/a/phone/notification/service.py"
echo -e "$now\tbillwatch\tpass\t{py·other·T2·test-covered}\t$longpath" >> "$TSF"
out7="$(python3 "$SCRIPT" 3 --max-len 40 2>&1)"
ok "long path is truncated"                    "! printf '%s' \"\$out7\" | grep -q '$longpath'"
ok "truncated path keeps the filename tail"    "printf '%s' \"\$out7\" | grep -q 'service.py'"

# --- 9: a landed file belonging to a real [feat:] group shows feature attribution
# (2026-09-20) — "repo (T2, feature: "Title"): file" instead of "repo (T2·cat): file" —
# by asking scripts/ovn_feature_groups.py which group contains this repo+file, then
# resolving the human title from roadmap/<repo>.md.
mkdir -p "$HOME/overnight-queue/repos/billwatch" "$HOME/overnight-queue/roadmap"
cat > "$HOME/overnight-queue/repos/billwatch/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `billwatch-backend/app/services/trending_service.py` — cache trends. VERIFY: x. (cat:python; multifile:no) [feat:billwatch-20260101-bill-caching-done-c-1]
- [ ] [T2] `billwatch-backend/app/services/other.py` — more. VERIFY: x. (cat:python; multifile:no) [feat:billwatch-20260101-bill-caching-done-c-1]
EOF
: > "$HOME/overnight-queue/repos/billwatch/OVERNIGHT_DONE.md"
cat > "$HOME/overnight-queue/roadmap/billwatch.md" <<'EOF'
- [ ] [P2] [decomposed] Bill Caching — done. {c:1}
EOF
: > "$TSF"
echo -e "$now\tbillwatch\tpass\t{py·other·T2·test-covered}\tbillwatch-backend/app/services/trending_service.py" >> "$TSF"
out8="$(python3 "$SCRIPT" 3 2>&1)"
ok "a feat-tagged landed item shows its human-readable feature title" \
  "printf '%s' \"\$out8\" | grep -q 'billwatch (T2, feature: \"Bill Caching\"): billwatch-backend/app/services/trending_service.py'"

# an item with NO [feat:] tag keeps the original file-only format unchanged
: > "$HOME/overnight-queue/repos/billwatch/OVERNIGHT_PROGRESS.md"
: > "$TSF"
echo -e "$now\tbillwatch\tpass\t{py·other·T2·test-covered}\tbillwatch-backend/app/services/untagged.py" >> "$TSF"
out9="$(python3 "$SCRIPT" 3 2>&1)"
ok "an untagged item falls back to the plain (tier·category) format, no fabricated feature" \
  "printf '%s' \"\$out9\" | grep -q 'billwatch (T2·other): billwatch-backend/app/services/untagged.py'"

rm -rf "$tmp"
echo "ovn_landed_detail.py: $P passed, $F failed"
[ "$F" -eq 0 ]
